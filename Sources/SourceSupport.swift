import Foundation
import Darwin
import SQLite3

/// 여러 출처가 함께 쓰는 도구.
///
/// Claude Code CLI 는 자기 상태를 레지스트리에 적어 두므로 이 도구가 필요 없다.
/// 그러나 codex 와 Claude 앱은 **아무것도 적지 않아서**, 살아있는 프로세스를 우리가
/// 직접 찾아 붙이고 기록 끝을 읽어 상태를 추정해야 한다. 그 공통분모가 여기 있다.

// MARK: - 살아있는 프로세스 표

/// 한 번 훑어 두고 여러 세션이 나눠 쓰는 프로세스 표.
///
/// 세션마다 전체 프로세스를 다시 훑으면 갱신 주기마다 수백 번씩 커널을 두드리게 된다.
struct LiveProcessTable {

    struct Entry {
        let pid: Int32
        let ppid: Int32
        let cwd: String
        let startedAt: Date
    }

    let entries: [Entry]

    /// 같은 사용자로 도는 프로세스만 담긴다. 남의 계정 것은 cwd 를 읽을 수 없어 저절로 빠진다.
    init() {
        entries = MetricsSampler.allProcesses().compactMap { row in
            guard let cwd = Self.workingDirectory(pid: row.pid),
                  let started = Self.startTime(pid: row.pid) else { return nil }
            return Entry(pid: row.pid, ppid: row.ppid, cwd: cwd, startedAt: started)
        }
    }

    /// 이 작업 폴더에서 도는 세션의 pid.
    ///
    /// **실행 파일 이름으로 거르지 않는다.** 설치 방식마다 이름이 달라져서, 이름으로 거르면
    /// 남의 환경에서 멀쩡한 세션이 통째로 사라진다 (`ClaudeCodeSource.isAlive` 가 같은 이유로
    /// 이름을 안 쓴다).
    ///
    /// 대신 작업 폴더로 후보를 모은 뒤 **그 무리의 조상**을 고른다. 세션이 띄운 도우미들
    /// (MCP 플러그인 · 언어 서버 등)은 작업 폴더를 물려받고 세션보다 **늦게** 뜨므로,
    /// 시작 순서로 고르면 도우미를 집는다 — 실제로 codex 를 재보니 후보 다섯 중 가장 늦은 것이
    /// 플러그인 노드 프로세스였다. 부모가 후보 안에 없는 것이 세션 그 자신이다.
    ///
    /// `startedNear` 를 주면 그 시각 언저리에 뜬 것만 본다. 여러 세션이 같은 폴더를 쓰는
    /// 경우(터미널의 셸과 codex 처럼)를 가르는 데 쓴다.
    func session(inDirectory cwd: String,
                 excluding used: Set<Int32>,
                 startedNear reference: Date? = nil,
                 within window: TimeInterval = 120) -> Int32? {
        let candidates = entries.filter { entry in
            guard !used.contains(entry.pid), entry.cwd == cwd else { return false }
            guard let reference else { return true }
            return abs(entry.startedAt.timeIntervalSince(reference)) < window
        }
        guard !candidates.isEmpty else { return nil }

        let pids = Set(candidates.map(\.pid))
        let roots = candidates.filter { !pids.contains($0.ppid) }
        // 조상을 못 가리면(서로 부모가 아님) 가장 먼저 뜬 것을 쓴다.
        return (roots.isEmpty ? candidates : roots).min { $0.startedAt < $1.startedAt }?.pid
    }

    // MARK: 커널에서 읽기

    static func workingDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let rc = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, size)
        }
        guard rc == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    static func startTime(pid: Int32) -> Date? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let rc = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, $0, size)
        }
        guard rc == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbsd.pbi_start_tvsec)
                                         + Double(info.pbsd.pbi_start_tvusec) / 1_000_000)
    }
}

// MARK: - 기록 읽기

enum Transcript {

    /// 기록은 수십 MB 까지 커진다. 끝에서 이만큼만 되감아 읽는다.
    static let defaultTailBytes = 64 * 1024

    /// 파일 끝에서 `bytes` 만큼만 읽는다. 앞은 건드리지 않는다.
    static func tail(of url: URL, bytes: Int = defaultTailBytes) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        // 처음 한 줄은 잘려 있을 수 있으므로 버린다.
        if offset > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }

    /// cwd 를 `~/.claude/projects` 아래의 폴더 이름으로 바꾼다.
    /// 영숫자가 아닌 글자는 전부 `-` 가 된다 (`/Users/a/My Docs/x_y` → `-Users-a-My-Docs-x-y`).
    static func projectSlug(for cwd: String) -> String {
        String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    static func parseISO(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

// MARK: - codex 스레드 이름

enum CodexThreads {

    /// codex 가 스레드에 붙여 둔 이름. `<id> → 제목`.
    ///
    /// `state_5.sqlite` 를 **읽기 전용**으로 열어 훑는다. 못 읽으면 빈 표를 돌려준다 —
    /// 이름은 보기 좋으라고 있는 것이지 세션의 뼈대가 아니므로, 실패해도 부르는 쪽이
    /// 원래 쓰던 이름(작업 폴더)으로 돌아가면 그만이다. 세션이 사라지지는 않는다.
    static func titles(codexHome: URL) -> [String: String] {
        let path = codexHome.appendingPathComponent("state_5.sqlite").path
        guard FileManager.default.fileExists(atPath: path) else { return [:] }

        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?mode=ro", &db,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return [:]
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, COALESCE(NULLIF(name, ''), NULLIF(title, ''), '') FROM threads
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var out: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = sqlite3_column_text(stmt, 0),
                  let name = sqlite3_column_text(stmt, 1) else { continue }
            let title = String(cString: name)
            if !title.isEmpty { out[String(cString: id)] = title }
        }
        return out
    }
}

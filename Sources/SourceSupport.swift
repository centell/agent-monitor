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

    /// 프로세스가 **어느 폴더에서 도는지**를 pid 마다 기억해 둔다.
    ///
    /// 이 표를 짓는 값의 거의 전부가 폴더를 묻는 `proc_pidinfo(PROC_PIDVNODEPATHINFO)` 다.
    /// 커널이 경로를 되짚어 채워 주는 호출이라 비싼데, **맥의 모든 프로세스마다** 물어야
    /// 한다 (실측: 581개가 도는 맥에서 갱신 주기마다 그만큼). 그런데 프로세스가 사는 동안
    /// 제 폴더는 거의 바뀌지 않으므로, 한 번 물은 답은 들고 있는다.
    ///
    /// **번호가 되돌아오는 것**만 조심하면 된다. pid 는 돌려 쓰이므로 죽은 프로세스의
    /// 폴더를 엉뚱한 새 프로세스에 물릴 수 있다. 시작 시각이 그걸 가른다 — 번호가 같아도
    /// 시각이 다르면 남이다. 그 시각은 `allProcesses()` 가 이미 들고 온 것이라 공짜다.
    private static let cacheLock = NSLock()
    private static var cachedDirectories: [Int32: (started: Date, cwd: String)] = [:]

    /// 같은 사용자로 도는 프로세스만 담긴다. 남의 계정 것은 cwd 를 읽을 수 없어 저절로 빠진다.
    init() {
        let rows = MetricsSampler.allProcesses()

        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }

        var fresh: [Int32: (started: Date, cwd: String)] = [:]
        fresh.reserveCapacity(rows.count)
        var out: [Entry] = []
        out.reserveCapacity(rows.count)

        for row in rows {
            let remembered = Self.cachedDirectories[row.pid]
            let cwd = (remembered?.started == row.started ? remembered?.cwd : nil)
                ?? Self.workingDirectory(pid: row.pid)
            guard let cwd else { continue }
            fresh[row.pid] = (row.started, cwd)
            out.append(Entry(pid: row.pid, ppid: row.ppid, cwd: cwd, startedAt: row.started))
        }

        // 이번 훑기에 없던 pid 는 버린다. 죽은 프로세스의 자리가 쌓이지 않고, 번호가
        // 돌아왔을 때 남의 폴더를 물려줄 여지도 남지 않는다.
        Self.cachedDirectories = fresh
        entries = out
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

    // MARK: 왜 기다리는가

    /// 도구 호출을 한 줄로 줄인다 — `Bash: pnpm build`.
    ///
    /// 이름만으로는 부족하다. `Bash` 는 빌드일 수도 있고 지우는 것일 수도 있어서,
    /// 결국 창으로 넘어가 봐야 안다. 그 왕복을 없애는 것이 이 값의 목적이므로
    /// 도구마다 «무엇을 하려는지» 가 담긴 칸을 하나씩 집는다.
    ///
    /// 모르는 도구는 이름만 적는다. 아무 칸이나 집어 엉뚱한 것을 보이느니
    /// 덜 말하는 편이 낫다 — 틀린 한 줄은 없느니만 못하다.
    static func callSummary(name: String, input: [String: Any]?) -> String {
        guard let argument = argument(ofTool: name, input: input) else { return name }
        return "\(name): \(argument)"
    }

    private static func argument(ofTool name: String, input: [String: Any]?) -> String? {
        guard let input else { return nil }
        func value(_ key: String) -> String? {
            guard let raw = input[key] as? String else { return nil }
            let text = plain(oneLine(raw))
            return text.isEmpty ? nil : text
        }
        switch name {
        case "Bash", "BashOutput", "KillShell":
            return value("command") ?? value("description")
        case "Read", "Write", "Edit", "MultiEdit", "NotebookEdit":
            return value("file_path").map { ($0 as NSString).lastPathComponent }
        case "Glob", "Grep":
            return value("pattern")
        case "WebFetch":
            return value("url")
        case "WebSearch":
            return value("query")
        case "Task", "Agent":
            return value("description")
        case "Skill":
            return value("skill")
        default:
            return nil
        }
    }

    /// 마지막 텍스트 블록에서 사람에게 건넨 **마지막 줄**을 집는다.
    ///
    /// 첫 줄이 아니라 마지막 줄인 이유: 첫 줄은 머리말이거나 제목일 때가 많고
    /// (「## 작업 완료」), 정작 사람이 답해야 할 것은 끝에 온다 (「커밋할까요?」).
    static func closingLine(inContent blocks: [[String: Any]]) -> String? {
        for block in blocks.reversed() where block["type"] as? String == "text" {
            guard let raw = block["text"] as? String else { continue }
            let lines = raw.split(whereSeparator: \.isNewline)
                .map { plain(oneLine(String($0))) }
                .filter { !$0.isEmpty }
            if let last = lines.last { return last }
        }
        return nil
    }

    /// 여러 줄을 한 줄로 눌러 담는다.
    ///
    /// 줄바꿈이 하나라도 남으면 목록의 줄 수가 세션마다 달라져 배치가 무너진다.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isNewline || $0 == "\t" || $0 == " " })
            .joined(separator: " ")
    }

    /// 마크다운 장식을 걷어낸다.
    ///
    /// 목록은 고정폭 글자만 그리므로 `**` 는 굵게 보이지 않고 칸만 잡아먹는다.
    private static func plain(_ line: String) -> String {
        var out = line.replacingOccurrences(of: "**", with: "")
                      .replacingOccurrences(of: "`", with: "")
        // 줄머리 장식(제목·목록표)을 떼어낸다. 한 겹씩 벗기므로 `- **x**` 도 벗겨진다.
        while let first = out.first, "#-*>•".contains(first) {
            out = String(out.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return out.trimmingCharacters(in: .whitespaces)
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

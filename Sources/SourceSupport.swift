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

    /// Claude 기록 한 줄의 `message.model`. 지어낸 줄이면 없다.
    ///
    /// API 가 실패하면 Claude Code 가 오류를 assistant 줄로 적는데, 그 줄의 모델은
    /// `<synthetic>` 이다. 그걸 받으면 오류 한 번에 모델 이름이 그 글자로 바뀐다.
    static func claudeModel(in message: [String: Any]?) -> String? {
        guard let raw = message?["model"] as? String,
              !raw.isEmpty, !raw.hasPrefix("<") else { return nil }
        return raw
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
        column("COALESCE(NULLIF(name, ''), NULLIF(title, ''), '')", codexHome: codexHome)
    }

    /// codex 가 스레드에 적어 둔 모델. `<id> → gpt-6.1-sol`.
    ///
    /// rollout 꼬리에서 못 찾았을 때의 받침이다. 모델은 턴이 **시작할 때** 한 번 적히므로
    /// (`turn_context`) 출력이 64KB 를 넘긴 긴 턴에서는 꼬리 밖으로 밀려난다.
    ///
    /// 이름과 **따로 묻는다.** 한 문장으로 물으면 codex 가 판을 올려 `model` 열이
    /// 사라지는 날 `prepare` 가 실패해 이름까지 함께 잃는다. 모델은 곁들이다.
    static func models(codexHome: URL) -> [String: String] {
        column("COALESCE(model, '')", codexHome: codexHome)
    }

    /// `threads` 의 열 하나를 `id → 값` 표로 읽는다. 빈 값은 담지 않는다.
    private static func column(_ expression: String, codexHome: URL) -> [String: String] {
        let path = codexHome.appendingPathComponent("state_5.sqlite").path
        guard FileManager.default.fileExists(atPath: path) else { return [:] }

        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?mode=ro", &db,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return [:]
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT id, \(expression) FROM threads"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var out: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = sqlite3_column_text(stmt, 0),
                  let raw = sqlite3_column_text(stmt, 1) else { continue }
            let value = String(cString: raw)
            if !value.isEmpty { out[String(cString: id)] = value }
        }
        return out
    }
}

// MARK: - 모델 이름

enum ModelName {
    /// 목록에 적을 짧은 모델 이름.
    ///
    /// `claude-opus-5-5` → `opus-5.5`. 앞의 `claude-` 는 이름 앞 자리의 색이 이미 말하고,
    /// 뒤의 날짜(`-20260101`)는 같은 모델의 판이라 목록에서 가를 일이 없다.
    /// 판 번호의 `-` 를 `.` 로 바꾸는 것은 사람이 그렇게 부르기 때문이다.
    ///
    /// **모르는 모양은 손대지 않는다** (`gpt-6.1-sol` 은 그대로). 규칙에 억지로 맞추면
    /// 다른 두 모델이 같은 이름으로 접힐 수 있고, 그건 길게 적는 것보다 나쁘다.
    static func short(_ raw: String) -> String {
        var name = raw
        // `[1m]` 같은 꼬리표는 컨텍스트 창 표시이지 모델이 아니다.
        if let bracket = name.firstIndex(of: "[") { name = String(name[..<bracket]) }
        guard name.hasPrefix("claude-") else { return name }
        name.removeFirst("claude-".count)

        var parts = name.split(separator: "-").map(String.init)
        // 날짜 꼬리 (여덟 자리 숫자).
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        // 이름 뒤에 숫자 둘이 오면 판 번호다 (`opus-5-5` → `opus-5.5`).
        if parts.count == 3, !parts[0].allSatisfy(\.isNumber),
           parts[1].allSatisfy(\.isNumber), parts[2].allSatisfy(\.isNumber) {
            return "\(parts[0])-\(parts[1]).\(parts[2])"
        }
        return parts.joined(separator: "-")
    }
}

// MARK: - 꼬리 밖의 모델

/// 꼬리(64KB)에서 모델을 못 찾았을 때 더 거슬러 올라가 찾는다.
///
/// **꼬리가 첨부 줄로 가득 찬 세션이 실제로 있다** (실측 2026-11-11: 열한 세션 중 넷,
/// 마지막 64KB 가 전부 `attachment` 줄). 그런 세션은 지금 한창 쓰이는 세션이라, 거기서
/// 모델이 빠지면 켜 둔 표시가 가장 필요한 줄에서 `claude/` 로 돌아간다.
///
/// 비싸지 않게 두 가지를 지킨다.
/// · 끝에서부터 덩어리로 읽고 **찾으면 멈춘다.** 상한을 넘으면 그만 찾는다 — 모름은 모름이다.
/// · 지난번에 찾은 자리를 기억한다. 파일이 자랐으면 **새로 붙은 쪽만** 보고, 거기 없으면
///   지난 답을 쓴다. 새 턴이 오면 새 줄이 붙으니 대개 첫 덩어리에서 끝난다.
final class ClaudeModelFinder {
    static let shared = ClaudeModelFinder()

    private struct Entry { let size: UInt64; let model: String?; var touched: Date }
    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    private static let chunk: UInt64 = 256 * 1024
    private static let limit: UInt64 = 8 * 1024 * 1024
    private static let needle = Data("\"model\"".utf8)

    func lastModel(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }

        lock.lock()
        let cached = entries[url.path]
        lock.unlock()
        if let cached, cached.size == size { return remember(url, size, cached.model) }

        // 지난번 크기보다 앞은 이미 본 곳이다. 거기서 멈추고 지난 답을 쓴다.
        let floor = cached.map { $0.size < size ? $0.size : 0 } ?? 0
        var end = size
        var carry = Data()              // 덩어리 경계에서 잘린 줄의 뒷부분
        while end > floor {
            // 상한을 넘었다. 지난 답으로 내려가지 않는다 — 안 본 자리에 더 새 줄이 있을 수
            // 있으므로 그 답은 낡았을 수 있다. 모름으로 둔다.
            guard size - end < Self.limit else { return remember(url, size, nil) }
            let start = max(floor, end >= Self.chunk ? end - Self.chunk : 0)
            try? handle.seek(toOffset: start)
            guard var data = try? handle.read(upToCount: Int(end - start)) else { break }
            data.append(carry)
            // 덩어리의 맨 앞이 줄의 처음인가. 파일 맨 앞이거나 바로 앞 바이트가 줄바꿈이면
            // 온전한 줄이다. 지난번 끝(`floor`)에서 이어 읽을 때가 대개 그렇다 — 그 줄을
            // 잘린 것으로 치고 넘기면 새로 붙은 첫 줄을 통째로 못 본다.
            let whole = start == 0 || byte(before: start, in: handle) == UInt8(ascii: "\n")
            var body = data
            if whole {
                carry = Data()
            } else if let nl = data.firstIndex(of: UInt8(ascii: "\n")) {
                carry = data[data.startIndex..<nl]
                body = data[data.index(after: nl)...]
            } else {
                // 덩어리보다 긴 한 줄의 가운데다. 다음 덩어리와 이어 붙여야 읽힌다.
                carry = data
                body = Data()
            }
            if let model = Self.lastMainModel(in: body) { return remember(url, size, model) }
            end = start
        }
        // 새로 붙은 쪽에 없었으면 지난 답이 여전히 지금 모델이다.
        return remember(url, size, cached?.model)
    }

    private func byte(before offset: UInt64, in handle: FileHandle) -> UInt8? {
        try? handle.seek(toOffset: offset - 1)
        return (try? handle.read(upToCount: 1))?.first
    }

    private func remember(_ url: URL, _ size: UInt64, _ model: String?) -> String? {
        lock.lock() ; defer { lock.unlock() }
        entries[url.path] = Entry(size: size, model: model, touched: Date())
        if entries.count > 64 {
            let cutoff = Date().addingTimeInterval(-600)
            entries = entries.filter { $0.value.touched > cutoff }
        }
        return model
    }

    /// 덩어리 안에서 **마지막** 본선 assistant 줄의 모델.
    private static func lastMainModel(in data: Data) -> String? {
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            // 모델이 안 적힌 줄은 JSON 으로 풀지 않는다. 대부분이 그렇다.
            guard line.range(of: needle) != nil,
                  let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  obj["isSidechain"] as? Bool != true,
                  let model = Transcript.claudeModel(in: obj["message"] as? [String: Any])
            else { continue }
            return model
        }
        return nil
    }
}

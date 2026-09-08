import Foundation
import Darwin

/// codex 세션을 긁어 온다.
///
/// Claude Code 와 달리 **codex 는 자기 상태를 어디에도 적지 않는다.** pid 도 status 도 없다.
/// 남기는 것은 `~/.codex/sessions/<연>/<월>/<일>/rollout-<시각>-<uuid>.jsonl` 한 줄기뿐이다.
/// 그래서 여기서는 두 가지를 우리 손으로 잇는다 —
///
///   ① **살아있음** — rollout 의 작업 폴더·시작 시각과 맞는 프로세스를 커널에서 찾는다.
///      찾으면 그 pid 가 이 세션의 pid 다 (덕분에 터미널 점프와 메모리 측정이 따라온다).
///   ② **상태** — rollout 끝의 turn 경계 이벤트로 «작업 중/입력 대기» 를 **추정**한다.
///
/// ②는 이 프로젝트가 원래 피하려던 파생 판정이다. 다른 길이 없으므로 하되,
/// `isEstimated` 를 세워 화면에 «추정» 이라고 적는다. 조용히 단정하지 않는 것이 조건이다.
///
/// 다루는 것은 **터미널 codex(`originator == "codex-tui"`)뿐이다.** `codex exec` 는 사람이
/// 앉아 있지 않고, 데스크탑 앱 스레드는 pid 도 터미널도 없어 «기다린다» 를 잴 수가 없다.
struct CodexSource: SessionSource {
    let sourceName = "codex"

    private let home = URL(fileURLWithPath: NSHomeDirectory())
    private let fm = FileManager.default

    /// rollout 은 수 MB 까지 커진다. 끝에서 이만큼만 되감아 읽는다.
    private let tailBytes = 64 * 1024

    /// 이보다 오래 손대지 않은 rollout 은 후보로 보지 않는다.
    /// 살아있는 세션이라면 turn 마다 파일에 쓰므로 이 안에 들어온다.
    private let lookback: TimeInterval = 24 * 60 * 60

    /// 프로세스 시작 시각이 세션 시작과 이만큼 안에서 어긋나면 같은 것으로 본다.
    private let matchWindow: TimeInterval = 120

    // MARK: 루트

    /// codex 홈. `CODEX_HOME` 이 있으면 그것을 따른다.
    var root: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return home.appendingPathComponent(".codex")
    }

    // MARK: 훑기

    func scan() -> [Session] {
        let sessionsDir = root.appendingPathComponent("sessions")
        guard fm.fileExists(atPath: sessionsDir.path) else { return [] }

        let metas = recentRollouts(in: sessionsDir).compactMap(parseMeta)
        guard !metas.isEmpty else { return [] }

        let names = threadNames()
        let live = liveProcesses()
        var used = Set<Int32>()
        var out: [Session] = []

        // 최근 세션부터 짝지어 간다. 한 프로세스가 두 세션에 붙는 일을 막는다.
        for meta in metas.sorted(by: { $0.startedAt > $1.startedAt }) {
            guard let pid = matchProcess(to: meta, among: live, excluding: used) else { continue }
            used.insert(pid)

            let facts = readTail(meta.url).map(parseTail) ?? TailFacts()
            var session = Session(
                id: meta.sessionID,
                pid: pid,
                name: names[meta.sessionID] ?? URL(fileURLWithPath: meta.cwd).lastPathComponent,
                cwd: meta.cwd,
                state: facts.state,
                kind: "codex-tui",
                startedAt: meta.startedAt,
                statusUpdatedAt: facts.timestamp,
                accountRoot: root
            )
            session.currentTool = facts.tool
            session.lastActivity = facts.timestamp
            // 상태를 우리가 추정했다는 표식. 화면에 «추정» 으로 나간다.
            session.isEstimated = true
            out.append(session)
        }
        return out
    }

    // MARK: rollout 고르기

    /// 최근 손댄 rollout 파일만 모은다.
    ///
    /// 날짜가 경로에 박혀 있으므로(`<연>/<월>/<일>`) 훑을 날짜 폴더부터 좁힌다.
    /// 287개가 쌓인 폴더를 통째로 훑을 이유가 없다.
    private func recentRollouts(in sessionsDir: URL) -> [URL] {
        let cutoff = Date().addingTimeInterval(-lookback)
        var days: [URL] = []
        let calendar = Calendar.current
        // 어제와 오늘이면 충분하다. lookback 을 늘리면 여기도 함께 늘린다.
        for back in 0...(Int(lookback / 86400) + 1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let y = parts.year, let m = parts.month, let d = parts.day else { continue }
            days.append(sessionsDir
                .appendingPathComponent(String(format: "%04d", y))
                .appendingPathComponent(String(format: "%02d", m))
                .appendingPathComponent(String(format: "%02d", d)))
        }

        var out: [URL] = []
        for day in days {
            guard let files = try? fm.contentsOfDirectory(at: day,
                                                          includingPropertiesForKeys: [.contentModificationDateKey],
                                                          options: [.skipsHiddenFiles]) else { continue }
            for file in files where file.pathExtension == "jsonl" && file.lastPathComponent.hasPrefix("rollout-") {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified < cutoff { continue }
                out.append(file)
            }
        }
        return out
    }

    private struct Meta {
        let url: URL
        let sessionID: String
        let cwd: String
        let startedAt: Date
    }

    /// 첫 줄의 `session_meta` 만 읽는다. 터미널 세션이 아니면 버린다.
    private func parseMeta(_ url: URL) -> Meta? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // 첫 줄만 필요하다. base_instructions 가 붙어 길어지므로 넉넉히 읽고 자른다.
        guard let head = try? handle.read(upToCount: 256 * 1024) else { return nil }
        let text = String(decoding: head, as: UTF8.self)
        guard let newline = text.firstIndex(of: "\n") else { return nil }

        guard let data = String(text[..<newline]).data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              obj["type"] as? String == "session_meta",
              let payload = obj["payload"] as? [String: Any],
              let id = payload["session_id"] as? String ?? payload["id"] as? String,
              let cwd = payload["cwd"] as? String
        else { return nil }

        // 터미널에서 띄운 것만 본다.
        guard payload["originator"] as? String == "codex-tui" else { return nil }

        let started = (payload["timestamp"] as? String).flatMap(parseISO)
            ?? (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            ?? Date.distantPast
        return Meta(url: url, sessionID: id, cwd: cwd, startedAt: started)
    }

    /// `session_index.jsonl` 에서 사람이 읽을 이름을 가져온다.
    /// 같은 id 가 여러 번 나오면 마지막 것이 최신이다.
    private func threadNames() -> [String: String] {
        let url = root.appendingPathComponent("session_index.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = obj["id"] as? String,
                  let name = obj["thread_name"] as? String, !name.isEmpty
            else { continue }
            out[id] = name
        }
        return out
    }

    // MARK: 프로세스 짝짓기

    private struct LiveProcess {
        let pid: Int32
        let ppid: Int32
        let cwd: String
        let startedAt: Date
    }

    /// 같은 사용자로 도는 프로세스의 pid·작업 폴더·시작 시각.
    ///
    /// 남의 계정 프로세스는 cwd 를 읽을 수 없어 저절로 빠진다.
    private func liveProcesses() -> [LiveProcess] {
        MetricsSampler.allProcesses().compactMap { entry in
            guard let cwd = workingDirectory(pid: entry.pid),
                  let started = processStartTime(pid: entry.pid) else { return nil }
            return LiveProcess(pid: entry.pid, ppid: entry.ppid, cwd: cwd, startedAt: started)
        }
    }

    /// rollout 에 맞는 프로세스를 고른다.
    ///
    /// **실행 파일 이름으로 거르지 않는다.** 설치 방식마다 이름이 달라져서,
    /// 이름으로 거르면 남의 환경에서 멀쩡한 세션이 통째로 사라진다
    /// (`ClaudeCodeSource.isAlive` 가 같은 이유로 이름을 안 쓴다).
    ///
    /// 대신 **작업 폴더가 같고 세션 시작 무렵에 뜬 것**을 찾는다.
    ///
    /// 그런데 그 폴더에서 도는 것은 codex 하나가 아니다. codex 가 띄운 도우미들
    /// (MCP 플러그인 · 언어 서버 등)도 같은 폴더를 물려받고, 그것들은 codex 보다
    /// **늦게** 뜬다. 실제로 재보니 후보 다섯 중 가장 늦은 것은 codex 가 아니라
    /// 플러그인 노드 프로세스였다. 그래서 시작 순서로 고르면 안 되고,
    /// **부모가 후보 안에 없는 것** — 즉 그 무리의 조상 — 을 고른다. 그것이 세션이다.
    ///
    /// 한계: 같은 폴더에서 codex 를 둘 띄우면 어느 쪽이 어느 rollout 인지 구분할 수 없다.
    /// 최근 세션부터 짝지으며 쓴 pid 를 빼는 것으로 겹침만 막는다.
    private func matchProcess(to meta: Meta,
                              among live: [LiveProcess],
                              excluding used: Set<Int32>) -> Int32? {
        let candidates = live.filter { candidate in
            !used.contains(candidate.pid)
                && candidate.cwd == meta.cwd
                && abs(candidate.startedAt.timeIntervalSince(meta.startedAt)) < matchWindow
        }
        guard !candidates.isEmpty else { return nil }

        let pids = Set(candidates.map(\.pid))
        let roots = candidates.filter { !pids.contains($0.ppid) }
        // 조상을 못 가리면(모두 서로의 부모가 아님) 가장 먼저 뜬 것을 쓴다.
        return (roots.isEmpty ? candidates : roots).min { $0.startedAt < $1.startedAt }?.pid
    }

    private func workingDirectory(pid: Int32) -> String? {
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

    private func processStartTime(pid: Int32) -> Date? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let rc = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, $0, size)
        }
        guard rc == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbsd.pbi_start_tvsec)
                                         + Double(info.pbsd.pbi_start_tvusec) / 1_000_000)
    }

    // MARK: 상태 추정

    private struct TailFacts {
        /// 무엇도 못 읽었으면 «모름» 이다. 모르는 것을 «입력 대기» 로 두면
        /// 있지도 않은 일감을 메뉴바 숫자에 올리게 된다.
        var state: SessionState = .unknown("no turn event")
        var tool: String?
        var timestamp: Date?
    }

    /// 끝에서 거슬러 올라가며 turn 의 경계를 찾는다.
    ///
    /// `task_started` 뒤에 `task_complete`·`turn_aborted` 가 없으면 아직 도는 중이고,
    /// 있으면 사람 차례다. 승인 대기(`waiting`)는 내지 않는다 —
    /// 훑어본 rollout 에 승인 요청에 해당하는 이벤트가 없어 근거가 없다.
    private func parseTail(_ text: String) -> TailFacts {
        var facts = TailFacts()
        var stateFound = false

        for line in text.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }

            if facts.timestamp == nil, let ts = obj["timestamp"] as? String {
                facts.timestamp = parseISO(ts)
            }

            guard obj["type"] as? String == "event_msg",
                  let payload = obj["payload"] as? [String: Any],
                  let kind = payload["type"] as? String else { continue }

            if !stateFound {
                switch kind {
                case "task_started":
                    facts.state = .busy
                    stateFound = true
                case "task_complete", "turn_aborted":
                    facts.state = .idle
                    stateFound = true
                default:
                    break
                }
            }

            if facts.tool == nil, kind == "item_completed",
               let item = payload["item"] as? [String: Any],
               let type = item["type"] as? String,
               Self.toolItems.contains(type) {
                facts.tool = type
            }

            if stateFound && facts.tool != nil && facts.timestamp != nil { break }
        }
        return facts
    }

    /// 도구로 볼 항목. 생각·말은 도구가 아니므로 뺀다.
    private static let toolItems: Set<String> = [
        "CommandExecution", "FileChange", "ImageView", "WebSearch", "McpToolCall", "PatchApply",
    ]

    // MARK: 읽기 도구

    /// 파일 끝에서 `tailBytes` 만큼만 읽는다. 앞은 건드리지 않는다.
    private func readTail(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        // 처음 한 줄은 잘려 있을 수 있으므로 버린다.
        if offset > 0, let nl = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: nl)...])
        }
        return text
    }

    private func parseISO(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

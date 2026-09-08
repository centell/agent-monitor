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
        let processes = LiveProcessTable()
        var used = Set<Int32>()
        var out: [Session] = []

        // 최근 세션부터 짝지어 간다. 한 프로세스가 두 세션에 붙는 일을 막는다.
        for meta in metas.sorted(by: { $0.startedAt > $1.startedAt }) {
            guard let pid = processes.session(inDirectory: meta.cwd,
                                              excluding: used,
                                              startedNear: meta.startedAt,
                                              within: matchWindow) else { continue }
            used.insert(pid)

            let facts = Transcript.tail(of: meta.url).map(parseTail) ?? TailFacts()
            var session = Session(
                id: meta.sessionID,
                pid: pid,
                name: names[meta.sessionID] ?? URL(fileURLWithPath: meta.cwd).lastPathComponent,
                source: "codex",
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

        let started = (payload["timestamp"] as? String).flatMap(Transcript.parseISO)
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
                facts.timestamp = Transcript.parseISO(ts)
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
}

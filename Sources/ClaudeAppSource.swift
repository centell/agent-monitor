import Foundation

/// Claude 데스크탑 앱 안에서 도는 Claude Code 세션을 긁어 온다.
///
/// 앱은 CLI 와 **다른 자리에 다른 것을 적는다.** 앱이 띄우는 claude 는
/// `--input-format stream-json` 파이프 모드라 터미널이 없고, 그래서
/// `<계정루트>/sessions/<pid>.json` 레지스트리에 등록하지 않는다. 대신
///
///   `~/Library/Application Support/Claude/claude-code-sessions/<작업공간>/<id>/local_<uuid>.json`
///
/// 에 세션을 적어 둔다. 이름(`title`)·작업 폴더·기록 id 는 여기 다 있지만
/// **`status` 는 없다.** 그래서 상태는 기록 끝에서 추정한다 — codex 와 같은 처지다.
///
/// 터미널이 없으므로 눌러서 이동할 수 없다. 그건 `TerminalJump.canJump` 가 tty 를
/// 못 찾아 스스로 걸러 주므로 여기서 따로 손대지 않는다 — 줄이 흐리게 그려진다.
struct ClaudeAppSource: SessionSource {
    let sourceName = "Claude app"

    private let home = URL(fileURLWithPath: NSHomeDirectory())
    private let fm = FileManager.default

    /// 앱이 세션을 적어 두는 곳.
    ///
    /// 다른 출처처럼 환경변수로 갈아끼울 수 있게 둔다. 그래야 진짜 앱을 띄우지 않고도
    /// 만들어 낸 상황을 먹여 재볼 수 있다 — 못 재는 코드는 못 믿는 코드다.
    var root: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_APP_SESSIONS_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    /// 기록이 사는 곳. CLI 와 **같은 곳**을 쓰므로 같은 환경변수를 따른다.
    private var projects: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
                .appendingPathComponent("projects")
        }
        return home.appendingPathComponent(".claude/projects")
    }

    // MARK: 훑기

    func scan() -> [Session] {
        let records = sessionRecords()
        guard !records.isEmpty else { return [] }

        let table = LiveProcessTable()
        var used = Set<Int32>()
        var out: [Session] = []

        // 최근 것부터 짝지어 한 프로세스가 두 세션에 붙는 일을 막는다.
        for record in records.sorted(by: { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }) {
            // 시간창을 두지 않는다. 앱 세션의 작업 폴더는 세션마다 따로 나므로
            // 폴더가 같으면 그 세션이고, 앱이 프로세스를 언제 다시 띄우든 상관없다.
            guard let pid = table.session(inDirectory: record.cwd, excluding: used) else { continue }
            used.insert(pid)

            let facts = readState(for: record)
            var session = Session(
                id: record.cliSessionID,
                pid: pid,
                name: record.title,
                source: "claude",
                runsInApp: true,
                cwd: record.cwd,
                state: facts.state,
                kind: "app",
                startedAt: record.createdAt,
                statusUpdatedAt: facts.timestamp ?? record.lastActivityAt,
                accountRoot: root
            )
            session.deepLink = Self.deepLink(for: record.localID)
            session.currentTool = facts.tool
            session.lastActivity = facts.timestamp ?? record.lastActivityAt
            // 앱은 상태를 적지 않는다. 우리가 기록에서 읽어 낸 것이므로 «추정» 이라 적는다.
            session.isEstimated = true
            out.append(session)
        }
        return out
    }

    // MARK: 등록부

    private struct Record {
        let localID: String         // 앱이 부르는 이름 (local_…). 딥링크가 이것을 받는다.
        let cliSessionID: String
        let cwd: String
        let title: String
        let createdAt: Date?
        let lastActivityAt: Date?
    }

    /// `local_*.json` 을 전부 모은다. 보관된 세션은 뺀다.
    private func sessionRecords() -> [Record] {
        guard let walker = fm.enumerator(at: root,
                                         includingPropertiesForKeys: nil,
                                         options: [.skipsHiddenFiles]) else { return [] }
        var out: [Record] = []
        for case let url as URL in walker {
            guard url.pathExtension == "json",
                  url.lastPathComponent.hasPrefix("local_"),
                  let data = try? Data(contentsOf: url),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let localID = obj["sessionId"] as? String,
                  let cliID = obj["cliSessionId"] as? String,
                  let cwd = obj["cwd"] as? String
            else { continue }

            // 사용자가 치운 세션은 목록에 올리지 않는다.
            if obj["isArchived"] as? Bool == true { continue }

            let title = (obj["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? URL(fileURLWithPath: cwd).lastPathComponent
            out.append(Record(localID: localID,
                              cliSessionID: cliID,
                              cwd: cwd,
                              title: title,
                              createdAt: epochMillis(obj["createdAt"]),
                              lastActivityAt: epochMillis(obj["lastActivityAt"])))
        }
        return out
    }

    /// 앱이 등록한 `claude://` 스킴으로 이 세션을 연다.
    ///
    /// 주소 형태는 앱 번들 안에 박혀 있는 것을 그대로 따랐다
    /// (`claude://code/continue?session=last&source=desktop_action`).
    /// `session` 에 세션 id 를 넣으면 그 세션으로 가고, 앱이 못 알아들어도
    /// **스킴을 처리하며 앱이 앞으로 나오므로** 헛걸음은 아니다.
    private static func deepLink(for localID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [
            URLQueryItem(name: "session", value: localID),
            URLQueryItem(name: "source", value: "agent_monitor"),
        ]
        return components.url
    }

    private func epochMillis(_ any: Any?) -> Date? {
        guard let ms = any as? Double, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    // MARK: 상태 추정

    private struct Facts {
        /// 못 읽었으면 «모름» 이다. 모르는 것을 «입력 대기» 로 두면
        /// 있지도 않은 일감을 메뉴바 숫자에 올리게 된다.
        var state: SessionState = .unknown("no turn end")
        var tool: String?
        var timestamp: Date?
    }

    private func readState(for record: Record) -> Facts {
        guard let url = transcriptURL(for: record), let text = Transcript.tail(of: url) else {
            return Facts()
        }
        return parseTail(text)
    }

    private func transcriptURL(for record: Record) -> URL? {
        let direct = projects
            .appendingPathComponent(Transcript.projectSlug(for: record.cwd))
            .appendingPathComponent("\(record.cliSessionID).jsonl")
        if fm.fileExists(atPath: direct.path) { return direct }

        // 규칙이 어긋났을 때를 대비한 폴백. 프로젝트 폴더를 훑어 파일명으로 찾는다.
        guard let dirs = try? fm.contentsOfDirectory(at: projects,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return nil }
        for dir in dirs {
            let candidate = dir.appendingPathComponent("\(record.cliSessionID).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// 기록 끝에서 턴이 끝났는지 본다.
    ///
    /// 마지막 assistant 메시지의 `stop_reason` 이 갈림길이다 —
    /// `end_turn` 이면 할 말을 마치고 사람 차례이고, `tool_use` 면 도구를 부르는 중이다.
    /// 마지막이 사람이 보낸 말이면 방금 시킨 것이므로 아직 도는 중이다.
    ///
    /// 서브에이전트(sidechain)는 세지 않는다 — 그건 이 세션의 턴이 아니다.
    private func parseTail(_ text: String) -> Facts {
        var facts = Facts()
        var stateFound = false

        for line in text.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }

            let type = obj["type"] as? String
            guard type == "assistant" || type == "user" else { continue }
            if obj["isSidechain"] as? Bool == true { continue }

            if facts.timestamp == nil, let ts = obj["timestamp"] as? String {
                facts.timestamp = Transcript.parseISO(ts)
            }

            let message = obj["message"] as? [String: Any]
            let content = message?["content"] as? [[String: Any]]

            if !stateFound {
                if type == "assistant" {
                    switch message?["stop_reason"] as? String {
                    case "end_turn", "stop_sequence":
                        facts.state = .idle
                        stateFound = true
                    case "tool_use":
                        facts.state = .busy
                        stateFound = true
                    default:
                        break   // 아직 쓰는 중이거나 우리가 모르는 값 — 다음 줄로.
                    }
                } else if let content, content.contains(where: { $0["type"] as? String == "text" }) {
                    // 사람이 방금 말을 걸었다. 도구 결과가 돌아온 것은 사람의 말이 아니다.
                    facts.state = .busy
                    stateFound = true
                }
            }

            if facts.tool == nil, let content {
                for block in content.reversed() where block["type"] as? String == "tool_use" {
                    facts.tool = block["name"] as? String
                    break
                }
            }

            if stateFound && facts.tool != nil && facts.timestamp != nil { break }
        }
        return facts
    }
}

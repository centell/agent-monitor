import Foundation
import Darwin

/// Claude Code 세션을 긁어 온다.
///
/// 1차 출처는 `<계정루트>/sessions/<pid>.json` 레지스트리다. Claude Code 가 자기 상태를
/// 직접 적어 두므로 추측할 필요가 없다. transcript 는 «현재 무슨 도구를 쓰는가» 를
/// 보강하는 데만 쓰고, 상태 판정에는 쓰지 않는다.
struct ClaudeCodeSource: SessionSource {
    let sourceName = "Claude Code"

    private let home = URL(fileURLWithPath: NSHomeDirectory())
    private let fm = FileManager.default

    /// transcript 는 수십 MB 까지 커진다. 끝에서 이만큼만 되감아 읽는다.
    private let tailBytes = 64 * 1024

    // MARK: 계정 루트

    /// 계정 루트를 전부 모은다.
    ///
    /// `~/.claude` 하나만 보면 안 된다. 계정을 여러 개 쓰면 `~/.claude-accounts/<이름>/`
    /// 아래에 각자의 `sessions/` 가 따로 생긴다. `projects/` 는 링크로 합쳐져 있어도
    /// 레지스트리는 합쳐지지 않는다.
    func accountRoots() -> [URL] {
        var roots: [URL] = []

        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            roots.append(URL(fileURLWithPath: (override as NSString).expandingTildeInPath))
        }
        roots.append(home.appendingPathComponent(".claude"))

        let accountsDir = home.appendingPathComponent(".claude-accounts")
        if let entries = try? fm.contentsOfDirectory(at: accountsDir,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) {
            for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                roots.append(entry)
            }
        }

        // 같은 곳을 두 번 훑지 않는다 (CLAUDE_CONFIG_DIR 가 기본 경로를 가리킬 수 있다).
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
                    .filter { fm.fileExists(atPath: $0.appendingPathComponent("sessions").path) }
    }

    // MARK: 훑기

    func scan() -> [Session] {
        var out: [Session] = []
        for root in accountRoots() {
            let sessionsDir = root.appendingPathComponent("sessions")
            guard let files = try? fm.contentsOfDirectory(at: sessionsDir,
                                                          includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { continue }
            for file in files where file.pathExtension == "json" {
                guard var session = parseRegistry(file, root: root) else { continue }
                guard isAlive(pid: session.pid, startedAt: session.startedAt) else { continue }
                enrich(&session, root: root)
                out.append(session)
            }
        }
        return out
    }

    // MARK: 레지스트리

    private func parseRegistry(_ url: URL, root: URL) -> Session? {
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let pid = obj["pid"] as? Int,
              let id = obj["sessionId"] as? String,
              let status = obj["status"] as? String
        else { return nil }

        let cwd = obj["cwd"] as? String ?? ""
        return Session(
            id: id,
            pid: Int32(pid),
            name: obj["name"] as? String ?? URL(fileURLWithPath: cwd).lastPathComponent,
            source: "claude",
            runsInApp: false,
            cwd: cwd,
            state: SessionState(raw: status),
            kind: obj["kind"] as? String,
            startedAt: epochMillis(obj["startedAt"]),
            statusUpdatedAt: epochMillis(obj["statusUpdatedAt"]) ?? epochMillis(obj["updatedAt"]),
            accountRoot: root
        )
    }

    private func epochMillis(_ any: Any?) -> Date? {
        guard let ms = any as? Double, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    // MARK: 생존 확인

    /// 등록부는 남았는데 프로세스가 죽은 경우를 걸러낸다.
    ///
    /// `kill(pid, 0)` 만으로는 부족하다. PID 는 재사용되므로 그 자리에 앉은 것이
    /// 정말 그 세션인지 확인해야 한다. 다만 **실행 파일 이름이나 경로로 확인하면 안 된다** —
    /// 설치 방식마다 달라서(이 맥에서는 `proc_name` 이 `claude` 가 아니라 `2.1.263` 을 돌려준다)
    /// 남의 환경에서 멀쩡한 세션을 전부 걸러내게 된다.
    ///
    /// 그래서 커널이 아는 프로세스 시작 시각을 레지스트리의 `startedAt` 과 맞춰 본다.
    /// PID 가 재사용됐다면 새 프로세스는 한참 뒤에 시작했을 것이므로 어긋난다.
    private func isAlive(pid: Int32, startedAt: Date?) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        // 시작 시각을 못 읽으면 살아있다고 본다. 확인 못 한다고 멀쩡한 세션을 버리지 않는다.
        guard let expected = startedAt, let actual = processStartTime(pid: pid) else { return true }
        return abs(actual.timeIntervalSince(expected)) < 60
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

    // MARK: transcript 보강

    private func enrich(_ session: inout Session, root: URL) {
        guard let url = transcriptURL(for: session, root: root),
              let tail = readTail(url) else { return }
        let facts = parseTail(tail)
        session.currentTool = facts.tool
        session.lastActivity = facts.timestamp
        session.pendingCall = facts.pendingCall
        session.lastSay = facts.lastSay
    }

    /// cwd 를 디렉터리 이름으로 바꾼다. 영숫자가 아닌 글자는 전부 `-` 가 된다.
    /// (`/Users/a/My Docs/x_y` → `-Users-a-My-Docs-x-y`)
    private func slug(for cwd: String) -> String {
        String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    private func transcriptURL(for session: Session, root: URL) -> URL? {
        let projects = root.appendingPathComponent("projects")
        let direct = projects
            .appendingPathComponent(slug(for: session.cwd))
            .appendingPathComponent("\(session.id).jsonl")
        if fm.fileExists(atPath: direct.path) { return direct }

        // 규칙이 어긋났을 때를 대비한 폴백. 프로젝트 폴더를 훑어 파일명으로 찾는다.
        guard let dirs = try? fm.contentsOfDirectory(at: projects,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return nil }
        for dir in dirs {
            let candidate = dir.appendingPathComponent("\(session.id).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

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

    private struct TailFacts {
        var tool: String?
        var timestamp: Date?
        /// 결과가 아직 안 돌아온 도구 호출. 승인 프롬프트가 떠 있으면 그 호출이 여기 남는다.
        var pendingCall: String?
        /// 이번 턴에 사람에게 건넨 마지막 말.
        var lastSay: String?
    }

    /// 끝에서부터 거슬러 올라가며 마지막 대화 이벤트를 찾는다.
    /// 서브에이전트(sidechain)는 세지 않는다 — 그건 이 세션의 활동이 아니다.
    ///
    /// «왜 기다리는가» 를 뽑는 데는 경계가 둘 필요하다.
    /// **대기 중인 호출은 마지막 assistant 메시지에서만** 집는다. 더 거슬러 올라가면
    /// 결과가 64KB 창 밖으로 밀려난 옛 호출까지 «아직 안 끝난 것» 으로 잘못 잡는다.
    /// **마지막 말은 이번 턴 안에서만** 집는다. 사람이 말을 건 줄을 만나면 그 앞은
    /// 지난 턴이므로 거기서 멈춘다 — 지난 턴의 말을 지금 물음으로 내밀면 안 된다.
    private func parseTail(_ text: String) -> TailFacts {
        var facts = TailFacts()
        var resolved = Set<String>()        // 결과가 돌아온 도구 호출 id
        var latestMessageID: String?        // 마지막 assistant 메시지의 id
        var reachedPreviousTurn = false     // 사람이 말을 건 줄을 지났는가
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in text.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }

            let type = obj["type"] as? String
            guard type == "assistant" || type == "user" else { continue }
            if obj["isSidechain"] as? Bool == true { continue }

            if facts.timestamp == nil, let ts = obj["timestamp"] as? String {
                facts.timestamp = iso.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
            }

            let message = obj["message"] as? [String: Any]
            let content = message?["content"] as? [[String: Any]]

            if type == "user" {
                // 도구 결과가 돌아온 호출을 적어 둔다. 남은 것이 대기 중인 호출이다.
                for block in content ?? [] where block["type"] as? String == "tool_result" {
                    if let id = block["tool_use_id"] as? String { resolved.insert(id) }
                }
                // 사람이 직접 건넨 말이면 여기서 이번 턴이 시작된 것이다.
                if message?["content"] is String
                    || content?.contains(where: { $0["type"] as? String == "text" }) == true {
                    reachedPreviousTurn = true
                }
                continue
            }

            // 한 메시지가 여러 줄로 나뉘어 적히므로(생각·말·도구 호출) id 로 묶어 본다.
            let messageID = message?["id"] as? String ?? ""
            if latestMessageID == nil { latestMessageID = messageID }
            let isLatestMessage = messageID == latestMessageID

            if let content {
                for block in content.reversed() where block["type"] as? String == "tool_use" {
                    if facts.tool == nil { facts.tool = block["name"] as? String }
                    if isLatestMessage, facts.pendingCall == nil,
                       let id = block["id"] as? String, !resolved.contains(id),
                       let name = block["name"] as? String {
                        facts.pendingCall = Transcript.callSummary(
                            name: name, input: block["input"] as? [String: Any])
                    }
                }
                if facts.lastSay == nil, !reachedPreviousTurn {
                    facts.lastSay = Transcript.closingLine(inContent: content)
                }
            }

            if facts.timestamp != nil && facts.tool != nil
                && (facts.lastSay != nil || reachedPreviousTurn) { break }
        }
        return facts
    }
}

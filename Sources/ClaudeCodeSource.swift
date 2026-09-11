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
                guard isAlive(session) else { continue }
                enrich(&session, root: root)
                out.append(session)
            }
        }
        return merged(out)
    }

    // MARK: 이어진 세션 합치기

    /// 이어진 세션 둘을 한 줄로 합친다.
    ///
    /// 세션이 이어지면 **대화만 새 프로세스로 옮겨 가고 터미널 창은 앞선 프로세스가 그대로
    /// 쥐고 있다.** 합치지 않으면 한 세션이 두 줄로 나오고, 그 둘이 정확히 반대로 고장난다 —
    /// 창을 가진 줄은 상태가 넘겨준 순간에 멈춰 있고(실측 3시간 반), 일하고 있는 줄은
    /// 갈 창이 없다(그쪽 tty 는 daemon 이 만든 pty 다).
    ///
    /// 고리는 앞선 세션의 기록 끝에 적힌 `continued-in` 이다. 프로세스 계보로 짐작하지
    /// 않는다 — 누가 누구로 이어졌는지는 기록에 그렇게 **적혀 있다**.
    private func merged(_ sessions: [Session]) -> [Session] {
        guard sessions.contains(where: { $0.continuedIn != nil }) else { return sessions }

        var slotOfID: [String: Int] = [:]
        for (slot, session) in sessions.enumerated() { slotOfID[session.id] = slot }

        var out = sessions
        var retired = Set<Int>()
        for (slot, session) in sessions.enumerated() {
            // 넘겨준 상대가 목록에 없으면(이미 끝났으면) 합치지 않는다. 이 줄이 아직
            // 살아있는 마지막 조각이므로 지우면 세션이 통째로 사라진다.
            guard let next = session.continuedIn, let heir = slotOfID[next] else { continue }
            out[heir].continuedFromPid = session.pid
            retired.insert(slot)
        }
        return out.enumerated().filter { !retired.contains($0.offset) }.map(\.element)
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
            accountRoot: root,
            procStart: ctime(obj["procStart"])
        )
    }

    private func epochMillis(_ any: Any?) -> Date? {
        guard let ms = any as? Double, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// `"Thu Sep 10 07:32:00 2026"` 같은 `ctime` 꼴을 읽는다. **UTC 로 적힌다** (실측:
    /// 커널이 알려 준 16:32 KST 를 레지스트리는 07:32 로 적었다).
    ///
    /// 달·요일 이름이 영어라 로캘을 `en_US_POSIX` 로 못 박는다. 그러지 않으면 맥의 언어를
    /// 한국어로 둔 사람에게서 `Sep` 이 안 읽혀 조용히 nil 이 되고, 그러면 이 값을 못 쓴다.
    private static let ctimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f
    }()

    private func ctime(_ any: Any?) -> Date? {
        guard let text = any as? String else { return nil }
        // 진짜 `ctime` 은 한 자리 날짜를 공백 둘로 채운다 (`"Thu Sep  1 …"`). 붙여 둔 형식은
        // 공백 하나라 그대로 두면 그런 날에만 조용히 안 읽힌다 — 한 달에 아흐레씩.
        let flat = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return Self.ctimeFormatter.date(from: flat)
    }

    // MARK: 생존 확인

    /// 등록부는 남았는데 프로세스가 죽은 경우를 걸러낸다.
    ///
    /// `kill(pid, 0)` 만으로는 부족하다. PID 는 재사용되므로 그 자리에 앉은 것이
    /// 정말 그 세션인지 확인해야 한다. 다만 **실행 파일 이름이나 경로로 확인하면 안 된다** —
    /// 설치 방식마다 달라서(이 맥에서는 `proc_name` 이 `claude` 가 아니라 `2.1.263` 을 돌려준다)
    /// 남의 환경에서 멀쩡한 세션을 전부 걸러내게 된다.
    ///
    /// 그래서 커널이 아는 프로세스 시작 시각을 레지스트리가 적어 둔 시각과 맞춰 본다.
    /// PID 가 재사용됐다면 새 프로세스는 한참 뒤에 시작했을 것이므로 어긋난다.
    ///
    /// **어느 시각과 맞출지가 함정이었다.** 예전에는 `startedAt` 하나만 봤는데, 그건
    /// «세션이 시작된 시각» 이지 «프로세스가 뜬 시각» 이 아니다. `claude` 는 백그라운드용
    /// 프로세스를 미리 데워 두었다가(`bg-spare`) 나중에 집어 쓰므로, 스페어가 놀고 있던
    /// 시간만큼 둘이 벌어진다 — 실측 48분 52초. 그동안 그런 세션은 **목록에서 조용히
    /// 사라지고 있었다.** 떠 있는데 안 보이는 것은 꺼졌는데 남아 있는 것보다 나쁘다.
    /// 아침에 본 백그라운드 세션이 멀쩡히 보였던 것은 그 스페어가 마침 그 순간 새로 뜬
    /// 것이었기 때문이다 — 운이 좋으면 보이는 상태였다.
    ///
    /// **둘 중 하나만 맞아도 살아있다고 본다.** 레지스트리가 `procStart` 를 적는 형식이
    /// 판마다 다를 수 있는데, 여기서 잘못 판단한 대가는 한쪽으로 크게 기운다 — 잘못
    /// 살렸으면 낡은 줄이 하나 남을 뿐이고, 잘못 죽이면 돌고 있는 세션이 통째로 사라진다.
    /// 이 파일이 이미 «확인 못 한다고 멀쩡한 세션을 버리지 않는다» 로 서 있으므로 그 결을 따른다.
    private func isAlive(_ session: Session) -> Bool {
        guard session.pid > 0, kill(session.pid, 0) == 0 else { return false }
        // 시작 시각을 못 읽으면 살아있다고 본다.
        guard let actual = processStartTime(pid: session.pid) else { return true }
        let claimed = [session.procStart, session.startedAt].compactMap { $0 }
        guard !claimed.isEmpty else { return true }
        return claimed.contains { abs(actual.timeIntervalSince($0)) < 60 }
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
        session.continuedIn = facts.continuedIn

        // 컨텍스트는 방금 읽은 꼬리에서 공짜로 나온다. 누적은 기록을 통째로 훑어야
        // 하므로 원장에 맡긴다 — 꺼져 있으면 원장이 아무것도 하지 않는다.
        var usage = TokenUsage(context: facts.context)
        if let totals = TokenLedger.shared.session(transcript: url) {
            usage.fresh = totals.fresh
            usage.total = totals.total
            // 꼬리에서 못 구했으면 원장이 본 것으로 메운다. 원장은 기록 전체를 보므로
            // 서브에이전트가 꼬리를 가득 채운 세션에서도 본선 턴을 놓치지 않는다.
            // 누적 칸을 꺼 두면 원장이 돌지 않으므로 그때는 여전히 «—» 다.
            usage.context = usage.context ?? totals.context
        }
        session.usage = usage.isEmpty ? nil : usage
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
        /// 이 세션이 넘어간 다음 세션의 id. 이어진 적이 없으면 없다.
        var continuedIn: String?
        /// 마지막 턴이 들고 간 컨텍스트 크기.
        var context: UInt64?
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

            // 세션이 다른 세션으로 넘어갔다는 표시. 파일 맨 끝에 붙으므로 거슬러 올라가는
            // 이 순회에서 가장 먼저 만난다. 추측이 아니라 **기록에 그렇게 적혀 있는 사실**이다.
            if type == "continued-in" {
                if facts.continuedIn == nil { facts.continuedIn = obj["continuedInSessionId"] as? String }
                continue
            }

            guard type == "assistant" || type == "user" else { continue }
            if obj["isSidechain"] as? Bool == true { continue }

            if facts.timestamp == nil, let ts = obj["timestamp"] as? String {
                facts.timestamp = iso.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
            }

            let message = obj["message"] as? [String: Any]
            let content = message?["content"] as? [[String: Any]]

            // 컨텍스트는 **마지막 턴 하나**의 값이다. 거슬러 올라가는 순회라 처음 만나는
            // assistant 줄이 그 턴이고, sidechain 은 위에서 이미 걸러졌다.
            if type == "assistant", facts.context == nil,
               let usage = message?["usage"] as? [String: Any] {
                facts.context = TokenMath.claude(usage: usage).context
            }

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

            // 컨텍스트도 손에 넣기 전에는 멈추지 않는다. 없이 멈추면 켜 둔 칸이
            // «—» 로 깜빡인다 — 값이 없어서가 아니라 우리가 덜 읽어서.
            if facts.timestamp != nil && facts.tool != nil && facts.context != nil
                && (facts.lastSay != nil || reachedPreviousTurn) { break }
        }
        return facts
    }
}

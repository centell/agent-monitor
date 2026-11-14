import AppKit

/// 세션을 적어 두고, 닫고, 다시 연다.
///
/// 셈은 `SnapshotLogic` 이 하고 여기서는 세상과 닿는 일만 한다 — 파일, 프로세스 인자,
/// 신호, Terminal.app. 설계: `docs/design/specs/2026-11-14-재부팅-뒤-다시-열기.md`
final class SessionReopen {

    static let shared = SessionReopen()

    private(set) var snapshot: SessionSnapshot?
    private let file: URL
    private var lastWrite: Date = .distantPast
    private var lastShape: [String] = []

    /// 「기다렸다 닫기」로 닫히기를 기다리는 세션. id → 창을 쥔 pid.
    ///
    /// pid 도 쥐는 것은 기다리는 사이 세션이 이어지면 id 가 바뀌기 때문이다. 창을 쥔
    /// 프로세스는 그대로라 그것으로 다시 찾는다. 끌 때는 늘 **그 순간 훑은** 세션의
    /// pid 를 쓴다 — 쥐고 있던 pid 로 신호를 보내면 그새 재사용된 남의 프로세스를 칠 수 있다.
    private(set) var closing: [String: Int32] = [:]

    /// 방금 연 세션. 다음 훑기에 잡히기 전에 「모두 열기」를 또 누르면 창이 둘 뜬다.
    private var recentlyOpened: [String: Date] = [:]

    init(file: URL? = nil) {
        self.file = file ?? Self.defaultFile
    }

    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("AgentMonitor/last-sessions.json")
    }

    // MARK: 켤 때

    /// 앱이 켜질 때 한 번. 재부팅 뒤면 끊길 때 살아 있던 세션을 다시 열 목록으로 올린다.
    func launched() {
        guard let old = load() else { return }
        let next = SnapshotLogic.afterLaunch(old, bootedAt: Self.bootTime() ?? .distantPast)
        snapshot = next
        if next != old { write(next) }
    }

    // MARK: 계속 적기

    /// 훑을 때마다 부른다.
    ///
    /// 매번 쓰지는 않는다. 세션이나 상태가 바뀌었을 때, 아니면 30초마다 쓴다.
    /// 「마지막으로 적은 시각」만 낡지 않으면 재부팅 뒤 후보를 가리는 데 모자람이 없다.
    func record(_ sessions: [Session]) {
        let live = sessions.compactMap(Self.saved(from:))
        let liveIDs = Set(sessions.map(\.id))
        let shape = live.map { "\($0.id):\($0.state)" }.sorted()
        let now = Date()

        var next = SnapshotLogic.recording(live, into: snapshot, now: now)
        next = SnapshotLogic.settled(next, liveIDs: liveIDs)
        let savedChanged = next.saved != snapshot?.saved
        snapshot = next
        if savedChanged || shape != lastShape || now.timeIntervalSince(lastWrite) > 30 {
            write(next)
            lastShape = shape
        }

        closeIdle(sessions)
    }

    // MARK: 다시 열 목록

    func pending(live sessions: [Session]) -> [SavedSession] {
        let now = Date()
        recentlyOpened = recentlyOpened.filter { now.timeIntervalSince($0.value) < 60 }
        let opened = Set(recentlyOpened.keys)
        return SnapshotLogic.pending(snapshot, liveIDs: Set(sessions.map(\.id)))
            .filter { !opened.contains($0.id) }
    }

    /// 다시 열지 않고 목록을 걷는다.
    func dismiss() {
        guard var s = snapshot else { return }
        s.saved = nil
        snapshot = s
        write(s)
    }

    // MARK: 저장하고 닫기

    /// 닫을 수 있는 세션. codex 는 아직 끄는 길을 재지 않아 저장만 하고 닫지 않는다.
    static func closable(_ session: Session) -> Bool {
        !session.runsInApp && session.source == "claude"
    }

    /// 지금 목록을 저장한다. 닫기는 `close(_:waitForWork:)` 가 한다.
    func save(_ sessions: [Session]) {
        let live = sessions.compactMap(Self.saved(from:))
        let next = SnapshotLogic.saving(live, into: snapshot, now: Date())
        snapshot = next
        write(next)
    }

    /// 닫는다. 기다리기로 했으면 쉬는 세션만 지금 닫고, 나머지는 쉬는 대로 닫는다.
    func close(_ sessions: [Session], waitForWork: Bool) {
        for session in sessions where Self.closable(session) {
            if waitForWork && session.state != .idle {
                closing[session.id] = session.hostPid
            } else {
                Self.terminate(session)
            }
        }
    }

    /// 기다리지 말고 지금 닫는다.
    func closeNow(_ sessions: [Session]) {
        for (id, hostPid) in closing {
            if let session = find(id: id, hostPid: hostPid, in: sessions) { Self.terminate(session) }
        }
        closing.removeAll()
    }

    func cancelClosing() { closing.removeAll() }

    /// 기다리는 세션 중 턴을 마친 것을 닫는다. 사라진 것은 명단에서 뺀다.
    private func closeIdle(_ sessions: [Session]) {
        guard !closing.isEmpty else { return }
        for (id, hostPid) in closing {
            guard let session = find(id: id, hostPid: hostPid, in: sessions) else {
                closing[id] = nil
                continue
            }
            if session.id != id, let snap = snapshot {
                // 기다리는 사이 이어졌다. 다시 열 목록도 뒤쪽 id 로 고친다.
                snapshot = SnapshotLogic.renaming(snap, from: id, to: session.id)
                if let fixed = snapshot { write(fixed) }
                closing[id] = nil
                closing[session.id] = hostPid
            }
            if session.state == .idle {
                Self.terminate(session)
                closing[session.id] = nil
            }
        }
    }

    private func find(id: String, hostPid: Int32, in sessions: [Session]) -> Session? {
        sessions.first { $0.id == id } ?? sessions.first { $0.hostPid == hostPid && Self.closable($0) }
    }

    /// 세션 하나를 끈다.
    ///
    /// 대화형 세션은 SIGTERM — 실측에서 4초 안에 내려가며 기록을 마무리하고 나갔다.
    /// 백그라운드 세션은 창이 없어 신호를 받을 주인이 daemon 이므로 CLI 에게 시킨다.
    /// 이어진 세션은 둘 다다 — 대화는 daemon 쪽에, 창은 앞선 프로세스에 있다.
    private static func terminate(_ session: Session) {
        if session.isBackground {
            SessionStop.stop(session) { _ in }
            if let window = session.continuedFromPid { kill(window, SIGTERM) }
        } else {
            kill(session.pid, SIGTERM)
        }
    }

    // MARK: 다시 열기

    enum OpenOutcome {
        case opened
        case notPermitted
        case failed(String)
    }

    func open(_ saved: SavedSession) -> OpenOutcome {
        let outcome = saved.background ? openInBackground(saved) : openInTerminal(saved)
        if case .opened = outcome { recentlyOpened[saved.id] = Date() }
        return outcome
    }

    private func openInTerminal(_ saved: SavedSession) -> OpenOutcome {
        let line = ReopenCommand.terminalLine(for: saved, defaultRoot: Self.defaultRoot(for: saved.source))
        let script = """
        tell application "Terminal"
            do script \(ReopenCommand.appleScriptString(line))
            activate
        end tell
        """
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { return .failed(S.errScript) }
        apple.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == errAEEventNotPermitted { return .notPermitted }
            return .failed(error[NSAppleScript.errorMessage] as? String ?? S.errUnknown(code))
        }
        return .opened
    }

    /// 목록을 차례로 연다. 처음 실패에서 멈추고 상자로 말한다 — 권한이 없으면 나머지도
    /// 다 같은 이유로 안 되고, 이 앱의 실패는 삑 소리 하나로 삼키지 않는다 (`TerminalJump.report`).
    func openAll(_ list: [SavedSession]) {
        for saved in list {
            switch open(saved) {
            case .opened:
                continue
            case .notPermitted:
                Self.alert(S.permissionTitle, S.permissionBody)
                return
            case .failed(let why):
                Self.alert(S.reopenFailedTitle, "\(saved.name): \(why)")
                return
            }
        }
    }

    static func alert(_ title: String, _ body: String) {
        NSApp.activate(ignoringOtherApps: true)
        let box = NSAlert()
        box.messageText = title
        box.informativeText = body
        box.addButton(withTitle: S.okButton)
        box.runModal()
    }

    /// 창 없이 연다. 실측: `claude --bg --resume <id>` 가 같은 id 로 bg 세션을 띄운다.
    private func openInBackground(_ saved: SavedSession) -> OpenOutcome {
        guard let claude = SessionStop.binary() else { return .failed(S.stopNoBinary) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: claude)
        task.arguments = ["--bg", "--resume", saved.id]
        task.currentDirectoryURL = URL(fileURLWithPath: saved.cwd)
        var env = ProcessInfo.processInfo.environment
        if ReopenCommand.standardized(saved.accountRoot) != ReopenCommand.standardized(Self.defaultRoot(for: "claude")) {
            env["CLAUDE_CONFIG_DIR"] = saved.accountRoot
        }
        task.environment = env
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return .failed(error.localizedDescription) }
        return .opened
    }

    // MARK: 세션 → 기록

    static func saved(from session: Session) -> SavedSession? {
        guard !session.runsInApp, session.source == "claude" || session.source == "codex" else { return nil }
        let background = session.isBackground && session.continuedFromPid == nil
        var keep: [String] = []
        var dropped: [String] = []
        // 백그라운드 세션의 인자는 daemon 이 붙인 것이라 사람이 고른 옵션이 아니다.
        // 이어진 세션은 창을 쥔 앞선 프로세스의 인자가 사람이 띄운 그대로다.
        if !background, let argv = MemoryReport.arguments(of: session.hostPid) {
            let split = ReopenArgs.split(argv)
            if session.source == "claude" {
                keep = split.keep
                dropped = split.dropped
            } else {
                // codex 는 옵션을 되살리는지 아직 재지 못했다. 붙이지 않고 보이기만 한다.
                dropped = split.keep + split.dropped
            }
        }
        return SavedSession(source: session.source, id: session.id, name: session.name,
                            cwd: session.cwd, accountRoot: session.accountRoot.path,
                            background: background, args: keep, droppedArgs: dropped,
                            state: session.state.raw, lastSeen: Date())
    }

    private static func defaultRoot(for source: String) -> String {
        let home = NSHomeDirectory()
        return source == "codex" ? "\(home)/.codex" : "\(home)/.claude"
    }

    // MARK: 파일

    private func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionSnapshot.self, from: data)
    }

    private func write(_ snapshot: SessionSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // 반쯤 쓴 파일이 남지 않게 한다. 꺼지는 순간에도 쓰는 파일이다.
        try? data.write(to: file, options: .atomic)
        lastWrite = snapshot.writtenAt
    }

    /// 이번 부팅 시각.
    static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}

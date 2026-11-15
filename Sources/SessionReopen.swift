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

    /// 마지막으로 잰 Terminal 창·탭 배치 (tty → 자리). 훑을 때마다 묻지 않는다 — 쓸 때만 다시 잰다.
    private var layout: [String: (window: Int, tab: Int)] = [:]
    private var layoutAt: Date = .distantPast
    private var layoutIDs: Set<String> = []

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
        // 탭으로 열기의 권한을 켤 때 남긴다 — 목록에는 켜져 있는데 앱은 없다고 보는 일이 있었다.
        Self.log("launch ax=\(AXIsProcessTrusted()) se=\(Self.mayAutomateSystemEvents(ask: false))")
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
        var live = sessions.compactMap { Self.saved(from: $0, layout: layout) }
        let liveIDs = Set(sessions.map(\.id))
        let shape = live.map { "\($0.id):\($0.state)" }.sorted()
        let now = Date()
        // 배치는 세션이 들고 나거나 30초가 지났을 때만 다시 잰다. 상태가 바뀔 때마다
        // Terminal 에 물으면 바쁜 날엔 몇 초마다 메인 스레드를 붙든다. 탭을 옮긴 것은 30초 안에 따라온다.
        if liveIDs != layoutIDs || now.timeIntervalSince(layoutAt) > 30 {
            layout = Self.terminalLayout()
            layoutAt = now
            layoutIDs = liveIDs
            live = sessions.compactMap { Self.saved(from: $0, layout: layout) }
        }

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
        layout = Self.terminalLayout()
        let live = sessions.compactMap { Self.saved(from: $0, layout: layout) }
        Self.log("save layout=\(layout.map { "\($0.key)=\($0.value.window).\($0.value.tab)" }.sorted()) "
                 + "sessions=\(live.map { "\($0.name)@\($0.window.map(String.init) ?? "-").\($0.tab.map(String.init) ?? "-")" })")
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

    /// 하나를 연다. `beside` 가 있으면 그 창(id)에 탭으로 붙인다.
    ///
    /// 탭으로 못 붙였으면 새 창으로 열고 `tabbed` 를 거짓으로 돌린다. 열기 자체는 된 것이라
    /// 멈추지 않는다 — 배치가 흐트러지는 것보다 세션이 안 열리는 편이 더 나쁘다.
    private func open(_ saved: SavedSession, beside window: Int?) -> (OpenOutcome, window: Int?, tabbed: Bool) {
        if saved.background {
            let outcome = openInBackground(saved)
            if case .opened = outcome { recentlyOpened[saved.id] = Date() }
            return (outcome, nil, true)
        }
        let line = ReopenCommand.terminalLine(for: saved, defaultRoot: Self.defaultRoot(for: saved.source))
        var tabbed = true
        var result: (OpenOutcome, Int?)
        if let window, let w = Self.addTab(to: window, line: line) {
            result = (.opened, w)
        } else {
            tabbed = window == nil
            result = Self.openWindow(line: line)
        }
        if case .opened = result.0 { recentlyOpened[saved.id] = Date() }
        return (result.0, result.1, tabbed)
    }

    func open(_ saved: SavedSession) -> OpenOutcome { open(saved, beside: nil).0 }

    /// 새 창에 연다. 돌려주는 것은 그 창의 id — 같은 창에 탭을 더 붙일 때 쓴다.
    private static func openWindow(line: String) -> (OpenOutcome, Int?) {
        let script = """
        tell application "Terminal"
            do script \(ReopenCommand.appleScriptString(line))
            activate
            return id of front window
        end tell
        """
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { return (.failed(S.errScript), nil) }
        let out = apple.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == errAEEventNotPermitted { return (.notPermitted, nil) }
            return (.failed(error[NSAppleScript.errorMessage] as? String ?? S.errUnknown(code)), nil)
        }
        return (.opened, Int(out.int32Value))
    }

    /// 창 `window` 에 탭을 하나 붙이고 거기서 연다. 못 붙였으면 nil. 돌려주는 것은 새 탭의 창 id.
    ///
    /// Terminal 의 AppleScript 에는 「새 탭」이 없다. 그 창을 맨 앞에 세우고 ⌘T 를 대신
    /// 누른다 — 그래서 손쉬운 사용 권한이 든다. 글자(`keystroke "t"`)가 아니라 자판 자리
    /// (`key code 17` = T)로 누른다 — 한글 자판이면 글자 t 는 오류도 없이 사라진다
    /// (실측 2026-11-15, 2SetHangul: keystroke 는 창 수 7→7, key code 는 7→8). macOS 탭이라 새 탭도 AppleScript 에는 **새 창**
    /// 으로 보인다 (`ReopenLayout.TerminalWindow`). 창 수가 늘고 맨 앞 창이 바뀐 것을 본
    /// 뒤에야 명령을 넣는다 — 안 그러면 남의 탭에 명령이 들어간다.
    private static func addTab(to window: Int, line: String) -> Int? {
        guard AXIsProcessTrusted(), mayAutomateSystemEvents(ask: false) else { return nil }
        let script = """
        tell application "Terminal"
            activate
            set index of window id \(window) to 1
            set had to count windows
        end tell
        delay 0.2
        tell application "System Events" to key code 17 using command down
        repeat 20 times
            delay 0.1
            tell application "Terminal"
                if (count windows) > had and (id of window 1) is not \(window) then
                    do script \(ReopenCommand.appleScriptString(line)) in window 1
                    return id of window 1
                end if
            end tell
        end repeat
        return 0
        """
        var error: NSDictionary?
        guard let out = NSAppleScript(source: script)?.executeAndReturnError(&error), error == nil else {
            log("addTab failed \(error ?? [:])")
            return nil
        }
        let id = Int(out.int32Value)
        return id == 0 ? nil : id
    }

    /// System Events 를 부려도 되는가. `ask` 면 아직 안 정한 사람에게 묻는다 (답할 때까지 막힌다).
    private static func mayAutomateSystemEvents(ask: Bool) -> Bool {
        let bundle = "com.apple.systemevents"
        guard let desc = NSAppleEventDescriptor(bundleIdentifier: bundle).aeDesc else { return false }
        func check() -> OSStatus { AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask) }
        var status = check()
        // 안 떠 있으면 허락을 잴 수 없다 (procNotFound). 띄우고 잠깐 기다린다 — 쉬면 스스로 내려간다.
        if status == OSStatus(procNotFound),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            for _ in 0..<20 where status == OSStatus(procNotFound) {
                Thread.sleep(forTimeInterval: 0.05)
                status = check()
            }
        }
        return status == noErr
    }

    /// 목록을 연다. 같은 창에 있던 것은 같은 창에 탭으로 모은다 (`ReopenLayout.groups`).
    ///
    /// 처음 실패에서 멈추고 상자로 말한다 — 권한이 없으면 나머지도 다 같은 이유로 안 되고,
    /// 이 앱의 실패는 삑 소리 하나로 삼키지 않는다 (`TerminalJump.report`). 탭으로 못 붙인
    /// 것은 새 창으로 열고, 다 연 뒤에 왜 그랬는지 한 번 말한다.
    func openAll(_ list: [SavedSession]) {
        let groups = ReopenLayout.groups(list)
        let wantsTabs = groups.contains { $0.count > 1 }
        // 권한을 묻는 시스템 상자를 띄운다. 이번 열기는 기다리지 않고 새 창으로 간다.
        if wantsTabs && !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        // System Events 를 부릴 허락도 따로다. 아직이면 묻는 상자를 **뒤에서** 띄운다 — 메인
        // 스레드에서 물으면 사람이 답할 때까지(안 답하면 2분) 메뉴바가 언다 (실측 -1712).
        if wantsTabs && !Self.mayAutomateSystemEvents(ask: false) {
            DispatchQueue.global().async { _ = Self.mayAutomateSystemEvents(ask: true) }
        }
        Self.log("openAll groups=\(groups.map { $0.map { "\($0.name)@\($0.window.map(String.init) ?? "-").\($0.tab.map(String.init) ?? "-")" } }) "
                 + "ax=\(AXIsProcessTrusted()) se=\(Self.mayAutomateSystemEvents(ask: false))")
        var allTabbed = true
        for group in groups {
            var window: Int?
            for saved in group {
                let (outcome, opened, tabbed) = open(saved, beside: window)
                Self.log("open \(saved.name) beside=\(window.map(String.init) ?? "-") -> \(outcome) window=\(opened.map(String.init) ?? "-") tabbed=\(tabbed)")
                allTabbed = allTabbed && tabbed
                switch outcome {
                case .opened:
                    window = opened
                case .notPermitted:
                    Self.alert(S.permissionTitle, S.permissionBody)
                    return
                case .failed(let why):
                    Self.alert(S.reopenFailedTitle, "\(saved.name): \(why)")
                    return
                }
            }
        }
        if !allTabbed { Self.askForTabPermission() }
    }

    /// 탭으로 못 묶은 까닭을 말하고, 설정을 바로 열 단추를 준다.
    ///
    /// 시스템의 권한 상자는 앱마다 한 번만 뜬다 — 한 번 지나가면 다시 불러도 조용하다
    /// (실측 2026-11-15, 로컬 빌드). 그래서 길만 말하지 않고 그 자리를 열어 준다.
    private static func askForTabPermission() {
        NSApp.activate(ignoringOtherApps: true)
        let box = NSAlert()
        box.messageText = S.reopenTabsTitle
        box.informativeText = S.reopenTabsBody
        box.addButton(withTitle: S.reopenOpenSettings)
        box.addButton(withTitle: S.okButton)
        guard box.runModal() == .alertFirstButtonReturn,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
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

    /// Terminal 의 창마다 탭마다 tty 를 묻는다. 못 물으면 빈 것.
    ///
    /// **메인 스레드에서 돈다.** 그래서 Terminal 이 안 떠 있으면 묻지 않고(물으면 Terminal 이
    /// 켜진다), 자동화 권한을 아직 안 받았으면 묻지 않고(상자가 훑기 한가운데 뜬다),
    /// 대답이 늦으면 2초에서 끊는다. 탭이 없는 창(설정 창 등)은 건넌다.
    static func terminalLayout() -> [String: (window: Int, tab: Int)] {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty,
              Notifier.mayAutomateTerminal() else { return [:] }
        let script = """
        with timeout of 2 seconds
            tell application "Terminal"
                set out to ""
                repeat with i from 1 to count windows
                    try
                        set w to window i
                        set b to bounds of w
                        set out to out & i & " " & (id of w) & " " & (item 1 of b) & "," & (item 2 of b) & "," & (item 3 of b) & "," & (item 4 of b) & " " & (tty of tab 1 of w) & linefeed
                    end try
                end repeat
                return out
            end tell
        end timeout
        """
        var error: NSDictionary?
        guard let text = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
              error == nil else { log("layout failed \(error ?? [:])"); return [:] }
        return ReopenLayout.groups(of: ReopenLayout.parse(text, onScreen: onScreenWindows()))
    }

    /// 지금 그려지고 있는 창 번호들. 묶음 뒤에 숨은 탭은 여기 없다. 화면 녹화 권한 없이 읽힌다.
    private static func onScreenWindows() -> Set<Int> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(info.compactMap { $0[kCGWindowNumber as String] as? Int })
    }

    static func saved(from session: Session, layout: [String: (window: Int, tab: Int)]) -> SavedSession? {
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
        var out = SavedSession(source: session.source, id: session.id, name: session.name,
                               cwd: session.cwd, accountRoot: session.accountRoot.path,
                               background: background, args: keep, droppedArgs: dropped,
                               state: session.state.raw, lastSeen: Date())
        // tmux 안이면 pane 의 tty 라 어느 탭도 그 값을 안 갖는다. 보고 있는 창의 tty 로 건넌다.
        if !background, var tty = TerminalJump.ttyPath(pid: session.hostPid) {
            if layout[tty] == nil, let client = Tmux.pane(forTTY: tty)?.clientTTY { tty = client }
            out.window = layout[tty]?.window
            out.tab = layout[tty]?.tab
        }
        return out
    }

    private static func defaultRoot(for source: String) -> String {
        let home = NSHomeDirectory()
        return source == "codex" ? "\(home)/.codex" : "\(home)/.claude"
    }

    // MARK: 파일

    /// 다시 열기가 어디서 어긋났는지 남는 자리. 저장·열기 때만 적으므로 작다.
    static func log(_ line: String) {
        let url = defaultFile.deletingLastPathComponent().appendingPathComponent("reopen.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

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

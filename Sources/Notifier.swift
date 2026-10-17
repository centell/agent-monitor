import AppKit
import UserNotifications

/// 세션이 사람 손을 기다리기 시작하면 맥 알림을 띄운다.
///
/// 전에는 Claude Code 의 Stop 훅이 이 일을 했다 (`terminal-notifier`). 훅은 그 터미널
/// 하나만 알아서 Codex·앱 세션은 못 봤고, 눌러서 가는 길도 Terminal.app 에서만 섰다.
/// 이 앱은 이미 모든 세션의 상태를 읽고 있고 **그 세션으로 가는 문**(`SessionJump`)도
/// 가지고 있으므로, 알림은 여기서 내는 것이 맞다.
///
/// **판정은 전환으로만 한다.** 「지금 idle 이다」로 알리면 갱신마다 울린다. 직전 판과
/// 견줘 바뀐 순간에만 한 번 알린다.
///
/// 한계: 들여다보는 간격(갱신 주기) 사이에 끝나고 다시 일을 시작한 턴은 못 본다.
/// 훅은 그 순간에 불리지만 이 앱은 보러 갈 때만 안다. 세션이 이어지는 판에도 하나를
/// 놓친다 — 줄의 id 가 새 세션 것으로 바뀌어 그 판은 «처음 본 세션» 이 된다.
/// 승인을 거절해 턴이 끝난 것(waiting → idle)은 «일을 마침» 으로 치지 않는다 —
/// 거절한 사람은 이미 거기 있다.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    static let shared = Notifier()

    /// 알림을 누르면 그 세션을 찾아 준다. 누르는 순간의 목록에서 찾는다.
    ///
    /// id 와 창을 쥔 pid 를 **둘 다** 넘긴다. 세션이 이어지면 줄의 id 는 다음 세션의 것으로
    /// 바뀌지만 창은 앞선 프로세스가 계속 쥐고 있어서(`hostPid`), id 로 못 찾으면 pid 로 찾는다.
    var sessionLookup: (_ id: String, _ hostPid: Int32) -> Session? = { _, _ in nil }

    private let settings = Settings.shared
    /// 직전 판의 상태. 처음 본 세션은 여기 없으므로 알리지 않는다 —
    /// 앱을 켜는 순간 기다리던 세션 전부가 한꺼번에 울리면 안 된다.
    private var previous: [String: SessionState] = [:]
    /// `UNUserNotificationCenter` 는 번들 안에서만 쓸 수 있다. `--list` 처럼 번들 밖에서
    /// 도는 실행에서 건드리면 그 자리에서 죽는다.
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    /// 앱이 뜰 때 한 번 부른다.
    func start() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = self
        requestIfWanted()
    }

    /// 켜져 있으면 권한을 묻는다. 이미 답한 뒤라면 macOS 는 다시 묻지 않고 그 답을 돌려준다.
    ///
    /// 꺼 둔 사람에게는 묻지 않는다 — 쓰지도 않을 권한 상자가 첫 실행에 뜨면 안 된다.
    func requestIfWanted() {
        guard available, settings.notifyDone || settings.notifyWaiting else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 매 갱신마다 부른다.
    func observe(_ sessions: [Session]) {
        defer { previous = Dictionary(sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a }) }
        guard available, settings.notifyDone || settings.notifyWaiting else { return }

        for session in sessions {
            guard let before = previous[session.id], before != session.state else { continue }
            switch (before, session.state) {
            case (.busy, .idle), (.shell, .idle):
                if settings.notifyDone { post(session, title: S.notifyDoneTitle) }
            case (_, .waiting):
                if settings.notifyWaiting { post(session, title: S.notifyWaitingTitle) }
            default:
                break
            }
        }
    }

    private func post(_ session: Session, title: String) {
        // 그 세션의 탭을 지금 보고 계시면 울리지 않는다. 보고 있는 것을 알려 봐야 소음이다.
        guard !isInFront(session) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = session.name
        if let reason = session.reason { content.body = reason }
        content.sound = .default
        content.userInfo = ["session": session.id, "hostPid": Int(session.hostPid)]
        // id 를 세션으로 둔다 — 같은 세션의 알림이 쌓이지 않고 새것으로 갈린다.
        let request = UNNotificationRequest(identifier: session.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 이 세션의 탭이 맨 앞 Terminal 창에서 선택된 탭인가.
    ///
    /// 훅은 «터미널 앱이 맨 앞인가» 만 봐서, 같은 터미널의 다른 탭을 보고 계셔도
    /// 침묵했다. 여기서는 탭까지 맞춰 본다. 알릴 때만 부르므로 AppleScript 값이 싸다.
    /// 못 재면 앞에 없다고 친다 — 놓치는 것보다 한 번 더 울리는 편이 낫다.
    ///
    /// **메인 스레드에서 돈다.** 그래서 둘을 막는다 — 자동화 권한을 아직 안 받았으면 묻지
    /// 않고 건너뛰고(묻는 상자가 갱신 한가운데 뜨면 앱이 답을 기다리며 언다), Terminal 이
    /// 대답을 안 하면 1초에서 끊는다 (기본은 2분이라 그동안 메뉴바가 언다).
    private func isInFront(_ session: Session) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal",
              var tty = TerminalJump.ttyPath(pid: session.hostPid),
              Self.mayAutomateTerminal() else { return false }
        // tmux 안이면 세션의 tty 는 pane 의 것이라 어느 탭도 그 값을 안 갖는다.
        // 그 pane 을 보고 있는 창의 tty 로 바꿔 잰다 (`TerminalJump` 와 같은 다리).
        if let client = Tmux.pane(forTTY: tty)?.clientTTY { tty = client }
        let script = """
        with timeout of 1 second
            tell application "Terminal" to return tty of selected tab of front window
        end timeout
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil && result?.stringValue == tty
    }

    /// 묻지 않고, 이미 허락받았는지만 본다.
    private static func mayAutomateTerminal() -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Terminal")
        guard let desc = target.aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false) == noErr
    }

    // MARK: UNUserNotificationCenterDelegate

    /// 앱이 앞에 있어도 띄운다. 이 앱은 Dock 이 없어 «앞에 있다» 가 사람이 보고 있다는
    /// 뜻이 아니다 — 메뉴를 막 닫은 직후에도 그렇게 잡힌다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// 누르면 그 세션으로 간다. 목록에서 누른 것과 같은 길이다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = response.notification.request.content.userInfo["session"] as? String else { return }
        let hostPid = Int32(response.notification.request.content.userInfo["hostPid"] as? Int ?? 0)
        DispatchQueue.main.async { [weak self] in
            guard let session = self?.sessionLookup(id, hostPid), SessionJump.canJump(session) else { return }
            SessionJump.report(SessionJump.jump(to: session), sessionName: session.name)
        }
    }
}

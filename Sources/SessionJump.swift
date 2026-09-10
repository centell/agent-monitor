import AppKit
import Foundation

/// 세션을 눌렀을 때 **그 세션이 사는 곳**으로 간다.
///
/// 처음에는 터미널 창만 알았다. 그러나 세션이 터미널에만 사는 것은 아니다 —
/// Claude 앱 세션은 tty 가 없어서 「눌러도 아무 일이 없는 줄」이 되어 있었다.
/// 터미널이 아니라 **문이 없던 것**이 문제였다.
///
/// 그래서 문을 순서대로 두드린다:
///   ① tty 가 있으면 그 터미널 창으로 (지금까지 하던 것)
///   ② 딥링크가 있으면 그것을 연다 — 앱이 세션까지 짚어 주면 제일 좋고,
///      못 짚더라도 **앱 자체는 반드시 앞으로 나온다.** 최악이 「아무 일 없음」이 아니게 된다.
enum SessionJump {

    /// 눌러서 갈 수 있는가. 목록을 그릴 때 쓰므로 권한을 건드리지 않는다.
    ///
    /// **창은 `hostPid` 가 쥐고 있다.** 세션이 이어지면 대화는 daemon 쪽 프로세스로 옮겨
    /// 가지만 터미널 창은 앞선 프로세스에 그대로 남으므로, 자기 pid 로 찾으면 못 찾는다.
    ///
    /// 물려받은 창이 없는 백그라운드 세션은 갈 수 없다. 그쪽 tty 는 `bg-pty-host` 가 만든
    /// pty 라 그것을 가진 창이 세상에 없다. 「tty 가 있으니 갈 수 있다」로만 재면 눌러도
    /// 아무 일이 없는 줄이 생기고, 그건 못 가는 것보다 나쁘다 — 사람은 자기가 잘못
    /// 눌렀다고 생각하게 된다.
    static func canJump(_ session: Session) -> Bool {
        guard !(session.isBackground && session.continuedFromPid == nil) else { return false }
        return TerminalJump.canJump(pid: session.hostPid) || session.deepLink != nil
    }

    /// 이 세션을 눌렀을 때 보여 줄 안내.
    static func hint(for session: Session) -> String {
        TerminalJump.canJump(pid: session.hostPid) ? S.jumpHint : S.jumpHintApp
    }

    @discardableResult
    static func jump(to session: Session) -> TerminalJump.Outcome {
        // 터미널이 있으면 터미널이 먼저다. 사람이 실제로 타이핑하던 자리다.
        if TerminalJump.canJump(pid: session.hostPid) {
            return TerminalJump.jump(pid: session.hostPid)
        }
        guard let url = session.deepLink else { return .noTTY }
        // 스킴을 등록한 앱이 뜨면서 앞으로 나온다. 세션까지 짚어 주는지는 앱에 달렸다.
        return NSWorkspace.shared.open(url) ? .moved : .failed(S.errNoHandler(url.scheme ?? "?"))
    }

    static func report(_ outcome: TerminalJump.Outcome, sessionName: String) {
        TerminalJump.report(outcome, sessionName: sessionName)
    }
}

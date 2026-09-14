import AppKit
import SwiftUI

/// 애드온이 내놓은 창 하나의 수명.
///
/// 이 저장소는 **그 안에 무엇이 그려지는지 모른다.** `Addon.extraWindowContent` 가
/// `AnyView` 로 건네주는 것을 받아 창에 담을 뿐이고, 제목조차 애드온이 낸 이름을 쓴다.
/// `SettingsWindowController` 와 같은 꼴이되, 이쪽은 탭 묶음이 아니라 창 하나다.
///
/// 창을 한 번 만들어 두고 다시 쓴다. 닫았다 열 때마다 새로 지으면 그때까지 접어 둔
/// 것·굴려 둔 자리가 매번 처음으로 돌아간다.
final class AddonWindowController: NSObject, NSWindowDelegate {

    static let shared = AddonWindowController()
    private var window: NSWindow?

    /// 애드온이 창을 내놓았을 때만 연다. 안 내놓았으면 조용히 아무 일도 안 한다 —
    /// 부를 자리(`MenuBarController`)가 이미 같은 것을 보고 항목을 세우므로 여기까지
    /// 올 일이 없으나, 없는 것을 열려 했을 때 창 대신 오류가 뜨는 편이 더 나쁘다.
    func show(sessionsProvider: @escaping () -> [Session]) {
        guard let content = Addon.extraWindowContent else { return }

        if window == nil {
            let hosting = NSHostingController(rootView: content(sessionsProvider))
            let w = NSWindow(contentViewController: hosting)
            w.title = Addon.extraWindowLabel ?? ""
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(NSSize(width: 760, height: 560))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        guard let w = window else { return }
        AppActivation.enter(w)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        AppActivation.leave(w)
    }
}

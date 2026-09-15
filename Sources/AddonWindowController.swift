import AppKit
import SwiftUI

/// 애드온이 내놓은 창들의 수명.
///
/// 이 저장소는 **그 안에 무엇이 그려지는지 모른다.** `Addon.Window` 가 `AnyView` 로
/// 건네주는 것을 받아 창에 담을 뿐이고, 제목조차 애드온이 낸 이름을 쓴다.
/// `SettingsWindowController` 와 같은 꼴이되, 이쪽은 탭 묶음이 아니라 창들이다.
///
/// 창을 한 번 만들어 두고 다시 쓴다. 닫았다 열 때마다 새로 지으면 그때까지 접어 둔
/// 것·굴려 둔 자리가 매번 처음으로 돌아간다.
///
/// **애드온마다 제 창을 따로 기억한다.** 전에는 애드온이 하나라 창도 하나였다. 여럿이
/// 되면 하나로는 안 되는데, 그냥 하나를 돌려 쓰면 두 번째 애드온의 창을 여는 순간
/// 첫 번째가 그 자리에 그대로 있고 안쪽만 바뀐 것처럼 보인다.
final class AddonWindowController: NSObject, NSWindowDelegate {

    static let shared = AddonWindowController()

    /// 애드온이 낸 `key` 로 찾는다. 파일 이름이 아니라 애드온이 정한 이름이라,
    /// 번들을 다시 깔아도 앉혀 둔 자리를 잃지 않는다.
    private var windows: [String: NSWindow] = [:]

    func show(_ spec: Addon.Window, sessionsProvider: @escaping () -> [Session]) {
        if windows[spec.key] == nil {
            let hosting = NSHostingController(rootView: spec.content(sessionsProvider))
            // **창 크기는 사람이 정한다.** 기본값(`.preferredContentSize`)은 SwiftUI 내용의
            // 크기를 창에 그대로 전달해서, 안에서 줄이 하나 늘면 창이 그만큼 자란다 —
            // 안내 한 줄이 떴다고 보고 있던 창이 위아래로 늘어나는 것을 실제로 봤다.
            // 내용이 넘치는 몫은 안쪽 스크롤이 받는다.
            hosting.sizingOptions = []
            let w = NSWindow(contentViewController: hosting)
            w.title = spec.label
            // **최소화를 둔다.** 설정창에서 값을 가져왔는데 그쪽은 고치고 닫는 자리라
            // 없어도 됐다. 켜 두고 보는 창에는 노란 단추와 `⌘M` 이 있어야 맞다.
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 760, height: 560))
            w.isReleasedWhenClosed = false
            w.delegate = self

            // 앉혀 둔 자리를 기억한다. 켜 두고 보는 창이라 매번 가운데로 돌아오면
            // 매번 다시 옮겨야 한다.
            //
            // **이름에 `key` 를 섞는다.** 안 섞으면 애드온 둘의 창이 같은 자리를 물고
            // 서로를 덮어쓴다.
            let name = "AddonWindow-\(spec.key)"

            // **두 손이 따로 있다.**
            //
            // `setFrameAutosaveName` 은 *적어 두기* 만 시작한다. 그것만 걸어 두면 자리는
            // 꼬박꼬박 저장되는데 다시 열 때 아무도 안 읽어, 창은 늘 `center()` 가 놓은
            // 데서 뜬다 — 저장된 값이 멀쩡히 있는데도.
            //
            // 실측: 창을 (333, 244) 에 놓고 앱을 내렸다 올렸더니 `defaults` 에는
            // `NSWindow Frame AddonWindow-Work = "333 22 760 592 …"` 가 적혀 있었는데
            // 창은 (2131, 520) 에 떴다. *읽는 손*(`setFrameUsingName`)이 빠져 있었다.
            w.setFrameAutosaveName(name)

            // 읽어서 못 앉히면 그때만 가운데로. **순서가 거꾸로면 안 된다** —
            // `center()` 를 나중에 부르면 읽어 온 자리를 바로 덮는다.
            if !w.setFrameUsingName(name) { w.center() }
            windows[spec.key] = w
        }
        guard let w = windows[spec.key] else { return }
        AppActivation.enter(w)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        AppActivation.leave(w)
    }
}

import AppKit

/// Dock 아이콘이 없는 앱(`LSUIElement`)이 제 창을 앞으로 끌어오는 일.
///
/// `activate(ignoringOtherApps:)` 만으로는 부족하다 — 액세서리 앱은 활성화 대상이
/// 아니어서, 창은 만들어지는데 맨 앞 앱은 그대로 Terminal 이었다. 그래서 창이 떠 있는
/// 동안만 보통 앱으로 바꿨다가 되돌린다. 그동안은 Dock 과 `⌘Tab` 에도 나타나므로
/// 창을 다시 찾기도 쉬워진다.
///
/// **어느 창이 떠 있는지 적어 두는 까닭**: 창이 둘이 되었기 때문이다. 닫는 쪽이 저 혼자
/// 판단해 메뉴바로 돌아가 버리면 아직 떠 있는 다른 창이 그 자리에서 뒤로 밀린다.
///
/// 수를 세지 않고 **창을 담는다.** 메뉴에서 같은 창을 두 번 누르면 여는 쪽은 두 번
/// 불리는데 닫는 쪽은 한 번뿐이라, 수로 세면 그 판부터 영영 0 이 되지 않는다.
/// 집합은 같은 것을 두 번 넣어도 하나다.
enum AppActivation {

    private static var open: Set<ObjectIdentifier> = []

    /// 이 창을 앞으로 끌어온다. 이미 떠 있던 창이어도 안전하다.
    ///
    /// ⚠ **여기 태우는 창은 해제되지 않아야 한다.** 지금 두 창 모두 싱글턴이 강하게 쥐고
    /// `isReleasedWhenClosed = false` 라 그 성질이 지켜진다. 「닫히면 풀리는」 창을 이 손에
    /// 태우면 두 가지가 조용히 깨진다 — 해제된 창의 자취가 집합에 남아 집합이 영영 안 비고
    /// 앱이 Dock 에 갇히거나, 그 자리에 새 창이 잡혀 같은 자취로 읽혀 넣기가 무시된다.
    static func enter(_ window: NSWindow) {
        open.insert(ObjectIdentifier(window))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 이 창이 닫혔다. 남은 것이 없을 때만 메뉴바에만 사는 앱으로 돌아간다.
    static func leave(_ window: NSWindow) {
        open.remove(ObjectIdentifier(window))
        guard open.isEmpty else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

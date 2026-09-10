import AppKit

/// 화면 구석에 붙여 두는 반투명 패널.
///
/// **껍데기만 맡는다.** 무엇이 그려지는지는 모르고, 모양·이동·항상 위로·크기 맞추기만
/// 한다. 내용은 `FloatingPanelController` 가 만들어 `setBody` 로 건넨다.
///
/// 평범한 창이 아니라 `NSPanel` 인 이유가 있다. 이 앱은 Dock 없이 사는 액세서리라
/// **앞으로 나올 수도, 되돌아갈 수도 없다** — 창이 앞을 뺏으면 사용자는 쓰던 앱으로
/// 돌아갈 길을 잃는다. `.nonactivatingPanel` 은 눌러도 앞을 안 뺏으므로, 상주하는
/// 창에는 이것이 유일하게 안전한 모양이다.
final class FloatingPanel: NSPanel {

    /// 항상 위로 둘 것인가.
    ///
    /// 끄면 보통 창 층으로 내려간다. 액세서리 앱이라 다른 앱 뒤로 들어가면 눌러서
    /// 꺼낼 방법이 없으므로, **되돌아오는 문은 메뉴바에 있다** (`상시 창 닫기/열기`).
    var isAlwaysOnTop: Bool = true {
        didSet { level = isAlwaysOnTop ? .floating : .normal }
    }

    private let effect = NSVisualEffectView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        // 액세서리 앱에게 «비활성» 은 예외가 아니라 평상시다. 기본값(숨김)을 그대로
        // 두면 창이 뜬 그 순간부터 사라져 있는다.
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true      // 몸통 아무 데나 잡아 끈다
        // 스페이스를 옮겨도 남는다. 모니터를 여러 대 쓰는 자리에서 「방금 그 창 어디 갔지」를
        // 없앤다. `ignoresCycle` 로 ⌘` 차례에는 끼지 않는다 — 이건 문서가 아니라 계기판이다.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        contentView = effect
    }

    /// 몸통을 갈아 끼우고 창 크기를 내용에 맞춘다.
    ///
    /// **붙여 둔 구석은 그대로 두고 반대편으로만 자란다.** 우하단에 붙여 두셨는데 아래로
    /// 자라면 세션이 하나 늘 때마다 창이 화면 밖으로 내려간다. 어느 구석에 두셨는지는
    /// 창이 화면의 어느 사분면에 앉아 있는지로 읽는다 — 따로 여쭐 것이 없다.
    func setBody(_ body: NSView) {
        let wanted = body.frame.size
        let visible = (screen ?? NSScreen.main)?.visibleFrame
        // 화면을 넘어서까지 자라지는 않는다. 넘으면 그때만 창 안에서 굴린다 —
        // 평소에 스크롤 막대가 없는 편이 구석에서 조용하다.
        let ceiling = max(120, (visible?.height ?? wanted.height) - 40)
        let height = min(wanted.height, ceiling)

        effect.subviews.forEach { $0.removeFromSuperview() }
        if wanted.height > ceiling {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: wanted.width, height: height))
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.autoresizingMask = [.width, .height]
            scroll.documentView = body
            effect.addSubview(scroll)
            // 몸통이 뒤집힌 좌표계라 원점이 맨 위다. 손이 필요한 줄부터 보여야 한다.
            scroll.contentView.scroll(to: .zero)
        } else {
            body.setFrameOrigin(.zero)
            body.autoresizingMask = [.width, .height]
            effect.addSubview(body)
        }
        resize(to: NSSize(width: wanted.width, height: height))
    }

    // MARK: 자리

    /// 처음 띄울 자리 — 주 화면 우하단.
    static func defaultFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 300, height: 160)
        return NSRect(x: visible.maxX - size.width - 24,
                      y: visible.minY + 24,
                      width: size.width,
                      height: size.height)
    }

    private func resize(to size: NSSize) {
        let old = frame
        var origin = old.origin
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            if old.midX > visible.midX { origin.x = old.maxX - size.width }   // 오른쪽에 붙었다
            if old.midY > visible.midY { origin.y = old.maxY - size.height }  // 위쪽에 붙었다
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
        clampIntoScreen()
    }

    /// 자란 끝이 화면 밖으로 나갔으면 도로 들여놓는다.
    ///
    /// 사분면으로 읽은 «붙인 구석» 이 늘 맞지는 않는다 — 화면 한가운데 두셨다가
    /// 세션이 열 개로 늘면 어느 쪽으로 자라도 끝이 넘친다. 그때 조용히 잘려 있는 것보다
    /// 들여놓는 편이 낫다.
    func clampIntoScreen() {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let margin: CGFloat = 8
        var origin = frame.origin
        if frame.width <= visible.width - margin * 2 {
            origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - frame.width - margin)
        }
        if frame.height <= visible.height - margin * 2 {
            origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - frame.height - margin)
        }
        if origin != frame.origin { setFrameOrigin(origin) }
    }
}

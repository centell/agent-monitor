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

    /// 바탕의 결과 진하기. 진하기 0 이면 바탕이 없다.
    var backdropStyle: PanelBackdropStyle = .blur { didSet { applyBackdrop() } }
    var backdropAlpha: Double = 1 { didSet { applyBackdrop() } }

    /// 창 가장자리와 목록 사이 여백. 다음 `setBody` 부터 적용된다.
    var padding: CGFloat = 6

    /// 바탕과 내용을 **형제로** 둔다.
    ///
    /// 예전에는 내용을 흐림 뷰 **안에** 넣었다. 「바탕 없음」을 만들려고 흐림 뷰를 숨겼더니
    /// 그 안에 든 줄들까지 함께 사라졌다 — 시험용 하네스에서 실제로 겪었고, 하마터면
    /// 「바탕을 없애면 글자가 안 보인다」는 엉뚱한 결론을 낼 뻔했다.
    /// 형제로 두면 바탕만 걷어낼 수 있다.
    private let backing = NSView()
    /// 흐림 결. 진하기는 `alphaValue` 로 준다 — 몸통이 형제라 글자는 함께 흐려지지 않는다.
    private let effect = NSVisualEffectView()
    /// 단색 결. 흐림과 **둘 중 하나만** 보인다.
    private let plate = NSView()

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

        backing.wantsLayer = true
        backing.layer?.cornerRadius = 10
        backing.layer?.masksToBounds = true
        contentView = backing

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.frame = backing.bounds
        backing.addSubview(effect)

        plate.wantsLayer = true
        plate.autoresizingMask = [.width, .height]
        plate.frame = backing.bounds
        backing.addSubview(plate)
        applyBackdrop()
    }

    /// 바탕만 갈아 끼운다. 내용은 형제라 건드리지 않는다.
    ///
    /// 진하기가 0 에 가까우면 **그림자도 끈다.** 바탕이 없는데 그림자만 남으면 아무것도
    /// 없는 자리에 네모난 그늘이 걸린다.
    private func applyBackdrop() {
        let alpha = min(max(backdropAlpha, 0), 1)
        let bare = alpha < 0.02

        effect.isHidden = bare || backdropStyle != .blur
        effect.alphaValue = alpha

        plate.isHidden = bare || backdropStyle != .solid
        plate.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(alpha).cgColor

        hasShadow = !bare
        invalidateShadow()
    }

    /// 몸통을 갈아 끼우고 창 크기를 내용에 맞춘다.
    ///
    /// **붙여 둔 구석은 그대로 두고 반대편으로만 자란다.** 우하단에 붙여 두셨는데 아래로
    /// 자라면 세션이 하나 늘 때마다 창이 화면 밖으로 내려간다. 어느 구석에 두셨는지는
    /// 창이 화면의 어느 사분면에 앉아 있는지로 읽는다 — 따로 여쭐 것이 없다.
    func setBody(_ body: NSView) {
        // 목록을 창 안쪽으로 들여놓는다. 붙여 두면 머리줄이 창 모서리에 닿는다.
        let inset = max(0, padding)
        let wanted = NSSize(width: body.frame.width + inset * 2,
                            height: body.frame.height + inset * 2)
        let visible = (screen ?? NSScreen.main)?.visibleFrame
        // 화면을 넘어서까지 자라지는 않는다. 넘으면 그때만 창 안에서 굴린다 —
        // 평소에 스크롤 막대가 없는 편이 구석에서 조용하다.
        let ceiling = max(120, (visible?.height ?? wanted.height) - 40)
        let size = NSSize(width: wanted.width, height: min(wanted.height, ceiling))

        // **자리·크기·내용을 한 번에 바꾼다.**
        //
        // 처음에는 내용을 먼저 갈아 끼우고 창을 나중에 늘렸다. 그 사이 한 프레임 동안
        // 새 몸통이 **옛 크기의 창** 안에 놓였다가 창과 함께 늘어나, 줄 수가 바뀔 때마다
        // 글자가 겹쳐 보였다. 「기다리는 것만」에서 특히 그랬다 — 세션이 대기와 작업을
        // 오갈 때마다 줄 수가 바뀌므로 그 한 프레임이 계속 보인다.
        //
        // 그래서 **하나의 실행 흐름 안에서** 자리·크기·내용을 다 바꾸고 마지막에 한 번만
        // 그린다. `display: false` 로 미뤄 두는 것이 그 열쇠다.
        //
        // ⚠ `disableScreenUpdatesUntilFlush()` 를 부르지 않는다. 이 자리에 딱 맞아 보이지만
        // **macOS 15부터 아무 일도 하지 않는 빈 함수**다. 한 번 넣었다가 「막아 두었다」고
        // 믿을 뻔했다 — 실제로 깜빡임을 없앤 것은 아래 두 가지다.
        setFrame(NSRect(origin: anchoredOrigin(for: size), size: size), display: false)

        backing.subviews.filter { $0 !== effect && $0 !== plate }.forEach { $0.removeFromSuperview() }
        if wanted.height > ceiling {
            let scroll = NSScrollView(frame: NSRect(x: inset, y: inset,
                                                    width: size.width - inset * 2,
                                                    height: size.height - inset * 2))
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.documentView = body
            backing.addSubview(scroll)
            // 몸통이 뒤집힌 좌표계라 원점이 맨 위다. 손이 필요한 줄부터 보여야 한다.
            scroll.contentView.scroll(to: .zero)
        } else {
            body.setFrameOrigin(NSPoint(x: inset, y: inset))
            backing.addSubview(body)
        }
        // 몸통에 `autoresizingMask` 를 달지 않는다. 목록이 바뀔 때마다 통째로 다시 만드니
        // 저절로 늘어날 일이 없고, 달아 두면 창이 늘 때 **줄은 제자리인데 그릇만** 늘어나
        // 글자가 밀린다. 창 크기를 바꾸는 손잡이가 없으므로 다른 쓸모도 없다.
        displayIfNeeded()
        // 테두리 없는 창은 크기가 바뀌어도 **그림자가 옛 크기로 남는다.** 줄어든 창 주위에
        // 유령 윤곽이 걸려 있으면 그것부터 「깨졌다」로 읽힌다. 다시 그리게 시킨다.
        invalidateShadow()
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

    /// 새 크기로 앉을 자리.
    ///
    /// **붙여 둔 구석은 지킨다.** 어느 구석에 두셨는지는 창이 화면의 어느 사분면에 앉아
    /// 있는지로 읽는다 — 따로 여쭐 것이 없다.
    ///
    /// 그러고도 끝이 화면을 넘으면 도로 들여놓는다. 사분면으로 읽은 구석이 늘 맞지는
    /// 않기 때문이다 — 한가운데 두셨다가 세션이 열 개로 늘면 어느 쪽으로 자라도 넘치고,
    /// 모니터를 빼면 적어 둔 자리 자체가 화면 밖이 된다.
    ///
    /// 자리를 **하나의 `setFrame` 안에서** 정해야 한다. 옮기고 나서 또 옮기면 그 사이가
    /// 화면에 나가고, 그게 곧 깜빡임이다.
    private func anchoredOrigin(for size: NSSize) -> NSPoint {
        let old = frame
        var origin = old.origin
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return origin }
        if old.midX > visible.midX { origin.x = old.maxX - size.width }   // 오른쪽에 붙었다
        if old.midY > visible.midY { origin.y = old.maxY - size.height }  // 위쪽에 붙었다

        let margin: CGFloat = 8
        if size.width <= visible.width - margin * 2 {
            origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        }
        if size.height <= visible.height - margin * 2 {
            origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin)
        }
        return origin
    }
}

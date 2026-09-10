import AppKit

/// 상시 창에서 쓰는 **직접 그리는 툴팁**.
///
/// AppKit 이 공짜로 주는 `NSView.toolTip` 을 상시 창에서는 못 쓴다. 하네스로 실제
/// 화면에서 재 본 결과다 (액세서리 앱 + `.borderless` + `.nonactivatingPanel` 을 그대로
/// 재현하고, 커서를 밖에서 안으로 걸어 넣어 찍었다):
///
/// | 판 | canBecomeKey | isKey | 앱 활성 | 강조 | 툴팁 |
/// |---|---|---|---|---|---|
/// | 지금 모양       | false | false | false | 켜짐 | **안 뜸** |
/// | 키로 띄움       | true  | true  | true  | 켜짐 | 뜸 |
/// | canBecomeKey 만 | true  | false | false | 켜짐 | **안 뜸** |
/// | `makeKey()` 만  | true  | true  | true  | —    | (앱이 깨어남) |
///
/// 읽는 법은 셋이다. **트래킹은 멀쩡하다** — 마우스 올림 강조는 비활성 앱에서도 켜진다
/// (`.activeAlways`). **`canBecomeKey` 를 여는 것으로는 안 고쳐진다** — 세 번째 줄이
/// 그것이다. 그리고 툴팁이 뜬 판은 전부 **앱이 앞으로 나온** 판이며, `makeKey()` 만
/// 불러도 앱이 활성이 된다. 즉 AppKit 툴팁을 얻는 길은 「눌러도 앞을 안 뺏는다」를
/// 깨는 길뿐이고, 그 값은 치를 수 없다 — 그 약속이 상주하는 창의 존재 이유다.
///
/// 그래서 툴팁을 우리가 그린다. 이미 살아 있는 트래킹 위에 지연 타이머와 작은 창을
/// 얹는 것뿐이라 새로 만드는 것은 그릇 하나다.
///
/// **메뉴는 건드리지 않는다.** 메뉴 트래킹 중에는 AppKit 툴팁이 멀쩡히 뜨므로,
/// 거기서는 지금까지 하던 것을 그대로 둔다 (`MenuBarController`).
final class RowTooltip {

    static let shared = RowTooltip()
    private init() {}

    /// 지금 떠 있는 창. 하나만 둔다 — 줄을 빠르게 훑고 지나가면 여러 개가 겹쳐 남는다.
    private var panel: NSPanel?
    private var timer: Timer?
    /// 지금 예약·표시의 주인인 줄. 다른 줄이 끼어들면 앞의 예약은 버린다.
    private weak var owner: NSView?

    /// 뜨기까지 기다리는 시간.
    ///
    /// 메뉴 쪽에서 `NSInitialToolTipDelay` 로 정해 둔 값과 같다 (`MenuBarController`).
    /// 두 화면이 같은 줄을 그리므로 기다리는 느낌도 같아야 한다. 0.3초는 지나가는 줄마다
    /// 튀어나와 시끄러웠고, 시스템 기본값(약 3초)은 이 글을 보려고 마우스를 올린 사람에게
    /// 너무 길었다.
    private let delay: TimeInterval = 0.8

    /// 가로 최대. 넘으면 접는다. 툴팁이 화면을 가로지르면 그 뒤가 안 보인다.
    private let maxWidth: CGFloat = 360

    // MARK: 예약과 걷기

    /// 이 줄에 마우스가 들어왔다. 잠시 뒤 띄운다.
    func schedule(_ text: String, for view: NSView) {
        guard !text.isEmpty else { return }
        cancel()
        owner = view
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self, weak view] _ in
            guard let self, let view, view.window != nil else { return }
            self.show(text)
        }
        // 목록이 다시 그려지는 동안에도 시간이 흘러야 한다. 기본 모드에만 두면 창을
        // 끄는 중이나 메뉴가 열린 동안 타이머가 멈춘다.
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    /// 마우스가 나갔거나, 눌렀거나, 줄이 사라졌다.
    ///
    /// `view` 를 주면 **그 줄이 아직 주인일 때만** 걷는다. 목록이 다시 그려지면서 옛 줄이
    /// 창을 떠날 때, 이미 새 줄이 띄워 둔 툴팁까지 걷어 가는 것을 막는다.
    func hide(if view: NSView? = nil) {
        if let view, owner !== view { return }
        cancel()
        panel?.orderOut(nil)
        panel = nil
        owner = nil
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: 그리기

    private func show(_ text: String) {
        let body = TooltipBody(text: text, maxWidth: maxWidth)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(body.frame.size)
        panel.contentView = body
        panel.setFrameOrigin(origin(for: body.frame.size))
        // 앞을 뺏지 않는다. 이 창을 위해 앱이 깨어나면 애초에 툴팁을 직접 그린 뜻이 없다.
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // 상시 창(`.floating`)보다 위에 있어야 가려지지 않는다.
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // **마우스를 받지 않는다.** 받으면 커서가 툴팁 위로 올라간 순간 줄에서 나간 것이
        // 되어, 툴팁이 스스로를 걷어내고 다시 뜨기를 반복한다.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        return panel
    }

    /// 커서 아래·오른쪽에 놓는다 — 시스템 툴팁이 서는 자리와 같다.
    ///
    /// 화면 끝에서는 반대편으로 접는다. 모니터가 여러 대인 자리에서는 **커서가 있는 화면**의
    /// 테두리를 봐야 한다. 주 화면 기준으로 재면 보조 화면에서 툴팁이 화면 밖으로 나간다.
    private func origin(for size: NSSize) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = cursor.x + 12
        var y = cursor.y - 20 - size.height       // 커서 아래 (AppKit 은 위로 자란다)
        if x + size.width > visible.maxX { x = cursor.x - 12 - size.width }
        if y < visible.minY { y = cursor.y + 20 }
        x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        y = min(max(y, visible.minY + 4), visible.maxY - size.height - 4)
        return NSPoint(x: x, y: y)
    }
}

// MARK: - 몸통

/// 툴팁 한 장. 시스템 툴팁의 생김새를 따른다 — 옅은 바탕, 얇은 테두리, 작은 글자.
///
/// **재는 것과 그리는 것을 같은 것에게 시킨다.** 처음에는 `boundingRect(with:options:)`
/// 로 재고 `draw(with:options:)` 로 그렸는데, 둘이 같은 옵션을 받고도 다른 답을 내서
/// 마지막 줄이 반쯤 잘렸다 (실측: 네 줄짜리 툴팁의 넷째 줄). 레이아웃 매니저 하나가
/// 재고 그리면 그 어긋남이 있을 수 없다 — 잰 것이 곧 그린 것이다.
private final class TooltipBody: NSView {

    private let inset = NSSize(width: 7, height: 5)
    private let storage: NSTextStorage
    private let layout = NSLayoutManager()
    private let container: NSTextContainer

    /// 글을 위에서 아래로 쌓는다. 뒤집어 두면 레이아웃 매니저가 내놓는 좌표를
    /// 그대로 쓸 수 있다 — 뒤집지 않으면 줄마다 y 를 되짚어야 하고, 그 되짚기가
    /// 위에서 말한 어긋남이 다시 들어올 틈이 된다.
    override var isFlipped: Bool { true }

    init(text: String, maxWidth: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1
        storage = NSTextStorage(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        container = NSTextContainer(size: NSSize(width: maxWidth - inset.width * 2,
                                                 height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        super.init(frame: .zero)

        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).size
        setFrameSize(NSSize(width: ceil(used.width) + inset.width * 2,
                            height: ceil(used.height) + inset.height * 2))
    }

    required init?(coder: NSCoder) { fatalError("사용하지 않음") }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        NSColor.controlBackgroundColor.setFill()
        box.fill()
        NSColor.separatorColor.setStroke()
        box.lineWidth = 1
        box.stroke()
        let glyphs = layout.glyphRange(for: container)
        layout.drawGlyphs(forGlyphRange: glyphs,
                          at: NSPoint(x: inset.width, y: inset.height))
    }
}

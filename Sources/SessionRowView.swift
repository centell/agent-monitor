import AppKit

/// 메뉴 한 줄을 직접 그리는 뷰.
///
/// **왜 커스텀 뷰인가.** 항목에 `keyEquivalent` 가 하나라도 있으면 AppKit 이 메뉴 **전체**
/// 오른쪽에 단축키 칸을 예약하고, 단축키가 없는 세션 줄까지 그만큼 밀려난다.
/// 실측 338pt. 커스텀 뷰 항목은 제 폭을 스스로 보고하므로 그 칸이 붙지 않아 296pt 가 된다.
/// 덕분에 `⌘,` · `⌘Q` 를 유지하면서도 메뉴가 넓어지지 않는다.
///
/// 대신 AppKit 이 공짜로 해 주던 **강조와 클릭을 직접** 해야 한다.
final class SessionRowView: NSView {

    private let normalText: NSAttributedString
    private let highlightedText: NSAttributedString
    private let onClick: (() -> Void)?
    private let onRightClick: (() -> Void)?
    private let isPinned: Bool
    private var isHighlighted = false
    private var tracking: NSTrackingArea?

    /// 메뉴 항목의 좌우 여백. 기본 메뉴 항목의 글자 시작 위치에 맞춘 값이다.
    private static let insetX: CGFloat = 20
    private static let insetY: CGFloat = 3

    /// 우클릭은 `enabled` 와 무관하게 늘 산다. 갈 수 없는 줄이라고 고정까지 막을
    /// 이유는 없다 — 오히려 못 가는 줄일수록 눈에 띄게 두고 싶을 수 있다.
    init(text: NSAttributedString, enabled: Bool, pinned: Bool = false,
         onClick: (() -> Void)?, onRightClick: (() -> Void)? = nil) {
        self.onClick = enabled ? onClick : nil
        self.onRightClick = onRightClick
        self.isPinned = pinned

        // 눌릴 수 없는 줄은 흐리게 둔다. 눌리는 줄과 생김새로 구분되어야 한다.
        let base = NSMutableAttributedString(attributedString: text)
        if !enabled {
            base.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                              range: NSRange(location: 0, length: base.length))
        }
        normalText = base

        // 강조된 줄은 네이티브 메뉴와 같이 글자를 흰색 계열로 바꾼다.
        // 상태는 표식의 «모양»(◆○●◐)으로도 읽히므로 색을 잃어도 뜻이 남는다.
        let highlighted = NSMutableAttributedString(attributedString: base)
        highlighted.addAttribute(.foregroundColor, value: NSColor.selectedMenuItemTextColor,
                                 range: NSRange(location: 0, length: highlighted.length))
        highlightedText = highlighted

        let unbounded = NSSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)
        let size = base.boundingRect(with: unbounded,
                                     options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: ceil(size.width) + Self.insetX * 2,
                                 height: ceil(size.height) + Self.insetY * 2))
    }

    required init?(coder: NSCoder) { fatalError("사용하지 않음") }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        // 고정한 줄은 바탕을 옅게 깐다.
        //
        // 글자색이 아니라 바탕인 이유: 글자색은 이미 «머리는 진하게 · 지표는 흐리게»
        // 라는 위계를 쓰고 있어서, 세 번째 색을 넣으면 그 위계가 흐려진다.
        // 바탕은 강조 말고는 비어 있던 층이라 아무것도 밀어내지 않는다.
        //
        // 강조(마우스 올림)가 이 바탕을 덮는다. 가리키고 있는 줄이 고정인지 잠시
        // 안 보이지만, 그건 지금 손이 가 있는 줄이라 잃어도 손해가 없다.
        if isPinned && !isHighlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            // 네이티브 메뉴처럼 좌우를 살짝 들여 둥근 사각형으로 칠한다.
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        (isHighlighted ? highlightedText : normalText)
            .draw(at: NSPoint(x: Self.insetX, y: Self.insetY))
    }

    // MARK: 마우스

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard onClick != nil else { return }
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
    }

    /// 누르기 시작한 자리. 상시 창에서는 이 줄 위에서 **창을 잡아 끌 수도** 있어서,
    /// 끌고 놓은 것을 클릭으로 세면 옮길 때마다 엉뚱한 터미널이 앞으로 튀어나온다.
    ///
    /// 창을 끄는 일 자체는 창이 한다(`isMovableByWindowBackground`). 여기서는 자리만
    /// 적어 두고 `super` 로 넘긴다 — 삼키면 줄 위에서는 창이 안 움직인다.
    private var pressedAt: NSPoint?

    override func mouseDown(with event: NSEvent) {
        pressedAt = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let onClick else { return }
        // 메뉴 안에서는 `mouseDown` 이 여기까지 오지 않는다. 적힌 자리가 없으면 «안 움직였다»로
        // 본다 — 메뉴에서 하던 동작을 그대로 둔다.
        let moved = pressedAt.map {
            abs(event.locationInWindow.x - $0.x) > 3 || abs(event.locationInWindow.y - $0.y) > 3
        } ?? false
        pressedAt = nil
        guard !moved else { return }
        // 메뉴를 먼저 닫고 동작한다. 열린 채로 창을 띄우면 메뉴가 위에 남는다.
        // 상시 창에는 닫을 메뉴가 없어 이 줄은 조용히 지나간다.
        enclosingMenuItem?.menu?.cancelTracking()
        onClick()
    }

    /// 우클릭 — 고정을 켜고 끈다.
    ///
    /// 왼쪽과 달리 메뉴를 닫지 않는다. 줄이 위로 올라가는 것을 그 자리에서 봐야
    /// 무엇이 일어났는지 알 수 있고, 여러 줄을 잇달아 꽂을 수도 있다.
    override func rightMouseUp(with event: NSEvent) {
        onRightClick?()
    }

    /// 메뉴 트래킹 중에는 `rightMouseUp` 이 뷰까지 오지 않는 경우가 있어
    /// 누르는 쪽도 받아 둔다. 실제 동작은 위에서 한 번만 한다.
    override func rightMouseDown(with event: NSEvent) {}
}

import AppKit

/// 메뉴바에 숫자 하나, 눌러서 여는 평면 목록.
///
/// 커스텀 팝오버 대신 `NSMenu` 를 쓴다. 「접힘 없는 한 화면」이 메뉴의 기본 생김새라
/// 요구사항과 그대로 맞고, 키보드 접근성이 따라온다.
final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let source: SessionSource
    private let interval: TimeInterval
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    /// 메뉴가 열려 있는 동안에는 항목을 갈아 끼우지 않는다. 읽는 중에 목록이
    /// 흔들리면 누르려던 줄이 다른 줄로 바뀐다.
    private var menuIsOpen = false
    private var sessions: [Session] = []

    init(source: SessionSource, interval: TimeInterval = 2) {
        self.source = source
        self.interval = interval
    }

    // MARK: 수명주기

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // Dock 에 뜨지 않는다

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        refresh()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)    // 메뉴가 열려 있어도 제목은 계속 갱신된다
        timer = t
    }

    // MARK: 갱신

    private func refresh() {
        sessions = source.scan().sortedForDisplay()
        updateTitle()
        if !menuIsOpen { rebuildMenu() }
    }

    /// 메뉴바에는 숫자만 둔다. 세션이 몇 개든 제목 길이가 자라지 않는다.
    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let waiting = sessions.attentionCount
        let total = sessions.count
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: waiting > 0 ? .semibold : .regular)

        let title = NSMutableAttributedString(
            string: "\(waiting)/\(total)",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        // 기다리는 것이 있을 때만 앞자리를 강조한다. 0이면 조용히 있는다.
        if waiting > 0 {
            title.addAttribute(.foregroundColor,
                               value: NSColor.controlAccentColor,
                               range: NSRange(location: 0, length: String(waiting).count))
        } else {
            title.addAttribute(.foregroundColor,
                               value: NSColor.secondaryLabelColor,
                               range: NSRange(location: 0, length: title.length))
        }
        button.attributedTitle = title
        button.toolTip = waiting > 0
            ? "\(waiting)개가 기다리는 중 · 전체 \(total)개"
            : "전체 \(total)개 · 기다리는 것 없음"
    }

    // MARK: 메뉴

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        sessions = source.scan().sortedForDisplay()   // 열기 직전 값으로 그린다
        updateTitle()
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        if sessions.isEmpty {
            menu.addItem(disabledRow("살아있는 세션이 없습니다"))
        } else {
            let nameWidth = max(12, sessions.map(\.name.count).max() ?? 12)
            var previousNeededAttention: Bool?

            for session in sessions {
                // 손이 필요한 무리와 그렇지 않은 무리 사이에만 줄을 하나 긋는다.
                // 접는 것이 아니라 가르는 것이다.
                let needs = session.state.needsAttention
                if let previous = previousNeededAttention, previous != needs {
                    menu.addItem(.separator())
                }
                previousNeededAttention = needs
                menu.addItem(row(for: session, nameWidth: nameWidth))
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func row(for session: Session, nameWidth: Int) -> NSMenuItem {
        let name = session.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
        let label = session.state.label.paddedDisplay(to: 8)
        let tool = (session.currentTool ?? "—").padding(toLength: 14, withPad: " ", startingAt: 0)
        let age = Self.elapsed(session.age())
        let estimated = session.isEstimated ? "  (추정)" : ""

        let text = "\(session.state.symbol)  \(name)  \(label)  \(tool)\(age)\(estimated)"
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        // 표식만 색을 준다. 줄 전체를 물들이면 목록이 시끄러워진다.
        attributed.addAttribute(.foregroundColor,
                                value: color(for: session.state),
                                range: NSRange(location: 0, length: 1))

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = attributed
        item.toolTip = session.cwd
        item.isEnabled = false
        return item
    }

    private func color(for state: SessionState) -> NSColor {
        switch state {
        case .waiting: return .systemOrange       // 가장 급하다 — 프롬프트가 떠 있다
        case .idle:    return .systemYellow       // 턴이 끝나 기다린다
        case .busy:    return .systemGreen
        case .shell:   return .systemTeal
        case .unknown: return .tertiaryLabelColor
        }
    }

    private func disabledRow(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: 표시

    static func elapsed(_ seconds: TimeInterval?) -> String {
        guard let s = seconds, s >= 0 else { return "—" }
        if s < 60 { return "\(Int(s))s" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }
}

private extension String {
    /// 한글은 글자 하나가 두 칸을 차지한다. `count` 로 맞추면 줄이 어긋나므로
    /// 표시 폭을 세어 맞춘다.
    func paddedDisplay(to width: Int) -> String {
        let w = reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
        return w >= width ? self : self + String(repeating: " ", count: width - w)
    }
}

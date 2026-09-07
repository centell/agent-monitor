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
    private let sampler = MetricsSampler()
    private var systemMemory: SystemMemory?

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
        sessions = measured(source.scan()).sortedForDisplay()
        updateTitle()
        if !menuIsOpen { rebuildMenu() }
    }

    /// 세션마다 프로세스 트리의 메모리·CPU 를 붙인다.
    private func measured(_ scanned: [Session]) -> [Session] {
        let metrics = sampler.sample(pids: scanned.map(\.pid))
        systemMemory = MetricsSampler.systemMemory()
        return scanned.map { session in
            var copy = session
            copy.metrics = metrics[session.pid]
            return copy
        }
    }

    /// 메뉴바에는 숫자만 둔다. 세션이 몇 개든 제목 길이가 자라지 않는다.
    ///
    /// 강조에 색을 쓰지 않는다. 메뉴바의 배경은 사용자의 배경화면이라 어떤 색을 골라도
    /// 누군가의 화면에서는 묻힌다. 실제로 파란 배경화면 위에서 `controlAccentColor`(파랑)가
    /// 보이지 않았다. 시스템이 밝기에 맞춰 뒤집어 주는 `labelColor` 만 쓰고,
    /// 강조는 **굵기와 글자**로 한다.
    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let waiting = sessions.attentionCount
        let total = sessions.count

        // 기다리는 것이 있으면 굵게, 없으면 보통. 0일 때만 흐리게 한다.
        let hasWaiting = waiting > 0
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: hasWaiting ? .bold : .regular
        )
        let title = NSMutableAttributedString(
            string: "\(waiting)/\(total)",
            attributes: [
                .font: font,
                .foregroundColor: hasWaiting ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ]
        )
        button.attributedTitle = title
        button.toolTip = waiting > 0
            ? "\(waiting)개가 기다리는 중 · 전체 \(total)개"
            : "전체 \(total)개 · 기다리는 것 없음"
    }

    // MARK: 메뉴

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        sessions = measured(source.scan()).sortedForDisplay()   // 열기 직전 값으로 그린다
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
            let nameWidth = max(12, sessions.map(\.name.displayWidth).max() ?? 12)
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

        // 시스템 요약 — 「지금 이 맥이 쪼들리나」에 답하는 줄.
        if let memory = systemMemory {
            menu.addItem(.separator())
            let agentBytes = sessions.compactMap { $0.metrics?.memoryBytes }.reduce(0, +)
            menu.addItem(disabledRow(MetricFormat.systemSummary(memory, agentBytes: agentBytes)))
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func row(for session: Session, nameWidth: Int) -> NSMenuItem {
        // 첫 줄은 물음 — 누가, 어떤 상태로, 얼마나 기다렸나.
        let name = session.name.paddedDisplay(to: nameWidth)
        let label = session.state.label.fitted(to: 10)
        let age = Self.elapsed(session.age())
        let estimated = session.isEstimated ? "  (추정)" : ""
        let line1 = "\(session.state.symbol)  \(name)  \(label)\(String(repeating: " ", count: max(1, 5 - age.count)))\(age)\(estimated)"

        // 둘째 줄은 진단 — 무엇으로, 얼마나 먹으며 돌고 있나.
        let tool = (session.currentTool ?? "—").fitted(to: 12)
        var line2 = "   \(tool)"
        if let metrics = session.metrics {
            let bar = MetricFormat.bar(bytes: metrics.memoryBytes).paddedDisplay(to: 7)
            line2 += "\(bar)\(MetricFormat.gigabytes(metrics.memoryBytes))"
            // CPU 는 의미 있을 때만 나타난다. 쉬는 세션까지 0% 를 늘어놓지 않는다.
            if let cpu = metrics.cpuPercent, cpu >= 5 {
                line2 += String(format: "   CPU %.0f%%", cpu)
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let text = NSMutableAttributedString(
            string: line1 + "\n" + line2,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        // 표식만 색을 준다. 줄 전체를 물들이면 목록이 시끄러워진다.
        text.addAttribute(.foregroundColor,
                          value: color(for: session.state),
                          range: NSRange(location: 0, length: 1))
        // 둘째 줄은 한 단계 작고 흐리게 — 볼 때만 보이면 된다.
        let secondStart = (line1 as NSString).length + 1
        text.addAttributes(
            [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
             .foregroundColor: NSColor.secondaryLabelColor],
            range: NSRange(location: secondStart, length: (line2 as NSString).length)
        )

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = text

        // 누르면 그 세션이 도는 터미널 창으로 간다.
        if TerminalJump.canJump(pid: session.pid) {
            item.target = self
            item.action = #selector(jumpToSession(_:))
            item.representedObject = session
            item.isEnabled = true
            var tip = "\(session.cwd)\n눌러서 이 세션의 터미널로 이동"
            if let m = session.metrics { tip += "\n자손 프로세스 \(m.descendantCount)개 포함" }
            item.toolTip = tip
        } else {
            item.isEnabled = false
            item.toolTip = session.cwd
        }
        return item
    }

    @objc private func jumpToSession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? Session else { return }
        TerminalJump.report(TerminalJump.jump(pid: session.pid), sessionName: session.name)
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


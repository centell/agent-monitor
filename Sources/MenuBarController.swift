import AppKit

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
    private let settings = Settings.shared

    init(source: SessionSource, interval: TimeInterval = 2) {
        self.source = source
        self.interval = interval
    }

    // MARK: 수명주기

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // Dock 에 뜨지 않는다

        // 툴팁이 뜰 때까지 기다리는 시간(밀리초).
        //
        // 기본값은 3초에 가깝다. 그건 «덧붙이는 설명» 을 전제한 값이라, 목록을 연 이유
        // 그 자체를 담은 여기서는 너무 길다. 반대로 0.3초는 눌러야 할 줄로 내려가는 길에
        // 지나친 줄마다 말풍선이 터져 시끄러웠다. 실측으로 그 사이에 앉혔다 —
        // 머무르면 나오고, 지나가면 안 나오는 값.
        //
        // `register` 로 넣는다 — 저장하지 않고 이번 실행에만 얹는 것이라 사용자가 맥 전체에
        // 맞춰 둔 값을 우리가 덮어써 남기지 않는다.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 800])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        refresh()
        restartTimer()

        // 갱신 주기 같은 설정은 즉시 반영돼야 한다.
        NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restartTimer()
            self?.refresh()
        }
    }

    /// 설정된 주기로 타이머를 다시 건다.
    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
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
        button.toolTip = S.menuTooltip(waiting: waiting, total: total)
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
            menu.addItem(disabledRow(S.noSessions))
        } else {
            let formatter = RowFormatter(settings: settings,
                                         nameWidth: RowFormatter.nameWidth(for: sessions))
            var previousNeededAttention: Bool?

            for session in sessions {
                // 손이 필요한 무리와 그렇지 않은 무리 사이에만 줄을 하나 긋는다.
                // 접는 것이 아니라 가르는 것이다.
                //
                // 고정한 것은 무리를 새로 만들지 않는다. 같은 무리 안에서 위로 갈 뿐이다 —
                // 바탕색이 이미 「이건 내가 꽂은 것」을 말하고 있어서, 선까지 그으면
                // 한 가지를 두 번 말하면서 목록만 잘게 쪼개진다.
                let needs = session.state.needsAttention
                if let previous = previousNeededAttention, previous != needs {
                    menu.addItem(.separator())
                }
                previousNeededAttention = needs
                menu.addItem(row(for: session, formatter: formatter))
            }
        }

        // 시스템 요약 — 「지금 이 맥이 쪼들리나」에 답하는 줄.
        if settings.showSummary, let memory = systemMemory {
            menu.addItem(.separator())
            let agentBytes = sessions.compactMap { $0.metrics?.memoryBytes }.reduce(0, +)
            menu.addItem(disabledRow(MetricFormat.systemSummary(memory, agentBytes: agentBytes)))
        }

        menu.addItem(.separator())
        // 세션 줄이 커스텀 뷰라 단축키 칸이 그 줄들을 밀지 않는다. 그래서 단축키를 그대로 쓴다.
        let preferences = NSMenuItem(title: S.settingsItem, action: #selector(openSettings), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        let quit = NSMenuItem(title: S.quitItem, action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func row(for session: Session, formatter: RowFormatter) -> NSMenuItem {
        let row = formatter.row(for: session)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        // 머리(이름·상태·시간)는 굵게, 지표는 흐리게. 두 줄 배치에서는 첫 줄이 굵어지고
        // 한 줄 배치에서는 왼쪽 절반이 굵어진다 — 배치가 달라도 규칙은 하나다.
        // 각 세션이 어디서 시작하는지가 눈에 바로 들어온다.
        let text = NSMutableAttributedString(
            string: row.text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        // 표식만 색을 준다. 줄 전체를 물들이면 목록이 시끄러워진다.
        text.addAttribute(.foregroundColor,
                          value: color(for: session.state),
                          range: NSRange(location: 0, length: 1))
        // 지표는 흐리게 — 평소엔 눈에 안 걸리고 찾을 때만 보이면 된다.
        if let dim = row.dimRange {
            text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: dim)
            text.addAttribute(.font,
                              value: NSFont.monospacedSystemFont(
                                  ofSize: row.secondLineStart != nil ? 11 : 12, weight: .regular),
                              range: dim)
        }

        // 누르면 그 세션이 사는 곳으로 간다 — 터미널 창이거나, 앱이거나.
        let canJump = SessionJump.canJump(session)
        let item = NSMenuItem()
        let view = SessionRowView(
            text: text,
            enabled: canJump,
            pinned: session.isPinned,
            onClick: { [weak self] in self?.jump(to: session) },
            onRightClick: { [weak self] in self?.togglePin(for: session) }
        )
        // 왜 기다리는지를 맨 위에 둔다. 마우스를 올리는 이유가 대개 그것이라 경로보다 앞이고,
        // 줄에서 뺀 값이므로 여기서는 폭에 맞춰 자르지 않는다 — 물음은 끝까지 읽혀야 한다.
        var tip = ""
        if settings.showReason, let why = session.reason, !why.isEmpty {
            tip += Self.folded(why) + "\n\n"
        }
        tip += session.cwd
        if canJump { tip += "\n" + SessionJump.hint(for: session) }
        tip += "\n" + (session.isPinned ? S.unpinHint : S.pinHint)
        if let m = session.metrics { tip += "\n" + S.descendants(m.descendantCount) }
        // 툴팁은 **뷰**에 단다.
        //
        // 항목에 커스텀 뷰가 붙으면 AppKit 은 그 칸을 통째로 뷰에 넘기므로, 항목에 매단
        // `toolTip` 은 뜰 자리가 없다. 커스텀 뷰로 바꾼 뒤로 경로·안내 툴팁이 조용히
        // 죽어 있었던 것이 이 때문이다.
        view.toolTip = tip
        item.toolTip = tip
        item.view = view
        return item
    }

    /// 우클릭 — 이 세션을 고정하거나 푼다.
    ///
    /// 메뉴를 열어 둔 채 목록을 다시 그리는 **유일한** 자리다. 평소에는 읽는 중에 줄이
    /// 흔들리면 누르려던 줄이 다른 줄로 바뀌므로 막아 두지만, 이건 주인이 방금 스스로
    /// 바꾼 것이라 결과가 그 자리에서 보여야 한다.
    private func togglePin(for session: Session) {
        settings.togglePin(session.id)
        // 설정 알림이 이미 다시 훑어 두었을 수 있지만, 순서를 여기서 한 번 더 확정한다.
        sessions = sessions.sortedForDisplay()
        rebuildMenu()
    }

    private func jump(to session: Session) {
        SessionJump.report(SessionJump.jump(to: session), sessionName: session.name)
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

    /// 누를 수 없는 안내 줄. 줄바꿈이 든 글도 그대로 그린다.
    private func disabledRow(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        item.isEnabled = false
        return item
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show { [weak self] in self?.sessions ?? [] }
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

    /// 툴팁에 넣을 한 문단을 낱말 경계에서 접는다.
    ///
    /// 자르지는 않는다 — 줄에서 뺀 것이 잘려서였으므로 여기서까지 자르면 옮긴 뜻이 없다.
    /// 다만 한 줄로 두면 툴팁이 화면 끝까지 늘어나므로 접기만 한다.
    /// 낱말 하나가 한 줄보다 길면(긴 명령·경로) 쪼개지 않고 그대로 둔다. 가운데서
    /// 쪼갠 경로는 읽을 수 없고, 읽을 수 없으면 접은 뜻도 없다.
    static func folded(_ text: String, limit: Int = 46) -> String {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.displayWidth <= limit {
                current = candidate
            } else {
                if !current.isEmpty { lines.append(current) }
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.joined(separator: "\n")
    }
}


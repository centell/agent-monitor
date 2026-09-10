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

    /// 쓰임새를 쌓아 두는 곳. **메뉴바 앱만** 기록한다 — 표본 사이 간격이 곧 시간의 단위라,
    /// 한 번 훑고 죽는 `--list` 같은 실행이 끼어들면 그 단위가 뒤죽박죽이 된다.
    private let stats = StatsRecorder()

    init(source: SessionSource, interval: TimeInterval = 2) {
        self.source = source
        self.interval = interval
    }

    // MARK: 수명주기

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // Dock 에 뜨지 않는다
        applyAppearance()

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
        restartHoverWatch()
        // 지난번에 띄워 두셨으면 그대로 다시 띄운다. 상시 창은 껐다 켤 때마다 다시
        // 찾아 켜야 하면 «상시» 가 아니다.
        FloatingPanelController.shared.sync()

        // 갱신 주기 같은 설정은 즉시 반영돼야 한다.
        NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
            self?.restartTimer()
            self?.restartHoverWatch()
            FloatingPanelController.shared.sync()
            self?.refresh()
        }
    }

    /// 밝게 볼지 어둡게 볼지를 **앱 전체에** 건다.
    ///
    /// 창마다 따로 걸지 않는다. 메뉴·상시 창·설정창·툴팁이 다 여기 딸려 있어서, 한 군데씩
    /// 걸면 새 창이 생길 때마다 거는 것을 잊는 자리가 하나씩 는다.
    /// 「시스템 따름」은 `nil` 이다 — 지금 시스템이 어느 쪽인지 읽어다 박으면 그 뒤에
    /// 시스템이 뒤집혀도 안 따라간다.
    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    // MARK: 올리면 열기

    /// 커서가 메뉴바 숫자 위에 머무는지 지켜보는 눈.
    ///
    /// **트래킹 영역을 쓰지 않는다.** 상태바 버튼은 시스템이 쥔 창에 살아서 `NSTrackingArea`
    /// 를 붙여도 들어옴이 배달되지 않는다 (실측). 대신 커서 위치를 그때그때 묻는다 —
    /// 상시 창이 얼어야 할지 판단할 때 이미 쓰는 것과 같은 수다.
    private var hoverWatch: Timer?
    private var hoverSince: Date?
    /// 열 준비가 되었는가. **메뉴를 닫은 뒤 커서가 버튼을 떠날 때까지 다시 열지 않는다.**
    /// 없으면 닫는 순간 커서가 아직 버튼 위라 곧바로 다시 열려 빠져나갈 수 없다.
    private var hoverArmed = true

    private func restartHoverWatch() {
        hoverWatch?.invalidate()
        hoverWatch = nil
        hoverSince = nil
        hoverArmed = true
        guard settings.hoverOpensMenu else { return }
        // 꺼져 있으면 타이머 자체를 안 만든다. 안 쓰는 손잡이가 초당 스무 번 돌 이유가 없다.
        //
        // 주기가 곧 「즉시」의 바닥이다 — 0초를 골라도 확인은 이 간격으로만 오므로
        // 그만큼은 늦는다. 50ms 는 손이 못 느끼는 폭이면서 초당 스무 번이라 값이 싸다.
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.hoverTick() }
        RunLoop.main.add(t, forMode: .common)
        hoverWatch = t
    }

    /// 메뉴바 숫자가 화면에서 차지하는 칸.
    private var statusButtonRect: NSRect? {
        guard let b = statusItem.button, let w = b.window else { return nil }
        return w.convertToScreen(b.convert(b.bounds, to: nil))
    }

    private func hoverTick() {
        guard !menuIsOpen, let rect = statusButtonRect else { return }
        let inside = rect.contains(NSEvent.mouseLocation)
        guard inside else {
            // 떠났으니 다시 열 준비를 한다.
            hoverSince = nil
            hoverArmed = true
            return
        }
        guard hoverArmed else { return }
        // 들어온 시각을 적고 **그 자리에서 바로** 재 본다. 적고 다음 차례에 재면
        // 「즉시」(0초)를 골라도 한 번의 주기만큼 늘 늦는다.
        if hoverSince == nil { hoverSince = Date() }
        guard let since = hoverSince,
              Date().timeIntervalSince(since) >= settings.hoverDelay else { return }
        hoverArmed = false
        // 눌린 것과 **똑같은 길**로 연다. 따로 띄우면 붙어 있는 메뉴와 두 갈래가 되고,
        // 언젠가 한쪽만 고쳐진다.
        statusItem.button?.performClick(nil)
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
        if settings.recordStats { stats.record(sessions: sessions, memory: systemMemory) }
        updateTitle()
        if !menuIsOpen { rebuildMenu() }
        // 상시 창은 스스로 훑지 않는다. 방금 잰 것을 그대로 건넨다 — 두 번 재면 값이
        // 두 배로 들고, 더 나쁘게는 쓰임새 기록의 시간 단위가 뒤틀린다.
        FloatingPanelController.shared.update(sessions: sessions, memory: systemMemory)
    }

    /// 앱이 내려갈 때 진행 중이던 대기를 적는다.
    ///
    /// 없으면 껐다 켤 때마다 «가장 오래 기다린 것» 이 통째로 사라진다. 남는 것은 짧은
    /// 대기뿐이라, 기록이 실제보다 늘 낙관적으로 보인다.
    func applicationWillTerminate(_ notification: Notification) {
        stats.finish()
    }

    /// 세션마다 프로세스 트리의 메모리·CPU 를 붙인다.
    private func measured(_ scanned: [Session]) -> [Session] {
        let metrics = sampler.sample(pids: scanned.map(\.hostPid))
        systemMemory = MetricsSampler.systemMemory()
        return scanned.map { session in
            var copy = session
            copy.metrics = metrics[session.hostPid]
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

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        // 닫는 순간 커서는 대개 아직 버튼 위다. 떠날 때까지 잠가 두지 않으면
        // 곧바로 다시 열려서 빠져나갈 수가 없다.
        hoverSince = nil
        hoverArmed = false
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        if sessions.isEmpty {
            menu.addItem(disabledRow(S.noSessions))
        } else {
            let formatter = RowFormatter(settings: settings,
                                         nameWidth: RowFormatter.nameWidth(for: sessions))
            // 칸은 **목록을 통째로 보고** 세운다. 한 줄씩 그리면 그 칸에서 가장 넓은
            // 글이 얼마나 넓은지를 알 수 없어 정지점을 못 정한다 (`RowTypesetter`).
            let texts = RowTypesetter.rows(for: sessions, formatter: formatter)
            var previousNeededAttention: Bool?

            for (session, text) in zip(sessions, texts) {
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
                menu.addItem(row(for: session, text: text))
            }
        }

        // 시스템 요약 — 「지금 이 맥이 쪼들리나」에 답하는 줄.
        if settings.showSummary, let memory = systemMemory {
            menu.addItem(.separator())
            let agentBytes = sessions.compactMap { $0.metrics?.memoryBytes }.reduce(0, +)
            menu.addItem(disabledRow(MetricFormat.systemSummary(memory, agentBytes: agentBytes)))
        }

        menu.addItem(.separator())
        // 창을 여닫는 문. 항목 하나가 양쪽을 겸한다 — 「열기」와 「닫기」가 따로 있으면
        // 지금 떠 있는지를 메뉴가 아니라 화면을 보고 판단해야 한다.
        let panelItem = NSMenuItem(title: settings.panelOpen ? S.panelHideItem : S.panelShowItem,
                                   action: #selector(togglePanel), keyEquivalent: "")
        panelItem.target = self
        menu.addItem(panelItem)

        // 세션 줄이 커스텀 뷰라 단축키 칸이 그 줄들을 밀지 않는다. 그래서 단축키를 그대로 쓴다.
        let preferences = NSMenuItem(title: S.settingsItem, action: #selector(openSettings), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        let quit = NSMenuItem(title: S.quitItem, action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// 줄의 생김새(굵기·색·툴팁)는 상시 창과 한 벌을 쓴다 — `SessionRowStyle`.
    /// 다 짜인 글을 받는다. 여기서 만들면 그 줄 하나만 보게 되어 칸이 안 맞는다.
    private func row(for session: Session, text: NSAttributedString) -> NSMenuItem {
        // 누르면 그 세션이 사는 곳으로 간다 — 터미널 창이거나, 앱이거나.
        let canJump = SessionJump.canJump(session)
        let item = NSMenuItem()
        let view = SessionRowView(
            text: text,
            enabled: canJump,
            pinned: session.isPinned,
            onClick: { [weak self] in self?.jump(to: session) },
            onRightClick: { [weak self] _ in self?.togglePin(for: session) }
        )
        let tip = SessionRowStyle.tooltip(for: session, settings: settings)
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

    /// 상시 창을 켜고 끈다. 실제로 여닫는 일은 설정 알림을 타고
    /// `FloatingPanelController.sync()` 한 곳에서만 일어난다.
    @objc private func togglePanel() { settings.panelOpen.toggle() }

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

}


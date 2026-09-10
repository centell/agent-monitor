import AppKit

/// 상시 띄우기 창의 **내용**과 수명.
///
/// 메뉴를 열지 않아도 목록이 늘 보이게 하는 것이 전부다. 메뉴바를 대신하지 않는다 —
/// 화면이 좁은 자리에서는 이 창을 안 켜면 그만이고, 켜도 메뉴바의 `2/5` 는 그대로 있다.
///
/// **스스로 훑지 않는다.** `MenuBarController` 가 이미 몇 초마다 훑고 있으므로 그 결과를
/// 받아 그리기만 한다. 따로 훑으면 재는 값이 두 배로 들 뿐 아니라, 쓰임새 기록이
/// **표본 사이 간격을 시간의 단위로 쓰기 때문에** 그 단위가 뒤틀린다 (`StatsRecorder`).
final class FloatingPanelController: NSObject {

    static let shared = FloatingPanelController()

    private var panel: FloatingPanel?
    private var sessions: [Session] = []
    private var memory: SystemMemory?
    private let settings = Settings.shared

    var isOpen: Bool { panel != nil }

    // MARK: 설정과 맞추기

    /// 설정이 곧 진실이다. 메뉴 항목도, 창의 우클릭 메뉴도, 설정창의 스위치도 모두
    /// `settings.panelOpen` 하나만 뒤집고 나머지는 여기로 흘러온다.
    /// 켜는 길이 셋인데 상태가 셋이면 언젠가 어긋난다.
    func sync() {
        if settings.panelOpen {
            open()
            panel?.isAlwaysOnTop = settings.panelAlwaysOnTop
        } else {
            close()
        }
    }

    private func open() {
        guard panel == nil else { return }
        let p = FloatingPanel()
        p.isAlwaysOnTop = settings.panelAlwaysOnTop
        p.setFrame(settings.panelFrame ?? FloatingPanel.defaultFrame(), display: false)
        panel = p
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelMoved), name: NSWindow.didMoveNotification, object: p)
        rebuild()
        p.orderFrontRegardless()
    }

    private func close() {
        guard let p = panel else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: p)
        settings.panelFrame = p.frame
        p.orderOut(nil)
        panel = nil
    }

    /// 옮긴 자리를 적어 둔다.
    ///
    /// `Settings` 의 다른 값들과 달리 이건 알림을 쏘지 않는다. 창을 끄는 동안 수십 번
    /// 불리는 자리라, 그때마다 «설정이 바뀌었다» 를 외치면 타이머가 계속 다시 걸린다.
    @objc private func panelMoved() {
        guard let p = panel else { return }
        settings.panelFrame = p.frame
    }

    // MARK: 갱신

    func update(sessions: [Session], memory: SystemMemory?) {
        self.sessions = sessions
        self.memory = memory
        guard panel != nil, !mouseIsInside else { return }
        rebuild()
    }

    /// 마우스가 창 위에 있는가.
    ///
    /// 있는 동안에는 다시 그리지 않는다. 대기 줄이 위로 올라오므로, 손이 내려가는 사이에
    /// **누르려던 줄이 다른 줄로 바뀐다.** 메뉴는 열려 있는 동안 얼려서 이걸 막는데
    /// (`MenuBarController.menuIsOpen`), 상시 창은 늘 열려 있어 그 방패가 없다.
    ///
    /// 들어옴·나감 알림 대신 그때그때 마우스 위치를 묻는다. 알림은 한 번 놓치면
    /// 창이 영영 얼어붙지만, 물어보는 쪽은 다음 갱신에 저절로 풀린다.
    private var mouseIsInside: Bool {
        guard let p = panel else { return false }
        return p.frame.contains(NSEvent.mouseLocation)
    }

    /// 얼어 있어도 지금 다시 그린다. **주인이 방금 스스로 바꾼 것**에만 쓴다 —
    /// 고정을 꽂거나 손잡이를 만졌을 때. 결과가 그 자리에서 보이지 않으면 안 먹은 줄 안다.
    private func forceRebuild() {
        sessions = sessions.sortedForDisplay()
        rebuild()
    }

    private func rebuild() {
        panel?.setBody(makeBody())
    }

    // MARK: 그리기

    private func makeBody() -> NSView {
        let shown = settings.panelWaitingOnly
            ? sessions.filter { $0.state.needsAttention }
            : sessions
        // 폭은 **보이는 줄**로 잰다. 숨긴 줄의 긴 이름까지 재면 「기다리는 것만」을 켜도
        // 창이 안 좁아진다.
        let formatter = RowFormatter(settings: settings,
                                     nameWidth: RowFormatter.nameWidth(for: shown))

        var pieces: [NSView] = [makeHeader()]

        if shown.isEmpty {
            pieces.append(PanelNoteView(
                text: settings.panelWaitingOnly && !sessions.isEmpty ? S.panelAllRunning : S.noSessions))
        } else {
            // 손이 필요한 무리와 그렇지 않은 무리 사이에만 줄을 하나 긋는다 — 메뉴와 같다.
            var previousNeededAttention: Bool?
            for session in shown {
                let needs = session.state.needsAttention
                if let previous = previousNeededAttention, previous != needs {
                    pieces.append(PanelSeparatorView())
                }
                previousNeededAttention = needs

                let row = makeRow(session, formatter: formatter)
                if let notice, notice.sessionID == session.id {
                    // 줄을 **대신한다**. 아래에 한 줄 더 붙이면 그 3초 동안 창이 커졌다
                    // 작아지고, 그러면 다른 줄들이 손 밑에서 움직인다.
                    //
                    // 폭도 대신할 줄에 맞춘다. 실측에서 이 글이 행보다 25pt 넓어 창이
                    // 3초 동안 벌어졌다 돌아왔다 — 세로로 안 흔들리게 해 놓고 가로로
                    // 흔들면 고친 것이 아니다. 글은 잘라서 맞춘다.
                    // 바닥값을 두지 않는다. 행은 표식·이름(최소 12칸)·경과 시간만 켜도
                    // 21칸이라 좁아질 수 없고, 바닥값을 두면 그 값이 행보다 커지는 순간
                    // 막으려던 바로 그 벌어짐이 생긴다.
                    let firstLine = formatter.row(for: session).text
                        .split(separator: "\n").first.map(String.init) ?? ""
                    let note = PanelNoteView(text: ("⚠  " + notice.text).fitted(to: firstLine.displayWidth),
                                             emphasised: true)
                    note.setFrameSize(NSSize(width: row.frame.width, height: row.frame.height))
                    pieces.append(note)
                } else {
                    pieces.append(row)
                }
            }
        }

        if settings.showSummary, let memory {
            pieces.append(PanelSeparatorView())
            let agentBytes = sessions.compactMap { $0.metrics?.memoryBytes }.reduce(0, +)
            pieces.append(PanelNoteView(text: MetricFormat.systemSummary(memory, agentBytes: agentBytes)))
        }

        // 가장 넓은 조각에 나머지를 맞춘다. 조각마다 제 폭이면 오른쪽 끝이 들쭉날쭉해진다.
        let width = pieces.map(\.frame.width).max() ?? 240
        let body = PanelBodyView()
        var y: CGFloat = 0
        for piece in pieces {
            piece.setFrameSize(NSSize(width: width, height: piece.frame.height))
            piece.setFrameOrigin(NSPoint(x: 0, y: y))
            body.addSubview(piece)
            y += piece.frame.height
        }
        body.setFrameSize(NSSize(width: width, height: y))
        return body
    }

    private func makeHeader() -> PanelHeaderView {
        PanelHeaderView(waiting: sessions.attentionCount,
                        total: sessions.count,
                        pinnedOnTop: settings.panelAlwaysOnTop) { [weak self] view, event in
            self?.showHandles(from: view, event: event)
        }
    }

    private func makeRow(_ session: Session, formatter: RowFormatter) -> SessionRowView {
        let view = SessionRowView(
            text: SessionRowStyle.attributed(for: session, formatter: formatter),
            enabled: SessionJump.canJump(session),
            pinned: session.isPinned,
            onClick: { [weak self] in self?.jump(to: session) },
            onRightClick: { [weak self] in
                Settings.shared.togglePin(session.id)
                self?.forceRebuild()
            }
        )
        view.toolTip = SessionRowStyle.tooltip(for: session, settings: settings)
        return view
    }

    // MARK: 눌렀는데 갈 수 없었을 때

    /// 지금 이유를 띄우고 있는 줄. 3초 뒤 스스로 걷힌다.
    private var notice: (sessionID: String, text: String)?
    private var noticeTimer: Timer?

    /// 줄을 눌렀을 때. 못 가면 **누른 그 줄에** 이유를 잠깐 띄운다.
    ///
    /// 상자를 띄우지 않는다. 이 창은 「눌러도 앞을 안 뺏는다」로 서 있는데, 실패할 때만
    /// 앞을 뺏으면 그 약속이 가장 필요한 순간에 깨진다. 배너로 보내지도 않는다 —
    /// 실패한 순간 사람 눈은 방금 누른 줄에 가 있다.
    ///
    /// 권한 문제만 예외로 상자를 띄운다. 그건 지나가는 한 줄로 끝날 일이 아니라 사람이
    /// 가서 고쳐야 하는 일이다.
    private func jump(to session: Session) {
        let outcome = SessionJump.jump(to: session)
        guard let message = outcome.message else {
            SessionJump.report(outcome, sessionName: session.name)
            return
        }
        notice = (session.id, message)
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.notice = nil
            self?.forceRebuild()
        }
        forceRebuild()
    }

    // MARK: 손잡이

    /// 머리줄을 우클릭하면 나오는 작은 메뉴.
    ///
    /// **머리줄에서만** 연다. 세션 줄의 우클릭은 이미 고정이라, 몸통에도 달면 둘이 겹친다.
    /// 설정창까지 가야만 끌 수 있으면 구석에 둔 창의 뜻이 반쯤 죽으므로 여기에도 둔다.
    private func showHandles(from view: NSView, event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(check(S.panelAlwaysOnTop, on: settings.panelAlwaysOnTop, #selector(flipAlwaysOnTop)))
        menu.addItem(check(S.panelWaitingOnly, on: settings.panelWaitingOnly, #selector(flipWaitingOnly)))
        menu.addItem(.separator())
        let close = NSMenuItem(title: S.panelHideItem, action: #selector(hidePanel), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func check(_ title: String, on: Bool, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc private func flipAlwaysOnTop() {
        settings.panelAlwaysOnTop.toggle()
        panel?.isAlwaysOnTop = settings.panelAlwaysOnTop
        forceRebuild()      // 머리줄의 표식(▲/△)이 그 자리에서 바뀌어야 한다
    }

    @objc private func flipWaitingOnly() {
        settings.panelWaitingOnly.toggle()
        forceRebuild()
    }

    @objc private func hidePanel() { settings.panelOpen = false }
}

// MARK: - 조각들

/// 줄들을 담는 자리. 위에서 아래로 쌓으려고 좌표계를 뒤집는다.
final class PanelBodyView: NSView {
    override var isFlipped: Bool { true }
}

/// 맨 윗줄 — `2/5` 와 항상 위로 표식, 그리고 손잡이가 나오는 자리.
final class PanelHeaderView: NSView {

    private let text: NSAttributedString
    private let mark: NSAttributedString
    private let onMenu: (NSView, NSEvent) -> Void

    /// 세션 줄과 글자 시작 위치를 맞춘다.
    private static let insetX: CGFloat = 20
    private static let height: CGFloat = 22

    init(waiting: Int, total: Int, pinnedOnTop: Bool, onMenu: @escaping (NSView, NSEvent) -> Void) {
        self.onMenu = onMenu
        text = NSAttributedString(
            string: "\(waiting)/\(total)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12,
                                                        weight: waiting > 0 ? .bold : .regular),
                .foregroundColor: waiting > 0 ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ]
        )
        // 채운 삼각과 빈 삼각. 있다 없다 하는 표식은 폭을 흔들고, 없는 쪽이 «꺼짐»인지
        // «고장»인지 알 수 없다 — 상태 표식(◆○●◐)이 늘 한 칸인 것과 같은 이유다.
        //
        // 3차 라벨색으로 두었더니 반투명 바탕 위에서 **있는지 없는지 알 수 없었다.**
        // 이 표식은 장식이 아니라 상태를 읽는 유일한 자리라, 안 보이면 없는 것과 같다.
        mark = NSAttributedString(
            string: pinnedOnTop ? "▲" : "△",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: ceil(text.size().width) + Self.insetX * 2 + 40,
                                 height: Self.height))
        toolTip = S.panelHandlesHint
    }

    required init?(coder: NSCoder) { fatalError("사용하지 않음") }

    override func draw(_ dirtyRect: NSRect) {
        let baseline = (bounds.height - text.size().height) / 2
        text.draw(at: NSPoint(x: Self.insetX, y: baseline))
        mark.draw(at: NSPoint(x: bounds.maxX - Self.insetX - mark.size().width,
                              y: (bounds.height - mark.size().height) / 2))
    }

    override func rightMouseDown(with event: NSEvent) { onMenu(self, event) }
}

/// 누를 수 없는 안내 줄 — 「살아있는 세션이 없습니다」·시스템 요약.
final class PanelNoteView: NSView {

    private let text: NSAttributedString
    private static let insetX: CGFloat = 20
    private static let insetY: CGFloat = 4

    /// `emphasised` 는 안내가 아니라 **방금 벌어진 일**을 적을 때 쓴다.
    /// 시스템 요약과 같은 흐린 글로 두면 3초 뒤 사라지는 말을 놓친다.
    init(text string: String, emphasised: Bool = false) {
        text = NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: emphasised ? 12 : 11,
                                                   weight: emphasised ? .semibold : .regular),
                .foregroundColor: emphasised ? NSColor.systemOrange : NSColor.secondaryLabelColor,
            ]
        )
        let size = text.size()
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: ceil(size.width) + Self.insetX * 2,
                                 height: ceil(size.height) + Self.insetY * 2))
    }

    required init?(coder: NSCoder) { fatalError("사용하지 않음") }

    override func draw(_ dirtyRect: NSRect) {
        text.draw(at: NSPoint(x: Self.insetX, y: Self.insetY))
    }
}

/// 무리를 가르는 가는 선.
final class PanelSeparatorView: NSView {

    init() { super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 9)) }

    required init?(coder: NSCoder) { fatalError("사용하지 않음") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 12, y: bounds.midY, width: bounds.width - 24, height: 1).fill()
    }
}

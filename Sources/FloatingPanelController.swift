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
            panel?.backdropStyle = settings.panelBackdropStyle
            panel?.backdropAlpha = settings.panelBackdropAlpha
            panel?.padding = settings.panelPadding
        } else {
            close()
        }
    }

    private func open() {
        guard panel == nil else { return }
        let p = FloatingPanel()
        p.isAlwaysOnTop = settings.panelAlwaysOnTop
        p.backdropStyle = settings.panelBackdropStyle
        p.backdropAlpha = settings.panelBackdropAlpha
        p.padding = settings.panelPadding
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
        // 「멈추는 중」은 그 줄이 **목록에서 실제로 빠질 때** 걷는다. 멈춘 직후에 걷으면
        // 다음 훑기까지의 사이에 줄이 되살아났다가 사라져 깜빡인다.
        // 얼어 있어도(`mouseIsInside`) 여기까지는 온다 — 걷는 일이 밀리면 손을 치웠을 때
        // 낡은 말이 한 번 더 보인다.
        if !stopping.isEmpty {
            stopping.formIntersection(sessions.map(\.id))
        }
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
                text: settings.panelWaitingOnly && !sessions.isEmpty ? S.panelAllRunning : S.noSessions,
                size: settings.panelFontSize - 1))
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
                    pieces.append(replacing(row, for: session, formatter: formatter,
                                            text: "⚠  " + notice.text, emphasised: true))
                } else {
                    pieces.append(row)
                }
            }
        }

        if settings.showSummary, let memory {
            pieces.append(PanelSeparatorView())
            let agentBytes = sessions.compactMap { $0.metrics?.memoryBytes }.reduce(0, +)
            pieces.append(PanelNoteView(text: MetricFormat.systemSummary(memory, agentBytes: agentBytes),
                                        size: settings.panelFontSize - 1))
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

    /// 줄을 **대신하는** 한 줄.
    ///
    /// 아래에 한 줄 더 붙이지 않는다. 그러면 그 동안 창이 커졌다 작아지고, 다른 줄들이
    /// 손 밑에서 움직인다.
    ///
    /// 폭도 대신할 줄에 맞춘다. 실측에서 이 글이 행보다 25pt 넓어 창이 3초 동안
    /// 벌어졌다 돌아왔다 — 세로로 안 흔들리게 해 놓고 가로로 흔들면 고친 것이 아니다.
    /// 글은 잘라서 맞춘다. 바닥값을 두지 않는다. 행은 표식·이름(최소 12칸)·경과 시간만
    /// 켜도 21칸이라 좁아질 수 없고, 바닥값을 두면 그 값이 행보다 커지는 순간 막으려던
    /// 바로 그 벌어짐이 생긴다.
    private func replacing(_ row: NSView, for session: Session, formatter: RowFormatter,
                           text: String, emphasised: Bool) -> PanelNoteView {
        let firstLine = formatter.row(for: session).text
            .split(separator: "\n").first.map(String.init) ?? ""
        let note = PanelNoteView(text: text.fitted(to: firstLine.displayWidth),
                                 size: settings.panelFontSize, emphasised: emphasised)
        note.setFrameSize(NSSize(width: row.frame.width, height: row.frame.height))
        return note
    }

    private func makeHeader() -> PanelHeaderView {
        PanelHeaderView(waiting: sessions.attentionCount,
                        total: sessions.count,
                        pinnedOnTop: settings.panelAlwaysOnTop,
                        size: settings.panelFontSize) { [weak self] view, event in
            self?.showHandles(from: view, event: event)
        }
    }

    private func makeRow(_ session: Session, formatter: RowFormatter) -> SessionRowView {
        let view = SessionRowView(
            text: SessionRowStyle.attributed(for: session, formatter: formatter,
                                             size: settings.panelFontSize,
                                             skin: settings.panelSkin,
                                             stopping: stopping.contains(session.id)),
            enabled: SessionJump.canJump(session),
            pinned: session.isPinned,
            insetY: settings.panelDensity,
            onClick: { [weak self] in self?.jump(to: session) },
            onRightClick: { [weak self] event in
                self?.showRowMenu(for: session, from: event)
            }
        )
        // AppKit 툴팁이 아니라 우리가 그리는 쪽을 쓴다. 이 창에서는 `toolTip` 이 뜨지
        // 않는다 — 실측과 이유는 `RowTooltip` 에 있다.
        view.panelToolTip = SessionRowStyle.tooltip(for: session, settings: settings, inPanel: true)
        return view
    }

    // MARK: 줄 우클릭

    /// 우클릭하면 나오는 작은 메뉴 — 고정, 그리고 멈출 수 있는 줄이면 멈추기.
    ///
    /// 예전에는 우클릭 한 번이 곧 고정이었다. 멈추기가 붙으면서 메뉴로 바꿨다 —
    /// 되돌리기 쉬운 일(고정)과 세션을 끄는 일이 **같은 손짓 하나**를 나눠 쓰면 안 된다.
    private func showRowMenu(for session: Session, from event: NSEvent) {
        guard let view = event.window?.contentView else { return }
        let menu = NSMenu()

        let pin = NSMenuItem(title: session.isPinned ? S.unpinItem : S.pinItem,
                             action: #selector(flipPin(_:)), keyEquivalent: "")
        pin.target = self
        pin.representedObject = session.id
        menu.addItem(pin)

        if SessionStop.canStop(session) {
            menu.addItem(.separator())
            // **한 단계로 끝내지 않는다.** 상자를 띄워 묻는 길도 있지만 그러면 이 창이
            // 앞을 뺏게 되고, 그건 이 창이 서 있는 약속을 깨는 일이다. 그래서 확인을
            // 메뉴 **안**에서 받는다 — 겉 항목은 문일 뿐이고, 한 칸 더 들어가야 돈다.
            //
            // 항목을 눌러 말을 굳히는 방법도 있었는데, 메뉴는 누르는 순간 닫히므로
            // 다시 열어야 하고 그 되열기가 사람에게는 「눌렀는데 아무 일도 없었다」로
            // 보인다. 하위 메뉴는 열려 있는 채로 한 걸음이 더 생긴다.
            let stop = NSMenuItem(title: S.stopItem, action: nil, keyEquivalent: "")
            let confirm = NSMenu()
            let go = NSMenuItem(title: S.stopConfirmItem, action: #selector(reallyStop(_:)), keyEquivalent: "")
            go.target = self
            go.representedObject = session
            confirm.addItem(go)
            // 대화가 남는다는 것을 그 자리에 적는다. 되돌릴 수 있는 종료라는 것을 모르면
            // 누르기까지의 무게가 실제보다 무거워진다.
            let note = NSMenuItem(title: S.stopKeepsChat, action: nil, keyEquivalent: "")
            note.isEnabled = false
            confirm.addItem(note)
            stop.submenu = confirm
            menu.addItem(stop)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func flipPin(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        settings.togglePin(id)
        forceRebuild()
    }

    /// 멈추는 중인 줄. 그 줄이 목록에서 사라질 때까지 이름 대신 「멈추는 중」이 앉는다.
    ///
    /// **없으면 누른 사람이 눌린 줄을 모른다.** `claude stop` 은 상대가 내려가기를 기다리므로
    /// 곧바로 안 끝나고, 그동안 줄은 멀쩡히 그대로 있다. 게다가 이 창은 **마우스가 위에
    /// 있는 동안 다시 그리지 않는다** (`mouseIsInside`) — 방금 메뉴를 눌렀으면 손은 아직
    /// 창 위다. 그래서 눌러도 아무 일이 없다가, 손을 치우는 순간 줄이 사라진다.
    /// 실제로 「되고 있는 건가 모르겠더라, 어느새 꺼져 있었다」는 말을 들었다.
    ///
    /// 이 앱은 「눌렀는데 아무 일도 없었다」를 없애려고 이동 실패에도 이유를 적어 왔다
    /// (`notice`). 성공하는 쪽에 그 구멍을 남겨 둘 이유가 없다.
    private var stopping: Set<String> = []

    @objc private func reallyStop(_ item: NSMenuItem) {
        guard let session = item.representedObject as? Session else { return }
        // 누른 그 순간 줄이 답한다. `forceRebuild` 여야 한다 — 마우스가 창 위에 있어
        // 평소 갱신은 막혀 있고, 이건 주인이 방금 스스로 누른 것이다.
        stopping.insert(session.id)
        forceRebuild()

        SessionStop.stop(session) { [weak self] outcome in
            guard let self else { return }
            guard let message = outcome.message else {
                // 멈췄다. **여기서 표시를 걷지 않는다.** 걷으면 다음 훑기까지의 사이에
                // 줄이 되살아났다가 사라져 깜빡인다. 목록에서 실제로 빠질 때 걷는다
                // (`update`). 그때까지는 「멈추는 중」이 맞는 말이기도 하다.
                return
            }
            self.stopping.remove(session.id)
            self.show(message, on: session)
        }
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
        show(message, on: session)
    }

    /// 그 줄에 한 줄을 3초 띄운다. 이동 실패와 멈추기 실패가 같은 자리를 쓴다 —
    /// 사람 눈이 가 있는 곳은 둘 다 방금 누른 줄이다.
    private func show(_ message: String, on session: Session) {
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
    /// 글자가 커지면 머리줄도 따라 커진다. 글자만 커지고 칸이 그대로면 위아래가 잘린다.
    private let height: CGFloat

    init(waiting: Int, total: Int, pinnedOnTop: Bool, size: CGFloat,
         onMenu: @escaping (NSView, NSEvent) -> Void) {
        self.onMenu = onMenu
        text = NSAttributedString(
            string: "\(waiting)/\(total)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size,
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
                .font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        height = ceil(size) + 10
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: ceil(text.size().width) + Self.insetX * 2 + 40,
                                 height: height))
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
    init(text string: String, size: CGFloat = 11, emphasised: Bool = false) {
        text = NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: size,
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

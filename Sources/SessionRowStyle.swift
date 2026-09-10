import AppKit

/// 세션 한 줄의 **생김새** — 굵기·색·툴팁.
///
/// `RowFormatter` 가 «무슨 글자» 를 정하고 여기가 «어떤 모양» 을 정한다.
/// 메뉴와 상시 창이 같은 줄을 그리므로 한 벌만 둔다. 각자 갖게 두면 창이 하나 늘 때마다
/// 규칙도 한 벌씩 늘고, 어느 날 둘이 어긋나도 **아무도 모른다** — 나란히 놓고 볼 일이
/// 없는 두 화면이라서.
///
/// 여기서 만드는 것은 **아직 안 벌려진** 줄이다. 칸 사이는 탭 하나로만 이어 두고,
/// 그 탭이 어디서 멈출지는 `RowTypesetter` 가 목록 전체를 보고 정한다.
enum SessionRowStyle {

    /// 표식만 색을 준다. 줄 전체를 물들이면 목록이 시끄러워진다.
    static func color(for state: SessionState) -> NSColor {
        switch state {
        case .waiting: return .systemOrange       // 가장 급하다 — 프롬프트가 떠 있다
        case .idle:    return .systemYellow       // 턴이 끝나 기다린다
        case .busy:    return .systemGreen
        case .shell:   return .systemTeal
        case .unknown: return .tertiaryLabelColor
        }
    }

    /// 흐리게 깔지 말 것 — 눌릴 수 없는 줄을 통째로 흐리게 만드는 손길(`SessionRowView`)에게
    /// 「이 구간만은 남겨 달라」고 붙이는 표식.
    ///
    /// 멈출 수 있는 줄은 **언제나** 눌릴 수 없는 줄이라(갈 터미널이 없으니까), 그냥 두면
    /// 「멈추는 중」이 나머지와 똑같이 흐려져 지표 한 조각처럼 보인다. 지금 무슨 일이
    /// 일어나는지를 알리는 말이 가장 안 보이는 말이 되면 안 된다.
    static let keepBright = NSAttributedString.Key("agentmonitor.keepBright")

    /// 벌리기 전의 한 줄.
    ///
    /// `spans` 는 **어느 칸이 글의 어디에 있는가** 이다. 예전에는 이것을 글자 수로
    /// 셈해서 구했는데(표식 한 칸 + 공백 둘 = 3번째부터가 이름), 칸을 탭으로 잇는 순간
    /// 그 셈이 무너진다. 셈이 아니라 **적어 두고 쓴다** — 틀려도 에러가 안 나는 자리라서,
    /// 셈으로 두면 어긋난 것을 아무도 모른다.
    struct Draft {
        let text: NSMutableAttributedString
        let spans: [(column: RowFormatter.Field.Column, range: NSRange)]
    }

    /// 머리(이름·상태·시간)는 굵게, 지표는 흐리게.
    ///
    /// 두 줄 배치에서는 첫 줄이 굵어지고 한 줄 배치에서는 왼쪽 절반이 굵어진다 —
    /// 배치가 달라도 규칙은 하나다. 각 세션이 어디서 시작하는지가 눈에 바로 들어온다.
    /// `size` 는 상시 창이 제 글자 크기를 넘기기 위한 것이다. 메뉴는 넘기지 않고
    /// 기본값 12pt 로 그린다 — 손잡이를 돌려도 메뉴는 그대로여야 한다.
    ///
    /// `columns` 는 **목록 전체에 있는 칸**이다. 이 줄에 없는 칸도 빈 채로 자리를
    /// 잡아 둬야 뒤따르는 칸이 제 정지점에 선다. `stopping` 은 지표 자리에
    /// 「멈추는 중」을 앉힌다 — 줄을 통째로 갈아치우지 않는 이유는 `RowFormatter` 에 있다.
    static func draft(for session: Session, row: RowFormatter.Row,
                      columns: [RowFormatter.Field.Column],
                      size: CGFloat = 12,
                      skin: PanelSkin = .simple,
                      stopping: Bool = false) -> Draft {
        let byColumn = Dictionary(row.fields.map { ($0.column, $0) }, uniquingKeysWith: { a, _ in a })
        let text = NSMutableAttributedString()
        var spans: [(column: RowFormatter.Field.Column, range: NSRange)] = []

        // 뒤쪽의 빈 칸까지 탭으로 채우면 줄이 그만큼 길어져 창이 넓어진다.
        // 알맹이가 있는 마지막 칸에서 끊는다.
        let pieces = columns.map { (column: $0, body: byColumn[$0]?.text ?? "") }
        let last = pieces.lastIndex { !$0.body.isEmpty } ?? 0
        for (index, piece) in pieces.enumerated() where index <= last {
            if index > 0 { text.append(NSAttributedString(string: "\t")) }
            let start = text.length
            text.append(NSAttributedString(string: piece.body))
            if !piece.body.isEmpty {
                spans.append((piece.column, NSRange(location: start, length: text.length - start)))
            }
        }

        var dimRanges = row.fields.filter(\.dim).compactMap { field in
            spans.first { $0.column == field.column }?.range
        }
        if let second = row.secondLine {
            let start = text.length + 1
            text.append(NSAttributedString(string: "\n" + second))
            dimRanges.append(NSRange(location: start, length: (second as NSString).length))
        }

        // MARK: 옷 입히기

        let whole = NSRange(location: 0, length: text.length)
        text.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ], range: whole)

        let markRange = spans.first { $0.column == .mark }?.range
        if let markRange {
            text.addAttribute(.foregroundColor, value: color(for: session.state), range: markRange)
        }

        // 지표는 흐리게 — 평소엔 눈에 안 걸리고 찾을 때만 보이면 된다.
        let dimSize = row.secondLineStart != nil ? size - 1 : size
        for range in dimRanges {
            text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            text.addAttribute(.font,
                              value: NSFont.monospacedSystemFont(ofSize: dimSize, weight: .regular),
                              range: range)
        }

        if skin != .simple {
            dress(text, skin: skin, session: session, size: size,
                  nameRange: spans.first { $0.column == .name }?.range,
                  markRange: markRange, dimRanges: dimRanges)
        }
        // **맨 마지막에 얹는다.** 스킨은 지표를 배경으로 내리는 일을 하므로, 먼저 칠하면
        // 그 위에 덮인다. 지금 무슨 일이 일어나는지는 어느 스킨에서도 가장 잘 보여야 한다.
        if stopping {
            for range in dimRanges {
                text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                text.addAttribute(.font,
                                  value: NSFont.monospacedSystemFont(ofSize: dimSize, weight: .semibold),
                                  range: range)
                text.addAttribute(keepBright, value: true, range: range)
            }
        }
        return Draft(text: text, spans: spans)
    }

    /// 스킨이 옷을 입힌다. **글자는 하나도 안 바꾼다** — 굵기·크기·색만 얹는다.
    ///
    /// 크기를 섞어도 세로 열이 안 깨지는 것은 칸마다 제 정지점이 있기 때문이다.
    /// 굵기를 바꾸면 그 칸의 폭도 달라지는데, 정지점을 **여기서 얹은 굵기 그대로**
    /// 재기 때문에 열은 그대로 선다 (`RowTypesetter`).
    private static func dress(_ text: NSMutableAttributedString, skin: PanelSkin,
                              session: Session, size: CGFloat,
                              nameRange: NSRange?, markRange: NSRange?,
                              dimRanges: [NSRange]) {
        let whole = NSRange(location: 0, length: text.length)
        let needs = session.state.needsAttention
        let accent = color(for: session.state)

        func put(_ r: NSRange?, _ s: CGFloat, _ w: NSFont.Weight, _ c: NSColor) {
            guard let r, r.length > 0, r.location + r.length <= text.length else { return }
            text.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: s, weight: w), range: r)
            text.addAttribute(.foregroundColor, value: c, range: r)
        }

        switch skin {
        case .simple:
            return

        case .bold:
            // 위계를 세 단으로 벌린다 — 이름 · 상태와 시간 · 지표.
            put(whole, size - 1, .regular, .secondaryLabelColor)
            put(nameRange, size, .bold, .labelColor)
            put(markRange, size, .bold, accent)
            for range in dimRanges { put(range, size - 2, .regular, .tertiaryLabelColor) }

        case .quiet:
            // 손이 필요한 줄만 남기고 나머지는 배경으로 내린다.
            put(whole, size, .regular, needs ? .secondaryLabelColor : .tertiaryLabelColor)
            put(nameRange, size, needs ? .semibold : .regular,
                needs ? .labelColor : .tertiaryLabelColor)
            put(markRange, size, .regular, needs ? accent : .quaternaryLabelColor)
            for range in dimRanges {
                put(range, size - 1, .regular, needs ? .tertiaryLabelColor : .quaternaryLabelColor)
            }
        }
    }

    /// 마우스를 올렸을 때 나오는 글.
    ///
    /// 왜 기다리는지를 맨 위에 둔다. 마우스를 올리는 이유가 대개 그것이라 경로보다 앞이고,
    /// 줄에서 뺀 값이므로 여기서는 폭에 맞춰 자르지 않는다 — 물음은 끝까지 읽혀야 한다.
    /// `inPanel` 은 **우클릭이 무엇을 하는지가 두 화면에서 다르기 때문에** 필요하다.
    /// 메뉴에서는 우클릭이 곧 고정이고, 상시 창에서는 작은 메뉴가 열린다.
    /// 안내가 실제 손짓과 어긋나면 안 쓰느니만 못하다.
    static func tooltip(for session: Session, settings: Settings, inPanel: Bool = false) -> String {
        var tip = ""
        if settings.showReason, let why = session.reason, !why.isEmpty {
            tip += folded(why) + "\n\n"
        }
        tip += session.cwd
        // 합쳐진 줄이라는 것을 밝힌다. 밝히지 않으면 목록의 pid 와 창의 주인이 다른
        // 이유를 알 길이 없다.
        if let from = session.continuedFromPid { tip += "\n" + S.continuedFrom(Int(from)) }
        // 갈 수 없는 줄에는 왜 못 가는지 적는다.
        else if session.isBackground { tip += "\n" + S.backgroundNoWindow }
        if SessionJump.canJump(session) { tip += "\n" + SessionJump.hint(for: session) }
        // 멈출 수 있는 줄이라는 것은 우클릭해 보기 전에는 알 길이 없다. 마침 이 줄은
        // 눌러도 갈 데가 없는 줄이라, 여기 말고는 할 일을 알릴 자리가 없다.
        if inPanel, SessionStop.canStop(session) { tip += "\n" + S.stopHint }
        tip += "\n" + (inPanel ? (session.isPinned ? S.unpinHintPanel : S.pinHintPanel)
                               : (session.isPinned ? S.unpinHint : S.pinHint))
        if let m = session.metrics { tip += "\n" + S.descendants(m.descendantCount) }
        return tip
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

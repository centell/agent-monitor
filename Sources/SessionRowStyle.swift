import AppKit

/// 세션 한 줄의 **생김새** — 굵기·색·툴팁.
///
/// `RowFormatter` 가 «무슨 글자» 를 정하고 여기가 «어떤 모양» 을 정한다.
/// 메뉴와 상시 창이 같은 줄을 그리므로 한 벌만 둔다. 각자 갖게 두면 창이 하나 늘 때마다
/// 규칙도 한 벌씩 늘고, 어느 날 둘이 어긋나도 **아무도 모른다** — 나란히 놓고 볼 일이
/// 없는 두 화면이라서.
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

    /// 머리(이름·상태·시간)는 굵게, 지표는 흐리게.
    ///
    /// 두 줄 배치에서는 첫 줄이 굵어지고 한 줄 배치에서는 왼쪽 절반이 굵어진다 —
    /// 배치가 달라도 규칙은 하나다. 각 세션이 어디서 시작하는지가 눈에 바로 들어온다.
    static func attributed(for session: Session, formatter: RowFormatter) -> NSAttributedString {
        let row = formatter.row(for: session)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let text = NSMutableAttributedString(
            string: row.text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
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
        return text
    }

    /// 마우스를 올렸을 때 나오는 글.
    ///
    /// 왜 기다리는지를 맨 위에 둔다. 마우스를 올리는 이유가 대개 그것이라 경로보다 앞이고,
    /// 줄에서 뺀 값이므로 여기서는 폭에 맞춰 자르지 않는다 — 물음은 끝까지 읽혀야 한다.
    static func tooltip(for session: Session, settings: Settings) -> String {
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
        tip += "\n" + (session.isPinned ? S.unpinHint : S.pinHint)
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

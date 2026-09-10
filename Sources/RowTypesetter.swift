import AppKit

/// 줄들을 **함께 보고** 칸을 세운다.
///
/// **왜 함께 봐야 하나.** 칸을 벌리려면 그 칸에서 가장 넓은 글이 얼마나 넓은지를
/// 알아야 하는데, 그건 한 줄만 봐서는 알 수 없다. 그래서 여기가 목록을 통째로 받는다.
///
/// **왜 공백으로 안 벌리나.** 고정폭 글꼴에서도 한글은 공백 두 개가 아니다 —
/// 12pt 실측으로 공백 7.418pt, 한글 10.380pt, 비율 1.3993 이다. 한 글자마다 4.456pt 가
/// 모자라고, 10.380 ÷ 7.418 이 정수가 아니라서 **공백을 몇 개 넣어도 못 맞춘다.**
/// 실제로 같은 「10칸」으로 채운 상태 칸이 화면에서는 56.36pt 에서 74.18pt 까지 벌어져,
/// 넓어 보이는 「알 수 없음」이 제일 좁고 좁아 보이는 「Waiting」이 제일 넓었다.
///
/// 그래서 칸 사이를 탭 하나로 잇고 `NSTextTab` 정지점을 문단에 박는다. 정지점은 칸이
/// 아니라 **점 좌표**라서 글자 폭이 제각각이어도 정확히 선다. 경과 시간은 오른쪽
/// 정렬 정지점을 쓴다 — 예전에 공백으로 밀어 넣던 일을 글꼴이 대신한다.
///
/// 터미널은 진짜 격자라 이 길로 오지 않는다. `RowFormatter.Row.text` 를 그대로 쓴다.
enum RowTypesetter {

    /// 칸이 서는 차례. 줄마다 있고 없고가 달라도 이 순서는 고정이다.
    private static let order: [RowFormatter.Field.Column] =
        [.mark, .name, .state, .tool, .age, .flag, .metrics]

    /// 목록 한 벌을 짠다. 돌려주는 순서는 받은 순서와 같다.
    static func rows(for sessions: [Session], formatter: RowFormatter,
                     size: CGFloat = 12,
                     skin: PanelSkin = .simple,
                     stopping: Set<String> = []) -> [NSAttributedString] {
        guard !sessions.isEmpty else { return [] }

        let rows = sessions.map {
            formatter.row(for: $0,
                          replacingMetrics: stopping.contains($0.id) ? S.stoppingLine : nil)
        }

        // 어느 칸이 이 목록에 있는가.
        //
        // 줄 하나가 아니라 목록 전체를 보고 정한다. 추정 표식처럼 **한 줄에만 있는 칸**을
        // 그 줄에서만 만들면, 그 줄의 지표만 오른쪽으로 밀려 열이 깨진다.
        var sample: [RowFormatter.Field.Column: RowFormatter.Field] = [:]
        for row in rows {
            for field in row.fields where sample[field.column] == nil { sample[field.column] = field }
        }
        let columns = order.filter { sample[$0] != nil }

        // 1. 칸을 꾸민다 — 탭으로만 잇고 아직 벌리지 않는다.
        let drafts = zip(sessions, rows).map { session, row in
            SessionRowStyle.draft(for: session, row: row, columns: columns,
                                  size: size, skin: skin, stopping: stopping.contains(session.id))
        }

        // 2. 칸마다 **제 속성 그대로** 폭을 잰다.
        //
        // 명목 글꼴로 재면 안 된다. 스킨은 칸마다 굵기와 크기를 바꾸므로, 굵은 글씨를
        // 보통 굵기로 재면 정지점이 실제보다 좁아진다. 그리고 좁은 정지점은 글자를
        // 조금 밀어내는 게 아니라 **다음 정지점으로 통째로 넘겨 버린다** — 지금의
        // 작은 어긋남보다 훨씬 흉하다.
        let base = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        let space = (" " as NSString).size(withAttributes: [.font: base]).width
        var width: [RowFormatter.Field.Column: CGFloat] = [:]
        for draft in drafts {
            for span in draft.spans {
                let measured = draft.text.attributedSubstring(from: span.range).size().width
                width[span.column] = max(width[span.column] ?? 0, measured)
            }
        }
        // 칸은 터미널에서 쓰던 폭보다 **좁아지지 않는다.** 그래서 영문만 있는 목록은
        // 지금까지와 같은 자리에 서고, 한글이 섞인 목록만 제자리를 찾는다.
        for column in columns {
            width[column] = max(width[column] ?? 0, CGFloat(sample[column]!.cells) * space)
        }

        // 3. 정지점을 건다. 첫 칸은 줄 맨 앞이라 정지점이 없다.
        var stops: [NSTextTab] = []
        var x: CGFloat = 0
        for (index, column) in columns.enumerated() {
            let field = sample[column]!
            let w = width[column] ?? 0
            guard index > 0 else { x += w; continue }
            x += CGFloat(field.gutter) * space
            switch field.align {
            case .right:
                // 오른쪽 정렬 정지점은 글이 **끝날** 자리를 가리킨다.
                stops.append(NSTextTab(textAlignment: .right, location: x + w, options: [:]))
            case .left:
                stops.append(NSTextTab(textAlignment: .left, location: x, options: [:]))
            }
            x += w
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.tabStops = stops
        // 마지막 정지점 너머로 탭이 넘어가면 이 간격으로 흩어진다. 그런 탭은 없어야
        // 정상이지만, 0 으로 두면 AppKit 이 기본값(28pt)을 되살려 조용히 어긋난다.
        paragraph.defaultTabInterval = space
        let frozen = paragraph.copy()

        return drafts.map { draft in
            draft.text.addAttribute(.paragraphStyle, value: frozen,
                                    range: NSRange(location: 0, length: draft.text.length))
            return draft.text
        }
    }

    /// 점 폭에 맞춰 글을 자른다.
    ///
    /// 칸 수로는 못 자른다. 자를 글과 맞출 폭이 서로 다른 글자로 되어 있으면 칸 수가
    /// 같아도 폭이 다르기 때문이다 — 「멈추는 중…」과 「Stopping…」이 그런 짝이다.
    /// 잘릴 때는 말줄임표를 넣는다. 잘렸다는 것 자체가 알려야 할 사실이라서.
    static func truncated(_ text: String, toWidth limit: CGFloat, font: NSFont) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: attributes).width }
        guard width(text) > limit else { return text }
        let ellipsis = width("…")
        var out = ""
        var used: CGFloat = 0
        for character in text {
            let next = width(String(character))
            if used + next + ellipsis > limit { break }
            out.append(character)
            used += next
        }
        return out + "…"
    }

    /// 짜 놓은 줄이 실제로 차지하는 폭.
    ///
    /// 정지점이 걸린 줄은 글자 수로 폭을 셈할 수 없다 — 탭이 어디서 멈추는지는
    /// 문단 양식만 안다. 창이 자리를 다툴 때는 이걸로 잰다.
    static func width(of text: NSAttributedString) -> CGFloat {
        let unbounded = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        return text.boundingRect(with: unbounded,
                                 options: [.usesLineFragmentOrigin, .usesFontLeading]).width
    }
}

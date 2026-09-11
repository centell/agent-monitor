import Foundation

/// 세션 한 줄을 글자로 옮긴다.
///
/// 메뉴와 설정창 미리보기가 **같은 코드**를 쓴다. 따로 두면 미리보기가 실제와
/// 어긋나 거짓말을 하게 되고, 그러면 손잡이를 만져 보는 의미가 없다.
///
/// **칸을 정하는 일과 칸을 벌리는 일이 갈라져 있다.** 여기서는 「무슨 글이 어느 칸에
/// 들어가는가」만 정한다. 그 칸이 화면에서 어디쯤 서는지는 `RowTypesetter` 가 정하고,
/// 터미널에서 어떻게 채워지는지는 아래 `joined` 가 정한다. 갈라 둔 이유는 **공백으로는
/// 화면을 못 벌리기 때문**이다 — 한글 한 자는 고정폭 글꼴에서도 공백 두 개가 아니라
/// 1.3993 개다(12pt 실측 10.380pt 대 7.418pt). 정수배가 아니므로 공백을 몇 개 넣어도
/// 맞출 수 없다. 터미널은 진짜 격자라 공백이 맞고, 화면은 아니다.
struct RowFormatter {

    let settings: Settings
    let nameWidth: Int

    /// 줄을 이루는 **칸** 하나.
    ///
    /// `text` 에는 채움 공백이 없다 — 잘릴 것만 잘려 있는 알맹이다. 채우거나 벌리는
    /// 일은 이것을 받아 가는 쪽이 각자 한다.
    struct Field {
        /// 칸의 종류. 줄마다 있고 없고가 달라도 **차례는 이 순서로 고정**이다.
        enum Column: CaseIterable { case mark, name, state, tool, age, flag, metrics }
        enum Align { case left, right }

        let column: Column
        /// 채움 공백이 없는 알맹이.
        let text: String
        /// 터미널에서 채울 폭(칸). 0 이면 채우지 않는다.
        ///
        /// 화면에서는 이것이 **바닥값**이 된다 — 칸은 이 폭보다 좁아지지 않는다.
        /// 그래서 영문만 있는 목록은 지금까지와 화소 단위로 같은 자리에 선다.
        let cells: Int
        /// 앞에 둘 여백(칸).
        let gutter: Int
        let align: Align
        /// 흐리게 그릴 칸인가.
        let dim: Bool
    }

    struct Row {
        /// 첫 줄을 이루는 칸들. 화면이 쓴다.
        let fields: [Field]
        /// 두 줄 배치의 아랫줄. 칸이 없다 — 통째로 흐리다.
        let secondLine: String?
        /// 칸을 공백으로 채워 이은 것. 터미널(`main.swift`)이 쓴다.
        let text: String
        /// 흐리게 그릴 구간(지표·둘째 줄). `text` 기준 UTF-16 이며 없을 수 있다.
        let dimRange: NSRange?
        /// 둘째 줄이 시작하는 위치. 두 줄 배치일 때만 있다.
        let secondLineStart: Int?
    }

    /// 줄에는 «왜 기다리는가» 를 적지 않는다.
    ///
    /// 한 번 적어 보고 물렸다. 이유가 없는 줄(도는 중)이 목록의 다수라 칸이 대개
    /// 비어 있었고, 정작 이유가 있는 줄은 폭에 맞춰 잘려 물음의 뒷부분 — 무엇을
    /// 고르라는지 — 이 사라졌다. 늘 내는 비용은 폭이고 얻는 것은 반쪽이었다.
    /// 그래서 이유는 마우스를 올렸을 때 통째로 보여 준다 (`MenuBarController`).
    /// `replacingMetrics` 는 지표 자리에 **다른 말**을 앉힌다.
    ///
    /// 줄을 통째로 딴 글로 갈아치우는 길도 있었는데, 그러면 무엇에 대한 말인지가 사라진다 —
    /// 「멈추는 중」만 남고 어느 세션이 멈추는 중인지는 안 보였다. 이름·상태·시간은 그대로
    /// 두고 지표만 바꾸면, 말이 붙을 자리와 그 말이 가리키는 것이 한 줄에 함께 남는다.
    func row(for session: Session, replacingMetrics: String? = nil) -> Row {
        let head = headFields(for: session)
        let headText = joined(head)
        // 공백만 남은 지표는 **없는 것으로 본다.** 켠 칸이 자리를 지키느라 채워 둔 공백인데,
        // 그것을 「있다」로 세면 두 줄 배치에서 아무것도 안 적힌 둘째 줄이 한 줄 생긴다
        // (지표를 못 잰 줄에서만 그렇게 되어, 그 줄만 키가 커진다).
        var tail = replacingMetrics ?? metricsBody(for: session)
        if tail.allSatisfy({ $0 == " " }) { tail = "" }

        switch settings.layout {
        case .single:
            guard !tail.isEmpty else {
                return Row(fields: head, secondLine: nil, text: headText,
                           dimRange: nil, secondLineStart: nil)
            }
            // 앞의 여백은 지표와 같게 둔다 — 바뀐 말이 지표가 서던 자리에 그대로 선다.
            let fields = head + [Field(column: .metrics, text: tail, cells: 0, gutter: 5,
                                       align: .left, dim: true)]
            let text = joined(fields)
            let start = (headText as NSString).length
            return Row(fields: fields, secondLine: nil, text: text,
                       dimRange: NSRange(location: start,
                                         length: (text as NSString).length - start),
                       secondLineStart: nil)

        case .double:
            // 두 줄일 때는 지표를 아래로 내리고 앞을 들여쓴다.
            guard !tail.isEmpty else {
                return Row(fields: head, secondLine: nil, text: headText,
                           dimRange: nil, secondLineStart: nil)
            }
            let second = "   " + tail.trimmingCharacters(in: .whitespaces)
            let text = headText + "\n" + second
            let start = (headText as NSString).length + 1
            return Row(fields: head, secondLine: second, text: text,
                       dimRange: NSRange(location: start, length: (second as NSString).length),
                       secondLineStart: start)
        }
    }

    // MARK: 조각

    /// 표식 · 이름 · 상태 · 도구 · 경과 시간.
    private func headFields(for session: Session) -> [Field] {
        var out: [Field] = [
            Field(column: .mark, text: session.state.symbol,
                  cells: 1, gutter: 0, align: .left, dim: false),
            Field(column: .name, text: displayName(for: session),
                  cells: nameWidth, gutter: 2, align: .left, dim: false),
        ]
        if settings.showStateLabel {
            out.append(Field(column: .state, text: session.state.label.truncatedDisplay(to: 10),
                             cells: 10, gutter: 2, align: .left, dim: false))
        }
        if settings.showTool {
            out.append(Field(column: .tool,
                             text: (session.currentTool ?? "—").truncatedDisplay(to: 14),
                             cells: 14, gutter: 2, align: .left, dim: false))
        }
        // 도구 칸을 껐을 때 그 자리에 있던 여백 둘은 경과 시간 앞으로 옮겨 온다.
        // 켜져 있을 때 여백이 0 인 것도 원래 그랬다 — 도구 칸이 제 폭까지 채워져 있어서
        // 그 안의 빈자리가 곧 여백 노릇을 한다.
        out.append(Field(column: .age, text: MenuBarController.elapsed(session.age()),
                         cells: 4, gutter: settings.showTool ? 0 : 2, align: .right, dim: false))
        if session.isEstimated {
            // 추정 표식에 제 칸을 준다. 예전에는 경과 시간 뒤에 그냥 붙어서, 추정인 줄이
            // 하나 섞이면 **그 줄만** 지표가 오른쪽으로 밀렸다.
            out.append(Field(column: .flag, text: S.estimated.trimmingCharacters(in: .whitespaces),
                             cells: 0, gutter: 2, align: .left, dim: false))
        }
        return out
    }

    /// 막대 · 메모리 · CPU · 컨텍스트 · 토큰. 각각 따로 켜고 끄므로 켜진 것만 이어 붙인다.
    ///
    /// 조각마다 폭이 고정이라 어떤 조합을 골라도 줄과 줄 사이에서 열이 맞는다.
    /// 메모리 숫자를 CPU 앞에 두는 것도 그래서다 — CPU 가 들고 나도 앞이 안 흔들린다.
    /// 여기 쓰이는 글자는 막대(█▊▍▏)까지 전부 정확히 한 칸이라(실측 7.418pt) 안을
    /// 더 쪼갤 것이 없다. 이 칸에서 폭이 튀는 것은 「멈추는 중…」뿐이고 그건 맨 뒤다.
    ///
    /// **켠 칸은 값이 없어도 자리를 지킨다.**
    ///
    /// 예전에는 지표를 못 잰 줄이 통째로 비었는데, 그때는 지표가 프로세스에서만 왔으므로
    /// 「못 잰 줄은 전부 못 잰다」가 참이었다. 토큰이 붙으면서 그게 깨졌다 — codex 앱
    /// 스레드는 제 프로세스가 없어 메모리는 못 재지만 토큰은 codex 가 적어 두므로 잰다.
    /// 앞칸을 비워 두면 그런 줄만 토큰이 왼쪽으로 밀려 열이 어긋난다.
    /// 그래서 못 잰 자리는 `—` 로 채운다 — 빈칸과 달리 «여기서는 못 쟀다» 라고 말한다.
    private func metricsBody(for session: Session) -> String {
        var out = ""
        let m = session.metrics

        if settings.showMemoryBar {
            out += (m.map { MetricFormat.bar(bytes: $0.memoryBytes) } ?? "").paddedDisplay(to: 7)
        }
        // 숫자에 이름을 붙인다. `0.5G` 와 `3%` 는 만든 사람에게만 뜻이 분명하다.
        if settings.showMemoryValue {
            out += "RAM " + (m.map { MetricFormat.gigabytes($0.memoryBytes) } ?? "—")
                .rightAligned(to: 5)
        }
        // 문턱을 두지 않는다. 「CPU %」를 켜 둔 것이 곧 «보여 달라»는 뜻이며,
        // 켜 놓았는데 아무것도 안 나오면 설정이 고장 난 것처럼 보인다.
        // 조용히 두고 싶으면 그 스위치를 끄면 된다 — 그게 손잡이의 일이다.
        if settings.showCPU {
            if !out.isEmpty { out += "  " }
            out += m?.cpuPercent.map { String(format: "CPU %3.0f%%", $0) }
                ?? ("CPU " + "—".rightAligned(to: 4))
        }
        // 지금 얼마나 찼는가. 분모를 적지 않는다 — codex 는 창 크기를 기록에 적지만
        // Claude 는 적지 않아서, 모델 이름으로 표를 만들어 채우면 새 모델이 나오는
        // 순간 조용히 틀린 분모가 뜬다.
        if settings.showContext {
            if !out.isEmpty { out += "  " }
            out += "CTX " + tokenCell(session.usage?.context)
        }
        // 새로 태운 것과 전부를 나란히 적는다. 하나만 적으면 어느 쪽을 골라도
        // 읽는 사람이 오해한다 (실측 한 세션에서 17.2M 대 81.9M).
        if settings.showTokens {
            if !out.isEmpty { out += "  " }
            out += "TOK " + tokenCell(session.usage?.fresh) + "/" + tokenCell(session.usage?.total)
        }
        return out
    }

    /// 토큰 한 칸. 없으면 `—`, 있으면 네 칸에 맞춰 오른쪽 정렬.
    private func tokenCell(_ count: UInt64?) -> String {
        (count.map(MetricFormat.tokens) ?? "—").rightAligned(to: 4)
    }

    /// 칸을 공백으로 채워 잇는다 — **터미널용**.
    ///
    /// 터미널은 진짜 고정폭 격자라 이 셈이 맞는다. 화면에서 이 길로 가면 안 된다.
    private func joined(_ fields: [Field]) -> String {
        fields.reduce(into: "") { out, field in
            out += String(repeating: " ", count: field.gutter)
            out += field.align == .right ? field.text.rightAligned(to: field.cells)
                                         : field.text.paddedDisplay(to: field.cells)
        }
    }

    // MARK: 출처 붙이기

    /// 목록에 적을 이름. 어느 세션인지 이름만 봐도 알 수 있게 출처를 앞에 붙인다.
    ///
    /// 출처가 하나뿐일 때도 붙인다 — 있다 없다 하면 열 폭이 흔들린다.
    /// 어떤 모양으로 붙일지는 설정을 따른다 (`SourceStyle`).
    func displayName(for session: Session) -> String {
        switch settings.sourceStyle {
        case .short:
            return "\(session.sourceTag)/\(session.name)"
        case .symmetric:
            // 넷이 다 자기가 뭔지 말한다. 「표시 없는 것이 터미널」이라는 암묵을 없앤다.
            let tag = session.runsInApp ? "\(session.source)-app" : "\(session.source)-cli"
            return "\(tag)/\(session.name)"
        case .symbol:
            // 이름은 짧게 두고 한 칸짜리 표식으로 가른다.
            // 폭이 고른 글자만 쓴다 — 상태 표식(◆○●◐)과 같은 이유다.
            let mark = session.runsInApp ? "□" : ">"
            return "\(mark) \(session.sourceTag)/\(session.name)"
        }
    }

    // MARK: 도우미

    /// 이름 칸의 폭. 실제로 그려질 이름으로 재야 하므로 설정을 함께 받는다.
    static func nameWidth(for sessions: [Session], settings: Settings = .shared) -> Int {
        let formatter = RowFormatter(settings: settings, nameWidth: 0)
        return max(12, sessions.map { formatter.displayName(for: $0).displayWidth }.max() ?? 12)
    }
}

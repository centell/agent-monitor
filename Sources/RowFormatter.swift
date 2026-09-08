import Foundation

/// 세션 한 줄을 글자로 옮긴다.
///
/// 메뉴와 설정창 미리보기가 **같은 코드**를 쓴다. 따로 두면 미리보기가 실제와
/// 어긋나 거짓말을 하게 되고, 그러면 손잡이를 만져 보는 의미가 없다.
struct RowFormatter {

    let settings: Settings
    let nameWidth: Int

    struct Row {
        let text: String
        /// 흐리게 그릴 구간(지표·둘째 줄). UTF-16 기준이며 없을 수 있다.
        let dimRange: NSRange?
        /// 둘째 줄이 시작하는 위치. 두 줄 배치일 때만 있다.
        let secondLineStart: Int?
    }

    func row(for session: Session) -> Row {
        let head = header(for: session)
        let tail = metrics(for: session)

        switch settings.layout {
        case .single:
            let text = head + tail
            let dim = tail.isEmpty ? nil
                : NSRange(location: (head as NSString).length, length: (tail as NSString).length)
            return Row(text: text, dimRange: dim, secondLineStart: nil)

        case .double:
            // 두 줄일 때는 지표를 아래로 내리고 앞을 들여쓴다.
            let second = "   " + tail.trimmingCharacters(in: .whitespaces)
            guard !tail.isEmpty else {
                return Row(text: head, dimRange: nil, secondLineStart: nil)
            }
            let text = head + "\n" + second
            let start = (head as NSString).length + 1
            return Row(text: text,
                       dimRange: NSRange(location: start, length: (second as NSString).length),
                       secondLineStart: start)
        }
    }

    // MARK: 조각

    /// 표식 · 이름 · 상태 · 도구 · 경과 시간.
    private func header(for session: Session) -> String {
        var out = "\(session.state.symbol)  \(displayName(for: session).paddedDisplay(to: nameWidth))"
        if settings.showStateLabel {
            out += "  \(session.state.label.fitted(to: 10))"
        }
        if settings.showTool {
            out += "  \((session.currentTool ?? "—").fitted(to: 14))"
        } else {
            out += "  "
        }
        out += MenuBarController.elapsed(session.age()).rightAligned(to: 4)
        if session.isEstimated { out += S.estimated }
        return out
    }

    /// 막대 · 메모리 · CPU. 셋을 따로 켜고 끄므로 켜진 것만 이어 붙인다.
    ///
    /// 조각마다 폭이 고정이라 어떤 조합을 골라도 줄과 줄 사이에서 열이 맞는다.
    /// 메모리 숫자를 CPU 앞에 두는 것도 그래서다 — CPU 가 들고 나도 앞이 안 흔들린다.
    private func metrics(for session: Session) -> String {
        guard let m = session.metrics else { return "" }
        var out = ""
        if settings.showMemoryBar {
            out += MetricFormat.bar(bytes: m.memoryBytes).paddedDisplay(to: 7)
        }
        // 숫자에 이름을 붙인다. `0.5G` 와 `3%` 는 만든 사람에게만 뜻이 분명하다.
        if settings.showMemoryValue {
            out += "RAM " + MetricFormat.gigabytes(m.memoryBytes).rightAligned(to: 5)
        }
        // 문턱을 두지 않는다. 「CPU %」를 켜 둔 것이 곧 «보여 달라»는 뜻이며,
        // 켜 놓았는데 아무것도 안 나오면 설정이 고장 난 것처럼 보인다.
        // 조용히 두고 싶으면 그 스위치를 끄면 된다 — 그게 손잡이의 일이다.
        if settings.showCPU, let cpu = m.cpuPercent {
            if !out.isEmpty { out += "  " }
            out += String(format: "CPU %3.0f%%", cpu)
        }
        return out.isEmpty ? "" : "     " + out
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

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
        var out = "\(session.state.symbol)  \(session.name.paddedDisplay(to: nameWidth))"
        if settings.showStateLabel {
            out += "  \(session.state.label.fitted(to: 10))"
        }
        if settings.showTool {
            out += "  \((session.currentTool ?? "—").fitted(to: 14))"
        } else {
            out += "  "
        }
        out += MenuBarController.elapsed(session.age()).rightAligned(to: 4)
        if session.isEstimated { out += "  (추정)" }
        return out
    }

    /// 막대 · 메모리 · CPU. 메모리 숫자를 맨 끝에 두어 CPU 가 들고 나도 열이 흔들리지 않게 한다.
    private func metrics(for session: Session) -> String {
        guard settings.metrics.showsBar, let m = session.metrics else { return "" }
        var out = "     " + MetricFormat.bar(bytes: m.memoryBytes).paddedDisplay(to: 7)
        if settings.metrics.showsValue {
            out += MetricFormat.gigabytes(m.memoryBytes).rightAligned(to: 5)
        }
        // 문턱을 두지 않는다. 「전부 (CPU 포함)」을 고른 것이 곧 «보여 달라»는 뜻이며,
        // 골라 놓았는데 아무것도 안 나오면 설정이 고장 난 것처럼 보인다.
        // 조용히 두고 싶으면 지표 단계를 낮추면 된다 — 그게 손잡이의 일이다.
        if settings.metrics.showsCPU, let cpu = m.cpuPercent {
            out += String(format: "  %3.0f%%", cpu)
        }
        return out
    }

    // MARK: 도우미

    static func nameWidth(for sessions: [Session]) -> Int {
        max(12, sessions.map(\.name.displayWidth).max() ?? 12)
    }
}

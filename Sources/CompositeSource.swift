import Foundation

/// 여러 출처를 하나처럼 보이게 묶는다.
///
/// 위쪽(메뉴·목록·알림)은 세션이 Claude Code 에서 왔는지 codex 에서 왔는지 알 필요가 없다.
/// 출처가 늘어도 화면 코드가 늘지 않게 여기서 끊는다.
///
/// 한 출처가 무엇에 걸려 아무것도 못 돌려주어도 나머지는 그대로 나온다 —
/// 한쪽이 조용해졌다고 목록 전체가 비면 안 된다.
struct CompositeSource: SessionSource {
    let sources: [SessionSource]

    init(_ sources: [SessionSource]) {
        self.sources = sources
    }

    var sourceName: String {
        sources.map(\.sourceName).joined(separator: " + ")
    }

    func scan() -> [Session] {
        sources.flatMap { $0.scan() }
    }
}

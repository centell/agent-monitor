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
        // 한 프로세스를 두 출처가 집을 수 있다 — 예컨대 같은 폴더에서 도는 세션을
        // 작업 폴더로 찾는 출처끼리. 그때는 **먼저 온 출처**를 남긴다. 앞쪽일수록
        // 근거가 단단한 출처(레지스트리를 직접 읽는 쪽)를 두었기 때문이다.
        var seen = Set<Int32>()
        return sources.flatMap { $0.scan() }.filter { seen.insert($0.pid).inserted }
    }
}

import Foundation

// MARK: - 상태

/// 세션이 지금 무엇을 하고 있는가.
///
/// 값은 Claude Code 가 레지스트리에 직접 적은 것을 그대로 옮긴 것이다.
/// 파생 판정을 만들지 않는 것이 이 프로젝트의 핵심 결정이므로,
/// 처음 보는 값도 임의로 뭉개지 않고 원문을 들고 다닌다.
enum SessionState: Equatable {
    case waiting             // 승인 대기 — 프롬프트가 떠 있음
    case idle                // 입력 대기 — 턴이 끝남
    case busy                // 작업 중
    case shell               // 셸 실행 중
    case unknown(String)     // 레지스트리가 우리가 모르는 값을 적었을 때

    init(raw: String) {
        switch raw {
        case "waiting": self = .waiting
        case "idle":    self = .idle
        case "busy":    self = .busy
        case "shell":   self = .shell
        default:        self = .unknown(raw)
        }
    }

    /// 레지스트리에 적혀 있던 원문.
    var raw: String {
        switch self {
        case .waiting:          return "waiting"
        case .idle:             return "idle"
        case .busy:             return "busy"
        case .shell:            return "shell"
        case .unknown(let s):   return s
        }
    }

    var label: String {
        switch self {
        case .waiting:          return S.stateWaiting
        case .idle:             return S.stateIdle
        case .busy:             return S.stateBusy
        case .shell:            return S.stateShell
        case .unknown(let raw): return S.stateUnknown(raw)
        }
    }

    /// 목록 맨 앞에 붙는 표식.
    ///
    /// 이모지를 쓰지 않는다. 고정폭 글꼴에서도 이모지는 폭이 튀어 줄이 어긋난다.
    /// 폭이 고른 도형만 쓰고, 급한 정도는 색으로 구분한다.
    var symbol: String {
        switch self {
        case .waiting: return "◆"
        case .idle:    return "○"
        case .busy:    return "●"
        case .shell:   return "◐"
        case .unknown: return "·"
        }
    }

    /// 사람 손이 필요한 상태인가. 메뉴바 숫자와 목록 정렬의 기준이 된다.
    ///
    /// 모르는 값은 «기다림»으로 세지 않는다. 셌다가 틀리면 있지도 않은 일감을
    /// 만들어 내는 셈이고, 그건 놓치는 것보다 나쁘다.
    var needsAttention: Bool {
        switch self {
        case .waiting, .idle: return true
        case .busy, .shell:   return false
        case .unknown:        return false
        }
    }

    /// 목록 정렬 순서. 작을수록 위.
    var sortRank: Int {
        switch self {
        case .waiting: return 0
        case .idle:    return 1
        case .shell:   return 2
        case .busy:    return 3
        case .unknown: return 4
        }
    }
}

// MARK: - 세션

struct Session {
    let id: String                  // sessionId (UUID)
    let pid: Int32
    let name: String                // 레지스트리가 붙인 이름 (예: tools-91)
    let source: String              // 어느 CLI 에서 왔는가 (claude · codex)
    let cwd: String
    let state: SessionState
    let kind: String?               // interactive 등
    let startedAt: Date?
    let statusUpdatedAt: Date?
    let accountRoot: URL            // 이 세션이 등록된 계정 루트

    /// transcript 로 보강한 것. 없을 수 있다.
    var currentTool: String?
    var lastActivity: Date?

    /// 레지스트리를 읽지 못해 추측으로 내려갔는가.
    ///
    /// 조용히 틀리지 않기 위한 표식이다. 이 값이 참이면 화면에도 추정치라고 적어야 한다.
    var isEstimated: Bool = false

    /// 프로세스 트리의 메모리·CPU. 재지 못했으면 없다.
    var metrics: SessionMetrics?

    /// 터미널이 없는 세션을 여는 다른 문. 앱 세션처럼 tty 가 없을 때 쓴다.
    var deepLink: URL?

    var shortID: String { String(id.prefix(8)) }

    /// 목록에 적을 이름. 어느 CLI 의 세션인지 이름만 봐도 알 수 있게 출처를 앞에 붙인다.
    /// 출처가 하나뿐일 때도 붙인다 — 있다 없다 하면 열 폭이 흔들린다.
    var displayName: String { "\(source)/\(name)" }

    /// 마지막 활동 이후 흐른 시간. transcript 가 없으면 상태 갱신 시각으로 대신한다.
    func age(now: Date = Date()) -> TimeInterval? {
        guard let t = lastActivity ?? statusUpdatedAt else { return nil }
        return now.timeIntervalSince(t)
    }
}

// MARK: - 출처

/// 세션을 어디서 긁어 오는가.
///
/// Claude Code 와 codex 구현체가 있고, `CompositeSource` 가 둘을 묶는다.
/// 다른 CLI 가 더 붙어도 위쪽(화면·알림)을 건드리지 않게 여기서 끊는다.
protocol SessionSource {
    /// 화면에 보일 출처 이름.
    var sourceName: String { get }
    func scan() -> [Session]
}

// MARK: - 칸 맞추기

extension Character {
    /// 고정폭 글꼴에서 두 칸을 먹는가 (한글·CJK·전각).
    var displayWidth: Int {
        guard let v = unicodeScalars.first?.value else { return 1 }
        let wide = (0x1100...0x115F).contains(v)     // 한글 자모
            || (0x2E80...0xA4CF).contains(v)         // CJK 부수 ~ 이(彝)
            || (0xAC00...0xD7A3).contains(v)         // 한글 음절
            || (0xF900...0xFAFF).contains(v)         // CJK 호환
            || (0xFE30...0xFE6F).contains(v)         // 세로쓰기·소형 변형
            || (0xFF00...0xFF60).contains(v)         // 전각
            || (0xFFE0...0xFFE6).contains(v)
        return wide ? 2 : 1
    }
}

extension String {
    /// 표시 폭 기준으로 오른쪽을 채운다.
    ///
    /// 한글은 글자 하나가 두 칸을 차지한다. `count` 로 맞추면 한글이 섞인 순간
    /// 열이 어긋난다 (`작업 중` 은 3글자지만 6칸이다).
    func paddedDisplay(to width: Int) -> String {
        let w = displayWidth
        return w >= width ? self : self + String(repeating: " ", count: width - w)
    }

    /// 칸에 맞춰 자르거나 채운다.
    ///
    /// `padding(toLength:)` 는 긴 문자열을 자르기만 하고 뒤에 공백을 남기지 않아
    /// 다음 칸과 글자가 맞붙는다 (`AskUserQuestio4m`). 여기서는 잘릴 때 말줄임표를
    /// 넣고 **언제나 한 칸은 비워** 다음 값과 붙지 않게 한다.
    func fitted(to width: Int) -> String {
        guard width > 2 else { return self }
        // 딱 맞는 것은 자르지 않는다. 넘칠 때만 줄인다.
        guard displayWidth > width else { return paddedDisplay(to: width) }
        var out = ""
        for ch in self {
            if out.displayWidth + ch.displayWidth > width - 1 { break }
            out.append(ch)
        }
        return (out + "…").paddedDisplay(to: width)
    }

    /// 표시 폭 기준으로 왼쪽을 채운다 (오른쪽 정렬).
    func rightAligned(to width: Int) -> String {
        let w = displayWidth
        return w >= width ? self : String(repeating: " ", count: width - w) + self
    }

    /// 고정폭 글꼴에서 차지하는 칸 수.
    ///
    /// `isASCII` 로 가르면 `…` 이나 `—` 까지 두 칸으로 세어 열이 어긋난다.
    /// 실제로 두 칸을 먹는 것은 한글·CJK·전각 문자다.
    var displayWidth: Int { reduce(0) { $0 + $1.displayWidth } }
}

// MARK: - 정렬

extension Array where Element == Session {
    /// 손이 필요한 것을 위로, 그 안에서는 오래 기다린 것을 위로.
    func sortedForDisplay(now: Date = Date()) -> [Session] {
        sorted { a, b in
            if a.state.sortRank != b.state.sortRank {
                return a.state.sortRank < b.state.sortRank
            }
            let aAge = a.age(now: now) ?? 0
            let bAge = b.age(now: now) ?? 0
            if aAge != bAge { return aAge > bAge }
            return a.name < b.name
        }
    }

    var attentionCount: Int { lazy.filter { $0.state.needsAttention }.count }
}

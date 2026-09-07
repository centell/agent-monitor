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
        case .waiting:          return "승인 대기"
        case .idle:             return "입력 대기"
        case .busy:             return "작업 중"
        case .shell:            return "셸 실행 중"
        case .unknown(let s):   return "알 수 없음(\(s))"
        }
    }

    var symbol: String {
        switch self {
        case .waiting: return "⏳"
        case .idle:    return "○"
        case .busy:    return "●"
        case .shell:   return "◐"
        case .unknown: return "?"
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

    var shortID: String { String(id.prefix(8)) }

    /// 마지막 활동 이후 흐른 시간. transcript 가 없으면 상태 갱신 시각으로 대신한다.
    func age(now: Date = Date()) -> TimeInterval? {
        guard let t = lastActivity ?? statusUpdatedAt else { return nil }
        return now.timeIntervalSince(t)
    }
}

// MARK: - 출처

/// 세션을 어디서 긁어 오는가.
///
/// 지금은 Claude Code 구현체 하나뿐이다. 나중에 다른 CLI 가 붙어도
/// 위쪽(화면·알림)을 건드리지 않게 여기서 끊는다.
protocol SessionSource {
    /// 화면에 보일 출처 이름.
    var sourceName: String { get }
    func scan() -> [Session]
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

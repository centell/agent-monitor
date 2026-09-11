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
    let source: String              // 어느 CLI 인가 (claude · codex)
    let runsInApp: Bool             // 터미널이 아니라 데스크탑 앱 안에서 도는가
    let cwd: String
    let state: SessionState
    let kind: String?               // interactive · bg 등
    let startedAt: Date?
    let statusUpdatedAt: Date?
    let accountRoot: URL            // 이 세션이 등록된 계정 루트

    /// 레지스트리가 적어 둔 **프로세스가 뜬 시각**. `startedAt` 과 다른 값이다.
    ///
    /// `startedAt` 은 «세션이 시작된 시각» 이고 이것은 «그 프로세스가 뜬 시각» 이다.
    /// 백그라운드 세션에서는 둘이 크게 벌어진다 — `claude` 가 프로세스를 미리 데워 두고
    /// (`bg-spare`) 나중에 집어 쓰기 때문에, 스페어가 놀고 있던 시간만큼 차이가 난다
    /// (실측 48분). PID 가 재사용됐는지 가리려면 봐야 하는 것은 이쪽이다.
    var procStart: Date?

    /// transcript 로 보강한 것. 없을 수 있다.
    var currentTool: String?
    var lastActivity: Date?

    /// 승인을 기다리는 도구 호출 (`Bash: pnpm build`). 기록에서 찾지 못하면 없다.
    var pendingCall: String?

    /// 이번 턴에 사람에게 건넨 마지막 말 (`커밋할까요?`).
    var lastSay: String?

    /// 레지스트리를 읽지 못해 추측으로 내려갔는가.
    ///
    /// 조용히 틀리지 않기 위한 표식이다. 이 값이 참이면 화면에도 추정치라고 적어야 한다.
    var isEstimated: Bool = false

    /// 이 세션이 넘어간 다음 세션의 id. 기록 끝의 `continued-in` 에서 온다.
    var continuedIn: String?

    /// 이 세션에 대화를 넘겨준 앞선 프로세스.
    ///
    /// 세션이 이어져도 **터미널 창과 프로세스 트리는 앞선 쪽이 계속 쥐고 있다.**
    /// 그래서 창을 찾을 때도, 트리를 잴 때도 이 값이 있으면 이쪽을 봐야 한다.
    var continuedFromPid: Int32?

    /// 프로세스 트리의 메모리·CPU. 재지 못했으면 없다.
    var metrics: SessionMetrics?

    /// 이 세션이 태운 토큰. 기록에서 못 읽었으면 없다.
    var usage: TokenUsage?

    /// 터미널이 없는 세션을 여는 다른 문. 앱 세션처럼 tty 가 없을 때 쓴다.
    var deepLink: URL?

    var shortID: String { String(id.prefix(8)) }

    /// 사람이 앉아 있는 세션이 아니라 daemon 이 띄운 백그라운드 세션인가.
    ///
    /// 추측하지 않는다 — Claude Code 가 레지스트리에 `kind` 로 직접 적어 준다.
    var isBackground: Bool { kind == "bg" }

    /// 이 세션의 **창과 프로세스 트리**를 쥐고 있는 프로세스.
    ///
    /// 보통은 자기 자신이다. 세션이 이어졌으면 앞선 프로세스가 그것을 계속 쥐고 있으므로
    /// 그쪽이다. 창 찾기와 트리 재기가 **같은 값**을 써야 한다 — 따로 놀면 한 세션의
    /// 메모리가 두 번 세어지거나, 눌러도 갈 곳이 없는 줄이 생긴다.
    var hostPid: Int32 { continuedFromPid ?? pid }

    /// 왜 나를 기다리는가. 없으면 없다 — 지어내지 않는다.
    ///
    /// 손이 필요한 두 상태에만 붙인다. 도는 중인 세션에도 붙이면 지금 할 일이 없는
    /// 줄이 목록에서 가장 시끄러워진다 — 이 앱이 하려던 일과 정반대가 된다.
    ///
    /// 승인 대기인데 호출을 못 찾았으면 마지막으로 한 말로 대신한다. 기록 창 밖으로
    /// 밀려났거나 우리가 모르는 물음일 때인데, 그때도 «무엇을 묻는 중인가» 에는
    /// 마지막 말이 가장 가깝다.
    var reason: String? {
        switch state {
        case .waiting: return pendingCall ?? lastSay
        case .idle:    return lastSay
        default:       return nil
        }
    }

    /// 주인이 상단에 고정해 둔 것인가.
    ///
    /// 핀은 폴더가 아니라 이 세션 하나에 꽂힌다. 한 폴더에 세션을 여럿 띄우는 일이
    /// 흔해서, 폴더에 꽂으면 꽂지 않은 것까지 딸려 올라온다.
    var isPinned: Bool { Settings.shared.isPinned(id) }

    /// 핀이 실제로 순서를 앞당기는가.
    ///
    /// 고정했더라도 **손을 기다릴 때만** 위로 올린다. 도는 중인 세션은 지금 할 일이
    /// 없어서, 위에 있어 봐야 정작 급한 줄을 밀어낼 뿐이다.
    /// 그때도 고정 표시(글자색)는 그대로 둔다 — 자리를 안 옮기는 것과 꽂힌 사실을
    /// 숨기는 것은 다른 일이고, 숨기면 우클릭해서 뽑을 줄을 찾지 못한다.
    var pinnedToTop: Bool { isPinned && state.needsAttention }

    /// `--json` 에 낼 출처 이름. 화면 설정과 무관하게 늘 같은 형태로 낸다 —
    /// 기계가 읽는 값이 사람의 설정에 따라 흔들리면 안 된다.
    var sourceTag: String { runsInApp ? "\(source)-app" : source }

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

    /// 칸에 맞춰 **자르기만** 한다. 채우지 않는다.
    ///
    /// 채우기와 갈라 둔 이유는 화면이 공백으로 못 벌리기 때문이다 — 한글 한 자는
    /// 고정폭 글꼴에서도 공백 두 개가 아니라 1.3993 개다(12pt 실측 10.380 대 7.418).
    /// 화면은 잘린 알맹이만 받아 정지점으로 벌리고(`RowTypesetter`), 터미널은
    /// 진짜 격자라 아래 `fitted` 로 공백까지 채워 받는다.
    func truncatedDisplay(to width: Int) -> String {
        // 딱 맞는 것은 자르지 않는다. 넘칠 때만 줄인다.
        guard width > 2, displayWidth > width else { return self }
        var out = ""
        for ch in self {
            if out.displayWidth + ch.displayWidth > width - 1 { break }
            out.append(ch)
        }
        return out + "…"
    }

    /// 칸에 맞춰 자르거나 채운다.
    ///
    /// `padding(toLength:)` 는 긴 문자열을 자르기만 하고 뒤에 공백을 남기지 않아
    /// 다음 칸과 글자가 맞붙는다 (`AskUserQuestio4m`). 여기서는 잘릴 때 말줄임표를 넣는다.
    func fitted(to width: Int) -> String {
        guard width > 2 else { return self }
        return truncatedDisplay(to: width).paddedDisplay(to: width)
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
    ///
    /// 고정한 것은 그보다 앞서지만, **기다리고 있을 때만** 그렇다 (`pinnedToTop`).
    func sortedForDisplay(now: Date = Date()) -> [Session] {
        sorted { a, b in
            if a.pinnedToTop != b.pinnedToTop { return a.pinnedToTop }
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

// MARK: - 토큰

/// 이 세션이 태운 토큰.
///
/// 값마다 따로 없을 수 있어 셋 다 옵셔널이다. 출처가 적어 두는 것이 제각각이라
/// (codex 는 누적을 스스로 적고, Claude 는 턴마다의 `usage` 만 적는다) 한 덩어리로
/// 묶으면 **못 얻은 것을 0 으로 적게 된다.** 0 과 «모름» 은 다른 말이다.
struct TokenUsage {
    /// 마지막 턴의 컨텍스트 크기 — 지금 얼마나 찼는가.
    ///
    /// 본선만 센다. 서브에이전트는 제 컨텍스트를 따로 쓰므로 이 세션이 찬 정도가 아니다.
    var context: UInt64?

    /// 세션이 **새로 태운** 것. 캐시 재사용분을 뺀 값이다.
    var fresh: UInt64?

    /// API 가 세는 **전부**. 캐시 재사용분까지 포함한다.
    ///
    /// `fresh` 와 나란히 적는다. 실측 한 세션에서 17.15M 대 81.93M 로 다섯 배 가까이
    /// 갈리는데, 둘 중 하나만 적으면 어느 쪽을 골라도 읽는 사람이 오해한다.
    var total: UInt64?

    var isEmpty: Bool { context == nil && fresh == nil && total == nil }
}

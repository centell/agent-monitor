import AppKit
import Combine
import Foundation

/// 한 줄로 볼 것인가, 두 줄로 볼 것인가.
///
/// 넓은 모니터에서는 한 줄이 빠르고, 노트북에서는 답답하다. 화면에 따라 답이 달라서
/// 고정할 수 없는 값이다.
enum RowLayout: String, CaseIterable, Identifiable {
    case single, double
    var id: String { rawValue }
    var label: String { self == .single ? S.layoutSingle : S.layoutDouble }
}

/// 출처를 줄에 어떻게 드러낼 것인가.
///
/// 터미널 세션과 앱 세션을 가르는 방법은 하나가 아니고, 무엇이 나은지는 폭을 얼마나
/// 아끼고 싶은지에 달렸다. 만든 사람이 대신 고를 일이 아니라 손잡이로 내놓는다.
enum SourceStyle: String, CaseIterable, Identifiable {
    /// `claude` · `claude-app` — 앱만 표시한다. 가장 좁다.
    case short
    /// `claude-cli` · `claude-app` — 양쪽 다 밝힌다. 넷이 대칭이 된다.
    case symmetric
    /// `> claude` · `□ claude-app` — 한 칸짜리 표식으로 가른다.
    case symbol

    var id: String { rawValue }
    var label: String {
        switch self {
        case .short:     return S.styleShort
        case .symmetric: return S.styleSymmetric
        case .symbol:    return S.styleSymbol
        }
    }
}

/// 상시 창 바탕의 **결**. 진하기는 따로 잰다.
///
/// 둘로 가른 이유가 있다. 처음에는 「흐릿·보통·또렷·없음」 네 이름이었는데, 그것들은
/// 투명도 눈금이 아니라 **서로 다른 재질**이라 사이를 채울 수 없었다. 결과 진하기로
/// 가르면 사이가 전부 열리고, 「없음」도 따로 둘 필요 없이 **진하기 0%** 가 된다.
enum PanelBackdropStyle: String, CaseIterable, Identifiable {
    /// 뒤가 비쳐 보이는 흐림.
    case blur
    /// 비치지 않는 단색 판.
    case solid

    var id: String { rawValue }
    var label: String { self == .blur ? S.backdropBlur : S.backdropSolid }
}

/// 밝게 볼 것인가, 어둡게 볼 것인가.
///
/// 색은 전부 의미색이라 시스템을 따라가는 것이 기본이고, 그것만으로 충분한 앱이 많다.
/// 그런데 이 앱은 **남의 화면 위에 얹혀 사는 계기판**이다 — 밝은 바탕 구석에 어두운
/// 창을 두고 싶을 수도, 그 반대일 수도 있고, 그건 그 화면을 보는 사람만 안다.
///
/// 메뉴와 창에 **함께** 걸린다. 그래서 상시 창 탭이 아니라 표시 탭에 있다.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return S.p("시스템 따름", "Follow system", "システムに従う")
        case .light:  return S.p("늘 밝게", "Always light", "常に明るく")
        case .dark:   return S.p("늘 어둡게", "Always dark", "常に暗く")
        }
    }

    /// AppKit 에 넘길 것. 「시스템 따름」은 **아무것도 지정하지 않는 것**이다 —
    /// 지금 시스템이 어느 쪽인지 우리가 읽어다 박으면, 그 뒤에 시스템이 바뀌어도 안 따라간다.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

/// 상시 창 줄의 **옷**.
///
/// 무엇을 보이는가(`RowFormatter`)는 그대로 두고 어떻게 보이는가만 바꾼다. 칸이 고정폭이라
/// 줄마다 같은 글자 자리에서 갈리므로, 크기를 섞어도 세로 열은 그대로 맞는다.
///
/// 메뉴에는 걸리지 않는다 — 메뉴는 늘 `simple` 로 그린다.
enum PanelSkin: String, CaseIterable, Identifiable {
    /// 지금까지의 모습. 전부 같은 무게라 고르게 읽힌다.
    case simple
    /// 이름이 먼저 읽히고 상태·지표는 뒤로 물러난다.
    case bold
    /// **기다리는 줄만 살고 도는 줄은 물러난다.** 이 앱의 주장을 그대로 그림으로 옮긴 것.
    case quiet

    var id: String { rawValue }
    var label: String {
        switch self {
        case .simple: return S.skinSimple
        case .bold:   return S.skinBold
        case .quiet:  return S.skinQuiet
        }
    }
}

/// 화면 배치 설정. `UserDefaults` 에 남아 다음 실행에도 유지된다.
final class Settings: ObservableObject {

    static let shared = Settings()

    /// 설정이 바뀌었음을 알린다. 폴링 주기처럼 즉시 반영이 필요한 것이 있다.
    static let didChange = Notification.Name("me.centell.agent-monitor.settingsDidChange")

    @Published var language: Language               { didSet { persist() } }
    @Published var appearance: AppAppearance        { didSet { persist() } }
    @Published var layout: RowLayout                { didSet { persist() } }
    @Published var showStateLabel: Bool             { didSet { persist() } }
    @Published var showTool: Bool                   { didSet { persist() } }
    /// 왜 기다리는지를 줄에 적을 것인가.
    ///
    /// 끌 수 있어야 한다. 이 칸에는 기록에 적힌 명령이 그대로 나오므로, 화면을 공유하거나
    /// 어깨너머로 보이는 자리에서는 인자에 섞인 것까지 함께 보인다. 무엇을 보일지는
    /// 그 자리에 있는 사람만 안다.
    @Published var showReason: Bool                 { didSet { persist() } }
    /// 지표 셋을 각각 켜고 끈다.
    ///
    /// 예전에는 사다리였다 — 끄기 → 막대 → 막대+숫자 → 전부. 그러면 「막대는 빼고
    /// 숫자만」이나 「CPU만」처럼 멀쩡한 조합이 아예 불가능하다.
    /// 셋은 서로 독립인 것을 재므로 손잡이도 셋이어야 한다.
    @Published var showMemoryBar: Bool              { didSet { persist() } }
    @Published var showMemoryValue: Bool            { didSet { persist() } }
    @Published var showCPU: Bool                    { didSet { persist() } }
    /// 마지막 턴이 들고 간 컨텍스트 크기를 줄에 적을 것인가.
    ///
    /// 기본은 끔이다. 켜면 줄이 넓어지는데, 쓰던 폭이 판을 올렸다고 말없이 바뀌면 안 된다.
    @Published var showContext: Bool                { didSet { persist() } }
    /// 세션이 지금까지 태운 토큰을 줄에 적을 것인가.
    ///
    /// **이 스위치만 값이 비싸다.** codex 는 누적을 스스로 적어 두지만 Claude 는 적지
    /// 않아 기록을 통째로 훑어야 한다. 꺼져 있으면 훑지 않는다 (`TokenLedger.enabled`).
    @Published var showTokens: Bool                 { didSet { persist() } }
    @Published var showSummary: Bool                { didSet { persist() } }

    /// 쓰임새를 기록해 둘 것인가 (`--stats` 의 재료).
    ///
    /// 기본은 켜 둔다 — 데이터는 지난 날로 돌아가 만들 수 없어서, 꺼 둔 채로 한 달이
    /// 지나면 그 한 달은 영영 없다. 대신 끄는 손잡이를 눈에 보이는 자리에 둔다.
    @Published var recordStats: Bool                { didSet { persist() } }
    @Published var refreshInterval: Double          { didSet { persist() } }

    /// codex 앱 스레드를 최근 몇 분까지 보일지. `0` 이면 아예 보이지 않는다.
    ///
    /// 앱 스레드는 «아직 열려 있는가» 를 잴 방법이 없다. 그래서 시간으로 자른다 —
    /// 창을 넓히면 놓치는 건 줄지만 끝난 지 오래인 스레드까지 «기다림» 으로 쌓인다.
    /// 어디서 자를지는 사람마다 다르므로 손잡이로 내놓는다.
    @Published var codexAppWindow: Double           { didSet { persist() } }

    /// 줄에 출처를 어떻게 적을지.
    @Published var sourceStyle: SourceStyle         { didSet { persist() } }

    /// 메뉴바 숫자에 마우스를 올리기만 해도 목록을 열 것인가.
    ///
    /// **기본은 끔이다.** 메뉴바는 다른 앱 메뉴를 쓰러 지나가는 복도라, 켜져 있는 것이
    /// 기본이면 「왜 자꾸 튀어나오지」가 첫인상이 된다. 원하는 사람만 켜게 둔다.
    @Published var hoverOpensMenu: Bool             { didSet { persist() } }
    /// 얼마나 머물러야 여는가(초). 지나가는 것과 들여다보려는 것을 이 값이 가른다.
    @Published var hoverDelay: Double               { didSet { persist() } }

    /// 상시 띄우기 창이 떠 있는가.
    ///
    /// 켜는 길이 셋이다 — 메뉴바 항목·창의 우클릭 메뉴·설정창 스위치. 셋이 각자 상태를
    /// 들면 언젠가 어긋나므로 **모두 이 값 하나만 뒤집고**, 창을 여닫는 일은
    /// `FloatingPanelController.sync()` 한 곳에서만 한다.
    @Published var panelOpen: Bool                  { didSet { persist() } }
    /// 그 창을 다른 창들 위에 둘 것인가.
    @Published var panelAlwaysOnTop: Bool           { didSet { persist() } }
    /// 그 창에 손이 필요한 줄만 남길 것인가. 메뉴는 이 값과 무관하게 늘 전부 보여준다.
    @Published var panelWaitingOnly: Bool           { didSet { persist() } }

    /// 상시 창의 **생김새** 셋. 메뉴에는 영향을 주지 않는다 — 메뉴는 늘 기본값으로 그린다.
    ///
    /// 「무엇을 보일지」(칸·지표)를 고르는 손잡이들과 결이 다르다. 그쪽은 정보의 문제이고
    /// 이쪽은 이 창이 화면 구석에서 어떻게 앉아 있을지의 문제다.
    @Published var panelBackdropStyle: PanelBackdropStyle { didSet { persist() } }
    /// 바탕의 진하기 (0…1). **0 이면 바탕이 없다** — 글자만 뜬다.
    @Published var panelBackdropAlpha: Double        { didSet { persist() } }
    @Published var panelFontSize: Double             { didSet { persist() } }
    /// 줄 위아래 여백(pt). 촘촘 1 · 보통 3 · 넉넉 6.
    @Published var panelDensity: Double              { didSet { persist() } }
    /// 창 가장자리와 목록 사이 여백(pt). 없음 0 · 보통 6 · 넉넉 12.
    ///
    /// 줄 밀도와 다른 값이다. 밀도는 **줄과 줄 사이**를 정하고 이건 **창과 목록 사이**를
    /// 정한다. 둘을 한 손잡이로 묶으면 「촘촘한데 테두리는 넉넉하게」가 불가능해진다.
    ///
    /// 좌우에서는 줄이 이미 물고 있는 20pt 위에 더해진다 — 그래서 0 이어도 좌우는
    /// 답답하지 않고, 세로만 0 이던 것이 이 손잡이로 풀린다.
    @Published var panelPadding: Double               { didSet { persist() } }
    /// 줄의 옷. 메뉴에는 걸리지 않는다.
    @Published var panelSkin: PanelSkin                { didSet { persist() } }

    /// 상단에 고정한 세션들 (sessionId).
    ///
    /// 폴더가 아니라 **세션**에 꽂는다. 한 폴더에서 세션을 여럿 띄우는 일이 흔한데
    /// (`vands-crm-v1` 에 둘), 폴더에 꽂으면 그 둘이 함께 올라와 정작 어느 것을
    /// 꽂았는지 알 수 없게 된다.
    ///
    /// 값은 세션과 함께 산다 — 세션을 껐다 켜면 sessionId 가 새로 생기므로 핀도
    /// 사라진다. 그게 이 손잡이의 뜻이기도 하다: 「**지금 도는 이 세션**을 놓치지 않겠다」.
    ///
    /// 죽은 세션의 id 는 여기 남는다. 다시 맞을 일이 없으니 화면에는 아무 영향이 없고,
    /// 한 줄이 40바이트다. 자동으로 털어내 보았지만 **살아 있는 핀이 지워지는 것을
    /// 한 번 봤다** — 안 지워도 되는 것을 지우는 위험이, 안 지워서 남는 것보다 크다.
    @Published var pinnedSessions: Set<String>      { didSet { persist() } }

    /// 저장소를 도메인 이름으로 못 박는다.
    ///
    /// `UserDefaults.standard` 는 번들 식별자를 따라가는데, 앱은 번들 안에서 돌고
    /// CLI(`--list`)는 번들 없이 돈다. 그래서 둘이 **서로 다른 곳**을 보고 있었다.
    /// 앱에서 두 줄로 바꿔도 `--list` 는 한 줄로 그리던 것이 이 때문이다.
    private let store = UserDefaults(suiteName: "me.centell.agent-monitor") ?? .standard
    private var loading = true

    private init() {
        language = Language(rawValue: store.string(forKey: Key.language) ?? "") ?? .system
        appearance = AppAppearance(rawValue: store.string(forKey: Key.appearance) ?? "") ?? .system
        layout = RowLayout(rawValue: store.string(forKey: Key.layout) ?? "") ?? .single
        showStateLabel = store.object(forKey: Key.stateLabel) as? Bool ?? true
        showTool = store.object(forKey: Key.tool) as? Bool ?? true
        showReason = store.object(forKey: Key.reason) as? Bool ?? true
        // 사다리였던 옛 설정에서 옮겨온다. 맞춰 두신 값이 말없이 초기값으로 돌아가면 안 된다.
        let legacy = store.string(forKey: Key.legacyMetrics)
        showMemoryBar = store.object(forKey: Key.memoryBar) as? Bool
            ?? legacy.map { $0 != "none" } ?? true
        showMemoryValue = store.object(forKey: Key.memoryValue) as? Bool
            ?? legacy.map { $0 == "barAndValue" || $0 == "all" } ?? true
        showCPU = store.object(forKey: Key.cpu) as? Bool
            ?? legacy.map { $0 == "all" } ?? false
        showContext = store.object(forKey: Key.context) as? Bool ?? false
        showTokens = store.object(forKey: Key.tokens) as? Bool ?? false
        showSummary = store.object(forKey: Key.summary) as? Bool ?? true
        recordStats = store.object(forKey: Key.recordStats) as? Bool ?? true
        refreshInterval = store.object(forKey: Key.interval) as? Double ?? 2
        codexAppWindow = store.object(forKey: Key.codexAppWindow) as? Double ?? 30
        sourceStyle = SourceStyle(rawValue: store.string(forKey: Key.sourceStyle) ?? "") ?? .short
        pinnedSessions = Set(store.stringArray(forKey: Key.pinned) ?? [])
        panelOpen = store.object(forKey: Key.panelOpen) as? Bool ?? false
        panelAlwaysOnTop = store.object(forKey: Key.panelAlwaysOnTop) as? Bool ?? true
        panelWaitingOnly = store.object(forKey: Key.panelWaitingOnly) as? Bool ?? false
        // 네 이름이었던 옛 설정에서 옮겨온다. 맞춰 두신 값이 말없이 초기값으로 돌아가면 안 된다.
        // `soft`(popover) 는 흐림과 단색 사이의 다른 **색조**라 퍼센트 눈금 위에 자리가 없어
        // 흐림 100% 로 보낸다. 잃는 것을 여기 적어 둔다 — 조용히 바꾸는 것이 가장 나쁘다.
        let legacyBackdrop = store.string(forKey: Key.panelBackdrop)
        panelBackdropStyle = legacyBackdrop == "solid" ? .solid : .blur
        panelBackdropAlpha = store.object(forKey: Key.panelBackdropAlpha) as? Double
            ?? (legacyBackdrop == "clear" ? 0 : 1)
        panelFontSize = store.object(forKey: Key.panelFontSize) as? Double ?? 12
        panelDensity = store.object(forKey: Key.panelDensity) as? Double ?? 3
        panelPadding = store.object(forKey: Key.panelPadding) as? Double ?? 6
        panelSkin = PanelSkin(rawValue: store.string(forKey: Key.panelSkin) ?? "") ?? .simple
        hoverOpensMenu = store.object(forKey: Key.hoverOpensMenu) as? Bool ?? false
        hoverDelay = store.object(forKey: Key.hoverDelay) as? Double ?? 0.4
        loading = false
    }

    /// 상시 창을 마지막에 두었던 자리.
    ///
    /// **알림을 쏘지 않는다.** 창을 끄는 동안 수십 번 불리는 값이라, 그때마다
    /// «설정이 바뀌었다» 를 외치면 타이머가 계속 다시 걸리고 목록도 계속 다시 그려진다.
    /// 다른 값들과 달리 이건 손잡이가 아니라 **창이 스스로 적어 두는 자국**이다.
    var panelFrame: NSRect? {
        get {
            guard let v = store.array(forKey: Key.panelFrame) as? [Double], v.count == 4 else { return nil }
            return NSRect(x: v[0], y: v[1], width: v[2], height: v[3])
        }
        set {
            guard let f = newValue else { return store.removeObject(forKey: Key.panelFrame) }
            store.set([f.minX, f.minY, f.width, f.height].map(Double.init), forKey: Key.panelFrame)
        }
    }

    /// 이 세션이 고정되어 있는가.
    func isPinned(_ sessionID: String) -> Bool { pinnedSessions.contains(sessionID) }

    /// 꽂혀 있으면 뽑고, 없으면 꽂는다.
    func togglePin(_ sessionID: String) {
        if pinnedSessions.contains(sessionID) {
            pinnedSessions.remove(sessionID)
        } else {
            pinnedSessions.insert(sessionID)
        }
    }


    /// 처음 모습으로 되돌린다. 만지다 길을 잃었을 때 빠져나올 문.
    func resetToDefaults() {
        loading = true
        language = .system
        appearance = .system
        layout = .single
        showStateLabel = true
        showTool = true
        showReason = true
        showMemoryBar = true
        showMemoryValue = true
        showCPU = false
        showContext = false
        showTokens = false
        showSummary = true
        recordStats = true
        refreshInterval = 2
        codexAppWindow = 30
        sourceStyle = .short
        panelAlwaysOnTop = true
        panelWaitingOnly = false
        panelBackdropStyle = .blur
        panelBackdropAlpha = 1
        panelFontSize = 12
        panelDensity = 3
        panelPadding = 6
        panelSkin = .simple
        hoverOpensMenu = false
        hoverDelay = 0.4
        // 핀과 «상시 창이 떠 있는가»는 되돌리지 않는다. 이 단추는 «표시 손잡이»를 처음으로
        // 돌리는 문이지, 주인이 직접 꽂아 두거나 직접 띄워 둔 것을 치우는 문이 아니다.
        // 창 안의 손잡이(항상 위로·기다리는 것만)는 표시 손잡이라 되돌린다.
        loading = false
        persist()
    }

    private func persist() {
        guard !loading else { return }
        store.set(language.rawValue, forKey: Key.language)
        store.set(appearance.rawValue, forKey: Key.appearance)
        store.set(layout.rawValue, forKey: Key.layout)
        store.set(showStateLabel, forKey: Key.stateLabel)
        store.set(showTool, forKey: Key.tool)
        store.set(showReason, forKey: Key.reason)
        store.set(showMemoryBar, forKey: Key.memoryBar)
        store.set(showMemoryValue, forKey: Key.memoryValue)
        store.set(showCPU, forKey: Key.cpu)
        store.set(showContext, forKey: Key.context)
        store.set(showTokens, forKey: Key.tokens)
        store.set(showSummary, forKey: Key.summary)
        store.set(recordStats, forKey: Key.recordStats)
        store.set(refreshInterval, forKey: Key.interval)
        store.set(codexAppWindow, forKey: Key.codexAppWindow)
        store.set(sourceStyle.rawValue, forKey: Key.sourceStyle)
        store.set(pinnedSessions.sorted(), forKey: Key.pinned)
        store.set(panelOpen, forKey: Key.panelOpen)
        store.set(panelAlwaysOnTop, forKey: Key.panelAlwaysOnTop)
        store.set(panelWaitingOnly, forKey: Key.panelWaitingOnly)
        store.set(panelBackdropStyle.rawValue, forKey: Key.panelBackdrop)
        store.set(panelBackdropAlpha, forKey: Key.panelBackdropAlpha)
        store.set(panelFontSize, forKey: Key.panelFontSize)
        store.set(panelDensity, forKey: Key.panelDensity)
        store.set(panelPadding, forKey: Key.panelPadding)
        store.set(panelSkin.rawValue, forKey: Key.panelSkin)
        store.set(hoverOpensMenu, forKey: Key.hoverOpensMenu)
        store.set(hoverDelay, forKey: Key.hoverDelay)
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }

    /// 실제로 쓸 언어. `system` 이면 맥의 언어를 따른다.
    ///
    /// 맞는 것이 없으면 영어로 떨어진다 — 아는 말로 적는 것보다 읽을 수 있는 말로 적는 것이 낫다.
    var resolvedLanguage: Language {
        guard language == .system else { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("ko") { return .korean }
        if preferred.hasPrefix("ja") { return .japanese }
        return .english
    }

    private enum Key {
        static let language = "language"
        static let appearance = "appearance"
        static let layout = "rowLayout"
        static let stateLabel = "showStateLabel"
        static let tool = "showTool"
        static let reason = "showReason"
        /// 사다리였던 옛 설정. 새 스위치가 아직 없을 때 여기서 옮겨온다.
        static let legacyMetrics = "metricDisplay"
        static let memoryBar = "showMemoryBar"
        static let memoryValue = "showMemoryValue"
        static let cpu = "showCPU"
        static let context = "showContext"
        static let tokens = "showTokens"
        static let summary = "showSummary"
        static let recordStats = "recordStats"
        static let interval = "refreshInterval"
        static let codexAppWindow = "codexAppWindow"
        static let sourceStyle = "sourceStyle"
        static let pinned = "pinnedSessions"
        static let panelOpen = "panelOpen"
        static let panelAlwaysOnTop = "panelAlwaysOnTop"
        static let panelWaitingOnly = "panelWaitingOnly"
        static let panelFrame = "panelFrame"
        static let panelBackdrop = "panelBackdrop"
        static let panelBackdropAlpha = "panelBackdropAlpha"
        static let panelFontSize = "panelFontSize"
        static let panelDensity = "panelDensity"
        static let panelPadding = "panelPadding"
        static let panelSkin = "panelSkin"
        static let hoverOpensMenu = "hoverOpensMenu"
        static let hoverDelay = "hoverDelay"
    }
}

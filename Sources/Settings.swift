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

/// 지표를 어디까지 보여줄 것인가.
enum MetricDisplay: String, CaseIterable, Identifiable {
    case none, bar, barAndValue, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:        return S.metricNone
        case .bar:         return S.metricBar
        case .barAndValue: return S.metricBarValue
        case .all:         return S.metricAll
        }
    }
    var showsBar: Bool { self != .none }
    var showsValue: Bool { self == .barAndValue || self == .all }
    var showsCPU: Bool { self == .all }
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

/// 화면 배치 설정. `UserDefaults` 에 남아 다음 실행에도 유지된다.
final class Settings: ObservableObject {

    static let shared = Settings()

    /// 설정이 바뀌었음을 알린다. 폴링 주기처럼 즉시 반영이 필요한 것이 있다.
    static let didChange = Notification.Name("me.centell.agent-monitor.settingsDidChange")

    @Published var language: Language               { didSet { persist() } }
    @Published var layout: RowLayout                { didSet { persist() } }
    @Published var showStateLabel: Bool             { didSet { persist() } }
    @Published var showTool: Bool                   { didSet { persist() } }
    @Published var metrics: MetricDisplay           { didSet { persist() } }
    @Published var showSummary: Bool                { didSet { persist() } }
    @Published var refreshInterval: Double          { didSet { persist() } }

    /// codex 앱 스레드를 최근 몇 분까지 보일지. `0` 이면 아예 보이지 않는다.
    ///
    /// 앱 스레드는 «아직 열려 있는가» 를 잴 방법이 없다. 그래서 시간으로 자른다 —
    /// 창을 넓히면 놓치는 건 줄지만 끝난 지 오래인 스레드까지 «기다림» 으로 쌓인다.
    /// 어디서 자를지는 사람마다 다르므로 손잡이로 내놓는다.
    @Published var codexAppWindow: Double           { didSet { persist() } }

    /// 줄에 출처를 어떻게 적을지.
    @Published var sourceStyle: SourceStyle         { didSet { persist() } }

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
        layout = RowLayout(rawValue: store.string(forKey: Key.layout) ?? "") ?? .single
        showStateLabel = store.object(forKey: Key.stateLabel) as? Bool ?? true
        showTool = store.object(forKey: Key.tool) as? Bool ?? true
        metrics = MetricDisplay(rawValue: store.string(forKey: Key.metrics) ?? "") ?? .barAndValue
        showSummary = store.object(forKey: Key.summary) as? Bool ?? true
        refreshInterval = store.object(forKey: Key.interval) as? Double ?? 2
        codexAppWindow = store.object(forKey: Key.codexAppWindow) as? Double ?? 30
        sourceStyle = SourceStyle(rawValue: store.string(forKey: Key.sourceStyle) ?? "") ?? .short
        pinnedSessions = Set(store.stringArray(forKey: Key.pinned) ?? [])
        loading = false
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
        layout = .single
        showStateLabel = true
        showTool = true
        metrics = .barAndValue
        showSummary = true
        refreshInterval = 2
        codexAppWindow = 30
        sourceStyle = .short
        // 핀은 되돌리지 않는다. 이 단추는 «표시 손잡이»를 처음으로 돌리는 문이지,
        // 주인이 직접 꽂아 둔 것을 치우는 문이 아니다.
        loading = false
        persist()
    }

    private func persist() {
        guard !loading else { return }
        store.set(language.rawValue, forKey: Key.language)
        store.set(layout.rawValue, forKey: Key.layout)
        store.set(showStateLabel, forKey: Key.stateLabel)
        store.set(showTool, forKey: Key.tool)
        store.set(metrics.rawValue, forKey: Key.metrics)
        store.set(showSummary, forKey: Key.summary)
        store.set(refreshInterval, forKey: Key.interval)
        store.set(codexAppWindow, forKey: Key.codexAppWindow)
        store.set(sourceStyle.rawValue, forKey: Key.sourceStyle)
        store.set(pinnedSessions.sorted(), forKey: Key.pinned)
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }

    /// 실제로 쓸 언어. `system` 이면 맥의 언어를 따른다.
    var resolvedLanguage: Language {
        guard language == .system else { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ko") ? .korean : .english
    }

    private enum Key {
        static let language = "language"
        static let layout = "rowLayout"
        static let stateLabel = "showStateLabel"
        static let tool = "showTool"
        static let metrics = "metricDisplay"
        static let summary = "showSummary"
        static let interval = "refreshInterval"
        static let codexAppWindow = "codexAppWindow"
        static let sourceStyle = "sourceStyle"
        static let pinned = "pinnedSessions"
    }
}

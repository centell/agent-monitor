import Combine
import Foundation

/// 한 줄로 볼 것인가, 두 줄로 볼 것인가.
///
/// 넓은 모니터에서는 한 줄이 빠르고, 노트북에서는 답답하다. 화면에 따라 답이 달라서
/// 고정할 수 없는 값이다.
enum RowLayout: String, CaseIterable, Identifiable {
    case single, double
    var id: String { rawValue }
    var label: String { self == .single ? "한 줄" : "두 줄" }
}

/// 지표를 어디까지 보여줄 것인가.
enum MetricDisplay: String, CaseIterable, Identifiable {
    case none, bar, barAndValue, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:        return "끄기"
        case .bar:         return "막대만"
        case .barAndValue: return "막대 + 숫자"
        case .all:         return "전부 (CPU 포함)"
        }
    }
    var showsBar: Bool { self != .none }
    var showsValue: Bool { self == .barAndValue || self == .all }
    var showsCPU: Bool { self == .all }
}

/// 화면 배치 설정. `UserDefaults` 에 남아 다음 실행에도 유지된다.
final class Settings: ObservableObject {

    static let shared = Settings()

    /// 설정이 바뀌었음을 알린다. 폴링 주기처럼 즉시 반영이 필요한 것이 있다.
    static let didChange = Notification.Name("me.centell.agent-monitor.settingsDidChange")

    @Published var layout: RowLayout                { didSet { persist() } }
    @Published var showStateLabel: Bool             { didSet { persist() } }
    @Published var showTool: Bool                   { didSet { persist() } }
    @Published var metrics: MetricDisplay           { didSet { persist() } }
    @Published var showSummary: Bool                { didSet { persist() } }
    @Published var refreshInterval: Double          { didSet { persist() } }

    private let store = UserDefaults.standard
    private var loading = true

    private init() {
        layout = RowLayout(rawValue: store.string(forKey: Key.layout) ?? "") ?? .single
        showStateLabel = store.object(forKey: Key.stateLabel) as? Bool ?? true
        showTool = store.object(forKey: Key.tool) as? Bool ?? true
        metrics = MetricDisplay(rawValue: store.string(forKey: Key.metrics) ?? "") ?? .barAndValue
        showSummary = store.object(forKey: Key.summary) as? Bool ?? true
        refreshInterval = store.object(forKey: Key.interval) as? Double ?? 2
        loading = false
    }

    /// 처음 모습으로 되돌린다. 만지다 길을 잃었을 때 빠져나올 문.
    func resetToDefaults() {
        loading = true
        layout = .single
        showStateLabel = true
        showTool = true
        metrics = .barAndValue
        showSummary = true
        refreshInterval = 2
        loading = false
        persist()
    }

    private func persist() {
        guard !loading else { return }
        store.set(layout.rawValue, forKey: Key.layout)
        store.set(showStateLabel, forKey: Key.stateLabel)
        store.set(showTool, forKey: Key.tool)
        store.set(metrics.rawValue, forKey: Key.metrics)
        store.set(showSummary, forKey: Key.summary)
        store.set(refreshInterval, forKey: Key.interval)
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }

    private enum Key {
        static let layout = "rowLayout"
        static let stateLabel = "showStateLabel"
        static let tool = "showTool"
        static let metrics = "metricDisplay"
        static let summary = "showSummary"
        static let interval = "refreshInterval"
    }
}

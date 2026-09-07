import AppKit
import SwiftUI

// MARK: - 화면

/// 손잡이와 **살아있는 미리보기**.
///
/// 미리보기는 실제 세션을 실제 행 그리기 코드(`RowFormatter`)로 그린다.
/// 흉내를 내면 손잡이를 만져 보는 의미가 없어진다.
struct SettingsView: View {

    @ObservedObject private var settings = Settings.shared
    let sessionsProvider: () -> [Session]

    @State private var sessions: [Session] = []
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Picker("줄 배치", selection: $settings.layout) {
                    ForEach(RowLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("상태를 글자로 보이기", isOn: $settings.showStateLabel)
                Toggle("도구 이름 보이기", isOn: $settings.showTool)

                Picker("지표", selection: $settings.metrics) {
                    ForEach(MetricDisplay.allCases) { Text($0.label).tag($0) }
                }

                Toggle("아래에 시스템 요약 보이기", isOn: $settings.showSummary)

                Picker("갱신 주기", selection: $settings.refreshInterval) {
                    Text("1초").tag(1.0)
                    Text("2초").tag(2.0)
                    Text("5초").tag(5.0)
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 6) {
                Text("미리보기")
                    .font(.headline)
                Text(previewText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("실제 세션을 메뉴와 같은 코드로 그린 것입니다. 폭이 곧 메뉴 폭입니다.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)

            HStack {
                Button("처음 모습으로") { settings.resetToDefaults() }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        // 높이를 못 박지 않으면 SwiftUI 내용이 접혀 창이 179pt 로 나온다.
        .frame(minWidth: 620, maxWidth: 620, minHeight: 600, alignment: .top)
        .onAppear { sessions = sessionsProvider() }
        .onReceive(tick) { _ in sessions = sessionsProvider() }
    }

    private var previewText: String {
        guard !sessions.isEmpty else { return "살아있는 세션이 없습니다." }
        let formatter = RowFormatter(settings: settings,
                                     nameWidth: RowFormatter.nameWidth(for: sessions))
        var lines = sessions.prefix(6).map { formatter.row(for: $0).text }
        if settings.showSummary, let memory = MetricsSampler.systemMemory() {
            let agent = sessions.compactMap { $0.metrics?.memoryBytes }.reduce(0, +)
            lines.append("")
            lines.append(MetricFormat.systemSummary(memory, agentBytes: agent))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 창

/// Dock 아이콘이 없는 앱(`LSUIElement`)이라 창을 앞으로 끌어오는 처리를 직접 해야 한다.
///
/// `activate(ignoringOtherApps:)` 만으로는 부족했다 — 실측에서 창은 만들어졌는데
/// 맨 앞 앱이 그대로 Terminal 이었다. 액세서리 앱은 활성화 대상이 아니기 때문이다.
/// 그래서 **창이 떠 있는 동안만 보통 앱으로 바꿨다가** 닫히면 되돌린다.
/// 그동안은 Dock 과 `⌘Tab` 에도 나타나므로 창을 다시 찾기도 쉬워진다.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(sessionsProvider: @escaping () -> [Session]) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(sessionsProvider: sessionsProvider))
            let w = NSWindow(contentViewController: hosting)
            w.title = "AgentMonitor 설정"
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        // 다시 메뉴바에만 사는 앱으로 돌아간다.
        NSApp.setActivationPolicy(.accessory)
    }
}

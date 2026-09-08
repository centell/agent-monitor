import AppKit
import SwiftUI

// MARK: - 화면

/// 손잡이와 **살아있는 미리보기**.
///
/// 미리보기는 실제 세션을 실제 행 그리기 코드(`RowFormatter`)로 그린다.
/// 흉내를 내면 손잡이를 만져 보는 의미가 없어진다.
struct LayoutSettingsView: View {

    @ObservedObject private var settings = Settings.shared
    let sessionsProvider: () -> [Session]

    @State private var sessions: [Session] = []
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        // 손잡이가 하나 늘 때마다 높이 상수를 올리는 것은 깨지기 쉽다. 넘치면 스크롤한다.
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Picker(S.language, selection: $settings.language) {
                    ForEach(Language.allCases) { Text($0.label).tag($0) }
                }

                Picker(S.rowLayout, selection: $settings.layout) {
                    ForEach(RowLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle(S.showStateLabel, isOn: $settings.showStateLabel)
                Toggle(S.showTool, isOn: $settings.showTool)
                Toggle(S.showReason, isOn: $settings.showReason)

                // 셋을 한 줄에 나란히 둔다. 줄 수가 늘지 않아 창 높이 상수를 안 건드리고,
                // 셋이 한 짝이라는 것도 보인다.
                LabeledContent(S.metrics) {
                    HStack(spacing: 14) {
                        Toggle(S.metricBar, isOn: $settings.showMemoryBar)
                        Toggle(S.metricValue, isOn: $settings.showMemoryValue)
                        Toggle(S.metricCPU, isOn: $settings.showCPU)
                    }
                }

                Toggle(S.showSummary, isOn: $settings.showSummary)

                Picker(S.refresh, selection: $settings.refreshInterval) {
                    Text(S.seconds(1)).tag(1.0)
                    Text(S.seconds(2)).tag(2.0)
                    Text(S.seconds(5)).tag(5.0)
                }
                .pickerStyle(.segmented)

                Picker(S.sourceStyle, selection: $settings.sourceStyle) {
                    ForEach(SourceStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker(S.codexAppWindow, selection: $settings.codexAppWindow) {
                    Text(S.windowOff).tag(0.0)
                    Text(S.minutes(10)).tag(10.0)
                    Text(S.minutes(30)).tag(30.0)
                    Text(S.hours(12)).tag(720.0)
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            // 손잡이 수에 맞춘 높이. 모자라면 Form 안에서 마지막 줄이 잘리므로
            // 손잡이를 더할 때는 이 값도 한 줄만큼 올린다.
            .frame(height: 500)

            VStack(alignment: .leading, spacing: 6) {
                Text(S.preview)
                    .font(.headline)
                Text(previewText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(S.previewNote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)

            HStack {
                Button(S.resetButton) { settings.resetToDefaults() }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { sessions = sessionsProvider() }
        .onReceive(tick) { _ in sessions = sessionsProvider() }
    }

    private var previewText: String {
        guard !sessions.isEmpty else { return S.noSessionsPeriod }
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

// MARK: - 탭 묶음

struct SettingsWindowView: View {
    let sessionsProvider: () -> [Session]

    var body: some View {
        TabView {
            LayoutSettingsView(sessionsProvider: sessionsProvider)
                .tabItem { Label(S.tabDisplay, systemImage: "list.bullet") }
            MemoryView(sessionsProvider: sessionsProvider)
                .tabItem { Label(S.tabMemory, systemImage: "memorychip") }
        }
        .padding(.top, 8)
        // 높이를 못 박지 않으면 SwiftUI 내용이 접혀 창이 179pt 로 나온다.
        .frame(minWidth: 640, maxWidth: 640, minHeight: 620, alignment: .top)
    }
}

// MARK: - 메모리

/// 「이 맥의 메모리를 누가 먹고 있나」.
///
/// 세션 합계만으로는 답이 안 나온다. 세션이 띄운 개발 서버나 컨테이너는 트리에서
/// 떨어져 나가 우리 합계에 안 잡히고, 정작 가장 많이 먹는 것이 브라우저일 때도 있다.
struct MemoryView: View {

    let sessionsProvider: () -> [Session]
    @State private var report: MemoryReport?
    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let report {
                    if let system = report.system {
                        GroupBox(S.thisMac) {
                            VStack(alignment: .leading, spacing: 4) {
                                line(S.used, gb(system.usedBytes) + " / " + gb(system.totalBytes))
                                line(S.swap, gb(system.swapUsedBytes))
                                line(S.compressed, gb(system.compressedBytes))
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox(S.agentSessions) {
                        line(gb(report.agentBytes), S.processCount(report.agentProcessCount))
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !report.suspected.isEmpty {
                        GroupBox(S.suspectedGroup) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(report.suspected) { entry in
                                    line(entry.name, gb(entry.bytes) + "   → " + (entry.suspectedOwner ?? ""))
                                }
                                Text(.init(S.suspectedNote))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 4)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox(S.outsideSessions) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(report.others.prefix(12)) { entry in
                                line(entry.name,
                                     gb(entry.bytes) + (entry.processCount > 1 ? S.countSuffix(entry.processCount) : ""))
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(S.memoryFootnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(S.measuring).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onAppear { refresh() }
        .onReceive(tick) { _ in refresh() }
    }

    private func refresh() { report = MemoryReport.build(sessions: sessionsProvider()) }

    private func gb(_ bytes: UInt64) -> String { MetricFormat.size(bytes) }

    private func line(_ left: String, _ right: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(left).font(.system(size: 12, design: .monospaced))
            Spacer(minLength: 12)
            Text(right).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
        }
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
            let hosting = NSHostingController(rootView: SettingsWindowView(sessionsProvider: sessionsProvider))
            let w = NSWindow(contentViewController: hosting)
            w.title = S.windowTitle
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

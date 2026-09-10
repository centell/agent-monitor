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

                // 언어 바로 아래. 둘 다 「앱 전체가 어떤 말·어떤 낯으로 보이나」라
                // 같은 결이고, 아래의 줄 손잡이들과는 층이 다르다.
                Picker(S.appearance, selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

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

                VStack(alignment: .leading, spacing: 2) {
                    Toggle(S.recordStats, isOn: $settings.recordStats)
                    // 무엇을 남기는지 그 자리에 적는다. 기록을 켜 두는 손잡이 옆에
                    // 「무엇이 남는가」가 없으면 켜 둔 사람이 무엇을 켰는지 모른다.
                    Text(S.recordStatsNote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Picker(S.refresh, selection: $settings.refreshInterval) {
                    Text(S.seconds(1)).tag(1.0)
                    Text(S.seconds(2)).tag(2.0)
                    Text(S.seconds(5)).tag(5.0)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(S.hoverOpen) {
                        HStack(spacing: 12) {
                            Toggle(S.hoverOpenToggle, isOn: $settings.hoverOpensMenu)
                            Picker("", selection: $settings.hoverDelay) {
                                Text(S.hoverInstant).tag(0.0)
                                Text(S.hoverFast).tag(0.25)
                                Text(S.hoverNormal).tag(0.4)
                                Text(S.hoverSlow).tag(0.7)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            // 꺼져 있으면 머무는 시간을 고를 일이 없다.
                            .disabled(!settings.hoverOpensMenu)
                        }
                    }
                    if settings.hoverOpensMenu {
                        Text(S.hoverNote).font(.caption).foregroundStyle(.tertiary)
                    }
                }

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
            .frame(height: 650)

            VStack(alignment: .leading, spacing: 6) {
                Text(S.preview)
                    .font(.headline)
                // 가로로 흐르게 둔다. 줄을 **제 폭 그대로** 그려야 「폭이 곧 메뉴 폭」이
                // 참인데, 그 폭이 창보다 넓을 수 있다. 굽히면 거짓이 되고, 안 굽히면
                // 창을 밀어내 좌우가 잘린다 — 실측에서 640pt 창의 양옆이 날아갔다.
                ScrollView(.horizontal) {
                    RowPreview(text: previewRows)
                }
                .fixedSize(horizontal: false, vertical: true)
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

    /// 미리보기의 알맹이 — **메뉴가 쓰는 그 코드**로 짠다.
    ///
    /// 목록 전체를 짜고 앞의 여섯 줄만 보인다. 여섯 줄만 짜면 칸이 그 여섯 줄에 맞춰
    /// 좁아져, 「폭이 곧 메뉴 폭입니다」라는 말이 거짓이 된다.
    private var previewRows: NSAttributedString {
        let quiet: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        guard !sessions.isEmpty else {
            return NSAttributedString(string: S.noSessionsPeriod, attributes: quiet)
        }
        let formatter = RowFormatter(settings: settings,
                                     nameWidth: RowFormatter.nameWidth(for: sessions))
        let rows = RowTypesetter.rows(for: sessions, formatter: formatter).prefix(6)
        let out = NSMutableAttributedString()
        for row in rows {
            if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(row)
        }
        if settings.showSummary, let memory = MetricsSampler.systemMemory() {
            let agent = sessions.compactMap { $0.metrics?.memoryBytes }.reduce(0, +)
            out.append(NSAttributedString(
                string: "\n\n" + MetricFormat.systemSummary(memory, agentBytes: agent),
                attributes: quiet))
        }
        // 줄 사이에 끼운 줄바꿈에도 같은 문단 양식을 태운다. 안 태우면 그 글자만
        // 기본 양식이 되어 줄 간격이 한 칸씩 들쭉날쭉해진다.
        if let paragraph = rows.first?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) {
            out.addAttribute(.paragraphStyle, value: paragraph,
                             range: NSRange(location: 0, length: out.length))
        }
        return out
    }
}

// MARK: - 탭 묶음

struct SettingsWindowView: View {
    let sessionsProvider: () -> [Session]

    var body: some View {
        TabView {
            LayoutSettingsView(sessionsProvider: sessionsProvider)
                .tabItem { Label(S.tabDisplay, systemImage: "list.bullet") }
            PanelSettingsView()
                .tabItem { Label(S.tabPanel, systemImage: "macwindow.on.rectangle") }
            MemoryView(sessionsProvider: sessionsProvider)
                .tabItem { Label(S.tabMemory, systemImage: "memorychip") }
            StatsView()
                .tabItem { Label(S.tabStats, systemImage: "chart.bar") }
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

// MARK: - 미리보기 그리기

/// 미리보기를 **메뉴와 같은 그리기**로 태운다.
///
/// SwiftUI `Text` 로는 못 그린다. 줄의 칸은 `NSTextTab` 정지점으로 서고 그 정지점은
/// 문단 양식에 박혀 있는데, SwiftUI 쪽으로 옮기면 그 양식이 그대로 태워진다는 보장이
/// 없다. 여기서 따로 그리기 시작하면 미리보기가 실제와 어긋나고, 어긋난 미리보기는
/// 손잡이를 만져 보는 뜻 자체를 없앤다 — 「폭이 곧 메뉴 폭입니다」가 거짓말이 된다.
struct RowPreview: NSViewRepresentable {

    let text: NSAttributedString

    func makeNSView(context: Context) -> AttributedRowsView { AttributedRowsView() }

    func updateNSView(_ view: AttributedRowsView, context: Context) { view.text = text }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AttributedRowsView,
                      context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// 속성 문자열 여러 줄을 그대로 그리는 뷰.
final class AttributedRowsView: NSView {

    var text = NSAttributedString() {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// 위에서 아래로 쌓아야 첫 줄이 위에 온다.
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let unbounded = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        let box = text.boundingRect(with: unbounded,
                                    options: [.usesLineFragmentOrigin, .usesFontLeading])
        return NSSize(width: ceil(box.width), height: ceil(box.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        text.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

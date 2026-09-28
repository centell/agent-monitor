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

                // 지표와 같은 꼴로 한 줄 더 둔다. 재는 것이 프로세스가 아니라 기록이라
                // 짝이 다르므로 줄을 나눴다 — 다섯을 한 줄에 몰면 무엇이 한 짝인지 사라진다.
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(S.tokenMetrics) {
                        HStack(spacing: 14) {
                            Toggle(S.metricContext, isOn: $settings.showContext)
                            Toggle(S.metricTokens, isOn: $settings.showTokens)
                        }
                    }
                    // 두 숫자가 무슨 뜻인지 켠 사람에게만 적는다. 늘 띄워 두면 배경이 된다.
                    if settings.showTokens {
                        Text(S.tokenNote).font(.caption).foregroundStyle(.tertiary)
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

                // 출처 표시 바로 밑에 둔다 — 엔진 색이 칠하는 곳이 바로 그 출처라서.
                Picker(S.engineTint, selection: $settings.engineTint) {
                    ForEach(EngineTint.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(S.tintRepo, isOn: $settings.tintRepo)

                Picker(S.codexAppWindow, selection: $settings.codexAppWindow) {
                    Text(S.windowOff).tag(0.0)
                    Text(S.minutes(10)).tag(10.0)
                    Text(S.minutes(30)).tag(30.0)
                    Text(S.hours(12)).tag(720.0)
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            // **제 키를 스스로 말하게 한다.** 예전에는 여기에 높이를 못 박아 두고
            // 「손잡이를 더할 때 이 값도 한 줄만큼 올려라」고 적어 두었는데, 그 주석을
            // 읽고도 빠뜨리면 마지막 줄이 조용히 잘린다 (실측: 실제로 한 번 잘렸다).
            // `fixedSize` 로 접히지 않게 못 박아 두면 Form 이 제 내용만큼 자라고,
            // 넘치는 몫은 바깥 `ScrollView` 가 받는다 — 손잡이가 몇이든 맞는다.
            .fixedSize(horizontal: false, vertical: true)
            // **Form 은 제 안에 스크롤 뷰를 하나 더 들고 있다.** 키를 스스로 말하게 해 두어도
            // 그 안쪽 뷰가 휠을 삼켜서, 손잡이 위에서 굴리면 아무 일도 안 일어나고 목록
            // **바깥**(미리보기)에 올려야만 창이 움직였다. 안쪽 스크롤을 잠가 두면 휠이
            // 바깥 `ScrollView` 로 넘어간다 — 어디에 올려 두고 굴려도 같게 움직인다.
            .scrollDisabled(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(S.preview)
                    .font(.headline)
                // 가로로 흐르게 둔다. 줄을 **제 폭 그대로** 그려야 「폭이 곧 메뉴 폭」이
                // 참인데, 그 폭이 창보다 넓을 수 있다. 굽히면 거짓이 되고, 안 굽히면
                // 창을 밀어내 좌우가 잘린다 — 실측에서 640pt 창의 양옆이 날아갔다.
                ScrollView(.horizontal) {
                    LivePreview(sessionsProvider: sessionsProvider)
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
    }
}

/// 미리보기 — **2초마다 새로 그리는 것은 이 칸뿐이다.**
///
/// 전에는 세션 목록이 손잡이 화면 전체의 상태라, 2초마다 위의 grouped `Form` 까지 통째로
/// 다시 계산됐다. 창을 열어 둔 판에서 CPU 가 10분에 14초 → 450초로 불어났고, 그때 표본에
/// 잡힌 것이 `GroupedFormRowLayout` 과 Observation 추적 등록이었다 (2026-09-28 실측).
/// 바뀌는 것은 미리보기뿐이니 그 칸만 제 상태를 들고 다시 그린다.
struct LivePreview: View {

    @ObservedObject private var settings = Settings.shared
    let sessionsProvider: () -> [Session]

    @State private var sessions: [Session] = []

    var body: some View {
        RowPreview(text: previewRows)
            .onAppear { sessions = sessionsProvider() }
            .every(2) { sessions = sessionsProvider() }
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

// MARK: - 정보

/// 「이 앱은 무엇이고, 새 판이 나왔는가」.
///
/// 업데이트 손잡이는 처음에 「표시」 탭에 있었는데 결이 맞지 않았다 — 그 탭은 **목록이
/// 어떻게 보이나**를 모아 둔 자리다. 판·출처·라이선스와 한 묶음으로 여기로 옮긴다.
struct AboutView: View {

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updates = UpdateCheck.shared

    /// 「마지막 확인 …분 전」이 멈춰 있지 않게 30초마다 다시 센다.
    @State private var now = Date()

    private static let repository = URL(string: "https://github.com/centell/agent-monitor")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AgentMonitor").font(.title3.weight(.semibold))
                        // 번들 밖(CLI)에서는 제 판을 모른다. 그때는 지어내지 않고 «—» 를 둔다.
                        Text(UpdateCheck.currentVersion ?? "—")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Form {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Toggle(S.checkUpdates, isOn: $settings.checkForUpdates)
                            Spacer()
                            // 눌러 보고 「아무 일도 안 일어났다」가 되지 않도록 결과를 옆에 적는다.
                            if let status = updates.status {
                                Text(status).font(.caption).foregroundStyle(.tertiary)
                            }
                            Button(S.checkNow) { UpdateCheck.shared.check(force: true) }
                        }
                        Text(S.checkUpdatesNote).font(.caption).foregroundStyle(.tertiary)
                        Text(S.lastChecked(updates.lastChecked.map { now.timeIntervalSince($0) }))
                            .font(.caption).foregroundStyle(.tertiary)
                    }

                    // 새 판이 있을 때만 나온다. 메뉴를 열지 않아도 여기서 보이고,
                    // 여기서 바로 넣을 수 있다.
                    if let update = updates.found {
                        LabeledContent(S.updateFound(update.version)) {
                            HStack(spacing: 8) {
                                Button(S.updateOpenPage) { NSWorkspace.shared.open(update.pageURL) }
                                Button(S.installNow) { UpdateCheck.shared.install(update) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    LabeledContent(S.aboutRepository) {
                        Link("github.com/centell/agent-monitor", destination: Self.repository)
                    }
                    LabeledContent(S.aboutLicense) { Text("MIT © 2026 Centell") }
                }
                .formStyle(.grouped)
                .fixedSize(horizontal: false, vertical: true)
                .scrollDisabled(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 다른 탭에 있다 돌아오면 그동안 멈춰 있던 「…분 전」부터 바로잡는다.
        .onAppear { now = Date() }
        .every(30) { now = Date() }
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
            // 애드온 칸. **애드온이 없어도 선다** — 「없다」를 말하고 「넣는 길」을 여는
            // 자리라, 비었을 때가 오히려 쓸모 있다.
            //
            // **애드온의 설정은 이 안으로 들어간다.** 전에는 애드온마다 최상위 탭을 하나씩
            // 내줬는데, 그러면 탭 줄이 애드온 수만큼 자란다 — 여섯에서 이미 빠듯했다.
            // 탭 줄은 앱이 정하는 것이지 남이 늘리는 것이 아니다.
            //
            // **「정보」 앞에 둔다.** 「정보」는 앱이 무엇인지를 적는 자리라 관례상 맨 뒤고,
            // 그 뒤에 손잡이가 붙으면 거기서 끝인 줄 알았던 사람이 한 칸을 더 보게 된다.
            // 릴리즈판에는 이 칸이 없다 (`ADDONS`, `build.sh`).
            #if ADDONS
            AddonsView()
                .tabItem { Label(S.tabAddons, systemImage: "puzzlepiece.extension") }
            #endif
            AboutView()
                .tabItem { Label(S.tabAbout, systemImage: "info.circle") }
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
        .every(3) { refresh() }
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

/// 손잡이 창.
///
/// 앞으로 끌어오는 일은 `AppActivation` 이 한다 — 창이 둘이 된 뒤로는 닫는 쪽이 저 혼자
/// 메뉴바로 돌아가면 안 되기 때문에, 그 판단을 한 곳에 모아 두었다.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowController()
    private var window: NSWindow?

    /// **창 틀은 남기고, 안에 든 화면은 닫을 때 버린다.**
    ///
    /// 틀을 남기는 까닭은 `AppActivation` 이 창을 자취로 담기 때문이다(그쪽 주석 참고).
    /// 화면을 버리는 까닭은 실측이다 — 전에는 화면째 남아, 닫은 뒤에도 SwiftUI 트리와
    /// 그 안의 타이머·관찰 추적이 그대로 돌았다. 창을 닫고 나서도 CPU 가 10분에 120초씩
    /// 들었고(열기 전은 9초), 앱을 다시 켜야만 돌아왔다 (2026-09-28).
    /// 다시 열 때 새로 짓는다. 고르던 탭이 처음으로 돌아가는 것은 그 값이다.
    func show(sessionsProvider: @escaping () -> [Session]) {
        let w: NSWindow
        if let existing = window {
            w = existing
        } else {
            w = NSWindow(contentViewController: Self.content(sessionsProvider))
            w.title = S.windowTitle
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        if w.contentViewController == nil {
            // 새 화면을 끼우면 창이 제 크기로 다시 맞춰진다. 사람이 옮기고 늘려 둔 자리를 지킨다.
            let frame = w.frame
            w.contentViewController = Self.content(sessionsProvider)
            w.setFrame(frame, display: false)
        }
        AppActivation.enter(w)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    private static func content(_ sessionsProvider: @escaping () -> [Session]) -> NSViewController {
        NSHostingController(rootView: SettingsWindowView(sessionsProvider: sessionsProvider))
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        AppActivation.leave(w)
        w.contentViewController = nil
    }
}

// MARK: - 되풀이

extension View {

    /// 이 뷰가 **보이는 동안만** `seconds` 마다 `action` 을 부른다.
    ///
    /// `Timer.publish(...).autoconnect()` 를 뷰의 속성으로 두면 부모가 다시 그려질 때마다
    /// 타이머가 새로 서고, 탭을 옮기거나 창을 닫아도 그 수명이 뷰가 아니라 붙든 쪽을 따른다.
    /// `.task` 는 뷰가 나타날 때 서고 사라질 때 취소된다 — 안 보이는 탭은 돌지 않는다.
    /// 애드온도 쓴다 — 설정창의 애드온 칸이 같은 창 안에 서므로 같은 수명을 따라야 한다.
    public func every(_ seconds: Double, perform action: @escaping () -> Void) -> some View {
        task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { break }
                action()
            }
        }
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

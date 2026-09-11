import AppKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("-h") || args.contains("--help") {
    print(S.helpText)
    exit(0)
}

let claudeSource = ClaudeCodeSource()
let claudeAppSource = ClaudeAppSource()
let codexSource = CodexSource()
let codexAppSource = CodexAppSource()

/// 문서용 그림을 찍는 모드. 지어낸 세션만 그린다 (`DemoSource`).
///
/// 설정에 남지 않는다 — 켜는 길이 이 인자 하나뿐이라, 실수로 켜 둔 채 다음 실행까지
/// 지어낸 줄을 보게 되는 일이 없다.
let demoMode = args.contains("--demo")

/// 어느 판을 그릴지. `--demo quiet` 로 «아무도 안 기다리는 화면» 을 찍는다.
let demoScene = args.contains("quiet") ? DemoSource.Scene.quiet : .busy

// 레지스트리를 직접 읽는 출처를 앞에 둔다 — 겹치면 앞선 쪽이 남는다.
let source: SessionSource = demoMode
    ? DemoSource(scene: demoScene)
    : CompositeSource([claudeSource, claudeAppSource, codexSource, codexAppSource])

/// 한 번 실행하고 끝나는 모드용. CPU 사용률은 두 표본의 차이로만 구할 수 있으므로
/// 잠깐 사이를 두고 두 번 잰다.
func measuredSessions(sampleCPU: Bool) -> ([Session], SystemMemory?) {
    // 지어낸 세션에는 잴 프로세스가 없다. 지표도 시스템 요약도 함께 지어낸 것을 쓴다 —
    // 안 그러면 찍는 사람의 맥 메모리가 그림에 실린다.
    guard !demoMode else { return (source.scan().sortedForDisplay(), DemoSource.systemMemory) }
    let sampler = MetricsSampler()
    var scanned = source.scan()
    if sampleCPU {
        _ = sampler.sample(pids: scanned.map(\.hostPid))
        Thread.sleep(forTimeInterval: 0.5)
    }
    let metrics = sampler.sample(pids: scanned.map(\.hostPid))
    for index in scanned.indices { scanned[index].metrics = metrics[scanned[index].hostPid] }
    return (scanned.sortedForDisplay(), MetricsSampler.systemMemory())
}

if args.contains("--roots") {
    var roots = claudeSource.accountRoots()
    // codex 는 계정을 나누지 않는다. 홈이 하나뿐이므로 있을 때만 더한다.
    if FileManager.default.fileExists(atPath: codexSource.root.appendingPathComponent("sessions").path) {
        roots.append(codexSource.root)
    }
    if FileManager.default.fileExists(atPath: claudeAppSource.root.path) {
        roots.append(claudeAppSource.root)
    }
    print(S.roots(roots.count))
    for root in roots { print("  \(root.path)") }
    exit(0)
}

if args.contains("--stats") {
    // 며칠치를 볼지. `--stats 30` 처럼 뒤에 숫자를 붙인다. 보관 기간을 넘겨 물어도
    // 없는 날은 그냥 빠지므로, 머리글에 «기록 며칠치» 를 함께 적어 둔다.
    let days = args.compactMap { Int($0) }.first.map { min(max($0, 1), 30) } ?? 7
    guard let report = StatsReport.build(days: days) else {
        print(StatsReport.hasRecords(days: days) ? S.statsAwayOnly : S.statsNoData)
        exit(0)
    }
    print(S.statsHeader(days: days, dataDays: report.dataDays, hours: report.overall.presentHours) + "\n")
    // 라벨 칸을 채운 뒤에도 두 칸을 더 둔다. 딱 맞는 라벨(`Actually running`)이
    // 값과 맞붙어 한 낱말처럼 읽히는 것을 막는다.
    func line(_ label: String, _ value: String) {
        print("  " + label.paddedDisplay(to: 16) + "  " + value)
    }
    let all = report.overall
    line(S.statsSessions, S.statsMeanMax(all.meanSessions, all.maxSessions))
    line(S.statsRunning, S.statsMean(all.meanRunning))
    line(S.statsQueue, S.statsQueueSplit(none: all.queueNone,
                                         one: all.queueOne,
                                         many: all.queueMany))
    line(S.statsWaits, S.statsWaitSplit(median: report.waitMedian,
                                        longest: report.waitLongest,
                                        total: report.waitTotal,
                                        count: report.waitCount))
    line(S.statsMemory, S.statsMemorySplit(mean: MetricFormat.size(all.meanAgentBytes),
                                           peak: MetricFormat.size(all.agentPeak),
                                           swap: MetricFormat.size(all.meanSwapBytes)))

    /// 표본이 이보다 적은 칸은 빼고 몇 칸을 뺐는지 밝힌다.
    /// 2분짜리 칸의 「100%」는 습관이 아니라 우연이다.
    let thinFloor = 5.0
    func sliceRow(_ when: String, _ present: String, _ sessions: String,
                  _ running: String, _ queue: String) {
        print("  " + when.paddedDisplay(to: 8) + present.rightAligned(to: 10)
              + sessions.rightAligned(to: 9) + running.rightAligned(to: 9)
              + queue.rightAligned(to: 12))
    }
    func table(_ title: String, _ column: String, _ slices: [StatsReport.Slice],
               label: (Int) -> String) {
        let shown = slices.filter { $0.bin.presentMinutes >= thinFloor }
        guard !shown.isEmpty else { return }
        print("\n" + title)
        sliceRow(column, S.statsColPresent, S.statsColSessions,
                 S.statsColRunning, S.statsColQueueMany)
        for slice in shown {
            sliceRow(label(slice.key),
                     String(format: "%.1fh", slice.bin.presentHours),
                     String(format: "%.1f", slice.bin.meanSessions),
                     String(format: "%.1f", slice.bin.meanRunning),
                     "\(Int((slice.bin.queueMany * 100).rounded()))%")
        }
        let thin = slices.count - shown.count
        if thin > 0 { print(S.statsThinNote(thin, minutes: Int(thinFloor))) }
    }
    table(S.statsByHour, S.statsColHour, report.byHour, label: S.hourLabel)
    table(S.statsByWeekday, S.statsColWeekday, report.byWeekday, label: S.weekdayLabel)

    print("\n" + S.statsFootnote)
    exit(0)
}

if args.contains("--memory") {
    let (sessions, _) = measuredSessions(sampleCPU: false)
    let report = MemoryReport.build(sessions: sessions)
    func gb(_ v: UInt64) -> String { MetricFormat.size(v) }

    if let system = report.system {
        print(S.thisMac)
        print("  " + S.used.paddedDisplay(to: 12) + "\(gb(system.usedBytes)) / \(gb(system.totalBytes))")
        print("  " + S.swap.paddedDisplay(to: 12) + gb(system.swapUsedBytes))
        print("  " + S.compressed.paddedDisplay(to: 12) + gb(system.compressedBytes))
        print("")
    }
    print(S.agentTotal(gb(report.agentBytes), sessions: sessions.count, processes: report.agentProcessCount))

    if !report.suspected.isEmpty {
        print("")
        print(S.suspectedCLIHeader)
        for entry in report.suspected {
            print("  \(entry.name.fitted(to: 34))\(gb(entry.bytes).rightAligned(to: 8))   → \(entry.suspectedOwner ?? "")")
        }
    }

    print("")
    print(S.outsideSessions)
    for entry in report.others.prefix(15) {
        let count = entry.processCount > 1 ? S.countSuffix(entry.processCount) : ""
        print("  \(entry.name.fitted(to: 34))\(gb(entry.bytes).rightAligned(to: 8))\(count)")
    }
    print("")
    print(S.floorNote)
    exit(0)
}

if args.contains("--json") {
    // 토큰은 기록을 훑어야 나온다. 화면 스위치와 무관하게 늘 낸다 —
    // 기계가 읽는 값이 사람의 손잡이에 따라 흔들리면 안 된다.
    TokenLedger.shared.countsCumulative = true
    TokenLedger.shared.wantsTokens = true
    let (sessions, _) = measuredSessions(sampleCPU: true)
    let iso = ISO8601DateFormatter()
    let payload: [[String: Any]] = sessions.map { s in
        var row: [String: Any] = [
            "sessionId": s.id,
            "pid": Int(s.pid),
            "name": s.name,
            "source": s.sourceTag,
            "runsInApp": s.runsInApp,
            "cwd": s.cwd,
            "status": s.state.raw,
            "label": s.state.label,
            "needsAttention": s.state.needsAttention,
            "canJump": SessionJump.canJump(s),
            "estimated": s.isEstimated,
            "pinned": s.isPinned,
            "accountRoot": s.accountRoot.path,
        ]
        row["kind"] = s.kind
        // 세션이 이어졌으면 창과 트리를 쥔 프로세스가 따로 있다. 이 둘이 어긋난 것이
        // 「눌러도 안 가는 줄」의 원인이었으므로 기계가 읽는 값에도 낸다.
        row["hostPid"] = Int(s.hostPid)
        row["continuedFromPid"] = s.continuedFromPid.map { Int($0) }
        row["currentTool"] = s.currentTool
        // 표시 설정과 무관하게 낸다. 기계가 읽는 값이 사람의 손잡이에 따라 흔들리면 안 된다.
        row["reason"] = s.reason
        row["deepLink"] = s.deepLink?.absoluteString
        row["startedAt"] = s.startedAt.map { iso.string(from: $0) }
        row["statusUpdatedAt"] = s.statusUpdatedAt.map { iso.string(from: $0) }
        row["lastActivity"] = s.lastActivity.map { iso.string(from: $0) }
        row["ageSeconds"] = s.age().map { Int($0) }
        row["memoryBytes"] = s.metrics.map { Int($0.memoryBytes) }
        row["cpuPercent"] = s.metrics?.cpuPercent.map { ($0 * 10).rounded() / 10 }
        row["descendantCount"] = s.metrics.map { $0.descendantCount }
        row["contextTokens"] = s.usage?.context.map { Int($0) }
        // 「새로 태운 것」과 「전부」를 따로 낸다. 하나로 합치면 어느 쪽을 골라도
        // 읽는 쪽이 오해한다 — 둘은 캐시 재사용분만큼 갈린다.
        row["freshTokens"] = s.usage?.fresh.map { Int($0) }
        row["totalTokens"] = s.usage?.total.map { Int($0) }
        return row.compactMapValues { $0 }
    }
    let data = try JSONSerialization.data(withJSONObject: payload,
                                          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

if args.contains("--list") {
    // 여기는 사람이 보는 줄이라 화면 스위치를 그대로 따른다. 꺼 두셨으면 훑지 않는다.
    TokenLedger.shared.countsCumulative = Settings.shared.showTokens
    TokenLedger.shared.wantsTokens = Settings.shared.showTokens || Settings.shared.showContext
    let (sessions, systemMemory) = measuredSessions(sampleCPU: true)
    if sessions.isEmpty {
        print(S.noSessionsPeriod)
        exit(0)
    }
    let waiting = sessions.attentionCount
    print(S.listHeader(waiting: waiting, total: sessions.count) + "\n")
    let formatter = RowFormatter(settings: .shared,
                                 nameWidth: RowFormatter.nameWidth(for: sessions))
    for s in sessions {
        print(" " + formatter.row(for: s).text)
    }
    if Settings.shared.showSummary, let memory = systemMemory {
        let agentBytes = sessions.compactMap { $0.metrics?.memoryBytes }.reduce(0, +)
        print("\n" + MetricFormat.systemSummary(memory, agentBytes: agentBytes))
    }
    exit(0)
}

// 기본 — 메뉴바에 띄운다.
let app = NSApplication.shared
let controller = MenuBarController(source: source, demo: demoMode)
app.delegate = controller
app.run()

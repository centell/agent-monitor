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
// 레지스트리를 직접 읽는 출처를 앞에 둔다 — 겹치면 앞선 쪽이 남는다.
let source = CompositeSource([claudeSource, claudeAppSource, codexSource, codexAppSource])

/// 한 번 실행하고 끝나는 모드용. CPU 사용률은 두 표본의 차이로만 구할 수 있으므로
/// 잠깐 사이를 두고 두 번 잰다.
func measuredSessions(sampleCPU: Bool) -> ([Session], SystemMemory?) {
    let sampler = MetricsSampler()
    var scanned = source.scan()
    if sampleCPU {
        _ = sampler.sample(pids: scanned.map(\.pid))
        Thread.sleep(forTimeInterval: 0.5)
    }
    let metrics = sampler.sample(pids: scanned.map(\.pid))
    for index in scanned.indices { scanned[index].metrics = metrics[scanned[index].pid] }
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
        return row.compactMapValues { $0 }
    }
    let data = try JSONSerialization.data(withJSONObject: payload,
                                          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

if args.contains("--list") {
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
let controller = MenuBarController(source: source)
app.delegate = controller
app.run()

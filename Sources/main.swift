import AppKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("-h") || args.contains("--help") {
    print("""
    agent-monitor — 로컬 에이전트 세션 중 무엇이 나를 기다리는지 보여준다

    사용법
      agent-monitor            메뉴바에 띄운다
      agent-monitor --list     사람이 읽는 표로 한 번 출력하고 끝낸다
      agent-monitor --json     JSON 으로 출력하고 끝낸다 (검증용)
      agent-monitor --roots    훑는 계정 루트를 보여준다

    메뉴바에는 «기다리는 중/전체» 숫자만 띄운다. 세션이 몇 개든 잘라내지 않는다.
    상태는 Claude Code 가 <계정루트>/sessions/<pid>.json 에 직접 적은 것을 그대로 읽는다.
    """)
    exit(0)
}

let source = ClaudeCodeSource()

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
    let roots = source.accountRoots()
    print("계정 루트 \(roots.count)개")
    for root in roots { print("  \(root.path)") }
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
            "cwd": s.cwd,
            "status": s.state.raw,
            "label": s.state.label,
            "needsAttention": s.state.needsAttention,
            "estimated": s.isEstimated,
            "accountRoot": s.accountRoot.path,
        ]
        row["kind"] = s.kind
        row["currentTool"] = s.currentTool
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
        print("살아있는 세션이 없습니다.")
        exit(0)
    }
    let waiting = sessions.attentionCount
    print("\(waiting)/\(sessions.count)  — 기다리는 중 \(waiting) · 전체 \(sessions.count)\n")
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

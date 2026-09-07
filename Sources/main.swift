import Foundation

// 1단계 — 수집만. 화면은 아직 없다.
// `--json` 은 레지스트리와 대조해 정확도를 재기 위한 검증용 출구다.

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("-h") || args.contains("--help") {
    print("""
    agent-monitor — 로컬 에이전트 세션 중 무엇이 나를 기다리는지 보여준다

    사용법
      agent-monitor            사람이 읽는 표로 출력
      agent-monitor --json     JSON 으로 출력 (검증용)
      agent-monitor --roots    훑는 계정 루트를 보여준다

    상태는 Claude Code 가 <계정루트>/sessions/<pid>.json 에 직접 적은 것을 그대로 읽는다.
    """)
    exit(0)
}

let source = ClaudeCodeSource()

if args.contains("--roots") {
    let roots = source.accountRoots()
    print("계정 루트 \(roots.count)개")
    for r in roots { print("  \(r.path)") }
    exit(0)
}

let sessions = source.scan().sortedForDisplay()

if args.contains("--json") {
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
        return row.compactMapValues { $0 }
    }
    let data = try JSONSerialization.data(withJSONObject: payload,
                                          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

// 사람이 읽는 표
func elapsed(_ seconds: TimeInterval?) -> String {
    guard let s = seconds, s >= 0 else { return "—" }
    if s < 60  { return "\(Int(s))s" }
    if s < 3600 { return "\(Int(s / 60))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    return "\(Int(s / 86400))d"
}

if sessions.isEmpty {
    print("살아있는 세션이 없습니다.")
    exit(0)
}

let waiting = sessions.attentionCount
print("\(waiting)/\(sessions.count)  — 기다리는 중 \(waiting) · 전체 \(sessions.count)")
print("")

let nameWidth = max(12, sessions.map(\.name.count).max() ?? 12)
for s in sessions {
    let name = s.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
    let label = s.state.label.padding(toLength: 12, withPad: " ", startingAt: 0)
    let tool = (s.currentTool ?? "—").padding(toLength: 16, withPad: " ", startingAt: 0)
    let mark = s.isEstimated ? " (추정)" : ""
    print(" \(s.state.symbol) \(name)  \(label) \(tool) \(elapsed(s.age()))\(mark)")
}

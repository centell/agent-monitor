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

if args.contains("--roots") {
    let roots = source.accountRoots()
    print("계정 루트 \(roots.count)개")
    for root in roots { print("  \(root.path)") }
    exit(0)
}

if args.contains("--json") {
    let sessions = source.scan().sortedForDisplay()
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

if args.contains("--list") {
    let sessions = source.scan().sortedForDisplay()
    if sessions.isEmpty {
        print("살아있는 세션이 없습니다.")
        exit(0)
    }
    let waiting = sessions.attentionCount
    print("\(waiting)/\(sessions.count)  — 기다리는 중 \(waiting) · 전체 \(sessions.count)\n")
    let nameWidth = max(12, sessions.map(\.name.count).max() ?? 12)
    for s in sessions {
        let name = s.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
        let label = s.state.label.padding(toLength: 12, withPad: " ", startingAt: 0)
        let tool = (s.currentTool ?? "—").padding(toLength: 16, withPad: " ", startingAt: 0)
        let mark = s.isEstimated ? " (추정)" : ""
        print(" \(s.state.symbol) \(name)  \(label) \(tool) \(MenuBarController.elapsed(s.age()))\(mark)")
    }
    exit(0)
}

// 기본 — 메뉴바에 띄운다.
let app = NSApplication.shared
let controller = MenuBarController(source: source)
app.delegate = controller
app.run()

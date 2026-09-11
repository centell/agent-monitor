import Foundation

/// 문서에 실을 그림을 찍기 위한 **지어낸 목록**.
///
/// 실물 화면을 찍으면 그 순간 도는 세션 이름이 그대로 나간다. 남의 일을 하는 자리에서는
/// 그것이 곧 고객사 이름이라, 리드미에 올릴 수 없다. 그렇다고 그림판에서 그려 붙이면
/// **실제와 어긋난 그림**이 남는다 — 이 저장소가 미리보기를 따로 그리지 않는 것과 같은 이유다.
///
/// 그래서 **세션만 지어내고 그리는 길은 그대로 쓴다.** 여기서 나온 줄도 `RowFormatter` 를
/// 거쳐 메뉴·상시 창·설정 미리보기·`--list` 로 간다. 보이는 것은 진짜 코드가 그린 것이다.
///
/// **진짜 기록에는 손대지 않는다.** 이 모드에서는 쓰임새 기록을 남기지 않고(지어낸 세션이
/// 통계에 섞이면 그 통계는 영영 못 믿는다), 프로세스도 재지 않는다(잴 프로세스가 없다).
/// 켜는 길은 `--demo` 하나뿐이고 설정에 남지 않는다.
struct DemoSource: SessionSource {
    let sourceName = "demo"

    /// 어느 판을 그릴 것인가.
    ///
    /// 문서에는 **아무도 안 기다리는 화면**도 실린다 — 메뉴바 숫자가 `0/4` 로 흐려진
    /// 그림이 그렇다. 기다리는 줄이 있는 판으로는 그 그림을 못 찍으므로 판을 둘 둔다.
    enum Scene: String {
        /// 손이 필요한 줄이 섞인 판. 기본.
        case busy
        /// 아무도 안 기다리는 판 — 전부 도는 중이다.
        case quiet
    }

    var scene: Scene = .busy

    /// 시스템 요약 줄에 쓸 값도 지어낸다. 안 그러면 찍는 사람의 맥 메모리가 그림에 실린다.
    static let systemMemory = SystemMemory(usedBytes: 15_600_000_000,
                                           totalBytes: 25_800_000_000,
                                           swapUsedBytes: 12_300_000_000,
                                           compressedBytes: 3_600_000_000)

    /// 줄 하나를 짓는 재료.
    private struct Fixture {
        let id: String
        let pid: Int32
        let name: String
        let source: String
        let runsInApp: Bool
        let state: SessionState
        /// 마지막 활동이 몇 초 전인가. 찍을 때마다 같은 시간이 나오도록 **지금 기준**으로 센다.
        let secondsAgo: TimeInterval
        let tool: String?
        let reason: String?
        let memoryBytes: UInt64?
        let cpuPercent: Double?
        let context: UInt64?
        let fresh: UInt64?
        let total: UInt64?
        let estimated: Bool
    }

    /// 한 화면에 이 앱이 가르는 것들이 **모두 한 번씩** 나오도록 고른다 —
    /// 상태 넷, 출처 넷 중 셋, 지표를 못 재는 줄 하나(앱 스레드), 추정으로 내려간 줄 하나.
    private static let fixtures: [Fixture] = [
        Fixture(id: "d0000001-0000-4000-8000-000000000001", pid: 2001,
                name: "payments-api", source: "claude", runsInApp: false,
                state: .waiting, secondsAgo: 120, tool: "Bash",
                reason: "Bash: pnpm build --filter web",
                memoryBytes: 640_000_000, cpuPercent: 0,
                context: 512_000, fresh: 640_000, total: 96_000_000, estimated: false),

        Fixture(id: "d0000002-0000-4000-8000-000000000002", pid: 2002,
                name: "docs-site", source: "claude", runsInApp: false,
                state: .idle, secondsAgo: 1_200, tool: nil,
                reason: "Shall I commit, or leave it for the review?",
                memoryBytes: 410_000_000, cpuPercent: 0,
                context: 88_000, fresh: 91_000, total: 12_000_000, estimated: false),

        Fixture(id: "d0000003-0000-4000-8000-000000000003", pid: 2003,
                name: "web-client", source: "claude", runsInApp: false,
                state: .busy, secondsAgo: 4, tool: "Read",
                reason: nil,
                memoryBytes: 830_000_000, cpuPercent: 12,
                context: 274_000, fresh: 310_000, total: 41_000_000, estimated: false),

        Fixture(id: "d0000004-0000-4000-8000-000000000004", pid: 2004,
                name: "data-pipeline", source: "codex", runsInApp: false,
                state: .shell, secondsAgo: 31, tool: "CommandExecution",
                reason: nil,
                memoryBytes: 720_000_000, cpuPercent: 3,
                context: 63_000, fresh: 74_000, total: 1_300_000, estimated: true),

        // 앱 스레드는 제 프로세스가 없어 메모리도 CPU 도 못 잰다. 토큰은 codex 가 적어 두므로
        // 잰다 — 그 어긋남이 화면에서 어떻게 보이는지가 이 줄의 일이다.
        Fixture(id: "d0000005-0000-4000-8000-000000000005", pid: 0,
                name: "design-tokens", source: "codex", runsInApp: true,
                state: .idle, secondsAgo: 300, tool: nil,
                reason: "Which of the two scales should I keep?",
                memoryBytes: nil, cpuPercent: nil,
                context: 109_000, fresh: 8_617, total: 634_000, estimated: false),
    ]

    /// 조용한 판. 같은 줄들을 쓰되 **손이 필요한 상태를 없앤다** — 줄을 따로 짓지 않는 것은
    /// 두 판이 서로 다른 앱처럼 보이지 않게 하려는 것이다.
    private static let quietFixtures: [Fixture] = fixtures.map {
        Fixture(id: $0.id, pid: $0.pid, name: $0.name, source: $0.source, runsInApp: $0.runsInApp,
                state: $0.state.needsAttention ? .busy : $0.state,
                secondsAgo: $0.secondsAgo, tool: $0.tool ?? "Read", reason: nil,
                memoryBytes: $0.memoryBytes, cpuPercent: $0.cpuPercent,
                context: $0.context, fresh: $0.fresh, total: $0.total, estimated: $0.estimated)
    }

    func scan() -> [Session] {
        let now = Date()
        return (scene == .quiet ? Self.quietFixtures : Self.fixtures).map { f in
            var session = Session(
                id: f.id,
                pid: f.pid,
                name: f.name,
                source: f.source,
                runsInApp: f.runsInApp,
                cwd: "/demo/\(f.name)",
                state: f.state,
                kind: f.runsInApp ? "thread" : "interactive",
                startedAt: now.addingTimeInterval(-3_600),
                statusUpdatedAt: now.addingTimeInterval(-f.secondsAgo),
                accountRoot: URL(fileURLWithPath: "/demo")
            )
            session.currentTool = f.tool
            session.lastActivity = now.addingTimeInterval(-f.secondsAgo)
            // «왜 기다리는가» 는 상태에 따라 다른 칸에서 나온다. 실물과 같은 자리에 넣어야
            // 마우스를 올렸을 때 실물과 같은 글이 뜬다.
            if f.state == .waiting { session.pendingCall = f.reason } else { session.lastSay = f.reason }
            session.isEstimated = f.estimated
            // **갈 곳을 준다.** 없으면 «눌러도 갈 데 없는 줄» 로 판정되어 목록이 통째로
            // 흐려지고 상태 표식의 색까지 빠진다 (`SessionRowView`). 진짜 세션은 터미널이나
            // 딥링크를 가지므로, 색이 빠진 그림은 실제보다 못하게 보이는 거짓이 된다.
            session.deepLink = URL(string: "x-agent-monitor-demo://\(f.name)")
            if let bytes = f.memoryBytes {
                session.metrics = SessionMetrics(memoryBytes: bytes,
                                                 cpuPercent: f.cpuPercent,
                                                 descendantCount: 4)
            }
            if f.context != nil || f.fresh != nil || f.total != nil {
                session.usage = TokenUsage(context: f.context, fresh: f.fresh, total: f.total)
            }
            return session
        }
    }
}

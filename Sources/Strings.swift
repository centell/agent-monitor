import Foundation

/// 화면에 쓸 말.
enum Language: String, CaseIterable, Identifiable {
    case system, korean, english
    var id: String { rawValue }

    /// 고르는 자리에 보일 이름.
    ///
    /// 한국어·영어 항목은 **제 언어로** 적는다. 영어만 아는 사람이 「한국어」를 못 읽으면
    /// 되돌아올 길이 막힌다.
    var label: String {
        switch self {
        case .system:  return S.p("시스템 따름", "Follow system")
        case .korean:  return "한국어"
        case .english: return "English"
        }
    }
}

/// 두 언어를 **나란히** 둔다.
///
/// `.lproj` 표준 방식을 쓰지 않는 이유가 둘이다. `--list` 같은 CLI 는 번들 밖에서 도는데
/// `NSLocalizedString` 은 `Bundle.main` 을 찾으므로 CLI 에서는 늘 기본 언어만 나온다.
/// 그리고 여기서 필요한 것은 시스템 언어를 따르는 것이 아니라 **사용자가 직접 고르는 것**이다.
///
/// 짝을 한 줄에 붙여 두면 한쪽만 고치고 다른 쪽을 빠뜨리는 일이 눈에 띈다.
enum S {

    static var isKorean: Bool { Settings.shared.resolvedLanguage == .korean }

    /// 두 말 중 하나를 고른다.
    static func p(_ korean: String, _ english: String) -> String { isKorean ? korean : english }

    // MARK: 상태

    static var stateWaiting: String { p("승인 대기", "Approval") }
    static var stateIdle: String    { p("입력 대기", "Idle") }
    static var stateBusy: String    { p("작업 중", "Working") }
    static var stateShell: String   { p("셸 실행 중", "Shell") }
    static func stateUnknown(_ raw: String) -> String { p("알 수 없음(\(raw))", "Unknown(\(raw))") }

    // MARK: 메뉴

    static var noSessions: String   { p("살아있는 세션이 없습니다", "No live sessions") }
    static var settingsItem: String { p("설정…", "Settings…") }
    static var quitItem: String     { p("종료", "Quit") }
    static var estimated: String    { p("  (추정)", "  (est.)") }

    static func menuTooltip(waiting: Int, total: Int) -> String {
        waiting > 0
            ? p("\(waiting)개가 기다리는 중 · 전체 \(total)개", "\(waiting) waiting · \(total) total")
            : p("전체 \(total)개 · 기다리는 것 없음", "\(total) sessions · nothing waiting")
    }

    static var jumpHint: String {
        p("눌러서 이 세션의 터미널로 이동", "Click to focus this session's terminal")
    }
    static var jumpHintApp: String {
        p("눌러서 이 세션을 띄운 앱으로 이동", "Click to focus the app running this session")
    }
    static var pinHint: String {
        p("우클릭으로 고정 — 기다릴 때 맨 위로 올라옵니다",
          "Right-click to pin — it rises to the top while waiting")
    }
    static var unpinHint: String {
        p("우클릭으로 고정 해제", "Right-click to unpin")
    }
    static func descendants(_ count: Int) -> String {
        p("자손 프로세스 \(count)개 포함", "includes \(count) descendant processes")
    }

    // MARK: 요약

    /// 두 줄로 나눈다.
    ///
    /// 한 줄로 두면 49칸이 되어 세션 줄(38칸)보다 넓어지고, 메뉴는 가장 긴 줄에 맞춰지므로
    /// **요약 하나 때문에 메뉴 전체가 넓어진다.** 이름을 떼어 줄이는 방법도 있지만,
    /// 숫자에서 이름을 빼면 만든 사람에게만 뜻이 통하게 된다.
    static func systemSummary(used: Double, total: Double, swap: Double, agent: Double) -> String {
        isKorean
            ? String(format: "메모리 %.1f/%.1fGB · 스왑 %.1fGB\n에이전트 %.1fGB", used, total, swap, agent)
            : String(format: "Memory %.1f/%.1fGB · Swap %.1fGB\nAgents %.1fGB", used, total, swap, agent)
    }

    // MARK: 설정창

    static var windowTitle: String   { p("AgentMonitor 설정", "AgentMonitor Settings") }
    static var tabDisplay: String    { p("표시", "Display") }
    static var tabMemory: String     { p("메모리", "Memory") }

    static var language: String      { p("언어", "Language") }
    static var rowLayout: String     { p("줄 배치", "Row layout") }
    static var layoutSingle: String  { p("한 줄", "One line") }
    static var layoutDouble: String  { p("두 줄", "Two lines") }
    static var showStateLabel: String { p("상태를 글자로 보이기", "Show status as text") }
    static var showTool: String      { p("도구 이름 보이기", "Show tool name") }
    // 어디에 나오는지까지 적는다. 줄에는 안 나오므로, 켜도 목록이 그대로면 고장으로 보인다.
    static var showReason: String {
        p("마우스를 올리면 왜 기다리는지 보이기", "Show why it is waiting on hover")
    }
    static var metrics: String       { p("지표", "Metrics") }
    // 줄에 실제로 찍히는 말(RAM·CPU)을 그대로 쓴다. 「숫자」·「전부」로 적으면
    // 켜 보기 전에는 무엇이 나올지 알 수 없다.
    static var metricBar: String     { p("RAM 막대", "RAM bar") }
    static var metricValue: String   { "RAM GB" }
    static var metricCPU: String     { "CPU %" }
    static var showSummary: String   { p("아래에 시스템 요약 보이기", "Show system summary below") }
    static var refresh: String       { p("갱신 주기", "Refresh") }
    static func seconds(_ n: Int) -> String { p("\(n)초", "\(n)s") }
    static var sourceStyle: String   { p("출처 표시", "Source label") }
    static var styleShort: String    { p("앱만", "App only") }
    static var styleSymmetric: String { p("양쪽 다", "Both") }
    static var styleSymbol: String   { p("표식", "Mark") }
    static var codexAppWindow: String { p("codex 앱 스레드", "codex app threads") }
    static var windowOff: String     { p("안 보임", "Hidden") }
    static func minutes(_ n: Int) -> String { p("\(n)분", "\(n)m") }
    static func hours(_ n: Int) -> String   { p("\(n)시간", "\(n)h") }
    static var preview: String       { p("미리보기", "Preview") }
    static var previewNote: String {
        p("실제 세션을 메뉴와 같은 코드로 그린 것입니다. 폭이 곧 메뉴 폭입니다.",
          "Rendered from real sessions with the same code the menu uses. This width is the menu width.")
    }
    static var resetButton: String   { p("처음 모습으로", "Reset to defaults") }

    // MARK: 메모리 화면

    static var thisMac: String       { p("이 맥", "This Mac") }
    static var used: String          { p("사용 중", "Used") }
    static var swap: String          { p("스왑", "Swap") }
    static var compressed: String    { p("압축됨", "Compressed") }
    static var agentSessions: String { p("에이전트 세션", "Agent sessions") }
    static func processCount(_ n: Int) -> String { p("프로세스 \(n)개", "\(n) processes") }
    static var suspectedGroup: String { p("세션이 띄운 것으로 보이는 것", "Likely spawned by a session") }
    static var suspectedNote: String {
        p("작업 폴더로 미루어 본 **추정**입니다. 세션 합계에는 넣지 않았습니다.",
          "A **guess** from the working directory. Not counted in the session total.")
    }
    static var outsideSessions: String { p("세션 밖", "Outside sessions") }
    static func countSuffix(_ n: Int) -> String { p("   (\(n)개)", "   (\(n))") }
    static var memoryFootnote: String {
        p("30MB 미만은 생략했습니다. 세션 트리에 속한 것은 «에이전트 세션» 에만 셉니다.",
          "Under 30MB omitted. Anything inside a session tree is counted only under “Agent sessions”.")
    }
    static var measuring: String     { p("재는 중…", "Measuring…") }
    static var unknownProcess: String { p("(알 수 없음)", "(unknown)") }
    static func multipleSessions(_ n: Int) -> String {
        p("여러 세션 (\(n))", "multiple sessions (\(n))")
    }

    // MARK: 터미널 이동

    static var permissionTitle: String {
        p("터미널을 제어할 권한이 없습니다", "No permission to control Terminal")
    }
    static var permissionBody: String {
        p("""
          세션 창으로 이동하려면 Terminal 제어를 허용해야 합니다.

          시스템 설정 → 개인정보 보호 및 보안 → 자동화 에서
          AgentMonitor 아래의 Terminal 을 켜 주세요.
          """,
          """
          Focusing a session's window needs permission to control Terminal.

          System Settings → Privacy & Security → Automation,
          then enable Terminal under AgentMonitor.
          """)
    }
    static var okButton: String      { p("확인", "OK") }
    static var errScript: String     { p("스크립트를 만들지 못함", "could not build the script") }
    static func errNoHandler(_ scheme: String) -> String {
        p("\(scheme):// 를 열 수 있는 앱이 없음", "no app can open \(scheme)://")
    }
    static func errUnknown(_ code: Int) -> String {
        p("알 수 없는 오류(\(code))", "unknown error (\(code))")
    }
    static var logNoTTY: String      { p("터미널이 없는 세션입니다", "no terminal for this session") }
    static var logNoWindow: String {
        p("tty 는 있으나 Terminal 창을 못 찾았습니다", "has a tty but no Terminal window matched")
    }
    static func logFailed(_ message: String) -> String {
        p("이동 실패 — \(message)", "jump failed — \(message)")
    }

    // MARK: 명령줄

    static func roots(_ n: Int) -> String { p("계정 루트 \(n)개", "\(n) account roots") }
    static var noSessionsPeriod: String { p("살아있는 세션이 없습니다.", "No live sessions.") }
    static func listHeader(waiting: Int, total: Int) -> String {
        p("\(waiting)/\(total)  — 기다리는 중 \(waiting) · 전체 \(total)",
          "\(waiting)/\(total)  — \(waiting) waiting · \(total) total")
    }
    static func agentTotal(_ size: String, sessions: Int, processes: Int) -> String {
        p("에이전트 세션  \(size)  (세션 \(sessions)개 · 프로세스 \(processes)개)",
          "Agent sessions  \(size)  (\(sessions) sessions · \(processes) processes)")
    }
    static var suspectedCLIHeader: String {
        p("세션이 띄운 것으로 보이는 것  — 작업 폴더로 미루어 본 추정이며 위 합계에 넣지 않음",
          "Likely spawned by a session  — a guess from the working directory, not counted above")
    }
    static var floorNote: String { p("30MB 미만은 생략했습니다.", "Under 30MB omitted.") }

    static var helpText: String {
        p("""
          agent-monitor — 로컬 에이전트 세션 중 무엇이 나를 기다리는지 보여준다

          사용법
            agent-monitor            메뉴바에 띄운다
            agent-monitor --list     사람이 읽는 표로 한 번 출력하고 끝낸다
            agent-monitor --json     JSON 으로 출력하고 끝낸다 (검증용)
            agent-monitor --memory   이 맥의 메모리를 누가 쓰는지 보여준다
            agent-monitor --roots    훑는 계정 루트를 보여준다

          메뉴바에는 «기다리는 중/전체» 숫자만 띄운다. 세션이 몇 개든 잘라내지 않는다.

          줄을 우클릭하면 그 세션을 고정한다. 고정한 세션은 손을 기다릴 때 맨 위로
          올라오고, 메뉴에서는 바탕이 옅게 깔린다 (`--list` 는 색을 쓰지 않으므로
          순서로만 드러난다). 도는 중일 때는 자리를 옮기지 않는다.
          핀은 그 세션과 함께 산다. 세션을 껐다 켜면 다시 꽂아야 한다.

          손이 필요한 줄에 마우스를 올리면 왜 기다리는지가 나온다 — 승인 대기는 기다리고
          있는 호출을, 입력 대기는 마지막으로 건넨 말을. 줄에는 적지 않는다. 폭을 늘 차지하는
          대신 잘려 나가는 쪽이라 옮겼다. 기록에서 못 찾으면 추측하지 않고 아무것도 안 낸다.
          «표시» 설정에서 끌 수 있고, `--json` 의 `reason` 으로도 나온다.

          줄 앞의 출처로 어디서 온 세션인지 구분한다 —
          claude(터미널) · claude-app · codex(터미널) · codex-app.

          상태를 그대로 읽는 곳: 터미널 Claude Code(<계정루트>/sessions/<pid>.json) 와
          codex 앱(~/.codex 의 state_5·thread_history_1 DB 를 읽기 전용으로).
          Claude 앱과 터미널 codex 는 상태를 적지 않아 기록 끝에서 추정하고 «추정» 이라 적는다.

          codex 앱 스레드는 «아직 열려 있는가» 를 잴 수 없어 시간으로 자른다.
          도는 중인 것은 언제나 보이고, 끝난 것은 설정한 창 안의 것만 보인다 (기본 30분).
          앱 세션은 프로세스가 없어 메모리·CPU 가 비고, 누르면 그 앱으로 간다.
          """,
          """
          agent-monitor — shows which of your local agent sessions is waiting for you

          Usage
            agent-monitor            run in the menu bar
            agent-monitor --list     print a readable table once and exit
            agent-monitor --json     print machine-readable output and exit
            agent-monitor --memory   show what is using RAM on this machine
            agent-monitor --roots    show which account roots are scanned

          The menu bar shows only a "waiting/total" count. It never truncates the list.

          Right-click a row to pin that session. A pinned session rises to the top while
          it waits for you and gets a tinted background in the menu (--list has no color,
          so there it shows only in the order). While it is working, it keeps its place.
          A pin lives with its session — restart the session and you pin it again.

          Hover a row that needs you and it says why — an approval shows the call it is
          waiting on, an idle row the last thing it said to you. It is not in the row itself:
          there it cost width on every line and still arrived truncated. If the transcript
          does not show it, nothing is printed rather than a guess. Turn it off under
          Display; --json carries it as "reason".

          Each row is prefixed with where it came from —
          claude (terminal), claude-app, codex (terminal), codex-app.

          Status is verbatim for terminal Claude Code (<account-root>/sessions/<pid>.json)
          and for codex app threads (read-only from ~/.codex state_5 / thread_history_1).
          The Claude app and terminal codex write no status, so it is estimated from the
          transcript and marked "(est.)".

          A codex app thread cannot be checked for "still open", so it is cut by time:
          running threads always show, finished ones only within the window (default 30m).
          App sessions have no process, so memory/CPU is blank; clicking focuses the app.
          """)
    }
}

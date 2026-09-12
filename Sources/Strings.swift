import Foundation

/// 화면에 쓸 말.
enum Language: String, CaseIterable, Identifiable {
    case system, korean, english, japanese
    var id: String { rawValue }

    /// 고르는 자리에 보일 이름.
    ///
    /// 한국어·영어·일본어 항목은 **제 언어로** 적는다. 영어만 아는 사람이 「한국어」를 못 읽으면
    /// 되돌아올 길이 막힌다.
    var label: String {
        switch self {
        case .system:   return S.p("시스템 따름", "Follow system", "システムに従う")
        case .korean:   return "한국어"
        case .english:  return "English"
        case .japanese: return "日本語"
        }
    }
}

/// 세 언어를 **나란히** 둔다.
///
/// `.lproj` 표준 방식을 쓰지 않는 이유가 둘이다. `--list` 같은 CLI 는 번들 밖에서 도는데
/// `NSLocalizedString` 은 `Bundle.main` 을 찾으므로 CLI 에서는 늘 기본 언어만 나온다.
/// 그리고 여기서 필요한 것은 시스템 언어를 따르는 것이 아니라 **사용자가 직접 고르는 것**이다.
///
/// 짝을 한 줄에 붙여 두면 한쪽만 고치고 다른 쪽을 빠뜨리는 일이 눈에 띈다.
/// 언어가 셋이 된 뒤에도 같은 이유로 나란히 둔다 — 인자를 하나 빠뜨리면 컴파일이 막는다.
enum S {

    static var lang: Language { Settings.shared.resolvedLanguage }

    /// 세 말 중 하나를 고른다.
    ///
    /// `resolvedLanguage` 는 `.system` 을 돌려주지 않으므로 남는 갈래는 영어뿐이다.
    static func p(_ korean: String, _ english: String, _ japanese: String) -> String {
        switch lang {
        case .korean:   return korean
        case .japanese: return japanese
        default:        return english
        }
    }

    // MARK: 상태

    static var stateWaiting: String { p("승인 대기", "Approval", "承認待ち") }
    static var stateIdle: String    { p("입력 대기", "Idle", "入力待ち") }
    static var stateBusy: String    { p("작업 중", "Working", "実行中") }
    static var stateShell: String   { p("셸 실행 중", "Shell", "シェル実行") }
    static func stateUnknown(_ raw: String) -> String {
        p("알 수 없음(\(raw))", "Unknown(\(raw))", "不明(\(raw))")
    }

    // MARK: 메뉴

    static var noSessions: String {
        p("살아있는 세션이 없습니다", "No live sessions", "動いているセッションはありません")
    }
    static var settingsItem: String { p("설정…", "Settings…", "設定…") }

    // MARK: 새 판

    /// 메뉴에 내거는 줄. **판 번호를 적는다** — 「업데이트 있음」만으론 무엇이 오는지 모른다.
    static func updateReady(_ version: String) -> String {
        p("새 버전 \(version) — 지금 설치", "Version \(version) — install now", "新しい版 \(version) — 今すぐ入れる")
    }
    static var checkUpdates: String { p("새 버전 알림", "Tell me about new versions", "新しい版を知らせる") }
    static var checkUpdatesNote: String {
        p("하루에 한 번 릴리즈를 확인합니다. 받는 일은 누르셔야 시작합니다.",
          "Checks releases once a day. Nothing downloads until you click.",
          "1日1回リリースを確認します。押すまで何もダウンロードしません。")
    }
    static var checkNow: String { p("지금 확인", "Check now", "今すぐ確認") }
    static var updateChecking: String { p("확인하는 중…", "Checking…", "確認中…") }
    static var updateUpToDate: String { p("최신입니다", "Up to date", "最新です") }
    static var updateCheckFailed: String {
        p("확인하지 못했습니다", "Could not check", "確認できませんでした")
    }
    static var updateDownloading: String { p("받는 중…", "Downloading…", "ダウンロード中…") }
    static var updateFailedTitle: String {
        p("새 판을 넣지 못했습니다", "Could not install the update", "新しい版を入れられませんでした")
    }
    static var updateNotWritable: String {
        p("앱이 놓인 자리를 이 앱이 바꿀 수 없습니다. 손으로 받아 바꿔 주세요.",
          "This app cannot write where it is installed. Please replace it by hand.",
          "インストール先に書き込めません。手動で入れ替えてください。")
    }
    static var updateDownloadFailed: String {
        p("받아 오지 못했습니다.", "The download did not finish.", "ダウンロードできませんでした。")
    }
    static var updateBadArchive: String {
        p("받은 것이 이 앱의 그 판이 아니어서 넣지 않았습니다.",
          "What arrived was not this app at that version, so nothing was replaced.",
          "届いたものがこのアプリのその版ではなかったため、入れ替えていません。")
    }
    static var updateSwapFailed: String {
        p("바꿔 끼우지 못했습니다. 지금 판은 그대로입니다.",
          "The swap did not start. The current version is untouched.",
          "入れ替えを始められませんでした。今の版はそのままです。")
    }
    static var updateOpenPage: String { p("릴리즈 페이지 열기", "Open releases", "リリースページを開く") }
    static var updateLater: String { p("나중에", "Later", "あとで") }
    static var quitItem: String     { p("종료", "Quit", "終了") }
    static var estimated: String    { p("  (추정)", "  (est.)", "  (推定)") }

    // MARK: 이어진 세션

    static func continuedFrom(_ pid: Int) -> String {
        p("이어진 세션입니다 — 터미널 창은 pid \(pid) 가 쥐고 있습니다",
          "A continued session — its terminal window belongs to pid \(pid)",
          "引き継いだセッションです — ターミナルの窓は pid \(pid) が持っています")
    }
    static var backgroundNoWindow: String {
        p("백그라운드 세션이라 갈 터미널 창이 없습니다",
          "A background session has no terminal window to go to",
          "バックグラウンドのセッションなので、行くべきターミナルの窓がありません")
    }

    // MARK: 이동 실패

    /// 목록의 한 줄 자리에 들어가는 말이라 짧게 둔다. 자세한 것은 `~Detail` 로 뺀다.
    static var jumpNoWindow: String {
        p("터미널 창을 못 찾았습니다", "Could not find its terminal window",
          "ターミナルの窓が見つかりませんでした")
    }
    static var jumpNoWindowDetail: String {
        p("그 탭이 닫혔거나, Terminal.app 이 아닌 터미널일 수 있습니다. 이 앱은 아직 Terminal.app 만 압니다.",
          "The tab may be closed, or it may be a terminal other than Terminal.app — the only one this app knows so far.",
          "そのタブが閉じられたか、Terminal.app 以外のターミナルかもしれません。このアプリはまだ Terminal.app しか知りません。")
    }
    static var jumpNoTerminal: String {
        p("터미널 없이 도는 세션입니다", "This session runs without a terminal",
          "ターミナル無しで動くセッションです")
    }
    static var jumpNoTerminalDetail: String {
        p("터미널에 매여 있지 않아 옮겨 갈 창이 없습니다.",
          "It is not attached to a terminal, so there is no window to move to.",
          "ターミナルに繋がっていないので、移る窓がありません。")
    }
    static var jumpFailedTitle: String {
        p("이동하지 못했습니다", "Could not move there", "移動できませんでした")
    }
    static func jumpFailedLine(_ why: String) -> String {
        p("이동 실패 — \(why.fitted(to: 28))", "Jump failed — \(why.fitted(to: 28))",
          "移動失敗 — \(why.fitted(to: 28))")
    }

    // MARK: 상시 창

    static var panelShowItem: String { p("상시 창 열기", "Show panel", "パネルを表示") }
    static var panelHideItem: String { p("상시 창 닫기", "Hide panel", "パネルを隠す") }
    static var panelGroup: String    { p("상시 창", "Panel", "パネル") }
    static var panelShowToggle: String { p("띄우기", "Show", "表示") }
    static var panelAlwaysOnTop: String { p("항상 위로", "Always on top", "常に最前面") }
    static var panelWaitingOnly: String { p("기다리는 것만", "Waiting only", "待ちだけ") }
    /// 「기다리는 것만」을 켜 두었는데 기다리는 것이 없을 때.
    ///
    /// 「없습니다」로 적지 않는다 — 세션은 살아 있고 다들 일하는 중인데 «없다»고 하면
    /// 앱이 멎은 것처럼 읽힌다.
    static var panelAllRunning: String { p("다 돌고 있습니다", "All running", "すべて実行中です") }
    static var tabPanel: String      { p("상시 창", "Panel", "パネル") }
    /// 이 탭의 경계를 맨 위에서 한 번 못 박는다.
    static var panelTabNote: String {
        p("여기 있는 손잡이는 상시 창에만 걸립니다. 메뉴는 달라지지 않습니다.",
          "Everything here affects only the panel. The menu is unchanged.",
          "ここの手当てはパネルにだけ効きます。メニューは変わりません。")
    }
    static var panelWaitingOnlyNote: String {
        p("손이 필요한 줄만 남깁니다. 메뉴는 이 값과 무관하게 늘 전부 보여줍니다.",
          "Keeps only the rows that need you. The menu always shows all of them.",
          "手が要る行だけを残します。メニューはこの値と関係なく常に全部見せます。")
    }
    static var backdropStyle: String { p("바탕 결", "Backdrop", "背景板") }
    static var backdropAlpha: String { p("바탕 진하기", "Opacity", "濃さ") }
    static var backdropBlur: String  { p("흐림", "Blur", "ぼかし") }
    static var backdropSolid: String { p("단색", "Solid", "単色") }
    static var panelTextSize: String { p("글자 크기", "Text size", "文字の大きさ") }
    static var panelDensityLabel: String { p("줄 밀도", "Row density", "行の詰まり") }
    /// 「줄 밀도」와 헷갈리지 않게 «창» 을 앞에 붙인다. 하나는 줄 사이, 하나는 창 가장자리다.
    static var panelPaddingLabel: String { p("창 여백", "Window padding", "窓の余白") }
    static var panelSkinLabel: String { p("줄 스킨", "Row skin", "行のスキン") }
    static var skinSimple: String    { p("심플", "Simple", "シンプル") }
    static var skinBold: String      { p("또렷", "Bold", "くっきり") }
    static var skinQuiet: String     { p("고요", "Quiet", "しずか") }
    static var skinNote: String {
        p("「고요」는 기다리는 줄만 살리고 도는 줄은 배경으로 내립니다. 곁눈으로 볼 때 좋고, 목록을 두루 읽을 때는 답답할 수 있습니다.",
          "“Quiet” keeps the waiting rows and sinks the rest. Good at a glance, cramped when you want to read the whole list.",
          "「しずか」は待っている行だけを活かし、動いている行は背景へ沈めます。ちらと見るのに向き、リスト全体を読むときは窮屈かもしれません。")
    }
    static var paddingNone: String   { p("없음", "None", "なし") }
    /// 진하기를 0 가까이 내렸을 때의 대가를 그 자리에 적는다. 배경화면 위에서는 멀쩡한데
    /// 다른 창 위에 겹치면 뒤 글자와 섞여 읽기 어려워지는 것을 실제로 보았다.
    static var backdropNote: String {
        p("바탕이 거의 없습니다. 배경화면 위에서는 깔끔하지만 다른 창 위에 겹치면 읽기 어려워집니다.",
          "Almost no backdrop. Clean over a wallpaper, hard to read over another window.",
          "背景板がほとんどありません。壁紙の上では綺麗ですが、別の窓に重なると読みにくくなります。")
    }
    static var panelLivePreview: String {
        p("창이 떠 있습니다 — 여기서 만지면 그 자리에서 바뀝니다.",
          "The panel is open — changes here show up on it as you make them.",
          "パネルが開いています — ここで触るとその場で変わります。")
    }
    static var panelOpenToSee: String {
        p("「띄우기」를 켜면 바뀌는 것을 바로 보면서 맞추실 수 있습니다.",
          "Turn on “Show” to see the changes as you make them.",
          "「表示」を入れると、変わるところを見ながら合わせられます。")
    }
    static var textSmall: String     { p("작게", "Small", "小さく") }
    static var textNormal: String    { p("보통", "Normal", "標準") }
    static var textLarge: String     { p("크게", "Large", "大きく") }
    static var densityTight: String  { p("촘촘", "Tight", "詰めて") }
    static var densityNormal: String { p("보통", "Normal", "標準") }
    static var densityLoose: String  { p("넉넉", "Loose", "ゆったり") }

    static var panelHandlesHint: String {
        p("우클릭 — 항상 위로 · 기다리는 것만 · 닫기",
          "Right-click — always on top · waiting only · close",
          "右クリック — 常に最前面 · 待ちだけ · 閉じる")
    }

    static func menuTooltip(waiting: Int, total: Int) -> String {
        waiting > 0
            ? p("\(waiting)개가 기다리는 중 · 전체 \(total)개", "\(waiting) waiting · \(total) total",
                "\(waiting)個が待機中 · 全部で \(total)個")
            : p("전체 \(total)개 · 기다리는 것 없음", "\(total) sessions · nothing waiting",
                "全部で \(total)個 · 待っているものなし")
    }

    static var jumpHint: String {
        p("눌러서 이 세션의 터미널로 이동", "Click to focus this session's terminal",
          "クリックでこのセッションのターミナルへ")
    }
    static var jumpHintApp: String {
        p("눌러서 이 세션을 띄운 앱으로 이동", "Click to focus the app running this session",
          "クリックでこのセッションを動かしているアプリへ")
    }
    static var pinHint: String {
        p("우클릭으로 고정 — 기다릴 때 맨 위로 올라옵니다",
          "Right-click to pin — it rises to the top while waiting",
          "右クリックでピン留め — 待っている間は一番上に来ます")
    }
    static var unpinHint: String {
        p("우클릭으로 고정 해제", "Right-click to unpin", "右クリックでピンを外す")
    }

    // MARK: 멈추기

    static var pinItem: String       { p("맨 위에 고정", "Pin to top", "一番上にピン留め") }
    static var unpinItem: String     { p("고정 해제", "Unpin", "ピンを外す") }
    static var stopItem: String      { p("이 세션 멈추기…", "Stop this session…", "このセッションを止める…") }
    /// 두 번째 단계. 「…」이 빠지고 말이 굳는 것으로 **이번엔 진짜 실행된다**를 알린다.
    static var stopConfirmItem: String { p("정말 멈추기", "Stop it", "本当に止める") }
    /// 누른 그 줄이 답하는 말.
    ///
    /// 「멈췄습니다」가 아니라 **「멈추는 중」**이다. `claude stop` 은 상대가 내려가기를
    /// 기다리므로 누른 순간에는 아직 안 멈췄고, 안 멈춘 것을 멈췄다고 적으면 그건 거짓말이다.
    /// 줄이 사라지는 것이 「멈췄다」이고, 이 말은 그때까지의 사이를 메운다.
    static var stoppingLine: String  { p("멈추는 중…", "Stopping…", "止めています…") }
    static var stopKeepsChat: String {
        p("대화는 남습니다 — claude attach 로 다시 열 수 있습니다",
          "The conversation is kept — reopen it with claude attach",
          "会話は残ります — claude attach で開き直せます")
    }
    /// 멈출 수 있는 줄이라고 툴팁에 적는다. 우클릭해 보기 전에는 알 길이 없다.
    static var stopHint: String {
        p("우클릭 메뉴에서 이 백그라운드 세션을 멈출 수 있습니다",
          "Right-click for a menu to stop this background session",
          "右クリックのメニューで、このバックグラウンドのセッションを止められます")
    }

    /// 상시 창에서는 우클릭이 **메뉴를 연다.** 메뉴에서는 곧바로 고정이다.
    /// 두 화면의 안내가 같으면 한쪽은 반드시 거짓말이 된다.
    static var pinHintPanel: String {
        p("우클릭 메뉴에서 고정 — 기다릴 때 맨 위로 올라옵니다",
          "Right-click for a menu to pin — it rises to the top while waiting",
          "右クリックのメニューでピン留め — 待っている間は一番上に来ます")
    }
    static var unpinHintPanel: String {
        p("우클릭 메뉴에서 고정 해제", "Right-click for a menu to unpin",
          "右クリックのメニューでピンを外す")
    }
    static var stopNoBinary: String {
        p("claude 명령을 못 찾았습니다", "Could not find the claude command",
          "claude コマンドが見つかりませんでした")
    }
    static func stopFailedLine(_ why: String) -> String {
        p("멈추지 못함 — \(why.fitted(to: 28))", "Stop failed — \(why.fitted(to: 28))",
          "停止失敗 — \(why.fitted(to: 28))")
    }
    static func errExit(_ code: Int) -> String {
        p("종료 코드 \(code)", "exit code \(code)", "終了コード \(code)")
    }
    static func descendants(_ count: Int) -> String {
        p("자손 프로세스 \(count)개 포함", "includes \(count) descendant processes",
          "子孫プロセス \(count)個を含む")
    }

    // MARK: 요약

    /// 두 줄로 나눈다.
    ///
    /// 한 줄로 두면 49칸이 되어 세션 줄(38칸)보다 넓어지고, 메뉴는 가장 긴 줄에 맞춰지므로
    /// **요약 하나 때문에 메뉴 전체가 넓어진다.** 이름을 떼어 줄이는 방법도 있지만,
    /// 숫자에서 이름을 빼면 만든 사람에게만 뜻이 통하게 된다.
    static func systemSummary(used: Double, total: Double, swap: Double, agent: Double) -> String {
        String(format: p("메모리 %.1f/%.1fGB · 스왑 %.1fGB\n에이전트 %.1fGB",
                         "Memory %.1f/%.1fGB · Swap %.1fGB\nAgents %.1fGB",
                         "メモリ %.1f/%.1fGB · スワップ %.1fGB\nエージェント %.1fGB"),
               used, total, swap, agent)
    }

    // MARK: 설정창

    static var windowTitle: String   { p("AgentMonitor 설정", "AgentMonitor Settings", "AgentMonitor 設定") }
    static var tabDisplay: String    { p("표시", "Display", "表示") }
    static var tabMemory: String     { p("메모리", "Memory", "メモリ") }
    static var tabStats: String      { p("통계", "Statistics", "統計") }

    static var language: String      { p("언어", "Language", "言語") }
    static var appearance: String    { p("밝기", "Appearance", "外観") }
    static var rowLayout: String     { p("줄 배치", "Row layout", "行の配置") }
    static var layoutSingle: String  { p("한 줄", "One line", "1行") }
    static var layoutDouble: String  { p("두 줄", "Two lines", "2行") }
    static var showStateLabel: String { p("상태를 글자로 보이기", "Show status as text", "状態を文字で見せる") }
    static var showTool: String      { p("도구 이름 보이기", "Show tool name", "ツール名を見せる") }
    // 어디에 나오는지까지 적는다. 줄에는 안 나오므로, 켜도 목록이 그대로면 고장으로 보인다.
    static var showReason: String {
        p("마우스를 올리면 왜 기다리는지 보이기", "Show why it is waiting on hover",
          "ポインタを載せたら待っている理由を見せる")
    }
    static var metrics: String       { p("지표", "Metrics", "指標") }
    // 줄에 실제로 찍히는 말(RAM·CPU)을 그대로 쓴다. 「숫자」·「전부」로 적으면
    // 켜 보기 전에는 무엇이 나올지 알 수 없다.
    static var metricBar: String     { p("RAM 막대", "RAM bar", "RAM バー") }
    static var metricValue: String   { "RAM GB" }
    static var metricCPU: String     { "CPU %" }
    static var tokenMetrics: String  { p("토큰", "Tokens", "トークン") }
    // 여기도 줄에 찍히는 말을 그대로 쓴다. 「컨텍스트」·「누적」으로 적으면 켜 보기
    // 전에는 줄의 어느 칸이 그것인지 알 수 없다.
    static var metricContext: String { p("CTX 컨텍스트", "CTX context", "CTX コンテキスト") }
    static var metricTokens: String  { p("TOK 누적", "TOK cumulative", "TOK 累計") }
    static var tokenNote: String {
        p("TOK 은 «새로 태운 것 / 전부» 입니다. 뒤쪽은 캐시 재사용분까지 셉니다.",
          "TOK reads «freshly burned / everything». The second number counts cache reads too.",
          "TOK は «新たに焼いた分 / 全部» です。後ろはキャッシュ再利用分まで数えます。")
    }
    static var showSummary: String {
        p("아래에 시스템 요약 보이기", "Show system summary below", "下にシステムの要約を見せる")
    }
    static var recordStats: String {
        p("쓰임새 기록하기 (agent-monitor --stats)", "Record usage (agent-monitor --stats)",
          "使い方を記録する (agent-monitor --stats)")
    }
    static var recordStatsNote: String {
        p("세션 수·대기 시간·메모리를 1분 단위로 남깁니다. 대화 내용은 남기지 않습니다.",
          "Keeps session counts, waiting times and memory per minute. No conversation content.",
          "セッション数・待ち時間・メモリを1分ごとに残します。会話の中身は残しません。")
    }
    static var refresh: String       { p("갱신 주기", "Refresh", "更新間隔") }
    static func seconds(_ n: Int) -> String { p("\(n)초", "\(n)s", "\(n)秒") }
    static var hoverOpen: String     { p("올리면 열기", "Open on hover", "載せたら開く") }
    static var hoverOpenToggle: String { p("켬", "On", "入") }
    static var hoverNote: String {
        p("메뉴바 숫자에 마우스를 올리면 목록이 열립니다. 「즉시」는 지나가기만 해도 열리므로, 메뉴바를 자주 지나다니시면 머무는 시간을 두시는 편이 낫습니다.",
          "Point at the menu bar count and the list opens. “Instant” opens as you pass by, so a dwell is kinder if you cross the menu bar often.",
          "メニューバーの数字にポインタを載せるとリストが開きます。「すぐ」は通り過ぎるだけでも開くので、メニューバーをよく横切るなら少し待つ方が楽です。")
    }
    static var hoverInstant: String  { p("즉시", "Instant", "すぐ") }
    static var hoverFast: String     { p("빠르게", "Fast", "速く") }
    static var hoverNormal: String   { p("보통", "Normal", "標準") }
    static var hoverSlow: String     { p("느긋", "Slow", "ゆっくり") }

    static var sourceStyle: String   { p("출처 표시", "Source label", "出所の表示") }
    static var styleShort: String    { p("앱만", "App only", "アプリのみ") }
    static var styleSymmetric: String { p("양쪽 다", "Both", "両方") }
    static var styleSymbol: String   { p("표식", "Mark", "印") }
    static var codexAppWindow: String { p("codex 앱 스레드", "codex app threads", "codex アプリのスレッド") }
    static var windowOff: String     { p("안 보임", "Hidden", "非表示") }
    static func minutes(_ n: Int) -> String { p("\(n)분", "\(n)m", "\(n)分") }
    static func hours(_ n: Int) -> String   { p("\(n)시간", "\(n)h", "\(n)時間") }
    static var preview: String       { p("미리보기", "Preview", "プレビュー") }
    static var previewNote: String {
        p("실제 세션을 메뉴와 같은 코드로 그린 것입니다. 폭이 곧 메뉴 폭입니다 — 창을 넓히면 끝까지 보입니다.",
          "Rendered from real sessions with the same code the menu uses. This width is the menu width — widen the window to see it all.",
          "実際のセッションをメニューと同じコードで描いたものです。この幅がそのままメニューの幅です — 窓を広げれば最後まで見えます。")
    }
    static var resetButton: String   { p("처음 모습으로", "Reset to defaults", "初期状態に戻す") }

    // MARK: 메모리 화면

    static var thisMac: String       { p("이 맥", "This Mac", "この Mac") }
    static var used: String          { p("사용 중", "Used", "使用中") }
    static var swap: String          { p("스왑", "Swap", "スワップ") }
    static var compressed: String    { p("압축됨", "Compressed", "圧縮済み") }
    static var agentSessions: String { p("에이전트 세션", "Agent sessions", "エージェントのセッション") }
    static func processCount(_ n: Int) -> String { p("프로세스 \(n)개", "\(n) processes", "プロセス \(n)個") }
    static var suspectedGroup: String {
        p("세션이 띄운 것으로 보이는 것", "Likely spawned by a session", "セッションが立てたと思われるもの")
    }
    static var suspectedNote: String {
        p("작업 폴더로 미루어 본 **추정**입니다. 세션 합계에는 넣지 않았습니다.",
          "A **guess** from the working directory. Not counted in the session total.",
          "作業フォルダから見た**推定**です。セッションの合計には入れていません。")
    }
    static var outsideSessions: String { p("세션 밖", "Outside sessions", "セッションの外") }
    static func countSuffix(_ n: Int) -> String { p("   (\(n)개)", "   (\(n))", "   (\(n)個)") }
    static var memoryFootnote: String {
        p("30MB 미만은 생략했습니다. 세션 트리에 속한 것은 «에이전트 세션» 에만 셉니다.",
          "Under 30MB omitted. Anything inside a session tree is counted only under “Agent sessions”.",
          "30MB 未満は省きました。セッションの木に属するものは «エージェントのセッション» にだけ数えます。")
    }
    static var measuring: String     { p("재는 중…", "Measuring…", "計測中…") }
    static var unknownProcess: String { p("(알 수 없음)", "(unknown)", "(不明)") }
    static func multipleSessions(_ n: Int) -> String {
        p("여러 세션 (\(n))", "multiple sessions (\(n))", "複数のセッション (\(n))")
    }

    // MARK: 터미널 이동

    static var permissionTitle: String {
        p("터미널을 제어할 권한이 없습니다", "No permission to control Terminal",
          "ターミナルを操作する権限がありません")
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
          """,
          """
          セッションの窓へ移動するには、Terminal の操作を許可する必要があります。

          システム設定 → プライバシーとセキュリティ → オートメーション で
          AgentMonitor の下にある Terminal を入れてください。
          """)
    }
    static var okButton: String      { p("확인", "OK", "OK") }
    static var errScript: String     { p("스크립트를 만들지 못함", "could not build the script", "スクリプトを作れませんでした") }
    static func errNoHandler(_ scheme: String) -> String {
        p("\(scheme):// 를 열 수 있는 앱이 없음", "no app can open \(scheme)://",
          "\(scheme):// を開けるアプリがありません")
    }
    static func errUnknown(_ code: Int) -> String {
        p("알 수 없는 오류(\(code))", "unknown error (\(code))", "不明なエラー(\(code))")
    }
    static var logNoTTY: String {
        p("터미널이 없는 세션입니다", "no terminal for this session", "ターミナルの無いセッションです")
    }
    static var logNoWindow: String {
        p("tty 는 있으나 Terminal 창을 못 찾았습니다", "has a tty but no Terminal window matched",
          "tty はあるが Terminal の窓が見つかりませんでした")
    }
    static func logFailed(_ message: String) -> String {
        p("이동 실패 — \(message)", "jump failed — \(message)", "移動失敗 — \(message)")
    }

    // MARK: 명령줄

    static func roots(_ n: Int) -> String {
        p("계정 루트 \(n)개", "\(n) account roots", "アカウントルート \(n)個")
    }
    static var noSessionsPeriod: String {
        p("살아있는 세션이 없습니다.", "No live sessions.", "動いているセッションはありません。")
    }
    static func listHeader(waiting: Int, total: Int) -> String {
        p("\(waiting)/\(total)  — 기다리는 중 \(waiting) · 전체 \(total)",
          "\(waiting)/\(total)  — \(waiting) waiting · \(total) total",
          "\(waiting)/\(total)  — 待機中 \(waiting) · 全部で \(total)")
    }
    static func agentTotal(_ size: String, sessions: Int, processes: Int) -> String {
        p("에이전트 세션  \(size)  (세션 \(sessions)개 · 프로세스 \(processes)개)",
          "Agent sessions  \(size)  (\(sessions) sessions · \(processes) processes)",
          "エージェントのセッション  \(size)  (セッション \(sessions)個 · プロセス \(processes)個)")
    }
    static var suspectedCLIHeader: String {
        p("세션이 띄운 것으로 보이는 것  — 작업 폴더로 미루어 본 추정이며 위 합계에 넣지 않음",
          "Likely spawned by a session  — a guess from the working directory, not counted above",
          "セッションが立てたと思われるもの  — 作業フォルダから見た推定で、上の合計には入れていない")
    }
    static var floorNote: String {
        p("30MB 미만은 생략했습니다.", "Under 30MB omitted.", "30MB 未満は省きました。")
    }

    // MARK: 통계

    static var statsNoData: String {
        p("""
          아직 쌓인 기록이 없습니다.
          메뉴바 앱이 돌고 있어야 쌓이며, 설정의 «쓰임새 기록하기» 가 켜져 있어야 합니다.
          """,
          """
          Nothing recorded yet.
          The menu bar app has to be running, with "Record usage" on in Settings.
          """,
          """
          まだ記録がありません。
          メニューバーのアプリが動いていて、設定の «使い方を記録する» が入っている必要があります。
          """)
    }
    /// 기록은 되고 있으나 아직 셀 것이 없을 때. 「없음」과 가른다.
    static var statsAwayOnly: String {
        p("""
          기록은 쌓이고 있으나, 아직 주인님이 앞에 계셨던 시간이 잡히지 않았습니다.
          자리를 비운 동안의 대기는 병목이 아니라서 세지 않습니다 — 조금 쓰신 뒤 다시 보세요.
          """,
          """
          Recording, but no time at the keyboard has been captured yet.
          Waiting that piles up while you are away is not counted — check again after a while.
          """,
          """
          記録は溜まっていますが、まだ席にいた時間が捉えられていません。
          席を外している間の待ちはボトルネックではないので数えません — しばらく使ってからまた見てください。
          """)
    }
    static func statsHeader(days: Int, dataDays: Int, hours: Double) -> String {
        switch lang {
        case .korean:
            return String(format: "최근 %d일 — 기록 %d일치 · 앞에 계셨던 시간 %.1f시간",
                          days, dataDays, hours)
        case .japanese:
            return String(format: "直近 %d日 — %d日分の記録 · 席にいた時間 %.1f時間",
                          days, dataDays, hours)
        default:
            return String(format: "Last %d days — %d %@ recorded · %.1f hours at the keyboard",
                          days, dataDays, dataDays == 1 ? "day" : "days", hours)
        }
    }
    static var statsSessions: String { p("세션 수", "Sessions", "セッション数") }
    static var statsRunning: String  { p("실제로 돌던 수", "Actually running", "実際の稼働数") }
    static var statsQueue: String    { p("대기 줄 길이", "Queue length", "待ち行列の長さ") }
    static var statsWaits: String    { p("대기 시간", "Waiting time", "待ち時間") }
    static var statsMemory: String   { p("에이전트 램", "Agent RAM", "エージェントRAM") }

    static func statsMeanMax(_ mean: Double, _ max: Int) -> String {
        String(format: p("평균 %.1f · 최대 %d", "%.1f avg · %d peak", "平均 %.1f · 最大 %d"), mean, max)
    }
    static func statsMean(_ mean: Double) -> String {
        String(format: p("평균 %.1f", "%.1f avg", "平均 %.1f"), mean)
    }
    /// 줄 길이 분포. «없음» 이 손이 빈 시간이고, «둘 이상» 이 밀리고 있던 시간이다.
    static func statsQueueSplit(none: Double, one: Double, many: Double) -> String {
        let n = Int((none * 100).rounded()), o = Int((one * 100).rounded()), m = Int((many * 100).rounded())
        return p("없음 \(n)% · 하나 \(o)% · 둘 이상 \(m)%",
                 "none \(n)% · one \(o)% · two+ \(m)%",
                 "なし \(n)% · 一つ \(o)% · 二つ以上 \(m)%")
    }
    static func statsWaitSplit(median: Double, longest: Double, total: Double, count: Int) -> String {
        p("중앙값 \(span(median)) · 최장 \(span(longest)) · 합계 \(span(total))  (\(count)번)",
          "median \(span(median)) · longest \(span(longest)) · total \(span(total))  (\(count)×)",
          "中央値 \(span(median)) · 最長 \(span(longest)) · 合計 \(span(total))  (\(count)回)")
    }
    static func statsMemorySplit(mean: String, peak: String, swap: String) -> String {
        p("평균 \(mean) · 최대 \(peak) · 스왑 평균 \(swap)",
          "\(mean) avg · \(peak) peak · swap \(swap) avg",
          "平均 \(mean) · 最大 \(peak) · スワップ平均 \(swap)")
    }
    // MARK: 기록 상태

    static var statsLiveness: String { p("기록 상태", "Recording", "記録の状態") }
    static var statsRecent: String   { p("최근 7일", "Last 7 days", "直近7日") }
    static func statsToday(_ minutes: Int) -> String {
        p("오늘 \(minutes)분 쌓임", "\(minutes) min today", "今日 \(minutes)分")
    }
    /// 마지막으로 적힌 때. 「방금」이 보이면 장치가 살아 있다는 뜻이다.
    static func statsLastRecord(_ secondsAgo: Double?) -> String {
        guard let secondsAgo else { return p("아직 없음", "nothing yet", "まだ無し") }
        if secondsAgo < 120 { return p("마지막 기록 방금", "last record just now", "最後の記録はたった今") }
        return p("마지막 기록 \(Int(secondsAgo / 60))분 전",
                 "last record \(Int(secondsAgo / 60))m ago",
                 "最後の記録は \(Int(secondsAgo / 60))分前")
    }
    static var statsRecordingOff: String {
        p("기록이 꺼져 있습니다 — «표시» 탭에서 켜실 수 있습니다",
          "Recording is off — turn it on in the Display tab",
          "記録が切れています — «表示» タブで入れられます")
    }
    static var statsOpenFolder: String { p("기록 폴더 열기", "Open the folder", "記録フォルダを開く") }
    static var statsRetention: String {
        p("하루 한 파일로 30일간 둡니다. 개수·시간·메모리만 남고 대화 내용은 남지 않습니다.",
          "One file a day, kept 30 days. Counts, durations and memory only — no conversation.",
          "一日一ファイルで30日間置きます。個数・時間・メモリだけが残り、会話の中身は残りません。")
    }

    // MARK: 시간대·요일

    static var statsByHour: String    { p("시간대별", "By hour", "時間帯別") }
    static var statsByWeekday: String { p("요일별", "By weekday", "曜日別") }
    static var statsColHour: String    { p("시간", "Hour", "時刻") }
    static var statsColWeekday: String { p("요일", "Day", "曜日") }
    // 표 머리글은 칸 폭 안에서 접히지 않아야 한다. 접히면 `sessi/ons` 처럼 쪼개져
    // 무슨 칸인지 못 읽는다. 그래서 뜻이 남는 선에서 가장 짧은 말을 쓴다.
    // 일본어도 같은 자를 받는다 — 「セッション」은 10칸이라 9칸 자리에 못 들어간다.
    static var statsColPresent: String { p("계신 시간", "at desk", "在席時間") }
    static var statsColSessions: String { p("세션", "sess", "総数") }
    static var statsColRunning: String  { p("돌던 수", "run", "稼働数") }
    static var statsColQueueMany: String { p("줄 2+", "queue 2+", "待ち2+") }

    static func hourLabel(_ hour: Int) -> String {
        switch lang {
        case .korean:   return String(format: "%02d시", hour)
        case .japanese: return String(format: "%02d時", hour)
        default:        return String(format: "%02d:00", hour)
        }
    }
    /// `Calendar` 의 요일 번호(1=일)를 이름으로.
    static func weekdayLabel(_ weekday: Int) -> String {
        let korean   = ["일", "월", "화", "수", "목", "금", "토"]
        let english  = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let japanese = ["日", "月", "火", "水", "木", "金", "土"]
        let index = max(0, min(6, weekday - 1))
        switch lang {
        case .korean:   return korean[index]
        case .japanese: return japanese[index]
        default:        return english[index]
        }
    }
    /// 뺀 칸이 있으면 몇 칸을 왜 뺐는지 밝힌다. 조용히 빼면 없는 시간대로 읽힌다.
    static func statsThinNote(_ count: Int, minutes: Int) -> String {
        p("  (\(minutes)분에 못 미치는 칸 \(count)개는 뺐습니다 — 비율이 튑니다)",
          "  (\(count) buckets under \(minutes) minutes omitted — the ratios swing)",
          "  (\(minutes)分に満たない枠 \(count)個は外しました — 比率が跳ねます)")
    }

    static var statsFootnote: String {
        p("""
          모두 «앞에 계셨던 시간» 기준입니다 — 자리를 비운 동안 쌓인 대기는 빼고 셉니다.
          여기서는 숫자만 냅니다. 「몇 개가 맞다」는 문턱은 쌓인 것을 보고 정합니다.
          """,
          """
          Everything is measured over time at the keyboard — waiting that piled up while
          you were away is not counted. These are numbers only; what counts as too many
          is a threshold to set once there is enough recorded to set it from.
          """,
          """
          すべて «席にいた時間» が基準です — 席を外している間に溜まった待ちは数えません。
          ここでは数字だけを出します。「いくつが適切か」の閾値は、溜まったものを見て決めます。
          """)
    }

    /// 걸린 시간을 사람이 읽는 꼴로. 초 단위까지 보이는 자리가 있어 `elapsed` 와 따로 둔다.
    static func span(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return p("\(total)초", "\(total)s", "\(total)秒") }
        if total < 3600 {
            let m = total / 60, s = total % 60
            if s == 0 { return p("\(m)분", "\(m)m", "\(m)分") }
            return p("\(m)분 \(s)초", "\(m)m \(s)s", "\(m)分 \(s)秒")
        }
        let h = total / 3600, m = (total % 3600) / 60
        if m == 0 { return p("\(h)시간", "\(h)h", "\(h)時間") }
        return p("\(h)시간 \(m)분", "\(h)h \(m)m", "\(h)時間 \(m)分")
    }

    static var helpText: String {
        p("""
          agent-monitor — 로컬 에이전트 세션 중 무엇이 나를 기다리는지 보여준다

          사용법
            agent-monitor            메뉴바에 띄운다
            agent-monitor --list     사람이 읽는 표로 한 번 출력하고 끝낸다
            agent-monitor --json     JSON 으로 출력하고 끝낸다 (검증용)
            agent-monitor --memory   이 맥의 메모리를 누가 쓰는지 보여준다
            agent-monitor --roots    훑는 계정 루트를 보여준다
            agent-monitor --stats    쌓아 둔 쓰임새 기록을 요약한다 (기본 7일)
            agent-monitor --demo     문서용 그림을 찍기 위해 지어낸 세션만 그린다

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
            agent-monitor --stats    summarise the recorded usage (7 days by default)
            agent-monitor --demo     draw made-up sessions only, for documentation shots

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
          """,
          """
          agent-monitor — ローカルのエージェントのセッションのうち、どれが自分を待っているかを見せる

          使い方
            agent-monitor            メニューバーに出す
            agent-monitor --list     人が読める表で一度だけ出力して終わる
            agent-monitor --json     JSON で出力して終わる (検証用)
            agent-monitor --memory   この Mac のメモリを何が使っているかを見せる
            agent-monitor --roots    走査するアカウントルートを見せる
            agent-monitor --stats    溜めた使い方の記録を要約する (既定は7日)
            agent-monitor --demo     文書用の画像を撮るため、作り物のセッションだけを描く

          メニューバーには «待機中/全体» の数字だけを出す。セッションがいくつあっても切り捨てない。

          行を右クリックするとそのセッションをピン留めする。留めたセッションは手を待つ間は
          一番上に来て、メニューでは背景がうっすら付く (`--list` は色を使わないので、
          そこでは並び順にだけ現れる)。実行中は位置を動かさない。
          ピンはそのセッションと共に生きる。セッションを開き直したら、また留める。

          手が要る行にポインタを載せると、なぜ待っているかが出る — 承認待ちは待っている
          呼び出しを、入力待ちは最後に言ってきたことを。行そのものには書かない。常に幅を
          食ったうえに切られる側だったので移した。記録に見つからなければ推測せず何も出さない。
          «表示» 設定で切れるし、`--json` の `reason` にも出る。

          行の先頭の出所で、どこから来たセッションかを見分ける —
          claude(ターミナル) · claude-app · codex(ターミナル) · codex-app。

          状態をそのまま読むのは、ターミナルの Claude Code(<アカウントルート>/sessions/<pid>.json) と
          codex アプリ(~/.codex の state_5・thread_history_1 DB を読み取り専用で)。
          Claude アプリとターミナルの codex は状態を書かないので、記録の末尾から推定し «推定» と書く。

          codex アプリのスレッドは «まだ開いているか» を測れないので、時間で切る。
          実行中のものは常に見え、終わったものは設定した窓の内側だけが見える (既定は30分)。
          アプリのセッションはプロセスが無いのでメモリ・CPU が空で、押すとそのアプリへ行く。
          """)
    }
}

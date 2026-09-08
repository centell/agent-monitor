import AppKit
import Foundation
import SQLite3

/// ChatGPT 앱(codex) 안에서 도는 스레드를 긁어 온다.
///
/// 여기는 앞의 두 곳과 사정이 또 다르다.
///
/// **좋은 쪽** — 상태가 **적혀 있다.** codex 는 턴마다 `~/.codex/thread_history_1.sqlite` 의
/// `thread_turns` 에 `inProgress` · `completed` · `interrupted` · `failed` 을 적고,
/// 스레드 자체는 `~/.codex/state_5.sqlite` 의 `threads` 에 제목·작업 폴더·출처를 적는다.
/// 그래서 이 출처만은 추정하지 않는다 (`isEstimated` 를 세우지 않는다).
/// 그리고 앱이 `codex://threads/<id>` 딥링크를 받으므로 눌러서 갈 수도 있다.
///
/// **나쁜 쪽** — 스레드마다 프로세스가 없다. ChatGPT 앱 하나가 전부 처리하므로
/// 메모리·CPU 를 잴 수 없고, **«아직 열려 있는가» 를 알 길이 없다.**
///
/// 그 «모름» 을 정직하게 다루는 방법이 시간이다. 도는 중(`inProgress`)인 것은 의심할
/// 여지가 없으니 언제나 보이고, 끝난 것은 **최근 창 안에 있을 때만** 보인다.
/// 창 밖의 것을 «입력 대기» 로 쌓으면 며칠 전에 끝난 스레드 수십 개가 메뉴바 숫자를
/// 부풀린다 — 없는 일감을 만드는 셈이고, 그건 놓치는 것보다 나쁘다.
/// 어디서 자를지는 사람마다 다르므로 설정으로 내놓았다 (`Settings.codexAppWindow`).
struct CodexAppSource: SessionSource {
    let sourceName = "codex app"

    private let home = URL(fileURLWithPath: NSHomeDirectory())
    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// codex 홈. `CODEX_HOME` 이 있으면 그것을 따른다.
    var root: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return home.appendingPathComponent(".codex")
    }

    private var stateURL: URL { root.appendingPathComponent("state_5.sqlite") }
    private var historyURL: URL { root.appendingPathComponent("thread_history_1.sqlite") }

    // MARK: 훑기

    func scan() -> [Session] {
        // 0 분은 «보지 않겠다» 는 뜻이다. 그러면 DB 도 열지 않는다.
        let window = settings.codexAppWindow
        guard window > 0 else { return [] }

        // 앱이 꺼져 있으면 그 안의 어떤 스레드도 «지금 나를 기다리는» 것이 아니다.
        // 스레드마다 프로세스가 없어 살아있음을 잴 수 없다고 했지만, 앱 자체가 도는지는
        // 잴 수 있다. 이것이 이 출처가 가진 유일하고 확실한 살아있음 신호다.
        guard Self.appIsRunning else { return [] }

        return threads(since: Date().addingTimeInterval(-window * 60)).map { thread in
            var session = Session(
                id: thread.id,
                // 스레드마다 프로세스가 없다. 0 은 «프로세스 없음» 을 뜻하며,
                // 지표를 재는 쪽도 터미널로 가는 쪽도 이 값으로는 아무것도 하지 않는다.
                pid: 0,
                name: thread.name,
                source: "codex-app",
                cwd: thread.cwd,
                state: thread.state,
                kind: "thread",
                startedAt: thread.startedAt,
                statusUpdatedAt: thread.updatedAt,
                accountRoot: root
            )
            session.lastActivity = thread.updatedAt
            session.deepLink = Self.deepLink(for: thread.id)
            // 상태를 codex 가 직접 적었다. 추정이 아니므로 «추정» 을 달지 않는다.
            session.isEstimated = false
            return session
        }
    }

    /// ChatGPT 앱이 지금 도는가.
    private static var appIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).isEmpty
    }

    /// ChatGPT 앱의 번들 식별자. `codex` 스킴을 등록한 그 앱이다.
    private static let appBundleID = "com.openai.codex"

    /// 앱이 등록한 `codex` 스킴으로 그 스레드를 연다.
    /// 주소 형태는 앱 번들에 박혀 있는 것을 그대로 따랐다 (`codex://threads/<id>`).
    private static func deepLink(for threadID: String) -> URL? {
        URL(string: "codex://threads/\(threadID)")
    }

    // MARK: 읽기

    private struct Thread {
        let id: String
        let name: String
        let cwd: String
        let state: SessionState
        let startedAt: Date?
        let updatedAt: Date?
    }

    /// 스레드와 그 **가장 최근 턴**을 한 번에 가져온다.
    ///
    /// 두 파일에 나뉘어 있어 붙여서 읽는다 — 스레드의 이름·폴더는 `state_5`,
    /// 턴의 상태는 `thread_history_1` 에 있다.
    ///
    /// 거르는 것 셋:
    ///   · `archived = 0` — 사용자가 치운 스레드는 올리지 않는다.
    ///   · `source = 'vscode'` — 앱 스레드만. `cli` 는 터미널 출처가 따로 다루고,
    ///     `exec` 는 사람이 앉아 있지 않으며, `{"subagent":…}` 는 남의 턴의 부품이지
    ///     세션이 아니다 (Claude 쪽에서 sidechain 을 세지 않는 것과 같은 이유).
    ///   · 창 밖의 것. 끝난 턴은 시작 시각으로, **도는 중인 턴은 스레드의 갱신 시각**으로 잰다.
    ///     턴이 정말 돌고 있으면 스레드가 계속 갱신되므로 몇 시간짜리 긴 턴도 살아남고,
    ///     중간에 죽어 `inProgress` 로 굳은 턴은 갱신이 멈추므로 걸러진다.
    ///     («N시간 넘으면 죽은 것으로 친다» 는 임의의 상한을 두지 않기 위해서다.
    ///      실제로 19일째 `inProgress` 인 스레드가 있었고, 그것의 갱신은 21분 만에 멈춰 있었다.)
    private func threads(since cutoff: Date) -> [Thread] {
        var db: OpaquePointer?
        // 읽기 전용으로 연다. 남의 앱이 쓰는 DB 를 우리가 건드리는 일은 없어야 한다.
        guard sqlite3_open_v2("file:\(stateURL.path)?mode=ro", &db,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        let attach = "ATTACH DATABASE 'file:\(historyURL.path)?mode=ro' AS h"
        guard sqlite3_exec(db, attach, nil, nil, nil) == SQLITE_OK else { return [] }

        let sql = """
        SELECT t.id,
               COALESCE(NULLIF(t.name, ''), NULLIF(t.title, ''), ''),
               COALESCE(t.cwd, ''),
               u.status, u.started_at, COALESCE(u.completed_at, u.started_at)
        FROM threads t
        JOIN (SELECT thread_id, status, started_at, completed_at,
                     ROW_NUMBER() OVER (PARTITION BY thread_id ORDER BY started_at DESC) rn
              FROM h.thread_turns) u
          ON u.thread_id = t.id AND u.rn = 1
        WHERE t.archived = 0
          AND t.source = 'vscode'
          AND (u.started_at >= ?1
               OR (u.status = 'inProgress' AND t.updated_at_ms >= ?1 * 1000))
        ORDER BY u.started_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(cutoff.timeIntervalSince1970))

        var out: [Thread] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(stmt, 0),
                  let statusText = sqlite3_column_text(stmt, 3) else { continue }
            let id = String(cString: idText)
            let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let cwd = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            out.append(Thread(id: id,
                              // 제목이 아직 안 붙은 스레드는 폴더 이름으로, 그것도 없으면 id 조각으로.
                              name: !name.isEmpty ? name
                                  : (!cwd.isEmpty ? URL(fileURLWithPath: cwd).lastPathComponent
                                                  : String(id.prefix(8))),
                              cwd: cwd,
                              state: Self.state(fromTurnStatus: String(cString: statusText)),
                              startedAt: date(sqlite3_column_int64(stmt, 4)),
                              updatedAt: date(sqlite3_column_int64(stmt, 5))))
        }
        return out
    }

    private func date(_ seconds: Int64) -> Date? {
        seconds > 0 ? Date(timeIntervalSince1970: Double(seconds)) : nil
    }

    /// codex 가 적은 턴 상태를 이 앱의 말로 옮긴다.
    ///
    /// 턴이 끝났다는 것은 **사람 차례**라는 뜻이므로 `idle` 이다. 중단·실패도 마찬가지로
    /// 사람이 봐야 하는 상태다. 처음 보는 값은 뭉개지 않고 원문을 들고 다닌다.
    private static func state(fromTurnStatus raw: String) -> SessionState {
        switch raw {
        case "inProgress":                          return .busy
        case "completed", "interrupted", "failed":  return .idle
        default:                                    return .unknown(raw)
        }
    }
}

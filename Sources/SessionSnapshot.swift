import Foundation

/// 재부팅 뒤 다시 열 세션의 **기록**과 그 기록을 다루는 셈.
///
/// 재부팅하면 세션 프로세스는 모두 죽는다. 「유지」는 안 되고 「적어 두고 다시 열기」만 된다.
/// 설계: `docs/design/specs/2026-11-14-재부팅-뒤-다시-열기.md`
///
/// 이 파일은 Foundation 만 쓴다 — 앱을 띄우지 않고도 셈을 시험할 수 있게 하려는 것이다.
/// 세션을 읽고 창을 여는 일은 `SessionReopen` 이 한다.

/// 다시 열 세션 하나.
struct SavedSession: Codable, Equatable {
    var source: String          // claude · codex
    var id: String              // 이어진 세션이면 대화를 쥔 뒤쪽 id
    var name: String
    var cwd: String
    var accountRoot: String     // claude 는 계정 루트, codex 는 codex 홈
    var background: Bool        // 창 없이 다시 열 것인가
    var args: [String]          // 다시 붙일 옵션 (허용 목록을 거친 것)
    var droppedArgs: [String]   // 붙이지 않은 옵션 — 메뉴에 보인다
    var state: String           // 적을 때의 상태 원문
    var lastSeen: Date
    /// Terminal 의 몇 번째 창(앞에서부터)의 몇 번째 탭에 있었는가. 못 쟀으면 없다.
    ///
    /// 창 id 가 아니라 순번을 적는다. id 는 재부팅하면 새로 매겨져 맞출 데가 없고,
    /// 다시 열 때 필요한 것은 「누구와 한 창에, 몇 번째로」뿐이다.
    var window: Int? = nil
    var tab: Int? = nil

    /// 끊길 때 턴이 돌고 있었는가. 다시 열 때 「작업 중이었음」으로 보인다.
    ///
    /// 승인 대기도 넣는다. 턴은 끝나지 않았고, 그 자리에서 끊긴 것이다.
    var wasWorking: Bool { ["busy", "shell", "waiting"].contains(state) }
}

/// 사람이 저장했거나, 재부팅을 알아채고 올려 둔 목록.
struct SavedList: Codable, Equatable {
    var at: Date
    var byUser: Bool            // 「세션 저장하고 모두 닫기…」로 저장했는가
    var sessions: [SavedSession]
    /// 한 번이라도 꺼진 것을 본 id.
    ///
    /// 저장한 직후에는 세션이 아직 살아 있다 (SIGTERM 은 몇 초 걸리고, 기다려 닫기는 일부러
    /// 늦춘다). 「살아 있으면 다시 연 것」으로만 셈하면 저장한 다음 훑기에서 목록이 걷힌다.
    /// 꺼진 것을 한 번 본 뒤에 살아 있어야 다시 연 것이다.
    var gone: [String] = []
}

/// 파일 하나에 든 것 전부.
struct SessionSnapshot: Codable, Equatable {
    /// 마지막으로 적은 시각. 재부팅 전에 적힌 것인지를 이 값으로 가린다.
    var writtenAt: Date
    /// 계속 적기 — 사라진 세션도 `lastSeen` 과 함께 남긴다 (설계 2.2).
    var seen: [SavedSession]
    /// 다시 열 목록. 다 열리거나 사람이 지울 때까지 남는다.
    var saved: SavedList?
}

enum SnapshotLogic {

    /// 사라진 세션을 이만큼 남긴다. 더 묵은 것은 다시 열 일이 없다.
    static let keepFor: TimeInterval = 24 * 60 * 60

    /// 마지막으로 적은 때로부터 이만큼 안에 보인 세션을 「끊길 때 살아 있던 것」으로 친다.
    ///
    /// 종료하는 동안 세션은 하나씩 죽고, 그사이 앱은 몇 번 더 적는다. 사라진 세션을 바로
    /// 지우면 기록이 0개로 덮이므로 남겨 두되, 이 창 밖의 것은 그전에 사람이 끈 것이다.
    static let lastMomentWindow: TimeInterval = 180

    /// 훑을 때마다 부른다. 지금 보이는 세션의 `lastSeen` 을 새로 하고, 안 보이는 것은 그대로 둔다.
    static func recording(_ live: [SavedSession], into old: SessionSnapshot?, now: Date) -> SessionSnapshot {
        var byID: [String: SavedSession] = [:]
        for s in old?.seen ?? [] { byID[s.id] = s }
        for s in live {
            var fresh = s
            fresh.lastSeen = now
            byID[s.id] = fresh
        }
        let seen = byID.values
            .filter { now.timeIntervalSince($0.lastSeen) < keepFor }
            .sorted { ($0.lastSeen, $0.id) > ($1.lastSeen, $1.id) }
        return SessionSnapshot(writtenAt: now, seen: seen, saved: old?.saved)
    }

    /// 앱이 켜질 때 한 번 부른다.
    ///
    /// 사람이 저장한 목록이 없고 기록이 이번 부팅 전에 적힌 것이면, 끊길 때 살아 있던
    /// 세션을 다시 열 목록으로 올린다. 올려 두지 않으면 켠 뒤의 계속 적기가 곧 덮는다.
    static func afterLaunch(_ snapshot: SessionSnapshot, bootedAt: Date) -> SessionSnapshot {
        // 앱을 오래 꺼 두었다가 재부팅했으면 그 기록은 이번 재부팅 직전의 모습이 아니다.
        guard snapshot.saved == nil, snapshot.writtenAt < bootedAt,
              bootedAt.timeIntervalSince(snapshot.writtenAt) < keepFor else { return snapshot }
        let last = snapshot.seen.filter {
            snapshot.writtenAt.timeIntervalSince($0.lastSeen) <= lastMomentWindow
        }
        guard !last.isEmpty else { return snapshot }
        var out = snapshot
        // 재부팅했으니 모두 꺼진 것을 본 셈이다.
        out.saved = SavedList(at: snapshot.writtenAt, byUser: false, sessions: last, gone: last.map(\.id))
        return out
    }

    /// 사람이 「저장하고 모두 닫기」를 눌렀다. 그 순간의 목록이 다시 열 목록이 된다.
    static func saving(_ live: [SavedSession], into old: SessionSnapshot?, now: Date) -> SessionSnapshot {
        var out = recording(live, into: old, now: now)
        let stamped = live.map { s -> SavedSession in var c = s; c.lastSeen = now; return c }
        // 닫지 않는 세션(codex)은 꺼질 일이 없으니 미리 꺼진 셈으로 친다. 안 그러면 목록이 영영 안 걷힌다.
        let neverClosed = stamped.filter { $0.source != "claude" }.map(\.id)
        out.saved = SavedList(at: now, byUser: true, sessions: stamped, gone: neverClosed)
        return out
    }

    /// 아직 다시 열지 않은 것. 지금 살아 있는 세션은 뺀다 — 손으로 이미 연 것도 같다.
    static func pending(_ snapshot: SessionSnapshot?, liveIDs: Set<String>) -> [SavedSession] {
        snapshot?.saved?.sessions.filter { !liveIDs.contains($0.id) } ?? []
    }

    /// 꺼진 것을 적고, 모두 한 번 꺼졌다가 다시 열렸으면 목록을 걷는다.
    /// 걷지 않으면 다음 재부팅 때 옛 목록이 되살아난다.
    static func settled(_ snapshot: SessionSnapshot, liveIDs: Set<String>) -> SessionSnapshot {
        guard var saved = snapshot.saved else { return snapshot }
        var out = snapshot
        let newlyGone = saved.sessions.map(\.id).filter { !liveIDs.contains($0) && !saved.gone.contains($0) }
        saved.gone += newlyGone
        let allWentAway = saved.sessions.allSatisfy { saved.gone.contains($0.id) }
        if allWentAway && pending(snapshot, liveIDs: liveIDs).isEmpty {
            out.saved = nil
        } else {
            out.saved = saved
        }
        return out
    }

    /// 닫기를 기다리던 세션이 그새 이어져 id 가 바뀌었다. 다시 열 때는 뒤쪽 id 를 써야 한다.
    static func renaming(_ snapshot: SessionSnapshot, from old: String, to new: String) -> SessionSnapshot {
        guard var saved = snapshot.saved else { return snapshot }
        for i in saved.sessions.indices where saved.sessions[i].id == old { saved.sessions[i].id = new }
        var out = snapshot
        out.saved = saved
        return out
    }
}

// MARK: - 옵션 고르기

/// 띄울 때 붙였던 옵션 중 **다시 붙일 것**을 고른다 (설계 3.2).
///
/// `--resume` 이 기록에서 되살리는 것(권한 모드 — 실측)은 붙이지 않는다. 붙이면 기록과
/// 다투게 된다. 허용 목록 밖의 옵션은 버리지 않고 `dropped` 로 돌려 메뉴에 보인다 —
/// 말없이 빠지면 「왜 그때와 다르지」를 사람이 알 길이 없다.
enum ReopenArgs {

    /// 다시 붙이는 것.
    static let flags: Set<String> = ["--dangerously-skip-permissions",
                                     "--allow-dangerously-skip-permissions"]

    /// 말없이 버리는 것. 다시 열기가 스스로 정하거나(`--resume`), 기록이 되살리는 것이다.
    static let silent: Set<String> = ["--resume", "-r", "--continue", "-c", "--session-id",
                                      "--fork-session", "--permission-mode"]

    /// `argv` 는 프로세스 인자 그대로 (`argv[0]` 은 실행 파일).
    static func split(_ argv: [String]) -> (keep: [String], dropped: [String]) {
        var keep: [String] = []
        var dropped: [String] = []
        let tokens = Array(argv.dropFirst())
        var i = 0

        /// 바로 뒤의 값 하나를 집는다. `-` 로 시작하면 값이 아니다.
        func value(after index: Int) -> String? {
            let next = index + 1
            guard next < tokens.count, !tokens[next].hasPrefix("-") else { return nil }
            return tokens[next]
        }

        while i < tokens.count {
            let t = tokens[i]
            let name = t.split(separator: "=", maxSplits: 1).first.map(String.init) ?? t
            let inline = t.contains("=")

            if name == "--remote-control" {
                keep.append(t)
                if !inline, let v = value(after: i) { keep.append(v); i += 1 }
            } else if name == "--add-dir" {
                keep.append(t)
                // 폴더를 여럿 받는다.
                if !inline {
                    while let v = value(after: i) { keep.append(v); i += 1 }
                }
            } else if flags.contains(name) {
                keep.append(t)
            } else if silent.contains(name) {
                if !inline, let _ = value(after: i) { i += 1 }
            } else if t.hasPrefix("-") {
                dropped.append(t)
                if !inline, let v = value(after: i) { dropped.append(v); i += 1 }
            }
            // `-` 없는 낱말은 처음 띄울 때 건넨 첫 질문이다. 다시 보내면 안 된다.
            i += 1
        }
        return (unique(keep), unique(dropped))
    }

    /// 같은 옵션을 한 번만 남긴다. 옵션과 그 값들을 한 묶음으로 본다.
    ///
    /// 다시 열 때 옵션을 `--resume` 뒤에 붙이므로, 그 세션을 다시 저장하면 처음 것과 붙인
    /// 것이 둘 다 잡힌다. 안 걷으면 다시 열 때마다 하나씩 늘었다 (실측 2026-11-15, 한 세션에
    /// `--remote-control=agent-monitor` 가 여러 번).
    static func unique(_ args: [String]) -> [String] {
        var groups: [[String]] = []
        for t in args {
            if t.hasPrefix("-") || groups.isEmpty { groups.append([t]) } else { groups[groups.count - 1].append(t) }
        }
        var seen: [[String]] = []
        for g in groups where !seen.contains(g) { seen.append(g) }
        return seen.flatMap { $0 }
    }
}

// MARK: - 창 배치

/// Terminal 의 창·탭 배치를 적고 되살리는 셈.
enum ReopenLayout {

    /// Terminal 창 하나 (AppleScript 가 보는 것).
    ///
    /// macOS 탭을 쓰는 Terminal 은 **탭 하나하나를 창으로** 돌려준다 (실측 2026-11-15 — 탭 둘인
    /// 창이 「탭 하나짜리 창 둘」로 나왔다). 그래서 「몇 번째 창의 몇 번째 탭」을 그대로 물으면
    /// 모두 1번 탭이 된다. 같은 묶음의 탭은 틀(bounds)이 같고, 앞에 보이는 탭만 화면에
    /// 그려진다 — 이 둘로 묶음을 되짓는다.
    struct TerminalWindow: Equatable {
        var index: Int      // 앞에서부터 순번
        var id: Int         // 창 번호 (CGWindowID 와 같다)
        var bounds: String
        var tty: String
        var onScreen: Bool  // 그려지고 있는가. 묶음 뒤에 숨은 탭은 거짓이다
    }

    /// `순번 id 틀 tty` 줄들. 틀은 공백 없이 `x1,y1,x2,y2`.
    static func parse(_ text: String, onScreen: Set<Int>) -> [TerminalWindow] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: " ")
            guard f.count == 4, let i = Int(f[0]), let id = Int(f[1]), f[3].hasPrefix("/dev/") else { return nil }
            return TerminalWindow(index: i, id: id, bounds: String(f[2]), tty: String(f[3]), onScreen: onScreen.contains(id))
        }
    }

    /// tty → (묶음 순번, 묶음 안 탭 순번).
    ///
    /// - 그려지는 창은 저마다 한 묶음이다. 틀이 같아도 둘 다 보이면 다른 창이다.
    /// - 숨은 창은 틀이 같은 그려지는 창 중 가장 앞의 것에 붙는다. 붙을 데가 없으면
    ///   (다른 데스크탑에 있거나 접혀 있으면) 틀이 같은 숨은 창끼리 한 묶음이다.
    /// - 묶음 순번은 그 묶음에서 가장 앞에 있는 창의 순번 차례, 탭 순번은 창 번호 차례다.
    ///   탭을 끌어 순서를 바꿨으면 그건 못 따라간다 — 창 번호는 만든 차례다.
    static func groups(of windows: [TerminalWindow]) -> [String: (window: Int, tab: Int)] {
        var leader: [Int: Int] = [:]                    // 창 id → 묶음 대표 id
        let front = windows.sorted { $0.index < $1.index }
        for w in front where w.onScreen { leader[w.id] = w.id }
        for w in front where !w.onScreen {
            let host = front.first { $0.onScreen && $0.bounds == w.bounds }
                ?? front.first { !$0.onScreen && $0.bounds == w.bounds && leader[$0.id] == $0.id }
            leader[w.id] = host?.id ?? w.id
        }
        var members: [Int: [TerminalWindow]] = [:]
        for w in front { members[leader[w.id]!, default: []].append(w) }
        let order = members.values.sorted { $0.map(\.index).min()! < $1.map(\.index).min()! }
        var out: [String: (window: Int, tab: Int)] = [:]
        for (g, list) in order.enumerated() {
            for (t, w) in list.sorted(by: { $0.id < $1.id }).enumerated() { out[w.tty] = (g + 1, t + 1) }
        }
        return out
    }

    /// 한 창에 열 묶음들. 묶음 안은 탭 차례대로, 묶음은 **뒤 창부터** 둔다.
    ///
    /// 차례대로 열면 마지막에 연 창이 맨 앞에 온다. 뒤 창부터 열어야 끊기 전에 맨 앞이던
    /// 창이 다시 맨 앞에 선다. 자리를 모르는 세션과 백그라운드 세션은 저마다 한 묶음이다.
    static func groups(_ list: [SavedSession]) -> [[SavedSession]] {
        var byWindow: [Int: [SavedSession]] = [:]
        var alone: [[SavedSession]] = []
        for s in list {
            if !s.background, let w = s.window { byWindow[w, default: []].append(s) } else { alone.append([s]) }
        }
        let windows = byWindow.keys.sorted(by: >).map { w in
            byWindow[w]!.sorted { ($0.tab ?? 0, $0.id) < ($1.tab ?? 0, $1.id) }
        }
        return alone + windows
    }
}

// MARK: - 명령 만들기

enum ReopenCommand {

    /// 셸에 그대로 넣을 수 있게 감싼다.
    static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 터미널 창에 칠 한 줄.
    ///
    /// 기본 계정이면 `CLAUDE_CONFIG_DIR` 를 붙이지 않는다. 붙이면 설정 파일 자리가
    /// `~/.claude.json` 에서 `~/.claude/.claude.json` 으로 옮겨 가 다른 계정처럼 뜬다.
    static func terminalLine(for s: SavedSession, defaultRoot: String) -> String {
        let cd = "cd -- \(quoted(s.cwd))"
        let isDefault = standardized(s.accountRoot) == standardized(defaultRoot)
        switch s.source {
        case "codex":
            let env = isDefault ? "" : "CODEX_HOME=\(quoted(s.accountRoot)) "
            return "\(cd) && \(env)codex resume \(quoted(s.id))"
        default:
            let env = isDefault ? "" : "CLAUDE_CONFIG_DIR=\(quoted(s.accountRoot)) "
            let rest = ReopenArgs.unique(s.args).map(quoted).joined(separator: " ")
            return "\(cd) && \(env)claude --resume \(quoted(s.id))" + (rest.isEmpty ? "" : " \(rest)")
        }
    }

    /// AppleScript 문자열 안에 넣을 수 있게 감싼다.
    static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }
}

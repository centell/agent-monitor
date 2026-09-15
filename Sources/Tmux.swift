import Foundation

/// tmux 안에서 도는 세션에게 **창으로 가는 다리**를 놓는다.
///
/// 터미널 창을 찾는 고리는 tty 다 (`TerminalJump`). 그런데 tmux 안의 세션은 그 고리가
/// 중간에서 끊긴다 — 세션의 tty 는 tmux 가 만든 **pane 의 pty** 이고, 터미널 탭이 쥔 tty 는
/// tmux **클라이언트** 쪽이라 둘이 서로 다른 값이다. 그래서 같은 tty 를 가진 탭을 아무리
/// 찾아도 세상에 없다.
///
/// 실측(2026-09-15, 이 맥): Terminal.app 탭 13개의 tty 를 모두 뽑아 세션 tty 와 대조했다.
///
///     vcrm-base  /dev/ttys008  맨 탭      → 찾음
///     ws         /dev/ttys011  tmux pane → 못 찾음   (클라이언트는 /dev/ttys004)
///     ws-ast     /dev/ttys013  tmux pane → 못 찾음   (클라이언트는 /dev/ttys012)
///
/// 갈린 자리가 「Terminal.app 이 아니라서」가 아니라 **「tmux pane 이라서」** 였다 — 그때
/// 이 맥에는 Terminal.app 말고 다른 터미널이 아예 떠 있지 않았다.
///
/// 그래서 이 파일이 하는 일은 하나다: **pane 의 tty 를 받아 그 pane 이 실제로 보이는 창의
/// tty 를 돌려준다.** 창을 앞으로 가져오는 일은 여전히 `TerminalJump` 가 한다.
enum Tmux {

    /// pane 하나가 어디에 사는지.
    struct Pane {
        /// `tmux` 에게 이 pane 을 가리킬 때 쓰는 말 (`$0:0.0`). 세션을 **id 로** 짚는다 —
        /// 이름은 사람이 바꿀 수 있고 공백도 들어가지만 id 는 그렇지 않다.
        let target: String
        /// 사람에게 보여 줄 세션 이름 (`ws`).
        let sessionName: String
        /// 이 pane 이 지금 보이고 있는 창의 tty. **떨어져 있으면 `nil`** — 그때는 이 세션이
        /// 세상 어느 창에도 그려지고 있지 않다.
        let clientTTY: String?
    }

    // MARK: 실행 파일 찾기

    /// `tmux` 가 어디 있는가.
    ///
    /// `PATH` 를 믿을 수 없는 이유는 `SessionStop.binary()` 와 같다 — 이 앱은 GUI 번들이라
    /// 로그인 셸의 `PATH` 를 물려받지 않아, 터미널에서 되는 명령이 여기서는 없는 명령이
    /// 된다. 실측으로 이 맥의 tmux 는 `/opt/homebrew/bin/tmux` 에 있고, 앱이 물려받은
    /// `PATH` 에는 그 자리가 없다.
    ///
    /// 셸을 띄워 `which` 를 묻지 않는다. 그건 남의 `.zshrc` 를 통째로 실행하는 일이다.
    private static func binary() -> String? {
        let home = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
            "\(home)/.local/bin/tmux",
        ]
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            candidates.append("\(dir)/tmux")
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// tmux 에게 묻고 답을 받는다. 서버가 없거나(`no server running`) 답이 0 이 아니면 `nil`.
    ///
    /// 실패를 말로 만들지 않는다. 여기서 나오는 실패는 죄다 **tmux 를 안 쓰는 맥**의 평범한
    /// 모습이라, 그걸 사람에게 알릴 이유가 없다. 부르는 쪽은 그저 「tmux 는 아니었다」로
    /// 읽고 하던 길을 간다.
    @discardableResult
    private static func run(_ arguments: [String]) -> String? {
        guard let tmux = binary() else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: tmux)
        task.arguments = arguments

        let out = Pipe()
        task.standardOutput = out
        // 서버가 없을 때 tmux 는 stderr 로 떠든다. 앱은 GUI 번들이라 그 글이 뜰 곳이 없으니
        // 받아서 버린다 — 파이프를 안 달면 그대로 콘솔로 샌다.
        task.standardError = Pipe()

        do { try task.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: 묻기

    /// 이 tty 를 쓰는 pane 이 tmux 안에 있는가. 있으면 그 pane 이 사는 곳을 돌려준다.
    ///
    /// **누를 때만 부른다.** 줄을 그릴 때마다 부르면 갱신 한 번에 서브프로세스가 하나씩
    /// 뜨고, 붙었는지 떨어졌는지는 1초 만에도 바뀌어서 그려 둔 값이 이미 옛말이 된다.
    static func pane(forTTY tty: String) -> Pane? {
        // 이름을 **맨 뒤에** 둔다. 세션 이름에는 공백이 들어갈 수 있고, 앞에 두면 그 공백이
        // 뒤 칸들을 밀어 버린다. 앞의 네 칸은 공백이 들어갈 수 없는 값들이다.
        let format = "#{pane_tty} #{session_id} #{window_index} #{pane_index} #{session_name}"
        guard let listing = run(["list-panes", "-a", "-F", format]) else { return nil }

        for line in listing.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5, fields[0] == tty else { continue }

            let sessionID = String(fields[1])
            let target = "\(sessionID):\(fields[2]).\(fields[3])"
            return Pane(target: target,
                        sessionName: String(fields[4]),
                        clientTTY: clientTTY(ofSession: sessionID))
        }
        return nil
    }

    /// 이 세션을 지금 보고 있는 창의 tty.
    ///
    /// 여러 창이 한 세션을 함께 볼 수 있어 답이 여럿일 수 있다. 첫째를 고른다 — 어느 쪽이든
    /// 같은 화면이 그려지고 있으므로 고르기로 더 나은 하나가 없다.
    ///
    /// **다른 세션에 붙어 있는 창을 이 세션으로 돌리지는(`switch-client`) 않는다.** 그
    /// 창에서 일하던 사람의 화면을 빼앗는 일이라, 「갈 창이 없다」고 말하는 편이 정직하다.
    private static func clientTTY(ofSession sessionID: String) -> String? {
        guard let listing = run(["list-clients", "-t", sessionID, "-F", "#{client_tty}"]) else {
            return nil
        }
        return listing.split(separator: "\n").first.map(String.init)
    }

    // MARK: 짚기

    /// 그 창 안에서 이 pane 을 앞에 세운다.
    ///
    /// 창을 앞으로 가져오는 것만으로는 덜 갔다. tmux 세션 안에서 사람이 다른 창(window)이나
    /// 다른 pane 을 보고 있었다면, 도착한 화면에 그 세션이 없다.
    ///
    /// 보고 있던 pane 이 바뀌는 것은 부작용이 아니라 **누른 뜻 그 자체**다 — 이 줄을 누른
    /// 사람은 이 세션을 보러 온 것이다.
    static func focus(_ pane: Pane) {
        run(["select-window", "-t", pane.target])
        run(["select-pane", "-t", pane.target])
    }
}

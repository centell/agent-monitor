import Foundation

/// 세션을 **멈춘다.**
///
/// 목록은 여태 보여 주기만 했다. 그런데 백그라운드 세션은 터미널을 닫아도 안 죽는다 —
/// 창이 아니라 daemon 아래 `bg-pty-host` 가 쥐고 있기 때문이다. 그래서 「분명 껐는데
/// 남아 있는 줄」이 생기고, 그 줄은 눌러도 갈 데가 없어 손쓸 길이 하나도 없었다.
/// 보여 주기만 하고 손댈 수 없는 줄은 계기판이 아니라 표지판이다.
///
/// 죽이지 않고 **CLI 에게 시킨다** (`claude stop`). `kill` 로 끊으면 그 세션이 적다 만
/// 기록이 어디서 끊길지 우리가 모른다. `claude stop` 은 대화를 지우지 않으므로
/// `claude attach <id>` 로 다시 열 수 있다 — 되돌릴 수 있는 종료다.
enum SessionStop {

    /// 이 줄을 멈출 수 있는가.
    ///
    /// **`SessionJump.canJump` 가 false 를 내는 바로 그 조건이다.** 갈 수 없는 줄과 멈출 수
    /// 있는 줄이 정확히 같은 집합이라, 「눌러도 아무 데도 못 가던 그 줄」에 비로소 할 일이
    /// 생긴다.
    ///
    /// `isBackground` 만으로 가르면 안 된다. **이어진 세션은 `kind: "bg"` 인 채로 목록에
    /// 남는다** — 대화가 daemon 쪽 프로세스로 옮겨 갔을 뿐, 사람이 앉아 있는 진짜 세션이다.
    /// 그 줄에 멈추기를 달면 주인이 지금 쓰고 있는 세션을 끄게 된다. 물려받은 창이 있는지
    /// (`continuedFromPid`)를 함께 봐야 갈린다.
    static func canStop(_ session: Session) -> Bool {
        session.isBackground && session.continuedFromPid == nil
    }

    enum Outcome {
        case stopped
        case noBinary                  // `claude` 를 못 찾았다
        case failed(String)

        /// 누른 사람에게 그 자리에서 보일 한 줄. 성공에는 없다 — 줄이 사라지는 것이 답이다.
        var message: String? {
            switch self {
            case .stopped:          return nil
            case .noBinary:         return S.stopNoBinary
            case .failed(let why):  return S.stopFailedLine(why)
            }
        }
    }

    // MARK: 실행 파일 찾기

    /// `claude` 가 어디 있는가.
    ///
    /// `PATH` 를 믿을 수 없다. 이 앱은 GUI 번들이라 로그인 셸의 `PATH` 를 물려받지 않는다 —
    /// 터미널에서 되는 명령이 여기서는 「없는 명령」이 된다. 그래서 흔한 자리를 직접 짚는다.
    ///
    /// 셸을 띄워 `which` 를 묻지 않는다. 그 방법은 사용자의 `.zshrc` 를 통째로 실행하는
    /// 것이라, 남의 설정이 무엇을 하는지 모르는 채 앱이 그것을 떠안게 된다.
    private static func binary() -> String? {
        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        // `PATH` 가 쓸 만하면 그것도 본다. 없다고 막지는 않되, 있으면 마다할 이유도 없다.
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            candidates.append("\(dir)/claude")
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: 멈추기

    /// 세션을 멈춘다. **부르는 쪽 줄을 막는다** — 부르는 자리가 이미 딴 줄이다 (`stop(_:then:)`).
    private static func run(_ session: Session) -> Outcome {
        guard let claude = binary() else { return .noBinary }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: claude)
        task.arguments = ["stop", session.shortID]

        // **계정 루트를 짚어 준다.** 계정을 여러 개 쓰면 CLI 는 제 기본 루트만 보므로,
        // 다른 계정의 세션은 「그런 세션 없음」이 된다. 목록은 루트를 전부 훑어 보여 주면서
        // 멈추기만 한 루트만 본다면, 보이는데 못 멈추는 줄이 생긴다.
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CONFIG_DIR"] = session.accountRoot.path
        task.environment = env

        let out = Pipe()
        task.standardOutput = out
        task.standardError = out

        do {
            try task.run()
        } catch {
            return .failed(error.localizedDescription)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if task.terminationStatus == 0 { return .stopped }
        let said = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(said.isEmpty ? S.errExit(Int(task.terminationStatus)) : said)
    }

    /// 멈추고 나서 알린다.
    ///
    /// **딴 줄에서 돌린다.** `claude stop` 은 소켓을 잡고 상대가 내려가기를 기다리므로
    /// 곧바로 돌아오지 않는다. 본 줄에서 부르면 그동안 창이 통째로 얼고, 상시 창은
    /// 늘 떠 있는 물건이라 그 멈춤이 화면 한복판에 남는다.
    static func stop(_ session: Session, then report: @escaping (Outcome) -> Void) {
        DispatchQueue.global().async {
            let outcome = run(session)
            DispatchQueue.main.async { report(outcome) }
        }
    }
}

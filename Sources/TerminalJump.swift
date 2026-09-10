import AppKit
import Darwin
import Foundation

/// 세션을 눌렀을 때 그 세션이 도는 터미널 창으로 화면을 옮긴다.
///
/// 잇는 고리는 tty 다. 세션 프로세스의 tty 를 커널에서 읽고, 같은 tty 를 쓰는
/// 터미널 창을 찾아 앞으로 가져온다.
///
/// 지금은 macOS 기본 Terminal.app 만 다룬다. iTerm2·Ghostty 등은 각자 다른
/// 자동화 통로를 쓰므로 나중에 이 파일에 더한다.
enum TerminalJump {

    enum Outcome {
        case moved
        case noTTY              // 세션에 터미널이 없다 (headless 등)
        case windowNotFound     // tty 는 있는데 그 창을 못 찾았다
        case notPermitted       // 자동화 권한이 없다
        case failed(String)

        /// 누른 사람에게 그 자리에서 보일 한 줄.
        ///
        /// 성공과 «권한 없음» 에는 없다 — 성공은 할 말이 없고, 권한은 사람이 **고칠 수
        /// 있는** 문제라 지나가는 한 줄이 아니라 안내가 필요하다.
        ///
        /// 짧게 둔다. 이 글은 목록의 한 줄 자리에 들어가므로, 길면 그 3초 동안 창이
        /// 넓어졌다 줄어든다.
        var message: String? {
            switch self {
            case .moved, .notPermitted: return nil
            case .noTTY:                return S.jumpNoTerminal
            case .windowNotFound:       return S.jumpNoWindow
            case .failed(let why):      return S.jumpFailedLine(why)
            }
        }
    }

    // MARK: tty 읽기

    /// pid → `/dev/ttysNNN`.
    ///
    /// `ps` 를 띄우지 않고 커널에서 바로 읽는다. 목록을 그릴 때마다 서브프로세스를
    /// 부를 이유가 없다.
    static func ttyPath(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let dev = info.kp_eproc.e_tdev
        guard dev != -1, let name = devname(dev, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// 이 세션을 눌러서 갈 수 있는가. 목록을 그릴 때 쓰므로 권한을 건드리지 않는다.
    static func canJump(pid: Int32) -> Bool { ttyPath(pid: pid) != nil }

    // MARK: 이동

    @discardableResult
    static func jump(pid: Int32) -> Outcome {
        guard let tty = ttyPath(pid: pid) else { return .noTTY }

        let escaped = tty.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (tty of t) is "\(escaped)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "moved"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "notfound"
        """

        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { return .failed(S.errScript) }
        let result = apple.executeAndReturnError(&error)

        if let error {
            // -1743: 사용자가 자동화를 아직 허용하지 않았다.
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == errAEEventNotPermitted {
                return .notPermitted
            }
            return .failed(error[NSAppleScript.errorMessage] as? String ?? S.errUnknown(code))
        }
        return result.stringValue == "moved" ? .moved : .windowNotFound
    }

    // MARK: 알림

    /// 실패를 조용히 삼키지 않는다.
    ///
    /// **답할 자리가 없을 때 쓴다.** 메뉴에서 누른 경우가 그렇다 — 누르는 순간 메뉴가
    /// 닫히므로 글자를 바꿀 줄 자체가 사라진다. 상시 창에서 누른 경우는 그 줄에 그대로
    /// 띄우므로 여기까지 오지 않는다 (`FloatingPanelController`).
    ///
    /// 예전에는 권한 문제만 말을 걸고 나머지는 **삑 소리 한 번**이었다. 이유는 `stderr`
    /// 에 적었는데, 이 앱은 GUI 번들이라 그 글이 뜨는 곳이 세상에 없다. 다른 터미널을
    /// 쓰는 사람에게는 모든 줄이 아무 설명 없이 안 되는 물건으로 보였다.
    static func report(_ outcome: Outcome, sessionName: String) {
        switch outcome {
        case .moved:
            return

        case .notPermitted:
            log(sessionName, S.permissionTitle)
            speak(title: S.permissionTitle, body: S.permissionBody)

        case .noTTY:
            log(sessionName, S.logNoTTY)
            speak(title: S.jumpNoTerminal, body: S.jumpNoTerminalDetail)

        case .windowNotFound:
            log(sessionName, S.logNoWindow)
            speak(title: S.jumpNoWindow, body: S.jumpNoWindowDetail)

        case .failed(let message):
            log(sessionName, S.logFailed(message))
            speak(title: S.jumpFailedTitle, body: message)
        }
    }

    /// 앞을 뺏고 말을 건다.
    ///
    /// 이 앱은 Dock 아이콘이 없어 `activate` 없이는 상자가 뒤에 깔린 채 뜬다.
    /// 메뉴바를 방금 누른 뒤라 손이 다른 데 가 있지 않은 순간이라서, 여기서는 이 무게가
    /// 치를 만하다. 같은 상자를 상시 창에서 띄우지 않는 이유도 이것이다 — 그쪽은
    /// 「눌러도 앞을 안 뺏는다」로 서 있다.
    private static func speak(title: String, body: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: S.okButton)
        alert.runModal()
    }

    private static func log(_ sessionName: String, _ line: String) {
        FileHandle.standardError.write(Data("\(sessionName): \(line)\n".utf8))
    }
}

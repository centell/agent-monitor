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
    /// 권한 문제는 사람이 고칠 수 있는 것이므로 무엇을 하면 되는지까지 말해 준다.
    /// 나머지는 소리로만 알린다 — 메뉴가 이미 닫힌 뒤라 띄울 자리가 마땅치 않다.
    static func report(_ outcome: Outcome, sessionName: String) {
        switch outcome {
        case .moved:
            return

        case .notPermitted:
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = S.permissionTitle
            alert.informativeText = S.permissionBody
            alert.alertStyle = .informational
            alert.addButton(withTitle: S.okButton)
            alert.runModal()

        case .noTTY:
            NSSound.beep()
            FileHandle.standardError.write(Data("\(sessionName): \(S.logNoTTY)\n".utf8))

        case .windowNotFound:
            NSSound.beep()
            FileHandle.standardError.write(Data("\(sessionName): \(S.logNoWindow)\n".utf8))

        case .failed(let message):
            NSSound.beep()
            FileHandle.standardError.write(Data("\(sessionName): \(S.logFailed(message))\n".utf8))
        }
    }
}

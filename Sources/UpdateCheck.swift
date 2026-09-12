import AppKit
import Foundation

/// 새 판이 나왔는지 보고, 주인이 누르면 받아 갈아 끼운다.
///
/// **Sparkle 을 쓰지 않는다.** 이 앱은 서명이 없어 Sparkle 의 가장 큰 값(EdDSA 로 받은
/// 것을 검증해 «받아오는 곳을 못 믿어도 되게» 하는 것)이 덜 쳐진다 — 사람들은 이미 같은
/// GitHub 릴리즈에서 같은 HTTPS 로 zip 을 손으로 받고 있고, 자동으로 받는다고 그 기준이
/// 낮아지지 않는다. 대신 치를 값은 컸다: 의존성 0 이 깨지고(손으로 짓는 번들에 프레임워크가
/// 들어간다), 릴리즈마다 appcast 를 만들어 올려야 하며(잊으면 사용자는 **조용히** 못 받는다),
/// 앱에서 유일하게 말투가 다른 창이 하나 생긴다.
///
/// 다만 **사람이 받을 땐 눈이 한 번 거치는데 자동은 안 거친다.** 그 차이는 남는다.
///
/// 재 둔 것 둘 — 이 길이 막히지 않는다는 근거다.
/// · `URLSession` 으로 받은 파일에는 격리 딱지가 안 붙는다(실측). 붙었다면 서명 없는 앱은
///   갈아 끼운 순간 macOS 가 막아서, 자동업데이트가 앱을 못 뜨게 만들었을 것이다.
/// · 번들을 갈아 끼워도 터미널 제어 권한은 살아남는다(실측: 9/7 에 허용된 기록이 그 뒤
///   여러 번의 교체를 지나 그대로였다). macOS 가 서명이 아니라 **번들 식별자**로 기억한다.
final class UpdateCheck: ObservableObject {

    static let shared = UpdateCheck()

    /// 찾은 새 판.
    struct Release {
        let version: String
        let pageURL: URL
        let archiveURL: URL
    }

    /// 메뉴에 내걸 새 판. 없으면 메뉴에 아무 줄도 늘지 않는다.
    @Published private(set) var found: Release?
    /// 설정창에만 보이는 한 줄. 「눌렀는데 아무 일도 안 일어난다」를 막는다.
    @Published private(set) var status: String?

    private var busy = false
    /// 마지막으로 본 때. 「정보」 탭이 이걸 적어 둔다 — **언제 봤는지 모르는 확인은
    /// 「확인하고 있다」는 말을 못 받쳐 준다.**
    @Published private(set) var lastChecked: Date?

    /// 얼마나 자주 볼 것인가. 하루 한 번이면 충분하고, 그만큼 값이 없다.
    private let interval: TimeInterval = 24 * 60 * 60

    /// 지금 이 앱의 판. **번들 밖(CLI)에서는 없다** — 제 판을 모르면 견줄 수가 없다.
    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// 어디를 보는가.
    ///
    /// 환경변수로 갈아끼울 수 있게 둔다 — 진짜 릴리즈를 올리지 않고도 교체까지 돌려 보기
    /// 위해서다. 이 프로젝트가 다른 출처에 이미 쓰는 방식과 같다(「못 재는 코드는 못 믿는
    /// 코드다」). 파일 경로를 줘도 받는다.
    private var feed: URL {
        let fallback = "https://api.github.com/repos/centell/agent-monitor/releases/latest"
        let text = ProcessInfo.processInfo.environment["AGENT_MONITOR_UPDATE_FEED"]
        return Self.resolve(text?.isEmpty == false ? text! : fallback)
            ?? URL(string: fallback)!
    }

    private static func resolve(_ text: String) -> URL? {
        text.hasPrefix("/") ? URL(fileURLWithPath: text) : URL(string: text)
    }

    // MARK: 확인

    /// 볼 때가 되었으면 본다. 갱신 주기마다 불려도 값이 없다 — 대개 곧바로 돌아선다.
    func check(force: Bool = false) {
        guard force || Settings.shared.checkForUpdates else { return }
        guard let current = Self.currentVersion else { return }
        guard !busy else { return }
        if !force, let last = lastChecked, Date().timeIntervalSince(last) < interval { return }

        busy = true
        lastChecked = Date()
        if force { status = S.updateChecking }

        fetch(feed) { [weak self] data in
            guard let self else { return }
            defer { self.busy = false }
            guard let data, let release = Self.parse(data) else {
                // 네트워크가 없거나 한도에 걸린 것은 **고장이 아니다.** 조용히 지나간다.
                if force { self.status = S.updateCheckFailed }
                return
            }
            guard Self.isNewer(release.version, than: current) else {
                self.found = nil
                if force { self.status = S.updateUpToDate }
                return
            }
            self.found = release
            self.status = nil
        }
    }

    /// 받아서 갈아 끼운다. 주인이 눌렀을 때만 불린다.
    func install(_ release: Release) {
        guard !busy else { return }
        busy = true
        status = S.updateDownloading

        let destination = Bundle.main.bundleURL
        // 남의 자리(/Applications 등)에 깔려 있으면 우리가 못 바꾼다. 그럴 땐 손으로
        // 받으시게 페이지를 연다 — 조용히 실패하는 것보다 낫다.
        guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            busy = false
            failed(S.updateNotWritable, release: release)
            return
        }

        let stage = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AgentMonitor-update-\(UUID().uuidString)")

        fetchFile(release.archiveURL, into: stage) { [weak self] archive in
            guard let self else { return }
            guard let archive else {
                self.busy = false
                self.failed(S.updateDownloadFailed, release: release)
                return
            }
            let unpacked = stage.appendingPathComponent("unpacked")
            guard Self.unzip(archive, into: unpacked),
                  let fresh = Self.bundle(in: unpacked, expecting: release.version) else {
                self.busy = false
                try? FileManager.default.removeItem(at: stage)
                self.failed(S.updateBadArchive, release: release)
                return
            }
            self.swap(to: fresh, at: destination, stage: stage, release: release)
        }
    }

    // MARK: 갈아 끼우기

    /// 돌고 있는 자기 자신은 못 갈아 끼운다. 짧은 도우미에게 넘기고 우리는 빠진다.
    ///
    /// 옛 판을 지우지 않고 **옆에 물려 둔다.** 새 판이 안 서면 그걸 도로 제자리에 놓는다 —
    /// 업데이트가 앱을 없애는 일만은 없어야 한다.
    private func swap(to fresh: URL, at destination: URL, stage: URL, release: Release) {
        let script = stage.appendingPathComponent("swap.sh")
        let backup = stage.appendingPathComponent("previous.app")
        do {
            try Self.swapScript.write(to: script, atomically: true, encoding: .utf8)
        } catch {
            busy = false
            try? FileManager.default.removeItem(at: stage)
            failed(S.updateBadArchive, release: release)
            return
        }

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [script.path, destination.path, fresh.path, backup.path,
                            String(ProcessInfo.processInfo.processIdentifier), stage.path]
        do { try helper.run() } catch {
            busy = false
            try? FileManager.default.removeItem(at: stage)
            failed(S.updateSwapFailed, release: release)
            return
        }
        // 우리가 빠져야 도우미가 시작한다. `terminate` 로 나가야 진행 중이던 대기가 기록된다.
        NSApp.terminate(nil)
    }

    private static let swapScript = """
    #!/bin/sh
    # $1 지금 앱 자리 · $2 새 앱 · $3 옛 판을 물려 둘 자리 · $4 앱의 pid · $5 치울 임시 폴더
    dest="$1" ; fresh="$2" ; backup="$3" ; pid="$4" ; stage="$5"

    # 앱이 완전히 빠질 때까지 기다린다. 돌고 있는 번들을 건드리면 안 된다.
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1 ; i=$((i+1)) ; done

    rm -rf "$backup"
    mv "$dest" "$backup" || exit 1
    if ! mv "$fresh" "$dest"; then mv "$backup" "$dest" ; exit 1 ; fi

    if ! open "$dest"; then
        rm -rf "$dest" ; mv "$backup" "$dest" ; open "$dest" ; rm -rf "$stage" ; exit 1
    fi

    # 새 판이 **실제로 서 있는지** 보고서 옛 판을 버린다. 안 서 있으면 되돌린다.
    sleep 3
    if pgrep -f "$dest/Contents/MacOS/" >/dev/null 2>&1; then
        rm -rf "$backup" "$stage"
    else
        rm -rf "$dest" ; mv "$backup" "$dest" ; open "$dest" ; rm -rf "$stage"
    fi
    """

    /// 받아 온 것이 **정말 이 앱의 그 판인지** 본다. 아니면 갈아 끼우지 않는다.
    private static func bundle(in directory: URL, expecting version: String) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return nil }

        for item in items where item.pathExtension == "app" {
            guard let data = try? Data(contentsOf: item.appendingPathComponent("Contents/Info.plist")),
                  let info = (try? PropertyListSerialization.propertyList(
                      from: data, format: nil)) as? [String: Any],
                  // 우리와 같은 앱인가. 다른 앱을 받아 제자리에 놓는 일만은 없어야 한다.
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  // 릴리즈가 말한 판과 안에 든 판이 같은가.
                  info["CFBundleShortVersionString"] as? String == version,
                  let executable = info["CFBundleExecutable"] as? String,
                  FileManager.default.isExecutableFile(
                      atPath: item.appendingPathComponent("Contents/MacOS/\(executable)").path)
            else { continue }
            return item
        }
        return nil
    }

    private static func unzip(_ archive: URL, into directory: URL) -> Bool {
        // `ditto` 를 쓴다. macOS 가 만든 압축의 속성을 그대로 풀어 주는 것이 이쪽이다.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", archive.path, directory.path]
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    // MARK: 주고받기

    private func fetch(_ url: URL, done: @escaping (Data?) -> Void) {
        let hand = { (data: Data?) in DispatchQueue.main.async { done(data) } }
        guard !url.isFileURL else { hand(try? Data(contentsOf: url)) ; return }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub 은 이름을 밝히지 않는 요청을 막는다.
        request.setValue("agent-monitor", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            hand(code == 200 ? data : nil)
        }.resume()
    }

    /// 받아서 파일로 놓는다. 받은 파일에는 격리 딱지가 붙지 않는다(실측).
    private func fetchFile(_ url: URL, into stage: URL, done: @escaping (URL?) -> Void) {
        let archive = stage.appendingPathComponent("update.zip")
        let hand = { (value: URL?) in DispatchQueue.main.async { done(value) } }
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        } catch { hand(nil) ; return }

        guard !url.isFileURL else {
            do { try FileManager.default.copyItem(at: url, to: archive) ; hand(archive) }
            catch { hand(nil) }
            return
        }
        URLSession.shared.downloadTask(with: url) { temporary, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let temporary else { hand(nil) ; return }
            do { try FileManager.default.moveItem(at: temporary, to: archive) ; hand(archive) }
            catch { hand(nil) }
        }.resume()
    }

    // MARK: 셈과 알림

    /// `v0.6.0` · `0.6.0-beta` 처럼 적힌 것에서 숫자만 꺼낸다.
    static func number(from tag: String) -> String {
        let body = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return body.split(separator: "-").first.map(String.init) ?? body
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for slot in 0..<max(new.count, old.count) {
            let a = slot < new.count ? new[slot] : 0
            let b = slot < old.count ? old[slot] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func parse(_ data: Data) -> Release? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let page = (obj["html_url"] as? String).flatMap(Self.resolve),
              let assets = obj["assets"] as? [[String: Any]]
        else { return nil }

        let archive = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        guard let text = archive?["browser_download_url"] as? String,
              let url = Self.resolve(text) else { return nil }
        return Release(version: Self.number(from: tag), pageURL: page, archiveURL: url)
    }

    /// 갈아 끼우지 못했을 때. **조용히 지나가지 않는다** — 대신 손으로 받을 길을 연다.
    private func failed(_ reason: String, release: Release) {
        status = reason
        let alert = NSAlert()
        alert.messageText = S.updateFailedTitle
        alert.informativeText = reason
        alert.addButton(withTitle: S.updateOpenPage)
        alert.addButton(withTitle: S.updateLater)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
    }
}

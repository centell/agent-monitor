import Foundation

/// 애드온 번들을 찾아 읽고, 판이 맞는 것만 꽂는다.
///
/// ## 왜 판부터 묻는가
///
/// 번들은 이 앱의 타입(`Session` · `SessionSource`)에 **직접 대고** 지어진다. 그래서 그
/// 타입이 바뀐 뒤에 옛 번들을 물리면 **아무 말 없이 앱이 죽는다** — 실측에서 SIGBUS 로
/// 끝났고 오류 한 줄 안 남았다. 늘어난 요구에 기본 구현을 달아 줘도 마찬가지였다.
///
/// 죽는 자리는 번들을 «부를 때» 이므로, **부르기 전에** 물어볼 길이 하나 필요하다. 그것이
/// `plugin_contract_version` 이다 — C 함수라 Swift 타입이 하나도 안 끼고, 그래서 타입이
/// 어긋난 번들에게도 안전하게 물어볼 수 있다. 판이 다르면 `plugin_install` 은 안 부른다.
///
/// 조용한 죽음을 **소리 나는 거절**로 바꾸는 것이 이 파일이 하는 일의 절반이다.
///
/// ## 이름은 왜 Info.plist 에서 읽나
///
/// 판이 안 맞는 번들은 코드를 한 줄도 안 부른다. 그런데 **그때야말로 이름이 필요하다** —
/// 「무엇이 안 맞는지」를 말해 줘야 하니까. 그래서 사람에게 보일 이름은 실행 없이 읽히는
/// Info.plist 에 두고, 안전을 가르는 판 번호만 코드에서 받는다.
///
/// 판 번호를 Info.plist 에 두지 않는 것은 **적혀 있는 것과 지어진 것이 어긋날 수 있기**
/// 때문이다. 코드에서 받은 값은 그 코드와 같은 소스에서 나온다.
enum AddonLoader {

    /// 번들 하나를 읽어 본 결과.
    struct Entry {
        enum State {
            /// 꽂혔다.
            case loaded
            /// 판이 안 맞아 안 불렀다. (번들이 말한 판)
            case contractMismatch(Int32)
            /// 규약을 안 지킨다 — 물어볼 자리가 없다.
            case notAnAddon
            /// 열지 못했다. (까닭)
            case unreadable(String)
            /// 방금 놓였다. 이 판이 켜질 때는 없었으므로 아직 안 꽂혔다.
            ///
            /// **번들은 한 번 꽂으면 못 뺀다** — `dlclose` 로 Swift 런타임에 올라간
            /// 메타데이터까지 되돌릴 수는 없다. 그래서 넣고 빼는 것은 다시 켜는 것으로 마친다.
            case pendingRestart
        }

        /// 파일 이름에서 확장자를 뗀 것. **설치·삭제가 이 이름으로 이뤄진다.**
        let id: String
        /// 사람에게 보일 이름. Info.plist 가 없으면 `id` 를 쓴다.
        let name: String
        /// 애드온이 스스로 매긴 판. 표시용이고 안전에는 안 쓴다.
        let version: String?
        let url: URL
        let state: State

        /// 이 애드온이 낸 설정 화면들.
        ///
        /// **등록부는 익명이다** — `Addon.settingsTabs` 는 그냥 배열이라 「이 탭이 누구
        /// 것인가」가 안 적혀 있다. 그래서 꽂는 쪽(여기)이 `plugin_install()` 앞뒤로 길이를
        /// 재서, 그 사이에 늘어난 몫을 이 번들 것으로 적는다.
        ///
        /// 애드온 쪽 규약을 안 바꾸는 길이라 **계약 판을 안 올려도 된다.** 물어볼 자리를
        /// 하나 더 만들었다면 이미 판 애드온이 전부 그 자리를 비운 채가 됐을 것이다.
        var settingsTabs: [Addon.SettingsTab] = []
    }

    /// 읽어 본 것 전부. 꽂힌 것도 못 꽂은 것도 함께 있다 —
    /// **못 꽂은 것을 안 보여 주면 조용히 실패한 것과 같다.**
    private(set) static var entries: [Entry] = []

    /// 어디서 찾는가.
    ///
    /// 환경변수로 갈아끼울 수 있게 둔다 — 진짜 애드온 폴더를 안 더럽히고 재보기 위해서다.
    /// 이 프로젝트가 이미 여러 곳에서 쓰는 방식과 같다 (`AGENT_MONITOR_WORK_DIR` ·
    /// `AGENT_MONITOR_UPDATE_FEED`).
    static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["AGENT_MONITOR_ADDON_DIR"],
           !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("AgentMonitor/Addons")
    }

    // MARK: 꽂기

    /// 폴더를 훑어 판이 맞는 번들을 전부 꽂는다. 앱이 켜질 때 한 번 부른다.
    ///
    /// **두 번 불러도 되게 짜지 않았다.** 등록부는 더하기만 하므로 두 번 부르면 같은 것이
    /// 두 번 꽂힌다. 번들은 내린 뒤 다시 꽂을 수 없으므로 (`dlclose` 로 Swift 런타임의
    /// 메타데이터까지 되돌릴 수는 없다) 설치·삭제는 **다시 켜는 것으로** 마친다.
    static func loadAll() {
        entries = []
        let fm = FileManager.default
        guard let found = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) else {
            // 폴더가 아예 없는 것은 **고장이 아니다.** 애드온 없는 판이 정상이다.
            return
        }

        for url in found.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension == "bundle" {
            entries.append(load(url))
        }
        Addon.isActive = entries.contains { if case .loaded = $0.state { return true } else { return false } }
    }

    /// 번들을 **실행하지 않고** 겉을 읽는다. Info.plist 만 보므로 판이 어긋난 번들에도
    /// 안전하고, 아직 안 꽂힌 번들의 이름을 목록에 적을 때도 쓴다.
    static func describe(_ url: URL, state: Entry.State) -> Entry {
        let id = url.deletingPathExtension().lastPathComponent
        let info = Bundle(url: url)?.infoDictionary
        return Entry(id: id,
                     name: (info?["CFBundleName"] as? String) ?? id,
                     version: info?["CFBundleShortVersionString"] as? String,
                     url: url, state: state)
    }

    /// 폴더에 지금 놓여 있는 번들 전부. **꽂지 않는다** — 목록을 다시 그릴 때만 쓴다.
    static func onDisk() -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return found.filter { $0.pathExtension == "bundle" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func load(_ url: URL) -> Entry {
        let bundle = Bundle(url: url)

        func entry(_ state: Entry.State) -> Entry { describe(url, state: state) }

        guard let executable = bundle?.executableURL else {
            return entry(.unreadable(S.addonNoExecutable))
        }
        guard let handle = dlopen(executable.path, RTLD_NOW | RTLD_LOCAL) else {
            let why = dlerror().map { String(cString: $0) } ?? S.addonUnknownError
            return entry(.unreadable(hostTooOld(why) ? S.addonHostTooOld : shorten(why)))
        }

        // **판부터.** 이 심볼이 없으면 우리 규약을 안 지키는 것이므로 더 건드리지 않는다.
        guard let versionSymbol = dlsym(handle, "plugin_contract_version") else {
            return entry(.notAnAddon)
        }
        typealias VersionFn = @convention(c) () -> Int32
        let theirs = unsafeBitCast(versionSymbol, to: VersionFn.self)()
        guard theirs == Addon.contractVersion else {
            // 여기서 돌아서는 것이 이 파일의 존재 이유다. 한 걸음 더 가면 조용히 죽는다.
            return entry(.contractMismatch(theirs))
        }

        guard let installSymbol = dlsym(handle, "plugin_install") else {
            return entry(.notAnAddon)
        }
        typealias InstallFn = @convention(c) () -> Void
        let tabsBefore = Addon.settingsTabs.count
        unsafeBitCast(installSymbol, to: InstallFn.self)()

        var loaded = entry(.loaded)
        // 이 부름 사이에 늘어난 것이 이 번들 몫이다. **순서에 기대는 셈이라** 번들을
        // 한 번에 하나씩 꽂는 동안에만 맞는다 — `loadAll` 이 차례로 도는 것이 그 전제다.
        if Addon.settingsTabs.count > tabsBefore {
            loaded.settingsTabs = Array(Addon.settingsTabs[tabsBefore...])
        }
        return loaded
    }

    /// `dlerror` 가 내놓는 글을 사람이 읽을 크기로 줄인다.
    ///
    /// 그대로 두면 **여섯 줄짜리 탐색 경로 목록**이 나온다 — 같은 경로를 여섯 번 적고
    /// 그때마다 같은 까닭을 되뇐다. 설정창의 한 줄에 그것이 들어가면 읽을 수 있는 것이
    /// 하나도 없다. 쓸모 있는 것은 괄호 안의 까닭 하나뿐이다.
    ///
    /// 못 알아볼 모양이면 **자르지 않고 그대로 둔다.** 줄이려다 까닭까지 지우면
    /// 고치려는 사람이 아무 실마리도 못 받는다.
    /// `dlopen` 이 «심볼 없음» 으로 거절했으면 그 뜻을 사람 말로 옮긴다.
    ///
    /// **판 검사로는 이걸 못 잡는다.** 판을 물어보려면 먼저 열어야 하는데, 이 경우는
    /// 여는 그 자리에서 막힌다. 그래서 잡는 자리가 «묻기 전» 이 아니라 «못 연 뒤» 다.
    ///
    /// 뜻은 하나뿐이다 — **번들이 이 앱에 없는 자리를 찾고 있다.** 즉 애드온이 더 새것이고
    /// 앱이 옛것이다. 날것의 dyld 글에는 그 말이 한 마디도 안 적혀 있다.
    private static func hostTooOld(_ message: String) -> Bool {
        message.contains("Symbol not found") && message.contains("AgentMonitor")
    }

    private static func shorten(_ message: String) -> String {
        guard let triedAt = message.range(of: " tried:") else { return message }
        let head = String(message[message.startIndex..<triedAt.lowerBound])
        // 괄호 안의 까닭들 중 «no such file» 이 아닌 첫 번째. 그것이 진짜 걸린 자리다.
        let reasons = message.components(separatedBy: "' (").dropFirst()
            .compactMap { $0.split(separator: ")").first.map(String.init) }
        let real = reasons.first { $0 != "no such file" } ?? reasons.first
        return real.map { "\(head) — \($0)" } ?? head
    }

    // MARK: 설치와 삭제

    enum InstallError: Error {
        case notFound
        case notABundle
        case unpackFailed
        case copyFailed(String)
    }

    /// 손에 있는 번들(또는 그것을 담은 zip)을 애드온 폴더에 놓는다.
    ///
    /// **덮어쓰기를 막지 않는다.** 같은 이름이 이미 있으면 갈아 끼우는 것이 맞다 —
    /// 그것이 「업데이트」다. 다만 지우기 전에 옆에 물려 두고, 새것을 놓지 못하면 도로
    /// 돌려놓는다. 업데이트가 가진 것을 없애는 일만은 없어야 한다.
    @discardableResult
    static func install(from source: URL) throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw InstallError.notFound }

        let stage = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AgentMonitor-addon-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }

        let bundle: URL
        if source.pathExtension == "bundle" {
            bundle = source
        } else if source.pathExtension == "zip" {
            try? fm.createDirectory(at: stage, withIntermediateDirectories: true)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            task.arguments = ["-x", "-k", source.path, stage.path]
            try? task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { throw InstallError.unpackFailed }
            let items = (try? fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])) ?? []
            guard let found = items.first(where: { $0.pathExtension == "bundle" }) else {
                throw InstallError.notABundle
            }
            bundle = found
        } else {
            throw InstallError.notABundle
        }

        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(bundle.lastPathComponent)
        let backup = stage.appendingPathComponent("previous.bundle")

        let hadPrevious = fm.fileExists(atPath: destination.path)
        if hadPrevious {
            try? fm.createDirectory(at: stage, withIntermediateDirectories: true)
            try? fm.removeItem(at: backup)
            do { try fm.moveItem(at: destination, to: backup) }
            catch { throw InstallError.copyFailed(error.localizedDescription) }
        }
        do {
            try fm.copyItem(at: bundle, to: destination)
        } catch {
            // 새것을 못 놓았으면 옛것을 도로 놓는다.
            if hadPrevious { try? fm.moveItem(at: backup, to: destination) }
            throw InstallError.copyFailed(error.localizedDescription)
        }
        return destination.deletingPathExtension().lastPathComponent
    }

    /// 꽂힌 번들을 지운다. **애드온이 남긴 자료는 건드리지 않는다.**
    ///
    /// 지우는 쪽이 부르는 자리(`main.swift` · 설정 탭)에서 그 사실을 말해 준다 —
    /// 다시 꽂으면 그대로 돌아온다는 뜻이고, 정말 지우려면 따로 말해야 한다는 뜻이다.
    @discardableResult
    static func remove(_ id: String) -> Bool {
        let target = directory.appendingPathComponent("\(id).bundle")
        guard FileManager.default.fileExists(atPath: target.path) else { return false }
        return (try? FileManager.default.removeItem(at: target)) != nil
    }
}

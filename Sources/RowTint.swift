import AppKit

/// 줄을 **조건별로** 가르는 색 — 어느 엔진인가, 어느 저장소에서 도는가.
///
/// 색이 이미 쓰이는 자리를 피해 **빈 자리 하나씩**을 쓴다. 겹치면 서로를 먹는다.
/// - 표식 색은 상태가 쓴다 (`SessionRowStyle.color`) — 주황·노랑·초록·청록.
/// - 줄 전체 바탕은 고정과 마우스 올림이 쓴다 (`SessionRowView`).
///
/// 그래서 엔진은 **이름 앞머리의 글자색**, 저장소는 **줄 왼쪽 끝의 세로띠**다.
/// 띠는 상태 색 계열(주황·노랑·초록·청록)을 안 쓴다 — 같은 계열이면 「급하다」로 읽힌다.
enum RowTint {

    // MARK: 엔진

    /// 앞머리 글자색 — **각자의 브랜드 색**. 모르는 엔진이면 없다 — 지어낸 색을 붙이지 않는다.
    ///
    /// - claude: Anthropic 의 테라코타 `#D97757`.
    /// - codex: OpenAI 브랜드는 흑백이라, 유일한 유채색인 ChatGPT 초록 `#10A37F`.
    ///
    /// 둘 다 상태 색과 **계열이 겹친다** (승인 대기의 주황, 작업 중의 초록). 알고 고른 것이다 —
    /// 브랜드 색이 곧바로 읽히는 값이 더 크고, 채도가 달라 나란히 두면 갈리며, 상태는
    /// 표식의 **모양**(◆○●◐)으로도 읽힌다. 겹치는 것은 계열이지 자리가 아니다.
    ///
    /// **원색 그대로는 글자로 안 읽힌다.** 로고용 색이라 옅어서, 상시 창의 밝은 회색 바탕
    /// (`#D6D8D8` 즈음) 위에서 테라코타의 명암비가 2.2:1 이었다 — 글자에는 4.5:1 이 필요하다.
    /// 그래서 색조는 두고 **밝기만 바탕에 맞춘다** — 밝은 바탕에서는 진하게(≈4.5:1),
    /// 어두운 바탕에서는 밝게.
    static func engineColor(for source: String) -> NSColor? {
        switch source {
        case "claude": return adaptive(light: 0x9C4526, dark: 0xE8967A)   // 원색 #D97757
        case "codex":  return adaptive(light: 0x086B53, dark: 0x2BC59C)   // 원색 #10A37F
        default:       return nil
        }
    }

    private static func adaptive(light: Int, dark: Int) -> NSColor {
        func rgb(_ v: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light)
        }
    }

    // MARK: 저장소

    /// 띠 색 여섯. 상태 색 계열을 뺐고, **엔진 색과 닮은 것도 뺐다** (테라코타 곁의 갈색·빨강,
    /// ChatGPT 초록 곁의 민트). 실제 화면에서 vcrm 무리의 띠가 claude 앞머리와 같은 색으로
    /// 떠서 「이 색은 엔진인가 저장소인가」가 안 갈린 적이 있다. 자리가 달라도 같은 색이면
    /// 같은 뜻으로 읽힌다.
    static let palette: [NSColor] = [
        .systemBlue, .systemPurple, .systemPink, .systemIndigo, .systemCyan, .systemGray,
    ]

    /// 목록 전체를 보고 **둘 이상 모인 저장소에만** 색을 매긴다 (세션 id → 색).
    ///
    /// 혼자인 저장소에는 띠가 없다. 보여야 하는 것은 「이 둘이 형제다」이고, 띠가 적을수록
    /// 달린 띠가 잘 보인다.
    ///
    /// 색은 **저장소 경로의 해시**로 고른다 — 세션이 들고 날 때마다 색이 바뀌면 눈이 매번
    /// 다시 배워야 한다. `hashValue` 는 실행마다 바뀌므로 쓰지 않는다. 해시가 겹치면
    /// 다음 빈 색으로 비켜 준다. 무리가 색보다 많으면 그때는 겹친다.
    ///
    /// **색은 `all` 로 정하고 띠는 `visible` 로 단다.** 상시 창은 「기다리는 것만」으로 줄을
    /// 거르는데, 걸러진 목록으로 비켜 주면 같은 저장소가 메뉴와 창에서 **다른 색**을 받는다.
    /// 그래서 비켜 주기는 늘 전체를 보고 하고, 「둘 이상인가」만 보이는 줄로 센다 —
    /// 가려진 형제 때문에 띠가 달리면 화면에서는 혼자인 줄에 띠가 붙은 것으로 보인다.
    static func groupColors(for visible: [Session], among all: [Session]) -> [String: NSColor] {
        func members(_ sessions: [Session]) -> [String: [String]] {
            var out: [String: [String]] = [:]
            for session in sessions {
                guard let key = repoKey(for: session.cwd) else { continue }
                out[key, default: []].append(session.id)
            }
            return out.filter { $0.value.count >= 2 }
        }
        var slot: [String: Int] = [:]
        var taken = Set<Int>()
        // 비켜 주는 차례가 늘 같도록 경로 순으로 돈다.
        for key in members(all).keys.sorted() {
            var index = Int(fnv1a(key) % UInt64(palette.count))
            if taken.count < palette.count {
                while taken.contains(index) { index = (index + 1) % palette.count }
            }
            taken.insert(index)
            slot[key] = index
        }
        var out: [String: NSColor] = [:]
        for (key, ids) in members(visible) {
            guard let index = slot[key] else { continue }
            for id in ids { out[id] = palette[index] }
        }
        return out
    }

    /// 이 디렉토리가 속한 **저장소**. worktree 는 본 저장소로 모인다.
    ///
    /// git 을 부르지 않고 `.git` 을 거슬러 올라가며 읽는다 — 목록을 그릴 때마다
    /// 프로세스를 띄울 까닭이 없다. 한 번 구한 값은 붙잡아 둔다.
    /// 저장소 밖이면 디렉토리 그 자체가 열쇠다. 디렉토리가 없는 줄(앱 스레드)은 없다.
    static func repoKey(for cwd: String) -> String? {
        guard !cwd.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[cwd] { return hit }
        let key = findRepo(from: cwd) ?? cwd
        cache[cwd] = key
        return key
    }

    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    private static func findRepo(from cwd: String) -> String? {
        let fm = FileManager.default
        // 링크를 풀어 둔다. `/tmp` 와 `/private/tmp` 처럼 같은 곳이 두 이름으로 오면 안 묶인다.
        var dir = URL(fileURLWithPath: cwd).resolvingSymlinksInPath()
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                if isDir.boolValue { return dotGit.path }
                return commonDir(fromGitFile: dotGit) ?? dotGit.path
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    /// worktree 의 `.git` 은 파일이다 — `gitdir: <본저장소>/.git/worktrees/<이름>`.
    /// 그 안의 `commondir` 이 본 저장소의 `.git` 을 가리킨다. 서브모듈에는 `commondir` 이
    /// 없으므로 gitdir 자체가 열쇠가 된다 (본 저장소와 따로 묶인다).
    private static func commonDir(fromGitFile file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        let raw = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let gitDir = URL(fileURLWithPath: raw, relativeTo: file.deletingLastPathComponent())
            .standardizedFileURL
        let commonFile = gitDir.appendingPathComponent("commondir")
        guard let common = try? String(contentsOf: commonFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !common.isEmpty
        else { return gitDir.path }
        return URL(fileURLWithPath: common, relativeTo: gitDir.appendingPathComponent(""))
            .standardizedFileURL.path
    }

    /// 실행마다 같은 값을 내는 해시.
    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

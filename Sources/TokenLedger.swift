import Foundation

// MARK: - 셈

/// 기록에 적힌 `usage` 를 이 앱이 쓰는 세 값으로 옮긴다.
///
/// 출처마다 적는 이름이 달라 여기 한 곳에 모아 둔다. 각 출처에 흩어 두면 「캐시
/// 재사용분을 어느 쪽에 넣었더라」를 파일마다 다시 읽어야 한다.
enum TokenMath {

    private static func count(_ any: Any?) -> UInt64 {
        guard let n = any as? NSNumber else { return 0 }
        let v = n.int64Value
        return v > 0 ? UInt64(v) : 0
    }

    /// Claude 가 턴마다 적는 `message.usage` 한 덩어리.
    ///
    /// `input_tokens` 는 **캐시를 뺀 새 입력만** 센다 (실측: input 2 · cache_read 580,989).
    /// 그래서 셋을 더해야 그 턴이 실제로 들고 간 컨텍스트가 된다.
    ///
    /// 컨텍스트에 `output_tokens` 는 넣지 않는다. **그 요청이 들고 들어간 양**이지 답을
    /// 받은 뒤의 양이 아니다 — 그만큼(대개 1% 안쪽) 적게 나온다. codex 가 적어 두는
    /// `last_token_usage.input_tokens` 와 같은 뜻이라, 두 출처가 같은 것을 가리킨다.
    static func claude(usage: [String: Any]) -> (fresh: UInt64, total: UInt64, context: UInt64) {
        let input = count(usage["input_tokens"])
        let created = count(usage["cache_creation_input_tokens"])
        let read = count(usage["cache_read_input_tokens"])
        let output = count(usage["output_tokens"])
        return (fresh: input + created + output,
                total: input + created + output + read,
                context: input + created + read)
    }

    /// codex 가 `token_count` 이벤트에 적는 누적 덩어리.
    ///
    /// Claude 와 **세는 법이 반대**다 — codex 의 `input_tokens` 는 캐시 재사용분을
    /// **품고 있다** (실측: input 1,340,177 중 cached 1,285,120, total_tokens 는
    /// input + output = 1,348,736). 그래서 빼야 «새로 태운 것» 이 나온다.
    /// **0 은 내지 않는다.** 이벤트는 있는데 숫자가 비어 있는 판을 만나면 «태운 게 없다»가
    /// 아니라 «못 읽었다»가 맞다. 0 을 내면 그 아래 DB 값으로 메우는 길도 함께 막힌다.
    static func codex(totalUsage: [String: Any]) -> (fresh: UInt64?, total: UInt64?) {
        let input = count(totalUsage["input_tokens"])
        let cached = count(totalUsage["cached_input_tokens"])
        let output = count(totalUsage["output_tokens"])
        let fresh = (input > cached ? input - cached : 0) + output
        let total = count(totalUsage["total_tokens"])
        let resolved = total > 0 ? total : input + output
        return (fresh: fresh > 0 ? fresh : nil, total: resolved > 0 ? resolved : nil)
    }

    /// codex 가 턴마다 적는 `token_count` 이벤트의 `info` 를 통째로 옮긴다.
    ///
    /// 컨텍스트로는 **직전 요청 한 번의 입력**을 쓴다. 캐시 재사용분을 품은 값이라
    /// 그 자체가 「그 요청이 들고 간 컨텍스트」다 (실측 63,248 중 62,208 이 캐시).
    /// Claude 쪽에서 셋을 더해 만든 값과 같은 뜻이 된다.
    static func codexUsage(info: [String: Any]) -> TokenUsage {
        var usage = TokenUsage()
        if let cumulative = info["total_token_usage"] as? [String: Any] {
            let sums = codex(totalUsage: cumulative)
            usage.fresh = sums.fresh
            usage.total = sums.total
        }
        if let last = info["last_token_usage"] as? [String: Any] {
            let input = count(last["input_tokens"])
            usage.context = input > 0 ? input : nil
        }
        return usage
    }

    /// codex rollout 꼬리에서 마지막 `token_count` 이벤트를 찾아 옮긴다.
    ///
    /// codex 는 턴마다 «지금까지 얼마나 썼나» 를 통째로 다시 적으므로 끝에서 처음
    /// 만나는 것 하나면 된다 — Claude 처럼 더해 갈 일이 없다.
    static func codexUsage(inTail text: String) -> TokenUsage {
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("token_count"),
                  let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  obj["type"] as? String == "event_msg",
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any]
            else { continue }
            return codexUsage(info: info)
        }
        return TokenUsage()
    }
}

// MARK: - 원장

/// Claude 기록을 훑어 **세션이 지금까지 태운 토큰**을 셈해 들고 있는다.
///
/// codex 는 누적을 스스로 적어 두지만 Claude 는 턴마다의 `usage` 만 적는다. 그래서
/// 누적을 알려면 기록을 통째로 훑어야 하는데, 기록은 수십 MB 까지 큰다(실측 68MB).
/// 갱신마다 다시 훑을 수는 없으므로 **어디까지 읽었는지와 그때까지의 합**을 들고
/// 다음에는 늘어난 부분만 읽는다.
///
/// 훑는 값은 생각보다 싸다 — `"usage"` 가 없는 줄은 JSON 으로 풀지 않으므로 68MB 를
/// 처음 훑는 데 0.15초였다. 그래도 세션 수만큼 곱해지는 값이라, 화면에서 끄면
/// 아예 돌지 않게 `enabled` 로 잠가 둔다.
final class TokenLedger {

    static let shared = TokenLedger()

    /// 문이 둘이다. **값이 다른 두 가지를 한 스위치로 묶지 않는다.**
    ///
    /// · `countsCumulative` — Claude 기록을 **통째로 훑을** 것인가. 비싼 쪽이라 `TOK`
    ///   스위치에만 달린다. `CTX` 만 켠 사람에게 68MB 훑기를 물리지 않는다.
    /// · `wantsTokens` — 토큰 때문에 **없던 파일을 열** 것인가. codex 앱 스레드의
    ///   rollout 이 여기 달렸다 (그쪽은 컨텍스트도 그 파일에 있어서 `CTX` 에도 걸린다).
    ///
    /// 둘 다 `--json` 에서는 켠다 — 기계가 읽는 값이 사람의 손잡이에 흔들리면 안 된다.
    var countsCumulative = false
    var wantsTokens = false

    private struct Entry {
        /// 여기까지 세었다 (바이트).
        var offset: UInt64
        var fresh: UInt64
        var total: UInt64
        /// 마지막으로 센 요청의 id.
        ///
        /// **한 메시지가 여러 줄로 적히는데 줄마다 같은 `usage` 가 붙는다** (실측:
        /// `usage` 가 달린 466줄이 실제로는 메시지 246개). 그대로 더하면 1.9배로
        /// 부푼다. 겹치는 줄은 언제나 서로 붙어 있어서(비인접 중복 0건) 직전 것
        /// 하나만 기억하면 걸러진다 — 본 것을 모두 들고 있을 필요가 없다.
        var lastRequestID: String?
        /// 지금까지 센 요청 수. **0 과 «모름» 을 가르는 값이다** — 한 번도 못 셌으면
        /// 합이 0 인 것이 아니라 우리가 읽어 내지 못한 것이므로 숫자를 내지 않는다.
        var counted: Int
        /// 마지막으로 본 **본선** 턴의 컨텍스트.
        ///
        /// 훑는 김에 함께 들고 있는다. 꼬리 64KB 만으로는 못 구할 때가 있어서다 —
        /// 서브에이전트를 오래 돌리면 그 줄이 창을 가득 채워 본선 턴이 밖으로 밀려난다
        /// (실측: 그런 세션에서 꼬리 안에 본선 `usage` 가 한 줄도 없었다).
        /// 그때 이 값이 없으면 켜 둔 칸이 «—» 로 깜빡인다.
        var lastContext: UInt64?
    }

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    /// 줄을 JSON 으로 풀기 전에 거르는 표식.
    private static let marker = Data("\"usage\"".utf8)
    private static let newline = UInt8(0x0A)

    /// **이 세션이 태운 것 전부** — 본 기록과 서브에이전트 기록들을 합친다.
    ///
    /// 서브에이전트는 본 기록 안에 섞여 있지 않다. `<세션id>/subagents/agent-*.jsonl` 로
    /// 옆에 따로 산다 (실측: 기록 22,833개를 훑어 `isSidechain:true` 가 본 기록에는
    /// 한 줄도 없고 전부 그 폴더 안에 있었다). 그래서 본 기록만 세면 **빠진다** —
    /// 실측 세션들에서 서브에이전트 몫이 1~33%였고, 팬아웃한 세션은 3분의 1이었다.
    ///
    /// 컨텍스트는 본 기록에서만 가져온다. 서브에이전트는 제 컨텍스트를 따로 쓴다.
    func session(transcript url: URL) -> (fresh: UInt64, total: UInt64, context: UInt64?)? {
        let main = totals(of: url)
        var fresh = main?.fresh ?? 0
        var total = main?.total ?? 0
        var any = main != nil

        for helper in Self.subagentTranscripts(besides: url) {
            guard let part = totals(of: helper) else { continue }
            fresh += part.fresh
            total += part.total
            any = true
        }
        return any ? (fresh, total, main?.context) : nil
    }

    /// 이 기록 옆에 있는 서브에이전트 기록들. 없으면 빈 목록이다.
    ///
    /// 폴더를 손댄 시각이 그대로면 지난번 목록을 그대로 쓴다. 이 목록이 달라지는 것은
    /// 파일이 **생기거나 없어질** 때뿐이고 그때는 폴더의 시각이 함께 움직인다. 이미 있는
    /// 파일이 길어지는 것은 목록을 바꾸지 않으며, 그 늘어난 몫은 어차피 `totals(of:)` 가
    /// 파일마다 따로 이어 센다 — 그래서 여기를 막아도 숫자는 안 멈춘다.
    private static let folderLock = NSLock()
    private static var folders: [String: (modified: Date, files: [URL])] = [:]

    private static func subagentTranscripts(besides url: URL) -> [URL] {
        let folder = url.deletingPathExtension().appendingPathComponent("subagents")
        let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate

        folderLock.lock() ; defer { folderLock.unlock() }
        if let modified, let remembered = folders[folder.path], remembered.modified == modified {
            return remembered.files
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { folders[folder.path] = nil ; return [] }

        let out = files.filter { $0.pathExtension == "jsonl" }
        if let modified { folders[folder.path] = (modified, out) }
        return out
    }

    /// 파일 하나의 누적과, 훑으며 함께 본 본선 컨텍스트. 못 읽었거나 꺼져 있으면 없다.
    func totals(of url: URL) -> (fresh: UInt64, total: UInt64, context: UInt64?)? {
        guard countsCumulative else { return nil }
        lock.lock()
        defer { lock.unlock() }

        let key = url.standardizedFileURL.path
        var entry = entries[key] ?? Entry(offset: 0, fresh: 0, total: 0,
                                          lastRequestID: nil, counted: 0, lastContext: nil)

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }

        // 파일이 **줄었으면** 우리가 세던 그 파일이 아니다. 이어 세면 남의 줄을 우리
        // 합에 얹게 되므로 처음부터 다시 센다.
        //
        // 잡는 것은 여기까지다 — 같은 경로에 **더 큰** 파일이 들어앉으면 못 알아챈다.
        // 기록은 세션 id 로 이름이 붙고 뒤에 덧붙기만 하므로 그런 일이 없다고 보는 것인데,
        // 아니게 되는 날이 오면 여기에 inode 를 함께 봐야 한다.
        if size < entry.offset {
            entry = Entry(offset: 0, fresh: 0, total: 0,
                          lastRequestID: nil, counted: 0, lastContext: nil)
        }

        if size > entry.offset {
            try? handle.seek(toOffset: entry.offset)
            if let data = try? handle.readToEnd(), !data.isEmpty {
                consume(data, into: &entry)
            }
        }

        entries[key] = entry
        // 한 줄도 못 셌으면 숫자를 내지 않는다. 0 을 내면 「이 세션은 아무것도 안 태웠다」가
        // 되는데, 그건 우리가 읽어 내지 못했다는 말과 완전히 다른 주장이다.
        guard entry.counted > 0 else { return nil }
        return (entry.fresh, entry.total, entry.lastContext)
    }

    /// 읽어 온 조각을 센다.
    ///
    /// **마지막 줄바꿈까지만** 센다. 그 뒤는 지금 쓰이고 있는 반 토막일 수 있고,
    /// 반 토막을 세면 그 턴이 통째로 빠지거나 다음 갱신에 두 번 세어진다.
    private func consume(_ data: Data, into entry: inout Entry) {
        guard let lastNewline = data.lastIndex(of: Self.newline) else { return }
        let complete = data[data.startIndex...lastNewline]

        for line in complete.split(separator: Self.newline, omittingEmptySubsequences: true) {
            guard line.range(of: Self.marker) != nil,
                  let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            // 같은 요청이 여러 줄로 적힌 것은 한 번만 센다.
            //
            // id 를 못 찾은 줄에서는 **직전 id 를 지우지 않는다.** 지우면 그 다음에 오는
            // 진짜 중복이 비교할 상대를 잃고 통과한다 — 걸러야 할 것을 세게 된다.
            if let id = obj["requestId"] as? String ?? message["id"] as? String {
                if id == entry.lastRequestID { continue }
                entry.lastRequestID = id
            }

            // 서브에이전트도 «이 세션이 시켜서 태운 것»이라 빼지 않는다. 지금 판에서는
            // 옆 폴더의 제 파일로 오므로 여기서 걸러낼 줄 자체가 없지만, 본 기록에 섞어
            // 적던 판(`isSidechain`)에서도 세도록 아래 갈래를 남겨 둔다.
            let sums = TokenMath.claude(usage: usage)
            entry.fresh += sums.fresh
            entry.total += sums.total
            entry.counted += 1
            // 컨텍스트는 본선만. 서브에이전트는 제 컨텍스트를 따로 쓴다.
            if obj["isSidechain"] as? Bool != true { entry.lastContext = sums.context }
        }

        entry.offset += UInt64(complete.count)
    }
}

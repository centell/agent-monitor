import CoreGraphics
import Foundation

/// 쓰임새를 기록한다 — 「세션을 몇 개까지 감당하는가」에 답하기 위한 재료.
///
/// **왜 기록하나.** 이 앱은 매 초 「몇 개가 나를 기다리는가」를 재면서 아무 데도 쌓지
/// 않는다. 그런데 「지금 너무 많이 띄운 것인가」는 지금 이 순간을 봐서는 답이 안 나오고
/// 며칠치를 봐야 나온다. 그래서 쌓는다.
///
/// **무엇으로 답하나.** 세션은 `busy`·`shell` 일 때만 일하고 `waiting`·`idle` 이면
/// 사람을 기다린다. 그리고 사람은 하나다. 창구가 하나인 줄서기이므로, 줄이 얼마나 길었나
/// (`q0`·`q1`·`q2plus`) 와 손이 얼마나 비었나만 알면 방향이 나온다.
///
/// **자리 비움을 빼는 것이 뼈대다.** 두 시간 자리를 비우면 모든 세션이 `idle` 로 쌓여
/// 「심하게 밀림」처럼 보이지만 실제로는 아무 일도 없었다. 그래서 마지막 입력 시각을 보고
/// **사람이 앞에 있던 표본만** 센다. 이 구분이 없으면 이 통계는 통째로 거짓말이 된다.
///
/// 재는 것과 판정하는 것은 나눈다. 여기서는 숫자만 남기고 「몇 개가 맞다」는 말은 하지
/// 않는다 — 그 문턱은 쌓인 것을 보고 정할 일이지 미리 지어낼 일이 아니다.
final class StatsRecorder {

    /// 사람이 앞에 있다고 보는 한계. 마지막 입력이 이보다 오래됐으면 자리 비움으로 친다.
    static let presenceWindow: TimeInterval = 300

    /// 한 표본에 인정하는 최대 시간. 맥이 잠들었다 깨면 표본 간격이 몇 시간이 되는데,
    /// 그 시간을 그대로 «기다린 시간» 으로 세면 하룻밤이 대기 기록이 된다.
    private let maxCredit: TimeInterval = 30

    private let directory: URL
    private let fm = FileManager.default

    private var lastSample: Date?
    private var pending: [String: Wait] = [:]      // sessionId → 진행 중인 대기
    private var bucket: Bucket?                    // 아직 안 적은 1분치
    private var lastSweep: Date?

    /// 사람이 앞에 있는가. 시험에서 갈아 끼울 수 있게 밖에서 받는다 —
    /// 실제 입력 시각에 매여 있으면 「자리 비움을 빼는가」를 시험할 방법이 없다.
    private let isPresent: () -> Bool

    init(directory: URL? = nil, isPresent: (() -> Bool)? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        self.isPresent = isPresent ?? {
            StatsRecorder.secondsSinceLastInput() < StatsRecorder.presenceWindow
        }
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("AgentMonitor/stats")
    }

    // MARK: 받아 적기

    /// 한 표본. 메뉴바 앱의 갱신 주기마다 불린다.
    ///
    /// 일회성 실행(`--list` 등)은 부르지 않는다 — 한 번 훑고 죽는 쪽이 기록하면
    /// 표본 간격이 뒤죽박죽이 되고, 그 간격이 곧 시간의 단위이므로 통계가 어긋난다.
    func record(sessions: [Session], memory: SystemMemory?, now: Date = Date()) {
        let elapsed = lastSample.map { min(now.timeIntervalSince($0), maxCredit) } ?? 0
        lastSample = now
        let present = isPresent()

        // 진행 중인 대기를 잇거나, 끝난 것을 내보낸다.
        var alive = Set<String>()
        for session in sessions {
            alive.insert(session.id)
            let waiting = session.state.needsAttention

            if var open = pending[session.id] {
                if !waiting || open.state != session.state.raw {
                    // 상태가 바뀌었으면 거기서 한 번의 대기가 끝난 것이다.
                    flush(open, end: now)
                    pending[session.id] = nil
                } else {
                    open.seconds += elapsed
                    if present { open.presentSeconds += elapsed }
                    pending[session.id] = open
                    continue
                }
            }
            if waiting {
                pending[session.id] = Wait(sessionID: session.id,
                                           name: session.name,
                                           source: session.sourceTag,
                                           state: session.state.raw,
                                           start: now,
                                           seconds: 0,
                                           presentSeconds: 0)
            }
        }
        // 사라진 세션의 대기도 그 자리에서 끝난 것으로 적는다. 안 그러면 껐다 켤 때마다
        // 가장 긴 대기가 통째로 사라져, 남는 것은 짧은 대기뿐인 낙관적인 기록이 된다.
        for (id, open) in pending where !alive.contains(id) {
            flush(open, end: now)
            pending[id] = nil
        }

        accumulate(sessions: sessions, memory: memory, present: present, now: now)
        sweepOldFiles(now: now)
    }

    /// 앱이 내려갈 때 진행 중인 것을 적는다.
    func finish(now: Date = Date()) {
        for (id, open) in pending {
            flush(open, end: now)
            pending[id] = nil
        }
        if let bucket { write(bucket) ; self.bucket = nil }
    }

    // MARK: 대기 한 번

    /// 대기 한 번.
    ///
    /// 길이는 표본을 세어 쌓으므로 **한 표본만큼 짧게 잡힌다**(갱신 주기, 기본 2초).
    /// 대기가 시작된 진짜 순간은 두 표본 사이 어딘가인데, 그 몫을 얹으면 최대 한 주기를
    /// 부풀리게 된다. 짧게 잡는 쪽을 골랐다 — 5분짜리 대기에서 오차 2초다.
    private struct Wait {
        let sessionID: String
        let name: String
        let source: String
        let state: String
        let start: Date
        var seconds: Double
        /// 그중 사람이 앞에 있던 시간. 자리를 비운 동안의 대기는 병목이 아니다.
        var presentSeconds: Double
    }

    private func flush(_ wait: Wait, end: Date) {
        // 한 표본에도 못 미치는 것은 적지 않는다. 상태가 스쳐 지나간 것이지 기다린 것이 아니다.
        guard wait.seconds >= 1 else { return }
        let row = [
            Self.iso(wait.start),
            Self.iso(end),
            String(format: "%.0f", wait.seconds),
            String(format: "%.0f", wait.presentSeconds),
            wait.state,
            wait.source,
            wait.sessionID,
            Self.csvSafe(wait.name),
        ].joined(separator: ",")
        append(row, to: "waits", header: Self.waitsHeader, day: end)
    }

    static let waitsHeader = "start,end,seconds,presentSeconds,state,source,sessionId,name"

    // MARK: 1분치 묶음

    /// 1분 동안의 표본을 모아 한 줄로 줄인다.
    ///
    /// 표본 하나하나를 적으면 하루 4만 줄이 되는데, 답해야 할 물음(줄이 얼마나 길었나)에는
    /// 그만한 해상도가 필요 없다. 다만 **줄 길이 분포는 평균에서 되살릴 수 없으므로**
    /// 여기서 세어 둔다 — 평균 1.0 은 「늘 하나」와 「없음과 둘이 반반」을 구별하지 못한다.
    private struct Bucket {
        let minute: Date
        var samples = 0
        var presentSamples = 0
        var total = 0.0, waiting = 0.0, idle = 0.0, busy = 0.0, shell = 0.0
        var maxTotal = 0
        var q0 = 0, q1 = 0, q2plus = 0
        var agentBytes = 0.0
        var agentPeak: UInt64 = 0
        var systemUsed = 0.0, swap = 0.0
    }

    private func accumulate(sessions: [Session], memory: SystemMemory?,
                            present: Bool, now: Date) {
        let minute = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        if let current = bucket, current.minute != minute {
            write(current)
            bucket = nil
        }
        var current = bucket ?? Bucket(minute: minute)
        current.samples += 1

        // 자리를 비운 표본은 세지 않는다. 개수·줄 길이·램 전부 사람이 앞에 있던 동안의 것이다.
        if present {
            let queue = sessions.attentionCount
            current.presentSamples += 1
            current.total += Double(sessions.count)
            current.waiting += Double(sessions.filter { $0.state == .waiting }.count)
            current.idle += Double(sessions.filter { $0.state == .idle }.count)
            current.busy += Double(sessions.filter { $0.state == .busy }.count)
            current.shell += Double(sessions.filter { $0.state == .shell }.count)
            current.maxTotal = max(current.maxTotal, sessions.count)
            switch queue {
            case 0:  current.q0 += 1
            case 1:  current.q1 += 1
            default: current.q2plus += 1
            }
            let agent = sessions.compactMap { $0.metrics?.memoryBytes }.reduce(0, +)
            current.agentBytes += Double(agent)
            current.agentPeak = max(current.agentPeak, agent)
            current.systemUsed += Double(memory?.usedBytes ?? 0)
            current.swap += Double(memory?.swapUsedBytes ?? 0)
        }
        bucket = current
    }

    static let loadHeader = "minute,samples,presentSamples,total,waiting,idle,busy,shell,"
        + "maxTotal,q0,q1,q2plus,agentBytes,agentPeakBytes,systemUsedBytes,swapBytes"

    private func write(_ bucket: Bucket) {
        // 아무도 앞에 없던 1분은 적지 않는다. 빈 줄로 남겨 두면 나중에 평균을 낼 때
        // 0 이 섞여 들어가 «세션이 없었다» 로 읽힌다.
        guard bucket.presentSamples > 0 else { return }
        let n = Double(bucket.presentSamples)
        func mean(_ sum: Double) -> String { String(format: "%.2f", sum / n) }
        let row = [
            Self.iso(bucket.minute),
            String(bucket.samples),
            String(bucket.presentSamples),
            mean(bucket.total), mean(bucket.waiting), mean(bucket.idle),
            mean(bucket.busy), mean(bucket.shell),
            String(bucket.maxTotal),
            String(bucket.q0), String(bucket.q1), String(bucket.q2plus),
            String(format: "%.0f", bucket.agentBytes / n),
            String(bucket.agentPeak),
            String(format: "%.0f", bucket.systemUsed / n),
            String(format: "%.0f", bucket.swap / n),
        ].joined(separator: ",")
        append(row, to: "load", header: Self.loadHeader, day: bucket.minute)
    }

    // MARK: 파일

    /// 하루에 한 파일. 오래된 것을 지우는 일이 파일 지우기 하나로 끝난다.
    static func file(in directory: URL, kind: String, day: Date) -> URL {
        directory.appendingPathComponent("\(kind)-\(dayStamp(day)).csv")
    }

    private func append(_ row: String, to kind: String, header: String, day: Date) {
        let url = Self.file(in: directory, kind: kind, day: day)
        do {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                try (header + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((row + "\n").utf8))
        } catch {
            // 기록에 실패해도 앱은 계속 돈다. 통계는 곁다리이고, 이것 때문에 목록이
            // 멈추면 본래 하려던 일을 잃는다.
        }
    }

    /// 보관 기간이 지난 파일을 지운다. 하루에 한 번만 훑는다.
    private func sweepOldFiles(now: Date, keepDays: Int = 30) {
        if let last = lastSweep, now.timeIntervalSince(last) < 3600 { return }
        lastSweep = now
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) else { return }
        let cutoff = Self.dayStamp(now.addingTimeInterval(-Double(keepDays) * 86400))
        for file in files where file.pathExtension == "csv" {
            // 이름이 `<종류>-YYYY-MM-DD.csv` 이므로 날짜 부분을 글자로 견주면 된다.
            let stamp = file.deletingPathExtension().lastPathComponent.suffix(10)
            if String(stamp) < cutoff { try? fm.removeItem(at: file) }
        }
    }

    // MARK: 도우미

    /// 마지막 입력 이후 흐른 시간. 권한이 필요 없고 잠긴 화면·잠자기도 그대로 쌓인다.
    static func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 쉼표와 줄바꿈을 걷어낸다. 세션 이름은 사람이 붙이는 것이라 무엇이든 들어올 수 있다.
    static func csvSafe(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: "·")
            .split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

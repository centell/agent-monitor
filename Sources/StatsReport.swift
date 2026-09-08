import Foundation

/// 쌓아 둔 기록을 읽어 몇 개의 숫자로 줄인다.
///
/// **판정하지 않는다.** 「몇 개가 맞다」는 말은 여기서 내지 않는다. 그 문턱은 실제로 쌓인
/// 것을 보고 정할 일이고, 아직 아무것도 안 쌓인 채로 정하면 그건 통계가 아니라 상상이다.
/// 지금은 재료만 낸다 — 줄이 얼마나 섰나, 손이 얼마나 비었나, 램을 얼마나 먹었나.
///
/// 모든 값은 **주인님이 앞에 계셨던 시간** 기준이다. 자리 비움이 섞이면 며칠을 쌓아도
/// 「늘 밀려 있음」밖에 안 나온다.
struct StatsReport {

    /// 기록이 실제로 있는 날 수. 「7일치를 봤다」와 「7일 중 이틀만 있다」는 다른 말이다.
    let dataDays: Int
    let presentHours: Double

    let meanSessions: Double
    let maxSessions: Int
    /// 그중 실제로 돌던 것 (`busy` + `shell`).
    let meanRunning: Double

    /// 나를 기다리던 세션 수의 분포. 손이 빈 시간 · 하나가 기다린 시간 · 줄이 선 시간.
    let queueNone: Double
    let queueOne: Double
    let queueMany: Double

    let waitCount: Int
    let waitMedian: Double
    let waitLongest: Double
    let waitTotal: Double
    /// 자리를 비운 동안 쌓인 것까지 더한 값. 병목은 아니지만 흐른 시간이긴 하다.
    let waitTotalIncludingAway: Double

    let agentMeanBytes: UInt64
    let agentPeakBytes: UInt64
    let swapMeanBytes: UInt64

    // MARK: 짓기

    static func build(directory: URL = StatsRecorder.defaultDirectory,
                      days: Int = 7,
                      now: Date = Date()) -> StatsReport? {
        let stamps = (0..<days).map { StatsRecorder.dayStamp(now.addingTimeInterval(-Double($0) * 86400)) }

        var presentMinutes = 0.0
        var weight = 0.0                       // 표본 수로 잰 무게
        var totalSum = 0.0, runningSum = 0.0
        var maxSessions = 0
        var q0 = 0.0, q1 = 0.0, q2 = 0.0
        var agentSum = 0.0, agentPeak: UInt64 = 0, swapSum = 0.0
        var dataDays = 0

        for stamp in stamps {
            let url = directory.appendingPathComponent("load-\(stamp).csv")
            guard let rows = readRows(url) else { continue }
            dataDays += 1
            for row in rows where row.count >= 16 {
                guard let samples = Double(row[1]), samples > 0,
                      let present = Double(row[2]), present > 0 else { continue }
                presentMinutes += present / samples
                weight += present
                totalSum += (Double(row[3]) ?? 0) * present
                runningSum += ((Double(row[6]) ?? 0) + (Double(row[7]) ?? 0)) * present
                maxSessions = max(maxSessions, Int(row[8]) ?? 0)
                q0 += Double(row[9]) ?? 0
                q1 += Double(row[10]) ?? 0
                q2 += Double(row[11]) ?? 0
                agentSum += (Double(row[12]) ?? 0) * present
                agentPeak = max(agentPeak, UInt64(row[13]) ?? 0)
                swapSum += (Double(row[15]) ?? 0) * present
            }
        }

        var present: [Double] = []
        var rawTotal = 0.0
        for stamp in stamps {
            let url = directory.appendingPathComponent("waits-\(stamp).csv")
            guard let rows = readRows(url) else { continue }
            for row in rows where row.count >= 8 {
                rawTotal += Double(row[2]) ?? 0
                // 자리를 비운 동안의 대기는 세지 않는다 — 아무도 기다리게 하지 않았다.
                if let seconds = Double(row[3]), seconds >= 1 { present.append(seconds) }
            }
        }

        guard weight > 0 || !present.isEmpty else { return nil }
        let queueTotal = max(q0 + q1 + q2, 1)
        let sorted = present.sorted()

        return StatsReport(
            dataDays: dataDays,
            presentHours: presentMinutes / 60,
            meanSessions: weight > 0 ? totalSum / weight : 0,
            maxSessions: maxSessions,
            meanRunning: weight > 0 ? runningSum / weight : 0,
            queueNone: q0 / queueTotal,
            queueOne: q1 / queueTotal,
            queueMany: q2 / queueTotal,
            waitCount: sorted.count,
            waitMedian: sorted.isEmpty ? 0 : sorted[sorted.count / 2],
            waitLongest: sorted.last ?? 0,
            waitTotal: sorted.reduce(0, +),
            waitTotalIncludingAway: rawTotal,
            agentMeanBytes: weight > 0 ? UInt64(agentSum / weight) : 0,
            agentPeakBytes: agentPeak,
            swapMeanBytes: weight > 0 ? UInt64(swapSum / weight) : 0
        )
    }

    /// 기록 파일이 하나라도 있는가.
    ///
    /// 「아무것도 없음」과 「쌓이고는 있는데 앞에 계셨던 시간이 아직 없음」은 다른 말이다.
    /// 가르지 않으면, 자리를 비운 동안 처음 열어 본 사람에게 고장으로 읽힌다.
    static func hasRecords(directory: URL = StatsRecorder.defaultDirectory,
                           days: Int = 7, now: Date = Date()) -> Bool {
        (0..<days).contains { offset in
            let stamp = StatsRecorder.dayStamp(now.addingTimeInterval(-Double(offset) * 86400))
            return FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("load-\(stamp).csv").path)
        }
    }

    /// 머리글을 뺀 줄들을 칸으로 갈라 돌려준다. 파일이 없으면 없다.
    private static func readRows(_ url: URL) -> [[String]]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline)
            .dropFirst()
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    }
}

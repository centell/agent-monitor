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

    /// 한 무리의 표본을 담는 그릇. 전체·시간대별·요일별이 같은 셈을 쓴다.
    ///
    /// 무게는 **앞에 계셨던 표본 수**다. 1분 줄마다 표본 수가 다를 수 있어(앱을 켠 첫 분,
    /// 자리를 뜬 분) 줄 수로 세면 짧은 분이 긴 분과 같은 무게를 갖는다.
    struct Bin {
        var weight = 0.0
        var presentMinutes = 0.0
        var sessions = 0.0
        var running = 0.0
        var maxSessions = 0
        var q0 = 0.0, q1 = 0.0, q2 = 0.0
        var agent = 0.0
        var agentPeak: UInt64 = 0
        var swap = 0.0

        var presentHours: Double { presentMinutes / 60 }
        var meanSessions: Double { weight > 0 ? sessions / weight : 0 }
        var meanRunning: Double { weight > 0 ? running / weight : 0 }
        var queueNone: Double { ratio(q0) }
        var queueOne: Double { ratio(q1) }
        var queueMany: Double { ratio(q2) }
        var meanAgentBytes: UInt64 { weight > 0 ? UInt64(agent / weight) : 0 }
        var meanSwapBytes: UInt64 { weight > 0 ? UInt64(swap / weight) : 0 }

        private func ratio(_ part: Double) -> Double {
            let all = q0 + q1 + q2
            return all > 0 ? part / all : 0
        }

        mutating func add(_ row: [String], present: Double, samples: Double) {
            weight += present
            presentMinutes += present / samples
            sessions += (Double(row[3]) ?? 0) * present
            running += ((Double(row[6]) ?? 0) + (Double(row[7]) ?? 0)) * present
            maxSessions = max(maxSessions, Int(row[8]) ?? 0)
            q0 += Double(row[9]) ?? 0
            q1 += Double(row[10]) ?? 0
            q2 += Double(row[11]) ?? 0
            agent += (Double(row[12]) ?? 0) * present
            agentPeak = max(agentPeak, UInt64(row[13]) ?? 0)
            swap += (Double(row[15]) ?? 0) * present
        }
    }

    /// 시간대나 요일 한 칸.
    struct Slice {
        /// 0~23 시각, 또는 `Calendar` 의 요일(1=일).
        let key: Int
        let bin: Bin
    }

    /// 기록이 실제로 있는 날 수. 「7일치를 봤다」와 「7일 중 이틀만 있다」는 다른 말이다.
    let dataDays: Int
    let overall: Bin

    /// 시간대별·요일별. 표본이 있는 칸만 담기며 시각·요일 순으로 정렬되어 있다.
    ///
    /// 이 두 갈래가 필요한 이유는 「앞에 있음」이 「일하는 중」과 같지 않아서다. 슬랙을 하거나
    /// 회의 중 노트북만 켜 두어도 입력은 있으므로 앞에 있는 것으로 잡힌다. 그 시간의 긴 대기는
    /// 세션을 많이 띄운 탓이 아닌데 전체 평균에는 섞여 든다.
    /// 시간대로 갈라 보면 **작동은 낮은데 줄만 긴 칸**으로 그런 시간이 드러난다.
    let byHour: [Slice]
    let byWeekday: [Slice]

    let waitCount: Int
    let waitMedian: Double
    let waitLongest: Double
    let waitTotal: Double
    /// 자리를 비운 동안 쌓인 것까지 더한 값. 병목은 아니지만 흐른 시간이긴 하다.
    let waitTotalIncludingAway: Double

    // MARK: 짓기

    static func build(directory: URL = StatsRecorder.defaultDirectory,
                      days: Int = 7,
                      now: Date = Date()) -> StatsReport? {
        let stamps = (0..<days).map { StatsRecorder.dayStamp(now.addingTimeInterval(-Double($0) * 86400)) }
        let parser = ISO8601DateFormatter()
        var calendar = Calendar.current
        calendar.timeZone = .current

        var overall = Bin()
        var hours: [Int: Bin] = [:]
        var weekdays: [Int: Bin] = [:]
        var dataDays = 0

        for stamp in stamps {
            guard let rows = readRows(directory.appendingPathComponent("load-\(stamp).csv")) else { continue }
            dataDays += 1
            for row in rows where row.count >= 16 {
                guard let samples = Double(row[1]), samples > 0,
                      let present = Double(row[2]), present > 0 else { continue }
                overall.add(row, present: present, samples: samples)
                // 기록은 UTC 로 적히므로 **현지 시각으로 바꿔** 나눈다. 시간대별로 보는 뜻이
                // 「몇 시에 그랬나」인데, UTC 로 묶으면 사람이 사는 시각과 어긋난다.
                guard let minute = parser.date(from: row[0]) else { continue }
                let parts = calendar.dateComponents([.hour, .weekday], from: minute)
                if let hour = parts.hour {
                    hours[hour, default: Bin()].add(row, present: present, samples: samples)
                }
                if let weekday = parts.weekday {
                    weekdays[weekday, default: Bin()].add(row, present: present, samples: samples)
                }
            }
        }

        var present: [Double] = []
        var rawTotal = 0.0
        for stamp in stamps {
            guard let rows = readRows(directory.appendingPathComponent("waits-\(stamp).csv")) else { continue }
            for row in rows where row.count >= 8 {
                rawTotal += Double(row[2]) ?? 0
                // 자리를 비운 동안의 대기는 세지 않는다 — 아무도 기다리게 하지 않았다.
                if let seconds = Double(row[3]), seconds >= 1 { present.append(seconds) }
            }
        }

        guard overall.weight > 0 || !present.isEmpty else { return nil }
        let sorted = present.sorted()

        return StatsReport(
            dataDays: dataDays,
            overall: overall,
            byHour: hours.keys.sorted().map { Slice(key: $0, bin: hours[$0]!) },
            byWeekday: weekdays.keys.sorted().map { Slice(key: $0, bin: weekdays[$0]!) },
            waitCount: sorted.count,
            waitMedian: sorted.isEmpty ? 0 : sorted[sorted.count / 2],
            waitLongest: sorted.last ?? 0,
            waitTotal: sorted.reduce(0, +),
            waitTotalIncludingAway: rawTotal
        )
    }

    /// 「지금 쌓이고 있나」에 답하는 값.
    ///
    /// 통계 자체와 물음이 다르다. 이쪽은 습관이 아니라 **장치가 살아 있는지**를 보는 것이라,
    /// 오늘 얼마나 쌓였는지와 마지막으로 적힌 때만 있으면 된다.
    struct Liveness {
        let minutesToday: Double
        let lastRecord: Date?
    }

    static func liveness(directory: URL = StatsRecorder.defaultDirectory,
                         now: Date = Date()) -> Liveness {
        let stamp = StatsRecorder.dayStamp(now)
        guard let rows = readRows(directory.appendingPathComponent("load-\(stamp).csv")) else {
            return Liveness(minutesToday: 0, lastRecord: nil)
        }
        let parser = ISO8601DateFormatter()
        var minutes = 0.0
        var last: Date?
        for row in rows where row.count >= 16 {
            guard let samples = Double(row[1]), samples > 0,
                  let present = Double(row[2]), present > 0 else { continue }
            minutes += present / samples
            if let minute = parser.date(from: row[0]) { last = minute }
        }
        return Liveness(minutesToday: minutes, lastRecord: last)
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

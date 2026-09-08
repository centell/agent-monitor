import AppKit
import SwiftUI

/// 쌓인 쓰임새를 보는 화면.
///
/// 한 화면이 물음 둘에 답한다. 맨 위는 **「지금 쌓이고 있나」** 로, 장치가 살아 있는지만
/// 본다 — 이건 한눈에 끝나야 하는 확인이다. 그 아래는 **「그래서 내 습관이 어떤가」** 로,
/// 들여다보는 자리다. 새로고침이 잦을 이유도 앞쪽에만 있다.
///
/// 숫자는 `--stats` 와 같은 코드(`StatsReport`)에서 나온다. 화면용으로 따로 세면
/// 둘이 어긋나는 날이 오고, 그때 어느 쪽이 맞는지 아무도 모르게 된다.
struct StatsView: View {

    @ObservedObject private var settings = Settings.shared
    @State private var report: StatsReport?
    @State private var liveness = StatsReport.Liveness(minutesToday: 0, lastRecord: nil)
    @State private var now = Date()

    /// 기록은 1분에 한 줄이므로 그보다 자주 읽을 이유가 없다.
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                livenessBox

                if let report {
                    summaryBox(report)
                    if !report.byHour.isEmpty {
                        sliceBox(S.statsByHour, S.statsColHour, report.byHour, label: S.hourLabel)
                    }
                    if !report.byWeekday.isEmpty {
                        sliceBox(S.statsByWeekday, S.statsColWeekday, report.byWeekday,
                                 label: S.weekdayLabel)
                    }
                } else {
                    Text(StatsReport.hasRecords() ? S.statsAwayOnly : S.statsNoData)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(S.statsFootnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { refresh() }
        .onReceive(tick) { _ in refresh() }
    }

    // MARK: 기록 상태

    private var livenessBox: some View {
        GroupBox(S.statsLiveness) {
            VStack(alignment: .leading, spacing: 6) {
                if settings.recordStats {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(S.statsToday(Int(liveness.minutesToday.rounded())))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text("·").foregroundStyle(.tertiary)
                        Text(S.statsLastRecord(liveness.lastRecord.map { now.timeIntervalSince($0) }))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // 꺼 두신 것을 화면이 말해 주지 않으면, 안 쌓이는 것을 고장으로 읽으신다.
                    Text(S.statsRecordingOff)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button(S.statsOpenFolder) {
                        let directory = StatsRecorder.defaultDirectory
                        try? FileManager.default.createDirectory(at: directory,
                                                                 withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    }
                    .controlSize(.small)
                    Text(S.statsRetention)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 요약

    private func summaryBox(_ report: StatsReport) -> some View {
        let all = report.overall
        return GroupBox(S.statsRecent) {
            VStack(alignment: .leading, spacing: 4) {
                Text(S.statsHeader(days: 7, dataDays: report.dataDays, hours: all.presentHours))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
                row(S.statsSessions, S.statsMeanMax(all.meanSessions, all.maxSessions))
                row(S.statsRunning, S.statsMean(all.meanRunning))
                row(S.statsQueue, S.statsQueueSplit(none: all.queueNone,
                                                    one: all.queueOne,
                                                    many: all.queueMany))
                row(S.statsWaits, S.statsWaitSplit(median: report.waitMedian,
                                                   longest: report.waitLongest,
                                                   total: report.waitTotal,
                                                   count: report.waitCount))
                row(S.statsMemory, S.statsMemorySplit(mean: MetricFormat.size(all.meanAgentBytes),
                                                      peak: MetricFormat.size(all.agentPeak),
                                                      swap: MetricFormat.size(all.meanSwapBytes)))
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .frame(width: 132, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: 시간대·요일

    /// 표본이 이보다 적은 칸은 빼고 몇 칸을 뺐는지 밝힌다.
    /// 2분짜리 칸의 「100%」는 습관이 아니라 우연이다.
    private static let thinFloor = 5.0

    private func sliceBox(_ title: String, _ column: String,
                          _ slices: [StatsReport.Slice],
                          label: @escaping (Int) -> String) -> some View {
        let shown = slices.filter { $0.bin.presentMinutes >= Self.thinFloor }
        let thin = slices.count - shown.count
        return GroupBox(title) {
            VStack(alignment: .leading, spacing: 3) {
                sliceRow(column, S.statsColPresent, S.statsColSessions,
                         S.statsColRunning, S.statsColQueueMany, header: true)
                ForEach(shown, id: \.key) { slice in
                    sliceRow(label(slice.key),
                             String(format: "%.1fh", slice.bin.presentHours),
                             String(format: "%.1f", slice.bin.meanSessions),
                             String(format: "%.1f", slice.bin.meanRunning),
                             "\(Int((slice.bin.queueMany * 100).rounded()))%",
                             ratio: slice.bin.queueMany)
                }
                if thin > 0 {
                    Text(S.statsThinNote(thin, minutes: Int(Self.thinFloor)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 한 줄. 마지막 칸 뒤에 막대를 둔다.
    ///
    /// 막대가 재는 것은 «줄이 둘 이상이던 시간» 하나뿐이다. 다섯 칸을 다 그리면 눈이
    /// 무엇을 봐야 할지 잃는다 — 여기서 찾는 것은 **길게 밀린 시간대**이므로 그것만 그린다.
    private func sliceRow(_ when: String, _ present: String, _ sessions: String,
                          _ running: String, _ queue: String,
                          header: Bool = false, ratio: Double = 0) -> some View {
        let font = Font.system(size: 12, weight: header ? .semibold : .regular, design: .monospaced)
        return HStack(spacing: 6) {
            // 어느 칸도 접히지 않게 한 줄로 못 박고, 폭은 두 언어의 머리글이 다 들어가게 잡는다.
            Text(when).font(font).lineLimit(1).frame(width: 50, alignment: .leading)
            Text(present).font(font).lineLimit(1).frame(width: 66, alignment: .trailing)
            Text(sessions).font(font).lineLimit(1).frame(width: 46, alignment: .trailing)
            Text(running).font(font).lineLimit(1).frame(width: 54, alignment: .trailing)
            Text(queue).font(font).lineLimit(1).frame(width: 62, alignment: .trailing)
            if header {
                Spacer(minLength: 0)
            } else {
                // 막대는 자리를 늘 차지한다. 있다 없다 하면 줄마다 폭이 흔들린다.
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 120, height: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.55))
                        .frame(width: max(2, 120 * ratio), height: 8)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(header ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }

    // MARK: 읽기

    private func refresh() {
        now = Date()
        liveness = StatsReport.liveness(now: now)
        report = StatsReport.build(now: now)
    }
}

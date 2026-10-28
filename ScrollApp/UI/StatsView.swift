import Charts
import SwiftUI

private enum StatsRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 days"
    case month = "30 days"
    case all = "All time"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .all: return nil
        }
    }

    var phrase: String {
        switch self {
        case .today: return "scrolled today"
        case .week: return "scrolled in the last 7 days"
        case .month: return "scrolled in the last 30 days"
        case .all: return "scrolled in total"
        }
    }
}

private struct Totals {
    var watchMs: Int64 = 0
    var videos = 0
    var adsSkipped = 0
}

struct StatsView: View {
    @EnvironmentObject private var stats: StatsStore
    let onBack: () -> Void
    @State private var range: StatsRange = .week
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Your scrolling", onBack: onBack) {
                Button { confirmReset = true } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }
                .tint(Ink.secondary)
                .accessibilityLabel("Reset statistics")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    let totals = totalsByPlatform()
                    Hero(totals: Array(totals.values), phrase: range.phrase)

                    SectionLabel("By source")
                    Card {
                        ForEach(Array(Platform.allCases.enumerated()), id: \.element) { i, platform in
                            if i > 0 { CardDivider() }
                            SourceRow(platform: platform, totals: totals[platform] ?? Totals())
                        }
                    }

                    let chartDays = range == .month || range == .all ? 30 : 7
                    SectionLabel("Watch time, last \(chartDays) days")
                    Card { DailyChart(rows: stats.rows, days: chartDays) }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Ink.page.ignoresSafeArea())
        .alert("Reset statistics?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { stats.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all watch time, video counts and skipped-ad counts.")
        }
    }

    private func totalsByPlatform() -> [Platform: Totals] {
        let from = range.days.map { StatsStore.dayKey(for: Calendar.current.date(byAdding: .day, value: 1 - $0, to: Date()) ?? Date()) }
        var totals: [Platform: Totals] = [:]
        for row in stats.rows where from == nil || row.day >= from! {
            var t = totals[row.platform] ?? Totals()
            t.watchMs += row.watchMs
            t.videos += row.videos
            t.adsSkipped += row.adsSkipped
            totals[row.platform] = t
        }
        return totals
    }
}

private struct Hero: View {
    let totals: [Totals]
    let phrase: String

    var body: some View {
        let videos = totals.reduce(0) { $0 + $1.videos }
        let ads = totals.reduce(0) { $0 + $1.adsSkipped }
        VStack(alignment: .leading, spacing: 2) {
            Text(formatDuration(ms: totals.reduce(0) { $0 + $1.watchMs }))
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(Ink.primary)
            Text(phrase).foregroundStyle(Ink.secondary)
            Text("\(plural(videos, "video")) · \(plural(ads, "ad")) skipped")
                .foregroundStyle(Ink.secondary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

private struct SourceRow: View {
    let platform: Platform
    let totals: Totals

    var body: some View {
        HStack(spacing: 12) {
            Dot(color: platform.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.title).foregroundStyle(Ink.primary)
                Text(totals.videos > 0 ? "about \(formatDuration(ms: totals.watchMs / Int64(totals.videos))) each" : "nothing yet")
                    .font(.footnote)
                    .foregroundStyle(Ink.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totals.videos) \(platform.itemNoun)")
                    .fontWeight(.medium)
                    .foregroundStyle(Ink.primary)
                Text(formatDuration(ms: totals.watchMs))
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
        }
    }
}

/// One stacked segment: a source's minutes on one day, drawn from low to high.
private struct Segment: Identifiable {
    let id: String
    let date: Date
    let platform: Platform
    let low: Double
    let high: Double
    let isTop: Bool
}

/// Stacked minutes per day, one segment per source in fixed order from the baseline, with a small
/// gap between segments and only the data end rounded.
private struct DailyChart: View {
    let rows: [DayStat]
    let days: Int
    @State private var selected: Date?
    @State private var showTable = false

    private static let plotHeight: CGFloat = 190

    var body: some View {
        let dates = lastDays()
        let minutes = dates.map { minutesByPlatform(on: $0) }
        let maxTotal = minutes.map { $0.reduce(0, +) }.max() ?? 0

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ForEach(Platform.allCases) { platform in
                    HStack(spacing: 6) {
                        Dot(color: platform.color, size: 8)
                        Text(platform.shortName).font(.footnote).foregroundStyle(Ink.secondary)
                    }
                }
            }

            if maxTotal <= 0 {
                Text("No watch time in these days yet.").font(.subheadline).foregroundStyle(Ink.muted)
            } else {
                let scale = niceScale(maxTotal)
                chart(dates: dates, minutes: minutes, top: scale.top, step: scale.step)
                detail(dates: dates, minutes: minutes)
                Button(showTable ? "Hide table" : "Show as table") { showTable.toggle() }
                    .font(.subheadline)
                if showTable { table(dates: dates, minutes: minutes) }
            }
        }
    }

    private func chart(dates: [Date], minutes: [[Double]], top: Double, step: Double) -> some View {
        let segments = stack(dates: dates, minutes: minutes, top: top)
        let ticks = Array(stride(from: 0, through: top, by: step))
        let labelled = days <= 7 ? dates : dates.enumerated().filter { (days - 1 - $0.offset) % 7 == 0 }.map(\.element)
        let selectedDay = selected.map { Calendar.current.startOfDay(for: $0) }
        let dayFormat: Date.FormatStyle = days <= 7 ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day()
        return Chart {
            if let selectedDay {
                RectangleMark(x: .value("Day", selectedDay, unit: .day))
                    .foregroundStyle(Ink.wash)
            }
            ForEach(segments) { segment in
                BarMark(
                    x: .value("Day", segment.date, unit: .day),
                    yStart: .value("From", segment.low),
                    yEnd: .value("To", segment.high),
                    width: .ratio(days <= 7 ? 0.56 : 0.66)
                )
                .foregroundStyle(segment.platform.color)
                .cornerRadius(segment.isTop ? 4 : 0)
            }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine().foregroundStyle(Ink.grid)
                AxisValueLabel {
                    if let m = value.as(Double.self) { Text(m == 0 ? "0" : formatMinutes(m)) }
                }
                .foregroundStyle(Ink.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: labelled) { _ in
                AxisValueLabel(format: dayFormat, centered: true)
                .foregroundStyle(Ink.muted)
            }
        }
        .chartXSelection(value: $selected)
        .frame(height: Self.plotHeight)
        .accessibilityLabel("Watch time per day for the last \(days) days")
    }

    @ViewBuilder
    private func detail(dates: [Date], minutes: [[Double]]) -> some View {
        if let selected, let i = dates.firstIndex(of: Calendar.current.startOfDay(for: selected)) {
            let values = minutes[i]
            VStack(alignment: .leading, spacing: 4) {
                Text("\(dates[i].formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · \(formatMinutes(values.reduce(0, +)))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ink.primary)
                HStack(spacing: 14) {
                    ForEach(Array(Platform.allCases.enumerated()), id: \.element) { p, platform in
                        HStack(spacing: 6) {
                            Dot(color: platform.color, size: 8)
                            Text("\(platform.shortName) \(formatMinutes(values[p]))")
                                .font(.footnote)
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                }
            }
        } else {
            Text("Tap a bar to see that day").font(.footnote).foregroundStyle(Ink.muted)
        }
    }

    private func table(dates: [Date], minutes: [[Double]]) -> some View {
        VStack(spacing: 0) {
            tableRow(["Day"] + Platform.allCases.map(\.shortName) + ["Total"], header: true)
            ForEach(dates.indices.reversed(), id: \.self) { i in
                Rectangle().fill(Ink.grid).frame(height: 1)
                tableRow(
                    [dates[i].formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())]
                        + minutes[i].map(formatMinutes) + [formatMinutes(minutes[i].reduce(0, +))],
                    header: false
                )
            }
        }
    }

    private func tableRow(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                Text(cell)
                    .font(.footnote)
                    .foregroundStyle(header ? Ink.muted : (i == 0 ? Ink.secondary : Ink.primary))
                    .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
                    .layoutPriority(i == 0 ? 1 : 0)
            }
        }
        .padding(.vertical, 6)
    }

    private func lastDays() -> [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }

    private func minutesByPlatform(on date: Date) -> [Double] {
        let key = StatsStore.dayKey(for: date)
        return Platform.allCases.map { platform in
            Double(rows.filter { $0.day == key && $0.platform == platform }.reduce(0) { $0 + $1.watchMs }) / 60_000
        }
    }

    private func stack(dates: [Date], minutes: [[Double]], top: Double) -> [Segment] {
        // A 2pt gap between stacked segments, expressed in minutes for this plot's scale.
        let gap = top * 2 / Double(Self.plotHeight)
        var segments: [Segment] = []
        for (i, date) in dates.enumerated() {
            let values = minutes[i]
            let lastShown = values.lastIndex { $0 > 0 }
            var y = 0.0
            for (p, value) in values.enumerated() where value > 0 {
                let low = y > 0 ? y + gap : y
                segments.append(Segment(
                    id: "\(i)-\(p)",
                    date: date,
                    platform: Platform.allCases[p],
                    low: low,
                    high: max(y + value, low + gap / 2),
                    isTop: p == lastShown
                ))
                y += value
            }
        }
        return segments
    }

    /// Axis top and gridline step, in minutes, giving at most four gridlines.
    private func niceScale(_ max: Double) -> (top: Double, step: Double) {
        let steps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 180, 240, 360, 480, 720]
        let step = steps.first { (max / $0).rounded(.up) <= 4 } ?? ((max / 4 / 60).rounded(.up) * 60)
        return ((max / step).rounded(.up) * step, step)
    }
}

private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

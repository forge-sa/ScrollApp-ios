import Foundation

/// Totals for one source on one day.
struct DayStat: Codable, Identifiable, Hashable {
    /// Local calendar day, "yyyy-MM-dd".
    var day: String
    var platform: Platform
    var watchMs: Int64 = 0
    var videos = 0
    var adsSkipped = 0

    var id: String { day + "|" + platform.rawValue }
}

/// Per-day, per-source totals, kept in a small JSON file on the phone.
@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var rows: [DayStat] = []
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("stats.json")
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([DayStat].self, from: data) {
            rows = saved
        }
    }

    func addWatchTime(_ platform: Platform, ms: Int64) { update(platform) { $0.watchMs += ms } }
    func addVideo(_ platform: Platform) { update(platform) { $0.videos += 1 } }
    func addAdSkipped(_ platform: Platform) { update(platform) { $0.adsSkipped += 1 } }

    func clear() {
        rows = []
        save()
    }

    /// Writes now; otherwise changes are written a few seconds after they happen.
    func save() {
        saveTask?.cancel()
        saveTask = nil
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func update(_ platform: Platform, _ change: (inout DayStat) -> Void) {
        let day = StatsStore.dayKey(for: Date())
        if let i = rows.firstIndex(where: { $0.day == day && $0.platform == platform }) {
            change(&rows[i])
        } else {
            var row = DayStat(day: day, platform: platform)
            change(&row)
            rows.append(row)
        }
        if saveTask == nil {
            saveTask = runAfter(3) { [weak self] in self?.save() }
        }
    }

    static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(twoDigits(c.month ?? 0))-\(twoDigits(c.day ?? 0))"
    }
}

/// Accumulates on-screen time for the source currently playing.
@MainActor
final class WatchTimer {
    private let stats: StatsStore
    private var platform: Platform?
    private var since: TimeInterval = 0

    init(stats: StatsStore) {
        self.stats = stats
    }

    func start(_ platform: Platform) {
        if self.platform == platform { return }
        stop()
        self.platform = platform
        since = uptime()
    }

    func stop() {
        checkpoint()
        platform = nil
    }

    /// Records the time so far without stopping, so a crash or kill loses at most one interval.
    func checkpoint() {
        guard let platform else { return }
        let now = uptime()
        let ms = Int64((now - since) * 1000)
        if ms > 0 { stats.addWatchTime(platform, ms: ms) }
        since = now
    }
}

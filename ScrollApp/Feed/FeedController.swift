import SwiftUI
import UIKit
import WebKit

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// The unified feed. Each platform keeps its own web view, stacked on top of each other; a swipe
/// slides the current one away to reveal the next platform's, which was already lined up on its next
/// unseen item. The feed is a history of (platform, item index) entries, so swiping back returns to
/// what was shown. Same design as the Android app's FeedController.
@MainActor
final class FeedController: ObservableObject, PlatformFeedDelegate {
    private final class Entry {
        let platform: Platform
        var index: Int
        var counted = false
        var sawVideo = false

        init(platform: Platform, index: Int) {
            self.platform = platform
            self.index = index
        }
    }

    let container: FeedContainerView

    @Published private(set) var current: Platform?
    @Published private(set) var liked: Bool?
    @Published private(set) var notice: String?
    /// Bumped on each like, to play the heart animation.
    @Published private(set) var likeBurst = 0
    /// True until the ad rules are compiled and the sources are created.
    @Published private(set) var starting = true
    @Published var shareItem: ShareItem?

    private let settings: AppSettings
    private let stats: StatsStore
    private let timer: WatchTimer
    private var rules: WKContentRuleList?
    private var feeds: [Platform: PlatformFeed] = [:]
    private var order: [Platform] = []
    private var history: [Entry] = []
    private var position = -1
    private var foreground = false
    private var covered = false
    private var animating = false
    private var peek: PlatformFeed?
    private var peekIsOver = false
    private var plannedNext: Platform?
    private var entryPlayingSince: TimeInterval = 0
    private var countTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var checkpointTask: Task<Void, Never>?

    private static let maxSkipStreak = 6
    private static let skipLabels = ["ad": "an ad", "suggested": "a suggested post", "live": "a LIVE stream"]

    private var playing: Bool { foreground && !covered }
    private var currentEntry: Entry? { history.indices.contains(position) ? history[position] : nil }
    private var currentFeed: PlatformFeed? { currentEntry.flatMap { feeds[$0.platform] } }

    init(settings: AppSettings, stats: StatsStore) {
        self.settings = settings
        self.stats = stats
        self.timer = WatchTimer(stats: stats)
        self.container = FeedContainerView(frame: .zero)

        container.onDrag = { [weak self] dy in self?.drag(dy) }
        container.onSwipe = { [weak self] direction in self?.swipe(direction) }

        checkpointTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                self.timer.checkpoint()
            }
        }
        Task { @MainActor [weak self] in
            let rules = try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: AdBlock.identifier,
                encodedContentRuleList: AdBlock.rulesJSON
            )
            guard let self else { return }
            self.rules = rules
            self.starting = false
            self.syncFeeds()
        }
    }

    // MARK: Lifecycle

    func setForeground(_ on: Bool) {
        guard foreground != on else { return }
        foreground = on
        refreshPlayback()
        if !on { stats.save() }
    }

    /// Another screen (stats, settings, login) is on top of the feed.
    func setCovered(_ on: Bool) {
        guard covered != on else { return }
        covered = on
        refreshPlayback()
    }

    private func refreshPlayback() {
        // Autoscroll keeps the feed going hands-free, so the screen must not lock mid-video.
        UIApplication.shared.isIdleTimerDisabled = playing
        guard let entry = currentEntry, let feed = feeds[entry.platform] else {
            timer.stop()
            return
        }
        if playing {
            feed.setActive(true, restart: false, sound: settings.sound)
            timer.start(entry.platform)
            scheduleEntryChecks()
        } else {
            feed.setActive(false, restart: false, sound: settings.sound)
            timer.stop()
            countTask?.cancel()
            stallTask?.cancel()
        }
    }

    // MARK: Sources

    /// Brings the set of web views in line with the enabled platforms and restarts the feed if it changed.
    func syncFeeds() {
        guard !starting else { return }
        let wanted = Platform.allCases.filter { settings.isEnabled($0) }
        guard wanted != order else { return }
        for platform in order where !wanted.contains(platform) {
            feeds.removeValue(forKey: platform)?.destroy()
        }
        for platform in wanted where feeds[platform] == nil {
            feeds[platform] = makeFeed(platform)
        }
        order = wanted
        restartFeed()
    }

    func setPlatformEnabled(_ platform: Platform, _ on: Bool) {
        settings.setEnabled(platform, on)
        syncFeeds()
    }

    func setDesktopMode(_ platform: Platform, _ on: Bool) {
        settings.setDesktop(platform, on)
        recreateFeed(platform)
    }

    /// Reloads a source from its start page, e.g. after logging in or after wandering off its feed.
    func reload(_ platform: Platform) {
        guard let feed = feeds[platform] else { return }
        forgetHistory(platform)
        feed.reload()
        if currentEntry?.platform == platform { feed.nextFresh = 1 }
    }

    private func makeFeed(_ platform: Platform) -> PlatformFeed {
        let feed = PlatformFeed(
            platform: platform,
            script: PageScript.source,
            desktop: settings.isDesktop(platform),
            rules: rules
        )
        feed.delegate = self
        container.insertSubview(feed.webView, at: 0)
        container.setNeedsLayout()
        return feed
    }

    private func recreateFeed(_ platform: Platform) {
        guard let old = feeds[platform] else { return }
        let wasCurrent = currentFeed === old
        old.destroy()
        let feed = makeFeed(platform)
        feeds[platform] = feed
        forgetHistory(platform)
        if wasCurrent {
            feed.nextFresh = 1
            stack(feed)
            feed.setActive(playing, restart: false, sound: settings.sound)
        }
    }

    /// Drops this platform's past entries: after a reload its item indices mean something else.
    private func forgetHistory(_ platform: Platform) {
        let entry = currentEntry
        history = history.filter { $0.platform != platform || $0 === entry }
        position = entry.flatMap { kept in history.firstIndex { $0 === kept } } ?? -1
        if let entry, entry.platform == platform { entry.index = 0 }
        if plannedNext == platform { plannedNext = nil }
    }

    private func restartFeed() {
        leaveEntry()
        history = []
        position = -1
        plannedNext = nil
        for feed in feeds.values {
            feed.setActive(false, restart: false, sound: settings.sound)
            feed.nextFresh = feed.position
        }
        guard !feeds.isEmpty else {
            current = nil
            return
        }
        next()
    }

    // MARK: Moving through the unified feed

    func next() {
        guard !animating else { return }
        if position + 1 >= history.count {
            guard let platform = plannedNext ?? pickNext(after: currentEntry?.platform),
                  let feed = feeds[platform] else { return }
            history.append(Entry(platform: platform, index: feed.nextFresh))
            feed.nextFresh += 1
        }
        plannedNext = nil
        move(to: position + 1, forward: true)
    }

    func previous() {
        guard !animating else { return }
        guard position > 0 else {
            settleDrag()
            return
        }
        move(to: position - 1, forward: false)
    }

    private func pickNext(after: Platform?) -> Platform? {
        let ready = order.filter { feeds[$0]?.suspended == false }
        let candidates = ready.isEmpty ? order : ready
        guard let first = candidates.first else { return nil }
        guard let after, candidates.count > 1 else { return first }
        switch settings.mixMode {
        case .shuffle:
            return candidates.filter { $0 != after }.randomElement() ?? first
        case .rotate:
            let start = order.firstIndex(of: after) ?? -1
            for step in 1...order.count {
                let platform = order[(start + step) % order.count]
                if candidates.contains(platform) { return platform }
            }
            return first
        }
    }

    private func move(to target: Int, forward: Bool) {
        let fromFeed = currentFeed
        let to = history[target]
        guard let toFeed = feeds[to.platform] else { return }
        leaveEntry()
        feedLog.debug("show #\(target) \(to.platform.rawValue, privacy: .public) item \(to.index)")
        position = target
        current = to.platform
        liked = nil
        toFeed.seek(to.index)

        if fromFeed === toFeed {
            // Same source twice in a row: the page moves itself.
            settleDrag()
            enterEntry()
            return
        }
        fromFeed?.setActive(false, restart: false, sound: settings.sound)
        animateSwap(from: fromFeed, to: toFeed, forward: forward) { [weak self] in
            guard let self else { return }
            // Line the source we left up on its next item, so it is buffered when its turn comes back.
            if forward, let fromFeed { fromFeed.seek(self.nextIndex(for: fromFeed, after: target)) }
            toFeed.setActive(self.playing, restart: true, sound: self.settings.sound)
            self.enterEntry()
        }
    }

    /// The index this feed shows next: its next entry in history, or its next unseen item.
    private func nextIndex(for feed: PlatformFeed, after: Int) -> Int {
        history.dropFirst(after + 1).first(where: { $0.platform == feed.platform })?.index ?? feed.nextFresh
    }

    private func enterEntry() {
        guard let entry = currentEntry else { return }
        container.interceptEnabled = true
        if playing {
            timer.start(entry.platform)
            scheduleEntryChecks()
        }
    }

    private func leaveEntry() {
        timer.stop()
        countTask?.cancel()
        stallTask?.cancel()
    }

    private func scheduleEntryChecks() {
        countTask?.cancel()
        stallTask?.cancel()
        entryPlayingSince = uptime()
        if currentEntry?.counted == false {
            countTask = runAfter(2) { [weak self] in self?.countVideo() }
        }
        stallTask = runAfter(2) { [weak self] in self?.checkStall() }
    }

    /// A video counts once it has been on screen for a moment (leaving time to skip ads first) and
    /// has actually played; one frozen behind a login wall does not count.
    private func countVideo() {
        guard let entry = currentEntry, playing, !entry.counted else { return }
        guard entry.sawVideo else {
            countTask = runAfter(2) { [weak self] in self?.countVideo() }
            return
        }
        entry.counted = true
        stats.addVideo(entry.platform)
    }

    /// Photo posts never end and videos behind login walls never play: move on rather than stall.
    /// A page still on its first load gets longer, unless another source is ready to show instead.
    private func checkStall() {
        guard let entry = currentEntry, let feed = feeds[entry.platform], playing, !entry.sawVideo else { return }
        let coldStart = !feed.ready && !feeds.values.contains { $0 !== feed && $0.ready }
        let limit: TimeInterval = coldStart && !feed.everPlayed ? 25 : 12
        if uptime() - entryPlayingSince < limit {
            stallTask = runAfter(2) { [weak self] in self?.checkStall() }
            return
        }
        feedLog.debug("\(entry.platform.rawValue, privacy: .public) item \(entry.index) never played, moving on")
        feed.emptyStreak += 1
        if feed.emptyStreak >= 2 && feeds.count > 1 {
            feed.suspended = true
            flash("\(entry.platform.title) isn't showing videos. Log in from Settings, then reload it.")
        }
        if settings.autoscroll || feed.suspended { next() }
    }

    // MARK: Page events

    func feed(_ feed: PlatformFeed, didUpdate state: FeedState) {
        if state.progressed {
            feed.emptyStreak = 0
            feed.suspended = false
        }
        let entry = currentEntry
        let isCurrent = entry.map { feeds[$0.platform] === feed } ?? false
        if isCurrent, let entry {
            if liked != state.liked { liked = state.liked }
            if !animating { container.interceptEnabled = !state.panelOpen }
            if state.progressed { entry.sawVideo = true }
        }
        if state.skip == nil && !feed.busy { feed.skipStreak = 0 }
        if let reason = state.skip {
            skip(feed, state: state, reason: reason, entry: isCurrent ? entry : nil)
        }
    }

    private func skip(_ feed: PlatformFeed, state: FeedState, reason: String, entry: Entry?) {
        guard settings.skipAds, !feed.busy, state.skipKey != feed.lastSkipKey,
              feed.skipStreak < Self.maxSkipStreak else { return }
        feed.lastSkipKey = state.skipKey
        if let entry, feed.position == entry.index {
            // Swap the item under the current entry for the one after it.
            for other in history where other.platform == feed.platform && other.index >= entry.index && other !== entry {
                other.index += 1
            }
            entry.index += 1
            feed.nextFresh = max(feed.nextFresh, entry.index + 1)
            feed.seek(entry.index)
            if !entry.counted { scheduleEntryChecks() }
            flash("Skipped \(Self.skipLabels[reason] ?? "an ad")")
        } else if entry == nil, feed.position == feed.nextFresh {
            // A lined-up source landed on an ad while waiting for its turn.
            feed.nextFresh += 1
            feed.seek(feed.nextFresh)
        } else {
            return
        }
        feedLog.debug("\(feed.platform.rawValue, privacy: .public) skipped \(reason, privacy: .public)")
        stats.addAdSkipped(feed.platform)
        feed.skipStreak += 1
        if feed.skipStreak == Self.maxSkipStreak {
            flash("\(feed.platform.title): too many items look like ads, so skipping is paused there.")
        }
    }

    func feedVideoEnded(_ feed: PlatformFeed) {
        guard settings.autoscroll, playing, !animating, currentFeed === feed, !feed.busy else { return }
        next()
    }

    func feedReloaded(_ feed: PlatformFeed) {
        guard feeds[feed.platform] === feed else { return }
        forgetHistory(feed.platform)
        feed.resetPosition()
        feed.nextFresh = currentEntry?.platform == feed.platform ? 1 : 0
    }

    func feedCrashed(_ feed: PlatformFeed) {
        if feeds[feed.platform] === feed { recreateFeed(feed.platform) }
    }

    // MARK: Actions

    func like() {
        guard let feed = currentFeed else { return }
        feed.press("like") { [weak self] found, wasLiked in
            guard let self else { return }
            guard found else {
                self.flash("Couldn't find the like button on this one")
                return
            }
            let nowLiked = wasLiked != true
            self.liked = nowLiked
            if nowLiked { self.likeBurst += 1 }
        }
    }

    /// Uses the site's own repost when it has one on screen, otherwise shares the link.
    func repost() {
        guard let feed = currentFeed else { return }
        feed.press("repost") { [weak self] found, _ in
            guard let self else { return }
            if found {
                self.flash("Reposted on \(feed.platform.shortName)")
            } else {
                feed.videoURL { [weak self] url in self?.shareItem = ShareItem(url: url) }
            }
        }
    }

    func toggleAutoscroll() {
        settings.autoscroll.toggle()
        flash(settings.autoscroll ? "Autoscroll on: moves on when a video ends" : "Autoscroll off")
    }

    func toggleSound() {
        settings.sound.toggle()
        for feed in feeds.values { feed.setSound(settings.sound) }
    }

    private func flash(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = runAfter(2.8) { [weak self] in self?.notice = nil }
    }

    // MARK: Drag and animation

    private func drag(_ dy: CGFloat) {
        guard !animating, let cur = currentFeed else { return }
        let h = container.bounds.height
        if dy < 0 {
            guard let nextFeed = upcomingFeed(), nextFeed !== cur else { return }
            showPeek(nextFeed, over: false, current: cur)
            cur.webView.transform = CGAffineTransform(translationX: 0, y: dy)
        } else if position > 0, let prevFeed = feeds[history[position - 1].platform] {
            cur.webView.transform = .identity
            guard prevFeed !== cur else { return }
            showPeek(prevFeed, over: true, current: cur)
            prevFeed.webView.transform = CGAffineTransform(translationX: 0, y: -h + dy)
        }
    }

    private func swipe(_ direction: Int) {
        switch direction {
        case 1: next()
        case -1: previous()
        default: settleDrag()
        }
    }

    /// The feed the next swipe will show, deciding (and remembering) the next platform if needed.
    private func upcomingFeed() -> PlatformFeed? {
        if history.indices.contains(position + 1) { return feeds[history[position + 1].platform] }
        if plannedNext == nil { plannedNext = pickNext(after: currentEntry?.platform) }
        return plannedNext.flatMap { feeds[$0] }
    }

    private func showPeek(_ feed: PlatformFeed, over: Bool, current cur: PlatformFeed) {
        if let old = peek, old !== feed {
            old.webView.transform = .identity
            container.sendSubviewToBack(old.webView)
        }
        peek = feed
        peekIsOver = over
        if over {
            container.bringSubviewToFront(feed.webView)
        } else {
            feed.webView.transform = .identity
            container.insertSubview(feed.webView, belowSubview: cur.webView)
        }
    }

    private func settleDrag() {
        guard let cur = currentFeed else { return }
        let h = container.bounds.height
        let revealed = peek
        let over = peekIsOver
        peek = nil
        UIView.animate(withDuration: 0.18, animations: {
            cur.webView.transform = .identity
            if let revealed, over { revealed.webView.transform = CGAffineTransform(translationX: 0, y: -h) }
        }, completion: { [weak self] _ in
            guard let self, !self.animating, let top = self.currentFeed else { return }
            self.stack(top)
        })
    }

    private func animateSwap(from: PlatformFeed?, to: PlatformFeed, forward: Bool, done: @escaping () -> Void) {
        let h = container.bounds.height
        let dragged = peek === to
        peek = nil
        guard let from, h > 0 else {
            stack(to)
            done()
            return
        }
        animating = true
        if forward {
            to.webView.transform = .identity
            container.insertSubview(to.webView, belowSubview: from.webView)
            UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut], animations: {
                from.webView.transform = CGAffineTransform(translationX: 0, y: -h)
            }, completion: { [weak self] _ in
                self?.finishSwap(to: to, done: done)
            })
        } else {
            if !dragged { to.webView.transform = CGAffineTransform(translationX: 0, y: -h) }
            container.bringSubviewToFront(to.webView)
            UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut], animations: {
                to.webView.transform = .identity
            }, completion: { [weak self] _ in
                self?.finishSwap(to: to, done: done)
            })
        }
    }

    private func finishSwap(to: PlatformFeed, done: () -> Void) {
        stack(to)
        animating = false
        done()
    }

    /// Puts [top] in front and every other feed flat behind it.
    private func stack(_ top: PlatformFeed) {
        for feed in feeds.values {
            feed.webView.layer.removeAllAnimations()
            feed.webView.transform = .identity
        }
        container.bringSubviewToFront(top.webView)
    }
}

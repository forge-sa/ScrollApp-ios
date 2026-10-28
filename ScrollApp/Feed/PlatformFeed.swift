import UIKit
import WebKit

/// What the page script last reported about the item on screen.
struct FeedState: Equatable {
    var id: String?
    var skipKey: String?
    var hasVideo = false
    /// The item has actually played (a video frozen behind a login wall has not).
    var progressed = false
    /// "ad", "suggested" or "live" when the item should be skipped.
    var skip: String?
    var liked: Bool?
    var panelOpen = false
}

@MainActor
protocol PlatformFeedDelegate: AnyObject {
    func feed(_ feed: PlatformFeed, didUpdate state: FeedState)
    func feedVideoEnded(_ feed: PlatformFeed)
    /// The page loaded again by itself, so it is back at its first item.
    func feedReloaded(_ feed: PlatformFeed)
    func feedCrashed(_ feed: PlatformFeed)
}

/// One platform's feed: a WKWebView on the site's own short-video feed, plus the bookkeeping that
/// maps "the Nth item of this feed" onto moves inside the page. iOS cannot send a page a real touch,
/// so the page is moved and pressed from script (see sh.nav / sh.press in the page script).
@MainActor
final class PlatformFeed: NSObject {
    let platform: Platform
    let webView: WKWebView
    weak var delegate: PlatformFeedDelegate?

    private(set) var state = FeedState()

    /// Item the page is on, counted in moves from the first one.
    private(set) var position = 0
    private var target = 0
    private var stepping = false
    private var settledAt: TimeInterval = 0
    /// Bumped on reset so moves still in flight are ignored.
    private var generation = 0

    /// First item not yet placed in the unified feed.
    var nextFresh = 0
    /// Consecutive skipped items; a runaway streak means the ad markers match normal videos.
    var skipStreak = 0
    var lastSkipKey: String?
    var emptyStreak = 0
    var suspended = false

    /// Whether anything has played since the page loaded; cold starts get longer before giving up.
    private(set) var everPlayed = false
    /// The page has shown a video, so its feed exists and can be moved.
    private(set) var ready = false
    private var loads = 0
    private var active = false
    private var sound = true

    /// True while the page is moving or has just moved, when its reports may still describe the old item.
    var busy: Bool { stepping || position != target || uptime() - settledAt < 0.7 }

    /// Appended to WebKit's user agent so sites serve the same page as Safari.
    static var safariAgentSuffix: String {
        let major = UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? "18"
        return "Version/\(major).0 Mobile/15E148 Safari/604.1"
    }

    init(platform: Platform, script: String, desktop: Bool, rules: WKContentRuleList?) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = PlatformFeed.safariAgentSuffix
        configuration.defaultWebpagePreferences.preferredContentMode = desktop ? .desktop : .mobile
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(
            source: platform.pageScript(script),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        if let rules { content.add(rules) }
        configuration.userContentController = content

        self.platform = platform
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        content.add(MessageProxy(self), name: "scrollApp")
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        // Lets Safari's Web Inspector attach, to fix selectors when sites change.
        webView.isInspectable = true
        #endif
        webView.load(URLRequest(url: platform.config.feedURL))
    }

    func reload() {
        resetPosition()
        nextFresh = 0
        skipStreak = 0
        emptyStreak = 0
        suspended = false
        everPlayed = false
        webView.load(URLRequest(url: platform.config.feedURL))
    }

    func resetPosition() {
        generation += 1
        position = 0
        target = 0
        stepping = false
        ready = false
        state = FeedState()
    }

    func destroy() {
        generation += 1
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    // MARK: Playback

    func setActive(_ on: Bool, restart: Bool, sound: Bool) {
        active = on
        self.sound = sound
        js("__sh.setActive(\(on), \(restart), \(sound))")
    }

    func setSound(_ on: Bool) {
        sound = on
        js("__sh.setSound(\(on))")
    }

    // MARK: Moving through the page's own feed

    func seek(_ index: Int) {
        target = max(0, index)
        pump()
    }

    private func pump() {
        guard !stepping, position != target else { return }
        // Nothing on screen yet (still loading, or a login wall): nowhere to move to.
        guard let before = state.id, ready else {
            target = position
            return
        }
        stepping = true
        let dir = target > position ? 1 : -1
        let started = generation
        js("__sh.nav(\(dir))")
        // Checked twice, so a slow page is not mistaken for one that ignored the move.
        runAfter(1.2) { [weak self] in
            guard let self, self.generation == started else { return }
            if self.state.id != before {
                self.finishStep(dir)
                return
            }
            runAfter(0.8) { [weak self] in
                guard let self, self.generation == started else { return }
                if self.state.id == before { feedLog.debug("\(self.platform.rawValue, privacy: .public) did not move") }
                // Moved or not, count the step rather than retry forever.
                self.finishStep(dir)
            }
        }
    }

    private func finishStep(_ dir: Int) {
        position += dir
        stepping = false
        settledAt = uptime()
        pump()
    }

    // MARK: Actions and queries

    /// Presses the site's own like or repost button from script. Reports whether it was found and,
    /// for likes, whether the video was already liked before the press.
    func press(_ kind: String, completion: @escaping (_ found: Bool, _ wasLiked: Bool?) -> Void) {
        webView.evaluateJavaScript("window.__sh ? __sh.press('\(kind)') : '{}'") { result, _ in
            guard let json = result as? String,
                  let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            else {
                completion(false, nil)
                return
            }
            completion(object["found"] as? Bool ?? false, object["liked"] as? Bool)
        }
    }

    func videoURL(_ completion: @escaping (URL) -> Void) {
        let fallback = platform.config.feedURL
        webView.evaluateJavaScript("window.__sh ? __sh.url() : location.href") { result, _ in
            completion((result as? String).flatMap(URL.init(string:)) ?? fallback)
        }
    }

    private func js(_ code: String) {
        webView.evaluateJavaScript("window.__sh && \(code)", completionHandler: nil)
    }

    // MARK: Page events

    fileprivate func receive(_ json: String) {
        guard let message = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
        switch message["t"] as? String {
        case "hello":
            // A fresh copy of the script (new page load) starts inactive; restore our state.
            js("__sh.setActive(\(active), false, \(sound))")
            loads += 1
            if loads > 1 { delegate?.feedReloaded(self) }
        case "ended":
            delegate?.feedVideoEnded(self)
        case "state":
            state = FeedState(
                id: message["id"] as? String,
                skipKey: message["skipKey"] as? String,
                hasVideo: message["video"] as? Bool ?? false,
                progressed: message["progressed"] as? Bool ?? false,
                skip: message["skip"] as? String,
                liked: message["liked"] as? Bool,
                panelOpen: message["panel"] as? Bool ?? false
            )
            if state.progressed { everPlayed = true }
            if state.hasVideo { ready = true }
            delegate?.feed(self, didUpdate: state)
        default:
            break
        }
    }
}

extension PlatformFeed: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
            // Stay on the web: drop "open in app" deep links (snssdk://, instagram://, youtube://).
            decisionHandler(.cancel)
            return
        }
        // Allow, but without handing universal links to an installed Instagram/TikTok/YouTube app
        // (WebKit's _WKNavigationActionPolicyAllowWithoutTryingAppLink).
        decisionHandler(WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        delegate?.feedCrashed(self)
    }
}

/// Holds the feed weakly: WKUserContentController retains its message handlers.
@MainActor
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var feed: PlatformFeed?

    init(_ feed: PlatformFeed) {
        self.feed = feed
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let json = message.body as? String else { return }
        feed?.receive(json)
    }
}

import SwiftUI

/// What the page script needs to know about one site. Site markup changes often: if ads stop being
/// skipped or the like button stops working, these markers and selectors are what to update.
/// Keep them in step with the Android app's Platform.kt.
struct SiteConfig {
    var feedURL: URL
    var loginURL: URL
    /// Path of a single video's page, used for sharing.
    var linkPattern: String
    /// Whole-line labels that mark an item as an ad.
    var adMarkers: [String]
    /// Labels that mark a non-video item (people suggestions, Threads posts) as filler.
    var nonVideoMarkers: [String] = []
    var adSelector = ""
    var likeSelector = ""
    var repostPattern = ""
    /// Panels (comments, share sheets) during which vertical swipes belong to the page.
    var panelSelector = ""
    /// CSS hiding promo slots that sit outside the feed items.
    var css = ""
    var skipLive = false
    /// The page has no per-video links; the id has to come from its React props.
    var videoIdInProps = false
    /// The site's own next/previous buttons, used to move its feed from script.
    var nextSelector = ""
    var prevSelector = ""
}

enum Platform: String, CaseIterable, Identifiable, Codable {
    case youtube, instagram, tiktok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .youtube: return "YouTube Shorts"
        case .instagram: return "Instagram Reels"
        case .tiktok: return "TikTok"
        }
    }

    var shortName: String {
        switch self {
        case .youtube: return "Shorts"
        case .instagram: return "Reels"
        case .tiktok: return "TikTok"
        }
    }

    /// What one item is called, plural ("shorts").
    var itemNoun: String {
        switch self {
        case .youtube: return "shorts"
        case .instagram: return "reels"
        case .tiktok: return "TikToks"
        }
    }

    /// Series color; the three were validated together for color-blind safety on the dark surface.
    var color: Color {
        switch self {
        case .youtube: return Color(hex: 0xD95926)
        case .instagram: return Color(hex: 0x9085E9)
        case .tiktok: return Color(hex: 0x199E70)
        }
    }

    var config: SiteConfig {
        switch self {
        case .youtube:
            return SiteConfig(
                feedURL: URL(string: "https://m.youtube.com/shorts/")!,
                loginURL: URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fm.youtube.com%2Fshorts%2F")!,
                linkPattern: "^/shorts/[\\w-]+",
                adMarkers: ["Sponsored", "Ad", "Реклама", "Жарнама"],
                adSelector: "ytm-ad-slot-renderer, ad-slot-renderer, ytm-promoted-sparkles-web-renderer, ytm-reel-player-ad-overlay-renderer",
                likeSelector: "ytm-like-button-renderer button, like-button-view-model button",
                panelSelector: "ytm-engagement-panel-section-list-renderer, bottom-sheet-container, .engagement-panel-container",
                css: "ytm-promoted-sparkles-web-renderer, ytm-promoted-video-renderer, ytm-companion-ad-renderer, "
                    + "ytm-mealbar-promo-renderer, ytm-statement-banner-renderer, ytm-ad-slot-renderer, ad-slot-renderer "
                    + "{ display: none !important; }",
                nextSelector: ".ytShortsCarouselShortsA11yNav button:last-of-type",
                prevSelector: ".ytShortsCarouselShortsA11yNav button:first-of-type"
            )
        case .instagram:
            return SiteConfig(
                feedURL: URL(string: "https://www.instagram.com/reels/")!,
                loginURL: URL(string: "https://www.instagram.com/accounts/login/?next=%2Freels%2F")!,
                linkPattern: "^/reels?/[\\w-]+",
                adMarkers: ["Sponsored", "Реклама", "Жарнама"],
                nonVideoMarkers: [
                    "Suggested for you", "Suggested for You", "Suggested accounts", "People you may know", "Threads",
                    "Рекомендации для вас", "Рекомендуемые аккаунты", "Возможно, вы знакомы",
                ],
                likeSelector: "svg[aria-label='Like'], svg[aria-label='Unlike'], svg[aria-label='Нравится'], svg[aria-label='Не нравится']",
                repostPattern: "^(repost|репост)"
            )
        case .tiktok:
            return SiteConfig(
                feedURL: URL(string: "https://www.tiktok.com/foryou")!,
                loginURL: URL(string: "https://www.tiktok.com/login")!,
                linkPattern: "/video/\\d+",
                adMarkers: ["Sponsored", "Ad", "Promoted", "Promotional content", "Реклама", "Жарнама"],
                nonVideoMarkers: ["Suggested accounts", "Рекомендуемые аккаунты"],
                adSelector: "[data-e2e='ad-tag'], [data-e2e='video-ad-tag']",
                likeSelector: "[data-e2e='like-icon'], [data-e2e='browse-like-icon']",
                repostPattern: "^(repost|репост)",
                panelSelector: "[data-e2e='comment-list'], [data-e2e='browse-comment-list']",
                skipLive: true,
                videoIdInProps: true
            )
        }
    }

    /// The script injected into this platform's pages: its config followed by the shared page script.
    func pageScript(_ script: String) -> String {
        let c = config
        let settings: [String: Any] = [
            "adMarkers": c.adMarkers,
            "nonVideoMarkers": c.nonVideoMarkers,
            "adSelector": c.adSelector,
            "likeSelector": c.likeSelector,
            "repostPattern": c.repostPattern,
            "panelSelector": c.panelSelector,
            "linkPattern": c.linkPattern,
            "css": c.css,
            "skipLive": c.skipLive,
            "videoIdInProps": c.videoIdInProps,
            "nextSelector": c.nextSelector,
            "prevSelector": c.prevSelector,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: settings)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "window.__shConfig = \(json);\n\(script)"
    }
}

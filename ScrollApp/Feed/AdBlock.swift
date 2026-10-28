import Foundation
import WebKit

/// Request-level blocking for ad networks, as a WebKit content rule list. Instagram and TikTok serve
/// their ads inside the normal feed responses, so those are caught on the page instead
/// (see SiteConfig.adMarkers).
enum AdBlock {
    static let identifier = "scrollapp-ads-v1"

    private static let hosts = [
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adservice.google.com",
        "imasdk.googleapis.com",
        "googletagservices.com",
        "analytics.tiktok.com",
        "an.facebook.com",
    ]
    private static let youtubePaths = ["pagead/", "api/stats/ads", "get_midroll_", "ptracking"]

    /// Content-blocker regexes support groups and quantifiers but not alternation, so one rule per pattern.
    static var rulesJSON: String {
        let hostRules = hosts.map { host in
            rule("^[^:]+:(//)?([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: host) + "[/:]")
        }
        let pathRules = youtubePaths.map { path in
            rule("^[^:]+:(//)?([^/]+\\.)?youtube\\.com/" + NSRegularExpression.escapedPattern(for: path))
        }
        let data = (try? JSONSerialization.data(withJSONObject: hostRules + pathRules)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func rule(_ urlFilter: String) -> [String: Any] {
        ["trigger": ["url-filter": urlFilter], "action": ["type": "block"]]
    }
}

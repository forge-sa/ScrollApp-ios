import Foundation

enum MixMode: String, CaseIterable, Identifiable {
    case rotate, shuffle

    var id: String { rawValue }
    var label: String { self == .rotate ? "Take turns" : "Shuffle" }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var autoscroll: Bool {
        didSet { defaults.set(autoscroll, forKey: "autoscroll") }
    }
    @Published var sound: Bool {
        didSet { defaults.set(sound, forKey: "sound") }
    }
    @Published var skipAds: Bool {
        didSet { defaults.set(skipAds, forKey: "skipAds") }
    }
    @Published var mixMode: MixMode {
        didSet { defaults.set(mixMode.rawValue, forKey: "mixMode") }
    }
    @Published var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: "onboarded") }
    }
    @Published private(set) var enabled: Set<Platform>
    /// Sources that load the desktop site, for when the mobile site refuses to show the feed.
    @Published private(set) var desktop: Set<Platform>

    init() {
        let stored = UserDefaults.standard
        stored.register(defaults: ["autoscroll": true, "sound": true, "skipAds": true, "onboarded": false])
        autoscroll = stored.bool(forKey: "autoscroll")
        sound = stored.bool(forKey: "sound")
        skipAds = stored.bool(forKey: "skipAds")
        onboarded = stored.bool(forKey: "onboarded")
        mixMode = MixMode(rawValue: stored.string(forKey: "mixMode") ?? "") ?? .rotate
        let enabledNames = stored.stringArray(forKey: "enabled") ?? Platform.allCases.map(\.rawValue)
        enabled = Set(enabledNames.compactMap(Platform.init(rawValue:)))
        desktop = Set((stored.stringArray(forKey: "desktop") ?? []).compactMap(Platform.init(rawValue:)))
    }

    func isEnabled(_ platform: Platform) -> Bool { enabled.contains(platform) }

    func setEnabled(_ platform: Platform, _ on: Bool) {
        if on { enabled.insert(platform) } else { enabled.remove(platform) }
        defaults.set(enabled.map(\.rawValue), forKey: "enabled")
    }

    func isDesktop(_ platform: Platform) -> Bool { desktop.contains(platform) }

    func setDesktop(_ platform: Platform, _ on: Bool) {
        if on { desktop.insert(platform) } else { desktop.remove(platform) }
        defaults.set(desktop.map(\.rawValue), forKey: "desktop")
    }
}

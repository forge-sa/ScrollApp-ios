import AVFoundation
import SwiftUI

@main
@MainActor
struct ScrollAppApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var stats: StatsStore
    @StateObject private var feed: FeedController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = AppSettings()
        let stats = StatsStore()
        _settings = StateObject(wrappedValue: settings)
        _stats = StateObject(wrappedValue: stats)
        _feed = StateObject(wrappedValue: FeedController(settings: settings, stats: stats))
        // Sound plays like in a video app, even with the ring/silent switch on silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(stats)
                .environmentObject(feed)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            feed.setForeground(phase == .active)
        }
    }
}

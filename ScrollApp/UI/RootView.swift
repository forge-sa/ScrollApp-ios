import SwiftUI

private enum Screen {
    case feed, stats, settings
}

/// The feed stays in place underneath (its web views must stay alive); the other screens cover it,
/// and the feed pauses while covered.
struct RootView: View {
    @EnvironmentObject private var feed: FeedController
    @EnvironmentObject private var settings: AppSettings
    @State private var screen: Screen = .feed
    @State private var login: Platform?
    @State private var lastLogin: Platform?

    var body: some View {
        ZStack {
            FeedView(onStats: { screen = .stats }, onSettings: { screen = .settings })
            switch screen {
            case .stats:
                StatsView(onBack: { screen = .feed })
                    .transition(.move(edge: .trailing))
            case .settings:
                SettingsView(
                    onLogin: { platform in
                        lastLogin = platform
                        login = platform
                    },
                    onBack: {
                        settings.onboarded = true
                        screen = .feed
                    }
                )
                .transition(.move(edge: .trailing))
            case .feed:
                EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.22), value: screen)
        .sheet(item: $login, onDismiss: {
            // The session cookies are shared, so the feed just needs to load again to pick them up.
            if let platform = lastLogin { feed.reload(platform) }
        }) { platform in
            LoginView(platform: platform)
        }
        .onAppear {
            if !settings.onboarded { screen = .settings }
            updateCovered()
        }
        .onChange(of: screen) { _, _ in updateCovered() }
        .onChange(of: login) { _, _ in updateCovered() }
    }

    private func updateCovered() {
        feed.setCovered(screen != .feed || login != nil)
    }
}

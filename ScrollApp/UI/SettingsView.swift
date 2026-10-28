import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var feed: FeedController
    @EnvironmentObject private var settings: AppSettings
    let onLogin: (Platform) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: settings.onboarded ? "Settings" : "Welcome", onBack: onBack) {
                Button("Done", action: onBack).fontWeight(.semibold).padding(.trailing, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !settings.onboarded {
                        Card {
                            Text("One feed for Shorts, Reels and TikToks")
                                .fontWeight(.semibold)
                                .foregroundStyle(Ink.primary)
                            Text("Log in to each app below so the feed shows your own recommendations. "
                                + "Instagram and TikTok usually need an account; YouTube Shorts works without one. "
                                + "Then tap Done and swipe up.")
                                .font(.subheadline)
                                .foregroundStyle(Ink.secondary)
                                .padding(.top, 6)
                        }
                    }

                    SectionLabel("Sources")
                    VStack(spacing: 10) {
                        ForEach(Platform.allCases) { platform in
                            SourceCard(platform: platform, onLogin: onLogin)
                        }
                    }

                    SectionLabel("Feed")
                    Card {
                        ToggleRow(title: "Autoscroll", subtitle: "Move to the next video when one ends", isOn: $settings.autoscroll)
                        CardDivider()
                        ToggleRow(
                            title: "Skip ads and filler",
                            subtitle: "Ads, LIVE streams, people suggestions and Threads posts",
                            isOn: $settings.skipAds
                        )
                        CardDivider()
                        Text("Mixing").foregroundStyle(Ink.primary).padding(.bottom, 8)
                        Picker("Mixing", selection: $settings.mixMode) {
                            ForEach(MixMode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    SectionLabel("How to use")
                    Card {
                        Help(title: "Swipe up / down", text: "Next / previous video, across all sources")
                        Help(title: "Like", text: "Heart button below the video (double-tap also works on Reels and TikTok)")
                        Help(title: "Repost", text: "Uses the app's own repost when it has one, otherwise opens the share sheet")
                        Help(title: "Source name", text: "Tap the colored name in the bottom bar to reload that source")
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Ink.page.ignoresSafeArea())
        .tint(Ink.accent)
    }
}

private struct SourceCard: View {
    @EnvironmentObject private var feed: FeedController
    @EnvironmentObject private var settings: AppSettings
    let platform: Platform
    let onLogin: (Platform) -> Void

    var body: some View {
        let enabled = settings.isEnabled(platform)
        Card {
            Toggle(isOn: Binding(get: { enabled }, set: { feed.setPlatformEnabled(platform, $0) })) {
                HStack(spacing: 10) {
                    Dot(color: platform.color)
                    Text(platform.title).foregroundStyle(Ink.primary)
                }
            }
            if enabled {
                HStack(spacing: 8) {
                    Button { onLogin(platform) } label: { Text("Log in").frame(maxWidth: .infinity) }
                    Button { feed.reload(platform) } label: { Text("Reload").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.bordered)
                .padding(.vertical, 10)
                ToggleRow(
                    title: "Desktop site",
                    subtitle: "Try this if the mobile site won't show the feed",
                    isOn: Binding(
                        get: { settings.isDesktop(platform) },
                        set: { feed.setDesktopMode(platform, $0) }
                    )
                )
            }
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Ink.primary)
                Text(subtitle).font(.footnote).foregroundStyle(Ink.secondary)
            }
        }
    }
}

private struct Help: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.medium).foregroundStyle(Ink.primary)
            Text(text).font(.subheadline).foregroundStyle(Ink.secondary)
        }
        .padding(.vertical, 6)
    }
}

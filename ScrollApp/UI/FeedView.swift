import SwiftUI
import UIKit

struct FeedView: View {
    @EnvironmentObject private var feed: FeedController
    let onStats: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FeedHost(container: feed.container)
                .overlay(alignment: .top) {
                    NoticeView(text: feed.notice)
                        .animation(.easeOut(duration: 0.2), value: feed.notice)
                }
                .overlay { LikeBurst(trigger: feed.likeBurst) }
                .overlay {
                    if !feed.starting && feed.current == nil { NoSources(onSettings: onSettings) }
                }
            BottomBar(onStats: onStats, onSettings: onSettings)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(item: $feed.shareItem) { item in
            ShareSheet(url: item.url)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct FeedHost: UIViewRepresentable {
    let container: FeedContainerView

    func makeUIView(context: Context) -> FeedContainerView { container }
    func updateUIView(_ uiView: FeedContainerView, context: Context) {}
}

private struct BottomBar: View {
    @EnvironmentObject private var feed: FeedController
    @EnvironmentObject private var settings: AppSettings
    let onStats: () -> Void
    let onSettings: () -> Void

    var body: some View {
        let liked = feed.liked == true
        HStack(spacing: 2) {
            SourcePill()
            Spacer(minLength: 4)
            BarButton(
                systemImage: liked ? "heart.fill" : "heart",
                label: liked ? "Unlike" : "Like",
                tint: liked ? Ink.heart : Ink.primary,
                action: { feed.like() }
            )
            BarButton(systemImage: "arrow.2.squarepath", label: "Repost or share", action: { feed.repost() })
            BarButton(
                systemImage: settings.autoscroll ? "arrow.down.circle.fill" : "arrow.down.circle",
                label: settings.autoscroll ? "Autoscroll is on" : "Autoscroll is off",
                tint: settings.autoscroll ? Ink.primary : Ink.muted,
                highlighted: settings.autoscroll,
                action: { feed.toggleAutoscroll() }
            )
            BarButton(
                systemImage: settings.sound ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: settings.sound ? "Mute" : "Unmute",
                action: { feed.toggleSound() }
            )
            BarButton(systemImage: "chart.bar.fill", label: "Statistics", action: onStats)
            BarButton(systemImage: "gearshape.fill", label: "Settings and accounts", action: onSettings)
        }
        .padding(.horizontal, 6)
        .frame(height: 56)
        .background(Ink.page)
    }
}

/// Which source is on screen; tap it to reload that source.
private struct SourcePill: View {
    @EnvironmentObject private var feed: FeedController

    var body: some View {
        if let platform = feed.current {
            Menu {
                Button("Reload \(platform.title)") { feed.reload(platform) }
            } label: {
                HStack(spacing: 6) {
                    Dot(color: platform.color, size: 8)
                    Text(platform.shortName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Ink.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Ink.surface, in: Capsule())
            }
        }
    }
}

private struct BarButton: View {
    let systemImage: String
    let label: String
    var tint: Color = Ink.primary
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(highlighted ? Ink.wash : Color.clear, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

private struct NoticeView: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}

private struct LikeBurst: View {
    let trigger: Int
    @State private var scale: CGFloat = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 110))
            .foregroundStyle(Ink.heart)
            .scaleEffect(scale)
            .opacity(scale > 0 ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: trigger) {
                guard trigger > 0 else { return }
                scale = 0.5
                withAnimation(.spring(duration: 0.25)) { scale = 1.15 }
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation(.easeIn(duration: 0.3)) { scale = 0 }
            }
    }
}

private struct NoSources: View {
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("No sources turned on")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Ink.primary)
            Text("Turn on YouTube Shorts, Instagram Reels or TikTok to fill your feed.")
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
            Button("Open settings", action: onSettings)
        }
        .padding(32)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

import SwiftUI
import os

let feedLog = Logger(subsystem: "dev.wardar.scrollapp", category: "feed")

/// Monotonic seconds, unaffected by clock changes.
func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

/// Runs [body] on the main actor after [seconds], unless the returned task is cancelled first.
@MainActor @discardableResult
func runAfter(_ seconds: Double, _ body: @escaping @MainActor () -> Void) -> Task<Void, Never> {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        guard !Task.isCancelled else { return }
        body()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

func formatDuration(ms: Int64) -> String {
    let minutes = ms / 60_000
    if ms < 60_000 { return "\(ms / 1000)s" }
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h \(twoDigits(Int(minutes % 60)))m"
}

func twoDigits(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

func formatMinutes(_ minutes: Double) -> String { formatDuration(ms: Int64(minutes * 60_000)) }

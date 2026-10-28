import SwiftUI

/// The app is dark-only; these are the surfaces and ink the stats chart was validated against.
enum Ink {
    static let page = Color(hex: 0x0D0D0D)
    static let surface = Color(hex: 0x1A1A19)
    static let primary = Color.white
    static let secondary = Color(hex: 0xC3C2B7)
    static let muted = Color(hex: 0x898781)
    static let grid = Color(hex: 0x2C2C2A)
    static let baseline = Color(hex: 0x383835)
    static let accent = Color(hex: 0x3987E5)
    static let heart = Color(hex: 0xFF4D67)
    static let wash = Color.white.opacity(0.08)
}

struct ScreenHeader<Action: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .tint(Ink.primary)
            .accessibilityLabel("Back")
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Ink.primary)
            Spacer()
            action()
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
    }
}

extension ScreenHeader where Action == EmptyView {
    init(title: String, onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack, action: { EmptyView() })
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.medium))
            .tracking(1)
            .foregroundStyle(Ink.muted)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }
}

struct Dot: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

struct CardDivider: View {
    var body: some View {
        Rectangle().fill(Ink.grid).frame(height: 1).padding(.vertical, 10)
    }
}

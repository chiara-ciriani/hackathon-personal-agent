// Calm visual language: muted blue-grey and sage, no red, no alarms, large type that follows Dynamic Type.
import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 0.36, green: 0.45, blue: 0.56)       // slate blue
    static let calm = Color(red: 0.47, green: 0.60, blue: 0.53)         // sage
    static let warm = Color(red: 0.72, green: 0.62, blue: 0.47)         // sand (used for "louder"; never red)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let muted = Color.secondary

    /// Sage when quieter than the session median, slate around it, sand when louder.
    static func levelColor(_ level: Double?, median: Double?) -> Color {
        guard let level, let median else { return accent.opacity(0.5) }
        let d = level - median
        if d < -2 { return calm }
        if d > 2 { return warm }
        return accent
    }
}

/// A rounded card container used across screens.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A gentle full-width banner (tracking hints, zone prompts). Text only; no haptics, no colour-only meaning.
struct GentleBanner: View {
    var text: String
    var systemImage: String = "info.circle"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

/// Primary button style: large, high contrast, at least 44 pt tall.
struct CalmButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .foregroundStyle(prominent ? Color.white : Theme.accent)
            .background(prominent ? Theme.accent : Theme.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

import SwiftUI

/// "Platform" and the platform pill (TT-199, D82, Grigor's design): the number in accent on an accent-tinted pill, or a
/// grey dash on a grey pill until it is posted. Every screen that shows a platform uses this; only the size changes. While
/// the platform is worth waiting for (D55) the dash pill pulses; still with Reduce Motion and in snapshots.
struct PlatformTag: View {
    /// "7"; nil shows the dash.
    let number: String?
    /// The label's point size.
    var size: CGFloat = 17
    /// The number's point size, which sizes the pill; the label's when nil.
    var pillSize: CGFloat?
    /// The dash pill pulses (a platform feed is live and the platform may be posted any minute, D55).
    var pulses = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Off in snapshot tests (Schedule's and Trip details' flags), so the image is stable.
    @Environment(\.skeletonPulses) private var skeletonPulses
    @Environment(\.playsRideMotion) private var playsRideMotion
    @State private var dimmed = false

    var body: some View {
        HStack(spacing: size * 0.55) {
            Text("schedule.platform_label")
                .font(.system(size: size))
                .foregroundStyle(TTColor.inkSecondary)
                .lineLimit(1)
                .fixedSize()
            PlatformBadge(number: number, size: pillSize ?? size, palette: palette)
                .opacity(dimmed ? 0.4 : 1)
        }
        .onAppear { pulse() }
        .onChange(of: isPulsing) { pulse() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var palette: PlatformBadge.Palette {
        let dark = colorScheme == .dark
        return PlatformBadge.Palette(
            numberInk: TTColor.accent,
            numberFill: TTColor.accent.opacity(dark ? 0.18 : 0.12),
            dashInk: dark ? TTColor.inkSecondary : TTColor.inkTertiary,
            dashFill: TTColor.inkTertiary.opacity(dark ? 0.25 : 0.14)
        )
    }

    private var isPulsing: Bool {
        number == nil && pulses && skeletonPulses && playsRideMotion && !reduceMotion
    }

    private func pulse() {
        guard isPulsing else {
            dimmed = false
            return
        }
        // One fade out and back takes 1.6 s (D55).
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dimmed = true }
    }

    /// "Platform 7", "Platform pending" while it may be posted any minute, else "Platform —".
    private var accessibilityText: String {
        if let number { return String(format: String(localized: "schedule.platform"), number) }
        if pulses { return String(localized: "schedule.platform_pending") }
        return String(format: String(localized: "schedule.platform"), String(localized: "schedule.platform_placeholder"))
    }
}

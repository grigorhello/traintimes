import SwiftUI

/// Schedule's watched-trip strip while an alerted train counts down (TT-177, *Live-Depart*): the filled bell and "Your
/// 5:13 PM train", "Platform [7] · On time", the countdown and "departs", a chevron. A tap opens its Trip details.
struct DepartureStripView: View {
    let strip: DepartureStrip
    var onOpen: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: TTSpace.s3) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(strip.title)
                            .font(TTFont.badge)
                    }
                    .foregroundStyle(TTColor.accent)
                    HStack(spacing: 6) {
                        PlatformTag(number: strip.platform, size: 17, pillSize: 15, pulses: strip.pillPulses)
                        Text(verbatim: "· " + strip.status)
                            .font(TTFont.body)
                            .tracking(-0.4)
                            .foregroundStyle(TTColor.inkSecondary)
                    }
                }
                .lineLimit(1)
                .monospacedDigit()
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(strip.countdown)
                        .font(TTFont.route)
                        .tracking(-0.4)
                        .foregroundStyle(strip.isDelayed ? TTColor.delayInk : TTColor.accent)
                        .contentTransition(.numericText(countsDown: true))
                    Text("depart.in")
                        .font(TTFont.footnote)
                        .foregroundStyle(TTColor.inkSecondary)
                }
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .animation(.easeOut(duration: 0.15), value: strip.countdown)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TTColor.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
            .background(TTColor.accentSoft, in: RoundedRectangle(cornerRadius: TTRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: TTRadius.lg)
                    .strokeBorder(TTColor.accent.opacity(colorScheme == .dark ? 0.20 : 0.14), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: TTRadius.lg))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.departure")
    }
}

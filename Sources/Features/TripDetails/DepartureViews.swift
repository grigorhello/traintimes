import SwiftUI

/// The departure card (TT-177, *Live-Depart-Trip*): the journey card before an alerted train leaves, with the ride card's
/// anatomy. "Departs from Union Station GO", the platform as the 28 pt hero (the pill until it is posted, then the number
/// pressing in with a light tap), the countdown on the right, your stop with the arrival, and the Live row. A late train
/// counts down in delay-ink; "Boarding now" tints the card soft green.
struct LiveDepartureCard: View {
    let departure: DepartureDetails
    /// The Directions link on the "Departs from" line; nil shows none.
    var onDirections: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let yourStopRow: CGFloat = 60
    private static let statusRow: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TTRadius.xl)
        let tinted = departure.isBoarding
        VStack(spacing: 0) {
            block
            hairline
            yourStop
            hairline
            status
        }
        .padding(.horizontal, TTSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tinted ? TTColor.accentSoft : TTColor.surface, in: shape)
        .overlay(shape.strokeBorder(edgeColour, lineWidth: tinted ? 1 : 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark || tinted ? 0 : 0.06), radius: 1, x: 0, y: 1)
        .animation(RideMotion.tint, value: tinted)
        // One light tap as the platform is posted while the sheet is open (Live-Spec).
        .sensoryFeedback(.impact(weight: .light), trigger: departure.platform) { old, new in old == nil && new != nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.departure")
    }

    /// The 1 pt accent edge of the boarding card, the 0.5 pt white edge of a dark one.
    private var edgeColour: Color {
        if departure.isBoarding { return TTColor.accent.opacity(colorScheme == .dark ? 0.22 : 0.18) }
        return .white.opacity(colorScheme == .dark ? 0.08 : 0)
    }

    private var hairline: some View {
        Rectangle()
            .fill(departure.isBoarding ? TTColor.accent.opacity(colorScheme == .dark ? 0.18 : 0.16) : TTColor.hairline)
            .frame(height: 1)
    }

    /// The label (with the Directions link at its right end), the platform and the line under it; the countdown and the
    /// departure time on the right.
    private var block: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: TTSpace.s3) {
                Text(departure.label)
                    .font(departure.isBoarding ? TTFont.footnote.weight(.semibold) : TTFont.footnote)
                    .monospacedDigit()
                    .foregroundStyle(departure.isBoarding ? TTColor.accent : TTColor.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let onDirections {
                    DirectionsLink(action: onDirections)
                }
            }
            HStack(alignment: .center, spacing: TTSpace.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    platform
                    Text(detailText)
                        .font(TTFont.subhead)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                if let countdown = departure.countdown {
                    VStack(alignment: .trailing, spacing: -2) {
                        Text(countdown)
                            .font(TTFont.timeLead)
                            .tracking(-0.6)
                            .monospacedDigit()
                            .foregroundStyle(departure.isDelayed ? TTColor.delayInk : TTColor.accent)
                            .contentTransition(.numericText(countsDown: true))
                        Text(departure.countdownTime)
                            .font(TTFont.footnote)
                            .monospacedDigit()
                            .foregroundStyle(TTColor.inkSecondary)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .animation(.easeOut(duration: 0.15), value: countdown)
                    .animation(RideMotion.tint, value: departure.isDelayed)
                }
            }
        }
        .padding(.top, TTSpace.s4)
        .padding(.bottom, 14)
    }

    /// "Platform" and the pill (TT-199): the dash (pulsing while it may be posted any minute), then the number, which
    /// presses in from 0.94 as it replaces it.
    private var platform: some View {
        PlatformTag(number: departure.platform, size: 26, pulses: departure.pillPulses)
            .animation(.easeOut(duration: 0.2), value: departure.platform)
            .keyframeAnimator(initialValue: 1.0, trigger: pressTrigger) { content, scale in
                content.scaleEffect(scale, anchor: .bottomLeading)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    LinearKeyframe(DepartureMotion.platformFrom, duration: 0.01)
                    SpringKeyframe(
                        1.0, duration: 0.64,
                        spring: Spring(response: DepartureMotion.platformCurve.response, dampingRatio: DepartureMotion.platformCurve.damping)
                    )
                }
            }
    }

    /// The platform presses in once as it is posted; not with Reduce Motion.
    private var pressTrigger: String? { reduceMotion ? nil : departure.platform }

    /// The line in ink-secondary with its emphasis semibold, in ink, or in delay-ink for a late train.
    private var detailText: AttributedString {
        var text = AttributedString(departure.detail)
        text.foregroundColor = TTColor.inkSecondary
        if let emphasis = departure.emphasis, let range = text.range(of: emphasis, options: .backwards) {
            text[range].font = TTFont.subhead.weight(.semibold)
            text[range].foregroundColor = departure.isDelayed ? TTColor.delayInk : TTColor.ink
        }
        return text
    }

    /// The pin, "Your stop" and its name; the arrival and the ride's length on the right.
    private var yourStop: some View {
        HStack(spacing: TTSpace.s3) {
            RoutePin()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("onboard.yourStop")
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                Text(verbatim: departure.yourStop)
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.ink)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(departure.arrival)
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.ink)
                Text(departure.rideLength)
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
        }
        .frame(height: Self.yourStopRow)
    }

    /// The Live dot and "Live · GO train data", or "Timetable" with the grey dot; how fresh on the right.
    private var status: some View {
        HStack(spacing: TTSpace.s3) {
            HStack(spacing: TTSpace.s2) {
                switch departure.source {
                case .live(let text):
                    LiveDot()
                    Text(RideCard.lead(text))
                case .timetable, .complete:
                    LiveDot(isLive: false)
                    Text("onboard.live.timetable")
                        .font(TTFont.subhead.weight(.semibold))
                        .foregroundStyle(TTColor.inkSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let freshness = departure.freshness {
                Text(freshness)
                    .font(TTFont.footnote)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(height: Self.statusRow)
    }
}

/// The Directions link at the right end of the "Departs from" line (TT-188's link, *Directions-Live*): the glyph and the
/// word in the accent, a 44 pt hit area around them.
private struct DirectionsLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text("button.directions")
                    .font(TTFont.subhead.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(TTColor.accent)
            .padding(.vertical, 12)
            .padding(.leading, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -12)
        .accessibilityIdentifier("trip.directions")
    }
}

import SwiftUI

/// The hero card before departure (TT-205, D92, boards 2 and 4): "5:13 PM departs in" at 22 pt (the time in ink, the words in
/// ink-secondary) over the minutes at 64 pt; "Platform" over the pill at the right (the dash, pulsing while it may be posted
/// any minute, then the number pressing in with a light tap); "3 min late" in delay-ink under the minutes only when late.
/// Boarding: the number in the accent. One view, driven by `DepartureHero`, so a later ticket can show it for every train.
struct DepartureHeroCard: View {
    let hero: DepartureHero

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TTRadius.xl)
        HStack(alignment: .top, spacing: TTSpace.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text(line)
                    .font(TTFont.departLine)
                    .tracking(-0.4)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(hero.countdown)
                    .font(TTFont.rideMinutes)
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(hero.isBoarding ? TTColor.accent : TTColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 68)
                    .padding(.leading, -2)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.15), value: hero.countdown)
                if let late = hero.late {
                    Text(late)
                        .font(TTFont.headline)
                        .tracking(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.delayInk)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            platform
                .padding(.top, 2)
        }
        .padding(.vertical, TTSpace.s4)
        .padding(.horizontal, TTSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.surface, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0), lineWidth: 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 1, x: 0, y: 1)
        // One light tap as the platform is posted while the sheet is open (Live-Spec).
        .sensoryFeedback(.impact(weight: .light), trigger: hero.platform) { old, new in old == nil && new != nil }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip.departure")
    }

    /// The clock time in ink (delay-ink while late), the words after it in ink-secondary.
    private var line: AttributedString {
        var text = AttributedString(hero.line)
        text.foregroundColor = TTColor.inkSecondary
        if let range = text.range(of: hero.time) {
            text[range].foregroundColor = hero.isLate ? TTColor.delayInk : TTColor.ink
        }
        return text
    }

    /// "Platform" over the pill (TT-199): the dash, then the number, which presses in from 0.94 as it replaces it.
    private var platform: some View {
        PlatformTag(number: hero.platform, size: 17, pillSize: 20, pulses: hero.pillPulses, isStacked: true)
            .animation(.easeOut(duration: 0.2), value: hero.platform)
            .keyframeAnimator(initialValue: 1.0, trigger: pressTrigger) { content, scale in
                content.scaleEffect(scale, anchor: .bottomTrailing)
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
    private var pressTrigger: String? { reduceMotion ? nil : hero.platform }
}

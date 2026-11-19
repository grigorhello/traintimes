import SwiftUI

/// The hero card before departure (TT-205, D93, boards 2 and 4): "5:13 PM departs in" at 22 pt (the time in ink, the words in
/// ink-secondary) over the minutes at 64 pt; "Platform" over the pill at the right (the dash, pulsing while it may be posted
/// any minute, then the number pressing in with a light tap); "3 min late" in delay-ink under the minutes only when late.
/// A train that does not count down (TT-207, D96): "Departs at" over the expected clock time at 64 pt, in delay-ink while
/// late. Express: the bolt beside "Platform".
/// Boarding at the platform (TT-233, D114, Card states board 5): the card's accent outline and tint, "5:58 PM boarding
/// now" in the accent and the pill filled, cross-fading in on `TTMotion.cross`. Boarding by the clock alone (the last 2 min
/// with no position, D69) keeps its look: the number in the accent, nothing else.
struct DepartureHeroCard: View {
    let hero: DepartureHero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False in the unit test host, so a snapshot draws the card at rest.
    @Environment(\.playsEntranceMotion) private var playsMotion

    var body: some View {
        HStack(alignment: .top, spacing: TTSpace.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text(line)
                    .font(TTFont.departLine)
                    .tracking(-0.4)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(hero.number)
                    .font(TTFont.rideMinutes)
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 68)
                    .padding(.leading, -2)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.15), value: hero.number)
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
        // Boarding: the accent outline and tint between the content and the card's surface, as on the timeline card.
        .background {
            if hero.isBoarding { BoardingHighlight(cornerRadius: TTRadius.xl) }
        }
        .ttSheetCard()
        .animation(boardingAnimation, value: hero.isBoarding)
        // One light tap as the platform is posted while the sheet is open (Live-Spec).
        .sensoryFeedback(.impact(weight: .light), trigger: hero.platform) { old, new in old == nil && new != nil }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip.departure")
    }

    /// The card cross-fades into Boarding and out of it (TT-233): a plain fade with Reduce Motion, and no animation in the
    /// unit test host.
    private var boardingAnimation: Animation? {
        guard playsMotion else { return nil }
        return reduceMotion ? TTMotion.fade : TTMotion.cross
    }

    /// Boarding by the clock in the accent; a clock time in delay-ink while late; ink otherwise (also at the platform, where
    /// the line and the card carry the accent).
    private var numberColor: Color {
        if hero.boardsByClock { return TTColor.accent }
        return !hero.showsCountdown && hero.isLate ? TTColor.delayInk : TTColor.ink
    }

    /// The clock time in ink (delay-ink while late), the words after it in ink-secondary; "Departs at" all ink-secondary.
    /// Boarding at the platform: the whole line in the accent, the time still in delay-ink while late.
    private var line: AttributedString {
        var text = AttributedString(hero.line)
        text.foregroundColor = hero.isBoarding ? TTColor.accent : TTColor.inkSecondary
        guard let range = text.range(of: hero.time) else { return text }
        if hero.isBoarding {
            if hero.isLate { text[range].foregroundColor = TTColor.delayInk }
        } else if hero.showsCountdown {
            text[range].foregroundColor = hero.isLate ? TTColor.delayInk : TTColor.ink
        }
        return text
    }

    /// "Platform" over the pill (TT-199): the dash, then the number, which presses in from 0.94 as it replaces it. The
    /// pill is filled while the train is boarding at that platform (TT-233).
    private var platform: some View {
        PlatformTag(
            number: hero.platform, size: 17, pillSize: 20, pulses: hero.pillPulses, isStacked: true, showsExpress: hero.isExpress,
            isFilled: hero.isBoarding
        )
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

import SwiftUI

/// How the station picker moves (TT-161, D54; the Picker-Spec board on the canvas has the tables). Everything starts on the
/// tap: the list is revealed by a clip growing down from the card's bottom edge, its content rides down a little behind it,
/// its rows fall in one after another, the veil and day strip fade, and the swap button turns into the X. Closing is
/// quicker and has no stagger.
enum PickerMotion {
    /// The list's clip growing down from the card's bottom edge: at rest by about 450 ms, never overshooting into the
    /// keyboard gap.
    static var reveal: Animation { .spring(response: 0.42, dampingFraction: 0.90) }
    /// The rows as one block riding down 10 pt inside the clip, which gives the landing its weight.
    static var ride: Animation { .spring(response: 0.45, dampingFraction: 0.76) }
    /// Closing, for everything but the veil and the buttons: ease-in, 220 ms.
    static var close: Animation { .timingCurve(0.4, 0, 0.7, 0.3, duration: 0.22) }
    /// Every height change while the picker is open (typing, switching fields): critically damped, no bounce.
    static var height: Animation { .spring(response: 0.28, dampingFraction: 1.0) }
    /// The animation for a state change into (`opening`) or out of the picker.
    static func animation(opening: Bool) -> Animation { opening ? reveal : close }

    /// A header or row falling into place, one after another in list order; a header shares its group's first row's slot
    /// and the stagger stops at the ninth.
    static func row(order: Int) -> Animation {
        .spring(response: 0.32, dampingFraction: 0.86).delay(0.040 + 0.018 * Double(min(order, 8)))
    }
}

/// The list surface revealed from the top: a clip grows down from the card's bottom edge (no fade, no scale). Closing
/// retracts it, lifting 8 pt and fading in the last 40 %. The clip reaches past the surface on the sides and above, so the
/// shadow beside the card shows; the shadow below shows only as the clip arrives.
private struct PanelReveal: ViewModifier, Animatable {
    /// 0 is away, 1 is settled; the spring may overshoot a little.
    var progress: Double
    var lift: CGFloat = 0
    var fadeTail: Double = 0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: -lift * (1 - progress))
            .opacity(fadeTail == 0 ? 1 : min(1, progress / fadeTail))
            .mask(alignment: .top) {
                GeometryReader { geometry in
                    let reach: CGFloat = 96
                    let above: CGFloat = 220
                    let height = geometry.size.height * max(progress, 0)
                    let shadow = reach * min(1, max(0, (progress - 0.85) / 0.15))
                    Rectangle()
                        .frame(width: geometry.size.width + 2 * reach, height: above + height + shadow)
                        .offset(x: -reach, y: -above)
                }
            }
    }
}

/// The X coming in: it turns from -90° to 0 while it scales from 0.6 to 1.
private struct TurnIn: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(-90 * (1 - progress)))
            .scaleEffect(0.6 + 0.4 * progress)
            .opacity(min(1, progress * 2))
    }
}

extension AnyTransition {
    /// The suggestions list under the route card. Reduce Motion: a 200 ms fade.
    static func pickerPanel(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity.animation(.easeOut(duration: 0.2)) }
        return .asymmetric(
            insertion: .modifier(active: PanelReveal(progress: 0), identity: PanelReveal(progress: 1)),
            removal: AnyTransition
                .modifier(
                    active: PanelReveal(progress: 0, lift: 8, fadeTail: 0.4), identity: PanelReveal(progress: 1, lift: 8, fadeTail: 0.4)
                )
                .animation(PickerMotion.close)
        )
    }

    /// The frosted veil over the timetable: 220 ms ease-out in, 200 ms ease-in out.
    static var pickerVeil: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.22)),
            removal: .opacity.animation(.easeIn(duration: 0.20))
        )
    }

    /// The X taking the swap button's place: the swap scales to 0.6 and fades over 140 ms, then the X comes in 40 ms later.
    static var pickerCancelButton: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: TurnIn(progress: 0), identity: TurnIn(progress: 1))
                .animation(.spring(response: 0.30, dampingFraction: 0.80).delay(0.04)),
            removal: .scale(scale: 0.6).combined(with: .opacity).animation(.easeIn(duration: 0.14))
        )
    }

    /// The swap button coming back when the picker closes: the X scales out first, then the swap comes in 40 ms later.
    static var pickerSwapButton: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.6).combined(with: .opacity).animation(.spring(response: 0.30, dampingFraction: 0.80).delay(0.04)),
            removal: .scale(scale: 0.6).combined(with: .opacity).animation(.easeIn(duration: 0.14))
        )
    }
}

private struct PickerEntranceKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False in snapshot tests, which draw the settled panel with every row in place instead of mid-fall.
    var animatesPickerEntrance: Bool {
        get { self[PickerEntranceKey.self] }
        set { self[PickerEntranceKey.self] = newValue }
    }
}

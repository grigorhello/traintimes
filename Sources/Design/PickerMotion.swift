import SwiftUI

/// How the station picker moves (TT-161, D54, revised as "Lively": Grigor, 2026-11-10; the Picker-Bounce-Spec board on the
/// canvas has the tables). Everything starts on the tap: the list is revealed by a calm clip growing down from the card's
/// bottom edge, its content rides down behind it on a bouncy spring, its rows fall in one after another with a little
/// bounce, the veil and day strip fade, and the swap button turns into the X. The bounce is on transforms only; the clip
/// barely overshoots. Closing is quicker and has no stagger.
enum PickerMotion {
    /// The list's clip growing down from the card's bottom edge: about 1 % over (5 pt of 450), inside the keyboard gap.
    static var reveal: Animation { .spring(response: 0.46, dampingFraction: 0.82) }
    /// The rows as one block riding down 24 pt inside the clip, which gives the landing its weight.
    static var ride: Animation { .spring(response: 0.50, dampingFraction: 0.60) }
    /// How far the block rides.
    static let rideDistance: CGFloat = 24
    /// Closing, for everything but the veil and the buttons: ease-in, 220 ms.
    static var close: Animation { .timingCurve(0.4, 0, 0.7, 0.3, duration: 0.22) }
    /// Every height change while the picker is open (typing, switching fields): critically damped, no bounce.
    static var height: Animation { .spring(response: 0.28, dampingFraction: 1.0) }
    /// The swap button and the X leaving: 120 ms ease-in.
    static var buttonOut: Animation { .easeIn(duration: 0.12) }
    /// The X and the swap button arriving, 40 ms after the other left.
    static var buttonIn: Animation { .spring(response: 0.42, dampingFraction: 0.55).delay(0.04) }
    /// The press tint stays on a picked row this long before the list closes.
    static let pickHold: Duration = .milliseconds(120)
    /// The animation for a state change into (`opening`) or out of the picker.
    static func animation(opening: Bool) -> Animation { opening ? reveal : close }

    /// A header or row's delay in the fall: 30 ms plus 24 ms a place, the stagger stopping at the ninth. A header shares its
    /// group's first row's place.
    private static func delay(order: Int) -> Double { 0.030 + 0.024 * Double(min(order, 8)) }
    /// The row's opacity: 0 to 1 in 140 ms, ease-out.
    static func rowFade(order: Int) -> Animation { .easeOut(duration: 0.14).delay(delay(order: order)) }
    /// The row's fall (y -28 to 0, scale 0.92 to 1), with a bounce.
    static func rowFall(order: Int) -> Animation {
        .spring(response: 0.44, dampingFraction: 0.56).delay(delay(order: order))
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

    // `ViewModifier` is main-actor isolated, `Animatable` is not: the witness is `nonisolated` (it only reads and writes a Double).
    nonisolated var animatableData: Double {
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

/// A button glyph turning and scaling into or out of its place: at rest at 1, away at `degrees`, half size and clear. The X
/// arrives from -135° and leaves to -90°; the swap arrows arrive from +90° and leave to +90°. Built from SwiftUI's own
/// rotation, scale and opacity, which SwiftUI moves frame by frame by itself: a custom `Animatable` progress needs its body
/// run on every frame, and inside the route card's paused `TimelineView` it was not, so the turn and the size caught up in
/// jumps 0.9 s and 1.7 s after the tap (TT-196).
private struct Turn: ViewModifier {
    let degrees: Double
    let isAway: Bool

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isAway ? degrees : 0))
            .scaleEffect(isAway ? 0.5 : 1)
            .opacity(isAway ? 0 : 1)
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

    /// The X taking the swap button's place: the swap button turns to +90° at half size and fades over 120 ms, then the X
    /// comes in 40 ms later from -135° on a bouncy spring. Closing, the X leaves to -90° the same way.
    static var pickerCancelButton: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: Turn(degrees: -135, isAway: true), identity: Turn(degrees: -135, isAway: false))
                .animation(PickerMotion.buttonIn),
            removal: .modifier(active: Turn(degrees: -90, isAway: true), identity: Turn(degrees: -90, isAway: false))
                .animation(PickerMotion.buttonOut)
        )
    }

    /// The swap button in the card: it arrives from +90° at half size (40 ms after the X has left) and leaves to +90°.
    static var pickerSwapButton: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: Turn(degrees: 90, isAway: true), identity: Turn(degrees: 90, isAway: false))
                .animation(PickerMotion.buttonIn),
            removal: .modifier(active: Turn(degrees: 90, isAway: true), identity: Turn(degrees: 90, isAway: false))
                .animation(PickerMotion.buttonOut)
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

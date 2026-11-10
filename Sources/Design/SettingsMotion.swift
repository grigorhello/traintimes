import SwiftUI

/// How Settings moves (TT-168, D57; the Settings-Spec board on the canvas has the table). Springs on the switch thumb, the
/// chosen symbol, the notification dot and badge, the cards of a pushed page and the Testing reveal; nothing on the tab
/// bar, the push and pop, scrolling or row presses. Reduce Motion plays none of the springs: colours cross-fade and cards
/// fade in.
enum SettingsMotion {
    /// The switch thumb gliding to the chosen option.
    static var glide: Animation { .spring(response: 0.45, dampingFraction: 0.72) }
    /// The cards of a pushed page rising 16 pt and growing from 0.97.
    static var rise: Animation { .spring(response: 0.44, dampingFraction: 0.62) }
    /// The Mock time card opening.
    static var reveal: Animation { .spring(response: 0.46, dampingFraction: 0.82) }
    /// The Reset button arriving.
    static var arrive: Animation { .spring(response: 0.40, dampingFraction: 0.50) }
    /// The first card of a pushed page starts this long after the push, the next ones 40 ms later each.
    static let riseDelay = 0.16
    static let riseStagger = 0.04
    /// The Mock time rows drop in 30 ms after the card starts opening, 24 ms apart.
    static func dropDelay(order: Int) -> Double { 0.030 + 0.024 * Double(order) }
}

extension EnvironmentValues {
    /// False in snapshot tests, which draw every page settled instead of mid-spring.
    @Entry var playsSettingsMotion: Bool = true
}

/// What a one-shot spring animates: the scale and the turn.
private struct BumpValues {
    var scale = 1.0
    var degrees = 0.0
}

/// A one-shot spring played each time `trigger` changes: the view starts at `from` (and `turn` degrees) after `delay` and
/// springs to rest. At rest, and before the first trigger, it is drawn as it is.
private struct Bump<Trigger: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsSettingsMotion) private var playsMotion
    let trigger: Trigger
    let from: Double
    let turn: Double
    let response: Double
    let damping: Double
    let delay: Double

    func body(content: Content) -> some View {
        let plays = playsMotion && !reduceMotion
        // Plain numbers, so the keyframes capture these and not the modifier (whose environment values are not Sendable).
        let startScale = self.from, startTurn = self.turn, hold = self.delay + 0.001
        let spring = Spring(response: self.response, dampingRatio: self.damping)
        let turnSpring = Spring(response: 0.50, dampingRatio: 0.58)
        return content.keyframeAnimator(
            initialValue: BumpValues(), trigger: plays ? AnyHashable(trigger) : AnyHashable(0)
        ) { view, values in
            view.scaleEffect(values.scale).rotationEffect(.degrees(values.degrees))
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                LinearKeyframe(startScale, duration: 0.001)
                LinearKeyframe(startScale, duration: hold)
                SpringKeyframe(1, duration: 0.8, spring: spring)
            }
            KeyframeTrack(\.degrees) {
                LinearKeyframe(startTurn, duration: 0.001)
                LinearKeyframe(startTurn, duration: hold)
                SpringKeyframe(0, duration: 0.8, spring: turnSpring)
            }
        }
    }
}

/// The bell swinging once on a Notifications page that has just opened or just been allowed: 16°, -13°, 8°, -4°, 0 over
/// 700 ms, from 200 ms, hanging from a point near its top.
private struct BellSwing<Trigger: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsSettingsMotion) private var playsMotion
    let trigger: Trigger

    func body(content: Content) -> some View {
        let plays = playsMotion && !reduceMotion
        content.keyframeAnimator(
            initialValue: BumpValues(), trigger: plays ? AnyHashable(trigger) : AnyHashable(0)
        ) { view, values in
            view.rotationEffect(.degrees(values.degrees), anchor: UnitPoint(x: 0.5, y: 0.1))
        } keyframes: { _ in
            KeyframeTrack(\.degrees) {
                LinearKeyframe(0, duration: 0.2)
                CubicKeyframe(16, duration: 0.126)
                CubicKeyframe(-13, duration: 0.154)
                CubicKeyframe(8, duration: 0.154)
                CubicKeyframe(-4, duration: 0.14)
                CubicKeyframe(0, duration: 0.126)
            }
        }
    }
}

/// A card of a pushed page arriving: it rises 16 pt and grows from 0.97 on a spring, `order` places after the first (40 ms
/// apart, from 160 ms). Reduce Motion: a 200 ms fade.
private struct Rise: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsSettingsMotion) private var playsMotion
    let order: Int
    @State private var arrived = false

    func body(content: Content) -> some View {
        let settled = arrived || !playsMotion
        let delay = SettingsMotion.riseDelay + SettingsMotion.riseStagger * Double(order)
        content
            .opacity(settled ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.14).delay(delay), value: arrived)
            .scaleEffect(settled || reduceMotion ? 1 : 0.97)
            .offset(y: settled || reduceMotion ? 0 : 16)
            .animation(reduceMotion ? nil : SettingsMotion.rise.delay(delay), value: arrived)
            .onAppear { arrived = true }
    }
}

extension View {
    /// Springs in from `from` times its size (and `turn` degrees) each time `trigger` changes.
    func settingsBump(
        trigger: some Hashable, from: Double, turn: Double = 0, response: Double, damping: Double, delay: Double = 0
    ) -> some View {
        modifier(Bump(trigger: trigger, from: from, turn: turn, response: response, damping: damping, delay: delay))
    }

    /// The chosen switch symbol or label pressing in: 0.80 to 1, `spring(0.40, 0.50)`; `turns` adds the Appearance symbol's
    /// quarter turn.
    func settingsPress(trigger: some Hashable, turns: Bool = false) -> some View {
        settingsBump(trigger: trigger, from: 0.80, turn: turns ? -90 : 0, response: 0.40, damping: 0.50)
    }

    /// The notification dot (from 0.2) or badge (from 0.72) popping when the state changes, `spring(0.35, 0.50)`.
    func settingsPop(trigger: some Hashable, from: Double) -> some View {
        settingsBump(trigger: trigger, from: from, response: 0.35, damping: 0.50)
    }

    func settingsBellSwing(trigger: some Hashable) -> some View {
        modifier(BellSwing(trigger: trigger))
    }

    /// A card of a pushed page rising in, `order` places after the first.
    func settingsRise(order: Int) -> some View {
        modifier(Rise(order: order))
    }
}

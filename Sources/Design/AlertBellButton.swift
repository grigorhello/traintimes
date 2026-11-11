import SwiftUI

/// The bell's faces (TT-190, the spec board's four, and the hold while iOS asks).
enum BellFace: Equatable, Sendable {
    /// Outline in ink-secondary: no alert for this train on this day, or its alert is switched off.
    case off
    /// The outline in accent held at 1.12 while iOS asks for permission, after the first bell tap ever.
    case asking
    /// The filled bell in accent at half strength while the alert is saved. No words.
    case waiting
    /// The filled bell in accent: the alert is saved and can reach the rider.
    case on
    /// The bell with a slash in ink-secondary: an alert covers the train but iOS notifications are off.
    case crossed
}

/// The bell on a departure card (TT-141), with its pop (TT-166, D62): when the alert turns on or off the glyph swells to
/// 1.3 over 0.1 s (`TTMotion.swell`), swaps `bell` and `bell.fill` at the top, as Kavsoft does, and springs back on
/// `TTMotion.pop`. While `\.holdsBellPop` is true (the alert setup sheet is up) the bell keeps the glyph it had and pops
/// once the sheet is gone. Reduce Motion cross-fades the glyph instead. Turned off it is quiet on purpose (TT-191, D71): the
/// outline swaps in at once and settles from 0.86 on `TTMotion.settle`.
///
/// Permission from the bell (TT-190, D72): the pop now comes on the tap, into the half-strength wait, and the wait goes
/// solid in 150 ms once the alert is saved. While iOS asks the bell holds at 1.12 in accent (120 ms ease-out) and finishes
/// into the pop. A refusal shakes it sideways, 7, 6, 4 and 2 pt over 420 ms, as `shakes` grows.
struct AlertBellButton: View {
    let face: BellFace
    /// Each increase shakes the bell once (a refusal, the Motion board's Refused).
    var shakes = 0
    let label: Text
    let glyph: CGFloat
    let target: CGFloat
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.holdsBellPop) private var holdsPop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The face drawn: it follows `face` at the top of the swell, or after the sheet holding it has gone.
    @State private var shown: BellFace
    /// The latest `face`, read when the swell ends (the view value the task captured may be older by then).
    @State private var wanted: BellFace
    @State private var scale: CGFloat
    /// Each turn off settles the outline again (TT-191).
    @State private var offs = 0

    init(face: BellFace, shakes: Int = 0, label: Text, glyph: CGFloat, target: CGFloat, action: @escaping () -> Void) {
        self.face = face
        self.shakes = shakes
        self.label = label
        self.glyph = glyph
        self.target = target
        self.action = action
        _shown = State(initialValue: face)
        _wanted = State(initialValue: face)
        _scale = State(initialValue: face == .asking ? Self.askingScale : 1)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph))
                .foregroundStyle(tint)
                .opacity(shown == .waiting ? 0.5 : 1)
                .contentTransition(.opacity)
                .frame(width: target, height: target)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
        .scaleEffect(scale)
        .keyframeAnimator(initialValue: 1.0, trigger: offs) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            MoveKeyframe(0.86)
            SpringKeyframe(1.0, duration: 0.6, spring: TTMotion.settleCurve.spring)
        }
        .keyframeAnimator(initialValue: CGFloat(0), trigger: reduceMotion ? 0 : shakes) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            // 0, -7, 6, -4, 2, 0 at 0, 16.7, 38.1, 59.5, 81 and 100 % of 420 ms.
            KeyframeTrack(\.self) {
                CubicKeyframe(-7, duration: 0.07)
                CubicKeyframe(6, duration: 0.09)
                CubicKeyframe(-4, duration: 0.09)
                CubicKeyframe(2, duration: 0.09)
                CubicKeyframe(0, duration: 0.08)
            }
        }
        .onChange(of: face) { _, face in
            wanted = face
            change(to: face)
        }
        .onChange(of: holdsPop) { change(to: wanted) }
    }

    private var symbol: String {
        switch shown {
        case .off, .asking: "bell"
        case .waiting, .on: "bell.fill"
        case .crossed: "bell.slash.fill"
        }
    }

    private var tint: Color {
        guard isEnabled else { return TTColor.inkTertiary }
        return switch shown {
        case .asking, .waiting, .on: TTColor.accent
        case .off, .crossed: TTColor.inkSecondary
        }
    }

    /// Draws the new face: the hold while iOS asks, the pop when the alert turns on or off, otherwise a quiet change (the
    /// wait going solid in 150 ms; the outline under a refusal's shake). Nothing while a sheet holds the pop.
    private func change(to face: BellFace) {
        guard !holdsPop, shown != face else { return }
        let from = shown
        if face == .asking || (from == .asking && !Self.pops(from: from, to: face)) {
            withAnimation(.easeOut(duration: 0.12)) {
                shown = face
                scale = face == .asking && !reduceMotion ? Self.askingScale : 1
            }
            return
        }
        if from == .on, face == .off, !reduceMotion {
            // Off: the outline at once, then the quiet settle (TT-191).
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) { shown = face }
            offs += 1
            return
        }
        guard Self.pops(from: from, to: face), !reduceMotion else {
            withAnimation(from == .waiting && face == .on ? .easeOut(duration: 0.15) : TTMotion.fade) { shown = face }
            return
        }
        withAnimation(TTMotion.swell) { scale = 1.3 }
        Task {
            try? await Task.sleep(for: Self.swellTime)
            // The new glyph at the top of the swell, with no fade, then the spring back.
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) { shown = wanted }
            withAnimation(TTMotion.pop) { scale = 1 }
        }
    }

    /// The pop marks the alert turning on: into the wait (from the outline, the hold or the crossed bell), or straight on
    /// when no wait was drawn. Off settles instead (TT-191).
    private static func pops(from: BellFace, to: BellFace) -> Bool {
        switch to {
        case .waiting: true
        case .on: from != .waiting
        case .off, .asking, .crossed: false
        }
    }

    /// `TTMotion.swell`'s length.
    private static let swellTime: Duration = .milliseconds(100)
    /// The hold while iOS asks (the Motion board's First tap ever).
    private static let askingScale: CGFloat = 1.12
}

extension EnvironmentValues {
    /// True while the alert setup sheet is up (from opening it until it is gone), so a bell whose alert it changed pops
    /// where the rider can see it (TT-166). RootView sets it.
    @Entry var holdsBellPop: Bool = false
}

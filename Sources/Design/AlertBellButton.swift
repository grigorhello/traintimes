import SwiftUI

/// The bell on a departure card (TT-141), with its pop (TT-166, D60): when the alert turns on or off the glyph swells to
/// 1.3 over 0.1 s (`TTMotion.swell`), swaps `bell` and `bell.fill` at the top, as Kavsoft does, and springs back on
/// `TTMotion.pop`. While `\.holdsBellPop` is true (the alert setup sheet is up) the bell keeps the glyph it had and pops
/// once the sheet is gone. Reduce Motion cross-fades the glyph instead.
struct AlertBellButton: View {
    let isOn: Bool
    let label: Text
    let glyph: CGFloat
    let target: CGFloat
    let action: () -> Void

    @Environment(\.holdsBellPop) private var holdsPop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The glyph drawn: it follows `isOn` at the top of the swell, or after the sheet holding it has gone.
    @State private var shownOn: Bool
    /// The latest `isOn`, read when the swell ends (the view value the task captured may be older by then).
    @State private var wanted: Bool
    @State private var scale: CGFloat = 1

    init(isOn: Bool, label: Text, glyph: CGFloat, target: CGFloat, action: @escaping () -> Void) {
        self.isOn = isOn
        self.label = label
        self.glyph = glyph
        self.target = target
        self.action = action
        _shownOn = State(initialValue: isOn)
        _wanted = State(initialValue: isOn)
    }

    var body: some View {
        IconButton(systemName: shownOn ? "bell.fill" : "bell", label: label, action: action)
            .sized(glyph: glyph, target: target)
            .scaleEffect(scale)
            .contentTransition(.opacity)
            .onChange(of: isOn) { _, isOn in
                wanted = isOn
                pop(to: isOn)
            }
            .onChange(of: holdsPop) { pop(to: wanted) }
    }

    /// Plays the pop when the glyph drawn is not the alert's, unless a sheet holds it.
    private func pop(to isOn: Bool) {
        guard !holdsPop, shownOn != isOn else { return }
        guard !reduceMotion else {
            withAnimation(TTMotion.fade) { shownOn = isOn }
            return
        }
        withAnimation(TTMotion.swell) { scale = 1.3 }
        Task {
            try? await Task.sleep(for: Self.swellTime)
            // The new glyph at the top of the swell, with no fade, then the spring back.
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) { shownOn = wanted }
            withAnimation(TTMotion.pop) { scale = 1 }
        }
    }

    /// `TTMotion.swell`'s length.
    private static let swellTime: Duration = .milliseconds(100)
}

extension EnvironmentValues {
    /// True while the alert setup sheet is up (from opening it until it is gone), so a bell whose alert it changed pops
    /// where the rider can see it (TT-166). RootView sets it.
    @Entry var holdsBellPop: Bool = false
}

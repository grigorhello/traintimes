import SwiftUI

/// Before departure's motion (TT-177, the Live-Spec motion table): the watched strip growing the countdown, the posted
/// platform pressing in, the pill's pulse. Boarding's tint and the rolling digits reuse `RideMotion.tint` and the ride's
/// countdown transition.
enum DepartureMotion {
    /// The watched strip growing the countdown.
    static let growCurve = TTMotion.Curve(response: 0.46, damping: 0.82)
    /// "Platform 7" pressing in from 0.94 as it replaces the pill.
    static let platformCurve = TTMotion.Curve(response: 0.40, damping: 0.50)
    static let platformFrom = 0.94
    /// One fade of the pending platform's pill and back (the canvas's `pp-pulse`, 0.45 to 1).
    static let pulse = 1.4
    static let pulseLow = 0.45

    static var grow: Animation { growCurve.animation }
}

/// The pending platform's pill in the departure card and its strip (TT-177): the size of a platform number, pulsing while
/// the platform is worth waiting for (D55), still otherwise, with Reduce Motion and in snapshots.
struct DeparturePill: View {
    var pulses = true
    var width: CGFloat = 64
    var height: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsRideMotion) private var playsMotion
    @State private var dimmed = false

    var body: some View {
        Capsule()
            .fill(TTColor.controlBorder)
            .frame(width: width, height: height)
            .opacity(dimmed ? DepartureMotion.pulseLow : 1)
            .onAppear { start() }
            .onChange(of: pulses) { start() }
            .accessibilityHidden(true)
    }

    private func start() {
        guard pulses, playsMotion, !reduceMotion else {
            dimmed = false
            return
        }
        withAnimation(.easeInOut(duration: DepartureMotion.pulse / 2).repeatForever(autoreverses: true)) { dimmed = true }
    }
}

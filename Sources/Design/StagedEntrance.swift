import SwiftUI

extension EnvironmentValues {
    /// False in the unit test host, so snapshots draw a sheet's content at rest instead of mid-entrance (TT-167). UI tests
    /// run the app on its own and play it.
    @Entry var playsEntranceMotion: Bool = EntranceHost.plays
}

/// The unit test bundle is not loaded into this run of the app.
private enum EntranceHost {
    static let plays = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
}

/// One beat of a sheet's staged entrance (TT-167, D65; Kavsoft's staged open, the Trip details row of the Motion board):
/// the sheet is the system's, and its content arrives after it. On its first appearance the element rides `rise` points
/// down into place and grows from `scale` on `spring`, fading in over 0.15 s (`TTMotion.appear`), `delay` seconds after it
/// appears; with no spring it only fades. It plays once per appearance, never on a re-render or a live update. Reduce
/// Motion: a fade on `TTMotion.fade`, every beat at once.
private struct StagedEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsEntranceMotion) private var playsMotion
    let rise: CGFloat
    let scale: CGFloat
    let spring: Animation?
    let delay: Double
    @State private var arrived = false

    func body(content: Content) -> some View {
        let moves = !reduceMotion
        let rests = arrived || !moves
        // Fixed for the whole run, so the view keeps its identity; the unit test host draws the content exactly as it is.
        if playsMotion {
            content
                .opacity(arrived ? 1 : 0)
                .animation(moves ? TTMotion.appear.delay(delay) : TTMotion.fade, value: arrived)
                .scaleEffect(rests ? 1 : scale)
                .offset(y: rests ? 0 : -rise)
                .animation(moves ? spring?.delay(delay) : nil, value: arrived)
                .onAppear { arrived = true }
        } else {
            content
        }
    }
}

extension View {
    /// Arrives with the staged entrance: from `rise` points up and `scale` times its size to rest on `spring`, fading in,
    /// `delay` seconds after it appears.
    func stagedEntrance(rise: CGFloat = 0, scale: CGFloat = 1, on spring: Animation? = nil, delay: Double = 0) -> some View {
        modifier(StagedEntrance(rise: rise, scale: scale, spring: spring, delay: delay))
    }
}

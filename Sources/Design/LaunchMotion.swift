import SwiftUI

/// The first second of a cold start, "Bloom" (TT-206, D94), and the welcome after it, by name: the numbers of
/// `splash.css` and `first-d.css` on the Route and stations canvas. `o` is a line's distance from the centre line
/// (Barrie 0, Kitchener and Richmond Hill 1, Milton and Stouffville 2, the Lakeshores 3). Reduce Motion turns every move
/// into a 0.2 s cross-fade and drops the glint.
enum LaunchMotion {
    /// The mark springing from 0.9 to 1 (spring 0.44, 0.62), 80 ms in.
    static var mark: Animation { TTMotion.cascade.delay(0.08) }
    /// Each line drawing out of the mark, 560 ms, 220 ms + o × 50 ms in.
    static func draw(_ order: Int) -> Animation {
        .timingCurve(0.3, 0.6, 0.2, 1, duration: 0.56).delay(0.22 + 0.05 * Double(order))
    }
    /// A line's two station rings fading in, 160 ms, 560 ms + o × 50 ms in.
    static func rings(_ order: Int) -> Animation { .easeOut(duration: 0.16).delay(0.56 + 0.05 * Double(order)) }
    /// A line's tile popping in at its tip from 0.6, 600 ms + o × 50 ms in.
    static func tile(_ order: Int) -> Animation { TTMotion.cascade.delay(0.6 + 0.05 * Double(order)) }
    /// The name "Train Times" rising 10 pt, 760 ms in.
    static var name: Animation { TTMotion.glide.delay(0.76) }
    /// Everything is still by then; the welcome (or the fold) follows.
    static let bloomDuration: Duration = .milliseconds(1300)

    /// A saved route: the lines and tiles fold back into the mark (the draw reversed), then the mark fades.
    static var fold: Animation { .timingCurve(0.7, 0, 0.84, 0, duration: 0.3) }
    static var markFade: Animation { .easeOut(duration: 0.2).delay(0.24) }
    static let foldDuration: Duration = .milliseconds(460)

    /// The splash becoming the welcome: the picture glides down 64 pt as the mark eases from 96 to 76 pt.
    static var glide: Animation { TTMotion.glide }
    /// The splash's name fading out.
    static var nameOut: Animation { .easeOut(duration: 0.18) }
    /// The welcome's words rising 10 pt, 120 ms after the glide; the button 120 ms after them; the footnote 80 ms later.
    static var words: Animation { TTMotion.glide.delay(0.12) }
    static var button: Animation { TTMotion.glide.delay(0.24) }
    static var footnote: Animation { .easeOut(duration: 0.3).delay(0.32) }

    /// The welcome letting go as step 1 arrives, 180 ms.
    static var letGo: Animation { .easeOut(duration: 0.18) }
    /// A tile flying from the picture to its row, or to Schedule's line seat: the glide spring, 24 ms a tile apart.
    static func fly(_ index: Int) -> Animation { TTMotion.glide.delay(0.024 * Double(index)) }
    /// Step 1's card surface fading in, 260 ms from 160 ms; each name, 300 ms from 280 ms + i × 24 ms; the question rising
    /// 380 ms from 140 ms.
    static var card: Animation { .easeOut(duration: 0.26).delay(0.16) }
    static func lineName(_ index: Int) -> Animation { .easeOut(duration: 0.3).delay(0.28 + 0.024 * Double(index)) }
    static var question: Animation { TTMotion.glide.delay(0.14) }

    /// The glint running down one line, tip to hub: a 16 pt white dash, 910 ms, one line every 1.3 s, the first 2.4 s
    /// after the welcome settles (the connector glint of D80).
    static let glintDuration = 0.91
    static let glintEvery = 1.3
    static let glintFirst = 2.4
    static let glintLength: CGFloat = 16

    /// Reduce Motion's cross-fade.
    static var fade: Animation { .easeInOut(duration: 0.2) }

    /// Where Bloom goes once it has played: a saved route folds the lines back into the mark and opens Schedule; with none
    /// the splash becomes the welcome, with no cut.
    enum Exit: Equatable {
        case schedule, welcome
    }

    static func exit(savedRoute: Route?) -> Exit {
        savedRoute == nil ? .welcome : .schedule
    }

    /// The splash plays on a cold start of the app, not in the unit test host (snapshots draw each screen at rest) and not
    /// in UI tests on the fixtures, whose launch waits stay as they were.
    static let plays = !UnitTestHost.isRunning && ProcessInfo.processInfo.environment["TT_FIXTURES"] == nil
}

extension EnvironmentValues {
    /// The launch's motion: Bloom and the welcome's entrance and glint (TT-206). False in the unit test host and fixture
    /// UI tests.
    @Entry var playsLaunchMotion: Bool = LaunchMotion.plays
}

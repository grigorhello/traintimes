import SwiftUI

/// The first seconds of a cold start, "Bloom" (TT-206, D94), and the welcome after it, by name: the numbers of
/// `splash.css` and `first-d.css` on the Route and stations canvas, at the full pace for the first launches (TT-227).
/// `o` is a line's distance from the centre line (Barrie 0, Kitchener and Richmond Hill 1, Milton and Stouffville 2, the
/// Lakeshores 3). Reduce Motion turns every move into a 0.2 s cross-fade and drops the glint.
enum LaunchMotion {
    /// The mark springing from 0.9 to 1 (spring 0.44, 0.62).
    static var mark: Animation { TTMotion.cascade.delay(timing.markDelay) }
    /// Each line drawing out of the mark, staggered by its distance from the centre line.
    static func draw(_ order: Int) -> Animation {
        .timingCurve(0.3, 0.6, 0.2, 1, duration: timing.drawDuration).delay(timing.drawStart + timing.stagger * Double(order))
    }
    /// A line's two station rings fading in.
    static func rings(_ order: Int) -> Animation {
        .easeOut(duration: timing.ringsDuration).delay(timing.ringsStart + timing.stagger * Double(order))
    }
    /// A line's tile popping in at its tip from 0.6.
    static func tile(_ order: Int) -> Animation { TTMotion.cascade.delay(timing.tileStart + timing.stagger * Double(order)) }
    /// The name "Train Times" rising 10 pt.
    static var name: Animation { TTMotion.glide.delay(timing.nameDelay) }
    /// Everything is still by then (the full pace holds the finished network for a beat); the welcome (or the fold) follows.
    static var bloomDuration: Duration { timing.bloom }

    /// A saved route: the lines and tiles fold back into the mark (the draw reversed), then the mark fades.
    static var fold: Animation { .timingCurve(0.7, 0, 0.84, 0, duration: timing.foldDuration) }
    static var markFade: Animation { .easeOut(duration: timing.markFadeDuration).delay(timing.markFadeDelay) }
    static var foldDuration: Duration { timing.foldTotal }

    // MARK: Pace (TT-227)

    /// The first launches play Bloom slower, with a held beat, so its motion reads; after them it is quick again, since a
    /// rider often opens the app in a hurry (Grigor, 2026-11-18: "first a few times like 5-10 times then quick").
    enum Pace: Equatable, Sendable {
        case full, quick
    }

    /// Splashes that play at the full pace: the first 8 that finished on this install.
    static let fullLaunches = 8
    static let countKey = "launch.bloomCount"

    static func paceAfter(played count: Int) -> Pace {
        count < fullLaunches ? .full : .quick
    }

    /// This launch's pace, read once per process (a cold start) so it never changes mid-splash.
    static let pace: Pace = plays ? paceAfter(played: UserDefaults.standard.integer(forKey: countKey)) : .quick

    /// Counts a splash that played to its end (the fold began, or the welcome took over), so a launch in the background
    /// that never showed it does not use up a full one.
    static func recordPlayed(defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: countKey) < fullLaunches else { return }
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    /// Bloom's numbers (`o` is a line's order in the stagger). Quick is TT-206's: about 1.8 s from the launch still to
    /// Schedule. Full is about 2.6 s: each move about 1.3 times as long and the finished network held for half a second.
    struct Timing: Equatable, Sendable {
        var markDelay: Double
        /// The first line's draw starts here; each order `o` adds `stagger`.
        var drawStart: Double
        var stagger: Double
        var drawDuration: Double
        var ringsStart: Double
        var ringsDuration: Double
        var tileStart: Double
        var nameDelay: Double
        var bloom: Duration
        var foldDuration: Double
        var markFadeDuration: Double
        var markFadeDelay: Double
        var foldTotal: Duration

        static let quick = Timing(
            markDelay: 0.08, drawStart: 0.22, stagger: 0.05, drawDuration: 0.56, ringsStart: 0.56, ringsDuration: 0.16,
            tileStart: 0.6, nameDelay: 0.76, bloom: .milliseconds(1300), foldDuration: 0.3, markFadeDuration: 0.2,
            markFadeDelay: 0.24, foldTotal: .milliseconds(460)
        )
        static let full = Timing(
            markDelay: 0.1, drawStart: 0.28, stagger: 0.07, drawDuration: 0.72, ringsStart: 0.72, ringsDuration: 0.2,
            tileStart: 0.78, nameDelay: 0.98, bloom: .milliseconds(2100), foldDuration: 0.36, markFadeDuration: 0.24,
            markFadeDelay: 0.28, foldTotal: .milliseconds(520)
        )
    }

    static var timing: Timing { pace == .full ? .full : .quick }

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
    /// True while the saved route's splash still covers Schedule (TT-227): Schedule loads under it, and its cards' cascade
    /// and the Now pulse wait to play until it lifts.
    @Entry var launchCovers: Bool = false
}

import SwiftUI

/// Schedule's Feedback button asking (TT-228, D106; the Schedule canvas, board 24, `feedback-nudge.css`): the bubble turns
/// into the question bubble, tilts like a head asking and the button fills solid, holds, then goes back. About 2.5 s,
/// played once per showing. Nothing overshoots: nothing was touched (D59, D95). No haptic (D95 rule 1).
enum FeedbackNudgeMotion {
    /// Where the button is in the play.
    struct Pose: Equatable {
        /// The solid accent fill, the on-accent glyph and the button grown.
        var filled = false
        /// The question bubble in place of the text bubble.
        var asks = false
        /// The glyph tilted to −10° and grown to 1.08.
        var tilted = false

        static let rest = Pose()
        /// As it asks, about 1000 ms in: what the snapshots freeze.
        static let asking = Pose(filled: true, asks: true, tilted: true)
    }

    /// The round button grows to this; the labelled pill to `pillScale`.
    static let buttonScale: CGFloat = 1.14
    static let pillScale: CGFloat = 1.06
    static let tilt: Double = -10
    static let glyphScale: CGFloat = 1.08

    /// Ease-out with no overshoot, the canvas's (0.2, 0.9, 0.25, 1).
    private static func out(_ duration: Double) -> Animation { .timingCurve(0.2, 0.9, 0.25, 1, duration: duration) }

    /// One change of the pose, `at` seconds from the start.
    struct Step {
        let at: Double
        let animation: Animation
        let apply: (inout Pose) -> Void
    }

    /// The play, in order. Reduce Motion keeps the fill and cross-fades the glyph (the view draws no tilt or growth then).
    static var steps: [Step] {
        [
            // 0–420: the fill, the glyph's colour and the button's size.
            Step(at: 0, animation: out(0.42)) { $0.filled = true },
            // The lines give way to the question mark inside the bubble (180–700 on the canvas).
            Step(at: 0.06, animation: out(0.5)) { $0.asks = true },
            // 140–560: the tilt.
            Step(at: 0.14, animation: out(0.42)) { $0.tilted = true },
            // 700–1850 it asks; then the mark leaves and the lines come back (1850–2520).
            Step(at: 1.85, animation: .easeInOut(duration: 0.5)) { $0.asks = false },
            Step(at: 1.90, animation: .easeInOut(duration: 0.4)) { $0.tilted = false },
            // 1950–2400: the fill and size go back.
            Step(at: 1.95, animation: .easeInOut(duration: 0.45)) { $0.filled = false }
        ]
    }

    /// The whole play, to the last line written again.
    static let duration: Double = 2.52
}

import SwiftUI

/// Schedule's Feedback button asking (TT-228, D112; drawn with a bounce since TT-252, D128; the Schedule canvas, board 24,
/// `feedback-nudge.css`): the bubble's two lines pull back, a question mark is drawn inside it, the bubble tilts like a head
/// asking and the button fills solid and bounces bigger and smaller, then the mark is erased and the lines are written
/// again. About 2.6 s, played by `KeyframeAnimator` on the render clock, so no step waits on a timer. No haptic (D95 rule 1).
enum FeedbackNudgeMotion {
    /// One frame of the play. Every value is at rest in `rest`; `asking` is the moment the snapshots freeze.
    struct Frame: Equatable {
        /// The button's size (the round button's; the labelled pill bounces less, `pillScale(_:)`).
        var scale: CGFloat = 1
        /// The solid accent over the soft one, 0 to 1.
        var fill: Double = 0
        /// The glyph and label in the on-accent colour from 0.5. It flips at once where the fill is half way: faded with
        /// the fill, the glyph and the fill pass through the same green and the icon blinks out (D112).
        var ink: Double = 0
        var tilt: Double = 0
        var glyphScale: CGFloat = 1
        /// How much of each text line is drawn, from its left end.
        var upper: CGFloat = 1
        var lower: CGFloat = 1
        /// The question mark's hook, drawn from `hookFrom` to `hookTo` along its path.
        var hookFrom: CGFloat = 0
        var hookTo: CGFloat = 0
        /// The question mark's dot, 0 to 1 (it pops a little past 1).
        var dot: CGFloat = 0

        static let rest = Frame()
        /// As it asks, about 1000 ms in.
        static let asking = Frame(
            scale: FeedbackNudgeMotion.buttonScale, fill: 1, ink: 1, tilt: FeedbackNudgeMotion.tilt, glyphScale: FeedbackNudgeMotion.glyphScale, upper: 0, lower: 0, hookFrom: 0, hookTo: 1, dot: 1
        )
    }

    /// The round button settles at this while it asks; the bounce goes past it both ways.
    static let buttonScale: CGFloat = 1.15
    /// The labelled pill moves this share of the round button's bounce, so a wide pill does not crowd the line's name.
    static let pillShare: CGFloat = 0.45
    static let tilt: Double = -10
    static let glyphScale: CGFloat = 1.08

    static func pillScale(_ scale: CGFloat) -> CGFloat { 1 + (scale - 1) * pillShare }

    /// The whole play, to the last line written again.
    static let duration: Double = 2.6

    /// The canvas's ease-out, (0.2, 0.9, 0.25, 1).
    private static var out: UnitCurve { UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.9), endControlPoint: UnitPoint(x: 0.25, y: 1)) }
    /// The pop and the bigger-and-smaller pulses after it (D128: Grigor asked for a bounce you cannot miss).
    private static var pop: Spring { Spring(duration: 0.55, bounce: 0.7) }
    private static var beat: Spring { Spring(duration: 0.42, bounce: 0.65) }
    private static var settle: Spring { Spring(duration: 0.5, bounce: 0.35) }
    private static var lean: Spring { Spring(duration: 0.45, bounce: 0.45) }

    /// The play's frame `time` seconds in, for tests and snapshots.
    static func frame(at time: Double) -> Frame {
        KeyframeTimeline(initialValue: Frame.rest) { keyframes() }.value(time: time)
    }

    /// The play's length as the keyframes add up.
    static var keyframesDuration: Double {
        KeyframeTimeline(initialValue: Frame.rest) { keyframes() }.duration
    }

    /// Times are seconds from the start; each track adds up to `duration` or less and ends at rest.
    @KeyframesBuilder<Frame>
    static func keyframes() -> some Keyframes<Frame> {
        // 0–1.0 the pop and its bounces; 1.0–1.88 one more beat while it asks; then back, a little under 1 and up.
        KeyframeTrack(\.scale) {
            SpringKeyframe(buttonScale, duration: 1.0, spring: pop)
            CubicKeyframe(1.23, duration: 0.16)
            SpringKeyframe(buttonScale, duration: 0.72, spring: beat)
            SpringKeyframe(1, duration: 0.64, spring: settle)
            // A spring cut short can stop a hair off; the last frames land exactly at rest.
            LinearKeyframe(1, duration: 0.08)
        }
        // 0–300 the fill; back 1950–2400.
        KeyframeTrack(\.fill) {
            LinearKeyframe(1, duration: 0.3, timingCurve: out)
            LinearKeyframe(1, duration: 1.65)
            LinearKeyframe(0, duration: 0.45, timingCurve: .easeInOut)
        }
        // The colour flips where the fill is half way: 60 ms in, 2175 ms on the way back.
        KeyframeTrack(\.ink) {
            LinearKeyframe(0, duration: 0.06)
            MoveKeyframe(1)
            LinearKeyframe(1, duration: 2.115)
            MoveKeyframe(0)
        }
        // 140–640 the lean, with a small sway; back 1900–2500.
        KeyframeTrack(\.tilt) {
            LinearKeyframe(0, duration: 0.14)
            SpringKeyframe(tilt, duration: 0.5, spring: lean)
            LinearKeyframe(tilt, duration: 1.26)
            SpringKeyframe(0, duration: 0.6, spring: settle)
            LinearKeyframe(0, duration: 0.1)
        }
        KeyframeTrack(\.glyphScale) {
            LinearKeyframe(1, duration: 0.14)
            SpringKeyframe(glyphScale, duration: 0.5, spring: lean)
            LinearKeyframe(glyphScale, duration: 1.26)
            SpringKeyframe(1, duration: 0.6, spring: settle)
            LinearKeyframe(1, duration: 0.1)
        }
        // The lines pull back to their left ends (lower 0–160, upper 60–220) and are written again like typing (upper
        // 2200–2400, lower 2330–2520).
        KeyframeTrack(\.upper) {
            LinearKeyframe(1, duration: 0.06)
            LinearKeyframe(0, duration: 0.16, timingCurve: .easeIn)
            LinearKeyframe(0, duration: 1.98)
            LinearKeyframe(1, duration: 0.2, timingCurve: .easeOut)
        }
        KeyframeTrack(\.lower) {
            LinearKeyframe(0, duration: 0.16, timingCurve: .easeIn)
            LinearKeyframe(0, duration: 2.17)
            LinearKeyframe(1, duration: 0.19, timingCurve: .easeOut)
        }
        // The hook is drawn from its top-left end 180–540, erased from the same end 1900–2150, then both ends go back to
        // the start together, so nothing shows.
        KeyframeTrack(\.hookTo) {
            LinearKeyframe(0, duration: 0.18)
            LinearKeyframe(1, duration: 0.36, timingCurve: out)
            LinearKeyframe(1, duration: 1.66)
            MoveKeyframe(0)
        }
        KeyframeTrack(\.hookFrom) {
            LinearKeyframe(0, duration: 1.9)
            LinearKeyframe(1, duration: 0.25, timingCurve: .easeInOut)
            LinearKeyframe(1, duration: 0.05)
            MoveKeyframe(0)
        }
        // The dot pops in 520–820 and shrinks away 1850–1980.
        KeyframeTrack(\.dot) {
            LinearKeyframe(0, duration: 0.52)
            SpringKeyframe(1, duration: 0.3, spring: Spring(duration: 0.3, bounce: 0.5))
            LinearKeyframe(1, duration: 1.03)
            LinearKeyframe(0, duration: 0.13, timingCurve: .easeIn)
        }
    }
}

/// The feedback bubble drawn in a 24-unit box (board 24's paths, `feedback-nudge.css`): the outline always, the two text
/// lines and the question mark as far as the frame says. With `crossFades` (Reduce Motion) nothing is trimmed: the lines
/// and the mark fade instead.
struct FeedbackGlyph: View {
    var frame = FeedbackNudgeMotion.Frame.rest
    var crossFades = false
    var size: CGFloat = 20

    var body: some View {
        let style = StrokeStyle(lineWidth: size * 1.9 / 24, lineCap: .round, lineJoin: .round)
        ZStack {
            FeedbackGlyphShape.bubble.stroke(style: style)
            if crossFades {
                FeedbackGlyphShape.upperLine.stroke(style: style).opacity(Double(frame.upper))
                FeedbackGlyphShape.lowerLine.stroke(style: style).opacity(Double(frame.lower))
                FeedbackGlyphShape.hook.stroke(style: style).opacity(Double(max(0, frame.hookTo - frame.hookFrom)))
                FeedbackGlyphShape.dot.opacity(Double(min(frame.dot, 1)))
            } else {
                line(.upperLine, frame.upper, style)
                line(.lowerLine, frame.lower, style)
                if frame.hookTo - frame.hookFrom > 0.005 {
                    // A short piece of the hook is only its round cap, which reads as the dot: it fades in and out over the
                    // first and last tenth (the simulator check saw a lone dot as the erase ended).
                    FeedbackGlyphShape.hook.trim(from: frame.hookFrom, to: frame.hookTo).stroke(style: style)
                        .opacity(Double(min(1, (frame.hookTo - frame.hookFrom) / 0.12)))
                }
                if frame.dot > 0.01 {
                    FeedbackGlyphShape.dot.scale(frame.dot, anchor: FeedbackGlyphShape.dotCentre)
                }
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func line(_ shape: FeedbackGlyphShape, _ drawn: CGFloat, _ style: StrokeStyle) -> some View {
        if drawn > 0.01 { shape.trim(from: 0, to: drawn).stroke(style: style) }
    }
}

/// The glyph's pieces, from the SVG's 24 × 24 viewBox.
struct FeedbackGlyphShape: Shape {
    enum Piece { case bubble, upperLine, lowerLine, hook, dot }
    let piece: Piece

    static let bubble = FeedbackGlyphShape(piece: .bubble)
    static let upperLine = FeedbackGlyphShape(piece: .upperLine)
    static let lowerLine = FeedbackGlyphShape(piece: .lowerLine)
    static let hook = FeedbackGlyphShape(piece: .hook)
    static let dot = FeedbackGlyphShape(piece: .dot)
    static let dotCentre = UnitPoint(x: 12 / 24, y: 14.2 / 24)

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit) }
        var path = Path()
        switch piece {
        case .bubble:
            // M5.5 4.5h13a2.5 2.5 0 0 1 2.5 2.5v8a2.5 2.5 0 0 1-2.5 2.5H11l-4.6 3.4c-.4.3-.9 0-.9-.4v-3H5.5A2.5 2.5 0 0 1 3 15V7…z
            let radius = 2.5 * unit
            path.move(to: p(5.5, 4.5))
            path.addLine(to: p(18.5, 4.5))
            path.addArc(tangent1End: p(21, 4.5), tangent2End: p(21, 7), radius: radius)
            path.addLine(to: p(21, 15))
            path.addArc(tangent1End: p(21, 17.5), tangent2End: p(18.5, 17.5), radius: radius)
            path.addLine(to: p(11, 17.5))
            path.addLine(to: p(6.4, 20.9))
            path.addCurve(to: p(5.5, 20.5), control1: p(6.0, 21.2), control2: p(5.5, 20.9))
            path.addLine(to: p(5.5, 17.5))
            path.addArc(tangent1End: p(3, 17.5), tangent2End: p(3, 15), radius: radius)
            path.addLine(to: p(3, 7))
            path.addArc(tangent1End: p(3, 4.5), tangent2End: p(5.5, 4.5), radius: radius)
            path.closeSubpath()
        case .upperLine:
            path.move(to: p(7.5, 9))
            path.addLine(to: p(16.5, 9))
        case .lowerLine:
            path.move(to: p(7.5, 12.5))
            path.addLine(to: p(13.5, 12.5))
        case .hook:
            // M9.9 8.7a2.1 2.1 0 1 1 3.2 1.8c-.7.42-1.1.9-1.1 1.6: the arc (centre 12, 8.71) over the top from its left,
            // laid out as short lines so its direction never depends on how the arc call reads a flipped y axis.
            let start = -179.7 * Double.pi / 180
            let end = 58.4 * Double.pi / 180
            let steps = 36
            for step in 0...steps {
                let angle = start + (end - start) * Double(step) / Double(steps)
                let point = p(12 + 2.1 * CGFloat(cos(angle)), 8.711 + 2.1 * CGFloat(sin(angle)))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.addCurve(to: p(12, 12.1), control1: p(12.4, 10.92), control2: p(12, 11.4))
        case .dot:
            path.addEllipse(in: CGRect(origin: p(12 - 1.1, 14.2 - 1.1), size: CGSize(width: 2.2 * unit, height: 2.2 * unit)))
        }
        return path
    }
}

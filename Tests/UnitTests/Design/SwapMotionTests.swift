import XCTest
@testable import TrainTimes

/// The swap motion (TT-165, D59) as numbers: what the route card draws at any moment after a tap, against the canvas's
/// Swap-Motion-B board (the Motion-Spec table: 0, 130, 300 and 650 ms).
final class SwapMotionTests: XCTestCase {
    private let step: CGFloat = 49

    /// The closed form is the spring the canvas sampled: the same values at the same fractions of its durations.
    func testSpringsMatchTheCanvasCurves() {
        XCTAssertEqual(TTMotion.crossCurve.progress(at: 0), 0)
        XCTAssertEqual(TTMotion.crossCurve.progress(at: 0.65 * 0.2), 0.5114, accuracy: 0.001)
        XCTAssertEqual(TTMotion.crossCurve.progress(at: 0.65 * 0.5), 1.0089, accuracy: 0.001)
        XCTAssertEqual(TTMotion.crossCurve.progress(at: 0.65 * 0.6), 1.0307, accuracy: 0.001)
        XCTAssertEqual(TTMotion.turnCurve.progress(at: 0.76 * 0.4), 1.1067, accuracy: 0.001)
        XCTAssertEqual(TTMotion.pressCurve.progress(at: 0.75 * 0.3), 1.1623, accuracy: 0.001)
        XCTAssertEqual(TTMotion.crossCurve.progress(at: 3), 1, accuracy: 0.0001)
    }

    /// 0 ms: the names have traded in the data and each still stands in the other's row, the arrows are a half turn back
    /// and the button is pressed.
    func testTheTapStartsFromTheOldPicture() {
        let pose = SwapMotion.pose(at: 0, step: step)
        XCTAssertEqual(pose.from, SwapMotion.NamePose(y: step))
        XCTAssertEqual(pose.to, SwapMotion.NamePose(y: -step))
        XCTAssertEqual(pose.arrowDegrees, -180)
        XCTAssertEqual(pose.buttonScale, SwapMotion.pressScale, accuracy: 0.0001)
        XCTAssertEqual(pose.dotLights, [0, 0, 0])
        XCTAssertEqual(pose.pinScale, 1)
    }

    /// Every spring has settled by the end: the card is drawn at rest.
    func testTheCardIsAtRestAfterTheMotion() {
        XCTAssertEqual(SwapMotion.pose(at: SwapMotion.duration, step: step), SwapMotion.rest)
        XCTAssertEqual(SwapMotion.pose(at: 5, step: step), SwapMotion.rest)
        // Just before the end it is within a fraction of a point of rest, so nothing jumps.
        let late = SwapMotion.pose(at: SwapMotion.duration - 0.001, step: step)
        XCTAssertEqual(late.from.y, 0, accuracy: 0.05)
        XCTAssertEqual(late.arrowDegrees, 0, accuracy: 0.5)
        XCTAssertEqual(late.buttonScale, 1, accuracy: 0.002)
        XCTAssertEqual(late.pinScale, 1, accuracy: 0.002)
    }

    /// 130 ms: the names are at the peak of their arcs, 18 pt to the side at 1.06 times their size on a full pill, the one
    /// moving up to the right. By 60 % of 0.65 s the arc is over.
    func testTheNamesPassAlongArcsOnAPill() {
        let peak = SwapMotion.pose(at: SwapMotion.peakTime, step: step)
        XCTAssertEqual(peak.from.x, 18, accuracy: 0.001)
        XCTAssertEqual(peak.to.x, -18, accuracy: 0.001)
        XCTAssertEqual(peak.from.scale, 1.06, accuracy: 0.001)
        XCTAssertEqual(peak.to.pill, 1, accuracy: 0.001)
        // They are still on their way: the move is a little over a quarter done, the names near the middle.
        XCTAssertGreaterThan(peak.from.y, 20)
        XCTAssertLessThan(peak.to.y, -20)

        let done = SwapMotion.pose(at: SwapMotion.restTime, step: step)
        for name in [done.from, done.to] {
            XCTAssertEqual(name.x, 0)
            XCTAssertEqual(name.scale, 1)
            XCTAssertEqual(name.pill, 0)
        }
    }

    /// 300 ms: the names have landed and give a little past their rows (the spring overshoots by about 3 %, 1.5 pt of 49)
    /// before they settle.
    func testTheNamesLandAndSettleSlightlyPast() {
        let landed = SwapMotion.pose(at: 0.39, step: step)
        XCTAssertLessThan(landed.from.y, 0)
        XCTAssertGreaterThan(landed.to.y, 0)
        XCTAssertEqual(abs(landed.from.y), 1.5, accuracy: 0.5)
    }

    /// The arrows turn a half turn and swing about 19° past upright; the button presses and rebounds.
    func testArrowsSwingPastUprightAndTheButtonRebounds() {
        let moments = stride(from: 0.0, through: 0.9, by: 0.005).map { SwapMotion.pose(at: $0, step: step) }
        XCTAssertEqual(moments.map(\.arrowDegrees).max() ?? 0, 19, accuracy: 1)
        XCTAssertGreaterThanOrEqual(moments.map(\.arrowDegrees).min() ?? 0, -180)
        XCTAssertEqual(moments.map(\.buttonScale).max() ?? 0, 1.02, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(moments.map(\.buttonScale).min() ?? 0, SwapMotion.pressScale)
    }

    /// The dots light up one after the other from the top, each fully at its own peak; the pin pops once the names land.
    func testTheRailLightsUpTopToBottomAndThePinPops() {
        // The first dot peaks 40 ms plus 35 % of 0.32 s in, the next 70 ms later, the third 70 ms after that.
        let first = SwapMotion.dotStart + 0.35 * SwapMotion.dotLength
        let early = SwapMotion.pose(at: first, step: step).dotLights
        XCTAssertEqual(early[0], 1, accuracy: 0.001)
        XCTAssertGreaterThan(early[1], 0)
        XCTAssertLessThan(early[1], early[0])
        XCTAssertEqual(early[2], 0)
        let last = SwapMotion.pose(at: first + 2 * SwapMotion.dotGap, step: step).dotLights
        XCTAssertEqual(last[2], 1, accuracy: 0.001)
        // All three are dark again by 0.5 s.
        XCTAssertEqual(SwapMotion.pose(at: 0.51, step: step).dotLights, [0, 0, 0])

        XCTAssertEqual(SwapMotion.pose(at: SwapMotion.pinStart, step: step).pinScale, 1)
        XCTAssertEqual(SwapMotion.pose(at: SwapMotion.pinLand, step: step).pinScale, SwapMotion.pinPeak, accuracy: 0.001)
        // It comes down on the pop spring and goes a little under 1 before it settles.
        let pins = stride(from: 0.35, through: 0.9, by: 0.005).map { SwapMotion.pose(at: $0, step: step).pinScale }
        XCTAssertLessThan(pins.min() ?? 1, 1)
        XCTAssertGreaterThan(pins.min() ?? 0, 0.9)
    }

    /// A second tap during the motion carries on from where it was: each name, drawn where it is, goes back to the row it
    /// came from, and the arrows keep turning.
    func testASecondTapContinuesFromTheCurrentPicture() {
        let elapsed = 0.2
        let before = SwapMotion.pose(at: elapsed, step: step)
        let restart = SwapMotion.pose(at: 0, step: step, carry: SwapMotion.carry(at: elapsed, step: step))

        // The name that was in the From row is now in the To row (the data swapped back): same place on screen, which is
        // its old offset less the step between the rows; and the same on the other side.
        XCTAssertEqual(restart.to.y, -step + before.from.y, accuracy: 0.001)
        XCTAssertEqual(restart.from.y, step + before.to.y, accuracy: 0.001)
        XCTAssertEqual(restart.to.x, before.from.x, accuracy: 0.001)
        XCTAssertEqual(restart.from.x, before.to.x, accuracy: 0.001)
        XCTAssertEqual(restart.to.scale, before.from.scale, accuracy: 0.001)
        XCTAssertEqual(restart.from.pill, before.to.pill, accuracy: 0.001)
        XCTAssertEqual(restart.arrowDegrees, -180 + before.arrowDegrees, accuracy: 0.001)

        // What it carried fades out, and by the end it is at rest again.
        XCTAssertEqual(SwapMotion.pose(at: SwapMotion.duration, step: step, carry: SwapMotion.carry(at: elapsed, step: step)), SwapMotion.rest)
    }

    /// A tap after the motion has ended carries nothing.
    func testATapAtRestCarriesNothing() {
        XCTAssertEqual(SwapMotion.carry(at: SwapMotion.duration, step: step), SwapMotion.Carry())
    }
}

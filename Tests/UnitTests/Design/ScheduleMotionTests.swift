import XCTest
@testable import TrainTimes

/// Schedule's motion (TT-164, D60) as numbers, against the canvas's Motion-Spec board: the cascade's stagger and poses, and
/// the Now dot's pulse.
final class ScheduleMotionTests: XCTestCase {
    /// 60 ms for the first card in view, then 40 ms apart, and the sixth card and every one after it together.
    func testCascadeDelayIsCappedAtTheSixthCard() {
        XCTAssertEqual(TTMotion.cascadeDelay(0), 0.06, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.cascadeDelay(1), 0.10, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.cascadeDelay(4), 0.22, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.cascadeDelay(5), 0.26, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.cascadeDelay(6), 0.26, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.cascadeDelay(40), 0.26, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.cascadeDelay(-1), 0.06, accuracy: 1e-9)
    }

    /// The glide and cascade springs are the curves the canvas sampled (glide over 530 ms, cascade over 670 ms).
    func testSpringsMatchTheCanvasCurves() {
        XCTAssertEqual(TTMotion.glideCurve.progress(at: 0.53 * 0.5), 1.0193, accuracy: 0.001)
        XCTAssertEqual(TTMotion.glideCurve.progress(at: 0.53 * 0.6), 1.0383, accuracy: 0.001)
        XCTAssertEqual(TTMotion.cascadeCurve.progress(at: 0.67 * 0.2), 0.7381, accuracy: 0.001)
        XCTAssertEqual(TTMotion.cascadeCurve.progress(at: 0.67 * 0.4), 1.0821, accuracy: 0.001)
    }

    /// 0 ms: the old cards are gone and the new ones have not started; each waits for its delay, unseen, 20 pt up at 0.96.
    func testCardsStartUnseenAboveTheirPlace() {
        let pose = CascadeMotion.pose(at: 0, order: 0)
        XCTAssertEqual(pose.opacity, 0)
        XCTAssertEqual(pose.offsetY, -20, accuracy: 1e-9)
        XCTAssertEqual(pose.scale, 0.96, accuracy: 1e-9)
        // The second card starts 40 ms after the first.
        XCTAssertGreaterThan(CascadeMotion.pose(at: 0.09, order: 0).opacity, 0)
        XCTAssertEqual(CascadeMotion.pose(at: 0.09, order: 1).opacity, 0)
    }

    /// 150 ms (the board's Glide frame): the first card is dropping in, nearly opaque; it is opaque 0.12 s after its start.
    func testTheFirstCardDropsInAndFadesOverATenthOfASecond() {
        let glide = CascadeMotion.pose(at: 0.15, order: 0)
        XCTAssertGreaterThan(glide.opacity, 0.8)
        XCTAssertLessThan(glide.offsetY, 0)
        XCTAssertGreaterThan(glide.offsetY, -20)
        XCTAssertEqual(CascadeMotion.pose(at: 0.06 + 0.12, order: 0).opacity, 1, accuracy: 1e-6)
    }

    /// Around 340 ms (the board's Land frame) the first card rebounds a little under 2 pt past its place, then settles.
    func testCardsReboundSlightlyThenRest() {
        let land = CascadeMotion.pose(at: 0.06 + 0.28, order: 0)
        XCTAssertGreaterThan(land.offsetY, 1)
        XCTAssertLessThan(land.offsetY, 2)
        XCTAssertGreaterThan(land.scale, 1)
        XCTAssertEqual(CascadeMotion.pose(at: CascadeMotion.duration, order: 5), CascadeMotion.rest)
        // Just before the end the last card is within a fraction of a point of rest, so nothing jumps.
        let late = CascadeMotion.pose(at: CascadeMotion.duration - 0.001, order: 5)
        XCTAssertEqual(late.offsetY, 0, accuracy: 0.05)
        XCTAssertEqual(late.scale, 1, accuracy: 0.001)
        XCTAssertEqual(late.opacity, 1, accuracy: 1e-6)
    }

    /// Rail marks and empty cards only fade; under Reduce Motion nothing moves or scales and the fade is `TTMotion.fade`'s.
    func testRailMarksAndReduceMotionOnlyFade() {
        let mark = CascadeMotion.pose(at: 0.1, order: 0, moves: false)
        XCTAssertEqual(mark.offsetY, 0)
        XCTAssertEqual(mark.scale, 1)
        XCTAssertGreaterThan(mark.opacity, 0)
        for time in stride(from: 0.0, through: 1.2, by: 0.05) {
            let pose = CascadeMotion.pose(at: time, order: 2, reduceMotion: true)
            XCTAssertEqual(pose.offsetY, 0)
            XCTAssertEqual(pose.scale, 1)
        }
        XCTAssertLessThan(CascadeMotion.pose(at: 0.06 + 0.12, order: 0, reduceMotion: true).opacity, 1)
        XCTAssertEqual(CascadeMotion.pose(at: 0.06 + 0.18, order: 0, reduceMotion: true).opacity, 1, accuracy: 1e-6)
    }

    /// The Now dot swells to 1.7 at 35 % of 0.6 s and back, while the ring spreads to 3.4 times and fades; none at rest.
    func testNowPulse() {
        XCTAssertEqual(NowPulse.pose(at: -0.1), NowPulse.rest)
        let start = NowPulse.pose(at: 0)
        XCTAssertEqual(start.dotScale, 1, accuracy: 1e-6)
        XCTAssertEqual(start.ringScale, 1, accuracy: 1e-6)
        XCTAssertEqual(start.ringOpacity, 0.6, accuracy: 1e-6)
        XCTAssertEqual(NowPulse.pose(at: 0.21).dotScale, 1.7, accuracy: 1e-6)
        let late = NowPulse.pose(at: 0.599)
        XCTAssertEqual(late.dotScale, 1, accuracy: 0.01)
        XCTAssertEqual(late.ringScale, 3.4, accuracy: 0.01)
        XCTAssertEqual(late.ringOpacity, 0, accuracy: 0.01)
        XCTAssertEqual(NowPulse.pose(at: 0.6), NowPulse.rest)
        XCTAssertEqual(NowPulse.rest.ringOpacity, 0, "No ring is drawn at rest")
    }

    /// The frame before the start is taken draws the first pose; at rest there is none.
    func testAPendingRunDrawsItsFirstFrame() {
        let now = Date()
        XCTAssertNil(MotionRun.rest.elapsed(at: now))
        XCTAssertEqual(MotionRun(pending: true).elapsed(at: now), 0)
        XCTAssertEqual(MotionRun(start: now.addingTimeInterval(-0.25)).elapsed(at: now) ?? 0, 0.25, accuracy: 1e-6)
    }
}

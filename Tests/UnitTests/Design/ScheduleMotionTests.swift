import XCTest
@testable import TrainTimes

/// Schedule's motion (TT-164, D61) as numbers, against the canvas's Motion-Spec board: the cascade's stagger and poses, and
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

    /// The Now dot swells to 1.7 at 35 % of 0.6 s and back while a ring spreads to 3.4 times and fades, a second ring 0.3 s
    /// behind it; the rule draws across from the rail and the label pops (TT-197, D80); none of it at rest.
    func testNowPulse() {
        XCTAssertEqual(NowPulse.pose(at: -0.1), NowPulse.rest)
        let start = NowPulse.pose(at: 0)
        XCTAssertEqual(start.dotScale, 1, accuracy: 1e-6)
        XCTAssertEqual(start.ringScale, 1, accuracy: 1e-6)
        XCTAssertEqual(start.ringOpacity, 0.6, accuracy: 1e-6)
        XCTAssertEqual(start.echoOpacity, 0, "The second ring waits")
        XCTAssertEqual(start.ruleReveal, 0, accuracy: 1e-6, "The rule starts at the rail")
        XCTAssertEqual(NowPulse.pose(at: 0.21).dotScale, 1.7, accuracy: 1e-6)
        XCTAssertEqual(NowPulse.pose(at: 0.225).labelScale, 1.15, accuracy: 1e-6)
        XCTAssertEqual(NowPulse.pose(at: 0.3).echoOpacity, 0.6, accuracy: 1e-6)
        let late = NowPulse.pose(at: 0.599)
        XCTAssertEqual(late.dotScale, 1, accuracy: 0.01)
        XCTAssertEqual(late.ringScale, 3.4, accuracy: 0.01)
        XCTAssertEqual(late.ringOpacity, 0, accuracy: 0.01)
        XCTAssertEqual(late.ruleReveal, 1, accuracy: 0.01, "The rule is drawn by then")
        XCTAssertEqual(NowPulse.pose(at: 0.899).echoOpacity, 0, accuracy: 0.01)
        XCTAssertEqual(NowPulse.pose(at: 0.9), NowPulse.rest)
        XCTAssertEqual(NowPulse.rest.ringOpacity, 0, "No ring is drawn at rest")
        XCTAssertEqual(NowPulse.rest.ruleReveal, 1)
    }

    /// Under Reduce Motion nothing moves: the line, dot and label dip to 45 % and come back over 0.6 s.
    func testNowPulseUnderReduceMotion() {
        let middle = NowPulse.pose(at: 0.3, reduceMotion: true)
        XCTAssertEqual(middle.opacity, 0.45, accuracy: 1e-6)
        XCTAssertEqual(middle.dotScale, 1)
        XCTAssertEqual(middle.ringOpacity, 0)
        XCTAssertEqual(middle.ruleReveal, 1)
        XCTAssertEqual(middle.labelScale, 1)
        XCTAssertEqual(NowPulse.pose(at: 0.6, reduceMotion: true), NowPulse.rest)
    }

    /// The frame before the start is taken draws the first pose; at rest there is none.
    func testAPendingRunDrawsItsFirstFrame() {
        let now = Date()
        XCTAssertNil(MotionRun.rest.elapsed(at: now))
        XCTAssertEqual(MotionRun(pending: true).elapsed(at: now), 0)
        XCTAssertEqual(MotionRun(start: now.addingTimeInterval(-0.25)).elapsed(at: now) ?? 0, 0.25, accuracy: 1e-6)
    }

    /// The cards wait unseen at their first pose from the request until its start is taken, and while new trains are still
    /// awaited; with motion off, or no clock, they are at rest.
    @MainActor func testTheCascadeCueIsPendingUntilItsStartIsTaken() {
        let clock = ScheduleMotionClock(cascadeSeen: 1)
        XCTAssertEqual(CascadeCue(clock: clock, request: 1, plays: true).run, .rest)
        XCTAssertTrue(CascadeCue(clock: clock, request: 2, plays: true).run.pending, "A new request")
        XCTAssertTrue(CascadeCue(clock: clock, request: 1, awaitsNewTrains: true, plays: true).run.pending, "Trains awaited")
        XCTAssertFalse(CascadeCue(clock: clock, request: 2, plays: false).run.pending, "Motion off")
        XCTAssertEqual(CascadeCue.rest.run, .rest)
        let start = Date()
        clock.cascadeSeen = 2
        clock.cascadeStart = start
        XCTAssertEqual(CascadeCue(clock: clock, request: 2, plays: true).run, MotionRun(start: start))
    }

    /// Each tap plays one press: 0.90 at once, back past 1 to about 1.016, at rest by 0.75 s and on every whole tap count.
    func testThePressDipsAndSpringsBackPastOne() {
        XCTAssertEqual(DayPressMotion.scale(presses: 0), 1)
        XCTAssertEqual(DayPressMotion.scale(presses: 3), 1)
        XCTAssertEqual(DayPressMotion.scale(presses: 3.0001), 0.90, accuracy: 0.001)
        XCTAssertEqual(DayPressMotion.scale(at: DayPressMotion.duration), 1)
        let samples = (1..<750).map { DayPressMotion.scale(at: Double($0) / 1000) }
        XCTAssertEqual(samples.max() ?? 0, 1.0163, accuracy: 0.002)
        XCTAssertGreaterThanOrEqual(samples.min() ?? 0, 0.90)
        XCTAssertEqual(DayPressMotion.scale(presses: 3.9999), 1, accuracy: 0.002)
    }

    /// The play's first frame looks like the lead before the tick (34 pt time, "Departing", old status), so nothing changes
    /// before the card moves; it ends departed. The Now rule waits until the card has nearly cleared it (D86).
    func testDeparturePlayStartsAsTheLead() {
        let first = DeparturePlay.departing(at: 0, wasLead: true)
        XCTAssertEqual(first.offsetY, TTTimeline.departedLift)
        XCTAssertEqual(first.timeScale, DeparturePlay.leadTimeRatio, accuracy: 1e-6)
        XCTAssertEqual(first.leadOut, 1)
        XCTAssertEqual(first.statusOut, 1)
        XCTAssertEqual(first.look, 0)
        XCTAssertEqual(DeparturePlay.departing(at: 0, wasLead: false).leadOut, 0)
        XCTAssertEqual(DeparturePlay.departing(at: 0.5, wasLead: true).leadOut, 0, accuracy: 1e-6)
        XCTAssertEqual(DeparturePlay.departing(at: DeparturePlay.duration, wasLead: true), .rest(departed: true))
        XCTAssertEqual(DeparturePlay.now(at: 0.3, glide: 7).ruleReveal, 0)
        XCTAssertEqual(DeparturePlay.now(at: DeparturePlay.duration - 0.01, glide: 7).ruleReveal, 1, accuracy: 0.01)
    }
}

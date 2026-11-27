import XCTest
@testable import TrainTimes

/// When Schedule's Feedback button asks (TT-228, D112, revised by TT-252, D128): stillness, every app open, every 2 min,
/// never by itself in fixture runs, the Testing switch and launch argument, and both events.
@MainActor
final class FeedbackNudgeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock: TestClock!
    private var recorder: RecordingAnalytics!

    /// Noon on Thursday, Nov 19, 2026, in Toronto.
    private let start = Date(timeIntervalSince1970: 1_795_107_600)

    override func setUp() async throws {
        try await super.setUp()
        defaults = .ephemeral()
        clock = TestClock(now: start)
        recorder = RecordingAnalytics.install()
    }

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func nudge(playsByItself: Bool = true) -> FeedbackNudge {
        FeedbackNudge(defaults: defaults, clock: clock, playsByItself: playsByItself)
    }

    // MARK: Stillness

    func testStillOnlyWithNothingInTheWay() {
        XCTAssertTrue(FeedbackNudge.Stillness().isStill)
        let blockers: [(inout FeedbackNudge.Stillness) -> Void] = [
            { $0.isActive = false }, { $0.isLoaded = false }, { $0.launchCovers = true }, { $0.isCovered = true },
            { $0.isPicking = true }, { $0.hasCapsule = true }, { $0.hasRideStrip = true }
        ]
        for block in blockers {
            var stillness = FeedbackNudge.Stillness()
            block(&stillness)
            XCTAssertFalse(stillness.isStill)
        }
        // A touch changes the stillness (so the wait starts again) without making Schedule busy.
        var touched = FeedbackNudge.Stillness()
        touched.touches += 1
        XCTAssertNotEqual(touched, FeedbackNudge.Stillness())
        XCTAssertTrue(touched.isStill)
    }

    // MARK: When it plays

    func testFirstPlayOfAnOpenComesAfterTheStillness() {
        let rule = nudge()
        XCTAssertEqual(rule.nextPlay(stillSince: start), start.addingTimeInterval(FeedbackNudge.stillness))
        XCTAssertFalse(rule.isDue(stillSince: start))
        clock.advance(seconds: FeedbackNudge.stillness)
        XCTAssertTrue(rule.isDue(stillSince: start))
    }

    func testATouchStartsTheStillnessAgain() {
        let rule = nudge()
        clock.advance(seconds: 1)
        // Schedule was touched 1 s in: the wait counts from then.
        XCTAssertFalse(rule.isDue(stillSince: clock.now))
        XCTAssertTrue(rule.isDue(stillSince: start))
    }

    func testRepeatsEveryTwoMinutesFromTheLastPlay() {
        let rule = nudge()
        clock.advance(seconds: 2)
        rule.play()
        XCTAssertEqual(rule.nextPlay(stillSince: start), clock.now.addingTimeInterval(FeedbackNudge.repeatEvery))
        clock.advance(seconds: 119)
        XCTAssertFalse(rule.isDue(stillSince: start))
        clock.advance(seconds: 1)
        XCTAssertTrue(rule.isDue(stillSince: start))
        rule.play()
        XCTAssertEqual(rule.playRequest, 2)
    }

    func testARepeatStillWaitsForTheStillness() {
        let rule = nudge()
        rule.play()
        clock.advance(seconds: 300)
        // Schedule just became still again (back from another tab): the stillness first, not at once.
        let stillSince = clock.now
        XCTAssertEqual(rule.nextPlay(stillSince: stillSince), stillSince.addingTimeInterval(FeedbackNudge.stillness))
    }

    func testEveryReturnFromTheBackgroundIsANewOpen() {
        let rule = nudge()
        rule.play()
        rule.wentToBackground()
        clock.advance(seconds: 20)
        rule.cameToForeground()
        let stillSince = clock.now
        XCTAssertEqual(rule.nextPlay(stillSince: stillSince), stillSince.addingTimeInterval(FeedbackNudge.stillness))
        clock.advance(seconds: FeedbackNudge.stillness)
        rule.play()
        XCTAssertEqual(recorder.events.compactMap { $0.properties["reason"] }, [.string("open"), .string("open")])
    }

    func testActiveAgainWithoutTheBackgroundIsTheSameOpen() {
        let rule = nudge()
        rule.play()
        rule.cameToForeground()
        XCTAssertEqual(rule.nextPlay(stillSince: clock.now), clock.now.addingTimeInterval(FeedbackNudge.repeatEvery))
    }

    func testKeepsPlayingAfterTheSheetOpens() {
        let rule = nudge()
        rule.play()
        rule.sheetOpened(from: .schedule)
        clock.advance(seconds: FeedbackNudge.repeatEvery)
        XCTAssertTrue(rule.isDue(stillSince: start))
    }

    func testNeverByItselfInFixtureRuns() {
        let rule = nudge(playsByItself: false)
        XCTAssertNil(rule.nextPlay(stillSince: start))
        clock.advance(seconds: 600)
        XCTAssertFalse(rule.isDue(stillSince: start))
    }

    // MARK: Testing

    func testPlayOnNextStillPlaysOnceWhereItWouldNot() {
        let rule = nudge(playsByItself: false)
        rule.playOnNextStill()
        XCTAssertEqual(rule.nextPlay(stillSince: start), start.addingTimeInterval(FeedbackNudge.stillness))
        rule.play()
        XCTAssertEqual(rule.showings, 1)
        XCTAssertNil(rule.nextPlay(stillSince: clock.now), "it plays once per tap")
    }

    func testLaunchArgumentPlaysOncePerRun() {
        defaults.set("now", forKey: FeedbackNudge.launchKey)
        let rule = nudge(playsByItself: false)
        XCTAssertTrue(rule.isForced)
        rule.play()
        XCTAssertFalse(rule.isForced)
        XCTAssertNil(rule.nextPlay(stillSince: clock.now))
    }

    // MARK: Analytics

    func testShownEventCountsTheShowingAndSaysWhy() {
        let rule = nudge()
        rule.play()
        clock.advance(seconds: FeedbackNudge.repeatEvery)
        rule.play()
        rule.playOnNextStill()
        rule.play()
        XCTAssertEqual(recorder.events, [
            AnalyticsEvent("feedback_nudge_shown", ["count": .int(1), "reason": .string("open")]),
            AnalyticsEvent("feedback_nudge_shown", ["count": .int(2), "reason": .string("repeat")]),
            AnalyticsEvent("feedback_nudge_shown", ["count": .int(3), "reason": .string("testing")])
        ])
    }

    func testOpenedWithinAMinuteOfTheNudgeIsAfterNudge() {
        let rule = nudge()
        rule.play()
        clock.advance(seconds: 20)
        rule.sheetOpened(from: .schedule)
        XCTAssertEqual(
            recorder.events.last,
            AnalyticsEvent("feedback_opened", ["source": .string("schedule"), "after_nudge": .bool(true), "nudges_seen": .int(1)])
        )
    }

    func testOpenedLongAfterOrWithoutANudgeIsNotAfterNudge() {
        let rule = nudge()
        rule.sheetOpened(from: .settings)
        XCTAssertEqual(
            recorder.events.last,
            AnalyticsEvent("feedback_opened", ["source": .string("settings"), "after_nudge": .bool(false), "nudges_seen": .int(0)])
        )
        rule.play()
        clock.advance(seconds: 61)
        rule.sheetOpened(from: .schedule)
        XCTAssertEqual(recorder.events.last?.properties["after_nudge"], .bool(false))
    }
}

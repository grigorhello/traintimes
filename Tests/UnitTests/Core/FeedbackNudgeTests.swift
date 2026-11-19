import XCTest
@testable import TrainTimes

/// When Schedule's Feedback button asks (TT-228, D112): stillness, one try per app open, once a day, not in the first two
/// days, stop on open or after 5 showings, the Testing reset, and both events.
@MainActor
final class FeedbackNudgeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock: TestClock!
    private var recorder: RecordingAnalytics!

    /// Noon on Thursday, Nov 19, 2026, in Toronto: the install's first day.
    private let firstDay = Date(timeIntervalSince1970: 1_795_107_600)

    override func setUp() async throws {
        try await super.setUp()
        defaults = .ephemeral()
        clock = TestClock(now: firstDay)
        recorder = RecordingAnalytics.install()
    }

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func nudge(playsByItself: Bool = true) -> FeedbackNudge {
        FeedbackNudge(defaults: defaults, clock: clock, playsByItself: playsByItself)
    }

    private func advance(days: Int) {
        clock.advance(seconds: TimeInterval(days) * 24 * 3600)
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
        // A touch changes the stillness (so the wait restarts and is cancelled) without making Schedule busy.
        var touched = FeedbackNudge.Stillness()
        touched.touches += 1
        XCTAssertNotEqual(touched, FeedbackNudge.Stillness())
        XCTAssertTrue(touched.isStill)
    }

    // MARK: When it may play

    func testNotInTheFirstTwoDays() {
        let rule = nudge()
        XCTAssertFalse(rule.isDue)
        advance(days: 1)
        XCTAssertFalse(nudge().isDue)
        advance(days: 1)
        XCTAssertTrue(nudge().isDue)
    }

    func testTheFirstDayCountsByTorontoCalendarDay() {
        // 11:30 PM on the first day: two calendar days later is only 24.5 hours on.
        clock.set(firstDay.addingTimeInterval(11.5 * 3600))
        _ = nudge()
        clock.advance(seconds: 24.5 * 3600 + 60)
        XCTAssertTrue(nudge().isDue)
    }

    func testOneTryPerAppOpen() {
        _ = nudge()
        advance(days: 2)
        let rule = nudge()
        XCTAssertTrue(rule.stillnessBegan())
        // The wait was cancelled by a touch: no second try until the next app open.
        XCTAssertFalse(rule.stillnessBegan())
        rule.wentToBackground()
        clock.advance(seconds: 5 * 60)
        rule.cameToForeground()
        XCTAssertFalse(rule.stillnessBegan(), "back within 10 min is the same app open")
        rule.wentToBackground()
        clock.advance(seconds: 11 * 60)
        rule.cameToForeground()
        XCTAssertTrue(rule.stillnessBegan(), "back after more than 10 min is a new app open")
    }

    func testOncePerDay() {
        _ = nudge()
        advance(days: 2)
        var rule = nudge()
        XCTAssertTrue(rule.stillnessBegan())
        rule.play()
        XCTAssertEqual(rule.playRequest, 1)
        clock.advance(seconds: 3600)
        rule = nudge()
        XCTAssertFalse(rule.isDue, "it already played today")
        advance(days: 1)
        XCTAssertTrue(nudge().isDue)
    }

    func testStopsAfterFiveShowings() {
        _ = nudge()
        for _ in 1...FeedbackNudge.maxShowings {
            advance(days: 2)
            let rule = nudge()
            XCTAssertTrue(rule.stillnessBegan())
            rule.play()
        }
        advance(days: 2)
        XCTAssertFalse(nudge().isDue)
        XCTAssertEqual(recorder.events.compactMap { $0.properties["count"] }, (1...5).map { .int($0) })
    }

    func testStopsForGoodOnceTheSheetOpens() {
        _ = nudge()
        advance(days: 2)
        nudge().sheetOpened(from: .settings)
        advance(days: 3)
        XCTAssertFalse(nudge().isDue)
    }

    func testNeverByItselfInFixtureRuns() {
        _ = nudge(playsByItself: false)
        advance(days: 3)
        XCTAssertFalse(nudge(playsByItself: false).isDue)
    }

    // MARK: Testing

    func testPlayOnNextStillClearsTheCountersAndSkipsTheWaits() {
        let rule = nudge(playsByItself: false)
        rule.sheetOpened(from: .schedule)
        XCTAssertFalse(rule.isDue)
        rule.playOnNextStill()
        XCTAssertTrue(rule.stillnessBegan())
        XCTAssertTrue(rule.stillnessBegan(), "forced, a cancelled wait may try again")
        rule.play()
        XCTAssertEqual(rule.showings, 1)
        XCTAssertFalse(rule.isDue, "it plays once per tap")
    }

    func testLaunchArgumentPlaysOncePerRun() {
        defaults.set("now", forKey: FeedbackNudge.launchKey)
        let rule = nudge(playsByItself: false)
        XCTAssertTrue(rule.stillnessBegan())
        rule.play()
        XCTAssertFalse(rule.isDue)
    }

    // MARK: Analytics

    func testShownEventCountsTheShowing() {
        _ = nudge()
        advance(days: 2)
        let rule = nudge()
        rule.play()
        XCTAssertEqual(recorder.events, [AnalyticsEvent("feedback_nudge_shown", ["count": .int(1)])])
    }

    func testOpenedWithinAMinuteOfTheNudgeIsAfterNudge() {
        _ = nudge()
        advance(days: 2)
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
        rule.playOnNextStill()
        rule.play()
        clock.advance(seconds: 61)
        rule.sheetOpened(from: .schedule)
        XCTAssertEqual(recorder.events.last?.properties["after_nudge"], .bool(false))
    }
}

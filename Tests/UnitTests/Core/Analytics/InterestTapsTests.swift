import XCTest
@testable import TrainTimes

/// Interest taps (TT-209): taps on the same element within 2 s of each other count once, with `count`.
@MainActor
final class InterestTapsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testOneTapIsOneEventWhenTheRunEnds() {
        var taps = InterestTaps()
        XCTAssertNil(taps.tap("schedule.card.time", screen: "schedule", at: start))
        XCTAssertEqual(
            taps.finish(),
            AnalyticsEvent("interest_tapped", ["element": .string("schedule.card.time"), "screen": .string("schedule"), "count": .int(1)])
        )
        XCTAssertNil(taps.finish(), "Sent once")
    }

    func testRageTapsWithin2SecondsCountOnce() {
        var taps = InterestTaps()
        XCTAssertNil(taps.tap("trip.time", screen: "trip_details", at: start))
        XCTAssertNil(taps.tap("trip.time", screen: "trip_details", at: start.addingTimeInterval(1.5)))
        // Each tap restarts the 2 s: 3 s after the first is still 1.5 s after the second.
        XCTAssertNil(taps.tap("trip.time", screen: "trip_details", at: start.addingTimeInterval(3)))
        XCTAssertEqual(taps.finish()?.properties["count"], .int(3))
    }

    func testATapAfter2SecondsStartsANewRun() {
        var taps = InterestTaps()
        _ = taps.tap("trip.time", screen: "trip_details", at: start)
        let ended = taps.tap("trip.time", screen: "trip_details", at: start.addingTimeInterval(2))
        XCTAssertEqual(ended?.properties["count"], .int(1))
        XCTAssertEqual(taps.finish()?.properties["count"], .int(1))
    }

    func testAnotherElementEndsTheRun() {
        var taps = InterestTaps()
        _ = taps.tap("schedule.card.time", screen: "schedule", at: start)
        _ = taps.tap("schedule.card.time", screen: "schedule", at: start.addingTimeInterval(0.3))
        let ended = taps.tap("schedule.card.status", screen: "schedule", at: start.addingTimeInterval(0.6))
        XCTAssertEqual(ended?.properties["element"], .string("schedule.card.time"))
        XCTAssertEqual(ended?.properties["count"], .int(2))
        XCTAssertEqual(taps.finish()?.properties["element"], .string("schedule.card.status"))
    }

    func testTheTrackerSendsOnceThe2SecondsPass() async throws {
        let recorder = RecordingAnalytics.install()
        defer { Analytics.tracker = nil }
        Analytics.screen(.schedule)
        InterestTracker.tap("schedule.line")
        InterestTracker.tap("schedule.line")
        XCTAssertTrue(recorder.events.isEmpty, "Nothing until the run is over")
        try await Task.sleep(for: .seconds(2.5))
        XCTAssertEqual(
            recorder.events,
            [AnalyticsEvent("interest_tapped", ["element": .string("schedule.line"), "screen": .string("schedule"), "count": .int(2)])]
        )
    }
}

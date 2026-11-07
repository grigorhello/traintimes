import XCTest
@testable import TrainTimes

/// The watched-trip strip (TT-144): a watched train that has left shows above the timeline until 10 min after its
/// arrival, or until swiped away.
@MainActor
final class ScheduleWatchedStripTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    func testWatchedTrainThatLeftShowsTheStrip() async throws {
        let model = try await ScheduleViewModel.watchedFixture()
        let strip = try XCTUnwrap(model.watchedStrip(formatter))
        XCTAssertEqual(strip.id.tripId, ScheduleViewModel.watchedTripId)
        XCTAssertEqual(strip.title, "7:05 AM to Union")
        XCTAssertEqual(strip.detail, "Departed · Est. arrival 7:46 AM")
    }

    func testTwentyFourHourTimes() async throws {
        let model = try await ScheduleViewModel.watchedFixture()
        let strip = try XCTUnwrap(model.watchedStrip(TimeFormatter(format: .twentyFourHour)))
        XCTAssertEqual(strip.title, "07:05 to Union")
        XCTAssertEqual(strip.detail, "Departed · Est. arrival 07:46")
    }

    func testTrainWithoutAnAlertHasNoStrip() async throws {
        let model = try await ScheduleViewModel.watchedFixture(isWatched: false)
        XCTAssertNil(model.watchedStrip(formatter))
    }

    func testNoStripBeforeTheLiveDeparture() async throws {
        let model = try await ScheduleViewModel.watchedFixture(minute: 4)
        XCTAssertNil(model.watchedStrip(formatter))
    }

    /// "Departed" needs the live departure, as in Trip details (D32): the scheduled time passing is not enough.
    func testNoStripWithoutLiveData() async throws {
        let model = try await ScheduleViewModel.watchedFixture(hasLiveData: false)
        XCTAssertNil(model.watchedStrip(formatter))
    }

    func testStripStaysUntilTenMinutesAfterTheEstimatedArrival() async throws {
        let lastMinute = try await ScheduleViewModel.watchedFixture(minute: 55)
        XCTAssertNotNil(lastMinute.watchedStrip(formatter))
        let gone = try await ScheduleViewModel.watchedFixture(minute: 56)
        XCTAssertNil(gone.watchedStrip(formatter))
    }

    /// With no arrival estimate the strip says the scheduled arrival (D15) and counts the 10 min from it.
    func testScheduledArrivalWithoutAnEstimate() async throws {
        let model = try await ScheduleViewModel.watchedFixture(hasArrivalEstimate: false)
        XCTAssertEqual(model.watchedStrip(formatter)?.detail, "Departed · Scheduled arrival 7:45 AM")
        let lastMinute = try await ScheduleViewModel.watchedFixture(minute: 54, hasArrivalEstimate: false)
        XCTAssertNotNil(lastMinute.watchedStrip(formatter))
        let gone = try await ScheduleViewModel.watchedFixture(minute: 55, hasArrivalEstimate: false)
        XCTAssertNil(gone.watchedStrip(formatter))
    }

    func testSwipedAwayStripStaysHidden() async throws {
        let model = try await ScheduleViewModel.watchedFixture()
        let strip = try XCTUnwrap(model.watchedStrip(formatter))
        model.dismissWatchedStrip(strip.id)
        XCTAssertNil(model.watchedStrip(formatter))
        await model.refresh()
        XCTAssertNil(model.watchedStrip(formatter))
    }

    func testAnotherDayHasNoStrip() async throws {
        let model = try await ScheduleViewModel.watchedFixture()
        await model.select(model.days[1])
        XCTAssertNil(model.watchedStrip(formatter))
    }
}

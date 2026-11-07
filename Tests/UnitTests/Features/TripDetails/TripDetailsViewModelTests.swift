import XCTest
@testable import TrainTimes

/// TT-118: every fact shown comes from the feed or the schedule, and a missing estimate is left out, never guessed.
@MainActor
final class TripDetailsViewModelTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    func testOnTimeShowsExpectedDepartureAndScheduledStops() async throws {
        let model = try await TripDetailsViewModel.loadedFixture()
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.title, "7:32 AM train")
        XCTAssertEqual(details.routeName, "Oakville GO to Union Station GO")
        XCTAssertEqual(details.lineAndDay, "Lakeshore West · Thu, Nov 5")
        XCTAssertEqual(details.status, .onTime)
        XCTAssertEqual(details.scheduledDeparture, "7:32 AM")
        XCTAssertEqual(details.liveDeparture, TripDetails.Fact(label: "Expected departure", value: "7:32 AM", isLate: false))
        XCTAssertEqual(details.scheduledArrival, "8:12 AM")
        XCTAssertNil(details.estimatedArrival, "The feed gives no arrival estimate for this trip")
        XCTAssertEqual(details.platform, "Platform 2")
        XCTAssertEqual(details.stopsHeader, "Scheduled")
        XCTAssertEqual(details.stops.map(\.time), ["7:32 AM", "7:40 AM", "7:46 AM", "7:52 AM", "7:57 AM", "8:04 AM", "8:12 AM"])
        XCTAssertEqual(details.stops.map(\.isEnd), [true, false, false, false, false, false, true])
        XCTAssertEqual(details.footnote, "Arrival times are scheduled.")
        XCTAssertEqual(details.alertButton, "Alert me")
    }

    func testDelayedShowsLiveTimesInDelayInk() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(.delayed, hasAlert: true)
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.status, .delayed(minutes: 9))
        XCTAssertEqual(details.liveDeparture, TripDetails.Fact(label: "Expected departure", value: "7:41 AM", isLate: true))
        XCTAssertEqual(details.estimatedArrival, "8:21 AM")
        XCTAssertEqual(details.stopsHeader, "Expected")
        XCTAssertEqual(details.stops.map(\.name), [
            "Oakville GO", "Clarkson GO", "Port Credit GO", "Long Branch GO", "Mimico GO", "Exhibition GO", "Union Station GO",
        ])
        XCTAssertEqual(details.stops.map(\.time), ["7:41 AM", "7:49 AM", "7:55 AM", "8:01 AM", "8:06 AM", "8:13 AM", "8:21 AM"])
        XCTAssertEqual(details.footnote, "Arrival times are estimates from the live feed. Scheduled arrival 8:12 AM.")
        XCTAssertEqual(details.alertButton, "Manage alert")
        XCTAssertEqual(model.freshnessMode(formatter), .live(updated: "Updated just now"))
    }

    /// Acceptance: a trip with no estimate shows only Scheduled values and no Est. arrival cell.
    func testNoEstimateShowsOnlyScheduledValues() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(tripId: "LW-0821-20261105")
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.status, .scheduled)
        XCTAssertNil(details.liveDeparture)
        XCTAssertNil(details.estimatedArrival)
        XCTAssertEqual(details.scheduledArrival, "9:01 AM")
        XCTAssertEqual(details.platform, "Platform pending")
        XCTAssertEqual(details.stopsHeader, "Scheduled")
        XCTAssertEqual(details.stops.first?.time, "8:21 AM")
        XCTAssertEqual(details.stops.last?.time, "9:01 AM")
    }

    /// Stale live data drops every estimate (D13): the badge says Scheduled and the stops show scheduled times.
    func testStaleDataShowsNoEstimates() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(.delayed, minutesLater: 5)
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.status, .scheduled)
        XCTAssertNil(details.liveDeparture)
        XCTAssertNil(details.estimatedArrival)
        XCTAssertEqual(details.stopsHeader, "Scheduled")
        XCTAssertEqual(details.stops.first?.time, "7:32 AM")
        XCTAssertEqual(model.freshnessMode(formatter), .stale(lastReported: "7:21 AM"))
    }

    func testDepartedReplacesExpectedDepartureAndHidesAlert() async throws {
        let model = try await TripDetailsViewModel.departedFixture()
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertTrue(model.hasDeparted)
        XCTAssertEqual(details.liveDeparture, TripDetails.Fact(label: "Departed", value: "7:43 AM", isLate: true))
        XCTAssertEqual(details.estimatedArrival, "8:23 AM")
        XCTAssertEqual(details.stops.last?.time, "8:23 AM")
        XCTAssertNil(details.alertButton)
    }

    func testScheduledTrainThatHasLeftOffersNoAlert() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(tripId: "LW-0821-20261105", minutesLater: 61)
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertNil(details.liveDeparture, "Without live data the sheet never claims the train departed")
        XCTAssertNil(details.alertButton)
    }

    func testSkippedStopKeepsItsScheduledTimeStruck() async throws {
        let model = try await TripDetailsViewModel.departedFixture(skipping: ["MO"])
        let details = try XCTUnwrap(model.details(formatter))
        let mimico = try XCTUnwrap(details.stops.first { $0.id == "MO" })
        XCTAssertTrue(mimico.isSkipped)
        XCTAssertEqual(mimico.time, "7:57 AM")
        XCTAssertEqual(details.stopsHeader, "Expected")
    }

    func testUnknownTripShowsNothing() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(tripId: "LW-0000")
        XCTAssertNil(model.details(formatter))
    }
}

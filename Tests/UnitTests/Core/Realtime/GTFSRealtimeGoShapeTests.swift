import XCTest
@testable import TrainTimes

/// The shape of GO's real TripUpdates feed, read through the alert server on 2026-11-13 (TT-131, D89): departures only,
/// with the delay and the time at every stop still ahead, the last stop included, and no arrivals; stops already left
/// dropped; a cancelled trip CANCELED with every stop SKIPPED. Modelled on 20261113-LW-1031, Oakville to Aldershot.
final class GTFSRealtimeGoShapeTests: XCTestCase {
    private let day = ServiceDay(year: 2026, month: 11, day: 13)

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        day.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    /// The trip from Clarkson to Aldershot, ridden from Oakville (OA) to Aldershot (AL); GO's arrivals equal its departures.
    private var call: GTFSTimetable.Call {
        let times = [at(19, 53), at(20, 0), at(20, 6), at(20, 12), at(20, 19), at(20, 27)]
        return GTFSTimetable.Call(
            tripId: "20261113-LW-1031", stops: ["CL", "OA", "BO", "AP", "BU", "AL"],
            arrivals: times, departures: times, from: 1, to: 5
        )
    }

    private func departure(_ stop: String, _ time: Date, delay: Int) -> GTFSRealtimeFeed.StopTimeUpdate {
        GTFSRealtimeFeed.StopTimeUpdate(stopId: stop, departure: .init(delay: delay, time: time))
    }

    func testTheDestinationsDepartureIsItsArrivalEstimate() throws {
        let update = GTFSRealtimeFeed.TripUpdate(
            tripId: "20261113-LW-1031", startDate: "20261113",
            stopTimeUpdates: [
                departure("OA", at(20, 1, 16), delay: 76), departure("BO", at(20, 7, 16), delay: 76),
                departure("AP", at(20, 13, 16), delay: 76), departure("BU", at(20, 20, 16), delay: 76),
                departure("AL", at(20, 28, 16), delay: 76),
            ],
            timestamp: at(19, 54, 59)
        )
        let live = try XCTUnwrap(update.live(on: call, feedTime: at(19, 55, 2)))
        XCTAssertEqual(live.expectedDeparture, at(20, 1, 16))
        XCTAssertEqual(live.expectedArrival, at(20, 28, 16), "GO posts no arrivals: Aldershot's departure is the estimate")
        XCTAssertEqual(live.delayMinutes, 1)
    }

    func testAnArrivalStillWinsOverTheDeparture() throws {
        var last = departure("AL", at(20, 29), delay: 120)
        last.arrival = .init(time: at(20, 28))
        let update = GTFSRealtimeFeed.TripUpdate(
            tripId: "20261113-LW-1031", stopTimeUpdates: [departure("OA", at(20, 1), delay: 60), last]
        )
        XCTAssertEqual(update.live(on: call, feedTime: at(19, 55))?.expectedArrival, at(20, 28))
    }

    func testACarriedDelayIsStillNoArrivalEstimate() {
        let update = GTFSRealtimeFeed.TripUpdate(
            tripId: "20261113-LW-1031", stopTimeUpdates: [departure("OA", at(20, 5), delay: 300)]
        )
        XCTAssertNil(update.live(on: call, feedTime: at(19, 55))?.expectedArrival)
    }

    func testACancelledTripWithEveryStopSkippedIsCancelled() throws {
        let skipped = call.stops.map { GTFSRealtimeFeed.StopTimeUpdate(stopId: $0, departure: .init(delay: 0), relationship: .skipped) }
        let update = GTFSRealtimeFeed.TripUpdate(
            tripId: "20261113-LW-1031", isCancelled: true, stopTimeUpdates: skipped, timestamp: at(18, 39, 52)
        )
        let live = try XCTUnwrap(update.live(on: call, feedTime: at(19, 55)))
        XCTAssertTrue(live.isCancelled)
        XCTAssertFalse(live.isStopSkipped)
        XCTAssertEqual(live.reportedAt, at(18, 39, 52))
    }
}

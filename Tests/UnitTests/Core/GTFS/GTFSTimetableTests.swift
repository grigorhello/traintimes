import XCTest
@testable import TrainTimes

/// TT-130 against real schedules: `go-gtfs-sample.zip` is the GO Transit feed published on Nov 4, 2026 (valid Nov 4 to 27),
/// cut down to the Lakeshore West and Kitchener trains on Sun Nov 8, Mon Nov 9 and Fri Nov 27, plus one bus trip that
/// calls at Oakville and Union. Expected values were read from the full feed.
final class GTFSTimetableTests: XCTestCase {
    static func sampleZip() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: GTFSTimetableTests.self).url(forResource: "go-gtfs-sample", withExtension: "zip")))
    }

    private let sunday = ServiceDay(year: 2026, month: 11, day: 8)
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)
    private let friday = ServiceDay(year: 2026, month: 11, day: 27)

    private func timetable() throws -> GTFSTimetable {
        GTFSTimetable(feed: try GTFSFeed(zip: Self.sampleZip(), importedAt: Date(timeIntervalSince1970: 0)))
    }

    private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func ids(_ trips: [Trip]) -> [String] { trips.map(\.key.tripId) }

    private func express(_ trips: [Trip]) -> Set<String> {
        Set(trips.filter { $0.tags.contains(.express) }.map(\.key.tripId))
    }

    func testImportsRailOnly() throws {
        let timetable = try timetable()
        XCTAssertEqual(timetable.feed.lines.map(\.id), ["LW", "KI"], "Lines go by short name; the bus route is left out")
        XCTAssertEqual(timetable.feed.lines.map(\.name), ["Lakeshore West", "Kitchener"])
        XCTAssertFalse(timetable.feed.trips.contains { $0.id.contains("-56-") })
        XCTAssertEqual(timetable.stations.count, 29, "Only stations a train calls at")
        XCTAssertFalse(timetable.stations.contains { $0.id == "02300" })
        XCTAssertEqual(timetable.stations.first?.name, "Acton GO")
        XCTAssertEqual(timetable.stations.first { $0.id == "UN" }?.name, "Union Station GO")
        XCTAssertEqual(timetable.stations.first { $0.id == "UN" }?.lines, ["Kitchener", "Lakeshore West"])
        XCTAssertEqual(timetable.stations.first { $0.id == "OA" }?.lines, ["Lakeshore West"])
        XCTAssertEqual(timetable.lastServiceDay, friday)
    }

    /// TT-200 (D83): metres along Lakeshore West from Union follow the order its trains call, past the branch at
    /// Aldershot (West Harbour and Hamilton GO Centre before St. Catharines, which is nearer Union in a straight line).
    func testDistanceFromUnionFollowsTheLine() throws {
        let stations = try timetable().stations
        let ids = ["EX", "OA", "BU", "AL", "WR", "HA", "CF", "SCTH", "NI"]
        let along = ids.map { id in stations.first { $0.id == id }?.distanceFromUnion["Lakeshore West"] ?? -1 }
        XCTAssertEqual(along, along.sorted())
        XCTAssertFalse(along.contains(-1))
        XCTAssertEqual(along.first ?? 0, 3265, accuracy: 50)
        XCTAssertNil(stations.first { $0.id == "UN" }?.distanceFromUnion["Lakeshore West"])
        XCTAssertNil(stations.first { $0.id == "OA" }?.distanceFromUnion["Kitchener"])
    }

    func testLineBetweenStations() throws {
        let timetable = try timetable()
        XCTAssertEqual(timetable.line(between: "OA", and: "UN"), Line(id: "LW", name: "Lakeshore West", colorHex: "#98002e"))
        XCTAssertEqual(timetable.line(between: "BL", and: "UN"), Line(id: "KI", name: "Kitchener", colorHex: "#00853e"))
        XCTAssertNil(timetable.line(between: "OA", and: "BL"), "No train calls at both")
        XCTAssertNil(timetable.line(between: "OA", and: "XX"))
    }

    func testDirectTrainsOnAWeekday() throws {
        let trips = try timetable().trips(from: "OA", to: "UN", on: monday)
        XCTAssertEqual(trips.count, 46, "The bus trip between the same stops is not a train")
        XCTAssertEqual(trips.first?.key, TripKey(serviceDay: monday, tripId: "20261109-LW-1004"))
        XCTAssertEqual(trips.first?.scheduledDeparture, utc("2026-11-09T10:17:00Z")) // 5:17 AM
        XCTAssertEqual(trips.first?.scheduledArrival, utc("2026-11-09T11:00:00Z")) // 6:00 AM
        XCTAssertEqual(trips.first?.platform, .pending, "The static feed has no platforms")
        XCTAssertEqual(trips.last?.key.tripId, "20261109-LW-1040")
        XCTAssertEqual(trips.last?.scheduledArrival, utc("2026-11-10T05:15:00Z"), "24:15:00 is 12:15 AM the next morning")
        XCTAssertEqual(trips.map(\.scheduledDeparture), trips.map(\.scheduledDeparture).sorted())
        let returning = try timetable().trips(from: "UN", to: "OA", on: monday)
        XCTAssertTrue(Set(ids(returning)).isDisjoint(with: ids(trips)), "One direction only")
    }

    /// Express trains skip stations most of the line's trains call at between the two stations.
    func testExpressFollowsTheStoppingPattern() throws {
        let timetable = try timetable()
        // Hamilton and Aldershot trains run Clarkson to Union non-stop in the morning peak.
        XCTAssertEqual(express(timetable.trips(from: "OA", to: "UN", on: monday)), Set([
            "20261109-LW-1854", "20261109-LW-1756", "20261109-LW-1856", "20261109-LW-1256", "20261109-LW-1858",
            "20261109-LW-1758", "20261109-LW-1860", "20261109-LW-1258", "20261109-LW-1960",
        ]))
        // Off-peak Kitchener trains skip Etobicoke North, as about half the trains do: that alone is not express.
        XCTAssertEqual(express(timetable.trips(from: "BE", to: "UN", on: monday)), Set([
            "20261109-GT-3656", "20261109-GT-3856", "20261109-GT-3758", "20261109-GT-3958", "20261109-GT-3760",
            "20261109-GT-3860", "20261109-GT-3862", "20261109-GT-3776",
        ]))
        let bloor = timetable.trips(from: "UN", to: "BL", on: monday)
        XCTAssertEqual(bloor.count, 35)
        XCTAssertTrue(express(bloor).isEmpty, "Nothing to skip between neighbouring stations")
    }

    func testSundayHasItsOwnTimetable() throws {
        let timetable = try timetable()
        let trips = timetable.trips(from: "OA", to: "UN", on: sunday)
        XCTAssertEqual(trips.count, 36)
        XCTAssertEqual(trips.first?.scheduledDeparture, utc("2026-11-08T13:01:00Z")) // 8:01 AM
        XCTAssertEqual(express(trips), ["20261108-LW-1970", "20261108-LW-1978", "20261108-LW-1986", "20261108-LW-1990"])
        XCTAssertTrue(timetable.trips(from: "OA", to: "UN", on: ServiceDay(year: 2026, month: 11, day: 10)).isEmpty)
    }

    func testAfterMidnightTrainsStayOnTheirServiceDay() throws {
        let trips = try timetable().trips(from: "UN", to: "WR", on: friday)
        XCTAssertEqual(trips.count, 20)
        let last = try XCTUnwrap(trips.last)
        XCTAssertEqual(last.key, TripKey(serviceDay: friday, tripId: "20261127-LW-1641"))
        XCTAssertEqual(last.scheduledDeparture, utc("2026-11-28T05:47:00Z"), "24:47:00 is 12:47 AM on Nov 28")
        XCTAssertEqual(last.scheduledArrival, utc("2026-11-28T07:10:00Z"), "26:10:00 is 2:10 AM on Nov 28")
        XCTAssertEqual(ServiceDay(containing: last.scheduledArrival), friday)
        XCTAssertEqual(ServiceDay.minutesIntoServiceDay(last.scheduledDeparture), 24 * 60 + 47, "Sorts after 11:59 PM")
    }

    func testStopsOfOneTrain() throws {
        let stops = try timetable().stops(of: "20261109-LW-1858", from: "OA", to: "UN", on: monday)
        XCTAssertEqual(stops.map(\.station.name), ["Oakville GO", "Clarkson GO", "Union Station GO"])
        XCTAssertEqual(stops.first?.station.place, GeoPoint(latitude: 43.455594, longitude: -79.682242), "For Directions (TT-188)")
        XCTAssertEqual(stops.map(\.scheduled), [utc("2026-11-09T12:28:00Z"), utc("2026-11-09T12:36:00Z"), utc("2026-11-09T13:02:00Z")])
        XCTAssertTrue(try timetable().stops(of: "20261109-LW-1858", from: "OA", to: "UN", on: sunday).isEmpty)
    }

    func testStoredFeedReadsBackTheSame() throws {
        let feed = try GTFSFeed(zip: Self.sampleZip(), importedAt: utc("2026-11-07T12:00:00Z"))
        XCTAssertEqual(try JSONDecoder().decode(GTFSFeed.self, from: JSONEncoder().encode(feed)), feed)
    }

    func testNotAZip() {
        XCTAssertThrowsError(try ZipArchive(data: Data("stop_id,stop_name".utf8))) { error in
            XCTAssertEqual(error as? ZipArchive.ZipError, .notAZip)
        }
    }
}

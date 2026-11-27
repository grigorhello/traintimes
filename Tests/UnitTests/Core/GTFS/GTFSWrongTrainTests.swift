import XCTest
@testable import TrainTimes

/// TT-251 (D127): a trip by id and the trains leaving a station, on the sample feed (Nov 27) with synthetic tracks: the
/// Lakeshore West shapes are `OnBoardFixtures`' Union to Oakville line (the eastbound one turned round), Kitchener's run
/// Union, Bramalea, Kitchener.
final class GTFSWrongTrainTests: XCTestCase {
    private let friday = OnBoardFixtures.friday

    private func timetable(withShapes: Bool = true) throws -> GTFSTimetable {
        let archive = try ZipArchive(data: GTFSTimetableTests.sampleZip())
        let lakeshore = OnBoardFixtures.shapes.split(separator: "\n").dropFirst().map { line -> String in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            return "\(fields[1]),\(fields[2])"
        }
        let kitchener = ["43.645195,-79.380600", "43.702259,-79.688751", "43.455686,-80.493130"]
        var rows = ["shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence,shape_dist_traveled"]
        for (id, points) in [
            ("UNAL", lakeshore), ("UNAP", lakeshore), ("UNHA", lakeshore), ("UNNI", lakeshore), ("ALUN", lakeshore.reversed()),
            ("UNBE", kitchener), ("UNKI", kitchener), ("KIUN", kitchener.reversed()),
        ] as [(String, [String])] {
            for (index, point) in points.enumerated() { rows.append("\(id),\(point),\(index + 1),") }
        }
        let shapes = rows.joined(separator: "\n")
        let feed = try GTFSFeed(importedAt: Date(timeIntervalSince1970: 0)) { name -> Data? in
            if name == "shapes.txt" { return withShapes ? Data(shapes.utf8) : nil }
            return try archive.data(named: name)
        }
        return GTFSTimetable(feed: feed)
    }

    private func time(_ hours: Int, _ minutes: Int) -> Date { OnBoardFixtures.time(hours, minutes) }

    func testATripByIdHasItsStopsItsLineAndItsTrack() throws {
        let trip = try XCTUnwrap(timetable().trip(id: "20261127-LW-1327", on: friday))
        XCTAssertEqual(trip.key, TripKey(serviceDay: friday, tripId: "20261127-LW-1327"))
        XCTAssertEqual(trip.lineId, "LW")
        XCTAssertEqual(trip.stops.first?.station.id, "UN")
        XCTAssertEqual(trip.stops.first?.departure, time(17, 35))
        XCTAssertEqual(trip.stops.last?.station.id, "AP")
        XCTAssertEqual(trip.stops.last?.arrival, time(18, 29))
        XCTAssertNotNil(trip.stops.first?.station.place)
        let track = try XCTUnwrap(trip.track)
        XCTAssertEqual(track.stopDistances.count, trip.stops.count, "every stop placed")
        XCTAssertEqual(track.stopDistances, track.stopDistances.sorted(), "in calling order")
    }

    func testATripByIdIsNilOnAnotherDayOrUnknownAndHasNoTrackWithoutShapes() throws {
        let table = try timetable()
        XCTAssertNil(table.trip(id: "20261127-LW-1327", on: ServiceDay(year: 2026, month: 11, day: 9)))
        XCTAssertNil(table.trip(id: "20261127-LW-9999", on: friday))
        let plain = try XCTUnwrap(timetable(withShapes: false).trip(id: "20261127-LW-1327", on: friday))
        XCTAssertNil(plain.track)
    }

    func testTheCandidatesAtUnion() throws {
        let candidates = try timetable().candidates(leaving: "UN", on: friday)
        let byId = Dictionary(candidates.map { ($0.trip.tripId, $0) }, uniquingKeysWith: { first, _ in first })
        // Two pairs leaving a minute apart, Kitchener and Lakeshore West.
        XCTAssertEqual(byId["20261127-GT-3227"]?.departure, time(17, 34))
        XCTAssertEqual(byId["20261127-LW-1327"]?.departure, time(17, 35))
        XCTAssertEqual(byId["20261127-LW-1879"]?.departure, time(17, 50))
        XCTAssertEqual(byId["20261127-GT-3877"]?.departure, time(17, 51))
        // Block 70P: the Kitchener train ends at Union and is no candidate there; it leaves again as LW-1077.
        XCTAssertNil(byId["20261127-GT-3776"])
        XCTAssertEqual(byId["20261127-LW-1077"]?.departure, time(17, 29))
        let lakeshore = try XCTUnwrap(byId["20261127-LW-1327"])
        XCTAssertEqual(lakeshore.lineId, "LW")
        XCTAssertEqual(lakeshore.originAlong, 0, accuracy: 1, "Union is where its track starts")
        XCTAssertEqual(lakeshore.stopsAfter.first, "EX")
        XCTAssertEqual(lakeshore.stopsAfter.last, "AP")
        XCTAssertTrue(candidates.allSatisfy { !$0.stopsAfter.isEmpty })
        XCTAssertEqual(candidates.map(\.departure), candidates.map(\.departure).sorted())
    }

    func testTheCandidatesAtClarksonGoBothWays() throws {
        let candidates = try timetable().candidates(leaving: "CL", on: friday)
        let byId = Dictionary(candidates.map { ($0.trip.tripId, $0) }, uniquingKeysWith: { first, _ in first })
        let west = try XCTUnwrap(byId["20261127-LW-1977"])
        XCTAssertEqual(west.departure, time(17, 24))
        XCTAssertEqual(west.stopsAfter.first, "OA")
        let east = try XCTUnwrap(byId["20261127-LW-1028"])
        XCTAssertEqual(east.departure, time(17, 39))
        XCTAssertEqual(east.stopsAfter.last, "UN")
        XCTAssertGreaterThan(west.originAlong, 0)
        XCTAssertGreaterThan(east.originAlong, 0)
    }

    func testNoCandidateWithoutATrack() throws {
        XCTAssertTrue(try timetable(withShapes: false).candidates(leaving: "UN", on: friday).isEmpty)
    }
}

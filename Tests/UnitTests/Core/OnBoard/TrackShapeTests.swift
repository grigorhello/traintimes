import XCTest
@testable import TrainTimes

/// TT-171: placing a position on a trip's track, and importing the tracks from shapes.txt.
final class TrackShapeTests: XCTestCase {
    /// About 1 km due east along Toronto's latitude, then 1 km due north.
    private let corner = TrackShape(points: [
        GeoPoint(latitude: 43.6, longitude: -79.4),
        GeoPoint(latitude: 43.6, longitude: -79.387_59),
        GeoPoint(latitude: 43.609, longitude: -79.387_59),
    ])

    func testProjectionGivesTheDistanceAlongAndOffTheLine() {
        XCTAssertEqual(corner.distances[1], 1_000, accuracy: 5)
        XCTAssertEqual(corner.length, 2_000, accuracy: 10)
        // 100 m north of the first segment's middle.
        let projection = corner.project(GeoPoint(latitude: 43.600_9, longitude: -79.393_8))
        XCTAssertEqual(projection.along, 500, accuracy: 5)
        XCTAssertEqual(projection.off, 100, accuracy: 2)
        // Before the start: the start, and the distance to it.
        let before = corner.project(GeoPoint(latitude: 43.6, longitude: -79.401_24))
        XCTAssertEqual(before.along, 0)
        XCTAssertEqual(before.off, 100, accuracy: 2)
    }

    func testAPointAlongTheLineProjectsBackToItsDistance() {
        for distance in [0.0, 250, 999, 1_000, 1_500, 2_000] {
            XCTAssertEqual(corner.project(corner.point(at: distance)).along, distance, accuracy: 1, "\(distance)")
            XCTAssertEqual(corner.project(corner.point(at: distance)).off, 0, accuracy: 1, "\(distance)")
        }
        XCTAssertEqual(corner.point(at: -10), corner.points.first)
        XCTAssertEqual(corner.point(at: 5_000), corner.points.last)
    }

    /// A line that doubles back keeps its stops in calling order: the third stop is nearest the start, but comes after the
    /// second.
    func testStopsKeepTheirCallingOrder() {
        let hairpin = TrackShape(points: [
            GeoPoint(latitude: 43.6, longitude: -79.4),
            GeoPoint(latitude: 43.6, longitude: -79.387_59),
            GeoPoint(latitude: 43.600_5, longitude: -79.387_59),
            GeoPoint(latitude: 43.600_5, longitude: -79.4),
        ])
        let stops = [hairpin.points[0], hairpin.points[1], GeoPoint(latitude: 43.600_5, longitude: -79.399)]
        let distances = hairpin.distances(of: stops)
        XCTAssertEqual(distances[0], 0, accuracy: 1)
        XCTAssertEqual(distances[1], 1_000, accuracy: 5)
        XCTAssertEqual(distances[2], 1_974, accuracy: 5)
    }

    func testSimplifyingKeepsTheCornersOnly() {
        let straight = (0...10).map { GeoPoint(latitude: 43.6, longitude: -79.4 + Double($0) * 0.001) }
        let bent = straight + [GeoPoint(latitude: 43.61, longitude: -79.39)]
        let simplified = TrackShape.simplified(bent, tolerance: 3)
        XCTAssertEqual(simplified, [straight[0], straight[10], bent[11]])
    }

    /// shapes.txt is imported for rail trips only, in sequence order, with each station's place (D35 ignored it before).
    func testShapesImportForRailTripsOnly() throws {
        let files = [
            "routes.txt": "route_id,route_short_name,route_long_name,route_type\nR1,LW,Lakeshore West,2\nB1,56,Oakville / Oshawa,3",
            "stops.txt": """
            stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
            OA,Oakville GO,43.455594,-79.682242,1,
            OA-1,"Oakville GO, platform 1",43.4556,-79.6823,0,OA
            UN,Union Station GO,43.645195,-79.3806,1,
            """,
            "trips.txt": "route_id,service_id,trip_id,shape_id\nR1,DAY,train,RAIL\nB1,DAY,bus,BUS",
            "stop_times.txt": """
            trip_id,arrival_time,departure_time,stop_id,stop_sequence
            train,07:32:00,07:32:00,OA-1,1
            train,08:05:00,08:05:00,UN,2
            bus,07:00:00,07:00:00,OA,1
            bus,08:30:00,08:30:00,UN,2
            """,
            "calendar_dates.txt": "service_id,date,exception_type\nDAY,20261109,1",
            "shapes.txt": """
            shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence
            RAIL,43.645195,-79.3806,3
            RAIL,43.455594,-79.682242,1
            RAIL,43.55,-79.5,2
            BUS,43.5,-79.5,1
            BUS,43.6,-79.4,2
            """,
        ]
        let feed = try GTFSFeed(importedAt: Date(timeIntervalSince1970: 0)) { files[$0].map { Data($0.utf8) } }
        XCTAssertEqual(feed.shapes?.map(\.id), ["RAIL"])
        XCTAssertEqual(feed.shapes?.first?.points, [43.455594, -79.682242, 43.55, -79.5, 43.645195, -79.3806])
        XCTAssertEqual(feed.trips.map(\.shape), [0])
        XCTAssertEqual(feed.stops.first?.latitude, 43.455594, "A platform takes its station's place")
        XCTAssertEqual(feed.stops.first?.longitude, -79.682242)

        let ride = Ride(trip: TripKey(serviceDay: ServiceDay(year: 2026, month: 11, day: 9), tripId: "train"), from: "OA", to: "UN")
        let plan = try XCTUnwrap(GTFSTimetable(feed: feed).ridePlan(for: ride))
        XCTAssertEqual(plan.stops.map(\.station.id), ["OA", "UN"])
        let track = try XCTUnwrap(plan.track)
        XCTAssertEqual(track.stopDistances[0], 0, accuracy: 1)
        XCTAssertEqual(track.stopDistances[1], track.shape.length, accuracy: 1)
    }

    /// Without shapes.txt, a ride has no track and runs on the timetable.
    func testATripWithoutAShapeHasNoTrack() throws {
        let timetable = GTFSTimetable(feed: try GTFSFeed(zip: GTFSTimetableTests.sampleZip(), importedAt: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(timetable.feed.shapes, [])
        let plan = try XCTUnwrap(timetable.ridePlan(for: OnBoardFixtures.ride))
        XCTAssertEqual(plan.stops.count, 6)
        XCTAssertNil(plan.track)
    }
}

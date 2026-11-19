import XCTest
@testable import TrainTimes

/// Automatic direction's rule (TT-234, D116), case by case, on Oakville GO to Union Station (about 32 km apart): which
/// end a reading is at, the readings that say nothing, the circle and the old reading, the train check on the track, and
/// turn or ask. No location code and no clock.
final class DirectionRuleTests: XCTestCase {
    private let oakville = DirectionFixtures.oakvillePlace
    private let union = DirectionFixtures.unionPlace
    /// From Oakville to Union: the rider is expected at Oakville.
    private let ends = DirectionRule.Ends(
        fromId: "OA", from: DirectionFixtures.oakvillePlace, toId: "UN", to: DirectionFixtures.unionPlace
    )
    /// A straight track from Oakville to Union.
    private let rails = TrackShape(points: [DirectionFixtures.oakvillePlace, DirectionFixtures.unionPlace])
    private let metresPerDegree = 111_195.08

    private var apart: Double { TrackShape.distance(oakville, union) }

    private var track: DirectionRule.Track {
        DirectionRule.Track(shape: rails, along: ["OA": 0, "UN": rails.length])
    }

    /// `north` metres north and `east` metres east of `place`.
    private func moved(_ place: GeoPoint, north: Double = 0, east: Double = 0) -> GeoPoint {
        GeoPoint(
            latitude: place.latitude + north / metresPerDegree,
            longitude: place.longitude + east / (metresPerDegree * cos(place.latitude * .pi / 180))
        )
    }

    /// The place on the straight line between the two stations, `distance` metres from Union.
    private func place(fromUnion distance: Double) -> GeoPoint {
        rails.point(at: rails.length - distance)
    }

    /// The same, `distance` metres from Oakville.
    private func place(fromOakville distance: Double) -> GeoPoint {
        rails.point(at: distance)
    }

    /// The way from Oakville to Union as a unit vector.
    private var heading: (north: Double, east: Double) {
        let north = (union.latitude - oakville.latitude) * metresPerDegree
        let east = (union.longitude - oakville.longitude) * metresPerDegree
            * cos((union.latitude + oakville.latitude) / 2 * .pi / 180)
        let length = hypot(north, east)
        return (north / length, east / length)
    }

    /// `distance` metres before Union along the track and `off` metres to its side.
    private func place(beforeUnion distance: Double, off: Double) -> GeoPoint {
        moved(place(fromUnion: distance), north: off * heading.east, east: -off * heading.north)
    }

    private func verdict(
        _ place: GeoPoint, radius: Double = 20, age: TimeInterval = 0, ends: DirectionRule.Ends? = nil,
        track: DirectionRule.Track? = nil
    ) -> DirectionRule.Verdict {
        DirectionRule.verdict(
            ends: ends ?? self.ends, reading: DirectionReading(place: place, radius: radius, age: age), track: track
        )
    }

    /// Union to Oakville: the same two stations the other way round.
    private var turnedEnds: DirectionRule.Ends {
        DirectionRule.Ends(fromId: "UN", from: union, toId: "OA", to: oakville)
    }

    // MARK: Which end

    func testTheTwoStationsAreAbout32KmApart() {
        XCTAssertEqual(apart, 32_178, accuracy: 50)
        XCTAssertEqual(rails.length, apart, accuracy: 1)
    }

    /// From is already the closer station: nothing to do.
    func testFromAlreadyTheCloserStationStays() {
        XCTAssertEqual(verdict(oakville), .stays)
        XCTAssertEqual(verdict(place(fromOakville: 10_000)), .stays)
        XCTAssertEqual(verdict(union, ends: turnedEnds), .stays)
    }

    /// At the To station the route should leave from it.
    func testAtTheToStationTurns() {
        XCTAssertEqual(verdict(union), .turns)
        XCTAssertEqual(verdict(place(fromUnion: 10_000)), .turns)
        XCTAssertEqual(verdict(oakville, ends: turnedEnds), .turns)
    }

    /// The other station must be at least 1.5 times as far: on these 32 km each end reaches 12.9 km toward the other.
    func testInBetweenIsSkipped() {
        XCTAssertEqual(verdict(rails.point(at: rails.length / 2)), .skipped)
        // 14 km from one, 18 km from the other: 1.3 times as far.
        XCTAssertEqual(verdict(place(fromUnion: 14_000)), .skipped)
        XCTAssertEqual(verdict(place(fromOakville: 14_000)), .skipped)
        // 12 km from one, 20 km from the other: 1.7 times as far.
        XCTAssertEqual(verdict(place(fromUnion: 12_000)), .turns)
        XCTAssertEqual(verdict(place(fromOakville: 12_000)), .stays)
    }

    /// The ticket's own example: Clarkson to Union is 25 km, each end reaches 10 km and the 5 km between is in between.
    func testClarksonToUnionReaches10KmFromEachEnd() {
        let clarkson = GeoPoint(latitude: 43.513127, longitude: -79.633206)
        let ends = DirectionRule.Ends(fromId: "CL", from: clarkson, toId: "UN", to: union)
        let line = TrackShape(points: [clarkson, union])
        XCTAssertEqual(line.length, 25_094, accuracy: 50)

        XCTAssertEqual(verdict(line.point(at: line.length - 9_000), ends: ends), .turns)
        XCTAssertEqual(verdict(line.point(at: 9_000), ends: ends), .stays)
        XCTAssertEqual(verdict(line.point(at: line.length - 11_000), ends: ends), .skipped)
        XCTAssertEqual(verdict(line.point(at: 11_000), ends: ends), .skipped)
        XCTAssertEqual(verdict(line.point(at: line.length / 2), ends: ends), .skipped)
    }

    /// The closer station is more than 15 km away, and the reading is not on its outer side: far from both.
    func testCloserButBeyond15KmAndNotOnTheOuterSideIsSkipped() {
        // 16 km due south of Union: Oakville is 24.9 km away, 1.55 times as far, and nearer than the two are apart.
        let south = moved(union, north: -16_000)
        let toUnion = TrackShape.distance(south, union)
        let toOakville = TrackShape.distance(south, oakville)
        XCTAssertGreaterThan(toUnion, DirectionRule.reach)
        XCTAssertGreaterThanOrEqual(toOakville, DirectionRule.ratio * toUnion, "the ratio alone would give an answer")
        XCTAssertLessThan(toOakville, apart, "not on Union's outer side")
        XCTAssertEqual(verdict(south, radius: 0), .skipped)
        // 14 km on the same line is within reach.
        XCTAssertEqual(verdict(moved(union, north: -14_000), radius: 0), .turns)

        // The same at the From end.
        XCTAssertEqual(verdict(moved(oakville, north: 16_000), radius: 0), .skipped)
        XCTAssertEqual(verdict(moved(oakville, north: 14_000), radius: 0), .stays)
    }

    /// Beyond 15 km but on the station's outer side (farther from the other station than the two are apart), the closer
    /// station is still the answer.
    func testBeyond15KmOnTheOuterSideGivesAnAnswer() {
        let north = moved(union, north: 20_000)
        XCTAssertGreaterThan(TrackShape.distance(north, union), DirectionRule.reach)
        XCTAssertGreaterThan(TrackShape.distance(north, oakville), apart)
        XCTAssertEqual(verdict(north), .turns)

        let south = moved(oakville, north: -20_000)
        XCTAssertGreaterThan(TrackShape.distance(south, oakville), DirectionRule.reach)
        XCTAssertGreaterThan(TrackShape.distance(south, union), apart)
        XCTAssertEqual(verdict(south), .stays)
    }

    /// 100 km out, the other station is only 1.2 times as far: far from both, even on the outer side.
    func testFarFromBothIsSkipped() {
        XCTAssertEqual(verdict(moved(union, north: 100_000)), .skipped)
        XCTAssertEqual(verdict(moved(oakville, north: -100_000)), .skipped)
    }

    // MARK: A usable reading

    /// The whole circle must give the answer: the radius is added to the closer distance and taken off the farther.
    func testAWideCircleThatReachesTheMiddleIsSkipped() {
        let tenOut = place(fromUnion: 10_000)
        XCTAssertEqual(verdict(tenOut, radius: 100), .turns)
        XCTAssertEqual(verdict(tenOut, radius: 3_500), .skipped, "13.5 km and 18.7 km: 1.4 times as far")

        XCTAssertEqual(verdict(union, radius: 1_000), .turns)
        XCTAssertEqual(verdict(union, radius: 14_000), .skipped)
        XCTAssertEqual(verdict(oakville, radius: 14_000), .skipped, "nor does it stay: the reading says nothing")
    }

    /// An old reading may have moved at a train's speed since: its circle grows by 42 m for each second of its age.
    func testAnOldReadingIsWidenedBy42MetresASecond() {
        let tenOut = place(fromUnion: 10_000)
        XCTAssertEqual(verdict(tenOut, age: 10), .turns)
        XCTAssertEqual(verdict(tenOut, age: 80), .skipped, "80 s is 3.4 km more")
        XCTAssertEqual(verdict(union, age: 5), .turns)
        XCTAssertEqual(verdict(union, age: 400), .skipped, "400 s is 16.8 km more")

        // An age reads exactly as that much more radius.
        let spots = [union, oakville, tenOut, place(fromOakville: 10_000), rails.point(at: rails.length / 2)]
        for age in [0.0, 10, 59, 70, 80, 300] {
            for spot in spots {
                XCTAssertEqual(
                    verdict(spot, radius: 20, age: age), verdict(spot, radius: 20 + age * DirectionRule.speed, age: 0),
                    "\(age) s at \(spot)"
                )
            }
        }
    }

    /// A radius or an age below zero widens nothing, and narrows nothing either.
    func testANegativeRadiusOrAgeCountsAsNone() {
        let middle = rails.point(at: rails.length / 2)
        XCTAssertEqual(verdict(middle, radius: -10_000), .skipped)
        XCTAssertEqual(verdict(middle, radius: 0, age: -300), .skipped)
        XCTAssertEqual(verdict(union, radius: -1, age: -1), .turns)
    }

    // MARK: Maybe on the train

    /// Within 300 m of the track and more than 1 km before the station it names: maybe on the train.
    func testOnTheTrackWellBeforeTheStationMayBeOnTheTrain() {
        XCTAssertEqual(verdict(place(fromUnion: 5_000), track: track), .maybeOnTrain)
        XCTAssertEqual(verdict(place(fromUnion: 1_500), track: track), .maybeOnTrain)
        XCTAssertEqual(verdict(place(beforeUnion: 5_000, off: 200), track: track), .maybeOnTrain)
        // With no track there is no train check.
        XCTAssertEqual(verdict(place(fromUnion: 5_000), track: nil), .turns)
    }

    /// At the station, or within its last kilometre, the route turns.
    func testAtTheStationOnTheTrackTurns() {
        XCTAssertEqual(verdict(union, track: track), .turns)
        XCTAssertEqual(verdict(place(fromUnion: 500), track: track), .turns)
        // 2 km past Union, beyond the end of the track.
        let past = moved(union, north: 2_000 * heading.north, east: 2_000 * heading.east)
        XCTAssertEqual(TrackShape.distance(past, union), 2_000, accuracy: 20)
        XCTAssertEqual(verdict(past, track: track), .turns)
    }

    /// More than 300 m off the track is not on the train, however far before the station.
    func testFarOffTheTrackIsNotOnTheTrain() {
        let near = place(beforeUnion: 5_000, off: 400)
        XCTAssertEqual(rails.project(near).off, 400, accuracy: 20)
        XCTAssertEqual(verdict(near, track: track), .turns)

        let far = place(beforeUnion: 5_000, off: 1_000)
        XCTAssertEqual(rails.project(far).off, 1_000, accuracy: 20)
        XCTAssertEqual(rails.length - rails.project(far).along, 5_000, accuracy: 50)
        XCTAssertEqual(verdict(far, track: track), .turns)
    }

    /// "Before the station" is measured along the track whichever way it was drawn, and for either station.
    func testTheTrainCheckReadsTheTrackEitherWay() {
        // The same track drawn from Union to Oakville.
        let back = TrackShape(points: [union, oakville])
        let drawnBack = DirectionRule.Track(shape: back, along: ["UN": 0, "OA": back.length])
        XCTAssertEqual(verdict(place(fromUnion: 5_000), track: drawnBack), .maybeOnTrain)
        XCTAssertEqual(verdict(place(fromUnion: 500), track: drawnBack), .turns)
        XCTAssertEqual(verdict(union, track: drawnBack), .turns)

        // The route the other way round: Oakville is the station the reading names.
        for drawn in [track, drawnBack] {
            XCTAssertEqual(verdict(place(fromOakville: 5_000), ends: turnedEnds, track: drawn), .maybeOnTrain)
            XCTAssertEqual(verdict(place(fromOakville: 500), ends: turnedEnds, track: drawn), .turns)
            XCTAssertEqual(verdict(oakville, ends: turnedEnds, track: drawn), .turns)
        }
    }

    /// The train check only stands between a reading and a turn.
    func testTheTrainCheckLeavesTheOtherAnswersAlone() {
        XCTAssertEqual(verdict(place(fromOakville: 5_000), track: track), .stays)
        XCTAssertEqual(verdict(rails.point(at: rails.length / 2), track: track), .skipped)
        XCTAssertEqual(verdict(place(fromUnion: 5_000), radius: 9_000, track: track), .skipped)
    }

    /// A track that does not place both stations is left out.
    func testATrackThatDoesNotPlaceBothStationsIsLeftOut() {
        let half = DirectionRule.Track(shape: rails, along: ["UN": rails.length])
        XCTAssertEqual(verdict(place(fromUnion: 5_000), track: half), .turns)
        let other = DirectionRule.Track(shape: rails, along: ["CL": 0, "UN": rails.length])
        XCTAssertEqual(verdict(place(fromUnion: 5_000), track: other), .turns)
    }

    // MARK: Turn or ask

    func testAReadingThatSaysNothingHasNoOutcome() {
        XCTAssertNil(DirectionRule.outcome(of: .skipped, mayTurn: true))
        XCTAssertNil(DirectionRule.outcome(of: .skipped, mayTurn: false))
    }

    func testFromAlreadyCloserEndsTheLookWithNothing() {
        XCTAssertEqual(DirectionRule.outcome(of: .stays, mayTurn: true), .nothing(.alreadyCloser))
        XCTAssertEqual(DirectionRule.outcome(of: .stays, mayTurn: false), .nothing(.alreadyCloser))
    }

    /// The route turns by itself only while the answer is in time; later it asks.
    func testAtTheToStationTurnsInTimeAndAsksLater() {
        XCTAssertEqual(DirectionRule.outcome(of: .turns, mayTurn: true), .turn)
        XCTAssertEqual(DirectionRule.outcome(of: .turns, mayTurn: false), .ask)
    }

    /// Maybe on the train asks, never turns.
    func testMaybeOnTheTrainAlwaysAsks() {
        XCTAssertEqual(DirectionRule.outcome(of: .maybeOnTrain, mayTurn: true), .ask)
        XCTAssertEqual(DirectionRule.outcome(of: .maybeOnTrain, mayTurn: false), .ask)
    }

    /// The rule's numbers, as the ticket gives them.
    func testTheRulesNumbers() {
        XCTAssertEqual(DirectionRule.ratio, 1.5)
        XCTAssertEqual(DirectionRule.reach, 15_000)
        XCTAssertEqual(DirectionRule.speed, 42)
        XCTAssertEqual(DirectionRule.trackReach, 300)
        XCTAssertEqual(DirectionRule.trackLead, 1_000)
        XCTAssertEqual(DirectionRule.quick, .seconds(1))
        XCTAssertEqual(DirectionRule.limit, .seconds(10))
        XCTAssertEqual(DirectionRule.handHold, 600)
        XCTAssertEqual(DirectionRule.undoHold, 3_600)
        XCTAssertEqual(DirectionRule.proofLasts, 3_600)
    }

    // MARK: The track from the timetable

    private let monday = ServiceDay(year: 2026, month: 11, day: 9)

    /// One train from Oakville to Union on Mon Nov 9, on a track that bends once between them.
    private func timetable(shapes: Bool = true) throws -> GTFSTimetable {
        var files = [
            "routes.txt": "route_id,route_short_name,route_long_name,route_type\nR1,LW,Lakeshore West,2",
            "stops.txt": """
            stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
            OA,Oakville GO,43.455594,-79.682242,1,
            UN,Union Station GO,43.645195,-79.3806,1,
            """,
            "trips.txt": "route_id,service_id,trip_id,shape_id\nR1,DAY,train,RAIL",
            "stop_times.txt": """
            trip_id,arrival_time,departure_time,stop_id,stop_sequence
            train,07:32:00,07:32:00,OA,1
            train,08:05:00,08:05:00,UN,2
            """,
            "calendar_dates.txt": "service_id,date,exception_type\nDAY,20261109,1",
        ]
        if shapes {
            files["shapes.txt"] = """
            shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence
            RAIL,43.455594,-79.682242,1
            RAIL,43.55,-79.5,2
            RAIL,43.645195,-79.3806,3
            """
        }
        let feed = try GTFSFeed(importedAt: Date(timeIntervalSince1970: 0)) { files[$0].map { Data($0.utf8) } }
        return GTFSTimetable(feed: feed)
    }

    /// The track is the first direct train's, whichever way it runs, with each station's distance along it.
    func testTheTrackIsTheFirstDirectTrainsEitherWay() throws {
        let timetable = try timetable()
        let track = try XCTUnwrap(timetable.directionTrack(between: "OA", and: "UN", from: monday))
        XCTAssertEqual(track.shape.points.count, 3)
        XCTAssertEqual(track.shape.length, 32_362, accuracy: 50)
        XCTAssertEqual(try XCTUnwrap(track.along["OA"]), 0, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(track.along["UN"]), track.shape.length, accuracy: 1)
        XCTAssertEqual(track.along.count, 2)

        // No train runs from Union to Oakville: the route that way round reads the same train's track.
        XCTAssertEqual(timetable.directionTrack(between: "UN", and: "OA", from: monday), track)

        // The rule reads it for either direction of the route.
        let beforeUnion = track.shape.point(at: track.shape.length - 5_000)
        XCTAssertEqual(verdict(beforeUnion, track: track), .maybeOnTrain)
        XCTAssertEqual(verdict(track.shape.point(at: track.shape.length - 500), track: track), .turns)
        XCTAssertEqual(verdict(track.shape.point(at: 5_000), ends: turnedEnds, track: track), .maybeOnTrain)
        XCTAssertEqual(verdict(track.shape.point(at: 500), ends: turnedEnds, track: track), .turns)
    }

    /// A day with no direct train takes the next day that has one, as far as `days` reaches.
    func testTheTrackComesFromTheNextDayThatHasATrain() throws {
        let timetable = try timetable()
        let thursday = ServiceDay(year: 2026, month: 11, day: 5)
        XCTAssertNotNil(timetable.directionTrack(between: "OA", and: "UN", from: thursday))
        XCTAssertEqual(
            timetable.directionTrack(between: "OA", and: "UN", from: thursday),
            timetable.directionTrack(between: "OA", and: "UN", from: monday)
        )
        XCTAssertNotNil(timetable.directionTrack(between: "OA", and: "UN", from: thursday, days: 5))
        XCTAssertNil(timetable.directionTrack(between: "OA", and: "UN", from: thursday, days: 4))
        let tuesday = monday.adding(days: 1)
        XCTAssertNil(timetable.directionTrack(between: "OA", and: "UN", from: tuesday), "the train ran yesterday")
    }

    /// No train between the two, or a train with no shape: no track, and the rule leaves the train check out.
    func testNoTrackWithoutADirectTrainOrAShape() throws {
        XCTAssertNil(try timetable().directionTrack(between: "OA", and: "XX", from: monday))
        XCTAssertNil(try timetable().directionTrack(between: "OA", and: "OA", from: monday))
        XCTAssertNil(try timetable(shapes: false).directionTrack(between: "OA", and: "UN", from: monday))
    }
}

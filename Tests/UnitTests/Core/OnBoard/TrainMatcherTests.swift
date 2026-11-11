import XCTest
@testable import TrainTimes

/// Train detection's matcher (TT-175) on synthetic tracks: the On board tests' 11:17 AM Lakeshore West train from Union
/// (Exhibition 11:24, Mimico 11:32, Long Branch 11:38, Port Credit 11:45, Clarkson 11:52), ridden, driven beside and stood
/// beside, alone and among the day's other trains. The phone sends a fix each second; the feed places a train every 15 s.
final class TrainMatcherTests: XCTestCase {
    private var base: RidePlan!
    private let line = Line(id: "LW", name: "Lakeshore West", colorHex: nil)

    override func setUpWithError() throws {
        base = try OnBoardFixtures.plan()
    }

    // MARK: Riding the train

    func testFeedAsksAfterTwoSharedStops() throws {
        let train = try candidate("A")
        var matcher = TrainMatcher()
        matcher.setCandidates([train])
        let run = try self.run(&matcher, from: OnBoardFixtures.time(11, 17), phone: riding(train.plan), feedOf: [train])

        let asked = try XCTUnwrap(run.asked)
        let question = try XCTUnwrap(question(of: matcher))
        XCTAssertEqual(question.trains.map(\.trip), [train.trip])
        XCTAssertEqual(question.since?.id, "UN")
        XCTAssertEqual(question.stops.map(\.id), ["EX", "MI"])
        // As the train leaves Mimico, its second shared stop, while they move together.
        XCTAssertGreaterThan(asked, OnBoardFixtures.time(11, 32, 20))
        XCTAssertLessThan(asked, OnBoardFixtures.time(11, 34))
    }

    func testTimetableAsksAfterThreeMoreMinutesTogether() throws {
        let train = try candidate("A")
        var matcher = TrainMatcher()
        matcher.setCandidates([train])
        let run = try self.run(&matcher, from: OnBoardFixtures.time(11, 17), phone: riding(train.plan))

        let asked = try XCTUnwrap(run.asked)
        let twoStops = try XCTUnwrap(run.firstTime(sharing: 2))
        XCTAssertGreaterThanOrEqual(asked.timeIntervalSince(twoStops), TrainMatcher.togetherTime)
        XCTAssertLessThan(asked, OnBoardFixtures.time(11, 37))
        XCTAssertEqual(question(of: matcher)?.stops.map(\.id), ["EX", "MI"])
    }

    func testLateTrainIsAskedOnTheTimetable() throws {
        let train = try candidate("A")
        var matcher = TrainMatcher()
        matcher.setCandidates([train])
        let run = try self.run(&matcher, from: OnBoardFixtures.time(11, 17), phone: riding(train.plan, late: 180))

        XCTAssertGreaterThan(try XCTUnwrap(run.asked), OnBoardFixtures.time(11, 37))
        XCTAssertEqual(question(of: matcher)?.trains.map(\.trip), [train.trip])
        XCTAssertEqual(question(of: matcher)?.stops.map(\.id), ["EX", "MI"])
    }

    func testCheckingStripFollowsTheSharedStops() throws {
        let train = try candidate("A")
        var matcher = TrainMatcher()
        matcher.setCandidates([train])
        let run = try self.run(&matcher, from: OnBoardFixtures.time(11, 17), phone: riding(train.plan))

        guard case .checking(let moving)? = run.states.first(where: { $0.state != .idle })?.state else {
            return XCTFail("The strip shows once the phone moves along the line")
        }
        XCTAssertEqual(moving.line?.id, "LW")
        XCTAssertEqual(moving.since?.id, "UN")
        XCTAssertNil(moving.train)
        XCTAssertEqual(moving.stops, 0)
        let oneStop = try XCTUnwrap(run.firstTime(sharing: 1))
        XCTAssertGreaterThan(oneStop, OnBoardFixtures.time(11, 23, 30))
        XCTAssertLessThan(oneStop, OnBoardFixtures.time(11, 24, 30))
    }

    // MARK: Never asked

    func testCarBesideTheLineIsNeverAsked() throws {
        var matcher = TrainMatcher()
        matcher.setCandidates(try dayOfTrains())
        let run = try self.run(&matcher, to: OnBoardFixtures.time(12, 10), phone: car(lights: []))
        XCTAssertNil(run.asked)
    }

    func testCarStoppingAtRedLightsIsNeverAsked() throws {
        var matcher = TrainMatcher()
        matcher.setCandidates(try dayOfTrains())
        let mimico = try XCTUnwrap(base.track).stopDistances[2]
        let run = try self.run(&matcher, to: OnBoardFixtures.time(12, 10), phone: car(lights: [2000, 6000, mimico + 50, 12000]))
        XCTAssertNil(run.asked)
    }

    func testPersonStandingOnThePlatformIsNeverAsked() throws {
        var matcher = TrainMatcher()
        matcher.setCandidates(try dayOfTrains())
        let exhibition = try XCTUnwrap(base.track).shape.point(at: try XCTUnwrap(base.track).stopDistances[1])
        let run = try self.run(&matcher, from: OnBoardFixtures.time(10, 50), to: OnBoardFixtures.time(12, 20)) { _ in exhibition }
        XCTAssertNil(run.asked)
        XCTAssertEqual(run.states.map { $0.state }, [.idle])
    }

    func testOneSharedStopNeverAsksOnTheTimetable() throws {
        // An express from Union to Exhibition, then Port Credit: one shared stop for 21 minutes.
        let express = try candidate("X", skipping: ["MI", "LO"])
        var matcher = TrainMatcher()
        matcher.setCandidates([express])
        let run = try self.run(&matcher, from: OnBoardFixtures.time(11, 17), phone: riding(express.plan))

        XCTAssertGreaterThan(try XCTUnwrap(run.asked), OnBoardFixtures.time(11, 45))
        XCTAssertEqual(question(of: matcher)?.stops.map(\.id), ["EX", "PO"])
    }

    // MARK: The feed's one stop and 3 minutes

    func testFeedAsksAfterOneStopAndThreeMinutesWhenStopsAreFarApart() throws {
        let express = try candidate("X", skipping: ["MI", "LO"])
        var matcher = TrainMatcher()
        matcher.setCandidates([express])
        let run = try self.run(&matcher, from: OnBoardFixtures.time(11, 17), phone: riding(express.plan), feedOf: [express])

        let asked = try XCTUnwrap(run.asked)
        XCTAssertGreaterThan(asked, OnBoardFixtures.time(11, 27, 20))
        XCTAssertLessThan(asked, OnBoardFixtures.time(11, 30))
        XCTAssertEqual(question(of: matcher)?.stops.map(\.id), ["EX"])
    }

    // MARK: Two trains

    func testLocalAndExpressAreBothOffered() throws {
        let local = try candidate("A")
        let express = try candidate("X-3", shift: -180, skipping: ["LO"])
        var matcher = TrainMatcher()
        matcher.setCandidates([local, express])
        try self.run(&matcher, phone: riding(local.plan))

        XCTAssertEqual(question(of: matcher)?.trains.map(\.trip.tripId), ["X-3", "A"])
    }

    func testOnlyTheLeastLateTrainsAreOffered() throws {
        // The train 15 min earlier fits too, running 15 min late: the question offers the two that fit on time.
        var matcher = TrainMatcher()
        matcher.setCandidates(try dayOfTrains())
        try self.run(&matcher, phone: riding(try candidate("A").plan))

        XCTAssertEqual(question(of: matcher)?.trains.map(\.trip.tripId), ["X-3", "T0"])
    }

    func testExpressOnTimeIsOfferedAlone() throws {
        let express = try candidate("X-3", shift: -180, skipping: ["LO"])
        var matcher = TrainMatcher()
        matcher.setCandidates(try dayOfTrains())
        try self.run(&matcher, from: OnBoardFixtures.time(11, 5), phone: riding(express.plan))

        XCTAssertEqual(question(of: matcher)?.trains.map(\.trip.tripId), ["X-3"])
    }

    // MARK: No, and an ignored question

    func testNoSilencesTheTrains() throws {
        let trains = try stride(from: -60, through: 90, by: 15).map { try candidate("T\($0)", shift: TimeInterval($0 * 60)) }
        let ride = try candidate("A").plan
        var matcher = TrainMatcher()
        matcher.setCandidates(trains)
        let asked = try XCTUnwrap(try self.run(&matcher, phone: riding(ride)).asked)
        XCTAssertEqual(question(of: matcher)?.trains.map(\.trip.tripId), ["T0"])

        XCTAssertEqual(matcher.decline().map(\.tripId), ["T0"])
        XCTAssertEqual(matcher.state, .idle)
        XCTAssertTrue(matcher.silenced.contains { $0.tripId == "T0" })
        let after = try self.run(&matcher, from: asked.addingTimeInterval(1), phone: riding(ride))
        XCTAssertNil(after.asked)
    }

    func testIgnoredQuestionGoesAtTheNextStation() throws {
        let train = try candidate("A")
        var matcher = TrainMatcher()
        matcher.setCandidates([train])
        let asked = try XCTUnwrap(try self.run(&matcher, from: OnBoardFixtures.time(11, 17), phone: riding(train.plan)).asked)
        let after = try self.run(&matcher, from: asked.addingTimeInterval(1), phone: riding(train.plan), untilAsked: false)

        // Standing at Long Branch (from 11:37:40), before the 3 minutes are up.
        let gone = try XCTUnwrap(after.states.first { $0.state == .idle }?.at)
        XCTAssertGreaterThan(gone, OnBoardFixtures.time(11, 37, 30))
        XCTAssertLessThan(gone.timeIntervalSince(asked), TrainMatcher.ignoreAfter)
        XCTAssertTrue(matcher.silenced.contains(train.trip))
        XCTAssertEqual(after.states.last?.state, .idle)
    }

    func testIgnoredQuestionGoesAfterThreeMinutes() throws {
        let express = try candidate("X", skipping: ["MI", "LO"])
        var matcher = TrainMatcher()
        matcher.setCandidates([express])
        let asked = try XCTUnwrap(
            try self.run(&matcher, from: OnBoardFixtures.time(11, 17), phone: riding(express.plan), feedOf: [express]).asked
        )
        let after = try self.run(
            &matcher, from: asked.addingTimeInterval(1), phone: riding(express.plan), feedOf: [express], untilAsked: false
        )

        let gone = try XCTUnwrap(after.states.first { $0.state == .idle }?.at)
        XCTAssertEqual(gone.timeIntervalSince(asked), TrainMatcher.ignoreAfter, accuracy: 2)
        XCTAssertTrue(matcher.silenced.contains(express.trip))
    }

    // MARK: Helpers

    /// What one run showed: when it asked, and each state with the moment it first showed.
    private struct Run {
        var asked: Date?
        var states: [(at: Date, state: TrainMatcher.State)] = []

        /// When the checking strip first counted `stops` shared stops.
        func firstTime(sharing stops: Int) -> Date? {
            states.first { entry in
                if case .checking(let progress) = entry.state { return progress.stops >= stops }
                return false
            }?.at
        }
    }

    /// Runs the matcher each second from `start` until it asks (or to `end`), with the phone where `phone` puts it and,
    /// for the trains in `feedOf`, GO's train feed placing each on its timetable every 15 s.
    @discardableResult
    private func run(
        _ matcher: inout TrainMatcher,
        from start: Date = OnBoardFixtures.time(11, 10),
        to end: Date = OnBoardFixtures.time(12, 0),
        phone: (Date) throws -> GeoPoint?,
        feedOf trains: [TrainCandidate] = [],
        untilAsked: Bool = true
    ) throws -> Run {
        var result = Run()
        var feed: [TripKey: TrainPosition] = [:]
        var lastFeed = Date.distantPast
        var time = start
        while time < end {
            if let point = try phone(time) {
                matcher.receive(LocationFix(coordinate: point, horizontalAccuracy: 8), at: time)
            }
            if !trains.isEmpty, time.timeIntervalSince(lastFeed) >= 15 {
                for train in trains {
                    let point = try place(of: train.plan, at: time)
                    feed[train.trip] = TrainPosition(coordinate: point, reportedAt: time)
                }
                lastFeed = time
            }
            matcher.update(feed: feed, at: time)
            if result.states.last?.state != matcher.state { result.states.append((time, matcher.state)) }
            if case .asking = matcher.state, result.asked == nil {
                result.asked = time
                if untilAsked { return result }
            }
            time.addTimeInterval(1)
        }
        return result
    }

    /// The phone on that train, `late` seconds behind its timetable.
    private func riding(_ plan: RidePlan, late: TimeInterval = 0) -> (Date) throws -> GeoPoint? {
        { time in try self.place(of: plan, at: time.addingTimeInterval(-late)) }
    }

    /// A car on the road 60 m north of the line from 11:17:30 at 50 km/h, standing 30 s at each red light (metres along).
    private func car(lights: [Double]) throws -> (Date) throws -> GeoPoint? {
        let shape = try XCTUnwrap(base.track).shape
        let start = OnBoardFixtures.time(11, 17, 30)
        let speed = 50 / 3.6
        return { time in
            var distance = max(time.timeIntervalSince(start), 0) * speed
            for light in lights where distance > light {
                distance -= min(30, (distance - light) / speed) * speed
            }
            var point = shape.point(at: distance)
            point.latitude += 60 / 111_195.08
            return point
        }
    }

    /// Where a train on that plan is at `time` (standing 20 s either side of each stop's time).
    private func place(of plan: RidePlan, at time: Date) throws -> GeoPoint {
        try XCTUnwrap(plan.track).shape.point(at: OnBoardFixtures.along(at: time, plan: plan))
    }

    /// The 11:17 AM train `shift` seconds later, without the stations in `skipping`.
    private func candidate(_ id: String, shift: TimeInterval = 0, skipping: Set<String> = []) throws -> TrainCandidate {
        let track = try XCTUnwrap(base.track)
        let kept = base.stops.indices.filter { !skipping.contains(base.stops[$0].station.id) }
        let plan = RidePlan(
            stops: kept.map { index in
                let stop = base.stops[index]
                return RidePlan.Stop(
                    station: stop.station,
                    arrival: stop.arrival.addingTimeInterval(shift),
                    departure: stop.departure.addingTimeInterval(shift)
                )
            },
            track: RidePlan.Track(shape: track.shape, stopDistances: kept.map { track.stopDistances[$0] })
        )
        let route = Route(from: base.stops[0].station, to: base.stops[base.stops.count - 1].station, line: line)
        return TrainCandidate(trip: TripKey(serviceDay: OnBoardFixtures.friday, tripId: id), route: route, plan: plan)
    }

    /// A timetable morning: a train every 15 min from 10:17 to 12:47 (`T-60` … `T90`, `T0` the 11:17), and an express 3 min
    /// ahead of the 11:17 that skips Long Branch (`X-3`).
    private func dayOfTrains() throws -> [TrainCandidate] {
        try stride(from: -60, through: 90, by: 15).map { try candidate("T\($0)", shift: TimeInterval($0 * 60)) }
            + [try candidate("X-3", shift: -180, skipping: ["LO"])]
    }

    private func question(of matcher: TrainMatcher) -> TrainMatcher.Question? {
        if case .asking(let question) = matcher.state { return question }
        return nil
    }
}

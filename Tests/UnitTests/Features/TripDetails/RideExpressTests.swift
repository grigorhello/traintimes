import XCTest
@testable import TrainTimes

/// TT-232, D111: a ride that passes stations without stopping. Which stations are skipped and where they lie on a stretch,
/// the rail's rows with them between the stops, the train's place across them, the bolt's loop, the Live Activity's
/// content and `ride_started`'s new properties. The demo express is the 5:13 PM train from Union to Clarkson without
/// stopping, at Clarkson at 5:39 PM.
@MainActor
final class RideExpressTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)
    private let day = DemoRideRig.day

    private func t(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        DemoRideRig.time(hours, minutes, seconds)
    }

    private func details(_ rig: DemoRideRig) throws -> RideDetails {
        try XCTUnwrap(rig.onBoard.details(for: rig.key, formatter: formatter))
    }

    private func stop(_ id: String, _ name: String, _ time: Date) -> RidePlan.Stop {
        RidePlan.Stop(station: Station(id: id, name: name), arrival: time, departure: time)
    }

    /// Union, Mimico and Clarkson: Exhibition is passed on the first stretch, Long Branch and Port Credit on the second.
    private func mixedPlan() -> RidePlan {
        let stops = [stop("UN", "Union Station GO", t(17, 13)), stop("MI", "Mimico GO", t(17, 25)), stop("CL", "Clarkson GO", t(17, 43))]
        return RidePlan(stops: stops, track: nil, skipped: RidePlan.skipped(stops: stops, track: nil, lineId: "LW"))
    }

    private func state(_ phase: RidePhase, next: Station?, arrival: Date) -> RideState {
        RideState(
            phase: phase, currentStop: nil, nextStop: next, stopsLeft: 1, minutesToYourStop: 0,
            expectedArrival: arrival, source: .trainFeed, lastUpdate: nil
        )
    }

    // MARK: Which stations are skipped

    func testTheLinesOrderGivesTheStationsBetweenTwoStops() {
        XCTAssertEqual(GONetwork.stationsBetween(["UN", "CL"], onLine: "LW")?.map { $0.map(\.id) }, [["EX", "MI", "LO", "PO"]])
        XCTAssertEqual(
            GONetwork.stationsBetween(["CL", "UN"], onLine: "LW")?.map { $0.map(\.id) }, [["PO", "LO", "MI", "EX"]],
            "Towards Union: in the order the train passes them"
        )
        XCTAssertEqual(GONetwork.stationsBetween(["UN", "MI", "CL"], onLine: "LW")?.map { $0.map(\.id) }, [["EX"], ["LO", "PO"]])
        XCTAssertEqual(GONetwork.stationsBetween(["EX", "MI"], onLine: "LW")?.map { $0.map(\.id) }, [[]], "Neighbours")
    }

    func testAnUnknownOrderFallsBackToTheStopsOnly() {
        XCTAssertNil(GONetwork.stationsBetween(["UN", "CL"], onLine: "XX"), "A line the app does not know")
        XCTAssertNil(GONetwork.stationsBetween(["UN", "ZZ"], onLine: "LW"), "A stop that is not on the line")
        XCTAssertNil(GONetwork.stationsBetween(["UN", "CL", "MI"], onLine: "LW"), "Stops that do not run one way along it")
        let stops = [stop("UN", "Union Station GO", t(17, 13)), stop("ZZ", "Elsewhere GO", t(17, 39))]
        XCTAssertEqual(RidePlan.skipped(stops: stops, track: nil, lineId: "LW"), [])
        XCTAssertEqual(RidePlan.skipped(stops: DemoRide.plan(on: day, express: true).stops, track: nil, lineId: nil), [])
        let plan = RidePlan(stops: stops, track: nil)
        let ride = RideDetails(plan: plan, state: state(.yourStopNext, next: stops[1].station, arrival: t(17, 39)), now: t(17, 20), formatter: formatter)
        XCTAssertEqual(ride?.stops.map(\.id), ["UN", "ZZ"])
        XCTAssertEqual(ride?.stops.contains(where: \.isSkipped), false)
    }

    func testWithNoTrackTheSkippedStationsAreSpacedEvenly() {
        let skipped = mixedPlan().skipped
        XCTAssertEqual(skipped.map(\.station.id), ["EX", "LO", "PO"])
        XCTAssertEqual(skipped.map(\.after), [0, 1, 1])
        XCTAssertEqual(skipped[0].along, 0.5, accuracy: 0.0001)
        XCTAssertEqual(skipped[1].along, 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(skipped[2].along, 2.0 / 3, accuracy: 0.0001)
    }

    func testOnATrackTheyAreSpacedByDistanceAndAStationOffTheTrackIsLeftOut() throws {
        let plan = DemoRide.plan(on: day, express: true)
        XCTAssertTrue(plan.isExpress)
        XCTAssertEqual(plan.stops.map(\.station.id), ["UN", "CL"])
        XCTAssertEqual(plan.skipped.map(\.station.id), ["EX", "MI", "LO", "PO"])
        XCTAssertEqual(plan.skipped.map(\.after), [0, 0, 0, 0])
        for (along, expected) in zip(plan.skipped.map(\.along), [0.126, 0.384, 0.569, 0.766]) {
            XCTAssertEqual(along, expected, accuracy: 0.005, "Where the station is along the track from Union to Clarkson")
        }
        // Mimico placed 5 km north of the track, as a station on another branch would be.
        let stopping = DemoRide.plan(on: day)
        var places: [String: GeoPoint] = [:]
        for stop in stopping.stops {
            places[stop.station.id] = try XCTUnwrap(stop.station.place)
        }
        places["MI"] = GeoPoint(latitude: 43.6614, longitude: -79.4978)
        let onTrack = RidePlan.skipped(stops: plan.stops, track: plan.track, lineId: "LW", places: places)
        XCTAssertEqual(onTrack.map(\.station.id), ["EX", "LO", "PO"])
        // A train that stops everywhere passes nothing.
        XCTAssertEqual(stopping.skipped, [])
        XCTAssertFalse(stopping.isExpress)
    }

    func testTheFeedsExpressSkipsTheFourStationsBetweenUnionAndClarkson() throws {
        let timetable = GTFSTimetable(feed: try GTFSFeed(zip: GTFSTimetableTests.sampleZip(), importedAt: Date(timeIntervalSince1970: 0)))
        let friday = ServiceDay(year: 2026, month: 11, day: 27)
        // The 4:50 PM from Union calls at Clarkson next; the 5:05 PM calls everywhere.
        let express = Ride(trip: TripKey(serviceDay: friday, tripId: "20261127-LW-1875"), from: "UN", to: "CL")
        let plan = try XCTUnwrap(timetable.ridePlan(for: express))
        XCTAssertEqual(plan.stops.map(\.station.id), ["UN", "CL"])
        XCTAssertEqual(plan.skipped.map(\.station.id), ["EX", "MI", "LO", "PO"])
        XCTAssertTrue(plan.isExpress)
        let stopping = Ride(trip: TripKey(serviceDay: friday, tripId: "20261127-LW-1127"), from: "UN", to: "CL")
        let all = try XCTUnwrap(timetable.ridePlan(for: stopping))
        XCTAssertEqual(all.stops.count, 6)
        XCTAssertEqual(all.skipped, [])
        XCTAssertFalse(all.isExpress)
    }

    // MARK: The rows

    func testTheExpressListsEveryStationWithTheFourBetweenDisabled() async throws {
        let rig = await DemoRideRig.express(at: t(17, 29))
        let ride = try details(rig)
        XCTAssertEqual(ride.moment, .yourStopNext, "Nothing between the train and your stop")
        XCTAssertEqual(ride.kicker, "Clarkson is next")
        XCTAssertEqual(ride.countdown, "10 min")
        XCTAssertTrue(ride.isExpress)
        XCTAssertEqual(ride.stops.map(\.id), ["UN", "EX", "MI", "LO", "PO", "CL"])
        XCTAssertEqual(ride.stops.map(\.name), ["Union Station", "Exhibition", "Mimico", "Long Branch", "Port Credit", "Clarkson"])
        XCTAssertEqual(ride.stops.map(\.index), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(ride.stops.map(\.isSkipped), [false, true, true, true, true, false])
        XCTAssertEqual(ride.stops.map(\.time), [nil, nil, nil, nil, nil, "5:39 PM"], "Only your stop has a time")
        XCTAssertEqual(ride.stops.map(\.isNext), [false, false, false, false, false, true])
        XCTAssertEqual(ride.rows.map(\.id), ["UN", "EX", "MI", "LO", "PO", "CL"], "Six rows fit: no fold")
        // 16 of the 26 minutes gone: past Long Branch (57 % of the way), before Port Credit (77 %).
        let position = try XCTUnwrap(ride.trainPosition)
        XCTAssertGreaterThan(position, 3)
        XCTAssertLessThan(position, 4)
        XCTAssertEqual(ride.stops.map(\.isDone), [true, true, true, true, false, false], "The rings behind the train are passed")
        XCTAssertEqual(ride.passed, 0, "No stop has passed: a skipped station plays no Tick")
        XCTAssertEqual(ride.stretch, 0..<5)
        XCTAssertTrue(ride.softensLastStretch)
        XCTAssertEqual(ride.loop, RideMotion.movingLoop)
    }

    func testTheExpressMovesThroughTheRowsAndStopsAtYours() async throws {
        let rig = await DemoRideRig.express(at: t(17, 22))
        let early = try XCTUnwrap(try details(rig).trainPosition)
        XCTAssertGreaterThan(early, 1, "Past Exhibition")
        XCTAssertLessThan(early, 2, "Before Mimico")
        rig.drive(to: t(17, 26))
        let later = try XCTUnwrap(try details(rig).trainPosition)
        XCTAssertGreaterThan(later, 2, "Through Mimico without pausing")
        XCTAssertEqual(try details(rig).passed, 0)
        rig.drive(to: t(17, 39, 5))
        let there = try details(rig)
        XCTAssertEqual(there.moment, .atYourStop)
        XCTAssertNil(there.trainPosition)
        XCTAssertEqual(there.stops.map(\.isDone), [true, true, true, true, true, true])
        XCTAssertEqual(there.passed, 5)
        XCTAssertEqual(there.rows.map(\.id), ["UN", "EX", "MI", "LO", "PO", "CL"])
        XCTAssertEqual(there.stops.last?.time, "5:39 PM")
    }

    func testStopsAndSkippedStationsMix() throws {
        let plan = mixedPlan()
        // 5:16 PM, a quarter of the way to Mimico: half way to Exhibition's row.
        let first = try XCTUnwrap(RideDetails(
            plan: plan, state: state(.riding, next: plan.stops[1].station, arrival: t(17, 43)), now: t(17, 16), formatter: formatter
        ))
        XCTAssertEqual(first.stops.map(\.id), ["UN", "EX", "MI", "LO", "PO", "CL"])
        XCTAssertEqual(first.stops.map(\.isSkipped), [false, true, false, true, true, false])
        XCTAssertEqual(first.stops.map(\.time), [nil, nil, "5:25 PM", nil, nil, "5:43 PM"])
        XCTAssertEqual(first.stops.map(\.isNext), [false, false, true, false, false, false])
        XCTAssertEqual(try XCTUnwrap(first.trainPosition), 0.5, accuracy: 0.0001)
        XCTAssertEqual(first.passed, 0)
        XCTAssertEqual(first.stretch, 0..<2)
        XCTAssertEqual(first.stops.map(\.isDone), [true, false, false, false, false, false])
        XCTAssertFalse(first.isExpress, "Skipped stations show whether or not the trip has the express tag")
        // 5:34 PM, half way from Mimico to Clarkson: half way between Long Branch's row and Port Credit's.
        let second = try XCTUnwrap(RideDetails(
            plan: plan, state: state(.yourStopNext, next: plan.stops[2].station, arrival: t(17, 43)), now: t(17, 34), formatter: formatter
        ))
        XCTAssertEqual(try XCTUnwrap(second.trainPosition), 3.5, accuracy: 0.0001)
        XCTAssertEqual(second.passed, 2, "Mimico's row")
        XCTAssertEqual(second.stretch, 2..<5)
        XCTAssertEqual(second.stops.map(\.isDone), [true, true, true, true, false, false])
        XCTAssertEqual(second.stops.map(\.time), [nil, nil, nil, nil, nil, "5:43 PM"])
    }

    private func stations(_ count: Int, skipped: Set<Int>) -> [RideDetails.Stop] {
        (0..<count).map { index in
            RideDetails.Stop(
                id: "S\(index)", index: index, name: "Station \(index)", time: nil, isFirst: index == 0,
                isYours: index == count - 1, isDone: false, isNext: false, isLate: false, isSkipped: skipped.contains(index)
            )
        }
    }

    func testALongExpressFoldsSoYourStopFits() {
        let seven = stations(7, skipped: [1, 2, 3, 4, 5])
        XCTAssertEqual(RideDetails.rows(seven, passed: 0).map(\.id), ["S0", "S1", "S2", "S3", "S4", "S5", "S6"], "Seven rows fit")
        // Twelve stations, nothing between the two ends: the row behind the train, the next two, a fold, your stop.
        let twelve = stations(12, skipped: Set(1...10))
        XCTAssertEqual(RideDetails.rows(twelve, passed: 0).map(\.id), ["S0", "S1", "S2", "fold.S2", "S11"])
        XCTAssertEqual(RideDetails.rows(twelve, at: 5.4).map(\.id), ["S0", "fold.S0", "S5", "S6", "S7", "fold.S7", "S11"])
        XCTAssertEqual(RideDetails.rows(twelve, at: nil).map(\.id), ["S0", "fold.S0", "S10", "S11"], "At your stop")
        XCTAssertTrue(RideDetails.rows(twelve, at: 9.9).contains { $0.id == "S11" })
        // A train that stops everywhere folds as before, however short.
        XCTAssertEqual(RideDetails.rows(stations(6, skipped: []), passed: 3).map(\.id), ["S0", "fold.S0", "S3", "S4", "S5"])
    }

    // MARK: The train's place

    func testTheTrainPassesASkippedRowWhenTheClockReachesItsPlace() {
        XCTAssertEqual(RideDetails.rowsPast(0.5, along: []), 0.5, "No station between: as before")
        let along = [0.2, 0.6]
        XCTAssertEqual(RideDetails.rowsPast(0.1, along: along), 0.5, accuracy: 0.0001)
        XCTAssertEqual(RideDetails.rowsPast(0.2, along: along), 1, accuracy: 0.0001, "On the first skipped row")
        XCTAssertEqual(RideDetails.rowsPast(0.4, along: along), 1.5, accuracy: 0.0001)
        XCTAssertEqual(RideDetails.rowsPast(0.6, along: along), 2, accuracy: 0.0001)
        XCTAssertEqual(RideDetails.rowsPast(0.76, along: along), 2.46, accuracy: 0.0001)
        XCTAssertEqual(RideDetails.rowsPast(0.92, along: along), 2.92, accuracy: 0.0001, "The clock's furthest: 0.92 of the last row")
        XCTAssertEqual(RideDetails.rowsPast(0.5, along: [0.6, 0.2]), 1.5, accuracy: 0.0001, "Out of order: evenly")
    }

    func testASkippedRowIsPassedOnceTheTrainIsAtOrPastIt() {
        XCTAssertTrue(RideDetails.hasPassed(row: 3, at: 3.2))
        XCTAssertTrue(RideDetails.hasPassed(row: 3, at: 3))
        XCTAssertFalse(RideDetails.hasPassed(row: 4, at: 3.2))
        XCTAssertTrue(RideDetails.hasPassed(row: 4, at: nil), "At your stop")
    }

    func testTheTrainNeverGoesBackAcrossASkippedRow() {
        XCTAssertEqual(RideDetails.forward(2.9, from: 3.1, stretch: 0..<5), 3.1, "One stretch from Union to Clarkson")
        XCTAssertEqual(RideDetails.forward(3.3, from: 3.1, stretch: 0..<5), 3.3)
        XCTAssertEqual(RideDetails.forward(2.9, from: 3.1), 2.9, "With no stretch given, a new row shows as it is")
        XCTAssertEqual(RideDetails.forward(2, from: 1.9, stretch: 2..<5), 2, "At a stop: as it is")
        XCTAssertEqual(RideDetails.forward(2.4, from: 1.9, stretch: 2..<5), 2.4, "A new stretch")
    }

    func testTheRailRunsTheGlintToTheNextStopAndKeepsThePinsGap() async throws {
        let rig = await DemoRideRig.express(at: t(17, 29))
        let ride = try details(rig)
        let rail = RideRail(rows: ride.rows, stopCount: ride.stops.count)
        XCTAssertEqual(rail.tops, [0, 50, 100, 150, 200, 250])
        XCTAssertEqual(rail.trainY(3.5), 200, "Half way from Long Branch's row to Port Credit's")
        XCTAssertEqual(rail.nextY(3.5), 275, "The glint runs to Clarkson, the next stop, not to Port Credit's ring")
        XCTAssertEqual(rail.trainY(4.92), 275 - 24, accuracy: 0.001, "At the clock's furthest: 24 pt short of the pin")
        XCTAssertEqual(rail.trainY(nil), 275)
    }

    // MARK: The bolt

    func testTheBoltFlashesAtTheStartOfTheLoopThenDips() {
        XCTAssertEqual(RideMotion.boltScale(0), 1)
        XCTAssertEqual(RideMotion.boltScale(0.06), 1.35, accuracy: 0.0001)
        XCTAssertEqual(RideMotion.boltScale(0.13), 0.94, accuracy: 0.0001)
        XCTAssertEqual(RideMotion.boltScale(0.2), 1, accuracy: 0.0001)
        XCTAssertEqual(RideMotion.boltScale(0.7), 1, "Only in the first fifth of the loop")
        XCTAssertEqual(RideMotion.boltTilt(0.06), -10, accuracy: 0.0001)
        XCTAssertEqual(RideMotion.boltTilt(0.5), 0)
        XCTAssertEqual(RideMotion.boltOpacity(0.1), 1)
        XCTAssertEqual(RideMotion.boltOpacity(0.6), 0.55, accuracy: 0.0001)
        XCTAssertEqual(RideMotion.boltOpacity(0.8), 0.775, accuracy: 0.0001)
        XCTAssertEqual(RideMotion.boltOpacity(1), 1, accuracy: 0.0001)
    }

    // MARK: The Live Activity

    private func content(_ rig: DemoRideRig) throws -> RideActivityAttributes.ContentState {
        let engine = try XCTUnwrap(rig.engine)
        return try XCTUnwrap(RideActivityAttributes.ContentState(
            plan: rig.plan, state: try XCTUnwrap(engine.state), now: engine.now, deviceNow: engine.now, formatter: formatter
        ))
    }

    func testTheActivityOnAnExpressHasEveryStationTheSkippedOnesHollowAndTheBolt() async throws {
        let rig = await DemoRideRig.express(at: t(17, 29))
        let content = try content(rig)
        XCTAssertEqual(content.title, "Clarkson is next")
        XCTAssertEqual(content.minutes, "10 min")
        XCTAssertEqual(content.value, "5:39 PM")
        XCTAssertEqual(content.stations, 6)
        XCTAssertEqual(content.skipped, [1, 2, 3, 4])
        XCTAssertTrue(content.express)
        XCTAssertEqual(content.position, try XCTUnwrap(try details(rig).trainPosition), accuracy: 0.0001, "Where the ride screen has it")
        // The attributes keep the ride's stops, as the alert server counts them for the same train.
        let attributes = RideActivityAttributes(ride: DemoRide.ride(on: day), plan: rig.plan, line: DemoRide.line)
        XCTAssertEqual(attributes.stopCount, 2)
        // It travels as JSON and comes back the same.
        let decoded = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: JSONEncoder().encode(content))
        XCTAssertEqual(decoded.stations, 6)
        XCTAssertEqual(decoded.skipped, [1, 2, 3, 4])
        XCTAssertTrue(decoded.express)
        XCTAssertEqual(decoded.position, content.position)

        rig.drive(to: t(17, 39, 5))
        XCTAssertEqual(try self.content(rig).position, 5, "At your stop: the last dot")
    }

    func testTheActivityOnATrainThatStopsEverywhereIsAsBefore() async throws {
        let rig = await DemoRideRig.started()
        let content = try content(rig)
        XCTAssertNil(content.stations)
        XCTAssertEqual(content.skipped, [])
        XCTAssertFalse(content.express)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(content), encoding: .utf8))
        XCTAssertFalse(json.contains("stations"))
        XCTAssertFalse(json.contains("skipped"))
        XCTAssertFalse(json.contains("express"))
    }

    // MARK: Analytics and the demo

    func testRideStartedSaysExpressAndHowManyStationsArePassed() async throws {
        let analytics = RecordingAnalytics.install()
        defer { Analytics.tracker = nil }
        let clock = TestClock(now: t(17, 20))
        let express = OnBoard(app: DemoRide.engine(on: day, clock: clock, tickInterval: nil, express: true), makeDemoDetector: nil)
        let started = await express.start(DemoRide.ride(on: day), on: DemoRide.route)
        XCTAssertTrue(started)
        let first = try XCTUnwrap(analytics.events.last { $0.name == "ride_started" })
        XCTAssertEqual(first.properties["express"], .bool(true))
        XCTAssertEqual(first.properties["skipped_stations"], .int(4))
        XCTAssertEqual(first.properties["demo"], .bool(false))

        let stopping = OnBoard(app: DemoRide.engine(on: day, clock: clock, tickInterval: nil), makeDemoDetector: nil)
        _ = await stopping.start(DemoRide.ride(on: day), on: DemoRide.route)
        let second = try XCTUnwrap(analytics.events.last { $0.name == "ride_started" })
        XCTAssertEqual(second.properties["express"], .bool(false))
        XCTAssertEqual(second.properties["skipped_stations"], .int(0))
    }

    func testTheTestingSwitchIsKeptAndResetTurnsItOff() {
        let defaults = UserDefaults.ephemeral()
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.demoExpress)
        let model = SettingsViewModel(
            settings: settings, permissions: FakeNotificationPermission(.allowed), appInfo: AppInfo(version: "1.0", build: "1"),
            showsTesting: true, clock: FixedClock(now: t(17, 0))
        )
        XCTAssertFalse(model.showsDemoExpress, "Only with Ride or Depart")
        model.demoTrains = .ride
        XCTAssertTrue(model.showsDemoExpress)
        model.demoExpress = true
        XCTAssertTrue(defaults.bool(forKey: DemoRide.expressKey))
        XCTAssertTrue(AppSettings(defaults: defaults).demoExpress)
        model.resetTesting()
        XCTAssertFalse(settings.demoExpress)
        XCTAssertFalse(defaults.bool(forKey: DemoRide.expressKey))
    }
}

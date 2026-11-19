import XCTest
@testable import TrainTimes

/// Automatic direction's look (TT-234, D116), driven as `ScheduleView` drives it: the scene on every change, the
/// readings as the reader hands them over, touches, the background and the return. The route is Oakville to Union, so
/// a reading at Union is the rider at the To end. Times the look counts are passed in: a test that wants an answer in
/// time gives the look a long quick time, one that wants it late a short one.
@MainActor
final class DirectionLookTests: XCTestCase {
    private let route = DirectionFixtures.route
    /// 8:00 AM on Thu Nov 19, Toronto.
    private let morning = ServiceDay(year: 2026, month: 11, day: 19).date(hour: 8, minute: 0)
    /// 5:30 PM the same day.
    private let evening = ServiceDay(year: 2026, month: 11, day: 19).date(hour: 17, minute: 30)

    /// Union to Oakville: the route after a turn.
    private var turned: Route { Route(from: route.to, to: route.from, line: route.line) }
    /// Clarkson to Union: another route the rider may pick.
    private var picked: Route { Route(from: Station(id: "CL", name: "Clarkson GO"), to: route.to, line: route.line) }

    /// Schedule in front on Today with nothing over it.
    private var front: DirectionLook.Scene { DirectionLook.Scene(isActive: true, isInFront: true) }
    /// The same under the launch splash.
    private var underSplash: DirectionLook.Scene {
        DirectionLook.Scene(isActive: true, isInFront: true, launchCovers: true)
    }
    /// The scene no longer active: Control Centre, an iOS prompt.
    private var inactive: DirectionLook.Scene { DirectionLook.Scene(isActive: false, isInFront: true) }
    /// Something over Schedule while the scene stays active: a sheet of the app's, something of Schedule's own, a
    /// bell's capsule.
    private var covers: [DirectionLook.Scene] {
        [
            DirectionLook.Scene(isActive: true, isInFront: false),
            DirectionLook.Scene(isActive: true, isInFront: true, isBusy: true),
            DirectionLook.Scene(isActive: true, isInFront: true, hasBellCapsule: true),
        ]
    }

    private var atUnion: DirectionReading { DirectionFixtures.reading(at: DirectionFixtures.unionPlace) }
    private var atOakville: DirectionReading { DirectionFixtures.reading(at: DirectionFixtures.oakvillePlace) }
    /// Half way between the two stations.
    private var inBetween: DirectionReading {
        let oakville = DirectionFixtures.oakvillePlace
        let union = DirectionFixtures.unionPlace
        return DirectionFixtures.reading(
            at: GeoPoint(
                latitude: (oakville.latitude + union.latitude) / 2, longitude: (oakville.longitude + union.longitude) / 2
            )
        )
    }

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    // MARK: Helpers

    /// Waits for what the look does in its own tasks: the station list, the turn, a capsule.
    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out", file: file, line: line)
    }

    /// Long enough for the look's tasks and its short timers to have run, before a check that nothing happened.
    private func pause() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    /// A look at the To station that turns the route, up to its "Now from Union" capsule.
    private func turnAtUnion(_ rig: Rig, file: StaticString = #filePath, line: UInt = #line) async {
        rig.look.update(front)
        rig.location.send(atUnion)
        await eventually({ rig.schedule.turnCount == 1 && rig.capsule == .turned(station: "Union") }, file: file, line: line)
    }

    /// A look whose answer comes after a touch, up to its "Trains from Union?" capsule.
    private func askAtUnion(_ rig: Rig, file: StaticString = #filePath, line: UInt = #line) async {
        rig.look.update(front)
        rig.look.touched()
        rig.location.send(atUnion)
        await eventually({ rig.capsule == .asks(station: "Union") }, file: file, line: line)
    }

    // MARK: The gates

    /// The launch where the welcome sets the first route has no look; the next visit has one.
    func testNoLookInTheLaunchThatBeganWithoutARoute() {
        let rig = Rig(route: nil, now: evening)
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.noRoute))

        let welcomed = Rig(route: nil, now: evening)
        welcomed.schedule.route = route
        welcomed.look.update(front)
        XCTAssertEqual(welcomed.outcome, .nothing(.noRoute))
        XCTAssertEqual(welcomed.look.lastLook?.waited, 0)
        XCTAssertEqual(welcomed.location.starts, 0)
        XCTAssertFalse(welcomed.look.isLooking)

        welcomed.look.wentToBackground()
        welcomed.look.update(front)
        XCTAssertEqual(welcomed.location.starts, 1)
        XCTAssertTrue(welcomed.look.isLooking)
    }

    func testNoLookWhileTheRiderTurnedItOff() {
        let rig = Rig(now: evening)
        XCTAssertTrue(rig.look.isOn)
        rig.store.isOff = true
        XCTAssertFalse(rig.look.isOn)

        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.off))
        XCTAssertEqual(rig.location.starts, 0)
        XCTAssertEqual(rig.location.requests, 0)
    }

    /// Location not asked yet, refused or with no reader: no look, and the look never asks.
    func testNoLookWithoutLocationAndTheLookNeverAsks() {
        for permission in [DirectionPermission.notAsked, .refused, .unavailable] {
            let rig = Rig(permission: permission, now: evening)
            XCTAssertFalse(rig.look.isOn, "\(permission)")
            rig.look.update(front)
            XCTAssertEqual(rig.outcome, .nothing(.off), "\(permission)")
            XCTAssertEqual(rig.location.starts, 0, "\(permission)")
            XCTAssertEqual(rig.location.requests, 0, "\(permission)")
            XCTAssertEqual(rig.location.permission, permission, "the prompt would have changed it")
        }
    }

    func testNoLookWithPreciseLocationOff() {
        let rig = Rig(isPrecise: false, now: evening)
        XCTAssertFalse(rig.look.isOn)
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.off))
        XCTAssertEqual(rig.location.starts, 0)
        XCTAssertEqual(rig.location.requests, 0)
    }

    /// The permission is read right before each start: Allow Once can run out between two visits.
    func testThePermissionIsReadBeforeEachStart() {
        let rig = Rig(now: evening)
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 1)

        rig.look.wentToBackground()
        rig.location.permission = .notAsked
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.off))
        XCTAssertEqual(rig.location.starts, 1)

        rig.look.wentToBackground()
        rig.location.permission = .allowed
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 2)
        XCTAssertEqual(rig.location.requests, 0)
    }

    /// During a ride, or while one is saved on device and not restored yet.
    func testNoLookWhileARideIsHeld() {
        let rig = Rig(now: evening)
        rig.ride.holdsRide = true
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.riding))
        XCTAssertEqual(rig.location.starts, 0)
    }

    /// A route chosen by hand is kept until the app has been out of view for more than 10 min.
    func testAChoiceByHandHoldsUntilMoreThan10MinOutOfView() {
        let rig = Rig(now: evening)
        rig.look.chose(route, by: .byHand)
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.chosenByHand))
        XCTAssertEqual(rig.location.starts, 0)

        rig.look.wentToBackground()
        rig.clock.advance(minutes: 10)
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.chosenByHand))
        XCTAssertEqual(rig.location.starts, 0, "10 min out of view")

        rig.look.wentToBackground()
        rig.clock.advance(minutes: 11)
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 1, "more than 10 min out of view")
        XCTAssertTrue(rig.look.isLooking)
    }

    /// After Undo the route is not turned between those two stations for an hour, whichever way it points.
    func testTheUndoHourHoldsTheLook() {
        let rig = Rig(now: evening)
        rig.store.startUndoHour(for: turned, at: rig.clock.now)
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.undone))
        XCTAssertEqual(rig.location.starts, 0)

        rig.look.wentToBackground()
        rig.clock.advance(minutes: 59)
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 0)

        rig.look.wentToBackground()
        rig.clock.advance(minutes: 1)
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 1, "the hour is over")
    }

    /// Detect my train's offer goes first: the look waits for its sheet to close.
    func testTheLookWaitsForDetectMyTrainsOffer() {
        let rig = Rig(now: evening)
        rig.offer.isDue = true
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 0)
        XCTAssertNil(rig.look.lastLook)

        rig.offer.isDue = false
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 1)
        XCTAssertTrue(rig.look.isLooking)
    }

    func testTheLookWaitsForToday() {
        let rig = Rig(now: evening)
        rig.schedule.isToday = false
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 0)
        XCTAssertNil(rig.look.lastLook)

        rig.schedule.isToday = true
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 1)
    }

    /// With something over Schedule, or the scene not active yet, the look starts once that is gone.
    func testTheLookWaitsUntilNothingIsOverSchedule() {
        for cover in covers + [inactive] {
            let rig = Rig(now: evening)
            rig.look.update(cover)
            XCTAssertEqual(rig.location.starts, 0, "\(cover)")
            XCTAssertFalse(rig.look.isLooking, "\(cover)")
            XCTAssertNil(rig.look.lastLook, "\(cover)")

            rig.look.update(front)
            XCTAssertEqual(rig.location.starts, 1, "\(cover)")
            XCTAssertTrue(rig.look.isLooking, "\(cover)")
            XCTAssertTrue(rig.location.isReading, "\(cover)")
        }
    }

    // MARK: One look per visit

    /// One look per visit, whatever opens and closes over Schedule; back from the background is a new visit.
    func testOneLookPerVisit() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.location.send(atOakville)
        await eventually { rig.outcome == .nothing(.alreadyCloser) }

        for cover in covers + [inactive] {
            rig.look.update(cover)
            rig.look.update(front)
        }
        XCTAssertEqual(rig.location.starts, 1)

        rig.look.wentToBackground()
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 2)
        XCTAssertTrue(rig.look.isLooking)
    }

    /// A new visit cancels a look still running: the reader stops and a reading on its way is not heard.
    func testTheBackgroundEndsARunningLook() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.look.wentToBackground()

        XCTAssertFalse(rig.look.isLooking)
        XCTAssertFalse(rig.location.isReading)
        XCTAssertEqual(rig.outcome, .nothing(.left))
        rig.location.send(atUnion)
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 0)
        XCTAssertNil(rig.capsule)
    }

    /// The scene leaving active stops the look, and coming back from inactive is not a new visit.
    func testLeavingActiveStopsTheLook() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.look.update(inactive)

        XCTAssertFalse(rig.look.isLooking)
        XCTAssertFalse(rig.location.isReading)
        XCTAssertEqual(rig.location.stops, 1)
        XCTAssertEqual(rig.outcome, .nothing(.left))

        rig.look.update(front)
        await pause()
        XCTAssertEqual(rig.location.starts, 1)
        XCTAssertEqual(rig.schedule.turnCount, 0)
    }

    // MARK: Turn or ask

    /// An answer in time turns the route: silent, and "Now from Union" comes after the capsule's delay.
    func testAnAnswerInTimeTurnsTheRoute() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        XCTAssertTrue(rig.look.isLooking)
        XCTAssertTrue(rig.location.isReading)

        let sent = ContinuousClock.now
        rig.location.send(atUnion)
        await eventually { rig.schedule.turnCount == 1 }
        XCTAssertEqual(rig.schedule.route, turned)
        XCTAssertEqual(rig.outcome, .turn)
        XCTAssertFalse(rig.look.isLooking)
        XCTAssertFalse(rig.location.isReading)

        await eventually { rig.capsule != nil }
        XCTAssertEqual(rig.capsule, .turned(station: "Union"))
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - sent, rig.capsuleDelay)
        XCTAssertTrue(rig.haptics.played.isEmpty, "the turn is silent")
        XCTAssertEqual(rig.location.requests, 0)
        XCTAssertFalse(rig.store.holdsChoice(at: rig.clock.now), "the app's turn is not the rider's choice")
        XCTAssertNil(rig.store.morningWay)
    }

    /// A reading comes with its radius and its age: a fresh enough one still gives the answer.
    func testAReadingWithAnAgeStillAnswers() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.location.send(DirectionFixtures.reading(at: DirectionFixtures.unionPlace, radius: 65, age: 12))
        await eventually { rig.schedule.turnCount == 1 }
        XCTAssertEqual(rig.outcome, .turn)
    }

    /// The places come from the station list by id: the saved route carries none.
    func testThePlacesComeFromTheStationList() async {
        let saved = Route(
            from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station"), line: nil
        )
        XCTAssertNil(saved.from.place)
        let rig = Rig(route: saved, now: evening)
        rig.look.update(front)
        rig.location.send(atUnion)
        await eventually { rig.schedule.turnCount == 1 }
        XCTAssertEqual(rig.schedule.route?.from.id, "UN")
    }

    /// No place for one of the two stations, or no station list yet: no look.
    func testNoPlacesNoLook() async {
        let unplaced = PlacedDirectionStations(list: [DirectionFixtures.oakville, Station(id: "UN", name: "Union Station")])
        let stationLists: [any StationRepository] = [unplaced, PlacedDirectionStations(list: []), FailingStations()]
        for stations in stationLists {
            let rig = Rig(stations: stations, now: evening)
            rig.look.update(front)
            rig.location.send(atUnion)
            await eventually { rig.outcome == .nothing(.noPlaces) }
            XCTAssertFalse(rig.look.isLooking)
            XCTAssertFalse(rig.location.isReading)
            XCTAssertEqual(rig.schedule.turnCount, 0)
            XCTAssertNil(rig.capsule)
        }
    }

    /// From is already the closer station: nothing changes and nothing is said.
    func testFromAlreadyCloserSaysNothing() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.location.send(atOakville)
        await eventually { rig.outcome == .nothing(.alreadyCloser) }

        XCTAssertFalse(rig.look.isLooking)
        XCTAssertFalse(rig.location.isReading)
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 0)
        XCTAssertEqual(rig.schedule.route, route)
        XCTAssertNil(rig.capsule)
        XCTAssertTrue(rig.haptics.played.isEmpty)
    }

    /// A reading that says nothing (in between, too wide a circle, too old) is skipped and the reader waits for the next.
    func testAReadingThatSaysNothingWaitsForTheNext() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.location.send(inBetween)
        rig.location.send(DirectionFixtures.reading(at: DirectionFixtures.unionPlace, radius: 14_000))
        rig.location.send(DirectionFixtures.reading(at: DirectionFixtures.unionPlace, age: 400))
        await pause()
        XCTAssertTrue(rig.look.isLooking)
        XCTAssertTrue(rig.location.isReading)
        XCTAssertNil(rig.look.lastLook)
        XCTAssertEqual(rig.schedule.turnCount, 0)

        rig.location.send(atUnion)
        await eventually { rig.schedule.turnCount == 1 }
        XCTAssertEqual(rig.outcome, .turn)
    }

    /// Back in the app, an answer after the quick time asks: nothing moves, and the capsule offers the switch.
    func testAnAnswerAfterTheQuickTimeAsks() async {
        let rig = Rig(now: evening, quick: .milliseconds(20))
        rig.look.update(front)
        rig.look.wentToBackground()

        // Schedule waits for the look's decision; with no answer it gets a no once the quick time has passed.
        let didTurn = await rig.look.cameBack(front)
        XCTAssertFalse(didTurn)
        XCTAssertTrue(rig.look.isLooking, "the reader goes on until its limit")

        rig.location.send(atUnion)
        await eventually { rig.capsule != nil }
        XCTAssertEqual(rig.capsule, .asks(station: "Union"))
        XCTAssertEqual(rig.outcome, .ask)
        XCTAssertFalse(rig.location.isReading)
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 0)
        XCTAssertEqual(rig.schedule.route, route)
        XCTAssertTrue(rig.haptics.played.isEmpty)
    }

    /// Where no splash plays, a cold start follows the coming-back rule: the quick time counts from the look's start.
    func testAColdStartWithNoSplashFollowsTheQuickRule() async {
        let rig = Rig(now: evening, quick: .zero, playsSplash: false)
        rig.look.update(front)
        await pause()

        rig.location.send(atUnion)
        await eventually { rig.capsule != nil }
        XCTAssertEqual(rig.capsule, .asks(station: "Union"))
        XCTAssertEqual(rig.schedule.turnCount, 0)
    }

    /// A drag or a tap on Schedule means the rider is reading: the answer asks, however soon it comes.
    func testATouchBeforeTheAnswerAsks() async {
        let rig = Rig(now: evening)
        rig.look.touched()
        rig.look.update(front)
        rig.look.touched()
        rig.location.send(atUnion)

        await eventually { rig.capsule != nil }
        XCTAssertEqual(rig.capsule, .asks(station: "Union"))
        XCTAssertEqual(rig.outcome, .ask)
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 0)
    }

    /// A cold start under the splash may turn until the splash lifts, however long that takes, and its capsule waits
    /// for the lift.
    func testAColdStartUnderTheSplashMayTurnUntilItLifts() async {
        let rig = Rig(now: evening, quick: .zero, playsSplash: true)
        rig.look.update(underSplash)
        // Longer than the quick time, which does not count under the splash.
        await pause()

        rig.location.send(atUnion)
        await eventually { rig.schedule.turnCount == 1 }
        XCTAssertEqual(rig.schedule.route, turned)
        XCTAssertEqual(rig.outcome, .turn)

        await pause()
        XCTAssertNil(rig.capsule, "the capsule waits under the splash")

        let lifted = ContinuousClock.now
        rig.look.update(front)
        await eventually { rig.capsule != nil }
        XCTAssertEqual(rig.capsule, .turned(station: "Union"))
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - lifted, rig.capsuleDelay)
    }

    /// Once the splash has lifted the trains can be read: an answer from then on asks.
    func testAnAnswerAfterTheSplashLiftsAsks() async {
        let rig = Rig(now: evening, playsSplash: true)
        rig.look.update(underSplash)
        rig.look.update(front)
        XCTAssertTrue(rig.look.isLooking, "the same look goes on")
        XCTAssertEqual(rig.location.starts, 1)

        rig.location.send(atUnion)
        await eventually { rig.capsule != nil }
        XCTAssertEqual(rig.capsule, .asks(station: "Union"))
        XCTAssertEqual(rig.schedule.turnCount, 0)
    }

    /// After the limit the reader stops and that visit is over, with nothing said.
    func testTheLimitStopsTheReaderWithNothing() async {
        let rig = Rig(now: evening, limit: .milliseconds(50))
        rig.look.update(front)
        rig.location.send(inBetween)
        await eventually { rig.outcome == .nothing(.noReading) }

        XCTAssertFalse(rig.look.isLooking)
        XCTAssertFalse(rig.location.isReading)
        XCTAssertEqual(rig.location.stops, 1)
        XCTAssertGreaterThan(rig.look.lastLook?.waited ?? 0, 0)

        rig.location.send(atUnion)
        rig.look.update(front)
        await pause()
        XCTAssertEqual(rig.location.starts, 1)
        XCTAssertEqual(rig.schedule.turnCount, 0)
        XCTAssertNil(rig.capsule)
    }

    /// An answer that comes while something has opened over Schedule, or while a bell's capsule is up, is dropped:
    /// no turn, no question, and no second look when it is gone.
    func testAnAnswerWhileSomethingIsOverScheduleIsDropped() async {
        for touches in [false, true] {
            for cover in covers {
                let rig = Rig(now: evening)
                rig.look.update(front)
                if touches { rig.look.touched() }
                rig.look.update(cover)
                XCTAssertTrue(rig.look.isLooking, "the look goes on while the scene is active")

                rig.location.send(atUnion)
                await eventually { rig.outcome == .nothing(.covered) }
                XCTAssertFalse(rig.location.isReading, "\(cover)")

                rig.look.update(front)
                await pause()
                XCTAssertEqual(rig.location.starts, 1, "\(cover)")
                XCTAssertEqual(rig.schedule.turnCount, 0, "\(cover)")
                XCTAssertNil(rig.capsule, "\(cover)")
            }
        }
    }

    /// The same when the day or the route changed under the look.
    func testAnAnswerForAnotherDayOrRouteIsDropped() async {
        let otherDay = Rig(now: evening)
        otherDay.look.update(front)
        otherDay.schedule.isToday = false
        otherDay.location.send(atUnion)
        await eventually { otherDay.outcome == .nothing(.covered) }

        let otherRoute = Rig(now: evening)
        otherRoute.look.update(front)
        otherRoute.schedule.route = picked
        otherRoute.location.send(atUnion)
        await eventually { otherRoute.outcome == .nothing(.covered) }

        await pause()
        XCTAssertEqual(otherDay.schedule.turnCount, 0)
        XCTAssertNil(otherDay.capsule)
        XCTAssertEqual(otherRoute.schedule.turnCount, 0)
        XCTAssertEqual(otherRoute.schedule.route, picked)
        XCTAssertNil(otherRoute.capsule)
    }

    /// On the track well before the station the rider may be on the train: the look asks, even with the answer in time.
    func testMaybeOnTheTrainAsks() async {
        let shape = TrackShape(points: [DirectionFixtures.oakvillePlace, DirectionFixtures.unionPlace])
        let rails = DirectionRule.Track(shape: shape, along: ["OA": 0, "UN": shape.length])

        let riding = Rig(now: evening, track: { _, _ in rails })
        riding.look.update(front)
        riding.location.send(DirectionFixtures.reading(at: shape.point(at: shape.length - 5_000)))
        await eventually { riding.capsule != nil }
        XCTAssertEqual(riding.capsule, .asks(station: "Union"))
        XCTAssertEqual(riding.outcome, .ask)
        XCTAssertEqual(riding.schedule.turnCount, 0)

        // At the station the same track lets the route turn.
        let arrived = Rig(now: evening, track: { _, _ in rails })
        arrived.look.update(front)
        arrived.location.send(atUnion)
        await eventually { arrived.schedule.turnCount == 1 }
    }

    // MARK: Coming back

    /// Schedule awaits the look on a return: true when the route turned in time, so the turn is the one arrival.
    func testComingBackReturnsTrueWhenTheRouteTurnsInTime() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.look.wentToBackground()

        let scene = front
        let back = Task { await rig.look.cameBack(scene) }
        await eventually { rig.location.isReading }
        rig.location.send(atUnion)
        let didTurn = await back.value

        XCTAssertTrue(didTurn)
        await eventually { rig.schedule.turnCount == 1 }
        XCTAssertEqual(rig.schedule.route, turned)
    }

    /// False as soon as the look ends with nothing to do.
    func testComingBackReturnsFalseWhenFromIsAlreadyCloser() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.look.wentToBackground()

        let scene = front
        let back = Task { await rig.look.cameBack(scene) }
        await eventually { rig.location.isReading }
        rig.location.send(atOakville)
        let didTurn = await back.value

        XCTAssertFalse(didTurn)
        XCTAssertEqual(rig.outcome, .nothing(.alreadyCloser))
    }

    /// False at once when there is no look to wait for.
    func testComingBackDoesNotWaitWithNoLook() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.look.wentToBackground()
        rig.store.isOff = true

        let didTurn = await rig.look.cameBack(front)
        XCTAssertFalse(didTurn)
        XCTAssertEqual(rig.outcome, .nothing(.off))
        XCTAssertEqual(rig.location.starts, 1)
    }

    /// The cold start does not wait: its look runs under the splash, or beside the first load.
    func testTheColdStartDoesNotWait() async {
        let rig = Rig(now: evening, quick: .seconds(60))
        let began = ContinuousClock.now
        let didTurn = await rig.look.cameBack(front)

        XCTAssertFalse(didTurn)
        XCTAssertTrue(rig.look.isLooking)
        XCTAssertLessThan(ContinuousClock.now - began, .seconds(30))
    }

    /// A touch ends the wait: from there the answer can only ask.
    func testATouchEndsTheWait() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.look.wentToBackground()

        let scene = front
        let back = Task { await rig.look.cameBack(scene) }
        await eventually { rig.location.isReading }
        rig.look.touched()
        let didTurn = await back.value

        XCTAssertFalse(didTurn)
        XCTAssertTrue(rig.look.isLooking)
    }

    // MARK: A ride that ended at your stop

    private func arrival(at stop: String = "UN", minutesAgo: Double = 10) -> RideArrival {
        RideArrival(stopId: stop, at: evening.addingTimeInterval(-minutesAgo * 60))
    }

    /// The ride is the proof: the route turns to leave from the stop with no reading, as an answer in time does.
    func testARideThatEndedAtTheToStationTurnsTheRouteWithNoReading() async {
        let rig = Rig(now: evening)
        rig.ride.arrival = arrival()
        rig.look.update(front)

        XCTAssertEqual(rig.outcome, .turn)
        XCTAssertEqual(rig.look.lastLook?.waited, 0)
        XCTAssertEqual(rig.location.starts, 0, "no reading")
        await eventually { rig.schedule.turnCount == 1 && rig.capsule != nil }
        XCTAssertEqual(rig.schedule.route, turned)
        XCTAssertEqual(rig.capsule, .turned(station: "Union"))
        XCTAssertTrue(rig.haptics.played.isEmpty)
        XCTAssertEqual(rig.location.requests, 0)

        // The proof is used once, and it was this visit's look.
        rig.look.update(front)
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 1)
        XCTAssertEqual(rig.location.starts, 0)

        // The next visit looks as usual.
        rig.look.wentToBackground()
        rig.look.update(front)
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 1)
        XCTAssertEqual(rig.location.starts, 1)
    }

    /// A ride that ran on the timetable alone, a ride restored as long over and a demo ride leave no arrival: the look
    /// runs as usual.
    func testARideWithNoArrivalIsNoProof() async {
        let rig = Rig(now: evening)
        rig.ride.arrival = nil
        rig.look.update(front)

        XCTAssertNil(rig.look.lastLook)
        XCTAssertEqual(rig.location.starts, 1)
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 0)
    }

    /// The ride ends while the app is open: the turn plays once the ride's sheet is gone and Schedule shows.
    func testTheProofWaitsUntilScheduleShows() async {
        for cover in covers {
            let rig = Rig(now: evening)
            rig.ride.holdsRide = true
            rig.look.update(cover)

            rig.ride.holdsRide = false
            rig.ride.arrival = arrival(minutesAgo: 0)
            rig.look.update(cover)
            XCTAssertNil(rig.look.lastLook, "\(cover)")

            rig.look.update(front)
            XCTAssertEqual(rig.outcome, .turn, "\(cover)")
            XCTAssertEqual(rig.location.starts, 0, "\(cover)")
            await eventually { rig.schedule.turnCount == 1 }
        }
    }

    /// Not on another day, and not while another ride is held.
    func testTheProofWaitsForTodayAndForNoRide() async {
        let otherDay = Rig(now: evening)
        otherDay.ride.arrival = arrival()
        otherDay.schedule.isToday = false
        otherDay.look.update(front)
        XCTAssertNil(otherDay.look.lastLook)
        otherDay.schedule.isToday = true
        otherDay.look.update(front)
        XCTAssertEqual(otherDay.outcome, .turn)

        let riding = Rig(now: evening)
        riding.ride.arrival = arrival()
        riding.ride.holdsRide = true
        riding.look.update(front)
        XCTAssertEqual(riding.outcome, .nothing(.riding))
        riding.ride.holdsRide = false
        riding.look.update(front)
        XCTAssertEqual(riding.outcome, .turn)

        await eventually { otherDay.schedule.turnCount == 1 && riding.schedule.turnCount == 1 }
    }

    /// Only when the stop is the route's To station: at the From station, or any other stop, the look decides.
    func testTheProofNeedsTheRoutesToStation() async {
        for stop in ["OA", "CL"] {
            let rig = Rig(now: evening)
            rig.ride.arrival = arrival(at: stop)
            rig.look.update(front)

            XCTAssertNil(rig.look.lastLook, stop)
            XCTAssertEqual(rig.location.starts, 1, "the look runs as usual")
            await pause()
            XCTAssertEqual(rig.schedule.turnCount, 0, stop)
            XCTAssertNil(rig.capsule, stop)
        }
    }

    /// Within an hour of the ride's end; after that the look decides.
    func testTheProofLastsAnHour() async {
        let inTime = Rig(now: evening)
        inTime.ride.arrival = arrival(minutesAgo: 60)
        inTime.look.update(front)
        XCTAssertEqual(inTime.outcome, .turn)
        XCTAssertEqual(inTime.location.starts, 0)
        await eventually { inTime.schedule.turnCount == 1 }

        let late = Rig(now: evening)
        late.ride.arrival = arrival(minutesAgo: 61)
        late.look.update(front)
        XCTAssertNil(late.look.lastLook)
        XCTAssertEqual(late.location.starts, 1, "the look runs as usual")
        await pause()
        XCTAssertEqual(late.schedule.turnCount, 0)
    }

    /// An Undo hour for the pair stops the proof, and the look with it.
    func testTheUndoHourStopsTheProof() async {
        let rig = Rig(now: evening)
        rig.store.startUndoHour(for: route, at: rig.clock.now)
        rig.ride.arrival = arrival()
        rig.look.update(front)

        XCTAssertEqual(rig.outcome, .nothing(.undone))
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 0)
        XCTAssertNil(rig.capsule)
    }

    /// The 10 min hold of a choice by hand does not stop it: the ride is newer than the choice.
    func testAChoiceByHandDoesNotStopTheProof() async {
        let rig = Rig(now: evening)
        rig.look.chose(route, by: .byHand)
        rig.ride.arrival = arrival()
        rig.look.update(front)

        XCTAssertEqual(rig.outcome, .turn)
        await eventually { rig.schedule.turnCount == 1 && rig.capsule == .turned(station: "Union") }
    }

    /// Detect my train's offer goes first: the turn plays when its sheet is closed.
    func testTheOfferGoesBeforeTheProof() async {
        let rig = Rig(now: evening)
        rig.offer.isDue = true
        rig.ride.arrival = arrival()
        rig.look.update(front)
        XCTAssertNil(rig.look.lastLook)
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 0)

        rig.offer.isDue = false
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .turn)
        XCTAssertEqual(rig.location.starts, 0)
        await eventually { rig.schedule.turnCount == 1 }
    }

    /// Only while Automatic direction reads on when Schedule shows: the setting off, Allow Once run out, Precise off.
    func testTheProofNeedsAutomaticDirectionOn() async {
        let off = Rig(now: evening)
        off.store.isOff = true
        let ranOut = Rig(permission: .notAsked, now: evening)
        let refused = Rig(permission: .refused, now: evening)
        let rough = Rig(isPrecise: false, now: evening)

        for rig in [off, ranOut, refused, rough] {
            rig.ride.arrival = arrival()
            rig.look.update(front)
            XCTAssertEqual(rig.outcome, .nothing(.off))
        }
        await pause()
        for rig in [off, ranOut, refused, rough] {
            XCTAssertEqual(rig.schedule.turnCount, 0)
            XCTAssertNil(rig.capsule)
            XCTAssertEqual(rig.location.requests, 0)
        }
    }

    /// A look still running gives way to the proof.
    func testTheProofEndsALookStillRunning() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        XCTAssertTrue(rig.look.isLooking)

        rig.ride.arrival = arrival(minutesAgo: 0)
        rig.look.update(front)
        XCTAssertFalse(rig.look.isLooking)
        XCTAssertFalse(rig.location.isReading)
        XCTAssertEqual(rig.outcome, .turn)
        await eventually { rig.schedule.turnCount == 1 }

        rig.location.send(atOakville)
        await pause()
        XCTAssertEqual(rig.schedule.turnCount, 1)
    }

    /// Back in the app after the ride: the proof's turn is the arrival, with no wait.
    func testComingBackAfterTheRideReturnsTrueAtOnce() async {
        let rig = Rig(now: evening)
        rig.look.update(front)
        rig.look.wentToBackground()
        rig.ride.arrival = arrival()

        let didTurn = await rig.look.cameBack(front)
        XCTAssertTrue(didTurn)
        XCTAssertEqual(rig.location.starts, 1, "only the first visit's look read the location")
        await eventually { rig.schedule.turnCount == 1 }
    }

    // MARK: The rider's choice

    /// A route chosen by hand ends a running look, starts the hold and sets the widgets' morning way.
    func testAChoiceByHandEndsTheLookAndIsKept() async {
        let rig = Rig(now: morning)
        rig.look.update(front)
        rig.schedule.route = picked
        rig.look.chose(picked, by: .byHand)

        XCTAssertFalse(rig.look.isLooking)
        XCTAssertFalse(rig.location.isReading)
        XCTAssertEqual(rig.outcome, .nothing(.chosenByHand))
        XCTAssertTrue(rig.store.holdsChoice(at: rig.clock.now))
        XCTAssertEqual(rig.store.morningWay, WidgetFile.RouteKey(fromId: "CL", toId: "UN"), "chosen before 12 PM")
        XCTAssertFalse(rig.store.holdsUndo(for: picked, at: rig.clock.now))
        XCTAssertNil(rig.capsule)

        rig.location.send(atUnion)
        rig.look.update(front)
        await pause()
        XCTAssertEqual(rig.location.starts, 1)
        XCTAssertEqual(rig.schedule.turnCount, 0)
        XCTAssertEqual(rig.schedule.route, picked)
    }

    /// Chosen after 12 PM, the route is the way home: the morning way is its reverse.
    func testAChoiceByHandInTheEveningSetsTheReverseAsTheMorningWay() {
        let rig = Rig(now: evening)
        rig.schedule.route = turned
        rig.look.chose(turned, by: .byHand)
        XCTAssertEqual(rig.store.morningWay, WidgetFile.RouteKey(fromId: "OA", toId: "UN"))
    }

    /// The swap button back, in a visit where the app turned the route, is the Undo: the hour starts and the capsule
    /// says so. The look turns nothing and plays nothing: the swap is the button's own.
    func testASwapBackByHandAfterATurnIsTheUndo() async {
        let rig = Rig(now: evening)
        await turnAtUnion(rig)

        rig.schedule.route = route
        rig.look.chose(route, by: .byHand)
        XCTAssertEqual(rig.capsule, .kept)
        XCTAssertTrue(rig.store.holdsUndo(for: route, at: rig.clock.now))
        XCTAssertTrue(rig.store.holdsUndo(for: turned, at: rig.clock.now))
        XCTAssertTrue(rig.store.holdsChoice(at: rig.clock.now))
        XCTAssertEqual(rig.schedule.turnCount, 1)
        XCTAssertTrue(rig.haptics.played.isEmpty)
    }

    /// The same once the capsule has gone, and before it has come.
    func testASwapBackIsTheUndoWithoutTheCapsuleToo() async {
        let gone = Rig(now: evening)
        await turnAtUnion(gone)
        gone.look.capsule.dismiss()
        gone.schedule.route = route
        gone.look.chose(route, by: .byHand)
        XCTAssertEqual(gone.capsule, .kept)
        XCTAssertTrue(gone.store.holdsUndo(for: route, at: gone.clock.now))

        let early = Rig(now: evening, capsuleDelay: .milliseconds(100))
        early.look.update(front)
        early.location.send(atUnion)
        await eventually { early.schedule.turnCount == 1 }
        early.schedule.route = route
        early.look.chose(route, by: .byHand)
        XCTAssertEqual(early.capsule, .kept)
        XCTAssertTrue(early.store.holdsUndo(for: route, at: early.clock.now))
        // "Now from Union" does not come after it.
        await pause()
        XCTAssertEqual(early.capsule, .kept)
    }

    /// Another route picked after a turn is a plain choice: the capsule goes and no Undo hour starts.
    func testAnotherRoutePickedAfterATurnIsNotTheUndo() async {
        let rig = Rig(now: evening)
        await turnAtUnion(rig)

        rig.schedule.route = picked
        rig.look.chose(picked, by: .byHand)
        XCTAssertNil(rig.capsule)
        XCTAssertFalse(rig.store.holdsUndo(for: route, at: rig.clock.now))
        XCTAssertFalse(rig.store.holdsUndo(for: picked, at: rig.clock.now))
        XCTAssertTrue(rig.store.holdsChoice(at: rig.clock.now))
    }

    /// A swap in a visit where the app turned nothing is a plain choice, and so is one in a later visit.
    func testASwapWithNoTurnInThisVisitIsNotTheUndo() async {
        let plain = Rig(now: evening)
        plain.look.update(front)
        plain.schedule.route = turned
        plain.look.chose(turned, by: .byHand)
        XCTAssertNil(plain.capsule)
        XCTAssertFalse(plain.store.holdsUndo(for: route, at: plain.clock.now))

        let later = Rig(now: evening)
        await turnAtUnion(later)
        later.look.wentToBackground()
        later.look.update(front)
        later.schedule.route = route
        later.look.chose(route, by: .byHand)
        XCTAssertNil(later.capsule)
        XCTAssertFalse(later.store.holdsUndo(for: route, at: later.clock.now))
    }

    /// One train's link ends this visit's look and is kept as a choice by hand is, but leaves the morning way.
    func testATrainsLinkEndsThisVisitsLookAndHolds() {
        let rig = Rig(now: morning)
        rig.look.update(front)
        rig.look.chose(route, by: .trainLink)

        XCTAssertFalse(rig.look.isLooking)
        XCTAssertFalse(rig.location.isReading)
        XCTAssertEqual(rig.outcome, .nothing(.chosenByLink))
        XCTAssertTrue(rig.store.holdsChoice(at: rig.clock.now))
        XCTAssertNil(rig.store.morningWay)

        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 1)

        rig.look.wentToBackground()
        rig.clock.advance(minutes: 5)
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.chosenByHand))
        XCTAssertEqual(rig.location.starts, 1)
    }

    /// A link that arrives before the look could start still ends this visit's look.
    func testATrainsLinkBeforeTheLookEndsIt() {
        let rig = Rig(now: evening)
        rig.look.chose(route, by: .trainLink)
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 0)
        XCTAssertFalse(rig.look.isLooking)
    }

    /// A train's link takes the direction capsule away.
    func testATrainsLinkEndsTheCapsule() async {
        let rig = Rig(now: evening)
        await turnAtUnion(rig)
        rig.look.chose(turned, by: .trainLink)
        XCTAssertNil(rig.capsule)
        XCTAssertFalse(rig.store.holdsUndo(for: route, at: rig.clock.now))
    }

    /// A widget's route link is neither a hold nor the morning way: a look that ran for the old route starts again
    /// for the new one, and may turn it.
    func testAWidgetsRouteRestartsARunningLook() async {
        let rig = Rig(now: evening)
        rig.look.update(front)

        rig.schedule.route = turned
        rig.look.chose(turned, by: .widgetRoute)
        XCTAssertEqual(rig.location.starts, 2)
        XCTAssertEqual(rig.location.stops, 1)
        XCTAssertTrue(rig.look.isLooking)
        XCTAssertFalse(rig.store.holdsChoice(at: rig.clock.now))
        XCTAssertNil(rig.store.morningWay)

        // The widget's route is Union to Oakville: at Oakville the look turns it.
        rig.location.send(atOakville)
        await eventually { rig.schedule.turnCount == 1 && rig.capsule != nil }
        XCTAssertEqual(rig.schedule.route, route)
        XCTAssertEqual(rig.capsule, .turned(station: "Oakville"))
        XCTAssertEqual(rig.outcome, .turn)
    }

    /// Applied before the look starts, a widget's route changes nothing for it.
    func testAWidgetsRouteBeforeTheLookLeavesItToLook() {
        let rig = Rig(now: evening)
        rig.schedule.route = turned
        rig.look.chose(turned, by: .widgetRoute)
        XCTAssertEqual(rig.location.starts, 0)
        XCTAssertNil(rig.look.lastLook)

        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 1)
        XCTAssertTrue(rig.look.isLooking)
    }

    // MARK: Undo and Switch

    /// Undo turns the route back, plays the undo feel at once, and the route is left alone for an hour.
    func testUndoTurnsBackAndHoldsForAnHour() async {
        let rig = Rig(now: evening)
        await turnAtUnion(rig)

        await rig.look.undo()
        XCTAssertEqual(rig.schedule.turnCount, 2)
        XCTAssertEqual(rig.schedule.route, route)
        XCTAssertEqual(rig.capsule, .kept)
        XCTAssertEqual(rig.haptics.played, [.tap])
        XCTAssertTrue(rig.store.holdsUndo(for: route, at: rig.clock.now))
        XCTAssertTrue(rig.store.holdsUndo(for: turned, at: rig.clock.now))
        XCTAssertNil(rig.store.morningWay)

        // A visit inside the hour leaves the route alone and says nothing.
        rig.look.wentToBackground()
        rig.clock.advance(minutes: 30)
        rig.look.update(front)
        XCTAssertEqual(rig.outcome, .nothing(.undone))
        XCTAssertEqual(rig.location.starts, 1)
        XCTAssertNil(rig.capsule)

        // After the hour the app looks again.
        rig.look.wentToBackground()
        rig.clock.advance(minutes: 31)
        rig.look.update(front)
        XCTAssertEqual(rig.location.starts, 2)
    }

    /// A swap back after Undo is a plain choice: the app's turn was already undone.
    func testASwapAfterUndoIsAPlainChoice() async {
        let rig = Rig(now: evening)
        await turnAtUnion(rig)
        await rig.look.undo()
        rig.look.capsule.dismiss()

        rig.schedule.route = turned
        rig.look.chose(turned, by: .byHand)
        XCTAssertNil(rig.capsule)
    }

    /// Undo is the Turned capsule's only: with no capsule, or the question, it does nothing.
    func testUndoNeedsTheTurnedCapsule() async {
        let rig = Rig(now: evening)
        await rig.look.undo()
        XCTAssertEqual(rig.schedule.turnCount, 0)
        XCTAssertTrue(rig.haptics.played.isEmpty)

        await askAtUnion(rig)
        await rig.look.undo()
        XCTAssertEqual(rig.schedule.turnCount, 0)
        XCTAssertEqual(rig.capsule, .asks(station: "Union"))
        XCTAssertTrue(rig.haptics.played.isEmpty)
        XCTAssertFalse(rig.store.holdsUndo(for: route, at: rig.clock.now))
    }

    /// Switch turns the route with no capsule after it, and plays the swap feel 310 ms after the tap.
    func testSwitchTurnsTheRouteWithNoCapsuleAfter() async {
        let rig = Rig(now: evening)
        await askAtUnion(rig)
        XCTAssertEqual(rig.schedule.turnCount, 0)

        await rig.look.switchRoute()
        XCTAssertEqual(rig.schedule.turnCount, 1)
        XCTAssertEqual(rig.schedule.route, turned)
        XCTAssertNil(rig.capsule)
        XCTAssertTrue(rig.haptics.played.isEmpty, "the swap feel comes 310 ms after the tap")
        XCTAssertFalse(rig.store.holdsUndo(for: route, at: rig.clock.now))
        XCTAssertNil(rig.store.morningWay)

        await eventually { rig.haptics.played == [.tap] }
        XCTAssertNil(rig.capsule)
    }

    /// Switch is the question's only: with no capsule, or "Now from Union", it does nothing.
    func testSwitchNeedsTheAskingCapsule() async {
        let rig = Rig(now: evening)
        await rig.look.switchRoute()
        XCTAssertEqual(rig.schedule.turnCount, 0)

        await turnAtUnion(rig)
        await rig.look.switchRoute()
        XCTAssertEqual(rig.schedule.turnCount, 1)
        XCTAssertEqual(rig.capsule, .turned(station: "Union"))
        XCTAssertTrue(rig.haptics.played.isEmpty)
    }

    /// The question left alone changes nothing.
    func testTheQuestionLeftAloneChangesNothing() async {
        let rig = Rig(now: evening)
        await askAtUnion(rig)
        rig.look.capsule.dismiss()
        rig.look.wentToBackground()

        XCTAssertEqual(rig.schedule.turnCount, 0)
        XCTAssertEqual(rig.schedule.route, route)
        XCTAssertFalse(rig.store.holdsUndo(for: route, at: rig.clock.now))
        XCTAssertFalse(rig.store.holdsChoice(at: rig.clock.now))
        XCTAssertTrue(rig.haptics.played.isEmpty)
    }

    // MARK: The capsule's stage

    /// When a bell's capsule takes the stage, the direction capsule is over and does not come back.
    func testABellsCapsuleEndsTheDirectionCapsule() async {
        let rig = Rig(now: evening)
        await turnAtUnion(rig)

        var bell = front
        bell.hasBellCapsule = true
        rig.look.update(bell)
        XCTAssertNil(rig.capsule)

        rig.look.update(front)
        await pause()
        XCTAssertNil(rig.capsule)
        XCTAssertEqual(rig.schedule.turnCount, 1, "the turn stays")
    }

    /// A bell's capsule that comes before "Now from Union" keeps it away.
    func testABellsCapsuleBeforeTheTurnedCapsuleKeepsItAway() async {
        let rig = Rig(now: evening, capsuleDelay: .milliseconds(100))
        rig.look.update(front)
        rig.location.send(atUnion)
        await eventually { rig.schedule.turnCount == 1 }

        var bell = front
        bell.hasBellCapsule = true
        rig.look.update(bell)
        await pause()
        XCTAssertNil(rig.capsule)
        rig.look.update(front)
        await pause()
        XCTAssertNil(rig.capsule)
    }

    /// The background ends the capsule, shown or still waiting for the splash to lift.
    func testTheBackgroundEndsTheCapsule() async {
        let shown = Rig(now: evening)
        await turnAtUnion(shown)
        shown.look.wentToBackground()
        XCTAssertNil(shown.capsule)

        let waiting = Rig(now: evening, playsSplash: true)
        waiting.look.update(underSplash)
        waiting.location.send(atUnion)
        await eventually { waiting.schedule.turnCount == 1 }
        waiting.look.wentToBackground()
        waiting.look.update(front)
        await pause()
        XCTAssertNil(waiting.capsule)
    }

    // MARK: Last look

    /// Settings › Testing shows the last look: what it did and how long it waited, and nothing of where.
    func testTheLastLookRecordsWhatItDid() async {
        let rig = Rig(now: evening)
        XCTAssertNil(rig.look.lastLook)

        rig.look.update(front)
        XCTAssertNil(rig.look.lastLook, "still looking")
        rig.location.send(atOakville)
        await eventually { rig.look.lastLook != nil }
        XCTAssertEqual(rig.outcome, .nothing(.alreadyCloser))
        XCTAssertGreaterThanOrEqual(rig.look.lastLook?.waited ?? -1, 0)

        // A visit whose look cannot start is noted with no wait.
        rig.look.wentToBackground()
        XCTAssertEqual(rig.outcome, .nothing(.alreadyCloser), "no look was running")
        rig.store.isOff = true
        rig.look.update(front)
        XCTAssertEqual(rig.look.lastLook, DirectionLook.LastLook(waited: 0, outcome: .nothing(.off)))
    }

    // MARK: No events

    /// A turn and its Undo, the question shown, left and answered, and the turn after a ride send no event: each would
    /// say the rider is at their station now.
    func testTheLookSendsNoEvent() async {
        let recorder = RecordingAnalytics.install()

        let undone = Rig(now: evening)
        await turnAtUnion(undone)
        await undone.look.undo()

        let switched = Rig(now: evening)
        await askAtUnion(switched)
        await switched.look.switchRoute()

        let left = Rig(now: evening)
        await askAtUnion(left)
        left.look.wentToBackground()

        let afterARide = Rig(now: evening)
        afterARide.ride.arrival = arrival()
        afterARide.look.update(front)
        await eventually { afterARide.schedule.turnCount == 1 && afterARide.capsule != nil }

        let nothing = Rig(now: evening)
        nothing.look.update(front)
        nothing.location.send(atOakville)
        await eventually { nothing.outcome == .nothing(.alreadyCloser) }

        XCTAssertEqual(undone.schedule.turnCount, 2)
        XCTAssertEqual(switched.schedule.turnCount, 1)
        XCTAssertTrue(recorder.events.isEmpty, "\(recorder.names)")
        XCTAssertTrue(recorder.screens.isEmpty)
    }
}

/// A look with everything under it faked: Schedule's route, the reader, the store in memory, the clock, the ride and
/// Detect my train's offer. The capsule stays up until a test ends it, and the quick time and the limit are long unless
/// a test shortens them.
@MainActor
private final class Rig {
    /// Detect my train's offer, as a test sets it.
    @MainActor
    final class Offer {
        var isDue = false
    }

    let schedule: FakeRouteTurning
    let location: FakeDirectionLocation
    let store: DirectionStore
    let clock: TestClock
    let ride: FakeRideSource
    let haptics: FakeHaptics
    let offer: Offer
    let capsuleDelay: Duration
    let look: DirectionLook

    init(
        route: Route? = DirectionFixtures.route, permission: DirectionPermission = .allowed, isPrecise: Bool = true,
        stations: any StationRepository = DirectionFixtures.stations, now: Date,
        track: @escaping @Sendable (Route, ServiceDay) async -> DirectionRule.Track? = { _, _ in nil },
        quick: Duration = .seconds(300), limit: Duration = .seconds(300), capsuleDelay: Duration = .milliseconds(20),
        playsSplash: Bool = false
    ) {
        let schedule = FakeRouteTurning(route: route)
        let location = FakeDirectionLocation(permission: permission, isPrecise: isPrecise)
        let store = DirectionStore(defaults: nil)
        let clock = TestClock(now: now)
        let ride = FakeRideSource()
        let haptics = FakeHaptics()
        let offer = Offer()
        self.schedule = schedule
        self.location = location
        self.store = store
        self.clock = clock
        self.ride = ride
        self.haptics = haptics
        self.offer = offer
        self.capsuleDelay = capsuleDelay
        look = DirectionLook(
            schedule: schedule, location: location, stations: stations, store: store, clock: clock, ride: ride,
            offerDue: { offer.isDue }, track: track,
            capsule: DirectionCapsuleModel(actionDuration: .seconds(300), plainDuration: .seconds(300)), haptics: haptics,
            quick: quick, limit: limit, capsuleDelay: capsuleDelay, playsSplash: playsSplash
        )
    }

    /// The capsule on Schedule.
    var capsule: DirectionCapsule.Kind? { look.capsule.shown?.kind }
    /// What the last look did.
    var outcome: DirectionRule.Outcome? { look.lastLook?.outcome }
}

/// A station list that cannot be read: the first timetable is still downloading.
private struct FailingStations: StationRepository {
    func stations() async throws -> [Station] { throw URLError(.notConnectedToInternet) }
    func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: nil) }
}

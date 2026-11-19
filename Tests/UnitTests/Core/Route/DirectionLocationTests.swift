import XCTest
@testable import TrainTimes

/// Automatic direction's readers (TT-234, D116): the one that is no reader, for fixture runs and the unit test host, and
/// Demo place over a reader, which stands the phone at one of the route's two stations.
@MainActor
final class DirectionLocationTests: XCTestCase {
    private let route = DirectionFixtures.route

    /// What a reader handed over.
    @MainActor
    private final class Readings {
        var list: [DirectionReading] = []
    }

    /// Settings › Testing › Demo place, as a test sets it.
    @MainActor
    private final class Stored {
        var id: String?

        init(_ id: String?) {
            self.id = id
        }
    }

    private func demo(
        over base: any DirectionLocating, stored: Stored, route: Route? = DirectionFixtures.route,
        stations: any StationRepository = DirectionFixtures.stations
    ) -> DemoPlaceLocation {
        DemoPlaceLocation(base: base, stations: stations, route: { route }, stored: { stored.id })
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out", file: file, line: line)
    }

    /// Long enough for a reading that was on its way to arrive.
    private func pause() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    // MARK: No reader

    /// Fixture runs and the unit test host: unavailable, never allowed by a prompt, and it never reads.
    func testNoReaderIsUnavailableAndNeverReads() async {
        let location = NoDirectionLocation()
        XCTAssertEqual(location.permission, .unavailable)
        XCTAssertFalse(location.isPrecise)
        let allowed = await location.requestWhenInUse()
        XCTAssertFalse(allowed)
        XCTAssertEqual(location.permission, .unavailable)
        XCTAssertFalse(location.readsOn(DirectionStore(defaults: nil)))

        let readings = Readings()
        location.start { readings.list.append($0) }
        await pause()
        location.stop()
        XCTAssertTrue(readings.list.isEmpty)
    }

    // MARK: Reads on

    /// Automatic direction reads on with location allowed and Precise Location, unless the rider turned it off.
    func testReadsOnNeedsLocationPreciseLocationAndNoOff() {
        let store = DirectionStore(defaults: nil)
        XCTAssertTrue(FakeDirectionLocation().readsOn(store))
        XCTAssertFalse(FakeDirectionLocation(permission: .notAsked).readsOn(store))
        XCTAssertFalse(FakeDirectionLocation(permission: .refused).readsOn(store))
        XCTAssertFalse(FakeDirectionLocation(permission: .unavailable).readsOn(store))
        XCTAssertFalse(FakeDirectionLocation(isPrecise: false).readsOn(store))

        store.isOff = true
        XCTAssertFalse(FakeDirectionLocation().readsOn(store))
        store.isOff = false
        XCTAssertTrue(FakeDirectionLocation().readsOn(store))
    }

    // MARK: Demo place

    /// The stored id counts only when it is one of the route's two stations; any other reads Off.
    func testDemoPlaceIsOneOfTheRoutesTwoStations() {
        XCTAssertEqual(DemoPlace.station(on: route, stored: "OA"), "OA")
        XCTAssertEqual(DemoPlace.station(on: route, stored: "UN"), "UN")
        XCTAssertNil(DemoPlace.station(on: route, stored: "CL"))
        XCTAssertNil(DemoPlace.station(on: route, stored: nil))
        XCTAssertNil(DemoPlace.station(on: nil, stored: "UN"))
        XCTAssertEqual(DemoPlace.key, "settings.demoPlace")
    }

    /// With a demo place on, location counts as allowed with Precise Location whatever the reader under it says, and the
    /// iOS prompt is not shown.
    func testADemoPlaceCountsAsAllowedAndPrecise() async {
        let base = FakeDirectionLocation(permission: .refused, isPrecise: false)
        let location = demo(over: base, stored: Stored("UN"))

        XCTAssertEqual(location.permission, .allowed)
        XCTAssertTrue(location.isPrecise)
        XCTAssertTrue(location.readsOn(DirectionStore(defaults: nil)))
        let allowed = await location.requestWhenInUse()
        XCTAssertTrue(allowed)
        XCTAssertEqual(base.requests, 0)
        XCTAssertEqual(base.permission, .refused)
    }

    /// It gives one reading at that station's place, with no radius and no age, and the reader under it is not started.
    func testADemoPlaceGivesOneReadingAtThatStation() async {
        let base = FakeDirectionLocation()
        let stored = Stored("UN")
        let location = demo(over: base, stored: stored)
        let readings = Readings()

        location.start { readings.list.append($0) }
        await eventually { !readings.list.isEmpty }
        await pause()
        XCTAssertEqual(readings.list, [DirectionReading(place: DirectionFixtures.unionPlace, radius: 0, age: 0)])
        XCTAssertEqual(base.starts, 0)
        location.stop()

        // The other station of the route.
        stored.id = "OA"
        readings.list = []
        location.start { readings.list.append($0) }
        await eventually { !readings.list.isEmpty }
        XCTAssertEqual(readings.list, [DirectionReading(place: DirectionFixtures.oakvillePlace, radius: 0, age: 0)])
        XCTAssertEqual(base.starts, 0)
    }

    /// A stop before the reading arrives drops it.
    func testStoppingADemoPlaceDropsItsReading() async {
        let base = FakeDirectionLocation()
        let location = demo(over: base, stored: Stored("UN"))
        let readings = Readings()

        location.start { readings.list.append($0) }
        location.stop()
        await pause()
        XCTAssertTrue(readings.list.isEmpty)
        XCTAssertEqual(base.stops, 1, "the reader under it is stopped too")
    }

    /// A station the list gives no place for has no reading.
    func testADemoPlaceWithoutAPlaceGivesNoReading() async {
        let unplaced = PlacedDirectionStations(
            list: [Station(id: "OA", name: "Oakville GO"), Station(id: "UN", name: "Union Station")]
        )
        let base = FakeDirectionLocation()
        let location = demo(over: base, stored: Stored("UN"), stations: unplaced)
        let readings = Readings()

        location.start { readings.list.append($0) }
        await pause()
        XCTAssertTrue(readings.list.isEmpty)
        XCTAssertEqual(base.starts, 0)
    }

    /// A stored id that is neither of the route's stations reads Off: the reader under it answers, is asked and is the
    /// one started.
    func testAnIdOffTheRouteIsTheReaderUnderIt() async {
        let base = FakeDirectionLocation(permission: .notAsked, isPrecise: false)
        let location = demo(over: base, stored: Stored("CL"))
        await behavesAsTheReaderUnderIt(location, base: base)
    }

    func testNoDemoPlaceIsTheReaderUnderIt() async {
        let base = FakeDirectionLocation(permission: .notAsked, isPrecise: false)
        let location = demo(over: base, stored: Stored(nil))
        await behavesAsTheReaderUnderIt(location, base: base)
    }

    /// With no route there is no demo place either.
    func testADemoPlaceWithNoRouteIsTheReaderUnderIt() async {
        let base = FakeDirectionLocation(permission: .notAsked, isPrecise: false)
        let location = demo(over: base, stored: Stored("UN"), route: nil)
        await behavesAsTheReaderUnderIt(location, base: base)
    }

    private func behavesAsTheReaderUnderIt(
        _ location: DemoPlaceLocation, base: FakeDirectionLocation, file: StaticString = #filePath, line: UInt = #line
    ) async {
        XCTAssertEqual(location.permission, .notAsked, file: file, line: line)
        XCTAssertFalse(location.isPrecise, file: file, line: line)
        XCTAssertFalse(location.readsOn(DirectionStore(defaults: nil)), file: file, line: line)
        base.permission = .refused
        XCTAssertEqual(location.permission, .refused, file: file, line: line)

        // The prompt is the reader's own.
        base.permission = .notAsked
        base.answer = .allowed
        let allowed = await location.requestWhenInUse()
        XCTAssertTrue(allowed, file: file, line: line)
        XCTAssertEqual(base.requests, 1, file: file, line: line)
        XCTAssertEqual(location.permission, .allowed, file: file, line: line)
        base.isPrecise = true
        XCTAssertTrue(location.isPrecise, file: file, line: line)

        // And so are the readings.
        let readings = Readings()
        location.start { readings.list.append($0) }
        XCTAssertEqual(base.starts, 1, file: file, line: line)
        XCTAssertTrue(base.isReading, file: file, line: line)
        await pause()
        XCTAssertTrue(readings.list.isEmpty, "no demo reading", file: file, line: line)

        let reading = DirectionFixtures.reading(at: DirectionFixtures.oakvillePlace, radius: 65, age: 12)
        base.send(reading)
        XCTAssertEqual(readings.list, [reading], file: file, line: line)

        location.stop()
        XCTAssertEqual(base.stops, 1, file: file, line: line)
        XCTAssertFalse(base.isReading, file: file, line: line)
    }

    /// The reader's prompt can say no, and Demo place does not change the answer.
    func testTheReaderUnderItCanRefuse() async {
        let base = FakeDirectionLocation(permission: .notAsked)
        base.answer = .refused
        let location = demo(over: base, stored: Stored(nil))

        let allowed = await location.requestWhenInUse()
        XCTAssertFalse(allowed)
        XCTAssertEqual(base.requests, 1)
        XCTAssertEqual(location.permission, .refused)
    }

    /// Demo place is read each time: turned on or off on the Testing page, it takes over or gives way at once.
    func testDemoPlaceIsReadEachTime() {
        let base = FakeDirectionLocation(permission: .refused)
        let stored = Stored(nil)
        let location = demo(over: base, stored: stored)
        XCTAssertEqual(location.permission, .refused)

        stored.id = "OA"
        XCTAssertEqual(location.permission, .allowed)
        stored.id = "CL"
        XCTAssertEqual(location.permission, .refused)
        stored.id = nil
        XCTAssertEqual(location.permission, .refused)
    }

    // MARK: Demo place and the look

    private func makeLook(_ schedule: FakeRouteTurning, place: String) -> DirectionLook {
        // No reader under it, as in a fixture run.
        let location = DemoPlaceLocation(
            base: NoDirectionLocation(), stations: DirectionFixtures.stations, route: { [weak schedule] in schedule?.route },
            stored: { place }
        )
        return DirectionLook(
            schedule: schedule, location: location, stations: DirectionFixtures.stations,
            store: DirectionStore(defaults: nil),
            clock: TestClock(now: ServiceDay(year: 2026, month: 11, day: 19).date(hour: 17, minute: 30)),
            capsule: DirectionCapsuleModel(actionDuration: .seconds(300), plainDuration: .seconds(300)),
            haptics: FakeHaptics(), quick: .seconds(300), limit: .seconds(300), capsuleDelay: .milliseconds(20),
            playsSplash: false
        )
    }

    /// At a desk: Demo place at the To station turns the route when Schedule shows, with no location reader at all.
    func testADemoPlaceAtTheToStationTurnsTheRoute() async {
        let schedule = FakeRouteTurning(route: route)
        let look = makeLook(schedule, place: "UN")
        XCTAssertTrue(look.isOn)

        look.update(DirectionLook.Scene(isActive: true, isInFront: true))
        await eventually { schedule.turnCount == 1 }
        XCTAssertEqual(schedule.route?.from.id, "UN")
        XCTAssertEqual(look.lastLook?.outcome, .turn)
        await eventually { look.capsule.shown?.kind == .turned(station: "Union") }
    }

    /// Demo place at the From station leaves the route alone and says nothing.
    func testADemoPlaceAtTheFromStationLeavesTheRoute() async {
        let schedule = FakeRouteTurning(route: route)
        let look = makeLook(schedule, place: "OA")

        look.update(DirectionLook.Scene(isActive: true, isInFront: true))
        await eventually { look.lastLook?.outcome == .nothing(.alreadyCloser) }
        XCTAssertEqual(schedule.turnCount, 0)
        XCTAssertNil(look.capsule.shown)
    }
}

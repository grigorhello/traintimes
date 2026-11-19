import XCTest
@testable import TrainTimes

/// The widget file (TT-182, D107): what the app writes for the widgets, and when the widgets reload. Wed Nov 11, 8:00 AM.
final class WidgetFileWriterTests: XCTestCase {
    private let wed = ServiceDay(year: 2026, month: 11, day: 11)
    private let oakville = Station(id: "OA", name: "Oakville")
    private let union = Station(id: "UN", name: "Union")
    private let burlington = Station(id: "BU", name: "Burlington")
    private let line = Line(id: "LW", name: "Lakeshore West", colorHex: "#8B1A31")
    private let toUnion = WidgetFile.RouteKey(fromId: "OA", toId: "UN")
    private let toOakville = WidgetFile.RouteKey(fromId: "UN", toId: "OA")
    private let fileURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        .appending(path: WidgetFile.fileName)

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    @MainActor
    private final class Reloads {
        var count = 0
    }

    @MainActor
    private struct Rig {
        let writer: WidgetFileWriter
        let reloads: Reloads
        let routeStore: UserDefaultsRouteStore
        let rules: AlertRules
        let settings: AppSettings
        let recents: RecentRoutes
    }

    @MainActor
    private func rig(
        lastDay: ServiceDay? = nil, widgetRoutes: [Route] = [], at time: (Int, Int) = (8, 0), direction: DirectionStore? = nil
    ) -> Rig {
        let routeStore = UserDefaultsRouteStore(defaults: .ephemeral())
        let rules = AlertFixtures.rules(FakeAlertServer())
        let settings = AppSettings(defaults: .ephemeral())
        let recents = RecentRoutes(defaults: .ephemeral())
        let timetable = FakeTimetable(lastDay: lastDay, stationList: [burlington, oakville, union])
        let reloads = Reloads()
        let writer = WidgetFileWriter(
            repository: timetable, stations: timetable, clock: FixedClock(now: wed.date(hour: time.0, minute: time.1)),
            fileURL: fileURL, widgetRoutes: FakeWidgetRoutes(list: widgetRoutes), routeStore: routeStore, rules: rules,
            settings: settings, recents: recents, direction: direction, reload: { reloads.count += 1 }
        )
        return Rig(writer: writer, reloads: reloads, routeStore: routeStore, rules: rules, settings: settings, recents: recents)
    }

    private var written: WidgetFile? { WidgetFile.read(from: fileURL) }

    @MainActor
    func testAfterLaunchTheFileHoldsTheOpenAndWidgetRoutesBothWaysFor14Days() async throws {
        let open = Route(from: oakville, to: union, line: line)
        // The open route turned around is the same pair of stations, so it is kept once.
        let rig = rig(widgetRoutes: [Route(from: union, to: oakville, line: line), Route(from: burlington, to: union, line: line)])
        rig.routeStore.save(open)
        rig.recents.record(open)
        rig.settings.timeFormat = .twentyFourHour

        let wrote = await rig.writer.write()
        XCTAssertTrue(wrote)
        XCTAssertEqual(rig.reloads.count, 1)
        let file = try XCTUnwrap(written)
        XCTAssertEqual(file.version, WidgetFile.currentVersion)
        XCTAssertEqual(file.firstDay, wed)
        XCTAssertEqual(file.lastDay, wed.adding(days: 13))
        XCTAssertEqual(file.openRoute, WidgetFile.RouteKey(fromId: "OA", toId: "UN"))
        XCTAssertEqual(file.routes.map(\.key), [WidgetFile.RouteKey(fromId: "OA", toId: "UN"), WidgetFile.RouteKey(fromId: "BU", toId: "UN")])
        let oakvilleUnion = file.routes[0]
        XCTAssertEqual(oakvilleUnion.line?.name, "Lakeshore West")
        XCTAssertEqual(Set(oakvilleUnion.outbound.map(\.serviceDay)).count, 14)
        XCTAssertEqual(oakvilleUnion.outbound.count, 28)
        XCTAssertEqual(oakvilleUnion.outbound.first?.tripId, "OA-UN-20261111-0700")
        XCTAssertEqual(oakvilleUnion.inbound.first?.tripId, "UN-OA-20261111-0700")
        XCTAssertEqual(oakvilleUnion.outbound.first?.departure, wed.date(hour: 7, minute: 0))
        XCTAssertEqual(oakvilleUnion.outbound.first?.arrival, wed.date(hour: 7, minute: 40))
        XCTAssertEqual(oakvilleUnion.outbound.first?.isExpress, true)
        XCTAssertEqual(oakvilleUnion.outbound[1].isExpress, false)
        XCTAssertEqual(file.timeFormat, .twentyFourHour)
        XCTAssertEqual(file.stations.map(\.id), ["BU", "OA", "UN"])
        XCTAssertEqual(file.yourStationIds, ["OA", "UN"])
    }

    /// Written after 12 PM, the open route is stored the other way round: its morning way.
    @MainActor
    func testTheOpenRouteIsStoredInItsMorningWay() async throws {
        let rig = rig(at: (17, 0))
        rig.routeStore.save(Route(from: union, to: oakville, line: line))
        await rig.writer.write()
        XCTAssertEqual(try XCTUnwrap(written).openRoute, WidgetFile.RouteKey(fromId: "OA", toId: "UN"))
    }

    // MARK: - The stored morning way (TT-234, D116)

    /// A turn before 12 PM leaves the file's open route: the route on Schedule is saved the other way round, the stored
    /// morning way is not touched.
    @MainActor
    func testATurnBeforeNoonLeavesTheMorningWay() async throws {
        let store = DirectionStore(defaults: nil)
        let rig = rig(direction: store)
        // The rider chose Oakville to Union by hand at 8:00 AM.
        let chosen = Route(from: oakville, to: union, line: line)
        rig.routeStore.save(chosen)
        store.setMorningWay(from: chosen, at: wed.date(hour: 8, minute: 0))
        await rig.writer.write()
        XCTAssertEqual(try XCTUnwrap(written).openRoute, toUnion)

        // The app turns the route at Union. By the clock alone the file would now say Union to Oakville.
        rig.routeStore.save(Route(from: union, to: oakville, line: line))
        await rig.writer.write()
        let file = try XCTUnwrap(written)
        XCTAssertEqual(file.routes.map(\.key), [toOakville])
        XCTAssertEqual(file.openRoute, toUnion)
        XCTAssertEqual(store.morningWay, toUnion)
    }

    /// A turn after 12 PM leaves it too: at 5:00 PM the route turns to leave from Union, and turns back at Oakville.
    @MainActor
    func testATurnAfterNoonLeavesTheMorningWay() async throws {
        let store = DirectionStore(defaults: nil)
        let rig = rig(at: (17, 0), direction: store)
        let chosen = Route(from: oakville, to: union, line: line)
        store.setMorningWay(from: chosen, at: wed.date(hour: 8, minute: 0))

        rig.routeStore.save(Route(from: union, to: oakville, line: line))
        await rig.writer.write()
        XCTAssertEqual(try XCTUnwrap(written).openRoute, toUnion)

        // By the clock alone the file would now say Union to Oakville.
        rig.routeStore.save(chosen)
        await rig.writer.write()
        let file = try XCTUnwrap(written)
        XCTAssertEqual(file.routes.map(\.key), [toUnion])
        XCTAssertEqual(file.openRoute, toUnion)
        XCTAssertEqual(store.morningWay, toUnion)
    }

    /// An install from before the store has no morning way: the first write takes it from the open route by the clock and
    /// stores it, and a turn after that leaves it.
    @MainActor
    func testWithNothingStoredTheMorningWayIsTakenOnceFromTheOpenRoute() async throws {
        let store = DirectionStore(defaults: nil)
        let rig = rig(at: (17, 0), direction: store)
        rig.routeStore.save(Route(from: union, to: oakville, line: line))
        XCTAssertNil(store.morningWay)
        await rig.writer.write()
        XCTAssertEqual(try XCTUnwrap(written).openRoute, toUnion)
        XCTAssertEqual(store.morningWay, toUnion)

        rig.routeStore.save(Route(from: oakville, to: union, line: line))
        await rig.writer.write()
        let file = try XCTUnwrap(written)
        XCTAssertEqual(file.routes.map(\.key), [toUnion])
        XCTAssertEqual(file.openRoute, toUnion)
        XCTAssertEqual(store.morningWay, toUnion)
    }

    /// It is stored before the schedule is read, so a write that fails still takes it, and a turn before the next write
    /// leaves it.
    @MainActor
    func testTheMorningWayIsTakenAlsoWhenTheScheduleCannotBeRead() async throws {
        let store = DirectionStore(defaults: nil)
        let rig = rig(at: (17, 0), direction: store)
        rig.routeStore.save(Route(from: union, to: oakville, line: line))
        let failing = WidgetFileWriter(
            repository: FailingTimetable(), stations: FailingTimetable(), clock: FixedClock(now: wed.date(hour: 17, minute: 0)),
            fileURL: fileURL, routeStore: rig.routeStore, rules: rig.rules, settings: rig.settings, recents: rig.recents,
            direction: store, reload: {}
        )
        let wrote = await failing.write()
        XCTAssertFalse(wrote)
        XCTAssertEqual(store.morningWay, toUnion)

        rig.routeStore.save(Route(from: oakville, to: union, line: line))
        await rig.writer.write()
        XCTAssertEqual(try XCTUnwrap(written).openRoute, toUnion)
    }

    /// A route chosen by hand moves it: the swap button at 8:00 AM stores the new direction as the morning way.
    @MainActor
    func testAChoiceByHandMovesTheMorningWay() async throws {
        let store = DirectionStore(defaults: nil)
        let rig = rig(direction: store)
        let chosen = Route(from: oakville, to: union, line: line)
        rig.routeStore.save(chosen)
        store.setMorningWay(from: chosen, at: wed.date(hour: 7, minute: 30))
        await rig.writer.write()
        XCTAssertEqual(try XCTUnwrap(written).openRoute, toUnion)

        let swapped = Route(from: union, to: oakville, line: line)
        rig.routeStore.save(swapped)
        store.setMorningWay(from: swapped, at: wed.date(hour: 8, minute: 0))
        await rig.writer.write()
        XCTAssertEqual(try XCTUnwrap(written).openRoute, toOakville)
    }

    /// A link that puts another route on Schedule sets no morning way. The stored one names other stations, so the file
    /// takes it from the open route, once.
    @MainActor
    func testAMorningWayStoredForOtherStationsIsReplaced() async throws {
        let store = DirectionStore(defaults: nil)
        let rig = rig(direction: store)
        store.setMorningWay(from: Route(from: burlington, to: union, line: line), at: wed.date(hour: 7, minute: 30))
        rig.routeStore.save(Route(from: oakville, to: union, line: line))
        await rig.writer.write()
        XCTAssertEqual(try XCTUnwrap(written).openRoute, toUnion)
        XCTAssertEqual(store.morningWay, toUnion)

        // A turn then leaves the new one.
        rig.routeStore.save(Route(from: union, to: oakville, line: line))
        await rig.writer.write()
        XCTAssertEqual(try XCTUnwrap(written).openRoute, toUnion)
        XCTAssertEqual(store.morningWay, toUnion)
    }

    /// Before the first route the file has no open route and nothing is stored.
    @MainActor
    func testWithNoRouteNoMorningWayIsStored() async throws {
        let store = DirectionStore(defaults: nil)
        let rig = rig(direction: store)
        await rig.writer.write()
        XCTAssertNil(try XCTUnwrap(written).openRoute)
        XCTAssertNil(store.morningWay)
    }

    // MARK: - The rest of the file

    @MainActor
    func testTheFeedsEndStopsTheFile() async throws {
        let rig = rig(lastDay: wed.adding(days: 4))
        rig.routeStore.save(Route(from: oakville, to: union, line: line))
        await rig.writer.write()
        let file = try XCTUnwrap(written)
        XCTAssertEqual(file.lastDay, wed.adding(days: 4))
        XCTAssertEqual(Set(file.routes[0].outbound.map(\.serviceDay)).count, 5)
    }

    @MainActor
    func testAlertedTrainsAndUsualTimes() async throws {
        let rig = rig()
        let open = Route(from: oakville, to: union, line: line)
        rig.routeStore.save(open)
        let morning = trip("OA-UN-20261112-0700", day: wed.adding(days: 1), hour: 7)
        let evening = trip("OA-UN-20261111-1730", day: wed, hour: 17, minute: 30)
        await rig.rules.save(AlertRule(kind: .thisTrip, trip: morning, route: open))
        await rig.rules.save(AlertRule(kind: .repeating, trip: evening, route: open, weekdays: [3]))
        var paused = AlertRule(kind: .thisTrip, trip: trip("OA-UN-20261113-0700", day: wed.adding(days: 2), hour: 7), route: open)
        paused.paused = true
        await rig.rules.save(paused)

        await rig.writer.write()
        let file = try XCTUnwrap(written)
        let alerted = file.routes[0].outbound.filter(\.isAlerted).map(\.tripId)
        // Thursday's 7:00 (This trip) and each Wednesday's 17:30 (Repeat); the switched-off alert counts for nothing.
        XCTAssertEqual(alerted, ["OA-UN-20261111-1730", "OA-UN-20261112-0700", "OA-UN-20261118-1730"])
        XCTAssertFalse(file.routes[0].inbound.contains(where: \.isAlerted))
        XCTAssertEqual(
            file.usualTimes,
            [WidgetFile.UsualTime(route: WidgetFile.RouteKey(fromId: "OA", toId: "UN"), minutesIntoDay: 17 * 60 + 30, weekdays: [3])]
        )
    }

    /// The widgets reload only when the bytes change: a route, alert or Time format change does, backgrounding with nothing
    /// changed does not.
    @MainActor
    func testOnlyAChangeReloadsTheWidgets() async throws {
        let rig = rig()
        rig.routeStore.save(Route(from: oakville, to: union, line: line))
        await rig.writer.write()
        XCTAssertEqual(rig.reloads.count, 1)

        let unchanged = await rig.writer.write()
        XCTAssertFalse(unchanged)
        XCTAssertEqual(rig.reloads.count, 1)

        rig.settings.timeFormat = .twelveHour
        let format = await rig.writer.write()
        XCTAssertTrue(format)
        rig.routeStore.save(Route(from: burlington, to: union, line: line))
        let route = await rig.writer.write()
        XCTAssertTrue(route)
        await rig.rules.save(
            AlertRule(kind: .thisTrip, trip: trip("BU-UN-20261111-0700", day: wed, hour: 7), route: Route(from: burlington, to: union, line: line))
        )
        let alert = await rig.writer.write()
        XCTAssertTrue(alert)
        XCTAssertEqual(rig.reloads.count, 4)
    }

    @MainActor
    func testAScheduleThatCannotBeReadKeepsTheLastFile() async throws {
        let rig = rig()
        rig.routeStore.save(Route(from: oakville, to: union, line: line))
        await rig.writer.write()
        let before = try Data(contentsOf: fileURL)
        let failing = WidgetFileWriter(
            repository: FailingTimetable(), stations: FailingTimetable(), fileURL: fileURL, routeStore: rig.routeStore,
            rules: rig.rules, settings: rig.settings, recents: rig.recents, reload: {}
        )
        let wrote = await failing.write()
        XCTAssertFalse(wrote)
        XCTAssertEqual(try Data(contentsOf: fileURL), before)
    }

    /// Settings › Testing never reaches the widget file: its schedule is the one `withTesting()` wraps, and fixture runs
    /// have none.
    @MainActor
    func testDemoTrainsAndMockTimeNeverReachTheFile() throws {
        let timetable = FakeTimetable(lastDay: nil, stationList: [])
        let dependencies = ScheduleDependencies(
            repository: timetable, stations: timetable, clock: FixedClock(now: .now), widgetData: timetable
        ).withTesting()
        XCTAssertTrue(dependencies.repository is DemoScheduleRepository)
        XCTAssertTrue(dependencies.clock is MockTimeClock)
        XCTAssertTrue(try XCTUnwrap(dependencies.widgetData) is FakeTimetable)
        XCTAssertNil(ScheduleDependencies.app(environment: ["TT_FIXTURES": "1"]).widgetData)
    }

    @MainActor
    private func trip(_ id: String, day: ServiceDay, hour: Int, minute: Int = 0) -> Trip {
        let departure = day.date(hour: hour, minute: minute)
        return Trip(
            key: TripKey(serviceDay: day, tripId: id), scheduledDeparture: departure,
            scheduledArrival: departure.addingTimeInterval(40 * 60), platform: .pending, tags: []
        )
    }
}

/// Two trains each way each day, 7:00 AM (express) and 5:30 PM, ids from the route and day.
private struct FakeTimetable: ScheduleRepository, StationRepository {
    let lastDay: ServiceDay?
    let stationList: [Station]

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        [(7, 0), (17, 30)].map { hour, minute in
            let departure = day.date(hour: hour, minute: minute)
            return Trip(
                key: TripKey(serviceDay: day, tripId: "\(route.from.id)-\(route.to.id)-\(day.gtfsDate)-\(String(format: "%02d%02d", hour, minute))"),
                scheduledDeparture: departure, scheduledArrival: departure.addingTimeInterval(40 * 60), platform: .pending,
                tags: hour == 7 ? [.express] : []
            )
        }
    }

    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    func lastServiceDay() async throws -> ServiceDay? { lastDay }
    func stations() async throws -> [Station] { stationList }
    func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: nil) }
}

private struct FailingTimetable: ScheduleRepository, StationRepository {
    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { throw URLError(.notConnectedToInternet) }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    func stations() async throws -> [Station] { throw URLError(.notConnectedToInternet) }
    func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: nil) }
}

private struct FakeWidgetRoutes: WidgetRoutesProviding {
    let list: [Route]
    func routes() async -> [Route] { list }
}

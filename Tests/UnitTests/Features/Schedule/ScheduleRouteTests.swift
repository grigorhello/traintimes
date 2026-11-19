import XCTest
@testable import TrainTimes

/// The route the form hands to Schedule (TT-120): saved on device, then loaded. Who chose it, the swap button and the
/// silent turn of Automatic direction (TT-234, D116).
@MainActor
final class ScheduleRouteTests: XCTestCase {
    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func repository() throws -> FixtureScheduleRepository {
        try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
    }

    private func reverse(of route: Route) -> Route {
        Route(from: route.to, to: route.from, line: route.line)
    }

    func testFirstRouteIsSavedAndTheTimelineLoadsWhenItAppears() async throws {
        let repository = try repository()
        let store = UserDefaultsRouteStore(defaults: .ephemeral())
        let model = ScheduleViewModel(route: nil, repository: repository, clock: FixedClock(now: repository.now), routeStore: store)

        await model.show(repository.route)
        XCTAssertEqual(model.route, repository.route)
        XCTAssertEqual(store.route, repository.route)
        XCTAssertEqual(model.scrollRequest, 0, "The timeline appears now and loads itself")

        await model.loadIfNeeded()
        XCTAssertEqual(model.departures.count, 4)
        XCTAssertEqual(model.scrollRequest, 1)
    }

    func testNewRouteFromTheSheetReloadsAndScrolls() async throws {
        let repository = try repository()
        let store = UserDefaultsRouteStore(defaults: .ephemeral())
        let reverse = Route(from: repository.route.to, to: repository.route.from, line: repository.route.line)
        let model = ScheduleViewModel(route: reverse, repository: repository, clock: FixedClock(now: repository.now), routeStore: store)
        await model.loadIfNeeded()
        XCTAssertTrue(model.departures.isEmpty, "The fixtures only run Oakville to Union")

        await model.show(repository.route)
        XCTAssertEqual(model.departures.count, 4)
        XCTAssertEqual(model.scrollRequest, 2)
        XCTAssertEqual(store.route, repository.route)
    }

    func testSwapIsRemembered() async throws {
        let repository = try repository()
        let store = UserDefaultsRouteStore(defaults: .ephemeral())
        let model = ScheduleViewModel(
            route: repository.route, repository: repository, clock: FixedClock(now: repository.now), routeStore: store
        )
        await model.swap()
        XCTAssertEqual(store.route?.from.name, "Union")
        XCTAssertEqual(store.route?.to.name, "Oakville")
    }

    // MARK: Automatic direction (TT-234, D116)

    /// The silent turn: the route turns round, is saved and recorded in Recent as a swap is, and the new direction's
    /// trains load with a jump to Now and one Now play. No haptic, no event, and no one is told a choice was made.
    func testTurnIsSilentSavedAndLoadsTheNewTrains() async throws {
        let analytics = RecordingAnalytics.install()
        let repository = try repository()
        let reversed = reverse(of: repository.route)
        let store = UserDefaultsRouteStore(defaults: .ephemeral())
        let recents = RecentRoutes(defaults: .ephemeral())
        let haptics = FakeHaptics()
        let choices = RecordingChoices()
        let model = ScheduleViewModel(
            route: reversed, repository: repository, clock: FixedClock(now: repository.now), routeStore: store,
            recents: recents, haptics: haptics
        )
        model.choices = choices
        await model.loadIfNeeded()
        XCTAssertTrue(model.departures.isEmpty, "The fixtures only run Oakville to Union")
        let turns = model.turns
        let scrolls = model.scrollRequest
        let entrances = model.entranceRequest
        let pulses = model.nowPulse
        let sent = analytics.events.count

        await model.turn()

        XCTAssertEqual(model.route, repository.route)
        XCTAssertEqual(model.routeTitle, "Oakville to Union")
        XCTAssertEqual(store.route, repository.route, "Saved, so the next launch opens it")
        XCTAssertEqual(recents.routes, [repository.route, reversed], "Recorded in Recent as a swap is")
        XCTAssertEqual(model.turns, turns + 1)
        XCTAssertEqual(model.departures.count, 4, "The new direction's trains")
        XCTAssertFalse(model.awaitsNewTrains)
        XCTAssertEqual(model.entranceRequest, entrances + 1, "They cascade in")
        XCTAssertEqual(model.scrollRequest, scrolls + 1)
        XCTAssertTrue(model.scrollJumps, "A jump to Now, as a swap makes")
        XCTAssertEqual(model.nowPulse, pulses + 1, "One Now play")

        // Longer than the swap feel's 310 ms, so a feel on its way would have landed.
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(haptics.played, [], "No haptic: nothing answered a finger")
        XCTAssertEqual(analytics.events.count, sent, "No event: it would say where the rider is")
        XCTAssertTrue(choices.chosen.isEmpty, "The app's own turn is no one's choice")
    }

    /// Before the first load (a cold start under the splash) the route alone changes, and the normal load reads it.
    func testTurnBeforeTheFirstLoadOnlyChangesTheRoute() async throws {
        let repository = try repository()
        let store = UserDefaultsRouteStore(defaults: .ephemeral())
        let model = ScheduleViewModel(
            route: reverse(of: repository.route), repository: repository, clock: FixedClock(now: repository.now),
            routeStore: store
        )

        await model.turn()
        XCTAssertEqual(model.route, repository.route)
        XCTAssertEqual(store.route, repository.route)
        XCTAssertEqual(model.turns, 1)
        XCTAssertEqual(model.scrollRequest, 0, "Nothing is on screen yet")
        XCTAssertEqual(model.entranceRequest, 0)
        XCTAssertEqual(model.nowPulse, 0)

        await model.loadIfNeeded()
        XCTAssertEqual(model.departures.count, 4, "The launch's load reads the turned route")
        XCTAssertEqual(model.scrollRequest, 1)
    }

    /// The swap button is the rider's own choice: `route_swapped` once and no `route_set`, the swap feel, and the look is
    /// told the new route was chosen by hand. It is not counted as a turn.
    func testSwapSendsRouteSwappedPlaysItsFeelAndIsAChoiceByHand() async throws {
        let analytics = RecordingAnalytics.install()
        let repository = try repository()
        let haptics = FakeHaptics()
        let choices = RecordingChoices()
        let model = ScheduleViewModel(
            route: repository.route, repository: repository, clock: FixedClock(now: repository.now), haptics: haptics
        )
        model.choices = choices
        await model.loadIfNeeded()
        let sent = analytics.events.count

        await model.swap()

        let swapped = reverse(of: repository.route)
        XCTAssertEqual(model.route, swapped)
        XCTAssertEqual(Array(analytics.events.dropFirst(sent)), [AnalyticsEvent("route_swapped")])
        XCTAssertFalse(analytics.names.contains("route_set"))
        XCTAssertEqual(choices.chosen, [swapped])
        XCTAssertEqual(choices.by, [.byHand])
        XCTAssertEqual(model.turns, 0, "The swap button plays its own motion")
        // The swap feel is a Tap 310 ms after the tap.
        for _ in 0..<300 where haptics.played.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(haptics.played, [.tap])
    }

    /// `show` passes on who chose the route: by hand unless the caller says one train's link or a widget's route link did.
    func testShowPassesOnWhoChoseTheRoute() async throws {
        let repository = try repository()
        let reversed = reverse(of: repository.route)
        let choices = RecordingChoices()
        let model = ScheduleViewModel(route: nil, repository: repository, clock: FixedClock(now: repository.now))
        model.choices = choices

        await model.show(repository.route)
        await model.show(reversed, chosen: .trainLink)
        await model.show(repository.route, chosen: .widgetRoute)

        XCTAssertEqual(choices.chosen, [repository.route, reversed, repository.route])
        XCTAssertEqual(choices.by, [.byHand, .trainLink, .widgetRoute])
    }
}

/// Stands in for Automatic direction's look: records each route Schedule says was chosen, and by whom.
@MainActor
private final class RecordingChoices: RouteChoiceFollowing {
    private(set) var chosen: [Route] = []
    private(set) var by: [RouteChoice] = []

    func chose(_ route: Route, by choice: RouteChoice) {
        chosen.append(route)
        by.append(choice)
    }
}

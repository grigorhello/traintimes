import XCTest
@testable import TrainTimes

/// D48: Schedule records each route it shows as the newest recent route, per direction, and a relaunch restores the last
/// route and the recent list.
@MainActor
final class ScheduleRecentTests: XCTestCase {
    private func repository() throws -> FixtureScheduleRepository {
        try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
    }

    func testTheRouteOnScreenIsTheNewestRecentRoute() throws {
        let repository = try repository()
        let recents = RecentRoutes(defaults: .ephemeral())
        _ = ScheduleViewModel(route: repository.route, repository: repository, clock: FixedClock(now: repository.now), recents: recents)
        XCTAssertEqual(recents.routes, [repository.route])
    }

    /// Swapping keeps the first direction as a recent route, so the sheet offers the way back.
    func testSwapAndShowRecordTheRoute() async throws {
        let repository = try repository()
        let recents = RecentRoutes(defaults: .ephemeral())
        let model = ScheduleViewModel(
            route: repository.route, repository: repository, clock: FixedClock(now: repository.now), recents: recents
        )
        await model.swap()
        let back = try XCTUnwrap(model.route)
        XCTAssertEqual(recents.routes, [back, repository.route])
        XCTAssertEqual(recents.routes(excluding: model.route), [repository.route])

        let burlington = Route(from: Station(id: "BU", name: "Burlington"), to: repository.route.to, line: repository.route.line)
        await model.show(burlington)
        XCTAssertEqual(recents.routes, [burlington, back, repository.route])

        // The sheet opened over Burlington lists the other two, newest first.
        let form = RouteFormViewModel(route: model.route, repository: repository, recents: model.recents)
        XCTAssertEqual(form.recentRoutes, [back, repository.route])
    }

    /// Acceptance: a relaunch restores the last route, its direction and the recent routes.
    func testRelaunchRestoresTheLastRouteAndTheRecentRoutes() async throws {
        let repository = try repository()
        let defaults = UserDefaults.ephemeral()
        let model = ScheduleViewModel(
            route: repository.route, repository: repository, clock: FixedClock(now: repository.now),
            routeStore: UserDefaultsRouteStore(defaults: defaults), recents: RecentRoutes(defaults: defaults)
        )
        await model.swap()

        // What RootView does at launch.
        let store = UserDefaultsRouteStore(defaults: defaults)
        let relaunched = ScheduleViewModel(
            route: store.route, repository: repository, clock: FixedClock(now: repository.now), routeStore: store,
            recents: RecentRoutes(defaults: defaults)
        )
        XCTAssertEqual(relaunched.routeTitle, "Union to Oakville")
        XCTAssertEqual(relaunched.route?.line?.name, "Lakeshore West")
        XCTAssertEqual(relaunched.recents.routes(excluding: relaunched.route), [repository.route])
    }
}

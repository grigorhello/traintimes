import XCTest
@testable import TrainTimes

/// The route the form hands to Schedule (TT-120): saved on device, then loaded.
@MainActor
final class ScheduleRouteTests: XCTestCase {
    private func repository() throws -> FixtureScheduleRepository {
        try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
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
}

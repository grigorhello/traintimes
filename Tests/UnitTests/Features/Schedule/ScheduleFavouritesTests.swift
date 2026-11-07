import XCTest
@testable import TrainTimes

/// TT-122: the Schedule star, per direction, at the three-favourite limit, and the route restored on relaunch.
@MainActor
final class ScheduleFavouritesTests: XCTestCase {
    private func repository() throws -> FixtureScheduleRepository {
        try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
    }

    private func schedule(_ repository: FixtureScheduleRepository, _ favourites: Favourites) -> ScheduleViewModel {
        ScheduleViewModel(route: repository.route, repository: repository, clock: FixedClock(now: repository.now), favourites: favourites)
    }

    private func others(_ line: Line?) -> [Route] {
        let union = Station(id: "UN", name: "Union")
        return [("BU", "Burlington"), ("CL", "Clarkson"), ("PO", "Port Credit")].map {
            Route(from: Station(id: $0.0, name: $0.1), to: union, line: line)
        }
    }

    func testStarFollowsTheDirection() async throws {
        let repository = try repository()
        let favourites = Favourites(defaults: .ephemeral())
        let model = schedule(repository, favourites)
        XCTAssertEqual(model.toggleFavourite(), .toggled)
        XCTAssertTrue(model.isFavourite)

        await model.swap()
        XCTAssertFalse(model.isFavourite, "Union to Oakville is its own favourite")
        await model.swap()
        XCTAssertTrue(model.isFavourite)
    }

    /// At three favourites the star changes nothing and asks for Manage favourites instead.
    func testStarAtThreeFavouritesOpensManageInsteadOfReplacing() throws {
        let repository = try repository()
        let favourites = Favourites(defaults: .ephemeral())
        let full = others(repository.route.line)
        full.forEach { favourites.add($0) }
        let model = schedule(repository, favourites)

        XCTAssertEqual(model.toggleFavourite(), .full)
        XCTAssertFalse(model.isFavourite)
        XCTAssertEqual(favourites.routes, full)
    }

    func testStarStillRemovesWhenTheListIsFull() throws {
        let repository = try repository()
        let favourites = Favourites(defaults: .ephemeral())
        favourites.add(repository.route)
        others(repository.route.line).prefix(2).forEach { favourites.add($0) }
        let model = schedule(repository, favourites)

        XCTAssertTrue(model.isFavourite)
        XCTAssertEqual(model.toggleFavourite(), .toggled)
        XCTAssertFalse(model.isFavourite)
        XCTAssertEqual(favourites.routes.count, 2)
    }

    /// Removing a favourite in the route form turns the star off: both share one list.
    func testRouteFormAndStarShareTheList() throws {
        let repository = try repository()
        let favourites = Favourites(defaults: .ephemeral())
        favourites.add(repository.route)
        let model = schedule(repository, favourites)
        let form = RouteFormViewModel(route: model.route, repository: repository, favourites: model.favourites, isManagingFavourites: true)

        form.removeFavourite(repository.route)
        XCTAssertFalse(model.isFavourite)
    }

    /// Acceptance: a relaunch restores the last route and its direction, and the favourites.
    func testRelaunchRestoresTheLastRouteDirectionAndFavourites() async throws {
        let repository = try repository()
        let defaults = UserDefaults.ephemeral()
        let model = ScheduleViewModel(
            route: repository.route, repository: repository, clock: FixedClock(now: repository.now),
            routeStore: UserDefaultsRouteStore(defaults: defaults), favourites: Favourites(defaults: defaults)
        )
        XCTAssertEqual(model.toggleFavourite(), .toggled)
        await model.swap()

        // What RootView does at launch.
        let store = UserDefaultsRouteStore(defaults: defaults)
        let relaunched = ScheduleViewModel(
            route: store.route, repository: repository, clock: FixedClock(now: repository.now), routeStore: store,
            favourites: Favourites(defaults: defaults)
        )
        XCTAssertEqual(relaunched.routeTitle, "Union to Oakville")
        XCTAssertEqual(relaunched.route?.line?.name, "Lakeshore West")
        XCTAssertFalse(relaunched.isFavourite)
        XCTAssertEqual(relaunched.favourites.routes, [repository.route])
    }
}

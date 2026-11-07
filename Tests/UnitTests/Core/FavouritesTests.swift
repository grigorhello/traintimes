import XCTest
@testable import TrainTimes

/// TT-122: up to three favourites, each direction its own, kept on device.
@MainActor
final class FavouritesTests: XCTestCase {
    private let lakeshore = Line(id: "LW", name: "Lakeshore West", colorHex: "#111827")
    private let oakville = Station(id: "OA", name: "Oakville")
    private let union = Station(id: "UN", name: "Union")
    private let burlington = Station(id: "BU", name: "Burlington")
    private let clarkson = Station(id: "CL", name: "Clarkson")

    private func route(_ from: Station, _ to: Station) -> Route {
        Route(from: from, to: to, line: lakeshore)
    }

    /// Acceptance: three favourites at most; a fourth is refused and never replaces one.
    func testThreeFavouriteLimit() {
        let favourites = Favourites(defaults: .ephemeral())
        XCTAssertTrue(favourites.add(route(oakville, union)))
        XCTAssertTrue(favourites.add(route(union, oakville)))
        XCTAssertFalse(favourites.isFull)
        XCTAssertTrue(favourites.add(route(burlington, union)))
        XCTAssertTrue(favourites.isFull)

        XCTAssertFalse(favourites.add(route(clarkson, union)))
        XCTAssertEqual(favourites.routes, [route(oakville, union), route(union, oakville), route(burlington, union)])
        XCTAssertFalse(favourites.contains(route(clarkson, union)))

        favourites.remove(route(union, oakville))
        XCTAssertTrue(favourites.add(route(clarkson, union)), "Removing one makes room for another")
        XCTAssertEqual(favourites.routes, [route(oakville, union), route(burlington, union), route(clarkson, union)])
    }

    /// Acceptance: each direction is its own favourite.
    func testEachDirectionIsItsOwnFavourite() {
        let favourites = Favourites(defaults: .ephemeral())
        favourites.add(route(oakville, union))
        XCTAssertTrue(favourites.contains(route(oakville, union)))
        XCTAssertFalse(favourites.contains(route(union, oakville)))

        favourites.add(route(union, oakville))
        XCTAssertEqual(favourites.routes.count, 2)
        favourites.remove(route(oakville, union))
        XCTAssertEqual(favourites.routes, [route(union, oakville)], "Removing one direction keeps the other")
    }

    func testAddingTheSameDirectionTwiceKeepsOne() {
        let favourites = Favourites(defaults: .ephemeral())
        favourites.add(route(oakville, union))
        XCTAssertTrue(favourites.add(Route(from: oakville, to: union, line: nil)))
        XCTAssertEqual(favourites.routes.count, 1)
    }

    func testFavouritesAreKeptOnDeviceInOrder() {
        let defaults = UserDefaults.ephemeral()
        let noLine = Route(from: burlington, to: union, line: nil)
        let favourites = Favourites(defaults: defaults)
        favourites.add(route(union, oakville))
        favourites.add(noLine)
        XCTAssertEqual(Favourites(defaults: defaults).routes, [route(union, oakville), noLine])
    }

    /// UI tests pass `-route.favourites ""` to start with none.
    func testEmptyValueReadsAsNoFavourites() {
        let defaults = UserDefaults.ephemeral()
        defaults.set("", forKey: Favourites.key)
        XCTAssertEqual(Favourites(defaults: defaults).routes, [])
    }
}

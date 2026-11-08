import XCTest
@testable import TrainTimes

/// D48: the routes opened last, newest first, one entry per direction, four kept and three listed.
@MainActor
final class RecentRoutesTests: XCTestCase {
    private let union = Station(id: "UN", name: "Union Station GO")
    private let line = Line(id: "LW", name: "Lakeshore West", colorHex: "#98002e")

    private func route(_ id: String, _ name: String) -> Route {
        Route(from: Station(id: id, name: name), to: union, line: line)
    }

    func testNewestFirstAndOneEntryPerDirection() {
        let recents = RecentRoutes(defaults: nil)
        let oakville = route("OA", "Oakville GO")
        let back = Route(from: union, to: oakville.from, line: line)
        recents.record(oakville)
        recents.record(back)
        XCTAssertEqual(recents.routes, [back, oakville], "Each direction is its own entry")

        recents.record(oakville)
        XCTAssertEqual(recents.routes, [oakville, back], "Opening a route again moves it to the top")
    }

    func testKeepsFourAndListsThreeWithoutTheRouteOnScreen() {
        let recents = RecentRoutes(defaults: nil)
        let routes = [route("OA", "Oakville GO"), route("BU", "Burlington GO"), route("CL", "Clarkson GO"),
                      route("PO", "Port Credit GO"), route("AL", "Aldershot GO")]
        routes.forEach { recents.record($0) }
        XCTAssertEqual(recents.routes, Array(routes.reversed().prefix(4)))

        XCTAssertEqual(recents.routes(excluding: routes[4]), [routes[3], routes[2], routes[1]])
        XCTAssertEqual(recents.routes(excluding: nil), [routes[4], routes[3], routes[2]])
    }

    func testKeptOnDevice() {
        let defaults = UserDefaults.ephemeral()
        let oakville = route("OA", "Oakville GO")
        RecentRoutes(defaults: defaults).record(oakville)
        XCTAssertEqual(RecentRoutes(defaults: defaults).routes, [oakville])
        XCTAssertTrue(RecentRoutes(defaults: .ephemeral()).routes.isEmpty)
    }
}

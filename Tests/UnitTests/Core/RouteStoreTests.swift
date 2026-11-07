import XCTest
@testable import TrainTimes

@MainActor
final class RouteStoreTests: XCTestCase {
    private let lakeshore = Line(id: "LW", name: "Lakeshore West", colorHex: "#111827")

    func testFreshInstallHasNoRoute() {
        XCTAssertNil(UserDefaultsRouteStore(defaults: .ephemeral()).route)
    }

    func testSavedRouteIsReadBackOnTheNextLaunch() {
        let defaults = UserDefaults.ephemeral()
        let route = Route(from: Station(id: "OA", name: "Oakville"), to: Station(id: "UN", name: "Union"), line: lakeshore)
        UserDefaultsRouteStore(defaults: defaults).save(route)
        XCTAssertEqual(UserDefaultsRouteStore(defaults: defaults).route, route)
    }

    func testRouteWithoutLineIsKept() {
        let store = UserDefaultsRouteStore(defaults: .ephemeral())
        let route = Route(from: Station(id: "BU", name: "Burlington"), to: Station(id: "UN", name: "Union"), line: nil)
        store.save(route)
        XCTAssertEqual(store.route, route)
    }

    /// UI tests pass `-route.last ""` for a fresh install.
    func testEmptyValueReadsAsNoRoute() {
        let defaults = UserDefaults.ephemeral()
        defaults.set("", forKey: UserDefaultsRouteStore.key)
        XCTAssertNil(UserDefaultsRouteStore(defaults: defaults).route)
    }
}

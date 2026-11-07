import XCTest
@testable import TrainTimes

@MainActor
final class RouteFormViewModelTests: XCTestCase {
    private let oakville = Station(id: "OA", name: "Oakville")
    private let union = Station(id: "UN", name: "Union")

    private func model(_ route: Route? = nil) throws -> RouteFormViewModel {
        RouteFormViewModel(route: route, repository: try FixtureScheduleRepository(bundle: Bundle(for: Self.self)))
    }

    /// Acceptance: the first route takes two picks and one tap; picking From opens the To list straight away.
    func testFirstUseTakesTwoPicksAndOneTap() async throws {
        let model = try model()
        XCTAssertNil(model.from)
        XCTAssertNil(model.to)
        XCTAssertFalse(model.canShowTrains)
        XCTAssertFalse(model.canSwap)

        model.open(.from)
        await model.loadStations()
        XCTAssertEqual(model.stations.map(\.name), ["Oakville", "Union"])
        model.pick(oakville)
        XCTAssertTrue(model.isPickingStation, "The list stays open")
        XCTAssertEqual(model.pickingField, .to)
        XCTAssertFalse(model.canShowTrains)

        model.pick(union)
        XCTAssertFalse(model.isPickingStation)
        XCTAssertTrue(model.canShowTrains)
        let route = await model.route()
        XCTAssertEqual(route?.from, oakville)
        XCTAssertEqual(route?.to, union)
        XCTAssertEqual(route?.line?.name, "Lakeshore West")
    }

    func testIdenticalStationsAreRejectedInline() async throws {
        let model = try model()
        model.open(.from)
        model.pick(oakville)
        model.pick(oakville)
        XCTAssertTrue(model.isSameStation)
        XCTAssertFalse(model.canShowTrains)
        let route = await model.route()
        XCTAssertNil(route)
    }

    /// From the Schedule header the form opens prefilled, and changing From closes the list since To is set.
    func testPrefilledFormClosesTheListAfterOnePick() throws {
        let model = try model(Route(from: oakville, to: union, line: nil))
        XCTAssertTrue(model.canShowTrains)
        model.open(.from)
        model.pick(union)
        XCTAssertFalse(model.isPickingStation)
        XCTAssertTrue(model.isSameStation)
    }

    func testCancelLeavesTheFormUnchanged() throws {
        let model = try model(Route(from: oakville, to: union, line: nil))
        model.open(.to)
        model.closeStations()
        XCTAssertFalse(model.isPickingStation)
        XCTAssertEqual(model.to, union)
    }

    func testSwapReversesTheStations() async throws {
        let model = try model(Route(from: oakville, to: union, line: nil))
        model.swap()
        XCTAssertEqual(model.from, union)
        XCTAssertEqual(model.to, oakville)
        let route = await model.route()
        XCTAssertEqual(route?.line?.name, "Lakeshore West", "The line serves both directions")
    }

    /// A pair with no direct service still makes a route, with no line (Schedule then shows No direct connection).
    func testPairWithNoLineStillMakesARoute() async throws {
        let burlington = Station(id: "BU", name: "Burlington")
        let model = try model(Route(from: burlington, to: union, line: nil))
        let route = await model.route()
        XCTAssertEqual(route?.from, burlington)
        XCTAssertNil(route?.line)
    }
}

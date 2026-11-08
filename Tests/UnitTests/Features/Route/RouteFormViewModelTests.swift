import XCTest
@testable import TrainTimes

@MainActor
final class RouteFormViewModelTests: XCTestCase {
    private let oakville = Station(id: "OA", name: "Oakville GO", lines: ["Lakeshore West"])
    private let union = Station(id: "UN", name: "Union Station GO")

    /// `recent` are recorded oldest first, so the last one is the newest.
    private func model(_ route: Route? = nil, recent routes: [Route] = []) async throws -> RouteFormViewModel {
        let recents = RecentRoutes(defaults: .ephemeral())
        routes.forEach { recents.record($0) }
        let model = RouteFormViewModel(
            route: route, repository: try FixtureScheduleRepository(bundle: Bundle(for: Self.self)), recents: recents
        )
        await model.loadStations()
        return model
    }

    /// Acceptance: the first route takes two picks and one tap; picking From opens the To list straight away.
    func testFirstUseTakesTwoPicksAndOneTap() async throws {
        let model = try await model()
        XCTAssertNil(model.from)
        XCTAssertNil(model.to)
        XCTAssertFalse(model.canShowTrains)
        XCTAssertFalse(model.canSwap)

        model.open(.from)
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

    /// A saved route with the same station twice (only reachable from storage) is rejected inline.
    func testIdenticalStationsAreRejectedInline() async throws {
        let model = try await model(Route(from: oakville, to: Station(id: "OA", name: "Oakville"), line: nil))
        XCTAssertTrue(model.isSameStation, "Stations compare by id")
        XCTAssertEqual(model.from, model.to, "Station equality is the id, whatever the name or lines")
        XCTAssertFalse(model.canShowTrains)
        let route = await model.route()
        XCTAssertNil(route)
    }

    /// From the Schedule header the form opens prefilled, and changing From closes the list since To is set.
    func testPrefilledFormClosesTheListAfterOnePick() async throws {
        let model = try await model(Route(from: oakville, to: union, line: nil))
        XCTAssertTrue(model.canShowTrains)
        model.open(.from)
        model.pick(Station(id: "BU", name: "Burlington GO"))
        XCTAssertFalse(model.isPickingStation)
        XCTAssertEqual(model.from?.id, "BU")
    }

    func testCancelLeavesTheFormUnchanged() async throws {
        let model = try await model(Route(from: oakville, to: union, line: nil))
        model.open(.to)
        model.query = "ac"
        model.closeStations()
        XCTAssertFalse(model.isPickingStation)
        XCTAssertEqual(model.from, oakville)
        XCTAssertEqual(model.to, union)
    }

    func testSwapReversesTheStations() async throws {
        let model = try await model(Route(from: oakville, to: union, line: nil))
        model.swap()
        XCTAssertEqual(model.from, union)
        XCTAssertEqual(model.to, oakville)
        let route = await model.route()
        XCTAssertEqual(route?.line?.name, "Lakeshore West", "The line serves both directions")
    }

    /// D48: Recent lists the routes opened last, newest first, without the route the sheet opened with.
    func testRecentLeavesOutTheRouteOnScreen() async throws {
        let there = Route(from: oakville, to: union, line: nil)
        let back = Route(from: union, to: oakville, line: nil)
        let burlington = Route(from: Station(id: "BU", name: "Burlington GO"), to: union, line: nil)
        let model = try await model(there, recent: [burlington, back, there])
        XCTAssertEqual(model.recentRoutes, [back, burlington])
        XCTAssertEqual(model.title(model.recentRoutes[0]), "Union Station GO to Oakville GO")

        let firstUse = try await self.model()
        XCTAssertTrue(firstUse.recentRoutes.isEmpty, "First use shows the footnote")
    }

    /// A pair with no direct service still makes a route, with no line (Schedule then shows No direct connection).
    func testPairWithNoLineStillMakesARoute() async throws {
        let burlington = Station(id: "BU", name: "Burlington GO")
        let model = try await model(Route(from: burlington, to: union, line: nil))
        let route = await model.route()
        XCTAssertEqual(route?.from, burlington)
        XCTAssertNil(route?.line)
    }

    // MARK: Station search (TT-121)

    /// Acceptance: typing "oak" finds Oakville GO, whatever the case.
    func testTypingOakFindsOakvilleGO() async throws {
        let model = try await model()
        model.open(.from)
        model.query = "oak"
        XCTAssertEqual(model.allStations.map(\.station.name), ["Oakville GO"])
        model.query = "  OAK "
        XCTAssertEqual(model.allStations.map(\.station.name), ["Oakville GO"])
        model.query = "zzz"
        XCTAssertEqual(model.allStations, [])
    }

    /// Acceptance: the other field's station is greyed with its reason and cannot be picked.
    func testOtherFieldsStationIsGreyedAndCannotBePicked() async throws {
        let model = try await model(Route(from: oakville, to: union, line: nil))
        model.open(.from)
        let row = try XCTUnwrap(model.allStations.first { $0.id == "UN" })
        XCTAssertTrue(row.isDisabled)
        XCTAssertEqual(row.detail, "All lines · Same as To")
        model.pick(union)
        XCTAssertEqual(model.from, oakville, "Picking the To station for From does nothing")
        XCTAssertTrue(model.isPickingStation)

        model.open(.to)
        let oakvilleRow = try XCTUnwrap(model.allStations.first { $0.id == "OA" })
        XCTAssertTrue(oakvilleRow.isDisabled)
        XCTAssertEqual(oakvilleRow.detail, "Lakeshore West · Same as From")
        XCTAssertFalse(try XCTUnwrap(model.allStations.first { $0.id == "BU" }).isDisabled)
    }

    /// Rows show the full name and line context; All stations is alphabetical when choosing From.
    func testAllStationsAreAlphabeticalWithLineContext() async throws {
        let model = try await model()
        model.open(.from)
        let rows = model.allStations
        XCTAssertEqual(rows.prefix(3).map(\.station.name), ["Acton GO", "Agincourt GO", "Ajax GO"])
        XCTAssertEqual(rows.first?.detail, "Kitchener")
        XCTAssertEqual(rows.first { $0.id == "UN" }?.detail, "All lines")
        XCTAssertEqual(model.yourStations, [], "No recent routes, no Your stations group")
    }

    /// Choosing To lists Union Station GO first, unless it is the From station.
    func testUnionIsSuggestedFirstWhenChoosingTo() async throws {
        let model = try await model()
        model.open(.from)
        XCTAssertEqual(model.allStations.first?.id, "AC")
        model.pick(oakville)
        XCTAssertEqual(model.pickingField, .to)
        XCTAssertEqual(model.allStations.first?.id, "UN")
        XCTAssertEqual(model.allStations.filter { $0.id == "UN" }.count, 1)

        let fromUnion = try await self.model(Route(from: union, to: oakville, line: nil))
        fromUnion.open(.to)
        XCTAssertEqual(fromUnion.allStations.first?.id, "AC")
        XCTAssertTrue(try XCTUnwrap(fromUnion.allStations.first { $0.id == "UN" }).isDisabled)
    }

    /// Your stations come from the recent routes, alphabetically and with a clock (D48).
    func testYourStationsComeFromRecentRoutes() async throws {
        let model = try await model(recent: [Route(from: union, to: oakville, line: nil)])
        model.open(.from)
        XCTAssertEqual(model.yourStations.map(\.station.name), ["Oakville GO", "Union Station GO"])
        XCTAssertTrue(model.yourStations.allSatisfy(\.isRecent))
        XCTAssertTrue(try XCTUnwrap(model.allStations.first { $0.id == "OA" }).isRecent)
        model.query = "uni"
        XCTAssertEqual(model.yourStations.map(\.station.name), ["Union Station GO"])
    }

    /// Each time the search opens, or moves on from From to To, it starts empty.
    func testSearchClearsOnOpenAndPick() async throws {
        let model = try await model()
        model.open(.from)
        model.query = "oak"
        model.pick(oakville)
        XCTAssertEqual(model.query, "")
        model.query = "uni"
        model.closeStations()
        model.open(.to)
        XCTAssertEqual(model.query, "")
    }
}

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

    /// Schedule (D54): the picker opens over the route on screen, and one pick completes the route and applies at once.
    func testSchedulePickAppliesAtOnce() async throws {
        let model = try await model(Route(from: oakville, to: union, line: nil))
        XCTAssertTrue(model.appliesAtOnce)
        XCTAssertTrue(model.canShowTrains)
        model.open(.from)
        XCTAssertEqual(model.pickingStationName, "Oakville GO", "The current station shows selected")
        XCTAssertTrue(model.pick(Station(id: "BU", name: "Burlington GO")), "The caller shows the route now")
        XCTAssertFalse(model.isPickingStation)
        XCTAssertEqual(model.from?.id, "BU")
        let route = await model.route()
        XCTAssertEqual(route?.from.id, "BU")
        XCTAssertEqual(route?.to, union)
    }

    /// First use waits for "Show trains": no pick applies a route, even the one that completes it.
    func testFirstUsePickNeverAppliesAtOnce() async throws {
        let model = try await model()
        XCTAssertFalse(model.appliesAtOnce)
        model.open(.from)
        XCTAssertFalse(model.pick(oakville))
        XCTAssertFalse(model.pick(union))
        XCTAssertTrue(model.canShowTrains)
    }

    /// Cancel (the X, the scrim, a swipe down) changes nothing and clears what was typed.
    func testCancelLeavesTheFormUnchanged() async throws {
        let model = try await model(Route(from: oakville, to: union, line: nil))
        model.open(.to)
        model.query = "ac"
        model.closeStations()
        XCTAssertFalse(model.isPickingStation)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.from, oakville)
        XCTAssertEqual(model.to, union)
    }

    /// A Recent row applies both of its stations.
    func testChoosingARecentRouteAppliesBothStations() async throws {
        let back = Route(from: union, to: oakville, line: nil)
        let model = try await model(Route(from: oakville, to: union, line: nil), recent: [back])
        model.open(.to)
        model.choose(back)
        XCTAssertFalse(model.isPickingStation)
        XCTAssertEqual(model.from, union)
        XCTAssertEqual(model.to, oakville)
    }

    func testSwapReversesTheStations() async throws {
        let model = try await model(Route(from: oakville, to: union, line: nil))
        model.swap()
        XCTAssertEqual(model.from, union)
        XCTAssertEqual(model.to, oakville)
        let route = await model.route()
        XCTAssertEqual(route?.line?.name, "Lakeshore West", "The line serves both directions")
    }

    /// D48, D54: Recent lists the routes opened last, newest first, without the route on screen; Schedule only, and
    /// gone once the rider types.
    func testRecentIsScheduleOnlyAndHidesWhileTyping() async throws {
        let there = Route(from: oakville, to: union, line: nil)
        let back = Route(from: union, to: oakville, line: nil)
        let burlington = Route(from: Station(id: "BU", name: "Burlington GO"), to: union, line: nil)
        let model = try await model(there, recent: [burlington, back, there])
        model.open(.to)
        XCTAssertEqual(model.suggestedRoutes, [back, burlington])
        XCTAssertEqual(model.title(model.suggestedRoutes[0]), "Union Station GO to Oakville GO")
        model.query = "bur"
        XCTAssertEqual(model.suggestedRoutes, [])

        let firstUse = try await self.model(recent: [burlington, back, there])
        firstUse.open(.from)
        XCTAssertTrue(firstUse.suggestedRoutes.isEmpty, "First use has no Recent group")
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

    /// Acceptance: the other field's station is greyed with its reason (under Your stations; the line sections leave it
    /// out, D83) and cannot be picked.
    func testOtherFieldsStationIsGreyedAndCannotBePicked() async throws {
        let route = Route(from: oakville, to: union, line: nil)
        let model = try await model(route, recent: [route])
        model.open(.from)
        let row = try XCTUnwrap(model.yourStations.first { $0.id == "UN" })
        XCTAssertTrue(row.isDisabled)
        XCTAssertEqual(row.detail, "All lines · Same as To")
        XCTAssertFalse(model.pick(union))
        XCTAssertEqual(model.from, oakville, "Picking the To station for From does nothing")
        XCTAssertTrue(model.isPickingStation)

        model.open(.to)
        let oakvilleRow = try XCTUnwrap(model.yourStations.first { $0.id == "OA" })
        XCTAssertTrue(oakvilleRow.isDisabled)
        XCTAssertEqual(oakvilleRow.detail, "Lakeshore West · Same as From")
        let burlington = try XCTUnwrap(model.lineSections.first?.rows.first { $0.id == "BU" })
        XCTAssertFalse(burlington.isDisabled)
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
        XCTAssertEqual(model.lineSections.first?.rows.first?.id, "UN")
        XCTAssertEqual(model.lineSections.flatMap(\.rows).filter { $0.id == "UN" }.count, 1)
        XCTAssertNil(model.allStations.first { $0.id == "UN" })

        let fromUnion = try await self.model(Route(from: union, to: oakville, line: nil))
        fromUnion.open(.to)
        XCTAssertNil((fromUnion.lineSections.flatMap(\.rows) + fromUnion.allStations).first { $0.id == "UN" })
    }

    /// TT-200 (D83): with Oakville GO chosen, the destination list opens on Lakeshore West, Union first and then
    /// alphabetically (the fixture stations have no places), without Oakville itself; Other stations has every station on
    /// another line.
    func testSameLineStationsComeFirst() async throws {
        let model = try await model()
        model.open(.from)
        XCTAssertEqual(model.lineSections, [], "Nothing chosen: the list is as before")
        model.pick(oakville)
        let sections = model.lineSections
        XCTAssertEqual(sections.map(\.line.id), ["LW"])
        XCTAssertEqual(sections.first?.line.name, "Lakeshore West")
        let names = sections.first?.rows.map(\.station.name) ?? []
        XCTAssertEqual(names.prefix(3), ["Union Station GO", "Aldershot GO", "Appleby GO"])
        XCTAssertEqual(names.count, 14)
        XCTAssertFalse(names.contains("Oakville GO"))
        let others = model.allStations
        XCTAssertEqual(others.first?.station.name, "Acton GO")
        XCTAssertTrue(others.allSatisfy { !$0.station.lines.contains("Lakeshore West") })
        XCTAssertEqual(names.count + others.count, model.stations.count - 1)
    }

    /// TT-200 (D83): it works from either field, and a saved route's station (no lines of its own) takes its lines from
    /// the station list. Union, on every line, gives a section per line in GO's order and leaves no Other stations.
    func testFromFieldUsesTheToStationsLines() async throws {
        let saved = Route(from: Station(id: "OA", name: "Oakville"), to: Station(id: "UN", name: "Union"), line: nil)
        let model = try await model(saved)
        model.open(.from)
        XCTAssertEqual(model.lineSections.map(\.line.id), ["LW", "MI", "KI", "BR", "RH", "ST", "LE"])
        XCTAssertEqual(model.allStations, [])
        model.open(.to)
        XCTAssertEqual(model.lineSections.map(\.line.id), ["LW"])
    }

    /// TT-200 (D83): typing still finds every station, the shared line's matches first.
    func testSearchRanksSameLineMatchesFirst() async throws {
        let model = try await model()
        model.open(.from)
        model.pick(oakville)
        model.query = "b"
        XCTAssertEqual(model.lineSections.first?.rows.map(\.station.name), ["Bronte GO", "Burlington GO", "Long Branch GO"])
        XCTAssertTrue(model.allStations.contains { $0.station.name == "Bramalea GO" })
        XCTAssertFalse(model.hasNoMatch)
        model.pickFirstMatch()
        XCTAssertEqual(model.to?.name, "Bronte GO", "Return picks the first same-line match")
    }

    /// TT-200 (D83): with the feed's places, a line runs from Union outward.
    func testLineRunsFromUnionOutward() async throws {
        let line = ["Lakeshore West"]
        func station(_ id: String, _ name: String, _ latitude: Double, _ longitude: Double) -> Station {
            Station(id: id, name: name, lines: line, place: GeoPoint(latitude: latitude, longitude: longitude))
        }
        let stations = [
            station("AL", "Aldershot GO", 43.3132, -79.8556), station("EX", "Exhibition GO", 43.6363, -79.4187),
            station("OA", "Oakville GO", 43.4553, -79.6824), station("PO", "Port Credit GO", 43.5554, -79.5868),
            station("UN", "Union Station GO", 43.6453, -79.3806),
        ]
        let model = RouteFormViewModel(route: nil, repository: PlacedStations(list: stations))
        await model.loadStations()
        model.open(.from)
        model.pick(stations[0])
        XCTAssertEqual(model.lineSections.first?.rows.map(\.id), ["UN", "EX", "PO", "OA"])
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

    /// The active field's own station is not listed: picking it again would change nothing. Nor is the other field's
    /// station in its own line sections (D83).
    func testOwnStationIsNotListed() async throws {
        let model = try await model(Route(from: oakville, to: union, line: nil))
        model.open(.to)
        var listed = model.lineSections.flatMap(\.rows) + model.allStations
        XCTAssertNil(listed.first { $0.id == "UN" })
        XCTAssertNil(listed.first { $0.id == "OA" })
        XCTAssertNotNil(listed.first { $0.id == "BU" })
        model.open(.from)
        listed = model.lineSections.flatMap(\.rows) + model.allStations
        XCTAssertNil(listed.first { $0.id == "OA" })
        XCTAssertNil(listed.first { $0.id == "UN" })
        XCTAssertNotNil(listed.first { $0.id == "AC" })
    }

    /// Typing matches the start of a word: "st" finds Union Station GO, "nion" finds nothing.
    func testTypingMatchesWordPrefixes() async throws {
        let model = try await model()
        model.open(.from)
        model.query = "st"
        XCTAssertTrue(model.allStations.contains { $0.id == "UN" })
        model.query = "union st"
        XCTAssertEqual(model.allStations.map(\.station.name), ["Union Station GO"])
        model.query = "nion"
        XCTAssertEqual(model.allStations, [])
        model.query = "UNI"
        XCTAssertTrue(model.allStations.contains { $0.id == "UN" })
    }

    /// No match: one "No stations match" row in the panel, never before the stations have loaded.
    func testNoMatch() async throws {
        let model = try await model()
        model.open(.from)
        XCTAssertFalse(model.hasNoMatch)
        model.query = "zzz"
        XCTAssertTrue(model.hasNoMatch)

        let notLoaded = RouteFormViewModel(
            route: nil, repository: try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        )
        notLoaded.open(.from)
        notLoaded.query = "zzz"
        XCTAssertFalse(notLoaded.hasNoMatch, "Still loading")
    }

    /// The Return key picks the first station the typed text finds; with nothing typed it does nothing.
    func testReturnPicksTheFirstMatch() async throws {
        let model = try await model()
        model.open(.from)
        XCTAssertFalse(model.pickFirstMatch())
        XCTAssertNil(model.from)
        model.query = "oak"
        model.pickFirstMatch()
        XCTAssertEqual(model.from, oakville)
        XCTAssertEqual(model.pickingField, .to, "Focus moves on to the destination")
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
        XCTAssertEqual(model.query, "")
        model.query = "uni"
        model.open(.to)
        XCTAssertEqual(model.query, "")
    }
}

/// A station list with places, as the GTFS feed gives it.
private struct PlacedStations: StationRepository {
    let list: [Station]
    func stations() async throws -> [Station] { list }
    func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: nil) }
}

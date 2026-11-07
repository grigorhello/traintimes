import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Station search against design/frames/station-search.png, light and dark: choosing From with favourites (the frame),
/// choosing To on first use (Union Station GO first), and the search for "oak". Drawn in the key window, since the sheet
/// is a NavigationStack with a search bar.
final class StationSearchSnapshotTests: XCTestCase {
    @MainActor func testFromLight() async throws { snap(try await fromWithFavourites(), .light) }
    @MainActor func testFromDark() async throws { snap(try await fromWithFavourites(), .dark) }
    @MainActor func testToLight() async throws { snap(try await toOnFirstUse(), .light) }
    @MainActor func testToDark() async throws { snap(try await toOnFirstUse(), .dark) }
    @MainActor func testSearchLight() async throws { snap(try await search(), .light) }
    @MainActor func testSearchDark() async throws { snap(try await search(), .dark) }

    @MainActor
    private func model(route: (FixtureScheduleRepository) -> Route?, favourites: Bool) async throws -> RouteFormViewModel {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let model = RouteFormViewModel(
            route: route(repository), repository: repository, favourites: favourites ? [repository.route] : []
        )
        await model.loadStations()
        return model
    }

    /// The frame: Oakville to Union saved and a favourite, choosing From, so Union Station GO is greyed "Same as To".
    @MainActor
    private func fromWithFavourites() async throws -> RouteFormViewModel {
        let model = try await model(route: { $0.route }, favourites: true)
        model.open(.from)
        return model
    }

    @MainActor
    private func toOnFirstUse() async throws -> RouteFormViewModel {
        let model = try await model(route: { _ in nil }, favourites: false)
        model.open(.from)
        model.pick(try XCTUnwrap(model.stations.first { $0.id == "OA" }))
        return model
    }

    @MainActor
    private func search() async throws -> RouteFormViewModel {
        let model = try await model(route: { _ in nil }, favourites: false)
        model.open(.from)
        model.query = "oak"
        return model
    }

    @MainActor
    private func snap(_ model: RouteFormViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        assertSnapshot(
            of: StationSearchView(viewModel: model),
            as: .image(
                drawHierarchyInKeyWindow: true,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ),
            testName: testName,
            line: line
        )
    }
}

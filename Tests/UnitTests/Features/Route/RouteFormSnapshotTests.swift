import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Route form against design/frames/route-picker.png, light and dark: first use in the Schedule tab (drawn in the key
/// window so the tab bar renders), then the form as the route sheet with a route chosen and with identical stations.
final class RouteFormSnapshotTests: XCTestCase {
    @MainActor func testFirstUseLight() { snapFirstUse(.light) }
    @MainActor func testFirstUseDark() { snapFirstUse(.dark) }
    @MainActor func testChosenLight() throws { snap(try form(), .light) }
    @MainActor func testChosenDark() throws { snap(try form(), .dark) }
    @MainActor func testSameStationLight() throws { snap(try form(sameStation: true), .light) }
    @MainActor func testSameStationDark() throws { snap(try form(sameStation: true), .dark) }

    /// No saved route and fresh settings, so nothing an earlier run stored leaks in.
    @MainActor
    private func snapFirstUse(_ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let root = RootView(
            settings: AppSettings(defaults: .ephemeral()),
            dependencies: .fixtures(bundle: Bundle(for: Self.self)),
            routeStore: UserDefaultsRouteStore(defaults: .ephemeral())
        )
        assertSnapshot(
            of: root,
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

    @MainActor
    private func form(sameStation: Bool = false) throws -> RouteFormView {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let route = repository.route
        // Station search cannot pick the other field's station (TT-121), so identical stations come from the route.
        let model = RouteFormViewModel(
            route: sameStation ? Route(from: route.from, to: route.from, line: nil) : route, repository: repository
        )
        return RouteFormView(viewModel: model, onShowTrains: { _ in })
    }

    @MainActor
    private func snap(_ view: some View, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .device(config: .iPhone17Pro), traits: UITraitCollection(userInterfaceStyle: style)),
            testName: testName,
            line: line
        )
    }
}

import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The inline station picker (TT-161, D52) against design/frames/route-picker.png, route-pick-from.png, route-pick-to.png
/// and schedule-pick.png, light and dark: first use closed, picking From with nothing typed, picking To with "un" typed,
/// and Schedule changing the destination in place (Recent, Your stations with the greyed row). The keyboard is not drawn;
/// a safe area of its height stands in for it, so the panel ends where it does on the simulator.
final class RouteFormSnapshotTests: XCTestCase {
    /// The software keyboard on iPhone 17 Pro, portrait.
    private static let keyboardHeight: CGFloat = 291

    @MainActor func testFirstUseLight() { snapFirstUse(.light) }
    @MainActor func testFirstUseDark() { snapFirstUse(.dark) }
    @MainActor func testPickingFromLight() async throws { snap(try await pickingFrom(), .light) }
    @MainActor func testPickingFromDark() async throws { snap(try await pickingFrom(), .dark) }
    @MainActor func testPickingToLight() async throws { snap(try await pickingTo(), .light) }
    @MainActor func testPickingToDark() async throws { snap(try await pickingTo(), .dark) }
    @MainActor func testSchedulePickingLight() async throws { snap(try await schedulePicking(), .light) }
    @MainActor func testSchedulePickingDark() async throws { snap(try await schedulePicking(), .dark) }

    /// No saved route and fresh settings, so nothing an earlier run stored leaks in.
    @MainActor
    private func snapFirstUse(_ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let root = RootView(
            settings: AppSettings(defaults: .ephemeral()),
            dependencies: .fixtures(bundle: Bundle(for: Self.self)),
            routeStore: UserDefaultsRouteStore(defaults: .ephemeral()),
            recents: RecentRoutes(defaults: .ephemeral())
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

    /// First use, tapped the starting station: the placeholder, every station in the panel.
    @MainActor
    private func pickingFrom() async throws -> some View {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let model = RouteFormViewModel(route: nil, repository: repository)
        await model.loadStations()
        model.open(.from)
        return form(model)
    }

    /// First use, Oakville GO chosen and "un" typed for the destination.
    @MainActor
    private func pickingTo() async throws -> some View {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let model = RouteFormViewModel(route: nil, repository: repository)
        await model.loadStations()
        model.open(.from)
        model.pick(try XCTUnwrap(model.stations.first { $0.id == "OA" }))
        model.query = "un"
        return form(model)
    }

    @MainActor
    private func form(_ model: RouteFormViewModel) -> some View {
        RouteFormView(viewModel: model, onShowTrains: { _ in })
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: Self.keyboardHeight) }
    }

    /// Schedule on Oakville to Union with the destination tapped, and the canvas's recent routes: Union to Oakville,
    /// Burlington to Union and Clarkson to Union under the route on screen.
    @MainActor
    private func schedulePicking() async throws -> some View {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let route = repository.route
        let recents = RecentRoutes(defaults: .ephemeral())
        [
            Route(from: Station(id: "CL", name: "Clarkson GO"), to: route.to, line: route.line),
            Route(from: Station(id: "BU", name: "Burlington GO"), to: route.to, line: route.line),
            Route(from: route.to, to: route.from, line: route.line),
        ].forEach { recents.record($0) }
        let schedule = ScheduleViewModel(
            route: route, repository: repository, clock: FixedClock(now: repository.now), recents: recents
        )
        await schedule.loadIfNeeded()
        let picker = RouteFormViewModel(route: route, repository: repository, recents: recents)
        await picker.loadStations()
        picker.open(.to)
        let view = ScheduleView(viewModel: schedule, stations: repository, picker: picker)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: Self.keyboardHeight) }
        layOutOnce(view)
        return view
    }

    @MainActor
    private func snap(_ view: some View, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        assertSnapshot(
            of: view,
            as: .image(
                perceptualPrecision: 0.98, layout: .device(config: .iPhone17Pro), traits: UITraitCollection(userInterfaceStyle: style)
            ),
            testName: testName,
            line: line
        )
    }
}

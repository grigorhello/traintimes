import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The first launch (TT-206) at rest against the Route and stations canvas, light and dark: Bloom's last frame (board 1),
/// the welcome (board 3), step 1 (board 4) and step 2 on a long line and a short one (board 5). First trains loading and
/// failed (board 6) are `ScheduleStatesSnapshotTests`' Loading and Failed.
final class WelcomeSnapshotTests: XCTestCase {
    @MainActor func testSplashLight() { snap(LaunchSplash(atRest: true), .light) }
    @MainActor func testSplashDark() { snap(LaunchSplash(atRest: true), .dark) }
    @MainActor func testWelcomeLight() throws { snap(flow(try model()), .light) }
    @MainActor func testWelcomeDark() throws { snap(flow(try model()), .dark) }
    @MainActor func testLinesLight() throws { snap(flow(try model { $0.chooseYourLine() }), .light) }
    @MainActor func testLinesDark() throws { snap(flow(try model { $0.chooseYourLine() }), .dark) }
    /// Lakeshore West, 15 stations: the list scrolls under a fade.
    @MainActor func testLongLineLight() throws { snap(flow(try station("LW")), .light) }
    @MainActor func testLongLineDark() throws { snap(flow(try station("LW")), .dark) }
    /// Richmond Hill, 6 stations: the list ends with its last row.
    @MainActor func testShortLineLight() throws { snap(flow(try station("RH")), .light) }
    @MainActor func testShortLineDark() throws { snap(flow(try station("RH")), .dark) }

    /// At 7:21 AM, so step 2 has the station first and Union second.
    @MainActor
    private func model(_ change: (WelcomeViewModel) -> Void = { _ in }) throws -> WelcomeViewModel {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let model = WelcomeViewModel(stations: repository, clock: FixedClock(now: repository.now))
        change(model)
        return model
    }

    @MainActor
    private func station(_ lineId: String) throws -> WelcomeViewModel {
        try model {
            $0.chooseYourLine()
            $0.pick(lineId: lineId)
        }
    }

    @MainActor
    private func flow(_ model: WelcomeViewModel) -> some View {
        WelcomeFlowView(model: model, startsOnSplash: false, onRoute: { _ in })
            .environment(\.animatesPickerEntrance, false)
    }

    @MainActor
    private func snap(_ view: some View, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        // The button's dark glass is drawn differently from one run to the next; its solid fallback here, the glass on the
        // simulator.
        let view = view.environment(\.rendersGlass, false)
        // The tiles fly to where the rows measured them: lay out once so they are in place when the snapshot draws.
        layOutOnce(view)
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ).comparedAsRecorded,
            testName: testName,
            line: line
        )
    }
}

import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Schedule screen against design/frames/schedule-timeline.png and schedule-timeline-dark.png (today: header, rail,
/// Now line and cards in the normal state, TT-112 and TT-113) and design/frames/schedule-no-trains.png (Sun 8 selected),
/// light and dark. Drawn inside the shell in the key window, so the bars and safe areas render as on the simulator.
/// The screen is laid out once first, so the cards' measured sizes are in the layout the snapshot draws.
final class ScheduleSnapshotTests: XCTestCase {
    @MainActor func testTodayLight() async throws { snap(try await .loadedFixture(), .light) }
    @MainActor func testTodayDark() async throws { snap(try await .loadedFixture(), .dark) }
    @MainActor func testAnotherDayLight() async throws { snap(try await .loadedFixture(dayIndex: 3), .light) }
    @MainActor func testAnotherDayDark() async throws { snap(try await .loadedFixture(dayIndex: 3), .dark) }

    @MainActor
    private func snap(_ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = RootView(schedule: schedule)
        layOutOnce(view)
        assertSnapshot(
            of: view,
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

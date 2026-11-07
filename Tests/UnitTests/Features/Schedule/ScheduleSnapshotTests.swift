import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Route header, day strip and freshness row against design/frames/schedule-timeline.png (today) and
/// design/frames/schedule-no-trains.png (Sun 8 selected), light and dark. Cards and states arrive in TT-113 to TT-115.
/// Drawn inside the shell in the key window, so the bars and safe areas render as on the simulator.
final class ScheduleSnapshotTests: XCTestCase {
    @MainActor func testTodayLight() async throws { snap(try await .loadedFixture(), .light) }
    @MainActor func testTodayDark() async throws { snap(try await .loadedFixture(), .dark) }
    @MainActor func testAnotherDayLight() async throws { snap(try await .loadedFixture(dayIndex: 3), .light) }
    @MainActor func testAnotherDayDark() async throws { snap(try await .loadedFixture(dayIndex: 3), .dark) }

    @MainActor
    private func snap(_ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        assertSnapshot(
            of: RootView(schedule: schedule),
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

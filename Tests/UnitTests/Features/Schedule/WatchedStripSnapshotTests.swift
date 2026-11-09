import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Schedule with a watched train kept after departure, against design/frames/schedule-watched.png (TT-144): the
/// accent-soft strip under the day strip, light and dark, at 7:28 AM as in the frame. A snapshot cannot scroll to Now,
/// so the timeline starts at its first train, the departed 7:05 AM; compare the header and the strip.
final class WatchedStripSnapshotTests: XCTestCase {
    @MainActor func testWatchedLight() async throws { snap(try await .watchedFixture(), .light) }
    @MainActor func testWatchedDark() async throws { snap(try await .watchedFixture(), .dark) }

    /// TT-153: the longest real station name stays readable in the route header and the strip, light and dark.
    @MainActor func testLongNamesLight() async throws { snap(try await .watchedFixture(route: .longNames), .light) }
    @MainActor func testLongNamesDark() async throws { snap(try await .watchedFixture(route: .longNames), .dark) }

    @MainActor
    private func snap(_ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let settings = AppSettings(defaults: .ephemeral())
        settings.timeFormat = .twelveHour
        let view = RootView(schedule: schedule, settings: settings)
        layOutOnce(view)
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                precision: glassSnapshotPrecision,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ),
            testName: testName,
            line: line
        )
    }
}

private extension Route {
    static let longNames = Route(
        from: Station(id: "UN", name: "Union Station GO"),
        to: Station(id: "BR", name: "Brampton Innovation District GO"),
        line: Line(id: "KI", name: "Kitchener", colorHex: nil)
    )
}

import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Schedule screen against design/frames/schedule-timeline.png and schedule-timeline-dark.png (today: header, rail,
/// Now line and cards in the normal state, TT-112 and TT-113), design/frames/schedule-no-trains.png (Sun 8 selected),
/// and the delayed and cancelled states (TT-114), light and dark. Drawn inside the shell in the key window, so the bars and safe areas render as on the simulator.
/// The screen is laid out once first, so the cards' measured sizes are in the layout the snapshot draws.
final class ScheduleSnapshotTests: XCTestCase {
    @MainActor func testTodayLight() async throws { snap(try await .loadedFixture(), .light) }
    @MainActor func testTodayDark() async throws { snap(try await .loadedFixture(), .dark) }
    @MainActor func testAnotherDayLight() async throws { snap(try await .loadedFixture(dayIndex: 3), .light) }
    @MainActor func testAnotherDayDark() async throws { snap(try await .loadedFixture(dayIndex: 3), .dark) }
    // TT-160: a past day selected (Wed 4), with the strip scrolled to show it. The fixtures run no trains before Thu 5, so the
    // timeline area shows the empty state, as a past day outside the feed does on a device.
    @MainActor func testPastDayLight() async throws { snap(try await .loadedFixture(dayIndex: -1), .light) }
    @MainActor func testPastDayDark() async throws { snap(try await .loadedFixture(dayIndex: -1), .dark) }
    // TT-114: design/frames/schedule-timeline-delayed.png, schedule-timeline-cancelled.png and schedule-dark.png. The
    // delayed scenario also has the Lakeshore West line notice, so its Notice chip matches schedule-delayed.png (TT-132).
    @MainActor func testDelayedLight() async throws { snap(try await .loadedFixture(.delayed), .light) }
    @MainActor func testDelayedDark() async throws { snap(try await .loadedFixture(.delayed), .dark) }
    @MainActor func testCancelledLight() async throws { snap(try await .loadedFixture(.cancelled), .light) }
    @MainActor func testCancelledDark() async throws { snap(try await .loadedFixture(.cancelled), .dark) }
    @MainActor func testEveningDark() async throws { snap(try await .loadedFixture(.eveningDark), .dark) }

    @MainActor
    private func snap(_ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = RootView(schedule: schedule, settings: AppSettings(defaults: .ephemeral()))
        layOutOnce(view)
        // The whole failure message on one line, so the CI log shows how far the image is from the reference: this suite
        // failed one test now and then after TT-164 (a different one each run) with only the message's first line logged.
        let failure = verifySnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                precision: glassSnapshotPrecision,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ),
            file: #filePath,
            testName: testName,
            line: line
        )
        if let failure {
            let diagnostics = snapshotDiagnostics(of: view, style: style, file: #filePath, testName: testName)
            XCTFail(failure.replacingOccurrences(of: "\n", with: " | ") + " | " + diagnostics, line: line)
        }
    }
}

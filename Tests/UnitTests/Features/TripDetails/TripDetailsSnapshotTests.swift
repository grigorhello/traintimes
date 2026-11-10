import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Trip details against design/frames/trip-details*.png (TT-163), light and dark: the 7:32 AM train delayed 9 min with an
/// alert, the 7:58 AM express train on the timetable only, a cancelled train, a 12-stop trip scrolled to its end, and a train
/// after it has left. The sheet content is drawn on its own in the key window; the system draws the grabber.
final class TripDetailsSnapshotTests: XCTestCase {
    @MainActor func testDelayedLight() async throws { snap(try await .loadedFixture(.delayed, hasAlert: true), .light) }
    @MainActor func testDelayedDark() async throws { snap(try await .loadedFixture(.delayed, hasAlert: true), .dark) }
    @MainActor func testScheduledLight() async throws { snap(try await .timetableOnlyFixture(), .light) }
    @MainActor func testScheduledDark() async throws { snap(try await .timetableOnlyFixture(), .dark) }
    @MainActor func testCancelledLight() async throws { snap(try await .loadedFixture(.cancelled, hasAlert: true), .light) }
    @MainActor func testCancelledDark() async throws { snap(try await .loadedFixture(.cancelled, hasAlert: true), .dark) }
    @MainActor func testEndLight() async throws { snap(try await .longTripFixture(), .light, startsAtEnd: true) }
    @MainActor func testEndDark() async throws { snap(try await .longTripFixture(), .dark, startsAtEnd: true) }
    @MainActor func testDepartedLight() async throws { snap(try await .departedFixture(), .light) }
    @MainActor func testDepartedDark() async throws { snap(try await .departedFixture(), .dark) }

    @MainActor
    private func snap(
        _ model: TripDetailsViewModel, _ style: UIUserInterfaceStyle, startsAtEnd: Bool = false,
        testName: String = #function, line: UInt = #line
    ) {
        let view = TripDetailsView(viewModel: model, startsAtEnd: startsAtEnd)
            .environment(\.timeFormatter, TimeFormatter(format: .twelveHour))
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

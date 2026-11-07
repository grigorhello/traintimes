import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Trip details against design/frames/trip-details.png, light and dark: the 7:32 AM train on time, delayed 9 min (with
/// an alert, as in the frame) and after it has left. The sheet content is drawn on its own; the system draws the grabber.
final class TripDetailsSnapshotTests: XCTestCase {
    @MainActor func testOnTimeLight() async throws { snap(try await .loadedFixture(), .light) }
    @MainActor func testOnTimeDark() async throws { snap(try await .loadedFixture(), .dark) }
    @MainActor func testDelayedLight() async throws { snap(try await .loadedFixture(.delayed, hasAlert: true), .light) }
    @MainActor func testDelayedDark() async throws { snap(try await .loadedFixture(.delayed, hasAlert: true), .dark) }
    @MainActor func testDepartedLight() async throws { snap(try await .departedFixture(), .light) }
    @MainActor func testDepartedDark() async throws { snap(try await .departedFixture(), .dark) }

    @MainActor
    private func snap(_ model: TripDetailsViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = TripDetailsView(viewModel: model)
            .environment(\.timeFormatter, TimeFormatter(format: .twelveHour))
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .device(config: .iPhone17Pro), traits: UITraitCollection(userInterfaceStyle: style)),
            testName: testName,
            line: line
        )
    }
}

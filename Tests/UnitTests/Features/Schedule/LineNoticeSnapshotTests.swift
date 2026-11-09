import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The line notice sheet (TT-132), light and dark, with the fixture's Lakeshore West notice from the delayed scenario.
/// The Notice chip is in `ScheduleSnapshotTests.testDelayed*` (design/frames/schedule-delayed.png). The
/// sheet content is drawn on its own; the system draws the grabber.
final class LineNoticeSnapshotTests: XCTestCase {
    @MainActor func testSheetLight() async throws { snap(try await .loadedFixture(.delayed), .light) }
    @MainActor func testSheetDark() async throws { snap(try await .loadedFixture(.delayed), .dark) }

    @MainActor
    private func snap(_ model: ScheduleViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = LineNoticeSheet(viewModel: model)
            .environment(\.timeFormatter, TimeFormatter(format: .twelveHour))
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .device(config: .iPhone17Pro), traits: UITraitCollection(userInterfaceStyle: style)),
            testName: testName,
            line: line
        )
    }
}

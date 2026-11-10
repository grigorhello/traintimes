import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Alerts tab icon with no dot, the accent dot (something new, TT-143) and the red dot (notifications off while an alert
/// is on, TT-169, D58), light and dark, at three times their size on the bar's surface.
final class TabBarDotSnapshotTests: XCTestCase {
    @MainActor func testBellDotsLight() { snap(.light) }
    @MainActor func testBellDotsDark() { snap(.dark) }

    @MainActor
    private func snap(_ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        assertSnapshot(
            of: BellDots(),
            as: .image(perceptualPrecision: 0.98, layout: .fixed(width: 330, height: 120), traits: UITraitCollection(userInterfaceStyle: style)),
            testName: testName,
            line: line
        )
    }
}

private struct BellDots: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 36) {
            ForEach([nil, TabBarStyle.Dot.accent, .warning], id: \.self) { dot in
                TabBarStyle.icon("bell.fill", label: "Alerts", isSelected: false, dot: dot, colorScheme: colorScheme)
                    .scaleEffect(3)
                    .frame(width: 80, height: 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.surface)
    }
}

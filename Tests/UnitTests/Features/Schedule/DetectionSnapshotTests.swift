import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The departure question on Schedule against board 9 of the Live view canvas (TT-231; one line, Yes and No since TT-205,
/// D93; it was train detection's until TT-243), and the automatic ride's one-time strip (TT-243, D120), light and dark.
/// Drawn under the top of the screen on the canvas ground, with the ripple still.
final class DetectionSnapshotTests: XCTestCase {
    @MainActor func testQuestionLight() { snap(question, .light) }
    @MainActor func testQuestionDark() { snap(question, .dark) }
    @MainActor func testAutoRideStripLight() { snap(autoRideStrip, .light) }
    @MainActor func testAutoRideStripDark() { snap(autoRideStrip, .dark) }

    private let formatter = TimeFormatter(format: .twelveHour)

    @MainActor
    private var question: some View {
        screen { TrainQuestionCard(title: TrainQuestionCard.title(stop: "Clarkson GO")) }
    }

    @MainActor
    private var autoRideStrip: some View {
        screen { DirectionStripCard.autoRide() }
    }

    @MainActor
    private func screen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: TTSpace.s3) {
            content()
            Spacer()
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
    }

    @MainActor
    private func snap(_ content: some View, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = content
            .environment(\.timeFormatter, formatter)
            .environment(\.rendersGlass, false)
            .environment(\.playsRideMotion, false)
        layOutOnce(view)
        // The whole failure message on one line, so the CI log shows how far the image is from the reference.
        let failure = verifySnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                precision: glassSnapshotPrecision,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ).comparedAsRecorded,
            file: #filePath,
            testName: testName,
            line: line
        )
        if let failure {
            XCTFail(failure.replacingOccurrences(of: "\n", with: " | "), line: line)
        }
    }
}

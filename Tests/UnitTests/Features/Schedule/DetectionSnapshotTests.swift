import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Train detection's question on Schedule against board 9 of the Live view canvas (TT-175; one line, Yes and No since
/// TT-205, D93), light and dark. Drawn under the top of the screen on the canvas ground, with the ripple still.
final class DetectionSnapshotTests: XCTestCase {
    @MainActor func testQuestionLight() { snap(question, .light) }
    @MainActor func testQuestionDark() { snap(question, .dark) }

    private let formatter = TimeFormatter(format: .twelveHour)

    @MainActor
    private var question: some View {
        screen {
            if let question = TrainQuestion(DetectionFixtures.question()) {
                TrainQuestionCard(question: question)
            }
        }
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

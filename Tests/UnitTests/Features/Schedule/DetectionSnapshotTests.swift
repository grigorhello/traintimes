import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Train detection on Schedule against the canvas's Live-Detect board (TT-175), light and dark: the checking strip while it
/// matches and once the train shares a stop, and the question for one train and for two. Drawn under the top of the screen on
/// the canvas ground, with the ripples still.
final class DetectionSnapshotTests: XCTestCase {
    @MainActor func testCheckingLight() { snap(checking, .light) }
    @MainActor func testCheckingDark() { snap(checking, .dark) }
    @MainActor func testQuestionLight() { snap(question(both: false), .light) }
    @MainActor func testQuestionDark() { snap(question(both: false), .dark) }
    @MainActor func testQuestionTwoTrainsLight() { snap(question(both: true), .light) }
    @MainActor func testQuestionTwoTrainsDark() { snap(question(both: true), .dark) }

    private let formatter = TimeFormatter(format: .twelveHour)

    /// "Matching your train…", then "Looks like the 5:13 PM train · 1 of 2 stops".
    @MainActor
    private var checking: some View {
        screen {
            ForEach([0, 1], id: \.self) { stops in
                if let strip = DetectionStrip(DetectionFixtures.progress(stops: stops), formatter: formatter) {
                    DetectionStripView(strip: strip)
                }
            }
        }
    }

    @MainActor
    private func question(both: Bool) -> some View {
        screen {
            TrainQuestionCard(question: TrainQuestion(DetectionFixtures.question(both: both), formatter: formatter))
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
            ),
            file: #filePath,
            testName: testName,
            line: line
        )
        if let failure {
            XCTFail(failure.replacingOccurrences(of: "\n", with: " | "), line: line)
        }
    }
}

import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Before departure against the canvas's Live-Depart-Trip and Live-Depart boards (TT-177), light and dark: the demo
/// train's Trip details pending (5:01 PM), with Platform 7 just announced (5:03), 3 min late (5:07) and boarding (5:14);
/// the countdown strip on Schedule. Glass is drawn as its solid fallback, and the motion is off (the pill still).
final class DepartureSnapshotTests: XCTestCase {
    @MainActor func testPendingLight() async { snap(await sheet(at: DepartureRig.time(17, 1)), .light) }
    @MainActor func testPendingDark() async { snap(await sheet(at: DepartureRig.time(17, 1)), .dark) }
    @MainActor func testPlatformLight() async { snap(await announced(), .light) }
    @MainActor func testPlatformDark() async { snap(await announced(), .dark) }
    @MainActor func testDelayedLight() async { snap(await sheet(at: DepartureRig.time(17, 7)), .light) }
    @MainActor func testDelayedDark() async { snap(await sheet(at: DepartureRig.time(17, 7)), .dark) }
    @MainActor func testBoardingLight() async { snap(await sheet(at: DepartureRig.time(17, 14)), .light) }
    @MainActor func testBoardingDark() async { snap(await sheet(at: DepartureRig.time(17, 14)), .dark) }
    @MainActor func testStripLight() { snap(strip, .light) }
    @MainActor func testStripDark() { snap(strip, .dark) }

    @MainActor
    private func sheet(at time: Date) async -> some View {
        TripDetailsView(viewModel: await DepartureRig.started(at: time).tripDetails())
    }

    /// Opened while the platform was pending, then posted at 5:03.
    @MainActor
    private func announced() async -> some View {
        let rig = DepartureRig.started()
        let model = await rig.tripDetails()
        rig.move(to: DepartureRig.time(17, 3), model)
        return TripDetailsView(viewModel: model)
    }

    /// The strip at 5:03 PM (Platform 7, on time, 10 min) under the top of the screen, on the canvas ground.
    @MainActor
    private var strip: some View {
        let rig = DepartureRig.started(at: DepartureRig.time(17, 3))
        let formatter = TimeFormatter(format: .twelveHour)
        return VStack {
            if let strip = rig.onBoard.demoDepartureStrip(formatter: formatter) {
                DepartureStripView(strip: strip)
                    .padding(.horizontal, TTSpace.s5)
            }
            Spacer()
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
    }

    @MainActor
    private func snap(_ content: some View, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = content
            .environment(\.timeFormatter, TimeFormatter(format: .twelveHour))
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

import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// On board against the canvas's Live-Ride, Live-Entry, Live-Permission and Live-Schedule boards (TT-172), light and dark:
/// the demo ride riding (5:32 PM), with your stop next (5:38), arriving (5:42) and stopped at Clarkson (5:43); Trip details
/// with "I'm on board"; the permission sheet; the ride strip. Glass is drawn as its solid fallback, and the motion is off
/// (rows settled, ripples still).
final class RideSnapshotTests: XCTestCase {
    @MainActor func testRidingLight() async throws { snap(await ride(at: DemoRideRig.time(17, 32)), .light) }
    @MainActor func testRidingDark() async throws { snap(await ride(at: DemoRideRig.time(17, 32)), .dark) }
    @MainActor func testYourStopNextLight() async throws { snap(await ride(at: DemoRideRig.time(17, 38)), .light) }
    @MainActor func testYourStopNextDark() async throws { snap(await ride(at: DemoRideRig.time(17, 38)), .dark) }
    @MainActor func testArrivingLight() async throws { snap(await ride(at: DemoRideRig.time(17, 42, 20)), .light) }
    @MainActor func testArrivingDark() async throws { snap(await ride(at: DemoRideRig.time(17, 42, 20)), .dark) }
    @MainActor func testStoppedLight() async throws { snap(await ride(at: DemoRideRig.time(17, 43, 5)), .light) }
    @MainActor func testStoppedDark() async throws { snap(await ride(at: DemoRideRig.time(17, 43, 5)), .dark) }
    @MainActor func testEntryLight() async throws { snap(TripDetailsView(viewModel: try await .onBoardFixture(hasAlert: true)), .light) }
    @MainActor func testEntryDark() async throws { snap(TripDetailsView(viewModel: try await .onBoardFixture(hasAlert: true)), .dark) }
    @MainActor func testPermissionLight() { snap(permission, .light) }
    @MainActor func testPermissionDark() { snap(permission, .dark) }
    @MainActor func testStripLight() async { snap(await strip(), .light) }
    @MainActor func testStripDark() async { snap(await strip(), .dark) }

    @MainActor
    private func ride(at time: Date) async -> some View {
        let rig = await DemoRideRig.started(at: time)
        return TripDetailsView(viewModel: rig.tripDetails())
    }

    /// The sheet over a dimmed Trip details, as it rises from the bottom.
    @MainActor
    private var permission: some View {
        ZStack(alignment: .bottom) {
            TTColor.canvas
            Color.black.opacity(0.2)
            RideIntroSheet(destination: "Clarkson")
                .frame(height: RideIntroSheet.height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: TTRadius.sheet, topTrailingRadius: TTRadius.sheet))
        }
        .ignoresSafeArea()
    }

    /// The strip at 5:32 PM under the top of the screen, on the canvas ground.
    @MainActor
    private func strip() async -> some View {
        let rig = await DemoRideRig.started()
        let formatter = TimeFormatter(format: .twelveHour)
        return VStack {
            if let strip = rig.onBoard.strip(formatter: formatter) {
                RideStripView(strip: strip)
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

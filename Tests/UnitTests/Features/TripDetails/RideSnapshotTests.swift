import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// On board against the canvas's Live-Ride-Lean (TT-204) and the Live view canvas's boards (TT-205, D93), light and dark:
/// the demo ride riding (5:32 PM), with your stop next (5:38), arriving (5:42) and stopped at Clarkson (5:43); Trip details
/// with "I'm on board" (the hero card over the folded trip); the location sheet; the one-line ride strip. Glass is drawn as its solid fallback, and the motion is off
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
    /// TT-223, D103: 5 s after Clarkson (30 s on the demo's clock) "Now" has rolled into the wish, "Enjoy your evening".
    @MainActor func testWishLight() async throws { snap(await wish(), .light) }
    @MainActor func testWishDark() async throws { snap(await wish(), .dark) }
    /// TT-232, D111 (Live view canvas, boards 36 and 38): the demo express, Union to Clarkson without stopping. At 5:29 PM
    /// past Long Branch, the bolt by the train and the four stations between as disabled rows; then stopped at Clarkson.
    @MainActor func testExpressRidingLight() async throws { snap(await express(at: DemoRideRig.time(17, 29)), .light) }
    @MainActor func testExpressRidingDark() async throws { snap(await express(at: DemoRideRig.time(17, 29)), .dark) }
    @MainActor func testExpressStoppedLight() async throws { snap(await express(at: DemoRideRig.time(17, 39, 5)), .light) }
    @MainActor func testExpressStoppedDark() async throws { snap(await express(at: DemoRideRig.time(17, 39, 5)), .dark) }
    /// TT-204: 5 min late, "5 min late" under the minutes and the times ahead in the delay ink.
    @MainActor func testLateLight() { snap(late, .light) }
    @MainActor func testLateDark() { snap(late, .dark) }
    @MainActor func testEntryLight() async throws { snap(TripDetailsView(viewModel: try await .onBoardFixture(hasAlert: true)), .light) }
    @MainActor func testEntryDark() async throws { snap(TripDetailsView(viewModel: try await .onBoardFixture(hasAlert: true)), .dark) }
    @MainActor func testPermissionLight() { snap(permission, .light) }
    @MainActor func testPermissionDark() { snap(permission, .dark) }
    /// Live-Always (TT-176, cut down by TT-205): "Detect my train next time?", after the first completed ride.
    @MainActor func testDetectOfferLight() { snap(detectOffer, .light) }
    @MainActor func testDetectOfferDark() { snap(detectOffer, .dark) }
    @MainActor func testStripLight() async { snap(await strip(), .light) }
    @MainActor func testStripDark() async { snap(await strip(), .dark) }

    @MainActor
    private func ride(at time: Date) async -> some View {
        let rig = await DemoRideRig.started(at: time)
        return TripDetailsView(viewModel: rig.tripDetails())
    }

    @MainActor
    private func express(at time: Date) async -> some View {
        let rig = await DemoRideRig.express(at: time)
        return TripDetailsView(viewModel: rig.tripDetails())
    }

    @MainActor
    private func wish() async -> some View {
        let rig = await DemoRideRig.started(at: DemoRideRig.time(17, 43, 30))
        rig.drive(to: DemoRideRig.time(17, 44, 10))
        return TripDetailsView(viewModel: rig.tripDetails())
    }

    /// The ride content alone, 5 min late at 5:32 PM, where the sheet puts it under its header.
    @MainActor
    private var late: some View {
        let plan = DemoRide.plan(on: DemoRideRig.day)
        let state = RideState(
            phase: .riding, currentStop: nil, nextStop: plan.stops[4].station, stopsLeft: 2, minutesToYourStop: 16,
            expectedArrival: DemoRideRig.time(17, 48), source: .trainFeed, lastUpdate: DemoRideRig.time(17, 31)
        )
        let ride = RideDetails(
            plan: plan, state: state, now: DemoRideRig.time(17, 32), formatter: TimeFormatter(format: .twelveHour)
        )
        return VStack {
            if let ride { RideContent(ride: ride) }
            Spacer()
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, 150)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
    }

    /// The sheet over a dimmed Trip details, as it rises from the bottom.
    @MainActor
    private var permission: some View {
        ZStack(alignment: .bottom) {
            TTColor.canvas
            Color.black.opacity(0.2)
            RideIntroSheet()
                .frame(height: RideIntroSheet.height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: TTRadius.sheet, topTrailingRadius: TTRadius.sheet))
        }
        .ignoresSafeArea()
    }

    /// The "Detect my train" offer over a dimmed screen, as it rises from the bottom.
    @MainActor
    private var detectOffer: some View {
        ZStack(alignment: .bottom) {
            TTColor.canvas
            Color.black.opacity(0.2)
            DetectOfferSheet()
                .frame(height: DetectOfferSheet.height)
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

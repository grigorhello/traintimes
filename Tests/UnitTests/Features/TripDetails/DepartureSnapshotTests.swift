import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Before departure against boards 2 and 4 of the Live view canvas (TT-205, D93), light and dark: the demo train's Trip
/// details with the hero card over the folded trip, pending (5:01 PM), with Platform 7 (5:03), 3 min late (5:07) and
/// boarding (5:14). Glass is drawn as its solid fallback, and the motion is off (the pill still).
final class DepartureSnapshotTests: XCTestCase {
    @MainActor func testPendingLight() async { snap(await sheet(at: DepartureRig.time(17, 1)), .light) }
    @MainActor func testPendingDark() async { snap(await sheet(at: DepartureRig.time(17, 1)), .dark) }
    @MainActor func testPlatformLight() async { snap(await announced(), .light) }
    @MainActor func testPlatformDark() async { snap(await announced(), .dark) }
    @MainActor func testDelayedLight() async { snap(await sheet(at: DepartureRig.time(17, 7)), .light) }
    @MainActor func testDelayedDark() async { snap(await sheet(at: DepartureRig.time(17, 7)), .dark) }
    @MainActor func testBoardingLight() async { snap(await sheet(at: DepartureRig.time(17, 14)), .light) }
    @MainActor func testBoardingDark() async { snap(await sheet(at: DepartureRig.time(17, 14)), .dark) }
    /// Union's paired platform in the hero (TT-245, D122): on time "12/13", and late and Express, the widest row.
    @MainActor func testUnionPairLight() throws { snap(try unionPairs(), .light) }
    @MainActor func testUnionPairDark() throws { snap(try unionPairs(), .dark) }

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

    /// The 5:13 PM train from Union with Platform 12/13, counting down 9 min before, on time and 3 min late on an express.
    @MainActor
    private func unionPairs() throws -> some View {
        let day = DepartureRig.day
        let scheduled = DepartureRig.time(17, 13)
        func hero(delay: Int, express: Bool) throws -> DepartureHero {
            let expected = scheduled.addingTimeInterval(TimeInterval(delay * 60))
            let train = Departure(
                trip: Trip(
                    key: TripKey(serviceDay: day, tripId: DemoRide.tripId), scheduledDeparture: scheduled,
                    scheduledArrival: scheduled.addingTimeInterval(30 * 60), platform: .published("12/13"),
                    tags: express ? [.express] : []
                ),
                status: delay > 0 ? .delayed(minutes: delay, reportedAt: scheduled) : .onTime,
                expectedDeparture: expected,
                expectedArrival: expected.addingTimeInterval(30 * 60)
            )
            return try XCTUnwrap(DepartureHero(
                train, now: expected.addingTimeInterval(-9 * 60), showsCountdown: true, pillPulses: false,
                formatter: TimeFormatter(format: .twelveHour)
            ))
        }
        let onTime = try hero(delay: 0, express: false)
        let late = try hero(delay: 3, express: true)
        return VStack(spacing: TTSpace.s4) {
            DepartureHeroCard(hero: onTime)
            DepartureHeroCard(hero: late)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.s5)
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

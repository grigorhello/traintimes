import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The On board Live Activity's one card (TT-205, D93) against the Live view canvas's boards 3, 12, 13 and 15, on a light and
/// a dark Lock Screen: the Lock Screen card riding (5:32 PM), your stop next (5:38), arriving (5:42) and stale; the island
/// compact, compact arriving, minimal, expanded riding, arriving and at your stop. The system draws the island's black
/// shape and the Lock Screen's rounded card; these mock-ups stand in for them, at Apple's sizes for a 402 pt iPhone
/// (compact trailing about 52 pt, the expanded island at most 160 pt tall and 374 pt wide, the camera's row about 40 pt),
/// so content that would be cut off is cut off here too. The countdown is stopped at the moment the content was made.
/// Before departure (TT-178): the Lock Screen card pending, late, boarding, departed and stale; the island compact and
/// expanded.
final class RideActivitySnapshotTests: XCTestCase {
    @MainActor func testLockScreenLight() async throws { snap(try await lockScreen(), .light) }
    @MainActor func testLockScreenDark() async throws { snap(try await lockScreen(), .dark) }
    @MainActor func testIslandLight() async throws { snap(try await island(), .light) }
    @MainActor func testIslandDark() async throws { snap(try await island(), .dark) }
    // Before departure (TT-178, *Live-Depart-Lock* and the island's before-departure cells).
    @MainActor func testDepartureLockScreenLight() throws { snap(try departureLockScreen(), .light) }
    @MainActor func testDepartureLockScreenDark() throws { snap(try departureLockScreen(), .dark) }
    @MainActor func testDepartureIslandLight() throws { snap(try departureIsland(), .light) }
    @MainActor func testDepartureIslandDark() throws { snap(try departureIsland(), .dark) }

    // On an express (TT-232, D111, the Live view canvas's board 40): the stations it passes hollow, the bolt above the train
    // and after the tile in the compact island. Riding at 5:22 and 5:29 PM, arriving at 5:38:20, at Clarkson at 5:39:05.
    @MainActor func testExpressLockScreenLight() async throws { snap(try await expressLockScreen(), .light) }
    @MainActor func testExpressLockScreenDark() async throws { snap(try await expressLockScreen(), .dark) }
    @MainActor func testExpressIslandLight() async throws { snap(try await expressIsland(), .light) }
    @MainActor func testExpressIslandDark() async throws { snap(try await expressIsland(), .dark) }

    private struct Moment {
        let attributes: RideActivityAttributes
        let state: RideActivityAttributes.ContentState
    }

    /// The device clock the content is made on; the snapshots stop the countdown here.
    private static let deviceNow = DemoRideRig.time(17, 32)

    @MainActor
    private func moment(_ time: Date, express: Bool = false) async throws -> Moment {
        let rig = express ? await DemoRideRig.express(at: time) : await DemoRideRig.started(at: time)
        let engine = try XCTUnwrap(rig.engine)
        let state = try XCTUnwrap(RideActivityAttributes.ContentState(
            plan: rig.plan, state: try XCTUnwrap(engine.state), now: engine.now, deviceNow: Self.deviceNow,
            formatter: TimeFormatter(format: .twelveHour)
        ))
        let attributes = RideActivityAttributes(ride: DemoRide.ride(on: DemoRideRig.day), plan: rig.plan, line: DemoRide.line)
        return Moment(attributes: attributes, state: state)
    }

    /// The demo departure at `time` (TT-177): platform pending at 5:01, Platform 7 and 3 min late at 5:05, Boarding now at
    /// 5:14:30, Departed at 5:16:30.
    @MainActor
    private func departure(_ time: Date) throws -> Moment {
        let day = DepartureRig.day
        let session = DemoDeparture.Session(day: day, clock: TestClock(now: time))
        let live = try XCTUnwrap(session.departure(at: time).flatMap { LiveDeparture($0, now: time) })
        let state = RideActivityAttributes.ContentState(
            departure: live, now: time, deviceNow: Self.deviceNow, formatter: TimeFormatter(format: .twelveHour)
        )
        let attributes = RideActivityAttributes(ride: DemoRide.ride(on: day), plan: DemoRide.plan(on: day), line: DemoRide.line)
        return Moment(attributes: attributes, state: state)
    }

    // MARK: Lock Screen

    @MainActor
    private func lockScreen() async throws -> some View {
        let riding = try await moment(DemoRideRig.time(17, 32))
        let next = try await moment(DemoRideRig.time(17, 38))
        let arriving = try await moment(DemoRideRig.time(17, 42, 20))
        return VStack(spacing: 14) {
            lockCard(riding, isStale: false)
            lockCard(next, isStale: false)
            lockCard(arriving, isStale: false)
            lockCard(riding, isStale: true)
            Spacer()
        }
        .padding(.top, 120)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wallpaper())
    }

    @MainActor
    private func expressLockScreen() async throws -> some View {
        let early = try await moment(DemoRideRig.time(17, 22), express: true)
        let riding = try await moment(DemoRideRig.time(17, 29), express: true)
        let arriving = try await moment(DemoRideRig.time(17, 38, 20), express: true)
        let there = try await moment(DemoRideRig.time(17, 39, 5), express: true)
        return VStack(spacing: 14) {
            lockCard(early, isStale: false)
            lockCard(riding, isStale: false)
            lockCard(arriving, isStale: false)
            lockCard(there, isStale: false)
            Spacer()
        }
        .padding(.top, 120)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wallpaper())
    }

    /// Before departure: pending, late, boarding, departed, and stale.
    @MainActor
    private func departureLockScreen() throws -> some View {
        let pending = try departure(DepartureRig.time(17, 1))
        let late = try departure(DepartureRig.time(17, 5))
        let boarding = try departure(DepartureRig.time(17, 14, 30))
        let departed = try departure(DepartureRig.time(17, 16, 30))
        return VStack(spacing: 14) {
            lockCard(pending, isStale: false)
            lockCard(late, isStale: false)
            lockCard(boarding, isStale: false)
            lockCard(departed, isStale: false)
            lockCard(late, isStale: true)
            Spacer()
        }
        .padding(.top, 120)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wallpaper())
    }

    /// The card as the Lock Screen draws an activity: its background tint behind it, rounded.
    @MainActor
    private func lockCard(_ moment: Moment, isStale: Bool) -> some View {
        RideActivityLockView(attributes: moment.attributes, state: moment.state, isStale: isStale)
            .background(RideActivityLockView.background(moment.state))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Dynamic Island

    @MainActor
    private func island() async throws -> some View {
        let riding = try await moment(DemoRideRig.time(17, 32))
        let arriving = try await moment(DemoRideRig.time(17, 42, 20))
        let there = try await moment(DemoRideRig.time(17, 43, 5))
        return VStack(spacing: 18) {
            compact(riding)
            compact(arriving)
            HStack(spacing: 8) {
                Capsule().fill(.black).frame(width: 126, height: 37)
                RideActivityTile(attributes: riding.attributes, size: .minimal)
                    .frame(width: 37, height: 37)
                    .background(.black, in: Circle())
            }
            expanded(riding)
            expanded(arriving)
            expanded(there)
            Spacer()
        }
        .padding(.top, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wallpaper())
    }

    @MainActor
    private func expressIsland() async throws -> some View {
        let riding = try await moment(DemoRideRig.time(17, 29), express: true)
        let arriving = try await moment(DemoRideRig.time(17, 38, 20), express: true)
        return VStack(spacing: 18) {
            compact(riding)
            compact(arriving)
            expanded(riding)
            expanded(arriving)
            Spacer()
        }
        .padding(.top, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wallpaper())
    }

    /// Before departure: compact pending and late, expanded pending, late and boarding.
    @MainActor
    private func departureIsland() throws -> some View {
        let pending = try departure(DepartureRig.time(17, 1))
        let late = try departure(DepartureRig.time(17, 5))
        let boarding = try departure(DepartureRig.time(17, 14, 30))
        return VStack(spacing: 18) {
            compact(pending)
            compact(late)
            expanded(pending)
            expanded(late)
            expanded(boarding)
            Spacer()
        }
        .padding(.top, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wallpaper())
    }

    /// The compact island: the tile (and an express ride's bolt) left of the camera, the minutes right of it.
    @MainActor
    private func compact(_ moment: Moment) -> some View {
        let style = RideActivityStyle.island(moment.state, isStale: false)
        return HStack(spacing: 0) {
            RideActivityCompactLeading(attributes: moment.attributes, state: moment.state, style: style)
            Spacer(minLength: 126)
            RideActivityCompactTrailing(state: moment.state, style: style)
                .frame(maxWidth: 52, alignment: .trailing)
            .clipped()
        }
        .padding(.horizontal, 8)
        .frame(height: 37)
        .fixedSize()
        .background(.black, in: Capsule())
    }

    /// The expanded island as the widget fills it: the card in the bottom region, under the camera's row.
    @MainActor
    private func expanded(_ moment: Moment) -> some View {
        RideActivityExpanded(attributes: moment.attributes, state: moment.state, style: .island(moment.state, isStale: false))
            .padding(.horizontal, 14)
            .padding(.top, 40)
            .padding(.bottom, 10)
            .expandedIsland()
    }

    /// A plain Lock Screen wallpaper, light or dark.
    private struct Wallpaper: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(white: 0.16), Color(white: 0.05)]
                    : [Color(red: 0.78, green: 0.86, blue: 0.95), Color(red: 0.93, green: 0.90, blue: 0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    @MainActor
    private func snap(_ content: some View, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = content.environment(\.rideActivityPausedAt, Self.deviceNow)
        let failure = verifySnapshot(
            of: view,
            as: .image(
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

private extension View {
    /// The expanded island's black shape, cut at its 160 pt maximum.
    func expandedIsland() -> some View {
        // Its own height up to 160 pt, the rest cut off.
        frame(maxHeight: 160, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .clipped()
            .background(.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
    }
}

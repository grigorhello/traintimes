import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The On board Live Activity against the canvas's Live-Lock and Live-Island boards (TT-174), on a light and a dark Lock
/// Screen: the Lock Screen card riding (5:32 PM), arriving (5:42) and stale; the island compact, compact arriving, minimal,
/// expanded, expanded arriving and expanded at your stop. The system draws the island's black shape and the Lock Screen's
/// rounded card; these mock-ups stand in for them, at Apple's sizes for a 402 pt iPhone (compact trailing about 52 pt, the
/// expanded island at most 160 pt tall, 374 pt wide, its centre region 166 pt wide, as measured on the simulator), so
/// content that would be cut off is cut off here too. The countdown is stopped at the moment the content was made. Before
/// departure (TT-178): the Lock Screen card pending, late, boarding, departed and stale; the island compact and expanded.
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

    private struct Moment {
        let attributes: RideActivityAttributes
        let state: RideActivityAttributes.ContentState
    }

    /// The device clock the content is made on; the snapshots stop the countdown here.
    private static let deviceNow = DemoRideRig.time(17, 32)

    @MainActor
    private func moment(_ time: Date) async throws -> Moment {
        let rig = await DemoRideRig.started(at: time)
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
            departure: live, origin: session.route.from.name, destination: session.route.to.name, hasPlatformSource: true,
            now: time, deviceNow: Self.deviceNow, formatter: TimeFormatter(format: .twelveHour)
        )
        let attributes = RideActivityAttributes(ride: DemoRide.ride(on: day), plan: DemoRide.plan(on: day), line: DemoRide.line)
        return Moment(attributes: attributes, state: state)
    }

    // MARK: Lock Screen

    @MainActor
    private func lockScreen() async throws -> some View {
        let riding = try await moment(DemoRideRig.time(17, 32))
        let arriving = try await moment(DemoRideRig.time(17, 42, 20))
        return VStack(spacing: 14) {
            lockCard(riding, isStale: false)
            lockCard(arriving, isStale: false)
            lockCard(riding, isStale: true)
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
            expandedAlert(arriving)
            expanded(there)
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
            expandedDeparture(pending)
            expandedDeparture(late)
            expandedDeparture(boarding)
            Spacer()
        }
        .padding(.top, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wallpaper())
    }

    /// The expanded island before departure as the widget fills it: tile, train and countdown, then the arrival and
    /// "I’m on board".
    @MainActor
    private func expandedDeparture(_ moment: Moment) -> some View {
        let style = RideActivityStyle.island(moment.state, isStale: false)
        return VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RideActivityTile(attributes: moment.attributes, size: .large, edge: style.tileEdge)
                RideActivityDepartureTitle(attributes: moment.attributes, state: moment.state, style: style)
                    .frame(width: 166, alignment: .leading)
                    .padding(.top, 28)
                Spacer(minLength: 0)
                RideActivityDepartureCountdown(state: moment.state, style: style)
            }
            RideActivityDepartureBottom(state: moment.state, style: style)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .expandedIsland()
    }

    /// The compact island: the tile left of the camera, the countdown (on green while arriving) right of it.
    @MainActor
    private func compact(_ moment: Moment) -> some View {
        let style = RideActivityStyle.island(moment.state, isStale: false)
        return HStack(spacing: 0) {
            RideActivityTile(attributes: moment.attributes, size: .compact)
            Spacer(minLength: 126)
            Group {
                if moment.state.isDeparture {
                    RideActivityDepartureCompactTrailing(state: moment.state, style: style)
                } else {
                    RideActivityCompactTrailing(state: moment.state, style: style)
                }
            }
            .frame(maxWidth: 52, alignment: .trailing)
            .clipped()
        }
        .padding(.horizontal, 8)
        .frame(height: 37)
        .fixedSize()
        .background(.black, in: Capsule())
    }

    /// The expanded island's regions as the widget fills them: tile, title and countdown around the camera, the bar under.
    @MainActor
    private func expanded(_ moment: Moment) -> some View {
        let style = RideActivityStyle.island(moment.state, isStale: false)
        return VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RideActivityTile(attributes: moment.attributes, size: .large, edge: style.tileEdge)
                // The centre region's width on the iPhone 17 Pro, under the camera between the two corners.
                RideActivityTitle(state: moment.state, style: style)
                    .frame(width: 166, alignment: .leading)
                    .padding(.top, 28)
                Spacer(minLength: 0)
                RideActivityCountdownStack(state: moment.state, style: style)
            }
            RideActivityExpandedBottom(attributes: moment.attributes, state: moment.state, style: style)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .expandedIsland()
    }

    /// Arriving: the green card in the bottom region, under the camera.
    @MainActor
    private func expandedAlert(_ moment: Moment) -> some View {
        RideActivityExpandedAlert(
            attributes: moment.attributes, state: moment.state, style: .island(moment.state, isStale: false)
        )
        .padding(.horizontal, 10)
        .padding(.top, 44)
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

import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Automatic direction's capsule on Schedule (TT-234, D116; boards 14 and 20 of the Route and stations canvas), above the
/// tab bar where a bell's capsule shows, light and dark: "Now from Union" with Undo over the turned route, Union to
/// Oakville, with the location arrow in the From ring's place (TT-235: board 14's last frame; Schedule is drawn at rest,
/// after the turn's motion); "Trains from Union?" with Switch over the route as it was; the line after Undo; and a
/// station name too long for the capsule's room, cut short so the words before it, the question mark and Switch still
/// show. The capsule's glass is off (`\.rendersGlass`), as in the other Schedule state snapshots.
final class DirectionCapsuleSnapshotTests: XCTestCase {
    @MainActor func testTurnedLight() async throws { try await snap(turned(), .turned(station: "Union"), .light) }
    @MainActor func testTurnedDark() async throws { try await snap(turned(), .turned(station: "Union"), .dark) }
    @MainActor func testAsksLight() async throws { try await snap(.loadedFixture(), .asks(station: "Union"), .light) }
    @MainActor func testAsksDark() async throws { try await snap(.loadedFixture(), .asks(station: "Union"), .dark) }
    @MainActor func testKeptLight() async throws { try await snap(.loadedFixture(), .kept, .light) }
    @MainActor func testKeptDark() async throws { try await snap(.loadedFixture(), .kept, .dark) }
    @MainActor func testLongNameLight() async throws { try await snap(longName(), .asks(station: Self.longShortName), .light) }
    @MainActor func testLongNameDark() async throws { try await snap(longName(), .asks(station: Self.longShortName), .dark) }

    /// The fixture list's longest station name, and what the capsule says of it ("Brampton Innovation District").
    private static let longStationName = "Brampton Innovation District GO"
    private static let longShortName = StationNames.short(longStationName)

    /// The app opened at Union and turned the route (`ScheduleViewModel.turn(_:while:)`): Union to Oakville, with trains
    /// and the arrow on From.
    @MainActor
    private func turned() async throws -> ScheduleViewModel {
        let fixtures = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let model = try await schedule(on: fixtures.route, fixtures: fixtures)
        await model.turn()
        return model
    }

    /// Union to Brampton Innovation District GO on the Kitchener line: the capsule asks about the To station.
    @MainActor
    private func longName() async throws -> ScheduleViewModel {
        let fixtures = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let route = Route(
            from: fixtures.route.to, to: Station(id: "BR", name: Self.longStationName),
            line: Line(id: "KI", name: "Kitchener", colorHex: nil)
        )
        return try await schedule(on: route, fixtures: fixtures)
    }

    /// `route` with the fixture day's trains and live status on the fixture clock, already loaded. The fixture repository
    /// itself only runs Oakville to Union.
    @MainActor
    private func schedule(on route: Route, fixtures: FixtureScheduleRepository) async throws -> ScheduleViewModel {
        let trips = try await fixtures.trips(for: fixtures.route, on: fixtures.serviceDay)
        let live = try await fixtures.liveStatus(for: fixtures.route, on: fixtures.serviceDay)
        let repository = StubScheduleRepository(tripList: trips, live: live, stopList: [])
        let model = ScheduleViewModel(route: route, repository: repository, clock: FixedClock(now: fixtures.now))
        await model.loadIfNeeded()
        return model
    }

    /// Schedule in the shell, as the other Schedule snapshots draw it, with `capsule` up. The look is the one `RootView`
    /// makes and hands to Schedule, which follows each route chosen (`ScheduleViewModel.choices`): `RootView` sets it on
    /// its tabs, so a look put in the environment from outside would never reach Schedule. The capsule goes up after the
    /// first layout and is held, as under a finger, so its time cannot run out before the picture; a capsule already up
    /// when the snapshot first draws stands at rest.
    @MainActor
    private func snap(
        _ schedule: ScheduleViewModel, _ capsule: DirectionCapsule.Kind, _ style: UIUserInterfaceStyle,
        testName: String = #function, line: UInt = #line
    ) throws {
        let view = RootView(schedule: schedule, settings: AppSettings(defaults: .ephemeral()))
            .environment(\.rendersGlass, false)
        layOutOnce(view)
        let look = try XCTUnwrap(schedule.choices as? DirectionLook, line: line)
        look.capsule.show(capsule)
        look.capsule.hold(true)
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                precision: glassSnapshotPrecision,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ).comparedAsRecorded,
            testName: testName,
            line: line
        )
    }
}

import Foundation
import UIKit

/// What the Schedule tab and the route form read: GO Transit's GTFS feed, its GTFS-realtime TripUpdates and Alerts feeds
/// and train positions through the alert server (D88), and the device clock in the app (TT-130, TT-131, TT-132, TT-179);
/// the fixture repository and clock from `Fixtures.json` in previews and tests (D20).
struct ScheduleDependencies {
    let repository: any ScheduleRepository
    let stations: any StationRepository
    let clock: any AppClock
    /// On board's trips and tracks (TT-171): the GO feed in the app; none in fixture runs, so no ride starts or restores.
    var rides: (any RideDataProviding)?
    /// Where GO's train feed places each train (TT-179): the alert server's `/v1/trains` in the app; none in fixture runs.
    var trains: (any TrainPositionProviding)?
    /// The widget file's schedule and stations (TT-182, D107): the GO feed as it is, never wrapped by `withTesting()`, so Demo
    /// trains and Mock time never reach the widgets; none in fixture runs, which write no widget file.
    var widgetData: (any ScheduleRepository & StationRepository)?
    /// The trains leaving the rider's station close to an alerted one (TT-242, D120): the GO feed in the app; none in fixture
    /// runs.
    var rivals: (any RivalTrainsProviding)?

    /// The app's schedule. Debug builds keep the fixtures for Xcode previews, the unit test host and UI tests, which set
    /// `TT_FIXTURES` in the launch environment so they never download the feed; `TT_FIXTURES=delayed` picks that fixture
    /// scenario.
    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> ScheduleDependencies {
        #if DEBUG
        if isFixtureRun(environment) {
            let scenario = environment["TT_FIXTURES"].flatMap { FixtureScheduleRepository.Scenario(rawValue: $0) } ?? .normal
            return fixtures(scenario: scenario).withTesting()
        }
        #endif
        let repository = GTFSScheduleRepository(
            store: .shared,
            live: GTFSRealtimeStore.relay(),
            alerts: GTFSRealtimeStore.relay(url: GTFSRealtimeStore.alertsURL),
            platforms: PlatformStore.relay(),
            trains: RelayTrainPositions.shared
        )
        let live = ScheduleDependencies(
            repository: repository, stations: repository, clock: SystemClock(), rides: repository,
            trains: RelayTrainPositions.shared, widgetData: repository, rivals: repository
        )
        return BuildChannel.showsTesting ? live.withTesting() : live
    }

    /// The same schedule with Settings › Testing applied, in TestFlight and Debug builds only: Demo trains (D49) and Mock
    /// time (TT-158, D51). With both off it changes nothing. Every screen reads the returned clock, so Mock time reaches
    /// Schedule, Trip details and Alerts alike.
    func withTesting() -> ScheduleDependencies {
        let mocked = MockTimeClock(base: clock)
        return ScheduleDependencies(
            repository: DemoScheduleRepository(
                base: repository, clock: mocked, mode: { DemoTrains.stored }, isMockTime: { MockTime.stored != nil },
                mockLive: { MockLive.stored }
            ),
            stations: stations,
            clock: mocked,
            rides: rides,
            trains: trains,
            widgetData: widgetData,
            rivals: rivals
        )
    }

    /// Xcode previews, the unit test host and UI tests run on the fixtures (Debug builds only).
    static func isFixtureRun(_ environment: [String: String]) -> Bool {
        ["TT_FIXTURES", "XCTestConfigurationFilePath", "XCODE_RUNNING_FOR_PREVIEWS"].contains { environment[$0] != nil }
    }

    /// `Fixtures.json` ships in Debug builds and the unit test bundle only, so Release gets an empty schedule here.
    static func fixtures(scenario: FixtureScheduleRepository.Scenario = .normal, bundle: Bundle = .main) -> ScheduleDependencies {
        guard let repository = try? FixtureScheduleRepository(scenario: scenario, bundle: bundle) else {
            return ScheduleDependencies(repository: NoScheduleRepository(), stations: NoScheduleRepository(), clock: SystemClock())
        }
        return ScheduleDependencies(repository: repository, stations: repository, clock: FixedClock(now: repository.now))
    }
}

extension RideEngine {
    /// The app's one ride engine (TT-171): the GO feed's trips and tracks, the phone's location and the schedule's clock, so
    /// Mock time reaches rides too. Fixture runs keep no ride on device. `location` is `AppDelegate.location`, which the
    /// automatic ride's watch shares (TT-242, D120), so a ride it starts keeps the watch's location session.
    static func app(
        location: any LocationProviding, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RideEngine {
        let dependencies = ScheduleDependencies.app(environment: environment)
        return RideEngine(
            data: dependencies.rides,
            location: location,
            trains: dependencies.trains,
            clock: dependencies.clock,
            defaults: dependencies.rides == nil ? nil : .standard
        )
    }
}

extension AutoRideWatch {
    /// The app's automatic ride watch (TT-242, D120): the alerted train's live status from the GO feed as it is (never the
    /// Demo or Mock time wrapper), GO's train positions, the other trains leaving the station, the shared location provider,
    /// the Live Activity for the hold, and the device clock. None in fixture runs, previews and the unit test host.
    static func app(
        ride: RideEngine, location: any LocationProviding, liveActivity: RideLiveActivity?, nudge: ArrivalNudge,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AutoRideWatch? {
        let dependencies = ScheduleDependencies.app(environment: environment)
        guard let data = dependencies.widgetData, let trains = dependencies.trains else { return nil }
        return AutoRideWatch(
            ride: ride,
            location: location,
            // A watch armed with the app closed reads GPS that keeps going in the background (TT-243).
            closedLocation: BackgroundFixes(),
            departures: ScheduleDepartureReading(repository: data),
            positions: trains,
            rivals: dependencies.rivals ?? NoRivalTrains(),
            holding: liveActivity,
            clock: SystemClock(),
            store: AutoRideStore(defaults: .standard),
            replan: { nudge.replan() },
            isDeclined: { DepartureQuestion.isDeclined($0, in: .standard) },
            isTesting: {
                MockTime.stored != nil || DemoTrains.stored == .ride || DemoTrains.stored == .departure
            },
            isActive: { UIApplication.shared.applicationState == .active }
        )
    }
}

extension AutoRideWake {
    /// "When the app is closed" in the app (TT-243, D120): significant-change wake-ups, today's alerted trains from the
    /// stored rules and the GO feed as it is (never the Demo or Mock time wrapper), the device clock. None in fixture runs,
    /// previews and the unit test host, where there is no watch.
    static func app(
        watch: AutoRideWatch?, ride: RideEngine, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AutoRideWake? {
        let dependencies = ScheduleDependencies.app(environment: environment)
        guard let watch, let data = dependencies.widgetData else { return nil }
        let departures = ScheduleDepartureReading(repository: data)
        return AutoRideWake(
            location: SystemWakeLocation(),
            watch: watch,
            store: AutoRideStore(defaults: .standard),
            clock: SystemClock(),
            trains: { now in
                await alertedTrains(
                    rules: AlertRules.stored(in: .standard), repository: data, departures: departures,
                    plans: { await ride.plan(for: $0) }, at: now
                )
            },
            isInForeground: { UIApplication.shared.applicationState != .background }
        )
    }
}

extension ArrivalNudge {
    /// The demo ride's nudge (TT-173), on its 6x clock. None in fixture runs (UI tests, previews), so a demo ride in a UI
    /// test leaves no notification to go off over a later test.
    static func demo(environment: [String: String] = ProcessInfo.processInfo.environment) -> ArrivalNudge? {
        ScheduleDependencies.isFixtureRun(environment) ? nil : ArrivalNudge.system(rate: DemoRide.speed)
    }
}

extension ScheduleViewModel {
    /// Previews: the canvas route on the canvas clock (Thu Nov 5, 7:21 AM) from `Fixtures.json`.
    static func fixtures(scenario: FixtureScheduleRepository.Scenario = .normal, bundle: Bundle = .main) -> ScheduleViewModel {
        guard let repository = try? FixtureScheduleRepository(scenario: scenario, bundle: bundle) else {
            return ScheduleViewModel(route: nil, repository: NoScheduleRepository(), clock: SystemClock())
        }
        return ScheduleViewModel(route: repository.route, repository: repository, clock: FixedClock(now: repository.now))
    }
}

/// Stands in where `Fixtures.json` is missing.
private struct NoScheduleRepository: ScheduleRepository, StationRepository {
    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { [] }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    func stations() async throws -> [Station] { [] }
    func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: nil) }
}

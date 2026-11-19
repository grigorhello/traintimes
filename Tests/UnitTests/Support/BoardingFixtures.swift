import Foundation
@testable import TrainTimes

private final class BundleToken {}

/// A repository whose live status a test replaces between polls (TT-233, D114).
actor BoardingScheduleRepository: ScheduleRepository {
    private let tripList: [Trip]
    private var live: LiveSnapshot

    init(trips: [Trip], live: LiveSnapshot) {
        tripList = trips
        self.live = live
    }

    /// What the next poll fetches.
    func set(_ live: LiveSnapshot) {
        self.live = live
    }

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { tripList }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { live }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
}

/// Boarding test values (TT-233, D114) on the fixture route, Oakville to Union on Thu Nov 5.
enum BoardingFixtures {
    /// The 7:32 AM train, which has Platform 2 in the timetable fixture.
    static let firstTripId = "LW-0732-20261105"
    /// The 7:58 AM express train, with no platform until GO posts one.
    static let expressTripId = "LW-0758-20261105"

    /// The fixture's live status as if fetched at `now`, with where GO's train feed placed trains 10 s before (`metres`
    /// from Oakville, by trip id), the platforms GO posts and the trips whose update has dropped Oakville (`left`).
    static func live(
        at now: Date, metres: [String: Double] = [:], platforms: [String: String] = [:], left: Set<String> = []
    ) async throws -> LiveSnapshot {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        var live = try await fixture.liveStatus(for: fixture.route, on: fixture.serviceDay)
        live.updatedAt = now
        live.platforms = platforms
        live.originFixes = metres.mapValues { OriginFix(metres: $0, reportedAt: now.addingTimeInterval(-10)) }
        live.leftOrigin = left
        return live
    }
}

extension ScheduleViewModel {
    /// Board 3 of the Boarding boards (TT-233, D114): the fixture route at 7:51 AM with fresh live data, already loaded.
    /// The 7:32 AM train has left; the 7:58 AM express stands at Oakville with Platform 7 posted, so it is Boarding and
    /// the next train, "in 7 min"; two later trains follow.
    @MainActor
    static func boardingFixture() async throws -> ScheduleViewModel {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let now = fixture.serviceDay.date(hour: 7, minute: 51)
        let express = BoardingFixtures.expressTripId
        let live = try await BoardingFixtures.live(at: now, metres: [express: 120], platforms: [express: "7"])
        let repository = StubScheduleRepository(
            tripList: try await fixture.trips(for: fixture.route, on: fixture.serviceDay), live: live, stopList: []
        )
        let model = ScheduleViewModel(route: fixture.route, repository: repository, clock: FixedClock(now: now))
        await model.loadIfNeeded()
        return model
    }
}

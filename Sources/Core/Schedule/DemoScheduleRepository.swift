import Foundation

/// Settings › Testing › Demo trains (D49), in TestFlight builds: made-up live status on the real timetable, so delays,
/// cancellations and offline can be checked without waiting for a real disruption. It wraps the real repository and only
/// changes live status and line notices; with the setting off everything passes through.
struct DemoScheduleRepository: ScheduleRepository {
    let base: any ScheduleRepository
    let clock: any AppClock
    /// The setting, read on each call so a change applies at the next refresh.
    let mode: @Sendable () -> DemoTrains
    /// Mock time is on (TT-158): the real live status belongs to the real clock, so with Demo trains off there is none.
    var isMockTime: @Sendable () -> Bool = { false }

    /// The next train is this late, in minutes; its estimated arrival moves with it.
    static let delayMinutes = 9
    /// How long ago the pretend last update was, when offline.
    static let offlineLastUpdated: TimeInterval = 20 * 60

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        try await base.trips(for: route, on: day)
    }

    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot {
        let mode = mode()
        let now = clock.now
        switch mode {
        case .off:
            return isMockTime() ? .empty : try await base.liveStatus(for: route, on: day)
        case .offline:
            return LiveSnapshot(updatedAt: now.addingTimeInterval(-Self.offlineLastUpdated), isOffline: true)
        case .delays:
            let trips = try await base.trips(for: route, on: day).sorted { $0.scheduledDeparture < $1.scheduledDeparture }
            // The next train still to leave is late and the one after it is cancelled; the rest run on time. A late train
            // has not left until its late time, so it stays the late one until then.
            let delay = TimeInterval(Self.delayMinutes * 60)
            let upcoming = trips.filter { $0.scheduledDeparture.addingTimeInterval(delay) >= now }
            var updates: [String: LiveTripUpdate] = [:]
            for trip in trips {
                updates[trip.key.tripId] = LiveTripUpdate(expectedDeparture: trip.scheduledDeparture, reportedAt: now)
            }
            if let next = upcoming.first {
                updates[next.key.tripId] = LiveTripUpdate(
                    expectedDeparture: next.scheduledDeparture.addingTimeInterval(delay),
                    expectedArrival: next.scheduledArrival.addingTimeInterval(delay),
                    delayMinutes: Self.delayMinutes,
                    reportedAt: now
                )
            }
            if upcoming.count > 1 {
                updates[upcoming[1].key.tripId] = LiveTripUpdate(isCancelled: true, reportedAt: now)
            }
            return LiveSnapshot(updatedAt: now, updates: updates)
        }
    }

    func lineNotices(for line: Line) async throws -> [LineNotice] {
        guard mode() == .delays else { return try await base.lineNotices(for: line) }
        let now = clock.now
        // A new id each hour, so a dismissed demo notice comes back for the next test.
        let hour = Int(now.timeIntervalSince1970 / 3600)
        return [
            LineNotice(
                id: "demo-\(line.id)-\(hour)", lineName: line.name, text: "Delays of up to 15 min near Port Credit", reportedAt: now
            )
        ]
    }

    func stops(for trip: TripKey, on route: Route) async throws -> [TripStop] {
        try await base.stops(for: trip, on: route)
    }

    func lastServiceDay() async throws -> ServiceDay? {
        try await base.lastServiceDay()
    }
}

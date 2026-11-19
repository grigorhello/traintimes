import Foundation

/// Settings › Testing › Live data (TT-195, D75), for TestFlight and Debug builds: a made-up live feed on the real timetable,
/// so the live states can be checked on a phone before the Metrolinx key arrives. It goes through the same path as the real
/// feed (`DemoScheduleRepository`), so Schedule, Trip details and the countdown strip read it like live data. Raw values
/// are what the setting stores on device (`-settings.mockLive mixed` in a launch argument).
enum MockLive: String, CaseIterable, Sendable {
    /// The real feed.
    case off
    /// Every train live and on time, data fresh.
    case onTime
    /// One of every state on the next trains: late 4 min, cancelled, on time, late 22 min, skips your stop; platforms posted
    /// on every train and a line notice.
    case mixed
    /// The next train's delay changes each minute (on time, 3, 6, 9 min, then over), so updates can be watched arriving.
    case changing
    /// The next train late, reported 8 min ago: past the 3 min threshold, so cards fall back to Scheduled.
    case stale
    /// Boarding at the platform (TT-233, D114): every train live and on time with its platform posted, and the next train
    /// stands at its platform, so it reads Boarding at once and "Departing" for 1 min past its time; then it has moved off
    /// and the train after it boards (`BoardingRule`).
    case boarding

    static let key = "settings.mockLive"

    /// The stored choice, read from the standard defaults, so the schedule can read it from any thread.
    static var stored: MockLive {
        UserDefaults.standard.string(forKey: key).flatMap(MockLive.init(rawValue:)) ?? .off
    }
}

/// The made-up feeds behind `MockLive`, worked out from the timetable and the clock on each call.
enum MockLiveFeed {
    /// Mixed: what the next trains get, in order; later trains run on time.
    enum Step: Equatable {
        case late(Int)
        case cancelled
        case onTime
        case skipsStop
    }

    static let mixedSteps: [Step] = [.late(4), .cancelled, .onTime, .late(22), .skipsStop]
    /// Changing: the next train's delay in minutes, one value per minute of the clock.
    static let changingDelays = [0, 3, 6, 9]
    /// Stale: how long ago the data was reported, and the next train's delay in it.
    static let staleAge: TimeInterval = 8 * 60
    static let staleDelayMinutes = 5
    /// Board (TT-233, D114): the next train stands this far from the station (inside `BoardingRule.radius`) until this long
    /// past its time.
    static let boardingMetres: Double = 120
    static let boardingHold: TimeInterval = 60
    /// Board: a train that has moved off is placed this far away (outside the radius) for this long; after that nothing
    /// is said about it, which is the clock.
    static let movedMetres: Double = 900
    static let movedFor: TimeInterval = 10 * 60

    /// The live snapshot for `mode` (never `.off`) on `trips` at `now`.
    static func snapshot(_ mode: MockLive, trips: [Trip], now: Date) -> LiveSnapshot {
        let trips = trips.sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        let reportedAt = mode == .stale ? now.addingTimeInterval(-staleAge) : now
        var updates: [String: LiveTripUpdate] = [:]
        for trip in trips { updates[trip.key.tripId] = onTime(trip, at: reportedAt) }
        // Where the train feed places trains against the route's origin: Board's only.
        var fixes: [String: OriginFix] = [:]

        switch mode {
        case .off, .onTime:
            break
        case .mixed:
            // A late train has not left until its late time, so the first one stays "next" until then.
            let firstDelay = TimeInterval(4 * 60)
            let upcoming = trips.filter { $0.scheduledDeparture.addingTimeInterval(firstDelay) >= now }
            for (trip, step) in zip(upcoming, mixedSteps) {
                switch step {
                case .late(let minutes): updates[trip.key.tripId] = late(trip, minutes: minutes, at: now)
                case .cancelled: updates[trip.key.tripId] = LiveTripUpdate(isCancelled: true, reportedAt: now)
                case .onTime: break
                case .skipsStop: updates[trip.key.tripId] = LiveTripUpdate(isStopSkipped: true, reportedAt: now)
                }
            }
        case .changing:
            let minutes = changingDelays[Int(now.timeIntervalSince1970 / 60) % changingDelays.count]
            let delay = TimeInterval(minutes * 60)
            if let next = trips.first(where: { $0.scheduledDeparture.addingTimeInterval(delay) >= now }) {
                updates[next.key.tripId] = late(next, minutes: minutes, at: now)
            }
        case .stale:
            let delay = TimeInterval(staleDelayMinutes * 60)
            if let next = trips.first(where: { $0.scheduledDeparture.addingTimeInterval(delay) >= now }) {
                updates[next.key.tripId] = late(next, minutes: staleDelayMinutes, at: reportedAt)
            }
        case .boarding:
            // A train's minute at the platform past its time is over: it has moved off, and is placed away from the
            // station for 10 min. Earlier trains get no position, so they follow the clock.
            for trip in trips {
                let movedAt = trip.scheduledDeparture.addingTimeInterval(boardingHold)
                if movedAt <= now, now.timeIntervalSince(movedAt) <= movedFor {
                    fixes[trip.key.tripId] = OriginFix(metres: movedMetres, reportedAt: now)
                }
            }
            // The next train is the first one still there: it stands at its platform, however far off its time is.
            if let next = trips.first(where: { $0.scheduledDeparture.addingTimeInterval(boardingHold) > now }) {
                fixes[next.key.tripId] = OriginFix(metres: boardingMetres, reportedAt: now)
            }
        }
        return LiveSnapshot(updatedAt: reportedAt, updates: updates, originFixes: fixes)
    }

    /// Mixed and Board post a platform on every train, from 3 to 6 in turn (a train boards only with its platform posted).
    static func withPlatforms(_ trips: [Trip]) -> [Trip] {
        trips.sorted { $0.scheduledDeparture < $1.scheduledDeparture }.enumerated().map { index, trip in
            var trip = trip
            trip.platform = .published(String(3 + index % 4))
            return trip
        }
    }

    /// Trip details' stops with the update's delay on each, so the stop list reads "Expected" like a live trip.
    static func stops(_ stops: [TripStop], trip: TripKey, live: LiveSnapshot) -> [TripStop] {
        guard let update = live.updates[trip.tripId], !update.isCancelled, !update.isStopSkipped else { return stops }
        let delay = TimeInterval((update.delayMinutes ?? 0) * 60)
        return stops.map { stop in
            var stop = stop
            stop.expected = stop.scheduled.addingTimeInterval(delay)
            return stop
        }
    }

    private static func onTime(_ trip: Trip, at reportedAt: Date) -> LiveTripUpdate {
        LiveTripUpdate(expectedDeparture: trip.scheduledDeparture, expectedArrival: trip.scheduledArrival, reportedAt: reportedAt)
    }

    private static func late(_ trip: Trip, minutes: Int, at reportedAt: Date) -> LiveTripUpdate {
        let delay = TimeInterval(minutes * 60)
        return LiveTripUpdate(
            expectedDeparture: trip.scheduledDeparture.addingTimeInterval(delay),
            expectedArrival: trip.scheduledArrival.addingTimeInterval(delay),
            delayMinutes: minutes,
            reportedAt: reportedAt
        )
    }
}

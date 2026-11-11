import Foundation

/// Settings › Testing › Demo trains › Departure (TT-177, D69): the before-departure window of the demo ride's train, the
/// 5:13 PM Lakeshore West train from Union to Clarkson, with an alert on it, played from 5:01 PM on a clock of its own, ten
/// times as fast and over again, so every moment can be checked on the simulator with no train and no alert: platform
/// pending (12 min to go), Platform 7 posted at 5:03, 3 min late from 5:04 (5:16 PM), Boarding now from 5:14, Departed at
/// 5:16, and the window ends at 5:18. Its strip and Trip details take the place of a real live departure; "I’m on board"
/// hands over into the demo ride from the demo's time. The timetable is left alone and nothing is kept on device.
enum DemoDeparture {
    /// Seconds into the service day, as GTFS counts them.
    static let startSeconds = 17 * 3600 + 1 * 60
    static let platformSeconds = 17 * 3600 + 3 * 60
    static let delaySeconds = 17 * 3600 + 4 * 60
    /// Two minutes after the late departure: the window ends and the demo starts again from 5:01 PM.
    static let endSeconds = 17 * 3600 + 18 * 60
    static let departureSeconds = 17 * 3600 + 13 * 60
    static let arrivalSeconds = 17 * 3600 + 43 * 60
    static let delayMinutes = 3
    static let platform = "7"
    /// The demo clock runs this many times as fast as the real one: the 17 minutes take under 2.
    static let speed = 10.0

    /// One play of the demo on `day`, read against `clock`.
    struct Session: Sendable {
        let day: ServiceDay
        let clock: any AppClock

        var key: TripKey { TripKey(serviceDay: day, tripId: DemoRide.tripId) }
        var route: Route { DemoRide.route }
        var now: Date { clock.now }

        /// The demo train at `now`: its platform once posted.
        func trip(at now: Date) -> Trip {
            Trip(
                key: key,
                scheduledDeparture: day.gtfsTime(DemoDeparture.departureSeconds),
                scheduledArrival: day.gtfsTime(DemoDeparture.arrivalSeconds),
                platform: now >= day.gtfsTime(DemoDeparture.platformSeconds) ? .published(DemoDeparture.platform) : .pending,
                tags: []
            )
        }

        /// Fresh live data from a feed that posts platforms: on time, then 3 min late.
        func live(at now: Date) -> LiveSnapshot {
            let delay = delay(at: now)
            let update = LiveTripUpdate(
                expectedDeparture: day.gtfsTime(DemoDeparture.departureSeconds).addingTimeInterval(delay),
                expectedArrival: day.gtfsTime(DemoDeparture.arrivalSeconds).addingTimeInterval(delay),
                delayMinutes: Int(delay / 60),
                reportedAt: now
            )
            return LiveSnapshot(updatedAt: now, hasPlatformSource: true, updates: [DemoRide.tripId: update])
        }

        /// The demo ride's six stops; expected times once the train runs late.
        func stops(at now: Date) -> [TripStop] {
            let delay = delay(at: now)
            return DemoRide.plan(on: day).stops.enumerated().map { index, stop in
                let scheduled = index == 0 ? stop.departure : stop.arrival
                return TripStop(station: stop.station, scheduled: scheduled, expected: delay > 0 ? scheduled.addingTimeInterval(delay) : nil)
            }
        }

        /// The demo train resolved at `now`, as the timeline would resolve it.
        func departure(at now: Date) -> Departure? {
            let live = live(at: now)
            return Departure.resolve([trip(at: now)], live: live, freshness: Freshness(live, now: now), isToday: true).first
        }

        private func delay(at now: Date) -> TimeInterval {
            now >= day.gtfsTime(DemoDeparture.delaySeconds) ? TimeInterval(DemoDeparture.delayMinutes * 60) : 0
        }
    }

    /// The demo as Settings › Testing plays it: today, from 5:01 PM, ten times as fast, over again.
    static func session(startingAt realStart: Date = Date()) -> Session {
        let day = ServiceDay(calendarDayContaining: realStart)
        return Session(day: day, clock: DemoDepartureClock(day: day, realStart: realStart))
    }
}

/// The demo departure's clock: 5:01 PM when the demo starts, running ten times as fast, back to 5:01 PM after 5:18 PM.
struct DemoDepartureClock: AppClock {
    let day: ServiceDay
    let realStart: Date

    var now: Date {
        let loop = TimeInterval(DemoDeparture.endSeconds - DemoDeparture.startSeconds)
        let elapsed = max(0, Date().timeIntervalSince(realStart)) * DemoDeparture.speed
        return day.gtfsTime(DemoDeparture.startSeconds).addingTimeInterval(elapsed.truncatingRemainder(dividingBy: loop))
    }
}

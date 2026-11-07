import Foundation

extension GTFSRealtimeFeed {
    /// The trip updates for one service day, by trip id (D9). An update dated another day is left out.
    func tripUpdates(on day: ServiceDay) -> [String: TripUpdate] {
        let date = String(day.dateKey)
        var updates: [String: TripUpdate] = [:]
        for update in tripUpdates where update.startDate.map({ $0 == date }) ?? true {
            updates[update.tripId] = update
        }
        return updates
    }
}

extension GTFSRealtimeFeed.TripUpdate {
    /// What the feed says about one direct trip between the route's stations (TT-131, D36). Nil when it gives no
    /// estimate for the departure from the route's origin, so the trip stays Scheduled: a trip in the feed with no
    /// applicable estimate is missing live data and never On time (D12, D13).
    ///
    /// - Cancelled: the trip is CANCELED or DELETED.
    /// - Stop skipped: the origin or the destination is SKIPPED.
    /// - Departure: the origin's own departure, else its arrival; else the delay of the nearest earlier stop with an
    ///   estimate, which carries on down the line as GTFS-realtime defines; else the trip-wide delay. NO_DATA at the
    ///   origin, or at that earlier stop, means no estimate.
    /// - Arrival: only the destination's own arrival estimate (Q3, D15); a delay carried from earlier stops is not one.
    func live(on call: GTFSTimetable.Call, feedTime: Date) -> LiveTripUpdate? {
        let reportedAt = timestamp ?? feedTime
        if isCancelled { return LiveTripUpdate(isCancelled: true, reportedAt: reportedAt) }

        let positioned = stopTimeUpdates.compactMap { update in
            update.stopId.flatMap { call.stops.firstIndex(of: $0) }.map { (position: $0, update: update) }
        }
        let origin = positioned.last { $0.position == call.from }?.update
        let destination = positioned.last { $0.position == call.to }?.update
        if origin?.relationship == .skipped || destination?.relationship == .skipped {
            return LiveTripUpdate(isStopSkipped: true, reportedAt: reportedAt)
        }

        let scheduledDeparture = call.departures[call.from]
        let departureDelay: TimeInterval?
        if let origin {
            departureDelay = origin.lateness(scheduledArrival: call.arrivals[call.from], scheduledDeparture: scheduledDeparture)
        } else if let earlier = positioned.last(where: { $0.position < call.from && $0.update.relationship != .skipped }) {
            departureDelay = earlier.update.lateness(
                scheduledArrival: call.arrivals[earlier.position], scheduledDeparture: call.departures[earlier.position]
            )
        } else {
            departureDelay = delay.map { TimeInterval($0) }
        }
        guard let departureDelay else { return nil }

        let scheduledArrival = call.arrivals[call.to]
        let expectedArrival = destination.flatMap { stop -> Date? in
            guard stop.relationship == .scheduled, let arrival = stop.arrival else { return nil }
            return arrival.time ?? arrival.delay.map { scheduledArrival.addingTimeInterval(TimeInterval($0)) }
        }
        return LiveTripUpdate(
            expectedDeparture: scheduledDeparture.addingTimeInterval(departureDelay),
            expectedArrival: expectedArrival,
            delayMinutes: Int(departureDelay / 60),
            reportedAt: reportedAt
        )
    }

    /// Trip details' stop list with the feed's own estimate and skipped flag at each stop (D32). A stop the feed says
    /// nothing about keeps its scheduled time only.
    func applied(to stops: [TripStop]) -> [TripStop] {
        guard !isCancelled else { return stops }
        return stops.enumerated().map { index, scheduledStop in
            guard let update = stopTimeUpdates.last(where: { $0.stopId == scheduledStop.station.id }) else { return scheduledStop }
            var stop = scheduledStop
            switch update.relationship {
            case .skipped:
                stop.isSkipped = true
            case .scheduled:
                // The origin's time is its departure, every later stop's its arrival.
                let scheduled = stop.scheduled
                let events = index == 0 ? [update.departure, update.arrival] : [update.arrival, update.departure]
                stop.expected = events.compactMap { $0 }.compactMap { event in
                    event.time ?? event.delay.map { scheduled.addingTimeInterval(TimeInterval($0)) }
                }.first
            case .noData:
                break
            }
            return stop
        }
    }
}

private extension GTFSRealtimeFeed.StopTimeUpdate {
    /// Seconds late at this stop: the departure's time or delay, else the arrival's. Nil for NO_DATA, or with no times.
    func lateness(scheduledArrival: Date, scheduledDeparture: Date) -> TimeInterval? {
        guard relationship == .scheduled else { return nil }
        return departure?.lateness(against: scheduledDeparture) ?? arrival?.lateness(against: scheduledArrival)
    }
}

private extension GTFSRealtimeFeed.Event {
    /// Seconds late against a scheduled time: from the estimated time, else the reported delay.
    func lateness(against scheduled: Date) -> TimeInterval? {
        if let time { return time.timeIntervalSince(scheduled) }
        return delay.map { TimeInterval($0) }
    }
}

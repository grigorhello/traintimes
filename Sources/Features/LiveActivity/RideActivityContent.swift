import Foundation

// The ride as its Live Activity shows it (TT-174, D67, *Live-Lock*, *Live-Island*): the engine's state turned into the
// activity's attributes and content state, every word and time formatted here by the one formatter (D17).

extension RideActivityAttributes {
    /// The activity's fixed part for `ride`: which ride, the line's tile, your stop and how many stops the bar has.
    init(ride: Ride, plan: RidePlan, line: Line?) {
        tripId = ride.tripId
        serviceDate = ride.serviceDate
        originId = ride.originId
        destinationId = ride.destinationId
        lineCode = line?.id ?? "GO"
        lineColorHex = line.flatMap { GOLineColor.hex[$0.id] ?? $0.colorHex }
        destinationName = RideDetails.shortName(plan.stops[plan.stops.count - 1].station.name)
        stopCount = plan.stops.count
    }

    func shows(_ ride: Ride?) -> Bool {
        guard let ride else { return false }
        return shows(tripId: ride.tripId, serviceDate: ride.serviceDate, originId: ride.originId, destinationId: ride.destinationId)
    }
}

extension RideActivityAttributes.ContentState {
    /// The activity at `now` on the engine's clock (Mock time, or the demo ride's own clock), in the ride screen's words
    /// (`RideDetails`, TT-205): "Clarkson in" over the minutes to your stop, "Arrives 5:43 PM" at the right, the stop line.
    /// The countdown is anchored on the device clock, which timer text runs on: it ends `deviceNow` plus the time left on
    /// the engine's clock. Nil for a plan with fewer than two stops.
    init?(plan: RidePlan, state: RideState, now: Date, deviceNow: Date, formatter: some TimeFormatting) {
        guard let times = RideTimes(plan: plan, state: state),
              let details = RideDetails(plan: plan, state: state, now: now, formatter: formatter) else { return nil }
        let last = times.last
        let phase: Phase = switch state.phase {
        case .riding: .riding
        case .atStation: .atStation
        case .yourStopNext: .yourStopNext
        case .arriving: .arriving
        case .atYourStop, .ended: .atYourStop
        }
        let countdownTo: Date? = phase == .atYourStop ? nil : times.time(at: last)
        // Arriving and at your stop the card says one thing: nothing at the right.
        let showsArrival = phase == .riding || phase == .atStation || phase == .yourStopNext
        self.phase = phase
        title = details.kicker
        countdownEnd = countdownTo.map { deviceNow.addingTimeInterval($0.timeIntervalSince(now)) }
        // The ride screen's minutes, word for word (`RideDetails`): sent again as the engine's minute changes.
        minutes = countdownTo.map { _ in
            String(format: String(localized: "onboard.minutes"), max(1, times.minutes(to: last, from: now)))
        }
        self.now = String(localized: "onboard.now")
        label = showsArrival ? String(localized: "depart.arrivesLabel") : ""
        value = showsArrival ? formatter.time(times.time(at: last)) : nil
        delay = nil
        platformNumber = nil
        late = times.delayMinutes >= 1 && phase != .atYourStop
        // The ride screen's rail: every station from where you got on to your stop, the ones the train does not stop at
        // hollow, and the train where the ride screen has it (TT-232, D111). On a train that stops everywhere, its stops.
        position = details.railFill
        let hollow = details.stops.filter(\.isSkipped).map(\.index)
        stations = hollow.isEmpty ? nil : details.stops.count
        skipped = hollow
        express = plan.isExpress
        isClose = details.isClose
        updated = String(format: String(localized: "live.updated"), formatter.time(now))
    }

    /// The same activity as far as a rider can tell: the train within 2 % of the bar and the countdown within 15 s, the
    /// rest the same (the update time aside), the minutes included, so a new minute sends an update (TT-219). The app sends
    /// nothing new for such a change, only once a minute to keep it fresh.
    func looksLike(_ other: Self) -> Bool {
        var mine = self, theirs = other
        guard abs(mine.position - theirs.position) < 0.02 else { return false }
        switch (mine.countdownEnd, theirs.countdownEnd) {
        case (nil, nil): break
        case let (end?, otherEnd?) where abs(end.timeIntervalSince(otherEnd)) < 15: break
        default: return false
        }
        mine.position = 0
        theirs.position = 0
        mine.countdownEnd = nil
        theirs.countdownEnd = nil
        mine.updated = ""
        theirs.updated = ""
        return mine == theirs
    }
}

// MARK: Before departure (TT-178, D74)

extension RideActivityAttributes.ContentState {
    /// The alerted train's activity at `now` on its clock (Mock time, or the demo departure's own), the countdown anchored on
    /// the device clock as the ride's is: "5:13 PM departs in" over the minutes to the expected departure, "Platform" and the
    /// pill at the right; "5:16 PM boarding now" in the last 2 min. `server/src/activity.ts` writes the same words for the
    /// same train, so the alert server's activity and the app's look alike; only the app knows a posted platform (GO's feeds
    /// post none, D35).
    init(departure live: LiveDeparture, now: Date, deviceNow: Date, formatter: some TimeFormatting) {
        let leaves = formatter.time(live.leaves)
        phase = switch live.phase {
        case .countingDown: .countingDown
        case .boarding: .boarding
        case .departed: .departed
        }
        title = switch live.phase {
        case .countingDown: String(format: String(localized: "depart.line"), leaves)
        case .boarding: String(format: String(localized: "depart.boardingLine"), leaves)
        case .departed: String(format: String(localized: "depart.departed"), leaves)
        }
        let isLate = live.phase != .departed && live.delayMinutes != nil
        countdownEnd = live.phase == .departed ? nil : deviceNow.addingTimeInterval(live.leaves.timeIntervalSince(now))
        // The departure hero's and the timeline's minutes ("in 12 min"); the alert server writes the same each minute.
        minutes = live.phase == .departed ? nil : String(format: String(localized: "onboard.minutes"), live.minutes(at: now))
        self.now = ""
        label = String(localized: "depart.platformLabel")
        value = nil
        delay = isLate ? live.delayMinutes.map { String(format: String(localized: "onboard.late"), $0) } : nil
        platformNumber = live.platform
        late = isLate
        position = 0
        isClose = live.phase == .boarding
        updated = String(format: String(localized: "live.updated"), formatter.time(now))
    }
}

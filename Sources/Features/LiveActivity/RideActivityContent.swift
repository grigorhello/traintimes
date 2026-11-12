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
    /// The activity at `now` on the engine's clock (Mock time, or the demo ride's own clock). The countdown is anchored on
    /// the device clock, which timer text runs on: it ends `deviceNow` plus the time left on the engine's clock. Nil for a
    /// plan with fewer than two stops.
    init?(plan: RidePlan, state: RideState, now: Date, deviceNow: Date, formatter: some TimeFormatting) {
        guard let times = RideTimes(plan: plan, state: state) else { return nil }
        let stops = plan.stops
        let last = times.last
        let yours = RideDetails.shortName(stops[last].station.name)
        let phase: Phase = switch state.phase {
        case .riding: .riding
        case .atStation: .atStation
        case .yourStopNext: .yourStopNext
        case .arriving: .arriving
        case .atYourStop, .ended: .atYourStop
        }
        let passed = phase == .atYourStop ? last : times.passed
        let next = min(passed + 1, last)
        func pair(_ first: String, _ second: String) -> String {
            String(format: String(localized: "onboard.detail"), first, second)
        }
        func name(_ index: Int) -> String {
            RideDetails.shortName(stops[index].station.name)
        }
        let arrival = formatter.time(times.time(at: last))
        let toYourStop = state.stopsLeft == 1
            ? String(localized: "onboard.yoursNext")
            : String(format: String(localized: "live.toYourStop"), yours, arrival, state.stopsLeft)

        let countdownTo: Date?
        switch phase {
        case .riding:
            title = pair(String(localized: "onboard.next"), name(next))
            detail = toYourStop
            countdownTo = times.time(at: next)
        case .atStation:
            title = pair(String(localized: "onboard.nowAt"), name(passed))
            detail = toYourStop
            countdownTo = nil
        case .yourStopNext:
            title = pair(String(localized: "onboard.next"), yours)
            detail = String(localized: "onboard.yoursNext")
            countdownTo = times.time(at: last)
        case .arriving:
            title = String(format: String(localized: "live.arriving"), yours)
            detail = String(localized: "live.arrivingDetail")
            countdownTo = times.time(at: last)
        case .atYourStop, .countingDown, .boarding, .departed:
            // A ride's state is never a departure phase (`phase` is mapped from `RidePhase` above).
            title = String(localized: "onboard.thisIsYours")
            detail = pair(yours, String(localized: "onboard.complete"))
            countdownTo = nil
        }
        self.phase = phase
        countdownEnd = countdownTo.map { deviceNow.addingTimeInterval($0.timeIntervalSince(now)) }
        self.now = String(localized: "onboard.now")
        time = formatter.time(countdownTo ?? times.time(at: passed))
        departure = String(format: String(localized: "live.stopTime"), name(0), formatter.time(times.scheduled(at: 0)))
        self.arrival = String(format: String(localized: "live.stopTime"), yours, arrival)
        position = switch phase {
        case .atYourStop, .countingDown, .boarding, .departed: Double(last)
        case .atStation: Double(passed)
        case .riding, .yourStopNext, .arriving: Double(passed) + times.fraction(from: passed, at: now)
        }
        button = phase == .atYourStop ? String(localized: "onboard.done") : String(localized: "onboard.end")
        updated = String(format: String(localized: "live.updated"), formatter.time(now))
    }

    /// The same activity as far as a rider can tell: the train within 2 % of the bar and the countdown within 15 s, the
    /// rest the same (the update time aside). The app sends nothing new for such a change, only once a minute to keep it
    /// fresh.
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
    /// the device clock as the ride's is. `server/src/activity.ts` writes the same words for the same train, so the alert
    /// server's activity and the app's look alike; only the app knows a posted platform (GO's feeds post none, D35).
    init(
        departure live: LiveDeparture, origin: String, destination: String, hasPlatformSource: Bool, now: Date, deviceNow: Date,
        formatter: some TimeFormatting
    ) {
        let departure = live.departure
        let trip = departure.trip
        let leaves = formatter.time(live.leaves)
        let arrivalTime = formatter.time(departure.expectedArrival ?? trip.scheduledArrival)
        let yours = RideDetails.shortName(destination)
        // A pending platform worth waiting for (fresh live data from a feed that posts platforms, D55) shows the pill.
        let showsPill = live.platform == nil && hasPlatformSource && live.isLive
        let platformText = if let posted = live.platform {
            String(format: String(localized: "depart.platform"), posted)
        } else if showsPill {
            String(localized: "depart.platformLabel")
        } else {
            String(localized: "depart.checkBoard")
        }
        let word = switch live.phase {
        case .boarding: String(localized: "depart.boarding")
        case .departed: String(format: String(localized: "depart.departed"), leaves)
        case .countingDown:
            if let minutes = live.delayMinutes {
                String(format: String(localized: "depart.delayed"), minutes)
            } else {
                live.isLive ? String(localized: "status.on_time") : String(localized: "status.scheduled")
            }
        }

        phase = switch live.phase {
        case .countingDown: .countingDown
        case .boarding: .boarding
        case .departed: .departed
        }
        title = String(format: String(localized: "schedule.route_title"), formatter.time(trip.scheduledDeparture), yours)
        detail = String(format: String(localized: "onboard.detail"), platformText, word)
        platform = platformText
        platformNumber = live.platform
        pill = showsPill
        late = live.phase == .countingDown && live.delayMinutes != nil
        countdownEnd = live.phase == .departed ? nil : deviceNow.addingTimeInterval(live.leaves.timeIntervalSince(now))
        self.now = ""
        time = live.phase == .departed ? "" : String(localized: "depart.in")
        self.departure = String(format: String(localized: "live.stopTime"), TrainQuestion.shortName(origin), leaves)
        let arrivalText = String(format: String(localized: "live.stopTime"), yours, arrivalTime)
        arrival = arrivalText
        arrives = String(format: String(localized: "depart.arrives"), arrivalText)
        position = 0
        button = String(localized: "onboard.button")
        updated = String(format: String(localized: "live.updated"), formatter.time(now))
    }
}

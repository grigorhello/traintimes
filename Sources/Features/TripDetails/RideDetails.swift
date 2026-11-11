import Foundation

/// The ride as Trip details shows it in ride mode (TT-172, *Live-Ride*): the ride card, the stop list with the train on
/// its rail, the footnote and the button. Every time is already formatted by the one formatter (D17).
struct RideDetails: Equatable {
    /// The card's five looks; an ended ride keeps the look of your stop.
    enum Moment: Equatable {
        case riding, atStation, yourStopNext, arriving, atYourStop
    }

    /// The card's status row.
    enum Source: Equatable {
        /// "Live · your location" or "Live · GO train data", with the rippling dot.
        case live(String)
        /// "Timetable", with the grey dot.
        case timetable
        /// "Ride complete", at your stop.
        case complete
    }

    /// The card's second row while your stop is two or more stops away.
    struct YourStop: Equatable {
        let name: String
        /// "11 min".
        let minutes: String
        let time: String
    }

    struct Stop: Equatable, Identifiable {
        let id: String
        let name: String
        let time: String
        let isFirst: Bool
        let isYours: Bool
        /// The train has left it, or stands at it.
        let isDone: Bool
        /// The first stop ahead.
        let isNext: Bool
    }

    let moment: Moment
    /// "5:13 PM train": the sheet's accessibility label.
    let title: String
    /// "Next stop", "Now at", "Next stop · yours", "Arriving at your stop", "This is your stop".
    let label: String
    /// The station the card is about.
    let name: String
    /// "4 min", or "Now".
    let countdown: String
    /// The time under the countdown.
    let countdownTime: String
    /// "5:36 PM · On time", "Your stop is next", "Get ready to step off", "On time · Ride complete".
    let detail: String
    let yourStop: YourStop?
    let source: Source
    /// "Updated just now", "Last reported 5:31 PM", or your stop's time once you are there.
    let freshness: String?
    /// "2 stops to Clarkson", "Clarkson is next", "You are at Clarkson".
    let stopsHeader: String
    /// "Expected", or "Scheduled" on the timetable alone.
    let stopsBasis: String
    let stops: [Stop]
    /// Where the train is on the stop list, in rows from the first stop: 3.25 is a quarter of the way from the fourth stop
    /// to the fifth. Nil at your stop, where the tick takes its place.
    let trainPosition: Double?
    /// "A tap about 1 min before Clarkson and again when the train stops. …"
    let footnote: String
    /// "End ride", or "Done" at your stop.
    let button: String

    var isComplete: Bool { moment == .atYourStop }
    /// Arriving and at your stop tint the card.
    var isTinted: Bool { moment == .arriving || moment == .atYourStop }
    /// Your stop's row is tinted once it is next, and stays so.
    var highlightsYourStop: Bool { moment == .yourStopNext || moment == .arriving || moment == .atYourStop }
    /// Your stop's pin rings until the train stops there.
    var pingsYourStop: Bool { moment == .yourStopNext || moment == .arriving }
    /// How far the rail is green, in the same rows as `trainPosition`.
    var railFill: Double { trainPosition ?? Double(max(0, stops.count - 1)) }

    /// "Clarkson GO" reads "Clarkson" in running text.
    static func shortName(_ name: String) -> String {
        name.hasSuffix(" GO") ? String(name.dropLast(3)) : name
    }
}

extension RideDetails {
    /// The display model at `now` (the ride engine's clock), or nil for a plan with fewer than two stops.
    init?(plan: RidePlan, state: RideState, now: Date, formatter: some TimeFormatting) {
        guard let times = RideTimes(plan: plan, state: state) else { return nil }
        let stops = plan.stops
        let last = times.last
        let destination = stops[last].station
        let yours = Self.shortName(destination.name)
        let moment: Moment = switch state.phase {
        case .riding: .riding
        case .atStation: .atStation
        case .yourStopNext: .yourStopNext
        case .arriving: .arriving
        case .atYourStop, .ended: .atYourStop
        }
        let isComplete = moment == .atYourStop
        let passed = isComplete ? last : times.passed
        let next = min(passed + 1, last)
        let punctuality = times.delayMinutes >= 1
            ? String(format: String(localized: "status.delayed"), times.delayMinutes)
            : String(localized: "status.on_time")
        func pair(_ first: String, _ second: String) -> String {
            String(format: String(localized: "onboard.detail"), first, second)
        }
        func minutes(_ count: Int) -> String {
            String(format: String(localized: "onboard.minutes"), max(1, count))
        }

        switch moment {
        case .riding:
            label = String(localized: "onboard.next")
            name = stops[next].station.name
            countdown = minutes(times.minutes(to: next, from: now))
            countdownTime = formatter.time(times.time(at: next))
            detail = pair(countdownTime, punctuality)
        case .atStation:
            label = String(localized: "onboard.nowAt")
            name = stops[passed].station.name
            countdown = String(localized: "onboard.now")
            countdownTime = formatter.time(times.time(at: passed))
            detail = state.stopsLeft == 1
                ? String(localized: "onboard.yoursNext")
                : String(format: String(localized: "onboard.stops"), state.stopsLeft, yours)
        case .yourStopNext:
            label = String(localized: "onboard.nextYours")
            name = destination.name
            countdown = minutes(times.minutes(to: last, from: now))
            countdownTime = formatter.time(times.time(at: last))
            detail = pair(countdownTime, punctuality)
        case .arriving:
            label = String(localized: "onboard.arriving")
            name = destination.name
            countdown = minutes(times.minutes(to: last, from: now))
            countdownTime = formatter.time(times.time(at: last))
            detail = String(localized: "onboard.getReady")
        case .atYourStop:
            label = String(localized: "onboard.thisIsYours")
            name = destination.name
            countdown = String(localized: "onboard.now")
            countdownTime = formatter.time(times.time(at: last))
            detail = pair(punctuality, String(localized: "onboard.complete"))
        }
        self.moment = moment

        yourStop = moment == .riding || moment == .atStation
            ? YourStop(name: destination.name, minutes: minutes(times.minutes(to: last, from: now)), time: formatter.time(times.time(at: last)))
            : nil

        if isComplete {
            source = .complete
            freshness = formatter.time(times.time(at: last))
        } else {
            switch state.source {
            case .phone: source = .live(String(localized: "onboard.live.phone"))
            case .trainFeed: source = .live(String(localized: "onboard.live.feed"))
            case .timetable: source = .timetable
            }
            freshness = state.lastUpdate.map { update in
                state.source == .timetable
                    ? String(format: String(localized: "status.last_reported"), formatter.time(update))
                    : formatter.updated(at: update, now: now)
            }
        }

        stopsHeader = switch moment {
        case .atYourStop: String(format: String(localized: "onboard.atYours"), yours)
        case .yourStopNext, .arriving: String(format: String(localized: "onboard.isNext"), yours)
        case .riding, .atStation:
            state.stopsLeft == 1
                ? String(format: String(localized: "onboard.stops_one"), yours)
                : String(format: String(localized: "onboard.stops"), state.stopsLeft, yours)
        }
        stopsBasis = state.source == .timetable && times.delay == 0
            ? String(localized: "trip.stops_scheduled")
            : String(localized: "trip.stops_expected")
        self.stops = stops.enumerated().map { index, stop in
            Stop(
                id: stop.station.id,
                name: stop.station.name,
                time: formatter.time(index > passed ? times.time(at: index) : times.scheduled(at: index)),
                isFirst: index == 0,
                isYours: index == last,
                isDone: index <= passed,
                isNext: !isComplete && index == passed + 1
            )
        }

        trainPosition = switch moment {
        case .atYourStop: nil
        case .atStation: Double(passed)
        case .riding, .yourStopNext, .arriving: Double(passed) + times.fraction(from: passed, at: now)
        }
        title = String(format: String(localized: "trip.title"), formatter.time(stops[0].departure))
        footnote = String(format: String(localized: "onboard.footnote"), yours)
        button = isComplete ? String(localized: "onboard.done") : String(localized: "onboard.end")
    }
}

/// The ride strip on Schedule (TT-172, *Live-Schedule*): "On board · 5:13 PM train", the next stop, the minutes to it, and
/// your stop with its time. A tap opens Trip details in ride mode.
struct RideStrip: Equatable {
    /// "On board · 5:13 PM train".
    let title: String
    /// "Next stop Port Credit", or "This is your stop".
    let next: String
    /// "4 min" to the next stop, or "Now" at your stop.
    let countdown: String
    /// "Clarkson".
    let destination: String
    /// Your stop's time.
    let arrival: String
    /// The dot ripples while the phone or the feed places the train, grey on the timetable.
    let isLive: Bool

    init?(plan: RidePlan, state: RideState, now: Date, formatter: some TimeFormatting) {
        guard let times = RideTimes(plan: plan, state: state) else { return nil }
        let stops = plan.stops
        let last = times.last
        let isThere = state.phase == .atYourStop || state.phase == .ended
        let next = min(times.passed + 1, last)
        title = String(format: String(localized: "onboard.strip"), formatter.time(stops[0].departure))
        self.next = isThere
            ? String(localized: "onboard.thisIsYours")
            : String(format: String(localized: "onboard.stripNext"), RideDetails.shortName(stops[next].station.name))
        countdown = isThere
            ? String(localized: "onboard.now")
            : String(format: String(localized: "onboard.minutes"), max(1, times.minutes(to: next, from: now)))
        destination = RideDetails.shortName(stops[last].station.name)
        arrival = formatter.time(times.time(at: last))
        isLive = state.source != .timetable
    }
}

/// The ride's times as the card, the strip and the Live Activity (TT-174) read them: the timetable moved by the ride's
/// delay (never earlier, GO trains do not leave early), and which stop the train last passed.
struct RideTimes {
    let plan: RidePlan
    let last: Int
    /// Seconds late at your stop, from the engine's expected arrival; 0 or more.
    let delay: TimeInterval
    /// The stop the train stands at, or the last one it passed.
    let passed: Int

    init?(plan: RidePlan, state: RideState) {
        guard plan.stops.count >= 2 else { return nil }
        let stops = plan.stops
        self.plan = plan
        last = stops.count - 1
        // To the second, so a measured offset of a few microseconds does not tip a countdown over a minute.
        delay = max(0, state.expectedArrival.timeIntervalSince(stops[stops.count - 1].arrival).rounded())
        func index(of station: Station?) -> Int? {
            station.flatMap { station in stops.firstIndex { $0.station.id == station.id } }
        }
        if state.phase == .atYourStop || state.phase == .ended {
            passed = stops.count - 1
        } else if let current = index(of: state.currentStop) {
            passed = current
        } else {
            passed = max(0, (index(of: state.nextStop) ?? stops.count - 1) - 1)
        }
    }

    var delayMinutes: Int { Int((delay / 60).rounded()) }

    /// The stop's scheduled time: the departure at the origin, the arrival elsewhere.
    func scheduled(at index: Int) -> Date {
        index == 0 ? plan.stops[0].departure : plan.stops[index].arrival
    }

    /// The stop's expected time.
    func time(at index: Int) -> Date {
        scheduled(at: index).addingTimeInterval(delay)
    }

    /// Whole minutes until the stop's expected time, rounded up from the whole seconds.
    func minutes(to index: Int, from now: Date) -> Int {
        Int((time(at: index).timeIntervalSince(now).rounded() / 60).rounded(.up))
    }

    /// How far the train is from stop `index` to the next one by the clock, kept off both ends: the stops' own rows say
    /// when it stands at one.
    func fraction(from index: Int, at now: Date) -> Double {
        let to = min(index + 1, last)
        let leaves = plan.stops[index].departure.addingTimeInterval(delay)
        let reaches = plan.stops[to].arrival.addingTimeInterval(delay)
        let span = reaches.timeIntervalSince(leaves)
        guard span > 0 else { return 0 }
        return min(max(now.timeIntervalSince(leaves) / span, 0.08), 0.92)
    }
}

extension OnBoard {
    /// Trip details' ride mode for `key`, at the engine's clock; nil when the engine's ride is another trip's.
    func details(for key: TripKey, formatter: some TimeFormatting) -> RideDetails? {
        guard let engine, engine.ride?.tripKey == key, let plan = engine.plan, let state = engine.state else { return nil }
        return RideDetails(plan: plan, state: state, now: engine.now, formatter: formatter)
    }

    /// The ride strip on Schedule; nil with no ride running.
    func strip(formatter: some TimeFormatting) -> RideStrip? {
        guard activeRide != nil, let engine, let plan = engine.plan, let state = engine.state else { return nil }
        return RideStrip(plan: plan, state: state, now: engine.now, formatter: formatter)
    }
}

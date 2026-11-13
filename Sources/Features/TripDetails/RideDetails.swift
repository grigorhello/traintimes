import Foundation

/// The ride as Trip details shows it in ride mode (TT-204, D87, *Live-Ride-Lean*): one job, how long until your stop. A
/// kicker over the minutes, "5 min late" only when late, the stops from where you got on to your stop with the train on
/// their rail, and the button. Every time is already formatted by the one formatter (D17).
struct RideDetails: Equatable {
    /// The engine's five phases; an ended ride keeps the look of your stop.
    enum Moment: Equatable {
        case riding, atStation, yourStopNext, arriving, atYourStop
    }

    /// The departure card's status row (TT-177); the ride itself no longer says where its position comes from (D87).
    enum Source: Equatable {
        /// "Live · GO train data", with the rippling dot.
        case live(String)
        /// "Timetable", with the grey dot.
        case timetable
        case complete
    }

    struct Stop: Equatable, Identifiable {
        let id: String
        let name: String
        /// The expected time of a stop ahead, and your stop's once the train stands there; nil for a stop it has passed.
        let time: String?
        let isFirst: Bool
        let isYours: Bool
        /// The train has left it, or stands at it.
        let isDone: Bool
        /// The first stop ahead.
        let isNext: Bool
        /// The time is 1 min or more after the timetable's: drawn in the delay ink.
        let isLate: Bool
    }

    let moment: Moment
    /// "5:13 PM train": the sheet's accessibility label.
    let title: String
    /// "Your stop", "Your stop is next", "Arriving at your stop", "This is your stop".
    let kicker: String
    /// The minutes to your stop, "11 min", or "Now" at it.
    let countdown: String
    /// "5 min late" when the train is 1 min or more late; nil on time and at your stop.
    let late: String?
    let stops: [Stop]
    /// Where the train is on the stop list, in rows from the first stop: 3.25 is a quarter of the way from the fourth stop
    /// to the fifth. Nil at your stop, where the tick takes its place.
    let trainPosition: Double?
    /// "End ride", or "Done" at your stop.
    let button: String

    var isComplete: Bool { moment == .atYourStop }
    /// Arriving and at your stop tint the hero card.
    var isTinted: Bool { moment == .arriving || moment == .atYourStop }
    /// Every kicker but "Your stop" is in the accent.
    let isKickerAccent: Bool
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
        let moment: Moment = switch state.phase {
        case .riding: .riding
        case .atStation: .atStation
        case .yourStopNext: .yourStopNext
        case .arriving: .arriving
        case .atYourStop, .ended: .atYourStop
        }
        let isComplete = moment == .atYourStop
        let passed = isComplete ? last : times.passed
        let minutes = String(format: String(localized: "onboard.minutes"), max(1, times.minutes(to: last, from: now)))
        let isLate = times.delayMinutes >= 1

        // Standing at the stop before yours, your stop is the next one.
        let yoursIsNext = moment == .yourStopNext || (moment == .atStation && passed + 1 == last)
        switch moment {
        case .riding, .atStation, .yourStopNext:
            kicker = yoursIsNext ? String(localized: "onboard.yoursNext") : String(localized: "onboard.yourStop")
            isKickerAccent = yoursIsNext
            countdown = minutes
        case .arriving:
            kicker = String(localized: "onboard.arriving")
            isKickerAccent = true
            countdown = minutes
        case .atYourStop:
            kicker = String(localized: "onboard.thisIsYours")
            isKickerAccent = true
            countdown = String(localized: "onboard.now")
        }
        self.moment = moment
        late = isLate && !isComplete ? String(format: String(localized: "onboard.late"), times.delayMinutes) : nil

        self.stops = stops.enumerated().map { index, stop in
            let shows = index > passed || (isComplete && index == last)
            return Stop(
                id: stop.station.id,
                name: stop.station.name,
                time: shows ? formatter.time(times.time(at: index)) : nil,
                isFirst: index == 0,
                isYours: index == last,
                isDone: index <= passed,
                isNext: !isComplete && index == passed + 1,
                isLate: isLate && index > passed
            )
        }

        trainPosition = switch moment {
        case .atYourStop: nil
        case .atStation: Double(passed)
        case .riding, .yourStopNext, .arriving: Double(passed) + times.fraction(from: passed, at: now)
        }
        title = String(format: String(localized: "trip.title"), formatter.time(stops[0].departure))
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

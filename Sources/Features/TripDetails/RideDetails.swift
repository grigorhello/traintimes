import Foundation

/// The ride as Trip details shows it in ride mode (TT-204, D87, *Live-Ride-Lean*): one job, how long until your stop. A
/// kicker over the minutes, "5 min late" only when late, the stops from where you got on to your stop with the train on
/// their rail, and the button. Every time is already formatted by the one formatter (D17).
struct RideDetails: Equatable {
    /// The engine's five phases; an ended ride keeps the look of your stop.
    enum Moment: Equatable {
        case riding, atStation, yourStopNext, arriving, atYourStop
    }

    /// A row of the drawn rail.
    enum Row: Equatable, Identifiable {
        case stop(Stop)
        /// Stops left out, between two drawn ones: a short row with a dotted rail and no names.
        case fold(after: String)

        var id: String {
            switch self {
            case .stop(let stop): stop.id
            case .fold(let after): "fold.\(after)"
            }
        }

        /// The drawn stop's place in `stops`; nil for a fold.
        var stopIndex: Int? {
            if case .stop(let stop) = self { return stop.index }
            return nil
        }
    }

    struct Stop: Equatable, Identifiable {
        let id: String
        /// Its place in `stops`, where `trainPosition` counts.
        let index: Int
        /// "Port Credit", without " GO".
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
    /// "Clarkson in", "Clarkson is next", "Arriving at Clarkson", "This is Clarkson": the stop named, so a guessed stop
    /// can be checked at a glance.
    let kicker: String
    /// The minutes to your stop, "11 min", or "Now" at it.
    let countdown: String
    /// The arrival wish that takes "Now"'s place 5 s after the train reached your stop (TT-223, D103): it replaces the
    /// number, it adds no line (D87).
    let wish: ArrivalWish?
    /// "5 min late" when the train is 1 min or more late; nil on time and at your stop.
    let late: String?
    /// Every stop from where you got on to yours.
    let stops: [Stop]
    /// The rail as drawn: the boarding stop, the stops passed before the last one folded into one short dotted row, the
    /// last stop passed, the next two, the ones between them and your stop folded, and your stop. Your stop's row always
    /// fits on the screen, however long the trip (review of TT-204).
    let rows: [Row]
    /// Where the train is on `stops`: on a stop's index while it stands there; while it moves, that far to the next stop by
    /// the clock (`RideTimes.fraction(from:at:)`, the timetable moved by the ride's measured delay, TT-224, D106). The view
    /// keeps it from going back and short of your stop's pin. Nil at your stop, where the tick takes its place.
    let trainPosition: Double?
    /// The stop the train stands at, or the last one it passed: a stop passes when this goes up.
    let passed: Int
    /// Your stop is the next one: moving to it, or standing at the stop before it.
    let yoursIsNext: Bool
    /// "End ride", or "Done" at your stop.
    let button: String

    var isComplete: Bool { moment == .atYourStop }
    /// Arriving and at your stop tint the hero card.
    var isTinted: Bool { moment == .arriving || moment == .atYourStop }
    /// Your stop is next, the train is arriving, or it is there: the kicker and the number turn to the accent. Before
    /// that, and when late, they are ink, so the green means "your stop is close".
    let isClose: Bool
    /// Your stop's pin rings until the train stops there.
    var pingsYourStop: Bool { moment == .yourStopNext || moment == .arriving }
    /// The train is between two stations: the loop plays (TT-224).
    var isMoving: Bool { moment == .riding || moment == .yourStopNext || moment == .arriving }
    /// The loop's length while the train moves, quicker in the last minute; nil standing at a station.
    var loop: Double? {
        guard isMoving else { return nil }
        return moment == .arriving ? RideMotion.arrivingLoop : RideMotion.movingLoop
    }
    /// The rail from the train to your pin is soft green: your stop is next, or the train is arriving.
    var softensLastStretch: Bool { (yoursIsNext || moment == .arriving) && !isComplete }
    /// How far the rail is green, in the same rows as `trainPosition`.
    var railFill: Double { trainPosition ?? Double(max(0, stops.count - 1)) }

    /// "Clarkson GO" reads "Clarkson": every stop on a GO train is a GO station.
    static func shortName(_ name: String) -> String {
        name.hasSuffix(" GO") ? String(name.dropLast(3)) : name
    }
}

extension RideDetails {
    /// The display model at `now` (the ride engine's clock), or nil for a plan with fewer than two stops.
    init?(plan: RidePlan, state: RideState, now: Date, formatter: some TimeFormatting, wish: ArrivalWish? = nil) {
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

        let yours = Self.shortName(stops[last].station.name)
        // Standing at the stop before yours, your stop is the next one.
        let yoursIsNext = moment == .yourStopNext || (moment == .atStation && passed + 1 == last)
        switch moment {
        case .riding, .atStation, .yourStopNext:
            let format = yoursIsNext ? String(localized: "onboard.isNext") : String(localized: "onboard.yourStopIn")
            kicker = String(format: format, yours)
            isClose = yoursIsNext
            countdown = minutes
        case .arriving:
            kicker = String(format: String(localized: "onboard.arrivingAt"), yours)
            isClose = true
            countdown = minutes
        case .atYourStop:
            kicker = String(format: String(localized: "onboard.thisIs"), yours)
            isClose = true
            countdown = String(localized: "onboard.now")
        }
        self.moment = moment
        self.passed = passed
        self.yoursIsNext = yoursIsNext
        self.wish = isComplete ? wish : nil
        late = isLate && !isComplete ? String(format: String(localized: "onboard.late"), times.delayMinutes) : nil

        let built = stops.enumerated().map { index, stop -> Stop in
            let shows = index > passed || (isComplete && index == last)
            return Stop(
                id: stop.station.id,
                index: index,
                name: Self.shortName(stop.station.name),
                time: shows ? formatter.time(times.time(at: index)) : nil,
                isFirst: index == 0,
                isYours: index == last,
                isDone: index <= passed,
                isNext: !isComplete && index == passed + 1,
                isLate: isLate && index > passed
            )
        }

        self.stops = built
        // At your stop the stop before it stays drawn: no row moves while the train slides into your pin (TT-224).
        rows = Self.rows(built, passed: isComplete ? max(0, last - 1) : passed)
        trainPosition = switch moment {
        case .atYourStop: nil
        case .atStation: Double(passed)
        case .riding, .yourStopNext, .arriving: Double(passed) + times.fraction(from: passed, at: now)
        }
        title = String(format: String(localized: "trip.title"), formatter.time(stops[0].departure))
        button = isComplete ? String(localized: "onboard.done") : String(localized: "onboard.end")
    }
}

extension RideDetails {
    /// The train never goes back on screen (TT-220's rule, D60): a later delay moves the clock's position back a little on
    /// the same stretch, and the train holds where it was instead. A new stretch, a stop, or your stop shows as it is.
    static func forward(_ position: Double?, from held: Double?) -> Double? {
        guard let position, let held else { return position }
        guard position.rounded(.down) == held.rounded(.down), position != position.rounded(.down) else { return position }
        return max(position, held)
    }

    /// The boarding stop, the last stop passed and your stop always show. Stops passed before the last one fold; stops
    /// ahead all show while there are four at most, else the next two, then a fold, then yours. A fold never hides a single
    /// stop: it shows instead. At most seven stop rows and two folds, so your stop stays on screen.
    static func rows(_ stops: [Stop], passed: Int) -> [Row] {
        let last = stops.count - 1
        guard last >= 0 else { return [] }
        let passed = min(max(passed, 0), last)
        var shown: Set<Int> = [0, passed, last]
        let ahead = last - passed
        for index in (passed + 1)..<(last + 1) where ahead <= 4 || index <= passed + 2 {
            shown.insert(index)
        }
        for index in 0...last where !shown.contains(index) && shown.contains(index - 1) && shown.contains(index + 1) {
            shown.insert(index)
        }
        var rows: [Row] = []
        for index in 0...last {
            if shown.contains(index) {
                rows.append(.stop(stops[index]))
            } else if shown.contains(index - 1) {
                rows.append(.fold(after: stops[index - 1].id))
            }
        }
        return rows
    }
}

/// The ride strip on Schedule (TT-172; one line since TT-205, D93, *Live-Schedule*): the ride screen's line and minutes. A
/// tap opens Trip details in ride mode.
struct RideStrip: Equatable {
    /// "Clarkson in", "Clarkson is next", "Arriving at Clarkson", "This is Clarkson": the ride screen's kicker.
    let line: String
    /// "11 min" to your stop, or "Now" at it.
    let countdown: String
    /// The dot ripples while the phone or the feed places the train, grey on the timetable.
    let isLive: Bool

    init?(plan: RidePlan, state: RideState, now: Date, formatter: some TimeFormatting) {
        guard let details = RideDetails(plan: plan, state: state, now: now, formatter: formatter) else { return nil }
        line = details.kicker
        countdown = details.countdown
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
        return RideDetails(plan: plan, state: state, now: engine.now, formatter: formatter, wish: arrivalWish)
    }

    /// The ride strip on Schedule; nil with no ride running.
    func strip(formatter: some TimeFormatting) -> RideStrip? {
        guard activeRide != nil, let engine, let plan = engine.plan, let state = engine.state else { return nil }
        return RideStrip(plan: plan, state: state, now: engine.now, formatter: formatter)
    }
}

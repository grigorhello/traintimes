import Foundation

/// One train the phone may be on (TT-175): a trip running now on the Schedule's route, or on the same two stations the
/// other way, with its stops on that stretch and its track.
struct TrainCandidate: Sendable, Equatable, Identifiable {
    let trip: TripKey
    /// The stretch the stops run on; a ride started from the question rides it.
    let route: Route
    /// Two stops at least, and the track: a trip with no track cannot be matched.
    let plan: RidePlan

    var id: TripKey { trip }
    /// The train's name (D9): its scheduled departure from the stretch's first stop, "5:13 PM train".
    var departure: Date { plan.stops[0].departure }
    var ride: Ride { Ride(trip: trip, from: route.from.id, to: route.to.id) }
}

extension RidePlan {
    /// Where the timetable has the train at `time`, in metres along its track: standing at each stop from its arrival to
    /// its departure, at an even speed between them, waiting at the first stop before it leaves and at the last after.
    func scheduledAlong(at time: Date) -> Double {
        guard let distances = track?.stopDistances, let lastDistance = distances.last else { return 0 }
        for index in stops.indices {
            if time < stops[index].arrival {
                guard index > 0 else { return distances[0] }
                let leaves = stops[index - 1].departure
                let span = stops[index].arrival.timeIntervalSince(leaves)
                let fraction = span > 0 ? min(max(time.timeIntervalSince(leaves) / span, 0), 1) : 1
                return distances[index - 1] + (distances[index] - distances[index - 1]) * fraction
            }
            if time <= stops[index].departure { return distances[index] }
        }
        return lastDistance
    }
}

/// The in-app matcher (TT-175, Live-Spec "The matching rule"): is the phone on one of the candidate trains? Pure logic,
/// fed with the phone's fixes and, once TT-179 adds it, the train feed's positions; the detector runs it.
///
/// Positions are projected onto each train's track, so "same place" is one number. All four checks must hold:
/// 1. **Same place**: within 150 m of the train. The feed places a train to the metre; the timetable only to about a minute,
///    so a timetable train is anywhere it would be between a minute early and a minute late against the delay learned at
///    the stops it shared with the phone (up to 15 min late before the first one).
/// 2. **Same way**: the phone moves along the track in the train's direction faster than 25 km/h, and the feed's train too,
///    their speeds within 20 %. The timetable gives no speed (it averages each stretch), so for it the phone's alone counts.
/// 3. **Stopped together**: both stand within 80 m of a station's platform at the same time (the platform taken as 150 m
///    either side of the station's place), after the phone has moved with the train.
/// 4. **Twice**: two shared stops, or one plus 3 min of moving together.
///
/// Confidence: with the feed, the question comes as soon as the four hold; on the timetable alone, after one more shared
/// stop or 3 more minutes of moving together. One stop alone never asks. The question comes while the phone and the train
/// move together, never while they stand. Two trains can fit on the timetable (a local and a late express): the question
/// offers both. Unanswered, it goes after 3 min or at the next station, and that train is not asked about again.
struct TrainMatcher {
    static let placeRadius = 150.0
    static let speedTolerance = 0.20
    static let minimumSpeed = 25 / 3.6
    /// Slower than this (7 km/h) a phone or a train stands.
    static let stoppedSpeed = 2.0
    static let platformMargin = 80.0
    static let platformHalfLength = 150.0
    static let togetherTime: TimeInterval = 3 * 60
    /// How far the timetable is from where a train runs on the delay it has shown.
    static let timetableSlack: TimeInterval = 60
    /// The latest a train is taken to run before a shared stop tells its delay.
    static let latestDelay: TimeInterval = 15 * 60
    /// The phone's speed is measured over this many seconds of fixes.
    static let speedWindow: TimeInterval = 8
    /// A fix older than this tells nothing.
    static let fixTimeout: TimeInterval = 60
    /// Apart for this long, a train loses what it had shared with the phone.
    static let separation: TimeInterval = 30
    /// The checking strip stays while the phone is this close to a line, and goes after a minute farther away.
    static let lineReach = 300.0
    static let feedTimeout: TimeInterval = 90
    /// A fix less precise than this is not used (Precise Location off gives 1 to 20 km).
    static let worstAccuracy = 100.0
    static let ignoreAfter: TimeInterval = 3 * 60
    /// The most trains one question offers.
    static let mostOffered = 2
    /// Trains this much later than the least late one that fits are not offered with it.
    static let closeDelays: TimeInterval = 5 * 60
    /// One shared stop and 3 min of moving together make the fourth check only when the train's next stop is this far
    /// away on the timetable (Oakville to Burlington on an express), and only on the feed's position.
    static let farApart: TimeInterval = 10 * 60

    enum Source: Equatable {
        case trainFeed
        case timetable
    }

    /// What the checking strip shows: the line the phone moves along, where from, and the train that fits best so far.
    struct Progress: Equatable {
        let line: Line?
        let since: Station?
        /// The train with the most shared stops; nil while none has one.
        let train: TrainCandidate?
        let stops: Int
    }

    /// The question: one or two trains, the station the phone moved with the first from and the stations it stopped with
    /// it at.
    struct Question: Equatable {
        let trains: [TrainCandidate]
        let since: Station?
        /// The first two shared stops, in order; one when the feed's train held the fourth check on 3 min of moving
        /// together.
        let stops: [Station]
        let askedAt: Date
        /// The last shared stop on the first train's plan: standing at another station means the question was ignored.
        let lastStop: Int
        /// Every train that fitted when it was asked: a No or an ignored question silences them all, so the matcher does not
        /// ask again about the next guess from the same evidence.
        let fitting: [TripKey]
    }

    enum State: Equatable {
        case idle
        case checking(Progress)
        case asking(Question)
    }

    private(set) var candidates: [TrainCandidate] = []
    private(set) var state = State.idle
    private(set) var silenced: Set<TripKey>
    private var evidence: [TripKey: Evidence] = [:]
    private var samples: [Sample] = []
    private var lastUpdate: Date?
    private var checking: Checking?
    /// After a No or an ignored question the strip stays hidden until another train shares a stop.
    private var isQuiet = false

    init(silenced: Set<TripKey> = []) {
        self.silenced = silenced
    }

    // MARK: Inputs

    /// The trains running now; a train still in the list keeps what it shared with the phone.
    mutating func setCandidates(_ list: [TrainCandidate]) {
        candidates = list.filter { $0.plan.track != nil && $0.plan.stops.count >= 2 }
        let keys = Set(candidates.map(\.trip))
        evidence = evidence.filter { keys.contains($0.key) }
    }

    /// A fix from the phone, at `time`.
    mutating func receive(_ fix: LocationFix, at time: Date) {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= Self.worstAccuracy else { return }
        samples.append(Sample(at: time, point: fix.coordinate))
        samples.removeAll { time.timeIntervalSince($0.at) > Self.fixTimeout }
    }

    /// No: the question's trains, and every train that fitted with them, are not asked about again. Returns the trains the
    /// question offered.
    @discardableResult
    mutating func decline() -> [TripKey] {
        guard case .asking(let question) = state else { return [] }
        let offered = question.trains.map(\.trip)
        silence(question.fitting + offered)
        return offered
    }

    /// Trains not to ask about again: a No, or a question left unanswered.
    mutating func silence(_ trips: [TripKey]) {
        silenced.formUnion(trips)
        for trip in trips { evidence[trip] = nil }
        isQuiet = true
        if case .asking = state { state = .idle }
        update(feed: [:], at: lastUpdate ?? .distantPast)
    }

    /// The four checks at `now`, with the train feed's latest positions (none until TT-179).
    mutating func update(feed: [TripKey: TrainPosition], at now: Date) {
        let dt = lastUpdate.map { min(max(now.timeIntervalSince($0), 0), 5) } ?? 0
        lastUpdate = now
        guard let phone = phoneMotion(at: now) else {
            if case .asking = state { return }
            checking = nil
            state = .idle
            return
        }
        if case .asking(let question) = state {
            if isIgnored(question, phone: phone, at: now) { decline() }
            return
        }

        var ready: [TrainCandidate] = []
        var fitting: [TrainCandidate] = []
        for candidate in candidates where !silenced.contains(candidate.trip) {
            guard let track = candidate.plan.track else { continue }
            var proof = evidence[candidate.trip] ?? Evidence()
            let result = check(candidate, track: track, phone: phone, feed: feed[candidate.trip], proof: &proof, dt: dt, now: now)
            evidence[candidate.trip] = proof
            if result.isReady { ready.append(candidate) }
            if result.fits { fitting.append(candidate) }
        }

        if !ready.isEmpty {
            // The timetable cannot tell apart trains that fit as well as the ready one, so the question offers the least late
            // of them (a local and an express a few minutes apart), never one that only fits by running much later.
            var delays: [TripKey: TimeInterval] = [:]
            for train in fitting { delays[train.trip] = delay(of: train) }
            let least = delays.values.min() ?? 0
            let close: [TrainCandidate] = fitting.filter { (delays[$0.trip] ?? 0) <= least + Self.closeDelays }
            let likely: [TrainCandidate] = close.sorted { a, b in
                let delayA = delays[a.trip] ?? 0
                let delayB = delays[b.trip] ?? 0
                return delayA != delayB ? delayA < delayB : a.departure < b.departure
            }
            let offered: [TrainCandidate] = Array(likely.prefix(Self.mostOffered)).sorted { $0.departure < $1.departure }
            let readyTrips = Set(ready.map(\.trip))
            if offered.contains(where: { readyTrips.contains($0.trip) }),
               let first = offered.first, let proof = evidence[first.trip] {
                state = .asking(Question(
                    trains: offered,
                    since: proof.since.map { first.plan.stops[$0].station },
                    stops: proof.sharedStops.prefix(2).map { first.plan.stops[$0].station },
                    askedAt: now,
                    lastStop: proof.sharedStops.last ?? 0,
                    fitting: fitting.map(\.trip)
                ))
                return
            }
        }
        let shown = progress(phone: phone, at: now)
        state = shown.map(State.checking) ?? .idle
    }

    // MARK: The checks

    private struct CheckResult {
        /// Shared enough, confidently enough, and moving together now: ask.
        var isReady = false
        /// The fourth check holds and the train is with the phone now.
        var fits = false
    }

    private func check(
        _ candidate: TrainCandidate, track: RidePlan.Track, phone: PhoneMotion, feed: TrainPosition?, proof: inout Evidence,
        dt: TimeInterval, now: Date
    ) -> CheckResult {
        let plan = candidate.plan
        let here = track.shape.project(phone.latest.point)
        let before = track.shape.project(phone.reference.point)
        let phoneSpeed = (here.along - before.along) / phone.span
        let train = trainPlace(candidate, track: track, feed: feed, proof: &proof, now: now)

        // 1 · Same place.
        let samePlace = here.off <= Self.placeRadius
            && here.along >= train.low - Self.placeRadius && here.along <= train.high + Self.placeRadius
        guard samePlace else {
            if proof.hasMoved {
                proof.apartSince = proof.apartSince ?? now
                if let apart = proof.apartSince, now.timeIntervalSince(apart) >= Self.separation { proof = Evidence() }
            }
            return CheckResult()
        }
        proof.apartSince = nil

        // 2 · Same way.
        var sameWay = phoneSpeed >= Self.minimumSpeed
        if train.source == .trainFeed {
            if let trainSpeed = train.speed, trainSpeed >= Self.minimumSpeed {
                sameWay = sameWay && abs(phoneSpeed - trainSpeed) <= Self.speedTolerance * max(phoneSpeed, trainSpeed)
            } else {
                sameWay = false
            }
        }
        if sameWay {
            if !proof.hasMoved {
                proof.hasMoved = true
                proof.since = track.stopDistances.lastIndex { $0 <= here.along + Self.platformHalfLength } ?? 0
            }
            if !proof.sharedStops.isEmpty { proof.togetherSinceStop += dt }
            if proof.completeAt != nil { proof.togetherSinceComplete += dt }
            proof.stopArrival = nil
        }

        // 3 · Stopped together, after moving together.
        if proof.hasMoved, phone.speed < Self.stoppedSpeed, here.off <= Self.platformMargin,
           let stop = nearestStop(to: here.along, distances: track.stopDistances),
           isTrainStanding(at: stop, plan: plan, track: track, train: train, proof: proof, now: now) {
            if !proof.sharedStops.contains(stop) {
                proof.sharedStops.append(stop)
                proof.togetherSinceStop = 0
                proof.stopArrival = now
            }
            // The timetable's delay, from the middle of the time they stood there against the middle of its own.
            if train.source == .timetable, proof.sharedStops.last == stop, let arrived = proof.stopArrival {
                let middle = arrived.addingTimeInterval(now.timeIntervalSince(arrived) / 2)
                let scheduled = plan.stops[stop].arrival.addingTimeInterval(
                    plan.stops[stop].departure.timeIntervalSince(plan.stops[stop].arrival) / 2
                )
                proof.delay = min(max(middle.timeIntervalSince(scheduled), 0), Self.latestDelay)
            }
        }

        // 4 · Twice, and the confidence rule. One stop and 3 min together count only on the feed, where stops are far apart.
        let isFarApart = proof.sharedStops.first.map { stop in
            stop + 1 < plan.stops.count && plan.stops[stop + 1].arrival.timeIntervalSince(plan.stops[stop].departure) >= Self.farApart
        } ?? false
        let twice = proof.sharedStops.count >= 2
            || (train.source == .trainFeed && proof.sharedStops.count == 1 && isFarApart && proof.togetherSinceStop >= Self.togetherTime)
        if twice, proof.completeAt == nil {
            proof.completeAt = proof.sharedStops.count
            proof.togetherSinceComplete = 0
        }
        let confident: Bool = switch train.source {
        case .trainFeed: twice
        case .timetable:
            proof.completeAt.map { proof.sharedStops.count > $0 || proof.togetherSinceComplete >= Self.togetherTime } ?? false
        }
        return CheckResult(isReady: confident && sameWay, fits: twice)
    }

    /// Where the train is along its track: a point from a fresh feed position, else the stretch the timetable allows.
    private func trainPlace(
        _ candidate: TrainCandidate, track: RidePlan.Track, feed: TrainPosition?, proof: inout Evidence, now: Date
    ) -> TrainPlace {
        if let feed, now.timeIntervalSince(feed.reportedAt) < Self.feedTimeout {
            let along = track.shape.project(feed.coordinate).along
            if proof.feed.last?.at != feed.reportedAt {
                proof.feed.append(FeedSample(along: along, at: feed.reportedAt))
                if proof.feed.count > 2 { proof.feed.removeFirst() }
            }
            var speed: Double?
            if proof.feed.count == 2 {
                let span = proof.feed[1].at.timeIntervalSince(proof.feed[0].at)
                if span > 0 { speed = (proof.feed[1].along - proof.feed[0].along) / span }
            }
            // The position was reported a few seconds ago: carried on at the train's speed to now.
            let current = along + max(speed ?? 0, 0) * now.timeIntervalSince(feed.reportedAt)
            return TrainPlace(low: current, high: current, source: .trainFeed, speed: speed)
        }
        let plan = candidate.plan
        let earliest = proof.delay.map { $0 - Self.timetableSlack } ?? -Self.timetableSlack
        let latest = proof.delay.map { $0 + Self.timetableSlack } ?? Self.latestDelay
        return TrainPlace(
            low: plan.scheduledAlong(at: now.addingTimeInterval(-latest)),
            high: plan.scheduledAlong(at: now.addingTimeInterval(-earliest)),
            source: .timetable,
            speed: nil
        )
    }

    private func isTrainStanding(
        at stop: Int, plan: RidePlan, track: RidePlan.Track, train: TrainPlace, proof: Evidence, now: Date
    ) -> Bool {
        switch train.source {
        case .trainFeed:
            guard let speed = train.speed else { return false }
            return speed < Self.stoppedSpeed
                && abs(train.low - track.stopDistances[stop]) <= Self.platformHalfLength + Self.platformMargin
        case .timetable:
            let opens = plan.stops[stop].arrival.addingTimeInterval(-Self.timetableSlack)
            let closes = plan.stops[stop].departure.addingTimeInterval(Self.timetableSlack)
            if let delay = proof.delay {
                let time = now.addingTimeInterval(-delay)
                return time >= opens && time <= closes
            }
            return now >= opens && now <= closes.addingTimeInterval(Self.latestDelay)
        }
    }

    /// The stop whose platform the phone is on.
    private func nearestStop(to along: Double, distances: [Double]) -> Int? {
        guard let nearest = distances.indices.min(by: { abs(distances[$0] - along) < abs(distances[$1] - along) }),
              abs(distances[nearest] - along) <= Self.platformHalfLength + Self.platformMargin else { return nil }
        return nearest
    }

    // MARK: The strip and the question

    /// The checking strip: from the moment the phone moves faster than 25 km/h on a line until it has been 300 m from
    /// every line for a minute.
    private mutating func progress(phone: PhoneMotion, at now: Date) -> Progress? {
        let open = candidates.filter { !silenced.contains($0.trip) }
        let near = open.compactMap { candidate -> (TrainCandidate, TrackShape.Projection)? in
            guard let shape = candidate.plan.track?.shape else { return nil }
            let projection = shape.project(phone.latest.point)
            return projection.off <= Self.lineReach ? (candidate, projection) : nil
        }
        if var current = checking {
            if near.isEmpty {
                if now.timeIntervalSince(current.lastNear) >= 60 { checking = nil }
            } else {
                current.lastNear = now
                checking = current
            }
        } else if phone.speed >= Self.minimumSpeed,
                  let match = near.first(where: { $0.1.off <= Self.placeRadius && movesForward($0.0, phone: phone) }) {
            let distances = match.0.plan.track?.stopDistances ?? []
            let since = distances.lastIndex { $0 <= match.1.along + Self.platformHalfLength } ?? 0
            checking = Checking(line: match.0.route.line, since: match.0.plan.stops[since].station, lastNear: now)
        }
        guard let current = checking else { return nil }

        // The train the phone moves with that has shared the most stops.
        var leading: (candidate: TrainCandidate, proof: Evidence)?
        for candidate in open {
            guard let proof = evidence[candidate.trip], proof.hasMoved, proof.apartSince == nil else { continue }
            if let best = leading, !Self.leads(proof, candidate, over: best.proof, best.candidate) { continue }
            leading = (candidate, proof)
        }
        let stops = leading?.proof.sharedStops.count ?? 0
        if isQuiet {
            guard stops > 0 else { return nil }
            isQuiet = false
        }
        var since = current.since
        if let leading, let index = leading.proof.since {
            since = leading.candidate.plan.stops[index].station
        }
        return Progress(line: current.line, since: since, train: stops > 0 ? leading?.candidate : nil, stops: stops)
    }

    /// More shared stops leads; on a tie, the less late train, then the earlier one.
    private static func leads(_ proof: Evidence, _ train: TrainCandidate, over other: Evidence, _ otherTrain: TrainCandidate) -> Bool {
        if proof.sharedStops.count != other.sharedStops.count { return proof.sharedStops.count > other.sharedStops.count }
        let delay = proof.delay ?? 0
        let otherDelay = other.delay ?? 0
        if delay != otherDelay { return delay < otherDelay }
        return train.departure < otherTrain.departure
    }

    /// How late the timetable takes the train to run, from the stops it shared with the phone; 0 on the feed.
    private func delay(of candidate: TrainCandidate) -> TimeInterval {
        evidence[candidate.trip]?.delay ?? 0
    }

    private func movesForward(_ candidate: TrainCandidate, phone: PhoneMotion) -> Bool {
        guard let shape = candidate.plan.track?.shape else { return false }
        return (shape.project(phone.latest.point).along - shape.project(phone.reference.point).along) / phone.span >= Self.minimumSpeed
    }

    /// Unanswered for 3 min, or the phone stands at another station.
    private func isIgnored(_ question: Question, phone: PhoneMotion, at now: Date) -> Bool {
        if now.timeIntervalSince(question.askedAt) >= Self.ignoreAfter { return true }
        guard let first = question.trains.first, let track = first.plan.track, phone.speed < Self.stoppedSpeed else { return false }
        let here = track.shape.project(phone.latest.point)
        guard here.off <= Self.platformMargin, let stop = nearestStop(to: here.along, distances: track.stopDistances) else { return false }
        return stop != question.lastStop
    }

    // MARK: The phone's motion

    /// The phone's latest place and a fix about 8 s before it; nil without a fix in the last minute or before there are
    /// two to measure between.
    private func phoneMotion(at now: Date) -> PhoneMotion? {
        guard let latest = samples.last, now.timeIntervalSince(latest.at) <= Self.fixTimeout else { return nil }
        let cutoff = now.addingTimeInterval(-Self.speedWindow)
        // No new fix within the window means the phone has not moved: the latest fix is its own reference.
        let reference = samples.last { $0.at <= cutoff }
            ?? samples.first.flatMap { oldest in
                oldest.at < latest.at && now.timeIntervalSince(oldest.at) >= Self.speedWindow / 2 ? oldest : nil
            }
        guard let reference else { return nil }
        // Between two fixes the speed is theirs; a fix that is its own reference has the phone standing since.
        let span = max(reference.at < latest.at ? latest.at.timeIntervalSince(reference.at) : now.timeIntervalSince(reference.at), 1)
        return PhoneMotion(
            latest: latest,
            reference: reference,
            span: span,
            speed: TrackShape.distance(reference.point, latest.point) / span
        )
    }
}

private struct Sample {
    let at: Date
    let point: GeoPoint
}

private struct PhoneMotion {
    let latest: Sample
    let reference: Sample
    /// Seconds from the reference fix to now.
    let span: TimeInterval
    /// Metres a second, either way.
    let speed: Double
}

private struct TrainPlace {
    /// Metres along the track: the feed's one place, or the stretch the timetable allows.
    let low: Double
    let high: Double
    let source: TrainMatcher.Source
    /// Metres a second along the track, from the feed's last two positions.
    let speed: Double?
}

private struct FeedSample {
    let along: Double
    let at: Date
}

/// What one train has shared with the phone so far.
private struct Evidence {
    /// Checks 1 and 2 have held together: the phone has moved with it.
    var hasMoved = false
    /// The stop the phone moved with it from.
    var since: Int?
    var sharedStops: [Int] = []
    /// Seconds late, learned at the shared stops (timetable only).
    var delay: TimeInterval?
    /// When the phone and the train began standing at the latest shared stop.
    var stopArrival: Date?
    var togetherSinceStop: TimeInterval = 0
    /// Shared stops when the fourth check first held, for the timetable's confidence rule.
    var completeAt: Int?
    var togetherSinceComplete: TimeInterval = 0
    var apartSince: Date?
    var feed: [FeedSample] = []
}

private struct Checking {
    let line: Line?
    let since: Station?
    var lastNear: Date
}

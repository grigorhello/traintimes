import Foundation

/// The wrong train warning, part 2 (TT-251, D127): whether the phone left the rider's station in another train that does
/// not go to the rider's stop. Pure, beside `AutoRideRule`, whose proof it runs on the other trains leaving the station:
/// `WrongTrainCheck` feeds it the phone's good fixes, the candidates, GO's timed positions and the stops each train still
/// has ahead, and asks for a verdict at each look. Its numbers are its own constants, and `AutoRideRule`'s where Y1 and Y2
/// are named. T is the rider's train, O their station, D their stop, L T's expected departure from O, X another train.
///
/// All four, then it is `wrong`:
/// 1. **You left from your station.** Y1 for O (a covered station: the covered form, from X's departure), then Y2 on X's
///    own track from O's place on it (covered: 600 m of travel within 120 s of the first fix after the roof). On a ride
///    started after T left with no fix at O, the tap stands in for Y1.
/// 2. **With another train.** Three of X's timed positions in a row, 20 s or more apart, each 90 s old at most when read:
///    at each one's own time the phone within 400 m of it along X's track and the gap changing by 100 m at most (500 m and
///    150 m above 60 km/h). Exactly one train may match, a train to D included; with two, it waits.
/// 3. **Yours is somewhere else.** T's last two timed positions 800 m or more from the phone at their own times (450 m
///    along a shared track), plus 45 s of T's speed while it moves; or T still stands at O (two timed positions within
///    350 m of it and its fresh update still lists O); or the phone parted from T's track by 250 m; or T is not in the feed:
///    X matched for 60 s, no position of T from the last 2 min within 800 m of the phone, and X and T leave O 2 min or more
///    apart. Never the clock, an untimed position or an old one.
/// 4. **Not to your stop.** X's fresh update does not list D, and the timetable agrees. No fresh update: no warning.
///
/// The reason is the first that fits: `wrongWay` (X runs back along T's line), `otherLine` (the phone parted from T's
/// track), `skipsStop`. On a ride started by a tap there is one proof with no feed, the wrong way by the track: after the
/// phone was at O, Y2 turned round on T's own track, each step between 25 and 160 km/h, 600 m backwards in all (never where
/// T's track starts at O). `withTrain` is Y3 for T, with no train leaving within 180 s on the same track the same way left
/// unresolved (Y4). Quiet: a train that also stops at D, T cancelled or skipping O or D, a phone that stands still, no fresh
/// update for X, untimed positions.
struct WrongTrainRule {
    // MARK: Numbers

    /// Fixes and positions are kept this long.
    static let keeps: TimeInterval = 5 * 60
    /// Condition 2.
    static let matchCount = 3
    static let matchSpan: TimeInterval = 20
    static let matchMaxAge: TimeInterval = 90
    static let matchGap = 400.0
    static let matchDrift = 100.0
    static let fastSpeed = 60.0 / 3.6
    static let fastGap = 500.0
    static let fastDrift = 150.0
    /// Condition 1 at a covered station: travel from the first fix after the roof.
    static let coveredTravel = 600.0
    static let coveredWithin: TimeInterval = 120
    /// Condition 3: T elsewhere.
    static let elsewhereFar = 800.0
    static let elsewhereAlong = 450.0
    static let elsewhereLead: TimeInterval = 45
    /// Condition 3: T still standing at O.
    static let standsRadius = 350.0
    /// Condition 3: the phone off T's track.
    static let partedOff = 250.0
    /// Condition 3: T not in the feed.
    static let missingMatch: TimeInterval = 60
    static let missingLook: TimeInterval = 120
    static let missingFar = 800.0
    static let missingApart: TimeInterval = 120
    /// Trains leaving O this close to T on the same track the same way are its twins.
    static let twinWindow: TimeInterval = 180
    /// Same way: X's point this far past O within `sameWayOff` of T's track ahead of O.
    static let sameWayLead = 600.0
    static let sameWayOff = 150.0
    /// The wrong way by the track.
    static let backMaxSpeed = 160.0 / 3.6
    static let backPast = 600.0
    /// The station behind O is a station of T's line this close to T's track (`RidePlan.onTrackDistance`).
    static let behindReach = 750.0
    /// A candidate is weighed while one of its positions is this close to the phone.
    static let nearby = 1500.0

    // MARK: Types

    /// How the rider is tied to T.
    enum Tie: Sendable, Equatable {
        /// An alert, no ride.
        case alert
        /// A ride started by a tap before T left (or at O).
        case rideAtOrigin
        /// A ride started by a tap after T left.
        case rideAfterLeft

        var isRide: Bool { self != .alert }
    }

    struct Finding: Sendable, Equatable {
        /// X; nil for the wrong way by the track, which knows no train.
        let trip: TripKey?
        let reason: WrongTrainReason
        let evidence: WrongTrainEvidence
        let nextStopId: String?
        let nextStopTime: Date?
        /// Whole seconds from the phone's first moving fix to the verdict.
        let seconds: Int
    }

    enum Verdict: Sendable, Equatable {
        case quiet
        /// The phone moves with a candidate but the proof is not complete; `since` is its first moving fix.
        case following(since: Date)
        case withTrain
        case wrong(Finding)
    }

    struct Moment: Sendable {
        var now: Date
        /// L: T's expected departure from O, as last read.
        var departure: Date
    }

    /// A good fix, kept `keeps` and placed on each candidate's track when it is weighed.
    private struct Raw {
        let at: Date
        let point: GeoPoint
        let isStationary: Bool
    }

    /// One of GO's positions.
    private struct Sighting {
        let reportedAt: Date
        let readAt: Date
        let point: GeoPoint
        let hasVehicleTime: Bool

        var isUsable: Bool { hasVehicleTime && readAt.timeIntervalSince(reportedAt) <= WrongTrainRule.matchMaxAge }
    }

    /// Condition 2 for one candidate.
    private struct Match {
        /// Three positions in a row agree.
        var matched = false
        /// When the match first held, at the third position of the run.
        var since: Date?
        /// The latest position.
        var latest: Date?
        /// One position at least is within the gap of the phone.
        var near = false
    }

    // MARK: State

    let ride: Ride
    /// The check changes it when a ride starts by a tap on T while it watches the alert.
    var tie: Tie
    /// The good fixes on T's track (Y1, Y3, the wrong way by the track, "parted").
    private var own: PlacedFixes
    private var raw: [Raw] = []
    private var candidates: [WrongTrainCandidate] = []
    private var sightings: [String: [Sighting]] = [:]
    private var stops: [String: LiveStopsAhead] = [:]
    /// Each candidate's expected departure from O as its fresh TripUpdate last gave it (kept once O drops out of the
    /// stops ahead): a late train is weighed at its real time, not its scheduled one.
    private var liveDepartures: [String: Date] = [:]
    /// The nearest station of T's line behind O on T's track, the wrong way by the track's next station.
    let behind: Station?

    /// Nil for a plan with no track: T cannot be checked. `lineStations` are T's line's stations with their places.
    init?(plan: RidePlan, ride: Ride, tie: Tie, lineStations: [Station] = [], reportsStationary: Bool) {
        guard let track = plan.track, let first = track.stopDistances.first else { return nil }
        self.ride = ride
        self.tie = tie
        own = PlacedFixes(shape: track.shape, originAlong: first, reportsStationary: reportsStationary)
        behind = lineStations
            .compactMap { station -> (Station, Double)? in
                guard station.id != ride.originId, let place = station.place else { return nil }
                let projection = track.shape.project(place)
                guard projection.off <= Self.behindReach, projection.along < first else { return nil }
                return (station, projection.along)
            }
            .max { $0.1 < $1.1 }?.0
    }

    // MARK: Observations

    /// A fix from the phone as it came at `now`; only good ones count. Fixes and positions older than `keeps` go.
    mutating func observe(_ fix: LocationFix, at now: Date) {
        guard let mark = own.add(fix, at: now) else { return }
        raw.append(Raw(at: mark.at, point: mark.point, isStationary: mark.isStationary))
        let from = now.addingTimeInterval(-Self.keeps)
        raw.removeAll { $0.at < from }
        own.drop(before: from)
        for (trip, list) in sightings { sightings[trip] = list.filter { $0.readAt >= from } }
    }

    /// The trains leaving O (`WrongTrainTimetable.candidates(leaving:on:)`); T and trains with no stop after O are left out.
    mutating func setCandidates(_ trains: [WrongTrainCandidate]) {
        candidates = trains.filter { $0.trip.tripId != ride.tripId && !$0.stopsAfter.isEmpty }
    }

    /// GO's position of a trip, T's or a candidate's, read at `readAt`. A position already seen is dropped.
    mutating func observe(_ position: TrainPosition, of tripId: String, readAt: Date) {
        var list = sightings[tripId] ?? []
        guard !list.contains(where: { $0.reportedAt == position.reportedAt && $0.hasVehicleTime == position.hasVehicleTime })
        else { return }
        list.append(Sighting(
            reportedAt: position.reportedAt, readAt: readAt, point: position.coordinate, hasVehicleTime: position.hasVehicleTime
        ))
        list.sort { $0.reportedAt < $1.reportedAt }
        list.removeAll { readAt.timeIntervalSince($0.readAt) > Self.keeps }
        sightings[tripId] = list
    }

    /// The live feed's stops ahead for a trip, T's or a candidate's; nil when the feed has none.
    mutating func setStops(_ live: LiveStopsAhead?, of tripId: String) {
        stops[tripId] = live
        if let live, live.isFresh, let time = live.stops.first(where: { $0.id == ride.originId })?.time {
            liveDepartures[tripId] = time
        }
    }

    /// A candidate's departure from O: the feed's expected time when it gave one, else the timetable's.
    private func departure(of candidate: WrongTrainCandidate) -> Date {
        liveDepartures[candidate.trip.tripId] ?? candidate.departure
    }

    /// The candidates the check should read the stops ahead of: those with a position near the phone.
    func weighed() -> [WrongTrainCandidate] {
        candidates.filter(isNear)
    }

    /// Whether the phone has a moving fix on T's track or a candidate's (the check reads the fast feed from then on).
    var hasMoved: Bool {
        raw.contains { !$0.isStationary } && (own.tp() != nil || own.tp(.backward) != nil || !weighed().isEmpty)
    }

    /// When the phone was last seen at O (its stationary fix held), nil if never.
    func seenAtStation(now: Date) -> Date? { own.seenAtStation(now: now) }

    /// The phone's latest good fix as the check reads it: metres from O's point, whether it lies 150 m or less off T's track
    /// or a candidate's, its straight-line speed over the last `AutoRideRule.speedSpan` (nil with no earlier fix in it),
    /// whether it was stationary, and whether the phone was ever seen at O.
    struct LastFix: Equatable {
        let at: Date
        let fromOrigin: Double
        let onTrack: Bool
        let speed: Double?
        let isStationary: Bool
        let wasAtStation: Bool
    }

    func lastFix() -> LastFix? {
        guard let last = own.marks.last else { return nil }
        let onTrack = last.off <= AutoRideRule.leaveOff
            || candidates.contains { $0.shape.project(last.point).off <= AutoRideRule.leaveOff }
        let earliest = raw.first { last.at.timeIntervalSince($0.at) <= AutoRideRule.speedSpan && $0.at < last.at }
        let speed = earliest.map { TrackShape.distance($0.point, last.point) / last.at.timeIntervalSince($0.at) }
        return LastFix(
            at: last.at, fromOrigin: last.fromOrigin, onTrack: onTrack, speed: speed, isStationary: last.isStationary,
            wasAtStation: own.atStation != nil
        )
    }

    // MARK: The verdict

    func verdict(at moment: Moment) -> Verdict {
        if isQuietForT { return .quiet }
        if hasTrain(moment) { return .withTrain }
        if let finding = wrongWayByTrack(moment) { return .wrong(finding) }

        var matches: [(candidate: WrongTrainCandidate, fixes: PlacedFixes, tp: Date, match: Match)] = []
        var following: Date?
        for candidate in weighed() {
            let fixes = placed(on: candidate)
            guard let tp = fixes.tp(), let covered = leftStation(moment, on: fixes, candidate: candidate) else { continue }
            let match = self.match(candidate, fixes: fixes, from: tp)
            let servesStop = servesDestination(candidate)
            if !servesStop, match.near, let last = fixes.marks.last,
               last.along >= AutoRideRule.leaveAlong, last.off <= AutoRideRule.leaveOff {
                following = min(following ?? tp, tp)
            }
            guard match.matched, leaves(fixes, from: tp, covered: covered.first) else { continue }
            matches.append((candidate, fixes, tp, match))
        }
        guard matches.count <= 1 else { return following.map { .following(since: $0) } ?? .quiet }
        if let found = matches.first {
            if servesDestination(found.candidate) { return .quiet }
            if isElsewhere(moment, from: found.tp, candidate: found.candidate, fixes: found.fixes, match: found.match),
               let finding = finding(moment, found.candidate, fixes: found.fixes, from: found.tp) {
                return .wrong(finding)
            }
            return .following(since: min(following ?? found.tp, found.tp))
        }
        return following.map { .following(since: $0) } ?? .quiet
    }

    // MARK: Quiet

    /// T cancelled, or O or D skipped for T, as the fresh feed says.
    private var isQuietForT: Bool {
        guard let live = stops[ride.tripId], live.isFresh else { return false }
        return live.isCancelled || live.skipped.contains(ride.originId) || live.skipped.contains(ride.destinationId)
    }

    /// The train also stops at D: the timetable lists it after O, or its fresh update does.
    private func servesDestination(_ candidate: WrongTrainCandidate) -> Bool {
        if candidate.stopsAfter.contains(ride.destinationId) { return true }
        guard let live = stops[candidate.trip.tripId], live.isFresh else { return false }
        return live.lists(ride.destinationId)
    }

    // MARK: Condition 1

    /// The candidate's fixes: the kept good fixes placed on its track from O's place on it.
    private func placed(on candidate: WrongTrainCandidate) -> PlacedFixes {
        var fixes = PlacedFixes(shape: candidate.shape, originAlong: candidate.originAlong, reportsStationary: own.reportsStationary)
        for fix in raw { fixes.add(fix.point, at: fix.at, isStationary: fix.isStationary) }
        return fixes
    }

    private var isCovered: Bool { AutoRideRule.coveredStations.contains(ride.originId) }

    /// How Y1 held.
    private enum AtStation {
        /// A fix at O, or the tap.
        case seen
        /// The covered form, from this first fix after the roof.
        case covered(PlacedFixes.Mark)

        var first: PlacedFixes.Mark? {
            guard case .covered(let mark) = self else { return nil }
            return mark
        }
    }

    /// Y1 for O, nil when it does not hold.
    private func leftStation(_ moment: Moment, on fixes: PlacedFixes, candidate: WrongTrainCandidate) -> AtStation? {
        if isCovered {
            if let first = fixes.coveredStart(after: departure(of: candidate).addingTimeInterval(-AutoRideRule.coveredLead)) {
                return .covered(first)
            }
        } else if let seen = own.seenAtStation(now: moment.now),
                  seen >= moment.departure.addingTimeInterval(-AutoRideRule.stationLead) {
            return .seen
        }
        // A ride started after T left with no fix at O: the tap stands in.
        if tie == .rideAfterLeft, own.atStation == nil { return .seen }
        return nil
    }

    /// Y2 on the candidate's track: 600 m past O, or at a covered station 600 m of travel within 120 s of the first fix
    /// after the roof.
    private func leaves(_ fixes: PlacedFixes, from tp: Date, covered first: PlacedFixes.Mark?) -> Bool {
        guard let first else { return fixes.leaves(from: tp) { $0.along >= AutoRideRule.leavePast } }
        return fixes.leaves(from: tp) { mark in
            mark.along - first.along >= Self.coveredTravel && mark.at.timeIntervalSince(first.at) <= Self.coveredWithin
        }
    }

    // MARK: Condition 2

    private func isNear(_ candidate: WrongTrainCandidate) -> Bool {
        guard let latest = raw.last else { return false }
        return (sightings[candidate.trip.tripId] ?? []).contains { sighting in
            let phone = own.phonePoint(at: sighting.reportedAt) ?? latest.point
            return TrackShape.distance(phone, sighting.point) <= Self.nearby
        }
    }

    private func match(_ candidate: WrongTrainCandidate, fixes: PlacedFixes, from tp: Date) -> Match {
        // Its usable positions from Tp on with the phone's gap at each one's own time, newest first, 20 s apart or more.
        let usable = (sightings[candidate.trip.tripId] ?? []).compactMap { sighting -> (at: Date, along: Double, gap: Double)? in
            guard sighting.isUsable, sighting.reportedAt >= tp, let phone = fixes.phoneAlong(at: sighting.reportedAt) else {
                return nil
            }
            let along = candidate.shape.project(sighting.point).along - candidate.originAlong
            return (sighting.reportedAt, along, phone - along)
        }
        var result = Match()
        result.near = usable.contains { abs($0.gap) <= Self.fastGap }
        var spaced: [(at: Date, along: Double, gap: Double)] = []
        for position in usable.reversed() where spaced.last.map({ $0.at.timeIntervalSince(position.at) >= Self.matchSpan }) ?? true {
            spaced.append(position)
        }
        guard let newest = spaced.first else { return result }
        result.latest = newest.at
        // The run of positions that agree, from the newest back.
        var run = 1
        while run < spaced.count {
            let later = spaced[run - 1], earlier = spaced[run]
            let speed = (later.along - earlier.along) / later.at.timeIntervalSince(earlier.at)
            let fast = speed > Self.fastSpeed
            let gap = fast ? Self.fastGap : Self.matchGap, drift = fast ? Self.fastDrift : Self.matchDrift
            guard abs(later.gap) <= gap, abs(earlier.gap) <= gap, abs(later.gap - earlier.gap) <= drift else { break }
            run += 1
        }
        if run >= Self.matchCount {
            result.matched = true
            result.since = spaced[run - Self.matchCount].at
        }
        return result
    }

    // MARK: Condition 3

    private func isElsewhere(
        _ moment: Moment, from tp: Date, candidate: WrongTrainCandidate, fixes: PlacedFixes, match: Match
    ) -> Bool {
        if isFarFromT(from: tp) || standsAtOrigin(from: tp) || hasParted(fixes, from: tp) { return true }
        // T is not in the feed.
        guard let since = match.since, let latest = match.latest, latest.timeIntervalSince(since) >= Self.missingMatch,
              abs(departure(of: candidate).timeIntervalSince(moment.departure)) >= Self.missingApart else { return false }
        let recent = (sightings[ride.tripId] ?? []).filter { moment.now.timeIntervalSince($0.readAt) <= Self.missingLook }
        let fallback = raw.last?.point
        return !recent.contains { sighting in
            guard let phone = own.phonePoint(at: sighting.reportedAt) ?? fallback else { return true }
            return TrackShape.distance(phone, sighting.point) < Self.missingFar
        }
    }

    /// T's last two timed positions from Tp on, each 90 s old at most when read.
    private func lastTwoOfT(from tp: Date) -> (Sighting, Sighting)? {
        let usable = (sightings[ride.tripId] ?? []).filter { $0.isUsable && $0.reportedAt >= tp }
        guard usable.count >= 2 else { return nil }
        return (usable[usable.count - 2], usable[usable.count - 1])
    }

    /// T's last two timed positions 800 m or more from the phone at their own times (450 m along a shared track), plus
    /// 45 s of T's speed while it moves.
    private func isFarFromT(from tp: Date) -> Bool {
        guard let (a, b) = lastTwoOfT(from: tp) else { return false }
        let span = b.reportedAt.timeIntervalSince(a.reportedAt)
        guard span > 0 else { return false }
        let speed = abs(own.shape.project(b.point).along - own.shape.project(a.point).along) / span
        let lead = speed > AutoRideRule.standSpeed ? speed * Self.elsewhereLead : 0
        return [a, b].allSatisfy { sighting in
            guard let phone = own.phonePoint(at: sighting.reportedAt) else { return false }
            let placed = own.shape.project(phone)
            if placed.off <= AutoRideRule.leaveOff {
                return abs(placed.along - own.shape.project(sighting.point).along) >= Self.elsewhereAlong + lead
            }
            return TrackShape.distance(phone, sighting.point) >= Self.elsewhereFar + lead
        }
    }

    /// T still stands at O: its last two timed positions within 350 m of O, and its fresh update still lists O.
    private func standsAtOrigin(from tp: Date) -> Bool {
        guard let (a, b) = lastTwoOfT(from: tp), let live = stops[ride.tripId], live.isFresh, !live.isCancelled,
              live.lists(ride.originId) else { return false }
        return [a, b].allSatisfy { TrackShape.distance($0.point, own.originPoint) <= Self.standsRadius }
    }

    /// A good fix past O on X's track, 250 m or more off T's track ahead of O.
    private func hasParted(_ fixes: PlacedFixes, from tp: Date) -> Bool {
        fixes.marks.contains { mark in
            mark.at >= tp && mark.along >= AutoRideRule.leaveAlong && mark.off <= AutoRideRule.leaveOff
                && own.shape.project(mark.point, from: own.originAlong).off >= Self.partedOff
        }
    }

    // MARK: Condition 4 and the finding

    private func finding(_ moment: Moment, _ candidate: WrongTrainCandidate, fixes: PlacedFixes, from tp: Date) -> Finding? {
        guard let live = stops[candidate.trip.tripId], live.isFresh, !live.isCancelled, !live.stops.isEmpty,
              !live.lists(ride.destinationId), !candidate.stopsAfter.contains(ride.destinationId) else { return nil }
        let reason: WrongTrainReason
        if goesBack(candidate) {
            reason = .wrongWay
        } else if hasParted(fixes, from: tp) {
            reason = .otherLine
        } else {
            reason = .skipsStop
        }
        let next = live.stops.first { $0.id != ride.originId }
        return Finding(
            trip: candidate.trip, reason: reason, evidence: .feed, nextStopId: next?.id, nextStopTime: next?.time,
            seconds: Int(moment.now.timeIntervalSince(tp))
        )
    }

    /// X runs back along T's line: its point past O lies on T's track behind O.
    private func goesBack(_ candidate: WrongTrainCandidate) -> Bool {
        let projection = own.shape.project(candidate.shape.point(at: candidate.originAlong + Self.sameWayLead))
        return projection.off <= Self.sameWayOff && projection.along < own.originAlong - AutoRideRule.leaveAlong
    }

    /// X runs on T's track the same way from O.
    private func runsSameWay(_ candidate: WrongTrainCandidate) -> Bool {
        let point = candidate.shape.point(at: candidate.originAlong + Self.sameWayLead)
        return own.shape.project(point, from: own.originAlong).off <= Self.sameWayOff
    }

    // MARK: The wrong way by the track

    private func wrongWayByTrack(_ moment: Moment) -> Finding? {
        guard tie.isRide, own.originAlong >= Self.backPast, let seen = own.seenAtStation(now: moment.now),
              seen >= moment.departure.addingTimeInterval(-AutoRideRule.stationLead), let tp = own.tp(.backward),
              own.leaves(from: tp, direction: .backward, speedFrom: 0, maxSpeed: Self.backMaxSpeed, reached: { -$0.along >= Self.backPast })
        else { return nil }
        return Finding(
            trip: nil, reason: .wrongWay, evidence: .track, nextStopId: behind?.id, nextStopTime: nil,
            seconds: Int(moment.now.timeIntervalSince(tp))
        )
    }

    // MARK: With your train

    /// Y3 for T from its Tp, and no twin left unresolved.
    private func hasTrain(_ moment: Moment) -> Bool {
        guard let tp = own.tp(), agrees(from: tp) else { return false }
        return candidates.allSatisfy { candidate in
            guard abs(departure(of: candidate).timeIntervalSince(moment.departure)) <= Self.twinWindow, runsSameWay(candidate) else {
                return true
            }
            return isResolved(candidate, from: tp)
        }
    }

    /// The phone's gap to T's usable positions from Tp on, along T's track.
    private func gapsToT(from tp: Date) -> [(at: Date, gap: Double)] {
        (sightings[ride.tripId] ?? []).compactMap { sighting in
            guard sighting.isUsable, sighting.reportedAt >= tp, let phone = own.phoneAlong(at: sighting.reportedAt) else {
                return nil
            }
            return (sighting.reportedAt, phone - (own.shape.project(sighting.point).along - own.originAlong))
        }
    }

    /// `AutoRideRule`'s Y3 for T.
    private func agrees(from tp: Date) -> Bool {
        let gaps = gapsToT(from: tp).filter { abs($0.gap) <= AutoRideRule.feedGap }
        for (index, a) in gaps.enumerated() {
            for b in gaps[(index + 1)...] where b.at.timeIntervalSince(a.at) >= AutoRideRule.feedSpan {
                if abs(b.gap - a.gap) <= AutoRideRule.feedDrift { return true }
            }
        }
        return false
    }

    /// `AutoRideRule`'s Y4 for a twin: the phone parted from its track, or its position is far from the phone, or behind or
    /// ahead of it along T's track at two positions 20 s apart.
    private func isResolved(_ twin: WrongTrainCandidate, from tp: Date) -> Bool {
        let parted = own.marks.contains { mark in
            mark.at >= tp && mark.along >= AutoRideRule.leaveAlong && mark.off <= AutoRideRule.rivalTrack
                && twin.shape.project(mark.point, from: twin.originAlong).off >= AutoRideRule.rivalParted
        }
        if parted { return true }
        let fresh = (sightings[twin.trip.tripId] ?? []).filter {
            $0.readAt.timeIntervalSince($0.reportedAt) <= AutoRideRule.feedMaxAge && $0.reportedAt >= tp
        }
        for sighting in fresh {
            guard let phone = own.phonePoint(at: sighting.reportedAt) else { continue }
            if TrackShape.distance(phone, sighting.point) >= AutoRideRule.rivalAway { return true }
        }
        let apart = fresh.filter { sighting in
            guard let phone = own.phoneAlong(at: sighting.reportedAt) else { return false }
            return abs(phone - (own.shape.project(sighting.point).along - own.originAlong)) > AutoRideRule.feedGap
        }
        guard let first = apart.first, let last = apart.last else { return false }
        return last.reportedAt.timeIntervalSince(first.reportedAt) >= AutoRideRule.feedSpan
    }
}

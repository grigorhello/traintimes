import Foundation

/// Rides start by themselves, part 1 (TT-242, D120): whether the phone left the rider's station with the alerted train.
/// Pure: `AutoRideWatch` feeds it the phone's fixes and GO's positions of the trip and of its rivals as they come, and asks
/// for a verdict on each fix and each look. Its numbers are its own constants, never `TrainMatcher`'s.
///
/// All five must hold for a start:
/// - **Y1 · At the station.** A good fix within 300 m of the origin point, measured at or after L − 15 min; a stationary
///   fix there counts while it is the latest, up to `RideEngine.stationaryTimeout`. At a covered station (Union's shed),
///   and for a watch armed at or after L, the covered form: the first good fix after L − 60 s is 150 m or less off the
///   track, 300 to 1,500 m along, and the next good fix is farther along.
/// - **Y2 · Leaves with it.** From Tp (the first good fix 300 m or more along) for 45 s: every good fix 150 m or less off
///   the track, their median 60 m or less, 25 km/h or more from 30 s on, no standstill under 2 m/s longer than 10 s (a
///   pause counts: the stationary update on iOS 18, a gap over 10 s on iOS 17; a gap over 20 s always), and 600 m or more
///   past the stop at the end. A failure starts the 45 s again.
/// - **Y3 · GO agrees.** Two positions of the trip with their vehicle's own time, at or after Tp, 20 s or more apart, each
///   90 s old or less when read, where the phone (interpolated to that moment) and the train are within 400 m along the
///   track and that gap changes by 100 m or less between the two.
/// - **Y4 · No rival.** No other trip leaving within 180 s on the same track, until the tracks part, its position is
///   800 m or more from the phone, or it stays more than 400 m from the phone at two positions 20 s apart while Y3 holds.
/// - **Y5 · Room.** 5 min or more to the rider's stop, and no answer yet.
///
/// Not on board, after the train left, on fresh good fixes only: the phone stayed within 300 m of the station for 60 s
/// (or a held stationary fix there) while GO places the train 800 m or more along; or it was 300 m or more off the track
/// for 60 s; or it was never at the station and, as the train left, more than 1,500 m from it and 300 m off the track.
///
/// No verdict before the train has left (`leftAt`). Until `min(leftAt + 180 s, L + 6 min)` it waits; after that it is
/// unsure, with the first reason that applies, and a start is still allowed while all five hold.
struct AutoRideRule {
    // MARK: Numbers

    /// A good fix: this accurate or better, and younger than `goodAge` when it came.
    static let goodAccuracy = 100.0
    static let goodAge: TimeInterval = 10
    /// Speed is the along-track distance over the good fixes of the last 8 s.
    static let speedSpan: TimeInterval = 8
    /// Tp: the first good fix this far along.
    static let leaveAlong = 300.0
    /// Y1: within this distance of the origin point, from this long before L.
    static let stationRadius = 300.0
    static let stationLead: TimeInterval = 15 * 60
    /// Y1's covered form: the first good fix after L − 60 s.
    static let coveredLead: TimeInterval = 60
    static let coveredOff = 150.0
    static let coveredAlong = 300.0...1500.0
    /// Stations whose platforms are under a roof GPS does not see through: the covered form is their only Y1.
    static let coveredStations: Set<String> = ["UN"]
    /// Y2.
    static let leaveSpan: TimeInterval = 45
    static let leaveOff = 150.0
    static let leaveMedianOff = 60.0
    static let leaveSpeed = 25.0 / 3.6
    static let leaveSpeedFrom: TimeInterval = 30
    static let standSpeed = 2.0
    static let standLimit: TimeInterval = 10
    /// A gap between good fixes this long is a pause where iOS sends no stationary update (iOS 17), and this long always.
    static let pauseGap: TimeInterval = 10
    static let breakGap: TimeInterval = 20
    static let leavePast = 600.0
    /// Y3.
    static let feedSpan: TimeInterval = 20
    static let feedMaxAge: TimeInterval = 90
    static let feedGap = 400.0
    static let feedDrift = 100.0
    /// Y4: another train leaving this close to the alerted one could be the one the phone is on.
    static let rivalWindow: TimeInterval = 180
    /// Y4's same track: the rival's point this far past the station within `rivalTrack` of this trip's track.
    static let rivalLead = 600.0
    static let rivalTrack = 150.0
    static let rivalParted = 250.0
    static let rivalAway = 800.0
    /// Y5.
    static let room: TimeInterval = 5 * 60
    /// Not on board.
    static let stayRadius = 300.0
    static let staySpan: TimeInterval = 60
    static let stayTrainAlong = 800.0
    static let elsewhereOff = 300.0
    static let elsewhereFar = 1500.0
    /// The deadline: `min(leftAt + decideSpan, L + decideCap)`.
    static let decideSpan: TimeInterval = 180
    static let decideCap: TimeInterval = 6 * 60
    /// A look this long after the one before it means the app was suspended between them (`leftAt(look:previous:...)`).
    static let lookGap: TimeInterval = 30
    /// Raw fixes, with their places, are kept this long.
    static let keepsFixes: TimeInterval = 3 * 60

    // MARK: Types

    enum Verdict: Equatable, Sendable {
        case starts
        case notOnBoard
        case waiting
        case unsure(AutoRideCheck.Reason)
    }

    /// What the watch knows at the moment it asks.
    struct Moment: Sendable {
        var now: Date
        /// L: the train's expected departure from the rider's station, as last read.
        var departure: Date
        /// When the train left, as the watch stamped it; nil while it has not.
        var leftAt: Date?
        /// The expected arrival at the rider's stop.
        var arrival: Date
        /// Yes, No or a ride for this trip came first.
        var answered = false
    }

    /// One good fix, placed on the track: along from the origin stop, off the track, from the origin point.
    private struct Mark {
        let at: Date
        let along: Double
        let off: Double
        let fromOrigin: Double
        let isStationary: Bool
    }

    /// A good fix's place, kept `keepsFixes` for the rivals' tracks.
    private struct Place {
        let at: Date
        let point: GeoPoint
        let along: Double
        let off: Double
    }

    /// One of GO's positions, placed on this trip's track.
    private struct Sighting {
        let reportedAt: Date
        let readAt: Date
        let point: GeoPoint
        let along: Double
        let hasVehicleTime: Bool

        var isFresh: Bool { readAt.timeIntervalSince(reportedAt) <= AutoRideRule.feedMaxAge }
    }

    // MARK: State

    let originId: String
    private let shape: TrackShape
    private let originAlong: Double
    private let originPoint: GeoPoint
    /// The watch armed at or after L (an app opened on the moving train): the covered form counts at any station.
    private let armedLate: Bool
    /// iOS sends a stationary update when the phone stops (iOS 18); without it a gap is a pause.
    private let reportsStationary: Bool

    private var marks: [Mark] = []
    private var places: [Place] = []
    /// The latest good fix within `stationRadius` of the origin point, by its index in `marks`.
    private var lastAtStation: Int?
    private var sightings: [Sighting] = []
    private var rivals: [RivalTrain] = []
    private var rivalSightings: [String: [Sighting]] = [:]
    /// Rivals whose track the phone was seen leaving, by trip id.
    private var parted: Set<String> = []

    /// Nil for a plan with no track: it cannot be checked, and the watch does not arm.
    init?(plan: RidePlan, originId: String, armedLate: Bool, reportsStationary: Bool) {
        guard let track = plan.track, let first = track.stopDistances.first else { return nil }
        self.originId = originId
        shape = track.shape
        originAlong = first
        originPoint = track.shape.point(at: first)
        self.armedLate = armedLate
        self.reportsStationary = reportsStationary
    }

    // MARK: Observations

    /// A fix from the phone as it came at `now`; only good ones count.
    mutating func observe(_ fix: LocationFix, at now: Date) {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= Self.goodAccuracy, fix.age < Self.goodAge else { return }
        let at = now.addingTimeInterval(-fix.age)
        // Fixes come in order; one measured before the last is dropped.
        if let last = marks.last, at < last.at { return }
        let projection = shape.project(fix.coordinate)
        let mark = Mark(
            at: at, along: projection.along - originAlong, off: projection.off,
            fromOrigin: TrackShape.distance(fix.coordinate, originPoint), isStationary: fix.isStationary
        )
        marks.append(mark)
        if mark.fromOrigin <= Self.stationRadius { lastAtStation = marks.count - 1 }
        let place = Place(at: at, point: fix.coordinate, along: mark.along, off: mark.off)
        places.append(place)
        places.removeAll { now.timeIntervalSince($0.at) > Self.keepsFixes }
        for rival in rivals where !parted.contains(rival.trip.tripId) && hasParted(from: rival, at: place) {
            parted.insert(rival.trip.tripId)
        }
    }

    /// GO's position of the trip, read at `readAt`. A position already seen is dropped.
    mutating func observe(_ position: TrainPosition, readAt: Date) {
        guard !sightings.contains(where: { $0.reportedAt == position.reportedAt }) else { return }
        sightings.append(sighting(position, readAt: readAt))
        sightings.sort { $0.reportedAt < $1.reportedAt }
    }

    /// The trains leaving the station close to this one (`RivalTrainsProviding`), as last read.
    mutating func setRivals(_ trains: [RivalTrain]) {
        rivals = trains
        for rival in trains where !parted.contains(rival.trip.tripId) {
            if places.contains(where: { hasParted(from: rival, at: $0) }) { parted.insert(rival.trip.tripId) }
        }
    }

    /// GO's position of a rival, read at `readAt`.
    mutating func observe(_ position: TrainPosition, rival tripId: String, readAt: Date) {
        var list = rivalSightings[tripId] ?? []
        guard !list.contains(where: { $0.reportedAt == position.reportedAt }) else { return }
        list.append(sighting(position, readAt: readAt))
        list.sort { $0.reportedAt < $1.reportedAt }
        rivalSightings[tripId] = list
    }

    private func sighting(_ position: TrainPosition, readAt: Date) -> Sighting {
        Sighting(
            reportedAt: position.reportedAt, readAt: readAt, point: position.coordinate,
            along: shape.project(position.coordinate).along - originAlong, hasVehicleTime: position.hasVehicleTime
        )
    }

    // MARK: The verdict

    func verdict(at moment: Moment) -> Verdict {
        guard let leftAt = moment.leftAt, !moment.answered else { return .waiting }
        let room = hasRoom(moment)
        let y1 = isAtStation(moment)
        let tp = tp()
        let y2 = tp.map { leavesWith(from: $0) } ?? false
        let y3 = tp.map { agrees(from: $0) } ?? false
        let y4 = tp.map { hasNoRival(moment, from: $0, agrees: y3) } ?? false
        if room, y1, y2, y3, y4 { return .starts }
        if isNotOnBoard(moment, leftAt: leftAt, atStation: y1) { return .notOnBoard }
        let deadline = min(leftAt.addingTimeInterval(Self.decideSpan), moment.departure.addingTimeInterval(Self.decideCap))
        guard moment.now >= deadline else { return .waiting }
        if !room { return .unsure(.short) }
        if !y1 { return .unsure(.noStation) }
        if tp != nil, !y2 { return .unsure(.weakFixes) }
        // No good fix since the train left (missing or not accurate enough): the phone failed, not GO's feed. A stationary
        // fix that still held when it left is a phone standing still, as Y1 and "stayed" read it, not a failure.
        let held = marks.last.map { $0.isStationary && $0.at.addingTimeInterval(RideEngine.stationaryTimeout) >= leftAt } ?? false
        if tp == nil, !held, !marks.contains(where: { $0.at >= leftAt }) { return .unsure(.weakFixes) }
        if !y3 { return .unsure(.noFeed) }
        return .unsure(.rival)
    }

    /// When the watch stamps the train's departure (`leftAt`): at its first look that reads `.departed`, or the later of
    /// the look before and L when that look is more than 30 s earlier (the app was suspended); L with no fresh position.
    static func leftAt(look now: Date, previous: Date?, departure: Date, sighted: Bool) -> Date {
        guard sighted else { return departure }
        if let previous, now.timeIntervalSince(previous) > lookGap { return max(previous, departure) }
        return now
    }

    // MARK: Y5

    private func hasRoom(_ moment: Moment) -> Bool {
        moment.arrival.timeIntervalSince(moment.now) >= Self.room
    }

    // MARK: Y1

    private var isCovered: Bool { Self.coveredStations.contains(originId) }

    private func isAtStation(_ moment: Moment) -> Bool {
        if armedLate || isCovered, coveredForm(moment) { return true }
        guard !isCovered, let index = lastAtStation else { return false }
        let station = marks[index]
        var seen = station.at
        // iOS sends nothing while the phone is still: its stationary fix holds while it is the latest, until the next fix.
        if station.isStationary {
            let until = index + 1 < marks.count ? marks[index + 1].at : moment.now
            seen = min(until, station.at.addingTimeInterval(RideEngine.stationaryTimeout))
        }
        return seen >= moment.departure.addingTimeInterval(-Self.stationLead)
    }

    private func coveredForm(_ moment: Moment) -> Bool {
        let from = moment.departure.addingTimeInterval(-Self.coveredLead)
        guard let index = marks.firstIndex(where: { $0.at > from }), index + 1 < marks.count else { return false }
        let first = marks[index], next = marks[index + 1]
        return first.off <= Self.coveredOff && Self.coveredAlong.contains(first.along) && next.along > first.along
    }

    // MARK: Y2

    /// Tp: the start of the latest run of good fixes 300 m or more along (a phone that came in along the track and stood
    /// at the station starts a new run when it leaves); with the covered form, from the first good fix after L − 60 s.
    private func tp() -> Date? {
        guard let lastBelow = marks.lastIndex(where: { $0.along < Self.leaveAlong }) else {
            return marks.first?.at
        }
        let start = lastBelow + 1
        return start < marks.count ? marks[start].at : nil
    }

    private func leavesWith(from tp: Date) -> Bool {
        guard let first = marks.firstIndex(where: { $0.at >= tp }) else { return false }
        var start = first
        var standingSince: Date?
        var index = first
        while index < marks.count {
            let mark = marks[index]
            defer { index += 1 }
            // A gap: a pause where iOS sends no stationary update, and a break always.
            if index > start {
                let gap = mark.at.timeIntervalSince(marks[index - 1].at)
                if gap > Self.breakGap || (!reportsStationary && gap > Self.pauseGap) {
                    start = index
                    standingSince = nil
                    continue
                }
            }
            // Standing: a stationary update (which holds until the next fix), or under 2 m/s over the last 8 s.
            let speed = self.speed(at: index)
            let heldStill = index > start && marks[index - 1].isStationary
            let stands = mark.isStationary || heldStill || (speed.map { $0 < Self.standSpeed } ?? false)
            if stands {
                let since = standingSince ?? (heldStill ? marks[index - 1].at : mark.at)
                standingSince = since
                if mark.at.timeIntervalSince(since) > Self.standLimit {
                    // A standstill starts the 45 s again, from the next fix that moves.
                    start = index + 1
                    standingSince = nil
                    continue
                }
            } else {
                standingSince = nil
            }
            let windowStart = marks[start].at
            let tooSlow = mark.at.timeIntervalSince(windowStart) >= Self.leaveSpeedFrom
                && (speed.map { $0 < Self.leaveSpeed } ?? false)
            if mark.off > Self.leaveOff || tooSlow {
                start = index + 1
                standingSince = nil
                continue
            }
            if mark.at.timeIntervalSince(windowStart) >= Self.leaveSpan {
                let offs = marks[start...index].map(\.off).sorted()
                if median(offs) <= Self.leaveMedianOff, mark.along >= Self.leavePast { return true }
                // Not yet: the window slides on by one fix.
                start += 1
            }
        }
        return false
    }

    /// Metres a second along the track over the last 8 s of good fixes; nil with no earlier fix in them.
    private func speed(at index: Int) -> Double? {
        let mark = marks[index]
        var earliest: Mark?
        var cursor = index - 1
        while cursor >= 0, mark.at.timeIntervalSince(marks[cursor].at) <= Self.speedSpan {
            earliest = marks[cursor]
            cursor -= 1
        }
        guard let earliest, mark.at > earliest.at else { return nil }
        return (mark.along - earliest.along) / mark.at.timeIntervalSince(earliest.at)
    }

    private func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return .infinity }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    // MARK: Y3

    /// The phone's place along the track at `time`, between the good fixes either side of it (20 s apart at most).
    private func phoneAlong(at time: Date) -> Double? {
        guard let after = marks.firstIndex(where: { $0.at >= time }) else { return nil }
        let b = marks[after]
        if b.at == time { return b.along }
        guard after > 0 else { return nil }
        let a = marks[after - 1]
        let span = b.at.timeIntervalSince(a.at)
        guard span > 0, span <= Self.breakGap else { return nil }
        return a.along + (b.along - a.along) * time.timeIntervalSince(a.at) / span
    }

    /// The phone's gaps to the trip's usable positions from Tp on, oldest first.
    private func gaps(from tp: Date) -> [(at: Date, gap: Double)] {
        sightings.compactMap { sighting in
            guard sighting.hasVehicleTime, sighting.isFresh, sighting.reportedAt >= tp,
                  let phone = phoneAlong(at: sighting.reportedAt) else { return nil }
            return (sighting.reportedAt, phone - sighting.along)
        }
    }

    private func agrees(from tp: Date) -> Bool {
        let gaps = gaps(from: tp).filter { abs($0.gap) <= Self.feedGap }
        for (index, a) in gaps.enumerated() {
            for b in gaps[(index + 1)...] where b.at.timeIntervalSince(a.at) >= Self.feedSpan {
                if abs(b.gap - a.gap) <= Self.feedDrift { return true }
            }
        }
        return false
    }

    // MARK: Y4

    private func hasNoRival(_ moment: Moment, from tp: Date, agrees: Bool) -> Bool {
        rivals.allSatisfy { rival in
            guard abs(rival.departure.timeIntervalSince(moment.departure)) <= Self.rivalWindow, isOnSameTrack(rival) else {
                return true
            }
            return isResolved(rival, from: tp, agrees: agrees)
        }
    }

    private func isOnSameTrack(_ rival: RivalTrain) -> Bool {
        shape.project(rival.shape.point(at: rival.originAlong + Self.rivalLead)).off <= Self.rivalTrack
    }

    /// A good fix past the station, on this trip's track and off the rival's.
    private func hasParted(from rival: RivalTrain, at place: Place) -> Bool {
        guard place.along >= Self.leaveAlong, place.off <= Self.rivalTrack else { return false }
        return rival.shape.project(place.point, from: rival.originAlong).off >= Self.rivalParted
    }

    private func isResolved(_ rival: RivalTrain, from tp: Date, agrees: Bool) -> Bool {
        if parted.contains(rival.trip.tripId) { return true }
        let fresh = (rivalSightings[rival.trip.tripId] ?? []).filter { $0.isFresh && $0.reportedAt >= tp }
        // Its position far from the phone.
        for sighting in fresh {
            guard let phone = phoneAlong(at: sighting.reportedAt) else { continue }
            if TrackShape.distance(shape.point(at: phone + originAlong), sighting.point) >= Self.rivalAway { return true }
        }
        // Behind or ahead of the phone along the track at two positions 20 s apart, while this trip agrees.
        guard agrees else { return false }
        let apart = fresh.filter { sighting in
            guard let phone = phoneAlong(at: sighting.reportedAt) else { return false }
            return abs(phone - sighting.along) > Self.feedGap
        }
        guard let first = apart.first, let last = apart.last else { return false }
        return last.reportedAt.timeIntervalSince(first.reportedAt) >= Self.feedSpan
    }

    // MARK: Not on board

    private func isNotOnBoard(_ moment: Moment, leftAt: Date, atStation: Bool) -> Bool {
        guard let last = marks.last else { return false }
        let isFresh = moment.now.timeIntervalSince(last.at) < Self.goodAge
        // Stayed: within 300 m of the station for 60 s, or still there, while GO places the train 800 m along.
        let held = last.isStationary && last.fromOrigin <= Self.stayRadius
            && moment.now.timeIntervalSince(last.at) <= RideEngine.stationaryTimeout
        if held || (isFresh && spans(after: leftAt, where: { $0.fromOrigin <= Self.stayRadius })) {
            if let train = sightings.last(where: \.isFresh), moment.now.timeIntervalSince(train.readAt) <= Self.feedMaxAge,
               train.along >= Self.stayTrainAlong {
                return true
            }
        }
        // Went elsewhere: off the track for 60 s.
        if isFresh, spans(after: leftAt, where: { $0.off >= Self.elsewhereOff }) { return true }
        // Never at the station, and far from it and off the track as the train left.
        if !atStation, let atLeft = marks.last(where: { $0.at <= leftAt.addingTimeInterval(Self.goodAge) }),
           leftAt.timeIntervalSince(atLeft.at) <= Self.staySpan,
           atLeft.fromOrigin > Self.elsewhereFar, atLeft.off >= Self.elsewhereOff {
            return true
        }
        return false
    }

    /// Every good fix of the last 60 s after the train left matches, and they cover the 60 s with no gap over 10 s.
    private func spans(after leftAt: Date, where matches: (Mark) -> Bool) -> Bool {
        guard let last = marks.last else { return false }
        let from = last.at.addingTimeInterval(-Self.staySpan)
        guard from >= leftAt.addingTimeInterval(-Self.pauseGap) else { return false }
        let window = marks.filter { $0.at >= from }
        guard let first = window.first, first.at.timeIntervalSince(from) <= Self.pauseGap else { return false }
        for (a, b) in zip(window, window.dropFirst()) where b.at.timeIntervalSince(a.at) > Self.pauseGap { return false }
        return window.allSatisfy(matches)
    }
}

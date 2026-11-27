import Foundation

/// The phone's good fixes placed on one trip's track, measured from the rider's station on it: `AutoRideRule`'s Y1 (at the
/// station) and Y2 (leaves with it), the phone's place along the track at a moment, and the spans "not on board" reads
/// (TT-242, D120). Moved out of `AutoRideRule` by TT-251 (D127) so `WrongTrainRule` runs the same proof on another
/// train's track; the numbers stay `AutoRideRule`'s.
struct PlacedFixes {
    /// One good fix, placed on the track: along from the station, off the track, from the station's point.
    struct Mark {
        let at: Date
        let point: GeoPoint
        let along: Double
        let off: Double
        let fromOrigin: Double
        let isStationary: Bool
    }

    /// Which way along the track Y2 is read: the train's way, or turned round (`WrongTrainRule`'s wrong way by the track).
    enum Direction {
        case forward
        case backward

        var sign: Double { self == .forward ? 1 : -1 }
    }

    let shape: TrackShape
    let originAlong: Double
    let originPoint: GeoPoint
    /// iOS sends a stationary update when the phone stops (iOS 18); without it a gap is a pause.
    let reportsStationary: Bool

    private(set) var marks: [Mark] = []
    /// The latest good fix within `AutoRideRule.stationRadius` of the station's point, and when the next fix after it came:
    /// kept when older fixes are dropped, so Y1 holds for a phone that stood at the station a while ago.
    private(set) var atStation: Mark?
    private(set) var afterStation: Date?

    init(shape: TrackShape, originAlong: Double, reportsStationary: Bool) {
        self.shape = shape
        self.originAlong = originAlong
        originPoint = shape.point(at: originAlong)
        self.reportsStationary = reportsStationary
    }

    /// A good fix: `AutoRideRule.goodAccuracy` or better, younger than `AutoRideRule.goodAge` when it came.
    static func isGood(_ fix: LocationFix) -> Bool {
        fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= AutoRideRule.goodAccuracy && fix.age < AutoRideRule.goodAge
    }

    /// Places a good fix that came at `now`; nil for one that is not good, or measured before the last.
    @discardableResult
    mutating func add(_ fix: LocationFix, at now: Date) -> Mark? {
        guard Self.isGood(fix) else { return nil }
        return add(fix.coordinate, at: now.addingTimeInterval(-fix.age), isStationary: fix.isStationary)
    }

    /// Places a good fix measured at `at`; nil for one measured before the last (fixes come in order).
    @discardableResult
    mutating func add(_ point: GeoPoint, at: Date, isStationary: Bool) -> Mark? {
        if let last = marks.last, at < last.at { return nil }
        let projection = shape.project(point)
        let mark = Mark(
            at: at, point: point, along: projection.along - originAlong, off: projection.off,
            fromOrigin: TrackShape.distance(point, originPoint), isStationary: isStationary
        )
        marks.append(mark)
        if mark.fromOrigin <= AutoRideRule.stationRadius {
            atStation = mark
            afterStation = nil
        } else if atStation != nil, afterStation == nil {
            afterStation = mark.at
        }
        return mark
    }

    /// Drops the marks measured before `date`; the station's mark is kept.
    mutating func drop(before date: Date) {
        marks.removeAll { $0.at < date }
    }

    // MARK: Y1

    /// When the phone was last seen at the station: its latest good fix there, or, for a stationary fix, until the next fix
    /// or `RideEngine.stationaryTimeout` (iOS sends nothing while the phone is still).
    func seenAtStation(now: Date) -> Date? {
        guard let station = atStation else { return nil }
        guard station.isStationary else { return station.at }
        return min(afterStation ?? now, station.at.addingTimeInterval(RideEngine.stationaryTimeout))
    }

    /// Y1's covered form: the first good fix after `from` is `AutoRideRule.coveredOff` or less off the track,
    /// `AutoRideRule.coveredAlong` along, and the next good fix is farther along. That first fix, or nil.
    func coveredStart(after from: Date) -> Mark? {
        guard let index = marks.firstIndex(where: { $0.at > from }), index + 1 < marks.count else { return nil }
        let first = marks[index], next = marks[index + 1]
        guard first.off <= AutoRideRule.coveredOff, AutoRideRule.coveredAlong.contains(first.along), next.along > first.along
        else { return nil }
        return first
    }

    // MARK: Y2

    /// Tp: the start of the latest run of good fixes `AutoRideRule.leaveAlong` or more along the way (a phone that came in
    /// along the track and stood at the station starts a new run when it leaves).
    func tp(_ direction: Direction = .forward) -> Date? {
        let sign = direction.sign
        guard let lastBelow = marks.lastIndex(where: { sign * $0.along < AutoRideRule.leaveAlong }) else {
            return marks.first?.at
        }
        let start = lastBelow + 1
        return start < marks.count ? marks[start].at : nil
    }

    /// Y2 from `tp`: `AutoRideRule.leaveSpan` of good fixes, every one `AutoRideRule.leaveOff` or less off the track, their
    /// median `AutoRideRule.leaveMedianOff` or less, `AutoRideRule.leaveSpeed` or more from `speedFrom` on (and `maxSpeed`
    /// at most), no standstill longer than `AutoRideRule.standLimit` (a pause counts), and `reached` at the end. A failure
    /// starts the span again. Speeds are read along `direction`, so going the other way reads as standing.
    func leaves(
        from tp: Date,
        direction: Direction = .forward,
        speedFrom: TimeInterval = AutoRideRule.leaveSpeedFrom,
        maxSpeed: Double? = nil,
        reached: (Mark) -> Bool
    ) -> Bool {
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
                if gap > AutoRideRule.breakGap || (!reportsStationary && gap > AutoRideRule.pauseGap) {
                    start = index
                    standingSince = nil
                    continue
                }
            }
            // Standing: a stationary update (which holds until the next fix), or under 2 m/s over the last 8 s.
            let speed = self.speed(at: index, direction)
            let heldStill = index > start && marks[index - 1].isStationary
            let stands = mark.isStationary || heldStill || (speed.map { $0 < AutoRideRule.standSpeed } ?? false)
            if stands {
                let since = standingSince ?? (heldStill ? marks[index - 1].at : mark.at)
                standingSince = since
                if mark.at.timeIntervalSince(since) > AutoRideRule.standLimit {
                    // A standstill starts the span again, from the next fix that moves.
                    start = index + 1
                    standingSince = nil
                    continue
                }
            } else {
                standingSince = nil
            }
            let windowStart = marks[start].at
            let tooSlow = mark.at.timeIntervalSince(windowStart) >= speedFrom
                && (speed.map { $0 < AutoRideRule.leaveSpeed } ?? false)
            let tooFast = maxSpeed.map { limit in speed.map { $0 > limit } ?? false } ?? false
            if mark.off > AutoRideRule.leaveOff || tooSlow || tooFast {
                start = index + 1
                standingSince = nil
                continue
            }
            if mark.at.timeIntervalSince(windowStart) >= AutoRideRule.leaveSpan {
                let offs = marks[start...index].map(\.off).sorted()
                if Self.median(offs) <= AutoRideRule.leaveMedianOff, reached(mark) { return true }
                // Not yet: the window slides on by one fix.
                start += 1
            }
        }
        return false
    }

    /// Metres a second along the track, read along `direction`, over the last `AutoRideRule.speedSpan` of good fixes; nil
    /// with no earlier fix in them.
    func speed(at index: Int, _ direction: Direction = .forward) -> Double? {
        let mark = marks[index]
        var earliest: Mark?
        var cursor = index - 1
        while cursor >= 0, mark.at.timeIntervalSince(marks[cursor].at) <= AutoRideRule.speedSpan {
            earliest = marks[cursor]
            cursor -= 1
        }
        guard let earliest, mark.at > earliest.at else { return nil }
        return direction.sign * (mark.along - earliest.along) / mark.at.timeIntervalSince(earliest.at)
    }

    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return .infinity }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    // MARK: The phone at a moment

    /// The phone's place along the track at `time`, between the good fixes either side of it (`AutoRideRule.breakGap`
    /// apart at most).
    func phoneAlong(at time: Date) -> Double? {
        guard let (a, b) = around(time) else { return nil }
        guard let a else { return b.along }
        return a.along + (b.along - a.along) * time.timeIntervalSince(a.at) / b.at.timeIntervalSince(a.at)
    }

    /// The phone's point at `time`, between the good fixes either side of it, as `phoneAlong(at:)` finds them.
    func phonePoint(at time: Date) -> GeoPoint? {
        guard let (a, b) = around(time) else { return nil }
        guard let a else { return b.point }
        let fraction = time.timeIntervalSince(a.at) / b.at.timeIntervalSince(a.at)
        return GeoPoint(
            latitude: a.point.latitude + (b.point.latitude - a.point.latitude) * fraction,
            longitude: a.point.longitude + (b.point.longitude - a.point.longitude) * fraction
        )
    }

    /// The marks either side of `time`: (nil, b) when b is at `time` itself.
    private func around(_ time: Date) -> (Mark?, Mark)? {
        guard let after = marks.firstIndex(where: { $0.at >= time }) else { return nil }
        let b = marks[after]
        if b.at == time { return (nil, b) }
        guard after > 0 else { return nil }
        let a = marks[after - 1]
        let span = b.at.timeIntervalSince(a.at)
        guard span > 0, span <= AutoRideRule.breakGap else { return nil }
        return (a, b)
    }

    /// `phoneAlong(at:)` between two fixes that are not stationary: a stationary one says the phone stood, which on a smooth
    /// train can be iOS taking it for still.
    func movingPhoneAlong(at time: Date) -> Double? {
        guard let after = marks.firstIndex(where: { $0.at >= time }), !marks[after].isStationary else { return nil }
        if marks[after].at == time { return marks[after].along }
        guard after > 0, !marks[after - 1].isStationary else { return nil }
        return phoneAlong(at: time)
    }

    /// Every good fix of the last `AutoRideRule.staySpan` after `leftAt` matches, and they cover the span with no gap over
    /// `AutoRideRule.pauseGap`.
    func spans(after leftAt: Date, where matches: (Mark) -> Bool) -> Bool {
        guard let last = marks.last else { return false }
        let from = last.at.addingTimeInterval(-AutoRideRule.staySpan)
        guard from >= leftAt.addingTimeInterval(-AutoRideRule.pauseGap) else { return false }
        let window = marks.filter { $0.at >= from }
        guard let first = window.first, first.at.timeIntervalSince(from) <= AutoRideRule.pauseGap else { return false }
        for (a, b) in zip(window, window.dropFirst()) where b.at.timeIntervalSince(a.at) > AutoRideRule.pauseGap { return false }
        return window.allSatisfy(matches)
    }
}

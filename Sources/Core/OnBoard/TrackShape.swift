import Foundation

/// A place on Earth (WGS 84), as GTFS and the phone give it.
struct GeoPoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// A trip's track as a polyline (GTFS shapes.txt, TT-171), and where a place is along it: every fix, from the phone or
/// the train feed, becomes a distance along the line (Live-Spec, "one position, two sources"). Pure functions; distances
/// are metres, measured on a flat local frame per segment, which is well within a metre over a GO segment.
struct TrackShape: Sendable, Equatable {
    let points: [GeoPoint]
    /// Metres along the line to each point; the first is 0.
    let distances: [Double]

    init(points: [GeoPoint]) {
        self.points = points
        var distances = [0.0]
        for index in points.indices.dropFirst() {
            distances.append(distances[index - 1] + Self.segment(points[index - 1], points[index]).length)
        }
        self.distances = distances
    }

    /// From the stored form: latitude, longitude, latitude, longitude, … (`GTFSFeed.Shape`).
    init(flat: [Double]) {
        self.init(points: stride(from: 0, to: flat.count - 1, by: 2).map { GeoPoint(latitude: flat[$0], longitude: flat[$0 + 1]) })
    }

    var length: Double { distances.last ?? 0 }

    struct Projection: Equatable, Sendable {
        /// Metres along the line from its start to the nearest point on it.
        let along: Double
        /// Metres from the place to that point.
        let off: Double
    }

    /// The nearest point on the line to `point`, no earlier than `minimum` metres along it.
    func project(_ point: GeoPoint, from minimum: Double = 0) -> Projection {
        guard points.count >= 2 else { return Projection(along: 0, off: points.first.map { Self.segment($0, point).length } ?? 0) }
        var best = Projection(along: 0, off: .infinity)
        for index in points.indices.dropLast() where distances[index + 1] >= minimum {
            let segment = Self.segment(points[index], points[index + 1])
            let place = Self.segment(points[index], point)
            let squared = segment.length * segment.length
            var fraction = squared > 0 ? (place.x * segment.x + place.y * segment.y) / squared : 0
            fraction = min(max(fraction, 0), 1)
            var along = distances[index] + fraction * segment.length
            if along < minimum {
                along = minimum
                fraction = segment.length > 0 ? (minimum - distances[index]) / segment.length : 0
            }
            let off = hypot(place.x - fraction * segment.x, place.y - fraction * segment.y)
            if off < best.off { best = Projection(along: along, off: off) }
        }
        return best
    }

    /// Each place's distance along the line, in order: a stop is never placed before the one before it, so a line that
    /// passes near itself keeps its stops in calling order.
    func distances(of places: [GeoPoint]) -> [Double] {
        var minimum = 0.0
        return places.map { place in
            minimum = project(place, from: minimum).along
            return minimum
        }
    }

    /// The point `distance` metres along the line, clamped to its ends.
    func point(at distance: Double) -> GeoPoint {
        guard let first = points.first else { return GeoPoint(latitude: 0, longitude: 0) }
        guard distance > 0 else { return first }
        guard let index = distances.firstIndex(where: { $0 >= distance }), index > 0 else { return points.last ?? first }
        let start = distances[index - 1]
        let span = distances[index] - start
        let fraction = span > 0 ? (distance - start) / span : 0
        let a = points[index - 1], b = points[index]
        return GeoPoint(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
    }

    /// The points that keep the line within `tolerance` metres of the original (Douglas–Peucker), first and last kept.
    static func simplified(_ points: [GeoPoint], tolerance: Double) -> [GeoPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var spans = [(first: 0, last: points.count - 1)]
        while let span = spans.popLast() {
            let (first, last) = span
            guard last > first + 1 else { continue }
            let chord = segment(points[first], points[last])
            let squared = chord.length * chord.length
            var farthest = first
            var farthestDistance = 0.0
            for index in (first + 1)..<last {
                let place = segment(points[first], points[index])
                let fraction = squared > 0 ? min(max((place.x * chord.x + place.y * chord.y) / squared, 0), 1) : 0
                let distance = hypot(place.x - fraction * chord.x, place.y - fraction * chord.y)
                if distance > farthestDistance {
                    farthest = index
                    farthestDistance = distance
                }
            }
            guard farthestDistance > tolerance else { continue }
            keep[farthest] = true
            spans.append((first, farthest))
            spans.append((farthest, last))
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// Metres between two places (TT-175, the phone's speed).
    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        segment(a, b).length
    }

    /// `b` seen from `a` in metres east (x) and north (y), on a flat frame at their mean latitude.
    private static func segment(_ a: GeoPoint, _ b: GeoPoint) -> (x: Double, y: Double, length: Double) {
        let metresPerDegree = 111_195.08
        let latitude = (a.latitude + b.latitude) / 2 * .pi / 180
        let x = (b.longitude - a.longitude) * metresPerDegree * cos(latitude)
        let y = (b.latitude - a.latitude) * metresPerDegree
        return (x, y, hypot(x, y))
    }
}

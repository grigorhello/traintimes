import Foundation

// The stations a train passes without stopping (TT-232, D111). The trip's own stops stay the truth for what is a stop
// (GTFS stop_times); the line's order (`GONetwork`, shipped in the app) says which stations lie between two of them.

extension GONetwork {
    /// The stations of line `id` between each stop of `stops` (station ids, in the order the train calls) and the next one,
    /// in the order the train passes them: one list per stretch, empty where the two are neighbours. Nil when the order
    /// is not known: the line is not in the app, a stop is not on it, or the stops do not run one way along it.
    static func stationsBetween(_ stops: [String], onLine id: String) -> [[Station]]? {
        guard stops.count >= 2, let line = line(id) else { return nil }
        let order = [union] + line.stations
        let indices = stops.compactMap { stop in order.firstIndex { $0.id == stop } }
        guard indices.count == stops.count else { return nil }
        let pairs = Array(zip(indices, indices.dropFirst()))
        let ascends = indices[1] > indices[0]
        guard pairs.allSatisfy({ from, to in ascends ? to > from : to < from }) else { return nil }
        return pairs.map { from, to in
            ascends ? Array(order[(from + 1)..<to]) : Array(order[(to + 1)..<from].reversed())
        }
    }
}

extension RidePlan {
    /// A station this close to the trip's track is on the train's way; further off it is on another branch of its line
    /// (Hamilton GO Centre for a Niagara train), and is left out.
    static let onTrackDistance = 750.0
    /// A skipped station's share of its stretch is kept inside these, so its row is never on a stop's.
    static let alongLimits = 0.04...0.9

    /// The stations the train passes without stopping between the ride's `stops`, on line `lineId`, in the order it passes
    /// them. Each is placed along its stretch by distance where the trip has a track and `places` has the station (so
    /// the train on screen passes its row about when the real train passes it), evenly otherwise. Empty when the line's
    /// order is not known (`GONetwork.stationsBetween`): the ride then shows its stops only.
    static func skipped(stops: [Stop], track: Track?, lineId: String?, places: [String: GeoPoint] = [:]) -> [Skipped] {
        guard let lineId, let between = GONetwork.stationsBetween(stops.map(\.station.id), onLine: lineId) else { return [] }
        var result: [Skipped] = []
        for (index, stations) in between.enumerated() where !stations.isEmpty {
            var kept: [Station] = stations
            var measured: [Double] = []
            if let track, track.stopDistances.count == stops.count {
                let start = track.stopDistances[index]
                let span = track.stopDistances[index + 1] - start
                kept = []
                for station in stations {
                    guard span > 0, let place = places[station.id] else {
                        kept.append(station)
                        continue
                    }
                    let projection = track.shape.project(place, from: start)
                    guard projection.off <= onTrackDistance else { continue }
                    kept.append(station)
                    measured.append((projection.along - start) / span)
                }
            }
            let edges: [Double] = [0] + measured + [1]
            let isMeasured = measured.count == kept.count && zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 }
            for (order, station) in kept.enumerated() {
                let along = isMeasured ? measured[order] : Double(order + 1) / Double(kept.count + 1)
                let limited = min(max(along, alongLimits.lowerBound), alongLimits.upperBound)
                result.append(Skipped(station: station, after: index, along: limited))
            }
        }
        return result
    }
}

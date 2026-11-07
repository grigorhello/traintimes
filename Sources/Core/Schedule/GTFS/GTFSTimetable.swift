import Foundation

/// What the app asks of an imported GTFS feed (TT-130): stations, the line between two of them, and the direct trains
/// between them on a service day, as domain types.
struct GTFSTimetable: Sendable {
    let feed: GTFSFeed
    /// Every station a train calls at, alphabetically, with the names of its lines.
    let stations: [Station]
    /// The last service day with trains (the feed's validity window, Q6); the day strip stops there.
    let lastServiceDay: ServiceDay?
    private let tripsByDate: [Int: [Int]]
    private let stopIndex: [String: Int]

    init(feed: GTFSFeed) {
        self.feed = feed
        var tripsByDate: [Int: [Int]] = [:]
        var stationLines = [Set<Int>](repeating: [], count: feed.stops.count)
        for (index, trip) in feed.trips.enumerated() {
            for date in feed.services[trip.service] { tripsByDate[date, default: []].append(index) }
            for stop in trip.stops { stationLines[stop].insert(trip.line) }
        }
        self.tripsByDate = tripsByDate
        lastServiceDay = tripsByDate.keys.max().map(ServiceDay.init(dateKey:))
        stopIndex = Dictionary(feed.stops.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        stations = feed.stops.enumerated()
            .map { index, stop in
                Station(id: stop.id, name: stop.name, lines: stationLines[index].map { feed.lines[$0].name }.sorted())
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The line with the most trains calling at both stations; nil when no train calls at both (TT-115's No direct
    /// connection).
    func line(between first: String, and second: String) -> Line? {
        guard let a = stopIndex[first], let b = stopIndex[second] else { return nil }
        var counts: [Int: Int] = [:]
        for trip in feed.trips where trip.stops.contains(a) && trip.stops.contains(b) {
            counts[trip.line, default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) else { return nil }
        let line = feed.lines[best.key]
        return Line(id: line.id, name: line.name, colorHex: line.color)
    }

    /// Direct trains from one station to another on a service day, stopping at both in that order, by departure.
    /// Express (Q4, D35): the feed has no express flag, so a train is Express when it skips a station that more than half
    /// of its line's trains between the two stations call at that day.
    func trips(from origin: String, to destination: String, on day: ServiceDay) -> [Trip] {
        let matches = calls(from: origin, to: destination, on: day)
        var usual: [Int: Set<Int>] = [:]
        for (line, group) in Dictionary(grouping: matches, by: { feed.trips[$0.trip].line }) {
            var counts: [Int: Int] = [:]
            for match in group {
                for stop in feed.trips[match.trip].stops[(match.from + 1)..<match.to] { counts[stop, default: 0] += 1 }
            }
            usual[line] = Set(counts.filter { $0.value * 2 > group.count }.keys)
        }
        return matches
            .map { match in
                let trip = feed.trips[match.trip]
                let between = Set(trip.stops[(match.from + 1)..<match.to])
                return Trip(
                    key: TripKey(serviceDay: day, tripId: trip.id),
                    scheduledDeparture: day.gtfsTime(trip.departures[match.from]),
                    scheduledArrival: day.gtfsTime(trip.arrivals[match.to]),
                    // Neither the static feed nor its TripUpdates carry platforms (D36).
                    platform: .pending,
                    tags: usual[trip.line, default: []].isSubset(of: between) ? [] : [.express]
                )
            }
            .sorted { ($0.scheduledDeparture, $0.key.tripId) < ($1.scheduledDeparture, $1.key.tripId) }
    }

    /// Every stop of one trip from the origin to the destination, with scheduled times (Trip details, TT-118).
    func stops(of tripId: String, from origin: String, to destination: String, on day: ServiceDay) -> [TripStop] {
        guard let match = calls(from: origin, to: destination, on: day).first(where: { feed.trips[$0.trip].id == tripId }) else {
            return []
        }
        let trip = feed.trips[match.trip]
        return (match.from...match.to).map { position in
            let stop = feed.stops[trip.stops[position]]
            let time = position == match.from ? trip.departures[position] : trip.arrivals[position]
            return TripStop(station: Station(id: stop.id, name: stop.name), scheduled: day.gtfsTime(time))
        }
    }

    /// A direct trip's whole calling pattern with its scheduled times, which live estimates are matched against (TT-131).
    struct Call: Sendable {
        let tripId: String
        /// Stop ids in calling order.
        let stops: [String]
        let arrivals: [Date]
        let departures: [Date]
        /// Where the route's origin and destination are in `stops`.
        let from: Int
        let to: Int
    }

    /// The direct trains from one station to another on a service day, with every stop they call at.
    func directCalls(from origin: String, to destination: String, on day: ServiceDay) -> [Call] {
        calls(from: origin, to: destination, on: day).map { match in
            let trip = feed.trips[match.trip]
            return Call(
                tripId: trip.id,
                stops: trip.stops.map { feed.stops[$0].id },
                arrivals: trip.arrivals.map(day.gtfsTime),
                departures: trip.departures.map(day.gtfsTime),
                from: match.from,
                to: match.to
            )
        }
    }

    /// The trips that run on the day and call at the origin, then later at the destination, with both positions.
    private func calls(from origin: String, to destination: String, on day: ServiceDay) -> [(trip: Int, from: Int, to: Int)] {
        guard let a = stopIndex[origin], let b = stopIndex[destination], a != b else { return [] }
        return (tripsByDate[day.dateKey] ?? []).compactMap { index in
            let stops = feed.trips[index].stops
            guard let from = stops.firstIndex(of: a), let to = stops[(from + 1)...].firstIndex(of: b) else { return nil }
            return (trip: index, from: from, to: to)
        }
    }
}

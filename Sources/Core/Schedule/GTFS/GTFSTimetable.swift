import Foundation

/// What the app asks of an imported GTFS feed (TT-130): stations, the line between two of them, and the direct trains
/// between them on a service day, as domain types.
struct GTFSTimetable: Sendable {
    let feed: GTFSFeed
    /// Every station a train calls at, alphabetically, with the names of its lines and its place (the picker orders a line
    /// from Union outward by it, TT-200).
    let stations: [Station]
    /// The last service day with trains (the feed's validity window, Q6); the day strip stops there.
    let lastServiceDay: ServiceDay?
    private let tripsByDate: [Int: [Int]]
    private let stopIndex: [String: Int]
    /// Each trip's index in `feed.trips` by its id (ids are unique, TT-251).
    private let tripIndex: [String: Int]

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
        tripIndex = Dictionary(feed.trips.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let alongLine = Self.distancesFromUnion(feed)
        stations = feed.stops.enumerated()
            .map { index, stop in
                Station(
                    id: stop.id, name: stop.name, lines: stationLines[index].map { feed.lines[$0].name }.sorted(),
                    place: stop.place, distanceFromUnion: alongLine[index] ?? [:]
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// For each stop, metres from Union along each line's trains (the sum of the straight hops between calls), by line
    /// name, the least over the trips that call at Union (TT-200, D83): a line's stations in the order its trains reach
    /// them, so a branch's far end (St. Catharines past West Harbour) stays in line order. Each stopping pattern is walked
    /// once.
    private static func distancesFromUnion(_ feed: GTFSFeed) -> [Int: [String: Double]] {
        guard let union = feed.stops.firstIndex(where: { $0.id == "UN" }) else { return [:] }
        var result: [Int: [String: Double]] = [:]
        var walked = Set<[Int]>()
        for trip in feed.trips {
            guard let start = trip.stops.firstIndex(of: union),
                  walked.insert([trip.line] + trip.stops).inserted else { continue }
            let name = feed.lines[trip.line].name
            for direction in [1, -1] {
                var distance = 0.0
                var previous = start
                var index = start + direction
                while trip.stops.indices.contains(index),
                      let from = feed.stops[trip.stops[previous]].place, let to = feed.stops[trip.stops[index]].place {
                    distance += TrackShape.distance(from, to)
                    let stop = trip.stops[index]
                    result[stop, default: [:]][name] = min(result[stop]?[name] ?? .infinity, distance)
                    previous = index
                    index += direction
                }
            }
        }
        return result
    }

    /// The route codes a service alert may name for a line (TT-132, D37): its routes' codes, and the line id itself.
    func routeCodes(ofLine id: String) -> Set<String> {
        let routes = feed.lines.first { $0.id == id }?.routeIds ?? []
        return Set(routes.map(GTFSFeed.routeCode) + [id])
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
            return TripStop(station: Station(id: stop.id, name: stop.name, place: stop.place), scheduled: day.gtfsTime(time))
        }
    }

    /// The ride's stops from the origin to your stop with their scheduled times, and each stop's place on the trip's track
    /// when the feed has one (TT-171). Nil when the trip does not run that day between those stations.
    func ridePlan(for ride: Ride) -> RidePlan? {
        let day = ServiceDay(dateKey: ride.serviceDate)
        guard let match = calls(from: ride.originId, to: ride.destinationId, on: day).first(where: { feed.trips[$0.trip].id == ride.tripId })
        else { return nil }
        let trip = feed.trips[match.trip]
        let positions = Array(match.from...match.to)
        let stops = positions.map { position in
            let stop = feed.stops[trip.stops[position]]
            return RidePlan.Stop(
                station: Station(id: stop.id, name: stop.name),
                arrival: day.gtfsTime(trip.arrivals[position]),
                departure: day.gtfsTime(trip.departures[position])
            )
        }
        var track: RidePlan.Track?
        let places = positions.compactMap { position -> GeoPoint? in
            let stop = feed.stops[trip.stops[position]]
            guard let latitude = stop.latitude, let longitude = stop.longitude else { return nil }
            return GeoPoint(latitude: latitude, longitude: longitude)
        }
        if let index = trip.shape, let shapes = feed.shapes, index < shapes.count, places.count == positions.count {
            let shape = TrackShape(flat: shapes[index].points)
            track = RidePlan.Track(shape: shape, stopDistances: shape.distances(of: places))
        }
        // The stations it passes without stopping, and the Schedule card's express tag for this stretch (TT-232, D111).
        var stationPlaces: [String: GeoPoint] = [:]
        for stop in feed.stops {
            if let place = stop.place { stationPlaces[stop.id] = place }
        }
        let skipped = RidePlan.skipped(stops: stops, track: track, lineId: feed.lines[trip.line].id, places: stationPlaces)
        let isExpress = trips(from: ride.originId, to: ride.destinationId, on: day)
            .first { $0.key.tripId == ride.tripId }?.tags.contains(.express) ?? false
        return RidePlan(stops: stops, track: track, skipped: skipped, isExpress: isExpress)
    }

    /// Every rail trip leaving a station on a service day, any line, by scheduled departure; trips that end there are left
    /// out (TT-242, D120: `AutoRideRule`'s rivals, Y4). Each carries its track where the feed has one, and the station's
    /// distance along it, placed as `ridePlan(for:)` places a ride's first stop, so the numbers agree with ride plans.
    func departures(from station: String, on day: ServiceDay) -> [StationDeparture] {
        let place = stopIndex[station].flatMap { feed.stops[$0].place }
        // Many trips share a track: each is built and measured once.
        var tracks: [Int: (shape: TrackShape, along: Double?)] = [:]
        return leaving(station, on: day)
            .map { match in
                let trip = feed.trips[match.trip]
                var track: (shape: TrackShape, along: Double?)?
                if let index = trip.shape, let shapes = feed.shapes, index < shapes.count {
                    if tracks[index] == nil {
                        let shape = TrackShape(flat: shapes[index].points)
                        tracks[index] = (shape: shape, along: place.flatMap { shape.distances(of: [$0]).first })
                    }
                    track = tracks[index]
                }
                return StationDeparture(
                    trip: TripKey(serviceDay: day, tripId: trip.id),
                    departure: day.gtfsTime(trip.departures[match.from]),
                    shape: track?.shape,
                    along: track?.along
                )
            }
            .sorted { ($0.departure, $0.trip.tripId) < ($1.departure, $1.trip.tripId) }
    }

    /// A trip by id on a service day (TT-251, D127): its stops in calling order with their scheduled times, its line, and its
    /// track over all of its stops with each placed on it, as `ridePlan(for:)` places a ride's. Nil when no trip has the
    /// id or it does not run that day.
    func trip(id: String, on day: ServiceDay) -> TimetableTrip? {
        guard let index = tripIndex[id], tripsByDate[day.dateKey]?.contains(index) == true else { return nil }
        let trip = feed.trips[index]
        let stops = trip.stops.indices.map { position in
            let stop = feed.stops[trip.stops[position]]
            return TimetableTrip.Stop(
                station: Station(id: stop.id, name: stop.name, place: stop.place),
                arrival: day.gtfsTime(trip.arrivals[position]),
                departure: day.gtfsTime(trip.departures[position])
            )
        }
        var track: RidePlan.Track?
        let places = stops.compactMap(\.station.place)
        if let shapeIndex = trip.shape, let shapes = feed.shapes, shapeIndex < shapes.count, places.count == stops.count {
            let shape = TrackShape(flat: shapes[shapeIndex].points)
            track = RidePlan.Track(shape: shape, stopDistances: shape.distances(of: places))
        }
        return TimetableTrip(key: TripKey(serviceDay: day, tripId: trip.id), lineId: feed.lines[trip.line].id, stops: stops, track: track)
    }

    /// The trains a rider at `station` may take by mistake (TT-251, D127): every rail trip leaving it that day with a track,
    /// not ending there, with the station's place on its track (as `departures(from:on:)` places it) and its stops after it.
    func candidates(leaving station: String, on day: ServiceDay) -> [WrongTrainCandidate] {
        let place = stopIndex[station].flatMap { feed.stops[$0].place }
        var tracks: [Int: (shape: TrackShape, along: Double?)] = [:]
        return leaving(station, on: day).compactMap { match in
            let trip = feed.trips[match.trip]
            guard let place, let index = trip.shape, let shapes = feed.shapes, index < shapes.count else { return nil }
            if tracks[index] == nil {
                let shape = TrackShape(flat: shapes[index].points)
                tracks[index] = (shape, shape.distances(of: [place]).first)
            }
            guard let track = tracks[index], let along = track.along else { return nil }
            return WrongTrainCandidate(
                trip: TripKey(serviceDay: day, tripId: trip.id),
                lineId: feed.lines[trip.line].id,
                departure: day.gtfsTime(trip.departures[match.from]),
                shape: track.shape,
                originAlong: along,
                stopsAfter: trip.stops[(match.from + 1)...].map { feed.stops[$0].id }
            )
        }
        .sorted { ($0.departure, $0.trip.tripId) < ($1.departure, $1.trip.tripId) }
    }

    /// The same trips as `departures(from:on:)`, each as a call that starts and ends at the station, so
    /// `TripUpdate.live(on:feedTime:)` reads only what the live feed says there: cancelled, the stop skipped, or the
    /// expected departure (TT-242).
    func departureCalls(from station: String, on day: ServiceDay) -> [Call] {
        leaving(station, on: day).map { match in
            let trip = feed.trips[match.trip]
            return Call(
                tripId: trip.id,
                stops: trip.stops.map { feed.stops[$0].id },
                arrivals: trip.arrivals.map(day.gtfsTime),
                departures: trip.departures.map(day.gtfsTime),
                from: match.from,
                to: match.from
            )
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

    /// The trips that run on the day and call at the station before their last stop, with its position.
    private func leaving(_ station: String, on day: ServiceDay) -> [(trip: Int, from: Int)] {
        guard let stop = stopIndex[station] else { return [] }
        return (tripsByDate[day.dateKey] ?? []).compactMap { index in
            let stops = feed.trips[index].stops
            guard let from = stops.firstIndex(of: stop), from < stops.count - 1 else { return nil }
            return (trip: index, from: from)
        }
    }
}

/// A rail trip leaving a station (TT-242, D120), from `GTFSTimetable.departures(from:on:)`.
struct StationDeparture: Sendable, Equatable {
    let trip: TripKey
    /// Scheduled.
    let departure: Date
    /// The trip's whole track; nil where the feed gives it none.
    let shape: TrackShape?
    /// The station's distance along `shape`, in metres; nil with no shape or where the feed does not place the station.
    let along: Double?
}

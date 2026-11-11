import Foundation

/// The rail part of a GTFS feed, as kept on device (TT-130, D35): stations, lines, each service's dates and each trip's
/// stops and times, and the track each trip runs on (TT-171). Feed types stay inside the GTFS repository; screens read
/// domain types (`GTFSTimetable`).
struct GTFSFeed: Codable, Sendable, Equatable {
    struct Stop: Codable, Sendable, Equatable {
        let id: String
        let name: String
        /// Where the station is (WGS 84), to place it on its trips' track (TT-171). Nil where the feed gives none, and in
        /// a copy imported before TT-171 until its refresh.
        var latitude: Double?
        var longitude: Double?

        var place: GeoPoint? {
            guard let latitude, let longitude else { return nil }
            return GeoPoint(latitude: latitude, longitude: longitude)
        }
    }

    struct Line: Codable, Sendable, Equatable {
        /// The route's short name ("LW"), which stays the same from one feed to the next; the route id does not.
        let id: String
        let name: String
        /// "#98002e"; nil when the feed has none.
        let color: String?
        /// The feed's route ids for the line ("09261126-LW"), to scope service alerts to it (TT-132). Nil in a copy
        /// imported before TT-132, until its weekly refresh.
        var routeIds: [String]?
    }

    struct Trip: Codable, Sendable, Equatable {
        let id: String
        /// Index into `lines`.
        let line: Int
        /// Index into `services`.
        let service: Int
        /// Indexes into `stops`, in calling order.
        let stops: [Int]
        /// Seconds after noon minus 12 h on the service date, the GTFS reference: 25:10:00 is 90,600.
        let arrivals: [Int]
        let departures: [Int]
        /// Index into `shapes`; nil when the feed gives the trip no track (TT-171).
        var shape: Int?
    }

    /// A trip's track (GTFS shapes.txt, TT-171): latitude and longitude pairs in order, simplified on import.
    struct Shape: Codable, Sendable, Equatable {
        let id: String
        /// Latitude, longitude, latitude, longitude, …
        let points: [Double]
    }

    var importedAt: Date
    var stops: [Stop]
    var lines: [Line]
    /// Each service's dates as yyyymmdd, ascending.
    var services: [[Int]]
    var trips: [Trip]
    /// The tracks the rail trips run on (TT-171). Nil in a copy imported before TT-171, which is refreshed for them; empty
    /// when the feed has no shapes.txt.
    var shapes: [Shape]? = nil
}

extension GTFSFeed {
    /// The part of a route id that stays the same from one feed to the next: GO's route ids carry the schedule period
    /// ("09261126-LW"), which changes between feeds, so a live alert and an older copy on device may differ in it (D37).
    static func routeCode(_ routeId: String) -> String {
        routeId.split(separator: "-").last.map(String.init) ?? routeId
    }

    enum ImportError: Error, Equatable {
        case missingFile(String)
        case noRail
    }

    /// Imports the rail routes (route_type 2) of a GTFS zip.
    init(zip data: Data, importedAt: Date) throws {
        let archive = try ZipArchive(data: data)
        try self.init(importedAt: importedAt) { try archive.data(named: $0) }
    }

    /// Imports the rail routes (route_type 2): their trips, stop times, stations, service dates and track shapes. `file`
    /// returns a feed file's contents by name, nil when the feed has none.
    init(importedAt: Date, file: (String) throws -> Data?) throws {
        func required(_ name: String) throws -> Data {
            guard let data = try file(name) else { throw ImportError.missingFile(name) }
            return data
        }

        // Rail routes. Routes that share a short name are one line.
        var lines: [Line] = []
        var lineByRoute: [String: Int] = [:]
        try GTFSCSV.forEach(in: required("routes.txt")) { route in
            guard route["route_type"] == "2" else { return }
            let id = route["route_short_name"].isEmpty ? route["route_id"] : route["route_short_name"]
            if !lines.contains(where: { $0.id == id }) {
                let name = route["route_long_name"]
                let color = route["route_color"]
                lines.append(Line(id: id, name: name.isEmpty ? id : name, color: color.isEmpty ? nil : "#\(color)", routeIds: []))
            }
            guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
            lines[index].routeIds?.append(route["route_id"])
            lineByRoute[route["route_id"]] = index
        }
        guard !lines.isEmpty else { throw ImportError.noRail }

        // Their trips.
        var tripIds: [String] = []
        var tripLines: [Int] = []
        var tripServices: [String] = []
        var tripShapes: [String] = []
        var tripIndex: [String: Int] = [:]
        try GTFSCSV.forEach(in: required("trips.txt")) { trip in
            guard let line = lineByRoute[trip["route_id"]], tripIndex[trip["trip_id"]] == nil else { return }
            tripIndex[trip["trip_id"]] = tripIds.count
            tripIds.append(trip["trip_id"])
            tripLines.append(line)
            tripServices.append(trip["service_id"])
            tripShapes.append(trip["shape_id"])
        }

        // Their stop times; stop_times.txt is mostly buses, so other rows are skipped unsplit. A stop with no time is skipped.
        struct Call { let sequence: Int; let stop: String; let arrival: Int; let departure: Int }
        var calls = [[Call]](repeating: [], count: tripIds.count)
        let railTrips = tripIndex
        try GTFSCSV.forEach(in: required("stop_times.txt"), keeping: (column: "trip_id", keep: { railTrips[$0] != nil })) { time in
            guard let index = railTrips[time["trip_id"]], let sequence = Int(time["stop_sequence"]) else { return }
            let departureTime = Self.seconds(time["departure_time"])
            guard let arrival = Self.seconds(time["arrival_time"]) ?? departureTime else { return }
            let departure = departureTime ?? arrival
            calls[index].append(Call(sequence: sequence, stop: time["stop_id"], arrival: arrival, departure: departure))
        }

        // Stations: a platform with a parent station counts as that station.
        var stopNames: [String: String] = [:]
        var stopPlaces: [String: (latitude: Double, longitude: Double)] = [:]
        var parents: [String: String] = [:]
        try GTFSCSV.forEach(in: required("stops.txt")) { stop in
            stopNames[stop["stop_id"]] = stop["stop_name"]
            if let latitude = Double(stop["stop_lat"]), let longitude = Double(stop["stop_lon"]) {
                stopPlaces[stop["stop_id"]] = (latitude, longitude)
            }
            if !stop["parent_station"].isEmpty { parents[stop["stop_id"]] = stop["parent_station"] }
        }

        // Track shapes (TT-171): shapes.txt is mostly buses, so only the rail trips' shapes are split. Each is simplified
        // to the points that matter within a few metres, which keeps the copy on device small.
        let railShapes = Set(tripShapes.filter { !$0.isEmpty })
        var shapePoints: [String: [(sequence: Int, point: GeoPoint)]] = [:]
        if let shapesFile = try file("shapes.txt") {
            GTFSCSV.forEach(in: shapesFile, keeping: (column: "shape_id", keep: { railShapes.contains($0) })) { point in
                guard let sequence = Int(point["shape_pt_sequence"]), let latitude = Double(point["shape_pt_lat"]),
                      let longitude = Double(point["shape_pt_lon"]) else { return }
                shapePoints[point["shape_id"], default: []].append((sequence, GeoPoint(latitude: latitude, longitude: longitude)))
            }
        }

        // Service dates: calendar.txt weekly patterns, then calendar_dates.txt additions (1) and removals (2).
        let usedServices = Set(tripServices)
        var dates: [String: Set<Int>] = [:]
        if let calendar = try file("calendar.txt") {
            let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            GTFSCSV.forEach(in: calendar) { service in
                let id = service["service_id"]
                guard usedServices.contains(id), let start = Int(service["start_date"]), let end = Int(service["end_date"]) else { return }
                let runs = weekdays.map { service[$0] == "1" }
                var day = ServiceDay(dateKey: start)
                while day.dateKey <= end {
                    if runs[day.weekday - 1] { dates[id, default: []].insert(day.dateKey) }
                    day = day.adding(days: 1)
                }
            }
        }
        if let calendarDates = try file("calendar_dates.txt") {
            GTFSCSV.forEach(in: calendarDates) { exception in
                let id = exception["service_id"]
                guard usedServices.contains(id), let date = Int(exception["date"]) else { return }
                switch exception["exception_type"] {
                case "1": dates[id, default: []].insert(date)
                case "2": dates[id]?.remove(date)
                default: break
                }
            }
        }

        // The stored form: only trips that run on some date and call at two stations or more.
        var stops: [Stop] = []
        var stopIndex: [String: Int] = [:]
        var services: [[Int]] = []
        var serviceIndex: [String: Int] = [:]
        var shapes: [Shape] = []
        var shapeIndex: [String: Int] = [:]
        var trips: [Trip] = []
        for index in tripIds.indices {
            let ordered = calls[index].sorted { $0.sequence < $1.sequence }
            guard ordered.count >= 2, let serviceDates = dates[tripServices[index]], !serviceDates.isEmpty else { continue }
            if serviceIndex[tripServices[index]] == nil {
                serviceIndex[tripServices[index]] = services.count
                services.append(serviceDates.sorted())
            }
            let service = serviceIndex[tripServices[index]] ?? 0
            var indexes: [Int] = []
            for id in ordered.map({ parents[$0.stop] ?? $0.stop }) {
                if stopIndex[id] == nil {
                    stopIndex[id] = stops.count
                    let name = stopNames[id] ?? ""
                    let place = stopPlaces[id]
                    stops.append(Stop(id: id, name: name.isEmpty ? id : name, latitude: place?.latitude, longitude: place?.longitude))
                }
                indexes.append(stopIndex[id] ?? 0)
            }
            let shapeId = tripShapes[index]
            if shapeIndex[shapeId] == nil, let points = shapePoints[shapeId], points.count >= 2 {
                shapeIndex[shapeId] = shapes.count
                let track = TrackShape.simplified(points.sorted { $0.sequence < $1.sequence }.map(\.point), tolerance: 3)
                shapes.append(Shape(id: shapeId, points: track.flatMap { [$0.latitude, $0.longitude] }))
            }
            trips.append(Trip(
                id: tripIds[index], line: tripLines[index], service: service, stops: indexes,
                arrivals: ordered.map(\.arrival), departures: ordered.map(\.departure), shape: shapeIndex[shapeId]
            ))
        }
        guard !trips.isEmpty else { throw ImportError.noRail }

        self.init(importedAt: importedAt, stops: stops, lines: lines, services: services, trips: trips, shapes: shapes)
    }

    /// "25:10:00" as 90,600 seconds; nil when empty or malformed. Hours may pass 24 and may have one digit.
    static func seconds(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 3, let hours = Int(parts[0]), let minutes = Int(parts[1]), let seconds = Int(parts[2]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}

extension ServiceDay {
    /// The GTFS date, 20261109.
    var dateKey: Int { year * 10_000 + month * 100 + day }

    init(dateKey: Int) {
        self.init(year: dateKey / 10_000, month: dateKey / 100 % 100, day: dateKey % 100)
    }

    /// A GTFS stop time on this service day. GTFS counts from noon minus 12 h, Toronto time, so a DST day and a time past
    /// 24:00 land on the right moment: 25:10:00 is 1:10 AM the next morning, still this service day (D24).
    func gtfsTime(_ seconds: Int) -> Date {
        noon.addingTimeInterval(TimeInterval(seconds - 12 * 3600))
    }
}

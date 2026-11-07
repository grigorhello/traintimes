import Foundation

/// The rail part of a GTFS feed, as kept on device (TT-130, D35): stations, lines, each service's dates and each trip's
/// stops and times. Feed types stay inside the GTFS repository; screens read domain types (`GTFSTimetable`).
struct GTFSFeed: Codable, Sendable, Equatable {
    struct Stop: Codable, Sendable, Equatable {
        let id: String
        let name: String
    }

    struct Line: Codable, Sendable, Equatable {
        /// The route's short name ("LW"), which stays the same from one feed to the next; the route id does not.
        let id: String
        let name: String
        /// "#98002e"; nil when the feed has none.
        let color: String?
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
    }

    var importedAt: Date
    var stops: [Stop]
    var lines: [Line]
    /// Each service's dates as yyyymmdd, ascending.
    var services: [[Int]]
    var trips: [Trip]
}

extension GTFSFeed {
    enum ImportError: Error, Equatable {
        case missingFile(String)
        case noRail
    }

    /// Imports the rail routes (route_type 2) of a GTFS zip.
    init(zip data: Data, importedAt: Date) throws {
        let archive = try ZipArchive(data: data)
        try self.init(importedAt: importedAt) { try archive.data(named: $0) }
    }

    /// Imports the rail routes (route_type 2): their trips, stop times, stations and service dates. `file` returns a feed
    /// file's contents by name, nil when the feed has none.
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
                lines.append(Line(id: id, name: name.isEmpty ? id : name, color: color.isEmpty ? nil : "#\(color)"))
            }
            lineByRoute[route["route_id"]] = lines.firstIndex { $0.id == id }
        }
        guard !lines.isEmpty else { throw ImportError.noRail }

        // Their trips.
        var tripIds: [String] = []
        var tripLines: [Int] = []
        var tripServices: [String] = []
        var tripIndex: [String: Int] = [:]
        try GTFSCSV.forEach(in: required("trips.txt")) { trip in
            guard let line = lineByRoute[trip["route_id"]], tripIndex[trip["trip_id"]] == nil else { return }
            tripIndex[trip["trip_id"]] = tripIds.count
            tripIds.append(trip["trip_id"])
            tripLines.append(line)
            tripServices.append(trip["service_id"])
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
        var parents: [String: String] = [:]
        try GTFSCSV.forEach(in: required("stops.txt")) { stop in
            stopNames[stop["stop_id"]] = stop["stop_name"]
            if !stop["parent_station"].isEmpty { parents[stop["stop_id"]] = stop["parent_station"] }
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
                    stops.append(Stop(id: id, name: name.isEmpty ? id : name))
                }
                indexes.append(stopIndex[id] ?? 0)
            }
            trips.append(Trip(
                id: tripIds[index], line: tripLines[index], service: service, stops: indexes,
                arrivals: ordered.map(\.arrival), departures: ordered.map(\.departure)
            ))
        }
        guard !trips.isEmpty else { throw ImportError.noRail }

        self.init(importedAt: importedAt, stops: stops, lines: lines, services: services, trips: trips)
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

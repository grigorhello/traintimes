import Foundation
import os

/// The writer's log (TT-185): a write that failed, or one that never finished, left no trace, and the widgets kept
/// the old file. No rider data in it: the sizes and the error's type only.
private let widgetLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TrainTimes", category: "widgets")

/// The routes of the widgets placed on the Home and Lock Screens: `PlacedWidgetRoutes` reads their From and To from
/// WidgetKit (TT-183).
protocol WidgetRoutesProviding: Sendable {
    /// Throws when the widgets cannot be read: that write is skipped and the last file stays.
    func routes() async throws -> [Route]
}

struct NoWidgetRoutes: WidgetRoutesProviding {
    func routes() async -> [Route] { [] }
}

/// Writes the widget file into the App Group container (TT-182, D107): the open route and each widget's route both ways for
/// 14 service days (or to the feed's end), the alerted trains, the Repeat alerts' usual times, the Time format and the
/// stations. It reads the real schedule and the device clock, never Settings › Testing (Demo trains, Mock time), and fixture
/// runs make none. The widgets reload only when the bytes change.
@MainActor
final class WidgetFileWriter {
    static let days = 14

    private let repository: any ScheduleRepository
    private let stations: any StationRepository
    private let clock: any AppClock
    private let fileURL: URL
    private let widgetRoutes: any WidgetRoutesProviding
    private let routeStore: any RouteStoring
    private let rules: AlertRules
    private let settings: AppSettings
    private let recents: RecentRoutes
    private let reload: @MainActor () -> Void
    private var running: Task<Void, Never>?
    private var writesAgain = false

    init(
        repository: any ScheduleRepository, stations: any StationRepository, clock: any AppClock = SystemClock(), fileURL: URL,
        widgetRoutes: any WidgetRoutesProviding = NoWidgetRoutes(), routeStore: any RouteStoring, rules: AlertRules,
        settings: AppSettings, recents: RecentRoutes, reload: @escaping @MainActor () -> Void
    ) {
        self.repository = repository
        self.stations = stations
        self.clock = clock
        self.fileURL = fileURL
        self.widgetRoutes = widgetRoutes
        self.routeStore = routeStore
        self.rules = rules
        self.settings = settings
        self.recents = recents
        self.reload = reload
    }

    /// Writes the file soon: at launch, each time the app comes to the front (a widget placed or edited meanwhile gets
    /// its route), after a route, alert, Time format or timetable change and on going to the background. A call while a
    /// write runs writes once more after it.
    func update() {
        guard running == nil else {
            writesAgain = true
            return
        }
        running = Task {
            repeat {
                writesAgain = false
                await write()
            } while writesAgain
            running = nil
        }
    }

    /// Writes the file now, atomically, and reloads the widgets when its bytes changed. False when nothing changed or the
    /// schedule could not be read (the last file stays).
    @discardableResult
    func write() async -> Bool {
        widgetLog.info("Widget file: write starts")
        let data: Data
        do {
            data = try await makeFile().encoded()
        } catch {
            widgetLog.error("Widget file: not made, \(String(describing: type(of: error)), privacy: .public)")
            return false
        }
        guard (try? Data(contentsOf: fileURL)) != data else {
            widgetLog.info("Widget file: unchanged")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            widgetLog.error("Widget file: not saved, \(String(describing: type(of: error)), privacy: .public)")
            return false
        }
        reload()
        widgetLog.info("Widget file: written, \(data.count, privacy: .public) bytes")
        return true
    }

    func makeFile() async throws -> WidgetFile {
        let now = clock.now
        let firstDay = ServiceDay(containing: now)
        var lastDay = firstDay.adding(days: Self.days - 1)
        if let end = try await repository.lastServiceDay(), end < lastDay { lastDay = end }
        let days = firstDay <= lastDay ? (0...firstDay.days(to: lastDay)).map { firstDay.adding(days: $0) } : []

        let open = routeStore.route
        let placed = try await widgetRoutes.routes()
        var routes: [Route] = []
        for route in [open].compactMap({ $0 }) + placed where !routes.contains(where: { $0.joinsSameStations(as: route) }) {
            routes.append(route)
        }
        var timetables: [WidgetFile.Timetable] = []
        for route in routes {
            let outbound = try await departures(route, on: days)
            let inbound = try await departures(Route(from: route.to, to: route.from, line: route.line), on: days)
            timetables.append(
                WidgetFile.Timetable(
                    from: WidgetFile.Stop(route.from), to: WidgetFile.Stop(route.to),
                    line: route.line.map { WidgetFile.TrainLine(id: $0.id, name: $0.name, colorHex: $0.colorHex) },
                    outbound: outbound, inbound: inbound
                )
            )
        }

        let morning = open.map { route in
            let key = WidgetFile.RouteKey(fromId: route.from.id, toId: route.to.id)
            return now < firstDay.date(hour: WidgetEntryBuilder.turnAroundHour, minute: 0) ? key : key.reversed
        }
        let usualTimes = rules.rules.filter { $0.kind == .repeating && !$0.paused }.map { rule in
            WidgetFile.UsualTime(
                route: WidgetFile.RouteKey(fromId: rule.origin.id, toId: rule.destination.id),
                minutesIntoDay: ServiceDay.minutesIntoServiceDay(rule.scheduledDeparture), weekdays: rule.weekdays.sorted()
            )
        }
        var yourStationIds: [String] = []
        for id in recents.routes.flatMap({ [$0.from.id, $0.to.id] }) where !yourStationIds.contains(id) {
            yourStationIds.append(id)
        }
        let allStations = try await stations.stations().map { WidgetFile.Stop($0) }
        return WidgetFile(
            firstDay: firstDay, lastDay: lastDay, openRoute: morning, routes: timetables, usualTimes: usualTimes,
            timeFormat: settings.timeFormat, stations: allStations, yourStationIds: yourStationIds
        )
    }

    private func departures(_ route: Route, on days: [ServiceDay]) async throws -> [WidgetFile.Departure] {
        var departures: [WidgetFile.Departure] = []
        for day in days {
            let trips = try await repository.trips(for: route, on: day)
            for trip in trips {
                departures.append(
                    WidgetFile.Departure(
                        tripId: trip.key.tripId, serviceDay: trip.key.serviceDay, departure: trip.scheduledDeparture,
                        arrival: trip.scheduledArrival, isExpress: trip.tags.contains(.express),
                        isAlerted: rules.isAlerted(trip, on: route)
                    )
                )
            }
        }
        return departures.sorted { ($0.departure, $0.tripId) < ($1.departure, $1.tripId) }
    }
}

private extension WidgetFile.Stop {
    init(_ station: Station) {
        self.init(id: station.id, name: station.name, lines: station.lines)
    }
}

private extension Route {
    /// The same two stations, either way.
    func joinsSameStations(as other: Route) -> Bool {
        isSameDirection(as: other) || (from.id == other.to.id && to.id == other.from.id)
    }
}

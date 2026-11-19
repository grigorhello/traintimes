import Foundation

/// The widget file (TT-182, D107): what the app writes into the App Group container for the widgets to read, the only
/// thing the two share. Timetable only: no live status (D13), the real clock and the real schedule, never Settings ›
/// Testing. Written whole with a format version; a file of another version reads as not loaded.
struct WidgetFile: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let fileName = "widgets.json"

    var version = WidgetFile.currentVersion
    /// The service day the file starts on and the last one it covers: 14 days, or to the feed's end.
    var firstDay: ServiceDay
    var lastDay: ServiceDay
    /// The route open in the app, in its morning way (as shown when written before 12 PM, reversed after); a widget with no
    /// route of its own shows it. Nil before the first route.
    var openRoute: RouteKey?
    /// The open route and each placed widget's route, both ways, once per pair of stations.
    var routes: [Timetable]
    /// The usual times of the Repeat alerts that are switched on, for relevance only.
    var usualTimes: [UsualTime]
    /// Settings › Time format, so the widgets write times as the app does (D17).
    var timeFormat: TimeFormat
    /// Every station, and the ids of Your stations (the recent routes' stations), for the widget's station search (TT-183).
    var stations: [Stop]
    var yourStationIds: [String]

    /// A direction between two stations, by id.
    struct RouteKey: Codable, Hashable, Sendable {
        var fromId: String
        var toId: String

        var reversed: RouteKey { RouteKey(fromId: toId, toId: fromId) }
    }

    struct Stop: Codable, Hashable, Sendable {
        var id: String
        var name: String
        var lines: [String] = []
    }

    struct TrainLine: Codable, Hashable, Sendable {
        var id: String
        var name: String
        var colorHex: String?
    }

    /// One route's trains, From → To (`outbound`) and To → From (`inbound`), by absolute time across the file's days.
    struct Timetable: Codable, Hashable, Sendable {
        var from: Stop
        var to: Stop
        var line: TrainLine?
        var outbound: [Departure]
        var inbound: [Departure]

        var key: RouteKey { RouteKey(fromId: from.id, toId: to.id) }

        /// The trains and stations of one direction, when it joins the same two stations.
        func direction(_ key: RouteKey) -> (from: Stop, to: Stop, trains: [Departure])? {
            if key == self.key { return (from, to, outbound) }
            if key == self.key.reversed { return (to, from, inbound) }
            return nil
        }
    }

    struct Departure: Codable, Hashable, Sendable {
        var tripId: String
        var serviceDay: ServiceDay
        var departure: Date
        var arrival: Date
        var isExpress: Bool
        /// An alert that is switched on covers the train (D70): the widget's bell, Your train and relevance.
        var isAlerted: Bool

        var key: TripKey { TripKey(serviceDay: serviceDay, tripId: tripId) }
    }

    /// A Repeat alert's usual train: its direction, minutes into the service day and ISO weekdays (1 is Monday).
    struct UsualTime: Codable, Hashable, Sendable {
        var route: RouteKey
        var minutesIntoDay: Int
        var weekdays: [Int]
    }

    /// The route's timetable, in either direction.
    func timetable(for key: RouteKey) -> Timetable? {
        routes.first { $0.direction(key) != nil }
    }

    /// The file in the App Group container, or nil when it is missing, unreadable or of another version.
    static func read(from url: URL) -> WidgetFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> WidgetFile? {
        struct Version: Decodable { let version: Int }
        guard (try? JSONDecoder().decode(Version.self, from: data))?.version == currentVersion else { return nil }
        return try? JSONDecoder().decode(WidgetFile.self, from: data)
    }

    /// The same bytes for the same contents (sorted keys), so the writer can tell a change from a rewrite.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    /// The App Group container's widget file; nil when the build is not entitled to the group.
    static var containerFileURL: URL? {
        AppGroup.containerURL?.appending(path: fileName)
    }
}

/// The widgets by the names links and analytics use, and each one's WidgetKit kind: the Home Screen's two (TT-183) and
/// Next train's three Lock Screen sizes (TT-184), which are the same WidgetKit widget under names of their own.
enum WidgetKind: String, CaseIterable, Sendable {
    case nextTrain = "next_train"
    case departures
    case lockRectangular = "lock_rectangular"
    case lockCircular = "lock_circular"
    case lockInline = "lock_inline"

    /// The kind WidgetKit knows the widget by.
    var kind: String {
        switch self {
        case .nextTrain, .lockRectangular, .lockCircular, .lockInline: "NextTrain"
        case .departures: "Departures"
        }
    }

    /// One of Next train's Lock Screen sizes.
    var isOnLockScreen: Bool {
        switch self {
        case .lockRectangular, .lockCircular, .lockInline: true
        case .nextTrain, .departures: false
        }
    }

    /// The widget of a WidgetKit kind; a Lock Screen size is told from Next train by its family (`init(kind:family:)`).
    init?(kind: String) {
        guard let match = [Self.nextTrain, .departures].first(where: { $0.kind == kind }) else { return nil }
        self = match
    }
}

/// The app's links (TT-182): a widget's train and header, as `traintimes://trip?…` and `traintimes://route?…`, with the
/// notification payload's keys (D39). The app reads them with `NotificationLink(url:today:)`.
enum WidgetLink {
    static let scheme = "traintimes"

    /// Trip details for the train, on the route it was shown on.
    static func trip(_ key: TripKey, route: WidgetFile.RouteKey) -> URL {
        url(host: "trip", [
            "tripId": key.tripId, "serviceDate": key.serviceDay.gtfsDate, "originId": route.fromId, "destinationId": route.toId,
        ])
    }

    /// Schedule on the route at Now; with no route, the Schedule tab.
    static func route(_ route: WidgetFile.RouteKey?) -> URL {
        url(host: "route", route.map { ["originId": $0.fromId, "destinationId": $0.toId] } ?? [:])
    }

    /// The link as a widget opens it (TT-183): `source=widget&widget=next_train` beside its own items, so the app counts the
    /// tap (`widget_opened`). `NotificationLink(url:today:)` ignores both.
    static func tagged(_ url: URL, from widget: WidgetKind) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != "source" && $0.name != "widget" }
        items += [URLQueryItem(name: "source", value: "widget"), URLQueryItem(name: "widget", value: widget.rawValue)]
        components.queryItems = items.sorted { $0.name < $1.name }
        return components.url ?? url
    }

    /// The widget a link was tapped on; nil for every other link.
    static func widget(of url: URL) -> WidgetKind? {
        guard url.scheme == scheme, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "source" })?.value == "widget" else { return nil }
        return items.first { $0.name == "widget" }?.value.flatMap(WidgetKind.init(rawValue:))
    }

    private static func url(host: String, _ items: [String: String]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if !items.isEmpty {
            components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }
}

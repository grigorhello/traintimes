import AppIntents
import Foundation

/// Edit widget (TT-183, D101; board Widgets-Edit): From, To and "Turn around at 12 PM", one intent for Next train and
/// Departures. In `Shared/` so the app reads each placed widget's stations from WidgetKit (`SystemPlacedWidgets`).
struct TrainWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.edit.title"
    /// Edit widget only: not an action in Shortcuts or Spotlight.
    static let isDiscoverable = false

    @Parameter(title: "widget.edit.from", query: FromStationQuery())
    var from: StationEntity?

    @Parameter(title: "widget.edit.to", query: ToStationQuery())
    var to: StationEntity?

    @Parameter(title: "widget.edit.turn_around", description: "widget.edit.turn_around.description", default: true)
    var turnsAround: Bool

    init() {}

    /// The widget's own route; with no From or no To it follows the route open in the app.
    var route: WidgetFile.RouteKey? {
        guard let from, let to, from.id != to.id else { return nil }
        return WidgetFile.RouteKey(fromId: from.id, toId: to.id)
    }
}

/// A station in Edit widget: its GTFS stop id and its full name, from the widget file's station list.
struct StationEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "widget.edit.station"
    static let defaultQuery = StationQuery()

    let id: String
    let name: String

    init(_ stop: WidgetFile.Stop) {
        id = stop.id
        name = stop.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// The stations Edit widget offers: Your stations first, then every station, searched like the app's station picker (a
/// word prefix, case and accent insensitive, D54). A stored id resolves to its station.
struct StationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        WidgetStations.current.stops(for: identifiers).map(StationEntity.init)
    }

    func entities(matching string: String) async throws -> [StationEntity] {
        WidgetStations.current.matching(string).map(StationEntity.init)
    }

    func suggestedEntities() async throws -> [StationEntity] {
        WidgetStations.current.suggested.map(StationEntity.init)
    }
}

/// From's stations. A new widget starts on the route open in the app, in its morning way (before 12 PM the route as
/// shown, after it the reverse), and keeps that pair from then on.
struct FromStationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        WidgetStations.current.stops(for: identifiers).map(StationEntity.init)
    }

    func entities(matching string: String) async throws -> [StationEntity] {
        WidgetStations.current.matching(string).map(StationEntity.init)
    }

    func suggestedEntities() async throws -> [StationEntity] {
        WidgetStations.current.suggested.map(StationEntity.init)
    }

    func defaultResult() async -> StationEntity? {
        WidgetStations.current.defaultFrom.map(StationEntity.init)
    }
}

/// To's stations; a new widget's To is the open route's other end.
struct ToStationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        WidgetStations.current.stops(for: identifiers).map(StationEntity.init)
    }

    func entities(matching string: String) async throws -> [StationEntity] {
        WidgetStations.current.matching(string).map(StationEntity.init)
    }

    func suggestedEntities() async throws -> [StationEntity] {
        WidgetStations.current.suggested.map(StationEntity.init)
    }

    func defaultResult() async -> StationEntity? {
        WidgetStations.current.defaultTo.map(StationEntity.init)
    }
}

/// The station lists behind Edit widget, from the widget file (TT-182), apart from App Intents so they are unit tested.
struct WidgetStations: Sendable {
    let file: WidgetFile?

    /// The file in the App Group container, as it is now.
    static var current: WidgetStations {
        WidgetStations(file: WidgetFile.containerFileURL.flatMap { WidgetFile.read(from: $0) })
    }

    /// Your stations (the recent routes' stations, newest first), then the rest as the file lists them.
    var suggested: [WidgetFile.Stop] {
        guard let file else { return [] }
        let yours = file.yourStationIds.compactMap { id in file.stations.first { $0.id == id } }
        return yours + file.stations.filter { !file.yourStationIds.contains($0.id) }
    }

    /// The suggested stations whose name, or a word of it, starts with the typed text; all of them with nothing typed.
    func matching(_ text: String) -> [WidgetFile.Stop] {
        let text = text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? suggested : suggested.filter { StationNames.matches($0.name, prefix: text) }
    }

    /// The stations with these ids, in the ids' order; an id the file does not list is left out.
    func stops(for ids: [String]) -> [WidgetFile.Stop] {
        guard let file else { return [] }
        return ids.compactMap { id in file.stations.first { $0.id == id } }
    }

    /// A new widget's From and To: the route open in the app, in its morning way.
    var defaultFrom: WidgetFile.Stop? {
        file?.openRoute.flatMap { stops(for: [$0.fromId]).first }
    }

    var defaultTo: WidgetFile.Stop? {
        file?.openRoute.flatMap { stops(for: [$0.toId]).first }
    }
}

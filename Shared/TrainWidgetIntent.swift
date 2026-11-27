import AppIntents
import Foundation

/// Edit widget (TT-183, D101; TT-257, D131, board "Commute first" 8): Show, My trains or A route, and for A route From, To
/// and "Turn around at 12 PM"; one intent for Next train, Departures and the Lock Screen sizes. In `Shared/` so the app
/// reads each placed widget's choice from WidgetKit (`SystemPlacedWidgets`).
struct TrainWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.edit.title"
    static var description: IntentDescription { IntentDescription("widget.edit.description") }
    /// Edit widget only: not an action in Shortcuts or Spotlight.
    static let isDiscoverable = false

    /// My trains for every widget, a placed one never edited included (iOS stores no optional default, D131); A route
    /// brings back From and To.
    @Parameter(title: "widget.edit.show", default: .myTrains)
    var show: WidgetShow

    @Parameter(title: "widget.edit.from")
    var from: StationEntity?

    @Parameter(title: "widget.edit.to")
    var to: StationEntity?

    @Parameter(title: "widget.edit.turn_around", description: "widget.edit.turn_around.description", default: true)
    var turnsAround: Bool

    init() {}

    /// From, To and Turn around only under A route.
    static var parameterSummary: some ParameterSummary {
        When(\.$show, .equalTo, .route) {
            Summary {
                \.$show
                \.$from
                \.$to
                \.$turnsAround
            }
        } otherwise: {
            Summary {
                \.$show
            }
        }
    }

    var mode: WidgetMode { show.mode }

    /// A route's own stations; with no From or no To it follows the route open in the app, as My trains does with no saved
    /// train.
    var route: WidgetFile.RouteKey? {
        guard show == .route, let from, let to, from.id != to.id else { return nil }
        return WidgetFile.RouteKey(fromId: from.id, toId: to.id)
    }
}

/// Edit widget's Show.
enum WidgetShow: String, AppEnum, CaseIterable {
    case myTrains = "my_trains"
    case route

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "widget.edit.show") }

    static var caseDisplayRepresentations: [WidgetShow: DisplayRepresentation] {
        [.myTrains: DisplayRepresentation(title: "widget.edit.my_trains"), .route: DisplayRepresentation(title: "widget.edit.a_route")]
    }

    var mode: WidgetMode {
        switch self {
        case .myTrains: .myTrains
        case .route: .route
        }
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
}

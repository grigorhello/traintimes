import AppIntents
import Foundation
import WidgetKit

/// One widget on the Home Screen, in StandBy or on the Lock Screen (TT-183, TT-184): which one, its own route when
/// Edit widget shows A route with a From and a To, and its Show (TT-257, D131).
struct PlacedWidget: Equatable, Sendable {
    let kind: WidgetKind
    let route: WidgetFile.RouteKey?
    var mode: WidgetMode = .myTrains
}

extension WidgetKind {
    /// A placed widget by its WidgetKit kind and family: Next train's Lock Screen sizes go by their own names (TT-184).
    init?(kind: String, family: WidgetFamily) {
        guard let widget = WidgetKind(kind: kind) else { return nil }
        switch (widget, family) {
        case (.nextTrain, .accessoryRectangular): self = .lockRectangular
        case (.nextTrain, .accessoryCircular): self = .lockCircular
        case (.nextTrain, .accessoryInline): self = .lockInline
        default: self = widget
        }
    }
}

/// The widgets the rider has placed; nil when they could not be read, which is not the same as none. Tests pass a fake;
/// the app asks WidgetKit.
protocol PlacedWidgetsProviding: Sendable {
    func widgets() async -> [PlacedWidget]?
}

/// WidgetKit's list of the placed widgets with their Edit widget settings (`TrainWidgetIntent`).
struct SystemPlacedWidgets: PlacedWidgetsProviding {
    func widgets() async -> [PlacedWidget]? {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let placed = (try? result.get())?.compactMap { info -> PlacedWidget? in
                    guard let kind = WidgetKind(kind: info.kind, family: info.family) else { return nil }
                    let intent = info.widgetConfigurationIntent(of: TrainWidgetIntent.self)
                    return PlacedWidget(kind: kind, route: intent?.route, mode: intent?.mode ?? .myTrains)
                }
                continuation.resume(returning: placed)
            }
        }
    }
}

/// The placed widgets' routes for the widget file (TT-182's `WidgetRoutesProviding`): each widget's From and To as the
/// feed's stations, so the file carries their timetables. A widget whose route is not in the file yet shows "Open Train
/// Times once" until the app next writes the file (at launch and each time it comes to the front). When the widgets
/// cannot be read it throws, and the writer keeps the last file rather than drop their routes.
struct PlacedWidgetRoutes: WidgetRoutesProviding {
    struct Unreadable: Error {}

    let widgets: any PlacedWidgetsProviding
    let stations: any StationRepository

    func routes() async throws -> [Route] {
        guard let placed = await widgets.widgets() else { throw Unreadable() }
        let keys = placed.compactMap(\.route)
        guard !keys.isEmpty else { return [] }
        let all = try await stations.stations()
        var routes: [Route] = []
        for key in keys {
            guard let from = all.first(where: { $0.id == key.fromId }), let to = all.first(where: { $0.id == key.toId }),
                  let route = try? await stations.route(from: from, to: to) else { continue }
            routes.append(route)
        }
        return routes
    }
}

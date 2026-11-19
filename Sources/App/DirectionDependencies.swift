import Foundation

/// What Automatic direction's look reads (TT-234, D116): the phone's location through its own reader, the store on device
/// and the track between the route's stations. Previews, the unit test host and UI tests get no reader, so a test never
/// raises the iOS prompt (Demo place is their way in), and no track. UI tests keep the store on device, so an Undo hour
/// lasts into the next launch; the unit test host and previews keep it in memory.
@MainActor
struct DirectionDependencies {
    let location: any DirectionLocating
    let store: DirectionStore
    /// The track between a route's two stations from a service day on, for the train check; nil leaves the check out.
    var track: @Sendable (Route, ServiceDay) async -> DirectionRule.Track? = { _, _ in nil }
    /// How long after a look starts its answer still turns the route. UI tests get longer: a slow runner's launch can
    /// keep the main thread busy past the rule's second, and the look would ask where the test expects the turn.
    var quick: Duration = DirectionRule.quick

    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> DirectionDependencies {
        if ScheduleDependencies.isFixtureRun(environment) {
            return DirectionDependencies(
                location: NoDirectionLocation(),
                store: DirectionStore(defaults: environment["TT_FIXTURES"] != nil ? .standard : nil),
                quick: environment["TT_FIXTURES"] != nil ? .seconds(5) : DirectionRule.quick
            )
        }
        return DirectionDependencies(
            location: SystemDirectionLocation(),
            store: DirectionStore(),
            track: { route, day in
                guard let timetable = try? await GTFSFeedStore.shared.timetable() else { return nil }
                return timetable.directionTrack(between: route.from.id, and: route.to.id, from: day)
            }
        )
    }
}

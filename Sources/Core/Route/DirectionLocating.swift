import Foundation

/// Whether Automatic direction may look at the location (TT-234, D116).
enum DirectionPermission: Equatable, Sendable {
    /// When In Use or Always.
    case allowed
    /// iOS has not asked yet, or Allow Once ran out.
    case notAsked
    /// The rider said no, or location is restricted.
    case refused
    /// No reader here: fixture runs, previews and the unit test host. The setting reads off and a tap does nothing.
    case unavailable
}

/// The one look at the location that sets the route's direction when the app opens (TT-234, D116). Its own reader: never
/// the ride's `LocationProviding` nor train detection's. The look reads `permission` right before each start and never
/// asks; only the Settings switch calls `requestWhenInUse()`.
@MainActor
protocol DirectionLocating: AnyObject {
    var permission: DirectionPermission { get }
    /// Precise Location is on.
    var isPrecise: Bool { get }
    /// The iOS prompt, from the rider's tap on the Settings switch. True when location is allowed after it.
    func requestWhenInUse() async -> Bool
    /// Starts reading: each reading as it comes, until `stop()`.
    func start(_ onReading: @escaping @MainActor (DirectionReading) -> Void)
    func stop()
}

extension DirectionLocating {
    /// Automatic direction reads on: location allowed with Precise Location, unless the rider turned it off.
    func readsOn(_ store: DirectionStore) -> Bool {
        permission == .allowed && isPrecise && !store.isOff
    }
}

/// No reader: fixture runs, previews and the unit test host, so a test never raises the iOS prompt.
@MainActor
final class NoDirectionLocation: DirectionLocating {
    var permission: DirectionPermission { .unavailable }
    var isPrecise: Bool { false }
    func requestWhenInUse() async -> Bool { false }
    func start(_ onReading: @escaping @MainActor (DirectionReading) -> Void) {}
    func stop() {}
}

/// Settings › Testing › Demo place (TT-234, D116), for TestFlight and Debug builds: Off, or one of the route's two
/// stations by id. UI tests set it with `-settings.demoPlace <station id>`.
enum DemoPlace {
    static let key = "settings.demoPlace"

    /// The stored station id, nil when off or when the build has no Testing section.
    static var stored: String? {
        guard BuildChannel.showsTesting, let id = UserDefaults.standard.string(forKey: key), !id.isEmpty else { return nil }
        return id
    }

    /// The stored id when it is one of `route`'s two stations; any other reads Off.
    static func station(on route: Route?, stored: String? = DemoPlace.stored) -> String? {
        guard let stored, let route, stored == route.from.id || stored == route.to.id else { return nil }
        return stored
    }
}

/// The reader with Demo place over it: while a demo place is on it counts as location allowed with Precise Location and
/// gives one reading at that station's place, with no radius and no age, at once. Off, it is the reader under it.
@MainActor
final class DemoPlaceLocation: DirectionLocating {
    private let base: any DirectionLocating
    private let stations: any StationRepository
    private let route: @MainActor () -> Route?
    private let stored: @MainActor () -> String?
    private var reading: Task<Void, Never>?

    init(
        base: any DirectionLocating, stations: any StationRepository, route: @escaping @MainActor () -> Route?,
        stored: @escaping @MainActor () -> String? = { DemoPlace.stored }
    ) {
        self.base = base
        self.stations = stations
        self.route = route
        self.stored = stored
    }

    private var station: String? { DemoPlace.station(on: route(), stored: stored()) }

    var permission: DirectionPermission { station == nil ? base.permission : .allowed }
    var isPrecise: Bool { station == nil ? base.isPrecise : true }

    func requestWhenInUse() async -> Bool {
        station == nil ? await base.requestWhenInUse() : true
    }

    func start(_ onReading: @escaping @MainActor (DirectionReading) -> Void) {
        guard let station else { return base.start(onReading) }
        let stations = stations
        reading?.cancel()
        reading = Task {
            let place = (try? await stations.stations())?.first { $0.id == station }?.place
            guard !Task.isCancelled, let place else { return }
            onReading(DirectionReading(place: place, radius: 0, age: 0))
        }
    }

    func stop() {
        reading?.cancel()
        reading = nil
        base.stop()
    }
}

import Foundation
@testable import TrainTimes

/// The phone's location in Automatic direction's tests (TT-234, D116): a permission a test sets, an iOS prompt that
/// answers `answer` and counts each time it is shown, and the readings a test sends while the look reads.
@MainActor
final class FakeDirectionLocation: DirectionLocating {
    var permission: DirectionPermission
    var isPrecise: Bool
    /// The permission after the iOS prompt.
    var answer: DirectionPermission = .allowed
    /// Calls of `requestWhenInUse()`: the look must leave it at 0.
    private(set) var requests = 0
    private(set) var starts = 0
    private(set) var stops = 0
    private var onReading: (@MainActor (DirectionReading) -> Void)?

    /// Started and not stopped.
    var isReading: Bool { onReading != nil }

    init(permission: DirectionPermission = .allowed, isPrecise: Bool = true) {
        self.permission = permission
        self.isPrecise = isPrecise
    }

    func requestWhenInUse() async -> Bool {
        requests += 1
        permission = answer
        return permission == .allowed
    }

    func start(_ onReading: @escaping @MainActor (DirectionReading) -> Void) {
        starts += 1
        self.onReading = onReading
    }

    func stop() {
        stops += 1
        onReading = nil
    }

    /// Hands a reading to the running look; nothing when not reading.
    func send(_ reading: DirectionReading) {
        onReading?(reading)
    }
}

/// Schedule's side of the look in tests: a route a test sets, and a silent turn that is counted.
@MainActor
final class FakeRouteTurning: RouteTurning {
    var route: Route?
    var isToday = true
    private(set) var turnCount = 0

    init(route: Route?) {
        self.route = route
    }

    /// The route becomes its reverse.
    func turn() async {
        turnCount += 1
        if let route { self.route = Route(from: route.to, to: route.from, line: route.line) }
    }
}

/// The ride engine's side of the look in tests: a ride held, and a ride that ended at your stop.
@MainActor
final class FakeRideSource: DirectionRideSource {
    var holdsRide = false
    var arrival: RideArrival?

    init() {}
}

/// Automatic direction's test values (TT-234, D116): Oakville GO to Union Station on Lakeshore West, with the stations'
/// real places, about 32 km apart.
enum DirectionFixtures {
    static let oakvillePlace = GeoPoint(latitude: 43.455594, longitude: -79.682242)
    static let unionPlace = GeoPoint(latitude: 43.645195, longitude: -79.3806)

    static let oakville = Station(id: "OA", name: "Oakville GO", place: oakvillePlace)
    static let union = Station(id: "UN", name: "Union Station", place: unionPlace)

    /// Oakville to Union.
    static let route = Route(from: oakville, to: union, line: Line(id: "LW", name: "Lakeshore West", colorHex: nil))

    /// A station list that holds both stations with their places, as the GTFS feed gives them.
    static let stations: any StationRepository = PlacedDirectionStations(list: [oakville, union])

    /// A reading at `place`, fresh and exact unless a test says otherwise.
    static func reading(at place: GeoPoint, radius: Double = 20, age: TimeInterval = 0) -> DirectionReading {
        DirectionReading(place: place, radius: radius, age: age)
    }
}

/// A station list a test fills.
struct PlacedDirectionStations: StationRepository {
    let list: [Station]

    func stations() async throws -> [Station] { list }
    func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: nil) }
}

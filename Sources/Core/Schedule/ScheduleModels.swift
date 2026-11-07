import Foundation

struct Station: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// The lines that serve the station, for its line context in station search (TT-121). Empty where unknown, as for
    /// the saved route.
    var lines: [String] = []

    /// One station is one id, whatever name or lines it was loaded with, so a station from the saved route equals the
    /// same station picked in search.
    static func == (lhs: Station, rhs: Station) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Line: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// Hex colour from feed metadata ("#111827"); nil when the feed has none (the header then uses ink-secondary).
    let colorHex: String?
}

struct Route: Hashable, Sendable {
    let from: Station
    let to: Station
    let line: Line?
}

/// A trip's identity (D9): service date plus the feed's trip id, never departure time.
struct TripKey: Hashable, Sendable {
    let serviceDay: ServiceDay
    let tripId: String
}

enum Platform: Hashable, Sendable {
    case published(String)
    case pending
}

/// Express is the only tag in v1 (D21); it is shown only when the feed verifies it.
enum TrainTag: String, Hashable, Sendable {
    case express
}

/// The closed status set (D12).
enum TrainStatus: Hashable, Sendable {
    case onTime
    case delayed(minutes: Int, reportedAt: Date)
    case cancelled(reportedAt: Date)
    case stopSkipped
    case scheduled
    case stale(lastReported: Date)
    case offline
}

/// One direct train between the route's stations, as published in the schedule.
struct Trip: Hashable, Sendable, Identifiable {
    let key: TripKey
    let scheduledDeparture: Date
    let scheduledArrival: Date
    let platform: Platform
    let tags: [TrainTag]

    var id: TripKey { key }
}

/// Live evidence for one trip, as reported by the feed.
struct LiveTripUpdate: Hashable, Sendable {
    var expectedDeparture: Date?
    var expectedArrival: Date?
    /// Reported departure delay; derived from `expectedDeparture` when the feed gives none.
    var delayMinutes: Int?
    var isCancelled = false
    var isStopSkipped = false
    var reportedAt: Date
}

/// Everything the live feed said for a route and service day.
struct LiveSnapshot: Hashable, Sendable {
    /// When the feed was last fetched; nil when there is no live data.
    var updatedAt: Date?
    var isOffline = false
    /// Keyed by feed trip id.
    var updates: [String: LiveTripUpdate] = [:]

    static let empty = LiveSnapshot(updatedAt: nil)
}

struct LineNotice: Hashable, Sendable, Identifiable {
    let id: String
    let lineName: String
    let text: String
    let reportedAt: Date
}

/// The schedule as the timeline reads it: fixtures in M1, GTFS (TT-130) and GTFS-realtime (TT-131) later.
protocol ScheduleRepository: Sendable {
    /// Direct trains that stop at both stations in order, for one service day.
    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip]
    /// Live status for the same route and day.
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot
    /// Line-wide notices; they never change a trip's status.
    func lineNotices(for line: Line) async throws -> [LineNotice]
}

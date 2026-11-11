import Foundation

struct Station: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// The lines that serve the station, for its line context in the station picker (TT-121). Empty where unknown, as for
    /// the saved route.
    var lines: [String] = []
    /// Where the station is (GTFS stop_lat/stop_lon), for the Directions link on Trip details (TT-188, D64). Nil where the
    /// feed gives none, and on stations that only name a route (the saved route, alert rules).
    var place: GeoPoint?

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
    /// "Platform pending" while offline (`Departure.resolve`).
    var platform: Platform
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
    /// When the live data was produced: the feed's own timestamp, never later than the fetch (TT-131). Nil when there
    /// is no live data.
    var updatedAt: Date?
    var isOffline = false
    /// The feed publishes platforms for this route's origin, so a train with none yet is waiting for one (TT-162). False
    /// for GO's real feeds (D35, D36): neither carries platforms.
    var hasPlatformSource = false
    /// Keyed by feed trip id.
    var updates: [String: LiveTripUpdate] = [:]

    static let empty = LiveSnapshot(updatedAt: nil)
}

/// One stop of a trip between the route's stations (Trip details, TT-118).
struct TripStop: Hashable, Sendable, Identifiable {
    /// Full stop name from the schedule: "Oakville GO".
    let station: Station
    let scheduled: Date
    /// The live feed's estimate for this stop; nil when it gives none.
    var expected: Date?
    /// Reported by the live feed: the train does not stop here.
    var isSkipped = false

    var id: String { station.id }
}

/// A line-wide service notice (TT-132): shown as the Notice chip under the line name, never as a trip status.
struct LineNotice: Hashable, Sendable, Identifiable {
    /// The feed's notice id; dismissing hides this id until a notice with a new id arrives.
    let id: String
    let lineName: String
    /// One sentence: "Delays of up to 15 min near Port Credit".
    let text: String
    /// The full notice, when the feed gives more than the one sentence.
    var details: String?
    let reportedAt: Date
}

/// Today's line notices for the saved route's line that the rider has not dismissed (TT-132), whichever day Schedule
/// shows. Schedule's view model provides them; the Alerts tab lists them apart from trip updates (TT-143).
@MainActor
protocol LineNoticesProviding: AnyObject {
    var todayNotices: [LineNotice] { get }
}

/// The schedule as the timeline reads it: fixtures in previews and tests, the GO GTFS feed in the app (TT-130), and
/// GTFS-realtime (TT-131) later.
protocol ScheduleRepository: Sendable {
    /// Direct trains that stop at both stations in order, for one service day.
    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip]
    /// Live status for the same route and day.
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot
    /// The line-wide notices that apply to a line now; they never change a trip's status.
    func lineNotices(for line: Line) async throws -> [LineNotice]
    /// Every stop of one trip from the route's origin to its destination, in order, with the live feed's estimates and
    /// skipped stops where it reports them (Trip details, TT-118).
    func stops(for trip: TripKey, on route: Route) async throws -> [TripStop]
    /// The last service day the schedule covers; nil when it has no end. The day strip stops there (Q6, TT-130).
    func lastServiceDay() async throws -> ServiceDay?
}

extension ScheduleRepository {
    /// A source with no stop data lists no stops.
    func stops(for trip: TripKey, on route: Route) async throws -> [TripStop] { [] }

    /// A source with no validity window (the fixtures) never ends the day strip early.
    func lastServiceDay() async throws -> ServiceDay? { nil }
}

import Foundation

/// Fetches one of GO's GTFS-realtime feeds: TripUpdates (TT-131, D36) or Alerts (TT-132, D37), relayed by the alert
/// server, which holds the Metrolinx key (TT-179, D88): the app ships no key. One feed covers the whole network, so the
/// Schedule screen and the Trip details sheet share each fetch: a feed fetched in the last 20 s is reused. The last good feed is kept in memory only, so a feed from an earlier run of the app can never show as live.
actor GTFSRealtimeStore {
    /// GO's TripUpdates as the alert server relays them, at most 30 s old.
    static let feedURL = HTTPAlertServer.production.appending(path: "v1/live/trip-updates")
    /// Service alerts, for line notices (TT-132).
    static let alertsURL = HTTPAlertServer.production.appending(path: "v1/live/alerts")
    /// A fetch this recent is reused.
    static let reuseInterval: TimeInterval = 20

    typealias Download = @Sendable () async throws -> Data

    /// The latest feed, and whether the last fetch failed.
    struct Result: Sendable, Equatable {
        /// The last good feed, nil before the first one.
        var feed: GTFSRealtimeFeed?
        /// When the last good feed was fetched.
        var fetchedAt: Date?
        /// The last fetch failed: `feed`, if any, is from an earlier fetch.
        var isOffline: Bool
    }

    private let clock: any AppClock
    private let download: Download
    private var lastGood: (feed: GTFSRealtimeFeed, fetchedAt: Date)?
    private var lastAttempt: (at: Date, failed: Bool)?
    private var fetching: Task<GTFSRealtimeFeed, Error>?

    init(clock: any AppClock = SystemClock(), download: @escaping Download) {
        self.clock = clock
        self.download = download
    }

    /// A feed from the alert server's relay: TripUpdates unless another feed's URL is given. The server answers 503
    /// while GO fails, which shows as Offline.
    static func relay(url: URL = feedURL) -> GTFSRealtimeStore {
        // A dead connection shows Offline within seconds rather than after URLSession's default minute.
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        return GTFSRealtimeStore {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
    }

    /// The feed, fetched again unless the last fetch is under 20 s old. A failed fetch keeps the last good feed and says
    /// so with `isOffline`.
    func latest() async -> Result {
        let now = clock.now
        if let lastAttempt, now.timeIntervalSince(lastAttempt.at) < Self.reuseInterval, fetching == nil {
            return result(isOffline: lastAttempt.failed)
        }
        do {
            let feed = try await fetch()
            lastGood = (feed, clock.now)
            lastAttempt = (now, false)
            return result(isOffline: false)
        } catch {
            lastAttempt = (now, true)
            return result(isOffline: true)
        }
    }

    /// One download however many callers ask at the same time.
    private func fetch() async throws -> GTFSRealtimeFeed {
        if let fetching { return try await fetching.value }
        let task = Task.detached { [download] in try await GTFSRealtimeFeed(protobuf: download()) }
        fetching = task
        defer { fetching = nil }
        return try await task.value
    }

    private func result(isOffline: Bool) -> Result {
        Result(feed: lastGood?.feed, fetchedAt: lastGood?.fetchedAt, isOffline: isOffline)
    }
}

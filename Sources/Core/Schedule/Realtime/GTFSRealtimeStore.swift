import Foundation

/// Fetches one of GO's GTFS-realtime feeds: TripUpdates (TT-131, D36) or Alerts (TT-132, D37). One feed covers the
/// whole network, so the Schedule screen and the Trip details sheet share each fetch: a feed fetched in the last 20 s is
/// reused. The last good feed is kept in memory only, so a feed from an earlier run of the app can never show as live.
actor GTFSRealtimeStore {
    /// The Metrolinx Open Data API needs the key with every call (Q1). The `key` parameter name is to be confirmed when
    /// the key arrives.
    static let feedURL = URL(string: "https://api.openmetrolinx.com/OpenDataAPI/api/V1/Gtfs/Feed/TripUpdates")!
    /// Service alerts, for line notices (TT-132).
    static let alertsURL = URL(string: "https://api.openmetrolinx.com/OpenDataAPI/api/V1/Gtfs/Feed/Alerts")!
    /// A fetch this recent is reused.
    static let reuseInterval: TimeInterval = 20
    /// Info.plist key filled from the `METROLINX_API_KEY` build setting (`Config/Secrets.xcconfig`, never committed).
    static let apiKeyInfoKey = "MetrolinxAPIKey"

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

    /// A feed from Metrolinx with the app's key: TripUpdates unless another feed's URL is given.
    static func metrolinx(apiKey: String, url: URL = feedURL) -> GTFSRealtimeStore {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        // A dead connection shows Offline within seconds rather than after URLSession's default minute.
        let request = URLRequest(url: components.url!, timeoutInterval: 10)
        return GTFSRealtimeStore {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
    }

    /// The key built into the app; nil when it was built without one, as every build is until the key arrives.
    static func apiKey(in bundle: Bundle = .main) -> String? {
        guard let key = (bundle.object(forInfoDictionaryKey: apiKeyInfoKey) as? String)?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty, !key.hasPrefix("$(")
        else { return nil }
        return key
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

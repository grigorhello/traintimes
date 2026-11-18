import Foundation

/// GO's platforms at one station (TT-225): its timetable and live feeds carry none (D35, D36), so the alert server
/// relays GO's per-station departures board (`/v1/live/platforms?stop=UN`, at most 30 s old). A station fetched in the
/// last 20 s is reused, so Schedule and Trip details share each fetch. Kept in memory only.
actor PlatformStore {
    static let boardURL = HTTPAlertServer.production.appending(path: "v1/live/platforms")
    static let reuseInterval: TimeInterval = 20

    /// The board's JSON for a station code.
    typealias Download = @Sendable (_ stop: String) async throws -> Data

    /// One station's posted platforms.
    struct Board: Sendable, Equatable {
        /// Platform by GO's trip number ("1713"); trains without one are left out.
        var platforms: [String: String]
    }

    private let clock: any AppClock
    private let download: Download
    private var boards: [String: (board: Board?, at: Date)] = [:]
    private var fetching: [String: Task<Board, Error>] = [:]

    init(clock: any AppClock = SystemClock(), download: @escaping Download) {
        self.clock = clock
        self.download = download
    }

    /// The alert server's relay. A dead connection gives up within seconds.
    static func relay() -> PlatformStore {
        PlatformStore { stop in
            var components = URLComponents(url: boardURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "stop", value: stop)]
            let request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
    }

    /// The station's board, fetched again unless the last try is under 20 s old; nil when the last fetch failed, so a
    /// platform from an earlier fetch is never shown as current.
    func board(at stop: String) async -> Board? {
        let now = clock.now
        if let held = boards[stop], now.timeIntervalSince(held.at) < Self.reuseInterval, fetching[stop] == nil {
            return held.board
        }
        let board = try? await fetch(stop)
        boards[stop] = (board, now)
        return board
    }

    private func fetch(_ stop: String) async throws -> Board {
        if let task = fetching[stop] { return try await task.value }
        let task = Task.detached { [download] in try Self.decode(await download(stop)) }
        fetching[stop] = task
        defer { fetching[stop] = nil }
        return try await task.value
    }

    private struct Payload: Decodable {
        struct Trip: Decodable {
            let trip: String
            let platform: String?
        }
        let trips: [Trip]
    }

    static func decode(_ data: Data) throws -> Board {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        var platforms: [String: String] = [:]
        for trip in payload.trips {
            guard let platform = trip.platform?.trimmingCharacters(in: .whitespaces), !platform.isEmpty else { continue }
            platforms[trip.trip] = platform
        }
        return Board(platforms: platforms)
    }
}

extension PlatformStore.Board {
    /// The platform for a GTFS trip id: GO's trip number is its last part ("20261118-LW-1713" is "1713").
    func platform(forTrip tripId: String) -> String? {
        tripId.split(separator: "-").last.flatMap { platforms[String($0)] }
    }
}

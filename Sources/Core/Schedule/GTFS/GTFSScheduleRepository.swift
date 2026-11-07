import Foundation

/// The schedule from GO Transit's published GTFS feed (TT-130, D35). Live status, platforms and line notices come with
/// GTFS-realtime (TT-131, TT-132), so until then every trip is Scheduled with "Platform pending".
struct GTFSScheduleRepository: ScheduleRepository, StationRepository {
    let store: GTFSFeedStore

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        try await store.timetable().trips(from: route.from.id, to: route.to.id, on: day)
    }

    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }

    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }

    func stops(for trip: TripKey, on route: Route) async throws -> [TripStop] {
        try await store.timetable().stops(of: trip.tripId, from: route.from.id, to: route.to.id, on: trip.serviceDay)
    }

    func lastServiceDay() async throws -> ServiceDay? {
        try await store.timetable().lastServiceDay
    }

    func stations() async throws -> [Station] {
        try await store.timetable().stations
    }

    func route(from: Station, to: Station) async throws -> Route {
        Route(from: from, to: to, line: try await store.timetable().line(between: from.id, and: to.id))
    }
}

/// Downloads the GO GTFS feed, imports its rail part and keeps the last good import on device, so the timetable works
/// offline (TT-130, D35). The first use waits for the download; after that the copy on device answers at once and is
/// refreshed in the background once it is a week old. A copy that no longer covers today waits for its refresh. A failed
/// refresh keeps the copy.
actor GTFSFeedStore {
    /// Metrolinx open data; public, no API key (Metrolinx Access and Use Agreement).
    static let feedURL = URL(string: "https://assets.metrolinx.com/raw/upload/Documents/Metrolinx/Open%20Data/GO-GTFS.zip")!
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    /// A refresh that failed is not tried again for this long.
    static let retryInterval: TimeInterval = 60 * 60
    /// The same when the copy has run out, so a pull to refresh soon tries again.
    static let runOutRetryInterval: TimeInterval = 60
    static let shared = GTFSFeedStore(directory: .applicationSupportDirectory.appending(path: "GTFS", directoryHint: .isDirectory))

    typealias Download = @Sendable () async throws -> Data

    private let fileURL: URL
    private let clock: any AppClock
    private let download: Download
    private var current: GTFSTimetable?
    private var hasReadCopy = false
    private var refreshing: Task<GTFSTimetable, Error>?
    private var lastAttempt: Date?

    init(directory: URL, clock: any AppClock = SystemClock(), download: @escaping Download = { try await GTFSFeedStore.downloadFeed() }) {
        fileURL = directory.appending(path: "feed.json")
        self.clock = clock
        self.download = download
    }

    /// The timetable on device, refreshed when due; the first use downloads it.
    func timetable() async throws -> GTFSTimetable {
        if !hasReadCopy {
            hasReadCopy = true
            current = try? JSONDecoder().decode(GTFSFeed.self, from: Data(contentsOf: fileURL)).timetable
        }
        guard let current else { return try await refresh() }
        let now = clock.now
        guard Self.isDue(current, now: now) else { return current }
        // A copy that no longer covers today would show no trains, so its refresh is waited for (the copy if that
        // fails, as offline); a copy that is only a week old answers at once and is refreshed in the background.
        let expired = current.lastServiceDay.map { $0 < ServiceDay(containing: now) } ?? true
        if refreshing == nil {
            let retry = expired ? Self.runOutRetryInterval : Self.retryInterval
            guard lastAttempt.map({ now.timeIntervalSince($0) >= retry }) ?? true else { return current }
            lastAttempt = now
            guard expired else {
                Task { _ = try? await self.refresh() }
                return current
            }
        }
        guard expired else { return current }
        return (try? await refresh()) ?? current
    }

    /// Downloads and imports the feed, once however many callers ask at the same time, and keeps it on device.
    @discardableResult
    func refresh() async throws -> GTFSTimetable {
        if let refreshing { return try await refreshing.value }
        let task = Task.detached { [download, clock, fileURL] in
            let zip = try await download()
            let feed = try GTFSFeed(zip: zip, importedAt: clock.now)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Written whole or not at all, so a failed refresh leaves the last good copy.
            try JSONEncoder().encode(feed).write(to: fileURL, options: .atomic)
            return feed.timetable
        }
        refreshing = task
        defer { refreshing = nil }
        let timetable = try await task.value
        current = timetable
        return timetable
    }

    /// A week old, or the feed's last service day has passed.
    static func isDue(_ timetable: GTFSTimetable, now: Date) -> Bool {
        guard let lastServiceDay = timetable.lastServiceDay, lastServiceDay >= ServiceDay(containing: now) else { return true }
        return now.timeIntervalSince(timetable.feed.importedAt) >= refreshInterval
    }

    static func downloadFeed() async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: feedURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

private extension GTFSFeed {
    var timetable: GTFSTimetable { GTFSTimetable(feed: self) }
}

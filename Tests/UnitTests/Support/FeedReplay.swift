import Foundation
import XCTest
@testable import TrainTimes

/// The GTFS-realtime feed a replay test serves next: one of the TT-131 and TT-132 samples in
/// `Tests/UnitTests/Core/Realtime` (written by `scripts/make-realtime-samples.py`), or no connection.
actor FeedReplay {
    private var next: Result<Data, any Error>
    private(set) var downloads = 0
    /// Downloads waiting for `release()`; nil while downloads answer at once.
    private var held: [CheckedContinuation<Void, Never>]?

    init(_ sample: String) throws {
        next = .success(try Self.sample(sample))
    }

    func serve(_ sample: String) throws {
        next = .success(try Self.sample(sample))
    }

    func goOffline() {
        next = .failure(URLError(.notConnectedToInternet))
    }

    /// Downloads wait until `release()`, as on a slow connection.
    func hold() {
        if held == nil { held = [] }
    }

    func release() {
        let waiting = held ?? []
        held = nil
        waiting.forEach { $0.resume() }
    }

    func download() async throws -> Data {
        if held != nil {
            await withCheckedContinuation { held?.append($0) }
        }
        downloads += 1
        return try next.get()
    }

    static func sample(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "pb")))
    }

    private final class BundleToken {}
}

extension GTFSScheduleRepository {
    /// The TT-130 feed sample with live status, and line notices (TT-132), from replays, all on the test's clock. A nil
    /// replay is a feed the app does not read, as without the Metrolinx key.
    static func replaying(
        _ replay: FeedReplay?, alerts: FeedReplay? = nil, clock: any AppClock, directory: URL
    ) throws -> GTFSScheduleRepository {
        let zip = try GTFSTimetableTests.sampleZip()
        return GTFSScheduleRepository(
            store: GTFSFeedStore(directory: directory, clock: clock, download: { zip }),
            live: replay.map { replay in GTFSRealtimeStore(clock: clock, download: { try await replay.download() }) },
            alerts: alerts.map { alerts in GTFSRealtimeStore(clock: clock, download: { try await alerts.download() }) },
            clock: clock
        )
    }
}

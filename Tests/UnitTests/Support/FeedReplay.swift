import Foundation
import XCTest
@testable import TrainTimes

/// The GTFS-realtime feed a replay test serves next: one of the TT-131 samples in `Tests/UnitTests/Core/Realtime`
/// (written by `scripts/make-realtime-samples.py`), or no connection.
actor FeedReplay {
    private var next: Result<Data, any Error>
    private(set) var downloads = 0

    init(_ sample: String) throws {
        next = .success(try Self.sample(sample))
    }

    func serve(_ sample: String) throws {
        next = .success(try Self.sample(sample))
    }

    func goOffline() {
        next = .failure(URLError(.notConnectedToInternet))
    }

    func download() throws -> Data {
        downloads += 1
        return try next.get()
    }

    static func sample(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "pb")))
    }

    private final class BundleToken {}
}

extension GTFSScheduleRepository {
    /// The TT-130 feed sample with live status from a replay, both on the test's clock.
    static func replaying(_ replay: FeedReplay, clock: any AppClock, directory: URL) throws -> GTFSScheduleRepository {
        let zip = try GTFSTimetableTests.sampleZip()
        return GTFSScheduleRepository(
            store: GTFSFeedStore(directory: directory, clock: clock, download: { zip }),
            live: GTFSRealtimeStore(clock: clock, download: { try await replay.download() })
        )
    }
}

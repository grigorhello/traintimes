import Foundation

/// The rule for interest taps (TT-209): taps on text that is not a button say the rider wanted to know more. Taps on the
/// same element, each within 2 s of the one before, count once, as one `interest_tapped` with `count` (rage taps). The
/// event goes once the run is over: another element is tapped, or 2 s pass with no tap.
struct InterestTaps {
    static let window: TimeInterval = 2

    struct Run: Equatable {
        let element: String
        let screen: String
        var count: Int
        var last: Date
    }

    private(set) var run: Run?

    /// A tap; returns the event for the run before it when this tap ends that run.
    mutating func tap(_ element: String, screen: String, at now: Date) -> AnalyticsEvent? {
        if var run, run.element == element, now.timeIntervalSince(run.last) < Self.window {
            run.count += 1
            run.last = now
            self.run = run
            return nil
        }
        let ended = finish()
        run = Run(element: element, screen: screen, count: 1, last: now)
        return ended
    }

    /// The run's event, and no run after it (2 s passed with no tap).
    mutating func finish() -> AnalyticsEvent? {
        defer { run = nil }
        return run.map { .interestTapped(element: $0.element, screen: $0.screen, count: $0.count) }
    }
}

/// The app's one run of interest taps; `.tracksInterest(_:)` feeds it and it sends through `Analytics`.
@MainActor
enum InterestTracker {
    private static var taps = InterestTaps()
    private static var finishing: Task<Void, Never>?

    static func tap(_ element: String) {
        let screen = Analytics.currentScreen?.rawValue ?? "unknown"
        if let ended = taps.tap(element, screen: screen, at: Date()) { Analytics.track(ended) }
        finishing?.cancel()
        finishing = Task {
            try? await Task.sleep(for: .seconds(InterestTaps.window))
            guard !Task.isCancelled else { return }
            if let ended = taps.finish() { Analytics.track(ended) }
        }
    }
}

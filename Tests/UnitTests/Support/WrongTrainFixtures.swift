import Foundation
@testable import TrainTimes

/// The wrong train warning's card in tests (TT-250): every show it was asked for, and whether a card of that ride shows.
@MainActor
final class FakeWrongTrainCard: WrongTrainShowing {
    struct Call {
        let wrong: RideActivityAttributes.ContentState.Wrong?
        let ride: Ride
        let until: Date?
        let alert: WrongTrainAlert?
    }

    /// A card of the ride shows (false: none, or Live Activities are off).
    var shows = true
    private(set) var calls: [Call] = []

    func show(
        _ wrong: RideActivityAttributes.ContentState.Wrong?, for ride: Ride, until: Date?, alert: WrongTrainAlert?
    ) async -> Bool {
        calls.append(Call(wrong: wrong, ride: ride, until: until, alert: alert))
        return shows
    }

    /// The beats of the updates that put the warning on, in order.
    var beats: [Int] { calls.compactMap { $0.wrong?.beat } }
    var alerts: [WrongTrainAlert] { calls.compactMap(\.alert) }
}

/// The wrong train warning's notification in tests.
@MainActor
final class FakeWrongTrainNotifier: WrongTrainNotifying {
    private(set) var posted: [WrongTrainNote] = []
    private(set) var removed = 0

    func post(_ note: WrongTrainNote) async { posted.append(note) }
    func remove() { removed += 1 }
}

/// Background time in tests: how often it was taken and given back.
@MainActor
final class FakeBackgroundTime: BackgroundTiming {
    private(set) var begun = 0
    private(set) var ended = 0

    func begin() { begun += 1 }
    func end() { ended += 1 }
}

/// Whether the app is in front, settable from a test.
@MainActor
final class ActiveSwitch {
    var isActive = false
}

/// A presenter with fakes all round: the card, the notification, the haptics, background time, "I’m fine" in an ephemeral
/// store, the 12-hour clock, and `gap` between the five (none by default).
@MainActor
final class WrongTrainRig {
    let card: FakeWrongTrainCard
    let notifier: FakeWrongTrainNotifier
    let haptics: FakeHaptics
    let background: FakeBackgroundTime
    let active: ActiveSwitch
    let defaults: UserDefaults
    let clock: TestClock
    let presenter: WrongTrain
    /// The rides the presenter ended through `endRide`.
    private(set) var ended: [Ride] = []

    init(gap: Duration = .zero, hasCard: Bool = true, setsEndRide: Bool = true) {
        let card = FakeWrongTrainCard()
        let notifier = FakeWrongTrainNotifier()
        let haptics = FakeHaptics()
        let background = FakeBackgroundTime()
        let active = ActiveSwitch()
        let defaults = UserDefaults.ephemeral()
        let clock = TestClock(now: WrongTrainFixtures.now)
        self.card = card
        self.notifier = notifier
        self.haptics = haptics
        self.background = background
        self.active = active
        self.defaults = defaults
        self.clock = clock
        presenter = WrongTrain(
            card: hasCard ? card : nil, notifier: notifier, store: WrongTrainStore(defaults: defaults), haptics: haptics,
            isActive: { active.isActive }, gap: gap, clock: clock, formatter: { TimeFormatter(format: .twelveHour) },
            background: background
        )
        if setsEndRide {
            presenter.endRide = { [weak self] ride in
                self?.ended.append(ride)
                return true
            }
        }
    }

    var store: WrongTrainStore { WrongTrainStore(defaults: defaults) }
}

enum WrongTrainFixtures {
    /// 11:20 AM on the On board tests' Friday, three minutes after their train left Union.
    static let now = OnBoardFixtures.time(11, 20)

    /// The On board tests' ride (Union to Clarkson) in a train that does not stop at Clarkson; next stop Oakville at
    /// 11:38 AM; 10 min to answer.
    static func warning(
        ride: Ride = OnBoardFixtures.ride, reason: WrongTrainReason = .skipsStop, nextStopTime: Date? = OnBoardFixtures.time(11, 38),
        expires: Date = OnBoardFixtures.time(11, 30), isDemo: Bool = false, source: WrongTrainSource = .onBoard
    ) -> WrongTrainWarning {
        WrongTrainWarning(
            ride: ride, reason: reason, evidence: .feed, source: source, stopName: "Clarkson", originId: ride.originId,
            nextStopId: "OA", nextStopName: "Oakville", nextStopTime: nextStopTime, expires: expires, secondsAfter: 42,
            isDemo: isDemo
        )
    }

    /// Lets the presenter's tasks run: the card cleared after an answer, an engine's last event.
    @MainActor
    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

import Foundation

/// Where the feedback sheet was opened (TT-228).
enum FeedbackOpenSource: String, Sendable {
    /// Schedule's Feedback button.
    case schedule
    /// Settings › Send feedback.
    case settings
}

/// Why the button played, for `feedback_nudge_shown` (TT-252).
enum FeedbackNudgeReason: String, Sendable {
    /// The first play of an app open.
    case open
    /// Again, 2 min after the last play.
    case `repeat`
    /// Settings › Testing or the launch argument.
    case testing
}

/// When Schedule's Feedback button asks (TT-228, D112, revised by TT-252, D128): the bubble draws a question mark and goes
/// back, so riders notice it. One per app, made in `RootView`. It plays on every app open (a cold start or any return to the
/// foreground) once Schedule has been still for `stillness` (`Stillness`), then again every `repeatEvery` while Schedule
/// stays still, counted from the last play. Settings › Testing › Feedback animation (`playOnNextStill()`) and the launch
/// argument `-settings.feedbackNudge now` make it play on the next still Schedule where it would not play by itself.
@Observable @MainActor
final class FeedbackNudge {
    /// How long Schedule is still before the button plays; a touch or anything over Schedule starts it again.
    static let stillness: TimeInterval = 1.5
    /// Again this long after the last play, on a still Schedule (Grigor, 2026-11-27: "every 2 minutes").
    static let repeatEvery: TimeInterval = 120
    /// A sheet opened this soon after the animation started counts as `after_nudge`.
    static let afterNudgeWindow: TimeInterval = 60
    /// The launch argument's key: `-settings.feedbackNudge now`.
    static let launchKey = "settings.feedbackNudge"

    enum Key {
        static let count = "feedback.nudge.count"
        static let forced = "feedback.nudge.forced"
    }

    /// Bumped each time the button should play; the button plays on each change.
    private(set) var playRequest = 0

    private let defaults: UserDefaults
    private let clock: any AppClock
    /// False in fixture runs, previews and the unit test host: it then plays only when forced.
    private let playsByItself: Bool
    private var playedThisOpen = false
    private var playedAt: Date?
    private var isAway = false
    /// The launch argument cannot be removed from the arguments domain, so it forces one showing per run.
    private var launchForceUsed = false

    init(defaults: UserDefaults = .standard, clock: any AppClock = SystemClock(), playsByItself: Bool) {
        self.defaults = defaults
        self.clock = clock
        self.playsByItself = playsByItself
    }

    /// The rule's clock, for Schedule's wait.
    var now: Date { clock.now }

    /// Times it has played on this install.
    var showings: Int { defaults.integer(forKey: Key.count) }

    /// Settings › Testing, or the launch argument, asked for it on the next still Schedule.
    var isForced: Bool {
        defaults.bool(forKey: Key.forced) || (defaults.string(forKey: Self.launchKey) == "now" && !launchForceUsed)
    }

    /// When the button plays if Schedule stays still from `stillSince` on; nil when it does not play at all. The first play
    /// of an app open, and a forced one, come `stillness` after Schedule became still; later ones `repeatEvery` after the
    /// last play, and never sooner than `stillness` after Schedule became still.
    func nextPlay(stillSince: Date) -> Date? {
        let settled = stillSince.addingTimeInterval(Self.stillness)
        if isForced { return settled }
        guard playsByItself else { return nil }
        guard playedThisOpen, let playedAt else { return settled }
        return max(settled, playedAt.addingTimeInterval(Self.repeatEvery))
    }

    /// Whether a Schedule still since `stillSince` should play now.
    func isDue(stillSince: Date) -> Bool {
        guard let at = nextPlay(stillSince: stillSince) else { return false }
        return at <= clock.now
    }

    /// The wait ran out on a still Schedule: the button plays.
    func play() {
        let reason: FeedbackNudgeReason = isForced ? .testing : (playedThisOpen ? .repeat : .open)
        if defaults.bool(forKey: Key.forced) { defaults.removeObject(forKey: Key.forced) }
        if defaults.string(forKey: Self.launchKey) == "now" { launchForceUsed = true }
        let count = showings + 1
        defaults.set(count, forKey: Key.count)
        playedThisOpen = true
        playedAt = clock.now
        playRequest += 1
        Analytics.track(.feedbackNudgeShown(count: count, reason: reason))
    }

    /// The feedback sheet opened, from Schedule or Settings.
    func sheetOpened(from source: FeedbackOpenSource) {
        let afterNudge = playedAt.map { clock.now.timeIntervalSince($0) <= Self.afterNudgeWindow } ?? false
        Analytics.track(.feedbackOpened(source: source, afterNudge: afterNudge, nudgesSeen: showings))
    }

    /// Settings › Testing › Feedback animation: it plays on the next still Schedule.
    func playOnNextStill() {
        defaults.set(true, forKey: Key.forced)
    }

    func wentToBackground() {
        isAway = true
    }

    /// Back from the background is a new app open: the button plays again once Schedule is still.
    func cameToForeground() {
        guard isAway else { return }
        isAway = false
        playedThisOpen = false
    }

    /// What Schedule shows, for the stillness the wait needs: trains on screen, the splash gone, and nothing over or in
    /// front of them. A touch or scroll bumps `touches`, which restarts the wait.
    struct Stillness: Equatable {
        var isActive = true
        var isLoaded = true
        var launchCovers = false
        /// A sheet is up or another tab is selected.
        var isCovered = false
        var isPicking = false
        var hasCapsule = false
        /// The ride strip or the "On the train?" question.
        var hasRideStrip = false
        var touches = 0

        var isStill: Bool {
            isActive && isLoaded && !launchCovers && !isCovered && !isPicking && !hasCapsule && !hasRideStrip
        }
    }
}

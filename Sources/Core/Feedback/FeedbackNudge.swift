import Foundation

/// Where the feedback sheet was opened (TT-228).
enum FeedbackOpenSource: String, Sendable {
    /// Schedule's Feedback button.
    case schedule
    /// Settings › Send feedback.
    case settings
}

/// When Schedule's Feedback button asks (TT-228, D107): now and then the bubble draws a question mark and goes back, so
/// riders notice it. One per app, made in `RootView`. It plays only after `stillness` of a still Schedule (`Stillness`),
/// one try per app open, at most once a Toronto calendar day, not in the install's first two days, and never again once
/// the sheet has been opened or after `maxShowings`. Settings › Testing › Feedback animation (`playOnNextStill()`) and the
/// launch argument `-settings.feedbackNudge now` let it play on the next still Schedule, without the waits.
@Observable @MainActor
final class FeedbackNudge {
    static let stillness: Duration = .seconds(4)
    static let maxShowings = 5
    /// It may play from the third calendar day on: day 1 is the first day this rule ran on the install.
    static let skippedDays = 2
    /// Back after longer away than this is a new app open (the same rule as TT-222's return to Now).
    static let newOpenAfter: TimeInterval = 10 * 60
    /// A sheet opened this soon after the animation started counts as `after_nudge`.
    static let afterNudgeWindow: TimeInterval = 60
    /// The launch argument's key: `-settings.feedbackNudge now`.
    static let launchKey = "settings.feedbackNudge"

    enum Key {
        static let firstDay = "feedback.nudge.firstDay"
        static let lastDay = "feedback.nudge.lastDay"
        static let count = "feedback.nudge.count"
        static let opened = "feedback.nudge.opened"
        static let forced = "feedback.nudge.forced"
    }

    /// Bumped each time the button should play; the button plays on each change.
    private(set) var playRequest = 0

    private let defaults: UserDefaults
    private let clock: any AppClock
    /// False in fixture runs, previews and the unit test host: it then plays only when forced.
    private let playsByItself: Bool
    private var triedThisOpen = false
    private var playedAt: Date?
    private var wentToBackgroundAt: Date?
    /// The launch argument cannot be removed from the arguments domain, so it forces one showing per run.
    private var launchForceUsed = false

    init(defaults: UserDefaults = .standard, clock: any AppClock = SystemClock(), playsByItself: Bool) {
        self.defaults = defaults
        self.clock = clock
        self.playsByItself = playsByItself
        if defaults.object(forKey: Key.firstDay) == nil { defaults.set(clock.now, forKey: Key.firstDay) }
    }

    /// Times it has played on this install, 0 to 5.
    var showings: Int { defaults.integer(forKey: Key.count) }

    /// Settings › Testing, or the launch argument, asked for it on the next still Schedule.
    var isForced: Bool {
        defaults.bool(forKey: Key.forced) || (defaults.string(forKey: Self.launchKey) == "now" && !launchForceUsed)
    }

    /// Whether a still Schedule would start the wait now.
    var isDue: Bool {
        if isForced { return true }
        guard playsByItself, !triedThisOpen, !defaults.bool(forKey: Key.opened), showings < Self.maxShowings else { return false }
        let now = clock.now
        guard defaults.string(forKey: Key.lastDay) != ServiceDay(calendarDayContaining: now).description else { return false }
        return daysSinceFirst(now) >= Self.skippedDays
    }

    /// Schedule just became still: true when the wait should start. A started wait uses this app open's one try, so a
    /// touch that cancels it waits for the next app open.
    func stillnessBegan() -> Bool {
        guard isDue else { return false }
        triedThisOpen = true
        return true
    }

    /// The wait ran out on a still Schedule: the button plays.
    func play() {
        if defaults.bool(forKey: Key.forced) { defaults.removeObject(forKey: Key.forced) }
        if defaults.string(forKey: Self.launchKey) == "now" { launchForceUsed = true }
        let now = clock.now
        let count = min(showings + 1, Self.maxShowings)
        defaults.set(count, forKey: Key.count)
        defaults.set(ServiceDay(calendarDayContaining: now).description, forKey: Key.lastDay)
        playedAt = now
        playRequest += 1
        Analytics.track(.feedbackNudgeShown(count: count))
    }

    /// The feedback sheet opened, from Schedule or Settings: it never plays by itself again.
    func sheetOpened(from source: FeedbackOpenSource) {
        let afterNudge = playedAt.map { clock.now.timeIntervalSince($0) <= Self.afterNudgeWindow } ?? false
        Analytics.track(.feedbackOpened(source: source, afterNudge: afterNudge, nudgesSeen: showings))
        defaults.set(true, forKey: Key.opened)
    }

    /// Settings › Testing › Feedback animation: clears the counters and lets it play on the next still Schedule.
    func playOnNextStill() {
        for key in [Key.lastDay, Key.count, Key.opened] { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: Key.forced)
    }

    func wentToBackground() {
        wentToBackgroundAt = clock.now
    }

    /// Back after more than 10 min away is a new app open, with a new try.
    func cameToForeground() {
        defer { wentToBackgroundAt = nil }
        guard let away = wentToBackgroundAt, clock.now.timeIntervalSince(away) > Self.newOpenAfter else { return }
        triedThisOpen = false
    }

    private func daysSinceFirst(_ now: Date) -> Int {
        guard let first = defaults.object(forKey: Key.firstDay) as? Date else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: now)).day ?? 0
    }

    /// What Schedule shows, for the stillness the wait needs: trains on screen, the splash gone, and nothing over or in
    /// front of them. A touch or scroll bumps `touches`, which restarts (so cancels) the wait.
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

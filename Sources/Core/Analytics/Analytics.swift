import Foundation

/// One product analytics event (TT-208, D92): a snake_case name and flat properties. Every event and property is listed
/// in `docs/ANALYTICS.md`, which is what anyone reading the data (Claude included) reads first. Events are anonymous: no
/// name, email, push token, installation id, location or free text ever goes in one.
struct AnalyticsEvent: Equatable, Sendable {
    let name: String
    let properties: [String: AnalyticsValue]

    init(_ name: String, _ properties: [String: AnalyticsValue] = [:]) {
        self.name = name
        self.properties = properties
    }
}

enum AnalyticsValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)

    /// The value as the SDK takes it.
    var raw: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .bool(let value): value
        }
    }
}

/// The screens `$screen` names; SwiftUI screens are named by us, never by the SDK's view-controller names.
enum AnalyticsScreen: String, Sendable {
    case schedule
    /// The first launch (TT-206, D94): the welcome and its two steps.
    case welcome
    case routeForm = "route_form"
    case alerts
    case settings
    case tripDetails = "trip_details"
    case lineNotices = "line_notices"
    case detectOffer = "detect_offer"
}

/// Where the analytics go: PostHog in TestFlight and App Store builds with a project token (`PostHogAnalytics`), nothing
/// anywhere else. View models and rules call `Analytics.track`, so tests record the events with a fake.
@MainActor
protocol AnalyticsTracking: AnyObject {
    func track(_ event: AnalyticsEvent)
    func screen(_ screen: AnalyticsScreen)
}

/// The one tracker for the app. Silent until `AppDelegate` starts PostHog; tests swap in `RecordingAnalytics`.
@MainActor
enum Analytics {
    static var tracker: (any AnalyticsTracking)?
    /// The screen on top, as last named by `screen(_:)`; interest taps say where they happened (TT-209).
    private(set) static var currentScreen: AnalyticsScreen?

    static func track(_ event: AnalyticsEvent) {
        tracker?.track(event)
    }

    static func screen(_ screen: AnalyticsScreen) {
        currentScreen = screen
        tracker?.screen(screen)
    }
}

// MARK: - The events (docs/ANALYTICS.md)

/// How Trip details was opened.
enum TripOpenSource: String, Sendable {
    /// A card on Schedule; `notification` an alert's tap; `ride` the ride strip; `departure` the countdown strip or the
    /// Live Activity before departure; `detection` the background question's notification; `link` a `traintimes://trip`
    /// link, a widget's train (TT-182).
    case schedule, notification, ride, departure, detection, link
}

/// How a ride started.
enum RideStartSource: String, Sendable {
    /// "I'm on board" in Trip details.
    case onBoard = "on_board"
    /// Yes on the train detection question on Schedule.
    case detection
    /// Start On board on the background question's notification (TT-176).
    case notification
}

/// Where an alert was removed.
enum AlertRemoveSource: String, Sendable {
    case bell
    case alertsTab = "alerts_tab"
}

extension AnalyticsEvent {
    /// A route shown on Schedule: the first one (first use) or a change from the station picker or Recent. `restored` is
    /// the route saved before this install sent any route, counted once at launch (TT-217, `RouteCount`).
    static func routeSet(_ route: Route, isFirst: Bool, restored: Bool = false) -> Self {
        var properties: [String: AnalyticsValue] = [
            "from": .string(route.from.id), "to": .string(route.to.id), "is_first": .bool(isFirst)
        ]
        if let line = route.line { properties["line"] = .string(line.id) }
        if restored { properties["restored"] = .bool(true) }
        return Self("route_set", properties)
    }

    /// What Schedule could not reach (TT-217).
    enum OfflineKind: String, Sendable {
        /// Live status: the timetable shows, marked Offline.
        case live
        /// The first timetable could not download: "Couldn’t load the timetable".
        case timetable
    }

    /// Schedule turned Offline, once per turn into that state, never on each poll (TT-217).
    static func offlineShown(_ kind: OfflineKind) -> Self {
        Self("offline_shown", ["kind": .string(kind.rawValue)])
    }

    static let routeSwapped = Self("route_swapped")

    /// The weather sheet opened from the tile on Schedule (TT-226): the day (0 is Today) and the sheet's first line.
    static func weatherOpened(dayOffset: Int, cue: WeatherCue) -> Self {
        Self("weather_opened", ["day_offset": .int(dayOffset), "cue": .string(cue.rawValue)])
    }

    /// The weather tile turned grey, at most once per Schedule visit (TT-226).
    static func weatherUnavailable(_ reason: WeatherUnavailable) -> Self {
        Self("weather_unavailable", ["reason": .string(reason.rawValue)])
    }

    /// The saved route's launch splash lifting over Schedule (TT-227): `schedule_ready` is false while Schedule still showed
    /// "Loading timetable"; `full` is the slower first-launches pace.
    static func launchSplashEnded(scheduleReady: Bool, full: Bool) -> Self {
        Self("launch_splash_ended", ["schedule_ready": .bool(scheduleReady), "full": .bool(full)])
    }

    /// What took Schedule back to today at Now.
    enum BackToNowSource: String, Sendable {
        /// The Schedule tab tapped again.
        case tab
        /// The app back in the foreground after more than 10 min away (TT-222).
        case reopen
    }

    /// Back to today at Now.
    static func backToNow(_ source: BackToNowSource) -> Self {
        Self("back_to_now", ["source": .string(source.rawValue)])
    }

    /// A day picked on the day strip, counted from today (-1 is yesterday).
    static func dayChanged(offset: Int) -> Self {
        Self("day_changed", ["offset": .int(offset)])
    }

    static func tripOpened(source: TripOpenSource, isToday: Bool) -> Self {
        Self("trip_opened", ["source": .string(source.rawValue), "is_today": .bool(isToday)])
    }

    /// An alert saved and kept: turned on or off, its days changed, or a new one.
    static func alertSaved(_ rule: AlertRule, isNew: Bool) -> Self {
        Self("alert_saved", [
            "is_on": .bool(!rule.paused), "repeats": .bool(rule.kind == .repeating),
            "days": .int(rule.weekdays.count), "is_new": .bool(isNew)
        ])
    }

    static func alertRemoved(source: AlertRemoveSource) -> Self {
        Self("alert_removed", ["source": .string(source.rawValue)])
    }

    /// The answer to the iOS notification prompt, sent only when the prompt was shown.
    static func notificationPermission(_ permission: NotificationPermission) -> Self {
        Self("notification_permission", ["result": .string(permission == .allowed ? "allowed" : "denied")])
    }

    /// A notification tapped: an alert (`alert`) or the train detection question (`detection`, with its action).
    static func notificationOpened(kind: String, action: String = "open") -> Self {
        Self("notification_opened", ["kind": .string(kind), "action": .string(action)])
    }

    /// `plan`: the ride's plan, for the express tag and how many stations it passes without stopping (TT-232).
    static func rideStarted(source: RideStartSource, demo: Bool, plan: RidePlan? = nil) -> Self {
        Self("ride_started", [
            "source": .string(source.rawValue), "demo": .bool(demo),
            "express": .bool(plan?.isExpress ?? false), "skipped_stations": .int(plan?.skipped.count ?? 0),
        ])
    }

    /// `atStop`: the train was at your stop when the ride ended (Done there, or the end 2 min after it), so Done does not
    /// read as giving up (TT-221). `watchedSeconds` and `opens`: how long, in whole seconds, and how many times the ride
    /// screen was on screen during the ride (TT-224, D106).
    static func rideEnded(_ reason: RideEndReason, atStop: Bool = false, watchedSeconds: Int = 0, opens: Int = 0) -> Self {
        let name = switch reason {
        case .byRider: "by_rider"
        case .arrived: "arrived"
        case .leftTheLine: "left_the_line"
        case .cancelled: "cancelled"
        }
        return Self("ride_ended", [
            "reason": .string(name), "at_stop": .bool(atStop), "watched_seconds": .int(watchedSeconds), "opens": .int(opens),
        ])
    }

    /// The arrival wish on screen with the app active, once per ride (TT-223, D103).
    static func arrivalWishShown(_ wish: ArrivalWish, demo: Bool) -> Self {
        Self("arrival_wish_shown", ["wish": .string(wish.id), "period": .string(wish.period.rawValue), "demo": .bool(demo)])
    }

    /// The first way the arrival wish left the screen, once per ride: `seconds` on screen (120 at most) and `taps` on it.
    static func arrivalWishClosed(
        _ wish: ArrivalWish, close: ArrivalWish.Close, seconds: Int, taps: Int, demo: Bool
    ) -> Self {
        Self("arrival_wish_closed", [
            "wish": .string(wish.id), "close": .string(close.rawValue), "seconds": .int(seconds), "taps": .int(taps),
            "demo": .bool(demo),
        ])
    }

    /// Train detection asked "On the train to Clarkson?" (TT-230): on Schedule (`app`) or as the background notification
    /// (`background`); `evidence` is `stops` (shared stops) or `moving` (moved together on a stretch with no stop between).
    static func detectionAsked(where place: String, evidence: String) -> Self {
        Self("detection_asked", ["where": .string(place), "evidence": .string(evidence)])
    }

    /// Yes or No on the train detection question on Schedule.
    static func detectionAnswered(yes: Bool) -> Self {
        Self("detection_answered", ["answer": .string(yes ? "yes" : "no")])
    }

    static let directionsOpened = Self("directions_opened")

    static func feedbackSent(_ kind: FeedbackKind, withEmail: Bool) -> Self {
        Self("feedback_sent", ["kind": .string(kind.rawValue), "with_email": .bool(withEmail)])
    }

    /// Schedule's Feedback button started asking (TT-228): `count` is which showing this is, 1 to 5.
    static func feedbackNudgeShown(count: Int) -> Self {
        Self("feedback_nudge_shown", ["count": .int(count)])
    }

    /// The feedback sheet opened (TT-228): `after_nudge` within 60 s of the button asking; `nudges_seen` 0 to 5.
    static func feedbackOpened(source: FeedbackOpenSource, afterNudge: Bool, nudgesSeen: Int) -> Self {
        Self("feedback_opened", [
            "source": .string(source.rawValue), "after_nudge": .bool(afterNudge), "nudges_seen": .int(nudgesSeen)
        ])
    }

    /// Taps on one information-only element (TT-209): `count` taps in a row, each within 2 s of the one before.
    static func interestTapped(element: String, screen: String, count: Int) -> Self {
        Self("interest_tapped", ["element": .string(element), "screen": .string(screen), "count": .int(count)])
    }

    static func settingChanged(_ setting: String, value: String) -> Self {
        Self("setting_changed", ["setting": .string(setting), "value": .string(value)])
    }
}

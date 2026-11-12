import Foundation
import Observation

/// What the Trip details sheet shows (TT-118, TT-163), every time already formatted by the one formatter (D17).
struct TripDetails: Hashable {
    /// One time on the journey card. A time that runs late is the expected one in delay-ink with `scheduled` struck under it.
    struct Time: Hashable {
        let value: String
        var scheduled: String?
        var isLate = false
    }

    struct Stop: Hashable, Identifiable {
        let id: String
        let name: String
        let time: String
        /// Origin and destination: headline name and time, ring and pin markers.
        let isEnd: Bool
        /// A cross marker and a struck time.
        let isSkipped: Bool
    }

    /// "7:32 AM train": the scheduled departure, which stays the train's name (D9). The sheet's accessibility label.
    let title: String
    /// The first and last stop, else the route's.
    let origin: String
    let destination: String
    let departure: Time
    let arrival: Time
    /// "in 20 min", or "Departing": only on the next usable train today, as on its card.
    let countdown: String?
    /// "Platform 2", or "Platform —" until GO publishes it.
    let platform: String
    /// The part of `platform` after "Platform": "2", or the "—" placeholder.
    let platformValue: String
    let hasPlatform: Bool
    /// From the stopping-pattern rule (D35); shown only when true.
    let isExpress: Bool
    /// "40 min": arrival minus departure of the two times shown.
    let tripLength: String
    /// What the card shows (D50): Scheduled until live data says more, "Departed" once the train has left.
    let status: TripStatus
    /// The status row's right side: how fresh the data is, or the service day for a timetable only.
    let freshnessText: String?
    /// Cancelled or stop skipped: struck journey times and no alert button.
    let isCancelled: Bool
    /// Cancelled itself (not only a skipped stop): every stop time is struck and the footnote says so.
    let isTrainCancelled: Bool
    /// "7 stops": every stop, both ends included.
    let stopCount: String
    /// "Expected" when every stop has a live time, otherwise "Scheduled".
    let stopsHeader: String
    let stops: [Stop]
    /// The arrival basis under the stop list.
    let footnote: String
    /// "Alert me" or "Alert on" (TT-192); nil once the train has left or when it is cancelled.
    let alertButton: String?
    /// The Directions link under the departure station (TT-188, D64).
    let showsDirections: Bool
}

/// The Trip details sheet for one trip and service date (TT-118). It loads the trip, its live status and its stops from
/// the repository, resolves the status with the timeline's rules (D12, D13) and never fills a missing value with a guess.
@Observable @MainActor
final class TripDetailsViewModel {
    let route: Route
    let key: TripKey
    /// The train has an alert that is switched on (TT-189): it counts for the departure card (TT-177). Read from the alert
    /// rules' one lookup once the trip is loaded, so a repeating alert counts on each of its days and a change shows at
    /// once; without them (previews, tests) the value passed in.
    var hasAlert: Bool {
        // The demo departure plays an alerted train (TT-177).
        if demoDeparture != nil { return true }
        guard let alerts, let trip = departure?.trip else { return fixedHasAlert }
        return alerts.isAlerted(trip, on: route)
    }
    /// On board (TT-172): "I'm on board" and ride mode. Nil where the sheet needs no ride (previews, most tests).
    let onBoard: OnBoard?
    private let fixedHasAlert: Bool
    /// The alert rules (TT-189): `hasAlert`, and the alerted train that leaves first shows the departure card from 30 min
    /// before it leaves (TT-177). Nil keeps `hasAlert` at the value passed in and shows no departure card.
    private let alerts: (any WatchedTripsProviding)?
    /// The sheet's own bell model on the app's alert rules (TT-192, D77): "Alert me" and the Live bar's bell turn the alert
    /// on and off through it, and its capsule (a refusal, a failed save, the day panel) shows inside the sheet. Nil keeps the
    /// bar at `hasAlert` and its taps do nothing (previews, most tests).
    let bells: AlertBellModel?

    /// Nil until loaded, or when the trip is not on the route that day.
    private(set) var departure: Departure?
    private(set) var stops: [TripStop] = []
    private(set) var freshness: Freshness?
    /// Today's live feed posts platforms for the route's origin (D55): a pending platform may still be posted.
    private(set) var hasPlatformSource = false
    /// The clock at the last load or tick.
    private(set) var now: Date

    private let repository: any ScheduleRepository
    private let clock: any AppClock
    private let maps: any MapsOpening
    /// The next usable train today, which alone shows the countdown (as its card does).
    private(set) var nextDepartureId: TripKey?
    /// The route's trips from the last load, resolved again at the current clock before each reload.
    @ObservationIgnored private var trips: [Trip] = []
    @ObservationIgnored private var live = LiveSnapshot.empty
    /// The route's trains resolved at the last load or tick: the departure card shows only on the alerted one that leaves
    /// first (TT-177).
    @ObservationIgnored private var departures: [Departure] = []
    /// The sheet saw this train's platform pending while it was live, then saw it posted at `platformPostedAt`: the card
    /// says "just announced" for 2 min.
    @ObservationIgnored private var sawPendingPlatform = false
    private var platformPostedAt: Date?
    /// The sheet follows a ride: it opened on this trip's running ride, or "I'm on board" started one here. Only then
    /// does a ride that ended at your stop stay on screen as Ride complete.
    private var followsRide: Bool

    init(
        route: Route, key: TripKey, repository: any ScheduleRepository, clock: any AppClock, hasAlert: Bool = false,
        onBoard: OnBoard? = nil, alerts: (any WatchedTripsProviding)? = nil, bells: AlertBellModel? = nil,
        maps: any MapsOpening = SystemMapsOpener()
    ) {
        self.route = route
        self.key = key
        self.repository = repository
        self.clock = clock
        fixedHasAlert = hasAlert
        self.onBoard = onBoard
        self.alerts = alerts
        self.bells = bells
        followsRide = onBoard?.isRunning(key) ?? false
        self.maps = maps
        now = clock.now
    }

    var isToday: Bool { key.serviceDay == ServiceDay(containing: now) }

    /// The live departure is in the past: the sheet says "Departed" and hides the alert button.
    var hasDeparted: Bool {
        guard let expected = departure?.expectedDeparture else { return false }
        return expected <= now
    }

    /// The stop list shows live times only while the trip's status rests on fresh live data and every stop the train
    /// calls at has an estimate; otherwise every stop shows its scheduled time.
    var hasLiveStops: Bool {
        guard departure?.expectedDeparture != nil, !stops.isEmpty else { return false }
        return stops.allSatisfy { $0.isSkipped || $0.expected != nil }
    }

    /// No alert for a train that has already left today, or that is cancelled.
    var showsAlertButton: Bool {
        guard let departure, departure.isUsable else { return false }
        return !(isToday && departure.departureTime <= now)
    }

    /// The departure station while directions to it help (TT-188, D64): the train has not left it yet (live time, else
    /// scheduled; a past day's train has left), it calls there (not cancelled, no skipped stop), and the feed gives the
    /// station a place. Riding (TT-172) replaces the journey card with the ride card, which takes the link with it.
    var directionsStation: Station? {
        guard let departure, departure.isUsable, departure.departureTime > now,
              let station = stops.first?.station, station.place != nil
        else { return nil }
        return station
    }

    /// The Directions link: Apple Maps with directions to the departure station.
    func openDirections() {
        guard let station = directionsStation, let place = station.place else { return }
        maps.openDirections(to: station.name, at: place)
    }

    func details(_ formatter: some TimeFormatting) -> TripDetails? {
        guard let departure else { return nil }
        let trip = departure.trip
        let isLive = hasLiveStops
        let isCancelled = !departure.isUsable
        let isTrainCancelled: Bool = if case .cancelled = departure.status { true } else { false }
        // A late departure carries both times (the spec): each shows its expected value in delay-ink, the scheduled one struck.
        let isDelayed = departure.expectedDeparture.map { $0.timeIntervalSince(trip.scheduledDeparture) >= 60 } ?? false
        let platformValue: String
        let hasPlatform: Bool
        switch trip.platform {
        case .published(let name):
            platformValue = name
            hasPlatform = true
        case .pending:
            platformValue = String(localized: "schedule.platform_placeholder")
            hasPlatform = false
        }
        // Ring = Scheduled (D50): without live data the status reads Scheduled, as on the card.
        let resolved = TripStatus(departure.status, formatter: formatter)
        let status: TripStatus = hasDeparted ? .departed : (resolved.isLive ? resolved : .scheduled)
        let arrivalTime = departure.expectedArrival ?? trip.scheduledArrival
        return TripDetails(
            title: String(format: String(localized: "trip.title"), formatter.time(trip.scheduledDeparture)),
            origin: stops.first?.station.name ?? route.from.name,
            destination: stops.last?.station.name ?? route.to.name,
            departure: Self.time(departure.expectedDeparture, scheduled: trip.scheduledDeparture, isDelayed: isDelayed, formatter),
            arrival: Self.time(departure.expectedArrival, scheduled: trip.scheduledArrival, isDelayed: isDelayed, formatter),
            countdown: departure.id == nextDepartureId ? formatter.relative(until: departure.departureTime, now: now) : nil,
            platform: String(format: String(localized: "schedule.platform"), platformValue),
            platformValue: platformValue,
            hasPlatform: hasPlatform,
            isExpress: trip.tags.contains(.express),
            tripLength: formatter.tripLength(from: departure.departureTime, to: arrivalTime),
            status: status,
            freshnessText: freshnessText(formatter),
            isCancelled: isCancelled,
            isTrainCancelled: isTrainCancelled,
            stopCount: String(format: String(localized: "trip.stops_count"), stops.count),
            stopsHeader: isLive ? String(localized: "trip.stops_expected") : String(localized: "trip.stops_scheduled"),
            stops: stops.enumerated().map { index, stop in
                TripDetails.Stop(
                    id: stop.id,
                    name: stop.station.name,
                    time: formatter.time(isLive ? (stop.expected ?? stop.scheduled) : stop.scheduled),
                    isEnd: index == 0 || index == stops.count - 1,
                    isSkipped: stop.isSkipped
                )
            },
            footnote: footnote(for: departure, isLive: isLive, formatter),
            alertButton: showsAlertButton
                ? (isAlertOn ? String(localized: "button.alert_on") : String(localized: "button.alert_me"))
                : nil,
            showsDirections: directionsStation != nil
        )
    }

    // MARK: Alert bar (TT-192)

    /// The bell's face in the bar and beside "I'm on board": the bell model's, which reads the train's one alert (D70) and
    /// knows the hold while iOS asks and the wait while saving (D72). The demo departure's train is alerted.
    var bell: BellFace {
        if demoDeparture != nil { return .on }
        guard let bells, let trip = departure?.trip else { return fixedHasAlert ? .on : .off }
        return bells.bell(for: trip, on: route)
    }

    /// "Alert on": the alert is on, or saved after the tap that turned it on.
    var isAlertOn: Bool { bell == .on || bell == .waiting }

    /// Each refusal shakes the bar's bell (D72).
    var bellShakes: Int {
        guard let bells, let trip = departure?.trip else { return 0 }
        return bells.shakes(for: trip)
    }

    /// "Alert me" turns the alert on in place, "Alert on" turns it off; the Live bar's bell does the same (TT-192). The
    /// first tap ever asks iOS (D72). The demo departure's train is made up: its bell sets nothing.
    func tapAlert() async {
        guard demoDeparture == nil, let bells, let trip = departure?.trip else { return }
        await bells.tap(trip, on: route)
    }

    /// Repeat beside "Alert on": the day panel above the bar, or closed again (D71's panel).
    func tapRepeat() {
        guard demoDeparture == nil, let bells, let trip = departure?.trip else { return }
        bells.togglePanel(for: trip, on: route)
    }

    /// The days the alert repeats on: the open panel's, else the saved alert's; empty for a one-day alert.
    var repeatDays: [Int] {
        if let days = bells?.capsule?.panelDays { return days }
        guard let bells, let trip = departure?.trip, let rule = bells.rules.alert(for: trip, on: route),
              rule.kind == .repeating, !rule.paused else { return [] }
        return rule.weekdays
    }

    /// Repeat's words: "Repeat", or the days once it repeats ("Mon to Fri"), "N days" when they do not fit.
    var repeatTitle: String {
        guard let summary = AlertDays.summary(of: repeatDays) else { return String(localized: "alert.repeat") }
        return summary.count > Self.repeatTitleLimit
            ? String(format: String(localized: "trip.repeat_days"), Set(repeatDays).count)
            : summary
    }

    /// Longer days than "Mon, Wed, Fri" read as a count (the canvas's 13 characters).
    private static let repeatTitleLimit = 13

    /// The capsule the sheet shows: a refusal, a failed save or the day panel. "Alert on" and "Alert off" are the bar's.
    var capsule: AlertBellModel.Capsule? {
        guard let capsule = bells?.capsule, capsule.showsInTripDetails else { return nil }
        return capsule
    }

    /// The expected time when the feed has one, in delay-ink with the scheduled time to strike under it while the train's
    /// departure runs a minute or more late (the strike is left out when both read the same minute); the scheduled time
    /// alone otherwise. Never a guess.
    private static func time(
        _ expected: Date?, scheduled: Date, isDelayed: Bool, _ formatter: some TimeFormatting
    ) -> TripDetails.Time {
        guard let expected else { return TripDetails.Time(value: formatter.time(scheduled)) }
        let value = formatter.time(expected)
        let struck = formatter.time(scheduled)
        return TripDetails.Time(value: value, scheduled: isDelayed && struck != value ? struck : nil, isLate: isDelayed)
    }

    private func footnote(for departure: Departure, isLive: Bool, _ formatter: some TimeFormatting) -> String {
        if case .cancelled = departure.status { return String(localized: "trip.footnote_cancelled") }
        return isLive
            ? String(format: String(localized: "trip.footnote_live"), formatter.time(departure.trip.scheduledArrival))
            : String(localized: "trip.footnote_scheduled")
    }

    /// The status row's right side (D14): "Updated just now", "Last reported 7:29 AM", "Offline · last updated 6:52 AM",
    /// or the service day for a timetable only (the ring already says Scheduled).
    private func freshnessText(_ formatter: some TimeFormatting) -> String? {
        switch freshness {
        case nil: nil
        case .live(let updatedAt): formatter.updated(at: updatedAt, now: clock.now)
        case .scheduledOnly: key.serviceDay.shortLabel
        case .stale(let lastReported): String(format: String(localized: "status.last_reported"), formatter.time(lastReported))
        case .offline(let lastUpdated):
            lastUpdated.map { String(format: String(localized: "freshness.offline"), formatter.time($0)) }
                ?? String(localized: "schedule.offline")
        }
    }

    // MARK: On board (TT-172)

    /// "I'm on board" shows from this long before the train leaves your station.
    static let boardingLead: TimeInterval = 20 * 60

    /// The button's window: from 20 min before the train leaves your station until it reaches your stop.
    static func isInBoardingWindow(departure: Date, arrival: Date, now: Date) -> Bool {
        now >= departure.addingTimeInterval(-boardingLead) && now < arrival
    }

    /// The sheet shows the ride: this trip's ride runs, or the ride it followed ended at your stop (Ride complete until
    /// the sheet closes). Opened again later, the sheet shows the trip.
    var isRiding: Bool {
        guard let onBoard else { return false }
        return onBoard.isRunning(key) || (followsRide && onBoard.endedAtYourStop(key))
    }

    /// "I'm on board": a ride can start, and this train runs today, is not cancelled and is in its window. In the demo
    /// departure, while its window lasts (it hands over into the demo ride).
    var showsOnBoardButton: Bool {
        guard let onBoard, !isRiding else { return false }
        if demoDeparture != nil { return liveDeparture != nil }
        guard onBoard.canStart, isToday, let departure, departure.isUsable else { return false }
        return Self.isInBoardingWindow(
            departure: departure.departureTime, arrival: departure.expectedArrival ?? departure.trip.scheduledArrival, now: now
        )
    }

    /// The first "I'm on board" shows the app's sheet, then the iOS prompt. The demo asks for nothing.
    var needsLocationIntro: Bool { demoDeparture == nil && (onBoard?.asksForLocation ?? false) }

    /// The footnote under the stops while the button shows.
    var onBoardHint: String {
        String(format: String(localized: "onboard.hint"), RideDetails.shortName(route.to.name))
    }

    /// Your stop's short name, for the permission sheet.
    var destinationName: String { RideDetails.shortName(route.to.name) }

    func rideDetails(_ formatter: some TimeFormatting) -> RideDetails? {
        guard isRiding else { return nil }
        return onBoard?.details(for: key, formatter: formatter)
    }

    /// "I'm on board" (or Continue on the permission sheet): the ride starts, and location is asked here.
    @discardableResult
    func startRide() async -> Bool {
        guard let onBoard else { return false }
        // Set before the ride starts: the sheet shows the ride as soon as it runs, which can be before the start returns.
        ridesInPlace = liveDeparture != nil
        let started: Bool
        if demoDeparture != nil {
            started = await onBoard.handOffDemo()
        } else {
            started = await onBoard.start(Ride(trip: key, from: route.from.id, to: route.to.id), on: route)
        }
        if started { followsRide = true } else { ridesInPlace = false }
        return started
    }

    /// "I'm on board" was tapped on the departure card (TT-177, D69): the ride takes the card's place in the same update,
    /// drawn at rest. Its rows rise only when the sheet opens on a ride or starts one from the journey card.
    private(set) var ridesInPlace = false

    // MARK: Before departure (TT-177)

    /// Demo trains › Departure plays this trip: the sheet reads the demo's train, stops and clock.
    var demoDeparture: DemoDeparture.Session? {
        guard let session = onBoard?.departureDemo, session.key == key else { return nil }
        return session
    }

    /// This train's window before departure: it is the alerted train in its window that leaves first (the demo's train
    /// while it plays). Nil otherwise, and while riding.
    var liveDeparture: LiveDeparture? {
        if demoDeparture != nil { return departure.flatMap { LiveDeparture($0, now: now) } }
        guard let alerts else { return nil }
        let route = route
        let live = LiveDeparture.earliest(in: departures, now: now) { alerts.isAlerted($0.trip, on: route) }
        return live?.key == key ? live : nil
    }

    /// The departure card in place of the journey card, while this train is live before departure and no ride shows.
    func departureDetails(_ formatter: some TimeFormatting) -> DepartureDetails? {
        guard !isRiding, let live = liveDeparture else { return nil }
        let justAnnounced = platformPostedAt.map { now.timeIntervalSince($0) < DepartureDetails.announcedFor } ?? false
        return DepartureDetails(
            live,
            origin: stops.first?.station.name ?? route.from.name,
            destination: stops.last?.station.name ?? route.to.name,
            now: now,
            freshness: freshness,
            hasPlatformSource: hasPlatformSource,
            justAnnounced: live.platform != nil && justAnnounced,
            formatter: formatter
        )
    }

    /// The sheet follows the clock each second: riding, or live before departure.
    var followsClock: Bool { isRiding || liveDeparture != nil || demoDeparture != nil }

    /// Each second while `followsClock`: the countdown, Boarding now and Departed follow the clock between loads.
    func tick() {
        resolve()
    }

    /// Notes when the live train's platform is posted after the sheet saw it pending.
    private func notePlatform() {
        guard let live = liveDeparture else { return }
        if live.platform == nil {
            sawPendingPlatform = true
            platformPostedAt = nil
        } else if sawPendingPlatform, platformPostedAt == nil {
            platformPostedAt = now
        }
    }

    /// End ride, or Done at your stop.
    func endRide() {
        onBoard?.end()
    }

    /// Loads, then reloads on the timetable's foreground refresh interval while the sheet is open, so the sheet moves
    /// with the schedule and never holds it up.
    func run() async {
        while !Task.isCancelled {
            // Live data left on screen ages first, so it never shows as live while the next fetch runs (D13).
            if freshness != nil { resolve() }
            await load()
            try? await Task.sleep(for: .seconds(TTTimeline.foregroundRefreshSeconds))
        }
    }

    func load() async {
        // The demo departure's train is not in the timetable: the demo gives it all.
        guard demoDeparture == nil else {
            resolve()
            return
        }
        let day = key.serviceDay
        let isToday = day == ServiceDay(containing: clock.now)
        let trips = (try? await repository.trips(for: route, on: day)) ?? []
        let live = isToday ? (try? await repository.liveStatus(for: route, on: day)) ?? .empty : .empty
        stops = (try? await repository.stops(for: key, on: route)) ?? []
        self.trips = trips
        self.live = live
        resolve()
    }

    /// The trip's status from the last load at the current clock, and which train is next (the rule of the timeline's cards).
    private func resolve() {
        if let demo = demoDeparture {
            let current = demo.now
            let live = demo.live(at: current)
            now = current
            departure = demo.departure(at: current)
            departures = departure.map { [$0] } ?? []
            stops = demo.stops(at: current)
            freshness = Freshness(live, now: current)
            hasPlatformSource = live.hasPlatformSource
            nextDepartureId = key
            notePlatform()
            return
        }
        let current = clock.now
        let isToday = key.serviceDay == ServiceDay(containing: current)
        let freshness = isToday ? Freshness(live, now: current) : .scheduledOnly
        now = current
        let departures = Departure.resolve(trips, live: isToday ? live : .empty, freshness: freshness, isToday: isToday)
        departure = departures.first { $0.id == key }
        nextDepartureId = isToday ? departures.first { $0.isUsable && $0.departureTime >= current }?.id : nil
        self.freshness = freshness
        self.departures = departures
        hasPlatformSource = isToday && live.hasPlatformSource
        notePlatform()
    }
}

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

/// Trip details' alert card (TT-254, D129; the Alerts canvas's boards 45 to 50): "Alert" and its switch, the seven day
/// marks and Remove alert, or for an alert whose usual train left the timetable "Time changed", its sentence and Pick a new
/// train. Every word already formatted.
struct TripAlertCard: Hashable {
    /// A day mark: lit (the alert repeats that day), the ring (a one-day alert's own day) or off.
    enum Mark: Hashable {
        case lit
        case ring
        case off
    }

    struct Day: Hashable, Identifiable {
        /// The ISO weekday, 1 is Monday.
        let id: Int
        /// "M".
        let letter: String
        /// "Monday".
        let name: String
        let mark: Mark
    }

    let ruleID: AlertRule.ID
    /// The switch: the value on its way to the server, else the saved one. Off greys the marks, which then take no tap.
    let isOn: Bool
    /// "Once, today", "Once, tomorrow" or "Once, Fri 6" under "Alert": a one-day alert only (the marks say the rest).
    let words: String?
    /// Monday first.
    let days: [Day]
    /// "7:32 AM is no longer in the timetable.": the usual train changed (`reviewNeeded`), so the card is all the sheet shows.
    let changedLine: String?

    var isChanged: Bool { changedLine != nil }
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
    /// Remove alert (TT-254, D129): RootView removes it where the sheet was opened (the Alerts tab, or Schedule with
    /// "Alert removed · Undo") and closes the sheet. Nil in previews and most tests.
    @ObservationIgnored var onRemoveAlert: (@MainActor (AlertRule) -> Void)?
    /// Pick a new train on a Time changed card: RootView closes the sheet and starts Schedule's pick (TT-193).
    @ObservationIgnored var onPickNewTrain: (@MainActor (AlertRule) -> Void)?
    /// The alert the card shows, held once found (or passed by the Alerts tab, whose changed card has no train to look
    /// up): a day cleared that leaves this train's weekday out keeps the card in its place.
    private var heldAlertID: AlertRule.ID?

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
    /// The sheet follows a ride: it opened on this trip's running ride, or "I'm on board" started one here. Only then
    /// does a ride that ended at your stop stay on screen as Ride complete.
    private var followsRide: Bool
    /// "I'm on board"'s Rail joint, End ride's Tap, and this train turning late (Warning) or boarding (Rail joint) while
    /// the sheet is open (TT-215, D100): an open sheet watches its train.
    private let haptics: any HapticPlaying
    @ObservationIgnored private var watchedFeels = WatchedTrainFeels()
    /// Counts `boarding_shown` once per train per day, with Schedule (TT-233, D114). Previews and most tests count nothing.
    private let boardingShown: BoardingShown

    init(
        route: Route, key: TripKey, repository: any ScheduleRepository, clock: any AppClock, hasAlert: Bool = false,
        onBoard: OnBoard? = nil, alerts: (any WatchedTripsProviding)? = nil, bells: AlertBellModel? = nil,
        boardingShown: BoardingShown = BoardingShown(defaults: nil),
        maps: any MapsOpening = SystemMapsOpener(), haptics: any HapticPlaying = TTHaptics.shared,
        ridesInPlace: Bool = false, alertID: AlertRule.ID? = nil
    ) {
        self.haptics = haptics
        self.route = route
        self.key = key
        self.repository = repository
        self.clock = clock
        fixedHasAlert = hasAlert
        self.onBoard = onBoard
        self.alerts = alerts
        self.bells = bells
        self.boardingShown = boardingShown
        followsRide = onBoard?.isRunning(key) ?? false
        self.ridesInPlace = ridesInPlace
        self.maps = maps
        heldAlertID = alertID
        now = clock.now
    }

    var isToday: Bool { key.serviceDay == ServiceDay(containing: now) }

    /// The train has left its station as far as live data says: the sheet says "Departed". It moved off or the feed dropped
    /// the station (TT-233, D114, `BoardingRule`), or its live departure time has passed with no position to go by; a train
    /// standing at its platform past its time has not left. Without live data the clock alone never claims it.
    var hasDeparted: Bool {
        guard let departure, let source = BoardingRule.phase(of: departure, now: now).source else { return false }
        return source != .clock || departure.expectedDeparture != nil
    }

    /// The stop list shows live times only while the trip's status rests on fresh live data and every stop the train
    /// calls at has an estimate; otherwise every stop shows its scheduled time.
    var hasLiveStops: Bool {
        guard departure?.expectedDeparture != nil, !stops.isEmpty else { return false }
        return stops.allSatisfy { $0.isSkipped || $0.expected != nil }
    }

    /// No alert for a train that has already left today (`BoardingRule`, TT-233: one still standing at its platform past its
    /// time has not), or that is cancelled.
    var showsAlertButton: Bool {
        guard let departure, departure.isUsable else { return false }
        return !(isToday && departure.hasLeft(at: now))
    }

    /// The departure station while directions to it help (TT-188, D64): the train has not left it yet (`BoardingRule`,
    /// TT-233: where it stands when the train feed places it, else its live time, else the scheduled one; a past day's train
    /// has left), it calls there (not cancelled, no skipped stop), and the feed gives the station a place. Riding (TT-172)
    /// replaces the journey card with the ride card, which takes the link with it.
    var directionsStation: Station? {
        guard let departure, departure.isUsable, !departure.hasLeft(at: now),
              let station = stops.first?.station, station.place != nil
        else { return nil }
        return station
    }

    /// The Directions link: Apple Maps with directions to the departure station.
    func openDirections() {
        guard let station = directionsStation, let place = station.place else { return }
        Analytics.track(.directionsOpened)
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
        if heldAlertID == nil { heldAlertID = bells.rules.alert(for: trip, on: route)?.id }
    }

    /// The bar shows "Alert me" (TT-192) only while the train has no alert, and stays through the hold and the wait of the
    /// tap that turns one on; then the alert card takes over and the bar goes (TT-254, D129). Not once the train has left
    /// or when it is cancelled (`showsAlertButton`).
    var showsAlertBar: Bool {
        guard showsAlertButton else { return false }
        if bells != nil, alertRule != nil, !savesFirstAlert { return false }
        return true
    }

    /// The first save of an alert from "Alert me" is on its way (iOS asking, or the bell waiting): the bar holds, and the
    /// card comes once the alert is on, so a save the server cannot take never shows a card that goes again.
    private var savesFirstAlert: Bool {
        guard heldAlertID == nil, let bells, let trip = departure?.trip else { return false }
        let face = bells.bell(for: trip, on: route)
        return face == .waiting || face == .asking
    }

    // MARK: Alert card (TT-254, D129)

    /// The alert the card shows: the one held, else the alert that covers this train on its day (D70), switched on or off.
    /// Nil without the alert rules (previews, most tests) and for the demo departure's made-up train.
    var alertRule: AlertRule? {
        guard demoDeparture == nil, let rules = bells?.rules else { return nil }
        if let heldAlertID, let held = rules.rules.first(where: { $0.id == heldAlertID }) { return held }
        guard let trip = departure?.trip else { return nil }
        return rules.alert(for: trip, on: route)
    }

    /// The usual train of the alert changed (the server's Time changed): the card alone, with Pick a new train.
    var alertChanged: Bool {
        guard let rule = alertRule, let rules = bells?.rules else { return false }
        return rules.state(of: rule) == .reviewNeeded
    }

    /// The card on top of the sheet, from every door: switched on or off, one day (its own weekday a ring) or repeating,
    /// or Time changed. Nil with no alert on the train.
    func alertCard(_ formatter: some TimeFormatting) -> TripAlertCard? {
        guard let rule = alertRule, let bells, !savesFirstAlert else { return nil }
        if alertChanged {
            return TripAlertCard(
                ruleID: rule.id, isOn: !rule.paused, words: nil, days: [],
                changedLine: String(format: String(localized: "trip.alert.changed"), formatter.time(rule.scheduledDeparture))
            )
        }
        let isOn = bells.isSwitchedOn(rule)
        let pending = bells.pendingDays(for: rule.id)
        let lit = pending ?? (rule.kind == .repeating ? rule.weekdays : [])
        let ownDay = (rule.trip ?? key).serviceDay
        let isOneDay = lit.isEmpty
        return TripAlertCard(
            ruleID: rule.id,
            isOn: isOn,
            words: isOneDay ? Self.onceWords(ownDay, today: ServiceDay(containing: now)) : nil,
            days: AlertDays.week.map { day in
                let mark: TripAlertCard.Mark = lit.contains(day) ? .lit : (isOneDay && day == ownDay.isoWeekday ? .ring : .off)
                return TripAlertCard.Day(id: day, letter: AlertDays.letter(day), name: AlertDays.fullName(day), mark: mark)
            },
            changedLine: nil
        )
    }

    /// "Once, today", "Once, tomorrow", else the date: "Once, Fri 6".
    static func onceWords(_ day: ServiceDay, today: ServiceDay) -> String {
        if day == today { return String(localized: "trip.alert.once_today") }
        if day == today.adding(days: 1) { return String(localized: "trip.alert.once_tomorrow") }
        return String(format: String(localized: "trip.alert.once_date"), day.weekdayShort, day.day)
    }

    /// The card's switch (Click, `alert_saved`): the same alert switched on or off, a one-day one too. With notifications
    /// off it nudges instead, as the crossed bell does (D72).
    func setAlertOn(_ isOn: Bool) async {
        guard let bells, let rule = alertRule, let trip = alertTrip else { return }
        heldAlertID = rule.id
        await bells.setSwitch(isOn, for: rule.id, trip: trip, route: route)
    }

    /// A day mark (Tick, `alert_saved`): lit or cleared at once and saved, the last lit day staying lit; on a one-day alert
    /// any day makes it repeat and keeps its own day (`AlertDays.toggled`). The marks take no tap while switched off.
    func tapAlertDay(_ day: Int) {
        guard let bells, let rule = alertRule, !alertChanged, bells.isSwitchedOn(rule), let trip = alertTrip else { return }
        heldAlertID = rule.id
        bells.tapDay(day, for: rule.id, trip: trip, route: route)
    }

    /// Remove alert: the sheet closes and the alert goes where it was opened from, with Undo there (`onRemoveAlert`).
    func removeAlert() {
        guard let rule = alertRule else { return }
        onRemoveAlert?(rule)
    }

    /// Pick a new train on a Time changed card: the sheet closes and Schedule asks for the new train's bell (TT-193).
    func pickNewTrain() {
        guard let rule = alertRule, alertChanged else { return }
        onPickNewTrain?(rule)
    }

    /// The train the card's changes are saved for: the sheet's train, else (no train in the timetable that day) the
    /// alert's own as it was saved.
    private var alertTrip: Trip? {
        if let trip = departure?.trip { return trip }
        guard let rule = alertRule, rule.trip != nil else { return nil }
        return AlertsViewModel.departure(of: rule).trip
    }

    /// The hero counts the minutes whenever the train's Alerts card does (TT-254): an alert on it and 60 min or less to go
    /// today (`AlertsViewModel.countdownLead`).
    private var alertCounts: Bool {
        guard isToday, alertRule != nil, !alertChanged, let departure else { return false }
        return departure.departureTime.timeIntervalSince(now) <= AlertsViewModel.countdownLead
    }

    /// The capsule the sheet shows: a refusal or a failed save (TT-254: the alert card says the rest).
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

    /// The sheet followed this trip's ride, which Not on it on the card or the undo by itself ended (TT-243, D120): `RootView`
    /// closes it.
    var rideWasUndone: Bool {
        followsRide && onBoard?.endedUndone(key) == true
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

    func rideDetails(_ formatter: some TimeFormatting) -> RideDetails? {
        guard isRiding else { return nil }
        return onBoard?.details(for: key, formatter: formatter)
    }

    /// "I'm on board" (or Continue on the permission sheet): the ride starts, and location is asked here. `source`:
    /// `departure` for Yes on the departure question (TT-231), which opens this sheet and starts the ride.
    @discardableResult
    func startRide(source: RideStartSource = .onBoard) async -> Bool {
        guard let onBoard else { return false }
        // Rail joint at the tap; when iOS will ask for location first, once the ride has started.
        let asks = needsLocationIntro
        if !asks { haptics.play(.onBoard) }
        // Set before the ride starts: the sheet shows the ride as soon as it runs, which can be before the start returns.
        ridesInPlace = liveDeparture != nil
        isStartingRide = true
        defer { isStartingRide = false }
        let started: Bool
        if demoDeparture != nil {
            started = await onBoard.handOffDemo(source: source)
        } else {
            started = await onBoard.start(Ride(trip: key, from: route.from.id, to: route.to.id), on: route, source: source)
        }
        if started { followsRide = true } else { ridesInPlace = false }
        if started, asks { haptics.play(.onBoard) }
        return started
    }

    /// "I'm on board" was tapped on the departure card (TT-177, D69), the ride started by itself (TT-242, D120: the sheet
    /// opened on it, or adopted it): the ride takes the card's place in the same update, drawn at rest. Its rows rise only
    /// when the sheet opens on a ride or starts one from the journey card.
    private(set) var ridesInPlace = false
    @ObservationIgnored private var isStartingRide = false

    /// This train's ride started by itself while the sheet is open (TT-242, D120; the view calls it when `isRiding` turns
    /// true): the sheet follows it as if "I’m on board" had been tapped here, drawn at rest, with no haptic. A ride this
    /// sheet starts itself is left to `startRide(source:)`.
    func adoptRide() {
        guard isRiding, !isStartingRide, !followsRide else { return }
        followsRide = true
        ridesInPlace = true
    }

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

    /// The hero card over the folded trip (TT-205, D93) for every train that has not left and runs, while no ride shows
    /// (TT-207, D96). It counts down on the next train, the alerted one in its window (TT-177) and while "I’m on board"
    /// shows; any other train says "Departs at" and its expected time. Any of them reads "boarding now" and lights up
    /// while the train stands at its platform, also past its time (TT-233, D114). Nil once the train has left
    /// (`BoardingRule`), or when it is cancelled or skips a stop: the sheet shows the trip as before.
    func departureHero(_ formatter: some TimeFormatting) -> DepartureHero? {
        guard !isRiding, let departure else { return nil }
        return DepartureHero(
            departure, now: now, showsCountdown: showsCountdown,
            pillPulses: hasPlatformSource && (freshness?.isLive ?? false),
            atLine: Self.atLine(key.serviceDay, today: ServiceDay(containing: now)), formatter: formatter
        )
    }

    /// The hero's line over a clock time on another day (TT-254): "Departs tomorrow at", "Departs Monday at", or beyond a
    /// week "Departs Fri 13 at"; nil today ("Departs at").
    static func atLine(_ day: ServiceDay, today: ServiceDay) -> String? {
        guard day > today else { return nil }
        if day == today.adding(days: 1) { return String(localized: "depart.atLine.tomorrow") }
        let name = today.days(to: day) > AlertsViewModel.weekdayReach
            ? String(format: String(localized: "alerts.when.date"), day.weekdayShort, day.day)
            : day.weekdayName
        return String(format: String(localized: "depart.atLine.day"), name)
    }

    /// The hero counts down: the next usable train today, the alerted train in its window, or "I’m on board" shows.
    var showsCountdown: Bool {
        departure?.id == nextDepartureId || liveDeparture != nil || showsOnBoardButton || alertCounts
    }

    /// The sheet follows the clock each second: riding, or before departure (the hero's countdown, also while the next
    /// train stands at its platform past its time, TT-233).
    var followsClock: Bool {
        isRiding || liveDeparture != nil || demoDeparture != nil || showsOnBoardButton
            || (departure.map { ($0.id == nextDepartureId || alertCounts) && !$0.hasLeft(at: now) } ?? false)
    }

    /// Each second while `followsClock`: the countdown, Boarding now and Departed follow the clock between loads (a
    /// position that grows older than 2 min says nothing more, `BoardingRule`).
    func tick() {
        resolve()
    }

    /// End ride, or Done at your stop.
    func endRide() {
        if onBoard?.isRunning(key) == true { haptics.play(.undo) }
        onBoard?.end()
    }

    /// Not on it (TT-243, D120): Tap at once, then the ride that started by itself ends and its train is left alone today.
    func notOnIt() {
        guard onBoard?.isRunning(key) == true else { return }
        haptics.play(.undo)
        onBoard?.notOnIt()
    }

    /// "I’m fine" on the wrong train warning (TT-250, D127): Tap, the warning goes and the ride carries on.
    func wrongTrainFine() {
        guard onBoard?.wrongTrainWarning != nil else { return }
        haptics.play(.undo)
        onBoard?.wrongTrain?.fine(surface: .ride)
    }

    /// "Trains from …" on the wrong train warning: Tap, the ride ends, the sheet closes and Schedule shows the way back.
    func wrongTrainTrains() {
        guard onBoard?.wrongTrainWarning != nil else { return }
        haptics.play(.undo)
        onBoard?.wrongTrain?.trains(surface: .ride)
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
            playWatchedFeels()
            return
        }
        let current = clock.now
        let isToday = key.serviceDay == ServiceDay(containing: current)
        let freshness = isToday ? Freshness(live, now: current) : .scheduledOnly
        now = current
        let departures = Departure.resolve(trips, live: isToday ? live : .empty, freshness: freshness, isToday: isToday)
        departure = departures.first { $0.id == key }
        // The next train is the first that has not left (`BoardingRule`, TT-233): one standing at its platform past its
        // time is still the next one.
        nextDepartureId = isToday ? departures.first { $0.isUsable && !$0.hasLeft(at: current) }?.id : nil
        self.freshness = freshness
        self.departures = departures
        hasPlatformSource = isToday && live.hasPlatformSource
        holdAlert()
        playWatchedFeels()
        countBoardingShown()
    }

    /// Holds the alert the card shows once the trip is in, so editing its days never takes the card away. Not during the
    /// first save from "Alert me" (`tapAlert()` holds it once that lands).
    private func holdAlert() {
        guard heldAlertID == nil, !savesFirstAlert, let bells, let trip = departure?.trip,
              let rule = bells.rules.alert(for: trip, on: route) else { return }
        heldAlertID = rule.id
    }

    /// This train turning late or cancelled plays Warning, reaching Boarding now Rail joint, once each, not while riding.
    private func playWatchedFeels() {
        guard !isRiding, let departure else { return }
        if let moment = watchedFeels.moment(for: [departure], now: now, isWatched: { _ in true }) { haptics.play(moment) }
    }

    /// The hero shows this train Boarding at its platform (the rule's, never the clock's last 2 min): `boarding_shown`,
    /// which `BoardingShown` sends once per train per day (TT-233, D114). Not while the ride shows in the hero's place;
    /// the demo departure's train is made up and has no position.
    private func countBoardingShown() {
        guard !isRiding, let departure, departure.isBoarding(at: now) else { return }
        boardingShown.shown(departure, surface: .trip, now: now)
    }
}

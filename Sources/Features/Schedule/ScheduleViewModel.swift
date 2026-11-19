import CoreGraphics
import Foundation
import Observation

/// The Schedule screen (TT-112): line and route header, day strip, the status row when offline or stale, and the line notice
/// chip (TT-132), plus the departures, cards and layout the timeline draws (TT-113). There is no Now button: tapping the
/// Schedule tab again scrolls back to Now (D49).
@Observable @MainActor
final class ScheduleViewModel {
    /// Today plus 13 days when the schedule has no known end (the fixtures).
    static let dayCount = 14
    /// Today plus 41 days at most; the strip covers every day to the schedule's last service day (Q6, D35, D49).
    static let maxDayCount = 42
    /// Days before Today the strip also shows, to its left (TT-160, D53).
    static let pastDayCount = 7
    /// Live status is fetched again this often while Schedule is in the foreground (TT-131).
    static let livePollInterval: Duration = .seconds(30)
    /// Away from the app longer than this, Schedule comes back at Now on Today, as the Schedule tab does (TT-222).
    static let returnToNowAfter: TimeInterval = 10 * 60
    /// The watched-trip strip stays this long after the train's arrival (TT-144).
    static let watchedStripAfterArrival: TimeInterval = 10 * 60

    private(set) var route: Route?
    private(set) var selectedDay: ServiceDay
    private(set) var departures: [Departure] = []
    private(set) var layout = TimelineLayout()
    /// The clock at the last load or minute tick. The Now line, the next train and "in N min" read it.
    private(set) var now: Date
    /// Nil until the first load.
    private(set) var freshness: Freshness?
    /// Today's live feed publishes platforms for the route's origin (TT-162): a pending platform may then arrive.
    private(set) var hasPlatformSource = false
    /// On a day with no direct trains: the next day in the strip that has some, for "Show Monday". Nil when none does.
    private(set) var nextDayWithTrains: ServiceDay?
    /// The last day the schedule covers (the GTFS feed's validity window); nil when it has no end.
    private(set) var lastServiceDay: ServiceDay?
    /// Today's line-wide notices for the route's line that the rider has not dismissed (TT-132). They show as the
    /// Notice chip and never change a trip's status. Another day has none.
    private(set) var lineNotices: [LineNotice] = []
    /// The same notices from the last load of today, kept while another day is shown: the Alerts tab's Line notices and
    /// the notice sheet it opens (TT-143). Equal to `lineNotices` while today is shown.
    private(set) var todayNotices: [LineNotice] = []
    /// The line `todayNotices` were read for, so another route's line drops them.
    @ObservationIgnored private var todayNoticesLine: Line.ID?
    /// Watched-trip strips the rider swiped away while the app runs (TT-144).
    private(set) var dismissedWatchedTrips: Set<TripKey> = []
    /// Bumped when the timeline should scroll: to Now on today, to the first train on another day.
    /// A refresh never bumps it, so pull to refresh keeps the scroll position.
    private(set) var scrollRequest = 0
    /// Bumped once, after a scroll request, when every card has been measured and the layout has settled: the view
    /// scrolls again (without animation on the launch's request, animated after it), because the first scroll ran on
    /// estimated card sizes (D49).
    private(set) var settleRequest = 0
    /// Bumped twice, a moment after a scroll request: the view scrolls again (as `settleRequest` does), in case the first
    /// scroll ran before the content was laid out, as when the timeline had just replaced the loading skeleton (TT-159, D52).
    private(set) var rescrollRequest = 0
    /// A scroll request is waiting for the cards to be measured.
    @ObservationIgnored private var awaitsMeasurement = false
    /// Bumped when a new set of trains is shown: a day picked, the route swapped or picked, the first load, back to Today
    /// from another day. The cards cascade in (TT-164, D61). A minute tick, a status change, a refresh or poll and the
    /// midnight turn never bump it.
    private(set) var entranceRequest = 0
    /// New trains are loading for another day or route: the old cards are hidden at once and the new ones wait at the
    /// cascade's first pose (TT-164, D61). Only the latest such load ends the wait, so a load it overtook (today's, still
    /// waiting for live status) can neither end it early nor keep the latest trains hidden.
    private(set) var awaitsNewTrains = false
    /// Counts the loads of new trains, so each knows whether it is still the latest.
    @ObservationIgnored private var newTrainsTicket = 0
    /// New trains have kept the timeline empty for `slowNewTrains`, so it shows the loading timeline until they land: today's
    /// trains wait for live status, which can take the network's time (up to 10 s on a dead connection, D36).
    private(set) var newTrainsAreSlow = false
    static let slowNewTrains: Duration = .milliseconds(400)
    /// The last scroll request jumps instead of gliding: new trains replaced the cards, so the timeline moves at once and
    /// they cascade in where they land (TT-164, D61).
    private(set) var scrollJumps = false
    /// Bumped when the rider picks a day or the Schedule tab takes them back to Today: the accent tile glides there. The
    /// midnight turn and a Mock time jump move the selection without it, so nothing slides at midnight (TT-164, D61).
    private(set) var daySelection = 0
    /// Bumped when the Schedule tab or the Today tile is tapped, once when the launch's scroll has settled, and when the
    /// timeline shows again (`timelineAppeared()`): the Now line plays (TT-164, TT-197).
    private(set) var nowPulse = 0
    /// The launch's scroll request pulses Now once it settles.
    @ObservationIgnored private var pulsesOnSettle = false
    /// Bumped when a minute tick or a live update makes trains on Today leave (TT-203, D86): `departing` step up above the
    /// Now line, the Now line glides `departureGlide` onto them and `departureNext` takes the lead. Never bumped by a load
    /// of new trains (launch, day change, route), the first tick after the screen shows or the first poll after the app
    /// comes back, nor for a train the clock says left over a minute ago or one that was cancelled: those are drawn at
    /// rest. A train GO's feeds say has left (it moved off, or its station dropped out of the trip, TT-233, D114) plays
    /// when that arrives, however long past its time.
    private(set) var departureRequest = 0
    private(set) var departing: Set<TripKey> = []
    /// The departing train that was the next one: its time shrinks from 34 to 32 pt.
    private(set) var departureLead: TripKey?
    private(set) var departureNext: TripKey?
    private(set) var departureGlide: CGFloat = 0
    /// What the last layout showed, so the next update can tell which trains have just left.
    @ObservationIgnored private var seenDepartures: (
        day: ServiceDay, route: Route?, present: Set<TripKey>, departed: Set<TripKey>, next: TripKey?
    )?
    /// The trains `train_departed` has gone out for (TT-233, D114), so a train whose position comes back after the clock
    /// took it, and which then leaves again, is counted once.
    @ObservationIgnored private var countedDepartures: Set<TripKey> = []

    /// The weather tile beside the day strip and its sheet (TT-226), for the route's From station.
    let weather: WeatherTileModel
    private let repository: any ScheduleRepository
    private let clock: any AppClock
    /// Keeps the route on device (TT-120); nil in previews and tests that do not check it.
    private let routeStore: (any RouteStoring)?
    /// Counts each route shown for analytics and marks the install as counted (TT-217).
    private let routeCount: RouteCount
    /// Sends `boarding_shown` once per train per day (TT-233, D114).
    private let boardingShown: BoardingShown
    /// Each route shown is recorded first (D48); the station picker lists the others under Recent (D54).
    let recents: RecentRoutes
    private let dismissedNotices: DismissedNotices
    /// The trips with an alert, for the watched-trip strip (TT-144).
    private let watchedTrips: any WatchedTripsProviding
    private var hasLoaded = false
    /// The last load found no timetable on device and could not download one (TT-206): the failed card, not an endless
    /// "Loading timetable". Live polls and Try again load again.
    private(set) var timetableFailed = false
    private var isLoading = false
    /// When the app last went to the background, for the return to Now after a long time away (TT-222).
    @ObservationIgnored private var wentToBackgroundAt: Date?
    /// The Today last acted on, so the day turning over at midnight is seen once (TT-159, D52).
    @ObservationIgnored private var knownToday: ServiceDay
    /// The last timetable and live status, resolved again before each poll's fetch so live data that aged past the
    /// freshness threshold while the app was away turns stale at once (D13).
    @ObservationIgnored private var loaded: (day: ServiceDay, trips: [Trip], live: LiveSnapshot)?
    /// Measured card sizes, reported by the view; the layout keeps cards 16 pt apart with them.
    @ObservationIgnored private var cardSizes: [TripKey: TimelineCardSize] = [:]
    /// The feels of a day tap, a swap and an alerted train turning late or boarding (TT-215, D100).
    private let haptics: any HapticPlaying
    @ObservationIgnored private var watchedFeels = WatchedTrainFeels()
    /// The train whose Trip details is open, set by RootView: the sheet plays its feels, so Schedule leaves it out.
    @ObservationIgnored var openTrip: TripKey?
    /// Told each route the rider's choice puts on Schedule (TT-234, D116): Automatic direction's look, set by RootView.
    @ObservationIgnored weak var choices: (any RouteChoiceFollowing)?
    /// Counts the turns made without the swap button (`turn(_:while:)`): the Feedback button's wait starts again on it.
    private(set) var turns = 0
    /// The last such turn, for the route card's calm swap (TT-235, D116): the names as they stood and when they start to
    /// trade. A turn made under the launch splash is held (no start) until the splash has gone (`setSplashCovers(_:fade:)`).
    private(set) var turnToken: RouteCard.Turn?
    /// The route card's From marker is the location arrow (TT-235, D116): the app turned the route from the rider's place
    /// in this visit (by itself, or by the capsule's Switch). It goes when the app goes to the background, on Undo, and
    /// when the route changes by hand or by a link.
    private(set) var marksFrom = false
    /// The trains the last turn replaced, drawn once more over the new ones while they fade (TT-235, D116); nil a moment
    /// after, and when nothing of them showed.
    private(set) var outgoing: OutgoingTrains?
    /// The launch splash covers Schedule, as the view reports it.
    @ObservationIgnored private var splashCovers = false
    /// A turn's trains show from the timetable until their live status lands: a watched train that is late already is
    /// then first noted, not felt as turning late.
    @ObservationIgnored private var fillsLive = false

    /// The trains a turn replaced, as they stood at that moment (TT-235, D116).
    struct OutgoingTrains {
        /// The `entranceRequest` that brought the new trains: the old ones are drawn only while it is the latest.
        let request: Int
        let route: Route
        let departures: [Departure]
        let layout: TimelineLayout
        let now: Date
        let next: TripKey?
        let freshness: Freshness?
        let hasPlatformSource: Bool
        let isToday: Bool
        let isPastDay: Bool
        /// Where that timeline opened (`initialScrollOffset` on Today, its top on another day): the old cards are drawn as
        /// far from the new opening as they stood from this one.
        let opensAt: CGFloat
        /// The cards near the opening, which are the ones drawn.
        let shown: Set<TripKey>
    }
    /// How far above and below the opening the outgoing cards are drawn, and how long they are kept.
    private static let outgoingAbove: CGFloat = 400
    private static let outgoingBelow: CGFloat = 1400
    private static let outgoingLasts: Duration = .seconds(2)

    init(
        route: Route?, repository: any ScheduleRepository, clock: any AppClock, routeStore: (any RouteStoring)? = nil,
        recents: RecentRoutes = RecentRoutes(defaults: nil), dismissedNotices: DismissedNotices = DismissedNotices(defaults: nil),
        watchedTrips: any WatchedTripsProviding = NoWatchedTrips(), routeCount: RouteCount = RouteCount(defaults: nil),
        boardingShown: BoardingShown = BoardingShown(defaults: nil), weather: WeatherTileModel? = nil,
        haptics: any HapticPlaying = TTHaptics.shared
    ) {
        self.route = route
        self.weather = weather ?? .app(clock: clock, station: route?.from)
        self.haptics = haptics
        self.routeCount = routeCount
        self.boardingShown = boardingShown
        self.repository = repository
        self.clock = clock
        self.routeStore = routeStore
        self.recents = recents
        self.dismissedNotices = dismissedNotices
        self.watchedTrips = watchedTrips
        let now = clock.now
        self.now = now
        let day = ServiceDay(calendarDayContaining: now)
        selectedDay = day
        knownToday = day
        if let route { recents.record(route) }
    }

    /// The calendar day in Toronto: the screen turns to the next day at 12:00 AM, not at the 3:00 AM service-day cutoff
    /// the rest of the app keeps (TT-159, D52).
    var today: ServiceDay { ServiceDay(calendarDayContaining: clock.now) }
    var isToday: Bool { selectedDay == today }
    /// A past day's cards only fade in; the cascade's drop is for today and later (TT-164, D61).
    var isPastDay: Bool { selectedDay < today }
    /// The day strip, Today first, running to the schedule's last service day (every day of the GTFS calendar, up to
    /// `maxDayCount`). Today always shows.
    var days: [ServiceDay] {
        let first = today
        let count = lastServiceDay == nil ? Self.dayCount : Self.maxDayCount
        let later = (1..<count).map { first.adding(days: $0) }
        return [first] + later.filter { day in lastServiceDay.map { day <= $0 } ?? true }
    }
    /// The previous 7 days, oldest first: the strip shows them to the left of Today (TT-160, D53).
    var pastDays: [ServiceDay] {
        let first = today
        return (1...Self.pastDayCount).reversed().map { first.adding(days: -$0) }
    }
    /// Everything the strip shows: `pastDays`, then `days`.
    var stripDays: [ServiceDay] { pastDays + days }
    /// A day's place in the strip counted from Today: 0 is Today, 1 tomorrow, -1 yesterday. Nil for a day the strip lacks.
    func stripIndex(of day: ServiceDay) -> Int? {
        stripDays.firstIndex(of: day).map { $0 - Self.pastDayCount }
    }

    /// "Oakville to Union".
    var routeTitle: String? {
        route.map { String(format: String(localized: "schedule.route_title"), $0.from.name, $0.to.name) }
    }

    /// What fills the space under the day strip (TT-115).
    enum Content: Equatable {
        /// The first timetable for this route is loading: skeleton cards on the rail.
        case loading
        case timeline
        /// "No direct trains on Sunday", one sentence, and "Show Monday" when a later day in the strip has trains.
        case noTrains(title: String, message: String, showDay: String?)
        /// The stations share no line, so no direct train can run between them.
        case noConnection
        /// No timetable on device and the download failed: "Couldn’t load the timetable" with Try again (TT-206).
        case failed
    }

    var content: Content {
        guard let route else { return .loading }
        guard route.line != nil else { return .noConnection }
        if freshness == nil, timetableFailed { return .failed }
        guard freshness != nil, !(awaitsNewTrains && newTrainsAreSlow) else { return .loading }
        guard departures.isEmpty else { return .timeline }
        return .noTrains(
            title: String(format: String(localized: "schedule.no_trains.title"), selectedDay.weekdayName),
            message: String(
                format: String(localized: "schedule.no_trains.body"), route.from.name, route.to.name, selectedDay.shortLabel
            ),
            showDay: nextDayWithTrains.map { String(format: String(localized: "schedule.no_trains.show_day"), $0.weekdayName) }
        )
    }

    /// "Open GO trip planner" on the No direct connection card.
    static let tripPlannerURL = URL(string: "https://www.gotransit.com/en/plan-your-trip")!

    /// The next usable train on today's timeline: the first that is not cancelled, skipped or gone by the boarding rule
    /// (TT-233, D114). A train standing at its platform past its time stays the next one, and its countdown then reads
    /// "Departing"; with no position a train at now has left (D86). None on another day.
    var nextDepartureId: TripKey? {
        guard isToday else { return nil }
        return departures.first { $0.isUsable && !$0.hasLeft(at: now) }?.id
    }

    /// The timeline cards in departure order, times from the one formatter the view passes in.
    func cards(_ formatter: some TimeFormatting) -> [DepartureCard] {
        let next = nextDepartureId
        return departures.indices.map { index in
            let departure = departures[index]
            let usableBelow = departures[(index + 1)...].contains { $0.isUsable }
            let isNext = departure.id == next
            let awaitsPlatform = freshness.map {
                departure.awaitsPlatform(isNext: isNext, now: now, freshness: $0, hasPlatformSource: hasPlatformSource)
            } ?? false
            return DepartureCard(
                departure, isNext: isNext, nextUsableBelow: usableBelow, awaitsPlatform: awaitsPlatform,
                isDeparted: hasDeparted(departure), isBoarding: isBoarding(departure), now: now, formatter: formatter
            )
        }
    }

    /// The cards of the trains a turn has just replaced, as they stood (TT-235, D116): only those near where the timeline
    /// was open.
    func cards(of outgoing: OutgoingTrains, _ formatter: some TimeFormatting) -> [DepartureCard] {
        let departures = outgoing.departures
        return departures.indices.compactMap { index in
            let departure = departures[index]
            guard outgoing.shown.contains(departure.id) else { return nil }
            let isNext = departure.id == outgoing.next
            let awaitsPlatform = outgoing.freshness.map {
                departure.awaitsPlatform(
                    isNext: isNext, now: outgoing.now, freshness: $0, hasPlatformSource: outgoing.hasPlatformSource
                )
            } ?? false
            return DepartureCard(
                departure, isNext: isNext, nextUsableBelow: departures[(index + 1)...].contains { $0.isUsable },
                awaitsPlatform: awaitsPlatform,
                isDeparted: outgoing.isPastDay || (outgoing.isToday && departure.hasLeft(at: outgoing.now)),
                isBoarding: outgoing.isToday && departure.isBoarding(at: outgoing.now), now: outgoing.now, formatter: formatter
            )
        }
    }

    /// Every train on a past day; on Today, a train that has left by the boarding rule (TT-233, D114): it moved off its
    /// station, GO's trip feed dropped the station, or, with no position to go by, its expected departure is at or before
    /// now (TT-203, D86). Never on a later day.
    func hasDeparted(_ departure: Departure) -> Bool {
        if isPastDay { return true }
        return isToday && departure.hasLeft(at: now)
    }

    /// On Today, the train stands at the rider's station with its platform posted (`BoardingRule`): its card is Boarding.
    func isBoarding(_ departure: Departure) -> Bool {
        isToday && departure.isBoarding(at: now)
    }

    /// A gridline label hides near the "Now" label.
    func showsLabel(_ gridline: TimelineLayout.Gridline) -> Bool {
        guard let nowY = layout.nowY else { return true }
        return abs(gridline.y - nowY) > TTTimeline.pillLabelHideDistance
    }

    /// The view reports each card's measured size; the layout is recomputed only when one moves by a point or more,
    /// so sub-point rounding can never start a measure and relayout loop.
    func setCardSize(_ size: TimelineCardSize, for id: TripKey) {
        if let old = cardSizes[id], abs(old.height - size.height) < 1, abs(old.anchor - size.anchor) < 1 {
            settleIfMeasured()
            return
        }
        cardSizes[id] = size
        relayout()
        settleIfMeasured()
    }

    /// A scroll request, then another once every card has its measured size (D49): the first scroll ran before the cards
    /// were measured, so the Now line has moved since. The view makes the launch's second scroll without animation and
    /// later ones with.
    private func requestScroll(jumping: Bool = false) {
        pulsesOnSettle = false
        scrollJumps = jumping
        scrollRequest += 1
        awaitsMeasurement = !departures.allSatisfy { cardSizes[$0.id] != nil }
        let request = scrollRequest
        Task {
            for delay in Self.rescrollDelays {
                try? await Task.sleep(for: delay)
                guard request == scrollRequest else { return }
                rescrollRequest += 1
            }
        }
    }

    /// When the view scrolls again after a scroll request (TT-159, D52).
    private static let rescrollDelays: [Duration] = [.milliseconds(150), .milliseconds(600)]

    private func settleIfMeasured() {
        guard awaitsMeasurement, departures.allSatisfy({ cardSizes[$0.id] != nil }) else { return }
        awaitsMeasurement = false
        settleRequest += 1
        if pulsesOnSettle {
            pulsesOnSettle = false
            nowPulse += 1
        }
    }

    /// Once a minute: the Now line moves, without animation, and "in N min" counts down. A train that leaves on this tick
    /// plays its step up (D86) unless `playsDepartures` is false.
    func tick(playsDepartures: Bool = true) {
        let current = clock.now
        guard current != now else { return }
        now = current
        countBoarding()
        relayout(playsDepartures: playsDepartures)
    }

    /// Ticks on every minute boundary while the screen is shown, and once on start, so coming back to the screen
    /// (from Settings, say) never shows the minute it was left.
    func runClock() async {
        // The screen has just shown: trains that left while it was away are drawn at rest.
        tick(playsDepartures: false)
        await rollOverIfNeeded()
        while !Task.isCancelled {
            let seconds = 60 - clock.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            tick()
            await rollOverIfNeeded()
        }
    }

    /// The day changed while the screen stayed open (TT-159, D52, D53): a rider looking at Today, at a later day that has
    /// become Today or past since they chose it, or at a day that has dropped out of the strip, moves to the new Today from
    /// its top (Now is the first thing on it), as a relaunch would, and the strip selects it. A rider browsing a later day,
    /// or a past day they chose on purpose, stays there; the strip only shifts.
    func rollOverIfNeeded() async {
        let current = today
        guard current != knownToday else { return }
        let previous = knownToday
        let followsToday = (previous <= selectedDay && selectedDay <= current)
            || selectedDay < current.adding(days: -Self.pastDayCount)
        knownToday = current
        now = clock.now
        guard followsToday else {
            resolve()
            return
        }
        selectedDay = current
        guard hasLoaded else { return }
        await load()
        requestScroll()
    }


    /// The status row above the timeline (D49): only while the timetable loads, offline, or showing stale data. Live and
    /// timetable-only data say nothing there.
    func statusRowMode(_ formatter: some TimeFormatting) -> FreshnessLine.Mode? {
        guard let mode = freshnessMode(formatter) else { return nil }
        switch mode {
        case .loading, .stale, .offline: return mode
        case .live, .scheduledOnly: return nil
        }
    }

    /// The freshness line (D14), with times from the one formatter. "Loading timetable" until the first load.
    func freshnessMode(_ formatter: some TimeFormatting) -> FreshnessLine.Mode? {
        switch freshness {
        case nil: route == nil || timetableFailed ? nil : .loading
        case .live(let updatedAt): .live(updated: formatter.updated(at: updatedAt, now: clock.now))
        case .scheduledOnly: .scheduledOnly(day: isToday ? nil : selectedDay.shortLabel)
        case .stale(let lastReported): .stale(lastReported: formatter.time(lastReported))
        case .offline(let lastUpdated): .offline(lastUpdated: lastUpdated.map { formatter.time($0) })
        }
    }

    /// The watched train that has left, for the strip above the timeline (TT-144): today only, from the moment it is known
    /// to have left (`isKnownGone`), as Trip details says "Departed" (D32), until 10 min after its arrival (estimated, else
    /// scheduled) or until swiped away. The latest such train when there are several. Watched means the train's own alert
    /// (TT-189), so a repeating alert's train counts on each of its days.
    var watchedDeparture: Departure? {
        guard isToday, let route else { return nil }
        return departures.last { departure in
            guard isKnownGone(departure), !dismissedWatchedTrips.contains(departure.id),
                  watchedTrips.isWatched(departure.trip, on: route) else { return false }
            let arrival = departure.expectedArrival ?? departure.trip.scheduledArrival
            return now < arrival.addingTimeInterval(Self.watchedStripAfterArrival)
        }
    }

    /// "Departed" as the watched-trip strip says it (D32), by the boarding rule (TT-233, D114): GO's feeds say the train has
    /// left (it moved off, or its station dropped out of the trip), or its live departure time has passed with no position
    /// to say otherwise. The scheduled time passing with no live data is not enough, and a train still standing at its
    /// platform past its time has not left.
    private func isKnownGone(_ departure: Departure) -> Bool {
        switch BoardingRule.phase(of: departure, now: now).source {
        case .moved?, .feed?: true
        case .clock?: departure.expectedDeparture != nil
        case nil: false
        }
    }

    /// The strip's text, times from the one formatter the view passes in.
    func watchedStrip(_ formatter: some TimeFormatting) -> WatchedTripStrip? {
        guard let departure = watchedDeparture, let route else { return nil }
        let arrival = departure.expectedArrival.map {
            String(format: String(localized: "schedule.watched.est_arrival"), formatter.time($0))
        } ?? String(format: String(localized: "schedule.watched.scheduled_arrival"), formatter.time(departure.trip.scheduledArrival))
        return WatchedTripStrip(
            id: departure.id,
            title: String(format: String(localized: "schedule.watched.title"), formatter.time(departure.trip.scheduledDeparture), route.to.name),
            detail: arrival
        )
    }

    /// The Live Activity's train (TT-178, D74): the same train at `now`, the app's clock to the second, and still for the 10
    /// min after it left (or to your stop), while the activity asks "On board?" (TT-231).
    func activityDeparture(at now: Date) -> LiveDeparture? {
        guard isToday, let route else { return nil }
        return LiveDeparture.earliest(in: departures, now: now) { watchedTrips.isAlerted($0.trip, on: route) }
    }

    /// Swiped away: that train's strip stays hidden while the app runs.
    func dismissWatchedStrip(_ id: TripKey) {
        dismissedWatchedTrips.insert(id)
    }

    /// The line notice sheet's rows, times from the one formatter the view passes in.
    func noticeRows(_ formatter: some TimeFormatting) -> [LineNoticeRow] {
        todayNotices.map { notice in
            LineNoticeRow(
                id: notice.id,
                title: String(format: String(localized: "notice.title"), notice.lineName),
                text: notice.text,
                details: notice.details,
                reported: reported(notice.reportedAt, formatter)
            )
        }
    }

    /// "Reported at 7:12 AM" today, else with the day, "Reported Nov 7 at 1:57 PM": GO's notices start when they were
    /// posted, often days before (D91).
    private func reported(_ date: Date, _ formatter: some TimeFormatting) -> String {
        if ServiceDay(calendarDayContaining: date) == ServiceDay(calendarDayContaining: now) {
            return String(format: String(localized: "notice.reported"), formatter.time(date))
        }
        return String(format: String(localized: "notice.reported_on"), formatter.shortDate(date), formatter.time(date))
    }

    /// Hides the notice until a notice with a new id arrives, after a relaunch too.
    func dismissNotice(_ id: String) {
        dismissedNotices.dismiss(id)
        lineNotices.removeAll { $0.id == id }
        todayNotices.removeAll { $0.id == id }
    }

    /// The first load, then a scroll to the present; the cards cascade in, and Now pulses once the scroll has settled.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        let turnsBefore = turns
        await loadNewTrains()
        // A turn made while this load ran (Automatic direction under the splash, TT-235) brought its own trains, its jump
        // to Now and the one Now play.
        guard turns == turnsBefore else { return }
        requestScroll()
        pulsesOnSettle = true
    }

    /// Pull to refresh. Cards keep their trip key (D9), so they keep their identity, and the scroll position stays.
    func refresh() async {
        await load()
    }

    /// Try again on the failed card: "Loading timetable" again while the download runs.
    func retry() async {
        timetableFailed = false
        await load()
    }

    /// While Schedule is on screen with the app in the foreground: live status again at once (on coming back to the
    /// app; the first load does it at launch), then every 30 s (TT-131). Only today has live status. Each refresh keeps
    /// the cards' identity and the scroll position, as pull to refresh does.
    func pollLiveStatus(every interval: Duration = ScheduleViewModel.livePollInterval) async {
        // The first poll runs on coming back to the app: trains that left meanwhile are drawn at rest (D86).
        var plays = false
        while !Task.isCancelled {
            await pollOnce(playsDepartures: plays)
            plays = true
            try? await Task.sleep(for: interval)
        }
    }

    /// One poll of `pollLiveStatus`: the data on screen at the current clock, then today's live status again. A train the
    /// new status says has left plays its step up unless `playsDepartures` is false (the first poll). Tests call it to poll
    /// without waiting.
    func pollOnce(playsDepartures plays: Bool) async {
        guard hasLoaded, !isLoading else { return }
        // Data left on screen while the app was away ages first, so it never shows as live during the fetch (D13).
        now = clock.now
        if today != knownToday {
            // The day changed while the app stayed in memory (or in the background): the timeline moves to Today
            // and the present, as a relaunch would (D30, D52).
            await rollOverIfNeeded()
        } else {
            resolve(playsDepartures: plays)
            if isToday { await load(playsDepartures: plays) }
        }
    }

    /// Another day shows scheduled times only, with no Now line, starting at that day's first train. Today, also when it is
    /// already selected, does what tapping the Schedule tab again does: back to Now, with the pulse (TT-197, D80).
    func select(_ day: ServiceDay) async {
        if day == today { return await backToNow() }
        guard day != selectedDay else { return }
        Analytics.track(.dayChanged(offset: today.days(to: day)))
        selectedDay = day
        daySelection += 1
        await loadNewTrains()
        requestScroll(jumping: true)
    }

    /// A day tile tapped: Tick at the tap (TT-215, D100), then `select(_:)`.
    func dayTapped(_ day: ServiceDay) async {
        haptics.play(.day)
        await select(day)
    }

    /// Tapping the Schedule tab while Schedule shows: back to today and the present in one tap (D49), and the Now dot
    /// pulses (TT-164).
    func backToNow() async {
        knownToday = today
        let jumping = !isToday
        if jumping {
            selectedDay = today
            daySelection += 1
            await loadNewTrains()
        }
        requestScroll(jumping: jumping)
        nowPulse += 1
    }

    /// The app went to the background: the moment is kept for `cameToForeground()` (TT-222).
    func wentToBackground() {
        wentToBackgroundAt = clock.now
        // The arrow on From lives for the visit (TT-235, D116).
        if marksFrom { marksFrom = false }
        if outgoing != nil { outgoing = nil }
    }

    /// Back in the foreground. After more than 10 min away the timeline goes back to Now on Today, exactly as the
    /// Schedule tab tapped again does (TT-222); a shorter time keeps the day and the scroll, and Now plays where it is
    /// (D80).
    ///
    /// `look` is Automatic direction's look (TT-234, D116), awaited first, 1 s at most, so there is one arrival and one
    /// Now play: after a long time away Today is put back before it, so the look runs on Today (the other day's cards
    /// hide meanwhile). When it turned the route (true), the turn's own load, jump to Now and Now play are the arrival.
    func cameToForeground(looking look: (@MainActor () async -> Bool)? = nil) async {
        let away = wentToBackgroundAt.map { clock.now.timeIntervalSince($0) } ?? 0
        wentToBackgroundAt = nil
        let returns = hasLoaded && away > Self.returnToNowAfter
        var jumping = false
        if returns {
            Analytics.track(.backToNow(.reopen))
            knownToday = today
            jumping = !isToday
            if jumping {
                selectedDay = today
                daySelection += 1
                if look != nil { awaitsNewTrains = true }
            }
        }
        if let look, await look() { return }
        guard returns else { return timelineAppeared() }
        if jumping { await loadNewTrains() }
        requestScroll(jumping: jumping)
        nowPulse += 1
    }

    /// The timeline shows again (back to the Schedule tab, back to the foreground): Now plays where it is, without scrolling,
    /// so the rider sees which moment the line marks (TT-197, D80). The launch's own play waits for its scroll to settle.
    func timelineAppeared() {
        guard hasLoaded, isToday, !pulsesOnSettle else { return }
        nowPulse += 1
    }

    /// The clock jumped (Mock time changed in Settings, TT-158): back to today and the present, as a relaunch would.
    func restart() async {
        knownToday = today
        selectedDay = today
        now = clock.now
        guard hasLoaded else { return }
        await loadNewTrains()
        requestScroll(jumping: true)
    }

    /// "Show Monday" on a day with no direct trains.
    func showNextDayWithTrains() async {
        guard let nextDayWithTrains else { return }
        await dayTapped(nextDayWithTrains)
    }

    /// The swap button: the rider's own choice, which Automatic direction keeps (TT-234, D116). The new direction is
    /// remembered.
    func swap() async {
        guard let route else { return }
        haptics.play(.swap)
        Analytics.track(.routeSwapped)
        let swapped = Route(from: route.to, to: route.from, line: route.line)
        self.route = swapped
        if marksFrom { marksFrom = false }
        routeStore?.save(swapped)
        recents.record(swapped)
        choices?.chose(swapped, by: .byHand)
        await loadNewTrains()
        requestScroll(jumping: true)
    }

    /// The route turns round without the swap button (TT-234, D116): by itself when the app opens at the other station,
    /// by the capsule's Undo or by its Switch. Silent: no haptic and no event (the caller plays Undo's and Switch's own
    /// feel), and never through `swap()` or `show(_:chosen:)`. The route is saved and recorded in Recent as a swap is, and
    /// the timeline is at Now after it with one Now play.
    ///
    /// The turn never empties the timeline (TT-235, D116): the other direction's trains are read first, while the old
    /// ones show, then the route and the trains change in one step, straight from the timetable; the old cards are kept
    /// as `outgoing` for their fade, and status and platforms fill in as a poll's do. `stillMay` is asked once the trains
    /// are in, right before that step: false leaves everything as it is. Returns false when nothing turned: `stillMay`
    /// said no, the route or the day changed meanwhile, or a turn by itself found no timetable to read (the look then
    /// asks). Undo and Switch are the rider's taps: with no timetable they turn as any new route does. Before the first
    /// load (a cold start under the splash) the route alone changes, and the launch's load reads it.
    @discardableResult
    func turn(_ kind: RouteTurnKind = .byItself, while stillMay: @MainActor () -> Bool = { true }) async -> Bool {
        guard let route else { return false }
        let turned = Route(from: route.to, to: route.from, line: route.line)
        guard hasLoaded else {
            guard stillMay() else { return false }
            setTurned(turned, from: route, kind: kind)
            return true
        }
        let day = selectedDay
        let trips = try? await repository.trips(for: turned, on: day)
        var nextDay: ServiceDay?
        if let trips, trips.isEmpty { nextDay = await firstDayWithTrains(after: day, on: turned) }
        // Another route or day was chosen while the trains were read: that choice stands.
        guard route == self.route, day == selectedDay else { return false }
        guard let trips else {
            guard kind != .byItself, stillMay() else { return false }
            setTurned(turned, from: route, kind: kind)
            await loadNewTrains()
            requestScroll(jumping: true)
            if isToday { nowPulse += 1 }
            return true
        }
        guard stillMay() else { return false }
        // From here to the scroll request nothing is awaited: the route, its trains and the old cards' last frame are one
        // update.
        let old = loaded.flatMap { $0.day == day ? $0 : nil }
        let leaving = outgoingTrains(on: old != nil)
        setTurned(turned, from: route, kind: kind)
        // An older load of new trains can neither hide these nor end a wait for them.
        newTrainsTicket += 1
        if awaitsNewTrains { awaitsNewTrains = false }
        if newTrainsAreSlow { newTrainsAreSlow = false }
        if timetableFailed { timetableFailed = false }
        nextDayWithTrains = nextDay
        now = clock.now
        entranceRequest += 1
        // Timetable times until the status lands. The data mode stays what it was, so the status row does not blink.
        fillsLive = true
        loaded = (day, trips, LiveSnapshot(updatedAt: old?.live.updatedAt, isOffline: old?.live.isOffline ?? false))
        resolve()
        keep(leaving)
        requestScroll(jumping: true)
        if isToday { nowPulse += 1 }
        await load()
        fillsLive = false
        return true
    }

    /// The route turned (TT-235, D116): saved and recorded as a swap is, with the token the route card plays its calm
    /// swap from (held while the launch splash covers it) and, unless it is an Undo, the arrow on From.
    private func setTurned(_ turned: Route, from route: Route, kind: RouteTurnKind) {
        self.route = turned
        turns += 1
        routeStore?.save(turned)
        recents.record(turned)
        // Device time: the card draws the swap from the display's clock, which Mock time does not move.
        turnToken = RouteCard.Turn(id: turns, from: route.from.name, to: route.to.name, start: splashCovers ? nil : Date())
        let marks = kind != .undone
        if marks != marksFrom { marksFrom = marks }
    }

    /// The trains on screen right now, for their fade under a turn's new ones; nil when none show (under the splash,
    /// hidden for a load of new trains, or no timeline).
    private func outgoingTrains(on showsDay: Bool) -> OutgoingTrains? {
        guard showsDay, !splashCovers, !awaitsNewTrains, content == .timeline, let route else { return nil }
        let opensAt = isToday ? layout.initialScrollOffset : 0
        let shown = layout.cards.filter {
            $0.bottom >= opensAt - Self.outgoingAbove && $0.top <= opensAt + Self.outgoingBelow
        }
        return OutgoingTrains(
            request: entranceRequest + 1, route: route, departures: departures, layout: layout, now: now, next: nextDepartureId,
            freshness: freshness, hasPlatformSource: hasPlatformSource, isToday: isToday, isPastDay: isPastDay, opensAt: opensAt,
            shown: Set(shown.map(\.id))
        )
    }

    /// Keeps the replaced trains for their fade, while the new ones are a timeline to fade over.
    private func keep(_ leaving: OutgoingTrains?) {
        guard let leaving, leaving.request == entranceRequest, content == .timeline else {
            if outgoing != nil { outgoing = nil }
            return
        }
        outgoing = leaving
        let request = leaving.request
        let lasts = Self.outgoingLasts
        Task { [weak self] in
            try? await Task.sleep(for: lasts)
            guard let self, self.outgoing?.request == request else { return }
            self.outgoing = nil
        }
    }

    /// The launch splash covers Schedule, or has lifted (the view reports it, TT-235, D116). A turn made under it held
    /// its token: the names trade once the splash has gone, the lift plus its fade (`LaunchMotion`'s 200 ms, 240 ms on
    /// the first 8 launches).
    func setSplashCovers(_ covers: Bool, fade: TimeInterval = LaunchMotion.timing.markFadeDuration) {
        let lifted = splashCovers && !covers
        splashCovers = covers
        guard lifted, var token = turnToken, token.start == nil else { return }
        token.start = Date().addingTimeInterval(fade)
        turnToken = token
    }

    /// A route to show, saved on device so the next launch opens it (TT-120), with who chose it (TT-234, D116): by hand
    /// (the station picker, a Recent row, the welcome), one train's link, or a widget's route link.
    func show(_ route: Route, chosen choice: RouteChoice = .byHand) async {
        routeCount.set(route, isFirst: self.route == nil)
        // The arrow on From goes when the route changes by hand or by a link (TT-235, D116).
        if marksFrom, route != self.route { marksFrom = false }
        self.route = route
        routeStore?.save(route)
        recents.record(route)
        choices?.chose(route, by: choice)
        // On first use the timeline appears only now and loads itself (`loadIfNeeded`), scrolling to Now.
        guard hasLoaded else { return }
        await loadNewTrains()
        requestScroll(jumping: true)
    }

    /// A load for another day or route: the old cards hide at once and the new ones cascade in once it lands.
    private func loadNewTrains() async {
        newTrainsTicket += 1
        let ticket = newTrainsTicket
        awaitsNewTrains = true
        let slow = Task {
            try? await Task.sleep(for: Self.slowNewTrains)
            if !Task.isCancelled, ticket == newTrainsTicket { newTrainsAreSlow = true }
        }
        defer {
            slow.cancel()
            if ticket == newTrainsTicket {
                awaitsNewTrains = false
                if newTrainsAreSlow { newTrainsAreSlow = false }
            }
        }
        await load(newTrains: true)
    }

    /// `newTrains` asks for the cascade in the same update that puts the trains on screen, so they never show at rest first.
    private func load(newTrains: Bool = false, playsDepartures: Bool = false) async {
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }
        guard let route else { return }
        let day = selectedDay
        let isToday = day == today
        guard let trips = try? await repository.trips(for: route, on: day) else {
            // No timetable on device yet and none could be downloaded (TT-130): "Loading timetable" stays until a refresh
            // gets one, rather than claiming there are no trains.
            guard day == selectedDay, route == self.route else { return }
            if !timetableFailed { Analytics.track(.offlineShown(.timetable)) }
            timetableFailed = true
            loaded = nil
            departures = []
            freshness = nil
            lineNotices = []
            if isToday { setTodayNotices([], line: route.line) }
            relayout()
            return
        }
        if timetableFailed { timetableFailed = false }
        lastServiceDay = try? await repository.lastServiceDay()
        // Notices load alongside live status, so a dead connection still shows Offline after one 10 s timeout (D36).
        let source = repository
        async let fetchedNotices = Self.notices(on: route, from: source, isToday: isToday)
        let live = isToday ? (try? await repository.liveStatus(for: route, on: day)) ?? .empty : .empty
        let notices = await fetchedNotices
        let nextDay = trips.isEmpty ? await firstDayWithTrains(after: day, on: route) : nil
        // A newer day or route was picked while this one loaded.
        guard day == selectedDay, route == self.route else { return }
        nextDayWithTrains = nextDay
        // Filtered only now, so a notice dismissed while this load ran stays hidden.
        let visible = notices.filter { !dismissedNotices.contains($0.id) }
        if visible != lineNotices { lineNotices = visible }
        if isToday {
            setTodayNotices(visible, line: route.line)
        } else if route.line?.id != todayNoticesLine {
            setTodayNotices([], line: nil)
        }
        now = clock.now
        // Trains that replace "Loading timetable" cascade too, even when a refresh brings them.
        if newTrains || loaded == nil { entranceRequest += 1 }
        // The live status a turn's trains waited for is here.
        fillsLive = false
        loaded = (day, trips, live)
        resolve(playsDepartures: playsDepartures && !newTrains)
    }

    /// The statuses and the status row from the last load at the current clock.
    private func resolve(playsDepartures: Bool = false) {
        guard let loaded else {
            relayout()
            return
        }
        let isToday = loaded.day == today
        let freshness = isToday ? Freshness(loaded.live, now: now) : .scheduledOnly
        let departures = Departure.resolve(loaded.trips, live: isToday ? loaded.live : .empty, freshness: freshness, isToday: isToday)
        if departures != self.departures { self.departures = departures }
        if freshness != self.freshness {
            if case .offline = freshness, !Self.isOffline(self.freshness) { Analytics.track(.offlineShown(.live)) }
            self.freshness = freshness
        }
        let hasPlatformSource = isToday && loaded.live.hasPlatformSource
        if hasPlatformSource != self.hasPlatformSource { self.hasPlatformSource = hasPlatformSource }
        playWatchedFeels()
        countBoarding()
        relayout(playsDepartures: playsDepartures)
    }

    /// `boarding_shown` for every train on Today's timeline that is Boarding by the rule (TT-233, D114), each time the
    /// trains or the clock are refreshed; `BoardingShown` sends it once per train per day.
    private func countBoarding() {
        guard isToday, route != nil else { return }
        for departure in departures where departure.isBoarding(at: now) {
            boardingShown.shown(departure, surface: .schedule, now: now)
        }
    }

    /// An alerted train on Today's timeline turning late or cancelled plays Warning, reaching Boarding now Rail joint
    /// (TT-215, D100); not the train whose Trip details is open, which plays its own.
    private func playWatchedFeels() {
        guard isToday, let route, !fillsLive else {
            watchedFeels = WatchedTrainFeels()
            return
        }
        let watched = watchedTrips
        let open = openTrip
        let moment = watchedFeels.moment(for: departures, now: now) {
            $0.id != open && watched.isAlerted($0.trip, on: route)
        }
        if let moment { haptics.play(moment) }
    }

    private static func isOffline(_ freshness: Freshness?) -> Bool {
        if case .offline? = freshness { true } else { false }
    }

    private func setTodayNotices(_ notices: [LineNotice], line: Line?) {
        todayNoticesLine = line?.id
        if notices != todayNotices { todayNotices = notices }
    }

    /// Today's notices for the route's line. They are read apart from the trips, so they never change a status.
    private nonisolated static func notices(on route: Route, from repository: any ScheduleRepository, isToday: Bool) async -> [LineNotice] {
        guard isToday, let line = route.line else { return [] }
        return (try? await repository.lineNotices(for: line)) ?? []
    }

    private func firstDayWithTrains(after day: ServiceDay, on route: Route) async -> ServiceDay? {
        for candidate in days where candidate > day {
            if let trips = try? await repository.trips(for: route, on: candidate), !trips.isEmpty { return candidate }
        }
        return nil
    }

    /// Set only when it changes: each new card reports its size once, mostly the standard one the layout already used, and
    /// setting an equal layout would still redraw every card (a day of cards took a moment in a Debug build, TT-164).
    private func relayout(playsDepartures: Bool = false) {
        let previousNowY = self.layout.nowY
        let layout = TimelineLayout(TimelineInput(departures: departures, now: isToday ? now : nil, cardSizes: cardSizes))
        if layout != self.layout { self.layout = layout }
        trackDepartures(plays: playsDepartures, previousNowY: previousNowY)
    }

    /// Which trains have just left Today's timeline since the last layout, by the boarding rule (TT-233, D114), for the step
    /// up (TT-203, D86). Only trains that were on screen and not yet gone, usable, and seen to leave (`sawLeave`) play; a new
    /// day or route never does, nor an update that does not play (`plays` false: the screen or the app just came back).
    /// `train_departed` goes out for the train that was the next one, in the same updates.
    private func trackDepartures(plays: Bool, previousNowY: CGFloat?) {
        guard isToday else {
            seenDepartures = nil
            return
        }
        let departed = Set(departures.filter { $0.hasLeft(at: now) }.map(\.id))
        let next = nextDepartureId
        defer { seenDepartures = (selectedDay, route, Set(departures.map(\.id)), departed, next) }
        guard plays, let seen = seenDepartures, seen.day == selectedDay, seen.route == route else { return }
        let left = departures.filter {
            departed.contains($0.id) && !seen.departed.contains($0.id) && seen.present.contains($0.id) && $0.isUsable
                && sawLeave($0)
        }
        // The train that was the next one has left while Schedule watched: what said so, and how long after its scheduled
        // time. Sent once per train, whether or not its card moves.
        if let lead = left.first(where: { $0.id == seen.next }), let source = BoardingRule.phase(of: lead, now: now).source,
           countedDepartures.insert(lead.id).inserted {
            let seconds = now.timeIntervalSince(lead.trip.scheduledDeparture)
            Analytics.track(.trainDeparted(source: source, secondsAfter: Int(seconds.rounded(.down))))
        }
        // A train steps up only once every train before it has (`TimelineLayout`), so only those that did are moved.
        let steppedUp = Set(layout.cards.filter(\.isSteppedUp).map(\.id))
        let leaving = left.filter { steppedUp.contains($0.id) }
        guard !leaving.isEmpty else { return }
        departing = Set(leaving.map(\.id))
        departureLead = seen.next.flatMap { departing.contains($0) ? $0 : nil }
        departureNext = next
        let moved = (layout.nowY ?? 0) - (previousNowY ?? layout.nowY ?? 0)
        departureGlide = min(max(0, moved), 2 * TTTimeline.pointsPerMinute)
        departureRequest += 1
    }

    /// Schedule saw the train leave in this update: GO's feeds say so (it moved off its station, or the station dropped
    /// out of the trip), however long past its time, or the clock does within `departurePlayWindow`.
    private func sawLeave(_ departure: Departure) -> Bool {
        switch BoardingRule.phase(of: departure, now: now).source {
        case .moved?, .feed?: true
        case .clock?: now.timeIntervalSince(departure.departureTime) < Self.departurePlayWindow
        case nil: false
        }
    }

    /// A train the clock says left longer ago than this is drawn at rest: the app was away when it left.
    static let departurePlayWindow: TimeInterval = 60
}

extension ScheduleViewModel: RouteTurning {}

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

    private let repository: any ScheduleRepository
    private let clock: any AppClock
    /// Keeps the route on device (TT-120); nil in previews and tests that do not check it.
    private let routeStore: (any RouteStoring)?
    /// Each route shown is recorded first (D48); the station picker lists the others under Recent (D54).
    let recents: RecentRoutes
    private let dismissedNotices: DismissedNotices
    /// The trips with an alert, for the watched-trip strip (TT-144).
    private let watchedTrips: any WatchedTripsProviding
    private var hasLoaded = false
    private var isLoading = false
    /// The Today last acted on, so the day turning over at midnight is seen once (TT-159, D52).
    @ObservationIgnored private var knownToday: ServiceDay
    /// The last timetable and live status, resolved again before each poll's fetch so live data that aged past the
    /// freshness threshold while the app was away turns stale at once (D13).
    @ObservationIgnored private var loaded: (day: ServiceDay, trips: [Trip], live: LiveSnapshot)?
    /// Measured card sizes, reported by the view; the layout keeps cards 16 pt apart with them.
    @ObservationIgnored private var cardSizes: [TripKey: TimelineCardSize] = [:]

    init(
        route: Route?, repository: any ScheduleRepository, clock: any AppClock, routeStore: (any RouteStoring)? = nil,
        recents: RecentRoutes = RecentRoutes(defaults: nil), dismissedNotices: DismissedNotices = DismissedNotices(defaults: nil),
        watchedTrips: any WatchedTripsProviding = NoWatchedTrips()
    ) {
        self.route = route
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
    }

    var content: Content {
        guard let route else { return .loading }
        guard route.line != nil else { return .noConnection }
        guard freshness != nil else { return .loading }
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

    /// The next usable train on today's timeline: the first that is not cancelled, skipped or gone. None on another day.
    var nextDepartureId: TripKey? {
        guard isToday else { return nil }
        return departures.first { $0.isUsable && $0.departureTime >= now }?.id
    }

    /// The timeline cards in departure order, times from the one formatter the view passes in.
    func cards(_ formatter: some TimeFormatting) -> [DepartureCard] {
        let next = nextDepartureId
        return departures.indices.map { index in
            let departure = departures[index]
            let usableBelow = departures[(index + 1)...].contains { $0.isUsable }
            return DepartureCard(
                departure, isNext: departure.id == next, nextUsableBelow: usableBelow, now: now,
                formatter: formatter
            )
        }
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
    private func requestScroll() {
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
    }

    /// Once a minute: the Now line moves, without animation, and "in N min" counts down.
    func tick() {
        let current = clock.now
        guard current != now else { return }
        now = current
        relayout()
    }

    /// Ticks on every minute boundary while the screen is shown, and once on start, so coming back to the screen
    /// (from Settings, say) never shows the minute it was left.
    func runClock() async {
        tick()
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
        case nil: route == nil ? nil : .loading
        case .live(let updatedAt): .live(updated: formatter.updated(at: updatedAt, now: clock.now))
        case .scheduledOnly: .scheduledOnly(day: isToday ? nil : selectedDay.shortLabel)
        case .stale(let lastReported): .stale(lastReported: formatter.time(lastReported))
        case .offline(let lastUpdated): .offline(lastUpdated: lastUpdated.map { formatter.time($0) })
        }
    }

    /// The watched train that has left, for the strip above the timeline (TT-144): today only, from the moment its live
    /// departure time has passed, as Trip details says "Departed" (D32), until 10 min after its arrival (estimated, else
    /// scheduled) or until swiped away. The latest such train when there are several.
    var watchedDeparture: Departure? {
        guard isToday else { return nil }
        return departures.last { departure in
            guard let departed = departure.expectedDeparture, departed <= now,
                  !dismissedWatchedTrips.contains(departure.id), watchedTrips.isWatched(departure.id) else { return false }
            let arrival = departure.expectedArrival ?? departure.trip.scheduledArrival
            return now < arrival.addingTimeInterval(Self.watchedStripAfterArrival)
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
                reported: String(format: String(localized: "notice.reported"), formatter.time(notice.reportedAt))
            )
        }
    }

    /// Hides the notice until a notice with a new id arrives, after a relaunch too.
    func dismissNotice(_ id: String) {
        dismissedNotices.dismiss(id)
        lineNotices.removeAll { $0.id == id }
        todayNotices.removeAll { $0.id == id }
    }

    /// The first load, then a scroll to the present.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
        requestScroll()
    }

    /// Pull to refresh. Cards keep their trip key (D9), so they keep their identity, and the scroll position stays.
    func refresh() async {
        await load()
    }

    /// While Schedule is on screen with the app in the foreground: live status again at once (on coming back to the
    /// app; the first load does it at launch), then every 30 s (TT-131). Only today has live status. Each refresh keeps
    /// the cards' identity and the scroll position, as pull to refresh does.
    func pollLiveStatus(every interval: Duration = ScheduleViewModel.livePollInterval) async {
        while !Task.isCancelled {
            if hasLoaded, !isLoading {
                // Data left on screen while the app was away ages first, so it never shows as live during the fetch (D13).
                now = clock.now
                if today != knownToday {
                    // The day changed while the app stayed in memory (or in the background): the timeline moves to Today
                    // and the present, as a relaunch would (D30, D52).
                    await rollOverIfNeeded()
                } else {
                    resolve()
                    if isToday { await load() }
                }
            }
            try? await Task.sleep(for: interval)
        }
    }

    /// Another day shows scheduled times only, with no Now line, starting at that day's first train.
    func select(_ day: ServiceDay) async {
        guard day != selectedDay else { return }
        selectedDay = day
        await load()
        requestScroll()
    }

    /// Tapping the Schedule tab while Schedule shows: back to today and the present in one tap (D49).
    func backToNow() async {
        knownToday = today
        if !isToday {
            selectedDay = today
            await load()
        }
        requestScroll()
    }

    /// The clock jumped (Mock time changed in Settings, TT-158): back to today and the present, as a relaunch would.
    func restart() async {
        knownToday = today
        selectedDay = today
        now = clock.now
        guard hasLoaded else { return }
        await load()
        requestScroll()
    }

    /// "Show Monday" on a day with no direct trains.
    func showNextDayWithTrains() async {
        guard let nextDayWithTrains else { return }
        await select(nextDayWithTrains)
    }

    /// Swap is explicit, never automatic. The new direction is remembered.
    func swap() async {
        guard let route else { return }
        let swapped = Route(from: route.to, to: route.from, line: route.line)
        self.route = swapped
        routeStore?.save(swapped)
        recents.record(swapped)
        await load()
        requestScroll()
    }

    /// The route from the route form (TT-120), saved on device so the next launch opens it.
    func show(_ route: Route) async {
        self.route = route
        routeStore?.save(route)
        recents.record(route)
        // On first use the timeline appears only now and loads itself (`loadIfNeeded`), scrolling to Now.
        guard hasLoaded else { return }
        await load()
        requestScroll()
    }

    private func load() async {
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
            loaded = nil
            departures = []
            freshness = nil
            lineNotices = []
            if isToday { setTodayNotices([], line: route.line) }
            relayout()
            return
        }
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
        loaded = (day, trips, live)
        resolve()
    }

    /// The statuses and the status row from the last load at the current clock.
    private func resolve() {
        guard let loaded else {
            relayout()
            return
        }
        let isToday = loaded.day == today
        let freshness = isToday ? Freshness(loaded.live, now: now) : .scheduledOnly
        let departures = Departure.resolve(loaded.trips, live: isToday ? loaded.live : .empty, freshness: freshness, isToday: isToday)
        if departures != self.departures { self.departures = departures }
        if freshness != self.freshness { self.freshness = freshness }
        relayout()
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

    private func relayout() {
        layout = TimelineLayout(TimelineInput(departures: departures, now: isToday ? now : nil, cardSizes: cardSizes))
    }
}

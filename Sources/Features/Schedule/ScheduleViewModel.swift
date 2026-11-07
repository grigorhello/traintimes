import CoreGraphics
import Foundation
import Observation

/// The Schedule screen (TT-112): route header, day strip, freshness row and the Now button, plus the departures, cards
/// and layout the timeline draws (TT-113).
@Observable @MainActor
final class ScheduleViewModel {
    /// Today plus 13 days. Q6: the real horizon comes from the GTFS validity window in TT-130.
    static let dayCount = 14
    /// The Now button dims while the timeline sits within a minute of the present.
    static let atNowTolerance = TTTimeline.pointsPerMinute

    private(set) var route: Route?
    private(set) var selectedDay: ServiceDay
    private(set) var departures: [Departure] = []
    private(set) var layout = TimelineLayout()
    /// The clock at the last load or minute tick. The Now line, the next train and "in N min" read it.
    private(set) var now: Date
    /// Nil until the first load.
    private(set) var freshness: Freshness?
    /// Bumped when the timeline should scroll: to Now on today, to the first train on another day.
    /// A refresh never bumps it, so pull to refresh keeps the scroll position.
    private(set) var scrollRequest = 0
    /// True while today is selected and the timeline already shows the present: the Now button dims.
    /// Stored and set only when it flips, so scrolling does not re-render the screen every frame.
    private(set) var isAtNow = true
    /// Reported by the view on every scroll frame: the timeline's scroll offset and visible height.
    @ObservationIgnored var scrollOffset: CGFloat = 0 { didSet { updateIsAtNow() } }
    @ObservationIgnored var viewportHeight: CGFloat = 0 { didSet { updateIsAtNow() } }

    private let repository: any ScheduleRepository
    private let clock: any AppClock
    /// Keeps the route on device (TT-120); nil in previews and tests that do not check it.
    private let routeStore: (any RouteStoring)?
    /// The star (TT-122), shared with the route form's favourites list.
    let favourites: Favourites
    private var hasLoaded = false
    /// Measured card sizes, reported by the view; the layout keeps cards 16 pt apart with them.
    @ObservationIgnored private var cardSizes: [TripKey: TimelineCardSize] = [:]

    init(
        route: Route?, repository: any ScheduleRepository, clock: any AppClock, routeStore: (any RouteStoring)? = nil,
        favourites: Favourites = Favourites(defaults: nil)
    ) {
        self.route = route
        self.repository = repository
        self.clock = clock
        self.routeStore = routeStore
        self.favourites = favourites
        let now = clock.now
        self.now = now
        selectedDay = ServiceDay(containing: now)
    }

    var today: ServiceDay { ServiceDay(containing: clock.now) }
    /// The star: on when this route, in this direction, is a favourite.
    var isFavourite: Bool { route.map { favourites.contains($0) } ?? false }
    var isToday: Bool { selectedDay == today }
    /// The day strip, Today first.
    var days: [ServiceDay] { (0..<Self.dayCount).map { today.adding(days: $0) } }

    /// "Oakville to Union".
    var routeTitle: String? {
        route.map { String(format: String(localized: "schedule.route_title"), $0.from.name, $0.to.name) }
    }

    /// "Now", or "Today" while another day is selected.
    var nowButtonTitle: String {
        isToday ? String(localized: "button.now") : String(localized: "button.today")
    }

    var nowButtonAccessibilityLabel: String {
        isToday ? String(localized: "button.now.label") : String(localized: "button.today.label")
    }

    /// The next usable train on today's timeline: the first that is not cancelled, skipped or gone. None on another day.
    var nextDepartureId: TripKey? {
        guard isToday else { return nil }
        return departures.first { $0.isUsable && $0.departureTime >= now }?.id
    }

    /// The timeline cards in departure order, times from the one formatter the view passes in.
    func cards(_ formatter: some TimeFormatting) -> [DepartureCard] {
        let next = nextDepartureId
        return departures.map { DepartureCard($0, isNext: $0.id == next, now: now, formatter: formatter) }
    }

    /// A gridline label hides near a pill (TT-111) and near the "Now" label.
    func showsLabel(_ gridline: TimelineLayout.Gridline) -> Bool {
        guard gridline.showsLabel else { return false }
        guard let nowY = layout.nowY else { return true }
        return abs(gridline.y - nowY) > TTTimeline.pillLabelHideDistance
    }

    /// The "Now" label hides while a time pill sits beside it, as gridline labels do; the line and dot stay.
    var showsNowLabel: Bool {
        guard let nowY = layout.nowY else { return false }
        // A delayed train's struck pill at its scheduled time counts too (TT-114 draws it).
        let pills: [CGFloat] = layout.cards.flatMap { card in [card.markerY, card.scheduledMarkerY].compactMap { $0 } }
        return !pills.contains { abs($0 - nowY) <= TTTimeline.pillLabelHideDistance }
    }

    /// The view reports each card's measured size; the layout is recomputed only when one moves by a point or more,
    /// so sub-point rounding can never start a measure and relayout loop.
    func setCardSize(_ size: TimelineCardSize, for id: TripKey) {
        if let old = cardSizes[id], abs(old.height - size.height) < 1, abs(old.anchor - size.anchor) < 1 { return }
        cardSizes[id] = size
        relayout()
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
        while !Task.isCancelled {
            let seconds = 60 - clock.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            tick()
        }
    }


    /// The freshness line (D14), with times from the one formatter. Nil until the first load.
    func freshnessMode(_ formatter: some TimeFormatting) -> FreshnessLine.Mode? {
        switch freshness {
        case nil: nil
        case .live(let updatedAt): .live(updated: formatter.updated(at: updatedAt, now: clock.now))
        case .scheduledOnly: .scheduledOnly(day: isToday ? nil : selectedDay.shortLabel)
        case .stale(let lastReported): .stale(lastReported: formatter.time(lastReported))
        case .offline(let lastUpdated): .offline(lastUpdated: lastUpdated.map { formatter.time($0) })
        }
    }

    /// The first load, then a scroll to the present.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
        scrollRequest += 1
    }

    /// Pull to refresh. Cards keep their trip key (D9), so they keep their identity, and the scroll position stays.
    func refresh() async {
        await load()
    }

    /// Another day shows scheduled times only, with no Now line, starting at that day's first train.
    func select(_ day: ServiceDay) async {
        guard day != selectedDay else { return }
        selectedDay = day
        updateIsAtNow()
        await load()
        scrollRequest += 1
    }

    /// The Now button: back to today and the present in one tap.
    func backToNow() async {
        if !isToday {
            selectedDay = today
            updateIsAtNow()
            await load()
        }
        scrollRequest += 1
    }

    /// Swap is explicit, never automatic. The new direction is remembered.
    func swap() async {
        guard let route else { return }
        let swapped = Route(from: route.to, to: route.from, line: route.line)
        self.route = swapped
        routeStore?.save(swapped)
        await load()
        scrollRequest += 1
    }

    /// The route from the route form (TT-120), saved on device so the next launch opens it.
    func show(_ route: Route) async {
        self.route = route
        routeStore?.save(route)
        // On first use the timeline appears only now and loads itself (`loadIfNeeded`), scrolling to Now.
        guard hasLoaded else { return }
        await load()
        scrollRequest += 1
    }

    enum FavouriteResult {
        case toggled
        /// Three favourites already: the star never replaces one, the route sheet opens to manage them instead.
        case full
    }

    /// The star toggles the current route as a favourite; at three favourites it leaves the list unchanged.
    func toggleFavourite() -> FavouriteResult {
        guard let route else { return .toggled }
        if favourites.contains(route) {
            favourites.remove(route)
            return .toggled
        }
        return favourites.add(route) ? .toggled : .full
    }

    private func load() async {
        hasLoaded = true
        guard let route else { return }
        let day = selectedDay
        let isToday = day == today
        let trips = (try? await repository.trips(for: route, on: day)) ?? []
        let live = isToday ? (try? await repository.liveStatus(for: route, on: day)) ?? .empty : .empty
        // A newer day or route was picked while this one loaded.
        guard day == selectedDay, route == self.route else { return }
        now = clock.now
        let freshness = isToday ? Freshness(live, now: now) : .scheduledOnly
        departures = Departure.resolve(trips, live: live, freshness: freshness, isToday: isToday)
        self.freshness = freshness
        relayout()
    }

    private func relayout() {
        layout = TimelineLayout(TimelineInput(departures: departures, now: isToday ? now : nil, cardSizes: cardSizes))
        updateIsAtNow()
    }

    private func updateIsAtNow() {
        var value = false
        if isToday {
            let target = min(layout.initialScrollOffset, max(0, layout.height - viewportHeight))
            value = abs(scrollOffset - target) <= Self.atNowTolerance
        }
        if value != isAtNow { isAtNow = value }
    }
}

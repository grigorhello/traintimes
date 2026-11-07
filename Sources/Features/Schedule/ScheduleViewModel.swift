import CoreGraphics
import Foundation
import Observation

/// The Schedule screen (TT-112): route header, day strip, freshness row and the Now button, plus the departures and
/// layout the timeline draws (TT-113).
@Observable @MainActor
final class ScheduleViewModel {
    /// Today plus 13 days. Q6: the real horizon comes from the GTFS validity window in TT-130.
    static let dayCount = 14
    /// The Now button dims while the timeline sits within a minute of the present.
    static let atNowTolerance = TTTimeline.pointsPerMinute

    private(set) var route: Route?
    /// Kept in memory here; saved on device in TT-122.
    private(set) var isFavourite: Bool
    private(set) var selectedDay: ServiceDay
    private(set) var departures: [Departure] = []
    private(set) var layout = TimelineLayout()
    /// Nil until the first load.
    private(set) var freshness: Freshness?
    /// Bumped when the timeline should scroll: to Now on today, to the first train on another day.
    /// A refresh never bumps it, so pull to refresh keeps the scroll position.
    private(set) var scrollRequest = 0
    /// Reported by the view: the timeline's scroll offset and visible height.
    var scrollOffset: CGFloat = 0
    var viewportHeight: CGFloat = 0

    private let repository: any ScheduleRepository
    private let clock: any AppClock
    private var hasLoaded = false

    init(route: Route?, repository: any ScheduleRepository, clock: any AppClock, isFavourite: Bool = false) {
        self.route = route
        self.repository = repository
        self.clock = clock
        self.isFavourite = isFavourite
        selectedDay = ServiceDay(containing: clock.now)
    }

    var today: ServiceDay { ServiceDay(containing: clock.now) }
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

    /// True while today is selected and the timeline already shows the present: the Now button dims.
    var isAtNow: Bool {
        guard isToday else { return false }
        let target = min(layout.initialScrollOffset, max(0, layout.height - viewportHeight))
        return abs(scrollOffset - target) <= Self.atNowTolerance
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
        await load()
        scrollRequest += 1
    }

    /// The Now button: back to today and the present in one tap.
    func backToNow() async {
        if !isToday {
            selectedDay = today
            await load()
        }
        scrollRequest += 1
    }

    /// Swap is explicit, never automatic.
    func swap() async {
        guard let route else { return }
        self.route = Route(from: route.to, to: route.from, line: route.line)
        await load()
        scrollRequest += 1
    }

    func toggleFavourite() {
        isFavourite.toggle()
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
        let now = clock.now
        let freshness = isToday ? Freshness(live, now: now) : .scheduledOnly
        departures = Departure.resolve(trips, live: live, freshness: freshness, isToday: isToday)
        layout = TimelineLayout(TimelineInput(departures: departures, now: isToday ? now : nil))
        self.freshness = freshness
    }
}

import SwiftUI

/// Schedule tab (TT-112, D49): the line (code tile, name and a Notice chip) above the route card (D48; a tap on a station
/// opens the picker under the card, in place, D54), the day strip carousel, a status row only while loading, offline or
/// stale, the watched-trip strip once a watched train has left (TT-144), then the to-scale timeline with its rail and
/// cards (TT-113). The header is a top inset over one full-height scroll view, so the timeline scrolls under the glass
/// tab bar at the bottom (D49). There is no Now button: tapping the Schedule tab again scrolls back to Now. Motion (TT-164,
/// D61): the selected day's tile glides to a tapped day, which presses and springs back; a new set of trains cascades in;
/// the Now dot pulses on the way back to Now.
struct ScheduleView: View {
    @Environment(\.scenePhase) private var scenePhase
    let viewModel: ScheduleViewModel
    /// The stations the picker lists (TT-161).
    let stations: any StationRepository
    /// Tap a card: Trip details (TT-118).
    var onOpenTrip: (TripKey) -> Void = { _ in }
    /// The Notice chip: the notice sheet (TT-132).
    var onOpenLineNotice: () -> Void = {}
    /// The one-tap bells and their glass capsule (TT-141, TT-191); nil shows outlined bells that do nothing.
    var bells: AlertBellModel?
    /// The alert setup sheet (TT-142): a bell tapped before notifications are allowed.
    var onAlertSetup: (AlertSetupRequest) -> Void = { _ in }
    /// On board (TT-172): the ride strip under the day strip while a ride runs; nil shows none.
    var onBoard: OnBoard?
    /// A tap on the ride strip: Trip details in ride mode.
    var onOpenRide: () -> Void = {}
    /// A tap on the countdown strip before departure (TT-177): its Trip details. Nil opens the trip on the route shown.
    var onOpenDeparture: ((TripKey) -> Void)?

    /// The one formatter (D17), following the Time format setting (TT-105).
    @Environment(\.timeFormatter) private var formatter
    @Environment(\.openURL) private var openURL
    /// The strip's leftmost tile, as its id (0 is Today), for scrolling it to a tile that is out of view. Nil until the
    /// strip has scrolled; it opens on `openingTile`, at Today after the past week.
    @State private var stripPosition: Int?
    /// The station picker, made each time a station row is tapped; open while `isPickingStation` (TT-161, D54).
    @State private var picker: RouteFormViewModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsScheduleMotion) private var playsMotion
    /// When the cascade and the Now pulse started, read only by the views that move (TT-164, D61).
    @State private var motion: ScheduleMotionClock
    /// Taps on each day tile, by tile id: each one replays that tile's press.
    @State private var dayTaps: [Int: Int] = [:]
    /// When each day tile last pressed, by tile id.
    @State private var dayPressedAt: [Int: Date] = [:]

    /// `picker` opens Schedule with the picker already made, for previews and snapshots.
    init(
        viewModel: ScheduleViewModel,
        stations: any StationRepository,
        onOpenTrip: @escaping (TripKey) -> Void = { _ in },
        onOpenLineNotice: @escaping () -> Void = {},
        bells: AlertBellModel? = nil,
        onAlertSetup: @escaping (AlertSetupRequest) -> Void = { _ in },
        picker: RouteFormViewModel? = nil,
        onBoard: OnBoard? = nil,
        onOpenRide: @escaping () -> Void = {},
        onOpenDeparture: ((TripKey) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.stations = stations
        self.onOpenTrip = onOpenTrip
        self.onOpenLineNotice = onOpenLineNotice
        self.bells = bells
        self.onAlertSetup = onAlertSetup
        self.onBoard = onBoard
        self.onOpenRide = onOpenRide
        self.onOpenDeparture = onOpenDeparture
        _picker = State(initialValue: picker)
        // A screen made over trains that are already loaded shows them at rest: only a later request cascades.
        _motion = State(initialValue: ScheduleMotionClock(cascadeSeen: viewModel.entranceRequest))
    }
    /// The rider has dragged the timeline since the last scroll request, so the later scrolls to Now stay out of the way.
    @State private var riderScrolled = false
    /// The latest ask to scroll the timeline, carried out by `ScrollOffsetSetter`.
    @State private var scrollOrder = ScrollOrder()

    var body: some View {
        timeline
            .safeAreaInset(edge: .top, spacing: 0) { header }
            // The timeline moves with the strip under the day strip instead of jumping (TT-175), the countdown's too (TT-177).
            .rideStripMotion(onBoard, departs: viewModel.liveDeparture != nil || onBoard?.departureDemo != nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TTColor.canvas)
            // A tap outside the day panel closes it, and still reaches what it lands on (TT-191).
            .simultaneousGesture(TapGesture().onEnded { bells?.closePanel() }, including: isPanelOpen ? .all : .subviews)
            .overlay { pickerLayer.animation(PickerMotion.animation(opening: isPicking), value: isPicking) }
            .overlay(alignment: .bottom) { capsuleLayer }
            // A light haptic when an alert turns on (TT-141), the selection haptic when a day tile lights (TT-191).
            .sensoryFeedback(.impact(weight: .light), trigger: bells?.enabledCount ?? 0)
            .sensoryFeedback(.selection, trigger: bells?.dayOnCount ?? 0)
            .onDisappear { bells?.closePanel() }
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.loadIfNeeded() }
            .task { await viewModel.runClock() }
            // Live status every 30 s, and at once on coming back to the foreground (TT-131).
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await viewModel.pollLiveStatus()
            }
            .onChange(of: viewModel.entranceRequest) { startEntrance() }
            .onChange(of: viewModel.nowPulse) { startPulse() }
    }

    // MARK: Motion (TT-164, D61)

    /// The cards' cascade: pending (every card at its first pose, unseen) from the tap that asks for new trains until the
    /// start is taken, just after the frame that puts them on screen. The cards work it out from the clock themselves, so
    /// the start and the end redraw them alone.
    private var cascade: CascadeCue {
        CascadeCue(
            clock: motion, request: viewModel.entranceRequest, awaitsNewTrains: viewModel.awaitsNewTrains, plays: playsMotion
        )
    }

    /// The start is taken on the main actor's next turn, after the frame that draws the new cards: building that frame
    /// can take a moment, and a start taken before it would skip the cascade's first frames.
    private func startEntrance() {
        let request = viewModel.entranceRequest
        let motion = motion
        guard playsMotion else {
            motion.cascadeSeen = request
            return
        }
        Task { @MainActor in
            // A newer request takes its own start.
            guard request == viewModel.entranceRequest else { return }
            let start = Date()
            motion.cascadeSeen = request
            motion.cascadeStart = start
            try? await Task.sleep(for: .seconds(CascadeMotion.duration))
            if motion.cascadeStart == start { motion.cascadeStart = nil }
        }
    }

    /// Started on the next turn too, like the cascade, so its first frames are drawn.
    private func startPulse() {
        guard playsMotion, !reduceMotion else { return }
        let pulse = viewModel.nowPulse
        let motion = motion
        Task { @MainActor in
            guard pulse == viewModel.nowPulse else { return }
            let start = Date()
            motion.pulseStart = start
            try? await Task.sleep(for: .seconds(NowPulse.duration))
            if motion.pulseStart == start { motion.pulseStart = nil }
        }
    }

    /// Room for a slow frame after a day tap: the press's animation starts only after it.
    private static let slowFrameRoom = 0.3

    /// The tapped day presses (not under Reduce Motion), then the day is selected.
    private func tapDay(_ tile: StripTile) {
        // The selected tile's accent shape is drawn apart from it, so pressing it would shrink only its label. A tile still in
        // its last press, or in the slow frame before it, does not press again: two runs of its animation would add up.
        let pressedAt = dayPressedAt[tile.id] ?? .distantPast
        if playsMotion, !reduceMotion, tile.day != viewModel.selectedDay,
           Date().timeIntervalSince(pressedAt) > DayPressMotion.duration + Self.slowFrameRoom {
            dayPressedAt[tile.id] = Date()
            dayTaps[tile.id, default: 0] += 1
        }
        Task { await viewModel.select(tile.day) }
    }

    // MARK: Header

    /// Everything above the timeline, on a canvas background that also covers the status bar, with a 16 pt fade under it.
    private var header: some View {
        VStack(alignment: .leading, spacing: TTSpace.s3) {
            routeBlock(picking: picking)
                .padding(.horizontal, TTSpace.s5)
            // The day strip fades out under the veil while picking (it is not tappable) and back on close.
            dayStrip
                .opacity(isPicking ? 0 : 1)
                .allowsHitTesting(!isPicking)
                .animation(isPicking ? .easeOut(duration: 0.22) : .easeIn(duration: 0.20), value: isPicking)
            if let mode = viewModel.statusRowMode(formatter) {
                FreshnessLine(mode: mode)
                    .padding(.horizontal, TTSpace.s5)
                    .padding(.top, -TTSpace.s1)
            }
            // The ride strip takes the watched-trip strip's place while a ride runs (Live-Schedule). Its own view reads the
            // ride, so the ride's every-second changes redraw the strip alone.
            RideStripSlot(
                onBoard: onBoard, onOpen: onOpenRide, departure: viewModel.departureStrip(formatter),
                onOpenDeparture: { key in
                    if let onOpenDeparture { onOpenDeparture(key) } else { onOpenTrip(key) }
                }
            ) {
                if let strip = viewModel.watchedStrip(formatter) {
                    WatchedTripStripView(strip: strip, onOpen: { onOpenTrip(strip.id) }) {
                        withAnimation(.easeOut(duration: 0.2)) { viewModel.dismissWatchedStrip(strip.id) }
                    }
                    .id(strip.id)
                    .transition(.opacity)
                    .padding(.horizontal, TTSpace.s5)
                }
            }
        }
        .padding(.top, TTSpace.s3)
        .padding(.bottom, TTSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.canvas.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [TTColor.canvas, TTColor.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.edgeFade)
                .offset(y: Self.edgeFade)
                .allowsHitTesting(false)
        }
    }

    /// The canvas's `.edge-top`.
    private static let edgeFade: CGFloat = 16

    /// The line first, then the route card (D49, D48); tapping a station opens the picker for it (D54).
    private func routeBlock(picking: RouteCard.Picking?) -> some View {
        VStack(alignment: .leading, spacing: Self.lineRowGap) {
            lineRow
            RouteCard(
                from: viewModel.route?.from.name,
                to: viewModel.route?.to.name,
                fromID: "schedule.from",
                toID: "schedule.to",
                onTap: { openPicker($0) },
                picking: picking,
                swapID: "schedule.swap"
            ) {
                Task { await viewModel.swap() }
            }
        }
    }

    // MARK: Station picker

    /// A tap on a station row: the picker opens for that field, or moves to it while open.
    private func openPicker(_ stop: RouteCard.Stop) {
        let field: RouteFormViewModel.Field = stop == .from ? .from : .to
        if let picker, picker.isPickingStation {
            picker.open(field)
            return
        }
        let model = RouteFormViewModel(route: viewModel.route, repository: stations, recents: viewModel.recents)
        model.open(field)
        picker = model
        Task { await model.loadStations() }
    }

    /// The tapped row as the search field, with the current station as a grey hint, and the X in the swap button's place.
    private var picking: RouteCard.Picking? {
        guard let picker, picker.isPickingStation else { return nil }
        return RouteCard.Picking(
            stop: picker.pickingField == .from ? .from : .to,
            query: picker.query,
            current: picker.pickingStationName,
            cancelID: "schedule.cancel",
            onQuery: { picker.query = $0 },
            onSubmit: { if picker.pickFirstMatch() { apply(picker) } },
            onCancel: { picker.closeStations() }
        )
    }

    private var isPicking: Bool { picker?.isPickingStation ?? false }

    /// The list is revealed from the card's bottom edge, and the card squares off its bottom corners to meet it; the day
    /// strip and timeline recede under a frosted veil (no dark scrim). A tap on the veil, the X or a swipe down on the list
    /// cancels; a pick applies at once. The layer stays in place so that the veil and the list can play their exit.
    private var pickerLayer: some View {
        VStack(spacing: 0) {
            // An unseen copy of the line row and the card, as tall as they are in the header, so the veil and the list
            // start right under the card whatever the line row holds.
            routeBlock(picking: nil)
                .padding(.horizontal, TTSpace.s5)
                .padding(.top, TTSpace.s3)
                .hidden()
                .allowsHitTesting(false)
            ZStack(alignment: .top) {
                if let picker, picker.isPickingStation {
                    veil
                        .onTapGesture { picker.closeStations() }
                        .accessibilityHidden(true)
                        .transition(.pickerVeil)
                }
                // The panel is the only child of its own container, so the reveal measures the panel and nothing else.
                ZStack(alignment: .top) {
                    if let picker, picker.isPickingStation {
                        StationPickerPanel(
                            viewModel: picker,
                            onPick: { if picker.pick($0) { apply(picker) } },
                            onPickRoute: { route in
                                picker.choose(route)
                                Task { await viewModel.show(route) }
                            },
                            onCancel: { picker.closeStations() }
                        )
                        .transition(.pickerPanel(reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, TTSpace.s5)
            }
        }
        // Closed, the layer is only its hidden copy, and every touch goes through to the screen.
        .allowsHitTesting(isPicking)
    }

    /// The timeline and day strip behind the picker, frosted instead of dimmed (Grigor, 2026-11-10: the dark scrim looked
    /// wrong): `.regularMaterial` under the `Veil` tint. It starts at the card's bottom edge and takes the taps that cancel.
    private var veil: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(TTColor.veil)
            // The header above the card is plain canvas, so a veil that starts square at the card's bottom edge left a hard
            // tonal line in the side margins (light mode). Its first points fade back to canvas instead, as the approved
            // frame eases the tone. A colour gradient, not a mask: a mask drops the material (and the layer render's tint).
            .overlay(alignment: .top) {
                LinearGradient(colors: [TTColor.canvas, TTColor.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.veilRamp)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
    }

    /// How far the veil takes to reach full strength below the card's bottom edge.
    private static let veilRamp: CGFloat = 40

    /// A pick that completed the route: show it, which saves it and adds it to Recent.
    private func apply(_ picker: RouteFormViewModel) {
        Task {
            if let route = await picker.route() { await viewModel.show(route) }
        }
    }

    /// The GO line code tile and the line's name in 26 pt bold, with the amber Notice chip at the end of the row.
    @ViewBuilder private var lineRow: some View {
        if let line = viewModel.route?.line {
            HStack(spacing: Self.lineRowGap) {
                LineTile(line: line)
                Text(verbatim: line.name)
                    .font(TTFont.lineName)
                    .tracking(-0.6)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("schedule.line")
                Spacer(minLength: 0)
                if !viewModel.lineNotices.isEmpty {
                    noticeChip
                }
            }
            .frame(height: LineTile.size)
            .padding(.leading, 2)
        }
    }

    /// The canvas's 10 pt between the line row and the card, and between the tile and the name.
    private static let lineRowGap: CGFloat = 10

    /// "Notice" in amber: 30 pt tall, with a 44 pt target that takes only the chip's height in the row.
    private var noticeChip: some View {
        Button(action: onOpenLineNotice) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: TTSize.iconSM + 1, weight: .semibold))
                Text("schedule.notice_chip")
                    .font(TTFont.badgeLarge)
                    .tracking(-0.2)
            }
            .foregroundStyle(TTColor.delayInk)
            .padding(.leading, 10)
            .padding(.trailing, TTSpace.s3)
            .frame(height: 30)
            .background(TTColor.delayFill, in: Capsule())
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.vertical, -7)
        .fixedSize()
        .accessibilityLabel(Text("schedule.line_notice"))
        .accessibilityIdentifier("schedule.lineNotice")
    }

    // MARK: Day strip

    /// A swipeable row of 60 × 48 pt tiles: the previous 7 days, Today and every day of the schedule after it (D49, D53). It
    /// opens with Today first, so the past week is a swipe to the right. It bleeds to both screen edges under a 16 pt fade,
    /// so half of the sixth tile peeks, and snaps tile by tile. A tile's id is its place counted from Today: 0 is Today, -1
    /// yesterday.
    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: TTSpace.s2) {
                ForEach(stripTiles) { tile in
                    DayCell(
                        weekday: tile.id == 0 ? String(localized: "button.today") : tile.day.weekdayShort,
                        day: "\(tile.day.day)",
                        isSelected: tile.day == viewModel.selectedDay,
                        isToday: tile.id == 0,
                        drawsSelection: false
                    ) {
                        tapDay(tile)
                    }
                    .accessibilityIdentifier("schedule.day.\(tile.id)")
                    .dayPress(dayTaps[tile.id, default: 0], animated: playsMotion && !reduceMotion)
                }
            }
            .scrollTargetLayout()
            .background(alignment: .leading) { selectionTile }
            // Room for the tile shadow inside the clipped strip.
            .padding(.vertical, Self.shadowRoom)
        }
        .contentMargins(.horizontal, TTSpace.s5, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: stripBinding)
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.edgeFade)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.edgeFade)
            }
        }
        // "Show Monday" and picking another day bring an out-of-view tile to the start; Today brings the strip back.
        .onChange(of: viewModel.selectedDay) { showSelectedDay() }
        // Tapping the Schedule tab again returns to Today and Now: the strip comes back to Today too, though Today was selected.
        .onChange(of: viewModel.scrollRequest) {
            guard viewModel.isToday, let first = stripPosition, first != 0 else { return }
            withAnimation(.easeOut(duration: 0.3)) { stripPosition = 0 }
        }
        .frame(height: DayCell.size.height + 2 * Self.shadowRoom)
        .padding(.vertical, -Self.shadowRoom)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    /// A strip tile. Its id is the one the strip's scroll position and the UI identifier use, counted from Today, so the
    /// `ForEach` identity and the position agree (D53).
    private struct StripTile: Identifiable {
        let id: Int
        let day: ServiceDay
    }

    private var stripTiles: [StripTile] {
        viewModel.stripDays.enumerated().map { StripTile(id: $0.offset - ScheduleViewModel.pastDayCount, day: $0.element) }
    }

    /// The scroll position, reading `openingTile` until the strip has scrolled, so it opens there on its first layout.
    private var stripBinding: Binding<Int?> {
        Binding(get: { stripPosition ?? openingTile }, set: { stripPosition = $0 })
    }

    /// The tile the strip opens on: Today (0), or the selected day when that is not one of the first five tiles from Today.
    private var openingTile: Int {
        let selected = viewModel.stripIndex(of: viewModel.selectedDay) ?? 0
        return (0..<Self.fullTiles).contains(selected) ? 0 : selected
    }

    /// Brings the selected day's tile to the start of the strip when it is not among the five whole tiles. Before the strip
    /// has scrolled, the binding's `openingTile` does it.
    private func showSelectedDay() {
        let index = viewModel.stripIndex(of: viewModel.selectedDay) ?? 0
        guard let first = stripPosition, index < first || index >= first + Self.fullTiles else { return }
        withAnimation(.easeOut(duration: 0.3)) { stripPosition = index }
    }

    private static let shadowRoom: CGFloat = 2
    /// Tiles that show whole at the start of the strip.
    private static let fullTiles = 5

    /// The selected day's accent tile, one shape under the tiles (which leave the selected one see-through), so that it
    /// glides from the old day to the new one on `TTMotion.glide`, passing under the days between, as on the board. Placed by
    /// the tile's index: the lazy strip may not have built the old day's tile to match a geometry to. It glides only when
    /// the rider picks a day (`daySelection`), so the strip shifting at midnight moves it with the tiles. Reduce Motion: it
    /// jumps.
    @ViewBuilder private var selectionTile: some View {
        if let index = viewModel.stripIndex(of: viewModel.selectedDay) {
            RoundedRectangle(cornerRadius: TTRadius.md)
                .fill(TTColor.accent)
                .frame(width: DayCell.size.width, height: DayCell.size.height)
                .offset(x: CGFloat(index + ScheduleViewModel.pastDayCount) * (DayCell.size.width + TTSpace.s2))
                .animation(playsMotion && !reduceMotion ? TTMotion.glide : nil, value: viewModel.daySelection)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Timeline

    /// The to-scale timeline (TT-111 layout, TT-113 drawing), its loading skeleton, or an empty state card (TT-115).
    /// One scroll view holds them all, so a scroll request still lands when the content changes with it. It scrolls under
    /// the tab bar, with the bottom edge softened by the system on iOS 26 and later.
    private var timeline: some View {
        ScrollView {
            Group {
                switch viewModel.content {
                case .loading:
                    ScheduleLoadingTimeline(now: viewModel.now, formatter: formatter)
                case .timeline:
                    ScheduleTimeline(
                        viewModel: viewModel, formatter: formatter, onOpen: onOpenTrip, bell: bell(for:), onBell: tapBell(_:),
                        cascade: cascade, motion: motion
                    )
                    .background(
                        ScrollOffsetSetter(offset: viewModel.isToday ? viewModel.layout.initialScrollOffset : 0, order: scrollOrder)
                    )
                // The empty states only fade in with a new set of trains, never cascade.
                case .noTrains(let title, let message, let showDay):
                    noTrains(title: title, message: message, showDay: showDay)
                        .cascadeEntrance(cascade, order: 0, moves: false)
                case .noConnection:
                    noConnection
                        .cascadeEntrance(cascade, order: 0, moves: false)
                }
            }
        }
        .softBottomEdge()
        .refreshable { await viewModel.refresh() }
        .onChange(of: viewModel.scrollRequest) { previous, _ in
            riderScrolled = false
            scroll(animated: previous != 0 && !viewModel.scrollJumps)
        }
        // The cards are measured after the first scroll, which moves Now: scroll again (D49).
        .onChange(of: viewModel.settleRequest) {
            settle()
        }
        // And again a moment after the request, when the content was not laid out yet at the first scroll (D52).
        .onChange(of: viewModel.rescrollRequest) {
            settle()
        }
        .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in
            if !riderScrolled { riderScrolled = true }
            // A scroll closes the day panel (TT-191).
            if isPanelOpen { bells?.closePanel() }
        })
        .accessibilityIdentifier("schedule.timeline")
    }

    /// Today shows Now near the top, another day its first train: `ScrollOffsetSetter` moves the scroll view there.
    private func scroll(animated: Bool) {
        scrollOrder = ScrollOrder(token: scrollOrder.token + 1, animated: animated)
    }

    /// A scroll to the present again, unless the rider has taken over the scrolling. Without animation on the first request
    /// (the launch) and after a jump to new trains (TT-164: the cards cascade in where they land); later ones animate, as
    /// the request did, so the second scroll only steers the first.
    private func settle() {
        guard !riderScrolled else { return }
        scroll(animated: viewModel.scrollRequest > 1 && !viewModel.scrollJumps)
    }

    // MARK: Alerts

    private func train(_ id: TripKey) -> (trip: Trip, route: Route)? {
        guard let route = viewModel.route, let departure = viewModel.departures.first(where: { $0.id == id }) else { return nil }
        return (departure.trip, route)
    }

    private func bell(for id: TripKey) -> AlertBellModel.Bell {
        guard let bells, let train = train(id) else { return .off }
        return bells.bell(for: train.trip, on: train.route)
    }

    private func tapBell(_ id: TripKey) {
        guard let train = train(id) else { return }
        tapBell(train.trip, on: train.route)
    }

    private func tapBell(_ trip: Trip, on route: Route) {
        guard let bells else { return }
        Task {
            if let request = await bells.tap(trip, on: route) { onAlertSetup(request) }
        }
    }

    private var isPanelOpen: Bool { bells?.capsule?.isPanelOpen ?? false }

    /// The glass capsule 12 pt above the tab bar (TT-191, D71): "Alert on · 7:32 AM" with Repeat, which grows it into the
    /// day panel; "Alert off · 7:32 AM" with Undo; "Couldn't …" with Try again; "Tap the bell on a train" after the Alerts
    /// tab's "Add alert". The timeline fades under it. One at a time (`GlassCapsuleStage`).
    @ViewBuilder private var capsuleLayer: some View {
        if let bells {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    CapsuleVeil(isShown: bells.capsule != nil, isTall: bells.capsule?.isPanelOpen ?? false)
                        // From the screen's bottom edge, under the tab bar.
                        .offset(y: proxy.safeAreaInsets.bottom)
                    GlassCapsuleStage(item: bells.capsule, isPanel: { $0.isPanelOpen }) { capsule in
                        alertCapsule(capsule, bells: bells, panelWidth: proxy.size.width - 2 * TTSpace.s5)
                    }
                    .padding(.bottom, TTSpace.s3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func alertCapsule(_ capsule: AlertBellModel.Capsule, bells: AlertBellModel, panelWidth: CGFloat) -> some View {
        AlertCapsuleView(
            glyph: Self.glyph(capsule.kind),
            words: capsule.words(formatter, today: viewModel.today),
            action: capsule.actionKey.map { key in
                AlertCapsuleView.Action(title: LocalizedStringKey(key)) { act(on: capsule, bells: bells) }
            },
            panel: capsule.panelDays.map { days in
                AlertCapsuleView.Panel(
                    words: capsule.panelWords(formatter, today: viewModel.today),
                    days: days,
                    onToggle: { bells.toggleDay($0) },
                    onDone: { bells.closePanel() }
                )
            },
            panelWidth: panelWidth,
            reservesPanelSpace: true
        )
        // A finger on the capsule holds it.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in bells.holdCapsule(true) }
                .onEnded { _ in bells.holdCapsule(false) }
        )
    }

    /// Repeat, Undo, Try again or Turn on.
    private func act(on capsule: AlertBellModel.Capsule, bells: AlertBellModel) {
        switch capsule.kind {
        case .on:
            bells.repeatTapped()
        case .off:
            Task { await bells.undo() }
        case .failed:
            Task {
                if let request = await bells.tryAgain() { onAlertSetup(request) }
            }
        case .notificationsOff:
            bells.dismissCapsule()
            openURL(AlertSetupViewModel.notificationSettingsURL)
        case .notificationsOn, .hint:
            break
        }
    }

    /// Each capsule's glyph: the filled bell, the outline, the exclamation mark or the crossed bell.
    static func glyph(_ kind: AlertBellModel.Capsule.Kind) -> CapsuleGlyph {
        switch kind {
        case .on: .bellOn
        case .off, .hint: .bellOff
        case .failed: .failed
        case .notificationsOff: .notificationsOff
        case .notificationsOn: .confirmed
        }
    }

    // MARK: Empty states

    /// "No direct trains on Sunday" with "Show Monday", and the trip planner footnote (`schedule-no-trains.png`).
    private func noTrains(title: String, message: String, showDay: String?) -> some View {
        VStack(spacing: TTSpace.s3) {
            EmptyStateCard(
                systemImage: "calendar",
                title: Text(verbatim: title),
                message: Text(verbatim: message),
                actionTitle: showDay.map { Text(verbatim: $0) }
            ) {
                Task { await viewModel.showNextDayWithTrains() }
            }
            Text("schedule.no_trains.footnote")
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TTSpace.s3)
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, TTSpace.s6)
    }

    /// "No direct connection" with "Open GO trip planner" (`components.png`).
    private var noConnection: some View {
        EmptyStateCard(
            systemImage: "exclamationmark.triangle",
            title: "schedule.no_connection.title",
            message: "schedule.no_connection.body",
            actionTitle: "schedule.no_connection.action"
        ) {
            openURL(ScheduleViewModel.tripPlannerURL)
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, TTSpace.s3)
    }
}

#Preview {
    NavigationStack {
        ScheduleView(viewModel: .fixtures(), stations: ScheduleDependencies.fixtures().stations)
    }
}

extension View {
    /// The system's soft fade where content scrolls under the floating tab bar (iOS 26 and later, D49).
    @ViewBuilder fileprivate func softBottomEdge() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
    }
}

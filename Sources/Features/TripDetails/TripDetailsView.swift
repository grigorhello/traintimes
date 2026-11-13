import SwiftUI

/// Trip details sheet (TT-118, redesigned in TT-163 after design/frames/trip-details*.png): on the canvas ground, a pinned
/// header (line tile, line name, glass close button), the journey card, the stop list on one rail, and the alert bar
/// floating over the content (TT-192: "Alert me" turns the alert on in place, the sheet stays). Everything scrolls; the
/// content ends above the bar.
struct TripDetailsView: View {
    let viewModel: TripDetailsViewModel
    /// Snapshots only: a long trip scrolled to its end, as the canvas's Trip-Details-End frame.
    var startsAtEnd = false

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// The permission sheet before the first ride's iOS prompt (TT-172).
    @State private var showsIntro = false
    @State private var tick = 0
    /// The ride card as End ride or Done left it: it stays while the sheet closes, so the journey or departure card does
    /// not show through for the length of the dismissal (TT-177).
    @State private var closingRide: RideDetails?
    /// The staged entrance has played: content that appears later (the departure card taking the journey card's place
    /// once "Alert me" alerts a train in its window, TT-192) cross-fades in at rest instead of arriving again.
    @State private var entranceSettled = false

    // Canvas geometry (TT-163). Rows: station 56, meta 28, status 44, stop 44.
    /// 15 pt under the 15 pt the grabber takes from the sheet's top edge.
    private static let headerTop: CGFloat = 30
    private static let headerHeight: CGFloat = 44
    private static let lineGap: CGFloat = 10
    private static let stationRow: CGFloat = 56
    private static let metaRow: CGFloat = 28
    private static let statusRow: CGFloat = 44
    private static let stopRow: CGFloat = 44
    private static let markerColumn: CGFloat = 20
    private static let railWidth: CGFloat = 2
    private static let stopDot: CGFloat = 8
    private static let dotHalo: CGFloat = 2
    private static let skippedGlyph: CGFloat = 14
    private static let alertHeight: CGFloat = 52
    /// With the Directions link (TT-188): the ring sits on the name line, 12 pt from the row's top, and the time 4 pt down.
    private static let directionsRingTop: CGFloat = 12
    private static let directionsTimeTop: CGFloat = 4
    private static let directionsGlyph: CGFloat = 15
    private static let directionsGap: CGFloat = 5
    /// 16 + the 52 pt button + 24 pt above the sheet's bottom edge; 40 pt when there is no button.
    private static let bottomInsetWithButton: CGFloat = 92
    private static let bottomInset: CGFloat = 40
    private static let buttonBottom: CGFloat = 24
    /// The capsule and the day panel sit 10 pt above the bar (TT-192).
    private static let capsuleGap: CGFloat = 10
    private static let topFade: CGFloat = 16
    private static let bottomFade: CGFloat = 112
    private static let bottomFadeOpacity = 0.72

    var body: some View {
        // The ride's countdowns and the train on the rail follow the clock, as does the countdown before departure: the sheet
        // is drawn again each second while riding or live (TT-177).
        let _ = tick
        let ride = closingRide ?? viewModel.rideDetails(formatter)
        let details = viewModel.details(formatter)
        let departure = ride == nil ? viewModel.departureDetails(formatter) : nil
        let showsOnBoard = ride == nil && viewModel.showsOnBoardButton
        let hasButton = ride != nil || showsOnBoard || details?.alertButton != nil
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Above the scroll view, so the close button's glass shadow is not cut off by the top fade (a hard edge in light).
                header(isRiding: ride != nil)
                    .zIndex(1)
                ScrollView {
                    Group {
                        if let ride {
                            RideContent(ride: ride, risesIn: !viewModel.ridesInPlace)
                        } else if let departure, let details {
                            departureContent(departure, details: details)
                        } else if let details {
                            content(details, hint: showsOnBoard ? viewModel.onBoardHint : nil)
                        }
                    }
                    .environment(\.stagedEntranceSettled, entranceSettled)
                    .animation(TTMotion.fade, value: departure == nil)
                    .padding(.horizontal, TTSpace.s5)
                    .padding(.top, TTSpace.s4)
                    .padding(.bottom, hasButton ? Self.bottomInsetWithButton : Self.bottomInset)
                }
                .defaultScrollAnchor(startsAtEnd ? UnitPoint.bottom : nil)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [TTColor.canvas, TTColor.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.topFade)
                        .allowsHitTesting(false)
                }
            }
            if let ride {
                bottomFade
                rideButton(ride)
            } else if showsOnBoard {
                bottomFade
                capsuleLayer
                onBoardButtons(alert: details?.alertButton)
            } else if details?.alertButton != nil {
                bottomFade
                capsuleLayer
                alertBar
            }
        }
        // The sheet's bottom edge is the screen's: the button sits 24 pt above it, over the home indicator's area.
        .ignoresSafeArea(.container, edges: .bottom)
        .background(TTColor.canvas)
        .task { await viewModel.run() }
        .task {
            // The longest beat (the last stop row) is still by about 0.7 s.
            try? await Task.sleep(for: .seconds(1))
            entranceSettled = true
        }
        // The bell's haptics, as on Schedule (TT-191): a light tap when an alert turns on, the warning on a refusal, the
        // selection tick when a day lights.
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.bells?.enabledCount ?? 0)
        .sensoryFeedback(.warning, trigger: viewModel.bells?.refusedCount ?? 0)
        .sensoryFeedback(.selection, trigger: viewModel.bells?.dayOnCount ?? 0)
        // Back from the capsule's Turn on with notifications on, the alert turns on (D72).
        .task(id: scenePhase) {
            guard scenePhase == .active, let bells = viewModel.bells else { return }
            await bells.cameBack()
        }
        .task(id: viewModel.followsClock) {
            while viewModel.followsClock, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                viewModel.tick()
                tick &+= 1
            }
        }
        .sheet(isPresented: $showsIntro) {
            RideIntroSheet(
                destination: viewModel.destinationName,
                onContinue: {
                    showsIntro = false
                    Task { await viewModel.startRide() }
                },
                onNotNow: { showsIntro = false }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ride?.title ?? details?.title ?? "")
        .accessibilityIdentifier("sheet.tripDetails")
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TTRadius.sheet)
        .presentationBackground(TTColor.canvas)
    }

    // MARK: Header

    /// The line tile and its name in the Schedule header's style, and the glass close button flush with the margin.
    /// In ride mode (TT-204 review) the line name drops to 17 pt, so the state is the loudest line, and the close button is
    /// a chevron: it lowers the sheet and the ride goes on.
    private func header(isRiding: Bool) -> some View {
        HStack(spacing: Self.lineGap) {
            if let line = viewModel.route.line {
                LineTile(line: line)
                Text(verbatim: line.name)
                    .font(isRiding ? TTFont.headline : TTFont.lineName)
                    .tracking(isRiding ? -0.4 : -0.6)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("trip.title")
            }
            Spacer(minLength: 0)
            GlassIconButton(systemName: isRiding ? "chevron.down" : "xmark", label: "button.close", tint: TTColor.ink) {
                dismiss()
            }
                .accessibilityIdentifier("trip.close")
        }
        .frame(height: Self.headerHeight)
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, Self.headerTop)
    }

    private func content(_ details: TripDetails, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            journey(details)
            stops(details, hint: hint)
                .padding(.top, TTSpace.s5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A live time or status that changes later cross-fades; nothing bounces (TT-167).
        .contentTransition(.opacity)
        .animation(TTMotion.fade, value: details)
    }

    // MARK: Before departure (TT-177)

    /// *Live-Depart-Trip*: the departure card in the journey card's place; the stop list as it was, with the window's
    /// footnote.
    private func departureContent(_ departure: DepartureDetails, details: TripDetails) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LiveDepartureCard(
                departure: departure,
                onDirections: viewModel.directionsStation != nil ? { viewModel.openDirections() } : nil
            )
            // The card arrives first, as the journey card does (TT-167, D65).
            .stagedEntrance(rise: 12, on: TTMotion.card)
            stops(details, hint: departure.footnote)
                .padding(.top, TTSpace.s5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Journey card

    /// Two stations with their times, the meta row between them, then the status row under a hairline.
    private func journey(_ details: TripDetails) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: TTSpace.s3) {
                journeyMarkers(ringOnNameLine: details.showsDirections)
                VStack(spacing: 0) {
                    if details.showsDirections {
                        directionsRow(details.origin, time: details.departure)
                    } else {
                        stationRow(details.origin, time: details.departure, isStruck: details.isCancelled)
                    }
                    metaRow(details)
                    stationRow(details.destination, time: details.arrival, isStruck: details.isCancelled)
                }
            }
            .padding(.top, 6)
            Divider().overlay(TTColor.hairline)
            HStack(spacing: TTSpace.s2) {
                StatusLine(status: details.status)
                Spacer(minLength: 0)
                if let text = details.freshnessText {
                    Text(text)
                        .font(TTFont.footnote)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(height: Self.statusRow)
        }
        .padding(.horizontal, TTSpace.s4)
        .ttSheetCard()
        // The staged entrance (TT-167, D65): the card first, riding 12 pt down into place as the sheet's content arrives.
        .stagedEntrance(rise: 12, on: TTMotion.card)
    }

    /// The ring centred on the first row (on its name line when the Directions link is under the name), the three dots
    /// beside the meta row, the pin centred on the second row.
    private func journeyMarkers(ringOnNameLine: Bool) -> some View {
        let size = RouteMarkers.Size.regular
        return VStack(spacing: 0) {
            Circle()
                .strokeBorder(TTColor.inkSecondary, lineWidth: size.ringStroke)
                .frame(width: size.ring, height: size.ring)
                .padding(.top, ringOnNameLine ? Self.directionsRingTop : 0)
                .frame(height: Self.stationRow, alignment: ringOnNameLine ? .top : .center)
            VStack(spacing: size.gap) {
                ForEach(0..<size.dots, id: \.self) { _ in
                    Circle().fill(TTColor.inkTertiary).frame(width: size.dot, height: size.dot)
                }
            }
            .frame(height: Self.metaRow)
            RoutePin()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: size.pin, height: size.pin)
                .frame(height: Self.stationRow)
        }
        .frame(width: Self.markerColumn)
        .accessibilityHidden(true)
    }

    private func stationRow(_ name: String, time: TripDetails.Time, isStruck: Bool) -> some View {
        HStack(spacing: TTSpace.s2) {
            stationName(name)
            Spacer(minLength: 0)
            timeStack(time, isStruck: isStruck)
        }
        .frame(height: Self.stationRow)
    }

    /// The departure row with the Directions link under the name (TT-188, D64): the name and the link are one button the
    /// full height of the row's left side, and the time lines up with the name.
    private func directionsRow(_ name: String, time: TripDetails.Time) -> some View {
        HStack(alignment: .top, spacing: TTSpace.s2) {
            Button { viewModel.openDirections() } label: {
                VStack(alignment: .leading, spacing: 0) {
                    stationName(name)
                    HStack(spacing: Self.directionsGap) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: Self.directionsGlyph, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("button.directions")
                            .font(TTFont.subhead.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(TTColor.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(DimOnPressStyle())
            .accessibilityIdentifier("trip.directions")
            timeStack(time, isStruck: false)
                .padding(.top, Self.directionsTimeTop)
        }
        .frame(height: Self.stationRow)
    }

    private func stationName(_ name: String) -> some View {
        Text(verbatim: name)
            .font(TTFont.headline)
            .foregroundStyle(TTColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// The time, with the struck scheduled time under it when the train runs late.
    private func timeStack(_ time: TripDetails.Time, isStruck: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(time.value)
                .font(TTFont.route)
                .monospacedDigit()
                .strikethrough(isStruck)
                .foregroundStyle(isStruck ? TTColor.inkTertiary : time.isLate ? TTColor.delayInk : TTColor.ink)
            if let scheduled = time.scheduled {
                Text(scheduled)
                    .font(TTFont.footnote)
                    .monospacedDigit()
                    .strikethrough()
                    .foregroundStyle(TTColor.inkTertiary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// "Platform [2] · in 11 min · Express" on the left (the platform first, Grigor, TT-199), the trip length on the right.
    private func metaRow(_ details: TripDetails) -> some View {
        HStack(spacing: TTSpace.s2) {
            HStack(spacing: TTSpace.s1 + 2) {
                PlatformTag(number: details.hasPlatform ? details.platformValue : nil, size: 15)
                if let countdown = details.countdown {
                    separator
                    Text(countdown)
                        .font(TTFont.subhead.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                }
                if details.isExpress {
                    separator
                    HStack(spacing: TTSpace.s1) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: TTSize.iconSM, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("tag.express")
                            .font(TTFont.subhead.weight(.semibold))
                    }
                    .foregroundStyle(details.isCancelled ? TTColor.inkTertiary : TTColor.accent)
                }
            }
            // A long run of facts (a three-digit countdown, a platform, Express) shrinks before it clips or pushes the trip length.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(details.tripLength)
                .font(TTFont.footnote)
                .monospacedDigit()
                .foregroundStyle(TTColor.inkSecondary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
        .frame(height: Self.metaRow)
    }

    /// A separator glyph, not copy.
    private var separator: some View {
        Text(verbatim: "·")
            .font(TTFont.subhead)
            .foregroundStyle(TTColor.inkTertiary)
    }

    // MARK: Stops

    /// `hint` takes the footnote's place while "I'm on board" shows (TT-172).
    private func stops(_ details: TripDetails, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(details.stopCount).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(details.stopsHeader)
            }
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, TTSpace.s1)

            VStack(spacing: 0) {
                ForEach(Array(details.stops.enumerated()), id: \.element.id) { index, stop in
                    stopRow(stop, isFirst: index == 0, isStruck: details.isTrainCancelled)
                        .stagedEntrance(rise: 10, on: TTMotion.stops, delay: TTMotion.stopDelay(index))
                }
            }
            .background(alignment: .topLeading) { rail(stops: details.stops.count) }
            .padding(.horizontal, TTSpace.s4)
            .padding(.vertical, 6)
            .ttSheetCard()
            .padding(.top, 6)

            Text(hint ?? details.footnote)
                .font(TTFont.footnote)
                .monospacedDigit()
                .foregroundStyle(TTColor.inkSecondary)
                .padding(.horizontal, TTSpace.s1)
                .padding(.top, 10)
        }
        // The list's card, rail and words fade in with the journey card while the rows ripple in (TT-167).
        .stagedEntrance()
    }

    /// The 2 pt rail from just under the origin ring to just above the destination pin's head, down the marker column.
    private func rail(stops count: Int) -> some View {
        let ring = RouteMarkers.Size.regular.ring
        let length = max(0, Self.stopRow * CGFloat(count - 1) - ring / 2 - 10)
        return Rectangle()
            .fill(TTColor.controlBorder.opacity(0.38))
            .frame(width: Self.railWidth, height: length)
            .offset(x: Self.markerColumn / 2 - Self.railWidth / 2, y: Self.stopRow / 2 + ring / 2)
            .accessibilityHidden(true)
    }

    private func stopRow(_ stop: TripDetails.Stop, isFirst: Bool, isStruck: Bool) -> some View {
        let isDimmed = stop.isSkipped || isStruck
        let font = stop.isEnd ? TTFont.headline : TTFont.body
        return HStack(spacing: TTSpace.s3) {
            stopMarker(stop, isFirst: isFirst)
                .frame(width: Self.markerColumn, height: Self.stopRow)
            Text(verbatim: stop.name)
                .font(font)
                .foregroundStyle(stop.isSkipped ? TTColor.inkTertiary : TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: TTSpace.s2)
            Text(stop.time)
                .font(font)
                .monospacedDigit()
                .strikethrough(isDimmed)
                .foregroundStyle(isDimmed ? TTColor.inkTertiary : TTColor.ink)
        }
        .frame(height: Self.stopRow)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip.stop.\(stop.id)")
    }

    /// The origin ring, a dot with a surface halo over the rail, the destination pin; a skipped stop is a cross on a disc.
    @ViewBuilder private func stopMarker(_ stop: TripDetails.Stop, isFirst: Bool) -> some View {
        let size = RouteMarkers.Size.regular
        if stop.isSkipped {
            Image(systemName: "xmark")
                .font(.system(size: Self.skippedGlyph, weight: .semibold))
                .foregroundStyle(TTColor.cancelInk)
                .frame(width: Self.markerColumn, height: Self.markerColumn)
                .background(TTColor.surface, in: Circle())
                .accessibilityLabel(Text("status.stop_skipped"))
        } else if stop.isEnd && isFirst {
            Circle()
                .strokeBorder(TTColor.inkSecondary, lineWidth: size.ringStroke)
                .frame(width: size.ring, height: size.ring)
                .background(TTColor.surface, in: Circle())
        } else if stop.isEnd {
            RoutePin()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: size.pin, height: size.pin)
        } else {
            Circle()
                .fill(TTColor.controlBorder)
                .frame(width: Self.stopDot, height: Self.stopDot)
                .padding(Self.dotHalo)
                .background(TTColor.surface, in: Circle())
        }
    }

    // MARK: Alert button

    /// The canvas's `.edge-bottom`: the content fades into the ground under the button, as under the tab bar.
    private var bottomFade: some View {
        LinearGradient(
            colors: [TTColor.canvas.opacity(0), TTColor.canvas.opacity(Self.bottomFadeOpacity)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: Self.bottomFade)
        .allowsHitTesting(false)
    }

    /// "Alert me", or "Alert on" with Repeat beside it (TT-192, D77): the sheet never closes.
    private var alertBar: some View {
        TripAlertBar(
            face: viewModel.bell,
            shakes: viewModel.bellShakes,
            repeatTitle: viewModel.repeatTitle,
            repeats: !viewModel.repeatDays.isEmpty,
            isPanelOpen: viewModel.capsule?.isPanelOpen ?? false,
            onAlert: { Task { await viewModel.tapAlert() } },
            onRepeat: { viewModel.tapRepeat() }
        )
        // Last, from 120 ms: it grows from 0.9 as it fades in (TT-167).
        .stagedEntrance(scale: 0.9, on: TTMotion.grow, delay: TTMotion.buttonDelay)
        .padding(.horizontal, TTSpace.s5)
        .padding(.bottom, Self.buttonBottom)
    }

    // MARK: Capsule (TT-192)

    /// What the bar cannot say, in D71's glass capsule 10 pt above it: "Notifications are off · Turn on", "Couldn't …
    /// · Try again", and the day panel Repeat opens, the bar's width. The content fades under it; a tap or a drag outside
    /// the panel closes it.
    @ViewBuilder private var capsuleLayer: some View {
        if let bells = viewModel.bells {
            let capsule = viewModel.capsule
            let isPanelOpen = capsule?.isPanelOpen ?? false
            ZStack(alignment: .bottom) {
                if isPanelOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { bells.closePanel() }
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in bells.closePanel() })
                }
                CapsuleVeil(isShown: capsule != nil, isTall: isPanelOpen)
                GeometryReader { proxy in
                    GlassCapsuleStage(item: capsule, isPanel: { $0.isPanelOpen }) { capsule in
                        sheetCapsule(capsule, bells: bells, panelWidth: proxy.size.width - 2 * TTSpace.s5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .padding(.bottom, Self.buttonBottom + Self.alertHeight + Self.capsuleGap)
            }
        }
    }

    private func sheetCapsule(_ capsule: AlertBellModel.Capsule, bells: AlertBellModel, panelWidth: CGFloat) -> some View {
        let today = ServiceDay(calendarDayContaining: viewModel.now)
        return AlertCapsuleView(
            glyph: capsule.kind.glyph,
            words: capsule.words(formatter, today: today),
            action: capsule.actionKey.map { key in
                AlertCapsuleView.Action(title: LocalizedStringKey(key)) {
                    switch capsule.kind {
                    case .failed:
                        Task { await bells.tryAgain() }
                    case .notificationsOff:
                        bells.turnOnInSettings()
                        openURL(AlertBellModel.notificationSettingsURL)
                    case .on, .off, .notificationsOn, .newTrain:
                        break
                    }
                }
            },
            panel: capsule.panelDays.map { days in
                AlertCapsuleView.Panel(
                    words: capsule.panelWords(formatter, today: today),
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

    // MARK: On board (TT-172)

    /// *Live-Entry*: the alert button turns into a 52 pt glass bell beside "I'm on board"; the bell alone goes once the
    /// train has left (no alert then), and "I'm on board" fills the row.
    private func onBoardButtons(alert: String?) -> some View {
        HStack(spacing: 10) {
            if let alert {
                // A tap turns the alert on or off in place, with the card's pop (TT-192); filled while it is on.
                AlertBellButton(
                    face: viewModel.bell, shakes: viewModel.bellShakes, label: Text(verbatim: alert), glyph: 22,
                    target: Self.alertHeight, weight: .semibold, tint: TTColor.accent
                ) {
                    Task { await viewModel.tapAlert() }
                }
                .ttGlass(in: Circle())
                .accessibilityIdentifier("trip.alert")
            }
            Button {
                if viewModel.needsLocationIntro {
                    showsIntro = true
                } else {
                    Task { await viewModel.startRide() }
                }
            } label: {
                Text("onboard.button")
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.alertHeight)
                    .ttGlass(tint: TTColor.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("trip.onboard")
        }
        // Arrives like the alert button it stands in for (TT-167).
        .stagedEntrance(scale: 0.9, on: TTMotion.grow, delay: TTMotion.buttonDelay)
        .padding(.horizontal, TTSpace.s5)
        .padding(.bottom, Self.buttonBottom)
    }

    /// End ride as plain ink-secondary text, so a stray thumb on a moving train does not reach for it (TT-204 review); Done
    /// at your stop, a filled accent capsule. Either one ends the ride and closes the sheet.
    private func rideButton(_ ride: RideDetails) -> some View {
        Button {
            closingRide = ride
            viewModel.endRide()
            dismiss()
        } label: {
            let title = Text(ride.button)
                .font(TTFont.headline)
                .foregroundStyle(ride.isComplete ? TTColor.onAccent : TTColor.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.alertHeight)
            if ride.isComplete {
                title.ttGlass(tint: TTColor.accent, in: Capsule())
            } else {
                title
            }
        }
        .contentShape(Capsule())
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("trip.endRide")
        .padding(.horizontal, TTSpace.s5)
        .padding(.bottom, Self.buttonBottom)
    }
}

/// The Directions link dims while pressed, as the canvas's link does.
private struct DimOnPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.45 : 1)
    }
}

#Preview {
    Text(verbatim: "")
        .sheet(isPresented: .constant(true)) {
            if let repository = try? FixtureScheduleRepository(scenario: .delayed) {
                TripDetailsView(
                    viewModel: TripDetailsViewModel(
                        route: repository.route,
                        key: TripKey(serviceDay: repository.serviceDay, tripId: "LW-0732-20261105"),
                        repository: repository,
                        clock: FixedClock(now: repository.now),
                        hasAlert: true
                    )
                )
            }
        }
}

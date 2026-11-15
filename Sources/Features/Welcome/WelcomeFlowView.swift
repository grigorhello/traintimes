import SwiftUI

/// The coordinate space the first launch's tiles fly in; file scope, so `onGeometryChange` closures (Sendable) can read it.
private let welcomeSpace = "welcome"

/// The first launch (TT-206, D94), against boards 1 to 6 of the Route and stations canvas: Bloom becomes the welcome
/// (the network's picture, "Welcome to Train Times", "Choose your line"), then step 1, your line, and step 2, your station,
/// which is already Schedule's header, so Schedule takes over with only the station list folding away. The seven line tiles
/// are the thread through it: drawn once, above every step, they fly from the picture's tips to the list's rows and the
/// chosen one on to the line's seat. No tab bar, no permission, nothing disabled.
struct WelcomeFlowView: View {
    let model: WelcomeViewModel
    let onRoute: (Route) -> Void

    @Environment(\.playsLaunchMotion) private var playsLaunch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bloom, until it becomes the welcome.
    @State private var onSplash: Bool
    @State private var bloomed: Bool
    /// The welcome's words, button and footnote are in.
    @State private var wordsIn: Bool
    /// When the welcome settled, for the glint.
    @State private var glintFrom: Date?
    /// The station tapped on step 2: the list folds away, then Schedule opens.
    @State private var picked: Station?

    /// `startsOnSplash` false draws the welcome at rest (snapshots, UI tests on the fixtures).
    init(model: WelcomeViewModel, startsOnSplash: Bool = LaunchMotion.plays, onRoute: @escaping (Route) -> Void) {
        self.model = model
        self.onRoute = onRoute
        _onSplash = State(initialValue: startsOnSplash)
        _bloomed = State(initialValue: !startsOnSplash)
        _wordsIn = State(initialValue: !startsOnSplash)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = WelcomeLayout(proxy)
            ZStack(alignment: .topLeading) {
                TTColor.canvas.ignoresSafeArea()
                if model.step == .welcome {
                    welcome(layout)
                        .transition(.opacity.animation(LaunchMotion.letGo))
                }
                switch model.step {
                case .welcome:
                    EmptyView()
                case .lines:
                    WelcomeLinesStep(
                        lines: model.lines,
                        bottomInset: layout.insets.bottom,
                        onHome: { go { model.backToWelcome() } },
                        onLine: { id in go { model.pick(lineId: id) } },
                        onSearch: { go { model.searchStations() } },
                        onRowFrame: { id, frame in model.rowFrames[id] = frame }
                    )
                    .transition(.opacity.animation(LaunchMotion.letGo))
                case .station:
                    if let line = model.chosenLine {
                        WelcomeStationStep(
                            line: line,
                            unionIsFirst: model.unionIsFirst,
                            picked: picked,
                            onPick: { pick($0) },
                            onSearch: { field in go { model.search(field) } },
                            onBack: { go { model.backToLines() } },
                            onSeat: { model.seatFrame = $0 }
                        )
                        .transition(.opacity.animation(LaunchMotion.letGo))
                    }
                case .search:
                    if let form = model.routeForm {
                        RouteFormView(viewModel: form, onShowTrains: onRoute)
                            .transition(.opacity.animation(LaunchMotion.letGo))
                    }
                }
                tiles(layout)
            }
            .coordinateSpace(.named(welcomeSpace))
        }
        .task { await bloom() }
        .task { await model.prepareTimetable() }
    }

    private func go(_ change: () -> Void) {
        withAnimation(reduceMotion ? LaunchMotion.fade : LaunchMotion.letGo, change)
    }

    // MARK: Splash and welcome

    /// Bloom (about 1.3 s), then the picture glides down 64 pt as the mark eases to 76 pt and the splash's name fades; the
    /// words rise 120 ms into the glide, then the button and the footnote. The glint starts once it has all settled.
    private func bloom() async {
        guard onSplash else { return }
        // One frame at the launch still's pose first, so the motion starts from it.
        try? await Task.sleep(for: .milliseconds(16))
        bloomed = true
        try? await Task.sleep(for: LaunchMotion.bloomDuration)
        withAnimation(reduceMotion ? LaunchMotion.fade : LaunchMotion.glide) { onSplash = false }
        wordsIn = true
        try? await Task.sleep(for: .milliseconds(600))
        if playsLaunch { glintFrom = Date() }
    }

    private func welcome(_ layout: WelcomeLayout) -> some View {
        let geometry = NetworkGeometry(hub: layout.welcomeHub, scale: layout.scale)
        return ZStack(alignment: .topLeading) {
            BloomStage(
                layout: layout, markSize: onSplash ? 96 : TTSize.appMark, bloomed: bloomed, showsName: onSplash,
                glintFrom: glintFrom
            )
            .offset(y: onSplash ? 0 : WelcomeLayout.glide)
            // Each tile on the picture picks its line and skips the list.
            if !onSplash {
                ForEach(Array(model.lines.enumerated()), id: \.element.id) { index, entry in
                    Button { go { model.pick(lineId: entry.id, fromMap: true) } } label: {
                        Color.clear
                            .frame(width: TTSize.targetMin, height: TTSize.targetMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: entry.line.name))
                    .accessibilityIdentifier("welcome.map.\(entry.id)")
                    .position(geometry.tip(index))
                }
            }
            words(layout)
            Button {
                go { model.chooseYourLine() }
            } label: {
                Text("welcome.choose").frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.ttGlassPrimary)
            .accessibilityIdentifier("welcome.choose")
            .padding(.horizontal, TTSpace.s5)
            .rises(wordsIn, LaunchMotion.button, reduceMotion: reduceMotion)
            .allowsHitTesting(wordsIn)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 78 - layout.insets.bottom)
            WelcomeFootnote()
                .opacity(wordsIn ? 1 : 0)
                .animation(reduceMotion ? LaunchMotion.fade : LaunchMotion.footnote, value: wordsIn)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 44 - layout.insets.bottom)
        }
    }

    /// "Welcome to" / "Train Times" and the promise, centred from 58 pt under the hub's centre.
    private func words(_ layout: WelcomeLayout) -> some View {
        VStack(spacing: TTSpace.s2) {
            Text("welcome.title")
                .font(TTFont.largeTitle)
                .tracking(-0.6)
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcome.title")
            Text("welcome.tagline")
                .font(TTFont.body)
                .foregroundStyle(TTColor.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TTSpace.s5)
        .rises(wordsIn, LaunchMotion.words, reduceMotion: reduceMotion)
        .padding(.top, layout.welcomeHub.y + 58)
    }

    // MARK: Tiles

    /// The seven tiles above every step. On the splash each pops in at its tip as its line arrives; from there they fly.
    private func tiles(_ layout: WelcomeLayout) -> some View {
        let geometry = NetworkGeometry(hub: layout.splashHub, scale: layout.scale)
        return ForEach(Array(model.lines.enumerated()), id: \.element.id) { index, entry in
            let center = tileCenter(index, id: entry.id, geometry: geometry)
            LineTile(line: entry.line)
                .scaleEffect(bloomed || reduceMotion ? 1 : 0.6)
                .opacity(bloomed ? 1 : 0)
                .animation(reduceMotion ? LaunchMotion.fade : LaunchMotion.tile(NetworkGeometry.order(index)), value: bloomed)
                .opacity(tileShown(entry.id) ? 1 : 0)
                .animation(LaunchMotion.letGo, value: model.step)
                .position(center)
                .animation(flight(index), value: center)
        }
        .allowsHitTesting(false)
    }

    /// The picture's glide moves the tiles as one; between steps they fly 24 ms apart.
    private func flight(_ index: Int) -> Animation? {
        if reduceMotion { return nil }
        return model.step == .welcome ? LaunchMotion.glide : LaunchMotion.fly(index)
    }

    private func tileCenter(_ index: Int, id: String, geometry: NetworkGeometry) -> CGPoint {
        let tip = geometry.tip(index)
        let onPicture = CGPoint(x: tip.x, y: tip.y + (onSplash ? 0 : WelcomeLayout.glide))
        let row = model.rowFrames[id].map { CGPoint(x: $0.midX, y: $0.midY) }
        switch model.step {
        case .welcome:
            return onPicture
        case .lines, .search:
            return row ?? onPicture
        case .station(let lineId, _):
            if id == lineId, let seatFrame = model.seatFrame { return CGPoint(x: seatFrame.midX, y: seatFrame.midY) }
            return row ?? onPicture
        }
    }

    private func tileShown(_ id: String) -> Bool {
        switch model.step {
        case .welcome, .lines: true
        case .station(let lineId, _): id == lineId
        case .search: false
        }
    }

    // MARK: Station

    /// The station's row keeps its press for a moment, the list folds into the card, then Schedule takes over.
    private func pick(_ station: Station) {
        guard picked == nil, let route = model.route(to: station) else { return }
        picked = station
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            onRoute(route)
        }
    }
}

/// "Independent app. No account, no ads.", 44 pt above the screen's bottom edge on the welcome and step 1.
private struct WelcomeFootnote: View {
    var body: some View {
        Text("welcome.footnote")
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, TTSpace.s5)
    }
}

/// Step 1 or 2 of 2: two 18 × 4 pt segments, 4 pt apart, the first in accent and the second too on step 2.
private struct WelcomeStepMark: View {
    let step: Int

    var body: some View {
        HStack(spacing: 4) {
            segment(isOn: true)
            segment(isOn: step >= 2)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(String(format: String(localized: "welcome.step"), step)))
        .accessibilityIdentifier("welcome.step")
    }

    private func segment(isOn: Bool) -> some View {
        Capsule()
            .fill(isOn ? TTColor.accent : TTColor.inkTertiary.opacity(0.34))
            .frame(width: 18, height: 4)
    }
}

// MARK: Step 1

/// Step 1 of 2, board 4: the name (back to the welcome), "Which GO line is yours?", one card of the seven lines, "Search
/// stations" and the footnote. The rows hold room for their tiles, which fly in from the picture above them.
private struct WelcomeLinesStep: View {
    let lines: [GONetwork.LineStations]
    let bottomInset: CGFloat
    let onHome: () -> Void
    let onLine: (String) -> Void
    let onSearch: () -> Void
    let onRowFrame: (String, CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = !LaunchMotion.plays

    private static let rowHeight: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onHome) {
                    HStack(spacing: TTSpace.s2) {
                        Image("TrainTimesSymbol")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(TTColor.accent)
                            .frame(width: 31, height: 31)
                            .offset(y: -1.7)
                            .frame(width: 20, height: 24)
                        Text("app.name")
                            .font(TTFont.headline)
                            .tracking(-0.4)
                            .foregroundStyle(TTColor.ink)
                    }
                    .frame(height: TTSize.targetMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome.home")
                Spacer(minLength: 0)
                WelcomeStepMark(step: 1)
            }
            .frame(height: LineTile.size)
            .padding(.leading, 2)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.24).delay(0.12), value: appeared)
            Text("welcome.which_line")
                .font(TTFont.largeTitle)
                .tracking(-0.6)
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 14)
                .padding(.leading, 2)
                .rises(appeared, LaunchMotion.question, reduceMotion: reduceMotion)
            card
                .padding(.top, 22)
            Button(action: onSearch) {
                Text("welcome.search")
            }
            .buttonStyle(.ttText)
            .accessibilityIdentifier("welcome.search")
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.24).delay(0.46), value: appeared)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, TTSpace.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            WelcomeFootnote().padding(.bottom, 44 - bottomInset)
        }
        .onAppear { appeared = true }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, entry in
                VStack(spacing: 0) {
                    if index > 0 {
                        Divider().overlay(TTColor.hairline).padding(.leading, 60)
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.2).delay(0.32), value: appeared)
                    }
                    Button { onLine(entry.id) } label: {
                        HStack(spacing: TTSpace.s3) {
                            Color.clear
                                .frame(width: LineTile.size, height: LineTile.size)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(welcomeSpace)) } action: {
                                    onRowFrame(entry.id, $0)
                                }
                            Text(verbatim: entry.line.name)
                                .font(TTFont.headline)
                                .foregroundStyle(TTColor.ink)
                                .opacity(appeared ? 1 : 0)
                                .animation(LaunchMotion.lineName(index), value: appeared)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, TTSpace.s4)
                        .frame(height: Self.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(WelcomeRowStyle())
                    .accessibilityIdentifier("welcome.line.\(entry.id)")
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TTRadius.xl))
        .background {
            // The card's surface fades in under the tiles as they land.
            Color.clear
                .ttSheetCard(cornerRadius: TTRadius.xl)
                .opacity(appeared ? 1 : 0)
                .animation(LaunchMotion.card, value: appeared)
        }
    }
}

/// A pressed row: the ink at 6 % in light, white at 8 % in dark, as the picker's rows.
private struct WelcomeRowStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? (colorScheme == .dark ? Color.white.opacity(0.08) : TTColor.ink.opacity(0.06)) : .clear
            )
    }
}

// MARK: Step 2

/// Step 2 of 2, board 5: Schedule's own header (the line's seat and name, the route card with Union filled in and "Your
/// station" in the other row, the X going back) with the line's stations hanging under the card, from Union outward.
private struct WelcomeStationStep: View {
    let line: GONetwork.LineStations
    let unionIsFirst: Bool
    let picked: Station?
    let onPick: (Station) -> Void
    let onSearch: (RouteFormViewModel.Field) -> Void
    let onBack: () -> Void
    let onSeat: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Schedule's 10 pt between the line row and the card, and between the tile and the name.
    private static let gap: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                Color.clear
                    .frame(width: LineTile.size, height: LineTile.size)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(welcomeSpace)) } action: { onSeat($0) }
                Text(verbatim: line.line.name)
                    .font(TTFont.lineName)
                    .tracking(-0.6)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("welcome.lineName")
                Spacer(minLength: 0)
                WelcomeStepMark(step: 2)
                    .opacity(picked == nil ? 1 : 0)
            }
            .frame(height: LineTile.size)
            .padding(.leading, 2)
            RouteCard(
                from: unionIsFirst ? GONetwork.union.name : picked?.name,
                to: unionIsFirst ? picked?.name : GONetwork.union.name,
                fromPlaceholder: unionIsFirst ? "route.choose_from" : "welcome.your_station",
                toPlaceholder: unionIsFirst ? "welcome.your_station" : "route.choose_to",
                fromID: "welcome.from",
                toID: "welcome.to",
                onTap: { onSearch($0 == .from ? .from : .to) },
                canSwap: picked != nil,
                swapID: "welcome.swap",
                onSwap: {},
                onClose: picked == nil ? onBack : nil
            )
            if picked == nil {
                WelcomeStationsPanel(line: line, onPick: onPick, spacingAbove: Self.gap)
                    .transition(.pickerPanel(reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, TTSpace.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(PickerMotion.close, value: picked)
    }
}

/// The line's stations under the route card as one surface with it (`ttAttachedPanel`), each row with a ring on the line's
/// own rail in its colour; the rows fall in with the picker's stagger (`PickerMotion`). A long line scrolls.
private struct WelcomeStationsPanel: View {
    let line: GONetwork.LineStations
    let onPick: (Station) -> Void
    var spacingAbove: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animatesPickerEntrance) private var animatesEntrance
    @State private var revealed = false

    private static let rowHeight: CGFloat = 52
    private static let inset = TTSpace.s4
    /// The glyph column of the picker: the ring's centre 26 pt in, where the card's markers are.
    private static let glyphColumn: CGFloat = 20
    private static let ring: CGFloat = 13
    private static let rail: CGFloat = 3

    private var isRevealed: Bool { revealed || !animatesEntrance }

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
                .mask {
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
                    }
                }
        }
        .overlay(alignment: .top) { Divider().overlay(TTColor.hairline).padding(.leading, Self.inset) }
        .ttAttachedPanel(cornerRadius: TTRadius.lg)
        .padding(.top, -(spacingAbove + 1))
        .padding(.bottom, TTSpace.s3)
        .onAppear { revealed = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.stations")
    }

    /// Light: the line's colour; dark: mixed 42 % toward white, as the picture's lines.
    private var ink: Color {
        GOLineColor.color(for: line.line, towardWhite: colorScheme == .dark ? 0.42 : 0)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(line.stations.enumerated()), id: \.element.id) { index, station in
                row(station, index: index)
            }
        }
        .background(alignment: .topLeading) {
            // The rail from the first ring to the last, behind them.
            Rectangle()
                .fill(ink)
                .frame(width: Self.rail, height: CGFloat(max(line.stations.count - 1, 0)) * Self.rowHeight)
                .offset(x: Self.inset + Self.glyphColumn / 2 - Self.rail / 2, y: Self.rowHeight / 2)
                .opacity(isRevealed ? 1 : 0)
                .animation(reduceMotion ? LaunchMotion.fade : .easeOut(duration: 0.3).delay(0.1), value: isRevealed)
        }
        .padding(.bottom, TTSpace.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ station: Station, index: Int) -> some View {
        Button { onPick(station) } label: {
            HStack(spacing: TTSpace.s3) {
                Circle()
                    .fill(TTColor.surface)
                    .overlay(Circle().strokeBorder(ink, lineWidth: Self.rail))
                    .frame(width: Self.ring, height: Self.ring)
                    .frame(width: Self.glyphColumn)
                Text(verbatim: station.name)
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.inset)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(WelcomeRowStyle())
        .overlay(alignment: .top) {
            if index > 0 { Divider().overlay(TTColor.hairline).padding(.leading, 48) }
        }
        .accessibilityIdentifier("welcome.station.\(station.id)")
        .opacity(isRevealed ? 1 : 0)
        .animation(reduceMotion ? LaunchMotion.fade : PickerMotion.rowFade(order: index), value: isRevealed)
        .scaleEffect(isRevealed || reduceMotion ? 1 : 0.92)
        .offset(y: isRevealed || reduceMotion ? 0 : -28)
        .animation(reduceMotion ? nil : PickerMotion.rowFall(order: index), value: isRevealed)
    }
}

private extension View {
    /// Rises 10 pt and fades in once `isIn`, on `animation`; Reduce Motion fades only.
    func rises(_ isIn: Bool, _ animation: Animation, reduceMotion: Bool) -> some View {
        opacity(isIn ? 1 : 0)
            .offset(y: isIn || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? LaunchMotion.fade : animation, value: isIn)
    }
}

#Preview {
    WelcomeFlowView(
        model: WelcomeViewModel(stations: ScheduleDependencies.fixtures().stations, clock: SystemClock()), onRoute: { _ in }
    )
}

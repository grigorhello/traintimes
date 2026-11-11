import SwiftUI

/// The scroll view's coordinate space name; file scope, so the `onGeometryChange` closure (Sendable) can read it.
private let stationPickerScrollSpace = "stationPicker"

/// The suggestions under the route card while a station row is the search field (TT-161, D54), against the canvas
/// frames Route-Pick-From / To and Schedule-Pick. The panel is the route card's own surface continued below it: no gap,
/// flat where they meet, one shadow around both, a hairline seam between. It is as tall as its rows, up to the space above
/// the keyboard, and scrolls past that under a short fade. Groups, in order: Recent routes (Schedule, before typing), Your
/// stations (from the recent routes) and All stations; every row has a glyph in the column the card's markers use, so all
/// the titles line up with the field. The other field's station is greyed with its reason and cannot be picked. The parent
/// reveals it (`AnyTransition.pickerPanel`); its content rides down a little and its rows fall in one after another.
struct StationPickerPanel: View {
    let viewModel: RouteFormViewModel
    let onPick: (Station) -> Void
    let onPickRoute: (Route) -> Void
    /// A swipe down on the panel: the same as the X.
    let onCancel: () -> Void
    /// The space a parent stack puts between the card and the panel, which the panel takes back so that it hangs from the
    /// card's bottom edge.
    var spacingAbove: CGFloat = 0

    /// 56 pt rows, 16 pt in from the panel's edges.
    private static let rowHeight: CGFloat = 56
    private static let inset = TTSpace.s4
    /// The glyph column: the card's marker column, so row titles start where the field's text does.
    private static let glyphColumn: CGFloat = 20
    /// A swipe down this far, mostly vertical, cancels.
    private static let cancelDistance: CGFloat = 60
    /// A long list ends under a fade this tall.
    private static let fadeHeight: CGFloat = 28
    /// The panel hangs 1 pt over the card's bottom edge, so no seam shows, and ends 10 pt above the keyboard.
    private static let overlap: CGFloat = 1
    private static let keyboardGap: CGFloat = 10

    /// The list is at its top, so a swipe down is a cancel and not a scroll back up.
    @State private var isAtTop = true
    /// Set once the panel is on screen: the content rides down and the rows fall in.
    @State private var settled = false
    /// The rider started typing, which ends any stagger still running: rows still falling snap into place.
    @State private var staggerEnded = false
    /// Counts picks, for the selection haptic.
    @State private var picks = 0
    /// The picked row, which keeps its press tint for 120 ms before the list closes; taps meanwhile are ignored.
    @State private var heldRow: String?
    @Environment(\.animatesPickerEntrance) private var animatesEntrance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rowsRevealed: Bool { settled || !animatesEntrance || staggerEnded }

    var body: some View {
        ViewThatFits(in: .vertical) {
            // A list that could fit is measured whole; a longer one (every station, about 70) only ever scrolls, so it is not
            // built a second time just to be measured (TT-196). A lazy stack was tried and dropped: on iOS 26 SwiftUI built
            // its rows on a background render thread, which trapped Swift 6's main-actor check while typing.
            if rowCount <= Self.measuredRows { groups }
            ScrollView {
                groups
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .named(stationPickerScrollSpace)).minY >= -1 } action: {
                        isAtTop = $0
                    }
            }
            .coordinateSpace(.named(stationPickerScrollSpace))
            // Scrolling the list keeps the keyboard, so the panel does not resize under the rider's finger.
            .scrollDismissesKeyboard(.never)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Self.fadeHeight)
                }
            }
        }
        // Switching to the other field crossfades the groups in 180 ms, with no second drop.
        .id(viewModel.pickingField)
        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
        .animation(.easeInOut(duration: 0.18), value: viewModel.pickingField)
        // The seam with the card above, inset like the row separators.
        .overlay(alignment: .top) { Divider().overlay(TTColor.hairline).padding(.leading, Self.inset) }
        .ttAttachedPanel(cornerRadius: TTRadius.lg)
        .padding(.top, -(spacingAbove + Self.overlap))
        .padding(.bottom, Self.keyboardGap)
        // Typing and every other height change follow the critically damped spring: nothing bounces under the thumb.
        .animation(PickerMotion.height, value: viewModel.query)
        .onAppear { settled = true }
        .onChange(of: viewModel.query) { _, query in
            if !query.isEmpty { staggerEnded = true }
        }
        .sensoryFeedback(.selection, trigger: picks)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { drag in
                let down = drag.translation.height
                if isAtTop, down > Self.cancelDistance, down > abs(drag.translation.width) { onCancel() }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stations.panel")
    }

    // MARK: Groups

    /// The most rows that can fit above the keyboard (or above the home indicator, with no software keyboard) and more.
    private static let measuredRows = 14

    private var rowCount: Int {
        viewModel.suggestedRoutes.count + viewModel.yourStations.count + viewModel.allStations.count
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: 0) { groupRows }
            .padding(.bottom, TTSpace.s1 + TTSpace.s1 / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The rows ride down 24 pt as one block, on a bouncier spring than the clip that reveals them.
            .offset(y: settled || !animatesEntrance || reduceMotion ? 0 : -PickerMotion.rideDistance)
            .animation(PickerMotion.ride, value: settled)
    }

    @ViewBuilder private var groupRows: some View {
        let routes = viewModel.suggestedRoutes
        let yours = viewModel.yourStations
        let all = viewModel.allStations
        // The frame calls the typed results "Stations" when there is no Your stations group to tell them apart from.
        let allTitle: LocalizedStringKey = viewModel.query.isEmpty || !yours.isEmpty ? "stations.all" : "stations.results"
        // Each group's header shares its first row's place in the fall, and the next group starts after its last row.
        let yoursBase = routes.count
        let allBase = yoursBase + yours.count
        let allGlyph: Glyph = viewModel.pickingField == .from ? .ring : .pin
        if !routes.isEmpty {
            header("route.recent", order: 0)
            ForEach(Array(routes.enumerated()), id: \.element) { index, route in
                VStack(alignment: .leading, spacing: 0) {
                    if index > 0 { hairline }
                    routeRow(route)
                }
                .fallsIn(order: index, revealed: rowsRevealed, snaps: staggerEnded, reduceMotion: reduceMotion)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
        if !yours.isEmpty {
            header("stations.yours", order: yoursBase)
            stationRows(yours, idPrefix: "station.yours.", glyph: .clock, base: yoursBase)
        }
        if !all.isEmpty {
            header(allTitle, order: allBase)
            stationRows(all, idPrefix: "station.", glyph: allGlyph, base: allBase)
        }
        if viewModel.hasNoMatch {
            Text("stations.none")
                .font(TTFont.body)
                .foregroundStyle(TTColor.inkSecondary)
                .padding(.horizontal, Self.inset)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                .accessibilityIdentifier("stations.none")
        }
    }

    /// A 13 pt ink-secondary group title: 12 pt above and 4 pt below.
    private func header(_ title: LocalizedStringKey, order: Int) -> some View {
        Text(title)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, Self.inset)
            .padding(.top, TTSpace.s3)
            .padding(.bottom, TTSpace.s1)
            .accessibilityAddTraits(.isHeader)
            .fallsIn(order: order, revealed: rowsRevealed, snaps: staggerEnded, reduceMotion: reduceMotion)
    }

    private var hairline: some View {
        Divider()
            .overlay(TTColor.hairline)
            .padding(.leading, Self.inset)
    }

    private func stationRows(_ rows: [RouteFormViewModel.StationRow], idPrefix: String, glyph: Glyph, base: Int) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            VStack(alignment: .leading, spacing: 0) {
                if index > 0 { hairline }
                stationRow(row, id: idPrefix + row.station.id, glyph: glyph)
            }
            .fallsIn(order: base + index, revealed: rowsRevealed, snaps: staggerEnded, reduceMotion: reduceMotion)
            // A row that appears while typing fades in over 150 ms.
            .transition(.opacity.animation(.easeOut(duration: 0.15)))
        }
    }

    /// The glyph in front of a station row: a clock for Your stations, a ring (From) or a pin (To) for the rest.
    private enum Glyph {
        case clock, ring, pin
    }

    @ViewBuilder private func glyphView(_ glyph: Glyph, isDisabled: Bool) -> some View {
        let colour = isDisabled ? TTColor.inkTertiary : TTColor.inkSecondary
        Group {
            switch glyph {
            case .clock:
                Image(systemName: "clock")
                    .font(.system(size: TTSize.iconSM))
                    .foregroundStyle(colour)
            case .ring:
                Circle()
                    .strokeBorder(colour, lineWidth: 2.5)
                    .frame(width: 12, height: 12)
            case .pin:
                RoutePin()
                    .fill(colour, style: FillStyle(eoFill: true))
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: Self.glyphColumn)
        .accessibilityHidden(true)
    }

    /// Full name in `headline`, line context in `footnote`. A greyed row is disabled, so VoiceOver reads it as dimmed with its
    /// reason.
    private func stationRow(_ row: RouteFormViewModel.StationRow, id: String, glyph: Glyph) -> some View {
        Button {
            commit(id) { onPick(row.station) }
        } label: {
            HStack(spacing: TTSpace.s3) {
                glyphView(glyph, isDisabled: row.isDisabled)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.station.name)
                        .font(TTFont.headline)
                        .foregroundStyle(row.isDisabled ? TTColor.inkTertiary : TTColor.ink)
                        .lineLimit(1)
                    Text(verbatim: row.detail)
                        .font(TTFont.footnote)
                        .foregroundStyle(row.isDisabled ? TTColor.inkTertiary : TTColor.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.inset)
            .padding(.vertical, TTSpace.s2)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelRowStyle(isHeld: heldRow == id))
        .disabled(row.isDisabled)
        .accessibilityIdentifier(id)
    }

    /// Mini markers in the glyph column, origin over destination at 15 pt semibold, the line's code tile at the right; a tap
    /// shows that route.
    private func routeRow(_ route: Route) -> some View {
        let id = "route.recent.\(route.from.id)-\(route.to.id)"
        return Button {
            commit(id) { onPickRoute(route) }
        } label: {
            HStack(alignment: .top, spacing: TTSpace.s3) {
                RouteMarkers(size: .mini)
                    .frame(width: Self.glyphColumn)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: route.from.name).tracking(-0.2)
                    Text(verbatim: route.to.name).tracking(-0.2)
                }
                .font(TTFont.recentRoute)
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                Spacer(minLength: 0)
                if let line = route.line {
                    PanelLineTile(line: line)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, Self.inset)
            .padding(.vertical, TTSpace.s2)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelRowStyle(isHeld: heldRow == id))
        .accessibilityLabel(Text(verbatim: viewModel.title(route)))
        .accessibilityIdentifier(id)
    }

    /// A pick: the selection haptic now, the press tint held for 120 ms, then the pick (which closes the list). A second
    /// tap in between, or a cancel, does nothing.
    private func commit(_ id: String, _ pick: @escaping @MainActor () -> Void) {
        guard heldRow == nil else { return }
        picks += 1
        heldRow = id
        Task { @MainActor in
            try? await Task.sleep(for: PickerMotion.pickHold)
            defer { heldRow = nil }
            if viewModel.isPickingStation { pick() }
        }
    }
}

private extension View {
    /// A header or row falling in after the ones above it: opacity 0 to 1 in 140 ms, and from 28 pt above at 92 % size
    /// (about the centre, never one axis) on a bouncy spring. Once the panel has settled, rows that appear later (while
    /// typing) are already in place; the first keystroke makes the rest snap. Reduce Motion: a 200 ms fade, no movement.
    func fallsIn(order: Int, revealed: Bool, snaps: Bool, reduceMotion: Bool) -> some View {
        opacity(revealed ? 1 : 0)
            .animation(snaps ? nil : reduceMotion ? .easeOut(duration: 0.2) : PickerMotion.rowFade(order: order), value: revealed)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.92)
            .offset(y: revealed || reduceMotion ? 0 : -28)
            .animation(snaps || reduceMotion ? nil : PickerMotion.rowFall(order: order), value: revealed)
    }
}

/// Tints a pressed row (the ink at 6 % in light, white at 8 % in dark) and keeps a greyed row in ink-tertiary, as on the
/// frame (the plain style would dim a disabled row further).
private struct PanelRowStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    /// The row was picked and keeps its tint for the 120 ms before the list closes.
    var isHeld = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed || isHeld
                    ? (colorScheme == .dark ? Color.white.opacity(0.08) : TTColor.ink.opacity(0.06)) : .clear
            )
    }
}

/// The line's code in a 26 pt tile in its own colour, canvas `.pk-row .tile`.
private struct PanelLineTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let line: Line

    private static let size: CGFloat = 26

    var body: some View {
        Text(verbatim: line.id)
            .font(TTFont.lineCodeSmall)
            .tracking(0.3)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(GOLineColor.color(for: line), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

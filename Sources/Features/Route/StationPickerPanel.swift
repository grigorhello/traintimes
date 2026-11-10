import SwiftUI

/// The scroll view's coordinate space name; file scope, so the `onGeometryChange` closure (Sendable) can read it.
private let stationPickerScrollSpace = "stationPicker"

/// The suggestions under the route card while a station row is the search field (TT-161, D53), against the canvas frames
/// Route form · picking the starting station / the destination and Schedule · changing a station in place. A glass panel
/// that is as tall as its rows, up to the space above the keyboard, and scrolls past that. Groups, in order: Recent
/// routes (Schedule, before typing), Your stations (from the recent routes) and All stations. The other field's station is
/// greyed with its reason and cannot be picked.
struct StationPickerPanel: View {
    let viewModel: RouteFormViewModel
    let onPick: (Station) -> Void
    let onPickRoute: (Route) -> Void
    /// A swipe down on the panel: the same as the X.
    let onCancel: () -> Void

    /// Canvas `.pk-panel`: a 26 pt radius.
    private static let radius: CGFloat = 26
    /// Canvas `.pk-row`: 56 pt rows, 16 pt in from the panel's edges.
    private static let rowHeight: CGFloat = 56
    private static let inset = TTSpace.s4
    /// A swipe down this far, mostly vertical, cancels.
    private static let cancelDistance: CGFloat = 60

    /// The list is at its top, so a swipe down is a cancel and not a scroll back up.
    @State private var isAtTop = true

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .named(stationPickerScrollSpace)).minY >= -1 } action: {
                        isAtTop = $0
                    }
            }
            .coordinateSpace(.named(stationPickerScrollSpace))
            // Scrolling the list keeps the keyboard, so the panel does not resize under the rider's finger.
            .scrollDismissesKeyboard(.never)
        }
        .ttGlassPanel(cornerRadius: Self.radius)
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

    private var content: some View {
        let routes = viewModel.suggestedRoutes
        let yours = viewModel.yourStations
        let all = viewModel.allStations
        // The frame calls the typed results "Stations" when there is no Your stations group to tell them apart from.
        let allTitle: LocalizedStringKey = viewModel.query.isEmpty || !yours.isEmpty ? "stations.all" : "stations.results"
        return VStack(alignment: .leading, spacing: 0) {
            if !routes.isEmpty {
                header("route.recent")
                ForEach(Array(routes.enumerated()), id: \.element) { index, route in
                    if index > 0 { hairline }
                    routeRow(route)
                }
            }
            if !yours.isEmpty {
                header("stations.yours")
                stationRows(yours, idPrefix: "station.yours.")
            }
            if !all.isEmpty {
                header(allTitle)
                stationRows(all, idPrefix: "station.")
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
        .padding(.bottom, TTSpace.s1 + TTSpace.s1 / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A 13 pt ink-secondary group title: canvas `.pk-h`, 12 pt above and 4 pt below.
    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, Self.inset)
            .padding(.top, TTSpace.s3)
            .padding(.bottom, TTSpace.s1)
            .accessibilityAddTraits(.isHeader)
    }

    private var hairline: some View {
        Divider()
            .overlay(TTColor.hairline)
            .padding(.leading, Self.inset)
    }

    private func stationRows(_ rows: [RouteFormViewModel.StationRow], idPrefix: String) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            if index > 0 { hairline }
            stationRow(row, id: idPrefix + row.station.id)
        }
    }

    /// Full name in `headline`, line context in `footnote`, a clock at the right for a station from the recent routes. A
    /// greyed row is disabled, so VoiceOver reads it as dimmed with its reason.
    private func stationRow(_ row: RouteFormViewModel.StationRow, id: String) -> some View {
        Button {
            onPick(row.station)
        } label: {
            HStack(spacing: TTSpace.s3) {
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
                if row.isRecent {
                    Image(systemName: "clock")
                        .font(.system(size: TTSize.iconSM))
                        .foregroundStyle(TTColor.inkTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Self.inset)
            .padding(.vertical, TTSpace.s2)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelRowStyle())
        .disabled(row.isDisabled)
        .accessibilityIdentifier(id)
    }

    /// Mini markers, origin over destination at 15 pt semibold, the line's code tile at the right; a tap shows that route.
    private func routeRow(_ route: Route) -> some View {
        Button {
            onPickRoute(route)
        } label: {
            HStack(alignment: .top, spacing: TTSpace.s3) {
                RouteMarkers(size: .mini)
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
        .buttonStyle(PanelRowStyle())
        .accessibilityLabel(Text(verbatim: viewModel.title(route)))
        .accessibilityIdentifier("route.recent.\(route.from.id)-\(route.to.id)")
    }
}

/// Keeps a greyed row in ink-tertiary, as on the frame (the plain style would dim a disabled row further), and tints a
/// pressed row.
private struct PanelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? TTColor.ink.opacity(0.06) : .clear)
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

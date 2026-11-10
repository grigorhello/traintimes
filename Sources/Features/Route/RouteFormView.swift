import SwiftUI

/// The first screen on first launch (TT-120, D48, D53), against the canvas frames Route form · first use and picking the
/// starting station / the destination: a large title, the route card, "Show trains" and a footnote. Tapping a station row
/// makes it the search field and unfolds the suggestions under the card, with no sheet; "Show trains" and the footnote
/// step aside while it is open. After the first route, Schedule picks in place with the same card and panel.
struct RouteFormView: View {
    let viewModel: RouteFormViewModel
    let onShowTrains: (Route) -> Void

    /// Canvas `.pk-panel`: 8 pt under the card and 10 pt above the keyboard.
    private static let panelGap: CGFloat = TTSpace.s2
    private static let keyboardGap: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s4) {
            Text("route.choose")
                .font(TTFont.largeTitle)
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("route.title")
            RouteCard(
                from: viewModel.from?.name,
                to: viewModel.to?.name,
                fromID: "route.from",
                toID: "route.to",
                onTap: { viewModel.open($0 == .from ? .from : .to) },
                picking: picking,
                canSwap: viewModel.canSwap,
                swapID: "route.swap"
            ) {
                viewModel.swap()
            }
            if viewModel.isPickingStation {
                StationPickerPanel(
                    viewModel: viewModel,
                    onPick: { viewModel.pick($0) },
                    onPickRoute: { viewModel.choose($0) },
                    onCancel: { viewModel.closeStations() }
                )
                .padding(.top, Self.panelGap - TTSpace.s4)
                .padding(.bottom, Self.keyboardGap)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            } else {
                if viewModel.isSameStation {
                    Text("route.same_station")
                        .font(TTFont.footnote)
                        .foregroundStyle(TTColor.cancelInk)
                        .accessibilityIdentifier("route.sameStation")
                }
                Button {
                    Task { if let route = await viewModel.route() { onShowTrains(route) } }
                } label: {
                    Text("button.show_trains").frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttGlassPrimary)
                .disabled(!viewModel.canShowTrains)
                .accessibilityIdentifier("route.showTrains")
                Text("route.footnote")
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, TTSpace.s3)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, TTSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TTColor.canvas)
        .animation(.spring(duration: 0.3), value: viewModel.isPickingStation)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadStations() }
    }

    /// The tapped row as the search field, with the X in the swap button's place.
    private var picking: RouteCard.Picking? {
        guard viewModel.isPickingStation else { return nil }
        return RouteCard.Picking(
            stop: viewModel.pickingField == .from ? .from : .to,
            query: viewModel.query,
            selected: viewModel.pickingStationName,
            cancelID: "route.cancel",
            onQuery: { viewModel.query = $0 },
            onSubmit: { viewModel.pickFirstMatch() },
            onCancel: { viewModel.closeStations() }
        )
    }
}

#Preview {
    RouteFormView(
        viewModel: RouteFormViewModel(route: nil, repository: ScheduleDependencies.fixtures().stations), onShowTrains: { _ in }
    )
}

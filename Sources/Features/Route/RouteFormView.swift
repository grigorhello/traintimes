import SwiftUI

/// The first screen on first launch (TT-120, D48, D54), against the canvas frames Route form · first use and picking the
/// starting station / the destination: a large title, the route card, "Show trains" and a footnote. Tapping a station row
/// makes it the search field and the suggestions drop out from under the card as one surface with it, with no sheet;
/// "Show trains" and the footnote step aside while it is open. After the first route, Schedule picks in place with the
/// same card and panel.
struct RouteFormView: View {
    let viewModel: RouteFormViewModel
    let onShowTrains: (Route) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    onCancel: { viewModel.closeStations() },
                    spacingAbove: TTSpace.s4
                )
                .transition(.pickerPanel(reduceMotion: reduceMotion))
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
        .animation(PickerMotion.animation(opening: viewModel.isPickingStation), value: viewModel.isPickingStation)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadStations() }
    }

    /// The tapped row as the search field, with the X in the swap button's place.
    private var picking: RouteCard.Picking? {
        guard viewModel.isPickingStation else { return nil }
        return RouteCard.Picking(
            stop: viewModel.pickingField == .from ? .from : .to,
            query: viewModel.query,
            current: viewModel.pickingStationName,
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

import SwiftUI

/// Route form (TT-120) as the canvas "Route-Picker" (D48). On first use it is the Schedule tab's screen, under a large
/// title; otherwise it is the route sheet the Schedule route card opens, prefilled, with the routes opened last under
/// Recent in place of the footnote.
struct RouteFormView: View {
    let viewModel: RouteFormViewModel
    /// First use, in the Schedule tab rather than a sheet.
    var isFirstUse = false
    let onShowTrains: (Route) -> Void

    /// Canvas `.mini`: the ring sits centred on the first headline line (22 pt).
    private static let miniMarkerTop: CGFloat = 6
    /// Canvas `.cell .txt`: 2 pt between lines.
    private static let lineGap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s4) {
            Text("route.choose")
                .font(isFirstUse ? TTFont.largeTitle : TTFont.route)
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("route.title")
            RouteCard(
                from: viewModel.from?.name,
                to: viewModel.to?.name,
                tap: .stop(fromID: "route.from", toID: "route.to", action: { stop in
                    viewModel.open(stop == .from ? .from : .to)
                }),
                canSwap: viewModel.canSwap,
                swapID: "route.swap"
            ) {
                viewModel.swap()
            }
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
            .buttonStyle(.ttPrimary)
            .disabled(!viewModel.canShowTrains)
            .accessibilityIdentifier("route.showTrains")
            if viewModel.recentRoutes.isEmpty {
                Text("route.footnote")
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, TTSpace.s3)
            } else {
                recentSection
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, isFirstUse ? TTSpace.s6 : TTSpace.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: isPickingStation) {
            StationSearchView(viewModel: viewModel)
        }
    }

    // MARK: Recent

    /// "Recent" over a card of the last routes opened, newest first; a tap opens that route.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: TTSpace.s2) {
            Text("route.recent")
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
                .padding(.horizontal, TTSpace.s4)
                .accessibilityAddTraits(.isHeader)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentRoutes, id: \.self) { route in
                        if route != viewModel.recentRoutes.first {
                            Divider().overlay(TTColor.hairline)
                        }
                        recentRow(route)
                    }
                }
            }
        }
        .padding(.top, TTSpace.s2)
    }

    /// Mini markers, origin over destination in headline, the line in footnote.
    private func recentRow(_ route: Route) -> some View {
        Button {
            onShowTrains(route)
        } label: {
            HStack(alignment: .top, spacing: TTSpace.s3) {
                RouteMarkers(size: .mini)
                    .padding(.top, Self.miniMarkerTop)
                VStack(alignment: .leading, spacing: Self.lineGap) {
                    Text(verbatim: route.from.name)
                        .font(TTFont.headline)
                        .foregroundStyle(TTColor.ink)
                    Text(verbatim: route.to.name)
                        .font(TTFont.headline)
                        .foregroundStyle(TTColor.ink)
                    if let line = route.line {
                        Text(line.name)
                            .font(TTFont.footnote)
                            .foregroundStyle(TTColor.inkSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TTSpace.s4)
            .padding(.vertical, TTSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: viewModel.title(route)))
        .accessibilityIdentifier("route.recent.\(route.from.id)-\(route.to.id)")
    }

    private var isPickingStation: Binding<Bool> {
        Binding(get: { viewModel.isPickingStation }, set: { if !$0 { viewModel.closeStations() } })
    }
}

#Preview {
    RouteFormView(
        viewModel: RouteFormViewModel(route: nil, repository: ScheduleDependencies.fixtures().stations), isFirstUse: true,
        onShowTrains: { _ in }
    )
}

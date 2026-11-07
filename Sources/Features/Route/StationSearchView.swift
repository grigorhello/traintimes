import SwiftUI

/// Station search (TT-121) against design/frames/station-search.png: the sheet the route form opens for From or To.
/// A native search field, then Your stations (starred) and All stations. The other field's station is greyed with its
/// reason and cannot be picked; Cancel returns to the form unchanged.
struct StationSearchView: View {
    @Bindable var viewModel: RouteFormViewModel
    @State private var isSearching = false

    private var title: LocalizedStringKey {
        viewModel.pickingField == .from ? "route.from" : "route.to"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TTSpace.s2) {
                    section("stations.yours", rows: viewModel.yourStations, top: TTSpace.s1)
                    section("stations.all", rows: viewModel.allStations, top: TTSpace.s3)
                }
                .padding(.horizontal, TTSpace.s5)
                .padding(.bottom, TTSpace.s6)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(TTColor.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title)
                        .font(TTFont.navTitle)
                        .foregroundStyle(TTColor.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("stations.title")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("button.cancel") { viewModel.closeStations() }
                        .font(TTFont.body)
                        .foregroundStyle(TTColor.accent)
                        .accessibilityIdentifier("stations.cancel")
                }
            }
            .searchable(
                text: $viewModel.query,
                isPresented: $isSearching,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("stations.search")
            )
        }
        .task { await viewModel.loadStations() }
        // Picking From moves on to To with an empty search, so the To list starts from the top.
        .onChange(of: viewModel.pickingField) { isSearching = false }
        .presentationDragIndicator(.visible)
        .presentationBackground(TTColor.surface)
    }

    /// A footnote group title over a card of rows split by hairlines; hidden when no row matches.
    @ViewBuilder
    private func section(_ title: LocalizedStringKey, rows: [RouteFormViewModel.StationRow], top: CGFloat) -> some View {
        if !rows.isEmpty {
            Text(title)
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
                .padding(.horizontal, TTSpace.s4)
                .padding(.top, top)
                .accessibilityAddTraits(.isHeader)
            Card(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Divider().overlay(TTColor.hairline)
                        }
                        stationRow(row)
                    }
                }
            }
        }
    }

    /// Full name in `headline`, line context in `footnote`; a greyed row is disabled, so VoiceOver reads it as dimmed
    /// with its reason.
    private func stationRow(_ row: RouteFormViewModel.StationRow) -> some View {
        Button {
            viewModel.pick(row.station)
        } label: {
            HStack(spacing: TTSpace.s3) {
                VStack(alignment: .leading, spacing: TTSpace.s1 / 2) {
                    Text(row.station.name)
                        .font(TTFont.headline)
                        .foregroundStyle(row.isDisabled ? TTColor.inkTertiary : TTColor.ink)
                    Text(row.detail)
                        .font(TTFont.footnote)
                        .foregroundStyle(row.isDisabled ? TTColor.inkTertiary : TTColor.inkSecondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if row.isFavourite {
                    Image(systemName: "star.fill")
                        .font(TTFont.body)
                        .foregroundStyle(row.isDisabled ? TTColor.inkTertiary : TTColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, TTSpace.s3)
            .padding(.horizontal, TTSpace.s4)
            // 56 pt rows, as on the canvas (`.station`).
            .frame(minHeight: TTSize.targetMin + TTSpace.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.isDisabled)
        .accessibilityIdentifier("station.\(row.station.id)")
    }
}

#Preview {
    StationSearchView(viewModel: RouteFormViewModel(route: nil, repository: ScheduleDependencies.fixtures().stations))
}

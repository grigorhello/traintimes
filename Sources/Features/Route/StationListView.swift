import SwiftUI

/// The station list the route form opens for From or To. A plain list for now: station search, its groups and the
/// greyed "Same as" row replace it in TT-121.
struct StationListView: View {
    let viewModel: RouteFormViewModel

    private var title: LocalizedStringKey {
        viewModel.pickingField == .from ? "route.from" : "route.to"
    }

    var body: some View {
        NavigationStack {
            List(viewModel.stations) { station in
                Button {
                    viewModel.pick(station)
                } label: {
                    Text(station.name)
                        .font(TTFont.headline)
                        .foregroundStyle(TTColor.ink)
                        .frame(maxWidth: .infinity, minHeight: TTSize.targetMin, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(TTColor.surface)
                .accessibilityIdentifier("station.\(station.id)")
            }
            .scrollContentBackground(.hidden)
            .background(TTColor.canvas)
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("button.cancel") { viewModel.closeStations() }
                        .accessibilityIdentifier("stations.cancel")
                }
            }
        }
        .task { await viewModel.loadStations() }
        .presentationDragIndicator(.visible)
    }
}

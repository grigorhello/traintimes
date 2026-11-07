import SwiftUI

/// Route form (TT-120) against design/frames/route-picker.png. With `onSettings` it is the first-use screen in the
/// Schedule tab, under the "Train Times" header with the gear; without it, it is the route sheet from the Schedule header.
/// A returning rider sees the favourites list in place of the footnote (canvas "Route-Picker", rider "returning", TT-122).
struct RouteFormView: View {
    let viewModel: RouteFormViewModel
    var onSettings: (() -> Void)?
    let onShowTrains: (Route) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let onSettings {
                header(onSettings)
            }
            VStack(alignment: .leading, spacing: TTSpace.s4) {
                Text("route.choose")
                    .font(TTFont.route)
                    .foregroundStyle(TTColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("route.title")
                fieldsCard
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
                if viewModel.favouriteRoutes.isEmpty {
                    Text("route.footnote")
                        .font(TTFont.footnote)
                        .foregroundStyle(TTColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, TTSpace.s3)
                } else {
                    favouritesSection
                }
            }
            .padding(.horizontal, TTSpace.s5)
            .padding(.top, onSettings == nil ? TTSpace.s8 : TTSpace.s3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
        // Keeps Settings' back button reading "Train Times" on first use; the header above replaces the bar.
        .navigationTitle(Text("app.name"))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: isPickingStation) {
            StationSearchView(viewModel: viewModel)
        }
    }

    /// Same header as Schedule, so first use looks like the Schedule tab it becomes.
    private func header(_ onSettings: @escaping () -> Void) -> some View {
        HStack {
            Text("app.name")
                .font(TTFont.navTitle)
                .foregroundStyle(TTColor.ink)
                .accessibilityIdentifier("schedule.title")
            Spacer()
            IconButton(systemName: "gearshape", label: "nav.settings", action: onSettings)
                .accessibilityIdentifier("schedule.settings")
        }
        .padding(.leading, TTSpace.s5)
        .padding(.trailing, TTSpace.s2)
    }

    /// From and To, split by a hairline, with one 44 pt swap button to the right of both.
    private var fieldsCard: some View {
        Card(padding: 0) {
            HStack(spacing: TTSpace.s2) {
                VStack(spacing: 0) {
                    fieldRow(.from, label: "route.from", station: viewModel.from)
                    Divider().overlay(TTColor.hairline)
                    fieldRow(.to, label: "route.to", station: viewModel.to)
                }
                IconButton(systemName: "arrow.up.arrow.down", label: "route.swap", isSelected: viewModel.canSwap) {
                    viewModel.swap()
                }
                .disabled(!viewModel.canSwap)
                .accessibilityIdentifier("route.swap")
            }
            .padding(.leading, TTSpace.s4)
            .padding(.trailing, TTSpace.s2)
        }
    }

    private func fieldRow(_ field: RouteFormViewModel.Field, label: LocalizedStringKey, station: Station?) -> some View {
        Button {
            viewModel.open(field)
        } label: {
            HStack(spacing: TTSpace.s3) {
                VStack(alignment: .leading, spacing: TTSpace.s1 / 2) {
                    Text(label)
                        .font(TTFont.footnote)
                        .foregroundStyle(TTColor.inkSecondary)
                    Text(station?.name ?? String(localized: "route.choose_station"))
                        .font(TTFont.body)
                        .foregroundStyle(station == nil ? TTColor.inkTertiary : TTColor.ink)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(TTFont.body)
                    .foregroundStyle(TTColor.inkSecondary)
            }
            // 60 pt rows including the 8 pt padding, as on the canvas (`.fieldrow`).
            .padding(.vertical, TTSpace.s2)
            .frame(minHeight: TTSize.targetMin + TTSpace.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("route.\(field.rawValue)")
    }

    // MARK: Favourites

    /// "Favourites" and "3 of 3", the list (star, name, line, chevron), the full-list sentence and Manage favourites.
    private var favouritesSection: some View {
        VStack(alignment: .leading, spacing: TTSpace.s2) {
            HStack {
                Text("route.favourites")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(viewModel.favouritesCount)
                    .monospacedDigit()
                    .accessibilityIdentifier("route.favouritesCount")
            }
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, TTSpace.s4)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(viewModel.favouriteRoutes, id: \.self) { route in
                        if route != viewModel.favouriteRoutes.first {
                            Divider().overlay(TTColor.hairline)
                        }
                        favouriteRow(route)
                    }
                }
            }
            if viewModel.isFavouritesFull {
                Text("route.favourites_footnote")
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                    .padding(.horizontal, TTSpace.s4)
            }
            Button {
                viewModel.toggleManagingFavourites()
            } label: {
                Text(viewModel.isManagingFavourites ? "button.done" : "route.manage_favourites" as LocalizedStringKey)
            }
            .buttonStyle(.ttSecondary)
            .padding(.leading, TTSpace.s4)
            .accessibilityIdentifier("route.manageFavourites")
        }
        .padding(.top, TTSpace.s2)
    }

    /// Opens the route; while managing, the chevron gives way to a remove button.
    private func favouriteRow(_ route: Route) -> some View {
        let id = "route.favourite.\(route.from.id)-\(route.to.id)"
        return Button {
            onShowTrains(route)
        } label: {
            HStack(spacing: TTSpace.s3) {
                Image(systemName: "star.fill")
                    .font(.system(size: TTSize.iconMD))
                    .foregroundStyle(TTColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: TTSpace.s1 / 2) {
                    Text(viewModel.title(route))
                        .font(TTFont.headline)
                        .foregroundStyle(TTColor.ink)
                    if let line = route.line {
                        Text(line.name)
                            .font(TTFont.footnote)
                            .foregroundStyle(TTColor.inkSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                // Keeps a long name clear of the remove button drawn over the row's end while managing.
                .padding(.trailing, viewModel.isManagingFavourites ? TTSize.targetMin : 0)
                Spacer(minLength: 0)
                if !viewModel.isManagingFavourites {
                    Image(systemName: "chevron.right")
                        .font(TTFont.body)
                        .foregroundStyle(TTColor.inkSecondary)
                }
            }
            .padding(.horizontal, TTSpace.s4)
            .padding(.vertical, TTSpace.s3)
            .frame(maxWidth: .infinity, minHeight: TTSize.targetMin + TTSpace.s2, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!viewModel.isManagingFavourites)
        .accessibilityIdentifier(id)
        .overlay(alignment: .trailing) {
            if viewModel.isManagingFavourites {
                Button {
                    viewModel.removeFavourite(route)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: TTSize.iconMD))
                        .foregroundStyle(TTColor.cancelInk)
                        .frame(width: TTSize.targetMin, height: TTSize.targetMin)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .padding(.trailing, TTSpace.s2)
                .accessibilityLabel(Text("route.favourite_remove"))
                .accessibilityIdentifier("\(id).remove")
            }
        }
    }

    private var isPickingStation: Binding<Bool> {
        Binding(get: { viewModel.isPickingStation }, set: { if !$0 { viewModel.closeStations() } })
    }
}

#Preview {
    RouteFormView(
        viewModel: RouteFormViewModel(route: nil, repository: ScheduleDependencies.fixtures().stations), onSettings: {}, onShowTrains: { _ in }
    )
}

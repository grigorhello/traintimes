import SwiftUI

/// Trip details sheet (TT-118), after design/frames/trip-details.png: title and close, full route names, line and date,
/// the badge beside the freshness line, the facts card, the stop list and the alert button pinned at the bottom.
struct TripDetailsView: View {
    let viewModel: TripDetailsViewModel
    /// "Alert me" or "Manage alert": Alert setup for this trip (TT-142).
    var onAlert: () -> Void = {}

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.dismiss) private var dismiss

    /// Canvas `.sheet`: 10 pt padding, the 5 pt grabber and its 16 pt margin, then the 12 pt gap before the title row.
    private static let titleTop: CGFloat = 10 + 5 + TTSpace.s4 + TTSpace.s3
    /// The canvas close button bleeds 10 pt into the side margin.
    private static let closeBleed: CGFloat = 10
    /// Canvas `.stop`: a 20 pt marker column, 10 pt markers with a 2 pt ring, rows at least 36 pt tall.
    private static let markerColumn: CGFloat = 20
    private static let marker: CGFloat = 10
    private static let ring: CGFloat = 2
    private static let stopRow: CGFloat = 36
    private static let factGap: CGFloat = 2

    var body: some View {
        let details = viewModel.details(formatter)
        VStack(spacing: 0) {
            titleBar(details?.title)
            ScrollView {
                if let details {
                    content(details)
                        .padding(.horizontal, TTSpace.s5)
                        .padding(.bottom, TTSpace.s4)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let title = details?.alertButton {
                    Button(action: onAlert) {
                        Text(title).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttPrimary)
                    .accessibilityIdentifier("trip.alert")
                    .padding(.horizontal, TTSpace.s5)
                    .padding(.vertical, TTSpace.s2)
                    .background(TTColor.surface)
                }
            }
        }
        .background(TTColor.surface)
        .task { await viewModel.run() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.tripDetails")
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TTRadius.sheet)
        .presentationBackground(TTColor.surface)
    }

    private func titleBar(_ title: String?) -> some View {
        HStack {
            Text(title ?? "")
                .font(TTFont.navTitle)
                .monospacedDigit()
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("trip.title")
            Spacer()
            IconButton(systemName: "xmark", label: "button.close") { dismiss() }
                .accessibilityIdentifier("trip.close")
        }
        .padding(.leading, TTSpace.s5)
        .padding(.trailing, TTSpace.s5 - Self.closeBleed)
        .padding(.top, Self.titleTop)
        .padding(.bottom, TTSpace.s3)
    }

    private func content(_ details: TripDetails) -> some View {
        VStack(alignment: .leading, spacing: TTSpace.s3) {
            VStack(alignment: .leading, spacing: TTSpace.s1) {
                Text(details.routeName)
                    .font(TTFont.route)
                    .foregroundStyle(TTColor.ink)
                Text(details.lineAndDay)
                    .font(TTFont.subhead)
                    .foregroundStyle(TTColor.inkSecondary)
            }
            HStack(spacing: TTSpace.s3) {
                StatusBadge(status: details.status)
                if let mode = viewModel.freshnessMode(formatter) {
                    FreshnessLine(mode: mode)
                }
            }
            facts(details)
            stops(details)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Facts

    /// Two columns; a missing estimate leaves its cell out and never moves another fact into its place.
    private func facts(_ details: TripDetails) -> some View {
        VStack(alignment: .leading, spacing: TTSpace.s4) {
            HStack(alignment: .top, spacing: TTSpace.s3) {
                fact(String(localized: "trip.scheduled_departure"), details.scheduledDeparture)
                if let live = details.liveDeparture {
                    fact(live.label, live.value, isLate: live.isLate)
                } else {
                    emptyCell
                }
            }
            HStack(alignment: .top, spacing: TTSpace.s3) {
                fact(String(localized: "schedule.scheduled_arrival"), details.scheduledArrival)
                if let estimate = details.estimatedArrival {
                    fact(String(localized: "schedule.est_arrival"), estimate)
                } else {
                    emptyCell
                }
            }
            VStack(alignment: .leading, spacing: Self.factGap) {
                Text("trip.platform")
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                Text(details.platform)
                    .font(TTFont.body)
                    .foregroundStyle(TTColor.ink)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(TTSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.canvas, in: RoundedRectangle(cornerRadius: TTRadius.lg))
    }

    private func fact(_ label: String, _ value: String, isLate: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Self.factGap) {
            Text(label)
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
            Text(value)
                .font(TTFont.timeArrival)
                .monospacedDigit()
                .foregroundStyle(isLate ? TTColor.delayInk : TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var emptyCell: some View {
        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
    }

    // MARK: Stops

    private func stops(_ details: TripDetails) -> some View {
        VStack(alignment: .leading, spacing: TTSpace.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text("trip.stops").accessibilityAddTraits(.isHeader)
                Spacer()
                Text(details.stopsHeader)
            }
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, Self.ring)

            VStack(spacing: 0) {
                ForEach(details.stops) { stop in
                    stopRow(stop)
                }
            }

            Text(details.footnote)
                .font(TTFont.footnote)
                .monospacedDigit()
                .foregroundStyle(TTColor.inkSecondary)
                .padding(.horizontal, Self.ring)
                .padding(.top, TTSpace.s1)
        }
    }

    private func stopRow(_ stop: TripDetails.Stop) -> some View {
        HStack(spacing: TTSpace.s3) {
            stopMarker(stop)
                .frame(width: Self.markerColumn)
            Text(stop.name)
                .font(stop.isEnd ? TTFont.headline : TTFont.body)
                .foregroundStyle(TTColor.ink)
            Spacer(minLength: TTSpace.s2)
            Text(stop.time)
                .font(stop.isEnd ? TTFont.timeArrival : TTFont.body)
                .monospacedDigit()
                .strikethrough(stop.isSkipped)
                .foregroundStyle(stop.isSkipped ? TTColor.inkTertiary : TTColor.ink)
        }
        .frame(minHeight: Self.stopRow)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip.stop.\(stop.id)")
    }

    @ViewBuilder private func stopMarker(_ stop: TripDetails.Stop) -> some View {
        if stop.isSkipped {
            Image(systemName: "xmark")
                .font(TTFont.badge)
                .foregroundStyle(TTColor.cancelInk)
                .accessibilityLabel(Text("status.stop_skipped"))
        } else if stop.isEnd {
            Circle()
                .fill(TTColor.accent)
                .frame(width: Self.marker, height: Self.marker)
        } else {
            Circle()
                .strokeBorder(TTColor.controlBorder, lineWidth: Self.ring)
                .frame(width: Self.marker, height: Self.marker)
        }
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

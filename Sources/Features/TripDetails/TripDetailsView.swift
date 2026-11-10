import SwiftUI

/// Trip details sheet (TT-118, redesigned in TT-163 after design/frames/trip-details*.png): on the canvas ground, a pinned
/// header (line tile, line name, glass close button), the journey card, the stop list on one rail, and the alert button
/// floating over the content as a tinted-glass capsule. Everything scrolls; the content ends above the button.
struct TripDetailsView: View {
    let viewModel: TripDetailsViewModel
    /// "Alert me" or "Manage alert": Alert setup for this trip (TT-142).
    var onAlert: () -> Void = {}
    /// Snapshots only: a long trip scrolled to its end, as the canvas's Trip-Details-End frame.
    var startsAtEnd = false

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.dismiss) private var dismiss

    // Canvas geometry (TT-163). Rows: station 56, meta 28, status 44, stop 44.
    /// 15 pt under the 15 pt the grabber takes from the sheet's top edge.
    private static let headerTop: CGFloat = 30
    private static let headerHeight: CGFloat = 44
    private static let lineGap: CGFloat = 10
    private static let stationRow: CGFloat = 56
    private static let metaRow: CGFloat = 28
    private static let statusRow: CGFloat = 44
    private static let stopRow: CGFloat = 44
    private static let markerColumn: CGFloat = 20
    private static let railWidth: CGFloat = 2
    private static let stopDot: CGFloat = 8
    private static let dotHalo: CGFloat = 2
    private static let skippedGlyph: CGFloat = 14
    private static let alertHeight: CGFloat = 52
    /// 16 + the 52 pt button + 24 pt above the sheet's bottom edge; 40 pt when there is no button.
    private static let bottomInsetWithButton: CGFloat = 92
    private static let bottomInset: CGFloat = 40
    private static let buttonBottom: CGFloat = 24
    private static let topFade: CGFloat = 16
    private static let bottomFade: CGFloat = 112
    private static let bottomFadeOpacity = 0.72

    var body: some View {
        let details = viewModel.details(formatter)
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Above the scroll view, so the close button's glass shadow is not cut off by the top fade (a hard edge in light).
                header
                    .zIndex(1)
                ScrollView {
                    if let details {
                        content(details)
                            .padding(.horizontal, TTSpace.s5)
                            .padding(.top, TTSpace.s4)
                            .padding(.bottom, details.alertButton == nil ? Self.bottomInset : Self.bottomInsetWithButton)
                    }
                }
                .defaultScrollAnchor(startsAtEnd ? UnitPoint.bottom : nil)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [TTColor.canvas, TTColor.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.topFade)
                        .allowsHitTesting(false)
                }
            }
            if let title = details?.alertButton {
                bottomFade
                alertButton(title)
            }
        }
        // The sheet's bottom edge is the screen's: the button sits 24 pt above it, over the home indicator's area.
        .ignoresSafeArea(.container, edges: .bottom)
        .background(TTColor.canvas)
        .task { await viewModel.run() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(details?.title ?? "")
        .accessibilityIdentifier("sheet.tripDetails")
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TTRadius.sheet)
        .presentationBackground(TTColor.canvas)
    }

    // MARK: Header

    /// The line tile and its name in the Schedule header's style, and the glass close button flush with the margin.
    private var header: some View {
        HStack(spacing: Self.lineGap) {
            if let line = viewModel.route.line {
                LineTile(line: line)
                Text(verbatim: line.name)
                    .font(TTFont.lineName)
                    .tracking(-0.6)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("trip.title")
            }
            Spacer(minLength: 0)
            GlassIconButton(systemName: "xmark", label: "button.close", tint: TTColor.ink) { dismiss() }
                .accessibilityIdentifier("trip.close")
        }
        .frame(height: Self.headerHeight)
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, Self.headerTop)
    }

    private func content(_ details: TripDetails) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            journey(details)
            stops(details)
                .padding(.top, TTSpace.s5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Journey card

    /// Two stations with their times, the meta row between them, then the status row under a hairline.
    private func journey(_ details: TripDetails) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: TTSpace.s3) {
                journeyMarkers
                VStack(spacing: 0) {
                    stationRow(details.origin, time: details.departure, isStruck: details.isCancelled)
                    metaRow(details)
                    stationRow(details.destination, time: details.arrival, isStruck: details.isCancelled)
                }
            }
            .padding(.top, 6)
            Divider().overlay(TTColor.hairline)
            HStack(spacing: TTSpace.s2) {
                StatusLine(status: details.status)
                Spacer(minLength: 0)
                if let text = details.freshnessText {
                    Text(text)
                        .font(TTFont.footnote)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(height: Self.statusRow)
        }
        .padding(.horizontal, TTSpace.s4)
        .ttSheetCard()
    }

    /// The ring centred on the first row, the three dots beside the meta row, the pin centred on the second row.
    private var journeyMarkers: some View {
        let size = RouteMarkers.Size.regular
        return VStack(spacing: 0) {
            Circle()
                .strokeBorder(TTColor.inkSecondary, lineWidth: size.ringStroke)
                .frame(width: size.ring, height: size.ring)
                .frame(height: Self.stationRow)
            VStack(spacing: size.gap) {
                ForEach(0..<size.dots, id: \.self) { _ in
                    Circle().fill(TTColor.inkTertiary).frame(width: size.dot, height: size.dot)
                }
            }
            .frame(height: Self.metaRow)
            RoutePin()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: size.pin, height: size.pin)
                .frame(height: Self.stationRow)
        }
        .frame(width: Self.markerColumn)
        .accessibilityHidden(true)
    }

    private func stationRow(_ name: String, time: TripDetails.Time, isStruck: Bool) -> some View {
        HStack(spacing: TTSpace.s2) {
            Text(verbatim: name)
                .font(TTFont.headline)
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(time.value)
                    .font(TTFont.route)
                    .monospacedDigit()
                    .strikethrough(isStruck)
                    .foregroundStyle(isStruck ? TTColor.inkTertiary : time.isLate ? TTColor.delayInk : TTColor.ink)
                if let scheduled = time.scheduled {
                    Text(scheduled)
                        .font(TTFont.footnote)
                        .monospacedDigit()
                        .strikethrough()
                        .foregroundStyle(TTColor.inkTertiary)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .frame(height: Self.stationRow)
    }

    /// "in 20 min · Platform — · Express" on the left, the trip length on the right.
    private func metaRow(_ details: TripDetails) -> some View {
        HStack(spacing: TTSpace.s2) {
            HStack(spacing: TTSpace.s1 + 2) {
                if let countdown = details.countdown {
                    Text(countdown)
                        .font(TTFont.subhead.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                    separator
                }
                Text(platformText(details))
                    .font(TTFont.subhead)
                    .monospacedDigit()
                if details.isExpress {
                    separator
                    HStack(spacing: TTSpace.s1) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: TTSize.iconSM, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("tag.express")
                            .font(TTFont.subhead.weight(.semibold))
                    }
                    .foregroundStyle(details.isCancelled ? TTColor.inkTertiary : TTColor.accent)
                }
            }
            // A long run of facts (a three-digit countdown, a platform, Express) shrinks before it clips or pushes the trip length.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(details.tripLength)
                .font(TTFont.footnote)
                .monospacedDigit()
                .foregroundStyle(TTColor.inkSecondary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
        .frame(height: Self.metaRow)
    }

    /// A separator glyph, not copy.
    private var separator: some View {
        Text(verbatim: "·")
            .font(TTFont.subhead)
            .foregroundStyle(TTColor.inkTertiary)
    }

    /// "Platform" in ink-secondary; the number semibold in ink, or the dash in ink-tertiary until GO publishes it.
    private func platformText(_ details: TripDetails) -> AttributedString {
        var text = AttributedString(details.platform)
        text.foregroundColor = TTColor.inkSecondary
        if let range = text.range(of: details.platformValue, options: .backwards) {
            if details.hasPlatform {
                text[range].foregroundColor = TTColor.ink
                text[range].font = TTFont.subhead.weight(.semibold)
            } else {
                text[range].foregroundColor = TTColor.inkTertiary
            }
        }
        return text
    }

    // MARK: Stops

    private func stops(_ details: TripDetails) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(details.stopCount).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(details.stopsHeader)
            }
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, TTSpace.s1)

            VStack(spacing: 0) {
                ForEach(Array(details.stops.enumerated()), id: \.element.id) { index, stop in
                    stopRow(stop, isFirst: index == 0, isStruck: details.isTrainCancelled)
                }
            }
            .background(alignment: .topLeading) { rail(stops: details.stops.count) }
            .padding(.horizontal, TTSpace.s4)
            .padding(.vertical, 6)
            .ttSheetCard()
            .padding(.top, 6)

            Text(details.footnote)
                .font(TTFont.footnote)
                .monospacedDigit()
                .foregroundStyle(TTColor.inkSecondary)
                .padding(.horizontal, TTSpace.s1)
                .padding(.top, 10)
        }
    }

    /// The 2 pt rail from just under the origin ring to just above the destination pin's head, down the marker column.
    private func rail(stops count: Int) -> some View {
        let ring = RouteMarkers.Size.regular.ring
        let length = max(0, Self.stopRow * CGFloat(count - 1) - ring / 2 - 10)
        return Rectangle()
            .fill(TTColor.controlBorder.opacity(0.38))
            .frame(width: Self.railWidth, height: length)
            .offset(x: Self.markerColumn / 2 - Self.railWidth / 2, y: Self.stopRow / 2 + ring / 2)
            .accessibilityHidden(true)
    }

    private func stopRow(_ stop: TripDetails.Stop, isFirst: Bool, isStruck: Bool) -> some View {
        let isDimmed = stop.isSkipped || isStruck
        let font = stop.isEnd ? TTFont.headline : TTFont.body
        return HStack(spacing: TTSpace.s3) {
            stopMarker(stop, isFirst: isFirst)
                .frame(width: Self.markerColumn, height: Self.stopRow)
            Text(verbatim: stop.name)
                .font(font)
                .foregroundStyle(stop.isSkipped ? TTColor.inkTertiary : TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: TTSpace.s2)
            Text(stop.time)
                .font(font)
                .monospacedDigit()
                .strikethrough(isDimmed)
                .foregroundStyle(isDimmed ? TTColor.inkTertiary : TTColor.ink)
        }
        .frame(height: Self.stopRow)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip.stop.\(stop.id)")
    }

    /// The origin ring, a dot with a surface halo over the rail, the destination pin; a skipped stop is a cross on a disc.
    @ViewBuilder private func stopMarker(_ stop: TripDetails.Stop, isFirst: Bool) -> some View {
        let size = RouteMarkers.Size.regular
        if stop.isSkipped {
            Image(systemName: "xmark")
                .font(.system(size: Self.skippedGlyph, weight: .semibold))
                .foregroundStyle(TTColor.cancelInk)
                .frame(width: Self.markerColumn, height: Self.markerColumn)
                .background(TTColor.surface, in: Circle())
                .accessibilityLabel(Text("status.stop_skipped"))
        } else if stop.isEnd && isFirst {
            Circle()
                .strokeBorder(TTColor.inkSecondary, lineWidth: size.ringStroke)
                .frame(width: size.ring, height: size.ring)
                .background(TTColor.surface, in: Circle())
        } else if stop.isEnd {
            RoutePin()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: size.pin, height: size.pin)
        } else {
            Circle()
                .fill(TTColor.controlBorder)
                .frame(width: Self.stopDot, height: Self.stopDot)
                .padding(Self.dotHalo)
                .background(TTColor.surface, in: Circle())
        }
    }

    // MARK: Alert button

    /// The canvas's `.edge-bottom`: the content fades into the ground under the button, as under the tab bar.
    private var bottomFade: some View {
        LinearGradient(
            colors: [TTColor.canvas.opacity(0), TTColor.canvas.opacity(Self.bottomFadeOpacity)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: Self.bottomFade)
        .allowsHitTesting(false)
    }

    /// "Alert me" or "Manage alert": a 52 pt capsule, tinted Liquid Glass on iOS 26 and later, the solid accent before it.
    private func alertButton(_ title: String) -> some View {
        Button(action: onAlert) {
            Text(title)
                .font(TTFont.headline)
                .foregroundStyle(TTColor.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: Self.alertHeight)
                .ttGlass(tint: TTColor.accent, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("trip.alert")
        .padding(.horizontal, TTSpace.s5)
        .padding(.bottom, Self.buttonBottom)
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

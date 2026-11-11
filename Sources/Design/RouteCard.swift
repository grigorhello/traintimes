import SwiftUI

/// The route card (D48), drawn like a maps route box: a ring for the origin, dots, a pin for the destination, the two
/// stations split by a hairline, and the swap button to the right. No "From"/"To" words: the markers say which is which.
/// Schedule shows it as its header and the route form uses it for its fields. A tap on a station row makes that row the
/// search field and the swap button turns into the X that cancels (TT-161, D54). While one is open the suggestions
/// hang right under the card as one surface with it, so the card squares off its bottom corners. The swap button plays
/// `SwapMotion` (TT-165, D59): the names trade rows, the arrows turn, the rail lights up.
struct RouteCard: View {
    enum Stop {
        case from, to
    }

    /// The row that is the search field while the picker is open.
    struct Picking {
        let stop: Stop
        /// What the rider typed.
        let query: String
        /// The current station, shown as a grey hint that the first keystroke replaces; nil on first use, which starts on the
        /// placeholder.
        let current: String?
        let cancelID: String
        let onQuery: (String) -> Void
        let onSubmit: () -> Void
        let onCancel: () -> Void
    }

    let from: String?
    let to: String?
    /// Shown in ink-tertiary while a station is not chosen yet.
    var fromPlaceholder: LocalizedStringKey = "route.choose_from"
    var toPlaceholder: LocalizedStringKey = "route.choose_to"
    let fromID: String
    let toID: String
    /// A tap on a station row: the picker for that field. Also on the other row while one is open.
    let onTap: (Stop) -> Void
    /// Set while the picker is open.
    var picking: Picking?
    var canSwap = true
    let swapID: String
    let onSwap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.swapFrozenAt) private var frozenAt
    /// The swap motion in progress, nil at rest.
    @State private var swap = SwapRun()

    /// Canvas `.rrow`: 48 pt per station.
    static let rowHeight: CGFloat = 48
    /// How far a long name (Brampton Innovation District GO) may shrink to stay on one line.
    private static let nameMinimumScale: CGFloat = 0.75
    /// Canvas `.rcard`: a 20 pt marker column.
    private static let markerColumn: CGFloat = 20
    /// The raised pill reaches this far past a name on each side (canvas `.stn-in`), and the names column is clipped there.
    private static let pillInset: CGFloat = 8
    private static let pillRadius: CGFloat = 10

    var body: some View {
        // Paused (no frames) unless a swap is playing; the poses come from the clock, not from SwiftUI animations.
        TimelineView(.animation(paused: swap.start == nil)) { context in
            card(pose: pose(at: context.date))
        }
    }

    private func card(pose: SwapMotion.Pose) -> some View {
        // While a station is being picked the suggestions hang right under the card, so it squares off its bottom corners.
        Card(padding: 0, joinsBelow: picking != nil) {
            HStack(spacing: TTSpace.s3) {
                // The ring centred on the first row; the pin lands centred on the second.
                RouteMarkers(dotLights: pose.dotLights, pinScale: pose.pinScale)
                    .padding(.top, (Self.rowHeight - RouteMarkers.Size.regular.ring) / 2)
                    .frame(width: Self.markerColumn, height: 2 * Self.rowHeight, alignment: .top)
                // The names stay inside their column (and the pill's 8 pt inset), so a name arcing sideways never covers the
                // rail. The one moving up is drawn in front.
                VStack(spacing: 0) {
                    row(.from, station: from, placeholder: fromPlaceholder, id: fromID, pose: pose.from).zIndex(2)
                    hairline
                    row(.to, station: to, placeholder: toPlaceholder, id: toID, pose: pose.to).zIndex(1)
                }
                .padding(.horizontal, Self.pillInset)
                .clipped()
                .padding(.horizontal, -Self.pillInset)
                if let picking {
                    GlassIconButton(systemName: "xmark", label: "button.cancel", tint: TTColor.ink, action: picking.onCancel)
                        .accessibilityIdentifier(picking.cancelID)
                        .transition(.pickerCancelButton)
                } else {
                    GlassIconButton(
                        systemName: "arrow.up.arrow.down", label: "route.swap", glyphDegrees: pose.arrowDegrees,
                        action: { tapSwap() }
                    )
                    .disabled(!canSwap)
                    .scaleEffect(pose.buttonScale)
                    .accessibilityIdentifier(swapID)
                    .transition(.pickerSwapButton)
                }
            }
            .padding(.leading, TTSpace.s4)
            .padding(.trailing, TTSpace.s2)
        }
        // The corners, the swap button and the X move together with the list opening or closing below (D54).
        .animation(PickerMotion.animation(opening: picking != nil), value: picking != nil)
    }

    // MARK: Swap motion (TT-165, D59)

    /// A row and its hairline: how far a name travels to take the other's place.
    private var rowStep: CGFloat { Self.rowHeight + 1 / max(displayScale, 1) }

    /// The tap: the motion starts, then the route is swapped (the card only shows the names traded once the data says so, so
    /// the order does not matter). A tap during a motion carries on from where it is. Reduce Motion plays none of it: the
    /// names cross-fade (`NameCrossfade`).
    private func tapSwap() {
        if !reduceMotion {
            let now = Date()
            var carry = SwapMotion.Carry()
            if let start = swap.start {
                carry = SwapMotion.carry(at: now.timeIntervalSince(start), step: rowStep, from: swap.carry)
            }
            swap = SwapRun(start: now, from: from, to: to, carry: carry)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(SwapMotion.duration))
                // A newer tap has its own run.
                if swap.start == now { swap = SwapRun() }
            }
        }
        onSwap()
    }

    private func pose(at date: Date) -> SwapMotion.Pose {
        guard picking == nil else { return SwapMotion.rest }
        if let frozenAt { return SwapMotion.pose(at: frozenAt, step: rowStep) }
        guard let start = swap.start else { return SwapMotion.rest }
        var pose = SwapMotion.pose(at: date.timeIntervalSince(start), step: rowStep, carry: swap.carry)
        // Until the card shows the stations the other way round than at the tap (Schedule swaps a moment later, in a task),
        // each name stays where the tap found it: at rest, or mid-flight on a second tap (the carry, read back).
        if from != swap.to || to != swap.from {
            pose.from = swap.carry.to
            pose.to = swap.carry.from
        }
        return pose
    }

    /// The station as a button read as its field name and station, or the search field while it is the active row.
    @ViewBuilder
    private func row(
        _ stop: Stop, station: String?, placeholder: LocalizedStringKey, id: String, pose: SwapMotion.NamePose
    ) -> some View {
        if let picking, picking.stop == stop {
            let placeholderKey: String.LocalizationValue = stop == .from ? "route.choose_from" : "route.choose_to"
            StationField(
                text: picking.query,
                placeholder: String(localized: placeholderKey),
                current: picking.current,
                identifier: id,
                onChange: picking.onQuery,
                onSubmit: picking.onSubmit
            )
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
        } else {
            let field: LocalizedStringKey = stop == .from ? "route.from" : "route.to"
            Button { onTap(stop) } label: {
                name(station, placeholder: placeholder, pose: pose)
                    .modifier(NameCrossfade(isOn: reduceMotion, key: station))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(field))
            .accessibilityValue(station.map { Text(verbatim: $0) } ?? Text(placeholder))
            .accessibilityIdentifier(id)
        }
    }

    /// The station in headline, or the placeholder in body ink-tertiary, on one line. While it trades rows it is moved,
    /// pushed aside and enlarged about its own centre, on a raised pill; the row (and its tap target) stays put.
    private func name(_ station: String?, placeholder: LocalizedStringKey, pose: SwapMotion.NamePose) -> some View {
        Group {
            if let station {
                Text(verbatim: station)
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.ink)
            } else {
                Text(placeholder)
                    .font(TTFont.body)
                    .foregroundStyle(TTColor.inkTertiary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(Self.nameMinimumScale)
        .background {
            if pose.pill > 0 {
                RoundedRectangle(cornerRadius: Self.pillRadius)
                    .fill(TTColor.surfaceRaised)
                    .shadow(color: colorScheme == .dark ? .black.opacity(0.5) : TTColor.ink.opacity(0.14), radius: 7, x: 0, y: 6)
                    .opacity(pose.pill)
                    .padding(EdgeInsets(top: -2, leading: -Self.pillInset, bottom: -2, trailing: -Self.pillInset))
            }
        }
        .scaleEffect(pose.scale)
        .offset(x: pose.x, y: pose.y)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
    }

    private var hairline: some View {
        Divider().overlay(TTColor.hairline)
    }
}

/// A swap in progress in one route card: when its button was tapped, the stations at that moment, and what it carries over
/// from a motion that tap interrupted.
private struct SwapRun: Equatable {
    var start: Date?
    var from: String?
    var to: String?
    var carry = SwapMotion.Carry()
}

/// Reduce Motion: a station name that changes cross-fades on `TTMotion.fade` and does not move.
private struct NameCrossfade: ViewModifier {
    let isOn: Bool
    let key: String?

    func body(content: Content) -> some View {
        if isOn {
            ZStack { content.id(key).transition(.opacity) }
                .animation(TTMotion.fade, value: key)
        } else {
            content
        }
    }
}

/// The ring, dots and pin down the left of a route (D48): full size in the route card, mini in the Recent rows.
struct RouteMarkers: View {
    enum Size {
        case regular, mini

        var ring: CGFloat { self == .regular ? 12 : 10 }
        var ringStroke: CGFloat { self == .regular ? 2.5 : 2 }
        var dot: CGFloat { self == .regular ? 3 : 2 }
        var dots: Int { self == .regular ? 3 : 2 }
        var gap: CGFloat { self == .regular ? 6 : 3 }
        var pin: CGFloat { self == .regular ? 20 : 14 }
    }

    var size: Size = .regular
    /// The swap motion (TT-165): how lit each dot is (0 to 1: accent and 1.8 times its size) and how big the pin is, scaled
    /// from near its tip. At rest: none lit, 1.
    var dotLights: [Double] = []
    var pinScale: CGFloat = 1

    var body: some View {
        VStack(spacing: size.gap) {
            Circle()
                .strokeBorder(TTColor.inkSecondary, lineWidth: size.ringStroke)
                .frame(width: size.ring, height: size.ring)
            ForEach(0..<size.dots, id: \.self) { index in
                let light = index < dotLights.count ? dotLights[index] : 0
                Circle()
                    .fill(TTColor.inkTertiary)
                    .overlay { Circle().fill(TTColor.accent).opacity(light) }
                    .frame(width: size.dot, height: size.dot)
                    .scaleEffect(1 + 0.8 * light)
            }
            RoutePin()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: size.pin, height: size.pin)
                .scaleEffect(pinScale, anchor: UnitPoint(x: 0.5, y: 0.9))
        }
        .accessibilityHidden(true)
    }
}

/// The destination pin with its hole, from the canvas SVG (24 pt view box).
struct RoutePin: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(12, 22.5))
        path.addCurve(to: point(19.5, 9.8), control1: point(12, 22.5), control2: point(19.5, 15.9))
        // Over the top, right to left.
        path.addRelativeArc(center: point(12, 9.8), radius: 7.5 * scale, startAngle: .degrees(0), delta: .degrees(-180))
        path.addCurve(to: point(12, 22.5), control1: point(4.5, 15.9), control2: point(12, 22.5))
        path.closeSubpath()
        // The hole, cut out by the even-odd fill.
        path.addEllipse(in: CGRect(origin: point(12 - 2.8, 9.8 - 2.8), size: CGSize(width: 5.6 * scale, height: 5.6 * scale)))
        return path
    }
}

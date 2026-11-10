import SwiftUI

/// The route card (D48), drawn like a maps route box: a ring for the origin, dots, a pin for the destination, the two
/// stations split by a hairline, and the swap button to the right. No "From"/"To" words: the markers say which is which.
/// Schedule shows it as its header and the route form uses it for its fields. A tap on a station row makes that row the
/// search field and the swap button turns into the X that cancels (TT-161, D52).
struct RouteCard: View {
    enum Stop {
        case from, to
    }

    /// The row that is the search field while the picker is open.
    struct Picking {
        let stop: Stop
        /// What the rider typed.
        let query: String
        /// The current station, shown selected so typing replaces it; nil on first use, which starts on the placeholder.
        let selected: String?
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

    /// Canvas `.rrow`: 48 pt per station.
    static let rowHeight: CGFloat = 48
    /// How far a long name (Brampton Innovation District GO) may shrink to stay on one line.
    private static let nameMinimumScale: CGFloat = 0.75
    /// Canvas `.rcard`: a 20 pt marker column.
    private static let markerColumn: CGFloat = 20

    var body: some View {
        Card(padding: 0) {
            HStack(spacing: TTSpace.s3) {
                // The ring centred on the first row; the pin lands centred on the second.
                RouteMarkers()
                    .padding(.top, (Self.rowHeight - RouteMarkers.Size.regular.ring) / 2)
                    .frame(width: Self.markerColumn, height: 2 * Self.rowHeight, alignment: .top)
                VStack(spacing: 0) {
                    row(.from, station: from, placeholder: fromPlaceholder, id: fromID)
                    hairline
                    row(.to, station: to, placeholder: toPlaceholder, id: toID)
                }
                if let picking {
                    GlassIconButton(systemName: "xmark", label: "button.cancel", tint: TTColor.ink, action: picking.onCancel)
                        .accessibilityIdentifier(picking.cancelID)
                } else {
                    GlassIconButton(systemName: "arrow.up.arrow.down", label: "route.swap", action: onSwap)
                        .disabled(!canSwap)
                        .accessibilityIdentifier(swapID)
                }
            }
            .padding(.leading, TTSpace.s4)
            .padding(.trailing, TTSpace.s2)
        }
    }

    /// The station as a button read as its field name and station, or the search field while it is the active row.
    @ViewBuilder
    private func row(_ stop: Stop, station: String?, placeholder: LocalizedStringKey, id: String) -> some View {
        if let picking, picking.stop == stop {
            let placeholderKey: String.LocalizationValue = stop == .from ? "route.choose_from" : "route.choose_to"
            StationField(
                text: picking.query,
                placeholder: String(localized: placeholderKey),
                selected: picking.selected,
                identifier: id,
                onChange: picking.onQuery,
                onSubmit: picking.onSubmit
            )
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
        } else {
            let field: LocalizedStringKey = stop == .from ? "route.from" : "route.to"
            Button { onTap(stop) } label: {
                name(station, placeholder: placeholder).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(field))
            .accessibilityValue(station.map { Text(verbatim: $0) } ?? Text(placeholder))
            .accessibilityIdentifier(id)
        }
    }

    /// The station in headline, or the placeholder in body ink-tertiary, on one line.
    private func name(_ station: String?, placeholder: LocalizedStringKey) -> some View {
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
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
    }

    private var hairline: some View {
        Divider().overlay(TTColor.hairline)
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

    var body: some View {
        VStack(spacing: size.gap) {
            Circle()
                .strokeBorder(TTColor.inkSecondary, lineWidth: size.ringStroke)
                .frame(width: size.ring, height: size.ring)
            ForEach(0..<size.dots, id: \.self) { _ in
                Circle()
                    .fill(TTColor.inkTertiary)
                    .frame(width: size.dot, height: size.dot)
            }
            RoutePin()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: size.pin, height: size.pin)
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

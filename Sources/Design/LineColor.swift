import SwiftUI

/// GO Transit's own line colours (D49). Riders know the lines by them, and the feed's `route_color` differs, so the colour
/// comes from this table, keyed by line id; a line it does not list uses the feed's colour, else ink-secondary.
enum GOLineColor {
    static let hex: [String: String] = [
        "LW": "#8B1A31",  // Lakeshore West
        "LE": "#EA3624",  // Lakeshore East
        "MI": "#E6853E",  // Milton
        "KI": "#3A8346",  // Kitchener
        "RH": "#4397C3",  // Richmond Hill
        "BR": "#143664",  // Barrie
        "ST": "#724715",  // Stouffville
    ]

    static func color(for line: Line) -> Color {
        (hex[line.id] ?? line.colorHex).flatMap { Color(hex: $0) } ?? TTColor.inkSecondary
    }
}

extension Color {
    /// A colour from "#RRGGBB" (the "#" is optional); nil for anything else.
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255
        )
    }
}

/// The line's code in a rounded tile in its own colour (D49), as on the canvas's `.line-tile`.
struct LineTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let line: Line

    static let size: CGFloat = 32
    private static let radius: CGFloat = 9

    var body: some View {
        Text(verbatim: line.id)
            .font(TTFont.lineCode)
            .tracking(0.4)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(GOLineColor.color(for: line), in: RoundedRectangle(cornerRadius: Self.radius))
            // A dark line colour on the dark canvas keeps an edge.
            .overlay(
                RoundedRectangle(cornerRadius: Self.radius)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

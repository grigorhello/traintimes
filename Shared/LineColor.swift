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

    /// The line's colour mixed toward white by `amount` (0 to 1, in sRGB like CSS `color-mix`): the first launch's 4 pt
    /// lines and rails in dark mode take 42 % (TT-206).
    static func color(for line: Line, towardWhite amount: Double) -> Color {
        guard amount > 0, let hex = hex[line.id] ?? line.colorHex,
              let value = UInt32(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex, radix: 16)
        else { return color(for: line) }
        func mix(_ shift: UInt32) -> Double {
            let channel = Double((value >> shift) & 0xFF) / 255
            return channel + (1 - channel) * amount
        }
        return Color(red: mix(16), green: mix(8), blue: mix(0))
    }

    /// GO's lines by the names the feed gives them, clockwise round Union as on GO's own map (TT-200, D83): the order of
    /// the picker's line sections.
    static let lines: [(id: String, name: String)] = [
        ("LW", "Lakeshore West"), ("MI", "Milton"), ("KI", "Kitchener"), ("BR", "Barrie"),
        ("RH", "Richmond Hill"), ("ST", "Stouffville"), ("LE", "Lakeshore East"),
    ]

    /// The line a station's line name stands for, with its id so it takes its GO colour; a name GO does not list keeps
    /// the name as its id (ink-secondary).
    static func line(named name: String) -> Line {
        Line(id: lines.first { $0.name == name }?.id ?? name, name: name, colorHex: nil)
    }

    /// Line names in GO's order; names it does not list go last, alphabetically.
    static func ordered(_ names: [String]) -> [String] {
        let rank = { (name: String) in lines.firstIndex { $0.name == name } ?? lines.count }
        return names.sorted { (rank($0), $0) < (rank($1), $1) }
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
    /// The app's 32 pt tile, and the widgets' 26 pt (Departures) and 20 pt (Next train) ones (TT-183).
    enum Kind: Sendable {
        case standard, widget, widgetSmall

        var side: CGFloat {
            switch self {
            case .standard: LineTile.size
            case .widget: 26
            case .widgetSmall: 20
            }
        }

        var radius: CGFloat {
            switch self {
            case .standard: 9
            case .widget: 8
            case .widgetSmall: 6
            }
        }

        var font: Font {
            switch self {
            case .standard, .widget: TTFont.lineCode
            case .widgetSmall: TTFont.lineCodeTiny
            }
        }

        var tracking: CGFloat {
            switch self {
            case .standard: 0.4
            case .widget: 0
            case .widgetSmall: 0.3
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    let line: Line
    var kind: Kind = .standard
    /// Where iOS draws a widget in one colour (a tinted or clear Home Screen, TT-183): the code in an outline, no fill.
    var isOutline = false

    static let size: CGFloat = 32

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: kind.radius)
        Text(verbatim: line.id)
            .font(kind.font)
            .tracking(kind.tracking)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(isOutline ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            .frame(width: kind.side, height: kind.side)
            .background {
                if isOutline {
                    shape.strokeBorder(.primary, lineWidth: 1.5)
                } else {
                    shape.fill(GOLineColor.color(for: line))
                }
            }
            // A dark line colour on the dark canvas keeps an edge.
            .overlay(shape.strokeBorder(.white.opacity(colorScheme == .dark && !isOutline ? 0.16 : 0), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

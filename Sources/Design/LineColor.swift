import SwiftUI

extension Color {
    /// A line colour from feed metadata ("#111827"). Nil when the value is not a 6-digit hex colour, or when the colour
    /// would vanish on the canvas (very dark in dark mode, very light in light mode); the header then uses ink-secondary.
    init?(lineHex hex: String, on colorScheme: ColorScheme) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let lightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        guard colorScheme == .dark ? lightness >= 0.25 : lightness <= 0.85 else { return nil }
        self.init(red: red, green: green, blue: blue)
    }
}

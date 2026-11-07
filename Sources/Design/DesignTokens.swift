import SwiftUI

// Train Times design tokens. Colours live in Colors.xcassets (light and dark); everything else is here.
// Source of truth: the design canvas (Component sheet) and "Train Times v1 — Screen Requirements", section Visual tokens.

enum TTColor {
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let surfaceRaised = Color("SurfaceRaised")
    static let hairline = Color("Hairline")
    static let controlBorder = Color("ControlBorder")
    static let ink = Color("Ink")
    static let inkSecondary = Color("InkSecondary")
    static let inkTertiary = Color("InkTertiary")
    static let accent = Color("Accent")
    static let accentPressed = Color("AccentPressed")
    static let onAccent = Color("OnAccent")
    static let accentSoft = Color("AccentSoft")
    static let ontimeInk = Color("OntimeInk")      // neutral on purpose: green is the brand, not a status
    static let ontimeFill = Color("OntimeFill")
    static let delayInk = Color("DelayInk")
    static let delayFill = Color("DelayFill")
    static let cancelInk = Color("CancelInk")
    static let cancelFill = Color("CancelFill")
    static let scheduledInk = Color("ScheduledInk")
    static let scheduledFill = Color("ScheduledFill")
}

enum TTSpace {
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16
    static let s5: CGFloat = 20, s6: CGFloat = 24, s8: CGFloat = 32, s12: CGFloat = 48
}

enum TTRadius {
    static let sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 18, sheet: CGFloat = 28
}

enum TTSize {
    static let targetMin: CGFloat = 44      // every tappable thing
    static let iconMD: CGFloat = 22, iconSM: CGFloat = 15
    static let rowMin: CGFloat = 76
    static let dayCell: CGFloat = 44        // 7-day strip
}

/// Text styles. Sizes are the default (Large) Dynamic Type values; always pass `relativeTo:` so they scale.
enum TTFont {
    static let timeLead   = Font.system(size: 34, weight: .semibold, design: .default)   // next train's time
    static let timeRow    = Font.system(size: 32, weight: .semibold)                      // other trains' time
    static let timeArrival = Font.system(size: 17, weight: .semibold)
    static let largeTitle = Font.system(size: 34, weight: .semibold)
    static let route      = Font.system(size: 22, weight: .semibold)                      // "Oakville to Union"
    static let navTitle   = Font.system(size: 17, weight: .semibold)
    static let headline   = Font.system(size: 17, weight: .semibold)
    static let body       = Font.system(size: 17, weight: .regular)
    static let subhead    = Font.system(size: 15, weight: .regular)
    static let footnote   = Font.system(size: 13, weight: .regular)
    static let badge      = Font.system(size: 13, weight: .semibold)
    // Times use monospaced digits: .monospacedDigit() on every time label.
}

/// Timeline geometry (Schedule screen). See requirements doc, Schedule screen (timeline).
enum TTTimeline {
    static let pointsPerMinute: CGFloat = 7          // 6 on compact phones (375 pt wide)
    static let pointsPerMinuteCompact: CGFloat = 6
    static let gridlineEveryMinutes = 15
    static let minCardGap: CGFloat = 16              // cards never touch; zoom the segment locally if they would
    static let connectorLength: CGFloat = 14         // marker to card
    static let foldAfterMinutes = 30                 // gaps longer than this fold to a dashed 30-min segment
    static let pillLabelHideDistance: CGFloat = 22   // gridline label hides within this distance of a pill
    static let leftInset: CGFloat = 12
    static let nowOffsetFromTopMinutes = 2           // initial scroll puts Now about 2 min below the top edge
    static let foregroundRefreshSeconds: TimeInterval = 30
}

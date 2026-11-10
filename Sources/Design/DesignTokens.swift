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
    static let ontimeInk = Color("OntimeInk")      // green, the accent: "On time" reads as good news (TT-156, D49)
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
    static let sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 18, xl: CGFloat = 26, sheet: CGFloat = 28
}

enum TTSize {
    static let targetMin: CGFloat = 44      // every tappable thing
    static let iconMD: CGFloat = 22, iconSM: CGFloat = 15
    /// SF Symbol size in `IconButton` (gear, swap, star, bell, close). The canvas draws its glyphs inside the 22 pt
    /// icon-md box; an SF Symbol at 18 pt matches their drawn size in the frames (TT-116).
    static let iconButtonGlyph: CGFloat = 18
    static let rowMin: CGFloat = 76
    static let appMark: CGFloat = 36        // app icon in Settings › About
}

/// Text styles at the default (Large) Dynamic Type sizes. Fixed sizes, no Dynamic Type scaling (D23, D45).
enum TTFont {
    static let timeLead   = Font.system(size: 34, weight: .semibold, design: .default)   // next train's time
    static let timeRow    = Font.system(size: 32, weight: .semibold)                      // other trains' time
    static let timeArrival = Font.system(size: 17, weight: .semibold)                     // arrival times; also on timeline cards (D50)
    static let largeTitle = Font.system(size: 34, weight: .semibold)
    static let route      = Font.system(size: 22, weight: .semibold)                      // "Oakville to Union"
    static let navTitle   = Font.system(size: 17, weight: .semibold)
    static let headline   = Font.system(size: 17, weight: .semibold)
    static let body       = Font.system(size: 17, weight: .regular)
    static let subhead    = Font.system(size: 15, weight: .regular)
    static let footnote   = Font.system(size: 13, weight: .regular)
    static let badge      = Font.system(size: 13, weight: .semibold)
    static let badgeLarge = Font.system(size: 15, weight: .semibold)                          // status line on a timeline card (D50)
    static let lineName   = Font.system(size: 26, weight: .bold)                              // the line above the route card
    static let lineCode   = Font.system(size: 13, weight: .bold)                              // the code in the line tile
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
    static let pillLabelHideDistance: CGFloat = 22   // gridline label hides within this distance of the Now label
    static let leftInset: CGFloat = 12
    static let labelWidth: CGFloat = 40              // the gridline time column (40 pt after the 12 pt inset)
    static let nowOffsetFromTopMinutes = 5           // initial scroll puts Now about 5 min (35 pt) below the top edge
    static let foregroundRefreshSeconds: TimeInterval = 30
}

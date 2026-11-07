import SwiftUI

/// Trip status from the closed set (D12). Colour + word + icon, never colour alone.
enum TripStatus: Hashable, Sendable {
    case onTime
    case delayed(minutes: Int)
    case cancelled
    case stopSkipped
    case scheduled
    /// `time` is already formatted by the one time formatter.
    case lastReported(time: String)
    case offline

    var text: String {
        switch self {
        case .onTime: String(localized: "status.on_time")
        case .delayed(let minutes): String(format: String(localized: "status.delayed"), minutes)
        case .cancelled: String(localized: "status.cancelled")
        case .stopSkipped: String(localized: "status.stop_skipped")
        case .scheduled: String(localized: "status.scheduled")
        case .lastReported(let time): String(format: String(localized: "status.last_reported"), time)
        case .offline: String(localized: "status.offline")
        }
    }

    var symbol: String {
        switch self {
        case .onTime: "checkmark.circle.fill"
        case .delayed: "clock.badge.exclamationmark"
        case .cancelled, .stopSkipped: "xmark.circle.fill"
        case .scheduled, .lastReported: "clock"
        case .offline: "wifi.slash"
        }
    }

    var ink: Color {
        switch self {
        case .onTime: TTColor.ontimeInk
        case .delayed: TTColor.delayInk
        case .cancelled, .stopSkipped: TTColor.cancelInk
        case .scheduled, .lastReported, .offline: TTColor.scheduledInk
        }
    }

    var fill: Color {
        switch self {
        case .onTime: TTColor.ontimeFill
        case .delayed: TTColor.delayFill
        case .cancelled, .stopSkipped: TTColor.cancelFill
        case .scheduled, .lastReported, .offline: TTColor.scheduledFill
        }
    }
}

struct StatusBadge: View {
    let status: TripStatus

    var body: some View {
        Label {
            Text(status.text).monospacedDigit()
        } icon: {
            Image(systemName: status.symbol)
        }
        .labelStyle(BadgeLabelStyle())
        .font(TTFont.badge)
        .foregroundStyle(status.ink)
        .padding(.horizontal, TTSpace.s2)
        .padding(.vertical, TTSpace.s1)
        .background(status.fill, in: Capsule())
    }
}

/// Express is a tag, not a status (D21). Icon only when a row carries more tags.
struct ExpressTag: View {
    var iconOnly = false

    var body: some View {
        Group {
            if iconOnly {
                Image(systemName: "bolt.fill")
                    .accessibilityLabel(Text("tag.express"))
            } else {
                Label { Text("tag.express") } icon: { Image(systemName: "bolt.fill") }
                    .labelStyle(BadgeLabelStyle())
            }
        }
        .font(TTFont.badge)
        .foregroundStyle(TTColor.inkSecondary)
        .padding(.horizontal, TTSpace.s2)
        .padding(.vertical, TTSpace.s1)
        .overlay(Capsule().strokeBorder(TTColor.controlBorder, lineWidth: 1))
    }
}

/// Minute pill on the timeline rail. `time` is formatted by the one time formatter.
struct TimePill: View {
    enum Style: Sendable { case next, later, slipped, cancelled }

    let time: String
    var style: Style = .later

    var body: some View {
        Text(time)
            .font(TTFont.badge)
            .monospacedDigit()
            .strikethrough(style == .slipped || style == .cancelled)
            .foregroundStyle(ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
    }

    private var ink: Color {
        switch style {
        case .next: TTColor.onAccent
        case .later: TTColor.accent
        case .slipped: TTColor.delayInk
        case .cancelled: TTColor.cancelInk
        }
    }

    private var fill: Color {
        switch style {
        case .next: TTColor.accent
        case .later: TTColor.accentSoft
        case .slipped: TTColor.delayFill
        case .cancelled: TTColor.cancelFill
        }
    }
}

private struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: TTSpace.s1) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview("Badges") { BadgesGallery() }
#Preview("Badges dark") { BadgesGallery().preferredColorScheme(.dark) }

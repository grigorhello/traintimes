import SwiftUI

/// The ride strip under the day strip while a ride runs (TT-172, *Live-Schedule*): "On board · 5:13 PM train" with the Live
/// dot, the next stop, the minutes to it, your stop and its time, and a chevron. A tap opens Trip details in ride mode.
struct RideStripView: View {
    let strip: RideStrip
    var onOpen: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: TTSpace.s3) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        LiveDot(isLive: strip.isLive)
                        Text(strip.title)
                            .font(TTFont.badge)
                            .foregroundStyle(TTColor.accent)
                    }
                    Text(strip.next)
                        .font(TTFont.headline)
                        .tracking(-0.4)
                        .foregroundStyle(TTColor.ink)
                }
                .lineLimit(1)
                .monospacedDigit()
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(strip.countdown)
                        .font(TTFont.route)
                        .tracking(-0.4)
                        .foregroundStyle(TTColor.accent)
                        .contentTransition(.numericText(countsDown: true))
                    Text(destination)
                        .font(TTFont.footnote)
                }
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .animation(.easeOut(duration: 0.15), value: strip.countdown)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TTColor.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
            .background(TTColor.accentSoft, in: RoundedRectangle(cornerRadius: TTRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: TTRadius.lg)
                    .strokeBorder(TTColor.accent.opacity(colorScheme == .dark ? 0.20 : 0.14), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: TTRadius.lg))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.ride")
    }

    /// "**Clarkson** 5:43 PM": the station semibold in ink, the time in ink-secondary.
    private var destination: AttributedString {
        var name = AttributedString(strip.destination)
        name.font = TTFont.footnote.weight(.semibold)
        name.foregroundColor = TTColor.ink
        var time = AttributedString(" " + strip.arrival)
        time.foregroundColor = TTColor.inkSecondary
        return name + time
    }
}

/// The ride strip while a ride runs, else `otherwise` (the watched-trip strip). It drops in 12 pt from under the day strip,
/// from 0.97, on `RideMotion.rise` (a fade with Reduce Motion), and its countdown follows the ride's clock each second.
struct RideStripSlot<Otherwise: View>: View {
    let onBoard: OnBoard?
    var onOpen: () -> Void = {}
    @ViewBuilder var otherwise: Otherwise

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isRiding = onBoard?.activeRide != nil
        Group {
            if isRiding {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let strip = onBoard?.strip(formatter: formatter) {
                        RideStripView(strip: strip, onOpen: onOpen)
                    }
                }
                .padding(.horizontal, TTSpace.s5)
                .padding(.top, -2)
                .transition(
                    reduceMotion ? .opacity : .offset(y: -12).combined(with: .scale(scale: 0.97)).combined(with: .opacity)
                )
            } else {
                otherwise
            }
        }
        .animation(reduceMotion ? TTMotion.fade : RideMotion.rise, value: isRiding)
    }
}

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

/// The ride strip while a ride runs; else the alerted train's countdown before it leaves (TT-177, the demo's while Demo
/// trains › Departure plays); else `otherwise` (the watched-trip strip). The ride strip drops in 12 pt from under the day
/// strip, from 0.97, on `RideMotion.rise`; the countdown grows in on `DepartureMotion.grow` (fades with Reduce Motion). Both
/// follow their clocks each second.
struct RideStripSlot<Otherwise: View>: View {
    let onBoard: OnBoard?
    var onOpen: () -> Void = {}
    /// Before departure (TT-177): the alerted train's countdown; nil shows none.
    var departure: DepartureStrip?
    var onOpenDeparture: (TripKey) -> Void = { _ in }
    @ViewBuilder var otherwise: Otherwise

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Tier: Equatable {
        case ride, departure, otherwise
    }

    var body: some View {
        if onBoard?.departureDemo != nil {
            // The demo departure runs ten times as fast: its strip is read again each second.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                slot(departure: onBoard?.demoDepartureStrip(formatter: formatter))
            }
        } else {
            slot(departure: departure)
        }
    }

    private func slot(departure: DepartureStrip?) -> some View {
        let isRiding = onBoard?.activeRide != nil
        let tier: Tier = isRiding ? .ride : departure != nil ? .departure : .otherwise
        return Group {
            switch tier {
            case .ride:
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
            case .departure:
                if let departure {
                    DepartureStripView(strip: departure) { onOpenDeparture(departure.key) }
                        .padding(.horizontal, TTSpace.s5)
                        .padding(.top, -2)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.97, anchor: .top).combined(with: .opacity))
                }
            case .otherwise:
                otherwise
            }
        }
        .animation(animation(for: tier), value: tier)
    }

    private func animation(for tier: Tier) -> Animation {
        if reduceMotion { return TTMotion.fade }
        return tier == .departure ? DepartureMotion.grow : RideMotion.rise
    }
}

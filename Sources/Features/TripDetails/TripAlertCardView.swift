import SwiftUI

/// Trip details' alert card (TT-254, D129; the Alerts canvas's boards 45 to 50, `.acd`): on top of the sheet for every
/// train with an alert. "Alert" with the system switch (a one-day alert says "Once, today" under it); the seven 36 pt round
/// day marks, Monday first, with a wider gap before Saturday (lit in the accent, a one-day alert's own day as an accent
/// ring, the rest recessed; a tap lights or clears a day and presses it as the day tiles press); and "Remove alert" in red
/// under a hairline. Switched off, the title and the marks go grey and take no tap; Remove stays live. Time changed: "Time
/// changed" with its sentence, Pick a new train and Remove alert, nothing else.
struct TripAlertCardView: View {
    let card: TripAlertCard
    let onSwitch: (Bool) -> Void
    let onDay: (Int) -> Void
    let onRemove: () -> Void
    let onPickNewTrain: () -> Void

    static let mark: CGFloat = 36
    static let markGap: CGFloat = 10
    /// The weekend sits 6 pt further off.
    static let weekendGap: CGFloat = 6
    static let topRow: CGFloat = 52
    static let topRowWithWords: CGFloat = 60
    static let changedTopRow: CGFloat = 64
    static let removeRow: CGFloat = 46
    static let buttonHeight: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if card.isChanged {
                changedTop
                Button(action: onPickNewTrain) {
                    Text("alerts.pick_new_train")
                        .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                }
                .buttonStyle(.ttGlassPrimary)
                .padding(.top, 6)
                .padding(.bottom, 14)
                .accessibilityIdentifier("trip.pickNewTrain")
            } else {
                top
                days
            }
            removeButton
        }
        .padding(.top, 6)
        .padding(.horizontal, TTSpace.s4)
        .padding(.bottom, card.isChanged ? 6 : 4)
        .ttSheetCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.alertCard")
    }

    // MARK: Rows

    private var top: some View {
        HStack(spacing: TTSpace.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text("trip.alert.title")
                    .font(TTFont.headline)
                    .tracking(-0.4)
                    .foregroundStyle(card.isOn ? TTColor.ink : TTColor.inkSecondary)
                if let words = card.words {
                    Text(verbatim: words)
                        .font(TTFont.subhead)
                        .tracking(-0.2)
                        .foregroundStyle(TTColor.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Toggle(isOn: Binding(get: { card.isOn }, set: { onSwitch($0) })) {
                Text("trip.alert.title")
            }
            .labelsHidden()
            .tint(TTColor.accent)
            .accessibilityIdentifier("trip.alertSwitch")
        }
        .frame(height: card.words == nil ? Self.topRow : Self.topRowWithWords)
    }

    private var days: some View {
        HStack(spacing: Self.markGap) {
            ForEach(card.days) { day in
                DayMark(day: day, isOn: card.isOn) { onDay(day.id) }
                    .padding(.leading, day.id == 6 ? Self.weekendGap : 0)
            }
        }
        .opacity(card.isOn ? 1 : 0.6)
        .animation(.easeOut(duration: 0.15), value: card.isOn)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.alertDays")
    }

    private var changedTop: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TTSpace.s2) {
                Circle()
                    .fill(TTColor.delayInk)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text("alerts.time_changed")
                    .font(TTFont.headline)
                    .tracking(-0.4)
                    .foregroundStyle(TTColor.delayInk)
            }
            if let line = card.changedLine {
                Text(verbatim: line)
                    .font(TTFont.subhead)
                    .tracking(-0.2)
                    .foregroundStyle(TTColor.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.changedTopRow, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Text("alerts.remove")
                .font(TTFont.badgeLarge)
                .tracking(-0.2)
                .foregroundStyle(TTColor.cancelInk)
                .frame(maxWidth: .infinity, minHeight: Self.removeRow, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RemovePressStyle())
        .overlay(alignment: .top) {
            Rectangle().fill(TTColor.hairline).frame(height: 1)
        }
        .accessibilityIdentifier("trip.removeAlert")
    }
}

/// One round day mark: lit (accent, white letter), the ring (a one-day alert's own day, an accent ring and letter) or off
/// (recessed). Switched off, a lit mark is grey and the ring too. Lit by a tap, it presses in from 0.92 on
/// `TTMotion.tilePressCurve`, as the day panel's tiles do; the colour fills in 120 ms and fades out in 150 ms.
private struct DayMark: View {
    let day: TripAlertCard.Day
    let isOn: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presses = 0

    private var isLit: Bool { day.mark == .lit }

    var body: some View {
        Button(action: action) {
            Text(verbatim: day.letter)
                .font(TTFont.badgeLarge)
                .foregroundStyle(letter)
                .frame(width: TripAlertCardView.mark, height: TripAlertCardView.mark)
                .background {
                    if day.mark == .ring {
                        Circle().strokeBorder(isOn ? TTColor.accent : TTColor.inkTertiary, lineWidth: 2)
                    } else {
                        Circle().fill(fill)
                    }
                }
                .animation(.easeOut(duration: isLit ? 0.12 : 0.15), value: day.mark)
                .contentShape(Circle())
        }
        .buttonStyle(MarkStyle())
        .disabled(!isOn)
        .keyframeAnimator(initialValue: 1.0, trigger: presses) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            MoveKeyframe(0.92)
            SpringKeyframe(1.0, duration: 0.5, spring: TTMotion.tilePressCurve.spring)
        }
        .onChange(of: isLit) { _, lit in
            if lit, !reduceMotion { presses += 1 }
        }
        .accessibilityLabel(Text(verbatim: day.name))
        .accessibilityAddTraits(isLit ? .isSelected : [])
        .accessibilityIdentifier("trip.alertDay.\(day.id)")
    }

    private var fill: Color {
        guard isLit else { return TTColor.surfaceRaised }
        return isOn ? TTColor.accent : TTColor.inkTertiary.opacity(0.6)
    }

    private var letter: Color {
        switch day.mark {
        case .lit: isOn ? TTColor.onAccent : TTColor.surface
        case .ring: isOn ? TTColor.accent : TTColor.inkTertiary
        case .off: TTColor.inkSecondary
        }
    }
}

/// A mark is drawn the same pressed or not: its fill and press are its feedback.
private struct MarkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Remove alert dims while pressed, as a link does.
private struct RemovePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.45 : 1)
    }
}

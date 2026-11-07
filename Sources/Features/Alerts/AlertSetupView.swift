import SwiftUI

/// Alert setup sheet (TT-142), after design/frames/alert-setup.png, alert-setup-repeat.png and permission-prompt.png:
/// title and close, the trip card, This trip | Repeat, the Repeat days, the sentence, then "Enable alerts" (or "Save")
/// with the footnote, or the rule's state in words once it exists. Notifications off replaces the button with the red
/// panel and Open Settings. The sheet is as tall as its content, as on the canvas (D41).
struct AlertSetupView: View {
    @Bindable var viewModel: AlertSetupViewModel
    /// Delete alert closes the sheet.
    var onDelete: () -> Void = {}

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var height: CGFloat = 460

    /// Canvas `.sheet`: 10 pt padding, the 5 pt grabber and its 16 pt margin, the 16 pt gap and the title row's -8 pt.
    private static let titleTop: CGFloat = 10 + 5 + TTSpace.s4 + TTSpace.s4 - TTSpace.s2
    /// The canvas close button bleeds 10 pt into the side margin.
    private static let closeBleed: CGFloat = 10
    /// Canvas: 6 pt between the 44 pt day chips, so seven fit the sheet's width.
    private static let chipGap: CGFloat = 6
    private static let cardLineGap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s4) {
            titleBar
            tripCard
            SegmentedControl(
                selection: $viewModel.kind,
                options: [(AlertRule.Kind.thisTrip, "alert.this_trip"), (AlertRule.Kind.repeating, "alert.repeat")]
            )
            .accessibilityIdentifier("alert.kind")
            if viewModel.kind == .repeating {
                days
            }
            Text(viewModel.body)
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(.horizontal, TTSpace.s5)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxWidth: .infinity, alignment: .top)
        // RootView reads it again whenever the app comes back to the foreground (TT-141).
        .task { await viewModel.refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.alertSetup")
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TTRadius.sheet)
        .presentationBackground(TTColor.surface)
    }

    private var titleBar: some View {
        HStack {
            Text(viewModel.title)
                .font(TTFont.navTitle)
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("alert.title")
            Spacer()
            IconButton(systemName: "xmark", label: "button.close") { dismiss() }
                .accessibilityIdentifier("alert.close")
        }
        .padding(.trailing, -Self.closeBleed)
        .padding(.top, Self.titleTop)
    }

    private var tripCard: some View {
        VStack(alignment: .leading, spacing: Self.cardLineGap) {
            Text(viewModel.routeName)
                .font(TTFont.headline)
                .foregroundStyle(TTColor.ink)
            Text(viewModel.tripLine(formatter))
                .font(TTFont.subhead)
                .monospacedDigit()
                .foregroundStyle(TTColor.inkSecondary)
        }
        .padding(TTSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.canvas, in: RoundedRectangle(cornerRadius: TTRadius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("alert.trip")
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: TTSpace.s2) {
            Text("alert.repeat_on")
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
            HStack(spacing: Self.chipGap) {
                ForEach(AlertSetupViewModel.weekdays, id: \.self) { day in
                    DayChip(letter: AlertSetupViewModel.letter(day), isOn: viewModel.weekdays.contains(day)) {
                        viewModel.toggle(day)
                    }
                    .accessibilityLabel(Text(verbatim: AlertSetupViewModel.fullName(day)))
                    .accessibilityIdentifier("alert.day.\(day)")
                }
            }
        }
    }

    /// The canvas puts the This-trip footnote 12 pt under the button; everything else sits at the sheet's 16 pt gap.
    private var actions: some View {
        let state = viewModel.state
        return VStack(spacing: state == nil && viewModel.kind == .thisTrip ? TTSpace.s3 : TTSpace.s4) {
            if state == .notificationsOff {
                deniedPanel
                Button { openURL(AlertSetupViewModel.notificationSettingsURL) } label: {
                    Text("button.open_settings").frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttSecondary)
                .accessibilityIdentifier("alert.openSettings")
            } else {
                Button { Task { await viewModel.save() } } label: {
                    Text(viewModel.buttonTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttPrimary)
                .disabled(!viewModel.canSave)
                .accessibilityIdentifier("alert.enable")
                if let state {
                    stateLine(state)
                } else {
                    Text(viewModel.footnote)
                        .font(TTFont.footnote)
                        .foregroundStyle(TTColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("alert.footnote")
                }
            }
            if viewModel.isManaging, state != .settingUp {
                Button("alert.delete") {
                    Task {
                        await viewModel.delete()
                        onDelete()
                    }
                }
                .buttonStyle(.ttText)
                .accessibilityIdentifier("alert.delete")
            }
        }
    }

    /// Canvas: cancel-fill panel, 12 pt radius, the cancel icon beside "Notifications off" and the sentence.
    private var deniedPanel: some View {
        HStack(alignment: .top, spacing: TTSpace.s3) {
            Image(systemName: "xmark.octagon.fill")
                .font(TTFont.headline)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Self.cardLineGap) {
                Text("alert.denied.title").font(TTFont.headline)
                Text("alert.denied.body")
                    .font(TTFont.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(TTColor.cancelInk)
        .padding(.vertical, TTSpace.s3)
        .padding(.horizontal, TTSpace.s4)
        .background(TTColor.cancelFill, in: RoundedRectangle(cornerRadius: TTRadius.md))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("alert.denied")
    }

    /// The rule state in words with its icon (canvas `.state`); "Could not save · Try again" saves again.
    @ViewBuilder private func stateLine(_ state: AlertSetupViewModel.SheetState) -> some View {
        let line = HStack(spacing: TTSpace.s1) {
            if let symbol = Self.symbol(state) { Image(systemName: symbol).accessibilityHidden(true) }
            Text(Self.text(state))
        }
        .font(TTFont.footnote)
        .foregroundStyle(Self.ink(state))
        .frame(maxWidth: .infinity)
        if state == .couldNotSave {
            Button { Task { await viewModel.save() } } label: { line.frame(minHeight: TTSize.targetMin) }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("alert.state")
        } else {
            line
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("alert.state")
        }
    }

    private static func text(_ state: AlertSetupViewModel.SheetState) -> LocalizedStringKey {
        switch state {
        case .settingUp: "alert.state.setting_up"
        case .on: "alert.state.on"
        case .paused: "alert.state.paused"
        case .notificationsOff: "alert.state.off"
        case .reviewNeeded: "alert.state.review"
        case .couldNotSave: "alert.state.could_not_save"
        }
    }

    private static func symbol(_ state: AlertSetupViewModel.SheetState) -> String? {
        switch state {
        case .settingUp: "clock"
        case .on: "checkmark.circle.fill"
        case .paused: nil
        case .reviewNeeded: "clock.badge.exclamationmark"
        case .notificationsOff, .couldNotSave: "xmark.octagon.fill"
        }
    }

    private static func ink(_ state: AlertSetupViewModel.SheetState) -> Color {
        switch state {
        case .settingUp, .paused: TTColor.inkSecondary
        case .on: TTColor.ontimeInk
        case .reviewNeeded: TTColor.delayInk
        case .notificationsOff, .couldNotSave: TTColor.cancelInk
        }
    }
}

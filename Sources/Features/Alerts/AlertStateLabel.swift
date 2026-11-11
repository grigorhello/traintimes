import SwiftUI

extension AlertSetupViewModel.SheetState {
    /// The rule's state in words as the alert setup sheet (TT-142) and the Alerts rows (TT-143) show it: the stored
    /// state, with a paused rule that is On reading Paused.
    init(_ state: AlertRuleState, paused: Bool) {
        switch state {
        case .settingUp: self = .settingUp
        case .on: self = paused ? .paused : .on
        case .notificationsOff: self = .notificationsOff
        case .reviewNeeded: self = .reviewNeeded
        case .couldNotSave: self = .couldNotSave
        }
    }

    var text: LocalizedStringKey {
        switch self {
        case .settingUp: "alert.state.setting_up"
        case .on: "alert.state.on"
        case .paused: "alert.state.paused"
        case .notificationsOff: "alert.state.not_delivering"
        case .reviewNeeded: "alert.state.review"
        case .couldNotSave: "alert.state.could_not_save"
        }
    }

    var symbol: String? {
        switch self {
        case .settingUp: "clock"
        case .on: "checkmark.circle.fill"
        case .paused: nil
        case .reviewNeeded: "clock.badge.exclamationmark"
        case .notificationsOff: "bell.slash.fill"
        case .couldNotSave: "xmark.octagon.fill"
        }
    }

    var ink: Color {
        switch self {
        // Not delivering is quiet: the card above the rows says why (TT-169).
        case .settingUp, .paused, .notificationsOff: TTColor.inkSecondary
        // Alert rule On states use the accent (requirements' token table, canvas `.phone .state.on`).
        case .on: TTColor.accent
        case .reviewNeeded: TTColor.delayInk
        case .couldNotSave: TTColor.cancelInk
        }
    }
}

/// The rule state in words with its icon (canvas `.state`), in footnote: "On" with a checkmark, "Not delivering" with a
/// crossed bell, "Paused", "Review needed · usual train has changed".
struct AlertStateLabel: View {
    let state: AlertSetupViewModel.SheetState

    var body: some View {
        HStack(spacing: TTSpace.s1) {
            if let symbol = state.symbol { Image(systemName: symbol).accessibilityHidden(true) }
            Text(state.text)
        }
        .font(TTFont.footnote)
        .foregroundStyle(state.ink)
    }
}

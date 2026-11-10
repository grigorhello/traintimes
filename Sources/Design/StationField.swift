import SwiftUI
import UIKit

/// A station row of the route card while it is the search field (TT-161, D53). It looks like the row: the typed text in
/// headline, an accent cursor, and nothing else, no capsule and no search glyph. It takes the keyboard as soon as it is on
/// screen. On Schedule the current station stays in the row as a hint, in the same headline but ink-tertiary, and the first
/// keystroke replaces it: nothing is selected, so no selection handles (Grigor, 2026-11-10).
struct StationField: UIViewRepresentable {
    /// What the rider typed; empty while the placeholder or the current station shows.
    let text: String
    let placeholder: String
    /// The station the row held, shown as the hint until the first keystroke; nil starts on the placeholder (first use).
    let current: String?
    let identifier: String
    let onChange: (String) -> Void
    /// The Return key.
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PickerTextField {
        let field = PickerTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.font = .systemFont(ofSize: 17, weight: .semibold)
        field.textColor = UIColor(named: "Ink")
        field.tintColor = UIColor(named: "Accent")
        let hint = UIColor(named: "InkTertiary") ?? UIColor.placeholderText
        field.attributedPlaceholder = NSAttributedString(
            string: current ?? placeholder,
            attributes: [
                // The current station keeps the row's headline; the empty placeholder is the body text.
                .font: UIFont.systemFont(ofSize: 17, weight: current == nil ? .regular : .semibold),
                .foregroundColor: hint,
            ]
        )
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .words
        field.accessibilityIdentifier = identifier
        // The row is as wide as the card allows; the text never pushes its width.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.text = text
        return field
    }

    func updateUIView(_ field: PickerTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // The model changed the text (cleared it, or a test set it); typing already reports through `editingChanged`.
        if text != coordinator.reported {
            field.text = text
            coordinator.reported = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: StationField
        /// The text last passed to `onChange`, so `updateUIView` can tell a keystroke from a change made by the model.
        var reported: String

        init(_ parent: StationField) {
            self.parent = parent
            reported = parent.text
        }

        @objc func editingChanged(_ field: UITextField) {
            reported = field.text ?? ""
            parent.onChange(reported)
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

/// Takes the keyboard when it joins the app's key window (a field drawn for a snapshot is not in one, so it shows no
/// cursor).
final class PickerTextField: UITextField {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window?.isKeyWindow == true else { return }
        if !focus() {
            // The window was not ready to hand out the keyboard yet: once more on the next turn.
            Task { [weak self] in _ = self?.focus() }
        }
    }

    private func focus() -> Bool {
        guard window != nil else { return false }
        return isFirstResponder || becomeFirstResponder()
    }
}

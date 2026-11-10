import SwiftUI
import UIKit

/// A station row of the route card while it is the search field (TT-161, D52). It looks like the row: the typed text in
/// headline, the placeholder in body ink-tertiary, an accent cursor, and nothing else, no capsule and no search glyph. It
/// takes the keyboard as soon as it is on screen. On Schedule the current station shows selected, so typing replaces it.
struct StationField: UIViewRepresentable {
    /// What the rider typed; empty while the placeholder or the selected station shows.
    let text: String
    let placeholder: String
    /// The station name shown selected until the first keystroke; nil starts on the placeholder (first use).
    let selected: String?
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
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .regular),
                .foregroundColor: UIColor(named: "InkTertiary") ?? UIColor.placeholderText,
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
        if text.isEmpty, let selected {
            field.text = selected
            field.selectsAllOnFocus = true
        } else {
            field.text = text
        }
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
/// cursor), and selects its text first when `selectsAllOnFocus` is set.
final class PickerTextField: UITextField {
    var selectsAllOnFocus = false

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
        if isFirstResponder { return true }
        guard becomeFirstResponder() else { return false }
        if selectsAllOnFocus {
            selectedTextRange = textRange(from: beginningOfDocument, to: endOfDocument)
        }
        return true
    }
}

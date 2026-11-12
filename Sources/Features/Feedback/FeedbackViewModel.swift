import Foundation
import Observation

/// The feedback sheet (TT-202, D85): Feedback or Question, the message, an optional reply email, then Send. The app
/// version, iPhone model and iOS version go with it (`FeedbackContext`), nothing else.
@Observable @MainActor
final class FeedbackViewModel {
    enum Phase: Equatable {
        case editing, sending, sent, failed
    }

    static let supportEmail = "support@traintimes.ca"
    /// "Email us": the rider's mail app, addressed to support, with a subject.
    static let mailURL = URL(string: "mailto:\(supportEmail)?subject=Train%20Times")!

    var kind: FeedbackKind
    /// Capped at `FeedbackMessage.maxLength` characters, as the server takes it.
    var message = "" {
        didSet {
            if message.count > FeedbackMessage.maxLength { message = String(message.prefix(FeedbackMessage.maxLength)) }
        }
    }
    var email = ""
    private(set) var phase: Phase = .editing

    private let sender: any FeedbackSending
    private let context: FeedbackContext

    init(kind: FeedbackKind = .feedback, sender: any FeedbackSending, context: FeedbackContext = .current) {
        self.kind = kind
        self.sender = sender
        self.context = context
    }

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Empty, or something that looks like an address: one @, a dot after it, no spaces.
    var isEmailValid: Bool {
        let email = trimmedEmail
        if email.isEmpty { return true }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        return email.count <= 200 && parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".") && !email.contains(" ")
    }

    var canSend: Bool {
        !trimmedMessage.isEmpty && isEmailValid && (phase == .editing || phase == .failed)
    }

    /// Whether the thanks says a reply will come: a question with an email.
    var expectsReply: Bool { kind == .question && !trimmedEmail.isEmpty }

    func send() async {
        guard canSend else { return }
        phase = .sending
        let outgoing = FeedbackMessage(
            kind: kind,
            message: trimmedMessage,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            appVersion: context.appVersion,
            device: context.device,
            osVersion: context.osVersion
        )
        do {
            try await sender.send(outgoing)
            phase = .sent
        } catch {
            phase = .failed
        }
    }
}

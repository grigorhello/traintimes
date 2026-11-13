import SwiftUI

/// Send feedback or a question in a few seconds (TT-202, D85): Close and Send on top, then a Feedback · Question switch, the
/// message and an optional reply email, in one sheet opened from Settings › Support and, in the early stage, Schedule's Feedback pill. Sent, it
/// thanks the rider; failed, it offers Try again and "Email us instead".
struct FeedbackSheet: View {
    @State private var viewModel: FeedbackViewModel
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    /// Off in snapshots, so the keyboard does not come up.
    private let focusesMessage: Bool

    private enum Field { case message, email }

    init(viewModel: FeedbackViewModel, focusesMessage: Bool = true) {
        _viewModel = State(initialValue: viewModel)
        self.focusesMessage = focusesMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Send sits up here, beside Close, so the keyboard never covers it.
            HStack {
                GlassIconButton(systemName: "xmark", label: "button.close", tint: TTColor.ink) { dismiss() }
                    .accessibilityIdentifier("feedback.close")
                Spacer(minLength: 0)
                if viewModel.phase != .sent {
                    sendButton
                }
            }
            .padding(.horizontal, TTSpace.s4)
            .padding(.top, TTSpace.s4)

            if viewModel.phase == .sent {
                sent
            } else {
                form
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.25), value: viewModel.phase)
        .background(TTColor.canvas)
        // A container, so the identifier stays on the sheet and Close, Send and Done keep their own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.feedback")
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TTRadius.sheet)
        .presentationBackground(TTColor.canvas)
        .task {
            if focusesMessage { focus = .message }
        }
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpace.s4) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("feedback.title")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(TTColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("feedback.subtitle")
                        .font(TTFont.subhead)
                        .foregroundStyle(TTColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GlassSwitch(
                    selection: $viewModel.kind,
                    options: [
                        .init(value: .feedback, label: .text("feedback.kind.feedback"), name: "feedback.kind.feedback", identifier: "feedback.kind.feedback"),
                        .init(value: .question, label: .text("feedback.kind.question"), name: "feedback.kind.question", identifier: "feedback.kind.question"),
                    ]
                )

                messageBox
                emailField

                Text("feedback.note")
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                    .padding(.horizontal, TTSpace.s1)

                if viewModel.phase == .failed {
                    failure
                }
            }
            .padding(.horizontal, TTSpace.s5)
            .padding(.top, TTSpace.s1)
            .padding(.bottom, TTSpace.s6)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Send, Try again after a failure, a spinner while sending; disabled until there is something to send.
    private var sendButton: some View {
        Button {
            Task { await viewModel.send() }
        } label: {
            ZStack {
                Text(LocalizedStringKey(viewModel.phase == .failed ? "feedback.try_again" : "feedback.send"))
                    .opacity(viewModel.phase == .sending ? 0 : 1)
                if viewModel.phase == .sending {
                    ProgressView().tint(TTColor.onAccent)
                }
            }
            .frame(minWidth: 52)
        }
        .buttonStyle(.ttGlassPrimary)
        .disabled(!viewModel.canSend)
        .accessibilityIdentifier("feedback.send")
    }

    private var messageBox: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.message.isEmpty {
                Text(LocalizedStringKey(viewModel.kind == .feedback ? "feedback.placeholder.feedback" : "feedback.placeholder.question"))
                    .font(TTFont.body)
                    .foregroundStyle(TTColor.inkTertiary)
                    .padding(.horizontal, TTSpace.s4)
                    .padding(.vertical, TTSpace.s3 + 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $viewModel.message)
                .font(TTFont.body)
                .foregroundStyle(TTColor.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, TTSpace.s3)
                .padding(.vertical, TTSpace.s2 - 1)
                .focused($focus, equals: .message)
                .accessibilityLabel(Text(LocalizedStringKey(viewModel.kind == .feedback ? "feedback.kind.feedback" : "feedback.kind.question")))
                .accessibilityIdentifier("feedback.message")
        }
        .frame(height: 176)
        .ttSheetCard(cornerRadius: TTRadius.lg)
    }

    private var emailField: some View {
        TextField("feedback.email", text: $viewModel.email)
            .font(TTFont.body)
            .foregroundStyle(viewModel.isEmailValid ? TTColor.ink : TTColor.cancelInk)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .onSubmit { Task { await viewModel.send() } }
            .focused($focus, equals: .email)
            .padding(.horizontal, TTSpace.s4)
            .frame(height: SettingsMetrics.rowHeight)
            .ttSheetCard(cornerRadius: TTRadius.lg)
            .accessibilityIdentifier("feedback.email")
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: TTSpace.s1) {
            Text("feedback.failed")
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.cancelInk)
                .fixedSize(horizontal: false, vertical: true)
            EmailUsButton {
                Text("feedback.email_instead").font(TTFont.subhead.weight(.semibold))
            }
            .buttonStyle(.ttText)
            .accessibilityIdentifier("feedback.emailInstead")
        }
        .padding(.horizontal, TTSpace.s1)
    }

    // MARK: Sent

    private var sent: some View {
        VStack(spacing: TTSpace.s3) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(TTColor.accent)
                .frame(width: 64, height: 64)
                .background(TTColor.accentSoft, in: Circle())
                .padding(.bottom, TTSpace.s1)
                .accessibilityHidden(true)
            Text("feedback.sent.title")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(LocalizedStringKey(viewModel.expectsReply ? "feedback.sent.reply" : "feedback.sent.body"))
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.inkSecondary)
            Button { dismiss() } label: {
                Text("feedback.done").frame(maxWidth: .infinity).frame(height: 52)
            }
            .buttonStyle(.ttGlassPrimary)
            .padding(.top, TTSpace.s4)
            .accessibilityIdentifier("feedback.done")
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, 72)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}

#Preview("Feedback") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FeedbackSheet(viewModel: FeedbackViewModel(sender: FixtureFeedbackSender()))
    }
}

import XCTest
@testable import TrainTimes

/// The feedback sheet's model (TT-202, D85).
@MainActor
final class FeedbackViewModelTests: XCTestCase {
    private let context = FeedbackContext(appVersion: "1.0 (45)", device: "iPhone18,1", osVersion: "26.1.0")

    func testSendsTheTrimmedMessageWithTheContext() async {
        let sender = RecordingFeedbackSender()
        let model = FeedbackViewModel(sender: sender, context: context)
        model.kind = .question
        model.message = "  Does it cover Kitchener?\n"
        model.email = " rider@example.com "
        XCTAssertTrue(model.canSend)

        await model.send()

        XCTAssertEqual(model.phase, .sent)
        XCTAssertTrue(model.expectsReply)
        XCTAssertEqual(sender.sent, [FeedbackMessage(
            kind: .question, message: "Does it cover Kitchener?", email: "rider@example.com",
            appVersion: "1.0 (45)", device: "iPhone18,1", osVersion: "26.1.0"
        )])
    }

    func testAnEmptyMessageOrABadEmailCannotBeSent() async {
        let sender = RecordingFeedbackSender()
        let model = FeedbackViewModel(sender: sender, context: context)
        XCTAssertFalse(model.canSend)
        model.message = "   \n"
        XCTAssertFalse(model.canSend)
        model.message = "Great app"
        XCTAssertTrue(model.canSend, "The email is optional")
        for bad in ["rider", "rider@", "@example.com", "rider@example", "ri der@example.com", "rider@example."] {
            model.email = bad
            XCTAssertFalse(model.isEmailValid, bad)
            XCTAssertFalse(model.canSend, bad)
        }
        await model.send()
        XCTAssertTrue(sender.sent.isEmpty)
        XCTAssertEqual(model.phase, .editing)
    }

    func testFeedbackWithoutAnEmailSendsNone() async {
        let sender = RecordingFeedbackSender()
        let model = FeedbackViewModel(sender: sender, context: context)
        model.message = "Love the timeline"
        await model.send()
        XCTAssertNil(sender.sent.first?.email)
        XCTAssertFalse(model.expectsReply)
    }

    func testAFailureCanBeTriedAgain() async {
        let sender = RecordingFeedbackSender()
        sender.fails = true
        let model = FeedbackViewModel(sender: sender, context: context)
        model.message = "Hello"
        await model.send()
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.canSend)

        sender.fails = false
        await model.send()
        XCTAssertEqual(model.phase, .sent)
        XCTAssertFalse(model.canSend, "Sent once")
    }

    func testTheMessageIsCappedAtTheServersLimit() {
        let model = FeedbackViewModel(sender: RecordingFeedbackSender(), context: context)
        model.message = String(repeating: "a", count: FeedbackMessage.maxLength + 50)
        XCTAssertEqual(model.message.count, FeedbackMessage.maxLength)
    }

    func testTheRequestMatchesTheServersAPI() throws {
        let message = FeedbackMessage(kind: .feedback, message: "Hi", email: nil, appVersion: "1.0 (45)", device: "iPhone18,1", osVersion: "26.1.0")
        let request = try HTTPFeedbackSender().request(message)
        XCTAssertEqual(request.url?.absoluteString, "https://alerts.traintimes.ca/v1/feedback")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["kind": "feedback", "message": "Hi", "appVersion": "1.0 (45)", "device": "iPhone18,1", "osVersion": "26.1.0"])
    }
}

/// Records what the model sends, or fails while `fails` is set.
@MainActor
final class RecordingFeedbackSender: FeedbackSending {
    var sent: [FeedbackMessage] = []
    var fails = false

    func send(_ message: FeedbackMessage) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        sent.append(message)
    }
}

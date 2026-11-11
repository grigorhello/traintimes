import XCTest
@testable import TrainTimes

/// Train detection's strip and question as Schedule words them (TT-175, Live-Detect).
final class DetectionDisplayTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    func testStripWhileMatching() throws {
        let strip = try XCTUnwrap(DetectionStrip(DetectionFixtures.progress(stops: 0), formatter: formatter))
        XCTAssertEqual(strip.title, "Moving along Lakeshore West")
        XCTAssertEqual(strip.detail, "Matching your train…")
        XCTAssertEqual(strip.trailing, "since Union")
    }

    func testStripCountsTheSharedStops() throws {
        let one = try XCTUnwrap(DetectionStrip(DetectionFixtures.progress(stops: 1), formatter: formatter))
        XCTAssertEqual(one.detail, "Looks like the 5:13 PM train")
        XCTAssertEqual(one.trailing, "1 of 2 stops")
        let three = try XCTUnwrap(DetectionStrip(DetectionFixtures.progress(stops: 3), formatter: formatter))
        XCTAssertEqual(three.trailing, "2 of 2 stops")
    }

    func testNoStripWithoutALine() {
        let progress = TrainMatcher.Progress(line: nil, since: nil, train: nil, stops: 0)
        XCTAssertNil(DetectionStrip(progress, formatter: formatter))
    }

    func testQuestionAboutOneTrain() {
        let question = TrainQuestion(DetectionFixtures.question(), formatter: formatter)
        XCTAssertEqual(question.title, "On the 5:13 PM train?")
        XCTAssertEqual(question.why, "Your phone has moved with it since Union and stopped with it at Exhibition and Mimico.")
        XCTAssertEqual(question.emphasized, ["Exhibition", "Mimico"])
        XCTAssertEqual(question.answers.map(\.label), ["Yes, on board"])
        XCTAssertEqual(question.answers.map(\.train), [DetectionFixtures.train])
    }

    func testQuestionAboutTwoTrainsOffersEachTime() {
        let question = TrainQuestion(DetectionFixtures.question(both: true), formatter: formatter)
        XCTAssertEqual(question.title, "On the 5:13 PM or 5:16 PM train?")
        XCTAssertEqual(question.answers.map(\.label), ["5:13 PM", "5:16 PM"])
        XCTAssertEqual(question.answers.map(\.train), [DetectionFixtures.train, DetectionFixtures.express])
    }

    func testTwentyFourHourTimes() {
        let question = TrainQuestion(DetectionFixtures.question(), formatter: TimeFormatter(format: .twentyFourHour))
        XCTAssertEqual(question.title, "On the 17:13 train?")
    }

    // MARK: What the strip under the day strip shows

    func testRideStripContentFollowsTheRideAndDetection() {
        let checking = TrainMatcher.State.checking(DetectionFixtures.progress(stops: 1))
        let asking = TrainMatcher.State.asking(DetectionFixtures.question())
        XCTAssertEqual(RideStripContent(isRiding: false, detection: .idle), .otherwise)
        XCTAssertEqual(RideStripContent(isRiding: false, detection: checking), .checking)
        XCTAssertEqual(RideStripContent(isRiding: false, detection: asking), .asking)
        // A ride wins over a question left up.
        XCTAssertEqual(RideStripContent(isRiding: true, detection: asking), .riding)
    }

    func testNoCheckingStripWithoutALine() {
        let progress = TrainMatcher.Progress(line: nil, since: nil, train: nil, stops: 0)
        XCTAssertEqual(RideStripContent(isRiding: false, detection: .checking(progress)), .otherwise)
    }
}

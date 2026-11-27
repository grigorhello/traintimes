import XCTest
@testable import TrainTimes

/// The Feedback button's play (TT-252, D128), read from its keyframes: it starts and ends at rest, asks in the middle, and
/// bounces bigger and smaller while it asks.
@MainActor
final class FeedbackNudgeMotionTests: XCTestCase {
    func testStartsAndEndsAtRest() {
        XCTAssertEqual(FeedbackNudgeMotion.frame(at: 0).fill, 0)
        XCTAssertLessThanOrEqual(FeedbackNudgeMotion.keyframesDuration, FeedbackNudgeMotion.duration + 0.001)
        let end = FeedbackNudgeMotion.frame(at: FeedbackNudgeMotion.duration)
        XCTAssertEqual(end.scale, 1, accuracy: 0.01)
        XCTAssertEqual(end.fill, 0, accuracy: 0.001)
        XCTAssertEqual(end.ink, 0)
        XCTAssertEqual(end.tilt, 0, accuracy: 0.01)
        XCTAssertEqual(end.glyphScale, 1, accuracy: 0.001)
        XCTAssertEqual(end.upper, 1, accuracy: 0.001)
        XCTAssertEqual(end.lower, 1, accuracy: 0.001)
        XCTAssertEqual(end.hookTo - end.hookFrom, 0, accuracy: 0.001)
        XCTAssertEqual(end.dot, 0, accuracy: 0.001)
    }

    func testAsksAboutOneSecondIn() {
        let frame = FeedbackNudgeMotion.frame(at: 1.0)
        XCTAssertEqual(frame.fill, 1)
        XCTAssertEqual(frame.ink, 1)
        XCTAssertEqual(frame.upper, 0)
        XCTAssertEqual(frame.lower, 0)
        XCTAssertEqual(frame.hookTo, 1, accuracy: 0.001)
        XCTAssertEqual(frame.hookFrom, 0)
        XCTAssertEqual(frame.dot, 1, accuracy: 0.05)
        XCTAssertEqual(frame.tilt, FeedbackNudgeMotion.tilt, accuracy: 1)
    }

    func testBouncesBiggerAndSmaller() {
        let scales = stride(from: 0.0, through: 1.9, by: 1.0 / 120).map { FeedbackNudgeMotion.frame(at: $0).scale }
        // Local peaks and dips while it asks: at least two of each, the first peak well past the resting 1.15.
        var peaks: [CGFloat] = [], dips: [CGFloat] = []
        for index in 1..<(scales.count - 1) {
            if scales[index] > scales[index - 1] && scales[index] >= scales[index + 1] { peaks.append(scales[index]) }
            if scales[index] < scales[index - 1] && scales[index] <= scales[index + 1] { dips.append(scales[index]) }
        }
        XCTAssertGreaterThanOrEqual(peaks.count, 2)
        XCTAssertGreaterThanOrEqual(dips.count, 1)
        XCTAssertGreaterThan(peaks.first ?? 0, 1.18)
        XCTAssertLessThan(scales.max() ?? 2, 1.3)
    }

    func testTheColourFlipsAtOnce() {
        XCTAssertEqual(FeedbackNudgeMotion.frame(at: 0.05).ink, 0)
        XCTAssertEqual(FeedbackNudgeMotion.frame(at: 0.07).ink, 1)
        XCTAssertEqual(FeedbackNudgeMotion.frame(at: 2.17).ink, 1)
        XCTAssertEqual(FeedbackNudgeMotion.frame(at: 2.19).ink, 0)
    }
}

import XCTest
@testable import RealTimeCaptionsTranslatorCore

final class QuestionDetectorTests: XCTestCase {
    func testDetectsQuestionMark() {
        var detector = SubtitleViewModelQuestionDetector()
        XCTAssertTrue(detector.shouldTrigger(itemID: "1", text: "Can you explain this?"))
    }

    func testDetectsQuestionStarterWithoutQuestionMark() {
        var detector = SubtitleViewModelQuestionDetector()
        XCTAssertTrue(detector.shouldTrigger(itemID: "1", text: "What is your experience with SwiftUI"))
    }

    func testSkipsNonQuestionAndDeduplicates() {
        var detector = SubtitleViewModelQuestionDetector()
        XCTAssertFalse(detector.shouldTrigger(itemID: "1", text: "This is a statement"))
        XCTAssertTrue(detector.shouldTrigger(itemID: "2", text: "How do you work with teams"))
        XCTAssertFalse(detector.shouldTrigger(itemID: "2", text: "How do you work with teams"))
        XCTAssertFalse(detector.shouldTrigger(itemID: "3", text: "How do you work with teams"))
    }
}

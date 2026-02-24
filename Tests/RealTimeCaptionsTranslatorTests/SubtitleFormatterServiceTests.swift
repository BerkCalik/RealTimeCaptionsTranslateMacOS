import XCTest
@testable import RealTimeCaptionsTranslatorCore

final class SubtitleFormatterServiceTests: XCTestCase {
    private let formatter = SubtitleFormatterService()

    func testRemovesFillerWords() {
        let payload = formatter.format("um this is uh like a test you know")
        XCTAssertEqual(payload.line1, "This is a test.")
        XCTAssertNil(payload.line2)
    }

    func testWrapsToTwoLinesWithNoSingleWordOrphan() {
        let payload = formatter.format("one two three four five six seven eight nine ten eleven twelve thirteen")
        XCTAssertEqual(payload.line1, "One two three four five six seven eight nine ten eleven")
        XCTAssertEqual(payload.line2, "twelve thirteen.")
    }

    func testAddsPunctuationIfMissing() {
        let payload = formatter.format("hello world")
        XCTAssertEqual(payload.line1, "Hello world.")
    }
}

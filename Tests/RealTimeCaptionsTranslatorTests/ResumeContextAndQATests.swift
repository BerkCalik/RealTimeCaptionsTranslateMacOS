import XCTest
@testable import RealTimeCaptionsTranslatorCore

final class ResumeContextAndQATests: XCTestCase {
    func testResumeContextLoaderReturnsBundleResource() {
        let result = ResumeContextLoader.load()
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertFalse(result.usingFallback)
    }

    func testQAInstructionBuilderIncludesRulesAndContext() {
        let instruction = RealtimeQuestionAnswerInstructionBuilder.buildSessionInstructions(
            resumeContext: "Name: Jane Doe\nSkills: Swift, WebRTC",
            usingFallback: false
        )

        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("english only"))
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("resume context"))
        XCTAssertTrue(instruction.contains("Jane Doe"))
        XCTAssertTrue(instruction.contains("WebRTC"))
    }

    func testQARequestInstructionMentionsNoMadeUpFacts() {
        let instruction = RealtimeQuestionAnswerInstructionBuilder.buildAnswerRequestInstructions(
            resumeContext: "Name: Jane Doe",
            usingFallback: false,
            englishLevel: .b1
        )
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("english"))
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("avoid made-up facts"))
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("never ask follow-up questions"))
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("first person"))
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("cefr english level: b1"))
        XCTAssertTrue(instruction.contains("Jane Doe"))
    }
}

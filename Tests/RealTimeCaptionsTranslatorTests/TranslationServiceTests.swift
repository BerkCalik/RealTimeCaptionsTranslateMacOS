import Foundation
import XCTest
@testable import RealTimeCaptionsTranslatorCore

final class TranslationServiceTests: XCTestCase {
    func testValidateModelAccessFailsWhenAPIKeyMissing() async {
        let service = RealtimeWebRTCService(apiKey: nil)

        do {
            try await service.validateModelAccess(model: .realtimeMini)
            XCTFail("Expected translationAPIKeyMissing")
        } catch let error as SubtitleError {
            switch error {
            case .translationAPIKeyMissing:
                XCTAssertTrue(true)
            default:
                XCTFail("Unexpected SubtitleError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBuildSessionInstructionsSupportsHybridFlow() {
        let instruction = RealtimeWebRTCService.buildSessionInstructions()

        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("transcription events"))
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("do not produce assistant text automatically"))
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("response.create"))
    }

    func testLatencyProfileMappingStableBalancedUltraFast() {
        let stable = RealtimeWebRTCService.profile(for: .stable)
        let balanced = RealtimeWebRTCService.profile(for: .balanced)
        let ultraFast = RealtimeWebRTCService.profile(for: .ultraFast)

        XCTAssertEqual(stable, .init(
            liveEnabled: false,
            debounceNs: 200_000_000,
            vadThreshold: 0.50,
            vadPrefixMs: 180,
            vadSilenceMs: 260
        ))
        XCTAssertEqual(balanced, .init(
            liveEnabled: true,
            debounceNs: 200_000_000,
            vadThreshold: 0.45,
            vadPrefixMs: 120,
            vadSilenceMs: 150
        ))
        XCTAssertEqual(ultraFast, .init(
            liveEnabled: true,
            debounceNs: 120_000_000,
            vadThreshold: 0.40,
            vadPrefixMs: 80,
            vadSilenceMs: 100
        ))
    }

    func testBuildTranslationInstructionsIncludesTechTermsWhenEnabled() {
        let instruction = RealtimeWebRTCService.buildTranslationRequestInstructions(
            keepTechWordsOriginal: true,
            technicalTerms: ["WebRTC", "SwiftUI", "gpt-4o"]
        )

        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("output only turkish text"))
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("unchanged"))
        XCTAssertTrue(instruction.contains("WebRTC"))
        XCTAssertTrue(instruction.contains("SwiftUI"))
        XCTAssertTrue(instruction.contains("gpt-4o"))
    }

    func testBuildTranslationInstructionsWithoutTechRule() {
        let instruction = RealtimeWebRTCService.buildTranslationRequestInstructions(
            keepTechWordsOriginal: false,
            technicalTerms: ["WebRTC"]
        )

        XCTAssertFalse(instruction.localizedCaseInsensitiveContains("unchanged"))
        XCTAssertFalse(instruction.contains("WebRTC"))
    }

    func testBuildTranslationInstructionsForLiveModeMentionsPartial() {
        let instruction = RealtimeWebRTCService.buildTranslationRequestInstructions(
            keepTechWordsOriginal: false,
            technicalTerms: [],
            isFinal: false
        )

        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("live partial utterance"))
        XCTAssertTrue(instruction.localizedCaseInsensitiveContains("incomplete"))
    }

    func testExtractTechnicalTermsFindsExpectedTokens() {
        let terms = RealtimeWebRTCService.extractTechnicalTerms(
            from: "We used WebRTC with SwiftUI, URLSession, API v1.2.3 and gpt-4o in camelCaseConfig."
        )

        XCTAssertTrue(terms.contains("WebRTC"))
        XCTAssertTrue(terms.contains("SwiftUI"))
        XCTAssertTrue(terms.contains("URLSession"))
        XCTAssertTrue(terms.contains("API"))
        XCTAssertTrue(terms.contains("v1.2.3"))
        XCTAssertTrue(terms.contains("gpt-4o"))
    }

    func testParseServerEventsEnglishDelta() throws {
        let data = try makeJSONData([
            "type": "conversation.item.input_audio_transcription.delta",
            "item_id": "item-1",
            "delta": "hello"
        ])

        let events = try RealtimeWebRTCService.parseServerEvents(data: data)
        XCTAssertEqual(events, [.englishDelta(itemID: "item-1", text: "hello")])
    }

    func testParseServerEventsEnglishFinal() throws {
        let data = try makeJSONData([
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "item-1",
            "transcript": "hello world"
        ])

        let events = try RealtimeWebRTCService.parseServerEvents(data: data)
        XCTAssertEqual(events, [.englishFinal(itemID: "item-1", text: "hello world")])
    }

    func testParseServerEventsTurkishDelta() throws {
        let data = try makeJSONData([
            "type": "response.output_text.delta",
            "response_id": "resp-1",
            "delta": "merhaba"
        ])

        let events = try RealtimeWebRTCService.parseServerEvents(data: data)
        XCTAssertEqual(events, [.turkishDelta(responseID: "resp-1", text: "merhaba")])
    }

    func testParseServerEventsTurkishFinalFromDone() throws {
        let data = try makeJSONData([
            "type": "response.output_text.done",
            "response_id": "resp-1",
            "text": "merhaba dunya"
        ])

        let events = try RealtimeWebRTCService.parseServerEvents(data: data)
        XCTAssertEqual(events, [
            .turkishDelta(responseID: "resp-1", text: "merhaba dunya"),
            .turkishFinal(responseID: "resp-1")
        ])
    }

    func testParseServerEventsIgnoresBenignCancellationError() throws {
        let data = try makeJSONData([
            "type": "error",
            "error": [
                "message": "Cancellation failed: no active response found"
            ]
        ])

        let events = try RealtimeWebRTCService.parseServerEvents(data: data)
        XCTAssertTrue(events.isEmpty)
    }

    func testEnqueueLimitedDropsOldestWhenQueueIsFull() {
        var queue = ["a", "b"]
        let dropped = RealtimeWebRTCService.enqueueLimited("c", into: &queue, max: 2)

        XCTAssertEqual(dropped, "a")
        XCTAssertEqual(queue, ["b", "c"])
    }

    private func makeJSONData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }
}

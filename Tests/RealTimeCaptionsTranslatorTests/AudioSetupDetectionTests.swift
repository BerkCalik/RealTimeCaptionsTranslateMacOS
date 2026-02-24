import XCTest
@testable import RealTimeCaptionsTranslatorCore

final class AudioSetupDetectionTests: XCTestCase {
    func testDetectsBlackHoleNamesCaseInsensitively() {
        XCTAssertTrue(AudioSetupDetector.isBlackHoleName("BlackHole 2ch"))
        XCTAssertTrue(AudioSetupDetector.isBlackHoleName("blackhole 16CH"))
    }

    func testDoesNotMatchUnrelatedDeviceNames() {
        XCTAssertFalse(AudioSetupDetector.isBlackHoleName("MacBook Pro Microphone"))
        XCTAssertFalse(AudioSetupDetector.isBlackHoleName("Built-in Input"))
    }

    func testBlackHoleCandidateSelectionKeepsOriginalOrder() {
        let devices = [
            AudioInputDevice(id: "1", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "2", name: "BlackHole 2ch"),
            AudioInputDevice(id: "3", name: "blackhole 16ch")
        ]

        let candidates = AudioSetupDetector.blackHoleCandidates(in: devices)
        XCTAssertEqual(candidates.map(\.id), ["2", "3"])
    }
}

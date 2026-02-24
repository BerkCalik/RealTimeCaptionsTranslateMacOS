import AVFoundation
import XCTest
@testable import RealTimeCaptionsTranslatorCore

final class SubtitleViewModelTranslationTests: XCTestCase {
    @MainActor
    func testKeepTechWordsOriginalDefaultsToTrue() {
        let settingsStore = makeSettingsStore()
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: MockRealtimeService(events: []),
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        XCTAssertTrue(viewModel.keepTechWordsOriginal)
    }

    @MainActor
    func testLatencyPresetDefaultsToBalanced() {
        let settingsStore = makeSettingsStore()
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: MockRealtimeService(events: []),
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        XCTAssertEqual(viewModel.selectedLatencyPreset, .balanced)
    }

    @MainActor
    func testRefreshDevicesSetsBlackHoleMissingState() async {
        let settingsStore = makeSettingsStore()
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(
                devices: [
                    AudioInputDevice(id: "1", name: "MacBook Microphone")
                ]
            ),
            realtimeService: MockRealtimeService(events: []),
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        await viewModel.refreshDevicesAndSetupState()

        XCTAssertEqual(viewModel.audioSetupState, .blackHoleMissing)
        XCTAssertTrue(viewModel.blackHoleCandidates.isEmpty)
    }

    @MainActor
    func testRefreshDevicesSetsBlackHoleAvailableNotSelectedState() async {
        let settingsStore = makeSettingsStore()
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(
                devices: [
                    AudioInputDevice(id: "1", name: "MacBook Microphone"),
                    AudioInputDevice(id: "2", name: "BlackHole 2ch")
                ]
            ),
            realtimeService: MockRealtimeService(events: []),
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        await viewModel.refreshDevicesAndSetupState()
        viewModel.selectedDeviceID = "1"

        XCTAssertEqual(viewModel.audioSetupState, .blackHoleAvailableNotSelected)
        XCTAssertEqual(viewModel.blackHoleCandidates.first?.id, "2")
    }

    @MainActor
    func testSelectFirstBlackHoleSetsSelectedDeviceAndState() async {
        let settingsStore = makeSettingsStore()
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(
                devices: [
                    AudioInputDevice(id: "1", name: "MacBook Microphone"),
                    AudioInputDevice(id: "2", name: "BlackHole 2ch"),
                    AudioInputDevice(id: "3", name: "BlackHole 16ch")
                ]
            ),
            realtimeService: MockRealtimeService(events: []),
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        await viewModel.refreshDevicesAndSetupState()
        viewModel.selectedDeviceID = "1"
        viewModel.selectFirstBlackHoleIfAvailable()

        XCTAssertEqual(viewModel.selectedDeviceID, "2")
        XCTAssertEqual(viewModel.audioSetupState, .blackHoleSelected)
    }

    @MainActor
    func testApplyKeepTechWordsPreferencePropagatesToService() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [])
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.keepTechWordsOriginal = false
        viewModel.applyKeepTechWordsPreference()
        await waitUntilAsync {
            await realtimeService.lastKeepTechWordsOriginal == false
        }

        let persisted = await realtimeService.lastKeepTechWordsOriginal
        XCTAssertEqual(persisted, false)
        XCTAssertEqual(viewModel.statusText, "Tech words can be translated")
    }

    @MainActor
    func testApplyLatencyPresetPropagatesToService() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [])
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.selectedLatencyPreset = .ultraFast
        viewModel.applyLatencyPreset()
        await waitUntilAsync {
            await realtimeService.lastLatencyPreset == .ultraFast
        }

        let persisted = await realtimeService.lastLatencyPreset
        XCTAssertEqual(persisted, .ultraFast)
        XCTAssertEqual(viewModel.statusText, "Latency preset: Ultra Fast")
    }

    @MainActor
    func testStartAppliesSelectedLatencyPresetToService() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [])
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.selectedLatencyPreset = .stable
        viewModel.start()

        await waitUntilAsync {
            await realtimeService.lastLatencyPreset == .stable
        }

        let persisted = await realtimeService.lastLatencyPreset
        XCTAssertEqual(persisted, .stable)
    }

    @MainActor
    func testClearSubtitlesClearsEnglishAndTurkishPanels() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [
            .englishDelta(itemID: "i1", text: "hello"),
            .englishFinal(itemID: "i1", text: "hello world"),
            .turkishDelta(responseID: "r1", text: "merhaba"),
            .turkishFinal(responseID: "r1")
        ])

        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.start()
        await waitUntil { viewModel.subtitleLines.isEmpty == false && viewModel.translatedLines.isEmpty == false }

        XCTAssertFalse(viewModel.subtitleLines.isEmpty)
        XCTAssertFalse(viewModel.translatedLines.isEmpty)

        viewModel.clearSubtitles()

        XCTAssertTrue(viewModel.subtitleLines.isEmpty)
        XCTAssertTrue(viewModel.translatedLines.isEmpty)
    }

    @MainActor
    func testEnglishAndTurkishStreamsUpdatePanelsIndependently() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [
            .englishDelta(itemID: "i1", text: "this is"),
            .englishDelta(itemID: "i1", text: "this is a test"),
            .englishFinal(itemID: "i1", text: "this is a test"),
            .turkishDelta(responseID: "r1", text: "bu bir"),
            .turkishDelta(responseID: "r1", text: "bu bir test"),
            .turkishFinal(responseID: "r1")
        ])

        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.start()
        await waitUntil { viewModel.translatedLines.isEmpty == false && viewModel.subtitleLines.isEmpty == false }

        XCTAssertTrue(viewModel.subtitleLines.joined(separator: " ").localizedCaseInsensitiveContains("this is a test"))
        XCTAssertTrue(viewModel.translatedLines.joined(separator: " ").localizedCaseInsensitiveContains("bu bir test"))
    }

    @MainActor
    func testEnglishPanelContinuesWhenTranslationFinalMissing() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [
            .englishDelta(itemID: "i1", text: "build"),
            .englishFinal(itemID: "i1", text: "build succeeded"),
            .turkishDelta(responseID: "r1", text: "derleme")
        ])

        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.start()
        await waitUntil { viewModel.subtitleLines.isEmpty == false }

        XCTAssertTrue(viewModel.subtitleLines.joined(separator: " ").localizedCaseInsensitiveContains("build succeeded"))
        XCTAssertTrue(viewModel.translatedLines.joined(separator: " ").localizedCaseInsensitiveContains("derleme"))
    }

    @MainActor
    func testSwitchingLiveTranslationResponseDoesNotCommitOldPartial() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [
            .turkishDelta(responseID: "r1", text: "merhaba"),
            .turkishDelta(responseID: "r2", text: "merhaba dunya")
        ])

        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.start()
        await waitUntil { viewModel.translatedLines.isEmpty == false }

        let rendered = viewModel.translatedLines.joined(separator: " ")
        XCTAssertTrue(rendered.localizedCaseInsensitiveContains("merhaba dunya"))
        XCTAssertEqual(rendered.components(separatedBy: "merhaba").count - 1, 1)
    }

    @MainActor
    func testApplySelectedTranslationModelShowsInfoOnSuccess() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [])
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.selectedTranslationModel = .realtime
        viewModel.applySelectedTranslationModel()

        await waitUntil { viewModel.errorAlertMessage != nil }

        XCTAssertEqual(viewModel.alertTitle, "Info")
        XCTAssertTrue((viewModel.errorAlertMessage ?? "").localizedCaseInsensitiveContains("access test succeeded"))
        let validated = await realtimeService.lastValidatedModel
        XCTAssertEqual(validated, .realtime)
    }

    @MainActor
    func testApplySelectedTranslationModelShowsErrorOnFailure() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [], validateError: SubtitleError.translationFailed("401 Unauthorized"))
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.selectedTranslationModel = .realtimeMini
        viewModel.applySelectedTranslationModel()

        await waitUntil { viewModel.errorAlertMessage != nil }

        XCTAssertEqual(viewModel.alertTitle, "Error")
        XCTAssertTrue((viewModel.errorAlertMessage ?? "").localizedCaseInsensitiveContains("failed"))
    }

    @MainActor
    func testStartFailureShowsPopup() async {
        let settingsStore = makeSettingsStore()
        let realtimeService = MockRealtimeService(events: [], startError: SubtitleError.translationFailed("Realtime unavailable"))
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            microphonePermissionProvider: { true }
        )

        viewModel.start()
        await waitUntil { viewModel.errorAlertMessage != nil }

        XCTAssertEqual(viewModel.alertTitle, "Error")
        XCTAssertTrue((viewModel.errorAlertMessage ?? "").contains("Realtime unavailable"))
    }

    @MainActor
    func testApplyAPITokenPersistsAndPropagatesToService() async {
        let settingsStore = makeSettingsStore()
        let apiTokenStore = InMemoryAPITokenStore()
        let realtimeService = MockRealtimeService(events: [])
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            apiTokenStore: apiTokenStore,
            microphonePermissionProvider: { true }
        )

        viewModel.apiToken = "sk-test-token"
        viewModel.applyAPIToken()

        await waitUntilAsync {
            await realtimeService.lastAPIToken == "sk-test-token"
        }

        XCTAssertEqual(apiTokenStore.loadToken(), "sk-test-token")
        XCTAssertNil(settingsStore.string(forKey: "settings.apiToken"))
        XCTAssertEqual(viewModel.statusText, "API token saved")
    }

    @MainActor
    func testSettingsLoadOnNewViewModelInstance() async {
        let settingsStore = makeSettingsStore()
        let apiTokenStore = InMemoryAPITokenStore()
        settingsStore.set(34.0, forKey: "settings.fontSize")
        settingsStore.set(TranslationModelOption.realtime.rawValue, forKey: "settings.selectedTranslationModel")
        settingsStore.set(TranslationLatencyPreset.ultraFast.rawValue, forKey: "settings.selectedLatencyPreset")
        settingsStore.set(false, forKey: "settings.keepTechWordsOriginal")
        apiTokenStore.saveToken("sk-restored")

        let realtimeService = MockRealtimeService(events: [])
        let viewModel = SubtitleViewModel(
            audioService: MockAudioCaptureService(),
            realtimeService: realtimeService,
            settingsStore: settingsStore,
            apiTokenStore: apiTokenStore,
            microphonePermissionProvider: { true }
        )

        XCTAssertEqual(viewModel.fontSize, 34)
        XCTAssertEqual(viewModel.selectedTranslationModel, .realtime)
        XCTAssertEqual(viewModel.selectedLatencyPreset, .ultraFast)
        XCTAssertFalse(viewModel.keepTechWordsOriginal)
        XCTAssertEqual(viewModel.apiToken, "sk-restored")

        await waitUntilAsync {
            await realtimeService.lastAPIToken == "sk-restored"
        }
    }

    @MainActor
    private func waitUntil(
        iterations: Int = 80,
        intervalNanoseconds: UInt64 = 50_000_000,
        condition: () -> Bool
    ) async {
        for _ in 0 ..< iterations where condition() == false {
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }

    @MainActor
    private func waitUntilAsync(
        iterations: Int = 80,
        intervalNanoseconds: UInt64 = 50_000_000,
        condition: () async -> Bool
    ) async {
        for _ in 0 ..< iterations {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }

    private func makeSettingsStore() -> UserDefaults {
        let suiteName = "RealTimeCaptionsTranslatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class InMemoryAPITokenStore: APITokenStoring {
    private var token: String?

    func loadToken() -> String? {
        token
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = trimmed.isEmpty ? nil : trimmed
    }

    func deleteToken() {
        token = nil
    }
}

private final class MockAudioCaptureService: AudioCaptureServicing {
    private let devices: [AudioInputDevice]

    init(devices: [AudioInputDevice] = [AudioInputDevice(id: "1", name: "Mock Input")]) {
        self.devices = devices
    }

    func availableInputDevices() async throws -> [AudioInputDevice] {
        devices
    }

    func startCapture(deviceID _: String) throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stopCapture() async {}
}

private actor MockRealtimeService: RealtimeSpeechTranslationServicing {
    private let events: [RealtimeCaptionEvent]
    private let validateError: Error?
    private let startError: Error?
    private(set) var lastValidatedModel: TranslationModelOption?
    private(set) var lastKeepTechWordsOriginal: Bool?
    private(set) var lastLatencyPreset: TranslationLatencyPreset?
    private(set) var lastAPIToken: String?

    init(events: [RealtimeCaptionEvent], validateError: Error? = nil, startError: Error? = nil) {
        self.events = events
        self.validateError = validateError
        self.startError = startError
    }

    func startSession(deviceID _: String, model _: TranslationModelOption) async throws -> AsyncThrowingStream<RealtimeCaptionEvent, Error> {
        if let startError {
            throw startError
        }

        let events = self.events
        return AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                continuation.finish()
            }
        }
    }

    func stopSession() async {}

    func validateModelAccess(model: TranslationModelOption) async throws {
        lastValidatedModel = model
        if let validateError {
            throw validateError
        }
    }

    func setKeepTechWordsOriginal(_ enabled: Bool) async {
        lastKeepTechWordsOriginal = enabled
    }

    func setLatencyPreset(_ preset: TranslationLatencyPreset) async {
        lastLatencyPreset = preset
    }

    func setAPIToken(_ token: String) async {
        lastAPIToken = token
    }
}

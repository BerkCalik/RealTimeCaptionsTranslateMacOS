import AVFoundation
import Foundation

@MainActor
final class SubtitleViewModel: ObservableObject {
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published var selectedDeviceID: String = "" {
        didSet {
            settingsStore.setSelectedDeviceID(selectedDeviceID)
            updateAudioSetupState()
        }
    }

    @Published private(set) var subtitle: SubtitlePayload = .empty
    @Published private(set) var subtitleLines: [String] = []
    @Published private(set) var translatedLines: [String] = []
    @Published var fontSize: Double = 42 {
        didSet { settingsStore.setFontSize(fontSize) }
    }
    @Published var selectedTranslationModel: TranslationModelOption = .realtimeMini {
        didSet { settingsStore.setSelectedTranslationModel(selectedTranslationModel) }
    }
    @Published var selectedLatencyPreset: TranslationLatencyPreset = .balanced {
        didSet { settingsStore.setSelectedLatencyPreset(selectedLatencyPreset) }
    }
    @Published var keepTechWordsOriginal: Bool = true {
        didSet { settingsStore.setKeepTechWordsOriginal(keepTechWordsOriginal) }
    }
    @Published var apiToken: String = "" {
        didSet { settingsStore.setAPIToken(apiToken) }
    }
    @Published private(set) var audioSetupState: AudioSetupState = .ready
    @Published var isSetupGuidePresented: Bool = false
    @Published var isBlackHoleContinueDialogPresented: Bool = false
    @Published private(set) var blackHoleCandidates: [AudioInputDevice] = []
    @Published private(set) var setupSteps: [SetupGuideAction] = []

    @Published private(set) var state: SubtitleState = .idle
    @Published private(set) var statusText: String = "Idle"
    @Published private(set) var alertTitle: String = "Error"
    @Published var errorAlertMessage: String?

    private let audioService: AudioCaptureServicing
    private let realtimeService: RealtimeSpeechTranslationServicing
    private let microphonePermissionProvider: @Sendable () async -> Bool
    private let settingsStore: SubtitleViewModelSettingsStore
    private let systemActions: SubtitleViewModelSystemActions

    private var streamingTask: Task<Void, Never>?
    private var captionReducer = SubtitleViewModelCaptionReducer()
    private static let blackHoleDownloadURL = URL(string: "https://existential.audio/blackhole/")!
    private static let soundInputSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.sound?input")!

    var isListening: Bool {
        if case .listening = state {
            return true
        }
        return false
    }

    init(
        audioService: AudioCaptureServicing,
        realtimeService: RealtimeSpeechTranslationServicing,
        settingsStore: UserDefaults = .standard,
        systemActions: SubtitleViewModelSystemActions = .init(),
        apiTokenStore: any APITokenStoring = KeychainAPITokenStore(),
        microphonePermissionProvider: @escaping @Sendable () async -> Bool = {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    ) {
        self.audioService = audioService
        self.realtimeService = realtimeService
        self.settingsStore = SubtitleViewModelSettingsStore(defaults: settingsStore, tokenStore: apiTokenStore)
        self.systemActions = systemActions
        self.microphonePermissionProvider = microphonePermissionProvider

        loadPersistedSettings()
        updateAudioSetupState()

        Task { [apiToken] in
            await realtimeService.setAPIToken(apiToken)
        }
    }

    func refreshDevices() async {
        await refreshDevicesAndSetupState()
    }

    func refreshDevicesAndSetupState() async {
        do {
            let fetchedDevices = try await audioService.availableInputDevices()
            devices = fetchedDevices

            if selectedDeviceID.isEmpty {
                selectedDeviceID = fetchedDevices.first?.id ?? ""
            } else if fetchedDevices.contains(where: { $0.id == selectedDeviceID }) == false {
                selectedDeviceID = fetchedDevices.first?.id ?? ""
            }

            if fetchedDevices.isEmpty {
                state = .error(SubtitleError.noInputDevices.localizedDescription)
                statusText = SubtitleError.noInputDevices.localizedDescription
                presentErrorAlert(SubtitleError.noInputDevices.localizedDescription)
            } else if case .error = state {
                state = .idle
                statusText = "Idle"
            }
            updateAudioSetupState()
            if audioSetupState == .blackHoleMissing, fetchedDevices.isEmpty == false, isListening == false {
                statusText = "BlackHole not found. If newly installed, reopen audio apps and refresh."
            }
        } catch {
            state = .error(error.localizedDescription)
            statusText = error.localizedDescription
            presentErrorAlert(error.localizedDescription)
            updateAudioSetupState()
        }
    }

    func start() {
        start(ignoreSetupWarning: false)
    }

    func continueStartWithoutBlackHole() {
        isBlackHoleContinueDialogPresented = false
        start(ignoreSetupWarning: true)
    }

    func openSetupGuide() {
        isSetupGuidePresented = true
    }

    func closeSetupGuide() {
        isSetupGuidePresented = false
    }

    func openSetupFromStartWarning() {
        isBlackHoleContinueDialogPresented = false
        openSetupGuide()
    }

    func selectFirstBlackHoleIfAvailable() {
        guard let first = blackHoleCandidates.first else {
            statusText = "BlackHole device not found"
            return
        }
        selectedDeviceID = first.id
        statusText = "BlackHole selected: \(first.name)"
    }

    func openBlackHoleDownloadPage() {
        if systemActions.openURL(Self.blackHoleDownloadURL) == false {
            presentErrorAlert("Unable to open BlackHole download page: \(Self.blackHoleDownloadURL.absoluteString)")
        }
    }

    func openAudioMidiSetup() {
        if systemActions.openAudioMidiSetup() {
            return
        }
        presentErrorAlert("Unable to open Audio MIDI Setup. Open it manually from Applications > Utilities.")
    }

    func openSoundInputSettings() {
        if systemActions.openURL(Self.soundInputSettingsURL) == false {
            presentErrorAlert("Unable to open Sound Input settings.")
        }
    }

    private func start(ignoreSetupWarning: Bool) {
        guard streamingTask == nil else { return }

        if ignoreSetupWarning == false,
           audioSetupState == .blackHoleMissing,
           devices.isEmpty == false {
            isBlackHoleContinueDialogPresented = true
            statusText = "BlackHole not detected"
            return
        }

        streamingTask = Task { @MainActor [weak self] in
            await self?.runSession()
        }
    }

    func stop() {
        Task { @MainActor [weak self] in
            await self?.stopInternal(status: "Stopped")
        }
    }

    func applySelectedTranslationModel() {
        let targetModel = selectedTranslationModel
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                await self.realtimeService.setAPIToken(self.apiToken)
                try await self.realtimeService.validateModelAccess(model: targetModel)
                self.statusText = "Model access ready: \(targetModel.title)"
                self.presentInfoAlert("OpenAI access test succeeded for \(targetModel.title).")

                if self.isListening {
                    await self.stopInternal(status: "WebRTC restarting...")
                    self.start()
                }
            } catch is CancellationError {
                return
            } catch {
                self.statusText = "Model access failed"
                self.presentErrorAlert("\(targetModel.title) model access test failed: \(error.localizedDescription)")
            }
        }
    }

    func applyAPIToken() {
        apiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentToken = apiToken

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.realtimeService.setAPIToken(currentToken)

            if currentToken.isEmpty {
                self.statusText = "API token cleared"
            } else {
                self.statusText = "API token saved"
            }
        }
    }

    func applyKeepTechWordsPreference() {
        let enabled = keepTechWordsOriginal
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.realtimeService.setKeepTechWordsOriginal(enabled)
            self.statusText = enabled ? "Tech words kept original" : "Tech words can be translated"
        }
    }

    func applyLatencyPreset() {
        let preset = selectedLatencyPreset
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.realtimeService.setLatencyPreset(preset)
            self.statusText = "Latency preset: \(preset.title)"
        }
    }

    func clearSubtitles() {
        captionReducer.clearAll()
        syncCaptionOutputs()
    }

    func copyEnglishText() {
        copyText(subtitleLines.joined(separator: "\n"), language: "English")
    }

    func copyTurkishText() {
        copyText(translatedLines.joined(separator: "\n"), language: "Turkish")
    }

    func shutdown() async {
        await stopInternal(status: "Idle")
    }

    func dismissErrorAlert() {
        errorAlertMessage = nil
    }

    private func runSession() async {
        do {
            statusText = "WebRTC connecting..."
            try await SubtitleViewModelSessionPreparation.ensureMicrophonePermission(using: microphonePermissionProvider)

            if devices.isEmpty {
                await refreshDevicesAndSetupState()
            }

            guard selectedDeviceID.isEmpty == false else {
                throw SubtitleError.invalidDevice
            }

            captionReducer.resetTurkishFinalDeduplication()
            try await SubtitleViewModelSessionPreparation.configureRealtimeService(
                realtimeService,
                apiToken: apiToken,
                keepTechWordsOriginal: keepTechWordsOriginal,
                latencyPreset: selectedLatencyPreset,
                model: selectedTranslationModel
            )

            let eventStream = try await realtimeService.startSession(
                deviceID: selectedDeviceID,
                model: selectedTranslationModel
            )

            state = .listening
            statusText = "Listening (Realtime)"

            for try await event in eventStream {
                if Task.isCancelled { break }
                processRealtimeEvent(event)
            }

            if Task.isCancelled == false {
                state = .idle
                statusText = "WebRTC disconnected"
            }
        } catch is CancellationError {
            state = .idle
            statusText = "Stopped"
        } catch {
            state = .error(error.localizedDescription)
            statusText = error.localizedDescription
            presentErrorAlert(error.localizedDescription)
        }

        await realtimeService.stopSession()
        captionReducer.resetTurkishFinalDeduplication()
        streamingTask = nil

        if case .error = state {
            return
        }

        if isListening {
            state = .idle
            statusText = "Idle"
        }
    }

    private func stopInternal(status: String) async {
        let runningTask = streamingTask
        streamingTask = nil
        runningTask?.cancel()

        await realtimeService.stopSession()
        captionReducer.resetTurkishFinalDeduplication()

        state = .idle
        statusText = status
    }

    private func processRealtimeEvent(_ event: RealtimeCaptionEvent) {
        switch event {
        case .englishDelta(let itemID, let text):
            captionReducer.handleEnglishDelta(itemID: itemID, text: text)
            syncCaptionOutputs()

        case .englishFinal(let itemID, let text):
            captionReducer.handleEnglishFinal(itemID: itemID, text: text)
            syncCaptionOutputs()

        case .turkishDelta(let responseID, let text):
            captionReducer.handleTurkishDelta(responseID: responseID, text: text)
            syncCaptionOutputs()

        case .turkishFinal(let responseID):
            captionReducer.handleTurkishFinal(responseID: responseID)
            syncCaptionOutputs()

        case .speechStarted:
            if isListening {
                statusText = "Listening (Realtime)"
            }

        case .speechStopped:
            if isListening {
                statusText = "Listening (Realtime)"
            }

        case .status(let message):
            statusText = message
        }
    }

    private func syncCaptionOutputs() {
        subtitle = captionReducer.subtitle
        subtitleLines = captionReducer.subtitleLines
        translatedLines = captionReducer.translatedLines
    }

    private func updateAudioSetupState() {
        let resolution = SubtitleViewModelAudioSetupStateResolver.resolve(
            devices: devices,
            selectedDeviceID: selectedDeviceID
        )
        blackHoleCandidates = resolution.blackHoleCandidates
        audioSetupState = resolution.audioSetupState
        setupSteps = resolution.setupSteps
    }

    private func presentErrorAlert(_ message: String) {
        guard let alert = SubtitleViewModelAlertFactory.error(message) else { return }
        applyAlert(alert)
    }

    private func presentInfoAlert(_ message: String) {
        guard let alert = SubtitleViewModelAlertFactory.info(message) else { return }
        applyAlert(alert)
    }

    private func applyAlert(_ alert: SubtitleViewModelAlertState) {
        alertTitle = alert.title
        errorAlertMessage = nil
        errorAlertMessage = alert.message
    }

    private func loadPersistedSettings() {
        let persisted = settingsStore.load()

        if let value = persisted.selectedDeviceID {
            selectedDeviceID = value
        }
        if let value = persisted.selectedTranslationModel {
            selectedTranslationModel = value
        }
        if let value = persisted.selectedLatencyPreset {
            selectedLatencyPreset = value
        }
        if let value = persisted.keepTechWordsOriginal {
            keepTechWordsOriginal = value
        }
        if let value = persisted.fontSize {
            fontSize = value
        }
        if let value = persisted.apiToken {
            apiToken = value
        }
    }

    private func copyText(_ text: String, language: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            statusText = "\(language) text is empty"
            return
        }

        systemActions.copyStringToPasteboard(normalized)
        statusText = "\(language) text copied"
    }
}

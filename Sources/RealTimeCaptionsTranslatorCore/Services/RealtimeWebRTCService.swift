import CoreAudio
import Foundation
import WebRTC

actor RealtimeWebRTCService: RealtimeSpeechTranslationServicing {
    private enum EmbeddedConfig {
        static let callsEndpoint = URL(string: "https://api.openai.com/v1/realtime/calls")!
        static let modelsEndpoint = URL(string: "https://api.openai.com/v1/models")!
    }

    enum TranslationRequestMode: Equatable {
        case live
        case final
    }

    struct TranslationRequest: Equatable {
        let id: String
        let itemID: String
        let english: String
        let mode: TranslationRequestMode
    }

    struct LatencyProfile: Equatable {
        let liveEnabled: Bool
        let debounceNs: UInt64
        let vadThreshold: Double
        let vadPrefixMs: Int
        let vadSilenceMs: Int
    }

    private var apiKey: String?
    private let callsEndpoint: URL
    private let modelsEndpoint: URL
    private let session: URLSession

    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?
    private var delegateBridge: RealtimeWebRTCDelegateBridge?

    private var continuation: AsyncThrowingStream<RealtimeCaptionEvent, Error>.Continuation?
    private var keepTechWordsOriginal = true
    private var latencyPreset: TranslationLatencyPreset = .balanced

    private var responseTracker = RealtimeTranslationResponseTracker()
    private var pendingFinalTranslationQueue: [TranslationRequest] = []
    private var pendingLiveTranslationRequest: TranslationRequest?
    private var liveDispatchTask: Task<Void, Never>?
    private var translationRequestCounter = 0

    private var previousDefaultInputDeviceID: AudioDeviceID?
    private var isStarting = false

    private let maxTranslationQueueSize = 50
    private let logPrefix = "[OpenAIWS]"

    init(
        apiKey: String? = nil,
        callsEndpoint: URL = EmbeddedConfig.callsEndpoint,
        modelsEndpoint: URL = EmbeddedConfig.modelsEndpoint,
        session: URLSession = .shared
    ) {
        self.apiKey = Self.normalizeToken(apiKey)
        self.callsEndpoint = callsEndpoint
        self.modelsEndpoint = modelsEndpoint
        self.session = session
    }

    func validateModelAccess(model: TranslationModelOption) async throws {
        guard let apiKey,
              apiKey.isEmpty == false else {
            throw SubtitleError.translationAPIKeyMissing
        }

        var request = URLRequest(url: modelsEndpoint.appendingPathComponent(model.rawValue))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SubtitleError.translationFailed("Invalid model response")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            throw SubtitleError.translationFailed(Self.errorMessage(from: data, statusCode: http.statusCode))
        }
    }

    func setKeepTechWordsOriginal(_ enabled: Bool) async {
        keepTechWordsOriginal = enabled
        print("\(logPrefix) keepTechWordsOriginal=\(enabled)")

        do {
            try sendSessionUpdateIfPossible()
        } catch {
            emit(.status("Translation settings update failed"))
            print("\(logPrefix) session.update failed: \(error.localizedDescription)")
        }
    }

    func setLatencyPreset(_ preset: TranslationLatencyPreset) async {
        latencyPreset = preset
        print("\(logPrefix) latencyPreset=\(preset.rawValue)")

        if Self.profile(for: preset).liveEnabled == false {
            pendingLiveTranslationRequest = nil
            liveDispatchTask?.cancel()
            liveDispatchTask = nil

            if responseTracker.activeRequestMode == .live {
                cancelActiveResponseIfPossible()
            }
            return
        }

        if pendingLiveTranslationRequest != nil {
            scheduleLiveTranslationDispatch()
        }
    }

    func setAPIToken(_ token: String) async {
        apiKey = Self.normalizeToken(token)
        print("\(logPrefix) apiTokenUpdated=\((apiKey?.isEmpty == false) ? "yes" : "no")")
    }

    func startSession(deviceID: String, model: TranslationModelOption) async throws -> AsyncThrowingStream<RealtimeCaptionEvent, Error> {
        guard isStarting == false else {
            throw SubtitleError.translationFailed("Session is already starting.")
        }

        isStarting = true
        defer { isStarting = false }

        try await stopSessionInternal(keepDevice: false)

        guard let apiKey,
              apiKey.isEmpty == false else {
            throw SubtitleError.translationAPIKeyMissing
        }

        guard let numericDeviceID = UInt32(deviceID) else {
            throw SubtitleError.invalidDevice
        }

        let selectedDeviceID = AudioDeviceID(numericDeviceID)
        let currentDefault = try CoreAudioDeviceManager.defaultInputDeviceID()
        if currentDefault != selectedDeviceID {
            try CoreAudioDeviceManager.setDefaultInputDevice(selectedDeviceID)
            previousDefaultInputDeviceID = currentDefault
        } else {
            previousDefaultInputDeviceID = nil
        }

        let stream = AsyncThrowingStream<RealtimeCaptionEvent, Error> { continuation in
            self.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.stopSession()
                }
            }
        }

        do {
            try await openPeerConnection(apiKey: apiKey, model: model)
            emit(.status("WebRTC connected"))
            print("\(logPrefix) session started model=\(model.rawValue)")
            return stream
        } catch {
            continuation?.finish(throwing: error)
            continuation = nil
            try await stopSessionInternal(keepDevice: false)
            throw error
        }
    }

    func stopSession() async {
        try? await stopSessionInternal(keepDevice: false)
    }

    private func stopSessionInternal(keepDevice: Bool) async throws {
        if let dataChannel {
            dataChannel.close()
        }
        if let peerConnection {
            peerConnection.close()
        }

        dataChannel = nil
        peerConnection = nil
        localAudioTrack = nil
        delegateBridge = nil
        peerConnectionFactory = nil

        continuation?.finish()
        continuation = nil

        liveDispatchTask?.cancel()
        liveDispatchTask = nil

        responseTracker.reset()
        pendingFinalTranslationQueue.removeAll()
        pendingLiveTranslationRequest = nil
        translationRequestCounter = 0

        if keepDevice == false, let previousDefaultInputDeviceID {
            try? CoreAudioDeviceManager.setDefaultInputDevice(previousDefaultInputDeviceID)
            self.previousDefaultInputDeviceID = nil
        }

        print("\(logPrefix) session stopped")
    }

    private func openPeerConnection(apiKey: String, model: TranslationModelOption) async throws {
        let factory = RTCPeerConnectionFactory()
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        let bridge = RealtimeWebRTCDelegateBridge(owner: self)
        guard let peerConnection = factory.peerConnection(with: configuration, constraints: constraints, delegate: bridge) else {
            throw SubtitleError.translationFailed("Failed to create peer connection")
        }

        let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "local-audio")
        _ = peerConnection.add(audioTrack, streamIds: ["stream-audio"])

        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        guard let dataChannel = peerConnection.dataChannel(forLabel: "oai-events", configuration: dataChannelConfig) else {
            throw SubtitleError.translationFailed("Failed to create data channel")
        }

        dataChannel.delegate = bridge

        peerConnectionFactory = factory
        self.peerConnection = peerConnection
        self.localAudioTrack = audioTrack
        self.dataChannel = dataChannel
        delegateBridge = bridge

        emit(.status("WebRTC connecting..."))

        let offer = try await createOffer(peerConnection: peerConnection, constraints: constraints)
        try await setLocalDescription(offer, peerConnection: peerConnection)

        let answerSDP = try await exchangeSDP(
            offerSDP: offer.sdp,
            apiKey: apiKey,
            model: model
        )

        let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
        try await setRemoteDescription(answer, peerConnection: peerConnection)
    }

    private func createOffer(
        peerConnection: RTCPeerConnection,
        constraints: RTCMediaConstraints
    ) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { sdp, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sdp else {
                    continuation.resume(throwing: SubtitleError.translationFailed("Offer SDP is missing."))
                    return
                }
                continuation.resume(returning: sdp)
            }
        }
    }

    private func setLocalDescription(
        _ sdp: RTCSessionDescription,
        peerConnection: RTCPeerConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(sdp) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }

    private func setRemoteDescription(
        _ sdp: RTCSessionDescription,
        peerConnection: RTCPeerConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(sdp) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }

    private func exchangeSDP(
        offerSDP: String,
        apiKey: String,
        model: TranslationModelOption
    ) async throws -> String {
        try await RealtimeWebRTCSignalingExchange.exchangeSDP(
            offerSDP: offerSDP,
            apiKey: apiKey,
            model: model,
            callsEndpoint: callsEndpoint,
            session: session,
            profile: currentLatencyProfile()
        )
    }

    func handleDataChannelMessage(_ data: Data) async {
        do {
            let json = try RealtimeServerEventParser.parseJSONObject(data: data)
            let stateUpdate = responseTracker.applyServerLifecycleUpdate(json: json)
            if let createdResponseID = stateUpdate.createdResponseID {
                print("\(logPrefix) response created id=\(createdResponseID)")
            }
            let events = try Self.parseServerEvents(json: json)

            for event in events {
                if case .turkishDelta(let responseID, _) = event,
                   responseTracker.shouldEmitTurkishDelta(responseID: responseID) == false {
                    continue
                }

                if case .turkishFinal(let responseID) = event,
                   responseTracker.shouldEmitTurkishFinal(responseID: responseID) == false {
                    continue
                }

                emit(event)
                await processOutgoingActions(for: event)
            }

            if stateUpdate.shouldDispatchNext {
                tryDispatchNextTranslationIfPossible()
            }
        } catch {
            continuation?.finish(throwing: error)
            continuation = nil
            try? await stopSessionInternal(keepDevice: false)
        }
    }

    func handleDataChannelStateChanged(_ state: RTCDataChannelState) async {
        switch state {
        case .open:
            do {
                try sendSessionUpdateIfPossible()
                tryDispatchNextTranslationIfPossible()
            } catch {
                emit(.status("Translation queue waiting"))
            }
            emit(.status("WebRTC channel open"))

        case .closed:
            emit(.status("WebRTC disconnected"))

        default:
            break
        }
    }

    func handlePeerConnectionStateChanged(_ state: RTCPeerConnectionState) async {
        switch state {
        case .connected:
            emit(.status("Listening (Realtime)"))

        case .disconnected, .failed, .closed:
            continuation?.finish(throwing: SubtitleError.translationSocketDisconnected)
            continuation = nil
            try? await stopSessionInternal(keepDevice: false)

        default:
            break
        }
    }

    private func emit(_ event: RealtimeCaptionEvent) {
        continuation?.yield(event)
    }

    private func processOutgoingActions(for event: RealtimeCaptionEvent) async {
        switch event {
        case .englishDelta(let itemID, let text):
            processEnglishDeltaForTranslation(itemID: itemID, text: text)

        case .englishFinal(let itemID, let text):
            processEnglishFinalForTranslation(itemID: itemID, text: text)
            tryDispatchNextTranslationIfPossible()

        default:
            break
        }
    }

    private func processEnglishDeltaForTranslation(itemID: String, text: String) {
        guard currentLatencyProfile().liveEnabled else { return }
        guard let normalized = normalizedTranslationInput(from: text) else { return }

        translationRequestCounter += 1
        pendingLiveTranslationRequest = TranslationRequest(
            id: "live-\(translationRequestCounter)",
            itemID: itemID,
            english: normalized,
            mode: .live
        )
        scheduleLiveTranslationDispatch()

        if responseTracker.activeRequestMode == .live {
            cancelActiveResponseIfPossible()
        }
    }

    private func processEnglishFinalForTranslation(itemID: String, text: String) {
        guard let normalized = normalizedTranslationInput(from: text) else { return }
        liveDispatchTask?.cancel()
        liveDispatchTask = nil

        if pendingLiveTranslationRequest?.itemID == itemID {
            pendingLiveTranslationRequest = nil
        }

        translationRequestCounter += 1
        let request = TranslationRequest(
            id: "final-\(translationRequestCounter)",
            itemID: itemID,
            english: normalized,
            mode: .final
        )

        if let dropped = Self.enqueueLimited(request, into: &pendingFinalTranslationQueue, max: maxTranslationQueueSize) {
            emit(.status("Translation queue overflow, dropped oldest segment."))
            print("\(logPrefix) dropped translation request id=\(dropped.id)")
        }

        if responseTracker.activeRequestMode == .live {
            cancelActiveResponseIfPossible()
        }
    }

    private func scheduleLiveTranslationDispatch() {
        let debounceNanoseconds = currentLatencyProfile().debounceNs
        liveDispatchTask?.cancel()
        liveDispatchTask = Task { [debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard Task.isCancelled == false else { return }
            self.dispatchLiveTranslationIfReady()
        }
    }

    private func dispatchLiveTranslationIfReady() {
        if pendingLiveTranslationRequest == nil {
            return
        }

        if responseTracker.activeRequestMode == .live {
            cancelActiveResponseIfPossible()
            return
        }

        tryDispatchNextTranslationIfPossible()
    }

    private func tryDispatchNextTranslationIfPossible() {
        guard responseTracker.hasActiveResponse == false else { return }
        guard responseTracker.hasPendingCreateRequest == false else { return }
        guard let dataChannel, dataChannel.readyState == .open else { return }

        let request: TranslationRequest
        if pendingFinalTranslationQueue.isEmpty == false {
            request = pendingFinalTranslationQueue.removeFirst()
        } else if let pendingLiveTranslationRequest {
            request = pendingLiveTranslationRequest
            self.pendingLiveTranslationRequest = nil
        } else {
            return
        }

        responseTracker.setPendingCreateRequest(request)

        do {
            let terms = Self.extractTechnicalTerms(from: request.english)
            let instruction = Self.buildTranslationRequestInstructions(
                keepTechWordsOriginal: keepTechWordsOriginal,
                technicalTerms: terms,
                isFinal: request.mode == .final
            )

            let payload: [String: Any] = [
                "type": "response.create",
                "response": [
                    "conversation": "none",
                    "modalities": ["text"],
                    "instructions": instruction,
                    "input": [
                        [
                            "type": "message",
                            "role": "user",
                            "content": [
                                [
                                    "type": "input_text",
                                    "text": request.english
                                ]
                            ]
                        ]
                    ]
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let buffer = RTCDataBuffer(data: data, isBinary: false)
            guard dataChannel.sendData(buffer) else {
                throw SubtitleError.translationFailed("Failed to send translation response.create")
            }
        } catch {
            responseTracker.clearPendingCreateRequest()
            emit(.status("Translation request failed: \(error.localizedDescription)"))
            print("\(logPrefix) response.create failed: \(error.localizedDescription)")

            // Continue draining queue after failure.
            tryDispatchNextTranslationIfPossible()
        }
    }

    private func cancelActiveResponseIfPossible() {
        guard responseTracker.prepareCancelIfPossible() != nil else { return }

        do {
            try sendClientEvent([
                "type": "response.cancel"
            ])
            responseTracker.markCancelSent()
        } catch {
            print("\(logPrefix) response.cancel failed: \(error.localizedDescription)")
        }
    }

    private func normalizedTranslationInput(from text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return isTranslatableInput(normalized) ? normalized : nil
    }

    private func currentLatencyProfile() -> LatencyProfile {
        Self.profile(for: latencyPreset)
    }

    private static func normalizeToken(_ token: String?) -> String? {
        guard let token else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func profile(for preset: TranslationLatencyPreset) -> LatencyProfile {
        switch preset {
        case .stable:
            return LatencyProfile(
                liveEnabled: false,
                debounceNs: 200_000_000,
                vadThreshold: 0.50,
                vadPrefixMs: 180,
                vadSilenceMs: 260
            )
        case .balanced:
            return LatencyProfile(
                liveEnabled: true,
                debounceNs: 200_000_000,
                vadThreshold: 0.45,
                vadPrefixMs: 120,
                vadSilenceMs: 150
            )
        case .ultraFast:
            return LatencyProfile(
                liveEnabled: true,
                debounceNs: 120_000_000,
                vadThreshold: 0.40,
                vadPrefixMs: 80,
                vadSilenceMs: 100
            )
        }
    }

    static func parseServerEvents(data: Data) throws -> [RealtimeCaptionEvent] {
        try RealtimeServerEventParser.parseServerEvents(data: data)
    }

    private static func parseServerEvents(json: [String: Any]) throws -> [RealtimeCaptionEvent] {
        try RealtimeServerEventParser.parseServerEvents(json: json)
    }

    private func sendClientEvent(_ payload: [String: Any]) throws {
        guard let dataChannel else {
            throw SubtitleError.translationSocketDisconnected
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        let sent = dataChannel.sendData(buffer)
        if sent == false {
            throw SubtitleError.translationFailed("Failed to send realtime client event.")
        }
    }

    private func sendSessionUpdateIfPossible() throws {
        guard let dataChannel, dataChannel.readyState == .open else {
            return
        }

        try sendClientEvent([
            "type": "session.update",
            "session": [
                "instructions": Self.buildSessionInstructions()
            ]
        ])
    }

    static func buildSessionInstructions() -> String {
        RealtimeTranslationInstructionBuilder.buildSessionInstructions()
    }

    static func buildTranslationRequestInstructions(
        keepTechWordsOriginal: Bool,
        technicalTerms: [String],
        isFinal: Bool = true
    ) -> String {
        RealtimeTranslationInstructionBuilder.buildTranslationRequestInstructions(
            keepTechWordsOriginal: keepTechWordsOriginal,
            technicalTerms: technicalTerms,
            isFinal: isFinal
        )
    }

    static func extractTechnicalTerms(from englishText: String) -> [String] {
        RealtimeTranslationInstructionBuilder.extractTechnicalTerms(from: englishText)
    }

    static func enqueueLimited<T>(_ item: T, into queue: inout [T], max: Int) -> T? {
        guard max > 0 else {
            return item
        }

        var dropped: T?
        if queue.count >= max {
            dropped = queue.removeFirst()
        }
        queue.append(item)
        return dropped
    }

    private func isTranslatableInput(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }

        if trimmed.rangeOfCharacter(from: .letters) == nil {
            return false
        }

        let lowered = trimmed.lowercased()
        let noiseTokens = ["[silence]", "(silence)", "[noise]", "(noise)"]
        if noiseTokens.contains(lowered) {
            return false
        }

        return true
    }

    private static func errorMessage(from data: Data, statusCode: Int) -> String {
        RealtimeServerEventParser.httpErrorMessage(from: data, statusCode: statusCode)
    }
}

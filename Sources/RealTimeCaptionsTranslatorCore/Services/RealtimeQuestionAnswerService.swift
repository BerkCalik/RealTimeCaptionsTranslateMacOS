import Foundation
import WebRTC

actor RealtimeQuestionAnswerService: RealtimeQuestionAnswerServicing {
    private enum EmbeddedConfig {
        static let callsEndpoint = URL(string: "https://api.openai.com/v1/realtime/calls")!
    }

    private struct QuestionRequest: Equatable {
        let id: String
        let question: String
    }

    private var apiKey: String?
    private let callsEndpoint: URL
    private let session: URLSession

    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var delegateBridge: RealtimeQuestionAnswerDelegateBridge?

    private var continuation: AsyncThrowingStream<QAEvent, Error>.Continuation?
    private var isStarting = false
    private var sessionInstructions = ""
    private var resumeContextText = ""
    private var resumeUsingFallback = true
    private var answerEnglishLevel: QAEnglishLevel = .b1

    private var pendingQuestions: [QuestionRequest] = []
    private var pendingCreateRequest: QuestionRequest?
    private var activeQuestionID: String?
    private var activeResponseID: String?
    private var activeCancelRequested = false
    private var finalizedResponseIDs: Set<String> = []
    private var droppedResponseIDs: Set<String> = []
    private var emittedTextResponseIDs: Set<String> = []

    private let maxQueueSize = 20
    private let logPrefix = "[OpenAIQA]"

    init(
        apiKey: String? = nil,
        callsEndpoint: URL = EmbeddedConfig.callsEndpoint,
        session: URLSession = .shared
    ) {
        self.apiKey = Self.normalizeToken(apiKey)
        self.callsEndpoint = callsEndpoint
        self.session = session
    }

    func setAPIToken(_ token: String) async {
        apiKey = Self.normalizeToken(token)
        print("\(logPrefix) apiTokenUpdated=\((apiKey?.isEmpty == false) ? "yes" : "no")")
    }

    func setAnswerEnglishLevel(_ level: QAEnglishLevel) async {
        answerEnglishLevel = level
    }

    func startSession(apiToken: String) async throws -> AsyncThrowingStream<QAEvent, Error> {
        guard isStarting == false else {
            throw SubtitleError.translationFailed("Q&A session is already starting.")
        }

        isStarting = true
        defer { isStarting = false }

        await setAPIToken(apiToken)
        try await stopSessionInternal()

        guard let apiKey, apiKey.isEmpty == false else {
            throw SubtitleError.translationAPIKeyMissing
        }

        let resume = ResumeContextLoader.load()
        resumeContextText = resume.text
        resumeUsingFallback = resume.usingFallback
        sessionInstructions = RealtimeQuestionAnswerInstructionBuilder.buildSessionInstructions(
            resumeContext: resume.text,
            usingFallback: resume.usingFallback
        )

        let stream = AsyncThrowingStream<QAEvent, Error> { continuation in
            self.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.stopSession()
                }
            }
        }

        emit(.serviceState(.connecting))
        emit(.status("Auto Q&A connecting..."))
        if let message = resume.statusMessage {
            emit(.status(message))
        }

        do {
            try await openPeerConnection(apiKey: apiKey)
            print("\(logPrefix) session started")
            return stream
        } catch {
            continuation?.finish(throwing: error)
            continuation = nil
            try? await stopSessionInternal()
            throw error
        }
    }

    func stopSession() async {
        try? await stopSessionInternal()
    }

    func submit(questionID: String, question: String) async {
        let normalized = question
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.isEmpty == false else { return }

        let request = QuestionRequest(id: questionID, question: normalized)
        if let dropped = Self.enqueueLimited(request, into: &pendingQuestions, max: maxQueueSize) {
            emit(.responseFailed(questionID: dropped.id, message: "Q&A queue overflow, dropped."))
            emit(.status("Auto Q&A queue overflow, dropped oldest question."))
        }

        tryDispatchNextIfPossible()
    }

    func cancelActiveResponse() async {
        guard activeCancelRequested == false, let activeResponseID else { return }
        droppedResponseIDs.insert(activeResponseID)
        activeCancelRequested = true

        do {
            try sendClientEvent(["type": "response.cancel"])
        } catch {
            print("\(logPrefix) response.cancel failed: \(error.localizedDescription)")
        }
    }

    private func stopSessionInternal() async throws {
        if let dataChannel {
            dataChannel.close()
        }
        if let peerConnection {
            peerConnection.close()
        }

        dataChannel = nil
        peerConnection = nil
        delegateBridge = nil
        peerConnectionFactory = nil

        continuation?.finish()
        continuation = nil

        pendingQuestions.removeAll()
        pendingCreateRequest = nil
        activeQuestionID = nil
        activeResponseID = nil
        activeCancelRequested = false
        finalizedResponseIDs.removeAll()
        droppedResponseIDs.removeAll()
        emittedTextResponseIDs.removeAll()
        sessionInstructions = ""
        resumeContextText = ""
        resumeUsingFallback = true
    }

    private func openPeerConnection(apiKey: String) async throws {
        let factory = RTCPeerConnectionFactory()
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        let bridge = RealtimeQuestionAnswerDelegateBridge(owner: self)
        guard let peerConnection = factory.peerConnection(with: configuration, constraints: constraints, delegate: bridge) else {
            throw SubtitleError.translationFailed("Failed to create Q&A peer connection")
        }

        // OpenAI Realtime WebRTC signaling currently expects an audio m-line in the SDP offer,
        // even for text-only data-channel usage. Add a recvonly audio transceiver to satisfy that.
        let audioTransceiverInit = RTCRtpTransceiverInit()
        audioTransceiverInit.direction = .recvOnly
        _ = peerConnection.addTransceiver(of: .audio, init: audioTransceiverInit)

        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        guard let dataChannel = peerConnection.dataChannel(forLabel: "oai-events", configuration: dataChannelConfig) else {
            throw SubtitleError.translationFailed("Failed to create Q&A data channel")
        }

        dataChannel.delegate = bridge

        peerConnectionFactory = factory
        self.peerConnection = peerConnection
        self.dataChannel = dataChannel
        delegateBridge = bridge

        let offer = try await createOffer(peerConnection: peerConnection, constraints: constraints)
        try await setLocalDescription(offer, peerConnection: peerConnection)

        let answerSDP = try await RealtimeQuestionAnswerSignalingExchange.exchangeSDP(
            offerSDP: offer.sdp,
            apiKey: apiKey,
            callsEndpoint: callsEndpoint,
            session: session,
            sessionInstructions: sessionInstructions
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

    func handleDataChannelStateChanged(_ state: RTCDataChannelState) async {
        switch state {
        case .open:
            do {
                try sendSessionUpdateIfPossible()
                tryDispatchNextIfPossible()
            } catch {
                emit(.status("Auto Q&A session.update failed"))
            }
            emit(.serviceState(.ready))
            emit(.status("Auto Q&A ready"))

        case .closed:
            emit(.status("Auto Q&A disconnected"))

        default:
            break
        }
    }

    func handlePeerConnectionStateChanged(_ state: RTCPeerConnectionState) async {
        switch state {
        case .connected:
            emit(.status("Auto Q&A connected"))
        case .disconnected, .failed, .closed:
            continuation?.finish(throwing: SubtitleError.translationSocketDisconnected)
            continuation = nil
            try? await stopSessionInternal()
        default:
            break
        }
    }

    func handleDataChannelMessage(_ data: Data) async {
        do {
            let json = try RealtimeServerEventParser.parseJSONObject(data: data)
            try processServerEvent(json: json)
        } catch {
            continuation?.finish(throwing: error)
            continuation = nil
            try? await stopSessionInternal()
        }
    }

    private func processServerEvent(json: [String: Any]) throws {
        guard let type = json["type"] as? String else { return }

        switch type {
        case "response.created":
            guard let responseID = RealtimeServerEventParser.responseID(from: json),
                  responseID.isEmpty == false else { return }
            activeResponseID = responseID
            activeQuestionID = pendingCreateRequest?.id
            pendingCreateRequest = nil
            activeCancelRequested = false
            finalizedResponseIDs.remove(responseID)
            emittedTextResponseIDs.remove(responseID)
            if let activeQuestionID {
                emit(.responseStarted(questionID: activeQuestionID))
            }

        case "response.output_text.delta":
            guard let delta = json["delta"] as? String, delta.isEmpty == false else { return }
            let responseID = (json["response_id"] as? String) ?? RealtimeServerEventParser.responseID(from: json) ?? activeResponseID
            guard let responseID else { return }
            guard shouldEmitDelta(for: responseID) else { return }
            emittedTextResponseIDs.insert(responseID)
            guard let questionID = questionID(for: responseID) else { return }
            emit(.answerDelta(questionID: questionID, text: delta))

        case "response.output_text.done":
            let responseID = (json["response_id"] as? String) ?? RealtimeServerEventParser.responseID(from: json) ?? activeResponseID
            guard let responseID else { return }
            if let text = json["text"] as? String,
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
               emittedTextResponseIDs.contains(responseID) == false,
               shouldEmitDelta(for: responseID),
               let questionID = questionID(for: responseID) {
                emittedTextResponseIDs.insert(responseID)
                emit(.answerDelta(questionID: questionID, text: text))
            }

        case "response.done":
            let responseID = RealtimeServerEventParser.responseID(from: json) ?? activeResponseID
            guard let responseID else {
                tryDispatchNextIfPossible()
                return
            }

            if let text = RealtimeServerEventParser.responseText(from: json),
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
               emittedTextResponseIDs.contains(responseID) == false,
               shouldEmitDelta(for: responseID),
               let questionID = questionID(for: responseID) {
                emittedTextResponseIDs.insert(responseID)
                emit(.answerDelta(questionID: questionID, text: text))
            }

            if shouldEmitCompletion(for: responseID), let questionID = questionID(for: responseID) {
                emit(.answerCompleted(questionID: questionID))
            }
            clearActiveIfNeeded(responseID: responseID)
            tryDispatchNextIfPossible()

        case "response.failed":
            let responseID = RealtimeServerEventParser.responseID(from: json) ?? activeResponseID
            let message = (json["error"] as? [String: Any]).flatMap { $0["message"] as? String } ?? "Auto Q&A response failed"
            if let responseID, let questionID = questionID(for: responseID) {
                finalizedResponseIDs.insert(responseID)
                emit(.responseFailed(questionID: questionID, message: message))
                clearActiveIfNeeded(responseID: responseID)
            }
            tryDispatchNextIfPossible()

        case "response.cancelled":
            let responseID = RealtimeServerEventParser.responseID(from: json) ?? activeResponseID
            if let responseID, let questionID = questionID(for: responseID) {
                finalizedResponseIDs.insert(responseID)
                emit(.responseFailed(questionID: questionID, message: "Auto Q&A response cancelled"))
                clearActiveIfNeeded(responseID: responseID)
            }
            tryDispatchNextIfPossible()

        case "error":
            let message = RealtimeServerEventParser.realtimeErrorMessage(from: json) ?? "Unknown realtime error"
            if RealtimeServerEventParser.isIgnorableCancellationErrorMessage(message) {
                activeResponseID = nil
                activeQuestionID = nil
                activeCancelRequested = false
                pendingCreateRequest = nil
                tryDispatchNextIfPossible()
                return
            }

            if let questionID = activeQuestionID {
                emit(.responseFailed(questionID: questionID, message: message))
            }
            activeResponseID = nil
            activeQuestionID = nil
            activeCancelRequested = false
            pendingCreateRequest = nil
            emit(.status("Auto Q&A error: \(message)"))
            tryDispatchNextIfPossible()

        default:
            break
        }
    }

    private func shouldEmitDelta(for responseID: String) -> Bool {
        droppedResponseIDs.contains(responseID) == false
    }

    private func shouldEmitCompletion(for responseID: String) -> Bool {
        if droppedResponseIDs.contains(responseID) {
            droppedResponseIDs.remove(responseID)
            finalizedResponseIDs.insert(responseID)
            return false
        }
        if finalizedResponseIDs.contains(responseID) {
            return false
        }
        finalizedResponseIDs.insert(responseID)
        return true
    }

    private func questionID(for responseID: String) -> String? {
        guard activeResponseID == responseID else { return nil }
        return activeQuestionID
    }

    private func clearActiveIfNeeded(responseID: String) {
        guard activeResponseID == responseID else { return }
        activeResponseID = nil
        activeQuestionID = nil
        activeCancelRequested = false
    }

    private func tryDispatchNextIfPossible() {
        guard activeResponseID == nil else { return }
        guard pendingCreateRequest == nil else { return }
        guard let dataChannel, dataChannel.readyState == .open else { return }
        guard pendingQuestions.isEmpty == false else { return }

        let request = pendingQuestions.removeFirst()
        pendingCreateRequest = request

        do {
            let payload: [String: Any] = [
                "type": "response.create",
                "response": [
                    "conversation": "none",
                    "modalities": ["text"],
                    "instructions": RealtimeQuestionAnswerInstructionBuilder.buildAnswerRequestInstructions(
                        resumeContext: resumeContextText,
                        usingFallback: resumeUsingFallback,
                        englishLevel: answerEnglishLevel
                    ),
                    "input": [
                        [
                            "type": "message",
                            "role": "user",
                            "content": [
                                [
                                    "type": "input_text",
                                    "text": request.question
                                ]
                            ]
                        ]
                    ]
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let buffer = RTCDataBuffer(data: data, isBinary: false)
            guard dataChannel.sendData(buffer) else {
                throw SubtitleError.translationFailed("Failed to send Auto Q&A response.create")
            }
        } catch {
            pendingCreateRequest = nil
            emit(.responseFailed(questionID: request.id, message: error.localizedDescription))
            emit(.status("Auto Q&A request failed: \(error.localizedDescription)"))
            tryDispatchNextIfPossible()
        }
    }

    private func sendSessionUpdateIfPossible() throws {
        guard let dataChannel, dataChannel.readyState == .open else { return }
        try sendClientEvent([
            "type": "session.update",
            "session": [
                "instructions": sessionInstructions
            ]
        ])
    }

    private func sendClientEvent(_ payload: [String: Any]) throws {
        guard let dataChannel else {
            throw SubtitleError.translationSocketDisconnected
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        guard dataChannel.sendData(buffer) else {
            throw SubtitleError.translationFailed("Failed to send Q&A realtime client event")
        }
    }

    private func emit(_ event: QAEvent) {
        continuation?.yield(event)
    }

    private static func normalizeToken(_ token: String?) -> String? {
        guard let token else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func enqueueLimited<T>(_ item: T, into queue: inout [T], max: Int) -> T? {
        guard max > 0 else { return item }
        var dropped: T?
        if queue.count >= max {
            dropped = queue.removeFirst()
        }
        queue.append(item)
        return dropped
    }
}

actor NoOpRealtimeQuestionAnswerService: RealtimeQuestionAnswerServicing {
    func startSession(apiToken _: String) async throws -> AsyncThrowingStream<QAEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stopSession() async {}
    func submit(questionID _: String, question _: String) async {}
    func cancelActiveResponse() async {}
    func setAPIToken(_ token: String) async {}
    func setAnswerEnglishLevel(_ level: QAEnglishLevel) async {}
}

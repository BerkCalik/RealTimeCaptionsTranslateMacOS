import Foundation

struct RealtimeTranslationResponseTracker {
    struct StateUpdateResult {
        let shouldDispatchNext: Bool
        let createdResponseID: String?
    }

    private(set) var activeResponseID: String?
    private(set) var activeRequest: RealtimeWebRTCService.TranslationRequest?
    private(set) var activeCancelRequested = false
    private(set) var pendingCreateRequest: RealtimeWebRTCService.TranslationRequest?

    private var droppedResponseIDs: Set<String> = []
    private var finalizedResponseIDs: Set<String> = []

    var hasActiveResponse: Bool {
        activeResponseID != nil
    }

    var hasPendingCreateRequest: Bool {
        pendingCreateRequest != nil
    }

    var activeRequestMode: RealtimeWebRTCService.TranslationRequestMode? {
        activeRequest?.mode
    }

    mutating func reset() {
        activeResponseID = nil
        activeRequest = nil
        activeCancelRequested = false
        pendingCreateRequest = nil
        droppedResponseIDs.removeAll()
        finalizedResponseIDs.removeAll()
    }

    mutating func setPendingCreateRequest(_ request: RealtimeWebRTCService.TranslationRequest) {
        pendingCreateRequest = request
    }

    mutating func clearPendingCreateRequest() {
        pendingCreateRequest = nil
    }

    mutating func prepareCancelIfPossible() -> String? {
        guard activeCancelRequested == false else { return nil }
        guard let responseID = activeResponseID else { return nil }

        if activeRequest?.mode == .live {
            droppedResponseIDs.insert(responseID)
        }
        return responseID
    }

    mutating func markCancelSent() {
        activeCancelRequested = true
    }

    mutating func shouldEmitTurkishDelta(responseID: String) -> Bool {
        droppedResponseIDs.contains(responseID) == false
    }

    mutating func shouldEmitTurkishFinal(responseID: String) -> Bool {
        if droppedResponseIDs.contains(responseID) {
            droppedResponseIDs.remove(responseID)
            return false
        }

        if finalizedResponseIDs.contains(responseID) {
            return false
        }
        finalizedResponseIDs.insert(responseID)
        return true
    }

    mutating func applyServerLifecycleUpdate(json: [String: Any]) -> StateUpdateResult {
        guard let type = json["type"] as? String else {
            return StateUpdateResult(shouldDispatchNext: false, createdResponseID: nil)
        }

        if type == "response.created",
           let responseID = RealtimeServerEventParser.responseID(from: json),
           responseID.isEmpty == false {
            activeResponseID = responseID
            activeRequest = pendingCreateRequest
            activeCancelRequested = false
            finalizedResponseIDs.remove(responseID)
            pendingCreateRequest = nil
            return StateUpdateResult(shouldDispatchNext: false, createdResponseID: responseID)
        }

        if type == "response.done" || type == "response.cancelled" || type == "response.failed" {
            let responseID = RealtimeServerEventParser.responseID(from: json)
            if responseID == activeResponseID {
                activeResponseID = nil
                activeRequest = nil
                activeCancelRequested = false
            }

            if type == "response.cancelled" || type == "response.failed" {
                if let responseID {
                    droppedResponseIDs.remove(responseID)
                    finalizedResponseIDs.insert(responseID)
                }
            }

            return StateUpdateResult(shouldDispatchNext: true, createdResponseID: nil)
        }

        if type == "error",
           let message = RealtimeServerEventParser.realtimeErrorMessage(from: json),
           RealtimeServerEventParser.isIgnorableCancellationErrorMessage(message) {
            activeResponseID = nil
            activeRequest = nil
            activeCancelRequested = false
            pendingCreateRequest = nil
            return StateUpdateResult(shouldDispatchNext: true, createdResponseID: nil)
        }

        return StateUpdateResult(shouldDispatchNext: false, createdResponseID: nil)
    }

    mutating func applyServerLifecycleUpdate(from data: Data) throws -> StateUpdateResult {
        applyServerLifecycleUpdate(json: try RealtimeServerEventParser.parseJSONObject(data: data))
    }
}

import Foundation

enum SubtitleError: LocalizedError {
    case permissionsDenied
    case missingPrivacyUsageDescriptions
    case invalidDevice
    case noInputDevices
    case audioSetupFailed(String)
    case speechRecognizerUnavailable
    case onDeviceRecognitionUnavailable
    case translationAPIKeyMissing
    case translationModelMissing
    case translationSocketDisconnected
    case translationProtocolError(String)
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionsDenied:
            return "Speech or microphone permission was denied."
        case .missingPrivacyUsageDescriptions:
            return "Missing NSMicrophoneUsageDescription or NSSpeechRecognitionUsageDescription in app metadata."
        case .invalidDevice:
            return "Selected audio input device is invalid."
        case .noInputDevices:
            return "No audio input devices were found."
        case .audioSetupFailed(let message):
            return message
        case .speechRecognizerUnavailable:
            return "Speech recognizer is unavailable for en-US."
        case .onDeviceRecognitionUnavailable:
            return "On-device speech recognition is not available on this Mac."
        case .translationAPIKeyMissing:
            return "Translation API token is missing. Enter a valid token in settings."
        case .translationModelMissing:
            return "Translation model not found."
        case .translationSocketDisconnected:
            return "Realtime connection disconnected."
        case .translationProtocolError(let message):
            return "Realtime protocol error: \(message)"
        case .translationFailed(let reason):
            return "Translation failed: \(reason)"
        }
    }
}

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

enum AudioSetupState: Equatable {
    case ready
    case blackHoleMissing
    case blackHoleAvailableNotSelected
    case blackHoleSelected
}

struct SetupGuideAction: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let isCompleted: Bool
}

enum AudioSetupDetector {
    static func isBlackHoleName(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("blackhole")
    }

    static func blackHoleCandidates(in devices: [AudioInputDevice]) -> [AudioInputDevice] {
        devices.filter { isBlackHoleName($0.name) }
    }
}

struct SubtitlePayload: Equatable {
    let line1: String
    let line2: String?

    static let empty = SubtitlePayload(line1: "", line2: nil)

    var isEmpty: Bool {
        line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (line2?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

struct SpeechRecognitionEvent: Equatable {
    let text: String
    let isFinal: Bool
}

struct TranslationStreamChunk: Equatable {
    let text: String
    let isFinal: Bool
}

enum RealtimeCaptionEvent: Equatable {
    case englishDelta(itemID: String, text: String)
    case englishFinal(itemID: String, text: String)
    case turkishDelta(responseID: String, text: String)
    case turkishFinal(responseID: String)
    case speechStarted
    case speechStopped
    case status(String)
}

enum SubtitleState: Equatable {
    case idle
    case listening
    case error(String)
}

enum QAEntryStatus: Equatable {
    case queued
    case answering
    case done
    case failed
    case stopped

    var title: String {
        switch self {
        case .queued:
            return "Queued"
        case .answering:
            return "Answering"
        case .done:
            return "Done"
        case .failed:
            return "Failed"
        case .stopped:
            return "Stopped"
        }
    }
}

struct QAEntry: Identifiable, Equatable {
    let id: String
    let sourceItemID: String
    let question: String
    var answer: String
    var status: QAEntryStatus
    let createdAt: Date
    var errorMessage: String?
}

enum QAServiceState: Equatable {
    case idle
    case connecting
    case ready
    case error
}

enum QAEnglishLevel: String, CaseIterable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"

    var id: String { rawValue }

    var title: String { rawValue }
}

enum QAEvent: Equatable {
    case serviceState(QAServiceState)
    case status(String)
    case responseStarted(questionID: String)
    case answerDelta(questionID: String, text: String)
    case answerCompleted(questionID: String)
    case responseFailed(questionID: String, message: String)
}

enum TranslationLatencyPreset: String, CaseIterable, Identifiable {
    case stable
    case balanced
    case ultraFast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return "Stable"
        case .balanced:
            return "Balanced"
        case .ultraFast:
            return "Ultra Fast"
        }
    }
}

enum TranslationModelOption: String, CaseIterable, Identifiable {
    case realtimeMini = "gpt-realtime-mini"
    case realtime = "gpt-realtime"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .realtimeMini:
            return "Realtime Mini"
        case .realtime:
            return "Realtime"
        }
    }
}

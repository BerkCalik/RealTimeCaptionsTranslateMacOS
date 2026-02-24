import AVFoundation
import Foundation

enum SubtitleViewModelSessionPreparation {
    static func hasRequiredPrivacyKeys() -> Bool {
        let microphone = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        return microphone?.isEmpty == false
    }

    static func ensureMicrophonePermission(
        using provider: @Sendable () async -> Bool
    ) async throws {
        guard await provider() else {
            if hasRequiredPrivacyKeys() == false {
                throw SubtitleError.missingPrivacyUsageDescriptions
            }
            throw SubtitleError.permissionsDenied
        }
    }

    static func configureRealtimeService(
        _ realtimeService: RealtimeSpeechTranslationServicing,
        apiToken: String,
        keepTechWordsOriginal: Bool,
        latencyPreset: TranslationLatencyPreset,
        model: TranslationModelOption
    ) async throws {
        await realtimeService.setAPIToken(apiToken)
        await realtimeService.setKeepTechWordsOriginal(keepTechWordsOriginal)
        await realtimeService.setLatencyPreset(latencyPreset)
        try await realtimeService.validateModelAccess(model: model)
    }
}

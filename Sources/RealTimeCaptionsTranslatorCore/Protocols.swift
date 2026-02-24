import AVFoundation
import Foundation

protocol AudioCaptureServicing {
    func availableInputDevices() async throws -> [AudioInputDevice]
    func startCapture(deviceID: String) throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error>
    func stopCapture() async
}

protocol SpeechRecognitionServicing {
    func requestPermissions() async -> Bool
    func startRecognition(buffers: AsyncThrowingStream<AVAudioPCMBuffer, Error>) throws -> AsyncThrowingStream<SpeechRecognitionEvent, Error>
    func stopRecognition() async
}

protocol SubtitleFormatting {
    func format(_ raw: String) -> SubtitlePayload
    func formatLines(_ raw: String) -> [String]
}

protocol TranslationServicing {
    func prepareModel() async throws
    func streamTranslate(text: String, isFinal: Bool) async throws -> AsyncThrowingStream<TranslationStreamChunk, Error>
    func cancelActiveStream() async
    func setModel(_ model: TranslationModelOption) async
    func currentModel() async -> TranslationModelOption
    func validateModelAccess() async throws
}

protocol RealtimeSpeechTranslationServicing {
    func startSession(deviceID: String, model: TranslationModelOption) async throws -> AsyncThrowingStream<RealtimeCaptionEvent, Error>
    func stopSession() async
    func validateModelAccess(model: TranslationModelOption) async throws
    func setKeepTechWordsOriginal(_ enabled: Bool) async
    func setLatencyPreset(_ preset: TranslationLatencyPreset) async
    func setAPIToken(_ token: String) async
}

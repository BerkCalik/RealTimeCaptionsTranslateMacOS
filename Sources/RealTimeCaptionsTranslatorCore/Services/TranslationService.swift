import Foundation

// Legacy service kept only for compatibility. Main runtime path uses RealtimeWebRTCService.
actor TranslationService: TranslationServicing {
    private var model: TranslationModelOption = .realtimeMini

    init(apiKey _: String? = nil, defaultModel: TranslationModelOption = .realtimeMini, session _: URLSession = .shared) {
        model = defaultModel
    }

    func prepareModel() async throws {
        throw SubtitleError.translationFailed("Legacy text translation service is disabled.")
    }

    func streamTranslate(text _: String, isFinal _: Bool) async throws -> AsyncThrowingStream<TranslationStreamChunk, Error> {
        throw SubtitleError.translationFailed("Legacy text translation service is disabled.")
    }

    func cancelActiveStream() async {}

    func setModel(_ model: TranslationModelOption) async {
        self.model = model
    }

    func currentModel() async -> TranslationModelOption {
        model
    }

    func validateModelAccess() async throws {
        throw SubtitleError.translationFailed("Legacy text translation service is disabled.")
    }
}

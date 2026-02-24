@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

final class SpeechRecognitionService: SpeechRecognitionServicing {
    private let recognizer: SFSpeechRecognizer?
    private let stateQueue = DispatchQueue(label: "SpeechRecognitionService.state")

    private var recognitionTask: SFSpeechRecognitionTask?
    private var bufferFeedTask: Task<Void, Never>?
    private var activeRequest: SFSpeechAudioBufferRecognitionRequest?
    private var transcriptContinuation: AsyncThrowingStream<SpeechRecognitionEvent, Error>.Continuation?

    init(localeIdentifier: String = "en-US") {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    func requestPermissions() async -> Bool {
        guard hasRequiredPrivacyKeys() else {
            return false
        }

        let speechAuthorized = await requestSpeechAuthorization()
        let microphoneAuthorized = await requestMicrophoneAuthorization()
        return speechAuthorized && microphoneAuthorized
    }

    func startRecognition(
        buffers: AsyncThrowingStream<AVAudioPCMBuffer, Error>
    ) throws -> AsyncThrowingStream<SpeechRecognitionEvent, Error> {
        guard let recognizer else {
            throw SubtitleError.speechRecognizerUnavailable
        }

        guard recognizer.isAvailable else {
            throw SubtitleError.speechRecognizerUnavailable
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw SubtitleError.onDeviceRecognitionUnavailable
        }

        stopRecognitionSync()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        stateQueue.sync {
            activeRequest = request
        }

        return AsyncThrowingStream { continuation in
            self.stateQueue.sync {
                self.transcriptContinuation = continuation
            }

            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let transcript = result?.bestTranscription.formattedString,
                   transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    continuation.yield(
                        SpeechRecognitionEvent(
                            text: transcript,
                            isFinal: result?.isFinal ?? false
                        )
                    )
                }

                if let error {
                    self?.finishTranscripts(throwing: error)
                }
            }

            self.stateQueue.sync {
                self.recognitionTask = task
            }

            let feedTask = Task(priority: .userInitiated) {
                do {
                    for try await buffer in buffers {
                        if Task.isCancelled {
                            break
                        }
                        request.append(buffer)
                    }
                    request.endAudio()
                } catch {
                    self.finishTranscripts(throwing: error)
                }
            }

            self.stateQueue.sync {
                self.bufferFeedTask = feedTask
            }
        }
    }

    func stopRecognition() async {
        stopRecognitionSync()
    }

    private func stopRecognitionSync() {
        var taskToCancel: SFSpeechRecognitionTask?
        var requestToEnd: SFSpeechAudioBufferRecognitionRequest?
        var feedTaskToCancel: Task<Void, Never>?
        var continuationToFinish: AsyncThrowingStream<SpeechRecognitionEvent, Error>.Continuation?

        stateQueue.sync {
            taskToCancel = recognitionTask
            requestToEnd = activeRequest
            feedTaskToCancel = bufferFeedTask
            continuationToFinish = transcriptContinuation

            recognitionTask = nil
            activeRequest = nil
            bufferFeedTask = nil
            transcriptContinuation = nil
        }

        feedTaskToCancel?.cancel()
        requestToEnd?.endAudio()
        taskToCancel?.cancel()
        continuationToFinish?.finish()
    }

    private func finishTranscripts(throwing error: Error) {
        var taskToCancel: SFSpeechRecognitionTask?
        var requestToEnd: SFSpeechAudioBufferRecognitionRequest?
        var feedTaskToCancel: Task<Void, Never>?
        var continuationToFinish: AsyncThrowingStream<SpeechRecognitionEvent, Error>.Continuation?

        stateQueue.sync {
            taskToCancel = recognitionTask
            requestToEnd = activeRequest
            feedTaskToCancel = bufferFeedTask
            continuationToFinish = transcriptContinuation

            recognitionTask = nil
            activeRequest = nil
            bufferFeedTask = nil
            transcriptContinuation = nil
        }

        feedTaskToCancel?.cancel()
        requestToEnd?.endAudio()
        taskToCancel?.cancel()
        continuationToFinish?.finish(throwing: error)
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func hasRequiredPrivacyKeys() -> Bool {
        let microphone = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        let speech = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String

        return (microphone?.isEmpty == false) && (speech?.isEmpty == false)
    }
}

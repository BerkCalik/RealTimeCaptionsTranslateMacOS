import AVFoundation
import CoreAudio
import Foundation

final class AudioCaptureService: AudioCaptureServicing {
    private let stateQueue = DispatchQueue(label: "AudioCaptureService.state")

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation?
    private var inputNode: AVAudioInputNode?
    private var previousDefaultInputDeviceID: AudioDeviceID?

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    func availableInputDevices() async throws -> [AudioInputDevice] {
        try CoreAudioDeviceManager.inputDevices()
    }

    func startCapture(deviceID: String) throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        guard let numericID = UInt32(deviceID) else {
            throw SubtitleError.invalidDevice
        }

        stopCaptureSync()

        let selectedDeviceID = AudioDeviceID(numericID)
        let previousDefaultDevice = try CoreAudioDeviceManager.defaultInputDeviceID()
        if previousDefaultDevice != selectedDeviceID {
            try CoreAudioDeviceManager.setDefaultInputDevice(selectedDeviceID)
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw SubtitleError.audioSetupFailed("Unable to create audio converter.")
        }

        stateQueue.sync {
            self.engine = engine
            self.converter = converter
            self.inputNode = inputNode
            self.previousDefaultInputDeviceID = previousDefaultDevice
        }

        return AsyncThrowingStream { continuation in
            self.stateQueue.sync {
                self.continuation = continuation
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.processIncomingBuffer(buffer)
            }

            do {
                try engine.start()
            } catch {
                inputNode.removeTap(onBus: 0)
                self.finishStream(throwing: error)
            }
        }
    }

    func stopCapture() async {
        stopCaptureSync()
    }

    private func processIncomingBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        do {
            guard let convertedBuffer = try convertToTargetFormat(inputBuffer) else {
                return
            }

            _ = stateQueue.sync {
                continuation?.yield(convertedBuffer)
            }
        } catch {
            finishStream(throwing: error)
        }
    }

    private func convertToTargetFormat(_ inputBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        try stateQueue.sync {
            guard let converter else {
                throw SubtitleError.audioSetupFailed("Audio converter is unavailable.")
            }

            let frameRatio = targetFormat.sampleRate / inputBuffer.format.sampleRate
            let estimatedFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * frameRatio) + 1

            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: max(estimatedFrameCapacity, 1)
            ) else {
                throw SubtitleError.audioSetupFailed("Unable to allocate output audio buffer.")
            }

            var conversionError: NSError?
            var didConsumeInput = false

            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if didConsumeInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didConsumeInput = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            switch status {
            case .haveData, .inputRanDry, .endOfStream:
                return outputBuffer.frameLength > 0 ? outputBuffer : nil
            case .error:
                throw conversionError ?? SubtitleError.audioSetupFailed("Audio conversion failed.")
            @unknown default:
                throw SubtitleError.audioSetupFailed("Unsupported audio conversion status.")
            }
        }
    }

    private func stopCaptureSync() {
        var engineToStop: AVAudioEngine?
        var inputNodeToDetach: AVAudioInputNode?
        var continuationToFinish: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation?
        var previousDeviceID: AudioDeviceID?

        stateQueue.sync {
            engineToStop = engine
            inputNodeToDetach = inputNode
            continuationToFinish = continuation
            previousDeviceID = previousDefaultInputDeviceID

            engine = nil
            converter = nil
            continuation = nil
            inputNode = nil
            previousDefaultInputDeviceID = nil
        }

        inputNodeToDetach?.removeTap(onBus: 0)
        engineToStop?.stop()
        continuationToFinish?.finish()

        if let previousDeviceID {
            try? CoreAudioDeviceManager.setDefaultInputDevice(previousDeviceID)
        }
    }

    private func finishStream(throwing error: Error) {
        var engineToStop: AVAudioEngine?
        var inputNodeToDetach: AVAudioInputNode?
        var continuationToFinish: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation?
        var previousDeviceID: AudioDeviceID?

        stateQueue.sync {
            engineToStop = engine
            inputNodeToDetach = inputNode
            continuationToFinish = continuation
            previousDeviceID = previousDefaultInputDeviceID

            engine = nil
            converter = nil
            continuation = nil
            inputNode = nil
            previousDefaultInputDeviceID = nil
        }

        inputNodeToDetach?.removeTap(onBus: 0)
        engineToStop?.stop()
        continuationToFinish?.finish(throwing: error)

        if let previousDeviceID {
            try? CoreAudioDeviceManager.setDefaultInputDevice(previousDeviceID)
        }
    }
}

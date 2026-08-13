// SpeechCapture.swift
// Thin wrapper around SFSpeechRecognizer + AVAudioEngine for dictating a
// chore or shopping item.
//
// Recognition is forced on-device (`requiresOnDeviceRecognition`) when the
// recognizer supports it, so utterances aren't sent to Apple's servers.
// Permission prompts (microphone + speech recognition) are requested on
// first use; the usage strings live in Info.plist.

import Foundation
import AVFoundation
import Speech

@MainActor
final class SpeechCapture: ObservableObject {

    /// Live transcript, updated as you speak.
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    /// Set when we can't record — permissions denied, recognizer unavailable.
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// True when the device can transcribe at all.
    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    // MARK: - Permissions

    /// Requests speech + microphone access. Returns true when both granted.
    func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechOK else {
            errorMessage = "Speech recognition access is off. Enable it in Settings › Privacy › Speech Recognition."
            return false
        }

        let micOK = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micOK else {
            errorMessage = "Microphone access is off. Enable it in Settings › Privacy › Microphone."
            return false
        }
        return true
    }

    // MARK: - Recording

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""

        guard await requestPermissions() else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available on this device right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Keep audio on the device when the recognizer allows it.
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Clears state so the sheet can be reused.
    func reset() {
        stop()
        transcript = ""
        errorMessage = nil
    }
}

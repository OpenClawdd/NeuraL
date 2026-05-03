//
//  SpeechManager.swift
//  NeuraL
//
//  Phase 6.4 — Speech Input & Output Manager
//
//  Provides speech-to-text (via SFSpeechRecognizer) and text-to-speech
//  (via AVSpeechSynthesizer) capabilities for hands-free interaction
//  with NeuraL.
//
//  Architecture:
//  - SpeechRecognizer: Wraps SFSpeechRecognizer for voice input
//  - SpeechSynthesizer: Wraps AVSpeechSynthesizer for reading responses
//  - SpeechManager: @Observable class that coordinates both and is
//    consumed by the SwiftUI views
//
//  Privacy:
//  - Speech recognition uses Apple's on-device recognizer when available
//    (iOS 16+), falling back to the server recognizer with user permission
//  - All audio is processed locally when on-device recognition is available
//  - The user must grant microphone and speech recognition permissions
//

import Foundation
import SwiftUI
import Speech
import AVFoundation

// MARK: - Speech Recognition State

enum SpeechRecognitionState: Sendable, CustomStringConvertible {
    case idle
    case requestingAuthorization
    case authorized
    case denied
    case listening(partialResult: String)
    case processing
    case completed(finalText: String)
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .requestingAuthorization: return "Requesting Authorization..."
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .listening(let partial): return "Listening: \(partial.prefix(30))..."
        case .processing: return "Processing..."
        case .completed(let text): return "Completed: \(text.prefix(30))..."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }

    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}

// MARK: - Speech Recognizer

/// Wraps SFSpeechRecognizer for on-device speech-to-text.
actor SpeechRecognizer {

    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var audioEngine: AVAudioEngine?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)

    private var state: SpeechRecognitionState = .idle

    /// Request authorization for speech recognition.
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Check if on-device speech recognition is available.
    var supportsOnDeviceRecognition: Bool {
        if #available(iOS 16.0, *) {
            return speechRecognizer?.supportsOnDeviceRecognition ?? false
        }
        return false
    }

    /// Start listening for speech input.
    func startListening() -> AsyncStream<SpeechRecognitionState> {
        AsyncStream { continuation in
            Task {
                // Check authorization
                let authStatus = await requestAuthorization()
                guard authStatus == .authorized else {
                    continuation.yield(.denied)
                    continuation.finish()
                    return
                }

                // Set up audio engine
                let audioEngine = AVAudioEngine()
                self.audioEngine = audioEngine

                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)

                // Create recognition request
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                if #available(iOS 16.0, *) {
                    request.requiresOnDeviceRecognition = true
                }
                self.recognitionRequest = request

                // Install audio tap
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    request.append(buffer)
                }

                // Prepare and start audio engine
                audioEngine.prepare()
                do {
                    try audioEngine.start()
                } catch {
                    continuation.yield(.error("Audio engine failed to start: \(error.localizedDescription)"))
                    continuation.finish()
                    return
                }

                continuation.yield(.listening(partialResult: ""))

                // Start recognition task
                guard let speechRecognizer = self.speechRecognizer else {
                    continuation.yield(.error("Speech recognizer not available for current locale"))
                    continuation.finish()
                    return
                }

                self.recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        continuation.yield(.error(error.localizedDescription))
                        continuation.finish()
                        return
                    }

                    if let result = result {
                        let transcribed = result.bestTranscription.formattedString
                        if result.isFinal {
                            continuation.yield(.completed(finalText: transcribed))
                            continuation.finish()
                        } else {
                            continuation.yield(.listening(partialResult: transcribed))
                        }
                    }
                }
            }
        }
    }

    /// Stop listening.
    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        state = .idle
    }

    deinit {
        stopListening()
    }
}

// MARK: - Speech Synthesizer

/// Wraps AVSpeechSynthesizer for text-to-speech output.
@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Whether auto-read is enabled (automatically read assistant responses).
    @Published var autoReadResponses: Bool = false

    /// The current speaking state.
    @Published var speakingState: SpeakingState = .idle

    enum SpeakingState: Sendable {
        case idle
        case speaking(progress: Float)
        case paused
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak the given text aloud.
    func speak(_ text: String, language: String? = nil) {
        guard !synthesizer.isSpeaking else { stop() }

        // Strip markdown formatting for cleaner speech
        let cleanText = stripMarkdown(text)

        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        if let language = language {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        } else {
            // Auto-detect language from text
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        speakingState = .speaking(progress: 0)
        synthesizer.speak(utterance)
    }

    /// Pause speaking.
    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
        speakingState = .paused
    }

    /// Resume speaking.
    func resume() {
        synthesizer.continueSpeaking()
    }

    /// Stop speaking entirely.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingState = .idle
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            speakingState = .idle
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            speakingState = .idle
        }
    }

    // MARK: - Markdown Stripping

    /// Strip markdown formatting for cleaner speech output.
    private func stripMarkdown(_ text: String) -> String {
        var result = text

        // Remove code blocks
        result = result.replacingOccurrences(of: "```[\\s\\S]*?```", with: ". Code omitted. ", options: .regularExpression)

        // Remove inline code
        result = result.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)

        // Remove bold/italic markers
        result = result.replacingOccurrences(of: "\\*{1,3}([^*]+)\\*{1,3}", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "_{1,3}([^_]+)_{1,3}", with: "$1", options: .regularExpression)

        // Remove headers
        result = result.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)

        // Remove links (keep text)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)

        // Remove list markers
        result = result.replacingOccurrences(of: "^\\s*[-*+]\\s+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "^\\s*\\d+\\.\\s+", with: "", options: .regularExpression)

        // Clean up extra whitespace
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Speech Manager

/// @Observable coordinator for speech input and output.
/// This is the main class consumed by SwiftUI views.
@Observable
@MainActor
final class SpeechManager {

    var recognitionState: SpeechRecognitionState = .idle
    var isAutoReadEnabled: Bool = false
    var isSpeaking: Bool = false

    private let recognizer = SpeechRecognizer()
    private let synthesizer = SpeechSynthesizer()
    private var listeningTask: Task<Void, Never>?

    /// Start listening for voice input.
    func startListening() {
        guard !recognitionState.isListening else { return }

        listeningTask = Task { [weak self] in
            guard let self = self else { return }

            let stream = await self.recognizer.startListening()
            for await state in stream {
                if Task.isCancelled { break }
                self.recognitionState = state

                if case .completed(let text) = state {
                    // The completed text will be picked up by ChatView
                    break
                }
            }
        }
    }

    /// Stop listening for voice input.
    func stopListening() {
        listeningTask?.cancel()
        listeningTask = nil
        Task {
            await recognizer.stopListening()
        }
        recognitionState = .idle
    }

    /// Get the recognized text if recognition is complete.
    var recognizedText: String? {
        if case .completed(let text) = recognitionState {
            return text
        }
        return nil
    }

    /// Consume the recognized text (resets state to idle).
    func consumeRecognizedText() -> String? {
        guard case .completed(let text) = recognitionState else { return nil }
        recognitionState = .idle
        return text
    }

    /// Speak text aloud.
    func speak(_ text: String) {
        isSpeaking = true
        synthesizer.speak(text)
        // Monitor speaking state
        Task {
            while synthesizer.isSpeaking {
                try? await Task.sleep(for: .milliseconds(200))
            }
            isSpeaking = false
        }
    }

    /// Stop speaking.
    func stopSpeaking() {
        synthesizer.stop()
        isSpeaking = false
    }

    /// Toggle auto-read mode.
    func toggleAutoRead() {
        isAutoReadEnabled.toggle()
        synthesizer.autoReadResponses = isAutoReadEnabled
    }
}

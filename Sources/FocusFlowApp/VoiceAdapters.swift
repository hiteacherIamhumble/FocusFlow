import AVFoundation
import Speech

@MainActor
final class SpeechSynthesisService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    struct VoiceOption: Identifiable, Hashable {
        let id: String
        let displayName: String
    }

    static func availableEnglishVoices() -> [VoiceOption] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                if $0.language == $1.language {
                    return $0.name < $1.name
                }
                return $0.language < $1.language
            }
            .prefix(8)
        return [VoiceOption(id: "", displayName: "System gentle voice")]
            + voices.map { VoiceOption(id: $0.identifier, displayName: "\($0.name) · \($0.language)") }
    }

    func speak(_ text: String, enabled: Bool, voiceIdentifier: String?) {
        guard enabled else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 0.98
        utterance.volume = 0.85
        if let voiceIdentifier, !voiceIdentifier.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) ?? AVSpeechSynthesisVoice(language: "en-US")
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

@MainActor
final class SpeechRecognitionService: NSObject {
    enum SpeechRecognitionError: Error, LocalizedError {
        case unavailable
        case denied
        case audioInputUnavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Speech recognition is not available right now."
            case .denied:
                return "Speech recognition permission is not enabled."
            case .audioInputUnavailable:
                return "No microphone input is available."
            }
        }
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    static func isAvailable(locale: Locale = Locale(identifier: "en-US")) -> Bool {
        SFSpeechRecognizer(locale: locale)?.isAvailable == true
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func start(onTranscript: @escaping @MainActor (String, Bool) -> Void) async throws {
        guard await requestAuthorization() else {
            throw SpeechRecognitionError.denied
        }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecognitionError.unavailable
        }

        stop()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw SpeechRecognitionError.audioInputUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in
                    onTranscript(transcript, result.isFinal)
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stop()
                }
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }
}

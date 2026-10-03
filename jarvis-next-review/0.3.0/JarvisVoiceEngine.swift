import Foundation
import AVFoundation

protocol JarvisVoiceProvider: AnyObject {
    func speak(_ text: String, completion: @escaping () -> Void)
    func stop()
    var isSpeaking: Bool { get }
}

class AppleVoiceProvider: NSObject, JarvisVoiceProvider {
    private let synthesizer = AVSpeechSynthesizer()
    var isSpeaking: Bool { synthesizer.isSpeaking }
    
    func speak(_ text: String, completion: @escaping () -> Void) {
        let utterance = AVSpeechUtterance(string: text)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let bestVoice = voices.first { $0.language == "de-DE" && $0.quality == .enhanced } 
                       ?? AVSpeechSynthesisVoice(language: "de-DE")
        
        utterance.voice = bestVoice
        utterance.rate = 0.44
        utterance.pitchMultiplier = 0.82
        
        // Persistenter Delegate, um Completion zu garantieren
        let delegate = VoiceDelegate(completion: completion)
        // In nativem macOS ist AVSpeechSynthesizerDelegate ein Protocol
        // Wir nutzen einen Wrapper, da der Synthesizer nur einen Delegate hat
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
        
        // Damit der Delegate nicht sofort deallokiert wird, müssen wir ihn halten
        // In dieser Architektur wird er pro Segment kurzzeitig referenziert.
        // Für produktive Zwecke wird der Delegate in einer Liste verwaltet.
        self.currentDelegate = delegate
    }
    
    private var currentDelegate: VoiceDelegate?
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

class VoiceDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let completion: () -> Void
    init(completion: @escaping () -> Void) { self.completion = completion }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion()
    }
}

class LocalNeuralVoiceProvider: JarvisVoiceProvider {
    var isSpeaking: Bool = false
    func speak(_ text: String, completion: @escaping () -> Void) {
        // Interface für lokale Engines wie Piper/Kokoro.
        // Da diese externe Binaries benötigen, meldet dieser Provider aktuell ehrlichen Status.
        print("Neural Voice Provider: Integration ausstehend.")
        completion()
    }
    func stop() { }
}

@MainActor
class JarvisVoiceEngine: ObservableObject {
    private var provider: JarvisVoiceProvider
    @Published var isSpeaking = false
    var onStateChange: ((JarvisSystemState) -> Void)?
    
    init() {
        self.provider = AppleVoiceProvider() // Fallback
    }
    
    func speak(_ text: String) {
        let segments = segmentText(text)
        processQueue(segments)
    }
    
    private func processQueue(_ segments: [String]) {
        guard !segments.isEmpty else {
            isSpeaking = false
            onStateChange?(.ready)
            return
        }
        
        let current = segments[0]
        let remaining = Array(segments.dropFirst())
        
        isSpeaking = true
        onStateChange?(.speaking)
        
        provider.speak(current) { [weak self] in
            DispatchQueue.main.async {
                self?.processQueue(remaining)
            }
        }
    }
    
    func interrupt() {
        provider.stop()
        isSpeaking = false
        onStateChange?(.ready)
    }
    
    private func segmentText(_ text: String) -> [String] {
        return text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) + "." }
    }
}

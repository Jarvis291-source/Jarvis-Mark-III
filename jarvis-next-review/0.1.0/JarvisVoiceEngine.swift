import Foundation
import AVFoundation

@MainActor
class JarvisVoiceEngine: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    var onStateChange: ((JarvisSystemState) -> Void)?
    
    init() {
        synthesizer.delegate = self
    }
    
    func speak(_ text: String) {
        // Text-Segmentierung für natürliche Prosodie
        let segments = segmentText(text)
        
        for segment in segments {
            let utterance = AVSpeechUtterance(string: segment)
            
            // Cineastische Konfiguration
            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            utterance.rate = 0.45 // Ruhig
            utterance.pitchMultiplier = 0.8 // Tief und souverän
            utterance.volume = 1.0
            
            synthesizer.speak(utterance)
        }
    }
    
    func interrupt() {
        synthesizer.stopSpeaking(at: .immediate)
        onStateChange?(.ready)
    }
    
    private func segmentText(_ text: String) -> [String] {
        return text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) + "." }
    }
}

extension JarvisVoiceEngine: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStateChange?(.speaking)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking {
            onStateChange?(.ready)
        }
    }
}

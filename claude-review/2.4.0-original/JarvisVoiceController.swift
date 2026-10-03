import SwiftUI
import AVFoundation

class JarvisVoiceController: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    
    // Interface zum HUD-State
    var onStateChange: ((JarvisSystemState) -> Void)?
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(_ text: String) {
        // Text-Segmentierung für natürliche Prosodie
        let segments = segmentText(text)
        
        for segment in segments {
            let utterance = AVSpeechUtterance(string: segment)
            
            // KONFIGURATION: Cineastische KI-Stimme (Deutsch)
            // Wir suchen nach einer tiefen, ruhigen Stimme. 
            // Falls 'Yannick' oder 'Tessa' nicht verfügbar sind, wird die Standard-Deutsch-Stimme genutzt.
            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            
            utterance.rate = 0.48 // Ruhig, nicht hektisch
            utterance.pitchMultiplier = 0.85 // Tiefer, souveräner Klang
            utterance.volume = 1.0
            
            synthesizer.speak(utterance)
        }
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        onStateChange?(.ready)
    }
    
    private func segmentText(_ text: String) -> [String] {
        // Teilt den Text an Satzzeichen, um natürliche Pausen zu erzwingen
        return text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) + "." }
    }
}

extension JarvisVoiceController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.onStateChange?(.speaking)
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            // Prüfen, ob noch etwas in der Queue ist, sonst zurück auf ready
            if synthesizer.isSpeaking {
                // Weiterhin im speaking state
            } else {
                self.onStateChange?(.ready)
            }
        }
    }
}
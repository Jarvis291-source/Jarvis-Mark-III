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
        // Für produktive

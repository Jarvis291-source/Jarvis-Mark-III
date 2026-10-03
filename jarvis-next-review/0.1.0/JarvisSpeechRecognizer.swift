import Foundation
import Speech
import AVFoundation

@MainActor
class JarvisSpeechRecognizer: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    var onCommandRecognized: ((String) -> Void)?
    
    func startListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            let inputNode = audioEngine.inputNode
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }
            
            recognitionRequest.shouldReportPartialResults = true
            
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    let transcript = result.bestTranscription.formattedString
                    // Einfache Pausenerkennung: Wenn der Satz abgeschlossen scheint
                    if result.isFinal {
                        self.onCommandRecognized?(transcript)
                    }
                }
                
                if error != nil {
                    self.restartListening()
                }
            }
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
        } catch {
            print("Speech Recognition Error: \(error)")
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudioProcessing()
        recognitionTask?.cancel()
    }
    
    private func restartListening() {
        stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.startListening()
        }
    }
}

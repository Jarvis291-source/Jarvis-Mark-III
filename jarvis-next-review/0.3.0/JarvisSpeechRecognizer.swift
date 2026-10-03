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
        Task {
            let granted = await requestPermissions()
            if granted {
                performStart()
            } else {
                print("Berechtigungen für Speech/Mic wurden abgelehnt.")
            }
        }
    }
    
    private func requestPermissions() async -> Bool {
        let speechGranted = await SFSpeechRecognizer.requestAuthorization { status in }
        // Mikrofon-Berechtigung wird auf macOS beim ersten Zugriff auf inputNode implizit abgefragt,
        // aber wir stellen sicher, dass Speech-Auth da ist.
        return speechGranted == .authorized
    }
    
    private func performStart() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        
        do {
            let inputNode = audioEngine.inputNode
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }
            
            recognitionRequest.shouldReportPartialResults = true
            
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    let transcript = result.bestTranscription.formattedString
                    if transcript.lowercased().contains("jarvis") {
                        if result.isFinal {
                            let cleanCommand = transcript.lowercased()
                                .replacingOccurrences(of: "jarvis", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            self.onCommandRecognized?(cleanCommand)
                        }
                    }
                }
                if error != nil { self.restartListening() }
            }
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
        } catch {
            print("Speech Error: \(error)")
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio() // Korrigiert auf native API
        recognitionTask?.cancel()
    }
    
    private func restartListening() {
        stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.performStart()
        }
    }
}

// Helper for async authorization
extension SFSpeechRecognizer {
    static func requestAuthorization(completion: @escaping (AVAudioSession.RecordingOptions) -> Void) async -> AVAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

// Fixed return type for the helper
extension SFSpeechRecognizer {
    static func requestAuthorization() async -> AVAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

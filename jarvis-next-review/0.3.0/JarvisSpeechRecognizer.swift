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
        // Mikrofon-Berechtigung wird auf macOS beim ersten

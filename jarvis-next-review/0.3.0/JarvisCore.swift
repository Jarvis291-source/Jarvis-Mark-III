import SwiftUI
import Combine

@MainActor
class JarvisCore: ObservableObject {
    static let shared = JarvisCore()
    
    @Published var systemState: JarvisSystemState = .ready
    @Published var activeModule: JarvisModuleType? = nil
    @Published var lastResponse: String = ""
    @Published var memoryCount: Int = 0
    @Published var aiStatus: String = "Prüfe Verbindung..."
    
    let voiceEngine = JarvisVoiceEngine()
    let speechRecognizer = JarvisSpeechRecognizer()
    let aiProvider = JarvisAIProvider()
    let memoryManager = JarvisMemoryManager()
    let macController = JarvisMacController()
    let internetProvider = JarvisInternetProvider()
    let updater = JarvisUpdater()
    let router = JarvisRouter()
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupBindings()
        updateMemoryCount()
    }
    
    private func setupBindings() {
        voiceEngine.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.systemState = state
            }
        }
        
        speechRecognizer.onCommandRecognized = { [weak self] command in
            Task {
                await self?.processCommand(command)
            }
        }
    }
    
    func processCommand(_ command: String) {
        let lower = command.lowercased()
        
        // INTERRUPTION LOGIC: "Jarvis stopp" funktioniert immer
        if lower.contains("stopp") || lower.contains("stop") || lower.contains("ruhe") || lower.contains("abbrechen") {
            voiceEngine.interrupt()
            return
        }
        
        // Andere Befehle blockieren, wenn Jarvis gerade spricht
        if voiceEngine.isSpeaking { return }
        
        systemState = .thinking
        let action = router.route(command: command)
        
        Task {
            let response = await action.execute(command: command, core: self)
            self.lastResponse = response
            self.voiceEngine.speak(response)
        }
    }
    
    func updateMemoryCount() {
        self.memoryCount = memoryManager.getCount()
    }
    
    func setModule(_ module: JarvisModuleType?) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            self.activeModule = module
        }
    }
}

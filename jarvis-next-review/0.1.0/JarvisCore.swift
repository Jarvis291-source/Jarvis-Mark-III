import SwiftUI
import Combine

@MainActor
class JarvisCore: ObservableObject {
    static let shared = JarvisCore()
    
    @Published var systemState: JarvisSystemState = .ready
    @Published var activeModule: JarvisModuleType? = nil
    @Published var lastResponse: String = ""
    
    // Sub-Systeme
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
    }
    
    private func setupBindings() {
        // Voice Engine meldet Zustände an den Core
        voiceEngine.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.systemState = state
            }
        }
        
        // Speech Recognizer meldet Erkennungen
        speechRecognizer.onCommandRecognized = { [weak self] command in
            Task {
                await self?.processCommand(command)
            }
        }
    }
    
    func processCommand(_ command: String) {
        systemState = .thinking
        
        // Routing entscheidet, welches Modul zuständig ist
        let action = router.route(command: command)
        
        Task {
            let response = await action.execute(core: self)
            self.lastResponse = response
            self.voiceEngine.speak(response)
        }
    }
    
    func setModule(_ module: JarvisModuleType?) {
        withAnimation(.spring()) {
            self.activeModule = module
        }
    }
}

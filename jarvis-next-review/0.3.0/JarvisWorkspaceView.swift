import SwiftUI

struct JarvisWorkspaceView: View {
    let module: JarvisModuleType
    var onClose: () -> Void
    var core: JarvisCore
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            
            VStack {
                HStack {
                    Text("\(module.rawValue) INTERFACE").font(.system(size: 24, weight: .light, design: .monospaced)).foregroundColor(.cyan)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").foregroundColor(.white) }.buttonStyle(PlainButtonStyle())
                }
                .padding(30)
                
                Spacer()
                
                Group {
                    switch module {
                    case .mac: MacWorkspaceView()
                    case .ai: AIWorkspaceView(core: core)
                    case .internet: Text("INTERNET-SUCHE: NOCH NICHT VERFÜGBAR").foregroundColor(.white.opacity(0.5))
                    case .memory: MemoryWorkspaceView(core: core)
                    case .update: UpdateWorkspaceView(core: core)
                    default: Text("MODUL \(module.rawValue): NOCH NICHT VERFÜGBAR").foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: 800, maxHeight: 500)
                .padding()
                
                Spacer()
            }
            .padding(40)
        }
    }
}

struct MacWorkspaceView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("SYSTEM-STEUERUNG").font(.system(size: 18, design: .monospaced)).foregroundColor(.cyan)
            Divider().background(Color.cyan.opacity(0.3))
            Text("• Safari\n• Mail\n• Finder\n• Kalender\n• Notizen").foregroundColor(.white).font(.system(size: 14, design: .monospaced))
        }
    }
}

struct AIWorkspaceView: View {
    var core: JarvisCore
    var body: some View {
        VStack {
            Text("OLLAMA LOCAL ENGINE").foregroundColor(.cyan).font(.system(size: 18, design: .monospaced))
            Text("Status: \(core.aiProvider.getStatusSync())").foregroundColor(.white.opacity(0.6)).font(.system(size: 14, design: .monospaced))
        }
    }
}

struct MemoryWorkspaceView: View {
    var core: JarvisCore
    var body: some View {
        VStack {
            Text("LOCAL MEMORY").foregroundColor(.cyan).font(.system(size: 18, design: .monospaced))
            // Synchroner Zugriff über Core-Property verhindert Compilerfehler
            Text("Gespeicherte Einträge: \(core.memoryCount)").foregroundColor(.white.opacity(0.6))
        }
    }
}

struct UpdateWorkspaceView: View {
    var core: JarvisCore
    var body: some View {
        VStack {
            Text("SYSTEM UPDATE").foregroundColor(.cyan).font(.system(size: 18, design: .monospaced))
            Text("Status: NOCH NICHT VERFÜGBAR").foregroundColor(.white.opacity(0.5))
        }
    }
}

// Helper extension for AI Status
extension JarvisAIProvider {
    func getStatusSync() -> String {
        // Synchroner Wrapper für den UI-Thread
        let semaphore = DispatchSemaphore(value: 0)
        var result = "Prüfe..."
        Task {
            result = await self.getStatus()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
        return result
    }
}

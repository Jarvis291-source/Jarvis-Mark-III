import Foundation

enum JarvisAction {
    case ai
    case mac
    case internet
    case memoryStore
    case memoryRetrieve
    
    func execute(command: String, core: JarvisCore) async -> String {
        switch self {
        case .ai:
            return await core.aiProvider.generateResponse(for: command)
        case .mac:
            return await core.macController.handleCommand(command)
        case .internet:
            return await core.internetProvider.search(query: command)
        case .memoryStore:
            let info = command.replacingOccurrences(of: "merke dir", with: "").trimmingCharacters(in: .whitespaces)
            core.memoryManager.store(information: info)
            core.updateMemoryCount()
            return "Ich habe mir das gemerkt: \(info)"
        case .memoryRetrieve:
            return await core.memoryManager.retrieve(query: command)
        }
    }
}

class JarvisRouter {
    func route(command: String) -> JarvisAction {
        let lower = command.lowercased()
        
        if lower.contains("merke dir") || lower.contains("speichere") {
            return .memoryStore
        } else if lower.contains("öffne") || lower.contains("starte") || 
                  lower.contains("lautstärke") || lower.contains("screenshot") {
            return .mac
        } else if lower.contains("suche") || lower.contains("wetter") || 
                  lower.contains("internet") || lower.contains("web") {
            return .internet
        } else if lower.contains("erinnere") || lower.contains("gesagt") || 
                  lower.contains("gedächtnis") {
            return .memoryRetrieve
        } else {
            return .ai
        }
    }
}

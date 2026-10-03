import Foundation

enum JarvisAction {
    case ai
    case mac
    case internet
    case memory
    
    func execute(core: JarvisCore) async -> String {
        switch self {
        case .ai:
            return await core.aiProvider.generateResponse(for: core.lastResponse)
        case .mac:
            return await core.macController.handleCommand(core.lastResponse)
        case .internet:
            return await core.internetProvider.search(query: core.lastResponse)
        case .memory:
            return await core.memoryManager.retrieve(query: core.lastResponse)
        }
    }
}

class JarvisRouter {
    func route(command: String) -> JarvisAction {
        let lowerCommand = command.lowercased()
        
        if lowerCommand.contains("öffne") || lowerCommand.contains("starte") || lowerCommand.contains("lautstärke") {
            return .mac
        } else if lowerCommand.contains("suche") || lowerCommand.contains("wetter") || lowerCommand.contains("internet") {
            return .internet
        } else if lowerCommand.contains("erinnere") || lowerCommand.contains("gesagt") || lowerCommand.contains("gedächtnis") {
            return .memory
        } else {
            return .ai
        }
    }
}

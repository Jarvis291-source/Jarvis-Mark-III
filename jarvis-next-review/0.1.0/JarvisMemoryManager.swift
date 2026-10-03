import Foundation

class JarvisMemoryManager {
    private let storageKey = "jarvis_local_memory"
    
    func store(information: String) {
        // Speicherung in UserDefaults oder lokaler SQLite/JSON Datei
        var memory = getMemory()
        memory.append(["date": Date().description, "info": information])
        UserDefaults.standard.set(memory, forKey: storageKey)
    }
    
    func retrieve(query: String) async -> String {
        let memory = getMemory()
        // Einfache Keywordsuche als Basis, später semantische Suche (Vector DB)
        let matches = memory.filter { $0["info"]?.contains(query) ?? false }
        
        return matches.isEmpty ? "Ich kann mich an nichts Spezifisches zu diesem Thema erinnern." : "Ich habe Folgendes in meinem Gedächtnis gefunden: \(matches.first?["info"] ?? "")"
    }
    
    private func getMemory() -> [[String: String]] {
        UserDefaults.standard.array(forKey: storageKey) as? [[String: String]] ?? []
    }
}

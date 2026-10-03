import Foundation

class JarvisMemoryManager {
    private let storageKey = "jarvis_local_memory"
    
    func store(information: String) {
        var memory = getMemory()
        let entry = ["date": Date().description, "info": information]
        memory.append(entry)
        UserDefaults.standard.set(memory, forKey: storageKey)
    }
    
    func retrieve(query: String) async -> String {
        let memory = getMemory()
        let matches = memory.filter { $0["info"]?.lowercased().contains(query.lowercased()) ?? false }
        
        if matches.isEmpty {
            return "Ich habe keine Informationen dazu in meinem Gedächtnis."
        }
        return "Ich erinnere mich: \(matches.last?["info"] ?? "")"
    }
    
    func getCount() -> Int {
        return getMemory().count
    }
    
    private func getMemory() -> [[String: String]] {
        UserDefaults.standard.array(forKey: storageKey) as? [[String: String]] ?? []
    }
}

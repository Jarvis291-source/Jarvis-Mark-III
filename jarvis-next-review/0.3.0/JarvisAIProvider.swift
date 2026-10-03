import Foundation

class JarvisAIProvider {
    private let ollamaBaseURL = URL(string: "http://127.0.0.1:11434")!
    private var currentModel: String = ""
    
    func getStatus() async -> String {
        do {
            let (data, response) = try await URLSession.shared.data(from: ollamaBaseURL.appendingPathComponent("api/tags"))
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return "Offline"
            }
            
            let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            if let best = tags.models.first?.name {
                self.currentModel = best
                return "Verbunden (\(best))"
            }
            return "Kein Modell gefunden"
        } catch {
            return "Offline"
        }
    }
    
    func generateResponse(for prompt: String) async -> String {
        if currentModel.isEmpty {
            let status = await getStatus()
            if status == "Offline" || status == "Kein Modell gefunden" {
                return "Der Ollama-Server ist nicht erreichbar oder es ist kein Modell installiert."
            }
        }
        
        let requestURL = ollamaBaseURL.appendingPathComponent("api/generate")
        let requestBody: [String: Any] = [
            "model": currentModel,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.7]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return "Fehler bei der Datenaufbereitung."
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseText = json["response"] as? String {
                return responseText
            }
            return "Die KI konnte keine Antwort generieren."
        } catch {
            return "Kommunikationsfehler mit Ollama."
        }
    }
}

struct OllamaTagsResponse: Codable {
    struct Model: Codable { let name: String }
    let models: [Model]
}

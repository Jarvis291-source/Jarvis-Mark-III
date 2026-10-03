import Foundation
import AppKit

class JarvisMacController {
    func handleCommand(_ command: String) async -> String {
        let lower = command.lowercased()
        
        if lower.contains("safari") {
            openApp(bundleId: "com.apple.Safari")
            return "Ich öffne Safari für Sie."
        } else if lower.contains("mail") {
            openApp(bundleId: "com.apple.mail")
            return "Ihr Postfach wird geöffnet."
        } else if lower.contains("finder") {
            openApp(bundleId: "com.apple.finder")
            return "Finder ist nun aktiv."
        }
        
        return "Ich konnte den entsprechenden Systembefehl nicht zuordnen."
    }
    
    private func openApp(bundleId: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open(url)
        }
    }
}

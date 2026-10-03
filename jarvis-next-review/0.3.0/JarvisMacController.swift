import Foundation
import AppKit

class JarvisMacController {
    func handleCommand(_ command: String) async -> String {
        let lower = command.lowercased()
        
        if lower.contains("safari") { return openApp(bundleId: "com.apple.Safari") ? "Safari wird geöffnet." : "Fehler." }
        if lower.contains("mail") { return openApp(bundleId: "com.apple.mail") ? "Mail wird geöffnet." : "Fehler." }
        if lower.contains("finder") { return openApp(bundleId: "com.apple.finder") ? "Finder ist nun aktiv." : "Fehler." }
        if lower.contains("kalender") { return openApp(bundleId: "com.apple.Calendar") ? "Kalender wird geöffnet." : "Fehler." }
        if lower.contains("notizen") { return openApp(bundleId: "com.apple.Notes") ? "Notizen werden geöffnet." : "Fehler." }
        if lower.contains("rechner") { return openApp(bundleId: "com.apple.calculator") ? "Rechner wird geöffnet." : "Fehler." }
        if lower.contains("einstellungen") || lower.contains("system") { return openSystemSettings() ? "Systemeinstellungen öffnen." : "Fehler." }
        if lower.contains("screenshot") { return takeScreenshot() ? "Screenshot wird erstellt." : "Fehler." }
        if lower.contains("lautstärke") { return adjustVolume(lower) }
        
        return "Dieser Systembefehl ist mir nicht bekannt."
    }
    
    private func openApp(bundleId: String) -> Bool {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }
    
    private func openSystemSettings() -> Bool {
        let url = URL(string: "x-apple.systempreferences:")!
        return NSWorkspace.shared.open(url)
    }
    
    private func takeScreenshot() -> Bool {
        let process = Process()
        process.launchPath = "/usr/sbin/screencapture"
        let desktopPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Jarvis_Screenshot.png").path
        process.arguments = ["-x", desktopPath]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
    
    private func adjustVolume(_ command: String) -> String {
        let script = command.contains("leise") ? "set volume output volume 20" : "set volume output volume 80"
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        return error == nil ? "Lautstärke angepasst." : "Fehler bei der Steuerung."
    }
}

import SwiftUI
import AppKit
import AVFoundation
import Speech

struct JarvisUpdateManifest: Codable {
    let app: String
    let channel: String
    let latestVersion: String
    let build: Int
    let minimumSupportedVersion: String
    let package: String?
    let sha256: String?
    let mandatory: Bool
    let releaseNotes: [String]
}

struct JarvisMemoryEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
}

enum JarvisRoute: String {
    case mac = "MAC"
    case memory = "GEDÄCHTNIS"
    case weather = "WETTER"
    case news = "NACHRICHTEN"
    case web = "INTERNET"
    case localAI = "LOKALE KI"
}

@main struct JarvisZeroApp: App {
    var body: some Scene {
        WindowGroup { JarvisView().frame(minWidth: 1280, minHeight: 820) }
            .windowStyle(.hiddenTitleBar)
    }
}

struct LogLine: Identifiable { let id = UUID(); let who:String; let text:String }

@MainActor final class JarvisCore: NSObject, ObservableObject, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {
    @Published var status = "BEREIT"
    @Published var transcript = ""
    @Published var logs:[LogLine] = [LogLine(who:"JARVIS", text:"System online. Bereit, Jonas.")]
    @Published var listening = false
    @Published var continuous = true
    @Published var speaking = false
    @Published var voiceLabel = "DEUTSCHE STIMME"
    @Published var localAI = false
    @Published var localAIModel = "NICHT VERBUNDEN"
    @Published var aiSetupStatus = "PRÜFUNG AUSSTEHEND"
    @Published var aiInstalling = false
    @Published var memoryCount = 0
    @Published var developmentStatus = "BEREIT"
    @Published var candidateReady = false
    @Published var developerMode = false
    @Published var awaitingDeveloperInstallConfirmation = false
    @Published var developerInstruction = ""
    @Published var internetStatus = "BEREIT"
    @Published var claudeCodeStatus = "PRÜFUNG AUSSTEHEND"
    @Published var claudeCodeAvailable = false
    @Published var lastRoute = "LOKAL"
    @Published var defaultLocation = UserDefaults.standard.string(forKey:"JarvisDefaultLocation") ?? ""
    @Published var cpuPulse:Double = 0.22
    @Published var updateAvailable = false
    @Published var latestVersion = "1.9.3"
    @Published var updateStatus = "AKTUELL"
    @Published var updateNotes:[String] = []
    private var pendingPackageURL:String?
    private var pendingSHA256:String?
    private static let currentVersion = "1.9.3"
    private static let manifestURL = "https://raw.githubusercontent.com/Jarvis291-source/Jarvis-Mark-III/main/manifest.json"
    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier:"de-DE"))
    private var request:SFSpeechAudioBufferRecognitionRequest?
    private var task:SFSpeechRecognitionTask?
    private var lastHandled = ""
    private var restartWork: Task<Void,Never>?
    private var updateLoop: Task<Void,Never>?
    private var developmentLoop: Task<Void,Never>?
    private var recentContext:[String] = []
    private var memory:[JarvisMemoryEntry] = []
    private static let selfSourceURL = "https://raw.githubusercontent.com/Jarvis291-source/Jarvis-Mark-III/main/releases/1.9.3/JarvisZero.swift"

    override init(){ super.init(); recognizer?.delegate = self; synth.delegate = self }
    func boot() async {
        loadMemory()
        await requestPermissions()
        await checkLocalAI()
        checkClaudeCode()
        await checkForUpdates()
        startAutomaticUpdateChecks()
        startDevelopmentLoop()
        if continuous { startListening() }
    }
    func startAutomaticUpdateChecks() {
        updateLoop?.cancel()
        updateLoop = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000_000)
                if Task.isCancelled { break }
                await self.checkForUpdates()
            }
        }
    }
    func requestPermissions() async {
        _ = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { _ in c.resume(returning: ()) } }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
    func speak(_ text:String){
        logs.append(LogLine(who:"JARVIS",text:text))
        let resume = continuous

        if engine.isRunning { stopListening() }
        synth.stopSpeaking(at:.immediate)

        let utterance = AVSpeechUtterance(string:text)
        let voices = AVSpeechSynthesisVoice.speechVoices()

        let germanMalePremium = voices.first {
            $0.language == "de-DE" && $0.gender == .male && $0.quality == .premium
        }
        let germanPremium = voices.first {
            $0.language == "de-DE" && $0.quality == .premium
        }
        let germanMaleEnhanced = voices.first {
            $0.language == "de-DE" && $0.gender == .male && $0.quality == .enhanced
        }
        let germanEnhanced = voices.first {
            $0.language == "de-DE" && $0.quality == .enhanced
        }
        let germanMale = voices.first {
            $0.language == "de-DE" && $0.gender == .male
        }
        let chosen = germanMalePremium
            ?? germanPremium
            ?? germanMaleEnhanced
            ?? germanEnhanced
            ?? germanMale
            ?? AVSpeechSynthesisVoice(language:"de-DE")

        utterance.voice = chosen
        utterance.rate = 0.50
        utterance.pitchMultiplier = 0.97
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.01
        utterance.postUtteranceDelay = 0.02

        voiceLabel = chosen?.name.uppercased() ?? "DE SYSTEM"
        shouldResumeAfterSpeech = resume
        speaking = true
        status = "SPRICHT"
        synth.speak(utterance)
    }

    private var shouldResumeAfterSpeech = false

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speaking = true
            self.status = "SPRICHT"
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speaking = false
            if self.shouldResumeAfterSpeech && self.continuous {
                self.shouldResumeAfterSpeech = false
                try? await Task.sleep(nanoseconds: 180_000_000)
                self.startListening()
            } else {
                self.status = self.listening ? "HÖRT ZU" : "BEREIT"
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speaking = false
            if self.continuous && !self.listening {
                try? await Task.sleep(nanoseconds: 150_000_000)
                self.startListening()
            }
        }
    }


    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Jarvis-ZERO", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var memoryURL: URL { supportDirectory.appendingPathComponent("memory.json") }
    private var developmentDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Entwicklung", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func loadMemory() {
        guard let data = try? Data(contentsOf: memoryURL),
              let decoded = try? JSONDecoder().decode([JarvisMemoryEntry].self, from: data) else {
            memory = []
            memoryCount = 0
            return
        }
        memory = decoded
        memoryCount = memory.count
    }

    private func saveMemory() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? data.write(to: memoryURL, options: .atomic)
        memoryCount = memory.count
    }

    func remember(_ text:String) {
        let clean = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard clean.count > 1 else { return }
        if !memory.contains(where: { $0.text.caseInsensitiveCompare(clean) == .orderedSame }) {
            memory.append(JarvisMemoryEntry(id:UUID(), text:clean, createdAt:Date()))
            if memory.count > 250 { memory.removeFirst(memory.count - 250) }
            saveMemory()
        }
    }

    private func memoryContext() -> String {
        memory.suffix(30).map { "- \($0.text)" }.joined(separator:"\n")
    }

    private func addContext(_ role:String,_ text:String) {
        let clean=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else{return}
        recentContext.append("\(role): \(clean)")
        if recentContext.count > 16 { recentContext.removeFirst(recentContext.count - 16) }
    }

    func startDevelopmentLoop() {
        developmentLoop?.cancel()
        developmentLoop = Task {
            try? await Task.sleep(nanoseconds: 21_600_000_000_000)
            while !Task.isCancelled {
                if self.localAI && !self.speaking && !self.listening {
                    await self.analyzeDevelopmentIdea()
                }
                try? await Task.sleep(nanoseconds: 43_200_000_000_000)
            }
        }
    }

    func analyzeDevelopmentIdea() async {
        guard localAI else {
            developmentStatus = "KI NICHT BEREIT"
            return
        }
        developmentStatus = "ANALYSE"
        let recent = logs.suffix(20).map { "\($0.who): \($0.text)" }.joined(separator:"\n")
        let prompt = """
        Analysiere Jarvis als lokalen macOS-Assistenten. Finde genau eine kleine, realistische Verbesserung,
        die Zuverlässigkeit, Bedienung, Sprachsteuerung oder Automatisierung verbessert.
        Antworte ausschließlich auf Deutsch und sehr konkret. Kein Marketing.
        Letzte Nutzung:
        \(recent)
        """
        if let idea = await askOllamaRaw(prompt) {
            let stamp = ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")
            let file = developmentDirectory.appendingPathComponent("Idee-\(stamp).txt")
            try? idea.write(to:file, atomically:true, encoding:.utf8)
            developmentStatus = "NEUE IDEE GESPEICHERT"
        } else {
            developmentStatus = "ANALYSEFEHLER"
        }
    }

    private var activeSourceURL: URL {
        developmentDirectory.appendingPathComponent("AktiverQuellcode.swift")
    }

    private var developerCandidateAppURL: URL {
        developmentDirectory.appendingPathComponent("Jarvis-Entwicklungskandidat.app", isDirectory:true)
    }

    private func loadDevelopmentSource() async -> String? {
        if let local=try? String(contentsOf:activeSourceURL,encoding:.utf8),
           local.contains("@main struct JarvisZeroApp") { return local }
        guard let url=URL(string:Self.selfSourceURL) else{return nil}
        do {
            var req=URLRequest(url:url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.timeoutInterval = 30
            let (data,response)=try await URLSession.shared.data(for:req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let source=String(data:data,encoding:.utf8) else{return nil}
            try? source.write(to:activeSourceURL,atomically:true,encoding:.utf8)
            return source
        } catch { return nil }
    }

    func enterDeveloperMode() {
        checkClaudeCode()
        guard claudeCodeAvailable else {
            developerMode=false
            developmentStatus="CLAUDE CODE NICHT BEREIT"
            speak("Der Entwicklermodus braucht Claude Code. Ich kann Claude Code auf diesem Mac gerade nicht erreichen.")
            return
        }
        developerMode=true
        awaitingDeveloperInstallConfirmation=false
        developmentStatus="ENTWICKLERMODUS AKTIV"
        speak("Entwicklermodus aktiviert. Sag mir jetzt, was ich an mir verändern soll.")
    }

    func leaveDeveloperMode() {
        developerMode=false
        awaitingDeveloperInstallConfirmation=false
        developerInstruction=""
        developmentStatus="BEREIT"
        speak("Entwicklermodus beendet.")
    }
    func processDeveloperInstruction(_ instruction:String) async {
        let clean=instruction.trimmingCharacters(in:.whitespacesAndNewlines)
        guard developerMode, !clean.isEmpty else{return}
        checkClaudeCode()
        guard claudeCodeAvailable else {
            developmentStatus="CLAUDE CODE NICHT BEREIT"
            speak("Claude Code ist nicht erreichbar. Ich habe nichts verändert.")
            return
        }

        developerInstruction=clean
        candidateReady=false
        awaitingDeveloperInstallConfirmation=false
        developmentStatus="QUELLCODE LADEN"

        guard let source=await loadDevelopmentSource() else {
            developmentStatus="QUELLCODEFEHLER"
            speak("Ich konnte meinen aktuellen Quellcode nicht laden.")
            return
        }

        speak("Verstanden. Ich lasse Claude Code die Änderung jetzt entwickeln und prüfe den neuen Build anschließend.")
        developmentStatus="CLAUDE CODE ENTWICKELT"

        let prompt = """
        Du arbeitest im ausdrücklich aktivierten Entwicklermodus von Jarvis ZERO.
        Ändere den vollständigen SwiftUI-macOS-Quellcode exakt nach dem Entwicklungsauftrag.

        ENTWICKLUNGSAUFTRAG:
        \(clean)

        REGELN:
        - Gib ausschließlich den vollständigen neuen Swift-Quellcode zurück, ohne Markdown.
        - Bestehende Kernfunktionen, Gedächtnis, Mac-Steuerung, Internet, Ollama, Claude-Code-Anbindung und Update-System erhalten, außer der Auftrag verlangt ausdrücklich eine Änderung.
        - Keine Zugangsdaten, Tokens oder Passwörter einbauen.
        - Keine macOS-Berechtigungen oder Sicherheitsmechanismen umgehen.
        - Der Code muss mit SwiftUI, AppKit, AVFoundation und Speech kompilierbar bleiben.
        - Der erzeugte Code darf sich nicht selbst installieren.
        - Installation erfolgt erst nach ausdrücklicher Bestätigung des Benutzers.

        AKTUELLER QUELLCODE:
        \(source)
        """

        guard var candidate=await askClaudeCode(prompt,workingDirectory:developmentDirectory) else {
            developmentStatus="CLAUDE CODE FEHLER"
            speak("Claude Code konnte den Entwicklungsauftrag nicht abschließen. Ich habe nichts verändert.")
            return
        }

        if candidate.hasPrefix("```") {
            candidate=candidate
                .replacingOccurrences(of:"```swift",with:"")
                .replacingOccurrences(of:"```",with:"")
                .trimmingCharacters(in:.whitespacesAndNewlines)
        }

        guard candidate.contains("import SwiftUI"),
              candidate.contains("@main struct JarvisZeroApp"),
              candidate.contains("confirmAndInstallUpdate"),
              candidate.contains("processDeveloperInstruction") else {
            developmentStatus="KANDIDAT UNGÜLTIG"
            speak("Der neue Entwurf hat meine Strukturprüfung nicht bestanden und wurde verworfen.")
            return
        }

        let candidateFile=developmentDirectory.appendingPathComponent("EntwicklerKandidat.swift")
        do {
            try candidate.write(to:candidateFile,atomically:true,encoding:.utf8)
            let fm=FileManager.default
            try? fm.removeItem(at:developerCandidateAppURL)
            let macos=developerCandidateAppURL.appendingPathComponent("Contents/MacOS",isDirectory:true)
            try fm.createDirectory(at:macos,withIntermediateDirectories:true)
            let plist=developerCandidateAppURL.appendingPathComponent("Contents/Info.plist")
            try fm.copyItem(at:Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist"),to:plist)

            developmentStatus="KOMPILIERPRÜFUNG"
            let binary=macos.appendingPathComponent("JarvisZero")
            let compile=runProcess("/usr/bin/xcrun",[
                "swiftc","-parse-as-library",candidateFile.path,
                "-o",binary.path,
                "-framework","SwiftUI",
                "-framework","AppKit",
                "-framework","AVFoundation",
                "-framework","Speech"
            ])
            guard compile == 0, fm.fileExists(atPath:binary.path) else {
                candidateReady=false
                developmentStatus="KANDIDAT VERWORFEN"
                speak("Der neue Code hat die Kompilierprüfung nicht bestanden. Die laufende Version bleibt unverändert.")
                return
            }

            _=runProcess("/bin/chmod",["+x",binary.path])
            developmentStatus="SIGNIERPRÜFUNG"
            let sign=runProcess("/usr/bin/codesign",["--force","--deep","--sign","-",developerCandidateAppURL.path])
            guard sign == 0,
                  runProcess("/usr/bin/codesign",["--verify","--deep","--strict",developerCandidateAppURL.path]) == 0 else {
                candidateReady=false
                developmentStatus="SIGNIERPRÜFUNG FEHLER"
                speak("Der neue Build hat die Signierprüfung nicht bestanden und wurde verworfen.")
                return
            }

            try candidate.write(to:activeSourceURL,atomically:true,encoding:.utf8)
            candidateReady=true
            awaitingDeveloperInstallConfirmation=true
            developmentStatus="ENTWICKLUNG BEREIT"
            speak("Die neue Entwicklung ist fertig und geprüft. Soll ich sie jetzt installieren?")
        } catch {
            candidateReady=false
            developmentStatus="ENTWICKLUNGSFEHLER"
            speak("Beim Aufbau des neuen Jarvis ist ein Fehler aufgetreten. Die bisherige Version bleibt erhalten.")
        }
    }
    func installDeveloperCandidate() {
        guard candidateReady,
              FileManager.default.fileExists(atPath:developerCandidateAppURL.path) else {
            awaitingDeveloperInstallConfirmation=false
            developmentStatus="KEIN KANDIDAT"
            speak("Es ist gerade keine geprüfte Entwicklung zur Installation vorhanden.")
            return
        }

        awaitingDeveloperInstallConfirmation=false
        let fm=FileManager.default
        let home=fm.homeDirectoryForCurrentUser
        let target=home.appendingPathComponent("Applications/Jarvis-ZERO.app",isDirectory:true)
        let backup=home.appendingPathComponent("Applications/Jarvis-ZERO-Backup.app",isDirectory:true)
        let desktopLink=home.appendingPathComponent("Desktop/Jarvis.app")
        let log=home.appendingPathComponent("Desktop/Jarvis-Entwicklung.log")
        let helper=developmentDirectory.appendingPathComponent("install-dev.sh")

        let shell = """
        #!/bin/bash
        set -u
        TARGET="\(target.path)"
        BACKUP="\(backup.path)"
        NEW="\(developerCandidateAppURL.path)"
        LOG="\(log.path)"
        DESKTOP_LINK="\(desktopLink.path)"

        exec >>"$LOG" 2>&1
        echo "=== JARVIS ENTWICKLERMODUS ==="
        date

        /bin/rm -rf "$BACKUP"
        if [ -d "$TARGET" ]; then
          /bin/cp -R "$TARGET" "$BACKUP" || exit 31
        fi

        /usr/bin/pkill -TERM -x JarvisZero 2>/dev/null || true
        sleep 1

        /bin/rm -rf "$TARGET"
        /bin/cp -R "$NEW" "$TARGET" || {
          /bin/rm -rf "$TARGET"
          [ -d "$BACKUP" ] && /bin/cp -R "$BACKUP" "$TARGET"
          exit 32
        }

        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
        /usr/bin/codesign --verify --deep --strict "$TARGET" || {
          /bin/rm -rf "$TARGET"
          [ -d "$BACKUP" ] && /bin/cp -R "$BACKUP" "$TARGET"
          /usr/bin/open -n "$TARGET" 2>/dev/null || true
          exit 33
        }

        /bin/rm -rf "$DESKTOP_LINK"
        /bin/ln -s "$TARGET" "$DESKTOP_LINK"
        /usr/bin/open -n "$TARGET"
        sleep 4

        if /usr/bin/pgrep -x JarvisZero >/dev/null 2>&1; then
          echo "SUCCESS"
          exit 0
        fi

        echo "START FEHLER - ROLLBACK"
        /bin/rm -rf "$TARGET"
        if [ -d "$BACKUP" ]; then
          /bin/cp -R "$BACKUP" "$TARGET"
          /usr/bin/open -n "$TARGET" 2>/dev/null || true
        fi
        exit 34
        """

        do {
            try shell.write(to:helper,atomically:true,encoding:.utf8)
            _=runProcess("/bin/chmod",["+x",helper.path])
            developmentStatus="INSTALLATION"
            speak("Verstanden. Ich installiere die geprüfte Entwicklung und starte anschließend neu.")

            let launcher=Process()
            launcher.executableURL=URL(fileURLWithPath:"/usr/bin/nohup")
            launcher.arguments=["/bin/bash",helper.path]
            launcher.standardOutput=FileHandle.nullDevice
            launcher.standardError=FileHandle.nullDevice
            try launcher.run()

            DispatchQueue.main.asyncAfter(deadline:.now()+1.2) {
                NSApp.terminate(nil)
            }
        } catch {
            developmentStatus="INSTALLATIONSFEHLER"
            speak("Die Installation konnte nicht gestartet werden. Die aktuelle Version bleibt erhalten.")
        }
    }
    func runSelfDevelopmentCycle() async {
        guard localAI else {
            developmentStatus = "KI NICHT BEREIT"
            return
        }
        developmentStatus = "QUELLCODE LADEN"
        guard let url=URL(string:Self.selfSourceURL) else {
            developmentStatus = "QUELLCODEFEHLER"
            return
        }
        do {
            var req=URLRequest(url:url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.timeoutInterval = 30
            let (data,response)=try await URLSession.shared.data(for:req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let source=String(data:data,encoding:.utf8) else {
                developmentStatus = "QUELLCODEFEHLER"
                return
            }

            developmentStatus = "KANDIDAT ENTWICKELN"
            let prompt = """
            Du verbesserst eine SwiftUI macOS-App namens Jarvis ZERO.
            Erstelle aus dem folgenden Quellcode eine konservativ verbesserte Version.
            Regeln:
            - Bestehende Funktionen und Update-Mechanismus erhalten.
            - Keine neuen kostenpflichtigen APIs.
            - Keine geheimen Daten oder Zugangsdaten einbauen.
            - Keine selbstständige Installation oder Ersetzung der laufenden App.
            - Nur eine kleine, sinnvolle Verbesserung.
            - Gib ausschließlich vollständigen Swift-Quellcode zurück, ohne Markdown.
            QUELLCODE:
            \(source)
            """

            let candidate:String?
            if claudeCodeAvailable {
                developmentStatus = "CLAUDE CODE ENTWICKELT"
                candidate = await askClaudeCode(prompt, workingDirectory: developmentDirectory)
            } else {
                developmentStatus = "OLLAMA ENTWICKELT"
                candidate = await askOllamaRaw(prompt)
            }

            guard let candidate,
                  candidate.contains("import SwiftUI"),
                  candidate.contains("@main struct JarvisZeroApp") else {
                developmentStatus = "KANDIDAT UNGÜLTIG"
                return
            }

            let candidateFile=developmentDirectory.appendingPathComponent("Kandidat.swift")
            try candidate.write(to:candidateFile,atomically:true,encoding:.utf8)

            developmentStatus = "KANDIDAT PRÜFEN"
            let binary=developmentDirectory.appendingPathComponent("Kandidat")
            try? FileManager.default.removeItem(at:binary)
            let result=runProcess("/usr/bin/xcrun",[
                "swiftc","-parse-as-library",candidateFile.path,
                "-o",binary.path,
                "-framework","SwiftUI",
                "-framework","AppKit",
                "-framework","AVFoundation",
                "-framework","Speech"
            ])
            guard result == 0, FileManager.default.fileExists(atPath:binary.path) else {
                candidateReady=false
                developmentStatus = "KANDIDAT VERWORFEN"
                return
            }

            candidateReady=true
            developmentStatus = "KANDIDAT GEPRÜFT"
        } catch {
            candidateReady=false
            developmentStatus = "ENTWICKLUNGSFEHLER"
        }
    }


    private func findClaudeBinary() -> String? {
        let candidates=[
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        ]
        if let direct=candidates.first(where:{ FileManager.default.isExecutableFile(atPath:$0) }) {
            return direct
        }
        if let which=runCapture("/usr/bin/which",["claude"])?.trimmingCharacters(in:.whitespacesAndNewlines),
           !which.isEmpty,
           FileManager.default.isExecutableFile(atPath:which) {
            return which
        }
        return nil
    }

    func checkClaudeCode() {
        if let claude=findClaudeBinary() {
            claudeCodeAvailable=true
            claudeCodeStatus="VERBUNDEN"
            let version=runCapture(claude,["--version"])?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
            if !version.isEmpty { claudeCodeStatus="VERBUNDEN // \(version)" }
        } else {
            claudeCodeAvailable=false
            claudeCodeStatus="NICHT GEFUNDEN"
        }
    }

    private func askClaudeCode(_ prompt:String, workingDirectory:URL? = nil) async -> String? {
        guard let claude=findClaudeBinary() else {
            claudeCodeAvailable=false
            claudeCodeStatus="NICHT GEFUNDEN"
            return nil
        }

        claudeCodeStatus="ARBEITET"
        let result:String? = await Task.detached(priority:.userInitiated) {
            let pipe=Pipe()
            let err=Pipe()
            let p=Process()
            p.executableURL=URL(fileURLWithPath:claude)
            p.arguments=["-p",prompt]
            if let dir=workingDirectory {
                p.currentDirectoryURL=dir
            }
            p.standardOutput=pipe
            p.standardError=err
            do {
                try p.run()
                p.waitUntilExit()
                guard p.terminationStatus == 0 else { return nil }
                let data=pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data:data,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)
            } catch {
                return nil
            }
        }.value

        if let result, !result.isEmpty {
            claudeCodeAvailable=true
            claudeCodeStatus="BEREIT"
            return result
        } else {
            claudeCodeStatus="FEHLER"
            return nil
        }
    }

    func checkLocalAI() async {
        aiSetupStatus = "PRÜFE LOKALE KI"
        guard let url=URL(string:"http://127.0.0.1:11434/api/tags") else{return}

        func probe() async -> [String]? {
            var r=URLRequest(url:url)
            r.timeoutInterval=1.5
            do {
                let (data,resp)=try await URLSession.shared.data(for:r)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any]
                let models=(obj?["models"] as? [[String:Any]]) ?? []
                return models.compactMap { $0["name"] as? String }
            } catch { return nil }
        }

        var names = await probe()
        if names == nil, let ollama=findOllamaBinary() {
            aiSetupStatus="STARTE KI-DIENST"
            let p=Process()
            p.executableURL=URL(fileURLWithPath:ollama)
            p.arguments=["serve"]
            p.standardOutput=FileHandle.nullDevice
            p.standardError=FileHandle.nullDevice
            try? p.run()
            try? await Task.sleep(nanoseconds:1_200_000_000)
            names=await probe()
        }

        guard let available=names else {
            localAI=false
            localAIModel="NICHT VERBUNDEN"
            aiSetupStatus=findOllamaBinary() == nil ? "OLLAMA FEHLT" : "KI-DIENST NICHT ERREICHBAR"
            return
        }

        if let preferred=available.first(where:{ $0.lowercased().contains("qwen2.5:3b") }) {
            localAI=true
            localAIModel=preferred
            aiSetupStatus="KI BEREIT"
        } else if let first=available.first {
            localAI=true
            localAIModel=first
            aiSetupStatus="KI BEREIT"
        } else {
            localAI=false
            localAIModel="KEIN MODELL"
            aiSetupStatus="MODELL FEHLT"
        }
    }

    private func findOllamaBinary() -> String? {
        let candidates=[
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath:$0) }
    }

    func confirmAndSetupAI() {
        guard !aiInstalling else{return}
        let alert=NSAlert()
        alert.messageText="Lokale KI für Jarvis einrichten?"
        alert.informativeText="Jarvis lädt das lokale Modell qwen2.5:3b über Ollama. Das Modell benötigt mehrere Gigabyte Speicherplatz und bleibt lokal auf diesem Mac."
        alert.alertStyle = .informational
        alert.addButton(withTitle:"KI einrichten")
        alert.addButton(withTitle:"Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await setupLocalAI() }
        }
    }

    func setupLocalAI() async {
        guard !aiInstalling else{return}
        aiInstalling=true
        defer { aiInstalling=false }

        guard let ollama=findOllamaBinary() else {
            aiSetupStatus="OLLAMA FEHLT"
            speak("Ollama ist auf diesem Mac noch nicht installiert. Installiere Ollama einmal, danach kann ich das lokale KI-Modell selbst einrichten.")
            return
        }

        aiSetupStatus="STARTE KI-DIENST"
        let server=Process()
        server.executableURL=URL(fileURLWithPath:ollama)
        server.arguments=["serve"]
        server.standardOutput=FileHandle.nullDevice
        server.standardError=FileHandle.nullDevice
        try? server.run()
        try? await Task.sleep(nanoseconds:1_000_000_000)

        aiSetupStatus="LADE KI-MODELL"
        let pull=Process()
        pull.executableURL=URL(fileURLWithPath:ollama)
        pull.arguments=["pull","qwen2.5:3b"]
        pull.standardOutput=FileHandle.nullDevice
        pull.standardError=FileHandle.nullDevice
        do {
            try pull.run()
            pull.waitUntilExit()
            guard pull.terminationStatus == 0 else {
                aiSetupStatus="MODELL-DOWNLOAD FEHLER"
                return
            }
        } catch {
            aiSetupStatus="MODELL-DOWNLOAD FEHLER"
            return
        }

        await checkLocalAI()
        if localAI {
            speak("Die lokale KI ist eingerichtet und einsatzbereit.")
        }
    }

    func checkForUpdates() async {
        updateStatus = "PRÜFUNG…"
        let url = Self.manifestURL + "?t=\(Int(Date().timeIntervalSince1970))"

        guard let output = runCapture("/usr/bin/curl", [
            "-L", "--fail", "--silent", "--show-error",
            "--connect-timeout", "5",
            "--max-time", "12",
            "-H", "Cache-Control: no-cache",
            url
        ]) else {
            updateAvailable = false
            updateStatus = "NETZWERKFEHLER"
            return
        }

        guard let data = output.data(using: .utf8) else {
            updateAvailable = false
            updateStatus = "DATENFEHLER"
            return
        }

        do {
            let manifest = try JSONDecoder().decode(JarvisUpdateManifest.self, from: data)
            latestVersion = manifest.latestVersion
            updateNotes = manifest.releaseNotes
            pendingPackageURL = manifest.package
            pendingSHA256 = manifest.sha256
            updateAvailable = isVersion(manifest.latestVersion, newerThan: Self.currentVersion)
                && manifest.package != nil
                && manifest.sha256 != nil
            updateStatus = updateAvailable ? "UPDATE \(manifest.latestVersion)" : "AKTUELL"
        } catch {
            updateAvailable = false
            updateStatus = "LESEFEHLER"
        }
    }

    private func isVersion(_ remote:String, newerThan local:String) -> Bool {
        let a = remote.split(separator:".").map { Int($0) ?? 0 }
        let b = local.split(separator:".").map { Int($0) ?? 0 }
        let n = max(a.count,b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
    func confirmAndInstallUpdate() {
        guard updateAvailable else { Task { await checkForUpdates() }; return }
        let alert = NSAlert()
        alert.messageText = "JARVIS Update \(latestVersion) installieren?"
        alert.informativeText = "Jarvis erstellt zuerst ein Backup. Das Update wird nur nach deiner Bestätigung installiert."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update installieren")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn { Task { await installPendingUpdate() } }
    }
    private func installPendingUpdate() async {
        guard let urlText = pendingPackageURL,
              let expected = pendingSHA256?.lowercased(),
              let url = URL(string: urlText) else {
            updateStatus = "UPDATE UNGÜLTIG"
            return
        }

        updateStatus = "WIRD GELADEN"
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 30
            request.setValue("Jarvis-ZERO/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                updateStatus = "DOWNLOADFEHLER"
                return
            }

            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("JarvisUpdate-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)

            let source = work.appendingPathComponent("JarvisZero.swift")
            try data.write(to: source, options: .atomic)

            updateStatus = "DATEIPRÜFUNG"
            guard let actual = sha256(of: source), actual == expected else {
                updateStatus = "PRÜFSUMMENFEHLER"
                return
            }

            let app = work.appendingPathComponent("Jarvis-ZERO.app", isDirectory: true)
            let macos = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
            let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
            try fm.createDirectory(at: macos, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)

            let plist = app.appendingPathComponent("Contents/Info.plist")
            let currentPlist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
            try fm.copyItem(at: currentPlist, to: plist)

            _ = runProcess("/usr/libexec/PlistBuddy", ["-c", "Set :CFBundleShortVersionString \(latestVersion)", plist.path])
            _ = runProcess("/usr/libexec/PlistBuddy", ["-c", "Set :CFBundleVersion \(latestVersion.replacingOccurrences(of: ".", with: ""))", plist.path])

            let binary = macos.appendingPathComponent("JarvisZero")
            updateStatus = "WIRD VORBEREITET"
            let compile = runProcess("/usr/bin/xcrun", [
                "swiftc", "-parse-as-library", source.path,
                "-o", binary.path,
                "-framework", "SwiftUI",
                "-framework", "AppKit",
                "-framework", "AVFoundation",
                "-framework", "Speech"
            ])
            guard compile == 0, fm.fileExists(atPath: binary.path) else {
                updateStatus = "KOMPILIERFEHLER"
                return
            }

            _ = runProcess("/bin/chmod", ["+x", binary.path])
            let sign = runProcess("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
            guard sign == 0 else {
                updateStatus = "SIGNIERFEHLER"
                return
            }

            let home = fm.homeDirectoryForCurrentUser
            let apps = home.appendingPathComponent("Applications", isDirectory: true)
            try fm.createDirectory(at: apps, withIntermediateDirectories: true)

            let target = apps.appendingPathComponent("Jarvis-ZERO.app", isDirectory: true)
            let backup = apps.appendingPathComponent("Jarvis-ZERO-Backup.app", isDirectory: true)
            let log = home.appendingPathComponent("Desktop/Jarvis-Update.log")
            let desktopLink = home.appendingPathComponent("Desktop/Jarvis.app")
            let helper = work.appendingPathComponent("install.sh")

            let shell = """
            #!/bin/bash
            set -u

            TARGET=\"\(target.path)\"
            BACKUP=\"\(backup.path)\"
            NEW=\"\(app.path)\"
            LOG=\"\(log.path)\"
            DESKTOP_LINK=\"\(desktopLink.path)\"

            exec >>"$LOG" 2>&1
            echo "=== JARVIS UPDATE \(latestVersion) ==="
            date
            echo "Waiting for current Jarvis to close..."

            for i in {1..30}; do
              if ! /usr/bin/pgrep -x JarvisZero >/dev/null 2>&1; then
                break
              fi
              sleep 0.2
            done

            /usr/bin/pkill -TERM -x JarvisZero 2>/dev/null || true
            sleep 1

            /bin/rm -rf "$BACKUP"
            if [ -d "$TARGET" ]; then
              /bin/cp -R "$TARGET" "$BACKUP" || exit 21
            fi

            /bin/rm -rf "$TARGET"
            /bin/cp -R "$NEW" "$TARGET" || {
              echo "Copy failed, restoring backup."
              /bin/rm -rf "$TARGET"
              [ -d "$BACKUP" ] && /bin/cp -R "$BACKUP" "$TARGET"
              exit 22
            }

            /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
            /bin/rm -rf "$DESKTOP_LINK"
            /bin/ln -s "$TARGET" "$DESKTOP_LINK"
            /usr/bin/codesign --verify --deep --strict "$TARGET" || {
              echo "Verification failed, restoring backup."
              /bin/rm -rf "$TARGET"
              [ -d "$BACKUP" ] && /bin/cp -R "$BACKUP" "$TARGET"
              /usr/bin/open "$TARGET" 2>/dev/null || true
              exit 23
            }

            echo "Installed app verified. Launching Jarvis..."
            /usr/bin/open -n "$TARGET"
            sleep 3

            if /usr/bin/pgrep -x JarvisZero >/dev/null 2>&1; then
              echo "SUCCESS: Jarvis \(latestVersion) is running."
              echo "Desktop link: $DESKTOP_LINK"
              exit 0
            fi

            echo "New Jarvis did not start. Rolling back."
            /bin/rm -rf "$TARGET"
            if [ -d "$BACKUP" ]; then
              /bin/cp -R "$BACKUP" "$TARGET"
              /usr/bin/open -n "$TARGET" 2>/dev/null || true
            fi
            exit 24
            """

            try shell.write(to: helper, atomically: true, encoding: .utf8)
            _ = runProcess("/bin/chmod", ["+x", helper.path])

            updateStatus = "NEUSTART"

            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            launcher.arguments = ["/bin/bash", helper.path]
            launcher.standardOutput = FileHandle.nullDevice
            launcher.standardError = FileHandle.nullDevice
            try launcher.run()

            try? await Task.sleep(nanoseconds: 400_000_000)
            NSApp.terminate(nil)
        } catch {
            updateStatus = "UPDATEFEHLER"
        }
    }

    private func sha256(of url:URL) -> String? {
        let pipe=Pipe(); let p=Process(); p.executableURL=URL(fileURLWithPath:"/usr/bin/shasum"); p.arguments=["-a","256",url.path]; p.standardOutput=pipe
        do { try p.run(); p.waitUntilExit(); guard p.terminationStatus == 0 else{return nil}; let d=pipe.fileHandleForReading.readDataToEndOfFile(); return String(data:d,encoding:.utf8)?.split(separator:" ").first.map(String.init)?.lowercased() } catch { return nil }
    }
    private func runCapture(_ executable:String,_ args:[String]) -> String? {
        let pipe = Pipe()
        let err = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    @discardableResult private func runProcess(_ executable:String,_ args:[String]) -> Int32 {
        let p=Process(); p.executableURL=URL(fileURLWithPath:executable); p.arguments=args
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }

    func startListening(){
        guard !engine.isRunning else{return}
        let req=SFSpeechAudioBufferRecognitionRequest(); req.shouldReportPartialResults=true; if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }; req.contextualStrings = ["Jarvis", "öffne Safari", "öffne Finder", "öffne Mail", "öffne Kalender", "öffne Notizen", "öffne Systemeinstellungen", "öffne Rechner", "mach einen Screenshot", "Lautstärke", "Update prüfen"]; request=req
        let node=engine.inputNode; let format=node.outputFormat(forBus:0)
        node.removeTap(onBus:0); node.installTap(onBus:0, bufferSize:1024, format:format){ [weak req] b,_ in req?.append(b) }
        engine.prepare()
        do { try engine.start(); listening=true; status="HÖRT ZU" } catch { status="MIKROFONFEHLER"; return }
        task=recognizer?.recognitionTask(with:req){ [weak self] result,error in
            guard let self else{return}
            Task { @MainActor in
                if let text=result?.bestTranscription.formattedString { self.transcript=text; self.maybeHandle(text) }
                if error != nil || result?.isFinal == true { self.restartListeningSoon() }
            }
        }
    }
    func stopListening(){ task?.cancel(); task=nil; request?.endAudio(); request=nil; if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus:0) }; listening=false; status="ONLINE" }
    func restartListeningSoon(){
        stopListening(); guard continuous else{return}; restartWork?.cancel(); restartWork=Task { try? await Task.sleep(nanoseconds:350_000_000); if !Task.isCancelled { self.startListening() } }
    }
    func maybeHandle(_ text:String){
        let lower=text.lowercased(); guard lower.contains("jarvis") else{return}
        var cmd=lower
        if let r=cmd.range(of:"jarvis") { cmd=String(cmd[r.upperBound...]).trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters)) }
        guard cmd.count>2, cmd != lastHandled else{return}; lastHandled=cmd
        Task { await execute(cmd) }
    }
    func submit(_ text:String){ let clean=text.trimmingCharacters(in:.whitespacesAndNewlines); guard !clean.isEmpty else{return}; logs.append(LogLine(who:"DU",text:clean)); addContext("Nutzer",clean); Task{ await execute(clean.lowercased()) } }
    func openBundle(_ id:String,_ label:String) async { if let u=NSWorkspace.shared.urlForApplication(withBundleIdentifier:id){ do{ _=try await NSWorkspace.shared.openApplication(at:u,configuration:.init()); speak("\(label) wurde geöffnet.") }catch{speak("\(label) konnte ich nicht öffnen.")} } }
    private func decideRoute(_ cmd:String) async -> JarvisRoute {
        let q=cmd.lowercased()
        if q.hasPrefix("öffne ") || q.hasPrefix("starte ") || q.contains("screenshot") ||
           q.contains("lautstärke") || q.contains("stumm") || q.contains("ton an") ||
           q.contains("update prüfen") || q.contains("nach update suchen") { return .mac }
        if q.hasPrefix("merke dir ") || q.hasPrefix("merk dir ") || q.hasPrefix("lerne ") ||
           q.contains("was hast du gelernt") || q.contains("was weißt du über mich") { return .memory }
        if q.contains("wetter") || q.contains("temperatur morgen") || q.contains("regen morgen") ||
           q.contains("wird es morgen") { return .weather }
        if q.contains("nachrichten") || q.contains("news") || q.contains("was ist heute passiert") ||
           q.contains("was passiert auf der welt") || q.contains("weltgeschehen") { return .news }
        if q.contains("heute") || q.contains("aktuell") || q.contains("gerade") ||
           q.contains("neueste") || q.contains("preis") || q.contains("öffnungszeiten") { return .web }

        if localAI {
            let classify="""
            Ordne die Nutzeranfrage genau einer Kategorie zu.
            Antworte nur mit einem Wort:
            MAC, GEDÄCHTNIS, WETTER, NACHRICHTEN, INTERNET oder LOKALEKI.
            MAC = lokale Aktion am Mac.
            GEDÄCHTNIS = merken oder gespeichertes Wissen.
            WETTER = aktuelle Wetterfrage oder Vorhersage.
            NACHRICHTEN = aktuelle Ereignisse und Nachrichten.
            INTERNET = andere Informationen, die aktuelle Webdaten brauchen.
            LOKALEKI = zeitunabhängige Erklärung, Unterhaltung, Schreiben oder allgemeines Wissen.
            Anfrage: \(cmd)
            """
            if let result=await askOllamaRaw(classify)?.uppercased() {
                if result.contains("WETTER") { return .weather }
                if result.contains("NACHRICHTEN") { return .news }
                if result.contains("INTERNET") { return .web }
                if result.contains("GEDÄCHTNIS") { return .memory }
                if result.contains("MAC") { return .mac }
            }
        }
        return .localAI
    }

    private func locationFrom(_ cmd:String) -> String? {
        let q=cmd.trimmingCharacters(in:.whitespacesAndNewlines)
        if let r=q.range(of:" in ",options:.caseInsensitive) {
            let candidate=String(q[r.upperBound...]).trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters))
            if candidate.count >= 2 { return candidate }
        }
        return defaultLocation.isEmpty ? nil : defaultLocation
    }

    private func setDefaultLocation(_ location:String) {
        let clean=location.trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters))
        guard clean.count >= 2 else{return}
        defaultLocation=clean
        UserDefaults.standard.set(clean,forKey:"JarvisDefaultLocation")
    }

    private func weatherCodeText(_ code:Int) -> String {
        switch code {
        case 0: return "klar"
        case 1,2: return "überwiegend klar"
        case 3: return "bewölkt"
        case 45,48: return "neblig"
        case 51,53,55,56,57: return "Nieselregen"
        case 61,63,65,66,67: return "Regen"
        case 71,73,75,77: return "Schnee"
        case 80,81,82: return "Regenschauer"
        case 85,86: return "Schneeschauer"
        case 95,96,99: return "Gewitter"
        default: return "wechselhaft"
        }
    }

    private func fetchWeather(_ cmd:String) async -> String? {
        guard let place=locationFrom(cmd) else {
            return "Für welchen Ort soll ich das Wetter prüfen? Du kannst zum Beispiel sagen: Jarvis, mein Ort ist Hof."
        }
        internetStatus="WETTERDATEN"
        let encoded=place.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? place
        guard let geoURL=URL(string:"https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=de&format=json") else{return nil}
        do {
            let (geoData,geoResp)=try await URLSession.shared.data(from:geoURL)
            guard (geoResp as? HTTPURLResponse)?.statusCode == 200,
                  let geo=try JSONSerialization.jsonObject(with:geoData) as? [String:Any],
                  let results=geo["results"] as? [[String:Any]],
                  let first=results.first,
                  let lat=first["latitude"] as? Double,
                  let lon=first["longitude"] as? Double else {
                internetStatus="ORT NICHT GEFUNDEN"
                return "Ich konnte den Ort \(place) nicht eindeutig finden."
            }
            let resolved=(first["name"] as? String) ?? place
            let wantsTomorrow=cmd.lowercased().contains("morgen")
            let fstr="https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=3"
            guard let furl=URL(string:fstr) else{return nil}
            let (data,resp)=try await URLSession.shared.data(from:furl)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let daily=obj["daily"] as? [String:Any],
                  let maxs=daily["temperature_2m_max"] as? [Double],
                  let mins=daily["temperature_2m_min"] as? [Double],
                  let codes=daily["weather_code"] as? [Int],
                  let rain=daily["precipitation_probability_max"] as? [Int] else {
                internetStatus="WETTERFEHLER"; return nil
            }
            let i=wantsTomorrow ? 1 : 0
            guard i<maxs.count,i<mins.count,i<codes.count,i<rain.count else{return nil}
            internetStatus="BEREIT"
            return "\(wantsTomorrow ? "Morgen" : "Heute") wird es in \(resolved) \(weatherCodeText(codes[i])). Die Temperatur liegt ungefähr zwischen \(Int(mins[i].rounded())) und \(Int(maxs[i].rounded())) Grad. Die maximale Regenwahrscheinlichkeit liegt bei \(rain[i]) Prozent."
        } catch { internetStatus="WETTERFEHLER"; return nil }
    }

    private func decodeHTMLEntities(_ text:String) -> String {
        var x=text
        for (a,b) in ["&amp;":"&","&quot;":"\"","&#39;":"'","&lt;":"<","&gt;":">","&nbsp;":" "] {
            x=x.replacingOccurrences(of:a,with:b)
        }
        return x
    }

    private func stripHTML(_ text:String) -> String {
        let range=NSRange(location:0,length:(text as NSString).length)
        let regex=try? NSRegularExpression(pattern:"<[^>]+>",options:[])
        let clean=regex?.stringByReplacingMatches(in:text,options:[],range:range,withTemplate:"") ?? text
        return decodeHTMLEntities(clean).trimmingCharacters(in:.whitespacesAndNewlines)
    }

    private func fetchNews(_ cmd:String) async -> String? {
        internetStatus="NACHRICHTEN"
        let lower=cmd.lowercased()
        var query=""
        if let r=lower.range(of:"über ") {
            query=String(cmd[r.upperBound...]).trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters))
        }
        let urlString:String
        if query.isEmpty {
            urlString="https://news.google.com/rss?hl=de&gl=DE&ceid=DE:de"
        } else {
            let enc=query.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? query
            urlString="https://news.google.com/rss/search?q=\(enc)&hl=de&gl=DE&ceid=DE:de"
        }
        guard let url=URL(string:urlString) else{return nil}
        do {
            let (data,resp)=try await URLSession.shared.data(from:url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let xml=String(data:data,encoding:.utf8) else{return nil}
            let regex=try NSRegularExpression(pattern:"<item>.*?<title>(.*?)</title>.*?</item>",options:[.dotMatchesLineSeparators,.caseInsensitive])
            let ns=xml as NSString
            let matches=regex.matches(in:xml,range:NSRange(location:0,length:ns.length))
            let titles=matches.prefix(5).compactMap { m -> String? in
                guard m.numberOfRanges > 1 else{return nil}
                return stripHTML(ns.substring(with:m.range(at:1)))
            }
            guard !titles.isEmpty else{return nil}
            internetStatus="BEREIT"
            let joined=titles.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator:" ")
            return query.isEmpty ? "Die wichtigsten aktuellen Meldungen sind: \(joined)" : "Aktuelle Meldungen zu \(query): \(joined)"
        } catch { internetStatus="NACHRICHTENFEHLER"; return nil }
    }

    private func fetchWebSearch(_ cmd:String) async -> String? {
        internetStatus="INTERNETSUCHE"
        let encoded=cmd.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? cmd
        guard let url=URL(string:"https://html.duckduckgo.com/html/?q=\(encoded)") else{return nil}
        do {
            var req=URLRequest(url:url); req.timeoutInterval=15
            req.setValue("Mozilla/5.0 Jarvis-ZERO",forHTTPHeaderField:"User-Agent")
            let (data,resp)=try await URLSession.shared.data(for:req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let html=String(data:data,encoding:.utf8) else{return nil}
            let regex=try NSRegularExpression(pattern:"<a[^>]*class=\"result__a\"[^>]*>(.*?)</a>.*?<a[^>]*class=\"result__snippet\"[^>]*>(.*?)</a>",options:[.dotMatchesLineSeparators,.caseInsensitive])
            let ns=html as NSString
            let matches=regex.matches(in:html,range:NSRange(location:0,length:ns.length))
            let snippets=matches.prefix(5).compactMap { m -> String? in
                guard m.numberOfRanges > 2 else{return nil}
                return "\(stripHTML(ns.substring(with:m.range(at:1)))): \(stripHTML(ns.substring(with:m.range(at:2))))"
            }
            guard !snippets.isEmpty else{return nil}
            internetStatus="BEREIT"
            if localAI {
                return await askOllamaRaw("""
                Beantworte die Nutzerfrage ausschließlich anhand der folgenden aktuellen Suchtreffer.
                Antworte auf Deutsch, knapp und erwähne Unsicherheit, wenn die Treffer nicht eindeutig sind.
                Nutzerfrage: \(cmd)
                Suchtreffer:
                \(snippets.joined(separator:"\n"))
                """) ?? snippets.prefix(3).joined(separator:" ")
            }
            return snippets.prefix(3).joined(separator:" ")
        } catch { internetStatus="INTERNETFEHLER"; return nil }
    }

    private func openGeneralTarget(_ name:String) -> Bool {
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !clean.isEmpty else{return false}
        let lower=clean.lowercased()
        let home=FileManager.default.homeDirectoryForCurrentUser
        let known:[String:URL]=[
            "downloads":home.appendingPathComponent("Downloads"),
            "download":home.appendingPathComponent("Downloads"),
            "schreibtisch":home.appendingPathComponent("Desktop"),
            "desktop":home.appendingPathComponent("Desktop"),
            "dokumente":home.appendingPathComponent("Documents"),
            "dokument":home.appendingPathComponent("Documents"),
            "programme":URL(fileURLWithPath:"/Applications"),
            "applications":URL(fileURLWithPath:"/Applications")
        ]
        if let url=known[lower] {
            return NSWorkspace.shared.open(url)
        }

        let openApp=runProcess("/usr/bin/open",["-a",clean])
        if openApp == 0 { return true }

        if let result=runCapture("/usr/bin/mdfind",["kMDItemFSName == '*\(clean.replacingOccurrences(of:"'",with:""))*'cd"]),
           let first=result.split(separator:"\n").first,
           !first.isEmpty {
            return NSWorkspace.shared.open(URL(fileURLWithPath:String(first)))
        }
        return false
    }

    func execute(_ cmd:String) async {
        status="VERARBEITUNG"; cpuPulse=0.9
        defer { if !speaking { status=listening ? "HÖRT ZU":"BEREIT" }; cpuPulse=0.22 }
        if cmd.contains("geh in den entwicklermodus") || cmd.contains("gehe in den entwicklermodus") || cmd.contains("entwicklermodus aktivieren") {
            enterDeveloperMode()
            return
        }

        if developerMode && (cmd.contains("entwicklermodus beenden") || cmd.contains("entwicklermodus verlassen")) {
            leaveDeveloperMode()
            return
        }

        if awaitingDeveloperInstallConfirmation {
            if cmd == "ja" || cmd.contains("ja installieren") || cmd.contains("installieren") || cmd.contains("übernehmen") {
                installDeveloperCandidate()
                return
            }
            if cmd == "nein" || cmd.contains("nicht installieren") || cmd.contains("abbrechen") {
                awaitingDeveloperInstallConfirmation=false
                developmentStatus="ENTWICKLUNG BEREIT"
                speak("In Ordnung. Die geprüfte Entwicklung bleibt gespeichert und wird nicht installiert.")
                return
            }
        }

        if developerMode {
            await processDeveloperInstruction(cmd)
            return
        }
        if cmd.hasPrefix("mein ort ist ") || cmd.hasPrefix("mein standort ist ") {
            let location=cmd.replacingOccurrences(of:"mein ort ist ",with:"").replacingOccurrences(of:"mein standort ist ",with:"")
            setDefaultLocation(location)
            speak("Ich verwende \(defaultLocation) künftig als deinen Standardort für Wetterabfragen.")
            return
        }
        if cmd.hasPrefix("merke dir ") || cmd.hasPrefix("merk dir ") || cmd.hasPrefix("lerne ") {
            let text=cmd
                .replacingOccurrences(of:"merke dir ",with:"")
                .replacingOccurrences(of:"merk dir ",with:"")
                .replacingOccurrences(of:"lerne ",with:"")
                .trimmingCharacters(in:.whitespacesAndNewlines)
            if !text.isEmpty {
                remember(text)
                speak("Das habe ich gespeichert.")
                return
            }
        }
        if cmd == "was hast du gelernt" || cmd.contains("was weißt du über mich") {
            if memory.isEmpty {
                speak("Mein lokales Gedächtnis ist noch leer.")
            } else {
                speak("Ich habe aktuell \(memory.count) gespeicherte Informationen.")
            }
            return
        }
        if cmd.contains("entwickle dich weiter") || cmd.contains("selbstentwicklung starten") {
            speak("Ich starte einen Entwicklungszyklus und prüfe den Kandidaten lokal.")
            await runSelfDevelopmentCycle()
            speak(candidateReady ? "Ein geprüfter Entwicklungskandidat ist bereit." : "Der Kandidat hat meine Prüfung nicht bestanden und wurde verworfen.")
            return
        }
        if cmd.contains("öffne safari") { await openBundle("com.apple.Safari","Safari"); return }
        if cmd.contains("öffne finder") { await openBundle("com.apple.finder","Finder"); return }
        if cmd.contains("öffne mail") { await openBundle("com.apple.mail","Mail"); return }
        if cmd.contains("öffne kalender") { await openBundle("com.apple.iCal","Kalender"); return }
        if cmd.contains("öffne notizen") { await openBundle("com.apple.Notes","Notizen"); return }
        if cmd.contains("öffne systemeinstellungen") || cmd.contains("öffne einstellungen") { await openBundle("com.apple.systempreferences","Systemeinstellungen"); return }
        if cmd.contains("öffne rechner") || cmd.contains("öffne taschenrechner") { await openBundle("com.apple.calculator","Rechner"); return }
        if cmd.hasPrefix("öffne ") || cmd.hasPrefix("starte ") {
            var target=cmd
            if target.hasPrefix("öffne ") { target=String(target.dropFirst(6)) }
            if target.hasPrefix("starte ") { target=String(target.dropFirst(7)) }
            if openGeneralTarget(target) {
                speak("\(target) wurde geöffnet.")
            } else {
                speak("Ich konnte \(target) auf diesem Mac nicht finden.")
            }
            return
        }
        if cmd.contains("mach einen screenshot") || cmd.contains("screenshot machen") {
            let f=DateFormatter(); f.dateFormat="yyyy-MM-dd_HH-mm-ss"
            let path=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Jarvis-Screenshot-\(f.string(from:Date())).png").path
            let code=runProcess("/usr/sbin/screencapture",["-x",path])
            speak(code == 0 ? "Screenshot wurde auf dem Schreibtisch gespeichert." : "Screenshot konnte ich nicht erstellen.")
            return
        }
        if cmd.contains("ton an") || cmd.contains("nicht mehr stumm") || cmd.contains("unmute") {
            _=runProcess("/usr/bin/osascript",["-e","set volume output muted false"])
            speak("Ton ist wieder eingeschaltet."); return
        }
        if cmd.contains("stumm") || cmd.contains("mute") {
            _=runProcess("/usr/bin/osascript",["-e","set volume output muted true"])
            speak("Ton ist stummgeschaltet."); return
        }
        if cmd.contains("lautstärke") {
            let digits=cmd.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let n=digits.first {
                let value=max(0,min(100,n))
                _=runProcess("/usr/bin/osascript",["-e","set volume output volume \(value)"])
                speak("Lautstärke auf \(value) Prozent."); return
            }
        }
        if cmd.contains("update prüfen") || cmd.contains("prüfe update") || cmd.contains("nach update suchen") {
            await checkForUpdates()
            speak(updateAvailable ? "Version \(latestVersion) ist verfügbar." : "Jarvis ist auf dem aktuellen Stand.")
            return
        }
        if cmd.contains("was kannst du") {
            speak("Ich kann Programme öffnen, im Internet suchen, Uhrzeit und Datum nennen, Screenshots erstellen, Lautstärke steuern, Updates prüfen und mit der lokalen KI antworten.")
            return
        }
        if cmd.hasPrefix("suche ") || cmd.contains("suche im internet") || cmd.contains("google ") {
            let q=cmd.replacingOccurrences(of:"suche im internet nach",with:"").replacingOccurrences(of:"suche nach",with:"").replacingOccurrences(of:"suche",with:"").replacingOccurrences(of:"google",with:"").trimmingCharacters(in:.whitespaces)
            if let enc=q.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed), let u=URL(string:"https://www.google.com/search?q=\(enc)"){ NSWorkspace.shared.open(u); speak("Ich habe die Internetsuche nach \(q) geöffnet."); return }
        }
        if cmd.contains("wie spät") || cmd.contains("uhrzeit") { let f=DateFormatter(); f.timeStyle = .short; speak("Es ist \(f.string(from:Date())) Uhr."); return }
        if cmd.contains("welcher tag") || cmd.contains("datum") { let f=DateFormatter(); f.dateStyle = .full; f.locale=Locale(identifier:"de_DE"); speak("Heute ist \(f.string(from:Date()))."); return }
        let route=await decideRoute(cmd)
        lastRoute=route.rawValue
        switch route {
        case .weather:
            speak(await fetchWeather(cmd) ?? "Die Wetterabfrage ist gerade fehlgeschlagen.")
            return
        case .news:
            speak(await fetchNews(cmd) ?? "Ich konnte die aktuellen Nachrichten gerade nicht abrufen.")
            return
        case .web:
            speak(await fetchWebSearch(cmd) ?? "Die Internetsuche ist gerade fehlgeschlagen.")
            return
        case .localAI:
            if localAI, let answer=await askOllama(cmd) { speak(answer) }
            else { speak("Für diese Frage brauche ich meine lokale KI. Sobald Ollama eingerichtet ist, kann ich sie direkt beantworten.") }
            return
        case .memory, .mac:
            if localAI, let answer=await askOllama(cmd) { speak(answer) }
            else { speak("Dafür fehlt mir noch die lokale KI.") }
            return
        }
    }
    func askOllama(_ prompt:String) async -> String? {
        let memories = memoryContext()
        let context = recentContext.suffix(12).joined(separator:"\n")
        let fullPrompt = """
        Du bist Jarvis, ein deutschsprachiger persönlicher macOS-Assistent.
        Antworte ausschließlich auf Deutsch, natürlich, präzise und knapp.
        Nutze gespeicherte Informationen nur, wenn sie zur aktuellen Frage passen.
        Behaupte niemals, eine Mac-Aktion ausgeführt zu haben, wenn sie nicht tatsächlich ausgeführt wurde.

        Gespeichertes Gedächtnis:
        \(memories)

        Letzter Gesprächskontext:
        \(context)

        Nutzer: \(prompt)
        """
        guard let answer = await askOllamaRaw(fullPrompt) else { return nil }
        addContext("Nutzer", prompt)
        addContext("Jarvis", answer)
        return answer
    }

    private func askOllamaRaw(_ prompt:String) async -> String? {
        guard let u=URL(string:"http://127.0.0.1:11434/api/generate") else{return nil}
        let model = localAIModel == "NICHT VERBUNDEN" || localAIModel == "KEIN MODELL" ? "qwen2.5:3b" : localAIModel
        let body:[String:Any] = ["model":model,"prompt":prompt,"stream":false]
        guard let data=try? JSONSerialization.data(withJSONObject:body) else{return nil}
        var r=URLRequest(url:u)
        r.httpMethod="POST"
        r.httpBody=data
        r.timeoutInterval=120
        r.setValue("application/json",forHTTPHeaderField:"Content-Type")
        do {
            let (d,response)=try await URLSession.shared.data(for:r)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else{return nil}
            let o=try JSONSerialization.jsonObject(with:d) as? [String:Any]
            return (o?["response"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}


struct ArcRing: View {
    let radius: CGFloat
    let speed: Double
    let reverse: Bool
    let active: Bool
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            let rotation = timeline.date.timeIntervalSinceReferenceDate * speed * (reverse ? -1 : 1)
            Circle()
                .trim(from: 0.03, to: 0.76)
                .stroke(
                    Color.cyan.opacity(active ? 0.98 : 0.42),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [3, 8])
                )
                .frame(width: radius, height: radius)
                .rotationEffect(.degrees(rotation))
                .shadow(color: .cyan.opacity(active ? 0.85 : 0.35), radius: active ? 18 : 7)
        }
    }
}

struct ScanBeam: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.0) / 4.0
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .cyan.opacity(0.05), .cyan.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 90)
                    .offset(y: (geo.size.height + 90) * t - 90)
                    .blur(radius: 3)
            }
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

struct CornerFrame: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: 28)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 28, y: 0))
                p.move(to: CGPoint(x: w - 28, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: 28))
                p.move(to: CGPoint(x: 0, y: h - 28)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 28, y: h))
                p.move(to: CGPoint(x: w - 28, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - 28))
            }
            .stroke(.cyan.opacity(0.55), lineWidth: 1.2)
        }
        .allowsHitTesting(false)
    }
}

struct HUDPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Rectangle().fill(.cyan).frame(width: 5, height: 5)
                    .shadow(color: .cyan, radius: 6)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(.cyan)
                Rectangle().fill(.cyan.opacity(0.25)).frame(height: 1)
            }
            content
        }
        .padding(13)
        .background(
            LinearGradient(
                colors: [.cyan.opacity(0.075), .black.opacity(0.30), .cyan.opacity(0.018)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.cyan.opacity(0.22), lineWidth: 1))
        .overlay(CornerFrame())
        .shadow(color: .cyan.opacity(0.09), radius: 14)
    }
}

struct MetricBar: View {
    let label: String
    let value: Double
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(text)
            }
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(.cyan.opacity(0.78))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.cyan.opacity(0.09))
                    Rectangle()
                        .fill(LinearGradient(colors: [.cyan.opacity(0.45), .cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * max(0, min(1, value)))
                        .shadow(color: .cyan.opacity(0.55), radius: 5)
                }
            }
            .frame(height: 3)
        }
    }
}

struct CoreOrb: View {
    let status: String
    let listening: Bool
    let processing: Bool
    let speaking: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let frequency = speaking ? 5.2 : (processing ? 3.2 : 1.8)
            let amplitude = speaking ? 0.075 : (processing ? 0.045 : 0.025)
            let pulse = 0.94 + (sin(t * frequency) + 1) * amplitude
            let glow = speaking ? 0.98 : (processing ? 0.82 : (listening ? 0.58 : 0.34))

            ZStack {
                Circle()
                    .stroke(.cyan.opacity(0.045), lineWidth: 24)
                    .frame(width: 410, height: 410)
                    .blur(radius: 9)
                    .scaleEffect(pulse)

                ArcRing(radius: 410, speed: speaking ? 16 : 7, reverse: false, active: processing || speaking, lineWidth: speaking ? 2.8 : 1.8)
                ArcRing(radius: 365, speed: speaking ? 24 : 12, reverse: true, active: listening || speaking, lineWidth: speaking ? 2.1 : 1.4)
                ArcRing(radius: 320, speed: speaking ? 31 : 19, reverse: false, active: processing || speaking, lineWidth: speaking ? 1.8 : 1.1)
                ArcRing(radius: 278, speed: speaking ? 11 : 5, reverse: true, active: speaking, lineWidth: 1.0)

                Circle().stroke(.cyan.opacity(0.08), lineWidth: 1).frame(width: 270, height: 270)
                Circle().stroke(.cyan.opacity(0.18), lineWidth: 1).frame(width: 238, height: 238)

                ForEach(0..<24, id: \.self) { i in
                    Capsule()
                        .fill(.cyan.opacity(i.isMultiple(of: 3) ? 0.9 : 0.22))
                        .frame(width: i.isMultiple(of: 3) ? 3 : 1.5, height: i.isMultiple(of: 3) ? 18 : 11)
                        .offset(y: -151)
                        .rotationEffect(.degrees(Double(i) * 15 + t * (speaking ? 11 : 3)))
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(speaking ? 0.72 : (processing ? 0.45 : 0.20)),
                                .cyan.opacity(speaking ? 0.72 : (processing ? 0.42 : 0.24)),
                                .cyan.opacity(speaking ? 0.20 : 0.06),
                                .clear
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 125
                        )
                    )
                    .frame(width: 235, height: 235)
                    .scaleEffect(pulse)
                    .shadow(color: .cyan.opacity(glow), radius: speaking ? 46 : (processing ? 32 : 18))

                Circle()
                    .stroke(.white.opacity(speaking ? 0.28 : 0.08), lineWidth: speaking ? 2 : 1)
                    .frame(width: speaking ? 178 : 165, height: speaking ? 178 : 165)
                    .scaleEffect(pulse)

                VStack(spacing: 8) {
                    Text("JARVIS")
                        .font(.system(size: 38, weight: .ultraLight, design: .rounded))
                        .tracking(8)
                    Text(status)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(3)

                    HStack(spacing: 3) {
                        ForEach(0..<18, id: \.self) { i in
                            let phase = sin(t * (speaking ? 8 : 2) + Double(i) * 0.7)
                            Capsule()
                                .fill(.cyan.opacity(speaking ? 0.95 : (i.isMultiple(of: 3) ? 0.85 : 0.30)))
                                .frame(width: 3, height: speaking ? CGFloat(9 + abs(phase) * 20) : CGFloat(6 + (i % 5) * 3))
                        }
                    }
                    .frame(height: 30)
                }
                .foregroundStyle(.cyan)
            }
        }
    }
}

struct JarvisView: View {
    @StateObject var core = JarvisCore()
    @State var input = ""
    @State var now = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.002, green: 0.010, blue: 0.018),
                    Color(red: 0.003, green: 0.045, blue: 0.070),
                    Color(red: 0.001, green: 0.012, blue: 0.020),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Canvas { context, size in
                let step: CGFloat = 40
                for x in stride(from: 0, through: size.width, by: step) {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(p, with: .color(.cyan.opacity(0.035)), lineWidth: 0.5)
                }
                for y in stride(from: 0, through: size.height, by: step) {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(p, with: .color(.cyan.opacity(0.035)), lineWidth: 0.5)
                }
                var diagonal = Path()
                diagonal.move(to: CGPoint(x: size.width * 0.23, y: 0))
                diagonal.addLine(to: CGPoint(x: size.width * 0.05, y: size.height))
                context.stroke(diagonal, with: .color(.cyan.opacity(0.055)), lineWidth: 1)
                diagonal = Path()
                diagonal.move(to: CGPoint(x: size.width * 0.78, y: 0))
                diagonal.addLine(to: CGPoint(x: size.width * 0.96, y: size.height))
                context.stroke(diagonal, with: .color(.cyan.opacity(0.055)), lineWidth: 1)
            }
            .ignoresSafeArea()

            ScanBeam().opacity(core.speaking ? 0.95 : (core.listening ? 0.75 : 0.34))

            VStack(spacing: 10) {
                header

                HStack(alignment: .top, spacing: 12) {
                    leftColumn
                    centerColumn
                    rightColumn
                }
                .padding(.horizontal, 18)

                commandBar
                footer
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(timer) { now = $0 }
        .task { await core.boot() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text("J.A.R.V.I.S.")
                        .font(.system(size: 25, weight: .ultraLight, design: .rounded))
                        .tracking(8)
                    Text("MARK V")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.cyan.opacity(0.10))
                        .overlay(Rectangle().stroke(.cyan.opacity(0.35)))
                }
                Text("HOLOGRAFISCHE NEURALE STEUERUNG // ADAPTIVE LOKALE INTELLIGENZ")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.cyan.opacity(0.58))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(now.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                Text("SICHERE LOKALE SITZUNG // KEINE API-KOSTEN")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.cyan.opacity(0.46))
            }
            Text("● \(core.status)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(core.listening ? .green : .cyan)
                .shadow(color: core.listening ? .green.opacity(0.6) : .cyan.opacity(0.6), radius: 6)
        }
        .foregroundStyle(.cyan)
        .padding(.horizontal, 22)
        .padding(.top, 15)
    }

    private var leftColumn: some View {
        VStack(spacing: 11) {
            HUDPanel(title: "SYSTEMTELEMETRIE") {
                stat("SYSTEM", "BEREIT")
                stat("STIMME", core.speaking ? "SPRICHT" : (core.listening ? "AKTIV" : "BEREIT"))
                stat("LOKALE KI", core.localAI ? "VERBUNDEN" : "NICHT BEREIT")
                stat("KI-MODELL", core.localAIModel)
                stat("GEDÄCHTNIS", "\(core.memoryCount) EINTRÄGE")
                stat("ROUTER", core.lastRoute)
                stat("INTERNET", core.internetStatus)
                stat("CLAUDE CODE", core.claudeCodeStatus)
                stat("ENTWICKLERMODUS", core.developerMode ? "AKTIV" : "AUS")
                stat("ENTWICKLUNG", core.developmentStatus)
                stat("UPDATE", core.updateStatus)
                MetricBar(label: "SYSTEMLAST", value: core.cpuPulse, text: "\(Int(core.cpuPulse * 100))%")
                MetricBar(label: "SPRACHVERBINDUNG", value: core.speaking ? 1.0 : (core.listening ? 0.94 : 0.22), text: core.speaking ? "AUSGABE" : (core.listening ? "VERBUNDEN" : "RUHE"))
                MetricBar(label: "NETZWERK", value: 0.72, text: "BEREIT")
            }

            HUDPanel(title: "BEFEHLSZENTRALE") {
                quick("Safari", "com.apple.Safari", "safari")
                quick("Finder", "com.apple.finder", "folder")
                quick("Mail", "com.apple.mail", "envelope")
                quick("Kalender", "com.apple.iCal", "calendar")
                quick("Notizen", "com.apple.Notes", "note.text")
                quick("Einstellungen", "com.apple.systempreferences", "gearshape")
                quick("Rechner", "com.apple.calculator", "plus.forwardslash.minus")
            }

            Spacer(minLength: 0)
        }
        .frame(width: 255)
    }

    private var centerColumn: some View {
        VStack(spacing: 7) {
            Spacer(minLength: 4)
            ZStack {
                CoreOrb(status: core.status, listening: core.listening, processing: core.status == "VERARBEITUNG", speaking: core.speaking)
                VStack {
                    HStack {
                        tinyTag("STIMME", core.speaking ? "SPRICHT" : (core.listening ? "VERBUNDEN" : "WARTET"))
                        Spacer()
                        tinyTag("KI", core.localAI ? "LOKAL" : "NICHT BEREIT")
                    }
                    Spacer()
                    HStack {
                        tinyTag("UPDATE", core.updateStatus)
                        Spacer()
                        tinyTag("VERSION", "1.9.3")
                    }
                }
                .frame(width: 500, height: 405)
            }
            .frame(height: 425)

            Text(core.speaking ? "SPRACHAUSGABE // JARVIS SPRICHT" : (core.listening ? "WARTE AUF BEFEHL // SAGE „JARVIS …“" : "SPRACHSYSTEM STANDBY"))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(.cyan.opacity(0.82))

            Text(core.transcript.isEmpty ? "Audiosystem bereit. Aktivierungswort ist aktiv." : core.transcript)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 42)

            HUDPanel(title: "AKTIVE INTELLIGENZ") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(core.localAI ? "LOKALE KI VERBUNDEN" : "LOKALE KI NOCH NICHT EINGERICHTET")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                        Text(core.localAI ? core.localAIModel : "Mac-Steuerung funktioniert weiterhin ohne KI-Modell.")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Circle()
                            .fill(core.localAI ? .green : .cyan.opacity(0.45))
                            .frame(width: 8, height: 8)
                            .shadow(color: core.localAI ? .green : .cyan, radius: 7)
                        if !core.localAI {
                            Button(core.aiInstalling ? "KI WIRD EINGERICHTET …" : "KI EINRICHTEN") {
                                core.confirmAndSetupAI()
                            }
                            .buttonStyle(.bordered)
                            .tint(.cyan)
                            .disabled(core.aiInstalling)
                        }
                    }
                }
                Text(core.aiSetupStatus)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(core.localAI ? .green : .cyan.opacity(0.72))

                HStack {
                    Text("AUTOMATISCHE ENTSCHEIDUNG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.72))
                    Spacer()
                    Text(core.lastRoute)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                }

                HStack {
                    Text("ENTWICKLER-KI")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.72))
                    Spacer()
                    Text(core.claudeCodeAvailable ? "CLAUDE CODE" : "OLLAMA")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(core.claudeCodeAvailable ? .green : .cyan)
                }

                HStack {
                    Text("SELBSTENTWICKLUNG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.72))
                    Spacer()
                    Text(core.candidateReady ? "KANDIDAT GEPRÜFT" : core.developmentStatus)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(core.candidateReady ? .green : .cyan.opacity(0.72))
                }

                if core.candidateReady {
                    Button("ENTWICKLUNG INSTALLIEREN") {
                        core.installDeveloperCandidate()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }

                Button(core.developerMode ? "ENTWICKLERMODUS AKTIV" : "ENTWICKLERMODUS") {
                    core.developerMode ? core.leaveDeveloperMode() : core.enterDeveloperMode()
                }
                .buttonStyle(.bordered)
                .tint(core.developerMode ? .green : .cyan)

                Button("ENTWICKLUNGSZYKLUS STARTEN") {
                    Task { await core.runSelfDevelopmentCycle() }
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                .disabled(!core.localAI)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rightColumn: some View {
        VStack(spacing: 11) {
            HUDPanel(title: "LIVE-DATENSTROM") {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(core.logs.suffix(10)) { line in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(line.who)
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .tracking(1.2)
                                            .foregroundStyle(.cyan)
                                        Rectangle().fill(.cyan.opacity(0.18)).frame(height: 1)
                                    }
                                    Text(line.text)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.76))
                                }
                                .id(line.id)
                            }
                        }
                    }
                    .frame(height: 270)
                    .onChange(of: core.logs.count) { _, _ in
                        if let id = core.logs.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }

            HUDPanel(title: "SPRACHSYSTEM") {
                Toggle("Dauerhaft zuhören", isOn: $core.continuous)
                    .toggleStyle(.switch)
                    .tint(.cyan)
                    .onChange(of: core.continuous) { _, enabled in
                        enabled ? core.startListening() : core.stopListening()
                    }
                HStack {
                    Text("AKTIVIERUNGSWORT")
                    Spacer()
                    Text("JARVIS")
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.72))

                HStack {
                    Text("STIMMPROFIL")
                    Spacer()
                    Text(core.voiceLabel)
                        .lineLimit(1)
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.72))
            }

            HUDPanel(title: "UPDATE-ZENTRALE") {
                HStack {
                    Circle().fill(.green).frame(width: 6, height: 6).shadow(color: .green, radius: 5)
                    Text("GITHUB-KANAL // VERBUNDEN")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(.green)
                }
                Text(core.updateAvailable ? "Version \(core.latestVersion) verfügbar" : core.updateStatus)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan)
                if core.updateAvailable {
                    Button("UPDATE INSTALLIEREN") {
                        core.confirmAndInstallUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                    Button("ERNEUT NACH UPDATE SUCHEN") {
                        Task { await core.checkForUpdates() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                } else {
                    Button("NACH UPDATE SUCHEN") {
                        Task { await core.checkForUpdates() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 315)
    }

    private var commandBar: some View {
        HStack(spacing: 10) {
            Text("›")
                .font(.system(size: 22, weight: .thin, design: .monospaced))
                .foregroundStyle(.cyan)
                .shadow(color: .cyan, radius: 6)
            TextField("BEFEHL EINGEBEN // Mit Jarvis schreiben …", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit { send() }
                .padding(.vertical, 11)
            Button("AUSFÜHREN") { send() }
                .buttonStyle(.borderedProminent)
                .tint(.cyan.opacity(0.50))
        }
        .padding(.horizontal, 14)
        .background(.black.opacity(0.42))
        .overlay(Rectangle().stroke(.cyan.opacity(0.28), lineWidth: 1))
        .padding(.horizontal, 18)
    }

    private var footer: some View {
        HStack {
            Text("JARVIS // MARK V // VERSION 1.9.3")
            Spacer()
            Text("SPRACHSTEUERUNG • OLLAMA • CLAUDE CODE • INTERNET • GEDÄCHTNIS • ENTWICKLERMODUS")
        }
        .font(.system(size: 7, weight: .semibold, design: .monospaced))
        .tracking(1.8)
        .foregroundStyle(.cyan.opacity(0.48))
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }

    func stat(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.46))
            Spacer()
            Text(b)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
                .lineLimit(1)
        }
    }

    func quick(_ label: String, _ id: String, _ icon: String) -> some View {
        Button {
            Task { await core.openBundle(id, label) }
        } label: {
            HStack {
                Image(systemName: icon).frame(width: 15)
                Text(label)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.cyan.opacity(0.88))
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    func tinyTag(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.48))
            Text(value)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
                .lineLimit(1)
        }
        .padding(7)
        .background(.black.opacity(0.42))
        .overlay(Rectangle().stroke(.cyan.opacity(0.22)))
    }

    func send() {
        let text = input
        input = ""
        core.submit(text)
    }
}

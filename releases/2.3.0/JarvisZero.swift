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
    @Published var developmentProgress:Double = 0.0
    @Published var developmentProgressText = "BEREIT"
    @Published var internetStatus = "BEREIT"
    @Published var claudeCodeStatus = "PRÜFUNG AUSSTEHEND"
    @Published var claudeCodeAvailable = false
    @Published var lastRoute = "LOKAL"
    @Published var defaultLocation = UserDefaults.standard.string(forKey:"JarvisDefaultLocation") ?? ""
    @Published var cpuPulse:Double = 0.22
    @Published var updateAvailable = false
    @Published var latestVersion = "2.3.0"
    @Published var updateStatus = "AKTUELL"
    @Published var updateNotes:[String] = []
    private var pendingPackageURL:String?
    private var pendingSHA256:String?
    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "2.3.0"
    }
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
    private static let selfSourceURL = "https://raw.githubusercontent.com/Jarvis291-source/Jarvis-Mark-III/main/releases/2.3.0/JarvisZero.swift"

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

    private var activeProjectDirectory: URL {
        developmentDirectory.appendingPathComponent("AktivesProjekt", isDirectory:true)
    }

    private var claudeProjectWorkspace: URL {
        developmentDirectory.appendingPathComponent("Claude-Projekt", isDirectory:true)
    }

    private func swiftFiles(in root:URL) -> [URL] {
        guard let e=FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil) else{return []}
        var out:[URL]=[]
        for case let u as URL in e {
            if u.pathExtension.lowercased()=="swift" { out.append(u) }
        }
        return out.sorted { $0.path < $1.path }
    }

    private func seedDeveloperProject(from source:String) throws {
        let fm=FileManager.default
        let versionFile=activeProjectDirectory.appendingPathComponent("JARVIS_VERSION.txt")
        let projectVersion=(try? String(contentsOf:versionFile,encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines)
        if fm.fileExists(atPath:activeProjectDirectory.path),
           !swiftFiles(in:activeProjectDirectory).isEmpty,
           projectVersion == Self.currentVersion { return }

        // Ein Projekt einer abgestürzten/älteren Claude-Version niemals erneut als Basis verwenden.
        try? fm.removeItem(at:activeProjectDirectory)
        let sources=activeProjectDirectory.appendingPathComponent("Sources",isDirectory:true)
        let coreDir=sources.appendingPathComponent("Core",isDirectory:true)
        let uiDir=sources.appendingPathComponent("UI",isDirectory:true)
        try fm.createDirectory(at:coreDir,withIntermediateDirectories:true)
        try fm.createDirectory(at:uiDir,withIntermediateDirectories:true)

        // Ab 2.3.0 wird der stabile Monolith VOR Claude in Kern und UI getrennt.
        // Dadurch muss Claude bei großen Designaufträgen nicht mehr die gesamte Jarvis-Datei umstrukturieren.
        let splitMarker="\n\nstruct ArcRing: View {"
        if let markerRange=source.range(of:splitMarker) {
            let coreSource=String(source[..<markerRange.lowerBound]).trimmingCharacters(in:.whitespacesAndNewlines)+"\n"
            let uiBody=String(source[markerRange.lowerBound...]).trimmingCharacters(in:.whitespacesAndNewlines)
            let uiSource="""
            import SwiftUI
            import AppKit
            import Foundation
            import Combine

            \(uiBody)
            """
            try coreSource.write(to:coreDir.appendingPathComponent("JarvisCore.swift"),atomically:true,encoding:.utf8)
            try uiSource.write(to:uiDir.appendingPathComponent("JarvisHUD.swift"),atomically:true,encoding:.utf8)
        } else {
            // Sicherer Fallback, falls sich die Quellstruktur später ändert.
            try source.write(to:coreDir.appendingPathComponent("JarvisZero.swift"),atomically:true,encoding:.utf8)
        }

        let guide="""
        # JARVIS Entwicklerprojekt

        ## Architektur
        - Sources/Core enthält die stabile Kernlogik: Sprache, Routing, Claude Code, Ollama, Gedächtnis, Updates, Installation und Rollback.
        - Sources/UI/JarvisHUD.swift enthält die SwiftUI-Oberfläche und ist bei Designaufträgen der primäre Arbeitsbereich.
        - Alle Swift-Dateien unter Sources werden vom Host gemeinsam kompiliert.

        ## Regeln für Designaufträge
        1. Lies zuerst Sources/UI/JarvisHUD.swift vollständig.
        2. Ändere bei einem Designauftrag die UI tatsächlich und substanziell.
        3. Reine Text-, Überschrift- oder Farbänderungen gelten nicht als fertiger Designauftrag.
        4. Kernlogik in Sources/Core nur ändern, wenn die gewünschte UI-Funktion es zwingend benötigt.
        5. Du darfst zusätzliche SwiftUI-Dateien unter Sources/UI anlegen.
        6. Keine externen Pakete oder Abhängigkeiten hinzufügen.
        7. Keine vorhandenen Funktionen für Sprache, Claude, Updates, lokale KI, Gedächtnis, Installation oder Rollback entfernen.
        """
        try guide.write(to:activeProjectDirectory.appendingPathComponent("CLAUDE.md"),atomically:true,encoding:.utf8)
        try Self.currentVersion.write(to:versionFile,atomically:true,encoding:.utf8)
    }

    private func cloneDirectory(from src:URL,to dst:URL) throws {
        let fm=FileManager.default
        try? fm.removeItem(at:dst)
        try fm.copyItem(at:src,to:dst)
    }

    private var developerCandidateAppURL: URL {
        developmentDirectory.appendingPathComponent("Jarvis-Entwicklungskandidat.app", isDirectory:true)
    }

    private func loadDevelopmentSource() async -> String? {
        let versionFile=activeProjectDirectory.appendingPathComponent("JARVIS_VERSION.txt")
        let projectVersion=(try? String(contentsOf:versionFile,encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines)
        if projectVersion == Self.currentVersion,
           let first=swiftFiles(in:activeProjectDirectory).first,
           let local=try? String(contentsOf:first,encoding:.utf8),
           !local.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            return local
        }

        // Bei Versionsabweichung bewusst den veröffentlichten stabilen Quellstand laden.
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
            speak("Der Entwicklermodus braucht eine aktive Claude Code Anmeldung. Claude Code ist entweder nicht erreichbar oder nicht angemeldet.")
            return
        }
        developerMode=true
        awaitingDeveloperInstallConfirmation=false
        developmentProgress=0.0
        developmentProgressText="BEREIT"
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
    private func projectFingerprint(_ root:URL) -> String {
        swiftFiles(in:root).map { file in
            let relative=file.path.replacingOccurrences(of:root.path,with:"")
            let data=(try? Data(contentsOf:file)) ?? Data()
            return "\(relative)|\(data.count)|\(data.hashValue)"
        }.joined(separator:"\n")
    }

    private func uiProjectFingerprint(_ root:URL) -> String {
        swiftFiles(in:root)
            .filter { $0.path.contains("/Sources/UI/") }
            .map { file in
                let relative=file.path.replacingOccurrences(of:root.path,with:"")
                let data=(try? Data(contentsOf:file)) ?? Data()
                return "\(relative)|\(data.count)|\(data.hashValue)"
            }
            .joined(separator:"\n")
    }

    private func nextDeveloperVersion() -> String {
        let current=Self.currentVersion
        var parts=current.split(separator:".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        if parts.count > 3 { parts=Array(parts.prefix(3)) }
        parts[2] += 1
        return parts.map(String.init).joined(separator:".")
    }

    private func writeCandidateInfoPlist(version:String,to destination:URL) throws {
        let source=Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        let data=try Data(contentsOf:source)
        guard var plist=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any] else {
            throw NSError(domain:"JarvisDeveloper",code:41)
        }
        plist["CFBundleShortVersionString"]=version
        plist["CFBundleVersion"]=String(Int(Date().timeIntervalSince1970))
        let output=try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0)
        try output.write(to:destination,options:.atomic)
    }

    private func runProcessCaptured(_ executable:String,_ args:[String],logURL:URL) -> (Int32,String) {
        let fm=FileManager.default
        try? fm.removeItem(at:logURL)
        fm.createFile(atPath:logURL.path,contents:nil)
        guard let handle=try? FileHandle(forWritingTo:logURL) else { return (-1,"Protokolldatei konnte nicht geöffnet werden.") }
        defer { try? handle.close() }
        let p=Process()
        p.executableURL=URL(fileURLWithPath:executable)
        p.arguments=args
        p.standardOutput=handle
        p.standardError=handle
        do {
            try p.run()
            p.waitUntilExit()
            try? handle.synchronize()
            let text=(try? String(contentsOf:logURL,encoding:.utf8)) ?? ""
            return (p.terminationStatus,text)
        } catch {
            return (-1,error.localizedDescription)
        }
    }

    private func runClaudePass(prompt:String,workspace:URL,label:String,timeout:TimeInterval=1200) async -> Int32 {
        guard let claude=findClaudeBinary() else {
            claudeCodeAvailable=false
            claudeCodeStatus="NICHT GEFUNDEN"
            return -1
        }

        let fm=FileManager.default
        let outURL=developmentDirectory.appendingPathComponent("Letzter-Claude-Bericht.txt")
        let errURL=developmentDirectory.appendingPathComponent("Letzter-Claude-Fehler.txt")
        try? fm.removeItem(at:outURL)
        try? fm.removeItem(at:errURL)
        fm.createFile(atPath:outURL.path,contents:nil)
        fm.createFile(atPath:errURL.path,contents:nil)
        guard let outHandle=try? FileHandle(forWritingTo:outURL),
              let errHandle=try? FileHandle(forWritingTo:errURL) else { return -1 }

        claudeCodeStatus=label
        let status:Int32 = await Task.detached(priority:.userInitiated) {
            defer {
                try? outHandle.close()
                try? errHandle.close()
            }
            let p=Process()
            p.executableURL=URL(fileURLWithPath:claude)
            p.currentDirectoryURL=workspace
            p.arguments=[
                "-p",prompt,
                "--effort","high",
                "--permission-mode","acceptEdits",
                "--tools","Read,Edit,Write,Glob,Grep",
                "--verbose"
            ]
            var env=ProcessInfo.processInfo.environment
            env["HOME"]=FileManager.default.homeDirectoryForCurrentUser.path
            let localBin=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
            env["PATH"]="\(localBin):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            p.environment=env
            p.standardOutput=outHandle
            p.standardError=errHandle
            do {
                try p.run()
                let started=Date()
                while p.isRunning && Date().timeIntervalSince(started) < timeout {
                    Thread.sleep(forTimeInterval:0.25)
                }
                if p.isRunning {
                    p.interrupt()
                    Thread.sleep(forTimeInterval:1.0)
                    if p.isRunning { p.terminate() }
                }
                p.waitUntilExit()
                return p.terminationStatus
            } catch {
                return -1
            }
        }.value
        return status
    }

    private func runClaudeWorkspaceEdit(instruction:String, source:String) async -> URL? {
        guard findClaudeBinary() != nil else {
            claudeCodeAvailable=false
            claudeCodeStatus="NICHT GEFUNDEN"
            return nil
        }

        let fm=FileManager.default
        do {
            try seedDeveloperProject(from:source)
            try cloneDirectory(from:activeProjectDirectory,to:claudeProjectWorkspace)
            let original=projectFingerprint(claudeProjectWorkspace)
            let originalUI=uiProjectFingerprint(claudeProjectWorkspace)

            let lowerInstruction=instruction.lowercased()
            let voiceFocused = lowerInstruction.contains("stimm") || lowerInstruction.contains("voice") || lowerInstruction.contains("jarvis aus") || lowerInstruction.contains("iron man")
            let designFocused = lowerInstruction.contains("design") || lowerInstruction.contains("benutzeroberfläche") || lowerInstruction.contains("oberfläche") || lowerInstruction.contains("swiftui") || lowerInstruction.contains("hud") || lowerInstruction.contains("partikel") || lowerInstruction.contains("kugel") || lowerInstruction.contains("core")
            let designRules = designFocused ? """
            
            BESONDERE REGELN FÜR EINEN GROSSEN UI-/DESIGNAUFTRAG:
            - Behandle den Auftrag als echten SwiftUI-Umbau, nicht als Textänderung oder Beschreibung.
            - Beginne in Sources/UI/JarvisHUD.swift. Diese Datei ist absichtlich vom stabilen JarvisCore getrennt und ist dein primärer Arbeitsbereich.
            - Lies JarvisView, CoreOrb, HUDPanel und die zugehörigen UI-Helfer vollständig, bevor du das Design umbaust.
            - Die funktionierende JarvisCore-Logik für Sprache, Claude Code, Updates, lokale KI, Gedächtnis und Installation muss erhalten bleiben.
            - Du darfst die UI in mehrere Swift-Dateien unter Sources/UI aufteilen. Wenn du Typen verschiebst, entferne die alten Definitionen vollständig, damit keine doppelten Symbole entstehen.
            - Mindestens JarvisView oder die von JarvisView verwendeten UI-Komponenten müssen sich bei einem Designauftrag substanziell ändern. Eine reine Überschrift-, Farb- oder Textänderung reicht nicht.
            - Für Animationen bevorzugst du SwiftUI TimelineView, Canvas, Shape und leichte GPU-freundliche Effekte. Keine externe Bibliothek und kein Metal-Paket hinzufügen.
            - Alle Bedienelemente für Entwicklermodus, Update, Texteingabe und vorhandene Statusinformationen müssen weiterhin erreichbar bleiben.
            - Keine erfolgreiche Smartphone-Kopplung vortäuschen. Eine Pairing-Ansicht darf als UI vorbereitet werden, echte Autorisierung erst mit echter Gegenstelle.
            - Ziel ist ein kompilierbarer macOS-SwiftUI-Projektstand, nicht ein Mockup und nicht nur eine Erklärung.
            """ : ""

            let voiceRules = voiceFocused ? """
            
            BESONDERE REGELN FÜR DIESEN STIMMAUFTRAG:
            - Der Auftrag betrifft primär die AUSGABESTIMME. Verändere nicht unnötig die bestehende Mikrofon- und SFSpeechRecognition-Architektur.
            - Bevorzuge für die Sprachausgabe AVSpeechSynthesizer, eine passende installierte männliche Stimme sowie rate, pitchMultiplier, volume und saubere Sprechpausen.
            - Erzeuge eine eigenständige, tiefe, ruhige, elegante, futuristische KI-Stimme; keine exakte Imitation einer realen Schauspielerstimme.
            - Baue KEINE neue AVAudioEngine-Ausgabe-Graphkette nur für Pitch/Effekt ein, wenn dieselbe Wirkung stabil über AVSpeechSynthesizer erreichbar ist.
            - Wenn du eine neue Voice-Klasse erstellst, entferne oder migriere ALLE alten Verweise vollständig.
            - Bestehende Spracherkennung, Entwicklermodus, Updatefunktion und Installationsbestätigung müssen erhalten bleiben.
            """ : ""

            let basePrompt = """
            Du arbeitest direkt am vollständigen Jarvis-Projekt im aktuellen Arbeitsordner.

            AUFTRAG DES BENUTZERS:
            \(instruction)
            \(voiceRules)
            \(designRules)

            ÄNDERE DIE DATEIEN TATSÄCHLICH:
            - Verwende Read/Edit/Write und bearbeite den Projektstand direkt.
            - Antworte nicht nur mit einer Beschreibung oder einem Codeblock.
            - Du darfst Swift-Dateien erstellen, löschen, aufteilen und ersetzen.
            - Mindestens eine kompilierbare Swift-Datei mit macOS-App-Einstiegspunkt muss erhalten bleiben.
            - Alle Swift-Dateien werden danach mit SwiftUI, AppKit, AVFoundation und Speech kompiliert.
            - Sprachsteuerung und zukünftige Entwicklung müssen erhalten bleiben.
            - Keine Zugangsdaten einbauen und keine macOS-Sicherheitsmechanismen umgehen.
            - Installiere die App nicht selbst; Build, Signatur und Installation übernimmt Jarvis.
            """

            let before=projectFingerprint(claudeProjectWorkspace)
            let status=await runClaudePass(
                prompt:basePrompt,
                workspace:claudeProjectWorkspace,
                label:"CLAUDE PROGRAMMIERT 1/1",
                timeout:1200
            )
            let after=projectFingerprint(claudeProjectWorkspace)
            let files=swiftFiles(in:claudeProjectWorkspace)

            if !files.isEmpty, before != after, original != after {
                if designFocused {
                    let changedUI=uiProjectFingerprint(claudeProjectWorkspace)
                    guard changedUI != originalUI else {
                        let report=(try? String(contentsOf:developmentDirectory.appendingPathComponent("Letzter-Claude-Bericht.txt"),encoding:.utf8)) ?? ""
                        let error=(try? String(contentsOf:developmentDirectory.appendingPathComponent("Letzter-Claude-Fehler.txt"),encoding:.utf8)) ?? ""
                        let diagnostic="CLAUDE-LAUF BEENDET, ABER OHNE UI-ÄNDERUNG. KEIN AUTOMATISCHER ZWEITVERSUCH.\\n\\nBERICHT:\\n\\(report)\\n\\nFEHLER:\\n\\(error)"
                        try? diagnostic.write(to:developmentDirectory.appendingPathComponent("Claude-Diagnose.txt"),atomically:true,encoding:.utf8)
                        claudeCodeStatus="KEINE UI-ÄNDERUNG // 1/1"
                        return nil
                    }
                }

                claudeCodeAvailable=true
                claudeCodeStatus=status == 0 ? "PROJEKT GEÄNDERT // 1/1" : "PROJEKT GEÄNDERT / CLAUDE ENDE \\(status)"
                return claudeProjectWorkspace
            }

            let report=(try? String(contentsOf:developmentDirectory.appendingPathComponent("Letzter-Claude-Bericht.txt"),encoding:.utf8)) ?? ""
            let error=(try? String(contentsOf:developmentDirectory.appendingPathComponent("Letzter-Claude-Fehler.txt"),encoding:.utf8)) ?? ""
            let combined=(report+"\\n"+error).lowercased()
            let limitDetected=combined.contains("session limit") || combined.contains("usage limit") || combined.contains("rate limit")
            let executionError=combined.contains("execution error")
            let headline = limitDetected ? "CLAUDE-LIMIT ERREICHT" : (executionError ? "CLAUDE EXECUTION ERROR" : "CLAUDE HAT KEINE DATEIÄNDERUNG ERZEUGT")
            let diagnostic="\\(headline). ES WURDE BEWUSST KEIN AUTOMATISCHER ZWEITVERSUCH GESTARTET.\\n\\nBERICHT:\\n\\(report)\\n\\nFEHLER:\\n\\(error)"
            try? diagnostic.write(to:developmentDirectory.appendingPathComponent("Claude-Diagnose.txt"),atomically:true,encoding:.utf8)
            claudeCodeStatus=limitDetected ? "LIMIT ERREICHT // STOPP" : (executionError ? "EXECUTION ERROR // STOPP" : "KEINE ÄNDERUNG // 1/1")
            return nil
        } catch {
            let message="PROJEKTFEHLER: \(error.localizedDescription)"
            try? message.write(to:developmentDirectory.appendingPathComponent("Claude-Diagnose.txt"),atomically:true,encoding:.utf8)
            claudeCodeStatus=message
            return nil
        }
    }

    private func repairClaudeProject(_ project:URL,buildError:String,attempt:Int) async -> Bool {
        let original=projectFingerprint(project)
        let clipped=String(buildError.suffix(24000))
        let prompt="""
        Der Jarvis-Projektstand wurde vom echten Swift-Compiler abgelehnt.
        Reparaturdurchlauf \(attempt) von maximal 6.

        COMPILERFEHLER:
        \(clipped)

        Repariere den GESAMTEN Projektstand direkt im aktuellen Arbeitsordner.
        WICHTIG:
        - Lies zuerst alle Swift-Dateien, die an den gemeldeten Symbolen beteiligt sind.
        - Wenn Code in eine neue Datei/Klasse ausgelagert wurde, entferne oder migriere die alte Implementierung vollständig.
        - Keine verwaisten Verweise auf engine, recognizer, task, request, synth oder alte Voice-Methoden zurücklassen.
        - Keine parallele alte und neue Spracharchitektur im selben Controller stehen lassen.
        - Der Benutzerauftrag darf nicht zurückgenommen werden.
        - Verwende nur SwiftUI, AppKit, AVFoundation, Speech und Foundation.
        - Bei reinen Stimmänderungen AVSpeechSynthesizer bevorzugen; keine unnötige AVAudioEngine-Effektkette erzeugen.
        - Ein Audiofehler darf niemals absichtlich abort()/SIGABRT auslösen.
        - Installiere nichts und ersetze die laufende App nicht.
        - Bearbeite die Dateien tatsächlich. Beende erst, wenn alle im Compilerbericht zusammenhängenden Fehler behoben sind.
        """
        _=await runClaudePass(prompt:prompt,workspace:project,label:"CLAUDE REPARIERT BUILD",timeout:1200)
        if !swiftFiles(in:project).isEmpty && projectFingerprint(project) != original { return true }

        // Ein einmaliger frischer Reparaturpass fängt abgebrochene Claude-Streams ab.
        let retryPrompt="""
        Der vorherige automatische Reparaturpass hat keine verwertbare Dateiänderung hinterlassen.
        Arbeite jetzt ausschließlich als Swift-Build-Reparaturagent.
        Lies die betroffenen Swift-Dateien und behebe diese Compilerfehler vollständig:
        \(clipped)
        Keine Erklärungen statt Dateiänderungen. Keine Installation. Bestehenden Benutzerauftrag erhalten.
        """
        _=await runClaudePass(prompt:retryPrompt,workspace:project,label:"CLAUDE REPARATUR WIEDERHOLUNG",timeout:1200)
        return !swiftFiles(in:project).isEmpty && projectFingerprint(project) != original
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
        developmentProgress=0.08
        developmentProgressText="PROJEKT VORBEREITEN"
        developmentStatus="PROJEKT VORBEREITEN"

        guard let source=await loadDevelopmentSource() else {
            developmentProgress=0
            developmentProgressText="QUELLCODEFEHLER"
            developmentStatus="QUELLCODEFEHLER"
            speak("Ich konnte meine aktuelle Codebasis nicht vorbereiten.")
            return
        }

        speak("Verstanden. Claude Code bearbeitet jetzt genau diesen Entwicklungsabschnitt in einem einzigen Durchlauf. Danach prüfe ich den Build lokal.")
        developmentProgress=0.20
        developmentProgressText="CLAUDE PROGRAMMIERT"
        developmentStatus="CLAUDE PROGRAMMIERT"

        guard let project=await runClaudeWorkspaceEdit(instruction:clean,source:source) else {
            developmentProgress=0
            developmentProgressText="CLAUDE HAT NICHTS GEÄNDERT"
            developmentStatus="CLAUDE CODE FEHLER"
            speak("Claude Code hat in diesem einen Durchlauf keinen verwertbaren Projektstand erzeugt. Ich starte bewusst keinen zweiten Versuch. Die laufende Version bleibt unverändert und die Diagnose wurde gespeichert.")
            return
        }

        let fm=FileManager.default
        let newVersion=nextDeveloperVersion()
        let buildLog=developmentDirectory.appendingPathComponent("Letzter-Build-Fehler.txt")
        var compileSucceeded=false

        do {
            try? fm.removeItem(at:developerCandidateAppURL)
            let macos=developerCandidateAppURL.appendingPathComponent("Contents/MacOS",isDirectory:true)
            try fm.createDirectory(at:macos,withIntermediateDirectories:true)
            let contents=developerCandidateAppURL.appendingPathComponent("Contents",isDirectory:true)
            let plist=contents.appendingPathComponent("Info.plist")
            try writeCandidateInfoPlist(version:newVersion,to:plist)
            try newVersion.write(to:project.appendingPathComponent("JARVIS_VERSION.txt"),atomically:true,encoding:.utf8)

            let binary=macos.appendingPathComponent("JarvisZero")

            let files=swiftFiles(in:project)
            if !files.isEmpty {
                developmentProgress=0.58
                developmentProgressText="LOKAL KOMPILIEREN"
                developmentStatus="LOKALER BUILD"

                try? fm.removeItem(at:binary)
                var arguments=["swiftc","-parse-as-library"]
                arguments.append(contentsOf:files.map{$0.path})
                arguments.append(contentsOf:[
                    "-o",binary.path,
                    "-framework","SwiftUI",
                    "-framework","AppKit",
                    "-framework","AVFoundation",
                    "-framework","Speech"
                ])

                let result=runProcessCaptured("/usr/bin/xcrun",arguments,logURL:buildLog)
                compileSucceeded = result.0 == 0 && fm.fileExists(atPath:binary.path)
            }
            guard compileSucceeded else {
                candidateReady=false
                developmentProgress=0
                developmentProgressText="LOKALER BUILD FEHLERHAFT"
                developmentStatus="KANDIDAT VERWORFEN"
                speak("Der neue Projektstand ist noch nicht kompilierbar. Ich starte keine automatische Claude Reparatur und verbrauche kein weiteres Kontingent. Die laufende Version bleibt unverändert und der Compilerfehler wurde gespeichert.")
                return
            }

            _=runProcess("/bin/chmod",["+x",binary.path])

            developmentProgress=0.90
            developmentProgressText="SIGNIEREN UND PRÜFEN"
            developmentStatus="SIGNIERPRÜFUNG"
            let sign=runProcess("/usr/bin/codesign",["--force","--deep","--sign","-",developerCandidateAppURL.path])
            guard sign == 0,
                  runProcess("/usr/bin/codesign",["--verify","--deep","--strict",developerCandidateAppURL.path]) == 0 else {
                candidateReady=false
                developmentProgress=0
                developmentProgressText="SIGNIERFEHLER"
                developmentStatus="SIGNIERPRÜFUNG FEHLER"
                speak("Der neue Build hat die Signierprüfung nicht bestanden und wurde nicht übernommen.")
                return
            }

            try? fm.removeItem(at:activeProjectDirectory)
            try fm.copyItem(at:project,to:activeProjectDirectory)

            candidateReady=true
            awaitingDeveloperInstallConfirmation=true
            developmentProgress=1.0
            developmentProgressText="VERSION \(newVersion) BEREIT"
            developmentStatus="ENTWICKLUNG BEREIT"
            speak("Die neue Jarvis Version \(newVersion) ist fertig, kompiliert und signiert. Nach der Installation überwache ich den Start zwanzig Sekunden und rolle bei einem frühen Absturz automatisch zurück. Soll ich sie jetzt installieren?")
        } catch {
            candidateReady=false
            developmentProgress=0
            developmentProgressText="ENTWICKLUNGSFEHLER"
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

        echo "RUNTIME STARTTEST - 20 SEKUNDEN"
        HEALTHY=1
        for SECOND in $(/usr/bin/seq 1 20); do
          sleep 1
          if ! /usr/bin/pgrep -x JarvisZero >/dev/null 2>&1; then
            echo "PROZESS NACH $SECOND SEKUNDEN BEENDET"
            HEALTHY=0
            break
          fi
        done

        if [ "$HEALTHY" -eq 1 ]; then
          echo "SUCCESS - 20 SEKUNDEN STABIL"
          exit 0
        fi

        echo "START/RUNTIME FEHLER - ROLLBACK"
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
            developmentProgress=1.0
            developmentProgressText="INSTALLATION"
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
        guard let claude=findClaudeBinary() else {
            claudeCodeAvailable=false
            claudeCodeStatus="NICHT GEFUNDEN"
            return
        }

        let version=runCapture(claude,["--version"])?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        let auth=runCapture(claude,["auth","status","--text"])?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""

        if auth.isEmpty {
            claudeCodeAvailable=false
            claudeCodeStatus=version.isEmpty ? "NICHT ANGEMELDET" : "NICHT ANGEMELDET // \(version)"
        } else {
            claudeCodeAvailable=true
            claudeCodeStatus=version.isEmpty ? "VERBUNDEN + ANGEMELDET" : "VERBUNDEN + ANGEMELDET // \(version)"
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
            let fm=FileManager.default
            let base=workingDirectory ?? fm.temporaryDirectory
            let token=UUID().uuidString
            let outURL=base.appendingPathComponent("claude-output-\(token).txt")
            let errURL=base.appendingPathComponent("claude-error-\(token).txt")

            fm.createFile(atPath:outURL.path,contents:nil)
            fm.createFile(atPath:errURL.path,contents:nil)

            guard let outHandle=try? FileHandle(forWritingTo:outURL),
                  let errHandle=try? FileHandle(forWritingTo:errURL) else {
                return nil
            }

            defer {
                try? outHandle.close()
                try? errHandle.close()
                try? fm.removeItem(at:outURL)
                try? fm.removeItem(at:errURL)
            }

            let p=Process()
            p.executableURL=URL(fileURLWithPath:claude)
            p.arguments=["-p",prompt]
            if let dir=workingDirectory { p.currentDirectoryURL=dir }
            p.standardOutput=outHandle
            p.standardError=errHandle

            do {
                try p.run()
                let timeout:TimeInterval=420
                let started=Date()

                while p.isRunning && Date().timeIntervalSince(started) < timeout {
                    Thread.sleep(forTimeInterval:0.25)
                }

                if p.isRunning {
                    p.terminate()
                    Thread.sleep(forTimeInterval:0.4)
                    if p.isRunning { p.interrupt() }
                }

                p.waitUntilExit()
                try? outHandle.synchronize()
                try? errHandle.synchronize()

                guard p.terminationStatus == 0,
                      let data=try? Data(contentsOf:outURL),
                      !data.isEmpty else { return nil }

                return String(data:data,encoding:.utf8)?
                    .trimmingCharacters(in:.whitespacesAndNewlines)
            } catch {
                return nil
            }
        }.value

        if let result, !result.isEmpty {
            claudeCodeAvailable=true
            claudeCodeStatus="BEREIT"
            return result
        } else {
            claudeCodeStatus="FEHLER ODER ZEITLIMIT"
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
        let developerActivationPhrases=[
            "geh in den entwicklermodus",
            "gehe in den entwicklermodus",
            "entwicklermodus aktivieren"
        ]
        if let activation=developerActivationPhrases.compactMap({ phrase -> (String, Range<String.Index>)? in
            guard let range=cmd.range(of:phrase) else{return nil}
            return (phrase,range)
        }).first {
            var remainder=String(cmd[activation.1.upperBound...])
                .trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters))
            for prefix in ["und dann ","und ","dann ","bitte "] {
                if remainder.hasPrefix(prefix) {
                    remainder=String(remainder.dropFirst(prefix.count))
                        .trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters))
                    break
                }
            }

            if !developerMode {
                enterDeveloperMode()
            }

            guard developerMode else{return}

            // Ein kombinierter Befehl wie "Geh in den Entwicklermodus und ändere ..."
            // darf den eigentlichen Entwicklungsauftrag nicht mehr abschneiden.
            if remainder.count > 2 {
                await processDeveloperInstruction(remainder)
            } else if developerMode {
                developmentStatus="ENTWICKLERMODUS AKTIV // WARTE AUF AUFTRAG"
            }
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
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let rotation = timeline.date.timeIntervalSinceReferenceDate * speed * (reverse ? -1 : 1)
            Circle()
                .trim(from: 0.04, to: 0.78)
                .stroke(
                    Color.cyan.opacity(active ? 0.90 : 0.24),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [3, 9])
                )
                .frame(width: radius, height: radius)
                .rotationEffect(.degrees(rotation))
                .shadow(color: .cyan.opacity(active ? 0.60 : 0.18), radius: active ? 14 : 5)
        }
        .allowsHitTesting(false)
    }
}

enum JarvisSystemState {
    case ready
    case listening
    case thinking
    case speaking
    case programming
    case updating(progress: Double)
    case error
}

enum JarvisModuleType: String, CaseIterable, Hashable {
    case mac = "MAC"
    case ai = "KI"
    case claude = "CLAUDE"
    case internet = "INTERNET"
    case memory = "GEDÄCHTNIS"
    case devices = "GERÄTE"
    case automation = "AUTOMATION"
    case system = "SYSTEM"
    case update = "UPDATE"
    case dev = "ENTWICKLUNG"

    var icon: String {
        switch self {
        case .mac: return "desktopcomputer"
        case .ai: return "cpu"
        case .claude: return "terminal"
        case .internet: return "globe"
        case .memory: return "brain"
        case .devices: return "laptopcomputer.and.iphone"
        case .automation: return "gearshape.2"
        case .system: return "command"
        case .update: return "arrow.clockwise.circle"
        case .dev: return "hammer"
        }
    }
}

struct JarvisBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.001, green: 0.006, blue: 0.012),
                    Color(red: 0.002, green: 0.025, blue: 0.040),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate

                    // Seeded pseudo-random starting positions + continuous drift.
                    // This keeps the field alive without teleporting every particle each frame.
                    for i in 0..<110 {
                        let seed = Double(i + 1)
                        let startX = abs(sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                        let startY = abs(sin(seed * 78.233) * 24634.6345).truncatingRemainder(dividingBy: 1)
                        let speedX = 0.0025 + abs(sin(seed * 3.17)) * 0.0075
                        let speedY = 0.0015 + abs(cos(seed * 5.91)) * 0.0050
                        let directionX = i.isMultiple(of: 2) ? 1.0 : -1.0
                        let directionY = i.isMultiple(of: 3) ? 1.0 : -1.0

                        var nx = (startX + time * speedX * directionX).truncatingRemainder(dividingBy: 1)
                        var ny = (startY + time * speedY * directionY).truncatingRemainder(dividingBy: 1)
                        if nx < 0 { nx += 1 }
                        if ny < 0 { ny += 1 }

                        let waveX = sin(time * (0.10 + seed.truncatingRemainder(dividingBy: 7) * 0.015) + seed) * 0.012
                        let waveY = cos(time * (0.08 + seed.truncatingRemainder(dividingBy: 5) * 0.014) + seed * 0.7) * 0.010
                        nx = (nx + waveX + 1).truncatingRemainder(dividingBy: 1)
                        ny = (ny + waveY + 1).truncatingRemainder(dividingBy: 1)

                        let x = CGFloat(nx) * size.width
                        let y = CGFloat(ny) * size.height
                        let twinkle = 0.55 + 0.45 * sin(time * (0.7 + seed.truncatingRemainder(dividingBy: 9) * 0.11) + seed)
                        let radius: CGFloat = i.isMultiple(of: 13) ? 1.8 : (i.isMultiple(of: 5) ? 1.2 : 0.75)
                        let alpha = (i.isMultiple(of: 11) ? 0.30 : 0.13) * twinkle

                        let rect = CGRect(x: x - radius/2, y: y - radius/2, width: radius, height: radius)
                        context.fill(Path(ellipseIn: rect), with: .color(.cyan.opacity(alpha)))

                        if i.isMultiple(of: 17) {
                            let glowRect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                            context.fill(Path(ellipseIn: glowRect), with: .color(.cyan.opacity(0.025 + 0.035 * twinkle)))
                        }
                    }

                    let step: CGFloat = 72
                    for x in stride(from: 0, through: size.width, by: step) {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(.cyan.opacity(0.022)), lineWidth: 0.5)
                    }
                    for y in stride(from: 0, through: size.height, by: step) {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(.cyan.opacity(0.022)), lineWidth: 0.5)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            RadialGradient(
                colors: [.clear, .black.opacity(0.78)],
                center: .center,
                startRadius: 260,
                endRadius: 900
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

struct JarvisCoreView: View {
    let state: JarvisSystemState

    private var color: Color {
        if case .error = state { return .orange }
        return .cyan
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate
                var particleCount = 230
                var rotationSpeed = 0.34
                var pulse = 1.0

                switch state {
                case .ready:
                    break
                case .listening:
                    particleCount = 280
                    rotationSpeed = 0.72
                    pulse = 1.0 + sin(time * 4.0) * 0.055
                case .thinking:
                    particleCount = 340
                    rotationSpeed = 1.45
                    pulse = 1.02
                case .speaking:
                    particleCount = 310
                    rotationSpeed = 0.90
                    pulse = 1.0 + sin(time * 7.0) * 0.085
                case .programming:
                    particleCount = 360
                    rotationSpeed = 1.10
                    pulse = 1.03
                case .updating:
                    particleCount = 250
                    rotationSpeed = 0.42
                case .error:
                    particleCount = 260
                    rotationSpeed = 0.22
                    pulse = 1.0 + sin(time * 5.0) * 0.03
                }

                let baseRadius = min(size.width, size.height) * 0.28
                for i in 0..<particleCount {
                    let fi = Double(i)
                    let golden = Double.pi * (3.0 - sqrt(5.0))
                    let y = 1.0 - (fi / Double(max(1, particleCount - 1))) * 2.0
                    let radial = sqrt(max(0.0, 1.0 - y * y))
                    let theta = golden * fi + time * rotationSpeed
                    let x3 = cos(theta) * radial
                    let z3 = sin(theta) * radial
                    let depth = (z3 + 1.0) / 2.0
                    let perspective = 0.78 + depth * 0.28
                    let px = center.x + CGFloat(x3) * baseRadius * pulse * perspective
                    let py = center.y + CGFloat(y) * baseRadius * pulse * perspective
                    let dot = 1.0 + depth * 1.6
                    let rect = CGRect(x: px - dot/2, y: py - dot/2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.18 + depth * 0.68)))
                }

                let glowRadius = baseRadius * 0.46
                let glowRect = CGRect(
                    x: center.x - glowRadius,
                    y: center.y - glowRadius,
                    width: glowRadius * 2,
                    height: glowRadius * 2
                )
                context.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.055)))
            }
            .overlay {
                ZStack {
                    ArcRing(radius: 390, speed: 8, reverse: false, active: isActive, lineWidth: 1.4)
                    ArcRing(radius: 350, speed: 13, reverse: true, active: isActive, lineWidth: 1.0)
                    ArcRing(radius: 310, speed: 19, reverse: false, active: isActive, lineWidth: 0.8)

                    if case let .updating(progress) = state {
                        Circle()
                            .trim(from: 0, to: max(0, min(1, progress)))
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 405, height: 405)
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .cyan, radius: 10)
                    }

                    VStack(spacing: 7) {
                        Text("JARVIS")
                            .font(.system(size: 31, weight: .ultraLight, design: .rounded))
                            .tracking(8)
                        Text(stateLabel)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(2.6)
                    }
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.5), radius: 10)
                }
            }
        }
        .frame(width: 430, height: 430)
        .allowsHitTesting(false)
    }

    private var isActive: Bool {
        switch state {
        case .ready: return false
        default: return true
        }
    }

    private var stateLabel: String {
        switch state {
        case .ready: return "BEREIT"
        case .listening: return "HÖRT ZU"
        case .thinking: return "DENKT"
        case .speaking: return "SPRICHT"
        case .programming: return "CLAUDE PROGRAMMIERT"
        case .updating: return "UPDATE"
        case .error: return "FEHLER"
        }
    }
}

struct CornerAccents: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l: CGFloat = 9
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY - l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        return p
    }
}

struct JarvisModuleView: View {
    let type: JarvisModuleType
    let isActive: Bool
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 9) {
                    Image(systemName: type.icon)
                        .font(.system(size: 15, weight: .light))
                    Text(type.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                }
                if isHovered {
                    Text(isActive ? "WORKSPACE AKTIV" : "ÖFFNEN // SYSTEMMODUL")
                        .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .opacity(0.68)
                }
            }
            .foregroundStyle(isHovered || isActive ? .white : .cyan.opacity(0.82))
            .frame(width: 146, height: isHovered ? 50 : 38)
            .background(.black.opacity(0.54))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.cyan.opacity(isHovered || isActive ? 0.78 : 0.24), lineWidth: 1))
            .overlay(CornerAccents().stroke(.white.opacity(isHovered ? 0.75 : 0.0), lineWidth: 1.2))
            .shadow(color: .cyan.opacity(isHovered ? 0.28 : 0.06), radius: isHovered ? 12 : 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.035 : 1.0)
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}

struct ConnectionLinesView: View {
    let module: JarvisModuleType

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let target = modulePosition(module, in: size)
                var p = Path()
                p.move(to: center)
                p.addLine(to: target)
                context.stroke(p, with: .color(.cyan.opacity(0.34)), style: StrokeStyle(lineWidth: 1, dash: [4, 8]))

                let node = CGRect(x: target.x - 3, y: target.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: node), with: .color(.cyan.opacity(0.85)))
            }
        }
        .allowsHitTesting(false)
    }

    private func modulePosition(_ module: JarvisModuleType, in size: CGSize) -> CGPoint {
        let index = JarvisModuleType.allCases.firstIndex(of: module) ?? 0
        let angle = Double(index) * (2.0 * Double.pi / Double(JarvisModuleType.allCases.count)) - Double.pi / 2.0
        let rx = min(size.width * 0.35, 430)
        let ry = min(size.height * 0.33, 285)
        return CGPoint(
            x: size.width / 2 + CGFloat(cos(angle)) * rx,
            y: size.height / 2 + CGFloat(sin(angle)) * ry
        )
    }
}

struct JarvisWorkspaceView: View {
    @ObservedObject var core: JarvisCore
    let module: JarvisModuleType
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: module.icon)
                    .font(.system(size: 20, weight: .light))
                Text("\(module.rawValue) // WORKSPACE")
                    .font(.system(size: 18, weight: .light, design: .monospaced))
                    .tracking(2)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.cyan)

            Rectangle().fill(.cyan.opacity(0.25)).frame(height: 1)

            workspaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(22)
        .frame(maxWidth: 760, maxHeight: 510)
        .background(.black.opacity(0.88))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.48), lineWidth: 1))
        .overlay(CornerAccents().stroke(.cyan.opacity(0.85), lineWidth: 1.2))
        .shadow(color: .cyan.opacity(0.20), radius: 28)
    }

    @ViewBuilder private var workspaceContent: some View {
        switch module {
        case .mac:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("MAC-STEUERUNG", "Direkter Zugriff auf lokale Programme")
                HStack {
                    appButton("Safari", "com.apple.Safari", "safari")
                    appButton("Finder", "com.apple.finder", "folder")
                    appButton("Mail", "com.apple.mail", "envelope")
                    appButton("Kalender", "com.apple.iCal", "calendar")
                }
            }
        case .ai:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("LOKALE KI", core.localAI ? core.localAIModel : "Nicht verbunden")
                statusRow("OLLAMA", core.localAI ? "VERBUNDEN" : "NICHT BEREIT")
                statusRow("ROUTER", core.lastRoute)
                statusRow("SETUP", core.aiSetupStatus)
                if !core.localAI {
                    Button(core.aiInstalling ? "KI WIRD EINGERICHTET …" : "KI EINRICHTEN") { core.confirmAndSetupAI() }
                        .buttonStyle(.borderedProminent).tint(.cyan).disabled(core.aiInstalling)
                }
            }
        case .claude:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("CLAUDE CODE", "Entwickler-KI")
                statusRow("VERBINDUNG", core.claudeCodeAvailable ? "BEREIT" : "NICHT BEREIT")
                statusRow("STATUS", core.claudeCodeStatus)
                statusRow("ENTWICKLUNG", core.developmentStatus)
                Button(core.developerMode ? "ENTWICKLERMODUS BEENDEN" : "ENTWICKLERMODUS STARTEN") {
                    core.developerMode ? core.leaveDeveloperMode() : core.enterDeveloperMode()
                }
                .buttonStyle(.bordered).tint(core.developerMode ? .green : .cyan)
            }
        case .internet:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("INTERNET", "Öffentliche Informationen und Web-Routing")
                statusRow("STATUS", core.internetStatus)
                statusRow("LETZTE ROUTE", core.lastRoute)
                Button("SAFARI ÖFFNEN") { Task { await core.openBundle("com.apple.Safari", "Safari") } }
                    .buttonStyle(.bordered).tint(.cyan)
            }
        case .memory:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("GEDÄCHTNIS", "Lokaler Jarvis-Speicher")
                statusRow("GESPEICHERTE EINTRÄGE", "\(core.memoryCount)")
                Text("Neue Erinnerungen können weiterhin per Sprache oder Texteingabe mit „Merke dir …“ gespeichert werden.")
                    .foregroundStyle(.white.opacity(0.62))
            }
        case .devices:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("GERÄTE", "Vorbereitung für sichere Geräte-Kopplung")
                statusRow("PAIRING", "NOCH NICHT AKTIV")
                Text("Die holografische Geräteoberfläche ist vorbereitet. Eine erfolgreiche Smartphone-Kopplung wird erst angezeigt, wenn eine echte Gegenstelle und Autorisierung implementiert sind.")
                    .foregroundStyle(.white.opacity(0.62))
            }
        case .automation:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("AUTOMATION", "Lokale Abläufe und zukünftige Routinen")
                statusRow("STATUS", "BEREIT")
                Text("Dieses Modul ist als Arbeitsbereich vorbereitet. Bestehende Jarvis-Funktionen bleiben unverändert.")
                    .foregroundStyle(.white.opacity(0.62))
            }
        case .system:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("SYSTEM", "Sprache und Kernstatus")
                Toggle("Dauerhaft zuhören", isOn: $core.continuous)
                    .toggleStyle(.switch).tint(.cyan)
                    .onChange(of: core.continuous) { _, enabled in
                        enabled ? core.startListening() : core.stopListening()
                    }
                statusRow("STIMME", core.voiceLabel)
                statusRow("SYSTEM", core.status)
                statusRow("LOKALE KI", core.localAI ? "VERBUNDEN" : "NICHT BEREIT")
            }
        case .update:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("UPDATE", "Stabiler GitHub-Updatekanal")
                statusRow("STATUS", core.updateStatus)
                statusRow("VERSION", Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "2.3.0")
                if core.updateAvailable {
                    statusRow("NEU", core.latestVersion)
                    Button("UPDATE INSTALLIEREN") { core.confirmAndInstallUpdate() }
                        .buttonStyle(.borderedProminent).tint(.cyan)
                }
                Button("NACH UPDATE SUCHEN") { Task { await core.checkForUpdates() } }
                    .buttonStyle(.bordered).tint(.cyan)
            }
        case .dev:
            VStack(alignment: .leading, spacing: 10) {
                workspaceTitle("ENTWICKLUNG", "Single-Pass Claude-Entwicklungsmodus")
                statusRow("STATUS", core.developmentStatus)
                statusRow("CLAUDE", core.claudeCodeStatus)
                ProgressView(value: core.developmentProgress).tint(.cyan)
                Text("\(core.developmentProgressText) // \(Int(core.developmentProgress * 100)) %")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Button(core.developerMode ? "ENTWICKLERMODUS BEENDEN" : "ENTWICKLERMODUS STARTEN") {
                    core.developerMode ? core.leaveDeveloperMode() : core.enterDeveloperMode()
                }
                .buttonStyle(.bordered).tint(core.developerMode ? .green : .cyan)
                if core.candidateReady {
                    Button("GEPRÜFTEN KANDIDATEN INSTALLIEREN") { core.installDeveloperCandidate() }
                        .buttonStyle(.borderedProminent).tint(.green)
                }
            }
        }
    }

    private func workspaceTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
            Text(subtitle).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.52))
        }
    }

    private func statusRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(value).foregroundStyle(.cyan)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.60))
    }

    private func appButton(_ name: String, _ id: String, _ icon: String) -> some View {
        Button {
            Task { await core.openBundle(id, name) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                Text(name)
            }
            .frame(width: 92, height: 62)
        }
        .buttonStyle(.bordered).tint(.cyan)
    }
}

struct JarvisView: View {
    @StateObject private var core = JarvisCore()
    @State private var input = ""
    @State private var activeModule: JarvisModuleType?
    @State private var hoveredModule: JarvisModuleType?
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            JarvisBackgroundView()

            if let hoveredModule, activeModule == nil {
                ConnectionLinesView(module: hoveredModule)
                    .transition(.opacity)
            }

            if activeModule == nil {
                moduleLayer
                    .transition(.opacity)
            }

            JarvisCoreView(state: systemState)
                .scaleEffect(activeModule == nil ? 1.0 : 0.58)
                .offset(x: activeModule == nil ? 0 : -410, y: activeModule == nil ? 0 : -40)
                .opacity(activeModule == nil ? 1.0 : 0.62)
                .animation(.spring(response: 0.55, dampingFraction: 0.84), value: activeModule)

            header

            if let module = activeModule {
                JarvisWorkspaceView(core: core, module: module) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        activeModule = nil
                    }
                }
                .offset(x: 150, y: -10)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(10)
            }

            commandBar
        }
        .preferredColorScheme(.dark)
        .onReceive(timer) { now = $0 }
        .task { await core.boot() }
    }

    private var systemState: JarvisSystemState {
        if core.updateStatus.contains("%") {
            let digits = core.updateStatus.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
            return .updating(progress: (digits.first ?? 0) / 100.0)
        }
        if core.developmentStatus.contains("CLAUDE") || core.claudeCodeStatus.contains("PROGRAMMIERT") || core.developmentProgress > 0.05 && core.developmentProgress < 0.95 {
            return .programming
        }
        if core.speaking { return .speaking }
        if core.status == "VERARBEITUNG" { return .thinking }
        if core.listening { return .listening }
        if core.status.contains("FEHLER") || core.developmentStatus.contains("FEHLER") { return .error }
        return .ready
    }

    private var moduleLayer: some View {
        GeometryReader { geo in
            ForEach(JarvisModuleType.allCases, id: \.self) { module in
                let index = JarvisModuleType.allCases.firstIndex(of: module) ?? 0
                let angle = Double(index) * (2.0 * Double.pi / Double(JarvisModuleType.allCases.count)) - Double.pi / 2.0
                let rx = min(geo.size.width * 0.35, 430)
                let ry = min(geo.size.height * 0.33, 285)
                let x = geo.size.width / 2 + CGFloat(cos(angle)) * rx
                let y = geo.size.height / 2 + CGFloat(sin(angle)) * ry

                JarvisModuleView(
                    type: module,
                    isActive: activeModule == module,
                    isHovered: hoveredModule == module
                ) {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                        activeModule = module
                        hoveredModule = nil
                    }
                }
                .position(x: x, y: y)
                .onHover { hovering in
                    hoveredModule = hovering ? module : nil
                }
            }
        }
        .padding(.horizontal, 55)
        .padding(.vertical, 80)
    }

    private var header: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("J.A.R.V.I.S.")
                        .font(.system(size: 22, weight: .ultraLight, design: .rounded))
                        .tracking(7)
                    Text("NEURALES STEUERSYSTEM // MARK V")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(1.8)
                        .opacity(0.55)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(now.formatted(date: .abbreviated, time: .standard))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    Text("● \(core.status)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(core.listening ? .green : .cyan)
                }
            }
            .foregroundStyle(.cyan)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var commandBar: some View {
        VStack {
            Spacer()
            VStack(spacing: 6) {
                if !core.transcript.isEmpty {
                    Text(core.transcript)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    Image(systemName: core.listening ? "waveform" : "mic")
                        .foregroundStyle(.cyan)
                    TextField("Mit Jarvis sprechen oder Befehl eingeben …", text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit { send() }
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.right")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 16)
                .frame(width: 560, height: 42)
                .background(.black.opacity(0.72))
                .overlay(Capsule().stroke(.cyan.opacity(0.32), lineWidth: 1))
                .clipShape(Capsule())
                .shadow(color: .cyan.opacity(0.10), radius: 12)

                HStack(spacing: 16) {
                    Text("STIMME \(core.listening ? "AKTIV" : "STANDBY")")
                    Text("KI \(core.localAI ? "LOKAL" : "OFFLINE")")
                    Text("CLAUDE \(core.claudeCodeAvailable ? "BEREIT" : "OFFLINE")")
                    Text("VERSION \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "2.3.0")")
                }
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.cyan.opacity(0.40))
            }
            .padding(.bottom, 14)
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        core.submit(text)
    }
}

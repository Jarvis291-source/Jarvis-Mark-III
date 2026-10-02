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

@main struct JarvisZeroApp: App {
    var body: some Scene {
        WindowGroup { JarvisView().frame(minWidth: 1280, minHeight: 820) }
            .windowStyle(.hiddenTitleBar)
    }
}

struct LogLine: Identifiable { let id = UUID(); let who:String; let text:String }

@MainActor final class JarvisCore: NSObject, ObservableObject, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {
    @Published var status = "ONLINE"
    @Published var transcript = ""
    @Published var logs:[LogLine] = [LogLine(who:"JARVIS", text:"System online. Bereit, Jonas.")]
    @Published var listening = false
    @Published var continuous = true
    @Published var localAI = false
    @Published var localAIModel = "OFFLINE"
    @Published var cpuPulse:Double = 0.22
    @Published var updateAvailable = false
    @Published var latestVersion = "1.7.4"
    @Published var updateStatus = "UP TO DATE"
    @Published var updateNotes:[String] = []
    private var pendingPackageURL:String?
    private var pendingSHA256:String?
    private static let currentVersion = "1.7.4"
    private static let manifestURL = "https://raw.githubusercontent.com/Jarvis291-source/Jarvis-Mark-III/main/manifest.json"
    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier:"de-DE"))
    private var request:SFSpeechAudioBufferRecognitionRequest?
    private var task:SFSpeechRecognitionTask?
    private var lastHandled = ""
    private var restartWork: Task<Void,Never>?
    private var updateLoop: Task<Void,Never>?

    override init(){ super.init(); recognizer?.delegate = self; synth.delegate = self }
    func boot() async {
        await requestPermissions()
        await checkLocalAI()
        await checkForUpdates()
        startAutomaticUpdateChecks()
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
        let u=AVSpeechUtterance(string:text)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        u.voice = voices.first(where: { $0.language == "en-GB" && $0.gender == .male && $0.quality == .enhanced })
            ?? voices.first(where: { $0.language == "en-GB" && $0.gender == .male })
            ?? AVSpeechSynthesisVoice(language:"en-GB")
        u.rate=0.46; u.pitchMultiplier=0.82; u.volume=0.92
        shouldResumeAfterSpeech = resume
        synth.speak(u)
    }
    private var shouldResumeAfterSpeech = false
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.shouldResumeAfterSpeech && self.continuous {
                self.shouldResumeAfterSpeech = false
                try? await Task.sleep(nanoseconds: 220_000_000)
                self.startListening()
            }
        }
    }
    func checkLocalAI() async {
        guard let url=URL(string:"http://127.0.0.1:11434/api/tags") else{return}
        var r=URLRequest(url:url); r.timeoutInterval=1.2
        do {
            let (data,resp)=try await URLSession.shared.data(for:r)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                localAI=false; localAIModel="OFFLINE"; return
            }
            let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any]
            let models=(obj?["models"] as? [[String:Any]]) ?? []
            let names=models.compactMap { $0["name"] as? String }
            if let preferred=names.first(where: { $0.lowercased().contains("qwen2.5:3b") }) {
                localAI=true; localAIModel=preferred
            } else if let first=names.first {
                localAI=true; localAIModel=first
            } else {
                localAI=false; localAIModel="NO MODEL"
            }
        } catch {
            localAI=false; localAIModel="OFFLINE"
        }
    }
    func checkForUpdates() async {
        updateStatus = "CHECKING…"
        let url = Self.manifestURL + "?t=\(Int(Date().timeIntervalSince1970))"

        guard let output = runCapture("/usr/bin/curl", [
            "-L", "--fail", "--silent", "--show-error",
            "--connect-timeout", "5",
            "--max-time", "12",
            "-H", "Cache-Control: no-cache",
            url
        ]) else {
            updateAvailable = false
            updateStatus = "NETWORK ERROR"
            return
        }

        guard let data = output.data(using: .utf8) else {
            updateAvailable = false
            updateStatus = "DATA ERROR"
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
            updateStatus = updateAvailable ? "UPDATE \(manifest.latestVersion)" : "UP TO DATE"
        } catch {
            updateAvailable = false
            updateStatus = "DECODE ERROR"
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
            updateStatus = "UPDATE INVALID"
            return
        }

        updateStatus = "DOWNLOADING"
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 30
            request.setValue("Jarvis-ZERO/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                updateStatus = "DOWNLOAD ERROR"
                return
            }

            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("JarvisUpdate-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)

            let source = work.appendingPathComponent("JarvisZero.swift")
            try data.write(to: source, options: .atomic)

            updateStatus = "VERIFYING HASH"
            guard let actual = sha256(of: source), actual == expected else {
                updateStatus = "HASH ERROR"
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
            updateStatus = "COMPILING"
            let compile = runProcess("/usr/bin/xcrun", [
                "swiftc", "-parse-as-library", source.path,
                "-o", binary.path,
                "-framework", "SwiftUI",
                "-framework", "AppKit",
                "-framework", "AVFoundation",
                "-framework", "Speech"
            ])
            guard compile == 0, fm.fileExists(atPath: binary.path) else {
                updateStatus = "COMPILE ERROR"
                return
            }

            _ = runProcess("/bin/chmod", ["+x", binary.path])
            let sign = runProcess("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
            guard sign == 0 else {
                updateStatus = "SIGN ERROR"
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

            updateStatus = "RESTARTING"

            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            launcher.arguments = ["/bin/bash", helper.path]
            launcher.standardOutput = FileHandle.nullDevice
            launcher.standardError = FileHandle.nullDevice
            try launcher.run()

            try? await Task.sleep(nanoseconds: 400_000_000)
            NSApp.terminate(nil)
        } catch {
            updateStatus = "UPDATE ERROR"
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
        do { try engine.start(); listening=true; status="LISTENING" } catch { status="MIC ERROR"; return }
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
    func submit(_ text:String){ let clean=text.trimmingCharacters(in:.whitespacesAndNewlines); guard !clean.isEmpty else{return}; logs.append(LogLine(who:"DU",text:clean)); Task{ await execute(clean.lowercased()) } }
    func openBundle(_ id:String,_ label:String) async { if let u=NSWorkspace.shared.urlForApplication(withBundleIdentifier:id){ do{ _=try await NSWorkspace.shared.openApplication(at:u,configuration:.init()); speak("\(label) wurde geöffnet.") }catch{speak("\(label) konnte ich nicht öffnen.")} } }
    func execute(_ cmd:String) async {
        status="PROCESSING"; cpuPulse=0.9
        defer { status=listening ? "LISTENING":"ONLINE"; cpuPulse=0.22 }
        if cmd.contains("öffne safari") { await openBundle("com.apple.Safari","Safari"); return }
        if cmd.contains("öffne finder") { await openBundle("com.apple.finder","Finder"); return }
        if cmd.contains("öffne mail") { await openBundle("com.apple.mail","Mail"); return }
        if cmd.contains("öffne kalender") { await openBundle("com.apple.iCal","Kalender"); return }
        if cmd.contains("öffne notizen") { await openBundle("com.apple.Notes","Notizen"); return }
        if cmd.contains("öffne systemeinstellungen") || cmd.contains("öffne einstellungen") { await openBundle("com.apple.systempreferences","Systemeinstellungen"); return }
        if cmd.contains("öffne rechner") || cmd.contains("öffne taschenrechner") { await openBundle("com.apple.calculator","Rechner"); return }
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
        if localAI, let answer=await askOllama(cmd) { speak(answer); return }
        speak("Diesen Befehl kenne ich lokal noch nicht. Für freie Gespräche kannst du die lokale KI aktivieren; die Mac-Befehle funktionieren bereits ohne API.")
    }
    func askOllama(_ prompt:String) async -> String? {
        guard let u=URL(string:"http://127.0.0.1:11434/api/generate") else{return nil}
        let model = localAIModel == "OFFLINE" || localAIModel == "NO MODEL" ? "qwen2.5:3b" : localAIModel
        let body:[String:Any] = ["model":model,"prompt":"Du bist JARVIS, Jonas' deutscher Mac-Assistent. Antworte knapp und natürlich. Nutzer: \(prompt)","stream":false]
        guard let data=try? JSONSerialization.data(withJSONObject:body) else{return nil}
        var r=URLRequest(url:u); r.httpMethod="POST"; r.httpBody=data; r.timeoutInterval=90; r.setValue("application/json",forHTTPHeaderField:"Content-Type")
        do { let (d,_)=try await URLSession.shared.data(for:r); let o=try JSONSerialization.jsonObject(with:d) as? [String:Any]; return o?["response"] as? String } catch { return nil }
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            let pulse = 0.92 + (sin(timeline.date.timeIntervalSinceReferenceDate * 2.2) + 1) * 0.035
            ZStack {
                ArcRing(radius: 390, speed: 7, reverse: false, active: processing, lineWidth: 2)
                ArcRing(radius: 345, speed: 12, reverse: true, active: listening, lineWidth: 1.5)
                ArcRing(radius: 300, speed: 19, reverse: false, active: processing, lineWidth: 1.2)
                Circle().stroke(.cyan.opacity(0.10), lineWidth: 1).frame(width: 255, height: 255)
                Circle().stroke(.cyan.opacity(0.22), lineWidth: 1).frame(width: 225, height: 225)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(processing ? 0.42 : 0.18),
                                .cyan.opacity(processing ? 0.40 : 0.22),
                                .cyan.opacity(0.05),
                                .clear
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 120
                        )
                    )
                    .frame(width: 230, height: 230)
                    .scaleEffect(pulse)
                    .shadow(color: .cyan.opacity(processing ? 0.8 : 0.42), radius: processing ? 30 : 15)
                ForEach(0..<8, id: \.self) { i in
                    Capsule()
                        .fill(.cyan.opacity(i.isMultiple(of: 2) ? 0.95 : 0.32))
                        .frame(width: 3, height: 26)
                        .offset(y: -132)
                        .rotationEffect(.degrees(Double(i) * 45))
                }
                VStack(spacing: 8) {
                    Text("JARVIS")
                        .font(.system(size: 38, weight: .ultraLight, design: .rounded))
                        .tracking(8)
                    Text(status)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(3)
                    HStack(spacing: 3) {
                        ForEach(0..<16, id: \.self) { i in
                            Capsule()
                                .fill(.cyan.opacity(i.isMultiple(of: 3) ? 1 : 0.30))
                                .frame(width: 3, height: CGFloat(6 + (i % 5) * 3))
                        }
                    }
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

            ScanBeam().opacity(core.listening ? 0.75 : 0.34)

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
                    Text("MARK IV")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.cyan.opacity(0.10))
                        .overlay(Rectangle().stroke(.cyan.opacity(0.35)))
                }
                Text("HOLOGRAPHIC COMMAND INTERFACE // LOCAL INTELLIGENCE CORE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.cyan.opacity(0.58))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(now.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                Text("SECURE LOCAL SESSION // ZERO API FEES")
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
            HUDPanel(title: "CORE TELEMETRY") {
                stat("CORE", "ONLINE")
                stat("VOICE", core.listening ? "ACTIVE" : "STANDBY")
                stat("LOCAL AI", core.localAI ? "CONNECTED" : "OPTIONAL")
                stat("AI MODEL", core.localAIModel)
                stat("UPDATE", core.updateStatus)
                MetricBar(label: "CORE LOAD", value: core.cpuPulse, text: "\(Int(core.cpuPulse * 100))%")
                MetricBar(label: "VOICE LINK", value: core.listening ? 0.94 : 0.22, text: core.listening ? "LOCKED" : "IDLE")
                MetricBar(label: "NETWORK", value: 0.72, text: "READY")
            }

            HUDPanel(title: "COMMAND MATRIX") {
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
                CoreOrb(status: core.status, listening: core.listening, processing: core.status == "PROCESSING")
                VStack {
                    HStack {
                        tinyTag("VOICE", core.listening ? "LINKED" : "WAIT")
                        Spacer()
                        tinyTag("AI", core.localAI ? "LOCAL" : "OPTIONAL")
                    }
                    Spacer()
                    HStack {
                        tinyTag("UPDATE", core.updateStatus)
                        Spacer()
                        tinyTag("BUILD", "1.7.4")
                    }
                }
                .frame(width: 500, height: 405)
            }
            .frame(height: 425)

            Text(core.listening ? "AWAITING COMMAND // SAY “JARVIS …”" : "VOICE ARRAY STANDBY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(.cyan.opacity(0.82))

            Text(core.transcript.isEmpty ? "Audio stream ready. Wake word armed." : core.transcript)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 42)

            HUDPanel(title: "ACTIVE INTELLIGENCE") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(core.localAI ? "LOCAL NEURAL CORE CONNECTED" : "LOCAL NEURAL CORE OPTIONAL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                        Text(core.localAI ? core.localAIModel : "Mac control remains available without AI model.")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Circle()
                        .fill(core.localAI ? .green : .cyan.opacity(0.45))
                        .frame(width: 8, height: 8)
                        .shadow(color: core.localAI ? .green : .cyan, radius: 7)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rightColumn: some View {
        VStack(spacing: 11) {
            HUDPanel(title: "LIVE DATA STREAM") {
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

            HUDPanel(title: "VOICE ARRAY") {
                Toggle("Dauerhaft zuhören", isOn: $core.continuous)
                    .toggleStyle(.switch)
                    .tint(.cyan)
                    .onChange(of: core.continuous) { _, enabled in
                        enabled ? core.startListening() : core.stopListening()
                    }
                HStack {
                    Text("WAKE WORD")
                    Spacer()
                    Text("JARVIS")
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.72))
            }

            HUDPanel(title: "UPDATE UPLINK") {
                HStack {
                    Circle().fill(.green).frame(width: 6, height: 6).shadow(color: .green, radius: 5)
                    Text("GITHUB CHANNEL // LIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(.green)
                }
                Text(core.updateAvailable ? "Version \(core.latestVersion) verfügbar" : core.updateStatus)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Button(core.updateAvailable ? "UPDATE INSTALLIEREN" : "NACH UPDATE SUCHEN") {
                    if core.updateAvailable {
                        core.confirmAndInstallUpdate()
                    } else {
                        Task { await core.checkForUpdates() }
                    }
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
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
            TextField("COMMAND INPUT // Befehl eingeben …", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit { send() }
                .padding(.vertical, 11)
            Button("EXECUTE") { send() }
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
            Text("JARVIS // MARK IV // BUILD 1.7.4")
            Spacer()
            Text("LOCAL CORE • CONTINUOUS VOICE • SECURE UPDATE UPLINK • ZERO API FEES")
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

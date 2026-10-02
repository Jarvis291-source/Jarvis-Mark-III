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
        WindowGroup { JarvisView().frame(minWidth: 1180, minHeight: 760) }
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
    @Published var latestVersion = "1.6"
    @Published var updateStatus = "UP TO DATE"
    @Published var updateNotes:[String] = []
    private var pendingPackageURL:String?
    private var pendingSHA256:String?
    private static let currentVersion = "1.6.1"
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
        let urls = [
            Self.manifestURL + "?t=\(Int(Date().timeIntervalSince1970))",
            "https://api.github.com/repos/Jarvis291-source/Jarvis-Mark-III/contents/manifest.json?ref=main"
        ]
        var lastError = "NETWORK ERROR"
        for (index, text) in urls.enumerated() {
            guard let url = URL(string: text) else { continue }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.timeoutInterval = 10
            req.setValue("Jarvis-ZERO/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
            if index == 1 { req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse else { lastError = "NO HTTP"; continue }
                guard http.statusCode == 200 else { lastError = "HTTP \(http.statusCode)"; continue }
                let manifestData: Data
                if index == 1 {
                    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String:Any],
                          let b64 = obj["content"] as? String,
                          let decoded = Data(base64Encoded: b64.replacingOccurrences(of: "\n", with: "")) else {
                        lastError = "API DECODE ERROR"; continue
                    }
                    manifestData = decoded
                } else {
                    manifestData = data
                }
                do {
                    let manifest = try JSONDecoder().decode(JarvisUpdateManifest.self, from: manifestData)
                    latestVersion = manifest.latestVersion
                    updateNotes = manifest.releaseNotes
                    pendingPackageURL = manifest.package
                    pendingSHA256 = manifest.sha256
                    updateAvailable = isVersion(manifest.latestVersion, newerThan: Self.currentVersion) && manifest.package != nil && manifest.sha256 != nil
                    updateStatus = updateAvailable ? "UPDATE \(manifest.latestVersion)" : "UP TO DATE"
                    return
                } catch {
                    lastError = "DECODE ERROR"
                }
            } catch {
                lastError = "NETWORK ERROR"
            }
        }
        updateAvailable = false
        updateStatus = lastError
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
        guard let urlText=pendingPackageURL, let expected=pendingSHA256?.lowercased(), let url=URL(string:urlText) else { updateStatus="UPDATE INVALID"; return }
        updateStatus="DOWNLOADING"
        do {
            let (data,response)=try await URLSession.shared.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain:"JarvisUpdate",code:1) }
            let fm=FileManager.default
            let work=fm.temporaryDirectory.appendingPathComponent("JarvisUpdate-\(UUID().uuidString)",isDirectory:true)
            try fm.createDirectory(at:work,withIntermediateDirectories:true,attributes:nil)
            let source=work.appendingPathComponent("JarvisZero.swift")
            try data.write(to:source,options:.atomic)
            guard sha256(of:source) == expected else { updateStatus="HASH ERROR"; return }
            updateStatus="VERIFYING"
            let app=work.appendingPathComponent("Jarvis-ZERO.app",isDirectory:true)
            let macos=app.appendingPathComponent("Contents/MacOS",isDirectory:true)
            let resources=app.appendingPathComponent("Contents/Resources",isDirectory:true)
            try fm.createDirectory(at:macos,withIntermediateDirectories:true,attributes:nil)
            try fm.createDirectory(at:resources,withIntermediateDirectories:true,attributes:nil)
            let plist=app.appendingPathComponent("Contents/Info.plist")
            let currentPlist=Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
            try fm.copyItem(at:currentPlist,to:plist)
            _=runProcess("/usr/libexec/PlistBuddy",["-c","Set :CFBundleShortVersionString \(latestVersion)",plist.path])
            _=runProcess("/usr/libexec/PlistBuddy",["-c","Set :CFBundleVersion \(latestVersion.replacingOccurrences(of: ".", with: ""))",plist.path])
            let binary=macos.appendingPathComponent("JarvisZero")
            updateStatus="COMPILING"
            let compile=runProcess("/usr/bin/xcrun",["swiftc","-parse-as-library",source.path,"-o",binary.path,"-framework","SwiftUI","-framework","AppKit","-framework","AVFoundation","-framework","Speech"])
            guard compile == 0 else { updateStatus="COMPILE ERROR"; return }
            _=runProcess("/bin/chmod",["+x",binary.path])
            _=runProcess("/usr/bin/codesign",["--force","--deep","--sign","-",app.path])
            let target=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Jarvis-ZERO.app")
            let backup=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Jarvis-ZERO-Backup.app")
            let script=work.appendingPathComponent("install.sh")
            let shell="""
            #!/bin/bash
            set -e
            sleep 2
            TARGET=\"\(target.path)\"
            BACKUP=\"\(backup.path)\"
            NEW=\"\(app.path)\"
            /usr/bin/pkill -x JarvisZero 2>/dev/null || true
            sleep 1
            /bin/rm -rf \"$BACKUP\"
            if [ -d \"$TARGET\" ]; then /bin/cp -R \"$TARGET\" \"$BACKUP\"; fi
            /bin/rm -rf \"$TARGET\"
            /bin/cp -R \"$NEW\" \"$TARGET\"
            /usr/bin/xattr -dr com.apple.quarantine \"$TARGET\" 2>/dev/null || true
            /usr/bin/open \"$TARGET\"
            """
            try shell.write(to:script,atomically:true,encoding:.utf8)
            _=runProcess("/bin/chmod",["+x",script.path])
            updateStatus="INSTALLING"
            let p=Process(); p.executableURL=URL(fileURLWithPath:"/bin/bash"); p.arguments=[script.path]; try p.run()
        } catch {
            updateStatus="UPDATE ERROR"
        }
    }
    private func sha256(of url:URL) -> String? {
        let pipe=Pipe(); let p=Process(); p.executableURL=URL(fileURLWithPath:"/usr/bin/shasum"); p.arguments=["-a","256",url.path]; p.standardOutput=pipe
        do { try p.run(); p.waitUntilExit(); guard p.terminationStatus == 0 else{return nil}; let d=pipe.fileHandleForReading.readDataToEndOfFile(); return String(data:d,encoding:.utf8)?.split(separator:" ").first.map(String.init)?.lowercased() } catch { return nil }
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
    let radius:CGFloat; let speed:Double; let reverse:Bool; let active:Bool
    var body: some View { TimelineView(.animation(minimumInterval:1/30)){ t in
        let x=t.date.timeIntervalSinceReferenceDate*speed*(reverse ? -1:1)
        Circle().trim(from:0.04,to:0.78).stroke(Color.cyan.opacity(active ? 0.95:0.55),style:StrokeStyle(lineWidth:2,lineCap:.round,dash:[2,7])).frame(width:radius,height:radius).rotationEffect(.degrees(x)).shadow(color:.cyan.opacity(0.7),radius:active ? 12:5)
    }}
}
struct HUDPanel<Content:View>: View { let title:String; @ViewBuilder var content:Content
    var body: some View { VStack(alignment:.leading,spacing:10){ HStack{Text(title).font(.system(size:10,weight:.semibold)).tracking(2).foregroundStyle(.cyan); Rectangle().fill(.cyan.opacity(0.3)).frame(height:1)}; content }.padding(14).background(Color.cyan.opacity(0.035)).overlay(RoundedRectangle(cornerRadius:3).stroke(Color.cyan.opacity(0.25),lineWidth:1)) }
}
struct JarvisView: View {
    @StateObject var core=JarvisCore(); @State var input=""; @State var now=Date()
    let timer=Timer.publish(every:1,on:.main,in:.common).autoconnect()
    var body: some View { ZStack {
        LinearGradient(colors:[Color(red:0.005,green:0.02,blue:0.035),Color(red:0.01,green:0.07,blue:0.10),.black],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
        Canvas { c,s in let step:CGFloat=36; for x in stride(from:0,to:s.width,by:step){ var p=Path();p.move(to:.init(x:x,y:0));p.addLine(to:.init(x:x,y:s.height));c.stroke(p,with:.color(.cyan.opacity(0.045)),lineWidth:0.5)}; for y in stride(from:0,to:s.height,by:step){var p=Path();p.move(to:.init(x:0,y:y));p.addLine(to:.init(x:s.width,y:y));c.stroke(p,with:.color(.cyan.opacity(0.045)),lineWidth:0.5)} }.ignoresSafeArea()
        VStack(spacing:12){
            HStack{ VStack(alignment:.leading){Text("J.A.R.V.I.S.").font(.system(size:24,weight:.ultraLight)).tracking(8).foregroundStyle(.cyan);Text("JUST A RATHER VERY INTELLIGENT SYSTEM // MARK III").font(.system(size:8)).tracking(2).foregroundStyle(.cyan.opacity(0.6))};Spacer();Text(now.formatted(date:.abbreviated,time:.standard)).monospacedDigit().foregroundStyle(.cyan); Text("● \(core.status)").font(.system(size:11,weight:.bold)).foregroundStyle(core.listening ? .green:.cyan)}.padding(.horizontal,24).padding(.top,16)
            HStack(alignment:.top,spacing:14){
                VStack(spacing:14){ HUDPanel(title:"SYSTEM STATUS"){ stat("CORE","ONLINE");stat("VOICE",core.listening ? "ACTIVE":"STANDBY");stat("LOCAL AI",core.localAI ? "CONNECTED":"OPTIONAL");stat("AI MODEL",core.localAIModel);stat("API COST","€ 0.00");stat("UPDATE",core.updateStatus) }; HUDPanel(title:"QUICK COMMANDS"){ quick("Safari","com.apple.Safari");quick("Finder","com.apple.finder");quick("Mail","com.apple.mail");quick("Kalender","com.apple.iCal");quick("Notizen","com.apple.Notes");quick("Einstellungen","com.apple.systempreferences");quick("Rechner","com.apple.calculator") }; Spacer() }.frame(width:235)
                VStack(spacing:6){ Spacer(); ZStack{ ArcRing(radius:330,speed:7,reverse:false,active:core.status=="PROCESSING");ArcRing(radius:285,speed:12,reverse:true,active:core.listening);ArcRing(radius:235,speed:18,reverse:false,active:core.status=="PROCESSING");Circle().stroke(.cyan.opacity(0.18),lineWidth:1).frame(width:190,height:190);Circle().fill(RadialGradient(colors:[.cyan.opacity(0.32),.cyan.opacity(0.05),.clear],center:.center,startRadius:4,endRadius:100)).frame(width:190,height:190);VStack(spacing:8){Text("JARVIS").font(.system(size:34,weight:.ultraLight)).tracking(7);HStack(spacing:3){ForEach(0..<12,id:\.self){i in Capsule().fill(Color.cyan.opacity(i % 3 == 0 ? 0.95 : 0.35)).frame(width:3,height:CGFloat(7 + (i % 4)*4))}};Text(core.status).font(.system(size:9,weight:.bold)).tracking(3)}.foregroundStyle(.cyan)}.frame(height:360); Text(core.listening ? "SAG: \"JARVIS …\"" : "VOICE STANDBY").font(.system(size:11,weight:.semibold)).tracking(3).foregroundStyle(.cyan.opacity(0.8)); Text(core.transcript.isEmpty ? "Warte auf Sprachbefehl …" : core.transcript).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.72)).frame(height:44); Spacer() }.frame(maxWidth:.infinity)
                VStack(spacing:14){ HUDPanel(title:"LIVE FEED"){ ScrollViewReader{p in ScrollView{VStack(alignment:.leading,spacing:10){ForEach(core.logs.suffix(12)){l in VStack(alignment:.leading,spacing:2){Text(l.who).font(.system(size:8,weight:.bold)).tracking(1).foregroundStyle(.cyan);Text(l.text).font(.system(size:11)).foregroundStyle(.white.opacity(0.78))}.id(l.id)}}}.frame(height:300).onChange(of:core.logs.count){_,_ in if let id=core.logs.last?.id{p.scrollTo(id,anchor:.bottom)}}} }; HUDPanel(title:"VOICE CONTROL"){ Toggle("Dauerhaft zuhören",isOn:$core.continuous).toggleStyle(.switch).onChange(of:core.continuous){_,v in v ? core.startListening():core.stopListening()};Text("Aktivierung: „Jarvis …“").font(.system(size:10)).foregroundStyle(.secondary) }; HUDPanel(title:"UPDATE SYSTEM"){ Text("GITHUB CHANNEL • LIVE // 15 MIN CHECK").font(.system(size:9,weight:.bold)).tracking(1.4).foregroundStyle(.green); Text(core.updateAvailable ? "Version \(core.latestVersion) verfügbar" : core.updateStatus).font(.system(size:10,weight:.semibold)).foregroundStyle(.cyan); Button(core.updateAvailable ? "UPDATE INSTALLIEREN" : "NACH UPDATE SUCHEN"){ if core.updateAvailable { core.confirmAndInstallUpdate() } else { Task { await core.checkForUpdates() } } }.buttonStyle(.bordered).tint(.cyan) }; Spacer() }.frame(width:300)
            }.padding(.horizontal,20)
            HStack{ TextField("Befehl eingeben …",text:$input).textFieldStyle(.plain).onSubmit{send()}.padding(12).background(.black.opacity(0.35)).overlay(Rectangle().stroke(.cyan.opacity(0.3)));Button("EXECUTE"){send()}.buttonStyle(.borderedProminent).tint(.cyan.opacity(0.55)) }.padding(.horizontal,20)
            HStack{Text("JARVIS // MARK III // BUILD 1.6.1");Spacer();Text("LOCAL CORE • ON-DEVICE VOICE • ZERO API FEES")}.font(.system(size:8,weight:.semibold)).tracking(2).foregroundStyle(.cyan.opacity(0.55)).padding(.horizontal,24).padding(.bottom,12)
        }
    }.preferredColorScheme(.dark).onReceive(timer){now=$0}.task{await core.boot()} }
    func stat(_ a:String,_ b:String)->some View{HStack{Text(a).font(.system(size:9)).foregroundStyle(.secondary);Spacer();Text(b).font(.system(size:9,weight:.bold)).foregroundStyle(.cyan)}}
    func quick(_ label:String,_ id:String)->some View{Button{Task{await core.openBundle(id,label)}}label:{HStack{Image(systemName:"chevron.right");Text(label);Spacer()}.font(.system(size:11)).foregroundStyle(.cyan)}.buttonStyle(.plain)}
    func send(){let s=input;input="";core.submit(s)}
}

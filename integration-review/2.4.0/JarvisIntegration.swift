import SwiftUI
import AppKit

struct JarvisView: View {
    @StateObject private var core = JarvisCore()
    @State private var input = ""
    @State private var activeModule: JarvisModuleType?
    @State private var hoveredModule: JarvisModuleType?

    var body: some View {
        ZStack {
            JarvisBackgroundView(systemState: systemState)

            if activeModule == nil {
                moduleLayer
                    .transition(.opacity)
            }

            JarvisCoreView(state: systemState)
                .scaleEffect(activeModule == nil ? 1.0 : 0.55)
                .offset(x: activeModule == nil ? 0 : -360)
                .animation(.spring(response: 0.65, dampingFraction: 0.82), value: activeModule)

            if let module = activeModule {
                JarvisBackendWorkspaceView(core: core, module: module) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                        activeModule = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(20)
            }

            header
            commandBar
        }
        .preferredColorScheme(.dark)
        .task { await core.boot() }
    }

    private var systemState: JarvisSystemState {
        if core.updateStatus.contains("%") {
            let digits = core.updateStatus.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
            return .updating(progress: (digits.first ?? 0) / 100.0)
        }
        if core.developmentStatus.contains("CLAUDE") ||
            core.claudeCodeStatus.contains("PROGRAMMIERT") ||
            (core.developmentProgress > 0.05 && core.developmentProgress < 0.95) {
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
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ForEach(Array(JarvisModuleType.allCases.enumerated()), id: \.element.id) { index, module in
                let angle = CGFloat(index) * (2 * CGFloat.pi / CGFloat(JarvisModuleType.allCases.count)) - CGFloat.pi / 2
                let rx = min(geo.size.width * 0.35, 430)
                let ry = min(geo.size.height * 0.32, 285)
                let x = center.x + cos(angle) * rx
                let y = center.y + sin(angle) * ry

                JarvisModuleView(
                    type: module,
                    isActive: activeModule == module,
                    isHovered: hoveredModule == module
                ) {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
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
        .padding(.horizontal, 40)
        .padding(.vertical, 70)
    }

    private var header: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("J.A.R.V.I.S.")
                        .font(.system(size: 22, weight: .ultraLight, design: .rounded))
                        .tracking(7)
                    Text("NEURALES STEUERSYSTEM // CLAUDE HUD")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.6)
                        .opacity(0.55)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(core.status)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text("ROUTE // \(core.lastRoute)")
                        .font(.system(size: 8, design: .monospaced))
                        .opacity(0.55)
                }
            }
            .foregroundStyle(.cyan)
            .padding(22)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var commandBar: some View {
        VStack {
            Spacer()
            VStack(spacing: 7) {
                if !core.transcript.isEmpty {
                    Text(core.transcript)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    Image(systemName: core.listening ? "waveform" : "mic")
                        .foregroundStyle(.cyan)
                    TextField("Mit Jarvis sprechen oder Befehl eingeben …", text: $input)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit { send() }
                    Button(action: send) {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 16)
                .frame(width: 560, height: 44)
                .background(.black.opacity(0.80))
                .overlay(Capsule().stroke(.cyan.opacity(0.35), lineWidth: 1))
                .clipShape(Capsule())

                HStack(spacing: 16) {
                    Text("STIMME \(core.listening ? "AKTIV" : "STANDBY")")
                    Text("KI \(core.localAI ? core.localAIModel : "OFFLINE")")
                    Text("CLAUDE \(core.claudeCodeAvailable ? "BEREIT" : "OFFLINE")")
                    Text("UPDATE \(core.updateStatus)")
                }
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.45))
            }
            .padding(.bottom, 18)
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        core.submit(text)
    }
}

struct JarvisBackendWorkspaceView: View {
    @ObservedObject var core: JarvisCore
    let module: JarvisModuleType
    let onClose: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 430)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: module.icon).foregroundStyle(.cyan)
                    Text("\(module.rawValue) INTERFACE")
                        .font(.system(size: 20, weight: .light, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                Rectangle().fill(.cyan.opacity(0.25)).frame(height: 1)
                content
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: 760, maxHeight: 560)
            .background(.black.opacity(0.90))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.42), lineWidth: 1))
            .shadow(color: .cyan.opacity(0.18), radius: 28)
            .padding(.trailing, 38)
        }
        .padding(.vertical, 90)
    }

    @ViewBuilder private var content: some View {
        switch module {
        case .mac:
            VStack(alignment: .leading, spacing: 12) {
                title("MAC-STEUERUNG", "Direkte lokale Aktionen")
                HStack {
                    appButton("Safari", "com.apple.Safari", "safari")
                    appButton("Finder", "com.apple.finder", "folder")
                    appButton("Mail", "com.apple.mail", "envelope")
                    appButton("Kalender", "com.apple.iCal", "calendar")
                }
            }

        case .ai:
            VStack(alignment: .leading, spacing: 10) {
                title("LOKALE KI", core.localAI ? core.localAIModel : "Nicht verbunden")
                row("OLLAMA", core.localAI ? "VERBUNDEN" : "NICHT BEREIT")
                row("ROUTER", core.lastRoute)
                row("SETUP", core.aiSetupStatus)
                if !core.localAI {
                    Button(core.aiInstalling ? "KI WIRD EINGERICHTET …" : "KI EINRICHTEN") {
                        core.confirmAndSetupAI()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(core.aiInstalling)
                }
            }

        case .claude:
            VStack(alignment: .leading, spacing: 10) {
                title("CLAUDE CODE", "Entwickler-KI")
                row("VERBINDUNG", core.claudeCodeAvailable ? "BEREIT" : "NICHT BEREIT")
                row("STATUS", core.claudeCodeStatus)
                row("ENTWICKLUNG", core.developmentStatus)
                Button(core.developerMode ? "ENTWICKLERMODUS BEENDEN" : "ENTWICKLERMODUS STARTEN") {
                    core.developerMode ? core.leaveDeveloperMode() : core.enterDeveloperMode()
                }
                .buttonStyle(.bordered)
                .tint(core.developerMode ? .green : .cyan)
            }

        case .internet:
            VStack(alignment: .leading, spacing: 10) {
                title("INTERNET", "Web-Routing und öffentliche Informationen")
                row("STATUS", core.internetStatus)
                row("LETZTE ROUTE", core.lastRoute)
                Button("SAFARI ÖFFNEN") {
                    Task { await core.openBundle("com.apple.Safari", "Safari") }
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }

        case .memory:
            VStack(alignment: .leading, spacing: 10) {
                title("GEDÄCHTNIS", "Lokaler Jarvis-Speicher")
                row("EINTRÄGE", "\(core.memoryCount)")
                Text("„Merke dir …“ speichert weiterhin lokal im bestehenden JarvisCore.")
                    .foregroundStyle(.white.opacity(0.62))
            }

        case .devices:
            VStack(alignment: .leading, spacing: 10) {
                title("GERÄTE", "Sichere Kopplung")
                row("PAIRING", "NOCH NICHT IMPLEMENTIERT")
                Text("Keine simulierte Verbindung: Das Modul meldet erst Erfolg, wenn eine echte Gegenstelle vorhanden ist.")
                    .foregroundStyle(.white.opacity(0.62))
            }

        case .automation:
            VStack(alignment: .leading, spacing: 10) {
                title("AUTOMATION", "Lokale Routinen")
                row("STATUS", "VORBEREITET")
                Text("Bestehende Jarvis-Aktionen bleiben über Sprache und Texteingabe verfügbar.")
                    .foregroundStyle(.white.opacity(0.62))
            }

        case .system:
            VStack(alignment: .leading, spacing: 10) {
                title("SYSTEM", "Sprache und Kernstatus")
                row("STATUS", core.status)
                row("STIMME", core.voiceLabel)
                row("DAUERHÖREN", core.continuous ? "AKTIV" : "AUS")
                Button(core.continuous ? "DAUERHÖREN AUSSCHALTEN" : "DAUERHÖREN EINSCHALTEN") {
                    core.continuous.toggle()
                    core.continuous ? core.startListening() : core.stopListening()
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }

        case .update:
            VStack(alignment: .leading, spacing: 10) {
                title("UPDATE", "Stabiler GitHub-Updatekanal")
                row("STATUS", core.updateStatus)
                row("NEUE VERSION", core.latestVersion)
                Button("NACH UPDATE SUCHEN") {
                    Task { await core.checkForUpdates() }
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                if core.updateAvailable {
                    Button("UPDATE INSTALLIEREN") {
                        core.confirmAndInstallUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }
            }

        case .dev:
            VStack(alignment: .leading, spacing: 10) {
                title("ENTWICKLUNG", "Claude Single-Pass Entwicklung")
                row("STATUS", core.developmentStatus)
                row("CLAUDE", core.claudeCodeStatus)
                ProgressView(value: core.developmentProgress).tint(.cyan)
                Text("\(core.developmentProgressText) // \(Int(core.developmentProgress * 100)) %")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Button(core.developerMode ? "ENTWICKLERMODUS BEENDEN" : "ENTWICKLERMODUS STARTEN") {
                    core.developerMode ? core.leaveDeveloperMode() : core.enterDeveloperMode()
                }
                .buttonStyle(.bordered)
                .tint(core.developerMode ? .green : .cyan)
                if core.candidateReady {
                    Button("GEPRÜFTEN KANDIDATEN INSTALLIEREN") {
                        core.installDeveloperCandidate()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
    }

    private func title(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
            Text(subtitle)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(value).foregroundStyle(.cyan)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.62))
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
        .buttonStyle(.bordered)
        .tint(.cyan)
    }
}

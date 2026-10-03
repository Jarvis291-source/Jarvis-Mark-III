import SwiftUI

enum JarvisSystemState: Equatable {
    case ready
    case listening
    case thinking
    case speaking
    case programming
    case updating(progress: Double)
    case error
}

enum JarvisModuleType: String, CaseIterable, Identifiable {
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
    
    var id: String { self.rawValue }
    
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
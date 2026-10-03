import SwiftUI

struct JarvisWorkspaceView: View {
    let module: JarvisModuleType
    var onClose: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Text("\(module.rawValue) INTERFACE")
                        .font(.system(size: 24, weight: .light, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").foregroundColor(.white)
                    }.buttonStyle(PlainButtonStyle())
                }
                .padding(30)
                
                Spacer()
                
                Text("SYSTEM MODUL AKTIV: \(module.rawValue)")
                    .font(.system(size: 18, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
            }
            .padding(40)
        }
        .transition(.opacity)
    }
}

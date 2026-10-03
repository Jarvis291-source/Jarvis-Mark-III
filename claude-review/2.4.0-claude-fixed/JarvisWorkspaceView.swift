import SwiftUI

struct JarvisWorkspaceView: View {
    let module: JarvisModuleType
    var onClose: () -> Void
    
    var body: some View {
        ZStack {
            // Dark overlay
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    HStack {
                        Image(systemName: module.icon)
                            .foregroundColor(.cyan)
                        Text("\(module.rawValue) INTERFACE")
                            .font(.system(size: 20, weight: .light, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white.opacity(0.5))
                            .padding(8)
                            .background(Circle().stroke(Color.white.opacity(0.2)))
                    }.buttonStyle(PlainButtonStyle())
                }
                .padding(30)
                .background(Color.cyan.opacity(0.05))
                
                // Main Workspace Area
                ZStack {
                    // Technical Grid Background
                    JarvisGridBackground()
                    
                    VStack {
                        Text("INITIALIZING \(module.rawValue) SUB-SYSTEM...")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.7))
                            .padding(.top, 100)
                        
                        Spacer()
                        
                        // Placeholder for real backend content
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                            .background(Color.cyan.opacity(0.02))
                            .frame(maxWidth: 800, maxHeight: 400)
                            .overlay(
                                Text("Connect to JarvisCore.\(module.rawValue) bindings required.")
                                    .foregroundColor(.white.opacity(0.3))
                                    .font(.system(size: 12, design: .monospaced))
                            )
                        
                        Spacer()
                    }
                }
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
    }
}

struct JarvisGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 40
            for x in stride(from: 0, to: size.width, by: step) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.cyan.opacity(0.05)), lineWidth: 1)
            }
            for y in stride(from: 0, to: size.height, by: step) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.cyan.opacity(0.05)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }
}
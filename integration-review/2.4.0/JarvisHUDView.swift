import SwiftUI

struct JarvisHUDView: View {
    @Binding var systemState: JarvisSystemState
    @ObservedObject var voiceController: JarvisVoiceController
    
    @State private var activeModule: JarvisModuleType? = nil
    @State private var hoveredModule: JarvisModuleType? = nil
    @State private var inputText: String = ""
    
    var body: some View {
        ZStack {
            // Layer 1: Living Background
            JarvisBackgroundView(systemState: systemState)
            
            // Layer 2: Connections
            if let hovered = hoveredModule {
                ConnectionLinesView(to: hovered, systemState: systemState)
            }
            
            // Layer 3: Modules Layout
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                
                ForEach(JarvisModuleType.allCases, id: \.self) { module in
                    let angle = getAngle(for: module)
                    let radius: CGFloat = activeModule == nil ? 300 : 450
                    let x = center.x + cos(angle) * radius
                    let y = center.y + sin(angle) * radius
                    
                    JarvisModuleView(
                        type: module,
                        isActive: activeModule == module,
                        isHovered: hoveredModule == module,
                        action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                activeModule = module
                            }
                        }
                    )
                    .position(x: x, y: y)
                    .onHover { hovering in
                        hoveredModule = hovering ? module : nil
                    }
                }
            }
            
            // Layer 4: The Core
            JarvisCoreView(state: systemState)
                .scaleEffect(activeModule == nil ? 1.0 : 0.5)
                .offset(x: activeModule == nil ? 0 : -300) // Move core to side when workspace open
                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: activeModule)
            
            // Layer 5: Workspace
            if let module = activeModule {
                JarvisWorkspaceView(module: module, onClose: {
                    withAnimation(.spring()) {
                        activeModule = nil
                    }
                })
            }
            
            // Layer 6: Minimal Input
            VStack {
                Spacer()
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 15)
                    
                    TextField("Awaiting voice command...", text: $inputText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                        .font(.system(size: 14, design: .monospaced))
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 15)
                }
                .frame(width: 450, height: 44)
                .background(
                    Capsule()
                        .fill(Color.cyan.opacity(0.05))
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.2), lineWidth: 1))
                )
                .padding(.bottom, 30)
            }
        }
    }
    
    func getAngle(for module: JarvisModuleType) -> CGFloat {
        let index = JarvisModuleType.allCases.firstIndex(of: module) ?? 0
        return CGFloat(index) * (2 * .pi / CGFloat(JarvisModuleType.allCases.count))
    }
}

struct ConnectionLinesView: View {
    let to: JarvisModuleType
    var systemState: JarvisSystemState
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let index = JarvisModuleType.allCases.firstIndex(of: to) ?? 0
                let angle = CGFloat(index) * (2 * .pi / CGFloat(JarvisModuleType.allCases.count))
                let radius: CGFloat = 300
                let target = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                
                var path = Path()
                path.move(to: center)
                path.addLine(to: target)
                
                let opacity = systemState == .thinking ? 0.6 : 0.3
                context.stroke(path, with: .color(.cyan.opacity(opacity)), lineWidth: 1)
                
                // Animated data pulse on the line
                let time = timeline.date.timeIntervalSinceReferenceDate
                let pulsePos = (time.truncatingRemainder(dividingBy: 2)) / 2
                let px = center.x + (target.x - center.x) * CGFloat(pulsePos)
                let py = center.y + (target.y - center.y) * CGFloat(pulsePos)
                context.fill(Path(ellipseIn: CGRect(x: px-2, y: py-2, width: 4, height: 4)), with: .color(.white))
            }
            .ignoresSafeArea()
        }
    }
}
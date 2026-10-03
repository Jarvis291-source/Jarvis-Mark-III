import SwiftUI

struct JarvisHUDView: View {
    @ObservedObject var core: JarvisCore
    @State private var hoveredModule: JarvisModuleType? = nil
    
    var body: some View {
        ZStack {
            JarvisParticleField(systemState: core.systemState)
            
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                
                ForEach(JarvisModuleType.allCases) { module in
                    let angle = CGFloat(JarvisModuleType.allCases.firstIndex(of: module)!) * (2 * .pi / CGFloat(JarvisModuleType.allCases.count))
                    let radius: CGFloat = core.activeModule == nil ? 300 : 400
                    
                    JarvisModuleView(
                        type: module,
                        isActive: core.activeModule == module,
                        isHovered: hoveredModule == module,
                        action: {
                            withAnimation(.spring()) {
                                core.setModule(module == core.activeModule ? nil : module)
                            }
                        }
                    )
                    .position(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    .onHover { hovering in
                        hoveredModule = hovering ? module : nil
                    }
                }
            }
            
            JarvisCoreView(state: core.systemState)
                .scaleEffect(core.activeModule == nil ? 1.0 : 0.6)
                .offset(x: core.activeModule == nil ? 0 : -250)
                .animation(.spring(), value: core.activeModule)
            
            if let module = core.activeModule {
                JarvisWorkspaceView(module: module, onClose: {
                    withAnimation(.spring()) {
                        core.setModule(nil)
                    }
                })
            }
        }
    }
}

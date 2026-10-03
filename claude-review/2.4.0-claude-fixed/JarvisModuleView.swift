import SwiftUI

struct JarvisModuleView: View {
    let type: JarvisModuleType
    var isActive: Bool
    var isHovered: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(isHovered ? Color.white.opacity(0.2) : Color.cyan.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: type.icon)
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(isHovered ? .white : .cyan)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.rawValue)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(isHovered ? .white : .cyan.opacity(0.8))
                    
                    if isHovered {
                        Text("SYS_READY // 0x4F")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: 180, height: 48)
            .background(
                ZStack {
                    // Holographic Glass
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.cyan.opacity(isHovered ? 0.15 : 0.05))
                    
                    // Technical Borders
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.cyan.opacity(isHovered ? 0.8 : 0.3), lineWidth: 1)
                    
                    // High-tech accents
                    if isHovered {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: 10)
                            .position(x: 0, y: 24)
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
}
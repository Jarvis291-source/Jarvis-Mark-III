import SwiftUI

struct JarvisModuleView: View {
    let type: JarvisModuleType
    var isActive: Bool
    var isHovered: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(isHovered ? Color.white.opacity(0.2) : Color.cyan.opacity(0.1)).frame(width: 30, height: 30)
                    Image(systemName: type.icon).foregroundColor(isHovered ? .white : .cyan).font(.system(size: 14))
                }
                Text(type.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(isHovered ? .white : .cyan.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: 160, height: 45)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Color.cyan.opacity(isHovered ? 0.2 : 0.05))
                    RoundedRectangle(cornerRadius: 2).stroke(Color.cyan.opacity(isHovered ? 0.8 : 0.3), lineWidth: 1)
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHovered ? 1.05 : 1.0)
    }
}

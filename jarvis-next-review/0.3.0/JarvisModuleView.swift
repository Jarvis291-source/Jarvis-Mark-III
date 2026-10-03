import SwiftUI

struct JarvisModuleView: View {
    let type: JarvisModuleType
    var isActive: Bool
    var isHovered: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {

import SwiftUI

struct JarvisWorkspaceView: View {
    let module: JarvisModuleType
    var onClose: () -> Void
    var core: JarvisCore
    
    var body: some View {

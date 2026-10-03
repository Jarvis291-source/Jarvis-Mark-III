import SwiftUI

@main
struct JarvisZeroApp: App {
    @StateObject private var core = JarvisCore.shared
    
    var body: some Scene {
        WindowGroup {
            JarvisHUDView(core: core)
                .frame(minWidth: 1100, minHeight: 750)
                .preferredColorScheme(.dark)
                .onAppear {
                    core.speechRecognizer.startListening()
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

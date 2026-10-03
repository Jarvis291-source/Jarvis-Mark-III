import SwiftUI

struct JarvisMainContainer: View {
    @State private var systemState: JarvisSystemState = .ready
    @StateObject private var voiceController = JarvisVoiceController()
    
    var body: some View {
        JarvisHUDView(systemState: $systemState, voiceController: voiceController)
            .frame(minWidth: 1100, minHeight: 750)
            .preferredColorScheme(.dark)
            .onAppear {
                // Verknüpfe VoiceController mit dem State
                voiceController.onStateChange = { newState in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.systemState = newState
                    }
                }
            }
    }
}
import SwiftUI

struct JarvisHUDView: View {
    @ObservedObject var core: JarvisCore
    @State private var hoveredModule: JarvisModuleType? = nil
    
    var body: some View {

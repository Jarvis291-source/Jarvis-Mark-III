import SwiftUI

struct JarvisCoreView: View {
    var state: JarvisSystemState
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                var color = Color(red: 0, green: 0.8, blue: 1.0)
                var pulse = 1.0
                var rotationSpeed = 0.4
                
                switch state {
                case .ready: rotationSpeed = 0.2
                case .listening: 
                    pulse = 1.0 + sin(time * 5) * 0.1
                    rotationSpeed = 0.6
                case .thinking: 
                    rotationSpeed = 2.0
                    color = .white
                case .speaking: 
                    pulse = 1.0 + sin(time * 10) * 0.2
                    rotationSpeed = 0.5
                case .working: rotationSpeed = 1.2
                case .updating: rotationSpeed = 0.1
                case .error: color = .orange
                }
                
                // LAYER 1: Energy Core
                context.fill(Path(ellipseIn: CGRect(x: center.x - 40*pulse, y: center.y - 40*pulse, width: 80*pulse, height: 80*pulse)), 
                             with: .color(color.opacity(0.3)))
                
                // LAYER 2: Rotating Rings
                for r in 1...3 {
                    let radius = CGFloat(r * 50) * pulse
                    let angleOffset = time * rotationSpeed * (1.0 / CGFloat(r))
                    
                    for i in 0..<12 {
                        let angle = angleOffset + (CGFloat(i) * CGFloat.pi * 2 / 12)
                        let px = center.x + cos(angle) * radius
                        let py = center.y + sin(angle) * radius
                        context.fill(Path(ellipseIn: CGRect(x: px-2, y: py-2, width: 4, height: 4)), with: .color(color.opacity(0.6)))
                    }
                }
                
                // LAYER 3: Particle Shell
                for i in 0..<100 {
                    let angle = CGFloat(i) * CGFloat.pi * 2 / 100
                    let phi = CGFloat(i) * CGFloat.pi / 10
                    let x3d = cos(angle + time * rotationSpeed) * sin(phi)
                    let y3d = cos(phi)
                    let z3d = sin(angle + time * rotationSpeed) * sin(phi)
                    
                    let px = center.x + x3d * 120 * pulse
                    let py = center.y + y3d * 120 * pulse
                    context.fill(Path(ellipseIn: CGRect(x: px-1, y: py-1, width: 2, height: 2)), 
                                 with: .color(color.opacity((z3d + 1) / 2)))
                }
            }
        }
        .frame(width: 400, height: 400)
    }
}

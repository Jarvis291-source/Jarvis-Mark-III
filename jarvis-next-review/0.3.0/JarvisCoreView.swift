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
                
                context.fill(Path(ellipseIn: CGRect(x: center.x - 50*pulse, y: center.y - 50*pulse, width: 100*pulse, height: 100*pulse)), 
                             with: .color(color.opacity(0.2)))
                
                for r in 1...4 {
                    let radius = CGFloat(r * 45) * pulse
                    let angleOffset = time * rotationSpeed * (1.0 / CGFloat(r))
                    for i in 0..<16 {
                        let angle = angleOffset + (CGFloat(i) * CGFloat.pi * 2 / 16)
                        let px = center.x + cos(angle) * radius
                        let py = center.y + sin(angle) * radius
                        context.fill(Path(ellipseIn: CGRect(x: px-1, y: py-1, width: 2, height: 2)), with: .color(color.opacity(0.5)))
                    }
                }
                
                for i in 0..<100 {
                    let angle = CGFloat(i) * CGFloat.pi * 2 / 100
                    let phi = CGFloat(i) * CGFloat.pi / 10
                    let x3d = cos(angle + time * rotationSpeed) * sin(phi)
                    let y3d = cos(phi)
                    let z3d = sin(angle + time * rotationSpeed) * sin(phi)
                    let px = center.x + x3d * 120 * pulse
                    let py = center.y + y3d * 120 * pulse
                    context.fill(Path(ellipseIn: CGRect(x: px-0.5, y: py-0.5, width: 1, height: 1)), 
                                 with: .color(color.opacity((z3d + 1) / 2)))
                }
            }
        }
        .frame(width: 400, height: 400)
    }
}

import SwiftUI

struct JarvisCoreView: View {
    var state: JarvisSystemState
    
    var body: some View {
        TimelineView<TimelineView.AnimationSchedule>(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // State Parameters
                var coreColor = Color(red: 0, green: 0.8, blue: 1.0)
                var pulse = 1.0
                var speed = 0.5
                
                switch state {
                case .ready: speed = 0.3
                case .listening: 
                    pulse = 1.0 + sin(time * 4) * 0.1
                    speed = 0.7
                case .thinking: 
                    speed = 2.5
                    coreColor = .white
                case .speaking: 
                    pulse = 1.0 + sin(time * 8) * 0.2
                    speed = 0.8
                case .programming: 
                    speed = 1.2
                    coreColor = .white
                case .updating: speed = 0.2
                case .error: coreColor = .orange
                }
                
                // LAYER 1: Deep Core Glow
                let innerGlow = Path(ellipseIn: CGRect(x: center.x - 30 * pulse, y: center.y - 30 * pulse, width: 60 * pulse, height: 60 * pulse))
                context.fill(innerGlow, with: .color(coreColor.opacity(0.4)))
                
                // LAYER 2: Rotating Data Rings (Outer)
                for ringIdx in 1...3 {
                    let ringRadius = CGFloat(ringIdx * 40) * pulse
                    let ringSpeed = speed * (1.0 / CGFloat(ringIdx))
                    let ringAngle = time * ringSpeed
                    
                    for i in 0..<12 {
                        let angle = ringAngle + (CGFloat(i) * CGFloat.pi * 2.0 / 12.0)
                        let px = center.x + cos(angle) * ringRadius
                        let py = center.y + sin(angle) * ringRadius
                        
                        context.fill(Path(ellipseIn: CGRect(x: px-2, y: py-2, width: 4, height: 4)), with: .color(coreColor.opacity(0.6)))
                        
                        // Connect to core
                        var line = Path()
                        line.move(to: CGPoint(x: px, y: py))
                        line.addLine(to: center)
                        context.stroke(line, with: .color(coreColor.opacity(0.1)), lineWidth: 0.5)
                    }
                }
                
                // LAYER 3: 3D Particle Shell
                let particleCount = 150
                for i in 0..<particleCount {
                    let angle = CGFloat(i) * CGFloat.pi * 2 / CGFloat(particleCount)
                    let phi = CGFloat(i) * CGFloat.pi / 15
                    
                    let x3d = cos(angle + time * speed) * sin(phi)
                    let y3d = cos(phi)
                    let z3d = sin(angle + time * speed) * sin(phi)
                    
                    let projectX = center.x + x3d * 100 * pulse
                    let projectY = center.y + y3d * 100 * pulse
                    let opacity = (z3d + 1) / 2
                    
                    let size = z3d > 0 ? 2.0 : 1.0
                    context.fill(Path(ellipseIn: CGRect(x: projectX - size/2, y: projectY - size/2, width: size, height: size)), 
                                 with: .color(coreColor.opacity(opacity * 0.7)))
                }
                
                // LAYER 4: Energy Orbits
                let orbitRadius: CGFloat = 130 * pulse
                let orbitTime = time * speed * 1.5
                let ox = center.x + cos(orbitTime) * orbitRadius
                let oy = center.y + sin(orbitTime) * orbitRadius
                context.fill(Path(ellipseIn: CGRect(x: ox-4, y: oy-4, width: 8, height: 8)), with: .color(.white.opacity(0.8)))
                
                // LAYER 5: State-specific overlays
                if case .updating(let progress) = state {
                    var progressPath = Path()
                    progressPath.addArc(center: center, radius: 140, startAngle: .degrees(0), endAngle: .degrees(progress * 360), clockwise: false)
                    context.stroke(progressPath, with: .color(.cyan), lineWidth: 3)
                }
                
                if case .error = state {
                    // Glitch effect
                    let glitchOffset = CGFloat.random(in: -5...5)
                    context.fill(Path(rect: CGRect(x: center.x + glitchOffset, y: center.y - 50, width: 100, height: 1)), with: .color(.orange.opacity(0.5)))
                }
            }
        }
        .frame(width: 400, height: 400)
    }
}
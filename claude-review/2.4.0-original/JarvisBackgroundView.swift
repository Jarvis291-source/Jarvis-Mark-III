import SwiftUI

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    var size: CGFloat
    var opacity: Double
    var layer: Int // Für Parallax-Tiefe
}

struct JarvisBackgroundView: View {
    @State private var particles: [Particle] = []
    var systemState: JarvisSystemState
    
    init(systemState: JarvisSystemState) {
        self.systemState = systemState
        _particles = State(initialValue: createParticles())
    }
    
    static func createParticles() -> [Particle] {
        var p: [Particle] = []
        for _ in 0..<120 {
            p.append(Particle(
                position: CGPoint(x: CGFloat.random(in: 0...1200), y: CGFloat.random(in: 0...800)),
                velocity: CGPoint(x: CGFloat.random(in: -0.2...0.2), y: CGFloat.random(in: -0.2...0.2)),
                size: CGFloat.random(in: 0.5...2.0),
                opacity: Double.random(in: 0.1...0.4),
                layer: Int.random(in: 1...3)
            ))
        }
        return p
    }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // State-dependent drift
                var driftMultiplier: CGFloat = 1.0
                var color = Color.cyan.opacity(0.3)
                
                switch systemState {
                case .listening: driftMultiplier = 0.5; color = .white.opacity(0.4)
                case .thinking: driftMultiplier = 3.0; color = .cyan.opacity(0.6)
                case .speaking: driftMultiplier = 1.5; color = .white.opacity(0.5)
                case .error: color = .orange.opacity(0.4)
                default: driftMultiplier = 1.0
                }
                
                for i in 0..<particles.count {
                    var p = particles[i]
                    
                    // Update position based on velocity and time
                    let x = p.position.x + (p.velocity.x * time * 10 * CGFloat(p.layer) * driftMultiplier)
                    let y = p.position.y + (p.velocity.y * time * 10 * CGFloat(p.layer) * driftMultiplier)
                    
                    // Wrap around screen
                    let finalX = x.truncatingRemainder(dividingBy: size.width)
                    let finalY = y.truncatingRemainder(dividingBy: size.height)
                    
                    // Subtle twinkle
                    let twinkle = sin(time * 2 + Double(i)) * 0.1 + p.opacity
                    
                    let rect = CGRect(x: finalX, y: finalY, width: p.size, height: p.size)
                    context.fill(Path(rect), with: .color(color.opacity(twinkle)))
                    
                    // Rare connection lines
                    if i % 30 == 0 && systemState == .thinking {
                        if let next = particles.last {
                            var path = Path()
                            path.move(to: CGPoint(x: finalX, y: finalY))
                            path.addLine(to: CGPoint(x: size.width/2, y: size.height/2))
                            context.stroke(path, with: .color(.cyan.opacity(0.05)), lineWidth: 0.5)
                        }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .background(Color.black)
    }
}
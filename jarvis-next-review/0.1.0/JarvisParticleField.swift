import SwiftUI

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    var size: CGFloat
    var opacity: Double
    var layer: Int
}

struct JarvisParticleField: View {
    var systemState: JarvisSystemState
    
    @State private var particles: [Particle] = (0..<150).map { _ in
        Particle(
            position: CGPoint(x: CGFloat.random(in: 0...1200), y: CGFloat.random(in: 0...800)),
            velocity: CGPoint(x: CGFloat.random(in: -0.1...0.1), y: CGFloat.random(in: -0.1...0.1)),
            size: CGFloat.random(in: 0.5...2.0),
            opacity: Double.random(in: 0.1...0.4),
            layer: Int.random(in: 1...3)
        )
    }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                var drift: CGFloat = 1.0
                
                switch systemState {
                case .listening: drift = 0.5
                case .thinking: drift = 2.5
                case .speaking: drift = 1.2
                default: drift = 1.0
                }
                
                for i in 0..<particles.count {
                    var p = particles[i]
                    let x = p.position.x + (p.velocity.x * time * 15 * CGFloat(p.layer) * drift)
                    let y = p.position.y + (p.velocity.y * time * 15 * CGFloat(p.layer) * drift)
                    
                    let finalX = x.truncatingRemainder(dividingBy: size.width)
                    let finalY = y.truncatingRemainder(dividingBy: size.height)
                    
                    context.fill(Path(ellipseIn: CGRect(x: finalX, y: finalY, width: p.size, height: p.size)), 
                                 with: .color(.cyan.opacity(p.opacity)))
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

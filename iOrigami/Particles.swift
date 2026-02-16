import SwiftUI

struct Particle: Identifiable, Hashable {
    let id = UUID()
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var color: Color
    var size: Double
    var opacity: Double = 1.0
    var scale: Double = 1.0
}

class ParticleSystem: ObservableObject {
    @Published var particles: [Particle] = []

    func emit(count: Int, center: CGPoint, color: Color = .blue) {
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 2...10)
            let p = Particle(
                x: center.x,
                y: center.y,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                color: color,
                size: Double.random(in: 4...10)
            )
            particles.append(p)
        }
    }

    func update() {
        for i in indices(particles) {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].vy += 0.2  // Gravity
            particles[i].opacity -= 0.02
            particles[i].scale *= 0.95
        }
        particles.removeAll { $0.opacity <= 0 }
    }

    private func indices(_ particles: [Particle]) -> Range<Int> {
        return 0..<particles.count
    }
}

struct ParticleOverlay: View {
    @StateObject var system = ParticleSystem()
    let timer = Timer.publish(every: 1 / 60, on: .main, in: .common).autoconnect()

    // Triggers
    var triggerFold: Int
    var triggerPuff: Bool

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for p in system.particles {
                    let rect = CGRect(
                        x: p.x - p.size / 2, y: p.y - p.size / 2, width: p.size, height: p.size)
                    context.opacity = p.opacity
                    context.fill(Path(ellipseIn: rect), with: .color(p.color))
                }
            }
            .onReceive(timer) { _ in
                system.update()
            }
            .onChange(of: triggerFold) { _, _ in
                let center = CGPoint(
                    x: geo.size.width / 2, y: geo.size.height / 2)
                system.emit(count: 20, center: center, color: .orange)
            }
            .onChange(of: triggerPuff) { _, newValue in
                let center = CGPoint(
                    x: geo.size.width / 2, y: geo.size.height / 2)
                if newValue {
                    system.emit(count: 40, center: center, color: .cyan)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

import CoreGraphics

/// A fly that buzzes around the cat until it is caught or escapes.
@MainActor
final class Fly {
    private(set) var pos: CGPoint
    private var vel = CGVector.zero
    private let home: CGPoint
    private let scale: CGFloat
    private var age: CGFloat = 0
    private var fleeing = false
    private(set) var gone = false
    /// Flips every frame, for the wing flicker.
    private(set) var wingsUp = false

    init(home: CGPoint, scale: CGFloat) {
        self.home = home
        self.scale = scale
        pos = CGPoint(x: home.x + .random(in: -30...30) * scale, y: home.y + .random(in: -10...20) * scale)
    }

    func update(_ dt: CGFloat) {
        age += dt
        wingsUp.toggle()
        if fleeing {
            vel.dy += 260 * scale * dt
            pos.x += vel.dx * dt
            pos.y += vel.dy * dt
            if age > 2.2 { gone = true }
            return
        }
        // An erratic orbit around home: two slow waves and two fast ones.
        let s = scale
        let target = CGPoint(x: home.x + (sin(age * 1.7) * 60 + sin(age * 5.3) * 18) * s,
                             y: home.y + (cos(age * 1.3) * 30 + sin(age * 7.1) * 12) * s)
        vel.dx += (target.x - pos.x) * 9 * dt - vel.dx * 2.5 * dt
        vel.dy += (target.y - pos.y) * 9 * dt - vel.dy * 2.5 * dt
        pos.x += vel.dx * dt + .random(in: -0.6...0.6) * s
        pos.y += vel.dy * dt + .random(in: -0.6...0.6) * s
        if age > 40 { flee(from: home) }
    }

    func flee(from p: CGPoint) {
        guard !fleeing else { return }
        fleeing = true
        age = 0
        vel = CGVector(dx: (pos.x >= p.x ? 1 : -1) * 260 * scale, dy: 160 * scale)
    }
}

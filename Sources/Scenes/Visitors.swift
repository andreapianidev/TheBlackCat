import AppKit

/// Something that comes to visit the cat for a short scene: a bird, a dog, a toy.
/// Units are points at scale 1, around `pos`, x pointing where it faces, y up.
@MainActor
class Visitor {
    var pos: CGPoint
    var facing: CGFloat = 1
    var done = false
    var t: CGFloat = 0
    var alpha: CGFloat = 1
    let scale: CGFloat

    /// What the drawing covers, in visitor units around `pos`.
    var bounds: CGRect { CGRect(x: -30, y: -5, width: 60, height: 50) }
    /// Drawn in front of the cat (a box the cat sits in).
    var inFront: Bool { false }
    /// A rectangle the cat can stand on, in global coordinates.
    var platform: CGRect? { nil }

    init(at p: CGPoint, scale: CGFloat) {
        pos = p
        self.scale = scale
    }

    func update(_ dt: CGFloat) { t += dt }
    /// Drawn mirrored with `facing`.
    func draw(_ ctx: CGContext) {}
    /// Drawn without mirroring, for text.
    func drawOverlay(_ ctx: CGContext) {}

    static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    static func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
    }

    /// Big comic lettering, cached per word.
    private static var words: [String: CGImage] = [:]
    static func shout(_ ctx: CGContext, _ text: String, at p: CGPoint, size: CGFloat) {
        let img: CGImage
        if let cached = words[text] {
            img = cached
        } else {
            let font = NSFont(name: "Chalkboard SE Bold", size: 48) ?? NSFont.systemFont(ofSize: 48, weight: .heavy)
            let a = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black,
                                                                   .strokeColor: NSColor.white, .strokeWidth: -4])
            let sz = a.size()
            guard let bm = CGContext(data: nil, width: Int(sz.width) + 8, height: Int(sz.height) + 8, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: bm, flipped: false)
            a.draw(at: CGPoint(x: 4, y: 4))
            NSGraphicsContext.restoreGraphicsState()
            guard let made = bm.makeImage() else { return }
            words[text] = made
            img = made
        }
        let k = size / 48
        let w = CGFloat(img.width) * k, h = CGFloat(img.height) * k
        ctx.draw(img, in: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h))
    }
}

// MARK: - Bird

final class Bird: Visitor {
    enum State { case flyingIn, perched, fleeing }
    private(set) var state = State.flyingIn
    private let landing: CGPoint
    private var vel = CGVector.zero
    private var nextHop: CGFloat = 1
    private(set) var perchedFor: CGFloat = 0

    override var bounds: CGRect { CGRect(x: -24, y: -4, width: 48, height: 38) }

    init(from start: CGPoint, landing: CGPoint, scale: CGFloat) {
        self.landing = landing
        super.init(at: start, scale: scale)
        facing = landing.x >= start.x ? 1 : -1
    }

    func flee(from x: CGFloat) {
        guard state != .fleeing else { return }
        state = .fleeing
        facing = pos.x >= x ? 1 : -1
        vel = CGVector(dx: facing * 240 * scale, dy: 280 * scale)
    }

    override func update(_ dt: CGFloat) {
        super.update(dt)
        switch state {
        case .flyingIn:
            let dx = landing.x - pos.x, dy = landing.y - pos.y
            let d = hypot(dx, dy), v = 240 * scale
            if d < v * dt + 1 {
                pos = landing
                state = .perched
            } else {
                pos.x += dx / d * v * dt
                pos.y += dy / d * v * dt + sin(t * 9) * 0.8 * scale
            }
        case .perched:
            perchedFor += dt
            nextHop -= dt
            if nextHop <= 0 {
                nextHop = .random(in: 0.5...1.4)
                if Bool.random() { facing = -facing }
                pos.x += facing * .random(in: 3...9) * scale
            }
        case .fleeing:
            vel.dy += 60 * scale * dt
            pos.x += vel.dx * dt
            pos.y += vel.dy * dt
        }
    }

    override func draw(_ ctx: CGContext) {
        let flying = state != .perched
        let peck = state == .perched ? max(0, sin(t * 6)) : 0
        ctx.setFillColor(Self.c(0.38, 0.28, 0.2))
        ctx.move(to: CGPoint(x: -8, y: 10)); ctx.addLine(to: CGPoint(x: -18, y: 15)); ctx.addLine(to: CGPoint(x: -17, y: 8)); ctx.closePath()
        ctx.fillPath()
        if !flying {
            ctx.setStrokeColor(Self.c(0.45, 0.3, 0.15))
            ctx.setLineWidth(1.2)
            ctx.move(to: CGPoint(x: -1, y: 4)); ctx.addLine(to: CGPoint(x: -1, y: 0))
            ctx.move(to: CGPoint(x: 2, y: 4)); ctx.addLine(to: CGPoint(x: 2, y: 0))
            ctx.strokePath()
        }
        ctx.setFillColor(Self.c(0.55, 0.42, 0.3))
        ctx.fillEllipse(in: Self.oval(0, 10, 19, 12))
        ctx.setFillColor(Self.c(0.88, 0.78, 0.62))
        ctx.fillEllipse(in: Self.oval(2, 8, 12, 7))
        let hy = 15 - 4 * peck
        ctx.setFillColor(Self.c(0.5, 0.36, 0.25))
        ctx.fillEllipse(in: Self.oval(8, hy, 11, 10))
        ctx.setFillColor(Self.c(0.96, 0.62, 0.18))
        ctx.move(to: CGPoint(x: 12.5, y: hy + 0.8)); ctx.addLine(to: CGPoint(x: 17.5, y: hy - 0.6 - peck)); ctx.addLine(to: CGPoint(x: 12.5, y: hy - 1.6)); ctx.closePath()
        ctx.fillPath()
        ctx.setFillColor(Self.c(0, 0, 0))
        ctx.fillEllipse(in: Self.oval(10, hy + 1.5, 2.2, 2.2))
        ctx.setFillColor(Self.c(1, 1, 1))
        ctx.fillEllipse(in: Self.oval(10.4, hy + 1.9, 0.7, 0.7))
        // Wing.
        ctx.saveGState()
        ctx.translateBy(x: -1, y: 12)
        ctx.rotate(by: flying ? sin(t * 28) * 0.9 : -0.15)
        ctx.setFillColor(Self.c(0.42, 0.31, 0.22))
        ctx.fillEllipse(in: Self.oval(-3, flying ? 4 : 0, 13, 6))
        ctx.restoreGState()
    }
}

// MARK: - Dog

final class Dog: Visitor {
    var speed: CGFloat = 0
    private var barking: CGFloat = 0
    private var phase: CGFloat = 0
    var sniffing = false

    override var bounds: CGRect { CGRect(x: -64, y: -4, width: 132, height: 96) }

    func bark() { barking = 0.6 }

    override func update(_ dt: CGFloat) {
        super.update(dt)
        pos.x += speed * dt
        if speed != 0 { facing = speed > 0 ? 1 : -1 }
        phase += abs(speed) * dt / (26 * scale)
        barking = max(0, barking - dt)
    }

    override func draw(_ ctx: CGContext) {
        let fur = Self.c(0.62, 0.42, 0.24), dark = Self.c(0.36, 0.22, 0.12), light = Self.c(0.88, 0.74, 0.55)
        let moving = speed != 0
        ctx.setLineCap(.round)
        // Legs.
        for (i, x) in [-28.0, -18.0, 18.0, 28.0].enumerated() {
            let swing = moving ? sin(phase + (i % 2 == 0 ? 0 : .pi)) * 7 : 0
            ctx.setStrokeColor(i % 2 == 0 ? dark : fur)
            ctx.setLineWidth(7)
            ctx.move(to: CGPoint(x: x, y: 26)); ctx.addLine(to: CGPoint(x: x + swing, y: 3)); ctx.strokePath()
            ctx.setFillColor(dark)
            ctx.fillEllipse(in: Self.oval(x + swing + 2, 2, 9, 5))
        }
        // Tail.
        let wag = sin(t * 14) * 8
        ctx.setStrokeColor(fur)
        ctx.setLineWidth(5)
        ctx.move(to: CGPoint(x: -40, y: 40)); ctx.addQuadCurve(to: CGPoint(x: -52 + wag * 0.3, y: 56 + wag), control: CGPoint(x: -50, y: 42))
        ctx.strokePath()
        // Body.
        ctx.setFillColor(fur)
        ctx.fillEllipse(in: Self.oval(-1, 36, 78, 28))
        ctx.setFillColor(light)
        ctx.fillEllipse(in: Self.oval(4, 28, 50, 12))
        // Head.
        let bob = sniffing ? max(0, sin(t * 8)) * -6 : sin(phase * 2) * 1.2
        ctx.saveGState()
        ctx.translateBy(x: 40, y: 50 + bob)
        ctx.setFillColor(fur)
        ctx.fillEllipse(in: Self.oval(0, 0, 26, 25))
        ctx.fillEllipse(in: Self.oval(12, -4, 18, 13))
        ctx.setFillColor(Self.c(0.08, 0.06, 0.05))
        ctx.fillEllipse(in: Self.oval(20, -1, 6, 5))
        ctx.fillEllipse(in: Self.oval(4, 4, 3.6, 3.6))
        ctx.setFillColor(Self.c(1, 1, 1))
        ctx.fillEllipse(in: Self.oval(4.6, 4.8, 1.2, 1.2))
        if barking > 0 || moving {
            ctx.setFillColor(Self.c(0.95, 0.45, 0.5))
            ctx.fillEllipse(in: Self.oval(14, -12, 6, barking > 0 ? 8 : 6))
        }
        // Floppy ear.
        ctx.setFillColor(dark)
        ctx.saveGState()
        ctx.translateBy(x: -5, y: 6)
        ctx.rotate(by: -0.35 + sin(phase) * 0.15)
        ctx.fillEllipse(in: Self.oval(0, -8, 10, 20))
        ctx.restoreGState()
        ctx.restoreGState()
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard barking > 0 else { return }
        Self.shout(ctx, "BAU!", at: CGPoint(x: facing * 40, y: 84), size: 22)
    }
}

// MARK: - Mouse

final class Mouse: Visitor {
    var speed: CGFloat = 0
    private var squeaking: CGFloat = 0

    override var bounds: CGRect { CGRect(x: -32, y: -2, width: 54, height: 40) }

    func squeak() { squeaking = 0.5 }

    override func update(_ dt: CGFloat) {
        super.update(dt)
        pos.x += speed * dt
        if speed != 0 { facing = speed > 0 ? 1 : -1 }
        squeaking = max(0, squeaking - dt)
    }

    override func draw(_ ctx: CGContext) {
        let gray = Self.c(0.56, 0.56, 0.6), pink = Self.c(0.95, 0.65, 0.7)
        ctx.setStrokeColor(Self.c(0.7, 0.55, 0.58))
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        let flick = sin(t * 12) * 3
        ctx.move(to: CGPoint(x: -9, y: 4)); ctx.addQuadCurve(to: CGPoint(x: -28, y: 8 + flick), control: CGPoint(x: -19, y: -2))
        ctx.strokePath()
        ctx.setFillColor(gray)
        ctx.fillEllipse(in: Self.oval(0, 6, 19, 11))
        ctx.fillEllipse(in: Self.oval(9, 6, 11, 8))
        ctx.setFillColor(pink)
        ctx.fillEllipse(in: Self.oval(15, 5.5, 2.6, 2.6))
        ctx.fillEllipse(in: Self.oval(6.5, 11.5, 6, 6))
        ctx.setFillColor(gray)
        ctx.fillEllipse(in: Self.oval(6.5, 11.5, 4, 4).offsetBy(dx: -0.6, dy: 0.4))
        ctx.setFillColor(pink)
        ctx.fillEllipse(in: Self.oval(6.5, 11.5, 3, 3))
        ctx.setFillColor(Self.c(0, 0, 0))
        ctx.fillEllipse(in: Self.oval(10.5, 7.8, 1.8, 1.8))
        if speed != 0 {
            ctx.setStrokeColor(gray)
            ctx.setLineWidth(1.5)
            for x in [-5.0, 4.0] {
                let s = sin(t * 30 + x) * 2.5
                ctx.move(to: CGPoint(x: x, y: 2)); ctx.addLine(to: CGPoint(x: x + s, y: 0)); ctx.strokePath()
            }
        }
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard squeaking > 0 else { return }
        Self.shout(ctx, "IIK!", at: CGPoint(x: 0, y: 28), size: 14)
    }
}

// MARK: - Ball of yarn

final class Yarn: Visitor {
    var vel = CGVector.zero
    var floorY: CGFloat
    var minX: CGFloat
    var maxX: CGFloat
    var walls = true
    private var spin: CGFloat = 0
    private var trail: [CGPoint] = []

    override var bounds: CGRect { CGRect(x: -60, y: -4, width: 120, height: 36) }

    init(at p: CGPoint, floorY: CGFloat, minX: CGFloat, maxX: CGFloat, scale: CGFloat) {
        self.floorY = floorY
        self.minX = minX
        self.maxX = maxX
        super.init(at: p, scale: scale)
    }

    var onFloor: Bool { pos.y <= floorY + 0.5 && abs(vel.dy) < 1 }

    override func update(_ dt: CGFloat) {
        super.update(dt)
        vel.dy -= 2000 * dt
        pos.x += vel.dx * dt
        pos.y += vel.dy * dt
        if pos.y < floorY {
            pos.y = floorY
            vel.dy = abs(vel.dy) > 120 ? -vel.dy * 0.35 : 0
        }
        if pos.y <= floorY + 0.5 {
            let friction = 140 * scale * dt
            vel.dx = abs(vel.dx) <= friction ? 0 : vel.dx - friction * (vel.dx > 0 ? 1 : -1)
        }
        if walls {
            if pos.x < minX { pos.x = minX; vel.dx = abs(vel.dx) * 0.5 }
            if pos.x > maxX { pos.x = maxX; vel.dx = -abs(vel.dx) * 0.5 }
        }
        spin -= vel.dx * dt / (10 * scale)
        trail.append(pos)
        if trail.count > 24 { trail.removeFirst() }
    }

    override func draw(_ ctx: CGContext) {
        // The loose thread follows where the ball has been (drawn in unmirrored units).
        if trail.count > 2, let first = trail.first {
            ctx.setStrokeColor(Self.c(0.8, 0.2, 0.3))
            ctx.setLineWidth(1.1)
            ctx.move(to: CGPoint(x: (first.x - pos.x) / scale * facing, y: 1.2))
            for p in trail.dropFirst() { ctx.addLine(to: CGPoint(x: (p.x - pos.x) / scale * facing, y: 1.2 + (p.y - pos.y) / scale * 0.2)) }
            ctx.strokePath()
        }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: 10)
        ctx.rotate(by: spin)
        ctx.setFillColor(Self.c(0.86, 0.24, 0.33))
        ctx.fillEllipse(in: Self.oval(0, 0, 20, 20))
        ctx.setStrokeColor(Self.c(0.62, 0.12, 0.2))
        ctx.setLineWidth(1.1)
        for a in [0.0, 1.1, 2.2] {
            ctx.saveGState()
            ctx.rotate(by: a)
            ctx.addEllipse(in: Self.oval(0, 0, 20, 8))
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}

// MARK: - Butterfly

final class Butterfly: Visitor {
    var target: CGPoint
    var resting = false
    private var seed = CGFloat.random(in: 0...10)

    override var bounds: CGRect { CGRect(x: -16, y: -16, width: 32, height: 32) }

    init(at p: CGPoint, target: CGPoint, scale: CGFloat) {
        self.target = target
        super.init(at: p, scale: scale)
    }

    override func update(_ dt: CGFloat) {
        super.update(dt)
        let s = scale
        let wobble = resting ? CGPoint.zero
            : CGPoint(x: sin(t * 2.3 + seed) * 40 * s + sin(t * 7.7) * 8 * s, y: cos(t * 1.9 + seed) * 22 * s + sin(t * 9.1) * 6 * s)
        let goal = CGPoint(x: target.x + wobble.x, y: target.y + wobble.y)
        let k = min(1, dt * (resting ? 12 : 2.4))
        let dx = goal.x - pos.x
        pos.x += dx * k
        pos.y += (goal.y - pos.y) * k
        if abs(dx) > 1 { facing = dx > 0 ? 1 : -1 }
    }

    override func draw(_ ctx: CGContext) {
        let flap = resting ? 0.35 + 0.15 * abs(sin(t * 3)) : abs(sin(t * 16))
        let orange = Self.c(1, 0.6, 0.12), deep = Self.c(0.85, 0.35, 0.08)
        ctx.setStrokeColor(Self.c(0.1, 0.08, 0.06))
        ctx.setLineWidth(0.6)
        for side in [-1.0, 1.0] {
            ctx.setFillColor(orange)
            let up = Self.oval(side * 5.5 * flap, 4, 10 * flap + 1, 10)
            ctx.addEllipse(in: up)
            ctx.drawPath(using: .fillStroke)
            ctx.setFillColor(deep)
            let low = Self.oval(side * 4.5 * flap, -4, 8 * flap + 1, 7)
            ctx.addEllipse(in: low)
            ctx.drawPath(using: .fillStroke)
        }
        ctx.setStrokeColor(Self.c(0.08, 0.06, 0.05))
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 0, y: -6)); ctx.addLine(to: CGPoint(x: 0, y: 6)); ctx.strokePath()
        ctx.setLineWidth(0.6)
        ctx.move(to: CGPoint(x: 0, y: 6)); ctx.addLine(to: CGPoint(x: -3, y: 11))
        ctx.move(to: CGPoint(x: 0, y: 6)); ctx.addLine(to: CGPoint(x: 3, y: 11))
        ctx.strokePath()
    }
}

// MARK: - Cardboard box

final class CardboardBox: Visitor {
    private var vy: CGFloat = 0
    let floorY: CGFloat

    override var bounds: CGRect { CGRect(x: -46, y: -4, width: 92, height: 50) }
    override var inFront: Bool { true }

    init(at p: CGPoint, floorY: CGFloat, scale: CGFloat) {
        self.floorY = floorY
        super.init(at: p, scale: scale)
    }

    var landed: Bool { pos.y <= floorY + 0.5 && vy == 0 }

    override func update(_ dt: CGFloat) {
        super.update(dt)
        guard !landed else { return }
        vy -= 2200 * dt
        pos.y += vy * dt
        if pos.y <= floorY {
            pos.y = floorY
            vy = abs(vy) > 250 ? -vy * 0.25 : 0
        }
    }

    override func draw(_ ctx: CGContext) {
        let card = Self.c(0.8, 0.62, 0.4), edge = Self.c(0.55, 0.39, 0.24), inside = Self.c(0.6, 0.44, 0.27)
        // Open flaps, leaning outward.
        ctx.setFillColor(inside)
        ctx.setStrokeColor(edge)
        ctx.setLineWidth(1.2)
        ctx.move(to: CGPoint(x: -32, y: 24)); ctx.addLine(to: CGPoint(x: -44, y: 34)); ctx.addLine(to: CGPoint(x: -20, y: 36)); ctx.addLine(to: CGPoint(x: -10, y: 24)); ctx.closePath()
        ctx.drawPath(using: .fillStroke)
        ctx.move(to: CGPoint(x: 32, y: 24)); ctx.addLine(to: CGPoint(x: 44, y: 34)); ctx.addLine(to: CGPoint(x: 20, y: 36)); ctx.addLine(to: CGPoint(x: 10, y: 24)); ctx.closePath()
        ctx.drawPath(using: .fillStroke)
        // Front face: low enough that a cat inside still shows its head and ears.
        ctx.setFillColor(card)
        ctx.addRect(CGRect(x: -32, y: 0, width: 64, height: 24))
        ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(Self.c(0.9, 0.78, 0.55))
        ctx.fill(CGRect(x: -4, y: 12, width: 8, height: 12))
        ctx.setStrokeColor(Self.c(0.8, 0.2, 0.2, 0.7))
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: -26, y: 4, width: 14, height: 7))
    }
}

// MARK: - Robot vacuum

final class RobotVacuum: Visitor {
    var speed: CGFloat = 0

    override var bounds: CGRect { CGRect(x: -38, y: -4, width: 76, height: 26) }

    override var platform: CGRect? {
        CGRect(x: pos.x - 30 * scale, y: pos.y, width: 60 * scale, height: 13 * scale)
    }

    override func update(_ dt: CGFloat) {
        super.update(dt)
        pos.x += speed * dt
        if speed != 0 { facing = speed > 0 ? 1 : -1 }
    }

    override func draw(_ ctx: CGContext) {
        ctx.setFillColor(Self.c(0.16, 0.16, 0.18))
        ctx.addPath(CGPath(roundedRect: CGRect(x: -32, y: 0, width: 64, height: 13), cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(Self.c(0.32, 0.32, 0.36))
        ctx.addPath(CGPath(roundedRect: CGRect(x: -29, y: 8, width: 58, height: 5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(Int(t * 2) % 2 == 0 ? Self.c(0.3, 0.95, 0.45) : Self.c(0.15, 0.5, 0.25))
        ctx.fillEllipse(in: Self.oval(20, 10.5, 3, 3))
        ctx.setStrokeColor(Self.c(0.6, 0.6, 0.65))
        ctx.setLineWidth(1)
        for k in 0..<3 {
            let a = t * 18 + CGFloat(k) * 2.1
            ctx.move(to: CGPoint(x: 30, y: 1.5))
            ctx.addLine(to: CGPoint(x: 30 + cos(a) * 5, y: 1.5 + sin(a) * 1.5))
        }
        ctx.strokePath()
    }
}

// MARK: - Rival cat

/// Another cat, drawn with the same rig in a different coat.
final class RivalCat: Visitor {
    let body: CatBody
    let anim = Animator()

    override var bounds: CGRect { CGRect(x: -70, y: -30, width: 140, height: 120) }

    init(at p: CGPoint, scale: CGFloat, coat: CatCoat) {
        body = CatBody(pos: p, footing: .floor(screen: 0), scale: scale)
        super.init(at: p, scale: scale)
        anim.coat = coat
    }

    /// Walks by `dx` points this frame at `speed`, ignoring ledges, so it can leave the screen.
    func stroll(_ dt: CGFloat, toward x: CGFloat?, speed: CGFloat) {
        guard let x else { body.stroll(by: 0, speed: 0); return }
        let dx = x - body.pos.x
        let step = min(abs(dx), speed * dt) * (dx >= 0 ? 1 : -1)
        body.stroll(by: step, speed: abs(dx) < 1 ? 0 : speed)
    }

    override func update(_ dt: CGFloat) {
        super.update(dt)
        pos = body.pos
        facing = 1
        frame = anim.update(dt, body: body, dark: false)
    }

    private var frame: CatFrame?

    override func draw(_ ctx: CGContext) {
        guard let f = frame else { return }
        ctx.scaleBy(x: body.facing / scale * f.scale, y: 1 / scale * f.scale)
        CatRig.draw(f.look, in: ctx)
    }
}

// MARK: - Laser dot

final class LaserDot: Visitor {
    var target: CGPoint

    override var bounds: CGRect { CGRect(x: -10, y: -10, width: 20, height: 20) }

    override init(at p: CGPoint, scale: CGFloat) {
        target = p
        super.init(at: p, scale: scale)
    }

    override func update(_ dt: CGFloat) {
        super.update(dt)
        let k = min(1, dt * 14)
        pos.x += (target.x - pos.x) * k + .random(in: -0.8...0.8)
        pos.y += (target.y - pos.y) * k + .random(in: -0.8...0.8)
    }

    override func draw(_ ctx: CGContext) {
        if let g = CGGradient(colorsSpace: nil, colors: [Self.c(1, 0.1, 0.1, 0.55), Self.c(1, 0.1, 0.1, 0)] as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 8, options: [])
        }
        ctx.setFillColor(Self.c(1, 0.25, 0.2))
        ctx.fillEllipse(in: Self.oval(0, 0, 4, 4))
    }
}

// MARK: - Panels

/// A see-through panel that follows one visitor around.
@MainActor
final class VisitorPanel {
    private let panel: FloatingPanel
    private let view = VisitorView()
    let visitor: Visitor

    init(_ v: Visitor) {
        visitor = v
        let b = v.bounds
        let size = CGSize(width: b.width * v.scale, height: b.height * v.scale)
        panel = FloatingPanel(size: size)
        view.frame = CGRect(origin: .zero, size: size)
        view.wantsLayer = true
        view.visitor = v
        panel.contentView = view
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + (v.inFront ? 1 : -1))
        sync()
        panel.orderFrontRegardless()
    }

    func sync() {
        let b = visitor.bounds
        let s = visitor.scale
        let anchorX = visitor.facing >= 0 ? -b.minX * s : b.maxX * s
        let origin = CGPoint(x: (visitor.pos.x - anchorX).rounded(), y: (visitor.pos.y + b.minY * s).rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        view.anchor = CGPoint(x: visitor.pos.x - origin.x, y: visitor.pos.y - origin.y)
        panel.alphaValue = visitor.alpha
        view.needsDisplay = true
    }

    func close() { panel.orderOut(nil) }
}

final class VisitorView: NSView {
    weak var visitor: Visitor?
    var anchor = CGPoint.zero

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let v = visitor else { return }
        ctx.clear(bounds)
        ctx.saveGState()
        ctx.translateBy(x: anchor.x, y: anchor.y)
        ctx.scaleBy(x: v.facing * v.scale, y: v.scale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        v.draw(ctx)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: anchor.x, y: anchor.y)
        ctx.scaleBy(x: v.scale, y: v.scale)
        v.drawOverlay(ctx)
        ctx.restoreGState()
    }
}

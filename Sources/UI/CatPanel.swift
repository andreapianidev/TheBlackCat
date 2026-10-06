import AppKit

/// A borderless, see-through panel that floats over every app and every Space.
/// Clicks go through it, except on the cat itself.
class FloatingPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
protocol CatViewDelegate: AnyObject {
    func catPressed()
    func catDragged(to p: CGPoint)
    func catReleased(dragged: Bool, clicks: Int)
    func catMenu(_ event: NSEvent, in view: NSView)
}

final class CatView: NSView {
    weak var delegate: CatViewDelegate?
    var frameToDraw: CatFrame?
    /// The cat's feet in this view's coordinates.
    var anchor: CGPoint = .zero
    var particles: ParticleSystem?
    /// The fly being hunted, in global coordinates, and its wing phase.
    var fly: (CGPoint, Bool)?

    private var downAt: CGPoint?
    private var dragging = false
    private var clicks = 0

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func render() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        if let f = frameToDraw {
            ctx.saveGState()
            ctx.translateBy(x: anchor.x, y: anchor.y)
            ctx.rotate(by: f.rotation)
            ctx.scaleBy(x: f.facing * f.scale, y: f.scale)
            CatRig.draw(f.look, in: ctx)
            ctx.restoreGState()
        }
        if let window, let particles {
            particles.draw(in: ctx, origin: window.frame.origin)
        }
        if let window, let (p, up) = fly {
            let at = CGPoint(x: p.x - window.frame.origin.x, y: p.y - window.frame.origin.y)
            ctx.setFillColor(NSColor(white: 0.85, alpha: 0.75).cgColor)
            let wy: CGFloat = up ? 2.4 : 1.2
            ctx.fillEllipse(in: CGRect(x: at.x - 4.5, y: at.y + 0.5, width: 4, height: wy + 1.5))
            ctx.fillEllipse(in: CGRect(x: at.x + 0.5, y: at.y + 0.5, width: 4, height: wy + 1.5))
            ctx.setFillColor(NSColor(white: 0.05, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: at.x - 2.2, y: at.y - 1.6, width: 4.4, height: 3.4))
        }
    }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        dragging = false
        clicks = event.clickCount
        delegate?.catPressed()
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        if !dragging, let d = downAt, hypot(p.x - d.x, p.y - d.y) > 4 { dragging = true }
        if dragging { delegate?.catDragged(to: p) }
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.catReleased(dragged: dragging, clicks: clicks)
        dragging = false
        downAt = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.catMenu(event, in: self)
    }
}

/// Little things that float off the cat: Zzz, hearts, exclamation marks,
/// and in the comic style sweat drops, anger marks and speed lines.
final class ParticleSystem {
    private struct P {
        var kind: ParticleKind
        var pos: CGPoint
        var vel: CGVector
        var age: CGFloat = 0
        var life: CGFloat
        var size: CGFloat
        var dir: CGFloat = 1
    }
    private var items: [P] = []

    var isEmpty: Bool { items.isEmpty }
    /// True when nothing but slow Zzz is floating: no reason to animate fast.
    var isCalm: Bool { items.allSatisfy { $0.kind == .zzz } }
    /// Letters are laid out once and reused: text layout every frame is expensive.
    private var glyphs: [String: CGImage] = [:]

    func emit(_ kind: ParticleKind, at p: CGPoint, scale s: CGFloat, facing: CGFloat = 1) {
        switch kind {
        case .zzz:
            items.append(P(kind: kind, pos: p, vel: CGVector(dx: 9 * s, dy: 16 * s), life: 2.6, size: 9 * s))
        case .heart:
            items.append(P(kind: kind, pos: CGPoint(x: p.x + .random(in: -8...8) * s, y: p.y),
                           vel: CGVector(dx: .random(in: -6...6) * s, dy: 26 * s), life: 1.6, size: 8 * s))
        case .bang, .question:
            items.append(P(kind: kind, pos: p, vel: CGVector(dx: 0, dy: 22 * s), life: 1.1, size: 16 * s))
        case .note:
            items.append(P(kind: kind, pos: p, vel: CGVector(dx: 10 * s, dy: 18 * s), life: 2, size: 13 * s))
        case .ring:
            items.append(P(kind: kind, pos: p, vel: .zero, life: 1.4, size: 30 * s))
        case .sweat:
            items.append(P(kind: kind, pos: CGPoint(x: p.x - facing * 9 * s, y: p.y + 4 * s),
                           vel: CGVector(dx: -facing * 22 * s, dy: 12 * s), life: 0.9, size: 7 * s, dir: facing))
        case .anger:
            items.append(P(kind: kind, pos: CGPoint(x: p.x + facing * 6 * s, y: p.y + 10 * s), vel: .zero, life: 1.3, size: 7 * s))
        case .dust:
            for k in [-1.0, 1.0] as [CGFloat] {
                items.append(P(kind: kind, pos: CGPoint(x: p.x + k * 12 * s, y: p.y + 3 * s),
                               vel: CGVector(dx: k * 40 * s, dy: 8 * s), life: 0.5, size: 6 * s))
            }
        case .speed:
            items.append(P(kind: kind, pos: p, vel: CGVector(dx: -facing * 70 * s, dy: 0), life: 0.25, size: 18 * s, dir: facing))
        case .sparkle:
            for _ in 0..<3 {
                items.append(P(kind: kind, pos: CGPoint(x: p.x + .random(in: -14...14) * s, y: p.y + .random(in: -4...10) * s),
                               vel: CGVector(dx: 0, dy: 14 * s), life: 0.9, size: .random(in: 4...7) * s))
            }
        }
    }

    func update(_ dt: CGFloat) {
        for i in items.indices {
            items[i].age += dt
            items[i].pos.x += items[i].vel.dx * dt + (items[i].kind == .zzz ? sin(items[i].age * 3) * 0.3 : 0)
            items[i].pos.y += items[i].vel.dy * dt
            if items[i].kind == .sweat { items[i].vel.dy -= 120 * dt }
        }
        items.removeAll { $0.age >= $0.life }
    }

    func draw(in ctx: CGContext, origin: CGPoint) {
        for p in items {
            let t = p.age / p.life
            let alpha = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85
            let at = CGPoint(x: p.pos.x - origin.x, y: p.pos.y - origin.y)
            switch p.kind {
            case .zzz: text(ctx, "z", at: at, size: p.size * (0.8 + t * 0.7), color: NSColor(white: 0.85, alpha: alpha), bold: true)
            case .bang: text(ctx, "!", at: at, size: p.size, color: NSColor.systemYellow.withAlphaComponent(alpha), bold: true)
            case .question: text(ctx, "?", at: at, size: p.size, color: NSColor.white.withAlphaComponent(alpha), bold: true)
            case .note: text(ctx, "♪", at: at, size: p.size, color: NSColor.white.withAlphaComponent(alpha), bold: false)
            case .heart: heart(ctx, at: at, size: p.size, alpha: alpha)
            case .ring:
                ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(alpha * 0.9).cgColor)
                ctx.setLineWidth(3)
                let r = p.size * (1 + t * 2.2)
                ctx.strokeEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
            case .sweat: sweat(ctx, at: at, size: p.size, alpha: min(1, alpha * 1.4))
            case .anger: anger(ctx, at: at, size: p.size * (1 + 0.15 * sin(p.age * 18)), alpha: alpha)
            case .dust:
                ctx.setFillColor(NSColor(white: 0.75, alpha: 0.7 * (1 - t)).cgColor)
                let r = p.size * (0.6 + t)
                ctx.fillEllipse(in: CGRect(x: at.x - r, y: at.y - r * 0.7, width: 2 * r, height: 1.4 * r))
            case .speed:
                ctx.setStrokeColor(NSColor(white: 0.1, alpha: 0.55 * (1 - t)).cgColor)
                ctx.setLineWidth(1.6)
                ctx.setLineCap(.round)
                ctx.move(to: at)
                ctx.addLine(to: CGPoint(x: at.x - p.dir * p.size, y: at.y))
                ctx.strokePath()
            case .sparkle: sparkle(ctx, at: at, size: p.size, alpha: alpha)
            }
        }
    }

    private func glyph(_ s: String, color: NSColor, bold: Bool) -> CGImage? {
        let key = s + (bold ? "b" : "r") + color.description
        if let g = glyphs[key] { return g }
        let font = NSFont.systemFont(ofSize: 64, weight: bold ? .heavy : .regular)
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let sz = a.size()
        let w = Int(ceil(sz.width)) + 4, h = Int(ceil(sz.height)) + 4
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        a.draw(at: CGPoint(x: 2, y: 2))
        NSGraphicsContext.restoreGraphicsState()
        let img = ctx.makeImage()
        glyphs[key] = img
        return img
    }

    private func text(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, color: NSColor, bold: Bool) {
        guard let g = glyph(s, color: color.withAlphaComponent(1), bold: bold) else { return }
        let k = size / 64
        let w = CGFloat(g.width) * k, h = CGFloat(g.height) * k
        ctx.saveGState()
        ctx.setAlpha(color.alphaComponent)
        ctx.draw(g, in: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    private func heart(_ ctx: CGContext, at p: CGPoint, size s: CGFloat, alpha: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: p.x, y: p.y - s * 0.55))
        path.addCurve(to: CGPoint(x: p.x - s * 0.6, y: p.y + s * 0.2), control1: CGPoint(x: p.x - s * 0.2, y: p.y - s * 0.25),
                      control2: CGPoint(x: p.x - s * 0.6, y: p.y - s * 0.15))
        path.addArc(center: CGPoint(x: p.x - s * 0.3, y: p.y + s * 0.2), radius: s * 0.3, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addArc(center: CGPoint(x: p.x + s * 0.3, y: p.y + s * 0.2), radius: s * 0.3, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addCurve(to: CGPoint(x: p.x, y: p.y - s * 0.55), control1: CGPoint(x: p.x + s * 0.6, y: p.y - s * 0.15),
                      control2: CGPoint(x: p.x + s * 0.2, y: p.y - s * 0.25))
        ctx.setFillColor(NSColor(calibratedRed: 1, green: 0.42, blue: 0.56, alpha: alpha).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// A comic sweat drop: round bottom, pointed top, black outline.
    private func sweat(_ ctx: CGContext, at p: CGPoint, size s: CGFloat, alpha: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: p.x, y: p.y + s))
        path.addQuadCurve(to: CGPoint(x: p.x + s * 0.55, y: p.y - s * 0.1), control: CGPoint(x: p.x + s * 0.45, y: p.y + s * 0.45))
        path.addArc(center: CGPoint(x: p.x, y: p.y - s * 0.1), radius: s * 0.55, startAngle: 0, endAngle: .pi, clockwise: true)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: CGPoint(x: p.x - s * 0.45, y: p.y + s * 0.45))
        ctx.addPath(path)
        ctx.setFillColor(NSColor(calibratedRed: 0.6, green: 0.84, blue: 1, alpha: alpha).cgColor)
        ctx.setStrokeColor(NSColor(white: 0, alpha: alpha).cgColor)
        ctx.setLineWidth(1.2)
        ctx.drawPath(using: .fillStroke)
    }

    /// The comic anger mark: four little arcs facing each other.
    private func anger(_ ctx: CGContext, at p: CGPoint, size s: CGFloat, alpha: CGFloat) {
        ctx.setStrokeColor(NSColor(calibratedRed: 0.92, green: 0.12, blue: 0.18, alpha: alpha).cgColor)
        ctx.setLineWidth(max(1.6, s * 0.28))
        ctx.setLineCap(.round)
        for k in 0..<4 {
            let a = CGFloat(k) * .pi / 2 + .pi / 4
            let c = CGPoint(x: p.x + cos(a) * s * 0.75, y: p.y + sin(a) * s * 0.75)
            ctx.addArc(center: c, radius: s * 0.5, startAngle: a + .pi * 0.75, endAngle: a + .pi * 1.25, clockwise: false)
            ctx.strokePath()
        }
    }

    private func sparkle(_ ctx: CGContext, at p: CGPoint, size s: CGFloat, alpha: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: p.x, y: p.y + s))
        path.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: p)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(calibratedRed: 1, green: 0.85, blue: 0.25, alpha: alpha).cgColor)
        ctx.fillPath()
    }
}

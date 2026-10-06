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

    private var downAt: CGPoint?
    private var dragging = false
    private var clicks = 0

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

/// Little things that float off the cat: Zzz, hearts, exclamation marks.
final class ParticleSystem {
    private struct P {
        var kind: ParticleKind
        var pos: CGPoint
        var vel: CGVector
        var age: CGFloat = 0
        var life: CGFloat
        var size: CGFloat
    }
    private var items: [P] = []

    var isEmpty: Bool { items.isEmpty }

    func emit(_ kind: ParticleKind, at p: CGPoint, scale s: CGFloat) {
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
        }
    }

    func update(_ dt: CGFloat) {
        for i in items.indices {
            items[i].age += dt
            items[i].pos.x += items[i].vel.dx * dt + (items[i].kind == .zzz ? sin(items[i].age * 3) * 0.3 : 0)
            items[i].pos.y += items[i].vel.dy * dt
        }
        items.removeAll { $0.age >= $0.life }
    }

    func draw(in ctx: CGContext, origin: CGPoint) {
        for p in items {
            let t = p.age / p.life
            let alpha = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85
            let at = CGPoint(x: p.pos.x - origin.x, y: p.pos.y - origin.y)
            switch p.kind {
            case .zzz: text("z", at: at, size: p.size * (0.8 + t * 0.7), color: NSColor(white: 0.85, alpha: alpha), bold: true)
            case .bang: text("!", at: at, size: p.size, color: NSColor.systemYellow.withAlphaComponent(alpha), bold: true)
            case .question: text("?", at: at, size: p.size, color: NSColor.white.withAlphaComponent(alpha), bold: true)
            case .note: text("♪", at: at, size: p.size, color: NSColor.white.withAlphaComponent(alpha), bold: false)
            case .heart: heart(ctx, at: at, size: p.size, alpha: alpha)
            case .ring:
                ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(alpha * 0.9).cgColor)
                ctx.setLineWidth(3)
                let r = p.size * (1 + t * 2.2)
                ctx.strokeEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
            }
        }
    }

    private func text(_ s: String, at p: CGPoint, size: CGFloat, color: NSColor, bold: Bool) {
        let font = NSFont.systemFont(ofSize: size, weight: bold ? .heavy : .regular)
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let sz = a.size()
        a.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
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
}

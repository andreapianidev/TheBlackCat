import CoreGraphics
import Foundation

/// Everything needed to paint one frame of the cat.
struct CatLook {
    var pose: CatPose
    var tail: [CGPoint]
    var tailPuff: CGFloat = 1
    /// Pupil direction, each axis -1...1, in rig space.
    var gaze: CGVector = .zero
    /// Eye glow, stronger in the dark.
    var glow: CGFloat = 0.4
    /// Opacity of the contact shadow on the ground.
    var groundShadow: CGFloat = 0.2
    /// Soft light outline so a dark cat still reads on a dark window.
    var halo: CGFloat = 0.22
    var coat: CatCoat = .black
    /// Comic style: ink outline, flat colours, big deadpan eyes.
    var comic = false
    /// 0...1, changes a few times a second in comic style so the ink line "boils".
    var boil: CGFloat = 0
    /// Closed eyes drawn as a content smile.
    var happy = false
}

enum CatRig {
    // MARK: Small vector helpers, kept local so the rig builds on its own.

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func add(_ a: CGPoint, _ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: a.x + x, y: a.y + y) }
    private static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
    private static func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }
    private static func oval(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h) }
    private static let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    private static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let mouth = CGColor(red: 0.46, green: 0.13, blue: 0.2, alpha: 1)
    private static let tongue = CGColor(red: 0.95, green: 0.5, blue: 0.58, alpha: 1)

    /// A paint pass: a colour, and how far every shape is grown (for outlines).
    private struct Ink {
        var color: CGColor
        var grow: CGFloat
    }

    /// Two bone inverse kinematics: where the middle joint goes so the chain
    /// reaches `target`. `bend` picks the side the joint folds to.
    static func twoBone(root: CGPoint, target: CGPoint, l1: CGFloat, l2: CGFloat, bend: CGFloat) -> (joint: CGPoint, end: CGPoint) {
        var dx = target.x - root.x, dy = target.y - root.y
        var d = hypot(dx, dy)
        let reach = l1 + l2 - 0.01
        if d > reach { dx *= reach / d; dy *= reach / d; d = reach }
        d = max(d, 0.01)
        let base = atan2(dy, dx)
        let c = ((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)).clamped01(lo: -1)
        let a = acos(c)
        let ang = base + bend * a
        return (pt(root.x + cos(ang) * l1, root.y + sin(ang) * l1), pt(root.x + dx, root.y + dy))
    }

    static func tailRoot(_ p: CatPose) -> CGPoint {
        let dx = p.hip.x - p.chest.x, dy = p.hip.y - p.chest.y
        let len = max(hypot(dx, dy), 0.01)
        return pt(p.hip.x + dx / len * p.hipR * 0.85, p.hip.y + dy / len * p.hipR * 0.85 + 2)
    }

    /// Rough body circles in rig space, for hit testing.
    static func hitCircles(_ p: CatPose) -> [(CGPoint, CGFloat)] {
        [(p.hip, p.hipR + 3), (p.chest, p.chestR + 3), (mid(p.hip, p.chest), (p.hipR + p.chestR) / 2 + 3),
         (p.head, p.headR * 1.25), (mid(p.chest, p.feet[0]), 8), (mid(p.hip, p.feet[2]), 8)]
    }

    /// Joints of one leg: root, middle joint, lower joint, foot.
    private static func leg(_ p: CatPose, _ i: Int) -> [CGPoint] {
        let farShift: CGFloat = (i == 1 || i == 3) ? -3 : 0
        let foot = p.feet[i]
        if i < 2 {
            let root = add(p.chest, 1 + farShift, -3)
            let (elbow, wrist) = twoBone(root: root, target: add(foot, 0.5, 3.5), l1: 12, l2: 12.5, bend: -1)
            return [root, elbow, wrist, foot]
        }
        let root = add(p.hip, 2 + farShift, -3)
        let (knee, hock) = twoBone(root: root, target: add(foot, -4.5, 8), l1: 13, l2: 13, bend: 1)
        return [root, knee, hock, foot]
    }

    // MARK: Drawing

    static func draw(_ look: CatLook, in ctx: CGContext) {
        var p = look.pose
        let coat = look.coat
        if look.comic { p.headR *= 1.16 }

        if look.groundShadow > 0 {
            let w = abs(p.chest.x - p.hip.x) + p.hipR + p.chestR + 8
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: look.groundShadow))
            ctx.fillEllipse(in: oval(pt((p.hip.x + p.chest.x) / 2, 0.5), w, 5))
        }

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        // A thin light outline instead of a blurred glow: it reads the same and costs far less.
        if look.halo > 0 && !look.comic {
            let haloColor = coat.isDark ? white : black
            ctx.saveGState()
            ctx.setAlpha(min(1, look.halo * 1.6))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            silhouette(ctx, p, look, Ink(color: haloColor, grow: 1.0))
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Comic style: a white sticker border, then the black ink line, around the whole cat.
        if look.comic {
            let b = look.boil
            silhouette(ctx, p, look, Ink(color: white, grow: 3.1 + b * 0.6))
            silhouette(ctx, p, look, Ink(color: black, grow: 1.7 + (1 - b) * 0.45))
        }

        // The coat, in its own layer so markings only land on fur.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let inner = Ink(color: coat.isDark ? CGColor(red: 1, green: 1, blue: 1, alpha: 0.85) : black, grow: 0.85)
        let fur = Ink(color: coat.fur, grow: 0)
        let far = Ink(color: coat.farFur, grow: 0)
        if p.tuck < 0.95 {
            drawLeg(ctx, p, 1, far, comic: look.comic)
            drawLeg(ctx, p, 3, far, comic: look.comic)
        }
        drawTail(ctx, look.tail, puff: look.tailPuff, ink: fur, coat: coat)
        if look.comic { drawTorso(ctx, p, inner) }
        drawTorso(ctx, p, fur)
        torsoMarkings(ctx, p, coat)
        if p.tuck < 0.95 {
            for i in [2, 0] {
                if look.comic { drawLeg(ctx, p, i, inner, comic: true) }
                drawLeg(ctx, p, i, fur, comic: look.comic)
            }
            legMarkings(ctx, p, coat)
        } else {
            // Front paws peeking out of a loaf.
            ctx.setFillColor(coat.bib ?? coat.points ?? coat.fur)
            ctx.fillEllipse(in: oval(add(p.feet[0], 1, 2), 8, 5))
        }
        drawNeck(ctx, p, fur)
        if look.comic { drawHead(ctx, p, inner) }
        drawHead(ctx, p, fur)
        headMarkings(ctx, p, coat)
        ctx.endTransparencyLayer()

        ctx.endTransparencyLayer()
        ctx.restoreGState()

        if look.comic {
            drawComicFace(ctx, p, look: look)
        } else {
            drawRim(ctx, p, coat)
            drawFace(ctx, p, look: look)
        }
    }

    /// The whole body in one ink, grown outward: used for the comic outlines.
    private static func silhouette(_ ctx: CGContext, _ p: CatPose, _ look: CatLook, _ ink: Ink) {
        if p.tuck < 0.95 { for i in 0..<4 { drawLeg(ctx, p, i, ink, comic: true) } }
        drawTail(ctx, look.tail, puff: look.tailPuff, ink: ink, coat: nil)
        drawTorso(ctx, p, ink)
        if p.tuck >= 0.95 {
            ctx.setFillColor(ink.color)
            ctx.fillEllipse(in: oval(add(p.feet[0], 1, 2), 8, 5).insetBy(dx: -ink.grow, dy: -ink.grow))
        }
        drawNeck(ctx, p, ink)
        drawHead(ctx, p, ink)
    }

    private static func line(_ ctx: CGContext, _ pts: [CGPoint], _ width: CGFloat, _ ink: Ink) {
        guard let first = pts.first else { return }
        ctx.setStrokeColor(ink.color)
        ctx.setLineWidth(width + 2 * ink.grow)
        ctx.move(to: first)
        for q in pts.dropFirst() { ctx.addLine(to: q) }
        ctx.strokePath()
    }

    private static func blob(_ ctx: CGContext, _ r: CGRect, _ ink: Ink) {
        ctx.setFillColor(ink.color)
        ctx.fillEllipse(in: r.insetBy(dx: -ink.grow, dy: -ink.grow))
    }

    private static func drawLeg(_ ctx: CGContext, _ p: CatPose, _ i: Int, _ ink: Ink, comic: Bool) {
        let j = leg(p, i)
        let paw: CGFloat = comic ? 1.18 : 1
        if i < 2 {
            line(ctx, [j[0], j[1]], 8.5, ink)
            line(ctx, [j[1], j[2], j[3]], 5.6, ink)
            blob(ctx, oval(add(j[3], 1.5, 1.8), 7.5 * paw, 4.6 * paw), ink)
        } else {
            line(ctx, [j[0], j[1]], 12, ink)
            line(ctx, [j[1], j[2]], 5.8, ink)
            line(ctx, [j[2], j[3]], 4.6, ink)
            blob(ctx, oval(add(j[3], 1.5, 1.8), 7.5 * paw, 4.4 * paw), ink)
        }
    }

    private static func drawTail(_ ctx: CGContext, _ pts: [CGPoint], puff: CGFloat, ink: Ink, coat: CatCoat?) {
        guard pts.count > 1 else { return }
        let n = pts.count - 1
        for i in 1...n {
            let f = CGFloat(i) / CGFloat(n)
            var segInk = ink
            if let coat { segInk.color = coat.tailColor(i, of: n) }
            line(ctx, [pts[i - 1], pts[i]], (5.2 - 2.2 * f) * puff, segInk)
        }
        var tipInk = ink
        if let coat { tipInk.color = coat.tailColor(n, of: n) }
        blob(ctx, circle(pts[n], 1.9 * puff), tipInk)
    }

    private static func drawTorso(_ ctx: CGContext, _ p: CatPose, _ ink: Ink) {
        blob(ctx, circle(p.hip, p.hipR), ink)
        blob(ctx, circle(p.chest, p.chestR), ink)
        let dx = p.chest.x - p.hip.x, dy = p.chest.y - p.hip.y
        let len = max(hypot(dx, dy), 0.01)
        let nx = -dy / len, ny = dx / len
        ctx.setFillColor(ink.color)
        ctx.setStrokeColor(ink.color)
        ctx.setLineWidth(max(2 * ink.grow, 0.01))
        ctx.move(to: pt(p.hip.x + nx * p.hipR, p.hip.y + ny * p.hipR))
        ctx.addLine(to: pt(p.chest.x + nx * p.chestR, p.chest.y + ny * p.chestR))
        ctx.addLine(to: pt(p.chest.x - nx * p.chestR, p.chest.y - ny * p.chestR))
        ctx.addLine(to: pt(p.hip.x - nx * p.hipR, p.hip.y - ny * p.hipR))
        ctx.closePath()
        ctx.drawPath(using: ink.grow > 0 ? .fillStroke : .fill)
        // A soft belly so the body is not a plain capsule.
        let m = mid(p.hip, p.chest)
        blob(ctx, oval(pt(m.x - nx * 2.5, m.y - ny * 2.5), len * 0.75, (p.hipR + p.chestR) * 0.95), ink)
        if p.arch > 0.5 {
            blob(ctx, oval(pt(m.x + nx * p.arch * 0.6, m.y + ny * p.arch * 0.6),
                           len * 0.9, (p.hipR + p.chestR) * 0.9 + p.arch), ink)
        }
    }

    private static func drawNeck(_ ctx: CGContext, _ p: CatPose, _ ink: Ink) {
        line(ctx, [p.chest, add(p.head, -2, -3)], p.chestR * 1.25, ink)
    }

    private static func earTriangles(_ p: CatPose) -> [(CGPoint, CGPoint, CGPoint)] {
        let e = p.earBack
        return [
            (pt(-8.5, 4.5), pt(-1.5, 8.2), pt(-7 - 5 * e, 16 - 8 * e)),
            (pt(1.5, 7.8), pt(9.5, 4.2), pt(7.5 + 5 * e, 16.5 - 8 * e)),
        ]
    }

    /// Moves the context into head space: origin at the head centre, unit = 1/10.5 of the radius.
    private static func enterHead(_ ctx: CGContext, _ p: CatPose) -> CGFloat {
        ctx.translateBy(x: p.head.x, y: p.head.y)
        ctx.rotate(by: p.headTilt)
        let s = p.headR / 10.5
        ctx.scaleBy(x: s, y: s)
        return s
    }

    private static func drawHead(_ ctx: CGContext, _ p: CatPose, _ ink: Ink) {
        ctx.saveGState()
        let s = enterHead(ctx, p)
        let g = ink.grow / s
        ctx.setFillColor(ink.color)
        ctx.setStrokeColor(ink.color)
        ctx.setLineWidth(2.4 + 2 * g)
        for (a, b, c) in earTriangles(p) {
            ctx.move(to: a); ctx.addLine(to: c); ctx.addLine(to: b); ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        }
        let local = Ink(color: ink.color, grow: g)
        blob(ctx, oval(pt(0.8, -0.8), 23.5, 19.5), local)
        blob(ctx, oval(pt(6.3, -3.8), 10.5, 7.6), local)
        ctx.restoreGState()
    }

    // MARK: Markings (painted only where there is already fur)

    private static func torsoMarkings(_ ctx: CGContext, _ p: CatPose, _ coat: CatCoat) {
        ctx.saveGState()
        ctx.setBlendMode(.sourceAtop)
        let dx = p.chest.x - p.hip.x, dy = p.chest.y - p.hip.y
        let len = max(hypot(dx, dy), 0.01)
        let ux = dx / len, uy = dy / len
        let nx = -uy, ny = ux
        if let s = coat.stripes {
            for k in 0..<4 {
                let t = 0.1 + 0.24 * CGFloat(k)
                let c = lerp(p.hip, p.chest, t)
                let r = p.hipR + (p.chestR - p.hipR) * t
                let top = pt(c.x + nx * r * 1.1, c.y + ny * r * 1.1)
                let low = pt(c.x + nx * r * 0.05 - ux * 3, c.y + ny * r * 0.05 - uy * 3)
                line(ctx, [top, low], 3.0, Ink(color: s, grow: 0))
            }
            line(ctx, [add(p.hip, -4, 6), add(p.hip, 2, -2)], 2.6, Ink(color: s, grow: 0))
        }
        if let w = coat.bib {
            ctx.setFillColor(w)
            ctx.fillEllipse(in: oval(pt(p.chest.x + ux * 4 - nx * p.chestR * 0.45, p.chest.y + uy * 4 - ny * p.chestR * 0.45),
                                     p.chestR * 1.4, p.chestR * 1.35))
            let m = mid(p.hip, p.chest)
            ctx.fillEllipse(in: oval(pt(m.x - nx * (p.chestR + 1.5), m.y - ny * (p.chestR + 1.5)), len * 0.8, 7))
        }
        if let a = coat.patchA, let b = coat.patchB {
            ctx.setFillColor(a)
            ctx.fillEllipse(in: oval(pt(p.hip.x + nx * 3 - ux * 2, p.hip.y + ny * 3 - uy * 2), p.hipR * 1.7, p.hipR * 1.35))
            ctx.setFillColor(b)
            let m = lerp(p.hip, p.chest, 0.62)
            ctx.fillEllipse(in: oval(pt(m.x + nx * 7, m.y + ny * 7), 15, 10))
        }
        ctx.restoreGState()
    }

    private static func legMarkings(_ ctx: CGContext, _ p: CatPose, _ coat: CatCoat) {
        guard coat.bib != nil || coat.points != nil || coat.stripes != nil else { return }
        ctx.saveGState()
        ctx.setBlendMode(.sourceAtop)
        for i in 0..<4 {
            let j = leg(p, i)
            if let pts = coat.points {
                line(ctx, [lerp(j[1], j[2], 0.35), j[2], j[3]], 7.5, Ink(color: pts, grow: 0))
                blob(ctx, oval(add(j[3], 1.5, 1.8), 9, 6), Ink(color: pts, grow: 0))
            }
            if let w = coat.bib {
                blob(ctx, oval(add(j[3], 1.5, 2.2), 9, 6.5), Ink(color: w, grow: 0))
            }
            if let s = coat.stripes, i == 0 || i == 2 {
                for t in [0.35, 0.7] as [CGFloat] {
                    let c = lerp(j[1], j[2], t)
                    line(ctx, [add(c, -3.5, 0.8), add(c, 3.5, -0.8)], 1.8, Ink(color: s, grow: 0))
                }
            }
        }
        ctx.restoreGState()
    }

    private static func headMarkings(_ ctx: CGContext, _ p: CatPose, _ coat: CatCoat) {
        guard coat.bib != nil || coat.points != nil || coat.stripes != nil || coat.patchA != nil else { return }
        ctx.saveGState()
        ctx.setBlendMode(.sourceAtop)
        _ = enterHead(ctx, p)
        if let s = coat.stripes {
            let ink = Ink(color: s, grow: 0)
            line(ctx, [pt(-2.6, 6.2), pt(-2.0, 9.6)], 1.4, ink)
            line(ctx, [pt(1.0, 7.0), pt(1.0, 10.6)], 1.4, ink)
            line(ctx, [pt(4.4, 6.0), pt(3.8, 9.4)], 1.4, ink)
            line(ctx, [pt(-10.5, -0.5), pt(-6.5, -1.4)], 1.3, ink)
            line(ctx, [pt(-10.5, -3.6), pt(-6.5, -3.8)], 1.3, ink)
        }
        if let w = coat.bib {
            ctx.setFillColor(w)
            ctx.fillEllipse(in: oval(pt(6.4, -4.6), 12.5, 8.6))
            ctx.fillEllipse(in: oval(pt(3.5, -7.6), 10, 5.5))
            ctx.fillEllipse(in: oval(pt(6.6, 0.6), 2.6, 7))
        }
        if let pts = coat.points {
            ctx.setFillColor(pts.copy(alpha: 0.92) ?? pts)
            ctx.fillEllipse(in: oval(pt(4.8, -2.6), 15.5, 13))
            for (a, b, c) in earTriangles(p) {
                ctx.move(to: a); ctx.addLine(to: c); ctx.addLine(to: b); ctx.closePath()
                ctx.fillPath()
            }
        }
        if let a = coat.patchA, let b = coat.patchB {
            ctx.setFillColor(a)
            ctx.fillEllipse(in: oval(pt(-5.5, 6.5), 13, 11))
            ctx.setFillColor(b)
            ctx.fillEllipse(in: oval(pt(9, 7.5), 7, 6))
        }
        ctx.restoreGState()
    }

    // MARK: Realistic face

    private static func drawRim(_ ctx: CGContext, _ p: CatPose, _ coat: CatCoat) {
        ctx.saveGState()
        ctx.setStrokeColor(coat.rim)
        ctx.setLineCap(.round)
        ctx.setLineWidth(1.1)
        let dx = p.chest.x - p.hip.x, dy = p.chest.y - p.hip.y
        let len = max(hypot(dx, dy), 0.01)
        let nx = -dy / len, ny = dx / len
        let a = pt(p.hip.x + nx * (p.hipR - 0.6), p.hip.y + ny * (p.hipR - 0.6))
        let b = pt(p.chest.x + nx * (p.chestR - 0.6), p.chest.y + ny * (p.chestR - 0.6))
        let m = mid(a, b)
        ctx.move(to: pt(p.hip.x - dx / len * p.hipR * 0.5 + nx * p.hipR * 0.8, p.hip.y - dy / len * p.hipR * 0.5 + ny * p.hipR * 0.8))
        ctx.addQuadCurve(to: b, control: pt(m.x + nx * (1.5 + p.arch * 0.9), m.y + ny * (1.5 + p.arch * 0.9)))
        ctx.strokePath()
        _ = enterHead(ctx, p)
        ctx.addArc(center: pt(0.8, -0.3), radius: 9.9, startAngle: 1.75, endAngle: 2.95, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func innerEars(_ ctx: CGContext, _ p: CatPose, _ color: CGColor) {
        ctx.setFillColor(color)
        for (a, b, c) in earTriangles(p) {
            let cx = (a.x + b.x + c.x) / 3, cy = (a.y + b.y + c.y) / 3
            func shrink(_ q: CGPoint) -> CGPoint { pt(cx + (q.x - cx) * 0.5, cy + (q.y - cy) * 0.5 - 0.4) }
            ctx.move(to: shrink(a)); ctx.addLine(to: shrink(c)); ctx.addLine(to: shrink(b)); ctx.closePath()
            ctx.fillPath()
        }
    }

    private static func drawFace(_ ctx: CGContext, _ p: CatPose, look: CatLook) {
        let coat = look.coat
        ctx.saveGState()
        _ = enterHead(ctx, p)
        if coat.points == nil { innerEars(ctx, p, coat.earInner) }

        let open = p.eyeOpen.clamped01()
        let eyes: [(CGPoint, CGFloat, CGFloat)] = [(pt(-2.4, 2.2), 4.9, 4.6), (pt(5.2, 1.6), 5.8, 5.0)]
        for (c, w, h) in eyes {
            if open < 0.12 {
                ctx.setStrokeColor(coat.closedEye)
                ctx.setLineWidth(0.9)
                ctx.setLineCap(.round)
                ctx.move(to: pt(c.x - w / 2, c.y))
                ctx.addQuadCurve(to: pt(c.x + w / 2, c.y), control: pt(c.x, c.y - 1.6))
                ctx.strokePath()
                continue
            }
            let eh = h * open
            let rect = oval(pt(c.x, c.y - (h - eh) * 0.3), w, eh)
            ctx.saveGState()
            if look.glow > 0 {
                ctx.setShadow(offset: .zero, blur: 3 + 5 * look.glow, color: coat.irisOut.copy(alpha: 0.35 + 0.5 * look.glow))
            }
            ctx.setFillColor(coat.irisOut)
            ctx.fillEllipse(in: rect)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: rect)
            ctx.clip()
            if let grad = CGGradient(colorsSpace: nil, colors: [coat.irisIn, coat.irisOut] as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(grad, startCenter: pt(c.x - 0.4, c.y + 0.6), startRadius: 0,
                                       endCenter: c, endRadius: w * 0.6, options: [.drawsAfterEndLocation])
            }
            let pw = 1.1 + 2.7 * p.pupil.clamped01()
            let gx = max(-1, min(1, look.gaze.dx)) * (w / 2 - pw / 2 - 0.3)
            let gy = max(-1, min(1, look.gaze.dy)) * 0.8
            ctx.setFillColor(black)
            ctx.fillEllipse(in: oval(pt(c.x + gx, c.y + gy), pw, h * 0.95))
            ctx.setFillColor(white)
            ctx.fillEllipse(in: circle(pt(c.x + gx + 0.9, c.y + gy + 1.0), 0.65))
            ctx.restoreGState()
        }

        ctx.setFillColor(coat.nose)
        ctx.move(to: pt(9.6, -1.5)); ctx.addLine(to: pt(11.7, -1.5)); ctx.addLine(to: pt(10.7, -2.9)); ctx.closePath()
        ctx.fillPath()
        if p.mouthOpen > 0.05 {
            let mh = 4.6 * p.mouthOpen
            ctx.setFillColor(mouth)
            ctx.fillEllipse(in: oval(pt(8.6, -6.4 - mh * 0.25), 5.4, mh))
            if p.mouthOpen > 0.5 {
                ctx.setFillColor(white)
                for fx in [7.2, 10.0] as [CGFloat] {
                    ctx.move(to: pt(fx - 0.6, -4.6)); ctx.addLine(to: pt(fx + 0.6, -4.6)); ctx.addLine(to: pt(fx, -6.3)); ctx.closePath()
                    ctx.fillPath()
                }
            }
        }
        ctx.setStrokeColor(coat.whisker)
        ctx.setLineWidth(0.55)
        for (ty, cy) in [(-1.2, -2.6), (-5.0, -4.6), (-8.8, -6.4)] as [(CGFloat, CGFloat)] {
            ctx.move(to: pt(9.5, -4.0))
            ctx.addQuadCurve(to: pt(24, ty), control: pt(17, cy))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: Comic face

    /// Big white eyes with small pupils and a flat lid, eyebrows that act, a "w" mouth.
    private static func drawComicFace(_ ctx: CGContext, _ p: CatPose, look: CatLook) {
        let coat = look.coat
        let ink = coat.isDark ? CGColor(red: 1, green: 1, blue: 1, alpha: 0.95) : black
        ctx.saveGState()
        _ = enterHead(ctx, p)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if coat.points == nil { innerEars(ctx, p, coat.earInner) }

        let open = p.eyeOpen.clamped01()
        let angry = p.earBack > 0.55 || p.mouthOpen > 0.8
        let shocked = !angry && p.pupil > 0.85
        let eyes: [(CGPoint, CGFloat, CGFloat)] = [(pt(-2.8, 2.6), 6.4, 7.6), (pt(5.4, 2.2), 7.2, 8.4)]
        for (k, (c, w, h)) in eyes.enumerated() {
            if open < 0.12 {
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(1.3)
                ctx.move(to: pt(c.x - w / 2, c.y))
                if look.happy {
                    ctx.addQuadCurve(to: pt(c.x + w / 2, c.y), control: pt(c.x, c.y + 2.6))
                } else {
                    ctx.addQuadCurve(to: pt(c.x + w / 2, c.y), control: pt(c.x, c.y - 1.4))
                }
                ctx.strokePath()
                continue
            }
            let rect = oval(c, w * (shocked ? 1.12 : 1), h * (shocked ? 1.12 : 1))
            ctx.setFillColor(white)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(black)
            ctx.setLineWidth(1.0)
            ctx.strokeEllipse(in: rect)
            // Pupil: a small dot, smaller when shocked.
            let r: CGFloat = shocked ? 0.9 : 1.2 + 0.7 * p.pupil.clamped01()
            let gx = max(-1, min(1, look.gaze.dx)) * (w / 2 - r - 0.6)
            let gy = max(-1, min(1, look.gaze.dy)) * (h / 2 - r - 0.8) * 0.6 - (1 - open) * 1.2
            ctx.setFillColor(black)
            ctx.fillEllipse(in: circle(pt(c.x + gx, c.y + gy), r))
            // Flat upper lid: the half-mast, unimpressed look.
            if open < 0.97 {
                ctx.saveGState()
                ctx.addEllipse(in: rect)
                ctx.clip()
                let lidY = rect.maxY - rect.height * (1 - open) * 0.9
                let tilt: CGFloat = angry ? (k == 0 ? -1.4 : 1.4) : 0
                ctx.setFillColor(coat.fur)
                ctx.move(to: pt(rect.minX - 1, lidY - tilt))
                ctx.addLine(to: pt(rect.maxX + 1, lidY + tilt))
                ctx.addLine(to: pt(rect.maxX + 1, rect.maxY + 1))
                ctx.addLine(to: pt(rect.minX - 1, rect.maxY + 1))
                ctx.closePath()
                ctx.fillPath()
                ctx.restoreGState()
                ctx.setStrokeColor(black)
                ctx.setLineWidth(1.0)
                ctx.move(to: pt(rect.minX + 0.4, lidY - tilt))
                ctx.addLine(to: pt(rect.maxX - 0.4, lidY + tilt))
                ctx.strokePath()
            }
            // Eyebrows.
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(1.25)
            let by = c.y + h / 2 + (shocked ? 3.2 : 1.8)
            let inward: CGFloat = k == 0 ? 1 : -1
            if angry {
                ctx.move(to: pt(c.x - inward * w * 0.45, by + 1.4))
                ctx.addLine(to: pt(c.x + inward * w * 0.4, by - 1.0))
            } else if shocked {
                ctx.move(to: pt(c.x - w * 0.4, by - 0.4))
                ctx.addQuadCurve(to: pt(c.x + w * 0.4, by - 0.4), control: pt(c.x, by + 1.4))
            } else {
                ctx.move(to: pt(c.x - w * 0.35, by))
                ctx.addLine(to: pt(c.x + w * 0.35, by + (open < 0.8 ? -0.3 : 0.2)))
            }
            ctx.strokePath()
        }

        // Nose and mouth.
        ctx.setFillColor(coat.nose)
        ctx.setStrokeColor(black)
        ctx.setLineWidth(0.7)
        ctx.move(to: pt(9.3, -1.4)); ctx.addLine(to: pt(12.1, -1.4)); ctx.addLine(to: pt(10.7, -3.1)); ctx.closePath()
        ctx.drawPath(using: .fillStroke)
        if p.mouthOpen > 0.05 {
            let mh = 5.2 * p.mouthOpen
            let r = oval(pt(9.4, -6.2 - mh * 0.3), 6.2, mh + 0.8)
            ctx.setFillColor(CGColor(red: 0.2, green: 0.04, blue: 0.08, alpha: 1))
            ctx.fillEllipse(in: r)
            ctx.saveGState()
            ctx.addEllipse(in: r)
            ctx.clip()
            ctx.setFillColor(tongue)
            ctx.fillEllipse(in: oval(pt(r.midX, r.minY), r.width * 0.8, r.height * 0.7))
            ctx.restoreGState()
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(0.9)
            ctx.strokeEllipse(in: r)
        } else {
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(0.95)
            ctx.move(to: pt(10.7, -3.1)); ctx.addLine(to: pt(10.7, -4.4))
            ctx.move(to: pt(8.2, -4.6)); ctx.addQuadCurve(to: pt(10.7, -4.4), control: pt(9.4, -6.0))
            ctx.addQuadCurve(to: pt(13.1, -4.6), control: pt(12.0, -6.0))
            ctx.strokePath()
        }
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(0.8)
        for (ty, cy) in [(-1.6, -2.8), (-5.4, -4.9)] as [(CGFloat, CGFloat)] {
            ctx.move(to: pt(13, -3.6))
            ctx.addQuadCurve(to: pt(22, ty), control: pt(17.5, cy))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Still pictures (widget, icon, menus)

    /// Renders a cat in a pose into a square bitmap, sitting on the bottom third.
    static func image(_ kind: PoseKind, size: Int, scale: CGFloat? = nil, gaze: CGVector = .zero, glow: CGFloat = 0.6,
                      halo: CGFloat = 0, tail: TailStyle? = nil, coat: CatCoat = .black, comic: Bool = false) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let pose = CatPose.make(kind)
        let k = scale ?? CGFloat(size) / 110
        ctx.translateBy(x: CGFloat(size) / 2 + 4 * k, y: CGFloat(size) * 0.22)
        ctx.scaleBy(x: k, y: k)
        let style = tail ?? (kind == .sleep || kind == .loaf || kind == .sit ? .wrapped : .happy)
        let pts = TailChain().settle(root: tailRoot(pose), style: style, groundY: 0)
        draw(CatLook(pose: pose, tail: pts, gaze: gaze, glow: glow, groundShadow: 0, halo: halo, coat: coat, comic: comic), in: ctx)
        return ctx.makeImage()
    }
}

extension CGFloat {
    func clamped01(lo: CGFloat = 0) -> CGFloat { Swift.min(Swift.max(self, lo), 1) }
}

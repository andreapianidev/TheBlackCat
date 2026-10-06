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
    /// Soft light outline so a black cat still reads on a black window.
    var halo: CGFloat = 0.22
}

enum CatPalette {
    static let fur = CGColor(red: 0.045, green: 0.045, blue: 0.06, alpha: 1)
    static let farFur = CGColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1)
    static let rim = CGColor(red: 0.47, green: 0.55, blue: 0.72, alpha: 0.42)
    static let earInner = CGColor(red: 0.27, green: 0.15, blue: 0.19, alpha: 1)
    static let irisIn = CGColor(red: 0.95, green: 0.96, blue: 0.42, alpha: 1)
    static let irisOut = CGColor(red: 0.58, green: 0.78, blue: 0.2, alpha: 1)
    static let glow = CGColor(red: 0.75, green: 0.95, blue: 0.3, alpha: 0.9)
    static let nose = CGColor(red: 0.32, green: 0.19, blue: 0.23, alpha: 1)
    static let mouth = CGColor(red: 0.46, green: 0.13, blue: 0.2, alpha: 1)
    static let whisker = CGColor(red: 1, green: 1, blue: 1, alpha: 0.3)
    static let closedEye = CGColor(red: 0.42, green: 0.44, blue: 0.52, alpha: 1)
    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
}

enum CatRig {
    // MARK: Small vector helpers, kept local so the rig builds on its own.

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func add(_ a: CGPoint, _ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: a.x + x, y: a.y + y) }
    private static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    private static func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }
    private static func oval(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h) }

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

    // MARK: Drawing

    static func draw(_ look: CatLook, in ctx: CGContext) {
        let p = look.pose

        if look.groundShadow > 0 {
            let w = abs(p.chest.x - p.hip.x) + p.hipR + p.chestR + 8
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: look.groundShadow))
            ctx.fillEllipse(in: oval(pt((p.hip.x + p.chest.x) / 2, 0.5), w, 5))
        }

        ctx.saveGState()
        if look.halo > 0 {
            ctx.setShadow(offset: .zero, blur: 4, color: CGColor(red: 1, green: 1, blue: 1, alpha: look.halo))
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if p.tuck < 0.95 {
            drawLeg(ctx, p, index: 1, color: CatPalette.farFur)
            drawLeg(ctx, p, index: 3, color: CatPalette.farFur)
        }
        drawTail(ctx, look.tail, puff: look.tailPuff)
        drawTorso(ctx, p)
        if p.tuck < 0.95 {
            drawLeg(ctx, p, index: 2, color: CatPalette.fur)
            drawLeg(ctx, p, index: 0, color: CatPalette.fur)
        } else {
            // Front paws peeking out of a loaf.
            ctx.setFillColor(CatPalette.fur)
            ctx.fillEllipse(in: oval(add(p.feet[0], 1, 2), 8, 5))
        }
        // Neck.
        ctx.setStrokeColor(CatPalette.fur)
        ctx.setLineWidth(p.chestR * 1.25)
        ctx.move(to: p.chest)
        ctx.addLine(to: add(p.head, -2, -3))
        ctx.strokePath()
        drawHead(ctx, p, look: look)

        ctx.endTransparencyLayer()
        ctx.restoreGState()

        drawRim(ctx, p)
        drawFace(ctx, p, look: look)
    }

    private static func drawLeg(_ ctx: CGContext, _ p: CatPose, index i: Int, color: CGColor) {
        let front = i < 2
        let farShift: CGFloat = (i == 1 || i == 3) ? -3 : 0
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        let foot = p.feet[i]
        if front {
            let root = add(p.chest, 1 + farShift, -3)
            let wrist = add(foot, 0.5, 3.5)
            let (elbow, w) = twoBone(root: root, target: wrist, l1: 12, l2: 12.5, bend: -1)
            ctx.setLineWidth(8.5); ctx.move(to: root); ctx.addLine(to: elbow); ctx.strokePath()
            ctx.setLineWidth(5.6); ctx.move(to: elbow); ctx.addLine(to: w); ctx.addLine(to: foot); ctx.strokePath()
            ctx.fillEllipse(in: oval(add(foot, 1.5, 1.8), 7.5, 4.6))
        } else {
            let root = add(p.hip, 2 + farShift, -3)
            let hock = add(foot, -4.5, 8)
            let (knee, h) = twoBone(root: root, target: hock, l1: 13, l2: 13, bend: 1)
            ctx.setLineWidth(12); ctx.move(to: root); ctx.addLine(to: knee); ctx.strokePath()
            ctx.setLineWidth(5.8); ctx.move(to: knee); ctx.addLine(to: h); ctx.strokePath()
            ctx.setLineWidth(4.6); ctx.move(to: h); ctx.addLine(to: foot); ctx.strokePath()
            ctx.fillEllipse(in: oval(add(foot, 1.5, 1.8), 7.5, 4.4))
        }
    }

    private static func drawTail(_ ctx: CGContext, _ pts: [CGPoint], puff: CGFloat) {
        guard pts.count > 1 else { return }
        ctx.setStrokeColor(CatPalette.fur)
        let n = CGFloat(pts.count - 1)
        for i in 1..<pts.count {
            let f = CGFloat(i) / n
            ctx.setLineWidth((5.2 - 2.2 * f) * puff)
            ctx.move(to: pts[i - 1]); ctx.addLine(to: pts[i]); ctx.strokePath()
        }
        // A rounder tip.
        ctx.setFillColor(CatPalette.fur)
        ctx.fillEllipse(in: circle(pts[pts.count - 1], 1.9 * puff))
    }

    private static func drawTorso(_ ctx: CGContext, _ p: CatPose) {
        ctx.setFillColor(CatPalette.fur)
        ctx.fillEllipse(in: circle(p.hip, p.hipR))
        ctx.fillEllipse(in: circle(p.chest, p.chestR))
        let dx = p.chest.x - p.hip.x, dy = p.chest.y - p.hip.y
        let len = max(hypot(dx, dy), 0.01)
        let nx = -dy / len, ny = dx / len
        ctx.move(to: pt(p.hip.x + nx * p.hipR, p.hip.y + ny * p.hipR))
        ctx.addLine(to: pt(p.chest.x + nx * p.chestR, p.chest.y + ny * p.chestR))
        ctx.addLine(to: pt(p.chest.x - nx * p.chestR, p.chest.y - ny * p.chestR))
        ctx.addLine(to: pt(p.hip.x - nx * p.hipR, p.hip.y - ny * p.hipR))
        ctx.closePath()
        ctx.fillPath()
        // A soft belly so the body is not a plain capsule.
        let m = mid(p.hip, p.chest)
        ctx.fillEllipse(in: oval(pt(m.x - nx * 2.5, m.y - ny * 2.5), len * 0.75, (p.hipR + p.chestR) * 0.95))
        if p.arch > 0.5 {
            ctx.fillEllipse(in: oval(pt(m.x + nx * p.arch * 0.6, m.y + ny * p.arch * 0.6),
                                     len * 0.9, (p.hipR + p.chestR) * 0.9 + p.arch))
        }
    }

    private static func earTriangles(_ p: CatPose) -> [(CGPoint, CGPoint, CGPoint)] {
        let e = p.earBack
        return [
            (pt(-8.5, 4.5), pt(-1.5, 8.2), pt(-7 - 5 * e, 16 - 8 * e)),
            (pt(1.5, 7.8), pt(9.5, 4.2), pt(7.5 + 5 * e, 16.5 - 8 * e)),
        ]
    }

    private static func drawHead(_ ctx: CGContext, _ p: CatPose, look: CatLook) {
        let r = p.headR
        ctx.saveGState()
        ctx.translateBy(x: p.head.x, y: p.head.y)
        ctx.rotate(by: p.headTilt)
        let s = r / 10.5
        ctx.scaleBy(x: s, y: s)
        ctx.setFillColor(CatPalette.fur)
        ctx.setStrokeColor(CatPalette.fur)
        ctx.setLineWidth(2.4)
        for (a, b, c) in earTriangles(p) {
            ctx.move(to: a); ctx.addLine(to: c); ctx.addLine(to: b); ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        }
        ctx.fillEllipse(in: oval(pt(0.8, -0.8), 23.5, 19.5))
        ctx.fillEllipse(in: oval(pt(6.3, -3.8), 10.5, 7.6))
        ctx.restoreGState()
    }

    private static func drawRim(_ ctx: CGContext, _ p: CatPose) {
        ctx.saveGState()
        ctx.setStrokeColor(CatPalette.rim)
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
        ctx.translateBy(x: p.head.x, y: p.head.y)
        ctx.rotate(by: p.headTilt)
        let s = p.headR / 10.5
        ctx.scaleBy(x: s, y: s)
        ctx.addArc(center: pt(0.8, -0.3), radius: 9.9, startAngle: 1.75, endAngle: 2.95, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawFace(_ ctx: CGContext, _ p: CatPose, look: CatLook) {
        ctx.saveGState()
        ctx.translateBy(x: p.head.x, y: p.head.y)
        ctx.rotate(by: p.headTilt)
        let s = p.headR / 10.5
        ctx.scaleBy(x: s, y: s)

        // Inner ears.
        ctx.setFillColor(CatPalette.earInner)
        for (a, b, c) in earTriangles(p) {
            let cx = (a.x + b.x + c.x) / 3, cy = (a.y + b.y + c.y) / 3
            func shrink(_ q: CGPoint) -> CGPoint { pt(cx + (q.x - cx) * 0.5, cy + (q.y - cy) * 0.5 - 0.4) }
            ctx.move(to: shrink(a)); ctx.addLine(to: shrink(c)); ctx.addLine(to: shrink(b)); ctx.closePath()
            ctx.fillPath()
        }

        // Eyes.
        let open = p.eyeOpen.clamped01()
        let eyes: [(CGPoint, CGFloat, CGFloat)] = [(pt(-2.4, 2.2), 4.9, 4.6), (pt(5.2, 1.6), 5.8, 5.0)]
        for (c, w, h) in eyes {
            if open < 0.12 {
                ctx.setStrokeColor(CatPalette.closedEye)
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
                ctx.setShadow(offset: .zero, blur: 3 + 5 * look.glow, color: CatPalette.glow.copy(alpha: 0.35 + 0.5 * look.glow))
            }
            ctx.setFillColor(CatPalette.irisOut)
            ctx.fillEllipse(in: rect)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: rect)
            ctx.clip()
            if let grad = CGGradient(colorsSpace: nil, colors: [CatPalette.irisIn, CatPalette.irisOut] as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(grad, startCenter: pt(c.x - 0.4, c.y + 0.6), startRadius: 0,
                                       endCenter: c, endRadius: w * 0.6, options: [.drawsAfterEndLocation])
            }
            let pw = 1.1 + 2.7 * p.pupil.clamped01()
            let gx = max(-1, min(1, look.gaze.dx)) * (w / 2 - pw / 2 - 0.3)
            let gy = max(-1, min(1, look.gaze.dy)) * 0.8
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fillEllipse(in: oval(pt(c.x + gx, c.y + gy), pw, h * 0.95))
            ctx.setFillColor(CatPalette.white)
            ctx.fillEllipse(in: circle(pt(c.x + gx + 0.9, c.y + gy + 1.0), 0.65))
            ctx.restoreGState()
        }

        // Nose, mouth, whiskers.
        ctx.setFillColor(CatPalette.nose)
        ctx.move(to: pt(9.6, -1.5)); ctx.addLine(to: pt(11.7, -1.5)); ctx.addLine(to: pt(10.7, -2.9)); ctx.closePath()
        ctx.fillPath()
        if p.mouthOpen > 0.05 {
            let mh = 4.6 * p.mouthOpen
            ctx.setFillColor(CatPalette.mouth)
            ctx.fillEllipse(in: oval(pt(8.6, -6.4 - mh * 0.25), 5.4, mh))
            if p.mouthOpen > 0.5 {
                ctx.setFillColor(CatPalette.white)
                for fx in [7.2, 10.0] as [CGFloat] {
                    ctx.move(to: pt(fx - 0.6, -4.6)); ctx.addLine(to: pt(fx + 0.6, -4.6)); ctx.addLine(to: pt(fx, -6.3)); ctx.closePath()
                    ctx.fillPath()
                }
            }
        }
        ctx.setStrokeColor(CatPalette.whisker)
        ctx.setLineWidth(0.55)
        for (ty, cy) in [(-1.2, -2.6), (-5.0, -4.6), (-8.8, -6.4)] as [(CGFloat, CGFloat)] {
            ctx.move(to: pt(9.5, -4.0))
            ctx.addQuadCurve(to: pt(24, ty), control: pt(17, cy))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: Still pictures (widget, icon)

    /// Renders a cat in a pose into a square bitmap, sitting on the bottom third.
    static func image(_ kind: PoseKind, size: Int, scale: CGFloat? = nil, gaze: CGVector = .zero, glow: CGFloat = 0.6,
                      halo: CGFloat = 0, tail: TailStyle? = nil) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let pose = CatPose.make(kind)
        let k = scale ?? CGFloat(size) / 110
        ctx.translateBy(x: CGFloat(size) / 2 + 4 * k, y: CGFloat(size) * 0.22)
        ctx.scaleBy(x: k, y: k)
        let style = tail ?? (kind == .sleep || kind == .loaf || kind == .sit ? .wrapped : .happy)
        let pts = TailChain().settle(root: tailRoot(pose), style: style, groundY: 0)
        draw(CatLook(pose: pose, tail: pts, gaze: gaze, glow: glow, groundShadow: 0, halo: halo), in: ctx)
        return ctx.makeImage()
    }
}

extension CGFloat {
    func clamped01(lo: CGFloat = 0) -> CGFloat { Swift.min(Swift.max(self, lo), 1) }
}

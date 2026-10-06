import CoreGraphics

/// A planned jump: where it starts, where it ends, how it flies.
struct JumpPlan: Equatable {
    var from: CGPoint
    var to: CGPoint
    var velocity: CGVector
    var duration: CGFloat
}

enum Ballistics {
    /// Velocity that carries a body from `p0` to `p1` under `gravity`, peaking
    /// `lift` points above the higher of the two.
    static func plan(from p0: CGPoint, to p1: CGPoint, gravity g: CGFloat, lift: CGFloat) -> JumpPlan {
        let apex = max(p0.y, p1.y) + max(lift, 1)
        let up = apex - p0.y
        let down = apex - p1.y
        let vy = (2 * g * up).squareRoot()
        let t = vy / g + (2 * down / g).squareRoot()
        let vx = (p1.x - p0.x) / t
        return JumpPlan(from: p0, to: p1, velocity: CGVector(dx: vx, dy: vy), duration: t)
    }

    static func position(of plan: JumpPlan, at t: CGFloat, gravity g: CGFloat) -> CGPoint {
        CGPoint(x: plan.from.x + plan.velocity.dx * t,
                y: plan.from.y + plan.velocity.dy * t - 0.5 * g * t * t)
    }

    /// A lift that looks right for the distance: low hops stay low, long leaps arc.
    static func naturalLift(from p0: CGPoint, to p1: CGPoint, scale: CGFloat) -> CGFloat {
        let d = hypot(p1.x - p0.x, p1.y - p0.y)
        return 14 * scale + d * 0.18
    }
}

import CoreGraphics

/// Small movements layered on top of a posture. Pure functions of time (or of an
/// impulse's progress), so the pose sheet can draw them without running the app.
/// Every offset starts and ends at zero, so nothing jumps when a movement begins.
enum CatMotion {
    /// Groom pose: licks the inside of a front paw, then wipes it over the muzzle and the ear. `t` in seconds.
    static func faceWash(_ p: inout CatPose, t: CGFloat) {
        let cycle: CGFloat = 1.9
        let u = t.truncatingRemainder(dividingBy: cycle) / cycle
        let split: CGFloat = 0.42
        if u < split {
            // Licking: the paw held at the mouth, the head bobbing on it.
            let k = sin(u / split * .pi * 4)
            p.feet[0].y += k * 1.2
            p.head.y += k * 0.9
            p.mouthOpen = max(p.mouthOpen, abs(sin(u / split * .pi)) * 0.3)
        } else {
            // Wiping: one loop forward over the muzzle, up past the ear, back down the cheek.
            let w = (u - split) / (1 - split)
            let a = w * 2 * .pi
            let dip = sin(w * .pi)
            p.feet[0].x += sin(a) * 5
            p.feet[0].y += (1 - cos(a)) * 6.5
            p.head.x += dip * 2
            p.head.y -= dip * 2.5
            p.headTilt -= dip * 0.3
            p.chest.x += dip * 1.5
            p.earBack = max(p.earBack, dip * 0.55)
        }
        p.eyeOpen = min(p.eyeOpen, 0.15)
    }

    /// Belly pose: rubbing the back on the floor, side to side, paws paddling in the air.
    static func roll(_ p: inout CatPose, t: CGFloat) {
        let r = sin(t * 2.6)
        p.hip.x += r * 2.5
        p.chest.x -= r * 1.5
        p.hip.y += abs(r) * 1.2
        p.head.x += r * 1.5
        p.headTilt += r * 0.22
        for i in 0..<4 {
            let ph = t * 5.2 + CGFloat(i) * 1.3
            p.feet[i].x += sin(ph) * 3 * abs(r)
            p.feet[i].y += (1 - cos(ph)) * 1.6 + abs(r) * 2
        }
    }

    /// After spinning after its own tail: the head goes round in small circles.
    static func dizzy(_ p: inout CatPose, t: CGFloat) {
        p.head.x += cos(t * 5) * 1.8
        p.head.y += sin(t * 5) * 1.2
        p.headTilt += sin(t * 5) * 0.12
        p.eyeOpen = min(p.eyeOpen, 0.55)
    }

    /// The tickle before a sneeze: nose up, eyes squeezed, mouth half open, a tremor.
    static func preSneeze(_ p: inout CatPose, t: CGFloat) {
        p.headTilt += 0.32
        p.head.y += 1 + sin(t * 31) * 0.35
        p.eyeOpen = min(p.eyeOpen, 0.2)
        p.mouthOpen = max(p.mouthOpen, 0.35)
    }

    /// The sneeze itself. `u` runs 0...1 over about a third of a second.
    static func sneeze(_ p: inout CatPose, u: CGFloat) {
        let k = sin(min(1, max(0, u)) * .pi)
        p.head.x += k * 3.5
        p.head.y -= k * 5
        p.headTilt -= k * 0.55
        p.chest.x += k * 1.5
        p.chest.y -= k * 1.2
        p.eyeOpen = min(p.eyeOpen, 1 - k)
        p.earBack = max(p.earBack, k * 0.7)
        p.mouthOpen = max(p.mouthOpen, k * 0.5)
    }

    /// A dream while asleep: the paws run a little, the head and ears jerk. `u` runs 0...1.
    static func dream(_ p: inout CatPose, u: CGFloat) {
        let env = sin(min(1, max(0, u)) * .pi)
        let run = sin(u * 26)
        p.tuck = min(p.tuck, 1 - 0.12 * env)
        p.feet[0].x += run * 2.6 * env
        p.feet[1].x -= run * 2.6 * env
        p.feet[2].x -= run * 2 * env
        p.head.y += sin(u * 19) * 0.7 * env
        p.earBack = max(p.earBack, max(0, sin(u * 14)) * 0.6 * env)
        p.mouthOpen = max(p.mouthOpen, max(0, sin(u * 9)) * 0.12 * env)
    }
}

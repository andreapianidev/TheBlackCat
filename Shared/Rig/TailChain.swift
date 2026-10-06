import CoreGraphics
import Foundation

/// The tail as a chain of damped springs. Each segment chases its target angle
/// and is pushed around by the body's acceleration, so it lags, swings and settles.
final class TailChain {
    let count = 11
    let segment: CGFloat = 4.1
    private var angles: [CGFloat]
    private var speeds: [CGFloat]
    private var time: CGFloat = 0

    init(angle: CGFloat = 2.75) {
        angles = Array(repeating: angle, count: count)
        speeds = Array(repeating: 0, count: count)
    }

    private func target(_ i: Int, _ s: TailStyle) -> CGFloat {
        let f = CGFloat(i + 1) / CGFloat(count)
        return s.angle + s.curl * pow(f, 1.3)
            + s.waveAmp * sin(time * s.waveFreq * 2 * .pi - CGFloat(i) * 0.55) * f
    }

    /// - Parameter accel: the body's acceleration in rig space, points/s².
    func step(_ dt: CGFloat, root: CGPoint, style s: TailStyle, accel: CGVector, groundY: CGFloat?) -> [CGPoint] {
        let dt = min(dt, 1.0 / 30)
        time += dt
        let k = s.stiffness
        let damping = 2 * k.squareRoot() * 0.6
        let sub = 2
        let h = dt / CGFloat(sub)
        for _ in 0..<sub {
            for i in 0..<count {
                let f = CGFloat(i + 1) / CGFloat(count)
                let a = angles[i]
                let push = (-accel.dy * cos(a) + accel.dx * sin(a)) * 0.012 * f
                let acc = k * (target(i, s) - a) - damping * speeds[i] + push
                speeds[i] += acc * h
                angles[i] += speeds[i] * h
            }
        }
        return points(root: root, groundY: groundY)
    }

    /// The tail at rest in the given style, for still pictures.
    func settle(root: CGPoint, style: TailStyle, groundY: CGFloat?) -> [CGPoint] {
        for i in 0..<count { angles[i] = target(i, style); speeds[i] = 0 }
        return points(root: root, groundY: groundY)
    }

    private func points(root: CGPoint, groundY: CGFloat?) -> [CGPoint] {
        var pts = [root]
        var p = root
        for a in angles {
            p = CGPoint(x: p.x + cos(a) * segment, y: p.y + sin(a) * segment)
            if let g = groundY { p.y = max(p.y, g + 1.6) }
            pts.append(p)
        }
        return pts
    }
}

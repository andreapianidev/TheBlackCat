import AppKit

/// Little extras layered on top of a posture.
struct Flourish: OptionSet {
    let rawValue: Int
    static let purr = Flourish(rawValue: 1 << 0)
    static let wiggle = Flourish(rawValue: 1 << 1)
    static let knead = Flourish(rawValue: 1 << 2)
    static let lick = Flourish(rawValue: 1 << 3)
    static let wavePaw = Flourish(rawValue: 1 << 4)
    static let sway = Flourish(rawValue: 1 << 5)
    static let chatter = Flourish(rawValue: 1 << 6)
    static let meow = Flourish(rawValue: 1 << 7)
    static let yawn = Flourish(rawValue: 1 << 8)
    static let eat = Flourish(rawValue: 1 << 9)
}

/// What the view needs to place the drawing on screen.
struct CatFrame {
    var look: CatLook
    var rotation: CGFloat
    var facing: CGFloat
    var scale: CGFloat
}

/// Turns the body's state and the brain's intentions into a pose, frame by frame.
@MainActor
final class Animator {
    var kind: PoseKind = .stand
    var tailStyle: TailStyle = .relaxed
    var flourish: Flourish = []
    /// Where to look, in global coordinates. Nil lets the eyes wander.
    var lookAt: CGPoint?
    /// Looking straight out of the screen, at the person.
    var lookAtViewer = false
    var eyesClosed = false
    var beat: CGFloat = 2

    private(set) var pose = CatPose.make(.stand)
    private let tail = TailChain()
    private var time: CGFloat = 0
    private var phase: CGFloat = 0
    private var gaitWeight: CGFloat = 0
    private var displayFacing: CGFloat = 1
    private var displayRotation: CGFloat = 0
    private var gaze = CGVector.zero
    private var wander = CGVector.zero
    private var nextWander: CGFloat = 1
    private var nextBlink: CGFloat = 2
    private var blinkT: CGFloat = -1
    private var nextTwitch: CGFloat = 4
    private var twitchT: CGFloat = -1
    private var squash: CGFloat = 0
    private var puffBoost: CGFloat = 0
    private var pupilBoost: CGFloat = 0

    private(set) var lastFrame: CatFrame?

    func landed(speed: CGFloat) { squash = min(1, speed / 1600) }
    func startle() { puffBoost = 1; pupilBoost = 1 }

    func update(_ dt: CGFloat, body: CatBody, dark: Bool) -> CatFrame {
        time += dt

        // Blend toward the target posture.
        var target = CatPose.make(kind)
        if eyesClosed || flourish.contains(.purr) { target.eyeOpen = min(target.eyeOpen, 0.08) }
        if flourish.contains(.meow) { target.mouthOpen = 0.7 }
        if flourish.contains(.yawn) { target.mouthOpen = 1; target.eyeOpen = 0.05; target.headTilt += 0.35 }
        if lookAtViewer { target.pupil = max(target.pupil, 0.75) }
        target.pupil = min(1, target.pupil + pupilBoost * 0.6)
        let airborne = kind == .airUp || kind == .airDown || kind == .dangle
        let rate: CGFloat = airborne ? 16 : 8
        pose = CatPose.lerp(pose, target, 1 - exp(-rate * dt))
        var p = pose

        // Gait.
        let moving = body.groundSpeed > 1 && (body.isGrounded || isClimbing(body))
        gaitWeight += ((moving ? 1 : 0) - gaitWeight) * min(1, dt * 10)
        if gaitWeight > 0.01 {
            applyGait(&p, gait: body.gait, speed: body.groundSpeed / body.scale, dt: dt)
        }

        // Breathing.
        let sleeping = kind == .sleep
        let period: CGFloat = sleeping ? 4.2 : 2.6
        let breath = sin(time * 2 * .pi / period)
        p.hipR *= 1 + breath * (sleeping ? 0.035 : 0.018)
        p.chestR *= 1 + breath * (sleeping ? 0.04 : 0.022)
        p.head.y += breath * (sleeping ? 0.5 : 0.25)

        // Flourishes.
        if flourish.contains(.wiggle) {
            p.hip.x += sin(time * 15) * 1.4
            p.hip.y += sin(time * 30) * 0.6
        }
        if flourish.contains(.knead) {
            p.feet[0].y += max(0, sin(time * 6)) * 4
            p.feet[1].y += max(0, -sin(time * 6)) * 4
        }
        if flourish.contains(.lick) {
            p.head.y += sin(time * 8) * 1.1
            p.feet[0].y += sin(time * 8 + 0.6) * 1.5
        }
        if flourish.contains(.wavePaw) {
            p.feet[0].x += sin(time * 10) * 3.5
        }
        if flourish.contains(.sway) {
            p.head.x += sin(time * beat * .pi) * 1.6
            p.headTilt += sin(time * beat * .pi) * 0.12
        }
        if flourish.contains(.chatter) {
            p.mouthOpen = max(p.mouthOpen, (sin(time * 38) * 0.5 + 0.5) * 0.45)
        }
        if flourish.contains(.eat) {
            p.head.y += sin(time * 9) * 1.4
        }
        if flourish.contains(.purr) {
            p.headTilt += sin(time * 1.3) * 0.06
        }

        // Landing squash.
        if squash > 0.01 {
            let k = 1 - squash * 0.28
            p.hip.y *= k; p.chest.y *= k; p.head.y = p.head.y * k
            squash *= exp(-9 * dt)
        }

        // Blink and ear twitches.
        if p.eyeOpen > 0.3 {
            nextBlink -= dt
            if nextBlink <= 0 { blinkT = 0; nextBlink = .random(in: 2...6.5) }
        }
        if blinkT >= 0 {
            blinkT += dt
            let b = blinkT / 0.16
            p.eyeOpen *= b < 1 ? abs(1 - 2 * b) : 1
            if b >= 1 { blinkT = -1 }
        }
        nextTwitch -= dt
        if nextTwitch <= 0 { twitchT = 0; nextTwitch = .random(in: 3...10) }
        if twitchT >= 0 {
            twitchT += dt
            p.earBack = max(p.earBack, sin(min(1, twitchT / 0.22) * .pi) * 0.6)
            if twitchT > 0.22 { twitchT = -1 }
        }

        // Where the cat is facing and how it is rotated on screen.
        var rotation: CGFloat = 0
        switch body.loco {
        case .climbing(_, let side, _):
            rotation = side == .left ? .pi / 2 : -.pi / 2
        case .dragged:
            rotation = (-body.accel.dx * 0.00006).clamped(-0.5, 0.5)
        case .airborne:
            rotation = (atan2(body.vel.dy, abs(body.vel.dx) + 200) * 0.45) * body.facing
        default:
            rotation = 0
        }
        displayRotation += (rotation - displayRotation) * min(1, dt * 12)
        displayFacing += (body.facing - displayFacing) * min(1, dt * 14)
        let facingScale = abs(displayFacing) < 0.25 ? (displayFacing < 0 ? -0.25 : 0.25) : displayFacing

        // Eyes.
        nextWander -= dt
        if nextWander <= 0 {
            wander = CGVector(dx: .random(in: -0.8...0.8), dy: .random(in: -0.5...0.5))
            nextWander = .random(in: 0.6...2.5)
        }
        var gazeTarget = wander
        if lookAtViewer {
            gazeTarget = CGVector(dx: 0, dy: -0.15)
        } else if let t = lookAt {
            let head = CGPoint(x: body.pos.x + p.head.x * body.scale * displayFacing, y: body.pos.y + p.head.y * body.scale)
            var dx = t.x - head.x, dy = t.y - head.y
            let c = cos(-displayRotation), s = sin(-displayRotation)
            (dx, dy) = (dx * c - dy * s, dx * s + dy * c)
            dx *= displayFacing < 0 ? -1 : 1
            let len = max(hypot(dx, dy), 1)
            gazeTarget = CGVector(dx: dx / len, dy: dy / len)
        }
        gaze.dx += (gazeTarget.dx - gaze.dx) * min(1, dt * 10)
        gaze.dy += (gazeTarget.dy - gaze.dy) * min(1, dt * 10)

        // Tail.
        var style = tailStyle
        style.puff = max(style.puff, 1 + puffBoost * 0.9)
        if flourish.contains(.sway) { style.waveFreq = beat / 2; style.waveAmp = 0.45 }
        puffBoost *= exp(-0.8 * dt)
        pupilBoost *= exp(-1.5 * dt)
        let c = cos(-displayRotation), s = sin(-displayRotation)
        var a = CGVector(dx: body.accel.dx * c - body.accel.dy * s, dy: body.accel.dx * s + body.accel.dy * c)
        a.dx *= displayFacing < 0 ? -1 : 1
        a.dx /= body.scale; a.dy /= body.scale
        let groundY: CGFloat? = body.isGrounded ? 0 : nil
        let pts = tail.step(dt, root: CatRig.tailRoot(p), style: style, accel: a, groundY: groundY)

        let look = CatLook(pose: p, tail: pts, tailPuff: style.puff, gaze: gaze,
                           glow: dark ? 0.9 : 0.35,
                           groundShadow: body.isGrounded ? 0.18 : 0,
                           halo: dark ? 0.3 : 0.18)
        let frame = CatFrame(look: look, rotation: displayRotation, facing: facingScale, scale: body.scale)
        lastFrame = frame
        return frame
    }

    private func isClimbing(_ body: CatBody) -> Bool {
        if case .climbing = body.loco { return true }
        return false
    }

    private func applyGait(_ p: inout CatPose, gait: Gait, speed: CGFloat, dt: CGFloat) {
        let stride: CGFloat, stance: CGFloat, lift: CGFloat, offsets: [CGFloat]
        switch gait {
        case .walk: stride = 34; stance = 0.62; lift = 4; offsets = [0.25, 0.75, 0, 0.5]
        case .trot: stride = 48; stance = 0.5; lift = 6; offsets = [0.5, 0, 0, 0.5]
        case .run: stride = 74; stance = 0.38; lift = 8; offsets = [0.55, 0.65, 0, 0.1]
        case .climb: stride = 26; stance = 0.55; lift = 5; offsets = [0.5, 0, 0, 0.5]
        }
        phase += speed * dt / stride
        phase -= floor(phase)
        let w = gaitWeight
        let travel = stride * stance
        for i in 0..<4 {
            var psi = phase + offsets[i]
            psi -= floor(psi)
            var dx: CGFloat, up: CGFloat = 0
            if psi < stance {
                dx = travel * (0.5 - psi / stance)
            } else {
                let u = (psi - stance) / (1 - stance)
                dx = travel * (-0.5 + u)
                up = lift * sin(.pi * u)
            }
            p.feet[i].x += dx * w
            p.feet[i].y += up * w
        }
        let bob = sin(phase * 4 * .pi)
        switch gait {
        case .run:
            let flex = sin(phase * 2 * .pi) * 5 * w
            p.chest.x += flex; p.hip.x -= flex
            p.chest.y += bob * 2 * w; p.hip.y -= bob * 2 * w
            p.head.x += flex * 0.8
        default:
            p.hip.y += bob * 0.9 * w
            p.chest.y += sin(phase * 4 * .pi + 1.2) * 0.9 * w
            p.head.y += sin(phase * 4 * .pi + 1.6) * 0.7 * w
        }
    }
}

import AppKit

enum Gait {
    case walk, trot, run, climb

    /// Points per second at scale 1.
    var speed: CGFloat {
        switch self {
        case .walk: return 46
        case .trot: return 105
        case .run: return 240
        case .climb: return 62
        }
    }
}

enum Locomotion: Equatable {
    case grounded(Footing)
    case airborne
    case climbing(windowID: UInt32, side: WallSide, offsetY: CGFloat)
    case dragged
}

enum BodyEvent {
    case landed(speed: CGFloat)
    case startedFalling
    case grabbedWall
    case mantled
}

/// Where the cat is and how it moves. Global AppKit coordinates; `pos` is the
/// point on the ground between its feet.
@MainActor
final class CatBody {
    var pos: CGPoint
    var vel = CGVector.zero
    var facing: CGFloat = 1
    var loco: Locomotion
    var scale: CGFloat
    /// Horizontal speed this frame while walking, for the gait animation.
    private(set) var groundSpeed: CGFloat = 0
    private(set) var gait: Gait = .walk
    /// Smoothed acceleration, for the tail.
    private(set) var accel = CGVector.zero

    private var flight: (plan: JumpPlan, elapsed: CGFloat, grab: (UInt32, WallSide)?)?
    private var lastPos: CGPoint
    private var lastVel = CGVector.zero
    private var dragSamples: [(CGPoint, TimeInterval)] = []

    let gravity: CGFloat = 2300
    var maxJumpUp: CGFloat { 250 * scale }
    var maxJumpAcross: CGFloat { 380 * scale }

    init(pos: CGPoint, footing: Footing, scale: CGFloat) {
        self.pos = pos
        self.lastPos = pos
        self.loco = .grounded(footing)
        self.scale = scale
    }

    var isGrounded: Bool { if case .grounded = loco { return true }; return false }
    var isAirborne: Bool { loco == .airborne }
    var isPlannedFlight: Bool { flight != nil }

    var footing: Footing? { if case .grounded(let f) = loco { return f }; return nil }

    var windowUnderneath: UInt32? {
        switch loco {
        case .grounded(.window(let id, _)): return id
        case .climbing(let id, _, _): return id
        default: return nil
        }
    }

    func currentLedge(_ world: World) -> Ledge? {
        guard let f = footing else { return nil }
        return world.ledge(for: f, at: pos.x, margin: 3)
    }

    // MARK: Per frame

    /// Keeps the cat attached to what it stands on and integrates free flight.
    func update(_ dt: CGFloat, world: World) -> BodyEvent? {
        var event: BodyEvent?
        groundSpeed = max(0, groundSpeed - 600 * dt)
        switch loco {
        case .grounded(let f):
            event = followFooting(f, world: world)
        case .airborne:
            event = fly(dt, world: world)
        case .climbing(let id, let side, let off):
            if let w = world.window(id),
               world.walls.contains(where: { $0.windowID == id && $0.side == side }) {
                pos = CGPoint(x: side == .left ? w.frame.minX : w.frame.maxX, y: w.frame.minY + off)
            } else {
                fall()
                event = .startedFalling
            }
        case .dragged:
            break
        }

        let v = CGVector(dx: (pos.x - lastPos.x) / max(dt, 0.001), dy: (pos.y - lastPos.y) / max(dt, 0.001))
        let a = CGVector(dx: (v.dx - lastVel.dx) / max(dt, 0.001), dy: (v.dy - lastVel.dy) / max(dt, 0.001))
        let k = min(1, dt * 12)
        accel = CGVector(dx: accel.dx + (a.dx.clamped(-6000, 6000) - accel.dx) * k,
                         dy: accel.dy + (a.dy.clamped(-6000, 6000) - accel.dy) * k)
        lastVel = v
        lastPos = pos
        return event
    }

    private func followFooting(_ f: Footing, world: World) -> BodyEvent? {
        switch f {
        case .window(let id, let off):
            guard let w = world.window(id) else { fall(); return .startedFalling }
            let x = w.frame.minX + off
            guard world.ledge(for: f, at: x, margin: 6 * scale) != nil else {
                pos = CGPoint(x: x, y: w.frame.maxY)
                fall()
                return .startedFalling
            }
            pos = CGPoint(x: x, y: w.frame.maxY)
        case .floor:
            if let l = world.ledge(for: f, at: pos.x, margin: 2) {
                pos.y = l.y
            } else if let l = world.floors.first(where: { $0.span.contains(pos.x) }) ?? world.nearestFloor(to: pos.x) {
                pos = CGPoint(x: l.span.clamp(pos.x, inset: 4), y: l.y)
                loco = .grounded(.floor(screen: l.screen))
            }
        }
        return nil
    }

    private func fly(_ dt: CGFloat, world: World) -> BodyEvent? {
        if var f = flight {
            f.elapsed += dt
            flight = f
            if let grab = f.grab, f.elapsed >= f.plan.duration {
                flight = nil
                if let w = world.window(grab.0),
                   let wall = world.walls.first(where: { $0.windowID == grab.0 && $0.side == grab.1 }) {
                    let y = min(max(f.plan.to.y, wall.span.lo + 2), wall.span.hi - 2)
                    loco = .climbing(windowID: grab.0, side: grab.1, offsetY: y - w.frame.minY)
                    facing = grab.1 == .left ? 1 : -1
                    vel = .zero
                    pos = CGPoint(x: wall.x, y: y)
                    return .grabbedWall
                }
            }
        }
        vel.dy -= gravity * dt
        var np = CGPoint(x: pos.x + vel.dx * dt, y: pos.y + vel.dy * dt)

        let b = world.bounds
        if !b.isNull {
            if np.x < b.minX + 12 { np.x = b.minX + 12; vel.dx = abs(vel.dx) * 0.4 }
            if np.x > b.maxX - 12 { np.x = b.maxX - 12; vel.dx = -abs(vel.dx) * 0.4 }
            if np.y > b.maxY - 30 { np.y = b.maxY - 30; vel.dy = min(vel.dy, 0) }
        }
        if abs(vel.dx) > 30 { facing = vel.dx > 0 ? 1 : -1 }

        if vel.dy <= 0, flight?.grab == nil, let l = world.landing(x: np.x, fromY: pos.y, toY: np.y) {
            return land(on: l, x: np.x, world: world)
        }
        if let lowest = world.floors.map(\.y).min(), np.y < lowest - 40,
           let l = world.floors.first(where: { $0.span.contains(np.x) }) ?? world.nearestFloor(to: np.x) {
            return land(on: l, x: l.span.clamp(np.x, inset: 10), world: world)
        }
        pos = np
        return nil
    }

    private func land(on l: Ledge, x: CGFloat, world: World) -> BodyEvent {
        let speed = -vel.dy
        pos = CGPoint(x: x, y: l.y)
        if let id = l.windowID, let w = world.window(id) {
            loco = .grounded(.window(id: id, offsetX: x - w.frame.minX))
        } else {
            loco = .grounded(.floor(screen: l.screen))
        }
        vel = .zero
        flight = nil
        return .landed(speed: speed)
    }

    // MARK: Commands from the brain

    /// Walks along the current ledge. Returns true when there is nowhere further to go.
    @discardableResult
    func walk(toward x: CGFloat, gait g: Gait, dt: CGFloat, world: World) -> Bool {
        guard case .grounded(let f) = loco, let ledge = currentLedge(world) else { return true }
        let target = ledge.span.clamp(x, inset: 8 * scale)
        let dx = target - pos.x
        gait = g
        if abs(dx) < 1 { return true }
        facing = dx > 0 ? 1 : -1
        let step = g.speed * scale * dt
        pos.x += abs(dx) <= step ? dx : facing * step
        groundSpeed = g.speed * scale
        if case .window(let id, _) = f, let w = world.window(id) {
            loco = .grounded(.window(id: id, offsetX: pos.x - w.frame.minX))
        }
        return abs(target - pos.x) < 1
    }

    func turn(toward x: CGFloat) {
        if abs(x - pos.x) > 6 { facing = x > pos.x ? 1 : -1 }
    }

    func launch(to target: CGPoint, grab: (UInt32, WallSide)? = nil, lift: CGFloat? = nil) {
        let l = lift ?? Ballistics.naturalLift(from: pos, to: target, scale: scale)
        let plan = Ballistics.plan(from: pos, to: target, gravity: gravity, lift: l)
        vel = plan.velocity
        flight = (plan, 0, grab)
        loco = .airborne
        facing = target.x >= pos.x ? 1 : -1
        if let g = grab { facing = g.1 == .left ? 1 : -1 }
        pos.y += 1
    }

    func hop(_ vy: CGFloat, dx: CGFloat = 0) {
        vel = CGVector(dx: dx, dy: vy)
        flight = nil
        loco = .airborne
        pos.y += 1
    }

    func fall() {
        loco = .airborne
        flight = nil
        vel = CGVector(dx: vel.dx * 0.3, dy: 0)
    }

    /// Scrambles up a window side. Returns an event when it reaches the top or slips.
    func climb(_ dt: CGFloat, time: CGFloat, world: World) -> BodyEvent? {
        guard case .climbing(let id, let side, var off) = loco, let w = world.window(id) else { return nil }
        // Cats climb in bursts: push, pause, push.
        let burst = max(0, sin(time * 9)) * 1.6 + 0.2
        off += Gait.climb.speed * scale * burst * dt
        gait = .climb
        groundSpeed = Gait.climb.speed * scale
        let topReach = w.frame.height - 3
        if off >= topReach {
            let cornerX = side == .left ? w.frame.minX + 14 * scale : w.frame.maxX - 14 * scale
            if world.ledges.contains(where: { $0.windowID == id && $0.span.contains(cornerX) }) {
                pos = CGPoint(x: cornerX, y: w.frame.maxY)
                loco = .grounded(.window(id: id, offsetX: cornerX - w.frame.minX))
                facing = side == .left ? 1 : -1
                return .mantled
            }
            // No room on top: kick off the wall.
            hop(380 * scale, dx: (side == .left ? -1 : 1) * 160 * scale)
            return .startedFalling
        }
        loco = .climbing(windowID: id, side: side, offsetY: off)
        pos = CGPoint(x: side == .left ? w.frame.minX : w.frame.maxX, y: w.frame.minY + off)
        return nil
    }

    // MARK: Dragging

    func beginDrag() {
        loco = .dragged
        flight = nil
        vel = .zero
        dragSamples.removeAll()
    }

    func drag(to p: CGPoint) {
        pos = p
        let now = ProcessInfo.processInfo.systemUptime
        dragSamples.append((p, now))
        dragSamples.removeAll { now - $0.1 > 0.12 }
    }

    /// Lets go. Returns the throw speed.
    @discardableResult
    func release() -> CGFloat {
        var v = CGVector.zero
        if let first = dragSamples.first, let last = dragSamples.last, last.1 - first.1 > 0.01 {
            let t = CGFloat(last.1 - first.1)
            v = CGVector(dx: (last.0.x - first.0.x) / t, dy: (last.0.y - first.0.y) / t)
        }
        v.dx = v.dx.clamped(-2600, 2600)
        v.dy = v.dy.clamped(-2600, 2600)
        vel = v
        loco = .airborne
        flight = nil
        return hypot(v.dx, v.dy)
    }

    /// Puts the cat somewhere directly, used when it arrives on screen.
    func place(at p: CGPoint, footing: Footing) {
        pos = p
        lastPos = p
        loco = .grounded(footing)
        vel = .zero
        flight = nil
    }
}

import CoreGraphics

/// One move the cat can make from its current ledge.
struct Move {
    var takeoffX: CGFloat
    var target: CGPoint
    var grab: (UInt32, WallSide)?
    /// Where the cat ends up once the move is complete (top of the wall for a climb).
    var arrival: CGPoint
    var targetWindow: UInt32?
}

@MainActor
enum Navigator {
    /// Every jump or climb reachable from where the body stands.
    static func moves(for body: CatBody, in world: World, toward goal: CGPoint? = nil) -> [Move] {
        guard let here = body.currentLedge(world) else { return [] }
        let s = body.scale
        var out: [Move] = []

        for l in world.ledges {
            if l.windowID == here.windowID && l.screen == here.screen && l.span == here.span { continue }
            let dy = l.y - here.y
            if dy > body.maxJumpUp || dy < -1600 { continue }
            let desired = goal?.x ?? CGFloat.random(in: l.span.lo...max(l.span.lo + 1, l.span.hi))
            let landX = l.span.clamp(desired, inset: 16 * s)
            let takeoff = here.span.clamp(landX, inset: 10 * s)
            let gap = abs(landX - takeoff)
            if gap > body.maxJumpAcross { continue }
            // A small step to a ledge at the same height is just walking, not a jump.
            if abs(dy) < 4 && gap < 20 * s { continue }
            let p = CGPoint(x: landX, y: l.y)
            out.append(Move(takeoffX: takeoff, target: p, grab: nil, arrival: p, targetWindow: l.windowID))
        }

        for wall in world.walls where wall.windowID != here.windowID {
            guard let w = world.window(wall.windowID) else { continue }
            let dir: CGFloat = wall.side == .left ? -1 : 1
            let takeoff = here.span.clamp(wall.x + dir * 55 * s, inset: 8 * s)
            let gap = (takeoff - wall.x) * dir
            guard gap > 18 * s, gap < 230 * s else { continue }
            let grabY = min(here.y + body.maxJumpUp * 0.6, wall.span.hi - 20 * s)
            guard grabY >= wall.span.lo + 4, grabY > here.y + 25 * s else { continue }
            // Only climb what a jump cannot reach, and only if the wall reaches the top.
            guard w.frame.maxY - here.y > body.maxJumpUp * 0.75, wall.span.hi >= w.frame.maxY - 6 else { continue }
            let cornerX = wall.side == .left ? w.frame.minX + 14 * s : w.frame.maxX - 14 * s
            guard world.ledges.contains(where: { $0.windowID == wall.windowID && $0.span.contains(cornerX) }) else { continue }
            out.append(Move(takeoffX: takeoff, target: CGPoint(x: wall.x, y: grabY), grab: (wall.windowID, wall.side),
                            arrival: CGPoint(x: cornerX, y: w.frame.maxY), targetWindow: wall.windowID))
        }
        return out
    }

    /// The best next step toward a goal: walking on this ledge or a move. Nil when stuck.
    static func step(for body: CatBody, in world: World, toward goal: CGPoint) -> (walkX: CGFloat, move: Move?)? {
        guard let here = body.currentLedge(world) else { return nil }
        let s = body.scale
        let walkX = here.span.clamp(goal.x, inset: 8 * s)
        var bestScore = hypot(walkX - goal.x, here.y - goal.y)
        var best: Move?
        for m in moves(for: body, in: world, toward: goal) {
            let score = hypot(m.arrival.x - goal.x, m.arrival.y - goal.y) + 30 * s
            if score < bestScore { bestScore = score; best = m }
        }
        if let m = best { return (m.takeoffX, m) }
        if abs(walkX - body.pos.x) < 4 { return nil }
        return (walkX, nil)
    }
}

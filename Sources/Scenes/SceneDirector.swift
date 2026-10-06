import AppKit

enum SceneKind: String, CaseIterable {
    case bird, dog, mouse, yarn, butterfly, box, robot, rival, laser

    var title: String {
        switch self {
        case .bird: return "Uccellino"
        case .dog: return "Cane"
        case .mouse: return "Topolino"
        case .yarn: return "Gomitolo"
        case .butterfly: return "Farfalla"
        case .box: return "Scatola di cartone"
        case .robot: return "Robot aspirapolvere"
        case .rival: return "Gatto rivale"
        case .laser: return "Puntino laser"
        }
    }
}

/// What a scene can use: the cat, its brain, the voice, the bubble.
@MainActor
struct Stage {
    let brain: Brain
    let body: CatBody
    let play: (CatSound) -> Void
    let say: (String) -> Void
    var s: CGFloat { body.scale }

    /// The floor under the cat (or the nearest one).
    func floor(_ world: World) -> Ledge? {
        world.floors.first { $0.span.contains(body.pos.x) } ?? world.nearestFloor(to: body.pos.x)
    }
}

@MainActor
protocol SceneScript: AnyObject {
    var visitors: [Visitor] { get }
    /// Advances the scene. Returns true when it is over.
    func update(_ dt: CGFloat, world: World) -> Bool
}

/// Rare little scenes: a visitor arrives and the cat reacts.
@MainActor
final class SceneDirector {
    static let platformID: UInt32 = 0xFFFF_0001

    var enabled = true
    private let stage: Stage
    private var scene: SceneScript?
    private var panels: [ObjectIdentifier: VisitorPanel] = [:]
    private var nextAt = Date().addingTimeInterval(.random(in: 300...600))

    init(stage: Stage) { self.stage = stage }

    var isActive: Bool { scene != nil }

    var platforms: [WindowInfo] {
        (scene?.visitors ?? []).compactMap { v in
            v.platform.map { WindowInfo(id: Self.platformID, frame: $0, pid: 0, owner: "Robot") }
        }
    }

    func start(_ kind: SceneKind?, world: World) {
        stop()
        guard let floor = stage.floor(world) else { return }
        let k = kind ?? SceneKind.allCases.randomElement()!
        switch k {
        case .bird: scene = BirdScene(stage, world: world, floor: floor)
        case .dog: scene = DogScene(stage, floor: floor)
        case .mouse: scene = MouseScene(stage, floor: floor)
        case .yarn: scene = YarnScene(stage, floor: floor)
        case .butterfly: scene = ButterflyScene(stage)
        case .box: scene = BoxScene(stage, floor: floor)
        case .robot: scene = RobotScene(stage, floor: floor)
        case .rival: scene = RivalScene(stage, floor: floor)
        case .laser: scene = LaserScene(stage, floor: floor)
        }
    }

    func stop() {
        for p in panels.values { p.close() }
        panels.removeAll()
        if scene != nil { stage.brain.sceneEnded() }
        scene = nil
    }

    func tick(_ dt: CGFloat, world: World, paused: Bool) {
        if paused { if scene != nil { stop() }; return }
        if scene == nil {
            guard enabled, Date() > nextAt else { return }
            nextAt = Date().addingTimeInterval(.random(in: 600...1500))
            // A sleeping cat only wakes up for some visitors.
            if stage.brain.isAsleep && Bool.random() { return }
            start(nil, world: world)
            return
        }
        guard let sc = scene else { return }
        let finished = sc.update(dt, world: world)
        let live = Set(sc.visitors.map { ObjectIdentifier($0) })
        for (id, p) in panels where !live.contains(id) { p.close(); panels[id] = nil }
        for v in sc.visitors {
            let id = ObjectIdentifier(v)
            if panels[id] == nil { panels[id] = VisitorPanel(v) }
            panels[id]?.sync()
        }
        if finished {
            stop()
            nextAt = Date().addingTimeInterval(.random(in: 600...1500))
        }
    }
}

@MainActor private func offscreen(_ v: Visitor, _ world: World) -> Bool {
    !world.bounds.insetBy(dx: -160, dy: -160).contains(v.pos)
}

// MARK: - Bird: lands nearby, gets stalked, flies off at the last moment

private final class BirdScene: SceneScript {
    let stage: Stage
    let bird: Bird
    var visitors: [Visitor] { [bird] }
    private var huntStarted = false
    private var saidSomething = false
    private var fledAt: CGFloat?
    private var time: CGFloat = 0

    init(_ stage: Stage, world: World, floor: Ledge) {
        self.stage = stage
        let s = stage.s
        let ledge = stage.body.currentLedge(world) ?? floor
        let side: CGFloat = Bool.random() ? 1 : -1
        var x = stage.body.pos.x + side * .random(in: 160...260) * s
        if !ledge.span.contains(x, margin: -20 * s) { x = stage.body.pos.x - side * .random(in: 160...260) * s }
        let perch = CGPoint(x: ledge.span.clamp(x, inset: 20 * s), y: ledge.y)
        let b = world.bounds
        let start = CGPoint(x: perch.x > stage.body.pos.x ? b.maxX + 40 : b.minX - 40, y: min(b.maxY - 60, perch.y + 260 * s))
        bird = Bird(from: start, landing: perch, scale: s)
        stage.play(.chirp)
    }

    func update(_ dt: CGFloat, world: World) -> Bool {
        time += dt
        bird.update(dt)
        let body = stage.body
        if bird.state == .perched && !huntStarted {
            huntStarted = true
            stage.play(.chirp)
            stage.brain.sceneHunt({ [weak bird] in bird?.state == .perched ? bird?.pos : nil })
        }
        if bird.state == .perched {
            let d = bird.pos.distance(to: body.pos)
            if (body.isAirborne && d < 170 * stage.s) || d < 55 * stage.s || bird.perchedFor > 28 {
                bird.flee(from: body.pos.x)
                stage.play(.chirp)
                fledAt = time
            }
        }
        if let f = fledAt, !saidSomething, time - f > 1.2, body.isGrounded {
            saidSomething = true
            stage.say(["Quasi.", "Lo lascio vivere. Per oggi.", "Uccellino. Ti ricorderò."].randomElement()!)
        }
        return bird.state == .fleeing && offscreen(bird, world)
    }
}

// MARK: - Dog: barks its way in, the cat bolts

private final class DogScene: SceneScript {
    let stage: Stage
    let dog: Dog
    var visitors: [Visitor] { [dog] }
    private enum Phase { case enter, sniff, leave }
    private var phase = Phase.enter
    private var scared = false
    private var nextBark: CGFloat = 0.2
    private var timer: CGFloat = 0
    private let stopX: CGFloat
    private let exitDir: CGFloat

    init(_ stage: Stage, floor: Ledge) {
        self.stage = stage
        let s = stage.s
        let fromLeft = stage.body.pos.x < (floor.span.lo + floor.span.hi) / 2
        let startX = fromLeft ? floor.span.lo - 120 : floor.span.hi + 120
        dog = Dog(at: CGPoint(x: startX, y: floor.y), scale: s)
        dog.speed = (fromLeft ? 1 : -1) * 310 * s
        stopX = floor.span.clamp(stage.body.pos.x, inset: 80 * s)
        exitDir = fromLeft ? 1 : -1
    }

    func update(_ dt: CGFloat, world: World) -> Bool {
        dog.update(dt)
        nextBark -= dt
        if nextBark <= 0 && phase != .leave {
            dog.bark()
            stage.play(.bark)
            nextBark = .random(in: 0.7...1.3)
        }
        let s = stage.s
        if !scared && (abs(dog.pos.x - stage.body.pos.x) < 520 * s || timer > 1.5) {
            scared = true
            if stage.body.windowUnderneath == nil {
                stage.brain.sceneFlee(from: dog.pos.x)
            } else {
                stage.brain.sceneStandoff(facing: dog.pos.x)
            }
        }
        timer += dt
        switch phase {
        case .enter:
            if (dog.speed > 0 && dog.pos.x >= stopX) || (dog.speed < 0 && dog.pos.x <= stopX) {
                dog.speed = 0
                dog.sniffing = true
                phase = .sniff
                timer = 0
            }
        case .sniff:
            if timer > 3 {
                dog.sniffing = false
                dog.speed = exitDir * 260 * s
                phase = .leave
            }
        case .leave:
            return offscreen(dog, world)
        }
        return false
    }
}

// MARK: - Mouse: darts across, never caught

private final class MouseScene: SceneScript {
    let stage: Stage
    let mouse: Mouse
    var visitors: [Visitor] { [mouse] }
    private let dir: CGFloat
    private var burst: CGFloat = 0
    private var chases = 0
    private var started = false
    private var panic: CGFloat = 0

    init(_ stage: Stage, floor: Ledge) {
        self.stage = stage
        dir = Bool.random() ? 1 : -1
        let startX = dir > 0 ? floor.span.lo - 30 : floor.span.hi + 30
        mouse = Mouse(at: CGPoint(x: startX, y: floor.y), scale: stage.s)
        stage.play(.squeak)
        mouse.squeak()
    }

    private func chase() {
        guard chases < 3 else { return }
        chases += 1
        stage.brain.sceneChase({ [weak mouse] in mouse?.pos }, gait: .sprint) { [weak self] in self?.chase() }
    }

    func update(_ dt: CGFloat, world: World) -> Bool {
        let s = stage.s
        burst -= dt
        if burst <= 0 { burst = .random(in: 0.35...0.8) }
        let running = burst > 0.3 || panic > 0
        mouse.speed = running ? dir * (panic > 0 ? 560 : 330) * s : 0
        panic = max(0, panic - dt)
        mouse.update(dt)
        if !started && world.bounds.contains(mouse.pos) {
            started = true
            chase()
        }
        if stage.body.isAirborne && mouse.pos.distance(to: stage.body.pos) < 90 * s && panic == 0 {
            panic = 1.2
            mouse.squeak()
            stage.play(.squeak)
        }
        if started && offscreen(mouse, world) {
            if stage.body.isGrounded { stage.say(["Domani.", "Era un topo. Credo.", "La prossima volta."].randomElement()!) }
            return true
        }
        return false
    }
}

// MARK: - Yarn: falls from above, gets batted around

private final class YarnScene: SceneScript {
    let stage: Stage
    let yarn: Yarn
    var visitors: [Visitor] { [yarn] }
    private var kicks = 0
    private var started = false
    private var time: CGFloat = 0
    private var leaving = false

    init(_ stage: Stage, floor: Ledge) {
        self.stage = stage
        let s = stage.s
        let x = floor.span.clamp(stage.body.pos.x + (Bool.random() ? 1 : -1) * 200 * s, inset: 40 * s)
        yarn = Yarn(at: CGPoint(x: x, y: floor.y + 500 * s), floorY: floor.y, minX: floor.span.lo + 12, maxX: floor.span.hi - 12, scale: s)
    }

    private func chase() {
        guard !leaving else { return }
        stage.brain.sceneChase({ [weak yarn] in yarn.map { CGPoint(x: $0.pos.x, y: $0.pos.y) } }, gait: .trot) { [weak self] in
            self?.kick()
        }
    }

    private func kick() {
        guard !leaving else { return }
        kicks += 1
        let s = stage.s
        if yarn.pos.distance(to: stage.body.pos) < 70 * s {
            let dir = stage.body.facing
            yarn.vel = CGVector(dx: dir * .random(in: 260...420) * s, dy: .random(in: 80...200) * s)
        }
        if kicks >= 5 {
            // The last one goes all the way.
            leaving = true
            yarn.walls = false
            let dir: CGFloat = yarn.pos.x > (yarn.minX + yarn.maxX) / 2 ? 1 : -1
            yarn.vel = CGVector(dx: dir * 900 * s, dy: 160 * s)
            stage.say(["Vinto.", "Ho vinto io.", "Non tornare."].randomElement()!)
            return
        }
        chase()
    }

    func update(_ dt: CGFloat, world: World) -> Bool {
        time += dt
        yarn.update(dt)
        if !started && yarn.onFloor {
            started = true
            chase()
        }
        if leaving { return offscreen(yarn, world) || time > 60 }
        if time > 45 { leaving = true; yarn.walls = false; yarn.vel = CGVector(dx: 900 * stage.s, dy: 0) }
        return false
    }
}

// MARK: - Butterfly: teases, gets chased, lands on the nose

private final class ButterflyScene: SceneScript {
    let stage: Stage
    let fly: Butterfly
    var visitors: [Visitor] { [fly] }
    private enum Phase { case tease, attempt, land, away }
    private var phase = Phase.tease
    private var timer: CGFloat = 0

    init(_ stage: Stage) {
        self.stage = stage
        let s = stage.s
        let head = CGPoint(x: stage.body.pos.x, y: stage.body.pos.y + 80 * s)
        fly = Butterfly(at: CGPoint(x: head.x + 300 * s, y: head.y + 250 * s), target: head, scale: s)
        stage.brain.sceneWatch({ [weak fly] in fly?.pos }, for: 7)
    }

    private var nose: CGPoint {
        let s = stage.s, b = stage.body
        return CGPoint(x: b.pos.x + b.facing * 15 * s, y: b.pos.y + 50 * s)
    }

    func update(_ dt: CGFloat, world: World) -> Bool {
        timer += dt
        let s = stage.s
        fly.update(dt)
        switch phase {
        case .tease:
            fly.target = CGPoint(x: stage.body.pos.x, y: stage.body.pos.y + 80 * s)
            if timer > 7 {
                phase = .attempt
                timer = 0
                stage.brain.sceneChase({ [weak fly] in fly?.pos }, gait: .walk)
            }
        case .attempt:
            fly.target = CGPoint(x: stage.body.pos.x + 40 * s, y: stage.body.pos.y + 120 * s)
            if timer > 4 && stage.body.isGrounded {
                phase = .land
                timer = 0
                stage.brain.sceneWatch({ [weak self] in self?.nose }, for: 4)
            }
        case .land:
            fly.target = nose
            fly.resting = fly.pos.distance(to: nose) < 6 * s
            if timer > 4 {
                phase = .away
                timer = 0
                fly.resting = false
                stage.brain.sceneSneeze()
            }
        case .away:
            fly.target = CGPoint(x: fly.pos.x + 400 * s, y: fly.pos.y + 500 * s)
            return offscreen(fly, world) || timer > 6
        }
        return false
    }
}

// MARK: - Box: if it fits, it sits

private final class BoxScene: SceneScript {
    let stage: Stage
    let box: CardboardBox
    var visitors: [Visitor] { [box] }
    private var sent = false
    private var wasInside = false
    private var time: CGFloat = 0
    private var fading: CGFloat?

    init(_ stage: Stage, floor: Ledge) {
        self.stage = stage
        let s = stage.s
        let x = floor.span.clamp(stage.body.pos.x + (Bool.random() ? 1 : -1) * 220 * s, inset: 60 * s)
        box = CardboardBox(at: CGPoint(x: x, y: floor.y + 420 * s), floorY: floor.y, scale: s)
    }

    func update(_ dt: CGFloat, world: World) -> Bool {
        time += dt
        box.update(dt)
        let s = stage.s
        if box.landed && !sent {
            sent = true
            stage.brain.sceneSitIn(at: box.pos, for: 30...60)
        }
        let inside = stage.body.pos.distance(to: box.pos) < 16 * s
        if inside { wasInside = true }
        if fading == nil && ((wasInside && !inside && stage.body.pos.distance(to: box.pos) > 70 * s) || time > 100) {
            fading = 0
        }
        if var f = fading {
            f += dt
            fading = f
            box.alpha = max(0, 1 - (f - 8) / 1.5)
            return f > 9.5
        }
        return false
    }
}

// MARK: - Robot vacuum: a taxi, or a monster

private final class RobotScene: SceneScript {
    let stage: Stage
    let robot: RobotVacuum
    var visitors: [Visitor] { [robot] }
    private var decided = false
    private var turns = 0
    private let floor: Ledge

    init(_ stage: Stage, floor: Ledge) {
        self.stage = stage
        self.floor = floor
        let fromLeft = Bool.random()
        robot = RobotVacuum(at: CGPoint(x: fromLeft ? floor.span.lo - 60 : floor.span.hi + 60, y: floor.y), scale: stage.s)
        robot.speed = (fromLeft ? 1 : -1) * 75 * stage.s
    }

    func update(_ dt: CGFloat, world: World) -> Bool {
        robot.update(dt)
        let s = stage.s
        // Bump into the screen edge once and turn around, then leave.
        if turns == 0 {
            if (robot.speed > 0 && robot.pos.x > floor.span.hi - 40 * s) || (robot.speed < 0 && robot.pos.x < floor.span.lo + 40 * s) {
                robot.speed = -robot.speed
                turns += 1
            }
        }
        let body = stage.body
        if !decided && body.isGrounded && body.windowUnderneath == nil && abs(robot.pos.x - body.pos.x) < 260 * s
            && world.bounds.contains(robot.pos) {
            decided = true
            if Double.random(in: 0..<1) < 0.55 {
                let lead = robot.speed * 0.45
                stage.brain.sceneBoard(top: CGPoint(x: robot.pos.x + lead, y: robot.pos.y + 13 * s), platform: SceneDirector.platformID)
            } else {
                stage.brain.sceneFlee(from: robot.pos.x)
            }
        }
        return turns > 0 && offscreen(robot, world)
    }
}

// MARK: - Rival cat: a standoff

private final class RivalScene: SceneScript {
    let stage: Stage
    let rival: RivalCat
    var visitors: [Visitor] { [rival] }
    private enum Phase { case enter, stare, hiss, leave }
    private var phase = Phase.enter
    private var timer: CGFloat = 0
    private let stopX: CGFloat
    private let exitX: CGFloat
    private var challenged = false

    init(_ stage: Stage, floor: Ledge) {
        self.stage = stage
        let s = stage.s
        let fromLeft = stage.body.pos.x > (floor.span.lo + floor.span.hi) / 2
        let startX = fromLeft ? floor.span.lo - 80 : floor.span.hi + 80
        rival = RivalCat(at: CGPoint(x: startX, y: floor.y), scale: s, coat: [CatCoat.chartreux, .ginger, .tabby].randomElement()!)
        stopX = stage.body.pos.x + (fromLeft ? -1 : 1) * 170 * s
        exitX = fromLeft ? floor.span.lo - 200 : floor.span.hi + 200
    }

    func update(_ dt: CGFloat, world: World) -> Bool {
        timer += dt
        let s = stage.s
        switch phase {
        case .enter:
            rival.anim.kind = .stand
            rival.anim.tailStyle = .alert
            rival.stroll(dt, toward: stopX, speed: 60 * s)
            if abs(rival.body.pos.x - stopX) < 2 { phase = .stare; timer = 0 }
            if !challenged && abs(rival.body.pos.x - stage.body.pos.x) < 420 * s {
                challenged = true
                stage.brain.sceneStandoff(facing: rival.body.pos.x)
            }
        case .stare:
            rival.stroll(dt, toward: nil, speed: 0)
            rival.body.facing = stage.body.pos.x > rival.body.pos.x ? 1 : -1
            rival.anim.kind = .sit
            rival.anim.tailStyle = .annoyed
            rival.anim.lookAt = stage.body.pos
            if timer > 2 { phase = .hiss; timer = 0; rival.anim.startle(); stage.play(.hiss) }
        case .hiss:
            rival.anim.kind = .hiss
            rival.anim.tailStyle = .angry
            if timer > 2.5 { phase = .leave; timer = 0 }
        case .leave:
            rival.anim.kind = .stand
            rival.anim.tailStyle = .happy
            rival.stroll(dt, toward: exitX, speed: 70 * s)
            if timer > 1 && offscreen(rival, world) { return true }
        }
        rival.update(dt)
        return timer > 40
    }
}

// MARK: - Laser dot: pure madness

private final class LaserScene: SceneScript {
    let stage: Stage
    let dot: LaserDot
    var visitors: [Visitor] { [dot] }
    private var time: CGFloat = 0
    private var next: CGFloat = 0
    private let length = CGFloat.random(in: 16...22)
    private let floor: Ledge

    init(_ stage: Stage, floor: Ledge) {
        self.stage = stage
        self.floor = floor
        let s = stage.s
        let start = CGPoint(x: floor.span.clamp(stage.body.pos.x + 120 * s, inset: 20), y: floor.y + 3)
        dot = LaserDot(at: start, scale: s)
        stage.brain.scenePlay(with: { [weak dot] in dot?.pos }, for: length)
    }

    func update(_ dt: CGFloat, world: World) -> Bool {
        time += dt
        next -= dt
        let s = stage.s
        if next <= 0 {
            next = .random(in: 0.4...1.2)
            let ledge = stage.body.currentLedge(world) ?? floor
            let x = ledge.span.clamp(stage.body.pos.x + .random(in: -380...380) * s, inset: 15)
            // Now and then it climbs a little way up a window, to be mean.
            let up: CGFloat = Int.random(in: 0..<5) == 0 ? .random(in: 40...120) * s : 0
            dot.target = CGPoint(x: x, y: ledge.y + 3 + up)
        }
        dot.update(dt)
        if time > length {
            stage.brain.sceneEnded()
            stage.say(["Dov'è andato?", "Era qui. Giuro.", "Lo troverò."].randomElement()!)
            return true
        }
        return false
    }
}

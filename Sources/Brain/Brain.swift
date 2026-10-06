import AppKit

enum CatSound { case meow, meowLong, demand, trill, hiss, crunch, chatter }
enum ParticleKind { case zzz, heart, bang, note, question, ring }
enum WeatherMood: Equatable { case rain, sun, cold, heat, mild }

/// Things that happen to the cat, from the senses, the menu or the system.
enum CatEvent {
    case called(strong: Bool)
    case praised, scolded, getDown, foodWord, sleepCommand, jumpCommand
    case loudNoise, dog, otherCat, whistle
    case music(Bool)
    case wave
    case userLeft, userBack
    case sawAnimal(dog: Bool, at: CGPoint)
    case sawPrey(at: CGPoint)
    case sawWord(String, at: CGPoint)
    case macWoke
    case hotMac(Bool)
    case lowBattery, charging
    case weather(WeatherMood)
    case meeting(String, Int)
    case appActivated(String)
    case feed(bowl: CGPoint)
    case find
    case clicked, doubleClicked
    case thrown(speed: CGFloat)
}

/// How the brain acts on the world. The controller implements it.
@MainActor
protocol BrainOutput: AnyObject {
    var cursor: CGPoint { get }
    var canNudge: Bool { get }
    func say(_ topic: ThoughtTopic)
    func sayText(_ text: String)
    func play(_ sound: CatSound)
    func emit(_ particle: ParticleKind)
    func nudge(window: UInt32, dx: CGFloat)
    func ate(_ fraction: CGFloat)
    func sleptOn(owner: String)
}

private enum TaskKind {
    case hold(PoseKind, TailStyle, Flourish)
    case walk(x: CGFloat, gait: Gait)
    case jump(Move)
    case stalk
    case eat
    case nudge(window: UInt32, dx: CGFloat)
    case say(ThoughtTopic)
    case text(String)
    case sound(CatSound)
    case face(CGFloat)
    case particle(ParticleKind)
    case hop(CGFloat)
}

private struct Task {
    var kind: TaskKind
    var duration: CGFloat = 0
    var elapsed: CGFloat = 0
    var launched = false
    var tick: CGFloat = 0

    static func hold(_ k: PoseKind, _ d: ClosedRange<CGFloat>, _ tail: TailStyle = .relaxed, _ f: Flourish = []) -> Task {
        Task(kind: .hold(k, tail, f), duration: .random(in: d))
    }
}

/// Somewhere the cat is heading, and what it does once there.
private struct Goal {
    var target: () -> CGPoint?
    var gait: Gait
    var radius: CGFloat
    var onArrive: () -> [Task]
    var steps = 0
    var deadline: CGFloat
}

@MainActor
final class Brain {
    var needs = Needs()
    weak var out: BrainOutput?

    // What the senses and the system have told us.
    var userAway = false
    var faceVisible = false
    var musicPlaying = false
    var macIsHot = false
    var lowPower = false
    var weather: WeatherMood = .mild
    var mischiefAllowed = false

    private let body: CatBody
    private let anim: Animator
    private var world = World()
    private var queue: [Task] = []
    private var goal: Goal?
    private var time: CGFloat = 0
    private var pettingTime: CGFloat = 0
    private var wasPetted = false
    private var nextHeart: CGFloat = 0
    private var nextZ: CGFloat = 0
    private var thrownPending = false
    private var lastMischief: CGFloat = -900
    private var viewerGlanceUntil: CGFloat = 0

    init(body: CatBody, anim: Animator) {
        self.body = body
        self.anim = anim
    }

    // MARK: State, for the menu, the widget and the frame rate

    var isAsleep: Bool {
        if case .hold(.sleep, _, _)? = queue.first?.kind { return true }
        return false
    }

    var isPetted: Bool { pettingTime > 0.4 }

    var status: String {
        switch body.loco {
        case .dragged: return "Penzola dalla tua mano"
        case .airborne: return "Vola"
        case .climbing: return "Si arrampica"
        default: break
        }
        if isPetted { return "Fa le fusa" }
        guard let t = queue.first else { return "Si guarda intorno" }
        switch t.kind {
        case .hold(let k, _, _):
            switch k {
            case .sleep: return "Dorme"
            case .loaf: return "Fa la pagnotta"
            case .sit, .lookUp: return "Sta seduto e osserva"
            case .groom: return "Si lava"
            case .flat: return "Si è spalmato"
            case .stretch: return "Si stiracchia"
            case .hiss: return "Soffia"
            case .knead: return "Fa la pasta"
            case .wave: return "Ti saluta"
            case .crouch: return "Sta in agguato"
            default: return "Si guarda intorno"
            }
        case .walk(_, let g): return g == .run ? "Corre" : "Passeggia"
        case .jump: return "Salta"
        case .stalk: return "Caccia il puntatore"
        case .eat: return "Mangia"
        case .nudge: return "Combina un guaio"
        default: return "Si guarda intorno"
        }
    }

    private var doing: Needs.Doing {
        if isPetted { return .petted }
        guard let t = queue.first else { return .resting }
        switch t.kind {
        case .hold(.sleep, _, _): return .sleeping
        case .hold: return .resting
        case .walk(_, .run), .stalk: return .playing
        case .eat: return .eating
        default: return .active
        }
    }

    // MARK: Frame

    func update(_ dt: CGFloat, world: World) {
        self.world = world
        time += dt
        needs.tick(Double(dt), doing: doing)
        anim.flourish = []
        anim.eyesClosed = false
        anim.lookAtViewer = false
        anim.lookAt = nil

        switch body.loco {
        case .dragged:
            anim.kind = .dangle
            anim.tailStyle = .hanging
            anim.lookAt = out?.cursor
            return
        case .climbing:
            anim.kind = .stand
            anim.tailStyle = .alert
            if let e = body.climb(dt, time: time, world: world) { bodyEvent(e) }
            return
        case .airborne:
            anim.kind = body.vel.dy > 0 ? .airUp : .airDown
            anim.tailStyle = .falling
            return
        case .grounded:
            break
        }

        if isPetted {
            pettedFrame(dt)
            return
        }

        if queue.isEmpty { decide(world) }
        var guardCount = 0
        while !queue.isEmpty && guardCount < 8 {
            guardCount += 1
            if run(&queue[0], dt, world) {
                queue.removeFirst()
                if queue.isEmpty { break }
                continue
            }
            break
        }
        lookAround()
    }

    func bodyEvent(_ e: BodyEvent) {
        switch e {
        case .landed(let speed):
            anim.landed(speed: speed)
            if thrownPending {
                thrownPending = false
                if speed > 1100 || needs.grudge > 0.4 {
                    queue = [Task.hold(.hiss, 0.8...1.2, .angry), Task(kind: .say(.thrown)), Task.hold(.sit, 1.5...3, .annoyed, .lick)]
                    out?.play(.hiss)
                } else {
                    queue = [Task(kind: .say(.thrown)), Task.hold(.groom, 2...4, .annoyed, .lick)]
                }
            }
        case .startedFalling:
            goal = nil
            queue.removeAll()
        case .grabbedWall, .mantled:
            break
        }
    }

    private func lookAround() {
        guard let cursor = out?.cursor else { return }
        if faceVisible && time < viewerGlanceUntil {
            anim.lookAtViewer = true
            return
        }
        if faceVisible && Int.random(in: 0..<600) == 0 {
            viewerGlanceUntil = time + .random(in: 1.5...4)
        }
        if cursor.distance(to: body.pos) < 520 * body.scale { anim.lookAt = cursor }
    }

    // MARK: Running tasks

    /// Runs one frame of a task. Returns true when it is finished.
    private func run(_ t: inout Task, _ dt: CGFloat, _ world: World) -> Bool {
        t.elapsed += dt
        switch t.kind {
        case .hold(let k, let tail, let f):
            anim.kind = k
            anim.tailStyle = tail
            anim.flourish = f
            if k == .sleep {
                anim.eyesClosed = true
                nextZ -= dt
                if nextZ <= 0 { out?.emit(.zzz); nextZ = .random(in: 1.6...2.6) }
            }
            if musicPlaying && (k == .sit || k == .loaf) { anim.flourish.insert(.sway) }
            if t.elapsed >= t.duration {
                if k == .sleep, let id = body.windowUnderneath, let w = world.window(id) { out?.sleptOn(owner: w.owner) }
                return true
            }
            return false

        case .walk(let x, let g):
            anim.kind = .stand
            anim.tailStyle = g == .run ? .falling : (goal != nil ? .happy : .relaxed)
            return body.walk(toward: x, gait: g, dt: dt, world: world) || t.elapsed > 30

        case .jump(let m):
            if !t.launched {
                anim.kind = .crouch
                anim.tailStyle = .stalking
                anim.flourish = [.wiggle]
                body.turn(toward: m.target.x)
                if t.elapsed > 0.32 {
                    body.launch(to: m.target, grab: m.grab)
                    t.launched = true
                }
                return false
            }
            return body.isGrounded

        case .stalk:
            guard let c = out?.cursor else { return true }
            if !t.launched {
                anim.kind = .crouch
                anim.tailStyle = .stalking
                anim.lookAt = c
                if t.elapsed > t.duration * 0.6 { anim.flourish = [.wiggle] }
                body.turn(toward: c.x)
                if t.elapsed >= t.duration {
                    let s = body.scale
                    let dx = (c.x - body.pos.x).clamped(-body.maxJumpAcross, body.maxJumpAcross)
                    let dy = (c.y - body.pos.y).clamped(10 * s, body.maxJumpUp * 0.8)
                    body.launch(to: CGPoint(x: body.pos.x + dx, y: body.pos.y + dy), lift: 12 * s)
                    t.launched = true
                }
                return false
            }
            return body.isGrounded

        case .eat:
            anim.kind = .eat
            anim.tailStyle = .happy
            anim.flourish = [.eat]
            t.tick -= dt
            if t.tick <= 0 { out?.play(.crunch); t.tick = .random(in: 0.3...0.55) }
            out?.ate(min(1, t.elapsed / max(t.duration, 0.1)))
            if t.elapsed >= t.duration {
                needs.fed()
                out?.say(.fed)
                return true
            }
            return false

        case .nudge(let id, let dx):
            anim.kind = .wave
            anim.tailStyle = .stalking
            anim.flourish = [.wavePaw]
            if !t.launched && t.elapsed > 0.7 {
                out?.nudge(window: id, dx: dx)
                t.launched = true
            }
            return t.elapsed > 1.1

        case .say(let topic):
            out?.say(topic)
            return true
        case .text(let line):
            out?.sayText(line)
            return true
        case .sound(let s):
            out?.play(s)
            return true
        case .face(let x):
            body.turn(toward: x)
            return true
        case .particle(let p):
            out?.emit(p)
            return true
        case .hop(let vy):
            if !t.launched { body.hop(vy * body.scale); t.launched = true; return false }
            return body.isGrounded
        }
    }

    private func pettedFrame(_ dt: CGFloat) {
        let sleeping = isAsleep
        var loafing = false
        if case .hold(.loaf, _, _)? = queue.first?.kind { loafing = true }
        anim.kind = sleeping ? .sleep : (loafing ? .loaf : .sit)
        anim.tailStyle = sleeping ? .wrapped : .happy
        anim.flourish = sleeping ? [] : [.purr]
        anim.eyesClosed = true
        nextHeart -= dt
        if nextHeart <= 0 { out?.emit(.heart); nextHeart = .random(in: 0.5...0.9) }
    }

    // MARK: Petting

    /// Called every frame with whether a hand is stroking the cat.
    func petting(_ active: Bool, dt: CGFloat) {
        if active {
            pettingTime += dt
            if pettingTime > 0.4 && !wasPetted {
                wasPetted = true
                if needs.grudge > 0.65 && body.isGrounded {
                    pettingTime = -2
                    wasPetted = false
                    queue = [Task.hold(.hiss, 0.6...0.8, .angry), Task(kind: .sound(.hiss))]
                    walkAway()
                    return
                }
                if !isAsleep { queue = [Task.hold(.sit, 60...60, .happy)] }
            }
            if isPetted { needs.petted(Double(dt)) }
        } else if pettingTime != 0 {
            if wasPetted {
                wasPetted = false
                if !isAsleep {
                    queue = [Task.hold(.sit, 1...2, .happy), Task.hold(.groom, 2...4, .relaxed, .lick)]
                    if Int.random(in: 0..<3) == 0 { queue.insert(Task(kind: .say(.petted)), at: 0) }
                }
            }
            pettingTime = pettingTime < 0 ? min(0, pettingTime + dt) : 0
        }
    }

    // MARK: Decisions

    private func decide(_ world: World) {
        if var g = goal {
            guard let target = g.target() else { goal = nil; return }
            if body.pos.distance(to: target) < g.radius || g.steps > 10 || time > g.deadline {
                goal = nil
                queue = g.onArrive()
                return
            }
            g.steps += 1
            goal = g
            if let step = Navigator.step(for: body, in: world, toward: target) {
                queue.append(Task(kind: .walk(x: step.walkX, gait: g.gait)))
                if let m = step.move { queue.append(Task(kind: .jump(m))) }
            } else {
                goal = nil
                queue = g.onArrive()
            }
            return
        }

        let hour = Calendar.current.component(.hour, from: Date())
        let live = Circadian.liveliness(hour: hour)
        let sleepy = Circadian.sleepiness(hour: hour)
        let n = needs
        let cursorNear = isCursorHuntable(world)
        let onWindow = body.windowUnderneath != nil

        var options: [(Double, () -> Void)] = [
            (pow(1 - n.energy, 2) * 4 * sleepy + (userAway ? 1.5 : 0) + (lowPower ? 1 : 0), { self.planSleep(world) }),
            (0.7 + (1 - n.energy) * 0.8, { self.queue = [Task.hold(.loaf, 8...30, .wrapped)] }),
            (1.0, { self.queue = [Task.hold(.sit, 4...12, Bool.random() ? .wrapped : .relaxed)] }),
            (0.6, { self.queue = [Task.hold(.groom, 3...7, .relaxed, .lick)] }),
            (0.7, { self.queue = [Task.hold(.stand, 1.5...4, .alert)] }),
            (1.3 * live * n.energy, { self.planWander(world) }),
            (1.5 * n.curiosity * live * n.energy + 0.2, { self.planExplore(world) }),
            (0.2, { self.queue = [Task.hold(.lookUp, 2...4, .alert)] }),
            (0.15, { self.queue = [Task.hold(.stretch, 1.4...2, .happy)] }),
            (n.loneliness * 0.45, { self.queue = [Task.hold(.knead, 4...8, .happy, .knead)] }),
        ]
        if cursorNear {
            options.append((2.2 * n.boredom * n.energy * live, { self.queue = [Task(kind: .stalk, duration: .random(in: 1.0...2.4))] }))
        }
        if Circadian.isZoomiesHour(hour) && n.energy > 0.5 {
            options.append((0.6 * n.boredom, { self.planZoomies(world) }))
        }
        if n.hunger > 0.65 {
            options.append((2.2 * n.hunger, { self.planAsk(.hungry) }))
        }
        if n.loneliness > 0.7 && !userAway {
            options.append((1.2 * n.loneliness, { self.planAsk(.idle) }))
        }
        if mischiefAllowed, onWindow, n.boredom > 0.45, time - lastMischief > 900, out?.canNudge == true {
            options.append((0.35, { self.planMischief(world) }))
        }
        if macIsHot || weather == .heat {
            options.append((1.6, { self.queue = [Task.hold(.flat, 15...40, .relaxed)] }))
        }
        if weather == .sun && (8..<19).contains(hour) {
            options.append((0.6, {
                self.queue = [Task.hold(.loaf, 20...60, .wrapped)]
                if Int.random(in: 0..<4) == 0 { self.queue.insert(Task(kind: .say(.sun)), at: 0) }
            }))
        }
        if n.grudge > 0.5 && cursorNear {
            options.append((1.5 * n.grudge, { self.walkAway() }))
        }

        let total = options.reduce(0) { $0 + max(0, $1.0) }
        var r = Double.random(in: 0..<max(total, 0.0001))
        for (w, act) in options {
            r -= max(0, w)
            if r <= 0 { act(); return }
        }
        options.last?.1()
    }

    private func isCursorHuntable(_ world: World) -> Bool {
        guard let c = out?.cursor, let ledge = body.currentLedge(world) else { return false }
        let s = body.scale
        return abs(c.x - body.pos.x) < 420 * s && abs(c.x - body.pos.x) > 30 * s
            && c.y > ledge.y - 10 && c.y < ledge.y + 240 * s
    }

    // MARK: Plans

    private func planWander(_ world: World) {
        guard let l = body.currentLedge(world) else { return }
        let x = CGFloat.random(in: l.span.lo...max(l.span.lo + 1, l.span.hi))
        let g: Gait = Int.random(in: 0..<5) == 0 ? .trot : .walk
        queue = [Task(kind: .walk(x: x, gait: g)), Task.hold(Bool.random() ? .stand : .sit, 1...4, .relaxed)]
    }

    private func planExplore(_ world: World) {
        let moves = Navigator.moves(for: body, in: world)
        guard !moves.isEmpty else { planWander(world); return }
        let weights = moves.map { m -> Double in
            let up = max(0, m.arrival.y - body.pos.y)
            return 1 + Double(up / 90) * needs.curiosity + (m.grab != nil ? 0.6 : 0)
        }
        let total = weights.reduce(0, +)
        var r = Double.random(in: 0..<total)
        var pick = moves[0]
        for (m, w) in zip(moves, weights) {
            r -= w
            if r <= 0 { pick = m; break }
        }
        queue = [Task(kind: .walk(x: pick.takeoffX, gait: .walk)), Task(kind: .jump(pick))]
        let highest = world.ledges.map(\.y).max() ?? 0
        if abs(pick.arrival.y - highest) < 2 && pick.arrival.y > body.pos.y + 100 {
            queue.append(Task(kind: .say(.onTop)))
            queue.append(Task.hold(.sit, 5...12, .happy))
        } else if let id = pick.targetWindow, let w = world.window(id), Int.random(in: 0..<7) == 0 {
            queue.append(Task.hold(.sit, 3...8, .relaxed))
            queue.append(Task(kind: .say(.window(owner: w.owner))))
        }
    }

    private func planSleep(_ world: World) {
        let sequence: () -> [Task] = {
            var t: [Task] = [Task(kind: .face(self.body.pos.x - self.body.facing * 50)),
                             Task.hold(.stand, 0.4...0.6, .relaxed),
                             Task(kind: .face(self.body.pos.x + self.body.facing * 50)),
                             Task.hold(.loaf, 2...4, .wrapped)]
            if Int.random(in: 0..<3) == 0 { t.append(Task(kind: .say(.sleepy))) }
            let long: ClosedRange<CGFloat> = self.userAway ? 300...900 : 90...420
            t.append(Task.hold(.sleep, long, .wrapped))
            t.append(Task.hold(.stretch, 1.4...2, .happy))
            t.append(Task.hold(.sit, 1...1.4, .relaxed, .yawn))
            return t
        }
        if Int.random(in: 0..<10) < 4, let spot = favoriteSpot(world) {
            goal = Goal(target: { spot }, gait: .walk, radius: 40 * body.scale, onArrive: sequence, deadline: time + 60)
        } else {
            queue = sequence()
        }
    }

    var favorites: [String: Double] = [:]

    private func favoriteSpot(_ world: World) -> CGPoint? {
        let candidates = world.ledges.compactMap { l -> (CGPoint, Double)? in
            guard let id = l.windowID, let w = world.window(id), let score = favorites[w.owner], score > 0 else { return nil }
            return (CGPoint(x: l.span.clamp(l.span.lo + l.span.length * 0.3), y: l.y), score)
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    private func planZoomies(_ world: World) {
        guard let l = body.currentLedge(world) else { return }
        queue = [Task(kind: .say(.zoomies)), Task.hold(.crouch, 0.3...0.5, .stalking, .wiggle)]
        for i in 0..<Int.random(in: 3...6) {
            let x = i % 2 == 0 ? l.span.hi : l.span.lo
            queue.append(Task(kind: .walk(x: x, gait: .run)))
            if Int.random(in: 0..<3) == 0 { queue.append(Task(kind: .hop(520))) }
        }
        queue.append(Task.hold(.sit, 1...2, .alert))
        queue.append(Task.hold(.groom, 2...4, .relaxed, .lick))
    }

    private func planAsk(_ topic: ThoughtTopic) {
        goal = Goal(target: { [weak self] in self?.out?.cursor }, gait: .trot, radius: 60 * body.scale,
                    onArrive: {
                        [Task(kind: .face(self.out?.cursor.x ?? self.body.pos.x)),
                         Task.hold(.sit, 0.5...0.8, .happy),
                         Task(kind: .sound(topic == .hungry ? .demand : .meow)),
                         Task.hold(.sit, 1.2...1.6, .happy, .meow),
                         Task(kind: .say(topic)),
                         Task.hold(.sit, 3...6, .happy)]
                    }, deadline: time + 40)
    }

    private func planMischief(_ world: World) {
        guard let id = body.windowUnderneath, let l = body.currentLedge(world) else { return }
        lastMischief = time
        let toRight = body.pos.x > (l.span.lo + l.span.hi) / 2
        let edge = toRight ? l.span.hi - 12 * body.scale : l.span.lo + 12 * body.scale
        let dx: CGFloat = (toRight ? -1 : 1) * .random(in: 18...45)
        queue = [Task(kind: .walk(x: edge, gait: .walk)),
                 Task(kind: .face(toRight ? l.span.lo : l.span.hi)),
                 Task.hold(.sit, 1...2, .stalking),
                 Task(kind: .nudge(window: id, dx: dx)),
                 Task(kind: .say(.mischief)),
                 Task.hold(.sit, 2...4, .happy)]
    }

    private func walkAway() {
        guard let c = out?.cursor else { return }
        let x = body.pos.x + (body.pos.x > c.x ? 1 : -1) * 300 * body.scale
        queue.append(Task(kind: .walk(x: x, gait: .trot)))
        queue.append(Task.hold(.sit, 3...6, .annoyed))
    }

    private func wakeUpFirst() -> [Task] {
        isAsleep ? [Task.hold(.stretch, 1...1.5, .happy), Task.hold(.sit, 0.8...1, .relaxed, .yawn)] : []
    }

    /// The cat walks in from the edge of the screen.
    func arrive(walkTo x: CGFloat, firstTime: Bool, name: String) {
        queue = [Task(kind: .walk(x: x, gait: .walk)), Task.hold(.sit, 0.5...0.8, .happy), Task(kind: .sound(.trill))]
        if firstTime {
            queue.append(Task(kind: .text("Ciao. Mi chiamo \(name) e da oggi vivo qui.")))
            queue.append(Task.hold(.sit, 3...4, .happy))
            queue.append(Task(kind: .text("Trattami bene. Le finestre ora sono mie.")))
        } else {
            queue.append(Task(kind: .say(.userBack)))
        }
        queue.append(Task.hold(.groom, 2...4, .relaxed, .lick))
    }

    /// Picked up by the scruff: whatever it was doing is over.
    func pickedUp() {
        if isAsleep { needs.offended(0.1) }
        goal = nil
        queue.removeAll()
        pettingTime = 0
        wasPetted = false
    }

    func wakeUp() {
        if isAsleep { queue = wakeUpFirst() }
    }

    // MARK: Reactions

    func react(_ e: CatEvent) {
        if case .dragged = body.loco { return }
        let s = body.scale
        switch e {
        case .called(let strong):
            if !strong && (needs.grudge > 0.5 || Int.random(in: 0..<4) == 0) {
                if isAsleep { anim.startle(); return }
                queue = [Task.hold(.sit, 1...2, .annoyed), Task(kind: .say(.ignoredCall))]
                return
            }
            let pre = wakeUpFirst()
            planAsk(.idle)
            queue = pre
            out?.play(.trill)

        case .praised:
            queue = [Task(kind: .sound(.trill)), Task.hold(.sit, 2...3, .happy, .purr)]
            if Bool.random() { queue.append(Task(kind: .say(.praised))) }

        case .scolded:
            needs.offended(0.1)
            queue = [Task.hold(.sit, 1...1.5, .annoyed), Task(kind: .say(.scolded))]
            walkAway()

        case .getDown:
            guard body.windowUnderneath != nil else { return }
            goal = nil
            if let w = world.floors.first(where: { $0.span.contains(body.pos.x) }) ?? world.nearestFloor(to: body.pos.x) {
                let p = CGPoint(x: w.span.clamp(body.pos.x + body.facing * 40 * s, inset: 10 * s), y: w.y)
                let m = Move(takeoffX: body.pos.x, target: p, grab: nil, arrival: p, targetWindow: nil)
                queue = [Task(kind: .jump(m)), Task.hold(.sit, 2...4, .annoyed)]
            }

        case .foodWord:
            if needs.hunger > 0.35 { queue = wakeUpFirst(); planAsk(.hungry) } else { anim.startle() }

        case .sleepCommand:
            goal = nil
            queue = []
            planSleep(world)

        case .jumpCommand:
            queue = wakeUpFirst()
            planExplore(world)

        case .loudNoise:
            startle(hiss: Bool.random())
            if Int.random(in: 0..<3) == 0 { queue.append(Task(kind: .say(.clap))) }

        case .dog:
            anim.startle()
            goal = nil
            queue = [Task(kind: .sound(.hiss)), Task.hold(.hiss, 1.8...2.6, .angry)]
            if Bool.random() { queue.append(Task(kind: .say(.dog))) }

        case .otherCat:
            queue = [Task.hold(.lookUp, 1.2...2, .alert), Task(kind: .sound(Bool.random() ? .trill : .meow))]
            if Bool.random() { queue.append(Task(kind: .say(.otherCat))) }

        case .whistle:
            react(.called(strong: false))

        case .music(let on):
            if on && !musicPlaying && Int.random(in: 0..<3) == 0 { out?.say(.music) }
            musicPlaying = on

        case .wave:
            guard !isAsleep else { return }
            queue = [Task(kind: .face(out?.cursor.x ?? body.pos.x)), Task.hold(.wave, 1.4...1.8, .happy, .wavePaw),
                     Task(kind: .sound(.trill)), Task.hold(.sit, 2...3, .happy)]

        case .userLeft:
            userAway = true
            if Bool.random() { out?.say(.userGone) }

        case .userBack:
            userAway = false
            queue = wakeUpFirst() + [Task(kind: .say(.userBack)), Task(kind: .sound(.trill))]
            viewerGlanceUntil = time + 3

        case .sawAnimal(let dog, let p):
            goal = nil
            if dog {
                anim.startle()
                queue = [Task(kind: .face(p.x)), Task(kind: .sound(.hiss)), Task.hold(.hiss, 1.5...2.2, .angry), Task(kind: .say(.dog))]
            } else {
                goTo(p, gait: .walk) {
                    [Task(kind: .face(p.x)), Task.hold(.sit, 2...3, .alert), Task(kind: .say(.otherCat)), Task(kind: .sound(.meow))]
                }
            }

        case .sawPrey(let p):
            goTo(p, gait: .trot) {
                [Task(kind: .face(p.x)), Task(kind: .say(.bird)),
                 Task.hold(.crouch, 2...3.5, .stalking, [.chatter, .wiggle]), Task(kind: .sound(.chatter)),
                 Task(kind: .hop(560)), Task.hold(.sit, 1.5...2.5, .annoyed, .lick)]
            }

        case .sawWord(let w, let p):
            goTo(p, gait: .trot) { [Task(kind: .face(p.x)), Task.hold(.sit, 1...2, .alert), Task(kind: .say(.word(w))), Task.hold(.sit, 3...5, .happy)] }

        case .macWoke:
            queue = [Task.hold(.stretch, 1.4...2, .happy), Task.hold(.sit, 1...1.3, .relaxed, .yawn), Task(kind: .say(.wake))]

        case .hotMac(let hot):
            if hot && !macIsHot { queue = [Task(kind: .say(.hotMac)), Task.hold(.flat, 20...40, .relaxed)] }
            macIsHot = hot

        case .lowBattery:
            out?.say(.lowBattery)

        case .charging:
            if Bool.random() { out?.say(.charging) }

        case .weather(let w):
            if w != weather {
                switch w {
                case .rain: out?.say(.rain)
                case .sun: out?.say(.sun)
                case .cold: out?.say(.cold)
                case .heat: out?.say(.heat)
                case .mild: break
                }
            }
            weather = w

        case .meeting(let title, let minutes):
            queue = wakeUpFirst() + [Task(kind: .sound(.meowLong)), Task(kind: .say(.meeting(title: title, minutes: minutes))),
                                     Task.hold(.sit, 3...5, .alert)]

        case .appActivated(let name):
            if Int.random(in: 0..<8) == 0 { out?.say(.app(name: name)) }

        case .feed(let bowl):
            out?.play(.demand)
            // Stop beside the bowl, on the side it comes from, so the head ends up over it.
            let side: CGFloat = body.pos.x < bowl.x ? -1 : 1
            let spot = CGPoint(x: bowl.x + side * 27 * s, y: bowl.y)
            goTo(spot, gait: .run, radius: 10 * s) {
                [Task(kind: .face(bowl.x)), Task(kind: .eat, duration: .random(in: 6...9)),
                 Task.hold(.sit, 1...2, .happy, .lick), Task.hold(.groom, 3...5, .relaxed, .lick)]
            }

        case .find:
            out?.emit(.ring)
            out?.sayText("Sono qui.")

        case .clicked:
            if isAsleep {
                anim.startle()
            } else {
                anim.lookAt = out?.cursor
                out?.emit(.question)
            }

        case .doubleClicked:
            out?.play(needs.hunger > 0.6 ? .demand : .meow)
            queue = [Task.hold(.sit, 1...1.4, .happy, .meow), Task(kind: .say(needs.hunger > 0.6 ? .hungry : .idle)),
                     Task.hold(.sit, 2...4, .happy)]

        case .thrown(let speed):
            needs.offended(min(0.6, Double(speed) / 4000))
            thrownPending = true
            goal = nil
            queue = []
        }
    }

    private func goTo(_ p: CGPoint, gait: Gait, radius: CGFloat? = nil, then: @escaping () -> [Task]) {
        goal = Goal(target: { p }, gait: gait, radius: radius ?? 70 * body.scale, onArrive: then, deadline: time + 45)
        if !wakeUpFirst().isEmpty { queue = wakeUpFirst() } else { queue = [] }
    }

    private func startle(hiss: Bool) {
        anim.startle()
        out?.emit(.bang)
        goal = nil
        guard body.isGrounded else { return }
        let wasAsleep = isAsleep
        queue = [Task(kind: .hop(600))]
        if hiss || wasAsleep {
            queue.append(Task(kind: .sound(.hiss)))
            queue.append(Task.hold(.hiss, 0.8...1.4, .angry))
        }
        walkAway()
    }
}

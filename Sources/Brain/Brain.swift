import AppKit

enum CatSound { case meow, meowLong, demand, trill, hiss, crunch, chatter, bark, chirp, squeak }
enum ParticleKind { case zzz, heart, bang, note, question, ring, sweat, anger, dust, speed, sparkle }
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
    /// The pointer is being waved around near the cat: someone wants to play.
    case playing
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
    func minimize(window: UInt32)
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
    case minimize(window: UInt32)
    case say(ThoughtTopic)
    case text(String)
    case sound(CatSound)
    case face(CGFloat)
    case particle(ParticleKind)
    case hop(CGFloat)
    case spin
    case watchFly
    case pounceFly
    case flyOutcome
    case watchTarget(() -> CGPoint?)
    case pounceAt(() -> CGPoint?)
    case call(() -> Void)
    /// Hold a posture with the eyes locked on something; `ramp` builds the stare up over the task.
    case focus(() -> CGPoint?, PoseKind, TailStyle, Flourish, ramp: Bool)
}

/// Little numbers the cat does on its own, between one visitor and the next.
private enum Quirk: CaseIterable { case tailChase, zoomies, stretch, faceWash, ghost, roll, sneeze }

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
    /// A decision from the Mind, carried out at the next free moment.
    private var intent: (CatIntent, String)?
    private var viewerGlanceUntil: CGFloat = 0
    private var hangUntil: CGFloat = 0
    private var hangPull = false
    private var lastLights: CGFloat = -900
    private var lastMinimize: CGFloat = -3600
    private var clickTimes: [CGFloat] = []
    private var playUntil: CGFloat = 0
    private var lastFly: CGFloat = -600
    private var nextFlip: CGFloat = 0
    private var nextScratchSound: CGFloat = 0
    private var slipDecided = false
    private var slipAt: CGFloat = .infinity
    private var nextDream: CGFloat = 12
    /// The last spontaneous number and when it happened, so they come often and never twice in a row.
    private var lastQuirk: Quirk?
    private var lastQuirkTime: CGFloat = 0
    /// Tasks a running task wants to add after itself (queue cannot change while a task runs).
    private var followUps: [Task] = []
    /// A `.call` task's action, run once the task is off the queue: the action may rewrite the
    /// queue (a scene's next step), which it cannot do while `run` holds `queue[0]` inout.
    private var pendingCall: (() -> Void)?
    /// The fly the cat is hunting, if any.
    private(set) var fly: Fly?
    /// Something to play with other than the pointer (a laser dot, a ball of yarn).
    var toy: (() -> CGPoint?)?
    private var playTarget: CGPoint? { toy?() ?? out?.cursor }

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
        case .hanging(let id, _, _): return id == nil ? "Penzola dalla barra dei menu" : "Si regge con le unghie"
        default: break
        }
        if isPetted { return "Fa le fusa" }
        guard let t = queue.first else { return "Si guarda intorno" }
        switch t.kind {
        case .hold(let k, _, let f):
            if f.contains(.roll) { return "Si rotola sulla schiena" }
            if f.contains(.faceWash) { return "Si lava il muso" }
            if f.contains(.dizzy) { return "Gli gira la testa" }
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
            case .paw: return "Gioca con i bottoni della finestra"
            case .belly: return "Pancia all'aria"
            case .scratch: return "Si fa le unghie"
            case .crouch: return "Sta in agguato"
            default: return "Si guarda intorno"
            }
        case .walk(_, let g): return g == .run ? "Corre" : "Passeggia"
        case .jump: return "Salta"
        case .stalk: return "Caccia il puntatore"
        case .eat: return "Mangia"
        case .nudge: return "Combina un guaio"
        case .spin: return "Si rincorre la coda"
        case .watchFly, .pounceFly: return "Caccia una mosca"
        case .focus: return "Fissa qualcosa"
        default: return "Si guarda intorno"
        }
    }

    private var doing: Needs.Doing {
        if isPetted { return .petted }
        guard let t = queue.first else { return .resting }
        switch t.kind {
        case .hold(.sleep, _, _): return .sleeping
        case .hold: return .resting
        case .walk(_, .run), .walk(_, .sprint), .stalk, .spin, .pounceFly: return .playing
        case .eat: return .eating
        default: return .active
        }
    }

    // MARK: Frame

    func update(_ dt: CGFloat, world: World) {
        self.world = world
        time += dt
        if let f = fly {
            f.update(dt)
            if f.gone { fly = nil }
        }
        needs.tick(Double(dt), doing: doing)
        anim.flourish = []
        anim.eyesClosed = false
        anim.lookAtViewer = false
        anim.lookAt = nil
        anim.focus = 0

        switch body.loco {
        case .dragged:
            anim.kind = .dangle
            anim.tailStyle = .hanging
            anim.lookAt = out?.cursor
            return
        case .climbing:
            anim.kind = .stand
            anim.tailStyle = .alert
            // Sometimes the claws do not hold: a scramble, then down it goes.
            if !slipDecided {
                slipDecided = true
                let chance = 0.1 + (1 - needs.energy) * 0.12
                slipAt = Double.random(in: 0..<1) < chance ? time + .random(in: 0.4...1.3) : .infinity
            }
            if time >= slipAt {
                slipAt = .infinity
                body.slip()
                anim.startle()
                out?.emit(.bang)
                out?.emit(.sweat)
                if Int.random(in: 0..<3) == 0 { out?.sayText(["Unghie corte oggi.", "Non è successo niente.", "Era scivoloso. Giuro."].randomElement()!) }
                return
            }
            if let e = body.climb(dt, time: time, world: world) { bodyEvent(e) }
            return
        case .airborne:
            anim.kind = body.vel.dy > 0 ? .airUp : .airDown
            anim.tailStyle = .falling
            return
        case .hanging(let id, _, _):
            anim.kind = .hang
            anim.tailStyle = .hanging
            anim.flourish = [.scramble]
            anim.lookAt = out?.cursor
            if time >= hangUntil {
                if hangPull && id != nil && body.pullUp(world) {
                    anim.landed(speed: 300)
                } else {
                    body.letGo()
                    out?.emit(.sweat)
                    if Int.random(in: 0..<3) == 0 { queue.insert(Task(kind: .say(id == nil ? .onTop : .clap)), at: 0) }
                }
            }
            return
        case .grounded:
            slipDecided = false
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
                if !followUps.isEmpty {
                    queue.insert(contentsOf: followUps, at: 0)
                    followUps.removeAll()
                }
                if let call = pendingCall {
                    pendingCall = nil
                    call()
                }
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
                out?.emit(.sweat)
                if speed > 1100 || needs.grudge > 0.4 {
                    queue = [Task(kind: .particle(.anger)), Task.hold(.hiss, 0.8...1.2, .angry), Task(kind: .say(.thrown)),
                             Task.hold(.sit, 1.5...3, .annoyed, .lick)]
                    out?.play(.hiss)
                } else {
                    queue = [Task(kind: .say(.thrown)), Task.hold(.groom, 2...4, .annoyed, .lick)]
                }
            }
        case .startedFalling:
            goal = nil
            queue.removeAll()
        case .grabbedEdge:
            if case .hanging(let id, _, _) = body.loco, id == nil {
                hangUntil = time + .random(in: 2...5)
                hangPull = false
            } else {
                hangUntil = time + .random(in: 0.9...2.2)
                out?.emit(.sweat)
            }
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
                // Dreaming: the paws run for a moment, the ears jerk.
                nextDream -= dt
                if nextDream <= 0 && t.elapsed > 6 { anim.dream(); nextDream = .random(in: 9...28) }
            }
            if musicPlaying && (k == .sit || k == .loaf) { anim.flourish.insert(.sway) }
            if k == .scratch {
                nextScratchSound -= dt
                if nextScratchSound <= 0 { out?.play(.crunch); nextScratchSound = .random(in: 0.2...0.35) }
            }
            if t.elapsed >= t.duration {
                if k == .sleep, let id = body.windowUnderneath, let w = world.window(id) { out?.sleptOn(owner: w.owner) }
                return true
            }
            return false

        case .walk(let x, let g):
            anim.kind = .stand
            anim.tailStyle = g == .run || g == .sprint ? .falling : (goal != nil ? .happy : .relaxed)
            return body.walk(toward: x, gait: g, dt: dt, world: world) || t.elapsed > 30

        case .jump(let m):
            if !t.launched {
                anim.kind = .crouch
                anim.tailStyle = .stalking
                anim.flourish = [.wiggle]
                body.turn(toward: m.target.x)
                if t.elapsed > 0.32 {
                    if let hang = m.hang {
                        body.launch(to: m.target, hang: hang)
                    } else if m.grab == nil, let id = m.targetWindow, m.target.y > body.pos.y + 50 * body.scale,
                              Double.random(in: 0..<1) < missChance {
                        // Misjudged it: only the front paws make it to the edge.
                        hangPull = Double.random(in: 0..<1) < 0.6
                        body.launch(to: m.target, hang: (id, m.target.y))
                    } else {
                        body.launch(to: m.target, grab: m.grab)
                    }
                    t.launched = true
                }
                return false
            }
            return body.isGrounded

        case .stalk:
            guard let c = playTarget else { return true }
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
                out?.emit(.sparkle)
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

        case .minimize(let id):
            out?.minimize(window: id)
            return true
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

        case .spin:
            // Chasing its own tail: round and round on the spot.
            anim.kind = .crouch
            anim.tailStyle = .stalking
            anim.flourish = [.wiggle]
            nextFlip -= dt
            if nextFlip <= 0 {
                body.facing = -body.facing
                nextFlip = .random(in: 0.18...0.3)
                if Int.random(in: 0..<3) == 0 { out?.emit(.dust) }
            }
            return t.elapsed >= t.duration

        case .watchFly:
            guard let f = fly else { return true }
            anim.kind = t.elapsed > t.duration * 0.6 ? .crouch : .sit
            anim.tailStyle = .stalking
            anim.lookAt = f.pos
            anim.flourish = t.elapsed > t.duration * 0.6 ? [.wiggle, .chatter] : [.chatter]
            body.turn(toward: f.pos.x)
            return t.elapsed >= t.duration

        case .pounceFly:
            guard let f = fly else { return true }
            if !t.launched {
                let s = body.scale
                let dx = (f.pos.x - body.pos.x).clamped(-body.maxJumpAcross * 0.6, body.maxJumpAcross * 0.6)
                let dy = (f.pos.y - body.pos.y - 30 * s).clamped(10 * s, body.maxJumpUp * 0.7)
                body.launch(to: CGPoint(x: body.pos.x + dx, y: body.pos.y + dy), lift: 14 * s)
                t.launched = true
                return false
            }
            return body.isGrounded

        case .watchTarget(let target):
            guard let p = target() else { return true }
            let late = t.elapsed > t.duration * 0.5
            anim.kind = late ? .crouch : .sit
            anim.tailStyle = .stalking
            anim.lookAt = p
            anim.flourish = late ? [.wiggle, .chatter] : [.chatter]
            body.turn(toward: p.x)
            return t.elapsed >= t.duration

        case .pounceAt(let target):
            if !t.launched {
                guard let p = target() else { return true }
                let s = body.scale
                let dx = (p.x - body.pos.x).clamped(-body.maxJumpAcross * 0.7, body.maxJumpAcross * 0.7)
                let dy = (p.y - body.pos.y).clamped(4 * s, body.maxJumpUp * 0.7)
                body.launch(to: CGPoint(x: body.pos.x + dx, y: body.pos.y + dy), lift: 16 * s)
                t.launched = true
                return false
            }
            return body.isGrounded

        case .call(let action):
            pendingCall = action
            return true

        case .focus(let target, let k, let tail, let f, let ramp):
            anim.kind = k
            anim.tailStyle = tail
            anim.flourish = f
            if let p = target() {
                anim.lookAt = p
                if abs(p.x - body.pos.x) > 6 * body.scale { body.turn(toward: p.x) }
            }
            anim.focus = ramp ? min(1, t.elapsed / max(t.duration * 0.8, 0.1)) : 1
            return t.elapsed >= t.duration

        case .flyOutcome:
            guard let f = fly else { return true }
            let s = body.scale
            let head = CGPoint(x: body.pos.x + body.facing * 25 * s, y: body.pos.y + 40 * s)
            if f.pos.distance(to: head) < 80 * s && Double.random(in: 0..<1) < 0.55 {
                fly = nil
                out?.emit(.sparkle)
                out?.play(.trill)
                out?.sayText(["Proteine.", "Presa. Ovviamente.", "Gnam.", "Un'altra, grazie."].randomElement()!)
                followUps = [Task.hold(.sit, 1.5...2.5, .happy, .lick), Task.hold(.groom, 2...3, .relaxed, .lick)]
            } else {
                f.flee(from: body.pos)
                out?.emit(.anger)
                out?.sayText(["Era lenta. Io di più.", "La prossima è mia.", "L'ho lasciata andare. Apposta."].randomElement()!)
                followUps = [Task.hold(.sit, 1.5...2.5, .annoyed)]
            }
            return true
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
                // The classic: a belly offered is a trap, about half the time.
                if case .hold(.belly, _, _)? = queue.first?.kind, Bool.random() {
                    pettingTime = -2.5
                    wasPetted = false
                    anim.startle()
                    queue = [Task(kind: .particle(.anger)), Task.hold(.hiss, 0.5...0.7, .annoyed), Task(kind: .text("Era una trappola.")),
                             Task.hold(.sit, 1.5...2.5, .happy, .lick)]
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
        if time < playUntil, goal == nil {
            planPlay(world)
            return
        }
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

        if let (i, app) = intent {
            intent = nil
            if follow(i, app: app, world) { return }
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
        if n.hunger > 0.65 {
            options.append((2.2 * n.hunger, { self.planAsk(.hungry) }))
        }
        if n.loneliness > 0.7 && !userAway {
            options.append((1.2 * n.loneliness, { self.planAsk(.idle) }))
        }
        // Spontaneous numbers: often, and much more likely once a while has passed without one.
        let due: Double = time - lastQuirkTime > 70 ? 4 : 1
        for q in Quirk.allCases where q != lastQuirk {
            let w = quirkWeight(q, hour: hour, live: live, world: world) * due
            if w > 0 { options.append((w, { self.perform(q, world) })) }
        }
        options.append((0.25 + n.loneliness * 0.4, { self.queue = [Task.hold(.belly, 4...9, .happy)] }))
        if let spot = scratchSpot(world) {
            options.append((0.3, {
                self.queue = [Task(kind: .walk(x: spot.x, gait: .walk)), Task(kind: .face(spot.wallX)),
                              Task.hold(.scratch, 2.5...4, .happy, .knead), Task.hold(.sit, 1...2, .happy)]
            }))
        }
        if time - lastFly > 300 {
            options.append((0.35 * n.boredom * live, { self.planFlyHunt() }))
        }
        if let m = Navigator.menuBarHang(for: body, in: world) {
            options.append((0.5 * n.curiosity * n.energy * live, {
                self.queue = [Task(kind: .walk(x: m.takeoffX, gait: .walk)), Task(kind: .jump(m))]
            }))
        }
        if onWindow, time - lastLights > 240, lightsSpot(world) != nil {
            options.append((0.7 * n.boredom * n.energy + 0.1, { self.planTrafficLights(world) }))
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

    /// How likely a jump up is to fall short: tired cats and wild cats misjudge more.
    private var missChance: Double {
        let hour = Calendar.current.component(.hour, from: Date())
        let wild = Circadian.isZoomiesHour(hour) ? 0.08 : 0
        return min(0.32, 0.09 + (1 - needs.energy) * 0.14 + wild)
    }

    private func isCursorHuntable(_ world: World) -> Bool {
        guard let c = playTarget, let ledge = body.currentLedge(world) else { return false }
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
            // Make the bed first: knead it, turn round on it, then settle.
            var t: [Task] = [Task.hold(.knead, 3...5, .happy, .knead),
                             Task(kind: .face(self.body.pos.x - self.body.facing * 50)),
                             Task.hold(.stand, 0.4...0.6, .relaxed),
                             Task(kind: .face(self.body.pos.x + self.body.facing * 50)),
                             Task.hold(.stand, 0.3...0.5, .relaxed),
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

    /// A window side reaching down to the cat's ledge: something to sharpen claws on.
    private func scratchSpot(_ world: World) -> (x: CGFloat, wallX: CGFloat)? {
        guard let l = body.currentLedge(world) else { return nil }
        let s = body.scale
        for w in world.walls where w.span.lo <= l.y + 30 * s && w.span.hi > l.y + 70 * s && w.windowID != body.windowUnderneath {
            let x = w.side == .left ? w.x - 14 * s : w.x + 14 * s
            if l.span.contains(x, margin: -8 * s) && abs(x - body.pos.x) < 500 * s { return (x, w.x) }
        }
        return nil
    }

    private func planFlyHunt() {
        let s = body.scale
        lastFly = time
        fly = Fly(home: CGPoint(x: body.pos.x + body.facing * 90 * s, y: body.pos.y + 75 * s), scale: s)
        queue = [Task(kind: .watchFly, duration: .random(in: 2.5...4.5)), Task(kind: .sound(.chatter)),
                 Task(kind: .pounceFly), Task(kind: .flyOutcome)]
    }

    /// Someone is waving the pointer: hunt it, chase it along the ledge, bat at it.
    private func planPlay(_ world: World) {
        guard let c = playTarget else { return }
        let s = body.scale
        let d = c.distance(to: body.pos)
        if d < 60 * s {
            queue = [Task(kind: .face(c.x)), Task.hold(.wave, 0.5...0.9, .stalking, .wavePaw)]
        } else if isCursorHuntable(world) {
            queue = [Task(kind: .stalk, duration: .random(in: 0.35...0.8))]
        } else {
            goal = Goal(target: { [weak self] in self?.playTarget }, gait: .run, radius: 160 * s,
                        onArrive: { [Task(kind: .stalk, duration: .random(in: 0.3...0.6))] }, deadline: time + 6)
        }
    }

    /// Where to sit to bat at the window buttons, top left of the window it stands on.
    private func lightsSpot(_ world: World) -> CGFloat? {
        guard let id = body.windowUnderneath, let w = world.window(id), let l = body.currentLedge(world) else { return nil }
        let x = w.frame.minX + 40 + 17 * body.scale
        return l.span.contains(x) ? x : nil
    }

    private func planTrafficLights(_ world: World) {
        guard let x = lightsSpot(world), let id = body.windowUnderneath, let w = world.window(id) else { return }
        lastLights = time
        queue = [Task(kind: .walk(x: x, gait: .walk)), Task(kind: .face(w.frame.minX)),
                 Task.hold(.paw, 0.8...1.2, .stalking), Task(kind: .sound(.chatter)),
                 Task.hold(.paw, 2...3.5, .stalking, [.wavePaw, .wiggle])]
        // With mischief on, once in a long while the paw lands on the yellow button.
        if mischiefAllowed, out?.canNudge == true, time - lastMinimize > 2700, Int.random(in: 0..<4) == 0 {
            lastMinimize = time
            queue.append(Task(kind: .minimize(window: id)))
            queue.append(Task(kind: .say(.mischief)))
        } else {
            queue.append(Task.hold(.sit, 1.5...3, .annoyed, .lick))
        }
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

    // MARK: Quirks

    private func quirkWeight(_ q: Quirk, hour: Int, live: Double, world: World) -> Double {
        let n = needs
        let lively = max(0.35, live)
        switch q {
        case .tailChase: return n.energy > 0.25 ? 0.3 * (0.5 + n.boredom) * lively : 0
        case .zoomies:
            guard n.energy > 0.4, let l = body.currentLedge(world), l.span.length > 300 * body.scale else { return 0 }
            return (Circadian.isZoomiesHour(hour) ? 0.9 : 0.22) * lively
        case .stretch: return 0.3
        case .faceWash: return 0.35
        case .ghost: return 0.28 * (0.5 + n.curiosity)
        case .roll: return 0.2 + n.loneliness * 0.2
        case .sneeze: return 0.09
        }
    }

    private func perform(_ q: Quirk, _ world: World) {
        lastQuirk = q
        lastQuirkTime = time
        switch q {
        case .tailChase: planTailChase()
        case .zoomies: planZoomies(world)
        case .stretch: planStretch()
        case .faceWash: planFaceWash()
        case .ghost: planGhost(world)
        case .roll: planRoll()
        case .sneeze: planSneeze()
        }
    }

    /// Something behind it moved. It was the tail. Round and round, then the world spins.
    private func planTailChase() {
        let behind: () -> CGPoint? = { [weak self] in
            guard let self else { return nil }
            let s = self.body.scale
            return CGPoint(x: self.body.pos.x - self.body.facing * 60 * s, y: self.body.pos.y + 8 * s)
        }
        queue = [Task(kind: .focus(behind, .crouch, .stalking, [.wiggle], ramp: true), duration: .random(in: 1.0...1.6)),
                 Task(kind: .spin, duration: .random(in: 2.2...3.6)),
                 Task(kind: .particle(.question)),
                 Task.hold(.sit, 1.8...2.4, .relaxed, .dizzy)]
        if Bool.random() {
            queue.append(Task(kind: .text(["Era la mia coda. Lo sapevo.", "Mi gira tutto.", "Ce l'avevo quasi."].randomElement()!)))
        }
        queue.append(Task.hold(.groom, 2...3, .relaxed, .lick))
    }

    /// The mad dash: a frozen second, eyes like saucers, then back and forth at full tilt.
    private func planZoomies(_ world: World) {
        guard let l = body.currentLedge(world) else { return }
        let s = body.scale
        var dir: CGFloat = body.pos.x < (l.span.lo + l.span.hi) / 2 ? 1 : -1
        let ahead = CGPoint(x: body.pos.x + dir * 200 * s, y: body.pos.y + 30 * s)
        queue = [Task(kind: .face(ahead.x)),
                 Task(kind: .focus({ ahead }, .stand, .alert, [], ramp: true), duration: .random(in: 0.6...1.0)),
                 Task(kind: .call { [weak self] in self?.anim.startle(); self?.out?.emit(.bang) }),
                 Task.hold(.crouch, 0.25...0.4, .stalking, .wiggle)]
        if Int.random(in: 0..<3) == 0 { queue.insert(Task(kind: .say(.zoomies)), at: 0) }
        var x = body.pos.x
        for i in 0..<Int.random(in: 3...6) {
            x = l.span.clamp(x + dir * .random(in: 260...620) * s, inset: 20 * s)
            queue.append(Task(kind: .walk(x: x, gait: i % 2 == 0 ? .sprint : .run)))
            if Int.random(in: 0..<3) == 0 { queue.append(Task(kind: .hop(.random(in: 420...600)))) }
            dir = -dir
        }
        queue += [Task(kind: .particle(.dust)), Task.hold(.stand, 0.4...0.6, .alert), Task.hold(.sit, 1...2, .alert)]
        if Int.random(in: 0..<3) == 0 { queue.append(Task(kind: .text(["Non è successo niente.", "Dovevo farlo.", "Ok. Ora sto bene."].randomElement()!))) }
        queue.append(Task.hold(.groom, 2...4, .relaxed, .lick))
    }

    /// Front paws far forward, back up high, the big yawn at the bottom of it.
    private func planStretch() {
        queue = [Task.hold(.stand, 0.4...0.7, .relaxed),
                 Task.hold(.stretch, 0.9...1.1, .happy),
                 Task.hold(.stretch, 1.2...1.6, .happy, .yawn),
                 Task.hold(.stretch, 0.4...0.6, .happy),
                 Task.hold(.stand, 0.5...0.8, .relaxed),
                 Task.hold(.sit, 1...2, .wrapped, .lick)]
    }

    /// Lick the paw, wipe the face, again, again.
    private func planFaceWash() {
        queue = [Task.hold(.sit, 0.6...1, .relaxed),
                 Task.hold(.groom, 4...7, .relaxed, .faceWash),
                 Task.hold(.sit, 1...2, .wrapped)]
    }

    /// Stares at an empty spot in the air, very hard. Then either bolts or pounces on nothing.
    private func planGhost(_ world: World) {
        guard let l = body.currentLedge(world) else { return }
        let s = body.scale
        let side: CGFloat = Bool.random() ? body.facing : -body.facing
        let spot = CGPoint(x: body.pos.x + side * .random(in: 120...320) * s, y: body.pos.y + .random(in: 70...240) * s)
        queue = [Task(kind: .face(spot.x)),
                 Task(kind: .focus({ spot }, .sit, .alert, [], ramp: true), duration: .random(in: 2.8...4.6))]
        if Bool.random() {
            // Something only it can see: it bolts, then stares back from a safe distance.
            let away = l.span.clamp(body.pos.x - side * .random(in: 260...480) * s, inset: 20 * s)
            queue += [Task(kind: .call { [weak self] in self?.anim.startle(); self?.out?.emit(.bang) }),
                      Task(kind: .hop(560)),
                      Task(kind: .walk(x: away, gait: .sprint)),
                      Task(kind: .focus({ spot }, .stand, .alert, [], ramp: false), duration: .random(in: 1.5...2.5))]
            if Bool.random() { queue.append(Task(kind: .text(["C'era qualcosa.", "L'hai visto anche tu?", "Lì. Proprio lì."].randomElement()!))) }
            queue.append(Task.hold(.sit, 2...3, .annoyed))
        } else {
            // ... or it decides it was prey: butt wiggle, then the pounce, on nothing.
            let ground = CGPoint(x: l.span.clamp(body.pos.x + side * min(abs(spot.x - body.pos.x), 180 * s), inset: 20 * s), y: l.y)
            queue += [Task(kind: .focus({ ground }, .crouch, .stalking, [.wiggle], ramp: false), duration: .random(in: 1.2...2.0)),
                      Task(kind: .pounceAt({ ground })),
                      Task(kind: .particle(.question)),
                      Task.hold(.sit, 1...1.5, .relaxed)]
            if Bool.random() { queue.append(Task(kind: .text(["Niente. Di nuovo.", "Giuro che c'era.", "Era un fantasma. Piccolo."].randomElement()!))) }
            queue.append(Task.hold(.groom, 2...3, .relaxed, .lick))
        }
    }

    /// On its back, rubbing side to side, over onto the other side, and again.
    private func planRoll() {
        let s = body.scale
        queue = [Task.hold(.sit, 0.5...0.8, .happy),
                 Task.hold(.belly, 2...3, .happy, .roll),
                 Task(kind: .face(body.pos.x - body.facing * 50 * s)),
                 Task(kind: .particle(.dust)),
                 Task.hold(.belly, 2...3, .happy, .roll),
                 Task.hold(.belly, 2...5, .happy),
                 Task.hold(.stand, 0.5...0.8, .relaxed)]
    }

    /// Nose up, eyes squeezed, and: etciù. Sometimes twice.
    private func planSneeze() {
        let sneeze: [Task] = [Task.hold(.sit, 0.7...1.0, .alert, .preSneeze),
                              Task(kind: .call { [weak self] in self?.anim.sneeze(); self?.out?.emit(.dust) }),
                              Task.hold(.sit, 0.35...0.45, .alert)]
        queue = [Task.hold(.sit, 0.4...0.6, .alert)] + sneeze
        if Int.random(in: 0..<3) == 0 { queue += sneeze }
        if Bool.random() { queue.append(Task(kind: .text(["Etciù.", "Polvere. Ovunque.", "Non guardarmi."].randomElement()!))) }
        queue.append(Task.hold(.sit, 1...1.5, .annoyed, .lick))
    }

    // MARK: Scenes (visitors directed by SceneDirector)

    private var sceneBusy: Bool { if case .dragged = body.loco { return true }; return false }

    /// Approach slowly, watch, wiggle, pounce.
    func sceneHunt(_ target: @escaping () -> CGPoint?, then: (() -> Void)? = nil) {
        guard !sceneBusy else { return }
        let s = body.scale
        queue = wakeUpFirst()
        goal = Goal(target: target, gait: .walk, radius: 120 * s, onArrive: {
            var t = [Task(kind: .watchTarget(target), duration: .random(in: 1.4...2.4)), Task(kind: .sound(.chatter)),
                     Task(kind: .pounceAt(target))]
            if let then { t.append(Task(kind: .call(then))) }
            return t
        }, deadline: time + 25)
    }

    /// Run after something and pounce on it.
    func sceneChase(_ target: @escaping () -> CGPoint?, gait: Gait = .sprint, then: (() -> Void)? = nil) {
        guard !sceneBusy else { return }
        queue = wakeUpFirst()
        goal = Goal(target: target, gait: gait, radius: 50 * body.scale, onArrive: {
            var t = [Task(kind: .pounceAt(target))]
            if let then { t.append(Task(kind: .call(then))) }
            return t
        }, deadline: time + 15)
    }

    /// Bolt away from danger at full speed, and up to the highest place in reach.
    func sceneFlee(from x: CGFloat) {
        guard !sceneBusy else { return }
        goal = nil
        anim.startle()
        out?.emit(.bang)
        out?.emit(.sweat)
        guard body.isGrounded, let l = body.currentLedge(world) else { return }
        queue = [Task(kind: .sound(.hiss))]
        let jumps = Navigator.moves(for: body, in: world).filter { $0.arrival.y > body.pos.y + 40 * body.scale }
        if let up = jumps.filter({ $0.grab == nil }).max(by: { $0.arrival.y < $1.arrival.y }) ?? jumps.max(by: { $0.arrival.y < $1.arrival.y }) {
            queue.append(Task(kind: .walk(x: up.takeoffX, gait: .sprint)))
            queue.append(Task(kind: .jump(up)))
        } else {
            queue.append(Task(kind: .walk(x: body.pos.x >= x ? l.span.hi : l.span.lo, gait: .sprint)))
        }
        queue += [Task(kind: .face(x)), Task(kind: .particle(.anger)), Task.hold(.hiss, 1.5...2.5, .angry),
                  Task(kind: .text(["Non è finita qui.", "Cane. Odio.", "Io non scappo. Mi riposiziono."].randomElement()!)),
                  Task.hold(.sit, 3...5, .annoyed)]
    }

    /// Get into something (a box) and stay there.
    func sceneSitIn(at spot: CGPoint, for duration: ClosedRange<CGFloat>) {
        guard !sceneBusy else { return }
        queue = wakeUpFirst()
        goal = Goal(target: { spot }, gait: .trot, radius: 10 * body.scale, onArrive: {
            [Task(kind: .hop(260)), Task(kind: .text(["Se ci sto, ci sto.", "Scatola. Mia.", "Casa nuova."].randomElement()!)),
             Task.hold(.loaf, duration, .wrapped)]
        }, deadline: time + 25)
    }

    /// Jump onto a moving platform (the robot vacuum).
    func sceneBoard(top: CGPoint, platform id: UInt32) {
        guard !sceneBusy, body.isGrounded else { return }
        goal = nil
        let m = Move(takeoffX: body.pos.x, target: top, grab: nil, arrival: top, targetWindow: id)
        queue = [Task(kind: .face(top.x)), Task(kind: .jump(m)), Task(kind: .text(["Taxi.", "Si parte.", "Avanti, autista."].randomElement()!)),
                 Task.hold(.loaf, 25...40, .happy)]
    }

    /// Face a rival and hiss it away.
    func sceneStandoff(facing x: CGFloat) {
        guard !sceneBusy else { return }
        goal = nil
        anim.startle()
        queue = [Task(kind: .face(x)), Task(kind: .particle(.anger)), Task(kind: .sound(.hiss)), Task.hold(.hiss, 2.5...3.5, .angry),
                 Task(kind: .text(["Questo è il mio desktop.", "Fuori dalla mia finestra.", "Qui comando io."].randomElement()!)),
                 Task.hold(.sit, 2...3, .annoyed)]
    }

    /// Watch something closely for a while.
    func sceneWatch(_ target: @escaping () -> CGPoint?, for seconds: CGFloat) {
        guard !sceneBusy else { return }
        goal = nil
        queue = wakeUpFirst() + [Task(kind: .watchTarget(target), duration: seconds)]
    }

    /// Something on the nose.
    func sceneSneeze() {
        queue = [Task.hold(.sit, 0.4...0.5, .alert, .yawn), Task(kind: .sound(.meow)), Task(kind: .hop(200)),
                 Task(kind: .text("Etciù.")), Task.hold(.sit, 1.5...2.5, .annoyed, .lick)]
    }

    /// Play with a toy that is not the pointer, for a while.
    func scenePlay(with target: @escaping () -> CGPoint?, for seconds: CGFloat) {
        guard !sceneBusy else { return }
        toy = target
        goal = nil
        queue = wakeUpFirst()
        playUntil = time + seconds
    }

    /// Keep still and follow something with the eyes, in the given posture.
    func sceneTrack(_ target: @escaping () -> CGPoint?, pose: PoseKind = .sit, tail: TailStyle = .alert,
                    flourish: Flourish = [], for seconds: CGFloat) {
        guard !sceneBusy else { return }
        goal = nil
        queue = wakeUpFirst() + [Task(kind: .focus(target, pose, tail, flourish, ramp: false), duration: seconds)]
    }

    /// Sit up and bat at something just above the head with a front paw.
    func sceneSwat(_ target: @escaping () -> CGPoint?, then: (() -> Void)? = nil) {
        guard !sceneBusy, body.isGrounded else { return }
        goal = nil
        queue = [Task(kind: .focus(target, .wave, .stalking, [.wavePaw], ramp: false), duration: 1.3)]
        if let then { queue.append(Task(kind: .call(then))) }
        queue.append(Task(kind: .focus(target, .lookUp, .alert, [], ramp: false), duration: 30))
    }

    /// Crouch, wiggle, and leap at something from where it stands.
    func scenePounce(_ target: @escaping () -> CGPoint?, then: (() -> Void)? = nil) {
        guard !sceneBusy, body.isGrounded else { return }
        goal = nil
        queue = [Task(kind: .focus(target, .crouch, .stalking, [.wiggle], ramp: false), duration: .random(in: 0.7...1.1)),
                 Task(kind: .sound(.chatter)), Task(kind: .pounceAt(target))]
        if let then { queue.append(Task(kind: .call(then))) }
    }

    /// Sit holding something down under a front paw, pleased with itself.
    func sceneProud(_ line: String, for seconds: CGFloat) {
        guard !sceneBusy else { return }
        goal = nil
        queue = [Task(kind: .sound(.trill)), Task(kind: .text(line)), Task.hold(.sit, seconds...seconds, .happy)]
    }

    /// The Mind decided what to do. Idle poses give way at once, anything else finishes first.
    func intend(_ i: CatIntent, app: String) {
        guard !isAsleep else { return }
        intent = (i, app)
        if goal == nil, case .hold(let k, _, _)? = queue.first?.kind, [.sit, .loaf, .stand, .lookUp].contains(k) {
            queue.removeAll()
        }
    }

    /// The top of a window of the given app, if the cat can see one.
    private func spot(of app: String, _ world: World) -> CGPoint? {
        guard !app.isEmpty else { return nil }
        let ledges = world.ledges.filter { l in
            guard let id = l.windowID, let w = world.window(id) else { return false }
            return w.owner == app
        }
        guard let l = ledges.randomElement() else { return nil }
        return CGPoint(x: l.span.clamp(l.span.lo + l.span.length * .random(in: 0.25...0.75)), y: l.y)
    }

    /// Turns a decision into tasks. False when it cannot be done right now.
    private func follow(_ i: CatIntent, app: String, _ world: World) -> Bool {
        let s = body.scale
        switch i {
        case .sleep:
            planSleep(world)
        case .napOnApp:
            guard let p = spot(of: app, world) else { planSleep(world); return true }
            goal = Goal(target: { p }, gait: .walk, radius: 40 * s, onArrive: {
                [Task.hold(.knead, 2...4, .happy, .knead), Task.hold(.loaf, 2...4, .wrapped),
                 Task.hold(.sleep, self.userAway ? 300...900 : 90...420, .wrapped),
                 Task.hold(.stretch, 1.4...2, .happy), Task.hold(.sit, 1...1.4, .relaxed, .yawn)]
            }, deadline: time + 60)
        case .explore:
            if let p = spot(of: app, world) {
                goal = Goal(target: { p }, gait: .trot, radius: 40 * s, onArrive: {
                    [Task.hold(.stand, 1...2, .alert), Task.hold(.sit, 3...8, .relaxed)]
                }, deadline: time + 50)
            } else {
                planExplore(world)
            }
        case .huntPointer:
            guard isCursorHuntable(world) else { return false }
            queue = [Task(kind: .stalk, duration: .random(in: 1.2...2.6))]
        case .mischief:
            guard mischiefAllowed, body.windowUnderneath != nil, out?.canNudge == true, time - lastMischief > 300 else { return false }
            planMischief(world)
        case .askFood:
            planAsk(.hungry)
        case .askCuddles:
            guard !userAway else { return false }
            planAsk(.idle)
        case .groom:
            queue = [Task.hold(.groom, 3...7, .relaxed, .lick)]
        case .loaf:
            queue = [Task.hold(.loaf, 8...30, .wrapped)]
        case .zoomies:
            planZoomies(world)
        case .chaseTail:
            queue = [Task(kind: .spin, duration: .random(in: 2.2...3.6)), Task(kind: .particle(.question)),
                     Task.hold(.sit, 1...1.6, .relaxed)]
        case .scratch:
            guard let sp = scratchSpot(world) else { return false }
            queue = [Task(kind: .walk(x: sp.x, gait: .walk)), Task(kind: .face(sp.wallX)),
                     Task.hold(.scratch, 2.5...4, .happy, .knead), Task.hold(.sit, 1...2, .happy)]
        case .hangFromMenuBar:
            guard let m = Navigator.menuBarHang(for: body, in: world) else { return false }
            queue = [Task(kind: .walk(x: m.takeoffX, gait: .walk)), Task(kind: .jump(m))]
        case .watchHuman:
            queue = [Task(kind: .face(out?.cursor.x ?? body.pos.x)), Task.hold(.sit, 3...7, .alert)]
        case .stretch:
            queue = [Task.hold(.stretch, 1.4...2, .happy), Task.hold(.sit, 1...1.4, .relaxed, .yawn)]
        }
        return true
    }

    func sceneEnded() {
        toy = nil
        playUntil = 0
        if goal != nil { goal = nil; queue = [] }
    }

    func sceneSay(_ text: String) { out?.sayText(text) }

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
            queue = [Task(kind: .particle(.sparkle)), Task(kind: .sound(.trill)), Task.hold(.sit, 2...3, .happy, .purr)]
            if Bool.random() { queue.append(Task(kind: .say(.praised))) }

        case .scolded:
            needs.offended(0.1)
            queue = [Task(kind: .particle(.sweat)), Task.hold(.sit, 1...1.5, .annoyed), Task(kind: .say(.scolded))]
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
            queue = [Task(kind: .particle(.anger)), Task(kind: .sound(.hiss)), Task.hold(.hiss, 1.8...2.6, .angry)]
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
            if hot && !macIsHot { queue = [Task(kind: .particle(.sweat)), Task(kind: .say(.hotMac)), Task.hold(.flat, 20...40, .relaxed)] }
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
            clickTimes.append(time)
            clickTimes.removeAll { time - $0 > 2.5 }
            let c = out?.cursor ?? body.pos
            if clickTimes.count >= 4 {
                // Enough.
                clickTimes.removeAll()
                needs.offended(0.12)
                anim.startle()
                queue = [Task(kind: .particle(.anger)), Task(kind: .sound(.hiss)), Task.hold(.hiss, 0.6...0.9, .angry),
                         Task(kind: .text(["Basta cliccare.", "Non sono un bottone.", "Ancora un clic e ti graffio."].randomElement()!))]
                walkAway()
                return
            }
            if isAsleep {
                anim.startle()
                out?.emit(.question)
                if clickTimes.count >= 2 { queue = wakeUpFirst() + [Task.hold(.sit, 1...2, .annoyed)] }
                return
            }
            guard body.isGrounded else { return }
            let reactions: [[Task]] = [
                [Task(kind: .particle(.question)), Task(kind: .face(c.x)), Task.hold(.lookUp, 1...1.6, .alert)],
                [Task(kind: .face(c.x)), Task(kind: .sound(.trill)), Task.hold(.stand, 0.6...0.9, .happy, .purr),
                 Task(kind: .particle(.heart))],
                [Task(kind: .sound(.trill)), Task.hold(.belly, 2.5...4.5, .happy)],
                [Task(kind: .face(c.x)), Task(kind: .hop(380)), Task.hold(.crouch, 0.5...0.8, .stalking, .wiggle)],
                [Task(kind: .face(c.x)), Task.hold(.wave, 0.8...1.2, .stalking, .wavePaw)],
                [Task(kind: .sound(.meow)), Task.hold(.sit, 1...1.4, .happy, .meow)],
            ]
            queue = reactions.randomElement()!
            playUntil = max(playUntil, time + 3)

        case .playing:
            if isAsleep && Int.random(in: 0..<3) != 0 { anim.startle(); return }
            if playUntil < time { out?.emit(.bang) }
            playUntil = time + 8
            needs.boredom = max(0, needs.boredom - 0.02)
            if goal == nil, case .hold? = queue.first?.kind { queue = wakeUpFirst() }

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
        out?.emit(.sweat)
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

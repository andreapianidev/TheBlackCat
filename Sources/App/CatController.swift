import AppKit
import Combine
import WidgetKit

/// Owns the cat: runs the frame loop, keeps the world up to date, wires the senses.
@MainActor
final class CatController: NSObject {
    let settings: CatSettings
    private var memory = CatMemory.load()

    private let body: CatBody
    private let anim = Animator()
    private let brain: Brain
    private var world = World()
    private var windows: [WindowInfo] = []
    private var screens: [ScreenInfo] = []
    private var trackTimer: Timer?

    private let panel: FloatingPanel
    private let view = CatView()
    private let particles = ParticleSystem()
    private let bubble = BubblePanel()
    private var bowl: BowlPanel?
    private let voice = CatVoice()
    private let thoughts = ThoughtEngine()
    private let mind = Mind()
    private lazy var menuBar = MenuBar(actions: self)
    private let settingsWindow = SettingsWindow()

    private let sight = SightSense()
    private let hearing = HearingSense()
    private let screenEyes = ScreenSense()
    private let system = SystemSense()
    private let attention = Attention()
    private let weather = WeatherSense()
    private let calendar = CalendarSense()
    private let notifier = Notifier()

    private var link: CADisplayLink?
    private var watchdog: Timer?
    private var lastTickWall: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var scanTimer: Timer?
    private var slowTimer: Timer?
    private var mindTimer: Timer?
    private var scanInterval: TimeInterval = 0
    private var cancellables: Set<AnyCancellable> = []

    private var dragging = false
    private var lastMouse = CGPoint.zero
    private var lastMouseMove: CFTimeInterval = 0
    private var hoverTime: CGFloat = 0
    private var nextHaptic: CGFloat = 0
    private var dark = false
    private var lastWidgetReload = Date.distantPast
    private var lastSpontaneous = Date()

    private var panelSize: CGSize { CGSize(width: 210 * body.scale, height: 250 * body.scale) }
    private var anchorInPanel: CGPoint { CGPoint(x: panelSize.width / 2, y: panelSize.height * 0.42) }
    private var nextSpeedLine: CGFloat = 0
    private lazy var director = SceneDirector(stage: Stage(
        brain: brain, body: body,
        play: { [weak self] s in self?.play(s) },
        say: { [weak self] t in self?.sayText(t) }))
    private var cursorTrail: [(CGPoint, CFTimeInterval)] = []
    private var lastPlayPing: CFTimeInterval = 0
    private enum Pace { case asleep, idle, active, fast }
    private var pace = Pace.active

    init(settings: CatSettings) {
        self.settings = settings
        let scale = settings.size.scale
        body = CatBody(pos: .zero, footing: .floor(screen: 0), scale: scale)
        brain = Brain(body: body, anim: anim)
        panel = FloatingPanel(size: CGSize(width: 210 * scale, height: 250 * scale))
        super.init()
        brain.out = self
        brain.needs = memory.needs
        brain.favorites = memory.favorites
        brain.needs.elapsedWhileAway(Date().timeIntervalSince(memory.lastSeen))
        view.delegate = self
        view.particles = particles
        view.wantsLayer = true
        panel.contentView = view
    }

    // MARK: Start

    func start() {
        _ = menuBar
        updateDarkness()
        fullScan()
        let first = !settings.onboarded
        if let main = world.screens.first {
            let floor = main.visible
            body.place(at: CGPoint(x: floor.minX + 24 * body.scale, y: floor.minY), footing: .floor(screen: 0))
            brain.arrive(walkTo: floor.minX + min(320, floor.width * 0.3), firstTime: first, name: settings.name)
        }
        resizePanel()
        if !settings.paused { panel.orderFrontRegardless() }

        makeDisplayLink()
        setPace(.active)
        // If the frame loop ever stops (display asleep, screens rearranged), start it again.
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.settings.paused else { return }
                if CACurrentMediaTime() - self.lastTickWall > 1.5 { self.makeDisplayLink(); self.setPace(self.pace) }
            }
        }
        trackTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trackWindowUnderCat() }
        }
        trackTimer?.tolerance = 0.02
        slowTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.slowTick() }
        }
        wireSettings()
        wireSenses()
        listenForCommands()
        handleCommands()
        if first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self else { return }
                self.openSettings()
                self.settings.onboarded = true
            }
        }
    }

    func stop() {
        saveMemory()
        publishSnapshot()
    }

    private func setScanInterval(_ t: TimeInterval) {
        guard t != scanInterval else { return }
        scanInterval = t
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fullScan() }
        }
        scanTimer?.tolerance = t * 0.3
    }

    /// All windows, every few tenths of a second. It is the expensive call, so it runs slowly.
    private func fullScan() {
        windows = WindowScanner.windows()
        screens = WindowScanner.screens()
        rebuildWorld()
    }

    private func rebuildWorld() {
        world = WorldBuilder.build(windows: director.platforms + windows, screens: screens, clearance: 8, minPiece: 46 * body.scale)
    }

    /// Between full scans, only the window under the cat is followed, so it rides a dragged window smoothly.
    private func trackWindowUnderCat() {
        guard let id = body.windowUnderneath, id != SceneDirector.platformID,
              let i = windows.firstIndex(where: { $0.id == id }) else { return }
        if let f = WindowScanner.frame(of: id) {
            if f != windows[i].frame { windows[i].frame = f; rebuildWorld() }
        } else {
            windows.remove(at: i)
            rebuildWorld()
        }
    }

    /// 60 frames a second only while something moves; a resting cat breathes at 30, a sleeping one at 12.
    private func setPace(_ p: Pace) {
        pace = p
        let lowPower = brain.lowPower
        switch p {
        case .asleep: link?.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)
        case .idle: link?.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 24, preferred: lowPower ? 15 : 20)
        case .active: link?.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        case .fast: link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: lowPower ? 30 : 60, preferred: lowPower ? 30 : 60)
        }
        setScanInterval(p == .asleep ? 1.5 : (p == .idle ? 0.6 : 0.3))
    }

    // MARK: Frame

    /// The frame loop follows a screen, not the cat's window: a window that wanders
    /// off screen would otherwise stop its own display link and freeze there.
    private func makeDisplayLink() {
        link?.invalidate()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(body.pos) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let l = screen?.displayLink(target: self, selector: #selector(tick(_:))) ?? Optional(view.displayLink(target: self, selector: #selector(tick(_:)))) else { return }
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = CGFloat(min(max(now - lastTick, 0), 1.0 / 12))
        lastTick = now
        lastTickWall = CACurrentMediaTime()
        guard !settings.paused, dt > 0 else { return }

        // Never lose the cat: anything that carries it off screen puts it back on a floor.
        if !dragging, !world.bounds.isNull, !world.bounds.insetBy(dx: -40, dy: -40).contains(body.pos),
           let floor = world.nearestFloor(to: body.pos.x) {
            body.place(at: CGPoint(x: floor.span.clamp(body.pos.x, inset: 30 * body.scale), y: floor.y),
                       footing: .floor(screen: floor.screen))
            emit(.ring)
        }

        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse { lastMouse = mouse; lastMouseMove = now }
        detectPlay(mouse, now: now)

        if !dragging, let e = body.update(dt, world: world) {
            brain.bodyEvent(e)
            if case .landed(let speed) = e, speed > 450 { emit(.dust) }
        }

        // Petting: the pointer resting on the cat and moving now and then.
        let over = hit(mouse)
        let pressed = NSEvent.pressedMouseButtons != 0
        if over && !pressed && !dragging && now - lastMouseMove < 1.5 { hoverTime += dt } else { hoverTime = 0 }
        let petting = hoverTime > 0.5 && body.isGrounded
        brain.petting(petting, dt: dt)
        brain.update(dt, world: world)
        director.tick(dt, world: world, paused: settings.paused)
        if !director.platforms.isEmpty { rebuildWorld() }
        voice.purr(brain.isPetted)
        if brain.isPetted {
            nextHaptic -= dt
            if nextHaptic <= 0 {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                nextHaptic = 0.42
            }
        }

        let frame = anim.update(dt, body: body, dark: dark)
        particles.update(dt)

        let origin = CGPoint(x: (body.pos.x - anchorInPanel.x).rounded(), y: (body.pos.y - anchorInPanel.y).rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        view.anchor = CGPoint(x: body.pos.x - origin.x, y: body.pos.y - origin.y)
        view.frameToDraw = frame
        view.fly = brain.fly.map { ($0.pos, $0.wingsUp) }
        view.render()
        let ignore = !(over || dragging)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }

        if bubble.visible { bubble.place(above: headPoint(frame)) }

        // Speed lines behind a running cat, in the comic style.
        if settings.comic && body.isGrounded && body.groundSpeed > 150 * body.scale {
            nextSpeedLine -= dt
            if nextSpeedLine <= 0 {
                nextSpeedLine = 0.06
                let p = CGPoint(x: body.pos.x - body.facing * 30 * body.scale, y: body.pos.y + .random(in: 8...36) * body.scale)
                particles.emit(.speed, at: p, scale: body.scale, facing: body.facing)
            }
        }

        // 60 frames only for fast motion; walking reads fine at 30, resting at 20, sleep at 12.
        let fast = dragging || !body.isGrounded || body.groundSpeed > 150 * body.scale
        let moving = body.groundSpeed > 1 || !particles.isCalm || brain.isPetted || brain.fly != nil || director.isActive
        let next: Pace = fast ? .fast : (brain.isAsleep && !brain.isPetted ? .asleep : (moving ? .active : .idle))
        if next != pace { setPace(next) }
    }

    /// A pointer waved quickly back and forth near the cat is an invitation to play.
    private func detectPlay(_ mouse: CGPoint, now: CFTimeInterval) {
        cursorTrail.append((mouse, now))
        cursorTrail.removeAll { now - $0.1 > 1.2 }
        guard now - lastPlayPing > 1, cursorTrail.count > 8, !dragging,
              mouse.distance(to: body.pos) < 450 * body.scale else { return }
        var length: CGFloat = 0
        var turns = 0
        var lastSign: CGFloat = 0
        for i in 1..<cursorTrail.count {
            let dx = cursorTrail[i].0.x - cursorTrail[i - 1].0.x
            let dy = cursorTrail[i].0.y - cursorTrail[i - 1].0.y
            length += hypot(dx, dy)
            let main = abs(dx) > abs(dy) ? dx : dy
            if abs(main) > 3 {
                let sign: CGFloat = main > 0 ? 1 : -1
                if lastSign != 0 && sign != lastSign { turns += 1 }
                lastSign = sign
            }
        }
        let span = CGFloat(max(cursorTrail.last!.1 - cursorTrail.first!.1, 0.1))
        if length / span > 550 && turns >= 3 {
            lastPlayPing = now
            brain.react(.playing)
        }
    }

    private func headPoint(_ f: CatFrame) -> CGPoint {
        let h = f.look.pose.head
        let x = h.x * f.facing * f.scale, y = (h.y + 14) * f.scale
        let c = cos(f.rotation), s = sin(f.rotation)
        return CGPoint(x: body.pos.x + x * c - y * s, y: body.pos.y + x * s + y * c)
    }

    /// True when `p` (global) is on the cat's body.
    private func hit(_ p: CGPoint) -> Bool {
        guard let f = anim.lastFrame else { return false }
        let c = cos(f.rotation), s = sin(f.rotation)
        for (center, r) in CatRig.hitCircles(f.look.pose) {
            let x = center.x * f.facing * f.scale, y = center.y * f.scale
            let gx = body.pos.x + x * c - y * s, gy = body.pos.y + x * s + y * c
            if hypot(p.x - gx, p.y - gy) < r * f.scale { return true }
        }
        return false
    }

    private func resizePanel() {
        panel.setContentSize(panelSize)
        view.frame = CGRect(origin: .zero, size: panelSize)
    }

    // MARK: Slow housekeeping

    private func updateDarkness() {
        dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            || !(7..<20).contains(Calendar.current.component(.hour, from: Date()))
    }

    private func slowTick() {
        updateDarkness()
        saveMemory()
        publishSnapshot()
        if settings.notifications && brain.needs.hunger > 0.85 { notifier.hungry(name: settings.name) }
        // Now and then, a thought of its own.
        if settings.thoughts, !brain.isAsleep, Date().timeIntervalSince(lastSpontaneous) > .random(in: 240...600) {
            lastSpontaneous = Date()
            say(spontaneousTopic())
        }
    }

    private func spontaneousTopic() -> ThoughtTopic {
        let hour = Calendar.current.component(.hour, from: Date())
        if brain.needs.hunger > 0.6 { return .hungry }
        if brain.needs.energy < 0.25 { return .sleepy }
        if (0..<5).contains(hour) { return .night }
        if (5..<8).contains(hour) { return .morning }
        if let id = body.windowUnderneath, let w = world.window(id), Bool.random() { return .window(owner: w.owner) }
        if !system.frontApp.isEmpty, Bool.random() { return .app(name: system.frontApp) }
        return .idle
    }

    private func saveMemory() {
        memory.needs = brain.needs
        memory.favorites = brain.favorites
        memory.lastSeen = Date()
        memory.save()
    }

    private func publishSnapshot() {
        let n = brain.needs
        SharedStore.save(.init(name: settings.name, status: settings.paused ? "È in giardino" : brain.status,
                               sleeping: brain.isAsleep, fullness: 1 - n.hunger, energy: n.energy,
                               happiness: 1 - n.loneliness * 0.6 - n.grudge * 0.4, playfulness: n.boredom, updated: Date(),
                               coat: settings.coat, comic: settings.comic))
        if Date().timeIntervalSince(lastWidgetReload) > 300 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Settings and senses

    private func wireSettings() {
        settings.$size.dropFirst().sink { [weak self] s in
            guard let self else { return }
            self.body.scale = s.scale
            self.resizePanel()
            self.rebuildWorld()
        }.store(in: &cancellables)
        settings.$sound.sink { [weak self] on in self?.voice.enabled = on }.store(in: &cancellables)
        settings.$volume.sink { [weak self] v in self?.voice.volume = Float(v) }.store(in: &cancellables)
        settings.$name.sink { [weak self] n in self?.thoughts.name = n; self?.hearing.name = n; self?.mind.name = n }.store(in: &cancellables)
        settings.$coat.sink { [weak self] id in
            guard let self else { return }
            let coat = CatCoat.named(id)
            let changed = self.anim.coat != coat
            self.anim.coat = coat
            self.thoughts.adjective = coat.adjective
            self.mind.adjective = coat.adjective
            if changed { self.emit(.ring); self.emit(.sparkle) }
        }.store(in: &cancellables)
        settings.$comic.sink { [weak self] on in
            guard let self else { return }
            let changed = self.anim.comic != on
            self.anim.comic = on
            if changed { self.emit(.ring) }
        }.store(in: &cancellables)
        settings.$brain.sink { [weak self] b in
            // A cloud brain without its key: try the vault in ~/.secrets once, into the keychain.
            if let c = CloudBrain(rawValue: b), !c.ready {
                _ = (c == .agnes ? VaultKey.agnes : VaultKey.deepSeek).importFromVault()
            }
            self?.thoughts.cloud = CloudBrain(rawValue: b)
            self?.mind.cloud = CloudBrain(rawValue: b)
        }.store(in: &cancellables)
        settings.$agnesVision.sink { [weak self] on in self?.screenEyes.agnesVision = on }.store(in: &cancellables)
        settings.$scenes.sink { [weak self] on in self?.director.enabled = on }.store(in: &cancellables)
        settings.$aiThoughts.sink { [weak self] on in
            self?.thoughts.useModel = on
            self?.mind.enabled = on
        }.store(in: &cancellables)
        // Camera and microphone are never left on: switching them on only allows short glances.
        settings.$sight.sink { [weak self] on in on ? self?.sight.glance(for: 6) : self?.sight.stop() }.store(in: &cancellables)
        settings.$hearing.sink { [weak self] on in on ? self?.hearing.listen(for: 8) : self?.hearing.stop() }.store(in: &cancellables)
        settings.$screenEyes.sink { [weak self] on in on ? self?.screenEyes.start() : self?.screenEyes.stop() }.store(in: &cancellables)
        settings.$weather.sink { [weak self] on in on ? self?.weather.start() : self?.weather.stop() }.store(in: &cancellables)
        settings.$calendar.sink { [weak self] on in on ? self?.calendar.start() : self?.calendar.stop() }.store(in: &cancellables)
        settings.$notifications.sink { [weak self] on in if on { self?.notifier.requestPermission() } }.store(in: &cancellables)
        settings.$mischief.sink { [weak self] on in
            self?.brain.mischiefAllowed = on
            if on && !WindowNudger.isTrusted { WindowNudger.requestTrust() }
        }.store(in: &cancellables)
        settings.$paused.dropFirst().sink { [weak self] out in
            guard let self else { return }
            if out { self.panel.orderOut(nil); self.bubble.hide() } else { self.comeBackInside() }
        }.store(in: &cancellables)
    }

    private func wireSenses() {
        sight.onPresence = { [weak self] present in self?.brain.faceVisible = present }
        attention.onEvent = { [weak self] e in self?.brain.react(e) }
        attention.catAwake = { [weak self] in !(self?.brain.isAsleep ?? true) }
        attention.openEyes = { [weak self] s in
            guard let self, self.settings.sight, !self.settings.paused else { return }
            self.sight.glance(for: s)
        }
        attention.openEars = { [weak self] s in
            guard let self, self.settings.hearing, !self.settings.paused else { return }
            self.hearing.listen(for: s)
        }
        attention.start()
        mindTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.consultMind() }
        }
        mindTimer?.tolerance = 1
        sight.onWave = { [weak self] in self?.brain.react(.wave) }
        hearing.onEvent = { [weak self] e in self?.brain.react(e) }
        screenEyes.onEvent = { [weak self] e in self?.brain.react(e) }
        screenEyes.catPosition = { [weak self] in self?.body.pos ?? .zero }
        screenEyes.onThought = { [weak self] text in
            guard let self, self.settings.thoughts else { return }
            self.sayText(text)
        }
        screenEyes.shouldLook = { [weak self] in
            guard let self else { return false }
            return !self.brain.isAsleep && self.brain.needs.curiosity > 0.3 && !self.settings.paused
        }
        system.onEvent = { [weak self] e in self?.brain.react(e) }
        system.onLowPower = { [weak self] low in
            guard let self else { return }
            self.brain.lowPower = low
            self.setPace(self.pace)
        }
        system.onScreensChanged = { [weak self] in
            guard let self else { return }
            self.fullScan()
            self.makeDisplayLink()
            self.setPace(self.pace)
        }
        system.start()
        weather.onWeather = { [weak self] mood, _ in self?.brain.react(.weather(mood)) }
        calendar.onMeeting = { [weak self] title, minutes in self?.brain.react(.meeting(title, minutes)) }
    }

    // MARK: Commands from the widget and Shortcuts

    private func listenForCommands() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let me = Unmanaged<CatController>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { me.handleCommands() } }
        }, SharedStore.commandNotification as CFString, nil, .deliverImmediately)
    }

    private func handleCommands() {
        for c in SharedStore.drainCommands() {
            switch c {
            case .feed: feed()
            case .call: call()
            case .sleep: brain.react(.sleepCommand)
            case .wake: brain.wakeUp()
            case .find: find()
            case .surprise: startScene(nil)
            }
        }
    }

    private func comeBackInside() {
        fullScan()
        guard let main = world.screens.first else { return }
        let floor = main.visible
        let fromRight = Bool.random()
        let x = fromRight ? floor.maxX - 24 * body.scale : floor.minX + 24 * body.scale
        body.place(at: CGPoint(x: x, y: floor.minY), footing: .floor(screen: 0))
        brain.arrive(walkTo: fromRight ? floor.maxX - 300 : floor.minX + 300, firstTime: false, name: settings.name)
        panel.orderFrontRegardless()
    }
}

// MARK: - BrainOutput

extension CatController: BrainOutput {
    var cursor: CGPoint { NSEvent.mouseLocation }
    var canNudge: Bool { settings.mischief && WindowNudger.isTrusted }

    func say(_ topic: ThoughtTopic) {
        guard settings.thoughts, !settings.paused else { return }
        let force: Bool
        switch topic {
        case .meeting, .fed, .thrown, .userBack: force = true
        default: force = false
        }
        thoughts.think(topic, context: thoughtContext(), force: force) { [weak self] text in
            guard let self, let f = self.anim.lastFrame else { return }
            self.bubble.show(text, above: self.headPoint(f), comic: self.settings.comic)
        }
    }

    func sayText(_ text: String) {
        guard let f = anim.lastFrame, !settings.paused else { return }
        bubble.show(text, above: headPoint(f), comic: settings.comic)
    }

    func play(_ sound: CatSound) {
        voice.play(sound)
        if sound != .crunch { hearing.mute(for: 2) }
        if sound == .bark || sound == .chirp || sound == .squeak { return }
        if sound == .meow || sound == .meowLong || sound == .demand || sound == .trill { particles.emit(.note, at: notePoint, scale: body.scale) }
    }

    private var notePoint: CGPoint {
        guard let f = anim.lastFrame else { return body.pos }
        return headPoint(f)
    }

    func emit(_ particle: ParticleKind) {
        guard let f = anim.lastFrame else { return }
        // Sweat, anger marks and speed lines belong to the comic style only.
        if !settings.comic && [.sweat, .anger, .speed].contains(particle) { return }
        let p: CGPoint
        switch particle {
        case .ring: p = CGPoint(x: body.pos.x, y: body.pos.y + 25 * body.scale)
        case .dust: p = body.pos
        case .sparkle: p = CGPoint(x: body.pos.x, y: body.pos.y + 40 * body.scale)
        default: p = headPoint(f)
        }
        particles.emit(particle, at: p, scale: body.scale, facing: body.facing)
    }

    func minimize(window id: UInt32) {
        guard canNudge, let w = world.window(id) else { return }
        WindowNudger.minimize(w)
    }

    func nudge(window id: UInt32, dx: CGFloat) {
        guard canNudge, let w = world.window(id) else { return }
        WindowNudger.nudge(w, dx: dx)
    }

    func ate(_ fraction: CGFloat) {
        bowl?.fill = 1 - fraction
        if fraction >= 1, let b = bowl {
            bowl = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { b.remove() }
        }
    }

    func sleptOn(owner: String) {
        brain.favorites[owner, default: 0] += 1
    }

    /// Every minute or two the cat decides, with its own character, what to do next.
    private func consultMind() {
        guard !settings.paused, !brain.isAsleep, !director.isActive, !dragging else { return }
        let apps = Array(Set(world.windows.map(\.owner).filter { !$0.isEmpty && $0 != "Dock" })).sorted()
        mind.maybeDecide(situation: { self.mindSituation() }, apps: apps) { [weak self] d in
            guard let self, !self.settings.paused, !self.director.isActive else { return }
            self.brain.intend(d.intent, app: d.app)
            if self.settings.thoughts, !d.thought.isEmpty, Int.random(in: 0..<3) > 0,
               let line = ThoughtBank.clean(d.thought) {
                self.sayText(line)
            }
        }
    }

    private func mindSituation() -> String {
        let n = brain.needs
        func level(_ v: Double) -> String { v > 0.7 ? "alta" : v > 0.4 ? "media" : "bassa" }
        var parts = [thoughtContext(), "stai facendo: \(brain.status.lowercased())",
                     "fame \(level(n.hunger)), energia \(level(n.energy)), voglia di giocare \(level(n.boredom)), "
                     + "bisogno di coccole \(level(n.loneliness)), curiosità \(level(n.curiosity))"]
        if brain.userAway { parts.append("l'umano non c'è") } else if brain.faceVisible { parts.append("l'umano ti sta guardando") }
        if brain.musicPlaying { parts.append("c'è musica") }
        if !settings.mischief { parts.append("i dispetti sono vietati") }
        return parts.joined(separator: "; ")
    }

    private func thoughtContext() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        var parts = ["sono le \(f.string(from: Date()))"]
        if !system.frontApp.isEmpty { parts.append("l'app in primo piano è \(system.frontApp)") }
        if let id = body.windowUnderneath, let w = world.window(id) { parts.append("sei sopra una finestra di \(w.owner)") }
        let n = brain.needs
        if n.hunger > 0.6 { parts.append("hai fame") }
        if n.energy < 0.3 { parts.append("hai sonno") }
        if n.grudge > 0.4 { parts.append("sei offeso") }
        if !weather.summary.isEmpty { parts.append("fuori: \(weather.summary)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Mouse on the cat

extension CatController: CatViewDelegate {
    func catPressed() {}

    func catDragged(to p: CGPoint) {
        if !dragging {
            dragging = true
            body.beginDrag()
            brain.pickedUp()
            voice.purr(false)
            bubble.hide()
        }
        let s = body.scale
        body.drag(to: CGPoint(x: p.x - 5 * s * body.facing, y: p.y - 58 * s))
        _ = body.update(1.0 / 60, world: world)
    }

    func catReleased(dragged: Bool, clicks: Int) {
        if dragging {
            dragging = false
            let speed = body.release()
            if speed > 500 { brain.react(.thrown(speed: speed)) }
            return
        }
        brain.react(clicks >= 2 ? .doubleClicked : .clicked)
        attention.poked()
    }

    func catMenu(_ event: NSEvent, in view: NSView) {
        menuBar.menuNeedsUpdate(menuBar.menu)
        NSMenu.popUpContextMenu(menuBar.menu, with: event, for: view)
    }
}

// MARK: - Menu

extension CatController: MenuBarActions {
    var menuStatus: String { settings.paused ? "È in giardino" : brain.status }
    var catName: String { settings.name }
    var isOutside: Bool { settings.paused }
    var isAsleep: Bool { brain.isAsleep }
    var size: CatSize { settings.size }
    var soundOn: Bool { settings.sound }
    var coatID: String { settings.coat }
    var comicOn: Bool { settings.comic }
    func setCoat(_ id: String) { settings.coat = id }
    var scenesOn: Bool { settings.scenes }
    func toggleScenes() { settings.scenes.toggle() }
    func startScene(_ kind: SceneKind?) {
        if settings.paused { settings.paused = false }
        director.start(kind, world: world)
    }
    func toggleComic() { settings.comic.toggle() }

    func feed() {
        if settings.paused { settings.paused = false }
        let c = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(c) }) ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let x = min(max(c.x, v.minX + 60), v.maxX - 60)
        let spot = CGPoint(x: x, y: v.minY)
        if let b = bowl { b.fill = 1 } else { bowl = BowlPanel(at: spot, scale: body.scale) }
        memory.timesFed += 1
        brain.react(.feed(bowl: bowl?.spot ?? spot))
    }

    func call() {
        if settings.paused { settings.paused = false; return }
        brain.react(.called(strong: true))
    }

    func find() {
        if settings.paused { settings.paused = false; return }
        brain.react(.find)
    }

    func toggleSleep() {
        if brain.isAsleep { brain.wakeUp() } else { brain.react(.sleepCommand) }
    }

    func setSize(_ s: CatSize) { settings.size = s }
    func toggleSound() { settings.sound.toggle() }
    func toggleOutside() { settings.paused.toggle() }

    func openSettings() {
        let readout = CatReadout(
            status: { [weak self] in self?.menuStatus ?? "" },
            needs: { [weak self] in self?.brain.needs ?? Needs() },
            aiStatus: { [weak self] in self?.thoughts.modelStatus ?? "" },
            screenAllowed: { CGPreflightScreenCaptureAccess() },
            accessibilityAllowed: { WindowNudger.isTrusted },
            weather: { [weak self] in
                guard let w = self?.weather.summary, !w.isEmpty else { return "" }
                return "Ora: \(w)."
            },
            age: { [weak self] in
                let days = Int(Date().timeIntervalSince(self?.memory.born ?? Date()) / 86400)
                return days == 0 ? "oggi" : (days == 1 ? "un giorno" : "\(days) giorni")
            },
            timesFed: { [weak self] in self?.memory.timesFed ?? 0 })
        settingsWindow.show(settings: settings, readout: readout)
    }

    func openAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Un gatto nero che vive sul tuo desktop.\nandreapiani.dev@gmail.com",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }
}

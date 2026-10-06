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

    private let panel: FloatingPanel
    private let view = CatView()
    private let particles = ParticleSystem()
    private let bubble = BubblePanel()
    private var bowl: BowlPanel?
    private let voice = CatVoice()
    private let thoughts = ThoughtEngine()
    private lazy var menuBar = MenuBar(actions: self)
    private let settingsWindow = SettingsWindow()

    private let sight = SightSense()
    private let hearing = HearingSense()
    private let screenEyes = ScreenSense()
    private let system = SystemSense()
    private let weather = WeatherSense()
    private let calendar = CalendarSense()
    private let notifier = Notifier()

    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var scanTimer: Timer?
    private var slowTimer: Timer?
    private var scanInterval: TimeInterval = 0
    private var asleepRate = false
    private var cancellables: Set<AnyCancellable> = []

    private var dragging = false
    private var lastMouse = CGPoint.zero
    private var lastMouseMove: CFTimeInterval = 0
    private var hoverTime: CGFloat = 0
    private var nextHaptic: CGFloat = 0
    private var dark = false
    private var lastWidgetReload = Date.distantPast
    private var lastSpontaneous = Date()

    private var panelSize: CGSize { CGSize(width: 260 * body.scale, height: 260 * body.scale) }
    private var anchorInPanel: CGPoint { CGPoint(x: panelSize.width / 2, y: panelSize.height * 0.38) }

    init(settings: CatSettings) {
        self.settings = settings
        let scale = settings.size.scale
        body = CatBody(pos: .zero, footing: .floor(screen: 0), scale: scale)
        brain = Brain(body: body, anim: anim)
        panel = FloatingPanel(size: CGSize(width: 260 * scale, height: 260 * scale))
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
        world = WindowScanner.world(scale: body.scale)
        let first = !settings.onboarded
        if let main = world.screens.first {
            let floor = main.visible
            body.place(at: CGPoint(x: floor.minX + 24 * body.scale, y: floor.minY), footing: .floor(screen: 0))
            brain.arrive(walkTo: floor.minX + min(320, floor.width * 0.3), firstTime: first, name: settings.name)
        }
        resizePanel()
        if !settings.paused { panel.orderFrontRegardless() }

        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        setFrameRate(asleep: false)
        setScanInterval(0.12)
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
            Task { @MainActor in
                guard let self else { return }
                self.world = WindowScanner.world(scale: self.body.scale)
            }
        }
        scanTimer?.tolerance = t * 0.3
    }

    private func setFrameRate(asleep: Bool) {
        asleepRate = asleep
        let lowPower = brain.lowPower
        link?.preferredFrameRateRange = asleep
            ? CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)
            : CAFrameRateRange(minimum: 30, maximum: lowPower ? 30 : 60, preferred: lowPower ? 30 : 60)
    }

    // MARK: Frame

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = CGFloat(min(max(now - lastTick, 0), 1.0 / 12))
        lastTick = now
        guard !settings.paused, dt > 0 else { return }

        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse { lastMouse = mouse; lastMouseMove = now }

        if !dragging, let e = body.update(dt, world: world) {
            brain.bodyEvent(e)
        }

        // Petting: the pointer resting on the cat and moving now and then.
        let over = hit(mouse)
        let pressed = NSEvent.pressedMouseButtons != 0
        if over && !pressed && !dragging && now - lastMouseMove < 1.5 { hoverTime += dt } else { hoverTime = 0 }
        let petting = hoverTime > 0.5 && body.isGrounded
        brain.petting(petting, dt: dt)
        brain.update(dt, world: world)
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
        view.needsDisplay = true
        let ignore = !(over || dragging)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }

        if bubble.visible { bubble.place(above: headPoint(frame)) }

        let asleep = brain.isAsleep && !brain.isPetted
        if asleep != asleepRate {
            setFrameRate(asleep: asleep)
            setScanInterval(asleep ? 0.5 : 0.12)
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
                               happiness: 1 - n.loneliness * 0.6 - n.grudge * 0.4, playfulness: n.boredom, updated: Date()))
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
        }.store(in: &cancellables)
        settings.$sound.sink { [weak self] on in self?.voice.enabled = on }.store(in: &cancellables)
        settings.$volume.sink { [weak self] v in self?.voice.volume = Float(v) }.store(in: &cancellables)
        settings.$name.sink { [weak self] n in self?.thoughts.name = n; self?.hearing.name = n }.store(in: &cancellables)
        settings.$aiThoughts.sink { [weak self] on in self?.thoughts.useModel = on }.store(in: &cancellables)
        settings.$sight.sink { [weak self] on in on ? self?.sight.start() : self?.sight.stop() }.store(in: &cancellables)
        settings.$hearing.sink { [weak self] on in on ? self?.hearing.start() : self?.hearing.stop() }.store(in: &cancellables)
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
        sight.onAway = { [weak self] away in self?.brain.react(away ? .userLeft : .userBack) }
        sight.onWave = { [weak self] in self?.brain.react(.wave) }
        hearing.onEvent = { [weak self] e in self?.brain.react(e) }
        screenEyes.onEvent = { [weak self] e in self?.brain.react(e) }
        screenEyes.catPosition = { [weak self] in self?.body.pos ?? .zero }
        screenEyes.shouldLook = { [weak self] in
            guard let self else { return false }
            return !self.brain.isAsleep && self.brain.needs.curiosity > 0.3 && !self.settings.paused
        }
        system.onEvent = { [weak self] e in self?.brain.react(e) }
        system.onLowPower = { [weak self] low in
            guard let self else { return }
            self.brain.lowPower = low
            self.setFrameRate(asleep: self.asleepRate)
        }
        system.onScreensChanged = { [weak self] in
            guard let self else { return }
            self.world = WindowScanner.world(scale: self.body.scale)
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
            }
        }
    }

    private func comeBackInside() {
        world = WindowScanner.world(scale: body.scale)
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
            self.bubble.show(text, above: self.headPoint(f))
        }
    }

    func sayText(_ text: String) {
        guard let f = anim.lastFrame, !settings.paused else { return }
        bubble.show(text, above: headPoint(f))
    }

    func play(_ sound: CatSound) {
        voice.play(sound)
        if sound != .crunch { hearing.mute(for: 2) }
        if sound == .meow || sound == .meowLong || sound == .demand || sound == .trill { particles.emit(.note, at: notePoint, scale: body.scale) }
    }

    private var notePoint: CGPoint {
        guard let f = anim.lastFrame else { return body.pos }
        return headPoint(f)
    }

    func emit(_ particle: ParticleKind) {
        guard let f = anim.lastFrame else { return }
        let p = particle == .ring ? CGPoint(x: body.pos.x, y: body.pos.y + 25 * body.scale) : headPoint(f)
        particles.emit(particle, at: p, scale: body.scale)
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

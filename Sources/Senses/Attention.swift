import AppKit
import IOKit.pwr_mgt

/// Decides when the camera and the microphone are worth opening. They stay off
/// unless something is happening: you come back to the Mac, you click the cat,
/// or now and then he gets curious and looks at you for a few seconds.
/// Being away is read from keyboard and mouse, so it needs no camera.
@MainActor
final class Attention {
    var onEvent: ((CatEvent) -> Void)?
    var openEyes: ((TimeInterval) -> Void)?
    var openEars: ((TimeInterval) -> Void)?
    var catAwake: (() -> Bool)?

    private var timer: Timer?
    private var away = false
    private var nextCuriosity = Date().addingTimeInterval(.random(in: 240...480))

    /// Away after this long without keyboard or mouse, unless a video is playing.
    private let awayAfter: TimeInterval = 240

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.5
    }

    /// Someone clicked the cat: he looks and listens for a moment.
    func poked() {
        openEyes?(8)
        openEars?(10)
    }

    private func tick() {
        let idle = Self.idleSeconds
        if !away, idle > awayAfter, !Self.videoPlaying {
            away = true
            onEvent?(.userLeft)
        } else if away, idle < 3 {
            away = false
            onEvent?(.userBack)
            openEyes?(8)
            openEars?(10)
        }
        if !away, idle < 60, Date() > nextCuriosity, catAwake?() ?? true {
            nextCuriosity = Date().addingTimeInterval(.random(in: 420...900))
            openEyes?(6)
        }
    }

    /// Seconds since the last key press, click, scroll or pointer move.
    static var idleSeconds: TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    /// A video or a call keeps the display awake: nobody is touching the Mac, but someone is there.
    private static var videoPlaying: Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (dict[kIOPMAssertPreventUserIdleDisplaySleep as String] ?? 0) > 0
    }
}

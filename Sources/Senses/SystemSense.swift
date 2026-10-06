import AppKit
import IOKit.ps

/// What the Mac itself tells the cat: which app is in front, sleep and wake,
/// heat, battery, low power mode, screens coming and going.
final class SystemSense {
    var onEvent: ((CatEvent) -> Void)?
    var onLowPower: ((Bool) -> Void)?
    var onScreensChanged: (() -> Void)?
    private(set) var frontApp = ""

    private var observers: [NSObjectProtocol] = []
    private var batteryTimer: Timer?
    private var lastLevel: Int?
    private var lastCharging: Bool?

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let name = app.localizedName else { return }
            self?.frontApp = name
            self?.onEvent?(.appActivated(name))
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onEvent?(.macWoke)
        })
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkThermal()
        })
        observers.append(nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.onLowPower?(ProcessInfo.processInfo.isLowPowerModeEnabled)
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onScreensChanged?()
        })
        frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        onLowPower?(ProcessInfo.processInfo.isLowPowerModeEnabled)
        checkThermal()
        readBattery()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.readBattery() }
    }

    private func checkThermal() {
        let s = ProcessInfo.processInfo.thermalState
        onEvent?(.hotMac(s == .serious || s == .critical))
    }

    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let level = desc["Current Capacity"] as? Int else { continue }
            let charging = (desc["Is Charging"] as? Bool) ?? ((desc["Power Source State"] as? String) == "AC Power")
            if let last = lastLevel, last > 15, level <= 15, !charging { onEvent?(.lowBattery) }
            if let was = lastCharging, !was, charging { onEvent?(.charging) }
            lastLevel = level
            lastCharging = charging
            return
        }
    }
}

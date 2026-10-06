import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: CatController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = CatController(settings: CatSettings())
        controller = c
        c.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.openSettings()
        return false
    }
}

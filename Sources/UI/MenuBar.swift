import AppKit

@MainActor
protocol MenuBarActions: AnyObject {
    var menuStatus: String { get }
    var catName: String { get }
    var isOutside: Bool { get }
    var isAsleep: Bool { get }
    var size: CatSize { get }
    var soundOn: Bool { get }
    func feed()
    func call()
    func find()
    func toggleSleep()
    func setSize(_ s: CatSize)
    func toggleSound()
    func toggleOutside()
    func openSettings()
    func openAbout()
}

/// The cat's silhouette in the menu bar, and everything you can ask of it.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var actions: MenuBarActions?
    let menu = NSMenu()

    init(actions: MenuBarActions) {
        self.actions = actions
        super.init()
        if let cg = CatRig.image(.sit, size: 44, glow: 0) {
            let img = NSImage(cgImage: cg, size: CGSize(width: 20, height: 20))
            img.isTemplate = true
            item.button?.image = img
        }
        item.button?.toolTip = "The Black Cat"
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let a = actions else { return }
        menu.removeAllItems()
        let header = NSMenuItem(title: "\(a.catName): \(a.menuStatus.lowercased())", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        add("Dai da mangiare", #selector(feed), "f", symbol: "fish")
        add("Chiamalo", #selector(call), "c", symbol: "pawprint")
        add("Dov'è?", #selector(find), "", symbol: "scope")
        add(a.isAsleep ? "Sveglialo" : "Mettilo a nanna", #selector(toggleSleep), "", symbol: a.isAsleep ? "sun.max" : "moon.zzz")
        menu.addItem(.separator())

        let sizeItem = NSMenuItem(title: "Taglia", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for s in CatSize.allCases {
            let i = NSMenuItem(title: s.label, action: #selector(pickSize(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = s.rawValue
            i.state = a.size == s ? .on : .off
            sub.addItem(i)
        }
        sizeItem.submenu = sub
        menu.addItem(sizeItem)
        let sound = add("Miagolii e fusa", #selector(toggleSound), "")
        sound.state = a.soundOn ? .on : .off
        add(a.isOutside ? "Fallo rientrare" : "Mandalo in giardino", #selector(toggleOutside), "", symbol: a.isOutside ? "house" : "leaf")
        menu.addItem(.separator())
        add("Impostazioni e sensi…", #selector(settings), ",")
        add("Informazioni su The Black Cat", #selector(about), "")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Esci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @discardableResult
    private func add(_ title: String, _ sel: Selector, _ key: String, symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(i)
        return i
    }

    @objc private func feed() { actions?.feed() }
    @objc private func call() { actions?.call() }
    @objc private func find() { actions?.find() }
    @objc private func toggleSleep() { actions?.toggleSleep() }
    @objc private func toggleSound() { actions?.toggleSound() }
    @objc private func toggleOutside() { actions?.toggleOutside() }
    @objc private func settings() { actions?.openSettings() }
    @objc private func about() { actions?.openAbout() }
    @objc private func pickSize(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let s = CatSize(rawValue: raw) { actions?.setSize(s) }
    }
}

import AppKit

/// Reads where the other apps' windows are. Only the rectangles and the owner
/// name are used, which macOS hands out without the screen recording permission.
enum WindowScanner {
    private static let ownPID = ProcessInfo.processInfo.processIdentifier
    private static let ignoredOwners: Set<String> = ["Dock", "Window Server", "Control Center",
                                                    "Centro di Controllo", "Notification Center",
                                                    "Centro Notifiche", "SystemUIServer"]

    static func screens() -> [ScreenInfo] {
        NSScreen.screens.map { ScreenInfo(frame: $0.frame, visible: $0.visibleFrame) }
    }

    static func windows() -> [WindowInfo] {
        guard let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let h = primary.frame.height
        var out: [WindowInfo] = []
        for d in list {
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  let pid = d[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let boundsDict = d[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let number = d[kCGWindowNumber as String] as? UInt32
            else { continue }
            if let alpha = d[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            // Small enough to include Stage Manager's thumbnails on the side of the screen.
            if bounds.width < 60 || bounds.height < 50 { continue }
            let owner = d[kCGWindowOwnerName as String] as? String ?? ""
            if ignoredOwners.contains(owner) { continue }
            let frame = ScreenSpace.cocoaRect(fromQuartz: bounds, primaryHeight: h)
            // Stage Manager stacks a proxy and the app's own window on the same rectangle.
            if out.contains(where: { $0.frame == frame }) { continue }
            out.append(WindowInfo(id: number,
                                  frame: frame,
                                  pid: pid, owner: owner))
        }
        return out
    }

    /// Where one window is right now, cheaply: used to follow the window under the cat
    /// between full scans. Nil when the window is gone or hidden.
    static func frame(of id: UInt32) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let ids = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
        defer { ids.deallocate() }
        ids[0] = UnsafeRawPointer(bitPattern: UInt(id))
        guard let array = CFArrayCreate(nil, ids, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]],
              let d = list.first,
              let b = d[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
        if (d[kCGWindowIsOnscreen as String] as? Bool) == false { return nil }
        return ScreenSpace.cocoaRect(fromQuartz: r, primaryHeight: primary.frame.height)
    }

    static func world(scale: CGFloat) -> World {
        WorldBuilder.build(windows: windows(), screens: screens(),
                           clearance: 8, minPiece: 46 * scale)
    }
}

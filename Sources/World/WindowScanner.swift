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
            if bounds.width < 120 || bounds.height < 70 { continue }
            let owner = d[kCGWindowOwnerName as String] as? String ?? ""
            if ignoredOwners.contains(owner) { continue }
            out.append(WindowInfo(id: number,
                                  frame: ScreenSpace.cocoaRect(fromQuartz: bounds, primaryHeight: h),
                                  pid: pid, owner: owner))
        }
        return out
    }

    static func world(scale: CGFloat) -> World {
        WorldBuilder.build(windows: windows(), screens: screens(),
                           clearance: 8, minPiece: 46 * scale)
    }
}

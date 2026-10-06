import AppKit
import ApplicationServices

/// The cat's mischief: a paw on a window and a small push, through Accessibility.
/// Only moves a window a few dozen points, never closes or resizes anything.
enum WindowNudger {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func nudge(_ w: WindowInfo, dx: CGFloat) {
        guard isTrusted, let primary = NSScreen.screens.first else { return }
        let want = ScreenSpace.quartzRect(fromCocoa: w.frame, primaryHeight: primary.frame.height)
        let app = AXUIElementCreateApplication(w.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for win in windows {
            guard let origin = point(win, kAXPositionAttribute), let size = size(win) else { continue }
            guard abs(origin.x - want.minX) < 4, abs(origin.y - want.minY) < 4,
                  abs(size.width - want.width) < 4, abs(size.height - want.height) < 4 else { continue }
            let steps = 8
            for i in 1...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03 * Double(i)) {
                    var p = CGPoint(x: origin.x + dx * CGFloat(i) / CGFloat(steps), y: origin.y)
                    if let v = AXValueCreate(.cgPoint, &p) {
                        AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v)
                    }
                }
            }
            return
        }
    }

    /// Sends a window to the Dock, as if a paw had landed on the yellow button. Never closes anything.
    static func minimize(_ w: WindowInfo) {
        guard isTrusted, let win = axWindow(for: w) else { return }
        AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    private static func axWindow(for w: WindowInfo) -> AXUIElement? {
        guard let primary = NSScreen.screens.first else { return nil }
        let want = ScreenSpace.quartzRect(fromCocoa: w.frame, primaryHeight: primary.frame.height)
        let app = AXUIElementCreateApplication(w.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { win in
            guard let o = point(win, kAXPositionAttribute), let s = size(win) else { return false }
            return abs(o.x - want.minX) < 4 && abs(o.y - want.minY) < 4 && abs(s.width - want.width) < 4 && abs(s.height - want.height) < 4
        }
    }

    private static func point(_ e: AXUIElement, _ attr: String) -> CGPoint? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func size(_ e: AXUIElement) -> CGSize? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
}

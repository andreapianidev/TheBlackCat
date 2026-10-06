import CoreGraphics

/// One window of another app, already in AppKit coordinates.
struct WindowInfo: Equatable {
    var id: UInt32
    var frame: CGRect
    var pid: Int32
    var owner: String
}

struct ScreenInfo: Equatable {
    var frame: CGRect
    var visible: CGRect
}

/// Where the cat's feet rest. Floors belong to a screen, ledges to a window.
enum Footing: Equatable {
    case floor(screen: Int)
    case window(id: UInt32, offsetX: CGFloat)
}

/// A horizontal run the cat can stand on.
struct Ledge: Equatable {
    var windowID: UInt32?      // nil for a screen floor
    var screen: Int
    var y: CGFloat
    var span: Interval
}

enum WallSide: Equatable {
    /// The window's left edge: the cat hangs on it from the outside, facing right.
    case left
    /// The window's right edge: the cat hangs on it from the outside, facing left.
    case right
}

/// A vertical run of a window side the cat can climb.
struct Wall: Equatable {
    var windowID: UInt32
    var side: WallSide
    var x: CGFloat
    var span: Interval
}

struct World {
    var screens: [ScreenInfo] = []
    var windows: [WindowInfo] = []
    var ledges: [Ledge] = []
    var walls: [Wall] = []

    var floors: [Ledge] { ledges.filter { $0.windowID == nil } }

    func window(_ id: UInt32) -> WindowInfo? { windows.first { $0.id == id } }

    /// The walkable piece under `x` that belongs to the given footing.
    func ledge(for footing: Footing, at x: CGFloat, margin: CGFloat = 0) -> Ledge? {
        switch footing {
        case .floor(let s):
            return ledges.first { $0.windowID == nil && $0.screen == s && $0.span.contains(x, margin: margin) }
        case .window(let id, _):
            return ledges.first { $0.windowID == id && $0.span.contains(x, margin: margin) }
        }
    }

    /// The highest walkable piece crossed while moving from `fromY` down to `toY` at `x`.
    func landing(x: CGFloat, fromY: CGFloat, toY: CGFloat) -> Ledge? {
        ledges
            .filter { $0.span.contains(x) && $0.y <= fromY + 0.5 && $0.y >= toY }
            .max { $0.y < $1.y }
    }

    /// The floor closest to `x`, for when the cat falls between screens.
    func nearestFloor(to x: CGFloat) -> Ledge? {
        floors.min { a, b in
            abs(a.span.clamp(x) - x) < abs(b.span.clamp(x) - x)
        }
    }

    func screenIndex(containing p: CGPoint) -> Int? {
        screens.firstIndex { $0.frame.insetBy(dx: -1, dy: -1).contains(p) }
    }

    var bounds: CGRect {
        screens.reduce(CGRect.null) { $0.union($1.frame) }
    }
}

enum WorldBuilder {
    /// Turns raw windows (front to back, as Quartz lists them) into the walkable world.
    ///
    /// - `clearance`: how much free room the cat needs above an edge.
    /// - `minPiece`: shortest piece worth standing on.
    static func build(windows: [WindowInfo], screens: [ScreenInfo],
                      clearance: CGFloat = 8, minPiece: CGFloat = 46) -> World {
        var world = World(screens: screens, windows: windows)

        for (i, s) in screens.enumerated() {
            world.ledges.append(Ledge(windowID: nil, screen: i, y: s.visible.minY,
                                      span: Interval(lo: s.visible.minX, hi: s.visible.maxX)))
        }

        for (i, w) in windows.enumerated() {
            let front = windows[..<i]
            let top = w.frame.maxY
            let mid = CGPoint(x: w.frame.midX, y: top - 1)
            guard let si = screens.firstIndex(where: { $0.frame.contains(mid) }) else { continue }
            let screen = screens[si]

            // The top edge, if there is room above it under the menu bar.
            if top < screen.visible.maxY - 24 && top > screen.visible.minY + 20 {
                let base = Interval(lo: max(w.frame.minX, screen.frame.minX),
                                    hi: min(w.frame.maxX, screen.frame.maxX))
                let cuts = front
                    .filter { $0.frame.minY < top + clearance && $0.frame.maxY > top }
                    .map { Interval(lo: $0.frame.minX, hi: $0.frame.maxX) }
                for piece in IntervalMath.subtract(base, cuts) where piece.length >= minPiece {
                    world.ledges.append(Ledge(windowID: w.id, screen: si, y: top, span: piece))
                }
            }

            // The sides, if the window is tall enough to be worth climbing.
            guard w.frame.height >= 140 else { continue }
            let sides: [(WallSide, CGFloat)] = [(.left, w.frame.minX), (.right, w.frame.maxX)]
            for (side, x) in sides {
                // The cat hangs outside the window, so there must be screen room there.
                let outside = side == .left ? x - 40 : x + 40
                guard outside > screen.frame.minX && outside < screen.frame.maxX else { continue }
                let base = Interval(lo: max(w.frame.minY, screen.visible.minY),
                                    hi: min(w.frame.maxY, screen.visible.maxY))
                let cuts = front
                    .filter { $0.frame.minX <= x + 3 && $0.frame.maxX >= x - 3 }
                    .map { Interval(lo: $0.frame.minY, hi: $0.frame.maxY) }
                for piece in IntervalMath.subtract(base, cuts) where piece.length >= 80 {
                    world.walls.append(Wall(windowID: w.id, side: side, x: x, span: piece))
                }
            }
        }
        return world
    }
}

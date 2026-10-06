import CoreGraphics

/// A closed range on one axis, used for the walkable part of an edge.
struct Interval: Equatable {
    var lo: CGFloat
    var hi: CGFloat

    var length: CGFloat { hi - lo }

    func contains(_ v: CGFloat, margin: CGFloat = 0) -> Bool {
        v >= lo - margin && v <= hi + margin
    }

    func clamp(_ v: CGFloat, inset: CGFloat = 0) -> CGFloat {
        let a = lo + inset, b = hi - inset
        if a > b { return (lo + hi) / 2 }
        return min(max(v, a), b)
    }
}

enum IntervalMath {
    /// What is left of `base` once every cut has been removed, sorted left to right.
    static func subtract(_ base: Interval, _ cuts: [Interval]) -> [Interval] {
        var pieces = [base]
        for c in cuts {
            var next: [Interval] = []
            for p in pieces {
                if c.hi <= p.lo || c.lo >= p.hi {
                    next.append(p)
                    continue
                }
                if c.lo > p.lo { next.append(Interval(lo: p.lo, hi: c.lo)) }
                if c.hi < p.hi { next.append(Interval(lo: c.hi, hi: p.hi)) }
            }
            pieces = next
        }
        return pieces.sorted { $0.lo < $1.lo }
    }
}

enum ScreenSpace {
    /// Quartz window bounds have their origin at the top left of the primary
    /// display with y growing down. AppKit puts it at the bottom left with y up.
    static func cocoaRect(fromQuartz r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func quartzRect(fromCocoa r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    func distance(to p: CGPoint) -> CGFloat { hypot(p.x - x, p.y - y) }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}

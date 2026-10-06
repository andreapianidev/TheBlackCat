import CoreGraphics

/// The postures the cat knows. Everything in between is blended.
enum PoseKind: String, Codable, CaseIterable {
    case stand, sit, loaf, sleep, flat, groom, stretch, crouch
    case airUp, airDown, hiss, dangle, eat, wave, lookUp, knead
    /// Hanging by the front paws from an edge; the origin is the grip.
    case hang
    /// Sitting on an edge and reaching down with a paw.
    case paw
    /// On its back, paws in the air, head upside down.
    case belly
    /// Up on its hind legs against something, sharpening its claws.
    case scratch
}

/// Every number that shapes the cat in one frame.
///
/// Rig space: points at scale 1, origin on the ground between the feet,
/// x pointing where the cat faces, y up.
struct CatPose {
    var hip = CGPoint(x: -20, y: 30)
    var chest = CGPoint(x: 16, y: 29)
    var hipR: CGFloat = 11
    var chestR: CGFloat = 10
    /// Hump above the spine (an arched, hissing back).
    var arch: CGFloat = 0
    var head = CGPoint(x: 27, y: 41)
    var headR: CGFloat = 10.5
    /// Radians, positive tips the nose up.
    var headTilt: CGFloat = 0
    /// Near front, far front, near hind, far hind.
    var feet: [CGPoint] = [CGPoint(x: 17, y: 0), CGPoint(x: 13, y: 0),
                           CGPoint(x: -19, y: 0), CGPoint(x: -23, y: 0)]
    var eyeOpen: CGFloat = 1
    /// 0 is a slit, 1 a round hunting pupil.
    var pupil: CGFloat = 0.35
    var earBack: CGFloat = 0
    var mouthOpen: CGFloat = 0
    /// 1 hides the legs under the body (loaf, sleep).
    var tuck: CGFloat = 0

    static func lerp(_ a: CatPose, _ b: CatPose, _ t: CGFloat) -> CatPose {
        func l(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        func p(_ x: CGPoint, _ y: CGPoint) -> CGPoint { CGPoint(x: l(x.x, y.x), y: l(x.y, y.y)) }
        var r = a
        r.hip = p(a.hip, b.hip); r.chest = p(a.chest, b.chest)
        r.hipR = l(a.hipR, b.hipR); r.chestR = l(a.chestR, b.chestR)
        r.arch = l(a.arch, b.arch)
        r.head = p(a.head, b.head); r.headR = l(a.headR, b.headR); r.headTilt = l(a.headTilt, b.headTilt)
        r.feet = zip(a.feet, b.feet).map { p($0, $1) }
        r.eyeOpen = l(a.eyeOpen, b.eyeOpen); r.pupil = l(a.pupil, b.pupil)
        r.earBack = l(a.earBack, b.earBack); r.mouthOpen = l(a.mouthOpen, b.mouthOpen)
        r.tuck = l(a.tuck, b.tuck)
        return r
    }

    static func make(_ kind: PoseKind) -> CatPose {
        var p = CatPose()
        func feet(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ c: (CGFloat, CGFloat), _ d: (CGFloat, CGFloat)) {
            p.feet = [CGPoint(x: a.0, y: a.1), CGPoint(x: b.0, y: b.1), CGPoint(x: c.0, y: c.1), CGPoint(x: d.0, y: d.1)]
        }
        switch kind {
        case .stand:
            break
        case .hang:
            p.head = CGPoint(x: 5, y: -9); p.headTilt = 0.25
            p.chest = CGPoint(x: 2, y: -20); p.chestR = 9.5
            p.hip = CGPoint(x: -1, y: -44); p.hipR = 10.5
            feet((3, 0), (6, 0), (-2, -64), (2, -62))
            p.pupil = 0.95; p.earBack = 0.35
        case .belly:
            p.hip = CGPoint(x: -14, y: 9); p.hipR = 11
            p.chest = CGPoint(x: 10, y: 10); p.chestR = 10.5
            p.head = CGPoint(x: 23, y: 10); p.headTilt = .pi * 0.92
            feet((12, 27), (16, 24), (-15, 27), (-11, 24))
            p.pupil = 0.8; p.eyeOpen = 0.7
        case .scratch:
            p.hip = CGPoint(x: -6, y: 16); p.hipR = 12
            p.chest = CGPoint(x: 6, y: 38); p.chestR = 9.5
            p.head = CGPoint(x: 9, y: 53); p.headTilt = 0.2
            feet((18, 50), (17, 43), (0, 0), (-4, 0))
            p.eyeOpen = 0.35
        case .paw:
            p.hip = CGPoint(x: -12, y: 13); p.hipR = 13.5
            p.chest = CGPoint(x: 5, y: 32); p.chestR = 10
            p.head = CGPoint(x: 12, y: 45); p.headTilt = -0.55
            feet((17, -9), (6, 0), (2, 0), (-1, 0))
            p.pupil = 1
        case .sit, .groom, .wave, .lookUp:
            p.hip = CGPoint(x: -12, y: 13); p.hipR = 13.5
            p.chest = CGPoint(x: 5, y: 32); p.chestR = 10
            p.head = CGPoint(x: 10, y: 49)
            feet((9, 0), (6, 0), (2, 0), (-1, 0))
            if kind == .groom {
                p.feet[0] = CGPoint(x: 14, y: 40)
                p.head = CGPoint(x: 12, y: 46); p.headTilt = -0.45; p.eyeOpen = 0.25
            } else if kind == .wave {
                p.feet[0] = CGPoint(x: 19, y: 44)
                p.head = CGPoint(x: 10, y: 50); p.headTilt = 0.1
            } else if kind == .lookUp {
                p.head = CGPoint(x: 8, y: 52); p.headTilt = 0.5; p.pupil = 0.7
            }
        case .loaf:
            p.hip = CGPoint(x: -16, y: 12); p.hipR = 12.5
            p.chest = CGPoint(x: 12, y: 12); p.chestR = 11.5
            p.head = CGPoint(x: 22, y: 24)
            feet((16, 1), (13, 1), (-12, 1), (-15, 1))
            p.tuck = 1; p.eyeOpen = 0.55
        case .sleep:
            p.hip = CGPoint(x: -8, y: 12); p.hipR = 13
            p.chest = CGPoint(x: 8, y: 12); p.chestR = 12.5
            p.head = CGPoint(x: 15, y: 10); p.headR = 10; p.headTilt = -0.35
            feet((10, 2), (8, 2), (-6, 2), (-8, 2))
            p.tuck = 1; p.eyeOpen = 0; p.earBack = 0.25
        case .flat:
            p.hip = CGPoint(x: -24, y: 9); p.hipR = 9.5
            p.chest = CGPoint(x: 14, y: 9); p.chestR = 9
            p.head = CGPoint(x: 29, y: 11); p.headTilt = -0.1
            feet((36, 3), (33, 2), (-42, 4), (-39, 3))
            p.eyeOpen = 0.25; p.earBack = 0.3
        case .stretch:
            p.hip = CGPoint(x: -18, y: 31); p.chest = CGPoint(x: 14, y: 11); p.chestR = 9.5
            p.head = CGPoint(x: 28, y: 14); p.headTilt = 0.25
            feet((33, 0), (30, 0), (-20, 0), (-24, 0))
            p.eyeOpen = 0.35
        case .crouch:
            p.hip = CGPoint(x: -18, y: 20); p.hipR = 11.5
            p.chest = CGPoint(x: 13, y: 15)
            p.head = CGPoint(x: 25, y: 21)
            feet((19, 0), (15, 0), (-16, 0), (-20, 0))
            p.pupil = 1; p.earBack = 0.15
        case .airUp:
            p.hip = CGPoint(x: -20, y: 30); p.chest = CGPoint(x: 18, y: 35)
            p.head = CGPoint(x: 30, y: 45); p.headTilt = 0.15
            feet((33, 28), (30, 25), (-38, 18), (-35, 15))
            p.pupil = 0.9
        case .airDown:
            p.hip = CGPoint(x: -18, y: 34); p.chest = CGPoint(x: 15, y: 28)
            p.head = CGPoint(x: 26, y: 38); p.headTilt = -0.2
            feet((22, 4), (19, 6), (-17, 12), (-20, 14))
            p.pupil = 0.9
        case .hiss:
            p.hip = CGPoint(x: -17, y: 31); p.chest = CGPoint(x: 14, y: 31); p.arch = 11
            p.head = CGPoint(x: 24, y: 31); p.headTilt = -0.1
            feet((17, 0), (14, 0), (-17, 0), (-20, 0))
            p.earBack = 1; p.mouthOpen = 1; p.pupil = 1
        case .dangle:
            p.head = CGPoint(x: 8, y: 62)
            p.chest = CGPoint(x: 4, y: 46); p.chestR = 9.5
            p.hip = CGPoint(x: -1, y: 16); p.hipR = 10.5
            feet((8, 24), (5, 26), (-1, -8), (2, -6))
            p.pupil = 0.8; p.earBack = 0.3
        case .eat:
            p.hip = CGPoint(x: -18, y: 30); p.chest = CGPoint(x: 14, y: 24)
            p.head = CGPoint(x: 25, y: 12); p.headTilt = -0.5
            p.eyeOpen = 0.5
        case .knead:
            p.hip = CGPoint(x: -14, y: 14); p.hipR = 13
            p.chest = CGPoint(x: 10, y: 22)
            p.head = CGPoint(x: 19, y: 34)
            feet((14, 0), (10, 0), (-6, 0), (-9, 0))
            p.eyeOpen = 0.12
        }
        return p
    }
}

/// How the tail is carried. Angles in radians in rig space (0 forward, pi/2 up).
struct TailStyle {
    var angle: CGFloat
    var curl: CGFloat
    var waveAmp: CGFloat
    var waveFreq: CGFloat
    var stiffness: CGFloat
    var puff: CGFloat

    static let relaxed  = TailStyle(angle: 2.75, curl: 0.7, waveAmp: 0.14, waveFreq: 0.5, stiffness: 30, puff: 1)
    static let happy    = TailStyle(angle: 1.55, curl: -2.0, waveAmp: 0.1, waveFreq: 0.6, stiffness: 45, puff: 1)
    static let alert    = TailStyle(angle: 1.95, curl: -0.7, waveAmp: 0.05, waveFreq: 1.5, stiffness: 60, puff: 1)
    static let stalking = TailStyle(angle: 3.2, curl: 0.25, waveAmp: 0.3, waveFreq: 2.6, stiffness: 40, puff: 1)
    static let angry    = TailStyle(angle: 1.7, curl: -0.25, waveAmp: 0.04, waveFreq: 0.4, stiffness: 120, puff: 1.9)
    static let wrapped  = TailStyle(angle: 3.35, curl: 3.0, waveAmp: 0.03, waveFreq: 0.3, stiffness: 22, puff: 1)
    static let annoyed  = TailStyle(angle: 2.6, curl: 0.4, waveAmp: 0.55, waveFreq: 1.4, stiffness: 40, puff: 1)
    static let falling  = TailStyle(angle: 1.5, curl: 0.4, waveAmp: 0.3, waveFreq: 1.2, stiffness: 25, puff: 1.2)
    static let hanging  = TailStyle(angle: 4.65, curl: 0.25, waveAmp: 0.18, waveFreq: 0.5, stiffness: 18, puff: 1)
}

import CoreGraphics

/// A cat's coat: colours and markings. The rig paints the same body with any of them.
struct CatCoat: Identifiable, Equatable {
    let id: String
    /// What the menu shows.
    let name: String
    /// How the cat describes itself to the language model.
    let adjective: String
    let fur: CGColor
    let farFur: CGColor
    let earInner: CGColor
    let nose: CGColor
    let irisIn: CGColor
    let irisOut: CGColor
    let whisker: CGColor
    let closedEye: CGColor
    let rim: CGColor
    var stripes: CGColor? = nil
    var points: CGColor? = nil
    var bib: CGColor? = nil
    var patchA: CGColor? = nil
    var patchB: CGColor? = nil
    /// Dark coats get white ink lines in the comic style, light ones black.
    var isDark = false
    /// Cartoon face: a wide white muzzle with cheek tufts and a big round nose.
    var cartoon = false

    static func == (a: CatCoat, b: CatCoat) -> Bool { a.id == b.id }

    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    static let black = CatCoat(
        id: "nero", name: "Nero", adjective: "nero",
        fur: c(0.045, 0.045, 0.06), farFur: c(0.11, 0.11, 0.14), earInner: c(0.27, 0.15, 0.19),
        nose: c(0.32, 0.19, 0.23), irisIn: c(0.95, 0.96, 0.42), irisOut: c(0.58, 0.78, 0.2),
        whisker: c(1, 1, 1, 0.3), closedEye: c(0.42, 0.44, 0.52), rim: c(0.47, 0.55, 0.72, 0.42), isDark: true)

    static let tuxedo = CatCoat(
        id: "smoking", name: "In smoking", adjective: "bianco e nero, in smoking",
        fur: c(0.05, 0.05, 0.065), farFur: c(0.12, 0.12, 0.15), earInner: c(0.32, 0.18, 0.22),
        nose: c(0.85, 0.5, 0.55), irisIn: c(0.96, 0.9, 0.45), irisOut: c(0.75, 0.68, 0.18),
        whisker: c(1, 1, 1, 0.55), closedEye: c(0.45, 0.47, 0.55), rim: c(0.47, 0.55, 0.72, 0.38),
        bib: c(0.96, 0.96, 0.95), isDark: true)

    static let ginger = CatCoat(
        id: "rosso", name: "Rosso tigrato", adjective: "rosso tigrato",
        fur: c(0.88, 0.52, 0.22), farFur: c(0.74, 0.41, 0.16), earInner: c(0.96, 0.68, 0.62),
        nose: c(0.86, 0.48, 0.48), irisIn: c(1, 0.86, 0.38), irisOut: c(0.86, 0.56, 0.12),
        whisker: c(1, 1, 1, 0.75), closedEye: c(0.55, 0.3, 0.12), rim: c(1, 0.85, 0.6, 0.35),
        stripes: c(0.66, 0.32, 0.1))

    static let chartreux = CatCoat(
        id: "certosino", name: "Grigio certosino", adjective: "grigio certosino",
        fur: c(0.47, 0.5, 0.57), farFur: c(0.38, 0.4, 0.47), earInner: c(0.62, 0.52, 0.57),
        nose: c(0.33, 0.34, 0.42), irisIn: c(1, 0.78, 0.32), irisOut: c(0.86, 0.5, 0.14),
        whisker: c(1, 1, 1, 0.6), closedEye: c(0.25, 0.27, 0.33), rim: c(0.8, 0.85, 0.95, 0.35))

    static let white = CatCoat(
        id: "bianco", name: "Bianco", adjective: "bianco",
        fur: c(0.96, 0.96, 0.95), farFur: c(0.84, 0.84, 0.86), earInner: c(0.98, 0.7, 0.74),
        nose: c(0.96, 0.6, 0.66), irisIn: c(0.72, 0.9, 1), irisOut: c(0.3, 0.56, 0.92),
        whisker: c(0.55, 0.55, 0.6, 0.6), closedEye: c(0.55, 0.55, 0.6), rim: c(0.7, 0.75, 0.88, 0.45))

    static let siamese = CatCoat(
        id: "siamese", name: "Siamese", adjective: "siamese",
        fur: c(0.94, 0.88, 0.77), farFur: c(0.83, 0.76, 0.65), earInner: c(0.5, 0.35, 0.32),
        nose: c(0.28, 0.2, 0.17), irisIn: c(0.72, 0.9, 1), irisOut: c(0.25, 0.5, 0.9),
        whisker: c(1, 1, 1, 0.7), closedEye: c(0.3, 0.22, 0.18), rim: c(1, 0.95, 0.85, 0.3),
        points: c(0.3, 0.21, 0.16))

    static let calico = CatCoat(
        id: "tricolore", name: "Tricolore", adjective: "tricolore",
        fur: c(0.97, 0.96, 0.93), farFur: c(0.86, 0.85, 0.82), earInner: c(0.97, 0.7, 0.72),
        nose: c(0.95, 0.6, 0.62), irisIn: c(0.95, 0.92, 0.5), irisOut: c(0.55, 0.72, 0.25),
        whisker: c(0.5, 0.5, 0.5, 0.6), closedEye: c(0.4, 0.38, 0.36), rim: c(0.85, 0.8, 0.7, 0.35),
        patchA: c(0.92, 0.56, 0.2), patchB: c(0.13, 0.12, 0.13))

    static let tabby = CatCoat(
        id: "soriano", name: "Soriano", adjective: "soriano grigio e marrone",
        fur: c(0.58, 0.52, 0.45), farFur: c(0.48, 0.43, 0.37), earInner: c(0.8, 0.6, 0.58),
        nose: c(0.72, 0.42, 0.42), irisIn: c(0.85, 0.95, 0.45), irisOut: c(0.4, 0.68, 0.22),
        whisker: c(1, 1, 1, 0.7), closedEye: c(0.25, 0.22, 0.2), rim: c(0.95, 0.9, 0.8, 0.3),
        stripes: c(0.22, 0.19, 0.16))

    static let silvestro = CatCoat(
        id: "silvestro", name: "Silvestro", adjective: "nero e bianco, da cartone animato, col nasone rosso",
        fur: c(0.05, 0.05, 0.065), farFur: c(0.12, 0.12, 0.15), earInner: c(0.86, 0.45, 0.5),
        nose: c(0.86, 0.16, 0.2), irisIn: c(0.98, 0.95, 0.55), irisOut: c(0.86, 0.74, 0.16),
        whisker: c(1, 1, 1, 0.75), closedEye: c(0.45, 0.47, 0.55), rim: c(0.47, 0.55, 0.72, 0.38),
        bib: c(0.97, 0.97, 0.95), isDark: true, cartoon: true)

    static let all: [CatCoat] = [.black, .tuxedo, .silvestro, .ginger, .chartreux, .white, .siamese, .calico, .tabby]

    static func named(_ id: String) -> CatCoat { all.first { $0.id == id } ?? .black }

    /// Colour of one tail segment, for rings, points and patches.
    func tailColor(_ i: Int, of n: Int) -> CGColor {
        let f = CGFloat(i) / CGFloat(max(n, 1))
        if let s = stripes, i % 3 == 1 { return s }
        if let p = points, f > 0.4 { return p }
        if let a = patchA, let b = patchB { return f < 0.35 ? a : (f < 0.6 ? fur : b) }
        if let w = bib, i == n { return w }
        return fur
    }
}

import Foundation

/// The cat's inner state. Every value is 0...1.
/// `energy` and `bond` are good when high; `hunger`, `boredom`, `loneliness` are urges.
struct Needs: Codable, Equatable {
    var energy: Double = 0.8
    var hunger: Double = 0.3
    var boredom: Double = 0.4
    var loneliness: Double = 0.4
    var curiosity: Double = 0.5
    /// How much it holds a grudge right now (thrown, scolded, dragged around).
    var grudge: Double = 0

    enum Doing { case sleeping, resting, active, playing, eating, petted }

    /// Advances the needs by `dt` seconds of the given kind of time.
    mutating func tick(_ dt: Double, doing: Doing) {
        let h = dt / 3600
        switch doing {
        case .sleeping: energy += h * 1.4
        case .resting, .petted, .eating: energy -= h * 0.08
        case .active: energy -= h * 0.35
        case .playing: energy -= h * 0.9
        }
        hunger += h / 5
        boredom += doing == .playing ? -h * 6 : (doing == .sleeping ? h * 0.1 : h * 0.6)
        loneliness += doing == .petted ? -h * 10 : h * 0.4
        curiosity += doing == .sleeping ? h * 0.3 : h * 0.5
        grudge -= h * 2.5
        clamp()
    }

    /// Catches up after the app was closed: the cat slept and got hungry.
    mutating func elapsedWhileAway(_ seconds: Double) {
        guard seconds > 60 else { return }
        let h = min(seconds, 24 * 3600) / 3600
        energy += h * 0.6
        hunger += h / 6
        loneliness += h * 0.15
        boredom += h * 0.1
        grudge = 0
        clamp()
    }

    mutating func fed() { hunger = 0; loneliness -= 0.1; grudge -= 0.2; clamp() }
    mutating func petted(_ dt: Double) { loneliness -= dt * 0.04; grudge -= dt * 0.02; clamp() }
    mutating func offended(_ amount: Double) { grudge += amount; clamp() }

    mutating func clamp() {
        func c(_ v: inout Double) { v = min(max(v, 0), 1) }
        c(&energy); c(&hunger); c(&boredom); c(&loneliness); c(&curiosity); c(&grudge)
    }
}

/// How lively a cat is at a given hour: crepuscular, lazy at noon, wild after dinner.
enum Circadian {
    static func liveliness(hour: Int) -> Double {
        switch hour {
        case 5..<8: return 1.3
        case 8..<12: return 0.75
        case 12..<16: return 0.5
        case 16..<19: return 0.9
        case 19..<23: return 1.35
        default: return 0.55
        }
    }

    static func sleepiness(hour: Int) -> Double {
        switch hour {
        case 12..<16: return 1.6
        case 23..<24, 0..<5: return 1.5
        case 5..<8, 19..<23: return 0.6
        default: return 1.0
        }
    }

    static func isZoomiesHour(_ hour: Int) -> Bool { (20..<23).contains(hour) }
}

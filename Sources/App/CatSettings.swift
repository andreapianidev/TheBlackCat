import Foundation
import Combine

enum CatSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var scale: CGFloat {
        switch self {
        case .small: return 0.75
        case .medium: return 1.0
        case .large: return 1.4
        }
    }
    var label: String {
        switch self {
        case .small: return "Gattino"
        case .medium: return "Gatto"
        case .large: return "Gattone"
        }
    }
}

/// What the person chose. Every sense is off until they switch it on.
final class CatSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var name: String { didSet { d.set(name, forKey: "name") } }
    @Published var size: CatSize { didSet { d.set(size.rawValue, forKey: "size") } }
    @Published var sound: Bool { didSet { d.set(sound, forKey: "sound") } }
    @Published var volume: Double { didSet { d.set(volume, forKey: "volume") } }
    @Published var sight: Bool { didSet { d.set(sight, forKey: "sight") } }
    @Published var hearing: Bool { didSet { d.set(hearing, forKey: "hearing") } }
    @Published var screenEyes: Bool { didSet { d.set(screenEyes, forKey: "screenEyes") } }
    @Published var thoughts: Bool { didSet { d.set(thoughts, forKey: "thoughts") } }
    @Published var aiThoughts: Bool { didSet { d.set(aiThoughts, forKey: "aiThoughts") } }
    @Published var weather: Bool { didSet { d.set(weather, forKey: "weather") } }
    @Published var calendar: Bool { didSet { d.set(calendar, forKey: "calendar") } }
    @Published var notifications: Bool { didSet { d.set(notifications, forKey: "notifications") } }
    @Published var mischief: Bool { didSet { d.set(mischief, forKey: "mischief") } }
    @Published var paused: Bool { didSet { d.set(paused, forKey: "paused") } }
    @Published var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }

    init() {
        d.register(defaults: ["name": "Nerone", "size": CatSize.medium.rawValue, "sound": true, "volume": 0.5,
                              "thoughts": true, "aiThoughts": true])
        name = d.string(forKey: "name") ?? "Nerone"
        size = CatSize(rawValue: d.string(forKey: "size") ?? "") ?? .medium
        sound = d.bool(forKey: "sound")
        volume = d.double(forKey: "volume")
        sight = d.bool(forKey: "sight")
        hearing = d.bool(forKey: "hearing")
        screenEyes = d.bool(forKey: "screenEyes")
        thoughts = d.bool(forKey: "thoughts")
        aiThoughts = d.bool(forKey: "aiThoughts")
        weather = d.bool(forKey: "weather")
        calendar = d.bool(forKey: "calendar")
        notifications = d.bool(forKey: "notifications")
        mischief = d.bool(forKey: "mischief")
        paused = d.bool(forKey: "paused")
        onboarded = d.bool(forKey: "onboarded")
    }
}

/// The cat's memory between launches.
struct CatMemory: Codable {
    var needs = Needs()
    var favorites: [String: Double] = [:]
    var lastSeen = Date()
    var timesFed = 0
    var born = Date()

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TheBlackCat", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cat.json")
    }

    static func load() -> CatMemory {
        guard let data = try? Data(contentsOf: url), let m = try? JSONDecoder().decode(CatMemory.self, from: data) else {
            return CatMemory()
        }
        return m
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.url, options: .atomic) }
    }
}

import Foundation

/// What the app, the widget and the Shortcuts actions share through the App Group.
enum SharedStore {
    static let group = "ERAK83QBBM.app.andreapiani.theblackcat"
    static let commandNotification = "app.andreapiani.theblackcat.command"

    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    enum Command: String, Codable {
        case feed, call, sleep, wake, find
    }

    /// A small picture of the cat for the widget.
    struct Snapshot: Codable {
        var name: String
        var status: String
        var sleeping: Bool
        var fullness: Double
        var energy: Double
        var happiness: Double
        var playfulness: Double
        var updated: Date

        static let placeholder = Snapshot(name: "Nerone", status: "Si gode il desktop", sleeping: false,
                                          fullness: 0.7, energy: 0.8, happiness: 0.6, playfulness: 0.5, updated: .now)
    }

    static func save(_ snapshot: Snapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: "snapshot") }
    }

    static func loadSnapshot() -> Snapshot? {
        guard let data = defaults.data(forKey: "snapshot") else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Queues a command for the running app and wakes it with a Darwin notification.
    static func send(_ command: Command) {
        var list = defaults.stringArray(forKey: "commands") ?? []
        list.append(command.rawValue)
        defaults.set(list, forKey: "commands")
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(commandNotification as CFString), nil, nil, true)
    }

    static func drainCommands() -> [Command] {
        let list = defaults.stringArray(forKey: "commands") ?? []
        defaults.removeObject(forKey: "commands")
        return list.compactMap(Command.init(rawValue:))
    }
}

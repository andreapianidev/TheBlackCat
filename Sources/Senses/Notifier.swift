import UserNotifications

/// System notifications, only for things worth leaving the desktop for.
final class Notifier {
    private var lastHungry = Date.distantPast

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func hungry(name: String) {
        guard Date().timeIntervalSince(lastHungry) > 2 * 3600 else { return }
        lastHungry = Date()
        let c = UNMutableNotificationContent()
        c.title = "\(name) ha fame"
        c.body = ["Ti fissa. Con insistenza.", "La ciotola è vuota da un po'. Lo dice lui.",
                  "Si è seduto davanti alla ciotola. Aspetta."].randomElement() ?? ""
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "hungry", content: c, trigger: nil))
    }
}

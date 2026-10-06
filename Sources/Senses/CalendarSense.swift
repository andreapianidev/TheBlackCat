import EventKit
import Foundation

/// Looks at the calendar once a minute and warns about what starts within five minutes.
@MainActor
final class CalendarSense {
    var onMeeting: ((String, Int) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var announced: Set<String> = []

    func start() {
        guard timer == nil else { return }
        Task { @MainActor [weak self] in
            guard let self, (try? await self.store.requestFullAccessToEvents()) == true else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            self.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let now = Date()
        let pred = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(6 * 60), calendars: nil)
        for e in store.events(matching: pred) where !e.isAllDay && e.startDate > now {
            let key = (e.eventIdentifier ?? e.title ?? "") + "\(e.startDate.timeIntervalSince1970)"
            guard !announced.contains(key) else { continue }
            let minutes = Int((e.startDate.timeIntervalSince(now) / 60).rounded(.up))
            guard minutes <= 5 else { continue }
            announced.insert(key)
            onMeeting?(e.title ?? "una riunione", max(1, minutes))
        }
    }
}

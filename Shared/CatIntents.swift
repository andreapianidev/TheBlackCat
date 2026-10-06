import AppIntents

/// Actions for Shortcuts, Siri, Spotlight and the widget button.
/// They only queue a command: the running cat decides how to react.
struct FeedCatIntent: AppIntent {
    static var title: LocalizedStringResource = "Dai da mangiare al gatto"
    static var description = IntentDescription("Riempie la ciotola sul desktop. Il gatto arriva di corsa, quasi sempre.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedStore.send(.feed)
        return .result(dialog: "Ciotola piena.")
    }
}

struct CallCatIntent: AppIntent {
    static var title: LocalizedStringResource = "Chiama il gatto"
    static var description = IntentDescription("Il gatto viene verso il puntatore, se ne ha voglia.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedStore.send(.call)
        return .result(dialog: "Psps psps.")
    }
}

struct SleepCatIntent: AppIntent {
    static var title: LocalizedStringResource = "Metti a dormire il gatto"
    static var description = IntentDescription("Il gatto si cerca un posto e si acciambella.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedStore.send(.sleep)
        return .result(dialog: "Nanna.")
    }
}

struct CatStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Come sta il gatto"
    static var description = IntentDescription("Ti dice cosa sta facendo il gatto e come si sente.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = SharedStore.loadSnapshot() ?? .placeholder
        let mood = s.fullness < 0.3 ? "Ha fame." : (s.happiness > 0.6 ? "È di buon umore." : "Ha l'aria di chi aspetta coccole.")
        return .result(dialog: "\(s.name): \(s.status.lowercased()). \(mood)")
    }
}

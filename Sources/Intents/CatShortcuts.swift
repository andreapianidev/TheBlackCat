import AppIntents

struct CatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FeedCatIntent(),
                    phrases: ["Dai da mangiare a \(.applicationName)", "Pappa per \(.applicationName)"],
                    shortTitle: "Pappa", systemImageName: "fish")
        AppShortcut(intent: CallCatIntent(),
                    phrases: ["Chiama \(.applicationName)", "Vieni qui \(.applicationName)"],
                    shortTitle: "Chiamalo", systemImageName: "pawprint")
        AppShortcut(intent: SurpriseCatIntent(),
                    phrases: ["Sorpresa per \(.applicationName)", "Fai succedere qualcosa a \(.applicationName)"],
                    shortTitle: "Sorpresa", systemImageName: "sparkles")
        AppShortcut(intent: SleepCatIntent(),
                    phrases: ["Metti a nanna \(.applicationName)"],
                    shortTitle: "Nanna", systemImageName: "moon.zzz")
        AppShortcut(intent: CatStatusIntent(),
                    phrases: ["Come sta \(.applicationName)"],
                    shortTitle: "Come sta", systemImageName: "heart")
    }
}

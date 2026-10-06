import AppIntents
import SwiftUI
import WidgetKit

struct CatEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedStore.Snapshot
}

struct CatProvider: TimelineProvider {
    func placeholder(in context: Context) -> CatEntry { CatEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (CatEntry) -> Void) {
        completion(CatEntry(date: .now, snapshot: SharedStore.loadSnapshot() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CatEntry>) -> Void) {
        let entry = CatEntry(date: .now, snapshot: SharedStore.loadSnapshot() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct CatWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CatEntry

    var body: some View {
        let s = entry.snapshot
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let img = CatRig.image(s.sleeping ? .sleep : .sit, size: 160, glow: 1) {
                    Image(decorative: img, scale: 2)
                        .resizable()
                        .scaledToFit()
                        .frame(height: family == .systemSmall ? 62 : 74)
                }
                Text(s.name).font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                Text(s.status).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                if family == .systemSmall {
                    Button(intent: FeedCatIntent()) { Label("Pappa", systemImage: "fish.fill") }
                        .font(.caption.bold())
                        .tint(.orange)
                }
            }
            if family != .systemSmall {
                VStack(alignment: .leading, spacing: 7) {
                    meter("Pancia", s.fullness, .orange)
                    meter("Energia", s.energy, .green)
                    meter("Umore", s.happiness, .pink)
                    meter("Gioco", s.playfulness, .blue)
                    Button(intent: FeedCatIntent()) { Label("Dai la pappa", systemImage: "fish.fill") }
                        .font(.caption.bold())
                        .tint(.orange)
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.09, blue: 0.29), Color(red: 0.06, green: 0.08, blue: 0.2)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func meter(_ label: String, _ v: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
            ProgressView(value: min(max(v, 0), 1)).tint(color)
        }
    }
}

struct CatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CatWidget", provider: CatProvider()) { CatWidgetView(entry: $0) }
            .configurationDisplayName("The Black Cat")
            .description("Come sta il gatto, e una ciotola sempre a portata di mano.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CatWidgetBundle: WidgetBundle {
    var body: some Widget { CatWidget() }
}

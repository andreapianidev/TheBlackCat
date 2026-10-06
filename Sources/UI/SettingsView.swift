import AppKit
import ServiceManagement
import SwiftUI

/// Live facts the settings window shows but does not own.
struct CatReadout {
    var status: () -> String
    var needs: () -> Needs
    var aiStatus: () -> String
    var screenAllowed: () -> Bool
    var accessibilityAllowed: () -> Bool
    var weather: () -> String
    var age: () -> String
    var timesFed: () -> Int
}

struct SettingsView: View {
    @ObservedObject var settings: CatSettings
    let readout: CatReadout
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            header
            Section("Il gatto") {
                TextField("Nome", text: $settings.name)
                Picker("Taglia", selection: $settings.size) {
                    ForEach(CatSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Miagolii e fusa", isOn: $settings.sound)
                if settings.sound {
                    Slider(value: $settings.volume, in: 0.1...1) { Text("Volume") }
                }
                Toggle("Pensieri nel fumetto", isOn: $settings.thoughts)
            }
            Section {
                sense("Vista", "camera", $settings.sight,
                      "Con la fotocamera si accorge quando sei davanti al Mac, ti guarda, e se lo saluti con la mano ti risponde. Se te ne vai, va a dormire.")
                sense("Udito", "ear", $settings.hearing,
                      "Con il microfono si spaventa se batti le mani, soffia ai cani, muove la coda a tempo di musica e arriva quando lo chiami per nome. Capisce anche «giù», «pappa», «nanna», «bravo».")
                sense("Occhi sullo schermo", "eye", $settings.screenEyes,
                      "Ogni tanto guarda cosa c'è sullo schermo: se vede un uccellino o un pesce si mette in caccia, se legge «tonno» arriva, se vede un cane soffia.")
                if settings.screenEyes && !readout.screenAllowed() {
                    permissionHint("Serve il permesso di registrazione dello schermo.", "Privacy_ScreenCapture")
                }
                sense("Pensieri con Apple Intelligence", "sparkles", $settings.aiThoughts,
                      "I pensieri li scrive il modello di Apple sul Mac, a partire da quello che succede. Stato: \(readout.aiStatus()).")
                sense("Meteo", "cloud.sun", $settings.weather,
                      "Con la tua posizione approssimativa sa che tempo fa fuori: con la pioggia è malinconico, al sole si stende. \(readout.weather())")
                sense("Calendario", "calendar", $settings.calendar,
                      "Ti avvisa, a modo suo, quando una riunione sta per cominciare.")
                sense("Notifiche", "bell", $settings.notifications,
                      "Ti scrive quando ha fame da troppo tempo.")
                sense("Dispetti", "hand.point.up.left", $settings.mischief,
                      "Ogni tanto spinge una finestra con la zampa. Poco, ma lo fa. Serve il permesso Accessibilità.")
                if settings.mischief && !readout.accessibilityAllowed() {
                    permissionHint("Serve il permesso Accessibilità.", "Privacy_Accessibility")
                }
            } header: {
                Text("I sensi")
            } footer: {
                Text("Tutto quello che vede e sente resta su questo Mac. Niente viene salvato o inviato.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Come sta") {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let n = readout.needs()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(readout.status()).font(.headline)
                        bar("Pancia piena", 1 - n.hunger, .orange)
                        bar("Energia", n.energy, .green)
                        bar("Coccole ricevute", 1 - n.loneliness, .pink)
                        bar("Voglia di giocare", n.boredom, .blue)
                        if n.grudge > 0.2 { bar("Rancore", n.grudge, .red) }
                        Text("Con te da \(readout.age()). Pappe date: \(readout.timesFed()).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Sistema") {
                Toggle("Apri all'accesso", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("Nei Comandi rapidi e in Spotlight trovi «Dai da mangiare al gatto», «Chiama il gatto», «Come sta il gatto». Sulla scrivania puoi aggiungere il widget The Black Cat.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("© 2026 The Black Cat · Andrea Piani · NIE Z2331796-S · Tijarafe, Santa Cruz de Tenerife · Islas Canarias")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let img = CatRig.image(.sit, size: 128, glow: 1) {
                Image(decorative: img, scale: 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.onboarded ? settings.name : "È arrivato un gatto.")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(settings.onboarded
                     ? "Vive sul tuo desktop. Accendi i sensi che vuoi, uno per uno."
                     : "Si chiama \(settings.name), ma puoi cambiargli nome. Cammina sul Dock, salta sulle finestre, dorme dove vuole. Qui sotto decidi cosa può vedere e sentire.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    private func sense(_ title: String, _ icon: String, _ on: Binding<Bool>, _ text: String) -> some View {
        Toggle(isOn: on) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: icon)
                Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionHint(_ text: String, _ pane: String) -> some View {
        HStack {
            Text(text).font(.footnote).foregroundStyle(.orange)
            Spacer()
            Button("Apri Impostazioni") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
    }

    private func bar(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack {
            Text(label).font(.callout).frame(width: 140, alignment: .leading)
            ProgressView(value: min(max(value, 0), 1)).tint(color)
        }
    }
}

final class SettingsWindow {
    private var window: NSWindow?

    func show(settings: CatSettings, readout: CatReadout) {
        if window == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "The Black Cat"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings, readout: readout))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

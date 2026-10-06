import Foundation
import FoundationModels

/// Something the cat can decide to do. The brain turns each one into movements.
@Generable
enum CatIntent: String, CaseIterable {
    case sleep, napOnApp, explore, huntPointer, mischief, askFood, askCuddles
    case groom, loaf, zoomies, chaseTail, scratch, hangFromMenuBar, watchHuman, stretch

    /// How the choice is explained to the model.
    var meaning: String {
        switch self {
        case .sleep: return "dormire dove sei"
        case .napOnApp: return "andare a dormire sopra la finestra di un'app"
        case .explore: return "esplorare saltando sulle finestre, anche quella di un'app precisa"
        case .huntPointer: return "cacciare il puntatore del mouse"
        case .mischief: return "fare un dispetto spingendo una finestra"
        case .askFood: return "chiedere la pappa"
        case .askCuddles: return "chiedere coccole all'umano"
        case .groom: return "lavarti con la lingua"
        case .loaf: return "metterti a pagnotta e osservare"
        case .zoomies: return "fare una corsa matta avanti e indietro"
        case .chaseTail: return "rincorrere la tua coda"
        case .scratch: return "farti le unghie sul bordo di una finestra"
        case .hangFromMenuBar: return "appenderti alla barra dei menu"
        case .watchHuman: return "fissare l'umano"
        case .stretch: return "stiracchiarti"
        }
    }
}

/// One decision: what to do, where, in what mood, and what crosses the cat's mind.
@Generable
struct CatDecision {
    @Guide(description: "Cosa fai adesso")
    var intent: CatIntent
    @Guide(description: "Per napOnApp, explore o mischief: il nome esatto di una delle app elencate. Altrimenti stringa vuota.")
    var app: String
    @Guide(description: "Il tuo umore adesso, una o due parole in italiano")
    var mood: String
    @Guide(description: "Il pensiero che ti passa per la testa, in prima persona, in italiano, al massimo dodici parole, ironico")
    var thought: String
}

/// The cat's character. Every minute or two it looks at the situation (time of day,
/// needs, open apps, what happened lately) and decides what to do next, with the
/// cloud brain chosen in Settings or Apple Intelligence on the Mac. It keeps a short
/// diary, so one decision follows from the previous ones. Without a model the
/// brain's own weighted choices carry on as before.
@MainActor
final class Mind {
    var enabled = true
    var cloud: CloudBrain?
    var name = "Nerone"
    var adjective = "nero"
    private(set) var mood = "tranquillo"

    private var diary: [String] = []
    private var busy = false
    private var nextAt = Date().addingTimeInterval(25)

    private var modelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Writes down something that happened, for the next decisions.
    func note(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        diary.append("\(f.string(from: Date())) \(text)")
        if diary.count > 12 { diary.removeFirst() }
    }

    /// Asks for a decision when it is time. The answer comes back on the main actor.
    func maybeDecide(situation: () -> String, apps: [String], deliver: @escaping (CatDecision) -> Void) {
        guard enabled, !busy, Date() > nextAt else { return }
        let cloud = cloud.flatMap { $0.ready ? $0 : nil }
        guard cloud != nil || modelAvailable else { return }
        busy = true
        nextAt = Date().addingTimeInterval(.random(in: 70...150))
        let prompt = """
        Situazione: \(situation()).
        Il tuo umore finora: \(mood).
        App con finestre aperte: \(apps.isEmpty ? "nessuna" : apps.joined(separator: ", ")).
        Cosa è successo di recente:
        \(diary.isEmpty ? "niente di speciale" : diary.joined(separator: "\n"))
        Cosa fai adesso?
        """
        Task { [weak self] in
            guard let self else { return }
            var decision: CatDecision?
            if let cloud { decision = await self.askCloud(cloud, prompt) }
            if decision == nil, self.modelAvailable { decision = await self.askApple(prompt) }
            self.busy = false
            guard var d = decision else { return }
            if !apps.contains(d.app) { d.app = "" }
            let mood = d.mood.trimmingCharacters(in: .whitespacesAndNewlines)
            if !mood.isEmpty { self.mood = String(mood.prefix(30)) }
            self.note("hai deciso di \(d.intent.meaning)\(d.app.isEmpty ? "" : " (\(d.app))")")
            deliver(d)
        }
    }

    private var instructions: String {
        """
        Sei \(name), un gatto \(adjective) che vive sul desktop di un Mac. Hai un carattere vero: \
        pigro ma curioso, orgoglioso, affettuoso a modo tuo, permaloso, imprevedibile. \
        Decidi cosa fare adesso come un gatto vero: coerente con l'ora, i bisogni, l'umore e \
        quello che è successo prima, senza ripetere sempre la stessa cosa. \
        Scrivi in italiano, mai volgare, niente emoji, niente trattini lunghi.
        """
    }

    private func askApple(_ prompt: String) async -> CatDecision? {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let r = try await session.respond(to: prompt, generating: CatDecision.self,
                                              options: GenerationOptions(temperature: 0.9))
            return r.content
        } catch {
            return nil
        }
    }

    private func askCloud(_ cloud: CloudBrain, _ prompt: String) async -> CatDecision? {
        let menu = CatIntent.allCases.map { "\($0.rawValue): \($0.meaning)" }.joined(separator: "\n")
        let system = instructions + """

        Gesti possibili (usa il nome a sinistra):
        \(menu)
        Rispondi solo con un oggetto JSON con le chiavi "intent", "app", "mood", "thought". \
        "app" è il nome esatto di una delle app elencate, oppure "". \
        "thought" è un pensiero in prima persona, al massimo dodici parole.
        """
        guard let raw = try? await cloud.chat(system: system, user: prompt, maxTokens: 160, json: true) else { return nil }
        var text = raw
        if let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}") { text = String(text[a...b]) }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let i = obj["intent"] as? String, let intent = CatIntent(rawValue: i.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return CatDecision(intent: intent, app: obj["app"] as? String ?? "",
                           mood: obj["mood"] as? String ?? "", thought: obj["thought"] as? String ?? "")
    }
}

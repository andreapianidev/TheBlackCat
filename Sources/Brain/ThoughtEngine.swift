import Foundation
import FoundationModels

/// Gives the cat something to say. Uses Agnes in the cloud when chosen and a key
/// is present, the on device Apple Intelligence model when it is available and
/// allowed, the hand written lines otherwise.
@MainActor
final class ThoughtEngine {
    var useModel = true
    var cloud = false
    var name = "Nerone"
    var adjective = "nero"

    private var lastSaid = Date.distantPast
    private var recent: [String] = []
    private var busy = false

    var modelStatus: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "Attivi, sul Mac"
        case .unavailable(.appleIntelligenceNotEnabled): return "Attiva Apple Intelligence nelle Impostazioni di Sistema"
        case .unavailable(.deviceNotEligible): return "Questo Mac non supporta Apple Intelligence"
        case .unavailable(.modelNotReady): return "Il modello si sta ancora scaricando"
        case .unavailable: return "Non disponibili"
        }
    }

    var cloudStatus: String {
        AgnesKey.load() != nil ? "Agnes: chiave presente" : "Agnes: manca la chiave"
    }

    private var cloudReady: Bool { cloud && AgnesKey.load() != nil }

    var modelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Topics where a quick canned line beats waiting for the model.
    private func isReflex(_ t: ThoughtTopic) -> Bool {
        switch t {
        case .thrown, .clap, .fed, .petted, .scolded, .praised, .ignoredCall, .dog, .zoomies, .mischief: return true
        default: return false
        }
    }

    func think(_ topic: ThoughtTopic, context: String, force: Bool = false, deliver: @escaping (String) -> Void) {
        guard force || Date().timeIntervalSince(lastSaid) > 20 else { return }
        lastSaid = Date()
        let canned = pick(topic)
        guard cloudReady || (useModel && modelAvailable), !busy, !isReflex(topic) else { deliver(canned); return }
        busy = true
        Task { [weak self] in
            let text = await self?.generate(topic, context: context)
            guard let self else { return }
            self.busy = false
            let line = text ?? canned
            self.remember(line)
            deliver(line)
        }
    }

    private func pick(_ topic: ThoughtTopic) -> String {
        let lines = ThoughtBank.lines(for: topic, name: name)
        let fresh = lines.filter { !recent.contains($0) }
        let line = (fresh.isEmpty ? lines : fresh).randomElement() ?? "Mrrp."
        remember(line)
        return line
    }

    private func remember(_ line: String) {
        recent.append(line)
        if recent.count > 14 { recent.removeFirst() }
    }

    private func generate(_ topic: ThoughtTopic, context: String) async -> String? {
        let instructions = """
        Sei \(name), un gatto \(adjective) che vive sul desktop di un Mac. Scrivi un solo pensiero, \
        in prima persona, in italiano, al massimo dodici parole. Tono ironico, altezzoso, \
        affettuoso sotto sotto. Mai volgare, mai cattivo. Niente emoji, niente virgolette, \
        niente trattini lunghi. Solo il pensiero, nient'altro.
        """
        let examples = ThoughtBank.lines(for: topic, name: name).prefix(3).joined(separator: " / ")
        let prompt = """
        Situazione: \(topic.situation).
        Contesto: \(context).
        Esempi di tono: \(examples)
        Pensiero nuovo:
        """
        if cloudReady,
           let raw = try? await AgnesClient.chat(system: instructions, user: prompt),
           let line = ThoughtBank.clean(raw) {
            return line
        }
        guard useModel, modelAvailable else { return nil }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let r = try await session.respond(to: prompt, options: GenerationOptions(temperature: 1.0, maximumResponseTokens: 50))
            return ThoughtBank.clean(r.content)
        } catch {
            return nil
        }
    }
}

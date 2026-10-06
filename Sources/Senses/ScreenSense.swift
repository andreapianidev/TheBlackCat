import AppKit
import ScreenCaptureKit
import Vision

/// Now and then the cat looks at the screen: animals, birds and fish, and a few
/// words it cares about. The snapshot is small, analysed with Vision and dropped.
@MainActor
final class ScreenSense {
    var onEvent: ((CatEvent) -> Void)?
    var catPosition: () -> CGPoint = { .zero }
    var shouldLook: () -> Bool = { true }
    /// When on, the reduced snapshot is sent to Agnes, which answers with a thought and what it saw.
    var agnesVision = false
    var onThought: ((String) -> Void)?

    private var timer: Timer?
    private var busy = false
    private var seenWords: [String: Date] = [:]
    private var lastPrey = Date.distantPast
    private var lastAgnes = Date.distantPast

    nonisolated private static let friendly: [String] = ["tonno", "pesce", "pesci", "gatto", "gatti", "gattino", "topo", "topi",
                                             "uccello", "uccellino", "croccantini", "crocchette", "pappa", "latte",
                                             "miao", "salmone", "prosciutto", "tuna", "fish", "mouse"]
    nonisolated private static let scary: [String] = ["cane", "cani", "aspirapolvere", "veterinario", "bagnetto", "dog", "vacuum"]

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func start() {
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 40, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.look() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func look() async {
        guard !busy, CGPreflightScreenCaptureAccess(), shouldLook() else { return }
        busy = true
        defer { busy = false }
        let pos = catPosition()
        guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(pos) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == number.uint32Value })
        else { return }
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = max(display.width / 2, 320)
        config.height = max(display.height / 2, 200)
        config.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return }
        let frame = screen.frame
        if agnesVision, AgnesKey.load() != nil, Date().timeIntervalSince(lastAgnes) >= 150 {
            lastAgnes = Date()
            if await askAgnes(image, frame: frame) { return }
        }
        let found = await Task.detached(priority: .utility) { Self.analyze(image) }.value
        for f in found {
            let p = CGPoint(x: frame.minX + f.box.midX * frame.width, y: frame.minY + f.box.midY * frame.height)
            switch f.kind {
            case .dog: onEvent?(.sawAnimal(dog: true, at: p)); return
            case .cat: onEvent?(.sawAnimal(dog: false, at: p)); return
            case .prey:
                guard Date().timeIntervalSince(lastPrey) > 300 else { continue }
                lastPrey = Date()
                onEvent?(.sawPrey(at: p)); return
            case .word(let w):
                if let last = seenWords[w], Date().timeIntervalSince(last) < 600 { continue }
                seenWords[w] = Date()
                onEvent?(Self.scary.contains(w) ? .sawAnimal(dog: true, at: p) : .sawWord(w, at: p))
                return
            }
        }
    }

    private static let agnesSystem = """
    Sei un gatto nero che vive sul desktop di un Mac e guarda lo schermo. Rispondi SOLO con un oggetto JSON, \
    senza testo prima o dopo, in questa forma: \
    {"pensiero": "<frase in prima persona di un gatto, in italiano, massimo 12 parole, ironica, mai volgare>", \
    "cosa": "uccello|pesce|topo|cibo|cane|gatto|niente", "x": 0.5, "y": 0.5}. \
    "cosa" è la cosa più interessante per un gatto che vedi nell'immagine, "niente" se non c'è nulla. \
    x e y vanno da 0 a 1 e sono la posizione della cosa nell'immagine, con l'origine in alto a sinistra. \
    Niente emoji, niente trattini lunghi.
    """

    /// Returns true when Agnes answered and the reply was usable.
    private func askAgnes(_ image: CGImage, frame: CGRect) async -> Bool {
        guard let raw = try? await AgnesClient.chat(system: Self.agnesSystem,
                                                     user: "Ecco lo schermo. Cosa vedi?",
                                                     image: image, maxTokens: 160),
              let reply = Self.parseAgnes(raw)
        else { return false }
        if let thought = reply.thought, let line = ThoughtBank.clean(thought) { onThought?(line) }
        let p = CGPoint(x: frame.minX + reply.x * frame.width, y: frame.maxY - reply.y * frame.height)
        switch reply.what {
        case "uccello", "pesce", "topo":
            if Date().timeIntervalSince(lastPrey) > 300 {
                lastPrey = Date()
                onEvent?(.sawPrey(at: p))
            }
        case "cane": onEvent?(.sawAnimal(dog: true, at: p))
        case "gatto": onEvent?(.sawAnimal(dog: false, at: p))
        case "cibo": onEvent?(.sawWord("pappa", at: p))
        default: break
        }
        return true
    }

    struct AgnesReply { var thought: String?; var what: String; var x: CGFloat; var y: CGFloat }

    /// Tolerant parse: strips code fences and anything around the outer braces.
    nonisolated static func parseAgnes(_ raw: String) -> AgnesReply? {
        var s = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}"), a < b { s = String(s[a...b]) }
        guard let data = s.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        func number(_ k: String) -> CGFloat {
            let v = (obj[k] as? NSNumber)?.doubleValue ?? Double(obj[k] as? String ?? "") ?? 0.5
            return CGFloat(min(max(v, 0), 1))
        }
        let thought = (obj["pensiero"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let what = ((obj["cosa"] as? String) ?? "niente").lowercased().trimmingCharacters(in: .whitespaces)
        return AgnesReply(thought: thought, what: what, x: number("x"), y: number("y"))
    }

    enum Kind { case dog, cat, prey, word(String) }
    struct Finding { var kind: Kind; var box: CGRect }

    nonisolated static func analyze(_ image: CGImage) -> [Finding] {
        let animals = VNRecognizeAnimalsRequest()
        let classify = VNClassifyImageRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        text.recognitionLanguages = ["it-IT", "en-US"]
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([animals, classify, text])

        var out: [Finding] = []
        for a in animals.results ?? [] {
            guard let label = a.labels.first, label.confidence > 0.6 else { continue }
            out.append(Finding(kind: label.identifier.lowercased() == "dog" ? .dog : .cat, box: a.boundingBox))
        }
        let prey = (classify.results ?? []).contains { c in
            c.confidence > 0.4 && ["bird", "fish", "parrot", "owl", "songbird", "goldfish", "butterfly"].contains { c.identifier.lowercased().contains($0) }
        }
        if prey { out.append(Finding(kind: .prey, box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))) }
        let words = Set(friendly + scary)
        for obs in text.results ?? [] {
            guard let s = obs.topCandidates(1).first?.string.lowercased() else { continue }
            let tokens = s.components(separatedBy: CharacterSet.letters.inverted)
            if let w = tokens.first(where: { words.contains($0) }) {
                out.append(Finding(kind: .word(w), box: obs.boundingBox))
            }
        }
        return out
    }
}

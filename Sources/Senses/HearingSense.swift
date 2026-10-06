import AVFoundation
import SoundAnalysis
import Speech

/// The microphone: sounds through SoundAnalysis, words through on device speech
/// recognition in Italian. Audio is analysed as it streams and never kept.
final class HearingSense: NSObject, SNResultsObserving {
    var onEvent: ((CatEvent) -> Void)?
    var name = "Nerone"

    private let engine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "app.andreapiani.theblackcat.hearing")
    private var recognizer: SFSpeechRecognizer?
    private let requestLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var taskStarted = Date()
    private var restartTimer: Timer?
    private var processedWords = 0
    private var lastFired: [String: Date] = [:]
    private var lastMusic = Date.distantPast
    private var musicOn = false
    private var mutedUntil = Date.distantPast
    private var running = false
    /// Speech recognition only listens while SoundAnalysis hears someone talking.
    private var speechOpenUntil = Date.distantPast
    private var preroll: [AVAudioPCMBuffer] = []

    /// Ignore what we hear for a moment, so the cat does not react to its own meow.
    func mute(for seconds: TimeInterval) { mutedUntil = Date().addingTimeInterval(seconds) }

    func start() {
        guard !running else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] ok in
            guard ok else { return }
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { self?.begin(speech: status == .authorized) }
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        restartTimer?.invalidate()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        task?.cancel()
        requestLock.withLock { request = nil }
        analyzer = nil
        if musicOn { musicOn = false; onEvent?(.music(false)) }
    }

    private func begin(speech: Bool) {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        running = true

        let analyzer = SNAudioStreamAnalyzer(format: format)
        if let req = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            req.overlapFactor = 0
            try? analyzer.add(req, withObserver: self)
        }
        self.analyzer = analyzer

        if speech {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
            startRecognition()
            restartTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                guard let self, Date().timeIntervalSince(self.taskStarted) > 50 else { return }
                self.startRecognition()
            }
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
            guard let self else { return }
            self.analysisQueue.async { self.analyzer?.analyze(buffer, atAudioFramePosition: when.sampleTime) }
            self.requestLock.withLock {
                guard self.request != nil else { return }
                if Date() < self.speechOpenUntil {
                    for b in self.preroll { self.request?.append(b) }
                    self.preroll.removeAll()
                    self.request?.append(buffer)
                } else if let copy = Self.copy(buffer) {
                    // Keep about a second, so the first word ("Nerone!") is not lost.
                    self.preroll.append(copy)
                    if self.preroll.count > 12 { self.preroll.removeFirst() }
                }
            }
        }
        try? engine.start()
    }

    private static func copy(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let c = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength),
              let src = b.floatChannelData, let dst = c.floatChannelData else { return nil }
        c.frameLength = b.frameLength
        for ch in 0..<Int(b.format.channelCount) {
            dst[ch].update(from: src[ch], count: Int(b.frameLength))
        }
        return c
    }

    private func startRecognition() {
        task?.cancel()
        requestLock.withLock { request?.endAudio(); request = nil }
        guard running, let rec = recognizer, rec.isAvailable else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.contextualStrings = [name, "micio", "pappa", "giù", "vieni"]
        requestLock.withLock { request = req }
        processedWords = 0
        taskStarted = Date()
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let r = result {
                let words = r.bestTranscription.segments.map { $0.substring }
                DispatchQueue.main.async { self.heard(words) }
            }
            if error != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, self.running, Date().timeIntervalSince(self.taskStarted) > 2 else { return }
                    self.startRecognition()
                }
            }
        }
    }

    private func heard(_ words: [String]) {
        guard words.count > processedWords else { processedWords = words.count; return }
        let fresh = words[processedWords...].map {
            $0.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        }
        processedWords = words.count
        guard Date() > mutedUntil else { return }
        let me = name.lowercased()
        for w in fresh {
            switch w {
            case me, "micio", "miciomicio", "gattino", "psps", "pss", "pspsps", "vieni": fire("call", .called(strong: false))
            case "giù", "giu", "scendi": fire("down", .getDown)
            case "pappa", "crocchette", "croccantini", "mangiare", "fame": fire("food", .foodWord)
            case "bravo", "bravissimo", "bello", "bellissimo", "amore", "tesoro": fire("praise", .praised)
            case "basta", "cattivo", "smettila": fire("scold", .scolded)
            case "nanna", "dormi": fire("sleep", .sleepCommand)
            case "salta": fire("jump", .jumpCommand)
            case "cane", "cagnolino": fire("dogword", .dog)
            default: break
            }
        }
    }

    private func fire(_ key: String, _ e: CatEvent, every seconds: TimeInterval = 4) {
        if let last = lastFired[key], Date().timeIntervalSince(last) < seconds { return }
        lastFired[key] = Date()
        onEvent?(e)
    }

    // MARK: SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        let top = r.classifications.prefix(3).filter { $0.confidence > 0.55 }.map { $0.identifier.lowercased() }
        if r.classifications.prefix(3).contains(where: { $0.identifier.lowercased().contains("speech") && $0.confidence > 0.4 }) {
            requestLock.withLock { speechOpenUntil = Date().addingTimeInterval(4) }
        }
        DispatchQueue.main.async { self.classified(top) }
    }

    private func classified(_ ids: [String]) {
        guard Date() > mutedUntil else { return }
        for id in ids {
            if id.contains("dog") || id.contains("bark") || id.contains("howl") || id.contains("bow_wow") {
                fire("dog", .dog, every: 10)
            } else if id.contains("clap") || id.contains("slam") || id.contains("bang") || id.contains("knock")
                        || id.contains("crash") || id.contains("glass") || id.contains("firework") || id.contains("thump") {
                fire("loud", .loudNoise, every: 5)
            } else if id.contains("whistl") {
                fire("whistle", .whistle, every: 6)
            } else if id.contains("meow") || id.contains("purr") || id == "cat" || id.contains("cat_") {
                fire("cat", .otherCat, every: 12)
            } else if id.contains("music") || id.contains("singing") || id.contains("guitar") || id.contains("piano")
                        || id.contains("drum") {
                lastMusic = Date()
                if !musicOn { musicOn = true; onEvent?(.music(true)) }
            }
        }
        if musicOn && Date().timeIntervalSince(lastMusic) > 20 {
            musicOn = false
            onEvent?(.music(false))
        }
    }
}

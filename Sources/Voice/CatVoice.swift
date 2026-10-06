import AVFoundation
import os

/// The cat's voice, synthesised on the fly: no audio files.
/// Meows are a harmonic source shaped by two moving formants ("i-a-u"),
/// the purr is low noise pulsed about 26 times a second, the hiss is filtered noise.
final class CatVoice {
    var enabled = true
    var volume: Float = 0.5

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let state = OSAllocatedUnfairLock(initialState: Synth())
    private var idleTimer: Timer?
    private var purring = false

    func play(_ s: CatSound) {
        guard enabled else { return }
        startIfNeeded()
        state.withLock { $0.add(s) }
        scheduleStop()
    }

    func purr(_ on: Bool) {
        guard on != purring else { return }
        purring = on
        if on && enabled { startIfNeeded() }
        state.withLock { $0.purrTarget = on && self.enabled ? 1 : 0 }
        scheduleStop()
    }

    private func startIfNeeded() {
        if engine.isRunning { return }
        if source == nil {
            var rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            if rate <= 0 { rate = 48000 }
            let sampleRate = rate
            state.withLock { $0.rate = sampleRate }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
            let lock = state
            let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, abl -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(abl)
                let gain = self?.volume ?? 0.5
                lock.withLock { synth in
                    for buffer in buffers {
                        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        for i in 0..<Int(frameCount) { data[i] = synth.next() * gain * 0.6 }
                    }
                }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
        }
        try? engine.start()
    }

    /// Switches the engine off after a while of silence, to spare the battery.
    private func scheduleStop() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            guard let self, !self.purring else { return }
            let quiet = self.state.withLock { $0.voices.isEmpty && $0.purrLevel < 0.01 }
            if quiet { self.engine.pause() } else { self.scheduleStop() }
        }
    }
}

// MARK: - Synthesis

private struct Biquad {
    var b0: Float = 0, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    mutating func bandpass(_ f: Double, q: Double, rate: Double) {
        let w = 2 * Double.pi * min(f, rate * 0.45) / rate
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        b0 = Float(alpha / a0); b1 = 0; b2 = Float(-alpha / a0)
        a1 = Float(-2 * cos(w) / a0); a2 = Float((1 - alpha) / a0)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

private struct Voice {
    var sound: CatSound
    var t: Double = 0
    var duration: Double
    var base: Double
    var phase: Double = 0
    var f1 = Biquad()
    var f2 = Biquad()
    var counter = 0
}

private struct Synth {
    var rate: Double = 48000
    var voices: [Voice] = []
    var purrTarget: Float = 0
    var purrLevel: Float = 0
    var purrT: Double = 0
    var purrLP: Float = 0
    var seed: UInt32 = 0x9E3779B9

    mutating func noise() -> Float {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    mutating func add(_ s: CatSound) {
        let v: Voice
        switch s {
        case .meow: v = Voice(sound: s, duration: .random(in: 0.55...0.75), base: .random(in: 480...600))
        case .meowLong: v = Voice(sound: s, duration: 1.25, base: 520)
        case .demand: v = Voice(sound: s, duration: 0.9, base: 640)
        case .trill: v = Voice(sound: s, duration: 0.38, base: 430)
        case .hiss: v = Voice(sound: s, duration: 0.95, base: 0)
        case .crunch: v = Voice(sound: s, duration: 0.12, base: 0)
        case .chatter: v = Voice(sound: s, duration: 0.6, base: 900)
        case .bark: v = Voice(sound: s, duration: 0.24, base: .random(in: 480...560))
        case .chirp: v = Voice(sound: s, duration: 0.36, base: 4300)
        case .squeak: v = Voice(sound: s, duration: 0.13, base: 2900)
        }
        if voices.count < 6 { voices.append(v) }
    }

    mutating func next() -> Float {
        let dt = 1 / rate
        var out: Float = 0

        var i = 0
        while i < voices.count {
            var v = voices[i]
            let u = v.t / v.duration
            var s: Float = 0
            switch v.sound {
            case .meow, .meowLong, .demand, .trill, .chatter:
                var f0: Double
                var env = min(1, v.t / 0.04) * min(1, (v.duration - v.t) / 0.22)
                switch v.sound {
                case .trill:
                    f0 = v.base * (0.9 + 0.45 * u)
                    if u < 0.65 { env *= 0.55 + 0.45 * sin(2 * .pi * 30 * v.t) }
                case .chatter:
                    f0 = v.base
                    env *= sin(2 * .pi * 11 * v.t) > 0.3 ? 1 : 0
                default:
                    f0 = v.base * (0.82 + 0.5 * sin(.pi * pow(u, 0.8)))
                    f0 *= 1 + 0.012 * sin(2 * .pi * 6 * v.t)
                }
                v.phase += f0 * dt
                if v.phase > 1 { v.phase -= 1 }
                var src: Double = 0
                let harmonics = v.sound == .demand ? 12 : 9
                for k in 1...harmonics { src += sin(2 * .pi * Double(k) * v.phase) / Double(k) }
                if v.counter % 32 == 0 {
                    let f1 = 380 + 560 * sin(.pi * u)
                    let f2 = 2400 - 1500 * u
                    v.f1.bandpass(f1, q: 4, rate: rate)
                    v.f2.bandpass(f2, q: 6, rate: rate)
                }
                v.counter += 1
                let x = Float(src * 0.5) + noise() * 0.04
                s = (v.f1.process(x) * 1.6 + v.f2.process(x) * 1.0) * Float(env)
                if v.sound == .demand { s *= 1.25 }
            case .bark:
                // A short harsh "wuf": falling pitch, rich harmonics, a breath of noise.
                let f0 = v.base * (1 - 0.45 * u)
                v.phase += f0 * dt
                if v.phase > 1 { v.phase -= 1 }
                var src: Double = 0
                for k in 1...14 { src += sin(2 * .pi * Double(k) * v.phase) / Double(k) }
                if v.counter % 32 == 0 {
                    v.f1.bandpass(750, q: 3, rate: rate)
                    v.f2.bandpass(1350, q: 4, rate: rate)
                }
                v.counter += 1
                let env = min(1, v.t / 0.01) * exp(-7 * v.t)
                let x = Float(src * 0.5) + noise() * 0.25
                s = (v.f1.process(x) * 1.8 + v.f2.process(x)) * Float(env) * 1.3
            case .chirp, .squeak:
                // Bird pips and mouse squeaks: quick upward sine sweeps.
                let pips = v.sound == .chirp ? 3.0 : 1.0
                let seg = v.duration / pips
                let local = v.t.truncatingRemainder(dividingBy: seg)
                let on = local < seg * 0.7
                let f = v.base * (1 + 0.25 * local / seg)
                v.phase += f * dt
                if v.phase > 1 { v.phase -= 1 }
                let env = on ? sin(.pi * min(1, local / (seg * 0.7))) : 0
                s = Float(sin(2 * .pi * v.phase) * env * 0.35)
            case .hiss:
                if v.counter == 0 { v.f1.bandpass(5200, q: 0.7, rate: rate) }
                v.counter += 1
                let env = min(1, v.t / 0.03) * exp(-2.4 * v.t)
                s = v.f1.process(noise()) * Float(env) * 1.4
            case .crunch:
                if v.counter == 0 { v.f1.bandpass(2600, q: 1.2, rate: rate) }
                v.counter += 1
                let click = (v.t.truncatingRemainder(dividingBy: 0.03) < 0.006) ? 1.0 : 0.0
                s = v.f1.process(noise()) * Float(click * exp(-8 * v.t)) * 1.2
            }
            out += s
            v.t += dt
            if v.t >= v.duration {
                voices.remove(at: i)
            } else {
                voices[i] = v
                i += 1
            }
        }

        // Purr.
        purrLevel += (purrTarget - purrLevel) * 0.00008
        if purrLevel > 0.001 {
            purrT += dt
            let breath = 0.62 + 0.38 * (sin(2 * .pi * purrT / 2.6) * 0.5 + 0.5)
            let rateHz = 24 + 3 * sin(2 * .pi * purrT / 2.6)
            let pulse = pow(max(0, sin(2 * .pi * rateHz * purrT)), 3)
            purrLP += (noise() - purrLP) * 0.02
            out += purrLP * Float(pulse * breath) * 2.4 * purrLevel
        }
        return max(-1, min(1, out))
    }
}

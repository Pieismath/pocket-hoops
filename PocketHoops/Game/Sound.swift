import AVFoundation
import UIKit

/// Every sound effect is synthesised at launch (no audio assets): chiptune blips,
/// a metallic rim clank, a noise swish, the end buzzer.
final class Sound {
    static let shared = Sound()

    enum Effect: CaseIterable {
        case shoot, rim, board, swish, score, fire, buzzer, tick, bounce, stage, lifeLost, ticket, tap, fizzle
    }

    var enabled = true
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var next = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.8
        for e in Effect.allCases { buffers[e] = synth(e) }
    }

    func start() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            players.forEach { $0.play() }
            started = true
        } catch {
            started = false
        }
    }

    func play(_ e: Effect, volume: Float = 1) {
        guard enabled else { return }
        if !started || !engine.isRunning { started = false; start() }
        guard started, let buf = buffers[e] else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.volume = volume
        p.scheduleBuffer(buf, at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
    }

    // MARK: Synthesis

    private func synth(_ e: Effect) -> AVAudioPCMBuffer {
        let sr = 44_100.0
        func buffer(_ seconds: Double, _ f: (Double) -> Double) -> AVAudioPCMBuffer {
            let n = AVAudioFrameCount(seconds * sr)
            let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
            b.frameLength = n
            let ch = b.floatChannelData![0]
            for i in 0..<Int(n) { ch[i] = Float(max(-1, min(1, f(Double(i) / sr)))) }
            return b
        }
        func square(_ t: Double, _ hz: Double) -> Double { sin(2 * .pi * hz * t) >= 0 ? 1 : -1 }
        func env(_ t: Double, _ attack: Double, _ decay: Double) -> Double {
            t < attack ? t / attack : exp(-(t - attack) / decay)
        }
        var seed: UInt64 = 0x1234_5678
        func noise() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 20_000) / 10_000 - 1
        }
        /// Sequence of square-wave notes (arcade jingle).
        func notes(_ ns: [(Double, Double)], vol: Double = 0.22) -> AVAudioPCMBuffer {
            let total = ns.reduce(0) { $0 + $1.1 }
            return buffer(total + 0.05) { t in
                var acc = 0.0
                for (hz, dur) in ns {
                    if t < acc + dur {
                        let lt = t - acc
                        return square(t, hz) * vol * min(1, lt / 0.004) * max(0, 1 - lt / (dur * 1.1))
                    }
                    acc += dur
                }
                return 0
            }
        }

        switch e {
        case .shoot:
            var lp = 0.0
            return buffer(0.16) { t in
                lp += (noise() - lp) * (0.08 + t * 1.5)
                return lp * 0.9 * env(t, 0.02, 0.05)
            }
        case .rim:
            return buffer(0.45) { t in
                let partials = [(523.0, 1.0), (1_307.0, 0.6), (2_210.0, 0.4), (3_150.0, 0.25)]
                let tone = partials.reduce(0) { $0 + sin(2 * .pi * $1.0 * t) * $1.1 * exp(-t * (6 + $1.0 / 500)) }
                return tone * 0.32 + noise() * 0.25 * exp(-t * 60)
            }
        case .board:
            var lp = 0.0
            return buffer(0.2) { t in
                lp += (noise() - lp) * 0.15
                return (sin(2 * .pi * 140 * t) * 0.6 + lp * 0.8) * exp(-t * 22)
            }
        case .swish:
            var lp = 0.0, hp = 0.0, last = 0.0
            return buffer(0.32) { t in
                let n = noise()
                hp = 0.9 * (hp + n - last); last = n
                lp += (hp - lp) * 0.35
                let shape = sin(.pi * min(1, t / 0.3))
                return lp * 0.55 * shape
            }
        case .score:
            return notes([(784, 0.06), (988, 0.06), (1_319, 0.1)])
        case .fire:
            return notes([(523, 0.05), (659, 0.05), (784, 0.05), (1_047, 0.05), (1_319, 0.05), (1_568, 0.14)])
        case .stage:
            return notes([(523, 0.1), (523, 0.1), (784, 0.1), (1_047, 0.3)], vol: 0.25)
        case .buzzer:
            return buffer(0.9) { t in
                let saw = (t * 110).truncatingRemainder(dividingBy: 1) * 2 - 1
                let saw2 = (t * 113).truncatingRemainder(dividingBy: 1) * 2 - 1
                return (saw + saw2) * 0.22 * min(1, t / 0.01) * (t > 0.8 ? (0.9 - t) * 10 : 1)
            }
        case .tick:
            return notes([(1_760, 0.04)], vol: 0.16)
        case .bounce:
            return buffer(0.14) { t in sin(2 * .pi * (95 - t * 200) * t) * 0.7 * exp(-t * 30) }
        case .lifeLost:
            return notes([(392, 0.1), (330, 0.1), (262, 0.22)], vol: 0.22)
        case .ticket:
            return notes([(2_093, 0.025), (2_637, 0.03)], vol: 0.1)
        case .tap:
            return notes([(1_046, 0.03)], vol: 0.12)
        case .fizzle:
            var lp = 0.0
            return buffer(0.4) { t in
                lp += (noise() - lp) * 0.3
                return lp * 0.5 * exp(-t * 7)
            }
        }
    }
}

enum Haptics {
    static var enabled = true
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let note = UINotificationFeedbackGenerator()

    static func tap() { if enabled { light.impactOccurred() } }
    static func release() { if enabled { medium.impactOccurred(intensity: 0.6) } }
    static func rim(_ s: Double) { if enabled { rigid.impactOccurred(intensity: CGFloat(0.4 + s * 0.6)) } }
    static func score() { if enabled { heavy.impactOccurred(intensity: 0.8) } }
    static func success() { if enabled { note.notificationOccurred(.success) } }
    static func error() { if enabled { note.notificationOccurred(.error) } }
}

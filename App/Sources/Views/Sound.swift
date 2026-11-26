import AVFoundation

/// 効果音（端末の中で作る。録音したファイルは持たない）。
/// ロボット掃除機の昼：ボタンのピッ、吸いこむシュッ（続くほど少し高く）、毛玉にぶつかるボフッ、残りわずかのピピッ、
/// 落とし物のキラン、ゴミ箱いっぱいの 3 音、強化のカチッ、ドックに帰る充電のポロン、星のキン、止まるモーターの下がる音。
/// 消音スイッチに従い、ほかのアプリの音と混ぜる（.ambient）
@MainActor
final class SoundBox {
    static let shared = SoundBox()

    enum Cue: Hashable {
        case tap, suck(Int), hit, warn, lost, binFull, upgrade, dock, star, dead
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var prepared = false
    private let rate = 44_100.0
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)

    /// 音量の段階：触る 0.3・吸う 0.25・ぶつかる 0.6・知らせ 0.6・強化 0.6・帰る 0.8・止まる 0.8
    private func volume(_ cue: Cue) -> Float {
        switch cue {
        case .tap: 0.3
        case .suck: 0.25
        case .hit, .warn, .upgrade, .lost: 0.6
        case .binFull: 0.65
        case .dock, .star, .dead: 0.8
        }
    }

    private func prepare() -> Bool {
        if prepared { return engine.isRunning || ((try? engine.start()) != nil) }
        guard let format else { return false }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for _ in 0..<8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        prepared = true
        return (try? engine.start()) != nil
    }

    func play(_ cue: Cue) {
        guard prepare(), engine.isRunning else { return }
        let buffer: AVAudioPCMBuffer
        if let b = buffers[cue] {
            buffer = b
        } else {
            guard let b = make(cue) else { return }
            buffers[cue] = b
            buffer = b
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.volume = volume(cue)
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    private struct Tone {
        var freq: Double
        var amp: Double
        var decay: Double
        var delay: Double = 0
        var glide: Double? = nil
    }

    private func make(_ cue: Cue) -> AVAudioPCMBuffer? {
        switch cue {
        case .tap:
            return render(0.06, noise: 0.05, noiseDecay: 120, tones: [Tone(freq: 1320, amp: 0.2, decay: 80)])
        case .suck(let n):
            // シュッ：ノイズが上がる。続くほど少し高い
            let f = 600.0 + Double(n) * 60
            return render(0.12, noise: 0.25, noiseDecay: 30, tones: [Tone(freq: f, amp: 0.08, decay: 30, glide: f * 1.8)])
        case .hit:
            // ボフッ（やわらかい低い音）
            return render(0.25, noise: 0.35, noiseDecay: 30, tones: [Tone(freq: 160, amp: 0.4, decay: 18, glide: 90)])
        case .warn:
            return render(0.35, noise: 0, tones: [Tone(freq: 1760, amp: 0.2, decay: 14), Tone(freq: 1760, amp: 0.2, decay: 14, delay: 0.14)])
        case .lost:
            // キラン
            return render(0.5, noise: 0, tones: [Tone(freq: 2093, amp: 0.18, decay: 8), Tone(freq: 2637, amp: 0.16, decay: 8, delay: 0.07), Tone(freq: 3136, amp: 0.14, decay: 8, delay: 0.14)])
        case .binFull:
            let notes = [523.3, 659.3, 784.0]
            return render(0.6, noise: 0, tones: notes.enumerated().map { i, f in Tone(freq: f, amp: 0.24, decay: 6, delay: Double(i) * 0.09) })
        case .upgrade:
            return render(0.3, noise: 0.15, noiseDecay: 90, tones: [Tone(freq: 880, amp: 0.25, decay: 12), Tone(freq: 1318.5, amp: 0.2, decay: 12, delay: 0.06)])
        case .dock:
            // 充電のポロン（下から上へ 4 音）
            let notes = [523.3, 784.0, 1046.5, 1568.0]
            return render(1.1, noise: 0, tones: notes.enumerated().map { i, f in Tone(freq: f, amp: 0.22, decay: 4, delay: Double(i) * 0.1) })
        case .star:
            return render(0.35, noise: 0, tones: [Tone(freq: 1568, amp: 0.22, decay: 10), Tone(freq: 2093, amp: 0.18, decay: 10, delay: 0.06)])
        case .dead:
            // モーターが止まる：下がるうなり
            return render(0.9, noise: 0.05, noiseDecay: 4, tones: [Tone(freq: 330, amp: 0.3, decay: 3, glide: 70), Tone(freq: 165, amp: 0.15, decay: 3, glide: 50)])
        }
    }

    private func render(_ seconds: Double, noise: Double, noiseDecay: Double = 60, tones: [Tone]) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let frames = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var rng = SeededRNG(seed: 22)
        var phases = Array(repeating: 0.0, count: tones.count)
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            var v = 0.0
            for (k, p) in tones.enumerated() where t >= p.delay {
                let local = t - p.delay
                var f = p.freq
                if let to = p.glide {
                    let x = min(1, local / max(0.01, seconds - p.delay))
                    f = p.freq + (to - p.freq) * x
                }
                phases[k] += 2 * .pi * f / rate
                let attack = min(1, local / 0.003)
                v += sin(phases[k]) * p.amp * exp(-local * p.decay) * attack
            }
            if noise > 0 {
                let n = rng.unit() * 2 - 1
                v += n * noise * exp(-t * noiseDecay)
            }
            let tail = min(1, (seconds - t) / 0.01)
            data[i] = Float(max(-1, min(1, v * tail)))
        }
        return buffer
    }
}

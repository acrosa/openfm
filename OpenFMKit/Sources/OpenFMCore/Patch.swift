// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A complete OpenFM sound in a readable, JSON-friendly form.
///
/// Voice parameters use DX7 ranges so a patch converts losslessly to and
/// from the 156-byte voice the engine plays (`bytes`).
public struct Patch: Codable, Equatable, Sendable {
    public struct Envelope: Codable, Equatable, Sendable {
        public var rates: [Int] = [99, 99, 99, 99]
        public var levels: [Int] = [99, 99, 99, 0]

        public init(rates: [Int] = [99, 99, 99, 99], levels: [Int] = [99, 99, 99, 0]) {
            self.rates = rates
            self.levels = levels
        }
    }

    public struct Operator: Codable, Equatable, Sendable {
        public var on = true
        public var level = 0
        public var fixed = false
        public var coarse = 1
        public var fine = 0
        /// -7...7
        public var detune = 0
        public var envelope = Envelope()
        public var velocity = 0
        public var ampModSens = 0
        public var rateScaling = 0
        public var breakpoint = 39
        public var leftDepth = 0
        public var rightDepth = 0
        public var leftCurve = 0
        public var rightCurve = 0

        public init() {}
    }

    public struct LFO: Codable, Equatable, Sendable {
        public var wave = 0
        public var speed = 35
        public var delay = 0
        public var pitchDepth = 0
        public var ampDepth = 0
        public var keySync = true
        public var pitchSens = 3

        public init(wave: Int = 0, speed: Int = 35, delay: Int = 0, pitchDepth: Int = 0, ampDepth: Int = 0,
                    keySync: Bool = true, pitchSens: Int = 3) {
            self.wave = wave
            self.speed = speed
            self.delay = delay
            self.pitchDepth = pitchDepth
            self.ampDepth = ampDepth
            self.keySync = keySync
            self.pitchSens = pitchSens
        }
    }

    public struct Effects: Codable, Equatable, Sendable {
        public var chorusMix = 0.0
        public var chorusRate = 0.6
        public var chorusDepth = 0.5
        public var delayMix = 0.0
        public var delayTime = 0.35
        public var delayFeedback = 0.35
        public var reverbMix = 0.2
        public var reverbSize = 0.5
        public var reverbDamping = 0.4

        public init(chorusMix: Double = 0, chorusRate: Double = 0.6, chorusDepth: Double = 0.5,
                    delayMix: Double = 0, delayTime: Double = 0.35, delayFeedback: Double = 0.35,
                    reverbMix: Double = 0.2, reverbSize: Double = 0.5, reverbDamping: Double = 0.4) {
            self.chorusMix = chorusMix
            self.chorusRate = chorusRate
            self.chorusDepth = chorusDepth
            self.delayMix = delayMix
            self.delayTime = delayTime
            self.delayFeedback = delayFeedback
            self.reverbMix = reverbMix
            self.reverbSize = reverbSize
            self.reverbDamping = reverbDamping
        }

        /// In the order of `Param.patchEffects`.
        public var values: [Double] {
            get { [chorusMix, chorusRate, chorusDepth, delayMix, delayTime, delayFeedback,
                   reverbMix, reverbSize, reverbDamping] }
            set {
                guard newValue.count >= 9 else { return }
                chorusMix = newValue[0]; chorusRate = newValue[1]; chorusDepth = newValue[2]
                delayMix = newValue[3]; delayTime = newValue[4]; delayFeedback = newValue[5]
                reverbMix = newValue[6]; reverbSize = newValue[7]; reverbDamping = newValue[8]
            }
        }
    }

    public var format = "openfm.patch"
    public var version = 1
    public var name = "Init Voice"
    public var category = "User"
    /// 1...32
    public var algorithm = 1
    public var feedback = 0
    public var keySync = true
    /// Semitones, -24...24
    public var transpose = 0
    /// OP1 first.
    public var operators: [Operator] = Patch.initOperators
    public var pitchEnvelope = Envelope(rates: [99, 99, 99, 99], levels: [50, 50, 50, 50])
    public var lfo = LFO()
    public var effects = Effects()

    /// The init voice: a single sine wave.
    public init() {}

    public static var initOperators: [Operator] {
        var ops = [Operator](repeating: Operator(), count: 6)
        ops[0].level = 99
        return ops
    }
}

// MARK: - DX7 voice bytes

extension Patch {
    public static let byteCount = 156

    /// Builds a patch from 156 unpacked DX7 voice bytes (byte 155 is the
    /// operator enable mask, bit 0 = OP6).
    public init(bytes: [UInt8], name: String? = nil, category: String = "User", effects: Effects = Effects()) {
        precondition(bytes.count >= Patch.byteCount)
        func b(_ i: Int, _ max: Int) -> Int { min(Int(bytes[i]), max) }
        var ops: [Operator] = []
        for number in 1...6 {
            let o = (6 - number) * 21
            var op = Operator()
            op.envelope = Envelope(rates: (0..<4).map { b(o + $0, 99) }, levels: (4..<8).map { b(o + $0, 99) })
            op.breakpoint = b(o + 8, 99)
            op.leftDepth = b(o + 9, 99)
            op.rightDepth = b(o + 10, 99)
            op.leftCurve = b(o + 11, 3)
            op.rightCurve = b(o + 12, 3)
            op.rateScaling = b(o + 13, 7)
            op.ampModSens = b(o + 14, 3)
            op.velocity = b(o + 15, 7)
            op.level = b(o + 16, 99)
            op.fixed = b(o + 17, 1) == 1
            op.coarse = b(o + 18, 31)
            op.fine = b(o + 19, 99)
            op.detune = b(o + 20, 14) - 7
            op.on = (Int(bytes[155]) >> (6 - number)) & 1 == 1
            ops.append(op)
        }
        operators = ops
        pitchEnvelope = Envelope(rates: (126..<130).map { b($0, 99) }, levels: (130..<134).map { b($0, 99) })
        algorithm = b(134, 31) + 1
        feedback = b(135, 7)
        keySync = b(136, 1) == 1
        lfo = LFO(wave: b(142, 5), speed: b(137, 99), delay: b(138, 99), pitchDepth: b(139, 99),
                  ampDepth: b(140, 99), keySync: b(141, 1) == 1, pitchSens: b(143, 7))
        transpose = b(144, 48) - 24
        let raw = String(decoding: bytes[145..<155].map { (32...126).contains($0) ? $0 : 32 }, as: UTF8.self)
        self.name = name ?? raw.trimmingCharacters(in: .whitespaces)
        self.category = category
        self.effects = effects
    }

    public var bytes: [UInt8] {
        var out = [UInt8](repeating: 0, count: Patch.byteCount)
        func put(_ i: Int, _ v: Int, _ max: Int) { out[i] = UInt8(min(Swift.max(v, 0), max)) }
        var mask = 0
        for number in 1...6 {
            let op = operators.indices.contains(number - 1) ? operators[number - 1] : Operator()
            let o = (6 - number) * 21
            for i in 0..<4 {
                put(o + i, op.envelope.rates.indices.contains(i) ? op.envelope.rates[i] : 99, 99)
                put(o + 4 + i, op.envelope.levels.indices.contains(i) ? op.envelope.levels[i] : 0, 99)
            }
            put(o + 8, op.breakpoint, 99)
            put(o + 9, op.leftDepth, 99)
            put(o + 10, op.rightDepth, 99)
            put(o + 11, op.leftCurve, 3)
            put(o + 12, op.rightCurve, 3)
            put(o + 13, op.rateScaling, 7)
            put(o + 14, op.ampModSens, 3)
            put(o + 15, op.velocity, 7)
            put(o + 16, op.level, 99)
            put(o + 17, op.fixed ? 1 : 0, 1)
            put(o + 18, op.coarse, 31)
            put(o + 19, op.fine, 99)
            put(o + 20, op.detune + 7, 14)
            if op.on { mask |= 1 << (6 - number) }
        }
        for i in 0..<4 {
            put(126 + i, pitchEnvelope.rates.indices.contains(i) ? pitchEnvelope.rates[i] : 99, 99)
            put(130 + i, pitchEnvelope.levels.indices.contains(i) ? pitchEnvelope.levels[i] : 50, 99)
        }
        put(134, algorithm - 1, 31)
        put(135, feedback, 7)
        put(136, keySync ? 1 : 0, 1)
        put(137, lfo.speed, 99)
        put(138, lfo.delay, 99)
        put(139, lfo.pitchDepth, 99)
        put(140, lfo.ampDepth, 99)
        put(141, lfo.keySync ? 1 : 0, 1)
        put(142, lfo.wave, 5)
        put(143, lfo.pitchSens, 7)
        put(144, transpose + 24, 48)
        let ascii = Array(name.uppercased().utf8.filter { (32...126).contains($0) }.prefix(10))
        for i in 0..<10 { out[145 + i] = i < ascii.count ? ascii[i] : 32 }
        out[155] = UInt8(mask)
        return out
    }
}

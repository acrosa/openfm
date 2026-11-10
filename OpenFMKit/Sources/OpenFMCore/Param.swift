// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One editable synth parameter: where it lives, its range and how to show it.
///
/// Addresses match `OpenFMAudioUnit`: 0...144 are unpacked DX7 voice offsets,
/// 160...165 are operator on/off switches and 200... are effects.
public struct Param: Hashable, Sendable {
    public enum Format: Hashable, Sendable {
        case plain
        case centered(Int)            // shown relative to a centre value
        case choice([String])
        case note                     // DX7 break point, 0 = A-1
        case algorithm
        case percent
        case seconds
        case hertz
        case semitones
    }

    public let address: Int
    /// Full name for the readout, e.g. "OUTPUT LEVEL".
    public let title: String
    /// Short caption for a value cell, e.g. "LEVEL".
    public let caption: String
    public let range: ClosedRange<Double>
    public let defaultValue: Double
    /// 1 for stepped parameters, 0 for continuous ones.
    public let step: Double
    /// Operator number 1...6 when the parameter belongs to one.
    public let op: Int?
    public let format: Format

    public var isStepped: Bool { step > 0 }
    public var span: Double { range.upperBound - range.lowerBound }

    public func normalized(_ value: Double) -> Double {
        span == 0 ? 0 : (value - range.lowerBound) / span
    }

    public func clamped(_ value: Double) -> Double {
        let v = min(max(value, range.lowerBound), range.upperBound)
        return isStepped ? v.rounded() : v
    }

    public func string(_ value: Double) -> String {
        switch format {
        case .plain:
            return String(Int(value.rounded()))
        case .centered(let centre):
            let d = Int(value.rounded()) - centre
            return d > 0 ? "+\(d)" : "\(d)"
        case .choice(let names):
            let i = Int(value.rounded())
            return names.indices.contains(i) ? names[i] : "\(i)"
        case .note:
            return Param.noteName(midi: Int(value.rounded()) + 21)
        case .algorithm:
            return String(format: "%02d", Int(value.rounded()) + 1)
        case .percent:
            return "\(Int((value * 100).rounded()))"
        case .seconds:
            return value < 1 ? "\(Int((value * 1000).rounded())) ms" : String(format: "%.2f s", value)
        case .hertz:
            return String(format: "%.2f Hz", value)
        case .semitones:
            return "\(Int(value.rounded())) st"
        }
    }

    public static func noteName(midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[((midi % 12) + 12) % 12])\(midi / 12 - 2)"
    }
}

// MARK: - Operator parameters

extension Param {
    public enum OpField: Int, CaseIterable, Sendable {
        case rate1, rate2, rate3, rate4
        case level1, level2, level3, level4
        case breakpoint, leftDepth, rightDepth, leftCurve, rightCurve
        case rateScaling, ampModSens, velocitySens
        case level, mode, coarse, fine, detune
    }

    public static let curveNames = ["−LIN", "−EXP", "+EXP", "+LIN"]

    /// A parameter of operator `op` (1...6).
    public static func op(_ op: Int, _ field: OpField) -> Param {
        let address = (6 - op) * 21 + field.rawValue
        func make(_ title: String, _ caption: String, _ max: Double, _ def: Double, _ format: Format = .plain) -> Param {
            Param(address: address, title: title, caption: caption, range: 0...max,
                  defaultValue: def, step: 1, op: op, format: format)
        }
        switch field {
        case .rate1, .rate2, .rate3, .rate4:
            let n = field.rawValue + 1
            return make("ENVELOPE RATE \(n)", "RATE \(n)", 99, 99)
        case .level1, .level2, .level3, .level4:
            let n = field.rawValue - 3
            return make("ENVELOPE LEVEL \(n)", "LEVEL \(n)", 99, n == 4 ? 0 : 99)
        case .breakpoint: return make("SCALING BREAK POINT", "BREAK", 99, 39, .note)
        case .leftDepth: return make("SCALING LEFT DEPTH", "L DEPTH", 99, 0)
        case .rightDepth: return make("SCALING RIGHT DEPTH", "R DEPTH", 99, 0)
        case .leftCurve: return make("SCALING LEFT CURVE", "L CURVE", 3, 0, .choice(curveNames))
        case .rightCurve: return make("SCALING RIGHT CURVE", "R CURVE", 3, 0, .choice(curveNames))
        case .rateScaling: return make("KEY RATE SCALING", "KEY RATE", 7, 0)
        case .ampModSens: return make("AMP MOD SENSITIVITY", "AMP MOD", 3, 0)
        case .velocitySens: return make("VELOCITY SENSITIVITY", "VELOCITY", 7, 0)
        case .level: return make("OUTPUT LEVEL", "LEVEL", 99, 0)
        case .mode: return make("FREQUENCY MODE", "MODE", 1, 0, .choice(["RATIO", "FIXED"]))
        case .coarse: return make("FREQUENCY COARSE", "COARSE", 31, 1)
        case .fine: return make("FREQUENCY FINE", "FINE", 99, 0)
        case .detune: return make("DETUNE", "DETUNE", 14, 7, .centered(7))
        }
    }

    public static func enabled(_ op: Int) -> Param {
        Param(address: 160 + op - 1, title: "OPERATOR", caption: "ON", range: 0...1,
              defaultValue: 1, step: 1, op: op, format: .choice(["OFF", "ON"]))
    }
}

// MARK: - Voice parameters

extension Param {
    private static func voice(_ address: Int, _ title: String, _ caption: String, _ max: Double,
                              _ def: Double, _ format: Format = .plain) -> Param {
        Param(address: address, title: title, caption: caption, range: 0...max,
              defaultValue: def, step: 1, op: nil, format: format)
    }

    public static func pitchRate(_ n: Int) -> Param { voice(125 + n, "PITCH ENVELOPE RATE \(n)", "RATE \(n)", 99, 99) }
    public static func pitchLevel(_ n: Int) -> Param { voice(129 + n, "PITCH ENVELOPE LEVEL \(n)", "LEVEL \(n)", 99, 50, .centered(50)) }

    public static let algorithm = voice(134, "ALGORITHM", "ALGORITHM", 31, 0, .algorithm)
    public static let feedback = voice(135, "FEEDBACK", "FEEDBACK", 7, 0)
    public static let keySync = voice(136, "OSCILLATOR KEY SYNC", "KEY SYNC", 1, 1, .choice(["OFF", "ON"]))
    public static let lfoSpeed = voice(137, "LFO SPEED", "SPEED", 99, 35)
    public static let lfoDelay = voice(138, "LFO DELAY", "DELAY", 99, 0)
    public static let lfoPitchDepth = voice(139, "LFO PITCH DEPTH", "PITCH", 99, 0)
    public static let lfoAmpDepth = voice(140, "LFO AMP DEPTH", "AMP", 99, 0)
    public static let lfoSync = voice(141, "LFO KEY SYNC", "KEY SYNC", 1, 1, .choice(["OFF", "ON"]))
    public static let lfoWave = voice(142, "LFO WAVE", "WAVE", 5, 0,
                               .choice(["TRI", "SAW DN", "SAW UP", "SQUARE", "SINE", "S&H"]))
    public static let pitchModSens = voice(143, "PITCH MOD SENSITIVITY", "SENS", 7, 3)
    public static let transpose = voice(144, "TRANSPOSE", "TRANSPOSE", 48, 24, .centered(24))
}

// MARK: - Effects

extension Param {
    private static func fx(_ index: Int, _ title: String, _ caption: String, _ range: ClosedRange<Double>,
                           _ def: Double, _ format: Format, step: Double = 0) -> Param {
        Param(address: 200 + index, title: title, caption: caption, range: range,
              defaultValue: def, step: step, op: nil, format: format)
    }

    public static let chorusMix = fx(0, "CHORUS MIX", "MIX", 0...1, 0, .percent)
    public static let chorusRate = fx(1, "CHORUS RATE", "RATE", 0.05...8, 0.6, .hertz)
    public static let chorusDepth = fx(2, "CHORUS DEPTH", "DEPTH", 0...1, 0.5, .percent)
    public static let delayMix = fx(3, "DELAY MIX", "MIX", 0...1, 0, .percent)
    public static let delayTime = fx(4, "DELAY TIME", "TIME", 0.02...1.5, 0.35, .seconds)
    public static let delayFeedback = fx(5, "DELAY FEEDBACK", "REPEATS", 0...0.95, 0.35, .percent)
    public static let reverbMix = fx(6, "REVERB MIX", "MIX", 0...1, 0.2, .percent)
    public static let reverbSize = fx(7, "REVERB SIZE", "SIZE", 0...1, 0.5, .percent)
    public static let reverbDamp = fx(8, "REVERB DAMPING", "DAMPING", 0...1, 0.4, .percent)
    public static let volume = fx(9, "MASTER VOLUME", "VOLUME", 0...1, 0.8, .percent)
    public static let bendRange = fx(10, "PITCH BEND RANGE", "BEND", 0...12, 2, .semitones, step: 1)

    public static let effectCount = 11
    /// Effect parameters stored with a patch (volume and bend range are global).
    public static let patchEffects: [Param] = [chorusMix, chorusRate, chorusDepth, delayMix, delayTime,
                                        delayFeedback, reverbMix, reverbSize, reverbDamp]
    public static let allEffects: [Param] = patchEffects + [volume, bendRange]
}

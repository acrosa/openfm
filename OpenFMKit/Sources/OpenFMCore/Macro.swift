// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A single control that moves several voice parameters at once, so a sound
/// can be shaped without opening the editor.
///
/// A macro is an offset: at zero the sound is exactly as designed, and
/// turning it moves each parameter it owns away from that starting point.
/// Add a new one by declaring it here and listing it in `Macro.all`.
public struct Macro: Hashable, Sendable, Identifiable {
    public let id: String
    /// Short caption, e.g. "TONE".
    public let caption: String
    /// What it does, in plain words.
    public let hint: String
    /// Parameter offsets at full deflection (+1) for carriers and modulators.
    let carrier: [Param.OpField: Double]
    let modulator: [Param.OpField: Double]

    func offsets(isCarrier: Bool) -> [Param.OpField: Double] { isCarrier ? carrier : modulator }

    /// "+12" style display for a value in -1...1.
    public func string(_ value: Double) -> String {
        let n = Int((value * 50).rounded())
        return n > 0 ? "+\(n)" : "\(n)"
    }

    /// Darker to brighter: the level of every modulator.
    public static let tone = Macro(id: "tone", caption: "TONE", hint: "Darker or brighter · moves every modulator level",
                                   carrier: [:], modulator: [.level: 22])
    /// How quickly notes speak. Envelope rates run backwards: lower is slower.
    public static let attack = Macro(id: "attack", caption: "ATTACK", hint: "Snappier or softer start of each note",
                                     carrier: [.rate1: -55], modulator: [.rate1: -30])
    /// How long a held note takes to settle.
    public static let decay = Macro(id: "decay", caption: "DECAY", hint: "Shorter or longer fade while a key is held",
                                    carrier: [.rate2: -28, .rate3: -28], modulator: [.rate2: -20, .rate3: -20])
    /// How loud a note stays while the key is held. Modulators move less, so
    /// the held tone keeps its character.
    public static let sustain = Macro(id: "sustain", caption: "SUSTAIN", hint: "Quieter or fuller while a key is held",
                                      carrier: [.level3: 60], modulator: [.level3: 25])
    /// How long notes ring after the key is released.
    public static let release = Macro(id: "release", caption: "RELEASE", hint: "Shorter or longer ring after you let go",
                                      carrier: [.rate4: -40], modulator: [.rate4: -30])

    /// The four that shape a note over time, in ADSR order.
    public static let envelope: [Macro] = [.attack, .decay, .sustain, .release]

    public static let all: [Macro] = [.tone, .attack, .decay, .sustain, .release]
}

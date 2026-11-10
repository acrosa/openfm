// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The factory bank. Every patch here was written for OpenFM and is released
/// under Apache 2.0 with the rest of the project; none is derived from a
/// commercial ROM or cartridge.
public enum FactoryPresets {
    public static let all: [Patch] = keys + basses + synths + drums + mallets + brassAndLeads + pads + plucks

    // MARK: Builders

    /// A ratio-mode operator. `r`/`l` are the four envelope rates and levels.
    private static func op(_ ratio: Double, _ level: Int, r: [Int], l: [Int], vel: Int = 0,
                           det: Int = 0, ams: Int = 0, rs: Int = 0, tame: Int = 0) -> Patch.Operator {
        var o = Patch.Operator()
        o.level = level
        let coarse = ratio < 1 ? 0 : min(31, Int(ratio))
        let base = coarse == 0 ? 0.5 : Double(coarse)
        o.coarse = coarse
        o.fine = min(99, max(0, Int(((ratio / base - 1) * 100).rounded())))
        o.detune = det
        o.envelope = Patch.Envelope(rates: r, levels: l)
        o.velocity = vel
        o.ampModSens = ams
        o.rateScaling = rs
        // `tame` pulls the level down towards the top of the keyboard, which
        // keeps bright modulators from aliasing.
        o.rightDepth = tame
        return o
    }

    private static let off = Patch.Operator()

    /// - Parameter pitch: pitch envelope rates and levels; level 50 is no change.
    private static func patch(_ name: String, _ category: String, alg: Int, fb: Int = 0,
                              transpose: Int = 0, _ ops: [Patch.Operator],
                              lfo: Patch.LFO = Patch.LFO(), fx: Patch.Effects = Patch.Effects(),
                              pitch: Patch.Envelope? = nil) -> Patch {
        var p = Patch()
        p.name = name
        p.category = category
        p.algorithm = alg
        p.feedback = fb
        p.transpose = transpose
        p.operators = ops
        p.lfo = lfo
        p.effects = fx
        if let pitch { p.pitchEnvelope = pitch }
        return p
    }

    private static func fx(chorus: Double = 0, delay: Double = 0, time: Double = 0.35, feedback: Double = 0.35,
                           reverb: Double = 0.2, size: Double = 0.5, damp: Double = 0.4,
                           rate: Double = 0.6, depth: Double = 0.5) -> Patch.Effects {
        Patch.Effects(chorusMix: chorus, chorusRate: rate, chorusDepth: depth, delayMix: delay, delayTime: time,
                      delayFeedback: feedback, reverbMix: reverb, reverbSize: size, reverbDamping: damp)
    }

    // MARK: Keys

    private static let keys: [Patch] = [
        patch("Glass Keys", "Keys", alg: 5, fb: 5, [
            op(1, 99, r: [96, 28, 22, 62], l: [99, 80, 0, 0], vel: 2),
            op(14, 62, r: [96, 55, 30, 70], l: [99, 60, 0, 0], vel: 6, tame: 40),
            op(1, 96, r: [96, 24, 20, 55], l: [99, 90, 0, 0], vel: 2, det: 2),
            op(1, 82, r: [96, 32, 22, 55], l: [99, 85, 0, 0], vel: 5),
            op(1, 96, r: [96, 24, 20, 55], l: [99, 90, 0, 0], vel: 2, det: -2),
            op(1, 76, r: [96, 30, 22, 55], l: [99, 85, 0, 0], vel: 5, det: 3),
        ], fx: fx(chorus: 0.3, reverb: 0.22)),

        patch("Felt Tines", "Keys", alg: 5, [
            op(1, 99, r: [92, 26, 20, 55], l: [99, 85, 0, 0], vel: 2),
            op(9, 50, r: [92, 50, 28, 60], l: [99, 50, 0, 0], vel: 5, tame: 45),
            op(1, 95, r: [92, 22, 18, 50], l: [99, 92, 0, 0], vel: 2, det: 1),
            op(1, 70, r: [92, 28, 20, 50], l: [99, 88, 0, 0], vel: 4),
            op(1, 95, r: [92, 22, 18, 50], l: [99, 92, 0, 0], vel: 2, det: -1),
            op(1, 68, r: [92, 28, 20, 50], l: [99, 88, 0, 0], vel: 4, det: 2),
        ], fx: fx(chorus: 0.45, reverb: 0.3, size: 0.6, rate: 0.4)),

        patch("Hard Clav", "Keys", alg: 1, fb: 6, [
            op(1, 99, r: [99, 50, 35, 80], l: [99, 70, 0, 0], vel: 3),
            op(3, 86, r: [99, 60, 35, 80], l: [99, 60, 0, 0], vel: 5, tame: 30),
            op(2, 88, r: [99, 55, 35, 80], l: [99, 60, 0, 0], vel: 3),
            op(1, 84, r: [99, 58, 35, 80], l: [99, 55, 0, 0], vel: 4),
            op(5, 70, r: [99, 70, 40, 80], l: [99, 30, 0, 0], vel: 5, tame: 40),
            op(1, 72, r: [99, 60, 40, 80], l: [99, 50, 0, 0], vel: 3),
        ], fx: fx(reverb: 0.12)),

        patch("Drawbars", "Keys", alg: 32, fb: 3, [
            op(0.5, 92, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
            op(1, 99, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
            op(1.5, 86, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
            op(2, 90, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
            op(3, 80, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
            op(4, 76, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
        ], fx: fx(chorus: 0.55, reverb: 0.18, rate: 5.5, depth: 0.25)),

        patch("Perc Organ", "Keys", alg: 31, fb: 4, [
            op(0.5, 94, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
            op(1, 99, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
            op(2, 88, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
            op(3, 78, r: [99, 99, 99, 85], l: [99, 99, 99, 0]),
            op(4, 92, r: [99, 62, 50, 85], l: [99, 0, 0, 0], vel: 2),
            op(4, 64, r: [99, 70, 50, 85], l: [99, 0, 0, 0]),
        ], fx: fx(chorus: 0.4, reverb: 0.2, rate: 0.9, depth: 0.4)),
    ]

    // MARK: Bass

    private static let basses: [Patch] = [
        patch("Solid Bass", "Bass", alg: 3, fb: 6, transpose: -12, [
            op(1, 99, r: [99, 45, 30, 70], l: [99, 85, 70, 0], vel: 2),
            op(1, 80, r: [99, 55, 35, 70], l: [99, 70, 50, 0], vel: 4),
            op(1, 60, r: [99, 60, 40, 70], l: [99, 50, 0, 0], vel: 3),
            op(1, 90, r: [99, 50, 30, 70], l: [99, 80, 60, 0], vel: 2, det: 1),
            op(2, 74, r: [99, 65, 40, 70], l: [99, 40, 0, 0], vel: 5),
            op(1, 70, r: [99, 70, 40, 70], l: [99, 0, 0, 0], vel: 3),
        ], fx: fx(reverb: 0.06)),

        patch("Wire Bass", "Bass", alg: 2, fb: 7, transpose: -12, [
            op(1, 99, r: [99, 40, 30, 75], l: [99, 90, 80, 0], vel: 2),
            op(1, 82, r: [99, 45, 30, 75], l: [99, 75, 60, 0], vel: 4),
            op(1, 92, r: [99, 40, 30, 75], l: [99, 90, 80, 0], vel: 2, det: 2),
            op(2, 78, r: [99, 60, 35, 75], l: [99, 50, 30, 0], vel: 4),
            op(3, 70, r: [99, 70, 40, 75], l: [99, 20, 0, 0], vel: 5),
            off,
        ], fx: fx(chorus: 0.2, reverb: 0.08)),

        // Squelch: one modulator with feedback, opened by how hard you play.
        patch("Acid Line", "Bass", alg: 2, fb: 7, transpose: -12, [
            op(1, 99, r: [99, 60, 40, 75], l: [99, 80, 60, 0], vel: 2),
            op(1, 88, r: [99, 62, 45, 75], l: [99, 45, 20, 0], vel: 6),
            off, off, off, off,
        ], fx: fx(delay: 0.15, time: 0.27, feedback: 0.4, reverb: 0.05)),

        // Mostly fundamental, with a short click so it reads on small speakers.
        patch("Sub Pulse", "Bass", alg: 5, [
            op(0.5, 99, r: [99, 40, 30, 70], l: [99, 95, 90, 0], vel: 1),
            op(0.5, 55, r: [99, 50, 30, 70], l: [99, 70, 60, 0]),
            op(1, 80, r: [99, 70, 50, 70], l: [99, 0, 0, 0], vel: 3),
            op(3, 70, r: [99, 85, 60, 70], l: [99, 0, 0, 0], vel: 4),
            off, off,
        ], fx: fx(reverb: 0.04)),

        // Three detuned pairs grinding against each other.
        patch("Growl", "Bass", alg: 5, fb: 6, transpose: -12, [
            op(1, 97, r: [95, 40, 30, 65], l: [99, 95, 92, 0], vel: 1, det: -7),
            op(1, 78, r: [95, 40, 30, 65], l: [99, 90, 85, 0], vel: 3),
            op(1, 97, r: [95, 40, 30, 65], l: [99, 95, 92, 0], vel: 1),
            op(1, 76, r: [95, 40, 30, 65], l: [99, 90, 85, 0], vel: 3, det: 3),
            op(1, 97, r: [95, 40, 30, 65], l: [99, 95, 92, 0], vel: 1, det: 7),
            op(1, 80, r: [95, 40, 30, 65], l: [99, 90, 85, 0], vel: 3, det: -3),
        ], fx: fx(chorus: 0.5, reverb: 0.06, rate: 0.3)),

        // Tight and bouncy, for running in octaves under a sequence.
        patch("Octave Bass", "Bass", alg: 5, transpose: -12, [
            op(1, 99, r: [99, 65, 45, 80], l: [99, 60, 0, 0], vel: 3),
            op(1, 80, r: [99, 70, 45, 80], l: [99, 40, 0, 0], vel: 5),
            op(2, 82, r: [99, 70, 50, 80], l: [99, 30, 0, 0], vel: 3),
            op(2, 70, r: [99, 75, 50, 80], l: [99, 20, 0, 0], vel: 4),
            off, off,
        ], fx: fx(delay: 0.2, time: 0.268, feedback: 0.3, reverb: 0.06)),

        // Everything modulating one carrier at once: loud, dirty, sustained.
        patch("Buzz Bass", "Bass", alg: 18, fb: 7, transpose: -12, [
            op(1, 99, r: [99, 45, 35, 70], l: [99, 92, 88, 0], vel: 2),
            op(1, 85, r: [99, 50, 35, 70], l: [99, 85, 75, 0], vel: 3),
            op(2, 82, r: [99, 50, 35, 70], l: [99, 85, 75, 0], vel: 3),
            op(3, 76, r: [99, 60, 40, 70], l: [99, 60, 40, 0], vel: 4),
            op(5, 70, r: [99, 65, 40, 70], l: [99, 40, 20, 0], vel: 4),
            op(1, 70, r: [99, 60, 40, 70], l: [99, 60, 40, 0]),
        ], fx: fx(reverb: 0.05)),
    ]

    // MARK: Synths

    private static let synths: [Patch] = [
        // Short, bright and echoing: made for arpeggios.
        patch("Arp Pluck", "Synth", alg: 5, fb: 4, [
            op(1, 99, r: [99, 62, 45, 65], l: [99, 40, 0, 0], vel: 3),
            op(3, 78, r: [99, 72, 50, 65], l: [99, 20, 0, 0], vel: 5, tame: 30),
            op(1, 92, r: [99, 62, 45, 65], l: [99, 40, 0, 0], vel: 3, det: 3),
            op(1, 76, r: [99, 70, 50, 65], l: [99, 30, 0, 0], vel: 4),
            op(2, 80, r: [99, 68, 50, 65], l: [99, 0, 0, 0], vel: 3, det: -2),
            op(1, 72, r: [99, 70, 50, 65], l: [99, 20, 0, 0], vel: 4),
        ], fx: fx(chorus: 0.2, delay: 0.35, time: 0.402, feedback: 0.5, reverb: 0.2)),

        // A chord stab: one bright modulator across three carriers.
        patch("Chord Stab", "Synth", alg: 22, fb: 6, [
            op(1, 97, r: [99, 58, 45, 70], l: [99, 50, 0, 0], vel: 3),
            op(2, 74, r: [99, 65, 45, 70], l: [99, 30, 0, 0], vel: 4),
            op(1, 95, r: [99, 58, 45, 70], l: [99, 50, 0, 0], vel: 3, det: -3),
            op(1, 95, r: [99, 58, 45, 70], l: [99, 50, 0, 0], vel: 3, det: 3),
            op(2, 86, r: [99, 60, 45, 70], l: [99, 40, 0, 0], vel: 3),
            op(1, 84, r: [99, 62, 45, 70], l: [99, 45, 0, 0], vel: 5),
        ], fx: fx(chorus: 0.3, delay: 0.15, time: 0.402, reverb: 0.25, size: 0.55)),

        // Ratios that are not harmonics of anything: struck sheet metal.
        patch("Metal Hit", "Synth", alg: 5, [
            op(1, 99, r: [99, 55, 40, 55], l: [99, 0, 0, 0], vel: 3),
            op(3.5, 86, r: [99, 60, 40, 55], l: [99, 0, 0, 0], vel: 4, tame: 30),
            op(1.41, 92, r: [99, 52, 40, 55], l: [99, 0, 0, 0], vel: 3),
            op(5.19, 84, r: [99, 62, 40, 55], l: [99, 0, 0, 0], vel: 4, tame: 40),
            op(2.76, 86, r: [99, 58, 40, 55], l: [99, 0, 0, 0], vel: 3),
            op(7.1, 80, r: [99, 68, 40, 55], l: [99, 0, 0, 0], vel: 5, tame: 50),
        ], fx: fx(delay: 0.12, time: 0.2, reverb: 0.4, size: 0.7, damp: 0.3)),

        // Carriers parked on vowel harmonics, all driven from the fundamental.
        patch("Robot Vox", "Synth", alg: 5, fb: 3, [
            op(3, 96, r: [75, 45, 35, 60], l: [99, 92, 88, 0], vel: 2),
            op(1, 76, r: [75, 45, 35, 60], l: [99, 88, 80, 0], vel: 3),
            op(5, 88, r: [70, 45, 35, 60], l: [99, 90, 84, 0], vel: 2),
            op(1, 74, r: [70, 45, 35, 60], l: [99, 88, 80, 0], vel: 3),
            op(9, 76, r: [65, 45, 35, 60], l: [99, 80, 70, 0], vel: 2, tame: 30),
            op(1, 70, r: [65, 45, 35, 60], l: [99, 85, 75, 0], vel: 3),
        ], lfo: Patch.LFO(wave: 4, speed: 34, delay: 35, pitchDepth: 9),
           fx: fx(chorus: 0.35, delay: 0.15, time: 0.3, reverb: 0.2)),

        // A hard, nasal lead that cuts through anything.
        patch("Buzz Lead", "Synth", alg: 18, fb: 7, [
            op(1, 99, r: [92, 55, 40, 65], l: [99, 96, 94, 0], vel: 2),
            op(2, 80, r: [92, 55, 40, 65], l: [99, 90, 85, 0], vel: 3),
            op(1, 88, r: [92, 55, 40, 65], l: [99, 95, 92, 0], vel: 3),
            op(3, 72, r: [92, 60, 40, 65], l: [99, 80, 70, 0], vel: 4, det: 3),
            off, off,
        ], lfo: Patch.LFO(speed: 37, delay: 40, pitchDepth: 14),
           fx: fx(delay: 0.28, time: 0.402, feedback: 0.45, reverb: 0.18)),

        // Bright, wide strings with a quick bow.
        patch("Glitter Strings", "Synth", alg: 2, fb: 7, [
            op(1, 96, r: [58, 40, 30, 50], l: [99, 96, 94, 0], vel: 1, det: -3),
            op(1, 80, r: [60, 40, 30, 50], l: [99, 92, 88, 0], vel: 2),
            op(2, 90, r: [56, 40, 30, 50], l: [99, 96, 94, 0], vel: 1, det: 3),
            op(1, 78, r: [60, 40, 30, 50], l: [99, 92, 88, 0], vel: 2, det: -1),
            op(2, 70, r: [60, 40, 30, 50], l: [99, 88, 80, 0]),
            op(4, 58, r: [60, 40, 30, 50], l: [99, 80, 70, 0], tame: 30),
        ], lfo: Patch.LFO(speed: 31, delay: 25, pitchDepth: 7),
           fx: fx(chorus: 0.65, reverb: 0.35, size: 0.6, rate: 0.5)),

        // Slow, hollow and slightly uneasy.
        patch("Cold Pad", "Synth", alg: 19, fb: 3, [
            op(1, 95, r: [38, 35, 25, 42], l: [99, 95, 90, 0], vel: 1, ams: 1),
            op(3, 62, r: [32, 30, 25, 42], l: [99, 85, 70, 0]),
            op(1, 54, r: [32, 30, 25, 42], l: [99, 85, 70, 0]),
            op(1, 90, r: [34, 35, 25, 42], l: [99, 95, 90, 0], vel: 1, det: 5, ams: 1),
            op(2, 84, r: [34, 35, 25, 42], l: [99, 95, 90, 0], vel: 1, det: -5),
            op(7, 60, r: [26, 28, 22, 42], l: [99, 60, 35, 0], tame: 35),
        ], lfo: Patch.LFO(wave: 0, speed: 18, delay: 30, pitchDepth: 3, ampDepth: 30),
           fx: fx(chorus: 0.45, delay: 0.2, time: 0.536, feedback: 0.5, reverb: 0.55, size: 0.85, damp: 0.5)),

        // The pitch dives as the note sounds.
        patch("Laser Zap", "Synth", alg: 5, fb: 5, [
            op(1, 99, r: [99, 55, 40, 60], l: [99, 0, 0, 0], vel: 2),
            op(1, 82, r: [99, 60, 40, 60], l: [99, 30, 0, 0], vel: 4),
            op(2, 80, r: [99, 60, 40, 60], l: [99, 0, 0, 0], vel: 2),
            op(1, 70, r: [99, 65, 40, 60], l: [99, 0, 0, 0]),
            off, off,
        ], fx: fx(delay: 0.3, time: 0.268, feedback: 0.5, reverb: 0.2),
           pitch: Patch.Envelope(rates: [52, 99, 99, 99], levels: [38, 38, 38, 92])),
    ]

    // MARK: Drums

    private static let drums: [Patch] = [
        // A sine that drops an octave or two in a few milliseconds, plus a click.
        patch("Kick", "Drums", alg: 5, transpose: -24, [
            op(1, 99, r: [99, 58, 58, 80], l: [99, 0, 0, 0], vel: 2),
            op(1, 72, r: [99, 85, 60, 80], l: [99, 0, 0, 0], vel: 4),
            op(2, 70, r: [99, 90, 60, 80], l: [99, 0, 0, 0], vel: 3),
            op(5, 74, r: [99, 95, 60, 80], l: [99, 0, 0, 0], vel: 4),
            off, off,
        ], fx: fx(reverb: 0.03),
           pitch: Patch.Envelope(rates: [80, 99, 99, 99], levels: [50, 50, 50, 78])),

        // A short tone under a burst of feedback noise.
        patch("Snare", "Drums", alg: 5, fb: 7, [
            op(1, 92, r: [99, 72, 60, 75], l: [99, 0, 0, 0], vel: 3),
            op(1.5, 70, r: [99, 85, 60, 75], l: [99, 0, 0, 0], vel: 3),
            op(2.3, 80, r: [99, 75, 60, 75], l: [99, 0, 0, 0], vel: 3),
            op(5.5, 84, r: [99, 80, 60, 75], l: [99, 0, 0, 0], vel: 3),
            op(3.3, 96, r: [99, 66, 55, 70], l: [99, 0, 0, 0], vel: 4),
            op(7.77, 99, r: [99, 60, 50, 70], l: [99, 60, 0, 0], vel: 2),
        ], fx: fx(reverb: 0.18, size: 0.35),
           pitch: Patch.Envelope(rates: [85, 99, 99, 99], levels: [50, 50, 50, 62])),

        // High, inharmonic and very short.
        patch("Hat", "Drums", alg: 5, fb: 7, transpose: 12, [
            op(7.07, 90, r: [99, 82, 70, 82], l: [99, 0, 0, 0], vel: 3),
            op(9.43, 92, r: [99, 80, 70, 82], l: [99, 0, 0, 0], vel: 3),
            op(11.3, 86, r: [99, 84, 70, 82], l: [99, 0, 0, 0], vel: 3),
            op(14.9, 90, r: [99, 80, 70, 82], l: [99, 0, 0, 0], vel: 3),
            op(5.59, 88, r: [99, 80, 70, 82], l: [99, 0, 0, 0], vel: 3),
            op(13.1, 99, r: [99, 70, 60, 80], l: [99, 50, 0, 0], vel: 2),
        ], fx: fx(reverb: 0.08, size: 0.3)),
    ]

    // MARK: Mallets and bells

    private static let mallets: [Patch] = [
        patch("Tubular", "Mallets", alg: 5, [
            op(1, 97, r: [95, 30, 22, 38], l: [99, 85, 0, 0], vel: 2),
            op(3.5, 78, r: [95, 35, 25, 40], l: [99, 80, 0, 0], vel: 3, tame: 30),
            op(1, 95, r: [95, 30, 22, 38], l: [99, 85, 0, 0], vel: 2, det: 3),
            op(3.5, 76, r: [95, 35, 25, 40], l: [99, 80, 0, 0], vel: 3, det: -3, tame: 30),
            op(2, 80, r: [99, 50, 35, 50], l: [99, 0, 0, 0], vel: 3),
            op(11, 78, r: [99, 60, 40, 50], l: [99, 0, 0, 0], vel: 4, tame: 50),
        ], fx: fx(reverb: 0.4, size: 0.75, damp: 0.3)),

        patch("Music Box", "Mallets", alg: 5, transpose: 12, [
            op(1, 99, r: [99, 45, 35, 50], l: [99, 60, 0, 0], vel: 3),
            op(4, 72, r: [99, 55, 40, 55], l: [99, 40, 0, 0], vel: 4, tame: 40),
            op(1, 90, r: [99, 48, 35, 50], l: [99, 50, 0, 0], vel: 3, det: 2),
            op(7, 60, r: [99, 65, 40, 55], l: [99, 20, 0, 0], vel: 5, tame: 50),
            op(4, 70, r: [99, 60, 40, 55], l: [99, 0, 0, 0], vel: 4),
            op(1, 50, r: [99, 60, 40, 55], l: [99, 0, 0, 0]),
        ], fx: fx(delay: 0.18, time: 0.28, reverb: 0.35, size: 0.6)),

        patch("Marimba", "Mallets", alg: 7, [
            op(1, 99, r: [99, 52, 40, 60], l: [99, 50, 0, 0], vel: 3),
            op(4, 76, r: [99, 75, 50, 70], l: [99, 0, 0, 0], vel: 5, tame: 30),
            op(1, 90, r: [99, 58, 40, 60], l: [99, 30, 0, 0], vel: 3),
            op(10, 62, r: [99, 85, 60, 70], l: [99, 0, 0, 0], vel: 6, tame: 50),
            off,
            off,
        ], fx: fx(reverb: 0.25, size: 0.45)),

        patch("Vibes", "Mallets", alg: 5, [
            op(1, 99, r: [99, 38, 28, 45], l: [99, 80, 0, 0], vel: 2, ams: 2),
            op(4, 68, r: [99, 50, 30, 50], l: [99, 50, 0, 0], vel: 4, tame: 35),
            op(1, 94, r: [99, 38, 28, 45], l: [99, 80, 0, 0], vel: 2, det: 2, ams: 2),
            op(4, 64, r: [99, 50, 30, 50], l: [99, 50, 0, 0], vel: 4, det: -2, tame: 35),
            op(4, 74, r: [99, 60, 40, 50], l: [99, 0, 0, 0], vel: 3, ams: 2),
            op(1, 55, r: [99, 60, 40, 50], l: [99, 0, 0, 0]),
        ], lfo: Patch.LFO(wave: 4, speed: 30, ampDepth: 55),
           fx: fx(reverb: 0.35, size: 0.6)),
    ]

    // MARK: Brass and leads

    private static let brassAndLeads: [Patch] = [
        patch("Brass Section", "Brass & Lead", alg: 22, fb: 7, [
            op(1, 96, r: [60, 40, 30, 60], l: [99, 92, 88, 0], vel: 2),
            op(1, 78, r: [52, 40, 30, 60], l: [99, 85, 75, 0], vel: 4),
            op(1, 94, r: [60, 40, 30, 60], l: [99, 92, 88, 0], vel: 2, det: -2),
            op(1, 94, r: [60, 40, 30, 60], l: [99, 92, 88, 0], vel: 2, det: 2),
            op(2, 84, r: [58, 40, 30, 60], l: [99, 88, 80, 0], vel: 3),
            op(1, 80, r: [50, 35, 30, 60], l: [99, 82, 72, 0], vel: 5),
        ], lfo: Patch.LFO(speed: 33, delay: 40, pitchDepth: 8),
           fx: fx(chorus: 0.25, reverb: 0.28, size: 0.55)),

        patch("Razor Lead", "Brass & Lead", alg: 18, fb: 7, [
            op(1, 99, r: [90, 60, 40, 65], l: [99, 95, 92, 0], vel: 2),
            op(2, 70, r: [90, 55, 40, 65], l: [99, 80, 70, 0], vel: 3),
            op(1, 84, r: [90, 60, 40, 65], l: [99, 95, 90, 0], vel: 3),
            op(1, 60, r: [90, 60, 40, 65], l: [99, 90, 85, 0], det: 3),
            off,
            off,
        ], lfo: Patch.LFO(speed: 36, delay: 45, pitchDepth: 12),
           fx: fx(delay: 0.25, time: 0.38, feedback: 0.4, reverb: 0.2)),

        patch("Breath Flute", "Brass & Lead", alg: 5, fb: 7, [
            op(1, 99, r: [58, 50, 35, 55], l: [99, 95, 92, 0], vel: 2),
            op(1, 62, r: [65, 50, 35, 55], l: [99, 80, 70, 0], vel: 3),
            op(2, 70, r: [55, 50, 35, 55], l: [99, 80, 70, 0], vel: 2),
            op(2, 50, r: [60, 50, 35, 55], l: [99, 80, 70, 0]),
            op(1, 66, r: [80, 60, 40, 60], l: [99, 30, 15, 0], vel: 4),
            op(9.37, 86, r: [80, 60, 40, 60], l: [99, 60, 40, 0]),
        ], lfo: Patch.LFO(wave: 4, speed: 32, delay: 50, pitchDepth: 10),
           fx: fx(reverb: 0.35, size: 0.6)),
    ]

    // MARK: Pads

    private static let pads: [Patch] = [
        patch("Warm Strings", "Pads", alg: 2, fb: 7, [
            op(1, 97, r: [45, 40, 30, 45], l: [99, 96, 94, 0], vel: 1, det: -2),
            op(1, 76, r: [50, 40, 30, 45], l: [99, 90, 85, 0], vel: 2),
            op(1, 96, r: [42, 40, 30, 45], l: [99, 96, 94, 0], vel: 1, det: 3),
            op(1, 74, r: [48, 40, 30, 45], l: [99, 90, 85, 0], vel: 2, det: -1),
            op(2, 62, r: [48, 40, 30, 45], l: [99, 85, 75, 0]),
            op(3, 50, r: [48, 40, 30, 45], l: [99, 80, 70, 0]),
        ], lfo: Patch.LFO(speed: 30, delay: 30, pitchDepth: 6),
           fx: fx(chorus: 0.6, reverb: 0.35, size: 0.65)),

        patch("Glass Pad", "Pads", alg: 19, fb: 4, [
            op(1, 96, r: [35, 35, 25, 40], l: [99, 95, 90, 0], vel: 1),
            op(2, 68, r: [30, 30, 25, 40], l: [99, 90, 80, 0]),
            op(1, 60, r: [30, 30, 25, 40], l: [99, 90, 80, 0]),
            op(2, 88, r: [32, 35, 25, 40], l: [99, 95, 90, 0], vel: 1, det: 3),
            op(1, 92, r: [32, 35, 25, 40], l: [99, 95, 90, 0], vel: 1, det: -3),
            op(5, 66, r: [28, 30, 22, 40], l: [99, 70, 50, 0], tame: 30),
        ], lfo: Patch.LFO(wave: 4, speed: 22, delay: 20, pitchDepth: 4),
           fx: fx(chorus: 0.5, delay: 0.2, time: 0.45, feedback: 0.45, reverb: 0.5, size: 0.8)),

        patch("Deep Space", "Pads", alg: 31, fb: 5, [
            op(1, 96, r: [25, 30, 20, 30], l: [99, 96, 92, 0], det: -7),
            op(1, 96, r: [22, 30, 20, 30], l: [99, 96, 92, 0], det: 7),
            op(0.5, 92, r: [28, 30, 20, 30], l: [99, 96, 92, 0]),
            op(2, 78, r: [18, 30, 20, 30], l: [99, 90, 80, 0], det: 4),
            op(3, 72, r: [16, 25, 20, 30], l: [99, 85, 70, 0], det: -4),
            op(7, 64, r: [14, 22, 18, 30], l: [99, 80, 40, 0], tame: 30),
        ], lfo: Patch.LFO(wave: 4, speed: 12, pitchDepth: 3),
           fx: fx(chorus: 0.4, delay: 0.25, time: 0.6, feedback: 0.55, reverb: 0.6, size: 0.95, damp: 0.5)),
    ]

    // MARK: Plucks

    private static let plucks: [Patch] = [
        patch("Nylon Pluck", "Plucks", alg: 8, fb: 3, [
            op(1, 99, r: [99, 45, 32, 50], l: [99, 60, 0, 0], vel: 3),
            op(1, 78, r: [99, 60, 35, 50], l: [99, 40, 0, 0], vel: 4),
            op(2, 80, r: [99, 50, 35, 50], l: [99, 40, 0, 0], vel: 3),
            op(3, 66, r: [99, 65, 40, 50], l: [99, 30, 0, 0], vel: 4, tame: 30),
            op(1, 60, r: [99, 60, 40, 50], l: [99, 30, 0, 0]),
            off,
        ], fx: fx(reverb: 0.3, size: 0.55)),

        patch("Echo Pluck", "Plucks", alg: 5, fb: 6, [
            op(1, 99, r: [99, 55, 38, 55], l: [99, 40, 0, 0], vel: 3),
            op(2, 82, r: [99, 68, 40, 55], l: [99, 30, 0, 0], vel: 5),
            op(1, 92, r: [99, 55, 38, 55], l: [99, 40, 0, 0], vel: 3, det: 3),
            op(2, 78, r: [99, 68, 40, 55], l: [99, 30, 0, 0], vel: 5, det: -2),
            op(2, 80, r: [99, 62, 40, 55], l: [99, 0, 0, 0], vel: 3),
            op(1, 74, r: [99, 62, 40, 55], l: [99, 20, 0, 0], vel: 4),
        ], fx: fx(chorus: 0.2, delay: 0.38, time: 0.33, feedback: 0.5, reverb: 0.25)),
    ]
}

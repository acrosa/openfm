// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// A complete, playable OpenFM interface in one file, built only on
/// OpenFMCore and stock SwiftUI controls.
///
/// It exists as a starting point: copy this target, rename it, and build
/// whatever you like. Run the app with `-openfm.interface minimal` to see it.
///
/// What it uses from the core:
///   presets.all / presets.neighbor(of:offset:)   the sound library
///   synth.load(_:presetID:)                      load a sound
///   synth.value(_:) / synth.set(_:to:)           read and write any parameter or macro
///   synth.beginEditing / endEditing              group a gesture (enables host automation)
///   synth.noteOn / noteOff                       play
public struct MinimalInterface: View {
    private let synth: SynthModel
    private let presets: PresetStore

    public init(synth: SynthModel, presets: PresetStore) {
        self.synth = synth
        self.presets = presets
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Sound picker.
            HStack {
                Button("Previous", systemImage: "chevron.left") { step(-1) }.labelStyle(.iconOnly)
                Text(synth.name).font(.title2.bold()).frame(maxWidth: .infinity)
                Button("Next", systemImage: "chevron.right") { step(1) }.labelStyle(.iconOnly)
            }

            // Macros (-1...1) and ordinary parameters use the same two calls.
            Form {
                ForEach(Macro.all) { macro in
                    LabeledContent(macro.caption.capitalized) {
                        Slider(value: Binding(get: { synth.value(macro) }, set: { synth.set(macro, to: $0) }), in: -1...1)
                    }
                }
                slider("Reverb", .reverbMix)
                slider("Algorithm", .algorithm)
                slider("Feedback", .feedback)
            }

            // One octave of keys.
            HStack(spacing: 4) {
                ForEach([60, 62, 64, 65, 67, 69, 71, 72], id: \.self) { note in
                    Key(note: note, synth: synth)
                }
            }
            .frame(height: 120)
        }
        .padding()
    }

    private func step(_ offset: Int) {
        if let preset = presets.neighbor(of: synth.presetID, offset: offset) {
            synth.load(preset.patch, presetID: preset.id)
        }
    }

    private func slider(_ title: String, _ param: Param) -> some View {
        LabeledContent("\(title)  \(synth.string(param))") {
            Slider(value: Binding(get: { synth.value(param) }, set: { synth.set(param, to: $0) }),
                   in: param.range, step: param.isStepped ? 1 : 0.01) { editing in
                if editing { synth.beginEditing(param) } else { synth.endEditing() }
            }
        }
    }
}

private struct Key: View {
    let note: Int
    let synth: SynthModel
    @State private var down = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(down ? Color.accentColor : Color.primary.opacity(0.12))
            .overlay(alignment: .bottom) { Text(Param.noteName(midi: note)).font(.caption).padding(8) }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down {
                            down = true
                            synth.noteOn(note, velocity: 100)
                        }
                    }
                    .onEnded { _ in
                        down = false
                        synth.noteOff(note)
                    }
            )
            .accessibilityLabel("Key \(Param.noteName(midi: note))")
            .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

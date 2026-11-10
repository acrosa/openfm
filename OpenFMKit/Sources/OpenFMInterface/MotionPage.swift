// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// Movement shared by the whole voice: LFO, pitch envelope and tuning.
struct MotionPage: View {
    @Environment(SynthModel.self) private var model
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "LFO", detail: model.string(.lfoWave))
                LFOPreview()
                    .frame(height: 96)
                FieldGrid(columns: columns) {
                    DragField(param: .lfoWave)
                    DragField(param: .lfoSpeed)
                    DragField(param: .lfoDelay)
                    DragField(param: .lfoPitchDepth)
                    DragField(param: .lfoAmpDepth)
                    DragField(param: .pitchModSens)
                    DragField(param: .lfoSync)
                    FieldSpacer()
                }
            }

            MoreSection(title: "Pitch envelope", detail: "CENTRE = NO CHANGE", key: "pitchEnvelope") {
                EnvelopeEditor(rates: (1...4).map(Param.pitchRate), levels: (1...4).map(Param.pitchLevel),
                               bipolar: true, title: "PITCH ENVELOPE")
                FieldGrid(columns: columns) {
                    ForEach((1...4).map(Param.pitchRate) + (1...4).map(Param.pitchLevel), id: \.address) {
                        DragField(param: $0)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Voice")
                FieldGrid(columns: columns) {
                    DragField(param: .transpose)
                    DragField(param: .bendRange)
                    DragField(param: .keySync, caption: "OSC SYNC")
                    DragField(param: .volume)
                    if columns >= 8 {
                        ForEach(0..<4, id: \.self) { _ in FieldSpacer() }
                    }
                }
            }
        }
    }
}

/// The LFO as it will play: its shape, how fast it cycles and how the delay
/// fades it in.
private struct LFOPreview: View {
    @Environment(SynthModel.self) private var model

    var body: some View {
        let wave = Int(model.value(.lfoWave))
        let speed = model.value(.lfoSpeed)
        let delay = model.value(.lfoDelay)
        let depth = max(model.value(.lfoPitchDepth), model.value(.lfoAmpDepth)) / 99
        let active = model.focus.map { (137...143).contains($0.address) } ?? false

        Canvas { context, size in
            let mid = size.height / 2
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: mid))
            axis.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(axis, with: .color(Theme.line), lineWidth: 1)

            let cycles = 1 + speed / 99 * 11
            let fadeEnd = delay / 99 * 0.7
            let amplitude = (mid - 12) * (0.25 + 0.75 * depth)
            var path = Path()
            let steps = Int(size.width)
            guard steps > 1 else { return }
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let phase = (t * cycles).truncatingRemainder(dividingBy: 1)
                var y: Double
                switch wave {
                case 0: y = phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase
                case 1: y = 1 - 2 * phase
                case 2: y = 2 * phase - 1
                case 3: y = phase < 0.5 ? 1 : -1
                case 4: y = sin(2 * .pi * phase)
                default:
                    // Sample and hold: a repeatable pseudo-random step per cycle.
                    let n = Int(t * cycles)
                    y = Double((n &* 73 &+ 17) % 19) / 9 - 1
                }
                let fade = fadeEnd > 0 ? min(1, t / fadeEnd) : 1
                let p = CGPoint(x: CGFloat(i), y: mid - CGFloat(y * fade) * amplitude)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(active ? Theme.accent : Theme.text),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

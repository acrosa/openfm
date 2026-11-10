// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// Chorus, delay and reverb, each as a pad you move a point around in.
struct EffectsPage: View {
    let wide: Bool

    var body: some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.sectionGap))
        layout {
            EffectPad(kind: .chorus)
            EffectPad(kind: .delay)
            EffectPad(kind: .reverb)
        }
    }
}

private struct EffectPad: View {
    enum Kind {
        case chorus, delay, reverb

        var title: String {
            switch self {
            case .chorus: "Chorus"
            case .delay: "Delay"
            case .reverb: "Reverb"
            }
        }
        var mix: Param {
            switch self {
            case .chorus: .chorusMix
            case .delay: .delayMix
            case .reverb: .reverbMix
            }
        }
        var x: Param {
            switch self {
            case .chorus: .chorusRate
            case .delay: .delayTime
            case .reverb: .reverbSize
            }
        }
        var y: Param {
            switch self {
            case .chorus: .chorusDepth
            case .delay: .delayFeedback
            case .reverb: .reverbDamp
            }
        }
    }

    @Environment(SynthModel.self) private var model
    let kind: Kind
    @State private var start: (x: Double, y: Double)?
    @GestureState private var isDragging = false

    var body: some View {
        let mix = model.value(kind.mix)
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: kind.title, detail: mix > 0.005 ? nil : "OFF")
            pad
            FieldGrid(columns: 3) {
                DragField(param: kind.x)
                DragField(param: kind.y)
                DragField(param: kind.mix)
            }
        }
    }

    private var pad: some View {
        GeometryReader { geo in
            let inset: CGFloat = 18
            let w = geo.size.width - inset * 2, h = geo.size.height - inset * 2
            let nx = kind.x.normalized(model.value(kind.x)), ny = kind.y.normalized(model.value(kind.y))
            let point = CGPoint(x: inset + w * nx, y: inset + h * (1 - ny))
            let active = model.activeParams.contains(kind.x) || model.activeParams.contains(kind.y)
                || model.activeParams.contains(kind.mix)
            let on = model.value(kind.mix) > 0.005

            ZStack {
                visual(nx: nx, ny: ny, color: active ? Theme.accent : Theme.text)
                    .opacity(on ? 1 : 0.3)
                    .padding(inset)

                // Crosshair through the point.
                Path { p in
                    p.move(to: CGPoint(x: point.x, y: 0))
                    p.addLine(to: CGPoint(x: point.x, y: geo.size.height))
                    p.move(to: CGPoint(x: 0, y: point.y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: point.y))
                }
                .stroke(active ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1)

                Text("\(kind.x.caption) →")
                    .labelStyle(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
                Text("↑ \(kind.y.caption)")
                    .labelStyle(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)

                // Only the puck is draggable, and it moves with the finger
                // rather than jumping to it; the rest of the pad scrolls.
                Circle()
                    .fill(active ? Theme.accent : Theme.surface)
                    .overlay { Circle().strokeBorder(active ? Theme.accent : Theme.text, lineWidth: 1.5) }
                    .frame(width: 24, height: 24)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
                    .position(point)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($isDragging) { _, state, _ in state = true }
                            .onChanged { g in
                                if start == nil {
                                    start = (model.value(kind.x), model.value(kind.y))
                                    model.beginEditing(kind.x, with: [kind.y])
                                    Haptics.grab()
                                }
                                guard let start else { return }
                                let before = (model.value(kind.x), model.value(kind.y))
                                model.set(kind.x, to: start.x + kind.x.span * g.translation.width / w)
                                model.set(kind.y, to: start.y - kind.y.span * g.translation.height / h)
                                // The pad is silent in the middle and bumps at its walls.
                                for (p, old) in [(kind.x, before.0), (kind.y, before.1)] {
                                    let now = model.value(p)
                                    if now != old, now == p.range.lowerBound || now == p.range.upperBound { Haptics.bump() }
                                }
                                model.setReadout(title: kind.title.uppercased(),
                                                 value: "\(model.string(kind.x)) · \(model.string(kind.y))")
                            }
                    )
            }
            .onChange(of: isDragging) { _, now in
                if !now, start != nil {
                    start = nil
                    model.endEditing()
                }
            }
        }
        .frame(height: 168)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("\(kind.title) pad")
        .accessibilityHint("Drag the dot to change both values")
        .accessibilityValue("\(kind.x.caption.capitalized) \(model.string(kind.x)), \(kind.y.caption.capitalized) \(model.string(kind.y))")
    }

    /// A picture of what the effect does at the current settings.
    private func visual(nx: Double, ny: Double, color: Color) -> some View {
        let mix = model.value(kind.mix)
        return Canvas { context, size in
            switch kind {
            case .chorus:
                // Two copies drifting apart: faster with rate, wider with depth.
                for voice in 0..<2 {
                    var path = Path()
                    let steps = Int(size.width / 2)
                    guard steps > 1 else { return }
                    for i in 0...steps {
                        let t = Double(i) / Double(steps)
                        let wobble = sin(2 * .pi * (t * (1 + nx * 5) + Double(voice) * 0.25)) * ny * 0.12
                        let y = sin(2 * .pi * (t * 3 + wobble))
                        let p = CGPoint(x: size.width * t, y: size.height / 2 - y * size.height * 0.3)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(color.opacity(voice == 0 ? 0.9 : 0.4)), lineWidth: 1.5)
                }
            case .delay:
                // Each repeat: spaced by time, shrinking with feedback.
                let gap = size.width * (0.06 + 0.3 * nx)
                var level = 1.0
                var x = 0.0
                let feedback = 0.95 * ny
                while x < size.width, level > 0.02 {
                    let height = size.height * 0.8 * level
                    let rect = CGRect(x: x, y: size.height - height, width: 3, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color.opacity(x == 0 ? 0.9 : 0.6)))
                    // The dry hit, the first echo, then feedback takes over.
                    level = x == 0 ? 0.8 : level * feedback
                    x += gap
                }
            case .reverb:
                // The tail: longer with size, darker with damping.
                var bright = Path(), dark = Path()
                let steps = Int(size.width / 2)
                guard steps > 1 else { return }
                let length = 0.12 + nx * nx * 1.6
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let yb = exp(-t / length), yd = exp(-t / (length * (1 - 0.7 * ny)))
                    let pb = CGPoint(x: size.width * t, y: size.height - yb * size.height * 0.85)
                    let pd = CGPoint(x: size.width * t, y: size.height - yd * size.height * 0.85)
                    if i == 0 { bright.move(to: pb); dark.move(to: pd) } else { bright.addLine(to: pb); dark.addLine(to: pd) }
                }
                context.stroke(bright, with: .color(color), lineWidth: 1.5)
                context.stroke(dark, with: .color(color.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            }
        }
        .opacity(0.35 + 0.65 * mix)
    }
}

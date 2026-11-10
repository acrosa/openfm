// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// A four-stage DX envelope you shape directly: drag a handle sideways to
/// change how fast that stage is reached, up and down to change its level.
struct EnvelopeEditor: View {
    @Environment(SynthModel.self) private var model
    /// Rates 1...4 and levels 1...4.
    let rates: [Param]
    let levels: [Param]
    /// Pitch envelopes are centred: level 50 means no change.
    var bipolar = false
    var title = "ENVELOPE"

    @State private var start: (index: Int, rate: Double, level: Double)?
    @GestureState private var isDragging = false

    private let inset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let g = Geometry(size: geo.size, inset: inset,
                             rates: rates.map(model.value), levels: levels.map(model.value))
            ZStack {
                guides(g)
                curve(g)
                ForEach(0..<4, id: \.self) { i in
                    handle(i, g)
                }
            }
        }
        .frame(height: 156)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .onChange(of: isDragging) { _, dragging in
            if !dragging, start != nil {
                start = nil
                model.endEditing()
            }
        }
    }

    // MARK: Drawing

    private func guides(_ g: Geometry) -> some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                for fraction in [0.0, 0.5, 1.0] {
                    let y = g.y(99 * fraction)
                    p.move(to: CGPoint(x: g.left, y: y))
                    p.addLine(to: CGPoint(x: g.right, y: y))
                }
            }
            .stroke(Theme.line, lineWidth: 1)

            // Where the key is released.
            Path { p in
                p.move(to: CGPoint(x: g.keyOff.x, y: g.top))
                p.addLine(to: CGPoint(x: g.keyOff.x, y: g.bottom))
            }
            .stroke(Theme.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

            Text("KEY OFF")
                .labelStyle(9)
                .position(x: g.keyOff.x, y: 8)
        }
        .accessibilityHidden(true)
    }

    private func curve(_ g: Geometry) -> some View {
        let active = start != nil
        let baseline = bipolar ? g.y(50) : g.bottom
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: g.left, y: baseline))
                for point in g.outline { p.addLine(to: point) }
                p.addLine(to: CGPoint(x: g.right, y: baseline))
                p.closeSubpath()
            }
            .fill((active ? Theme.accent : Theme.text).opacity(active ? 0.16 : 0.07))

            Path { p in
                p.move(to: g.outline[0])
                for point in g.outline.dropFirst() { p.addLine(to: point) }
            }
            .stroke(active ? Theme.accent : Theme.text, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private func handle(_ i: Int, _ g: Geometry) -> some View {
        let active = start?.index == i
        return ZStack {
            Circle()
                .fill(active ? Theme.accent : Theme.surface)
            Circle()
                .strokeBorder(active ? Theme.accent : Theme.text, lineWidth: 1.5)
            Text("\(i + 1)")
                .font(.value(10, weight: .semibold))
                .foregroundStyle(active ? Theme.surface : Theme.text)
        }
        .frame(width: 22, height: 22)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .position(g.handles[i])
        .gesture(drag(i, g))
        .accessibilityElement()
        .accessibilityLabel("\(title.capitalized) stage \(i + 1)")
        .accessibilityValue("Rate \(Int(model.value(rates[i]))), level \(levels[i].string(model.value(levels[i])))")
        .accessibilityAdjustableAction { direction in
            model.set(levels[i], to: model.value(levels[i]) + (direction == .increment ? 5 : -5))
        }
    }

    private func drag(_ i: Int, _ g: Geometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                if start == nil {
                    start = (i, model.value(rates[i]), model.value(levels[i]))
                    model.beginEditing(levels[i], with: [rates[i]])
                    Haptics.grab()
                }
                guard let start, start.index == i else { return }
                // Left is faster: a higher rate makes a shorter segment.
                let rate = start.rate - value.translation.width / g.segment * 99
                let level = start.level - value.translation.height / g.height * 99
                let before = (model.value(rates[i]), model.value(levels[i]))
                model.set(rates[i], to: rate)
                model.set(levels[i], to: level)
                let after = (model.value(rates[i]), model.value(levels[i]))
                // One feel per move: the axis that changed, level first.
                if before.1 != after.1 {
                    Haptics.change(levels[i], from: before.1, to: after.1)
                } else {
                    Haptics.change(rates[i], from: before.0, to: after.0)
                }
                let prefix = rates[i].op.map { "OP \($0) · " } ?? ""
                model.setReadout(title: "\(prefix)\(title) STAGE \(i + 1)",
                                 value: "R\(Int(after.0)) L\(levels[i].string(after.1))")
            }
    }

    // MARK: Geometry

    /// Maps rates and levels to points. Each stage is drawn wider the slower
    /// its rate; the held sustain gets a fixed stretch before key-off.
    struct Geometry {
        let left, right, top, bottom: CGFloat
        let segment: CGFloat
        let handles: [CGPoint]
        let keyOff: CGPoint
        let outline: [CGPoint]

        var height: CGFloat { bottom - top }

        init(size: CGSize, inset: CGFloat, rates: [Double], levels: [Double]) {
            let left = inset, right = size.width - inset
            let top = inset + 4, bottom = size.height - inset
            let width = right - left
            let hold = width * 0.14
            let segment = (width - hold) / 4
            let y: (Double) -> CGFloat = { bottom - (bottom - top) * $0 / 99 }
            let w: (Double) -> CGFloat = { segment * (0.12 + 0.88 * (99 - $0) / 99) }

            var x = left
            var points: [CGPoint] = [CGPoint(x: x, y: y(levels[3]))]
            var hs: [CGPoint] = []
            for i in 0..<3 {
                x += w(rates[i])
                hs.append(CGPoint(x: x, y: y(levels[i])))
            }
            points.append(contentsOf: hs)
            x += hold
            let release = CGPoint(x: x, y: y(levels[2]))
            points.append(release)
            x += w(rates[3])
            let end = CGPoint(x: x, y: y(levels[3]))
            hs.append(end)
            points.append(end)
            points.append(CGPoint(x: right, y: end.y))

            self.left = left
            self.right = right
            self.top = top
            self.bottom = bottom
            self.segment = segment
            keyOff = release
            handles = hs
            outline = points
        }

        func y(_ level: Double) -> CGFloat { bottom - (bottom - top) * level / 99 }
    }
}

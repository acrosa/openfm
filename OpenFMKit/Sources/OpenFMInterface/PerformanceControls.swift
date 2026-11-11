// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// A touch strip beside the keyboard, standing in for a hardware wheel.
/// Drag up and down; the bender springs back to the middle when let go.
struct WheelStrip: View {
    let title: String
    let label: String
    /// -1...1 when `bipolar`, otherwise 0...1.
    let value: Double
    var bipolar = false
    let set: (Double) -> Void

    @State private var start: Double?
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 8
            let travel = max(geo.size.height - inset * 2, 1)
            let rest = bipolar ? geo.size.height / 2 : geo.size.height - inset
            let thumb = bipolar ? rest - value * travel / 2 : rest - value * travel
            let lit = isDragging || value != 0
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface)
                // From rest to where the finger has taken it.
                (lit ? Theme.accent : Theme.secondary)
                    .opacity(0.25)
                    .frame(width: geo.size.width, height: abs(thumb - rest))
                    .offset(y: min(thumb, rest))
                Theme.line.frame(height: 1).offset(y: rest)
                Capsule()
                    .fill(lit ? Theme.accent : Theme.text)
                    .frame(width: geo.size.width - 12, height: 4)
                    .offset(y: thumb - 2)
                Text(title).labelStyle(9, color: lit ? Theme.accent : Theme.secondary).padding(.top, 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { g in
                        if start == nil {
                            start = value
                            Haptics.grab()
                        }
                        guard let start else { return }
                        let moved = -g.translation.height / (bipolar ? travel / 2 : travel)
                        let next = min(max(start + moved, bipolar ? -1 : 0), 1)
                        if (next == 1 || next == -1 || (!bipolar && next == 0)), next != value { Haptics.bump() }
                        set(next)
                    }
            )
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging, start != nil {
                start = nil
                if bipolar {
                    set(0)
                    Haptics.detent()
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            set(min(max(value + (direction == .increment ? 0.1 : -0.1), bipolar ? -1 : 0), 1))
        }
    }
}

/// Pitch bend and modulation, side by side.
struct Wheels: View {
    @Environment(SynthModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            WheelStrip(title: "Bend", label: "Pitch bend", value: model.pitchBend, bipolar: true) {
                model.setPitchBend($0)
            }
            WheelStrip(title: "Mod", label: "Modulation", value: model.modWheel) {
                model.setModWheel($0)
            }
        }
        .frame(width: 92)
    }
}

/// A small latching switch for the bar above the keys.
struct BarToggle: View {
    let title: String
    let label: String
    let hint: String
    var value: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Text(title)
                .labelStyle(9, color: isOn ? Theme.background : Theme.secondary)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(isOn ? Theme.accent : Theme.surface, in: Capsule())
                .frame(minWidth: 56, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityHint(hint)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Undo and redo for edits to the sound.
struct UndoButtons: View {
    @Environment(SynthModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            button("arrow.uturn.backward", label: "Undo", enabled: model.canUndo) { model.undo() }
            button("arrow.uturn.forward", label: "Redo", enabled: model.canRedo) { model.redo() }
        }
    }

    private func button(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tick()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Theme.text : Theme.tertiary)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityHint("\(label)es the last change to the sound")
    }
}

/// How the sound rises and fades, drawn from its loudest carrier. It moves
/// with the Attack, Decay, Sustain and Release controls.
struct EnvelopeShape: View {
    @Environment(SynthModel.self) private var model

    var body: some View {
        let op = model.mainCarrier
        let rates = (0..<4).map { model.value(.op(op, Param.OpField(rawValue: $0)!)) }
        let levels = (4..<8).map { model.value(.op(op, Param.OpField(rawValue: $0)!)) }
        let active = model.activeMacro.map(Macro.envelope.contains) ?? false
        GeometryReader { geo in
            let g = EnvelopeEditor.Geometry(size: geo.size, inset: 12, rates: rates, levels: levels)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: g.keyOff.x, y: g.top))
                    p.addLine(to: CGPoint(x: g.keyOff.x, y: g.bottom))
                }
                .stroke(Theme.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                Path { p in
                    p.move(to: CGPoint(x: g.left, y: g.bottom))
                    for point in g.outline { p.addLine(to: point) }
                    p.addLine(to: CGPoint(x: g.right, y: g.bottom))
                    p.closeSubpath()
                }
                .fill((active ? Theme.accent : Theme.text).opacity(active ? 0.16 : 0.07))
                Path { p in
                    p.move(to: g.outline[0])
                    for point in g.outline.dropFirst() { p.addLine(to: point) }
                }
                .stroke(active ? Theme.accent : Theme.secondary,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                Text("KEY OFF").labelStyle(9, color: Theme.tertiary)
                    .position(x: min(g.keyOff.x, geo.size.width - 36), y: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// The left-hand panel: algorithm number, feedback, the routing diagram and
/// a preview of the resulting waveform.
struct AlgorithmPanel: View {
    @Environment(SynthModel.self) private var model
    var compact = false
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                AlgorithmScrubber(showPicker: $showPicker)
                Spacer(minLength: 0)
                FieldGrid(columns: 1) {
                    DragField(param: .feedback)
                }
                .frame(width: 112)
            }

            AlgorithmGraph()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, compact ? 4 : 12)

            // How to use the diagram, right where the diagram is.
            Text("DRAG AN OPERATOR   ↑ LEVEL   → RATIO   ·   DOUBLE-TAP ON / OFF")
                .labelStyle(9)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, compact ? 4 : 12)

            if !compact {
                Text("WAVE").labelStyle(9)
                    .frame(height: 16)
                    .padding(.bottom, 8)
                WavePreview()
                    .frame(height: 64)
            }
        }
        .padding(Theme.gutter)
        .sheet(isPresented: $showPicker) {
            AlgorithmPicker()
                .presentationDetents([.medium, .large])
        }
    }
}

/// The algorithm number. Drag sideways to scrub through all 32 while the
/// diagram rearranges; tap to see them all at once.
private struct AlgorithmScrubber: View {
    @Environment(SynthModel.self) private var model
    @Binding var showPicker: Bool
    @State private var startValue: Double?
    @GestureState private var isDragging = false

    var body: some View {
        let active = model.focus == .algorithm
        let algorithm = model.algorithm
        VStack(alignment: .leading, spacing: 4) {
            Text("ALGORITHM").labelStyle(9, color: active ? Theme.accent : Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", algorithm.number))
                    .font(.display(40))
                    .kerning(-1.2)
                    .foregroundStyle(active ? Theme.accent : Theme.text)
                Image(systemName: "chevron.left.chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(height: 44, alignment: .bottom)
        }
        .frame(height: Theme.cell, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { g in
                    if startValue == nil {
                        startValue = model.value(.algorithm)
                        model.beginEditing(.algorithm)
                    }
                    guard let startValue else { return }
                    let before = model.value(.algorithm)
                    model.set(.algorithm, to: startValue + (g.translation.width - g.translation.height) / 16)
                    Haptics.change(.algorithm, from: before, to: model.value(.algorithm))
                }
        )
        .simultaneousGesture(TapGesture().onEnded { showPicker = true })
        .onChange(of: isDragging) { _, dragging in
            if !dragging, startValue != nil {
                startValue = nil
                model.endEditing()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Algorithm")
        .accessibilityValue("\(algorithm.number), \(model.hint(.algorithm))")
        .accessibilityAdjustableAction { direction in
            model.set(.algorithm, to: model.value(.algorithm) + (direction == .increment ? 1 : -1))
        }
        .accessibilityAction(named: "Show all algorithms") { showPicker = true }
    }
}

/// One cycle of the sound at full level, redrawn as you edit.
struct WavePreview: View {
    @Environment(SynthModel.self) private var model

    var body: some View {
        let wave = Algorithm.previewWave(bytes: model.bytes)
        let active = model.focus != nil
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let mid = size.height / 2
                var axis = Path()
                axis.move(to: CGPoint(x: 0, y: mid))
                axis.addLine(to: CGPoint(x: size.width, y: mid))
                context.stroke(axis, with: .color(Theme.line), lineWidth: 1)
                guard wave.count > 1 else { return }
                var path = Path()
                for (i, sample) in wave.enumerated() {
                    let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(wave.count - 1),
                                    y: mid - CGFloat(sample) * (mid - 8))
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                context.stroke(path, with: .color(active ? Theme.accent : Theme.text),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// All 32 algorithms on one sheet.
struct AlgorithmPicker: View {
    @Environment(SynthModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    ForEach(Algorithm.all, id: \.number) { algorithm in
                        let selected = model.algorithm.number == algorithm.number
                        Button {
                            model.beginEditing(.algorithm)
                            model.set(.algorithm, to: Double(algorithm.number - 1))
                            model.endEditing()
                            Haptics.tick()
                        } label: {
                            VStack(spacing: 6) {
                                AlgorithmGlyph(algorithm: algorithm, color: selected ? Theme.accent : Theme.text)
                                    .frame(height: 52)
                                Text(String(format: "%02d", algorithm.number))
                                    .font(.value(12))
                                    .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                            }
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                    .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Algorithm \(algorithm.number), \(algorithm.carriers.count) carriers")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                .padding(Theme.gutter)
            }
            .background(Theme.background)
            .navigationTitle("Algorithm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }
}

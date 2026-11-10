// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// Everything about the selected operator.
struct OperatorPage: View {
    @Environment(SynthModel.self) private var model
    /// 8 on wide layouts, 4 on narrow ones.
    let columns: Int

    var body: some View {
        let op = model.selectedOp
        let role = model.algorithm.isCarrier(op) ? "CARRIER" : "MODULATOR"

        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            OperatorSelector()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Envelope", detail: "OP \(op) · \(role)")
                EnvelopeEditor(rates: (0..<4).map { .op(op, Param.OpField(rawValue: $0)!) },
                               levels: (4..<8).map { .op(op, Param.OpField(rawValue: $0)!) })
                FieldGrid(columns: columns) {
                    ForEach(0..<8, id: \.self) { i in
                        DragField(param: .op(op, Param.OpField(rawValue: i)!))
                    }
                }
            }

            if columns >= 8 {
                HStack(alignment: .top, spacing: 16) {
                    frequency(op)
                    level(op)
                }
            } else {
                frequency(op)
                level(op)
            }

            MoreSection(title: "Keyboard scaling", detail: "LEVEL ACROSS THE KEYS", key: "scaling") {
                FieldGrid(columns: columns) {
                    DragField(param: .op(op, .leftCurve))
                    DragField(param: .op(op, .leftDepth))
                    DragField(param: .op(op, .breakpoint))
                    DragField(param: .op(op, .rightDepth))
                    DragField(param: .op(op, .rightCurve))
                    ForEach(0..<3, id: \.self) { _ in FieldSpacer() }
                }
            }
        }
    }

    private func frequency(_ op: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Frequency", detail: model.frequencyText(op))
            FieldGrid(columns: 4) {
                DragField(param: .op(op, .mode))
                DragField(param: .op(op, .coarse))
                DragField(param: .op(op, .fine))
                DragField(param: .op(op, .detune))
            }
        }
    }

    private func level(_ op: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Level", detail: model.isOn(op) ? nil : "OFF")
            FieldGrid(columns: 4) {
                DragField(param: .op(op, .level))
                DragField(param: .op(op, .velocitySens))
                DragField(param: .op(op, .ampModSens))
                DragField(param: .op(op, .rateScaling))
            }
        }
    }
}

/// Six tabs, one per operator, each showing its level at a glance.
struct OperatorSelector: View {
    @Environment(SynthModel.self) private var model

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...6, id: \.self) { op in
                let selected = model.selectedOp == op
                let on = model.isOn(op)
                // On a phone the diagram is on another page, so the tabs
                // carry the "what does this affect" highlight.
                let affected = model.affectedOps.contains(op)
                Button {
                    model.selectedOp = op
                    Haptics.tick()
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(op)")
                                .font(.value(17, weight: .semibold))
                                .foregroundStyle(selected || affected ? Theme.accent : Theme.text)
                            Spacer(minLength: 0)
                            Text(model.algorithm.isCarrier(op) ? "C" : "M")
                                .labelStyle(9)
                        }
                        Spacer(minLength: 0)
                        // Output level.
                        Theme.line
                            .frame(height: 2)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    (selected || affected ? Theme.accent : Theme.secondary)
                                        .frame(width: geo.size.width * model.value(.op(op, .level)) / 99)
                                }
                            }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                    .background(selected ? Theme.raised : Theme.surface)
                    .opacity(on ? 1 : 0.45)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Operator \(op), \(model.algorithm.isCarrier(op) ? "carrier" : "modulator")")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .background(Theme.line)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// The simple side of the instrument: see the sound, shape it with eight
/// controls, pick another, get more in. Everything else lives behind Edit.
///
/// On a large screen the sound list is always there, like a preset player.
/// On a phone it opens as a sheet and the header arrows step through it.
struct PlayPage: View {
    @Environment(SynthModel.self) private var model
    @Environment(PresetStore.self) private var store
    let wide: Bool
    /// iPad portrait: there is height to spare, so the scope takes it.
    var tall = false
    @Binding var showBrowser: Bool

    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        Group {
            if wide {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: Theme.sectionGap) {
                        output
                        controls
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    VStack(spacing: 8) {
                        SoundList()
                        HStack(spacing: 8) {
                            importButton
                            SaveMenu()
                        }
                    }
                    .frame(maxWidth: 380)
                }
                .padding(Theme.gutter)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.sectionGap) {
                        VStack(spacing: 8) {
                            output
                            HStack(spacing: 8) {
                                QuietButton(title: "Sounds", symbol: "square.grid.2x2") { showBrowser = true }
                                importButton
                                SaveMenu()
                            }
                        }
                        controls
                    }
                    .padding(Theme.gutter)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: PresetBrowser.importTypes) { result in
            importError = SoundActions.importFile(result, into: store, model: model)
        }
        .alert("Couldn’t Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private var importButton: some View {
        QuietButton(title: "Import", symbol: "tray.and.arrow.down") { isImporting = true }
            .accessibilityHint("Imports DX7 SysEx or OpenFM patch files")
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Output").labelStyle(10, color: Theme.text)
                Spacer(minLength: 8)
                OperatorMarks()
            }
            .frame(height: 16)
            // Live output while playing; the predicted wave when silent, so
            // the Shape controls show their effect even before a key is pressed.
            ScopeView(idleWave: Algorithm.previewWave(bytes: model.bytes))
                .padding(16)
                .frame(maxWidth: .infinity)
                .frame(height: tall ? 320 : (wide ? 168 : 112))
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Shape", detail: model.macroValues.values.contains { $0 != 0 } ? "ADJUSTED" : nil)
                FieldGrid(columns: 4) {
                    ForEach(Macro.all) { MacroField(macro: $0) }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Space")
                FieldGrid(columns: 4) {
                    DragField(param: .chorusMix, caption: "CHORUS")
                    DragField(param: .delayMix, caption: "ECHO")
                    DragField(param: .reverbMix, caption: "REVERB")
                    DragField(param: .volume)
                }
            }
        }
    }
}

/// A caption button that stays out of the way.
struct QuietButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
            Haptics.tick()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).labelStyle(10, color: Theme.text)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// A macro as a value cell. Zero sits in the middle: drag right for more,
/// left for less, double-tap to return to the designed sound.
struct MacroField: View {
    @Environment(SynthModel.self) private var model
    let macro: Macro

    @State private var startValue: Double?

    var body: some View {
        let value = model.value(macro)
        let active = model.activeMacro == macro || model.peek == .macro(macro)

        VStack(alignment: .leading, spacing: 0) {
            Text(macro.caption).labelStyle(9, color: active ? Theme.accent : Theme.secondary)
            Spacer(minLength: 0)
            Text(macro.string(value))
                .font(.value(17))
                .foregroundStyle(active ? Theme.accent : Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, minHeight: Theme.cell, maxHeight: Theme.cell, alignment: .leading)
        .background(active ? Theme.raised : Theme.surface)
        .overlay(alignment: .bottom) {
            // The bar grows from the centre detent in the direction of the offset.
            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack(alignment: .bottomLeading) {
                    Theme.line.frame(height: 2)
                    (active ? Theme.accent : Theme.secondary)
                        .frame(width: abs(value) * half, height: 2)
                        .offset(x: value < 0 ? half * (1 + value) : half)
                    Theme.text.frame(width: 2, height: 6).offset(x: half - 1)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 6)
        }
        .contentShape(Rectangle())
        .gesture(HorizontalDrag(onChanged: drag, onEnded: endDrag))
        .onTapGesture(count: 2) {
            model.set(macro, to: 0)
            model.peek(macro)
            Haptics.detent()
        }
        .onTapGesture { model.peek(macro) }
        .accessibilityElement()
        .accessibilityLabel(macro.caption.capitalized)
        .accessibilityValue(macro.string(value))
        .accessibilityHint("\(macro.hint). Drag sideways to change, double-tap to reset")
        .accessibilityAdjustableAction { direction in
            model.set(macro, to: value + (direction == .increment ? 0.1 : -0.1))
        }
    }

    private func drag(_ distance: CGFloat) {
        if startValue == nil {
            startValue = model.value(macro)
            model.beginEditing(macro)
        }
        guard let startValue else { return }
        let before = Int((model.value(macro) * 50).rounded())
        model.set(macro, to: startValue + distance / 140)
        let after = Int((model.value(macro) * 50).rounded())
        if after != before {
            // Zero is home: it has its own, firmer click.
            if after == 0 { Haptics.detent() }
            else if abs(after) == 50 { Haptics.bump() }
            else if after % 5 == 0 { Haptics.tick() }
        }
    }

    private func endDrag() {
        guard startValue != nil else { return }
        startValue = nil
        model.endEditing()
    }
}

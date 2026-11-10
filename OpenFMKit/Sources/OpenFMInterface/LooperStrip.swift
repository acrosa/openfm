// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// The loop recorder, as one strip above the keyboard.
///
/// Record → a one-bar count → play for one loop → it loops by itself. Pick
/// another sound and record again to add a layer; every layer keeps the sound
/// it was recorded with. Tap a layer to mute it, hold it to clear it.
struct LooperStrip: View {
    @Environment(SynthModel.self) private var model
    let looper: Looper
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 8) {
            recordButton
            playButton
            ForEach(looper.layers) { layer in
                LayerTile(looper: looper, layer: layer)
            }
            settingsButton
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 56)
        .onChange(of: looper.countIn) { _, beat in
            if beat != nil { Haptics.tick() }
        }
        .onChange(of: looper.recordingLayer) { old, new in
            if new != nil {
                Haptics.tap()
            } else if let old, looper.layers[old].hasContent {
                // The pass is over and the layer took.
                Haptics.success()
                model.post(title: "LOOP \(old + 1)", value: looper.layers[old].sound ?? "Recorded")
            }
        }
    }

    private var recordButton: some View {
        let recording = looper.recordingLayer != nil
        let waiting = looper.armedLayer != nil
        let full = looper.nextFreeLayer == nil && !recording && !waiting
        return Button {
            if let layer = looper.record() {
                model.post(title: "LOOP \(layer + 1)", value: looper.isPlaying ? "Starts next time round" : "Counting in")
                Haptics.tap()
            } else {
                Haptics.bump()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(recording ? Theme.accent : Theme.surface)
                if let count = looper.countIn {
                    Text("\(count)").font(.value(17, weight: .bold)).foregroundStyle(Theme.accent)
                } else {
                    Circle()
                        .fill(recording ? Theme.background : (waiting ? Theme.accent : Theme.text))
                        .frame(width: 14, height: 14)
                        .opacity(full ? 0.3 : 1)
                }
            }
            .frame(width: 52, height: 44)
            .overlay {
                if waiting {
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(recording || waiting)
        .accessibilityLabel("Record loop")
        .accessibilityValue(recording ? "Recording" : (waiting ? "Waiting" : (full ? "All four loops are full" : "Ready")))
        .accessibilityHint("Counts in one bar, then records one loop with the current sound")
    }

    private var playButton: some View {
        let running = looper.isPlaying || looper.isCountingIn
        return Button {
            looper.togglePlay()
            Haptics.tap()
        } label: {
            Image(systemName: running ? "stop.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 52, height: 44)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .opacity(running || looper.hasContent ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!running && !looper.hasContent)
        .accessibilityLabel(running ? "Stop loops" : "Play loops")
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
            Haptics.tick()
        } label: {
            VStack(spacing: 2) {
                Text("\(Int(looper.tempo))").font(.value(15)).foregroundStyle(Theme.text)
                Text("BPM").labelStyle(8)
            }
            .frame(width: 52, height: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Loop settings")
        .accessibilityValue("\(Int(looper.tempo)) beats per minute, \(looper.bars) bars")
        .popover(isPresented: $showSettings) {
            LooperSettings(looper: looper)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// One loop layer: its number, the sound it holds, and a playhead.
private struct LayerTile: View {
    let looper: Looper
    let layer: Looper.Layer

    var body: some View {
        let recording = looper.recordingLayer == layer.id
        let waiting = looper.armedLayer == layer.id
        let playing = looper.isPlaying && layer.hasContent && !layer.isMuted

        Button {
            if layer.hasContent {
                looper.toggleMute(layer.id)
                Haptics.tap()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(layer.id + 1)")
                    .font(.value(13, weight: .semibold))
                    .foregroundStyle(recording ? Theme.background : (layer.hasContent ? Theme.accent : Theme.tertiary))
                Text(caption(recording: recording, waiting: waiting))
                    .font(.value(12))
                    .foregroundStyle(recording ? Theme.background : (layer.hasContent ? Theme.text : Theme.tertiary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .background(recording ? Theme.accent : Theme.surface)
            .overlay(alignment: .bottomLeading) {
                // Where the loop is.
                GeometryReader { geo in
                    Theme.accent
                        .frame(width: geo.size.width * (playing ? looper.progress : 0), height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay {
                if waiting {
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5)
                }
            }
            .opacity(layer.isMuted ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if layer.hasContent {
                Button(layer.isMuted ? "Unmute" : "Mute", systemImage: layer.isMuted ? "speaker.wave.2" : "speaker.slash") {
                    looper.toggleMute(layer.id)
                }
                Button("Clear Loop", systemImage: "trash", role: .destructive) {
                    looper.clear(layer.id)
                    Haptics.tap()
                }
            }
        }
        .accessibilityLabel("Loop \(layer.id + 1)")
        .accessibilityValue(value(recording: recording, waiting: waiting))
        .accessibilityHint(layer.hasContent ? "Tap to mute. Touch and hold to clear" : "")
        .accessibilityAction(named: "Clear") { looper.clear(layer.id) }
    }

    private func caption(recording: Bool, waiting: Bool) -> String {
        if recording { return "REC" }
        if waiting { return "NEXT" }
        return layer.hasContent ? (layer.sound ?? "Loop") : "—"
    }

    private func value(recording: Bool, waiting: Bool) -> String {
        if recording { return "Recording" }
        if waiting { return "Waiting to record" }
        guard layer.hasContent else { return "Empty" }
        return "\(layer.sound ?? "Loop")\(layer.isMuted ? ", muted" : "")"
    }
}

/// Tempo, length, click and snap.
private struct LooperSettings: View {
    let looper: Looper
    @State private var startTempo: Double?

    var body: some View {
        @Bindable var looper = looper
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Loop", detail: looper.canChangeLength ? nil : "CLEAR LOOPS TO CHANGE LENGTH")
            FieldGrid(columns: 2) {
                cell("Tempo", "\(Int(looper.tempo))", active: startTempo != nil)
                    .gesture(HorizontalDrag(onChanged: { distance in
                        if startTempo == nil { startTempo = looper.tempo }
                        let next = min(max(((startTempo ?? 112) + distance / 3).rounded(), 40), 240)
                        if next != looper.tempo {
                            looper.tempo = next
                            if Int(next) % 5 == 0 { Haptics.tick() }
                        }
                    }, onEnded: { startTempo = nil }))
                    .accessibilityElement()
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(Int(looper.tempo)) beats per minute")
                    .accessibilityAdjustableAction { direction in
                        looper.tempo = min(max(looper.tempo + (direction == .increment ? 1 : -1), 40), 240)
                    }
                toggle("Bars", "\(looper.bars)", label: "Loop length in bars") {
                    guard looper.canChangeLength else { return Haptics.bump() }
                    let choices = Looper.barChoices
                    looper.bars = choices[((choices.firstIndex(of: looper.bars) ?? 0) + 1) % choices.count]
                    Haptics.tick()
                }
                .opacity(looper.canChangeLength ? 1 : 0.45)
                toggle("Click", looper.metronome ? "ON" : "OFF", label: "Metronome") {
                    looper.metronome.toggle()
                    Haptics.tap()
                }
                toggle("Snap", looper.quantize ? "ON" : "OFF", label: "Snap notes to the beat") {
                    looper.quantize.toggle()
                    Haptics.tap()
                }
            }
            Text("Drag Tempo sideways. Snap moves what you play onto the nearest sixteenth note.")
                .font(.prose(13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Clear all loops", symbol: "trash") { looper.clearAll() }
                .opacity(looper.hasContent ? 1 : 0.45)
                .disabled(!looper.hasContent)
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.background)
    }

    private func cell(_ caption: String, _ value: String, active: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption).labelStyle(9, color: active ? Theme.accent : Theme.secondary)
            Spacer(minLength: 0)
            Text(value).font(.value(17)).foregroundStyle(active ? Theme.accent : Theme.text)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, minHeight: Theme.cell, maxHeight: Theme.cell, alignment: .leading)
        .background(active ? Theme.raised : Theme.surface)
        .contentShape(Rectangle())
    }

    private func toggle(_ caption: String, _ value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { cell(caption, value) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }
}

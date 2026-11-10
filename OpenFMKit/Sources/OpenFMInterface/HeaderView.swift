// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// The top bar: which sound is loaded, what the current gesture is changing,
/// and what is coming out.
struct HeaderView: View {
    @Environment(SynthModel.self) private var model
    @Environment(PresetStore.self) private var store
    let compact: Bool
    @Binding var showBrowser: Bool
    @Binding var mode: InterfaceMode

    /// Where a swipe across the sound name began, and how far the name has
    /// been pulled since the last step.
    @State private var swipeStart: Int?
    @State private var swipeOffset: CGFloat = 0
    @GestureState private var isSwiping = false
    private let swipePitch: CGFloat = 64

    /// True while there is something to say about a control.
    private var isExplaining: Bool {
        model.focus != nil || model.activeMacro != nil || model.peek != nil
    }

    var body: some View {
        Group {
            if compact {
                // A phone has room for one thing at a time: the sound, or,
                // while a control is touched, what that control does.
                ZStack {
                    if isExplaining {
                        ReadoutView(compact: true, mode: mode)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            // A tap brings the sound name and arrows straight back.
                            .onTapGesture { model.dismissPeek() }
                            .transition(.opacity)
                    } else {
                        HStack(spacing: 4) {
                            presetBlock.frame(maxWidth: .infinity, alignment: .leading)
                            stepButton("chevron.left", label: "Previous sound", offset: -1)
                            stepButton("chevron.right", label: "Next sound", offset: 1)
                            ModeSwitch(mode: $mode).fixedSize().padding(.leading, 4)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isExplaining)
            } else {
                HStack(spacing: 20) {
                    HStack(spacing: 4) {
                        presetBlock
                        Spacer(minLength: 4)
                        stepButton("chevron.left", label: "Previous sound", offset: -1)
                        stepButton("chevron.right", label: "Next sound", offset: 1)
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                    .layoutPriority(1)
                    divider
                    ReadoutView(compact: false, mode: mode)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if mode == .edit {
                        divider
                        ScopeView().frame(width: 132, height: 44)
                    }
                    ModeSwitch(mode: $mode).fixedSize()
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: compact ? 60 : 76)
    }

    private var divider: some View {
        Theme.line.frame(width: 1, height: 44)
    }

    private var presetBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(presetCaption).labelStyle(9)
                if model.isEdited { Text("EDITED").labelStyle(9, color: Theme.accent) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.name)
                    .font(.display(compact ? 17 : 20))
                    .kerning(-0.4)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .offset(x: swipeOffset)
        .opacity(1 - min(abs(swipeOffset) / swipePitch, 1) * 0.5)
        .contentShape(Rectangle())
        // Swipe across the name to roll through the sounds, like the octave
        // dial: pull left for the next one, right for the one before.
        .onTapGesture { showBrowser = true }
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($isSwiping) { _, state, _ in state = true }
                .onChanged { g in
                    // Sideways only: a vertical drag here means nothing.
                    guard swipeStart != nil || abs(g.translation.width) > abs(g.translation.height) else { return }
                    swipe(g.translation.width)
                }
        )
        .onChange(of: isSwiping) { _, swiping in
            if !swiping {
                swipeStart = nil
                withAnimation(.snappy(duration: 0.2)) { swipeOffset = 0 }
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Sound: \(model.name)\(model.isEdited ? ", edited" : "")")
        .accessibilityHint("Opens the sound browser. Swipe sideways for the next or previous sound")
        .accessibilityAdjustableAction { direction in
            if let preset = store.neighbor(of: model.presetID, offset: direction == .increment ? 1 : -1) {
                model.load(preset.patch, presetID: preset.id)
            }
        }
    }

    private func swipe(_ distance: CGFloat) {
        let sounds = store.all
        guard !sounds.isEmpty else { return }
        if swipeStart == nil {
            swipeStart = sounds.firstIndex { $0.id == model.presetID } ?? 0
        }
        guard let swipeStart else { return }
        // One sound per `swipePitch` points; a long swipe passes several.
        let steps = Int((-distance / swipePitch).rounded(.towardZero))
        let target = ((swipeStart + steps) % sounds.count + sounds.count) % sounds.count
        if sounds[target].id != model.presetID {
            model.load(sounds[target].patch, presetID: sounds[target].id)
            Haptics.tick()
        }
        swipeOffset = (distance + CGFloat(steps) * swipePitch) * 0.5
    }

    private var presetCaption: String {
        var parts = [model.category]
        if let position = store.position(of: model.presetID) {
            parts.append(String(format: "%02d/%02d", position, store.all.count))
        }
        return parts.joined(separator: " · ")
    }

    private func stepButton(_ symbol: String, label: String, offset: Int) -> some View {
        Button {
            if let preset = store.neighbor(of: model.presetID, offset: offset) {
                model.load(preset.patch, presetID: preset.id)
                Haptics.tick()
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: compact ? 36 : 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Names the control under your finger, shows its value large, and says in
/// plain words what it does in this patch. A tap on a control shows the same
/// for a moment, with how to reset it.
struct ReadoutView: View {
    @Environment(SynthModel.self) private var model
    let compact: Bool
    let mode: InterfaceMode

    private struct Content {
        var title: String
        var value: String
        var hint: String
        var live: Bool
    }

    private var content: Content? {
        if let macro = model.activeMacro {
            return Content(title: macro.caption, value: macro.string(model.value(macro)), hint: macro.hint, live: true)
        }
        if let param = model.focus {
            let custom = model.customReadout
            return Content(title: custom?.title ?? model.title(param), value: custom?.value ?? model.readoutValue(param),
                           hint: model.hint(param), live: true)
        }
        switch model.peek {
        case .macro(let macro):
            return Content(title: macro.caption, value: macro.string(model.value(macro)),
                           hint: "\(macro.hint) · double-tap resets", live: true)
        case .param(let param):
            let binary = param.isStepped && param.span == 1
            return Content(title: model.title(param), value: model.readoutValue(param),
                           hint: "\(model.hint(param))\(binary ? "" : " · double-tap resets")", live: true)
        case .notice(let title, let value):
            return Content(title: title, value: value, hint: "", live: true)
        case nil:
            break
        }
        if let param = model.lastTouched {
            return Content(title: model.title(param), value: model.readoutValue(param), hint: model.hint(param), live: false)
        }
        return nil
    }

    var body: some View {
        Group {
            if let content, compact {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(content.title).labelStyle(9, color: Theme.accent)
                        Text(content.hint)
                            .font(.prose(13))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 8)
                    Text(content.value)
                        .font(.value(22))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .layoutPriority(1)
                }
            } else if let content {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title).labelStyle(9, color: content.live ? Theme.accent : Theme.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(content.value)
                            .font(.value(24))
                            .foregroundStyle(content.live ? Theme.text : Theme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(content.hint)
                            .font(.prose(13))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("READY").labelStyle(9)
                    Text(mode == .play ? "Drag a control sideways · tap it to see what it does"
                                       : "Drag a value sideways, or an operator in the diagram")
                        .font(.prose(15))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Live output: an oscilloscope and one mark per sounding voice.
struct ScopeView: View {
    @Environment(SynthModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Drawn while nothing is sounding, e.g. the predicted waveform.
    var idleWave: [Float] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { _ in
            Canvas { context, size in
                let count = 1024
                let samples = model.scope(count: count)
                let voices = model.activeVoices
                let scopeHeight = size.height - 10

                // Start at a rising zero crossing so the picture holds still.
                let window = 512
                var startIndex = 0
                for i in 1..<(count - window) where samples[i - 1] <= 0 && samples[i] > 0 {
                    startIndex = i
                    break
                }
                var path = Path()
                let mid = scopeHeight / 2
                if voices == 0, idleWave.count > 1 {
                    for (i, sample) in idleWave.enumerated() {
                        let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(idleWave.count - 1),
                                        y: mid - CGFloat(sample) * (mid - 2) * 0.7)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                } else {
                    for i in 0..<window {
                        let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(window - 1),
                                        y: mid - CGFloat(max(-1, min(1, samples[startIndex + i] * 1.6))) * (mid - 2))
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                let editing = model.activeMacro != nil && !idleWave.isEmpty
                context.stroke(path, with: .color(voices > 0 || editing ? Theme.accent : Theme.tertiary),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Sixteen voice marks along the bottom.
                let gap: CGFloat = 3
                let markWidth = (size.width - gap * 15) / 16
                for v in 0..<16 {
                    let rect = CGRect(x: CGFloat(v) * (markWidth + gap), y: size.height - 2, width: markWidth, height: 2)
                    context.fill(Path(rect), with: .color(v < voices ? Theme.accent : Theme.line))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Output")
    }
}

/// How much of the instrument is on screen.
public enum InterfaceMode: String, CaseIterable, Sendable {
    /// Pick a sound, shape it with a few controls, play.
    case play = "Play"
    /// The full editor: routing, operators, motion, effects.
    case edit = "Edit"
}

/// Two-position switch between the simple and the full interface.
struct ModeSwitch: View {
    @Binding var mode: InterfaceMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(InterfaceMode.allCases, id: \.self) { m in
                Button {
                    mode = m
                    Haptics.tap()
                } label: {
                    Text(m.rawValue)
                        .labelStyle(9, color: mode == m ? Theme.background : Theme.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(mode == m ? Theme.text : Color.clear, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == m ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 2)
        .background(Theme.surface.frame(height: 32).clipShape(Capsule()))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interface")
    }
}

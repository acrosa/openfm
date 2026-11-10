// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// A value cell you drag sideways: right raises the value, left lowers it.
/// Vertical movement is left alone so the page underneath can scroll.
/// A tap shows what the control is; two-state parameters flip on tap;
/// double-tap puts the value back to where the loaded sound had it.
struct DragField: View {
    @Environment(SynthModel.self) private var model
    let param: Param
    var caption: String?

    @State private var startValue: Double?

    private var isBinary: Bool { param.isStepped && param.span == 1 }

    var body: some View {
        let value = model.value(param)
        let active = model.activeParams.contains(param) || model.peek == .param(param)

        VStack(alignment: .leading, spacing: 0) {
            Text(caption ?? param.caption)
                .labelStyle(9, color: active ? Theme.accent : Theme.secondary)
            Spacer(minLength: 0)
            Text(param.string(value))
                .font(.value(17))
                .foregroundStyle(active ? Theme.accent : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, minHeight: Theme.cell, maxHeight: Theme.cell, alignment: .leading)
        .background(active ? Theme.raised : Theme.surface)
        .overlay(alignment: .bottom) {
            Theme.line
                .frame(height: 2)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        (active ? Theme.accent : Theme.tertiary)
                            .frame(width: geo.size.width * param.normalized(value))
                    }
                }
        }
        .contentShape(Rectangle())
        .gesture(HorizontalDrag(onChanged: drag, onEnded: endDrag))
        // Switches have no double-tap, so every tap on them lands at once.
        .modifier(DoubleTap(enabled: !isBinary) {
            model.beginEditing(param)
            model.restore(param)
            model.endEditing()
            model.peek(param)
            Haptics.tap()
        })
        .onTapGesture {
            if isBinary {
                model.beginEditing(param)
                model.set(param, to: model.value(param) == 0 ? 1 : 0)
                model.endEditing()
                Haptics.tap()
            }
            model.peek(param)
        }
        .accessibilityElement()
        .accessibilityLabel(model.title(param).capitalized)
        .accessibilityValue(param.string(value))
        .accessibilityHint(isBinary ? "Tap to switch" : "Drag sideways to change, double-tap to reset")
        .accessibilityAdjustableAction { direction in
            let step = param.isStepped ? 1 : param.span / 20
            model.set(param, to: value + (direction == .increment ? step : -step))
        }
    }

    private func drag(_ distance: CGFloat) {
        if startValue == nil {
            startValue = model.value(param)
            model.beginEditing(param)
        }
        guard let startValue else { return }
        // Small ranges get wide steps, large ranges a full sweep in ~220 pt.
        let pointsPerUnit = param.isStepped ? min(22, max(2.2, 220 / param.span)) : 220 / param.span
        let before = model.value(param)
        model.set(param, to: startValue + distance / pointsPerUnit)
        Haptics.change(param, from: before, to: model.value(param))
    }

    private func endDrag() {
        guard startValue != nil else { return }
        startValue = nil
        model.endEditing()
    }
}

/// Adds a double-tap only where one is wanted; a view without it responds to
/// single taps with no delay.
private struct DoubleTap: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture(count: 2, perform: action)
        } else {
            content
        }
    }
}

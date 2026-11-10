// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI
import UIKit

/// A loop's notes on a grid: time runs left to right in sixteenths, pitch
/// runs bottom to top. Tap an empty square to add a note, drag a note to move
/// it, select one to change its length or delete it. The loop keeps playing
/// while you edit.
struct LoopEditor: View {
    @Environment(\.dismiss) private var dismiss
    let looper: Looper
    let layer: Int

    @State private var notes: [LoopNote] = []
    @State private var selected: LoopNote.ID?
    @State private var drag: (id: LoopNote.ID, steps: Int, rows: Int)?

    private let gutter: CGFloat = 40

    private var steps: Int { Int(looper.lengthBeats / Looper.grid) }

    /// The pitches shown: everything in the loop plus a little room, and at
    /// least an octave and a half.
    private var range: ClosedRange<Int> {
        let low = (notes.map(\.note).min() ?? 60) - 4
        let high = (notes.map(\.note).max() ?? 60) + 4
        let pad = max(0, 18 - (high - low)) / 2
        return max(0, low - pad)...min(127, high + pad)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    grid(size: geo.size)
                }
                Theme.line.frame(height: 1)
                toolbar
            }
            .background(Theme.background)
            .navigationTitle("Loop \(layer + 1) · \(looper.layers[layer].sound ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .onAppear { notes = looper.layers[layer].notes }
    }

    // MARK: Grid

    private func grid(size: CGSize) -> some View {
        let range = range
        let rows = range.count
        let cellW = (size.width - gutter) / CGFloat(steps)
        let cellH = size.height / CGFloat(rows)

        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for (i, pitch) in range.reversed().enumerated() {
                    let y = CGFloat(i) * cellH
                    let black = [1, 3, 6, 8, 10].contains(pitch % 12)
                    context.fill(Path(CGRect(x: gutter, y: y, width: size.width - gutter, height: cellH)),
                                 with: .color(black ? Theme.background : Theme.surface))
                    if pitch % 12 == 0, cellH >= 9 {
                        context.draw(Text(Param.noteName(midi: pitch)).font(.value(9)).foregroundStyle(Theme.secondary),
                                     at: CGPoint(x: gutter / 2, y: y + cellH / 2))
                    }
                }
                for step in 0...steps {
                    let x = gutter + CGFloat(step) * cellW
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    // Bars strongest, then beats, then sixteenths.
                    let opacity = step % 16 == 0 ? 0.5 : (step % 4 == 0 ? 0.22 : 0.08)
                    context.stroke(line, with: .color(Theme.text.opacity(opacity)), lineWidth: 1)
                }
                if looper.isPlaying {
                    let x = gutter + (size.width - gutter) * looper.progress
                    var head = Path()
                    head.move(to: CGPoint(x: x, y: 0))
                    head.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(head, with: .color(Theme.accent), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { tap in
                    guard tap.location.x > gutter else { return }
                    add(step: Int((tap.location.x - gutter) / cellW), pitch: range.upperBound - Int(tap.location.y / cellH))
                }
            )
            .accessibilityLabel("Note grid")
            .accessibilityHint("Tap to add a note")

            ForEach(notes) { note in
                noteView(note, range: range, cellW: cellW, cellH: cellH)
            }
        }
    }

    private func noteView(_ note: LoopNote, range: ClosedRange<Int>, cellW: CGFloat, cellH: CGFloat) -> some View {
        let isSelected = selected == note.id
        let moving = drag?.id == note.id ? drag : nil
        let step = note.start / Looper.grid + Double(moving?.steps ?? 0)
        let row = Double(range.upperBound - note.note + (moving?.rows ?? 0))
        let width = max(CGFloat(note.length / Looper.grid) * cellW - 1, 6)

        return RoundedRectangle(cornerRadius: min(4, cellH / 3), style: .continuous)
            .fill(isSelected ? Theme.accent : Theme.text)
            .frame(width: width, height: max(cellH - 1, 4))
            // A comfortable target even when the note itself is thin.
            .frame(width: max(width, 28), height: max(cellH, 28), alignment: .leading)
            .contentShape(Rectangle())
            .offset(x: gutter + CGFloat(step) * cellW, y: CGFloat(row) * cellH - (max(cellH, 28) - cellH) / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let next = (note.id, Int((g.translation.width / cellW).rounded()), Int((g.translation.height / cellH).rounded()))
                        if drag == nil { Haptics.grab() }
                        if let drag, drag.steps != next.1 || drag.rows != next.2 { Haptics.tick() }
                        drag = next
                        selected = note.id
                    }
                    .onEnded { _ in
                        defer { drag = nil }
                        guard let drag, drag.steps != 0 || drag.rows != 0, let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
                        notes[i].start = min(max(notes[i].start + Double(drag.steps) * Looper.grid, 0), looper.lengthBeats - Looper.grid)
                        notes[i].note = min(max(notes[i].note - drag.rows, 0), 127)
                        commit()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("\(Param.noteName(midi: note.note)) at beat \(String(format: "%.2f", note.start + 1))")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAction(named: "Delete") {
                notes.removeAll { $0.id == note.id }
                commit()
            }
    }

    // MARK: Editing

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let i = notes.firstIndex(where: { $0.id == selected }) {
                Text("\(Param.noteName(midi: notes[i].note))  ·  \(lengthName(notes[i].length))")
                    .font(.value(13))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                tool("Shorter", "minus") {
                    notes[i].length = max(notes[i].length - Looper.grid, Looper.grid)
                    commit()
                }
                tool("Longer", "plus") {
                    notes[i].length = min(notes[i].length + Looper.grid, looper.lengthBeats - notes[i].start)
                    commit()
                }
                tool("Delete", "trash") {
                    notes.remove(at: i)
                    selected = nil
                    commit()
                }
            } else {
                Text("Tap the grid to add a note · drag a note to move it · select it to resize or delete")
                    .font(.prose(13))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 64)
    }

    private func tool(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tick()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 52, height: 44)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func lengthName(_ beats: Double) -> String {
        let sixteenths = Int((beats / Looper.grid).rounded())
        return sixteenths == 1 ? "1 step" : "\(sixteenths) steps"
    }

    private func add(step: Int, pitch: Int) {
        let start = Double(min(max(step, 0), steps - 1)) * Looper.grid
        let note = LoopNote(start: start, length: min(Looper.grid * 2, looper.lengthBeats - start), note: min(max(pitch, 0), 127))
        notes.append(note)
        selected = note.id
        Haptics.tap()
        commit()
    }

    /// Sends the edit to the looper. Deleting the last note clears the layer.
    private func commit() {
        looper.setNotes(layer, to: notes)
        if notes.isEmpty { dismiss() }
    }
}

/// The system share sheet, for handing an exported file to another app.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file ready to share.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

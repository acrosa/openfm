// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// Saving, reverting and importing, shared by every place that offers them.
@MainActor
enum SoundActions {
    /// Saves the current sound under `name`, replacing your own sound of the
    /// same name if that is what is loaded.
    static func save(_ model: SynthModel, in store: PresetStore, as name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.rename(name)
        let existing = store.preset(id: model.presetID).flatMap { $0.isFactory || $0.patch.name != name ? nil : $0.id }
        let preset = store.save(model.patch, replacing: existing)
        model.load(preset.patch, presetID: preset.id)
        model.post(title: "SAVED", value: name)
        Haptics.success()
    }

    /// Imports a file, loads its first sound and says what arrived.
    /// - Returns: an error message to show, or nil on success.
    static func importFile(_ result: Result<URL, Error>, into store: PresetStore, model: SynthModel) -> String? {
        do {
            let url = try result.get()
            let imported = try store.importFile(at: url)
            if let first = imported.first { model.load(first.patch, presetID: first.id) }
            let count = imported.count
            model.post(title: "IMPORTED", value: count == 1 ? (imported.first?.patch.name ?? "1 sound")
                                                           : "\(count) sounds · \(url.deletingPathExtension().lastPathComponent)")
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return error.localizedDescription
        }
    }
}

/// Save and Revert in one quiet button, dimmed until there is something to keep.
struct SaveMenu: View {
    @Environment(SynthModel.self) private var model
    @Environment(PresetStore.self) private var store
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        Menu {
            Button("Save…", systemImage: "square.and.arrow.down") {
                name = model.name
                isNaming = true
            }
            Button("Revert to Original", systemImage: "arrow.uturn.backward") {
                model.revert()
                model.post(title: "REVERTED", value: model.name)
                Haptics.tap()
            }
            .disabled(!model.isEdited)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 12, weight: .semibold))
                Text("Save").labelStyle(10, color: Theme.text)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .opacity(model.isEdited ? 1 : 0.7)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Save")
        .accessibilityHint(model.isEdited ? "Save or revert your changes" : "No changes to save")
        .alert("Save Sound", isPresented: $isNaming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { SoundActions.save(model, in: store, as: name) }
        } message: {
            Text("Saved to your sounds on this device.")
        }
    }
}

/// The sound library as a permanent column, so a large screen works like a
/// preset player: tap a name, play.
struct SoundList: View {
    @Environment(SynthModel.self) private var model
    @Environment(PresetStore.self) private var store
    @State private var search = ""

    private var sections: [(title: String, presets: [Preset])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.sections }
        return store.sections.compactMap { section in
            let matches = section.presets.filter { $0.patch.name.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? nil : (section.title, matches)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Sounds", detail: "\(store.all.count)")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                TextField("Search", text: $search)
                    .font(.value(14))
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                if !search.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(sections, id: \.title) { section in
                            Text(section.title)
                                .labelStyle(9)
                                .padding(.horizontal, 12)
                                .frame(height: 32, alignment: .bottomLeading)
                                .padding(.bottom, 6)
                            ForEach(section.presets) { preset in
                                row(preset).id(preset.id)
                            }
                        }
                        if sections.isEmpty {
                            Text("No sounds match “\(search)”.")
                                .font(.prose(13))
                                .foregroundStyle(Theme.secondary)
                                .padding(12)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .onChange(of: model.presetID) { _, id in
                    if let id { withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
                }
                .onAppear {
                    if let id = model.presetID { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func row(_ preset: Preset) -> some View {
        let current = model.presetID == preset.id
        return Button {
            model.load(preset.patch, presetID: preset.id)
            Haptics.tick()
        } label: {
            HStack(spacing: 12) {
                Theme.accent.frame(width: 2, height: 20).opacity(current ? 1 : 0)
                Text(preset.patch.name)
                    .font(.value(15, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? Theme.accent : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                AlgorithmGlyph(algorithm: .number(preset.patch.algorithm), color: current ? Theme.accent : Theme.secondary)
                    .frame(width: 36, height: 24)
            }
            .padding(.trailing, 12)
            .frame(height: 44)
            .background(current ? Theme.raised : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.patch.name)
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }
}

/// Six marks, one per operator: filled for carriers, outlined for
/// modulators, lit while a gesture reaches them.
struct OperatorMarks: View {
    @Environment(SynthModel.self) private var model

    var body: some View {
        let algorithm = model.algorithm
        let affected = model.affectedOps
        HStack(spacing: 4) {
            Text(String(format: "ALG %02d", algorithm.number))
                .font(.value(11))
                .foregroundStyle(Theme.secondary)
                .padding(.trailing, 4)
            ForEach(1...6, id: \.self) { op in
                let lit = affected.contains(op)
                let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                ZStack {
                    if algorithm.isCarrier(op) {
                        shape.fill(lit ? Theme.accent : Theme.secondary)
                    } else {
                        shape.strokeBorder(lit ? Theme.accent : Theme.secondary, lineWidth: 1.5)
                    }
                }
                .frame(width: 10, height: 10)
                .opacity(model.isOn(op) ? 1 : 0.3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Algorithm \(algorithm.number), \(algorithm.carriers.count) carriers")
    }
}

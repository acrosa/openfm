// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI
import UniformTypeIdentifiers

/// Browse, audition, save and import sounds. Tapping a row loads it at once
/// so you can play it on a connected keyboard while the sheet is open.
struct PresetBrowser: View {
    @Environment(SynthModel.self) private var model
    @Environment(PresetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var isImporting = false
    @State private var isSaving = false
    @State private var saveName = ""
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.presets) { preset in
                            row(preset)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if filteredSections.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Search sounds")
            .navigationTitle("Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Save Sound…", systemImage: "square.and.arrow.down") {
                            saveName = model.name
                            isSaving = true
                        }
                        Button("Revert to Original", systemImage: "arrow.uturn.backward") {
                            model.revert()
                            Haptics.tap()
                        }
                        .disabled(!model.isEdited)
                        Button("Import Sounds…", systemImage: "tray.and.arrow.down") { isImporting = true }
                        if let file = shareFile() {
                            ShareLink("Share Sound", item: file)
                        }
                        Divider()
                        Button("New Init Voice", systemImage: "waveform") {
                            model.load(Patch())
                            dismiss()
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .alert("Save Sound", isPresented: $isSaving) {
                TextField("Name", text: $saveName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { SoundActions.save(model, in: store, as: saveName) }
            } message: {
                Text("Saved to your sounds on this device.")
            }
            .alert("Couldn’t Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: PresetBrowser.importTypes) { result in
                importError = SoundActions.importFile(result, into: store, model: model)
            }
        }
        .tint(Theme.accent)
    }

    /// Every extension a registered `PatchFormat` reads, plus plain data for
    /// files whose type the system doesn't know.
    static let importTypes: [UTType] = PatchFormats.fileExtensions.compactMap { UTType(filenameExtension: $0) } + [.data]

    /// The current sound as a shareable `.openfmpatch` file.
    private func shareFile() -> URL? {
        guard let data = try? OpenFMPatchFormat.data(for: model.patch) else { return nil }
        let safeName = model.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).\(OpenFMPatchFormat.fileExtension)")
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }

    private var filteredSections: [(title: String, presets: [Preset])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.sections }
        return store.sections.compactMap { section in
            let matches = section.presets.filter { $0.patch.name.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? nil : (section.title, matches)
        }
    }

    private func row(_ preset: Preset) -> some View {
        let current = model.presetID == preset.id
        return Button {
            model.load(preset.patch, presetID: preset.id)
            // The sheet covers the keyboard, so let the sound speak for itself.
            model.audition()
            Haptics.tick()
        } label: {
            HStack(spacing: 12) {
                AlgorithmGlyph(algorithm: .number(preset.patch.algorithm), color: current ? Theme.accent : Theme.text)
                    .frame(width: 44, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.patch.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(current ? Theme.accent : Theme.text)
                    Text(String(format: "ALG %02d · FB %d", preset.patch.algorithm, preset.patch.feedback))
                        .font(.value(11))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                if current {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current ? [.isSelected] : [])
        .swipeActions(edge: .trailing) {
            if !preset.isFactory {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    store.delete(preset)
                    Haptics.tap()
                }
            }
        }
    }
}

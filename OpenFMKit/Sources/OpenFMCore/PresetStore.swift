// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import OpenFMEngine
import Observation

public struct Preset: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public var patch: Patch
    public var isFactory = false

    private enum CodingKeys: String, CodingKey { case id, patch }
}

/// Factory sounds plus the user's own, saved as readable JSON in the app's
/// Application Support folder.
@MainActor
@Observable
public final class PresetStore {
    public private(set) var factory: [Preset]
    public private(set) var user: [Preset] = []
    @ObservationIgnored private let fileURL: URL?

    public var all: [Preset] { factory + user }

    /// - Parameter directory: where `UserPresets.json` lives; pass nil to keep
    ///   user presets in memory only.
    public init(directory: URL? = PresetStore.defaultDirectory) {
        factory = FactoryPresets.all.map { Preset(id: "factory/\($0.name)", patch: $0, isFactory: true) }
        fileURL = directory?.appendingPathComponent("UserPresets.json")
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Preset].self, from: data) {
            user = saved
        }
    }

    public static var defaultDirectory: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
    }

    /// Categories in display order, each with its presets.
    public var sections: [(title: String, presets: [Preset])] {
        var order: [String] = []
        var groups: [String: [Preset]] = [:]
        // Your own and imported sounds come first, newest bank on top.
        var mine: [Preset] = []
        var seen: [String] = []
        for p in user.reversed() where !seen.contains(p.patch.category) { seen.append(p.patch.category) }
        for category in seen { mine += user.filter { $0.patch.category == category } }
        for p in mine + factory {
            if groups[p.patch.category] == nil { order.append(p.patch.category) }
            groups[p.patch.category, default: []].append(p)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    public func preset(id: String?) -> Preset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// The preset `offset` places away from `id`, wrapping around.
    public func neighbor(of id: String?, offset: Int) -> Preset? {
        let list = all
        guard !list.isEmpty else { return nil }
        guard let i = list.firstIndex(where: { $0.id == id }) else { return list.first }
        return list[((i + offset) % list.count + list.count) % list.count]
    }

    public func position(of id: String?) -> Int? {
        all.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    @discardableResult
    public func save(_ patch: Patch, replacing id: String? = nil) -> Preset {
        var patch = patch
        if FactoryPresets.all.contains(where: { $0.category == patch.category }) { patch.category = "User" }
        if let id, let i = user.firstIndex(where: { $0.id == id }) {
            user[i].patch = patch
            persist()
            return user[i]
        }
        let preset = Preset(id: UUID().uuidString, patch: patch)
        user.append(preset)
        persist()
        return preset
    }

    public func delete(_ preset: Preset) {
        user.removeAll { $0.id == preset.id }
        persist()
    }

    /// Imports every voice of a DX7 `.syx` file as user presets.
    @discardableResult
    public func importSysEx(_ data: Data, named name: String) throws -> [Preset] {
        let patches = try SysEx.patches(from: data, category: name)
        let presets = patches.map { Preset(id: UUID().uuidString, patch: $0) }
        user.append(contentsOf: presets)
        persist()
        return presets
    }

    /// Imports every sound in a file of any format in `PatchFormats.all`.
    @discardableResult
    public func importFile(at url: URL) throws -> [Preset] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let patches = try PatchFormats.patches(from: Data(contentsOf: url), filename: url.lastPathComponent)
        // A single shared sound keeps its own category; a bank is filed under its name.
        let collection = url.deletingPathExtension().lastPathComponent
        let presets = patches.map { patch -> Preset in
            var patch = patch
            if patches.count == 1, FactoryPresets.all.contains(where: { $0.category == patch.category }) {
                patch.category = "User"
            } else if patches.count > 1 {
                patch.category = collection
            }
            return Preset(id: UUID().uuidString, patch: patch)
        }
        user.append(contentsOf: presets)
        persist()
        return presets
    }

    private func persist() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(user) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

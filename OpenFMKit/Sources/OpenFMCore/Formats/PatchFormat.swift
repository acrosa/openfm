// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A file format OpenFM can read sounds from.
///
/// To support another synth's patches, write a type that turns its bytes
/// into `Patch` values and add it to `PatchFormats.all`. Nothing else in the
/// app needs to change: the browser, "Open in OpenFM" and drag-and-drop all
/// go through this list.
public protocol PatchFormat: Sendable {
    /// Shown in import errors and documentation.
    var name: String { get }
    /// Lowercase file extensions, without the dot.
    var fileExtensions: [String] { get }
    /// - Parameter collection: the file's name, used as the category for imported sounds.
    /// - Throws: if the data is not in this format.
    func patches(from data: Data, collection: String) throws -> [Patch]
}

public enum PatchFormats {
    public static let all: [any PatchFormat] = [DX7SysExFormat(), OpenFMPatchFormat()]

    public enum ImportError: LocalizedError {
        case unrecognized

        public var errorDescription: String? {
            let names = PatchFormats.all.map(\.name).joined(separator: ", ")
            return "OpenFM couldn’t read any sounds from this file. Supported formats: \(names)."
        }
    }

    public static var fileExtensions: [String] { all.flatMap(\.fileExtensions) }

    /// Reads sounds from a file, trying the format its extension suggests first.
    public static func patches(from data: Data, filename: String) throws -> [Patch] {
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension.lowercased()
        let collection = url.deletingPathExtension().lastPathComponent
        let ordered = all.filter { $0.fileExtensions.contains(ext) } + all.filter { !$0.fileExtensions.contains(ext) }
        for format in ordered {
            if let patches = try? format.patches(from: data, collection: collection), !patches.isEmpty {
                return patches
            }
        }
        throw ImportError.unrecognized
    }
}

/// Yamaha DX7 voices: 32-voice cartridge dumps and single-voice dumps.
public struct DX7SysExFormat: PatchFormat {
    public let name = "DX7 SysEx (.syx)"
    public let fileExtensions = ["syx"]
    public init() {}

    public func patches(from data: Data, collection: String) throws -> [Patch] {
        try SysEx.patches(from: data, category: collection)
    }
}

/// OpenFM's own JSON: one patch, or a list of patches or presets.
public struct OpenFMPatchFormat: PatchFormat {
    public static let fileExtension = "openfmpatch"
    public let name = "OpenFM patch (.openfmpatch, .json)"
    public let fileExtensions = [OpenFMPatchFormat.fileExtension, "json"]
    public init() {}

    public func patches(from data: Data, collection: String) throws -> [Patch] {
        let decoder = JSONDecoder()
        if let one = try? decoder.decode(Patch.self, from: data) { return [one] }
        if let many = try? decoder.decode([Patch].self, from: data) { return many }
        return try decoder.decode([Preset].self, from: data).map(\.patch)
    }

    /// The file contents for sharing one sound.
    public static func data(for patch: Patch) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(patch)
    }
}

// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import OpenFMEngine

/// Everything a standalone app needs, in one object: the running engine,
/// the model an interface edits, and the preset library.
///
///     let session = try OpenFMSession()
///     session.start()
///     MyInterface(synth: session.synth, presets: session.presets)
///
/// `looper` is optional for an interface: it records and plays loops.
@MainActor
public final class OpenFMSession {
    public let synth: SynthModel
    public let presets: PresetStore
    public let looper: Looper
    private let host: AudioHost

    /// - Parameter initialPreset: name of the sound to load first; the first
    ///   factory sound if nil or not found.
    public init(initialPreset: String? = nil) throws {
        host = try AudioHost()
        presets = PresetStore()
        synth = SynthModel(audioUnit: host.audioUnit)
        looper = Looper(synth: synth)
        if let first = presets.all.first(where: { $0.patch.name == initialPreset }) ?? presets.all.first {
            synth.load(first.patch, presetID: first.id)
        }
    }

    /// Starts audio output and MIDI input.
    public func start() { host.start() }

    /// Imports a patch file handed to the app (Files, AirDrop, another app)
    /// and loads its first sound.
    @discardableResult
    public func open(_ url: URL) throws -> [Preset] {
        let imported = try presets.importFile(at: url)
        if let first = imported.first { synth.load(first.patch, presetID: first.id) }
        return imported
    }
}

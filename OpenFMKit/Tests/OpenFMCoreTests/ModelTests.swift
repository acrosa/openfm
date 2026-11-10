// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import XCTest
@testable import OpenFMCore
import OpenFMEngine

@MainActor
final class ModelTests: XCTestCase {
    private func makeModel() throws -> SynthModel {
        SynthModel(audioUnit: try OpenFMAudioUnit(componentDescription: OpenFMAudioUnit.openFMDescription, options: []))
    }

    func testEditsReachTheAudioUnit() throws {
        let model = try makeModel()
        model.set(.op(3, .level), to: 42)
        model.set(.algorithm, to: 4)
        model.set(.delayTime, to: 0.5)
        XCTAssertEqual(model.audioUnit.value(forAddress: AUParameterAddress(Param.op(3, .level).address)), 42)
        XCTAssertEqual([UInt8](model.audioUnit.patchData())[134], 4)
        XCTAssertEqual(model.audioUnit.value(forAddress: 204), 0.5, accuracy: 0.001)
        XCTAssertTrue(model.isEdited)
    }

    func testValuesAreClampedAndStepped() throws {
        let model = try makeModel()
        model.set(.op(1, .level), to: 500)
        XCTAssertEqual(model.value(.op(1, .level)), 99)
        model.set(.feedback, to: 3.6)
        XCTAssertEqual(model.value(.feedback), 4)
        model.set(.feedback, to: -2)
        XCTAssertEqual(model.value(.feedback), 0)
    }

    func testFocusLightsEverythingDownstream() throws {
        let model = try makeModel()   // init voice: algorithm 1
        XCTAssertTrue(model.affectedOps.isEmpty)
        model.beginEditing(.op(6, .level))
        XCTAssertEqual(model.affectedOps, [6, 5, 4, 3])
        XCTAssertEqual(model.selectedOp, 6)
        XCTAssertEqual(model.hint(.op(6, .level)), "Modulator · brightness of OP 5")
        model.endEditing()
        XCTAssertNil(model.focus)
        XCTAssertEqual(model.lastTouched, .op(6, .level))

        model.beginEditing(.op(1, .level))
        XCTAssertEqual(model.affectedOps, [1])
        XCTAssertEqual(model.hint(.op(1, .level)), "Carrier · how loud this layer is")
        model.endEditing()
    }

    func testOperatorSwitchAndFrequencyText() throws {
        let model = try makeModel()
        XCTAssertTrue(model.isOn(2))
        model.toggle(2)
        XCTAssertFalse(model.isOn(2))
        XCTAssertTrue(model.isOn(1))
        XCTAssertFalse(model.patch.operators[1].on)

        model.set(.op(2, .coarse), to: 3)
        model.set(.op(2, .fine), to: 50)
        XCTAssertEqual(model.frequencyText(2), "×4.50")
        model.set(.op(2, .mode), to: 1)
        model.set(.op(2, .coarse), to: 2)
        model.set(.op(2, .fine), to: 0)
        XCTAssertEqual(model.frequencyText(2), "100 Hz")
    }

    func testLoadingAPatchRoundTrips() throws {
        let model = try makeModel()
        let patch = FactoryPresets.all[7]
        model.load(patch, presetID: "x")
        XCTAssertEqual(model.patch, patch)
        XCTAssertEqual(model.name, patch.name)
        XCTAssertFalse(model.isEdited)
        XCTAssertEqual([UInt8](model.audioUnit.patchData()), patch.bytes)
    }

    func testMacrosOffsetTheSoundAndReturnToIt() throws {
        let model = try makeModel()
        let patch = FactoryPresets.all[0]   // algorithm 5: OP2, 4, 6 modulate
        model.load(patch)
        let before = model.bytes

        model.beginEditing(Macro.tone)
        XCTAssertEqual(model.affectedOps, [2, 4, 6])
        model.set(Macro.tone, to: 1)
        model.endEditing()
        XCTAssertEqual(model.value(.op(2, .level)), Double(patch.operators[1].level + 22))
        XCTAssertEqual(model.value(.op(1, .level)), Double(patch.operators[0].level), "carriers keep their level")
        XCTAssertEqual([UInt8](model.audioUnit.patchData()), model.bytes, "macros reach the engine")

        model.set(Macro.attack, to: 0.5)
        XCTAssertLessThan(model.value(.op(1, .rate1)), Double(patch.operators[0].envelope.rates[0]))

        // Back to zero is exactly the designed sound.
        model.set(Macro.tone, to: 0)
        model.set(Macro.attack, to: 0)
        XCTAssertEqual(model.bytes, before)

        // A hand edit becomes the new starting point.
        model.set(Macro.tone, to: -1)
        model.set(.op(2, .level), to: 50)
        XCTAssertEqual(model.value(Macro.tone), 0)
        model.set(Macro.tone, to: 1)
        XCTAssertEqual(model.value(.op(2, .level)), 72)
    }

    /// Hold is a latch: the next phrase replaces the held one, so notes
    /// cannot pile up.
    func testHoldLatchesOnePhraseAtATime() throws {
        let unit = try OpenFMAudioUnit(componentDescription: OpenFMAudioUnit.openFMDescription, options: [])
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        try unit.outputBusses[0].setFormat(format)
        try unit.allocateRenderResources()
        let model = SynthModel(audioUnit: unit)
        model.load(FactoryPresets.all.first { $0.name == "Drawbars" }!)   // sustains for ever

        func voices() throws -> Int {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
            buffer.frameLength = 512
            var time = AudioTimeStamp()
            time.mFlags = .sampleTimeValid
            var flags = AudioUnitRenderActionFlags()
            let block = unit.renderBlock
            for _ in 0..<60 {
                _ = block(&flags, &time, 512, 0, buffer.mutableAudioBufferList, nil)
                time.mSampleTime += 512
            }
            return unit.activeVoices
        }

        model.setHold(true)
        // A three-note chord, released: it keeps sounding.
        for note in [60, 64, 67] { model.noteOn(note, velocity: 100) }
        for note in [60, 64, 67] { model.noteOff(note) }
        XCTAssertEqual(model.latchedNotes, [60, 64, 67])
        XCTAssertEqual(try voices(), 3)

        // The next note replaces the chord instead of adding to it.
        model.noteOn(72, velocity: 100)
        XCTAssertEqual(model.latchedNotes, [])
        model.noteOff(72)
        XCTAssertEqual(model.latchedNotes, [72])
        XCTAssertEqual(try voices(), 1)

        // Many phrases later there is still only the last one.
        for note in 40..<70 {
            model.noteOn(note, velocity: 100)
            model.noteOff(note)
        }
        XCTAssertEqual(try voices(), 1)

        model.setHold(false)
        XCTAssertEqual(model.latchedNotes, [])
        XCTAssertEqual(try voices(), 0)
    }

    func testPatchFormatsReadSysExAndOpenFMFiles() throws {
        let patch = FactoryPresets.all[5]
        let json = try OpenFMPatchFormat.data(for: patch)
        XCTAssertEqual(try PatchFormats.patches(from: json, filename: "Solid Bass.openfmpatch"), [patch])
        // The extension is a hint, not a requirement.
        XCTAssertEqual(try PatchFormats.patches(from: json, filename: "mystery.bin"), [patch])
        XCTAssertEqual(try PatchFormats.patches(from: JSONEncoder().encode([patch, patch]), filename: "two.json").count, 2)

        let single: [UInt8] = [0xF0, 0x43, 0x00, 0x00, 0x01, 0x1B] + patch.bytes.prefix(155) + [0x00, 0xF7]
        XCTAssertEqual(try PatchFormats.patches(from: Data(single), filename: "voice.syx").first?.algorithm, patch.algorithm)
        XCTAssertThrowsError(try PatchFormats.patches(from: Data([1, 2, 3]), filename: "noise.syx"))
        XCTAssertTrue(PatchFormats.fileExtensions.contains("syx"))
    }

    func testImportingAFileAddsPresets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Shared Sound.openfmpatch")
        try OpenFMPatchFormat.data(for: FactoryPresets.all[2]).write(to: file)

        let store = PresetStore(directory: directory)
        let imported = try store.importFile(at: file)
        XCTAssertEqual(imported.map(\.patch.name), ["Hard Clav"])
        XCTAssertEqual(imported[0].patch.category, "User")
        XCTAssertEqual(store.user.count, 1)
    }

    func testPresetStoreSavesDeletesAndImports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PresetStore(directory: directory)
        XCTAssertEqual(store.factory.count, FactoryPresets.all.count)
        XCTAssertTrue(store.user.isEmpty)

        var patch = FactoryPresets.all[0]
        patch.name = "Mine"
        let saved = store.save(patch)
        XCTAssertEqual(saved.patch.category, "User")
        XCTAssertEqual(store.neighbor(of: store.factory.last?.id, offset: 1)?.id, saved.id)
        XCTAssertEqual(store.neighbor(of: saved.id, offset: 1)?.id, store.factory.first?.id)

        // A second store reads what the first one wrote.
        let reopened = PresetStore(directory: directory)
        XCTAssertEqual(reopened.user.map(\.patch.name), ["Mine"])
        XCTAssertFalse(reopened.user[0].isFactory)

        reopened.delete(reopened.user[0])
        XCTAssertTrue(PresetStore(directory: directory).user.isEmpty)
        XCTAssertThrowsError(try store.importSysEx(Data([0, 1, 2]), named: "bad"))
    }
}

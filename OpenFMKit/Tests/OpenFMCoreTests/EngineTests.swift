// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import XCTest
@testable import OpenFMCore
import OpenFMEngine

/// Drives the real audio unit offline, exactly as a host would.
final class EngineTests: XCTestCase {
    private func makeUnit(sampleRate: Double = 48000) throws -> OpenFMAudioUnit {
        let unit = try OpenFMAudioUnit(componentDescription: OpenFMAudioUnit.openFMDescription, options: [])
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        try unit.outputBusses[0].setFormat(format)
        try unit.allocateRenderResources()
        return unit
    }

    /// Renders `seconds` of audio and returns the left channel.
    private func render(_ unit: OpenFMAudioUnit, seconds: Double, sampleRate: Double = 48000) throws -> [Float] {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let frames: AVAudioFrameCount = 512
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let block = unit.renderBlock
        var output: [Float] = []
        var time = AudioTimeStamp()
        time.mFlags = .sampleTimeValid
        var flags = AudioUnitRenderActionFlags()
        for _ in 0..<Int(seconds * sampleRate / Double(frames)) {
            let status = block(&flags, &time, frames, 0, buffer.mutableAudioBufferList, nil)
            XCTAssertEqual(status, noErr)
            output.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(frames)))
            time.mSampleTime += Double(frames)
        }
        return output
    }

    private func peak(_ samples: [Float]) -> Float { samples.map(abs).max() ?? 0 }

    func testSilentUntilPlayedThenSoundsAndReleases() throws {
        let unit = try makeUnit()
        XCTAssertEqual(peak(try render(unit, seconds: 0.2)), 0, accuracy: 1e-5)

        unit.noteOn(60, velocity: 100)
        let held = try render(unit, seconds: 0.3)
        XCTAssertGreaterThan(peak(held), 0.05)
        XCTAssertTrue(held.allSatisfy(\.isFinite))
        XCTAssertEqual(unit.activeVoices, 1)

        unit.noteOff(60)
        unit.setValue(0, forAddress: 206)   // no reverb tail
        _ = try render(unit, seconds: 1.0)
        XCTAssertEqual(unit.activeVoices, 0)
    }

    func testInitVoicePlaysAtConcertPitch() throws {
        let unit = try makeUnit()
        unit.setValue(0, forAddress: 206)
        unit.noteOn(69, velocity: 100)   // A = 440 Hz
        let samples = try render(unit, seconds: 1.0)
        var crossings = 0
        for i in 1..<samples.count where samples[i - 1] <= 0 && samples[i] > 0 { crossings += 1 }
        XCTAssertEqual(Double(crossings) / (Double(samples.count) / 48000), 440, accuracy: 3)
    }

    func testEveryFactoryPatchIsAudibleAndUnclipped() throws {
        let unit = try makeUnit()
        for patch in FactoryPresets.all {
            unit.panic()
            unit.loadPatchData(Data(patch.bytes))
            for (param, value) in zip(Param.patchEffects, patch.effects.values) {
                unit.setValue(Float(value), forAddress: AUParameterAddress(param.address))
            }
            for note: UInt8 in [48, 60, 67] { unit.noteOn(note, velocity: 100) }
            let samples = try render(unit, seconds: 1.5)
            for note: UInt8 in [48, 60, 67] { unit.noteOff(note) }
            XCTAssertTrue(samples.allSatisfy(\.isFinite), patch.name)
            XCTAssertGreaterThan(peak(samples), 0.03, "\(patch.name) is too quiet")
            XCTAssertLessThan(peak(samples), 1.0, "\(patch.name) clips")
        }
    }

    func testPolyphonyIsCappedAtSixteenVoices() throws {
        let unit = try makeUnit()
        for note: UInt8 in 40..<64 { unit.noteOn(note, velocity: 90) }
        _ = try render(unit, seconds: 0.1)
        XCTAssertEqual(unit.activeVoices, 16)
    }

    func testParameterTreeDrivesTheEngine() throws {
        let unit = try makeUnit()
        let tree = try XCTUnwrap(unit.parameterTree)
        XCTAssertEqual(tree.allParameters.count, 6 * 22 + 19 + Param.effectCount)

        let algorithm = try XCTUnwrap(tree.parameter(withAddress: 134))
        algorithm.value = 21
        XCTAssertEqual([UInt8](unit.patchData())[134], 21)
        XCTAssertEqual(algorithm.value, 21)

        // Switching operator 1 off silences the init voice.
        try XCTUnwrap(tree.parameter(withAddress: 160)).value = 0
        XCTAssertEqual([UInt8](unit.patchData())[155], 0b011111)
        unit.setValue(0, forAddress: 206)
        unit.noteOn(60, velocity: 100)
        XCTAssertEqual(peak(try render(unit, seconds: 0.2)), 0, accuracy: 1e-4)
    }

    func testEditingAHeldNoteChangesItsSound() throws {
        let unit = try makeUnit()
        unit.setValue(0, forAddress: 206)
        unit.noteOn(60, velocity: 100)
        let loud = peak(try render(unit, seconds: 0.3))
        unit.setValue(60, forAddress: AUParameterAddress(Param.op(1, .level).address))
        _ = try render(unit, seconds: 0.2)
        let quiet = peak(try render(unit, seconds: 0.2))
        XCTAssertLessThan(quiet, loud * 0.2)
    }

    func testHostMIDIEventsPlayNotes() throws {
        let unit = try makeUnit()
        let schedule = try XCTUnwrap(unit.scheduleMIDIEventBlock)
        let noteOn: [UInt8] = [0x90, 64, 110]
        schedule(AUEventSampleTimeImmediate, 0, 3, noteOn)
        XCTAssertGreaterThan(peak(try render(unit, seconds: 0.2)), 0.05)
    }

    func testStateRestoresPatchNameAndEffects() throws {
        let source = try makeUnit()
        let patch = FactoryPresets.all[3]
        source.loadPatchData(Data(patch.bytes))
        source.patchName = patch.name
        source.setValue(0.77, forAddress: 203)
        let state = try XCTUnwrap(source.fullState)

        let restored = try makeUnit()
        restored.fullState = state
        XCTAssertEqual([UInt8](restored.patchData()), patch.bytes)
        XCTAssertEqual(restored.patchName, patch.name)
        XCTAssertEqual(restored.value(forAddress: 203), 0.77, accuracy: 0.001)
    }

    func testRendersAtOtherSampleRates() throws {
        let unit = try makeUnit(sampleRate: 44100)
        unit.noteOn(69, velocity: 100)
        unit.setValue(0, forAddress: 206)
        let samples = try render(unit, seconds: 1.0, sampleRate: 44100)
        var crossings = 0
        for i in 1..<samples.count where samples[i - 1] <= 0 && samples[i] > 0 { crossings += 1 }
        XCTAssertEqual(Double(crossings) / (Double(samples.count) / 44100), 440, accuracy: 3)
    }
}

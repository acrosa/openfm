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

    /// Rising zero crossings per second over the last part of `samples`.
    private func pitch(_ samples: [Float], sampleRate: Double = 48000) -> Double {
        let tail = Array(samples.suffix(Int(sampleRate * 0.2)))
        let crossings = zip(tail, tail.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
        return Double(crossings) * sampleRate / Double(tail.count)
    }

    func testMonoPlaysOneVoiceAndGlidesBetweenOverlappingNotes() throws {
        let unit = try makeUnit()
        unit.setValue(0, forAddress: 206)
        unit.setValue(1, forAddress: 211)     // mono
        unit.setValue(0.2, forAddress: 212)   // glide

        unit.noteOn(57, velocity: 100)        // A 220
        XCTAssertEqual(pitch(try render(unit, seconds: 0.4)), 220, accuracy: 6)
        unit.noteOn(69, velocity: 100)        // A 440, overlapping
        let sliding = pitch(try render(unit, seconds: 0.1))
        XCTAssertEqual(unit.activeVoices, 1, "the second key moves the same voice")
        XCTAssertGreaterThan(sliding, 230)
        XCTAssertLessThan(sliding, 430, "part-way through the slide")
        XCTAssertEqual(pitch(try render(unit, seconds: 0.5)), 440, accuracy: 6)

        // Letting go of the upper key falls back to the one still held.
        unit.noteOff(69)
        XCTAssertEqual(pitch(try render(unit, seconds: 0.6)), 220, accuracy: 6)
        XCTAssertEqual(unit.activeVoices, 1)
        unit.noteOff(57)
        _ = try render(unit, seconds: 0.5)
        XCTAssertEqual(unit.activeVoices, 0)

        // Poly again: two keys, two voices.
        unit.setValue(0, forAddress: 211)
        unit.noteOn(57, velocity: 100)
        unit.noteOn(69, velocity: 100)
        _ = try render(unit, seconds: 0.1)
        XCTAssertEqual(unit.activeVoices, 2)
    }

    func testArpeggiatorStepsThroughHeldKeysInTime() throws {
        let unit = try makeUnit()
        unit.setValue(0, forAddress: 206)
        unit.setValue(1, forAddress: 213)     // up
        unit.setValue(3, forAddress: 214)     // four steps per beat
        unit.setValue(120, forAddress: 215)   // eight steps a second
        for note: UInt8 in [60, 64, 67] { unit.noteOn(note, velocity: 100) }

        // The init voice starts and stops at once, so each step is a burst.
        let samples = try render(unit, seconds: 2)
        let window = 240
        let loud = stride(from: 0, to: samples.count - window, by: window).map { start in
            samples[start..<(start + window)].contains { abs($0) > 0.02 }
        }
        let onsets = zip(loud, loud.dropFirst()).filter { !$0 && $1 }.count + (loud[0] ? 1 : 0)
        XCTAssertEqual(Double(onsets), 16, accuracy: 1)
        XCTAssertLessThanOrEqual(unit.activeVoices, 1)

        for note: UInt8 in [60, 64, 67] { unit.noteOff(note) }
        _ = try render(unit, seconds: 0.5)
        XCTAssertEqual(unit.activeVoices, 0)
        XCTAssertEqual(peak(try render(unit, seconds: 0.2)), 0, accuracy: 1e-4, "nothing keeps stepping")

        // Switching it off with keys down lets go of the sounding note.
        unit.noteOn(60, velocity: 100)
        _ = try render(unit, seconds: 0.05)
        unit.setValue(0, forAddress: 213)
        _ = try render(unit, seconds: 0.5)
        XCTAssertEqual(unit.activeVoices, 0)
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

    /// Record a note into a layer, stop playing live, and the layer keeps
    /// playing it, with the sound it was recorded with.
    func testLooperRecordsAndReplaysALayer() throws {
        let unit = try makeUnit()
        unit.setValue(0, forAddress: 206)   // no reverb tail to confuse the measurement
        // 240 BPM, one bar: the count-in and the loop are one second each.
        unit.looperSetTempo(240, bars: 1, metronome: false, quantize: true)
        XCTAssertFalse(unit.looperState.playing)

        unit.looperRecordLayer(0)
        _ = try render(unit, seconds: 0.5)
        XCTAssertTrue(unit.looperState.countingIn)
        XCTAssertEqual(unit.looperState.armedLayer, 0)
        _ = try render(unit, seconds: 0.55)
        XCTAssertTrue(unit.looperState.playing)
        XCTAssertEqual(unit.looperState.recordingLayer, 0)

        // Play one note a little after the downbeat, live.
        unit.noteOn(60, velocity: 100)
        _ = try render(unit, seconds: 0.25)
        unit.noteOff(60)
        // Change the live sound: the layer must not follow.
        unit.setValue(0, forAddress: AUParameterAddress(Param.op(1, .level).address))
        _ = try render(unit, seconds: 0.8)

        // The pass is over: the layer holds the note and nothing is recording.
        XCTAssertEqual(unit.looperState.recordingLayer, -1)
        XCTAssertEqual(unit.looperState.contentMask, 1)
        XCTAssertEqual(unit.activeVoices, 0, "nothing is played live any more")

        // With the live sound silenced, what is heard is the layer alone.
        XCTAssertGreaterThan(peak(try render(unit, seconds: 1.0)), 0.05, "the layer loops by itself")
        XCTAssertGreaterThan(peak(try render(unit, seconds: 1.0)), 0.05, "and keeps looping")

        unit.looperSetLayer(0, muted: true)
        _ = try render(unit, seconds: 1.0)
        XCTAssertEqual(peak(try render(unit, seconds: 1.0)), 0, accuracy: 1e-3, "muted")
        unit.looperSetLayer(0, muted: false)
        let full = peak(try render(unit, seconds: 1.0))
        XCTAssertGreaterThan(full, 0.05)

        // A layer has its own volume.
        unit.looperSetLayer(0, volume: 0.5)
        _ = try render(unit, seconds: 1.0)
        let half = peak(try render(unit, seconds: 1.0))
        XCTAssertEqual(half, full * 0.25, accuracy: full * 0.06, "volume 50 is a quarter of the amplitude")
        unit.looperSetLayer(0, volume: 1)
        _ = try render(unit, seconds: 1.0)

        unit.looperClearLayer(0)
        _ = try render(unit, seconds: 1.0)
        XCTAssertEqual(unit.looperState.contentMask, 0)
        XCTAssertEqual(peak(try render(unit, seconds: 1.0)), 0, accuracy: 1e-3, "cleared")

        unit.looperSetPlaying(false)
        _ = try render(unit, seconds: 0.1)
        XCTAssertFalse(unit.looperState.playing)
    }

    func testLooperSnapsNotesToTheGrid() throws {
        // At 60 BPM a sixteenth is 0.25 s. A note played 0.1 s late must come
        // back on the beat: sound starts right at the loop start next time.
        let unit = try makeUnit()
        unit.setValue(0, forAddress: 206)
        unit.looperSetTempo(60, bars: 1, metronome: false, quantize: true)
        unit.looperRecordLayer(0)
        _ = try render(unit, seconds: 4.0)          // count-in
        _ = try render(unit, seconds: 0.1)          // late
        unit.noteOn(60, velocity: 100)
        _ = try render(unit, seconds: 0.5)
        unit.noteOff(60)
        _ = try render(unit, seconds: 3.4 + 0.005)  // to the end of the pass
        let start = try render(unit, seconds: 0.05)
        XCTAssertGreaterThan(peak(start), 0.05, "the note was moved onto the downbeat")
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

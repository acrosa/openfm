// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import XCTest

/// Loads the installed AUv3 extension the way a host such as GarageBand
/// does, out of process, and checks that it actually produces sound.
final class ExtensionTests: XCTestCase {
    private func fourCC(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    private var component: AudioComponentDescription {
        AudioComponentDescription(componentType: kAudioUnitType_MusicDevice, componentSubType: fourCC("Opfm"),
                                  componentManufacturer: fourCC("OpFM"), componentFlags: 0, componentFlagsMask: 0)
    }

    /// Renders through AVAudioEngine and returns the loudest sample.
    private func renderPeak(_ engine: AVAudioEngine, seconds: Double) throws -> Float {
        let format = engine.manualRenderingFormat
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount))
        var peak: Float = 0
        var remaining = Int(seconds * format.sampleRate)
        while remaining > 0 {
            let frames = AVAudioFrameCount(min(remaining, Int(buffer.frameCapacity)))
            let status = try engine.renderOffline(frames, to: buffer)
            XCTAssertEqual(status, .success)
            if let data = buffer.floatChannelData {
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[0][i])) }
            }
            remaining -= Int(frames)
        }
        return peak
    }

    func testExtensionIsRegisteredAndPlaysHostMIDI() async throws {
        // The app must have been launched once for the system to register its extension.
        let app = await XCUIApplication()
        await app.launch()

        var found = false
        for _ in 0..<20 where !found {
            found = !AVAudioUnitComponentManager.shared().components(matching: component).isEmpty
            if !found { try await Task.sleep(for: .seconds(0.5)) }
        }
        XCTAssertTrue(found, "the OpenFM audio unit extension is not registered")

        let unit = try await AVAudioUnit.instantiate(with: component, options: .loadOutOfProcess)
        let engine = AVAudioEngine()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        engine.attach(unit)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
        try engine.start()

        XCTAssertEqual(try renderPeak(engine, seconds: 0.2), 0, accuracy: 1e-4, "silent before any note")

        // A host plays notes by scheduling MIDI on the audio unit.
        let schedule = try XCTUnwrap(unit.auAudioUnit.scheduleMIDIEventBlock)
        let noteOn: [UInt8] = [0x90, 60, 100]
        schedule(AUEventSampleTimeImmediate, 0, 3, noteOn)
        let peak = try renderPeak(engine, seconds: 0.5)
        XCTAssertGreaterThan(peak, 0.02, "a note sent by the host must be heard")

        let noteOff: [UInt8] = [0x80, 60, 0]
        schedule(AUEventSampleTimeImmediate, 0, 3, noteOff)
        engine.stop()
    }
}

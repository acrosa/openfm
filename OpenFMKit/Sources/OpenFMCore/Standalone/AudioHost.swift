// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import OpenFMEngine
import AudioToolbox
import os

/// Runs the OpenFM audio unit in-process for the standalone app: the same
/// `OpenFMAudioUnit` the AUv3 extension vends, pulled by the hardware output.
@MainActor
public final class AudioHost {
    public let audioUnit: OpenFMAudioUnit
    private var output: AUAudioUnit?
    private var midi: MIDIInput?
    private var observers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: "org.openfm.OpenFM", category: "audio")

    public init() throws {
        audioUnit = try OpenFMAudioUnit(componentDescription: OpenFMAudioUnit.openFMDescription, options: [])
    }

    public func start() {
        midi = MIDIInput(audioUnit: audioUnit)
        observe()
        restart()
    }

    private func observe() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            AVAudioSession.routeChangeNotification,
            AVAudioSession.mediaServicesWereResetNotification,
            AVAudioSession.interruptionNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let interruptionBegan = name == AVAudioSession.interruptionNotification
                    && (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
                MainActor.assumeIsolated {
                    if !interruptionBegan { self?.restartIfNeeded() }
                }
            })
        }
    }

    /// Route changes are frequent; only rebuild when the hardware format moved
    /// or the output stopped.
    private func restartIfNeeded() {
        let rate = AVAudioSession.sharedInstance().sampleRate
        if output?.isRunning != true || audioUnit.outputBusses[0].format.sampleRate != rate {
            restart()
        }
    }

    private func restart() {
        output?.stopHardware()
        output?.deallocateRenderResources()
        output = nil
        if audioUnit.renderResourcesAllocated { audioUnit.deallocateRenderResources() }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            let description = AudioComponentDescription(
                componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_RemoteIO,
                componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
            let io = try AUAudioUnit(componentDescription: description)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: session.sampleRate, channels: 2) else { return }
            try io.inputBusses[0].setFormat(format)
            try audioUnit.outputBusses[0].setFormat(format)
            try audioUnit.allocateRenderResources()
            io.outputProvider = AudioHost.makeProvider(audioUnit.renderBlock)
            try io.allocateRenderResources()
            try io.startHardware()
            output = io
        } catch {
            log.error("Audio start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Built off the main actor: the block runs on the realtime audio thread.
    private nonisolated static func makeProvider(_ render: @escaping AURenderBlock) -> AURenderPullInputBlock {
        { flags, timestamp, frames, _, data in
            render(flags, timestamp, frames, 0, data, nil)
        }
    }
}

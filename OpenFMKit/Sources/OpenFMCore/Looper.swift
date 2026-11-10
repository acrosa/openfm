// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import OpenFMEngine

/// A four-layer loop recorder for the standalone app.
///
/// Each layer keeps the sound it was recorded with: record a bass line, pick
/// another sound, and play or record over it. Timing lives in the audio
/// engine; this class issues commands and mirrors the engine's state for the
/// interface.
///
///     looper.record()        // counts in one bar, records one loop, then loops it
///     looper.togglePlay()
///     looper.toggleMute(0)
///     looper.clear(0)
@MainActor
@Observable
public final class Looper {
    public struct Layer: Identifiable, Equatable, Sendable {
        public let id: Int
        /// Name of the sound the layer was recorded with.
        public var sound: String?
        public var hasContent = false
        public var isMuted = false
    }

    public static let layerCount = 4
    public static let barChoices = [1, 2, 4]

    public private(set) var layers: [Layer] = (0..<Looper.layerCount).map { Layer(id: $0) }
    public private(set) var isPlaying = false
    /// Counting in before the first recording.
    public private(set) var isCountingIn = false
    /// Layer being recorded right now.
    public private(set) var recordingLayer: Int?
    /// Layer waiting for the loop to come round before it records.
    public private(set) var armedLayer: Int?
    /// 0...1 through the loop.
    public private(set) var progress = 0.0
    /// Beats left in the count-in, 4...1, or nil.
    public private(set) var countIn: Int?

    public var tempo = 112.0 { didSet { push() } }
    public var bars = 2 { didSet { push() } }
    public var metronome = false { didSet { push() } }
    /// Snap recorded notes to the nearest sixteenth.
    public var quantize = true { didSet { push() } }

    /// True while anything is running, armed or recorded.
    public var isIdle: Bool { !isPlaying && !isCountingIn && recordingLayer == nil && armedLayer == nil }
    public var hasContent: Bool { layers.contains(where: \.hasContent) }
    /// The next layer `record()` would use.
    public var nextFreeLayer: Int? { layers.first { !$0.hasContent && $0.id != recordingLayer && $0.id != armedLayer }?.id }
    /// The loop length can only change while nothing is recorded.
    public var canChangeLength: Bool { !hasContent && isIdle }

    @ObservationIgnored private let synth: SynthModel
    @ObservationIgnored private var timer: Timer?

    public init(synth: SynthModel) {
        self.synth = synth
        push()
    }

    private func push() {
        synth.audioUnit.looperSetTempo(Float(tempo), bars: bars, metronome: metronome, quantize: quantize)
    }

    // MARK: Commands

    /// Records one pass into the next free layer with the current sound.
    /// - Returns: the layer used, or nil if all four are full.
    @discardableResult
    public func record() -> Int? {
        guard let layer = nextFreeLayer, recordingLayer == nil, armedLayer == nil else { return nil }
        layers[layer].sound = synth.name
        layers[layer].isMuted = false
        synth.audioUnit.looperSetLayer(layer, muted: false)
        synth.audioUnit.looperRecordLayer(layer)
        armedLayer = layer
        startPolling()
        return layer
    }

    public func togglePlay() {
        let stop = isPlaying || isCountingIn
        synth.audioUnit.looperSetPlaying(!stop)
        if stop { armedLayer = nil }
        startPolling()
    }

    public func toggleMute(_ layer: Int) {
        guard layers.indices.contains(layer), layers[layer].hasContent else { return }
        layers[layer].isMuted.toggle()
        synth.audioUnit.looperSetLayer(layer, muted: layers[layer].isMuted)
    }

    public func clear(_ layer: Int) {
        guard layers.indices.contains(layer) else { return }
        synth.audioUnit.looperClearLayer(layer)
        layers[layer] = Layer(id: layer)
        startPolling()
    }

    public func clearAll() {
        synth.audioUnit.looperSetPlaying(false)
        for layer in layers.indices { clear(layer) }
    }

    // MARK: State

    /// Reads the engine's state. Called on a timer while the looper is busy;
    /// tests call it directly.
    public func refresh() {
        let state = synth.audioUnit.looperState
        isPlaying = state.playing
        isCountingIn = state.countingIn
        recordingLayer = state.recordingLayer >= 0 ? state.recordingLayer : nil
        armedLayer = state.armedLayer >= 0 ? state.armedLayer : nil
        countIn = state.countingIn ? max(1, Int((-state.positionBeats).rounded(.up))) : nil
        progress = state.playing && state.lengthBeats > 0 ? min(max(state.positionBeats / state.lengthBeats, 0), 1) : 0
        for i in layers.indices {
            let has = (state.contentMask >> UInt(i)) & 1 == 1
            if layers[i].hasContent != has { layers[i].hasContent = has }
            // A layer that was armed and recorded nothing goes back to empty.
            if !has, recordingLayer != i, armedLayer != i, layers[i].sound != nil, !state.countingIn {
                layers[i].sound = nil
            }
        }
    }

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                if self.isIdle, self.timer != nil, self.settled > 10 {
                    self.timer?.invalidate()
                    self.timer = nil
                    self.settled = 0
                } else {
                    self.settled = self.isIdle ? self.settled + 1 : 0
                }
            }
        }
    }

    /// Idle refreshes in a row; the timer stops once the engine has caught up.
    @ObservationIgnored private var settled = 0
}

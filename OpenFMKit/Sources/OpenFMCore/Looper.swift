// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import Foundation
import Observation
import OpenFMEngine

/// One note in a loop.
public struct LoopNote: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    /// Where it starts, in beats from the top of the loop.
    public var start: Double
    /// How long it lasts, in beats.
    public var length: Double
    /// MIDI note number.
    public var note: Int
    /// 1...127
    public var velocity: Int

    public init(start: Double, length: Double, note: Int, velocity: Int = 100) {
        self.start = start
        self.length = length
        self.note = note
        self.velocity = velocity
    }

    private enum CodingKeys: String, CodingKey { case start, length, note, velocity }
}

/// A four-layer loop recorder for the standalone app.
///
/// Each layer keeps the sound it was recorded with: record a bass line, pick
/// another sound, and play or record over it. Timing lives in the audio
/// engine; this class issues commands, mirrors the engine's state for the
/// interface, keeps the notes so they can be edited, saves everything to
/// disk, and exports it as audio or MIDI.
///
///     looper.record()        // counts in one bar, records one loop, then loops it
///     looper.togglePlay()
///     looper.toggleMute(0)
///     looper.setNotes(0, to: edited)
///     let wav = try looper.exportAudio()
@MainActor
@Observable
public final class Looper {
    public struct Layer: Identifiable, Equatable, Codable, Sendable {
        public let id: Int
        /// Name of the sound the layer was recorded with.
        public var sound: String?
        /// The sound itself, so the layer can be restored and exported.
        public var patch: Patch?
        public var notes: [LoopNote] = []
        public var isMuted = false
        /// Playback level, 0...1. 1 is as recorded.
        public var volume = 1.0

        public var hasContent: Bool { !notes.isEmpty }

        public init(id: Int) { self.id = id }
    }

    /// What is written to disk.
    private struct Saved: Codable {
        var tempo: Double
        var bars: Int
        var metronome: Bool
        var quantize: Bool
        var layers: [Layer]
    }

    public static let layerCount = 4
    public static let barChoices = [1, 2, 4]
    /// The grid notes snap to, in beats: a sixteenth note.
    public static let grid = 0.25

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

    public var lengthBeats: Double { Double(bars) * 4 }
    /// True while nothing is running, armed or being recorded.
    public var isIdle: Bool { !isPlaying && !isCountingIn && recordingLayer == nil && armedLayer == nil }
    public var hasContent: Bool { layers.contains(where: \.hasContent) }
    /// The next layer `record()` would use.
    public var nextFreeLayer: Int? { layers.first { !$0.hasContent && $0.id != recordingLayer && $0.id != armedLayer }?.id }
    /// The loop length can only change while nothing is recorded.
    public var canChangeLength: Bool { !hasContent && isIdle }

    @ObservationIgnored private let synth: SynthModel
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isRestoring = false
    /// Idle refreshes in a row; the timer stops once the engine has caught up.
    @ObservationIgnored private var settled = 0

    /// - Parameter directory: where `Loops.json` is kept; nil keeps loops in
    ///   memory only.
    public init(synth: SynthModel, directory: URL? = nil) {
        self.synth = synth
        fileURL = directory?.appendingPathComponent("Loops.json")
        restore()
        push()
    }

    private func push() {
        synth.audioUnit.looperSetTempo(Float(tempo), bars: bars, metronome: metronome, quantize: quantize)
        save()
    }

    // MARK: Commands

    /// Records one pass into the next free layer with the current sound.
    /// - Returns: the layer used, or nil if all four are full.
    @discardableResult
    public func record() -> Int? {
        guard let layer = nextFreeLayer, recordingLayer == nil, armedLayer == nil else { return nil }
        layers[layer] = Layer(id: layer)
        layers[layer].sound = synth.name
        layers[layer].patch = synth.patch
        synth.audioUnit.looperSetLayer(layer, muted: false)
        synth.audioUnit.looperSetLayer(layer, volume: 1)
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
        save()
    }

    public func setVolume(_ layer: Int, to volume: Double) {
        guard layers.indices.contains(layer) else { return }
        let v = min(max(volume, 0), 1)
        guard v != layers[layer].volume else { return }
        layers[layer].volume = v
        synth.audioUnit.looperSetLayer(layer, volume: Float(v))
        save()
    }

    public func clear(_ layer: Int) {
        guard layers.indices.contains(layer) else { return }
        synth.audioUnit.looperClearLayer(layer)
        synth.audioUnit.looperSetLayer(layer, volume: 1)
        synth.audioUnit.looperSetLayer(layer, muted: false)
        layers[layer] = Layer(id: layer)
        save()
        startPolling()
    }

    public func clearAll() {
        synth.audioUnit.looperSetPlaying(false)
        for layer in layers.indices { clear(layer) }
    }

    // MARK: Editing

    /// Replaces a layer's notes. The loop keeps playing and picks the change
    /// up at once. An empty list clears the layer.
    public func setNotes(_ layer: Int, to notes: [LoopNote]) {
        guard layers.indices.contains(layer), let patch = layers[layer].patch else { return }
        let length = lengthBeats
        let tidy = notes
            .map { note -> LoopNote in
                var n = note
                n.start = min(max(n.start, 0), length - Looper.grid)
                n.length = min(max(n.length, Looper.grid / 2), length - n.start)
                n.note = min(max(n.note, 0), 127)
                n.velocity = min(max(n.velocity, 1), 127)
                return n
            }
            .sorted { ($0.start, $0.note) < ($1.start, $1.note) }
        guard !tidy.isEmpty else { return clear(layer) }
        layers[layer].notes = tidy
        load(layer, notes: tidy, patch: patch, into: synth.audioUnit)
        save()
        startPolling()
    }

    private func effects(for patch: Patch, from unit: OpenFMAudioUnit) -> [NSNumber] {
        // A patch stores nine effect values; volume and bend range are global.
        let own = patch.effects.values.map { NSNumber(value: $0) }
        let global = [Param.volume, Param.bendRange].map {
            NSNumber(value: unit.value(forAddress: AUParameterAddress($0.address)))
        }
        return own + global
    }

    private func load(_ layer: Int, notes: [LoopNote], patch: Patch, into unit: OpenFMAudioUnit) {
        unit.looperLoadLayer(layer, events: Looper.events(from: notes, length: lengthBeats),
                             patch: Data(patch.bytes), effects: effects(for: patch, from: synth.audioUnit))
    }

    // MARK: Notes and engine events

    /// Packs notes as the engine's 16-byte event records.
    static func events(from notes: [LoopNote], length: Double) -> Data {
        var data = Data()
        func append(_ beat: Double, _ status: UInt8, _ note: Int, _ velocity: Int) {
            var b = beat
            withUnsafeBytes(of: &b) { data.append(contentsOf: $0) }
            data.append(contentsOf: [status, UInt8(clamping: note), UInt8(clamping: velocity), 0, 0, 0, 0, 0])
        }
        for n in notes {
            append(n.start, 0x90, n.note, n.velocity)
            append(min(n.start + n.length, length - 0.001), 0x80, n.note, 0)
        }
        return data
    }

    /// Pairs the engine's note-ons with their note-offs.
    static func notes(from data: Data, length: Double) -> [LoopNote] {
        struct Event { var beat: Double; var status: UInt8; var note: Int; var velocity: Int }
        var events: [Event] = []
        data.withUnsafeBytes { raw in
            for i in 0..<(raw.count / 16) {
                let beat = raw.loadUnaligned(fromByteOffset: i * 16, as: Double.self)
                events.append(Event(beat: beat, status: raw[i * 16 + 8], note: Int(raw[i * 16 + 9]), velocity: Int(raw[i * 16 + 10])))
            }
        }
        var notes: [LoopNote] = []
        var used = Set<Int>()
        for (i, on) in events.enumerated() where on.status == 0x90 {
            // The matching note-off is the earliest unused one after the note-on.
            let off = events.enumerated()
                .filter { $0.element.status == 0x80 && $0.element.note == on.note && $0.element.beat > on.beat && !used.contains($0.offset) }
                .min { $0.element.beat < $1.element.beat }
            if let off { used.insert(off.offset) }
            _ = i
            let end = off?.element.beat ?? length
            notes.append(LoopNote(start: on.beat, length: max(end - on.beat, Looper.grid / 2), note: on.note, velocity: max(on.velocity, 1)))
        }
        return notes.sorted { ($0.start, $0.note) < ($1.start, $1.note) }
    }

    // MARK: State

    /// Reads the engine's state. Called on a timer while the looper is busy;
    /// tests call it directly.
    public func refresh() {
        let state = synth.audioUnit.looperState
        let wasRecording = recordingLayer
        isPlaying = state.playing
        isCountingIn = state.countingIn
        recordingLayer = state.recordingLayer >= 0 ? state.recordingLayer : nil
        armedLayer = state.armedLayer >= 0 ? state.armedLayer : nil
        countIn = state.countingIn ? max(1, Int((-state.positionBeats).rounded(.up))) : nil
        progress = state.playing && state.lengthBeats > 0 ? min(max(state.positionBeats / state.lengthBeats, 0), 1) : 0

        // A recording just finished: collect what was played.
        if let done = wasRecording, recordingLayer != done {
            let notes = Looper.notes(from: synth.audioUnit.looperEvents(forLayer: done), length: lengthBeats)
            if notes.isEmpty {
                layers[done] = Layer(id: done)
            } else {
                layers[done].notes = notes
            }
            save()
        }
        // A layer that was armed but never got to record goes back to empty.
        for i in layers.indices where !layers[i].hasContent && layers[i].sound != nil {
            if recordingLayer != i, armedLayer != i, !state.countingIn { layers[i] = Layer(id: i) }
        }
    }

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                self.settled = self.isIdle ? self.settled + 1 : 0
                if self.settled > 10 {
                    self.timer?.invalidate()
                    self.timer = nil
                    self.settled = 0
                }
            }
        }
    }

    // MARK: Saving

    private func save() {
        guard let fileURL, !isRestoring else { return }
        let saved = Saved(tempo: tempo, bars: bars, metronome: metronome, quantize: quantize,
                          layers: layers.filter(\.hasContent))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(saved) { try? data.write(to: fileURL, options: .atomic) }
    }

    private func restore() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        isRestoring = true
        defer { isRestoring = false }
        tempo = min(max(saved.tempo, 40), 240)
        bars = Looper.barChoices.contains(saved.bars) ? saved.bars : 2
        metronome = saved.metronome
        quantize = saved.quantize
        for layer in saved.layers where layers.indices.contains(layer.id) && layer.hasContent {
            guard let patch = layer.patch else { continue }
            layers[layer.id] = layer
            load(layer.id, notes: layer.notes, patch: patch, into: synth.audioUnit)
            synth.audioUnit.looperSetLayer(layer.id, muted: layer.isMuted)
            synth.audioUnit.looperSetLayer(layer.id, volume: Float(layer.volume))
        }
    }

    // MARK: Export

    public enum ExportError: LocalizedError {
        case nothingToExport
        case renderFailed

        public var errorDescription: String? {
            switch self {
            case .nothingToExport: "Record a loop first."
            case .renderFailed: "OpenFM couldn’t render the loop."
            }
        }
    }

    /// The loop as a standard MIDI file: a tempo track, then one track per
    /// layer, named after its sound. Opens in any sequencer.
    public func midiFileData() throws -> Data {
        let sounding = layers.filter(\.hasContent)
        guard !sounding.isEmpty else { throw ExportError.nothingToExport }
        let ticksPerBeat = 480

        func variableLength(_ value: Int) -> [UInt8] {
            var bytes = [UInt8(value & 0x7f)]
            var v = value >> 7
            while v > 0 {
                bytes.insert(UInt8(v & 0x7f) | 0x80, at: 0)
                v >>= 7
            }
            return bytes
        }
        func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] {
            let n = UInt32(body.count)
            return Array(id.utf8) + [UInt8(n >> 24), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)] + body
        }
        func meta(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] { [0x00, 0xff, type] + variableLength(payload.count) + payload }
        let end: [UInt8] = [0xff, 0x2f, 0x00]
        let loopTicks = Int(lengthBeats) * ticksPerBeat

        let microsecondsPerBeat = Int((60_000_000 / tempo).rounded())
        var tempoTrack = meta(0x51, [UInt8((microsecondsPerBeat >> 16) & 0xff), UInt8((microsecondsPerBeat >> 8) & 0xff), UInt8(microsecondsPerBeat & 0xff)])
        tempoTrack += meta(0x58, [4, 2, 24, 8])
        tempoTrack += variableLength(loopTicks) + end

        var file = chunk("MThd", [0, 1, 0, UInt8(sounding.count + 1), UInt8(ticksPerBeat >> 8), UInt8(ticksPerBeat & 0xff)])
        file += chunk("MTrk", tempoTrack)
        for (channel, layer) in sounding.enumerated() {
            var events: [(tick: Int, bytes: [UInt8])] = []
            for n in layer.notes {
                let on = Int((n.start * Double(ticksPerBeat)).rounded())
                let off = min(Int(((n.start + n.length) * Double(ticksPerBeat)).rounded()), loopTicks)
                events.append((on, [0x90 | UInt8(channel), UInt8(n.note), UInt8(n.velocity)]))
                events.append((max(off, on + 1), [0x80 | UInt8(channel), UInt8(n.note), 0]))
            }
            // Note-offs before note-ons on the same tick.
            events.sort { ($0.tick, $0.bytes[0] & 0xf0) < ($1.tick, $1.bytes[0] & 0xf0) }
            var track = meta(0x03, Array((layer.sound ?? "Loop \(layer.id + 1)").utf8))
            var last = 0
            for e in events {
                track += variableLength(e.tick - last) + e.bytes
                last = e.tick
            }
            track += variableLength(max(loopTicks - last, 0)) + end
            file += chunk("MTrk", track)
        }
        return Data(file)
    }

    /// Writes the MIDI file to a temporary location for sharing.
    public func exportMIDI() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenFM Loop.mid")
        try midiFileData().write(to: url, options: .atomic)
        return url
    }

    /// Renders the loop to a WAV file exactly as it plays: every layer with
    /// its own sound, level and mute, repeated `repeats` times, plus the tail.
    public func exportAudio(repeats: Int = 2) throws -> URL {
        guard hasContent else { throw ExportError.nothingToExport }
        // A separate engine renders faster than real time without disturbing
        // what is playing. It must use the live sample rate: the engine's
        // lookup tables are shared by the whole process.
        let sampleRate = synth.audioUnit.outputBusses[0].format.sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let unit = try? OpenFMAudioUnit(componentDescription: OpenFMAudioUnit.openFMDescription, options: []) else {
            throw ExportError.renderFailed
        }
        try unit.outputBusses[0].setFormat(format)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.looperSetTempo(Float(tempo), bars: bars, metronome: false, quantize: false)
        for layer in layers where layer.hasContent {
            guard let patch = layer.patch else { continue }
            load(layer.id, notes: layer.notes, patch: patch, into: unit)
            unit.looperSetLayer(layer.id, muted: layer.isMuted)
            unit.looperSetLayer(layer.id, volume: Float(layer.volume))
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenFM Loop.wav")
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames: AVAudioFrameCount = 512
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw ExportError.renderFailed }
        let block = unit.renderBlock
        var time = AudioTimeStamp()
        time.mFlags = .sampleTimeValid
        var flags = AudioUnitRenderActionFlags()

        func render(seconds: Double) throws {
            var remaining = Int(seconds * sampleRate)
            while remaining > 0 {
                let count = AVAudioFrameCount(min(remaining, Int(frames)))
                buffer.frameLength = count
                guard block(&flags, &time, count, 0, buffer.mutableAudioBufferList, nil) == noErr else {
                    throw ExportError.renderFailed
                }
                try file.write(from: buffer)
                time.mSampleTime += Double(count)
                remaining -= Int(count)
            }
        }

        // One silent buffer lets the engine take the layers in before the loop starts.
        buffer.frameLength = frames
        _ = block(&flags, &time, frames, 0, buffer.mutableAudioBufferList, nil)
        time.mSampleTime += Double(frames)

        unit.looperSetPlaying(true)
        try render(seconds: lengthBeats * 60 / tempo * Double(max(repeats, 1)))
        unit.looperSetPlaying(false)
        try render(seconds: 3)   // let reverb and echoes ring out
        return url
    }
}

// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import AudioToolbox
import Foundation
import Observation
import OpenFMEngine

/// The state the interface edits. Every change goes through the audio unit's
/// parameter tree, so hosts can record it as automation, and lands in the
/// engine without blocking.
@MainActor
@Observable
public final class SynthModel {
    public let audioUnit: OpenFMAudioUnit

    /// 156 unpacked DX7 voice bytes, mirroring the engine.
    public private(set) var bytes: [UInt8]
    /// Effect values indexed by `address - 200`.
    public private(set) var effects: [Double]
    public var name: String
    public var category = "User"
    /// Identifier of the preset this sound was loaded from.
    public var presetID: String?
    public private(set) var isEdited = false

    /// 1...6
    public var selectedOp = 1
    /// The parameter under the user's finger right now.
    public private(set) var focus: Param?
    /// Every parameter the current gesture changes (an envelope handle moves
    /// a rate and a level together).
    public private(set) var activeParams: Set<Param> = []
    /// Replaces the readout text while a gesture edits several values.
    public private(set) var customReadout: (title: String, value: String)?
    /// The parameter touched most recently; shown dimmed when idle.
    public private(set) var lastTouched: Param?

    /// Something to show in the readout for a moment without changing it:
    /// a control that was tapped, or a message such as an import result.
    public enum Peek: Equatable, Sendable {
        case param(Param)
        case macro(Macro)
        case notice(title: String, value: String)
    }

    public private(set) var peek: Peek?
    @ObservationIgnored private var peekCount = 0
    /// The sound as it was loaded or last saved; what Revert returns to.
    public private(set) var loadedPatch: Patch?

    /// The macro under the user's finger, if any.
    public private(set) var activeMacro: Macro?
    /// Macro positions, -1...1. Zero means "as the sound was designed".
    public private(set) var macroValues: [Macro: Double] = [:]
    /// The voice the macros are measured from.
    @ObservationIgnored private var macroBaseline: [UInt8] = []

    @ObservationIgnored private var observerToken: AUParameterObserverToken?
    @ObservationIgnored private var parameters: [Int: AUParameter] = [:]

    public init(audioUnit: OpenFMAudioUnit) {
        self.audioUnit = audioUnit
        bytes = [UInt8](audioUnit.patchData())
        effects = Param.allEffects.map { Double(audioUnit.value(forAddress: AUParameterAddress($0.address))) }
        name = audioUnit.patchName
        macroBaseline = bytes

        if let tree = audioUnit.parameterTree {
            for p in tree.allParameters { parameters[Int(p.address)] = p }
            observerToken = tree.token(byAddingParameterObserver: SynthModel.makeObserver(self))
        }
        audioUnit.stateRestoredHandler = SynthModel.makeRestoreHandler(self)
    }

    // Built outside the main actor: these run on arbitrary threads.
    private nonisolated static func makeObserver(_ model: SynthModel) -> AUParameterObserver {
        { [weak model] address, value in
            Task { @MainActor in model?.hostChanged(Int(address), Double(value)) }
        }
    }

    private nonisolated static func makeRestoreHandler(_ model: SynthModel) -> @Sendable () -> Void {
        { [weak model] in
            Task { @MainActor in model?.syncFromAudioUnit() }
        }
    }

    // MARK: Values

    public var algorithm: Algorithm { Algorithm.all[Int(bytes[134] & 31)] }

    public func value(_ p: Param) -> Double {
        switch p.address {
        case 0..<145: return Double(bytes[p.address])
        case 160..<166: return isOn(p.address - 159) ? 1 : 0
        case 200..<(200 + Param.effectCount): return effects[p.address - 200]
        default: return 0
        }
    }

    public func string(_ p: Param) -> String { p.string(value(p)) }

    public func set(_ p: Param, to newValue: Double) {
        let v = p.clamped(newValue)
        guard v != value(p) else { return }
        write(p, v)
        // A direct edit becomes the new starting point for the macros.
        if p.address < 166 { rebaseMacros() }
    }

    private func write(_ p: Param, _ v: Double) {
        store(p.address, v)
        isEdited = true
        parameters[p.address]?.setValue(AUValue(v), originator: observerToken)
    }

    private func rebaseMacros() {
        macroBaseline = bytes
        if !macroValues.isEmpty { macroValues = [:] }
    }

    public func reset(_ p: Param) { set(p, to: p.defaultValue) }

    private func store(_ address: Int, _ v: Double) {
        switch address {
        case 0..<145:
            bytes[address] = UInt8(v)
        case 160..<166:
            let bit = UInt8(1 << (5 - (address - 160)))
            if v >= 0.5 { bytes[155] |= bit } else { bytes[155] &= ~bit }
        case 200..<(200 + Param.effectCount):
            effects[address - 200] = v
        default:
            break
        }
    }

    private func hostChanged(_ address: Int, _ value: Double) {
        store(address, value)
        if address < 166 { rebaseMacros() }
    }

    private func syncFromAudioUnit() {
        bytes = [UInt8](audioUnit.patchData())
        effects = Param.allEffects.map { Double(audioUnit.value(forAddress: AUParameterAddress($0.address))) }
        name = audioUnit.patchName
        presetID = nil
        isEdited = false
        rebaseMacros()
        loadedPatch = patch
    }

    // MARK: Revert

    /// The value `p` had when the current sound was loaded.
    public func loadedValue(_ p: Param) -> Double? {
        guard let loadedPatch else { return nil }
        switch p.address {
        case 0..<145:
            return Double(loadedPatch.bytes[p.address])
        case 160..<166:
            return (loadedPatch.bytes[155] >> UInt8(5 - (p.address - 160))) & 1 == 1 ? 1 : 0
        default:
            guard let i = Param.patchEffects.firstIndex(of: p) else { return nil }
            return loadedPatch.effects.values[i]
        }
    }

    /// Puts one control back: to the loaded sound's value, or, if it is
    /// already there, to the parameter's neutral default.
    public func restore(_ p: Param) {
        if let loaded = loadedValue(p), p.clamped(loaded) != value(p) {
            set(p, to: loaded)
        } else {
            set(p, to: p.defaultValue)
        }
    }

    /// Discards every edit since the sound was loaded or saved.
    public func revert() {
        guard let loadedPatch else { return }
        load(loadedPatch, presetID: presetID)
    }

    // MARK: Peek

    /// Shows a control's name, value and hint in the readout for a moment.
    public func peek(_ p: Param) { show(.param(p)) }
    public func peek(_ macro: Macro) { show(.macro(macro)) }
    /// Shows a short message in the readout for a moment.
    public func post(title: String, value: String) { show(.notice(title: title, value: value), seconds: 3) }

    /// Ends a peek early, for example when the user taps the readout away.
    public func dismissPeek() {
        peek = nil
        peekCount += 1
    }

    private func show(_ peek: Peek, seconds: Double = 1.8) {
        self.peek = peek
        peekCount += 1
        let token = peekCount
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.peekCount == token else { return }
            self.peek = nil
        }
    }

    // MARK: Macros

    public func value(_ macro: Macro) -> Double { macroValues[macro] ?? 0 }

    /// Moves a macro. Each one offsets several voice parameters from where
    /// they were when the sound was loaded or last edited by hand.
    public func set(_ macro: Macro, to newValue: Double) {
        let v = min(max(newValue, -1), 1)
        guard v != value(macro) else { return }
        macroValues[macro] = v
        let algorithm = Algorithm.all[Int(macroBaseline[134] & 31)]
        for op in 1...6 {
            for (field, amount) in macro.offsets(isCarrier: algorithm.isCarrier(op)) {
                let p = Param.op(op, field)
                let base = Double(macroBaseline[p.address])
                // Leave silent operators silent.
                if field == .level, base == 0 { continue }
                let target = p.clamped(base + amount * v)
                if target != value(p) { write(p, target) }
            }
        }
    }

    public func beginEditing(_ macro: Macro) {
        if focus != nil || activeMacro != nil { endEditing() }
        peek = nil
        activeMacro = macro
    }

    /// Operators a macro reaches in the current algorithm.
    public func ops(for macro: Macro) -> Set<Int> {
        let algorithm = self.algorithm
        return Set((1...6).filter { !macro.offsets(isCarrier: algorithm.isCarrier($0)).isEmpty })
    }

    // MARK: Output

    /// The most recent output samples, oldest first, for drawing a scope.
    public func scope(count: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        audioUnit.copyScope(into: &samples, count: count)
        return samples
    }

    /// Voices sounding right now, 0...16.
    public var activeVoices: Int { audioUnit.activeVoices }

    // MARK: Gestures

    /// Call when a drag starts. Lights up the readout and everything the
    /// parameter affects, and tells the host a touch began.
    public func beginEditing(_ p: Param, with others: [Param] = []) {
        if let previous = focus, previous != p { endEditing() }
        peek = nil
        focus = p
        lastTouched = p
        activeParams = Set([p] + others)
        customReadout = nil
        if let op = p.op { selectedOp = op }
        for q in activeParams {
            if let au = parameters[q.address] {
                au.setValue(au.value, originator: observerToken, atHostTime: 0, eventType: .touch)
            }
        }
    }

    public func endEditing() {
        activeMacro = nil
        for q in activeParams {
            if let au = parameters[q.address] {
                au.setValue(au.value, originator: observerToken, atHostTime: 0, eventType: .release)
            }
        }
        focus = nil
        activeParams = []
        customReadout = nil
    }

    public func setReadout(title: String, value: String) {
        customReadout = (title, value)
    }

    /// Operators lit while `focus` is being edited: the operator itself and
    /// whatever it feeds, or the feedback loop, or everything.
    public var affectedOps: Set<Int> {
        if let macro = activeMacro { return ops(for: macro) }
        guard let p = focus else { return [] }
        if p == .algorithm { return Set(1...6) }
        if p == .feedback { return algorithm.feedbackOps }
        if let op = p.op { return algorithm.downstream(of: op) }
        return []
    }

    // MARK: Operators

    public func isOn(_ op: Int) -> Bool { (bytes[155] >> UInt8(6 - op)) & 1 == 1 }

    public func toggle(_ op: Int) {
        let p = Param.enabled(op)
        set(p, to: isOn(op) ? 0 : 1)
        lastTouched = p
    }

    public func isFixed(_ op: Int) -> Bool { value(.op(op, .mode)) == 1 }

    /// "×3.50" for ratio operators, "440 Hz" for fixed ones.
    public func frequencyText(_ op: Int) -> String {
        let coarse = value(.op(op, .coarse)), fine = value(.op(op, .fine))
        if isFixed(op) {
            let hz = pow(10, Double(Int(coarse) & 3) + fine / 100)
            return hz < 100 ? String(format: "%.1f Hz", hz) : String(format: "%.0f Hz", hz)
        }
        let ratio = (coarse == 0 ? 0.5 : coarse) * (1 + fine / 100)
        return String(format: "×%.2f", ratio)
    }

    // MARK: Readout

    public func title(_ p: Param) -> String {
        if p.address >= 160, p.address < 166, let op = p.op { return "OPERATOR \(op)" }
        if let op = p.op { return "OP \(op) · \(p.title)" }
        return p.title
    }

    public func readoutValue(_ p: Param) -> String {
        if let op = p.op, p == .op(op, .coarse) || p == .op(op, .fine) { return frequencyText(op) }
        return string(p)
    }

    /// One plain sentence about what the parameter does in this patch.
    public func hint(_ p: Param) -> String {
        let alg = algorithm
        if p == .algorithm {
            let c = alg.carriers.count
            return "\(c) carrier\(c == 1 ? "" : "s") heard · \(6 - c) modulator\(c == 5 ? "" : "s") shaping tone"
        }
        if p == .feedback {
            let f = alg.feedback
            return f.from == f.to ? "OP \(f.from) modulates itself · adds edge and noise"
                                  : "OP \(f.from) feeds back into OP \(f.to) · adds edge and noise"
        }
        guard let op = p.op else {
            switch p.address {
            case 126..<134: return "Bends the pitch of every note over time"
            case 137...143: return "Slow movement shared by all voices"
            case 144: return "Shifts the whole keyboard in semitones"
            case 200..<203: return "Thickens and widens the sound"
            case 203..<206: return "Repeats bouncing left and right"
            case 206..<209: return "Places the sound in a space"
            default: return ""
            }
        }
        let targets = alg.targets(of: op)
        let role = alg.isCarrier(op) ? "Carrier" : "Modulator"
        switch p.address - (6 - op) * 21 {
        case 16:
            return alg.isCarrier(op) ? "Carrier · how loud this layer is"
                : "Modulator · brightness of OP \(targets.map(String.init).joined(separator: ", "))"
        case 17, 18, 19:
            if isFixed(op) { return "\(role) · fixed pitch, ignores the keyboard" }
            return alg.isCarrier(op) ? "Carrier · pitch relative to the played note" : "Modulator · sets which harmonics appear"
        case 20: return "\(role) · slight pitch offset, adds movement"
        case 0..<8: return alg.isCarrier(op) ? "Carrier · how the volume moves over time" : "Modulator · how the brightness moves over time"
        case 8..<13: return "\(role) · level change across the keyboard"
        case 13: return "\(role) · higher notes move faster"
        case 14: return "\(role) · how much the LFO pulses this operator"
        case 15: return "\(role) · how much playing harder raises the level"
        default: return alg.isCarrier(op) ? "Carrier · heard directly" : "Modulator · shapes OP \(targets.map(String.init).joined(separator: ", "))"
        }
    }

    // MARK: Patches

    public var patch: Patch {
        var fx = Patch.Effects()
        fx.values = Param.patchEffects.map { value($0) }
        return Patch(bytes: bytes, name: name, category: category, effects: fx)
    }

    public func load(_ patch: Patch, presetID: String? = nil) {
        let newBytes = patch.bytes
        audioUnit.loadPatchData(Data(newBytes))
        audioUnit.patchName = patch.name
        bytes = newBytes
        for (p, v) in zip(Param.patchEffects, patch.effects.values) {
            let clamped = p.clamped(v)
            effects[p.address - 200] = clamped
            audioUnit.setValue(Float(clamped), forAddress: AUParameterAddress(p.address))
        }
        name = patch.name
        category = patch.category
        self.presetID = presetID
        isEdited = false
        focus = nil
        activeParams = []
        customReadout = nil
        lastTouched = nil
        activeMacro = nil
        macroBaseline = newBytes
        macroValues = [:]
        var kept = patch
        kept.effects.values = Param.patchEffects.map { value($0) }
        loadedPatch = kept
    }

    public func rename(_ newName: String) {
        name = newName
        audioUnit.patchName = newName
    }

    // MARK: Playing

    /// Hold works as a latch: notes keep sounding after you let go, and the
    /// next thing you play replaces them. Without that, held notes pile up
    /// until every voice is droning.
    public private(set) var isHolding = false
    /// Notes still sounding only because Hold is on.
    public private(set) var latchedNotes: Set<Int> = []
    @ObservationIgnored private var pressedNotes: Set<Int> = []

    public func noteOn(_ note: Int, velocity: Int) {
        // A new phrase (nothing else is down) lets go of the latched one.
        if isHolding, pressedNotes.isEmpty, !latchedNotes.isEmpty {
            for held in latchedNotes where held != note { audioUnit.noteOff(UInt8(clamping: held)) }
            latchedNotes = []
        }
        pressedNotes.insert(note)
        latchedNotes.remove(note)
        audioUnit.noteOn(UInt8(clamping: note), velocity: UInt8(clamping: velocity))
    }

    public func noteOff(_ note: Int) {
        pressedNotes.remove(note)
        if isHolding {
            latchedNotes.insert(note)
        } else {
            audioUnit.noteOff(UInt8(clamping: note))
        }
    }

    public func setHold(_ on: Bool) {
        isHolding = on
        if !on {
            for held in latchedNotes where !pressedNotes.contains(held) { audioUnit.noteOff(UInt8(clamping: held)) }
            latchedNotes = []
        }
    }

    /// Stops everything at once.
    public func panic() {
        pressedNotes = []
        latchedNotes = []
        audioUnit.panic()
    }

    /// Plays one short note so a sound can be heard without a keyboard, for
    /// example while browsing. Does nothing if something is already sounding.
    public func audition(note: Int = 60, velocity: Int = 100, seconds: Double = 0.6) {
        guard activeVoices == 0 else { return }
        noteOn(note, velocity: velocity)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.noteOff(note)
        }
    }
}

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

    /// Earlier and later states of the sound, for undo and redo.
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    /// The state before the edit in progress; kept only if something changes.
    @ObservationIgnored private var pendingUndo: Snapshot?
    @ObservationIgnored private var isGrouping = false

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
        armUndo()
        write(p, v)
        if p.address < 166 { absorb(p.address) }
    }

    private func write(_ p: Param, _ v: Double) {
        if SynthModel.isUndoable(p.address), let before = pendingUndo {
            pendingUndo = nil
            undoStack.append(before)
            if undoStack.count > 64 { undoStack.removeFirst() }
            redoStack = []
        }
        store(p.address, v)
        // How notes are played is not part of the sound.
        if !Param.performance.contains(p) { isEdited = true }
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

    /// Folds a direct edit into what the macros are measured from, so the
    /// macros stay where they are and still return to the edited sound.
    private func absorb(_ address: Int) {
        guard macroBaseline.count == bytes.count else { return rebaseMacros() }
        // A new algorithm changes which operators each macro reaches.
        if address == 134 { return rebaseMacros() }
        if address >= 160 {
            macroBaseline[155] = bytes[155]
        } else if address < 126 {
            let p = Param.op(6 - address / 21, Param.OpField(rawValue: address % 21)!)
            macroBaseline[address] = UInt8(p.clamped(Double(bytes[address]) - macroOffset(at: address)))
        } else {
            macroBaseline[address] = bytes[address]
        }
    }

    /// How far the macros currently push the operator parameter at `address`.
    private func macroOffset(at address: Int) -> Double {
        guard address < 126, let field = Param.OpField(rawValue: address % 21) else { return 0 }
        if field == .level, macroBaseline[address] == 0 { return 0 }
        let isCarrier = Algorithm.all[Int(macroBaseline[134] & 31)].isCarrier(6 - address / 21)
        return macroValues.reduce(0) { $0 + ($1.key.offsets(isCarrier: isCarrier)[field] ?? 0) * $1.value }
    }

    private func hostChanged(_ address: Int, _ value: Double) {
        store(address, value)
        if address < 166 { absorb(address) }
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
        let before = snapshot()
        let steps = undoStack
        load(loadedPatch, presetID: presetID)
        // Reverting is itself an edit that can be undone.
        if before != snapshot() { undoStack = steps + [before] }
    }

    // MARK: Undo

    private struct Snapshot: Equatable {
        var bytes: [UInt8]
        var effects: [Double]
        var macroValues: [Macro: Double]
        var macroBaseline: [UInt8]
    }

    /// The voice, operator switches and the effects saved with a sound can be
    /// undone; volume and playing settings are left alone.
    private static func isUndoable(_ address: Int) -> Bool {
        address < 166 || (200..<(200 + Param.patchEffects.count)).contains(address)
    }

    private func snapshot() -> Snapshot {
        Snapshot(bytes: bytes, effects: Param.patchEffects.map { value($0) },
                 macroValues: macroValues, macroBaseline: macroBaseline)
    }

    /// Remembers the sound as it is now, to be kept if the next edit changes
    /// it. A gesture arms once when it begins, so a whole drag is one step.
    private func armUndo() {
        if focus == nil, activeMacro == nil, !isGrouping { pendingUndo = snapshot() }
    }

    private func grouped(_ edits: () -> Void) {
        pendingUndo = snapshot()
        isGrouping = true
        edits()
        isGrouping = false
        pendingUndo = nil
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Steps back one edit: a whole drag, a tap, or one Vary.
    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        apply(previous)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        apply(next)
    }

    private func apply(_ s: Snapshot) {
        if focus != nil || activeMacro != nil { endEditing() }
        pendingUndo = nil
        audioUnit.loadPatchData(Data(s.bytes))
        bytes = s.bytes
        for (p, v) in zip(Param.patchEffects, s.effects) {
            effects[p.address - 200] = v
            audioUnit.setValue(Float(v), forAddress: AUParameterAddress(p.address))
        }
        macroValues = s.macroValues
        macroBaseline = s.macroBaseline
        if let loadedPatch {
            isEdited = loadedPatch.bytes != s.bytes || loadedPatch.effects.values != s.effects
        } else {
            isEdited = true
        }
    }

    // MARK: Variations

    /// Nudges the sound into a near relative of itself: modulator levels,
    /// envelope speeds, detune and feedback move a little, and now and then a
    /// modulator jumps to a neighbouring harmonic. One undo step.
    public func vary(amount: Double = 0.5) {
        var generator = SystemRandomNumberGenerator()
        vary(amount: amount, using: &generator)
    }

    public func vary<G: RandomNumberGenerator>(amount: Double = 0.5, using generator: inout G) {
        let amount = min(max(amount, 0), 1)
        let algorithm = self.algorithm
        func nudge(_ p: Param, by spread: Double) {
            let reach = spread * amount
            guard reach >= 0.5 else { return }
            set(p, to: value(p) + Double.random(in: -reach...reach, using: &generator).rounded())
        }
        grouped {
            for op in 1...6 where isOn(op) && value(.op(op, .level)) > 0 {
                let carrier = algorithm.isCarrier(op)
                if !carrier {
                    nudge(.op(op, .level), by: 16)
                    if !isFixed(op), Double.random(in: 0..<1, using: &generator) < 0.3 * amount {
                        let step: Double = Bool.random(using: &generator) ? 1 : -1
                        set(.op(op, .coarse), to: max(1, value(.op(op, .coarse)) + step))
                    }
                }
                nudge(.op(op, .detune), by: 4)
                nudge(.op(op, .rate2), by: carrier ? 10 : 20)
                nudge(.op(op, .rate3), by: carrier ? 10 : 20)
                if !carrier { nudge(.op(op, .level2), by: 16) }
            }
            nudge(.feedback, by: 3)
        }
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

    /// Moves a macro. Each one offsets several voice parameters from the
    /// sound as loaded. Editing a parameter by hand moves that starting
    /// point and leaves the macros where they are.
    public func set(_ macro: Macro, to newValue: Double) {
        let v = min(max(newValue, -1), 1)
        guard v != value(macro) else { return }
        armUndo()
        macroValues[macro] = v
        let algorithm = Algorithm.all[Int(macroBaseline[134] & 31)]
        for op in 1...6 {
            for field in macro.offsets(isCarrier: algorithm.isCarrier(op)).keys {
                let p = Param.op(op, field)
                let base = Double(macroBaseline[p.address])
                // Leave silent operators silent.
                if field == .level, base == 0 { continue }
                // Every macro reaching this parameter adds its share.
                let target = p.clamped(base + macroOffset(at: p.address))
                if target != value(p) { write(p, target) }
            }
        }
    }

    public func beginEditing(_ macro: Macro) {
        if focus != nil || activeMacro != nil { endEditing() }
        pendingUndo = snapshot()
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
        if focus == nil { pendingUndo = snapshot() }
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
        pendingUndo = nil
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
            case 211: return "One note at a time · overlapping notes slide instead of restarting"
            case 212: return "How long a slide between overlapping notes takes · mono only"
            case 213: return "Plays held keys one after another"
            case 214: return "Arpeggio steps per beat"
            case 215: return "Arpeggio speed · follows the loop tempo"
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
        undoStack = []
        redoStack = []
        pendingUndo = nil
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

    /// Where the on-screen bender and wheel are, for drawing them.
    public private(set) var pitchBend = 0.0
    public private(set) var modWheel = 0.0

    /// Bends every sounding note: -1...1 of the bend range, 0 is centre.
    public func setPitchBend(_ amount: Double) {
        pitchBend = min(max(amount, -1), 1)
        audioUnit.sendPitchBend(UInt16(8192 + (pitchBend * 8191).rounded()))
    }

    /// Adds vibrato, 0...1, like a keyboard's modulation wheel.
    public func setModWheel(_ amount: Double) {
        modWheel = min(max(amount, 0), 1)
        audioUnit.sendController(1, value: UInt8((modWheel * 127).rounded()))
    }

    /// The loudest carrier that is switched on: the operator whose envelope
    /// best stands for how the whole sound rises and fades.
    public var mainCarrier: Int {
        let carriers = algorithm.carriers.filter { isOn($0) }
        return carriers.max { value(.op($0, .level)) < value(.op($1, .level)) } ?? algorithm.carriers.first ?? 1
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

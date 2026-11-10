// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI
import UIKit

/// The playing surface: a multi-touch keyboard with an octave shifter and a
/// hold switch. Touch lower on a key to play louder; slide to glide across
/// keys.
struct KeyboardSection: View {
    @Environment(SynthModel.self) private var model
    @State private var octave = 3

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                OctaveDial(octave: $octave)
                Text("OCTAVE").labelStyle(9)

                Spacer(minLength: 0)

                let hold = model.isHolding
                Button {
                    model.setHold(!hold)
                    Haptics.tap()
                } label: {
                    Text("HOLD")
                        .labelStyle(9, color: hold ? Theme.background : Theme.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(hold ? Theme.accent : Theme.surface, in: Capsule())
                        .frame(minWidth: 64, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hold")
                .accessibilityHint("Keeps notes sounding until you play something else")
                .accessibilityAddTraits(hold ? [.isSelected] : [])
            }
            .padding(.horizontal, Theme.gutter)
            .frame(height: 44)

            KeyboardView(lowestNote: (octave + 2) * 12,
                         latched: model.latchedNotes,
                         noteOn: { note, velocity in model.noteOn(note, velocity: velocity) },
                         noteOff: { note in model.noteOff(note) },
                         shiftOctave: { delta in
                             let next = min(max(octave + delta, 0), 7)
                             if next == octave { Haptics.bump() } else { octave = next }
                         })
                .accessibilityElement()
                .accessibilityLabel("Keyboard")
                .accessibilityAddTraits(.allowsDirectInteraction)
        }
    }
}

/// The keyboard's octave as a dial: swipe it sideways and the octaves roll
/// past with a click each, like a thumbwheel. Tapping either side steps once.
struct OctaveDial: View {
    @Binding var octave: Int

    private let range = 0...7
    private let pitch: CGFloat = 44
    @State private var startOctave: Int?
    @State private var offset: CGFloat = 0
    @GestureState private var isDragging = false

    var body: some View {
        ZStack {
            ForEach(Array(range), id: \.self) { o in
                let x = CGFloat(o - octave) * pitch + offset
                Text("C\(o)")
                    .font(.value(13, weight: o == octave ? .semibold : .medium))
                    .foregroundStyle(o == octave ? Theme.text : Theme.secondary)
                    .opacity(max(0, 1 - abs(x) / (pitch * 1.7)))
                    .offset(x: x)
            }
        }
        .frame(width: pitch * 3, height: 28)
        .background(Theme.surface, in: Capsule())
        .overlay(alignment: .bottom) {
            // The fixed mark the scale rolls under.
            Capsule().fill(isDragging ? Theme.accent : Theme.secondary).frame(width: 14, height: 2).padding(.bottom, 2)
        }
        .clipShape(Capsule())
        .frame(height: 44)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { g in
                    if startOctave == nil { startOctave = octave }
                    guard let startOctave else { return }
                    // The scale follows the finger: pull it left to reach higher octaves.
                    let wanted = Double(startOctave) - g.translation.width / pitch
                    let next = min(max(Int(wanted.rounded()), range.lowerBound), range.upperBound)
                    if next != octave {
                        octave = next
                        if next == range.lowerBound || next == range.upperBound { Haptics.bump() } else { Haptics.tick() }
                    }
                    let residual = g.translation.width + CGFloat(next - startOctave) * pitch
                    // Past the last octave the scale resists instead of following.
                    offset = abs(residual) > pitch / 2 ? residual.sign() * (pitch / 2 + (abs(residual) - pitch / 2) * 0.15) : residual
                }
        )
        .simultaneousGesture(
            SpatialTapGesture().onEnded { tap in
                step(tap.location.x > pitch * 1.5 ? 1 : -1)
            }
        )
        .onChange(of: isDragging) { _, dragging in
            if !dragging {
                startOctave = nil
                withAnimation(.snappy(duration: 0.2)) { offset = 0 }
            }
        }
        .animation(.snappy(duration: 0.2), value: octave)
        .accessibilityElement()
        .accessibilityLabel("Octave")
        .accessibilityValue("C\(octave)")
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    private func step(_ delta: Int) {
        let next = min(max(octave + delta, range.lowerBound), range.upperBound)
        if next == octave {
            Haptics.bump()
        } else {
            octave = next
            Haptics.tick()
        }
    }
}

private extension CGFloat {
    func sign() -> CGFloat { self < 0 ? -1 : 1 }
}

struct KeyboardView: UIViewRepresentable {
    /// MIDI note of the leftmost key (a C).
    let lowestNote: Int
    /// Notes kept sounding by Hold; drawn dimly lit.
    var latched: Set<Int> = []
    let noteOn: (Int, Int) -> Void
    let noteOff: (Int) -> Void
    /// Called with -1 or +1 when a hardware keyboard asks for another octave.
    var shiftOctave: (Int) -> Void = { _ in }

    func makeUIView(context: Context) -> KeysView {
        let view = KeysView()
        view.noteOn = noteOn
        view.noteOff = noteOff
        view.shiftOctave = shiftOctave
        view.lowestNote = lowestNote
        return view
    }

    func updateUIView(_ view: KeysView, context: Context) {
        view.noteOn = noteOn
        view.noteOff = noteOff
        view.shiftOctave = shiftOctave
        if view.lowestNote != lowestNote { view.lowestNote = lowestNote }
        if view.latched != latched { view.latched = latched }
        view.claimHardwareKeyboard()
    }
}

final class KeysView: UIView {
    var noteOn: (Int, Int) -> Void = { _, _ in }
    var noteOff: (Int) -> Void = { _ in }
    var lowestNote = 60 {
        didSet {
            releaseAll()
            setNeedsDisplay()
        }
    }

    var shiftOctave: (Int) -> Void = { _ in }
    var latched: Set<Int> = [] {
        didSet { setNeedsDisplay() }
    }

    private var held: [UITouch: Int] = [:]
    /// Notes held from a hardware keyboard, by physical key.
    private var typed: [UIKeyboardHIDUsage: Int] = [:]

    /// A connected keyboard plays like a piano: the home row is the white
    /// keys from the leftmost C, the row above holds the black keys, and
    /// Z / X move down and up an octave.
    ///
    ///      W E   T Y U   O P
    ///     A S D F G H J K L ; '
    private static let typedOffsets: [UIKeyboardHIDUsage: Int] = [
        .keyboardA: 0, .keyboardW: 1, .keyboardS: 2, .keyboardE: 3, .keyboardD: 4, .keyboardF: 5,
        .keyboardT: 6, .keyboardG: 7, .keyboardY: 8, .keyboardH: 9, .keyboardU: 10, .keyboardJ: 11,
        .keyboardK: 12, .keyboardO: 13, .keyboardL: 14, .keyboardP: 15, .keyboardSemicolon: 16,
        .keyboardQuote: 17,
    ]
    private static let typedVelocity = 100
    private static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
    /// White-key indices within an octave that have a black key to their right.
    private static let blackAfter: [Int: Int] = [0: 1, 1: 3, 3: 6, 4: 8, 5: 10]

    private let whiteColor = UIColor.dynamic(light: 0xFFFFFF, dark: 0xE9E7E1)
    private let blackColor = UIColor.dynamic(light: 0x161616, dark: 0x0C0C0D)
    private let gapColor = UIColor.dynamic(light: 0xF2F1ED, dark: 0x09090A)
    private let labelColor = UIColor(hex: 0x121212, alpha: 0.45)
    private let accent = UIColor.dynamic(light: 0x3F7A00, dark: 0xCCFF00)
    /// Held by the latch: tinted, but clearly not under a finger.
    private let latchedWhite = UIColor.dynamic(light: 0xC5DDA8, dark: 0xDDF08A)
    private let latchedBlack = UIColor.dynamic(light: 0x2C5200, dark: 0x5A7000)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: KeysView, _) in view.setNeedsDisplay() }
        // Take the hardware keyboard back once a search or name field is done with it.
        NotificationCenter.default.addObserver(forName: UITextField.textDidEndEditingNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.claimHardwareKeyboard() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Geometry

    private var whiteCount: Int {
        let target: CGFloat = bounds.width > 700 ? 56 : 46
        return max(7, Int((bounds.width / target).rounded()))
    }

    private var whiteWidth: CGFloat { bounds.width / CGFloat(whiteCount) }
    private var blackSize: CGSize { CGSize(width: whiteWidth * 0.58, height: bounds.height * 0.6) }

    private func whiteNote(_ index: Int) -> Int {
        lowestNote + (index / 7) * 12 + KeysView.whiteOffsets[index % 7]
    }

    private func blackKeys() -> [(note: Int, rect: CGRect)] {
        var keys: [(Int, CGRect)] = []
        for i in 0..<(whiteCount - 1) {
            guard let offset = KeysView.blackAfter[i % 7] else { continue }
            let x = CGFloat(i + 1) * whiteWidth - blackSize.width / 2
            keys.append((lowestNote + (i / 7) * 12 + offset, CGRect(origin: CGPoint(x: x, y: 0), size: blackSize)))
        }
        return keys
    }

    /// The key under a point and how hard it is struck there (lower = louder).
    private func key(at point: CGPoint) -> (note: Int, velocity: Int)? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        func velocity(_ fraction: CGFloat) -> Int { Int(36 + 91 * min(max(fraction, 0), 1)) }
        for key in blackKeys() where key.rect.contains(point) {
            return (key.note, velocity(point.y / key.rect.height))
        }
        let index = min(max(Int(point.x / whiteWidth), 0), whiteCount - 1)
        return (min(whiteNote(index), 127), velocity(point.y / bounds.height))
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let key = key(at: touch.location(in: self)) else { continue }
            held[touch] = key.note
            noteOn(key.note, key.velocity)
            Haptics.key(velocity: key.velocity)
        }
        setNeedsDisplay()
        claimHardwareKeyboard()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var changed = false
        for touch in touches {
            guard let key = key(at: touch.location(in: self)), held[touch] != key.note else { continue }
            if let old = held[touch], !held.contains(where: { $0.key != touch && $0.value == old }) { noteOff(old) }
            held[touch] = key.note
            noteOn(key.note, key.velocity)
            // Gliding onto a new key is a lighter touch than striking it.
            Haptics.key(velocity: key.velocity / 3)
            changed = true
        }
        if changed { setNeedsDisplay() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }

    private func release(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let note = held.removeValue(forKey: touch) else { continue }
            if !held.values.contains(note) { noteOff(note) }
        }
        setNeedsDisplay()
    }

    private func releaseAll() {
        for note in Set(held.values).union(typed.values) { noteOff(note) }
        held.removeAll()
        typed.removeAll()
    }

    // MARK: Hardware keyboard

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        claimHardwareKeyboard()
    }

    /// Takes key presses unless a text field is being typed into.
    func claimHardwareKeyboard() {
        guard window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            if !(window.firstResponder is UITextInput) { self.becomeFirstResponder() }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            // Leave shortcuts (⌘, ⌃, ⌥ combinations) to the system.
            guard let key = press.key, key.modifierFlags.isDisjoint(with: [.command, .control, .alternate]) else {
                unhandled.insert(press)
                continue
            }
            if let offset = KeysView.typedOffsets[key.keyCode] {
                let note = min(lowestNote + offset, 127)
                if typed[key.keyCode] == nil {
                    typed[key.keyCode] = note
                    noteOn(note, KeysView.typedVelocity)
                }
            } else if key.keyCode == .keyboardZ {
                shiftOctave(-1)
            } else if key.keyCode == .keyboardX {
                shiftOctave(1)
            } else {
                unhandled.insert(press)
            }
        }
        setNeedsDisplay()
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseTyped(presses)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseTyped(presses)
        super.pressesCancelled(presses, with: event)
    }

    private func releaseTyped(_ presses: Set<UIPress>) {
        for press in presses {
            guard let code = press.key?.keyCode, let note = typed.removeValue(forKey: code) else { continue }
            if !typed.values.contains(note), !held.values.contains(note) { noteOff(note) }
        }
        setNeedsDisplay()
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        gapColor.setFill()
        UIRectFill(bounds)
        let down = Set(held.values).union(typed.values)
        let w = whiteWidth

        for i in 0..<whiteCount {
            let note = whiteNote(i)
            let keyRect = CGRect(x: CGFloat(i) * w + 0.5, y: 0, width: w - 1, height: bounds.height)
            (down.contains(note) ? accent : (latched.contains(note) ? latchedWhite : whiteColor)).setFill()
            UIBezierPath(roundedRect: keyRect, byRoundingCorners: [.bottomLeft, .bottomRight],
                         cornerRadii: CGSize(width: 5, height: 5)).fill()
            if i % 7 == 0, bounds.height > 70 {
                let text = "C\(note / 12 - 2)" as NSString
                let font = UIFont(name: Typeface.monoMedium, size: 9) ?? .monospacedSystemFont(ofSize: 9, weight: .medium)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: labelColor, .kern: 0.6]
                let size = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: keyRect.midX - size.width / 2, y: bounds.height - size.height - 8),
                          withAttributes: attributes)
            }
        }
        for key in blackKeys() {
            (down.contains(key.note) ? accent : (latched.contains(key.note) ? latchedBlack : blackColor)).setFill()
            UIBezierPath(roundedRect: key.rect, byRoundingCorners: [.bottomLeft, .bottomRight],
                         cornerRadii: CGSize(width: 4, height: 4)).fill()
        }
    }
}

private extension UIWindow {
    /// The view currently receiving key presses, if any.
    var firstResponder: UIResponder? {
        func find(_ view: UIView) -> UIResponder? {
            if view.isFirstResponder { return view }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        return find(self)
    }
}

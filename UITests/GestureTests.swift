// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// Exercises the real gestures on a running app.
final class GestureTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(mode: String) {
        app.launchArguments = ["-openfm.preset", "Glass Keys", "-openfm.page", "algorithm", "-openfm.mode", mode]
        app.launch()
    }

    /// The simple side: a macro moves, the sound is marked as adjusted, and
    /// double-tap puts it back.
    func testPlayModeMacros() {
        launch(mode: "play")
        let tone = element("Tone")
        XCTAssertTrue(tone.waitForExistence(timeout: 10))
        XCTAssertEqual(tone.value as? String, "0")
        XCTAssertFalse(element("Operator 6, modulator").exists, "the editor stays out of Play mode")

        let centre = tone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        centre.press(forDuration: 0.1, thenDragTo: centre.withOffset(CGVector(dx: 70, dy: 0)))
        let raised = tone.value as? String ?? ""
        XCTAssertTrue(raised.hasPrefix("+"), "tone after dragging right: \(raised)")
        attach("play mode, tone raised")

        tone.doubleTap()
        XCTAssertEqual(tone.value as? String, "0")

        // The octave dial rolls with a swipe and steps with a tap on either side.
        let dial = element("Octave")
        XCTAssertEqual(dial.value as? String, "C3")
        let middle = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: -90, dy: 0)))
        XCTAssertEqual(dial.value as? String, "C5", "pulling the scale left two notches")
        dial.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        XCTAssertEqual(dial.value as? String, "C4")
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: 600, dy: 0)))
        XCTAssertEqual(dial.value as? String, "C0", "the dial stops at the lowest octave")
        attach("octave dial")
        XCTAssertTrue(app.buttons["Import"].exists)

        // On iPad the sound list is always there: tap a name and it is loaded.
        let row = app.buttons["Felt Tines"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(element("Sound: Felt Tines").waitForExistence(timeout: 5))

        // Editing marks the sound; Revert puts it back.
        let reverb = element("Reverb Mix")
        let original = reverb.value as? String
        let r = reverb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        r.press(forDuration: 0.1, thenDragTo: r.withOffset(CGVector(dx: 80, dy: 0)))
        XCTAssertNotEqual(reverb.value as? String, original)
        XCTAssertTrue(element("Sound: Felt Tines, edited").exists)
        reverb.doubleTap()
        XCTAssertEqual(reverb.value as? String, original, "double-tap returns to the loaded sound's value")
        r.press(forDuration: 0.1, thenDragTo: r.withOffset(CGVector(dx: -60, dy: 0)))
        app.buttons["Save"].tap()
        app.buttons["Revert to Original"].tap()
        XCTAssertEqual(reverb.value as? String, original)
        XCTAssertTrue(element("Sound: Felt Tines").waitForExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    func testDraggingAnOperatorChangesLevelAndRatio() {
        launch(mode: "edit")
        let op = element("Operator 6, modulator")
        XCTAssertTrue(op.waitForExistence(timeout: 10))
        XCTAssertEqual(op.value as? String, "Level 76, ×1.00")

        // Up raises the level.
        let centre = op.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        centre.press(forDuration: 0.1, thenDragTo: centre.withOffset(CGVector(dx: 0, dy: -30)))
        let raised = op.value as? String ?? ""
        XCTAssertTrue(raised.hasPrefix("Level 9"), "level after dragging up: \(raised)")
        attach("level raised")

        // Sideways changes the ratio and leaves the level alone.
        centre.press(forDuration: 0.1, thenDragTo: centre.withOffset(CGVector(dx: 60, dy: 0)))
        let shifted = op.value as? String ?? ""
        XCTAssertEqual(shifted.components(separatedBy: ", ").first, raised.components(separatedBy: ", ").first)
        XCTAssertFalse(shifted.hasSuffix("×1.00"), "ratio after dragging sideways: \(shifted)")

        // Double-tap switches the operator off and on again.
        op.doubleTap()
        XCTAssertEqual(op.value as? String, "Off")
        op.doubleTap()
        XCTAssertNotEqual(op.value as? String, "Off")
    }

    func testScrubbingTheAlgorithmAndDraggingAField() {
        launch(mode: "edit")
        let algorithm = element("Algorithm")
        XCTAssertTrue(algorithm.waitForExistence(timeout: 10))
        XCTAssertTrue((algorithm.value as? String ?? "").hasPrefix("5,"))
        let start = algorithm.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 80, dy: 0)))
        let value = algorithm.value as? String ?? ""
        XCTAssertFalse(value.hasPrefix("5,"), "algorithm after scrubbing: \(value)")
        attach("algorithm scrubbed")

        let feedback = element("Feedback")
        XCTAssertEqual(feedback.value as? String, "5")
        let f = feedback.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        f.press(forDuration: 0.1, thenDragTo: f.withOffset(CGVector(dx: -70, dy: 0)))
        XCTAssertNotEqual(feedback.value as? String, "5")

        // A vertical drag on a cell is left to the page, so it changes nothing.
        let held = feedback.value as? String
        f.press(forDuration: 0.1, thenDragTo: f.withOffset(CGVector(dx: 0, dy: -70)))
        XCTAssertEqual(feedback.value as? String, held)
    }

    /// An effect pad only moves when its dot is dragged; a swipe across the
    /// rest of the pad is left to the page.
    func testEffectPadMovesOnlyFromItsDot() {
        launch(mode: "edit")
        app.buttons["Effects"].tap()
        let pad = element("Delay pad")
        XCTAssertTrue(pad.waitForExistence(timeout: 10))
        let original = pad.value as? String
        XCTAssertEqual(original, "Time 350 ms, Repeats 35")

        let body = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.25))
        body.press(forDuration: 0.1, thenDragTo: body.withOffset(CGVector(dx: 0, dy: -60)))
        XCTAssertEqual(element("Delay pad").value as? String, original, "swiping the pad body changes nothing")

        // The dot sits about a quarter across and 60% down for these settings.
        let moved = element("Delay pad")
        let dot = moved.coordinate(withNormalizedOffset: CGVector(dx: 0.27, dy: 0.6))
        dot.press(forDuration: 0.1, thenDragTo: dot.withOffset(CGVector(dx: 60, dy: -20)))
        XCTAssertNotEqual(element("Delay pad").value as? String, original, "dragging the dot does")
        attach("delay pad after dragging its dot")
    }

    func testPagesKeyboardAndBrowser() {
        launch(mode: "edit")
        let pages = ["Operator", "Motion", "Effects"]
        for page in pages {
            let tab = app.buttons[page]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), page)
            tab.tap()
            attach(page)
        }
        XCTAssertTrue(element("Delay pad").exists)

        let keyboard = element("Keyboard")
        XCTAssertTrue(keyboard.exists)
        keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)).press(forDuration: 0.3)

        element("Sound: Glass Keys").tap()
        XCTAssertTrue(app.navigationBars["Sounds"].waitForExistence(timeout: 5))
        attach("browser")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Felt Tines")).firstMatch.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(element("Sound: Felt Tines").waitForExistence(timeout: 5))
    }
}

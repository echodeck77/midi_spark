//  PartPlayButtonTests.swift — PLAY RIFF / PLAY STACK ferry (2026-11-07): the pure layer (`euclideousPartPlay*` in Derivations.swift). Looks (§2.4), the lamp geometry (§2.3) and the flash decision + activity (§2.5, test 3).

import XCTest

final class PartPlayButtonTests: XCTestCase {
    private func close(_ a: Double, _ b: Double, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: 0.0005, msg, file: file, line: line)
    }

    // MARK: §2.4 the looks
    func testLooks() {
        let on = euclideousPartPlayLook(on: true)
        XCTAssertEqual(on.playHex, 0xAAB0BA); XCTAssertEqual(on.nameHex, 0xF2F4F7); XCTAssertTrue(on.lampFilled); XCTAssertTrue(on.lampUsesLane)
        let off = euclideousPartPlayLook(on: false)
        XCTAssertEqual(off.playHex, 0x6E737C); XCTAssertEqual(off.nameHex, 0x8A909A); XCTAssertFalse(off.lampFilled); XCTAssertFalse(off.lampUsesLane); XCTAssertEqual(off.lampStrokeHex, 0x6E737C)   // AMENDMENT 1 §A4.3
        XCTAssertEqual(EuclideousPartPlayLook.tileFillHex, 0x202226); XCTAssertEqual(EuclideousPartPlayLook.tileBorderHex, 0x2B2D33); close(EuclideousPartPlayLook.tileRadius, 9, "the source play tile's radius")
    }

    // MARK: §2.3 the lamp geometry
    func testLampGeometry() {
        XCTAssertEqual(EuclideousPartPlayLamp.points, [CGPoint(x: 1, y: 1), CGPoint(x: 7, y: 4.5), CGPoint(x: 1, y: 8)], "M1 1 L7 4.5 L1 8 Z")
        XCTAssertEqual(EuclideousPartPlayLamp.pathBounds, CGRect(x: 1, y: 1, width: 6, height: 7), "the triangle's bounds in the 8×9 box")
        XCTAssertEqual(EuclideousPartPlayLamp.size, CGSize(width: 5.5, height: 6), "drawn 5.5 × 6")
    }

    // MARK: test 3 — the flash decision (§2.5)
    func testFlashDecision() {
        XCTAssertTrue(euclideousPartPlayFlashes(outs: 0b0001, audible: true), "a note that reached ≥1 emitter, audible")
        XCTAssertFalse(euclideousPartPlayFlashes(outs: 0, audible: true), "routed nowhere")
        XCTAssertFalse(euclideousPartPlayFlashes(outs: 0b1111, audible: false), "silenced by solo / LANES / play")
    }

    // MARK: §2.5 the flash activity
    private func note(_ onBeat: Double, outs: UInt8) -> NoteRollNote { NoteRollNote(onBeat: onBeat, endBeat: nil, pitch: 60, velocity: 100, outs: outs) }

    func testFlashFull_OnNoteOnToAnEmitter() {
        let a = euclideousPartPlayFlash(notes: [note(1, outs: 0b0001)], nowBeat: 1, tempo: 120, audible: true, reduceMotion: false)
        close(a, 1, "full at the note-on")
    }
    func testFlashNone_RoutedNowhere() {
        close(euclideousPartPlayFlash(notes: [note(1, outs: 0)], nowBeat: 1, tempo: 120, audible: true, reduceMotion: false), 0)
    }
    func testFlashNone_Silenced() {
        close(euclideousPartPlayFlash(notes: [note(1, outs: 0b0001)], nowBeat: 1, tempo: 120, audible: false, reduceMotion: false), 0)
    }
    func testFlashNone_PartOffHasNoEmittingNotes() {
        close(euclideousPartPlayFlash(notes: [], nowBeat: 1, tempo: 120, audible: true, reduceMotion: false), 0)
    }
    func testFlashChordFlashesOnce() {
        // two notes at the same onset → the newest onset is that beat, so one activity value (not doubled)
        let a = euclideousPartPlayFlash(notes: [note(1, outs: 0b0001), note(1, outs: 0b0010)], nowBeat: 1, tempo: 120, audible: true, reduceMotion: false)
        close(a, 1, "a chord is one flash")
    }
    func testFlashFadesOver150ms() {
        // tempo 120 ⇒ 0.075 s ago = 0.15 beats; halfway through the 150 ms fade
        close(euclideousPartPlayFlash(notes: [note(1 - 0.15, outs: 0b0001)], nowBeat: 1, tempo: 120, audible: true, reduceMotion: false), 0.5, "linear fade, half way")
        close(euclideousPartPlayFlash(notes: [note(1 - 0.3, outs: 0b0001)], nowBeat: 1, tempo: 120, audible: true, reduceMotion: false), 0, "gone by 150 ms (0.3 beats)")
    }
    func testFlashNewerOnsetRestarts() {
        // an old note (faded) and a fresh one → the fresh one wins (max onset)
        let a = euclideousPartPlayFlash(notes: [note(1 - 0.3, outs: 0b0001), note(1, outs: 0b0001)], nowBeat: 1, tempo: 120, audible: true, reduceMotion: false)
        close(a, 1, "the newer note-on restarts the flash")
    }
    func testFlashReduceMotion_FullFor100msNoFade() {
        // tempo 120 ⇒ 0.05 s ago = 0.1 beats (within 100 ms) → full; 0.15 s ago = 0.3 beats → gone
        close(euclideousPartPlayFlash(notes: [note(1 - 0.1, outs: 0b0001)], nowBeat: 1, tempo: 120, audible: true, reduceMotion: true), 1, "full within 100 ms")
        close(euclideousPartPlayFlash(notes: [note(1 - 0.3, outs: 0b0001)], nowBeat: 1, tempo: 120, audible: true, reduceMotion: true), 0, "off after 100 ms, no fade")
    }

    // MARK: test 1 — the tiles keep the play / SOLO frames; the comet strip is unchanged (§1, §7.1)
    func testTheTilesKeepThePlayAndSoloFrames() {
        XCTAssertEqual(EuclideousLockBadge.playW, 44, "PLAY RIFF takes the 44 pt play-tile slot")
        XCTAssertEqual(EuclideousLockBadge.soloW, 44, "PLAY STACK takes the 44 pt SOLO-tile slot")
        let inner: CGFloat = 360.67   // landscape card 380.67 − 20 inset
        close(Double(EuclideousLockBadge.cometStripWidth(innerWidth: inner, withBadge: false)), 264.67, "AMENDMENT 1: g = 4 either side of the strip (lead 48, trail 48)")
        close(Double(EuclideousLockBadge.cometStripWidth(innerWidth: inner, withBadge: true)), 226.67, "with a lock badge the strip ends g before it, and the badge sits g before PLAY STACK (trail 4+34+4+44)")
    }

    // MARK: test 2 — a tap writes the field the lamp reads (§3; cardBackToggle's mutation)
    func testPlayRiffWritesRiffOnAndTheLampReadsIt() {
        var l = EuclidLine(noteSel: .all); l.riffOn = false
        XCTAssertTrue(euclideousMixLayerIsOff(l, notes: false), "lamp off")
        l.riffOn = !l.riffOnResolved   // the tap = cardBackToggle(.riff)
        XCTAssertTrue(l.riffOnResolved); XCTAssertFalse(euclideousMixLayerIsOff(l, notes: false), "lamp on, reads the field the tap wrote")
    }
    func testPlayStackTurnsTheNotesLayerOnWithAutoLightAndTheLampReadsIt() {
        var l = EuclidLine(noteSel: .all); l.notesOn = false; l.setLitOrder(EuclideousLitOrder())   // notes off, nothing selected
        XCTAssertTrue(euclideousMixLayerIsOff(l, notes: true), "lamp off")
        // the tap = cardBackToggle(.notes): turn on, and auto-light rank 1 if nothing is selected (so the layer actually reads on)
        if euclideousNotesLayerIsOn(l) { l.notesOn = false } else { l.notesOn = true; if !euclideousNotesHaveSelection(l) { var o = EuclideousLitOrder(); o.append(0); l.setLitOrder(o) } }
        XCTAssertTrue(euclideousNotesLayerIsOn(l), "the notes layer reads on (switch AND a selection)")
        XCTAssertFalse(euclideousMixLayerIsOff(l, notes: true), "lamp on")
    }

    // MARK: test 4 — §4.1 both parts off dims the strip (one part on → no dim); the dim is one 42 %
    func testBothPartsOffDimsTheStrip() {
        var l = EuclidLine(noteSel: .all)
        func bothOff(_ x: EuclidLine) -> Bool { euclideousMixLayerIsOff(x, notes: false) && euclideousMixLayerIsOff(x, notes: true) }
        var o = EuclideousLitOrder(); o.append(0); l.setLitOrder(o)
        l.riffOn = true; l.notesOn = true
        XCTAssertFalse(bothOff(l), "both on → no dim")
        l.notesOn = false
        XCTAssertFalse(bothOff(l), "riff on, notes off → no dim (§4.1 one part on)")
        l.riffOn = false
        XCTAssertTrue(bothOff(l), "both off → the strip greys")
        XCTAssertEqual(EuclideousLaneDimStyle.opacity, 0.42, accuracy: 0.001, "one 42 %, never stacked (the strip dim is soloDim OR partsOffDim)")
    }
}

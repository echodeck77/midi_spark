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
        XCTAssertEqual(off.playHex, 0x4E525A); XCTAssertEqual(off.nameHex, 0x5A5E66); XCTAssertFalse(off.lampFilled); XCTAssertFalse(off.lampUsesLane); XCTAssertEqual(off.lampStrokeHex, 0x4A4E57)
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
}

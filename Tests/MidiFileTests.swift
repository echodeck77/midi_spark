//  MidiFileTests.swift
//  THE REEL-TO-REEL export (step 2): the SMF encoder is pure Foundation → unit-tested. (Paul 2026-08-18)

import XCTest

final class MidiFileTests: XCTestCase {

    func testVarlenEncoding() {
        XCTAssertEqual(MidiFile.varlen(0), [0x00])
        XCTAssertEqual(MidiFile.varlen(127), [0x7F])
        XCTAssertEqual(MidiFile.varlen(128), [0x81, 0x00])
        XCTAssertEqual(MidiFile.varlen(8192), [0xC0, 0x00])
    }

    func testEncodeProducesAValidHeaderAndTrack() {
        let ev: [(beat: Double, b0: UInt8, b1: UInt8, b2: UInt8)] = [
            (0.0, 0x90, 60, 100),   // note on at beat 0
            (1.0, 0x80, 60, 0),     // note off at beat 1
        ]
        let data = MidiFile.encode(events: ev, bpm: 120, ppq: 480, loopBeats: 4.0)
        let bytes = [UInt8](data)
        XCTAssertEqual(Array(bytes[0..<4]), Array("MThd".utf8))
        XCTAssertEqual(Array(bytes[4..<8]), [0, 0, 0, 6])          // header length 6
        XCTAssertEqual(Array(bytes[8..<10]), [0, 0])              // format 0
        XCTAssertEqual(Array(bytes[10..<12]), [0, 1])            // 1 track
        XCTAssertEqual(Array(bytes[12..<14]), [0x01, 0xE0])      // division = 480 ppq
        XCTAssertEqual(Array(bytes[14..<18]), Array("MTrk".utf8))
        XCTAssertEqual(Array(bytes.suffix(3)), [0xFF, 0x2F, 0x00])   // end-of-track
        XCTAssertNotNil(data.range(of: Data([0x90, 60, 100])), "the note-ON is present")
        XCTAssertNotNil(data.range(of: Data([0x80, 60, 0])), "the note-OFF is present → no stuck note in the export")
    }

    func testEmptyEventsStillProduceAValidFile() {
        let data = MidiFile.encode(events: [], bpm: 120, ppq: 480, loopBeats: 4.0)
        let bytes = [UInt8](data)
        XCTAssertEqual(Array(bytes[0..<4]), Array("MThd".utf8))
        XCTAssertEqual(Array(bytes.suffix(3)), [0xFF, 0x2F, 0x00])
    }

    func testTempoMetaMatchesBPM() {
        let data = MidiFile.encode(events: [], bpm: 120, ppq: 480, loopBeats: 1.0)
        // 120 BPM → 500000 µs/quarter = 0x07A120
        XCTAssertNotNil(data.range(of: Data([0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20])))
    }

    // DECODE (config-sheets FILE mode, Paul 2026-08-20): parse SMF bytes into note events + loop length.

    func testEncodeDecodeRoundTrip() {
        // The strongest test: encode a known set → decode → the same notes, beat-accurate at the PPQ grid.
        let ev: [(beat: Double, b0: UInt8, b1: UInt8, b2: UInt8)] = [
            (0.0, 0x90, 60, 100),   // C on
            (0.5, 0x90, 64, 90),    // E on
            (1.0, 0x80, 60, 0),     // C off
            (2.0, 0x80, 64, 0),     // E off
        ]
        let data = MidiFile.encode(events: ev, bpm: 120, ppq: 480, loopBeats: 4.0)
        guard let (notes, loopBeats) = MidiFile.decode(data) else { return XCTFail("decode failed") }
        XCTAssertEqual(loopBeats, 4.0, accuracy: 0.001, "the end-of-track sets the loop length")
        XCTAssertEqual(notes.count, 4)
        XCTAssertEqual(notes[0], MidiFile.NoteEvent(beat: 0.0, note: 60, vel: 100, on: true))
        XCTAssertEqual(notes[1], MidiFile.NoteEvent(beat: 0.5, note: 64, vel: 90, on: true))
        XCTAssertEqual(notes.first { $0.note == 60 && !$0.on }?.beat ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(notes.first { $0.note == 64 && !$0.on }?.beat ?? -1, 2.0, accuracy: 0.001)
    }
    func testDecodeHandlesRunningStatusAndZeroVelOff() {
        // A hand-built track with RUNNING STATUS (0x90 then two note-ons without repeating status) + a vel-0 note-on = off.
        var trk: [UInt8] = []
        trk += [0x00, 0x90, 60, 100]   // C on
        trk += [0x00, 64, 90]          // running status → E on (no 0x90)
        trk += [0x60, 60, 0]           // running status, vel 0 → C off (delta 96 ticks)
        trk += [0x00, 0xFF, 0x2F, 0x00]
        var out: [UInt8] = []
        out += Array("MThd".utf8); out += [0,0,0,6, 0,0, 0,1, 0x00, 0x60]   // format 0, 1 track, ppq 96
        out += Array("MTrk".utf8); out += [0,0,0, UInt8(trk.count)]; out += trk
        guard let (notes, _) = MidiFile.decode(Data(out)) else { return XCTFail("decode failed") }
        XCTAssertEqual(notes.count, 3)
        XCTAssertTrue(notes.contains(MidiFile.NoteEvent(beat: 0, note: 64, vel: 90, on: true)), "running status parsed")
        XCTAssertTrue(notes.contains { $0.note == 60 && !$0.on && abs($0.beat - 1.0) < 0.001 }, "vel-0 note-on = off, at beat 1 (96/96)")
    }
    func testDecodeRejectsMalformedBytes() {
        XCTAssertNil(MidiFile.decode(Data([0x00, 0x01, 0x02])), "not an SMF → nil")
        XCTAssertNil(MidiFile.decode(Data()), "empty → nil")
        XCTAssertNil(MidiFile.decode(Data(Array("MThd".utf8) + [0,0,0,6, 0,0, 0,1])), "truncated header → nil")
    }
    func testFileClipDrivesTheDoorRing() {
        // The FILE→DoorRing bridge: decode → loadLoop → notesSoundingAt (the REPLAY playback path, reused).
        let ev: [(beat: Double, b0: UInt8, b1: UInt8, b2: UInt8)] = [
            (0.0, 0x90, 60, 100), (0.5, 0x90, 67, 100), (1.0, 0x80, 60, 0), (2.0, 0x80, 67, 0),
        ]
        guard let (notes, loopBeats) = MidiFile.decode(MidiFile.encode(events: ev, bpm: 120, ppq: 480, loopBeats: 4.0)) else { return XCTFail() }
        let ring = DoorRing()
        ring.loadLoop(notes.map { (beat: $0.beat, note: $0.note, vel: $0.vel, on: $0.on) }, lengthBeats: loopBeats)
        var n = [UInt8](repeating: 0, count: 16), v = [UInt8](repeating: 0, count: 16), ch = [UInt8](repeating: 0, count: 16)
        func sounding(_ p: Double) -> Set<UInt8> { let c = ring.notesSoundingAt(p, outNote: &n, outVel: &v, outChan: &ch); return Set((0..<c).map { n[$0] }) }
        XCTAssertEqual(sounding(0.25), [60], "only C at 0.25")
        XCTAssertEqual(sounding(0.75), [60, 67], "C + G at 0.75")
        XCTAssertEqual(sounding(1.5), [67], "C released → only G at 1.5")
    }

    func testLoadLoopParallelMatchesLoadLoopAndGuardsRaggedArrays() {
        // The render-thread-safe PARALLEL-array loader (called when a FILE clip changes) must produce the SAME loop as the
        // array-of-tuples loadLoop, and must CLAMP to the shortest array on a ragged input (no trap, no read past the end).
        // Events: C(60) held [0,1] vel 100 · G(67) held [0.5,1] vel 90 · loopLen 2.
        let beats: [Double] = [0.0, 0.5, 1.0, 1.0]
        let notes: [UInt8]  = [60, 67, 60, 67]
        let vels:  [UInt8]  = [100, 90, 0, 0]
        let ons:   [Bool]   = [true, true, false, false]
        let tuples: [(beat: Double, note: UInt8, vel: UInt8, on: Bool)] = [
            (0.0, 60, 100, true), (0.5, 67, 90, true), (1.0, 60, 0, false), (1.0, 67, 0, false),
        ]
        let a = DoorRing(); a.loadLoop(tuples, lengthBeats: 2.0)
        let b = DoorRing(); b.loadLoopParallel(beats: beats, notes: notes, vels: vels, ons: ons, lengthBeats: 2.0)
        // loopRoll order isn't guaranteed (a still-open note is flushed from a dictionary) → compare as a set of quantised tuples.
        func roll(_ r: DoorRing) -> Set<[Int]> { Set(r.loopRoll().map { [Int($0.note), Int($0.vel), Int(($0.start * 100).rounded()), Int(($0.end * 100).rounded())] }) }
        XCTAssertEqual(roll(a), roll(b), "the parallel load produces an IDENTICAL loop to the tuple load")
        XCTAssertEqual(roll(b), [[60, 100, 0, 100], [67, 90, 50, 100]], "C[0,1]@100 + G[.5,1]@90")

        // RAGGED: `notes` one element short → clamp to 3 events (drop the 4th), no trap. C-on · G-on · C-off only → G stays
        // open and is held to loopLen (2.0).
        let ragged = DoorRing()
        ragged.loadLoopParallel(beats: beats, notes: [60, 67, 60], vels: vels, ons: ons, lengthBeats: 2.0)
        let rr = ragged.loopRoll()
        XCTAssertEqual(rr.count, 2, "3 events → C paired + G held-open (no trap on the short array)")
        XCTAssertEqual(Set(rr.map { Int($0.note) }), [60, 67])
        XCTAssertEqual(rr.first { $0.note == 67 }?.end, 2.0, "G left open → held to loopLen")
    }
}

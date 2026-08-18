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
}

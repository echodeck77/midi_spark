//  MidiFile.swift
//  MidiSpark — a minimal Standard MIDI File (SMF) encoder for THE REEL-TO-REEL export (Paul 2026-08-18, step 2).
//  Foundation-only + pure → unit-tested. Takes the reel's pass-relative events (quarter-note beats) and writes a
//  format-0 SMF: one tempo meta + the events as full 3-byte channel messages (the stamp channel is already in b0).

import Foundation

enum MidiFile {
    /// MIDI variable-length quantity (big-endian, 7 bits/byte, high bit = continue).
    static func varlen(_ v: Int) -> [UInt8] {
        var value = UInt32(max(0, v))
        var buf: [UInt8] = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 { buf.insert(UInt8((value & 0x7F) | 0x80), at: 0); value >>= 7 }
        return buf
    }
    private static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    private static func be32(_ v: UInt32) -> [UInt8] { [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    /// A format-0 SMF from pass-relative events (beat = quarter notes). `bpm` sets the tempo meta; `ppq` = ticks/quarter;
    /// `loopBeats` = the loop length (the end-of-track lands there so the file is exactly one pass long).
    static func encode(events: [(beat: Double, b0: UInt8, b1: UInt8, b2: UInt8)], bpm: Double, ppq: Int, loopBeats: Double) -> Data {
        var track: [UInt8] = []
        // tempo meta at tick 0
        let us = UInt32(60_000_000.0 / max(1.0, bpm))
        track += varlen(0)
        track += [0xFF, 0x51, 0x03, UInt8((us >> 16) & 0xFF), UInt8((us >> 8) & 0xFF), UInt8(us & 0xFF)]
        // events sorted by tick (stable — recording order breaks ties, keeping off-before-on where they coincide)
        let sorted = events.enumerated().sorted { a, b in
            let ta = Int((a.element.beat * Double(ppq)).rounded()), tb = Int((b.element.beat * Double(ppq)).rounded())
            return ta != tb ? ta < tb : a.offset < b.offset
        }
        var last = 0
        for (_, e) in sorted {
            let t = max(0, Int((e.beat * Double(ppq)).rounded()))
            track += varlen(t - last); last = t
            track += [e.b0, e.b1, e.b2]
        }
        // end-of-track at the loop end (so the file is one pass long, offs already inside)
        let endT = max(last, Int((loopBeats * Double(ppq)).rounded()))
        track += varlen(endT - last)
        track += [0xFF, 0x2F, 0x00]
        // assemble: MThd (format 0, 1 track, ppq division) + MTrk
        var out: [UInt8] = []
        out += Array("MThd".utf8); out += be32(6); out += be16(0); out += be16(1); out += be16(UInt16(max(1, min(0x7FFF, ppq))))
        out += Array("MTrk".utf8); out += be32(UInt32(track.count)); out += track
        return Data(out)
    }
}

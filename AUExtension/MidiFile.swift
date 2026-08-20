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

    // MARK: - DECODE (config-sheets FILE mode, Paul 2026-08-20)

    /// One parsed note event: pass-relative beat (quarter notes), pitch, velocity, on/off.
    struct NoteEvent: Equatable { var beat: Double; var note: UInt8; var vel: UInt8; var on: Bool }

    /// Parse a Standard MIDI File (format 0 or 1) into note events + the clip length in beats. Handles multi-track
    /// merge (format 1 shares one timeline), running status, PPQ division. Skips CC/PB/AT/PC/meta/sysex (a FILE door
    /// plays NOTES; controllers are a later rider). Untrusted bytes → returns nil on ANYTHING malformed, never crashes.
    static func decode(_ data: Data) -> (notes: [NoteEvent], loopBeats: Double)? {
        let b = [UInt8](data)
        var p = 0
        func need(_ n: Int) -> Bool { p + n <= b.count }
        func u16() -> Int? { guard need(2) else { return nil }; let v = Int(b[p]) << 8 | Int(b[p+1]); p += 2; return v }
        func u32() -> Int? { guard need(4) else { return nil }; let v = Int(b[p]) << 24 | Int(b[p+1]) << 16 | Int(b[p+2]) << 8 | Int(b[p+3]); p += 4; return v }
        func tag() -> String? { guard need(4) else { return nil }; let s = String(bytes: b[p..<p+4], encoding: .ascii); p += 4; return s }

        guard tag() == "MThd", let hlen = u32(), hlen >= 6, need(hlen) else { return nil }
        let hEnd = p + hlen
        guard let _format = u16(), let ntracks = u16(), let division = u16() else { return nil }
        _ = _format
        guard division & 0x8000 == 0, (division & 0x7FFF) > 0 else { return nil }   // PPQ only (SMPTE division unsupported v1)
        let ppq = Double(division & 0x7FFF)
        p = hEnd   // skip any extra header bytes

        var notes: [NoteEvent] = []
        var maxTick = 0
        var tracks = 0
        while tracks < max(1, ntracks), p < b.count {
            guard tag() == "MTrk", let tlen = u32(), need(tlen) else { break }   // stop at the first non-track chunk
            let tEnd = p + tlen
            var tick = 0
            var status: UInt8 = 0
            trackLoop: while p < tEnd {
                // delta-time varlen
                var delta = 0, shifted = 0
                while p < tEnd {
                    let c = b[p]; p += 1
                    delta = (delta << 7) | Int(c & 0x7F)
                    shifted += 1
                    if c & 0x80 == 0 { break }
                    if shifted > 4 { return nil }   // malformed varlen
                }
                tick += delta
                guard p < tEnd else { break }
                var s = b[p]
                if s & 0x80 != 0 { status = s; p += 1 } else { s = status }   // running status
                let hi = s & 0xF0
                switch hi {
                case 0x90, 0x80:   // note on / off (2 data bytes)
                    guard p + 2 <= tEnd else { return nil }
                    let note = b[p], vel = b[p+1]; p += 2
                    let on = (hi == 0x90) && vel > 0
                    if note < 128 { notes.append(NoteEvent(beat: Double(tick) / ppq, note: note, vel: vel, on: on)) }
                case 0xA0, 0xB0, 0xE0:   // poly-AT / CC / pitch-bend (2 data) — skip
                    guard p + 2 <= tEnd else { return nil }; p += 2
                case 0xC0, 0xD0:   // program / channel-AT (1 data) — skip
                    guard p + 1 <= tEnd else { return nil }; p += 1
                case 0xF0:
                    if s == 0xFF {   // meta: type + varlen len + data
                        guard p + 1 <= tEnd else { return nil }
                        let metaType = b[p]; p += 1
                        var mlen = 0, ms = 0
                        while p < tEnd { let c = b[p]; p += 1; mlen = (mlen << 7) | Int(c & 0x7F); ms += 1; if c & 0x80 == 0 { break }; if ms > 4 { return nil } }
                        guard p + mlen <= tEnd else { return nil }
                        p += mlen
                        if metaType == 0x2F { maxTick = max(maxTick, tick); break trackLoop }   // end of track
                    } else if s == 0xF0 || s == 0xF7 {   // sysex: varlen len + data
                        var xlen = 0, xs = 0
                        while p < tEnd { let c = b[p]; p += 1; xlen = (xlen << 7) | Int(c & 0x7F); xs += 1; if c & 0x80 == 0 { break }; if xs > 4 { return nil } }
                        guard p + xlen <= tEnd else { return nil }; p += xlen
                    } else { return nil }   // unexpected system message in a track
                default:
                    return nil   // never a valid running-status start
                }
            }
            maxTick = max(maxTick, tick)
            p = tEnd
            tracks += 1
        }
        guard !notes.isEmpty else { return nil }
        notes.sort { $0.beat != $1.beat ? $0.beat < $1.beat : (!$0.on && $1.on) }   // time order; off-before-on at a tie
        let loopBeats = Double(maxTick) / ppq
        return (notes, loopBeats > 0 ? loopBeats : (notes.last?.beat ?? 0) + 1)
    }
}

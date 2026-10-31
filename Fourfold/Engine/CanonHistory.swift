//  CanonHistory.swift — CHORD CANON, all sources (2026-10-31): the short history of the pool's LIVE layers that lets a delayed lane hear what the player did `d` beats ago.
//  Foundation only, on purpose (the macOS test target compiles this file directly).
//
//  CHORDS is a closed form of the host beat, so a delayed lane simply asks it for `m − d` and needs no history. The other three layers are not: MIDI IN is whatever the player holds, PICK is the tapped-in notes and
//  KEY is the page's key pill — all three are only known as they happen. This ring remembers them. One entry is the state of all three at the start of a window in which any of them CHANGED (an identical window records
//  nothing, so a held chord costs one entry, not one a window), keyed by the ELAPSED beat clock (beats since the transport started — it keeps counting through a host loop or seek, so a loop is a canon across its own seam).
//
//  The ring is fixed-size and allocates nothing after `init`: 1024 entries, each up to 32 MIDI notes (note + velocity), 16 PICK notes, the key as a root and a 12-bit scale mask, and the MIDI-PLAYING flag the
//  stack's ADD / REPLACE rule reads. It is the ONE piece of canon state — a sanctioned exception to "derived, never accumulated" like the note tracker — and it is reset at a transport edge, a reset and a scene
//  flush (a preset or session load), never by an edit. A read older than the ring's oldest entry gets the oldest entry (the sound is held, never silent); a lane delayed by more than the ring remembers
//  (1024 changes ago — minutes of playing) hears the oldest it has.

import Foundation

struct EuclideousCanonHistory {
    static let capacity = 1024
    static let midiCap = 32
    static let pickCap = 16

    /// Entries held (≤ capacity) and the sequence number the NEXT entry gets (entries ever recorded since the last reset). Sequence numbers are stable names for an entry — the SLIP roll is keyed by one.
    private(set) var count = 0
    private(set) var nextSeq: Int64 = 0
    private var beat = [Double](repeating: 0, count: capacity)
    private var midiN = [UInt8](repeating: 0, count: capacity)
    private var midi = [UInt8](repeating: 0, count: capacity * midiCap * 2)      // note, velocity, note, velocity …
    private var playing = [Bool](repeating: false, count: capacity)
    private var pickN = [UInt8](repeating: 0, count: capacity)
    private var pick = [UInt8](repeating: 0, count: capacity * pickCap)
    private var keyRoot = [UInt8](repeating: 0, count: capacity)
    private var keyMask = [UInt16](repeating: 0, count: capacity)

    var oldestSeq: Int64 { nextSeq - Int64(count) }
    var isEmpty: Bool { count == 0 }
    private func slot(_ seq: Int64) -> Int { Int(seq % Int64(Self.capacity)) }

    mutating func reset() { count = 0; nextSeq = 0 }

    /// Records the layers as they are at elapsed beat `at`, unless they are exactly what the newest entry holds. `midi` is ascending (the pool layer's own order); only its first 32 notes are kept.
    mutating func record(at e: Double, midi m: ArraySlice<(note: Int, vel: UInt8)>, midiPlaying: Bool, pick p: ArraySlice<Int>, keyRoot root: Int, keyMask mask: UInt16) {
        let mn = min(Self.midiCap, m.count), pn = min(Self.pickCap, p.count)
        let r = UInt8(truncatingIfNeeded: ((root % 12) + 12) % 12)
        if count > 0 {
            let s = slot(nextSeq - 1)
            var same = Int(midiN[s]) == mn && Int(pickN[s]) == pn && playing[s] == midiPlaying && keyRoot[s] == r && keyMask[s] == mask
            if same { for i in 0..<mn where Int(midi[(s * Self.midiCap + i) * 2]) != m[m.startIndex + i].note || midi[(s * Self.midiCap + i) * 2 + 1] != m[m.startIndex + i].vel { same = false; break } }
            if same { for i in 0..<pn where Int(pick[s * Self.pickCap + i]) != p[p.startIndex + i] { same = false; break } }
            if same { return }
        }
        let s = slot(nextSeq)
        beat[s] = e; playing[s] = midiPlaying; keyRoot[s] = r; keyMask[s] = mask
        midiN[s] = UInt8(mn); pickN[s] = UInt8(pn)
        for i in 0..<mn { midi[(s * Self.midiCap + i) * 2] = UInt8(truncatingIfNeeded: max(0, min(127, m[m.startIndex + i].note))); midi[(s * Self.midiCap + i) * 2 + 1] = m[m.startIndex + i].vel }
        for i in 0..<pn { pick[s * Self.pickCap + i] = UInt8(truncatingIfNeeded: max(0, min(127, p[p.startIndex + i]))) }
        nextSeq += 1
        count = min(Self.capacity, count + 1)
    }

    /// The newest entry at or before elapsed beat `t` (a hair of float slack); the OLDEST entry when `t` is older than everything held; nil while the ring is empty.
    func seq(atOrBefore t: Double) -> Int64? {
        guard count > 0 else { return nil }
        var lo = oldestSeq, hi = nextSeq - 1
        if beat[slot(lo)] > t + 1e-9 { return lo }
        while lo < hi {                                   // the newest entry whose beat ≤ t
            let mid = lo + (hi - lo + 1) / 2
            if beat[slot(mid)] <= t + 1e-9 { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
    func beatOf(_ seq: Int64) -> Double { beat[slot(seq)] }
    func midiPlaying(_ seq: Int64) -> Bool { playing[slot(seq)] }

    /// The MIDI layer of an entry written into `out` (the pool layer's own `(note, vel)` shape); returns the count.
    func fillMidi(_ seq: Int64, into out: inout [(note: Int, vel: UInt8)]) -> Int {
        let s = slot(seq), n = min(Int(midiN[s]), out.count)
        for i in 0..<n { out[i] = (Int(midi[(s * Self.midiCap + i) * 2]), midi[(s * Self.midiCap + i) * 2 + 1]) }
        return n
    }
    func fillPick(_ seq: Int64, into out: inout [Int]) -> Int {
        let s = slot(seq), n = min(Int(pickN[s]), out.count)
        for i in 0..<n { out[i] = Int(pick[s * Self.pickCap + i]) }
        return n
    }
    func key(_ seq: Int64) -> (root: Int, mask: UInt16) { let s = slot(seq); return (Int(keyRoot[s]), keyMask[s]) }
}

/// The scale as a 12-bit mask of its intervals (bit i = interval i), the form the history keeps the key in. Every scale's intervals are ascending and under 12, so the mask loses nothing.
func euclideousCanonKeyMask(tones: [Int]) -> UInt16 {
    var m: UInt16 = 0
    for iv in tones where iv >= 0 && iv < 12 { m |= UInt16(1) << UInt16(iv) }
    return m
}
/// The KEY layer from a root and a scale mask: the scale tones in ONE base octave (C3 = 48 + root), ascending — exactly the notes the Router's live `fillKeyLayer` builds from the same key.
func euclideousCanonKeyNotes(root: Int, mask: UInt16, into out: inout [Int]) -> Int {
    let r = ((root % 12) + 12) % 12, base = 3 * 12 + 12
    var n = 0
    for iv in 0..<12 where (mask >> UInt16(iv)) & 1 != 0 && n < out.count {
        let note = base + r + iv
        if note >= 0 && note <= 127 { out[n] = note; n += 1 }
    }
    return n
}

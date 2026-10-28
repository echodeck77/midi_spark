//  ReelTapeAdapter.swift — REEL PHASE 1c (Docs/reel-redesign-plan.md): the old pass browser's view of the session tape, so the app ships between phases.
//  The browser still speaks in "passes" — numbered 0, 1, 2 … (shown 1-based) in the order they were played whole — but they now come from the tape, so it lists the WHOLE session, not the newest 64, and a pass
//  played while the browser was open is not missing. A pass here is a `SessionTape.filed` pass: one that ran its full length with no stop or jump inside (a run that starts mid-pass does not file its first, partial pass).
//  Everything is MAIN THREAD and read-only on the tape; replaying a pass hands its events to the render thread through `ReelDeck.stageLoop`. Foundation-only, so the unit tests reach it.

import Foundation

extension SessionTape {
    /// The events of filed pass `i` as the deck would have held them: pass-relative beats, every cable (0 = ALL too), notes and control changes, in time order. Empty if there is no such pass.
    func reelPassEvents(_ i: Int) -> [ReelDeck.Ev] {
        let f = filedPasses()
        guard i >= 0, i < f.count, let end = f[i].endTick else { return [] }
        let start = f[i].startTick
        return events(from: start, to: end, kinds: [.note, .control]).map { e in
            let w = e.wire
            return ReelDeck.Ev(beat: Double(Int(e.tick) - start) / Double(SessionTape.ppq), cable: UInt8(e.cable), b0: w.status, b1: w.d1, b2: w.d2, machine: 0)
        }
    }
    /// The length of filed pass `i` in beats (nil if there is no such pass).
    func reelPassCycleBeats(_ i: Int) -> Double? {
        let f = filedPasses()
        return i >= 0 && i < f.count ? Double(f[i].cycleTicks) / Double(SessionTape.ppq) : nil
    }

    /// The REMOVE DUPLICATES hash of every filed pass, oldest first, aligned with the pass list. Two passes with the same note-ons (rounded timing, cable, pitch, velocity) hash equal. Computed once per pass.
    func reelSignatures() -> [UInt64] {
        let n = filedPasses().count
        while reelSignatureCache.count < n { reelSignatureCache.append(SessionTape.reelSignature(of: reelPassEvents(reelSignatureCache.count))) }
        return Array(reelSignatureCache.prefix(n))
    }
    static func reelSignature(of evs: [ReelDeck.Ev]) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325                       // FNV-1a, the same recipe as `ReelDeck.passSignatures`
        for e in evs {
            guard (e.b0 & 0xF0) == 0x90, e.b2 > 0 else { continue }
            let bq = UInt64(bitPattern: Int64((e.beat * 480.0).rounded()))
            h = (h ^ bq) &* 0x100_0000_01b3
            h = (h ^ (UInt64(e.cable) << 16 | UInt64(e.b1) << 8 | UInt64(e.b2))) &* 0x100_0000_01b3
        }
        return h
    }

    /// The drawable notes of filed passes `lo…hi` laid end to end (a note held across a boundary reunites), outputs A–D only, plus the total length in beats — the tape's `ReelDeck.rangeRoll`.
    func reelRangeRoll(from lo: Int, to hi: Int) -> (notes: [ReelDeck.Note], totalBeats: Double) {
        var out: [ReelDeck.Note] = []
        var open: [Int: (start: Double, vel: UInt8)] = [:]
        var offset = 0.0
        var p = min(lo, hi); let end = max(lo, hi)
        while p <= end {
            if let cycle = reelPassCycleBeats(p) {
                for e in reelPassEvents(p) where e.cable >= 1 && e.cable <= FourfoldPorts.outputCount {
                    let key = Int(e.cable) << 8 | Int(e.b1)
                    let isOn = (e.b0 & 0xF0) == 0x90 && e.b2 > 0
                    let isOff = (e.b0 & 0xF0) == 0x80 || ((e.b0 & 0xF0) == 0x90 && e.b2 == 0)
                    if isOn { open[key] = (offset + e.beat, e.b2) }
                    else if isOff, let o = open.removeValue(forKey: key) {
                        out.append(ReelDeck.Note(cable: e.cable, note: e.b1, vel: o.vel, start: o.start, end: max(o.start, offset + e.beat), machine: 0))
                    }
                }
                offset += cycle
            }
            p += 1
        }
        for (key, o) in open { out.append(ReelDeck.Note(cable: UInt8(key >> 8), note: UInt8(key & 0xFF), vel: o.vel, start: o.start, end: max(o.start, offset), machine: 0)) }
        return (out, offset)
    }

    /// The events of filed passes `lo…hi` laid end to end, on `cables`, for a MIDI file — the tape's `ReelDeck.exportRangeEvents`.
    func reelExportEvents(from lo: Int, to hi: Int, cables: Set<UInt8>) -> (events: [(beat: Double, b0: UInt8, b1: UInt8, b2: UInt8)], totalBeats: Double) {
        var out: [(beat: Double, b0: UInt8, b1: UInt8, b2: UInt8)] = []
        var offset = 0.0
        var p = min(lo, hi); let end = max(lo, hi)
        while p <= end {
            if let cycle = reelPassCycleBeats(p) {
                for e in reelPassEvents(p) where cables.contains(e.cable) { out.append((offset + e.beat, e.b0, e.b1, e.b2)) }
                offset += cycle
            }
            p += 1
        }
        return (out, offset)
    }

    /// The MIDI files for passes `lo…hi`: `emitterMask` 0 = the A–D sum as one file, else one per selected output (A = bit 0 … D = bit 3). The tempo header is the tempo the first pass was PLAYED at (REEL-12), not the current one.
    func reelExportFiles(from lo: Int, to hi: Int, emitterMask: UInt8) -> [(name: String, data: Data)] {
        let f = filedPasses()
        guard !f.isEmpty else { return [] }
        let first = max(0, min(min(lo, hi), f.count - 1))
        let bpm = self.bpm(at: f[first].startTick)
        var files: [(name: String, data: Data)] = []
        if emitterMask == 0 {
            let (evs, total) = reelExportEvents(from: lo, to: hi, cables: Set((1...FourfoldPorts.outputCount).map { UInt8($0) }))
            if !evs.isEmpty { files.append((name: "Fourfold-All.mid", data: MidiFile.encode(events: evs, bpm: bpm, ppq: 480, loopBeats: total))) }
        } else {
            for i in 0..<FourfoldPorts.outputCount where (emitterMask & (1 << UInt8(i))) != 0 {
                let (evs, total) = reelExportEvents(from: lo, to: hi, cables: [UInt8(i + 1)])
                let label = FourfoldPorts.shortName(cable: i + 1).capitalized
                if !evs.isEmpty { files.append((name: "Fourfold-\(label).mid", data: MidiFile.encode(events: evs, bpm: bpm, ppq: 480, loopBeats: total))) }
            }
        }
        return files
    }
}

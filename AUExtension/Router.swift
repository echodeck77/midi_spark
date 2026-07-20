//  Router.swift
//  MidiSpark — the routing/derivation engine (spec v2.8 §2/§7; docs/router-design.md).
//
//  Split out of Kernel at build-order step 3, commit 4. The Kernel owns the INPUT side
//  (transport derivation, incoming MIDI, the source pool) and the render entry point; the
//  Router owns the OUTPUT side — grid columns, per-cell ARP derivation, the note tracker, and
//  emission. Behaviour is identical to the in-Kernel version this replaced (verified: T1).
//
//  Still single-cell / mono (one arp voice). Chains, fan-out, and the (bus, channel, note)
//  collision refcount arrive at commits 5–6; the seams are marked.

import Foundation
import AudioToolbox
import AVFoundation

// NotePool and the pure derivation functions (musicalOf/realOf, phaseIndex, arpPickSource,
// cellMode/CellMode, ratchetVelocity) now live in Derivations.swift — pure, Foundation-only, and
// unit-tested. The Router keeps only what depends on its state or CoreAudio.

// MARK: - The router / arp engine

final class Router {

    // Render-side parameter overrides (§7 second route). Slots:
    //   0 stepRate · 1 swing · 2+i transpose(i) · 18+i morph(i) · 34 morphMaster
    private var overrides = [Double](repeating: .nan, count: 35)
    private var overrideGen: UInt64 = .max

    // Poly note tracker (§7). Each sounding note is a Voice carrying the channel + cable its on used
    // and an ABSOLUTE gate-off sample, drained every render so an off beyond its opening window is
    // never dropped (no stuck note). Fixed capacity; no allocation on the hot path.
    private struct Voice {
        var active = false
        var note: UInt8 = 0
        var chan: UInt8 = 0
        var cable: UInt8 = 0
        var offSample: AUEventSampleTime = .max
    }
    private var voices = [Voice](repeating: Voice(), count: 128)

    // Collision refcount (§7, normative): per (bus, channel, note). Note-ONs always emit
    // (re-articulation is audible truth); the wire note-OFF is emitted only when the LAST instance
    // releases — so a sustained note never drops under a same-pitch arp. 4 buses × 16 ch × 128 notes.
    private var refcount = [UInt8](repeating: 0, count: 4 * 16 * 128)
    private var distinctSounding = 0   // number of (bus,ch,note) with refcount > 0 (diag; kept incrementally)

    private var wasPlaying = false
    private var prevEffColumn = -1   // column-transition edge (§7): change ⇒ truncate voices

    @inline(__always)
    private func rcIndex(_ cable: UInt8, _ chan: UInt8, _ note: UInt8) -> Int {
        (Int(cable & 3) * 16 + Int(chan & 15)) * 128 + Int(note & 127)
    }

    // Per-row chain scratch (§2/§1.1). Each row's TICK articulations this window, so a fed cell can
    // read its feeder's output (mirror model). Fixed capacity, no hot-path allocation. lastTick
    // dedups each row's arp independently across (rare) overlapping windows.
    private struct Artic {
        var onSample: AUEventSampleTime = 0
        var offSample: AUEventSampleTime = 0
        var note: UInt8 = 0    // after this row's accumulated transpose
        var chan: UInt8 = 0    // provenance channel (for INHERIT); OUT CH is applied only at emission
        var beat: Double = 0   // musical onset beat — the stable seed for CHANCE (loop-consistent)
    }
    private static let articCap = 24
    private var articBuf = [Artic](repeating: Artic(), count: Snap.rows * Router.articCap)
    private var articCount = [Int](repeating: 0, count: Snap.rows)
    private var lastTick = [Int64](repeating: -1, count: Snap.rows)
    private var strumProgress = [Int](repeating: 0, count: Snap.rows)   // strum notes emitted this column, per row

    func reset() {
        for i in voices.indices { voices[i].active = false; voices[i].offSample = .max }
        for i in refcount.indices { refcount[i] = 0 }
        distinctSounding = 0
        wasPlaying = false
        for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
        prevEffColumn = -1
        for i in overrides.indices { overrides[i] = .nan }
        overrideGen = .max
    }

    // MARK: parameter overrides

    @inline(__always)
    private func slot(for address: AUParameterAddress) -> Int? {
        switch address {
        case 0: return 0
        case 1: return 1
        case 100..<116: return 2 + Int(address - 100)
        case 200..<216: return 18 + Int(address - 200)
        case 300: return 34
        default: return nil
        }
    }

    @inline(__always)
    private func over(_ slotIndex: Int, _ fallback: Double) -> Double {
        let v = overrides[slotIndex]
        return v.isNaN ? fallback : v
    }

    /// A real document edit publishes a fresh snapshot generation → it is the new truth, so drop
    /// the render-side overrides and let the two param routes agree again (§7). Call once per render,
    /// BEFORE applying this render's parameter events.
    func refreshOverrides(forGeneration generation: UInt64) {
        if generation != overrideGen {
            for i in overrides.indices { overrides[i] = .nan }
            overrideGen = generation
        }
    }

    /// Apply one render-side .parameter/.parameterRamp event.
    func applyParamEvent(_ address: AUParameterAddress, _ value: Double, diag: inout KernelDiag) {
        guard let idx = slot(for: address) else { return }
        overrides[idx] = value
        diag.paramEventCount &+= 1
        diag.lastParamAddr = Int64(address)
        diag.lastParamValue = value
    }

    // Topmost occupied, non-muted cell in a grid column — the single active cell (no chains until
    // commit 5). cells index = column*8 + row (Snapshot.swift). Muted cells produce nothing (§6.2).
    @inline(__always)
    private func topCell(in column: Int, _ box: SnapshotBox) -> (row: Int, cell: SnapCell)? {
        let c = ((column % Snap.cols) + Snap.cols) % Snap.cols
        for row in 0..<Snap.rows {
            let cell = box.cells[c * Snap.rows + row]
            if cell.colourIndex >= 0 && !cell.muted { return (row, cell) }
        }
        return nil
    }

    // MARK: voice table

    /// Emit a note-on and register a voice with its scheduled gate-off. Returns the slot, or -1 if
    /// the table is full (the on still sounded; we just can't track its off — capacity is 128).
    @discardableResult
    private func openVoice(note: UInt8, chan: UInt8, cable: UInt8,
                           onSample: AUEventSampleTime, offSample: AUEventSampleTime,
                           velocity: UInt8 = 96, out: AUMIDIOutputEventBlock?) -> Int {
        guard let out else { return -1 }
        // Claim a slot BEFORE emitting: a note we can't track is worse than a dropped one (it would
        // hang). At 128-voice capacity this never trips for the real topologies.
        var slot = -1
        for i in voices.indices where !voices[i].active { slot = i; break }
        guard slot >= 0 else { return -1 }

        var on: [UInt8] = [0x90 | chan, note, max(1, velocity)]
        _ = out(onSample, cable, 3, &on)                     // §7 clause 1: note-ons ALWAYS emit
        let idx = rcIndex(cable, chan, note)
        if refcount[idx] == 0 { distinctSounding += 1 }
        refcount[idx] += 1

        voices[slot].active = true
        voices[slot].note = note
        voices[slot].chan = chan
        voices[slot].cable = cable
        voices[slot].offSample = offSample
        return slot
    }

    private func closeVoice(_ i: Int, atSample time: AUEventSampleTime, out: AUMIDIOutputEventBlock?) {
        guard voices[i].active else { return }
        let cable = voices[i].cable, chan = voices[i].chan, note = voices[i].note
        voices[i].active = false
        voices[i].offSample = .max

        let idx = rcIndex(cable, chan, note)
        if refcount[idx] > 0 { refcount[idx] -= 1 }
        if refcount[idx] == 0 {
            distinctSounding = max(0, distinctSounding - 1)
            // §7 clause 2: the wire note-off fires ONLY when the last instance releases. Clause 3:
            // no restoration strike — a surviving instance is simply never re-struck.
            if let out {
                var off: [UInt8] = [0x80 | chan, note, 0]
                _ = out(time, cable, 3, &off)
            }
        }
    }

    /// Emit any scheduled gate-off that has come due this window (drained every render → no stuck
    /// note when a voice's off falls beyond the window it was opened in).
    private func drainDue(windowStart: AUEventSampleTime, windowEnd: AUEventSampleTime,
                          out: AUMIDIOutputEventBlock?) {
        for i in voices.indices where voices[i].active && voices[i].offSample <= windowEnd {
            closeVoice(i, atSample: max(voices[i].offSample, windowStart), out: out)
        }
    }

    /// Close every sounding voice at one sample time (transport edge, column transition, reset).
    func allNotesOff(atSample time: AUEventSampleTime, out: AUMIDIOutputEventBlock?) {
        for i in voices.indices where voices[i].active { closeVoice(i, atSample: time, out: out) }
    }

    private func anyVoiceActive() -> Bool {
        for v in voices where v.active { return true }
        return false
    }

    private func activeVoiceCount() -> Int {
        var n = 0
        for v in voices where v.active { n += 1 }
        return n
    }

    // MARK: - chain helpers (§2.1)

    /// A cell is FED iff the cell directly above is occupied, has ▾ stack on, and is not muted
    /// (a muted feeder reroutes the follower to source, §2.1/§6.2).
    @inline(__always)
    private func isFed(_ box: SnapshotBox, _ column: Int, _ row: Int) -> Bool {
        guard row > 0 else { return false }
        let above = box.cells[column * Snap.rows + (row - 1)]
        return above.colourIndex >= 0 && above.stack && !above.muted
    }

    @inline(__always)
    private func sampleOf(musical: Double, beatPos: Double, beatsPerSample: Double,
                          windowStart: AUEventSampleTime, S: Double, a: Double) -> AUEventSampleTime {
        let real = realOf(musical, stepBeats: S, a: a)
        return windowStart + AUEventSampleTime(max(0, (real - beatPos) / beatsPerSample))
    }

    private func storeArtic(row: Int, on: AUEventSampleTime, off: AUEventSampleTime,
                            note: UInt8, chan: UInt8, beat: Double) {
        let c = articCount[row]
        guard c < Router.articCap else { return }
        let i = row * Router.articCap + c
        articBuf[i].onSample = on; articBuf[i].offSample = off
        articBuf[i].note = note; articBuf[i].chan = chan; articBuf[i].beat = beat
        articCount[row] = c + 1
    }

    /// Stamp OUT CH (§2.6) and FAN OUT one articulation to every lit bus (§2.3: a cell emits on each
    /// enabled letter simultaneously, duplicate events per bus). Each bus is an independent voice
    /// under the refcount. In-window offs close in-loop so wire events stay in ascending sample order.
    private func emitArtic(note: UInt8, provenanceChan: UInt8, outChannel: UInt8, busMask: UInt8,
                           onSample: AUEventSampleTime, offSample: AUEventSampleTime,
                           windowEnd: AUEventSampleTime, velocity: UInt8 = 96,
                           out: AUMIDIOutputEventBlock?, diag: inout KernelDiag) {
        let outCh: UInt8 = outChannel == 0 ? provenanceChan : outChannel - 1
        var mask = busMask
        while mask != 0 {
            let cable = UInt8(mask.trailingZeroBitCount)
            mask &= mask - 1                                  // clear the lowest set bit
            let slot = openVoice(note: note, chan: outCh, cable: cable,
                                 onSample: onSample, offSample: offSample, velocity: velocity, out: out)
            if slot >= 0 && offSample <= windowEnd { closeVoice(slot, atSample: offSample, out: out) }
        }
        diag.emitCount &+= 1
        diag.lastEmitNote = note
        diag.lastEmitChan = outCh
        diag.lastEmitInherit = (outChannel == 0)
    }

    /// HOLD content, emitted ONCE per column at the transition: an identity cell that is unfed (or
    /// +SRC) articulates the whole source chord and holds it to the column boundary (mirror model:
    /// identity = sample-and-hold of its input pool). Arp cells and pure-mirror cells have no hold.
    private func emitColumnHolds(box: SnapshotBox, column: Int, pool: NotePool, pass: Int,
                                 S: Double, a: Double, mNow: Double, beatPos: Double,
                                 beatsPerSample: Double, windowStart: AUEventSampleTime,
                                 windowEnd: AUEventSampleTime, out: AUMIDIOutputEventBlock?,
                                 diag: inout KernelDiag) {
        guard pool.count > 0 else { return }
        let colStart = (mNow / S).rounded(.down) * S
        let onSample = sampleOf(musical: colStart, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                windowStart: windowStart, S: S, a: a)
        let offSample = sampleOf(musical: colStart + S, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                 windowStart: windowStart, S: S, a: a)
        for r in 0..<Snap.rows {
            let cell = box.cells[column * Snap.rows + r]
            if cell.colourIndex < 0 || cell.muted || cell.busMask == 0 { continue }
            let ci = Int(cell.colourIndex)
            let colour = box.colours[ci]
            // Cells that chord-hold: identity (incl. open passgate) and CHANCE. CHANCE additionally
            // drops each chord note by its deterministic probability. Arp/ratchet/strum and a closed
            // passgate do not chord-hold.
            let mode = cellMode(type: colour.a.type, bypassed: cell.bypassed,
                                passMask: colour.a.passMask, pass: pass)
            guard mode == .identity || mode == .chance else { continue }
            let fed = isFed(box, column, r)
            guard !fed || cell.srcMix else { continue }   // holds source only when unfed or +SRC
            let transpose = Int(over(2 + ci, Double(colour.transpose)).rounded())
            let prob = (mode == .chance) ? effectiveProbability(colour, t: effectiveT(colourMorph: over(18 + ci, colour.morph),
                                                                                      master: over(34, box.morphMaster),
                                                                                      alt: cell.alt)) : 1
            for k in 0..<pool.count {
                let base = Int(pool.sorted[k])
                let n = base + transpose
                guard n >= 0 && n <= 127 else { continue }
                if mode == .chance && !chancePasses(beat: colStart, note: n, probability: prob) { continue }
                emitArtic(note: UInt8(n), provenanceChan: pool.channel(of: base),
                          outChannel: colour.outChannel, busMask: cell.busMask,
                          onSample: onSample, offSample: offSample, windowEnd: windowEnd,
                          out: out, diag: &diag)
            }
        }
    }

    /// One sounding note (+ provenance channel) of the cell at (column, row) at musical beat `m`,
    /// computed by DERIVATION — valid at ANY instant, independent of render-window boundaries. This
    /// is what lets a fed ARP sample its feeder's CURRENT note even when that note was struck in an
    /// earlier window (the per-window artic scratch cannot). Recurses up a chain of arps/mirrors.
    ///  · ARP feeder    → its arp note at m (over its own feeder or source).
    ///  · identity fed  → mirrors the note above (+ this transpose).
    ///  · identity unfed → the source chord is a POOL, not a single note; no fixture feeds an ARP
    ///    from one yet, so this returns nil (documented limitation, not a silent wrong answer).
    private func feederSoundingNote(row: Int, column: Int, m: Double, box: SnapshotBox,
                                    pool: NotePool, S: Double, cycleBeats: Double) -> (note: Int, chan: UInt8)? {
        guard row >= 0 else { return nil }
        let cell = box.cells[column * Snap.rows + row]
        guard cell.colourIndex >= 0, !cell.muted else { return nil }
        let ci = Int(cell.colourIndex)
        let colour = box.colours[ci]
        let transpose = Int(over(2 + ci, Double(colour.transpose)).rounded())
        let fed = isFed(box, column, row)
        let pass = Int((m / cycleBeats).rounded(.down))
        let mode = cellMode(type: colour.a.type, bypassed: cell.bypassed, passMask: colour.a.passMask, pass: pass)
        if mode == .silent { return nil }      // e.g. a closed passgate feeder sounds nothing
        if mode == .ratchet { return nil }     // ratchet sounds a chord (pool), not one note — see doc comment

        if mode == .arp {
            let master = over(34, box.morphMaster)
            let morph = over(18 + ci, colour.morph)
            let t = effectiveT(colourMorph: morph, master: master, alt: cell.alt)
            var arpBeats = effectiveRateBeats(colour, t: t)
            if arpBeats <= 0 { arpBeats = 0.25 }
            let octaves = effectiveOctaves(colour, t: t)
            let tick = Int64((m / arpBeats).rounded(.down))
            let pIdx = phaseIndex(tick: tick, mTickBeat: Double(tick) * arpBeats, arpBeats: arpBeats,
                                  S: S, cycleBeats: cycleBeats, phase: colour.a.phase,
                                  runStartColumn: cell.runStartColumn)
            if fed && !cell.srcMix {
                guard let up = feederSoundingNote(row: row - 1, column: column, m: m,
                                                  box: box, pool: pool, S: S, cycleBeats: cycleBeats)
                else { return nil }
                let oct = Int64(max(1, octaves))
                return (up.note + 12 * Int(((pIdx % oct) + oct) % oct) + transpose, up.chan)
            }
            let p = arpPickSource(phaseIndex: pIdx, octaves: octaves,
                                  pattern: colour.a.patternIndex, pool: pool)   // unfed / +SRC → source
            return p.base >= 0 ? (p.base + transpose, p.chan) : nil
        }
        if fed {
            guard let up = feederSoundingNote(row: row - 1, column: column, m: m,
                                              box: box, pool: pool, S: S, cycleBeats: cycleBeats)
            else { return nil }
            return (up.note + transpose, up.chan)          // identity mirror
        }
        return nil   // unfed identity: a chord (pool), not one note — see doc comment
    }

    /// The shared subdivision-tick scaffold for ARP and RATCHET. Walks every tick of length `sub`
    /// in this window that belongs to `effColumn`, dedups per row, and hands the body the tick's
    /// index, musical beat, and unwarped on/off sample times. `gateFraction` sets the note length
    /// as a fraction of `sub` (truncated at the column boundary). The body decides WHAT to emit;
    /// this owns the timing — so the boundary/dedup logic lives in exactly one place.
    /// Return from the body to skip a tick (the equivalent of `continue`).
    private func iterateTicks(row: Int, effColumn: Int, sub: Double, gateFraction: Double,
                              beatPos: Double, windowBeats: Double, windowStart: AUEventSampleTime,
                              beatsPerSample: Double, S: Double, a: Double,
                              _ body: (_ tick: Int64, _ mTickBeat: Double,
                                       _ onTime: AUEventSampleTime, _ offTime: AUEventSampleTime) -> Void) {
        let mStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        // floor, not ceil: a tick AT a column boundary sits between render windows — the previous
        // column's window rejects it (wrong column) and ceil would round past it, dropping the
        // column's first note. floor + the == dedup catches it once (fired slightly late, clamped).
        let firstTick = Int64((mStart / sub).rounded(.down))
        let lastT = Int64((mEnd / sub).rounded(.down))
        guard firstTick <= lastT else { return }

        for tick in firstTick...lastT {
            let mTickBeat = Double(tick) * sub
            let tickCol = ((Int((mTickBeat / S).rounded(.down)) % Snap.cols) + Snap.cols) % Snap.cols
            if tickCol != effColumn { continue }         // handled in that column's own window
            if tick == lastTick[row] { continue }
            lastTick[row] = tick

            let onTime = sampleOf(musical: mTickBeat, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                  windowStart: windowStart, S: S, a: a)
            let colEnd = (mTickBeat / S).rounded(.down) * S + S
            let mOff = min(mTickBeat + sub * gateFraction, colEnd)
            let offTime = sampleOf(musical: mOff, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                   windowStart: windowStart, S: S, a: a)
            body(tick, mTickBeat, onTime, offTime)
        }
    }

    // MARK: - the render-side pass

    func process(box: SnapshotBox,
                 pool: NotePool,
                 playing: Bool,
                 beatPos: Double,
                 tempo: Double,
                 sampleRate: Double,
                 timestampSample: Double,
                 frameCount: AUAudioFrameCount,
                 out: AUMIDIOutputEventBlock?,
                 diag: inout KernelDiag) {

        // ---- window in samples; global (non-cell) timing ----
        let windowStart = AUEventSampleTime(timestampSample)
        let windowEnd = windowStart + AUEventSampleTime(frameCount)
        let beatsPerSample = tempo / 60.0 / sampleRate
        let swing = min(75, max(50, over(1, box.swing)))
        let a = swing / 50.0
        var S = box.stepBeats
        let srIdx = Int(over(0, -1).rounded())
        if srIdx >= 0 && srIdx < Snap.stepRateBeats.count { S = Snap.stepRateBeats[srIdx] }
        diag.effSwing = swing

        // ---- drain scheduled gate-offs that have come due (survive across renders → no stuck note
        //      when a voice's off falls beyond its opening window). Runs regardless of transport. ----
        drainDue(windowStart: windowStart, windowEnd: windowEnd, out: out)
        diag.activeVoiceCount = activeVoiceCount()
        diag.distinctSounding = distinctSounding

        // ---- transport edges: all-notes-off (§7) ----
        if wasPlaying != playing {
            allNotesOff(atSample: AUEventSampleTimeImmediate, out: out)
            for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
            prevEffColumn = -1
            wasPlaying = playing
        }

        pool.rebuildSorted()
        diag.poolCount = pool.count

        // ---- derived column (§7). Musical space, so swing warps the beat→column map consistently
        //      with the arp ticks below. Locks are stubbed until step 6: effColumn == trueColumn. ----
        let mNow = musicalOf(beatPos, stepBeats: S, a: a)
        let cycleBeats = Double(Snap.cols) * S
        let posInCycle = mNow - (mNow / cycleBeats).rounded(.down) * cycleBeats
        let effColumn = min(Snap.cols - 1, max(0, Int(posInCycle / S)))
        diag.effColumn = effColumn
        diag.pass = Int((mNow / cycleBeats).rounded(.down))

        let active = topCell(in: effColumn, box)
        diag.activeCellRow = active?.row ?? -1

        guard playing else { return }   // `out` stays optional (openVoice/emit* tolerate nil)

        // ---- column transition (§7): active column changed → truncate all voices at the boundary
        //      (truncate-at-boundary tails), then emit the new column's HELD content once. A
        //      relocation/loop is the same edge, no special case. ----
        if effColumn != prevEffColumn {
            if anyVoiceActive() {
                let boundaryMusical = (mNow / S).rounded(.down) * S     // start of effColumn
                let realB = realOf(boundaryMusical, stepBeats: S, a: a)
                let off = max(0, (realB - beatPos) / beatsPerSample)
                allNotesOff(atSample: windowStart + AUEventSampleTime(off), out: out)
            }
            prevEffColumn = effColumn
            for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
            emitColumnHolds(box: box, column: effColumn, pool: pool, pass: diag.pass,
                            S: S, a: a, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                            windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        }

        guard pool.count > 0 else {
            diag.activeVoiceCount = activeVoiceCount(); diag.distinctSounding = distinctSounding; return
        }

        // ---- per-window TICK content: evaluate rows top-down so a fed cell reads its feeder's
        //      output (mirror model). ARP cells produce ticks; identity-fed cells mirror the feeder;
        //      identity-unfed cells have no tick content (their hold was emitted at the transition). ----
        for r in 0..<Snap.rows { articCount[r] = 0 }
        let windowBeats = Double(frameCount) * beatsPerSample

        for r in 0..<Snap.rows {
            let cell = box.cells[effColumn * Snap.rows + r]
            if cell.colourIndex < 0 || cell.muted { continue }
            let ci = Int(cell.colourIndex)
            let colour = box.colours[ci]
            let master = over(34, box.morphMaster)
            let morph = over(18 + ci, colour.morph)
            let t = effectiveT(colourMorph: morph, master: master, alt: cell.alt)
            let transpose = Int(over(2 + ci, Double(colour.transpose)).rounded())
            let fed = isFed(box, effColumn, r)
            let mode = cellMode(type: colour.a.type, bypassed: cell.bypassed,
                                passMask: colour.a.passMask, pass: diag.pass)
            let emits = cell.busMask != 0   // fan-out across every lit bus happens inside emitArtic

            if mode == .arp {
                var arpBeats = effectiveRateBeats(colour, t: t)
                let gate = effectiveGate(colour, t: t)
                let octaves = effectiveOctaves(colour, t: t)
                if arpBeats <= 0 { arpBeats = 0.25 }
                if r == diag.activeCellRow { diag.effMorphGold = t; diag.effRateBeats = arpBeats }

                iterateTicks(row: r, effColumn: effColumn, sub: arpBeats, gateFraction: gate,
                             beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                             beatsPerSample: beatsPerSample, S: S, a: a) { tick, mTickBeat, onTime, offTime in
                    let pIdx = phaseIndex(tick: tick, mTickBeat: mTickBeat, arpBeats: arpBeats, S: S,
                                          cycleBeats: cycleBeats, phase: colour.a.phase,
                                          runStartColumn: cell.runStartColumn)

                    // Input pick. Unfed (or +SRC) → source pool. FED → the feeder's CURRENT sounding
                    // note by derivation (window-independent), octave-arped by this cell (§1.1.3
                    // "arpeggiate the arpeggio"). +SRC-on-a-fed-ARP folds in source — no fixture yet.
                    let base: Int, prov: UInt8
                    if fed && !cell.srcMix {
                        guard let f = feederSoundingNote(row: r - 1, column: effColumn, m: mTickBeat,
                                                         box: box, pool: pool, S: S, cycleBeats: cycleBeats)
                        else { return }
                        let oct = Int64(max(1, octaves))
                        base = f.note + 12 * Int(((pIdx % oct) + oct) % oct)   // f.note already has feeder transpose
                        prov = f.chan
                    } else {
                        let pick = arpPickSource(phaseIndex: pIdx, octaves: octaves,
                                                 pattern: colour.a.patternIndex, pool: pool)
                        guard pick.base >= 0 else { return }
                        base = pick.base; prov = pick.chan
                    }
                    let noteValue = base + transpose
                    guard noteValue >= 0 && noteValue <= 127 else { return }

                    storeArtic(row: r, on: onTime, off: offTime, note: UInt8(noteValue), chan: prov, beat: mTickBeat)
                    if emits {
                        emitArtic(note: UInt8(noteValue), provenanceChan: prov,
                                  outChannel: colour.outChannel, busMask: cell.busMask,
                                  onSample: onTime, offSample: offTime, windowEnd: windowEnd,
                                  out: out, diag: &diag)
                    }
                }
            } else if mode == .ratchet {
                // RATCHET (§3): re-strike the WHOLE input pool `repeats` times per column, staccato
                // (0.6), with a velocity ramp. Not an arp (no index cycling) — every stab is the pool.
                let repeats = effectiveRepeats(colour, t: t)
                let ramp = effectiveRamp(colour, t: t)
                let sub = S / Double(repeats)                          // one repeat every `sub` beats
                if r == diag.activeCellRow { diag.effMorphGold = t; diag.effRateBeats = sub }

                iterateTicks(row: r, effColumn: effColumn, sub: sub, gateFraction: 0.6,
                             beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                             beatsPerSample: beatsPerSample, S: S, a: a) { _, mTickBeat, onTime, offTime in
                    let colStart = (mTickBeat / S).rounded(.down) * S
                    let repIdx = Int(((mTickBeat - colStart) / sub).rounded())    // 0…repeats-1
                    let vel = ratchetVelocity(base: 96, ramp: ramp, index: repIdx, count: repeats)

                    if fed && !cell.srcMix {
                        // ratchet the feeder's CURRENT sounding note (derivation, window-independent)
                        guard let f = feederSoundingNote(row: r - 1, column: effColumn, m: mTickBeat,
                                                         box: box, pool: pool, S: S, cycleBeats: cycleBeats)
                        else { return }
                        let n = f.note + transpose
                        guard n >= 0 && n <= 127 else { return }
                        storeArtic(row: r, on: onTime, off: offTime, note: UInt8(n), chan: f.chan, beat: mTickBeat)
                        if emits {
                            emitArtic(note: UInt8(n), provenanceChan: f.chan, outChannel: colour.outChannel,
                                      busMask: cell.busMask, onSample: onTime, offSample: offTime,
                                      windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                        }
                    } else {
                        // re-strike every held note (the source chord)
                        for k in 0..<pool.count {
                            let base = Int(pool.sorted[k])
                            let n = base + transpose
                            guard n >= 0 && n <= 127 else { continue }
                            storeArtic(row: r, on: onTime, off: offTime, note: UInt8(n), chan: pool.channel(of: base), beat: mTickBeat)
                            if emits {
                                emitArtic(note: UInt8(n), provenanceChan: pool.channel(of: base),
                                          outChannel: colour.outChannel, busMask: cell.busMask,
                                          onSample: onTime, offSample: offTime, windowEnd: windowEnd,
                                          velocity: vel, out: out, diag: &diag)
                            }
                        }
                    }
                }
            } else if mode == .strum {
                // STRUM (§3): stagger the source chord's onsets over `spread` beats from the column
                // start, held to the column boundary. Emitted per-window as each note's onset arrives
                // (strumProgress counter, reset per column) — boundary-safe, each note fires once.
                let spread = effectiveSpread(colour, t: t)
                let curve = colour.a.curve, tilt = colour.a.velTilt, dir = colour.a.strumDir
                let count = pool.count
                if r == diag.activeCellRow { diag.effMorphGold = t; diag.effRateBeats = spread }

                if count > 0 {
                    let colStart = (musicalOf(beatPos, stepBeats: S, a: a) / S).rounded(.down) * S
                    let offSample = sampleOf(musical: colStart + S, beatPos: beatPos,       // held to boundary
                                             beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    while strumProgress[r] < count {
                        let j = strumProgress[r]
                        let onsetMusical = colStart + strumOffset(index: j, count: count, spread: spread, curve: curve)
                        let onsetSample = sampleOf(musical: onsetMusical, beatPos: beatPos,
                                                   beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                        if onsetSample >= windowEnd { break }        // onset lands in a later window
                        strumProgress[r] += 1

                        let sortedIdx = strumSortedIndex(position: j, count: count, direction: dir, pass: diag.pass)
                        let baseNote = Int(pool.sorted[sortedIdx])
                        let n = baseNote + transpose
                        guard n >= 0 && n <= 127 else { continue }
                        let vel = strumVelocity(index: j, count: count, tilt: tilt, base: 96)
                        let onT = max(onsetSample, windowStart)
                        storeArtic(row: r, on: onT, off: offSample, note: UInt8(n), chan: pool.channel(of: baseNote), beat: onsetMusical)
                        if emits {
                            emitArtic(note: UInt8(n), provenanceChan: pool.channel(of: baseNote),
                                      outChannel: colour.outChannel, busMask: cell.busMask,
                                      onSample: onT, offSample: offSample, windowEnd: windowEnd,
                                      velocity: vel, out: out, diag: &diag)
                        }
                    }
                }
            } else if (mode == .identity || mode == .chance) && fed {
                // Identity/CHANCE fed: MIRROR the feeder's ticks (+ this cell's transpose). CHANCE
                // drops each note-on by a deterministic probability (off follows its on — we just
                // skip both). Open PASSGATE is .identity; a closed passgate is .silent → nothing here.
                let prob = (mode == .chance) ? effectiveProbability(colour, t: t) : 1
                let fr = r - 1
                for k in 0..<articCount[fr] {
                    let src = articBuf[fr * Router.articCap + k]
                    let n = Int(src.note) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    if mode == .chance && !chancePasses(beat: src.beat, note: n, probability: prob) { continue }
                    storeArtic(row: r, on: src.onSample, off: src.offSample, note: UInt8(n), chan: src.chan, beat: src.beat)
                    if emits {
                        emitArtic(note: UInt8(n), provenanceChan: src.chan,
                                  outChannel: colour.outChannel, busMask: cell.busMask,
                                  onSample: src.onSample, offSample: src.offSample,
                                  windowEnd: windowEnd, out: out, diag: &diag)
                    }
                }
            }
            // identity/chance-unfed: no tick content (their hold is emitted at the column transition)
        }
        diag.activeVoiceCount = activeVoiceCount()
        diag.distinctSounding = distinctSounding
    }
}

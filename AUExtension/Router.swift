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
// AudioToolbox is GONE (standalone-plan seam rule 1): the Router now emits through the Foundation-only
// `MIDIEmitter` protocol (Emission.swift) and names sample times as plain Int64 — the AU integer
// typedefs were only aliases (Int64=Int64, UInt32=UInt32, UInt64=
// UInt64). So this whole file — tick generation, the graph derivation, the 5-cable refcount — compiles
// into the macOS unit-test target. The live MIDIEmitter adapter lives in Kernel.swift.

// NotePool and the pure derivation functions (musicalOf/realOf, phaseIndex, arpPickSource,
// cellMode/CellMode, ratchetVelocity) now live in Derivations.swift — pure, Foundation-only, and
// unit-tested. The Router keeps only what depends on its state.

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
        var offSample: Int64 = .max
    }
    private var voices = [Voice](repeating: Voice(), count: 128)

    // Collision refcount (§7, normative): per (bus, channel, note). Note-ONs always emit
    // (re-articulation is audible truth); the wire note-OFF is emitted only when the LAST instance
    // releases — so a sustained note never drops under a same-pitch arp. 4 buses × 16 ch × 128 notes.
    // 5 cables now (delta §7b): 0 = ALL, 1–4 = A–D.
    private var refcount = [UInt8](repeating: 0, count: 5 * 16 * 128)
    private var distinctSounding = 0   // number of (cable,ch,note) with refcount > 0 (diag; kept incrementally)

    private var busChannels: [UInt8] = [1, 2, 3, 4]   // per-bus stamp channels, refreshed each process
    private var heldColumns: UInt8 = 0   // §5b COLUMN-SUBSET LAP: held column keys (bit i = column i),
                                         // ephemeral (PERFORM only), refreshed each process. 0 = no lap.
    private var wasPlaying = false
    private var prevEffColumn = -1   // column-transition edge (§7): change ⇒ truncate voices

    // AUDITION (§6.4 / delta §5): the held cell's target (col*rows+row, −1 = none), the sample the hold
    // began (its free phase clock's origin), and a dedicated tick-dedup slot. All ephemeral — audition
    // is a live gesture, never persisted, never in the snapshot.
    private var prevAudition = -1
    private var auditionStartSample: Int64 = 0
    private var auditionLastTick: Int64 = -1
    // Chord-hold audition (v2) scratch: the note-set the held source should be sounding through the
    // treatment, vs. what is sounding now — reconciled each window so the sustained preview follows the
    // keys live. Fixed 128-note bitsets + per-note velocity; reused every window, no hot-path allocation.
    private var auditionDesired = [Bool](repeating: false, count: 128)
    private var auditionCurrent = [Bool](repeating: false, count: 128)
    private var auditionVel = [UInt8](repeating: 96, count: 128)

    @inline(__always)
    private func rcIndex(_ cable: UInt8, _ chan: UInt8, _ note: UInt8) -> Int {
        (Int(cable % 5) * 16 + Int(chan & 15)) * 128 + Int(note & 127)
    }

    // Per-row reference scratch (delta §1). Each row's TICK articulations this window, so a
    // referencing cell can mirror its parent's output. Fixed capacity, no hot-path allocation.
    // lastTick dedups each row's arp independently across (rare) overlapping windows.
    private struct Artic {
        var onSample: Int64 = 0
        var offSample: Int64 = 0
        var note: UInt8 = 0    // after this row's accumulated transpose
        var beat: Double = 0   // musical onset beat — the stable seed for CHANCE (loop-consistent)
    }
    private static let articCap = 24
    private var articBuf = [Artic](repeating: Artic(), count: Snap.rows * Router.articCap)
    private var articCount = [Int](repeating: 0, count: Snap.rows)
    private var lastTick = [Int64](repeating: -1, count: Snap.rows)
    private var strumProgress = [Int](repeating: 0, count: Snap.rows)   // strum notes emitted this column, per row
    private var harmNotes = [Int](repeating: 0, count: 4)               // HARMONIZE fan scratch (root + 3 voices)
    private var harmVels = [UInt8](repeating: 0, count: 4)

    func reset() {
        for i in voices.indices { voices[i].active = false; voices[i].offSample = .max }
        for i in refcount.indices { refcount[i] = 0 }
        distinctSounding = 0
        wasPlaying = false
        for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
        prevEffColumn = -1
        prevAudition = -1; auditionLastTick = -1
        for i in overrides.indices { overrides[i] = .nan }
        overrideGen = .max
    }

    // MARK: parameter overrides

    @inline(__always)
    private func slot(for address: UInt64) -> Int? {
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
    func applyParamEvent(_ address: UInt64, _ value: Double, diag: inout KernelDiag) {
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
                           onSample: Int64, offSample: Int64,
                           velocity: UInt8 = 96, out: MIDIEmitter?) -> Int {
        guard let out else { return -1 }
        // Claim a slot BEFORE emitting: a note we can't track is worse than a dropped one (it would
        // hang). At 128-voice capacity this never trips for the real topologies.
        var slot = -1
        for i in voices.indices where !voices[i].active { slot = i; break }
        guard slot >= 0 else { return -1 }

        out.emit(sampleTime: onSample, cable: cable, 0x90 | chan, note, max(1, velocity))   // §7 clause 1: note-ons ALWAYS emit
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

    private func closeVoice(_ i: Int, atSample time: Int64, out: MIDIEmitter?) {
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
            out?.emit(sampleTime: time, cable: cable, 0x80 | chan, note, 0)
        }
    }

    /// Emit any scheduled gate-off that has come due this window (drained every render → no stuck
    /// note when a voice's off falls beyond the window it was opened in).
    private func drainDue(windowStart: Int64, windowEnd: Int64,
                          out: MIDIEmitter?) {
        for i in voices.indices where voices[i].active && voices[i].offSample <= windowEnd {
            closeVoice(i, atSample: max(voices[i].offSample, windowStart), out: out)
        }
    }

    /// Close every sounding voice at one sample time (transport edge, column transition, reset).
    func allNotesOff(atSample time: Int64, out: MIDIEmitter?) {
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

    // MARK: - graph routing (delta §1)

    /// The resolved parent ROW of a cell's input, with the live reroute applied. Returns the
    /// precomputed `resolvedParent` (§2), UNLESS that parent is muted → revert to MIDI IN. −1 = MIDI
    /// IN (the cell hears the source pool). Configuration (`inputRow`) is untouched — derivation only
    /// (delta §1 reroute rule). Any row is legal (upward or downward); cycles are broken by the
    /// depth guard in parentSoundingNote and are silent by construction.
    @inline(__always)
    private func parentRow(_ box: SnapshotBox, _ column: Int, _ row: Int) -> Int {
        let p = Int(box.cells[column * Snap.rows + row].resolvedParent)
        if p >= 0 && !box.cells[column * Snap.rows + p].muted { return p }
        return -1
    }

    @inline(__always)
    private func sampleOf(musical: Double, beatPos: Double, beatsPerSample: Double,
                          windowStart: Int64, S: Double, a: Double) -> Int64 {
        let real = realOf(musical, stepBeats: S, a: a)
        return windowStart + Int64(max(0, (real - beatPos) / beatsPerSample))
    }

    private func storeArtic(row: Int, on: Int64, off: Int64,
                            note: UInt8, beat: Double) {
        let c = articCount[row]
        guard c < Router.articCap else { return }
        let i = row * Router.articCap + c
        articBuf[i].onSample = on; articBuf[i].offSample = off
        articBuf[i].note = note; articBuf[i].beat = beat
        articCount[row] = c + 1
    }

    /// FAN OUT one articulation to every lit bus (§2.3). Channel is STAMPED per bus here (delta §7:
    /// notes have no channel until this exit); each bus emits TWICE — its own cable (bus+1) and the
    /// ALL cable (0), both on busChannels[bus] (§7b). Every (cable,channel,note) is an independent
    /// voice under the refcount, so the ALL duplicate and any shared-channel merge off-pair correctly.
    /// Channel comes ONLY from the bus stamp now (INHERIT/OUT CH removed, delta §7).
    private func emitArtic(note: UInt8, busMask: UInt8,
                           onSample: Int64, offSample: Int64,
                           windowEnd: Int64, velocity: UInt8 = 96,
                           out: MIDIEmitter?, diag: inout KernelDiag) {
        var lastCh: UInt8 = 0
        var mask = busMask
        while mask != 0 {
            let bus = Int(mask.trailingZeroBitCount)          // 0…3 = A…D
            mask &= mask - 1
            let ch = (busChannels[bus] &- 1) & 15             // 1–16 stored → 0–15 wire
            lastCh = ch
            // own cable (bus+1) and the ALL cable (0) — both channel-stamped identically (no array
            // literal on the hot path). Unrolled to avoid allocation.
            let own = openVoice(note: note, chan: ch, cable: UInt8(bus + 1),
                                onSample: onSample, offSample: offSample, velocity: velocity, out: out)
            if own >= 0 && offSample <= windowEnd { closeVoice(own, atSample: offSample, out: out) }
            let all = openVoice(note: note, chan: ch, cable: 0,
                                onSample: onSample, offSample: offSample, velocity: velocity, out: out)
            if all >= 0 && offSample <= windowEnd { closeVoice(all, atSample: offSample, out: out) }
        }
        diag.emitCount &+= 1
        diag.lastEmitNote = note
        diag.lastEmitChan = lastCh
    }

    /// HOLD content, emitted ONCE per column at the transition: an identity cell whose input is MIDI
    /// IN articulates the whole (filtered) source chord and holds it to the column boundary (identity
    /// = sample-and-hold of its input pool). Arp cells and referencing mirrors have no hold.
    /// HARMONIZE emit (§3): expand `base` (post-transpose) into root + up to 3 interval voices and
    /// emit each with its velocity (root full, added voices scaled). Optionally stores artics so a
    /// downstream mirror sees the full expanded set. Shared by the MIDI-IN hold and the mirror path.
    private func emitHarmony(base: Int, colour: SnapColour, t: Double, baseVel: UInt8, row: Int,
                             storeArtics: Bool, busMask: UInt8,
                             on: Int64, off: Int64, beat: Double,
                             windowEnd: Int64, out: MIDIEmitter?,
                             diag: inout KernelDiag) {
        let iv = (Int8(effectiveHarmInterval(colour, voice: 0, t: t)),
                  Int8(effectiveHarmInterval(colour, voice: 1, t: t)),
                  Int8(effectiveHarmInterval(colour, voice: 2, t: t)))
        let scale = effectiveHarmVelScale(colour, t: t)
        let cnt = harmonizeVoices(base: base, intervals: iv, into: &harmNotes,
                                  vel: baseVel, velScale: scale, vels: &harmVels)
        for i in 0..<cnt {
            if storeArtics { storeArtic(row: row, on: on, off: off, note: UInt8(harmNotes[i]), beat: beat) }
            if busMask != 0 {
                emitArtic(note: UInt8(harmNotes[i]), busMask: busMask, onSample: on, offSample: off,
                          windowEnd: windowEnd, velocity: harmVels[i], out: out, diag: &diag)
            }
        }
    }

    private func emitColumnHolds(box: SnapshotBox, column: Int, pool: NotePool, pass: Int,
                                 S: Double, a: Double, mNow: Double, beatPos: Double,
                                 beatsPerSample: Double, windowStart: Int64,
                                 windowEnd: Int64, out: MIDIEmitter?,
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
            // Cells that chord-hold their MIDI-IN source: identity (incl. open passgate), CHANCE
            // (drops each note by probability), and HARMONIZE (expands each note to voices).
            // Arp/ratchet/strum and a closed passgate do not chord-hold.
            let mode = cellMode(type: colour.a.type, bypassed: cell.bypassed,
                                passMask: colour.a.passMask, pass: pass)
            guard mode == .identity || mode == .chance || mode == .harmonize else { continue }
            guard parentRow(box, column, r) < 0 else { continue }   // holds source only when input is MIDI IN
            let transpose = Int(over(2 + ci, Double(colour.transpose)).rounded())
            let t = effectiveT(colourMorph: over(18 + ci, colour.morph), master: over(34, box.morphMaster), alt: cell.alt)
            let prob = (mode == .chance) ? effectiveProbability(colour, t: t) : 1
            let srcN = pool.srcCount(filter: cell.inputChannel)   // §7 source filter
            for k in 0..<srcN {
                let base = Int(pool.srcAscending(k, filter: cell.inputChannel))
                let n = base + transpose
                guard n >= 0 && n <= 127 else { continue }
                if mode == .chance && !chancePasses(beat: colStart, note: n, probability: prob) { continue }
                if mode == .harmonize {
                    emitHarmony(base: n, colour: colour, t: t, baseVel: 96, row: r, storeArtics: false,
                                busMask: cell.busMask, on: onSample, off: offSample, beat: colStart,
                                windowEnd: windowEnd, out: out, diag: &diag)
                } else {
                    emitArtic(note: UInt8(n), busMask: cell.busMask,
                              onSample: onSample, offSample: offSample, windowEnd: windowEnd,
                              out: out, diag: &diag)
                }
            }
        }
    }

    /// The single sounding note of the cell at (column, row) at musical beat `m`, computed by
    /// DERIVATION — valid at ANY instant, independent of render-window boundaries. This is what lets
    /// a referencing ARP sample its parent's CURRENT note even when that note was struck in an earlier
    /// window (the per-window artic scratch cannot). Recurses up the reference graph (delta §1), any
    /// row, cycle-guarded by `depth`. No channel — past the input filter notes carry none (delta §7).
    ///  · ARP referencing    → its arp note at m (over its own parent or the filtered source).
    ///  · identity referencing → mirrors the parent's note (+ this transpose).
    ///  · identity at MIDI IN → the source chord is a POOL, not one note → nil (documented limit).
    private func parentSoundingNote(row: Int, column: Int, m: Double, box: SnapshotBox,
                                    pool: NotePool, S: Double, cycleBeats: Double,
                                    depth: Int = 0) -> Int? {
        guard row >= 0, depth < Snap.rows else { return nil }   // depth guard = cycles are silent (delta §1)
        let cell = box.cells[column * Snap.rows + row]
        guard cell.colourIndex >= 0, !cell.muted else { return nil }
        let ci = Int(cell.colourIndex)
        let colour = box.colours[ci]
        let transpose = Int(over(2 + ci, Double(colour.transpose)).rounded())
        let parent = parentRow(box, column, row)               // §1: any-row reference, muted→MIDI IN
        let referencing = parent >= 0
        let pass = Int((m / cycleBeats).rounded(.down))
        let mode = cellMode(type: colour.a.type, bypassed: cell.bypassed, passMask: colour.a.passMask, pass: pass)
        if mode == .silent { return nil }      // e.g. a closed passgate sounds nothing
        // ratchet & harmonize sound a POOL (a chord), not one note — a referencing arp can't sample them
        if mode == .ratchet || mode == .harmonize { return nil }

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
            if referencing {
                guard let up = parentSoundingNote(row: parent, column: column, m: m,
                                                  box: box, pool: pool, S: S, cycleBeats: cycleBeats,
                                                  depth: depth + 1)
                else { return nil }
                let oct = Int64(max(1, octaves))
                return up + 12 * Int(((pIdx % oct) + oct) % oct) + transpose
            }
            let base = arpPickSource(phaseIndex: pIdx, octaves: octaves, pattern: colour.a.patternIndex,
                                     pool: pool, filter: cell.inputChannel)   // MIDI IN → filtered source (§7)
            return base >= 0 ? base + transpose : nil
        }
        if referencing {
            guard let up = parentSoundingNote(row: parent, column: column, m: m,
                                              box: box, pool: pool, S: S, cycleBeats: cycleBeats,
                                              depth: depth + 1)
            else { return nil }
            return up + transpose          // identity mirror
        }
        return nil   // identity at MIDI IN: a chord (pool), not one note — see doc comment
    }

    /// The shared subdivision-tick scaffold for ARP and RATCHET. Walks every tick of length `sub`
    /// in this window that belongs to `effColumn`, dedups per row, and hands the body the tick's
    /// index, musical beat, and unwarped on/off sample times. `gateFraction` sets the note length
    /// as a fraction of `sub` (truncated at the column boundary). The body decides WHAT to emit;
    /// this owns the timing — so the boundary/dedup logic lives in exactly one place.
    /// Return from the body to skip a tick (the equivalent of `continue`).
    private func iterateTicks(row: Int, effColumn: Int, sub: Double, gateFraction: Double,
                              beatPos: Double, windowBeats: Double, windowStart: Int64,
                              beatsPerSample: Double, S: Double, a: Double,
                              _ body: (_ tick: Int64, _ mTickBeat: Double,
                                       _ onTime: Int64, _ offTime: Int64) -> Void) {
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
            // Which column is EFFECTIVE at this tick's step (lap-aware, §5b) — so a held column's ticks
            // fire during the current window even though the tick's TRUE column differs. With no lap,
            // lapColumn returns the tick's true column and this is the original `tickCol == effColumn`.
            let tickStep = Int((mTickBeat / S).rounded(.down))
            let tickTrueCol = ((tickStep % Snap.cols) + Snap.cols) % Snap.cols
            if lapColumn(laneMask: heldColumns, absoluteStep: tickStep, trueColumn: tickTrueCol) != effColumn { continue }
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
                 frameCount: UInt32,
                 audition: Int = -1,
                 laneMask: UInt8 = 0,
                 out: MIDIEmitter?,
                 diag: inout KernelDiag) {

        busChannels = box.busChannels               // delta §7: per-bus stamp channels, this render
        heldColumns = laneMask                      // §5b lap: held column keys, this render

        // ---- window in samples; global (non-cell) timing ----
        let windowStart = Int64(timestampSample)
        let windowEnd = windowStart + Int64(frameCount)
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
            allNotesOff(atSample: renderSampleImmediate, out: out)
            for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
            prevEffColumn = -1
            wasPlaying = playing
        }

        pool.rebuildSorted()
        diag.poolCount = pool.count

        // ---- AUDITION (transport stopped): a held cell sounds its processor ALONE against the live
        //      source — phase zeroed, input forced to source, all-open passgate, host tempo (§6.4 /
        //      delta §5). The wasPlaying edge above already flushed any voices, so transport start
        //      auto-releases the audition; release is handled inside auditionRender on target change. ----
        if !playing {
            auditionRender(box: box, pool: pool, target: audition, tempo: tempo, sampleRate: sampleRate,
                           timestampSample: timestampSample, frameCount: frameCount, S: S, out: out, diag: &diag)
            diag.activeVoiceCount = activeVoiceCount(); diag.distinctSounding = distinctSounding
            return
        }
        prevAudition = -1   // playing ⇒ any audition was auto-released by the transport-start edge

        // ---- derived column (§7). Musical space, so swing warps the beat→column map consistently
        //      with the arp ticks below. The COLUMN-SUBSET LAP (§5b) warps WHICH column is effective
        //      (held keys); the TRUE timeline — pass, passgate, swing — is unwarped (all off mNow). ----
        let mNow = musicalOf(beatPos, stepBeats: S, a: a)
        let cycleBeats = Double(Snap.cols) * S
        let posInCycle = mNow - (mNow / cycleBeats).rounded(.down) * cycleBeats
        let trueColumn = min(Snap.cols - 1, max(0, Int(posInCycle / S)))
        let absoluteStep = Int((mNow / S).rounded(.down))          // global step counter (derived)
        let effColumn = lapColumn(laneMask: heldColumns, absoluteStep: absoluteStep, trueColumn: trueColumn)
        diag.effColumn = effColumn
        diag.pass = Int((mNow / cycleBeats).rounded(.down))        // TRUE pass — never remapped (§5b)

        let active = topCell(in: effColumn, box)
        diag.activeCellRow = active?.row ?? -1
        // v3.0 precompute exposure (read-only; router still routes by the old model until commit 3)
        diag.activeCellParent = active.map { box.cells[effColumn * Snap.rows + $0.row].resolvedParent } ?? -1

        guard playing else { return }   // `out` stays optional (openVoice/emit* tolerate nil)

        // ---- column transition (§7): active column changed → truncate all voices at the boundary
        //      (truncate-at-boundary tails), then emit the new column's HELD content once. A
        //      relocation/loop is the same edge, no special case. ----
        if effColumn != prevEffColumn {
            if anyVoiceActive() {
                let boundaryMusical = (mNow / S).rounded(.down) * S     // start of effColumn
                let realB = realOf(boundaryMusical, stepBeats: S, a: a)
                let off = max(0, (realB - beatPos) / beatsPerSample)
                allNotesOff(atSample: windowStart + Int64(off), out: out)
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
            let parent = parentRow(box, effColumn, r)   // §1: resolved input row (−1 = MIDI IN), muted→MIDI IN
            let fed = parent >= 0
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

                    // Input pick. MIDI IN → filtered source pool. Referencing → the parent's CURRENT
                    // sounding note by derivation (window-independent, any row incl. downward;
                    // cycle-guarded), octave-arped by this cell (delta §1 "arpeggiate the arpeggio").
                    let base: Int
                    if fed {
                        guard let up = parentSoundingNote(row: parent, column: effColumn, m: mTickBeat,
                                                          box: box, pool: pool, S: S, cycleBeats: cycleBeats)
                        else { return }
                        let oct = Int64(max(1, octaves))
                        base = up + 12 * Int(((pIdx % oct) + oct) % oct)   // up already has parent transpose
                    } else {
                        base = arpPickSource(phaseIndex: pIdx, octaves: octaves,
                                             pattern: colour.a.patternIndex, pool: pool,
                                             filter: cell.inputChannel)   // §7 source filter
                        guard base >= 0 else { return }
                    }
                    let noteValue = base + transpose
                    guard noteValue >= 0 && noteValue <= 127 else { return }

                    storeArtic(row: r, on: onTime, off: offTime, note: UInt8(noteValue), beat: mTickBeat)
                    if emits {
                        emitArtic(note: UInt8(noteValue), busMask: cell.busMask,
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

                    if fed {
                        // ratchet the parent's CURRENT sounding note (derivation, any row, cycle-guarded)
                        guard let up = parentSoundingNote(row: parent, column: effColumn, m: mTickBeat,
                                                          box: box, pool: pool, S: S, cycleBeats: cycleBeats)
                        else { return }
                        let n = up + transpose
                        guard n >= 0 && n <= 127 else { return }
                        storeArtic(row: r, on: onTime, off: offTime, note: UInt8(n), beat: mTickBeat)
                        if emits {
                            emitArtic(note: UInt8(n), busMask: cell.busMask,
                                      onSample: onTime, offSample: offTime,
                                      windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                        }
                    } else {
                        // re-strike every held note passing the input-channel filter (§7)
                        let srcN = pool.srcCount(filter: cell.inputChannel)
                        for k in 0..<srcN {
                            let base = Int(pool.srcAscending(k, filter: cell.inputChannel))
                            let n = base + transpose
                            guard n >= 0 && n <= 127 else { continue }
                            storeArtic(row: r, on: onTime, off: offTime, note: UInt8(n), beat: mTickBeat)
                            if emits {
                                emitArtic(note: UInt8(n), busMask: cell.busMask,
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
                let count = pool.srcCount(filter: cell.inputChannel)   // §7 source filter
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
                        let baseNote = Int(pool.srcAscending(sortedIdx, filter: cell.inputChannel))
                        let n = baseNote + transpose
                        guard n >= 0 && n <= 127 else { continue }
                        let vel = strumVelocity(index: j, count: count, tilt: tilt, base: 96)
                        let onT = max(onsetSample, windowStart)
                        storeArtic(row: r, on: onT, off: offSample, note: UInt8(n), beat: onsetMusical)
                        if emits {
                            emitArtic(note: UInt8(n), busMask: cell.busMask,
                                      onSample: onT, offSample: offSample, windowEnd: windowEnd,
                                      velocity: vel, out: out, diag: &diag)
                        }
                    }
                }
            } else if (mode == .identity || mode == .chance || mode == .harmonize) && fed {
                // Identity/CHANCE/HARMONIZE referenced: MIRROR the parent's ticks (+ this transpose).
                // CHANCE drops each note-on by probability; HARMONIZE expands each to voices.
                // articBuf holds this-pass artics, so an UPWARD parent (already evaluated) mirrors
                // correctly; a DOWNWARD parent's buffer is empty this pass → silent (unit-delay not
                // yet double-buffered — no fixture needs it; backward taps use ARP references).
                let prob = (mode == .chance) ? effectiveProbability(colour, t: t) : 1
                let fr = parent
                for k in 0..<articCount[fr] {
                    let src = articBuf[fr * Router.articCap + k]
                    let n = Int(src.note) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    if mode == .chance && !chancePasses(beat: src.beat, note: n, probability: prob) { continue }
                    if mode == .harmonize {
                        emitHarmony(base: n, colour: colour, t: t, baseVel: 96, row: r, storeArtics: true,
                                    busMask: emits ? cell.busMask : 0, on: src.onSample, off: src.offSample,
                                    beat: src.beat, windowEnd: windowEnd, out: out, diag: &diag)
                    } else {
                        storeArtic(row: r, on: src.onSample, off: src.offSample, note: UInt8(n), beat: src.beat)
                        if emits {
                            emitArtic(note: UInt8(n), busMask: cell.busMask,
                                      onSample: src.onSample, offSample: src.offSample,
                                      windowEnd: windowEnd, out: out, diag: &diag)
                        }
                    }
                }
            }
            // identity/chance-unfed: no tick content (their hold is emitted at the column transition)
        }
        diag.activeVoiceCount = activeVoiceCount()
        diag.distinctSounding = distinctSounding
    }

    // MARK: - audition (§6.4 / delta §5)

    /// Sound the held cell's processor ALONE against the live source while the transport is stopped.
    /// §6.4: phase zeroed, input FORCED to source (the `inputRow` reference is ignored), the cell's
    /// active A/B state, its lit letters, passgates all-open, an internal phase clock at host tempo.
    /// A change of `target` (new cell, switched cell, or release → −1) flushes and restarts the clock;
    /// transport start flushes via the process() transport edge (auto-release). v1 handles the
    /// time-varying processors ARP and RATCHET; chord-hold types (identity/passgate/chance/harmonize/
    /// strum) fall through to the Kernel's raw passthrough (their live-tracked audition is v2).
    private func auditionRender(box: SnapshotBox, pool: NotePool, target: Int,
                                tempo: Double, sampleRate: Double, timestampSample: Double,
                                frameCount: UInt32, S: Double, out: MIDIEmitter?, diag: inout KernelDiag) {
        let windowStart = Int64(timestampSample)
        if target != prevAudition {          // hold began / switched / released → cut and re-origin the clock
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevAudition = target
            auditionStartSample = windowStart
            auditionLastTick = -1
        }
        guard target >= 0 else { return }
        let col = target / Snap.rows, row = target % Snap.rows
        guard col >= 0, col < Snap.cols, row >= 0, row < Snap.rows else { return }
        let cell = box.cells[col * Snap.rows + row]
        guard cell.colourIndex >= 0, !cell.muted, cell.busMask != 0, !cell.bypassed else { return }
        guard pool.count > 0 else { return }          // no held notes → silence (soundcheck)
        let ci = Int(cell.colourIndex)
        let colour = box.colours[ci]

        let beatsPerSample = tempo / 60.0 / sampleRate
        let auditionBeat = Double(windowStart - auditionStartSample) * beatsPerSample   // free phase clock
        let windowBeats = Double(frameCount) * beatsPerSample
        let windowEnd = windowStart + Int64(frameCount)
        let t = effectiveT(colourMorph: over(18 + ci, colour.morph), master: over(34, box.morphMaster), alt: cell.alt)
        let transpose = Int(over(2 + ci, Double(colour.transpose)).rounded())

        switch colour.a.type {
        case .arp:
            var arpBeats = effectiveRateBeats(colour, t: t); if arpBeats <= 0 { arpBeats = 0.25 }
            let gate = effectiveGate(colour, t: t)
            let octaves = effectiveOctaves(colour, t: t)
            auditionTicks(sub: arpBeats, gateFraction: gate, startBeat: auditionBeat, windowBeats: windowBeats,
                          windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
                let base = arpPickSource(phaseIndex: tick, octaves: octaves,   // phase zeroed: index = ticks since hold
                                         pattern: colour.a.patternIndex, pool: pool, filter: cell.inputChannel)
                guard base >= 0 else { return }
                let n = base + transpose; guard n >= 0 && n <= 127 else { return }
                emitArtic(note: UInt8(n), busMask: cell.busMask, onSample: onT, offSample: offT,
                          windowEnd: windowEnd, out: out, diag: &diag)
            }
        case .ratchet:
            let repeats = effectiveRepeats(colour, t: t)
            let ramp = effectiveRamp(colour, t: t)
            let sub = S / Double(max(1, repeats))
            auditionTicks(sub: sub, gateFraction: 0.6, startBeat: auditionBeat, windowBeats: windowBeats,
                          windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
                let repIdx = ((Int(tick) % repeats) + repeats) % repeats
                let vel = ratchetVelocity(base: 96, ramp: ramp, index: repIdx, count: repeats)
                let srcN = pool.srcCount(filter: cell.inputChannel)
                for k in 0..<srcN {
                    let n = Int(pool.srcAscending(k, filter: cell.inputChannel)) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    emitArtic(note: UInt8(n), busMask: cell.busMask, onSample: onT, offSample: offT,
                              windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
        case .strum:
            // STRUM: roll the held chord in over `spread` beats from the hold (its own onset per note),
            // then sustain — the audition clock drives the roll; reconcile tracks live key changes.
            auditionStrum(cell: cell, colour: colour, pool: pool, transpose: transpose, t: t,
                          auditionBeat: auditionBeat, windowEnd: windowEnd, out: out, diag: &diag)
        default:
            // chord-hold types (passgate all-open / chance / harmonize): sustain the treated chord,
            // reconciled to the live held source each window (v2).
            auditionChordHold(cell: cell, colour: colour, pool: pool, transpose: transpose, t: t,
                              windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        }
    }

    /// Sustain the held source chord through a chord-hold treatment (§6.4), tracking the keys LIVE:
    /// build the note-set the source should sound through the treatment, then reconcile against what is
    /// currently sounding — close departed notes, open new ones (sustained; released by allNotesOff on
    /// hold-change / transport-start). passgate is forced all-open; chance seeds on the hold (beat 0) so
    /// each note is deterministically in or out for the whole hold; harmonize expands to its voices.
    private func auditionChordHold(cell: SnapCell, colour: SnapColour, pool: NotePool,
                                   transpose: Int, t: Double, windowStart: Int64, windowEnd: Int64,
                                   out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionDesired[i] = false }
        let type = colour.a.type
        let prob = (type == .chance) ? effectiveProbability(colour, t: t) : 1
        let srcN = pool.srcCount(filter: cell.inputChannel)         // §7 source filter, forced source
        for k in 0..<srcN {
            let base = Int(pool.srcAscending(k, filter: cell.inputChannel)) + transpose
            guard base >= 0 && base <= 127 else { continue }
            switch type {
            case .harmonize:
                let iv = (Int8(effectiveHarmInterval(colour, voice: 0, t: t)),
                          Int8(effectiveHarmInterval(colour, voice: 1, t: t)),
                          Int8(effectiveHarmInterval(colour, voice: 2, t: t)))
                let cnt = harmonizeVoices(base: base, intervals: iv, into: &harmNotes,
                                          vel: 96, velScale: effectiveHarmVelScale(colour, t: t), vels: &harmVels)
                for j in 0..<cnt where harmNotes[j] >= 0 && harmNotes[j] <= 127 {
                    auditionDesired[harmNotes[j]] = true; auditionVel[harmNotes[j]] = harmVels[j]
                }
            case .chance:
                if chancePasses(beat: 0, note: base, probability: prob) { auditionDesired[base] = true; auditionVel[base] = 96 }
            default:                                                 // passgate all-open (sustain the chord)
                auditionDesired[base] = true; auditionVel[base] = 96
            }
        }
        reconcileAuditionVoices(busMask: cell.busMask, windowEnd: windowEnd, out: out, diag: &diag)
    }

    /// STRUM audition: the held chord ROLLS in — each note has its own onset (`strumOffset`) measured
    /// from the hold; a note joins the sustained set once the audition clock passes its onset. So the
    /// first hold rolls the chord; thereafter it sustains and reconcile tracks live key changes. No
    /// columns here, so direction uses pass 0 and notes never auto-release (offSample .max).
    private func auditionStrum(cell: SnapCell, colour: SnapColour, pool: NotePool,
                               transpose: Int, t: Double, auditionBeat: Double,
                               windowEnd: Int64, out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionDesired[i] = false }
        let spread = effectiveSpread(colour, t: t)
        let count = pool.srcCount(filter: cell.inputChannel)
        for j in 0..<count {
            guard auditionBeat >= strumOffset(index: j, count: count, spread: spread, curve: colour.a.curve)
            else { continue }                                   // this note's onset hasn't arrived yet
            let sortedIdx = strumSortedIndex(position: j, count: count, direction: colour.a.strumDir, pass: 0)
            let n = Int(pool.srcAscending(sortedIdx, filter: cell.inputChannel)) + transpose
            guard n >= 0 && n <= 127 else { continue }
            auditionDesired[n] = true
            auditionVel[n] = strumVelocity(index: j, count: count, tilt: colour.a.velTilt, base: 96)
        }
        reconcileAuditionVoices(busMask: cell.busMask, windowEnd: windowEnd, out: out, diag: &diag)
    }

    /// Drive the sustained audition voices toward `auditionDesired`/`auditionVel`: close any sounding
    /// note no longer wanted, open any wanted note not yet sounding — IMMEDIATE ("sound now"), never
    /// auto-closing (offSample .max); reconcile / release ends them. Shared by chord-hold and strum.
    private func reconcileAuditionVoices(busMask: UInt8, windowEnd: Int64, out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionCurrent[i] = false }
        for v in voices where v.active { auditionCurrent[Int(v.note)] = true }
        for i in voices.indices where voices[i].active && !auditionDesired[Int(voices[i].note)] {
            closeVoice(i, atSample: renderSampleImmediate, out: out)
        }
        for n in 0..<128 where auditionDesired[n] && !auditionCurrent[n] {
            emitArtic(note: UInt8(n), busMask: busMask, onSample: renderSampleImmediate, offSample: .max,
                      windowEnd: windowEnd, velocity: auditionVel[n], out: out, diag: &diag)
        }
    }

    /// The audition tick scaffold: like `iterateTicks` but with NO column gating and a single dedup
    /// slot — audition is one free-running cell. `startBeat` is beats elapsed since the hold began, so
    /// `tick` counts from 0 (phase zeroed). floor + the `== auditionLastTick` dedup catches a boundary
    /// tick exactly once across windows (fired at window start when clamped), matching iterateTicks.
    private func auditionTicks(sub: Double, gateFraction: Double, startBeat: Double, windowBeats: Double,
                               windowStart: Int64, beatsPerSample: Double,
                               _ body: (_ tick: Int64, _ onT: Int64, _ offT: Int64) -> Void) {
        guard sub > 0 else { return }
        let firstTick = Int64((startBeat / sub).rounded(.down))
        let lastT = Int64(((startBeat + windowBeats) / sub).rounded(.down))
        guard firstTick <= lastT else { return }
        for tick in firstTick...lastT {
            if tick == auditionLastTick { continue }
            auditionLastTick = tick
            let tickBeat = Double(tick) * sub
            let onT = windowStart + Int64(max(0, (tickBeat - startBeat) / beatsPerSample))
            let offT = windowStart + Int64(max(0, (tickBeat + sub * gateFraction - startBeat) / beatsPerSample))
            body(tick, onT, offT)
        }
    }
}

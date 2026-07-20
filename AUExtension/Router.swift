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

// MARK: - The source pool (§2.5): omni, keyed by note number

/// The live held-note pool. All input channels merge (omni, §2.5) — note number is the key —
/// but each note's originating channel is remembered for INHERIT stamping (§2.6). Fixed capacity,
/// no allocation after init. A class so the Kernel (writer) and Router (reader) share one instance
/// with no copies on the hot path.
final class NotePool {
    private var vel = [UInt8](repeating: 0, count: 128)   // velocity by note (0 = not held)
    private var chan = [UInt8](repeating: 0, count: 128)  // originating channel by note
    private(set) var sorted = [UInt8](repeating: 0, count: 128)
    private(set) var count = 0

    func reset() {
        for i in 0..<128 { vel[i] = 0; chan[i] = 0 }
        count = 0
    }

    func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8) {
        let n = Int(note)
        if velocity > 0 {
            if vel[n] == 0 { count += 1 }
            vel[n] = velocity
            chan[n] = channel
        } else {
            noteOff(note)
        }
    }

    func noteOff(_ note: UInt8) {
        let n = Int(note)
        if vel[n] != 0 { count -= 1 }
        vel[n] = 0
    }

    @inline(__always) func channel(of note: Int) -> UInt8 { chan[note] }

    /// Rebuild the ascending note list; also re-derives `count` (belt-and-braces vs the
    /// incremental count, matching the pre-split behaviour).
    func rebuildSorted() {
        var n = 0
        for note in 0..<128 where vel[note] != 0 { sorted[n] = UInt8(note); n += 1 }
        count = n
    }
}

// MARK: - The router / arp engine

final class Router {

    // Render-side parameter overrides (§7 second route). Slots:
    //   0 stepRate · 1 swing · 2+i transpose(i) · 18+i morph(i) · 34 morphMaster
    private var overrides = [Double](repeating: .nan, count: 35)
    private var overrideGen: UInt64 = .max

    // Poly note tracker (§7). Each sounding note is a Voice carrying the channel + cable its on used
    // and an ABSOLUTE gate-off sample, drained every render so an off beyond its opening window is
    // never dropped (no stuck note). Fixed capacity; no allocation on the hot path. The
    // (bus, channel, note) COLLISION refcount is commit 6 — until then two voices on the same wire
    // note off independently (fine for the current single-emitter test topologies).
    private struct Voice {
        var active = false
        var note: UInt8 = 0
        var chan: UInt8 = 0
        var cable: UInt8 = 0
        var offSample: AUEventSampleTime = .max
    }
    private var voices = [Voice](repeating: Voice(), count: 128)
    private var wasPlaying = false
    private var lastTickIndex: Int64 = -1
    private var prevEffColumn = -1   // column-transition edge (§7): change ⇒ truncate voices

    func reset() {
        for i in voices.indices { voices[i].active = false; voices[i].offSample = .max }
        wasPlaying = false
        lastTickIndex = -1
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

    // MARK: - Swing warp (§4 v2.3): real beat ⇄ musical beat, identity at 50.

    @inline(__always)
    private func musicalOf(_ realBeat: Double, stepBeats S: Double, a: Double) -> Double {
        let pair = 2 * S
        let base = (realBeat / pair).rounded(.down) * pair
        let u = realBeat - base
        let split = a * S
        let m = u < split ? u / a : S + (u - split) / (2 - a)
        return base + m
    }

    @inline(__always)
    private func realOf(_ musicalBeat: Double, stepBeats S: Double, a: Double) -> Double {
        let pair = 2 * S
        let base = (musicalBeat / pair).rounded(.down) * pair
        let v = musicalBeat - base
        let u = v < S ? v * a : a * S + (v - S) * (2 - a)
        return base + u
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
                           out: AUMIDIOutputEventBlock) -> Int {
        var on: [UInt8] = [0x90 | chan, note, 96]
        _ = out(onSample, cable, 3, &on)
        for i in voices.indices where !voices[i].active {
            voices[i].active = true
            voices[i].note = note
            voices[i].chan = chan
            voices[i].cable = cable
            voices[i].offSample = offSample
            return i
        }
        return -1
    }

    private func closeVoice(_ i: Int, atSample time: AUEventSampleTime, out: AUMIDIOutputEventBlock?) {
        guard voices[i].active else { return }
        if let out {
            var off: [UInt8] = [0x80 | voices[i].chan, voices[i].note, 0]
            _ = out(time, voices[i].cable, 3, &off)
        }
        voices[i].active = false
        voices[i].offSample = .max
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

        // ---- transport edges: all-notes-off (§7) ----
        if wasPlaying != playing {
            allNotesOff(atSample: AUEventSampleTimeImmediate, out: out)
            lastTickIndex = -1
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

        guard playing, let out else { return }

        // ---- column transition (§7): the active column changed → truncate the sounding voice at
        //      the boundary (truncate-at-boundary tails). A relocation/loop is the same edge. ----
        if effColumn != prevEffColumn {
            if anyVoiceActive() {
                let boundaryMusical = (mNow / S).rounded(.down) * S     // start of effColumn
                let realB = realOf(boundaryMusical, stepBeats: S, a: a)
                let off = max(0, (realB - beatPos) / beatsPerSample)
                allNotesOff(atSample: windowStart + AUEventSampleTime(off), out: out)
            }
            prevEffColumn = effColumn
            lastTickIndex = -1
        }

        guard pool.count > 0, let cell = active?.cell else { return }   // rest column / no held notes

        // ---- effective params for THIS cell's Colour (overrides keyed by colour index) ----
        let ci = Int(cell.colourIndex)
        let colour = box.colours[ci]
        let master = over(34, box.morphMaster)
        let morph = over(18 + ci, colour.morph)
        let t = effectiveT(colourMorph: morph, master: master, alt: cell.alt)
        var arpBeats = effectiveRateBeats(colour, t: t)
        let gate = effectiveGate(colour, t: t)
        let octaves = effectiveOctaves(colour, t: t)
        let transpose = Int(over(2 + ci, Double(colour.transpose)).rounded())
        if arpBeats <= 0 { arpBeats = 0.25 }
        diag.effMorphGold = t; diag.effRateBeats = arpBeats

        // Bus: lowest lit letter for now (fan-out across all lit buses lands at commit 6).
        // No lit letter = no-destination (§2.4): truncate any tail, emit nothing.
        guard cell.busMask != 0 else { allNotesOff(atSample: windowStart, out: out); return }
        let cable = UInt8(cell.busMask.trailingZeroBitCount)

        // ---- derived ticks in MUSICAL beat space; delivery unwarped to real ----
        let windowBeats = Double(frameCount) * beatsPerSample
        let mStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let firstTick = Int64((mStart / arpBeats).rounded(.up))
        let lastTick = Int64((mEnd / arpBeats).rounded(.down))
        guard firstTick <= lastTick else { return }
        let span = pool.count * octaves

        for tick in firstTick...lastTick {
            let mTickBeat = Double(tick) * arpBeats
            // A tick that has already crossed into the next column is handled in that column's own
            // window — do NOT consume it here (leave lastTickIndex so the next window fires it).
            let tickCol = ((Int((mTickBeat / S).rounded(.down)) % Snap.cols) + Snap.cols) % Snap.cols
            if tickCol != effColumn { continue }
            if tick == lastTickIndex { continue }
            lastTickIndex = tick

            let realTickBeat = realOf(mTickBeat, stepBeats: S, a: a)
            let onOffset = max(0, (realTickBeat - beatPos) / beatsPerSample)
            let onTime = windowStart + AUEventSampleTime(onOffset)

            let step = Int(tick % Int64(span))
            let base = Int(pool.sorted[step % pool.count])
            let raised = base + 12 * (step / pool.count)
            let noteValue = raised + transpose
            guard noteValue >= 0 && noteValue <= 127 else { continue }

            // OUT CH stamp (§2.6): INHERIT (0) → the source note's original channel; else n → n−1.
            let outCh: UInt8 = colour.outChannel == 0 ? pool.channel(of: base) : colour.outChannel - 1

            // Gate-off, truncated at the column boundary (§7 Tails), as an absolute sample.
            let colEndMusical = (mTickBeat / S).rounded(.down) * S + S
            let mOffBeat = min(mTickBeat + arpBeats * gate, colEndMusical)
            let realOff = realOf(mOffBeat, stepBeats: S, a: a)
            let offOffset = max(0, (realOff - beatPos) / beatsPerSample)
            let offSample = windowStart + AUEventSampleTime(offOffset)

            let slot = openVoice(note: UInt8(noteValue), chan: outCh, cable: cable,
                                 onSample: onTime, offSample: offSample, out: out)
            diag.emitCount &+= 1
            diag.lastEmitNote = UInt8(noteValue)
            diag.lastEmitChan = outCh
            diag.lastEmitInherit = (colour.outChannel == 0)

            // Within-window gate-off: emit in-loop so wire events stay in ascending sample order.
            if slot >= 0 && offSample <= windowEnd { closeVoice(slot, atSample: offSample, out: out) }
        }
        diag.activeVoiceCount = activeVoiceCount()
    }
}

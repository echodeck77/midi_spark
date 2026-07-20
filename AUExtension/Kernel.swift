//  Kernel.swift
//  MidiSpark — render kernel, snapshot-driven, with render-side parameter events + diagnostics.
//  New in this revision:
//   · Handles AURenderEvent .parameter / .parameterRamp — the render-thread route hosts use
//     for automation & MIDI-mapped controls. Values land in a fixed override table; a fresh
//     snapshot generation (a real document edit) clears overrides so the two routes agree.
//   · CC/PB/AT pass through on cable A ALWAYS, playing or stopped (§2.6). Notes pass only
//     when stopped, as before.
//   · Diag struct: live counters/values the UI polls (benign torn reads; diagnostics only).

import Foundation
import AudioToolbox
import AVFoundation

struct KernelDiag {
    var renderCount: UInt64 = 0
    var playing = false
    var beat: Double = 0
    var tempo: Double = 0
    var poolCount = 0
    var snapshotGen: UInt64 = 0
    var paramEventCount: UInt64 = 0
    var lastParamAddr: Int64 = -1
    var lastParamValue: Double = 0
    var ccCount: UInt64 = 0
    var ccStatus: UInt8 = 0, ccData1: UInt8 = 0, ccData2: UInt8 = 0
    var effMorphGold: Double = 0
    var effRateBeats: Double = 0
    var effSwing: Double = 50
    var emitCount: UInt64 = 0
    var lastEmitNote: UInt8 = 0
    var lastEmitChan: UInt8 = 0        // 0-based wire channel; panel shows +1 (human numbering)
    var lastEmitInherit = true         // stamped from source channel (INHERIT) vs Colour OUT CH
    var effColumn = 0                  // active grid column (0…7), derived (§7)
    var pass: Int = 0                  // how many full 8-column cycles elapsed
    var activeCellRow = -1             // row of the sounding cell in effColumn, -1 = column empty
}

final class Kernel {
    var midiOut: AUMIDIOutputEventBlock?
    var musicalContext: AUHostMusicalContextBlock?
    var transportState: AUHostTransportStateBlock?
    var sampleRate: Double = 44_100
    var store: SnapshotStore?
    private(set) var diag = KernelDiag()

    // Held-note pool (the source, §2.5): omni, fixed capacity. Keyed by note number — all input
    // channels merge (§2.5) — with the originating channel remembered per note for INHERIT
    // stamping (§2.6). poolChan[n] is meaningful only while pool[n] != 0.
    private var pool = [UInt8](repeating: 0, count: 128)      // velocity by note (0 = not held)
    private var poolChan = [UInt8](repeating: 0, count: 128)  // originating channel by note
    private var poolSorted = [UInt8](repeating: 0, count: 128)
    private var poolCount = 0

    // Miniature note tracker (§7), still mono (one arp voice) until the refcount lands at commit 6.
    // The off must carry the channel AND cable the on used, so we remember both. The gate-off is
    // scheduled as an ABSOLUTE sample time and drained every render — so an off that falls beyond
    // the current window (a note entering a silent column) is never dropped (no stuck note).
    private var soundingNote: Int = -1
    private var soundingChannel: UInt8 = 0
    private var soundingCable: UInt8 = 0
    private var soundingOffSample: AUEventSampleTime = .max   // .max = nothing scheduled
    private var wasPlaying = false
    private var lastTickIndex: Int64 = -1
    private var prevEffColumn = -1   // column-transition edge detector (§7): change ⇒ truncate voice

    // ---- render-side parameter overrides -------------------------------------------------
    // Slots: 0 stepRate · 1 swing · 2+i transpose(i) · 18+i morph(i) · 34 morphMaster
    private var overrides = [Double](repeating: .nan, count: 35)
    private var overrideGen: UInt64 = .max

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

    func reset() {
        pool = [UInt8](repeating: 0, count: 128)
        poolChan = [UInt8](repeating: 0, count: 128)
        poolCount = 0
        closeVoice(atSample: AUEventSampleTimeImmediate)
        wasPlaying = false
        lastTickIndex = -1
        prevEffColumn = -1
        overrides = [Double](repeating: .nan, count: 35)
        overrideGen = .max
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

    // MARK: - render

    func render(timestamp: UnsafePointer<AudioTimeStamp>,
                frameCount: AUAudioFrameCount,
                events: UnsafePointer<AURenderEvent>?) {

        guard let box = store?.acquire() else { return }
        diag.renderCount &+= 1
        diag.snapshotGen = box.generation

        // A real document edit published a fresh snapshot → it is the new truth; drop overrides.
        if box.generation != overrideGen {
            for i in overrides.indices { overrides[i] = .nan }
            overrideGen = box.generation
        }

        // ---- transport & musical context (derived every render) ----
        var playing = false
        var beatPos = 0.0
        var tempo = 120.0
        if let ts = transportState {
            var flags = AUHostTransportStateFlags()
            _ = ts(&flags, nil, nil, nil)
            playing = flags.contains(.moving)
        }
        if let mc = musicalContext {
            var bpm = 0.0, beat = 0.0
            var tsNum = 0.0; var tsDen: Int = 0; var sampleOffset: Int = 0; var measureBeat = 0.0
            if mc(&bpm, &tsNum, &tsDen, &beat, &sampleOffset, &measureBeat) {
                tempo = bpm > 0 ? bpm : 120
                beatPos = beat
            }
        }
        diag.playing = playing; diag.beat = beatPos; diag.tempo = tempo

        // ---- event list: MIDI + parameter events ----
        var ev = events
        while let e = ev {
            let head = e.pointee.head
            switch head.eventType {
            case .MIDI:
                let midi = e.pointee.MIDI
                withUnsafeBytes(of: midi.data) { raw in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    let length = Int(midi.length)
                    if length >= 1 {
                        handleIncoming(bytes: bytes, length: length,
                                       sampleTime: midi.eventSampleTime,
                                       playing: playing)
                    }
                }
            case .parameter, .parameterRamp:
                let pe = e.pointee.parameter
                if let idx = slot(for: pe.parameterAddress) {
                    overrides[idx] = Double(pe.value)
                    diag.paramEventCount &+= 1
                    diag.lastParamAddr = Int64(pe.parameterAddress)
                    diag.lastParamValue = Double(pe.value)
                }
            default:
                break
            }
            ev = UnsafePointer(head.next)
        }

        // ---- window in samples; global (non-cell) timing ----
        let windowStart = AUEventSampleTime(timestamp.pointee.mSampleTime)
        let windowEnd = windowStart + AUEventSampleTime(frameCount)
        let beatsPerSample = tempo / 60.0 / sampleRate
        let swing = min(75, max(50, over(1, box.swing)))
        let a = swing / 50.0
        var S = box.stepBeats
        let srIdx = Int(over(0, -1).rounded())
        if srIdx >= 0 && srIdx < Snap.stepRateBeats.count { S = Snap.stepRateBeats[srIdx] }
        diag.effSwing = swing

        // ---- drain a scheduled gate-off that has come due (survives across renders → no stuck
        //      note when a voice enters a silent column). Runs regardless of transport (§7). ----
        if soundingNote >= 0 && soundingOffSample <= windowEnd {
            closeVoice(atSample: max(soundingOffSample, windowStart))
        }

        // ---- transport edges: all-notes-off (§7) ----
        if wasPlaying != playing {
            closeVoice(atSample: AUEventSampleTimeImmediate)
            lastTickIndex = -1
            prevEffColumn = -1
            wasPlaying = playing
        }

        rebuildSorted()
        diag.poolCount = poolCount

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

        guard playing, let out = midiOut else { return }

        // ---- column transition (§7): the active column changed → truncate the sounding voice at
        //      the boundary (truncate-at-boundary tails). A relocation/loop is the same edge. ----
        if effColumn != prevEffColumn {
            if soundingNote >= 0 {
                let boundaryMusical = (mNow / S).rounded(.down) * S     // start of effColumn
                let realB = realOf(boundaryMusical, stepBeats: S, a: a)
                let off = max(0, (realB - beatPos) / beatsPerSample)
                closeVoice(atSample: windowStart + AUEventSampleTime(off))
            }
            prevEffColumn = effColumn
            lastTickIndex = -1
        }

        guard poolCount > 0, let cell = active?.cell else { return }   // rest column / no held notes

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
        guard cell.busMask != 0 else { closeVoice(atSample: windowStart); return }
        let cable = UInt8(cell.busMask.trailingZeroBitCount)

        // ---- derived ticks in MUSICAL beat space; delivery unwarped to real ----
        let windowBeats = Double(frameCount) * beatsPerSample
        let mStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let firstTick = Int64((mStart / arpBeats).rounded(.up))
        let lastTick = Int64((mEnd / arpBeats).rounded(.down))
        guard firstTick <= lastTick else { return }
        let span = poolCount * octaves

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

            closeVoice(atSample: onTime)   // mono: close the prior note before the next on

            let step = Int(tick % Int64(span))
            let base = Int(poolSorted[step % poolCount])
            let raised = base + 12 * (step / poolCount)
            let noteValue = raised + transpose
            guard noteValue >= 0 && noteValue <= 127 else { continue }

            // OUT CH stamp (§2.6): INHERIT (0) → the source note's original channel; else n → n−1.
            // This is exactly the expression the router reuses per emitted entry (router-design §6).
            let outCh: UInt8 = colour.outChannel == 0 ? poolChan[base] : colour.outChannel - 1
            var on: [UInt8] = [0x90 | outCh, UInt8(noteValue), 96]
            _ = out(onTime, cable, 3, &on)
            soundingNote = noteValue
            soundingChannel = outCh
            soundingCable = cable
            diag.emitCount &+= 1
            diag.lastEmitNote = UInt8(noteValue)
            diag.lastEmitChan = outCh
            diag.lastEmitInherit = (colour.outChannel == 0)

            // Gate-off, truncated at the column boundary (§7 Tails). Scheduled as an absolute sample:
            // emitted now if it lands in this window, otherwise drained by a later render.
            let colEndMusical = (mTickBeat / S).rounded(.down) * S + S
            let mOffBeat = min(mTickBeat + arpBeats * gate, colEndMusical)
            let realOff = realOf(mOffBeat, stepBeats: S, a: a)
            let offOffset = max(0, (realOff - beatPos) / beatsPerSample)
            soundingOffSample = windowStart + AUEventSampleTime(offOffset)
            if soundingOffSample <= windowEnd { closeVoice(atSample: soundingOffSample) }
        }
    }

    // MARK: - helpers

    private func handleIncoming(bytes: UnsafeBufferPointer<UInt8>, length: Int,
                                sampleTime: AUEventSampleTime, playing: Bool) {
        let status = bytes[0] & 0xF0
        let isNote = (status == 0x90 || status == 0x80)
        let channel = bytes[0] & 0x0F
        if status == 0x90, length >= 3 {
            let vel = bytes[2]
            if vel > 0 {
                if pool[Int(bytes[1])] == 0 { poolCount += 1 }
                pool[Int(bytes[1])] = vel
                poolChan[Int(bytes[1])] = channel        // remember for INHERIT (§2.6)
            }
            else { if pool[Int(bytes[1])] != 0 { poolCount -= 1 }; pool[Int(bytes[1])] = 0 }
        } else if status == 0x80, length >= 3 {
            if pool[Int(bytes[1])] != 0 { poolCount -= 1 }
            pool[Int(bytes[1])] = 0
        }
        if !isNote {
            diag.ccCount &+= 1
            diag.ccStatus = bytes[0]
            diag.ccData1 = length > 1 ? bytes[1] : 0
            diag.ccData2 = length > 2 ? bytes[2] : 0
        }
        // §2.6: CC/PB/AT pass through on cable A always; notes pass only when stopped.
        let shouldForward = isNote ? !playing : true
        if shouldForward, let out = midiOut {
            var copy: [UInt8] = [0, 0, 0]
            for i in 0..<min(length, 3) { copy[i] = bytes[i] }
            _ = out(sampleTime, 0, min(length, 3), &copy)
        }
    }

    private func rebuildSorted() {
        var n = 0
        for note in 0..<128 where pool[note] != 0 { poolSorted[n] = UInt8(note); n += 1 }
        poolCount = n
    }

    /// Close the mono voice: emit its note-off on the SAME channel and cable the on used, then
    /// clear the voice and its scheduled gate-off. Idempotent — safe to call with nothing sounding.
    private func closeVoice(atSample time: AUEventSampleTime) {
        guard soundingNote >= 0, let out = midiOut else {
            soundingNote = -1; soundingOffSample = .max; return
        }
        var off: [UInt8] = [0x80 | soundingChannel, UInt8(soundingNote), 0]
        _ = out(time, soundingCable, 3, &off)
        soundingNote = -1
        soundingOffSample = .max
    }
}

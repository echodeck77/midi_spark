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

    // Miniature note tracker (§7). The off must carry the channel the on used, so we remember it.
    private var soundingNote: Int = -1
    private var soundingChannel: UInt8 = 0
    private var wasPlaying = false
    private var lastTickIndex: Int64 = -1

    private let demoColour = 0   // gold drives the demo arp until the router (step 3)

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
        flushSounding(atSample: AUEventSampleTimeImmediate)
        wasPlaying = false
        lastTickIndex = -1
        overrides = [Double](repeating: .nan, count: 35)
        overrideGen = .max
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

        // ---- transport edges: all-notes-off (§7) ----
        if wasPlaying != playing {
            flushSounding(atSample: AUEventSampleTimeImmediate)
            lastTickIndex = -1
            wasPlaying = playing
        }

        // ---- effective params: snapshot + render-side overrides (§3.2 / §13.5) ----
        let colour = box.colours[demoColour]
        let master = over(34, box.morphMaster)
        let morphGold = over(18 + demoColour, colour.morph)
        // alt: false — the demo arp is not a real cell, so it has no alt bit. The router (step 3)
        // passes each cell's own bit here; this call site disappears with the demo arp.
        let t = effectiveT(colourMorph: morphGold, master: master, alt: false)
        var arpBeats = effectiveRateBeats(colour, t: t)
        let gate = effectiveGate(colour, t: t)
        let octaves = effectiveOctaves(colour, t: t)
        let transpose = Int(over(2 + demoColour, Double(colour.transpose)).rounded())
        let swing = min(75, max(50, over(1, box.swing)))
        let a = swing / 50.0
        var S = box.stepBeats
        let srIdx = Int(over(0, -1).rounded())
        if srIdx >= 0 && srIdx < Snap.stepRateBeats.count { S = Snap.stepRateBeats[srIdx] }
        if arpBeats <= 0 { arpBeats = 0.25 }
        diag.effMorphGold = t; diag.effRateBeats = arpBeats; diag.effSwing = swing

        guard playing, poolCount > 0, let out = midiOut else { diag.poolCount = poolCount; return }

        // ---- derived ticks in MUSICAL beat space; delivery unwarped to real ----
        let beatsPerSample = tempo / 60.0 / sampleRate
        let windowBeats = Double(frameCount) * beatsPerSample
        let mStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let firstTick = Int64((mStart / arpBeats).rounded(.up))
        let lastTick = Int64((mEnd / arpBeats).rounded(.down))
        rebuildSorted()
        diag.poolCount = poolCount
        guard firstTick <= lastTick, poolCount > 0 else { return }
        let span = poolCount * octaves

        for tick in firstTick...lastTick {
            if tick == lastTickIndex { continue }
            lastTickIndex = tick
            let mTickBeat = Double(tick) * arpBeats
            let realTickBeat = realOf(mTickBeat, stepBeats: S, a: a)
            let onOffset = max(0, (realTickBeat - beatPos) / beatsPerSample)
            let onTime = AUEventSampleTime(timestamp.pointee.mSampleTime) + AUEventSampleTime(onOffset)

            flushSounding(atSample: onTime)

            let step = Int(tick % Int64(span))
            let base = Int(poolSorted[step % poolCount])
            let raised = base + 12 * (step / poolCount)
            let noteValue = raised + transpose
            guard noteValue >= 0 && noteValue <= 127 else { continue }

            // OUT CH stamp (§2.6): INHERIT (0) → the source note's original channel; else n → n−1.
            // This is exactly the expression the router reuses per emitted entry (router-design §6).
            let outCh: UInt8 = colour.outChannel == 0 ? poolChan[base] : colour.outChannel - 1
            var on: [UInt8] = [0x90 | outCh, UInt8(noteValue), 96]
            _ = out(onTime, 0, 3, &on)
            soundingNote = noteValue
            soundingChannel = outCh
            diag.emitCount &+= 1
            diag.lastEmitNote = UInt8(noteValue)
            diag.lastEmitChan = outCh
            diag.lastEmitInherit = (colour.outChannel == 0)

            let mOffBeat = mTickBeat + arpBeats * gate
            if mOffBeat < mEnd {
                let realOff = realOf(mOffBeat, stepBeats: S, a: a)
                let offOffset = max(0, (realOff - beatPos) / beatsPerSample)
                let offTime = AUEventSampleTime(timestamp.pointee.mSampleTime) + AUEventSampleTime(offOffset)
                flushSounding(atSample: offTime)
            }
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

    private func flushSounding(atSample time: AUEventSampleTime) {
        guard soundingNote >= 0, let out = midiOut else { soundingNote = -1; return }
        var off: [UInt8] = [0x80 | soundingChannel, UInt8(soundingNote), 0]   // pair on the on's channel
        _ = out(time, 0, 3, &off)
        soundingNote = -1
    }
}

//  Kernel.swift
//  MidiSpark — render kernel, snapshot-driven (build-order step 2; spec v2.8 §4/§7).
//  Behaviour vs step 1: identical shape (passthrough stopped / UP arp playing on cable A),
//  but rate, gate, octave count, morph(+MASTER), step size, and SWING now come from the
//  atomically-published snapshot. Automate "Morph Gold" or "Swing" in the host and hear it.
//  The playhead remains DERIVED, never accumulated; swing is a phase WARP on the derived
//  beat (§4 v2.3), so the no-accumulation guarantee survives by construction.

import Foundation
import AudioToolbox
import AVFoundation

final class Kernel {
    // Captured at allocateRenderResources.
    var midiOut: AUMIDIOutputEventBlock?
    var musicalContext: AUHostMusicalContextBlock?
    var transportState: AUHostTransportStateBlock?
    var sampleRate: Double = 44_100
    var store: SnapshotStore?

    // Held-note pool (the source, §2.5): omni, fixed capacity.
    private var pool = [UInt8](repeating: 0, count: 128)
    private var poolSorted = [UInt8](repeating: 0, count: 128)
    private var poolCount = 0

    // Miniature note tracker (§7): one arp voice for now.
    private var soundingNote: Int = -1
    private var wasPlaying = false
    private var lastTickIndex: Int64 = -1

    // The colour driving the demo arp until the router (step 3) exists: gold = index 0.
    private let demoColour = 0

    func reset() {
        pool = [UInt8](repeating: 0, count: 128)
        poolCount = 0
        flushSounding(atSample: AUEventSampleTimeImmediate)
        wasPlaying = false
        lastTickIndex = -1
    }

    // MARK: - Swing warp (§4 v2.3): real beat ⇄ musical beat, pairwise MPC-style at step level.
    //   a = swing/50 ∈ [1, 1.5]; within each 2-step pair the first step stretches to a·S,
    //   the second shrinks to (2−a)·S. Identity at swing = 50 by construction.

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

        // ---- incoming MIDI: pool + passthrough-when-stopped ----
        var ev = events
        while let e = ev {
            let head = e.pointee.head
            if head.eventType == .MIDI {
                let midi = e.pointee.MIDI
                withUnsafeBytes(of: midi.data) { raw in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    let length = Int(midi.length)
                    if length >= 1 {
                        handleIncoming(bytes: bytes, length: length,
                                       sampleTime: midi.eventSampleTime,
                                       passthrough: !playing)
                    }
                }
            }
            ev = UnsafePointer(head.next)
        }

        // ---- transport edges: all-notes-off (§7) ----
        if wasPlaying != playing {
            flushSounding(atSample: AUEventSampleTimeImmediate)
            lastTickIndex = -1
            wasPlaying = playing
        }
        guard playing, poolCount > 0, let out = midiOut else { return }

        // ---- effective params from the snapshot (§3.2 / §13.5) ----
        let colour = box.colours[demoColour]
        let t = effectiveMorph(colour.morph, master: box.morphMaster)
        let arpBeats = effectiveRateBeats(colour, t: t)
        let gate = effectiveGate(colour, t: t)
        let octaves = effectiveOctaves(colour, t: t)
        let a = box.swing / 50.0
        let S = box.stepBeats

        // ---- derived arp ticks, in MUSICAL beat space; delivery times unwarped back to real ----
        let beatsPerSample = tempo / 60.0 / sampleRate
        let windowBeats = Double(frameCount) * beatsPerSample
        let mStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let firstTick = Int64((mStart / arpBeats).rounded(.up))
        let lastTick = Int64((mEnd / arpBeats).rounded(.down))
        guard firstTick <= lastTick else { return }

        rebuildSorted()
        guard poolCount > 0 else { return }
        let span = poolCount * octaves

        for tick in firstTick...lastTick {
            if tick == lastTickIndex { continue }
            lastTickIndex = tick
            let mTickBeat = Double(tick) * arpBeats
            let realTickBeat = realOf(mTickBeat, stepBeats: S, a: a)
            let onOffset = max(0, (realTickBeat - beatPos) / beatsPerSample)
            let onTime = AUEventSampleTime(timestamp.pointee.mSampleTime) + AUEventSampleTime(onOffset)

            flushSounding(atSample: onTime)

            // UP over octaves: index derived from tick, never accumulated (§1.1 clause 4)
            let step = Int(tick % Int64(span))
            let base = Int(poolSorted[step % poolCount])
            let raised = base + 12 * (step / poolCount)
            let noteValue = raised + Int(colour.transpose)
            guard noteValue >= 0 && noteValue <= 127 else { continue }   // clamp policy (§2.6) — skip out-of-range
            var on: [UInt8] = [0x90, UInt8(noteValue), 96]
            _ = out(onTime, 0 /* cable A */, 3, &on)
            soundingNote = noteValue

            // gate-off inside this window if it lands here; next tick's flush catches the rest
            let mOffBeat = mTickBeat + arpBeats * gate
            if mOffBeat < mEnd {
                let realOff = realOf(mOffBeat, stepBeats: S, a: a)
                let offOffset = max(0, (realOff - beatPos) / beatsPerSample)
                let offTime = AUEventSampleTime(timestamp.pointee.mSampleTime) + AUEventSampleTime(offOffset)
                flushSounding(atSample: offTime)
            }
        }
    }

    // MARK: - helpers (fixed-size storage; no allocation intent on the hot path)

    private func handleIncoming(bytes: UnsafeBufferPointer<UInt8>, length: Int,
                                sampleTime: AUEventSampleTime, passthrough: Bool) {
        let status = bytes[0] & 0xF0
        if status == 0x90, length >= 3 {
            let vel = bytes[2]
            if vel > 0 { if pool[Int(bytes[1])] == 0 { poolCount += 1 }; pool[Int(bytes[1])] = vel }
            else { if pool[Int(bytes[1])] != 0 { poolCount -= 1 }; pool[Int(bytes[1])] = 0 }
        } else if status == 0x80, length >= 3 {
            if pool[Int(bytes[1])] != 0 { poolCount -= 1 }
            pool[Int(bytes[1])] = 0
        }
        if passthrough, let out = midiOut {
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
        var off: [UInt8] = [0x80, UInt8(soundingNote), 0]
        _ = out(time, 0, 3, &off)
        soundingNote = -1
    }
}

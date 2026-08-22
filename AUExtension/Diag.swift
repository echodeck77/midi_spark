//  Diag.swift
//  MidiSpark — render-side diagnostics counters, threaded `inout` through the render pass.
//
//  Pure (Foundation-only): moved out of Kernel.swift so Router — which takes `inout KernelDiag` —
//  compiles into the macOS unit-test target without dragging AudioToolbox along. Kernel produces it,
//  Router populates it; the UI reads a copy. Not on any allocation-sensitive boundary — plain values.

import Foundation

struct KernelDiag {
    var renderCount: UInt64 = 0
    var reelState: Int = 0            // THE REEL-TO-REEL: 0 off · 1 armed · 2 replaying (Paul 2026-08-18)
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
    var floodDropped = 0               // FLOOD GOVERNOR: note-ons dropped this session (the cog HEALTH tell)
    var lastEmitNote: UInt8 = 0
    var lastEmitChan: UInt8 = 0        // 0-based wire channel (bus stamp); panel shows +1 (human)
    var effColumn = 0                  // active grid column (0…7), derived (§7)
    var absoluteStep = 0               // global step counter — +1 each step, INCLUDING during a column LAP (LADDER arm commit)
    var routedPath = false             // CHAOS oracle: ≥1 occupied, audible cell admits a held note AND has an enabled emitter
                                       // (a STRUCTURAL "should something sound?" — silence with no routed path is EXPECTED, not a bug)
    var pass: Int = 0                  // how many full 8-column cycles elapsed
    var activeCellRow = -1             // row of the sounding cell in effColumn, -1 = column empty
    var activeCellParent: Int8 = -1    // v3.0 resolvedParent of the active cell (−1 = MIDI IN)
    var activeVoiceCount = 0           // instances in the poly voice table (per bus × ch × note)
    var distinctSounding = 0           // distinct (bus,ch,note) on the wire; < voices when notes collide
    // a8 hang detection (2026-07-25): the ASSERT-ON-SILENCE net. `passthroughHeld` = raw notes echoed &
    // awaiting their off; `silenceViolated` = voices/echoes lingered in the provably-silent state (stopped,
    // no held input, no audition) = a stuck note; `panics` counts the self-heal all-notes-off that cleared it.
    var passthroughHeld = 0
    var silenceViolated = false
    var panics: UInt64 = 0
    // DOOR REPLAY diagnostic (2026-08-22): localize "loop animates but silent" — engaged mask → captured loop size →
    // frozen-pool size. engaged=0 ⇒ never engaged · loopN=0 ⇒ recording/capture empty · loopN>0 & poolN=0 ⇒ the
    // notesSoundingAt/fill isn't reaching the pool · poolN>0 & still silent ⇒ no grid cell reads the door (or emit gate).
    var replayEngaged: UInt8 = 0       // which REPLAY doors are looping (bit i)
    var replayLoopN = 0                // events in the ENGAGED door's captured loop (0 = nothing captured)
    var replayPoolN = 0                // notes the engaged door's loop currently feeds into the frozen pool
}

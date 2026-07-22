//  Diag.swift
//  MidiSpark — render-side diagnostics counters, threaded `inout` through the render pass.
//
//  Pure (Foundation-only): moved out of Kernel.swift so Router — which takes `inout KernelDiag` —
//  compiles into the macOS unit-test target without dragging AudioToolbox along. Kernel produces it,
//  Router populates it; the UI reads a copy. Not on any allocation-sensitive boundary — plain values.

import Foundation

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
    var lastEmitChan: UInt8 = 0        // 0-based wire channel (bus stamp); panel shows +1 (human)
    var effColumn = 0                  // active grid column (0…7), derived (§7)
    var pass: Int = 0                  // how many full 8-column cycles elapsed
    var activeCellRow = -1             // row of the sounding cell in effColumn, -1 = column empty
    var activeCellParent: Int8 = -1    // v3.0 resolvedParent of the active cell (−1 = MIDI IN)
    var activeVoiceCount = 0           // instances in the poly voice table (per bus × ch × note)
    var distinctSounding = 0           // distinct (bus,ch,note) on the wire; < voices when notes collide
}

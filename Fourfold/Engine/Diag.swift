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
    var playing = false               // the HOST transport flag (raw)
    var effectivePlaying = false      // host OR free-run actually advancing the beat — the UI's "is anything really playing" tell (Paul 2026-09-04)
    var beat: Double = 0
    var tempo: Double = 0
    var beatsPerBar: Double = 4       // the host's real bar length in quarter-note beats (Kernel reads tsNum/tsDen) — the page's walk tags need it to date the LANES-sequencer step / per-lane RESET
    // HOST BEAT-REFERENCE CROSS-CHECK (2026-10-18, the "odd timing" investigation). The musical-context
    // block hands us `currentBeatPosition` AND `sampleOffsetToNextBeat`; the second is the host's own
    // statement of how many samples remain until the next whole beat, so it independently verifies the
    // first. If `beat`'s fractional part is honest, the two must agree:
    //     expected offset = (1 − frac(beat)) × samplesPerBeat
    // `beatRefErrorSamples` is (reported − expected), i.e. how wrong the host's beat position is in
    // samples; `beatRefFrames` is the block size that error should be compared against. A value that is
    // small (a few samples) means `beat` is trustworthy and every onset computed from it is correctly
    // placed. A value near ±one block would mean `beat` is itself block-quantised, which would put the
    // timing fault INSIDE the plugin rather than downstream of it. Read-only arithmetic over values the
    // render already fetches — no extra host calls, no render-thread logging (see the 2026-09 os_log
    // hazard). Exposed because `Kernel.render`'s context plumbing is the one seam `RouterTests` cannot
    // reach off-device (it is AudioToolbox), so this is the only way to inspect it on a release build.
    var beatRefErrorSamples: Double = 0
    var beatRefFrames: Int = 0
    var beatRefValid = false          // false ⇒ the host supplied no usable sampleOffsetToNextBeat, so the check says nothing
    var poolCount = 0
    var snapshotGen: UInt64 = 0
    var paramEventCount: UInt64 = 0
    var lastParamAddr: Int64 = -1
    var lastParamValue: Double = 0
    var ccCount: UInt64 = 0
    var ccStatus: UInt8 = 0, ccData1: UInt8 = 0, ccData2: UInt8 = 0
    var effSwing: Double = 50
    var emitCount: UInt64 = 0
    var floodDropped = 0               // FLOOD GOVERNOR: note-ons dropped this session (the cog HEALTH tell)
    var lastEmitNote: UInt8 = 0
    var lastEmitChan: UInt8 = 0        // 0-based wire channel (bus stamp); panel shows +1 (human)
    var effColumn = 0                  // active grid column (0…7), derived (§7)
    var absoluteStep = 0               // global step counter — +1 each step, INCLUDING during a column LAP (LADDER arm commit)
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
    // The last heal's context, captured on the render thread as PLAIN NUMBERS so the main-thread poll can build the
    // human log line + os_log it OFF the audio thread (edge-triggered on `panics`). The render thread must NOT build
    // a String or os_log — a persistent violation would then alloc+log every audio block = crackle / DSP overload
    // (Paul 2026-09-12). Reason: 0 none · 1 silence invariant violated (stopped, hard) · 2 playing silence leak (soft).
    var stuckReason: Int32 = 0
    var stuckVoices = 0                // router voices active at the last heal (captured before the flush cleared them)
    var stuckEchoes = 0                // passthrough echoes stranded at the last heal
    // DOOR REPLAY diagnostic (2026-08-22): localize "loop animates but silent" — engaged mask → captured loop size →
    // frozen-pool size. engaged=0 ⇒ never engaged · loopN=0 ⇒ recording/capture empty · loopN>0 & poolN=0 ⇒ the
    // notesSoundingAt/fill isn't reaching the pool · poolN>0 & still silent ⇒ no grid cell reads the door (or emit gate).
    // HOLD BISECT (Paul 2026-08-31): while any door latch is armed, per armed door — the LIVE admitted note count and the
    // FROZEN (held) note count. If a new chord doesn't update FRZ, the live→frozen HOLD capture is the fault; if LIVE never
    // shows the new chord, the input isn't reaching the door (channel/cable/range). Shown in cog HEALTH while armed.
}

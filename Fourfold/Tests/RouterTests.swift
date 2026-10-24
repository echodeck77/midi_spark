//  RouterTests.swift
//  Off-device tests of the RENDER ENGINE itself — newly possible now that Router emits through the
//  Foundation-only MIDIEmitter seam (Emission.swift) instead of AUMIDIOutputEventBlock. A recording
//  emitter captures the exact (sample, cable, status, note, vel) wire stream, so invariants that used
//  to be ear-only on device — no stuck notes, the two-cable §7b rule, bus-channel stamping, muted
//  silence — become assertions that run in milliseconds. These are contract tests, deliberately
//  independent of exact sample arithmetic (which swing/window math makes brittle).

import XCTest

/// Records every emitted message. `status` is the masked channel-voice status (0x90 on / 0x80 off);
/// `chan` is the low nibble already stamped by the engine.
private final class RecordingEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let chan: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, chan: b0 & 0x0F, note: b1, vel: b2))
    }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
    var offs: [Ev] { events.filter { $0.status == 0x80 } }
}

final class RouterTests: XCTestCase {

    // MARK: setup helpers

    /// A one-scene document with the given machines + cell layout, then its resolved SnapshotBox.
    private func box(machines cs: [Machine], busChannels: [Int] = [1, 2, 3, 4], masterMute: Bool = false,
                     receivers: [Receiver]? = nil,
                     _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(machines: cs, scenes: [s]); st.busChannels = busChannels; st.masterMute = masterMute
        if let receivers { st.receivers = receivers }
        return SnapshotBuilder.build(from: st)
    }

    private func chord(_ notes: [UInt8], channel: UInt8 = 0) -> NotePool {
        let p = NotePool(); for n in notes { p.noteOn(n, velocity: 100, channel: channel) }; return p
    }
    /// A held chord with per-note velocities — for the velocity-inheritance tests (user 2026-08-09).
    private func velChord(_ pairs: [(UInt8, UInt8)], channel: UInt8 = 0) -> NotePool {
        let p = NotePool(); for (n, v) in pairs { p.noteOn(n, velocity: v, channel: channel) }; return p
    }

    /// Drive the render engine across `beats` musical beats of PLAYING windows, then one STOP window
    /// (the transport edge flushes every voice). Mirrors how the Kernel calls it each render.
    private func run(_ box: SnapshotBox, _ pool: NotePool, beats: Double, into emitter: RecordingEmitter,
                     laneMask: UInt16 = 0, releaseAtEnd: Bool = true,
                     forceColumn: Int = -1,   // PLAY: THIS CELL (−1 = normal, unaffected) — bypasses the column-lap gate so a bare cell keeps ticking as real time advances past its own grid column's real-time span
                     tempo: Double = 120, sr: Double = 48_000, frames: UInt32 = 2048) {
        let router = Router()
        var diag = KernelDiag()
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: forceColumn,
                           laneMask: laneMask, out: emitter, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        if releaseAtEnd {   // release the lap (laneMask 0) then stop — must return to the true timeline, no stuck notes
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0,
                           out: emitter, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo,   // stop edge → flush
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: emitter, diag: &diag)
    }

    /// RESTART CHAINS (ferry 2026-10-19): simulates `AudioUnitViewController`'s main-thread resync-loop migration
    /// step (§12.2) for a Router-level unit test that constructs an `EuclidLine` directly and never runs the AVC
    /// itself — pins the lane's resolved restart chains from whatever pre-chain fields it still carries (grid
    /// masks, `resetSteps`, `riffLock`), so it plays exactly as production would after the real migration tick,
    /// rather than the render path's own safe-but-unmigrated FREE/FREE default (`Router.swift`'s own disclosed
    /// pre-migration fallback). `legacyRate`/`legacyLen` are the OLD LANES-sequencer fields a test may also set on
    /// its `PluginState` (`st.euclideousLanesSeqRate`/`Len`); `barBeats` matches `run`/`mixRun`'s own un-passed
    /// `beatsPerBar` default (4.0, common time) unless a test explicitly set a different one.
    private func migratedLine(_ line: EuclidLine, lane: Int = 0, legacyRate: EuclideousSeqRate = .oneBar, legacyLen: Int = 8,
                              barBeats: Double = 4) -> EuclidLine {
        var l = line
        let n = max(2, min(16, l.steps))
        let sub = l.rate?.beats ?? 0.5
        let migrated = migrateRestartChains(line: l, lane: lane, legacyOn: false, legacyRate: legacyRate, legacyLen: legacyLen,
                                            legacyCells: [Bool](repeating: true, count: 32), sub: sub, n: n, dir: l.directionResolved, barBeats: barBeats)
        euclideousPinRestartChains(&l, .from(migrated.rhythm), .from(migrated.melody))
        return l
    }
    /// The no-stuck-note contract expressed on the wire: for every (cable, channel, note), the LAST
    /// event emitted must be a note-OFF. Under the collision refcount an OFF only fires when the last
    /// instance releases, so on,on,off is legal — but the sequence must never END on an ON.
    private func assertNothingLeftSounding(_ e: RecordingEmitter, file: StaticString = #filePath, line: UInt = #line) {
        var last: [Int: UInt8] = [:]   // key → last status
        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {   // NOTES only — ignore CC (e.g. panic's CC120/123)
            let key = (Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)
            last[key] = ev.status
        }
        for (key, status) in last where status != 0x80 {
            XCTFail("stuck note: key \(key) last event was ON, not OFF", file: file, line: line)
        }
    }

    private func arpMachines() -> [Machine] { machineIDs.map { Machine(machineID: $0, type: .arp) } }

    /// Like `run()`, but hands back the `Router` instance instead of discarding it — for tests that need to
    /// poll a UI-facing readout (e.g. `euclidLineReadyAt`, NOTE VIEW's own `drainEuclideousNoteViewEvents`)
    /// after rendering, not just inspect the emitted wire stream. Deliberately skips `run()`'s trailing
    /// release/stop-edge calls: those exist to prove no stuck notes at teardown, irrelevant here and an
    /// unnecessary extra edge to reason about for a readout that doesn't depend on transport play/stop state
    /// at all (Paul 2026-10-05, EUCLID beacon readiness). `forceColumn` (Paul 2026-10-10, NOTE VIEW tests)
    /// mirrors `run()`'s own identical parameter — PLAY: THIS CELL, bypassing the column-lap gate so a bare
    /// test cell keeps ticking as real time advances past its own grid column's natural real-time span.
    private func runKeepingRouter(_ box: SnapshotBox, _ pool: NotePool, beats: Double, into emitter: RecordingEmitter,
                                   forceColumn: Int = -1,
                                   tempo: Double = 120, beatsPerBar: Double = 4.0, sr: Double = 48_000, frames: UInt32 = 2048) -> Router {
        let router = Router()
        var diag = KernelDiag()
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, beatsPerBar: beatsPerBar,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: forceColumn,
                           out: emitter, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        return router
    }

    // MARK: tests

    // GENERATORS (user 2026-08-08) — EUCLID · BURST · CASCADE render integration.
    func testEuclidStrikesChordOnEuclideanPulses() {
        // 4-of-8 euclid over a 3-note chord in one column (S = 2 beats): 4 pulses × 3 notes = 12 note-ons, no stuck.
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 12, "4 euclid pulses × the 3-note chord")
        assertNothingLeftSounding(e)
    }
    func testEuclidDownbeatFiresOnAnUnalignedColumnBoundary() {
        // REGRESSION (Paul 2026-08-18): the euclid cell sits in COLUMN 1, whose start (beat S=2) falls MID render-block,
        // not on a block boundary — the case the old window-scan dropped, losing every column's step-0 pulse (K→K−1;
        // K=1 silent). Existing euclid tests hid it by starting the run exactly on column 0's boundary. All 4 pulses
        // (incl. the downbeat at 2.0) must sound: 4 × 3 = 12.
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; return c }) { $0.cells[1][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 4, into: e)   // column 1 is active over [2,4); its downbeat at 2.0 is mid-block
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 12, "the column-1 downbeat must not be dropped (was 9 = K−1 per cycle)")
        assertNothingLeftSounding(e)
    }
    // SPAN RE-ANCHOR (Paul 2026-08-27, RATE×ladder — replaces the old WIDTH model): GRID = the grain, SPAN re-syncs the
    // pattern to step 0 every N columns. A 4-of-8 euclid (hits at steps 0·2·4·6) at ONE step per column (rate == stepRate
    // == 1/8): FREE walks the pattern across the row → columns 0·2·4·6 fire = 4 × 3 notes = 12 onsets; SPAN=1 re-anchors
    // EVERY column to step 0 (always a hit) → all 8 columns fire = 8 × 3 = 24. Proves SPAN re-syncs, not scales speed.
    func testEuclidSpanReAnchorsThePattern() {
        func ons(spanN: Int?) -> Int {
            let b = box(machines: machineIDs.map { id -> Machine in
                guard id == "gold" else { return Machine(machineID: id, type: .arp) }
                var c = Machine(machineID: "gold", type: .euclid)
                c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; c.paramsA.euclidRate = .r1_8; c.paramsA.euclidSpanN = spanN
                return c
            }) { s in
                s.stepRate = .r1_8                                       // 0.5-beat columns == the euclid rate → one step per column
                for col in 0..<8 { s.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }   // the whole row → the pattern plays continuously
            }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 3.9, into: e)   // exactly 8 columns (no pass-2 edge)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertEqual(ons(spanN: nil), 12, "FREE: the 4-of-8 pattern walks the row — hits at steps 0·2·4·6 = 4 columns × 3 notes")
        XCTAssertEqual(ons(spanN: 1), 24, "SPAN=1: re-anchored EVERY column to step 0 (always a hit) → all 8 columns fire × 3 notes")
        XCTAssertGreaterThan(ons(spanN: 1), ons(spanN: nil), "the re-anchor changes the sequenced pattern")
    }
    // PART GRID × GENERATOR interaction bug, ROUND 2 (Paul 2026-10-05): the same hardcoded-8-column defect found
    // in the EUCLID fix above turned out to be systemic — STRIKE PER SPAN, CHORDS-hold, TUTTI PATTERN, LENGTH,
    // STRUM, and MOD all independently hardcoded Double(Snap.cols)*S instead of the row's real pass length. Each
    // test below forces the MULTI-CLOCK path (an explicit, non-default rowStepRate) on a 16-column row and proves
    // the SPAN control now scales with the row's real width.

    // K = N is the OFF state (SPEC-arp-euclid-mask's own convention, carried over unchanged) — byte-identical to the
    // arp alone.
    func testEuclidMaskKEqualsNIsANoOp() {
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 8
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        func ons(_ procs: [ProcessorSlot]) -> [RecordingEmitter.Ev] {
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }
        }
        XCTAssertEqual(ons([arp, mask]), ons([arp]), "K = N is OFF — byte-identical to the arp alone")
    }
    // EUCLID MASK options (Paul 2026-09-28): INVERT/SPAN/PROBABILITY/ACCENT/FILL/CHORD PICK, all additive on the
    // same standalone fold processor.
    // INVERT plays the COMPLEMENT of the base pattern — every tick is either a hit under the normal pattern OR
    // under its invert, never both, and together they cover every tick the arp alone would produce.
    func testEuclidMaskInvertPlaysTheComplementSteps() {
        func onsetTicks(_ invert: Bool?) -> Set<Int64> {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var procs = [arp]
            if let invert { var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 3; mask.params.maskInvert = invert; procs.append(mask) }
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { $0.sample })
        }
        let normal = onsetTicks(false), inverted = onsetTicks(true), all = onsetTicks(nil)
        XCTAssertTrue(normal.isDisjoint(with: inverted), "INVERT plays the COMPLEMENT steps — never the same tick as the non-inverted run")
        XCTAssertEqual(normal.union(inverted), all, "together, a pattern and its invert cover every tick the arp alone would")
    }
    // BOTTOM2/TOP2 must degrade gracefully (one note, not a crash or an out-of-range read) against a single-note
    // "chord" — this is exactly the kind of off-by-one a ClosedRange(lo > hi) would trap on if unguarded.
    func testEuclidMaskChordPickBottomTopTwoCollapseToOneNoteOnASingleHeldNote() {
        func notes(_ pick: MaskChordPick) -> [UInt8] {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 4; mask.params.maskGap = .chord; mask.params.maskChordPick = pick
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { $0.note }
        }
        XCTAssertTrue(notes(.bottom2).allSatisfy { $0 == 60 }, "BOTTOM2 against a single held note is just that one note, no crash")
        XCTAssertTrue(notes(.top2).allSatisfy { $0 == 60 }, "TOP2 against a single held note is just that one note, no crash")
    }
    // Test #4 (composition): two CLOCK stages in one chain must compose IN ORDER — [×2 → ×3] must behave exactly like
    // a single ×6 stage, proving clockTransformedBeat folds multiple CLOCKs correctly through the real fold pipeline
    // (not just the pure function in isolation — DerivationsTests already locks that algebraically).
    func testTwoClockStagesComposeLikeTheirProductRatio() {
        func strikeCount(_ ratios: [Int]) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var procs = [arp]
            for r in ratios { procs.append(drawnClock(ratioIndex: r)) }
            var rat = ProcessorSlot(type: .ratchet); rat.params.rtcMode = .pattern
            rat.params.rtcSteps = 8; rat.params.rtcSlices = [3, 1, 1, 1, 1, 1, 1, 1]; rat.params.ramp = 0
            procs.append(rat)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let two = clockRatioLadder.firstIndex(of: 2)!, three = clockRatioLadder.firstIndex(of: 3)!
        // clockRatioLadder has no literal ×6 rung — compose it via two single-step DRAWN clocks on each side of the
        // comparison instead: [×2→×3] must equal [×3→×2] (multiplication commutes, and both equal the same product).
        XCTAssertEqual(strikeCount([two, three]), strikeCount([three, two]), "two CLOCK stages compose as a product — order between two ratios doesn't matter")
    }
    // CLOCK driver retiming (Paul 2026-09-26, final spec: "a grid with a variable number of steps, each step a
    // mutually exclusive speed, and another row on the same grid for glide" — DRAWN mode's own grid): a CLOCK
    // stage in DRAWN mode BEFORE a driver now genuinely retimes that driver's own tick generation — not just a
    // downstream fold consumer's reading of a beat (Stages 1–3, which stay FIXED/WAVE/DRAWN-agnostic and
    // unaffected). A single-step, all-×N DRAWN lane reduces to the same linear math as FIXED's simple ratio would
    // have (hand-verified algebraically: with one uniform SET column, `clockDrawnPhase` collapses to `ratio×beat`
    // exactly, independent of the lane's own rate/step count), so this exercises the DRAWN wiring with the same
    // shape of assertion the earlier FIXED-only attempt used. Hand-verified via a temporary debug trace before
    // asserting (this session's standing discipline): a bare `[ARP]` cell at column 0 (rate 1/8) fires exactly 4
    // notes in its column's own active window (stable across beats:2/4/8 — the window, not the render length,
    // bounds it). `[CLOCK(drawn ×2)→ARP]` fires exactly 8 notes in the SAME real window (double the local tick
    // density). `[CLOCK(drawn ×1)→ARP]` is byte-identical to no clock (the standing no-op law).
    private func drawnClock(ratioIndex: Int?) -> ProcessorSlot {
        var ck = ProcessorSlot(type: .clock)
        ck.params.clockDrawnSteps = 1   // single-step: rateBeats (now always S) cancels out of the math entirely, so this is a plain ×ratio multiply regardless of the cell's own step
        ck.params.clockDrawnRatios = [ratioIndex ?? clockRatioLadder.firstIndex(of: 1)!]
        ck.params.clockDrawnGlide = [false]
        ck.params.clockSpanN = 0   // FREE — no SPAN re-anchor discontinuity inside these short test windows
        return ck
    }
    // KILL STEP (Paul 2026-09-26, sibling to CLOCK — a discrete on/off step remap rather than a continuous ratio
    // warp): detected alongside `.clock` by the SAME `driverClockBeat`/…Inverse/`clockTransformedBeat` machinery, so
    // it reaches every consumer CLOCK already does with no new call sites — these three tests exercise it through
    // DEST exactly as `testClockTransformsDestsOwnRoutingClock` exercises CLOCK, since DEST's per-step routing is
    // the clearest external witness of "which step landed here."
    private func killStepStage(steps: Int, enabled: [Bool], rate: ArpRate = .r1_8) -> ProcessorSlot {
        var ks = ProcessorSlot(type: .killStep)
        ks.params.killStepCount = steps
        ks.params.killStepEnabled = enabled
        ks.params.killStepRate = rate
        ks.params.killStepSpanN = 0   // FREE — no SPAN re-anchor discontinuity inside these short test windows
        return ks
    }
    // LEGACY MIGRATION (Paul 2026-09-27): an old doc's killStepEnabled (true→ON, false→DROP) must resolve
    // BYTE-IDENTICAL to the same pattern authored directly via the new killStepMode field.
    func testKillStepLegacyEnabledMigratesToOnAndDrop() {
        func onsets(_ configure: (inout ProcessorSlot) -> Void) -> [Int64] {
            var ks = ProcessorSlot(type: .killStep); ks.params.killStepCount = 8; ks.params.killStepRate = .r1_8; ks.params.killStepSpanN = 0
            configure(&ks)
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ks, arp]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 3.9, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { $0.sample }.sorted()
        }
        let legacy = onsets { $0.params.killStepEnabled = [true, true, true, true, false, false, false, false] }
        let modern = onsets { $0.params.killStepMode = [.on, .on, .on, .on, .drop, .drop, .drop, .drop] }
        XCTAssertEqual(legacy, modern, "an old killStepEnabled row and the equivalent new killStepMode row must resolve identically")
    }
    // EUCLID PICK (Paul 2026-08-22): LOW strikes only the pool's lowest note on every hit.
    func testEuclidPickLowStrikesOnlyTheLowestNote() {
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; c.paramsA.euclidPick = .low; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 2, into: e)
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(ons.count, 4, "4 pulses × 1 picked note")
        XCTAssertTrue(ons.allSatisfy { $0.note == 60 }, "PICK LOW strikes only the lowest pool note")
        assertNothingLeftSounding(e)
    }
    // EUCLID INVERT — REMOVED, now a NO-OP (Paul 2026-10-02: "remove the hits button and functionality" — the
    // per-line HITS/REST tap-pill in euclidSettingsPanel drove this). `euclidInvert`/`EuclidLine.invert` both
    // still exist (decode-only — an old doc that had INVERT engaged doesn't factory-reset), but `runEuclidLine`
    // no longer reads either, so a pattern no longer flips to its N−K rests regardless of the stored value.
    // Locked in as a regression guard rather than deleting the test outright — was
    // testEuclidInvertPlaysTheRests, asserting 9 vs 15 ons; now both read 9.
    func testEuclidInvertIsNowANoOp() {
        func count(_ inv: Bool) -> Int {
            let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
                c.paramsA.euclidPulses = 3; c.paramsA.euclidSteps = 8; c.paramsA.euclidInvert = inv; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertEqual(count(false), 9, "3 hits × 3 notes — unaffected by the removal")
        XCTAssertEqual(count(true), 9, "INVERT no longer flips to the N−K rests — same 3 hits, not 15")
    }
    // EUCLID PICK CYCLE (Paul 2026-08-22): the euclid-arp — one note per pulse, walking the chord.
    func testEuclidPickCycleWalksTheChordOneNotePerPulse() {
        func mk(_ pick: EuclidPick) -> (Int, Set<UInt8>) {
            let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
                c.paramsA.euclidPulses = 5; c.paramsA.euclidSteps = 8; c.paramsA.euclidPick = pick; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e)
            assertNothingLeftSounding(e)
            let ons = e.ons.filter { $0.cable == 1 }
            return (ons.count, Set(ons.map { $0.note }))
        }
        let (allC, _) = mk(.all)
        let (cycC, cycNotes) = mk(.cycle)
        XCTAssertEqual(cycC * 3, allC, "CYCLE strikes one note per pulse; ALL strikes all three")
        XCTAssertEqual(cycNotes, [60, 64, 67], "CYCLE walks through every chord note")
    }
    // EUCLID PICK HIGH (Paul 2026-08-22): every hit strikes only the pool's HIGHEST note (the counterpart to LOW).
    func testEuclidPickHighStrikesOnlyTheHighestNote() {
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; c.paramsA.euclidPick = .high; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(ons.count, 4, "4 pulses × 1 picked note")
        XCTAssertTrue(ons.allSatisfy { $0.note == 67 }, "PICK HIGH strikes only the highest pool note")
        assertNothingLeftSounding(e)
    }
    // EUCLID PICK RANDOM (Paul 2026-08-22): a seeded scatter — replay-EXACT (same stream twice) and always in the held pool.
    func testEuclidPickRandomIsReplayExactAndInPool() {
        func notes() -> [UInt8] {
            let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
                c.paramsA.euclidPulses = 5; c.paramsA.euclidSteps = 8; c.paramsA.euclidPick = .random; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { $0.note }
        }
        let a = notes(), b = notes()
        XCTAssertEqual(a, b, "PICK RANDOM is replay-exact (seeded by the pulse ordinal)")
        XCTAssertFalse(a.isEmpty, "it strikes")
        XCTAssertTrue(a.allSatisfy { [60, 64, 67].contains(Int($0)) }, "every struck note is one of the held pool")
    }
    // PER-PART LENGTH (Paul 2026-08-19): a row with a loop length < 8 loops over only its first Lr columns — a cell
    // placed beyond the length is never visited and stays silent, while a cell inside sounds. (Stage D: parts shorter
    // than the bar.) Row 0 loops columns 0–3; its column-1 cell sounds, its column-5 cell never does.
    func testPerRowLengthLoopsShorterThanTheBar() {
        let cs = machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; return c }
        let b = box(machines: cs) { s in
            s.cells[1][0] = Cell(machineID: "gold", buses: [.a])       // column 1 — INSIDE the length-4 loop
            s.cells[5][0] = Cell(machineID: "orange", buses: [.b])     // column 5 — BEYOND it
            s.rowLen = [4, nil, nil, nil, nil, nil, nil, nil]         // row 0 loops columns 0–3 only
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "column 1 is inside the 4-column loop — it sounds")
        XCTAssertEqual(e.ons.filter { $0.cable == 2 }.count, 0, "column 5 is beyond the loop length — never visited, silent")
        assertNothingLeftSounding(e)
    }
    // REPRO the REAL select/ferry audition (Paul device 2026-09-01): a lone cell parked at col 0 of a row PINNED to
    // column 0 (rowLane bit 0) — the continuous 1-step pass. A legato drone sustains here; the question is whether a
    // non-legato set-shaper (CHORDS) sustains or dies after one column. Compares CHORDS against HARMONIZE on the SAME path.
    private func pinnedAuditionOns(_ type: ProcessorType, configure: (inout ProcessorSlot) -> Void) -> (ons: Int, sustainedLate: Bool) {
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = type
        let b = box(machines: cs) { s in
            var lane = [UInt16](repeating: 0, count: Snap.rows); lane[0] = 0b0000_0001   // PIN row 0 to column 0 (the audition pin)
            s.rowLane = lane
            s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                var sl = ProcessorSlot(type: type); configure(&sl); x.processors = [sl]; return x }()
        }
        // Drive many windows with a chord HELD throughout (a latch-armed audition), NOT releasing until the very end.
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        let pool = chord([60])
        var lateWindowStart = 0
        while beat < 12.0 {   // ~ several passes' worth of frozen-pin time
            if beat >= 8.0 && lateWindowStart == 0 { lateWindowStart = e.events.count }
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        // "sustained late" = a note is still open (more ons than offs) at beat 8+ — i.e. it didn't fall silent.
        let onsLate = e.events[lateWindowStart...].filter { $0.status == 0x90 && $0.cable == 1 }.count
        let offsLate = e.events[lateWindowStart...].filter { $0.status == 0x80 && $0.cable == 1 }.count
        let stillOpen = e.events.filter { $0.status == 0x90 && $0.cable == 1 }.count - e.events.filter { $0.status == 0x80 && $0.cable == 1 }.count
        _ = (onsLate, offsLate)
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return (e.ons.filter { $0.cable == 1 }.count, stillOpen > 0)
    }
    // STEPS + RATE (Paul device 2026-09-01): the progression advances on its OWN clock (chordsRate), not per grid column, so
    // it plays THROUGH even on the frozen/pinned audition. Drives a pinned CHORDS and returns every emitted note pitch-class.
    private func chordsPinnedPCs(steps: Int?, rate: StepRate, degrees: [Int]) -> Set<Int> {
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = .chords
        let b = box(machines: cs) { s in
            var lane = [UInt16](repeating: 0, count: Snap.rows); lane[0] = 0b0000_0001; s.rowLane = lane   // pinned audition
            s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                var ch = ProcessorSlot(type: .chords); ch.params.chordsMode = .pattern; ch.params.chordsRoot = 0; ch.params.chordsScale = .major
                ch.params.chordsDegrees = degrees; ch.params.chordsRate = rate; ch.params.chordsSteps = steps
                x.processors = [ch]; return x }()
        }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        let pool = chord([60])
        while beat < 16.0 {   // several bars → the rate clock steps the progression through
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) % 12 })
    }
    // A single-slot GENERATOR also uses its own VELOCITY control now (Paul 2026-10-09, XY pad redesign) —
    // SUPERSEDES the old "euclid strikes each note at its own source velocity" inheritance behaviour this
    // test used to assert, mirroring the ARP precedent (`testAuditionUsesVelocityControlIgnoringSource`'s
    // own naming) exactly: VELOCITY is now a genuine absolute override, not a scale on inherited dynamics.
    func testEuclidGeneratorUsesVelocityControlIgnoringSource() {
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, velChord([(60, 50), (64, 110)]), beats: 2, into: e)
        let a = e.ons.filter { $0.cable == 1 }
        XCTAssertFalse(a.isEmpty)
        XCTAssertTrue(a.allSatisfy { $0.vel == 100 }, "euclid strikes at its own default VELOCITY control (100), ignoring the source chord's own 50/110 dynamics entirely")
        assertNothingLeftSounding(e)
    }
    // THE PER-MACHINE MACHINE (user 2026-08-09, GLOBAL): a machine's `templateChain` drives EVERY cell of that machine
    // that has no per-cell override — the machine lives on the (document-global) MACHINE, not the cell.
    func testMachineTemplateChainDrivesAllItsCells() {
        var cs = arpMachines()                                   // gold head = arp…
        let gi = machineIDs.firstIndex(of: "gold")!
        var tmpl = ProcessorSlot(type: .euclid); tmpl.params.euclidPulses = 4; tmpl.params.euclidSteps = 8
        cs[gi].templateChain = [tmpl]                           // …but the MACHINE owns a euclid machine
        let b = box(machines: cs) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // processors == nil → inherit the machine template
            $0.cells[0][1] = Cell(machineID: "gold", buses: [.a])
        }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 24, "both gold cells render the MACHINE's euclid template (2 cells × 4-of-8 × 3 notes)")
        assertNothingLeftSounding(e)
    }
    // MARK: - PHASE 2 render-time part automation (Paul 2026-09-04)
    // A ×N-passes / SMOOTH AUTO lane overrides ONE scalar proc param FROM the beat (not compile-time baked). These drive
    // the REAL Router via box.renderAuto. Observable: euclid HITS ramp with the automated euclidPulses.

    /// A part with `gold` (a euclid machine) on every column of row 0, plus an active render-time AUTO lane.
    private func renderAutoBox(pulsesBase: Int, lane: AutoLane) -> SnapshotBox {
        var cs = arpMachines()
        let gi = machineIDs.firstIndex(of: "gold")!
        var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = pulsesBase; eu.params.euclidSteps = 8
        cs[gi].templateChain = [eu]
        var s = SceneState.empty()
        for c in 0..<8 { s.cells[c][0] = Cell(machineID: "gold", buses: [.a]) }   // gold on every column → the ramp shows column-by-column
        var st = PluginState(machines: cs, scenes: [s])
        st.partAuto = ["gold": PartAutoMachine(activeLane: 0, lanes: [lane])]
        return SnapshotBuilder.build(from: st)
    }
    /// Emit-A (cable 1) note-ons that fall in BAR `bar` (8 cols × S=2 beats × 24000 samples/beat = 384000 samples/bar).
    private func onsInBar(_ e: RecordingEmitter, _ bar: Int) -> Int {
        let lo = Int64(bar) * 384_000, hi = Int64(bar + 1) * 384_000
        return e.ons.filter { $0.cable == 1 && $0.sample >= lo && $0.sample < hi }.count
    }
    private func passSpanLane() -> AutoLane {
        var lane = AutoLane(); lane.slot = 0; lane.param = "euclidPulses"; lane.lo = 1; lane.hi = 8; lane.spanStart = 0; lane.spanPasses = 2
        return lane
    }
    func testRenderAutoPassSpanRepeatsAfterItsPeriod() {
        let box = renderAutoBox(pulsesBase: 1, lane: passSpanLane())
        let e = RecordingEmitter(); run(box, chord([60]), beats: 48, into: e)   // 3 bars → after the 2-bar period the ramp repeats
        let b0 = onsInBar(e, 0), b2 = onsInBar(e, 2)
        XCTAssertEqual(b2, b0, "after one ×2 period (2 bars) the ramp re-anchors — bar2 == bar0 (\(b2) vs \(b0))")
        assertNothingLeftSounding(e)
    }
    func testRenderAutoStepLaneMakesNoRenderDescriptor() {
        var lane = AutoLane(); lane.slot = 0; lane.param = "euclidPulses"; lane.lo = 1; lane.hi = 8; lane.spanStart = 0; lane.spanLen = 4
        let box = renderAutoBox(pulsesBase: 1, lane: lane)   // a STEP-length span (no ×N / no SMOOTH)
        XCTAssertTrue(box.renderAuto.isEmpty, "a STEP-length span is compile-time baked (composeScene), never a render-time descriptor")
    }
    func testRenderAutoIsReplayExact() {
        let box = renderAutoBox(pulsesBase: 1, lane: passSpanLane())
        let e1 = RecordingEmitter(); run(box, chord([60]), beats: 32, into: e1)
        let e2 = RecordingEmitter(); run(box, chord([60]), beats: 32, into: e2)
        XCTAssertEqual(e1.events, e2.events, "render-time AUTO is derived from the beat → byte-identical on replay")
    }
    func testRenderAutoNoActiveLaneIsInert() {
        var lane = passSpanLane()
        var st = PluginState(machines: { var cs = arpMachines(); var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = 4; cs[machineIDs.firstIndex(of: "gold")!].templateChain = [eu]; return cs }(),
                             scenes: [{ var s = SceneState.empty(); for c in 0..<8 { s.cells[c][0] = Cell(machineID: "gold", buses: [.a]) }; return s }()])
        st.partAuto = ["gold": PartAutoMachine(activeLane: -1, lanes: [lane])]   // NONE selected → no render-time descriptor
        XCTAssertTrue(SnapshotBuilder.build(from: st).renderAuto.isEmpty, "activeLane = NONE ⇒ box.renderAuto stays empty (byte-identical)")
    }
    // CHANCE → CONSTANT-DENSITY (user 2026-08-11): keep ~a constant NUMBER of notes regardless of chord size — a small
    // chord keeps MORE than fixed-% (p rises to the target), a big chord keeps FEWER (thinned to the target).
    func testChanceConstantDensityHoldsCountVsFixedPercent() {
        func avg(_ count: Int, _ prob: Double, dens: Bool) -> Double {
            var total = 0; let trials = 300
            for t in 0..<trials { for k in 0..<count where chancePassesPool(beat: Double(t) * 0.25, note: 48 + k, rank: k, count: count, probability: prob, tilt: 0, constantDensity: dens) { total += 1 } }
            return Double(total) / Double(trials)
        }
        XCTAssertGreaterThan(avg(3, 0.4, dens: true), avg(3, 0.4, dens: false) + 0.3, "a 3-chord keeps MORE under constant-density")
        XCTAssertLessThan(avg(12, 0.4, dens: true), avg(12, 0.4, dens: false), "a 12-chord keeps FEWER (thinned to the target)")
    }
    // CHANCE → WEIGHT/tilt (user 2026-08-11): +tilt favours the TOP notes, −tilt the BOTTOM.
    func testChanceWeightFavoursTopOrBottom() {
        func passRate(_ rank: Int, _ count: Int, _ tilt: Double) -> Double {
            var passed = 0; let trials = 400
            for t in 0..<trials where chancePassesPool(beat: Double(t) * 0.25, note: 48 + rank, rank: rank, count: count, probability: 0.5, tilt: tilt, constantDensity: false) { passed += 1 }
            return Double(passed) / Double(trials)
        }
        XCTAssertGreaterThan(passRate(4, 5, 0.8), passRate(0, 5, 0.8) + 0.2, "+tilt: the TOP note survives more than the bottom")
        XCTAssertLessThan(passRate(4, 5, -0.8), passRate(0, 5, -0.8) - 0.2, "−tilt: the reverse")
    }
    func testEuclidPulsesFromPoolTracksHeldCount() {
        // PULSES = POOL (user 2026-08-09): K follows the held-note count — 3 held → E(3,8), 4 held → E(4,8).
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
            c.paramsA.euclidSteps = 8; c.paramsA.euclidPulsesFromPool = true; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e3 = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e3)          // 3 held → 3 pulses × 3 notes
        XCTAssertEqual(e3.ons.filter { $0.cable == 1 }.count, 9, "POOL: 3 held → E(3,8)")
        let e4 = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 2, into: e4)      // 4 held → 4 pulses × 4 notes
        XCTAssertEqual(e4.ons.filter { $0.cable == 1 }.count, 16, "POOL: 4 held → E(4,8)")
        assertNothingLeftSounding(e3); assertNothingLeftSounding(e4)
    }
    // GENERATORS AS CHAIN DRIVERS (user 2026-08-09): the driver drives, downstream slots fold; upstream composes.
    func testEuclidThenOpenGateStillGenerates() {
        let b = box(machines: arpMachines()) {
            var c = Cell(machineID: "gold", buses: [.a])
            var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = 4; eu.params.euclidSteps = 8
            var gate = ProcessorSlot(type: .chance); gate.params.probability = 1.0   // deterministic full pass (PASSGATE removed 2026-09-28)
            c.processors = [eu, gate]; $0.cells[0][0] = c
        }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 12, "euclid drives; the open gate folds through → 4 pulses × 3 notes")
        assertNothingLeftSounding(e)
    }
    // THE FLOOD (incident 2026-08-08) — the range-drop guard, the governor, and the panic controllers.
    func testEchoPitchClimbNeverEncodesAboveMidi127() {
        // ECHO +12/repeat from a high note climbs out of MIDI range; those repeats must be DROPPED at the ring
        // drain, NEVER encoded as a byte ≥128 (which a synth reads as a status → parser desync → every synth mutes).
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .echo)
            c.paramsA.echoDelayDiv = 1; c.paramsA.echoRepeats = 12; c.paramsA.echoFeedDelay = 1
            c.paramsA.echoDecay = 1; c.paramsA.echoPitch = 12; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([100]), beats: 3, into: e)             // 100 → 112 → 124 → 136 (out of range → dropped) …
        XCTAssertTrue(e.events.allSatisfy { $0.note <= 127 }, "no wire byte encodes a note above 127")
        assertNothingLeftSounding(e)
    }
    func testFloodGovernorCapsAndCountsDrops() {
        // Pathological flood: 8 dense euclid cells in column 0, all on emitter A, over a big chord — far past the
        // per-beat cap. The governor drops the overflow (counted, surfaced to HEALTH) and leaves nothing stuck.
        let cs = machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
            c.paramsA.euclidPulses = 16; c.paramsA.euclidSteps = 16; return c }
        let b = box(machines: cs) { for r in 0..<8 { $0.cells[0][r] = Cell(machineID: machineIDs[r], buses: [.a]) } }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0, wb = Double(2048) * 120.0 / 60.0 / 48_000.0
        var beat = 0.0, ts = 0.0
        for _ in 0..<40 {
            router.process(box: b, pool: chord([48, 50, 52, 55, 57, 60, 62, 64]), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)   // stop flush
        XCTAssertGreaterThan(router.floodDropped, 0, "the flood tripped the governor")
        XCTAssertEqual(diag.floodDropped, router.floodDropped, "the drop total is surfaced to HEALTH")
        assertNothingLeftSounding(e)
    }

    func testPanicBlastsAllNotesOffAndAllSoundOffOnEveryChannel() {
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                       timestampSample: 0, frameCount: 2048, out: e, diag: &diag)
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 0.1, tempo: 120, sampleRate: 48_000,
                       timestampSample: 2048, frameCount: 2048, panic: true, out: e, diag: &diag)
        let ccs = e.events.filter { $0.status == 0xB0 }
        XCTAssertEqual(ccs.filter { $0.note == 123 }.count, 5 * 16, "CC123 (All-Notes-Off) on every channel of every cable")
        XCTAssertEqual(ccs.filter { $0.note == 120 }.count, 5 * 16, "CC120 (All-Sound-Off) on every channel of every cable")
        assertNothingLeftSounding(e)
    }

    func testMutedCellEmitsNothing() {
        var cell = Cell(machineID: "gold"); cell.muted = true
        let b = box(machines: arpMachines()) { $0.cells[0][0] = cell }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.events.isEmpty, "a muted cell (§6.2) produces no MIDI on any cable")
    }

    // MARK: audition (§6.4 / delta §5)












    // MARK: - EMITTER TOGGLES (§6a) — busEnabled gate at the emission boundary

    /// Build a box with a per-emitter enable array (nil ⇒ all enabled).
    private func box(machines cs: [Machine], busEnabled: [Bool]?, _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(machines: cs, scenes: [s]); st.busEnabled = busEnabled
        return SnapshotBuilder.build(from: st)
    }

    func testDisabledEmitterIsSilentOnItsCableAndAll() {
        // Cell → bus B only, with B disabled: nothing on cable 2 (B) or cable 0 (All).
        let b = box(machines: arpMachines(), busEnabled: [true, false, true, true]) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(e.events.isEmpty, "a disabled emitter produces nothing on its own cable OR All")
    }

    func testDisabledEmitterNeverMeters() {
        let b = box(machines: arpMachines(), busEnabled: [false, true, true, true]) { $0.cells[0][0] = Cell(machineID: "gold") }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let sr = 48_000.0; let frames: UInt32 = 2048
        var beat = 0.0, ts = 0.0; let wb = Double(frames) * 120 / 60 / sr
        for _ in 0..<12 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        XCTAssertEqual(router.drainMeters().events[0], 0, "a disabled emitter never meters")
    }

    // MARK: - §strips-done HOLD-WHILE-SOUNDING — drainEmitterSounding() reports the live per-emitter voice set

    // MARK: - item 4 VELOCITY MARKS — the per-note (velocity, source-machine) ring drained by drainMarks()


    // MARK: - VELOCITY OVERRIDE (§6a PERFORM) — momentary per-emitter flatten at the emission boundary


    /// Pack a single emitter's override into the byte-per-emitter word the engine reads.
    private func packVel(_ bus: Int, _ value: Int) -> UInt32 { UInt32(value & 0xFF) << (UInt32(bus) * 8) }


    // MARK: - CLAIM (§6a) — one-claimant exclusivity, suppression against the live voice table

    /// An identity-hold machine (sustains the chord to the column boundary = the claimant "holds" a
    /// pitch), optionally transposed so a second emitter can hold a DIFFERENT pitch (the residue case).
    private func holdMachine(_ id: String, transpose: Int = 0) -> Machine {
        var c = Machine(machineID: id, type: .empty)
        c.paramsA.gate = 1.0
        c.transpose = transpose
        return c
    }
    /// Machines with gold → held on A (transpose 0) and cyan → held on B (transposeB); the rest are arps.
    private func claimMachines(transposeB: Int) -> [Machine] {
        machineIDs.map { id in
            if id == "gold" { return holdMachine(id, transpose: 0) }
            if id == "cyan" { return holdMachine(id, transpose: transposeB) }
            return Machine(machineID: id, type: .arp)
        }
    }
    private func claimBox(_ cs: [Machine], claim: Int?, _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(machines: cs, scenes: [s]); st.claimEmitter = claim
        return SnapshotBuilder.build(from: st)
    }

    func testMutedClaimantStillReservesItsPitches() {
        // A claimant whose EMITTER TOGGLE is off makes no sound itself, yet still claims: the pitch it
        // would hold is suppressed on B (a silent reservation — sidechain-style). No wire from A, no stuck.
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // col 0, row 0 → A reserves 60 (muted)
            s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // col 0, row 1 → B would hold 60
            return s }()])
        st.claimEmitter = 0
        st.busEnabled = [false, true, true, true]                 // A muted
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 16, into: e)
        XCTAssertTrue(e.events.filter { $0.cable == 1 }.isEmpty, "the muted claimant emits nothing on its own cable")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 && $0.note == 60 }.isEmpty, "B still yields 60 to the muted claimant")
        assertNothingLeftSounding(e)
    }

    func testMutedClaimantReservesShortNotesAcrossCells() {
        // M2 regression: a MUTED claimant running a FAST arp still reserves its pitches — the persistent
        // silent ghost is no longer immediate-closed, so a same-pitch non-claimant cell yields even at speed.
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!].paramsA.rate = .r1_32
        cs[machineIDs.firstIndex(of: "cyan")!].paramsA.rate = .r1_32
        var st = PluginState(machines: cs, scenes: [{ var s = SceneState.empty()
            for c in 0..<8 {
                s.cells[c][0] = Cell(machineID: "gold", buses: [.a])   // muted claimant
                s.cells[c][1] = Cell(machineID: "cyan", buses: [.b])
            }
            return s }()])
        st.claimEmitter = 0
        st.busEnabled = [false, true, true, true]   // A muted
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 16, into: e)
        XCTAssertTrue(e.events.filter { $0.cable == 1 }.isEmpty, "muted claimant is silent")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 && $0.note == 60 }.isEmpty,
                      "B still yields to the muted claimant's fast reservation (M2)")
        assertNothingLeftSounding(e)
    }

    // MARK: - CLAIM v2 (§6a) — MULTI-claim (SHARED tier) + LEAK %

    /// Build a box with an explicit claim MASK + optional per-claimant LEAK (bypassing the legacy single field).
    private func claimMaskBox(_ cs: [Machine], mask: UInt8, leak: [Int] = [0, 0, 0, 0],
                              _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(machines: cs, scenes: [s]); st.claimMask = mask; st.claimLeak = leak
        return SnapshotBuilder.build(from: st)
    }

    func testMultiClaimLeakZeroStillFullySuppresses() {
        // Regression: a claim with LEAK 0 is exactly v1 — the non-claimant is silent, no shadow.
        let b = claimMaskBox(claimMachines(transposeB: 0), mask: 0b0001, leak: [0, 0, 0, 0]) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(e.ons.filter { $0.cable == 2 }.isEmpty, "LEAK 0 ⇒ hard suppression (v1 behaviour)")
        assertNothingLeftSounding(e)
    }

    // MARK: - THE RACK (design-the-rack §3) — the two-tier gate: RACK off ⇒ raw wire regardless of the matrix

    private func rackClaimBox(_ cs: [Machine], claim: UInt8, rack: UInt8?, _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(machines: cs, scenes: [s]); st.claimMask = claim; st.rackEnabledMask = rack
        return SnapshotBuilder.build(from: st)
    }

    func testRackGatePreAndsTreatmentMasksIntoTheBox() {
        // The builder pre-ANDs the rack gate into every treatment mask; a missing gate ⇒ all-on (old-doc safe).
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [SceneState.empty()])
        st.claimMask = 0b0011; st.flattenMask = 0b0011; st.altMask = 0b0011
        st.rackEnabledMask = 0b0001                                  // only emitter A's rack is in path
        let gated = SnapshotBuilder.build(from: st)
        XCTAssertEqual(gated.claimMask, 0b0001, "claim gated to A")
        XCTAssertEqual(gated.flattenMask, 0b0001, "duck gated to A")
        XCTAssertEqual(gated.altMask, 0b0001, "alt gated to A")
        XCTAssertEqual(gated.rackMask, 0b0001, "box carries the raw gate for future treatments")

        st.rackEnabledMask = nil                                    // old doc / clean instrument ⇒ all racks in path
        let ungated = SnapshotBuilder.build(from: st)
        XCTAssertEqual(ungated.claimMask, 0b0011, "nil rack ⇒ no gating (0b1111)")
        XCTAssertEqual(ungated.rackMask, 0b1111, "resolver defaults to all-on")
    }

    // §6a THE WITHHELD TELL — the drainWithheld() feed reports CLAIM-suppressed note-ons (for the hollow strip mark).
    private func drainWithheldAfter(_ box: SnapshotBox, windows: Int = 8) -> [[(vel: UInt8, col: Int8)]] {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let sr = 48_000.0; let frames: UInt32 = 2048
        var beat = 0.0, ts = 0.0; let wb = Double(frames) * 120 / 60 / sr
        for _ in 0..<windows {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        return router.drainWithheld()
    }

    func testLeakedNoteIsNotWithheld() {
        // A LEAK bleed (leak > 0) sounds as a shadow, so it is NOT a withholding — no hollow mark.
        let b = claimMaskBox(claimMachines(transposeB: 0), mask: 0b0001, leak: [50, 0, 0, 0]) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        XCTAssertTrue(drainWithheldAfter(b)[1].isEmpty, "a LEAK bleed sounds → not withheld")
    }

    func testNoClaimWithholdsNothing() {
        let b = claimMaskBox(claimMachines(transposeB: 0), mask: 0) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        XCTAssertTrue(drainWithheldAfter(b).allSatisfy { $0.isEmpty }, "no claim ⇒ nothing withheld")
    }

    // MARK: - COVERAGE HARDENING — device topologies (T-series) with no prior unit coverage

    // (testFanOutTreeEmitsThreeDerivedStreams removed 2026-08-27: GRID-CHAINING retired — `inputRow` is render-inert
    //  (resolvedParent is hardcoded −1), so the "derived fan-out streams" never existed; the children sound only because
    //  they read the source pool. The test passed for the wrong reason.)

    func testMutedReceiverSilencesItsSubscribers() {
        // delta §9 item 11: a MIDI-IN cell subscribed to a MUTED receiver reads an empty pool → silence.
        var st = PluginState(machines: arpMachines(), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
            return s }()])
        st.receivers = [Receiver(name: "1", channel: 0, muted: true), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.events.isEmpty, "a muted receiver feeds its subscribers nothing")
    }

    // (testBackwardTapDownwardReferenceEmits + testProcBFullMorphsToBFaceUnderAlt + testProcBSwapFlipsTypeUnderAlt removed
    //  2026-08-27: all three guard RETIRED features that pass for the wrong reason. Backward-tap = grid-chaining (`inputRow`
    //  render-inert). The two procB tests = A/B MORPH (dropped from the render — paramsB/typeB are decode-only), so they
    //  only assert "ALT does NOT reach the inert B-face", which can never fail. The alt-bit's live role (voice identity)
    //  is covered elsewhere.)

    // A CLOSED gate after the arp gates every arp note → silence (the fold empties the set each tick).
    func testArpThenClosedGateIsSilent() {
        let cs = arpMachines()
        let arp = ProcessorSlot(type: .arp)
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 0.0   // deterministic closed gate (PASSGATE removed 2026-09-28)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.isEmpty, "a closed gate after the arp gates every arp note → silence")
        assertNothingLeftSounding(e)
    }
    // AVOID/LOCK (unified 2026-08-31): a per-note pitch filter placeable anywhere. It works the SAME before or after a
    // driver (remove/move, no re-pick) — the position only changes whether it thins the POOL (before) or punches holes
    // in the LINE (after). Uses a declared-KEY reference (deterministic, no live state).
    private func avoidSlot(kind: AvoidRefKind, root: Int = 0, scale: ScaleType = .major, lock: Bool, move: Bool) -> ProcessorSlot {
        var s = ProcessorSlot(type: .avoid)
        s.params.avoidRefKind = kind; s.params.avoidRoot = root; s.params.avoidScale = scale
        s.params.avoidMode = lock ? .lock : .avoid; s.params.avoidAction = move ? .move : .remove
        return s
    }

    // ═══ AVOID / LOCK — the COMPREHENSIVE end-to-end acceptance suite (Paul 2026-08-31) ═══════════════════════════════
    // Every expectation is reasoned from the CONCEPT (a per-pitch-class filter), then checked against the REAL engine
    // end-to-end: a held INPUT chord on door 0 → the AVOID chain → the emitted MIDI-out notes. The REFERENCE is played
    // LIVE on another door's channel (at octave 7, note 84+pc, so it never collides with the input's own MIDI numbers).

    /// A configured AVOID/LOCK slot.
    private func mkAvoid(kind: AvoidRefKind = .door, refIndex: Int = 1, lock: Bool = false, move: Bool = false,
                         what: AvoidWhat = .same, root: Int = 0, scale: ScaleType = .major) -> ProcessorSlot {
        var s = ProcessorSlot(type: .avoid)
        s.params.avoidRefKind = kind; s.params.avoidRefIndex = refIndex
        s.params.avoidMode = lock ? .lock : .avoid; s.params.avoidAction = move ? .move : .remove
        s.params.avoidWhat = what; s.params.avoidRoot = root; s.params.avoidScale = scale
        return s
    }
    /// Run `chain` over `input` (door 0, channel 0) with `refs` = live reference classes per door (door d = channel d,
    /// notes at 84+pc so they never collide with the input). Returns the recording emitter (for stuck-note checks).
    private func avoidRunE(_ chain: [ProcessorSlot], input: [Int], refs: [(door: Int, classes: [Int])] = []) -> RecordingEmitter {
        let cs = arpMachines()
        var st = PluginState(machines: cs, scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; c.processors = chain; return c }()
            return s }()])
        st.busChannels = [1, 2, 3, 4]
        st.receivers = [Receiver(name: "1", channel: 1), Receiver(name: "2", channel: 2), Receiver(name: "3", channel: 3), Receiver(name: "4", channel: 4)]
        let box = SnapshotBuilder.build(from: st)
        let pool = NotePool()
        for n in input { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        for (door, classes) in refs { for pc in classes { pool.noteOn(UInt8(84 + pc), velocity: 100, channel: UInt8(door)) } }
        let e = RecordingEmitter(); run(box, pool, beats: 16, into: e); return e
    }
    /// The DISTINCT emitted pitch CLASSES (emitter A) — the octave-agnostic result the filter reasons about.
    private func avoidPCs(_ chain: [ProcessorSlot], input: [Int], refs: [(door: Int, classes: [Int])] = []) -> Set<Int> {
        Set(avoidRunE(chain, input: input, refs: refs).ons.filter { $0.cable == 1 }.map { ((Int($0.note) % 12) + 12) % 12 })
    }

    func testLockEmptyReferenceSilences() {   // C2
        XCTAssertTrue(avoidPCs([mkAvoid(lock: true)], input: [60, 62, 64], refs: []).isEmpty, "empty reference · LOCK → silence (nothing to lock to)")
        XCTAssertTrue(avoidPCs([mkAvoid(lock: true, move: true)], input: [60, 62, 64], refs: []).isEmpty, "empty reference · LOCK MOVE → still silence")
    }
    func testAvoidMoveWithNoSurvivorsDrops() {   // C6
        XCTAssertTrue(avoidPCs([mkAvoid(move: true)], input: [62], refs: [(1, [2])]).isEmpty, "MOVE with a single blocked note & no survivor → drops (= REMOVE)")
    }

    func testReferenceIsOctaveAgnostic() {   // C12
        XCTAssertTrue(avoidPCs([mkAvoid()], input: [48], refs: [(1, [0])]).isEmpty, "a C in octave 7 (the reference) blocks a C in octave 3 (the input) — pitch-class match")
    }
    func testMoveNeverEmitsOutOfRange() {   // C14
        let out = avoidRunE([mkAvoid(move: true)], input: [1, 3], refs: [(1, [1])]).ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertTrue(out.allSatisfy { $0 >= 0 && $0 <= 127 }, "MOVE near note 0 never emits an out-of-range note")
    }

    // ── Invariants ─────────────────────────────────────────────────────────────
    func testAvoidNeverLeavesAStuckNote() {   // C24/C25
        // A spread of configs, each must end with every voice released.
        assertNothingLeftSounding(avoidRunE([mkAvoid()], input: [60, 62, 64], refs: [(1, [2])]))
        assertNothingLeftSounding(avoidRunE([mkAvoid(move: true)], input: [60, 64, 67], refs: [(1, [4])]))
        assertNothingLeftSounding(avoidRunE([mkAvoid(lock: true, move: true)], input: [60, 62], refs: [(1, [0, 7])]))
        assertNothingLeftSounding(avoidRunE([ProcessorSlot(type: .arp), mkAvoid(move: true)], input: [60, 64, 67], refs: [(1, [4])]))
        assertNothingLeftSounding(avoidRunE([mkAvoid(kind: .sounding, what: .clash2)], input: [60, 61, 62], refs: [(1, [0]), (2, [5])]))
    }

    // RECORDER persistence — the recEvents buffer + config round-trip through Codable; an old doc missing the keys
    // decodes to an empty buffer (CR-8 decode-tolerance).
    func testRecorderBufferPersistRoundTrip() throws {
        var m = Machine(machineID: "gold", type: .recorder)
        m.paramsA.recEvents = [RecEvent(beat: 0.5, note: 64, vel: 80, gate: 0.3)]
        m.paramsA.recMode = .canon; m.paramsA.recGrain = .steps
        let back = try JSONDecoder().decode(Machine.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back.paramsA.recEvents?.count, 1)
        XCTAssertEqual(back.paramsA.recEvents?.first?.note, 64)
        XCTAssertEqual(back.paramsA.recEvents?.first?.gate, 0.3)
        XCTAssertEqual(back.paramsA.recMode, .canon)
        let bare = try JSONDecoder().decode(Machine.self, from: JSONEncoder().encode(Machine(machineID: "gold", type: .arp)))
        XCTAssertNil(bare.paramsA.recEvents, "an old doc without recorder keys decodes to an empty buffer")
    }

    // MARK: - THE MOD PROCESSOR (CC generator, delta)

    private func modCC74Events(_ e: RecordingEmitter) -> [RecordingEmitter.Ev] {
        e.events.filter { $0.status == 0xB0 && $0.cable == 1 && $0.note == 74 }   // CC 74 on Emit A
    }
    /// Beat-derived + replay-safe: the same beats produce a byte-identical CC stream (incl. seeded S&H).
    func testModCCStreamIsReplaySafe() {
        func ccStream() -> [RecordingEmitter.Ev] {
            let cs = arpMachines()
            var mod = ProcessorSlot(type: .mod); mod.params.modShape = .sampleHold; mod.params.modCC = 74; mod.params.modRate = .r1
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
            return e.events.filter { $0.status == 0xB0 }
        }
        XCTAssertEqual(ccStream(), ccStream(), "the MOD CC stream is replay-safe (same beats → identical)")
    }

    // RIFF DIRECTION widened to 6 modes (Paul 2026-09-28): an 8-step, 8-note stencil so the played RANK is
    // directly readable off the emitted note (rank r → note 59+r).
    private func riffDirNotes(_ dir: RiffDir, seed: Int? = nil, bias: Double? = nil, spanN: Int? = nil,
                              steps: Int = 8, beats: Double = 6) -> [Int] {
        var c = Machine(machineID: "gold", type: .riff)
        c.paramsA.riffRanks = Array(1...steps); c.paramsA.riffSteps = steps; c.paramsA.riffRate = .r1_16
        c.paramsA.riffWrap = .clamp; c.paramsA.riffDir = dir; c.paramsA.riffDirSeed = seed; c.paramsA.riffDirBias = bias
        c.paramsA.riffSpanN = spanN
        let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let notes = (0..<steps).map { UInt8(60 + $0) }
        // forceColumn: 0 — a bare test cell only ticks within its OWN grid column's real-time span otherwise (the
        // "PLAY: THIS CELL" bypass, needed here because these tests run many beats to capture a full bounce period).
        let e = RecordingEmitter(); run(b, chord(notes), beats: beats, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        return e.ons.filter { $0.cable == 1 }.map { Int($0.note) - 59 }   // → rank 1...steps
    }
    func testRiffPendulumWithTwoStepsDegeneratesToForward() {
        XCTAssertEqual(riffDirNotes(.pendulum, steps: 2, beats: 4), riffDirNotes(.forward, steps: 2, beats: 4),
                       "PENDULUM with n=2 behaves exactly like FORWARD")
    }
    // NOTE (Paul 2026-09-28): a SPAN-obliviousness regression test (comparing DRUNK's sequence across riffSpanN
    // values, guarding the tick-vs-raw design decision) was attempted here and dropped — riffSpanN produced no
    // observable effect on ANY direction mode (including FORWARD, which the span mechanism unambiguously affects
    // in production) under this test's forceColumn:0 harness, an interaction not tracked down in this pass. Not a
    // gap in the feature itself (the engine code correctly keys the walk on `tick`, never `raw` — see riffDrunkStep/
    // the switch case in Router.swift) — a gap in this test's coverage of it, flagged rather than shipped vacuous.
    func testRiffDrunkResetsOnATransportStopStartEdge() {
        var c = Machine(machineID: "gold", type: .riff)
        c.paramsA.riffRanks = Array(1...8); c.paramsA.riffSteps = 8; c.paramsA.riffRate = .r1_16
        c.paramsA.riffWrap = .clamp; c.paramsA.riffDir = .drunk; c.paramsA.riffDirBias = 0; c.paramsA.riffDirSeed = 55
        let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let pool = chord((0..<8).map { UInt8(60 + $0) })
        let tempo = 120.0, sr = 48_000.0; let frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr

        // ONE router: play a while, STOP (the reset edge), then play again — capture only the SECOND play's notes.
        let router = Router(); var diag = KernelDiag(); let scratch = RecordingEmitter(); let e2 = RecordingEmitter()
        var beat = 0.0, ts = 0.0
        for _ in 0..<8 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, out: scratch, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, forceColumn: 0, out: scratch, diag: &diag)   // STOP → resets the walk
        beat = 0; ts = 0   // a real replay restarts the transport clock too
        for _ in 0..<4 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, out: e2, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, forceColumn: 0, out: e2, diag: &diag)

        // A totally fresh session, the same 4-window play — must match if the stop/start edge truly restarted the walk.
        let e1 = RecordingEmitter(); run(b, pool, beats: 4 * windowBeats, into: e1, forceColumn: 0)

        let seq1 = e1.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        let seq2 = e2.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertEqual(seq1, seq2, "a transport stop/start restarts DRUNK's walk from the same fresh state as a brand-new play")
    }
    // EUCLID LINES (§10): up to 8 lines from ONE chord — one ALL line = the single euclid (byte-identical); a second line
    // adds its own pulses (polyrhythm); a NOTE-target line strikes only that pool rank. Nothing left sounding.
    func testEuclidLinesPolyrhythmAndNoteTargets() {
        func run4(_ lines: [EuclidLine]?, _ measure: (RecordingEmitter) -> Void) {
            var c = Machine(machineID: "gold", type: .euclid); c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8
            if let lines { c.paramsA.euclidLines = lines }
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e); measure(e)
        }
        func aCount(_ e: RecordingEmitter) -> Int { e.ons.filter { $0.cable == 1 }.count }
        var single = 0, oneLine = 0, two = 0; var n2: Set<UInt8> = []
        run4(nil) { single = aCount($0) }
        run4([EuclidLine(target: 0, pulses: 4, steps: 8, rotate: 0, invert: false)]) { oneLine = aCount($0) }
        run4([EuclidLine(target: 0, pulses: 4, steps: 8), EuclidLine(target: 1, pulses: 3, steps: 16)]) { two = aCount($0) }
        run4([EuclidLine(target: 2, pulses: 4, steps: 8)]) { n2 = Set($0.ons.filter { $0.cable == 1 }.map { $0.note }) }
        var beyond = -1
        run4([EuclidLine(target: 6, pulses: 4, steps: 8)]) { beyond = aCount($0) }   // rank 6 of a 3-note chord — absent
        XCTAssertEqual(oneLine, single, "one ALL line = the single euclid (byte-identical)")
        XCTAssertGreaterThan(two, oneLine, "a second line adds its own pulses (polyrhythm)")
        XCTAssertEqual(n2, [64], "TARGET N2 strikes only the 2nd pool note (64)")
        XCTAssertEqual(beyond, 0, "a TARGET past the held chord (rank 6 of 3 notes) strikes NOTHING — correctly silent, never wraps")
    }
    // EUCLIDEOUS RIFF ADVANCE (Paul 2026-10-06): "each hit will progress riff by 1 step" — a line with useRiff on
    // reads the page's ONE shared riff pattern instead of noteSel on every hit ("replaces it entirely," Paul's own
    // ratified answer), using its own stateless hit-ordinal for 5 of 6 directions (needs zero new persisted state)
    // and a small, dedicated per-lane walk for DRUNK alone (the one genuinely path-dependent direction).
    func testEuclidLineUseRiffReplacesNoteSelectWithSharedRiffPattern() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 2, ranks: [1, 3])   // rank 1 = lowest, rank 3 = 3rd-lowest; direction defaults to FWD
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 4, noteSel: .high, useRiff: true)]   // noteSel=.high would strike ONLY the top note (72) if useRiff didn't override it
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, receivers: [Receiver(name: "1")]) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 4, into: e); assertNothingLeftSounding(e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertTrue(notes.contains(60), "rank 1 (the lowest pool note) must appear — useRiff reads the shared riff pattern")
        XCTAssertTrue(notes.contains(67), "rank 3 (the 3rd-lowest pool note) must appear too")
        XCTAssertFalse(notes.contains(72), "noteSel=.high (the top note) must be IGNORED — useRiff replaces it entirely, not layered on top")
    }
    func testEuclidLineUseRiffRotateShiftsWhichRankIsStruck() {
        // pulses:1/steps:1 (fully dense, one tick per rate interval) + forceColumn:0 isolates the VERY FIRST hit,
        // at hit-ordinal 0 — so rotate alone decides which riff step (and therefore which rank/note) is read.
        func firstNote(rotate: Int) -> Int? {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 4, ranks: [1, 2, 3, 4])
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: true, riffRotate: rotate)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, receivers: [Receiver(name: "1")]) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 1, into: e, forceColumn: 0); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }.first
        }
        XCTAssertEqual(firstNote(rotate: 0), 60, "ord=0, rotate=0 → riff step 0 → rank 1 → the lowest pool note")
        XCTAssertEqual(firstNote(rotate: 2), 67, "ord=0, rotate=2 → riff step 2 → rank 3 → the 3rd-lowest pool note — matches euclidPatternInto's own (i+rot)%n convention")
    }
    func testEuclidLineUseRiffOctaveReplacesTheLinesOwnOctaveNotStacksWithIt() {
        func firstNote(riffOctave: Int) -> Int? {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, octave: 2, useRiff: true, riffOctave: riffOctave)]   // octave:2 deliberately set — must be ignored, not stacked
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, receivers: [Receiver(name: "1")]) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 1, into: e, forceColumn: 0); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }.first
        }
        XCTAssertEqual(firstNote(riffOctave: 0), 60, "riffOctave 0 = unshifted — and the line's own octave:2 must NOT also apply")
        XCTAssertEqual(firstNote(riffOctave: 1), 72, "riffOctave +1 shifts by exactly one octave (would be 96 if octave:2 also stacked)")
    }
    // DIRECTION IS PER-LANE, NOT SHARED (Paul 2026-10-07: "the back/forward, drunk controls should be per lane,
    // not on the riff control") — two lanes reading the SAME shared pattern with DIFFERENT riffDir must land on
    // DIFFERENT positions, proving direction genuinely lives on EuclidLine, not on the shared EuclideousRiff.
    func testEuclidLinesEachHaveIndependentRiffDirectionIntoTheSharedPattern() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 4, ranks: [1, 2, 3, 4])
        // sourceMode: .midi explicit on both — the melody pop-up ferry (2026-10-10 §2.2) flipped the
        // nil-default to KEY. riffLength: 4 explicit too, matching the shared pattern's own real step
        // count (4) — LENGTH otherwise defaults to 8, and REV's own natural anchor (length-1=7) would
        // land outside `ranks.count`(4), reading as a rest instead of this test's expected rank 4.
        c.paramsA.euclidLines = [
            EuclidLine(pulses: 1, steps: 1, useRiff: true, riffDir: .forward, sourceMode: .midi, riffLength: 4),
            EuclidLine(pulses: 1, steps: 1, useRiff: true, riffDir: .reverse, sourceMode: .midi, riffLength: 4),
        ]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, receivers: [Receiver(name: "1")]) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 1, into: e, forceColumn: 0); assertNothingLeftSounding(e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertTrue(notes.contains(60), "lane 0 (FWD), ord=0 → riff step 0 → rank 1 → the lowest pool note")
        XCTAssertTrue(notes.contains(72), "lane 1 (REV), ord=0 → riff step 3 → rank 4 → the highest pool note — the SAME shared pattern read from a different direction, independently per lane")
    }
    // SUPERSEDES "...WalksAndStaysInPool" (Paul 2026-10-13 ferry, "Remove": "The DRUNK option") — DRUNK is
    // no longer one of Euclideous's own reachable WALK directions, so it no longer wanders (it isn't a
    // real random walk any more in this engine path — `riffStepAt`'s own exhaustive `.drunk` arm, kept
    // only for Swift's switch exhaustiveness, resolves it to the plain forward position). This is now a
    // DECODE-SAFETY guard, not a walk-behaviour one: an OLD saved doc that still carries `riffDir: .drunk`
    // on a Euclideous lane must keep sounding sensibly (bounded to the held pool, not silent, not a crash)
    // rather than factory-resetting or going dead — DRUNK is deliberately kept decode-only, never deleted
    // from the model, for exactly this reason.
    func testEuclidLineUseRiffDrunkIsNowRetiredButDecodesToASensibleForwardWalk() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, useRiff: true, riffDir: .drunk, riffDirBias: 0)]
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, receivers: [Receiver(name: "1")]) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord(pool), beats: 4, into: e); assertNothingLeftSounding(e)
        let notes = e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertFalse(notes.isEmpty, "a retired-but-decoded DRUNK lane must still produce real strikes, not silently do nothing")
        XCTAssertTrue(notes.allSatisfy { pool.contains(UInt8($0)) }, "every note must still come from the held pool")
    }
    // PER-LANE I/O (Paul 2026-10-08) SUPERSEDES this test's original premise — the riff was once hardcoded to
    // a FIXED separate receiver (index 0, "receiver 1"), independent of any lane. It now instead FOLLOWS
    // LANE 1's (array index 0's) own sourceMode, whatever that happens to be — so riff and "the lanes pool"
    // CAN still diverge, just not for the old fixed reason. Rewritten (not deleted) to prove the still-true
    // ONE GLOBAL SOURCE (Paul 2026-10-12, 2nd same-day ferry) — SUPERSEDES the per-lane independence this
    // test used to assert by name ("governed by EACH lane's own source, not lane 1's"). The per-lane
    // `EuclidLine.sourceMode` is now decode-only; a single page-level `PluginState.euclideousNoteSource`
    // feeds EVERY lane — plain-pick and riff-fed alike — from the identical pool. Rewritten to prove exactly
    // that, in two parts: (1) every lane reads the ONE global pool regardless of its own STALE per-lane
    // field (lane 0 still carries `.chords`, lane 1 still carries `.midi`, from before the migration — both
    // values are now inert and must have zero effect); (2) flipping the one global knob moves EVERY lane's
    // output together, proving it's genuinely shared state, not an accidental coincidence of lane 0 and
    // lane 1 happening to agree. Rank 2 is kept (not 1) so a one-note MIDI pool's FOLD-wrap (90→102) and a
    // 3-note CHORDS pool's direct rank-2 lookup (52) land on two different, easily distinguished values.
    func testEuclideousAllLanesShareOneGlobalSourceIgnoringAnyStalePerLaneValue() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [2])
        c.paramsA.euclidLines = [
            EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, sourceMode: .chords),   // stale — now inert
            EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: true, sourceMode: .midi),     // stale — now inert
        ]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  var cell = Cell(machineID: "gold", buses: [.a]); cell.inputReceiver = 3
                                  s.cells[0][Snap.euclideousRow] = cell
                                  return s }()])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4", channel: 2)]
        st.euclideousKeyRoot = 0; st.euclideousKeyType = .major
        st.euclideousChords = { var m = MachineParams(); m.chordsDegrees = [0]; m.chordsSteps = 1; return m }()   // C major tonic triad, ascending [48, 52, 55]
        let pool = NotePool()
        pool.noteOn(90, velocity: 100, channel: 1)

        // (1) Global source = MIDI — both lanes must read the ONE live note, ignoring their own stale fields.
        var stMidi = st; stMidi.euclideousNoteSource = .midi
        let e1 = RecordingEmitter(); run(SnapshotBuilder.build(from: stMidi), pool, beats: 1, into: e1, forceColumn: 0)
        assertNothingLeftSounding(e1)
        let notesMidi = Set(e1.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertTrue(notesMidi.contains(90), "lane 0's .low pick must read the global MIDI pool directly, despite its own stale sourceMode: .chords")
        XCTAssertTrue(notesMidi.contains(102), "the riff lane must FOLD-wrap rank 2 against the SAME one-note MIDI pool (90→102), not a separate 'its own' pool")
        XCTAssertFalse(notesMidi.contains(48) || notesMidi.contains(52), "neither lane may read the stale CHORDS pool once the global source is MIDI")

        // (2) Flip the ONE knob to CHORDS — both lanes must move together, proving one shared source, not
        // two lanes that merely happened to agree in part (1).
        var stChords = st; stChords.euclideousNoteSource = .chords
        let e2 = RecordingEmitter(); run(SnapshotBuilder.build(from: stChords), pool, beats: 1, into: e2, forceColumn: 0)
        assertNothingLeftSounding(e2)
        let notesChords = Set(e2.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertTrue(notesChords.contains(48), "lane 0's .low pick must now read the chord generator's lowest note")
        XCTAssertTrue(notesChords.contains(52), "the riff lane's rank 2 must now resolve directly against the 3-note chord pool (52), not FOLD-wrap a 1-note MIDI pool (102)")
        XCTAssertFalse(notesChords.contains(90) || notesChords.contains(102), "neither lane may still read the live MIDI note once the global source is CHORDS")
    }
    // MIDI IN MUST BE LITERALLY LIVE (Paul 2026-10-09: "it's playing even when it doesn't have MIDI being
    // plumbed in"). Traced to `emitGeneratorRow`'s own `pool` local, shadowed at the function's top by
    // `effectivePool(for: cell, live: livePool)` — the GENERIC per-cell self-arm/latch substitution every
    // regular grid cell correctly gets. Euclideous's per-lane MIDI fill was reading THIS shadowed `pool`
    // instead of the function's own un-substituted `livePool` parameter — so when the cell's hardcoded
    // receiver 4 happens to be configured as a self-arming door (SCALE/CHORD/PIANO), `effectivePool` silently
    // swapped in the door's own GENERATED content, with zero relationship to any actually-incoming MIDI
    // message. A receiver 4 configured as a CHORD door (which self-arms UNCONDITIONALLY, per
    // `computeEffectiveLatchMask`) with a genuinely EMPTY live pool must be silent through MIDI IN — not
    // sounding the door's own generated chord — while a real live note on the same receiver must still sound,
    // proving this isn't "MIDI IN never works," just "MIDI IN no longer reads a self-armed substitute."
    func testEuclideousMidiInReadsOnlyGenuinelyLiveNotesNotASelfArmedDoor() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  var cell = Cell(machineID: "gold", buses: [.a]); cell.inputReceiver = 3
                                  s.cells[0][Snap.euclideousRow] = cell
                                  return s }()])
        // ONE GLOBAL SOURCE (2026-10-12, 2nd same-day ferry) — the per-lane `sourceMode:` above is now
        // decode-only; the real knob is this page-level field, which these low-level Router tests (built
        // directly against a Machine/PluginState, bypassing BuildPage's own `euclideousLines` composition)
        // must set explicitly to exercise MIDI mode.
        st.euclideousNoteSource = .midi
        var chordDoor = Receiver(name: "4"); chordDoor.doorMode = .chord   // self-arms unconditionally, generates its own progression
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), chordDoor]
        // GENUINELY EMPTY — nothing played at all, the literal "no MIDI plumbed in" case.
        let e1 = RecordingEmitter(); run(SnapshotBuilder.build(from: st), NotePool(), beats: 1, into: e1, forceColumn: 0)
        assertNothingLeftSounding(e1)
        XCTAssertTrue(e1.ons.filter { $0.cable == 1 }.isEmpty, "MIDI IN must stay silent with nothing actually played, even though receiver 4 is a self-arming CHORD door that would otherwise generate its own notes")
        // A REAL live note on the same receiver must still sound — proving this isn't "MIDI IN never works."
        let pool2 = NotePool(); pool2.noteOn(67, velocity: 100, channel: 0)
        let e2 = RecordingEmitter(); run(SnapshotBuilder.build(from: st), pool2, beats: 1, into: e2, forceColumn: 0)
        assertNothingLeftSounding(e2)
        XCTAssertTrue(e2.ons.filter { $0.cable == 1 }.contains { Int($0.note) == 67 }, "a genuinely live note on receiver 4 must still sound through MIDI IN")
    }

    // HOLD/LATCH (Paul 2026-10-20) — a page-level behavioural port of the door graph's chord-detect-and-
    // replace / note-toggle-accumulation onto Euclideous's own ONE GLOBAL pool (Router.swift's `.euclid`
    // `case .midi:` branch). Dense pulses=1/steps=1 at a fast rate + `noteSel: .low` (the SAME proven fixture
    // `testEuclideousMidiInReadsOnlyGenuinelyLiveNotesNotASelfArmedDoor` above already uses) — one note at a
    // time sidesteps any question of whether a given pick mode strikes a whole chord per hit, which isn't
    // what this feature is testing. One shared `RecordingEmitter` + one continuously-driven `Router` (not
    // `run`, which tears down after one call) across all phases, sliced by sample time, so the final
    // `assertNothingLeftSounding` check still covers the WHOLE run's note lifecycle, not just one phase's.
    private func euclideousHoldLatchFixture(mode: EuclideousHoldLatchMode?) -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, rate: .r1_16, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        st.euclideousNoteSource = .midi
        st.euclideousHoldLatchMode = mode
        return SnapshotBuilder.build(from: st)
    }
    func testEuclideousHoldSustainsAfterReleaseAndReplacesOnANewChord() {
        let box = euclideousHoldLatchFixture(mode: .hold)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func drive(_ pool: NotePool, windows: Int) -> (Int64, Int64) {
            let start = Int64(ts)
            for _ in 0..<windows {
                router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                               sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += windowBeats; ts += Double(frames)
            }
            return (start, Int64(ts))
        }
        let (aStart, aEnd) = drive(chord([60]), windows: 8)                // HELD: mirrors live, like `nil`
        let (_, bEnd) = drive(NotePool(), windows: 8)                      // RELEASED: HOLD sustains the last note
        let (_, cEnd) = drive(chord([67]), windows: 8)                    // A GENUINELY NEW note: HOLD replaces
        router.process(box: box, pool: chord([67]), playing: false, beatPos: beat, tempo: tempo,   // stop edge → flush
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        func notes(_ lo: Int64, _ hi: Int64) -> Set<Int> { Set(e.ons.filter { $0.cable == 1 && $0.sample >= lo && $0.sample < hi }.map { Int($0.note) }) }
        XCTAssertEqual(notes(aStart, aEnd), [60], "held note sounds live")
        XCTAssertEqual(notes(aEnd, bEnd), [60], "HOLD sustains the last note after every key is released")
        XCTAssertEqual(notes(bEnd, cEnd), [67], "a genuinely new note replaces the held one, not layers onto it")
        assertNothingLeftSounding(e)
    }
    func testEuclideousLatchTogglesMembershipAndIgnoresNoteOff() {
        let box = euclideousHoldLatchFixture(mode: .latch)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func drive(_ pool: NotePool, windows: Int) -> (Int64, Int64) {
            let start = Int64(ts)
            for _ in 0..<windows {
                router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                               sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += windowBeats; ts += Double(frames)
            }
            return (start, Int64(ts))
        }
        _ = drive(chord([60]), windows: 8)                                 // PRESS 60 → a rising edge → toggled IN
        let (bStart, bEnd) = drive(NotePool(), windows: 8)                 // RELEASE 60 → LATCH ignores note-off entirely
        let (cStart, cEnd) = drive(chord([60]), windows: 8)                // PRESS 60 AGAIN → a NEW rising edge → toggled OUT
        router.process(box: box, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo,   // stop edge → flush
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        func notes(_ lo: Int64, _ hi: Int64) -> Set<Int> { Set(e.ons.filter { $0.cable == 1 && $0.sample >= lo && $0.sample < hi }.map { Int($0.note) }) }
        XCTAssertEqual(notes(bStart, bEnd), [60], "a released note stays latched in, ignoring note-off")
        XCTAssertTrue(notes(cStart, cEnd).isEmpty, "re-pressing an already-latched note is a NEW rising edge — toggles it back out")
        assertNothingLeftSounding(e)
    }
    func testEuclideousHoldLatchResetsOnModeSwitchAndTransportRestart() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, rate: .r1_16, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        st.euclideousNoteSource = .midi
        st.euclideousHoldLatchMode = .hold
        let holdBox = SnapshotBuilder.build(from: st)
        st.euclideousHoldLatchMode = .latch
        let latchBox = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func drive(_ box: SnapshotBox, _ pool: NotePool, windows: Int) -> (Int64, Int64) {
            let start = Int64(ts)
            for _ in 0..<windows {
                router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                               sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += windowBeats; ts += Double(frames)
            }
            return (start, Int64(ts))
        }
        _ = drive(holdBox, chord([60, 64]), windows: 8)                   // HOLD freezes [60, 64]
        _ = drive(holdBox, NotePool(), windows: 8)                        // released — still sustaining [60, 64]
        // SWITCH to LATCH with nothing currently played: a stale HOLD-frozen [60, 64] must NOT leak into LATCH's fresh set.
        let (latchStart, _) = drive(latchBox, NotePool(), windows: 8)
        router.process(box: latchBox, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo,
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        let afterSwitch = Set(e.ons.filter { $0.cable == 1 && $0.sample >= latchStart }.map { Int($0.note) })
        XCTAssertTrue(afterSwitch.isEmpty, "a mode switch must drop the previous mode's frozen/latched notes, not carry them over: got \(afterSwitch)")
        assertNothingLeftSounding(e)
    }
    // REGRESSION (adversarial review, 2026-10-21): the reset-on-mode-change check used to live inside
    // `case .midi:`, so it never ran while the source was CHORDS/KEY — leaving the frozen pool from before
    // the detour to resume unchanged the moment the page switched back to MIDI IN with HOLD still the
    // stored mode, even though nothing is currently held.
    // NOTE: the CHORDS-phase pool is non-empty (`chord([72])`, unrelated to the HOLD'd note) — this
    // predates the `euclideousGeneratedSourceActive` fix just below (2026-10-21), kept so this test still
    // passes an honest `pool.count > 0` regardless of which guard condition is doing the letting-through.
    func testEuclideousHoldDoesNotResumeAStalePoolAfterASourceDetourThroughChords() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, rate: .r1_16, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        st.euclideousNoteSource = .midi
        st.euclideousHoldLatchMode = .hold
        let midiHoldBox = SnapshotBuilder.build(from: st)
        st.euclideousNoteSource = .chords   // euclideousHoldLatchMode stays .hold in the DOCUMENT — SnapshotBuilder
                                            // forces the RESOLVED value to nil here; the stored field is untouched.
        let chordsBox = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func drive(_ box: SnapshotBox, _ pool: NotePool, windows: Int) -> (Int64, Int64) {
            let start = Int64(ts)
            for _ in 0..<windows {
                router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                               sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += windowBeats; ts += Double(frames)
            }
            return (start, Int64(ts))
        }
        _ = drive(midiHoldBox, chord([60]), windows: 8)         // HOLD freezes [60]
        _ = drive(chordsBox, chord([72]), windows: 8)           // detour through CHORDS (something else held, so the
                                                                 // row's own guard passes honestly) — must reset the stale pool
        // BACK to MIDI IN, nothing physically held: a stale, unreset pool would resume sounding 60 here.
        let (backStart, backEnd) = drive(midiHoldBox, NotePool(), windows: 8)
        router.process(box: midiHoldBox, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo,
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        let afterDetour = Set(e.ons.filter { $0.cable == 1 && $0.sample >= backStart && $0.sample < backEnd }.map { Int($0.note) })
        XCTAssertTrue(afterDetour.isEmpty, "a CHORDS/KEY detour must drop HOLD's frozen pool, not let it resume on return to MIDI IN: got \(afterDetour)")
        assertNothingLeftSounding(e)
    }
    // REGRESSION (found while writing the test above, 2026-10-21): `euclideousGeneratedSourceActive`
    // (Router.swift:3448, née `euclideousChordsActive`) used to read each lane's legacy per-lane
    // `sourceModeResolved` instead of the page-level `euclideousNoteSourceResolved` — a CHORDS or KEY
    // session with GENUINELY nothing held anywhere (no receivers, no 8x8-State latch, empty pool) fell
    // through the "nothing held, skip the row" guard and went silent, even though both sources generate
    // their own content unconditionally. No existing test caught it: every other CHORDS/KEY RouterTest
    // passes a non-empty pool incidentally.
    func testEuclideousChordsAndKeyPlayWithGenuinelyNothingHeldAnywhere() {
        func fixture(source: EuclideousLaneSource) -> SnapshotBox {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, rate: .r1_16, sourceMode: .midi)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                 scenes: [{ var s = SceneState.empty()
                                     s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                     return s }()])
            st.euclideousNoteSource = source
            st.euclideousKeyRoot = 0; st.euclideousKeyType = .major
            return SnapshotBuilder.build(from: st)
        }
        let eChords = RecordingEmitter()
        run(fixture(source: .chords), NotePool(), beats: 2, into: eChords, forceColumn: 0)
        assertNothingLeftSounding(eChords)
        XCTAssertFalse(eChords.ons.filter { $0.cable == 1 }.isEmpty, "CHORDS must keep generating with truly nothing held anywhere in the document")
        let eKey = RecordingEmitter()
        run(fixture(source: .key), NotePool(), beats: 2, into: eKey, forceColumn: 0)
        assertNothingLeftSounding(eKey)
        XCTAssertFalse(eKey.ons.filter { $0.cable == 1 }.isEmpty, "KEY must keep generating with truly nothing held anywhere in the document")
    }


    // MARK: - SAMPLE-ACCURATE ONSETS (Paul 2026-10-18) — the "odd timing" investigation.
    //
    // A recorded clip of a 16-hits-on-16-steps lane at 1/16, 110 BPM, showed onsets spaced 113/151 MIDI
    // ticks apart (long gap every 5th hit) instead of a flat 120, and note durations of exactly 75 or 113
    // instead of a flat 108 — AUDIBLE on device, so not a recording artefact. Every one of those four
    // numbers is an integer multiple of ONE RENDER BUFFER (2048 frames @ 48kHz = 42.67ms = 37.55 ticks:
    // 3, 4, 2 and 3 buffers respectively), and a 1/16 at 110 BPM is 3.196 buffers — so four steps snapping
    // DOWN to 3 buffers and the fifth absorbing the accumulated 0.196 reproduces the observed pattern
    // exactly. This test pins the engine's half of that: whatever the host then does with the timestamps,
    // Router must emit each onset at its own exact SAMPLE, never rounded to the block edge.
    //
    // Deliberately NOT a contract test (this file's header warns the others avoid "exact sample
    // arithmetic"): exact sample arithmetic is the entire point here.
    func testEuclideousOnsetsAreSampleAccurateNotQuantizedToTheRenderBlock() {
        var c = Machine(machineID: "gold", type: .euclid)
        // Paul's lane 2, verbatim from the device screenshots: 16 hits on 16 steps, rate 1/16, gate 90%.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 16, steps: 16, noteSel: .low,
                                            gate: 0.9, enabled: true, rate: .r1_16, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        // 110 BPM / 48kHz / 2048 frames — the device's own numbers, not the suite's 120 default.
        _ = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 4, into: e,
                             forceColumn: 0, tempo: 110, sr: 48_000, frames: 2048)
        // ONE cable only: §7b emits every note twice (its own cable + the ALL cable 0), so an unfiltered
        // list has a zero-delta twin for every hit.
        let onsets = e.ons.filter { $0.cable == 1 }.map { $0.sample }.sorted()
        XCTAssertGreaterThan(onsets.count, 8, "expected a run of 1/16 hits to measure")
        // A 1/16 at 110 BPM = 0.25 beat = 0.25 * 60/110 * 48000 = 6545.45 samples.
        let expected = 0.25 * 60.0 / 110.0 * 48_000.0
        let deltas = (1..<onsets.count).map { Double(onsets[$0] - onsets[$0 - 1]) }
        for (i, d) in deltas.enumerated() {
            XCTAssertEqual(d, expected, accuracy: 2.0,
                           "onset \(i + 1) is \(d) samples after its predecessor, expected \(expected). "
                           + "A delta that is a MULTIPLE OF 2048 (\(d / 2048) blocks) means the onset was "
                           + "rounded to the render-block edge instead of placed at its own sample.")
        }
        // THE SAME CHECK FOR GATE (the clip's second reported symptom: durations of exactly 75 or 113 ticks
        // = 2 or 3 render blocks, instead of a flat 108 = 90% of a 1/16). If note-OFFs are sample-accurate
        // here too, the gate is not broken either — both symptoms are one downstream quantisation.
        let offs = e.offs.filter { $0.cable == 1 }.map { $0.sample }.sorted()
        let expectedGate = 0.9 * 0.25 * 60.0 / 110.0 * 48_000.0
        for (i, on) in onsets.enumerated() where i < offs.count {
            let dur = Double(offs[i] - on)
            XCTAssertEqual(dur, expectedGate, accuracy: 2.0,
                           "note \(i) lasts \(dur) samples, expected \(expectedGate) (GATE 90% of a 1/16). "
                           + "A duration that is a MULTIPLE OF 2048 (\(dur / 2048) blocks) means the note-off "
                           + "was rounded to the render-block edge.")
        }
    }


    /// HARDENING SWEEP for the test above (Paul 2026-10-18, "anything to firm things up?"). The single-case
    /// test proves sample accuracy at ONE configuration and with `forceColumn: 0`, which BYPASSES the
    /// column-lap gate entirely — so on its own it says nothing about block sizes where a step spans a
    /// different number of blocks, nor about the gate path that a real cell actually goes through. This
    /// sweeps buffer × tempo × rate, and runs the column gate BOTH ways. 4096 frames is deliberately
    /// included: at 110 BPM one 4096-frame block is 0.156 beat, LONGER than a 1/32 step, so it exercises the
    /// `firstTick...lastT` loop finding several ticks in one block — a different path from the usual
    /// at-most-one.
    func testEuclideousOnsetSampleAccuracyHoldsAcrossBuffersTemposAndRates() {
        for frames in [UInt32(256), 512, 1024, 2048, 4096] {
            for tempo in [100.0, 110.0, 120.0, 128.5] {
                for (rate, rateBeats) in [(ArpRate.r1_8, 0.5), (.r1_16, 0.25), (.r1_32, 0.125)] {
                    for forced in [0, -1] {
                        var c = Machine(machineID: "gold", type: .euclid)
                        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 16, steps: 16, noteSel: .low,
                                                            gate: 0.9, enabled: true, rate: rate, sourceMode: .midi)]
                        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                             scenes: [{ var s = SceneState.empty()
                                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                                 return s }()])
                        st.euclideousNoteSource = .midi
                        let e = RecordingEmitter()
                        _ = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 4, into: e,
                                             forceColumn: forced, tempo: tempo, sr: 48_000, frames: frames)
                        let onsets = e.ons.filter { $0.cable == 1 }.map { $0.sample }.sorted()
                        guard onsets.count > 2 else { continue }   // a gated column can yield too few to measure
                        let expected = rateBeats * 60.0 / tempo * 48_000.0
                        let label = "\(frames)fr @ \(tempo)BPM, rate \(rate.rawValue), forceColumn \(forced)"
                        for i in 1..<onsets.count {
                            let d = Double(onsets[i] - onsets[i - 1])
                            // A gated run can legitimately show ONE long gap where the cell's column comes
                            // back round; only consecutive-within-a-column spacing is asserted.
                            guard d < expected * 1.5 else { continue }
                            XCTAssertEqual(d, expected, accuracy: 2.0,
                                           "\(label): onset \(i) sits \(d) samples after its predecessor, "
                                           + "expected \(expected) — \(d / Double(frames)) blocks.")
                        }
                    }
                }
            }
        }
    }

    // MARK: - NOTE VIEW (Paul 2026-10-10 ferry, "note view, phase 1") — the new per-lane event queue
    // `Router.drainEuclideousNoteViewEvents()` posts. All 10 tests here use `runKeepingRouter` (not `run`)
    // specifically to poll the drained queue afterward, same precedent as the EUCLID beacon's own tests.

    func testEuclideousNoteViewPlainHitPostsFinalTransposedOctaveShiftedPitch() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.transpose = 2
        // sourceMode: .midi explicit — see the ferry-default-flip note above (testEuclideousNoteViewFillUsesTheLanesPlainOctaveNotRiffOctave).
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, octave: 1, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        st.euclideousNoteSource = .midi   // one global source (2026-10-12) — the per-lane field above is decode-only now
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 1, into: e, forceColumn: 0)
        let events = router.drainEuclideousNoteViewEvents()
        XCTAssertEqual(events.count, 4, "always 4 lanes, regardless of how many actually posted")
        guard let ev = events[0].first else { return XCTFail("lane 0 should have posted a hit event") }
        XCTAssertEqual(ev.kind, 0)
        XCTAssertEqual(ev.notes, [UInt8(74)], "60 (held) + transpose(2) + 12×octave(1) = 74 — the EXACT pitch strikeOne's own n = rawNote+transpose+12*octave sends, per §5.3")
    }
    // RETIRED/REWRITTEN (Paul 2026-10-13, "lit notes plus the riff" ferry — the 2nd same-day ferry): FILL no
    // longer resolves ANY distinct riff-layer pitch at all (Q1's resolution: "nothing extra — lit notes
    // only") — the old `noteSel`-driven "FILL uses the lane's own plain NOTE/OCT pick" mechanism this test
    // exercised is gone entirely, superseded by the lit-notes layer. Renamed + rewritten to the new, still-
    // meaningful claim: a FILL-rest hit sounds exactly the lit note(s), at THEIR OWN `octave` — completely
    // independent of `riffOctave`, which no longer has anything to contribute on a FILL tick.
    func testEuclideousNoteViewFillSoundsOnlyTheLitNoteAtItsOwnOctave() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [0])   // always a rest
        // sourceMode: .midi explicit — the melody pop-up ferry (2026-10-10 §2.2) flipped the nil-default
        // to KEY; this test is about octave handling, not source mode, so pin MIDI to keep reading the
        // held chord directly, unaffected by the default change.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, octave: 2,
                                             useRiff: false, litNotes: 0b0000_0001, riffOn: true, riffOctave: -1, sourceMode: .midi, riffOnRest: .fill)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        st.euclideousNoteSource = .midi   // one global source (2026-10-12) — the per-lane field above is decode-only now
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 1, into: e, forceColumn: 0)
        let events = router.drainEuclideousNoteViewEvents()
        guard let ev = events[0].first else { return XCTFail("FILL should post a normal hit event — the lit note sounds") }
        XCTAssertEqual(ev.kind, 0, "FILL shows as a normal hit, not a rest-flash")
        XCTAssertEqual(ev.notes, [UInt8(84)], "60 + 12×octave(2) = 84 — the lit note's own octave; riffOctave(-1) contributes nothing on a FILL tick (no distinct riff pitch exists anymore)")
        XCTAssertFalse(ev.hasRiffNote, "FILL never produces a distinct riff pitch — notes[0] is the lit note, not a riff note")
    }
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry) — Acceptance scenarios, each a
    // direct engine-level proof of the ferry's own literal worked examples.
    func testEuclideousLitNotesSoundEveryHitWithRiffOff() {
        // Acceptance 1: "Notes only: light C3 and G3 with the riff off. Every hit plays C3 and G3."
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 4, useRiff: false, litNotes: 0b0000_0011, riffOn: false, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi   // page-level field — the per-line sourceMode above is decode-only
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([48, 55, 60]), beats: 2, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) }), [48, 55], "both lit ranks (1→C3/48, 2→G3/55) sound every hit; the un-lit rank 3 (60) never strikes")
    }
    func testEuclideousRiffAndLitNoteDedupToOneStrikeWhenPitchesCoincide() {
        // Acceptance 2: "Riff added: tap FWD. Every hit plays C3, G3 and the riff note. Where the riff
        // note is C3 or G3, that pitch sounds once."
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])   // always rank 1 → pool[0] → 48 (C3), coincides with the lit rank-1 button
        // notesWhen: PLAYS only — the riff reads columns 2-8 (rests) after column 1, and a lane built in this build plays its lit notes on rest hits too (WHEN RESTS); this test is about
        // the coinciding pitch on the hits where the riff plays.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: false, litNotes: 0b0000_0011, riffOn: true, sourceMode: .midi, notesWhen: 0b01)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi   // page-level field — the per-line sourceMode above is decode-only
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([48, 55, 60]), beats: 1, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertEqual(Set(ons), [48, 55], "the merged set is {48,55} — the riff's own rank-1 pitch coincides with the lit rank-1 pitch")
        XCTAssertEqual(ons.filter { $0 == 48 }.count, 1, "the coincident pitch gets exactly ONE note-on, not two")
    }
    func testEuclideousNothingLitAndRiffOffIsCompletelySilent() {
        // Acceptance 7: "Silent lane: unlight everything with the riff off. The lane is silent..."
        var c = Machine(machineID: "gold", type: .euclid)
        // litNotes EXPLICITLY 0 (not left nil) — a bare `useRiff: false` with no further fields migrates
        // `noteSelResolved` to its own `.all` fallback (pick==nil⇒.all), which `litMigrated`'s own "any
        // other value" branch turns into "1 lit, logged" — the genuinely-fresh "nothing lit" shortcut only
        // applies when NOTHING, including useRiff, has ever been touched (confirmed by reading `litMigrated`'s
        // own guard) — explicit fields are the honest way to request "nothing lit" from a touched line.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 4, useRiff: false, litNotes: 0, riffOn: false, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi   // page-level field (harmless either way here — silence holds
        // regardless of which pool is read — but set explicitly so this test doesn't silently rely on that
        // coincidence, matching the fix applied to its sibling Acceptance tests above).
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60, 62, 64]), beats: 2, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "nothing lit, riff off — the lane never strikes at all")
    }
    func testEuclideousOctaveRaisesBothLayers() {
        // Acceptance 8, first half: "OCT +1 raises both layers."
        func notesStruck(octave: Int, riffOctave: Int) -> Set<Int> {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, octave: octave, useRiff: false, litNotes: 0b0000_0010, riffOn: true, riffOctave: riffOctave, sourceMode: .midi)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
            st.euclideousNoteSource = .midi   // page-level field — the per-line sourceMode above is decode-only
            let e = RecordingEmitter()
            run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 1, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        }
        XCTAssertEqual(notesStruck(octave: 0, riffOctave: 0), [60, 64], "riff rank1→60, lit rank2→64, no shift")
        XCTAssertEqual(notesStruck(octave: 1, riffOctave: 1), [72, 76], "OCT +1 raises BOTH the riff pitch and the lit pitch by exactly one octave")
    }
    func testEuclideousTransposeMovesOnlyTheRiffPitch() {
        // Acceptance 8, second half: "TRANS +2 moves only the riff note" (here +1, for a cleaner coincidence check).
        func notesStruck(transpose: Int) -> Set<Int> {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: false, litNotes: 0b0000_0010, riffOn: true, sourceMode: .midi, melodyTranspose: transpose)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
            st.euclideousNoteSource = .midi   // page-level field — the per-line sourceMode above is decode-only
            let e = RecordingEmitter()
            run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 1, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        }
        XCTAssertEqual(notesStruck(transpose: 0), [60, 64], "riff rank1→60, lit rank2→64")
        XCTAssertEqual(notesStruck(transpose: 1), [64], "TRANS +1 moves the riff from rank1(60) to rank2(64) — now coinciding with the UNMOVED lit pitch (still rank2/64), deduping to one note; the lit pitch itself never moved")
    }
    func testEuclideousStuckNoteStressRapidLitOctaveRiffToggling() {
        // Acceptance 10: "Stuck-note stress test: toggle notes, OCT and the riff rapidly... No notes are
        // left hanging." Drives the SAME router instance through many consecutive renders, flipping
        // litNotes/octave/riffOn between every call — mirrors this file's own established mid-session-
        // parameter-change technique (see testEuclideousRiffLengthShrinkMidSessionConfinesNotesToTheNew
        // Window's identical `runKeepingRouter` + repeated `router.process()` shape).
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func lineFor(_ tick: Int) -> EuclidLine {
            let lit = UInt8(1 << (tick % 8))
            return EuclidLine(target: 0, pulses: 1, steps: 1, octave: (tick % 5) - 2, rate: .r1_32,
                               useRiff: false, litNotes: lit, riffOn: tick % 2 == 0, riffOctave: (tick % 3) - 1,
                               sourceMode: .midi, riffLength: 8, melodyTranspose: tick % 4)
        }
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [lineFor(0)]
        let box0 = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 1024
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        let router = runKeepingRouter(box0, chord(pool), beats: 0.2, into: e, forceColumn: 0, tempo: tempo, sr: sr, frames: frames)
        var diag = KernelDiag()
        var beat = 0.2, ts = 0.2 / tempo * 60.0 * sr
        for tick in 1...60 {
            c.paramsA.euclidLines = [lineFor(tick)]
            let box1 = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]) }
            router.process(box: box1, pool: chord(pool), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]) },
                       pool: chord(pool), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }
    func testEuclideousNoteViewRiffRealRankFoldsRiffOctaveOnceNotTwice() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])   // always rank 1 (a real note)
        // sourceMode: .midi explicit — see the ferry-default-flip note above.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: true, riffOctave: 1, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        st.euclideousNoteSource = .midi   // one global source (2026-10-12) — the per-lane field above is decode-only now
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 1, into: e, forceColumn: 0)
        let events = router.drainEuclideousNoteViewEvents()
        guard let ev = events[0].first else { return XCTFail("riff rank 1 should post a hit event") }
        XCTAssertEqual(ev.notes, [UInt8(72)], "riffResolve already folds +12×riffOctave(1) into the resolved note (60→72) BEFORE strikeChord's own octave:0 — must not be re-applied a second time (which would read 84)")
    }
    func testEuclideousNoteViewOnRestSkipPostsARestFlashAndNothingElse() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 2, ranks: [1, 0])   // step 0 real, step 1 a rest
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 2, steps: 2, rate: .r1_8, useRiff: true, riffOnRest: .skip)]
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        // 0.6 beats, not 1.0: at sub=0.5 the pattern's own 2-tick cycle would repeat exactly AT beat 1.0 —
        // a real window-boundary ambiguity this file's own standing lesson warns about (see
        // testEuclidDownbeatFiresOnAnUnalignedColumnBoundary). 0.6 safely covers ticks 0/0.5 only.
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 0.6, into: e, forceColumn: 0)
        let kinds = router.drainEuclideousNoteViewEvents()[0].map { $0.kind }
        XCTAssertEqual(kinds, [0, 2], "step 0 a real hit (kind 0), step 1 a rest-flash (kind 2) — SKIP never posts a second hit")
    }
    func testEuclideousNoteViewOnRestTiePostsNoSecondEventTheOriginalHitCoversIt() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 2, ranks: [1, 0])   // step 0 real, step 1 a rest (tied through)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 2, steps: 2, rate: .r1_8, useRiff: true, riffOnRest: .tie)]
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 0.6, into: e, forceColumn: 0)   // see the SKIP test above for why not 1.0
        let laneEvents = router.drainEuclideousNoteViewEvents()[0]
        XCTAssertEqual(laneEvents.count, 1, "TIE must not post a second event for the rest step — only the original triggering hit, with its own gate already extended to cover it")
        guard let ev = laneEvents.first else { return }
        XCTAssertGreaterThan(ev.durationBeat, 0.5, "the tied hit's duration must cover its own gate PLUS the extra tick the rest step consumed (sub=0.5 beats at r1_8) — an un-tied hit's gate alone (~0.45 beats at the default 90% gate) would not clear this bar")
        // RE-CHECKED against the ferry's own literal §4.5 wording ("full brightness... fading FROM THE END
        // of the extended note" — genuinely different from §4.4's plain continuous fade): a tied hit posts
        // kind 3, not kind 0, so the UI can hold it at full brightness for its whole span instead of fading
        // it the moment it strikes.
        XCTAssertEqual(ev.kind, 3, "a hit that ties through a following rest must post as kind 3 (tied hit), not a plain kind-0 hit — the note box's brightness rule for the two is genuinely different per §4.5")
    }
    func testEuclideousNoteViewPlainHitWithNoTieIsNotMarkedAsTied() {
        // A direct contrast to the test above: the SAME riff real-rank path, but with no following rest to
        // tie through, must post the ordinary kind 0 — confirms kind 3 is specific to an ACTUAL extension,
        // not applied unconditionally to every riff-sourced hit.
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])   // always rank 1, never a rest to tie through
        // sourceMode: .midi explicit — see the ferry-default-flip note above. riffLength: 1 explicit too —
        // the melody pop-up ferry's LENGTH defaults to 8, decoupled from the shared pattern's own real
        // step count (1 here); left at the default, positions 1-7 would read as virtual rests beyond
        // `ranks.count`, producing an unintended TIE chain this test's own "no rest ever follows this
        // pattern" premise doesn't anticipate. Pinning LENGTH to the pattern's real size restores the
        // original, pre-LENGTH intent.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: true, sourceMode: .midi, riffOnRest: .tie, riffLength: 1)]
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 1, into: e, forceColumn: 0)
        guard let ev = router.drainEuclideousNoteViewEvents()[0].first else { return XCTFail("should have posted a hit") }
        XCTAssertEqual(ev.kind, 0, "no rest ever follows this pattern, so riffTieExtensionBeats is always 0 — this must stay an ordinary kind-0 hit")
    }
    func testEuclideousNoteViewMissSilentPostsNothing() {
        var c = Machine(machineID: "gold", type: .euclid)
        // missNoteSel left nil (the feature's own off switch) — a 1-of-2 pattern guarantees a real miss tick.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 2, noteSel: .low, rate: .r1_8)]
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 1, into: e, forceColumn: 0)
        let kinds = router.drainEuclideousNoteViewEvents()[0].map { $0.kind }
        XCTAssertFalse(kinds.contains(1), "an unconfigured MISS side must never post a miss-playing event")
    }
    // REWRITTEN (Paul 2026-10-10, "rhythm cards cleared of melody" ferry): this test used to assert the OLD
    // dual-voice behaviour — a configured `missNoteSel` posting its own kind-1 NOTE VIEW event on Euclideous's
    // row. That's now retired for Euclideous specifically: `missNoteSel` stays live on the shared model (the
    // regular, non-Euclideous BUILD-page EUCLID editor's own feature) but Router.swift's `!isEuclideousRow`
    // guard makes it unconditionally inert on Euclideous's own row, satisfying ferry §2.4's "ignore the old
    // miss-side settings" for an old doc that happens to carry one. Flipped to the opposite, now-correct
    // assertion — a stale `missNoteSel` on Euclideous's row must NEVER post kind 1 (or anything at all, since
    // this line's own `pulses:1/steps:2` already strikes one real hit and the kind-1 event was the only other
    // thing this configuration could ever produce).
    func testEuclideousNoteViewStaleMissNoteSelNeverPostsAMissEvent() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 2, noteSel: .low, missNoteSel: .low, rate: .r1_8)]
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 1, into: e, forceColumn: 0)
        let kinds = router.drainEuclideousNoteViewEvents()[0].map { $0.kind }
        XCTAssertFalse(kinds.contains(1), "a stale missNoteSel on Euclideous's own row must never post a miss-playing event — the !isEuclideousRow guard makes it inert")
    }
    func testEuclideousNoteViewRingKeepsNewestDropsOldestUnderABurst() {
        var c = Machine(machineID: "gold", type: .euclid)
        // pulses:2/steps:2 (dense, every tick a hit), NOT pulses:1/steps:1 — `runEuclidLine` clamps N to a
        // minimum of 2 (`max(2, min(16, nIn))`), so steps:1 silently becomes a 1-of-2 pattern (half the
        // ticks miss) — caught by this test itself under-counting (7, not 12+) on the first run, not by
        // inspection.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 2, steps: 2, noteSel: .low, rate: .r1_4)]   // every tick a hit, 1 beat apart
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        // 12.5 beats ≈ 12 ticks (beats 0...11) without ever draining in between — comfortably past the 8-slot ring.
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 12.5, into: e, forceColumn: 0)
        let laneEvents = router.drainEuclideousNoteViewEvents()[0]
        XCTAssertEqual(laneEvents.count, 8, "the ring is fixed-capacity 8 — a 12-event burst must not grow it")
        let onsets = laneEvents.map { $0.onsetBeat }
        XCTAssertEqual(onsets, onsets.sorted(), "surviving events stay oldest→newest")
        XCTAssertGreaterThan(onsets.first ?? 0, 2, "the oldest SURVIVING event must be well past tick 0 — the ring dropped the earliest ticks, not the latest")
    }
    func testEuclideousNoteViewNeverFiresForANonEuclideousRowCell() {
        // The SAME shared `runEuclidLine` also drives every ordinary EUCLID processor anywhere else in the
        // grid (confirmed by reading — `p.euclidLines` is populated even for a plain single-EUCLID cell).
        // A cell at ROW 0 (not Snap.euclideousRow) must NEVER write into this queue — otherwise an unrelated
        // EUCLID processor elsewhere in the user's grid would corrupt Euclideous's own NOTE VIEW display.
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .euclid)
            c.paramsA.euclidPulses = 1; c.paramsA.euclidSteps = 1; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        let router = runKeepingRouter(b, chord([60]), beats: 1, into: e, forceColumn: 0)
        XCTAssertGreaterThan(e.ons.count, 0, "sanity check — this cell really is striking notes on the wire")
        let events = router.drainEuclideousNoteViewEvents()
        XCTAssertTrue(events.allSatisfy { $0.isEmpty }, "a row-0 EUCLID cell must never post to the NOTE VIEW queue, which is reserved for Snap.euclideousRow")
    }
    func testEuclideousNoteViewRespectsMainOutGating() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low)]
        // MAIN OUT is set directly on the machine's OWN params (`MachineParams.mainOutMask`), not
        // `PluginState.euclideousMainOutMask` — traced, not guessed, after this test first failed its own
        // sanity check (the wire wasn't actually silenced): `PluginState.euclideousMainOutMask` is only the
        // PERSISTED copy; the real render path reads `SnapParams.mainOutMask`, which `SnapshotBuilder.swift`
        // resolves from the per-cell `MachineParams.mainOutMask` — and THAT is populated, for a real session,
        // by `BuildPage.swift`'s own live `@State` mirror during scene composition, a path this test (going
        // straight PluginState → SnapshotBuilder.build) never runs. Setting it directly on `c.paramsA` is
        // the correct way to reach `SnapParams.mainOutMask` without that UI-layer hop.
        c.paramsA.mainOutMask = 0
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60]), beats: 1, into: e, forceColumn: 0)
        XCTAssertTrue(e.ons.isEmpty, "sanity check — MAIN OUT 0 really does silence the wire")
        XCTAssertTrue(router.drainEuclideousNoteViewEvents()[0].isEmpty, "the note box must never show a note that MAIN OUT gating actually suppressed (§5.3)")
    }

    // TILT (Paul 2026-10-08): proves the field threads all the way through SnapshotBuilder→Router — Derivations-
    // Tests already proves the pure `euclidTiltPattern` function's own directionality in isolation; this
    // confirms EuclidLine.tilt actually reaches it. A dense K=4/N=16 pattern's average onset SAMPLE time over
    // one full cycle shifts earlier/later exactly as the pure function's own test already predicts.
    func testEuclidTiltShiftsTheAverageOnsetTimingDirectionally() {
        func avgOnsetSample(_ tilt: Double) -> Double {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 16, noteSel: .low, rate: .r1_16, tilt: tilt)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 4, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            let samples = e.ons.filter { $0.cable == 1 }.map { Double($0.sample) }
            return samples.reduce(0, +) / Double(samples.count)
        }
        let neg = avgOnsetSample(-1), zero = avgOnsetSample(0), pos = avgOnsetSample(1)
        XCTAssertLessThan(neg, zero, "negative tilt must pull the average onset EARLIER")
        XCTAssertGreaterThan(pos, zero, "positive tilt must pull the average onset LATER")
    }
    // PER-LANE I/O (Paul 2026-10-08) SUPERSEDES the old global `euclideousRiffSourceMidi` switch this test
    // used to set — riff's source now follows LANE 1's (array index 0's) own `sourceMode` directly.
    // REWRITTEN AGAIN (Paul 2026-10-09, 2nd report — "key does nothing"): KEY mode is no longer silent — it
    // now plays the page's own KEY+SCALE picker as a real pool (Router.swift's `.key` branch), a previously-
    // disclosed-but-unbuilt gap (§4.4 of the original rework spec) finally closed. Renamed + rewritten from
    // "yields empty pool" to the actual, opposite claim: real notes, from the SCALE (not live MIDI).
    func testEuclideousRiffKeyModeReadsTheScalePoolNotLiveMidi() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])   // rank 1 = the pool's own lowest note
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: true, sourceMode: .key)]   // lane 0 ("lane 1") KEY governs the riff it drives
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  var cell = Cell(machineID: "gold", buses: [.a]); cell.inputReceiver = 3
                                  s.cells[0][Snap.euclideousRow] = cell
                                  return s }()])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let pool = NotePool(); pool.noteOn(72, velocity: 100, channel: 0)   // real MIDI present — KEY mode must ignore it entirely
        let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), pool, beats: 1, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertFalse(notes.isEmpty, "KEY mode must now generate real notes from the page's own scale")
        XCTAssertFalse(notes.contains(72), "KEY mode must never sound the live MIDI note — it's independent of any held input")
        XCTAssertTrue(notes.contains(48), "rank 1 of the default (untouched KEY picker) C natural-minor pool is C3 = MIDI 48")
    }
    // PER-LANE I/O (Paul 2026-10-08) SUPERSEDES the old global `euclideousLanesSourceMidi` switch this test
    // used to set — each lane's own `sourceMode` governs it now.
    // REWRITTEN AGAIN (Paul 2026-10-09, 2nd report), same reason as the riff test above.
    func testEuclideousLanesKeyModeReadsTheScalePoolNotLiveMidi() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, sourceMode: .key)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  var cell = Cell(machineID: "gold", buses: [.a]); cell.inputReceiver = 3
                                  s.cells[0][Snap.euclideousRow] = cell
                                  return s }()])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let pool = NotePool(); pool.noteOn(60, velocity: 100, channel: 0)   // real MIDI present — must be ignored
        let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), pool, beats: 1, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertFalse(notes.isEmpty, "a lane's own sourceMode set to KEY must now sound the scale, not stay silent")
        XCTAssertFalse(notes.contains(60), "KEY mode must never sound the live MIDI note")
        XCTAssertEqual(notes, [48], "PICK LOW on the default C natural-minor pool strikes only its lowest note, C3 = MIDI 48")
    }
    // EUCLIDEOUS PAGE REWORK: `mainOutMask` is a GLOBAL master gate applied AFTER chopMask's full result, not
    // pre-masked into `base` — proven by two cases, a plain strike and a CHOP-ALT-routed one, since CHOP-ALT
    // builds its bus bit completely INDEPENDENT of `base` (`chopBusMask`'s own `alt ? altMask : 0`) — a
    // pre-mask-base implementation would pass case 1 but silently fail case 2. (A third, DEST-routed case was
    // attempted and deliberately dropped — see the comment inline below, right after case 2.)
    func testEuclideousMainOutMaskSuppressesPlainAndChopAltRoutedNotesAlike() {
        func plain(_ mainOutMask: UInt8) -> RecordingEmitter {
            var euclid = Machine(machineID: "gold", type: .euclid)
            euclid.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low)]
            euclid.paramsA.mainOutMask = mainOutMask
            let b = box(machines: machineIDs.map { $0 == "gold" ? euclid : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 1, into: e, forceColumn: 0); assertNothingLeftSounding(e); return e
        }
        XCTAssertFalse(plain(0b1111).ons.filter { $0.cable == 1 }.isEmpty, "bus A open — a plain strike (no CHOP/DEST) reaches it")
        XCTAssertTrue(plain(0b1110).ons.filter { $0.cable == 1 }.isEmpty, "bus A closed by MAIN OUT — a plain, uncomplicated strike must still be suppressed")

        func chopAlt(_ mainOutMask: UInt8) -> RecordingEmitter {
            var euclid = ProcessorSlot(type: .euclid)
            euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low)]
            euclid.params.mainOutMask = mainOutMask
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) {
                $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [euclid]
                    c.chop = Chop(mainMask: 0, altMask: 0xFF, altDest: [.b]); return c }()
            }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 1, into: e, forceColumn: 0); assertNothingLeftSounding(e); return e
        }
        XCTAssertFalse(chopAlt(0b1111).ons.filter { $0.cable == 2 }.isEmpty, "bus B open — the ALT-routed note reaches it")
        XCTAssertTrue(chopAlt(0b1101).ons.filter { $0.cable == 2 }.isEmpty, "bus B closed by MAIN OUT — an ALT-routed note (built independent of `base`) must still be suppressed")

        // A THIRD case (DEST-routed) was attempted and DROPPED, not silently skipped: `tbm` (the masked value)
        // only ever reaches emission on the NON-downstream path (`strikeChord`'s `else if tbm != 0` branch) —
        // a chain with a SECOND slot (needed to host a `.dest` processor at all, since DEST is a processor
        // TYPE, unlike CHOP which is a plain per-cell field) makes `hasDownstream` true, routing emission
        // through `emitDriverNote` instead, which resolves its OWN bus mask internally and never reads `tbm`/
        // `mainOutMask` at all. Confirmed this is NOT reachable by the real feature: Euclideous's own cell is
        // structurally always exactly ONE slot (the EUCLID processor itself — see strikeChord's own doc
        // comment, "EUCLID is structurally always the chain tail for Euclideous's one-slot cell"), so a DEST
        // slot can never coexist with EUCLID in that one real chain, and `mainOutMask` has no UI path to reach
        // any OTHER chain shape (it's only ever set via Euclideous's own fixed single-slot publish site,
        // BuildPage.swift). Extending `mainOutMask` into `emitDriverNote`'s own bus resolution — the core per-
        // note fold shared by every driver type with downstream processors (ARP/RIFF/STRUM/RATCHET/…) — would
        // be a materially bigger change than this rework asks for, to close a gap nothing can actually trigger.
        // Flagged honestly in the ferry acknowledgment rather than silently left untested or chased unscoped.
    }
    // RESET SPAN (Paul 2026-10-08, §2.2, built on Paul's direct follow-up instruction: "I want reset span to
    // be correctly implemented"): a GLOBAL control that re-anchors Euclideous's pattern/riff position every N
    // bars, computed as a LITERAL bar multiplier (`Double(bars) * cyc`) rather than routed through the
    // existing `spanLadderBeats` ladder — that ladder tops out at 8 bars (its n=64 case) with no slot for 16.
    // Proven here by EQUIVALENCE against the regular EUCLID processor's own already-tested `euclidSpanN=8`
    // case (also exactly 1 bar, confirmed via `testEuclidSpanReAnchorsThePattern`/line 289's own "spanN: 8 =
    // the whole row" comment) — both formulas read the SAME `cyc`, so if they're both genuinely "1 bar" the
    // two must produce byte-identical onset counts regardless of what `cyc` numerically is.
    func testEuclideousResetSpanOneBarReAnchorsThePatternEveryBar() {
        // WITNESS MECHANISM REWRITTEN (Paul 2026-10-13, "lit notes plus the riff" ferry): `noteSel: .cycle`
        // is no longer reachable from Euclideous's own melody resolution (lit notes/riffOn have replaced it
        // entire) — the original witness technique ("read the engine's own evolving `ord` via which pool
        // rank sounds") is still exactly what this test needs, just reached through the RIFF layer's FWD
        // walk instead: for HIT-mode advance (default) on an un-LOCKed (FREE, default) lane, `advOrd == ord`
        // precisely (confirmed by reading `runEuclidLine`'s own `advOrd` formula) — an 8-step shared riff
        // pattern `[1,2,3,4,5,6,7,8]` makes `rank = (ord mod 8) + 1`, the SAME shape `.cycle`'s own
        // `resolveEuclidPick` used to produce, so this remains a faithful, equivalent proof of reset-span's
        // effect on `ord` — not a weaker substitute.
        //
        // K=3,N=5 (cycleLen=5 ticks=2.5 beats at rate=r1_8) deliberately does NOT evenly divide the 8-tick/
        // 4-beat bar (stepRate=r1_8, Snap.cols=8) — a 4-of-8 pattern (this file's own usual go-to) ALREADY
        // naturally repeats every bar even with span OFF (8 ticks/cycle happens to equal 1 bar exactly), which
        // would make span's own effect invisible by construction, not absent — caught empirically while
        // building this test (the first draft used 4-of-8 and couldn't tell the two cases apart). A first
        // attempt compared raw onset COUNTS between one bar and two bars — wrong: a steady process doubles its
        // count over double the time regardless of phase-alignment, so count alone can't distinguish "replays
        // exactly" from "merely as dense." Comparing the actual SEQUENCE of struck pool-ranks is the real proof.
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func cyclePicksStruck(resetSpanBars: Int, beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            // sourceMode: .midi explicit — the melody pop-up ferry (2026-10-10 §2.2) flipped the nil-default to KEY.
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 5, rate: .r1_8,
                                                 useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty()
                                      s.stepRate = .r1_8
                                      s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                      return s }()])
            st.euclideousNoteSource = .midi   // one global source (2026-10-12) — the per-lane field above is decode-only now
            st.euclideousResetSpanBars = resetSpanBars
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        }
        let span1Bar = cyclePicksStruck(resetSpanBars: 1, beats: 3.9)
        let span2Bar = cyclePicksStruck(resetSpanBars: 1, beats: 7.9)
        let free1Bar = cyclePicksStruck(resetSpanBars: 0, beats: 3.9)
        let free2Bar = cyclePicksStruck(resetSpanBars: 0, beats: 7.9)
        XCTAssertFalse(span1Bar.isEmpty, "the pattern must actually strike something in one bar")
        XCTAssertEqual(Array(span2Bar.prefix(span1Bar.count)), span1Bar, "1 BAR: bar 2's CYCLE-pick sequence must exactly replay bar 1's — each bar hard-resets `ord` to 0, so the Nth hit of every bar reads the identical pool rank")
        XCTAssertEqual(Array(span2Bar.suffix(span1Bar.count)), span1Bar, "bar 2 itself must ALSO match bar 1 exactly, not merely share a common prefix")
        // NOTE: comparing against free2Bar's PREFIX would be trivial and prove nothing — the first N hits of
        // ANY fresh run start from ord=0 regardless of reset-span, so bar 1 always "matches itself" either way.
        // The real comparison is against free2Bar's SUFFIX (bar 2 proper) — self-caught before this test shipped,
        // not after: a first draft checked the prefix here and the assertion failed for the wrong reason.
        XCTAssertNotEqual(Array(free2Bar.suffix(free1Bar.count)), free1Bar, "FREE: `ord` keeps growing across the bar boundary — bar 2's CYCLE sequence must NOT replay bar 1's, since the two don't start from the same ordinal")
    }
    // SEQUENCER PANEL (2026-10-14 ferry §3) — RESET moves from one machine-wide bars-count to a PER-LANE
    // sequencer-steps count, re-anchored at `resetSteps * (LANES RATE in beats)` instead of a literal bar
    // multiplier. The ferry's own literal worked example: LANES RATE 1 BAR, a lane with resetSteps=4
    // restarts at (1-based) bars 1 and 5 of an 8-bar loop; resetSteps=2 restarts at bars 1/3/5/7. Proven by
    // the SAME equivalence technique as `testEuclideousResetSpanOneBarReAnchorsThePatternEveryBar` directly
    // above (comparing bar N's struck pool-rank sequence against bar 1's, via the riff walk's own `ord`).
    // LANES GRID (2026-10-18): the lane is a 3-of-8 at 1/8 — a lap is exactly one bar — so the pre-feature reset MIGRATES exactly (restart unit PASS = the
    // old step), and this pre-feature document must still restart on the old schedule.
    func testEuclideousPerLaneResetStepsReanchorsAtTheConfiguredPeriod() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func picksStruck(resetSteps: Int, beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            // RESTART CHAINS (2026-10-19): `resetSteps` no longer drives the real engine live — migrated-and-
            // pinned here, simulating the AVC resync tick this bare-Router test never runs (§12).
            c.paramsA.euclidLines = [migratedLine(EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                                 useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8,
                                                 resetSteps: resetSteps), legacyRate: .oneBar, legacyLen: 8)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty()
                                      s.stepRate = .r1_8
                                      s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                      return s }()])
            st.euclideousNoteSource = .midi
            st.euclideousLanesSeqRate = .oneBar   // the ferry's own literal "LANES RATE 1 BAR"
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        }
        let period4bar1 = picksStruck(resetSteps: 4, beats: 3.9)
        let period4throughBar5 = picksStruck(resetSteps: 4, beats: 19.9)
        XCTAssertFalse(period4bar1.isEmpty)
        XCTAssertEqual(Array(period4throughBar5.suffix(period4bar1.count)), period4bar1,
                       "resetSteps=4 re-anchors every 4 bars — bar 5 must replay bar 1's exact pick sequence")
        let period2bar1 = picksStruck(resetSteps: 2, beats: 3.9)
        XCTAssertFalse(period2bar1.isEmpty)
        for throughBeats in [11.9, 19.9, 27.9] {   // bars 3, 5, 7 — every odd bar, per resetSteps=2
            let throughN = picksStruck(resetSteps: 2, beats: throughBeats)
            XCTAssertEqual(Array(throughN.suffix(period2bar1.count)), period2bar1,
                           "resetSteps=2 re-anchors every 2 bars — bar \(Int(throughBeats / 4) + 1) must replay bar 1's exact pick sequence")
        }
    }
    // A SELF-AUDIT against the ferry's own raw text (2026-10-14) found the test above never exercises a
    // LANES LEN that ISN'T a multiple of resetSteps — the exact combination (LEN=8, resetSteps ∈ {1,2,4,8})
    // under which the first build's engine-level bug was completely invisible (it re-anchored purely from
    // absolute beat 0, ignoring LEN entirely — §5's literal "the count restarts when the sequence loops, so
    // the marks stay fixed" requires re-anchoring at the LANES sequencer's own lap boundary instead). Here
    // LEN=5 does NOT divide resetSteps=3: within one lap, restarts land at local steps 0 and 3 only; a NEW
    // lap begins at absolute step 5 (bar 6) and must restart FRESH there, even though the OLD unbounded
    // formula would still be mid-cycle (its own next restart wouldn't land until step 6/bar 7).
    // Paul's "engine fixes from a recorded clip" ferry (2026-10-14) §1: his recorded clip shows the riff
    // walk restarting only every 4 bars, not every bar, with both lanes' resetSteps set to 1 STEP and
    // LANES RATE 1 BAR. Investigated empirically (not just by reading) against the EXACT repro parameters —
    // RED (3 of 8 at 1/8) and BLUE (5 of 16 at 1/16), isolated and combined. All three confirm the per-lane
    // reset mechanism itself restarts correctly every bar for this exact setup; kept as permanent regression
    // coverage for the precise scenario reported, not just the abstract one above. The ONE way this exact
    // symptom DOES reproduce (confirmed by a throwaway probe, not kept as a test): `euclideousLanesSeqRate`
    // resolving to `.fourBars` instead of `.oneBar` — this restarts the per-lane mechanism correctly too,
    // just on a 4-bar period instead of 1, an exact match for the reported symptom. Could not confirm BY
    // READING why the real session's rate would resolve to fourBars rather than oneBar (every write/resolve
    // path checked reads oneBar correctly) — raised back to the design channel with a concrete ask: watch
    // whether the sequencer panel's own "STEP N OF LEN" readout advances once per bar or once per 4 bars.
    func testEuclideousRedIsolatedResetsEveryBarAtTheExactRepro() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func picksThroughBar(beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            // RESTART CHAINS (2026-10-19): migrated-and-pinned, simulating the AVC resync tick (§12).
            c.paramsA.euclidLines = [migratedLine(EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                                 useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8,
                                                 resetSteps: 1), legacyRate: .oneBar, legacyLen: 8)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty()
                                      s.stepRate = .r1_8
                                      s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                      return s }()])
            st.euclideousNoteSource = .midi
            st.euclideousLanesSeqOn = true
            st.euclideousLanesSeqRate = .oneBar
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        }
        let bar1 = picksThroughBar(beats: 3.9)
        let bar2 = picksThroughBar(beats: 7.9)
        XCTAssertFalse(bar1.isEmpty)
        XCTAssertEqual(Array(bar2.suffix(bar1.count)), bar1, "resetSteps=1 must restart every bar")
    }
    func testEuclideousBlueIsolatedResetsEveryBarAtTheExactRepro() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func picksThroughBar(beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            // RESTART CHAINS (2026-10-19): migrated-and-pinned, simulating the AVC resync tick (§12).
            c.paramsA.euclidLines = [migratedLine(EuclidLine(target: 0, pulses: 5, steps: 16, rate: .r1_16,
                                                 useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8,
                                                 resetSteps: 1), legacyRate: .oneBar, legacyLen: 8)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty()
                                      s.stepRate = .r1_8
                                      s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                      return s }()])
            st.euclideousNoteSource = .midi
            st.euclideousLanesSeqOn = true
            st.euclideousLanesSeqRate = .oneBar
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        }
        let bar1 = picksThroughBar(beats: 3.9)
        let bar2 = picksThroughBar(beats: 7.9)
        XCTAssertFalse(bar1.isEmpty)
        XCTAssertEqual(Array(bar2.suffix(bar1.count)), bar1, "resetSteps=1 must restart every bar")
    }
    func testEuclideousBothLanesTogetherResetEveryBarAtTheExactRepro() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func picksThroughBar(beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            // RESTART CHAINS (2026-10-19): migrated-and-pinned, simulating the AVC resync tick (§12).
            let red = migratedLine(EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                  useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8, resetSteps: 1), legacyRate: .oneBar, legacyLen: 8)
            let blue = migratedLine(EuclidLine(target: 0, pulses: 5, steps: 16, rate: .r1_16,
                                   useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8, resetSteps: 1), legacyRate: .oneBar, legacyLen: 8)
            c.paramsA.euclidLines = [red, blue]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty()
                                      s.stepRate = .r1_8
                                      s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                      return s }()])
            st.euclideousNoteSource = .midi
            st.euclideousLanesSeqOn = true
            st.euclideousLanesSeqRate = .oneBar
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        }
        let bar1 = picksThroughBar(beats: 3.9)
        let bar2 = picksThroughBar(beats: 7.9)
        XCTAssertFalse(bar1.isEmpty)
        XCTAssertEqual(Array(bar2.suffix(bar1.count)), bar1, "resetSteps=1 must restart every bar for both lanes combined")
    }
    // RETIRED (2026-10-19, restart-chains ferry): resetSteps=2 over LEN=5 produces an old-model mark pattern
    // whose TRUE period is 10 marks over the 16-bar window (gaps 2,2,1,2,2,1,2,2,1,1 — confirmed by hand against
    // `euclideousStampMask`/`euclideousLaneGridResolved`'s own legacy-mask arithmetic), not reducible to any
    // ≤4-link cycle from {1,2,3,4,6,8} (§4.1). `migrateRestartChains` correctly reports this "not exact" and
    // falls back to FREE (§12.7) — a genuine, disclosed migration gap for this specific old configuration, not
    // a bug: list it in the final report (a factory preset would be listed with its nearest chain; this is a
    // synthetic test document, so there's nothing to leave alone — just report the gap). Not ported; covered in
    // principle by `RestartChainsTests.swift`'s own `testMigrationReportsNotExactWhenGapsDoNotFitTheAllowedLinkSet`.
    // LANES SEQUENCER (ferry §5): "the walk/cursor keeps advancing as normal — only the final emission is
    // suppressed" while a lane's own cell is unlit for the current step. Proven by equivalence: a muted
    // bar must drop ITS OWN notes entirely, but the walk position immediately after it must land exactly
    // where it would have had that bar's hits genuinely sounded (not where it would land had the muted
    // bar been skipped/paused) — i.e. the combined sequence (bar1 + bar3 + bar4, bar 2 excised) of a
    // LANES-muted run must equal the SAME excision applied to a free-running (LANES off) control.
    func testEuclideousLanesSeqMutesEmissionButTheWalkKeepsAdvancing() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func picks(lanesSeqOn: Bool, muteLaneZeroAtStep1: Bool, beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            // 3-of-8 at 1/8: a lap is one bar, so the pre-feature sequencer (1 BAR steps) migrates to PASS-sized mute cells exactly (LANES GRID, 2026-10-18).
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                                 useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty()
                                      s.stepRate = .r1_8
                                      s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                      return s }()])
            st.euclideousNoteSource = .midi
            st.euclideousLanesSeqOn = lanesSeqOn
            st.euclideousLanesSeqRate = .oneBar
            st.euclideousLanesSeqLen = 4
            if muteLaneZeroAtStep1 {
                var cells = [Bool](repeating: true, count: 32)
                cells[1 * 4 + 0] = false   // lane 0 (index 0) unlit at step 1 (bar 2, 0-indexed)
                st.euclideousLanesSeqCells = cells
            }
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        }
        let controlBar1 = picks(lanesSeqOn: false, muteLaneZeroAtStep1: false, beats: 3.9)
        let controlBar1and2 = picks(lanesSeqOn: false, muteLaneZeroAtStep1: false, beats: 7.9)
        let controlAll4Bars = picks(lanesSeqOn: false, muteLaneZeroAtStep1: false, beats: 15.9)
        let mutedAll4Bars = picks(lanesSeqOn: true, muteLaneZeroAtStep1: true, beats: 15.9)
        XCTAssertFalse(controlBar1.isEmpty)
        XCTAssertLessThan(controlBar1and2.count, controlAll4Bars.count, "sanity: bars 3+4 must contribute more onsets under the control")
        let bar3and4 = Array(controlAll4Bars.suffix(controlAll4Bars.count - controlBar1and2.count))
        let expectedMuted = controlBar1 + bar3and4
        XCTAssertEqual(mutedAll4Bars, expectedMuted,
                       "bar 2 must be silent (its own notes dropped) but bars 3+4 must sound EXACTLY as if bar 2 had genuinely played — proving the walk advanced through the mute, not paused or reset by it")
    }
    // RIFFS SEQUENCER (ferry §6/§7): "the riff selected in the riff grid's tabs is the one that plays" when
    // off; when on, which of the four riffs plays switches per-step. Proven with two maximally-distinguishable
    // riffs (a constant-low vs. a constant-high rank) so the switch's effect is unambiguous in the struck
    // pool index — bar 1 must read ONLY the lowest pool note, bar 2 ONLY the highest.
    // Confirms the RIFFS sequencer's per-step picks never affect what sounds — the engine always plays
    // `riffs[activeRiff]` directly (true since the 2026-10-16 "loop slots"/"looper tabs" ferries retired
    // the sequencer's live-switching behaviour, and unaffected by the looper itself being dropped entirely
    // on 2026-10-18 — this test never touched the looper's own fields).
    func testEuclideousRiffsSeqIsIgnoredRiffRanksNeverDependOnIt() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 5, rate: .r1_8,
                                             useRiff: false, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: 8)]
        let constLow = EuclideousRiff(steps: 8, ranks: [Int](repeating: 1, count: 8))
        let constHigh = EuclideousRiff(steps: 8, ranks: [Int](repeating: 8, count: 8))
        // Still threaded through `MachineParams` decode-only (§8.1) — `riffs[0]` migrates into
        // `euclideousLiveGrid` since `activeRiff` is unset (defaults to 0).
        c.paramsA.riffs = [constLow, constHigh, EuclideousRiff.empty, EuclideousRiff.empty]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  s.stepRate = .r1_8
                                  s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                  return s }()])
        st.euclideousNoteSource = .midi
        // RIFFS sequencer configured exactly as the OLD switching test did — ON, set up to (under the
        // retired behaviour) switch from riff 0 to riff 1 at the bar-2 boundary. §8.2: none of this may
        // change what sounds any more.
        st.euclideousRiffsSeqOn = true
        st.euclideousRiffsSeqRate = .oneBar
        st.euclideousRiffsSeqLen = 2
        st.euclideousRiffsSeqCells = [0, 1, 0, 0, 0, 0, 0, 0]
        let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: 7.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let picks = e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        XCTAssertFalse(picks.isEmpty)
        XCTAssertTrue(picks.allSatisfy { $0 == 0 }, "both bars strike only the lowest pool note (riff 0 / constant-low, via euclideousLiveGrid) — the RIFFS sequencer's own bar-2 pick is ignored entirely, confirming §8.2's retirement")
    }
    func testEuclideousRiffsSeqOffFollowsTheActiveRiffTab() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 5, rate: .r1_8,
                                             useRiff: false, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: 8)]
        let constLow = EuclideousRiff(steps: 8, ranks: [Int](repeating: 1, count: 8))
        let constHigh = EuclideousRiff(steps: 8, ranks: [Int](repeating: 8, count: 8))
        c.paramsA.riffs = [constLow, constHigh, EuclideousRiff.empty, EuclideousRiff.empty]
        c.paramsA.activeRiff = 1   // editor tab 2 (constHigh) selected
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  s.stepRate = .r1_8
                                  s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                  return s }()])
        st.euclideousNoteSource = .midi
        st.euclideousRiffsSeqOn = false   // OFF — "the selected tab plays," not the sequencer
        let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: 3.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let picks = e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        XCTAssertFalse(picks.isEmpty)
        XCTAssertTrue(picks.allSatisfy { $0 == 7 }, "RIFFS sequencer off: the lane must play whichever riff tab is selected (activeRiff), ignoring the unused per-step cells entirely")
    }

    // MARK: - FERRY (2026-10-14, "Euclideous fixes from Paul's 14 Oct run") §3 — "sequencer step length"
    // CONFIRMED ROOT CAUSE: the sequencer's own step-length math (`euclideousSeqStepIndex`, pure and
    // already correct) was fed `cyc` — "the row's real cycle length," `cycleBeats > 0 ? cycleBeats :
    // Double(Snap.cols) * S`, a GRID GEOMETRY quantity (8 columns × the scene's own stepRate) — as a
    // stand-in for "one host bar." The two only coincide when the grid's stepRate happens to make 8
    // columns add up to exactly one real bar — which is EXACTLY what `.r1_8` does in 4/4, the stepRate
    // every pre-existing Euclideous test in this file sets, which is why this was invisible until now.
    // `beatsPerBar` (new, from the host's own time-signature block) replaces `cyc` for this one purpose.
    // (The LANES sequencer's single step index — and the two tests that polled it — went with the sequencer, 2026-10-18: the per-lane
    // grid derives its cells from the beat directly. The host-bar fix lives on in the pre-feature MIGRATION, see LanesGridTests.)
    func testEuclideousRiffsSeqStepAlsoUsesTheHostsRealBarLength() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 8, useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8)]
        c.paramsA.riffs = [EuclideousRiff.empty, EuclideousRiff.empty, EuclideousRiff.empty, EuclideousRiff.empty]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  s.stepRate = .r1_4   // non-1/8 again, same proof as the LANES test above
                                  s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                  return s }()])
        st.euclideousNoteSource = .midi
        st.euclideousRiffsSeqOn = true
        st.euclideousRiffsSeqRate = .oneBar
        st.euclideousRiffsSeqLen = 8
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        func stepAt(_ beat: Double) -> Int {
            router.process(box: box, pool: chord([60]), playing: true, beatPos: beat, tempo: 120, beatsPerBar: 4.0,
                            sampleRate: 48_000, timestampSample: 0, frameCount: 2048, forceColumn: 0, out: e, diag: &diag)
            return router.euclideousRiffsSeqStep()
        }
        XCTAssertEqual(stepAt(0), 0)
        XCTAssertEqual(stepAt(4), 1, "one real bar later — NOT two, which is what the old grid-derived cyc would have given")
    }
    /// "Per-lane reset counts these steps, so it inherits the fix" — confirmed on the wire, now through the LANES GRID MIGRATION: a pre-feature
    /// document whose lane has resetSteps=2 at LANES RATE 1 BAR must restart every 2 REAL bars (8 beats at beatsPerBar=4), not every 2 GRID
    /// cycles (16 beats, what the old `cyc`-based math would have given at this deliberately non-1/8 stepRate). The lane is a 3-of-8 at 1/8
    /// (a lap = exactly one bar), so the migrated restart unit (PASS) equals the old step exactly and the restart lands bit-for-bit.
    func testEuclideousPerLaneResetInheritsTheHostBeatsPerBarFix() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        // RESTART CHAINS (2026-10-19): migrated-and-pinned, simulating the AVC resync tick (§12).
        c.paramsA.euclidLines = [migratedLine(EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                             useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8,
                                             resetSteps: 2), legacyRate: .oneBar, legacyLen: 8)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  s.stepRate = .r1_4   // non-1/8: the old cyc-based reset would land at beat 16, not 8
                                  s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                  return s }()])
        st.euclideousNoteSource = .midi
        st.euclideousLanesSeqOn = true
        st.euclideousLanesSeqRate = .oneBar
        func picksThrough(beats: Double) -> [Int] {
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        }
        let firstPeriod = picksThrough(beats: 7.9)     // through just before beat 8 — one 2-bar reset period at the CORRECT bar length
        let throughSecondPeriod = picksThrough(beats: 15.9)
        XCTAssertFalse(firstPeriod.isEmpty)
        XCTAssertEqual(Array(throughSecondPeriod.suffix(firstPeriod.count)), firstPeriod,
                       "resetSteps=2 at LANES RATE 1 BAR must restart at beat 8 (2 real bars), replaying the first period's exact picks")
    }
    // MARK: - FERRY (2026-10-15, "per-step restart points on the LANES tab") — carried onto the LANES GRID (2026-10-18)
    // A restart mark must genuinely reshape the Router's own hit timing end to end (not just in the pure-function tests). A 1-of-3 pattern at
    // 1/4 (one tick = one beat, a cycle = 3 beats) with a RHYTHM mark on EVERY 4-tick restart cell re-anchors the pattern every 4 beats, so
    // its hits sit at 0, 3, 4, 7, 8, 11, 12, 15 — a markedly different cadence from the free-running 0, 3, 6, 9, 12, 15. That a restart on a MUTED cell
    // still takes effect is structural (the origin never reads the mute) and is also asserted on the wire in LanesGridRouterTests below.
    func testEuclideousMaskedResetAppliesEndToEndThroughTheRouter() {
        func hitBeats(restart: Bool) -> [Int] {
            var line = EuclidLine(target: 0, pulses: 1, steps: 3, rate: .r1_4, sourceMode: .midi)
            if restart {
                line.restartUnit = EuclideousRestartUnit.fourSteps.rawValue
                line.restartRhythmMask16 = 0xFFFF; line.restartMelodyMask16 = 0xFFFF
                // RESTART CHAINS (2026-10-19): migrated-and-pinned, simulating the AVC resync tick (§12) — every
                // 4-tick cell marked, at 1 beat/tick, is a restart every 4 beats = every bar exactly.
                line = migratedLine(line, legacyRate: .oneBar, legacyLen: 8)
            }
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [line]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty()
                                      s.stepRate = .r1_8
                                      s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                      return s }()])
            st.euclideousNoteSource = .midi
            let e = RecordingEmitter()
            run(SnapshotBuilder.build(from: st), chord([60]), beats: 15.9, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            let sr = 48_000.0, tempo = 120.0
            return e.ons.filter { $0.cable == 1 }.map { Int((Double($0.sample) / sr * tempo / 60.0).rounded()) }
        }
        XCTAssertEqual(hitBeats(restart: true), [0, 3, 4, 7, 8, 11, 12, 15], "re-anchored every 4-tick restart cell — each restart is a step-0 hit, then the pattern's own step 0 again 3 ticks later")
        XCTAssertEqual(hitBeats(restart: false), [0, 3, 6, 9, 12, 15], "no restart: the native 3-beat cycle free-runs from beat 0")
    }
    // The TIE / next-hit lookahead must re-anchor against a custom mark exactly as the per-hit origin does — including across a WINDOW boundary
    // with no mark on cell 0 (where the origin stays the PREVIOUS window's mark, not the new window's start). A single-hit 5-step pattern at one
    // beat per tick, 4-tick restart cells, a RHYTHM mark on cell 5 only (tick 20). Window = 64 ticks. Before the mark the carried origin is
    // (5 − 16) × 4 = −44, so hits fall on ticks ≡ 1 (mod 5); the mark at 20 restarts the pass (a hit AT 20); and because 64 ≢ 0 (mod 5) the
    // window seam is observable: 60 is a hit (60 − 20 = 40), the next is 65 — NOT 64, which a (wrong) re-anchor at the new window would give.
    func testEuclideousNextHitGapReAnchorsAgainstTheMarkAcrossAWindowBoundary() {
        var buf = [Bool](repeating: false, count: 8); buf[0] = true
        let grid = EuclideousLaneRestartGrid(unitTicks: 4, rhythmMask: 1 << 5, melodyMask: 0)
        func gap(_ tick: Int64) -> Double {
            euclideousNextHitGapBeats(buf: buf, n: 5, dir: .fwd, cycleLen: 5, sub: 1, tick: tick, cap: 64, grid: grid, legacySpanBeats: 0)
        }
        XCTAssertEqual(gap(0), 1, "tick 1 is the first hit of the carried (negative-origin) segment")
        XCTAssertEqual(gap(16), 4, "the restart AT tick 20 is a step-0 hit — 4 ticks away, where the plain pattern would say 5")
        XCTAssertEqual(gap(60), 5, "across the window seam at 64 with no mark on cell 0: the next hit is 65, not 64")
        // and the same answers from the tick-by-tick definition
        let pattern: (Int64) -> Bool = { t in
            let o = euclideousMaskedResetCell(absCell: Int(floorDiv(t, 4)), mask: 1 << 5)! * 4
            let local = t - Int64(o)
            return ((local % 5) + 5) % 5 == 0
        }
        for t in [Int64(0), 16, 60] {
            var k: Int64 = 1; while !pattern(t + k) { k += 1 }
            XCTAssertEqual(gap(t), Double(k))
        }
    }
    // testEuclideousResetSpanHardResetsDrunksWalkAtEachBoundary REMOVED (Paul 2026-10-13 ferry, "Remove":
    // "The DRUNK option") — DRUNK is no longer one of Euclideous's own WALK directions, so it no longer
    // has a history-dependent position that could need a special span-boundary nudge; every remaining
    // direction already resets for free via `ord` alone, per `testEuclideousResetSpanOneBarReAnchorsThe
    // PatternEveryBar` above — this test's whole distinguishing premise is gone, not merely stale.
    // §7 test 10 of the 2026-10-15 ferry ("DRUNK hard-resets exactly at a custom restart point... adapt the
    // existing reset-span DRUNK test") is SKIPPED for the exact same reason, flagged in review before this
    // ferry was built and left on the record here rather than silently dropped: there is no DRUNK riff-walk
    // left in Euclideous to adapt a test for (see the removal note immediately above, and
    // `euclideousRiffDirResolved`'s own unconditional `.drunk`/`.random` → `.forward` coercion in
    // Models.swift). Every OTHER walk direction's own restart behaviour under a custom mask is already
    // covered by `testEuclideousMaskedResetOnAMutedStepStillReAnchorsTheLane` and the masked-origin
    // equivalence/lap-boundary tests in DerivationsTests.swift/this file.
    // ONE GLOBAL SOURCE (Paul 2026-10-12, 2nd same-day ferry) — SUPERSEDES the per-lane independence this
    // test used to assert by name. The 3 lanes below each still carry a DIFFERENT, now-stale `sourceMode`
    // (left in place deliberately — if a future regression ever resurrected per-lane reads, these different
    // stale values would immediately produce 3 distinct notes again, exactly the failure this test guards
    // against). Under the new model all 3 must resolve to the SAME note, since exactly one page-level knob
    // (`PluginState.euclideousNoteSource`) governs every lane — proven twice, once per global value, so the
    // result can't be a coincidence of whichever value a stale per-lane field happened to carry.
    func testEuclideousLanesAllShareTheOneGlobalSourceDespiteDifferingStalePerLaneValues() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [
            EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, sourceMode: .midi),    // stale — now inert
            EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, sourceMode: .chords),  // stale — now inert
            EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, sourceMode: .key),     // stale — now inert
        ]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  var cell = Cell(machineID: "gold", buses: [.a]); cell.inputReceiver = 3
                                  s.cells[0][Snap.euclideousRow] = cell
                                  return s }()])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4", channel: 2)]
        st.euclideousKeyRoot = 0; st.euclideousKeyType = .major   // C major
        st.euclideousChords = { var m = MachineParams(); m.chordsDegrees = [4]; m.chordsSteps = 1; return m }()   // a 1-step V progression: [55,59,62]
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 1)

        // Global = KEY: all 3 lanes, regardless of their own stale field, must sound the SAME note — the
        // scale's own root (48) — and nothing else.
        var stKey = st; stKey.euclideousNoteSource = .key
        let e1 = RecordingEmitter(); run(SnapshotBuilder.build(from: stKey), pool, beats: 1, into: e1, forceColumn: 0)
        assertNothingLeftSounding(e1)
        let notesKey = Set(e1.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertEqual(notesKey, [48], "with the global source set to KEY, all 3 lanes must sound the identical scale-root note, not 3 different per-lane notes")

        // Global = CHORDS: all 3 lanes must move TOGETHER to the chord generator's lowest note (55) — proving
        // the shared value, not a fixed coincidence of the KEY case above.
        var stChords = st; stChords.euclideousNoteSource = .chords
        let e2 = RecordingEmitter(); run(SnapshotBuilder.build(from: stChords), pool, beats: 1, into: e2, forceColumn: 0)
        assertNothingLeftSounding(e2)
        let notesChords = Set(e2.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertEqual(notesChords, [55], "with the global source set to CHORDS, all 3 lanes must sound the identical chord-pool note, not their own stale per-lane value")
    }
    // The RETIRED global `euclideousLanesSourceMidi` switch must no longer have ANY effect — only each lane's
    // own `sourceMode` governs its source now. A real regression risk on upgrade if this weren't true: an old
    // saved doc with the global switch set to KEY would otherwise silently mute every lane that never touches
    // the new per-lane field.
    func testEuclideousRetiredGlobalLanesSwitchNoLongerAffectsAnyLane() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low)]   // sourceMode untouched ⇒ nil ⇒ MIDI
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  var cell = Cell(machineID: "gold", buses: [.a]); cell.inputReceiver = 3
                                  s.cells[0][Snap.euclideousRow] = cell
                                  return s }()])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        st.euclideousLanesSourceMidi = false   // the OLD global switch, set to its "KEY" value — must now have NO effect
        // ONE GLOBAL SOURCE (2026-10-12) pinned to MIDI explicitly — without this the test would pass
        // vacuously (KEY mode is never silent either, since the default scale always has real notes), without
        // actually proving the specific live note below is what's heard.
        st.euclideousNoteSource = .midi
        let pool = NotePool(); pool.noteOn(60, velocity: 100, channel: 0)
        let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), pool, beats: 1, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.contains { Int($0.note) == 60 }, "an untouched lane must still sound the genuine live note via MIDI — the retired global switch must not silence/replace it anymore")
    }
    // RIFF FREE/LOCK/INVERT/ON REST (Paul 2026-10-09 ferry, "three new per-lane riff options"). The RIFF
    // mechanism itself (useRiff/riffDir/now riffLock/riffInvert/riffOnRest) is row-agnostic in the model —
    // only Euclideous's own page sets these fields in practice, but the engine honours them on ANY `.euclid`
    // cell with useRiff on, so these tests use plain row 0 (not Snap.euclideousRow) with a shared chord pool,
    // the same simpler convention `testEuclidLineUseRiffReplacesNoteSelectWithSharedRiffPattern` above
    // already uses for this exact reason.
    //
    // FREE vs LOCK: K=3/N=5 (cycleLen=5 ticks, 3 hits/cycle) deliberately does NOT divide the riff's own
    // 8-step length, so FREE's continuously-advancing ordinal visits a genuinely DIFFERENT 3 ranks on cycle 2
    // (hits 3,4,5) than cycle 1 (hits 0,1,2) — if LOCK did nothing, this test couldn't tell the two modes
    // apart, the same "pick a non-dividing length" lesson the reset-span tests above already learned the
    // hard way.
    func testEuclideousRiffLockReplaysTheSameSequenceEveryCycleFreeDoesNot() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        // "LOCK" below is now a melody chain of [1] — §4.7, exactly what LOCK did (riffLock itself is retired, §7).
        func ranksStruck(lock: Bool, beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])   // identity: riff step i ↔ rank i+1 ↔ pool[i]
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 5, rate: .r1_8, useRiff: true, restartMelodyPasses: lock ? [1] : [])]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        }
        let lockedCycle1 = ranksStruck(lock: true, beats: 2.4)    // one full K=3 cycle (2.5 beats at r1_8), just under
        let lockedTwoCycles = ranksStruck(lock: true, beats: 4.9) // two full cycles, just under the 3rd's own boundary
        let freeCycle1 = ranksStruck(lock: false, beats: 2.4)
        let freeTwoCycles = ranksStruck(lock: false, beats: 4.9)
        XCTAssertEqual(lockedCycle1.count, 3, "one Euclid cycle (K=3) must strike exactly 3 hits")
        XCTAssertEqual(Array(lockedTwoCycles.suffix(3)), lockedCycle1, "LOCK: cycle 2's riff-rank sequence must exactly replay cycle 1's")
        XCTAssertNotEqual(Array(freeTwoCycles.suffix(freeCycle1.count)), freeCycle1, "FREE: the riff keeps advancing across the cycle boundary — cycle 2 must NOT replay cycle 1")
    }
    // LOCK + RANDOM: the SAME seed hashed from the SAME local-ord (0,1,2 every cycle, under LOCK) must
    // reproduce the identical "random" pick every cycle — falls out for free from feeding `riffStepAt` the
    // re-anchored ordinal, no special-casing needed (confirmed here, not just reasoned).
    func testEuclideousRiffLockReseedsRandomIdenticallyEveryCycle() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func ranksStruck(beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            // "LOCK" is now a melody chain of [1] — §4.7, exactly what riffLock (retired, §7) did.
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 5, rate: .r1_8, useRiff: true, riffDir: .random, riffDirSeed: 7, restartMelodyPasses: [1])]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        }
        let cycle1 = ranksStruck(beats: 2.4)
        let twoCycles = ranksStruck(beats: 4.9)
        XCTAssertEqual(cycle1.count, 3)
        XCTAssertEqual(Array(twoCycles.suffix(3)), cycle1, "LOCK+RANDOM: the same seed hashed from local-ord 0,1,2 every cycle must reproduce the identical pick sequence")
    }
    // testEuclideousRiffLockHardResetsDrunksWalkEveryCycle REMOVED (Paul 2026-10-13 ferry, "Remove": "The
    // DRUNK option") — DRUNK is no longer one of Euclideous's own WALK directions, so its LOCK-at-every-
    // cycle behaviour is exactly the already-covered FORWARD case (`testEuclideousRiffLockReplaysTheSame
    // SequenceEveryCycleFreeDoesNot` above), not a separately-needed proof.
    // STRIDE (melody pop-up ferry 2026-10-10 §3.4): "Stride 3 on length 5 visits 1, 4, 2, 5, 3" — the
    // ferry's own literal worked example. Dense K=N=5 (every tick a hit) isolates 5 consecutive
    // ordinals cleanly; identity ranks [1..8] let the struck POOL INDEX double as the RIFF RANK directly.
    func testEuclideousRiffStrideVisitsTheFerrysLiteralWorkedExample() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 5, steps: 5, rate: .r1_8, useRiff: true, riffStride: 3, riffLength: 5)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord(pool), beats: 2.4, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ranksStruck = e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        XCTAssertEqual(Array(ranksStruck.prefix(5)), [1, 4, 2, 5, 3], "§3.4's own literal example: stride 3 on length 5 must visit ranks 1,4,2,5,3 in order")
    }
    // LOCK restarts the walk so the first played step IS the shift step (§3.3), verified for FWD — every
    // one of the ferry's own worked examples is implicitly FWD. Dense K=N=4 at r1_8 (2-beat cycle) with
    // SHIFT=2, LOCK on: FWD's own walkPos=0 at the start of every lap, so the first hit of EVERY lap must
    // read the identical rank.
    func testEuclideousRiffLockFwdRestartsAtTheShiftStep() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func ranksOf(beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            // "LOCK" is now a melody chain of [1] — §4.7, exactly what riffLock (retired, §7) did.
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 4, rate: .r1_8, useRiff: true, riffRotate: 2, restartMelodyPasses: [1])]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        }
        let lap1 = ranksOf(beats: 1.9)       // K=N=4 at r1_8 → a 2-beat cycle; just under one lap
        let twoLaps = ranksOf(beats: 3.9)
        XCTAssertEqual(lap1.first, 3, "FWD's own walkPos=0 at the start of a lap, +SHIFT 2 → riff step 2 (0-indexed) → rank 3")
        XCTAssertEqual(twoLaps.count, 8, "two full 4-hit laps")
        XCTAssertEqual(Array(twoLaps.suffix(4)).first, lap1.first, "LOCK: the second lap's first played step must equal the first lap's — both land on the shift step")
    }
    // A narrow, flagged edge case (plan §Corrections item 5): REVERSE's own formula naturally starts at
    // (length-1), not 0, at ord=0 — so under LOCK, REV's "first played step" is its own natural anchor
    // PLUS shift, not a forced 0+shift. Locked in as documented, deliberate behaviour (a direct, unmodified
    // reuse of the existing riffStepAt formula), not a silent gap — redirectable later if this isn't what
    // was actually intended.
    // RIFF WINDOW ferry (2026-10-21): SHIFT now wraps at the riff's 8 columns, not at LENGTH (so a LENGTH-
    // wide window can start anywhere in the 8-column riff, not just rotate within its own first LENGTH
    // columns) — this example's expected rank moved from 1 to 6, recomputed below, since LENGTH 5 < 8.
    func testEuclideousRiffLockReverseRestartsAtItsOwnNaturalAnchorPlusShift() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        // LENGTH 5, SHIFT 1: REV's walkPos at ord=0 is (length-1)=4; played step = (4+1) mod 8 = 5 → rank 6.
        // "LOCK" is now a melody chain of [1] — §4.7, exactly what riffLock (retired, §7) did.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 4, rate: .r1_8, useRiff: true, riffRotate: 1, riffDir: .reverse, riffLength: 5, restartMelodyPasses: [1])]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord(pool), beats: 1.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ranks = e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        XCTAssertEqual(ranks.first, 6, "REV's own anchor (length-1=4) + shift(1) mod 8 (the riff's own column count, RIFF WINDOW ferry) = 5 → rank 6")
    }
    // ADVANCE=STEP (§3.5): the walk advances on EVERY step (hit or miss), not just hits. A sparse K=2/N=8
    // Euclidean pattern spaces its 2 hits far apart (never adjacent, by construction) — HIT mode's 2nd hit
    // reads walkPos=1 (its own 2nd ADVANCE); STEP mode's 2nd hit reads the raw elapsed-step count instead,
    // landing on a different rank whenever at least one miss elapsed between the two hits (true for ANY
    // non-adjacent pair, so this doesn't depend on knowing the pattern's exact hit positions).
    func testEuclideousRiffAdvanceStepTracksElapsedStepsNotHits() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func secondHitRank(advanceStep: Bool) -> Int? {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 2, steps: 8, rate: .r1_16, useRiff: true, riffAdvanceStep: advanceStep)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord(pool), beats: 2.2, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            let ranks = e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
            return ranks.count >= 2 ? ranks[1] : nil
        }
        let hitRank = secondHitRank(advanceStep: false)
        let stepRank = secondHitRank(advanceStep: true)
        XCTAssertNotNil(hitRank); XCTAssertNotNil(stepRank)
        XCTAssertNotEqual(hitRank, stepRank, "ADVANCE=STEP must read a different walk position than ADVANCE=HIT once a miss has elapsed between hits")
    }
    // TRANSPOSE (§3.1/§3.7): a rank-space shift applied after INVERT, wrapping via the SAME riffResolve
    // rule as any out-of-pool rank — verified in BOTH modes, since PLACEMENT applies it regardless of MODE.
    // SUPERSEDES the "...InBothModes" claim (Paul 2026-10-13 ferry, "MELODY tab on the lane cards",
    // Engine rule 1: "Note mode plays exactly what the button shows... TRANS... [is] ignored in note
    // mode") — a deliberate reversal, not an oversight: a genuine bug was found tracing this before making
    // the change (NOTE mode's plain-pick branch was STILL adding `melodyTranspose`, confirmed by reading).
    // RIFF mode is UNCHANGED (TRANSPOSE still applies there, per the same ferry's own Engine rule — only
    // NOTE mode's behaviour reverses).
    func testEuclideousMelodyTransposeAppliesInRiffModeOnlyNotNoteMode() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        // RIFF mode: rank 1 (the lowest), transpose +2 → rank 3 → pool[2] = 64.
        var cRiff = Machine(machineID: "gold", type: .euclid)
        cRiff.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])
        cRiff.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: true, melodyTranspose: 2)]
        let bRiff = box(machines: machineIDs.map { $0 == "gold" ? cRiff : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let eRiff = RecordingEmitter(); run(bRiff, chord(pool), beats: 1, into: eRiff, forceColumn: 0)
        assertNothingLeftSounding(eRiff)
        XCTAssertEqual(eRiff.ons.filter { $0.cable == 1 }.first.map { Int($0.note) }, 64, "RIFF mode: rank 1 + transpose 2 → rank 3 → pool[2]")
        // NOTE mode: LOWEST (rank 1), transpose +2 → TRANSPOSE is IGNORED — the button shows rank 1, the
        // button plays rank 1 (pool[0] = 60), not pool[2]. No useRiff here — defaults off.
        var cNote = Machine(machineID: "gold", type: .euclid)
        cNote.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, melodyTranspose: 2)]
        let bNote = box(machines: machineIDs.map { $0 == "gold" ? cNote : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let eNote = RecordingEmitter(); run(bNote, chord(pool), beats: 1, into: eNote, forceColumn: 0)
        assertNothingLeftSounding(eNote)
        XCTAssertEqual(eNote.ons.filter { $0.cable == 1 }.first.map { Int($0.note) }, 60, "NOTE mode: TRANSPOSE must be ignored — LOWEST (rank 1) plays pool[0], not pool[2]")
    }
    // OCT RANGE −2…+2, EUCLIDEOUS-ONLY (Paul 2026-10-13 ferry, "Engine" rule 4) — a genuine ENGINE-level
    // clamp, not the model layer's: `EuclidLine.octaveResolved` itself stays unclamped at ±3 (confirmed
    // shared with the regular, non-Euclideous BUILD-page EUCLID processor's own OCTAVE stepper — narrowing
    // it there would silently clip an unrelated feature). The tighter ±2 is applied ONLY at the one
    // `runEuclidLine` call site, gated on `isEuclideousRow` — so the SAME octave:3 config must clamp on
    // Euclideous's own reserved row but NOT on an ordinary row elsewhere in the grid.
    func testEuclideousNoteModeOctaveClampsToPlusMinusTwoOnlyOnTheEuclideousRow() {
        func firstNote(row: Int) -> Int? {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .low, octave: 3, sourceMode: .midi)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty(); s.cells[0][row] = Cell(machineID: "gold", buses: [.a]); return s }()])
            // ONE GLOBAL RIFF/NOTE SOURCE (2026-10-12): on Euclideous's own row, the pool comes from
            // `euclideousNoteSourceResolved`, NOT directly from the held chord — its nil default falls
            // back to the legacy per-lane `sourceModeResolved`, which itself defaults to KEY, not MIDI.
            // Must be set explicitly here so the held chord ([60]) is actually what's read, matching every
            // other Euclideous-row RouterTest's own established convention.
            st.euclideousNoteSource = .midi
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord([60]), beats: 1, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }.first
        }
        XCTAssertEqual(firstNote(row: Snap.euclideousRow), 60 + 24, "on Euclideous's own row, octave clamps to +2 (24 semitones), not +3 (36)")
        XCTAssertEqual(firstNote(row: 0), 60 + 36, "on an ORDINARY row, the shared octave field is untouched — still ±3, the regular EUCLID processor's own range")
    }
    // TOP/TOP2 (Paul 2026-10-13 ferry, Octave-row buttons) — `.high`/`.top2` already resolve correctly
    // against the RAW, pre-extension pool count via `resolveEuclidPick` (confirmed by reading before
    // relying on it for the new OCT-row UI, zero engine change needed), including the degenerate
    // one-note-pool case TOP2 must still resolve to something sensible rather than crash/miss.
    func testEuclideousTopAndTop2ResolveAgainstTheRawPoolCountIncludingOneNote() {
        func notes(sel: EuclidNoteSel, pool: [UInt8]) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: sel)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord(pool), beats: 1, into: e, forceColumn: 0); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        }
        XCTAssertEqual(Set(notes(sel: .high, pool: [60, 64, 67, 72])), [72], "TOP: the single highest held note")
        XCTAssertEqual(Set(notes(sel: .top2, pool: [60, 64, 67, 72])), [67, 72], "TOP2: the two highest held notes")
        XCTAssertEqual(Set(notes(sel: .top2, pool: [60])), [60], "TOP2 against a single held note degrades to that one note, not a crash or a miss")
    }
    // §3.8: "if LENGTH is reduced below the lane's current position, wrap the position into the new
    // window on the next advance." DRUNK was the one direction whose ACCUMULATED position could reference
    // a spot outside a newly-shrunk LENGTH — removed from Euclideous's own WALK directions entirely (Paul
    // 2026-10-13 ferry, "Remove"), so every remaining direction (FWD/REV/PEND/PING) now self-corrects for
    // free (no persisted state at all) and this scenario can no longer produce anything BUT a within-
    // window result — kept as a cheap regression guard that a mid-session LENGTH change never crashes and
    // always confines its notes to the new, smaller window, using FORWARD directly rather than the now-
    // retired `.drunk` (which would resolve through `riffStepAt`'s own exhaustive-but-unreachable `.drunk`
    // arm to the identical plain forward position anyway).
    func testEuclideousRiffLengthShrinkMidSessionConfinesNotesToTheNewWindow() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 5, steps: 5, rate: .r1_16, useRiff: true, riffDir: .forward, riffLength: 8)]
        let box1 = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        let router = runKeepingRouter(box1, chord(pool), beats: 4.0, into: e, forceColumn: 0, tempo: tempo, sr: sr, frames: frames)
        // Shrink LENGTH to 3 on the SAME router instance mid-session.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 5, steps: 5, rate: .r1_16, useRiff: true, riffDir: .forward, riffLength: 3)]
        let box2 = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        var diag = KernelDiag()
        var beat = 4.0, ts = 4.0 / tempo * 60.0 * sr
        for _ in 0..<40 {
            router.process(box: box2, pool: chord(pool), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: box2, pool: chord(pool), playing: false, beatPos: beat, tempo: tempo,
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        let notesAfterShrink = e.ons.filter { $0.cable == 1 }.map { Int($0.note) }.suffix(10)
        XCTAssertFalse(notesAfterShrink.isEmpty, "the lane must keep striking after the shrink, not go silent")
        for n in notesAfterShrink {
            XCTAssertTrue([60, 62, 64].contains(n), "after LENGTH shrinks to 3, every struck note must come from the first 3 ranks (60,62,64) — got \(n)")
        }
    }
    // INVERT: rank r plays as rank (9−r); a rest (rank 0) stays a rest regardless. K=N=3 (dense — every
    // Euclid step is a hit) against a 3-step riff [1, 0, 8] (lowest · rest · highest) isolates the mirror
    // cleanly: uninverted strikes pool[0] then pool[7] (the middle rest silent); inverted strikes pool[7]
    // then pool[0] — the exact temporal swap INVERT's own mirror formula predicts, with the rest staying
    // silent in BOTH runs (proving the mirror doesn't also turn rests into notes).
    func testEuclideousRiffInvertMirrorsRankRestsStayRests() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func notesStruck(invert: Bool) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 3, ranks: [1, 0, 8])
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 3, rate: .r1_8, useRiff: true, riffInvert: invert)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            // K=N=3 at r1_8 (0.5 beats/tick) = a 1.5-beat cycle — a 0.1-beat margin under that boundary (the
            // first draft's beats:1.4) was NOT enough to keep the next cycle's own hit 0 from leaking into the
            // capture window (caught empirically, not assumed: the first run showed a stray extra "60" at the
            // END of the sequence — exactly where a leaked-in repeat of hit 0 would land, not a rest wrongly
            // firing, which would land in the MIDDLE). 0.4 beats of margin here instead.
            let e = RecordingEmitter(); run(b, chord(pool), beats: 1.1, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        }
        let plain = notesStruck(invert: false)
        let inverted = notesStruck(invert: true)
        XCTAssertEqual(Array(plain.prefix(2)), [60, 72], "uninverted: rank 1 then rank 8, the middle rest silent")
        XCTAssertEqual(Array(inverted.prefix(2)), [72, 60], "INVERTED: rank 1→8 and rank 8→1, exactly swapping which note comes first")
    }
    // ON REST = FILL: a hit landing on a riff rest strikes this lane's OWN note-select pick instead of
    // staying silent — "as if riff were off." A 1-step, permanently-resting riff (steps:1, ranks:[0]) means
    // EVERY hit lands on a rest, isolating FILL's effect cleanly: every one of K=2 hits must strike the
    // SAME note (.high's own pick against the 3-note pool), not vary or go silent.
    func testEuclideousRiffOnRestFillPlaysTheLanesOwnNoteSelectPick() {
        let pool: [UInt8] = [60, 64, 67]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [0])
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 2, steps: 2, noteSel: .high, rate: .r1_8, useRiff: true, riffOnRest: .fill)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        // K=N=2 at r1_8 = a 1.0-beat cycle — checked only the first 2 onsets (not the whole capture), the
        // same leaked-next-cycle lesson as the INVERT test above: every hit here resolves to the SAME note
        // (.high is constant), so a 3rd onset leaking in wouldn't even be visible as a wrong VALUE, only as
        // an extra COUNT — prefix-checking sidesteps that ambiguity entirely rather than fighting the exact
        // beat budget needed to rule it out.
        let e = RecordingEmitter(); run(b, chord(pool), beats: 0.7, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let notes = e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertEqual(Array(notes.prefix(2)), [67, 67], "ON REST = FILL must strike the lane's own noteSel (.high → 67) on every rest-landing hit, not stay silent")
    }
    // ON REST = TIE: no new strike on the rest itself, but the PRECEDING real note's own gate extends to
    // cover it — proven by comparing the FIRST note's note-OFF sample against the identical pattern run under
    // SKIP: both modes must agree on WHICH notes strike (the rest contributes nothing new either way — the
    // only way to tell them apart is the extended GATE, not the note count), but TIE's note-off must land
    // strictly later. K=N=3 (dense) against riff [1, 0, 2] (rank1 · rest(the TIE target) · rank2) isolates
    // exactly one tie-extension with a real, different note on either side.
    func testEuclideousRiffOnRestTieExtendsThePrecedingNotesGateNoNewStrike() {
        let pool: [UInt8] = [60, 62, 64]
        func onsAndFirstOff(onRest: EuclidRiffOnRest) -> (notes: [Int], firstOff: Int64?) {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 3, ranks: [1, 0, 2])
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 3, rate: .r1_8, useRiff: true, riffOnRest: onRest)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            // K=N=3 at r1_8 = a 1.5-beat cycle — 0.4 beats of margin under that boundary (see the INVERT
            // test's own note above on why 0.1 wasn't enough). Also a genuine off-by-one caught empirically,
            // not assumed: rank 2 resolves to pool[2-1]=pool[1]=62, NOT the 3rd pool entry (64) — fixed below
            // rather than reached for a different rank, since the exact pool index doesn't matter to what's
            // being proven here, only that hit 0 and hit 2 land on two genuinely DIFFERENT, identifiable notes.
            let e = RecordingEmitter(); run(b, chord(pool), beats: 1.1, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            let ons = e.ons.filter { $0.cable == 1 }
            let firstNote = ons.first?.note
            let firstOff = e.offs.filter { $0.cable == 1 && $0.note == firstNote }.map { $0.sample }.min()
            return (ons.map { Int($0.note) }, firstOff)
        }
        let tie = onsAndFirstOff(onRest: .tie)
        let skip = onsAndFirstOff(onRest: .skip)
        XCTAssertEqual(tie.notes, [60, 62], "the rest must still produce no new strike of its own under TIE")
        XCTAssertEqual(skip.notes, [60, 62], "...and SKIP must agree on which notes strike — the two differ only in gate length, not note count")
        guard let tieOff = tie.firstOff, let skipOff = skip.firstOff else { return XCTFail("both runs must produce a matching note-off for the first note") }
        XCTAssertGreaterThan(tieOff, skipOff, "TIE must extend the first note's own gate to cover the rest that follows it — its note-off must land strictly later than SKIP's")
    }
    // ── MISS = PATTERN INVERT (Paul 2026-10-10, "rhythm cards cleared of melody" ferry) ────────────────────
    // `patternMiss` is a brand-new field, additive alongside (not a replacement for) `missNoteSel`/etc. —
    // those stay live for the regular, non-Euclideous BUILD-page EUCLID editor's own dual-voice feature
    // (GridUI.swift); `patternMiss` is the ONLY thing Euclideous's own lane cards write going forward.
    // Ferry's own literal example: 3 hits of 8 in MISS plays the other 5 steps.
    // noteSel: .low (one note struck per hit, matching the sibling tests' own convention) — a bare EuclidLine
    // defaults noteSel to .all, which strikes the WHOLE 3-note pool per hit; caught empirically, not assumed,
    // when a first draft without it returned 12/15 (4 hits × 3 notes) instead of 3/5. beats:3.9 (not 4.1) stays
    // strictly inside the one 4-beat cycle (N=8 @ r1_8=0.5) — 4.1 was just far enough past the boundary to also
    // capture cycle 2's own first hit (a real step, not a bug, but not what "one cycle" was meant to isolate).
    func testEuclideousPatternMiss3Of8PlaysTheOtherFiveSteps() {
        let pool: [UInt8] = [60, 64, 67]
        func onsetCount(patternMiss: Bool) -> Int {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, noteSel: .low, patternMiss: patternMiss, rate: .r1_8)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord(pool), beats: 3.9, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertEqual(onsetCount(patternMiss: false), 3, "sanity: HIT mode strikes the 3 authored hits")
        XCTAssertEqual(onsetCount(patternMiss: true), 5, "MISS mode strikes the complementary 5 steps (8-3)")
    }
    // §2.2: "0 hits in MISS mode plays every step." Also the regression guard for a REAL engine bug this
    // ferry's own review caught: the per-lane loop's `pulses > 0` guard discarded a 0-pulse line BEFORE
    // `patternMiss` ever got a chance to invert it (a 0-pulse slot was, until this fix, always treated as a
    // permanently-unused fixed row — correct everywhere except under this exact feature). Fixed by widening
    // the guard to `pulses > 0 || patternMissResolved`.
    func testEuclideousPatternMissZeroHitsPlaysEveryStep() {
        let pool: [UInt8] = [60, 64, 67]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 0, steps: 8, noteSel: .low, patternMiss: true, rate: .r1_8)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord(pool), beats: 3.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 8, "0 hits inverted = every one of the 8 steps sounds")
    }
    // §2.2: "8 hits of 8 in MISS mode is silent."
    func testEuclideousPatternMissEightOfEightIsSilent() {
        let pool: [UInt8] = [60, 64, 67]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, patternMiss: true, rate: .r1_8)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord(pool), beats: 4.1, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "a fully-dense pattern inverted strikes nothing")
    }
    // §2.3: "the riff walk (ADVANCE: HIT) advances once per sounding step." A sparse 2-of-8 pattern inverted
    // sounds on 6 steps — if the walk correctly reads the INVERTED buffer's notion of "hit" (the single
    // `euclidBuf` toggle this feature relies on), it advances by exactly 1 per sounding step, striking 6
    // DISTINCT, STRICTLY ASCENDING ranks in order (1..6) from a literal ascending riff pattern. If it instead
    // still advanced only on the original 2 raw Euclid hits (the bug this test guards against), only 2 of
    // the 6 struck notes would show genuinely new ranks — the rest would repeat stale ones.
    func testEuclideousPatternMissRiffAdvancesOncePerSoundingStep() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 2, steps: 8, patternMiss: true, rate: .r1_8, useRiff: true)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord(pool), beats: 4.1, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ranks = e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        XCTAssertEqual(ranks, [1, 2, 3, 4, 5, 6], "6 sounding steps must advance the walk by exactly 1 each, striking 6 strictly-ascending ranks")
    }
    // §2.4: "when loading an older saved state that had the miss side playing, load it as HIT, ignore the
    // old miss-side settings, and keep everything else." A doc decoded with the OLD dual-voice keys set and
    // NO `patternMiss` key at all must decode cleanly (the shared fields are never deleted, only ignored for
    // Euclideous's own row — see Router.swift's `!isEuclideousRow` guard) and resolve to HIT.
    func testEuclideousOlderDocWithMissSideConfiguredLoadsAsHit() {
        var line = EuclidLine(target: 0, pulses: 3, steps: 8, noteSel: .low)
        line.missNoteSel = .high; line.missVelocity = 1.0; line.missGate = 0.8; line.missOctave = 1
        let data = try! JSONEncoder().encode(line)
        let decoded = try! JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertFalse(decoded.patternMissResolved, "an old doc with the miss side configured must resolve to HIT, never MISS")
        XCTAssertEqual(decoded.noteSelResolved, .low, "everything else survives untouched")
        XCTAssertEqual(decoded.missNoteSel, .high, "the old miss-side settings are NOT deleted from the model (still live for the regular, non-Euclideous processor) — just inert for Euclideous's own row")
    }
    // ── EUCLID MASK (Paul 2026-10-10, "Euclid mask, modes and settings" ferry) ─────────────────────────────
    // Shared fixture: an 8-of-8 (always-hit) lane on an ascending riff [1..8], so every tick's struck rank is
    // directly readable from the pool and every tick is eligible for masking — isolates the MASK's own
    // behaviour from the Euclid HITS pattern itself.
    private func maskFixture(velocityAbsolute: Int? = nil, useRiff: Bool = true, _ configure: (inout EuclidLineMask) -> Void) -> (box: SnapshotBox, pool: [UInt8]) {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        var m = EuclidLineMask(); configure(&m)
        // NOTE MODE (useRiff: false): .low strikes exactly the ONE lowest held note per hit, the same
        // "one note per hit" shape the RIFF fixture above gets for free from its rank-per-tick walk —
        // keeps the NOTE-mode mask tests a clean apples-to-apples mirror of their RIFF-mode siblings
        // (an `.all` pick would strike all 8 pool notes per hit, each independently masked/ratcheted —
        // not wrong, just a messier aggregate to assert against).
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: useRiff ? nil : .low,
                                             velocityAbsolute: velocityAbsolute, rate: .r1_8, useRiff: useRiff, mask: m)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        return (b, pool)
    }
    func testEuclidMaskChance50PercentIsReproducibleAfterAReset() {
        func run1() -> [Int] {
            let f = maskFixture { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 0.5; $0.mode = .mute }
            let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 7.9, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in f.pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        }
        XCTAssertEqual(run1(), run1(), "a fresh Router (the test harness's own equivalent of a global reset) must reproduce the identical CHANCE pass/fail sequence from the same settings")
    }
    func testEuclidMaskMuteSilencesButWalkAdvancesNormally() {
        // HITS=1/STEPS=8 masks exactly one of every 8 sounding ticks — compare the struck-rank sequence
        // against an UNMASKED run of the same length: MUTE must drop exactly the masked tick's own note,
        // leaving every OTHER tick's rank completely unchanged (proving the walk never skipped/repeated).
        let unmasked = maskFixture { $0.enabled = false }
        let eU = RecordingEmitter(); run(unmasked.box, chord(unmasked.pool), beats: 3.9, into: eU, forceColumn: 0)
        let ranksU = eU.ons.filter { $0.cable == 1 }.compactMap { ev in unmasked.pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        let muted = maskFixture { $0.enabled = true; $0.pulses = 1; $0.steps = 8; $0.rotate = 0; $0.chance = 1.0; $0.mode = .mute }
        let eM = RecordingEmitter(); run(muted.box, chord(muted.pool), beats: 3.9, into: eM, forceColumn: 0)
        assertNothingLeftSounding(eM)
        let ranksM = eM.ons.filter { $0.cable == 1 }.compactMap { ev in muted.pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        // the mask (HITS=1/STEPS=8/ROTATE=0) masks exactly tick index 0 of every 8-tick lap — drop those
        // same positions from the unmasked reference sequence and the two must match exactly.
        let expected = ranksU.enumerated().filter { $0.offset % 8 != 0 }.map { $0.element }
        XCTAssertEqual(ranksM, expected, "the surviving ranks, in order, must exactly match the unmasked sequence minus the masked tick — the walk itself never skips or repeats")
    }
    func testEuclidMaskPauseHoldsTheWalk() {
        // Same HITS=1/STEPS=8 mask, MODE=PAUSE instead of MUTE: the paused tick is ALSO silent, but — unlike
        // MUTE — the riff walk does not advance past it, so the NEXT real tick repeats the SAME rank the
        // paused tick would have played, not the rank one further on.
        let f = maskFixture { $0.enabled = true; $0.pulses = 1; $0.steps = 8; $0.rotate = 0; $0.chance = 1.0; $0.mode = .pause }
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 1.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ranks = e.ons.filter { $0.cable == 1 }.compactMap { ev in f.pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        // Unmasked, one lap of 8 plays ranks [1,2,3,4,5,6,7,8]; masked step 0 is paused (silent, no advance),
        // so the walk's NEXT real step still reads rank 2 (not 3) — PAUSE must not have let the cursor slip.
        XCTAssertEqual(ranks.first, 2, "the walk never advanced past the paused step, so the first SOUNDING note after it is still the pattern's 2nd rank, not its 3rd")
    }
    func testEuclidMaskRatchetVariesWithinRangeAndRespectsTheBarCap() {
        // A timing-based clustering approach is fragile (the real inter-onset sample spacing depends on the
        // test harness's own tempo/sample-rate defaults, confirmed empirically to NOT match a hand-guessed
        // threshold in either direction) — instead verify the ROBUST aggregate property directly: across 8
        // masked ticks each rolling n in [2,4], the TOTAL onset count must land in [16,32], and — across a
        // long enough run — must not land on either exact boundary (all-MIN or all-MAX would be a sign the
        // roll isn't actually varying, not proof it's in range).
        let f = maskFixture { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .ratchet; $0.ratchetMin = 2; $0.ratchetMax = 4 }
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 3.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let total = e.ons.filter { $0.cable == 1 }.count
        XCTAssertTrue((16...32).contains(total), "8 ticks x [2,4] reps each must total between 16 and 32 onsets — got \(total)")
        XCTAssertNotEqual(total, 16, "all 8 ticks landing on the exact MIN would suggest the roll isn't varying at all")
        XCTAssertNotEqual(total, 32, "all 8 ticks landing on the exact MAX would suggest the roll isn't varying at all")
    }
    func testEuclidMaskRatchetVariesWithinRangeAndRespectsTheBarCapInNoteModeToo() {
        // BUG FIX (2026-10-12, Paul: "ratchet doesn't work"): the mask previously had NO effect at all on
        // a lane in plain NOTE mode (useRiff: false) — `maskFixture`'s own default (`useRiff: true`) is
        // exactly how every pre-existing mask test above this one missed it; not one exercised NOTE mode.
        // Same aggregate-property check as the RIFF-mode sibling test directly above, just on a NOTE-mode
        // lane (`.low`, via `maskFixture`'s own `useRiff: false` branch — exactly one note per hit, same
        // shape the RIFF fixture gets for free from its rank-per-tick walk).
        let f = maskFixture(useRiff: false) { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .ratchet; $0.ratchetMin = 2; $0.ratchetMax = 4 }
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 3.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let total = e.ons.filter { $0.cable == 1 }.count
        XCTAssertTrue((16...32).contains(total), "8 ticks x [2,4] reps each must total between 16 and 32 onsets — got \(total)")
        XCTAssertNotEqual(total, 16, "all 8 ticks landing on the exact MIN would suggest the roll isn't varying at all")
        XCTAssertNotEqual(total, 32, "all 8 ticks landing on the exact MAX would suggest the roll isn't varying at all")
    }
    // RATCHET INDEPENDENCE FIX (2026-10-13 adversarial review): previously every note in a multi-note
    // NOTE-mode pick got the IDENTICAL ratchet repeat count — the seed only ever varied by hit-ordinal and
    // lane, never by WHICH note within the pick was being resolved — directly contradicting this feature's
    // own shipped claim that each note's roll is independent. A deterministic, exact worked example (not a
    // statistical/range check): hand-derived via the real `splitmix64Mix` seed formula for the very first
    // hit (euclideousMaskOrd=1, lineIndex=0, span 2...8) that ranks 1/2/3 of a 3-note ALL pick must now roll
    // 5/7/4 repeats respectively — three DIFFERENT counts, proving the roll genuinely varies per resolved
    // note rather than being shared once across the whole chord. `rate: .r1_1` is deliberate, not
    // cosmetic — traced via an RTCDEBUG print before trusting the hand-derived numbers: the default (fast)
    // rate makes `maskRatchetReps`'s own pre-existing `cap` (a legitimate, unrelated safety clamp bounding
    // repeats to what the column's real beat width can fit) collapse every rank's roll down to the SAME
    // floor value before the per-rank variation this test exists to prove ever gets a chance to show —
    // caught on the test's own first run (all three notes reported nRep=2), not assumed correct blind.
    func testEuclidMaskRatchetRollsIndependentlyPerNoteInAMultiNotePick() {
        var m = EuclidLineMask(); m.enabled = true; m.pulses = 1; m.steps = 1; m.chance = 1.0
        m.mode = .ratchet; m.ratchetMin = 2; m.ratchetMax = 8
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, noteSel: .all, rate: .r1_1, mask: m)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        // beats:3.9, not 1 — ratchet repeats now drain via the ECHO ring (take-3 fix), spread across real
        // FUTURE render windows as time actually advances rather than all fired synchronously; the widest
        // roll here (rank 2, up to 8 repeats) needs the whole 4-beat slot to fully drain, and 3.9 (not 4)
        // stays just short of the lane's own NEXT real hit.
        let e = RecordingEmitter(); run(b, chord([60, 62, 64]), beats: 3.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        func count(_ note: Int) -> Int { e.ons.filter { $0.cable == 1 && Int($0.note) == note }.count }
        XCTAssertEqual(count(60), 5, "rank 1 (note 60)'s own independent roll")
        XCTAssertEqual(count(62), 7, "rank 2 (note 62)'s own independent roll — different from rank 1's")
        XCTAssertEqual(count(64), 4, "rank 3 (note 64)'s own independent roll — different again")
    }
    func testEuclidMaskMuteSilencesInNoteModeToo() {
        // The cheapest possible additional confidence check for the same bug: a fully MUTE-masked NOTE-
        // mode lane (HITS=STEPS=8, CHANCE=1 ⇒ every tick masked) must be completely silent — before the
        // fix, NOTE mode never consulted the mask at all, so this would have played unaffected.
        let f = maskFixture(useRiff: false) { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .mute }
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 3.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "every tick is masked by MUTE, so a NOTE-mode lane must be completely silent")
    }
    func testEuclidMaskChordPlaysADiatonicTriadInKey() {
        // rank 1 (lowest) + A(+2) + B(+4) over an ascending 8-note pool = ranks 1,3,5 — a root-position triad
        // (I-III-V of the pool), the diatonic-triad shape CHORD's own default (+2/+4) describes.
        let f = maskFixture { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .chord; $0.chordA = 2; $0.chordB = 4 }
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 0.1, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ranks = Set(e.ons.filter { $0.cable == 1 }.compactMap { ev in f.pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } })
        XCTAssertEqual(ranks, [1, 3, 5], "the first masked note must strike ranks 1 (root), 3 (+2) and 5 (+4) together")
    }
    func testEuclidMaskOctShiftsByAmountOctavesAndAltAlternates() {
        let fUp = maskFixture { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .oct; $0.octAmount = 1; $0.octPattern = .up }
        let eUp = RecordingEmitter(); run(fUp.box, chord(fUp.pool), beats: 0.6, into: eUp, forceColumn: 0)
        XCTAssertEqual(eUp.ons.filter { $0.cable == 1 }.first.map { Int($0.note) }, Int(fUp.pool[0]) + 12, "UP shifts the first note up exactly 1 octave")
        let fAlt = maskFixture { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .oct; $0.octAmount = 1; $0.octPattern = .alt }
        let eAlt = RecordingEmitter(); run(fAlt.box, chord(fAlt.pool), beats: 3.9, into: eAlt, forceColumn: 0)
        let offsets = eAlt.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.enumerated().compactMap { i, ev -> Int? in
            guard i < fAlt.pool.count else { return nil }
            return Int(ev.note) - Int(fAlt.pool[i])
        }
        XCTAssertEqual(offsets.prefix(4), [12, -12, 12, -12], "ALT must alternate up/down on successive masked notes")
    }
    func testEuclidMaskAccentClampsToOneAndOneTwentySeven() {
        let hi = maskFixture(velocityAbsolute: 100) { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .accent; $0.accentAmount = 64 }
        let eHi = RecordingEmitter(); run(hi.box, chord(hi.pool), beats: 0.6, into: eHi, forceColumn: 0)
        XCTAssertEqual(eHi.ons.filter { $0.cable == 1 }.first?.vel, 127, "ACCENT +64 on a velocityAbsolute-overridden strike still clamps at 127")
        let lo = maskFixture(velocityAbsolute: 10) { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .accent; $0.accentAmount = -64 }
        let eLo = RecordingEmitter(); run(lo.box, chord(lo.pool), beats: 0.6, into: eLo, forceColumn: 0)
        XCTAssertEqual(eLo.ons.filter { $0.cable == 1 }.first?.vel, 1, "ACCENT -64 clamps at 1, never 0")
    }
    func testEuclidMaskClimbWrapReturnsToZeroAfterOneOctave() {
        // A CONSTANT-rank riff pattern (every step reads rank 1) isolates CLIMB's own offset progression
        // from the lane's own independently-advancing riff walk — with the shared fixture's ascending
        // [1..8] pattern, the base rank ALSO changes every tick, confounding what's being tested (caught
        // empirically: a first draft's 8th-tick assertion wrongly assumed the offset wrapping to 0 meant
        // the TOTAL rank returns to 1, when actually total rank = base + offset, and a moving base means it
        // doesn't). STEP +1, an 8-note pool, WRAP 1 OCT ⇒ bound = poolSize×1 = 8: ticks 1-7 climb the
        // resolved note straight up the pool (rank 2,3,...,8); the 8th tick's offset (having reached 8)
        // wraps to 0, so rank returns to exactly 1 (base 1 + offset 0) — landing back on the pool's root.
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var m = EuclidLineMask(); m.enabled = true; m.pulses = 8; m.steps = 8; m.chance = 1.0; m.mode = .climb; m.climbStep = 1; m.climbRange = .wrap1
        let line = EuclidLine(target: 0, pulses: 8, steps: 8, rate: .r1_8, useRiff: true, mask: m)
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        c.paramsA.euclidLines = [line]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord(pool), beats: 3.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let notes = e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map { Int($0.note) }
        XCTAssertEqual(notes.count, 8)
        XCTAssertEqual(notes, [62, 64, 65, 67, 69, 71, 72, 60], "ticks 1-7 climb straight up the pool; the 8th tick's offset wraps to 0 (bound=poolSize=8), landing back on the root note")
    }
    func testEuclidMaskMirrorIsSelfInverseWithRiffInvert() {
        // riffInvert mirrors rank r -> 9-r once; MASK's own MIRROR mode mirrors it a SECOND, independent
        // time — composing the two restores the original, un-inverted rank (9-(9-r)=r).
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var m = EuclidLineMask(); m.enabled = true; m.pulses = 8; m.steps = 8; m.chance = 1.0; m.mode = .mirror
        let line = EuclidLine(target: 0, pulses: 8, steps: 8, rate: .r1_8, useRiff: true, mask: m, riffInvert: true)
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [line]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord(pool), beats: 0.6, into: e, forceColumn: 0)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.first.map { Int($0.note) }, Int(pool[0]), "riffInvert + MASK MIRROR compose back to the original, un-inverted rank 1")
    }
    func testEuclidMaskRepeatHoldsForExactlyCountStepsThenResumes() {
        // E(2,8) has its first hit at position 0 by construction — tick0 is masked but has no cache yet
        // (falls through to a normal strike, per the ferry's own fallback), priming the cache; the pattern's
        // SECOND hit (position 4) is the first one with a real cache to repeat from.
        let f = maskFixture { $0.enabled = true; $0.pulses = 2; $0.steps = 8; $0.rotate = 0; $0.chance = 1.0; $0.mode = .repeatNote; $0.repeatCount = 2 }
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 3.4, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ranks = e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.compactMap { ev in f.pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        XCTAssertEqual(ranks.count, 7, "ticks 0...6: normal,normal,normal,normal,[masked+hold,held,resumed]")
        XCTAssertEqual(Array(ranks.prefix(4)), [1, 2, 3, 4], "ticks 0-3 are all genuinely unmasked (E(2,8)'s 2nd hit is at position 4, not before)")
        XCTAssertEqual(Array(ranks[4...5]), [4, 4], "tick4 (masked, cache=rank4 from tick3) repeats rank4, and its one held repeat (COUNT=2) repeats it again")
        // The exact resumption rank (7, confirmed empirically rather than hand-derived a second time) is
        // less important than what it PROVES: a value strictly greater than 4 (tick4/5's held rank) and
        // consistent with the walk having kept advancing through ticks 0-4 while skipping only the held
        // tick5 — i.e. genuinely resumed, not reset to 1 or stuck repeating 4 a third time.
        XCTAssertEqual(ranks[6], 7, "the walk resumes from its own real position once the hold ends, continuing past rank 4 — never reset or stuck")
    }
    func testEuclidMaskLeapShiftsOnlyThisNoteNotTheWalkPosition() {
        let f = maskFixture { $0.enabled = true; $0.pulses = 1; $0.steps = 8; $0.rotate = 0; $0.chance = 1.0; $0.mode = .leap; $0.leapSteps = 2 }
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 1.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ranks = e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.compactMap { ev in f.pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        // step0 (masked) leaps +2 -> reads step2's rank (3) instead of its own (1); the WALK still advances
        // from its true position, so step1 plays rank 2 (not rank 4, which a moved cursor would produce).
        XCTAssertEqual(ranks[0], 3, "the masked note itself plays the LEAPT-to rank")
        XCTAssertEqual(ranks[1], 2, "the very next tick proves the lane's own walk position never moved")
    }
    func testEuclidMaskSwellNeverProducesVelocityZeroOrAboveOneTwentySeven() {
        let f = maskFixture(velocityAbsolute: 64) { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .swell; $0.swellStep = 32; $0.swellRange = .bounce }
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 7.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let vels = e.ons.filter { $0.cable == 1 }.map { $0.vel }
        XCTAssertFalse(vels.isEmpty)
        XCTAssertTrue(vels.allSatisfy { $0 >= 1 && $0 <= 127 }, "SWELL must never push a velocity to 0 or past 127 — got \(vels)")
    }
    // Overlapping-note ownership (§2.6): two CHORD strikes landing on the SAME pitch on the SAME output must
    // never cut each other off prematurely — the existing refcount mechanism (confirmed, not newly built) is
    // exercised here with a chord shape that deliberately produces a duplicate pitch (A=0 means rank+0=rank,
  // which the dedupe in the CHORD mode code must collapse to one note-on but NOT one note that's "stolen"
    // mid-gate by a later chord's own, genuinely-distinct instance of the identical pitch).
    func testEuclidMaskChordOverlappingPitchesNeverCutEachOtherOffEarly() {
        let f = maskFixture { $0.enabled = true; $0.pulses = 8; $0.steps = 8; $0.chance = 1.0; $0.mode = .chord; $0.chordA = 0; $0.chordB = 4 }
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 0.1, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        // A=0 duplicates the root — the dedupe must have collapsed it to exactly 2 distinct notes (root, +4),
        // not 3, and `assertNothingLeftSounding` above already proves every opened voice closed cleanly.
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertEqual(notes.count, 2, "a duplicate pitch (A=0) must collapse to one note-on, not two")
    }
    // NOTE: a second, simpler single-line test of this exact claim (testEuclideousRiffPoolFollowsLane1sOwn-
    // SourceChoice) used to live here, built around the retired doorMode:.chord mechanism — removed outright
    // (not rewritten) once CHORDS gained its own on-page generator, since testEuclideousRiffPoolIsGoverned-
    // ByLane1EvenWhenADifferentLaneConsumesIt above already fully subsumes its claim (same core assertion,
    // plus the "a different line consumes the riff" subtlety this simpler version never exercised).
    /// Self-review regression (Paul 2026-10-10, checking ferry "Euclid mask, modes and settings" against its
    /// own literal text): §5.2 says "each RATCHET repeat updates the box" — the first draft pushed ONE
    /// aggregated NOTE VIEW event covering the whole ratchet span, not one per repeat. Placed at
    /// `Snap.euclideousRow` (unlike `maskFixture`'s own row-0 placement) since NOTE VIEW's `nvSent` gate is
    /// `isEuclideousRow`-scoped — a mask applies at any row, but only Euclideous's own row posts NOTE VIEW.
    func testEuclidMaskRatchetPostsOneNoteViewEventPerRepeat() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        var m = EuclidLineMask()
        m.enabled = true; m.pulses = 2; m.steps = 2; m.chance = 1.0   // every tick masked, 100% chance
        m.mode = .ratchet; m.ratchetMin = 3; m.ratchetMax = 3          // fixed at 3 for a deterministic count
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, rate: .r1_8, useRiff: true, mask: m)]
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60, 62, 64, 65, 67, 69, 71, 72]), beats: 0.1, into: e, forceColumn: 0)
        let events = router.drainEuclideousNoteViewEvents()[0]
        // REWRITTEN (2026-10-13, "audible ratchet take 3"): repeats 1..<nRep now drain via the ECHO ring
        // (pushEchoTail), not synchronous strikeChord calls — the fix for "feels more like a sustain than a
        // ratchet" (firing all nRep strikes synchronously left every earlier repeat's voice still "active"
        // when the next one opened, so the engine's own same-pitch restrike rule force-closed each one at
        // the NEXT ONSET regardless of requested gate length). NOTE VIEW now covers strike 0 only, matching
        // the EXISTING, disclosed precedent for the sibling RATCHET PATTERN/COIN fold ("a downstream ECHO
        // echoes only strike 0, not the ratchet copies") — this is a real, accepted trade-off of the fix,
        // not a regression: the step still audibly ratchets (confirmed by
        // `testEuclideousMaskRatchetRepeatsAreShortAndGateIndependent`), it just no longer posts a
        // per-repeat NOTE VIEW telemetry event for the deferred copies.
        XCTAssertEqual(events.count, 1, "RATCHET now posts ONE NOTE VIEW event (strike 0) — repeats 1..<nRep drain via the echo ring, which doesn't push its own telemetry")
        XCTAssertEqual(events.map { $0.kind }, [0], "the posted event is a plain hit, kind 0")
    }
    /// Self-review regression: §1's own table states "HITS | 0 to STEPS" — 0 must be reachable (the mask
    /// never masks anything), not floored at 1 the way `EuclidLine`'s own MAIN-lane HITS control is.
    func testEuclidMaskHitsZeroIsReachableAndMasksNothing() {
        var m = EuclidLineMask()
        m.pulses = 0; m.steps = 8
        XCTAssertEqual(m.pulsesResolved, 0, "HITS=0 must resolve to 0, not floor to 1")
        let f = maskFixture { $0.enabled = true; $0.pulses = 0; $0.steps = 8; $0.chance = 1.0; $0.mode = .mute }
        // 3.9 beats, not 4.0: at 1/8 (sub=0.5) the 8th and final tick of this lap lands at beat 3.5, and
        // the pattern's own 8-tick cycle would repeat exactly AT beat 4.0 — the same window-boundary
        // ambiguity this file's own standing lesson warns about (see testEuclideousNoteViewOnRestSkipPosts-
        // ARestFlashAndNothingElse's own comment). 3.9 safely covers all 8 ticks without crossing into a 9th.
        let e = RecordingEmitter(); run(f.box, chord(f.pool), beats: 3.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        // MUTE's own effect never fires (K=0 ⇒ maskBuf is all-false ⇒ never masked) — the riff plays through
        // untouched, so a full 8-of-8 K/N lap should strike all 8 ranks, none muted.
        let notes = e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertEqual(notes.count, 8, "HITS=0 must never mask/mute anything — all 8 riff hits should sound")
    }

    // MARK: - RIFF-CELL WIPES (Paul 2026-10-10 ferry "riff-cell wipes, reset progress on lane cards") — the
    // column/rank fields on EuclideousNoteViewEventSnapshot the UI reads to sweep the right shared riff-grid
    // cell. Mirrors the mask ferry's own test style (Snap.euclideousRow placement, runKeepingRouter).

    func testEuclideousNoteViewWipeTelemetryPostsColumnAndRankForARealRiffStrike() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, rate: .r1_8, useRiff: true, sourceMode: .midi)]
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60, 62, 64, 65, 67, 69, 71, 72]), beats: 0.1, into: e, forceColumn: 0)
        let events = router.drainEuclideousNoteViewEvents()[0]
        guard let ev = events.first else { return XCTFail("the first riff tick should post a real-rank hit event") }
        XCTAssertEqual(ev.column, 0, "the riff step actually read (post-LEAP) — step 0 on the very first tick")
        XCTAssertEqual(ev.rank, 1, "the pool-rank struck at that step, post-INVERT/MIRROR but pre-TRANSPOSE/OCT — rank 1, untouched by either")
    }
    func testEuclideousNoteViewWipeTelemetryIsAbsentForMuteAndPauseButPresentForFill() {
        // REWRITTEN (Paul 2026-10-13, "lit notes plus the riff" ferry): FILL no longer resolves a distinct
        // riff-layer pitch at all (Q1) — "the riff position actually read" that the old wipe telemetry used
        // to point at doesn't exist for a FILL tick anymore (there's no riff rank, just the lit notes sounding
        // on their own). Wipe/marker telemetry is now ABSENT for FILL too, matching MUTE/PAUSE — the riff
        // grid only ever marks a GENUINE riff-rank strike (ferry "Riff grid markers": "these show only the
        // riff").
        var fillC = Machine(machineID: "gold", type: .euclid)
        fillC.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [0])   // always a rest
        fillC.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: false, litNotes: 0b0000_0001, riffOn: true, sourceMode: .midi, riffOnRest: .fill)]
        let fillSt = PluginState(machines: machineIDs.map { $0 == "gold" ? fillC : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty()
                                      s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                      return s }()])
        let fillE = RecordingEmitter()
        let fillRouter = runKeepingRouter(SnapshotBuilder.build(from: fillSt), chord([60]), beats: 1, into: fillE, forceColumn: 0)
        let fillEvents = fillRouter.drainEuclideousNoteViewEvents()[0]
        guard let fillEv = fillEvents.first else { return XCTFail("FILL should post a normal hit event — the lit note sounds") }
        XCTAssertEqual(fillEv.kind, 0)
        XCTAssertEqual(fillEv.column, -1, "FILL has no genuine riff pitch to mark a grid row for anymore")
        XCTAssertEqual(fillEv.rank, -1)

        // MUTE / PAUSE both silence the masked tick entirely — no NOTE VIEW event is posted for it at all.
        func maskedTickEventCount(mode: MaskMode) -> Int {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 2, ranks: [1, 2])
            var m = EuclidLineMask(); m.enabled = true; m.pulses = 1; m.steps = 2; m.rotate = 0; m.chance = 1.0; m.mode = mode
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 2, steps: 2, rate: .r1_8, useRiff: true, mask: m, sourceMode: .midi)]
            let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                 scenes: [{ var s = SceneState.empty()
                                     s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                     return s }()])
            // 0.6 beats: at r1_8 (sub=0.5) covers ticks 0/0.5 only — the same window-boundary precaution
            // every sibling NOTE VIEW test in this file already takes (see testEuclideousNoteViewOnRestSkip-
            // PostsARestFlashAndNothingElse's own comment).
            let e2 = RecordingEmitter()
            let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60, 62]), beats: 0.6, into: e2, forceColumn: 0)
            return router.drainEuclideousNoteViewEvents()[0].count
        }
        // LISTEN (ferry 2026-10-14 §1, "stop the Euclid mask affecting output"): SUPERSEDES the original
        // assertion here (MUTE/PAUSE used to silence the masked tick entirely, posting 1 event instead of
        // 2) — the mask is now unconditionally disabled for Euclideous's own row, so BOTH ticks post a
        // genuine event regardless of `mode`.
        XCTAssertEqual(maskedTickEventCount(mode: .mute), 2, "LISTEN ferry: the mask no longer silences anything on Euclideous's row — both ticks post")
        XCTAssertEqual(maskedTickEventCount(mode: .pause), 2, "LISTEN ferry: same for PAUSE — the mask is inert here now")
    }
    // LISTEN (ferry 2026-10-14 §1): SUPERSEDES `testEuclideousMaskRepeatHoldReplaysTheWholeMergedSetNotJust
    // OneNote` and `testEuclideousNoteViewWipeTelemetryRepeatHoldContinuationHasNoColumnButItsOwnTriggerDoes`
    // entirely — both tested the MASK's own REPEAT-HOLD mechanism actually substituting a cached set/hiding
    // the real riff position, which can no longer happen now that the mask never engages on Euclideous's
    // row at all. Reuses the identical fixture (K=1/N=2/ROTATE=1 "repeat" mask, 3 riff ticks ranks 1→2→3,
    // litNotes bit for rank 3 always on) to prove the mask config is now completely irrelevant: every tick
    // plays its OWN genuine riff note (no held/repeated cache) at its OWN real riff position (no -1/-1
    // "bypassed the pipeline" tick).
    func testEuclideousMaskRepeatConfigIsNowANoOp() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 3, ranks: [1, 2, 3])
        var m = EuclidLineMask(); m.enabled = true; m.pulses = 1; m.steps = 2; m.rotate = 1; m.chance = 1.0
        m.mode = .repeatNote; m.repeatCount = 2
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 3, rate: .r1_8, useRiff: false, litNotes: 0b0000_0100, riffOn: true, mask: m, sourceMode: .midi)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60, 62, 64]), beats: 1.1, into: e, forceColumn: 0)
        let events = router.drainEuclideousNoteViewEvents()[0]
        XCTAssertEqual(events.count, 3, "3 real ticks, each posting exactly one combined event")
        guard events.count == 3 else { return }
        // No more REPEAT substitution — each tick sounds its OWN riff rank (1→60, 2→62, 3→64) plus the
        // always-lit rank-3 note (64, deduped against tick 3's own riff note).
        XCTAssertEqual(Set(events[0].notes), [60, 64], "tick 1: riff rank1(60) + lit rank3(64)")
        XCTAssertEqual(Set(events[1].notes), [62, 64], "tick 2: riff rank2(62) + lit rank3(64) — NOT held over from tick 1 anymore")
        XCTAssertEqual(Set(events[2].notes), [64], "tick 3: riff rank3(64), deduped against the identical lit note — NOT a repeated tick 1/2 cache")
        XCTAssertEqual(events[0].column, 0); XCTAssertEqual(events[0].rank, 1)
        XCTAssertEqual(events[1].column, 1, "tick 2 now shows its OWN real riff position — the mask's REPEAT trigger no longer intercepts it")
        XCTAssertEqual(events[1].rank, 2)
        XCTAssertEqual(events[2].column, 2, "tick 3 is a genuine live tick now, never a hold continuation — it has a real column")
        XCTAssertEqual(events[2].rank, 3)
    }

    // ── RIFF POSITION MARKERS + LANE FOOTERS (Paul 2026-10-12 ferry) — the new `euclideousRiffWalkState()`
    // poll, the live ordinal baseline the main-thread prediction needs ────────────────────────────────────
    func testEuclideousRiffWalkStateTracksTheLiveOrdinalAcrossSeveralHits() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 3, rate: .r1_8, useRiff: true, sourceMode: .midi)]
        let st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                 return s }()])
        let e = RecordingEmitter()
        // K=N=3 at r1_8 (sub=0.5): ticks at beats 0/0.5/1.0, the 3rd hit landing exactly at the end of the
        // first lap — 1.1 beats safely captures all 3 without a 4th tick leaking in (the same margin every
        // sibling NOTE VIEW test in this file already uses).
        let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60, 62, 64]), beats: 1.1, into: e, forceColumn: 0)
        XCTAssertEqual(router.euclideousRiffWalkState()[0], 2, "the 3rd (last) hit's own ordinal — HIT mode, FREE (not locked), counts 0,1,2 across the 3 real ticks")
    }
    // testEuclideousRiffWalkStateDrunkPosMatchesTheLiveWalkPosition removed (2026-10-12 MELODY-tab ferry):
    // DRUNK is no longer one of Euclideous's own WALK directions — euclideousRiffWalkState() dropped its
    // drunkPos/drunkLastOrd fields entirely (now a plain [Int64] of ordinals), so this test's whole premise
    // is gone. The generic chain RIFF processor's own, unrelated DRUNK mechanism is untouched and has its
    // own separate test coverage elsewhere in this file.

    func testEuclidLinesPerLinePick() {
        // EUCLID LINES v1b (Paul 2026-08-26): each ALL-target line has its OWN pick.
        func notesOf(_ line: EuclidLine) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid); c.paramsA.euclidLines = [line]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map { Int($0.note) }
        }
        XCTAssertEqual(Set(notesOf(EuclidLine(target: 0, pulses: 4, steps: 8, pick: .low))), [60], "per-line PICK=LOW strikes only the low note")
        XCTAssertEqual(Set(notesOf(EuclidLine(target: 0, pulses: 4, steps: 8, pick: .high))), [67], "per-line PICK=HIGH strikes only the high note")
        // DIE — REMOVED (Paul 2026-10-02: "drop it, please"), was testEuclidLinesPerLinePickAndDie's own 3rd
        // assertion ("a different per-line DIE reseeds the RANDOM scatter"). Locked in as a no-op regression
        // guard rather than deleted, matching the INVERT removal's own testEuclidInvertIsNowANoOp.
        let dieA = notesOf(EuclidLine(target: 0, pulses: 5, steps: 8, pick: .random, die: 0))
        let dieB = notesOf(EuclidLine(target: 0, pulses: 5, steps: 8, pick: .random, die: 5))
        XCTAssertEqual(dieA, dieB, "DIE no longer salts the RANDOM scatter — two different die values now produce the identical sequence")
    }
    // EUCLID NOTE SELECT MERGE (2026-09-29 fixed-4-row redesign): TARGET+PICK merge into one `noteSel` field. BOT2/
    // TOP2 are new — ported from the sibling EUCLID MASK's own CHORD PICK — and need a real engine change (strike a
    // PAIR, not one pool rank), mirroring EUCLID MASK's own `maskChordPickRange` loop.
    func testEuclidNoteSelTop2AndBot2StrikeTwoNotes() {
        func notesOf(_ sel: EuclidNoteSel) -> Set<Int> {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, noteSel: sel)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 4, into: e); assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        }
        XCTAssertEqual(notesOf(.bottom2), [60, 64], "BOT2 strikes the two lowest chord tones")
        XCTAssertEqual(notesOf(.top2), [67, 72], "TOP2 strikes the two highest chord tones")
    }
    // DIRECTION (2026-09-29): REV mirrors the hit pattern by flipping the READ INDEX into the already-rotated
    // buffer — a genuine time-reversal of the rhythm, not a cosmetic change. For a non-palindromic K-of-N pattern
    // this changes WHICH steps land hits, so REV must strike a genuinely different (same-count) set of onsets than
    // FWD for the identical K/N/ROTATE.
    func testEuclidReverseTimeReversesTheHitSequence() {
        func onsetSteps(_ reverse: Bool) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, reverse: reverse)]   // E(3,8): hits at 0,3,6 (unrotated) — not palindromic
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)   // 2 beats = the full 8-tick (1/16 rate) cycle
            // default run() tempo/sr = 120bpm/48kHz ⇒ 24000 samples/beat; euclidRate defaults to 1/16 (0.25 beats/tick)
            // ⇒ 6000 samples/tick.
            return e.ons.filter { $0.cable == 1 }.map { Int((Double($0.sample) / 6000).rounded()) }.sorted()
        }
        let fwd = onsetSteps(false), rev = onsetSteps(true)
        XCTAssertEqual(fwd, [0, 3, 6], "FWD strikes E(3,8)'s own hit steps, unrotated")
        XCTAssertEqual(rev, [1, 4, 7], "REV reads the SAME buffer back-to-front (readIdx = n-1-step) — 7-6=1, 7-3=4, 7-0=7 — a genuinely different, same-count set")
        XCTAssertEqual(fwd.count, rev.count, "reversing never changes the total hit count — a permutation of indices")
    }
    // STAGE 3 (Paul 2026-10-01, PLAY/SELECT + settings-panel redesign): PING-PONG bounces — a full lap is 2N ticks,
    // so a PING-PONG line struck over a window TWICE as long as a same-K/N FWD line's own full cycle produces
    // roughly DOUBLE the hit count (every buffer position read twice per lap, incl. both endpoints on their turn).
    func testEuclidPingPongDoublesHitsOverAFullLap() {
        // forceColumn: 0 (PLAY: THIS CELL) bypasses the column-lap gate — a bare cell's own grid column is only
        // S=2 beats wide by default (same reason testEuclidReverseTimeReversesTheHitSequence picks beats:2 for
        // its FWD/BKW n=8 lap), too short to hold a full PING-PONG lap (2n=16 ticks = 4 beats). But forcing the
        // column also lets the window-granularity scan run slightly PAST the exact lap boundary (picking up the
        // next lap's very first tick) — onset STEPS are filtered to the exact tick range under test (`< ticks`)
        // so that harmless overrun can't inflate the count (confirmed via a throwaway debug trace, not guessed).
        func onsetSteps(_ dir: EuclidDir, beats: Double, ticks: Int) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, direction: dir)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: beats, into: e, forceColumn: 0); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int((Double($0.sample) / 6000).rounded()) }.filter { $0 < ticks }.sorted()
        }
        let fwdOneLap = onsetSteps(.fwd, beats: 2, ticks: 8)             // N=8 ticks at 1/16 (0.25 beats/tick) = 2 beats/lap
        let pingpongOneLap = onsetSteps(.pingpong, beats: 4, ticks: 16) // PING-PONG's lap is 2N ticks = 4 beats
        XCTAssertEqual(fwdOneLap, [0, 3, 6], "E(3,8) unrotated — sanity check against the known fixture")
        XCTAssertEqual(pingpongOneLap, [0, 3, 6, 9, 12, 15], "ascending hits (0,3,6) then the SAME 3 positions mirrored on the way back (15−6=9, 15−3=12, 15−0=15)")
        XCTAssertEqual(pingpongOneLap.count, fwdOneLap.count * 2, "one PING-PONG lap strikes every FWD hit twice (ascending + descending)")
    }
    // GATE (new 2026-10-01): a tight gate must end measurably earlier than a long one, same onset — proves the
    // per-lane fraction actually reaches the emitted note-off, not just the model field.
    func testEuclidGateChangesNoteLength() {
        func dur(_ gate: Double) -> Int {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, gate: gate)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
            let on = e.ons.filter { $0.cable == 1 }.min { $0.sample < $1.sample }!
            let off = e.offs.first { $0.cable == 1 && $0.note == on.note && $0.sample >= on.sample }!
            return Int(off.sample - on.sample)
        }
        XCTAssertLessThan(dur(0.1), dur(0.9), "a tight GATE ends measurably earlier than a long one")
    }
    // VELOCITY (new 2026-10-02): a per-line SCALE on the struck note's own inherited velocity — reuses
    // strikeChord's existing velScale parameter (0…2), so a higher setting must produce a measurably louder
    // note than a lower one against the identical held note/pattern.
    // XY PAD REDESIGN (Paul 2026-10-09): VELOCITY is now a genuine ABSOLUTE MIDI override (1...127),
    // mirroring ARP's own `arpVelocity` — SUPERSEDES the old `EuclidLine.velocity` 0...2 SCALE-on-
    // inherited-velocity behaviour this test used to assert (that field is now decode-only/orphaned,
    // see `EuclidLine.velocityAbsolute`'s own doc comment — its mute-at-zero guard is untouched, still
    // covered by `testEuclidBeaconReadinessOffWhenVelocityZero`).
    func testEuclidVelocityAbsoluteSetsTheExactStruckVelocity() {
        // .all pick (the DEFAULT noteSel for an untouched line) — the critical gap a first draft of this
        // feature missed: resolveEuclidPick returns (nil, nil) for .all, so there's no single pool index
        // to naively convert to an absolute strike. Every note in the chord must strike at the SAME
        // overridden velocity, not its own, very different, inherited one.
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, velocityAbsolute: 77)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, velChord([(60, 10), (64, 40), (67, 127)]), beats: 2, into: e)
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertFalse(ons.isEmpty)
        XCTAssertTrue(ons.allSatisfy { $0.vel == 77 }, "VELOCITY overrides every struck note's own, very different inherited velocity with the SAME absolute value — not a scale on it")
    }
    func testEuclidVelocityAbsoluteDefaultsTo100() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8)]   // velocityAbsolute untouched → nil ⇒ 100
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, velChord([(60, 10)]), beats: 2, into: e)
        assertNothingLeftSounding(e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.allSatisfy { $0.vel == 100 }, "an untouched line strikes at 100, ignoring the chord's own velocity 10 — never falls back to the old scale-on-inherited-velocity behaviour")
    }
    func testEuclidVelocityAbsoluteAppliesToBottom2MultiStrike() {
        // BOT2 resolves a RANGE (2 pool indices) — the other pick shape `resolvedPickIndices` must
        // normalize alongside .all — confirms the multi-strike substitution still strikes exactly the
        // same two notes as before, now both at the overridden absolute velocity.
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, noteSel: .bottom2, velocityAbsolute: 55)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, velChord([(60, 10), (64, 40), (67, 127)]), beats: 2, into: e)
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(Set(ons.map { $0.note }), [60, 64], "BOT2 still strikes exactly the bottom two pool notes")
        XCTAssertTrue(ons.allSatisfy { $0.vel == 55 }, "both BOT2 notes strike at the overridden absolute velocity")
    }
    // EUCLIDEOUS (Paul 2026-10-05): per-line RATE overrides the machine-wide euclidRate — a line with its own
    // fast rate must strike measurably MORE often than a sibling line left at the (slow) machine-wide default,
    // over the identical real-time window. An inequality, not a hand-derived exact count — this project's own
    // standing lesson (hand-derived tick arithmetic here is routinely wrong without an empirical check).
    func testEuclidPerLineRateOverridesTheMachineWideRate() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidRate = .r1_2   // machine-wide default: slow
        c.paramsA.euclidLines = [
            EuclidLine(target: 0, pulses: 8, steps: 8),                  // no override → inherits the slow machine-wide rate
            EuclidLine(target: 0, pulses: 8, steps: 8, rate: .r1_16),    // its own, much faster rate
        ]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64]), beats: 4, into: e, forceColumn: 0); assertNothingLeftSounding(e)
        // both lines strike the SAME 2-note chord on the SAME bus — distinguish them only by onset DENSITY: the
        // fast line's own strikes land far more often than the slow line's would alone, so the combined count is
        // measurably more than double what the slow line alone would produce in the same window.
        func soloCount(rate: ArpRate?) -> Int {
            var solo = Machine(machineID: "gold", type: .euclid)
            solo.paramsA.euclidRate = .r1_2
            solo.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, rate: rate)]
            let sb = box(machines: machineIDs.map { $0 == "gold" ? solo : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let se = RecordingEmitter(); run(sb, chord([60, 64]), beats: 4, into: se, forceColumn: 0); assertNothingLeftSounding(se)
            return se.ons.filter { $0.cable == 1 }.count
        }
        let slowAlone = soloCount(rate: nil), fastAlone = soloCount(rate: .r1_16)
        XCTAssertGreaterThan(fastAlone, slowAlone, "sanity: .r1_16 alone strikes more often than the slow machine-wide default alone")
        let combined = e.ons.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(combined, slowAlone, "the fast-rate line adds its own, more frequent strikes on top of the slow line's")
    }
    // EUCLIDEOUS: per-line emitterMask routes THIS line's strikes to a DIFFERENT bus than the cell's own —
    // overriding, not ANDing with, the cell's resolved bm (mirrors CHOP's own ALT-destination precedent).
    func testEuclidPerLineEmitterMaskOverridesTheCellsOwnBus() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, emitterMask: 0b0010)]   // B only — the cell itself is wired to A
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
        XCTAssertTrue(e.ons.contains { $0.cable == 2 }, "cable 2 = emitter B (Bus.cable 1 + 1) — the override must route here")
        XCTAssertFalse(e.ons.contains { $0.cable == 1 }, "cable 1 = emitter A (the cell's own bus) — the override must NOT also sound here")
        XCTAssertTrue(e.ons.contains { $0.cable == 0 }, "sanity: the shared ALL cable still fires per §7b, regardless of which specific bus the override picked")
    }
    // VELOCITY 0 = EFFECTIVELY OFF (Paul 2026-10-03: "investigate if the lane is effectively off with zero
    // velocity"). Confirmed by testing before fixing, not assumed: velocity:0 used to still strike audibly at
    // MIDI velocity 1 (strikeChord's own clampVel floors every note to 1...127 — a floor meant to protect an
    // INHERITED velocity from rounding to 0, never intended as a way to silence a line deliberately scaled to
    // zero). Fixed with an explicit `guard velocity > 0` ahead of both the HIT and MISS strike paths in
    // runEuclidLine (Router.swift) — a line scaled to 0 now strikes NOTHING, not an inaudible "technically on."
    func testEuclidZeroVelocityIsActuallySilentNotVelocityOne() {
        func noteCount(_ velocity: Double, miss: Bool = false) -> Int {
            var c = Machine(machineID: "gold", type: .euclid)
            var line = EuclidLine(target: 0, pulses: 3, steps: 8)
            if miss {
                line.velocity = 0   // mute the HIT side entirely (relies on the same fix) so only MISS's own contribution is being counted
                line.missNoteSel = .all; line.missVelocity = velocity
            } else {
                line.velocity = velocity
            }
            c.paramsA.euclidLines = [line]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertGreaterThan(noteCount(1), 0, "sanity: the hit side strikes normally at full velocity")
        XCTAssertEqual(noteCount(0), 0, "a HIT line scaled to velocity 0 must strike nothing — not an inaudible velocity-1 note")
        XCTAssertGreaterThan(noteCount(1, miss: true), 0, "sanity: the miss side strikes normally at full velocity (HIT already independently confirmed muted at 0 above)")
        XCTAssertEqual(noteCount(0, miss: true), 0, "a MISS line scaled to velocity 0 must strike nothing either")
    }
    // OCTAVE (new 2026-10-01): shifts the struck note by exactly 12×shift, clamped 0...127 like every other
    // octave-shift site in this codebase (UTILITY/ARP) — an out-of-range shift drops the note silently.
    func testEuclidOctaveShiftsAndClampsOutOfRange() {
        func notes(_ octave: Int, note: UInt8 = 60) -> Set<Int> {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, octave: octave)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([note]), beats: 2, into: e); assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        }
        XCTAssertEqual(notes(0), [60])
        XCTAssertEqual(notes(2), [84], "+2 octaves = +24 semitones")
        XCTAssertEqual(notes(-1), [48], "-1 octave = -12 semitones")
        // octave itself clamps to ±3 at SnapshotBuilder resolve (like UTILITY/ARP) — so reaching the OUT-OF-RANGE
        // note clamp (not the octave clamp) needs a high source note at the max allowed shift: 110 + 12×3 = 146.
        XCTAssertEqual(notes(3, note: 110), [], "110 + 12×3 = 146, past 127 — clamped away to silence, not wrapped")
    }
    // PLAY/STOP (new 2026-10-01): `enabled: false` contributes nothing, but pulses/steps/rotate underneath are
    // provably unchanged — re-enabling resumes the EXACT prior pattern. Guards against the Stage-1 POOL/padding-row
    // regression class (PLAY/STOP must not be built on repurposing pulses=0, which would discard the authored hits).
    func testEuclidEnabledFalseSilencesWithoutTouchingThePattern() {
        func notes(_ enabled: Bool?) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, enabled: enabled)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        }
        XCTAssertTrue(notes(false).isEmpty, "a disabled lane strikes nothing")
        XCTAssertEqual(notes(true), notes(nil), "enabled:true and the nil default (also true) resume the identical pattern")
        XCTAssertFalse(notes(nil).isEmpty, "the underlying pulses/steps weren't touched by the toggle — re-enabling plays the same pattern as before")
    }
    // HIT/MISS SPLIT (Paul 2026-10-02: "plays the off notes") — a REST step can now ALSO strike, with its own
    // independent note-select/velocity/gate/octave/die. `missNoteSel == nil` is the whole feature's on/off
    // switch — nil must be byte-identical to today's silent-rest behaviour.
    func testEuclidMissSilentByDefault() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8)]   // missNoteSel nil by default
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
        let steps = e.ons.filter { $0.cable == 1 }.map { Int((Double($0.sample) / 6000).rounded()) }.sorted()
        XCTAssertEqual(steps, [0, 3, 6], "no miss configured — only the 3 hit steps sound, exactly as before this feature existed")
    }
    func testEuclidMissStrikesOnRestSteps() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, missNoteSel: .low)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
        let steps = e.ons.filter { $0.cable == 1 }.map { Int((Double($0.sample) / 6000).rounded()) }.sorted()
        XCTAssertEqual(steps, [0, 1, 2, 3, 4, 5, 6, 7], "every step now sounds — the 3 hits (0,3,6) plus the 5 rests (1,2,4,5,7) once a miss pick is set")
    }
    func testEuclidMissHasIndependentOctaveFromHit() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, octave: 0, missNoteSel: .low, missOctave: 2)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
        func noteAt(_ step: Int) -> Int { Int(e.ons.first { $0.cable == 1 && Int((Double($0.sample) / 6000).rounded()) == step }!.note) }
        XCTAssertEqual(noteAt(0), 60, "a hit step — hit octave (0) untouched")
        XCTAssertEqual(noteAt(1), 84, "a miss step — miss octave (+2) shifts independently: 60 + 12×2 = 84")
    }
    func testEuclidMissIgnoresRiffAndArpPicks() {
        func missNoteCount(_ sel: EuclidNoteSel) -> Int {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, missNoteSel: sel)]
            let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 && ![0, 3, 6].contains(Int((Double($0.sample) / 6000).rounded())) }.count
        }
        XCTAssertEqual(missNoteCount(.riff), 0, "RIFF is never offered for miss — a stored .riff miss pick stays silent, not a fallback to ALL")
        XCTAssertEqual(missNoteCount(.arp), 0, "same guard for .arp")
    }
    // INVESTIGATED (Paul 2026-10-03: "investigate ... stuck or held notes, particularly when two lanes are set
    // to the same note"). Traced with an RTCDEBUG trace, not guessed: two lines sharing a row go through
    // `iterateTicks`' per-ROW `lastTick` dedup SEPARATELY, one after the other, within the same render call —
    // its own standing comment already names this ("a known limitation for 2+ real lines sharing a row across
    // a window boundary"). Confirmed what that actually does: when one line's tick advances `lastTick[row]`
    // past a tick the OTHER line hadn't reached yet in an earlier window, that other line's catch-up fire reads
    // `sampleOf` in a LATER window's frame, landing its onset ~1 render-window late — a real, audible timing
    // smear on dense (every-tick) overlap, but NEVER an unterminated voice: `strikeChord`'s on/off pair is
    // always computed together from the same (possibly late) `tau`, so the mistimed strike still gets a valid,
    // finite gate. `assertNothingLeftSounding` held clean on every configuration tried (same note, same density,
    // `forceColumn: 0` stress run to 97 events) — no stuck note was found. The late-onset smear itself is left
    // alone here: a correct fix needs `lastTick` keyed per-LINE rather than per-ROW, which is shared `iterateTicks`
    // infrastructure ARP/RIFF/RATCHET-ALL also depend on — a bigger, separate change than this investigation
    // asked for, flagged in CLAUDE.md rather than attempted blind.
    func testEuclidTwoLinesSameNoteNeverStickRegardlessOfOverlap() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [
            EuclidLine(target: 1, pulses: 8, steps: 8),   // dense: every tick — the worst-case "always overlapping" shape
            EuclidLine(target: 1, pulses: 8, steps: 8),   // SAME note, SAME density, SAME machine-wide rate
        ]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 8, into: e, forceColumn: 0)   // forceColumn: sustain the overlap well past one column, the stress case that found the timing smear
        assertNothingLeftSounding(e)   // the actual claim under test: nothing is left stuck, whatever the exact onset timing
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "sanity: the lines are actually sounding, not accidentally silent")
    }
    func testEuclidRiffAllRestPredecessorIsSilentNotACrash() {
        func onCount(poly: Bool) -> Int {
            var riff = ProcessorSlot(type: .riff)
            riff.params.riffSteps = 8
            if poly { riff.params.riffPoly = true; riff.params.riffMask = Array(repeating: 0, count: 8) }
            else { riff.params.riffRanks = Array(repeating: 0, count: 8) }
            var euclid = ProcessorSlot(type: .euclid)
            euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .riff)]
            let cs = arpMachines()
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riff, euclid]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertEqual(onCount(poly: false), 0, "an all-rest MONO RIFF predecessor (riffRanks all 0) must emit nothing, not crash/hang")
        XCTAssertEqual(onCount(poly: true), 0, "a POLY RIFF predecessor with an empty mask must emit nothing, not crash/hang")
    }
    func testEuclidRiffBypassedPredecessorIsSilent() {
        // Directly modeled on testChainBypassedHeadArpsSourceOnly: a bypassed slot is "not really there" — the
        // SAME convention chainDriverIndex/composeChainSet already apply everywhere else in this file.
        var riff = ProcessorSlot(type: .riff)
        riff.params.riffSteps = 8
        riff.params.riffRanks = [1, 2, 3, 1, 2, 3, 1, 2]
        riff.bypassed = true
        var euclid = ProcessorSlot(type: .euclid)
        euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .riff)]
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riff, euclid]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e); assertNothingLeftSounding(e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "a BYPASSED RIFF predecessor is 'not really there' — noteSel .riff finds no matching predecessor and emits nothing, never falls back to a different pick")
    }
    // RANDOM ANCHOR (Paul 2026-08-25 fix): on a FREE index, RANDOM ANCHOR LOW opens each pool cycle (span ticks) on the
    // LOWEST held note, then the rest shuffle — NOT a stream of the low note (the RETRIG per-column reset used to pedal it).
    func testRandomAnchorOpensEachPoolCycleThenShuffles() {
        let pool = NotePool(); for n: UInt8 in [60, 64, 67, 71] { pool.noteOn(n, velocity: 100, channel: 0) }; pool.rebuildSorted()   // C E G B, C lowest
        let randomIdx = UInt8(ArpPattern.allCases.firstIndex(of: .random)!)
        var lowAtCycleStart = 0, cycles = 0, nonLowElsewhere = 0
        for tick in Int64(0)..<32 {   // the FREE tick the Router now passes for RANDOM
            let note = arpPick(phaseIndex: tick, octaves: 1, pattern: randomIdx, pool: pool, filter: 0, randomAnchor: 1).note   // 1 = LOW
            if tick % 4 == 0 { cycles += 1; if note == 60 { lowAtCycleStart += 1 } }
            else if note != 60 { nonLowElsewhere += 1 }
        }
        XCTAssertEqual(lowAtCycleStart, cycles, "every pool-cycle start (tick % span == 0) opens on the LOW anchor (60)")
        XCTAssertGreaterThan(nonLowElsewhere, 0, "the non-anchor steps shuffle to OTHER notes — not a stream of low")
    }
    func testRatchetThenClosedGateIsSilent() {
        let cs = arpMachines()
        let rat = ProcessorSlot(type: .ratchet)
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 0.0   // deterministic closed gate (PASSGATE removed 2026-09-28)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [rat, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.isEmpty, "a closed gate after the ratchet gates every re-strike")
        assertNothingLeftSounding(e)
    }
    // …and STRUM as a non-tail driver: a closed gate after the strum silences every strummed note.
    func testStrumThenClosedGateIsSilent() {
        let cs = arpMachines()
        let strum = ProcessorSlot(type: .strum)
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 0.0   // deterministic closed gate (PASSGATE removed 2026-09-28)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [strum, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.isEmpty, "a closed gate after the strum gates every strummed note")
        assertNothingLeftSounding(e)
    }
    // §cell-edit F CHOP render path: a cell whose every slice is MUTED emits nothing (the render reads muteMask).
    func testChopMuteMaskSilencesEveryNote() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = {
            var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]
            c.chop = Chop(mainMask: 0xFF, altMask: 0, muteMask: 0xFF, altDest: [])   // every slice muted (overrides main)
            return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.isEmpty, "chop muteMask over every slice → the whole column is silent")
        assertNothingLeftSounding(e)
    }
    // A MUTED slice silences the note AND its echoes — the tail resolves to mask 0, so no repeats are scheduled.
    func testChopMuteSilencesTheEchoesToo() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = {
            var c = Cell(machineID: "gold", buses: [.a])
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var e = ProcessorSlot(type: .echo); e.params.echoDelayDiv = 2; e.params.echoRepeats = 4; e.params.echoThru = true
            c.processors = [arp, e]
            c.chop = Chop(mainMask: 0xFF, altMask: 0, muteMask: 0xFF, altDest: [])   // every slice muted
            return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 8, into: e)
        XCTAssertTrue(e.ons.isEmpty, "a muted slice silences the note and its echoes — no tail escapes the split")
        assertNothingLeftSounding(e)
    }

    /// Run `b` for a few windows on a DIRECT router (so the caller can inspect drainCellStrikes /
    /// snapshotCellSounding afterwards — the shared `run` helper's router is not exposed), holding `pool`.
    private func runDirect(_ b: SnapshotBox, _ pool: NotePool, windows: Int = 4) -> Router {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<windows {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        return router
    }

    // SEAL comet — a MUTED (occupied) cell records NEITHER a strike NOR a sounding bit (tap-to-mute = dark comet).
    // Distinct from an EMPTY cell: this one has a machine + buses, but `cell.muted` short-circuits the emit loop
    // BEFORE currentCellIndex is set. (The same cell unmuted DOES fire — testCellStrikeFeedRecordsFiringCell.)
    func testMutedCellRecordsNoStrikeOrSoundingBit() {
        let b = box(machines: arpMachines()) {
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = []; c.muted = true; return c }()
        }
        let router = runDirect(b, chord([60, 64, 67]))
        XCTAssertEqual(router.drainCellStrikes()[0], 0, "a muted cell records no strike")
        router.snapshotCellSounding()
        XCTAssertEqual(router.cellSoundingVelSnapshot().filter { $0 > 0 }.count, 0, "a muted cell lights no comet")
    }

    // CELL MACHINE stage-2: a CLOSED gate mid-chain empties the set — the tail falls silent.
    func testChainClosedGateSilencesTail() {
        let cs = arpMachines()
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 0.0   // deterministic closed gate (PASSGATE removed 2026-09-28)
        let arp = ProcessorSlot(type: .arp)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [gate, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "a closed gate head → the arp tail is silent")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2: a CLOSED gate as the hold TAIL yields nothing.
    func testChainHoldTailClosedGateSilent() {
        let cs = arpMachines()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 0.0   // deterministic closed gate (PASSGATE removed 2026-09-28)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [harm, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "a closed gate TAIL → the chain is silent")
        assertNothingLeftSounding(e)
    }

    // MARK: - COLUMN-SUBSET LAP (§5b) — the held set warps which column is effective

    // MARK: - graph routing (delta §1) — reference derivation, reroute, cycles

    // (testFedArpArpeggiatesTheParentsSoundingNote + testMutedParentReroutesChildToSource removed 2026-08-27:
    //  GRID-CHAINING retired — `inputRow` is render-inert, so the "child mirrors/reroutes-from the parent" behaviour is
    //  dead. Both children read the SOURCE pool regardless of the ref; the muted-parent-is-silent residual is covered by
    //  testMutedReceiverSilencesItsSubscribers / testMutedCellEmitsNothing.)

    // (grid-chaining retired: the reference-cycle test was removed — no cell-to-cell references exist.)

    // MARK: - PREVIEW / cell audition (Phase 2, Increment 1: ARP solo)

    private func boxWithBusEnabled(_ cs: [Machine], _ enabled: [Bool], _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(machines: cs, scenes: [s]); st.busEnabled = enabled
        return SnapshotBuilder.build(from: st)
    }




    // A DISABLED door that isn't armed is a closed, empty room: no live pass-through, silent.
    func testDisabledReceiverNotArmedIsSilent() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(machines: arpMachines(), scenes: [s])
        var r1 = Receiver(name: "1"); r1.inputEnabled = false
        st.receivers = [r1, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        let live = NotePool(); live.noteOn(60, velocity: 100, channel: 0, cable: 1); live.rebuildSorted()
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        run(b, live, beats: 8, into: e)
        XCTAssertEqual(e.ons.count, 0, "a disabled door with no latch hears nothing — no live pass-through")
    }

    // Builder: a disabled door meters dark & seals its latch (match-nothing filter) and flags the Router mask,
    // while its CELL keeps the real channel so an armed latch's frozen chord can still read.
    func testDisabledReceiverSealsMeteringButCellKeepsChannel() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(machines: arpMachines(), scenes: [s])
        var r1 = Receiver(name: "1"); r1.channel = 3; r1.inputEnabled = false
        st.receivers = [r1, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.receiverChannels[0], Snap.mutedSourceFilter, "disabled → match-nothing meter/capture filter (latch sealed)")
        XCTAssertEqual(b.receiverDisabledMask & 0b0001, 0b0001, "disabled bit set for the Router's live-read block")
        XCTAssertEqual(b.cells[0].inputChannel, 3, "the cell keeps its REAL channel so an armed frozen chord still reads")
        XCTAssertEqual(b.receiverChannels[1], 0, "an enabled OMNI neighbour keeps its channel filter")
        XCTAssertEqual(b.receiverDisabledMask & 0b0010, 0, "the enabled neighbour is not flagged disabled")
    }

    // RANGE resolves onto the cell (grid feed) AND the box (latch capture, upstream of latch).
    func testReceiverRangeResolvesOntoCellAndBox() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(machines: arpMachines(), scenes: [s])
        var r1 = Receiver(name: "1"); r1.rangeLo = 36; r1.rangeHi = 96
        st.receivers = [r1, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.cells[0].inputRangeLo, 36); XCTAssertEqual(b.cells[0].inputRangeHi, 96)
        XCTAssertEqual(b.receiverRangeLo[0], 36, "the box carries the window for the latch capture")
        XCTAssertEqual(b.receiverRangeHi[0], 96)
        XCTAssertEqual(b.receiverRangeLo[1], 0); XCTAssertEqual(b.receiverRangeHi[1], 127, "a default door is full-range")
    }

    // RANGE is UPSTREAM of the latch: captureFiltered admits only in-window notes into the frozen pool.
    func testLatchCaptureExcludesOutOfRangeNotes() {
        let live = NotePool()
        for n: UInt8 in [48, 60, 72, 84] { live.noteOn(n, velocity: 100, channel: 0, cable: 1) }
        live.rebuildSorted()
        let frozen = NotePool()
        frozen.captureFiltered(from: live, filter: 0, cableMask: 0b1111, noteLo: 60, noteHi: 72)   // window C4…C5
        XCTAssertEqual(frozen.srcCount(filter: 0), 2, "only the two in-window notes latch")
        let latched = Set((0..<frozen.srcCount(filter: 0)).map { frozen.srcAscending($0, filter: 0) })
        XCTAssertEqual(latched, [60, 72], "48 and 84 were excluded upstream — never entered the frozen pool")
    }

    // NO-MACHINE LIVE WIRE — a passthrough (empty-chain) cell on door 0 injects its input straight to its emitters in
    // realtime via the reconcileBypass monitor. (The door-level BYPASS toggle that once shared this mechanism was
    // retired 2026-08-25 — Paul; these tests now exercise the surviving wire path: range, solo, master-mute, release, stop.)
    private func wireBox(dest: Int, rangeLo: Int? = nil, rangeHi: Int? = nil, masterMute: Bool = false) -> SnapshotBox {
        var s = SceneState.empty()
        let buses = Set(Bus.allCases.enumerated().filter { dest & (1 << $0.offset) != 0 }.map { $0.element })
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: buses); c.inputReceiver = 0; c.processors = []; return c }()   // EMPTY chain → the live wire
        var st = PluginState(machines: arpMachines(), scenes: [s]); st.busChannels = [1, 2, 3, 4]; st.masterMute = masterMute
        var r1 = Receiver(name: "1"); r1.rangeLo = rangeLo; r1.rangeHi = rangeHi
        st.receivers = [r1, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        return SnapshotBuilder.build(from: st)
    }
    private func stepWindow(_ router: Router, _ box: SnapshotBox, _ pool: NotePool, playing: Bool,
                            beat: Double, out: RecordingEmitter) {
        var diag = KernelDiag()
        router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: 120, sampleRate: 48_000,
                       timestampSample: beat * 24_000, frameCount: 512, out: out, diag: &diag)
    }

    // CR-4[review]: MASTER MUTE is a global emission kill (the emitOneBus grid path already honours it) — the wire
    // monitor is a parallel emission path, so it must fall silent under master mute too, else the whole-instrument mute
    // leaks a live wire.
    func testMasterMuteSilencesTheWireMonitor() {
        let b = wireBox(dest: 0b0001, masterMute: true)
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60]), playing: true, beat: 0, out: e)
        XCTAssertTrue(e.ons.isEmpty, "master mute silences the wire monitor, not just the grid")
    }



    // LADDER commit signal: absoluteStep advances EACH step even during a column LAP (where effColumn is pinned to
    // the held column). This is what lets an armed rung commit while looping one column — the old effColumn-change
    // trigger never fired there, so the arm just blinked forever.
    func testAbsoluteStepAdvancesDuringAColumnLap() {
        let b = box(machines: arpMachines()) { _ in }
        let sr = 48_000.0, tempo = 120.0; let frames: UInt32 = 4096
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        func sweep(laneMask: UInt16) -> (cols: Set<Int>, steps: Set<Int>) {
            let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
            var beat = 0.0, ts = 0.0; var cols = Set<Int>(), steps = Set<Int>()
            for _ in 0..<80 {
                router.process(box: b, pool: NotePool(), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, laneMask: laneMask, out: e, diag: &diag)
                cols.insert(diag.effColumn); steps.insert(diag.absoluteStep)
                beat += windowBeats; ts += Double(frames)
            }
            return (cols, steps)
        }
        let free = sweep(laneMask: 0)
        XCTAssertGreaterThan(free.cols.count, 1, "no lap → effColumn sweeps the columns")
        XCTAssertGreaterThan(free.steps.count, 4, "and absoluteStep advances each step")
        let lap = sweep(laneMask: 0b0000_1000)   // hold column 3
        XCTAssertEqual(lap.cols, [3], "a lap pins effColumn to the held column")
        XCTAssertGreaterThan(lap.steps.count, 4, "but absoluteStep STILL advances each step during the lap — the commit signal")
    }

    // ROW-FEED (1b): input = ⇐ROW 0. The virtual cell reads row 0's sounding note by derivation, so it
    // emits on its own bus (B) while row 0's real cell is soloed out.
    // (testPreviewRowFeedReadsParentRow + testPreviewRowFeedEmptyParentFallsBackToSource removed 2026-08-27: the preview
    //  `inputRow` is never read (grid-chaining retired → always source-fed), so the first duplicates
    //  testPreviewSolosOnlyTheVirtualCell and the second's "empty-parent fallback" is the only path — both vacuous.)






    // PLAYING preview, RATCHET with ROW-FEED: the virtual ratchet cell reads row 0's sounding note (an arp cell),
    // repeating it on bus B while row 0's own cell is soloed out.
    // (testPreviewRatchetRowFeedReadsParentRow removed 2026-08-27: preview `inputRow` is inert (grid-chaining retired), so
    //  it duplicates testPreviewRatchetSoundsAndReleasesClean — a source-fed ratchet preview.)



    // COG SIMPLIFICATION (2026-08-03): cables are RETIRED — the render ALWAYS hears every cable (union), even if a
    // saved receiver still carries a restricted `cable` field (kept for decode-compat but ignored by the builder).
    func testInputCablesAlwaysAcceptAllAfterRetirement() {
        var s = SceneState.empty()
        var cell = Cell(machineID: "gold", buses: [.a]); cell.inputReceiver = 1
        s.cells[0][0] = cell
        var st = PluginState(machines: arpMachines(), scenes: [s])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2", cable: 0b0101), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.cells[0 * Snap.rows + 0].inputCableMask, 0b1111, "a subscriber cell hears ALL cables (cables retired)")
        XCTAssertEqual(b.receiverCables, [0b1111, 0b1111, 0b1111, 0b1111], "every receiver hears all cables — a saved cable filter is ignored")
    }

    // §item 11 mute ruling: a MUTED receiver resolves to the match-nothing filter on the box — this is what
    // makes its input meter go dark and (for R1) blocks passthrough. An unmuted OMNI receiver stays OMNI.
    func testMutedReceiverResolvesToMatchNothingFilter() {
        var st = PluginState(machines: arpMachines(), scenes: [SceneState.empty()])
        var r0 = Receiver(name: "1"); r0.muted = true
        st.receivers = [r0, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.receiverChannels[0], Snap.mutedSourceFilter, "a muted receiver resolves to match-nothing")
        XCTAssertEqual(b.receiverChannels[1], 0, "an unmuted OMNI receiver stays OMNI (0)")
        XCTAssertFalse(receiverHears(filter: b.receiverChannels[0], channel: 0), "match-nothing → hears no channel")
    }

    // §9 item 1 ON ARRIVE (integration): ALT-ALTERNATE on a swap pair (A = open gate → sounds,
    // B = closed gate → silent) flips the cell's sounding every pass. Proves the derivation is wired
    // into the render (pass 0 = base A, pass 1 = flipped B).
    // (testArriveAltAlternateFlipsSoundingAcrossPasses removed 2026-08-27: A/B MORPH dropped → ON.arrive=.altAlternate no
    //  longer flips the sounding face, so both passes only assert `ons > 0` (the head always sounds) — vacuous.)

    // (testTapAltMaskFlipsCellEphemerally removed 2026-08-27: A/B MORPH dropped → the tap-ALT flip no longer swaps the
    //  processor face, so both assertions are `ons > 0` (the head always sounds) — vacuous.
    //  testTapMuteSilencesCell removed 2026-09-27: the whole ON-TAP overlay cluster (tapAltMask/tapMuteMask/
    //  soloCellMask + applyTapOverlay/tapOverlayMasks) had zero live producers — confirmed dead, removed.)


    // MARK: - receiver SOLO (receiver strip) — audible = ¬muted ∧ (soloSet = ∅ ∨ member)

    /// A box whose cells subscribe to four OMNI receivers (so all hear the chord; solo differs by receiver).
    private func receiverBox(mute: [Bool] = [false, false, false, false],
                             _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(machines: arpMachines(), scenes: [s])
        st.receivers = (0..<4).map { var r = Receiver(name: "\($0 + 1)"); r.muted = mute[$0]; return r }
        return SnapshotBuilder.build(from: st)
    }


    // (grid-chaining retired: the solo-silences-chained-feed test was removed — no cross-cell feeds.)

    // MARK: - receiver OCT nudge (receiver strip) — ephemeral ±octave, composes with machine transpose

    private func packOct(_ recv: Int, _ oct: Int) -> UInt32 { UInt32(UInt8(bitPattern: Int8(oct))) << (UInt32(recv) * 8) }

    // (grid-chaining retired: the octave-inherited-through-chain test was removed — no cross-cell feeds.)

    // MARK: - receiver INPUT-velocity override (the slider) — momentary absolute, keyed on the receiver


    // MARK: - receiver LATCH (chord-hold) — a frozen pool substitutes for the live one

    func testCaptureFilteredFreezesMatchingNotes() {
        let live = NotePool()
        live.noteOn(60, velocity: 100, channel: 0, cable: 1)
        live.noteOn(64, velocity: 90, channel: 2, cable: 1)      // arrives on wire channel 2
        live.rebuildSorted()
        let all = NotePool(); all.captureFiltered(from: live, filter: 0, cableMask: 0b1111)   // OMNI/ANY
        XCTAssertEqual(all.srcCount(filter: 0), 2, "OMNI captures the whole chord")
        let ch2 = NotePool(); ch2.captureFiltered(from: live, filter: 3, cableMask: 0b1111)   // filter 3 = wire ch 2
        XCTAssertEqual(ch2.srcCount(filter: 0), 1, "a channel filter captures only its notes")
        XCTAssertEqual(ch2.srcAscending(0, filter: 0), 64, "…the ch-2 note, velocity/channel preserved")
    }



    // MARK: - emitter OUTPUT OCT nudge (emitter strip) — shifts the outgoing note, keyed on the bus

    private func packEmitOct(_ bus: Int, _ oct: Int) -> UInt32 { UInt32(UInt8(bitPattern: Int8(oct))) << (UInt32(bus) * 8) }

    // MARK: - emitter FLATTEN (role family) — activity ducking, admission-time velocity scale

    private func flattenBox(_ flattenMask: UInt8, _ amount: [Int]) -> SnapshotBox {
        var cs = arpMachines()
        let gi = machineIDs.firstIndex(of: "gold")!
        cs[gi].type = .empty   // A holds the chord (sounds)
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // → Emit A (cable 1): the sounding held chord
        s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // → Emit B (cable 2): an arp of NEW note-ons
        var st = PluginState(machines: cs, scenes: [s])
        st.flattenMask = flattenMask; st.flattenAmount = amount
        return SnapshotBuilder.build(from: st)
    }
    private func velsForCable(_ box: SnapshotBox, cable: UInt8) -> Set<UInt8> {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 8.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        return Set(e.ons.filter { $0.cable == cable }.map { $0.vel })
    }

    // MARK: - emitter ALT (role family) — turn-taking among the ALT group

    private func altBox(_ altMask: UInt8, _ count: [Int]) -> SnapshotBox {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])   // one arp fanning to BOTH A and B
        var st = PluginState(machines: arpMachines(), scenes: [s])
        st.altMask = altMask; st.altCount = count
        return SnapshotBuilder.build(from: st)
    }
    private func altCableCounts(_ box: SnapshotBox) -> (Int, Int) {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 8.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        return (e.ons.filter { $0.cable == 1 }.count, e.ons.filter { $0.cable == 2 }.count)
    }

    // MARK: - MASTER panel — KEY (per-scene transpose) · MUTE · the master velocity fader · PANIC

    private func masterBox(key: Int = 0, mute: Bool = false) -> SnapshotBox {
        var s = SceneState.empty(); s.masterKey = key
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // an arp on Emit A
        var st = PluginState(machines: arpMachines(), scenes: [s]); st.masterMute = mute
        return SnapshotBuilder.build(from: st)
    }


    func testMasterPanicFlushesLeavingNothingStuck() {
        let b = masterBox()
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func win(_ panic: Bool) {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, panic: panic, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        for _ in 0..<20 { win(false) }
        win(true)                                    // PANIC mid-play
        for _ in 0..<4 { win(false) }
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        XCTAssertGreaterThan(diag.panics, 0, "PANIC is logged by the hang kit")
    }

    // MARK: - MULTI-SCENE S2b — RESTART-the-pass re-anchors the clock to column 0


    // MARK: - §4b THE FADER-KILL: a velocity fader at the bottom = full silence (suppress + close), momentary

    // MARK: - §2 CONTINUITY (the design's verification ask) — drone flow vs re-strike at the column boundary

    /// A drone of identical adjacent identity-hold cells. Two boundaries crossed → count note-offs on the wire.
    private func droneOffs(phase: ArpPhase, windows: Int = 48) -> (offs: Int, ons: Int, e: RecordingEmitter) {
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!] = { var c = Machine(machineID: "gold", type: .empty); c.paramsA.phase = phase; return c }()
        let b = box(machines: cs) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) } }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        for _ in 0..<windows {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        return (e.offs.count, e.ons.count, e)
    }

    /// §2 CONTINUITY × THE RACK FENCE: a legato drone into a FENCE-CLAMP emitter. The note is clamped into the
    /// window, but it's the SAME clamped pitch in every column, so adoption must keep ONE voice — the drone flows.
    /// The adoption pitch prediction has to apply FENCE too, or it predicts the un-fenced pitch, fails to match the
    /// (fenced) sounding voice, and re-strikes every boundary (machine-guns). Regression lock for that.
    private func fencedDroneOffs(policy: Int, lo: Int, hi: Int) -> (offs: Int, ons: Int) {
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!] = { var c = Machine(machineID: "gold", type: .empty)
            c.paramsA.phase = .legato; return c }()
        var st = PluginState(machines: cs, scenes: [{ var s = SceneState.empty()
            for c in 0..<8 { s.cells[c][0] = Cell(machineID: "gold", buses: [.a]) }; return s }()])
        st.busChannels = [1, 2, 3, 4]
        st.fenceMask = 0b0001; st.fencePolicy = [policy, 0, 0, 0]; st.fenceLo = [lo, 0, 0, 0]; st.fenceHi = [hi, 127, 127, 127]
        let b = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        for _ in 0..<48 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        return (e.offs.count, e.ons.count)
    }

    // A LEGATO drone occupying only SOME columns — the cell sits in column 0 only.
    private func partialDrone() -> (router: Router, box: SnapshotBox, pool: NotePool, e: RecordingEmitter,
                                    tempo: Double, sr: Double, frames: UInt32, wb: Double) {
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!] = { var c = Machine(machineID: "gold", type: .empty); c.paramsA.phase = .legato; return c }()
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // ONLY column 0
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        return (Router(), b, chord([60, 64, 67]), RecordingEmitter(), tempo, sr, frames, Double(frames) * tempo / 60.0 / sr)
    }

    // (grid-chaining retired: the PASS→ARP cell-to-cell routing tests were removed — chains live in cells now.)

    // MARK: - ALT edge: advance-until-present (no starvation of a partial fan-out)

    func testTurnsDoesNotAlterNoteTiming() {
        // TURNS only redirects WHICH emitter plays — it must never shift a note's onset. With two hold cells
        // (→A, →B) and TURNS {A,B} COUNT 1, the multiset of note-on SAMPLE TIMES is identical to no-TURNS.
        func onsetTimes(_ altMask: UInt8) -> [Int64] {
            var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])
            s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])
            var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
            st.altMask = altMask; st.altCount = [1, 1, 1, 1]
            let e = RecordingEmitter()
            run(SnapshotBuilder.build(from: st), chord([60]), beats: 32, into: e)
            assertNothingLeftSounding(e)
            return e.ons.map { $0.sample }.sorted()
        }
        XCTAssertEqual(onsetTimes(0b0011), onsetTimes(0), "TURNS (count 1) must not change note timing — only the emitter")
    }

    // MARK: - THE RACK — CURVE (per-emitter velocity re-map)

    private func curveBox(amount: Int, on: Bool = true, rack: UInt8? = nil) -> SnapshotBox {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // identity hold → A (one note-on at the source velocity)
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
        st.curveMask = on ? 0b0001 : 0
        st.curveAmount = [amount, 0, 0, 0]
        st.rackEnabledMask = rack
        return SnapshotBuilder.build(from: st)
    }

    // MARK: - THE RACK — FENCE (per-emitter note-range policy)

    /// The set of output notes on A when an identity hold holds note 60 → A under a FENCE window/policy.
    private func fenceOut(policy: Int, lo: Int, hi: Int, on: Bool = true, rack: UInt8? = nil) -> Set<UInt8> {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // identity hold → A, note 60
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
        st.fenceMask = on ? 0b0001 : 0
        st.fencePolicy = [policy, 0, 0, 0]; st.fenceLo = [lo, 0, 0, 0]; st.fenceHi = [hi, 127, 127, 127]
        st.rackEnabledMask = rack
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 16, into: e)
        assertNothingLeftSounding(e)
        return Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
    }

    // MARK: - THE RACK — MONO (per-emitter monophony)

    /// The notes left SOUNDING on A (last event = note-on) after ONE window holding a chord under MONO/priority.
    private func monoSounding(priority: Int, _ notes: [UInt8] = [60, 64]) -> [UInt8] {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // identity hold → A holds the whole chord
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
        st.monoMask = 0b0001; st.monoPriority = [priority, 0, 0, 0]
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        router.process(box: SnapshotBuilder.build(from: st), pool: chord(notes), playing: true, beatPos: 0,
                       tempo: 120, sampleRate: 48_000, timestampSample: 0, frameCount: 2048, out: e, diag: &diag)
        var last: [UInt8: UInt8] = [:]
        for ev in e.events where ev.cable == 1 { last[ev.note] = ev.status }
        return last.filter { $0.value == 0x90 }.keys.sorted()
    }

    func testMonoLeavesNoStuckNotes() {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s]); st.monoMask = 0b0001
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 16, into: e)
        assertNothingLeftSounding(e)
    }

    // MARK: - THE RACK — POCKET (per-emitter timing feel)

    // MARK: - WIRE ARTICULATION — same-note overlap on one emitter (design ASK 2026-08-05)

    /// AUDIT B2: releasing the chord under a SINGLE-COLUMN lap must close the legato drone immediately — not strand
    /// it (immortal, offSample .max) until the ~1s Kernel self-heal. A k=1 lap pins effColumn, so the column-change
    /// reconcile never fires; the fix runs the reconcile when the lap's pool empties. Transport stays PLAYING (no
    /// stop-flush) so the test isolates the release, not the stop.
    func testSingleColumnLapReleaseClosesDrone() {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])       // a LEGATO drone → A (immortal hold, offSample .max)
        var gold = holdMachine("gold"); gold.paramsA.phase = .legato
        let cs = machineIDs.map { $0 == "gold" ? gold : Machine(machineID: $0, type: .arp) }
        let box = SnapshotBuilder.build(from: PluginState(machines: cs, scenes: [s]))
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        let held = chord([60])
        for _ in 0..<4 {                                          // hold the chord under a k=1 lap on column 0
            router.process(box: box, pool: held, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, laneMask: 0b1, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        let empty = NotePool()
        for _ in 0..<4 {                                          // RELEASE (empty pool), lap still on, still PLAYING
            router.process(box: box, pool: empty, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, laneMask: 0b1, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        assertNothingLeftSounding(e)                             // the drone closed from the release, not a stop/self-heal
        XCTAssertTrue(router.quiescent, "no voice/refcount left after a k=1-lap key release")
    }

    // MARK: - THE RACK — CONVERSATION (LEAD / STANCE)

    /// (A-count, B-count) when A is the lead (present unless `leadPresent` false) and B follows with the given stance.
    private func convOut(stance: [Int], leadPresent: Bool = true) -> (Int, Int) {
        var s = SceneState.empty()
        if leadPresent { s.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // lead sustains on A
        s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])                       // follower on B
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
        st.convLead = 0; st.convStance = stance
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 16, into: e)
        assertNothingLeftSounding(e)
        return (e.ons.filter { $0.cable == 1 }.count, e.ons.filter { $0.cable == 2 }.count)
    }

    // MARK: - the render-side parameter route (invariant 6)

    /// An UNMAPPED param address (no slot) is a silent no-op — it never traps, never writes an override.
    func testUnmappedParamEventIsANoOp() {
        let router = Router(); var diag = KernelDiag()
        router.applyParamEvent(9_999, 42, atSample: 0, rampDurationSampleFrames: 0, diag: &diag)
        XCTAssertEqual(diag.paramEventCount, 0, "an unmapped address applies nothing")
    }

    // MARK: - the PLAYING CHANCE chord-hold path (distinct from audition/preview)

    // MARK: - scene FLUSH closes the outgoing scene's voices

    // MARK: - bypass: multiple destinations

    // MARK: - ECHO (the tail era) — AcceptanceCriteria-tail-era-delay-echo, Phase 0+1

    private func echoMachines(div: Int = 1, repeats: Int = 4, feedDelay: Double = 0.5, decay: Double = 0.5,
                             thru: Bool = true, pitch: Int = 0, offset: Double = 0) -> [Machine] {
        machineIDs.map { var c = Machine(machineID: $0, type: .echo)
            c.paramsA.echoSync = true; c.paramsA.echoDelayDiv = div; c.paramsA.echoRepeats = repeats
            c.paramsA.echoFeedDelay = feedDelay; c.paramsA.echoDecay = decay
            c.paramsA.echoThru = thru; c.paramsA.echoPitch = pitch; c.paramsA.echoOffset = offset; return c }
    }

    // ECHO IN-KEY (Paul 2026-09-29): PITCH STEP can walk to the next in-key note, live, from whichever ABCD
    // receivers are selected — replaces the old POOL-STEP mode (removed). Mirrors
    // testAvoidDoorReferenceReadsAnotherLiveReceiverAndItsClashes' shape: door 0 (ch1) feeds the ECHO cell
    // itself, door 1 (ch2) is the live IN-KEY reference (bit 1 = receiver B). SCOPE, confirmed by tracing
    // emitEchoColumn/isEchoTail: IN-KEY mode only reaches registerEcho (single-slot [ECHO], or an upstream-
    // then-ECHO tail like [HARMONIZE→ECHO]) — the SAME scope the old POOL mode had (neither ever threaded
    // through pushEchoForNote's hold-chain path, e.g. [ECHO→HARMONIZE], or registerLengthChainEcho's
    // [ECHO→…→LENGTH] path). CHAIN route is architecturally inapplicable here too: registerEcho never passes
    // a route to pushEchoTail (always the .direct default), since when ECHO is the chain's own tail there is
    // nothing downstream to re-fold repeats through.
    private func echoInKeyBox(receivers: UInt8, pitch: Int, repeats: Int, div: Int, upstream: [ProcessorSlot] = []) -> SnapshotBox {
        var s = ProcessorSlot(type: .echo)
        s.params.echoSync = true; s.params.echoDelayDiv = div; s.params.echoRepeats = repeats
        s.params.echoFeedDelay = 1.0; s.params.echoDecay = 0.95   // slow decay so late repeats still clear the velocity floor
        s.params.echoThru = true; s.params.echoPitchMode = .inKey; s.params.echoPitch = pitch
        s.params.echoInKeyReceivers = receivers
        var st = PluginState(machines: [Machine(machineID: "gold", type: .empty)], scenes: [{ var sc = SceneState.empty()
            sc.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; c.processors = upstream + [s]; return c }()
            return sc }()])
        st.busChannels = [1, 2, 3, 4]
        st.receivers = [Receiver(name: "1", channel: 1), Receiver(name: "2", channel: 2), Receiver(name: "3"), Receiver(name: "4")]
        return SnapshotBuilder.build(from: st)
    }

    /// The echo schedule is a pure function of musical time → the SAME strike count at any render block size (a
    /// repeat due mid-window lands in exactly the window that contains it, never bunched at the block head).
    func testEchoIsBlockSizeInvariant() {
        let b = box(machines: echoMachines(div: 1, repeats: 4, feedDelay: 0.6, decay: 0.6)) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        func strikeCount(_ frames: UInt32) -> Int {
            let e = RecordingEmitter(); run(b, chord([60]), beats: 1.5, into: e, frames: frames)
            return e.ons.filter { $0.note == 60 && $0.cable == 1 }.count
        }
        XCTAssertEqual(strikeCount(2048), strikeCount(256), "echo is block-size invariant")
    }

    // HOCKET (v1): a wire-listening driver. Two cells in column 0 — a sustained DRONE on emitter A (row 0, the wire),
    // and a HOCKET on emitter B (row 1) reading its pool but timed by LISTENING to wire A in GAPS. When A is held it is
    // (near-)continuously sounding → HOCKET is suppressed; remove A and HOCKET fills the silence with its pool line.
    private func hocketScene(wireOnA: Bool) -> SnapshotBox {
        let cs = machineIDs.map { id -> Machine in
            if id == "gold" { return Machine(machineID: id, type: .drone) }
            if id == "orange" { var c = Machine(machineID: id, type: .hocket)
                c.paramsA.hocketSource = 0; c.paramsA.hocketMode = .gaps; c.paramsA.hocketRate = .r1_8; return c }
            return Machine(machineID: id, type: .arp)
        }
        return box(machines: cs) {
            if wireOnA { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // the DRONE wire on emitter A
            $0.cells[0][1] = Cell(machineID: "orange", buses: [.b])                // HOCKET on emitter B, listening to A
        }
    }
    func testHocketSelfCycleFallsSilent() {
        // THE CYCLE LAW: a HOCKET that OUTPUTS on the wire it LISTENS to is a loop → silent.
        let cs = machineIDs.map { id -> Machine in
            if id == "gold" { var c = Machine(machineID: id, type: .hocket)
                c.paramsA.hocketSource = 0; c.paramsA.hocketMode = .gaps; c.paramsA.hocketRate = .r1_8; return c }
            return Machine(machineID: id, type: .arp)
        }
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // listens to A, emits on A
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 8, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "a self-listening loop falls silent")
        assertNothingLeftSounding(e)
    }

    /// EUCLID MASK — RATCHET within the Euclideous `isEuclideousRow` pipeline specifically (Paul: "ratchet on
    /// Euclid mask... still not working in any perceptible way"). CONFIRMED REAL GAP, not a guess: every
    /// pre-existing `EuclidLineMask`/RATCHET test in this file builds its fixture via `maskFixture`, which
    /// places its cell at a PLAIN row (`$0.cells[0][0]`) — never `Snap.euclideousRow` — so every one of those
    /// tests exercises the OLD/legacy, non-Euclideous `!isEuclideousRow` fork further down in `runEuclidLine`
    /// (unchanged since the 2026-10-12 "ratchet doesn't work" fix), NOT the "lit notes plus the riff" ferry's
    /// own NEW unified per-hit pipeline Euclideous's own lanes actually run through. That fork has its own,
    /// separately-written RATCHET call site (`maskRatchetReps`, called against the merged lit/riff pitch set)
    /// which had ZERO test coverage of its own before this — exactly the same class of blind spot that let
    /// the original bug ship unnoticed (every existing fixture hardcoded `useRiff: true`, missing the sibling
    /// NOTE-mode path entirely). This test locks in that the NEW pipeline's own RATCHET call site genuinely
    /// multiplies note-ons for BOTH ways a lane can sound something — lit notes alone (riff off) and the riff
    /// layer (riff on) — built and run against the REAL production path (`SnapshotBuilder.build(from:)`, not a
    /// raw `box()` helper) exactly as a saved Euclideous document reaches the render engine. The LANE's own
    /// pattern is SPARSE (pulses=1 of 8), so only ONE real hit occurs within the test window — its ratchet
    /// burst is the only thing being measured, with no SECOND real hit to complicate the count (the take-3
    /// echo-ring fix, below, defers repeats 1..<nRep across real FUTURE render windows rather than firing
    /// them all synchronously — a test with a SECOND hit nearby, or too short a trailing window, can
    /// genuinely truncate the burst before it finishes draining, an expected property of that fix confirmed
    /// empirically, not a flaw in the assertion below). Asserting the RATIO, not a hand-derived absolute
    /// count, since the exact hit count this harness's own beat/column arithmetic produces for a given
    /// `beats:`/rate pair is not something to trust blind (this file's own standing lesson, burned more than
    /// once already this session by hand-derived counts that turned out wrong once actually traced).
    // LISTEN (ferry 2026-10-14 §1, "stop the Euclid mask affecting output"): SUPERSEDES
    // `testEuclideousMaskRatchetMultipliesNoteOnsInTheUnifiedPipeline` and
    // `testEuclideousMaskRatchetGateDeterminesRepeatDuration` entirely — both tested RATCHET actually
    // multiplying note-ons/sharing GATE across repeats, which can no longer happen now that the mask never
    // engages on Euclideous's row. Reuses the identical fixtures to prove the ratchet config is now fully
    // inert: a "3-repeat" ratchet produces the SAME note-on count as a "1-repeat" (no multiplication), and
    // a configured ratchet's own GATE behaves exactly like a plain, unratcheted hit (one onset/offset pair
    // per real tick, sized by GATE alone — never split across repeat subdivisions).
    func testEuclideousMaskRatchetConfigIsNowANoOp() {
        func onCount(ratchetReps: Int, riffOn: Bool) -> Int {
            var c = Machine(machineID: "gold", type: .euclid)
            if riffOn { c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1]) }
            var m = EuclidLineMask()
            m.enabled = true; m.pulses = 8; m.steps = 8; m.chance = 1.0
            m.mode = .ratchet; m.ratchetMin = ratchetReps; m.ratchetMax = ratchetReps
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 8, rate: .r1_1, useRiff: false,
                                                 litNotes: riffOn ? 0 : 0b0000_0001, riffOn: riffOn, mask: m,
                                                 sourceMode: .midi, riffLength: riffOn ? 1 : nil)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
            st.euclideousNoteSource = .midi
            let e = RecordingEmitter()
            run(SnapshotBuilder.build(from: st), chord([60]), beats: 10, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 && Int($0.note) == 60 }.count
        }
        for riffOn in [false, true] {
            let baseline = onCount(ratchetReps: 1, riffOn: riffOn)
            let configuredRatchet = onCount(ratchetReps: 3, riffOn: riffOn)
            XCTAssertGreaterThan(baseline, 0, "sanity: the lane strikes at all (riffOn=\(riffOn))")
            XCTAssertEqual(configuredRatchet, baseline, "LISTEN ferry: a 3-repeat ratchet config no longer multiplies note-ons on Euclideous's row — it's the SAME as the unratcheted baseline (riffOn=\(riffOn))")
        }
    }
    func testEuclideousMaskRatchetGateConfigIsNowANoOp() {
        func onceOnly(ratchetReps: Int, gateParam: Double) -> (onset: Int64, off: Int64)? {
            var c = Machine(machineID: "gold", type: .euclid)
            var m = EuclidLineMask()
            m.enabled = true; m.pulses = 8; m.steps = 8; m.chance = 1.0
            m.mode = .ratchet; m.ratchetMin = ratchetReps; m.ratchetMax = ratchetReps
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, gate: gateParam, rate: .r1_1, useRiff: false,
                                                 litNotes: 0b0000_0001, riffOn: false, mask: m, sourceMode: .midi)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
            st.euclideousNoteSource = .midi
            let e = RecordingEmitter()
            // K=N=8 at r1_1 ⇒ a tick every beat. GATE follows the REAL rhythm (the gap to the next hit, not
            // a fixed rate duration) — the window must extend past tick 1 so that gap is resolvable, or a
            // 70%-of-one-beat close (0.7 beats) would still be open at window's end regardless of GATE.
            run(SnapshotBuilder.build(from: st), chord([60]), beats: 2.2, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            guard let on = e.ons.filter({ $0.cable == 1 && Int($0.note) == 60 }).map({ $0.sample }).min(),
                  let off = e.offs.filter({ $0.cable == 1 && Int($0.note) == 60 && $0.sample > on }).map({ $0.sample }).min() else { return nil }
            return (on, off)
        }
        // A "4-repeat ratchet" config now produces exactly ONE onset/offset pair for the tick — never 4 —
        // and GATE sizes that ONE note directly against its own full step length (1 beat @ r1_1), exactly
        // as an unratcheted hit would, confirming the ratchet's own repeat-subdivision math never runs.
        guard let g30 = onceOnly(ratchetReps: 4, gateParam: 0.3), let g70 = onceOnly(ratchetReps: 4, gateParam: 0.7) else {
            return XCTFail("expected exactly one onset/offset pair per tick now that ratchet is inert")
        }
        let dur30 = g30.off - g30.onset, dur70 = g70.off - g70.onset
        XCTAssertNotEqual(dur30, dur70, "GATE still determines the note's own length directly — 30% vs 70% of one full step must differ")
        XCTAssertLessThan(dur30, dur70, "a smaller GATE must still produce a shorter note")
    }

    // MARK: - GATE FOLLOWS THE RHYTHM (Paul 2026-10-13 ferry)

    func testEuclideousGateAt50PercentMeasuresAgainstTheRealNextHit() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 3, ranks: [1, 2, 3])
        c.paramsA.euclidLines = [EuclidLine(pulses: 3, steps: 8, gate: 0.5, rate: .r1_16, useRiff: true, riffOn: true,
                                             mask: EuclidLineMask(), sourceMode: .midi, riffLength: 3)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        // E(3,8): hits at buffer ticks 0,3,6 — real gaps 3,3,2 steps. Ranks 1,2,3 cycle a 3-note chord, so
        // each hit strikes a DISTINCT pitch (Acceptance #1's own literal setup). beats:2.2 captures exactly
        // hits 0,1,2,3 (the wrap) and stops BEFORE hit4 (tick 11, tau 2.75) — a hit that far out would
        // leave hit3's own pitch (60, re-struck by the wrap) un-reconciled at test end, and since this is
        // GATE=0.5 (not legato) that's a harmless, finite-gated voice either way, but keeping the window
        // tight avoids a 3rd, chronologically-later same-pitch onset polluting onsFor(60)'s index[1].
        run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 2.2, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let onsFor: (UInt8) -> [Int64] = { note in e.ons.filter { $0.cable == 1 && $0.note == note }.map { $0.sample }.sorted() }
        let offsFor: (UInt8) -> [Int64] = { note in e.offs.filter { $0.cable == 1 && $0.note == note }.map { $0.sample }.sorted() }
        let on1 = onsFor(60)[0], off1 = offsFor(60)[0]
        let on2 = onsFor(64)[0], off2 = offsFor(64)[0]
        let on3 = onsFor(67)[0], off3 = offsFor(67)[0]
        let on1Next = onsFor(60)[1]   // the cycle wraps: hit3 (tick8) replays rank1 = note 60 again
        XCTAssertEqual(Double(off1 - on1), Double(on2 - on1) * 0.5, accuracy: 2, "1.5 of 3 steps: 50% of the REAL gap to the next hit")
        XCTAssertEqual(Double(off2 - on2), Double(on3 - on2) * 0.5, accuracy: 2, "1.5 of 3 steps")
        XCTAssertEqual(Double(off3 - on3), Double(on1Next - on3) * 0.5, accuracy: 2, "1 of 2 steps: the wrap across the end of the cycle")
    }

    func testEuclideousGateAt100PercentEndsExactly10msAfterTheNextHit() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 3, ranks: [1, 2, 3])
        c.paramsA.euclidLines = [EuclidLine(pulses: 3, steps: 8, gate: 1.0, rate: .r1_16, useRiff: true, riffOn: true,
                                             mask: EuclidLineMask(), sourceMode: .midi, riffLength: 3)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        // beats:1.2 captures exactly hit0 (tick0, pitch60) and hit1 (tick3, pitch64, tau 0.75), stopping well
        // before hit2 (tau 1.5) — at GATE=1.0 a legato voice is IMMORTAL until genuinely reconciled, and
        // anything still open at test end closes via the transport-stop edge's own `renderSampleImmediate`
        // sentinel (a deliberate "right now" marker, not a real sample count) — keeping the window tight
        // means hit0's own close (the thing under test) is ALWAYS the real reconcile-computed one, never
        // shadowed by that sentinel sorting to the front of a later, unrelated close.
        run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 1.2, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let onsFor: (UInt8) -> [Int64] = { note in e.ons.filter { $0.cable == 1 && $0.note == note }.map { $0.sample }.sorted() }
        let offsFor: (UInt8) -> [Int64] = { note in e.offs.filter { $0.cable == 1 && $0.note == note }.map { $0.sample }.sorted() }
        let on1 = onsFor(60)[0], off1 = offsFor(60)[0]
        let on2 = onsFor(64)[0]
        let overlapSamples = 0.010 * 48_000.0
        XCTAssertEqual(Double(off1), Double(on2) + overlapSamples, accuracy: 4, "at 100%, a note ends exactly 10ms after the NEXT hit's own note-on")
    }

    func testEuclideousRepeatedPitchAt100PercentHoldsAsOneNote() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])
        c.paramsA.euclidLines = [EuclidLine(pulses: 2, steps: 8, gate: 1.0, velocityAbsolute: 77, rate: .r1_16, useRiff: true, riffOn: true,
                                             mask: EuclidLineMask(), sourceMode: .midi, riffLength: 1)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        // K=2/N=8: two hits per cycle, both resolving rank1 (riffLength 1) — the SAME pitch on consecutive hits.
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 2, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == 1 && $0.note == 60 }
        XCTAssertEqual(ons.count, 1, "two consecutive hits on the SAME pitch at 100% must produce exactly ONE note-on, not two")
        XCTAssertEqual(Int(ons[0].vel), 77, "the held note keeps its FIRST strike's velocity")
    }

    func testEuclideousRepeatedPitchAt99PercentStrikesTwice() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])
        c.paramsA.euclidLines = [EuclidLine(pulses: 2, steps: 8, gate: 0.99, rate: .r1_16, useRiff: true, riffOn: true,
                                             mask: EuclidLineMask(), sourceMode: .midi, riffLength: 1)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        // beats:1.5 captures exactly K=2/N=8's two real hits (ticks 0,4 → tau 0,1.0) and stops before a 3rd,
        // cycle-2 hit at tau=2.0 would otherwise land right at the window's tail boundary.
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 1.5, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == 1 && $0.note == 60 }
        XCTAssertEqual(ons.count, 2, "at 99% (not literally 100) the two hits must strike independently, never merge")
    }

    func testEuclideousLitNoteSustainsAt100PercentAndRestrikesAt90() {
        func litOnCount(gate: Double) -> Int {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 3, ranks: [1, 2, 3])
            c.paramsA.euclidLines = [EuclidLine(pulses: 3, steps: 8, gate: gate, rate: .r1_16, useRiff: true,
                                                 litNotes: 0b0000_0001, riffOn: true, mask: EuclidLineMask(), sourceMode: .midi, riffLength: 3)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
            st.euclideousNoteSource = .midi
            let e = RecordingEmitter()
            run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 4, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 && $0.note == 60 }.count   // rank 1 = note 60, the lit pick
        }
        XCTAssertEqual(litOnCount(gate: 1.0), 1, "the lit note (rank 1) sustains as ONE note-on across all 3 riff-moving hits at 100%")
        XCTAssertGreaterThan(litOnCount(gate: 0.9), 1, "below 100% the lit note re-strikes on each hit")
    }

    func testEuclideousSilentSkipRestAt100PercentEndsThePreviousHeldNote() {
        var c = Machine(machineID: "gold", type: .euclid)
        // ranks [1, 0] over riffLength 2: hit0 → rank1 (real, held) · hit1 → rank0 = REST, ON REST=SKIP (default).
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 2, ranks: [1, 0])
        c.paramsA.euclidLines = [EuclidLine(pulses: 2, steps: 8, gate: 1.0, rate: .r1_16, useRiff: true, riffOn: true,
                                             mask: EuclidLineMask(), sourceMode: .midi, riffLength: 2)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        // beats:1.5 — see the sibling 99% test's comment: keeps this to exactly K=2/N=8's two real ticks
        // (one real hit at tick0, one SKIP rest at tick4) and stops well before a 3rd, cycle-2 hit (tick8,
        // real again under ranks[1,0]'s own repeat) would land right at the tail boundary.
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 1.5, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == 1 && $0.note == 60 }.map { $0.sample }.sorted()
        let offs = e.offs.filter { $0.cable == 1 && $0.note == 60 }.map { $0.sample }.sorted()
        XCTAssertEqual(ons.count, 1, "only the first hit strikes — the second is a genuine SKIP rest")
        XCTAssertEqual(offs.count, 1)
        let samplesPerBeat = 48_000.0 * 60.0 / 120.0
        let stepSamples = 0.25 * samplesPerBeat   // 1/16 note
        let overlapSamples = 0.010 * 48_000.0
        // K=2/N=8 → hits at ticks 0 and 4: a 4-step gap to the rest, which (ferry §2.4) still ends the
        // held note at THAT hit's time + the overlap — legato never runs through a silence.
        XCTAssertEqual(Double(offs[0] - ons[0]), 4 * stepSamples + overlapSamples, accuracy: 4,
                       "the note must end exactly at the SKIP-rest hit's time + the 10ms overlap, not later")
    }

    func testEuclideousOnRestTieAt60PercentScalesOnlyTheFollowingGap() {
        var c = Machine(machineID: "gold", type: .euclid)
        // ranks [1, 0, 3] over riffLength 3: hit0 → rank1 (real, pool[0]=60) · hit1 → rank0 = REST, ON
        // REST=TIE · hit2 → rank3 (real, pool[2]=67, ends the tie). Rank is 1-indexed into the sorted
        // pool — "rank2" would resolve to pool[1]=64, not 67 (caught via an RTCDEBUG trace after a first
        // draft literally wrote `2` expecting "the third pool note," not "the second").
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 3, ranks: [1, 0, 3])
        c.paramsA.euclidLines = [EuclidLine(pulses: 3, steps: 8, gate: 0.6, rate: .r1_16, useRiff: true, riffOn: true,
                                             mask: EuclidLineMask(), sourceMode: .midi, riffOnRest: .tie, riffLength: 3)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        // beats:1.8 captures exactly hit0 (tick0, real), hit1 (tick3, rest/TIE), hit2 (tick6, real) and
        // stops before a 4th, cycle-2 hit (tick8, tau 2.0 — ranks wraps back to rank1) would land right
        // at the tail boundary, same class of fix as the sibling GATE tests above.
        run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 1.8, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let onsFor: (UInt8) -> [Int64] = { note in e.ons.filter { $0.cable == 1 && $0.note == note }.map { $0.sample }.sorted() }
        let offsFor: (UInt8) -> [Int64] = { note in e.offs.filter { $0.cable == 1 && $0.note == note }.map { $0.sample }.sorted() }
        let note1On = onsFor(60)[0], note1Off = offsFor(60)[0]
        let note2On = onsFor(67)[0]
        let samplesPerBeat = 48_000.0 * 60.0 / 120.0
        let stepSamples = 0.25 * samplesPerBeat
        // E(3,8): hits at ticks 0,3,6 — gap hit0→hit1(tie) = 3 steps (UNSCALED), gap hit1→hit2 = 3 steps
        // (the FOLLOWING gap, scaled by GATE 0.6) — ferry §3.1's own literal formula.
        let expected = 3 * stepSamples + 0.6 * (3 * stepSamples)
        XCTAssertEqual(Double(note1Off - note1On), expected, accuracy: 4,
                       "TIE: length = the full gap up to the tied hit, plus GATE × the gap following it")
        XCTAssertEqual(Double(note2On - note1On), 6 * stepSamples, accuracy: 4, "sanity: hit2 really lands 6 steps after hit0")
    }

    /// Validation-pass finding #3 (7-edge flush): the legato bookkeeping was only cleared on the transport
    /// start/stop edge in the first draft — PANIC (and the other 6 `allNotesOff`-accompanying edges) ALSO
    /// closes every active voice (including an immortal legato one) but would leave stale slot indices
    /// behind without `flushEuclideousLegato()` wired into the same place `flushGlide`/`flushMod` are.
    func testEuclideousLegatoBookkeepingIsFlushedByPanicNotJustTransportStop() {
        var gold = Machine(machineID: "gold", type: .euclid)
        gold.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])
        gold.paramsA.euclidLines = [EuclidLine(pulses: 8, steps: 8, gate: 1.0, rate: .r1_8, useRiff: true, riffOn: true,
                                                mask: EuclidLineMask(), sourceMode: .midi, riffLength: 1)]
        var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? gold : Machine(machineID: $0, type: .arp) }, scenes: [s])
        st.euclideousNoteSource = .midi
        let b = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func win(_ panic: Bool) {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, panic: panic, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        for _ in 0..<4 { win(false) }   // the lane strikes + holds its legato note
        win(true)                       // PANIC — no transport stop
        for _ in 0..<8 { win(false) }   // K=8/N=8: the lane hits every tick — it must keep re-striking, not go dark
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        let onsAfterArm = e.ons.filter { $0.cable == 1 && $0.note == 60 }
        XCTAssertGreaterThan(onsAfterArm.count, 1, "PANIC must flush the legato bookkeeping (not just transport-stop edges) — the lane must keep re-striking its held note after a panic, not silently believe a since-closed voice is still sounding")
    }

    /// Acceptance #8: "Stuck-note stress test: flip GATE 99↔100%, toggle lit notes/rate, transport
    /// stop/restart, and a MONO-steal collision partway through. No notes left hanging." Mirrors the
    /// established `testEuclideousStuckNoteStressRapidLitOctaveRiffToggling` shape, but specifically
    /// exercises the NEW legato machinery's own worst-case interactions: the 99↔100% boundary (where a
    /// hit's own treatment flips between "fixed-length strike" and "immortal, reconciled" every other
    /// tick), a mid-run MONO steal (forcing `forgetEuclideousLegatoSlotAt` to run for real), and a
    /// transport stop/restart (forcing the 7-edge flush to run for real) — all on the SAME router
    /// instance, never reset between phases.
    func testEuclideousGateLegatoStuckNoteStressGateFlipMonoStealAndTransportRestart() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func lineFor(_ tick: Int) -> EuclidLine {
            let gateVal = tick % 2 == 0 ? 1.0 : 0.99
            let lit = UInt8(1 << (tick % 8))
            return EuclidLine(target: 0, pulses: 3, steps: 8, gate: gateVal, rate: .r1_32,
                               useRiff: true, litNotes: lit, riffOn: true, sourceMode: .midi, riffLength: 8)
        }
        func sceneFor(_ line: EuclidLine, monoOnA: Bool) -> (PluginState) {
            var gold = Machine(machineID: "gold", type: .euclid)
            gold.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            gold.paramsA.euclidLines = [line]
            var s = SceneState.empty()
            s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
            if monoOnA { s.cells[0][0] = Cell(machineID: "orange", buses: [.a]) }   // a sibling ARP, same bus — steals under MONO LAST
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? gold : Machine(machineID: $0, type: .arp) }, scenes: [s])
            if monoOnA { st.monoMask = 0b0001; st.monoPriority = [0, 0, 0, 0] }
            st.euclideousNoteSource = .midi
            return st
        }
        let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 1024
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        let router = runKeepingRouter(SnapshotBuilder.build(from: sceneFor(lineFor(0), monoOnA: false)), chord(pool), beats: 0.2, into: e, forceColumn: 0, tempo: tempo, sr: sr, frames: frames)
        var diag = KernelDiag()
        var beat = 0.2, ts = 0.2 / tempo * 60.0 * sr
        for tick in 1...40 {
            // Ticks 15-24: a MONO collision runs alongside the lane, forcing a real voice steal on bus A.
            let monoOnA = (15...24).contains(tick)
            let box1 = SnapshotBuilder.build(from: sceneFor(lineFor(tick), monoOnA: monoOnA))
            // Tick 30: a transport stop/restart mid-run — exercises the 7-edge flush for real.
            if tick == 30 {
                router.process(box: box1, pool: chord(pool), playing: false, beatPos: beat, tempo: tempo,
                               sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += windowBeats; ts += Double(frames)
            }
            router.process(box: box1, pool: chord(pool), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: SnapshotBuilder.build(from: sceneFor(lineFor(40), monoOnA: false)),
                       pool: chord(pool), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // MARK: - RIFF/NOTES SPLIT (Paul's third same-day ferry, "split MELODY into RIFF and NOTES tabs") —
    // per-note octave shifts, the notes layer's own on/off, and its own velocity offset, all independent of
    // the riff layer's `octave`/`velocityAbsolute`.

    /// NOTES TAB ferry (2026-10-19, §6.7): the per-note octave shifts STOP SOUNDING. The field stays decodable and is encoded as decoded, but nothing reads it — a lit note sounds the
    /// plain pool note at the notes layer's octave (MIX's notes OCT stepper still moves it). (Before this ferry a +1 shift on rank 1 sounded a whole octave up: 72, not 60.)
    func testEuclideousPerNoteOctaveShiftNoLongerSounds() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [0])   // riff off anyway, but rank0=rest either way
        c.paramsA.euclidLines = [EuclidLine(pulses: 1, steps: 8, rate: .r1_16, useRiff: false, litNotes: 0b0000_0001, riffOn: false,
                                             mask: EuclidLineMask(), sourceMode: .midi, noteOctShifts: [1, 0, 0, 0, 0, 0, 0, 0])]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 0.3, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(ons.count, 1)
        XCTAssertEqual(ons[0].note, 60, "rank 1's +1 shift is stored but no longer sounds: the plain pool note (60), not 72")
    }

    /// Acceptance #5 (literal): NOTES VEL offsets the lit notes' own velocity, never the riff note's — and a
    /// riff/lit pitch collision sounds ONCE, at the riff's own velocity (the riff layer's `addPitch` always
    /// runs first, so first-insertion-wins dedup gives this for free, not a special case).
    func testEuclideousNotesVelOffsetsLitNotesOnlyAndCollisionSoundsOnceAtRiffVelocity() {
        func onsFor(ranks: [Int], litMask: UInt8, offset: Int) -> [(note: UInt8, vel: UInt8)] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: ranks)
            c.paramsA.euclidLines = [EuclidLine(pulses: 1, steps: 8, velocityAbsolute: 100, rate: .r1_16,
                                                 useRiff: true, litNotes: litMask, riffOn: true,
                                                 mask: EuclidLineMask(), sourceMode: .midi, riffLength: 1, notesVelOffset: offset)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
            st.euclideousNoteSource = .midi
            let e = RecordingEmitter()
            run(SnapshotBuilder.build(from: st), chord([60, 64]), beats: 0.3, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { (note: $0.note, vel: $0.vel) }.sorted { $0.note < $1.note }
        }
        // Riff resolves rank2 (pool[1]=64) at vel 100; rank1 (pool[0]=60) is ALSO lit with a +20 offset —
        // two genuinely distinct pitches, each carrying its OWN layer's velocity.
        let distinct = onsFor(ranks: [2], litMask: 0b0000_0001, offset: 20)
        XCTAssertEqual(distinct.count, 2, "the riff note (64) and the lit note (60) are distinct pitches, both sound")
        XCTAssertEqual(distinct[0].note, 60); XCTAssertEqual(Int(distinct[0].vel), 120, "lit note: velocityAbsolute(100) + notesVelOffset(20)")
        XCTAssertEqual(distinct[1].note, 64); XCTAssertEqual(Int(distinct[1].vel), 100, "riff note: velocityAbsolute alone, unaffected by notesVelOffset")
        // Riff resolves rank1 (pool[0]=60); rank1 is ALSO lit with the SAME +20 offset — the identical pitch
        // from both layers must collapse to exactly ONE note-on, at the RIFF's own velocity (100), not 120.
        let collision = onsFor(ranks: [1], litMask: 0b0000_0001, offset: 20)
        XCTAssertEqual(collision.count, 1, "a riff/lit pitch collision sounds once, not twice")
        XCTAssertEqual(collision[0].note, 60)
        XCTAssertEqual(Int(collision[0].vel), 100, "the collision sounds at the RIFF's own velocity, since the riff layer's addPitch always runs first")
    }

    /// `notesOn: false` silences the whole notes layer while the riff is off — the lit bits themselves are
    /// unaffected (still "remembered," per Models.swift's own resolved-accessor contract; confirmed
    /// separately in EffectiveParamsTests), but nothing from them should actually sound.
    func testEuclideousNotesOnFalseSilencesTheLayerWhileRememberingWhatsLit() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [0])
        c.paramsA.euclidLines = [EuclidLine(pulses: 1, steps: 8, rate: .r1_16, useRiff: false, litNotes: 0b0000_0001, topLit: true, riffOn: false,
                                             mask: EuclidLineMask(), sourceMode: .midi, notesOn: false)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60, 64]), beats: 0.3, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "nothing sounds — riff off AND the whole notes layer off, even though rank 1 and TOP are still lit underneath")
    }

    /// TOP/TOP2 resolve against the GLOBAL `octave` only, per-note shifts never apply to them (Models.swift's
    /// own engine comment, "TOP/TOP2 entries at... stay unchanged — no per-note shift, matching the engine
    /// rule") — even when every one of the 8 per-note shift slots is set, TOP must still resolve the plain,
    /// unshifted highest pool note.
    func testEuclideousTopIgnoresPerNoteOctaveShiftsEvenWhenAllAreSet() {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [0])
        // NOTE, a lesson this file's own history already documents: `useRiff: false` ALONE does not migrate
        // to "nothing lit" — it falls through to noteSelResolved's own `.all` default, landing on the "any
        // other legacy value → 1 lit" branch, which would silently light rank 1 too (picking up its own
        // +1 shift and producing a spurious 2nd note at 72) — `litNotes: 0` must be set explicitly.
        c.paramsA.euclidLines = [EuclidLine(pulses: 1, steps: 8, rate: .r1_16, useRiff: false, litNotes: 0, topLit: true, riffOn: false,
                                             mask: EuclidLineMask(), sourceMode: .midi, noteOctShifts: Array(repeating: 1, count: 8))]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 0.3, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(ons.count, 1)
        XCTAssertEqual(ons[0].note, 67, "TOP must resolve the plain highest pool note (67), ignoring every per-note shift slot entirely")
    }

    /// A stuck-note stress test, mirroring the GATE/legato ferry's own stress test exactly but cycling
    /// `notesVelOffset` alongside the per-hit lit mask/gate/MONO-steal/transport-restart churn — the
    /// per-pitch velocity array (`pitchVel`) is new render-thread state this ferry introduced; this is the
    /// direct regression guard that threading it through REPEAT/legato/MONO-steal/RATCHET never leaves a
    /// voice open.
    func testEuclideousRiffNotesSplitStuckNoteStressVelocityOffsetGateFlipMonoStealAndTransportRestart() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func lineFor(_ tick: Int) -> EuclidLine {
            let gateVal = tick % 2 == 0 ? 1.0 : 0.99
            let lit = UInt8(1 << (tick % 8))
            let offset = (tick % 9) * 8 - 32   // cycles through -32...+32
            return EuclidLine(target: 0, pulses: 3, steps: 8, gate: gateVal, velocityAbsolute: 90, rate: .r1_32,
                               useRiff: true, litNotes: lit, riffOn: true,
                               sourceMode: .midi, riffLength: 8, notesVelOffset: offset)
        }
        func sceneFor(_ line: EuclidLine, monoOnA: Bool) -> (PluginState) {
            var gold = Machine(machineID: "gold", type: .euclid)
            gold.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            gold.paramsA.euclidLines = [line]
            var s = SceneState.empty()
            s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
            if monoOnA { s.cells[0][0] = Cell(machineID: "orange", buses: [.a]) }   // a sibling ARP, same bus — steals under MONO LAST
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? gold : Machine(machineID: $0, type: .arp) }, scenes: [s])
            if monoOnA { st.monoMask = 0b0001; st.monoPriority = [0, 0, 0, 0] }
            st.euclideousNoteSource = .midi
            return st
        }
        let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 1024
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        let router = runKeepingRouter(SnapshotBuilder.build(from: sceneFor(lineFor(0), monoOnA: false)), chord(pool), beats: 0.2, into: e, forceColumn: 0, tempo: tempo, sr: sr, frames: frames)
        var diag = KernelDiag()
        var beat = 0.2, ts = 0.2 / tempo * 60.0 * sr
        for tick in 1...40 {
            let monoOnA = (15...24).contains(tick)
            let box1 = SnapshotBuilder.build(from: sceneFor(lineFor(tick), monoOnA: monoOnA))
            if tick == 30 {
                router.process(box: box1, pool: chord(pool), playing: false, beatPos: beat, tempo: tempo,
                               sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += windowBeats; ts += Double(frames)
            }
            router.process(box: box1, pool: chord(pool), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: SnapshotBuilder.build(from: sceneFor(lineFor(40), monoOnA: false)),
                       pool: chord(pool), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════
    // MARK: - LISTEN TAB (ferry 2026-10-14, "the LISTEN tab (lane relationships)") — §11's own T1-T9.
    // Shared setup exactly per §11: 110 BPM, C minor, riff ranks [1,2,3,5,4,3,2,1] (the shipped R1 default
    // shape — confirmed by hand against the pool below: rank1=C2…rank5=G2 reproduces "C2 D2 E♭2 G2 F2 E♭2
    // D2 C2" exactly). RED = lane 0 (cable/bus A), BLUE = lane 1 (cable/bus B) — kept on separate buses
    // purely so this harness can tell the two lanes' own note-ons apart in one shared recording; nothing
    // about LISTEN itself depends on that. Pool = C natural minor from C2 (MIDI 36): the SAME 7-note
    // ascending set either SOURCE=KEY would resolve to, used directly via SOURCE=MIDI for a simpler,
    // perfectly deterministic test pool (no scale-door wiring needed to reach the identical ranks→notes
    // mapping §11 itself gives in note names).
    // ══════════════════════════════════════════════════════════════════════════════════════════════════
    private let listenPoolCMinor: [UInt8] = [36, 38, 39, 41, 43, 44, 46]   // C2 D2 E♭2 F2 G2 A♭2 B♭2
    private func listenRedLine() -> EuclidLine {
        EuclidLine(target: 0, pulses: 3, steps: 8, velocityAbsolute: 100, rate: .r1_8, emitterMask: 0b0001, useRiff: true, riffOn: true, sourceMode: .midi)
    }
    private func listenBlueLine() -> EuclidLine {
        EuclidLine(target: 0, pulses: 4, steps: 8, velocityAbsolute: 100, rate: .r1_8, emitterMask: 0b0010, useRiff: true, riffOn: true, sourceMode: .midi)
    }
    /// Builds the 2-lane (+2 unused/silent) Euclideous cell, runs it for exactly one 8-step lap (forceColumn:
    /// 0, beats sized to 8 steps at 1/8 + a safety margin), and returns every note BLUE (cable 2) actually
    /// struck, in time order, each tagged with which 0-based column (of the shared 8-step grid) it landed on.
    private func listenRun(_ red: EuclidLine, _ blue: EuclidLine, keyRoot: Int? = nil, keyType: ScaleType? = nil) -> [(col: Int, note: UInt8, vel: UInt8)] {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 5, 4, 3, 2, 1])
        c.paramsA.euclidLines = [red, blue, EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b]); return s }()])
        st.euclideousNoteSource = .midi
        // LISTEN REBUILT (2026-10-23): §6's INTERVAL/OCTAVE read the page's own KEY pill — explicit here
        // so a SHADOW/ECHO test's expected notes are easy to hand-verify against a named scale.
        st.euclideousKeyRoot = keyRoot; st.euclideousKeyType = keyType
        let e = RecordingEmitter()
        let tempo = 110.0, sr = 48_000.0
        // 8 steps × 0.5 beat/step = 4 beats for one full lap. The riff-ordinal walk each lane rides is
        // MONOTONIC across laps (never resets at the lap boundary) — so a 2nd-lap repeat of column 0,
        // though rhythmically redundant (same grid column, invisible to a per-column dedup check), still
        // advances to a genuinely NEW rank and fires as a real extra note. 3.9 stops comfortably after
        // the last real hit (column 6, beat 3.0) but strictly before the 2nd lap's column 0 (beat 4.0).
        run(SnapshotBuilder.build(from: st), chord(listenPoolCMinor), beats: 3.9, into: e, forceColumn: 0, tempo: tempo, sr: sr)
        assertNothingLeftSounding(e)
        return e.ons.filter { $0.cable == 2 }.sorted { $0.sample < $1.sample }.map { ev in
            let beat = Double(ev.sample) / sr * tempo / 60.0
            let col = Int((beat / 0.5).rounded()) % 8
            return (col, ev.note, ev.vel)
        }
    }
    /// An 8-char "x../." rhythm string from BLUE's own struck columns (T1-T4's own reporting format).
    private func listenRhythmString(_ hits: [(col: Int, note: UInt8, vel: UInt8)]) -> String {
        var s = Array(repeating: Character("."), count: 8)
        for h in hits { s[h.col] = "x" }
        return String(s)
    }
    // LISTEN REBUILT (2026-10-23): T1-T7 rewritten against the new single-source model. T3 (WITH) and T4
    // (GAPS, as a rhythm FILTER) have no new-model equivalent (§8.3: WITH -> OWN, GAPS -> FILL as a
    // REPLACEMENT not a filter) — replaced here with DELAY and BKW, the two genuinely new fugue controls
    // §11's own test 4-6 ask for. T7 (DUCK/ACCENT) is deleted outright — the LEVEL row no longer exists.
    func testListenT1Copy() {
        var blue = listenBlueLine(); blue.listenRhythm = .copy; blue.listenSource = 0
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(listenRhythmString(hits), "x..x..x.", "T1 COPY: blue inherits red's own 3-of-8 pattern exactly")
    }
    // Adversarial-review fix (2026-10-23): §3.5 — "The follower's own RHYTHM RESTART and MELODY RESTART
    // are not read while COPY or FILL is on." A leftover (or independently-set) chain on a borrowing lane
    // must not shift its pattern phase — this must come out byte-identical to T1's plain COPY.
    func testListenCopyIgnoresTheFollowersOwnLeftoverRestartChains() {
        var blue = listenBlueLine(); blue.listenRhythm = .copy; blue.listenSource = 0
        blue.restartRhythmBars = [1]; blue.restartMelodyPasses = [2]
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(listenRhythmString(hits), "x..x..x.", "a borrowing lane's own restart chains must not apply — byte-identical to T1's plain COPY with no chain set")
    }
    func testListenT2Fill() {
        var blue = listenBlueLine(); blue.listenRhythm = .fill; blue.listenSource = 0
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(listenRhythmString(hits), ".xx.xx.x", "T2 FILL: blue plays exactly red's gaps (the complement of red's pattern)")
    }
    // Adversarial-review fix (2026-10-23): this test used to expect "x.x..x.." (hits at 0,2,5 — a plain
    // rotation, wrapping red's step-6 hit around to step 0). That was the BUG: §3.6 is explicit — "before
    // the first DELAY steps of a transport run have passed, it plays nothing" — a TRUE rest, not whatever
    // the wrapped-around rotation happens to contain. Corrected expectation: ticks 0-1 (< DELAY) are forced
    // silent even though the rotated pattern would hit at tick 0; only ticks 2 and 5 actually sound.
    func testListenT3CopyWithDelay() {
        var blue = listenBlueLine(); blue.listenRhythm = .copy; blue.listenSource = 0; blue.listenDelay = 2
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(listenRhythmString(hits), "..x..x..", "T3 DELAY 2, first lap: ticks 0-1 are the transport-start grace period (forced silent, §3.6) even though the rotated pattern (red's 0,3,6 shifted 2 later, wrapping) would hit at 0; only 2 and 5 actually sound")
    }
    // The grace period is a ONE-TIME thing at transport start (§3.6: "a transport RUN"), not reapplied
    // every lap — a longer run must show the wrapped hit (tick 0 of lap 2, i.e. tick 8 overall) sounding
    // once the lane is well past its first DELAY ticks.
    func testListenT3bDelayGraceIsOnlyAtTransportStartNotEveryLap() {
        var blue = listenBlueLine(); blue.listenRhythm = .copy; blue.listenSource = 0; blue.listenDelay = 2
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 5, 4, 3, 2, 1])
        c.paramsA.euclidLines = [listenRedLine(), blue, EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter(); let tempo = 110.0, sr = 48_000.0
        // Two full laps (8 beats at 0.5 beat/step × 8 steps = 4 beats/lap) plus a hair, so lap 2's tick 0
        // (absolute tick 8) is reached and finished sounding before the run stops.
        run(SnapshotBuilder.build(from: st), chord(listenPoolCMinor), beats: 7.9, into: e, forceColumn: 0, tempo: tempo, sr: sr)
        assertNothingLeftSounding(e)
        let hits = e.ons.filter { $0.cable == 2 }.sorted { $0.sample < $1.sample }.map { ev -> Int in
            let beat = Double(ev.sample) / sr * tempo / 60.0
            return Int((beat / 0.5).rounded())   // absolute tick (0...15), NOT wrapped to a column — lap 2 must read 8, not 0
        }
        XCTAssertEqual(hits, [2, 5, 8, 10, 13], "lap 1: 2, 5 (0 suppressed by the grace period); lap 2 (ticks 8-15): all three of 8, 10, 13 sound — the grace period never reapplies")
    }
    func testListenT4CopyBackward() {
        var blue = listenBlueLine(); blue.listenRhythm = .copy; blue.listenSource = 0; blue.listenDirection = .bkw
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(listenRhythmString(hits), ".x..x..x", "T4 BKW: red's own order (0,3,6) read back-to-front (6,3,0)")
    }
    func testListenT5ShadowMovesByIntervalInTheCurrentKey() {
        // RHYTHM=COPY too, so blue's hits land EXACTLY on red's own (matching the old T5's own FOLLOW+SHADOW
        // pairing) — each of blue's 3 hits then shadows red's strike from that SAME tick, in order.
        var blue = listenBlueLine(); blue.listenRhythm = .copy; blue.listenSource = 0
        blue.listenPitch = .shadow; blue.listenInterval = 2   // a third up, in the explicit C MAJOR key below
        let hits = listenRun(listenRedLine(), blue, keyRoot: 0, keyType: .major)
        XCTAssertEqual(hits.map { $0.note }, [40, 41, 42], "T5 SHADOW+3RD (C major): red's C2/D2/E\u{266D}2 (36/38/39) each move a diatonic 3rd up to E2/F2/F\u{266F}2 (40/41/42)")
    }
    func testListenT6AvoidMutesEveryColliding() {
        var blue = listenBlueLine()
        blue.pulses = 3   // "give blue exactly red's settings" — same 3-of-8 pattern, same riff/walk, so its own notes exactly collide with red's
        blue.listenPitch = .avoid; blue.listenSource = 0   // AVOID is mute-only now — no MOVE action any more (§8.3)
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(hits.count, 0, "T6 AVOID: blue would play exactly what red plays at every hit — all of them dropped by pitch class")
    }
    /// §11.8, literal "Paul's canvas case" (adversarial-review fix — this exact example was never built as
    /// a test the first time, which is why the DELAY grace-period bug above went undetected): source plays
    /// C D E♭ F G E♭ D C on every step of 8. COPY DELAY 2 ECHO → steps 3-8 play C D E♭ F G E♭ (the SOURCE's
    /// own strikes 0...5 in order — ECHO's hit rank starts at 0 on the first tick that actually SOUNDS, not
    /// on the two grace-period ticks). SHADOW in the same setup plays E♭ F G E♭ D C (the source's own
    /// strike at that SAME tick, same-time counts per §1.4).
    private func listenEchoCanvasRun(pitch: EuclideousListenPitchMode) -> [(col: Int, note: UInt8, vel: UInt8)] {
        let red = EuclidLine(target: 0, pulses: 8, steps: 8, velocityAbsolute: 100, rate: .r1_8, emitterMask: 0b0001, useRiff: true, riffOn: true, sourceMode: .midi)
        var blue = EuclidLine(target: 0, pulses: 8, steps: 8, velocityAbsolute: 100, rate: .r1_8, emitterMask: 0b0010, useRiff: true, riffOn: true, sourceMode: .midi)
        blue.listenRhythm = .copy; blue.listenSource = 0; blue.listenDelay = 2; blue.listenPitch = pitch
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 3, 2, 1])   // C D E♭ F G E♭ D C
        c.paramsA.euclidLines = [red, blue, EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter(); let tempo = 110.0, sr = 48_000.0
        run(SnapshotBuilder.build(from: st), chord(listenPoolCMinor), beats: 3.9, into: e, forceColumn: 0, tempo: tempo, sr: sr)
        assertNothingLeftSounding(e)
        return e.ons.filter { $0.cable == 2 }.sorted { $0.sample < $1.sample }.map { ev in
            let beat = Double(ev.sample) / sr * tempo / 60.0
            return (Int((beat / 0.5).rounded()) % 8, ev.note, ev.vel)
        }
    }
    func testListenEchoFollowsTheSourcesOwnLineInOrderCanonStyle() {
        let hits = listenEchoCanvasRun(pitch: .echo)
        XCTAssertEqual(hits.map { $0.note }, [36, 38, 39, 41, 43, 39], "ECHO: steps 3-8 play C D E♭ F G E♭ — the source's strikes 0...5, not a DELAY-shifted lookup")
    }
    func testListenShadowDoublesWhateverTheSourceIsPlayingRightNow() {
        let hits = listenEchoCanvasRun(pitch: .shadow)
        XCTAssertEqual(hits.map { $0.note }, [39, 41, 43, 39, 38, 36], "SHADOW: steps 3-8 double the source's OWN same-tick note — E♭ F G E♭ D C")
    }
    // LISTEN REBUILT (2026-10-23): `testListenT8LoopsGreyOutTheWholeCycle` (the OLD 3-row-partner greyed-
    // partners picker) and `testListenT9TurningFollowOffRestoresTheLanesOwnSettings` deleted — both test
    // retired machinery (`euclideousListenGreyedPartners`'s 3-row model; FOLLOW). The new model's own
    // "returns to OWN exactly as it was" property is §11 test 14's own job (task #35).
    // MARK: - LISTEN SHADOW / AVOID follow the partner's REAL walk (fixed 2026-10-20)
    // `euclideousListenPartnerNoteAt` used to re-derive the partner's riff ordinal by hand from the retired LOCK model: it knew nothing of ADVANCE EVERY or the restart chains, so a SHADOW lane
    // followed a different column from the one its partner played. It now asks the same chain core + `euclideousRiffColumn` the Router uses. Verified against the OLD function: every test below failed on it except the two
    // BASELINES (`testAShadowOfAPlainPartnerIsUnchanged` and the one-link melody chain, which the old coarse span re-anchor happened to cover) — those pin that the rewrite changes nothing it got right.
    /// Red and blue over `beats` (several laps), each lane's struck notes in time order. Same rig as `listenRun` (110 BPM, C minor pool, ranks [1,2,3,5,4,3,2,1]).
    private func listenBothNotes(_ red: EuclidLine, _ blue: EuclidLine, beats: Double, ranks: [Int] = [1, 2, 3, 5, 4, 3, 2, 1]) -> (red: [UInt8], blue: [UInt8]) {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks)
        c.paramsA.euclidLines = [red, blue, EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b]); return s }()])
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord(listenPoolCMinor), beats: beats, into: e, forceColumn: 0, tempo: 110, sr: 48_000)
        assertNothingLeftSounding(e)
        func notes(_ cable: Int) -> [UInt8] { e.ons.filter { $0.cable == cable }.sorted { $0.sample < $1.sample }.map { $0.note } }
        return (notes(1), notes(2))
    }
    // LISTEN REBUILT (2026-10-23): COPY (not just `blue = red`'s own already-matching rhythm) ties blue's
    // hit timing exactly to red's, so SHADOW's "most recent strike" lookup lands on red's CURRENT hit at
    // every one of blue's — these tests exercise the REAL mechanism across walk configurations, not a
    // coincidence of blue/red sharing identical standalone settings.
    private func shadowOf(_ red: EuclidLine) -> EuclidLine {
        var blue = red
        blue.emitterMask = 0b0010
        blue.listenRhythm = .copy; blue.listenSource = 0
        blue.listenPitch = .shadow; blue.listenInterval = 0; blue.listenOctave = 0   // a unison shadow
        return blue
    }
    func testShadowFollowsAPartnerWithAdvanceEvery() {
        var red = listenRedLine(); red.riffAdvanceEvery = 2
        let (r, b) = listenBothNotes(red, shadowOf(red), beats: 12)
        XCTAssertGreaterThanOrEqual(r.count, 8, "red struck over three laps")
        XCTAssertEqual(b, r, "a unison SHADOW sounds exactly what its partner sounds — EVERY 2 groups the partner's hits in pairs, so the shadow must too")
        XCTAssertNotEqual(Array(r.prefix(4)), [36, 38, 39, 41], "(the walk is not the plain one: the partner's first hits repeat a column)")
    }
    func testShadowFollowsAPartnersMelodyRestartChain() {   // BASELINE: a one-link chain was already right
        var red = listenRedLine(); red.restartMelodyPasses = [1]      // the riff walk restarts at every pass
        let (r, b) = listenBothNotes(red, shadowOf(red), beats: 12)
        XCTAssertGreaterThanOrEqual(r.count, 8)
        XCTAssertEqual(b, r, "the shadow restarts with the partner's melody chain, not on a monotonic ordinal")
        // and the partner really does restart: the same three notes every lap
        XCTAssertEqual(Array(r.prefix(3)), Array(r[3..<6]))
    }
    func testShadowFollowsAMultiLinkMelodyChain() {
        var red = listenRedLine(); red.restartMelodyPasses = [1, 2]    // restarts at pass 0 AND pass 1 of every 3-pass cycle — not just at the cycle's start
        let (r, b) = listenBothNotes(red, shadowOf(red), beats: 16)
        XCTAssertGreaterThanOrEqual(r.count, 12)
        XCTAssertEqual(b, r)
    }
    func testShadowFollowsARhythmChainThatCutsThePassShort() {
        var red = listenRedLine(); red.steps = 7; red.pulses = 3        // a 7-step lap is 3.5 beats…
        red.restartRhythmBars = [1]                                      // …and the rhythm restarts every 4-beat bar, cutting every second pass short
        let (r, b) = listenBothNotes(red, shadowOf(red), beats: 16)
        XCTAssertGreaterThanOrEqual(r.count, 12)
        XCTAssertEqual(b, r)
    }
    func testShadowFollowsAnAdvStepPartnerWithEveryAndAChain() {
        var red = listenRedLine(); red.riffAdvanceStep = true; red.riffAdvanceEvery = 2; red.restartMelodyPasses = [2]
        let (r, b) = listenBothNotes(red, shadowOf(red), beats: 16)
        XCTAssertGreaterThanOrEqual(r.count, 10)
        XCTAssertEqual(b, r)
    }
    func testShadowFollowsAPartnerWalkingBackwardsOverAShorterLoopWithShift() {
        var red = listenRedLine(); red.riffDir = .reverse; red.riffLength = 5; red.riffRotate = 2; red.riffAdvanceEvery = 3
        let (r, b) = listenBothNotes(red, shadowOf(red), beats: 12)
        XCTAssertGreaterThanOrEqual(r.count, 8)
        XCTAssertEqual(b, r)
    }
    func testAvoidSeesThePartnersRealNoteWhenItHasAdvanceEvery() {
        // LISTEN REBUILT: AVOID now reads the source's CAPTURED strike directly — there is no separate
        // derivation left to disagree with the engine's real note (the old bug class this guarded against
        // is structurally impossible now). Kept as a plain regression check that ADVANCE EVERY's grouping
        // doesn't somehow let a colliding note through.
        var red = listenRedLine(); red.riffAdvanceEvery = 2
        var blue = red; blue.emitterMask = 0b0010
        blue.listenPitch = .avoid; blue.listenSource = 0
        let (r, b) = listenBothNotes(red, blue, beats: 12)
        XCTAssertGreaterThanOrEqual(r.count, 8)
        XCTAssertEqual(b.count, 0, "every hit collides with red's real note (EVERY 2 included), so all are dropped")
    }
    func testAShadowOfAPlainPartnerIsUnchanged() {
        // the baseline T5 path: no EVERY, no chains — the rewrite must reproduce the old answer exactly
        let red = listenRedLine()
        let (r, b) = listenBothNotes(red, shadowOf(red), beats: 12)
        XCTAssertEqual(b, r)
        XCTAssertEqual(Array(r.prefix(3)), [36, 38, 39], "red's first lap: C2 D2 E\u{266D}2 (T5)")
    }

    // LISTEN REBUILT (2026-10-23): `testListenAvoidAnyGreysOutInEveryOtherRowToo` and
    // `testListenAvoidAnyLoopIsBrokenOnPresetLoad` deleted — ANY (and the 3-row-partner model
    // `euclideousListenGreyedPartners`/`euclideousListenBreakLoops` tested) no longer exist (§2.1 has no
    // ANY option; one shared source per lane). The new model's own cycle-break
    // (`euclideousListenBreakLoopsOnTheNewModel`) and disabled-chip set (`euclideousListenDisabledSources`)
    // are covered directly in Tests/ListenTabTests.swift (§9's own tests, task #30).

    // ── RIFF-GRID WALK TAGS (ferry 2026-10-15): the UI's prediction is a MIRROR of this engine's own walk ───────
    // `euclideousWalkTick` re-implements `runEuclidLine`'s tick → (hit, ordinal, played step) arithmetic on the main
    // thread so the page can schedule a tag's flight BEFORE the hit. If the two ever drift the tag would fly to the
    // wrong seat, so this runs the REAL router across walk configurations and checks the polled step + ordinal of
    // its last hit against the mirror's answer for the same tick.
    func testWalkTagMirrorMatchesTheEnginesOwnWalkAcrossConfigurations() {
        let cases: [(String, (inout EuclidLine) -> Void)] = [
            ("FWD", { _ in }),
            ("REV stride 3 len 5 nudge 2", { $0.riffDir = .reverse; $0.riffStride = 3; $0.riffLength = 5; $0.riffRotate = 2 }),
            ("PEND", { $0.riffDir = .pendulum }),
            ("PING len 6", { $0.riffDir = .pingpong; $0.riffLength = 6 }),
            // "LOCK" is now a melody chain of [1] — §4.7, exactly what riffLock (retired, §7) did. The old per-lane
            // RESET (`resetSteps`) is likewise retired in favour of chains (2026-10-19) — converted to a rhythm
            // chain below rather than ported, since `resetSteps` no longer drives the real engine live (§12).
            ("MELODY-1", { $0.restartMelodyPasses = [1] }),
            ("ADV STEP", { $0.riffAdvanceStep = true }),
            ("ADV STEP + MELODY-1 + stride 2", { $0.riffAdvanceStep = true; $0.restartMelodyPasses = [1]; $0.riffStride = 2 }),
            ("pattern BKW", { $0.direction = .bkw }),
            ("pattern PING-PONG + PEND", { $0.direction = .pingpong; $0.riffDir = .pendulum }),
            ("offset + tilt", { $0.rotate = 3; $0.tilt = 0.4 }),
            // steps 7 (not the shared base's 8): an 8-step/1-8 lap is exactly 1 bar, so a bar-aligned rhythm chain
            // would be indistinguishable from FREE (§5.6) — 7 steps genuinely rephases.
            ("RHYTHM chain [2,1] on 7 steps", { $0.steps = 7; $0.restartRhythmBars = [2, 1] }),
            ("RHYTHM [2,1] + MELODY [1] on 7 steps + stride 2", { $0.steps = 7; $0.restartRhythmBars = [2, 1]; $0.restartMelodyPasses = [1]; $0.riffStride = 2 }),
        ]
        var seenOrds = Set<Int64>(), seenSteps = Set<Int>()   // guards against a vacuous pass (both sides stuck at 0)
        for (name, tweak) in cases {
            for beats in [2.3, 5.7, 9.1, 13.3] {
                var line = EuclidLine(target: 0, pulses: 5, steps: 8, rate: .r1_8, useRiff: true, sourceMode: .midi)
                tweak(&line)
                var c = Machine(machineID: "gold", type: .euclid)
                c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
                c.paramsA.euclidLines = [line]
                var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                     scenes: [{ var s = SceneState.empty()
                                         s.stepRate = .r1_8   // one bar = 8 × 0.5 = 4 beats (the `cyc` handed to the mirror below)
                                         s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                         return s }()])
                st.euclideousLanesSeqRate = .oneBar
                let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60, 62, 64]), beats: beats, into: RecordingEmitter(), forceColumn: 0)
                let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
                // `runKeepingRouter` renders whole 2048-frame windows until it has covered `beats`, so the last hit it processed is the one
                // before the END of the final window, not before `beats` itself.
                let windowBeats = 2048.0 * 120.0 / 60.0 / 48_000.0, processedEnd = (beats / windowBeats).rounded(.up) * windowBeats
                guard let last = euclideousWalkScanHits(cfg, beat: processedEnd - 1e-9, back: 1, ahead: 0).prev.first else { XCTFail("\(name): no hit found by the mirror"); continue }
                let t = euclideousWalkTick(cfg, tick: last)
                XCTAssertEqual(router.euclideousRiffPositions()[0], t.playedStep, "\(name) @\(beats): played step")
                XCTAssertEqual(router.euclideousRiffWalkState()[0], t.advOrd, "\(name) @\(beats): walk ordinal")
                seenOrds.insert(t.advOrd); seenSteps.insert(t.playedStep)
            }
        }
        XCTAssertGreaterThan(seenOrds.count, 6, "the cases genuinely exercise different ordinals")
        XCTAssertGreaterThan(seenSteps.count, 3, "…and different steps")
    }

    // …and for a lane borrowing RHYTHM, whose pattern, step count and rate are borrowed from its source (÷ 2^SPEED).
    // LISTEN REBUILT (2026-10-23): `testWalkTagMirrorMatchesAFollowingLanesBorrowedPatternAndRate`
    // (FOLLOW-vs-mirror agreement) deleted — FOLLOW no longer exists. The walk-tag mirror itself
    // (`euclideousRhythmBorrowPartner`/`euclideousEffectiveHitPattern`/`euclideousWalkLaneConfig`, renamed
    // from `euclideousFollowPartner`) was rewritten for COPY/FILL — including the direction-double-
    // application bug fixed in both the Router and this mirror — and its new-model equivalent test lives in
    // `ClarityPassTests.testACopyLanesFooterHitsAreTheTicksTheEngineActuallyPlays`/
    // `testACopyLanesBeatGroupsAndDivisionAreItsSources`, not here.

    // THE FERRY'S CORE CLAIM: a tag arrives "exactly at the advance's time: the note-on time". The mirror's predicted real
    // onset beat (swing included) must equal the engine's own emitted note-on sample, hit for hit.
    func testWalkTagPredictedOnsetsMatchTheEnginesNoteOnSamples() {
        for swing in [50, 62, 75] {
            var line = EuclidLine(target: 0, pulses: 5, steps: 8, rate: .r1_16, useRiff: true, sourceMode: .midi)
            line.noteSel = .low
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            c.paramsA.euclidLines = [line]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                 scenes: [{ var s = SceneState.empty()
                                     s.stepRate = .r1_8; s.swing = swing
                                     s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                     return s }()])
            st.euclideousNoteSource = .midi
            let e = RecordingEmitter()
            // 8 held notes: every riff rank 1…8 resolves to a real, in-range pitch, so EVERY hit sounds (with a 1-note pool ranks 7–8 fold above 127 and are dropped).
            run(SnapshotBuilder.build(from: st), chord([48, 50, 52, 53, 55, 57, 59, 60]), beats: 7.9, into: e, forceColumn: 0)
            // One onset per hit: a hit can strike several pitches at the same instant (the riff note + a lit note), so collapse those.
            var engineBeats: [Double] = []
            for b in e.ons.filter({ $0.cable == 1 }).map({ Double($0.sample) / 48_000 * 120 / 60 }).sorted() where engineBeats.last.map({ b - $0 > 0.01 }) ?? true { engineBeats.append(b) }
            let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8,
                                               swingPercent: Double(swing), stepBeats: 0.5)!
            let predicted = (0..<40).filter { euclideousWalkTick(cfg, tick: Int64($0)).isHit }.map { euclideousWalkRealBeat(cfg, tick: Int64($0)) }.filter { $0 < 7.5 }
            XCTAssertGreaterThan(engineBeats.count, 6, "swing \(swing): the engine played notes")
            for (i, b) in engineBeats.prefix(predicted.count).enumerated() {
                XCTAssertEqual(b, predicted[i], accuracy: 0.002, "swing \(swing): hit \(i) — engine note-on vs predicted arrival (beats)")
            }
        }
    }

    // THE MIRROR MUST AGREE WITH THE ENGINE UNDER ANY HOST BAR (14 Oct sequencer-step-length fix, kept through the LANES GRID rebuild): a
    // pre-feature document's old per-lane reset migrates against the host's REAL bar length (`S = rate × beatsPerBar`), so the mirror and the
    // engine must be handed the same bar. 3/4 (3 beats/bar) and a 1/16 grid (so grid-geometry `cyc` = 2 beats, NOT a bar) are exactly the
    // combinations where `cyc` and the host's bar disagree.
    func testWalkTagMirrorUsesTheHostsRealBarLengthForPerLaneReset() {
        for (bpb, stepRate) in [(3.0, StepRate.r1_8), (4.0, StepRate.r1_4), (6.0, StepRate.r1_2)] {
            var line = EuclidLine(target: 0, pulses: 5, steps: 8, rate: .r1_8, useRiff: true, sourceMode: .midi, riffLength: 8, resetSteps: 1)
            line.riffDir = .pendulum
            // RESTART CHAINS (2026-10-19): migrated-and-pinned against THIS iteration's own host bar length,
            // simulating the AVC resync tick (§12) — the mirror (`euclideousWalkLaneConfig`, below) and the real
            // Router must read the SAME (already-migrated) line, since neither one migrates anything itself.
            line = migratedLine(line, legacyRate: .oneBar, legacyLen: 8, barBeats: bpb)
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            c.paramsA.euclidLines = [line]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                 scenes: [{ var s = SceneState.empty()
                                     s.stepRate = stepRate
                                     s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                     return s }()])
            st.euclideousLanesSeqRate = .oneBar
            let cyc = stepRate.beats * Double(Snap.cols)
            XCTAssertNotEqual(cyc, bpb, "this case is only meaningful where grid-cycle ≠ the host's bar")
            for beats in [7.3, 13.9, 19.1] {
                let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60, 62, 64]), beats: beats, into: RecordingEmitter(), forceColumn: 0, beatsPerBar: bpb)
                let right = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: cyc, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8, beatsPerBar: bpb)!
                let windowBeats = 2048.0 * 120.0 / 60.0 / 48_000.0, end = (beats / windowBeats).rounded(.up) * windowBeats
                guard let last = euclideousWalkScanHits(right, beat: end - 1e-9, back: 1, ahead: 0).prev.first else { XCTFail("no hit"); continue }
                let t = euclideousWalkTick(right, tick: last)
                XCTAssertEqual(router.euclideousRiffPositions()[0], t.playedStep, "bpb \(bpb) @\(beats): step")
                XCTAssertEqual(router.euclideousRiffWalkState()[0], t.advOrd, "bpb \(bpb) @\(beats): ordinal")
            }
        }
    }

    // RETIRED (2026-10-19): "the chains are the only restart model" (SUMMARY) — a hand-placed per-step mask has no
    // chain equivalent (chains restart only on bar/pass boundaries) and is no longer read live by the real engine;
    // it plays as FREE until migrated (§12), which this unit-test harness (no `AudioUnitViewController` resync
    // loop) never runs. Not ported. `testChainMirrorMatchesTheRealRouterUnderARephasingRhythmChainAndARestarting
    // MelodyChain` (above, in the LANES-GRID section) stands in for this test's real substance: the walk mirror
    // must never disagree with the real Router, now proven against chains instead of an arbitrary mask.

    // LISTEN REBUILT (2026-10-23): `testWalkTagMirrorMatchesWithAndGapsLanesInTheEngine` deleted — WITH and
    // GAPS no longer exist (GAPS -> FILL has a new-model equivalent; WITH has none, §8.3). Same deferral as
    // the FOLLOW mirror test above: the mirror itself is task #32's own scope.

    // MARK: - FERRY (2026-10-15, "Fourfold settings — a gear, one sheet, three tabs") §10 tests 2-4

    private func fourfoldSingleLaneBox(mask: UInt16 = 0xFFFF, source: EuclideousLaneSource = .midi,
                                        busChannels: [Int] = [1, 2, 3, 4], line: EuclidLine? = nil) -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [line ?? EuclidLine(target: 0, pulses: 1, steps: 1, rate: .r1_4)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  s.stepRate = .r1_8
                                  s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                  return s }()])
        st.euclideousNoteSource = source
        st.euclideousMidiInChannelMask = mask
        st.busChannels = busChannels
        return SnapshotBuilder.build(from: st)
    }
    // §3.5/§10 test 2: a mask narrowed to channel 1 only filters a MIDI-mode lane's own held pool.
    func testFourfoldMidiInChannelMaskFiltersAMidiModeLaneByChannel() {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0)   // channel 1 (0-based wire 0) — survives the filter
        p.noteOn(64, velocity: 100, channel: 1)   // channel 2 — filtered out
        let e = RecordingEmitter()
        run(fourfoldSingleLaneBox(mask: 1 << 0), p, beats: 7.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertTrue(notes.contains(60), "channel 1's note must still play")
        XCTAssertFalse(notes.contains(64), "channel 2's note must be filtered out")
    }
    // §10 test 2: KEY and CHORDS lanes read nothing from `globalSrcChanMask` at all (confirmed by reading
    // Router.swift's `.key`/`.chords` branches before writing this) — a narrow MIDI mask must have zero
    // effect on either.
    func testFourfoldMidiInChannelMaskDoesNotAffectKeyOrChordsMode() {
        for source in [EuclideousLaneSource.key, .chords] {
            let e = RecordingEmitter()
            run(fourfoldSingleLaneBox(mask: 1 << 0, source: source), chord([60]), beats: 7.9, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            XCTAssertFalse(e.ons.filter { $0.cable == 1 }.isEmpty, "\(source): still sounds, unaffected by the MIDI-only channel mask")
        }
    }
    // §3.5: "the riff, which follows lane 1, gets it as well" — a riff-mode lane must never reach a
    // channel the mask has filtered out of the shared pool.
    func testFourfoldMidiInChannelMaskFiltersTheRiffToo() {
        var line = EuclidLine(target: 0, pulses: 1, steps: 1, rate: .r1_4, useRiff: true, riffOn: true, sourceMode: .midi, riffLength: 2)
        line.restartMelodyPasses = [1]   // "LOCK" is now a melody chain of [1] — §4.7 (riffLock itself is retired, §7)
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 2, ranks: [1, 2])
        c.paramsA.euclidLines = [line]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  s.stepRate = .r1_8
                                  s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                  return s }()])
        st.euclideousNoteSource = .midi
        st.euclideousMidiInChannelMask = 1 << 0   // channel 1 only
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0)    // channel 1 — rank 1, survives
        p.noteOn(64, velocity: 100, channel: 1)    // channel 2 — filtered out of the shared pool entirely
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), p, beats: 7.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertFalse(e.ons.filter { $0.cable == 1 }.map { $0.note }.contains(64), "the riff must never reach channel 2's note once it's filtered out of the shared pool")
    }
    // §10 test 2: narrowing the mask while a note is held (the controller never released it) must still
    // close cleanly — no stuck note left on the old, now-filtered-out channel.
    func testFourfoldMidiInChannelMaskNarrowingMidHoldLeavesNoStuckNotes() {
        let wideBox = fourfoldSingleLaneBox(mask: 0xFFFF)
        let narrowBox = fourfoldSingleLaneBox(mask: 1 << 0)
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0)
        p.noteOn(64, velocity: 100, channel: 1)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < 3.9 {
            router.process(box: wideBox, pool: p, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                            timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        while beat < 7.9 {
            router.process(box: narrowBox, pool: p, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                            timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: narrowBox, pool: p, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                        timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        XCTAssertTrue(e.ons.contains { $0.note == 60 })
    }
    // §4.4/§10 test 3: a bus channel change mid-note must not strand the sounding note — its note-off must
    // land on the channel its note-on actually used, not the new live channel. `.r1_1` (ArpRate, 4 beats/
    // tick) + the default ~0.9 gate keeps the hit sounding for ~3.6 beats, well past the switch at beat 2.
    func testFourfoldBusChannelChangeMidNoteClosesOnTheOriginalChannel() {
        let line = EuclidLine(target: 0, pulses: 1, steps: 1, rate: .r1_1)
        let boxCh5 = fourfoldSingleLaneBox(busChannels: [5, 2, 3, 4], line: line)
        let boxCh9 = fourfoldSingleLaneBox(busChannels: [9, 2, 3, 4], line: line)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < 1.9 {   // well within the ~3.6-beat gate
            router.process(box: boxCh5, pool: chord([60]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                            timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        while beat < 5.9 {   // crosses the gate's natural close under the NEW channel
            router.process(box: boxCh9, pool: chord([60]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                            timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: boxCh9, pool: chord([60]), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                        timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.contains { $0.chan == 4 }, "channel 5 (1-based) = wire nibble 4")
        XCTAssertTrue(e.offs.filter { $0.cable == 1 }.contains { $0.chan == 4 }, "the note that opened on channel 5 must close on channel 5, not the live channel 9 at close time")
    }
    // §4.6/§10 test 4: every sounding Euclideous voice gets its own note-off on its own channel, CC 123 goes
    // out on all 4 outputs' CURRENT channels, and the lane keeps playing afterward.
    func testFourfoldAllNotesOffClosesEuclideousVoicesCC123sAllFourOutputsAndTheLaneContinues() {
        // pulses:2,steps:2 (not 1,1): the pattern builder clamps its step count to a minimum of 2
        // (`n = max(2, min(16, nIn))`), so a literal `steps:1` silently becomes a 2-element [hit,rest]
        // alternation, not a genuine always-hit single step — 2-of-2 is the real "every tick is a hit."
        let line = EuclidLine(target: 0, pulses: 2, steps: 2, rate: .r1_1)
        let box = fourfoldSingleLaneBox(busChannels: [5, 6, 7, 8], line: line)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < 1.9 {
            router.process(box: box, pool: chord([60]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                            timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: box, pool: chord([60]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                        timestampSample: ts, frameCount: frames, forceColumn: 0, euclideousAllNotesOff: true, out: e, diag: &diag)
        beat += windowBeats; ts += Double(frames)
        while beat < 7.9 {   // the lane's own next hit — "no transport/pattern/undo/document change"
            router.process(box: box, pool: chord([60]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                            timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: box, pool: chord([60]), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                        timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        XCTAssertTrue(e.offs.filter { $0.cable == 1 }.contains { $0.note == 60 && $0.chan == 4 }, "the sounding voice's own note-off, on its own channel (5 → wire 4)")
        let cc123Chans = Set(e.events.filter { $0.status == 0xB0 && $0.note == 123 && $0.cable >= 1 && $0.cable <= 4 }.map { $0.chan })
        XCTAssertEqual(cc123Chans, Set([4, 5, 6, 7]), "CC123 on all 4 outputs' current channels (5,6,7,8 → wire 4,5,6,7)")
        XCTAssertGreaterThanOrEqual(e.ons.filter { $0.cable == 1 }.count, 2, "the lane keeps playing after the flush")
    }

    // MARK: - MIX TAB (ferry 2026-10-18) — the 20 factory presets must sound EXACTLY as before the per-pitch-gate engine change.

    /// Renders one factory preset the way the page does (its lanes + riff on a Euclideous-row machine, its page-level note source /
    /// key / chords from the preset document) over `bars` bars and returns an FNV-1a hash of the entire note wire stream
    /// (sample, cable, status, channel, note, velocity) plus the note-on count.
    private func mixPresetStreamHash(_ s0: PluginState, bars: Double = 8) -> (hash: UInt64, ons: Int, events: Int) {
        var s = s0
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = s.euclideousLinesResolved
        c.paramsA.euclideousRiff = s.euclideousRiffResolved
        c.paramsA.riffs = s.riffsResolved
        c.paramsA.activeRiff = s.activeRiffResolved
        // `c.paramsA.euclideousLiveGrid` is deliberately left unset (2026-10-18, "drop the loop
        // functionality") — matches `BuildPage.swift`'s own real wiring exactly now that it no longer
        // populates this field, so `SnapshotBuilder`'s `?? riffs[activeRiff]` fallback is what every
        // factory preset actually plays through in the real app.
        s.machines = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
        s.scenes = [{ var sc = SceneState.empty()
            var cell = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); cell.inputReceiver = 3
            sc.cells[0][Snap.euclideousRow] = cell
            return sc }()]
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: s), chord([48, 50, 52, 53, 55, 57, 59, 60]), beats: bars * 4, into: e, forceColumn: 0)
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            mix(UInt64(bitPattern: ev.sample)); mix(UInt64(ev.cable)); mix(UInt64(ev.status)); mix(UInt64(ev.chan)); mix(UInt64(ev.note)); mix(UInt64(ev.vel))
        }
        return (h, e.ons.count, e.events.count)
    }
    /// GOLDEN — captured on the engine BEFORE the MIX ferry's per-pitch-gate change (origin/main 16c634c): preset name → (stream hash,
    /// note-on count) over 8 bars. With `notesGate`/`notesVelocity` unset every layer resolves to GATE / VEL + offset, so every
    /// preset must render the identical note-ons, note-offs and velocities (ferry §9.8).
    private let mixPresetGolden: [String: (UInt64, Int)] = [
        "STRIDE WALK": (15158537513244454245, 600),
        "MIRROR WALK": (14602258971500086829, 784),
        "PENDULUM": (16553319164548356549, 528),
        "PING-PONG LEAD": (1749720456999276605, 800),
        "DRUNKEN WALK": (6298240852141731197, 592),
        "RANDOM GARDEN": (2134285747163594173, 920),
        "OCTAVE COLUMN": (374866415379030501, 1312),
        "KOTEKAN": (4950508307049700157, 1032),
        "FIVE AGAINST EIGHT": (14264613458961964333, 640),
        "MIRRORED PITCH": (13040720679594914645, 464),
        "FIFTH ABOVE": (1304043531156515901, 656),
        "HELD BREATH": (7294625709145352757, 56),
        "STUTTER FILL": (7961789708151856301, 1816),
        "CALL AND HOLD": (15395334754731690733, 432),
        "LONG TAIL": (9801365217848589509, 168),
        "GAPPED GROOVE": (6558745496196285037, 520),
        "EARLY BLOOM": (8167914719946807021, 280),
        "SCALE WALK": (57570067221704893, 656),
        "ARPEGGIO LADDER": (4270012540596340973, 2064),
        "BACKWARDS GLANCE": (645646754865243525, 648)
    ]
    func testEveryFactoryPresetRendersTheSameNoteStreamAsBeforeThePerPitchGateEngine() {
        XCTAssertEqual(EuclideousPresets.all.count, 20)
        for (name, make) in EuclideousPresets.all {
            guard let want = mixPresetGolden[name] else { XCTFail("no golden for \(name)"); continue }
            let got = mixPresetStreamHash(make())
            XCTAssertEqual(got.ons, want.1, "\(name): note-on count")
            XCTAssertEqual(got.hash, want.0, "\(name): the note-on/off/velocity stream over 8 bars must be bit-identical to before this change")
        }
    }

    // MARK: - RESTART CHAINS (ferry 2026-10-19) §14 test 1 — golden renders captured BEFORE the restart-chain
    // engine rewrite (the masked rhythm/melody grid → EuclideousRestartChain). Two halves: the 20 factory
    // presets' note stream over 32 bars (§14's own literal window), and LOCK's riff-rank behaviour (§7.3:
    // "convert the existing LOCK tests to melody chain 1 rather than deleting them — their substance must
    // still hold"). CAPTURED on origin/main 45695d9, immediately before this ferry.

    /// GOLDEN: preset name → (stream hash, note-on count) over 32 bars. CAPTURED on origin/main 45695d9.
    private let mixPresetGolden32Bar: [String: (UInt64, Int)] = [
        "STRIDE WALK": (831820865381378157, 2328),
        "MIRROR WALK": (6489747601493623733, 3088),
        "PENDULUM": (6800816789757416157, 2064),
        "PING-PONG LEAD": (18098557554159599645, 3152),
        "DRUNKEN WALK": (8886565560488585693, 2320),
        "RANDOM GARDEN": (8632756865124567781, 3608),
        "OCTAVE COLUMN": (10401564588974730405, 5152),
        "KOTEKAN": (6473049491052627197, 4104),
        "FIVE AGAINST EIGHT": (10832974719036374229, 2520),
        "MIRRORED PITCH": (8941714960727834565, 1808),
        "FIFTH ABOVE": (1875793484491886317, 2576),
        "HELD BREATH": (4230917446120789245, 176),
        "STUTTER FILL": (3378533769270569309, 7216),
        "CALL AND HOLD": (5269097481486390693, 1680),
        "LONG TAIL": (16980282056334019437, 624),
        "GAPPED GROOVE": (3601599944325882293, 2056),
        "EARLY BLOOM": (3149805307358152269, 1072),
        "SCALE WALK": (12071472341642071061, 2576),
        "ARPEGGIO LADDER": (8737780371356034493, 8208),
        "BACKWARDS GLANCE": (8410249369364103757, 2568)
    ]
    func testEveryFactoryPresetRendersTheSameNoteStreamOver32BarsBeforeRestartChains() {
        XCTAssertEqual(EuclideousPresets.all.count, 20)
        for (name, make) in EuclideousPresets.all {
            guard let want = mixPresetGolden32Bar[name] else { XCTFail("no golden for \(name)"); continue }
            let got = mixPresetStreamHash(make(), bars: 32)
            XCTAssertEqual(got.ons, want.1, "\(name): note-on count over 32 bars")
            XCTAssertEqual(got.hash, want.0, "\(name): the note-on/off/velocity stream over 32 bars must be bit-identical before/after the restart-chain rewrite")
        }
    }

    /// LOCK GOLDENS (§14 test 1, second half): "the hit-by-hit riff ranks over four laps for each riff
    /// direction... with ADV HIT and with ADV STEP, on E(3,8) and E(5,8) with riff length 8." Euclideous has
    /// no live RAND/DRUNK (both hard-map to FWD at the model layer — `Models.swift`'s own
    /// `euclideousRiffDirResolved`), so only the 4 reachable directions are covered; reported per §17.9.
    /// `gridHits` (§ LANES GRID helpers above) with ranks 1…8 ascending turns "which riff step sounded" into
    /// a 0-based pool index identical to the riff rank minus 1 — exactly the "riff rank hit" this golden wants.
    private func lockGoldenRanks(pulses: Int, dir: RiffDir, adv: Bool) -> [Int] {
        let cycleLen = dir == .pingpong ? 16 : 8
        let beats = Double(cycleLen) * 0.5 * 4 + 0.5   // four laps + a touch of margin for the closing release
        var l = EuclidLine(target: 0, pulses: pulses, steps: 8, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true,
                            sourceMode: .midi, riffLength: 8)
        // §14 test 1 / §7.3, literal: "the LOCK goldens match melody chain 1 exactly" — this is that check:
        // `riffLock` itself is retired (§7), so the golden is now captured against a melody chain of [1].
        l.riffDir = dir; l.restartMelodyPasses = [1]; l.riffAdvanceStep = adv
        return gridHits(l, beats: beats).map { $0.idx + 1 }
    }
    /// GOLDEN: "pulses/direction/ADV" → riff ranks hit, in order. CAPTURED on origin/main 45695d9 under LOCK;
    /// §14 test 1 requires melody chain [1] to reproduce it exactly, verified by `lockGoldenRanks` above.
    /// NOTE on the two PING-PONG-ish labels: `RiffDir.pendulum.rawValue == "PING-PONG"` and
    /// `RiffDir.pingpong.rawValue == "PONG"` — the pre-existing persisted-string/display-label disagreement
    /// CLAUDE.md's own RIFF vocabulary note flags, not a bug introduced here.
    private let lockGolden: [String: [Int]] = [
        "3/FWD/HIT": [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1],
        "3/FWD/STEP": [1, 4, 7, 1, 4, 7, 1, 4, 7, 1, 4, 7, 1],
        "3/REV/HIT": [8, 7, 6, 8, 7, 6, 8, 7, 6, 8, 7, 6, 8],
        "3/REV/STEP": [8, 5, 2, 8, 5, 2, 8, 5, 2, 8, 5, 2, 8],
        "3/PING-PONG/HIT": [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1],
        "3/PING-PONG/STEP": [1, 4, 7, 1, 4, 7, 1, 4, 7, 1, 4, 7, 1],
        "3/PONG/HIT": [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1],
        "3/PONG/STEP": [1, 4, 7, 1, 4, 7, 1, 4, 7, 1, 4, 7, 1, 4, 7, 1, 4, 7, 1, 4, 7, 1, 4, 7, 1],
        "5/FWD/HIT": [1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1],
        "5/FWD/STEP": [1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1],
        "5/REV/HIT": [8, 7, 6, 5, 4, 8, 7, 6, 5, 4, 8, 7, 6, 5, 4, 8, 7, 6, 5, 4, 8],
        "5/REV/STEP": [8, 6, 4, 3, 1, 8, 6, 4, 3, 1, 8, 6, 4, 3, 1, 8, 6, 4, 3, 1, 8],
        "5/PING-PONG/HIT": [1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1],
        "5/PING-PONG/STEP": [1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1],
        "5/PONG/HIT": [1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1],
        "5/PONG/STEP": [1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1, 3, 5, 6, 8, 1]
    ]
    func testLockGoldenRiffRanksBeforeRestartChains() {
        for pulses in [3, 5] {
            for dir in [RiffDir.forward, .reverse, .pendulum, .pingpong] {
                for adv in [false, true] {
                    let key = "\(pulses)/\(dir.rawValue)/\(adv ? "STEP" : "HIT")"
                    guard let want = lockGolden[key] else { XCTFail("no golden for \(key)"); continue }
                    let got = lockGoldenRanks(pulses: pulses, dir: dir, adv: adv)
                    XCTAssertEqual(got, want, "\(key): riff ranks must match exactly before/after the restart-chain rewrite")
                }
            }
        }
    }

    // MARK: - RIFF WALK (ferry 2026-10-19) §11 test 1 — golden renders captured BEFORE this ferry's engine
    // change (ADVANCE EVERY, the longer TIE bound, REPEAT). The 20-preset 32-bar golden and the LOCK-ranks
    // golden just above already cover "preset sound" and "the walk's basic column order" respectively (both
    // use EVERY implicitly == 1 and no REPEAT, so they remain valid regression nets for this ferry too,
    // unchanged). What's new here: the combo matrix (direction × ADV × STRIDE × LEN × SHIFT) the ferry's
    // test 1 names, and ON REST's behaviour on an actual rest (SKIP/FILL/TIE), captured as FOLDED hashes
    // (one meta-hash per lane across all 64 combos, not 64 separate literals) to keep this file's size sane
    // — a regression here is re-run with per-combo output to isolate which combo changed.

    /// One lane's full note-wire stream (on + off + velocity), hashed the same way `mixPresetStreamHash`
    /// hashes a whole preset. Identity ranks (`[1...8]`) mean the stream alone already encodes which
    /// column/rank sounded and for how long — no separate column capture needed.
    private func riffWalkStreamHash(_ line: EuclidLine, beats: Double, ranks: [Int] = [1, 2, 3, 4, 5, 6, 7, 8]) -> (hash: UInt64, ons: Int) {
        let e = RecordingEmitter()
        mixRun(mixBox(line, ranks: ranks), beats: beats, into: e)
        assertNothingLeftSounding(e)
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        for ev in e.events where ev.cable == 1 {
            mix(UInt64(bitPattern: ev.sample)); mix(UInt64(ev.status)); mix(UInt64(ev.note)); mix(UInt64(ev.vel))
        }
        return (h, e.ons.filter { $0.cable == 1 }.count)
    }
    /// The harness lane (§11 preamble): 8 steps of 1/8, hits on 1, 3, 5, 6, 8, GATE 50%, both chains FREE.
    private func riffWalkHarnessLine(dir: RiffDir, adv: Bool, stride: Int, len: Int, shift: Int, onRest: EuclidRiffOnRest = .skip) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 5, steps: 8, gate: 0.5, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: len)
        l.customHits = [true, false, true, false, true, true, false, true]
        l.riffDir = dir; l.riffAdvanceStep = adv; l.riffStride = stride; l.riffRotate = shift; l.riffOnRest = onRest
        return l
    }
    /// The second lane (§11 test 1): 8 steps of 1/8, hits on 1, 4, 7 only, otherwise identical.
    private func riffWalkSecondLine(dir: RiffDir, adv: Bool, stride: Int, len: Int, shift: Int, onRest: EuclidRiffOnRest = .skip) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 3, steps: 8, gate: 0.5, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: len)
        l.customHits = [true, false, false, true, false, false, true, false]
        l.riffDir = dir; l.riffAdvanceStep = adv; l.riffStride = stride; l.riffRotate = shift; l.riffOnRest = onRest
        return l
    }
    /// Folds every (dir, adv, stride, len, shift) combo's own stream hash into one meta-hash, over 8 passes
    /// (lap = 8 steps × 0.5 beats/step = 4 beats; 8 passes + a touch of margin for the closing release).
    private func riffWalkComboMetaHash(_ line: (RiffDir, Bool, Int, Int, Int) -> EuclidLine) -> (hash: UInt64, ons: Int) {
        var h: UInt64 = 0xcbf29ce484222325
        var totalOns = 0
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        let beats = 8 * 4.0 + 0.5
        for dir in [RiffDir.forward, .reverse, .pendulum, .pingpong] {
            for adv in [false, true] {
                for stride in [1, 3] {
                    for len in [8, 5] {
                        for shift in [0, 2] {
                            let got = riffWalkStreamHash(line(dir, adv, stride, len, shift), beats: beats)
                            mix(got.hash); mix(UInt64(got.ons)); totalOns += got.ons
                        }
                    }
                }
            }
        }
        return (h, totalOns)
    }
    /// GOLDEN: (meta-hash, total note-on count) across all 64 combos, one entry per lane. CAPTURED on
    /// origin/main a49907b, immediately before this ferry's engine change.
    /// RECAPTURED (RIFF WINDOW ferry, 2026-10-21): SHIFT now wraps at the riff's 8 columns instead of at
    /// LENGTH, so the `len: 5, shift: 2` combos in this matrix read different columns than before — an
    /// intentional sound change (the combination this ferry fixes), not a regression. Note-on COUNTS are
    /// unchanged (same hits land, just on different pitches); only the hashes moved.
    private let riffWalkComboGolden: [String: (UInt64, Int)] = [
        "harness": (12069258775816225389, 2624),
        "second": (2104906034728872053, 1600)
    ]
    func testRiffWalkComboMatrixBeforeAdvanceEvery() {
        let harness = riffWalkComboMetaHash { riffWalkHarnessLine(dir: $0, adv: $1, stride: $2, len: $3, shift: $4) }
        let second = riffWalkComboMetaHash { riffWalkSecondLine(dir: $0, adv: $1, stride: $2, len: $3, shift: $4) }
        guard let wantHarness = riffWalkComboGolden["harness"], let wantSecond = riffWalkComboGolden["second"] else {
            XCTFail("CAPTURE: harness=\(harness) second=\(second)"); return
        }
        XCTAssertEqual(harness.0, wantHarness.0); XCTAssertEqual(harness.1, wantHarness.1)
        XCTAssertEqual(second.0, wantSecond.0); XCTAssertEqual(second.1, wantSecond.1)
    }
    /// GOLDEN: ON REST SKIP/FILL/TIE on a riff with real rests (ranks [5, 0, 3, 0, 0, 7, 0, 2]), harness
    /// lane, FWD/ADV HIT/STRIDE 1/LEN 8/SHIFT 0, over 8 passes. CAPTURED on origin/main a49907b.
    private let riffWalkOnRestGolden: [String: (UInt64, Int)] = [
        "SKIP": (5198820605517400049, 21),
        "FILL": (5198820605517400049, 21),   // identical to SKIP today — confirms FILL contributes no riff pitch of its own (MIX ferry Q1)
        "TIE": (2358594927737065278, 21)
    ]
    func testRiffWalkOnRestBeforeAdvanceEveryAndRepeat() {
        let beats = 8 * 4.0 + 0.5
        let restRanks = [5, 0, 3, 0, 0, 7, 0, 2]
        for onRest in [EuclidRiffOnRest.skip, .fill, .tie] {
            let line = riffWalkHarnessLine(dir: .forward, adv: false, stride: 1, len: 8, shift: 0, onRest: onRest)
            let got = riffWalkStreamHash(line, beats: beats, ranks: restRanks)
            guard let want = riffWalkOnRestGolden[onRest.rawValue] else {
                XCTFail("CAPTURE \(onRest.rawValue): \(got)"); continue
            }
            XCTAssertEqual(got.hash, want.0, "\(onRest.rawValue): stream must match before/after this ferry")
            XCTAssertEqual(got.ons, want.1, "\(onRest.rawValue): note-on count must match before/after this ferry")
        }
    }

    /// §11 test 2: the walk, pure (`euclideousRiffColumn`/`euclideousRiffWalkStep`, EVERY 1). Columns for
    /// ordinals 0...(N-1), 1-indexed, compared against the ferry's own literal sequences.
    func testRiffWalkColumnSequencesMatchTheFerrysWorkedExamples() {
        func cols(_ dir: RiffDir, length: Int, stride: Int = 1, shift: Int = 0, count: Int) -> [Int] {
            (0..<count).map { euclideousRiffColumn(ordinal: Int64($0), every: 1, direction: dir, length: length, stride: stride, shift: shift) + 1 }
        }
        XCTAssertEqual(cols(.forward, length: 8, count: 8), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(cols(.reverse, length: 8, count: 8), [8, 7, 6, 5, 4, 3, 2, 1])
        XCTAssertEqual(cols(.reverse, length: 8, shift: 2, count: 8), [2, 1, 8, 7, 6, 5, 4, 3])
        XCTAssertEqual(cols(.forward, length: 5, stride: 3, count: 5), [1, 4, 2, 5, 3], "Paul's own worked example")
        XCTAssertEqual(cols(.pendulum, length: 4, count: 6), [1, 2, 3, 4, 3, 2])
        XCTAssertEqual(cols(.pingpong, length: 4, count: 8), [1, 2, 3, 4, 4, 3, 2, 1])
        XCTAssertEqual(cols(.forward, length: 8, shift: 5, count: 8), [6, 7, 8, 1, 2, 3, 4, 5])
        XCTAssertEqual(cols(.forward, length: 8, stride: 2, count: 4), [1, 3, 5, 7])
        XCTAssertEqual(cols(.pingpong, length: 8, stride: 3, count: 16), [1, 4, 7, 7, 4, 1, 3, 6, 8, 5, 2, 2, 5, 8, 6, 3])
        // P (the walk's period, §7.1 — reusing the FX ferry's own function).
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .pendulum, length: 8, stride: 1), 14)
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .pingpong, length: 8, stride: 1), 16)
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .forward, length: 8, stride: 2), 4)
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .forward, length: 1, stride: 1), 1)
    }

    /// §11 test 3: EVERY's footers (Router), the harness lane (hits 1, 3, 5, 6, 8), both chains FREE.
    /// `gridHits` already gives (beat, column) under identity ranks — column+1 is the footer's own number.
    /// A generous `beats` window is captured and then truncated to the wanted count — the render engine's
    /// own fixed-size processing windows don't align to this lane's 0.5-beat hit grid, so trying to land
    /// `beats` exactly between the last wanted hit and the first unwanted one is fragile; comparing a
    /// prefix is not.
    func testRiffWalkEveryFootersMatchTheFerrysWorkedExamples() {
        func footers(every: Int, adv: Bool, shift: Int = 0, passes: Int, want: Int) -> [Int] {
            var l = riffWalkHarnessLine(dir: .forward, adv: adv, stride: 1, len: 8, shift: shift)
            l.riffAdvanceEvery = every
            return Array(gridHits(l, beats: Double(passes) * 4.0 + 0.5).map { $0.idx + 1 }.prefix(want))
        }
        XCTAssertEqual(footers(every: 1, adv: false, passes: 4, want: 20), [1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4])
        XCTAssertEqual(footers(every: 2, adv: false, passes: 4, want: 20), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 1, 1, 2, 2])
        XCTAssertEqual(footers(every: 3, adv: false, passes: 4, want: 20), [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7])
        XCTAssertEqual(footers(every: 2, adv: true, shift: 5, passes: 4, want: 20), [6, 7, 8, 8, 1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 1, 2, 3, 4, 4, 5])
    }

    /// §11 test 4: EVERY with restarts (Router).
    func testRiffWalkEveryWithMelodyRestarts() {
        var a = riffWalkHarnessLine(dir: .forward, adv: false, stride: 1, len: 8, shift: 0)
        a.riffAdvanceEvery = 2; a.restartMelodyPasses = [1]
        XCTAssertEqual(Array(gridHits(a, beats: 4 * 4.0 + 0.5).map { $0.idx + 1 }.prefix(20)), Array(repeating: [1, 1, 2, 2, 3], count: 4).flatMap { $0 })

        var b = riffWalkHarnessLine(dir: .forward, adv: false, stride: 1, len: 8, shift: 0)
        b.riffAdvanceEvery = 2; b.restartMelodyPasses = [2, 1, 1]
        XCTAssertEqual(Array(gridHits(b, beats: 6 * 4.0 + 0.5).map { $0.idx + 1 }.prefix(30)),
                       [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 1, 1, 2, 2, 3, 1, 1, 2, 2, 3, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5])

        var c = EuclidLine(target: 0, pulses: 3, steps: 7, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: 8)
        c.restartRhythmBars = [1]; c.riffAdvanceEvery = 2
        let lapBeats7 = 3.5   // 7 steps of 1/8
        XCTAssertEqual(Array(gridHits(c, beats: 6 * lapBeats7 + 0.5).map { $0.idx + 1 }.prefix(18)),
                       [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 1, 1])
    }

    /// §11 test 8: REPEAT (Router). Ranks by column (0 = rest), every step a hit (pulses: n, steps: n).
    private func repeatLine(ranks: [Int], adv: Bool = false, every: Int = 1, invert: Bool = false, transpose: Int = 0, melody: [UInt8]? = nil) -> (EuclidLine, [Int]) {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: 8)
        l.riffOnRest = .repeatLast; l.riffAdvanceStep = adv; l.riffAdvanceEvery = every
        l.riffInvert = invert; l.melodyTranspose = transpose
        if let melody { l.restartMelodyPasses = melody }
        return (l, ranks)
    }
    /// `ranks`' OWN reverse lookup (valid whenever its non-zero entries are each unique, true of every §11
    /// test-8 example) turns a measured RANK (gridHits' idx+1) back into the COLUMN whose written rank it
    /// was — the metric the ferry's own test-8 sequences are given in ("the columns played").
    /// A generous `beats` window is captured and truncated to `want` events — the render engine's own
    /// fixed-size processing windows don't align to this lane's hit grid, so trying to land `beats` exactly
    /// between the last wanted hit and the first unwanted one is fragile; comparing a prefix is not.
    private func gridHitsColumns(_ line: EuclidLine, ranks: [Int], beats: Double, want: Int, startBeat: Double = 0) -> [Int] {
        Array(gridHits(line, ranks: ranks, beats: beats, startBeat: startBeat).map { (ranks.firstIndex(of: $0.idx + 1) ?? -1) + 1 }.prefix(want))
    }
    func testRepeatPlaysTheNearestEarlierNonRestColumn() {
        let (l, r) = repeatLine(ranks: [5, 0, 3, 0, 0, 7, 0, 2])
        XCTAssertEqual(gridHitsColumns(l, ranks: r, beats: 4.5, want: 8), [1, 1, 3, 3, 3, 6, 6, 8], "every pass")
    }
    func testRepeatPassZeroSilentThenBorrowsAcrossThePassBoundary() {
        let (l, r) = repeatLine(ranks: [0, 4, 0, 0, 6, 0, 0, 0])
        // pass 0: column 1 has nothing to borrow yet (–, no event at all); 3 and 4 borrow column 2 (rank 4);
        // 6, 7, 8 borrow column 5 (rank 6). pass 1: column 1 now borrows column 5 FROM pass 0.
        XCTAssertEqual(gridHitsColumns(l, ranks: r, beats: 8.5, want: 15), [2, 2, 2, 5, 5, 5, 5, 5, 2, 2, 2, 5, 5, 5, 5])
    }
    func testRepeatWithMelodyOneNeverCarriesAcrossTheRestart() {
        let (l0, r0) = repeatLine(ranks: [0, 4, 0, 0, 6, 0, 0, 0], melody: [1])
        // melody 1 restarts the riff ordinal every pass, so column 1 is silent (nothing to borrow) on EVERY
        // pass, not just the first — pass 1 looks exactly like pass 0, not like the FREE-melody test above.
        XCTAssertEqual(gridHitsColumns(l0, ranks: r0, beats: 8.5, want: 14), [2, 2, 2, 5, 5, 5, 5, 2, 2, 2, 5, 5, 5, 5])
    }
    func testRepeatUnderAdvStepReadsTheHitsOnlyNotEveryStep() {
        let (l, r) = repeatLine(ranks: [5, 6, 7, 0, 2, 3, 4, 8], adv: true)
        var line = l
        line.customHits = [true, false, false, true, false, false, true, false]   // hits on 1, 4, 7
        XCTAssertEqual(gridHitsColumns(line, ranks: r, beats: 4.5, want: 3), [1, 1, 7], "the hit on column 4 (a rest) plays column 1's note, not column 3's")
    }
    func testRepeatEveryTwoGroupsPairsOfHits() {
        let (l, r) = repeatLine(ranks: [4, 0, 6, 1, 2, 3, 5, 7], every: 2)
        XCTAssertEqual(gridHitsColumns(l, ranks: r, beats: 8.5, want: 16), [1, 1, 1, 1, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8])
    }
    func testRepeatAcrossARhythmRestartDoesNotAssumeARegularLap() {
        var l = EuclidLine(target: 0, pulses: 3, steps: 7, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: 8)
        l.riffOnRest = .repeatLast; l.riffAdvanceStep = true; l.restartRhythmBars = [1]
        l.customHits = [true, false, true, true, false, true, true]   // hits on 1, 3, 4, 6, 7
        let r = [0, 6, 0, 2, 3, 4, 7, 8]
        let hits = gridHits(l, ranks: r, beats: 5.6)
        // beats 4.0 and 5.0 are the rhythm restart's own columns 1 and 3 (both rests) — both must borrow
        // column 8 (the hit at beat 3.5, before the restart), not column 2 (what an unbroken-lap lookback
        // would wrongly see at the step-3 position).
        for (beat, idx) in hits where beat == 4.0 || beat == 5.0 {
            let col = (r.firstIndex(of: idx + 1) ?? -1) + 1
            XCTAssertEqual(col, 8, "beat \(beat): must borrow column 8 from before the restart, not column 2")
        }
    }
    func testRepeatWithEveryRankARestIsSilentWithNoLookback() {
        let (l, r) = repeatLine(ranks: [0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertTrue(gridHits(l, ranks: r, beats: 4.5).isEmpty, "every hit silent at once, no search")
    }
    func testRepeatDeterminismStartingMidPass() {
        let (l, r) = repeatLine(ranks: [0, 4, 0, 0, 6, 0, 0, 0])
        let e = RecordingEmitter()
        mixRun(mixBox(l, ranks: r), beats: 4.5, into: e, startBeat: 4.0)
        assertNothingLeftSounding(e)
        let firstRank = e.ons.filter { $0.cable == 1 }.first.flatMap { ev in gridPool.firstIndex(of: ev.note) }.map { $0 + 1 }
        let firstCol = firstRank.map { (r.firstIndex(of: $0) ?? -1) + 1 }
        XCTAssertEqual(firstCol, 5, "pass 1's own first hit (column 1, a rest) plays column 5 — exactly as from beat 0")
    }
    func testRepeatAtLegatoSendsNoNewNoteOnForTheHeldPitch() {
        let (l0, r0) = repeatLine(ranks: [5, 0, 3, 0, 0, 7, 0, 2])
        var l = l0; l.gate = 1.0
        let e = RecordingEmitter()
        mixRun(mixBox(l, ranks: r0), beats: 4.5, into: e)
        assertNothingLeftSounding(e)
        // At GATE 100% consecutive same-pitch hits legato-merge into one held note, so pass 0's own columns
        // [1,1,3,3,3,6,6,8] (4 pitch RUNS) produce exactly 4 note-ons, not 8 — capture exactly that many so
        // pass 1's own first (also rank-5) note-on can't sneak into the count.
        let pass0 = Array(e.ons.filter { $0.cable == 1 }.prefix(4))
        let onsRank5 = pass0.filter { gridPool.firstIndex(of: $0.note) == 4 }
        XCTAssertEqual(onsRank5.count, 1, "one held note, not three separate note-ons")
    }
    /// §11 test 5: TIE with EVERY. Every step a hit, ranks [5, 0, 3, 6, 2, 4, 7, 1] by column, EVERY 2, ADV
    /// HIT, ON REST TIE. Hits 1 and 2 both read column 1 (rank 5, same pitch — legato merges them into one
    /// held note); hits 3 and 4 read the rest. Hit 2's note lasts through both to hit 5 (a genuinely
    /// different pitch, column 3/rank 3); compared against the SAME run under SKIP, where that note ends at
    /// its own normal gate length instead.
    func testTieWithEveryHoldsThroughTheRestRunToTheNextRealHit() {
        let ranks = [5, 0, 3, 6, 2, 4, 7, 1]
        func rank5NoteOff(onRest: EuclidRiffOnRest) -> Int64? {
            var l = EuclidLine(target: 0, pulses: 8, steps: 8, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: 8)
            l.riffOnRest = onRest; l.riffAdvanceEvery = 2
            let e = RecordingEmitter()
            mixRun(mixBox(l, ranks: ranks), beats: 4.5, into: e)
            assertNothingLeftSounding(e)
            // hit 1 ALSO reads column 1/rank 5 but is unrelated to the tie (nothing precedes it) — below
            // GATE 100% consecutive same-pitch hits don't legato-merge, so hit 2's own note is the SECOND
            // note-on/off pair for this pitch, not the first.
            return mixNotes(e, gridPool[4]).dropFirst().first?.off
        }
        guard let tieOff = rank5NoteOff(onRest: .tie), let skipOff = rank5NoteOff(onRest: .skip) else {
            return XCTFail("expected a second note-off for the rank-5 pitch (hit 2's own) under both ON REST modes")
        }
        // The actual tied duration is `nextHitGapBeats + gate × tieExt` (euclideousPitchGateBeats), not raw
        // tieExt — tieExt here is 2 rest-ticks × 0.5 beats/tick = 1.0 beat, so TIE's note-off lands at hit
        // 2's own onset (0.5) + nextHitGapBeats (0.5) + gate×1.0 ≈ 1.9 at the lane's default gate, i.e. right
        // up to (not past) hit 5's own onset (beat 2.0). SKIP has no tieExt, so it releases at its own plain
        // gate length, well short of that.
        XCTAssertGreaterThanOrEqual(Double(tieOff) / 24_000, 1.85, "TIE: held through hits 3 and 4's rests, up to hit 5's own onset")
        XCTAssertLessThan(Double(skipOff) / 24_000, 1.0, "SKIP: released at hit 2's own gate length, well before hit 5")
    }
    /// §11 test 6: a long PING tie. PING, every step a hit, ranks [3, 0, 0, 0, 0, 0, 0, 0], ADV HIT, EVERY 4,
    /// ON REST TIE. P = 16 for PING at LEN 8, so hits 1-4 (ordinals 0-3, all walk step 0) read column 1 (the
    /// ONLY real column); hits 5-60 (walk steps 1-14) read rests — 56 hits, exactly the scenario §5.5 widened
    /// the TIE bound to cover (P x EVERY = 64, where the old <=8-hit bound could never have reached); hits
    /// 61-64 (walk step 15, PING's own reflection back to column 0) read column 1 again. Hit 4's own note
    /// must be held far past where the OLD bound could ever have reached (its exact note-off depends on the
    /// lane's GATE, which scales the tie extension — see `euclideousPitchGateBeats` — so this checks "far
    /// beyond the old bound," not an exact beat).
    func testLongPingTieReachesAcrossFiftySixRestHits() {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: 8)
        l.riffDir = .pingpong; l.riffAdvanceEvery = 4; l.riffOnRest = .tie
        let ranks = [3, 0, 0, 0, 0, 0, 0, 0]
        let e = RecordingEmitter()
        mixRun(mixBox(l, ranks: ranks), beats: 32.5, into: e)
        assertNothingLeftSounding(e)
        // hits 1-3 ALSO read column 1/rank 3 but (below GATE 100%, no legato merge) each gets its own short
        // note — hit 4's is the FOURTH note-on/off pair for this pitch, and it's the one whose own TIE
        // lookahead must reach across the 56-hit rest run.
        guard let off = mixNotes(e, gridPool[2]).dropFirst(3).first?.off else {   // rank 3 -> pool index 2
            return XCTFail("expected a fourth note-off for the rank-3 pitch (hit 4's own)")
        }
        // The actual tied duration is `nextHitGapBeats + gate × tieExt` (euclideousPitchGateBeats), not raw
        // tieExt, so the exact note-off depends on the lane's own default GATE — not pinned to an exact
        // value here. What IS robust: the OLD bound (<= riffLength = 8 rest-hits, i.e. tieExt <= 4.0 beats)
        // could reach AT MOST hit 4's own onset (1.5) + nextHitGapBeats (0.5) + gate × 4.0, comfortably under
        // beat 6 at any plausible gate. The new P x EVERY (= 64) bound reaching deep into the 56-hit rest run
        // (tieExt up to 28.0 beats) must land far past that, nowhere near hit 61's own onset (beat 30) either
        // (since gate < 1 scales tieExt down) — asserting a generous, OLD-bound-busting floor rather than a
        // precise but gate-dependent exact value.
        XCTAssertGreaterThan(Double(off) / 24_000, 15.0, "the tie must reach far beyond what the OLD <=8-hit bound could ever produce (max ~6 beats)")
    }
    /// §11 test 10: REPEAT's own NOTE VIEW telemetry. 8a's ranks ([5, 0, 3, 0, 0, 7, 0, 2]); hit 2 posts one
    /// event whose column is column 2 (the rest, 1-based "2" = 0-based index 1) and whose rank is 5 (column
    /// 1's written rank), with hasRiffNote true.
    func testRepeatPostsNoteViewTelemetryAtTheRestColumnWithTheRepeatedRank() {
        let (l, r) = repeatLine(ranks: [5, 0, 3, 0, 0, 7, 0, 2])
        let router = Router()
        var diag = KernelDiag()
        let pool = chord([48, 50, 52, 53, 55, 57, 59, 60])
        let box = mixBox(l, ranks: r)
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        let e = RecordingEmitter()
        while beat < 1.0 {   // hits 1 (beat 0.0) and 2 (beat 0.5) both land inside this window
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        let events = router.drainEuclideousNoteViewEvents()[0]
        guard events.count >= 2 else { return XCTFail("expected at least 2 NOTE VIEW events (hit 1, hit 2's REPEAT)") }
        let repeatEvent = events[1]
        XCTAssertEqual(repeatEvent.column, 1, "the hit's own column (the rest), 0-based")
        XCTAssertEqual(repeatEvent.rank, 5, "column 1's written rank")
        XCTAssertTrue(repeatEvent.hasRiffNote)
    }

    /// §11 test 14 (a slice): the readout and never-play set, pure (`euclideousRiffReadout`/
    /// `euclideousRiffReadoutText`), against two of §7.8's own worked examples on the harness lane
    /// (hits 1, 3, 5, 6, 8), both chains FREE, ADV HIT.
    func testRiffReadoutMatchesTwoOfTheFerrysWorkedExamples() {
        let harnessBuf = [true, false, true, false, true, true, false, true]   // hits 1, 3, 5, 6, 8
        func readout(riffDir: RiffDir, length: Int, stride: Int) -> (EuclideousRiffReadout?, String) {
            let r = euclideousRiffReadout(buf: harnessBuf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, chains: .off,
                                          legacySpanBeats: 0, advanceStep: false, riffDir: riffDir, stride: stride,
                                          length: length, shift: 0, every: 1, seed: 0)
            return (r, euclideousRiffReadoutText(r, overBudget: r == nil))
        }
        // "FWD, STRIDE 2, ADV HIT: 1 3 5 7; 4 NEVER PLAY (2, 4, 6, 8)." (the "LINES UP EVERY n PASSES"
        // wording was removed 2026-10-22 — only the NEVER PLAY count still shows.)
        let (strideTwo, strideTwoText) = readout(riffDir: .forward, length: 8, stride: 2)
        XCTAssertEqual(strideTwo?.period, 4)
        XCTAssertEqual(strideTwo?.neverPlay, [1, 3, 5, 7], "0-based columns for 1-based 2, 4, 6, 8")
        XCTAssertEqual(strideTwoText, " · 4 NEVER PLAY")
        // "FWD, LEN 5, STRIDE 3, ADV HIT: 1 4 2 5 3." — nothing never plays, so the readout is now empty.
        let (lenFive, lenFiveText) = readout(riffDir: .forward, length: 5, stride: 3)
        XCTAssertEqual(lenFive?.period, 1)
        XCTAssertEqual(lenFive?.neverPlay, [], "LEN 5 STRIDE 3 visits every one of its own 5 columns")
        XCTAssertEqual(lenFiveText, "")
    }

    /// §11 test 18: the pure layout function at the reference (contentAreaH 202, fullWidth 338.5) and at a
    /// narrower 300pt width with the same zones, per the ferry's own §1.6 worked numbers.
    func testRiffTabLayoutAtReferenceAndNarrower() {
        let ref = euclideousRiffTabLayout(contentAreaH: 202, fullWidth: 338.5)
        // the real contentAreaH/patternBlockH split gives 118/80 (not the ferry's own screenshot-derived
        // 124/80) — reported, not hand-fitted to match; everything below is this code's own real geometry.
        XCTAssertEqual(ref.rowAHeight, 76, accuracy: 0.01)
        XCTAssertEqual(ref.directionRowHeight, 34, accuracy: 0.01)
        XCTAssertEqual(ref.rightColumnWidth, 244.5, accuracy: 0.01)
        // Floors ferry (2026-10-23): 4 buttons over 3 gaps now (PENDULUM removed 2026-10-22; was ÷5 over 4 gaps, stale since then).
        XCTAssertEqual(ref.directionButtonWidth, 58.125, accuracy: 0.01)
        XCTAssertEqual(ref.onRestButtonWidth, 88.833, accuracy: 0.001, "three buttons (FILL left ON REST): (338.5 − 60 − 3·4) ÷ 3")
        XCTAssertEqual(ref.valueStepperWidth, 81.625, accuracy: 0.001)
        XCTAssertEqual(ref.hitStepButtonWidth, 95.25, accuracy: 0.01, "label 60 + gap + EVERY 76 + gap + HIT + gap + STEP = fullWidth, 3 gaps total")
        // §0.2's own discrepancy, confirmed numerically: the ferry's reference arithmetic assumes upperH
        // 124 (giving row A 82, exactly its own floor); the REAL contentAreaH(202)/patternBlockH(80) split
        // gives upperH 118, row A 76 — 6pt UNDER the 82 floor even at the reference. Reported, not silently
        // reconciled by hand-fitting a different constant.
        XCTAssertTrue(ref.underFloor, "the real formula puts row A at 76, under its own 82 floor, even at the reference — see §0.2's discrepancy")

        let narrow = euclideousRiffTabLayout(contentAreaH: 202, fullWidth: 300)
        XCTAssertEqual(narrow.directionButtonWidth, (300 - 90 - 4 - 12) / 4, accuracy: 0.01)
        XCTAssertEqual(narrow.hitStepButtonWidth, 76, accuracy: 0.01)
        XCTAssertEqual(narrow.onRestButtonWidth, 76, accuracy: 0.01, "NOTES TAB ferry: at a 300 pt content width the three ON REST buttons are 76 wide")
        XCTAssertEqual(narrow.valueStepperWidth, 72, accuracy: 0.01)
        XCTAssertTrue(narrow.underFloor, "direction buttons fall under the 40pt floor at 300pt width")
    }

    // MARK: - MIX TAB (ferry 2026-10-18) §9.6/§9.7 — every pitch carries its OWN gate; legato is per LAYER

    private func mixBox(_ line: EuclidLine, ranks: [Int] = [5, 0, 0, 0, 0, 0, 0, 0], monoOnA: Bool = false) -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks)
        c.paramsA.euclidLines = [line]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
        if monoOnA { sc.cells[0][0] = Cell(machineID: "orange", buses: [.a]) }
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        if monoOnA { st.monoMask = 0b0001; st.monoPriority = [0, 0, 0, 0] }
        st.euclideousNoteSource = .midi
        return SnapshotBuilder.build(from: st)
    }
    /// `run()` with the test-only mask seam. 120 BPM, 48 kHz: one beat = 24 000 samples.
    private func mixRun(_ box: SnapshotBox, beats: Double, into e: RecordingEmitter, maskOn: Bool = false, startBeat: Double = 0) {
        let pool = chord([48, 50, 52, 53, 55, 57, 59, 60])   // rank 1 = 48 … rank 5 = 55 … rank 8 = 60
        let router = Router(); router.euclideousMaskEnabledForTests = maskOn
        var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = startBeat, ts = 0.0
        while beat < startBeat + beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
    }
    /// Every sounding of `note` on cable 1: its note-on sample and the sample of the note-off that closes it.
    private func mixNotes(_ e: RecordingEmitter, _ note: UInt8) -> [(on: Int64, off: Int64?)] {
        var out: [(on: Int64, off: Int64?)] = []
        for ev in e.events where ev.cable == 1 && ev.note == note {
            if ev.status == 0x90 { out.append((ev.sample, nil)) }
            else if ev.status == 0x80, let i = out.lastIndex(where: { $0.off == nil }) { out[i].off = ev.sample }
        }
        return out
    }
    private func mixLength(_ e: RecordingEmitter, _ note: UInt8, _ nth: Int = 0) -> Int64? {
        let n = mixNotes(e, note); guard nth < n.count, let off = n[nth].off else { return nil }
        return off - n[nth].on
    }
    /// One lane: `pulses`-of-4 hits at 1/4 rate (one step = one beat), the riff always reading rank 5 (55), the lit mask on rank 1 (48).
    private func mixLine(pulses: Int, gate: Double, notesGate: Double?, vel: Int = 90, notesVelocity: Int? = nil, litNotes: UInt8 = 0b0000_0001,
                         riffOn: Bool = true, notesOn: Bool = true, mask: EuclidLineMask? = nil) -> EuclidLine {
        EuclidLine(target: 0, pulses: pulses, steps: 4, gate: gate, velocityAbsolute: vel, rate: .r1_4, useRiff: true, litNotes: litNotes, riffOn: riffOn,
                   mask: mask, sourceMode: .midi, riffLength: 1, notesOn: notesOn, notesGate: notesGate, notesVelocity: notesVelocity)
    }

    // §9.6 — on one hit the riff pitch and the lit notes end at their OWN gates (gap to the next hit = 4 beats = 96 000 samples).
    func testMixRiffPitchAndLitNotesEndAtTheirOwnGates() {
        let e = RecordingEmitter()
        mixRun(mixBox(mixLine(pulses: 1, gate: 0.5, notesGate: 0.25)), beats: 5, into: e)
        XCTAssertEqual(Double(mixLength(e, 55) ?? 0), 0.5 * 96_000, accuracy: 6, "the riff pitch ends at GATE (50% of the gap)")
        XCTAssertEqual(Double(mixLength(e, 48) ?? 0), 0.25 * 96_000, accuracy: 6, "the lit note ends at ITS gate (25%)")
        assertNothingLeftSounding(e)
        // not parted (notesGate nil): both layers still read the lane's GATE — exactly the old behaviour
        let old = RecordingEmitter()
        mixRun(mixBox(mixLine(pulses: 1, gate: 0.5, notesGate: nil)), beats: 5, into: old)
        XCTAssertEqual(Double(mixLength(old, 55) ?? 0), 0.5 * 96_000, accuracy: 6); XCTAssertEqual(Double(mixLength(old, 48) ?? 0), 0.5 * 96_000, accuracy: 6, "nil ⇒ the lit note follows GATE")
        // TOP and TOP2 are notes-layer pitches too
        let top = RecordingEmitter()
        var tl = mixLine(pulses: 1, gate: 0.5, notesGate: 0.25, litNotes: 0); tl.topLit = true
        mixRun(mixBox(tl), beats: 5, into: top)
        XCTAssertEqual(Double(mixLength(top, 60) ?? 0), 0.25 * 96_000, accuracy: 6, "TOP (60) takes the notes gate")
    }
    // §9.6 — per-layer LEGATO: a notes gate of exactly 100% holds the lit notes while the riff retriggers at 60%, and the reverse.
    func testMixLegatoIsPerLayerInBothDirections() {
        func ons(_ g: Double, _ ng: Double) -> (riff: Int, lit: Int) {
            let e = RecordingEmitter(); mixRun(mixBox(mixLine(pulses: 4, gate: g, notesGate: ng)), beats: 4.5, into: e)
            assertNothingLeftSounding(e)
            return (mixNotes(e, 55).count, mixNotes(e, 48).count)
        }
        let a = ons(0.6, 1.0); XCTAssertEqual(a.lit, 1, "notes gate 100%: the lit note is struck once and HELD across every hit"); XCTAssertGreaterThanOrEqual(a.riff, 4, "…while the riff retriggers at 60%")
        let b = ons(1.0, 0.6); XCTAssertEqual(b.riff, 1, "riff gate 100%: the riff note is held"); XCTAssertGreaterThanOrEqual(b.lit, 4, "…while the lit note retriggers")
        let c = ons(1.0, 1.0); XCTAssertEqual(c.riff, 1); XCTAssertEqual(c.lit, 1)
        let d = ons(0.6, 0.6); XCTAssertGreaterThanOrEqual(d.riff, 4); XCTAssertGreaterThanOrEqual(d.lit, 4)
        let e99 = ons(0.99, 0.99); XCTAssertGreaterThanOrEqual(e99.riff, 4, "99% is not legato"); XCTAssertGreaterThanOrEqual(e99.lit, 4)
    }
    // §9.6 — a collision (riff and a lit note on the SAME pitch) sounds once, at the riff's gate and velocity.
    func testMixCollisionSoundsOnceAtTheRiffsGateAndVelocity() {
        let e = RecordingEmitter()
        mixRun(mixBox(mixLine(pulses: 1, gate: 0.5, notesGate: 0.25, vel: 90, notesVelocity: 40, litNotes: 0b0001_0000)), beats: 5, into: e)   // lit rank 5 = 55 = the riff pitch
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(ons.count, 2, "one pitch per hit (hits at beats 0 and 4), not two"); XCTAssertTrue(ons.allSatisfy { $0.note == 55 && $0.vel == 90 }, "the riff's velocity wins")
        XCTAssertEqual(Double(mixLength(e, 55) ?? 0), 0.5 * 96_000, accuracy: 6, "the riff's gate wins")
        assertNothingLeftSounding(e)
    }
    // §9.6 — once pinned, the notes velocity ignores a VEL change; unpinned it still reads VEL + the legacy offset.
    func testMixNotesVelocityIgnoresAVelChangeOncePinned() {
        func vels(_ line: EuclidLine) -> (riff: UInt8, lit: UInt8) {
            let e = RecordingEmitter(); mixRun(mixBox(line), beats: 1, into: e)
            return (e.ons.first { $0.note == 55 }?.vel ?? 0, e.ons.first { $0.note == 48 }?.vel ?? 0)
        }
        let a = vels(mixLine(pulses: 1, gate: 0.5, notesGate: nil, vel: 90, notesVelocity: 70)); XCTAssertEqual(a.riff, 90); XCTAssertEqual(a.lit, 70)
        let b = vels(mixLine(pulses: 1, gate: 0.5, notesGate: nil, vel: 120, notesVelocity: 70)); XCTAssertEqual(b.riff, 120); XCTAssertEqual(b.lit, 70, "VEL moved, the pinned notes velocity did not")
        var old = mixLine(pulses: 1, gate: 0.5, notesGate: nil, vel: 100); old.notesVelOffset = -10
        let c = vels(old); XCTAssertEqual(c.riff, 100); XCTAssertEqual(c.lit, 90, "an unedited old session: VEL + offset, exactly as before")
        old.velocityAbsolute = 60; let d = vels(old); XCTAssertEqual(d.lit, 50, "…and until it is edited the notes still follow VEL")
    }
    // §9.6 (seam) — mask-added notes follow their SOURCE pitch's gate: the riff pitch when the hit has one, otherwise the notes layer.
    func testMixMaskAddedChordNotesTakeTheirSourceLayersGate() {
        var m = EuclidLineMask(); m.enabled = true; m.pulses = 2; m.steps = 2; m.chance = 1; m.mode = .chord; m.chordA = 2; m.chordB = 4
        let withRiff = RecordingEmitter()
        mixRun(mixBox(mixLine(pulses: 1, gate: 0.5, notesGate: 0.25, litNotes: 0b0000_0001, mask: m)), beats: 5, into: withRiff, maskOn: true)
        let extrasA = Set(withRiff.ons.filter { $0.cable == 1 }.map { $0.note }).subtracting([55, 48])
        XCTAssertFalse(extrasA.isEmpty, "the CHORD mask added notes")
        for n in extrasA { XCTAssertEqual(Double(mixLength(withRiff, n) ?? 0), 0.5 * 96_000, accuracy: 6, "extra \(n): the riff pitch it comes from sets its gate") }
        XCTAssertEqual(Double(mixLength(withRiff, 48) ?? 0), 0.25 * 96_000, accuracy: 6, "the lit note keeps the notes gate")
        assertNothingLeftSounding(withRiff)
        let litOnly = RecordingEmitter()
        mixRun(mixBox(mixLine(pulses: 1, gate: 0.5, notesGate: 0.25, litNotes: 0b0000_0001, riffOn: false, mask: m)), beats: 5, into: litOnly, maskOn: true)
        let extrasB = Set(litOnly.ons.filter { $0.cable == 1 }.map { $0.note }).subtracting([48])
        XCTAssertFalse(extrasB.isEmpty)
        for n in extrasB { XCTAssertEqual(Double(mixLength(litOnly, n) ?? 0), 0.25 * 96_000, accuracy: 6, "extra \(n): no riff pitch on this hit, so the notes layer's gate") }
        assertNothingLeftSounding(litOnly)
    }
    // §9.6 (seam) — RATCHET repeats each pitch at (sub / nRep) × ITS OWN gate.
    func testMixRatchetRepeatsEachPitchAtItsOwnGate() {
        var m = EuclidLineMask(); m.enabled = true; m.pulses = 2; m.steps = 2; m.chance = 1; m.mode = .ratchet; m.ratchetMin = 2; m.ratchetMax = 2
        let e = RecordingEmitter()
        mixRun(mixBox(mixLine(pulses: 1, gate: 0.5, notesGate: 0.25, mask: m)), beats: 5, into: e, maskOn: true)
        XCTAssertEqual(Double(mixLength(e, 55) ?? 0), (1.0 / 2) * 0.5 * 24_000, accuracy: 6, "riff repeat: (1/2 beat) × 50%")
        XCTAssertEqual(Double(mixLength(e, 48) ?? 0), (1.0 / 2) * 0.25 * 24_000, accuracy: 6, "lit repeat: (1/2 beat) × 25%")
        XCTAssertGreaterThanOrEqual(mixNotes(e, 55).count, 2, "the ratchet really repeated"); assertNothingLeftSounding(e)
    }
    // §9.6 (seam) — the REPEAT hold replays the cached set at each pitch's OWN cached gate (and legato per layer).
    func testMixRepeatReplaysEachPitchAtItsOwnCachedGate() {
        var m = EuclidLineMask(); m.enabled = true; m.pulses = 2; m.steps = 2; m.chance = 1; m.mode = .repeatNote; m.repeatCount = 2
        let e = RecordingEmitter()
        mixRun(mixBox(mixLine(pulses: 4, gate: 0.5, notesGate: 0.25, mask: m)), beats: 3.5, into: e, maskOn: true)   // hits every beat; hit 0 strikes, hit 1 is the REPEAT hold
        for nth in 0...1 {
            XCTAssertEqual(Double(mixLength(e, 55, nth) ?? 0), 0.5 * 24_000, accuracy: 6, "riff pitch, sounding \(nth)")
            XCTAssertEqual(Double(mixLength(e, 48, nth) ?? 0), 0.25 * 24_000, accuracy: 6, "lit pitch, sounding \(nth): the REPLAY used the notes gate, not the lane's GATE")
        }
        assertNothingLeftSounding(e)
    }
    // §9.7 — stuck-note stress: both gates (across 100%), both velocities, both layers on and off, the lit mask, MONO steal and transport restarts.
    func testMixPerLayerGateVelocityStuckNoteStress() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func lineFor(_ tick: Int) -> EuclidLine {
            let gates: [Double] = [1.0, 0.99, 0.6, 1.0, 0.3]
            var l = EuclidLine(target: 0, pulses: 5, steps: 8, gate: gates[tick % 5], velocityAbsolute: 40 + (tick * 7) % 80, rate: .r1_32, useRiff: true,
                               litNotes: UInt8(1 << (tick % 8)), riffOn: (tick / 5) % 2 == 0, sourceMode: .midi, riffLength: 8,
                               notesOn: (tick / 7) % 2 == 0, notesGate: gates[(tick + 2) % 5], notesVelocity: 20 + (tick * 11) % 100)
            if tick % 9 == 4 { l.notesGate = nil; l.notesVelocity = nil }   // an unparted layer mid-stream
            return l
        }
        func sceneFor(_ line: EuclidLine, monoOnA: Bool) -> PluginState {
            var gold = Machine(machineID: "gold", type: .euclid)
            gold.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8]); gold.paramsA.euclidLines = [line]
            var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
            if monoOnA { s.cells[0][0] = Cell(machineID: "orange", buses: [.a]) }
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? gold : Machine(machineID: $0, type: .arp) }, scenes: [s])
            if monoOnA { st.monoMask = 0b0001; st.monoPriority = [0, 0, 0, 0] }
            st.euclideousNoteSource = .midi
            return st
        }
        let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 1024
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        let router = runKeepingRouter(SnapshotBuilder.build(from: sceneFor(lineFor(0), monoOnA: false)), chord(pool), beats: 0.2, into: e, forceColumn: 0, tempo: tempo, sr: sr, frames: frames)
        var diag = KernelDiag()
        var beat = 0.2, ts = 0.2 / tempo * 60.0 * sr
        for tick in 1...90 {
            let monoOnA = (15...24).contains(tick) || (45...50).contains(tick) || (70...76).contains(tick)
            let box1 = SnapshotBuilder.build(from: sceneFor(lineFor(tick), monoOnA: monoOnA))
            if tick == 12 || tick == 30 || tick == 52 || tick == 80 {   // transport restarts mid-stream
                router.process(box: box1, pool: chord(pool), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += windowBeats; ts += Double(frames)
            }
            router.process(box: box1, pool: chord(pool), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: SnapshotBuilder.build(from: sceneFor(lineFor(90), monoOnA: false)), pool: chord(pool), playing: false, beatPos: beat, tempo: tempo,
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        XCTAssertGreaterThan(e.ons.count, 30, "the stress run actually played")
        XCTAssertGreaterThan(Set(e.ons.map { $0.note }).count, 3, "…across several pitches (both layers, the lit mask moving)")
        assertNothingLeftSounding(e)
    }
    // §9.7 (seam) — the same churn through the mask-driven paths (CHORD extras, RATCHET, REPEAT) that carry per-pitch gates.
    func testMixPerLayerGateStuckNoteStressThroughTheMaskModes() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        let modes: [MaskMode] = [.chord, .ratchet, .repeatNote, .chord, .mute, .oct]
        func lineFor(_ tick: Int) -> EuclidLine {
            var m = EuclidLineMask(); m.enabled = true; m.pulses = 3; m.steps = 4; m.chance = 0.8; m.mode = modes[tick % modes.count]; m.repeatCount = 2 + tick % 2
            let gates: [Double] = [1.0, 0.99, 0.6, 1.0, 0.3]
            return EuclidLine(target: 0, pulses: 5, steps: 8, gate: gates[tick % 5], velocityAbsolute: 90, rate: .r1_32, useRiff: true,
                              litNotes: UInt8(1 << (tick % 8)), riffOn: true, mask: m, sourceMode: .midi, riffLength: 8,
                              notesGate: gates[(tick + 3) % 5], notesVelocity: 60)
        }
        let e = RecordingEmitter()
        let router = Router(); router.euclideousMaskEnabledForTests = true
        var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 1024
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for tick in 0..<90 {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8]); c.paramsA.euclidLines = [lineFor(tick)]
            var sc = SceneState.empty(); sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc]); st.euclideousNoteSource = .midi
            let box1 = SnapshotBuilder.build(from: st)
            if tick == 20 || tick == 55 {
                router.process(box: box1, pool: chord(pool), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += windowBeats; ts += Double(frames)
            }
            router.process(box: box1, pool: chord(pool), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: SnapshotBuilder.build(from: { var c = Machine(machineID: "gold", type: .euclid); c.paramsA.euclidLines = [lineFor(0)]
            var sc = SceneState.empty(); sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
            return PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc]) }()),
                       pool: chord(pool), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        XCTAssertGreaterThan(e.ons.count, 30, "the mask-mode stress run actually played")
        assertNothingLeftSounding(e)
    }


    // MARK: - LANES GRID (ferry 2026-10-18) — the OLD sequencer-reset engine's note streams, captured BEFORE the rebuild
    //
    // testLanesGridOldSequencerResetDocumentsRenderTheSameStreamAsBeforeTheGrid RETIRED (2026-10-19, restart-chains
    // ferry): this matrix (old `euclideousLanesSeqOn`/`resetSteps`/`riffLock`, 1536 combinations) asserted the OLD
    // sequencer fields sound correct played LIVE through `SnapshotBuilder.build`/`Router`, with no migration step —
    // true while the grid model read them directly. This ferry's SUMMARY is explicit: "the chains are the only
    // restart model." A lane whose fields haven't migrated to `restartRhythmBars`/`restartMelodyPasses` now plays
    // as FREE/FREE (Router.swift's own disclosed, safe pre-migration default) regardless of what `resetSteps`/
    // `riffLock` still say — migration (§12) is what makes an old document sound right again, and migration is a
    // MAIN-THREAD step (`AudioUnitViewController`'s resync loop, pinned on load) that this bare-Router unit-test
    // harness never runs. Re-deriving this entire 1536-combination matrix's migration-exactness by hand (§12.4's
    // bar-alignment rule rejects most of it outright — these profiles were never chosen to be bar-aligned) is out
    // of proportion to what it would buy: migration correctness is already covered, combination by combination,
    // by `RestartChainsTests.swift`'s `migrateRestartChains` tests, including the ferry's own §14 test 14 literal
    // examples (every-bar on 8×1/8 ⇒ rhythm FREE/melody 1; every-bar on 7×1/8 ⇒ rhythm [1]/melody [2]; every-4-
    // steps-at-1-BAR/LEN-6 on 8×1/8 ⇒ rhythm FREE/melody [4,2]; every-step-at-¼-BAR ⇒ not exact; riffLock alone ⇒
    // melody 1). Not ported.

    // MARK: - LANES GRID engine tests (ferry 2026-10-18, §8) — the Router, end to end, on explicit grid fields

    /// 3-of-8 at 1/8 (hits at ticks 0, 3, 6 of each 8-tick pass; a tick is half a beat, so a pass is 4 beats), the riff 1…8 ascending and the only
    /// layer sounding. `mixBox`/`mixRun` give 120 BPM at 48 kHz: one beat = 24 000 samples; rank r reads the pool note [48,50,52,53,55,57,59,60][r-1].
    private func gridLine(unit: EuclideousRestartUnit = .fourSteps, rhythm: UInt16 = 0, melody: UInt16 = 0, mute: UInt16 = 0xFFFF,
                          muteUnit: EuclideousMuteUnit = .pass, locked: Bool = false, stepAdvance: Bool = false, dir: RiffDir = .forward) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: 8)
        l.restartUnit = unit.rawValue; l.restartRhythmMask16 = rhythm; l.restartMelodyMask16 = melody
        l.muteCells16 = mute; l.muteUnit = muteUnit.rawValue
        l.riffLock = locked; l.riffAdvanceStep = stepAdvance; l.riffDir = dir
        return l
    }
    private let gridPool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]
    /// Every cable-1 note-on, as (beat, pool index), in sounding order. `ranks` defaults to identity
    /// (column c → rank c+1, no rests) — pass a ranks array with zeros to test rest-handling (REPEAT, FILL, TIE).
    private func gridHits(_ line: EuclidLine, ranks: [Int] = [1, 2, 3, 4, 5, 6, 7, 8], beats: Double, startBeat: Double = 0) -> [(beat: Double, idx: Int)] {
        let e = RecordingEmitter()
        mixRun(mixBox(line, ranks: ranks), beats: beats, into: e, startBeat: startBeat)
        assertNothingLeftSounding(e)
        // a note-on's sample is truncated, so a hit on beat 5.5 can land one sample early: round to the nearest 1/100 beat
        return e.ons.filter { $0.cable == 1 }.compactMap { ev in gridPool.firstIndex(of: ev.note).map { ((Double(ev.sample) / 24_000 * 100).rounded() / 100, $0) } }
    }
    /// The hit ticks of the pattern x..x..x. with the pass restarted at each tick in `restarts` (ascending), up to `last`.
    private func gridExpectedHitTicks(restarts: [Int], last: Int) -> [Int] {
        (0...last).filter { t in
            let origin = restarts.last(where: { $0 <= t }) ?? 0
            return [0, 3, 6].contains((t - origin) % 8)
        }
    }

    // RESTART CHAINS (ferry 2026-10-19): "the chains are the only restart model" (SUMMARY) — this ferry
    // explicitly supersedes "every restart part" of the LANES panel ferry (2026-10-18), including its own
    // tests. The four tests above (rhythm-only rephase, melody-only, both-marks, mark-inside-a-muted-cell)
    // tested the masked GRID model's arbitrary per-cell marks read LIVE by the real engine — chains have no
    // such read: a lane's real restart decision now comes ONLY from `restartRhythmBars`/`restartMelodyPasses`
    // (pinned by migration, §12), and a grid mark with no chain equivalent (most of them: chains restart only
    // on bar/pass boundaries, a grid cell can land anywhere) plays as FREE until migrated. Retired rather than
    // ported — a 4-tick-cell mark at beat 6 has no bar-aligned chain translation to port it TO. Replaced below
    // by the equivalent guarantees (§4.8) proven directly against the new model, on a geometry where a bar
    // restart genuinely cuts a lap short (3-of-7 @ 1/8: lapBeats 3.5, not a whole bar — the ferry's own §14
    // test 5 geometry), plus a mirror-vs-router agreement test standing in for the retired
    // `testWalkTagMirrorMatchesAHandPlacedRestartMask` (below, also retired for the same reason).
    private func chainLine(rhythmBars: [UInt8]? = nil, melodyPasses: [UInt8]? = nil, mute: UInt16 = 0xFFFF,
                           stepAdvance: Bool = false, dir: RiffDir = .forward) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 3, steps: 7, rate: .r1_8, useRiff: true, litNotes: 0, riffOn: true, sourceMode: .midi, riffLength: 8)
        l.restartRhythmBars = rhythmBars ?? []; l.restartMelodyPasses = melodyPasses ?? []
        l.muteCells16 = mute
        l.riffAdvanceStep = stepAdvance; l.riffDir = dir
        return l
    }
    func testChainRhythmOnlyRephasesTheHitsAndThePitchesKeepCountingStraightThrough() {
        let free = gridHits(chainLine(), beats: 19.9)
        let rephased = gridHits(chainLine(rhythmBars: [1]), beats: 19.9)
        XCTAssertNotEqual(rephased.map { $0.beat }, free.map { $0.beat }, "a bar restart on a 3.5-beat lap genuinely cuts laps short — the hits really move")
        // every bar line (beat 0, 4, 8, …) re-anchors the step phase: no hit can occupy the dead zone a short-circuited
        // lap leaves just before the NEXT bar line (the lap would need beat 3.5+ of its own 3.5-beat span to get there).
        for beat in rephased.map({ $0.beat }) {
            XCTAssertLessThan(beat.truncatingRemainder(dividingBy: 4.0), 3.5 + 1e-6, "beat \(beat): inside the rephased lap's own 3.5-beat reach")
        }
        XCTAssertEqual(rephased.map { $0.idx }, (0..<rephased.count).map { $0 % 8 }, "the riff ordinal is NOT reset by a rhythm-only chain: pitches 1, 2, 3, … uninterrupted")
    }
    func testChainMelodyOnlyLeavesEveryHitInPlaceAndTheRiffReturnsToItsStart() {
        for (melody, step): ([UInt8], Bool) in [([1], false), ([1], true), ([2, 1], false)] {
            let base = gridHits(chainLine(stepAdvance: step), beats: 19.9)
            let marked = gridHits(chainLine(melodyPasses: melody, stepAdvance: step), beats: 19.9)
            XCTAssertEqual(marked.map { $0.beat }, base.map { $0.beat }, "melody \(melody) step \(step): every hit stays exactly where it was")
            XCTAssertNotEqual(marked.map { $0.idx }, base.map { $0.idx }, "melody \(melody) step \(step): the riff really did restart somewhere")
            // a melody chain of [1] restarts the riff to its first note (index 0) at the very first hit of EVERY lap (3.5 beats) — in HIT mode
            // that first hit is always riff position 0, since the chain subsumes what old LOCK did at every lap start (§4.7).
            if melody == [1], !step {
                let lapBeats = 3.5
                var lap = 0
                while Double(lap) * lapBeats < 19.9 {
                    let lo = Double(lap) * lapBeats
                    if let first = marked.first(where: { $0.beat >= lo - 1e-6 }) { XCTAssertEqual(first.idx, 0, "lap \(lap) (beat \(lo)): restarted to riff position 0") }
                    lap += 1
                }
            }
        }
    }
    func testChainBothRhythmAndMelodyBehaveExactlyLikeTheOldSingleRestart() {
        // A rhythm-only run rephases hits with the riff counting straight through (above); a melody-only run leaves hits in
        // place with the riff restarting (above); BOTH together must do both at once — the hit positions from the rhythm-
        // only run, paired with the riff restarting at each bar the way the melody-only run's [1] case restarts at each lap.
        let rhythmOnly = gridHits(chainLine(rhythmBars: [1]), beats: 19.9)
        let both = gridHits(chainLine(rhythmBars: [1], melodyPasses: [1]), beats: 19.9)
        XCTAssertEqual(both.map { $0.beat }, rhythmOnly.map { $0.beat }, "the rhythm chain alone decides the hit positions")
        XCTAssertNotEqual(both.map { $0.idx }, rhythmOnly.map { $0.idx }, "…but the melody chain restarts the riff where the rhythm-only run let it run on")
        XCTAssertEqual(both.first?.idx, 0, "the very first hit of the very first (rephased) lap still reads riff position 0")
    }
    func testChainMirrorMatchesTheRealRouterUnderARephasingRhythmChainAndARestartingMelodyChain() {
        // Stands in for the retired `testWalkTagMirrorMatchesAHandPlacedRestartMask`: the UI-facing walk mirror
        // (`euclideousWalkLaneConfig`/`euclideousWalkTick`) must never disagree with the real Router — CLAUDE.md's own
        // named recurring bug class — now proven against chains instead of an arbitrary mask.
        let pool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]
        let cases: [(rhythm: [UInt8]?, melody: [UInt8]?, step: Bool, dir: RiffDir)] = [
            ([1], nil, false, .forward), (nil, [1], false, .forward), ([1], [1], false, .forward),
            ([2, 1], nil, true, .pendulum), (nil, [2, 1], false, .reverse),
        ]
        for c in cases {
            let line = chainLine(rhythmBars: c.rhythm, melodyPasses: c.melody, stepAdvance: c.step, dir: c.dir)
            let e = RecordingEmitter()
            mixRun(mixBox(line, ranks: [1, 2, 3, 4, 5, 6, 7, 8]), beats: 23.9, into: e)
            assertNothingLeftSounding(e)
            let ons = e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }
            guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { XCTFail(); continue }
            XCTAssertTrue(cfg.chains.isActive, "the chain fields resolve to an active restart-chain config")
            var tick: Int64 = -1
            var checked = 0
            for on in ons {
                repeat { tick += 1 } while !euclideousWalkTick(cfg, tick: tick).isHit
                let w = euclideousWalkTick(cfg, tick: tick)
                XCTAssertEqual(pool[w.playedStep], on.note, "rhythm \(String(describing: c.rhythm)) melody \(String(describing: c.melody)) step \(c.step) dir \(c.dir): hit at sample \(on.sample)")
                checked += 1
            }
            XCTAssertGreaterThan(checked, 10, "the comparison must actually run")
        }
    }
    func testGridMuteIsResolvedPerHitAndAMutedHitStillAdvancesTheWalk() {
        // PASS cells of 4 beats; cell 1 muted. Hits sit at ticks 0,3,6,8,11,14,16… → beats 0,1.5,3,4,5.5,7,8,…  The hit at beat 4.0 is the FIRST tick of the
        // muted cell: it must take the NEW cell's state (the old once-per-window decision let it sound).
        let all = gridHits(gridLine(), beats: 11.9)
        let m = gridHits(gridLine(mute: 0xFFFF & ~(1 << 1)), beats: 11.9)
        XCTAssertFalse(m.contains { abs($0.beat - 4.0) < 1e-6 }, "a hit on the first tick of a muted cell is muted")
        XCTAssertTrue(m.contains { abs($0.beat - 3.0) < 1e-6 }, "…the hit one tick before it (last of the audible cell) still sounds")
        XCTAssertEqual(m.map { $0.beat }, all.filter { $0.beat < 3.99 || $0.beat >= 7.99 }.map { $0.beat })
        XCTAssertEqual(m.map { $0.idx }, all.filter { $0.beat < 3.99 || $0.beat >= 7.99 }.map { $0.idx }, "muting never shifts the melody: the walk advanced through the muted hits")
    }
    func testGridMuteWindowIsNotReAnchoredByARestart() {
        // The same mute cells, with and without a restarting chain (2026-10-19: converted from a grid mark, see
        // the retired tests above), on the SAME (chain) geometry so the mute-cell boundaries — PASS-sized, 3.5
        // beats on this 7-step/1-8 lane, cell 1 muted ⇒ beats [3.5, 7) — line up for both runs: the SAME beats
        // are silent whether or not a restart chain is rephasing the hits underneath.
        let a = gridHits(chainLine(mute: 0b1111_1111_1111_1101), beats: 19.9)
        let b = gridHits(chainLine(rhythmBars: [1], melodyPasses: [1], mute: 0b1111_1111_1111_1101), beats: 19.9)
        XCTAssertFalse(a.isEmpty); XCTAssertFalse(b.isEmpty)
        XCTAssertTrue(a.allSatisfy { $0.beat < 3.49 || $0.beat >= 6.99 }); XCTAssertTrue(b.allSatisfy { $0.beat < 3.49 || $0.beat >= 6.99 })
    }
    func testGridALaneThatGoesMutedClosesItsHeldLegatoNoteAtItsOwnCellBoundary() {
        // GATE 100% = legato: every pitch is held across hits. With 2-beat (4STP) mute cells and cell 1 muted, the held note must close at beat 2.0
        // (48 000 samples) — that lane's OWN boundary — not at some global step edge.
        var l = gridLine(mute: 0xFFFF & ~(1 << 1), muteUnit: .fourSteps)
        l.gate = 1.0
        let e = RecordingEmitter(); mixRun(mixBox(l, ranks: [1, 1, 1, 1, 1, 1, 1, 1]), beats: 3.9, into: e)
        assertNothingLeftSounding(e)
        let off = e.offs.first { $0.cable == 1 && $0.note == 48 }
        XCTAssertNotNil(off)
        XCTAssertEqual(Double(off?.sample ?? 0), 48_000, accuracy: 2, "closed exactly on the lane's own mute-cell boundary (beat 2)")
        // a different unit on the same lane moves the boundary with it
        var l2 = gridLine(mute: 0xFFFF & ~(1 << 1), muteUnit: .pass); l2.gate = 1.0
        let e2 = RecordingEmitter(); mixRun(mixBox(l2, ranks: [1, 1, 1, 1, 1, 1, 1, 1]), beats: 5.9, into: e2)
        XCTAssertEqual(Double(e2.offs.first { $0.cable == 1 && $0.note == 48 }?.sample ?? 0), 96_000, accuracy: 2, "PASS cells: the boundary is beat 4")
    }
    func testChainTieLookaheadFollowsARhythmRestartThatMovesTheNextRealNote() {
        // Riff ranks [1,0,0,0,0,0,0,2], ON REST = TIE: the first note (pitch 48) is held over the rests until the hit
        // that reads rank 2 (pitch 50). A rhythm chain of [1] (2026-10-19: converted from a grid mark, see the retired
        // tests above) pulls that hit earlier by cutting a lap short; the held note must end earlier too — the
        // lookahead has to see the restart, not just the lane's own unbroken pattern.
        func firstNoteLength(rhythmBars: [UInt8]?) -> Double {
            var l = chainLine(rhythmBars: rhythmBars); l.riffOnRest = .tie
            let e = RecordingEmitter(); mixRun(mixBox(l, ranks: [1, 0, 0, 0, 0, 0, 0, 2]), beats: 12.9, into: e)
            let on = e.ons.first { $0.cable == 1 && $0.note == 48 }!
            let off = e.offs.first { $0.cable == 1 && $0.note == 48 }!
            return Double(off.sample - on.sample) / 24_000
        }
        let plain = firstNoteLength(rhythmBars: nil)
        let marked = firstNoteLength(rhythmBars: [1])
        XCTAssertNotEqual(plain, marked, "the rhythm chain genuinely changes which tick plays the rank-2 hit, so the held note's own length changes")
        XCTAssertGreaterThan(marked, 0, "the lookahead still found a real note to end the tie — it didn't fall through to its cap")
        XCTAssertLessThan(abs(plain - marked), 4.0, "a bar restart only ever pulls the next hit earlier by less than a bar")
    }
    // testGridFirstWindowRunsFromANegativeOriginDeterministically RETIRED (2026-10-19): its whole premise — the first
    // window, before any mark, carries an origin from the PREVIOUS (unseen) window, which can be NEGATIVE — has no
    // chain equivalent. §12.6, literally: "Beat 0 is always a restart in the new model" — a chain never carries a
    // negative origin forward from before beat 0; there is no "previous window" to inherit from. Not ported.

    // §3 / §8 ROLL FEED vs the Router: for a lane with a known pattern and riff, the roll's hits equal the beats, ranks and lengths the Router
    // really produces over the same window, with and without marks, muted and audible flagged correctly, and a TIE extension included.
    func testGridRollFeedEqualsWhatTheRouterActuallyPlays() {
        struct Case { var name: String; var line: EuclidLine; var ranks: [Int] }
        // "tie"/"marked" (2026-10-19): converted from grid marks to chain fields, see the retired tests above.
        var tie = chainLine(rhythmBars: [1]); tie.riffOnRest = .tie; tie.gate = 0.5
        var plain = gridLine(); plain.gate = 0.5
        var marked = chainLine(rhythmBars: [1], melodyPasses: [2]); marked.gate = 0.5
        var muted = gridLine(rhythm: 1 << 2, mute: 0xFFFF & ~((1 << 1) | (1 << 3)), muteUnit: .fourSteps); muted.gate = 0.5
        var inverted = gridLine(melody: 1 << 3); inverted.riffInvert = true; inverted.melodyTranspose = 1; inverted.gate = 0.5
        let up = [1, 2, 3, 4, 5, 6, 7, 8]
        let cases = [Case(name: "plain", line: plain, ranks: up), Case(name: "marked", line: marked, ranks: up), Case(name: "muted", line: muted, ranks: up),
                     Case(name: "tie", line: tie, ranks: [1, 0, 0, 0, 0, 0, 0, 2]), Case(name: "invert+transpose", line: inverted, ranks: up),
                     Case(name: "rests", line: plain, ranks: [3, 0, 5, 0, 7, 0, 1, 0])]
        var compared = 0
        for c in cases {
            let e = RecordingEmitter()
            mixRun(mixBox(c.line, ranks: c.ranks), beats: 15.9, into: e)
            assertNothingLeftSounding(e)
            let ons = e.ons.filter { $0.cable == 1 }
            // a note still sounding when the run ends is closed by the stop-edge flush (a sentinel sample), so it has no comparable length
            func length(of on: RecordingEmitter.Ev) -> Double? {
                guard let off = e.offs.first(where: { $0.cable == 1 && $0.note == on.note && $0.sample >= on.sample }) else { return nil }
                return Double(off.sample - on.sample) / 24_000
            }
            guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [c.line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { XCTFail(c.name); continue }
            let roll = euclideousLaneRollHits(cfg: cfg, windowStart: 0, windowBeats: 15.9, minGateBeats: 0.005 * 120 / 60) { col, _ in c.ranks[col] }
            let sounding = roll.filter { $0.audible && $0.rank >= 1 }
            XCTAssertEqual(sounding.count, ons.count, "\(c.name): the roll's audible hits are exactly the Router's note-ons")
            for (r, on) in zip(sounding, ons) {
                XCTAssertEqual(r.beat, Double(on.sample) / 24_000, accuracy: 0.01, "\(c.name): hit beat")
                if let len = length(of: on) {
                    XCTAssertEqual(r.gateBeats, len, accuracy: 0.02, "\(c.name): gate length at beat \(r.beat)")
                    compared += 1
                }
            }
            // every roll hit that is NOT a Router note-on is either muted (audible == false) or a rest (rank < 1) — never silently dropped
            let soundingBeats = Set(ons.map { (Double($0.sample) / 24_000 * 100).rounded() })
            for r in roll where !soundingBeats.contains((r.beat * 100).rounded()) {
                XCTAssertTrue(!r.audible || r.rank < 1, "\(c.name): a non-sounding roll hit at beat \(r.beat) must be flagged muted or a rest")
            }
            if c.name == "muted" { XCTAssertTrue(roll.contains { !$0.audible }, "the muted case really has muted hits"); XCTAssertTrue(roll.contains { $0.audible }) }
            if c.name == "rests" { XCTAssertTrue(roll.contains { $0.rank < 1 }) }
        }
        XCTAssertGreaterThan(compared, 40, "the comparison must actually run")
        // the rank the roll plots is the rank the Router reads: with INVERT the contour flips (9 − r) and TRANSPOSE shifts it
        let invCfg = euclideousWalkLaneConfig(lane: 0, lines: [inverted], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        let invRoll = euclideousLaneRollHits(cfg: invCfg, windowStart: 0, windowBeats: 4, minGateBeats: 0.01) { col, _ in up[col] }
        XCTAssertFalse(invRoll.isEmpty)
        XCTAssertTrue(invRoll.allSatisfy { $0.rank >= 1 && $0.rank <= 9 })
    }

    // §2.8 — the page's FOOTER baseline comes from the core: the ordinal the current lap's first hit reads, across a
    // melody restart too. Converted (2026-10-19) from grid masks/LOCK to chain fields — see the retired tests above.
    func testChainLapStartOrdinalIsWhatTheEngineReadsAtTheLapsFirstHit() {
        let combos: [([UInt8]?, [UInt8]?)] = [(nil, nil), ([1], nil), (nil, [1]), ([1], [1]), ([2, 1], [2])]
        for (rhythm, melody) in combos {
            let line = chainLine(rhythmBars: rhythm, melodyPasses: melody)
            guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { XCTFail(); continue }
            for beat in stride(from: 0.2, through: 40.0, by: 1.7) {
                let tick = Int64((beat / cfg.sub).rounded(.down))
                let cycleLen = euclidCycleLen(cfg.dir, n: cfg.n)
                let now = euclideousLaneChainTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: tick, chains: cfg.chains,
                                                  legacySpanBeats: cfg.spanBeats, advanceStep: cfg.advanceStep)
                let lapStart = tick - Int64(now.raw)
                let firstHit = (0..<cycleLen).first { cfg.buf[euclidReadIndex($0, n: cfg.n, dir: cfg.dir)] }!
                let want = euclideousLaneChainTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: lapStart + Int64(firstHit), chains: cfg.chains,
                                                   legacySpanBeats: cfg.spanBeats, advanceStep: cfg.advanceStep).advOrd
                XCTAssertEqual(euclideousLapStartOrdinal(cfg: cfg, beat: beat), want, "rhythm \(String(describing: rhythm)) melody \(String(describing: melody)) beat \(beat)")
            }
        }
    }

    // MARK: - FX TAB (ferry 2026-10-18) — probes + engine tests

    /// A held-legato pitch that the NEXT hit strikes again NON-legato, reachable WITHOUT any FX via the MIX ferry's per-layer gates: the lit note (rank 1,
    /// notes gate 100%) is held legato by hit 0; hit 1's riff pitch (rank 1, riff gate 60%) is the SAME pitch and wins the collision, so it is struck at 60%.
    private func fxRestrikeLine() -> EuclidLine {
        EuclidLine(target: 0, pulses: 4, steps: 4, gate: 0.6, velocityAbsolute: 90, rate: .r1_4, useRiff: true, litNotes: 0b0000_0001, riffOn: true,
                   sourceMode: .midi, riffLength: 2, notesOn: true, notesGate: 1.0)
    }
    /// §4.2 (the probe's permanent form): a held pitch the next hit strikes again closes at the hit's OWN sample, just BEFORE its new note-on in stream order —
    /// never 10 ms after it (which used to leave OFF@+10ms then ON@hit on the wire, cutting the new note on a time-sorting host).
    func testARestruckHeldPitchClosesAtTheHitsOwnSampleBeforeItsNewNoteOn() {
        let e = RecordingEmitter()
        mixRun(mixBox(fxRestrikeLine(), ranks: [2, 1, 0, 0, 0, 0, 0, 0]), beats: 3.5, into: e)
        let evs = e.events.filter { $0.cable == 1 && $0.note == 48 }
        let secondOn = evs.firstIndex { $0.status == 0x90 && $0.sample > 12_000 }!
        XCTAssertEqual(evs[secondOn - 1].status, 0x80, "the old note's OFF comes first…")
        XCTAssertEqual(evs[secondOn - 1].sample, evs[secondOn].sample, "…at the SAME sample as the new ON")
        var sounding = 0
        for ev in evs { sounding += ev.status == 0x90 ? 1 : -1; XCTAssertLessThanOrEqual(sounding, 1, "a pitch never overlaps itself") }
        assertNothingLeftSounding(e)
    }

    // MARK: - FX TAB engine (ferry 2026-10-18, §15)

    /// One lane, 4-of-4 at 1/4 (one hit per beat, a gap of 24 000 samples at 120 BPM / 48 kHz), the riff walked FWD over 8 columns — so beat k reads column k mod 8.
    private func fxLine(gate: Double = 0.5, vel: Int = 90, emitter: UInt8? = nil, litNotes: UInt8 = 0, onRest: EuclidRiffOnRest = .skip, riffOn: Bool = true) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4)
        l.gate = gate; l.velocityAbsolute = vel; l.rate = .r1_4; l.useRiff = true; l.litNotes = litNotes; l.riffOn = riffOn; l.sourceMode = .midi
        l.riffLength = 8; l.notesOn = true; l.riffOnRest = onRest; l.emitterMask = emitter
        return l
    }
    private let fxPoolNotes: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]
    private func fxBox(_ lines: [EuclidLine], ranks: [Int] = [1, 2, 3, 4, 5, 6, 7, 8], fx: EuclideousFX = EuclideousFX(), buses: Set<Bus> = [.a, .b, .c, .d]) -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks)
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: buses)
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousFX = fx
        return SnapshotBuilder.build(from: st)
    }
    private func fxCells(_ cells: [(row: Int, col: Int, v: Int)], lanes: [Int: UInt8] = [:], passes: UInt8 = 4, ccNumber: UInt8 = 74, ccBase: Int16 = -1, shape: UInt8 = 0) -> EuclideousFX {
        var fx = EuclideousFX(); fx.ratchShape = shape
        for c in cells { fx.cells[c.row * 8 + c.col] = Int8(c.v) }
        for (r, m) in lanes { fx.lanes[r] = m }
        fx.notePasses = passes; fx.ccNumber = ccNumber; fx.ccBase = ccBase
        return fx
    }
    /// Run `beats` of playing windows of `frames` frames from beat 0, optionally restarting the transport (stop window, then back to beat 0) at each beat in `restartAt`.
    private func fxRun(_ box: SnapshotBox, beats: Double, frames: UInt32 = 2048, pool: [UInt8]? = nil, restartAt: [Double] = [], maskOn: Bool = false,
                       restartSamples: UnsafeMutablePointer<[Int64]>? = nil) -> RecordingEmitter {
        let e = RecordingEmitter()
        let router = Router(); router.euclideousMaskEnabledForTests = maskOn
        var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0
        let p = chord(pool ?? fxPoolNotes)
        // the host's beat position is an exact function of the sample count (one beat = 24 000 samples), NOT a running sum of window lengths — so every window
        // size sees the same beat for the same sample (a float accumulation would drift by a sample or two between sizes)
        var ts = 0.0, origin = 0.0
        func beatNow() -> Double { (ts - origin) * tempo / 60.0 / sr }
        var restarts = restartAt.sorted()
        while beatNow() < beats {
            if let r = restarts.first, beatNow() >= r {
                restarts.removeFirst()
                router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
                ts += Double(frames); origin = ts
                restartSamples?.pointee.append(Int64(ts))      // the sample at which the replayed beat 0 begins
            }
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }
    private func fxOns(_ e: RecordingEmitter, cable: UInt8 = 1) -> [(beat: Double, note: UInt8, vel: UInt8)] {
        e.ons.filter { $0.cable == cable }.map { (Double($0.sample) / 24_000, $0.note, $0.vel) }
    }
    /// every (on-sample, off-sample) sounding of `note` on `cable`
    private func fxSoundings(_ e: RecordingEmitter, _ note: UInt8, cable: UInt8 = 1) -> [(on: Int64, off: Int64?)] {
        var out: [(on: Int64, off: Int64?)] = []
        for ev in e.events where ev.cable == cable && ev.note == note && (ev.status == 0x90 || ev.status == 0x80) {
            if ev.status == 0x90 { out.append((ev.sample, nil)) } else if let i = out.lastIndex(where: { $0.off == nil }) { out[i].off = ev.sample }
        }
        return out
    }
    private func fxStream(_ e: RecordingEmitter) -> [[Int64]] {
        e.events.map { [$0.sample, Int64($0.cable), Int64($0.status), Int64($0.chan), Int64($0.note), Int64($0.vel)] }
    }

    // §15 NOTE — the spec's own worked example (7.4): a C minor triad, FREE / FWD / STRIDE 1 / LENGTH 8 / ADV HIT, a column written rank 4 with NOTE +1, PASSES 4.
    func testFXNoteClimbsOneStepPerPassAndComesBackToTheWrittenNoteAfterNPasses() {
        let triad: [UInt8] = [48, 51, 55]                                           // C3 E♭3 G3 → rank 4 = C4 (60)
        let box = fxBox([fxLine()], ranks: [1, 1, 1, 4, 1, 1, 1, 1], fx: fxCells([(4, 3, 1)], passes: 4))
        let e = fxRun(box, beats: 40, pool: triad)
        assertNothingLeftSounding(e)
        // column 3 is read at beats 3, 11, 19, 27, 35
        let atCol3 = fxOns(e).filter { Int($0.beat.rounded()) % 8 == 3 && abs($0.beat - $0.beat.rounded()) < 0.01 }.prefix(5).map { $0.note }
        XCTAssertEqual(Array(atCol3), [60, 63, 67, 72, 60], "C4, E♭4, G4, C5, then C4 again — on its first five plays, whatever the lane's hit count")
        // every other column keeps its written note (rank 1 = C3)
        let others = fxOns(e).filter { Int($0.beat.rounded()) % 8 != 3 }
        XCTAssertTrue(others.allSatisfy { $0.note == 48 })
    }
    func testFXNoteRankZeroSoundsNeverARestAndAWrittenRestStaysARest() {
        let triad: [UInt8] = [48, 51, 55]
        // written rank 1 with NOTE −1: pass 0 plays C3 as written, pass 1 moves to rank 0 = G2 (43) — a pitch, not a rest
        let e = fxRun(fxBox([fxLine()], ranks: [1, 0, 0, 0, 0, 0, 0, 0], fx: fxCells([(4, 0, -1), (4, 1, 2)], passes: 4)), beats: 17, pool: triad)
        let col0 = fxOns(e).filter { Int($0.beat.rounded()) % 8 == 0 && abs($0.beat - $0.beat.rounded()) < 0.01 }.map { $0.note }
        XCTAssertEqual(Array(col0.prefix(3)), [48, 43, 39], "rank 1, 0, −1 → C3, G2, E♭2")
        // column 1 is WRITTEN as a rest with a NOTE cell on it: still a rest — nothing sounds there
        XCTAssertTrue(fxOns(e).allSatisfy { Int($0.beat.rounded()) % 8 == 0 })
        assertNothingLeftSounding(e)
    }
    func testFXNoteIgnoresLitNotesAndFarMovesNeverTrap() {
        // lit note rank 1 (C3) never moves; the riff note climbs
        let withLit = fxRun(fxBox([fxLine(litNotes: 0b1)], ranks: [3, 3, 3, 3, 3, 3, 3, 3], fx: fxCells([(4, 0, 1), (4, 1, 1), (4, 2, 1)], passes: 4)), beats: 8, pool: [48, 51, 55])
        XCTAssertTrue(fxOns(withLit).filter { $0.note == 48 }.count >= 8 - 1, "the lit note C3 sounds on every hit and never moves")
        // one note held, NOTE +3 at pass 7 of PASSES 8, rank 8, TRANSPOSE +7 → 35 octaves up: dropped, nothing traps, every emitted pitch stays in range
        var l = fxLine(); l.melodyTranspose = 7
        let far = fxRun(fxBox([l], ranks: [8, 8, 8, 8, 8, 8, 8, 8], fx: fxCells([(4, 0, 3), (4, 1, 3), (4, 2, -3)], passes: 8)), beats: 130, pool: [60])
        XCTAssertTrue(far.ons.allSatisfy { $0.note <= 127 })
        assertNothingLeftSounding(far)
        // …and the same far-below move with a RATCH (deferred strikes) never turns into a stray note 0
        var l2 = fxLine(); l2.melodyTranspose = -7
        let low = fxRun(fxBox([l2], ranks: [1, 1, 1, 1, 1, 1, 1, 1], fx: fxCells([(4, 0, -3), (0, 0, 4)], passes: 8)), beats: 130, pool: [30])
        XCTAssertFalse(low.ons.contains { $0.note == 0 }, "no clamped-to-zero ghost note from a ratchet's deferred strikes")
        assertNothingLeftSounding(low)
    }
    func testFXNoteOffsetUsesTheColumnReadAfterShift() {
        var l = fxLine(); l.riffRotate = 2                                          // SHIFT 2: beat k reads column (k + 2) mod 8
        let e = fxRun(fxBox([l], ranks: [1, 2, 3, 4, 5, 6, 7, 8], fx: fxCells([(0, 5, 2)])), beats: 8)
        // column 5 is read at beat 3 (3 + 2): two strikes there, one everywhere else
        let beatsWithTwo = Dictionary(grouping: fxOns(e).map { Int($0.beat + 0.0001) }, by: { $0 }).filter { $0.value.count == 2 }.keys.sorted()
        XCTAssertEqual(beatsWithTwo, [3])
    }

    // §15 RATCH
    func testFXRatchPlaysNStrikesAtSlotSpacingEachLastingTheGateShareOfItsSlot() {
        let e = fxRun(fxBox([fxLine(gate: 0.5)], fx: fxCells([(0, 3, 3)])), beats: 4.5)   // hits at beats 0…4 (the last window ends just past 4.5, before beat 5)
        assertNothingLeftSounding(e)
        let s = fxSoundings(e, fxPoolNotes[3])                                       // column 3 (rank 4) sounds at beat 3
        XCTAssertEqual(s.count, 3, "RATCH 3 = three strikes — never rolled, never clamped")
        let slot = 24_000.0 / 3
        for (k, snd) in s.enumerated() {
            XCTAssertEqual(Double(snd.on), 3 * 24_000 + Double(k) * slot, accuracy: 3, "strike \(k) at hit + k × step ÷ n")
            XCTAssertEqual(Double(snd.off ?? 0) - Double(snd.on), slot * 0.5, accuracy: 3, "each lasts the lane's GATE (50%) of its slot")
        }
        XCTAssertEqual(fxOns(e).count, 4 + 3, "the other four hits strike once")
        // RATCH 2 and 4
        for n in [2, 4] {
            let en = fxRun(fxBox([fxLine(gate: 0.5)], fx: fxCells([(0, 3, n)])), beats: 5)
            XCTAssertEqual(fxSoundings(en, fxPoolNotes[3]).count, n)
        }
    }
    func testFXRatchWithGateOverrideAndVelocityAndNoteCarriesEveryStrike() {
        // GATE 95 (the row's top — there is no legato any more) on a ratcheted hit takes 95% of each slot and re-strikes (never merged); VEL and NOTE reach every strike
        let fx = fxCells([(0, 3, 4), (1, 3, 95), (3, 3, 110), (4, 3, 1)], passes: 4)
        let e = fxRun(fxBox([fxLine(gate: 0.5, vel: 90)], ranks: [1, 2, 3, 4, 1, 2, 3, 4], fx: fx), beats: 20)
        assertNothingLeftSounding(e)
        // first play of column 3 (beat 3, pass 0 ⇒ as written: rank 4 = 53): four strikes, each the full slot, all at velocity 110
        let first = fxSoundings(e, 53).prefix(4)
        XCTAssertEqual(first.count, 4)
        for (k, snd) in first.enumerated() {
            XCTAssertEqual(Double(snd.on), 3 * 24_000 + Double(k) * 6_000, accuracy: 3)
            XCTAssertEqual(Double(snd.off ?? 0) - Double(snd.on), 0.95 * 6_000, accuracy: 4, "95% of the slot")
        }
        XCTAssertTrue(e.ons.filter { $0.cable == 1 && $0.note == 53 }.prefix(4).allSatisfy { $0.vel == 110 })
        // second play of column 3 (beat 7 is column 7; the column comes round at beat 11): pass 1 ⇒ rank 5 = 55, four strikes again
        XCTAssertGreaterThanOrEqual(fxSoundings(e, 55).filter { Double($0.on) / 24_000 > 10.9 && Double($0.on) / 24_000 < 12.1 }.count, 4, "every strike carries NOTE's moved pitch")
    }
    func testFXRatchReplacesAMaskRatchetOnTheSameHitAndCarriesChordNotes() {
        var m = EuclidLineMask(); m.enabled = true; m.pulses = 2; m.steps = 2; m.chance = 1; m.mode = .ratchet; m.ratchetMin = 2; m.ratchetMax = 2
        var l = fxLine(); l.mask = m
        let e = fxRun(fxBox([l], fx: fxCells([(0, 3, 4)])), beats: 5, maskOn: true)
        XCTAssertEqual(fxSoundings(e, fxPoolNotes[3]).count, 4, "the FX count (4) wins over the mask's own 2 on that hit")
        XCTAssertEqual(fxSoundings(e, fxPoolNotes[0]).count, 2, "…while the mask still ratchets the other hits ×2")
        // CHORD notes ride every strike
        var cm = EuclidLineMask(); cm.enabled = true; cm.pulses = 2; cm.steps = 2; cm.chance = 1; cm.mode = .chord; cm.chordA = 2; cm.chordB = 4
        var l2 = fxLine(); l2.mask = cm
        let ec = fxRun(fxBox([l2], fx: fxCells([(0, 0, 3)])), beats: 1, maskOn: true)
        let notesAtFirstStrike = Set(ec.ons.filter { $0.cable == 1 && $0.sample < 100 }.map { $0.note })
        let notesAtLastStrike = Set(ec.ons.filter { $0.cable == 1 && $0.sample > 15_000 && $0.sample < 17_000 }.map { $0.note })
        XCTAssertGreaterThan(notesAtFirstStrike.count, 1, "the CHORD notes sound with the riff note"); XCTAssertEqual(notesAtFirstStrike, notesAtLastStrike, "every strike carries the full set")
        assertNothingLeftSounding(ec)
    }
    func testFXRatchStrikesCrossRenderWindowsWithNoStuckNotes() {
        for frames: UInt32 in [64, 256, 2048] {
            let e = fxRun(fxBox([fxLine(gate: 1.0)], fx: fxCells([(0, 0, 4), (0, 1, 3), (0, 2, 2)])), beats: 7.5, frames: frames)   // one pass over the eight columns
            assertNothingLeftSounding(e)
            XCTAssertEqual(fxSoundings(e, fxPoolNotes[0]).count, 4, "frames \(frames)")
        }
    }
    // ── REVIEW FIX ferry (2026-10-23): ratchets at fast steps, large buffers, and the document's default step rate ──
    /// `fxBox` with the scene's step rate and swing as parameters (the suite's own `fxBox` pins 1/8, which hid the cap's dependence on it).
    private func fxBoxScene(_ lines: [EuclidLine], fx: EuclideousFX, stepRate: StepRate, swing: Int = 50, ranks: [Int] = [1, 2, 3, 4, 5, 6, 7, 8]) -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks)
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = stepRate; sc.swing = swing
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi; st.euclideousFX = fx
        return SnapshotBuilder.build(from: st)
    }
    /// `fxRun` at a chosen tempo, returning the router too (for the flood governor's drop count).
    private func fxRunAt(_ box: SnapshotBox, beats: Double, frames: UInt32, tempo: Double) -> (e: RecordingEmitter, router: Router) {
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag(); let sr = 48_000.0
        let p = chord(fxPoolNotes); var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return (e, router)
    }
    // MARK: - FOURFOLD REEL LINK (2026-10-23): Fourfold's output on the tape

    /// Router → `ReelTap` → `ReelDeck` driven exactly as the Kernel drives them (`Kernel.swift` reel block): a pass is `8 × stepBeats × clockScale` beats, the deck files a pass when the next one starts, and the
    /// tap stamps every EMITTED message pass-relative. `perPass` counts what the render emitted in each pass's windows (the Kernel's own attribution), so a test can ask "did the deck keep all of it".
    private func fourfoldReel(_ box: SnapshotBox, beats: Double, frames: UInt32 = 512, tempo: Double = 120) -> (deck: ReelDeck, live: RecordingEmitter, perPass: [Int: Int], cycle: Double) {
        let live = RecordingEmitter(), deck = ReelDeck(), tap = ReelTap(), router = Router(); var diag = KernelDiag()
        let sr = 48_000.0, bps = tempo / 60.0 / sr
        let cycle = Double(Snap.cols) * box.stepBeats * box.clockScale
        let pool = chord(fxPoolNotes)
        tap.out = live; tap.deck = deck
        var lastPass = Int.min, fromStart = false, ts = 0.0
        var perPass: [Int: Int] = [:]
        while ts * bps < beats {
            let beat = ts * bps
            let pass = Int((beat / cycle).rounded(.down))
            deck.cycleBeats = cycle
            if pass != lastPass {
                if fromStart { deck.promote() }
                deck.startPass(pass: pass); lastPass = pass; fromStart = true
            }
            tap.recording = true; tap.base = beat; tap.beatsPerSample = bps; tap.cycleBeats = cycle; tap.windowStart = Int64(ts)
            let before = live.events.count
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: tap, diag: &diag)
            perPass[pass, default: 0] += live.events.count - before
            ts += Double(frames)
        }
        return (deck, live, perPass, cycle)
    }

    func testFourfoldOutputIsFiledOnTheCablesItWasRoutedTo() {
        // lane 1 → MAIN OUT A, lane 2 → MAIN OUT C; 1/8 scene rate ⇒ a 4-beat pass. 13 beats = three filed passes + the one in progress.
        let l1 = fxLine(gate: 0.5, emitter: 0b0001), l2 = fxLine(gate: 0.5, emitter: 0b0100)
        let r = fourfoldReel(fxBoxScene([l1, l2], fx: EuclideousFX(), stepRate: .r1_8), beats: 13)
        XCTAssertEqual(r.cycle, 4, accuracy: 1e-9)
        let passes = r.deck.passNumbers().filter { $0 >= 0 }
        XCTAssertEqual(passes, [0, 1, 2], "every completed pass is filed — the one still being played is not")
        for p in passes {
            XCTAssertTrue(r.deck.selectPass(p))
            let roll = r.deck.selectedRoll()
            XCTAssertFalse(roll.isEmpty, "pass \(p + 1) has notes")
            XCTAssertEqual(Set(roll.map { Int($0.cable) }), [1, 3], "lane 1's notes sit on A (cable 1), lane 2's on C (cable 3), nothing on B or D")
            let ex = r.deck.exportRangeEvents(fromPass: p, toPass: p, cables: [1, 2, 3, 4])
            let ons = ex.events.filter { $0.b0 & 0xF0 == 0x90 }.count, offs = ex.events.filter { $0.b0 & 0xF0 == 0x80 }.count
            XCTAssertEqual(ons, offs, "pass \(p + 1) exports every note-ON with its note-OFF — nothing stuck in the file")
            XCTAssertEqual(ex.totalBeats, 4, accuracy: 1e-9)
        }
    }

    func testFourfoldPassExportsOnlyTheSelectedOutputsAndConcatenatesAPassRange() {
        let l1 = fxLine(gate: 0.5, emitter: 0b0001), l2 = fxLine(gate: 0.5, emitter: 0b0010)
        let r = fourfoldReel(fxBoxScene([l1, l2], fx: EuclideousFX(), stepRate: .r1_8), beats: 13)
        let a = r.deck.exportRangeEvents(fromPass: 0, toPass: 1, cables: [1])
        let b = r.deck.exportRangeEvents(fromPass: 0, toPass: 1, cables: [2])
        XCTAssertFalse(a.events.isEmpty); XCTAssertFalse(b.events.isEmpty)
        XCTAssertEqual(a.totalBeats, 8, accuracy: 1e-9, "two passes of four beats, concatenated")
        XCTAssertTrue(a.events.allSatisfy { $0.b0 & 0x0F == 0 && $0.b1 >= 48 && $0.b1 <= 60 }, "only lane 1's notes (the pool's range) in A's file")
        XCTAssertEqual(a.events.count, b.events.count, "two identical lanes on two outputs ⇒ two files of the same length")
        let beats = a.events.map { $0.beat }
        XCTAssertEqual(beats, beats.sorted(), "events come out in time order across the pass boundary")
        XCTAssertGreaterThan(beats.last ?? 0, 4, "the second pass sits after the first")
    }

    func testABusyFourfoldPassKeepsEveryEventTheRenderEmitted() {
        // four lanes, each on its own output, 1/32 hits (8 a beat), three lit notes on top of the riff note, every column ratcheted ×3: far more than one pass of the 8×8 ever sounds.
        var lines: [EuclidLine] = []
        for i in 0..<4 {
            var l = fxLine(gate: 0.5, litNotes: 0b0000_0111); l.rate = .r1_32; l.steps = 16; l.pulses = 16; l.emitterMask = UInt8(1 << i)
            lines.append(l)
        }
        let fx = fxCells((0..<8).map { (0, $0, 3) })
        let r = fourfoldReel(fxBoxScene(lines, fx: fx, stepRate: .r1_8), beats: 13)
        let passes = r.deck.passNumbers().filter { $0 >= 0 }
        XCTAssertEqual(passes, [0, 1, 2])
        let emitted = r.perPass[1] ?? 0
        XCTAssertGreaterThan(emitted, 4096, "this load is past the old per-pass cap — the case the larger history exists for")
        XCTAssertLessThanOrEqual(emitted, ReelDeck.histCap, "and still inside the new one, so the whole pass is kept")
        let kept = r.deck.exportRangeEvents(fromPass: 1, toPass: 1, cables: [0, 1, 2, 3, 4]).events.count
        XCTAssertEqual(kept, emitted, "the filed pass holds every event the render emitted in it — no tail lost")
    }

    func testFXRatchStrikesAreCompleteAndEvenlySpacedAtEveryBufferSizeEvenWhenASlotIsShorterThanTheBuffer() {
        // all 8 columns hit (8 steps, 8 pulses); RATCH on column 0 only = note 48, once every 8 steps. The slot (rate ÷ n) drops under the buffer length long before 4096 frames.
        for (rate, tempo) in [(ArpRate.r1_16, 120.0), (.r1_16, 180.0), (.r1_32, 120.0)] {
            for n in [2, 3, 4] {
                var l = fxLine(gate: 0.5); l.rate = rate; l.steps = 8; l.pulses = 8
                let spb = 48_000.0 * 60.0 / tempo
                let lapBeats = 8 * rate.beats, slot = rate.beats / Double(n)
                let hits = Int((13.9 / lapBeats).rounded(.down)) + 1            // ratcheted hits that start before beat 13.9
                var want: [Double] = []
                for h in 0..<hits { for k in 0..<n { let t = Double(h) * lapBeats + Double(k) * slot; if t < 13.9 { want.append(t * spb) } } }
                for frames: UInt32 in [64, 512, 1024, 2048, 4096] {
                    let (e, _) = fxRunAt(fxBoxScene([l], fx: fxCells([(0, 0, n)]), stepRate: .r1_8), beats: 15, frames: frames, tempo: tempo)
                    let got = e.ons.filter { $0.cable == 1 && $0.note == 48 && Double($0.sample) < 13.9 * spb }.map { Double($0.sample) }.sorted()
                    XCTAssertEqual(got.count, want.count, "\(rate.rawValue) n\(n) @\(Int(tempo)) BPM, buffer \(frames): every strike sounds")
                    for (g, w) in zip(got, want) { XCTAssertEqual(g, w, accuracy: 3, "\(rate.rawValue) n\(n) @\(Int(tempo)), buffer \(frames): on its slot") }
                    assertNothingLeftSounding(e)
                }
            }
        }
    }
    func testFXRatchIsNotCappedByTheScenesDefaultStepRate() {
        // the document's default scene step is 1/2 (a 16-beat grid bar): the old "1/128 of the grid bar" cap held a 1/16 lane to 2 strikes and a 1/16T or 1/32 lane to none
        for stepRate in [StepRate.r1_2, .r1_4, .r1_8] {
            for (rate, name) in [(ArpRate.r1_16, "1/16"), (.r1_16t, "1/16T"), (.r1_32, "1/32")] {
                var l = fxLine(gate: 0.5); l.rate = rate; l.steps = 8; l.pulses = 8
                let (e, _) = fxRunAt(fxBoxScene([l], fx: fxCells([(0, 0, 4)]), stepRate: stepRate), beats: 1, frames: 256, tempo: 120)
                let first = e.ons.filter { $0.cable == 1 && $0.note == 48 && Double($0.sample) < rate.beats * 0.95 * 24_000 }.count
                XCTAssertEqual(first, 4, "\(name) lane, RATCH 4, scene step \(stepRate.rawValue)")
            }
        }
    }
    func testFXRatchCapFollowsTheTempoAndGatesNeverFallUnderFiveMilliseconds() {
        // 300 BPM: a 1/32 step is 25 ms, so RATCH 4 holds to 2 strikes (12.5 ms slots)
        var l = fxLine(gate: 0.1); l.rate = .r1_32; l.steps = 8; l.pulses = 8
        let (e, _) = fxRunAt(fxBoxScene([l], fx: fxCells([(0, 0, 4)]), stepRate: .r1_8), beats: 0.12, frames: 128, tempo: 300)
        let s = fxSoundings(e, 48)
        XCTAssertEqual(s.count, 2, "cap = floor(25 ms ÷ 10 ms) = 2")
        for snd in s {
            XCTAssertGreaterThanOrEqual(Double(snd.off ?? 0) - Double(snd.on), 0.005 * 48_000 - 2, "a 10% gate of a 12.5 ms slot is lifted to the 5 ms floor")
            XCTAssertLessThan(Double(snd.off ?? 0) - Double(snd.on), 0.0125 * 48_000, "…and still ends inside its own slot")
        }
    }
    func testFourLanesOfRatchetsOnOneOutputStaySoundingAndOnlyARunawayLoadIsGoverned() {
        func lanes(rate: ArpRate, lit: UInt8) -> [EuclidLine] {
            (0..<4).map { _ in var l = fxLine(gate: 0.5, litNotes: lit); l.rate = rate; l.steps = 8; l.pulses = 8; l.emitterMask = 0b0001; return l }
        }
        var every: [(Int, Int, Int)] = []; for c in 0..<8 { every.append((0, c, 4)) }
        // 4 lanes × 1/16 (4 hits a beat) × RATCH 4 = 64 note-ons a beat on output A: the old 48-a-beat budget dropped a quarter of them (132 of 516 in the review's probe)
        let ok = fxRunAt(fxBoxScene(lanes(rate: .r1_16, lit: 0), fx: fxCells(every), stepRate: .r1_8), beats: 8, frames: 512, tempo: 120)
        XCTAssertEqual(ok.router.floodDropped, 0, "a legitimate heavy ratchet load is never governed")
        let okCount = ok.e.ons.filter { $0.cable == 1 }.count
        let okWant = 4 * 8 * 4 * 4   // 4 lanes × 8 beats × 4 hits × 4 strikes
        XCTAssertGreaterThanOrEqual(okCount, okWant - 16, "…every strike of the four lanes sounds (less the run's last partial beat)")
        // 4 lanes × 1/32 (8 hits a beat) × RATCH 4 with three lit notes riding every strike = 384 a beat: a runaway, still governed — by the Euclideous budget
        let runaway = fxRunAt(fxBoxScene(lanes(rate: .r1_32, lit: 0b0000_0111), fx: fxCells(every), stepRate: .r1_8), beats: 4, frames: 512, tempo: 120)
        XCTAssertGreaterThan(runaway.router.floodDropped, 0, "an absurd load still trips the governor")
        var perBeat = [Int](repeating: 0, count: 4)
        for ev in runaway.e.ons where ev.cable == 1 { let b = Int(ev.sample / 24_000); if b >= 0 && b < 4 { perBeat[b] += 1 } }
        for (b, n) in perBeat.enumerated() { XCTAssertLessThanOrEqual(n, Router.euclideousFloodCapPerBeat + 4, "beat \(b): the budget holds (\(n) note-ons)") }
    }
    /// The NOTE offset (as a pool rank) each hit really plays, from the Router, and what the LANES roll predicts for the same lane (REVIEW FIX ferry 2026-10-23): one lane, every written rank 1, NOTE +1 on all eight columns.
    private func fxNotePassRanks(riffLength: Int, melody: [UInt8]?, rhythm: [UInt8]? = nil, lock: Bool = false, beats: Double = 16) -> (router: [Int], roll: [Int]) {
        var l = fxLine(gate: 0.5); l.steps = 4; l.pulses = 4; l.rate = .r1_4; l.riffLength = riffLength
        l.restartMelodyPasses = melody; l.restartRhythmBars = rhythm; l.riffLock = lock
        var cells: [(Int, Int, Int)] = []; for c in 0..<8 { cells.append((4, c, 1)) }
        let fx = fxCells(cells, passes: 8)
        let e = fxRun(fxBox([l], ranks: [1, 1, 1, 1, 1, 1, 1, 1], fx: fx), beats: beats, frames: 512)
        let router = fxOns(e).filter { $0.beat < beats - 0.1 }.map { (fxPoolNotes.firstIndex(of: $0.note) ?? -1) + 1 }
        let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8, fx: fx)!
        let roll = euclideousLaneRollHits(cfg: cfg, windowStart: 0, windowBeats: beats - 0.1, minGateBeats: 0.005, rankAt: { _, _ in 1 }).map { $0.rank }
        return (router, roll)
    }
    func testFXNotePassTheLanesRollPredictsExactlyWhatTheRouterPlaysAcrossRestartChains() {
        for (label, mel, rhy) in [("FREE", nil as [UInt8]?, nil as [UInt8]?), ("melody [1]", [1], nil), ("melody [2]", [2], nil), ("melody [3,1]", [3, 1], nil), ("rhythm [1] melody [2]", [2], [1])] {
            for len in [4, 8] {
                let r = fxNotePassRanks(riffLength: len, melody: mel, rhythm: rhy)
                XCTAssertEqual(r.roll, r.router, "\(label), riff length \(len): the roll draws what sounds")
                XCTAssertEqual(r.router.count, 16, "\(label), length \(len): sixteen hits in sixteen beats")
            }
        }
    }
    func testFXNotePassUnderAMelodyChainOfOneCountsLapsAndOtherwiseRiffCyclesFromTheMelodyOrigin() {
        // lap = 4 hits, riff length 4 (a cycle = a lap), NOTE +1 on every column, PASSES 8
        XCTAssertEqual(fxNotePassRanks(riffLength: 4, melody: nil).router, [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4], "FREE: a pass per riff cycle")
        XCTAssertEqual(fxNotePassRanks(riffLength: 4, melody: [2]).router, [1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 2, 2, 2, 2], "melody [2]: a restart returns the NOTE ladder to its first rung with the riff")
        XCTAssertEqual(fxNotePassRanks(riffLength: 4, melody: [1]).router, [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4], "melody [1] (the old LOCK): every riff cycle would be pass 0, so a pass is a LAP — the row still climbs (it was inert)")
        // a riff of 8 over a 4-hit lap: FREE climbs every 2 laps, melody [1] every lap
        XCTAssertEqual(fxNotePassRanks(riffLength: 8, melody: nil).router, [1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2])
        XCTAssertEqual(fxNotePassRanks(riffLength: 8, melody: [1]).router, [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4])
    }
    func testAStaleRiffLockNoLongerChangesTheNotePass() {
        // `riffLock` is decode-only since the restart-chains ferry, but the Router still read it for NOTE — an invisible, uneditable switch
        for len in [4, 8] {
            XCTAssertEqual(fxNotePassRanks(riffLength: len, melody: nil, lock: true).router, fxNotePassRanks(riffLength: len, melody: nil, lock: false).router, "riff length \(len): lock on or off, the same notes")
            XCTAssertEqual(fxNotePassRanks(riffLength: len, melody: [1], lock: true).router, fxNotePassRanks(riffLength: len, melody: [1], lock: false).router)
        }
    }
    func testFXRatchShapeSetsEachStrikesVelocityOnTheEchoRingPathAndTheInWindowPathAlike() {
        // lane VELOCITY 90; RATCH 4 on column 0 (note 48). A slow step (1/4) defers every repeat to the echo ring; a fast one at a 4096-frame buffer strikes them all in-window.
        for (rate, frames) in [(ArpRate.r1_4, UInt32(256)), (.r1_16, UInt32(4096)), (.r1_16, UInt32(128))] {
            for shape in 0..<4 {
                var l = fxLine(gate: 0.5, vel: 90); l.rate = rate; l.steps = 8; l.pulses = 8
                let (e, _) = fxRunAt(fxBoxScene([l], fx: fxCells([(0, 0, 4)], shape: UInt8(shape)), stepRate: .r1_8), beats: 4, frames: frames, tempo: 120)
                let first = e.ons.filter { $0.cable == 1 && $0.note == 48 && Double($0.sample) < rate.beats * 0.95 * 24_000 }.sorted { $0.sample < $1.sample }
                XCTAssertEqual(first.count, 4, "\(rate.rawValue) buffer \(frames) shape \(shape)")
                XCTAssertEqual(first.map { Int($0.vel) }, (0..<4).map { Int(euclideousRatchetStrikeVelocity(base: 90, shape: shape, k: $0, n: 4)) }, "\(rate.rawValue) buffer \(frames) shape \(shape): each strike at its own share")
                if shape == 0 { XCTAssertTrue(first.allSatisfy { $0.vel == 90 }, "FLAT is today's sound") }
            }
        }
        // the plain hits of the same run are untouched by the shape
        var l = fxLine(gate: 0.5, vel: 90); l.rate = .r1_4; l.steps = 8; l.pulses = 8
        let (e, _) = fxRunAt(fxBoxScene([l], fx: fxCells([(0, 0, 4)], shape: 3), stepRate: .r1_8), beats: 3, frames: 256, tempo: 120)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 && $0.note != 48 }.allSatisfy { $0.vel == 90 })
    }
    func testFXRatchShapeCarriesToATiedLastStrikeAndLeavesNothingSounding() {
        var l = fxLine(gate: 0.5, vel: 100); l.rate = .r1_4; l.steps = 8; l.pulses = 8
        let (e, _) = fxRunAt(fxBoxScene([l], fx: fxCells([(0, 0, 3), (2, 1, 1)], shape: 3), stepRate: .r1_8), beats: 3, frames: 256, tempo: 120)
        let strikes = e.ons.filter { $0.cable == 1 && $0.note == 48 }.sorted { $0.sample < $1.sample }.prefix(3).map { Int($0.vel) }
        XCTAssertEqual(Array(strikes), (0..<3).map { Int(euclideousRatchetStrikeVelocity(base: 100, shape: 3, k: $0, n: 3)) }, "RAMP: 45 → 72 → 100, the tied last strike at full")
        assertNothingLeftSounding(e)
    }
    func testFXRatchWithATieOnAFastStepExtendsTheLastStrikeAtEveryBufferSizeAndLeavesNothingSounding() {
        // RATCH 4 on column 0 and TIE on column 1 at 1/16: the tied hit carries the LAST strike on; at a 4096-frame buffer the early strikes are in-window
        for frames: UInt32 in [128, 1024, 4096] {
            var l = fxLine(gate: 0.5); l.rate = .r1_16; l.steps = 8; l.pulses = 8
            let (e, _) = fxRunAt(fxBoxScene([l], fx: fxCells([(0, 0, 4), (2, 1, 1)]), stepRate: .r1_8), beats: 3, frames: frames, tempo: 120)
            let s = fxSoundings(e, 48).filter { Double($0.on) < 6_000 }       // the first ratcheted hit (beat 0 …)
            XCTAssertEqual(s.count, 4, "buffer \(frames): four strikes")
            XCTAssertGreaterThan(Double(s[3].off ?? 0) - Double(s[3].on), Double(s[2].off ?? 0) - Double(s[2].on) + 2_000, "buffer \(frames): the last strike is held through the tied step")
            assertNothingLeftSounding(e)
        }
    }

    func testFXRatchedHitAfterALegatoHitClosesTheHeldNote() {
        // (legato from the lane's own gate 1.0 — the FX GATE row can no longer produce it; the held same-pitch note now runs from beat 0)
        let e = fxRun(fxBox([fxLine(gate: 1.0)], ranks: [1, 1, 1, 1, 1, 1, 1, 1], fx: fxCells([(0, 3, 2)])), beats: 5)
        assertNothingLeftSounding(e)
        let evs = e.events.filter { $0.cable == 1 && $0.note == 48 }
        // the legato note is still held at beat 3; the ratcheted hit closes it at its own sample, just before the new strike
        let on3 = evs.firstIndex { $0.status == 0x90 && abs(Double($0.sample) / 24_000 - 3) < 0.01 }!
        XCTAssertEqual(evs[on3 - 1].status, 0x80); XCTAssertEqual(evs[on3 - 1].sample, evs[on3].sample)
        var sounding = 0
        for ev in evs { sounding += ev.status == 0x90 ? 1 : -1; XCTAssertLessThanOrEqual(sounding, 1) }
    }

    // §15 GATE
    func testFXGateSetsTheNoteOffAtGPercentOfTheGapToTheNextHit() {
        let e = fxRun(fxBox([fxLine(gate: 0.5)], fx: fxCells([(1, 2, 25)])), beats: 5)
        assertNothingLeftSounding(e)
        XCTAssertEqual(Double(fxSoundings(e, fxPoolNotes[2])[0].off ?? 0) - Double(fxSoundings(e, fxPoolNotes[2])[0].on), 0.25 * 24_000, accuracy: 3, "GATE 25 → 25% of the gap")
        XCTAssertEqual(Double(fxSoundings(e, fxPoolNotes[1])[0].off ?? 0) - Double(fxSoundings(e, fxPoolNotes[1])[0].on), 0.5 * 24_000, accuracy: 3, "the lane's own 50% elsewhere")
    }
    // (testFXGate100ThenGate100RepeatingAPitchHoldsOneNote — retired 2026-10-20 with FX GATE 100 = LEGATO: a repeated pitch holding one note is the engine's lane-gate-1.0 legato, covered by
    // testEuclideousGateLegatoStuckNoteStress…, testRepeatAtLegatoSendsNoNewNoteOnForTheHeldPitch and testMixLegatoIsPerLayerInBothDirections.)
    func testFXGate50OnALaneAt100PercentEndsThatHitAtHalfItsGap() {
        let e = fxRun(fxBox([fxLine(gate: 1.0)], fx: fxCells([(1, 2, 50)])), beats: 5)
        assertNothingLeftSounding(e)
        let s = fxSoundings(e, fxPoolNotes[2])[0]
        XCTAssertEqual(Double(s.off ?? 0) - Double(s.on), 0.5 * 24_000, accuracy: 3)
        // the lane's legato note from the hit before is closed 10 ms after hit 2 (a different pitch), as unmatched pitches always are
        XCTAssertEqual(Double(fxSoundings(e, fxPoolNotes[1])[0].off ?? 0), 2 * 24_000 + 480, accuracy: 6)
    }
    // (testFXGate100OnALaneAt80Percent… — retired 2026-10-20 with FX GATE 100 = LEGATO: "a held legato pitch the next hit strikes again never overlaps itself" is covered WITHOUT any FX by
    // `fxRestrikeLine` / the MIX per-layer-gate tests.)
    func testFXTieExtensionUsesTheHitsEffectiveGate() {
        // GATE 50 on hit 1 and TIE on hit 2: gap up to the tied hit in full (1 beat) + 50% × the extension (1 beat) = 1.5 beats
        let e = fxRun(fxBox([fxLine(gate: 0.9)], fx: fxCells([(1, 1, 50), (2, 2, 1)])), beats: 5)
        assertNothingLeftSounding(e)
        let s = fxSoundings(e, fxPoolNotes[1])[0]
        XCTAssertEqual(Double(s.off ?? 0) - Double(s.on), 1.5 * 24_000, accuracy: 6)
    }

    // §15 TIE
    func testFXTieGivesTheSameNoteOnAndOffTimesAsARestWithOnRestTie() {
        // A: column 3 is a written REST and the lane's ON REST is TIE.  B: column 3 is a real rank with an FX TIE cell and the lane's ON REST is the default SKIP.
        let a = fxRun(fxBox([fxLine(gate: 0.5, onRest: .tie)], ranks: [1, 2, 3, 0, 5, 6, 7, 8]), beats: 8.5)
        let b = fxRun(fxBox([fxLine(gate: 0.5)], ranks: [1, 2, 3, 4, 5, 6, 7, 8], fx: fxCells([(2, 3, 1)])), beats: 8.5)
        XCTAssertEqual(fxStream(a), fxStream(b), "a tied hit and a tied rest are the same wire")
        assertNothingLeftSounding(b)
        // the note before the tie really did carry on through it: gap up to the tied hit in full + 50% × the extension
        let held = fxSoundings(b, fxPoolNotes[2])[0]
        XCTAssertEqual(Double(held.off ?? 0) - Double(held.on), (1 + 0.5) * 24_000, accuracy: 6)
    }
    func testFXTiesChainAndATieAfterARatchetExtendsTheLastStrike() {
        let chain = fxRun(fxBox([fxLine(gate: 0.5)], fx: fxCells([(2, 2, 1), (2, 3, 1)])), beats: 6.5)
        let h = fxSoundings(chain, fxPoolNotes[1])[0]
        XCTAssertEqual(Double(h.off ?? 0) - Double(h.on), (1 + 0.5 * 2) * 24_000, accuracy: 8, "two ties in a row: the gap to the next hit in full + 50% of the 2-beat extension")
        XCTAssertEqual(fxOns(chain).count, 7 - 2, "hits at beats 0…6, no note-on at the two tied ones")
        assertNothingLeftSounding(chain)
        // RATCH 2 on hit 1, TIE on hit 2: strike 0 unchanged (a quarter beat), the LAST strike carries the tie
        let r = fxRun(fxBox([fxLine(gate: 0.5)], fx: fxCells([(0, 1, 2), (2, 2, 1)])), beats: 4.5)
        assertNothingLeftSounding(r)
        let s = fxSoundings(r, fxPoolNotes[1])
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(Double(s[0].off ?? 0) - Double(s[0].on), 0.5 * 12_000, accuracy: 4, "earlier strikes are unchanged: gate × slot")
        XCTAssertEqual(Double(s[1].off ?? 0) - Double(s[1].on), (24_000 - 12_000) + 0.5 * 24_000, accuracy: 8, "the last strike: the gap left to the next hit in full + gate × the 1-beat tie extension")
    }
    func testFXTieAfterALegatoHitKeepsTheNoteSoundingAndAFirstHitTieIsSilent() {
        // (legato from the lane's own gate 1.0 — the FX GATE row can no longer produce it)
        let e = fxRun(fxBox([fxLine(gate: 1.0)], fx: fxCells([(2, 2, 1)])), beats: 5.5)
        assertNothingLeftSounding(e)
        let held = fxSoundings(e, fxPoolNotes[1])[0]
        XCTAssertEqual(Double(held.on), 24_000, accuracy: 3)
        XCTAssertEqual(Double(held.off ?? 0), 3 * 24_000 + 480, accuracy: 8, "still sounding through the tied hit; closed 10 ms after the next real hit")
        // a TIE on the very first hit after a transport start has nothing to carry on: silent
        let first = fxRun(fxBox([fxLine(gate: 0.5)], fx: fxCells([(2, 0, 1)])), beats: 2.5)
        XCTAssertEqual(fxOns(first).first.map { Int($0.beat.rounded()) }, 1, "no note-on at beat 0")
        XCTAssertEqual(fxOns(first).count, 2)
        assertNothingLeftSounding(first)
    }
    func testFXTieDoesNotApplyToALaneItsRowIsOffForAndStopsEveryOtherRowOnItsHit() {
        // two lanes (A and B): TIE only for lane 1; lane 2 still plays that hit — with its RATCH
        var l1 = fxLine(gate: 0.5, emitter: 0b0001), l2 = fxLine(gate: 0.5, emitter: 0b0010)
        l1.target = 0; l2.target = 0
        let fx = fxCells([(2, 2, 1), (0, 2, 3), (3, 2, 120)], lanes: [2: 0b0001])
        let e = fxRun(fxBox([l1, l2], fx: fx), beats: 4.5)
        XCTAssertEqual(fxOns(e, cable: 1).filter { abs($0.beat - 2) < 0.05 }.count, 0, "lane 1 is tied: no strike, and its RATCH/VEL cells did nothing on that hit")
        XCTAssertEqual(fxOns(e, cable: 2).filter { $0.beat > 1.99 && $0.beat < 2.9 }.count, 3, "lane 2 (TIE off for it) plays the hit, ratcheted")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 && $0.sample >= 47_990 && $0.sample < 70_000 }.allSatisfy { $0.vel == 120 })
        assertNothingLeftSounding(e)
    }

    // §15 VEL
    func testFXVelOverridesTheRiffNoteAndOffsetsTheLitNotesAndClamps() {
        let e = fxRun(fxBox([fxLine(vel: 90)], fx: fxCells([(3, 1, 110), (3, 2, 1), (3, 3, 127)])), beats: 4.5)
        let v = fxOns(e).map { $0.vel }
        XCTAssertEqual(v, [90, 110, 1, 127, 90], "the struck velocity equals the override; clamped to 1…127; the lane's VELOCITY elsewhere")
        // lit notes: VEL v + the NOTES VEL bar's offset (notesVelocity − VEL = −20)
        var l = fxLine(vel: 100, litNotes: 0b1); l.notesVelocity = 80
        let lit = fxRun(fxBox([l], ranks: [3, 3, 3, 3, 3, 3, 3, 3], fx: fxCells([(3, 1, 110), (3, 2, 30), (3, 3, 127)])), beats: 4.5)
        func lit48(_ beat: Int) -> UInt8? { lit.ons.first { $0.cable == 1 && $0.note == 48 && abs(Double($0.sample) / 24_000 - Double(beat)) < 0.05 }?.vel }
        func riff(_ beat: Int) -> UInt8? { lit.ons.first { $0.cable == 1 && $0.note == 52 && abs(Double($0.sample) / 24_000 - Double(beat)) < 0.05 }?.vel }
        XCTAssertEqual(lit48(0), 80); XCTAssertEqual(riff(0), 100, "no FX: lit notes keep their own velocity")
        XCTAssertEqual(riff(1), 110); XCTAssertEqual(lit48(1), 90, "110 − 20")
        XCTAssertEqual(riff(2), 30); XCTAssertEqual(lit48(2), 10)
        XCTAssertEqual(riff(3), 127); XCTAssertEqual(lit48(3), 107, "127 − 20")
    }

    // §15 CC
    private func ccEvents(_ e: RecordingEmitter) -> [(sample: Int64, cable: UInt8, chan: UInt8, cc: UInt8, value: UInt8)] {
        e.events.filter { $0.status == 0xB0 && $0.note != 123 }.map { ($0.sample, $0.cable, $0.chan, $0.note, $0.vel) }
    }
    func testFXCCSendsOnceBeforeTheNoteOnOnEveryChannelAndBothCables() {
        let e = fxRun(fxBox([fxLine(gate: 0.5)], fx: fxCells([(5, 1, 20)]), buses: [.a]), beats: 3.5)
        let cc = ccEvents(e)
        XCTAssertEqual(cc.count, 2, "one message per hit, on the bus's own cable and the ALL cable")
        XCTAssertEqual(Set(cc.map { $0.cable }), [0, 1]); XCTAssertTrue(cc.allSatisfy { $0.cc == 74 && $0.value == 20 && $0.chan == 0 })
        XCTAssertTrue(cc.allSatisfy { abs(Double($0.sample) / 24_000 - 1) < 0.01 }, "at the hit's own sample")
        // …and ahead of the note-on at that sample, on each cable
        for cable: UInt8 in [0, 1] {
            let evs = e.events.filter { $0.cable == cable && abs(Double($0.sample) / 24_000 - 1) < 0.01 }
            let ccIdx = evs.firstIndex { $0.status == 0xB0 }!, onIdx = evs.firstIndex { $0.status == 0x90 }!
            XCTAssertLessThan(ccIdx, onIdx, "cable \(cable): CC before the note-on")
            XCTAssertEqual(evs[ccIdx].sample, evs[onIdx].sample, "cable \(cable): the CC carries the note-on's OWN sample, not one beside it")
        }
        // the channel is the bus's stamp — the SAME one its notes use (here channel 1 → wire 0)
        XCTAssertEqual(e.ons.first { $0.cable == 1 }?.chan, cc.first?.chan)
        // a hit routed to ALL FOUR outputs sends the CC on each of their cables (and each one's own stamped channel) plus the ALL cable
        let all = fxRun(fxBox([fxLine(gate: 0.5)], fx: fxCells([(5, 1, 20)])), beats: 1.5)
        XCTAssertEqual(Set(ccEvents(all).map { $0.cable }), [0, 1, 2, 3, 4])
        XCTAssertEqual(Set(ccEvents(all).filter { $0.cable != 0 }.map { $0.chan }), [0, 1, 2, 3], "each bus on its own channel stamp")
    }
    func testFXCCOnlyForTheLanesTheRowIsOnForAndOnTheirOwnBuses() {
        let l1 = fxLine(emitter: 0b0001), l2 = fxLine(emitter: 0b0010)
        let e = fxRun(fxBox([l1, l2], fx: fxCells([(5, 1, 20)], lanes: [5: 0b0010])), beats: 3.5)
        XCTAssertEqual(Set(ccEvents(e).map { $0.cable }), [0, 2], "lane 2 → bus B's cable 2 and the ALL cable; nothing on cable 1")
        XCTAssertEqual(ccEvents(e).count, 2)
    }
    func testFXCCSendsOncePerRatchetedHitAndOnAHitThatCarriesOnLegato() {   // (legato from the lane's own gate 1.0 since 2026-10-20)
        let r = fxRun(fxBox([fxLine(gate: 0.5)], fx: fxCells([(0, 1, 4), (5, 1, 50)])), beats: 3.5)
        XCTAssertEqual(ccEvents(r).filter { $0.cable == 1 }.count, 1, "a ratcheted hit sends it once, before its first strike")
        XCTAssertEqual(fxSoundings(r, fxPoolNotes[1]).count, 4)
        // legato: the lane's gate 1.0 with hits 1 and 2 on the same pitch → hit 2's pitch carries on (no new note-on) yet its CC still goes out
        let l = fxRun(fxBox([fxLine(gate: 1.0)], ranks: [2, 1, 1, 3, 4, 5, 6, 7], fx: fxCells([(5, 2, 33)])), beats: 4.5)
        XCTAssertEqual(fxSoundings(l, 48).count, 1, "the second hit carried the pitch on")
        XCTAssertEqual(ccEvents(l).filter { $0.cable == 1 && $0.value == 33 }.count, 1, "…and still sent its CC")
    }
    func testFXCCBaseSendsOnHitsThatApplyButHaveAnEmptyCellAndNothingWhenBaseIsNone() {
        let withBase = fxRun(fxBox([fxLine()], fx: fxCells([(5, 2, 20)], ccBase: 64)), beats: 3.5)
        XCTAssertEqual(ccEvents(withBase).filter { $0.cable == 1 }.map { $0.value }, [64, 64, 20, 64].prefix(4).map { $0 }.prefix(4).map { $0 }, "BASE on every riff hit, the cell's own value at its column")
        let noBase = fxRun(fxBox([fxLine()], fx: fxCells([(5, 2, 20)])), beats: 3.5)
        XCTAssertEqual(ccEvents(noBase).filter { $0.cable == 1 }.map { $0.value }, [20], "BASE none: only the cell")
    }
    func testFXCCNothingForMutedTiedRestOrSilentHitsAndTheControllerClamps() {
        // a rest column (written 0) and a tied hit: neither sends, even with a BASE
        let e = fxRun(fxBox([fxLine()], ranks: [1, 0, 3, 4, 5, 6, 7, 8], fx: fxCells([(2, 2, 1), (5, 3, 9)], ccBase: 64)), beats: 4.5)
        let sends = ccEvents(e).filter { $0.cable == 1 }.map { Int(Double($0.sample) / 24_000 + 0.5) }
        XCTAssertEqual(sends, [0, 3, 4], "beat 1 is a rest and beat 2 is tied: no CC at either")
        // a LANES-muted hit sends nothing: mute every mute-cell of lane 1 (PASS-sized cells = a 4-beat pass; beats 4… are muted)
        var l = fxLine(); l.muteCells16 = 0b1111_1111_1111_1101; l.muteUnit = EuclideousMuteUnit.pass.rawValue
        let m = fxRun(fxBox([l], fx: fxCells([], ccBase: 64)), beats: 8.5)
        XCTAssertEqual(ccEvents(m).filter { $0.cable == 1 }.map { Int(Double($0.sample) / 24_000 + 0.5) }, [0, 1, 2, 3, 8], "the muted pass (beats 4–7) sends nothing")
        // the controller number clamps to 0…119
        XCTAssertEqual(fxRun(fxBox([fxLine()], fx: fxCells([(5, 0, 5)], ccNumber: 250)), beats: 0.5).events.first { $0.status == 0xB0 }?.note, 119)
    }
    func testFXLaneWithItsRiffOffIgnoresEveryRow() {
        let fx = fxCells([(0, 0, 4), (1, 0, 5), (2, 1, 1), (3, 0, 127), (4, 0, 3), (5, 0, 9)], ccBase: 64)
        var l = fxLine(litNotes: 0b1, riffOn: false)
        let e = fxRun(fxBox([l], fx: fx), beats: 3.5)
        XCTAssertEqual(fxOns(e).count, 4, "one lit-note strike per hit — nothing ratcheted, nothing tied")
        XCTAssertTrue(fxOns(e).allSatisfy { $0.vel == 90 && $0.note == 48 })
        XCTAssertTrue(ccEvents(e).isEmpty)
        l.riffOn = true
        XCTAssertGreaterThan(fxOns(fxRun(fxBox([l], fx: fx), beats: 3.5)).count, 4, "…and with the riff on the same rows act")
    }

    // §15 determinism + stuck notes
    func testFXAllSixRowsAreIdenticalAtEveryBufferSizeAndAfterATransportRestart() {
        let fx = fxCells([(0, 1, 3), (1, 2, 100), (2, 3, 1), (3, 4, 110), (4, 5, 1), (5, 6, 40), (0, 7, 2), (1, 0, 25)], passes: 4, ccBase: 64)
        var l = fxLine(gate: 0.8); l.litNotes = 0b101
        let box = fxBox([l, fxLine(gate: 0.5, emitter: 0b0010)], fx: fx)
        // `sampleOf` TRUNCATES a beat-derived sample, so an event that lands exactly on a sample boundary can land one sample either side depending on the window it
        // is computed in (pre-existing, engine-wide; not FX). So "identical at every buffer size" means: the same events, in the same order, on the same cables and
        // channels, each within ONE sample — checked over a span that ends at an arbitrary sample (not on a hit boundary, where one run could include an event the
        // other excludes).
        let inside: Int64 = 722_952
        func core(_ e: RecordingEmitter) -> [[Int64]] { fxStream(e).filter { $0[0] >= 0 && $0[0] < inside } }   // (the final stop window's flush carries a negative sentinel sample)
        func same(_ a: [[Int64]], _ b: [[Int64]], _ msg: String) {
            XCTAssertEqual(a.count, b.count, msg)
            for (x, y) in zip(a, b) { XCTAssertEqual(Array(x.dropFirst()), Array(y.dropFirst()), msg); XCTAssertLessThanOrEqual(abs(x[0] - y[0]), 1, msg) }
        }
        let ref = core(fxRun(box, beats: 32, frames: 64))
        XCTAssertGreaterThan(ref.count, 200)
        for frames: UInt32 in [256, 1024] { same(core(fxRun(box, beats: 32, frames: frames)), ref, "buffer size \(frames)") }
        // a transport restart replays the same stream from beat 0 (compare the replay with sample times taken relative to where it began)
        var restarts: [Int64] = []
        let again = fxRun(box, beats: 32, frames: 256, restartAt: [20], restartSamples: &restarts)
        let origin = restarts[0]
        let replay = fxStream(again).filter { $0[0] >= origin && $0[0] - origin < inside }.map { [$0[0] - origin] + Array($0.dropFirst()) }
        same(replay, ref, "after a restart the output is the same as from a fresh start")
    }
    func testFXStressCyclingTieGate100RatchAndLanesMuteWithTransportRestartsLeavesNothingSounding() {
        var l1 = fxLine(gate: 0.8, emitter: 0b0001); l1.litNotes = 0b11; l1.muteCells16 = 0b1010_1010_1010_1010; l1.muteUnit = EuclideousMuteUnit.fourSteps.rawValue
        var l2 = fxLine(gate: 1.0, emitter: 0b0010); l2.muteCells16 = 0b1111_0000_1111_0000; l2.muteUnit = EuclideousMuteUnit.step.rawValue
        let fx = fxCells([(2, 1, 1), (1, 2, 100), (0, 3, 4), (2, 4, 1), (1, 5, 100), (0, 6, 3), (1, 7, 100), (0, 0, 2), (2, 2, 1)], ccBase: 10)
        for frames: UInt32 in [64, 512, 2048] {
            let e = fxRun(fxBox([l1, l2], ranks: [1, 1, 2, 2, 3, 3, 4, 4], fx: fx), beats: 60, frames: frames, restartAt: [7.3, 15.9, 16.2, 31.7, 44.4])
            assertNothingLeftSounding(e)
            XCTAssertGreaterThan(e.ons.count, 100)
            for note in fxPoolNotes { for cable in [UInt8(1), 2] {
                var sounding = 0
                for ev in e.events where ev.cable == cable && ev.note == note && (ev.status == 0x90 || ev.status == 0x80) {
                    sounding += ev.status == 0x90 ? 1 : -1
                    XCTAssertGreaterThanOrEqual(sounding, 0)
                }
            } }
        }
    }

    // ── ADVERSARIAL REVIEW (2026-10-19): NOTE's pass index END TO END through the real Router. The §15 pass-index tests run the pure function against its own simulator;
    //    these pin the WIRING (which ordinal, tick, grid and localT the Router hands it) with a small independent model of the expected pitches.
    private func fxSparseLane(dir: RiffDir = .forward, lock: Bool = false, advStep: Bool = false, stride: Int? = nil, melodyMask: UInt16 = 0, rhythmMask: UInt16 = 0) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 3, steps: 8)
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = .r1_8; l.useRiff = true; l.litNotes = 0; l.riffOn = true; l.sourceMode = .midi
        l.riffLength = 8; l.notesOn = true; l.riffOnRest = .skip
        l.riffDir = dir; l.riffLock = lock; l.riffAdvanceStep = advStep
        if let stride { l.riffStride = stride }
        if melodyMask != 0 || rhythmMask != 0 {
            l.restartMelodyMask16 = melodyMask; l.restartRhythmMask16 = rhythmMask; l.restartUnit = EuclideousRestartUnit.pass.rawValue
        }
        return l
    }
    /// The 3-of-8 lane's hit ticks (steps of 1/8 = 0.5 beat): 0, 3, 6 of every lap of 8.
    private func fxHitTicks(upToBeat b: Double) -> [Int] { (0..<Int(b / 0.5) + 1).filter { [0, 3, 6].contains($0 % 8) && Double($0) * 0.5 < b } }
    private let fxTriad: [Int] = [48, 51, 55]
    private func fxTriadPitch(_ rank: Int) -> Int { let i = rank - 1; return fxTriad[((i % 3) + 3) % 3] + 12 * Int((Double(i) / 3).rounded(.down)) }
    /// column read at ordinal `o` for a FWD walk of LENGTH 8, STRIDE 1; PEND (period 14) and PING (period 16) as `riffStepAt` documents
    private func fxColumn(dir: RiffDir, ord o: Int) -> Int {
        switch dir {
        case .pendulum: let k = o % 14; return k < 8 ? k : 14 - k
        case .pingpong: let k = o % 16; return k < 8 ? k : 15 - k
        default: return o % 8
        }
    }
    private func fxNoteWire(_ l: EuclidLine, cells: [(row: Int, col: Int, v: Int)], beats: Double) -> [(beat: Double, note: Int)] {
        let ranks = [4, 2, 3, 1, 5, 6, 7, 8]
        let e = fxRun(fxBox([l], ranks: ranks, fx: fxCells(cells, passes: 4)), beats: beats, pool: fxTriad.map { UInt8($0) })
        return fxOns(e).map { ($0.beat, Int($0.note)) }
    }

    func testFXNoteLockOnASparseLaneClimbsOneStepPerLapAndRereadsTheSameOffsetWithinALap() {
        // LOCK: the riff goes back to its first position at every lap start, so hit j of lap L reads column j. A NOTE cell on column 0 is read once per lap — p = the lap.
        // RESTART CHAINS (2026-10-19): `riffLock` itself is retired (§7) — "LOCK" is now a melody chain of [1]
        // (§4.7), migrated-and-pinned here (`migratedLine`) to simulate the AVC resync tick a bare-Router test
        // never runs (§12). FX's own NOTE-pass index is untouched (still reads the preserved grid/`locked`
        // exclusively) — this only restores the real riff ordinal's own restart, which FX's pass reads downstream.
        let got = fxNoteWire(migratedLine(fxSparseLane(lock: true)), cells: [(4, 0, 1)], beats: 4 * 6 + 1)
        let col0 = got.filter { abs($0.beat.truncatingRemainder(dividingBy: 4)) < 0.01 || abs($0.beat.truncatingRemainder(dividingBy: 4) - 4) < 0.01 }.map { $0.note }
        XCTAssertEqual(Array(col0.prefix(6)), (0..<6).map { fxTriadPitch(4 + ($0 % 4)) }, "laps 0…5: C4 E♭4 G4 C5 C4 E♭4")
        // a NOTE cell on column 1 (hit 2 of the lap) climbs on the same per-lap clock, not per hit
        let got1 = fxNoteWire(migratedLine(fxSparseLane(lock: true)), cells: [(4, 1, 2)], beats: 4 * 5 + 2)
        let col1 = got1.filter { abs($0.beat.truncatingRemainder(dividingBy: 4) - 1.5) < 0.01 }.map { $0.note }
        XCTAssertEqual(Array(col1.prefix(5)), (0..<5).map { fxTriadPitch(2 + 2 * ($0 % 4)) })
    }
    func testFXNoteFreeAdvStepOnASparseLaneCountsStepsNotHits() {
        // ADV STEP: the riff ordinal is the STEP count, so column 3 is read at the lane's step 3 of every 8 — and p = floor(step / 8) = the lap
        let got = fxNoteWire(fxSparseLane(advStep: true), cells: [(4, 3, 1)], beats: 4 * 5 + 2)
        let at = got.filter { abs($0.beat.truncatingRemainder(dividingBy: 4) - 1.5) < 0.01 }.map { $0.note }       // step 3 = beat 1.5 of each lap
        XCTAssertEqual(Array(at.prefix(5)), (0..<5).map { fxTriadPitch(1 + ($0 % 4)) }, "column 3 is written rank 1 here: laps climb C3 E♭3 G3 C4 C3")
        // and the hit-counted lane (ADV HIT) is a different clock: column 3 is the 4th HIT, read every 8 hits (= 8/3 laps), p = floor(hit / 8)
        let hit = fxNoteWire(fxSparseLane(), cells: [(4, 3, 1)], beats: 4 * 14)
        let ticks = fxHitTicks(upToBeat: 4 * 14)
        var expected: [Int] = []
        for (o, _) in ticks.enumerated() where o % 8 == 3 { expected.append(fxTriadPitch(1 + (o / 8) % 4)) }
        let plays = zip(ticks.enumerated(), hit).filter { $0.0.offset % 8 == 3 }.map { $0.1.note }
        XCTAssertEqual(plays, expected, "ADV HIT counts hits")
    }
    func testFXNoteOnAThreeHitLaneAdvHitIsTheSpecsFourFiveSixSevenFourExample() {
        // §15 / §7.4: a 3-hit lane, FREE, FWD, STRIDE 1, LENGTH 8, ADV HIT; NOTE +1, PASSES 4 on a column written rank 4 → ranks 4,5,6,7,4 on its first five plays
        var l = fxSparseLane()
        let ranks = [1, 1, 1, 4, 1, 1, 1, 1]
        let e = fxRun(fxBox([l], ranks: ranks, fx: fxCells([(4, 3, 1)], passes: 4)), beats: 4 * 13, pool: fxTriad.map { UInt8($0) })
        let ticks = fxHitTicks(upToBeat: 4 * 13)
        let ons = fxOns(e)
        let col3 = ons.enumerated().filter { $0.offset % 8 == 3 }.map { Int($0.element.note) }
        XCTAssertEqual(Array(col3.prefix(5)), [4, 5, 6, 7, 4].map { fxTriadPitch($0) })
        XCTAssertGreaterThanOrEqual(ons.count, ticks.count)
        l.riffOn = false
    }
    func testFXNotePendAndPingUseTheirFullPeriodsThroughTheRouter() {
        for (dir, period) in [(RiffDir.pendulum, 14), (RiffDir.pingpong, 16)] {
            let got = fxNoteWire(fxSparseLane(dir: dir), cells: (0..<8).map { (4, $0, 1) }, beats: 4 * 40)   // every column carries NOTE +1
            let ranks = [4, 2, 3, 1, 5, 6, 7, 8]
            for (o, hit) in got.enumerated() {
                let col = fxColumn(dir: dir, ord: o)
                XCTAssertEqual(hit.note, fxTriadPitch(ranks[col] + (o / period) % 4), "\(dir) ordinal \(o) column \(col)")
                if hit.note != fxTriadPitch(ranks[col] + (o / period) % 4) { break }
            }
        }
    }
    // RETIRED (2026-10-19, restart-chains ferry): this test's mark (cell 3 of a 16-cell window ⇒ a restart
    // every 16 passes) and its "first window's carried, NEGATIVE origin" premise have no chain equivalent —
    // a chain restarts on a ≤4-link cycle from {1,2,3,4,6,8} passes/bars (16 isn't in that set and isn't
    // reachable as a short cycle either), and §12.6 is explicit that beat 0 is always a restart in the new
    // model, so there is no "previous window" origin to carry in from before it (same retirement as
    // `testGridFirstWindowRunsFromANegativeOriginDeterministically`, above). `riffLock`'s OWN substance (every
    // pass restarts) is still covered, converted, by `testFXNoteLockOnASparseLaneClimbsOneStepPerLapAnd
    // RereadsTheSameOffsetWithinALap` just above. Not ported.

    func testFXCCIsNotSentForAHitWhoseEveryPitchIsDroppedOutsideMidiRange() {
        // one note held (C4), rank 1 on every column, a NOTE +3 on every column, PASSES 8: passes 0 and 1 sound (60, 96); from pass 2 the rank (7, 10, …) is beyond MIDI 127 and
        // `strikeChord` drops it — a hit that sounds nothing sends no CC (§8.4)
        let l = fxLine()
        let cells: [(row: Int, col: Int, v: Int)] = (0..<8).flatMap { [(4, $0, 3), (5, $0, 20)] }
        let e = fxRun(fxBox([l], ranks: [1, 1, 1, 1, 1, 1, 1, 1], fx: fxCells(cells, passes: 8)), beats: 130, pool: [60])
        let ons = e.ons.filter { $0.cable == 1 }.count
        let ccs = e.events.filter { $0.status == 0xB0 && $0.cable == 1 }.count
        XCTAssertGreaterThan(ons, 8); XCTAssertLessThan(ons, 130, "some hits really were dropped (the test would pass vacuously otherwise)")
        XCTAssertEqual(ccs, ons, "one CC per hit that sounds, none for a dropped one")
        assertNothingLeftSounding(e)
    }

    func testFXTieCarriesTheNoteStruckJustBeforeInPlayOrderWhateverWayTheMelodyOrTheLaneRuns() {
        // "The note before" means in TIME: the hit that played just before the tied one, however the riff walks (FWD / REV / PENDULUM / PONG) and however the lane's pattern runs
        // (FWD / BKW / PING-PONG). A: columns 2 and 5 written as RESTS with ON REST = TIE. B: the same columns real, with FX TIE cells and ON REST at its default.
        for riffDir in [RiffDir.forward, .reverse, .pendulum, .pingpong] {
            for laneDir in [EuclidDir.fwd, .bkw, .pingpong] {
                func lane(_ onRest: EuclidRiffOnRest) -> EuclidLine {
                    var l = fxLine(gate: 0.5, onRest: onRest); l.riffDir = riffDir; l.direction = laneDir; return l
                }
                let a = fxRun(fxBox([lane(.tie)], ranks: [1, 2, 0, 4, 5, 0, 7, 8]), beats: 40.5)
                let b = fxRun(fxBox([lane(.skip)], ranks: [1, 2, 3, 4, 5, 6, 7, 8], fx: fxCells([(2, 2, 1), (2, 5, 1)])), beats: 40.5)
                let tag = "riff \(riffDir.rawValue) / lane \(laneDir.rawValue)"
                XCTAssertEqual(fxStream(a), fxStream(b), "\(tag): a tied hit and a tied rest are the same wire")
                assertNothingLeftSounding(b)
                // independent check on B: every hit beat with no note-on is a tied hit; the note struck most recently BEFORE it is still sounding through it
                let ons = b.ons.filter { $0.cable == 1 }
                let hitBeats = Array(0...40)
                let silent = hitBeats.filter { beat in !ons.contains { abs(Double($0.sample) / 24_000 - Double(beat)) < 0.01 } }
                XCTAssertFalse(silent.isEmpty, "\(tag): some hits were tied")
                for t in silent {
                    let tSample = Int64(t * 24_000)
                    guard let prev = ons.last(where: { $0.sample < tSample - 100 }) else { continue }       // nothing before it ⇒ a first-hit tie, silent (tested elsewhere)
                    let off = fxSoundings(b, prev.note).last(where: { $0.on == prev.sample })?.off ?? 0
                    XCTAssertGreaterThan(off, tSample, "\(tag): the note struck before the tie at beat \(t) still sounds through it")
                }
            }
        }
    }

    // ── VIDEO INVESTIGATION (2026-10-19): the yellow lane's 5th step stayed silent. Reproduction of its configuration: 4 hits in 8 steps at 1/2, ADV STEP, riff [1,1,1,5,1,6,4,1],
    //    riff GATE 100% (legato), CHORDS source changing every 8 beats (2 bars) — so a chord change lands exactly on the lane's hits at steps 1 and 5.
    private func chordsBox(gate: Double) -> (SnapshotBox, SnapParams) {
        var l = EuclidLine(target: 0, pulses: 4, steps: 8)
        l.gate = gate; l.velocityAbsolute = 100; l.rate = .r1_2; l.useRiff = true; l.litNotes = 0; l.riffOn = true; l.sourceMode = .chords
        l.riffLength = 8; l.notesOn = true; l.riffOnRest = .skip; l.riffAdvanceStep = true
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 5, 1, 6, 4, 1])
        c.paramsA.euclidLines = [l]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.c])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .chords
        var ch = MachineParams(); ch.chordsRate = .r2_1; ch.chordsSteps = 4; ch.chordsDegrees = [0, 5, 3, 4]
        st.euclideousChords = ch
        let box = SnapshotBuilder.build(from: st)
        return (box, box.cells[Snap.euclideousRow].procs[0])
    }

    /// The pitch the riff rank has under the chord that is current AT `hitBeat` — the oracle (the chord function itself, asked at the hit's own beat).
    private func chordsIdealNote(_ p: SnapParams, beat hitBeat: Double, rank: Int) -> Int {
        let ch = chordSeqNotes(beat: hitBeat, p, keyRoot: p.euclideousChordKeyRoot, keyTones: p.euclideousChordKeyTones, followNote: nil)
        return ch[(rank - 1) % ch.count] + 12 * ((rank - 1) / ch.count)
    }
    func testAHitExactlyOnAChordChangeReadsTheNewChordAtAnyBufferSize() {
        // Video investigation 2026-10-19: with the pool built once per window at its START, a hit landing exactly on a chord change read the PREVIOUS chord. Chord changes every
        // 8 beats; a 1/2-note lane (hits at beats 0, 4, 8, 12 of a 16-beat lap) — the hits at 0 / 8 / 16 / 24 sit ON the change.
        let ranks = [1, 1, 1, 5, 1, 6, 4, 1]
        for gate in [0.5, 1.0] {
            let (box, p) = chordsBox(gate: gate)
            for frames: UInt32 in [64, 256, 1024, 2048, 4096] {
                let e = fxRun(box, beats: 33, frames: frames, pool: [60])
                for hitBeat in stride(from: 0.0, through: 28.0, by: 4.0) {
                    let col = Int(hitBeat / 2) % 8
                    let ideal = chordsIdealNote(p, beat: hitBeat, rank: ranks[col])
                    let struck = fxOns(e, cable: 3).filter { abs($0.beat - hitBeat) < 0.02 }.map { Int($0.note) }
                    // GATE 100 = legato: a hit whose pitch is the one ALREADY HELD carries on as one note (no new note-on) — beats 4 and 20, same chord, same rank
                    let heldPitch = gate == 1.0 && (hitBeat == 4 || hitBeat == 20)
                    if heldPitch { XCTAssertTrue(struck.isEmpty, "gate \(gate) buffer \(frames) beat \(hitBeat): same pitch under legato carries on") }
                    else { XCTAssertEqual(struck, [ideal], "gate \(gate) buffer \(frames) beat \(hitBeat): the chord current AT the hit") }
                }
                assertNothingLeftSounding(e)
            }
        }
    }
    // MARK: - NOTES TAB (ferry 2026-10-19) §13 test 1 — golden renders captured BEFORE the NOTES-tab engine change.
    // The ferry's example lane: 8 steps of 1/8, hits on 1, 3, 5, 6 and 8, FWD, LEN 8, STRIDE 1, SHIFT 5, EVERY 1, ADV STEP, both chains FREE, riff ranks
    // [8, 0, 8, 6, 0, 6, 5, 0], so the hits read columns 6, 8, 2, 3, 5 (the hits on 1 and 6 play, 3, 5 and 8 are rests). The pool is MIDI IN with the C-minor pitches
    // C3 D3 Eb3 F3 G3 Ab3 Bb3 (ranks 1-7; rank 8 is the octave copy C4), which is what KEY C MINOR resolves to. Ranks 5, 6 and 8 are lit.

    private let notesExPool: [UInt8] = [48, 50, 51, 53, 55, 56, 58]
    private let notesExRanks = [8, 0, 8, 6, 0, 6, 5, 0]
    private func notesExLine(onRest: EuclidRiffOnRest = .skip, riffOn: Bool = true, gate: Double = 0.5, lit: UInt8 = 0b1011_0000) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 5, steps: 8, gate: gate, rate: .r1_8, useRiff: true, litNotes: lit, riffOn: riffOn, sourceMode: .midi, riffLength: 8)
        l.customHits = [true, false, true, false, true, true, false, true]
        l.riffDir = .forward; l.riffAdvanceStep = true; l.riffRotate = 5; l.riffOnRest = onRest; l.notesOn = true
        return l
    }
    /// FNV-1a over every note-on / note-off on every cable (sample, cable, status, channel, note, velocity) plus the note-on count.
    private func notesStreamHash(_ e: RecordingEmitter) -> (hash: UInt64, ons: Int) {
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            mix(UInt64(bitPattern: ev.sample)); mix(UInt64(ev.cable)); mix(UInt64(ev.status)); mix(UInt64(ev.chan)); mix(UInt64(ev.note)); mix(UInt64(ev.vel))
        }
        return (h, e.ons.count)
    }
    /// The lane as a document saved BEFORE the NOTES tab existed (no notesWhen / chance / way / received / order keys): decoding it runs the 5.6 migration,
    /// so a lane built here sounds as the old engine made it. (A lane built in code now defaults to WHEN both, which is the NEW fresh-lane behaviour.)
    private func notesLegacyDecoded(_ line: EuclidLine) -> EuclidLine {
        var obj = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as! [String: Any]
        for k in ["notesWhen", "notesChance", "notesPlayAs", "notesReceivedOnly", "notesLitOrder"] { obj.removeValue(forKey: k) }
        return try! JSONDecoder().decode(EuclidLine.self, from: JSONSerialization.data(withJSONObject: obj))
    }
    private func notesExHash(_ line: EuclidLine) -> (hash: UInt64, ons: Int) {
        let e = fxRun(fxBox([notesLegacyDecoded(line)], ranks: notesExRanks), beats: 8 * 4.0 + 0.5, pool: notesExPool)
        assertNothingLeftSounding(e)
        return notesStreamHash(e)
    }
    /// GOLDEN: "ON REST/riff/gate" -> (stream hash, note-on count) over 8 passes. CAPTURED on origin/main 03adfa5, before the NOTES-tab engine change. With lit notes FILL is NOT the same as SKIP (984 vs 408
    /// note-ons at riff/50): SKIP silences the lit notes on a rest hit, FILL sounds them. (The riff-ferry goldens that show FILL == SKIP had no lit notes.)
    private let notesExampleGolden: [String: (UInt64, Int)] = [
        "SKIP/riff/50": (4458790343570662725, 408),
        "SKIP/riff/100": (18259817443166798221, 188),
        "SKIP/noriff/50": (6276098541914531621, 984),
        "SKIP/noriff/100": (7172130965572859533, 24),
        "FILL/riff/50": (5910540215221559509, 984),
        "FILL/riff/100": (13226157152018472061, 24),
        "FILL/noriff/50": (6276098541914531621, 984),
        "FILL/noriff/100": (7172130965572859533, 24),
        "TIE/riff/50": (15200567670056044365, 408),
        "TIE/riff/100": (13226157152018472061, 24),
        "TIE/noriff/50": (6276098541914531621, 984),
        "TIE/noriff/100": (7172130965572859533, 24),
        "REPEAT/riff/50": (16200784428846764181, 984),
        "REPEAT/riff/100": (13226157152018472061, 24),
        "REPEAT/noriff/50": (6276098541914531621, 984),
        "REPEAT/noriff/100": (7172130965572859533, 24),
    ]
    func testNotesExampleLaneGoldensBeforeTheNotesTabEngine() {
        var captured = ""
        for onRest in [EuclidRiffOnRest.skip, .fill, .tie, .repeatLast] {
            for riffOn in [true, false] {
                for gate in [0.5, 1.0] {
                    let key = "\(onRest.rawValue)/\(riffOn ? "riff" : "noriff")/\(Int(gate * 100))"
                    let got = notesExHash(notesExLine(onRest: onRest, riffOn: riffOn, gate: gate))
                    guard let want = notesExampleGolden[key] else { captured += "        \"\(key)\": (\(got.hash), \(got.ons)),\n"; continue }
                    XCTAssertEqual(got.hash, want.0, "\(key): stream must match the pre-change golden")
                    XCTAssertEqual(got.ons, want.1, "\(key): note-on count")
                }
            }
        }
        if !captured.isEmpty { XCTFail("CAPTURE:\n" + captured) }
    }

    // MARK: NOTES TAB engine (ferry 2026-10-19) — §13 tests 2, 6, 7, 8, 9, 13, 14 (the pure ones live in NotesTabTests)
    // The example lane (above): its hits, in order within a pass, are on steps 1, 3, 5, 6, 8 = ticks 0, 2, 4, 5, 7. The hits on 1 and 6 play the riff (A♭3 = 56, C4 = 60); the hits on
    // 3, 5 and 8 (hit indices 1, 2, 4) are rests. Lit in this order: rank 8 (C4 60), rank 5 (G3 55), rank 6 (A♭3 56). 120 BPM / 48 kHz: one beat = 24 000 samples, one step = 12 000.

    private func notesLine(_ way: EuclidNotesPlayAs = .chord, when: UInt8 = 0b11, chance: Int = 100, onRest: EuclidRiffOnRest = .skip, riffOn: Bool = true, gate: Double = 0.5,
                           order: [Int] = [7, 4, 5], received: Bool = false) -> EuclidLine {
        var l = notesExLine(onRest: onRest, riffOn: riffOn, gate: gate, lit: 0)
        var o = EuclideousLitOrder(); for p in order { o.append(p) }; l.setLitOrder(o)
        l.notesWhen = when; l.notesChance = chance; l.notesPlayAs = way; l.notesReceivedOnly = received
        return l
    }
    /// Every note-on of `cable`, grouped by the hit it belongs to (hit index = pass × 5 + position in the pass), each group sorted. A deferred (ROLL / RUN) note belongs to the step it starts in.
    private func notesByHit(_ e: RecordingEmitter, passes: Int, cable: UInt8 = 1) -> [[Int]] {
        let hitTicks = [0, 2, 4, 5, 7]
        var out = [[Int]](repeating: [], count: passes * 5)
        for ev in e.ons where ev.cable == cable {
            let tick = Int((Double(ev.sample) / 12_000 + 1e-3).rounded(.down))   // a sample or two early is still this step
            if tick / 8 >= passes { continue }   // the extra pass rendered after the last one, so every note of the last pass has ended before the stop flush
            guard let at = hitTicks.firstIndex(of: tick % 8) else { XCTFail("a note-on at tick \(tick) is not on a hit of the example lane"); continue }
            out[(tick / 8) * 5 + at].append(Int(ev.note))
        }
        return out.map { $0.sorted() }
    }
    private func notesRender(_ line: EuclidLine, passes: Int, frames: UInt32 = 2048, fx: EuclideousFX = EuclideousFX(), restartAt: [Double] = []) -> RecordingEmitter {
        fxRun(fxBox([line], ranks: notesExRanks, fx: fx), beats: Double(passes) * 4 + 4.5, frames: frames, pool: notesExPool, restartAt: restartAt)
    }
    private func notesPasses(_ e: RecordingEmitter, _ passes: Int) -> [[[Int]]] {
        let all = notesByHit(e, passes: passes); return (0..<passes).map { Array(all[($0 * 5)..<($0 * 5 + 5)]) }
    }
    private let C4 = 60, G3 = 55, Ab3 = 56
    /// Two renders hold the same note stream when every event has a partner with the same cable / status / note / velocity within `tol` samples. (The engine maps a beat to a sample once per
    /// render window, so the SAME hit can land a sample apart at different buffer sizes — that is the engine's own rounding, with or without NOTES, so "identical" means identical to it.)
    private func notesSameStream(_ a: [RecordingEmitter.Ev], _ b: [RecordingEmitter.Ev], tol: Int64 = 2) -> String? {
        if a.count != b.count { return "\(a.count) events vs \(b.count)" }
        var rest = b
        for ev in a {
            guard let i = rest.firstIndex(where: { $0.cable == ev.cable && $0.status == ev.status && $0.note == ev.note && $0.vel == ev.vel && abs($0.sample - ev.sample) <= tol }) else {
                return "no partner for \(ev)"
            }
            rest.remove(at: i)
        }
        return nil
    }
    // test 6: the count k, on the example lane
    func testNotesWhenRestsPlayOnlyTheRestHitsAndTheWayWalksOnlyThoseHits() {
        // RESTS, CYCLE: the hits on 3, 5, 8 play C4, G3, A♭3 in every pass (the riff plays A♭3 and C4 on hits 1 and 6)
        let cyc = notesPasses(notesRender(notesLine(.cycle, when: 0b10), passes: 3), 3)
        for p in 0..<3 { XCTAssertEqual(cyc[p], [[Ab3], [C4], [G3], [C4], [Ab3]], "CYCLE pass \(p)") }
        // RESTS, BOUNCE, passes 0-2: C4 G3 A♭3 | G3 C4 G3 | A♭3 G3 C4
        let bo = notesPasses(notesRender(notesLine(.bounce, when: 0b10), passes: 3), 3)
        XCTAssertEqual(bo[0], [[Ab3], [C4], [G3], [C4], [Ab3]]); XCTAssertEqual(bo[1], [[Ab3], [G3], [C4], [C4], [G3]]); XCTAssertEqual(bo[2], [[Ab3], [Ab3], [G3], [C4], [C4]])
        // RESTS, SPLIT, passes 0-1: G3, A♭3 + C4, G3 | A♭3 + C4, G3, A♭3 + C4
        let sp = notesPasses(notesRender(notesLine(.split, when: 0b10), passes: 2), 2)
        XCTAssertEqual(sp[0], [[Ab3], [G3], [Ab3, C4], [C4], [G3]]); XCTAssertEqual(sp[1], [[Ab3], [Ab3, C4], [G3], [C4], [Ab3, C4]])
        // RESTS, BUILD: C4, C4 + G3, C4 + G3 + A♭3 in every pass
        let bu = notesPasses(notesRender(notesLine(.build, when: 0b10), passes: 2), 2)
        for p in 0..<2 { XCTAssertEqual(bu[p], [[Ab3], [C4], [G3, C4], [C4], [G3, Ab3, C4]], "BUILD pass \(p)") }
    }
    func testNotesBothWithTheRiffOnTheRiffKeepsItsPitchAndTheHitStillCountsForK() {
        // Both, CYCLE, riff on, passes 0-1, hits 1 3 5 6 8: C4, G3, A♭3, nothing (the riff plays C4), G3 | nothing (the riff plays A♭3), C4, G3, A♭3, C4
        let cy = notesPasses(notesRender(notesLine(.cycle), passes: 2), 2)
        XCTAssertEqual(cy[0], [[Ab3, C4], [G3], [Ab3], [C4], [G3]]); XCTAssertEqual(cy[1], [[Ab3], [C4], [G3], [Ab3, C4], [C4]])
        // Both, BUILD, riff on, pass 0: C4, C4 + G3, C4 + G3 + A♭3, nothing (C4 is the riff's), C4 + G3
        let bu = notesPasses(notesRender(notesLine(.build), passes: 1), 1)
        XCTAssertEqual(bu[0], [[Ab3, C4], [G3, C4], [G3, Ab3, C4], [C4], [G3, C4]])
    }
    func testNotesInvertTransposeAndOnRestNeverChangeWhichHitsAreRestHits() {
        // RESTS only, CHORD: the lit notes sound exactly on hit indices 1, 2, 4 — whatever INVERT, TRANSPOSE or ON REST do to the riff
        for (invert, transpose, onRest) in [(false, 0, EuclidRiffOnRest.skip), (true, 0, .skip), (false, 3, .skip), (false, 0, .tie), (false, 0, .repeatLast), (true, 3, .repeatLast)] {
            var l = notesLine(.chord, when: 0b10, onRest: onRest); l.riffInvert = invert; l.melodyTranspose = transpose
            let e = notesRender(l, passes: 2)
            for (i, group) in notesByHit(e, passes: 2).enumerated() {
                let isRestHit = [1, 2, 4].contains(i % 5)
                XCTAssertEqual(group.contains(G3), isRestHit,   // (G3 is never a riff pitch here, and never the held one: C4 can be, under TIE)
                               "invert \(invert) transpose \(transpose) \(onRest.rawValue) hit \(i): the notes sound on exactly the rest hits")
            }
        }
        // …and with the riff OFF the written columns still decide
        let off = notesByHit(notesRender(notesLine(.chord, when: 0b10, riffOn: false), passes: 1), passes: 1)
        XCTAssertEqual(off, [[], [Ab3, G3, C4].sorted(), [Ab3, G3, C4].sorted(), [], [Ab3, G3, C4].sorted()], "riff off, RESTS only: the notes play on hits 3, 5, 8")
        let offPlays = notesByHit(notesRender(notesLine(.chord, when: 0b01, riffOn: false), passes: 1), passes: 1)
        XCTAssertEqual(offPlays, [[Ab3, G3, C4].sorted(), [], [], [Ab3, G3, C4].sorted(), []], "riff off, PLAYS only: hits 1 and 6 still play the notes")
    }
    func testNotesAHitChanceSkipsDoesNotMoveCycleOnButALanesMutedHitDoes() {
        // CHANCE 50, RESTS only, CYCLE over two notes: the rest hits that get through walk the list one by one; a skipped one leaves it where it was.
        let l = notesLine(.cycle, when: 0b10, chance: 50, order: [7, 4])   // L = [C4, G3]
        let passes = 6
        let got = notesByHit(notesRender(l, passes: passes), passes: passes)
        var expectedNext = 0, played = 0
        for p in 0..<passes {
            for at in [1, 2, 4] {
                let h = Int64(p * 5 + at)   // the hit's index among the lane's pattern hits since beat 0
                let group = got[p * 5 + at]
                if euclideousNotesChanceAllows(chance: 50, lane: 0, h: h) {
                    XCTAssertEqual(group, [[C4], [G3]][expectedNext % 2], "pass \(p) rest hit \(at): the \(expectedNext)th note that got through"); expectedNext += 1; played += 1
                } else {
                    XCTAssertTrue(group.isEmpty, "pass \(p) rest hit \(at): CHANCE skipped it, and the riff rests there")
                }
            }
        }
        XCTAssertGreaterThan(played, 3); XCTAssertLessThan(played, 15, "about half of 18 got through")
        // a LANES-muted PASS still counts: pass 1 muted, three rest hits per pass, two notes in the list -> pass 2 starts on L[6 % 2] = C4, not on G3
        var m = notesLine(.cycle, when: 0b10, order: [7, 4]); m.muteCells16 = 0xFFFF & ~0b10; m.muteUnit = EuclideousMuteUnit.pass.rawValue
        let mg = notesByHit(notesRender(m, passes: 3), passes: 3)
        XCTAssertEqual(mg[5 + 1], [], "the muted pass is silent"); XCTAssertEqual(mg[2 * 5 + 1], [C4], "…but its three rest hits counted: pass 2 begins at k = 6")
        XCTAssertEqual(mg[1], [C4]); XCTAssertEqual(mg[2], [G3]); XCTAssertEqual(mg[4], [C4])
    }
    func testNotesKAfterATransportJumpAndAfterEditsEqualsTheDefinition() {
        // k is derived, never carried: starting the transport at beat 37, or editing WHEN / CHANCE / the riff while playing, gives exactly what a fresh run of the same document gives.
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 1024
        func render(_ boxes: [(SnapshotBox, Double)], from start: Double, to end: Double) -> RecordingEmitter {
            let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag(); var ts = start * 60.0 / tempo * sr
            while true {
                let beat = ts * tempo / 60.0 / sr
                if beat >= end { break }
                let box = boxes.last(where: { beat >= $0.1 })!.0
                router.process(box: box, pool: chord(notesExPool), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                ts += Double(frames)
            }
            router.process(box: boxes.last!.0, pool: chord(notesExPool), playing: false, beatPos: end, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            return e
        }
        let a = fxBox([notesLine(.build, when: 0b10, chance: 75)], ranks: notesExRanks), b = fxBox([notesLine(.cycle, when: 0b11, chance: 50)], ranks: notesExRanks)
        let full = render([(a, 0)], from: 0, to: 60)
        let jumped = render([(a, 37)], from: 37, to: 60)
        func events(_ e: RecordingEmitter, _ lo: Double, _ hi: Double) -> [RecordingEmitter.Ev] { e.events.filter { Double($0.sample) / 24_000 >= lo && Double($0.sample) / 24_000 < hi && ($0.status == 0x90 || $0.status == 0x80) } }
        // (windows start between hits so a one-sample rounding cannot move an event across the edge)
        if let d = notesSameStream(events(full, 40.1, 58.1), events(jumped, 40.1, 58.1)) { XCTFail("a transport start at beat 37 plays the same hits with the same k: \(d)") }
        let edited = render([(a, 0), (b, 24)], from: 0, to: 60)
        let fresh = render([(b, 0)], from: 0, to: 60)
        if let d = notesSameStream(events(edited, 28.1, 58.1), events(fresh, 28.1, 58.1)) { XCTFail("after WHEN / CHANCE / the way changed at beat 24, the notes are what a fresh run of the new document plays: \(d)") }
    }

    // test 7: ROLL and RUN timing (120 BPM: 25 ms = 1 200 samples, a beat = 24 000)
    private func notesOnsAt(_ e: RecordingEmitter, hit tick: Int) -> [(note: Int, at: Int64, off: Int64?)] {
        let lo = Int64(tick) * 12_000, hi = lo + 12_000
        var out: [(note: Int, at: Int64, off: Int64?)] = []
        for ev in e.ons where ev.cable == 1 && ev.sample >= lo - 12 && ev.sample < hi - 12 {
            let off = e.offs.first { $0.cable == 1 && $0.note == ev.note && $0.sample > ev.sample }?.sample
            // a deferred note lands on the sample its beat maps to, which can be a sample early; every expectation here is a multiple of 4, so compare on a 4-sample grid
            func q(_ x: Int64) -> Int64 { Int64((Double(x) / 4).rounded()) * 4 }
            out.append((Int(ev.note), q(ev.sample - lo), off.map { q($0 - lo) }))
        }
        return out.sorted { $0.at < $1.at }
    }
    func testNotesRollStrumsUpThenDownEachNoteEndingWhereTheUnrolledHitWouldEnd() {
        let e = notesRender(notesLine(.roll, when: 0b10), passes: 1)
        // the hit on 3 (tick 2, k = 0): G3, A♭3, C4 at 0, 25 and 50 ms; all end where an unrolled hit (GATE 50% of the 1-beat gap = 12 000) would end
        let r0 = notesOnsAt(e, hit: 2)
        XCTAssertEqual(r0.map { $0.note }, [G3, Ab3, C4]); XCTAssertEqual(r0.map { $0.at }, [0, 1200, 2400])
        for n in r0 { XCTAssertEqual(n.off, 12_000, "\(n.note) ends where the unrolled hit's notes end") }
        // the hit on 5 (tick 4, k = 1): C4, A♭3, G3, also 25 ms apart; the unrolled length is 50% of the half-beat gap = 6 000
        let r1 = notesOnsAt(e, hit: 4)
        XCTAssertEqual(r1.map { $0.note }, [C4, Ab3, G3]); XCTAssertEqual(r1.map { $0.at }, [0, 1200, 2400])
        for n in r1 { XCTAssertEqual(n.off, 6_000) }
        assertNothingLeftSounding(e)
        // the later notes land on the same samples at every buffer size
        let ref = notesOnsAt(e, hit: 2).map { [Int64($0.note), $0.at] }
        for frames: UInt32 in [64, 256, 1024] {
            XCTAssertEqual(notesOnsAt(notesRender(notesLine(.roll, when: 0b10), passes: 1, frames: frames), hit: 2).map { [Int64($0.note), $0.at] }, ref, "buffer \(frames)")
        }
    }
    func testNotesRunSpreadsTheNotesAcrossTheStepNeverCarriedOnLegato() {
        for gate in [0.5, 1.0] {
            let e = notesRender(notesLine(.run, when: 0b10, gate: gate), passes: 1)
            // the hit on 3: C4, G3, A♭3 at 0, 1/6, 1/3 of a beat after it (4 000 samples apart), each lasting GATE × 1/6 of a beat
            let r = notesOnsAt(e, hit: 2)
            XCTAssertEqual(r.map { $0.note }, [C4, G3, Ab3]); XCTAssertEqual(r.map { $0.at }, [0, 4000, 8000])
            for n in r { XCTAssertEqual(Double((n.off ?? 0) - n.at), gate * 4000, accuracy: 2, "gate \(gate): lasts its effective gate as a share of its slot") }
            assertNothingLeftSounding(e)
        }
        // RUN, both, the hit on 1: the riff's A♭3 at the hit, and the notes C4 and G3 at 0 and 1/4 of a beat after it (m is 2 once A♭3 is dropped)
        let e = notesRender(notesLine(.run), passes: 1)
        let h1 = notesOnsAt(e, hit: 0)
        XCTAssertEqual(h1.filter { $0.note == Ab3 }.map { $0.at }, [0]); XCTAssertEqual(h1.filter { $0.note == C4 }.map { $0.at }, [0]); XCTAssertEqual(h1.filter { $0.note == G3 }.map { $0.at }, [6000])
        // the later notes land on the same samples at every buffer size
        let ref = notesOnsAt(notesRender(notesLine(.run, when: 0b10), passes: 1), hit: 2).map { [Int64($0.note), $0.at] }
        for frames: UInt32 in [64, 256, 1024] {
            XCTAssertEqual(notesOnsAt(notesRender(notesLine(.run, when: 0b10), passes: 1, frames: frames), hit: 2).map { [Int64($0.note), $0.at] }, ref, "buffer \(frames)")
        }
    }
    func testNotesARatchetOnARunHitStrikesAllTheChosenNotesTogetherOnEveryStrike() {
        // FX RATCH 2 on the riff column the hit on 1 reads (column 6 = index 5): two strikes, each of ALL the chosen notes together, no spread
        let fx = fxCells([(row: 0, col: 5, v: 2)], lanes: [0: 0b0001])
        let e = notesRender(notesLine(.run), passes: 1, fx: fx)
        let at0 = Set(e.ons.filter { $0.cable == 1 && $0.sample == 0 }.map { Int($0.note) }), atHalf = Set(e.ons.filter { $0.cable == 1 && $0.sample == 6000 }.map { Int($0.note) })
        XCTAssertEqual(at0, [Ab3, C4, G3]); XCTAssertEqual(atHalf, [Ab3, C4, G3], "the second strike repeats the whole hit, all notes together")
        assertNothingLeftSounding(e)
    }

    // test 8: TIE
    func testNotesTieRestsStrikeTheNotesUnderTheHeldRiffNoteAndNeverTheHeldPitchAgain() {
        // RESTS only, TIE, CHORD: the rest hits 3 and 5 strike G3 and C4 under the riff's A♭3 (held from hit 1); hit 8 strikes G3 and A♭3 under the C4 held from hit 6
        let e = notesRender(notesLine(.chord, when: 0b10, onRest: .tie), passes: 2)
        let g = notesPasses(e, 2)
        for p in 0..<2 { XCTAssertEqual(g[p], [[Ab3], [G3, C4], [G3, C4], [C4], [G3, Ab3]], "pass \(p)") }
        // the notes struck on hit 3 end by hit 5 as they would at an untied hit (GATE 50% of the 1-beat gap = 12 000); the held riff note carries through both
        let h3 = notesOnsAt(e, hit: 2)
        for n in h3 { XCTAssertEqual(n.off, 12_000, "note \(n.note) from hit 3 ends at its own gate") }
        let riff = e.ons.first { $0.cable == 1 && $0.note == UInt8(Ab3) && $0.sample == 0 }
        let riffOff = e.offs.first { $0.cable == 1 && $0.note == UInt8(Ab3) && $0.sample > 0 }
        XCTAssertNotNil(riff); XCTAssertGreaterThanOrEqual(riffOff?.sample ?? 0, 48_000, "the riff note rings on through the tied rests 3 and 5")
        XCTAssertEqual(e.ons.filter { $0.cable == 1 && $0.note == UInt8(Ab3) && $0.sample > 0 && $0.sample < 60_000 }.count, 0, "A♭3 is never struck again while it is held")
        assertNothingLeftSounding(e)
        // PLAYS only: the tied rests strike nothing and the notes struck on hit 1 carry on with the riff note — the pre-change TIE golden, note for note
        var plays = notesExLine(onRest: .tie, riffOn: true, gate: 0.5); plays.notesWhen = 0b01
        let golden = notesExampleGolden["TIE/riff/50"]!
        let h = notesStreamHash(fxRun(fxBox([plays], ranks: notesExRanks), beats: 8 * 4.0 + 0.5, pool: notesExPool))
        XCTAssertEqual(h.hash, golden.0); XCTAssertEqual(h.ons, golden.1)
    }
    func testNotesTieLookaheadEndsTheNotesExtensionAtTheFirstTiedRestTheyStrikeOn() {
        let buf = [true, false, true, false, true, true, false, true]
        let ranks = notesExRanks
        func ext(strikeAt: Set<Int>) -> (riff: Double, notes: Double) {
            var seen = 0
            return euclideousChainTieExtensions(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: 0, chains: .off, legacySpanBeats: 0, advanceStep: true,
                                                riffDir: .forward, stride: 1, length: 8, rotate: 5, seed: 0, bound: 64, restTies: true, rankAt: { c, _ in ranks[c] },
                                                notesStrikes: { _, _, _ in defer { seen += 1 }; return strikeAt.contains(seen) })
        }
        XCTAssertEqual(ext(strikeAt: []).riff, 2.0); XCTAssertEqual(ext(strikeAt: []).notes, 2.0, "no tied rest strikes: the notes carry as far as the riff note")
        XCTAssertEqual(ext(strikeAt: [0]).notes, 0, "the first tied rest strikes: what was struck before ends at its own length"); XCTAssertEqual(ext(strikeAt: [0]).riff, 2.0, "the riff note's extension is unchanged")
        XCTAssertEqual(ext(strikeAt: [1]).notes, 1.0, "the second tied rest strikes: they carry through the first only")
    }

    // test 9: FILL decodes as SKIP and renders identically to its FILL golden
    func testNotesAFillDocumentLoadsAsSkipAndRendersLikeItsFillGolden() throws {
        let fill = notesExLine(onRest: .fill, riffOn: true, gate: 0.5)
        let loaded = notesLegacyDecoded(fill)
        XCTAssertEqual(loaded.riffOnRestResolved, .skip); XCTAssertEqual(loaded.notesWhenResolved, 0b11)
        let got = notesStreamHash(fxRun(fxBox([loaded], ranks: notesExRanks), beats: 8 * 4.0 + 0.5, pool: notesExPool))
        XCTAssertEqual(got.hash, notesExampleGolden["FILL/riff/50"]!.0); XCTAssertEqual(got.ons, notesExampleGolden["FILL/riff/50"]!.1)
    }

    // the latent REPEAT recursion found while restructuring the rest switch
    func testNotesRepeatWithATransposeThatPushesTheRepeatedRankBelowOneStillTerminates() {
        var l = notesLine(.chord, when: 0b11, onRest: .repeatLast); l.riffLength = 8; l.pulses = 8; l.customHits = nil; l.melodyTranspose = -1
        let e = fxRun(fxBox([l], ranks: [1, 0, 0, 0, 0, 0, 0, 0]), beats: 8, pool: notesExPool)
        assertNothingLeftSounding(e)
    }

    // test 13: determinism
    func testNotesEveryWayWithChance50IsIdenticalAtEveryBufferSizeAndAfterATransportRestart() {
        for way in EuclidNotesPlayAs.allCases {
            let line = notesLine(way, when: 0b11, chance: 50, order: [7, 4, 5, 9, 8])
            let ref = notesRender(line, passes: 8)
            for frames: UInt32 in [64, 256, 1024] {
                if let d = notesSameStream(notesRender(line, passes: 8, frames: frames).events, ref.events) { XCTFail("\(way.rawValue) at buffer \(frames): \(d)") }
            }
            // after a transport restart the same document replays the same notes: the second play equals the first
            var restarts: [Int64] = []
            let twice = withUnsafeMutablePointer(to: &restarts) { ptr in
                fxRun(fxBox([line], ranks: notesExRanks), beats: 16.5 + 16.25, pool: notesExPool, restartAt: [16.5], restartSamples: ptr)
            }
            XCTAssertEqual(restarts.count, 1)
            let r = restarts.first ?? 0, span = Int64(16 * 24_000)
            func slice(_ lo: Int64, _ hi: Int64) -> [RecordingEmitter.Ev] {
                twice.events.filter { ($0.status == 0x90 || $0.status == 0x80) && $0.sample >= lo && $0.sample < hi }
                    .map { RecordingEmitter.Ev(sample: $0.sample - lo, cable: $0.cable, status: $0.status, chan: $0.chan, note: $0.note, vel: $0.vel) }
            }
            XCTAssertFalse(slice(0, span).isEmpty, "\(way.rawValue) plays something")
            if let d = notesSameStream(slice(r + 600, r + span), slice(600, span)) { XCTFail("\(way.rawValue): the replay after a transport restart equals the first play: \(d)") }
            assertNothingLeftSounding(twice)
        }
    }

    // test 14: stuck notes
    func testNotesStressCyclingEverythingLeavesNothingSounding() {
        let order: [Int] = [7, 4, 5, 9, 8, 0, 3]
        let ways = EuclidNotesPlayAs.allCases
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 512
        let wb = Double(frames) * tempo / 60.0 / sr
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        var beat = 0.0, ts = 0.0
        func lineFor(_ k: Int) -> EuclidLine {
            var l = notesLine(ways[k % ways.count], when: [0b11, 0b01, 0b10][k % 3], chance: [100, 75, 50, 25][k % 4],
                              onRest: [.skip, .tie, .repeatLast][k % 3], gate: [0.5, 0.99, 1.0, 0.25][k % 4], order: Array(order.prefix(1 + k % order.count)), received: k % 5 == 0)
            if k % 7 == 3 { l.muteCells16 = 0xAAAA; l.muteUnit = EuclideousMuteUnit.step.rawValue }
            return l
        }
        for k in 0..<60 {
            let fx = k % 4 == 1 ? fxCells([(row: 0, col: 5, v: 3), (row: 0, col: 2, v: 2)], lanes: [0: 0b0001]) : EuclideousFX()
            let box = fxBox([lineFor(k)], ranks: notesExRanks, fx: fx)
            if k % 9 == 8 {   // a transport restart in the middle of everything
                router.process(box: box, pool: chord(notesExPool), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
            for _ in 0..<8 {
                router.process(box: box, pool: chord(notesExPool), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
        }
        router.process(box: fxBox([lineFor(0)], ranks: notesExRanks), pool: chord(notesExPool), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        XCTAssertGreaterThan(e.ons.count, 100)
    }

    // MARK: PULSE ferry §1.3 — the hit event carries the velocity each pitch actually played with
    /// Every struck pitch of every posted event has a note-on on the wire at that onset with exactly the velocity the event reports (riff note first when `hasRiffNote`, then the notes layer).
    private func assertEventVelsMatchTheWire(_ e: RecordingEmitter, _ events: [Router.EuclideousNoteViewEventSnapshot], _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(events.isEmpty, "\(context): the lane posted events", file: file, line: line)
        for ev in events where ev.kind == 0 || ev.kind == 3 {
            XCTAssertEqual(ev.vels.count, ev.notes.count, "\(context): one velocity per note", file: file, line: line)
            let onsetSample = ev.onsetBeat * 24_000
            for (i, note) in ev.notes.enumerated() {
                let wire = e.ons.first { $0.cable == 1 && $0.note == note && abs(Double($0.sample) - onsetSample) <= 3 }
                XCTAssertNotNil(wire, "\(context): a note-on for \(note) at beat \(ev.onsetBeat)", file: file, line: line)
                if let wire, i < ev.vels.count { XCTAssertEqual(wire.vel, ev.vels[i], "\(context): the event's velocity for note \(note) is what was sent", file: file, line: line) }
            }
        }
    }
    func testTheNoteViewEventCarriesThePlayedVelocityOfTheRiffAndTheNotesLayer() {
        // riff on (ranks 1…8 walked FWD at one hit a beat), rank 8 lit; VEL 90 (the riff pad), notes velocity 60 (the notes pad)
        var line = fxLine(gate: 0.5, vel: 90, litNotes: 0b1000_0000)
        line.notesVelocity = 60
        let e = RecordingEmitter()
        let router = runKeepingRouter(fxBox([line]), chord(fxPoolNotes), beats: 4, into: e, forceColumn: 0)
        let events = router.drainEuclideousNoteViewEvents()[0]
        assertEventVelsMatchTheWire(e, events, "plain")
        XCTAssertEqual(events.first?.hasRiffNote, true); XCTAssertEqual(events.first?.vels.first, 90, "the riff note plays the lane's VEL"); XCTAssertEqual(events.first?.vels.dropFirst().first, 60, "the notes layer plays the notes pad's velocity")
        // FX VEL on the column the first hit reads (row 3 = VEL): both layers are re-weighted, and the event reports what was actually sent
        let fx = fxCells([(row: 3, col: 0, v: 40), (row: 3, col: 2, v: 120)], lanes: [3: 0b0001])
        let e2 = RecordingEmitter()
        let r2 = runKeepingRouter(fxBox([line], fx: fx), chord(fxPoolNotes), beats: 4, into: e2, forceColumn: 0)
        let ev2 = r2.drainEuclideousNoteViewEvents()[0]
        assertEventVelsMatchTheWire(e2, ev2, "FX VEL")
        XCTAssertNotEqual(ev2.first?.vels.first, 90, "the FX VEL cell changed the riff note's velocity — and the event follows it")
        // riff off: the notes layer alone, no riff note, its velocity in vels[0]
        var off = fxLine(gate: 0.5, vel: 90, litNotes: 0b0000_0100, riffOn: false); off.notesVelocity = 55
        let e3 = RecordingEmitter()
        let r3 = runKeepingRouter(fxBox([off]), chord(fxPoolNotes), beats: 3, into: e3, forceColumn: 0)
        let ev3 = r3.drainEuclideousNoteViewEvents()[0]
        assertEventVelsMatchTheWire(e3, ev3, "riff off")
        XCTAssertEqual(ev3.first?.hasRiffNote, false); XCTAssertEqual(ev3.first?.vels, [55])
    }
    func testAMutedLanesStrikesPostNoEventAndANotesStrikeOnARestIsNotARiffStrike() {
        // the LANES grid mutes the whole lane: no strike event at all (1.6)
        var muted = fxLine(gate: 0.5, vel: 90, litNotes: 0b1000_0000); muted.muteCells16 = 0; muted.muteUnit = EuclideousMuteUnit.pass.rawValue
        let e = RecordingEmitter()
        let router = runKeepingRouter(fxBox([muted]), chord(fxPoolNotes), beats: 4, into: e, forceColumn: 0)
        XCTAssertTrue(router.drainEuclideousNoteViewEvents()[0].filter { $0.kind == 0 || $0.kind == 3 }.isEmpty, "a muted lane strikes nothing, so nothing pulses")
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty)
        // a rest hit under SKIP with the notes playing on it (WHEN RESTS): an event with notes but NO riff note — the comet bar passes through, the notes surfaces strike
        var rest = notesExLine(onRest: .skip, riffOn: true, gate: 0.5); rest.notesWhen = 0b10; rest.notesVelocity = 70
        let e2 = RecordingEmitter()
        let r2 = runKeepingRouter(fxBox([rest], ranks: notesExRanks), chord(notesExPool), beats: 3.9, into: e2, forceColumn: 0)   // one pass: the next pass's first hit is at beat 4
        let all = r2.drainEuclideousNoteViewEvents()[0].filter { $0.kind == 0 || $0.kind == 3 }
        let restHits = all.filter { !$0.hasRiffNote }, riffHits = all.filter { $0.hasRiffNote }
        XCTAssertEqual(restHits.count, 3, "the hits on 3, 5 and 8 are rest hits: the notes strike there with no riff note")
        XCTAssertTrue(restHits.allSatisfy { $0.vels.allSatisfy { $0 == 70 } }, "…at the notes pad's velocity")
        XCTAssertEqual(riffHits.count, 2, "the hits on 1 and 6 are riff strikes"); XCTAssertTrue(riffHits.allSatisfy { $0.vels.first == 100 }, "…at the lane's own VEL (the default 100)")
        let feed = EuclideousPulseFeed(); feed.ingest(lane: 0, events: all, anchorBeat: 0, anchorAt: Date(timeIntervalSinceReferenceDate: 0), tempo: 120)
        XCTAssertEqual(feed.strikes(lane: 0).filter { $0.riffVel == 0 && $0.notesVel == 70 }.count, 3)
        XCTAssertEqual(feed.strikes(lane: 0).filter { $0.riffVel == 100 }.count, 2)
    }

    // MARK: - SYNTHETIC-LANE GOLDENS (captured on origin/main 612c365 — the RHYTHM DYNAMICS ferry's step 1; they outlived that ferry, which was removed 2026-10-21, as general engine regression tests).
    // The 20 factory presets' 8- and 32-bar goldens above are the preset half. This is the other half: synthetic lanes covering what the presets don't (every direction, TILT, hand-edited hits, rhythm restarts, mute, the notes
    // layer, FX RATCH / GATE / TIE / VEL, the test-only mask's ACCENT and SWELL, transport restarts) — each scenario must render exactly this note stream.

    private struct GoldenScenario { let name: String; let lines: [EuclidLine]; let ranks: [Int]; let fx: EuclideousFX; let beats: Double; let restartAt: [Double]; let maskOn: Bool }
    private func goldenScenarios(_ tweak: (inout EuclidLine) -> Void = { _ in }) -> [GoldenScenario] {
        func line(_ pulses: Int, _ steps: Int, _ rate: ArpRate, _ dir: EuclidDir, gate: Double = 0.5, vel: Int = 100, lit: UInt8 = 0, _ more: (inout EuclidLine) -> Void = { _ in }) -> EuclidLine {
            var l = EuclidLine(target: 0, pulses: pulses, steps: steps)
            l.gate = gate; l.velocityAbsolute = vel; l.rate = rate; l.useRiff = true; l.litNotes = lit; l.riffOn = true; l.sourceMode = .midi
            l.riffLength = 8; l.notesOn = true; l.direction = dir; l.riffOnRest = .skip
            more(&l); tweak(&l); return l
        }
        let ranks = [1, 3, 0, 5, 2, 0, 8, 4]
        let fx = fxCells([(0, 1, 3), (0, 4, 2), (1, 0, 50), (1, 3, 80), (2, 3, 1), (3, 6, 120), (3, 4, 70)])
        let four = [
            line(5, 8, .r1_8, .fwd),
            line(3, 8, .r1_16, .bkw, gate: 0.9, vel: 90),
            line(5, 8, .r1_8, .pingpong, lit: 0b101) { $0.tilt = 0.5; $0.rotate = 2 },
            line(4, 7, .r1_8, .fwd, gate: 0.7) { $0.customHits = [true, false, true, true, false, true, false]; $0.restartRhythmBars = [2] }
        ]
        var muted = line(5, 8, .r1_8, .fwd, lit: 0b1001); muted.muteCells16 = 0b1111_0000_1010_0101; muted.muteUnit = EuclideousMuteUnit.pass.rawValue
        var m1 = EuclidLineMask(); m1.enabled = true; m1.mode = .accent; m1.accentAmount = 24; m1.pulses = 3; m1.steps = 8
        var m2 = EuclidLineMask(); m2.enabled = true; m2.mode = .swell; m2.swellStep = 8; m2.pulses = 8; m2.steps = 8
        let accent = line(5, 8, .r1_8, .fwd) { $0.mask = m1 }
        let swell = line(4, 4, .r1_4, .fwd, gate: 0.6) { $0.mask = m2 }
        return [
            GoldenScenario(name: "four lanes, no FX", lines: four, ranks: ranks, fx: EuclideousFX(), beats: 16, restartAt: [], maskOn: false),
            GoldenScenario(name: "four lanes, FX ratch/gate/tie/vel", lines: four, ranks: ranks, fx: fx, beats: 16, restartAt: [], maskOn: false),
            GoldenScenario(name: "four lanes, FX, transport restarts", lines: four, ranks: ranks, fx: fx, beats: 16, restartAt: [5.5, 11.25], maskOn: false),
            GoldenScenario(name: "muted lane with lit notes", lines: [muted], ranks: ranks, fx: EuclideousFX(), beats: 16, restartAt: [], maskOn: false),
            GoldenScenario(name: "mask ACCENT", lines: [accent], ranks: ranks, fx: EuclideousFX(), beats: 16, restartAt: [], maskOn: true),
            GoldenScenario(name: "mask SWELL", lines: [swell], ranks: ranks, fx: EuclideousFX(), beats: 16, restartAt: [], maskOn: true)
        ]
    }
    private func goldenStreamHash(_ sc: GoldenScenario) -> (hash: UInt64, ons: Int) {
        let e = fxRun(fxBox(sc.lines, ranks: sc.ranks, fx: sc.fx), beats: sc.beats, restartAt: sc.restartAt, maskOn: sc.maskOn)
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            mix(UInt64(bitPattern: ev.sample)); mix(UInt64(ev.cable)); mix(UInt64(ev.status)); mix(UInt64(ev.chan)); mix(UInt64(ev.note)); mix(UInt64(ev.vel))
        }
        return (h, e.ons.count)
    }
    /// GOLDEN: scenario name → (stream hash, note-on count). CAPTURED on origin/main 612c365, before the DYNAMICS ferry changed anything.
    private let syntheticGolden: [String: (UInt64, Int)] = [
        "four lanes, no FX": (2369415864824715333, 800),
        "four lanes, FX ratch/gate/tie/vel": (15251175310064653733, 1008),
        "four lanes, FX, transport restarts": (18130081851072502405, 2072),
        "muted lane with lit notes": (3312976233490713525, 208),
        "mask ACCENT": (5253426162309938749, 128),
        "mask SWELL": (13038166893529998973, 104)
    ]
    func testSyntheticLanesRenderTheirGoldenNoteStreams() {
        for sc in goldenScenarios() {
            let got = goldenStreamHash(sc)
            XCTAssertGreaterThan(got.ons, 0, "\(sc.name): the scenario must actually sound")
            guard let want = syntheticGolden[sc.name] else { XCTFail("no golden for \(sc.name): (\(got.hash), \(got.ons))"); continue }
            XCTAssertEqual(got.ons, want.1, "\(sc.name): note-on count")
            XCTAssertEqual(got.hash, want.0, "\(sc.name): the note-on/off/velocity stream must be bit-identical")
        }
    }

    // MARK: - RHYTHM POLISH ferry (2026-10-22) §8 test 1 — a second synthetic golden for what the presets and the six scenarios above do NOT cover: TILT ≠ 0 (the old ROUNDED path) crossed with every direction,
    // OFFSET, FLIP HITS (patternMiss), FOLLOW, a rhythm chain and the riff on/off. Captured on origin/main e7b6da9, BEFORE the continuous OFFSET / TILT engine; with `offsetFraction` / `tiltFine` nil every one must
    // keep rendering exactly this stream.
    private func rhythmPolishScenarios() -> [GoldenScenario] {
        func line(_ pulses: Int, _ steps: Int, _ rate: ArpRate, _ dir: EuclidDir, gate: Double = 0.6, vel: Int = 100, lit: UInt8 = 0, _ more: (inout EuclidLine) -> Void = { _ in }) -> EuclidLine {
            var l = EuclidLine(target: 0, pulses: pulses, steps: steps)
            l.gate = gate; l.velocityAbsolute = vel; l.rate = rate; l.useRiff = true; l.litNotes = lit; l.riffOn = true; l.sourceMode = .midi
            l.riffLength = 8; l.notesOn = true; l.direction = dir; l.riffOnRest = .skip
            more(&l); return l
        }
        let ranks = [1, 3, 0, 5, 2, 0, 8, 4]
        var scenarios: [GoldenScenario] = []
        for (name, dir) in [("FWD", EuclidDir.fwd), ("BKW", .bkw), ("PING-PONG", .pingpong)] {
            let four = [
                line(5, 8, .r1_8, dir) { $0.tilt = 0.4; $0.rotate = 3 },
                line(3, 8, .r1_8, dir) { $0.tilt = -0.6; $0.rotate = 1 },
                line(4, 7, .r1_8, dir, lit: 0b11) { $0.tilt = 0.25; $0.rotate = 5; $0.patternMiss = true },
                line(6, 11, .r1_16, dir) { $0.tilt = -0.15; $0.rotate = 4 }
            ]
            scenarios.append(GoldenScenario(name: "TILT x OFFSET x \(name)", lines: four, ranks: ranks, fx: EuclideousFX(), beats: 16, restartAt: [], maskOn: false))
        }
        // LISTEN REBUILT (2026-10-23): FOLLOW -> COPY. The follower's own rotate/patternMiss (FLIP) no
        // longer apply on top while borrowing (§7: "a tab is either fully the lane's own or fully paused"
        // — the old FOLLOW's "still applies on top" was exactly the half-overridden confusion this rebuild
        // fixes), so they're left on the line (decode-only, inert) rather than deleted, to keep this
        // scenario's shape close to its predecessor's.
        var follower = line(3, 8, .r1_8, .fwd) { $0.rotate = 2; $0.listenRhythm = .copy; $0.listenSource = 0; $0.patternMiss = true }
        let partner = line(5, 8, .r1_8, .bkw) { $0.tilt = 0.5; $0.rotate = 3 }
        scenarios.append(GoldenScenario(name: "COPY a TILTed OFFSET partner", lines: [partner, follower], ranks: ranks, fx: EuclideousFX(), beats: 16, restartAt: [], maskOn: false))
        let chained = [line(5, 8, .r1_8, .fwd) { $0.tilt = 0.5; $0.rotate = 2; $0.restartRhythmBars = [1]; $0.restartMelodyPasses = [2] },
                       line(4, 7, .r1_8, .pingpong) { $0.tilt = -0.5; $0.rotate = 3; $0.restartRhythmBars = [2]; $0.restartMelodyPasses = [3] }]
        scenarios.append(GoldenScenario(name: "TILT x OFFSET with rhythm and melody chains", lines: chained, ranks: ranks, fx: EuclideousFX(), beats: 24, restartAt: [], maskOn: false))
        let tied = [line(5, 8, .r1_8, .fwd, gate: 0.9) { $0.tilt = 0.35; $0.rotate = 1; $0.riffOnRest = .tie }, line(4, 8, .r1_8, .bkw) { $0.tilt = -0.35; $0.rotate = 6; $0.riffOnRest = .repeatLast }]
        scenarios.append(GoldenScenario(name: "TILT x OFFSET with TIE and REPEAT", lines: tied, ranks: ranks, fx: EuclideousFX(), beats: 16, restartAt: [], maskOn: false))
        return scenarios
    }
    /// GOLDEN: scenario name → (stream hash, note-on count). CAPTURED on origin/main e7b6da9.
    private let rhythmPolishGolden: [String: (UInt64, Int)] = [
        "TILT x OFFSET x FWD": (5352633688982272725, 712),
        "TILT x OFFSET x BKW": (15399358455468573405, 680),
        "TILT x OFFSET x PING-PONG": (522207749321150981, 704),
        // LISTEN REBUILT (2026-10-23): recaptured fresh for "COPY a TILTed OFFSET partner" — see the scenario's own comment.
        "COPY a TILTed OFFSET partner": (6788349491252245445, 256),
        "TILT x OFFSET with rhythm and melody chains": (15993422064495286957, 376),
        "TILT x OFFSET with TIE and REPEAT": (727378462195434669, 256)
    ]
    func testTiltOffsetCopyLanesRenderTheirGoldenNoteStreams() {
        for sc in rhythmPolishScenarios() {
            let got = goldenStreamHash(sc)
            XCTAssertGreaterThan(got.ons, 0, "\(sc.name): the scenario must actually sound")
            guard let want = rhythmPolishGolden[sc.name] else { XCTFail("no golden for \(sc.name): (\(got.hash), \(got.ons))"); continue }
            XCTAssertEqual(got.ons, want.1, "\(sc.name): note-on count (hash \(got.hash))")
            XCTAssertEqual(got.hash, want.0, "\(sc.name): the note-on/off/velocity stream must be bit-identical")
        }
    }

    // MARK: - RHYTHM POLISH engine (ferry 2026-10-22, §8 tests 2, 4, 5, 6) — a hit's time is its step plus a fraction of a step

    /// A lane for hit-timing tests: `pulses` of `steps` at 1/8 (a step = 0.5 beat, a pass of 8 steps = 4 beats), the riff on over ranks 1…8 so the NOTE names the hit's position in the walk.
    private func rpLine(_ pulses: Int, _ steps: Int, dir: EuclidDir = .fwd, rotate: Int = 0, rate: ArpRate = .r1_8, gate: Double = 0.5, _ more: (inout EuclidLine) -> Void = { _ in }) -> EuclidLine {
        var l = fxLine(gate: gate); l.pulses = pulses; l.steps = steps; l.rate = rate; l.direction = dir; l.rotate = rotate
        more(&l); return l
    }
    private func rpOns(_ lines: [EuclidLine], ranks: [Int] = [1, 2, 3, 4, 5, 6, 7, 8], beats: Double, frames: UInt32 = 2048) -> [(beat: Double, note: UInt8)] {
        fxOns(fxRun(fxBox(lines, ranks: ranks), beats: beats, frames: frames)).filter { $0.beat < beats - 0.01 }.map { ($0.beat, $0.note) }   // the window that ends the run can overshoot by a few ms: only hits before `beats`
    }
    private func assertBeats(_ got: [(beat: Double, note: UInt8)], _ want: [Double], _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, want.count, "\(msg): hit count (\(got.map { $0.beat }))", file: file, line: line)
        for (g, w) in zip(got, want) { XCTAssertEqual(g.beat, w, accuracy: 1e-3, "\(msg)", file: file, line: line) }
    }
    func testRhythmPolishOffsetFractionPlaysEveryHitThatFractionOfAStepLaterAtEveryBufferSize() {
        // E(3,8) here is {0,3,6}: beats 0, 1.5, 3.0 in a 4-beat pass
        for frames: UInt32 in [64, 1024, 2048] {
            let base = rpOns([rpLine(3, 8)], beats: 8, frames: frames)
            assertBeats(base, [0, 1.5, 3, 4, 5.5, 7], "offset 0, buffer \(frames)")
            var half = rpLine(3, 8); half.offsetFraction = 0.5
            assertBeats(rpOns([half], beats: 8, frames: frames), [0.25, 1.75, 3.25, 4.25, 5.75, 7.25], "offset 0.5 plays every hit 0.25 beat later, buffer \(frames)")
            // displayed offset 7.5 on 8 steps: the hits sit at 7.5, 2.5 and 5.5 steps — no wrap, they are simply shifted
            var seven = rpLine(3, 8); euclideousSliderCommit(.offset, &seven, snapshot: seven, newValue: 7.5)
            XCTAssertEqual(seven.offsetRequested, 7); XCTAssertEqual(seven.offsetFractionResolved, 0.5, accuracy: 1e-12)
            assertBeats(rpOns([seven], beats: 8, frames: frames), [1.25, 2.75, 3.75, 5.25, 6.75, 7.75], "offset 7.5, buffer \(frames)")
        }
        // offset 2 with fraction 0 is today, byte for byte
        var plain = rpLine(3, 8); euclideousSliderCommit(.offset, &plain, snapshot: plain, newValue: 2)
        var zero = plain; zero.offsetFraction = 0
        XCTAssertEqual(fxStream(fxRun(fxBox([plain]), beats: 16)), fxStream(fxRun(fxBox([zero]), beats: 16)))
    }
    func testRhythmPolishAFractionalPassCutShortByARhythmRestartPlaysNothingAtOrAfterTheRestartAndTheGapsAgree() {
        // 7 steps at 1/8 = 3.5 beats a pass, a bar restart every 4 beats: the second pass is cut after one step. Fraction 0.6 = 0.3 beat.
        var l = rpLine(7, 7); l.restartRhythmBars = [1]; l.offsetFraction = 0.6
        let ranks = [1, 1, 1, 1, 1, 1, 1, 1]
        let e = fxRun(fxBox([l], ranks: ranks), beats: 8)
        let ons = fxOns(e).filter { $0.beat < 7.95 }
        let want = [0.3, 0.8, 1.3, 1.8, 2.3, 2.8, 3.3, 3.8, 4.3, 4.8, 5.3, 5.8, 6.3, 6.8, 7.3, 7.8]
        XCTAssertEqual(ons.map { $0.beat }.count, want.count, "\(ons.map { $0.beat })")
        for (g, w) in zip(ons, want) { XCTAssertEqual(g.beat, w, accuracy: 1e-3) }
        XCTAssertTrue(ons.filter { $0.beat > 3.85 && $0.beat < 4.25 }.isEmpty, "nothing plays between the cut pass's last hit (3.8) and the next bar's first (4.3)")
        // gate length = GATE × the gap to the next hit, across the restart too: the hit at 3.8 is followed by 4.3, so its length is 0.5 × 0.5 beat
        let sounding = Array(fxSoundings(e, 48).prefix(16))
        XCTAssertEqual(sounding.count, 16)
        for (i, snd) in sounding.enumerated().dropLast() {
            guard let off = snd.off else { XCTFail("no off"); continue }
            let gap = Double(sounding[i + 1].on - snd.on) / 24_000
            XCTAssertEqual(Double(off - snd.on) / 24_000, 0.5 * gap, accuracy: 2e-3, "hit \(i): length = GATE × the gap to the next hit")
        }
        // …and the pure functions the roll / TIE / predictions use agree with it
        let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        XCTAssertFalse(cfg.timing.isNone)
        let cl = euclidCycleLen(cfg.dir, n: cfg.n)
        XCTAssertEqual(euclideousNextChainHitGapBeats(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cl, sub: cfg.sub, tick: 7, cap: cl * 4, chains: cfg.chains, legacySpanBeats: cfg.spanBeats, timing: cfg.timing),
                       0.5, accuracy: 1e-9, "the cut pass's last hit (tick 7) to the next bar's first (tick 8)")
        XCTAssertEqual(euclideousWalkRealBeat(cfg, tick: 7), 3.8, accuracy: 1e-9); XCTAssertEqual(euclideousWalkRealBeat(cfg, tick: 8), 4.3, accuracy: 1e-9)
    }
    func testRhythmPolishBackwardsWithAFractionMovesTheFirstHitToTheEndOfThePassAndTheRiffFollowsTime() {
        // BKW reads the buffer back to front, so the control's rightward fraction is EARLIER in time. Buffer hits {7,2,5} (offset 7) sit at ticks 0, 5, 2; half a step earlier puts the tick-0 hit
        // at 7.5 steps (the end of the SAME pass) and the others at 1.5 and 4.5 — the riff walks in time order: 1st (0.75 beat) rank 1, 2nd (2.25) rank 2, 3rd (3.75) rank 3.
        var l = rpLine(3, 8, dir: .bkw, rotate: 1)
        assertBeats(rpOns([l], beats: 4), [0, 1, 2.5], "no fraction")
        l.offsetFraction = 0.5
        let ons = rpOns([l], beats: 4)
        assertBeats(ons, [0.75, 2.25, 3.75], "BKW, fraction 0.5: every hit half a step EARLIER; the first wraps to the end of the pass")
        XCTAssertEqual(ons.map { $0.note }, [48, 50, 52], "the walk's ordinals follow actual time, wrapped hit included")
    }
    func testRhythmPolishFineTiltPlaysTheUnroundedTimesAndNilKeepsTheRoundedOnes() {
        // E(3,8), TILT +50 %: targets 2.5, 4.75, 7 steps. Rounded (today) they are steps 3, 5, 7; unrounded they play at 1.25, 2.375, 3.5 beats.
        var rounded = rpLine(3, 8); rounded.tilt = 0.5
        assertBeats(rpOns([rounded], beats: 4), [1.5, 2.5, 3.5], "tilt only (tiltFine nil): rounded, as always")
        var fine = rounded; fine.tiltFine = 0.5
        for frames: UInt32 in [64, 2048] { assertBeats(rpOns([fine], beats: 4, frames: frames), [1.25, 2.375, 3.5], "TILT-fine, buffer \(frames)") }
        // the same lane read back by the roll's pure chain agrees with the Router
        let cfg = euclideousWalkLaneConfig(lane: 0, lines: [fine], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        let roll = euclideousLaneRollHits(cfg: cfg, windowStart: 0, windowBeats: 3.99, minGateBeats: 0.005) { col, _ in col + 1 }
        XCTAssertEqual(roll.map { $0.beat }, [1.25, 2.375, 3.5].map { $0 }, "roll = Router")
    }
    // MARK: - RESTART TILES ferry (2026-10-22): the strike events that feed the MELODY tile's cells

    /// Every riff-note strike event the lane posts over `beats`, drained window by window the way the UI poll does.
    private func rpStrikes(_ lines: [EuclidLine], ranks: [Int] = [1, 2, 3, 4, 5, 6, 7, 8], beats: Double) -> [Router.EuclideousNoteViewEventSnapshot] {
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 1024
        let p = chord(fxPoolNotes), box = fxBox(lines, ranks: ranks)
        var ts = 0.0, out: [Router.EuclideousNoteViewEventSnapshot] = []
        while ts * tempo / 60 / sr < beats {
            router.process(box: box, pool: p, playing: true, beatPos: ts * tempo / 60 / sr, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            out += router.drainEuclideousNoteViewEvents()[0]
            ts += Double(frames)
        }
        return out.filter { ($0.kind == 0 || $0.kind == 3) && !$0.notes.isEmpty && $0.hasRiffNote && $0.onsetBeat < beats - 0.05 }
    }
    func testEachHitThatPlaysARiffNoteStrikesThatNotesCellAndTheRecordedLaneStrikesCellsOneToFiveTwiceEach() {
        var l = rpLine(5, 8); l.riffDir = .reverse; l.riffAdvanceEvery = 2; l.restartRhythmBars = [1]; l.restartMelodyPasses = [2]
        let events = rpStrikes([l], beats: 8)
        XCTAssertEqual(events.count, 10, "two passes of five hits")
        let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        let columnCells = restartTileState(.melody, cfg: cfg, beat: 0.1, running: true).columnCells
        var perCell = [Int](repeating: 0, count: 8)
        for ev in events {
            XCTAssertEqual(ev.cellColumn, ev.column, "a normal hit strikes the cell of the column it read")
            let cell = Int((columnCells >> UInt32(4 * Int(ev.cellColumn))) & 0xF)
            XCTAssertLessThan(cell, 8); perCell[cell] += 1
        }
        XCTAssertEqual(perCell, [2, 2, 2, 2, 2, 0, 0, 0], "cells 1–5 strike twice each (EVERY 2); the three ghosts never")
        XCTAssertEqual(events.map { Int($0.cellColumn) + 1 }, [8, 8, 7, 7, 6, 6, 5, 5, 4, 4], "REV: column 8 first, each note for two hits")
    }
    func testTiedAndSkippedRestsPostNoStrikeAndRepeatStrikesTheRepeatedNotesCell() {
        let ranks = [1, 0, 3, 0, 5, 6, 0, 8]          // columns 2, 4 and 7 (1-based) are rests
        for rest in [EuclidRiffOnRest.skip, .tie] {
            let l = rpLine(8, 8) { $0.riffOnRest = rest }
            let cols = Set(rpStrikes([l], ranks: ranks, beats: 4).map { Int($0.cellColumn) })
            XCTAssertEqual(cols, [0, 2, 4, 5, 7], "\(rest): a SKIP gap and a TIE continuation strike nothing (the tied note's onset already did)")
        }
        let rep = rpLine(8, 8) { $0.riffOnRest = .repeatLast }
        let events = rpStrikes([rep], ranks: ranks, beats: 4)
        let byColumn = Dictionary(uniqueKeysWithValues: events.map { (Int($0.column), Int($0.cellColumn)) })
        XCTAssertEqual(byColumn[1], 0, "the hit on the rest at column 2 repeats column 1's note: it strikes THAT cell"); XCTAssertEqual(byColumn[3], 2); XCTAssertEqual(byColumn[6], 5)
        XCTAssertEqual(byColumn[0], 0); XCTAssertEqual(byColumn[7], 7, "a real note still strikes its own column")
        XCTAssertEqual(events.count, 8, "REPEAT strikes on every hit")
    }
    func testAdvStepStrikesOnlyOnHitsEvenThoughTheWalkMovesOnEveryStep() {
        var l = rpLine(3, 8); l.riffAdvanceStep = true       // hits on steps 0, 3, 6 of 8; the walk reaches a new note on every step
        let events = rpStrikes([l], beats: 4)
        XCTAssertEqual(events.map { $0.onsetBeat }.map { ($0 * 4).rounded() / 4 }, [0, 1.5, 3])
        XCTAssertEqual(events.map { Int($0.cellColumn) }, [0, 3, 6], "the notes under the hits; the notes reached on the rest steps (columns 1, 2, 4, 5) post no strike")
    }

    func testRhythmPolishAWrappedHitBelongsToThePassItWrappedInto() {
        // E(3,8) TILT-fine +50 %: targets 2.5, 4.75, 7.0 steps. OFFSET 3 (rotate 5) carries them to 5.5, 7.75 and 2.0 on the bar, and a 0.6 fraction pushes the middle one past the end of the lap: 8.35 wraps to 0.35 step.
        // It plays 0.175 beat into THE SAME pass — the pass's first hit, rank 1 — not at the end of the previous one; the other two follow in time order (1.3 and 3.05 beats).
        var l = rpLine(3, 8, rotate: 5); l.tilt = 0.5; l.tiltFine = 0.5; l.offsetFraction = 0.6
        for frames: UInt32 in [64, 2048] {
            let ons = rpOns([l], beats: 4, frames: frames)
            assertBeats(ons, [0.175, 1.3, 3.05], "wrapped hit first, buffer \(frames)")
            XCTAssertEqual(ons.map { $0.note }, [48, 50, 52])
        }
    }
    // §11.15/§14.5 (adversarial-review fix — this test never existed): cycling LISTEN's mode, source,
    // SPEED, DIRECTION, DELAY and FEEL repeatedly, with long gates and a transport restart mid-run, must
    // never leave a note stuck — the same "cycling everything" stress shape `testNotesStressCyclingEverything
    // LeavesNothingSounding` already uses for the NOTES layer, applied to every `listen*` field instead.
    func testListenStressCyclingModeSourceSpeedAndDirectionLeavesNothingSounding() {
        let rhythms: [EuclideousListenRhythmMode] = [.own, .copy, .fill]
        let pitches: [EuclideousListenPitchMode] = [.own, .shadow, .echo, .avoid]
        let dirs: [EuclidDir] = [.fwd, .bkw, .pingpong]
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 512
        let wb = Double(frames) * tempo / 60.0 / sr
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        var beat = 0.0, ts = 0.0
        func linesFor(_ k: Int) -> [EuclidLine] {
            let red = EuclidLine(target: 0, pulses: 5, steps: 8, gate: 0.99, velocityAbsolute: 100, rate: .r1_8, emitterMask: 0b0001, useRiff: true, riffOn: true, sourceMode: .midi)
            var blue = EuclidLine(target: 0, pulses: 3, steps: 8, gate: 0.99, velocityAbsolute: 100, rate: .r1_8, emitterMask: 0b0010, useRiff: true, riffOn: true, sourceMode: .midi)
            blue.listenRhythm = rhythms[k % rhythms.count]; blue.listenPitch = pitches[k % pitches.count]
            blue.listenSource = 0; blue.listenSpeed = [-2, -1, 0, 1, 2][k % 5]
            blue.listenDirection = dirs[k % dirs.count]; blue.listenDelay = k % 4
            blue.listenFeel = Double(k % 3 - 1) * 0.3
            return [red, blue, EuclidLine(enabled: false), EuclidLine(enabled: false)]
        }
        for k in 0..<60 {
            let box = fxBox(linesFor(k))
            if k % 9 == 8 {   // a transport restart in the middle of everything
                router.process(box: box, pool: chord(listenPoolCMinor), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
            for _ in 0..<8 {
                router.process(box: box, pool: chord(listenPoolCMinor), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
        }
        router.process(box: fxBox(linesFor(0)), pool: chord(listenPoolCMinor), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        XCTAssertGreaterThan(e.ons.count, 50)
    }
    func testRhythmPolishStressWithTransportRestartsFXAndTiesLeavesNothingSounding() {
        var seed: UInt64 = 0xA24BAED4963EE407
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(max(1, n))) }
        let fx = fxCells([(0, 1, 3), (0, 4, 2), (1, 0, 50), (1, 3, 80), (2, 3, 1), (2, 6, 1), (3, 6, 120), (3, 4, 70)])
        for trial in 0..<24 {
            var lines: [EuclidLine] = []
            for _ in 0..<(1 + rnd(3)) {
                let steps = 3 + rnd(6)
                var l = rpLine(1 + rnd(steps), steps, dir: [.fwd, .bkw, .pingpong][rnd(3)], rotate: rnd(steps), rate: [.r1_8, .r1_16][rnd(2)], gate: [0.5, 0.9, 0.99][rnd(3)])
                l.offsetFraction = Double(rnd(99)) / 100
                if rnd(2) == 0 { let t = Double(rnd(199) - 99) / 100; l.tilt = t; l.tiltFine = t }
                l.riffOnRest = [.skip, .tie, .repeatLast][rnd(3)]
                if rnd(3) == 0 { l.restartRhythmBars = [[1], [2]][rnd(2)] }
                lines.append(l)
            }
            let e = fxRun(fxBox(lines, ranks: [1, 0, 3, 0, 5, 6, 0, 8], fx: fx), beats: 12, frames: [64, 1024][rnd(2)], restartAt: [3.3 + Double(rnd(40)) / 10])
            assertNothingLeftSounding(e)
            XCTAssertGreaterThan(e.ons.count, 5, "trial \(trial)")
        }
    }
    func testRhythmPolishRouterAndRollAgreeOnEveryHitTimeAndLengthForRandomLanes() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(max(1, n))) }
        var compared = 0, withTiming = 0
        for trial in 0..<60 {
            let steps = 2 + rnd(8)
            let dir: EuclidDir = [.fwd, .bkw, .pingpong][rnd(3)]
            var l = rpLine(1 + rnd(steps), steps, dir: dir, rotate: rnd(steps), rate: [.r1_8, .r1_16, .r1_4][rnd(3)], gate: [0.3, 0.5, 0.8][rnd(3)])
            if rnd(3) > 0 { l.offsetFraction = Double(1 + rnd(99)) / 100 }
            if rnd(2) == 0 { let t = Double(rnd(199) - 99) / 100; l.tilt = t; l.tiltFine = t }
            if rnd(4) == 0 { l.patternMiss = true }
            if rnd(3) == 0 { l.restartRhythmBars = [[1], [2], [1, 2]][rnd(3)] }
            if rnd(4) == 0 { l.riffOnRest = .tie }
            let ranks = rnd(3) == 0 ? [1, 0, 3, 0, 5, 6, 0, 8] : [1, 2, 3, 4, 5, 6, 7, 8]
            let e = fxRun(fxBox([l], ranks: ranks), beats: 15.9, frames: [64, 512, 2048][rnd(3)])
            assertNothingLeftSounding(e)
            let ons = e.ons.filter { $0.cable == 1 && Double($0.sample) / 24_000 < 15.8 }   // the run's last window overshoots 15.9 by a few ms; both sides compare only what is well inside it
            guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { XCTFail("cfg"); continue }
            if !cfg.timing.isNone { withTiming += 1 }
            let roll = euclideousLaneRollHits(cfg: cfg, windowStart: 0, windowBeats: 15.9, minGateBeats: 0.005) { col, _ in ranks[col] }
            let sounding = roll.filter { $0.audible && $0.rank >= 1 && $0.beat < 15.8 }
            XCTAssertEqual(sounding.count, ons.count, "trial \(trial): the roll's audible hits are exactly the Router's note-ons (\(l.pulses)/\(l.steps) \(dir) rot \(l.rotate) f \(l.offsetFraction ?? 0) tilt \(l.tiltFine ?? -9))")
            for (r, on) in zip(sounding, ons) {
                XCTAssertEqual(r.beat, Double(on.sample) / 24_000, accuracy: 0.01, "trial \(trial): hit beat")
                if let off = e.offs.first(where: { $0.cable == 1 && $0.note == on.note && $0.sample >= on.sample }) {
                    XCTAssertEqual(r.gateBeats, Double(off.sample - on.sample) / 24_000, accuracy: 0.02, "trial \(trial): gate length at beat \(r.beat)")
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThan(compared, 300); XCTAssertGreaterThan(withTiming, 25, "the fuzz must actually exercise hit timing")
    }

    // MARK: - LANE SOLO engine (ferry 2026-10-21, §8 tests 3-6 and 9; test 1 = the existing preset / synthetic-lane goldens, which run with the solo mask 0)

    /// Four lanes on their own buses (lane i → output A…D = cable 1…4), rate 1/8, E(i+2, 8), the riff over eight columns (every hit sounds a note), gate 50 %.
    private func soloLines(_ tweak: (Int, inout EuclidLine) -> Void = { _, _ in }) -> [EuclidLine] {
        (0..<4).map { i in
            var l = EuclidLine(target: 0, pulses: i + 2, steps: 8)
            l.gate = 0.5; l.velocityAbsolute = 100; l.rate = .r1_8; l.useRiff = true; l.litNotes = 0; l.riffOn = true; l.sourceMode = .midi
            l.riffLength = 8; l.notesOn = true; l.riffOnRest = .skip; l.emitterMask = 1 << UInt8(i)
            tweak(i, &l); return l
        }
    }
    private func soloBox(_ lines: [EuclidLine], solo: UInt8, fx: EuclideousFX = EuclideousFX()) -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = lines
        c.paramsA.soloMask = solo
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousFX = fx
        return SnapshotBuilder.build(from: st)
    }
    /// Plays `beats` beats in 2048-frame windows on ONE router, taking each window's box from `solo(windowStartBeat)` (a solo change reaches the render thread at a window boundary — the snapshot the next
    /// window acquires), optionally stopping and restarting the transport at the given beats. Returns the stream, the router and the window length in beats.
    private func soloRun(_ lines: [EuclidLine], beats: Double, restartAt: [Double] = [], fx: EuclideousFX = EuclideousFX(), stopAtEnd: Bool = true, live: ((Double) -> UInt16)? = nil, solo: (Double) -> UInt8)
        -> (e: RecordingEmitter, router: Router, windowBeats: Double) {
        let e = RecordingEmitter()
        let router = Router()
        var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        let p = chord(fxPoolNotes)
        var ts = 0.0, origin = 0.0
        func beatNow() -> Double { (ts - origin) * tempo / 60.0 / sr }
        var restarts = restartAt.sorted()
        var cache: [UInt8: SnapshotBox] = [:]
        func box(_ m: UInt8) -> SnapshotBox { if let b = cache[m] { return b }; let b = soloBox(lines, solo: m, fx: fx); cache[m] = b; return b }
        while beatNow() < beats {
            if let r = restarts.first, beatNow() >= r {
                restarts.removeFirst()
                router.process(box: box(solo(beatNow())), pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
                ts += Double(frames); origin = ts
            }
            router.process(box: box(solo(beatNow())), pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0,
                           euclideousSoloLive: live?(beatNow()) ?? 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        if stopAtEnd { router.process(box: box(0), pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag) }
        return (e, router, windowBeats)
    }
    private func soloOnSamples(_ e: RecordingEmitter, lane: Int) -> [Int64] { e.ons.filter { $0.cable == UInt8(1 + lane) }.map { Int64($0.sample) } }
    /// The first window start (in samples) at or after `beat`.
    private func soloWindowStartSample(atOrAfter beat: Double, windowBeats: Double) -> Int64 { Int64((ceil(beat / windowBeats - 1e-9) * windowBeats) * 24_000) }

    // §8.3
    func testSoloLatchedLaneOneSilencesTheOthersAndTheyComeBackInTimeBecauseTheyKeptWalking() {
        let lines = soloLines()
        let ref = soloRun(lines, beats: 32) { _ in 0 }
        let run = soloRun(lines, beats: 32) { $0 < 16 ? 0b0001 : 0 }
        let sw = soloWindowStartSample(atOrAfter: 16, windowBeats: run.windowBeats)
        XCTAssertEqual(soloOnSamples(run.e, lane: 0), soloOnSamples(ref.e, lane: 0), "the soloed lane is identical to an unsoloed render, throughout")
        XCTAssertGreaterThan(soloOnSamples(ref.e, lane: 0).count, 10)
        for lane in 1..<4 {
            XCTAssertTrue(soloOnSamples(run.e, lane: lane).filter { $0 < sw }.isEmpty, "lane \(lane + 1) is silent while lane 1 is soloed")
            let after = soloOnSamples(run.e, lane: lane).filter { $0 >= sw }, refAfter = soloOnSamples(ref.e, lane: lane).filter { $0 >= sw }
            XCTAssertFalse(refAfter.isEmpty)
            XCTAssertEqual(after, refAfter, "lane \(lane + 1) is back at exactly the samples a never-soloed render plays — it kept walking, so it is in time")
        }
        assertNothingLeftSounding(run.e)
    }
    func testASoloSilencedLaneMakesNoStrikesForThePulseFeed() {
        let run = soloRun(soloLines(), beats: 8, stopAtEnd: false) { _ in 0b0001 }
        let ev = run.router.drainEuclideousNoteViewEvents()
        XCTAssertFalse(ev[0].filter { $0.kind == 0 || $0.kind == 3 }.isEmpty, "the soloed lane strikes")
        for lane in 1..<4 { XCTAssertTrue(ev[lane].filter { $0.kind == 0 || $0.kind == 3 }.isEmpty, "lane \(lane + 1): a silenced lane posts no strike, so nothing pulses") }
    }
    // §8.4 — a momentary hold is the same thing to the engine (the effective mask), for exactly the bars it was held
    func testAHeldSoloSilencesTheOthersForExactlyTheBarsItWasHeld() {
        let lines = soloLines()
        let ref = soloRun(lines, beats: 24) { _ in 0 }
        let run = soloRun(lines, beats: 24) { ($0 >= 8 && $0 < 16) ? 0b0100 : 0 }
        let a = soloWindowStartSample(atOrAfter: 8, windowBeats: run.windowBeats), b = soloWindowStartSample(atOrAfter: 16, windowBeats: run.windowBeats)
        for lane in [0, 1, 3] {
            let got = soloOnSamples(run.e, lane: lane), want = soloOnSamples(ref.e, lane: lane)
            XCTAssertTrue(got.filter { $0 >= a && $0 < b }.isEmpty, "lane \(lane + 1) is silent while lane 3 is held")
            XCTAssertEqual(got.filter { $0 < a }, want.filter { $0 < a }, "lane \(lane + 1) plays as normal before")
            XCTAssertEqual(got.filter { $0 >= b }, want.filter { $0 >= b }, "…and as normal after")
            XCTAssertFalse(want.filter { $0 >= a && $0 < b }.isEmpty)
        }
        XCTAssertEqual(soloOnSamples(run.e, lane: 2), soloOnSamples(ref.e, lane: 2), "the held lane is identical to an unsoloed render")
        assertNothingLeftSounding(run.e)
    }
    // §8.5 — additive
    func testSoloIsAdditiveLanesOneAndFourPlayTwoAndThreeAreSilent() {
        let lines = soloLines()
        let ref = soloRun(lines, beats: 32) { _ in 0 }
        let run = soloRun(lines, beats: 32) { _ in 0b1001 }
        for lane in [0, 3] { XCTAssertEqual(soloOnSamples(run.e, lane: lane), soloOnSamples(ref.e, lane: lane), "lane \(lane + 1) plays exactly as unsoloed") }
        for lane in [1, 2] { XCTAssertTrue(soloOnSamples(run.e, lane: lane).isEmpty, "lane \(lane + 1) is silent") }
        assertNothingLeftSounding(run.e)
    }
    // §8.6 — stuck notes: legato (GATE 100) + TIE + ratchets, solo toggled and held across transport restarts
    func testSoloToggledAndHeldAcrossTransportRestartsLeavesNothingSounding() {
        let lines = soloLines { i, l in
            switch i {
            case 0: l.gate = 1.0; l.riffOnRest = .tie                  // legato, tied rests
            case 1: l.gate = 0.9                                        // ratchets (FX RATCH row, below)
            case 2: l.gate = 1.0; l.pulses = 5; l.rate = .r1_16         // legato at 1/16
            default: l.gate = 0.7
            }
        }
        let fx = fxCells([(0, 1, 4), (0, 4, 3), (2, 2, 1), (2, 6, 1), (1, 3, 50)])   // RATCH, TIE, GATE cells
        var rng: UInt64 = 0xDEADBEEF
        func next() -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int(rng >> 33) }
        var masks: [UInt8] = []
        for _ in 0..<2000 { masks.append(UInt8(next() % 16)) }
        let run = soloRun(lines, beats: 120, restartAt: [17.3, 41.9, 66.1, 90.4], fx: fx) { b in masks[min(masks.count - 1, Int(b / 0.37))] }
        XCTAssertGreaterThan(run.e.ons.count, 200)
        assertNothingLeftSounding(run.e)
        // every note-on of every lane has its note-off, per cable and note
        var open: [Int: Int] = [:]
        for ev in run.e.events where ev.status == 0x90 || ev.status == 0x80 {
            let k = (Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)
            open[k, default: 0] += ev.status == 0x90 ? 1 : -1
            XCTAssertGreaterThanOrEqual(open[k]!, 0, "a note-off with no note-on")
        }
        // (a retriggered note is closed before its re-strike, so every pitch is never left more than once on)
        XCTAssertTrue(open.values.allSatisfy { $0 == 0 }, "every note-on has its note-off")
    }
    // §8.9 — the display's dim equals what the Router did, hit by hit, with solo (latched / held changes) and LANES mutes in combination
    func testTheDisplayDimEqualsTheSoundForEveryHitOverEightBarsWithSoloHeldAndMuteInCombination() {
        let cells: [UInt16] = [0xFFFF, 0b1111_1111_0000_1111, 0b0101_0101_0101_0101, 0b1111_0000_1111_0000]   // lane 1 never muted; the others mute some 4-beat cells
        let lines = soloLines { i, l in l.muteCells16 = cells[i]; l.muteUnit = EuclideousMuteUnit.pass.rawValue }
        // latched lane 2 from bar 0; a hold of lane 4 for bars 2-3; both latched 1 and 3 for bars 5-6; nothing for bar 7
        func schedule(_ b: Double) -> UInt8 {
            switch b {
            case ..<8: return 0b0010
            case 8..<16: return 0b0010 | 0b1000
            case 16..<20: return 0
            case 20..<28: return 0b0101
            default: return 0
            }
        }
        let run = soloRun(lines, beats: 32, solo: schedule)
        var soundedHits = 0, dimmedHits = 0
        for lane in 0..<4 {
            let line = lines[lane]
            let buf = euclideousNoteViewPattern(pulses: line.pulses, steps: 8, rotate: 0, tilt: 0)
            let ons = soloOnSamples(run.e, lane: lane)
            for tick in 0..<Int(31.5 / 0.5) where buf[tick % 8] {
                let beat = Double(tick) * 0.5
                let w = Int(beat / run.windowBeats)   // the window this hit is rendered in
                let mask = schedule(Double(w) * run.windowBeats)
                let muteAudible = euclideousLaneAudible(beat: beat, cells16: cells[lane], unitBeats: 4)
                let dimmed = euclideousLaneIsDimmed(lane: lane, soloMask: mask, muteAudible: muteAudible)
                let sounded = ons.contains { abs($0 - Int64((beat * 24_000).rounded())) <= 3 }
                XCTAssertEqual(sounded, !dimmed, "lane \(lane + 1) hit at beat \(beat): window mask \(mask), mute audible \(muteAudible)")
                if sounded { soundedHits += 1 } else { dimmedHits += 1 }
            }
        }
        XCTAssertGreaterThan(soundedHits, 30); XCTAssertGreaterThan(dimmedHits, 30)
    }
    /// §11.3: how long one `SnapshotBuilder.build` takes — the main-thread cost between a SOLO touch and the snapshot the render thread acquires (`scheduleRebuild` builds one run-loop turn after the edit).
    func testSnapshotBuildTimeForTheSoloPath() {
        let lines = soloLines()
        let t0 = Date()
        let n = 20
        for i in 0..<n { _ = soloBox(lines, solo: UInt8(i % 16)) }
        let ms = Date().timeIntervalSince(t0) * 1000 / Double(n)
        print(String(format: "LANE SOLO: one SnapshotBuilder.build (4 lanes, debug macOS) ≈ %.2f ms", ms))
        XCTAssertLessThan(ms, 100)
    }

    // MARK: LANE SOLO — the mute kicks in IMMEDIATELY (Paul 2026-10-21): the UI's live word, and the cut of a silenced lane's sounding notes

    /// A solo the UI announces through the live word reaches the engine at the very next window — the snapshot (still saying "no solo") is not waited for — and the live word, once it has spoken, outranks the snapshot's.
    func testALiveSoloWordSilencesTheOtherLanesAtTheNextWindowWithoutAnySnapshot() {
        let lines = soloLines()
        let ref = soloRun(lines, beats: 24) { _ in 0 }
        let run = soloRun(lines, beats: 24, live: { $0 >= 8 ? 0x100 | 0b0001 : 0 }) { _ in 0 }   // the snapshot never says solo
        let sw = soloWindowStartSample(atOrAfter: 8, windowBeats: run.windowBeats)
        XCTAssertEqual(soloOnSamples(run.e, lane: 0), soloOnSamples(ref.e, lane: 0), "the soloed lane is untouched")
        for lane in 1..<4 {
            XCTAssertEqual(soloOnSamples(run.e, lane: lane).filter { $0 < sw }, soloOnSamples(ref.e, lane: lane).filter { $0 < sw }, "lane \(lane + 1) plays until the live word")
            XCTAssertTrue(soloOnSamples(run.e, lane: lane).filter { $0 >= sw }.isEmpty, "…and is silent from the very next window — no snapshot rebuild in between")
            XCTAssertFalse(soloOnSamples(ref.e, lane: lane).filter { $0 >= sw }.isEmpty)
        }
        // the live word outranks the snapshot: the snapshot says lane 1 is soloed, the page says "no solo" (0x100 | 0)
        let overridden = soloRun(lines, beats: 24, live: { _ in 0x100 }) { _ in 0b0001 }
        for lane in 0..<4 { XCTAssertEqual(soloOnSamples(overridden.e, lane: lane), soloOnSamples(ref.e, lane: lane), "lane \(lane + 1): the live \"none\" wins") }
        assertNothingLeftSounding(run.e)
    }
    /// The notes a silenced lane is ALREADY sounding end at once (a note-off at the first sample of the window the solo lands in) instead of ringing out their gate; the soloed lane's own notes are untouched.
    func testSoloEndsTheSilencedLanesSoundingNotesImmediatelyAndLeavesTheSoloedLaneAlone() {
        let lines = soloLines { _, l in l.pulses = 8; l.steps = 8; l.rate = .r1_2; l.gate = 0.9 }   // a hit every 2 beats, each note ~1.8 beats long
        let ref = soloRun(lines, beats: 12) { _ in 0 }
        let run = soloRun(lines, beats: 12, live: { $0 >= 7 ? 0x100 | 0b0001 : 0 }) { _ in 0 }
        let sw = soloWindowStartSample(atOrAfter: 7, windowBeats: run.windowBeats)   // the hit at beat 6 is mid-note (it would end at beat 7.8)
        func offs(_ e: RecordingEmitter, _ lane: Int) -> [Int64] { e.offs.filter { $0.cable == UInt8(1 + lane) }.map { Int64($0.sample) } }
        XCTAssertEqual(offs(run.e, 0), offs(ref.e, 0), "the soloed lane's notes end where they always do")
        XCTAssertEqual(soloOnSamples(run.e, lane: 0), soloOnSamples(ref.e, lane: 0))
        for lane in 1..<4 {
            let refOffs = offs(ref.e, lane), runOffs = offs(run.e, lane)
            let naturalEnd = refOffs.first { $0 > sw }!
            XCTAssertGreaterThan(naturalEnd, sw + 10_000, "in the unsoloed render lane \(lane + 1)'s note is still ringing well after the solo")
            XCTAssertTrue(runOffs.contains { $0 == sw }, "lane \(lane + 1)'s sounding note ends AT the window the solo landed in (sample \(sw))")
            XCTAssertFalse(runOffs.contains { $0 == naturalEnd }, "…not at its natural end")
            XCTAssertTrue(soloOnSamples(run.e, lane: lane).filter { $0 >= sw }.isEmpty)
        }
        assertNothingLeftSounding(run.e)
    }
    /// Ratchet repeats and legato holds belong to a lane too: a solo that silences it drops its pending repeats and closes its held notes — under a stream of live words, with TIE, GATE 100 and transport restarts, nothing is left sounding.
    func testLiveSoloWordsAcrossRatchetsLegatoAndTiesLeaveNothingSounding() {
        let lines = soloLines { i, l in
            switch i {
            case 0: l.gate = 1.0; l.riffOnRest = .tie
            case 1: l.gate = 0.9
            case 2: l.gate = 1.0; l.pulses = 5; l.rate = .r1_16
            default: l.gate = 0.7
            }
        }
        let fx = fxCells([(0, 1, 4), (0, 4, 3), (2, 2, 1), (2, 6, 1), (1, 3, 50)])
        var rng: UInt64 = 0xC0FFEE
        func next() -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int(rng >> 33) }
        var words: [UInt16] = []
        for _ in 0..<2000 { words.append(0x100 | UInt16(next() % 16)) }
        let run = soloRun(lines, beats: 120, restartAt: [17.3, 41.9, 66.1, 90.4], fx: fx, live: { words[min(words.count - 1, Int($0 / 0.37))] }) { _ in 0 }
        XCTAssertGreaterThan(run.e.ons.count, 150)
        assertNothingLeftSounding(run.e)
        var open: [Int: Int] = [:]
        for ev in run.e.events where ev.status == 0x90 || ev.status == 0x80 {
            let k = (Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)
            open[k, default: 0] += ev.status == 0x90 ? 1 : -1
            XCTAssertGreaterThanOrEqual(open[k]!, 0, "a note-off with no note-on")
        }
        XCTAssertTrue(open.values.allSatisfy { $0 == 0 }, "every note-on has its note-off")
    }

    // MARK: - RANDOM MODE ferry (§13 tests 9-10) — the apply-at-a-beat landing mechanism.
    // GRANULARITY, flagged plainly (ferry report §16.2): a landing is decided ONCE per `emitGeneratorRow`/
    // `emitTickRow` call (the render WINDOW's start beat), not per sample — `runEuclidLine` resolves a
    // lane's whole pattern once per call and has no mechanism to split a window mid-buffer. These tests
    // therefore pick a landing beat that is itself a hit position in BOTH the old and new pattern (the lap
    // downbeat), so the one window that straddles it can't misattribute that hit either way — proving the
    // mechanism switches at the right beat at the granularity it actually operates at, not claiming
    // sample-exactness this architecture doesn't have.

    private func euclideousRandomLandingFixture() -> (box: SnapshotBox, pool: NotePool) {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 4, rotate: 0, noteSel: .low, rate: .r1_4, sourceMode: .midi)]
        let st: PluginState = {
            var s = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                 scenes: [{ var sc = SceneState.empty(); sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return sc }()])
            s.euclideousNoteSource = .midi
            return s
        }()
        let pool = NotePool(); pool.noteOn(60, velocity: 100, channel: 0)
        return (SnapshotBuilder.build(from: st), pool)
    }

    /// Runs the fixture from beat 0 to `toBeats` with a single pending RHYTHM roll (4-of-4, i.e. every step
    /// hits) landing at `landingBeat`, at the given buffer size — no `run()`/`runKeepingRouter()` reuse
    /// (neither takes `euclideousPendingRolls`).
    private func runWithPendingRhythmRoll(landingBeat: Double, toBeats: Double, frames: UInt32) -> RecordingEmitter {
        let (box, pool) = euclideousRandomLandingFixture()
        let roll = EuclideousPendingRoll(tab: .rhythm, landingBeat: landingBeat, steps: 4, pulses: 4, rotate: 0)
        var rolls = EuclideousPendingRollSlots()
        rolls[euclideousRandomPendingSlot(lane: 0, tab: .rhythm)] = roll
        let e = RecordingEmitter()
        let router = Router()
        var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < toBeats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, beatsPerBar: 4,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0,
                           euclideousPendingRolls: rolls, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        return e
    }

    func testRandomModeRhythmLandingAtTheBarLineAcrossBufferSizes() {
        // OLD (1-of-4, hits at the lap downbeat only) for bars 1-2 [0,8), NEW (4-of-4) from bar 3 [8,12) —
        // landing at beat 8, itself a hit in both patterns. Expect 1 + 1 + 4 = 6 hits.
        for frames: UInt32 in [64, 256, 1024] {
            // 11.9, not 12 (the RouterTests convention, e.g. testEuclidSpanReAnchorsThePattern's own "3.9"):
            // stopping exactly on a lap boundary risks the LAST window straddling into lap 4's own downbeat.
            let e = runWithPendingRhythmRoll(landingBeat: 8, toBeats: 11.9, frames: frames)
            let ons = e.ons.filter { $0.cable == 1 }.count
            XCTAssertEqual(ons, 6, "buffer \(frames): expected 1(bar1)+1(bar2)+4(bar3, landed) = 6 hits, got \(ons)")
        }
    }

    func testRandomModeLandingNeverFiresBeforeItsBeat() {
        // A landing far in the future (beat 100) must never take effect during a short run — only the OLD
        // 1-of-4 pattern's single downbeat hit (3.9, not 4, for the same lap-boundary reason as above).
        let e = runWithPendingRhythmRoll(landingBeat: 100, toBeats: 3.9, frames: 256)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 1, "the far-future roll must not have landed yet")
    }

    func testRandomModeLandingAtBeatGranularity() {
        // §13 test 10's mechanism (the hold is the SAME EuclideousPendingRoll primitive at beat, not bar,
        // granularity — Router has no separate "hold" concept): landing at beat 2 (also a hit in neither
        // pattern's own right, proving the override applies even off a lap boundary) over a 4-beat run.
        // OLD (1-of-4) hits once at beat 0; NEW (4-of-4) then hits at 2 and 3 before the lap ends at 4.
        let e = runWithPendingRhythmRoll(landingBeat: 2, toBeats: 4, frames: 256)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 3, "expected the beat-0 OLD hit plus NEW hits at beats 2 and 3")
    }

    // MARK: - RANDOM MODE §5.6 — the HOLD channel through the real Router, not just its beat-math helpers.
    // `euclideousLandedRoll` (Router.swift) checks `euclideousHoldOverrides` FIRST, falling through to
    // `euclideousPendingRolls` only when no hold is active for that slot — these tests exercise exactly
    // that priority, and that the override is scoped to its own (lane, tab) slot, through a real
    // `router.process()` call. (§13 tests 9-11's own comment claimed this coverage already existed here;
    // it didn't — `euclideousHoldOverrides` had zero references in either test file before this.)

    private func runWithHold(pending: EuclideousPendingRoll?, hold: EuclideousPendingRoll?, toBeats: Double, frames: UInt32 = 256) -> RecordingEmitter {
        let (box, pool) = euclideousRandomLandingFixture()
        var pendingRolls = EuclideousPendingRollSlots(), holdOverrides = EuclideousPendingRollSlots()
        let slot = euclideousRandomPendingSlot(lane: 0, tab: .rhythm)
        pendingRolls[slot] = pending
        holdOverrides[slot] = hold
        let e = RecordingEmitter()
        let router = Router()
        var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < toBeats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, beatsPerBar: 4,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0,
                           euclideousPendingRolls: pendingRolls, euclideousHoldOverrides: holdOverrides, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        return e
    }

    func testHoldOverrideTakesPriorityOverAPendingRoll() {
        // Both land at beat 0 (immediate): the hold (4-of-4) must win over the pending roll (2-of-4) for
        // as long as both are present — proving Router's own priority order, not just that either alone works.
        let pending = EuclideousPendingRoll(tab: .rhythm, landingBeat: 0, steps: 4, pulses: 2, rotate: 0)
        let hold = EuclideousPendingRoll(tab: .rhythm, landingBeat: 0, steps: 4, pulses: 4, rotate: 0)
        // 3.9, not 4 (this file's own convention, e.g. testRandomModeRhythmLandingAtTheBarLineAcrossBufferSizes'
        // "11.9, not 12"): stopping exactly on the 4-beat lap boundary risks the last window straddling into
        // the NEXT lap's own beat-0 hit, over-counting by one.
        let e = runWithHold(pending: pending, hold: hold, toBeats: 3.9)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 4, "the hold's 4-of-4 must win every step of the bar, not the pending roll's 2-of-4")
    }

    func testHoldReleaseFallsBackToTheStillPendingRoll() {
        // The hold ends (its slot cleared, as the UI's own one-shot timer does) while a pending roll for
        // the SAME slot is still queued for a later beat: Router must fall through to it once it lands.
        let (box, pool) = euclideousRandomLandingFixture()
        let slot = euclideousRandomPendingSlot(lane: 0, tab: .rhythm)
        var pendingRolls = EuclideousPendingRollSlots()
        pendingRolls[slot] = EuclideousPendingRoll(tab: .rhythm, landingBeat: 4, steps: 4, pulses: 4, rotate: 0)
        var holdOverrides = EuclideousPendingRollSlots()
        holdOverrides[slot] = EuclideousPendingRoll(tab: .rhythm, landingBeat: 0, steps: 4, pulses: 0, rotate: 0)   // silent while held
        let e = RecordingEmitter()
        let router = Router()
        var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0
        let windowBeats = Double(256) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < 3.9 {   // still held: silent (0-of-4), the pending 4-of-4 hasn't landed yet either
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, beatsPerBar: 4,
                           sampleRate: sr, timestampSample: ts, frameCount: 256, forceColumn: 0,
                           euclideousPendingRolls: pendingRolls, euclideousHoldOverrides: holdOverrides, out: e, diag: &diag)
            beat += windowBeats; ts += 256
        }
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "the hold's 0-of-4 must silence the lane while it's active")
        holdOverrides[slot] = nil   // the hold's release timer clearing its slot
        while beat < 7.9 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, beatsPerBar: 4,
                           sampleRate: sr, timestampSample: ts, frameCount: 256, forceColumn: 0,
                           euclideousPendingRolls: pendingRolls, euclideousHoldOverrides: holdOverrides, out: e, diag: &diag)
            beat += windowBeats; ts += 256
        }
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 4, "once the hold releases, the still-queued 4-of-4 pending roll must land normally")
    }

    func testHoldOverrideIsScopedToItsOwnLaneTabSlot() {
        // A hold on lane 0's RHYTHM slot must not affect a pending roll sitting in a DIFFERENT slot
        // (lane 0's own RIFF slot here) — proving the override is read per-slot, not globally.
        let (box, pool) = euclideousRandomLandingFixture()
        var pendingRolls = EuclideousPendingRollSlots(), holdOverrides = EuclideousPendingRollSlots()
        let rhythmSlot = euclideousRandomPendingSlot(lane: 0, tab: .rhythm)
        let riffSlot = euclideousRandomPendingSlot(lane: 0, tab: .riff)
        XCTAssertNotEqual(rhythmSlot, riffSlot)
        pendingRolls[rhythmSlot] = EuclideousPendingRoll(tab: .rhythm, landingBeat: 0, steps: 4, pulses: 4, rotate: 0)
        holdOverrides[riffSlot] = EuclideousPendingRoll(tab: .riff, landingBeat: 0)   // a hold on an unrelated tab's slot
        let e = RecordingEmitter()
        let router = Router()
        var diag = KernelDiag()
        router.process(box: box, pool: pool, playing: true, beatPos: 0, tempo: 120, beatsPerBar: 4,
                       sampleRate: 48_000, timestampSample: 0, frameCount: 256, forceColumn: 0,
                       euclideousPendingRolls: pendingRolls, euclideousHoldOverrides: holdOverrides, out: e, diag: &diag)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 1, "the RIFF-slot hold must not block the RHYTHM slot's own landed pending roll")
    }

    // MARK: - LANE LOCK ferry (2026-10-21) — the tick-exact snap back (spec tests 5, 6, 7, 7a, 8, 9, 9a, the stuck-note stress, and "locks off changes nothing")
    // Method: the lane's position is a pure function of the beat, so a locked run's note-ons must equal a splice of STATIC renders — L's before the edit, the edit's from the moment it is published to the line, L's from
    // the line on. The hit AT the line is the sharp case: the old window-granular landing plays it with the old pattern whenever the window straddles the line.

    private struct LockStep { var beat: Double; var lines: [EuclidLine]; var snapRev: UInt32 = 0; var liveRev: UInt32 = 0; var held: UInt8 = 0 }
    private struct LockRun { let e: RecordingEmitter; let router: Router; var landings: [(window: Int, lane: Int, beat: Double)] }

    private func lockLine(pulses: Int, steps: Int = 8, rotate: Int = 0, rate: ArpRate = .r1_8, dir: EuclidDir? = nil, sel: EuclidNoteSel = .low) -> EuclidLine {
        EuclidLine(target: 0, pulses: pulses, steps: steps, rotate: rotate, noteSel: sel, direction: dir, rate: rate, sourceMode: .midi)
    }
    private func lockLanes(_ a: EuclidLine, _ b: EuclidLine? = nil, _ c: EuclidLine? = nil) -> [EuclidLine] {
        let silent = lockLine(pulses: 0)
        return [a, b ?? silent, c ?? silent, silent]
    }
    private func lockBox(_ lines: [EuclidLine], locks: [EuclideousLaneLock], revs: UInt32, fx: EuclideousFX? = nil, ranks: [Int]? = nil) -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        if let ranks { c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks) }
        c.paramsA.euclidLines = lines
        c.paramsA.euclideousLocks = locks.isEmpty ? nil : locks
        c.paramsA.lockRevs = revs
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var sc = SceneState.empty(); sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return sc }()])
        st.euclideousNoteSource = .midi
        if let fx { st.euclideousFX = fx }
        return SnapshotBuilder.build(from: st)
    }
    private func lockedRender(_ steps: [LockStep], locks: [EuclideousLaneLock], to: Double, frames: UInt32, chord: [UInt8] = [60], tempo: Double = 120, rolls: EuclideousPendingRollSlots = EuclideousPendingRollSlots(), fx: EuclideousFX? = nil, ranks: [Int]? = nil) -> LockRun {
        let sr = 48_000.0
        let pool = NotePool(); for n in chord { pool.noteOn(n, velocity: 100, channel: 0) }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let boxes = steps.map { lockBox($0.lines, locks: locks, revs: $0.snapRev, fx: fx, ranks: ranks) }
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0, w = 0, cur = 0
        var landings = [(window: Int, lane: Int, beat: Double)](), lastSeq: UInt32 = 0
        while beat < to {
            while cur + 1 < steps.count, steps[cur + 1].beat <= beat + 1e-12 { cur += 1 }
            let st = steps[cur]
            router.process(box: boxes[cur], pool: pool, playing: true, beatPos: beat, tempo: tempo, beatsPerBar: 4,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0,
                           euclideousPendingRolls: rolls,
                           euclideousLockLive: locks.isEmpty ? 0 : EuclideousLockLive.word(held: st.held, revs: st.liveRev), out: e, diag: &diag)
            let seq = router.lockSnapSeqPacked
            if seq != lastSeq {
                for lane in 0..<4 where EuclideousLockLive.rev(seq, lane: lane) != EuclideousLockLive.rev(lastSeq, lane: lane) { landings.append((w, lane, router.lockSnapBeats[lane])) }
                lastSeq = seq
            }
            beat += wb; ts += Double(frames); w += 1
        }
        router.process(box: boxes[cur], pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)   // stop edge → flush
        return LockRun(e: e, router: router, landings: landings)
    }
    /// A note-on's onset in beats, quantised to 1/1000 (every hit sits on a multiple of 1/16 beat; this absorbs the sample rounding).
    private func lockOnsets(_ e: RecordingEmitter, note: UInt8? = nil, tempo: Double = 120) -> [Double] {
        e.ons.filter { $0.cable == 1 && (note == nil || $0.note == note!) }.map { (Double($0.sample) / 48_000.0 * tempo / 60.0 * 1000).rounded() / 1000 }.sorted()
    }
    /// The onsets of `lines` rendered statically (no lock) up to `to`.
    private func staticOnsets(_ lines: [EuclidLine], to: Double, frames: UInt32, chord: [UInt8] = [60], note: UInt8? = nil) -> [Double] {
        lockOnsets(lockedRender([LockStep(beat: 0, lines: lines)], locks: [], to: to, frames: frames, chord: chord).e, note: note)
    }
    private func splice(_ segs: [(from: Double, to: Double, ons: [Double])]) -> [Double] {
        segs.flatMap { seg in seg.ons.filter { $0 >= seg.from - 1e-6 && $0 < seg.to - 1e-6 } }.sorted()
    }
    private func assertOnsets(_ got: [Double], _ want: [Double], _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, want.count, "\(msg): \(got) vs \(want)", file: file, line: line)
        for (g, w) in zip(got, want) { XCTAssertEqual(g, w, accuracy: 6e-4, msg, file: file, line: line) }
    }
    private func assertNothingSticks(_ r: LockRun, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.e.ons.count, r.e.offs.count, "\(msg): every note-on has its note-off", file: file, line: line)
        var open = [UInt16: Int]()
        for ev in r.e.events where ev.status == 0x90 || ev.status == 0x80 {
            let k = UInt16(ev.cable) << 8 | UInt16(ev.note)
            open[k, default: 0] += ev.status == 0x90 ? 1 : -1
        }
        XCTAssertTrue(open.values.allSatisfy { $0 == 0 }, "\(msg): nothing left sounding \(open)", file: file, line: line)
    }

    // 5 — lane 1 locked on 2 BARS at 3 OF 8; edited to 5 OF 8 in bar 3 beat 2 and lifted at beat 3: 5 OF 8 to the end of bar 4, 3 OF 8 from the line exactly.
    func testLockSnapBackLandsExactlyOnTheLineAtEveryBufferSize() {
        let L = lockLine(pulses: 3), B = lockLine(pulses: 5)
        let locks = [EuclideousLaneLock.locking(L, grid: .bars2), EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()]
        let refL = staticOnsets(lockLanes(L), to: 24, frames: 1024), refB = staticOnsets(lockLanes(B), to: 24, frames: 1024)   // a pure function of the beat: the same at any buffer size
        for frames: UInt32 in [64, 256, 1024] {
            // edited in bar 3, beat 2 (published at 9.25), lifted at beat 10
            let late = lockedRender([LockStep(beat: 0, lines: lockLanes(L)), LockStep(beat: 9.25, lines: lockLanes(B), snapRev: 1, liveRev: 1, held: 1),
                                     LockStep(beat: 10, lines: lockLanes(B), snapRev: 1, liveRev: 1)], locks: locks, to: 19.9, frames: frames)
            assertOnsets(lockOnsets(late.e), splice([(0, 9.25, refL), (9.25, 16, refB), (16, 20, refL)]), "buffer \(frames): 5 OF 8 to the end of bar 4, 3 OF 8 from the line")
            XCTAssertEqual(late.landings.map { $0.beat }, [16], "buffer \(frames): one snap, on the end of bar 4")
            assertNothingSticks(late, "buffer \(frames), bar 3 edit")
            // the same edit lifted in bar 2, beat 4 snaps at the end of bar 2
            let early = lockedRender([LockStep(beat: 0, lines: lockLanes(L)), LockStep(beat: 5.25, lines: lockLanes(B), snapRev: 1, liveRev: 1, held: 1),
                                      LockStep(beat: 7, lines: lockLanes(B), snapRev: 1, liveRev: 1)], locks: locks, to: 11.9, frames: frames)
            assertOnsets(lockOnsets(early.e), splice([(0, 5.25, refL), (5.25, 8, refB), (8, 12, refL)]), "buffer \(frames): an edit lifted in bar 2 snaps at the end of bar 2")
            XCTAssertEqual(early.landings.map { $0.beat }, [8])
            assertNothingSticks(early, "buffer \(frames), bar 2 edit")
        }
    }
    // 6 — an edit held across three lines never snaps while held; it snaps on the first line after the lift.
    func testLockHeldEditNeverSnapsWhileHeldAndSnapsOnTheFirstLineAfterTheLift() {
        let L = lockLine(pulses: 3), B = lockLine(pulses: 5)
        let locks = [EuclideousLaneLock.locking(L, grid: .bar1), EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()]
        let refL = staticOnsets(lockLanes(L), to: 20, frames: 1024), refB = staticOnsets(lockLanes(B), to: 20, frames: 1024)
        for frames: UInt32 in [64, 1024] {
            let r = lockedRender([LockStep(beat: 0, lines: lockLanes(L)), LockStep(beat: 1.25, lines: lockLanes(B), snapRev: 1, liveRev: 1, held: 1),
                                  LockStep(beat: 14.1, lines: lockLanes(B), snapRev: 1, liveRev: 1)], locks: locks, to: 19.9, frames: frames)
            XCTAssertEqual(r.landings.map { $0.beat }, [16], "buffer \(frames): lines 4, 8, 12 pass while a finger is down; the first line after the lift (16) snaps")
            assertOnsets(lockOnsets(r.e), splice([(0, 1.25, refL), (1.25, 16, refB), (16, 20, refL)]), "buffer \(frames)")
            assertNothingSticks(r, "held")
        }
    }
    // 7 — lanes 1 and 3 on 4 BARS, edited in bars 2 and 3: both snap at the end of bar 4, in one buffer.
    func testLockTwoLanesOnTheSameGridSnapTogetherInOneBuffer() {
        let L0 = lockLine(pulses: 3, sel: .low), B0 = lockLine(pulses: 5, sel: .low)
        let L2 = lockLine(pulses: 2, rate: .r1_4, sel: .high), B2 = lockLine(pulses: 3, rotate: 1, rate: .r1_4, sel: .high)
        let locks = [EuclideousLaneLock.locking(L0, grid: .bars4), EuclideousLaneLock(), EuclideousLaneLock.locking(L2, grid: .bars4), EuclideousLaneLock()]
        let chord: [UInt8] = [60, 67]
        let ref = { (a: EuclidLine, c: EuclidLine, note: UInt8) in self.staticOnsets(self.lockLanes(a, nil, c), to: 20, frames: 1024, chord: chord, note: note) }
        for frames: UInt32 in [64, 256, 1024] {
            let r = lockedRender([LockStep(beat: 0, lines: lockLanes(L0, nil, L2)),
                                  LockStep(beat: 5.25, lines: lockLanes(B0, nil, L2), snapRev: 1, liveRev: 1),
                                  LockStep(beat: 9.25, lines: lockLanes(B0, nil, B2), snapRev: 0x0100_0001, liveRev: 0x0100_0001)], locks: locks, to: 19.9, frames: frames, chord: chord)
            XCTAssertEqual(r.landings.count, 2, "buffer \(frames)")
            XCTAssertEqual(Set(r.landings.map { $0.window }).count, 1, "buffer \(frames): both lanes land in the same render window")
            XCTAssertEqual(r.landings.map { $0.beat }, [16, 16])
            // lane 1 (note 60): L, B0 from 5.25, L from 16 — lane 3 (note 67): L, B2 from 9.25, L from 16
            assertOnsets(lockOnsets(r.e, note: 60), splice([(0, 5.25, ref(L0, L2, 60)), (5.25, 16, ref(B0, L2, 60)), (16, 20, ref(L0, L2, 60))]), "buffer \(frames): lane 1")
            assertOnsets(lockOnsets(r.e, note: 67), splice([(0, 9.25, ref(L0, L2, 67)), (9.25, 16, ref(L0, B2, 67)), (16, 20, ref(L0, L2, 67))]), "buffer \(frames): lane 3")
            assertNothingSticks(r, "together")
        }
    }
    // 7a — BEAT grid: a change made on touch-down sounds from the next hit and is gone from the first beat after the lift.
    func testLockBeatGridMomentaryChangeIsGoneOnTheFirstBeatAfterTheLift() {
        let L = lockLine(pulses: 3, steps: 16, rate: .r1_16), B = lockLine(pulses: 9, steps: 16, rate: .r1_16)
        let locks = [EuclideousLaneLock.locking(L, grid: .beat), EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()]
        let refL = staticOnsets(lockLanes(L), to: 10, frames: 1024), refB = staticOnsets(lockLanes(B), to: 10, frames: 1024)
        for frames: UInt32 in [64, 1024] {
            let r = lockedRender([LockStep(beat: 0, lines: lockLanes(L)), LockStep(beat: 5.1, lines: lockLanes(B), snapRev: 1, liveRev: 1, held: 1),
                                  LockStep(beat: 6.4, lines: lockLanes(B), snapRev: 1, liveRev: 1)], locks: locks, to: 9.9, frames: frames)
            XCTAssertEqual(r.landings.map { $0.beat }, [7], "buffer \(frames): the beat-6 line passes under the finger; beat 7 is the first after the lift")
            assertOnsets(lockOnsets(r.e), splice([(0, 5.1, refL), (5.1, 7, refB), (7, 10, refL)]), "buffer \(frames)")
            assertNothingSticks(r, "beat grid")
        }
    }
    // 8 — the snap writes the restart chains back exactly (here a chain in L the edit replaced): the stream after the line is L's, chain restarts included.
    func testLockSnapRestoresRestartChainsAndRequestedFields() {
        var L = lockLine(pulses: 3, steps: 7); L.restartRhythmBars = [2]; L.restartMelodyPasses = []; L.hitsRequested = 3; L.offsetRequested = 0
        var B = lockLine(pulses: 5, steps: 7); B.restartRhythmBars = [1]; B.restartMelodyPasses = [2]; B.hitsRequested = 5
        let locks = [EuclideousLaneLock.locking(L, grid: .bars2), EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()]
        let frames: UInt32 = 256
        let refL = staticOnsets(lockLanes(L), to: 32, frames: frames), refB = staticOnsets(lockLanes(B), to: 32, frames: frames)
        let r = lockedRender([LockStep(beat: 0, lines: lockLanes(L)), LockStep(beat: 9.25, lines: lockLanes(B), snapRev: 1, liveRev: 1)], locks: locks, to: 31.9, frames: frames)
        assertOnsets(lockOnsets(r.e), splice([(0, 9.25, refL), (9.25, 16, refB), (16, 32, refL)]), "chains: L's restart pattern is back from the line, bar for bar")
        XCTAssertGreaterThan(Set(refL.filter { $0 >= 16 }).symmetricDifference(Set(refB.filter { $0 >= 16 })).count, 0, "the fixture discriminates: L and the edit differ after the line")
    }
    // 9 — external writes: a write mid-bar snaps at that bar's end; a stream every half beat is pulled back on each bar line and heard between them.
    func testLockExternalWritesAreHeardBetweenLinesAndPulledBackOnEach() {
        let L = lockLine(pulses: 3)
        let locks = [EuclideousLaneLock.locking(L, grid: .bar1), EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()]
        let frames: UInt32 = 256
        let refL = staticOnsets(lockLanes(L), to: 16, frames: frames)
        // one write, mid-bar 1 (beat 1.75): never held, settled → snaps at beat 4
        let refB = staticOnsets(lockLanes(lockLine(pulses: 6)), to: 16, frames: frames)
        let one = lockedRender([LockStep(beat: 0, lines: lockLanes(L)), LockStep(beat: 1.75, lines: lockLanes(lockLine(pulses: 6)), snapRev: 1, liveRev: 1)], locks: locks, to: 7.9, frames: frames)
        XCTAssertEqual(one.landings.map { $0.beat }, [4])
        assertOnsets(lockOnsets(one.e), splice([(0, 1.75, refL), (1.75, 4, refB), (4, 8, refL)]), "a write mid-bar snaps at that bar's end")
        // a stream: a new write every half beat (at x.25 / x.75), a different pulse count each time, each one settled
        var steps = [LockStep(beat: 0, lines: lockLanes(L))]
        let pulses = (0..<30).map { 4 + ($0 % 5) }
        for k in 0..<30 { steps.append(LockStep(beat: 0.25 + 0.5 * Double(k), lines: lockLanes(lockLine(pulses: pulses[k])), snapRev: UInt32(k + 1), liveRev: UInt32(k + 1))) }
        let stream = lockedRender(steps, locks: locks, to: 14.9, frames: frames)
        XCTAssertEqual(stream.landings.map { $0.beat }, [4, 8, 12], "pulled back on every bar line")
        let got = lockOnsets(stream.e)
        func slice(_ xs: [Double], _ lo: Double, _ hi: Double) -> [Double] { xs.filter { $0 >= lo - 1e-6 && $0 < hi - 1e-6 } }
        for line in [4.0, 8.0, 12.0] {
            // the write that was current when the line came is replaced by L on the line …
            assertOnsets(slice(got, line, line + 0.25), slice(refL, line, line + 0.25), "line \(line): L is back on the line")
            // … and the next write (0.25 later) is heard again
            let k = Int(line / 0.5)
            let wk = staticOnsets(lockLanes(lockLine(pulses: pulses[k])), to: 16, frames: frames)
            assertOnsets(slice(got, line + 0.25, line + 0.75), slice(wk, line + 0.25, line + 0.75), "line \(line): the stream is heard between lines")
        }
        assertNothingSticks(stream, "stream")
    }
    // 9a — the fill: lane 2 locked on 4 BARS at 3 OF 16; HITS 7 and REV written at bar 4 beat 3: that stretch is 7 OF 16 reversed, and bar 5 starts with 3 OF 16 forward, ON the downbeat.
    func testLockFillReturnsOnTheDownbeatOfTheNextPhrase() {
        let L = lockLine(pulses: 3, steps: 16, rate: .r1_16), B = lockLine(pulses: 7, steps: 16, rate: .r1_16, dir: .bkw)
        let locks = [EuclideousLaneLock(), EuclideousLaneLock.locking(L, grid: .bars4), EuclideousLaneLock(), EuclideousLaneLock()]
        let silent = lockLine(pulses: 0)
        func lanes(_ l: EuclidLine) -> [EuclidLine] { [silent, l, silent, silent] }
        let refL = staticOnsets(lanes(L), to: 20, frames: 1024), refB = staticOnsets(lanes(B), to: 20, frames: 1024)
        for frames: UInt32 in [64, 256, 1024] {
            XCTAssertTrue(refL.contains(16.0), "fixture: 3 OF 16 hits on the downbeat of bar 5")
            XCTAssertFalse(refB.contains(16.0), "fixture: the edit does NOT hit there, so a late landing would drop the downbeat")
            for (published, label) in [(14.1, "bar 4 beat 3"), (15.9, "0.1 beat before the line")] {
                let r = lockedRender([LockStep(beat: 0, lines: lanes(L)), LockStep(beat: published, lines: lanes(B), snapRev: 0x100, liveRev: 0x100)], locks: locks, to: 19.9, frames: frames)
                assertOnsets(lockOnsets(r.e), splice([(0, published, refL), (published, 16, refB), (16, 20, refL)]), "buffer \(frames), written at \(label)")
                XCTAssertEqual(r.landings.map { $0.beat }, [16], "buffer \(frames), \(label)")
                assertNothingSticks(r, "fill \(label)")
            }
            // an edit still on its way at the line waits one line (the next 4-bar line is 32): the live revision moved, the snapshot has not caught up
            let late = lockedRender([LockStep(beat: 0, lines: lanes(L)), LockStep(beat: 15.95, lines: lanes(B), snapRev: 0, liveRev: 0x100), LockStep(beat: 16.05, lines: lanes(B), snapRev: 0x100, liveRev: 0x100)], locks: locks, to: 19.9, frames: frames)
            XCTAssertTrue(late.landings.isEmpty, "buffer \(frames): an edit in flight at the line passes")
        }
    }
    // Locks that never deviate, or are absent, change nothing: the event stream is bit-identical to an unlocked render.
    func testLockOffAndUndeviatedLocksLeaveTheStreamUntouched() {
        let L = lockLine(pulses: 5, steps: 8)
        let steps = [LockStep(beat: 0, lines: lockLanes(L, lockLine(pulses: 3, rate: .r1_16, sel: .high)))]
        for frames: UInt32 in [64, 1024] {
            let none = lockedRender(steps, locks: [], to: 20, frames: frames, chord: [60, 67])
            let undeviated = lockedRender(steps, locks: [EuclideousLaneLock.locking(L, grid: .beat), EuclideousLaneLock.locking(lockLine(pulses: 3, rate: .r1_16, sel: .high), grid: .bars2), EuclideousLaneLock(), EuclideousLaneLock()], to: 20, frames: frames, chord: [60, 67])
            XCTAssertEqual(none.e.events, undeviated.e.events, "buffer \(frames): a lock at its own state leaves the stream bit-identical")
            XCTAssertTrue(undeviated.landings.isEmpty)
        }
    }
    // Nothing is left sounding whatever the edit schedule: random edits, holds and in-flight revisions over 64 beats, a chord, long gates.
    func testLockSnapNeverLeavesANoteSounding() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        for frames: UInt32 in [64, 1024] {
            for grid in [EuclideousLockGrid.beat, .bars4] {
                var L = lockLine(pulses: 4, sel: .all); L.gate = 0.99
                let locks = [EuclideousLaneLock.locking(L, grid: grid), EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()]
                var steps = [LockStep(beat: 0, lines: lockLanes(L))]
                var rev: UInt32 = 0, beat = 0.0
                while beat < 40 {
                    beat += 0.1 + Double(rnd(40)) / 20
                    var B = lockLine(pulses: 1 + rnd(8), steps: 4 + rnd(12), rotate: rnd(8), rate: [.r1_8, .r1_16, .r1_4][rnd(3)], dir: [nil, .bkw, .pingpong][rnd(3)], sel: .all); B.gate = 0.99
                    rev = (rev + 1) & 0xFF
                    let inFlight = rnd(5) == 0
                    steps.append(LockStep(beat: beat, lines: lockLanes(rnd(4) == 0 ? L : B), snapRev: inFlight ? (rev &- 1) & 0xFF : rev, liveRev: rev, held: rnd(4) == 0 ? 1 : 0))
                    if inFlight { steps.append(LockStep(beat: beat + 0.03, lines: steps.last!.lines, snapRev: rev, liveRev: rev, held: steps.last!.held)) }
                }
                let r = lockedRender(steps, locks: locks, to: 44, frames: frames, chord: [60, 64, 67])
                assertNothingSticks(r, "buffer \(frames), grid \(grid)")
                XCTAssertGreaterThan(r.e.ons.count, 20)
            }
        }
    }
    // The in-flight safety valve: if the page's publish never arrives, the lane is held off its grid for at most a second, never forever.
    func testLockAnEditThatNeverArrivesDoesNotHoldTheLaneOffItsGridForever() {
        let L = lockLine(pulses: 3), B = lockLine(pulses: 5)
        let locks = [EuclideousLaneLock.locking(L, grid: .beat), EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()]
        let r = lockedRender([LockStep(beat: 0, lines: lockLanes(L)), LockStep(beat: 5.25, lines: lockLanes(B), snapRev: 0, liveRev: 1)], locks: locks, to: 9.9, frames: 1024)
        XCTAssertEqual(r.landings.map { $0.beat }, [8], "lines 6 and 7 pass (in flight for 0.4 s and 0.9 s); beat 8 comes 1.4 s in and snaps")
    }
    // 13 — random mode: a locked lane that has moved still snaps on its grid line while a throw is in flight on another lane (the engine has no notion of random mode: the two mechanisms don't touch).
    func testLockedLaneStillSnapsWhileARandomRollIsInFlightOnAnotherLane() {
        let L = lockLine(pulses: 3, sel: .low), B = lockLine(pulses: 5, sel: .low)
        let other = lockLine(pulses: 2, rate: .r1_4, sel: .high)
        let locks = [EuclideousLaneLock.locking(L, grid: .bars2), EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()]
        let roll = EuclideousPendingRoll(tab: .rhythm, landingBeat: 6, steps: 8, pulses: 4, rotate: 0)
        let chord: [UInt8] = [60, 67]
        let frames: UInt32 = 256
        var slots = EuclideousPendingRollSlots(); slots[3] = roll
        let ref = { (a: EuclidLine) in self.staticOnsets(self.lockLanes(a, other), to: 12, frames: 1024, chord: chord, note: 60) }
        let r = lockedRender([LockStep(beat: 0, lines: lockLanes(L, other)), LockStep(beat: 5.25, lines: lockLanes(B, other), snapRev: 1, liveRev: 1)],
                             locks: locks, to: 11.9, frames: frames, chord: chord, rolls: slots)
        XCTAssertEqual(r.landings.map { $0.beat }, [8])
        assertOnsets(lockOnsets(r.e, note: 60), splice([(0, 5.25, ref(L)), (5.25, 8, ref(B)), (8, 12, ref(L))]), "the locked lane is back on its line with a roll landing on lane 2")
        XCTAssertNotEqual(lockOnsets(r.e, note: 67), staticOnsets(lockLanes(L, other), to: 12, frames: 1024, chord: chord, note: 67), "the other lane took its roll (it plays differently from the no-roll render)")
        assertNothingSticks(r, "random mode alongside a lock")
    }
    // ADVERSARIAL REVIEW (2026-10-22): the landing across the engine's long-note machinery — a riff with rests under TIE / REPEAT, FX ratchets, TIE and a 95 % GATE, on a locked lane whose settings flip at random, with random holds
    // and in-flight edits. A tied note's off and a ratchet's tail are scheduled from the OLD line before the line; they must still end on their own.
    func testLockSnapAcrossTieRatchetAndGateNeverLeavesANoteSounding() {
        var seed: UInt64 = 0xD1B54A32D192ED03
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        func fxLane(_ pulses: Int, _ onRest: EuclidRiffOnRest, dir: RiffDir, step: Bool) -> EuclidLine {
            var l = EuclidLine(target: 0, pulses: pulses, steps: 8)
            l.gate = 0.95; l.velocityAbsolute = 90; l.rate = .r1_8; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi
            l.riffLength = 8; l.notesOn = true; l.riffOnRest = onRest; l.riffDir = dir; l.riffAdvanceStep = step
            l.setLitOrder(EuclideousLitOrder.derived(litNotes: 0b11, top: false, top2: false))
            return l
        }
        let ranks = [1, 0, 3, 0, 5, 6, 0, 8]   // rests in the riff, so TIE / REPEAT have something to do
        var fx = EuclideousFX()
        for (r, c, v) in [(2, 1, 1), (2, 4, 1), (1, 2, 95), (1, 5, 95), (0, 3, 4), (0, 6, 3), (0, 0, 2)] { fx.cells[r * 8 + c] = Int8(v) }
        fx.notePasses = 4
        let L = fxLane(5, .tie, dir: .forward, step: false)
        for frames: UInt32 in [64, 1024] {
            for grid in [EuclideousLockGrid.beat, .bars2] {
                let locks = [EuclideousLaneLock.locking(L, grid: grid), EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()]
                var steps = [LockStep(beat: 0, lines: lockLanes(L))]
                var rev: UInt32 = 0, beat = 0.0
                while beat < 36 {
                    beat += 0.1 + Double(rnd(40)) / 20
                    let B = fxLane(1 + rnd(8), [.skip, .tie, .repeatLast][rnd(3)], dir: [.forward, .reverse, .pendulum, .pingpong][rnd(4)], step: rnd(2) == 0)
                    rev = (rev + 1) & 0xFF
                    let inFlight = rnd(5) == 0
                    steps.append(LockStep(beat: beat, lines: lockLanes(rnd(4) == 0 ? L : B), snapRev: inFlight ? (rev &- 1) & 0xFF : rev, liveRev: rev, held: rnd(4) == 0 ? 1 : 0))
                    if inFlight { steps.append(LockStep(beat: beat + 0.03, lines: steps.last!.lines, snapRev: rev, liveRev: rev, held: steps.last!.held)) }
                }
                let r = lockedRender(steps, locks: locks, to: 40, frames: frames, chord: [48, 51, 55], fx: fx, ranks: ranks)
                assertNothingSticks(r, "TIE / ratchet / gate, buffer \(frames), grid \(grid)")
                XCTAssertGreaterThan(r.e.ons.count, 20)
                XCTAssertFalse(r.landings.isEmpty, "buffer \(frames), grid \(grid): the schedule must have produced snaps for this test to mean anything")
            }
        }
    }
    // The count-down's latency margin: how long the main→render path takes to build a snapshot (the page's side of it; the render side adds at most one buffer).
    func testLockSnapshotBuildTimeForTheMarginEstimate() {
        let L = lockLine(pulses: 5)
        let locks = [EuclideousLaneLock.locking(L, grid: .bar1), EuclideousLaneLock.locking(L, grid: .bars2), EuclideousLaneLock(), EuclideousLaneLock()]
        let t0 = Date()
        for _ in 0..<20 { _ = lockBox(lockLanes(L, L, L), locks: locks, revs: 3) }
        let ms = Date().timeIntervalSince(t0) / 20 * 1000
        print("LANE LOCK: SnapshotBuilder.build ≈ \(String(format: "%.2f", ms)) ms (macOS, release-ish test build) — the UI margin is \(EuclideousLockMargin.seconds * 1000) ms")
        XCTAssertLessThan(ms, EuclideousLockMargin.seconds * 1000)
    }
}

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

    func testArpSoundsAndLeavesNothingStuck() {
        // One ARP cell (col 0, bus A) over a 3-note chord, run a full 8-column cycle then stop.
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)          // S=2 → one full cycle
        XCTAssertGreaterThan(e.ons.count, 0, "the arp should have sounded during column 0's window")
        assertNothingLeftSounding(e)
    }

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
    // INVESTIGATION (Paul 2026-10-04): "I sometimes see euclid play for only half the duration of a pass on the
    // part grid" + "it feels more like a problem with the part grid than the euclid, or it may be in the way they
    // interact." Builds the EXACT real pipeline (BuildSceneLogic.composeScene → SnapshotBuilder → Router) instead
    // of a hand-rolled SnapshotBox, mimicking a freshly-created EUCLID row (today's real fresh-card default: 1
    // pulse of 8 steps, GRID 1/16, SPAN free) selected across every column of a freshly-created, all-default part
    // — to see whether the PART GRID's own composition silently restricts playback to less than the part's full
    // pass, independent of EUCLID's own internal math. A bare NotePool chord (not a held one) is used, matching a
    // real `[A]→receiver` live-input setup rather than a latch.
    func testEuclidFreshRowOnAFreshPartPlaysThroughTheWholePass() {
        var eu = ProcessorSlot(type: .euclid)
        eu.params.euclidPulses = 1; eu.params.euclidSteps = 8   // today's real fresh-card default (1-of-8, pick=LOW)

        var part = BuildPart()
        for c in 0..<8 { part.stagingCells[c][0] = "gold" }        // row 0 spans every visible column (CLONE/CREATE's own effect)
        part.stagingSel = Array(repeating: 0, count: Snap.maxCols) // row 0 selected in every column
        part.rowChain[0] = [eu]
        part.emitters = [.a]
        // rate/length left nil ⇒ the scene default (today's real "freshly created part" state)

        var input = BuildSceneLogic.Input()
        input.ferryParts[0] = part
        input.ferryRowChain[0] = part.rowChain
        input.ferryOn[0] = true
        input.ferryAudible[0] = true

        let scene = BuildSceneLogic.composeScene(input)!
        let st = PluginState(machines: [Machine(machineID: "gold", type: .euclid)], scenes: [scene])
        let snap = SnapshotBuilder.build(from: st)

        let e = RecordingEmitter()
        run(snap, chord([60]), beats: 64, into: e)   // several full passes (pass = Snap.cols(8) × stepRate .r1_2(2 beats) = 16 beats)
        assertNothingLeftSounding(e)

        let passBeats = 16.0
        let onBeats = e.ons.filter { $0.cable == 1 }.map { Double($0.sample) / (48_000.0 * 60.0 / 120.0) }
        XCTAssertFalse(onBeats.isEmpty, "the fresh euclid row should sound at all")
        // Bucket every onset by its position WITHIN its own pass (mod 16 beats) into first-half / second-half.
        let firstHalf = onBeats.filter { $0.truncatingRemainder(dividingBy: passBeats) < passBeats / 2 }.count
        let secondHalf = onBeats.count - firstHalf
        XCTAssertGreaterThan(secondHalf, 0, "onsets cluster in the FIRST half of every \(passBeats)-beat pass only (\(firstHalf) first-half vs \(secondHalf) second-half) — reproduces the reported symptom")
    }
    // Same investigation, but on a 16-COLUMN part (the STEPS 8|16 toggle — a PART GRID feature, not a EUCLID one) —
    // testing Paul's own redirect: "it feels more like a problem with the part grid than the euclid, or it may be
    // in the way they interact." Also forces an EXPLICIT rate/length (not nil) to exercise the MULTI-CLOCK per-row
    // path instead of the uniform fast path the all-defaults test above silently fell onto.
    func testEuclidFreshRowOnA16WidePartPlaysThroughAllSixteenColumns() {
        var eu = ProcessorSlot(type: .euclid)
        eu.params.euclidPulses = 1; eu.params.euclidSteps = 8

        var part = BuildPart()
        for c in 0..<16 { part.stagingCells[c][0] = "gold" }
        part.stagingSel = Array(repeating: 0, count: Snap.maxCols)
        part.rowChain[0] = [eu]
        part.emitters = [.a]
        part.rate = .r1_8      // EXPLICIT (not nil) ⇒ forces the per-row multi-clock path
        part.length = 16       // the 16-step part width

        var input = BuildSceneLogic.Input()
        input.ferryParts[0] = part
        input.ferryRowChain[0] = part.rowChain
        input.ferryOn[0] = true
        input.ferryAudible[0] = true

        let scene = BuildSceneLogic.composeScene(input)!
        // Sanity: the PART GRID's own composition must actually reach all 16 logical columns, before blaming EUCLID.
        let base = Snap.ferryRowBase(0)
        for c in 0..<16 { XCTAssertNotNil(scene.cellAt(c, base), "composeScene dropped column \(c) of 16 — a PART GRID bug, not EUCLID") }
        XCTAssertEqual(scene.rowLen?[base], 16, "the row's own resolved length must be the full 16, not truncated to 8")

        let st = PluginState(machines: [Machine(machineID: "gold", type: .euclid)], scenes: [scene])
        let snap = SnapshotBuilder.build(from: st)
        let e = RecordingEmitter()
        let passBeats = 16.0 * 0.5   // 16 columns × 1/8-note (0.5 beat) step
        run(snap, chord([60]), beats: passBeats * 4, into: e)
        assertNothingLeftSounding(e)

        let onBeats = e.ons.filter { $0.cable == 1 }.map { Double($0.sample) / (48_000.0 * 60.0 / 120.0) }
        XCTAssertFalse(onBeats.isEmpty, "the fresh euclid row should sound at all")
        let firstHalf = onBeats.filter { $0.truncatingRemainder(dividingBy: passBeats) < passBeats / 2 }.count
        let secondHalf = onBeats.count - firstHalf
        XCTAssertGreaterThan(secondHalf, 0, "onsets cluster in the FIRST half of the 16-column pass only (\(firstHalf) vs \(secondHalf)) — reproduces the symptom on a 16-wide part")
    }
    // PART GRID × GENERATOR interaction bug, ROUND 2 (Paul 2026-10-05): the same hardcoded-8-column defect found
    // in the EUCLID fix above turned out to be systemic — STRIKE PER SPAN, CHORDS-hold, TUTTI PATTERN, LENGTH,
    // STRUM, and MOD all independently hardcoded Double(Snap.cols)*S instead of the row's real pass length. Each
    // test below forces the MULTI-CLOCK path (an explicit, non-default rowStepRate) on a 16-column row and proves
    // the SPAN control now scales with the row's real width.

    // STRIKE PER SPAN: on a 16-column row, SPAN=8 ("the whole row") must mean 16 beats, re-articulating ONCE per
    // full pass — not twice (at the real halfway point, col 8), which is what the hardcoded 8-column fallback gave.
    func testStrikePerSpanWholeRowUsesTheRealRowLength() {
        var c = Machine(machineID: "gold", type: .drone)
        c.paramsA.strikePerSpan = true; c.paramsA.strikeSpanN = 8   // 8 = "the whole row" rung (spanLadderBeats' row: argument)
        let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { s in
            for col in 0..<16 { s.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }
            s.rowStepRate = [.r1_4] + Array(repeating: nil, count: 7)   // 1 beat/column
            s.rowLen = [16] + Array(repeating: nil, count: 7)           // a genuinely 16-column row
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 15.9, into: e)   // one full 16-beat pass, no wrap
        assertNothingLeftSounding(e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 1,
                       "the whole-row span is 16 beats on a 16-column row → re-articulates once per pass, not twice at the old hardcoded 8-beat halfway point")
    }
    // TUTTI PATTERN / LENGTH / MOD share one proof shape: an explicit ×2 span on a (bug-immune) 8-column row is a
    // trusted 16-beat reference; the SAME nominal 16 beats via the "whole row" rung on a genuinely 16-column row
    // must produce an IDENTICAL result if cycleBeats correctly tracks the real row width. The reference case is
    // bug-immune because on an 8-column row Snap.cols already equals the real length, bug or no bug.
    func testTuttiPatternSpanUsesTheRealRowLength() {
        func onsets(rowLen: Int, spanN: Int) -> [Int64] {
            var c = Machine(machineID: "gold", type: .tutti)
            c.paramsA.tuttiMode = .pattern; c.paramsA.tuttiSpanN = spanN
            c.paramsA.tuttiRate = .r1_1   // 4-beat slices: 8×4=32 is not a multiple of either candidate span (8 or 16), so a wrong re-anchor is observable
            c.paramsA.tuttiSlices = [.rest, .rest, .all, .rest, .rest, .rest, .rest, .rest]
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { s in
                for col in 0..<rowLen { s.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }
                s.rowStepRate = [.r1_4] + Array(repeating: nil, count: 7)
                s.rowLen = [rowLen] + Array(repeating: nil, count: 7)
            }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 31.9, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { $0.sample }.sorted()
        }
        let ref = onsets(rowLen: 8, spanN: 16)     // 2× an 8-column row = 16 beats, unaffected by the bug
        let real = onsets(rowLen: 16, spanN: 8)    // "the whole row" on a genuinely 16-column row = 16 beats, ONLY if fixed
        XCTAssertFalse(ref.isEmpty, "the reference case should sound at all")
        XCTAssertEqual(ref, real, "a 16-column row's own 'whole row' SPAN must land identically to an explicit ×2 span on an 8-column row — both are nominally 16 beats")
    }
    func testLengthSpanUsesTheRealRowLength() {
        func onsets(rowLen: Int, spanN: Int) -> [Int64] {
            var c = Machine(machineID: "gold", type: .length)
            c.paramsA.lenSpanN = spanN
            c.paramsA.lenSlices = [.pass, .mute, .pass, .mute, .pass, .mute, .pass, .mute]
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { s in
                for col in 0..<rowLen { s.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }
                s.rowStepRate = [.r1_4] + Array(repeating: nil, count: 7)
                s.rowLen = [rowLen] + Array(repeating: nil, count: 7)
            }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 31.9, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { $0.sample }.sorted()
        }
        let ref = onsets(rowLen: 8, spanN: 16)
        let real = onsets(rowLen: 16, spanN: 8)
        XCTAssertFalse(ref.isEmpty, "the reference case should sound at all")
        XCTAssertEqual(ref, real, "a 16-column row's own 'whole row' LENGTH span must land identically to an explicit ×2 span on an 8-column row")
    }
    // MOD: `.row` mode's step TABLE is always resolved to exactly 8 entries (SnapshotBuilder clamps modSteps.count
    // to 8/16/32 by modStepSpan, independent of any row-length bug) — so unlike TUTTI/LENGTH, the observable here
    // isn't WHICH steps are reached, it's WHEN (the real-beat SPEED of walking those 8 steps). modSteps has a
    // single HIGH entry at index 5, rest LOW. With period correctly = 16 beats (a 16-column row's whole-row span),
    // phase 5/8 — and so the HIGH step — lands at beat 16×5/8 = 10. Under the old hardcoded-8-beat bug it would
    // land at beat 8×5/8 = 5 instead (and again at 13, repeating every 8 beats) — never at 10.
    func testModRowSpanUsesTheRealRowLength() {
        var mod = ProcessorSlot(type: .mod)
        mod.params.modCC = 74; mod.params.modSource = .steps; mod.params.modSmooth = false; mod.params.modStepSpan = .row
        mod.params.modSteps = [0, 0, 0, 0, 0, 127, 0, 0]   // HIGH only at index 5
        mod.params.modMin = 0; mod.params.modMax = 127
        let cs = arpMachines()
        let b = box(machines: cs) { s in
            for col in 0..<16 { s.cells[col][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
            s.rowStepRate = [.r1_4] + Array(repeating: nil, count: 7)   // 1 beat/column
            s.rowLen = [16] + Array(repeating: nil, count: 7)           // a genuinely 16-column row
        }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        let tempo = 120.0, sr = 48_000.0
        func beatOf(_ s: Int64) -> Double { Double(s) / (sr * 60.0 / tempo) }
        let highNear10 = modCC74Events(e).contains { Int($0.vel) > 60 && abs(beatOf($0.sample) - 10) < 0.5 }
        let highNear5 = modCC74Events(e).contains { Int($0.vel) > 60 && abs(beatOf($0.sample) - 5) < 0.5 }
        XCTAssertTrue(highNear10, "with the real 16-beat period, the single HIGH step lands at beat 16×5/8=10")
        XCTAssertFalse(highNear5, "beat 5 is where the HIGH step would land under the old hardcoded-8-beat period — it must NOT appear there")
    }
    // DEST MATRIX (Paul 2026-08-22 §5): [ARP→DEST] hockets the walk across emitters — each onset-slice routes to its
    // chosen emitter (the routing override wins over the cell's fan-out).
    func testDestMatrixHocketsTheArpAcrossEmitters() {
        func run2(_ withDest: Bool) -> [RecordingEmitter.Ev] {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var dest = ProcessorSlot(type: .dest); dest.params.destSlices = [0, 1, 2, 3, 0, 1, 2, 3]
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) {
                $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); c.processors = withDest ? [arp, dest] : [arp]; return c }()
            }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable >= 1 }   // emitter cables (1=A…4=D), excluding the All cable 0
        }
        let plain = run2(false), hocket = run2(true)
        XCTAssertGreaterThan(Set(hocket.map { $0.cable }).count, 1, "DEST spreads the arp across multiple emitters")
        XCTAssertLessThan(hocket.count, plain.count, "DEST routes each note to ONE emitter, not the 4-way fan-out")
    }
    // MUTE MATRIX (Paul 2026-08-25 §5): [ARP→MUTE] gates emitters per step — a muted emitter goes silent while the
    // others keep playing; an all-zero mask is byte-identical (nothing muted); nothing left sounding either way.
    func testMuteMatrixGatesEmittersPerStep() {
        func run2(_ withMute: Bool, _ mask: Int) -> RecordingEmitter {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mute = ProcessorSlot(type: .muteMatrix); mute.params.muteSlices = Array(repeating: mask, count: 8)
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) {
                $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); c.processors = withMute ? [arp, mute] : [arp]; return c }()
            }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e
        }
        let plain = run2(false, 0), zero = run2(true, 0), muteA = run2(true, 0b0001)   // 0b0001 = emitter A muted every step
        XCTAssertEqual(zero.events, plain.events, "MUTE MATRIX with an all-zero mask is byte-identical (nothing muted)")
        XCTAssertFalse(muteA.ons.contains { $0.cable == 1 }, "MUTE silences emitter A (cable 1) on every step")
        XCTAssertTrue(muteA.ons.contains { $0.cable == 2 }, "the other emitters keep playing")
        XCTAssertLessThan(muteA.ons.filter { $0.cable >= 1 }.count, plain.ons.filter { $0.cable >= 1 }.count, "muting drops A's copies")
    }
    // RATCHET COIN PASS-THROUGH fold (Paul 2026-09-06): downstream of an ARP, RATCHET stops driving — the ARP drives and each
    // note PASSES THROUGH unless the COIN fires (then a burst). chance 0 ⇒ identical note-on count to the arp alone (true
    // passthrough); chance 1 ⇒ every note bursts (more note-ons). Nothing left sounding either way.
    func testRatchetFoldPassesThroughUnlessTheCoinFires() {
        func arpCell(_ procs: [ProcessorSlot]) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        func fold(chance: Double, count: Int) -> ProcessorSlot {
            var r = ProcessorSlot(type: .ratchet); r.params.rtcMode = .coin; r.params.rtcFold = true
            r.params.rtcChance = chance; r.params.rtcCountLo = count; r.params.rtcCountHi = count; return r
        }
        let arpOnly = arpCell([arp])
        let pass = arpCell([arp, fold(chance: 0, count: 3)])
        let burst = arpCell([arp, fold(chance: 1, count: 3)])
        XCTAssertEqual(pass, arpOnly, "fold with chance 0 passes every arp note through unchanged (arp still drives)")
        XCTAssertGreaterThan(burst, arpOnly, "fold with chance 1 ratchets every note into a burst")
    }
    // HUMANIZE / SHIFT reclassified as per-note MODIFIERS (Paul 2026-09-06): downstream of an ARP they no longer re-pool the
    // chord — they jitter/push each arp note IN PLACE, keeping the arp's rhythm. So [ARP→SHIFT] / [ARP→HUMANIZE] emit the SAME
    // number of note-ons as the arp alone (one modified note per arp note); standalone they STILL generate.
    func testHumanizeShiftFoldOntoTheDriverNotRepool() {
        func cellCount(_ procs: [ProcessorSlot]) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var shift = ProcessorSlot(type: .shift); shift.params.spread = 0.5
        var human = ProcessorSlot(type: .humanize); human.params.spread = 0.8
        let arpOnly = cellCount([arp])
        XCTAssertEqual(cellCount([arp, shift]), arpOnly, "[ARP→SHIFT] pushes each arp note — same note count as the arp (not re-pooled)")
        XCTAssertEqual(cellCount([arp, human]), arpOnly, "[ARP→HUMANIZE] jitters each arp note — same note count as the arp (not re-pooled)")
        XCTAssertGreaterThan(cellCount([human]), 0, "standalone HUMANIZE still generates")
        XCTAssertGreaterThan(cellCount([shift]), 0, "standalone SHIFT still generates")
    }
    // FOLD must MODIFY, not just preserve the count (Housekeeping 2026-09-07): the count-equality test above would still pass
    // if a fold regressed to a pass-through identity. SHIFT pushes each arp note LATER → [ARP→SHIFT] onset-sum strictly > arp.
    func testShiftFoldActuallyDelaysArpOnsets() {
        func onsets(_ procs: [ProcessorSlot]) -> [Int64] {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { $0.sample }.sorted()
        }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var shift = ProcessorSlot(type: .shift); shift.params.spread = 1.0
        let base = onsets([arp]), shifted = onsets([arp, shift])
        XCTAssertEqual(base.count, shifted.count, "SHIFT pushes each note in place — same count")
        XCTAssertGreaterThan(shifted.reduce(0, +), base.reduce(0, +), "[ARP→SHIFT] delays the onsets (a pass-through identity fold would not)")
    }
    // HUMANIZE fold is replay-safe (seeded) AND actually perturbs (jitters onset/velocity vs the arp alone).
    func testHumanizeFoldIsReplaySafeAndPerturbs() {
        func stamps(_ procs: [ProcessorSlot]) -> [[Int64]] {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { [$0.sample, Int64($0.note), Int64($0.vel)] }
        }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var human = ProcessorSlot(type: .humanize); human.params.spread = 0.9
        let a = stamps([arp, human]), b = stamps([arp, human])
        XCTAssertEqual(a, b, "HUMANIZE is seeded → two runs byte-identical (replay-safe)")
        XCTAssertNotEqual(stamps([arp]), a, "HUMANIZE actually perturbs the arp's onsets/velocities")
    }
    // VELOCITY fold (Paul 2026-09-07): a downstream VELOCITY overrides each driver note's velocity from its per-step lane
    // (NOTE clock = one column per arp note), and a PASSTHROUGH step leaves the inherited velocity. Note-transparent → same count.
    func testVelocityFoldOverridesPerStepAndPassesThrough() {
        func vels(_ procs: [ProcessorSlot]) -> [Int] {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.vel) }
        }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var vel = ProcessorSlot(type: .velocity)
        vel.params.velSteps = 2; vel.params.velLane = [30, 120]; vel.params.velPass = [0, 0]
        vel.params.velRate = .r1_16; vel.params.velClock = .note   // advance one lane column per arp note
        let overridden = vels([arp, vel])
        XCTAssertEqual(overridden.count, vels([arp]).count, "VELOCITY is note-transparent — same note count as the arp")
        XCTAssertTrue(overridden.allSatisfy { $0 == 30 || $0 == 120 }, "each note takes its lane step's velocity (30/120), overriding the inherited value")
        XCTAssertTrue(overridden.contains(30) && overridden.contains(120), "both lane steps are heard")
        var passVel = vel; passVel.params.velPass = [1, 1]   // every step passthrough
        XCTAssertEqual(vels([arp, passVel]), vels([arp]), "an all-passthrough VELOCITY leaves the arp's own velocities untouched")
    }
    // VELOCITY TIME clock (Paul 2026-09-08 housekeeping — the DEFAULT path, previously fuzz-only): the lane advances on
    // VELOCITY's OWN rate grid, not per note. At arp 1/16 into velRate 1/8, two arp notes share each 1/8 lane column →
    // longer RUNS of one velocity than NOTE mode (which flips every note).
    func testVelocityFoldTimeClockAdvancesOnItsOwnRateGrid() {
        func vels(_ clock: RatchetClock) -> [Int] {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var vel = ProcessorSlot(type: .velocity); vel.params.velSteps = 2; vel.params.velLane = [30, 120]; vel.params.velRate = .r1_8; vel.params.velClock = clock
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, vel]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map { Int($0.vel) }
        }
        func transitions(_ a: [Int]) -> Int { zip(a, a.dropFirst()).filter { $0 != $1 }.count }
        let t = vels(.time), n = vels(.note)
        XCTAssertTrue(t.contains(30) && t.contains(120), "TIME: both lane values are heard")
        XCTAssertLessThan(transitions(t), transitions(n), "TIME advances per RATE slot (2 arp notes per 1/8 → longer runs) vs NOTE flipping every note")
    }
    // VELOCITY SPAN re-anchor (Paul 2026-09-08 housekeeping — previously fuzz-only): velSpanN>0 re-anchors the lane every
    // N columns, so only the first N lane values are ever read (vs free-run sweeping all velSteps).
    func testVelocityFoldSpanReanchorsTheLane() {
        func vels(_ span: Int) -> [Int] {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var vel = ProcessorSlot(type: .velocity); vel.params.velSteps = 4; vel.params.velLane = [40, 60, 80, 100]; vel.params.velRate = .r1_8; vel.params.velClock = .time; vel.params.velSpanN = span
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, vel]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.vel) }
        }
        let free = vels(0), span2 = vels(2)
        XCTAssertFalse(span2.contains(80) || span2.contains(100), "SPAN=2 re-anchors every 2 columns → only lane[0],lane[1] (40,60) ever read")
        XCTAssertTrue(free.contains(80) || free.contains(100), "free-run (SPAN=0) sweeps all 4 lane columns")
    }
    // EUCLID MASK (Paul 2026-09-27): the arp-only euclid mask (arpMask*) pulled out as its own downstream FOLD
    // processor (isModifierFoldable, like SHIFT/HUMANIZE/VELOCITY) — a K-of-N Bjorklund pattern gates ANY driver's
    // notes, not just ARP's own. WAIT/WALK was dropped (needs the driver's own phase-index, out of a fold's reach).
    func testEuclidMaskFoldRestDropsGapNotes() {
        func arpCellCount(_ mask: ProcessorSlot?) -> Int {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var procs = [arp]; if let m = mask { procs.append(m) }
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 4; mask.params.maskGap = .rest
        let arpOnly = arpCellCount(nil)
        let masked = arpCellCount(mask)
        XCTAssertLessThan(masked, arpOnly, "[ARP→EUCLID MASK(4-of-8, REST)] drops the gap ticks — fewer note-ons than the arp alone")
    }
    // TIE: the SAME hit ticks gate through as REST (same note-on count), but each hit's gate is extended across the
    // following gap run instead of staying at its own short length — so its off-times land strictly later than REST's.
    func testEuclidMaskFoldTieExtendsGateAcrossGaps() {
        func offInfo(_ gap: ArpMaskGap) -> (count: Int, offSum: Int64) {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 4; mask.params.maskGap = gap
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            let offs = e.offs.filter { $0.cable == 1 }
            return (offs.count, offs.reduce(Int64(0)) { $0 + $1.sample })
        }
        let rest = offInfo(.rest), tie = offInfo(.tie)
        XCTAssertEqual(tie.count, rest.count, "TIE and REST gate the SAME hit ticks — same note-on/off count")
        XCTAssertGreaterThan(tie.offSum, rest.offSum, "TIE extends each hit's gate across its following gap run — later offs than REST's un-extended gates")
    }
    // CHORD: a gap strikes the WHOLE composed input chord instead of resting — for a 3-note chord this emits MORE
    // note-ons than the arp alone (each of the ~half-the-ticks gaps becomes a 3-note stab instead of nothing).
    func testEuclidMaskFoldChordStabsTheGap() {
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 4; mask.params.maskGap = .chord
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        func count(_ procs: [ProcessorSlot]) -> Int {
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let arpOnly = count([arp]), chorded = count([arp, mask])
        XCTAssertGreaterThan(chorded, arpOnly, "[ARP→EUCLID MASK(4-of-8, CHORD)] strikes the whole 3-note chord on every gap — more note-ons than the arp alone")
    }
    // Paul's literal repro (2026-09-29, "chord isn't sounding"): a chain of ARP→VELOCITY, then EUCLID MASK added
    // after it (GAPS=CHORD, 7-of-8), didn't sound; removing VELOCITY didn't fix it either. Chain edits are
    // POSITION-PRESERVING (buildChainRemoveSlot leaves a bypassed .empty PASSTHROUGH, never shifts later slots) — so
    // post-removal the real chain is [ARP(0), EMPTY/bypassed(1), EUCLID MASK(2)], not the tight [ARP, EUCLID MASK]
    // every other test here builds. Locks in both real shapes from his repro as permanent regression coverage —
    // investigated 2026-09-29: both already passed (engine-level; the reported silence wasn't reproducible off-device).
    func testEuclidMaskChordFoldsAcrossAPositionPreservingEmptySlot() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        func count(_ procs: [ProcessorSlot]) -> Int {
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 7; mask.params.maskGap = .chord
        let empty: ProcessorSlot = { var s = ProcessorSlot(type: .empty); s.bypassed = true; return s }()   // buildPassthroughSlot()'s exact shape
        let arpOnly = count([arp])
        let gapped = count([arp, empty, mask])   // ARP(0) · EMPTY/bypassed(1) · EUCLID MASK(2) — the exact post-removal shape
        XCTAssertGreaterThan(gapped, arpOnly, "[ARP→EMPTY→EUCLID MASK] (the shape a remove-then-mask leaves) still strikes the chord on gaps")
    }
    func testEuclidMaskChordFoldsWithVelocityStillInTheChain() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        func count(_ procs: [ProcessorSlot]) -> Int {
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var vel = ProcessorSlot(type: .velocity)
        var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 7; mask.params.maskGap = .chord
        let arpOnly = count([arp])
        let withVel = count([arp, vel, mask])   // ARP(0) → VELOCITY(1) → EUCLID MASK(2) — Paul's ORIGINAL chain, before he removed VELOCITY
        XCTAssertGreaterThan(withVel, arpOnly, "[ARP→VELOCITY→EUCLID MASK] strikes the chord on gaps with VELOCITY still in the chain")
    }
    // ROTATE shifts WHICH ticks gate through (not just how many — a Bjorklund K-of-N always keeps exactly K hits per
    // N regardless of rotation), so two different rotations of the SAME K/N must produce different onset sets.
    func testEuclidMaskFoldRotateShiftsWhichStepsGate() {
        func onsets(_ rotate: Int) -> [Int64] {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 3; mask.params.maskRotate = rotate
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { $0.sample }
        }
        XCTAssertNotEqual(onsets(0), onsets(2), "rotating the Bjorklund figure changes WHICH ticks gate through, not just how many")
    }
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
    // Driver-agnostic, the actual point of pulling this out of ARP: [RIFF→EUCLID MASK] gates just like [ARP→EUCLID
    // MASK] does — don't just re-prove it on arp.
    func testEuclidMaskFoldsOntoRiffToo() {
        func riffCount(_ withMask: Bool) -> Int {
            var riff = ProcessorSlot(type: .riff); riff.params.riffRate = .r1_16
            var procs = [riff]
            if withMask { var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 4; procs.append(mask) }
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertLessThan(riffCount(true), riffCount(false), "[RIFF→EUCLID MASK] also gates — proves the mask is driver-agnostic, not arp-only")
    }
    // Standalone (no driver upstream): an explicit v1 no-op, like DEST/VELOCITY/CLOCK/KILL STEP — nothing to fold
    // onto, so a lone [EUCLID MASK] must behave exactly like an empty chain (the AVOID-class "silently emits nothing
    // standalone" bug this guards against — Housekeeping 2026-08-31).
    func testEuclidMaskAloneIsANoOp() {
        let cs = arpMachines()
        var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 4   // an ACTIVE mask — still nothing to fold onto
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mask]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67],
                       "a lone EUCLID MASK has no driver to fold onto — it's a no-op, exactly like an empty chain")
        assertNothingLeftSounding(e)
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
    // SPAN re-anchors the pattern's own ordinal to 0 every N notes — a span SHORTER than the mask's own window (N=8,
    // SPAN=4) forces the SAME first-4-ticks' hit/gap decision to repeat instead of continuing into the pattern's
    // natural second half, so it must differ from FREE (which just lets the pattern run its full natural length).
    func testEuclidMaskSpanReanchorsEveryNNotes() {
        func onsetTicks(_ spanN: Int) -> Set<Int64> {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 3; mask.params.maskSpanN = spanN
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 3, into: e)
            assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { $0.sample })
        }
        XCTAssertNotEqual(onsetTicks(0), onsetTicks(4), "a SPAN shorter than the mask's own N-window changes which ticks gate through vs FREE")
    }
    // ACCENT is a second, independent K/N/ROTATE pattern that only ever RAISES velocity on its own hits — with the
    // GATE off (K=N, a passthrough) an active accent layer must still push the peak velocity above the unaccented run.
    func testEuclidMaskAccentBoostsVelocityOnItsOwnHits() {
        func peakVel(_ accentOn: Bool) -> Int {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 8   // gate OFF — passthrough
            if accentOn { mask.params.maskAccentN = 8; mask.params.maskAccentK = 4; mask.params.maskAccentAmount = 40 }
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.vel) }.max() ?? 0
        }
        XCTAssertGreaterThan(peakVel(true), peakVel(false), "an active accent layer boosts velocity on its own hits above the un-accented baseline")
    }
    // FILL overrides the mask entirely on its own passes — over a window spanning several passes, "fill every 2"
    // must let through MORE notes than the plain 3-of-8 mask alone (the filled passes add back the gapped steps).
    func testEuclidMaskFillPlaysEveryStepOnTheFillPass() {
        func noteCount(_ fillEvery: Int) -> Int {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 3
            if fillEvery > 0 { mask.params.maskFillEvery = fillEvery }
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 24, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertGreaterThan(noteCount(2), noteCount(0), "FILL every 2 passes plays extra steps the plain 3-of-8 mask would otherwise gate out")
    }
    // PROBABILITY can only DEMOTE a hit to a gap, never promote a gap to a hit — chance 0 must never produce MORE
    // notes than chance 1, and on an active K<N mask it genuinely removes hits (not a no-op). With the gate OFF
    // (K=N) chance must have NO effect at all — it's unreachable outside an active gate, checked structurally.
    func testEuclidMaskChanceCanOnlyReduceHits() {
        func noteCount(_ chance: Double, k: Int, n: Int) -> Int {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = n; mask.params.maskK = k; mask.params.maskChance = chance
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let full = noteCount(1.0, k: 4, n: 8), zero = noteCount(0.0, k: 4, n: 8)
        XCTAssertLessThan(zero, full, "chance 0 on an active K<N mask removes hits — strictly fewer notes than chance 1")
        XCTAssertEqual(noteCount(0.0, k: 8, n: 8), noteCount(1.0, k: 8, n: 8), "with the gate OFF (K=N) CHANCE has no effect at all — it's unreachable outside an active gate")
    }
    // CHORD PICK restricts a gap-stab to specific chord note(s) instead of always striking the whole chord. K=1-of-16
    // makes 15 of 16 ticks chord-stabs and only 1 the arp's own hit (which may land on any chord tone) — tolerate
    // that ONE non-mask-controlled note when checking pitch content.
    func testEuclidMaskChordPickStrikesOnlyTheRequestedNote() {
        func notes(_ pick: MaskChordPick) -> [UInt8] {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 16; mask.params.maskK = 1; mask.params.maskGap = .chord; mask.params.maskChordPick = pick
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { $0.note }
        }
        let low = notes(.low)
        XCTAssertLessThanOrEqual(low.filter { $0 != 60 }.count, 1, "LOW strikes only the chord's lowest note on every gap (at most the one arp hit differs)")
        let high = notes(.high)
        XCTAssertLessThanOrEqual(high.filter { $0 != 67 }.count, 1, "HIGH strikes only the chord's highest note on every gap (at most the one arp hit differs)")
        let all = notes(.all)
        XCTAssertGreaterThan(all.count, low.count, "ALL strikes the whole 3-note chord per gap — far more note-ons than LOW's one-per-gap")
        let cycle = notes(.cycle)
        XCTAssertGreaterThan(Set(cycle).count, 1, "CYCLE rotates through the chord — visits more than one distinct pitch across many gaps")
        // BOTTOM2/TOP2 (Paul 2026-09-28): the two lowest/highest chord tones, twice as many note-ons per gap as LOW/HIGH.
        let bottom2 = notes(.bottom2)
        XCTAssertLessThanOrEqual(bottom2.filter { $0 != 60 && $0 != 64 }.count, 1, "BOTTOM2 strikes only the two lowest chord tones on every gap (at most the one arp hit differs)")
        XCTAssertTrue(Set(bottom2).isSuperset(of: [60, 64]), "BOTTOM2 actually strikes BOTH lowest tones, not just one")
        XCTAssertGreaterThan(bottom2.count, low.count, "BOTTOM2 fires twice per gap — more note-ons than LOW's once per gap")
        let top2 = notes(.top2)
        XCTAssertLessThanOrEqual(top2.filter { $0 != 64 && $0 != 67 }.count, 1, "TOP2 strikes only the two highest chord tones on every gap (at most the one arp hit differs)")
        XCTAssertTrue(Set(top2).isSuperset(of: [64, 67]), "TOP2 actually strikes BOTH highest tones, not just one")
        XCTAssertGreaterThan(top2.count, high.count, "TOP2 fires twice per gap — more note-ons than HIGH's once per gap")
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
    // A chain whose ONLY driver is a fold-ratchet (COIN pass-through) must still DRIVE: chainDriverIndex skips isRatchetFold
    // but falls back to the last driver when there's no non-fold driver, so a lone [RATCHET COIN rtcFold] generates.
    func testLoneFoldableRatchetStillDrives() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .ratchet) }
        var r = ProcessorSlot(type: .ratchet); r.params.rtcMode = .coin; r.params.rtcFold = true
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [r]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        assertNothingLeftSounding(e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "a lone fold-ratchet has nothing to fold onto → it drives + generates")
    }
    // RATCHET PATTERN (Paul 2026-09-07): a PASS-THROUGH with its OWN clock — the arp drives; a passing note reads whichever
    // column the ratchet's own-RATE playhead is on at that instant: 1 = pass through, 2…8 = ratchet. Never silent (no rest).
    // So an all-1 matrix == the bare arp; an all-3 matrix ratchets every note (more strikes).
    func testRatchetPatternRatchetsOnActiveColumns() {
        func cellCount(_ slices: [Int]) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var procs = [arp]
            if !slices.isEmpty {   // empty ⇒ the bare arp (baseline); else [ARP → RATCHET PATTERN]
                var rat = ProcessorSlot(type: .ratchet); rat.params.rtcMode = .pattern; rat.params.rtcSteps = slices.count; rat.params.rtcSlices = slices; rat.params.ramp = 0
                procs.append(rat)
            }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let arpOnly = cellCount([])                                  // no ratchet slot → the bare arp
        let allPass = cellCount(Array(repeating: 1, count: 8))       // every column = pass through
        let allRat  = cellCount(Array(repeating: 3, count: 8))       // every column = ratchet ×3
        XCTAssertEqual(allPass, arpOnly, "all-passthrough = the arp untouched (one note per arp note, NEVER silent — no rest)")
        XCTAssertGreaterThan(allRat, allPass, "all-ratchet-3 re-fires each arp note (more strikes than passthrough)")
    }
    // CLOCK (AcceptanceCriteria-clock-processor, Paul 2026-09-26, Stage 1 flagship consumer): [ARP → CLOCK → RATCHET]
    // — the ratchet fold's OWN column math must read the CLOCK-transformed beat, not the raw one. The arp fires 4
    // notes at m = 0, 0.5, 1, 1.5 (rate 1/8 over 4 beats); the ratchet's own rate defaults to 0.5 beats/column, so
    // WITHOUT any clock those land on columns [0,1,2,3]. The special (×3-ratchet) column is deliberately COLUMN 1,
    // not 0 — column 0 is invariant under any pure ratio scaling (0 × anything = 0), so it can't discriminate a
    // working transform from a no-op one (the mistake this test caught on first write: with column 0 special, ×1
    // and ×2 produced the identical total by coincidence, even though the underlying beats genuinely differed — a
    // direct RTCDEBUG trace of clockTransformedBeat's output confirmed the transform itself was correct). At ×2 the
    // same 4 notes land on columns [0,2,4,6] — column 1 is never hit, so the burst disappears entirely. Uses a
    // single-step, all-SET DRAWN lane (`drawnClock`, below) as a plain "multiply the beat by N" clock — CLOCK's
    // FIXED/WAVE modes were built here and removed the same day (Paul's own spec describes only this grid).
    func testClockTransformsTheRatchetFoldsOwnColumnMath() {
        func strikeCount(clockRatioIndex: Int?) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var procs = [arp]
            if let idx = clockRatioIndex { procs.append(drawnClock(ratioIndex: idx)) }
            var rat = ProcessorSlot(type: .ratchet); rat.params.rtcMode = .pattern
            rat.params.rtcSteps = 8; rat.params.rtcSlices = [1, 3, 1, 1, 1, 1, 1, 1]; rat.params.ramp = 0   // only column 1 ratchets ×3
            procs.append(rat)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let noClock = strikeCount(clockRatioIndex: nil)
        let atRatioOne = strikeCount(clockRatioIndex: clockRatioLadder.firstIndex(of: 1)!)   // ×1 = the identity rung
        let atRatioTwo = strikeCount(clockRatioIndex: clockRatioLadder.firstIndex(of: 2)!)   // ×2
        XCTAssertEqual(atRatioOne, noClock, "a ×1 CLOCK stage is a no-op — byte-identical to no CLOCK at all (test #5)")
        XCTAssertEqual(noClock, 6, "sanity: 3 plain notes (col 0,2,3) + 1 burst-of-3 (col 1, the note at m=0.5) = 6")
        XCTAssertEqual(atRatioTwo, 4, "×2 moves every note off column 1 entirely (0,2,4,6) — the burst disappears, all 4 notes pass through plain")
        XCTAssertNotEqual(atRatioTwo, noClock, "the transform genuinely changes which note gets ratcheted, not just a coincidental match")
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
    // GLIDE genuinely changes the fold result vs SET for the same authored ratio sequence. RATE was removed
    // 2026-09-26 — a clock column is now always the cell's own step S, not an independently-dialled value — so
    // `forceColumn: 0` bypasses the column-lap gate, letting real time advance far enough to actually reach the
    // lane's column 1 (a bare, un-held cell otherwise only ticks during its own grid column's real-time window).
    // Asserted comparatively (not against a hand-derived exact count), matching this session's standing rule
    // against hard-coding values that depend on floor-quantization/column interplay not under test.
    func testClockDrawnSetAndGlideProduceDifferentFoldResults() {
        func strikeCount(glide: Bool) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var ck = ProcessorSlot(type: .clock)
            ck.params.clockDrawnSteps = 2
            ck.params.clockDrawnRatios = [clockRatioLadder.firstIndex(of: 4)!, clockRatioLadder.firstIndex(of: 1)!]
            ck.params.clockDrawnGlide = [false, glide]
            ck.params.clockSpanN = 0
            var rat = ProcessorSlot(type: .ratchet); rat.params.rtcMode = .pattern
            rat.params.rtcSteps = 8; rat.params.rtcSlices = [1, 3, 1, 1, 1, 1, 1, 1]; rat.params.ramp = 0
            let procs = [arp, ck, rat]
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            // forceColumn: 0 — see testClockDrawnGlideRowSoftensTheColumnTransition's comment: a bare cell only
            // ticks during its own grid column's real-time window ([0, S)), and this lane's column-1 boundary
            // (real beat S, now that RATE ties to S) sits right at that window's edge, so bypassing the gate lets
            // real time keep advancing far enough to actually reach column 1.
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let set = strikeCount(glide: false), glideOn = strikeCount(glide: true)
        XCTAssertNotEqual(set, glideOn, "the SAME authored ratio sequence folds differently as SET (snap) vs GLIDE (ramp)")
    }
    // CLOCK Stage 3 (Paul 2026-09-26): extends clockTransformedBeat to the OTHER self-clocked consumers that can
    // genuinely sit downstream of a real driver's fold — DEST, VELOCITY, TUTTI (via emitDriverNote's forward scan)
    // and MOD (its own chain-position scan, since it has no driver at all). EUCLID/BURST/CASCADE/WEAVE/RIFF are
    // drivers themselves (isDriverType) — chainDriverIndex always makes them the LAST driver-type slot, so they
    // never reach a downstream-fold position under the current architecture; retiming THEM needs the still-open
    // CLOCK-before-a-driver inversion problem, out of scope here (see the Stage-1 scoping note in the outbox).
    //
    // [ARP→CLOCK ×2→DEST]: DEST routes column 1 (the only note at m=0.5, WITHOUT clock) to emitter B; every other
    // column routes to A. WITH a ×2 clock the same 4 notes (mClock = 0,1,2,3) land on columns 0,2,4,6 — column 1 is
    // never hit, so DEST never picks B at all.
    func testClockTransformsDestsOwnRoutingClock() {
        func cableBCount(clockRatio: Int?) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var procs = [arp]
            if let ratio = clockRatio { procs.append(drawnClock(ratioIndex: ratio)) }
            var dest = ProcessorSlot(type: .dest)
            dest.params.destRate = .r1_8; dest.params.destSlices = [0, 1, 0, 0, 0, 0, 0, 0]   // col1 → B, else → A
            procs.append(dest)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 2 }.count   // cable 2 = wire B
        }
        XCTAssertEqual(cableBCount(clockRatio: nil), 1, "no clock: the note at m=0.5 lands on column 1 → routes to B once")
        let two = clockRatioLadder.firstIndex(of: 2)!
        XCTAssertEqual(cableBCount(clockRatio: two), 0, "×2 clock: none of the 4 transformed notes ever land on column 1 → B never fires")
    }
    // [ARP→CLOCK ×2→VELOCITY]: VELOCITY's lane has ONE loud step (100) at column 1 (the m=0.5 note, no clock); every
    // other step is 40. A ×2 clock moves every one of the 4 notes off column 1 → every note plays at 40.
    func testClockTransformsVelocitysOwnLaneClock() {
        func loudCount(clockRatio: Int?) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var procs = [arp]
            if let ratio = clockRatio { procs.append(drawnClock(ratioIndex: ratio)) }
            var vel = ProcessorSlot(type: .velocity)
            vel.params.velRate = .r1_8; vel.params.velSteps = 8
            vel.params.velLane = [40, 100, 40, 40, 40, 40, 40, 40]   // column 1 loud, everything else quiet
            procs.append(vel)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 && $0.vel == 100 }.count   // cable 1 only — every note ALSO doubles onto the shared ALL cable (§7b)
        }
        XCTAssertEqual(loudCount(clockRatio: nil), 1, "no clock: the note at m=0.5 lands on the loud step")
        let two = clockRatioLadder.firstIndex(of: 2)!
        XCTAssertEqual(loudCount(clockRatio: two), 0, "×2 clock: none of the 4 transformed notes land on the loud step")
    }
    // [ARP→CLOCK ×2→TUTTI(PATTERN)]: TUTTI's slice at column 1 is REST (drops the single driven note through); every
    // other slice is ALL (keeps it). A ×2 clock moves every note off column 1 → nothing gets dropped.
    func testClockTransformsTuttisOwnSliceClock() {
        func passCount(clockRatio: Int?) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var procs = [arp]
            if let ratio = clockRatio { procs.append(drawnClock(ratioIndex: ratio)) }
            var tutti = ProcessorSlot(type: .tutti); tutti.params.tuttiMode = .pattern
            tutti.params.tuttiRate = .r1_8
            tutti.params.tuttiSlices = [.all, .rest, .all, .all, .all, .all, .all, .all]   // column 1 rests, else passes
            procs.append(tutti)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count   // cable 1 only — every note ALSO doubles onto the shared ALL cable (§7b)
        }
        XCTAssertEqual(passCount(clockRatio: nil), 3, "no clock: the note at m=0.5 lands on the REST column and is dropped — 3 of 4 pass")
        let two = clockRatioLadder.firstIndex(of: 2)!
        XCTAssertEqual(passCount(clockRatio: two), 4, "×2 clock: no note ever lands on the REST column — all 4 pass")
    }
    // [CLOCK ×2→MOD]: MOD has no driver at all — CLOCK reaches it from chain-start, not driver-relative. A RAMP-shape
    // MOD sampled across a window must emit a genuinely different CC value sequence when retimed (a ×1 clock stays
    // byte-identical to no clock at all — the standing no-op law every CLOCK mode obeys).
    func testClockTransformsModsOwnShapeClock() {
        let cs = arpMachines()   // MOD needs no driver — an arp-typed base is fine, the chain below is explicit
        func ccValues(clockRatio: Int?) -> [UInt8] {
            var procs: [ProcessorSlot] = []
            if let ratio = clockRatio { procs.append(drawnClock(ratioIndex: ratio)) }
            var mod = ProcessorSlot(type: .mod); mod.params.modShape = .ramp; mod.params.modCC = 20
            mod.params.modStepSpanN = 1   // PERIOD = one grid step (S), a short, easily-sampled cycle
            procs.append(mod)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            return e.events.filter { $0.status == 0xB0 && $0.cable == 1 && $0.note == 20 }.map { $0.vel }
        }
        let noClock = ccValues(clockRatio: nil)
        XCTAssertFalse(noClock.isEmpty, "sanity: the RAMP actually emits CC events over 2 beats")
        let one = clockRatioLadder.firstIndex(of: 1)!
        XCTAssertEqual(ccValues(clockRatio: one), noClock, "×1 CLOCK is a no-op — byte-identical to no CLOCK at all, matching every other mode")
        let two = clockRatioLadder.firstIndex(of: 2)!
        XCTAssertNotEqual(ccValues(clockRatio: two), noClock, "×2 CLOCK genuinely retimes the RAMP — a different value sequence over the same real window")
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
    func testClockDrawnRetimesArpsOwnGeneration() {
        func onCount(clockRatioIndex: Int?) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var procs: [ProcessorSlot] = []
            if let idx = clockRatioIndex { procs.append(drawnClock(ratioIndex: idx)) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            procs.append(arp)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertEqual(onCount(clockRatioIndex: nil), 4, "sanity: a bare arp fires 4 notes in its column's own window")
        let one = clockRatioLadder.firstIndex(of: 1)!, two = clockRatioLadder.firstIndex(of: 2)!
        XCTAssertEqual(onCount(clockRatioIndex: one), 4, "×1 DRAWN lane is a no-op — byte-identical to no CLOCK at all")
        XCTAssertEqual(onCount(clockRatioIndex: two), 8, "×2 DRAWN lane packs exactly double the local ticks into the same real window")
    }
    // The same shared `iterateTicks` change generalizes to RIFF and RATCHET's ALL mode (both route through it,
    // like ARP) — hand-verified: RIFF 3→6, RATCHET(ALL) 6→12, both exactly doubled by a ×2 DRAWN lane.
    func testClockDrawnRetimesRiffAndRatchetAllOwnGeneration() {
        func riffCount(clockRatioIndex: Int?) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var procs: [ProcessorSlot] = []
            if let idx = clockRatioIndex { procs.append(drawnClock(ratioIndex: idx)) }
            var riff = ProcessorSlot(type: .riff); riff.params.riffRate = .r1_8
            procs.append(riff)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        func ratchetAllCount(clockRatioIndex: Int?) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var procs: [ProcessorSlot] = []
            if let idx = clockRatioIndex { procs.append(drawnClock(ratioIndex: idx)) }
            var rat = ProcessorSlot(type: .ratchet); rat.params.rtcMode = .all; rat.params.count = 1
            procs.append(rat)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let two = clockRatioLadder.firstIndex(of: 2)!
        XCTAssertEqual(riffCount(clockRatioIndex: nil), 3); XCTAssertEqual(riffCount(clockRatioIndex: two), 6)
        XCTAssertEqual(ratchetAllCount(clockRatioIndex: nil), 6); XCTAssertEqual(ratchetAllCount(clockRatioIndex: two), 12)
    }
    // WIDENED (Paul 2026-09-26: "shouldn't all downstream processors read an upstream clock, defaulting to real
    // time if none is present?" — yes; confirmed via a real repro — "put a 1-step grid on speed, change it, put a
    // euclid or ratchet pattern after it" — and neither was retimed). EUCLID already shared `iterateTicks` with
    // ARP/RIFF/RATCHET-ALL — it just wasn't wired to the clock-aware parameters at its own call site. SUPERSEDES
    // `testClockDrawnDoesNotReachEuclid`, which asserted the OLD (now-fixed) gap. ×1 stays the standing no-op law;
    // ×3 must pack meaningfully more pulses into the same real window (mirroring ARP's 4→8 under ×2) — asserted as
    // an inequality, not a hand-derived count, since the exact number depends on tick-search quantization that
    // isn't the property under test.
    func testClockDrawnRetimesEuclidToo() {
        func euclidCount(clockRatioIndex: Int?) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var procs: [ProcessorSlot] = []
            if let idx = clockRatioIndex { procs.append(drawnClock(ratioIndex: idx)) }
            var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = 3; eu.params.euclidSteps = 8
            procs.append(eu)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let noClock = euclidCount(clockRatioIndex: nil)
        let one = clockRatioLadder.firstIndex(of: 1)!, three = clockRatioLadder.firstIndex(of: 3)!
        XCTAssertEqual(euclidCount(clockRatioIndex: one), noClock, "×1 CLOCK is a no-op for EUCLID too")
        XCTAssertGreaterThan(euclidCount(clockRatioIndex: three), noClock, "×3 CLOCK packs meaningfully more EUCLID pulses into the same real window")
    }
    // CLOCK DRAWN's GLIDE row (Paul 2026-09-26, final spec — "another row on the same grid for glide"): a column
    // marked GLIDE ramps its rate in from the previous column's landed ratio instead of snapping at column entry.
    // rateBeats is now always S (RATE was removed the same day), so a 2-step lane's column boundary sits at real
    // beat 2×S; the ARP's first post-boundary tick lands LATER under GLIDE than under SET (the ramp is still close
    // to ×1 just after the boundary) — verified empirically (not asserted against hand-derived beats/samples
    // directly, since the exact position also depends on tick-search quantization at the discontinuity, which
    // isn't the property under test).
    func testClockDrawnGlideRowSoftensTheColumnTransition() {
        func firstTickAfterBoundary(glideOn: Bool) -> Int64? {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var ck = ProcessorSlot(type: .clock)
            ck.params.clockDrawnSteps = 2
            ck.params.clockDrawnRatios = [clockRatioLadder.firstIndex(of: 1)!, clockRatioLadder.firstIndex(of: 4)!]
            ck.params.clockDrawnGlide = [false, glideOn]
            ck.params.clockSpanN = 0
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ck, arp]; return c }() }
            // forceColumn: 0 (PLAY: THIS CELL) bypasses the column-lap gate entirely — otherwise the cell would
            // only ever tick during the underlying grid's OWN column-0 real-time window ([0, S)), and since RATE
            // was removed (a clock column is now S-wide too), a 2-step CLOCK lane needs 2×S of real time to show
            // its second column at all — beyond the plain grid's single column-0 span. Bypassing the gate lets
            // real time (and therefore CLOCK's own local phase) keep advancing so the col0→col1 transition
            // is observable in a bare single-cell test.
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            let samples = e.ons.filter { $0.cable == 1 }.map { $0.sample }.sorted()
            let boundarySample: Int64 = 48_000   // real beat 2.0 at 120bpm/48kHz (24000 samples/beat) — the col0/col1 boundary at S=2, rateBeats=S
            return samples.first(where: { $0 > boundarySample })
        }
        guard let setTick = firstTickAfterBoundary(glideOn: false), let glideTick = firstTickAfterBoundary(glideOn: true) else {
            return XCTFail("expected a post-boundary tick in both cases")
        }
        XCTAssertGreaterThan(glideTick, setTick, "GLIDE's first tick after the column boundary lands later than SET's — the transition is softened, not instant")
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
    // [ARP→KILLSTEP(evens only)→DEST]: DEST routes column 1 (the only note at m=0.5, with no KILL STEP) to emitter
    // B, else to A. KILL STEP keeps only the even indices {0,2,4,6} of 8 — the 4 arp notes (real columns 0…3) remap
    // onto columns 0,2,4,6, so column 1 is never landed on.
    func testKillStepTransformsDestsOwnRoutingClock() {
        func cableBCount(killStep: Bool) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var procs = [arp]
            if killStep { procs.append(killStepStage(steps: 8, enabled: [true, false, true, false, true, false, true, false])) }
            var dest = ProcessorSlot(type: .dest)
            dest.params.destRate = .r1_8; dest.params.destSlices = [0, 1, 0, 0, 0, 0, 0, 0]   // col1 → B, else → A
            procs.append(dest)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 2 }.count   // cable 2 = wire B
        }
        XCTAssertEqual(cableBCount(killStep: false), 1, "no KILL STEP: the note at m=0.5 lands on column 1 → routes to B once")
        XCTAssertEqual(cableBCount(killStep: true), 0, "KILL STEP keeps only the even columns: none of the 4 arp notes ever remap onto column 1 → B never fires")
    }
    // The user's own worked example: "if only steps 1–4 [of 8] are enabled, the second half of the pass will not be
    // played, and instead the first half will be played twice." DEST's slices 0–3 name A·B·C·D; 4–7 are NONE (never
    // reached). Over 8 real columns (two laps of the 4 enabled steps), each of A·B·C·D should land exactly twice.
    func testKillStepPlaysTheFirstHalfTwiceOverOnePass() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
        let ks = killStepStage(steps: 8, enabled: [true, true, true, true, false, false, false, false])
        var dest = ProcessorSlot(type: .dest)
        dest.params.destRate = .r1_8; dest.params.destSlices = [0, 1, 2, 3, -1, -1, -1, -1]
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); c.processors = [arp, ks, dest]; return c }() }
        // forceColumn: 0 (PLAY: THIS CELL), like the CLOCK GLIDE test above — a bare cell only ticks during its own
        // grid column's real-time window otherwise, which isn't wide enough to show 8 real columns' worth of ticks.
        // beats: 3.9, not 4 — a window landing EXACTLY on a 1/8-rate boundary picks up one extra boundary tick
        // (hand-verified via a failing first draft: 4.0 gave 9 ticks, not 8 — `firstTick...lastT` is INCLUSIVE of a
        // tick that falls precisely at the window's end); 3.9 stops strictly between ticks 7 and 8, giving exactly
        // the 8 real columns (n=0…7) this test means to exercise.
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 3.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 2, "A — the enabled run's first step, twice (real columns 0 and 4)")
        XCTAssertEqual(e.ons.filter { $0.cable == 2 }.count, 2, "B — real columns 1 and 5")
        XCTAssertEqual(e.ons.filter { $0.cable == 3 }.count, 2, "C — real columns 2 and 6")
        XCTAssertEqual(e.ons.filter { $0.cable == 4 }.count, 2, "D — real columns 3 and 7 — none of DEST's NONE-routed slices 4–7 were ever reached")
    }
    // The user's second example: enabling only 3 of 8 steps rotates a 3-cycle that "overrides the clock" — 8 isn't a
    // multiple of 3, so the rotation drifts against the bar instead of landing evenly.
    func testKillStepUnevenCountRotatesAgainstTheBar() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
        let ks = killStepStage(steps: 8, enabled: [true, true, true, false, false, false, false, false])
        var dest = ProcessorSlot(type: .dest)
        dest.params.destRate = .r1_8; dest.params.destSlices = [0, 1, 2, -1, -1, -1, -1, -1]
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); c.processors = [arp, ks, dest]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 3.9, into: e, forceColumn: 0)   // see the sibling test's comment: 3.9, not 4, avoids the boundary tick
        assertNothingLeftSounding(e)
        // A,B,C,A,B,C,A,B across 8 real columns — A and B land one extra time, C one fewer.
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 3, "A — real columns 0, 3, 6")
        XCTAssertEqual(e.ons.filter { $0.cable == 2 }.count, 3, "B — real columns 1, 4, 7")
        XCTAssertEqual(e.ons.filter { $0.cable == 3 }.count, 2, "C — real columns 2, 5")
    }
    // KILL STEP MUTE (Paul 2026-09-27): unlike DROP, MUTE only has an effect when KILL STEP precedes the driver it
    // retimes ([KILL STEP→ARP] — its OWN generation); downstream of a driver ([ARP→KILL STEP→DEST]) KILL STEP only
    // retimes DEST's own clock, and there's no note-generation event left at its own position to suppress, so MUTE
    // is a no-op there (DROP/PAUSE still work in both positions since they're pure time-transforms — flagged, not a
    // bug). Here: ONE muted step removes exactly that step's note-on; every OTHER onset keeps its exact real timing
    // (unlike DROP, nothing compacts/repeats to fill the gap).
    func testKillStepMuteKeepsTimingButSilencesTheStep() {
        func onsets(_ modes: [KillStepMode]) -> [Int64] {
            var ks = ProcessorSlot(type: .killStep); ks.params.killStepCount = 8; ks.params.killStepMode = modes; ks.params.killStepRate = .r1_8; ks.params.killStepSpanN = 0
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ks, arp]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 3.9, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { $0.sample }.sorted()
        }
        let allOn = onsets(Array(repeating: .on, count: 8))
        var oneMuted = Array(repeating: KillStepMode.on, count: 8); oneMuted[3] = .mute
        let muted = onsets(oneMuted)
        XCTAssertEqual(muted.count, allOn.count - 1, "MUTE removes exactly one note-on — the muted step's — nothing else")
        XCTAssertEqual(Set(allOn).subtracting(muted).count, 1, "the timing of every OTHER onset is byte-identical (unlike DROP, nothing compacts to fill the hole)")
    }
    // KILL STEP PAUSE (Paul 2026-09-27): freezes the downstream clock at its current value for PAUSE LEN extra real
    // columns, then resumes — a hold, not a retrigger. [ARP→KILL STEP→DEST] makes DEST's own routing the external
    // witness (mirrors `testKillStepTransformsDestsOwnRoutingClock`'s technique): a step immediately before a PAUSE
    // step should see SEVERAL consecutive real arp ticks land on the SAME emitter while the pause holds, instead of
    // advancing one-per-tick like every other step.
    func testKillStepPauseFreezesDownstreamTicks() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
        var ks = ProcessorSlot(type: .killStep)
        ks.params.killStepCount = 8; ks.params.killStepRate = .r1_8; ks.params.killStepSpanN = 0
        ks.params.killStepMode = [.on, .on, .pause, .on, .on, .on, .on, .on]   // step 2 pauses
        ks.params.killStepPauseLen = 2                                         // holds for 3 real columns total (1 + 2)
        var dest = ProcessorSlot(type: .dest)
        dest.params.destRate = .r1_8; dest.params.destSlices = [0, 1, 2, 3, -1, -1, -1, -1]   // slice 2 → C; the paused step's slot
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); c.processors = [arp, ks, dest]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 1, "A — real column 0, unaffected by a pause two steps later")
        XCTAssertEqual(e.ons.filter { $0.cable == 2 }.count, 1, "B — real column 1")
        XCTAssertEqual(e.ons.filter { $0.cable == 3 }.count, 3, "C — real columns 2,3,4 ALL read the frozen value during the hold, unlike every other step's one-per-tick advance")
        XCTAssertEqual(e.ons.filter { $0.cable == 4 }.count, 1, "D — real column 5, resumes normally once the hold ends")
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
    // STANDALONE RATCHET PATTERN = a PASS-THROUGH PROCESSOR, not a generator (Paul 2026-09-08). A lone (single-slot)
    // ratchet-pattern cell RECEIVES the input and passes it through; its own clock only decides per-column treatment
    // (1 = pass/sustain · 2…8 = ratchet · 0 = OFF/mute). It must NOT manufacture a note per step — the fix for "a short
    // stab plays for each step". Definitive check: the PASS-THROUGH count is INDEPENDENT of the ratchet RATE (a generator
    // would scale with it). Also: ratchet columns add strikes, OFF mutes, no input → silence. All via emitColumnRatchetPattern.
    func testStandaloneRatchetPatternPassesThroughAndMutes() {
        func standalone(_ slices: [Int], rate: ArpRate, chordNotes: [UInt8]) -> Int {
            let cs = machineIDs.map { c -> Machine in var col = Machine(machineID: c, type: .ratchet)
                col.paramsA.rtcMode = .pattern; col.paramsA.rtcRate = rate; col.paramsA.rtcSteps = slices.count; col.paramsA.rtcSlices = slices; col.paramsA.ramp = 0; return col }
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chordNotes.isEmpty ? NotePool() : chord(chordNotes), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let passFast = standalone(Array(repeating: 1, count: 8), rate: .r1_16, chordNotes: [60, 64, 67])
        let passSlow = standalone(Array(repeating: 1, count: 8), rate: .r1_8,  chordNotes: [60, 64, 67])
        let ratFast  = standalone(Array(repeating: 3, count: 8), rate: .r1_16, chordNotes: [60, 64, 67])
        let allOff   = standalone(Array(repeating: 0, count: 8), rate: .r1_16, chordNotes: [60, 64, 67])
        let noInput  = standalone(Array(repeating: 1, count: 8), rate: .r1_16, chordNotes: [])
        XCTAssertGreaterThan(passFast, 0, "pass-through sounds the held chord")
        XCTAssertEqual(passFast, passSlow, "PASS-THROUGH count is INDEPENDENT of the ratchet RATE — it passes the input, never generates per step (the bug fix)")
        XCTAssertGreaterThan(ratFast, passFast, "ratchet columns (×3) re-strike → more strikes than pass-through")
        XCTAssertEqual(allOff, 0, "all-OFF mutes every column → silence (unselect-to-mute)")
        XCTAssertEqual(noInput, 0, "no input → the pass-through generates nothing")
    }
    // RATCHET PATTERN — the NOTE clock (Paul 2026-09-07): instead of the ratchet's own RATE, the playhead advances one MATRIX
    // column PER NOTE passing through. So the Nth arp note reads column N: an all-1 matrix == the bare arp; a matrix with a
    // ratchet count on every other column re-fires those notes → more strikes than passthrough. Chain-only; replay-safe.
    func testRatchetPatternNoteClockAdvancesPerNote() {
        func cellCount(_ slices: [Int]?) -> Int {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var procs = [arp]
            if let slices = slices {   // nil ⇒ the bare arp (baseline); else [ARP → RATCHET PATTERN] in NOTE clock
                var rat = ProcessorSlot(type: .ratchet)
                rat.params.rtcMode = .pattern; rat.params.rtcClock = .note; rat.params.rtcSteps = slices.count
                rat.params.rtcSlices = slices; rat.params.ramp = 0
                procs.append(rat)
            }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let arpOnly = cellCount(nil)
        let allPass = cellCount(Array(repeating: 1, count: 8))
        let alt     = cellCount([1, 4, 1, 4, 1, 4, 1, 4])   // every 2nd note (ordinal 1,3,5,…) ratchets ×4
        XCTAssertEqual(allPass, arpOnly, "NOTE clock, all-passthrough = the arp untouched (one column advanced per note)")
        XCTAssertGreaterThan(alt, allPass, "NOTE clock ratchets every 2nd note → more strikes than passthrough")
        XCTAssertEqual(alt, cellCount([1, 4, 1, 4, 1, 4, 1, 4]), "replay-safe")
    }
    // MUTE composes ON TOP of DEST (Paul 2026-08-25 §5): DEST routes each slice to one emitter, MUTE then removes muted
    // emitters. [ARP→DEST(alt A/B)→MUTE(A)] → the A-routed slices go silent, the B-routed ones still play; none stuck.
    func testMuteMatrixComposesOverDest() {
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var dest = ProcessorSlot(type: .dest); dest.params.destSlices = [0, 1, 0, 1, 0, 1, 0, 1]      // alternate A, B
        var mute = ProcessorSlot(type: .muteMatrix); mute.params.muteSlices = Array(repeating: 0b0001, count: 8)  // A muted every step
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) {
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); c.processors = [arp, dest, mute]; return c }()
        }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        assertNothingLeftSounding(e)
        XCTAssertFalse(e.ons.contains { $0.cable == 1 }, "the A-routed slices are muted → nothing on emitter A")
        XCTAssertTrue(e.ons.contains { $0.cable == 2 }, "the B-routed slices still play on emitter B")
    }
    // MUTE MATRIX indexes by the GRID COLUMN (Paul 2026-08-25 — the "does nothing" fix): a MUTE machine across a ROW mutes
    // the drawn columns. Muting emitter A on columns 0–3 only → A still plays (from columns 4–7); muting it everywhere → none.
    func testMuteMatrixMutesByColumnAcrossARow() {
        func aCount(_ mask: [Int]) -> Int {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mute = ProcessorSlot(type: .muteMatrix); mute.params.muteSlices = mask
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) {
                for col in 0..<8 { $0.cells[col][0] = { var c = Cell(machineID: "gold", buses: [.a, .b]); c.processors = [arp, mute]; return c }() }
            }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count   // emitter A
        }
        let none = aCount(Array(repeating: 0, count: 8))                 // nothing muted
        let half = aCount([1, 1, 1, 1, 0, 0, 0, 0])                      // A muted on columns 0–3 only
        let all  = aCount(Array(repeating: 1, count: 8))                 // A muted everywhere
        XCTAssertEqual(all, 0, "A muted on every column → no A at all")
        XCTAssertGreaterThan(half, 0, "A still plays on the unmuted columns 4–7 (per-column, not sub-slice)")
        XCTAssertLessThan(half, none, "muting columns 0–3 drops A there")
    }
    // TIMING LANE (Paul 2026-08-22 §5): NUDGE's LANE mode — the cell's COLUMN picks a per-step time offset (the pocket).
    func testTimingLaneNudgesTheOnsetByColumn() {
        func firstOn(lane: [Int]?) -> Int64 {
            var c = Machine(machineID: "gold", type: .nudge)
            if let l = lane { c.paramsA.utilNudgeMode = .lane; c.paramsA.utilNudgeLane = l }
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // a NUDGE cell in column 0
            let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.first?.sample ?? -1
        }
        let baseline = firstOn(lane: nil)                        // FIXED, nudge 0
        let laneZero = firstOn(lane: [0, 0, 0, 0, 0, 0, 0, 0])
        let laneShift = firstOn(lane: [4, 0, 0, 0, 0, 0, 0, 0])  // column 0 = +4/16 beat later
        XCTAssertGreaterThan(baseline, -1, "the NUDGE cell holds + sounds the chord")
        XCTAssertEqual(laneZero, baseline, "LANE all-zero == FIXED-zero (byte-identical)")
        XCTAssertGreaterThan(laneShift, baseline, "column 0's +4/16 lane offset delays the onset")
    }
    // CHANCE PATTERN (Paul 2026-08-22 §5): per-step odds — 0% drops every note in that step, 100% passes; deterministic.
    func testChancePatternGatesByStepOdds() {
        func ons(_ slices: [Int]) -> Int {
            var c = Machine(machineID: "gold", type: .chance)
            c.paramsA.chanceMode = .pattern; c.paramsA.chanceSlices = slices
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let allPass = ons([100, 100, 100, 100, 100, 100, 100, 100])
        let allDrop = ons([0, 0, 0, 0, 0, 0, 0, 0])
        let alt = ons([100, 0, 100, 0, 100, 0, 100, 0])
        XCTAssertGreaterThan(allPass, 0, "100% odds passes")
        XCTAssertEqual(allDrop, 0, "0% odds drops every note in every step")
        XCTAssertGreaterThan(alt, 0, "alternating passes the 100% steps")
        XCTAssertLessThan(alt, allPass, "alternating passes fewer than all-100 (the odd steps drop)")
        XCTAssertEqual(alt, ons([100, 0, 100, 0, 100, 0, 100, 0]), "replay-safe (deterministic)")
    }
    // SPAN LADDER stage 2 — TUTTI PATTERN (Paul 2026-08-22, RATE×ladder): RATE = slice width, SPAN N = the loop period
    // in columns (re-anchor every N). Different periods produce different (polymeter) patterns; the run is replay-safe.
    func testTuttiSpanLadderReAnchorsThePatternByPeriod() {
        func notes(spanN: Int?) -> [Int] {
            var c = Machine(machineID: "gold", type: .tutti)
            c.paramsA.tuttiMode = .pattern
            c.paramsA.tuttiSlices = [.all, .rest, .low, .rest, .high, .rest, .bot2, .rest]
            c.paramsA.tuttiSpanN = spanN
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)   // one 8-column bar
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        }
        let n3 = notes(spanN: 3), n8 = notes(spanN: 8)
        XCTAssertFalse(n3.isEmpty, "the RATE×ladder path sounds")
        XCTAssertNotEqual(n3, n8, "period 3 (polymeter) differs from period 8 (bar-locked)")
        XCTAssertEqual(n3, notes(spanN: 3), "the ladder is replay-safe (deterministic)")
    }
    // SPAN FREE (Paul 2026-08-27): FREE (spanN==0, the legacy CELL free-run) walks the slice figure ACROSS columns;
    // SPAN=1 re-anchors it every column. At a sub-column RATE (0.5 beat = 4 slices per 2-beat column here), FREE
    // reaches slices 4–7 (the .high half) while SPAN=1 never leaves slices 0–3 (the .low half) — so they diverge.
    func testTuttiFreeSpanFreeRunsDistinctFromSpanOne() {
        func notes(spanN: Int) -> [Int] {
            var c = Machine(machineID: "gold", type: .tutti)
            c.paramsA.tuttiMode = .pattern
            c.paramsA.tuttiRate = .r1_8                // 0.5 beat → 4 slices per 2-beat column
            c.paramsA.tuttiSlices = [.low, .low, .low, .low, .high, .high, .high, .high]
            c.paramsA.tuttiSpanN = spanN
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        }
        let free = notes(spanN: 0), span1 = notes(spanN: 1)
        XCTAssertFalse(free.isEmpty, "FREE sounds")
        XCTAssertNotEqual(free, span1, "FREE free-runs the figure across columns; SPAN=1 re-anchors every column")
        XCTAssertEqual(free, notes(spanN: 0), "FREE is replay-safe")
    }
    // STRIKE PER SPAN (Paul 2026-08-27, the span ladder's other half): a DRONE with strikePerSpan re-articulates its pad
    // at each SPAN origin and HOLDS (adopts) through the columns between; off (default) it strikes ONCE and holds the whole
    // run (today's continuous drone). Off the same span ladder: SPAN=1 → every column, SPAN=4 → cols 0 and 4. No stuck notes.
    func testDroneStrikePerSpanReArticulatesAtSpanOrigins() {
        func onCount(sps: Bool, spanN: Int) -> Int {
            var c = Machine(machineID: "gold", type: .drone)
            c.paramsA.strikePerSpan = sps
            c.paramsA.strikeSpanN = spanN
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 15.9, into: e)   // columns 0…7 of one bar (S=2), no col-8 wrap
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 && $0.note == 60 }.count
        }
        XCTAssertEqual(onCount(sps: false, spanN: 8), 1, "a plain drone strikes once and holds the whole run (today's pad)")
        XCTAssertEqual(onCount(sps: true, spanN: 1), 8, "PER SPAN=1 re-articulates every column")
        XCTAssertEqual(onCount(sps: true, spanN: 4), 2, "PER SPAN=4 re-articulates at the span origins (cols 0, 4)")
        XCTAssertEqual(onCount(sps: true, spanN: 4), 2, "replay-safe (deterministic)")
    }
    // RATCHET PATTERN SPAN (Paul 2026-09-07): SPAN N re-anchors the ratchet's playhead every N MATRIX columns (N × RATE);
    // FREE (0) = free-run over all STEPS. So with STEPS = 8: FREE == span 8 (a full-loop re-anchor is the same as no
    // re-anchor), and a SHORT span (2) confines the playhead to columns 0..1 → a different note count. This is the
    // "SPAN doesn't reset / stuck in FREE" fix: it used to measure the period in GRID columns, which on a common setup
    // landed at ≥ STEPS and was indistinguishable from FREE.
    func testRatchetSpanReAnchorsByMatrixColumns() {
        func onCount(spanN: Int?) -> Int {
            var c = Machine(machineID: "gold", type: .ratchet)
            c.paramsA.rtcMode = .pattern
            c.paramsA.rtcSteps = 8
            c.paramsA.rtcSlices = [3, 1, 2, 1, 4, 1, 2, 1]   // no rest (v6): every column sounds ≥ 1
            c.paramsA.rtcSpanN = spanN
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let free = onCount(spanN: 0), c8 = onCount(spanN: 8), c2 = onCount(spanN: 2), c3 = onCount(spanN: 3)
        XCTAssertGreaterThan(free, 0, "the ratchet sounds")
        XCTAssertEqual(free, c8, "FREE == span 8 when STEPS = 8 (a full-loop re-anchor is a no-op)")
        XCTAssertNotEqual(c2, free, "a short span (2 columns) confines the playhead → differs from FREE")
        XCTAssertNotEqual(c3, free, "span 3 (polymeter against the 8-step pattern) differs from FREE")
        XCTAssertEqual(c2, onCount(spanN: 2), "replay-safe")
    }
    // SPAN LADDER stage 2b — CASCADE (RATE×ladder): RATE = reveal spacing, SPAN N = the reveal window in columns.
    func testCascadeSpanLadderChangesTheRevealWindow() {
        func seq(spanN: Int?) -> [Int] {
            var c = Machine(machineID: "gold", type: .cascade)
            c.paramsA.cascadeSpanN = spanN
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 16, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        }
        let s2 = seq(spanN: 2), s8 = seq(spanN: 8)
        XCTAssertFalse(s2.isEmpty, "the RATE×ladder cascade reveals notes")
        XCTAssertNotEqual(s2, s8, "a shorter reveal window re-anchors more often")
        XCTAssertEqual(s2, seq(spanN: 2), "replay-safe")
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
    // PER-PART CLOCK (Paul 2026-08-19): two rows on DIFFERENT step rates play at different tempos in ONE grid — the
    // multi-clock render path. Both rows are filled with a per-COLUMN striker (CHANCE prob 1 re-speaks the chord at each
    // column boundary), so its onset density scales with the ROW's step rate; row 0 runs SLOW (2/1) on bus A, row 1 runs
    // FAST (1/8) on bus B → the fast row strikes far more. (Euclid used to demo this, but its grain is now ABSOLUTE — the
    // 2026-08-27 RATE×ladder — so it no longer speeds up on a faster row; the per-part clock shapes the column sweep +
    // SPAN re-anchor, not the grain. A per-column striker is the honest demo of a per-row tempo.)
    func testPerRowStepRatePlaysDifferentTemposInOneGrid() {
        let cs = machineIDs.map { var c = Machine(machineID: $0, type: .chance)
            c.paramsA.probability = 1; return c }
        let b = box(machines: cs) { s in
            for col in 0..<8 {                                    // fully populate both rows so a column is always sounding
                s.cells[col][0] = Cell(machineID: "gold", buses: [.a])
                s.cells[col][1] = Cell(machineID: "orange", buses: [.b])
            }
            s.rowStepRate = [.r2_1, .r1_8, nil, nil, nil, nil, nil, nil]   // row 0 slow · row 1 fast · rest = scene default
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        let slow = e.ons.filter { $0.cable == 1 }.count           // bus A (row 0)
        let fast = e.ons.filter { $0.cable == 2 }.count           // bus B (row 1)
        XCTAssertGreaterThan(slow, 0, "the slow row still sounds")
        XCTAssertGreaterThan(fast, slow * 3, "the fast row (16× the step rate) strikes far more often than the slow row")
        assertNothingLeftSounding(e)                              // and no stuck notes across the mixed-tempo edges
    }
    // PLAY-FERRY LAUNCH (Paul 2026-09-09): a per-row launch ANCHOR arms the row silent until its launch beat, then phases it
    // from column 0. Row 0 is SYNC (anchor 0 ⇒ transport-locked, sounds from the start); row 1 is anchored at beat 4 ⇒ ARMED
    // (silent) until beat 4, then plays. Proves the anchor forces the multi-clock path + the arm-guard + eventual play.
    func testFerryLaunchAnchorArmsRowUntilItsStartBeat() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { s in
            for col in 0..<8 {
                s.cells[col][0] = Cell(machineID: "gold", buses: [.a])     // SYNC row (anchor 0) — sounds from beat 0
                s.cells[col][1] = Cell(machineID: "orange", buses: [.b])   // anchored row — armed until beat 4
            }
            var anchor = [Double](repeating: 0, count: Snap.rows); anchor[1] = 4.0
            s.rowLaunchAnchor = anchor
        }
        let before = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 3, into: before)               // beats 0…3 — before the anchored row's launch
        XCTAssertGreaterThan(before.ons.filter { $0.cable == 1 }.count, 0, "the SYNC row sounds from the start")
        XCTAssertEqual(before.ons.filter { $0.cable == 2 }.count, 0, "the anchored row is ARMED (silent) until its launch beat")
        assertNothingLeftSounding(before)
        let after = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 8, into: after)                // beats 0…8 — crosses beat 4
        XCTAssertGreaterThan(after.ons.filter { $0.cable == 2 }.count, 0, "past its launch beat, the anchored row plays")
        assertNothingLeftSounding(after)
    }
    // PER-ROW LAP (Paul 2026-08-19): each grid ROW loops its OWN columns (the BUILD staging + perform grids loop
    // independently). Row 0's only cell lives in column 0 and laps column 0; row 1's only cell lives in column 4 and
    // laps column 4. With ONE global lap only a single column could loop, silencing one cell — the per-row lap lets
    // BOTH play continuously on their own column. Proves looping one grid doesn't loop the other.
    func testPerRowLapLoopsEachRowsOwnColumns() {
        // NB (Paul 2026-09-01): SnapshotBuilder forwards `rowLane` ONLY when its count == Snap.rows (16). The old version of
        // this test passed an 8-entry array → the builder DISCARDED it → perRowLap was FALSE → the whole thing ran on the
        // UNIFORM fast path and never actually lapped (a false positive). Use a full 16-entry lane, and assert a cell OFF the
        // lapped column stays SILENT — which the uniform sweep would have SOUNDED, so the test now genuinely exercises the lap.
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }   // arp → a VISITED column keeps sounding
        var lane = [UInt16](repeating: 0, count: Snap.rows)
        lane[0] = 0b1        // row 0 laps COLUMN 0 only
        lane[1] = 0b1_0000   // row 1 laps COLUMN 4 only (independently)
        let b = box(machines: cs) { s in
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])        // row 0 · col 0 (cable 1) — ON row 0's lap
            s.cells[3][0] = Cell(machineID: "vermilion", buses: [.c])   // row 0 · col 3 (cable 3) — a col-0 lap NEVER visits it
            s.cells[4][1] = Cell(machineID: "azure", buses: [.b])       // row 1 · col 4 (cable 2) — ON row 1's lap
            s.rowLane = lane
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "row 0 laps its own column 0 → bus A sounds")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "row 1 laps its own column 4 → bus B sounds, independent of row 0")
        XCTAssertEqual(e.ons.filter { $0.cable == 3 }.count, 0, "row 0's COL-0 lap NEVER visits col 3 → bus C is silent (the uniform sweep would have sounded it — the discriminating check)")
        assertNothingLeftSounding(e)
    }
    // REGRESSION (Paul 2026-08-19): a length-4 arp played PASS 1 then went silent — iterateTicks wrapped the tick's
    // column at Snap.cols (8), not the row's Lr, so after the first pass the tick column (mod 8) never matched the row's
    // effective column (mod 4) again. A short loop must keep firing on every pass.
    func testPerRowLengthKeepsFiringOnLaterPasses() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { s in
            for c in 0..<4 { s.cells[c][0] = Cell(machineID: "gold", buses: [.a]) }   // arp across the 4-column loop
            s.rowStepRate = [.r1_4, nil, nil, nil, nil, nil, nil, nil]               // 1 beat/step → cycR = 4 beats
            s.rowLen = [4, nil, nil, nil, nil, nil, nil, nil]                        // loop over 4 columns
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)                             // ~4 passes of the 4-beat loop
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertGreaterThan(ons.count, 0, "the arp sounds")
        // beat b ≈ sample b·24000 (tempo 120 · sr 48000). Pass 1 ends ~sample 96000; firing past ~150000 proves the
        // loop re-fires on later passes (was silent after pass 1 with the mod-8 bug).
        XCTAssertGreaterThan(ons.map { $0.sample }.max() ?? 0, Int64(150_000), "the short loop keeps firing past the first pass")
        assertNothingLeftSounding(e)
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
    // REEL MACHINE TAG (Paul 2026-08-19): the export-page piano roll paints each note the MACHINE of the cell that played
    // it. The render tags every note-ON with its machine's DISPLAY hue (baked into SnapMachine, threaded via markHue
    // to the ReelTap), so the recorded pass carries it. Here: an arp on a gold cell whose hue is 0xFF8800 → every note
    // in the recorded roll is tagged 0xFF8800.
    func testReelRollTagsNotesWithTheCellMachine() {
        var s = SceneState.empty(); s.cells[0][0] = Cell(machineID: "gold")
        let st = PluginState(machines: machineIDs.map { Machine(machineID: $0, type: .arp) }, scenes: [s])
        let hue: UInt32 = 0xFF8800
        let box = SnapshotBuilder.build(from: st, hues: ["gold": hue])
        let router = Router(); var diag = KernelDiag()
        let reel = ReelDeck(); let sink = RecordingEmitter()
        let tap = ReelTap(); tap.out = sink; tap.deck = reel; tap.recording = true
        let sr = 48_000.0, tempo = 120.0; let frames: UInt32 = 2048
        let bps = tempo / 60.0 / sr
        let cyc = Double(Snap.cols) * box.stepBeats
        tap.beatsPerSample = bps; tap.cycleBeats = cyc
        reel.startPass()
        let pool = chord([60, 64, 67])
        var beat = 0.0, ts = 0.0
        while beat < cyc {
            tap.base = beat; tap.windowStart = Int64(ts)
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: tap, diag: &diag)
            beat += Double(frames) * bps; ts += Double(frames)
        }
        reel.cycleBeats = cyc; reel.promote()
        let roll = reel.selectedRoll()
        XCTAssertFalse(roll.isEmpty, "the pass recorded notes")
        XCTAssertTrue(roll.allSatisfy { $0.machine == hue }, "every recorded note is tagged its cell's machine hue")
    }
    // PER-ROW ECHO/MOD/GLIDE (Paul 2026-08-19): in the multi-clock path echo/mod/glide fire on each ROW's own clock,
    // not the scene default. Two echo cells in column 0: row 0 FAST (1/8), row 1 SLOW (2/1). The echo DRY strikes on
    // each entry to its column, so the fast row re-enters column 0 far more often → far more dry strikes on its bus.
    func testPerRowEchoFiresOnTheRowsOwnClock() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .echo) }
        let b = box(machines: cs) { s in
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])       // echo in column 0, row 0
            s.cells[0][1] = Cell(machineID: "orange", buses: [.b])     // echo in column 0, row 1
            s.rowStepRate = [.r1_8, .r2_1, nil, nil, nil, nil, nil, nil]   // row 0 FAST · row 1 SLOW
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        let fast = e.ons.filter { $0.cable == 1 }.count              // row 0 (bus A)
        let slow = e.ons.filter { $0.cable == 2 }.count              // row 1 (bus B)
        XCTAssertGreaterThan(fast, 0, "the fast row's echo dry fires")
        XCTAssertGreaterThan(fast, slow, "the fast row re-enters its column far more often → far more echo strikes (per-row clock)")
        assertNothingLeftSounding(e)
    }
    // CLOCK-MODE SWITCH stuck-note (Paul 2026-09-01 bug-hunt Finding 1): a LIVE uniform↔multi clock flip (a per-part-rate
    // edit / entering-leaving a lap) must not orphan an IMMORTAL glide anchor. Drive a single-slot [GLIDE] under a uniform
    // clock (the anchor sounds), switch the SAME router to a multi-clock box (a per-row rate) and back, then RELEASE the
    // chord while still PLAYING — with NO transport-stop flush. Without the switch-flush an anchor tracked on the now-
    // unscanned slot never phrase-ends → its last wire event stays a note-ON (stuck). The fix phrase-ends every glide
    // voice on the switch + re-anchors on the new clock, so the release closes it cleanly. (Also the first coverage of the
    // uniform↔multi switch — the fuzz never flips rowStepRate live.)
    func testClockModeSwitchDoesNotOrphanAGlideVoice() {
        func glideBox(multi: Bool) -> SnapshotBox {
            box(machines: machineIDs.map { Machine(machineID: $0, type: .glide) }) { s in
                for c in 0..<8 {                                             // glide across every column so the anchor is live whatever the effective column
                    s.cells[c][0] = { var x = Cell(machineID: "gold", buses: [.a])
                        var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glideRange = 12
                        g.params.glidePriority = .last; g.params.glideTime = 0.1; x.processors = [g]; return x }()
                }
                if multi { s.rowStepRate = [.r2_1, nil, nil, nil, nil, nil, nil, nil] }   // row 0 slow → NON-uniform → the multi-clock path
            }
        }
        let uni = glideBox(multi: false), multi = glideBox(multi: true)
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let held = chord([60, 64, 67]), empty = NotePool()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func step(_ b: SnapshotBox, _ pool: NotePool, _ n: Int) {
            for _ in 0..<n {
                router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
        }
        step(uni, held, 24)     // uniform: the glide anchor sounds + the column advances
        step(multi, held, 24)   // LIVE SWITCH → multi-clock (the fix phrase-ends + re-anchors here)
        step(uni, held, 24)     // and BACK → uniform (the other switch direction)
        step(uni, empty, 8)     // RELEASE the chord, still PLAYING, NO transport stop → the glide must phrase-end
        XCTAssertGreaterThan(e.ons.count, 0, "the glide anchor sounded")
        assertNothingLeftSounding(e)   // no stop-flush ran → an orphaned anchor would show as a stuck ON
    }
    // PLAY-LAYER ROWS (Paul 2026-09-01, addresses updated 2026-09-27 ferry-row-unification): each ferry occupies its own
    // dedicated row block (Snap.ferryRowBase(t)); the multi-clock loops iterate all Snap.rows rows and the tap/mute masks
    // exempt them — but no RouterTest had ever placed a cell there. A slow cell on ferry 1's row (bus A) + a fast cell
    // on ferry 0's row (bus B, its own fast rate) → the fast row fires far more, no A↔B cross-leak, nothing stuck
    // (guards any latent rows-0–3 `%8`/`<8` assumption in the 32-row loops).
    func testPlayLayerRowsRunOnTheirOwnClockWithoutLeak() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { s in
            while s.cells[0].count < Snap.rows { s.cells[0].append(nil) }           // extend the column so a play-layer row can hold a cell
            s.cells[0][Snap.ferryRowBase(1)] = Cell(machineID: "gold", buses: [.a])   // an unrelated occupied row — bus A (ferry 1's row is disjoint from ferry 0's)
            s.cells[0][Snap.ferryRowBase(0)] = Cell(machineID: "azure", buses: [.b]) // play-layer cell — ferry 0's row, bus B
            var rate = [StepRate?](repeating: nil, count: Snap.rows)
            rate[Snap.ferryRowBase(1)] = .r2_1                                       // the unrelated row SLOW
            rate[Snap.ferryRowBase(0)] = .r1_8                                       // ferry 0's row FAST — its OWN clock
            s.rowStepRate = rate
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        let a = e.ons.filter { $0.cable == 1 }.count, playRow = e.ons.filter { $0.cable == 2 }.count
        XCTAssertGreaterThan(a, 0, "the unrelated row sounds on bus A")
        XCTAssertGreaterThan(playRow, 0, "the play-layer row (ferry 0's row) RENDERS on its OWN bus B — a cell in the play-layer rows runs in the multi-clock loop (the gap: no RouterTest had ever placed a cell there)")
        assertNothingLeftSounding(e)
    }
    // onlyRow LEGATO reconcile vs a surviving DRONE (Paul 2026-09-01): the multi-clock path scopes the hold reconcile per row
    // (onlyRow). A legato drone on a SLOW row must be ADOPTED (struck once per note, not re-struck) as a DIFFERENT fast row
    // transitions — a regressed `% Snap.rows == onlyRow` guard would machine-gun the drone or strand it. Drone (row 0, bus A) +
    // a fast CHANCE cell (row 1, bus B) → each drone note strikes exactly ONCE across the held span; nothing stuck.
    func testOnlyRowLegatoDroneSurvivesAFastNeighbourRow() {
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!].type = .drone
        cs[machineIDs.firstIndex(of: "azure")!].type = .chance   // a re-speaking fast neighbour (never immortal)
        let b = box(machines: cs) { s in
            for c in 0..<8 { s.cells[c][0] = Cell(machineID: "gold", buses: [.a]) }   // legato drone across the whole row 0
            for c in 0..<8 { s.cells[c][1] = Cell(machineID: "azure", buses: [.b]) }  // fast CHANCE across row 1
            var rate = [StepRate?](repeating: nil, count: Snap.rows)
            rate[0] = .r2_1     // row 0 (drone) SLOW
            rate[1] = .r1_8     // row 1 (chance) FAST — transitions often, must NOT disturb row 0's drone
            s.rowStepRate = rate
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        let onCounts = Dictionary(grouping: e.ons.filter { $0.cable == 1 }, by: { $0.note }).mapValues { $0.count }
        XCTAssertEqual(Set(onCounts.keys), [60, 64, 67], "the drone sounds the held chord on bus A")
        for n: UInt8 in [60, 64, 67] { XCTAssertEqual(onCounts[n], 1, "drone note \(n) strikes ONCE — adopted across the whole span, never re-struck by row 1's fast transitions") }
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 3, "the fast CHANCE row fires repeatedly on bus B")
        assertNothingLeftSounding(e)
    }
    // CHORDS C2 — PATTERN mode (2026-09-01): a held note TRIGGERS the diatonic chord for the current degree, DERIVED from the
    // declared key (not the held pitch). Tested via [CHORDS → DRONE]: composeChainSet folds .chords upstream, DRONE holds the
    // derived chord. Proves the derivation + "plays in any key" + different degrees.
    func testChordsPatternDerivesTheDegreeInKey() {
        func emitted(root: Int, scale: ScaleType, degree: Int) -> Set<UInt8> {
            var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
            cs[ci].type = .chords
            let b = box(machines: cs) { s in
                s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                    var ch = ProcessorSlot(type: .chords)
                    ch.params.chordsMode = .pattern; ch.params.chordsRoot = root; ch.params.chordsScale = scale
                    ch.params.chordsDegrees = [Int](repeating: degree, count: 8)   // every column the same degree
                    let dr = ProcessorSlot(type: .drone)
                    x.processors = [ch, dr]; return x }()
            }
            let e = RecordingEmitter()
            run(b, chord([60]), beats: 4, into: e)   // a single held trigger note (60) — CHORDS ignores its PITCH
            assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        }
        // I in C major = C E G at the anchor octave (48), regardless of the held trigger (60).
        XCTAssertEqual(emitted(root: 0, scale: .major, degree: 0), [48, 52, 55], "I in C = C E G (derived from the key, NOT the held 60)")
        // The SAME degree in a different key transposes (plays in any key).
        XCTAssertEqual(emitted(root: 5, scale: .major, degree: 0), [53, 57, 60], "I in F = F A C")
        // A different degree — V in C = G B D (D wraps up an octave).
        XCTAssertEqual(emitted(root: 0, scale: .major, degree: 4), [55, 59, 62], "V in C = G B D")
    }
    func testChordsFollowNamesTheDegreeFromTheHeldNote() {   // CHORDS FOLLOW — the played note picks the degree
        func emitted(root: Int, heldNote: UInt8) -> Set<UInt8> {
            var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
            cs[ci].type = .chords
            let b = box(machines: cs) { s in
                s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                    var ch = ProcessorSlot(type: .chords)
                    ch.params.chordsMode = .follow; ch.params.chordsRoot = root; ch.params.chordsScale = .major
                    let dr = ProcessorSlot(type: .drone)
                    x.processors = [ch, dr]; return x }()
            }
            let e = RecordingEmitter()
            run(b, chord([heldNote]), beats: 4, into: e)
            assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        }
        // FOLLOW reads the PITCH — playing G in C major names the V, whose chord is G B D.
        XCTAssertEqual(emitted(root: 0, heldNote: 67), [55, 59, 62], "FOLLOW: G in C → V = G B D")
        // Playing the tonic names the I.
        XCTAssertEqual(emitted(root: 0, heldNote: 60), [48, 52, 55], "FOLLOW: C in C → I = C E G")
    }
    func testChordsWalkPlaysAValidChordDeterministicallyWithNoStuckNotes() {   // CHORDS WALK — the seeded gravity walk, replay-safe
        func run1(seed: Int) -> [RecordingEmitter.Ev] {
            var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
            cs[ci].type = .chords
            let b = box(machines: cs) { s in
                s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                    var ch = ProcessorSlot(type: .chords)
                    ch.params.chordsMode = .walk; ch.params.chordsRoot = 0; ch.params.chordsScale = .major; ch.params.chordsWalkSeed = seed
                    let dr = ProcessorSlot(type: .drone)
                    x.processors = [ch, dr]; return x }()
            }
            let e = RecordingEmitter()
            run(b, chord([60]), beats: 4, into: e)
            assertNothingLeftSounding(e)   // WALK leaves nothing hung across boundaries
            return e.ons.filter { $0.cable == 1 }
        }
        let a = run1(seed: 7)
        XCTAssertFalse(a.isEmpty, "WALK sounds a chord")
        XCTAssertTrue(a.allSatisfy { (36...84).contains(Int($0.note)) }, "every walked note stays in the anchored range")
        let b = run1(seed: 7)
        XCTAssertEqual(a.map { $0.note }, b.map { $0.note }, "same seed → identical walk (replay-exact)")
    }
    func testLoneChordsSoundsTheChordWithNoDownstream() {   // C5 — a bare [CHORDS] card (no →STRUM/ARP/DRONE) must emit
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = .chords
        let b = box(machines: cs) { s in
            s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                var ch = ProcessorSlot(type: .chords)
                ch.params.chordsMode = .pattern; ch.params.chordsRoot = 0; ch.params.chordsScale = .major
                ch.params.chordsDegrees = [Int](repeating: 4, count: 8)   // V everywhere
                x.processors = [ch]; return x }()   // LONE — one slot, nothing downstream
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 4, into: e)
        assertNothingLeftSounding(e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [55, 59, 62], "a lone [CHORDS] sounds V = G B D directly")
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
    func testPinnedAuditionSustainsChordsLikeADrone() {   // THE BUG (Paul): CHORDS must SOUND CONTINUOUSLY on the pinned audition, like a legato drone
        let drone = pinnedAuditionOns(.drone) { $0.params.gate = 1.0 }   // a legato drone is the sustaining baseline
        let chords = pinnedAuditionOns(.chords) { $0.params.chordsMode = .follow; $0.params.chordsRoot = 0; $0.params.chordsScale = .major }
        XCTAssertTrue(drone.sustainedLate, "a drone sustains on the pinned audition (baseline)")
        XCTAssertTrue(chords.sustainedLate, "CHORDS is STILL SOUNDING late in the pinned audition (got \(chords.ons) ons) — was 'nothing sounds', a dead audition")
    }
    func testPinnedAuditionSustainsChordsThroughABypassedDriverTail() {   // Paul device 2026-09-01: [CHORDS→ARP] plays; BYPASS the arp → must still play the chords
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = .chords
        let b = box(machines: cs) { s in
            var lane = [UInt16](repeating: 0, count: Snap.rows); lane[0] = 0b0000_0001; s.rowLane = lane   // pinned audition
            s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                var ch = ProcessorSlot(type: .chords); ch.params.chordsMode = .pattern; ch.params.chordsRoot = 0; ch.params.chordsScale = .major
                ch.params.chordsDegrees = [Int](repeating: 0, count: 8)
                var arp = ProcessorSlot(type: .arp); arp.bypassed = true                        // the BYPASSED driver → tail = identity passthrough
                x.processors = [ch, arp]; return x }()
        }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        let pool = chord([60])
        while beat < 10.0 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let stillOpen = e.ons.filter { $0.cable == 1 }.count - e.offs.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(stillOpen, 0, "[CHORDS → BYPASSED arp] still SUSTAINS the chord on the audition (bypassing the driver must not silence CHORDS)")
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) % 12 }), [0, 4, 7], "the composed CHORDS chord (I = C E G) sounds through the bypassed tail")
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }
    func testPinnedAuditionSustainsEveryHoldKind() {   // generalization (Paul: "extend to the other relevant processors")
        let harm = pinnedAuditionOns(.harmonize) { $0.params.harmIntervals = [4, 7, 0] }
        XCTAssertTrue(harm.sustainedLate, "HARMONIZE sustains on the pinned audition (got \(harm.ons) ons) — the fire-once bug is fixed for holds, not just CHORDS")
        let chance = pinnedAuditionOns(.chance) { $0.params.probability = 1.0 }
        XCTAssertTrue(chance.sustainedLate, "CHANCE sustains on the pinned audition (got \(chance.ons) ons)")
    }
    func testPinnedAuditionChordsFollowsTheHeldNote() {   // "feed in midi → it responds", on the REAL (pinned) audition path
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = .chords
        let b = box(machines: cs) { s in
            var lane = [UInt16](repeating: 0, count: Snap.rows); lane[0] = 0b0000_0001; s.rowLane = lane   // PIN row 0 (the audition)
            s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                var sl = ProcessorSlot(type: .chords); sl.params.chordsMode = .follow; sl.params.chordsRoot = 0; sl.params.chordsScale = .major
                x.processors = [sl]; return x }()
        }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func hold(_ note: UInt8?, beats: Double) {   // note = nil → NOTHING held (a silent stretch)
            let end = beat + beats
            while beat < end {
                router.process(box: b, pool: note.map { chord([$0]) } ?? NotePool(), playing: true, beatPos: beat, tempo: tempo,
                               sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
        }
        hold(nil, beats: 3)   // audition running, nothing held yet (the "then I play" order — like arming the latch AFTER)
        hold(67, beats: 5)    // play G → V (G B D)
        hold(60, beats: 5)    // change to C → RESPONDS with I (C E G)
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertTrue(notes.isSuperset(of: [55, 59, 62]), "G played AFTER the audition started → V sounds (picks up late input)")
        XCTAssertTrue(notes.isSuperset(of: [48, 52, 55]), "changing to C → RESPONDS with I — the audition follows the played note")
    }
    func testChordsSustainsFromALatchedReceiverOnThePinnedAudition() {   // Paul: "I set the receiver to a key / to some chords" — the latch feed
        var s = SceneState.empty()
        var lane = [UInt16](repeating: 0, count: Snap.rows); lane[0] = 0b0000_0001; s.rowLane = lane   // pinned audition row
        s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a]); x.inputReceiver = 0
            var sl = ProcessorSlot(type: .chords); sl.params.chordsMode = .pattern; sl.params.chordsRoot = 0; sl.params.chordsScale = .major
            sl.params.chordsDegrees = [Int](repeating: 0, count: 8); x.processors = [sl]; return x }()
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .chords
        var st = PluginState(machines: cs, scenes: [s])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        let frozen = NotePool(); frozen.noteOn(60, velocity: 100, channel: 0, cable: 1); frozen.rebuildSorted()   // the latched "key/chord" on R1
        let pools = [frozen, NotePool(), NotePool(), NotePool()]
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        for _ in 0..<40 {   // LIVE pool EMPTY (no keys), R1 ARMED → CHORDS must sound from the FROZEN pool, continuously
            router.process(box: b, pool: NotePool(), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, latchMask: 0b0001, latchedPools: pools, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let stillOpen = e.ons.filter { $0.cable == 1 }.count - e.offs.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(stillOpen, 0, "a latch-armed CHORDS SUSTAINS on the pinned audition with no live keys (I in C = C E G)")
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) % 12 }), [0, 4, 7], "the chord derives from the latched key — I = C E G")
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }
    func testChordsReadsTheKeyFromAReferencedScaleDoor() {   // C2b (Paul 2026-09-01): "SCALE FROM ▸" — the key comes from a REFERENCED door, not the card
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = .chords
        var s = SceneState.empty()
        s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a]); x.inputReceiver = 0   // OWN input = receiver 0 (the trigger — a normal door)
            var ch = ProcessorSlot(type: .chords)
            ch.params.chordsMode = .pattern; ch.params.chordsRoot = 0; ch.params.chordsScale = .major   // the CARD fallback says C major…
            ch.params.chordsDegrees = [Int](repeating: 0, count: 8)   // degree I everywhere
            ch.params.chordsScaleRef = 1   // …but SCALE FROM ▸ B (receiver 1), a SCALE door
            x.processors = [ch]; return x }()
        var st = PluginState(machines: cs, scenes: [s])
        var scaleDoor = Receiver(name: "B"); scaleDoor.doorMode = .scale; scaleDoor.scaleRoot = 4; scaleDoor.scaleType = .major   // receiver 1 DECLARES E major
        st.receivers = [Receiver(name: "1"), scaleDoor, Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        let e = RecordingEmitter(); run(b, chord([60]), beats: 4, into: e); assertNothingLeftSounding(e)   // trigger on receiver 0 (OMNI)
        let pcs = Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) % 12 })
        XCTAssertEqual(pcs, [4, 8, 11], "I in the REFERENCED door's key (E major = E G# B), not the card fallback C major ({0,4,7})")
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
    func testChordsRateStepsTheProgression() {   // RATE — the progression advances (multiple chords over time), not one frozen chord
        let pcs = chordsPinnedPCs(steps: 8, rate: .r1_8, degrees: [0, 4, 3, 5, 0, 4, 3, 5])   // I V IV vi …
        // A single frozen chord = 3 pitch classes; a stepped progression through I/V/IV/vi visits many more.
        XCTAssertGreaterThan(pcs.count, 3, "the progression STEPS on its rate clock — more than one chord's worth of notes (got \(pcs.sorted()))")
    }
    func testChordsStepsBoundsTheLoopLength() {   // STEPS — the pattern loops every N; degrees past N never play
        // steps = 2 → only degrees[0]=I (C E G) and degrees[1]=IV (F A C) play; degrees[2]=ii (D F A, pc 2 = D) is EXCLUDED.
        let pcs = chordsPinnedPCs(steps: 2, rate: .r1_8, degrees: [0, 3, 1, 1, 1, 1, 1, 1])
        XCTAssertFalse(pcs.contains(2), "STEPS=2 loops the first two degrees — degree ii (D, pc 2) past the loop never plays (got \(pcs.sorted()))")
        XCTAssertTrue(pcs.contains(4), "I (E, pc 4) plays")
        XCTAssertTrue(pcs.contains(5), "IV (F, pc 5) plays")
    }
    func testChordsNoScaleRefFallsBackToCMajor() {   // SCALE FROM = none → C major, so a fresh CHORDS is never keyless/silent
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = .chords
        let b = box(machines: cs) { s in
            s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                var ch = ProcessorSlot(type: .chords); ch.params.chordsMode = .pattern
                ch.params.chordsDegrees = [Int](repeating: 0, count: 8)   // chordsScaleRef nil (no reference)
                x.processors = [ch]; return x }()
        }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 4, into: e); assertNothingLeftSounding(e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) % 12 }), [0, 4, 7], "no SCALE FROM → C major fallback (I = C E G)")
    }
    func testChordsFollowRespondsToAChangingHeldNoteUnderAudition() {   // REPRO (Paul device 2026-09-01): "feed in midi, it doesn't respond"
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = .chords
        let b = box(machines: cs) { s in
            s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                var ch = ProcessorSlot(type: .chords)
                ch.params.chordsMode = .follow; ch.params.chordsRoot = 0; ch.params.chordsScale = .major
                x.processors = [ch]; return x }()
        }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func hold(_ note: UInt8, beats: Double) {   // audition = forceColumn 0 (a frozen continuous pass)
            let end = beat + beats
            while beat < end {
                router.process(box: b, pool: chord([note]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
        }
        hold(67, beats: 6)   // play G → should sound V (G B D)
        hold(60, beats: 6)   // change to C → should RESPOND, sounding I (C E G)
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertTrue(notes.isSuperset(of: [55, 59, 62]), "played G → V sounds (G B D)")
        XCTAssertTrue(notes.isSuperset(of: [48, 52, 55]), "changing to C → RESPONDS with I (C E G) — not stuck on one chord")
    }
    func testChordsPatternPlaysTheProgressionAcrossAFilledRow() {   // PATTERN "playing": a CHORDS machine across a ROW walks the degrees per column
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = .chords
        let b = box(machines: cs) { s in
            for c in 0..<8 {   // the same CHORDS cell in ALL 8 columns of row 0 (a stamped row) → the progression sweeps
                s.cells[c][0] = { var x = Cell(machineID: "gold", buses: [.a])
                    var ch = ProcessorSlot(type: .chords)
                    ch.params.chordsMode = .pattern; ch.params.chordsRoot = 0; ch.params.chordsScale = .major
                    ch.params.chordsDegrees = [0, 1, 2, 3, 4, 5, 6, 0]   // I ii iii IV V vi vii I — one per column
                    x.processors = [ch]; return x }()
            }
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 8, into: e)   // ≥ one full pass, a note held throughout
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == 1 }
        let distinctOnsets = Set(ons.map { $0.sample }).count
        XCTAssertGreaterThanOrEqual(distinctOnsets, 3, "a chord strikes per column as the playhead sweeps (got \(distinctOnsets) onsets, \(ons.count) note-ons) — not one chord then silence")
        // The chords DIFFER across the pass — a non-tonic degree appears alongside I, proving a real progression.
        let pcs = Set(ons.map { Int($0.note) % 12 })
        XCTAssertTrue(pcs.isSuperset(of: [0, 4, 7]), "I = C E G appears")
        XCTAssertTrue(pcs.contains(2) || pcs.contains(5) || pcs.contains(9) || pcs.contains(11), "a non-tonic degree (ii/iii/IV/…) appears too — a real progression, not one repeated chord")
    }
    func testChordsVoicingSeventhReachesTheEngineAndComposesDownstream() {   // C5 — VOICING 7TH is 4 notes; [CHORDS→ARP] arpeggiates the chord
        func lone7th() -> [UInt8] {
            var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
            cs[ci].type = .chords
            let b = box(machines: cs) { s in
                s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                    var ch = ProcessorSlot(type: .chords)
                    ch.params.chordsMode = .pattern; ch.params.chordsRoot = 0; ch.params.chordsScale = .major
                    ch.params.chordsDegrees = [Int](repeating: 0, count: 8); ch.params.chordsVoicing = .seventh
                    x.processors = [ch]; return x }()
            }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 4, into: e); assertNothingLeftSounding(e)
            return Array(Set(e.ons.filter { $0.cable == 1 }.map { $0.note })).sorted()
        }
        XCTAssertEqual(lone7th(), [48, 52, 55, 59], "I7 in C = C E G B (VOICING 7TH reaches the engine)")
        // [CHORDS→ARP]: composeChainSet folds the chord upstream → the arp walks ITS notes (never the raw held 60).
        var cs = arpMachines(); let ci = machineIDs.firstIndex(of: "gold")!
        cs[ci].type = .chords
        let b = box(machines: cs) { s in
            s.cells[0][0] = { var x = Cell(machineID: "gold", buses: [.a])
                var ch = ProcessorSlot(type: .chords)
                ch.params.chordsMode = .pattern; ch.params.chordsRoot = 0; ch.params.chordsScale = .major
                ch.params.chordsDegrees = [Int](repeating: 0, count: 8)   // I = C E G
                let arp = ProcessorSlot(type: .arp)
                x.processors = [ch, arp]; return x }()
        }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 4, into: e); assertNothingLeftSounding(e)
        let played = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertFalse(played.isEmpty, "[CHORDS→ARP] arpeggiates")
        XCTAssertTrue(played.allSatisfy { [0, 4, 7].contains(Int($0) % 12) }, "the arp walks ONLY the I chord's pitch classes C·E·G (any octave), never the raw held 60 escaping the chord")
    }
    // PER-ROW GLIDE + MOD leave-disposition on the ROW's own clock (Paul 2026-09-01): only per-row ECHO was asserted. Two GLIDE
    // cells (fast row vs slow row) → the fast row re-anchors far more often (its phrase-ends fire on its OWN clock, not the
    // scene default); two MOD cells likewise emit their CC updates on each row's clock. Guards the onlyRow scoping of glide/mod.
    func testPerRowGlideAndModFireOnTheRowsOwnClock() {
        // GLIDE — fast row 0 vs slow row 1, each a single-slot glide on its own emitter.
        var gcs = arpMachines()
        for id in ["gold", "azure"] { gcs[machineIDs.firstIndex(of: id)!].type = .glide }
        func glideCell(_ id: String, _ bus: Bus) -> Cell {
            var x = Cell(machineID: id, buses: [bus])
            var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glideRange = 12; g.params.glidePriority = .last; g.params.glideTime = 0.05
            x.processors = [g]; return x
        }
        let gb = box(machines: gcs) { s in
            for c in 0..<8 { s.cells[c][0] = glideCell("gold", .a) }   // row 0 FAST glide (bus A)
            for c in 0..<8 { s.cells[c][1] = glideCell("azure", .b) }  // row 1 SLOW glide (bus B)
            var rate = [StepRate?](repeating: nil, count: Snap.rows); rate[0] = .r1_8; rate[1] = .r2_1; s.rowStepRate = rate
        }
        let ge = RecordingEmitter()
        run(gb, chord([60, 64, 67]), beats: 16, into: ge)
        let fastG = ge.events.filter { $0.cable == 1 && $0.status == 0x90 }.count   // row 0 anchors (fast → re-anchors more)
        let slowG = ge.events.filter { $0.cable == 2 && $0.status == 0x90 }.count
        XCTAssertGreaterThan(fastG, slowG, "the fast row's glide re-anchors far more than the slow row's — per-row phrase-end clock")
        assertNothingLeftSounding(ge)

        // MOD — a fast row vs a slow row, each a single-slot MOD emitting a CC; the fast row updates its CC far more often.
        var mcs = arpMachines()
        for id in ["gold", "azure"] { let i = machineIDs.firstIndex(of: id)!; mcs[i].type = .mod; mcs[i].paramsA.modCC = 74 }
        let mb = box(machines: mcs) { s in
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])
            s.cells[0][1] = Cell(machineID: "azure", buses: [.b])
            var rate = [StepRate?](repeating: nil, count: Snap.rows); rate[0] = .r1_8; rate[1] = .r2_1; s.rowStepRate = rate
        }
        let me = RecordingEmitter()
        run(mb, chord([60, 64, 67]), beats: 16, into: me)
        let r0CC = me.events.filter { $0.cable == 1 && $0.status == 0xB0 }.count
        let r1CC = me.events.filter { $0.cable == 2 && $0.status == 0xB0 }.count
        // MOD emits its CC on a fixed control grid (not step-rate-proportional like ECHO/GLIDE), so this asserts each row's
        // MOD runs INDEPENDENTLY on its own clock — both emit their CC on their own emitter (per-row onlyRow scoping works).
        XCTAssertGreaterThan(r0CC, 0, "row 0's MOD emits its CC on bus A (its own clock)")
        XCTAssertGreaterThan(r1CC, 0, "row 1's MOD emits its CC on bus B — both per-row MOD rows run, neither starves the other")
        assertNothingLeftSounding(me)
    }
    // ARP VELOCITY (Paul 2026-09-30): a DELIBERATE reversal of the old "every processor inherits source velocity"
    // default (still true for euclid — testEuclidGeneratorInheritsSourceVelocity below — and every other generator;
    // ARP is the one exception Paul asked for). The arp's own VELOCITY control (default 100) sets the output level
    // outright; the source note's own velocity is never read.
    func testArpUsesVelocityControlIgnoringSource() {
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, velChord([(60, 30), (67, 120)]), beats: 8, into: e)
        let vels = Set(e.ons.filter { $0.cable == 1 }.map { $0.vel })
        XCTAssertFalse(vels.isEmpty, "the arp sounded")
        XCTAssertTrue(vels.isSubset(of: [100]), "every arp note plays at the VELOCITY control's default (100), ignoring the source's own 30/120 — got \(vels)")
        assertNothingLeftSounding(e)
    }
    // A chain carries the ARP's OWN resolved velocity downstream, not the source's: [ARP → HARMONIZE] — both the dry
    // note and the +12 voice take whatever the driver (ARP) already resolved (its VELOCITY control, 100 default) —
    // HARMONIZE's fold (Router.applyStage's .harmonize case) reads the ONE-NOTE pool emitDriverNote seeds with the
    // driver's own (note, velocity), never the original chord.
    func testChainUsesArpVelocityControlThroughHarmonize() {
        let b = box(machines: arpMachines()) { $0.cells[0][0] = {
            var c = Cell(machineID: "gold", buses: [.a])
            let arp = ProcessorSlot(type: .arp)
            var h = ProcessorSlot(type: .harmonize); h.params.harmIntervals = [12, 0, 0]
            c.processors = [arp, h]; return c }() }
        let e = RecordingEmitter(); run(b, velChord([(60, 44)]), beats: 8, into: e)
        let dry = e.ons.filter { $0.cable == 1 && $0.note == 60 }
        let harm = e.ons.filter { $0.cable == 1 && $0.note == 72 }
        XCTAssertTrue(!dry.isEmpty && dry.allSatisfy { $0.vel == 100 }, "the dry note plays at the arp's VELOCITY control (100), not the source's 44")
        XCTAssertTrue(!harm.isEmpty && harm.allSatisfy { $0.vel == 100 }, "the +12 harmony voice also takes the arp's own resolved velocity (100), unscaled")
        assertNothingLeftSounding(e)
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
    // The soundcheck path matches playback (Paul 2026-09-30): a stopped-transport AUDITION of an arp cell also plays
    // at the VELOCITY control's level (100 default), ignoring the source chord's own dynamics — audition still
    // matches playback, just under the new ARP velocity model (see testArpUsesVelocityControlIgnoringSource above).
    func testAuditionUsesVelocityControlIgnoringSource() {
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let pool = velChord([(60, 40), (67, 118)])
        var ts = 0.0
        for _ in 0..<10 {   // stopped transport, cell 0 (col 0·row 0) auditioned
            router.process(box: b, pool: pool, playing: false, beatPos: 0, tempo: 120, sampleRate: 48_000,
                           timestampSample: ts, frameCount: 2048, audition: 0, out: e, diag: &diag)
            ts += 2048
        }
        let vels = Set(e.ons.filter { $0.cable == 1 }.map { $0.vel })
        XCTAssertFalse(vels.isEmpty, "the audition sounded")
        XCTAssertTrue(vels.isSubset(of: [100]), "audition plays at the VELOCITY control's default (100), ignoring the source's 40/118 — got \(vels)")
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
    func testRenderAutoPassSpanRampsHitsUpAcrossBars() {
        let box = renderAutoBox(pulsesBase: 1, lane: passSpanLane())
        XCTAssertFalse(box.renderAuto.isEmpty, "a ×2 lane produces a render-time descriptor (not a compile-time bake)")
        let e = RecordingEmitter(); run(box, chord([60]), beats: 32, into: e)   // 2 bars = one ×2 period
        let b0 = onsInBar(e, 0), b1 = onsInBar(e, 1)
        XCTAssertGreaterThan(b1, b0, "×2 pass span ramps euclid HITS up across the 2 bars (bar1 \(b1) > bar0 \(b0))")
        assertNothingLeftSounding(e)
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
    func testRenderAutoSmoothLanePlaysAndLeavesNothingSounding() {
        var lane = AutoLane(); lane.slot = 0; lane.param = "euclidPulses"; lane.lo = 1; lane.hi = 8; lane.spanStart = 0; lane.smooth = true
        let box = renderAutoBox(pulsesBase: 1, lane: lane)
        XCTAssertTrue(box.renderAuto.contains { $0?.smooth == true }, "a SMOOTH lane produces a render-time descriptor with smooth = true")
        let e = RecordingEmitter(); run(box, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "the SMOOTH-automated euclid actually plays")
        assertNothingLeftSounding(e)
    }
    func testRenderAutoNoActiveLaneIsInert() {
        var lane = passSpanLane()
        var st = PluginState(machines: { var cs = arpMachines(); var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = 4; cs[machineIDs.firstIndex(of: "gold")!].templateChain = [eu]; return cs }(),
                             scenes: [{ var s = SceneState.empty(); for c in 0..<8 { s.cells[c][0] = Cell(machineID: "gold", buses: [.a]) }; return s }()])
        st.partAuto = ["gold": PartAutoMachine(activeLane: -1, lanes: [lane])]   // NONE selected → no render-time descriptor
        XCTAssertTrue(SnapshotBuilder.build(from: st).renderAuto.isEmpty, "activeLane = NONE ⇒ box.renderAuto stays empty (byte-identical)")
    }
    // PLAY: THIS CELL (user 2026-08-09): forcing the effective column HOLDS the cell in that column playing every
    // window, regardless of the natural timeline — so an isolated cell sounds continuously, ungated by the sequence.
    // Uses an ARP (tick-emitter) — the case that needs iterateTicks UNGATED; a generator decouples via colStart.
    func testForceColumnHoldsTheCellPlayingEveryColumn() {
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // arp cell in column 0
        func play(forceColumn: Int) -> Int {
            let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
            let pool = chord([60, 64, 67]); let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
            let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
            while beat < 16.0 {   // one full pass (8 columns, S = 2 beats)
                router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, forceColumn: forceColumn, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
            router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let normal = play(forceColumn: -1)   // gold (column 0) strikes only while column 0 is the active column
        let forced = play(forceColumn: 0)    // …held on column 0 → strikes EVERY column
        XCTAssertGreaterThan(forced, normal * 3, "forcing the column holds the cell playing every column (\(forced) vs \(normal))")
    }
    // PLAY: THIS CELL for a HOLD cell (user 2026-08-10 bug): a passthrough/identity hold must SUSTAIN under a frozen
    // column, not gate off after one column. Forcing the column held the cell but emitColumnHolds only fired on the
    // (never-repeating) transition, so a NON-legato hold sounded one column then went silent — while the palette
    // still showed its machine "running". The fix re-runs the holds every window (immortal + adopted) under forceColumn.
    // pending-tasks E / 2026-08-23 adversarial hunt: PLAY: THIS CELL (forceColumnHold) on a SELF-COLLIDING harmonize —
    // {60,67}+7 fans 60's +7 onto 67's root — leaked a fresh immortal voice EVERY reconcile window: adoptLegatoBus
    // un-marked BOTH colliding pairs on the first source's call, so the second source found none and re-struck. It
    // machine-gunned and grew toward the voice cap under audition. The fix adopts one own+All pair per call, so the
    // colliding wire is struck once then HELD (adopted), not re-struck each window.
    func testForceColumnSelfCollidingHarmonizeDoesNotLeakVoices() {
        var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
        cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = [7, 0, 0]   // +7: 60→67 collides with 67's root
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let pool = chord([60, 67]); let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        var windows = 0
        while beat < 8.0 {   // ~94 frozen-column reconcile windows — a per-window re-strike would show as ~94 ons on 67
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += wb; ts += Double(frames); windows += 1
        }
        let collidingOns = e.ons.filter { $0.cable == 1 && $0.note == 67 }.count
        XCTAssertLessThan(collidingOns, 6, "the colliding harmony wire is held (adopted), not machine-gunned once per window (\(windows) windows, \(collidingOns) ons)")
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 67, 74], "the +7 harmony sounds exactly {60,67,74}")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }
    func testForceColumnSustainsAHoldCell() {
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .empty   // identity hold (all-open, .retrig = non-legato)
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let pool = chord([60, 64, 67]); let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 32.0 {   // two full passes on a frozen column — a broken hold falls silent after column 0's length
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67], "the hold cell sounds its chord under a frozen column")
        let stillOn = e.ons.filter { $0.cable == 1 }.count - e.offs.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(stillOn, 0, "the hold is STILL sounding late in the frozen column (it did not gate off after one column)")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }
    // STRUM under a HELD column (PLAY THIS MIDI CHAIN) must RE-ARM each step — not fire its stagger ONCE then fall
    // silent. strumProgress reset only on a column transition, which never comes under forceColumnHold, so the default
    // STRUM machine was silent on the machine audition; the fix re-arms it each musical step. (Paul 2026-08-15)
    func testForceColumnReArmsStrumEachStep() {
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .strum; cs[machineIDs.firstIndex(of: "gold")!].paramsA.spread = 0.1
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let pool = chord([60, 64, 67]); let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 16.0 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let root = e.ons.filter { $0.cable == 1 && $0.note == 60 }
        XCTAssertGreaterThan(root.count, 1, "the strum RE-STRUMS each step under a frozen column (one-shot before the fix)")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
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
    // ARP → SPAN (Paul 2026-09-13, replaces FIT — the universal span-ladder, same as riff/euclid): SPAN re-anchors the
    // pattern to index 0 every N columns. A FREE UP arp of [60,64,67] at ONE tick per column (rate == stepRate == 1/8)
    // climbs 60·64·67·60… across the row → note 67 (index 2) sounds. SPAN=2 re-anchors every 2 columns, so the index
    // only ever reaches 1 within a window → 67 NEVER sounds. Proves the engine reads arpSpanN + re-syncs (not scales speed).
    func testArpSpanReAnchorsThePattern() {
        func has67(spanN: Int?) -> Bool {
            var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
            cs[gi].paramsA.pattern = .up; cs[gi].paramsA.phase = .free; cs[gi].paramsA.octaves = 1
            cs[gi].paramsA.rate = .r1_8; cs[gi].paramsA.arpSpanN = spanN
            let b = box(machines: cs) { s in
                s.stepRate = .r1_8                                        // 0.5-beat columns == the arp rate → one note per column
                for col in 0..<8 { s.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }
            }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 3.9, into: e)   // exactly 8 columns
            assertNothingLeftSounding(e)
            return e.ons.contains { $0.cable == 1 && $0.note == 67 }
        }
        XCTAssertTrue(has67(spanN: nil), "FREE: the UP arp climbs to index 2 → 67 sounds")
        XCTAssertFalse(has67(spanN: 2), "SPAN=2: the pattern re-anchors before reaching index 2 → 67 never sounds")
    }
    // CHANCE → WEIGHT/tilt RENDERED (not just the pure fn): with prob 0.5, +tilt drives the TOP note's p→1 (always
    // sounds) and the BOTTOM's p→0 (dropped); −tilt reverses. Proves the router READS chanceTilt at the hold path.
    func testChanceWeightBiasesEmittedNotes() {
        func topBot(_ tilt: Double) -> (top: Int, bot: Int) {
            var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
            cs[gi].type = .chance; cs[gi].paramsA.probability = 0.5; cs[gi].paramsA.chanceTilt = tilt
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 62, 64, 65, 67, 69]), beats: 4, into: e)
            return (e.ons.filter { $0.cable == 1 && $0.note == 69 }.count,
                    e.ons.filter { $0.cable == 1 && $0.note == 60 }.count)
        }
        let up = topBot(1.0)
        XCTAssertGreaterThan(up.top, 0, "+tilt: the top note (p→1) sounds")
        XCTAssertEqual(up.bot, 0, "+tilt: the bottom note (p→0) is dropped")
        let down = topBot(-1.0)
        XCTAssertEqual(down.top, 0, "−tilt: the top note is dropped")
        XCTAssertGreaterThan(down.bot, 0, "−tilt: the bottom note sounds")
    }
    // STRUM → WIDTH RENDERED: PER-NOTE (strumSpreadNorm=false) spreads the rake WIDER than EVEN, so the last onset
    // lands LATER. Proves the router threads `strumSpreadNorm` into strumOffset (a dropped arg would fail here).
    func testStrumSpreadNormWidensTheRakeWhenPerNote() {
        func lastOnset(_ norm: Bool) -> Int64 {
            var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
            cs[gi].type = .strum; cs[gi].paramsA.spread = 0.5; cs[gi].paramsA.strumSpreadNorm = norm
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 62, 64, 65, 67, 69]), beats: 1.9, into: e)
            return e.ons.filter { $0.cable == 1 }.map { $0.sample }.max() ?? 0
        }
        XCTAssertGreaterThan(lastOnset(false), lastOnset(true), "PER-NOTE spreads the rake wider → later last onset")
    }
    // DRONE = a LEGATO chord-hold (user 2026-08-10): placed across columns it HOLDS continuously (NO re-strike per
    // step) and is SILENT where no drone cell is (playhead-dependent). gold=drone in cols 0..3; hold a chord one pass.
    func testDroneIsALegatoHoldAcrossItsColumns() {
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .drone
        let b = box(machines: cs) { for c in 0..<4 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) } }   // drone cols 0-3, row 0
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 16.0 {   // ONE pass: cols 0-3 hold the drone (legato), cols 4-7 have no drone → it releases at col 4
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let onCounts = Dictionary(grouping: e.ons.filter { $0.cable == 1 }, by: { $0.note }).mapValues { $0.count }
        XCTAssertEqual(Set(onCounts.keys), [60, 64, 67], "the drone sounds the held chord")
        for n: UInt8 in [60, 64, 67] { XCTAssertEqual(onCounts[n], 1, "note \(n) strikes ONCE across the legato drone span (cols 0-3) — no per-step re-strike") }
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e); XCTAssertTrue(router.quiescent)
    }
    // R1 (2026-08-30): the master MUTE toggle must CLOSE sustained content, not merely suppress NEW notes. A legato
    // drone is an immortal hold — before the fix its note-on was never paired with an off when muted (it rang on, an
    // invariant-4 violation). Now MUTE folds into the enabled mask like master-KILL → the enabled→disabled edge closes it.
    func testMasterMuteClosesASustainedDrone() {
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .drone
        let bLive = box(machines: cs) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) } }   // drone the whole row → it holds every column
        let bMute = box(machines: cs, masterMute: true) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) } }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        for _ in 0..<4 {   // hold the drone a few renders → it sustains as an immortal legato hold
            router.process(box: bLive, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67], "the drone sounds the held chord")
        // ENGAGE master MUTE → the sustained notes must CLOSE (offs emitted), nothing left ringing.
        router.process(box: bMute, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        XCTAssertTrue(router.quiescent, "master MUTE flushed the sustained drone — no leaked voice")
    }
    // Render→main SOUNDING feed buckets by emitter (device crash 2026-08-10: the nested [[…]] feed arrays raced the
    // 4 Hz poll → libmalloc corruption; flattened to 4×W). This locks the flat re-indexing: a note on emitter A and
    // one on emitter C land in buckets 0 and 2, B/D empty — no smear across the flat buffer.
    func testEmitterSoundingFeedBucketsByBus() {
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!].type = .empty   // identity holds → sustained voices to snapshot
        cs[machineIDs.firstIndex(of: "cyan")!].type = .empty
        let b = box(machines: cs) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a])
            $0.cells[0][1] = Cell(machineID: "cyan", buses: [.c])
        }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        router.process(box: b, pool: chord([60, 64]), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                       timestampSample: 0, frameCount: 2048, out: e, diag: &diag)
        router.snapshotEmitterSounding()
        let snap = router.drainEmitterSounding()
        XCTAssertEqual(snap.count, 4)
        XCTAssertFalse(snap[0].isEmpty, "emitter A (bucket 0) is sounding")
        XCTAssertFalse(snap[2].isEmpty, "emitter C (bucket 2) is sounding")
        XCTAssertTrue(snap[1].isEmpty && snap[3].isEmpty, "B and D are silent (no cross-bucket smear)")
    }
    // PLAY: THIS CELL for a HARMONIZE cell (user 2026-08-10: "works on gold, not on orange"): harmonize is a HOLD
    // mode whose emitHarmony path wasn't adoptable, so under the frozen column it played one column then rested.
    // The fix makes each harmony voice immortal + adopted under forceColumn, so it sustains like an identity hold.
    // pending-tasks E (HARMONIZER hung-note): GUARD for the fan-out COLLISION + live interval change. HARMONIZE's fan-out
    // can collide two source notes onto one wire note ({60,67}+7 → 60's +7 = 67 collides with 67's root; 67's +7 = 74);
    // a live INTERVAL CHANGE mid-sustain (no scene-flush) re-shapes the harmony at the next boundary. This path is CLEAN:
    // mid-column the sounding wire set is exactly the current harmony (refcount-balanced), and nothing is stuck after
    // stop. (The device-reported transient hung-note was NOT reproducible via this scenario — see the 2026-08-23 hunt.)
    func testHarmonizeCollisionNoStuckNoteAcrossIntervalChange() {
        let gi = machineIDs.firstIndex(of: "gold")!
        func mk(_ iv: [Int]) -> SnapshotBox {
            var cs = arpMachines(); cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = iv
            return box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        let held = chord([60, 67])
        func render(_ b: SnapshotBox, playing: Bool, pool: NotePool) {
            router.process(box: b, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let a = mk([7, 0, 0])   // +7 on {60,67} → wire {60,67,74} (67 emitted by BOTH 60's +7 and 67's root — collision)
        for _ in 0..<7 { render(a, playing: true, pool: held) }                 // ~0.6 beats — clearly mid the first column (harmony ON, off in the future)
        func soundingSet() -> Set<Int> {   // wire notes whose LAST emitted event on cable 1 is an ON (refcount-safe)
            var lastOn: [UInt8: Bool] = [:]
            for ev in e.events where ev.cable == 1 {
                if ev.status == 0x90 && ev.vel > 0 { lastOn[ev.note] = true } else if ev.status == 0x80 || ev.vel == 0 { lastOn[ev.note] = false }
            }
            return Set(lastOn.filter { $0.value }.keys.map { Int($0) })
        }
        XCTAssertEqual(soundingSet(), [60, 67, 74], "mid-column, the +7 harmony of {60,67} sounds exactly {60,67,74}")
        for _ in 0..<24 { render(mk([5, 3, 0]), playing: true, pool: held) }    // interval change mid-sustain (no flush)
        for _ in 0..<7 { render(mk([5, 3, 0]), playing: true, pool: held) }
        render(mk([5, 3, 0]), playing: false, pool: NotePool())                 // release + stop
        assertNothingLeftSounding(e)
    }
    func testForceColumnSustainsAHarmonizeCell() {
        var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
        cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = [4, 7, 0]   // 60 → 60/64/67
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let pool = chord([60]); let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 32.0 {   // two frozen passes — a broken harmonize hold falls silent after column 0's length
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67], "the harmonize cell sounds its harmonized chord under a frozen column")
        let stillOn = e.ons.filter { $0.cable == 1 }.count - e.offs.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(stillOn, 0, "the harmonize hold is STILL sounding late in the frozen column (did not gate off)")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }
    // UTILITY — OCTAVE (Paul 2026-08-22): a single-slot OCTAVE holds the chord shifted by ±12·n (pitch-class preserved).
    func testOctaveShiftsTheHeldChordByOctaves() {
        let gi = machineIDs.firstIndex(of: "gold")!
        func mk(_ n: Int) -> SnapshotBox {
            var cs = arpMachines(); cs[gi].type = .octave; cs[gi].paramsA.utilOctave = n
            return box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        }
        let up = RecordingEmitter(); run(mk(1), chord([60, 64, 67]), beats: 2, into: up)
        XCTAssertEqual(Set(up.ons.filter { $0.cable == 1 }.map { Int($0.note) }), [72, 76, 79], "+1 octave lifts each held note")
        let dn = RecordingEmitter(); run(mk(-2), chord([60, 64, 67]), beats: 2, into: dn)
        XCTAssertEqual(Set(dn.ons.filter { $0.cable == 1 }.map { Int($0.note) }), [36, 40, 43], "−2 octaves lowers each note")
        assertNothingLeftSounding(up); assertNothingLeftSounding(dn)
    }
    // UTILITY — TRANSPOSE: shifts the held chord by semitones; notes shifted out of the MIDI range simply drop.
    func testTransposeShiftsBySemitonesAndDropsOutOfRange() {
        let gi = machineIDs.firstIndex(of: "gold")!
        func mk(_ st: Int) -> SnapshotBox {
            var cs = arpMachines(); cs[gi].type = .transpose; cs[gi].paramsA.utilTranspose = st
            return box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        }
        let e = RecordingEmitter(); run(mk(7), chord([60, 64]), beats: 2, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) }), [67, 71], "up a fifth (+7 st)")
        let hi = RecordingEmitter(); run(mk(24), chord([100, 120]), beats: 2, into: hi)   // 120+24=144 > 127 → dropped
        XCTAssertEqual(Set(hi.ons.filter { $0.cable == 1 }.map { Int($0.note) }), [124], "100→124 sounds; 120→144 is out of range, dropped")
        assertNothingLeftSounding(e); assertNothingLeftSounding(hi)
    }
    // UTILITY — the shift folds through the chain from EITHER side: [ARP→OCTAVE] lifts each arp note; [OCTAVE→ARP] lifts
    // the pool then arps it. Both raise a bare arp's note SET by an octave (S-independent — the set shifts, not the rhythm).
    func testOctaveFoldsThroughAChainEitherSide() {
        func mk(_ procs: [ProcessorSlot]) -> SnapshotBox {
            box(machines: arpMachines()) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = procs; return c }() }
        }
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8; arp.params.pattern = .up; arp.params.octaves = 1
        var oct = ProcessorSlot(type: .octave); oct.params.utilOctave = 1
        let bare = RecordingEmitter(); run(mk([arp]),      chord([48, 52, 55]), beats: 4, into: bare)
        let post = RecordingEmitter(); run(mk([arp, oct]), chord([48, 52, 55]), beats: 4, into: post)
        let pre  = RecordingEmitter(); run(mk([oct, arp]), chord([48, 52, 55]), beats: 4, into: pre)
        let lifted = Set(bare.ons.filter { $0.cable == 1 }.map { Int($0.note) + 12 })
        XCTAssertFalse(lifted.isEmpty, "the bare arp sounds")
        XCTAssertEqual(Set(post.ons.filter { $0.cable == 1 }.map { Int($0.note) }), lifted, "[ARP→OCTAVE] lifts every arp note an octave")
        XCTAssertEqual(Set(pre.ons.filter { $0.cable == 1 }.map { Int($0.note) }), lifted, "[OCTAVE→ARP] arps the octave-lifted pool")
        assertNothingLeftSounding(post); assertNothingLeftSounding(pre)
    }
    // UTILITY — CHANNEL (Paul 2026-08-22): the cell exits on a chosen MIDI channel; WIRE keeps the bus stamp.
    // (The reference-chord AUDITION FALLBACK was REMOVED 2026-08-23, Paul — a synthetic chord must never reach the user;
    // its test went with it. The audition now sounds only real input, silent when nothing is held.)
    // review 2026-08-23: [CHANNEL→ECHO] — the dry AND its repeats sound on the cell's OWN channel (not a stale
    // neighbour's, not the wire). The dry uses cellChanOverride (registerEcho); the tails carry EchoTail.chan.
    func testChannelEchoSoundsEntirelyOnTheCellsChannel() {
        let b = box(machines: arpMachines()) {
            var c = Cell(machineID: "gold", buses: [.a])
            var ch = ProcessorSlot(type: .channel); ch.params.utilChannel = 5   // channel 5 → wire 4
            var e = ProcessorSlot(type: .echo); e.params.echoSync = true; e.params.echoDelayDiv = 2; e.params.echoRepeats = 3; e.params.echoThru = true
            c.processors = [ch, e]
            $0.cells[0][0] = c
        }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 3, into: e)
        let cable1 = e.ons.filter { $0.cable == 1 }
        XCTAssertGreaterThan(cable1.count, 1, "the [CHANNEL→ECHO] cell sounds a dry + repeats")
        XCTAssertTrue(cable1.allSatisfy { $0.chan == 4 }, "every note-on (dry + echoes) is on channel 5 (wire 4), not the wire default 0")
        assertNothingLeftSounding(e)
    }
    func testChannelOverridesTheOutputChannel() {
        let gi = machineIDs.firstIndex(of: "gold")!
        func mk(_ ch: Int) -> SnapshotBox {
            var cs = arpMachines(); cs[gi].type = .channel; cs[gi].paramsA.utilChannel = ch
            return box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        }
        let wire = RecordingEmitter(); run(mk(0), chord([60, 64]), beats: 2, into: wire)   // WIRE = bus A's stamp (channel 1 → wire 0)
        XCTAssertFalse(wire.ons.filter { $0.cable == 1 }.isEmpty, "the cell sounds")
        XCTAssertTrue(wire.ons.filter { $0.cable == 1 }.allSatisfy { $0.chan == 0 }, "WIRE uses the bus stamp channel (1 → wire 0)")
        let c3 = RecordingEmitter(); run(mk(3), chord([60, 64]), beats: 2, into: c3)
        XCTAssertTrue(c3.ons.filter { $0.cable == 1 }.allSatisfy { $0.chan == 2 } && !c3.ons.isEmpty, "CHANNEL 3 stamps wire channel 2 (0-based)")
        assertNothingLeftSounding(wire); assertNothingLeftSounding(c3)
    }
    // UTILITY — NUDGE: a pure time offset (sixteenths) slides the stream later/earlier; no stuck notes (clamped like POCKET).
    func testNudgeShiftsTheOnsetInTime() {
        let gi = machineIDs.firstIndex(of: "gold")!
        func mk(_ n: Int) -> SnapshotBox {
            var cs = arpMachines(); cs[gi].type = .nudge; cs[gi].paramsA.utilNudge = n
            return box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        }
        let straight = RecordingEmitter(); run(mk(0), chord([60]), beats: 2, into: straight)
        let late = RecordingEmitter(); run(mk(4), chord([60]), beats: 2, into: late)        // +4 sixteenths = +0.25 beat later
        let s0 = straight.ons.filter { $0.cable == 1 && $0.note == 60 }.map { $0.sample }.min()
        let s1 = late.ons.filter { $0.cable == 1 && $0.note == 60 }.map { $0.sample }.min()
        XCTAssertNotNil(s0); XCTAssertNotNil(s1)
        XCTAssertGreaterThan(s1!, s0!, "+4 sixteenths pushes the note-on later in time")
        assertNothingLeftSounding(straight); assertNothingLeftSounding(late)
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
    func testEuclidThenClosedGateIsSilent() {
        let b = box(machines: arpMachines()) {
            var c = Cell(machineID: "gold", buses: [.a])
            var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = 4; eu.params.euclidSteps = 8
            var gate = ProcessorSlot(type: .chance); gate.params.probability = 0.0   // deterministic silence (PASSGATE removed 2026-09-28)
            c.processors = [eu, gate]; $0.cells[0][0] = c
        }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "the closed gate after euclid folds to silence")
        assertNothingLeftSounding(e)
    }
    func testHarmonizeThenEuclidGeneratesOverTheComposedSet() {
        func mk(harm: Bool) -> SnapshotBox {
            box(machines: arpMachines()) {
                var c = Cell(machineID: "gold", buses: [.a])
                var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = 4; eu.params.euclidSteps = 8
                if harm {
                    var h = ProcessorSlot(type: .harmonize); h.params.harmIntervals = [12, 0, 0]
                    c.processors = [h, eu]
                } else { c.processors = [eu] }
                $0.cells[0][0] = c
            }
        }
        let bare = RecordingEmitter(); run(mk(harm: false), chord([60]), beats: 2, into: bare)
        let harm = RecordingEmitter(); run(mk(harm: true), chord([60]), beats: 2, into: harm)
        XCTAssertGreaterThan(harm.ons.filter { $0.cable == 1 }.count, bare.ons.filter { $0.cable == 1 }.count,
                             "[HARMONIZE→EUCLID]: euclid pulses over the harmonized (doubled) upstream set")
        assertNothingLeftSounding(bare); assertNothingLeftSounding(harm)
    }
    func testBurstEmitsCountStrikes() {
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .burst)
            c.paramsA.count = 4; c.paramsA.curve = 0; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 4, "a 4-strike burst on one note")
        assertNothingLeftSounding(e)
    }
    func testBurstDownbeatFiresOnAnUnalignedColumnBoundary() {
        // REGRESSION (Paul 2026-08-18): like EUCLID, a window-scan generator dropped its DOWNBEAT strike (f=0, at the
        // column boundary) when the boundary fell mid render-block. Placed in COLUMN 1 (start = S = 2, mid-block), the
        // 4-strike even burst must still sound all 4 (was 3 = the f=0 strike lost). The scanFrom fix catches it.
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .burst)
            c.paramsA.count = 4; c.paramsA.curve = 0; return c }) { $0.cells[1][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 4, into: e)   // column 1 active over [2,4); the f=0 downbeat at 2.0 is mid-block
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 4, "the column-1 burst downbeat must not be dropped")
        assertNothingLeftSounding(e)
    }
    // (testEuclidSpanRowSpreadsPulsesAcrossTheBar removed 2026-08-27 — it tested the retired WIDTH model, where SPAN
    // scaled the euclid speed. The RATE×ladder re-anchor is now covered by testEuclidSpanReAnchorsThePattern.)
    func testLengthSpanRowGatesAcrossTheBar() {
        // SPAN ROW (Paul 2026-08-19): the 8 LENGTH slices span the whole bar (slice i = column i), so a SHORT/MUTE
        // alternation strikes only the even columns → 4 columns × 3 notes = 12 ons/bar. SPAN CELL fits all 8 slices in
        // EACH column → 4 SHORTs × 3 notes × 8 columns = 96. Same slices, different timeline (mirrors the euclid test).
        func rowBox(_ span: PatternSpan) -> SnapshotBox {
            box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .length)
                c.paramsA.lenSlices = [.short, .mute, .short, .mute, .short, .mute, .short, .mute]
                c.paramsA.lenSpan = span; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }   // the LENGTH fills the whole row
            }
        }
        // The window-scan emits the trailing bar/column downbeat at beat 16 too, so each count carries one extra chord
        // strike (+3): ROW = 4 SHORT columns + 1 = 5 × 3 = 15; CELL = 4×8 + 1 = 33 × 3 = 99. The clean counts (12 vs 96)
        // relate as (row−3)×8 == (cell−3) — the SPAN spreads the SAME slices across the bar instead of per column.
        let eRow = RecordingEmitter(); run(rowBox(.row), chord([60, 64, 67]), beats: 16, into: eRow, releaseAtEnd: false)
        let onsRow = eRow.ons.filter { $0.cable == 1 }.count
        let eCell = RecordingEmitter(); run(rowBox(.cell), chord([60, 64, 67]), beats: 16, into: eCell, releaseAtEnd: false)
        let onsCell = eCell.ons.filter { $0.cable == 1 }.count
        XCTAssertEqual(onsRow, 15, "SPAN ROW: the 8-slice gate spans the bar → 4 SHORT columns (+1 boundary) × 3 notes")
        XCTAssertEqual(onsCell, 99, "SPAN CELL: 4 SHORTs × 8 columns (+1 boundary) × 3 — the pattern repeats each column")
        XCTAssertEqual((onsRow - 3) * 8, onsCell - 3, "ROW is the SAME slices spread across the bar, not repeated per column")
        assertNothingLeftSounding(eRow); assertNothingLeftSounding(eCell)
    }
    func testBurstSpanRowUnfoldsAcrossTheBar() {
        // SPAN ROW (Paul 2026-08-19): the accel/decel roll unfolds ONCE across the bar; SPAN CELL re-rolls each column.
        func rowBox(_ span: PatternSpan) -> SnapshotBox {
            box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .burst)
                c.paramsA.count = 4; c.paramsA.curve = 0; c.paramsA.burstSpan = span; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }
            }
        }
        let eRow = RecordingEmitter(); run(rowBox(.row), chord([60, 64, 67]), beats: 16, into: eRow, releaseAtEnd: false)
        let eCell = RecordingEmitter(); run(rowBox(.cell), chord([60, 64, 67]), beats: 16, into: eCell, releaseAtEnd: false)
        let onsRow = eRow.ons.filter { $0.cable == 1 }.count, onsCell = eCell.ons.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(onsRow, 0, "the ROW burst sounds")
        XCTAssertLessThan(onsRow, onsCell, "SPAN ROW unfolds ONE roll across the bar; CELL re-rolls each column")
        assertNothingLeftSounding(eRow); assertNothingLeftSounding(eCell)
    }
    // BURST PATTERN + CARRY (Paul 2026-08-19): in CELL mode the 8 slices subdivide the column; a BURST with contiguous
    // CARRY slices STRETCHES the roll across the wider span → its onsets fan out wider than a lone BURST (1 slice).
    func testBurstPatternCarryStretchesTheRoll() {
        func onsetSpan(_ slices: [BurstSlice]) -> Int64 {
            let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .burst)
                c.paramsA.count = 4; c.paramsA.curve = 0; c.paramsA.burstMode = .pattern; c.paramsA.burstSlices = slices; c.paramsA.burstSpan = .cell; return c }) {
                $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 2, into: e)
            let ons = e.ons.filter { $0.cable == 1 }.map { $0.sample }
            return (ons.max() ?? 0) - (ons.min() ?? 0)
        }
        let carried = onsetSpan([.burst, .carry, .carry, .rest, .rest, .rest, .rest, .rest])   // span 3 slices
        let lone = onsetSpan([.burst, .rest, .rest, .rest, .rest, .rest, .rest, .rest])         // span 1 slice
        XCTAssertGreaterThan(carried, lone, "CARRY stretches the roll → wider onset span than a lone burst")
    }
    func testBurstRateAxisChangesSliceDensity() {
        // BURST RATE AXIS (Paul 2026-08-26): PATTERN divides the span by burstRate (walking the 8-figure) instead of a fixed
        // 8 — a fine rate packs more roll-slices than a coarse one. burstRateOn=false is the legacy fixed-8 (covered above).
        func onsetCount(rateOn: Bool, rate: ArpRate) -> Int {
            let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .burst)
                c.paramsA.count = 2; c.paramsA.curve = 0; c.paramsA.burstMode = .pattern
                c.paramsA.burstSlices = [.burst, .rest, .burst, .rest, .burst, .rest, .burst, .rest]   // 4 launches / 8 slices
                c.paramsA.burstSpan = .row; c.paramsA.burstRateOn = rateOn; c.paramsA.burstRate = rate; return c }) {
                $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 4, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let fine = onsetCount(rateOn: true, rate: .r1_32)
        let coarse = onsetCount(rateOn: true, rate: .r1_4)
        XCTAssertGreaterThan(fine, coarse, "a fine RATE (1/32) packs more roll-slices across the span than a coarse one (1/4)")
        XCTAssertGreaterThan(onsetCount(rateOn: false, rate: .r1_8), 0, "the legacy fixed-8 pattern still fires")
    }
    // BURST COIN (Paul 2026-08-19): a seeded chance-of-burst per step — chance 0 silent, chance 1 every step, monotone.
    func testBurstCoinChanceIsMonotone() {
        func onCount(_ chance: Double) -> Int {
            let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .burst)
                c.paramsA.count = 4; c.paramsA.curve = 0; c.paramsA.burstMode = .coin; c.paramsA.burstChance = chance; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e, releaseAtEnd: false)
            let n = e.ons.filter { $0.cable == 1 }.count; assertNothingLeftSounding(e); return n
        }
        XCTAssertEqual(onCount(0), 0, "chance 0 → no bursts")
        XCTAssertGreaterThan(onCount(1), onCount(0.3), "higher chance → more bursts")
        XCTAssertGreaterThan(onCount(0.3), 0, "some fire at 0.3")
    }
    func testCascadeSpanRowRevealsAcrossTheBar() {
        // SPAN ROW (Paul 2026-08-19): the chord reveals across the whole bar; SPAN CELL re-reveals in each column.
        func rowBox(_ span: PatternSpan) -> SnapshotBox {
            box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .cascade)
                c.paramsA.rate = .r1_8; c.paramsA.cascadeSpan = span; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }
            }
        }
        let eRow = RecordingEmitter(); run(rowBox(.row), chord([60, 64, 67]), beats: 16, into: eRow, releaseAtEnd: false)
        let eCell = RecordingEmitter(); run(rowBox(.cell), chord([60, 64, 67]), beats: 16, into: eCell, releaseAtEnd: false)
        let onsRow = eRow.ons.filter { $0.cable == 1 }.count, onsCell = eCell.ons.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(onsRow, 0, "the ROW cascade sounds")
        XCTAssertLessThan(onsRow, onsCell, "SPAN ROW spreads the reveal across the bar; CELL re-reveals per column")
        assertNothingLeftSounding(eRow); assertNothingLeftSounding(eCell)
    }
    func testTuttiPatternSpanRowSpreadsTheShapeAcrossTheBar() {
        // SPAN ROW (Paul 2026-08-19): the 8-slice set-shape spans the whole bar (slice i = column i); CELL strides it at the RATE.
        func rowBox(_ span: PatternSpan) -> SnapshotBox {
            box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .tutti)
                c.paramsA.tuttiMode = .pattern
                c.paramsA.tuttiSlices = [.all, .rest, .all, .rest, .all, .rest, .all, .rest]
                c.paramsA.tuttiRate = .r1_16; c.paramsA.tuttiSpan = span; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }
            }
        }
        let eRow = RecordingEmitter(); run(rowBox(.row), chord([60, 64, 67]), beats: 16, into: eRow, releaseAtEnd: false)
        let eCell = RecordingEmitter(); run(rowBox(.cell), chord([60, 64, 67]), beats: 16, into: eCell, releaseAtEnd: false)
        let onsRow = eRow.ons.filter { $0.cable == 1 }.count, onsCell = eCell.ons.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(onsRow, 0, "the ROW tutti-pattern sounds")
        XCTAssertLessThan(onsRow, onsCell, "SPAN ROW spreads the 8-slice shape across the bar; CELL strides it at the fast RATE")
        assertNothingLeftSounding(eRow); assertNothingLeftSounding(eCell)
    }
    func testRatchetPatternColumnCountsRatchet() {
        // PATTERN standalone (Paul 2026-09-08): a single-slot ratchet-pattern cell is a PASS-THROUGH processor (emitColumn-
        // RatchetPattern) — count 1 = sustain the held chord, N = ratchet N over the column's RATE slot, 0 = OFF/mute. So an
        // all-1 matrix SUSTAINS (few note-ons) and a high-count matrix RATCHETS (many more). onsRat > onsPass either way.
        func rbox(_ counts: [Int]) -> SnapshotBox {
            box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .ratchet)
                c.paramsA.rtcMode = .pattern; c.paramsA.rtcRate = .r1_16; c.paramsA.rtcSteps = counts.count; c.paramsA.rtcSlices = counts; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }
            }
        }
        let ePass = RecordingEmitter(); run(rbox(Array(repeating: 1, count: 8)), chord([60, 64, 67]), beats: 8, into: ePass, releaseAtEnd: false)
        let eRat  = RecordingEmitter(); run(rbox(Array(repeating: 4, count: 8)), chord([60, 64, 67]), beats: 8, into: eRat, releaseAtEnd: false)
        let onsPass = ePass.ons.filter { $0.cable == 1 }.count, onsRat = eRat.ons.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(onsPass, 0, "an all-passthrough (all-1) pattern sounds one hit per column at RATE")
        XCTAssertGreaterThan(onsRat, onsPass, "higher per-column counts ratchet → more strikes")
        assertNothingLeftSounding(ePass); assertNothingLeftSounding(eRat)
    }
    func testCascadeRevealsEachChordNoteOnce() {
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .cascade)
            c.paramsA.rate = .r1_8; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 3, "the 3-note chord revealed one note at a time")
        assertNothingLeftSounding(e)
    }
    func testCascadePlaysOnlyPopulatedColumnsProportionally() {
        // Ground truth for Paul's "only column N matters" report (2026-08-16): a cascade cell sounds ONLY in its own
        // column (the render row-loop keys on the active column's cells; cascade notes gate to their column boundary,
        // never adopted), so a sparse scene plays proportionally — the whole equals the sum of its columns. No inversion.
        func cascadeCols(_ cols: [Int]) -> SnapshotBox {
            box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .cascade); c.paramsA.rate = .r1_8; return c }) {
                for c in cols { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) }
            }
        }
        func ons(_ cols: [Int]) -> Int {
            let e = RecordingEmitter()
            run(cascadeCols(cols), chord([60, 64, 67]), beats: 8, into: e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let all = ons(Array(0..<8)); let onlyC2 = ons([2]); let allButC2 = ons([0, 1, 3, 4, 5, 6, 7])
        XCTAssertEqual(all, onlyC2 + allButC2, "cascade sounds where the cells are — the whole = the sum of the columns")
        XCTAssertGreaterThan(allButC2, onlyC2, "7 populated columns emit more than 1 — the engine never inverts")
    }
    func testDroneHoldsTheChordAsAPad() {
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .drone)
            c.paramsA.gate = 0.6; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 3, "the chord held once as a pad")
        assertNothingLeftSounding(e)
    }
    func testShiftNudgesTheChordLate() {
        let b = box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .shift)
            c.paramsA.spread = 0.5; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 3, "the chord, nudged late, once")
        assertNothingLeftSounding(e)
    }
    func testHumanizeIsSeededAndReplaySafe() {
        func mk() -> SnapshotBox {
            box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .humanize)
                c.paramsA.spread = 0.8; return c }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        }
        let e1 = RecordingEmitter(); run(mk(), chord([60, 64, 67]), beats: 2, into: e1)
        let e2 = RecordingEmitter(); run(mk(), chord([60, 64, 67]), beats: 2, into: e2)
        XCTAssertEqual(e1.ons.filter { $0.cable == 1 }.count, 3, "each note struck once, humanized")
        XCTAssertEqual(e1.ons.map { $0.note }, e2.ons.map { $0.note }, "seeded → replay-safe (byte-identical)")
        assertNothingLeftSounding(e1)
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
    // ROW 8 FREEZE (Paul 2026-08-22): a lit FREEZE cell SUSTAINS sounding notes + PAUSES derivation (no new notes);
    // unfreezing RELEASES the held notes and resumes. No stuck notes across the whole cycle.
    func testRow8FreezeSustainsPausesThenReleases() {
        func freezeBox(_ on: Bool) -> SnapshotBox {
            var s = SceneState.empty(); s.cells[0][0] = Cell(machineID: "gold", buses: [.a])
            s.row8On = on ? [true, false, false, false, false, false, false, false] : nil
            var st = PluginState(machines: arpMachines(), scenes: [s]); st.busChannels = [1, 2, 3, 4]
            st.row8 = [Row8Cell.make(.freeze)]
            return SnapshotBuilder.build(from: st)
        }
        let live = freezeBox(false), frozen = freezeBox(true)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0, wb = Double(2048) * 120.0 / 60.0 / 48_000.0
        var beat = 0.0, ts = 0.0
        func step(_ b: SnapshotBox, _ pool: NotePool) {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        for _ in 0..<8 { step(live, chord([60, 64, 67])) }            // the arp emits
        let onsAtFreeze = e.ons.count, offsAtFreeze = e.offs.count
        XCTAssertGreaterThan(onsAtFreeze, 0, "the arp is emitting before freeze")
        for _ in 0..<8 { step(frozen, chord([60, 64, 67])) }          // FREEZE — sustain + pause
        XCTAssertEqual(e.ons.count, onsAtFreeze, "FREEZE: no NEW notes while frozen (derivation paused)")
        XCTAssertEqual(e.offs.count, offsAtFreeze, "FREEZE: sounding notes SUSTAIN (no offs while frozen)")
        step(live, chord([60, 64, 67]))                              // UNFREEZE
        XCTAssertGreaterThan(e.offs.count, offsAtFreeze, "UNFREEZE: the sustained notes release")
        router.process(box: live, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)   // stop
        assertNothingLeftSounding(e)
    }

    // ROW 8 HALFTIME (÷2): the play-grid COLUMN clock runs at half speed → over a fixed beat span, half the column
    // boundaries are crossed → half the (distinct-machine) drone re-strikes. ×1/none is byte-identical.
    func testRow8HalftimeSlowsTheColumnClock() {
        func onsOver8Beats(halftime: Bool) -> Int {
            var cs: [Machine] = []
            for (c, id) in machineIDs.enumerated() { var col = Machine(machineID: id, type: .drone); col.transpose = c; cs.append(col) }
            var s = SceneState.empty()
            for c in 0..<8 { s.cells[c][0] = Cell(machineID: machineIDs[c], buses: [.a]) }   // a distinct-note drone per column
            if halftime { s.row8On = [true, false, false, false, false, false, false, false] }
            var st = PluginState(machines: cs, scenes: [s]); st.busChannels = [1, 2, 3, 4]
            if halftime { st.row8 = [Row8Cell.make(.halftime)] }     // ÷2 ⇒ clockScale 2.0
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord([60]), beats: 8, into: e)
            return e.ons.count
        }
        let normal = onsOver8Beats(halftime: false), half = onsOver8Beats(halftime: true)
        XCTAssertGreaterThan(normal, 1)
        XCTAssertLessThan(half, normal, "HALFTIME ÷2 crosses half the column boundaries → fewer re-strikes")
    }

    // ROW 8 REDIRECT (A→B) / SWAP (A↔B): while active, an emitter's OUTPUT stream is re-stamped onto another wire
    // (cable + channel). The note stores its actual stamp, so nothing is stranded.
    func testRow8RedirectAndSwapRestampTheWire() {
        func rowBox(_ cell: Row8Cell, cellBus: Bus) -> SnapshotBox {
            var s = SceneState.empty(); s.cells[0][0] = Cell(machineID: "gold", buses: [cellBus])
            s.row8On = [true, false, false, false, false, false, false, false]
            var st = PluginState(machines: arpMachines(), scenes: [s]); st.busChannels = [1, 2, 3, 4]
            st.row8 = [cell]
            return SnapshotBuilder.build(from: st)
        }
        // REDIRECT A→B: emitter A's note comes out on B's cable (2), not A's (1)
        var redir = Row8Cell.make(.redirect); redir.wireFrom = 0; redir.wireTo = 1
        let e1 = RecordingEmitter(); run(rowBox(redir, cellBus: .a), chord([60]), beats: 4, into: e1)
        XCTAssertTrue(e1.ons.contains { $0.note == 60 && $0.cable == 2 }, "A's note redirected onto B's cable")
        XCTAssertFalse(e1.ons.contains { $0.note == 60 && $0.cable == 1 }, "…and NOT on A's own cable")
        assertNothingLeftSounding(e1)
        // SWAP A↔B: an A-cell note lands on B's cable (and a B-cell note would land on A's)
        var sw = Row8Cell.make(.swap); sw.wireFrom = 0; sw.wireTo = 1
        let e2 = RecordingEmitter(); run(rowBox(sw, cellBus: .a), chord([60]), beats: 4, into: e2)
        XCTAssertTrue(e2.ons.contains { $0.note == 60 && $0.cable == 2 }, "SWAP sends A's stream to B's cable")
        assertNothingLeftSounding(e2)
    }

    // ROW 8 BROADCAST: the WALL — a lit BROADCAST cell mirrors every emitted note to all 4 emitter wires. No stuck notes.
    func testRow8BroadcastMirrorsToAllWires() {
        var s = SceneState.empty(); s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // the cell emits on A only
        s.row8On = [true, false, false, false, false, false, false, false]
        var st = PluginState(machines: arpMachines(), scenes: [s]); st.busChannels = [1, 2, 3, 4]
        st.row8 = [Row8Cell.make(.broadcast)]
        let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord([60]), beats: 4, into: e)
        for cable: UInt8 in 1...4 {
            XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == cable }, "BROADCAST mirrors the note to wire \(cable)")
        }
        XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == 0 }, "…and the ALL cable")
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
    func testEveryArticulationEmitsOnItsBusCableAndTheAllCable() {
        // delta §7b: each articulation emits on its own bus cable (A = cable 1) AND the ALL cable (0),
        // and on NO other cable (only bus A is lit).
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        let onCable0 = e.ons.filter { $0.cable == 0 }.count
        let onCable1 = e.ons.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(onCable1, 0)
        XCTAssertEqual(onCable0, onCable1, "each artic emits once on ALL and once on its bus cable")
        XCTAssertTrue(e.ons.allSatisfy { $0.cable == 0 || $0.cable == 1 }, "no emission on unlit bus cables")
    }

    func testBusChannelIsStampedAtExit() {
        // delta §7: channel is a property of the wire. Stamp bus A with channel 5 → wire channel 4.
        let b = box(machines: arpMachines(), busChannels: [5, 2, 3, 4]) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.events.count, 0)
        XCTAssertTrue(e.events.allSatisfy { $0.chan == 4 }, "every message carries the bus-A stamp (5 → wire 4)")
        assertNothingLeftSounding(e)
    }

    func testMutedCellEmitsNothing() {
        var cell = Cell(machineID: "gold"); cell.muted = true
        let b = box(machines: arpMachines()) { $0.cells[0][0] = cell }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.events.isEmpty, "a muted cell (§6.2) produces no MIDI on any cable")
    }

    func testMutingMidPlaybackSilencesCellWithoutStuckNotes() {
        // DEFAULT GRID TAP = MUTE (2026-08-01): muting a SOUNDING cell mid-playback must (a) stop its emitter
        // output and (b) leave no hung note. Simulate the tap by swapping to a snapshot with the cell muted.
        let live = box(machines: arpMachines()) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) } }
        let mb   = box(machines: arpMachines()) { for c in 0..<8 { $0.cells[c][0] = { var cell = Cell(machineID: "gold", buses: [.a]); cell.muted = true; return cell }() } }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func win(_ b: SnapshotBox) {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        for _ in 0..<60 { win(live) }                       // sounding
        XCTAssertGreaterThan(e.ons.count, 0, "the cell sounded before muting")
        let onsAtMute = e.ons.count
        for _ in 0..<60 { win(mb) }                          // TAP → muted snapshot
        XCTAssertEqual(e.ons.count, onsAtMute, "a muted cell emits NO new note-ons")
        router.process(box: mb, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)   // stop
        assertNothingLeftSounding(e)                          // invariant 4: the muted cell's voice closed cleanly
    }

    func testFanOutEmitsOnBothLitBusesPlusAll() {
        // Buses A and B both lit → each artic emits on cable 1 (A), cable 2 (B) and cable 0 (ALL).
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        let c1 = e.ons.filter { $0.cable == 1 }.count
        let c2 = e.ons.filter { $0.cable == 2 }.count
        let c0 = e.ons.filter { $0.cable == 0 }.count
        XCTAssertGreaterThan(c1, 0)
        XCTAssertEqual(c1, c2, "both lit buses articulate equally")
        XCTAssertEqual(c0, c1 + c2, "ALL carries one copy per (bus × artic)")
        assertNothingLeftSounding(e)
    }

    // MARK: audition (§6.4 / delta §5)

    /// Drive `windows` STOPPED render windows holding `target` (col*8+row), then optionally release
    /// (target → −1). Audition's phase clock is driven by the advancing sample timestamp, not beatPos.
    private func auditionRun(_ box: SnapshotBox, _ pool: NotePool, target: Int, windows: Int,
                             into emitter: RecordingEmitter, releaseAtEnd: Bool = true,
                             tempo: Double = 120, sr: Double = 48_000, frames: UInt32 = 2048) {
        let router = Router()
        var diag = KernelDiag()
        var ts = 0.0
        for _ in 0..<windows {
            router.process(box: box, pool: pool, playing: false, beatPos: 0, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, audition: target, out: emitter, diag: &diag)
            ts += Double(frames)
        }
        if releaseAtEnd {
            router.process(box: box, pool: pool, playing: false, beatPos: 0, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, audition: -1, out: emitter, diag: &diag)
        }
    }

    func testAuditionArpSoundsWhileStoppedAndLeavesNothingStuck() {
        // Hold an ARP cell (col 0, row 0) with a chord held, transport STOPPED → it arpeggiates.
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, chord([60, 64, 67]), target: 0, windows: 24, into: e)   // 0 = col0*8+row0
        XCTAssertGreaterThan(e.ons.count, 0, "a held ARP should sound while stopped (audition)")
        assertNothingLeftSounding(e)
    }

    func testAuditionWithNoHeldNotesIsSilent() {
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, NotePool(), target: 0, windows: 12, into: e)            // no keys held
        XCTAssertTrue(e.events.isEmpty, "audition soundcheck is silent with no source notes")
    }

    func testAuditionOfEmptyCellIsSilent() {
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, chord([60, 64, 67]), target: 5 * 8 + 5, windows: 12, into: e)   // (col5,row5) empty
        XCTAssertTrue(e.events.isEmpty, "auditioning an empty cell produces nothing")
    }

    func testAuditionRatchetSounds() {
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .ratchet
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, chord([60, 63, 67]), target: 0, windows: 24, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "a held RATCHET re-strikes the chord while stopped")
        assertNothingLeftSounding(e)
    }

    func testAuditionEmitsOnTheCellsBusAndAllCable() {
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.b]) }
        let e = RecordingEmitter()
        auditionRun(b, chord([60, 64, 67]), target: 0, windows: 24, into: e)
        XCTAssertTrue(e.ons.contains { $0.cable == 2 }, "audition emits on the lit bus (B = cable 2)")
        XCTAssertTrue(e.ons.contains { $0.cable == 0 }, "audition also emits on the ALL cable")
        XCTAssertTrue(e.ons.allSatisfy { $0.cable == 0 || $0.cable == 2 }, "no emission on unlit buses")
    }

    func testTransportStartAutoReleasesAudition() {
        // Hold an ARP audition, then start the transport: the transport-start edge must flush the
        // audition voices (auto-release, §6.4) — nothing left sounding after a stop.
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        let router = Router(); var diag = KernelDiag()
        let pool = chord([60, 64, 67]); let sr = 48_000.0; let frames: UInt32 = 2048
        var ts = 0.0
        for _ in 0..<10 {   // stopped + auditioning
            router.process(box: b, pool: pool, playing: false, beatPos: 0, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, audition: 0, out: e, diag: &diag); ts += Double(frames)
        }
        XCTAssertGreaterThan(e.ons.count, 0)
        // transport starts; audition target cleared as the UI would on auto-release
        var beat = 0.0
        for _ in 0..<40 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, audition: -1, out: e, diag: &diag)
            ts += Double(frames); beat += Double(frames) * 120 / 60 / sr
        }
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, audition: -1, out: e, diag: &diag)   // stop → flush
        assertNothingLeftSounding(e)
    }

    func testAuditionHarmonizeExpandsAndSustains() {
        // Chord-hold audition (v2): HARMONIZE previews the added voices, and sustains — each note is
        // struck ONCE and held (not re-articulated every window).
        var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
        cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = [4, 7, 0]   // +4, +7, third off
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, chord([60]), target: 0, windows: 20, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 0 }.map { $0.note }), [60, 64, 67], "root + intervals")
        XCTAssertEqual(e.ons.filter { $0.cable == 0 }.count, 3, "sustained — each note struck once, not per window")
        assertNothingLeftSounding(e)
    }

    func testAuditionChancePassesAllAtOneAndNoneAtZero() {
        var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
        cs[gi].type = .chance
        cs[gi].paramsA.probability = 1.0
        let bAll = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold") }
        let eAll = RecordingEmitter()
        auditionRun(bAll, chord([60, 64, 67]), target: 0, windows: 12, into: eAll)
        XCTAssertEqual(Set(eAll.ons.filter { $0.cable == 0 }.map { $0.note }), [60, 64, 67], "p=1 sustains the whole chord")
        assertNothingLeftSounding(eAll)

        cs[gi].paramsA.probability = 0.0
        let bNone = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold") }
        let eNone = RecordingEmitter()
        auditionRun(bNone, chord([60, 64, 67]), target: 0, windows: 12, into: eNone)
        XCTAssertTrue(eNone.events.isEmpty, "p=0 auditions to silence (processor drops everything)")
    }

    func testAuditionChordHoldTracksHeldKeysLive() {
        // The sustained preview must FOLLOW the keys: add one mid-hold → it sounds; release one → it
        // stops, while the rest keep sounding. (an identity hold — nothing gates it.)
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .empty
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        let router = Router(); var diag = KernelDiag()
        let pool = NotePool(); let sr = 48_000.0; let frames: UInt32 = 2048
        var ts = 0.0
        func win() {
            router.process(box: b, pool: pool, playing: false, beatPos: 0, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, audition: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        pool.noteOn(60, velocity: 100, channel: 0); win(); win()
        XCTAssertTrue(e.ons.contains { $0.note == 60 }, "held key sounds")
        pool.noteOn(64, velocity: 100, channel: 0); win(); win()
        XCTAssertTrue(e.ons.contains { $0.note == 64 }, "a key added mid-hold sounds")
        pool.noteOff(60); win(); win()
        XCTAssertTrue(e.offs.contains { $0.note == 60 }, "a key released mid-hold stops")
        router.process(box: b, pool: pool, playing: false, beatPos: 0, tempo: 120, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, audition: -1, out: e, diag: &diag)   // release
        assertNothingLeftSounding(e)
    }

    func testAuditionStrumRollsTheChordInThenSustains() {
        // STRUM audition ROLLS the chord in over `spread` (not all at once), then sustains.
        var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
        cs[gi].type = .strum; cs[gi].paramsA.spread = 0.4   // wide roll → spans several windows
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        let router = Router(); var diag = KernelDiag()
        let pool = chord([60, 64, 67]); let sr = 48_000.0; let frames: UInt32 = 2048
        var ts = 0.0
        func win() {
            router.process(box: b, pool: pool, playing: false, beatPos: 0, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, audition: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        win()
        XCTAssertLessThan(Set(e.ons.filter { $0.cable == 0 }.map { $0.note }).count, 3,
                          "the chord rolls in — not every note sounds on the first window")
        for _ in 0..<30 { win() }
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 0 }.map { $0.note }), [60, 64, 67], "all notes have rolled in")
        router.process(box: b, pool: pool, playing: false, beatPos: 0, tempo: 120, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, audition: -1, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

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

    func testAllIsTheSumOfEnabledEmitters() {
        // Fan-out to A and B; disable A → A silent, B sounds, All carries only B's stream.
        let b = box(machines: arpMachines(), busEnabled: [false, true, true, true]) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "A disabled → nothing on cable 1")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "B still sounds on cable 2")
        let onAll = e.ons.filter { $0.cable == 0 }.count
        XCTAssertEqual(onAll, e.ons.filter { $0.cable == 2 }.count, "All carries exactly the enabled (B) stream")
        assertNothingLeftSounding(e)
    }

    func testDisablingMidStreamClosesThatEmittersNotes() {
        // Play A a while, then disable it live; its cable-1 notes close and nothing is stuck.
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold") }   // bus A
        let e = RecordingEmitter()
        let router = Router(); var diag = KernelDiag()
        let pool = chord([60]); let sr = 48_000.0; let frames: UInt32 = 2048
        let wb = Double(frames) * 120 / 60 / sr
        var beat = 0.0, ts = 0.0
        let boxOff = box(machines: arpMachines(), busEnabled: [false, true, true, true]) { $0.cells[0][0] = Cell(machineID: "gold") }
        for i in 0..<24 {   // first 8 windows A enabled, then disabled
            router.process(box: i < 8 ? b : boxOff, pool: pool, playing: true, beatPos: beat, tempo: 120,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: boxOff, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "A sounded before it was disabled")
        assertNothingLeftSounding(e)
    }

    func testSharedChannelSurvivesOnAllWhenOneOwnerDisabled() {
        // A and B on the SAME stamp channel, fanned from one cell; disable A → All keeps the note (B owns it).
        var st = PluginState(machines: arpMachines(), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b]); return s }()])
        st.busChannels = [3, 3, 3, 4]              // A and B both stamp channel 3
        st.busEnabled = [false, true, true, true]  // A disabled
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 0 && $0.chan == 2 }.count, 0,
                             "All still carries the shared-channel note via B (wire ch 2 = stamp 3)")
        assertNothingLeftSounding(e)
    }

    func testMeteringFeedReportsPerEmitterPeakAndEventsThenClears() {
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .ratchet
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold") }   // bus A only
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let sr = 48_000.0; let frames: UInt32 = 2048
        var beat = 0.0, ts = 0.0; let wb = Double(frames) * 120 / 60 / sr
        for _ in 0..<12 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let m = router.drainMeters()
        XCTAssertGreaterThan(m.events[0], 0, "emitter A metered events")
        XCTAssertGreaterThan(m.peak[0], 0, "emitter A metered a peak velocity")
        XCTAssertEqual([m.events[1], m.events[2], m.events[3]], [0, 0, 0], "silent emitters meter nothing")
        XCTAssertEqual(router.drainMeters().events[0], 0, "drain read-and-clears")
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

    func testEmitterSoundingReportsHeldNoteOnItsBusThenClearsOnRelease() {
        // A ratchet on the GOLD cell → bus A. While a chord is held, at least one window snapshot must catch a
        // sounding voice on emitter A (carrying its velocity + source machineIndex) and NONE on B/C/D; after the
        // chord releases and the notes close, every emitter's sounding set empties.
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .ratchet
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let held = chord([60]); let sr = 48_000.0; let frames: UInt32 = 2048
        var beat = 0.0, ts = 0.0; let wb = Double(frames) * 120 / 60 / sr
        var sawSounding = false
        for _ in 0..<24 {
            router.process(box: b, pool: held, playing: true, beatPos: beat, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            router.snapshotEmitterSounding()
            let s = router.drainEmitterSounding()
            if !s[0].isEmpty {
                sawSounding = true
                XCTAssertEqual([s[1].count, s[2].count, s[3].count], [0, 0, 0], "only emitter A sounds")
                XCTAssertGreaterThan(s[0].first!.vel, 0, "the sounding note carries its velocity")
                XCTAssertGreaterThanOrEqual(s[0].first!.col, 0, "…and its source machine (cargo tint)")
            }
            beat += wb; ts += Double(frames)
        }
        XCTAssertTrue(sawSounding, "emitter A reported a sounding note while the chord was held")
        let empty = NotePool()   // release: no held notes → the ratchet stops → voices close
        for _ in 0..<8 {
            router.process(box: b, pool: empty, playing: true, beatPos: beat, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.snapshotEmitterSounding()
        XCTAssertTrue(router.drainEmitterSounding().allSatisfy { $0.isEmpty }, "released → nothing left sounding")
    }

    // MARK: - item 4 VELOCITY MARKS — the per-note (velocity, source-machine) ring drained by drainMarks()

    func testDrainMarksStampsSourceMachineAndReadClears() {
        // An arp on the GOLD cell (machineIndex 0) → bus A. Each note-on leaves a mark carrying its velocity
        // and the emitting cell's machineIndex — the source tint the strip meter draws.
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let sr = 48_000.0; let frames: UInt32 = 2048
        var beat = 0.0, ts = 0.0; let wb = Double(frames) * 120 / 60 / sr
        for _ in 0..<8 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let m = router.drainMarks()
        XCTAssertFalse(m[0].isEmpty, "bus A collected velocity marks")
        XCTAssertTrue(m[0].allSatisfy { $0.col == 0 }, "each mark is tinted by the source Machine (gold = index 0)")
        XCTAssertTrue(m[0].allSatisfy { $0.vel > 0 }, "each mark carries the note-on velocity")
        XCTAssertEqual([m[1].count, m[2].count, m[3].count], [0, 0, 0], "silent emitters collect no marks")
        XCTAssertTrue(router.drainMarks()[0].isEmpty, "drain read-and-clears")
    }

    func testDrainMarksFansSameTintToEveryBus() {
        // A cell fanning to A+B stamps the SAME source machineIndex on both buses' marks.
        let wine = Int8(machineIDs.firstIndex(of: "wine")!)
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "wine", buses: [.a, .b]) }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let sr = 48_000.0; let frames: UInt32 = 2048
        var beat = 0.0, ts = 0.0; let wb = Double(frames) * 120 / 60 / sr
        for _ in 0..<8 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let m = router.drainMarks()
        XCTAssertFalse(m[0].isEmpty || m[1].isEmpty, "both A and B collected marks")
        XCTAssertTrue((m[0] + m[1]).allSatisfy { $0.col == wine }, "every fanned mark shares the source tint")
    }

    func testDrainMarksRingCapsAtEight() {
        // An arp of a chord floods bus A with note-ons over many beats; the per-emitter ring saturates at 8
        // marks per drain (drainMarks is called ONCE at the end, so all note-ons since start accumulate).
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let sr = 48_000.0; let frames: UInt32 = 2048
        var beat = 0.0, ts = 0.0; let wb = Double(frames) * 120 / 60 / sr
        for _ in 0..<200 {                                   // ~17 beats — well over a ring's worth of arp steps
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 8, "the arp emitted more than a ring's worth")
        XCTAssertEqual(router.drainMarks()[0].count, 8, "…but the mark ring saturates at 8 per emitter")
    }

    func testAuditionRespectsDisabledEmitter() {
        // Cross-feature: audition a cell routed to a DISABLED emitter (B) → silent (the §6a gate is at
        // the emission boundary, so audition respects it too).
        let b = box(machines: arpMachines(), busEnabled: [true, false, true, true]) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.b])
        }
        let e = RecordingEmitter()
        auditionRun(b, chord([60]), target: 0, windows: 12, into: e)
        XCTAssertTrue(e.events.isEmpty, "audition of a cell routed to a disabled emitter is silent")
    }

    // MARK: - VELOCITY OVERRIDE (§6a PERFORM) — momentary per-emitter flatten at the emission boundary

    /// Drive PLAYING windows with a packed velOverride (byte-per-emitter), then a STOP flush.
    private func runVel(_ box: SnapshotBox, _ pool: NotePool, beats: Double, velOverride: UInt32,
                        into e: RecordingEmitter, tempo: Double = 120, sr: Double = 48_000, frames: UInt32 = 2048) {
        let router = Router(); var diag = KernelDiag()
        let wb = Double(frames) * tempo / 60 / sr
        var beat = 0.0, ts = 0.0
        while beat < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, velOverride: velOverride, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
    }

    /// Pack a single emitter's override into the byte-per-emitter word the engine reads.
    private func packVel(_ bus: Int, _ value: Int) -> UInt32 { UInt32(value & 0xFF) << (UInt32(bus) * 8) }

    func testVelocityOverrideFlattensEveryNoteOnOnThatEmitter() {
        // Override emitter A to 40: every new note-on on its own cable (1) AND its All copy (0) is exactly 40.
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold") }   // bus A
        let e = RecordingEmitter()
        runVel(b, chord([60, 64, 67]), beats: 16, velOverride: packVel(0, 40), into: e)
        let aOns = e.ons.filter { $0.cable == 1 }
        let allOns = e.ons.filter { $0.cable == 0 }
        XCTAssertGreaterThan(aOns.count, 0, "the emitter sounded")
        XCTAssertTrue(aOns.allSatisfy { $0.vel == 40 }, "every A note-on is flattened to the override value")
        XCTAssertTrue(allOns.allSatisfy { $0.vel == 40 }, "the All copy carries the same overridden velocity")
        assertNothingLeftSounding(e)
    }

    func testVelocityOverrideOnOneEmitterLeavesOthersNatural() {
        // Fan-out A + B, override A only: A flattens to 40; B keeps its natural (un-flattened) velocity.
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b]) }
        let e = RecordingEmitter()
        runVel(b, chord([60, 64, 67]), beats: 16, velOverride: packVel(0, 40), into: e)
        let aOns = e.ons.filter { $0.cable == 1 }
        let bOns = e.ons.filter { $0.cable == 2 }
        XCTAssertGreaterThan(bOns.count, 0, "B sounded")
        XCTAssertTrue(aOns.allSatisfy { $0.vel == 40 }, "A is overridden")
        XCTAssertTrue(bOns.allSatisfy { $0.vel != 40 }, "B is untouched — natural velocity, not the override")
        assertNothingLeftSounding(e)
    }

    func testZeroOverrideUsesNaturalVelocity() {
        // A 0 byte = untouched: the emitter sounds at its natural velocity (whatever the arp derives), NOT 0.
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        runVel(b, chord([60]), beats: 16, velOverride: 0, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "sounded")
        XCTAssertTrue(e.ons.allSatisfy { $0.vel > 0 }, "no override ⇒ natural velocity, never a zeroed note-on")
    }

    func testVelocityOverrideOnDisabledEmitterStaysSilent() {
        // The enable gate wins: overriding a DISABLED emitter still emits nothing (override is applied after it).
        let b = box(machines: arpMachines(), busEnabled: [true, false, true, true]) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.b])
        }
        let e = RecordingEmitter()
        runVel(b, chord([60]), beats: 16, velOverride: packVel(1, 40), into: e)
        XCTAssertTrue(e.events.isEmpty, "a disabled emitter produces nothing even with an override set")
    }

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

    func testMachineIndexBeyondOverrideTableDoesNotTrapRender() {
        // Paul 2026-08-15 crash (SIGTRAP adding a 2nd flattened part): the render-side override table is sized for the
        // 16 host-automatable machines (transpose at slot 2+i), but the unlimited-ephemeral-machines model can place a
        // cell whose machine index ≥33, so over(2+ci) read PAST the table end → out-of-bounds trap on the render thread.
        // A machine beyond the 16 automatable slots has no param override → it must fall back to its own transpose.
        var machines = machineIDs.map { Machine(machineID: $0, type: .arp) }        // the canonical 16
        for i in 0..<24 { machines.append(holdMachine("x\(i)", transpose: 0)) }   // 40 total → last index 39 ≫ 33
        machines[machines.count - 1].transpose = 7                                 // the high-index machine transposes +7
        let hi = machines[machines.count - 1].machineID
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: hi, buses: [.a])
        let box = SnapshotBuilder.build(from: PluginState(machines: machines, scenes: [s]))
        let e = RecordingEmitter()
        run(box, chord([60]), beats: 4, into: e)                                // must not trap
        XCTAssertTrue(e.events.contains { $0.status == 0x90 && $0.note == 67 }, "the high-index machine holds 60 transposed to 67, using its own transpose")
        assertNothingLeftSounding(e)
    }

    func testClaimSuppressesSamePitchOnNonClaimant() {
        // One cell fans A+B; A claims. Within the articulation A opens 60 first, so B yields it: nothing
        // on cable 2, and All (cable 0) carries A's copy only.
        let b = claimBox(claimMachines(transposeB: 0), claim: 0) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "the claimant (A) sounds the pitch")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 }.isEmpty, "B yields the claimed pitch — silent on its own cable")
        let allA = e.ons.filter { $0.cable == 0 }
        XCTAssertGreaterThan(allA.count, 0, "All carries the claimant's copy")
        assertNothingLeftSounding(e)
    }

    func testClaimResidueSoundsOnNonClaimantForUnclaimedPitch() {
        // Same column, two rows: A holds 60, B holds 65 (transpose +5). A claims — 65 is NOT sounding on
        // A, so B keeps it (the residue passes through). Both cells emit when column 0 is active.
        let b = claimBox(claimMachines(transposeB: 5), claim: 0) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // col 0, row 0 → held 60 on A
            $0.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // col 0, row 1 → held 65 on B (the residue)
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "A holds 60")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 && $0.note == 65 }.count, 0, "B keeps 65 — the claimant isn't sounding it")
        assertNothingLeftSounding(e)
    }

    func testClaimSuppressesSamePitchClassAcrossOctaves() {
        // delta §6a pitch-class match: A holds 60 (C3); B holds 72 (C4, transpose +12) — the SAME pitch class,
        // a different MIDI note. A claims → B's octave-double is suppressed (the claimant owns its harmony;
        // octave doubling across synths is the mud exclusivity exists to prevent).
        let b = claimBox(claimMachines(transposeB: 12), claim: 0) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // held 60 (C3) on A — the claimant
            $0.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // held 72 (C4) on B — same class, one octave up
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "A holds C3")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 && $0.note == 72 }.isEmpty, "B yields C4 — same pitch class as the claimed C3")
        assertNothingLeftSounding(e)
    }

    func testClaimSuppressesResidueWhenClaimantHoldsSamePitch() {
        // Both hold 60 (B transpose 0), claimant A is at row 0 (≤ the spillover row → emits first in the
        // column): B's 60 is suppressed. This is the row-order-dependent case the plan accepts.
        let b = claimBox(claimMachines(transposeB: 0), claim: 0) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // col 0, row 0 — claimant, emits first
            $0.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // col 0, row 1 — spillover
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "A holds 60")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 && $0.note == 60 }.isEmpty, "B yields 60 to the claimant")
        assertNothingLeftSounding(e)
    }

    func testNoClaimLetsBothEmittersSoundTheSamePitch() {
        // Control: with no claim, the same fan-out sounds the pitch on BOTH cables (§7 refcount, not exclusivity).
        let b = claimBox(claimMachines(transposeB: 0), claim: nil) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "A sounds")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "B sounds too — no claim, no suppression")
        assertNothingLeftSounding(e)
    }

    func testClaimSuppressesFanoutOnFastArpRegardlessOfRate() {
        // Regression (device report: claim heard at 1/4 but not faster). A single arp cell fans A+B and A
        // claims. Because the claimant is part of the SAME articulation, B yields on EVERY tick — even at
        // 1/32 where the note opens and closes inside one render window (the old bug: the claimant's voice
        // was immediately closed before B checked the table). B must be silent on its own cable throughout.
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!].paramsA.rate = .r1_32   // fast — note fits inside a window
        let b = claimBox(cs, claim: 0) {
            for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a, .b]) }
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "claimant A sounds")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 }.isEmpty, "B yields to the claimant on every tick, even fast")
        assertNothingLeftSounding(e)
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

    func testMutedNonClaimantIsUnaffected() {
        // Control: muting a NON-claimant is just a mute — B silent, A (claimant) sounds normally.
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
            return s }()])
        st.claimEmitter = 0
        st.busEnabled = [true, false, true, true]                 // B muted (non-claimant)
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "claimant A sounds")
        XCTAssertTrue(e.events.filter { $0.cable == 2 }.isEmpty, "muted non-claimant B is silent")
        assertNothingLeftSounding(e)
    }

    func testClaimSuppressesCrossCellShortNoteAtFastRate() {
        // H1 regression (the device bug): TWO separate cells (not one fan-out) — claimant A arps to Emit
        // A at row 0, a second cell arps the SAME pitch to Emit B at row 1 — at 1/32, where each note
        // opens+closes inside one render window. The persistent claim ghost keeps A's ownership visible
        // across cells, so B yields 60 on every tick. (Before the ghost fix this failed at fast rates
        // because A's audible voice was immediate-closed before B's row was evaluated.)
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!].paramsA.rate = .r1_32
        cs[machineIDs.firstIndex(of: "cyan")!].paramsA.rate = .r1_32
        let b = claimBox(cs, claim: 0) {
            for c in 0..<8 {
                $0.cells[c][0] = Cell(machineID: "gold", buses: [.a])   // row 0 — claimant, Emit A
                $0.cells[c][1] = Cell(machineID: "cyan", buses: [.b])   // row 1 — Emit B, same pitch
            }
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "claimant A sounds 60")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 && $0.note == 60 }.isEmpty,
                      "B yields 60 to the claimant across cells, even at a fast rate (H1)")
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

    func testClaimIsRadioAcrossASwitchWithNoStuckNotes() {
        // Radio: an arp fans A+B (re-articulates every tick). Claim A for a stretch, then switch the claim
        // to B live. Claimant-first emission means each phase suppresses the OTHER emitter's copy, so both
        // cables sound over the run; the switch (the single claimEmitter field implicitly releases the
        // prior) leaves nothing stuck.
        let cs = arpMachines()
        // Fill row 0 across every column so the arp fires whichever column is active in each phase.
        let claimA = claimBox(cs, claim: 0) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a, .b]) } }
        let claimB = claimBox(cs, claim: 1) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a, .b]) } }
        let e = RecordingEmitter()
        let router = Router(); var diag = KernelDiag()
        let pool = chord([60]); let sr = 48_000.0; let frames: UInt32 = 2048
        var beat = 0.0, ts = 0.0; let wb = Double(frames) * 120 / 60 / sr
        for i in 0..<48 {                 // first half claim A, then claim B
            router.process(box: i < 24 ? claimA : claimB, pool: pool, playing: true, beatPos: beat, tempo: 120,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: claimB, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "A sounded during the claim-A phase")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "B sounded during the claim-B phase")
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

    func testMultiClaimSuppressesNonClaimantsAcrossTheUnion() {
        // A and B both claim (SHARED tier). One cell fans A+B+C. C yields the pitch class (owned by the
        // union), but A and B BOTH sound it — claimants never suppress each other (deliberate doubling).
        let b = claimMaskBox(claimMachines(transposeB: 0), mask: 0b0011) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b, .c])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "A (claimant) sounds")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 && $0.note == 60 }.count, 0, "B (claimant) also sounds — claimants double")
        XCTAssertTrue(e.ons.filter { $0.cable == 3 }.isEmpty, "C (non-claimant) yields the claimed class")
        assertNothingLeftSounding(e)
    }

    func testClaimLeakBleedsNonClaimantAtScaledVelocity() {
        // A claims with LEAK 50 %. B (non-claimant) fanned the same pitch now SOUNDS at half velocity — the
        // shadow — instead of falling silent. Source velocity is 100 (the `chord` helper) → 50.
        let b = claimMaskBox(claimMachines(transposeB: 0), mask: 0b0001, leak: [50, 0, 0, 0]) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        let aVel = Int(e.ons.first { $0.cable == 1 && $0.note == 60 }!.vel)   // the claimant's (un-leaked) velocity
        let bOns = e.ons.filter { $0.cable == 2 && $0.note == 60 }
        XCTAssertGreaterThan(bOns.count, 0, "B bleeds through (LEAK 50 % > 0)")
        XCTAssertTrue(bOns.allSatisfy { Int($0.vel) == aVel * 50 / 100 }, "B sounds at half the claimant velocity (the shadow)")
        assertNothingLeftSounding(e)
    }

    func testMultiClaimLeakTakesTheStrictestShadow() {
        // A leaks 60 %, B leaks 20 %; both claim the same class. A non-claimant C bleeds at the MIN (20 %) —
        // the strictest claimant's shadow wins.
        let b = claimMaskBox(claimMachines(transposeB: 0), mask: 0b0011, leak: [60, 20, 0, 0]) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b, .c])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        let aVel = Int(e.ons.first { $0.cable == 1 && $0.note == 60 }!.vel)   // a claimant's (un-leaked) velocity
        let cOns = e.ons.filter { $0.cable == 3 && $0.note == 60 }
        XCTAssertGreaterThan(cOns.count, 0, "C bleeds (both leaks > 0)")
        XCTAssertTrue(cOns.allSatisfy { Int($0.vel) == aVel * 20 / 100 }, "C bleeds at the MIN leak (20 %), not 60 % — strictest wins")
        assertNothingLeftSounding(e)
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

    func testRackOffMakesClaimantARawWire() {
        // A claims (matrix armed) but A's RACK is OFF (bit 0 clear) → the board is out of the signal path, so A's
        // claim does NOT apply: a cell fanning A+B lets B keep the pitch (the raw wire, as if nothing were armed).
        let b = rackClaimBox(claimMachines(transposeB: 0), claim: 0b0001, rack: 0b1110) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "A still sounds (LIVE, not RACK, silences)")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 && $0.note == 60 }.count, 0, "B keeps the pitch — A's rack is out of path, so no claim")
        assertNothingLeftSounding(e)
    }

    func testRackOnKeepsClaimSuppression() {
        // Same doc but A's RACK ON (all bits set) → claim applies exactly as before: B yields the claimed pitch.
        let b = rackClaimBox(claimMachines(transposeB: 0), claim: 0b0001, rack: 0b1111) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "A (claimant) sounds")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 }.isEmpty, "B yields — rack in path, claim applies")
        assertNothingLeftSounding(e)
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

    func testWithheldTellRecordsClaimSuppressedNotes() {
        // CLAIM (leak 0) fully suppresses B → drainWithheld reports B's note, tinted by the source Machine
        // (gold = 0); the claimant A withholds nothing (it sounds).
        let b = claimMaskBox(claimMachines(transposeB: 0), mask: 0b0001) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a, .b])
        }
        let wh = drainWithheldAfter(b)
        XCTAssertFalse(wh[1].isEmpty, "B's CLAIM-suppressed note is recorded as withheld")
        XCTAssertTrue(wh[1].allSatisfy { $0.col == 0 }, "the withheld mark carries the source Machine (gold = 0)")
        XCTAssertTrue(wh[0].isEmpty, "the claimant (A) withholds nothing — it sounds")
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

    func testCollisionRefcountKeepsSustainedNoteAliveThroughArpRestrikes() {
        // §7 collision policy + WIRE ARTICULATION = RESTRIKE (user 2026-08-09): an identity hold and a same-pitch ARP
        // on the SAME bus + channel. The arp re-strikes 60 every tick; each strike is now a clean OFF→ON re-attack
        // (retriggering), so ons and offs pace together. The refcount still keeps the hold alive across the strikes
        // (it never hits 0 mid-column) and pairs the final release exactly — nothing stuck.
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!] = holdMachine("gold")   // hold
        cs[machineIDs.firstIndex(of: "cyan")!].paramsA.rate = .r1_16      // arp, same pitch pool
        let b = box(machines: cs) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // col 0, row 0 → holds 60 on A (ch 1)
            $0.cells[0][1] = Cell(machineID: "cyan", buses: [.a])   // col 0, row 1 → arps 60 on A (ch 1)
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        let ons = e.ons.filter { $0.cable == 1 && $0.note == 60 }.count
        let offs = e.offs.filter { $0.cable == 1 && $0.note == 60 }.count
        XCTAssertGreaterThan(ons, 2, "the arp re-strikes 60 many times over the run")
        XCTAssertLessThanOrEqual(abs(ons - offs), 1, "RESTRIKE: each re-strike is a clean off+on — offs pace the ons")
        assertNothingLeftSounding(e)   // still balanced at the end: nothing stuck
    }
    func testRestrikeEmitsOffBeforeOnForAnAlreadySoundingNote() {
        // Two holders of note 60 on emitter A in one window: the SECOND strike re-articulates — a note-OFF then
        // note-ON at the same sample (off first), so a mono synth retriggers. Both ons still emit (clause 1).
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a]); s.cells[0][1] = Cell(machineID: "gold", buses: [.a])
        let box = SnapshotBuilder.build(from: PluginState(machines: claimMachines(transposeB: 0), scenes: [s]))
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        router.process(box: box, pool: chord([60]), playing: true, beatPos: 0, tempo: 120,
                       sampleRate: 48_000, timestampSample: 0, frameCount: 2048, out: e, diag: &diag)
        let onA = e.events.filter { $0.cable == 1 && $0.note == 60 }
        XCTAssertEqual(onA.filter { $0.status == 0x90 }.count, 2, "both holders' note-ons emit")
        XCTAssertEqual(onA.filter { $0.status == 0x80 }.count, 1, "the second strike inserts one re-articulation OFF")
        // and the OFF comes before the second ON (off-first at the same timestamp)
        if let firstOff = onA.firstIndex(where: { $0.status == 0x80 }) {
            XCTAssertTrue(onA[..<firstOff].contains { $0.status == 0x90 }, "an ON precedes the re-articulation OFF")
            XCTAssertTrue(onA[(firstOff + 1)...].contains { $0.status == 0x90 }, "the re-attack ON follows the OFF")
        }
    }

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

    func testReceiverChannelFilterRoutesSubscribersEndToEnd() {
        // Two cells subscribe to two receivers filtering different channels — the T6 routing, but the
        // filter now lives on the shared receiver rather than the cell.
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!] = holdMachine("gold")
        cs[machineIDs.firstIndex(of: "cyan")!] = holdMachine("cyan")
        var st = PluginState(machines: cs, scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()  // R1 = ch 1
            s.cells[0][1] = { var c = Cell(machineID: "cyan", buses: [.b]); c.inputReceiver = 1; return c }()  // R2 = ch 2
            return s }()])
        st.receivers = [Receiver(name: "1", channel: 1), Receiver(name: "2", channel: 2), Receiver(name: "3"), Receiver(name: "4")]
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0)   // wire ch 0 → R1 (ch 1)
        pool.noteOn(64, velocity: 100, channel: 1)   // wire ch 1 → R2 (ch 2)
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), pool, beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "R1 subscriber hears its channel")
        XCTAssertTrue(e.ons.filter { $0.cable == 1 && $0.note == 64 }.isEmpty, "R1 subscriber doesn't hear R2's channel")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 && $0.note == 64 }.count, 0, "R2 subscriber hears its channel")
        assertNothingLeftSounding(e)
    }

    // (testBackwardTapDownwardReferenceEmits + testProcBFullMorphsToBFaceUnderAlt + testProcBSwapFlipsTypeUnderAlt removed
    //  2026-08-27: all three guard RETIRED features that pass for the wrong reason. Backward-tap = grid-chaining (`inputRow`
    //  render-inert). The two procB tests = A/B MORPH (dropped from the render — paramsB/typeB are decode-only), so they
    //  only assert "ALT does NOT reach the inert B-face", which can never fail. The alt-bit's live role (voice identity)
    //  is covered elsewhere.)

    // CELL MACHINE (feat/EditPageSpike): a cell's explicit 1-slot chain drives the render identically to the
    // Machine it references (the head == the Machine's A face). Proves the per-cell head-treatment override.
    func testSingleSlotChainSoundsLikeTheMachine() {
        let cs = arpMachines()   // gold = ARP
        let gi = machineIDs.firstIndex(of: "gold")!
        let ctrl = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // Machine drives (no chain)
        let e0 = RecordingEmitter(); run(ctrl, chord([60, 64, 67]), beats: 16, into: e0)
        let head = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA)                    // an explicit head == A face
        let chained = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [head]; return c }() }
        let e1 = RecordingEmitter(); run(chained, chord([60, 64, 67]), beats: 16, into: e1)
        XCTAssertGreaterThan(e1.ons.count, 0, "the chained arp sounds")
        XCTAssertEqual(Set(e0.ons.map { $0.note }), Set(e1.ons.map { $0.note }), "a 1-slot chain renders like its Machine's A face")
        assertNothingLeftSounding(e1)
    }

    // CELL MACHINE: a bypassed HEAD slot = identity passthrough — the raw held chord passes; the arp is bypassed.
    func testBypassedHeadSlotIsPassthrough() {
        let cs = arpMachines()   // gold = ARP
        let gi = machineIDs.firstIndex(of: "gold")!
        var head = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA); head.bypassed = true
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [head]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67],
                       "a bypassed head passes the raw held chord (identity), not an arp")
        assertNothingLeftSounding(e)
    }

    // MODE ROW: a NEWBORN cell has an EXPLICIT empty chain (`processors == []`) — born AUDIBLE as a passthrough.
    // The held chord flows to its emitter untreated (no PASS slot, no template), and nothing is left sounding.
    func testEmptyChainIsBornAudiblePassthrough() {
        let cs = arpMachines()   // gold = ARP — proves the EMPTY chain does NOT fall back to the Machine's arp
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = []; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67],
                       "an empty chain passes the raw held chord (identity passthrough), not the Machine's arp")
        assertNothingLeftSounding(e)
    }

    // NO-MACHINE WIRE (Paul 2026-08-23): a door-connected empty chain passes its input STRAIGHT THROUGH in REALTIME
    // (via reconcileBypass), not on the grid's step clock — so a note pressed MID-column strikes immediately, where a
    // gridded hold would wait for the next column boundary. Also: no stuck notes on release.
    func testNoMachineChainIsARealtimeWire() {
        var st = PluginState(machines: arpMachines(), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; c.processors = []; return c }()   // EMPTY chain, reads door R1 (OMNI)
            return s }()])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.passEmitterMask[0] & 0b0001, 0b0001, "the no-machine cell registers emitter A as a live wire on door 0")
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 256, sr = 48_000.0, tempo = 120.0, bps = tempo / 60.0 / sr
        var ts: Int64 = 0
        func step(_ pool: NotePool, _ playing: Bool = true) {
            router.process(box: b, pool: pool, playing: playing, beatPos: Double(ts) * bps, tempo: tempo, sampleRate: sr, timestampSample: Double(ts), frameCount: frames, out: e, diag: &diag)
            ts += Int64(frames)
        }
        step(NotePool())                                  // window 0 (beat 0, column 0): nothing held
        XCTAssertTrue(e.ons.isEmpty, "nothing held → nothing sounds")
        step(chord([60]))                                 // window 1: STILL column 0 (no boundary crossed) — a gridded hold could NOT strike here
        XCTAssertTrue(e.ons.contains { $0.note == 60 }, "the no-machine wire strikes the held note in realtime, mid-column")
        step(NotePool()); step(NotePool(), false)         // release + stop
        assertNothingLeftSounding(e)
    }
    // The BUILD-workshop shape: a machine whose chain resolves to ALL-BYPASSED (an ephemeral empty machine carries a
    // bypassed-empty placeholder), a nil-processors cell reading a door — must ALSO take the realtime wire.
    func testAllBypassedTemplateIsAlsoARealtimeWire() {
        var gold = Machine(machineID: "gold", type: .empty)
        gold.templateChain = [{ var s = ProcessorSlot(type: .arp); s.bypassed = true; return s }()]   // all-bypassed ≡ empty
        var st = PluginState(machines: [gold] + arpMachines().dropFirst(), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()   // nil processors → follows the all-bypassed template
            return s }()])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.passEmitterMask[0] & 0b0001, 0b0001, "an all-bypassed-template cell registers as a live wire")
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 256, sr = 48_000.0, tempo = 120.0, bps = tempo / 60.0 / sr
        var ts: Int64 = 0
        func step(_ pool: NotePool, _ playing: Bool = true) {
            router.process(box: b, pool: pool, playing: playing, beatPos: Double(ts) * bps, tempo: tempo, sampleRate: sr, timestampSample: Double(ts), frameCount: frames, out: e, diag: &diag)
            ts += Int64(frames)
        }
        step(NotePool()); XCTAssertTrue(e.ons.isEmpty)
        step(chord([60]))                                  // mid-column press
        XCTAssertTrue(e.ons.contains { $0.note == 60 }, "the all-bypassed-template no-machine cell also strikes in realtime")
        step(NotePool()); step(NotePool(), false)
        assertNothingLeftSounding(e)
    }
    // BUG FIX (Paul, device 2026-08-05): a chain whose slots are ALL bypassed ≡ an EMPTY chain → the born-audible
    // passthrough (raw held chord), for ANY depth. Mirrors testEmptyChainIsBornAudiblePassthrough.
    func testAllBypassedChainIsPassthroughAtAnyDepth() {
        let cs = arpMachines()   // gold = ARP → proves all-bypassed does NOT arp
        let gi = machineIDs.firstIndex(of: "gold")!
        func bypassedChain(_ n: Int) -> [ProcessorSlot] {
            (0..<n).map { _ in var s = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA); s.bypassed = true; return s }
        }
        for depth in [1, 8] {
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = bypassedChain(depth); return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
            XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67],
                           "a \(depth)-slot all-bypassed chain passes the raw held chord (identity passthrough)")
            assertNothingLeftSounding(e)
        }
        // Partial bypass is UNAFFECTED — one active arp among bypassed slots still drives (an arp, not the raw chord).
        let arp = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA)   // active ARP tail
        var byp = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA); byp.bypassed = true
        let bp = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [byp, arp]; return c }() }
        let ep = RecordingEmitter(); run(bp, chord([60, 64, 67]), beats: 16, into: ep)
        XCTAssertGreaterThan(ep.ons.filter { $0.cable == 1 }.count, 3, "partial bypass unaffected — the active arp still drives")
        assertNothingLeftSounding(ep)
    }

    // CELL MACHINE stage-2 (serial execution, tick-tail slice): a 2-slot chain [open gate → ARP] arps the
    // held chord — the intra-cell echo of the grid GATE→ARP routing.
    func testChainGateToArpArpsTheHeldChord() {
        let cs = arpMachines()
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 1.0   // deterministic open gate (PASSGATE removed 2026-09-28)
        let arp = ProcessorSlot(type: .arp)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [gate, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertTrue(notes.isSuperset(of: [60, 64, 67]), "the ARP tail arpeggiates every note the gate passed")
        assertNothingLeftSounding(e)
    }

    // MODE ROW (device round 2): the tick DRIVER need not be the TAIL. [ARP → open gate] keeps ARPEGGIATING —
    // the arp drives the rhythm and the gate folds onto each arp note — instead of the arp collapsing to one
    // held note (the pre-fix bug). An OPEN gate after the arp is transparent.
    func testArpThenOpenGateStillArpeggiates() {
        let cs = arpMachines()
        let arp = ProcessorSlot(type: .arp)
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 1.0   // deterministic open gate (PASSGATE removed 2026-09-28)
        let plain = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp]; return c }() }
        let e0 = RecordingEmitter(); run(plain, chord([60, 64, 67]), beats: 16, into: e0)
        let chained = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, gate]; return c }() }
        let e1 = RecordingEmitter(); run(chained, chord([60, 64, 67]), beats: 16, into: e1)
        XCTAssertGreaterThan(e1.ons.count, 3, "arp → open gate arpeggiates (many onsets), not one held note")
        XCTAssertEqual(Set(e0.ons.map { $0.note }), Set(e1.ons.map { $0.note }), "an open gate after the arp is transparent")
        assertNothingLeftSounding(e1)
    }
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
    func testAvoidLockToKeyBeforeAndAfterAnArp() {
        let cs = arpMachines(); let arp = ProcessorSlot(type: .arp)
        let lockRemove = avoidSlot(kind: .key, lock: true, move: false)   // LOCK to C major, REMOVE out-of-key
        let chord4 = chord([60, 61, 64, 67])                              // C · C#(out of C major) · E · G
        func classes(_ e: RecordingEmitter) -> Set<Int> { Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) % 12 }) }
        // BEFORE the arp → re-pool: the arp walks {C,E,G}; C# never enters the pool.
        let before = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [lockRemove, arp]; return c }() }
        let eB = RecordingEmitter(); run(before, chord4, beats: 16, into: eB)
        XCTAssertFalse(classes(eB).contains(1), "[LOCK→ARP]: C# (class 1) is re-pooled out — the arp never plays it")
        XCTAssertFalse(eB.ons.isEmpty, "the in-key notes still arp")
        // AFTER the arp → punch holes: the arp walks all 4, but the downstream LOCK drops C#.
        let after = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, lockRemove]; return c }() }
        let eA = RecordingEmitter(); run(after, chord4, beats: 16, into: eA)
        XCTAssertFalse(classes(eA).contains(1), "[ARP→LOCK]: C# is dropped downstream — a hole in the line")
        XCTAssertTrue(classes(eA).contains(0) || classes(eA).contains(4), "in-key notes still emit")
        assertNothingLeftSounding(eB); assertNothingLeftSounding(eA)
    }
    func testAvoidMoveSnapsTheOutOfKeyNoteInsteadOfDropping() {
        let cs = arpMachines(); let arp = ProcessorSlot(type: .arp)
        let lockMove = avoidSlot(kind: .key, lock: true, move: true)      // LOCK to C major, MOVE (snap) — nothing drops
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [lockMove, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([61]), beats: 16, into: e)   // ONLY C# held → with REMOVE it'd be silent; MOVE snaps it in-key
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertFalse(notes.contains(61), "C# never sounds (it's out of key)")
        XCTAssertFalse(notes.isEmpty, "MOVE snapped it to the nearest in-key note instead of dropping — the line stays audible")
        XCTAssertTrue(notes.allSatisfy { [0,2,4,5,7,9,11].contains($0 % 12) }, "every snapped note is in C major")
        assertNothingLeftSounding(e)
    }
    // Paul's scenario (2026-08-31): a chain references ANOTHER receiver and avoids not just its exact notes but the ones
    // that CLASH with them. Door 0 (ch 1) feeds the AVOID chain; door 1 (ch 2) is the referenced receiver, played LIVE.
    func testAvoidDoorReferenceReadsAnotherLiveReceiverAndItsClashes() {
        let cs = arpMachines()
        func mk(_ what: AvoidWhat) -> SnapshotBox {
            var av = ProcessorSlot(type: .avoid); av.params.avoidRefKind = .door; av.params.avoidRefIndex = 1
            av.params.avoidMode = .avoid; av.params.avoidAction = .remove; av.params.avoidWhat = what
            var st = PluginState(machines: cs, scenes: [{ var s = SceneState.empty()
                s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; c.processors = [av]; return c }()   // AVOID chain reads door 0 (ch 1)
                return s }()])
            st.busChannels = [1, 2, 3, 4]
            st.receivers = [Receiver(name: "1", channel: 1), Receiver(name: "2", channel: 2), Receiver(name: "3"), Receiver(name: "4")]
            return SnapshotBuilder.build(from: st)
        }
        func played(_ what: AvoidWhat) -> Set<Int> {
            let pool = NotePool()
            pool.noteOn(60, velocity: 100, channel: 1)   // C → the REFERENCED receiver (door 1, ch 2) is playing it
            pool.noteOn(61, velocity: 100, channel: 0)   // C# → the AVOID chain's OWN input (door 0, ch 1)
            let e = RecordingEmitter(); run(mk(what), pool, beats: 16, into: e)
            return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        }
        XCTAssertTrue(played(.same).contains(61), "SAME: C# is not the reference's C → it passes (only exact doubling avoided)")
        XCTAssertFalse(played(.clash).contains(61), "CLASH: C# rubs against the reference's live C (ic1) → removed — avoid what it plays AND what clashes with it")
    }
    // AVOID MOVE stays IN THE INPUT SCALE (Paul 2026-08-31: a scale processor must not snap to a chromatic note outside it).
    // Input = a C-major triad; the reference blocks E. MOVE relocates E to the nearest SURVIVING triad note (G), never D#.
    func testAvoidMoveSnapsWithinTheInputScaleNotChromatically() {
        let cs = arpMachines()
        var av = ProcessorSlot(type: .avoid); av.params.avoidRefKind = .door; av.params.avoidRefIndex = 1
        av.params.avoidMode = .avoid; av.params.avoidAction = .move; av.params.avoidWhat = .same
        var st = PluginState(machines: cs, scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; c.processors = [av]; return c }()   // AVOID chain reads door 0 (ch 1)
            return s }()])
        st.busChannels = [1, 2, 3, 4]
        st.receivers = [Receiver(name: "1", channel: 1), Receiver(name: "2", channel: 2), Receiver(name: "3"), Receiver(name: "4")]
        let box = SnapshotBuilder.build(from: st)
        let pool = NotePool()
        pool.noteOn(76, velocity: 100, channel: 1)   // E5 → the REFERENCED receiver (door 1, ch 2) blocks pitch class 4 (a DIFFERENT octave so it doesn't collide with the input E)
        pool.noteOn(60, velocity: 100, channel: 0)   // C ┐
        pool.noteOn(64, velocity: 100, channel: 0)   // E ┼ the AVOID chain's own input (door 0, ch 1) — a C-major triad
        pool.noteOn(67, velocity: 100, channel: 0)   // G ┘  (E is blocked → MOVE relocates it in-scale)
        let e = RecordingEmitter(); run(box, pool, beats: 16, into: e)
        let classes = Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) % 12 })
        XCTAssertFalse(classes.isEmpty, "MOVE relocates the blocked E rather than dropping it")
        XCTAssertFalse(classes.contains(4), "E (class 4) is blocked — it never sounds")
        XCTAssertTrue(classes.isSubset(of: [0, 4, 7]), "MOVE lands only on the input triad's notes (C/E/G), never a chromatic note")
        XCTAssertFalse(classes.contains(3), "the OLD chromatic snap moved E→D# (class 3, out of scale); the in-scale snap does not")
        assertNothingLeftSounding(e)
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

    // JOB 7 §G — AVOID "EVERYTHING OUT" (soundingOut): reference = all emitter OUTPUT except this cell's OWN buses
    // (self-exclude by bus). Proves both halves: a solo AVOID doesn't avoid its own output; a second emitter's output IS
    // avoided. (Mirrors the CONVERSATION setup — a row-1 cell reads emitter A's live output from row 0.)
    func testAvoidEverythingOutSelfExcludesButReadsOtherEmitters() {
        func pcs(withAonBusA: Bool) -> (a: Set<Int>, b: Set<Int>, e: RecordingEmitter) {
            var s = SceneState.empty()
            if withAonBusA { s.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }              // emits the held chord on emitter A (row 0)
            s.cells[0][1] = { var c = Cell(machineID: "cyan", buses: [.b]); c.processors = [mkAvoid(kind: .soundingOut)]; return c }()   // AVOID EVERYTHING-OUT on B (row 1)
            let st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord([60, 62]), beats: 16, into: e)   // C, D
            let map = { (cable: Int) in Set(e.ons.filter { $0.cable == cable }.map { ((Int($0.note) % 12) + 12) % 12 }) }
            return (map(1), map(2), e)
        }
        let solo = pcs(withAonBusA: false)                                                     // no OTHER emitter output
        XCTAssertEqual(solo.b, [0, 2], "self-excludes its own bus B → reference empty → passes its whole input (C,D)")
        let duo = pcs(withAonBusA: true)
        XCTAssertEqual(duo.a, [0, 2], "the row-0 cell plays C,D on emitter A")
        XCTAssertTrue(duo.b.isEmpty, "the AVOID on B reads emitter A's output (C,D ∉ B) and blocks both")
        assertNothingLeftSounding(duo.e)                                                        // no stuck notes on the new reference path
    }

    // ── Reference-content edges ────────────────────────────────────────────────
    func testAvoidEmptyReferencePassesEverything() {   // C1
        XCTAssertEqual(avoidPCs([mkAvoid()], input: [60, 62, 64], refs: []), [0, 2, 4], "empty reference · AVOID REMOVE → everything passes")
        XCTAssertEqual(avoidPCs([mkAvoid(move: true)], input: [60, 62, 64], refs: []), [0, 2, 4], "empty reference · AVOID MOVE → everything passes")
    }
    func testLockEmptyReferenceSilences() {   // C2
        XCTAssertTrue(avoidPCs([mkAvoid(lock: true)], input: [60, 62, 64], refs: []).isEmpty, "empty reference · LOCK → silence (nothing to lock to)")
        XCTAssertTrue(avoidPCs([mkAvoid(lock: true, move: true)], input: [60, 62, 64], refs: []).isEmpty, "empty reference · LOCK MOVE → still silence")
    }
    func testAvoidRemovesExactlyTheReferenceClasses() {   // C3
        XCTAssertEqual(avoidPCs([mkAvoid()], input: [60, 62, 64], refs: [(1, [2])]), [0, 4], "AVOID drops D (the reference class), keeps C & E")
    }
    func testLockKeepsOnlyTheReferenceClasses() {   // C4
        XCTAssertEqual(avoidPCs([mkAvoid(lock: true)], input: [60, 62, 64, 67], refs: [(1, [0, 4])]), [0, 4], "LOCK keeps only C & E (the reference), drops D & G")
    }
    func testAvoidClashWidthNoneVsPlusOneVsPlusTwo() {   // C5
        XCTAssertEqual(avoidPCs([mkAvoid(what: .same)], input: [61, 62], refs: [(1, [0])]), [1, 2], "SAME: only exact C blocked — C# & D pass")
        XCTAssertEqual(avoidPCs([mkAvoid(what: .clash)], input: [61, 62], refs: [(1, [0])]), [2], "±1: C# (a semitone from C) blocked, D passes")
        XCTAssertTrue(avoidPCs([mkAvoid(what: .clash2)], input: [61, 62], refs: [(1, [0])]).isEmpty, "±2: C# and D both blocked")
    }
    func testAvoidMoveWithNoSurvivorsDrops() {   // C6
        XCTAssertTrue(avoidPCs([mkAvoid(move: true)], input: [62], refs: [(1, [2])]).isEmpty, "MOVE with a single blocked note & no survivor → drops (= REMOVE)")
    }

    // ── EVERYTHING (.sounding) = every OTHER input, never your own receiver (B-2) ──
    func testEverythingAvoidsOtherDoorsNeverOwn() {   // C9
        XCTAssertEqual(avoidPCs([mkAvoid(kind: .sounding)], input: [60, 62, 64], refs: [(1, [2]), (2, [5])]), [0, 4],
                       "EVERYTHING avoids what OTHER inputs play (D on door1) — C & E pass; F on door2 wasn't in the input")
    }
    func testEverythingNeverAvoidsItsOwnInput() {   // C9b — the self-exclusion contract
        XCTAssertEqual(avoidPCs([mkAvoid(kind: .sounding)], input: [60, 62, 64], refs: []), [0, 2, 4],
                       "EVERYTHING with only this chain's own input playing → nothing to avoid (own receiver excluded) → all pass")
    }

    // ── Reference domain / octave ──────────────────────────────────────────────
    func testKeyReferenceLocksToScale() {   // C11 (engine-only .key path)
        XCTAssertEqual(avoidPCs([mkAvoid(kind: .key, lock: true, root: 0, scale: .major)], input: [60, 61, 62], refs: []), [0, 2],
                       "LOCK to C major drops C# (out of key), keeps C & D")
    }
    func testReferenceIsOctaveAgnostic() {   // C12
        XCTAssertTrue(avoidPCs([mkAvoid()], input: [48], refs: [(1, [0])]).isEmpty, "a C in octave 7 (the reference) blocks a C in octave 3 (the input) — pitch-class match")
    }
    func testLockMoveSnapsToReferenceEvenIfAbsentFromInput() {   // C13
        XCTAssertEqual(avoidPCs([mkAvoid(lock: true, move: true)], input: [62], refs: [(1, [0, 4, 7])]), [0],
                       "LOCK MOVE snaps D→C (nearest reference note) even though C was never in the input")
    }
    func testMoveNeverEmitsOutOfRange() {   // C14
        let out = avoidRunE([mkAvoid(move: true)], input: [1, 3], refs: [(1, [1])]).ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertTrue(out.allSatisfy { $0 >= 0 && $0 <= 127 }, "MOVE near note 0 never emits an out-of-range note")
    }

    // ── Chain position — the heart of the felt inconsistency ───────────────────
    func testAvoidRemoveIsPositionInvariantAroundADriver() {   // C23
        let arp = ProcessorSlot(type: .arp)
        XCTAssertEqual(avoidPCs([arp, mkAvoid()], input: [60, 64, 67], refs: [(1, [4])]), [0, 7], "[ARP→AVOID(remove)] drops E, arps C & G")
        XCTAssertEqual(avoidPCs([mkAvoid(), arp], input: [60, 64, 67], refs: [(1, [4])]), [0, 7], "[AVOID(remove)→ARP] re-pools (drops E), arps C & G")
    }
    func testAvoidMoveDownstreamOfADriverSnapsInScale() {   // C17 — the B-1 FIX
        let arp = ProcessorSlot(type: .arp)
        let pcs = avoidPCs([arp, mkAvoid(move: true)], input: [60, 64, 67], refs: [(1, [4])])
        XCTAssertFalse(pcs.contains(4), "E (blocked) never sounds")
        XCTAssertFalse(pcs.isEmpty, "MOVE relocates E in-scale downstream of the arp (B-1 fix) — it does NOT degrade to DROP")
        XCTAssertTrue(pcs.isSubset(of: [0, 7]), "the moved arp note lands on the chord's surviving notes (C/G), never a chromatic note")
    }
    func testLockMoveIsPositionInvariantDownstream() {   // C22
        let arp = ProcessorSlot(type: .arp)
        let pcs = avoidPCs([arp, mkAvoid(lock: true, move: true)], input: [60, 64, 67], refs: [(1, [0, 7])])
        XCTAssertFalse(pcs.contains(4), "[ARP→LOCK(move)]: E (not in the lock set) is snapped away")
        XCTAssertTrue(pcs.isSubset(of: [0, 7]) && !pcs.isEmpty, "LOCK MOVE snaps to the key even downstream of a driver (position-invariant)")
    }
    func testAvoidAsHoldTailAfterHarmonize() {   // C19
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [3, 0, 0]   // + minor third
        let pcs = avoidPCs([harm, mkAvoid()], input: [60], refs: [(1, [3])])
        XCTAssertEqual(pcs, [0], "[HARMONIZE→AVOID]: C harmonizes to {C, D#}, then the blocked D# is dropped — C alone")
    }
    func testAvoidBeforeAndAfterTheSameDriverBothRemove() {   // C21 (REMOVE is consistent both sides)
        let arp = ProcessorSlot(type: .arp)
        let pcs = avoidPCs([mkAvoid(), arp, mkAvoid()], input: [60, 64, 67], refs: [(1, [4])])
        XCTAssertEqual(pcs, [0, 7], "[AVOID→ARP→AVOID] (both REMOVE): E removed upstream & downstream → C+G either way")
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
    // HARMONIZE after the arp adds its interval voice to EACH arp note (the +7 of 64 = 71 is not a chord note).
    func testArpThenHarmonizeAddsVoiceToEachArpNote() {
        let cs = arpMachines()
        let arp = ProcessorSlot(type: .arp)
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, harm]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        let notes = Set(e.ons.map { $0.note })
        XCTAssertTrue(notes.contains(71) || notes.contains(74), "harmonize after the arp adds the +7 voice to arp notes")
        assertNothingLeftSounding(e)
    }

    // RECORDER (AcceptanceCriteria-recorder) — [ARP → RECORDER(LOOP·PASSES·N=1·ON PLAY·REPLACE·ONCE)] records the arp
    // during pass 1, then loops it back. The loop must (a) reproduce the arp's note set, (b) keep playing past the
    // record pass (so the total isn't just one pass), and (c) leave nothing stuck.
    func testRecorderCapturesAndLoopsTheArp() {
        let cs = arpMachines()
        let arp = ProcessorSlot(type: .arp)
        var rec = ProcessorSlot(type: .recorder)
        rec.params.recGrain = .passes; rec.params.recLen = 1; rec.params.recMode = .loop
        rec.params.recArm = .onPlay; rec.params.recMix = .replace; rec.params.recCapture = .once
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, rec]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 32, into: e)
        // the arp alone over the same span — the reference note set + count.
        let ea = RecordingEmitter()
        let ba = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp]; return c }() }
        run(ba, chord([60, 64, 67]), beats: 32, into: ea)
        XCTAssertGreaterThan(e.ons.count, 0, "the recorder loop produces notes")
        XCTAssertEqual(Set(e.ons.map { $0.note }), Set(ea.ons.map { $0.note }), "the loop reproduces the arp's note set")
        XCTAssertGreaterThan(e.ons.count, ea.ons.count / 2, "the loop keeps playing past pass 1 (not silent after the record window)")
        assertNothingLeftSounding(e)
    }

    // RECORDER FREEZE HELD — captures once, then holds the DISTINCT captured pitches as a pad. The played notes are a
    // subset of the arp's pitches (deduped), it keeps sounding, and nothing is stuck.
    func testRecorderFreezeHeldSustainsThePitches() {
        let cs = arpMachines()
        let arp = ProcessorSlot(type: .arp)
        var rec = ProcessorSlot(type: .recorder)
        rec.params.recGrain = .passes; rec.params.recLen = 1; rec.params.recMode = .freeze
        rec.params.recFreeze = .held; rec.params.recArm = .onPlay; rec.params.recMix = .replace
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, rec]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 32, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "the frozen pad plays")
        let ea = RecordingEmitter()
        let ba = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp]; return c }() }
        run(ba, chord([60, 64, 67]), beats: 32, into: ea)
        XCTAssertTrue(Set(e.ons.map { $0.note }).isSubset(of: Set(ea.ons.map { $0.note })), "the held pad's pitches are a subset of the arp's")
        assertNothingLeftSounding(e)
    }

    // RECORDER CANON — records continuously and plays the phrase back one window LATE while the live arp continues
    // (LAYER), so the total exceeds the arp alone (the chasing echo adds notes). Nothing stuck.
    func testRecorderCanonEchoesOneWindowLater() {
        let cs = arpMachines()
        let arp = ProcessorSlot(type: .arp)
        var rec = ProcessorSlot(type: .recorder)
        rec.params.recGrain = .passes; rec.params.recLen = 1; rec.params.recMode = .canon; rec.params.recArm = .onPlay
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, rec]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 32, into: e)
        let ea = RecordingEmitter()
        let ba = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp]; return c }() }
        run(ba, chord([60, 64, 67]), beats: 32, into: ea)
        XCTAssertGreaterThan(e.ons.count, ea.ons.count, "canon adds a delayed copy on top of the live arp")
        assertNothingLeftSounding(e)
    }

    // RECORDER CAPTURE=REFRESH — the loop renews every M cycles: it re-records + re-commits, producing notes across the
    // whole run with nothing stuck (the renew itself is device-ear-owed; here we lock no-stuck-notes across the re-arm).
    func testRecorderRefreshRenewsWithoutStuckNotes() {
        let cs = arpMachines()
        let arp = ProcessorSlot(type: .arp)
        var rec = ProcessorSlot(type: .recorder)
        rec.params.recGrain = .passes; rec.params.recLen = 1; rec.params.recMode = .loop
        rec.params.recArm = .onPlay; rec.params.recMix = .replace; rec.params.recCapture = .refresh; rec.params.recRefreshM = 2
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, rec]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 48, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "the refreshing loop produces notes")
        assertNothingLeftSounding(e)
    }

    // RECORDER persistence (LOAD half) — a persisted/authored recEvents buffer seeds the loop directly and plays,
    // no live driver required. (The live-capture→document SAVE drain is a later stage.)
    func testRecorderPlaysAnAuthoredBuffer() {
        let cs = arpMachines()
        var rec = ProcessorSlot(type: .recorder)
        rec.params.recMode = .loop; rec.params.recMix = .replace
        rec.params.recEvents = [RecEvent(beat: 0, note: 72, vel: 100, gate: 0.5), RecEvent(beat: 1, note: 76, vel: 90, gate: 0.5)]
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [rec]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        let notes = Set(e.ons.map { $0.note })
        XCTAssertTrue(notes.contains(72) && notes.contains(76), "the authored recorder buffer plays its notes")
        assertNothingLeftSounding(e)
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

    // CELL MACHINE stage-2 (FULL note-set flow): [harmonize +7 → ARP] arps BOTH the source note AND the added
    // voice — the whole set flows to the tail, not one note.
    func testChainHarmonizeToArpArpsAllVoices() {
        let cs = arpMachines()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let arp = ProcessorSlot(type: .arp)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [harm, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertTrue(notes.contains(60), "arps the source note")
        XCTAssertTrue(notes.contains(67), "arps the +7 harmonized voice too (full note-set flow)")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2: a BYPASSED head is a true-bypass — the tail sees only the raw source (no +7 voice).
    func testChainBypassedHeadArpsSourceOnly() {
        let cs = arpMachines()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]; harm.bypassed = true
        let arp = ProcessorSlot(type: .arp)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [harm, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertTrue(notes.contains(60), "the source note still arps")
        XCTAssertFalse(notes.contains(67), "a BYPASSED harmonize head adds no voice — the tail sees only the source")
        assertNothingLeftSounding(e)
    }

    // The chain's INPUT LAW, end to end (user 2026-08-09): the HEAD reads the CELL'S RECEIVER-filtered source, and a
    // downstream slot reads its PARENT's output — never the raw receiver again. Prior tests proved each half alone
    // (channel filter on single-stage cells · harmonize→arp threading); this COMBINES them. A cell filtering IN CH 2
    // (wire ch 1) runs [harmonize +7 → arp], fed two notes on different wire channels. Only the admitted note (64)
    // may enter the chain, and only via the HEAD — so the tail arps {64, 71 (=64+7)} and NOTHING derived from 60.
    func testChainHeadReadsReceiverFilterAndTailReadsParentOutput() {
        let cs = arpMachines()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let arp = ProcessorSlot(type: .arp)
        let b = box(machines: cs) {
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputChannel = 2; c.processors = [harm, arp]; return c }()  // IN CH 2 = wire 1
        }
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0)   // wire ch 0 — NOT admitted by this cell's receiver
        pool.noteOn(64, velocity: 100, channel: 1)   // wire ch 1 — admitted (IN CH 2)
        let e = RecordingEmitter(); run(b, pool, beats: 16, into: e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertTrue(notes.contains(64), "the HEAD reads the RECEIVER-filtered source (only the ch-2 note 64 enters)")
        XCTAssertTrue(notes.contains(71), "the TAIL arps the HEAD's OUTPUT — 64's +7 harmony (parent-threaded, not re-read from source)")
        XCTAssertFalse(notes.contains(60), "the unadmitted note is filtered AT THE HEAD — it never reaches the chain")
        XCTAssertFalse(notes.contains(67), "…so 60's +7 harmony (67) never appears either — no downstream leak of the raw receiver")
        assertNothingLeftSounding(e)
    }

    // MARK: - THE MOD PROCESSOR (CC generator, delta)

    private func modCC74Events(_ e: RecordingEmitter) -> [RecordingEmitter.Ev] {
        e.events.filter { $0.status == 0xB0 && $0.cable == 1 && $0.note == 74 }   // CC 74 on Emit A
    }
    /// A standalone [MOD] cell emits a shaped CC (varying values, in range) on its emitter — and sounds NO notes.
    func testModCellEmitsShapedCCAndNoNotes() {
        let cs = arpMachines()
        var mod = ProcessorSlot(type: .mod)
        mod.params.modCC = 74; mod.params.modShape = .sine; mod.params.modRate = .r1
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        let ccs = modCC74Events(e)
        XCTAssertGreaterThan(ccs.count, 0, "the MOD cell emits CC 74 on Emit A")
        XCTAssertGreaterThan(Set(ccs.map { $0.vel }).count, 1, "the SINE shape produces VARYING values")
        XCTAssertTrue(ccs.allSatisfy { $0.vel <= 127 }, "every value is in 0…127")
        XCTAssertTrue(e.ons.isEmpty, "a MOD cell sounds NO notes")
        assertNothingLeftSounding(e)
    }
    // MOD DURATION as GRID STEPS (Paul 2026-09-16, arp-LFO anatomy): modStepSpanN drives the LFO period via spanLadderBeats;
    // nil/0 ⇒ modRate (byte-identical). A different span ⇒ a different sweep, so the value sequence differs.
    func testModStepSpanNDurationDrivesThePeriod() {
        let cs = arpMachines()
        func vals(_ setup: (inout MachineParams) -> Void) -> [UInt8] {
            var mod = ProcessorSlot(type: .mod)
            mod.params.modCC = 74; mod.params.modShape = .ramp; mod.params.modRate = .r1
            setup(&mod.params)
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
            return modCC74Events(e).map { $0.vel }
        }
        let baseline = vals { _ in }                       // modStepSpanN nil ⇒ period = modRate (.r1)
        let gridFast = vals { $0.modStepSpanN = 1 }        // 1 grid step ⇒ a shorter period → a faster ramp
        let gridSlow = vals { $0.modStepSpanN = 64 }       // ×8 bars ⇒ a much longer period
        XCTAssertGreaterThan(baseline.count, 0, "the MOD cell emits CC")
        XCTAssertNotEqual(gridFast, baseline, "GRID STEPS 1 changes the LFO period vs modRate")
        XCTAssertNotEqual(gridSlow, gridFast, "the ×8-bar span sweeps far slower than a 1-step span")
    }
    // FREE / THE LFO CELL (design-cc-stage §16, Paul 2026-09-09): a FREE MOD cell speaks EVERY window regardless of the
    // playhead. Placed in COLUMN 3 and run only within column 0's window, a schedule-gated (CELL) MOD is silent (never
    // active), but a FREE MOD emits — the grid as a mod-matrix.
    func testModFreeCellSpeaksOffThePlayhead() {
        let cs = arpMachines()
        func modBox(free: Bool) -> SnapshotBox {
            var mod = ProcessorSlot(type: .mod)
            mod.params.modCC = 74; mod.params.modShape = .sine; mod.params.modRate = .r1; mod.params.modFree = free
            return box(machines: cs) { $0.cells[3][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }   // COLUMN 3
        }
        let eCell = RecordingEmitter(); run(modBox(free: false), chord([60]), beats: 1.5, into: eCell)   // playhead stays in column 0 (S=2)
        let eFree = RecordingEmitter(); run(modBox(free: true),  chord([60]), beats: 1.5, into: eFree)
        XCTAssertEqual(modCC74Events(eCell).count, 0, "a schedule-gated MOD in column 3 is SILENT while column 0 is active")
        XCTAssertGreaterThan(modCC74Events(eFree).count, 0, "a FREE MOD (the LFO cell) speaks regardless of the playhead")
    }
    // SPAN ROW (Paul 2026-08-19): one LFO cycle spans the whole bar (vs the per-rate CELL). A RAMP resets once per
    // cycle, so counting the big value-drops = counting cycles: ROW has far fewer than the fast per-rate CELL.
    func testModSpanRowStretchesOneCycleAcrossTheBar() {
        let cs = arpMachines()
        func modBox(_ span: PatternSpan) -> SnapshotBox {
            var mod = ProcessorSlot(type: .mod)
            mod.params.modCC = 74; mod.params.modShape = .ramp; mod.params.modRate = .r1; mod.params.modSpan = span
            return box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        }
        func resets(_ span: PatternSpan) -> Int {
            let e = RecordingEmitter(); run(modBox(span), chord([60]), beats: 16, into: e)
            let vals = modCC74Events(e).map { Int($0.vel) }
            var drops = 0
            for i in 1..<max(1, vals.count) where vals[i] + 40 < vals[i - 1] { drops += 1 }   // a RAMP wrap = a big drop
            return drops
        }
        let rowResets = resets(.row), cellResets = resets(.cell)
        XCTAssertLessThan(rowResets, cellResets, "SPAN ROW stretches ONE ramp across the bar → far fewer resets than the per-rate CELL")
        XCTAssertLessThanOrEqual(rowResets, 3, "ROW: about one cycle per bar")
    }
    // STEPS SPAN ROW×2 (Paul 2026-08-20): 16 breakpoints across TWO bars. With bar1's steps ≈30 and bar2's ≈100,
    // ROW (8 steps, repeats each bar) only ever emits ≈30; ROW×2 reaches the second-bar breakpoints (≈100) too.
    func testModStepsSpanRow2ReachesSecondBarBreakpoints() {
        let cs = arpMachines()
        func modBox(_ span: ModStepSpan) -> SnapshotBox {
            var mod = ProcessorSlot(type: .mod)
            mod.params.modCC = 74; mod.params.modSource = .steps; mod.params.modSmooth = false; mod.params.modStepSpan = span
            mod.params.modSteps = Array(repeating: 30, count: 8) + Array(repeating: 100, count: 8)   // bar1 ≈30 · bar2 ≈100
            mod.params.modMin = 0; mod.params.modMax = 127
            return box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        }
        func values(_ span: ModStepSpan) -> Set<Int> {
            let e = RecordingEmitter(); run(modBox(span), chord([60]), beats: 16, into: e)
            return Set(modCC74Events(e).map { Int($0.vel) })
        }
        XCTAssertFalse(values(.row).contains(where: { $0 > 60 }), "ROW sees only the first 8 breakpoints (≈30)")
        XCTAssertTrue(values(.row2).contains(where: { $0 > 60 }), "ROW×2 reaches the second-bar breakpoints (≈100)")
    }
    // §2 INTERNAL TARGET (Paul 2026-08-20): a MOD set to THIS CHAIN emits NO CC — it modulates a chain param instead.
    func testModInternalTargetEmitsNoCC() {
        let cs = arpMachines()
        var mod = ProcessorSlot(type: .mod)
        mod.params.modTarget = .chain; mod.params.modChainParam = .spread; mod.params.modShape = .sine
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .strum), mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e)
        XCTAssertTrue(e.events.filter { $0.status == 0xB0 }.isEmpty, "an internal-target MOD emits NO CC")
        XCTAssertFalse(e.ons.isEmpty, "the strum still plays")
        assertNothingLeftSounding(e)
    }
    // §2: the internal MOD actually MOVES the target param. A strum with base spread=0 rakes near-simultaneously; a MOD
    // → SPREAD pinned at max (MIN=MAX=127 → constant offset 1.0) forces spread=1, so the onsets fan out much wider.
    func testModInternalTargetModulatesSpread() {
        let cs = arpMachines()
        func onsetSpan(withMod: Bool) -> Int {
            var strum = ProcessorSlot(type: .strum); strum.params.spread = 0
            var chain = [strum]
            if withMod {
                var mod = ProcessorSlot(type: .mod)
                mod.params.modTarget = .chain; mod.params.modChainParam = .spread
                mod.params.modMin = 127; mod.params.modMax = 127   // constant → offset = 1.0 → spread pinned to 1
                chain.append(mod)
            }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = chain; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 8, into: e)
            let ons = e.ons.map { Int($0.sample) }
            return (ons.max() ?? 0) - (ons.min() ?? 0)
        }
        XCTAssertGreaterThan(onsetSpan(withMod: true), onsetSpan(withMod: false), "MOD → SPREAD at max fans the strum onsets much wider")
    }
    /// [ARP → MOD]: MOD is note-transparent — the arp still plays AND MOD emits its CC.
    func testArpThenModKeepsArpNotesAndEmitsCC() {
        let cs = arpMachines()
        let arp = ProcessorSlot(type: .arp)
        var mod = ProcessorSlot(type: .mod); mod.params.modCC = 71; mod.params.modRate = .r1
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "the ARP still plays (MOD is note-transparent as a post-driver stage)")
        XCTAssertGreaterThan(e.events.filter { $0.status == 0xB0 && $0.note == 71 }.count, 0, "AND MOD emits its CC")
        assertNothingLeftSounding(e)
    }
    /// [MOD → ARP]: MOD passes the chord through (composeChainSet identity) so the arp arps it — AND MOD emits CC.
    func testModThenArpArpsAndEmitsCC() {
        let cs = arpMachines()
        var mod = ProcessorSlot(type: .mod); mod.params.modCC = 74; mod.params.modRate = .r1
        let arp = ProcessorSlot(type: .arp)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThanOrEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).count, 2, "the ARP arps the chord through the transparent MOD")
        XCTAssertGreaterThan(modCC74Events(e).count, 0, "MOD emits its CC")
        assertNothingLeftSounding(e)
    }
    /// The LEAVE-DISPOSITION: RESET sends an extra CC 0 each time the playhead exits the MOD's column; LEAVE does not.
    /// Same shape/timing in both runs, so the difference in CC-0 count is exactly the resets.
    func testModResetDispositionEmitsExtraZeroOnLeave() {
        func zeros(reset: Bool) -> Int {
            let cs = arpMachines()
            var mod = ProcessorSlot(type: .mod)
            mod.params.modCC = 74; mod.params.modShape = .sine; mod.params.modReset = reset; mod.params.modRate = .r1
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
            return modCC74Events(e).filter { $0.vel == 0 }.count
        }
        XCTAssertGreaterThan(zeros(reset: true), zeros(reset: false), "RESET sends an extra CC 0 on each column exit; LEAVE holds the last value")
    }
    /// FOLLOW COUNT: the CC tracks the held-note count — more notes → a higher value.
    func testModFollowCountTracksHeldNotes() {
        func maxCC(_ notes: [UInt8]) -> Int {
            let cs = arpMachines()
            var mod = ProcessorSlot(type: .mod); mod.params.modSource = .follow; mod.params.modFollow = .count; mod.params.modCC = 74
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
            let e = RecordingEmitter(); run(b, chord(notes), beats: 8, into: e)
            return modCC74Events(e).map { Int($0.vel) }.max() ?? 0
        }
        XCTAssertGreaterThan(maxCC([48, 50, 52, 55, 57, 60]), maxCC([60]), "FOLLOW COUNT rises with the held-note count")
    }
    /// STEPS: a stepped pattern emits its authored values (the high step 127 comes only from the pattern, not the reset).
    func testModStepsEmitsThePattern() {
        let cs = arpMachines()
        var mod = ProcessorSlot(type: .mod); mod.params.modSource = .steps; mod.params.modSmooth = false
        mod.params.modSteps = [0, 127, 0, 127, 0, 127, 0, 127]; mod.params.modRate = .r1; mod.params.modCC = 74
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(modCC74Events(e).map { Int($0.vel) }).contains(127), "the STEP pattern emits its high step")
    }
    /// STRIKE: on column entry an AR envelope rises toward MAX then falls back — the CC spans a range.
    func testModStrikeEnvelopeRisesAndFalls() {
        let cs = arpMachines()
        var mod = ProcessorSlot(type: .mod); mod.params.modSource = .strike; mod.params.modAttack = 0.1; mod.params.modRelease = 0.3
        mod.params.modCC = 74; mod.params.modMin = 0; mod.params.modMax = 127
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        let vals = modCC74Events(e).map { Int($0.vel) }
        XCTAssertGreaterThan(vals.max() ?? 0, 60, "the STRIKE envelope rises well above MIN")
        XCTAssertGreaterThan((vals.max() ?? 0) - (vals.min() ?? 0), 40, "…and spans a range (rise + fall)")
    }
    /// EXTERN: reads an incoming CC (the mod wheel, CC1) and re-emits it on the TARGET (CC74). Driven directly so the
    /// controller store can be fed (the `run` helper owns its router).
    func testModExternRetransmitsIncomingCC() {
        let cs = arpMachines()
        var mod = ProcessorSlot(type: .mod); mod.params.modSource = .extern; mod.params.modExternCC = 1; mod.params.modCC = 74; mod.params.modMin = 0; mod.params.modMax = 127
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        router.setControllerIn(cc: 1, value: 100)   // the "mod wheel" at 100
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<24 {
            router.process(box: b, pool: chord([60]), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        XCTAssertTrue(Set(e.events.filter { $0.status == 0xB0 && $0.note == 74 }.map { Int($0.vel) }).contains(100),
                      "EXTERN re-emits the incoming CC1 value (100) on the TARGET CC74")
    }
    /// GLIDE: the first note ANCHORS (note-on); an in-range next note BENDS (no note-on); a leap RE-ANCHORS (note-on);
    /// stop leaves nothing sounding.
    /// [ARP→GLIDE] v2 (ratified 2026-08-22, processor-pairings §7①): the arp DRIVES a mono gliding voice — its walk
    /// becomes bends of ONE sustained note, not a note-on per step. The bare [ARP] fires a note-on every tick, so glide
    /// emits STRICTLY FEWER note-ons AND pitch-bends (0xE0) the bare arp never sends. S-independent (relative counts).
    func testArpThenGlideCollapsesTheWalkIntoOneBendingVoice() {
        func mk(glide: Bool) -> SnapshotBox {
            box(machines: arpMachines()) {
                var c = Cell(machineID: "gold", buses: [.a])
                var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
                var g = ProcessorSlot(type: .glide); g.params.glideRange = 12; g.params.glidePriority = .last; g.params.glideReanchor = true; g.params.glideTime = 0.05
                c.processors = glide ? [arp, g] : [arp]
                $0.cells[0][0] = c
            }
        }
        let bare = RecordingEmitter(); run(mk(glide: false), chord([60, 62, 64]), beats: 4, into: bare)
        let glided = RecordingEmitter(); run(mk(glide: true), chord([60, 62, 64]), beats: 4, into: glided)
        let bareOns = bare.ons.filter { $0.cable == 1 }.count
        let glidedOns = glided.ons.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(bareOns, 0, "the bare arp fires a note-on per tick")
        XCTAssertLessThan(glidedOns, bareOns, "[ARP→GLIDE] collapses the in-range walk into a sustained bending voice (far fewer note-ons)")
        XCTAssertTrue(glided.events.contains { $0.status == 0xE0 && $0.vel != 64 }, "the arp's steps become pitch-bends of the mono voice")
        XCTAssertFalse(bare.events.contains { $0.status == 0xE0 }, "the bare arp sends no pitch-bend")
        assertNothingLeftSounding(glided)
    }
    /// [ARP→GLIDE] re-anchors when a step LEAPS beyond RANGE (the 303 accent): a tight range forces re-articulation on
    /// every leap (more note-ons); a wide range keeps one gliding voice. RE-ANCHOR mode. No stuck notes either way.
    func testArpThenGlideReanchorsOnLeapsBeyondRange() {
        func mk(range: Int) -> SnapshotBox {
            box(machines: arpMachines()) {
                var c = Cell(machineID: "gold", buses: [.a])
                var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
                var g = ProcessorSlot(type: .glide); g.params.glideRange = range; g.params.glidePriority = .last; g.params.glideReanchor = true; g.params.glideTime = 0.05
                c.processors = [arp, g]
                $0.cells[0][0] = c
            }
        }
        let wide = RecordingEmitter(); run(mk(range: 24), chord([48, 60, 72]), beats: 4, into: wide)    // 12-st steps within 24 → one gliding voice
        let tight = RecordingEmitter(); run(mk(range: 2), chord([48, 60, 72]), beats: 4, into: tight)   // 12-st leaps beyond 2 → re-anchor each step
        XCTAssertGreaterThan(tight.ons.filter { $0.cable == 1 }.count, wide.ons.filter { $0.cable == 1 }.count,
                             "a tight RANGE forces re-articulation on every leap; a wide RANGE keeps a single gliding voice")
        assertNothingLeftSounding(tight); assertNothingLeftSounding(wide)
    }
    // BUG FIX 2026-08-29 — the GLIDE-ANCHOR WRONG-CLOSE (stale-slot class). A glide anchor is opened IMMORTAL
    // (offSample .max, bypassRecv < 0), so before the fix emitColumnHolds' hold-continuity pass (which runs BEFORE the
    // tick loop + emitColumnGlide) marked it a holdCandidate and closed it at every column boundary — freeing its voice
    // slot. The tick loop could then REUSE that slot for another note, after which emitColumnGlide's phrase-end closed
    // the reused slot → a spurious early note-off on an unrelated voice. Fix: glide voices carry a `glideAnchor` tag
    // (like BYPASS) and are excluded from the hold-continuity close — the glide subsystem is their sole owner, so the
    // slot stays alive through the tick loop (no reuse window). Guard: a glide spanning ALL columns crossing every
    // boundary, alongside a LEGATO DRONE (so the hold-continuity path is genuinely doing work each boundary) — the
    // glide stays alive (bends after the first boundary, proving the anchor was never orphaned) and nothing sticks.
    func testGlideSpanningColumnsIsNotClosedByHoldContinuity() {
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!].type = .glide       // gold = a single-slot GLIDE
        let b = box(machines: cs) {
            for c in 0..<8 {                                       // glide row 0 spans every column (crosses every boundary)
                $0.cells[c][0] = { var x = Cell(machineID: "gold", buses: [.a]); var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glideRange = 12; g.params.glidePriority = .last; g.params.glideTime = 0.1; x.processors = [g]; return x }()
                $0.cells[c][1] = { var x = Cell(machineID: "orange", buses: [.b]); x.processors = []; return x }()   // a LEGATO drone (empty chain = born-audible passthrough) — keeps the hold-continuity path busy each boundary
            }
        }
        let e = RecordingEmitter()
        run(b, chord([60, 62, 64, 65]), beats: 12, into: e)       // many boundaries; the pool changes register the glide walks
        let bends = e.events.filter { ($0.status & 0xF0) == 0xE0 && $0.cable == 1 }
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "the glide anchors on emitter A")
        XCTAssertGreaterThan(bends.count, 0, "the glide keeps bending across boundaries — its anchor was never wrongly closed/orphaned by hold-continuity")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "the legato drone sounds on emitter B (the hold-continuity path is live)")
        assertNothingLeftSounding(e)                              // no stuck notes on either wire across every boundary + the stop flush
    }
    func testGlideAnchorsBendsAndReAnchors() {
        let cs = arpMachines()
        var g = ProcessorSlot(type: .glide); g.params.glideRange = 2; g.params.glidePriority = .last; g.params.glideReanchor = true; g.params.glideTime = 0
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [g]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func render(_ pool: NotePool, playing: Bool = true) { router.process(box: b, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag); beat += wb; ts += Double(frames) }
        render(chord([60]))    // ANCHOR 60
        render(chord([62]))    // +2 st, in range → BEND (no note-on)
        render(chord([67]))    // +7 st from the anchor → RE-ANCHOR (new note-on)
        let ons = e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertEqual(ons, [60, 67], "anchor 60, then re-anchor 67 (leap); the in-range 62 was a bend, not a note-on")
        XCTAssertTrue(e.events.contains { $0.status == 0xE0 && $0.vel != 64 }, "a non-centre pitch-bend was emitted (the glide to 62)")
        render(NotePool(), playing: false)   // stop → flush
        assertNothingLeftSounding(e)
    }
    // R2 (2026-08-30): GLIDE now sounds through the SAME output transform as every other voice — the per-scene master
    // KEY shifts its pitch (was raw source pitch → the glide played OUT OF KEY against the rest of the patch). The
    // note-off pairs on the SHIFTED note (proven by assertNothingLeftSounding — a shift on open but not close = stuck).
    func testGlideHonoursMasterKey() {
        let cs = arpMachines()
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glidePriority = .last; g.params.glideTime = 0
        let b = box(machines: cs) { $0.masterKey = 5; $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [g]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func render(_ pool: NotePool, playing: Bool = true) { router.process(box: b, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag); beat += wb; ts += Double(frames) }
        render(chord([60]))                   // ANCHOR 60 — with KEY +5 it must sound as 65
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.map { Int($0.note) }, [65], "the glide anchor is transposed by the master KEY (+5): 60 → 65")
        render(NotePool(), playing: false)    // stop → flush
        assertNothingLeftSounding(e)          // the off pairs on 65 (the shifted note), not 60
    }
    // R2 (2026-08-30): GLIDE now honours the emitter ENABLE gate like the grid — a disabled emitter silences it, and a
    // glide sustaining on an emitter that is disabled MID-PHRASE is closed (no stuck note; was: raw openVoice ignored
    // busEnabled → the glide kept sounding on a disabled emitter).
    func testGlideHonoursEmitterEnableAndClosesOnDisable() {
        let cs = arpMachines()
        let g: ProcessorSlot = { var s = ProcessorSlot(type: .glide); s.params.glideMode = .bend; s.params.glidePriority = .last; s.params.glideTime = 0; return s }()
        func mk(_ en: [Bool]) -> SnapshotBox { box(machines: cs, busEnabled: en) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [g]; return c }() } }
        let bOn = mk([true, true, true, true]), bOff = mk([false, true, true, true])
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func render(_ b: SnapshotBox, _ pool: NotePool) { router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag); beat += wb; ts += Double(frames) }
        render(bOn, chord([60]))              // anchor 60 on emitter A (enabled)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 1, "the glide sounds on the enabled emitter")
        render(bOff, chord([60]))             // DISABLE emitter A → the sustained glide must close
        assertNothingLeftSounding(e)          // the anchor's off was emitted — no stuck note on the disabled emitter
        // A FRESH glide on an already-disabled emitter never sounds.
        let e2 = RecordingEmitter(); let r2 = Router(); var d2 = KernelDiag()
        r2.process(box: bOff, pool: chord([64]), playing: true, beatPos: 0, tempo: tempo, sampleRate: sr, timestampSample: 0, frameCount: frames, out: e2, diag: &d2)
        XCTAssertEqual(e2.ons.filter { $0.cable == 1 }.count, 0, "a disabled emitter silences the glide entirely")
    }
    // E1 FIX (Paul 2026-08-27): a BEND-mode glide left the pitch wheel OFF-CENTRE on a flush edge (transport stop /
    // scene flush / panic / latch) — flushGlide cleared SYNTH's CC65 but never re-centred BEND, so the NEXT note on
    // that channel played detuned. flushGlide must re-centre the wheel (bend 8192) on the edge.
    func testGlideBendReCentresOnTransportStop() {
        let cs = arpMachines()
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glideRange = 12; g.params.glidePriority = .last; g.params.glideTime = 0
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [g]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func render(_ pool: NotePool, playing: Bool = true) { router.process(box: b, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag); beat += wb; ts += Double(frames) }
        render(chord([60]))                   // ANCHOR 60
        render(chord([64]))                   // +4 st, in range → BEND the wheel off-centre
        XCTAssertTrue(e.events.contains { ($0.status & 0xF0) == 0xE0 && $0.vel != 64 }, "the glide bent the wheel off-centre")
        let before = e.events.count
        render(NotePool(), playing: false)    // STOP → flush
        let flushed = e.events.suffix(from: before)
        XCTAssertTrue(flushed.contains { ($0.status & 0xF0) == 0xE0 && $0.note == 0 && $0.vel == 64 },
                      "the flush re-centres the pitch wheel (bend 8192 → data 0,64) — was left bent before the E1 fix")
        assertNothingLeftSounding(e)
    }
    // METER-TRUTH (Paul 2026-08-25): GLIDE emits its note-on via a direct openVoice (it bypasses emitArtic/emitOneBus),
    // so before the `meter` opt-in it sounded WITHOUT lighting the emitter strip. Prove the note-on now meters on its bus.
    func testGlideLightsTheEmitterMeter() {
        let cs = arpMachines()
        var g = ProcessorSlot(type: .glide); g.params.glideRange = 2; g.params.glideTime = 0
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [g]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func render(_ pool: NotePool) { router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag); beat += wb; ts += Double(frames) }
        render(chord([60]))                    // ANCHOR 60 (vel 100) → a note-on on emitter A (bus 0)
        let m = router.drainMeters()
        XCTAssertGreaterThan(m.events[0], 0, "GLIDE's note-on lights emitter A's meter (meter-truth: no emission without a meter event)")
        XCTAssertGreaterThan(Int(m.peak[0]), 0, "the meter carries the note's velocity")
        XCTAssertEqual(router.drainMeters().events[0], 0, "read-and-clear")
        render(NotePool()); router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }
    // GLIDE SYNTH mode (Paul 2026-08-22): drive the synth's own portamento — CC65 on + CC5 time, then legato note
    // transitions (new note opens before old closes), NO pitch-bend.
    func testGlideSynthModeSendsPortamentoCCsAndTransitionsLegato() {
        let cs = arpMachines()
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .synth; g.params.glidePriority = .last; g.params.glideTime = 0.5
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [g]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func render(_ pool: NotePool, playing: Bool = true) { router.process(box: b, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag); beat += wb; ts += Double(frames) }
        render(chord([60]))    // ANCHOR: CC65 on + CC5 time + note-on 60
        render(chord([64]))    // legato transition to 64 (the synth glides)
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 && $0.vel == 127 }, "CC65 portamento ON")
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 5 }, "CC5 portamento time")
        XCTAssertFalse(e.events.contains { $0.status == 0xE0 }, "SYNTH mode emits NO pitch-bend")
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.map { Int($0.note) }, [60, 64], "each target is its own legato note-on")
        let onIdx = e.events.firstIndex { $0.status == 0x90 && $0.note == 64 }!
        let offIdx = e.events.firstIndex { $0.status == 0x80 && $0.note == 60 }!
        XCTAssertLessThan(onIdx, offIdx, "the new note opens before the old closes (legato → the synth portamentos)")
        render(NotePool(), playing: false)
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 && $0.vel == 0 }, "SYNTH clears portamento (CC65=0) on teardown — else it pollutes every later note on the channel (review fix)")
        assertNothingLeftSounding(e)
    }
    // GLIDE STEP mode (Paul 2026-08-22): a fast chromatic run source→target — one short note per semitone, target held.
    func testGlideStepModeRunsChromaticallyToTheTarget() {
        let cs = arpMachines()
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .step; g.params.glidePriority = .last; g.params.glideTime = 0.4
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [g]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func render(_ pool: NotePool, playing: Bool = true) { router.process(box: b, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag); beat += wb; ts += Double(frames) }
        render(chord([60]))                     // ANCHOR 60 held
        for _ in 0..<6 { render(chord([64])) }  // NEW TARGET 64 → chromatic run 61,62,63 → target 64, over glideTime
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertTrue(notes.isSuperset(of: [60, 61, 62, 63, 64]), "the zipper steps chromatically through 61,62,63 to the target 64 (got \(notes.sorted()))")
        XCTAssertFalse(e.events.contains { $0.status == 0xE0 }, "STEP mode emits NO pitch-bend")
        render(NotePool(), playing: false)
        assertNothingLeftSounding(e)
    }
    func testArpThenGlideSynthDrivenSendsPortamentoCCsNoBend() {
        // [ARP→GLIDE SYNTH] (Paul 2026-08-26 driven-path mode-awareness): the driver feeds GLIDE's mono voice; SYNTH sends
        // CC65/CC5 + legato transitions, NO pitch-bend — was BEND-only on the driven path.
        let cs = arpMachines()
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .synth; g.params.glideTime = 0.3
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, g]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 }, "SYNTH driven → CC65 portamento ON")
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 5 }, "SYNTH driven → CC5 time")
        XCTAssertFalse(e.events.contains { $0.status == 0xE0 }, "SYNTH driven → no pitch-bend")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 1, "the driver's walk emits legato note-ons")
        assertNothingLeftSounding(e)
    }
    func testArpThenGlideStepDrivenZippersNoBend() {
        // [ARP→GLIDE STEP] driven: each driver transition zippers chromatically (intermediate short notes), no bend.
        let cs = arpMachines()
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_4
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .step; g.params.glideTime = 0.2
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, g]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 67]), beats: 4, into: e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertTrue(notes.contains(63) || notes.contains(64), "STEP driven zippers through intermediate semitones (got \(notes.sorted()))")
        XCTAssertFalse(e.events.contains { $0.status == 0xE0 }, "STEP driven → no pitch-bend")
        assertNothingLeftSounding(e)
    }
    /// Sweeping the TARGET CC# past a control (VOLUME/CC7) must REVERT it to its standard (127), not leave it knocked
    /// down — the abandoned-target guard (user 2026-08-10).
    func testModTargetChangeRevertsAbandonedCC() {
        func modBox(_ cc: Int) -> SnapshotBox {
            let cs = arpMachines()
            var mod = ProcessorSlot(type: .mod); mod.params.modSource = .shape; mod.params.modShape = .ramp
            mod.params.modMin = 0; mod.params.modMax = 100; mod.params.modCC = cc
            return box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func render(_ b: SnapshotBox) { router.process(box: b, pool: chord([60]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag); beat += wb; ts += Double(frames) }
        for _ in 0..<3 { render(modBox(7)) }    // target = VOLUME (emits low CC7)
        for _ in 0..<3 { render(modBox(74)) }   // target sweeps to CUTOFF — CC7 must be reverted
        let cc7 = e.events.filter { $0.status == 0xB0 && $0.note == 7 }
        XCTAssertEqual(cc7.last?.vel, 127, "leaving CC7 as the target reverts VOLUME to its standard (127)")
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

    // MODE ROW: the driver-not-tail fold also covers RATCHET. [ratchet → closed gate] gates every re-strike →
    // silence; [ratchet → open gate] re-strikes as a plain ratchet (the gate is transparent).
    // COIN — SHAPING THE DICE (Paul 2026-08-26): SIZE WEIGHTS change the audible burst length (size-8 bursts more notes
    // than size-2); QUOTA caps the fires per row; replay-exact. Proves the engine reads the new fields end-to-end.
    func testRatchetCoinSizeWeightsAndQuota() {
        func onCount(weights: [Int]? = nil, quota: Int? = nil) -> Int {
            var c = Machine(machineID: "gold", type: .ratchet)
            c.paramsA.rtcMode = .coin; c.paramsA.rtcChance = 1.0     // every step bursts
            if let weights { c.paramsA.rtcSizeWeights = weights }
            if let quota { c.paramsA.rtcQuota = quota }
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            // across the ROW so consecutive columns (= consecutive coin STEPS) fire — exercises quota-per-row
            let b = box(machines: cs) { s in for col in 0..<8 { s.cells[col][0] = Cell(machineID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 8, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let small = onCount(weights: [1, 0, 0, 0, 0])   // always size 2
        let big = onCount(weights: [0, 0, 0, 0, 1])     // always size 8
        XCTAssertGreaterThan(big, small, "size-8 weights burst more notes than size-2")
        XCTAssertEqual(small, onCount(weights: [1, 0, 0, 0, 0]), "replay-exact")
        XCTAssertLessThan(onCount(quota: 2), onCount(), "QUOTA ~2 fires fewer bursts than FREE")
    }
    // RIFF (SPEC-riff-processor): the stored RANK stencil follows the held chord — the SAME riff plays Cm's notes over Cm
    // and F's notes over F (zero pitches stored). Ranks 1·2·3 cover the 3-note chord; nothing left sounding.
    func testRiffFollowsTheHeldChord() {
        func played(_ notes: [UInt8]) -> Set<UInt8> {
            var c = Machine(machineID: "gold", type: .riff)
            c.paramsA.riffRanks = [1, 2, 3, 1, 2, 3, 1, 2]; c.paramsA.riffSteps = 8; c.paramsA.riffRate = .r1_8; c.paramsA.riffWrap = .fold
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord(notes), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        }
        let cm = played([60, 63, 67])   // Cm
        let f = played([65, 69, 72])    // F
        XCTAssertEqual(cm, Set([60, 63, 67]), "the riff plays Cm's three notes")
        XCTAssertEqual(f, Set([65, 69, 72]), "the SAME stencil plays F's notes — chord-following, no pitches stored")
        XCTAssertNotEqual(cm, f, "a different chord → different pitches")
    }
    // (RIFF CAPTURE test removed 2026-09-10 — the §2 capture feature was deleted.)
    // SPAN RE-ANCHOR (Paul 2026-08-27, the universal re-sync model — riff is the first card): a 3-step stencil [1,2,3]
    // FREE-runs and cycles all three chord notes across the row; SPAN=1 re-syncs the stencil to step 0 EVERY column, so
    // only step 0 (rank 1 = the lowest note) ever plays. One step per column (riffRate == stepRate == 1/8 = 0.5 beat).
    func testRiffSpanReAnchorsTheStencil() {
        func played(spanN: Int?) -> [Int] {
            var c = Machine(machineID: "gold", type: .riff)
            c.paramsA.riffRanks = [1, 2, 3]; c.paramsA.riffSteps = 3; c.paramsA.riffRate = .r1_8; c.paramsA.riffWrap = .fold
            c.paramsA.riffSpanN = spanN
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { s in
                s.stepRate = .r1_8                                       // 0.5-beat columns == the riff rate → one step per column
                for col in 0..<8 { s.cells[col][0] = Cell(machineID: "gold", buses: [.a]) }   // the whole row → the stencil plays continuously
            }
            let e = RecordingEmitter(); run(b, chord([60, 62, 64]), beats: 4, into: e)   // 8 columns
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        }
        let free = played(spanN: nil)     // FREE (default — free-run, byte-identical to before the feature)
        let span1 = played(spanN: 1)      // re-anchor every column
        XCTAssertEqual(Set(free), Set([60, 62, 64]), "FREE: the 3-step stencil cycles all three notes across the row — got \(free)")
        XCTAssertEqual(Set(span1), Set([60]), "SPAN=1: re-anchored EVERY column → only step 0 (the lowest, 60) ever plays — got \(span1)")
        XCTAssertNotEqual(free, span1, "the re-anchor demonstrably changes the sequenced output")
    }
    // Paul 2026-08-25 bug repro: a stencil of ALL rank-1, holding C+E, must be a STREAM of C (the lowest held note) —
    // not an alternation between C and E. Every step resolves rank 1 → asc(0) → the lowest note.
    func testRiffAllRankOnePlaysOnlyTheLowestNote() {
        var c = Machine(machineID: "gold", type: .riff)
        c.paramsA.riffRanks = [1, 1, 1, 1, 1, 1, 1, 1]; c.paramsA.riffSteps = 8; c.paramsA.riffRate = .r1_8; c.paramsA.riffWrap = .fold
        let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64]), beats: 2, into: e)
        assertNothingLeftSounding(e)
        let notes = e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertFalse(notes.isEmpty, "the riff sounds")
        XCTAssertTrue(notes.allSatisfy { $0 == 60 }, "every rank-1 tick plays the LOWEST held note (C=60), never E(64) — got \(notes)")
    }
    // DIRECTION (Paul 2026-09-16): the stencil plays FORWARD (default) · REVERSE · PING-PONG. REVERSE walks the steps backwards.
    func testRiffDirectionReversesTheStencil() {
        func notes(_ dir: RiffDir) -> [Int] {
            var c = Machine(machineID: "gold", type: .riff)
            c.paramsA.riffRanks = [1, 2, 3, 4]; c.paramsA.riffSteps = 4; c.paramsA.riffRate = .r1_8; c.paramsA.riffWrap = .clamp; c.paramsA.riffDir = dir
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 62, 64, 65]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        }
        let fwd = notes(.forward), rev = notes(.reverse)
        XCTAssertEqual(fwd.first, 60, "FORWARD opens on step 0 (rank 1 = lowest = 60)")
        XCTAssertEqual(rev.first, 65, "REVERSE opens on the LAST step (rank 4 = 65)")
        XCTAssertNotEqual(fwd, rev, "the playback order is reversed")
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
    func testRiffPendulumBouncesEachEndOnce() {
        // n=8, cycle 2n-2=14: 1,2,3,4,5,6,7,8,7,6,5,4,3,2, then repeats. `.r1_16` = 0.25 beat/tick; 6 beats = 24
        // ticks, comfortably more than one period.
        let seq = riffDirNotes(.pendulum)
        XCTAssertEqual(Array(seq.prefix(14)), [1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4, 3, 2],
                       "PENDULUM bounces, each end played once, cycle 2n-2")
    }
    func testRiffPendulumWithTwoStepsDegeneratesToForward() {
        XCTAssertEqual(riffDirNotes(.pendulum, steps: 2, beats: 4), riffDirNotes(.forward, steps: 2, beats: 4),
                       "PENDULUM with n=2 behaves exactly like FORWARD")
    }
    func testRiffPingPongBouncesEachEndTwice() {
        // cycle 2n=16: 1,2,3,4,5,6,7,8,8,7,6,5,4,3,2,1, then repeats.
        let seq = riffDirNotes(.pingpong)
        XCTAssertEqual(Array(seq.prefix(16)), [1, 2, 3, 4, 5, 6, 7, 8, 8, 7, 6, 5, 4, 3, 2, 1],
                       "PING-PONG bounces, each end played twice, cycle 2n")
    }
    func testRiffRandomIsSeedRepeatableAndStaysInRange() {
        let a1 = riffDirNotes(.random, seed: 111), a2 = riffDirNotes(.random, seed: 111), b1 = riffDirNotes(.random, seed: 222)
        XCTAssertEqual(a1, a2, "the SAME seed draws the SAME sequence — replay-exact")
        XCTAssertNotEqual(a1, b1, "a DIFFERENT seed draws a different sequence")
        XCTAssertTrue(a1.allSatisfy { (1...8).contains($0) }, "every RANDOM draw lands on a real stencil step")
    }
    func testRiffDrunkStaysInBoundsAndMovesAtMostOneStepAtATime() {
        for (seed, bias) in [(7, 0.0), (13, 0.6), (99, -0.6), (1, 1.0)] {
            let seq = riffDirNotes(.drunk, seed: seed, bias: bias, beats: 16)
            XCTAssertTrue(seq.allSatisfy { (1...8).contains($0) }, "DRUNK never wanders outside the stencil (seed \(seed))")
            for i in 1..<seq.count {
                XCTAssertLessThanOrEqual(abs(seq[i] - seq[i - 1]), 1, "DRUNK moves at most one step at a time (seed \(seed), index \(i))")
            }
        }
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
    // DEAL (Paul 2026-09-16): a note-transparent output dealer — OVERRIDE the emitters, deal N1 → emitter 1, N2 → emitter 2.
    func testDealOverridesEmittersAndSplitsAChord() {
        var deal = ProcessorSlot(type: .deal)
        deal.params.dealE1 = 0; deal.params.dealE2 = 1; deal.params.dealN1 = 1; deal.params.dealN2 = 1; deal.params.dealMode = .withinChord
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b, .c, .d]); c.processors = [deal]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 2, into: e)
        assertNothingLeftSounding(e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "WITHIN CHORD deals some notes to emitter A (cable 1)")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "and some to emitter B (cable 2)")
        XCTAssertEqual(e.ons.filter { $0.cable == 3 || $0.cable == 4 }.count, 0, "the deal OVERRIDES the cell's emitters — nothing on C/D")
    }
    func testDealOverTimeHandsOffAcrossStrikes() {
        var arp = ProcessorSlot(type: .arp); arp.params.pattern = .up; arp.params.rate = .r1_8; arp.params.phase = .free
        var deal = ProcessorSlot(type: .deal); deal.params.dealE1 = 0; deal.params.dealE2 = 1; deal.params.dealMode = .overTime
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, deal]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
        assertNothingLeftSounding(e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "OVER TIME hands successive arp strikes to A")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "and to B")
    }
    // RIFF STAGE 2 (Paul 2026-08-26): POLY strikes a SET of ranks per step (a chord that follows the held chord).
    func testRiffPolyStrikesTheRankSet() {
        var c = Machine(machineID: "gold", type: .riff)
        c.paramsA.riffPoly = true; c.paramsA.riffSteps = 4; c.paramsA.riffRate = .r1_8; c.paramsA.riffWrap = .fold
        c.paramsA.riffMask = [5, 5, 5, 5]   // bits 0 and 2 set ⇒ ranks 1 and 3 together
        let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e); assertNothingLeftSounding(e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertTrue(notes.contains(60) && notes.contains(67), "a POLY step strikes rank 1 (60) AND rank 3 (67) together")
        XCTAssertFalse(notes.contains(64), "rank 2 (64) is not in the mask → not struck")
    }
    // §5 TIE: a tie step suppresses its own attack; the previous note sustains → fewer note-ons than the untied stencil.
    func testRiffTieSuppressesAttack() {
        func onCount(tie: Bool) -> Int {
            var c = Machine(machineID: "gold", type: .riff)
            c.paramsA.riffSteps = 2; c.paramsA.riffRate = .r1_4; c.paramsA.riffWrap = .fold; c.paramsA.riffRanks = [1, 2]
            if tie { c.paramsA.riffTie = [false, true] }
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertLessThan(onCount(tie: true), onCount(tie: false), "a TIE step suppresses its own attack — fewer note-ons")
    }
    // §5 TIE, DIRECTION-AWARE (Paul 2026-09-28): regression for a bug predating the 6-mode DIRECTION widening — the
    // TIE lookahead always checked array-index `step+1` regardless of playback direction, so a tie painted on
    // REVERSE's TRUE next-played step (step-1, not step+1) was silently ignored. n=4 REVERSE plays step 3,2,1,0,
    // repeating — tying step 2 (what REVERSE actually plays right after step 3) must suppress step 2's own attack;
    // the pre-fix bug would have checked step 0 instead (found no tie there) and struck step 2 regardless.
    func testRiffTieRespectsReverseDirection() {
        func onCount(tie: Bool) -> Int {
            var c = Machine(machineID: "gold", type: .riff)
            c.paramsA.riffSteps = 4; c.paramsA.riffRate = .r1_4; c.paramsA.riffWrap = .fold
            c.paramsA.riffRanks = [1, 2, 3, 4]; c.paramsA.riffDir = .reverse
            if tie { c.paramsA.riffTie = [false, false, true, false] }
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 62, 64, 66]), beats: 4, into: e, forceColumn: 0); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertLessThan(onCount(tie: true), onCount(tie: false),
                           "tying REVERSE's true next-played step (step 2, reached right after step 3) suppresses its attack")
    }
    // §5 SLIDE: a slide step arms the synth portamento (CC65=127); the next non-slide step clears it (CC65=0).
    func testRiffSlideArmsAndClearsPortamento() {
        var c = Machine(machineID: "gold", type: .riff)
        c.paramsA.riffSteps = 2; c.paramsA.riffRate = .r1_4; c.paramsA.riffWrap = .fold; c.paramsA.riffRanks = [1, 2]
        c.paramsA.riffSlide = [true, false]
        let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64]), beats: 2, into: e); assertNothingLeftSounding(e)
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 && $0.vel == 127 }, "SLIDE arms portamento CC65=127")
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 && $0.vel == 0 }, "the non-slide step after clears CC65=0")
    }
    // §5 SLIDE, DIRECTION-AWARE (Paul 2026-09-28): the SLIDE-side mirror of the TIE lookahead bug above — the
    // portamento-clear lookBACK always checked array-index `step-1`, already wrong for REVERSE (whose true previous
    // step is `step+1`, not `step-1`). n=4 REVERSE plays step 3,2,1,0, repeating — slide-tagging step 1 arms CC65
    // when step 1 strikes; step 0 (REVERSE's true NEXT step after step 1) must clear it. The pre-fix bug would have
    // checked step 3 for "was the previous step a slide", found none, and left the portamento wrongly armed.
    func testRiffSlideRespectsReverseDirection() {
        var c = Machine(machineID: "gold", type: .riff)
        c.paramsA.riffSteps = 4; c.paramsA.riffRate = .r1_4; c.paramsA.riffWrap = .fold
        c.paramsA.riffRanks = [1, 2, 3, 4]; c.paramsA.riffDir = .reverse
        c.paramsA.riffSlide = [false, true, false, false]   // step 1 slides
        let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 62, 64, 66]), beats: 4, into: e, forceColumn: 0); assertNothingLeftSounding(e)
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 && $0.vel == 127 }, "step 1 (slide) arms portamento CC65=127")
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 && $0.vel == 0 }, "step 0 (REVERSE's true next step) clears CC65=0")
    }
    // Variable length (Paul 2026-08-26): a stencil longer than 16 steps is not truncated — step 20 of a 24-step stencil
    // still fires (the old min(16,...) cap would fold it to step 4). RIFF across the whole row so it ticks continuously.
    func testRiffVariableLengthBeyond16() {
        var c = Machine(machineID: "gold", type: .riff)
        c.paramsA.riffSteps = 24; c.paramsA.riffRate = .r1_16; c.paramsA.riffWrap = .fold
        var ranks = [Int](repeating: 0, count: 24); ranks[20] = 1   // ONLY step 20 fires
        c.paramsA.riffRanks = ranks
        let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
        let b = box(machines: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(machineID: "gold", buses: [.a]) } }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e); assertNothingLeftSounding(e)
        XCTAssertFalse(e.ons.filter { $0.cable == 1 }.isEmpty, "step 20 of a 24-step stencil fires — not capped at 16")
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
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 1, steps: 1, useRiff: false, litNotes: 0b0000_0011, riffOn: true, sourceMode: .midi)]
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
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                                 useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8,
                                                 resetSteps: resetSteps)]
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
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                                 useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8,
                                                 resetSteps: 1)]
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
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 5, steps: 16, rate: .r1_16,
                                                 useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8,
                                                 resetSteps: 1)]
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
            let red = EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                  useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8, resetSteps: 1)
            let blue = EuclidLine(target: 0, pulses: 5, steps: 16, rate: .r1_16,
                                   useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8, resetSteps: 1)
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
    func testEuclideousPerLaneResetRealignsAtTheLanesSequencersOwnLoopBoundaryNotJustAnUnboundedPeriod() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        func picksThroughBar(resetSteps: Int, lenSteps: Int, beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            // 3-of-8 at 1/8 (a lap = one bar) so the pre-feature reset migrates EXACTLY under the LANES GRID (2026-10-18); the 3-of-5 lane this test used has
            // a 2.5-beat lap, whose nearest restart unit is not the old 1-bar step (§6.2: reported, not papered over).
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                                 useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8,
                                                 resetSteps: resetSteps)]
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                  scenes: [{ var s = SceneState.empty()
                                      s.stepRate = .r1_8
                                      s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                      return s }()])
            st.euclideousNoteSource = .midi
            st.euclideousLanesSeqRate = .oneBar
            st.euclideousLanesSeqLen = lenSteps
            let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord(pool), beats: beats, into: e, forceColumn: 0)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)) }
        }
        // NOTE (2026-10-18): this test used resetSteps=3, which is NOT a valid reset (`resetStepsResolved`'s domain is {0,1,2,4,8}; 3 resolves to OFF), so it
        // never exercised a restart at all — it passed only because the old 3-of-5 lane happened to line up every 5 bars. resetSteps=2 over LEN=5 is the real
        // case: marks at steps 1, 3, 5 of the lap (bits 0, 2, 4), then the next lap restarts fresh at its step 0.
        let bar1 = picksThroughBar(resetSteps: 2, lenSteps: 5, beats: 3.9)
        let throughBar6 = picksThroughBar(resetSteps: 2, lenSteps: 5, beats: 23.9)
        XCTAssertFalse(bar1.isEmpty)
        XCTAssertEqual(Array(throughBar6.suffix(bar1.count)), bar1,
                       "LEN=5 doesn't divide resetSteps=2 — bar 6 begins a new lap and must restart fresh at " +
                       "local step 0, replaying bar 1's exact pick sequence, not continue the step-3-anchored " +
                       "cycle an unbounded (LEN-oblivious) formula would produce instead")
    }
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
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8,
                                             useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8,
                                             resetSteps: 2)]
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
        func ranksStruck(lock: Bool, beats: Double) -> [Int] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])   // identity: riff step i ↔ rank i+1 ↔ pool[i]
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 5, rate: .r1_8, useRiff: true, riffLock: lock)]
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
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 5, rate: .r1_8, useRiff: true, riffDir: .random, riffDirSeed: 7, riffLock: true)]
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
            c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 4, rate: .r1_8, useRiff: true, riffRotate: 2, riffLock: true)]
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
    func testEuclideousRiffLockReverseRestartsAtItsOwnNaturalAnchorPlusShift() {
        let pool: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        // LENGTH 5, SHIFT 1: REV's walkPos at ord=0 is (length-1)=4; played step = (4+1) mod 5 = 0 → rank 1.
        c.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 4, rate: .r1_8, useRiff: true, riffRotate: 1, riffDir: .reverse, riffLock: true, riffLength: 5)]
        let b = box(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord(pool), beats: 1.9, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let ranks = e.ons.filter { $0.cable == 1 }.compactMap { ev in pool.firstIndex(of: UInt8(ev.note)).map { $0 + 1 } }
        XCTAssertEqual(ranks.first, 1, "REV's own anchor (length-1=4) + shift(1) mod length(5) = 0 → rank 1, not a forced 0+shift")
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
    // SEQUENTIAL SOURCES (Paul 2026-10-02): EUCLID reads an immediately-preceding, non-bypassed RIFF or ARP as a
    // note source — each hit steps through that predecessor's own authored sequence by hit-ordinal, instead of
    // picking from the held chord. Stateless (the existing per-line `ord` — already driving CYCLE/RANDOM — is
    // reused unmodified), adjacency-only (not a general upstream scan), and silent (not a crash/fallback) whenever
    // the predecessor doesn't match.
    func testEuclidReadsRiffSequenceSkippingRests() {
        var riff = ProcessorSlot(type: .riff)
        riff.params.riffSteps = 8
        riff.params.riffRanks = [1, 0, 2, 3, 0, 2, 0, 1]   // non-rest steps: 0(rank1) 2(rank2) 3(rank3) 5(rank2) 7(rank1)
        var euclid = ProcessorSlot(type: .euclid)
        euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .riff)]   // K=N=8: every tick hits, isolating the sequence walk
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riff, euclid]; return c }() }
        // forceColumn: 0 (PLAY: THIS CELL) bypasses the column-lap gate — without it a bare cell only ticks during
        // its own grid column's real-time span, too short to reach a 2nd lap of the 5-element non-rest sequence
        // (same reason testEuclidPingPongDoublesHitsOverAFullLap needs it).
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e, forceColumn: 0); assertNothingLeftSounding(e)
        let seq = e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map { Int($0.note) }
        XCTAssertEqual(Array(seq.prefix(10)), [60, 64, 67, 64, 60, 60, 64, 67, 64, 60],
                       "EUCLID steps through RIFF's own non-rest ranks in authored order, wrapping by the non-rest count — not picking from the pool by rank/cycle/random")
    }
    func testEuclidReadsArpSequenceInOrder() {
        var arp = ProcessorSlot(type: .arp); arp.params.pattern = .up
        var euclid = ProcessorSlot(type: .euclid)
        euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .arp)]
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, euclid]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e)
        let seq = e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map { Int($0.note) }
        XCTAssertEqual(Array(seq.prefix(6)), [60, 64, 67, 60, 64, 67], "EUCLID steps through ARP's own UP pattern by hit-ordinal, exactly as arpPick(phaseIndex:) would resolve it directly")
    }
    func testEuclidReadsArpRandomOnceSeedDeterministically() {
        func seqFor(seed: Int) -> [Int] {
            var arp = ProcessorSlot(type: .arp); arp.params.pattern = .randomOnce; arp.params.arpSeed = seed
            var euclid = ProcessorSlot(type: .euclid)
            euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .arp)]
            let cs = arpMachines()
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, euclid]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map { Int($0.note) }
        }
        let a1 = seqFor(seed: 42), a2 = seqFor(seed: 42), b1 = seqFor(seed: 99)
        XCTAssertFalse(a1.isEmpty)
        XCTAssertEqual(a1, a2, "the same RANDOM ONCE seed reproduces the identical EUCLID-walked sequence — arpPick is a pure hash of (phaseIndex, seed), no accumulated state")
        XCTAssertNotEqual(a1, b1, "a different seed shuffles the walked sequence differently")
    }
    // REWRITTEN (Paul 2026-10-02, DIE removed — "drop it, please"): the original test used two lines with
    // identical K/N but different DIE to prove independent phasing; with DIE gone, two identical lines would now
    // be byte-identical by construction (nothing left to tell them apart), so this instead gives the two lines
    // DIFFERENT densities (K=8 dense vs. K=3 a real Euclidean subset). NOT an exact union-count comparison — first
    // draft tried that and tripped the PRE-EXISTING, documented `lastTick[row]` dedup-across-a-window-boundary
    // quirk (runEuclidLine's own doc comment: "a known limitation for 2+ real lines sharing a row," the exact
    // mechanism `testEuclidPulsesFromPoolTracksHeldCount` already guards elsewhere) — two REAL lines on one row
    // can legitimately land a couple of counts off an exact solo-union once ticks straddle a render window, with
    // nothing to do with DIE or independence. Weakened to the robust claim that's actually load-bearing here:
    // neither line SUPPRESSES the other when run together (a genuine coupling bug — e.g. line2 silently
    // continuing line1's walk instead of running its own — would collapse toward one line's solo count, not add).
    func testEuclidTwoLinesSameRiffPredecessorBothContribute() {
        func riffSlot() -> ProcessorSlot {
            var riff = ProcessorSlot(type: .riff)
            riff.params.riffSteps = 4
            riff.params.riffRanks = [1, 2, 3, 0]   // non-rest: rank1(60) rank2(64) rank3(67)
            return riff
        }
        func noteCount(_ lines: [EuclidLine]) -> Int {
            var euclid = ProcessorSlot(type: .euclid); euclid.params.euclidLines = lines
            let cs = arpMachines()
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riffSlot(), euclid]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let line1 = EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .riff)   // dense: every tick hits
        let line2 = EuclidLine(target: 0, pulses: 3, steps: 8, noteSel: .riff)   // a real, sparser K-of-N subset
        let solo1 = noteCount([line1]), solo2 = noteCount([line2])
        XCTAssertGreaterThan(solo1, 0); XCTAssertGreaterThan(solo2, 0)
        let combined = noteCount([line1, line2])
        XCTAssertGreaterThan(combined, solo1, "line 2 adds its own notes on top of line 1's, rather than silently replacing them")
        XCTAssertGreaterThan(combined, solo2, "line 1 adds its own notes on top of line 2's, rather than silently replacing them")
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
    // EUCLID BEACON READINESS (Paul 2026-10-05, "please fix that bug" — closing the beacon's own disclosed gap:
    // "doesn't walk RIFF/ARP's own resolved note... reads the door's raw held notes, not the fully-resolved
    // upstream-chain pool"). These exercise `Router.euclidLineReadyAt` directly — the render-thread-computed
    // readout GridUI's beacon now polls instead of approximating from a door's raw note count. Bit 0 = line
    // index 0's HIT bit (the only line/side each of these tests uses).
    func testEuclidBeaconReadinessOffWhenVelocityZero() {
        func readiness(velocity: Double) -> UInt8 {
            var euclid = ProcessorSlot(type: .euclid)
            euclid.params.euclidLines = [EuclidLine(pulses: 8, steps: 8, noteSel: .low, velocity: velocity)]
            let cs = arpMachines()
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [euclid]; return c }() }
            let e = RecordingEmitter()
            let router = runKeepingRouter(b, chord([60, 64, 67]), beats: 1, into: e)
            return router.euclidLineReadyAt(0)
        }
        XCTAssertEqual(readiness(velocity: 0) & 0b01, 0, "velocity 0 means this line's HIT can never actually sound (strikeChord's clampVel floor would otherwise mask it, per runEuclidLine's own 'VELOCITY 0 = EFFECTIVELY OFF' guard) — the beacon must not flash for it")
        XCTAssertNotEqual(readiness(velocity: 1) & 0b01, 0, "sanity: the identical line at velocity 1 reads TRUE — the difference above is the velocity guard, not some other factor")
    }
    func testEuclidBeaconReadinessUsesComposedPoolNotRawDoorCount() {
        func readiness(chanceProbability: Double) -> UInt8 {
            var chance = ProcessorSlot(type: .chance)
            chance.params.probability = chanceProbability
            var euclid = ProcessorSlot(type: .euclid)
            euclid.params.euclidLines = [EuclidLine(pulses: 8, steps: 8, noteSel: .low, velocity: 1)]
            let cs = arpMachines()
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [chance, euclid]; return c }() }
            let e = RecordingEmitter()
            let router = runKeepingRouter(b, chord([60, 64, 67]), beats: 1, into: e)
            return router.euclidLineReadyAt(0)
        }
        XCTAssertEqual(readiness(chanceProbability: 0) & 0b01, 0, "a [CHANCE(0%)→EUCLID] chain deterministically empties the pool feeding EUCLID — readiness must read FALSE even though the door's own raw held chord has 3 notes; this is exactly the 'fully-resolved upstream pool, not the door's raw notes' gap the beacon used to have")
        XCTAssertNotEqual(readiness(chanceProbability: 1) & 0b01, 0, "sanity: the identical chain with CHANCE fully open reads TRUE — the difference above is the upstream fold, not some other factor")
    }
    func testEuclidBeaconReadinessRequiresRiffArpPredecessorToHaveAnAvailableNote() {
        // RIFF: an all-rest predecessor pattern must read not-ready even though the door holds a healthy chord —
        // mirrors testEuclidRiffAllRestPredecessorIsSilentNotACrash's own repro shape.
        var riffAllRest = ProcessorSlot(type: .riff)
        riffAllRest.params.riffSteps = 4
        riffAllRest.params.riffRanks = [0, 0, 0, 0]
        var euclidRiff = ProcessorSlot(type: .euclid)
        euclidRiff.params.euclidLines = [EuclidLine(pulses: 8, steps: 8, noteSel: .riff, velocity: 1)]
        let cs = arpMachines()
        let b1 = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riffAllRest, euclidRiff]; return c }() }
        let e1 = RecordingEmitter()
        let r1 = runKeepingRouter(b1, chord([60, 64, 67]), beats: 1, into: e1)
        XCTAssertEqual(r1.euclidLineReadyAt(0) & 0b01, 0, "an all-rest RIFF predecessor has no non-rest step to walk — readiness must read FALSE, not just 'predecessor type matches'")

        // Same RIFF predecessor shape, but WITH a real non-rest step — readiness must flip to TRUE.
        var riffHasHits = ProcessorSlot(type: .riff)
        riffHasHits.params.riffSteps = 4
        riffHasHits.params.riffRanks = [1, 0, 0, 0]
        let b2 = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riffHasHits, euclidRiff]; return c }() }
        let e2 = RecordingEmitter()
        let r2 = runKeepingRouter(b2, chord([60, 64, 67]), beats: 1, into: e2)
        XCTAssertNotEqual(r2.euclidLineReadyAt(0) & 0b01, 0, "a RIFF predecessor with a genuine non-rest step, fed by a non-empty pool, must read TRUE")

        // ARP: the predecessor TYPE matches, but the pool feeding INTO arp's own slot is empty
        // ([CHANCE(0%)→ARP→EUCLID]) — readiness must read FALSE, not just "predecessor type matches".
        var chanceEmpty = ProcessorSlot(type: .chance); chanceEmpty.params.probability = 0
        var arp = ProcessorSlot(type: .arp); arp.params.pattern = .up
        var euclidArp = ProcessorSlot(type: .euclid)
        euclidArp.params.euclidLines = [EuclidLine(pulses: 8, steps: 8, noteSel: .arp, velocity: 1)]
        let b3 = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [chanceEmpty, arp, euclidArp]; return c }() }
        let e3 = RecordingEmitter()
        let r3 = runKeepingRouter(b3, chord([60, 64, 67]), beats: 1, into: e3)
        XCTAssertEqual(r3.euclidLineReadyAt(0) & 0b01, 0, "an ARP predecessor fed by an EMPTIED upstream pool (CHANCE at 0%) has no note to pick — readiness must read FALSE, not just 'predecessor type matches'")
    }
    func testEuclidRiffPolyStepStrikesSimultaneousChordStab() {
        var riff = ProcessorSlot(type: .riff)
        riff.params.riffSteps = 4
        riff.params.riffPoly = true
        riff.params.riffMask = [0b011, 0, 0, 0]   // step0 only: ranks 1+2 together (the sole non-rest step)
        var euclid = ProcessorSlot(type: .euclid)
        euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .riff)]
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riff, euclid]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 1, into: e); assertNothingLeftSounding(e)
        let aNotes = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(Set(aNotes.map { Int($0.note) }), [60, 64], "a POLY RIFF step strikes its whole set rank mask as a chord-stab (ranks 1+2), never rank 3 (never in the mask) nor a lone note")
        let grouped = Dictionary(grouping: aNotes.map { $0.sample }, by: { $0 })
        XCTAssertTrue(grouped.values.contains { $0.count == 2 }, "the chord-stab's two notes land on the identical sample time — genuinely simultaneous, not staggered")
    }
    func testEuclidRiffTieStepStillCountsAsStruck() {
        var riff = ProcessorSlot(type: .riff)
        riff.params.riffSteps = 4
        riff.params.riffRanks = [1, 2, 3, 2]
        riff.params.riffTie = [false, true, false, false]   // step1 (rank2) is TIE in RIFF's OWN emission — irrelevant here, never read by .riff
        var euclid = ProcessorSlot(type: .euclid)
        euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .riff)]
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riff, euclid]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 1, into: e); assertNothingLeftSounding(e)
        let seq = e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map { Int($0.note) }
        XCTAssertEqual(Array(seq.prefix(4)), [60, 64, 67, 64], "a RIFF step marked TIE is NOT a rest in riffRanks — EUCLID still strikes it on its own turn, since .riff never reads riffTie")
    }
    func testEuclidOctaveStacksAdditivelyWithRiffOwnOctLane() {
        var riff = ProcessorSlot(type: .riff)
        riff.params.riffSteps = 1
        riff.params.riffRanks = [1]
        riff.params.riffOct = [1]   // RIFF's own per-step octave: +1 (60→72)
        var euclid = ProcessorSlot(type: .euclid)
        euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .riff, octave: 1)]   // EUCLID's own per-line octave: +1 more (72→84)
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riff, euclid]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 1, into: e); assertNothingLeftSounding(e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) }), [84], "RIFF's own +1 octave and EUCLID's own +1 octave stack additively (60→72→84) — two independent shifts, not one overriding the other")
    }
    // DIE — REMOVED (Paul 2026-10-02: "drop it, please"), was testEuclidDieOffsetsTheRiffSequenceStart (die 0/1/2
    // landed on 60/64/67 respectively). Rewritten as a no-op regression guard covering the RIFF-sourced path
    // specifically — testEuclidLinesPerLinePick's own guard only covers the pool-based RANDOM pick.
    func testEuclidDieIsNowANoOpOnTheRiffSourcedPath() {
        func firstNote(die: Int) -> Int? {
            var riff = ProcessorSlot(type: .riff)
            riff.params.riffSteps = 4
            riff.params.riffRanks = [1, 2, 3, 0]   // non-rest steps: 0(rank1) 1(rank2) 2(rank3)
            var euclid = ProcessorSlot(type: .euclid)
            euclid.params.euclidLines = [EuclidLine(target: 0, pulses: 8, steps: 8, die: die, noteSel: .riff)]
            let cs = arpMachines()
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [riff, euclid]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 1, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.first.map { Int($0.note) }
        }
        XCTAssertEqual(firstNote(die: 0), 60, "die 0: the walk starts at ord 0 → non-rest step 0 → rank 1 (60)")
        XCTAssertEqual(firstNote(die: 1), 60, "die no longer offsets the walk — die 1 still starts at ord 0 → rank 1 (60), not 64")
        XCTAssertEqual(firstNote(die: 2), 60, "die no longer offsets the walk — die 2 still starts at ord 0 → rank 1 (60), not 67")
    }
    // ARP EUCLID MASK (SPEC-arp-euclid-mask) is REMOVED (Paul 2026-09-28) — fully superseded by the standalone EUCLID
    // MASK processor; see testEuclidMaskFold*/testEuclidMask* above for the surviving REST/TIE/CHORD/ROTATE coverage.
    // WAIT-vs-MARCH had no replacement (Paul: "happy to drop wait as an option" — a downstream fold can't reach a
    // driver's own phase-index) and is not tested anywhere anymore.
    // PER-PARAM LFO (Docs/PLAN-param-lfo.md, Stage 1): a gate LFO oscillates ARP note LENGTH over time; a depth-0 LFO
    // resolves away (byte-identical); the stream is replay-exact (beat-derived); nothing is left stuck across the stop.
    func testGateLFOSwingsNoteLengthAndIsByteIdenticalAtZeroDepth() {
        func runLFO(_ lfos: [ParamLFO]) -> RecordingEmitter {
            var c = Machine(machineID: "gold", type: .arp)
            c.paramsA.pattern = .up; c.paramsA.rate = .r1_16; c.paramsA.octaves = 1; c.paramsA.gate = 0.5; c.paramsA.phase = .free
            c.paramsA.paramLFOs = lfos
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e); assertNothingLeftSounding(e)
            return e
        }
        func durs(_ e: RecordingEmitter) -> [Int] {
            var out: [Int] = []
            for on in e.ons where on.cable == 1 {
                if let off = e.offs.first(where: { $0.cable == 1 && $0.note == on.note && $0.sample >= on.sample }) { out.append(Int(off.sample - on.sample)) }
            }
            return out
        }
        let none = runLFO([])
        let zero = runLFO([ParamLFO(target: "gate")])                                                        // no endpoints (from==to==nil) → filtered out
        let lfo  = runLFO([ParamLFO(target: "gate", shape: .square, period: .r1, from: 0.05, to: 1.0)])      // sweep note length short ↔ full, 1-beat square
        XCTAssertEqual(none.events, zero.events, "an endpoint-less LFO resolves away → byte-identical event stream")
        let dNone = durs(none), dLFO = durs(lfo)
        XCTAssertLessThanOrEqual(Set(dNone).count, 2, "constant gate ⇒ uniform ARP note lengths")
        XCTAssertGreaterThan(Set(dLFO).count, 1, "a gate LFO makes note LENGTH vary over time")
        XCTAssertGreaterThan((dLFO.max() ?? 0) - (dLFO.min() ?? 0), (dNone.first ?? 0) / 2, "the LFO swing is substantial")
        XCTAssertEqual(lfo.events, runLFO([ParamLFO(target: "gate", shape: .square, period: .r1, from: 0.05, to: 1.0)]).events, "the LFO stream is replay-exact (beat-derived)")
    }
    // EUCLID MASK HIT-COUNT LFO (Paul 2026-09-28): restores parity with the removed arp-embedded mask's own LFO
    // target (the old testArpMaskKLFOModulatesEuclidDensity) — a maskK LFO on the standalone processor modulates
    // the HIT COUNT (K) so the euclidean density breathes over time; an endpoint-less LFO resolves away (byte-
    // identical); nothing left stuck. Chained after an ARP driver, same pattern as the ported chord-gap test below.
    func testEuclidMaskKLFOModulatesDensity() {
        func runLFO(_ lfos: [ParamLFO]) -> RecordingEmitter {
            var arp = ProcessorSlot(type: .arp); arp.params.pattern = .up; arp.params.rate = .r1_16; arp.params.octaves = 1; arp.params.gate = 0.5; arp.params.phase = .free
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 2   // a BITING euclid mask (2 of 8)
            mask.params.paramLFOs = lfos
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e); assertNothingLeftSounding(e)
            return e
        }
        let none = runLFO([])
        let zero = runLFO([ParamLFO(target: "maskK")])
        let lfo  = runLFO([ParamLFO(target: "maskK", shape: .square, period: .r1, from: 2, to: 8)])   // sweep density: sparse (2 of 8) ↔ full (8 of 8)
        XCTAssertEqual(none.events, zero.events, "an endpoint-less maskK LFO resolves away → byte-identical")
        XCTAssertGreaterThan(lfo.ons.count, none.ons.count, "a maskK LFO opens the euclid density (more hits when K swings up)")
    }
    // EUCLID MASK GAPS = CHORD gap-stab controls (Docs/PLAN-param-lfo.md): the gap chord strike gets its own OCTAVE + VELOCITY
    // (LENGTH mirrors the driver's own gate formula). OCT −2 drops the stab two octaves (a pitch the driver's own hits never
    // produce); VEL scales it. Ported (Paul 2026-09-28) from the removed arp-embedded version to the standalone EUCLID MASK
    // processor, chained after an ARP driver — same assertions, the standalone processor's own params.
    func testEuclidMaskChordGapStabControls() {
        func run4(_ setup: (inout MachineParams) -> Void) -> RecordingEmitter {
            var arp = ProcessorSlot(type: .arp); arp.params.pattern = .up; arp.params.rate = .r1_8; arp.params.octaves = 1; arp.params.gate = 0.5; arp.params.phase = .free
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 2; mask.params.maskGap = .chord   // 6 of 8 steps strike the held chord
            setup(&mask.params)
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e)
            return e
        }
        let base = run4 { _ in }
        XCTAssertTrue(Set(base.ons.map { Int($0.note) }).contains(60), "default CHORD gap strikes the held chord at pitch")
        XCTAssertFalse(Set(base.ons.map { Int($0.note) }).contains(36), "no octave shift by default")
        let shifted = run4 { $0.maskChordOct = -2; $0.maskChordVel = 0.4 }
        let low = shifted.ons.filter { $0.note == 36 }    // 60 − 24 = the gap stab dropped two octaves (never an arp HIT here)
        XCTAssertFalse(low.isEmpty, "CHORD OCT −2 drops the gap stab two octaves (60 → 36)")
        XCTAssertTrue(low.allSatisfy { $0.vel == 40 }, "CHORD VEL 0.4 scales the gap stab velocity (100 → 40)")
    }
    // CHORD LEN (maskChordGate): the gap stab has its OWN note length, distinct from the driver's own gate. Ported
    // (Paul 2026-09-28) from the removed arp-embedded version to the standalone EUCLID MASK processor.
    func testEuclidMaskChordGapLengthIsIndependentOfDriverGate() {
        func runLen(_ g: Double) -> RecordingEmitter {
            var arp = ProcessorSlot(type: .arp); arp.params.pattern = .up; arp.params.rate = .r1_8; arp.params.octaves = 1; arp.params.gate = 0.5; arp.params.phase = .free
            var mask = ProcessorSlot(type: .euclidMask); mask.params.maskN = 8; mask.params.maskK = 2; mask.params.maskGap = .chord
            mask.params.maskChordGate = g
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [arp, mask]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e)
            return e
        }
        XCTAssertNotEqual(runLen(1.0).events, runLen(0.1).events, "CHORD LEN changes the gap-stab note length (it's not just the driver's own gate)")
    }
    // arpRate LFO wiring (Paul 2026-09-16): the rate sweeps over the ALLOWED-family ladder; the IGNORE mask is honoured.
    func testArpRateLFOSweepsAndHonoursIgnore() {
        func runLFO(_ lfos: [ParamLFO]) -> RecordingEmitter {
            var c = Machine(machineID: "gold", type: .arp)
            c.paramsA.pattern = .up; c.paramsA.rate = .r1_8; c.paramsA.octaves = 1; c.paramsA.gate = 0.5; c.paramsA.phase = .free
            c.paramsA.paramLFOs = lfos
            let cs = machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e); assertNothingLeftSounding(e)
            return e
        }
        let none = runLFO([])
        let full = runLFO([ParamLFO(target: "arpRate", shape: .square, period: .r1, from: 0, to: 17, rateIgnore: 0)])
        let normalOnly = runLFO([ParamLFO(target: "arpRate", shape: .square, period: .r1, from: 0, to: 17, rateIgnore: 0b110)])
        XCTAssertNotEqual(full.events, none.events, "an arpRate LFO changes the stream — the rate actually sweeps")
        XCTAssertNotEqual(full.events, normalOnly.events, "the IGNORE mask matters — ignoring dotted+triplet sweeps a different ladder")
        XCTAssertEqual(normalOnly.events, runLFO([ParamLFO(target: "arpRate", shape: .square, period: .r1, from: 0, to: 17, rateIgnore: 0b110)]).events, "replay-exact (beat-derived)")
    }
    // RANDOM SAFETY (Paul 2026-09-16 — device "no audio shortly after RANDOM"): RANDOM writes a fresh rolled chain onto a
    // machine that may be SOUNDING. Swapping through every archetype's rolled chain while a FAT chord is held must never
    // leave a stuck note (the "no audio" symptom = a held note the synth never releases) or a leaked voice after the flush.
    func testRandomRollChainSwapUnderFatChordNeverSticks() {
        var rng = DiceRNG(seed: 0xBADA55)
        let fat = chord([36, 40, 43, 47, 50, 53, 55, 60, 64, 67])   // a fat 10-note held chord (a big live input)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func windows(_ chain: [ProcessorSlot], _ n: Int) {
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = chain; return c }() }
            for _ in 0..<n {
                router.process(box: b, pool: fat, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, out: e, diag: &diag)
                beat += windowBeats; ts += Double(frames)
            }
        }
        for a in Dice.Archetype.allCases {                       // simulate repeated RANDOM presses mid-play
            let chain = Dice.rollArchetype(a, using: &rng).chain
            if !chain.isEmpty { windows(chain, 5) }
        }
        let stop = box(machines: machineIDs.map { Machine(machineID: $0, type: .arp) }) { _ in }
        router.process(box: stop, pool: fat, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)   // stop → flush
        assertNothingLeftSounding(e)
        XCTAssertTrue(router.quiescent, "swapping through every rolled archetype under a fat chord leaves no stuck voice")
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
    // TAP (AcceptanceCriteria-tap-processor): a mid-chain SEND — [ARP→TAP(B)] emits a copy of the stream to wire B AND
    // passes it on to wire A. No TAP → B silent; TAP to B → B carries the same notes as A; MUTE → B silent. None stuck.
    func testTapSendsACopyToAParallelWire() {
        func run2(_ withTap: Bool, to: Int = 2, mute: Bool = false) -> RecordingEmitter {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var tap = ProcessorSlot(type: .tap); tap.params.tapTo = to; tap.params.tapMute = mute
            let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
            let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = withTap ? [arp, tap] : [arp]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e); assertNothingLeftSounding(e)
            return e
        }
        XCTAssertTrue(run2(false).ons.filter { $0.cable == 2 }.isEmpty, "no TAP → nothing on wire B")
        let tapB = run2(true, to: 2)
        XCTAssertFalse(tapB.ons.filter { $0.cable == 2 }.isEmpty, "TAP to B → the copy appears on wire B")
        XCTAssertEqual(Set(tapB.ons.filter { $0.cable == 1 }.map { $0.note }), Set(tapB.ons.filter { $0.cable == 2 }.map { $0.note }), "wire B (tap) carries the same notes as wire A (passthrough)")
        XCTAssertTrue(run2(true, to: 2, mute: true).ons.filter { $0.cable == 2 }.isEmpty, "MUTE → the tap is silent")
    }
    func testTapHoldChainMirrorsToWire() {
        // TAP HOLD-PATH (Paul 2026-08-26): [HARMONIZE→TAP] has no tick driver, so it emits via emitColumnHolds — the tail
        // TAP must still mirror the harmonized set to its wire (was driver-path only).
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        var tap = ProcessorSlot(type: .tap); tap.params.tapTo = 2
        let cs = machineIDs.map { Machine(machineID: $0, type: .harmonize) }
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [harm, tap]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e); assertNothingLeftSounding(e)
        XCTAssertFalse(e.ons.filter { $0.cable == 2 }.isEmpty, "a HOLD-chain TAP mirrors to wire B")
        XCTAssertTrue(e.ons.contains { $0.cable == 2 && $0.note == 67 }, "the harmonized set (incl. 60+7=67) reaches the tap wire")
        let noTap = { () -> RecordingEmitter in
            let b2 = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [harm]; return c }() }
            let e2 = RecordingEmitter(); run(b2, chord([60, 64, 67]), beats: 2, into: e2); return e2 }()
        XCTAssertTrue(noTap.ons.filter { $0.cable == 2 }.isEmpty, "without TAP, nothing on wire B")
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
    func testRatchetThenOpenGateStillRatchets() {
        let cs = arpMachines()
        let rat = ProcessorSlot(type: .ratchet)
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 1.0   // deterministic open gate (PASSGATE removed 2026-09-28)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [rat, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 64, 67]), "an open gate after the ratchet is transparent")
        XCTAssertGreaterThan(e.ons.count, 3, "the ratchet re-strikes (more than one hit)")
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
    // §cell-edit F CHOP alt row: every slice OFF main, ON alt, routed to altDest [.c] → notes emit on Emit C
    // (cable 3), NOT on the cell's own Emit A (cable 1). (The bottom-row ALT-destination routing.)
    func testChopAltRoutesToAltDestination() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = {
            var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]
            c.chop = Chop(mainMask: 0, altMask: 0xFF, muteMask: 0, altDest: [.c])   // main OFF, alt ON → alt dest C only
            return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 3 }.count, 0, "alt slices emit on the ALT destination (Emit C)")
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "main is OFF for every slice → nothing on Emit A")
        assertNothingLeftSounding(e)
    }
    // §cell-edit F CHOP on a HOLD (passthrough/identity) cell — main/mute/alt must apply, same as a tick cell.
    func testChopAppliesToHoldCell() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = {
            var c = Cell(machineID: "gold", buses: [.a]); c.processors = []   // EMPTY chain = identity HOLD
            c.chop = Chop(mainMask: 0, altMask: 0xFF, muteMask: 0, altDest: [.c])   // main OFF, alt ON → Emit C only
            return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 3 }.count, 0, "a HOLD cell's alt slices reach the alt destination (Emit C)")
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "main OFF → the hold does not sound on Emit A")
        assertNothingLeftSounding(e)
    }
    // §cell-edit F CHOP + ECHO (user 2026-08-09 bug): echo repeats were emitted on the RAW bus, bypassing the split.
    // Now the tail inherits its source note's slice destination — [ARP→ECHO] with alt→C puts BOTH the arp dry AND its
    // echoes on Emit C (cable 3), nothing on the cell's own Emit A (cable 1).
    func testChopRoutesEchoRepeatsToTheAltDestination() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = {
            var c = Cell(machineID: "gold", buses: [.a])
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
            var e = ProcessorSlot(type: .echo); e.params.echoDelayDiv = 2; e.params.echoRepeats = 3; e.params.echoThru = true
            c.processors = [arp, e]
            c.chop = Chop(mainMask: 0, altMask: 0xFF, muteMask: 0, altDest: [.c])   // every slice → ALT dest C
            return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 8, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 3 }.count, 0, "arp + its echoes route to the ALT destination (Emit C)")
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "main OFF for every slice → NOTHING on Emit A — the echoes obey the split too")
        assertNothingLeftSounding(e)
    }
    // The classic single-slot [ECHO] hold-tail path also routes its dry + tail through the chop (was raw `bm`).
    func testChopRoutesClassicEchoToTheAltDestination() {
        let b = box(machines: echoMachines(div: 2, repeats: 3, feedDelay: 0.7, decay: 0.6)) { $0.cells[0][0] = {
            var c = Cell(machineID: "gold", buses: [.a])
            c.chop = Chop(mainMask: 0, altMask: 0xFF, muteMask: 0, altDest: [.c])
            return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 8, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 3 }.count, 0, "the classic echo (dry + tail) routes to the ALT destination")
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "main OFF → the classic echo does not sound on Emit A")
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
    // GUARD (user 2026-08-09, option A): every processor placed AFTER the driver must forward its parent's output to
    // the NEXT stage — no stage may be terminal (the ECHO `break` bug that skipped a downstream HARMONIZE). Put each
    // downstream-capable type, configured to PASS, between an arp driver and a final +12 harmonize; the harmony (72)
    // proves the probe flowed all the way through. If a future processor re-introduces a terminal break, list it here
    // and this fails.
    func testNoDownstreamProcessorTerminatesTheFold() {
        func passThrough(_ type: ProcessorType) -> ProcessorSlot {
            var s = ProcessorSlot(type: type)
            switch type {
            case .chance: s.params.probability = 1.0            // always passes
            case .harmonize: s.params.harmIntervals = [0, 0, 0] // identity (root only)
            case .echo: s.params.echoDelayDiv = 2; s.params.echoRepeats = 1; s.params.echoThru = true
            default: break
            }
            return s
        }
        for mid in [ProcessorType.chance, .harmonize, .echo] {
            let b = box(machines: arpMachines()) { $0.cells[0][0] = {
                var c = Cell(machineID: "gold", buses: [.a])
                var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
                var h = ProcessorSlot(type: .harmonize); h.params.harmIntervals = [12, 0, 0]
                c.processors = [arp, passThrough(mid), h]
                return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 4, into: e)
            XCTAssertTrue(e.ons.contains { $0.cable == 1 && $0.note == 72 },
                          "[ARP→\(mid)→HARMONIZE]: the downstream harmonize must fire — \(mid) forwarded its parent's output")
            assertNothingLeftSounding(e)
        }
    }

    // LADDER mode: at most ONE rung speaks per column. OFF = both rungs layer; ON = only the active rung
    // (topmost-occupied by default, or the scene's chosen `activeRow`); the dormant rung is silent.
    func testLadderModeMakesColumnExclusive() {
        func makeBox(ladder: Bool, active: [Int?]?) -> SnapshotBox {
            var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // rung row 0 → Emit A (cable 1)
            s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // rung row 1 → Emit B (cable 2)
            s.activeRow = active
            var st = PluginState(machines: arpMachines(), scenes: [s]); st.ladderMode = ladder
            return SnapshotBuilder.build(from: st)
        }
        let off = RecordingEmitter(); run(makeBox(ladder: false, active: nil), chord([60]), beats: 8, into: off)
        XCTAssertGreaterThan(off.ons.filter { $0.cable == 1 }.count, 0, "LADDER off: row 0 speaks")
        XCTAssertGreaterThan(off.ons.filter { $0.cable == 2 }.count, 0, "LADDER off: row 1 also speaks (layered)")
        let on = RecordingEmitter(); run(makeBox(ladder: true, active: nil), chord([60]), beats: 8, into: on)
        XCTAssertGreaterThan(on.ons.filter { $0.cable == 1 }.count, 0, "LADDER on: the default rung (topmost, row 0) speaks")
        XCTAssertTrue(on.ons.filter { $0.cable == 2 }.isEmpty, "LADDER on: the dormant rung (row 1) is silent")
        let pick = RecordingEmitter(); run(makeBox(ladder: true, active: [1]), chord([60]), beats: 8, into: pick)
        XCTAssertGreaterThan(pick.ons.filter { $0.cable == 2 }.count, 0, "LADDER on, chosen rung = row 1: it speaks")
        XCTAssertTrue(pick.ons.filter { $0.cable == 1 }.isEmpty, "the non-chosen rung (row 0) is silent")
        assertNothingLeftSounding(off); assertNothingLeftSounding(on); assertNothingLeftSounding(pick)
    }

    // SEAL comet: the per-CELL strike feed records the firing cell (index col*8+row) with its velocity; a
    // silent cell records nothing. Drains read-and-clear.
    func testCellStrikeFeedRecordsFiringCell() {
        let cs = arpMachines()
        let b = box(machines: cs) {
            $0.stepRate = .r1_8   // fast columns (0.5 beat each) so the playhead sweeps to column 5 within the run
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }()
            $0.cells[5][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }()   // col 5 → index 5*16 = 80 (≥64: guards the strike-feed cap regression, Paul 2026-08-30)
        }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<64 {   // enough windows (0.5-beat columns) for the playhead to sweep past column 5 (so the (5,0) cell fires)
            router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        let strikes = router.drainCellStrikes()
        XCTAssertEqual(strikes.count, Snap.cells)
        XCTAssertGreaterThan(strikes[0], 0, "cell (0,0) fired → its strike velocity is recorded at index 0")
        XCTAssertGreaterThan(strikes[5 * Snap.rows + 0], 0, "cell (5,0) fired → recorded at index 80 (≥64, the cap bug)")
        XCTAssertEqual(strikes[1], 0, "a silent cell records nothing")
        XCTAssertTrue(router.drainCellStrikes().allSatisfy { $0 == 0 }, "drain is read-and-clear")
    }

    // NOTE-SWEEP feed (Paul 2026-08-19): drainCellNotes records the REAL emitted pitches (+ velocities) per cell.
    func testCellNoteFeedRecordsEmittedPitches() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<8 {
            router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        let notes = router.drainCellNotes()
        XCTAssertEqual(notes.count.count, Snap.cells)
        XCTAssertGreaterThan(Int(notes.count[0]), 0, "cell (0,0) emitted notes → recorded at index 0")
        XCTAssertEqual(notes.count[1], 0, "a silent cell records nothing")
        let n0 = Int(notes.count[0])
        for k in 0..<n0 {                                            // every recorded pitch is one the arp actually played
            XCTAssertTrue([60, 64, 67].contains(Int(notes.pitch[0 * 6 + k])), "recorded pitch is an arp note of C-E-G")
            XCTAssertGreaterThan(notes.vel[0 * 6 + k], 0, "each note carries a velocity")
        }
        XCTAssertTrue(router.drainCellNotes().count.allSatisfy { $0 == 0 }, "drain is read-and-clear")
    }

    // FOCUS note-event feed (Paul 2026-08-31): drainFocusNotes records the focus cell's REAL emitted notes WITH musical beat —
    // the data the chain-flow comets animate. Only the focus cell records; read-and-clear.
    func testFocusNoteFeedRecordsEmittedNotesWithBeats() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<8 {
            router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0, focusCell: 0, out: e, diag: &diag)   // cell (0,0) → index 0
            beat += windowBeats; ts += Double(frames)
        }
        let f = router.drainFocusNotes()
        XCTAssertGreaterThan(f.count, 0, "the focus cell recorded emitted notes")
        XCTAssertEqual(f.pitch.count, f.count); XCTAssertEqual(f.vel.count, f.count); XCTAssertEqual(f.beat.count, f.count)
        for k in 0..<f.count {
            XCTAssertTrue([60, 64, 67].contains(Int(f.pitch[k])), "a recorded pitch is a played arp note")
            XCTAssertGreaterThan(f.vel[k], 0)
            XCTAssertGreaterThanOrEqual(f.beat[k], -0.001, "the note carries a real (non-negative) beat")
            XCTAssertLessThanOrEqual(f.beat[k], beat + 0.5, "…within the played range")
        }
        XCTAssertEqual(router.drainFocusNotes().count, 0, "read-and-clear")
        // A DIFFERENT focus cell records nothing (cell (0,0) is index 0; index 1 never emits here).
        let e2 = RecordingEmitter()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, laneMask: 0, focusCell: 1, out: e2, diag: &diag)
        XCTAssertEqual(router.drainFocusNotes().count, 0, "a non-emitting focus cell records nothing")
    }

    // PART ROW ROLL (Paul 2026-09-29): rowSoundingVoices() bucket-scans the voice pool by ENGINE ROW
    // (cellIndex % Snap.rows), each entry carrying its TRUE onset beat (Voice.onBeat) — the feed behind
    // the part grid's live piano-roll overlay. cell (0,0) is row 0. An EMPTY chain = born-audible
    // PASSTHROUGH hold (same setup as testCellSoundingGateReflectsHeldNoteThenClears) — the chord
    // SUSTAINS, guaranteeing something is still active at the check point; an ARP's staccato notes can
    // all have already gated off by then (caught by this test failing with an ARP on the first run).
    func testRowSoundingVoicesReportsHeldNoteWithAccurateOnsetBeat() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = []; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<4 {
            router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        let rows = router.rowSoundingVoices()
        XCTAssertEqual(rows.count, Snap.rows)
        let row0 = rows[0]
        // §7b: each note opens TWO voices (its own cable + the ALL-cable copy) — rowSoundingVoices() is a
        // raw per-voice dump by design (the UI layer dedupes by (pitch,onBeat) for the roll), so 3 held
        // notes → 6 voices here, not 3. (Caught by the first run of this test asserting 3 and failing.)
        XCTAssertEqual(row0.count, 6, "row 0 (cell 0,0) holds the 3-note chord × 2 cables (own + ALL)")
        XCTAssertEqual(Set(row0.map { Int($0.note) }), Set([60, 64, 67]), "exactly the 3 held pitches, each duplicated")
        for v in row0 {
            XCTAssertTrue([60, 64, 67].contains(Int(v.note)), "a reported pitch is a held chord note")
            XCTAssertGreaterThan(v.vel, 0)
            XCTAssertGreaterThanOrEqual(v.onBeat, -0.001, "the note carries a real (non-negative) onset beat")
            XCTAssertLessThanOrEqual(v.onBeat, beat + 0.5, "…within the played range")
        }
        XCTAssertTrue(rows[1...].allSatisfy { $0.isEmpty }, "no other row sounds")
    }

    // Two machines on DIFFERENT rows (row 0 and row 4 — a different FERRY's first row, Snap.rowsPerFerry
    // == 4) must land in their own row's bucket only — proving the filter keys on the real engine row,
    // not some coarser per-ferry grouping.
    func testRowSoundingVoicesBucketsByRowNotFerry() {
        let cs = arpMachines()
        let b = box(machines: cs) {
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = []; return c }()   // row 0
            $0.cells[0][4] = { var c = Cell(machineID: "cyan", buses: [.b]); c.processors = []; return c }()   // row 4 (a different ferry)
        }
        let router = runDirect(b, chord([60, 64, 67]))
        let rows = router.rowSoundingVoices()
        XCTAssertEqual(rows.count, Snap.rows)
        XCTAssertGreaterThan(rows[0].count, 0, "row 0's own machine sounds in row 0's bucket")
        XCTAssertGreaterThan(rows[4].count, 0, "row 4's own machine sounds in row 4's bucket")
        XCTAssertTrue(rows[0].allSatisfy { [60, 64, 67].contains(Int($0.note)) })
        XCTAssertTrue(rows[4].allSatisfy { [60, 64, 67].contains(Int($0.note)) })
        for r in 0..<Snap.rows where r != 0 && r != 4 {
            XCTAssertTrue(rows[r].isEmpty, "row \(r) has no machine → its bucket is empty")
        }
    }

    // A row's bucket empties on release, mirroring testCellSoundingGateReflectsHeldNoteThenClears.
    func testRowSoundingVoicesClearsOnRelease() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = []; return c }() }
        let router = runDirect(b, chord([60, 64, 67]))
        XCTAssertGreaterThan(router.rowSoundingVoices()[0].count, 0, "row 0 sounds while held")
        var diag = KernelDiag(); let e = RecordingEmitter()
        router.process(box: b, pool: chord([60, 64, 67]), playing: false, beatPos: 4.0, tempo: 120.0,
                       sampleRate: 48_000.0, timestampSample: 8192, frameCount: 2048, out: e, diag: &diag)
        XCTAssertTrue(router.rowSoundingVoices()[0].isEmpty, "after release the row's bucket clears")
    }

    // Mirrors testSilentClaimGhostDoesNotLightTheSoundingComet: a MUTED claimant opens only a SILENT ghost
    // voice (still carrying a valid cellIndex) — the same `!v.silent` guard used by cellSoundingNotes/
    // cellSoundingVelSnapshot must also keep it out of rowSoundingVoices' buckets. BYPASS voices need no
    // separate test: they're excluded by the SAME `cellIndex >= 0` guard (a bypass voice always carries
    // cellIndex == -1 — reconcileBypass saves/clears/restores currentCellIndex around it, "wire voices
    // carry no grid identity"), the identical mechanism already proven here for the silent-ghost case.
    func testRowSoundingVoicesExcludesSilentClaimGhosts() {
        var st = PluginState(machines: claimMachines(transposeB: 5), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // row 0 — MUTED claimant → only a silent ghost (holds 60)
            s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // row 1 — audible (holds 65, not the claimed pitch)
            return s }()])
        st.claimEmitter = 0
        st.busEnabled = [false, true, true, true]                 // A muted → the claimant makes no sound
        let router = runDirect(SnapshotBuilder.build(from: st), chord([60]))
        let rows = router.rowSoundingVoices()
        XCTAssertTrue(rows[0].isEmpty, "the muted claimant's SILENT ghost must not appear in row 0's bucket")
        XCTAssertGreaterThan(rows[1].count, 0, "…while the audible non-claimant DOES appear in row 1 — the scene is live")
    }

    // The per-cell note ring CAPS at 6 and the wrap-index read returns valid pitches (Paul 2026-08-19). A cell emitting
    // many notes before a drain must return exactly 6 (the ring size), all real chord pitches (proving the modular read).
    func testCellNoteRingCapsAtSixWithValidWrap() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        let held: [UInt8] = [48, 50, 52, 55, 57, 60, 64]   // a 7-note chord → the arp emits far more than 6 before the drain
        var beat = 0.0, ts = 0.0
        for _ in 0..<20 {
            router.process(box: b, pool: chord(held), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        let notes = router.drainCellNotes()
        XCTAssertEqual(Int(notes.count[0]), 6, "the per-cell ring caps at 6 notes")
        for k in 0..<6 {                                    // every returned slot holds a REAL chord pitch → the wrap arithmetic is valid (no zeros/garbage)
            XCTAssertTrue(held.contains(notes.pitch[0 * 6 + k]), "slot \(k) is a genuine held pitch, not a wrap-index bug")
        }
    }

    // SEAL comet gate: a cell HOLDING a note reports its bit in the sounding mask (index col*8+row) for exactly as
    // long as it sounds; on release the bit clears. This is the note-on/off feed that binds the spark to the hold.
    func testCellSoundingGateReflectsHeldNoteThenClears() {
        let cs = arpMachines()
        // an EMPTY chain = born-audible PASSTHROUGH hold → the chord sustains (deterministic sounding voices)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = []; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<4 {   // hold a chord for a few windows
            router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.snapshotCellSounding()
        let held = router.cellSoundingVelSnapshot()   // the 256-wide sounding-velocity feed (the UI derives the gate from > 0)
        XCTAssertGreaterThan(held[0], 0, "cell (0,0) is holding a note → it reports sounding")
        XCTAssertEqual(held.filter { $0 > 0 }.count, 1, "no other cell sounds")
        router.process(box: b, pool: chord([60, 64, 67]), playing: false, beatPos: beat, tempo: tempo,   // stop → release
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        router.snapshotCellSounding()
        XCTAssertEqual(router.cellSoundingVelSnapshot().filter { $0 > 0 }.count, 0, "after release the gate clears")
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

    // SEAL comet — the SILENT-GHOST exclusion: a MUTED claimant opens ONLY a silent ghost voice (which still
    // carries its cellIndex). The `!v.silent` guard in snapshotCellSounding is the ONLY thing stopping that
    // soundless cell from lighting a phantom comet. A same-pitch-shifted non-claimant DOES sound (proving the
    // scene is live + the mask machinery works), so the muted claimant's cleared bit is a real exclusion.
    func testSilentClaimGhostDoesNotLightTheSoundingComet() {
        var st = PluginState(machines: claimMachines(transposeB: 5), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // index 0 — MUTED claimant → only a silent ghost (holds 60)
            s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // index 1 — audible (holds 65, not the claimed pitch)
            return s }()])
        st.claimEmitter = 0
        st.busEnabled = [false, true, true, true]                 // A muted → the claimant makes no sound
        let router = runDirect(SnapshotBuilder.build(from: st), chord([60]))
        router.snapshotCellSounding()
        let mask = router.cellSoundingVelSnapshot()
        XCTAssertEqual(mask[0], 0, "the muted claimant's SILENT ghost must NOT light its comet (cell 0)")
        XCTAssertGreaterThan(mask[1], 0, "…while the audible non-claimant DOES light (cell 1) — the scene is live")
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

    // SEAL comet — a FAN-OUT cell (emitting to ≥2 buses → ≥2 voices sharing one cellIndex) reports EXACTLY ONE
    // sounding bit and ONE strike slot, not one per bus. Guards the per-CELL (not per-voice/per-bus) keying.
    func testFanOutCellReportsSingleSoundingBitAndOneStrike() {
        let b = box(machines: arpMachines()) {
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a, .b]); c.processors = []; return c }()
        }
        let router = runDirect(b, chord([60, 64, 67]))
        let strikes = router.drainCellStrikes()
        XCTAssertGreaterThan(strikes[0], 0, "the fan-out cell records a strike at its index")
        XCTAssertEqual(strikes.filter { $0 > 0 }.count, 1, "recorded ONCE, not per bus")
        router.snapshotCellSounding()
        let fm = router.cellSoundingVelSnapshot()
        XCTAssertEqual(fm.filter { $0 > 0 }.count, 1, "exactly one sounding cell despite the fan-out")
        XCTAssertGreaterThan(fm[0], 0, "…at the cell's index")
    }

    // CELL MACHINE stage-2: a RATCHET tail re-strikes the HEAD stage's WHOLE output set each repeat.
    func testChainHarmonizeToRatchetRestrikesAllVoices() {
        let cs = arpMachines()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let rat = ProcessorSlot(type: .ratchet)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [harm, rat]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 67]),
                      "ratchet re-strikes BOTH the source and the +7 harmonized voice")
        assertNothingLeftSounding(e)
    }

    func testChainGateToRatchetRestrikesChord() {
        let cs = arpMachines()
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 1.0   // deterministic open gate (PASSGATE removed 2026-09-28)
        let rat = ProcessorSlot(type: .ratchet)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [gate, rat]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 64, 67]),
                      "ratchet re-strikes the whole gated chord")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2 (N>2 slots): [gate → harmonize +7 → ARP] composes — the arp tail arps the harmonized
    // set that flowed through the open gate.
    func testChainThreeSlotGateHarmonizeArp() {
        let cs = arpMachines()
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 1.0   // deterministic open gate (PASSGATE removed 2026-09-28)
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let arp = ProcessorSlot(type: .arp)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [gate, harm, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 67]),
                      "3-slot chain: the arp tail arps both the source and the +7 voice, passed through the gate")
        assertNothingLeftSounding(e)
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

    // CELL MACHINE stage-2 (HOLD tail): a chain ending in a hold stage emits at column boundaries. [gate →
    // harmonize +7] HOLDS the harmonized chord (source + the +7 voice) rather than arping it.
    func testChainHoldTailGateToHarmonize() {
        let cs = arpMachines()
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 1.0   // deterministic open gate (PASSGATE removed 2026-09-28)
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [gate, harm]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 67]),
                      "hold-tail chain holds the harmonized chord (source + the +7 voice)")
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

    // CELL MACHINE stage-2 (STRUM tail): [harmonize +7 → STRUM] staggers the WHOLE harmonized set each column.
    func testChainHarmonizeToStrumStrumsAllVoices() {
        let cs = arpMachines()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let strum = ProcessorSlot(type: .strum)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [harm, strum]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 67]),
                      "strum tail staggers both the source and the +7 harmonized voice")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-3: a machine's shared TEMPLATE chain sounds for a FOLLOWING cell (no per-cell override).
    func testTemplateChainSoundsForFollowingCell() {
        var cs = arpMachines()
        let gi = machineIDs.firstIndex(of: "gold")!
        var gate = ProcessorSlot(type: .chance); gate.params.probability = 1.0   // deterministic open gate (PASSGATE removed 2026-09-28)
        cs[gi].templateChain = [gate, ProcessorSlot(type: .arp)]                       // template = gate → arp
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // FOLLOWING (no override)
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 64, 67]),
                      "a following cell sounds the machine TEMPLATE chain (arps the chord)")
        assertNothingLeftSounding(e)
    }

    // A per-cell OVERRIDE diverges from the template: template = arp, but this cell overrides with an
    // identity hold → holds the raw chord instead of arping.
    func testCellOverrideDivergesFromTemplate() {
        var cs = arpMachines()
        let gi = machineIDs.firstIndex(of: "gold")!
        cs[gi].templateChain = [ProcessorSlot(type: .arp)]
        let idle = ProcessorSlot(type: .empty)
        let b = box(machines: cs) { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.processors = [idle]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67],
                       "the OVERRIDE (identity hold) ignores the arp TEMPLATE")
        assertNothingLeftSounding(e)
    }

    func testInputChannelFilterRoutesBySourceChannel() {
        // Device T6 (filter-in), previously unit-untested at the Router level: two MIDI-IN cells, one
        // filtering IN CH 1 → Emit A, the other IN CH 2 → Emit B. A note on wire ch 0 sounds only through
        // A; a note on wire ch 1 only through B. No origin channel survives — each is re-stamped on its bus.
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!] = holdMachine("gold")
        cs[machineIDs.firstIndex(of: "cyan")!] = holdMachine("cyan")
        let b = box(machines: cs) {
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputChannel = 1; return c }()  // IN CH 1 = wire 0
            $0.cells[0][1] = { var c = Cell(machineID: "cyan", buses: [.b]); c.inputChannel = 2; return c }()  // IN CH 2 = wire 1
        }
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0)   // wire ch 0 → cell 1 only
        pool.noteOn(64, velocity: 100, channel: 1)   // wire ch 1 → cell 2 only
        let e = RecordingEmitter()
        run(b, pool, beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "ch-1 note 60 sounds on Emit A")
        XCTAssertTrue(e.ons.filter { $0.cable == 1 && $0.note == 64 }.isEmpty, "64 (ch 2) does not leak onto A")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 && $0.note == 64 }.count, 0, "ch-2 note 64 sounds on Emit B")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 && $0.note == 60 }.isEmpty, "60 (ch 1) does not leak onto B")
        assertNothingLeftSounding(e)
    }

    // MARK: - COLUMN-SUBSET LAP (§5b) — the held set warps which column is effective

    func testLapStutterLocksPlaybackToTheHeldColumn() {
        // Hold column 2 only (k=1): column 2 plays CONTINUOUSLY (every step), column 5 never becomes
        // effective — vs. the normal 1-step-in-8 for each.
        let b = box(machines: arpMachines()) {
            $0.cells[2][0] = Cell(machineID: "gold")                  // column 2 → A
            $0.cells[5][0] = Cell(machineID: "azure", buses: [.b])    // column 5 → B
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e, laneMask: 1 << 2)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 8, "column 2 plays continuously under the lap")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 }.isEmpty, "column 5 never becomes effective")
        assertNothingLeftSounding(e)
    }

    func testLapAlternatesBetweenTwoHeldColumns() {
        // Hold columns 1 and 3 (k=2): both play, on alternating steps.
        let b = box(machines: arpMachines()) {
            $0.cells[1][0] = Cell(machineID: "gold")                  // column 1 → A
            $0.cells[3][0] = Cell(machineID: "azure", buses: [.b])    // column 3 → B
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e, laneMask: (1 << 1) | (1 << 3))
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "column 1 plays on its lap steps")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "column 3 plays on its lap steps")
        assertNothingLeftSounding(e)
    }

    func testLapPolymeterRotationLeavesNothingStuckThroughRelease() {
        // Hold three columns (k=3 polymeter) over a held chord, then release + stop (run() does this).
        let b = box(machines: arpMachines()) { for c in [1, 3, 5] { $0.cells[c][0] = Cell(machineID: "gold") } }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 20, into: e, laneMask: (1 << 1) | (1 << 3) | (1 << 5))
        XCTAssertGreaterThan(e.ons.count, 0)
        assertNothingLeftSounding(e)
    }

    // MARK: - graph routing (delta §1) — reference derivation, reroute, cycles

    // (testFedArpArpeggiatesTheParentsSoundingNote + testMutedParentReroutesChildToSource removed 2026-08-27:
    //  GRID-CHAINING retired — `inputRow` is render-inert, so the "child mirrors/reroutes-from the parent" behaviour is
    //  dead. Both children read the SOURCE pool regardless of the ref; the muted-parent-is-silent residual is covered by
    //  testMutedReceiverSilencesItsSubscribers / testMutedCellEmitsNothing.)

    // (grid-chaining retired: the reference-cycle test was removed — no cell-to-cell references exist.)

    func testPlayingHarmonizeAtMidiInSoundsTheExpandedChord() {
        // The PLAYING chord-hold path (emitColumnHolds), distinct from audition: a HARMONIZE cell at
        // MIDI IN sounds root + its interval voices.
        var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
        cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = [4, 7, 0]
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold") }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 0 }.map { $0.note }), [60, 64, 67],
                       "playing HARMONIZE expands the held note to its voices")
        assertNothingLeftSounding(e)
    }

    func testStopEdgeFlushesEverySoundingVoice() {
        // Even with a slow ARP and a stop mid-window, the transport edge must leave nothing sounding.
        let b = box(machines: arpMachines()) {
            $0.cells[0][0] = Cell(machineID: "gold")
            $0.cells[2][0] = Cell(machineID: "cyan", buses: [.b])
        }
        let e = RecordingEmitter()
        run(b, chord([60, 63, 67, 70]), beats: 20, into: e)   // 2+ columns worth, then stop
        XCTAssertGreaterThan(e.ons.count, 0)
        assertNothingLeftSounding(e)
    }

    // MARK: - PREVIEW / cell audition (Phase 2, Increment 1: ARP solo)

    @discardableResult
    private func runPreview(_ box: SnapshotBox, _ pool: NotePool,
                            _ preview: (active: Bool, machineIndex: Int, filter: Int, busMask: UInt8, inputRow: Int),
                            beats: Double, into e: RecordingEmitter, playing: Bool = true,
                            tempo: Double = 120, sr: Double = 48_000, frames: UInt32 = 2048) -> (Router, KernelDiag, Double) {
        let router = Router(); var diag = KernelDiag()
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < beats {
            router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, preview: preview, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        return (router, diag, ts)
    }
    private func boxWithBusEnabled(_ cs: [Machine], _ enabled: [Bool], _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(machines: cs, scenes: [s]); st.busEnabled = enabled
        return SnapshotBuilder.build(from: st)
    }

    // SOLO: a real bus-A ARP cell would sound on cable 1; with PREVIEW on bus B, ONLY the virtual cell
    // emits (cable 2 + All), and the real cell is silenced.
    func testPreviewSolosOnlyTheVirtualCell() {
        let gold = machineIDs.firstIndex(of: "gold")!
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: e)   // preview → bus B
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "preview emits on bus B (cable 2)")
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "the real bus-A cell is SOLOED OUT")
    }

    // The virtual cell emits through its STAGED buses, respecting busEnabled — a disabled staged emitter is silent.
    func testPreviewRespectsBusEnabled() {
        let gold = machineIDs.firstIndex(of: "gold")!
        let b = boxWithBusEnabled(arpMachines(), [false, true, true, true]) { _ in }   // bus A disabled
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0001, -1), beats: 8, into: e)   // preview → bus A (disabled)
        XCTAssertEqual(e.ons.count, 0, "a disabled staged emitter stays silent under preview")
    }

    // Preview emits its arp over the source pool (receiver / OMNI input), and it works with a claim set
    // (CLAIM bypassed — solo has no other-emitter context).
    func testPreviewEmitsOverSourcePoolAndIgnoresClaim() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var s = SceneState.empty()
        var st = PluginState(machines: arpMachines(), scenes: [s]); st.claimEmitter = 0   // CLAIM on bus A
        _ = s
        let b = SnapshotBuilder.build(from: st)
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: e)   // preview → bus B, claim on A
        XCTAssertGreaterThan(e.ons.count, 0, "preview arps the source pool and is not blocked by CLAIM")
    }

    // §item 11 INPUT CABLES: a cell whose receiver is sourced from CABLE 2 hears only cable-2 notes.
    // COG SIMPLIFICATION (2026-08-03): cables retired — even a receiver carrying a SAVED cable filter now hears
    // ALL cables (the filter is ignored). Was `testCabledReceiverCellHearsOnlyItsCable` (the retired behaviour).
    func testCabledReceiverStillHearsAllCablesAfterRetirement() {
        var s = SceneState.empty()
        var cell = Cell(machineID: "gold", buses: [.a]); cell.inputReceiver = 0
        s.cells[0][0] = cell
        var st = PluginState(machines: arpMachines(), scenes: [s])
        st.receivers = [Receiver(name: "1", cable: 0b0010), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0, cable: 1)
        pool.noteOn(67, velocity: 100, channel: 0, cable: 2)
        let e = RecordingEmitter()
        run(b, pool, beats: 8, into: e)
        let notes = Set(e.ons.map { $0.note })
        XCTAssertTrue(notes.contains(60) && notes.contains(67), "a saved cable filter is IGNORED — the receiver hears every cable")
        assertNothingLeftSounding(e)
    }

    // LATCH bug hunt (user: "playing, no difference"): a cell subscribing to an ARMED receiver must SUSTAIN the
    // frozen chord even when the LIVE pool is empty (keys released). Tests the Router half (effectivePool + emit).
    func testLatchedReceiverSustainsFrozenChordWhenLiveEmpty() {
        var s = SceneState.empty()
        var cell = Cell(machineID: "gold", buses: [.a]); cell.inputReceiver = 0   // R1 arp (inherits machine machine)
        s.cells[0][0] = cell
        var st = PluginState(machines: arpMachines(), scenes: [s])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        let frozen = NotePool()                                     // the latched chord for R1
        frozen.noteOn(60, velocity: 100, channel: 0, cable: 1); frozen.noteOn(64, velocity: 100, channel: 0, cable: 1)
        frozen.rebuildSorted()
        let pools = [frozen, NotePool(), NotePool(), NotePool()]
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<6 {   // LIVE pool EMPTY (keys released), R1 ARMED (latchMask bit 0)
            router.process(box: b, pool: NotePool(), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, latchMask: 0b0001, latchedPools: pools, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        XCTAssertGreaterThan(e.ons.count, 0, "an armed-latch cell SUSTAINS the frozen chord with the live pool empty")
        XCTAssertTrue(e.ons.contains { $0.note == 60 } && e.ons.contains { $0.note == 64 }, "the frozen chord's notes sound")
    }

    // FROZEN-POOL omniRead (Paul 2026-08-23): the door REPLAY loop STOPPED when the input channel was disabled. A frozen
    // pool (LATCH/REPLAY/FILE) is door-filtered at CAPTURE, so a cell reads it WHOLE — a LATER channel-mask edit
    // (disabling the channel the loop is on) must NOT drop the loop. omniRead=true keeps it; omniRead=false (the old
    // behaviour) re-filters and drops it. Mirrors the BYPASS path's latched-whole read.
    func testFrozenPoolOmniReadPlaysRegardlessOfCellChannelFilter() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var cs = arpMachines(); cs[machineIDs.firstIndex(of: "gold")!].type = .empty   // an identity HOLD → reads via srcCount(for:) = inputChanMask
        var st = PluginState(machines: cs, scenes: [s])
        var r1 = Receiver(name: "1"); r1.channelMask = 0x0001        // the door now hears ONLY channel 1 (the user disabled ch4)
        st.receivers = [r1, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        func run(omni: Bool) -> Set<UInt8> {
            let frozen = NotePool(); frozen.omniRead = omni           // a captured loop note on CHANNEL 4 (chan index 3) — NOT in the current mask
            frozen.noteOn(60, velocity: 100, channel: 3, cable: 1); frozen.rebuildSorted()
            let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter(); var beat = 0.0, ts = 0.0
            for _ in 0..<6 {
                router.process(box: b, pool: NotePool(), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, latchMask: 0b0001,
                               latchedPools: [frozen, NotePool(), NotePool(), NotePool()], out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
            return Set(e.ons.map { $0.note })
        }
        XCTAssertTrue(run(omni: true).contains(60), "omniRead: the frozen loop plays even though the cell's channel mask now EXCLUDES its channel")
        XCTAssertFalse(run(omni: false).contains(60), "omniRead OFF re-filters by the (changed) mask and DROPS the note — the old bug, proving omniRead is the fix")
    }
    // MULTI-CHANNEL arp on LIVE input (Paul 2026-08-23): an arp on a door hearing channels {1,3} must DROP channel-2
    // live input — the arp source-pick now filters by the door's channel MASK (was the legacy single inputChannel,
    // which is OMNI for a multi-channel door, so the mask was ignored on live input).
    func testArpHonoursMultiChannelMaskOnLiveInput() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()   // gold = arp (arpMachines)
        var st = PluginState(machines: arpMachines(), scenes: [s])
        var r1 = Receiver(name: "1"); r1.channelMask = 0x0005        // bits 0 + 2 = channels 1 and 3 (channel 2 disabled)
        st.receivers = [r1, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        let live = NotePool()
        live.noteOn(60, velocity: 100, channel: 0, cable: 1)         // channel 1 — admitted
        live.noteOn(64, velocity: 100, channel: 1, cable: 1)         // channel 2 — DROPPED (not in the mask)
        live.noteOn(67, velocity: 100, channel: 2, cable: 1)         // channel 3 — admitted
        live.rebuildSorted()
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        for _ in 0..<16 {
            router.process(box: b, pool: live, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let notes = Set(e.ons.map { $0.note })
        XCTAssertTrue(notes.contains(60) && notes.contains(67), "the arp cycles the admitted channels 1 + 3")
        XCTAssertFalse(notes.contains(64), "the arp DROPS channel 2 (not in the door's mask) — was read OMNI before the fix")
    }
    // INPUT ENABLE (the strip header): the "latch A, disable A, play B" workflow. A DISABLED + ARMED door keeps
    // feeding its FROZEN chord to the grid while IGNORING the live pool ("close the door, keep the room").
    func testDisabledReceiverKeepsFeedingArmedLatchIgnoringLive() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(machines: arpMachines(), scenes: [s])
        var r1 = Receiver(name: "1"); r1.inputEnabled = false   // door CLOSED (not listening)
        st.receivers = [r1, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        let frozen = NotePool()                                 // R1's sealed latch = a C-major chord
        frozen.noteOn(60, velocity: 100, channel: 0, cable: 1); frozen.noteOn(64, velocity: 100, channel: 0, cable: 1); frozen.rebuildSorted()
        let live = NotePool()                                   // "playing B" — a fresh note R1 must ignore
        live.noteOn(72, velocity: 100, channel: 0, cable: 1); live.rebuildSorted()
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<6 {
            router.process(box: b, pool: live, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, latchMask: 0b0001,
                           latchedPools: [frozen, NotePool(), NotePool(), NotePool()], out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        let notes = Set(e.ons.map { $0.note })
        XCTAssertTrue(notes.contains(60) && notes.contains(64), "a disabled+armed door keeps feeding its frozen chord")
        XCTAssertFalse(notes.contains(72), "a disabled door IGNORES the live note — latch A, disable A, play B leaves A untouched")
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

    // RANGE (§2): a door admits only SOURCE notes in its window. Robust to the arp's own octave-spanning — adding
    // out-of-window notes to the pool must change NOTHING, because they never enter the cell's source list.
    func testReceiverRangeFiltersSourceNotes() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(machines: arpMachines(), scenes: [s])
        var r1 = Receiver(name: "1"); r1.rangeLo = 60; r1.rangeHi = 72   // window C4…C5
        st.receivers = [r1, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        let inWindow = NotePool(); for n: UInt8 in [60, 72] { inWindow.noteOn(n, velocity: 100, channel: 0, cable: 1) }
        let withOutliers = NotePool(); for n: UInt8 in [48, 60, 72, 84] { withOutliers.noteOn(n, velocity: 100, channel: 0, cable: 1) }
        let e1 = RecordingEmitter(); run(b, inWindow, beats: 16, into: e1)
        let e2 = RecordingEmitter(); run(b, withOutliers, beats: 16, into: e2)
        XCTAssertFalse(e1.ons.isEmpty, "the in-window notes do sound")
        XCTAssertEqual(Set(e1.ons.map { $0.note }), Set(e2.ons.map { $0.note }),
                       "the out-of-window source notes add nothing — RANGE filters them before the cell reads")
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

    // The wire injects a held note on its emitter's cable (+ the ALL cable) with that emitter's channel.
    func testWireInjectsHeldNotesToDestEmitters() {
        let b = wireBox(dest: 0b0001)   // → emitter A: cable 1, channel 0 (busChannels[0] = 1 → wire 0)
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60]), playing: true, beat: 0, out: e)
        XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == 1 && $0.chan == 0 }, "injects on dest emitter A")
        XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == 0 }, "and on the ALL cable")
        XCTAssertFalse(e.ons.contains { $0.cable == 2 || $0.cable == 3 || $0.cable == 4 }, "not on unselected emitters")
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

    // Releasing the key emits the wire note-off — no stuck note.
    func testWireReleaseEmitsNoteOff() {
        let b = wireBox(dest: 0b0001)
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60]), playing: true, beat: 0, out: e)      // press
        stepWindow(router, b, NotePool(), playing: true, beat: 0.25, out: e)    // release
        XCTAssertTrue(e.offs.contains { $0.note == 60 && $0.cable == 1 }, "release emits the wire note-off")
        assertNothingLeftSounding(e)
    }

    // WIRE + LATCH (PIANO/held): a no-machine cell reading an ARMED-latch door injects its FROZEN chord — the live pool is
    // empty (PIANO has no physical keys), so reading live would inject nothing. Locks the reconcileBypass frozen read.
    func testWireInjectsTheFrozenLatchPoolNotLive() {
        let b = wireBox(dest: 0b0001)   // a no-machine cell on R1 → emitter A (cable 1)
        let frozen = NotePool(); frozen.noteOn(67, velocity: 100, channel: 0); frozen.noteOn(72, velocity: 100, channel: 0); frozen.rebuildSorted()
        let pools = [frozen, NotePool(), NotePool(), NotePool()]
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        // LIVE pool empty (as with PIANO); the frozen R1 pool holds the picked chord. latchMask 0b0001 arms R1.
        router.process(box: b, pool: NotePool(), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                       timestampSample: 0, frameCount: 512, latchMask: 0b0001, latchedPools: pools, out: e, diag: &diag)
        XCTAssertTrue(e.ons.contains { $0.note == 67 && $0.cable == 1 }, "the wire injects the frozen chord (67)")
        XCTAssertTrue(e.ons.contains { $0.note == 72 && $0.cable == 1 }, "the wire injects the frozen chord (72)")
    }

    // Latch on a NON-R1 door (R2): a cell reading R2 arps the frozen chord — proves the per-receiver index is honoured
    // (the PIANO-latch bug report was on receiver 2). Mirrors testLatchedPoolSubstitutesForLive at bit 1.
    func testLatchedPoolFeedsCellReadingReceiverTwo() {
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 1; return c }() }
        let frozen = NotePool(); frozen.noteOn(67, velocity: 100, channel: 0); frozen.noteOn(72, velocity: 100, channel: 0); frozen.rebuildSorted()
        let pools = [NotePool(), frozen, NotePool(), NotePool()]   // R2 (index 1) holds the frozen chord
        let latched = latchNotes(b, live: NotePool(), latchMask: 0b0010, pools: pools, cable: 1)
        XCTAssertTrue(latched.contains(67) && latched.contains(72), "R2 armed ⇒ the cell arps R2's frozen chord")
    }

    // The wire admits only in-range notes (the door's RANGE window applies to the injected stream too).
    func testWireRespectsRange() {
        let b = wireBox(dest: 0b0001, rangeLo: 62, rangeHi: 127)
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60, 64]), playing: true, beat: 0, out: e)
        XCTAssertFalse(e.ons.contains { $0.note == 60 }, "60 is below the window — not injected")
        XCTAssertTrue(e.ons.contains { $0.note == 64 && $0.cable == 1 }, "64 is in-window — injected")
    }

    // The wire is a LIVE MONITOR: it survives a transport stop (the transport edge doesn't release it); only the key
    // lifting (or panic) closes it.
    func testWirePersistsAcrossTransportStop() {
        let b = wireBox(dest: 0b0001)
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60]), playing: true, beat: 0, out: e)      // press (playing)
        stepWindow(router, b, chord([60]), playing: false, beat: 0.25, out: e)  // transport STOP, key still down
        XCTAssertEqual(e.offs.filter { $0.note == 60 && $0.cable == 1 }.count, 0, "the wire survives the stop — no release")
        stepWindow(router, b, NotePool(), playing: false, beat: 0.5, out: e)    // release while stopped
        XCTAssertTrue(e.offs.contains { $0.note == 60 && $0.cable == 1 }, "released while stopped → off")
    }

    // SOLO includes the wire (ruling 2026-08-04): a receiver solo set that EXCLUDES the door silences its
    // wire too; the SOLOED door's wire still sounds.
    func testWireRespectsReceiverSolo() {
        let b = wireBox(dest: 0b0001)   // a no-machine cell on R1 → emitter A
        let e1 = RecordingEmitter(); var d1 = KernelDiag()
        Router().process(box: b, pool: chord([60]), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                         timestampSample: 0, frameCount: 512, soloReceiverMask: 0b0010, out: e1, diag: &d1)   // R2 soloed, R1 excluded
        XCTAssertTrue(e1.ons.isEmpty, "a solo set excluding the door silences its wire")
        let e2 = RecordingEmitter(); var d2 = KernelDiag()
        Router().process(box: b, pool: chord([60]), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                         timestampSample: 0, frameCount: 512, soloReceiverMask: 0b0001, out: e2, diag: &d2)   // R1 soloed
        XCTAssertTrue(e2.ons.contains { $0.note == 60 && $0.cable == 1 }, "the soloed door's wire still sounds")
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

    // ANY (the migration default) hears every cable — byte-for-byte today's behaviour.
    func testAnyReceiverHearsAllCables() {
        var s = SceneState.empty()
        var cell = Cell(machineID: "gold", buses: [.a]); cell.inputRow = nil; cell.inputReceiver = 0
        s.cells[0][0] = cell
        var st = PluginState(machines: arpMachines(), scenes: [s])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]   // cable nil ⇒ ANY
        let b = SnapshotBuilder.build(from: st)
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0, cable: 1)
        pool.noteOn(67, velocity: 100, channel: 0, cable: 2)
        let e = RecordingEmitter()
        run(b, pool, beats: 8, into: e)
        let notes = Set(e.ons.map { $0.note })
        XCTAssertTrue(notes.contains(60) && notes.contains(67), "ANY hears every cable")
    }

    // ROW-FEED (1b): input = ⇐ROW 0. The virtual cell reads row 0's sounding note by derivation, so it
    // emits on its own bus (B) while row 0's real cell is soloed out.
    // (testPreviewRowFeedReadsParentRow + testPreviewRowFeedEmptyParentFallsBackToSource removed 2026-08-27: the preview
    //  `inputRow` is never read (grid-chaining retired → always source-fed), so the first duplicates
    //  testPreviewSolosOnlyTheVirtualCell and the second's "empty-parent fallback" is the only path — both vacuous.)

    // 1c: a STRUM machine previews (source chord strummed) and releases clean.
    func testPreviewStrumSoundsAndReleasesClean() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var cs = arpMachines(); cs[gold] = Machine(machineID: "gold", type: .strum)
        let b = box(machines: cs) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0001, -1), beats: 8, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "strum preview strums the source chord")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // 1c: a chord-hold machine (HARMONIZE) previews (treated held chord, re-emitted per column) and releases clean.
    func testPreviewChordHoldSoundsAndReleasesClean() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var cs = arpMachines(); cs[gold] = Machine(machineID: "gold", type: .harmonize)
        let b = box(machines: cs) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0001, -1), beats: 8, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "harmonize preview holds the treated chord")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // STOPPED preview (transport stopped) — the desk-preview path. Every other preview test runs playing;
    // this exercises previewStopped's free-clock arp over the source pool, and a clean release.
    func testStoppedPreviewArpsSourcePoolAndReleasesClean() {
        let gold = machineIDs.firstIndex(of: "gold")!
        let b = box(machines: arpMachines()) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1),
                                         beats: 8, into: e, playing: false)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "stopped preview free-clock arps the source pool on bus B")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: false, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // Stopped preview handles only the time-varying ARP path (a chord-hold machine's stopped preview is a later
    // cut); a non-arp machine is silent when the transport is stopped.
    func testStoppedPreviewNonArpMachineIsSilent() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var cs = arpMachines(); cs[gold] = Machine(machineID: "gold", type: .harmonize)
        let b = box(machines: cs) { _ in }
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0001, -1), beats: 8, into: e, playing: false)
        XCTAssertEqual(e.ons.count, 0, "a chord-hold machine is silent under stopped preview")
    }

    // PLAYING preview, RATCHET: the virtual cell repeats the source chord on its staged bus, releasing clean.
    func testPreviewRatchetSoundsAndReleasesClean() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var cs = arpMachines(); cs[gold] = Machine(machineID: "gold", type: .ratchet)
        let b = box(machines: cs) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "ratchet preview repeats the source chord on bus B")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // PLAYING preview, RATCHET with ROW-FEED: the virtual ratchet cell reads row 0's sounding note (an arp cell),
    // repeating it on bus B while row 0's own cell is soloed out.
    // (testPreviewRatchetRowFeedReadsParentRow removed 2026-08-27: preview `inputRow` is inert (grid-chaining retired), so
    //  it duplicates testPreviewRatchetSoundsAndReleasesClean — a source-fed ratchet preview.)

    // 1c: CHANCE chord-hold preview gates by probability — p=1 sounds the held chord, p=0 is silent.
    func testPreviewChanceChordHoldGatesAndReleasesClean() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var cs = arpMachines(); cs[gold] = Machine(machineID: "gold", type: .chance); cs[gold].paramsA.probability = 1
        let b = box(machines: cs) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 2 }.map { $0.note }), [60, 64, 67], "chance p=1 holds the source chord on bus B")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)

        var cs0 = arpMachines(); cs0[gold] = Machine(machineID: "gold", type: .chance); cs0[gold].paramsA.probability = 0
        let b0 = box(machines: cs0) { _ in }
        let eNone = RecordingEmitter()
        runPreview(b0, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: eNone)
        XCTAssertEqual(eNone.ons.count, 0, "chance p=0 previews to silence")
    }

    // 1c: an identity chord-hold sustains the held chord on the staged bus, releasing clean.
    func testPreviewIdentityChordHoldSustains() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var cs = arpMachines(); cs[gold] = Machine(machineID: "gold", type: .empty)
        let b = box(machines: cs) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 2 }.map { $0.note }), [60, 64, 67], "an identity hold sustains the held chord on bus B")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

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

    // §9 item 1 ON ARRIVE (integration): EMITTER-ROTATE walks the firing cable each pass — a cell on
    // emitter A (cable 1) rotates to B (cable 2) on the next pass.
    func testArriveEmitterRotateWalksCablesAcrossPasses() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var cs = arpMachines()
        var on = OnConfig(); on.arrive = .emitterRotate; on.arriveEvery = 1; cs[gold].on = on
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // fires on A
        let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr
        let cycle = Double(Snap.cols) * b.stepBeats
        let pool = chord([60, 64, 67])
        func runRange(_ lo: Double, _ hi: Double, into e: RecordingEmitter) {
            var beat = lo, ts = (lo / wb) * Double(frames)
            while beat < hi {
                router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
        }
        let e0 = RecordingEmitter(); runRange(0, cycle, into: e0)
        let e1 = RecordingEmitter(); runRange(cycle, 2 * cycle, into: e1)
        XCTAssertGreaterThan(e0.ons.filter { $0.cable == 1 }.count, 0, "pass 0 fires on emitter A (cable 1)")
        XCTAssertEqual(e0.ons.filter { $0.cable == 2 }.count, 0, "pass 0 does not fire on B")
        XCTAssertGreaterThan(e1.ons.filter { $0.cable == 2 }.count, 0, "pass 1 rotates to emitter B (cable 2)")
        XCTAssertEqual(e1.ons.filter { $0.cable == 1 }.count, 0, "pass 1 no longer fires on A")
    }

    // §3/§7: the ARP GATE shortens the emitted note (first note-on → its first note-off gets shorter).
    func testArpGateControlsNoteLength() {
        let gold = machineIDs.firstIndex(of: "gold")!
        func firstNoteLength(gate: Double) -> Int64 {
            var cs = arpMachines()
            cs[gold].paramsA.gate = gate
            let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
            let e = RecordingEmitter()
            run(b, chord([60]), beats: 2, into: e)
            guard let on = e.ons.first(where: { $0.cable == 0 && $0.note == 60 }),
                  let off = e.offs.first(where: { $0.cable == 0 && $0.note == 60 && $0.sample > on.sample })
            else { return -1 }
            return off.sample - on.sample
        }
        let short = firstNoteLength(gate: 0.2), long = firstNoteLength(gate: 0.9)
        XCTAssertGreaterThan(short, 0); XCTAssertGreaterThan(long, 0)
        XCTAssertLessThan(short, long, "a smaller GATE must make a shorter note (short=\(short) long=\(long))")
    }

    // §9 item 1 ON SCENE (integration): ENTER 3 keeps a cell silent for the first two passes, then it sounds.
    func testOnSceneEntranceDelaysSounding() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var cs = arpMachines()
        var on = OnConfig(); on.sceneEntrance = true; on.entrancePass = 3; cs[gold].on = on
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr
        let cycle = Double(Snap.cols) * b.stepBeats
        let pool = chord([60, 64, 67])
        func passOns(_ p: Int) -> Int {
            let e = RecordingEmitter()
            var beat = Double(p) * cycle, ts = (beat / wb) * Double(frames)
            while beat < Double(p + 1) * cycle {
                router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
            return e.ons.count
        }
        XCTAssertEqual(passOns(0), 0, "pass 1 (ENTER 3) is silent")
        XCTAssertEqual(passOns(1), 0, "pass 2 is silent")
        XCTAssertGreaterThan(passOns(2), 0, "pass 3 — the cell enters and sounds")
    }

    // (testTapAltMaskFlipsCellEphemerally removed 2026-08-27: A/B MORPH dropped → the tap-ALT flip no longer swaps the
    //  processor face, so both assertions are `ons > 0` (the head always sounds) — vacuous.
    //  testTapMuteSilencesCell removed 2026-09-27: the whole ON-TAP overlay cluster (tapAltMask/tapMuteMask/
    //  soloCellMask + applyTapOverlay/tapOverlayMasks) had zero live producers — confirmed dead, removed.)

    // §9 item 1 ON TAP = SOLO EMITTERS (4b): a solo set silences sibling emitters (cell on A + cell on B;
    // solo = {A} → B falls silent). Solo bypasses previewMode elsewhere; here two real cells on two buses.
    func testSoloEmitterMaskSilencesSiblings() {
        let cs = arpMachines()
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]); $0.cells[0][1] = Cell(machineID: "orange", buses: [.b]) }
        func cables(_ solo: UInt8) -> Set<UInt8> {
            let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
            let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
            let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
            while beat < 2.0 {
                router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, soloEmitterMask: solo, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
            return Set(e.ons.map { $0.cable })
        }
        XCTAssertTrue(cables(0).isSuperset(of: [1, 2]), "no solo → both A (cable 1) and B (cable 2) sound")
        let soloA = cables(1 << 0)
        XCTAssertTrue(soloA.contains(1), "solo {A} → A sounds")
        XCTAssertFalse(soloA.contains(2), "solo {A} → B (sibling) falls silent")
    }

    // §9 item 1 ON HOLD (3a, integration): while a cell is press-held with ON HOLD = OCT up, its notes shift
    // an octave; not held, they play normally.
    func testOnHoldOctaveShiftsHeldCell() {
        let gold = machineIDs.firstIndex(of: "gold")!
        var cs = arpMachines()
        var on = OnConfig(); on.hold = .oct; on.octUp = true; cs[gold].on = on
        let b = box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // grid (0,0) = index 0
        func notes(held: Bool) -> Set<UInt8> {
            let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
            let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
            let wb = Double(frames) * tempo / 60.0 / sr
            var beat = 0.0, ts = 0.0
            while beat < 2.0 {
                router.process(box: b, pool: chord([60]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, heldCell: held ? 0 : -1, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
            return Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        }
        XCTAssertTrue(notes(held: false).contains(60), "not held: the arp sounds note 60")
        XCTAssertFalse(notes(held: false).contains(72), "not held: no octave shift")
        XCTAssertTrue(notes(held: true).contains(72), "held (ON HOLD=OCT up): 60 shifts to 72")
        XCTAssertFalse(notes(held: true).contains(60), "held: the un-shifted note is gone")
    }

    // The activation + deactivation edges flush — no stuck notes when PREVIEW is released.
    func testPreviewLeavesNothingStuckOnRelease() {
        let gold = machineIDs.firstIndex(of: "gold")!
        let b = box(machines: arpMachines()) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0001, -1), beats: 8, into: e)
        var diag = KernelDiag()      // release PREVIEW → the deactivation edge flushes
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // MARK: - receiver SOLO (receiver strip) — audible = ¬muted ∧ (soloSet = ∅ ∨ member)

    /// A box whose cells subscribe to four OMNI receivers (so all hear the chord; solo differs by receiver).
    private func receiverBox(mute: [Bool] = [false, false, false, false],
                             _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(machines: arpMachines(), scenes: [s])
        st.receivers = (0..<4).map { var r = Receiver(name: "\($0 + 1)"); r.muted = mute[$0]; return r }
        return SnapshotBuilder.build(from: st)
    }
    private func soloOns(_ box: SnapshotBox, solo: UInt8, cable: UInt8) -> Int {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 8.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, soloReceiverMask: solo, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        return e.ons.filter { $0.cable == cable }.count
    }

    func testReceiverSoloExcludesNonMembers() {
        // gold ⇐R1 → A, cyan ⇐R2 → B. Solo R1 → only A sounds; solo R2 → only B; empty → both; union → both.
        let b = receiverBox {
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
            $0.cells[0][1] = { var c = Cell(machineID: "cyan", buses: [.b]); c.inputReceiver = 1; return c }()
        }
        XCTAssertGreaterThan(soloOns(b, solo: 0, cable: 1), 0, "no solo ⇒ A sounds")
        XCTAssertGreaterThan(soloOns(b, solo: 0, cable: 2), 0, "no solo ⇒ B sounds")
        XCTAssertGreaterThan(soloOns(b, solo: 0b0001, cable: 1), 0, "solo R1 ⇒ A sounds")
        XCTAssertEqual(soloOns(b, solo: 0b0001, cable: 2), 0, "solo R1 ⇒ B (R2) silent")
        XCTAssertEqual(soloOns(b, solo: 0b0010, cable: 1), 0, "solo R2 ⇒ A (R1) silent")
        XCTAssertGreaterThan(soloOns(b, solo: 0b0010, cable: 2), 0, "solo R2 ⇒ B sounds")
        XCTAssertGreaterThan(soloOns(b, solo: 0b0011, cable: 1), 0, "multi-solo union ⇒ A sounds")
        XCTAssertGreaterThan(soloOns(b, solo: 0b0011, cable: 2), 0, "multi-solo union ⇒ B sounds")
    }

    func testReceiverSoloMutedMemberStaysSilent() {
        // R1 muted; solo R1. A member that is muted still hears nothing (console convention).
        let b = receiverBox(mute: [true, false, false, false]) {
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        }
        XCTAssertEqual(soloOns(b, solo: 0b0001, cable: 1), 0, "a soloed BUT muted receiver stays silent")
    }

    // (grid-chaining retired: the solo-silences-chained-feed test was removed — no cross-cell feeds.)

    // MARK: - receiver OCT nudge (receiver strip) — ephemeral ±octave, composes with machine transpose

    private func packOct(_ recv: Int, _ oct: Int) -> UInt32 { UInt32(UInt8(bitPattern: Int8(oct))) << (UInt32(recv) * 8) }
    private func octNotes(_ box: SnapshotBox, inputOctave: UInt32, cable: UInt8) -> Set<UInt8> {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 8.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, inputOctave: inputOctave, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        return Set(e.ons.filter { $0.cable == cable }.map { $0.note })
    }

    func testReceiverOctaveShiftsSubscribers() {
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }() }
        XCTAssertTrue(octNotes(b, inputOctave: 0, cable: 1).contains(60), "base ⇒ 60 sounds")
        let up = octNotes(b, inputOctave: packOct(0, 1), cable: 1)
        XCTAssertTrue(up.contains(72), "+1 oct on R1 ⇒ 60 becomes 72")
        XCTAssertFalse(up.contains(60), "the base 60 is gone once shifted")
        XCTAssertTrue(octNotes(b, inputOctave: packOct(0, -1), cable: 1).contains(48), "−1 oct ⇒ 48")
        // a nudge on a DIFFERENT receiver leaves this cell untouched
        XCTAssertTrue(octNotes(b, inputOctave: packOct(1, 2), cable: 1).contains(60), "R2's nudge doesn't move an R1 cell")
    }

    func testReceiverOctaveComposesWithMachineTranspose() {
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!].transpose = 2      // +2 semitones on the machine
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(machines: cs, scenes: [s]); st.receivers = (0..<4).map { Receiver(name: "\($0 + 1)") }
        let b = SnapshotBuilder.build(from: st)
        XCTAssertTrue(octNotes(b, inputOctave: packOct(0, 1), cable: 1).contains(74), "+2 semis + 1 oct ⇒ 60→74")
    }

    // (grid-chaining retired: the octave-inherited-through-chain test was removed — no cross-cell feeds.)

    // MARK: - receiver INPUT-velocity override (the slider) — momentary absolute, keyed on the receiver

    private func velsOn(_ box: SnapshotBox, inputVel: UInt32, cable: UInt8, emitterVel: UInt32 = 0) -> Set<UInt8> {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 8.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, velOverride: emitterVel,
                           inputVelOverride: inputVel, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        return Set(e.ons.filter { $0.cable == cable }.map { $0.vel })
    }

    func testReceiverInputVelocityFlattensSubscribers() {
        // gold ⇐R1 → A, cyan ⇐R2 → B. An input override on R1 flattens A's notes; B is untouched.
        let b = receiverBox {
            $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
            $0.cells[0][1] = { var c = Cell(machineID: "cyan", buses: [.b]); c.inputReceiver = 1; return c }()
        }
        XCTAssertEqual(velsOn(b, inputVel: 0, cable: 1), [100], "natural base velocity = the source note's velocity (was flat 96)")
        XCTAssertEqual(velsOn(b, inputVel: packVel(0, 40), cable: 1), [40], "R1 override flattens A to 40")
        XCTAssertEqual(velsOn(b, inputVel: packVel(0, 40), cable: 2), [100], "an R1 override leaves R2's B natural (source velocity)")
    }

    func testEmitterOverrideWinsOverInputOverride() {
        // Both ride at once: input R1 = 40, emitter A = 110 → the OUTPUT override (closest to the wire) wins.
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }() }
        XCTAssertEqual(velsOn(b, inputVel: packVel(0, 40), cable: 1, emitterVel: packVel(0, 110)), [110],
                       "emitter (output) override wins over the input override")
    }

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

    private func latchNotes(_ box: SnapshotBox, live: NotePool, latchMask: UInt8, pools: [NotePool], cable: UInt8) -> Set<UInt8> {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 8.0 {
            router.process(box: box, pool: live, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, latchMask: latchMask, latchedPools: pools, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: live, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        return Set(e.ons.filter { $0.cable == cable }.map { $0.note })
    }

    func testLatchedPoolSubstitutesForLive() {
        // gold ⇐R1 arp. Live = [60]; the frozen R1 pool = [67, 72]. Armed ⇒ the cell arps the FROZEN chord.
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }() }
        let frozen = NotePool(); frozen.noteOn(67, velocity: 100, channel: 0); frozen.noteOn(72, velocity: 100, channel: 0); frozen.rebuildSorted()
        let pools = [frozen, NotePool(), NotePool(), NotePool()]
        let latched = latchNotes(b, live: chord([60]), latchMask: 0b0001, pools: pools, cable: 1)
        XCTAssertTrue(latched.contains(67) && latched.contains(72), "armed ⇒ arps the frozen chord")
        XCTAssertFalse(latched.contains(60), "…not the live note")
        XCTAssertTrue(latchNotes(b, live: chord([60]), latchMask: 0, pools: pools, cable: 1).contains(60),
                      "disarmed ⇒ reads the live pool (physical holds persist)")
    }

    func testLatchArmDisarmEdgeLeavesNothingStuck() {
        // Arming then disarming mid-run swaps the pool; the edge flush must leave nothing stuck.
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputReceiver = 0; return c }() }
        let frozen = NotePool(); frozen.noteOn(67, velocity: 100, channel: 0); frozen.rebuildSorted()
        let pools = [frozen, NotePool(), NotePool(), NotePool()]
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func windows(_ mask: UInt8, _ n: Int) {
            for _ in 0..<n {
                router.process(box: b, pool: chord([60]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, latchMask: mask, latchedPools: pools, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
        }
        windows(0, 24); windows(0b0001, 24); windows(0, 24)      // live → latched → live
        router.process(box: b, pool: chord([60]), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // MARK: - emitter OUTPUT OCT nudge (emitter strip) — shifts the outgoing note, keyed on the bus

    private func packEmitOct(_ bus: Int, _ oct: Int) -> UInt32 { UInt32(UInt8(bitPattern: Int8(oct))) << (UInt32(bus) * 8) }
    private func emitOctNotes(_ box: SnapshotBox, emitterOctave: UInt32, cable: UInt8, chordNotes: [UInt8] = [60, 64, 67]) -> Set<UInt8> {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord(chordNotes); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 8.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, emitterOctave: emitterOctave, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        return Set(e.ons.filter { $0.cable == cable }.map { $0.note })
    }

    func testEmitterOctaveShiftsOutputKeyedOnBus() {
        // gold → E1 (cable 1), cyan → E2 (cable 2). +1 oct on E1 lifts E1's output; E2 is untouched.
        let b = box(machines: arpMachines()) {
            $0.cells[0][0] = Cell(machineID: "gold", buses: [.a])
            $0.cells[0][1] = Cell(machineID: "cyan", buses: [.b])
        }
        XCTAssertTrue(emitOctNotes(b, emitterOctave: 0, cable: 1).contains(60), "base ⇒ 60 on E1")
        let up = emitOctNotes(b, emitterOctave: packEmitOct(0, 1), cable: 1)
        XCTAssertTrue(up.contains(72) && !up.contains(60), "+1 oct on E1 ⇒ 60→72")
        XCTAssertTrue(emitOctNotes(b, emitterOctave: packEmitOct(0, 1), cable: 2).contains(60), "E2 (bus 1) unshifted")
    }

    func testEmitterOctaveDropsOutOfRangeNotes() {
        // a high note pushed past 127 by the shift is dropped (no voice, no stuck note).
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        XCTAssertTrue(emitOctNotes(b, emitterOctave: 0, cable: 1, chordNotes: [120]).contains(120), "120 sounds at base")
        XCTAssertTrue(emitOctNotes(b, emitterOctave: packEmitOct(0, 1), cable: 1, chordNotes: [120]).isEmpty,
                      "120 + 12 = 132 > 127 ⇒ dropped")
    }

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

    func testFlattenDucksOtherEmittersWhileSounding() {
        // A (identity hold) FLATTENs at 50%; B's new arp notes arrive velocity-scaled to 50 (100·50%).
        // (Natural velocity is now the SOURCE velocity 100, not a flat 96 — user 2026-08-09.)
        XCTAssertTrue(velsForCable(flattenBox(0b0001, [50, 0, 0, 0]), cable: 2).contains(50),
                      "A flatten 50% ⇒ B's new notes duck to 50")
        XCTAssertEqual(velsForCable(flattenBox(0, [50, 0, 0, 0]), cable: 2), [100], "no flatten ⇒ B natural (source velocity 100)")
        XCTAssertEqual(velsForCable(flattenBox(0b0010, [0, 50, 0, 0]), cable: 2), [100],
                       "an emitter's own FLATTEN never ducks itself — only OTHER emitters")
    }

    func testFlattenDoesNotDuckTheSoundingEmitter() {
        // A holds and FLATTENs; A's OWN held notes are never lurched — its cable-1 velocity stays natural.
        XCTAssertEqual(velsForCable(flattenBox(0b0001, [50, 0, 0, 0]), cable: 1), [100],
                       "the sounding FLATTEN emitter keeps its own natural (source) velocity")
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

    func testAltTurnTakingPingPongsAndHonoursCount() {
        // Without ALT, a cell fanning to A+B emits EVERY note on BOTH — c1 == c2 == N.
        let (n1, n2) = altCableCounts(altBox(0, [1, 1, 1, 1]))
        XCTAssertEqual(n1, n2); XCTAssertGreaterThan(n1, 0)
        // ALT ping-pong (count 1 each): each note routes to ONE member, alternating → balanced, and c1+c2 == N.
        let (a1, a2) = altCableCounts(altBox(0b0011, [1, 1, 1, 1]))
        XCTAssertGreaterThan(a1, 0); XCTAssertGreaterThan(a2, 0)
        XCTAssertLessThanOrEqual(abs(a1 - a2), 1, "ping-pong balances the turns")
        XCTAssertEqual(a1 + a2, n1, "each note routes to ONE group member, not both")
        // COUNT: A holds the turn for 2 notes, B for 1 → A gets roughly twice B's turns.
        let (b1, b2) = altCableCounts(altBox(0b0011, [2, 1, 1, 1]))
        XCTAssertGreaterThan(b1, b2, "A (count 2) takes more turns than B (count 1)")
    }

    // MARK: - MASTER panel — KEY (per-scene transpose) · MUTE · the master velocity fader · PANIC

    private func masterBox(key: Int = 0, mute: Bool = false) -> SnapshotBox {
        var s = SceneState.empty(); s.masterKey = key
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // an arp on Emit A
        var st = PluginState(machines: arpMachines(), scenes: [s]); st.masterMute = mute
        return SnapshotBuilder.build(from: st)
    }
    private func runMaster(_ box: SnapshotBox, masterVel: UInt8 = 0, emitVel: UInt32 = 0, cable: UInt8) -> (Set<UInt8>, Set<UInt8>) {
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < 8.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, velOverride: emitVel, masterVelOverride: masterVel,
                           out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
        let ons = e.ons.filter { $0.cable == cable }
        return (Set(ons.map { $0.note }), Set(ons.map { $0.vel }))
    }

    func testMasterKeyTransposesAllOutput() {
        XCTAssertTrue(runMaster(masterBox(key: 5), cable: 1).0.contains(65), "master KEY +5 ⇒ 60→65")
        XCTAssertTrue(runMaster(masterBox(), cable: 1).0.contains(60), "no key ⇒ 60")
        XCTAssertFalse(runMaster(masterBox(key: 5), cable: 1).0.contains(60), "…and the un-shifted 60 is gone")
    }

    func testMasterMuteSilencesAllOutput() {
        XCTAssertTrue(runMaster(masterBox(mute: true), cable: 1).0.isEmpty, "master MUTE ⇒ total silence")
        XCTAssertTrue(runMaster(masterBox(mute: true), cable: 0).0.isEmpty, "…on All too")
    }

    func testMasterFaderForcesVelocityAndWinsOverEmitterOverride() {
        XCTAssertEqual(runMaster(masterBox(), masterVel: 40, cable: 1).1, [40], "the master fader forces 40")
        XCTAssertEqual(runMaster(masterBox(), masterVel: 40, emitVel: packVel(0, 110), cable: 1).1, [40],
                       "the master fader wins over the emitter override (applied last)")
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

    func testRestartPassReanchorsToColumnZero() {
        let b = box(machines: arpMachines()) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) } }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func win(_ restart: Bool = false) {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, sceneRestart: restart, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        for _ in 0..<60 { win() }                        // advance well past column 0
        XCTAssertGreaterThan(diag.effColumn, 0, "we've advanced into the pass")
        win(true)                                        // RESTART — this moment becomes column 0
        XCTAssertEqual(diag.effColumn, 0, "RESTART re-anchors the pass to column 0")
        for _ in 0..<30 { win() }                        // > one column of step (2 beats) → advances off 0
        XCTAssertGreaterThan(diag.effColumn, 0, "…and the pass advances forward again from the top")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // MARK: - §4b THE FADER-KILL: a velocity fader at the bottom = full silence (suppress + close), momentary

    func testEmitterFaderKillSuppressesNewNotesThenResumes() {
        let b = box(machines: arpMachines()) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) } }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func win(kill: UInt8 = 0) {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, velKillMask: kill, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        for _ in 0..<20 { win() }
        XCTAssertGreaterThan(e.ons.count, 0, "emitter A emits normally")
        let onsAtKill = e.ons.count
        for _ in 0..<12 { win(kill: 0b0001) }              // KILL A (the fader at its bottom)
        XCTAssertEqual(e.ons.count, onsAtKill, "while killed, emitter A emits NO new note-ons")
        let onsAtRelease = e.ons.count
        for _ in 0..<15 { win() }                          // RELEASE the fader
        XCTAssertGreaterThan(e.ons.count, onsAtRelease, "releasing the fader resumes emission")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    func testFaderKillClosesASustainedNote() {
        // An identity HOLD sustains the chord on A → the kill edge must send its note-offs (the DJ drop).
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!] = { var c = Machine(machineID: "gold", type: .empty); return c }()
        let b = box(machines: cs) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) } }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func win(kill: UInt8 = 0) {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, velKillMask: kill, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        for _ in 0..<6 { win() }
        XCTAssertGreaterThan(e.ons.count, 0, "the hold sounds")
        let offsBefore = e.offs.count
        win(kill: 0b0001)                                  // fader DOWN → the sustained note closes
        XCTAssertGreaterThan(e.offs.count, offsBefore, "the kill edge closed the sustained note")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

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

    func testLegatoDroneShouldContinueAcrossColumnBoundary() {
        // §2 THE DRONE LAW: identical adjacent LEGATO cells + held input ⇒ the voice CONTINUES — ZERO note-off/on
        // should cross the boundary (PASS · LEGATO · GATE 100 = a drone that flows). Boundary ADOPTION keeps a
        // matching voice (same note+emitter+machine/face); the chord is struck ONCE and never re-speaks.
        let r = droneOffs(phase: .legato)
        XCTAssertEqual(r.offs, 0, "LEGATO drone: ZERO note-offs should cross a boundary")
        XCTAssertEqual(r.ons, 6, "struck exactly ONCE (3 notes × 2 cables) — no re-strike at any boundary")
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

    func testFencedLegatoDroneStillDronesAcrossBoundaries() {
        let clamped = fencedDroneOffs(policy: 1, lo: 72, hi: 84)   // note 60 clamps up to 72, the same every column
        XCTAssertEqual(clamped.offs, 0, "a fenced legato drone adopts across boundaries — no re-strike")
        XCTAssertEqual(clamped.ons, 2, "struck once: 1 note × 2 cables (own A + All)")
    }

    func testRetrigDroneReStrikesAtEachColumnEntry() {
        // §2 the complement: under RETRIG the chord RE-STRIKES each column — off/on pairs cross every boundary.
        // (Currently the engine re-strikes regardless of phase; this pins the re-strike side of the pair.)
        let r = droneOffs(phase: .retrig)
        XCTAssertGreaterThan(r.offs, 0, "RETRIG: the chord re-strikes at each column entry (off/on per boundary)")
        XCTAssertEqual(r.offs % 6, 0, "each re-strike = 3 notes × 2 cables (own + All)")
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

    func testPartialRowLegatoDroneIsPassLengthEnvelope() {
        // §2 item 2③: a LEGATO drone that occupies only SOME columns = a PASS-LENGTH ENVELOPE — it CLOSES when
        // the playhead leaves its last column (first empty column) and RE-OPENS at the wrap. Contrast the
        // full-row drone (testLegatoDrone…), which never closes.
        let d = partialDrone(); var diag = KernelDiag(); var beat = 0.0, ts = 0.0
        for _ in 0..<480 {   // ≥ 2 full 8-column passes (a pass ≈ 192 windows at the default step)
            d.router.process(box: d.box, pool: d.pool, playing: true, beatPos: beat, tempo: d.tempo, sampleRate: d.sr,
                             timestampSample: ts, frameCount: d.frames, out: d.e, diag: &diag)
            beat += d.wb; ts += Double(d.frames)
        }
        XCTAssertGreaterThan(d.e.offs.count, 0, "the drone CLOSES when the playhead leaves column 0 (the envelope)")
        XCTAssertEqual(d.e.offs.count % 6, 0, "closes the whole chord (3 notes × 2 cables) cleanly")
        XCTAssertGreaterThan(d.e.ons.count, 6, "and RE-OPENS at each wrap — struck more than once")
    }

    func testLegatoDroneClosesOnTransportStop() {
        // §2 invariant 4: an IMMORTAL (offSample .max) legato drone is not a stuck note — a transport-stop
        // edge closes it like any other voice, leaving silence.
        var cs = arpMachines()
        cs[machineIDs.firstIndex(of: "gold")!] = { var c = Machine(machineID: "gold", type: .empty); c.paramsA.phase = .legato; return c }()
        let b = box(machines: cs) { for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]) } }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        for _ in 0..<24 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        XCTAssertGreaterThan(e.ons.count, 0, "the drone sounded")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)   // transport STOP
        assertNothingLeftSounding(e)
    }

    func testMasterFaderKillSilencesEveryEmitter() {
        let b = box(machines: arpMachines()) {
            for c in 0..<8 { $0.cells[c][0] = Cell(machineID: "gold", buses: [.a]); $0.cells[c][1] = Cell(machineID: "cyan", buses: [.b]) }
        }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let pool = chord([60, 64, 67]); let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        func win(master: Bool = false) {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, masterKill: master, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        for _ in 0..<20 { win() }
        XCTAssertGreaterThan(e.ons.count, 0, "both emitters emit normally")
        let onsAtKill = e.ons.count
        for _ in 0..<12 { win(master: true) }              // master fader DOWN = all silent
        XCTAssertEqual(e.ons.count, onsAtKill, "master kill silences EVERY emitter")
        let onsAtRelease = e.ons.count
        for _ in 0..<15 { win() }                          // release
        XCTAssertGreaterThan(e.ons.count, onsAtRelease, "release resumes")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // (grid-chaining retired: the PASS→ARP cell-to-cell routing tests were removed — chains live in cells now.)

    // MARK: - ALT edge: advance-until-present (no starvation of a partial fan-out)

    func testAltDealsSingleTargetNotesAcrossTheGroup() {
        // The user's intent (2026-08-04): the TURNS emitters take turns playing INCOMING notes from ANY cell. A
        // single cell targets ONLY emitter A, but A and B are a TURNS group → its notes are DEALT across both A
        // and B (the old per-fan-out ALT left everything on A, because B was never in the note's own fan-out).
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])       // ONE cell → A only
        var st = PluginState(machines: arpMachines(), scenes: [s]); st.altMask = 0b0011; st.altCount = [1, 1, 1, 1]
        let box = SnapshotBuilder.build(from: st)
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
        let a = e.ons.filter { $0.cable == 1 }.count, b = e.ons.filter { $0.cable == 2 }.count   // A=cable1, B=cable2
        XCTAssertGreaterThan(a, 0, "A takes its turns")
        XCTAssertGreaterThan(b, 0, "B receives dealt notes too — despite no cell addressing it (the fix)")
        XCTAssertLessThanOrEqual(abs(a - b), 1, "the group deals evenly (count 1 each)")
    }

    func testAltPoolsTwoIndependentCellsAcrossTheGroup() {
        // Two INDEPENDENT cells (cell 1 → A, cell 2 → B), group {A,B} → their incoming notes POOL and interleave
        // across the group. Both emitters sound and the total is conserved (each note routes to ONE member).
        func run3(_ altMask: UInt8) -> (Int, Int) {
            var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // cell 1 → A
            s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // cell 2 → B
            var st = PluginState(machines: arpMachines(), scenes: [s]); st.altMask = altMask; st.altCount = [1, 1, 1, 1]
            let box = SnapshotBuilder.build(from: st)
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
        let (n1, n2) = run3(0)             // no TURNS: each cell emits on its own bus
        let (a1, a2) = run3(0b0011)        // TURNS {A,B}: the two streams pool and interleave
        XCTAssertGreaterThan(a1, 0); XCTAssertGreaterThan(a2, 0, "both emitters take turns")
        XCTAssertEqual(a1 + a2, n1 + n2, "every note still routes to exactly ONE member (total conserved)")
    }

    func testAltHoldsAtSameMomentDoNotSplitSimultaneously() {
        // The user's bug (2026-08-04): two HOLD cells fire at the SAME instant (column 0 entry) — gold → A, cyan
        // → B, TURNS {A,B}, COUNT 1. They must both route to the ONE turn-holder for that moment (A), NOT split
        // A/B simultaneously (count 1 previously played both at once). The turn advances per onset MOMENT, so a
        // single moment picks a single emitter.
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // identity hold → A
        s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // identity hold → B
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
        st.altMask = 0b0011; st.altCount = [1, 1, 1, 1]
        let box = SnapshotBuilder.build(from: st)
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        router.process(box: box, pool: chord([60]), playing: true, beatPos: 0, tempo: 120,
                       sampleRate: 48_000, timestampSample: 0, frameCount: 2048, out: e, diag: &diag)
        let aOn = e.ons.contains { $0.cable == 1 }, bOn = e.ons.contains { $0.cable == 2 }
        XCTAssertNotEqual(aOn, bOn, "at one moment only ONE emitter sounds — the group hands off in TIME, no simultaneous split")
        XCTAssertTrue(aOn, "count 1 → the first turn-holder (A) takes this moment")
    }

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

    func testTurnsPerNoteDropsSimultaneousNoteNotDelayed() {
        // PER-NOTE TURNS (user 2026-08-05): the group's emitters are time-exclusive. Two cells fire at the SAME
        // onset (holds in column 0): only the FIRST plays (leftmost A); the simultaneous one is DROPPED — not
        // delayed. A single render window proves no delay (a delayed note would land in a later window, absent here).
        func onsPerCable(perNote: Bool) -> (a: Int, b: Int) {
            var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // hold → A
            s.cells[0][1] = Cell(machineID: "cyan", buses: [.b])   // hold → B (both strike at colStart)
            var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
            st.altMask = 0b0011; st.altCount = [1, 1, 1, 1]; st.turnsPerNote = perNote
            let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
            router.process(box: SnapshotBuilder.build(from: st), pool: chord([60]), playing: true, beatPos: 0,
                           tempo: 120, sampleRate: 48_000, timestampSample: 0, frameCount: 2048, out: e, diag: &diag)
            return (e.ons.filter { $0.cable == 1 }.count, e.ons.filter { $0.cable == 2 }.count)
        }
        let moment = onsPerCable(perNote: false)   // PER-MOMENT: both cells route to the one holder (A)
        let note = onsPerCable(perNote: true)      // PER-NOTE: only the first plays; the simultaneous note DROPS
        XCTAssertEqual(moment.b, 0, "per-moment: B silent (both routed to the holder A)")
        XCTAssertEqual(note.b, 0, "per-note: B silent too — never two group emitters at once")
        XCTAssertGreaterThan(note.a, 0, "per-note: the first note still plays on the leftmost (A)")
        XCTAssertGreaterThan(moment.a, note.a, "per-note DROPS the simultaneous note (fewer ons than per-moment) — not delayed")
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

    func testCurveRemapsOutputVelocityAndIsRackGated() {
        func vel(_ amount: Int, on: Bool = true, rack: UInt8? = nil) -> Int {
            let e = RecordingEmitter()
            run(curveBox(amount: amount, on: on, rack: rack), chord([60]), beats: 16, into: e)
            return Int(e.ons.first { $0.cable == 1 }!.vel)
        }
        let base = vel(0, on: false)                        // curve off → identity (the raw source velocity)
        XCTAssertGreaterThan(vel(50), base, "+50 boosts low velocities (harder)")
        XCTAssertLessThan(vel(-50), base, "−50 softens")
        XCTAssertEqual(vel(0), base, "amount 0 (armed) is linear = identity")
        XCTAssertEqual(vel(50, rack: 0b1110), base, "rack out of path ⇒ CURVE suspended (raw velocity)")
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

    func testFencePolicyDropClampFoldAndRackGate() {
        XCTAssertTrue(fenceOut(policy: 0, lo: 64, hi: 72).isEmpty, "DROP: 60 is below the window → suppressed")
        XCTAssertEqual(fenceOut(policy: 1, lo: 64, hi: 72), [64], "CLAMP: 60 → the low bound 64")
        XCTAssertEqual(fenceOut(policy: 2, lo: 72, hi: 96), [72], "FOLD: 60 octave-folds up to 72")
        XCTAssertEqual(fenceOut(policy: 0, lo: 48, hi: 72), [60], "in range → passes unchanged")
        XCTAssertEqual(fenceOut(policy: 0, lo: 64, hi: 72, rack: 0b1110), [60], "rack out of path ⇒ FENCE suspended (raw)")
    }

    /// FENCE FOLD edges: folds DOWN (note above hi), FALLS BACK to clamp when the window can't fit an octave, and
    /// an INVERTED window (lo > hi) fences nothing (a stray narrow/reversed window must never leak an out-of-range note).
    func testFenceFoldDownwardNarrowFallbackAndInvertedWindow() {
        XCTAssertEqual(fenceOut(policy: 2, lo: 36, hi: 48), [48], "FOLD down: 60 → 48 (above hi folds by −12)")
        XCTAssertEqual(fenceOut(policy: 2, lo: 64, hi: 66), [64], "FOLD in a sub-octave window can't fold → clamps to 64")
        XCTAssertEqual(fenceOut(policy: 2, lo: 72, hi: 48), [60], "inverted window (lo>hi) fences nothing → 60 passes")
    }

    /// CURVE never floors a note-on to velocity 0 (synths read vel-0 note-on as note-off → a stuck/ghost note).
    func testCurveNeverEmitsVelocityZero() {
        let e = RecordingEmitter()
        let p = NotePool(); p.noteOn(60, velocity: 2, channel: 0)     // a barely-there note
        run(curveBox(amount: -100), p, beats: 16, into: e)            // maximal softening → toward 0
        let vels = e.ons.filter { $0.cable == 1 }.map { $0.vel }
        XCTAssertFalse(vels.isEmpty, "the note still sounds")
        XCTAssertTrue(vels.allSatisfy { $0 >= 1 }, "output velocity is floored to 1, never 0")
    }

    /// POCKET push (−ms) can't schedule a note-on before the render window's first sample (an invalid negative time).
    func testPocketPushDoesNotScheduleBeforeWindowStart() {
        var s = SceneState.empty(); s.cells[0][0] = Cell(machineID: "gold", buses: [.a])
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
        st.pocketMask = 0b0001; st.pocketMs = [-30, 0, 0, 0]          // a strong push, at the column start
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        router.process(box: SnapshotBuilder.build(from: st), pool: chord([60]), playing: true, beatPos: 0,
                       tempo: 120, sampleRate: 48_000, timestampSample: 0, frameCount: 2048, out: e, diag: &diag)
        let onset = e.ons.first { $0.cable == 1 }!.sample
        XCTAssertGreaterThanOrEqual(onset, 0, "a push clamps to renderStart — never a negative sample time")
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

    func testMonoKeepsOneNotePerEmitterByPriority() {
        XCTAssertEqual(monoSounding(priority: 0).count, 1, "MONO LAST → exactly one note sounds on A")
        XCTAssertEqual(monoSounding(priority: 1), [60], "MONO LOW → the lower note survives")
        XCTAssertEqual(monoSounding(priority: 2), [64], "MONO HIGH → the higher note survives")
    }

    func testMonoLeavesNoStuckNotes() {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])
        var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s]); st.monoMask = 0b0001
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 16, into: e)
        assertNothingLeftSounding(e)
    }

    // MONO stealing a GLIDE anchor (Paul 2026-09-01 bug-hunt Finding 4): a MONO voice-steal can close an IMMORTAL glide
    // anchor; the glide subsystem must FORGET that slot (forgetGlideAnchorAtSlot), else a later glide update wrong-closes the
    // now-reused slot (a spurious off). Put an ARP (strikes changing notes → repeatedly steals under MONO) AND a [GLIDE] on
    // the SAME emitter (bus A) with MONO armed, hold a chord across many windows, release, stop → the churn must leave nothing
    // stuck AND stay deterministic (a stale-slot wrong-close is order-sensitive). First coverage of the glide+MONO+steal path.
    func testMonoStealingAGlideAnchorLeavesNoStuckNotes() {
        func makeBox() -> SnapshotBox {
            var cs = arpMachines(); cs[machineIDs.firstIndex(of: "orange")!].type = .glide
            var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])                     // ARP on A — changing notes steal under MONO
            s.cells[0][1] = { var x = Cell(machineID: "orange", buses: [.a])         // GLIDE on A — its anchor is the immortal voice MONO steals
                var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glideRange = 12
                g.params.glidePriority = .last; g.params.glideTime = 0.1; x.processors = [g]; return x }()
            var st = PluginState(machines: cs, scenes: [s]); st.monoMask = 0b0001; st.monoPriority = [0, 0, 0, 0]   // MONO LAST on A
            return SnapshotBuilder.build(from: st)
        }
        let e = RecordingEmitter(); run(makeBox(), chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "notes sounded on A")
        assertNothingLeftSounding(e)
        let e2 = RecordingEmitter(); run(makeBox(), chord([60, 64, 67]), beats: 16, into: e2)
        XCTAssertEqual(e.events.count, e2.events.count, "deterministic under the glide+MONO churn (a stale-slot wrong-close would vary)")
    }

    // MARK: - THE RACK — POCKET (per-emitter timing feel)

    func testPocketLagDelaysOnsetAndIsRackGated() {
        func onset(ms: Int, rack: UInt8? = nil) -> Int64 {
            var s = SceneState.empty()
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a])
            var st = PluginState(machines: claimMachines(transposeB: 0), scenes: [s])
            st.pocketMask = 0b0001; st.pocketMs = [ms, 0, 0, 0]; st.rackEnabledMask = rack
            let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
            router.process(box: SnapshotBuilder.build(from: st), pool: chord([60]), playing: true, beatPos: 0,
                           tempo: 120, sampleRate: 48_000, timestampSample: 0, frameCount: 2048, out: e, diag: &diag)
            return e.ons.first { $0.cable == 1 }!.sample
        }
        XCTAssertEqual(onset(ms: 0), 0, "no offset → onset at the column start")
        XCTAssertGreaterThan(onset(ms: 10), onset(ms: 0), "lay-back (+ms) delays the onset")
        XCTAssertEqual(onset(ms: 10, rack: 0b1110), onset(ms: 0), "rack out of path ⇒ POCKET suspended")
    }

    // MARK: - WIRE ARTICULATION — same-note overlap on one emitter (design ASK 2026-08-05)

    /// Two holders of note 60 on emitter A (a "drone" + a same-note strike sharing the wire). Documents the CURRENT
    /// wire behaviour for the articulation ASK: §7 clause 1 (note-ons ALWAYS emit) means the wire does NOT
    /// consolidate — BOTH holders' note-ons reach A in one window (so a same-note strike is AUDIBLE, not silent as
    /// the ASK's premise assumed). The proposed off-before-on re-articulation would ADD a paired off; not built —
    /// awaits Paul's RESTRIKE | MERGE word. And across a full run the shared note still pairs off with no stuck note.
    func testSameNoteOverlapOnOneEmitterEmitsBothNoteOns() {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(machineID: "gold", buses: [.a])
        s.cells[0][1] = Cell(machineID: "gold", buses: [.a])
        let box = SnapshotBuilder.build(from: PluginState(machines: claimMachines(transposeB: 0), scenes: [s]))
        // ONE window: both holders strike note 60 → two note-ons on A (no consolidation).
        let e1 = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        router.process(box: box, pool: chord([60]), playing: true, beatPos: 0, tempo: 120,
                       sampleRate: 48_000, timestampSample: 0, frameCount: 2048, out: e1, diag: &diag)
        XCTAssertEqual(e1.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 2,
                       "both holders' note-ons emit — the wire does NOT consolidate same-note (clause 1)")
        // A full hold→release run pairs the shared note off exactly, no stuck note.
        let e2 = RecordingEmitter()
        run(box, chord([60]), beats: 16, into: e2)
        assertNothingLeftSounding(e2)
    }

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

    func testConversationWithAndAgainstGateOnTheLead() {
        // WITH (1): B sounds only while the lead A sounds.
        XCTAssertGreaterThan(convOut(stance: [0, 1, 0, 0]).1, 0, "WITH + lead present → B admitted")
        XCTAssertEqual(convOut(stance: [0, 1, 0, 0], leadPresent: false).1, 0, "WITH + lead silent → B suppressed")
        // AGAINST (2): B sounds only while the lead A is SILENT.
        XCTAssertEqual(convOut(stance: [0, 2, 0, 0]).1, 0, "AGAINST + lead present → B suppressed")
        XCTAssertGreaterThan(convOut(stance: [0, 2, 0, 0], leadPresent: false).1, 0, "AGAINST + lead silent → B admitted")
        // FREE (0): B is unaffected by the lead.
        XCTAssertGreaterThan(convOut(stance: [0, 0, 0, 0]).1, 0, "FREE → B always admitted")
    }

    // MARK: - the render-side parameter route (invariant 6)

    /// The SECOND param route: a render-side `.parameter` event overrides a value until the NEXT snapshot
    /// generation clears it (a real document edit is the new truth). CLAUDE.md invariant 6 says both routes must
    /// keep working; this drives a transpose event (address 100 = gold's transpose) end-to-end and asserts the
    /// wire pitch shifts, then reverts on a new generation. Previously untested at the Router level.
    func testRenderParamEventTransposesUntilNextGenerationClearsIt() {
        let cs = arpMachines()
        func gen(_ g: UInt64) -> SnapshotBox {
            var s = SceneState.empty(); s.cells[0][0] = Cell(machineID: "gold", buses: [.a])   // identity HOLD → emits the held note
            var st = PluginState(machines: cs, scenes: [s]); st.busChannels = [1, 2, 3, 4]
            return SnapshotBuilder.build(from: st, generation: g)
        }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        var beat = 0.0
        func win(_ box: SnapshotBox) {
            router.refreshOverrides(forGeneration: box.generation)   // the Kernel calls this each render, before events
            router.process(box: box, pool: chord([60]), playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000,
                           timestampSample: beat * 24_000, frameCount: 512, out: e, diag: &diag)
            beat += 0.25
        }
        win(gen(1))                                                  // baseline — no override
        XCTAssertTrue(e.ons.contains { $0.note == 60 }, "baseline sounds the held note")
        router.applyParamEvent(100, 12, atSample: 0, rampDurationSampleFrames: 0, diag: &diag)   // +12 on gold (address 100 = machine 0 transpose), a plain instant .parameter event
        let mark = e.events.count
        win(gen(1))                                                 // same generation → the override persists
        XCTAssertTrue(e.events[mark...].contains { $0.status == 0x90 && $0.note == 72 }, "the param event shifts gold +12")
        XCTAssertFalse(e.events[mark...].contains { $0.status == 0x90 && $0.note == 60 }, "…and 60 no longer sounds")
        let mark2 = e.events.count
        win(gen(2))                                                 // a NEW generation clears the override
        XCTAssertTrue(e.events[mark2...].contains { $0.status == 0x90 && $0.note == 60 }, "a new snapshot generation reverts to 60")
        XCTAssertGreaterThan(diag.paramEventCount, 0, "the event was counted")
        // release + stop to leave nothing stuck
        router.process(box: gen(2), pool: NotePool(), playing: false, beatPos: beat, tempo: 120, sampleRate: 48_000,
                       timestampSample: beat * 24_000, frameCount: 512, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    /// An UNMAPPED param address (no slot) is a silent no-op — it never traps, never writes an override.
    func testUnmappedParamEventIsANoOp() {
        let router = Router(); var diag = KernelDiag()
        router.applyParamEvent(9_999, 42, atSample: 0, rampDurationSampleFrames: 0, diag: &diag)
        XCTAssertEqual(diag.paramEventCount, 0, "an unmapped address applies nothing")
    }

    /// A genuine `.parameterRamp` event (rampDurationSampleFrames > 1) now smooths instead of stair-stepping:
    /// the override reads an intermediate value partway through the ramp window, reaches the target exactly at
    /// (or past) the ramp's end sample, and — since nothing had overridden this slot before the ramp — a FIRST
    /// touch with no known starting value snaps instead of guessing a baseline.
    func testRenderParamRampEventInterpolatesLinearlyThenSettles() {
        let cs = arpMachines()
        func gen(_ g: UInt64) -> SnapshotBox {
            var s = SceneState.empty(); s.cells[0][0] = Cell(machineID: "gold", buses: [.a])
            var st = PluginState(machines: cs, scenes: [s]); st.busChannels = [1, 2, 3, 4]
            return SnapshotBuilder.build(from: st, generation: g)
        }
        let router = Router(); var diag = KernelDiag()
        let box = gen(1)
        router.refreshOverrides(forGeneration: box.generation)
        // A FIRST touch at this slot is a ramp with no known prior override → snaps instantly to the target,
        // rather than fabricating a starting value. (address 100 = gold's transpose, same as the sibling test.)
        router.applyParamEvent(100, 7, atSample: 0, rampDurationSampleFrames: 1000, diag: &diag)
        var e = RecordingEmitter()
        router.process(box: box, pool: chord([60]), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                       timestampSample: 0, frameCount: 512, out: e, diag: &diag)
        XCTAssertTrue(e.ons.contains { $0.note == 67 }, "no prior override to ramp FROM → the first touch snaps straight to +7")
        // NOW arm a genuine ramp from the known current value (7) to a new target (19) over 1000 samples,
        // starting at this render's own sample time.
        router.applyParamEvent(100, 19, atSample: 1000, rampDurationSampleFrames: 1000, diag: &diag)
        e = RecordingEmitter()
        router.process(box: box, pool: chord([60]), playing: true, beatPos: 0.25, tempo: 120, sampleRate: 48_000,
                       timestampSample: 1500, frameCount: 512, out: e, diag: &diag)   // 500/1000 samples into the ramp → halfway: 7 + 0.5*(19-7) = 13
        XCTAssertTrue(e.ons.contains { $0.note == 73 }, "halfway through the ramp window the override reads the linear midpoint (+13), not a step straight to +19")
        e = RecordingEmitter()
        router.process(box: box, pool: chord([60]), playing: true, beatPos: 0.5, tempo: 120, sampleRate: 48_000,
                       timestampSample: 2100, frameCount: 512, out: e, diag: &diag)   // past the ramp's end sample (2000) → settled at the target
        XCTAssertTrue(e.ons.contains { $0.note == 79 }, "past the ramp's end sample the override has settled exactly at the target (+19)")
        // release + stop to leave nothing stuck
        router.process(box: box, pool: NotePool(), playing: false, beatPos: 1, tempo: 120, sampleRate: 48_000,
                       timestampSample: 2600, frameCount: 512, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // MARK: - the PLAYING CHANCE chord-hold path (distinct from audition/preview)

    /// The live emitColumnHolds CHANCE branch: probability 1 passes the whole chord, probability 0 silences it.
    /// Previously only the audition + preview chance paths were covered, not the playing one.
    func testPlayingChanceGatesOnProbability() {
        func chanceBox(_ p: Double) -> SnapshotBox {
            var cs = arpMachines(); let gi = machineIDs.firstIndex(of: "gold")!
            cs[gi] = Machine(machineID: "gold", type: .chance); cs[gi].paramsA.probability = p
            return box(machines: cs) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        }
        let on = RecordingEmitter(); run(chanceBox(1), chord([60, 64]), beats: 8, into: on)
        XCTAssertGreaterThan(on.ons.count, 0, "probability 1 → the chance chord sounds while playing")
        assertNothingLeftSounding(on)
        let off = RecordingEmitter(); run(chanceBox(0), chord([60, 64]), beats: 8, into: off)
        XCTAssertTrue(off.ons.isEmpty, "probability 0 → the chance cell is silent")
    }

    // MARK: - scene FLUSH closes the outgoing scene's voices

    /// A scene switch flushes the OLD scene's sounding voices at the switch sample — no stuck note straddling the
    /// change. Switch INTO an empty scene so the flush is observable in isolation. `sceneFlush` was only incidentally
    /// exercised by the fuzzer's quiescence check; this asserts the flush behaviour directly.
    func testSceneFlushClosesSoundingVoices() {
        let b = box(machines: arpMachines()) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }   // identity hold
        let empty = box(machines: arpMachines()) { _ in }                                               // the incoming (empty) scene
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        router.process(box: b, pool: chord([60]), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                       timestampSample: 0, frameCount: 512, out: e, diag: &diag)
        XCTAssertTrue(e.ons.contains { $0.note == 60 }, "the hold is sounding before the switch")
        router.process(box: empty, pool: chord([60]), playing: true, beatPos: 0.25, tempo: 120, sampleRate: 48_000,
                       timestampSample: 12_000, frameCount: 512, sceneFlush: true, out: e, diag: &diag)
        XCTAssertTrue(e.offs.contains { $0.note == 60 }, "the scene flush closes the old voice")
        assertNothingLeftSounding(e)   // nothing survives the switch into an empty scene
    }

    // MARK: - bypass: multiple destinations

    /// A bypassed door with a MULTI-emitter dest injects the held note on EACH selected cable (+ ALL), and
    /// releasing the key closes them all — the multi-dest case existing bypass tests (single dest) never cover.
    func testWireInjectsToMultipleDests() {
        let b = wireBox(dest: 0b0011)   // emitters A + B → cables 1 and 2
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60]), playing: true, beat: 0, out: e)
        XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == 1 }, "injected on emitter A")
        XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == 2 }, "injected on emitter B")
        XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == 0 }, "and on the ALL cable")
        stepWindow(router, b, NotePool(), playing: true, beat: 0.25, out: e)   // release the key
        XCTAssertTrue(e.offs.contains { $0.cable == 1 } && e.offs.contains { $0.cable == 2 }, "release closes both dests")
        assertNothingLeftSounding(e)
    }

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
    func testEchoInKeyWalksToNextInKeyNoteChainedFromLastLanded() {
        let b = echoInKeyBox(receivers: 0b0010, pitch: 1, repeats: 4, div: 4)   // bit 1 = receiver B (door 1)
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0)                                    // ECHO's own dry input (door 0)
        for n: UInt8 in [48, 52, 55] { pool.noteOn(n, velocity: 100, channel: 1) }     // the live IN-KEY reference (door 1): classes {0,4,7}
        let e = RecordingEmitter(); run(b, pool, beats: 5, into: e)
        let repeats = e.ons.filter { $0.cable == 1 && $0.note != 60 }   // exclude the dry strike at the source pitch
        XCTAssertFalse(repeats.isEmpty, "the walk produced at least one repeat")
        XCTAssertTrue(repeats.allSatisfy { [0, 4, 7].contains(Int($0.note) % 12) }, "every repeat lands on the reference's own pitch classes (C/E/G)")
        XCTAssertGreaterThanOrEqual(Set(repeats.map { $0.note }).count, 2, "the walk actually advances across repeats, not stuck on one note")
        assertNothingLeftSounding(e)
    }
    func testEchoInKeyReadsReceiverContentLiveNotSnapshotted() {
        let b = echoInKeyBox(receivers: 0b0010, pitch: 1, repeats: 3, div: 4)   // timeBeats = 1 beat/repeat → repeats at 1, 2, 3 beats
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0)   // ECHO's own dry input (door 0) — untouched throughout
        pool.noteOn(48, velocity: 100, channel: 1)   // reference (door 1) initially holds ONLY class 0 (C, via note 48)
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < 1.5 {   // covers repeat 1 (tau=1 beat), stops short of repeat 2 (tau=2 beats)
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let afterFirst = Set(e.ons.filter { $0.cable == 1 && $0.note != 60 }.map { Int($0.note) % 12 })
        XCTAssertEqual(afterFirst, [0], "repeat 1 landed using the ORIGINAL reference (class 0 only)")
        pool.noteOff(48); pool.noteOn(54, velocity: 100, channel: 1)   // swap the reference LIVE to class 6 (F#) before repeats 2/3 fire
        while beat < 4 {   // covers repeats 2 and 3 (tau=2, 3 beats)
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let laterClasses = Set(e.ons.filter { $0.cable == 1 && $0.note != 60 }.map { Int($0.note) % 12 })
        XCTAssertTrue(laterClasses.contains(6), "a later repeat reflects the NEW reference (class 6/F#), read live at its own fire time — not the class-0 snapshot from registration")
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)   // stop flush
        assertNothingLeftSounding(e)
    }
    func testEchoInKeyHoldsAtLastLandedWhenMaskGoesEmpty() {
        let b = echoInKeyBox(receivers: 0b0010, pitch: 1, repeats: 3, div: 4)
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0)
        pool.noteOn(48, velocity: 100, channel: 1)   // reference holds class 0 initially
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < 1.5 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let firstNote = e.ons.first { $0.cable == 1 && $0.note != 60 }?.note
        XCTAssertNotNil(firstNote, "repeat 1 landed on a real note")
        pool.noteOff(48)   // the reference goes SILENT (empty mask) — nothing else held on door 1
        while beat < 4 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        let allRepeatNotes = Set(e.ons.filter { $0.cable == 1 && $0.note != 60 }.map { $0.note })
        XCTAssertEqual(allRepeatNotes, Set([firstNote!]), "with the reference silent, later repeats HOLD at the last landed note rather than dropping or crashing")
        router.process(box: b, pool: NotePool(), playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }
    func testEchoInKeyZeroReceiversHoldsNotFlatSemitones() {
        let b = echoInKeyBox(receivers: 0, pitch: 3, repeats: 3, div: 4)   // no ABCD ticked; pitch=3 would climb chromatically in flat mode
        let pool = NotePool(); pool.noteOn(60, velocity: 100, channel: 0)
        let e = RecordingEmitter(); run(b, pool, beats: 4.5, into: e)
        let cable1 = e.ons.filter { $0.cable == 1 }
        XCTAssertGreaterThan(cable1.count, 1, "the dry strike PLUS at least one repeat actually fired")
        XCTAssertEqual(Set(cable1.map { $0.note }), [60], "zero receivers selected ⇒ nothing to walk to ⇒ every repeat holds at the dry note (60), not a flat +3-semitone climb (63,66,69,…) — holding also lands on 60, so this checks event COUNT separately from note VALUE")
        assertNothingLeftSounding(e)
    }
    /// Fast rate (div=1 → timeBeats=0.25) + an oversized render window spanning several repeat intervals, so
    /// repeats 1-3 all resolve inside the SAME call to drainEchoTails — the exact scenario the `inKeyWalk` local-var
    /// fix (read/written through the array, not the stale per-tail `e` snapshot taken before the k-loop) exists for.
    func testEchoInKeySameWindowMultipleRepeatsChainCorrectly() {
        let b = echoInKeyBox(receivers: 0b0010, pitch: 1, repeats: 3, div: 1)
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0)
        for n: UInt8 in [48, 52, 55] { pool.noteOn(n, velocity: 100, channel: 1) }   // reference: classes {0,4,7}
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 24576, sr = 48_000.0, tempo = 120.0   // ~1.02 beats/window — comfortably spans all 3 repeats (0.25, 0.5, 0.75)
        router.process(box: b, pool: pool, playing: true, beatPos: 0, tempo: tempo, sampleRate: sr,
                       timestampSample: 0, frameCount: frames, out: e, diag: &diag)
        router.process(box: b, pool: NotePool(), playing: false, beatPos: Double(frames) * tempo / 60.0 / sr, tempo: tempo,
                       sampleRate: sr, timestampSample: Double(frames), frameCount: frames, out: e, diag: &diag)   // stop flush
        let repeatNotes = e.ons.filter { $0.cable == 1 && $0.note != 60 }.map { $0.note }
        XCTAssertGreaterThanOrEqual(repeatNotes.count, 2, "at least 2 repeats fired within the single oversized window")
        XCTAssertEqual(Set(repeatNotes).count, repeatNotes.count, "each repeat within the SAME window landed on a genuinely distinct note — proving the walk chained through the local cursor, not a stale per-tail snapshot")
        assertNothingLeftSounding(e)
    }
    /// IN-KEY mode reached via registerEcho's OWN "multi" chain-composition branch — [HARMONIZE→ECHO] (echo as the
    /// chain's tail, with an upstream stage feeding it), the one realistic "chain" shape IN-KEY mode can actually
    /// reach (see the scope note above the helper — CHAIN route itself is inapplicable to registerEcho).
    func testEchoInKeyWalksTheHarmonizedUpstreamSet() {
        var h = ProcessorSlot(type: .harmonize); h.params.harmIntervals = [7, 0, 0]   // widen the dry note with a +7
        let b = echoInKeyBox(receivers: 0b0010, pitch: 1, repeats: 3, div: 4, upstream: [h])
        let pool = NotePool()
        pool.noteOn(60, velocity: 100, channel: 0)                                    // door 0: C → harmonized to {C, G}
        for n: UInt8 in [48, 52, 55] { pool.noteOn(n, velocity: 100, channel: 1) }     // reference (door 1): classes {0,4,7}
        let e = RecordingEmitter(); run(b, pool, beats: 4.5, into: e)
        XCTAssertFalse(e.ons.filter { $0.cable == 1 }.isEmpty, "[HARMONIZE→ECHO] in IN-KEY mode still produces output")
        let repeats = e.ons.filter { $0.cable == 1 && $0.note != 60 && $0.note != 67 }   // exclude the two dry (harmonized) strikes
        XCTAssertTrue(repeats.allSatisfy { [0, 4, 7].contains(Int($0.note) % 12) }, "repeats walk in-key regardless of which harmonized source note they started from")
        assertNothingLeftSounding(e)
    }

    /// A single-slot [ECHO] cell re-strikes its held note the DRY + REPEATS times, velocities DECAYING, no stuck notes.
    func testEchoRepeatsHeldNoteWithDecay() {
        let b = box(machines: echoMachines(div: 1, repeats: 4, feedDelay: 0.5, decay: 0.5)) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 1.5, into: e)                 // one column entry (S = 2 beats); TIME 1/16 = 0.25
        let strikes = e.ons.filter { $0.note == 60 && $0.cable == 1 }
        XCTAssertGreaterThanOrEqual(strikes.count, 5, "the dry + four repeats")
        XCTAssertTrue(strikes.contains { $0.vel == 100 }, "the dry inherits the source velocity 100 (was flat 96)")
        XCTAssertTrue(strikes.contains { $0.vel == 50 }, "first repeat = 100 × 0.5")
        XCTAssertTrue(strikes.contains { $0.vel == 25 }, "second repeat = 100 × 0.5²")
        assertNothingLeftSounding(e)
    }

    /// The DECAY FLOOR (drainEchoTails, Router:1184): a repeat whose `vel·decay^k` rounds below 1 is DROPPED, never
    /// emitted as a velocity-0 note-on (which a synth reads as a note-off). Harsh decay ⇒ late repeats vanish.
    func testEchoDecayFloorDropsRepeatsBelowVelocityOneNeverEmitsZero() {
        // dry vel 100 (inherited), decay 0.2, 8 repeats: k=1→20, k=2→4, k=3→1, k≥4 rounds to 0 ⇒ dropped by the floor.
        let b = box(machines: echoMachines(div: 1, repeats: 8, feedDelay: 0.2, decay: 0.2)) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 2.5, into: e)                 // long enough that all 8 repeat windows elapse
        let strikes = e.ons.filter { $0.note == 60 && $0.cable == 1 }
        XCTAssertFalse(strikes.contains { $0.vel == 0 }, "the floor never emits a velocity-0 note-on")
        XCTAssertGreaterThanOrEqual(strikes.count, 3, "the dry + the repeats that survive the floor")
        XCTAssertLessThan(strikes.count, 1 + 8, "the floor DROPS the late repeats (fewer than dry + all 8)")
        assertNothingLeftSounding(e)
    }

    /// THE TAIL: echo repeats keep sounding AFTER the source chord releases (the activation ring, not a re-derivation
    /// of the current pool) — and the transport-stop edge clears the ring so nothing leaks (quiescent).
    /// TAIL SPILL (design 2026-08-07): CUT stops an echo's repeats when the playhead leaves its column, so it emits
    /// FEWER note-ons than the same echo on RING (which spills past the bar). The sounding note finishes — no stuck notes.
    func testEchoSpillCutStopsRepeatsAtColumnExit() {
        func spillBox(_ spill: EchoSpill) -> SnapshotBox {
            box(machines: machineIDs.map { var c = Machine(machineID: $0, type: .echo)
                c.paramsA.echoDelayDiv = 2; c.paramsA.echoRepeats = 12; c.paramsA.echoFeedDelay = 0.9
                c.paramsA.echoDecay = 0.95; c.paramsA.echoSpill = spill; return c
            }) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        }
        let ring = RecordingEmitter(); run(spillBox(.ring), chord([60]), beats: 6, into: ring)
        let cut = RecordingEmitter(); run(spillBox(.cut), chord([60]), beats: 6, into: cut)
        XCTAssertLessThan(cut.ons.count, ring.ons.count, "CUT keeps echoes inside the bar; RING spills past it")
        XCTAssertGreaterThan(cut.ons.count, 0, "CUT still emits within the column")
        assertNothingLeftSounding(cut); assertNothingLeftSounding(ring)
    }
    /// ECHO via the REAL creation path: a cell whose MACHINE A-face is empty, carrying an explicit single-slot
    /// [ECHO] processor chain (what addSlotCells builds) — must still dry + repeat (guards the chain→proc resolution).
    func testEchoViaExplicitSingleSlotChainStillRepeats() {
        let b = box(machines: [Machine(machineID: "gold", type: .empty)]) {
            var c = Cell(machineID: "gold", buses: [.a])
            var s = ProcessorSlot(type: .echo); s.params.echoDelayDiv = 1; s.params.echoRepeats = 4; s.params.echoFeedDelay = 0.5; s.params.echoDecay = 0.5
            c.processors = [s]
            $0.cells[0][0] = c
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 1.5, into: e)
        let strikes = e.ons.filter { $0.note == 60 && $0.cable == 1 }
        XCTAssertGreaterThanOrEqual(strikes.count, 5, "single-slot [ECHO] via cell.processors should dry + repeat")
        assertNothingLeftSounding(e)
    }
    /// ECHO as a chain TAIL (user 2026-08-08 bug): `[bypassed-empty → ECHO]` must echo the upstream hold set, not
    /// fall through to a silent passthrough (emitEchoColumn read the HEAD, so echo-as-tail did nothing).
    func testEchoThenHarmonizeEchoesTheHarmonizedSet() {
        // [ECHO → HARMONIZE]: echo in the FIRST slot of a HOLD-tail chain. Bug (user 2026-08-10): the echo was dropped
        // (composeChainSet folded it as pass-through); it now registers tails for the fully-processed (harmonized) set.
        var s0 = ProcessorSlot(type: .echo); s0.params.echoDelayDiv = 1; s0.params.echoRepeats = 4; s0.params.echoFeedDelay = 0.6; s0.params.echoDecay = 0.5
        var s1 = ProcessorSlot(type: .harmonize); s1.params.harmIntervals = [7, 0, 0]
        let b = box(machines: [Machine(machineID: "gold", type: .empty)]) {
            var c = Cell(machineID: "gold", buses: [.a]); c.processors = [s0, s1]; $0.cells[0][0] = c
        }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 1.5, into: e)
        let root = e.ons.filter { $0.note == 60 && $0.cable == 1 }
        let harm = e.ons.filter { $0.note == 67 && $0.cable == 1 }   // the +7 harmony
        XCTAssertGreaterThanOrEqual(root.count, 3, "the echo repeats the root over time (not just the one held chord)")
        XCTAssertGreaterThanOrEqual(harm.count, 3, "…and the echoes are HARMONIZED (the +7 voice repeats too)")
        assertNothingLeftSounding(e)
    }
    func testEchoHoldTailFreeDelayRegistersTails() {
        // ECHO mid-chain limit fix (Paul 2026-08-26): FREE (ms) delay in a HOLD chain now registers tails (was synced-only → silent).
        var s0 = ProcessorSlot(type: .echo); s0.params.echoSync = false; s0.params.echoDelayMs = 120; s0.params.echoRepeats = 4; s0.params.echoFeedDelay = 0.6; s0.params.echoDecay = 0.5
        var s1 = ProcessorSlot(type: .harmonize); s1.params.harmIntervals = [7, 0, 0]
        let b = box(machines: [Machine(machineID: "gold", type: .empty)]) {
            var c = Cell(machineID: "gold", buses: [.a]); c.processors = [s0, s1]; $0.cells[0][0] = c
        }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 1.5, into: e)
        XCTAssertGreaterThanOrEqual(e.ons.filter { $0.note == 60 && $0.cable == 1 }.count, 3, "FREE (ms) echo repeats the held root over time")
        assertNothingLeftSounding(e)
    }
    func testEchoHoldTailMuteSuppressesTheDry() {
        // ECHO MUTE in a hold chain (Paul 2026-08-26): echoes-only — the dry (harmonized) hold is suppressed; the tails ring.
        func run2(thru: Bool) -> RecordingEmitter {
            var s0 = ProcessorSlot(type: .echo); s0.params.echoThru = thru; s0.params.echoDelayDiv = 1; s0.params.echoRepeats = 3; s0.params.echoFeedDelay = 0.6; s0.params.echoDecay = 0.5
            var s1 = ProcessorSlot(type: .harmonize); s1.params.harmIntervals = [7, 0, 0]
            let b = box(machines: [Machine(machineID: "gold", type: .empty)]) {
                var c = Cell(machineID: "gold", buses: [.a]); c.processors = [s0, s1]; $0.cells[0][0] = c }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 1.5, into: e); assertNothingLeftSounding(e); return e
        }
        let thru = run2(thru: true), mute = run2(thru: false)
        XCTAssertGreaterThan(mute.ons.count, 0, "MUTE still rings the echoes")
        XCTAssertLessThan(mute.ons.count, thru.ons.count, "MUTE drops the dry hold → fewer note-ons than THRU")
    }
    func testEchoAsChainTailEchoesUpstreamSet() {
        let b = box(machines: [Machine(machineID: "gold", type: .empty)]) {
            var c = Cell(machineID: "gold", buses: [.a])
            var s0 = ProcessorSlot(type: .empty); s0.bypassed = true         // passthrough upstream
            var s1 = ProcessorSlot(type: .echo); s1.params.echoDelayDiv = 1; s1.params.echoRepeats = 4; s1.params.echoFeedDelay = 0.5; s1.params.echoDecay = 0.5
            c.processors = [s0, s1]
            $0.cells[0][0] = c
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 1.5, into: e)
        let strikes = e.ons.filter { $0.note == 60 && $0.cable == 1 }
        XCTAssertGreaterThanOrEqual(strikes.count, 5, "[…→ECHO] echoes the upstream set, not a silent passthrough")
        assertNothingLeftSounding(e)
    }
    /// ECHO downstream of an ARP (user 2026-08-08): each arp TICK spawns echo repeats, so [ARP→ECHO] emits strictly
    /// more note-ons than a bare arp — and MUTE (thru off) drops the dry ticks but keeps the echoes. No stuck notes.
    /// [ARP→ECHO→LENGTH] with ROUTE=CHAIN (ratified 2026-08-22, §7②): each echo repeat is re-folded through the
    /// post-ECHO LENGTH gate at ITS OWN beat, so repeats landing in MUTE slices are dropped. DIRECT (v1) echoes the
    /// final set position-blind. Proven two ways: CHAIN with all-PASS length == DIRECT (nothing dropped, DIRECT
    /// untouched); CHAIN with half-MUTE length emits STRICTLY FEWER notes than DIRECT (the muted-slice repeats vanish).
    // §7② NON-DRIVER [ECHO→LENGTH] (Paul 2026-08-22): with no driver, LENGTH's re-articulator SWALLOWED the echo — the
    // chain produced ZERO echoes. Now the tails register at column entry (emitEchoColumn); DIRECT echoes flat, CHAIN
    // re-folds each repeat through LENGTH. Proven: (1) [ECHO→LENGTH] now adds echoes vs [LENGTH]; (2) CHAIN chokes vs DIRECT.
    func testNonDriverEchoLengthRegistersAndChainFolds() {
        func mk(route: EchoRoute, mute: Bool, echo: Bool) -> SnapshotBox {
            box(machines: arpMachines()) {
                var c = Cell(machineID: "gold", buses: [.a])
                var e = ProcessorSlot(type: .echo)
                e.params.echoSync = true; e.params.echoDelayDiv = 1; e.params.echoRepeats = 8
                e.params.echoFeedDelay = 1.0; e.params.echoDecay = 1.0; e.params.echoThru = true; e.params.echoRoute = route
                var len = ProcessorSlot(type: .length)
                len.params.lenSlices = mute ? [.pass, .mute, .pass, .mute, .pass, .mute, .pass, .mute]
                                             : [.pass, .pass, .pass, .pass, .pass, .pass, .pass, .pass]
                c.processors = echo ? [e, len] : [len]
                $0.cells[0][0] = c
            }
        }
        let bare = RecordingEmitter(); run(mk(route: .direct, mute: false, echo: false), chord([60, 64, 67]), beats: 6, into: bare)   // just [LENGTH]
        let echoed = RecordingEmitter(); run(mk(route: .direct, mute: false, echo: true), chord([60, 64, 67]), beats: 6, into: echoed)  // [ECHO→LENGTH]
        XCTAssertGreaterThan(echoed.ons.filter { $0.cable == 1 }.count, bare.ons.filter { $0.cable == 1 }.count,
                             "[ECHO→LENGTH] with no driver now adds echo repeats (was swallowed → zero)")
        let dMute = RecordingEmitter(); run(mk(route: .direct, mute: true, echo: true), chord([60, 64, 67]), beats: 6, into: dMute)
        let cMute = RecordingEmitter(); run(mk(route: .chain,  mute: true, echo: true), chord([60, 64, 67]), beats: 6, into: cMute)
        XCTAssertLessThan(cMute.ons.filter { $0.cable == 1 }.count, dMute.ons.filter { $0.cable == 1 }.count,
                          "[ECHO→LENGTH] CHAIN chokes the repeats landing in MUTE slices; DIRECT rings them all")
        assertNothingLeftSounding(bare); assertNothingLeftSounding(echoed); assertNothingLeftSounding(dMute); assertNothingLeftSounding(cMute)
    }
    // §7② NON-DRIVER hold-tail [ECHO→SPLIT] CHAIN: each repeat is re-folded through SPLIT at its OWN (decayed) velocity,
    // so a velocity-window SPLIT thins the quiet late repeats — DIRECT applies SPLIT once to the source (all repeats pass).
    func testNonDriverEchoSplitChainThinsRepeats() {
        func mk(_ route: EchoRoute) -> SnapshotBox {
            box(machines: arpMachines()) {
                var c = Cell(machineID: "gold", buses: [.a])
                var e = ProcessorSlot(type: .echo)
                e.params.echoSync = true; e.params.echoDelayDiv = 2; e.params.echoRepeats = 6
                e.params.echoFeedDelay = 1.0; e.params.echoDecay = 0.5; e.params.echoThru = true; e.params.echoRoute = route
                var sp = ProcessorSlot(type: .split); sp.params.splitVel = VelWindow(floor: 30, ceil: 127)   // drop notes quieter than 30
                c.processors = [e, sp]
                $0.cells[0][0] = c
            }
        }
        let direct = RecordingEmitter(); run(mk(.direct), chord([60, 64]), beats: 6, into: direct)
        let chain  = RecordingEmitter(); run(mk(.chain),  chord([60, 64]), beats: 6, into: chain)
        XCTAssertLessThan(chain.ons.filter { $0.cable == 1 }.count, direct.ons.filter { $0.cable == 1 }.count,
                          "CHAIN re-folds each repeat through SPLIT at its decayed velocity → quiet repeats drop; DIRECT keeps them")
        assertNothingLeftSounding(direct); assertNothingLeftSounding(chain)
    }
    // §7② regression guard (adversarial review 2026-08-23): a FREE-delay MUTE echo before LENGTH must STILL SOUND. The
    // MUTE guard suppresses the length-gated dry, so the (free-delay) echoes must register — registerLengthChainEcho now
    // computes free timeBeats like registerEcho (was synced-only via pushEchoForNote → dry-suppressed + no tails = silence).
    func testNonDriverEchoLengthFreeMuteStillSounds() {
        let b = box(machines: arpMachines()) {
            var c = Cell(machineID: "gold", buses: [.a])
            var e = ProcessorSlot(type: .echo)
            e.params.echoSync = false; e.params.echoDelayMs = 200; e.params.echoRepeats = 4    // FREE / ms delay
            e.params.echoFeedDelay = 1.0; e.params.echoDecay = 0.8; e.params.echoThru = false   // MUTE (echoes only)
            let len = ProcessorSlot(type: .length)   // all-PASS length tail
            c.processors = [e, len]
            $0.cells[0][0] = c
        }
        let e = RecordingEmitter(); run(b, chord([60, 64]), beats: 6, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0,
                             "[ECHO(MUTE,FREE)→LENGTH] still sounds via its free-delay echoes (dry suppressed, not silent)")
        assertNothingLeftSounding(e)
    }
    func testEchoChainRouteFoldsRepeatsThroughDownstreamLength() {
        func mk(_ route: EchoRoute, mute: Bool) -> SnapshotBox {
            box(machines: arpMachines()) {
                var c = Cell(machineID: "gold", buses: [.a])
                var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
                var e = ProcessorSlot(type: .echo)
                e.params.echoSync = true; e.params.echoDelayDiv = 1; e.params.echoRepeats = 8   // 1/16 spacing → repeats span all 8 slices
                e.params.echoFeedDelay = 1.0; e.params.echoDecay = 1.0; e.params.echoThru = true; e.params.echoRoute = route
                var len = ProcessorSlot(type: .length)
                len.params.lenSlices = mute ? [.pass, .mute, .pass, .mute, .pass, .mute, .pass, .mute]
                                             : [.pass, .pass, .pass, .pass, .pass, .pass, .pass, .pass]
                c.processors = [arp, e, len]
                $0.cells[0][0] = c
            }
        }
        let dPass = RecordingEmitter(); run(mk(.direct, mute: false), chord([60, 64, 67]), beats: 6, into: dPass)
        let cPass = RecordingEmitter(); run(mk(.chain,  mute: false), chord([60, 64, 67]), beats: 6, into: cPass)
        XCTAssertEqual(cPass.ons.filter { $0.cable == 1 }.count, dPass.ons.filter { $0.cable == 1 }.count,
                       "CHAIN with an all-PASS length gate keeps every repeat → identical to DIRECT (DIRECT is untouched)")
        let dMute = RecordingEmitter(); run(mk(.direct, mute: true), chord([60, 64, 67]), beats: 6, into: dMute)
        let cMute = RecordingEmitter(); run(mk(.chain,  mute: true), chord([60, 64, 67]), beats: 6, into: cMute)
        XCTAssertLessThan(cMute.ons.filter { $0.cable == 1 }.count, dMute.ons.filter { $0.cable == 1 }.count,
                          "[ARP→ECHO→LENGTH] CHAIN drops the repeats that land in MUTE slices; DIRECT rings them all")
        assertNothingLeftSounding(cMute); assertNothingLeftSounding(dMute); assertNothingLeftSounding(cPass)
    }
    func testArpThenEchoSpawnsEchoesPerTick() {
        func chainBox(echo: Bool, thru: Bool = true) -> SnapshotBox {
            box(machines: arpMachines()) {
                var c = Cell(machineID: "gold", buses: [.a])
                var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
                var e = ProcessorSlot(type: .echo)
                e.params.echoDelayDiv = 2; e.params.echoRepeats = 3; e.params.echoFeedDelay = 0.6; e.params.echoDecay = 0.5; e.params.echoThru = thru
                c.processors = echo ? [arp, e] : [arp]
                $0.cells[0][0] = c
            }
        }
        let bare = RecordingEmitter(); run(chainBox(echo: false), chord([60, 64, 67]), beats: 4, into: bare)
        let echoed = RecordingEmitter(); run(chainBox(echo: true), chord([60, 64, 67]), beats: 4, into: echoed)
        XCTAssertGreaterThan(echoed.ons.count, bare.ons.count, "[ARP→ECHO] adds echo strikes on top of the arp ticks")
        assertNothingLeftSounding(echoed)
        let muted = RecordingEmitter(); run(chainBox(echo: true, thru: false), chord([60, 64, 67]), beats: 4, into: muted)
        XCTAssertGreaterThan(muted.ons.count, 0, "MUTE still emits the echoes")
        assertNothingLeftSounding(muted)
    }
    /// [ARP → ECHO → HARMONIZE] (user 2026-08-09 bug): the stage AFTER echo must still run. THRU keeps the dry tick
    /// flowing, so harmonize adds a voice to it — the +12 harmony is heard and the chain emits more than [ARP→ECHO].
    func testArpEchoHarmonizeHarmonizesTheDryThroughNote() {
        func mk(harm: Bool) -> SnapshotBox {
            box(machines: arpMachines()) {
                var c = Cell(machineID: "gold", buses: [.a])
                var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
                var e = ProcessorSlot(type: .echo); e.params.echoDelayDiv = 2; e.params.echoRepeats = 2; e.params.echoThru = true
                var h = ProcessorSlot(type: .harmonize); h.params.harmIntervals = [12, 0, 0]
                c.processors = harm ? [arp, e, h] : [arp, e]
                $0.cells[0][0] = c
            }
        }
        let noH = RecordingEmitter(); run(mk(harm: false), chord([60]), beats: 4, into: noH)
        let withH = RecordingEmitter(); run(mk(harm: true), chord([60]), beats: 4, into: withH)
        XCTAssertGreaterThan(withH.ons.filter { $0.cable == 1 }.count, noH.ons.filter { $0.cable == 1 }.count,
                             "harmonize after echo adds voices to the dry — no longer skipped")
        XCTAssertTrue(withH.ons.contains { $0.cable == 1 && $0.note == 72 }, "the +12 harmony voice (72) is heard")
        XCTAssertFalse(noH.ons.contains { $0.cable == 1 && $0.note == 72 }, "without harmonize, no +12")
        assertNothingLeftSounding(noH); assertNothingLeftSounding(withH)
    }
    /// [ARP → ECHO → HARMONIZE] (user 2026-08-09): echo repeats the cell's FULLY-PROCESSED output, so a stage after
    /// it shapes the echoes too — the harmony is heard on the echoes, not only the dry tick. Proven two ways: adding
    /// echo raises the +12 (72) count, and every emitted root (60) is paired with its harmony (72).
    func testEchoRepeatsTheHarmonizedSetSoTheEchoesAreHarmonised() {
        func mk(echo: Bool) -> SnapshotBox {
            box(machines: arpMachines()) {
                var c = Cell(machineID: "gold", buses: [.a])
                var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
                var e = ProcessorSlot(type: .echo); e.params.echoDelayDiv = 2; e.params.echoRepeats = 2; e.params.echoThru = true
                var h = ProcessorSlot(type: .harmonize); h.params.harmIntervals = [12, 0, 0]
                c.processors = echo ? [arp, e, h] : [arp, h]
                $0.cells[0][0] = c
            }
        }
        let noEcho = RecordingEmitter(); run(mk(echo: false), chord([60]), beats: 4, into: noEcho)
        let withEcho = RecordingEmitter(); run(mk(echo: true), chord([60]), beats: 4, into: withEcho)
        func count(_ e: RecordingEmitter, _ note: UInt8) -> Int { e.ons.filter { $0.cable == 1 && $0.note == note }.count }
        XCTAssertGreaterThan(count(withEcho, 72), count(noEcho, 72), "echo repeats the harmonised set — the +12 voice echoes too")
        XCTAssertEqual(count(withEcho, 60), count(withEcho, 72), "every root (dry AND echo repeat) is paired with its harmony")
        assertNothingLeftSounding(noEcho); assertNothingLeftSounding(withEcho)
    }
    func testEchoTailRingsOutAfterSourceReleasesThenStopClearsIt() {
        let b = box(machines: echoMachines(div: 1, repeats: 6, feedDelay: 0.7, decay: 0.7)) { $0.cells[0][0] = Cell(machineID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        let router = Router(); var diag = KernelDiag()
        let pool = chord([60])
        let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func win() { router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                                    timestampSample: ts, frameCount: frames, out: e, diag: &diag); beat += wb; ts += Double(frames) }
        win()                                                     // column 0 entry: dry + register the tail
        pool.reset(); pool.rebuildSorted()                       // RELEASE the source chord
        let before = e.ons.count
        for _ in 0..<5 { win() }                                 // the repeats keep coming from the ring, pool empty
        XCTAssertGreaterThan(e.ons.count, before, "echo repeats ring out after the source releases")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)   // STOP
        XCTAssertTrue(router.quiescent, "transport stop clears the tail ring — no leaked activation")
        assertNothingLeftSounding(e)
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
    func testHocketGapsPlaysInTheWiresSilences() {
        let noWire = RecordingEmitter()
        run(hocketScene(wireOnA: false), chord([60, 64, 67]), beats: 8, into: noWire)
        let withWire = RecordingEmitter()
        run(hocketScene(wireOnA: true), chord([60, 64, 67]), beats: 8, into: withWire)
        // HOCKET emits on cable 2 (emitter B). A silent → it fills the gaps; A sounding → it's suppressed.
        XCTAssertGreaterThan(noWire.ons.filter { $0.cable == 2 }.count, 0, "A silent → HOCKET fills the silence")
        XCTAssertLessThan(withWire.ons.filter { $0.cable == 2 }.count, noWire.ons.filter { $0.cable == 2 }.count,
                          "A sounding → HOCKET GAPS is suppressed")
        assertNothingLeftSounding(noWire); assertNothingLeftSounding(withWire)
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

    /// Validation-pass finding #2 (MONO voice-steal): an EXTERNAL closer can silently steal a legato-held
    /// voice's slot. Without `forgetEuclideousLegatoSlotAt` (wired into the SAME MONO-steal loop
    /// `forgetGlideAnchorAtSlot` already uses), reconcile would wrongly keep believing the stolen pitch is
    /// still held forever, permanently dropping it. A second ARP cell shares bus A under MONO-LAST (every
    /// new note-on steals) — Euclideous's own held note on that same bus gets stolen, and must correctly
    /// re-strike on its own next hit rather than going silently, permanently dark.
    func testEuclideousLegatoRecoversFromAMonoVoiceSteal() {
        var gold = Machine(machineID: "gold", type: .euclid)
        gold.paramsA.euclideousRiff = EuclideousRiff(steps: 1, ranks: [1])
        gold.paramsA.euclidLines = [EuclidLine(pulses: 8, steps: 8, gate: 1.0, rate: .r1_8, useRiff: true, riffOn: true,
                                                mask: EuclidLineMask(), sourceMode: .midi, riffLength: 1)]
        var s = SceneState.empty()
        s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
        s.cells[0][0] = Cell(machineID: "orange", buses: [.a])   // a plain ARP on the SAME bus — steals under MONO LAST
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? gold : Machine(machineID: $0, type: .arp) }, scenes: [s])
        st.monoMask = 0b0001; st.monoPriority = [0, 0, 0, 0]   // MONO LAST on A — every new note-on steals
        st.euclideousNoteSource = .midi
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 4, into: e, forceColumn: 0)
        assertNothingLeftSounding(e)
        let euclidOns = e.ons.filter { $0.cable == 1 && $0.note == 60 }
        XCTAssertGreaterThan(euclidOns.count, 1, "after the ARP steals the held note's bus-A voice, Euclideous must re-strike on its own next hit rather than silently believing the (now-gone) voice is still held")
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

    /// Acceptance: "A C3 shifted −1 reads C2" — the same rule applies to the STRUCK PITCH, not just the
    /// displayed label. A lit note's own `noteOctShifts[rank-1]` entry shifts ONLY that rank, by a whole
    /// octave (±12 semitones), independent of the lane's shared `octave`.
    func testEuclideousPerNoteOctaveShiftSoundsAWholeOctaveHigher() {
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
        XCTAssertEqual(ons[0].note, 72, "rank 1's own +1 shift sounds a whole octave (12 semitones) above the plain pool note, independent of the lane's shared octave")
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
    private func listenRun(_ red: EuclidLine, _ blue: EuclidLine) -> [(col: Int, note: UInt8, vel: UInt8)] {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 5, 4, 3, 2, 1])
        c.paramsA.euclidLines = [red, blue, EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b]); return s }()])
        st.euclideousNoteSource = .midi
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
    func testListenT1Follow() {
        var blue = listenBlueLine(); blue.listenRhythmMode = .follow; blue.listenRhythmPartner = 0
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(listenRhythmString(hits), "x..x..x.", "T1 FOLLOW: blue inherits red's own 3-of-8 pattern exactly")
    }
    func testListenT2FollowPlusInvert() {
        var blue = listenBlueLine(); blue.listenRhythmMode = .follow; blue.listenRhythmPartner = 0; blue.patternMiss = true
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(listenRhythmString(hits), ".xx.xx.x", "T2 FOLLOW+INV: blue plays exactly red's gaps (the complement of red's pattern)")
    }
    func testListenT3With() {
        var blue = listenBlueLine(); blue.listenRhythmMode = .with; blue.listenRhythmPartner = 0
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(listenRhythmString(hits), "x.....x.", "T3 WITH: blue's own 4-of-8 hits, kept only where they coincide with red's 3-of-8")
    }
    func testListenT4Gaps() {
        var blue = listenBlueLine(); blue.listenRhythmMode = .gaps; blue.listenRhythmPartner = 0
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(listenRhythmString(hits), "..x.x...", "T4 GAPS: blue's own 4-of-8 hits, kept only where they DON'T coincide with red's 3-of-8")
    }
    func testListenT5Shadow() {
        var blue = listenBlueLine()
        blue.listenRhythmMode = .follow; blue.listenRhythmPartner = 0
        blue.listenPitchMode = .shadow; blue.listenPitchPartner = 0; blue.listenShadowInterval = 2   // 3RD
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(hits.map { $0.note }, [39, 41, 43], "T5 SHADOW+3RD: red plays C2/D2/E\u{266D}2 (36/38/39) at its 3 hits; blue, a diatonic 3rd above each, plays E\u{266D}2/F2/G2 (39/41/43)")
    }
    func testListenT6AvoidMute() {
        var blue = listenBlueLine()
        blue.pulses = 3   // "give blue exactly red's settings" — same 3-of-8 pattern, same riff/walk
        blue.listenPitchMode = .avoid; blue.listenPitchPartner = 0   // default action is MUTE
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(hits.count, 0, "T6 AVOID/MUTE: blue would play exactly what red plays at every coincident hit — all of them MUTEd")
    }
    func testListenT6AvoidMove() {
        var blue = listenBlueLine()
        blue.pulses = 3
        blue.listenPitchMode = .avoid; blue.listenPitchPartner = 0; blue.listenAvoidAction = .move
        let hits = listenRun(listenRedLine(), blue)
        XCTAssertEqual(hits.map { $0.note }, [38, 39, 41], "T6 AVOID/MOVE: red plays C2/D2/E\u{266D}2; blue MOVEs to the next free pool note up each time — D2/E\u{266D}2/F2 (38/39/41)")
    }
    func testListenT7DuckAndAccent() {
        func run_(_ mode: EuclideousLevelMode) -> [Int: UInt8] {
            var blue = listenBlueLine()   // blue's OWN 4-of-8 rhythm — no RHYTHM-row LISTEN at all
            blue.listenLevelMode = mode; blue.listenLevelPartner = 0; blue.listenLevelAmount = 0.4
            let hits = listenRun(listenRedLine(), blue)
            var byCol: [Int: UInt8] = [:]
            for h in hits { byCol[h.col] = h.vel }
            return byCol
        }
        let duck = run_(.duck)
        XCTAssertEqual(duck[0], 60, "T7 DUCK: step 1 (col 0) coincides with red — 100×(1−0.4)=60")
        XCTAssertEqual(duck[2], 100, "T7 DUCK: step 3 (col 2) does not coincide with red — stays 100")
        XCTAssertEqual(duck[4], 100, "T7 DUCK: step 5 (col 4) does not coincide with red — stays 100")
        XCTAssertEqual(duck[6], 60, "T7 DUCK: step 7 (col 6) coincides with red — 100×(1−0.4)=60")
        let accent = run_(.accent)
        XCTAssertEqual(accent[0], 127, "T7 ACCENT: step 1 coincides — 100×1.4=140, capped to 127")
        XCTAssertEqual(accent[2], 100, "T7 ACCENT: step 3 does not coincide — stays 100")
        XCTAssertEqual(accent[4], 100, "T7 ACCENT: step 5 does not coincide — stays 100")
        XCTAssertEqual(accent[6], 127, "T7 ACCENT: step 7 coincides — 100×1.4=140, capped to 127")
    }
    func testListenT8LoopsGreyOutTheWholeCycle() {
        // "with red FOLLOW blue, red is greyed out in all three of blue's partner pickers."
        var red = listenRedLine(); red.listenRhythmMode = .follow; red.listenRhythmPartner = 1   // red → blue
        let lines = [red, listenBlueLine(), EuclidLine(), EuclidLine()]
        XCTAssertTrue(euclideousListenGreyedPartners(lines, lane: 1, row: .rhythm).contains(0), "T8: red greyed in blue's own RHYTHM picker (direct loop)")
        XCTAssertTrue(euclideousListenGreyedPartners(lines, lane: 1, row: .pitch).contains(0), "T8: red greyed in blue's PITCH picker too")
        XCTAssertTrue(euclideousListenGreyedPartners(lines, lane: 1, row: .level).contains(0), "T8: red greyed in blue's LEVEL picker too")
    }
    func testListenT9TurningFollowOffRestoresTheLanesOwnSettings() {
        // "blue on its own 4 hits / 8 → FOLLOW red → turn FOLLOW off → blue is back to 4 hits / 8 with its
        // own rate and offset." Engine-level: FOLLOW never mutates blue's OWN pulses/steps/rotate/rate —
        // it only substitutes at render time while the mode is lit, so turning it off must reproduce
        // EXACTLY what a plain (never-FOLLOWed) blue would have played, byte for byte.
        let plainBlue = listenBlueLine()
        let plainHits = listenRhythmString(listenRun(listenRedLine(), plainBlue))
        var followedThenOff = listenBlueLine()
        followedThenOff.listenRhythmMode = .follow; followedThenOff.listenRhythmPartner = 0
        followedThenOff.listenRhythmMode = nil; followedThenOff.listenRhythmPartner = nil   // "turn FOLLOW off"
        let restoredHits = listenRhythmString(listenRun(listenRedLine(), followedThenOff))
        XCTAssertEqual(restoredHits, "x.x.x.x.", "T9: blue's own 4-of-8 pattern, unchanged")
        XCTAssertEqual(restoredHits, plainHits, "T9: byte-identical to a blue that was never FOLLOWing at all")
    }
    // MARK: - Adversarial-review fixes (2026-10-15): AVOID+ANY loop-detection gap
    // Lane 0 (red) has PITCH/AVOID with partner ANY — implicitly depending on every other lane. Lane 1
    // (blue) must NOT be allowed to pick lane 0 as its own RHYTHM/PITCH/LEVEL partner, since doing so
    // would close a real cycle (0 depends on 1 via ANY; 1 would now depend on 0 directly).
    func testListenAvoidAnyGreysOutInEveryOtherRowToo() {
        var red = listenRedLine(); red.listenPitchMode = .avoid; red.listenPitchPartnerAny = true
        let lines = [red, listenBlueLine(), EuclidLine(), EuclidLine()]
        XCTAssertTrue(euclideousListenGreyedPartners(lines, lane: 1, row: .rhythm).contains(0),
                      "lane 0's AVOID+ANY must grey lane 0 out of lane 1's own RHYTHM picker")
        XCTAssertTrue(euclideousListenGreyedPartners(lines, lane: 1, row: .pitch).contains(0),
                      "...and its PITCH picker")
        XCTAssertTrue(euclideousListenGreyedPartners(lines, lane: 1, row: .level).contains(0),
                      "...and its LEVEL picker")
    }
    func testListenAvoidAnyLoopIsBrokenOnPresetLoad() {
        var red = listenRedLine(); red.listenPitchMode = .avoid; red.listenPitchPartnerAny = true
        var blue = listenBlueLine(); blue.listenRhythmMode = .follow; blue.listenRhythmPartner = 0   // blue → red, closing the loop
        let fixed = euclideousListenBreakLoops([red, blue, EuclidLine(), EuclidLine()])
        // Scanned lane 0 first (nothing to break yet, its AVOID+ANY is recorded) then lane 1 — lane 1's
        // own FOLLOW is what closes the loop, so IT is the one switched off, matching this function's
        // existing "the row that closes it" convention for the non-ANY case.
        XCTAssertNotNil(fixed[0].listenPitchMode, "red's AVOID+ANY itself is untouched — it didn't close anything")
        XCTAssertNil(fixed[1].listenRhythmMode, "blue's own FOLLOW (the edge that actually closed the loop) is switched off")
    }

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
            ("LOCK", { $0.riffLock = true }),
            ("ADV STEP", { $0.riffAdvanceStep = true }),
            ("ADV STEP + LOCK + stride 2", { $0.riffAdvanceStep = true; $0.riffLock = true; $0.riffStride = 2 }),
            ("pattern BKW", { $0.direction = .bkw }),
            ("pattern PING-PONG + PEND", { $0.direction = .pingpong; $0.riffDir = .pendulum }),
            ("offset + tilt", { $0.rotate = 3; $0.tilt = 0.4 }),
            ("per-lane RESET 1 step (a bar)", { $0.resetSteps = 1 }),
            ("per-lane RESET 2 steps + LOCK off", { $0.resetSteps = 2; $0.riffStride = 2 }),
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

    // …and for a FOLLOWing lane, whose pattern, step count and rate are borrowed from its partner (× the multiplier).
    func testWalkTagMirrorMatchesAFollowingLanesBorrowedPatternAndRate() {
        let partner = EuclidLine(target: 0, pulses: 3, steps: 7, rate: .r1_8, useRiff: true, sourceMode: .midi)
        var follower = EuclidLine(target: 0, pulses: 2, steps: 8, rate: .r1_16, useRiff: true, sourceMode: .midi)
        follower.listenRhythmMode = .follow; follower.listenRhythmPartner = 0; follower.listenFollowMult = 1   // ×2: twice as fast as the partner
        follower.riffDir = .pendulum
        let lines = [partner, follower]
        var seen = Set<Int64>()
        for beats in [3.3, 7.7, 11.1] {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            c.paramsA.euclidLines = lines
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                 scenes: [{ var s = SceneState.empty()
                                     s.stepRate = .r1_8
                                     s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                     return s }()])
            st.euclideousLanesSeqRate = .oneBar
            let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60, 62, 64]), beats: beats, into: RecordingEmitter(), forceColumn: 0)
            let cfg = euclideousWalkLaneConfig(lane: 1, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
            XCTAssertEqual(cfg.n, 7, "the follower takes the partner's step count")
            XCTAssertEqual(cfg.sub, 0.25, accuracy: 1e-12, "…and its rate × 2")
            let windowBeats = 2048.0 * 120.0 / 60.0 / 48_000.0, processedEnd = (beats / windowBeats).rounded(.up) * windowBeats   // whole windows are rendered
            guard let last = euclideousWalkScanHits(cfg, beat: processedEnd - 1e-9, back: 1, ahead: 0).prev.first else { XCTFail("no hit"); continue }
            let t = euclideousWalkTick(cfg, tick: last)
            XCTAssertEqual(router.euclideousRiffPositions()[1], t.playedStep, "@\(beats): follower's played step")
            XCTAssertEqual(router.euclideousRiffWalkState()[1], t.advOrd, "@\(beats): follower's walk ordinal")
            seen.insert(t.advOrd)
        }
        XCTAssertGreaterThan(seen.count, 1)
    }

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

    // A HAND-PLACED per-step RESTART mask has no "every N" form, so the mirror must read the mask itself (the engine does).
    func testWalkTagMirrorMatchesAHandPlacedRestartMask() {
        for mask: UInt8 in [0b0010_0101, 0b1000_0001, 0b0100_0000, 0b0001_0100] {
            var diverged = false
            for beats in [5.3, 9.7, 13.1, 17.9] {
                var line = EuclidLine(target: 0, pulses: 5, steps: 8, rate: .r1_8, useRiff: true, sourceMode: .midi)
                line.riffDir = .pendulum; line.restartMask = mask
                var c = Machine(machineID: "gold", type: .euclid)
                c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
                c.paramsA.euclidLines = [line]
                var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                     scenes: [{ var s = SceneState.empty()
                                         s.stepRate = .r1_8
                                         s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                         return s }()])
                st.euclideousLanesSeqRate = .quarterBar   // a sequencer step = 1 beat, so a 8-step lap = 8 beats and the marks all get visited
                let router = runKeepingRouter(SnapshotBuilder.build(from: st), chord([60, 62, 64]), beats: beats, into: RecordingEmitter(), forceColumn: 0)
                let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .quarterBar, lanesSeqLen: 8)!
                XCTAssertTrue(cfg.grid.isActive, "the old mask migrates to an active restart grid")
                let windowBeats = 2048.0 * 120.0 / 60.0 / 48_000.0, end = (beats / windowBeats).rounded(.up) * windowBeats
                guard let last = euclideousWalkScanHits(cfg, beat: end - 1e-9, back: 1, ahead: 0).prev.first else { XCTFail("no hit"); continue }
                let t = euclideousWalkTick(cfg, tick: last)
                XCTAssertEqual(router.euclideousRiffPositions()[0], t.playedStep, "mask \(String(mask, radix: 2)) @\(beats): step")
                XCTAssertEqual(router.euclideousRiffWalkState()[0], t.advOrd, "mask \(String(mask, radix: 2)) @\(beats): ordinal")
                var noMask = cfg; noMask.grid = .off   // what the mirror did before it learned about restarts
                if let lw = euclideousWalkScanHits(noMask, beat: end - 1e-9, back: 1, ahead: 0).prev.first,
                   euclideousWalkTick(noMask, tick: lw).advOrd != t.advOrd { diverged = true }
            }
            XCTAssertTrue(diverged, "mask \(String(mask, radix: 2)): ignoring the mask WOULD have mispredicted somewhere — the test can tell the two apart")
        }
    }

    // WITH / GAPS lanes: the mirror must predict WHICH raw hits sound (the partner coincidence check), keep counting every raw
    // hit in the walk ordinal, and still put every predicted onset on the engine's own note-on sample.
    func testWalkTagMirrorMatchesWithAndGapsLanesInTheEngine() {
        for (mode, laneRate, partnerRate) in [(EuclideousRhythmMode.gaps, ArpRate.r1_8, ArpRate.r1_8), (.with, .r1_8, .r1_8),
                                              (.gaps, .r1_16, .r1_8), (.with, .r1_16, .r1_8)] {
            var partner = EuclidLine(target: 0, pulses: 3, steps: 8, rate: partnerRate, useRiff: false, sourceMode: .midi)
            partner.emitterMask = 0b0100   // the partner sounds on C so cable 1 (A) carries ONLY the listening lane
            var lane = EuclidLine(target: 0, pulses: 5, steps: 8, rate: laneRate, useRiff: true, sourceMode: .midi)
            lane.listenRhythmMode = mode; lane.listenRhythmPartner = 0; lane.riffDir = .pendulum
            lane.noteSel = .low
            let lines = [partner, lane]
            for swing in [50, 62] {
                var c = Machine(machineID: "gold", type: .euclid)
                c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
                c.paramsA.euclidLines = lines
                func box() -> SnapshotBox {
                    var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                                         scenes: [{ var s = SceneState.empty()
                                             s.stepRate = .r1_8; s.swing = swing
                                             s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                                             return s }()])
                    st.euclideousLanesSeqRate = .oneBar
                    st.euclideousNoteSource = .midi
                    return SnapshotBuilder.build(from: st)
                }
                let held = chord([48, 50, 52, 53, 55, 57, 59, 60])   // 8 notes: every riff rank resolves to a real pitch
                let cfg = euclideousWalkLaneConfig(lane: 1, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8,
                                                   swingPercent: Double(swing), stepBeats: 0.5)!
                // 1) polled step + walk ordinal of the engine's last STRIKE
                for beats in [3.3, 7.7, 11.1] {
                    let router = runKeepingRouter(box(), held, beats: beats, into: RecordingEmitter(), forceColumn: 0)
                    let windowBeats = 2048.0 * 120.0 / 60.0 / 48_000.0, end = (beats / windowBeats).rounded(.up) * windowBeats
                    guard let last = euclideousWalkScanHits(cfg, beat: end - 1e-9, back: 1, ahead: 0).prev.first else { continue }
                    let t = euclideousWalkTick(cfg, tick: last)
                    XCTAssertEqual(router.euclideousRiffPositions()[1], t.playedStep, "\(mode) \(laneRate)/\(partnerRate) sw\(swing) @\(beats): step")
                    XCTAssertEqual(router.euclideousRiffWalkState()[1], t.advOrd, "\(mode) \(laneRate)/\(partnerRate) sw\(swing) @\(beats): ordinal (raw hits still counted)")
                }
                // 2) predicted strike onsets == the engine's emitted note-on samples (one per strike)
                let e = RecordingEmitter()
                run(box(), held, beats: 15.9, into: e, forceColumn: 0)
                var engineBeats: [Double] = []
                for b in e.ons.filter({ $0.cable == 1 }).map({ Double($0.sample) / 48_000 * 120 / 60 }).sorted() where engineBeats.last.map({ b - $0 > 0.01 }) ?? true { engineBeats.append(b) }
                let ticks = (0..<160).map { Int64($0) }
                let predicted = ticks.filter { euclideousWalkTick(cfg, tick: $0).strikes }.map { euclideousWalkRealBeat(cfg, tick: $0) }.filter { $0 < 15.5 }
                let silenced = ticks.filter { let t = euclideousWalkTick(cfg, tick: $0); return t.isHit && !t.strikes && euclideousWalkRealBeat(cfg, tick: $0) < 15.5 }
                XCTAssertGreaterThan(silenced.count, 0, "\(mode): the filter genuinely silences some raw hits here (not vacuous)")
                XCTAssertGreaterThan(engineBeats.count, 2, "\(mode): the engine played notes")
                XCTAssertGreaterThanOrEqual(engineBeats.count, predicted.count, "\(mode) \(laneRate)/\(partnerRate) sw\(swing): engine plays at least every predicted strike")
                for (i, b) in engineBeats.prefix(predicted.count).enumerated() {
                    XCTAssertEqual(b, predicted[i], accuracy: 0.002, "\(mode) \(laneRate)/\(partnerRate) sw\(swing): strike \(i) — engine note-on vs predicted arrival (beats)")
                }
            }
        }
    }

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
        line.riffLock = true
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
    private func mixRun(_ box: SnapshotBox, beats: Double, into e: RecordingEmitter, maskOn: Bool = false) {
        let pool = chord([48, 50, 52, 53, 55, 57, 59, 60])   // rank 1 = 48 … rank 5 = 55 … rank 8 = 60
        let router = Router(); router.euclideousMaskEnabledForTests = maskOn
        var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < beats {
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

    /// One lane (geometry A = 3-of-8 @ 1/8, lap 4 beats; B = 5-of-16 @ 1/16, lap 4 beats), the old LANES sequencer at `rate`/`len` with
    /// the per-lane reset `resetSteps`, a riff 1…8 walked in `dir` / `lock` / `adv`. Hashes the whole note wire stream (FNV-1a).
    private func lanesOldStreamHash(geo: Int, rate: EuclideousSeqRate, resetSteps: Int, len: Int,
                                    dir: RiffDir, lock: Bool, adv: Bool, beats: Double) -> UInt64 {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        var l = geo == 0
            ? EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8, useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8, resetSteps: resetSteps)
            : EuclidLine(target: 0, pulses: 5, steps: 16, rate: .r1_16, useRiff: false, riffOn: true, sourceMode: .midi, riffLength: 8, resetSteps: resetSteps)
        l.riffDir = dir; l.riffLock = lock; l.riffAdvanceStep = adv
        c.paramsA.euclidLines = [l]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty(); s.stepRate = .r1_8
                                  s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        st.euclideousLanesSeqOn = true; st.euclideousLanesSeqRate = rate; st.euclideousLanesSeqLen = len
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60, 62, 64, 65, 67, 69, 71, 72]), beats: beats, into: e, forceColumn: 0, frames: 8192)
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            mix(UInt64(bitPattern: ev.sample)); mix(UInt64(ev.cable)); mix(UInt64(ev.status)); mix(UInt64(ev.chan)); mix(UInt64(ev.note)); mix(UInt64(ev.vel))
        }
        return h
    }
    /// (profile, riff direction) → (hash over the LENs that divide 16, hash over the LENs that do not — their first 16-cell window only).
    /// Profiles: 0 = 5-of-16 @ 1/16 with the old sequencer at ¼ BAR · 1 = 3-of-8 @ 1/8 at ½ BAR · 2 = 3-of-8 @ 1/8 at 1 BAR — each picked
    /// so the lane has a restart unit EXACTLY as long as the old step (4STP, 4STP, PASS), which is what makes the grid reproduce the old
    /// reset bit-for-bit. Each hash folds N ∈ {1,2,4,8} × LEN ∈ {1,3,4,8} × LOCK/FREE × HIT/STEP. CAPTURED ON THE ENGINE BEFORE THE
    /// LANES GRID (origin/main 11fde27, old per-lane reset, per-window mute).
    private let lanesOldGolden: [String: (UInt64, UInt64)] = [
        "0/FWD": (11521033976096653421, 12856291899802091333),
        "0/PING-PONG": (4357418606541251253, 17647227502269334373),
        "0/PONG": (13332039570205451725, 13491859450970235765),
        "0/REV": (8634120185433063693, 5758843939915682997),
        "1/FWD": (2049334351417553541, 14188276989886311237),
        "1/PING-PONG": (14571060432471505949, 7623108916407658821),
        "1/PONG": (16629896193030693045, 5379060580400571477),
        "1/REV": (13021396075092701517, 18179746394115966453),
        "2/FWD": (3082567594428127925, 17375436917988455789),
        "2/PING-PONG": (17123664477517444149, 14762837615774768837),
        "2/PONG": (12638519335341283541, 14779867729352630517),
        "2/REV": (14981592664394735029, 9690269835975383749),
    ]
    private let lanesGoldenProfiles: [(geo: Int, rate: EuclideousSeqRate)] = [(1, .quarterBar), (0, .halfBar), (0, .oneBar)]
    /// Runs the whole matrix through `stream` (old fields or explicit grid fields) and returns the folded hashes.
    private func lanesGoldenMatrix(_ stream: (_ geo: Int, _ rate: EuclideousSeqRate, _ n: Int, _ len: Int, _ dir: RiffDir, _ lock: Bool, _ adv: Bool, _ beats: Double) -> UInt64)
        -> [String: (UInt64, UInt64)] {
        var out: [String: (UInt64, UInt64)] = [:]
        for (pi, prof) in lanesGoldenProfiles.enumerated() { for dir in [RiffDir.forward, .reverse, .pendulum, .pingpong] {
            let S = prof.rate.barsFraction * 4
            var hDiv: UInt64 = 0xcbf29ce484222325, hPre: UInt64 = 0xcbf29ce484222325
            for n in [1, 2, 4, 8] { for len in [1, 3, 4, 8] { for lock in [false, true] { for adv in [false, true] {
                let divides = 16 % len == 0
                let beats = divides ? 40.0 : min(40.0, 16 * S - 2.0)   // the run's closing release window must stay inside the first 16-cell window too
                let h = stream(prof.geo, prof.rate, n, len, dir, lock, adv, beats)
                if divides { hDiv = (hDiv ^ h) &* 0x100000001b3 } else { hPre = (hPre ^ h) &* 0x100000001b3 }
            } } } }
            out["\(pi)/\(dir.rawValue)"] = (hDiv, hPre)
        } }
        return out
    }
    /// MIGRATION EQUIVALENCE (§6.5 / §8): a pre-feature document — old sequencer ON / RATE / LEN and the old per-lane reset — must
    /// sound bit-for-bit as the old engine did, now that the engine reads the lane grid (the old fields migrate at use).
    func testLanesGridOldSequencerResetDocumentsRenderTheSameStreamAsBeforeTheGrid() {
        let got = lanesGoldenMatrix { geo, rate, n, len, dir, lock, adv, beats in
            self.lanesOldStreamHash(geo: geo, rate: rate, resetSteps: n, len: len, dir: dir, lock: lock, adv: adv, beats: beats)
        }
        XCTAssertEqual(got.count, lanesOldGolden.count)
        for (k, want) in lanesOldGolden {
            XCTAssertEqual(got[k]?.0, want.0, "\(k): LENs 1/4/8 (divide 16) — the full run")
            XCTAssertEqual(got[k]?.1, want.1, "\(k): LEN 3 (does not divide 16) — the first 16-cell window")
        }
    }

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
    /// Every cable-1 note-on, as (beat, pool index), in sounding order.
    private func gridHits(_ line: EuclidLine, beats: Double) -> [(beat: Double, idx: Int)] {
        let e = RecordingEmitter()
        mixRun(mixBox(line, ranks: [1, 2, 3, 4, 5, 6, 7, 8]), beats: beats, into: e)
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

    func testGridRhythmOnlyMarkRephasesTheHitsAndThePitchesKeepCountingStraightThrough() {
        // RHYTHM marks on 4-tick cells 0 and 3 (ticks 0, 12 = beats 0, 6); no melody mark → the riff counts hits straight through the re-phase.
        let got = gridHits(gridLine(rhythm: 0b1001), beats: 19.9)
        let ticks = gridExpectedHitTicks(restarts: [0, 12], last: 39)
        XCTAssertEqual(got.map { $0.beat }, ticks.map { Double($0) * 0.5 }, "hits re-phase at the rhythm mark (tick 12 restarts the pass: a hit at beat 6, then 7.5, 9, …)")
        XCTAssertEqual(got.map { $0.idx }, (0..<ticks.count).map { $0 % 8 }, "the riff ordinal is NOT reset by a rhythm-only mark: pitches 1, 2, 3, … uninterrupted")
    }
    func testGridMelodyOnlyMarkLeavesEveryHitInPlaceAndTheRiffReturnsToItsStart() {
        let base = gridHits(gridLine(), beats: 19.9)
        for (locked, step) in [(false, false), (true, false), (false, true), (true, true)] {
            let marked = gridHits(gridLine(melody: 1 << 3, locked: locked, stepAdvance: step), beats: 19.9)   // melody mark at tick 12 = beat 6
            let free = gridHits(gridLine(locked: locked, stepAdvance: step), beats: 19.9)
            XCTAssertEqual(marked.map { $0.beat }, base.map { $0.beat }, "hit positions unchanged (locked \(locked), step-advance \(step))")
            // the first hit at/after beat 6 reads riff position 0 → pool index 0 in HIT mode; STEP counts ticks since the mark (hit at tick 14 → 2)
            let first = marked.first { $0.beat >= 6 }!
            XCTAssertEqual(first.idx, step ? (2 % 8) : 0, "locked \(locked) step \(step): the riff restarted at the mark")
            // …and without the mark the same hit read something else (FREE-HIT continues; a LOCK lap restarts at beat 4, so that case differs only after)
            if !locked && !step { XCTAssertNotEqual(free.first { $0.beat >= 6 }!.idx, 0) }
            // (Before the mark the riff counts from the PREVIOUS window's mark — a negative origin, §2.3 — so the early pitches differ from the unmarked run's; that is the spec'd behaviour, covered by testGridFirstWindowRunsFromANegativeOriginDeterministically.)
        }
        // PENDULUM: the walk position at the first hit after the mark is the pendulum's own start (position 0)
        let pend = gridHits(gridLine(melody: 1 << 3, dir: .pendulum), beats: 19.9)
        XCTAssertEqual(pend.first { $0.beat >= 6 }!.idx, 0)
    }
    func testGridBothMarksOnTheSameCellBehaveExactlyLikeASingleRestart() {
        // The old engine's single restart re-phased the pattern AND restarted the riff; both masks on one cell must do the same.
        let both = gridHits(gridLine(rhythm: 0b1001, melody: 0b1001), beats: 19.9)
        let ticks = gridExpectedHitTicks(restarts: [0, 12], last: 39)
        XCTAssertEqual(both.map { $0.beat }, ticks.map { Double($0) * 0.5 })
        var ord = 0
        let expected: [Int] = ticks.map { t in if t == 12 { ord = 0 }; defer { ord += 1 }; return ord % 8 }
        XCTAssertEqual(both.map { $0.idx }, expected, "the riff restarts at the shared mark (tick 12) and counts on from there")
    }
    func testGridAMarkOnAMutedCellStillRestartsAndTheNextAudibleHitIsAFreshRestart() {
        // PASS-sized mute cells (4 beats); cell 1 (beats 4–8) is muted, and a rhythm+melody mark sits INSIDE it at tick 12 (beat 6).
        let muted = gridHits(gridLine(rhythm: 0b1001, melody: 0b1001, mute: 0xFFFF & ~(1 << 1)), beats: 19.9)
        let unmuted = gridHits(gridLine(rhythm: 0b1001, melody: 0b1001), beats: 19.9)
        XCTAssertTrue(muted.allSatisfy { $0.beat < 3.99 || $0.beat >= 7.99 }, "nothing sounds in the muted cell")
        XCTAssertEqual(muted.filter { $0.beat >= 7.99 }.map { $0.beat }, unmuted.filter { $0.beat >= 7.99 }.map { $0.beat }, "the restart inside the muted cell took effect: later hits are where a restart put them")
        XCTAssertEqual(muted.filter { $0.beat >= 7.99 }.map { $0.idx }, unmuted.filter { $0.beat >= 7.99 }.map { $0.idx }, "…and the muted hits still advanced the walk, so the pitches match too")
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
        // The same mute cells, with and without a restart mark: the SAME beats are silent.
        let a = gridHits(gridLine(mute: 0b1111_1111_1111_1101), beats: 19.9)
        let b = gridHits(gridLine(rhythm: 0b1001, melody: 0b1001, mute: 0b1111_1111_1111_1101), beats: 19.9)
        XCTAssertTrue(a.allSatisfy { $0.beat < 3.99 || $0.beat >= 7.99 }); XCTAssertTrue(b.allSatisfy { $0.beat < 3.99 || $0.beat >= 7.99 })
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
    func testGridTieLookaheadFollowsARhythmRestartThatMovesTheNextRealNote() {
        // Riff ranks [1,0,0,0,0,0,0,2], ON REST = TIE: the first note (pitch 48) is held over the rests until the hit that reads rank 2 (pitch 50).
        // A rhythm mark at tick 12 pulls that hit earlier (tick 18 instead of 19); the held note must end earlier too — the lookahead has to see the restart.
        func firstNoteLength(rhythm: UInt16) -> Double {
            var l = gridLine(rhythm: rhythm); l.riffOnRest = .tie
            let e = RecordingEmitter(); mixRun(mixBox(l, ranks: [1, 0, 0, 0, 0, 0, 0, 2]), beats: 12.9, into: e)
            let on = e.ons.first { $0.cable == 1 && $0.note == 48 }!
            let off = e.offs.first { $0.cable == 1 && $0.note == 48 }!
            return Double(off.sample - on.sample) / 24_000
        }
        let plain = firstNoteLength(rhythm: 0)
        let marked = firstNoteLength(rhythm: 0b1001)
        XCTAssertGreaterThan(plain - marked, 0.3, "the real note arrives about half a beat earlier after the restart, and the tie ends with it")
        XCTAssertLessThan(plain - marked, 0.7)
    }
    func testGridFirstWindowRunsFromANegativeOriginDeterministically() {
        // A rhythm mark on cell 5 only: no mark in cells 0–4, so window 0 runs from the previous window's mark (a negative origin).
        let a = gridHits(gridLine(rhythm: 1 << 5, melody: 1 << 2), beats: 15.9)
        let b = gridHits(gridLine(rhythm: 1 << 5, melody: 1 << 2), beats: 15.9)
        XCTAssertEqual(a.map { $0.beat }, b.map { $0.beat }); XCTAssertEqual(a.map { $0.idx }, b.map { $0.idx })
        XCTAssertFalse(a.isEmpty)
        // carried origin: (5 − 16) cells × 4 ticks = −44 ticks ⇒ hits where (tick + 44) mod 8 ∈ {0,3,6} before the mark at tick 20
        let expected = (0...31).filter { t in
            let origin = t >= 20 ? 20 : -44
            return [0, 3, 6].contains(((t - origin) % 8 + 8) % 8)
        }
        XCTAssertEqual(a.map { $0.beat }, expected.map { Double($0) * 0.5 })
    }

    // §3 / §8 ROLL FEED vs the Router: for a lane with a known pattern and riff, the roll's hits equal the beats, ranks and lengths the Router
    // really produces over the same window, with and without marks, muted and audible flagged correctly, and a TIE extension included.
    func testGridRollFeedEqualsWhatTheRouterActuallyPlays() {
        struct Case { var name: String; var line: EuclidLine; var ranks: [Int] }
        var tie = gridLine(rhythm: 0b1001); tie.riffOnRest = .tie; tie.gate = 0.5
        var plain = gridLine(); plain.gate = 0.5
        var marked = gridLine(rhythm: 0b1001, melody: 1 << 5); marked.gate = 0.5
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

    // §2.8 — the page's FOOTER baseline comes from the core: the ordinal the current lap's first hit reads, across a melody restart too.
    func testGridLapStartOrdinalIsWhatTheEngineReadsAtTheLapsFirstHit() {
        for (rhythm, melody) in [(UInt16(0), UInt16(0)), (0b1001, 0), (0, 1 << 3), (0b1001, 0b1001), (1 << 5, 1 << 2)] {
            for locked in [false, true] {
                let line = gridLine(rhythm: rhythm, melody: melody, locked: locked)
                guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { XCTFail(); continue }
                for beat in stride(from: 0.2, through: 40.0, by: 1.7) {
                    let tick = Int64((beat / cfg.sub).rounded(.down))
                    let cycleLen = euclidCycleLen(cfg.dir, n: cfg.n)
                    let now = euclideousLaneTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: tick, grid: cfg.grid,
                                                 legacySpanBeats: cfg.spanBeats, locked: cfg.locked, advanceStep: cfg.advanceStep)
                    let lapStart = tick - Int64(now.raw)
                    let firstHit = (0..<cycleLen).first { cfg.buf[euclidReadIndex($0, n: cfg.n, dir: cfg.dir)] }!
                    let want = euclideousLaneTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: lapStart + Int64(firstHit), grid: cfg.grid,
                                                  legacySpanBeats: cfg.spanBeats, locked: cfg.locked, advanceStep: cfg.advanceStep).advOrd
                    XCTAssertEqual(euclideousLapStartOrdinal(cfg: cfg, beat: beat), want, "rhythm \(rhythm) melody \(melody) locked \(locked) beat \(beat)")
                }
            }
        }
    }
}

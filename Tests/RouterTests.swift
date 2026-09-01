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

    /// A one-scene document with the given colours + cell layout, then its resolved SnapshotBox.
    private func box(colours cs: [Colour], busChannels: [Int] = [1, 2, 3, 4], masterMute: Bool = false,
                     _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(colours: cs, scenes: [s]); st.busChannels = busChannels; st.masterMute = masterMute
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
                     laneMask: UInt8 = 0, soloCellMask: UInt64 = 0, releaseAtEnd: Bool = true,
                     tempo: Double = 120, sr: Double = 48_000, frames: UInt32 = 2048) {
        let router = Router()
        var diag = KernelDiag()
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: laneMask,
                           soloCellMask: soloCellMask, out: emitter, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        if releaseAtEnd {   // release the lap (laneMask 0) then stop — must return to the true timeline, no stuck notes
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0,
                           soloCellMask: soloCellMask, out: emitter, diag: &diag)
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

    private func arpColours() -> [Colour] { colourIDs.map { Colour(colourID: $0, type: .arp) } }

    // MARK: tests

    func testArpSoundsAndLeavesNothingStuck() {
        // One ARP cell (col 0, bus A) over a 3-note chord, run a full 8-column cycle then stop.
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold") }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)          // S=2 → one full cycle
        XCTAssertGreaterThan(e.ons.count, 0, "the arp should have sounded during column 0's window")
        assertNothingLeftSounding(e)
    }

    func testPlayCellOnlySilencesEveryOtherCell() {
        // EDIT "play this cell only" (user 2026-08-08): two ARP cells in the SAME column, rows 0 (bus A/cable 1)
        // and 1 (bus B/cable 2). Solo the (col0,row1) cell → only cable 2 lights; the other falls silent.
        let b = box(colours: arpColours()) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])
            $0.cells[0][1] = Cell(colourID: "orange", buses: [.b])
        }
        let soloed = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: soloed, soloCellMask: UInt64(1) << UInt64(0 * 8 + 1))
        XCTAssertGreaterThan(soloed.ons.filter { $0.cable == 2 }.count, 0, "the solo'd cell sounds")
        XCTAssertEqual(soloed.ons.filter { $0.cable == 1 }.count, 0, "the non-solo'd cell is silenced")
        assertNothingLeftSounding(soloed)
        // sanity: with NO solo, both buses light — so the silence above is the solo, not the fixture
        let both = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: both)
        XCTAssertGreaterThan(both.ons.filter { $0.cable == 1 }.count, 0, "no solo → the other cell sounds")
        XCTAssertGreaterThan(both.ons.filter { $0.cable == 2 }.count, 0)
    }

    // GENERATORS (user 2026-08-08) — EUCLID · BURST · CASCADE render integration.
    func testEuclidStrikesChordOnEuclideanPulses() {
        // 4-of-8 euclid over a 3-note chord in one column (S = 2 beats): 4 pulses × 3 notes = 12 note-ons, no stuck.
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; return c }) { $0.cells[1][0] = Cell(colourID: "gold", buses: [.a]) }
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
            let b = box(colours: colourIDs.map { id -> Colour in
                guard id == "gold" else { return Colour(colourID: id, type: .arp) }
                var c = Colour(colourID: "gold", type: .euclid)
                c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; c.paramsA.euclidRate = .r1_8; c.paramsA.euclidSpanN = spanN
                return c
            }) { s in
                s.stepRate = .r1_8                                       // 0.5-beat columns == the euclid rate → one step per column
                for col in 0..<8 { s.cells[col][0] = Cell(colourID: "gold", buses: [.a]) }   // the whole row → the pattern plays continuously
            }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 3.9, into: e)   // exactly 8 columns (no pass-2 edge)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertEqual(ons(spanN: nil), 12, "FREE: the 4-of-8 pattern walks the row — hits at steps 0·2·4·6 = 4 columns × 3 notes")
        XCTAssertEqual(ons(spanN: 1), 24, "SPAN=1: re-anchored EVERY column to step 0 (always a hit) → all 8 columns fire × 3 notes")
        XCTAssertGreaterThan(ons(spanN: 1), ons(spanN: nil), "the re-anchor changes the sequenced pattern")
    }
    // DEST MATRIX (Paul 2026-08-22 §5): [ARP→DEST] hockets the walk across emitters — each onset-slice routes to its
    // chosen emitter (the routing override wins over the cell's fan-out).
    func testDestMatrixHocketsTheArpAcrossEmitters() {
        func run2(_ withDest: Bool) -> [RecordingEmitter.Ev] {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var dest = ProcessorSlot(type: .dest); dest.params.destSlices = [0, 1, 2, 3, 0, 1, 2, 3]
            let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) {
                $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a, .b, .c, .d]); c.processors = withDest ? [arp, dest] : [arp]; return c }()
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
            let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) {
                $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a, .b, .c, .d]); c.processors = withMute ? [arp, mute] : [arp]; return c }()
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
    // MUTE composes ON TOP of DEST (Paul 2026-08-25 §5): DEST routes each slice to one emitter, MUTE then removes muted
    // emitters. [ARP→DEST(alt A/B)→MUTE(A)] → the A-routed slices go silent, the B-routed ones still play; none stuck.
    func testMuteMatrixComposesOverDest() {
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        var dest = ProcessorSlot(type: .dest); dest.params.destSlices = [0, 1, 0, 1, 0, 1, 0, 1]      // alternate A, B
        var mute = ProcessorSlot(type: .muteMatrix); mute.params.muteSlices = Array(repeating: 0b0001, count: 8)  // A muted every step
        let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        let b = box(colours: cs) {
            $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a, .b, .c, .d]); c.processors = [arp, dest, mute]; return c }()
        }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        assertNothingLeftSounding(e)
        XCTAssertFalse(e.ons.contains { $0.cable == 1 }, "the A-routed slices are muted → nothing on emitter A")
        XCTAssertTrue(e.ons.contains { $0.cable == 2 }, "the B-routed slices still play on emitter B")
    }
    // MUTE MATRIX indexes by the GRID COLUMN (Paul 2026-08-25 — the "does nothing" fix): a MUTE colour across a ROW mutes
    // the drawn columns. Muting emitter A on columns 0–3 only → A still plays (from columns 4–7); muting it everywhere → none.
    func testMuteMatrixMutesByColumnAcrossARow() {
        func aCount(_ mask: [Int]) -> Int {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
            var mute = ProcessorSlot(type: .muteMatrix); mute.params.muteSlices = mask
            let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) {
                for col in 0..<8 { $0.cells[col][0] = { var c = Cell(colourID: "gold", buses: [.a, .b]); c.processors = [arp, mute]; return c }() }
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
            var c = Colour(colourID: "gold", type: .nudge)
            if let l = lane { c.paramsA.utilNudgeMode = .lane; c.paramsA.utilNudgeLane = l }
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // a NUDGE cell in column 0
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
            var c = Colour(colourID: "gold", type: .chance)
            c.paramsA.chanceMode = .pattern; c.paramsA.chanceSlices = slices
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) } }
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
            var c = Colour(colourID: "gold", type: .tutti)
            c.paramsA.tuttiMode = .pattern
            c.paramsA.tuttiSlices = [.all, .rest, .low, .rest, .high, .rest, .bot2, .rest]
            c.paramsA.tuttiSpanN = spanN
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) } }
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
            var c = Colour(colourID: "gold", type: .tutti)
            c.paramsA.tuttiMode = .pattern
            c.paramsA.tuttiRate = .r1_8                // 0.5 beat → 4 slices per 2-beat column
            c.paramsA.tuttiSlices = [.low, .low, .low, .low, .high, .high, .high, .high]
            c.paramsA.tuttiSpanN = spanN
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) } }
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
            var c = Colour(colourID: "gold", type: .drone)
            c.paramsA.strikePerSpan = sps
            c.paramsA.strikeSpanN = spanN
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 15.9, into: e)   // columns 0…7 of one bar (S=2), no col-8 wrap
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 && $0.note == 60 }.count
        }
        XCTAssertEqual(onCount(sps: false, spanN: 8), 1, "a plain drone strikes once and holds the whole run (today's pad)")
        XCTAssertEqual(onCount(sps: true, spanN: 1), 8, "PER SPAN=1 re-articulates every column")
        XCTAssertEqual(onCount(sps: true, spanN: 4), 2, "PER SPAN=4 re-articulates at the span origins (cols 0, 4)")
        XCTAssertEqual(onCount(sps: true, spanN: 4), 2, "replay-safe (deterministic)")
    }
    // §1 STANDARD PANEL ANATOMY (Paul 2026-08-27) — the per-STAGE OCT header standard: a slot's stageOct shifts its OWN
    // output ±3 octaves. Single-slot cells shift via the transpose sum (hold + tick paths); 0 = byte-identical.
    func testStageOctShiftsSingleSlotStageOutput() {
        func droneNotes(_ oct: Int) -> Set<Int> {                                     // hold path (emitColumnHolds transpose)
            var c = Colour(colourID: "gold", type: .drone); c.paramsA.stageOct = oct
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e)
            return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        }
        XCTAssertEqual(droneNotes(0), [60, 64, 67], "stageOct 0 = the raw held chord")
        XCTAssertEqual(droneNotes(1), [72, 76, 79], "stageOct +1 = up an octave (hold path)")
        XCTAssertEqual(droneNotes(-1), [48, 52, 55], "stageOct -1 = down an octave (hold path)")
        func arpNotes(_ oct: Int) -> Set<Int> {                                       // tick/driver path (emitTickRow transpose)
            var c = Colour(colourID: "gold", type: .arp); c.paramsA.rate = .r1_16; c.paramsA.octaves = 1; c.paramsA.stageOct = oct
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        }
        let a0 = arpNotes(0), a1 = arpNotes(1)
        XCTAssertFalse(a0.isEmpty, "the arp sounds")
        XCTAssertEqual(Set(a1.map { $0 - 12 }), a0, "arp stageOct +1 shifts every arp note up an octave (tick path)")
    }
    func testStageOctShiftsAFoldedChainStage() {
        // [ARP → HARMONIZE]: HARMONIZE folds downstream (emitDriverNote → applyStage). Its stageOct shifts the whole
        // folded output ±12 — the folded-slot path, distinct from the driver's own transpose.
        func notes(_ oct: Int) -> Set<Int> {
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16; arp.params.octaves = 1
            var harm = ProcessorSlot(type: .harmonize); harm.params.stageOct = oct
            let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp, harm]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        }
        let n0 = notes(0), n1 = notes(1)
        XCTAssertFalse(n0.isEmpty, "the [ARP→HARMONIZE] chain sounds")
        XCTAssertEqual(Set(n1.map { $0 - 12 }), n0, "the folded HARMONIZE stage's stageOct +1 shifts its whole output up an octave")
    }
    // §1 ANATOMY SOURCE (Paul 2026-08-27): a stage's SOURCE — CHAIN reads the upstream output · MIDI IN reads the row's raw
    // DOOR · BOTH merges. v1 acts in composeChainSet (folded/upstream stages). [OCTAVE(+1) → TRANSPOSE(0, SOURCE) → ARP]:
    // CHAIN sees the octave-shifted set (+12), MIDI IN sees the raw door (+0), BOTH sees both — distinguishable by pitch.
    func testStageSourceReadsTheDoorInChainCompose() {
        func notes(_ src: StageSource) -> Set<Int> {
            var oct = ProcessorSlot(type: .octave); oct.params.utilOctave = 1
            var mid = ProcessorSlot(type: .transpose); mid.params.utilTranspose = 0; mid.params.stageSource = src
            var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16; arp.params.octaves = 1
            let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [oct, mid, arp]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        }
        XCTAssertEqual(notes(.chain), [72, 76, 79], "CHAIN reads the OCTAVE-shifted upstream set")
        XCTAssertEqual(notes(.midiIn), [60, 64, 67], "MIDI IN reads the raw door chord (ignores the upstream octave)")
        XCTAssertEqual(notes(.both), [60, 64, 67, 72, 76, 79], "BOTH merges the door with the upstream set")
    }
    // SPAN LADDER stage 2b — RATCHET PATTERN (RATE×ladder): RATE = slice width, SPAN N = the loop period in columns.
    func testRatchetSpanLadderReAnchorsThePatternByPeriod() {
        func onCount(spanN: Int?) -> Int {
            var c = Colour(colourID: "gold", type: .ratchet)
            c.paramsA.rtcMode = .pattern
            c.paramsA.rtcSlices = [3, 0, 2, 0, 4, 0, 2, 0]
            c.paramsA.rtcSpanN = spanN
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) } }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        let c3 = onCount(spanN: 3), c8 = onCount(spanN: 8)
        XCTAssertGreaterThan(c3, 0, "the RATE×ladder ratchet sounds")
        XCTAssertNotEqual(c3, c8, "period 3 (polymeter) differs from period 8")
        XCTAssertEqual(c3, onCount(spanN: 3), "replay-safe")
    }
    // SPAN LADDER stage 2b — CASCADE (RATE×ladder): RATE = reveal spacing, SPAN N = the reveal window in columns.
    func testCascadeSpanLadderChangesTheRevealWindow() {
        func seq(spanN: Int?) -> [Int] {
            var c = Colour(colourID: "gold", type: .cascade)
            c.paramsA.cascadeSpanN = spanN
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) } }
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
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; c.paramsA.euclidPick = .low; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 2, into: e)
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(ons.count, 4, "4 pulses × 1 picked note")
        XCTAssertTrue(ons.allSatisfy { $0.note == 60 }, "PICK LOW strikes only the lowest pool note")
        assertNothingLeftSounding(e)
    }
    // EUCLID INVERT (Paul 2026-08-22): strike the N−K rests. 3-of-8 = 3 hits (9 ons) vs INVERT = 5 rests (15 ons).
    func testEuclidInvertPlaysTheRests() {
        func count(_ inv: Bool) -> Int {
            let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
                c.paramsA.euclidPulses = 3; c.paramsA.euclidSteps = 8; c.paramsA.euclidInvert = inv; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
            assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertEqual(count(false), 9, "3 hits × 3 notes")
        XCTAssertEqual(count(true), 15, "INVERT plays the 5 rests × 3 notes")
    }
    // EUCLID PICK CYCLE (Paul 2026-08-22): the euclid-arp — one note per pulse, walking the chord.
    func testEuclidPickCycleWalksTheChordOneNotePerPulse() {
        func mk(_ pick: EuclidPick) -> (Int, Set<UInt8>) {
            let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
                c.paramsA.euclidPulses = 5; c.paramsA.euclidSteps = 8; c.paramsA.euclidPick = pick; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; c.paramsA.euclidPick = .high; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(ons.count, 4, "4 pulses × 1 picked note")
        XCTAssertTrue(ons.allSatisfy { $0.note == 67 }, "PICK HIGH strikes only the highest pool note")
        assertNothingLeftSounding(e)
    }
    // EUCLID PICK RANDOM (Paul 2026-08-22): a seeded scatter — replay-EXACT (same stream twice) and always in the held pool.
    func testEuclidPickRandomIsReplayExactAndInPool() {
        func notes() -> [UInt8] {
            let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
                c.paramsA.euclidPulses = 5; c.paramsA.euclidSteps = 8; c.paramsA.euclidPick = .random; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let cs = colourIDs.map { var c = Colour(colourID: $0, type: .chance)
            c.paramsA.probability = 1; return c }
        let b = box(colours: cs) { s in
            for col in 0..<8 {                                    // fully populate both rows so a column is always sounding
                s.cells[col][0] = Cell(colourID: "gold", buses: [.a])
                s.cells[col][1] = Cell(colourID: "orange", buses: [.b])
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
    // PER-ROW LAP (Paul 2026-08-19): each grid ROW loops its OWN columns (the BUILD staging + perform grids loop
    // independently). Row 0's only cell lives in column 0 and laps column 0; row 1's only cell lives in column 4 and
    // laps column 4. With ONE global lap only a single column could loop, silencing one cell — the per-row lap lets
    // BOTH play continuously on their own column. Proves looping one grid doesn't loop the other.
    func testPerRowLapLoopsEachRowsOwnColumns() {
        // NB (Paul 2026-09-01): SnapshotBuilder forwards `rowLane` ONLY when its count == Snap.rows (16). The old version of
        // this test passed an 8-entry array → the builder DISCARDED it → perRowLap was FALSE → the whole thing ran on the
        // UNIFORM fast path and never actually lapped (a false positive). Use a full 16-entry lane, and assert a cell OFF the
        // lapped column stays SILENT — which the uniform sweep would have SOUNDED, so the test now genuinely exercises the lap.
        let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }   // arp → a VISITED column keeps sounding
        var lane = [UInt8](repeating: 0, count: Snap.rows)
        lane[0] = 0b1        // row 0 laps COLUMN 0 only
        lane[1] = 0b1_0000   // row 1 laps COLUMN 4 only (independently)
        let b = box(colours: cs) { s in
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])        // row 0 · col 0 (cable 1) — ON row 0's lap
            s.cells[3][0] = Cell(colourID: "vermilion", buses: [.c])   // row 0 · col 3 (cable 3) — a col-0 lap NEVER visits it
            s.cells[4][1] = Cell(colourID: "azure", buses: [.b])       // row 1 · col 4 (cable 2) — ON row 1's lap
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
        let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        let b = box(colours: cs) { s in
            for c in 0..<4 { s.cells[c][0] = Cell(colourID: "gold", buses: [.a]) }   // arp across the 4-column loop
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
        let cs = colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; return c }
        let b = box(colours: cs) { s in
            s.cells[1][0] = Cell(colourID: "gold", buses: [.a])       // column 1 — INSIDE the length-4 loop
            s.cells[5][0] = Cell(colourID: "orange", buses: [.b])     // column 5 — BEYOND it
            s.rowLen = [4, nil, nil, nil, nil, nil, nil, nil]         // row 0 loops columns 0–3 only
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "column 1 is inside the 4-column loop — it sounds")
        XCTAssertEqual(e.ons.filter { $0.cable == 2 }.count, 0, "column 5 is beyond the loop length — never visited, silent")
        assertNothingLeftSounding(e)
    }
    // REEL COLOUR TAG (Paul 2026-08-19): the export-page piano roll paints each note the COLOUR of the cell that played
    // it. The render tags every note-ON with its colour's DISPLAY hue (baked into SnapColour, threaded via markColour
    // to the ReelTap), so the recorded pass carries it. Here: an arp on a gold cell whose hue is 0xFF8800 → every note
    // in the recorded roll is tagged 0xFF8800.
    func testReelRollTagsNotesWithTheCellColour() {
        var s = SceneState.empty(); s.cells[0][0] = Cell(colourID: "gold")
        let st = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [s])
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
        XCTAssertTrue(roll.allSatisfy { $0.colour == hue }, "every recorded note is tagged its cell's colour hue")
    }
    // PER-ROW ECHO/MOD/GLIDE (Paul 2026-08-19): in the multi-clock path echo/mod/glide fire on each ROW's own clock,
    // not the scene default. Two echo cells in column 0: row 0 FAST (1/8), row 1 SLOW (2/1). The echo DRY strikes on
    // each entry to its column, so the fast row re-enters column 0 far more often → far more dry strikes on its bus.
    func testPerRowEchoFiresOnTheRowsOwnClock() {
        let cs = colourIDs.map { Colour(colourID: $0, type: .echo) }
        let b = box(colours: cs) { s in
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])       // echo in column 0, row 0
            s.cells[0][1] = Cell(colourID: "orange", buses: [.b])     // echo in column 0, row 1
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
            box(colours: colourIDs.map { Colour(colourID: $0, type: .glide) }) { s in
                for c in 0..<8 {                                             // glide across every column so the anchor is live whatever the effective column
                    s.cells[c][0] = { var x = Cell(colourID: "gold", buses: [.a])
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
    // PLAY-LAYER ROWS 8…15 (Paul 2026-09-01): the hidden play layer occupies engine rows 8…15 (Snap.playLayerRowBase); the
    // multi-clock loops iterate all 16 rows and the tap/mute masks exempt rows ≥8 — but no RouterTest had ever placed a cell
    // there. A slow part cell (row 0, bus A) + a fast play-layer cell (row 8, bus B, its own fast rate) → the play row fires
    // far more, no A↔B cross-leak, nothing stuck (guards any latent rows-0–7 `%8`/`<8` assumption in the 16-row loops).
    func testPlayLayerRowsRunOnTheirOwnClockWithoutLeak() {
        let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        let b = box(colours: cs) { s in
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])                     // part cell — row 0, bus A
            while s.cells[0].count < Snap.rows { s.cells[0].append(nil) }           // extend the column so a play-layer row can hold a cell
            s.cells[0][Snap.playLayerRowBase] = Cell(colourID: "azure", buses: [.b]) // play-layer cell — row 8, bus B
            var rate = [StepRate?](repeating: nil, count: Snap.rows)
            rate[0] = .r2_1                                                          // row 0 SLOW
            rate[Snap.playLayerRowBase] = .r1_8                                      // row 8 FAST — its OWN clock
            s.rowStepRate = rate
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        let a = e.ons.filter { $0.cable == 1 }.count, playRow = e.ons.filter { $0.cable == 2 }.count
        XCTAssertGreaterThan(a, 0, "the part row (row 0) sounds on bus A")
        XCTAssertGreaterThan(playRow, 0, "the play-layer row (row 8) RENDERS on its OWN bus B — a cell in engine rows 8…15 runs in the multi-clock loop (the gap: no RouterTest had ever placed a cell there)")
        assertNothingLeftSounding(e)
    }
    // onlyRow LEGATO reconcile vs a surviving DRONE (Paul 2026-09-01): the multi-clock path scopes the hold reconcile per row
    // (onlyRow). A legato drone on a SLOW row must be ADOPTED (struck once per note, not re-struck) as a DIFFERENT fast row
    // transitions — a regressed `% Snap.rows == onlyRow` guard would machine-gun the drone or strand it. Drone (row 0, bus A) +
    // a fast CHANCE cell (row 1, bus B) → each drone note strikes exactly ONCE across the held span; nothing stuck.
    func testOnlyRowLegatoDroneSurvivesAFastNeighbourRow() {
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!].type = .drone
        cs[colourIDs.firstIndex(of: "azure")!].type = .chance   // a re-speaking fast neighbour (never immortal)
        let b = box(colours: cs) { s in
            for c in 0..<8 { s.cells[c][0] = Cell(colourID: "gold", buses: [.a]) }   // legato drone across the whole row 0
            for c in 0..<8 { s.cells[c][1] = Cell(colourID: "azure", buses: [.b]) }  // fast CHANCE across row 1
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
            var cs = arpColours(); let ci = colourIDs.firstIndex(of: "gold")!
            cs[ci].type = .chords
            let b = box(colours: cs) { s in
                s.cells[0][0] = { var x = Cell(colourID: "gold", buses: [.a])
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
    // PER-ROW GLIDE + MOD leave-disposition on the ROW's own clock (Paul 2026-09-01): only per-row ECHO was asserted. Two GLIDE
    // cells (fast row vs slow row) → the fast row re-anchors far more often (its phrase-ends fire on its OWN clock, not the
    // scene default); two MOD cells likewise emit their CC updates on each row's clock. Guards the onlyRow scoping of glide/mod.
    func testPerRowGlideAndModFireOnTheRowsOwnClock() {
        // GLIDE — fast row 0 vs slow row 1, each a single-slot glide on its own emitter.
        var gcs = arpColours()
        for id in ["gold", "azure"] { gcs[colourIDs.firstIndex(of: id)!].type = .glide }
        func glideCell(_ id: String, _ bus: Bus) -> Cell {
            var x = Cell(colourID: id, buses: [bus])
            var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glideRange = 12; g.params.glidePriority = .last; g.params.glideTime = 0.05
            x.processors = [g]; return x
        }
        let gb = box(colours: gcs) { s in
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
        var mcs = arpColours()
        for id in ["gold", "azure"] { let i = colourIDs.firstIndex(of: id)!; mcs[i].type = .mod; mcs[i].paramsA.modCC = 74 }
        let mb = box(colours: mcs) { s in
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])
            s.cells[0][1] = Cell(colourID: "azure", buses: [.b])
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
    // VELOCITY INHERITANCE (user 2026-08-09): every processor takes its output velocity from the input source note,
    // not a fixed 96. Octave-invariant (an octave-arped copy keeps the source dynamic).
    func testArpInheritsSourceVelocity() {
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, velChord([(60, 30), (67, 120)]), beats: 8, into: e)
        let vels = Set(e.ons.filter { $0.cable == 1 }.map { $0.vel })
        XCTAssertFalse(vels.isEmpty, "the arp sounded")
        XCTAssertTrue(vels.isSubset(of: [30, 120]), "every arp note carries a SOURCE velocity (30 or 120), never a flat 96 — got \(vels)")
        XCTAssertTrue(vels.contains(30) && vels.contains(120), "both source dynamics come through")
        assertNothingLeftSounding(e)
    }
    // A chain carries velocity end-to-end: [ARP → HARMONIZE] — the dry AND the +12 voice inherit the source velocity.
    func testChainInheritsSourceVelocityThroughHarmonize() {
        let b = box(colours: arpColours()) { $0.cells[0][0] = {
            var c = Cell(colourID: "gold", buses: [.a])
            let arp = ProcessorSlot(type: .arp)
            var h = ProcessorSlot(type: .harmonize); h.params.harmIntervals = [12, 0, 0]
            c.processors = [arp, h]; return c }() }
        let e = RecordingEmitter(); run(b, velChord([(60, 44)]), beats: 8, into: e)
        let dry = e.ons.filter { $0.cable == 1 && $0.note == 60 }
        let harm = e.ons.filter { $0.cable == 1 && $0.note == 72 }
        XCTAssertTrue(!dry.isEmpty && dry.allSatisfy { $0.vel == 44 }, "the dry note keeps its source velocity 44")
        XCTAssertTrue(!harm.isEmpty && harm.allSatisfy { $0.vel == 44 }, "the +12 harmony voice inherits the base note's velocity 44")
        assertNothingLeftSounding(e)
    }
    // A single-slot GENERATOR inherits too — euclid strikes each note at its own source velocity (envelope × source).
    func testEuclidGeneratorInheritsSourceVelocity() {
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
            c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, velChord([(60, 50), (64, 110)]), beats: 2, into: e)
        let a = e.ons.filter { $0.cable == 1 }
        XCTAssertTrue(a.filter { $0.note == 60 }.allSatisfy { $0.vel == 50 }, "euclid note 60 → source velocity 50")
        XCTAssertTrue(a.filter { $0.note == 64 }.allSatisfy { $0.vel == 110 }, "euclid note 64 → source velocity 110")
        assertNothingLeftSounding(e)
    }
    // The soundcheck path inherits velocity too (user 2026-08-09): a stopped-transport AUDITION of an arp cell sounds
    // at the source velocity, not a flat 96 — audition matches playback.
    func testAuditionInheritsSourceVelocity() {
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        XCTAssertTrue(vels.isSubset(of: [40, 118]), "audition inherits the source velocity (40/118), not a flat 96 — got \(vels)")
    }
    // THE PER-COLOUR MACHINE (user 2026-08-09, GLOBAL): a colour's `templateChain` drives EVERY cell of that colour
    // that has no per-cell override — the machine lives on the (document-global) COLOUR, not the cell.
    func testColourTemplateChainDrivesAllItsCells() {
        var cs = arpColours()                                   // gold head = arp…
        let gi = colourIDs.firstIndex(of: "gold")!
        var tmpl = ProcessorSlot(type: .euclid); tmpl.params.euclidPulses = 4; tmpl.params.euclidSteps = 8
        cs[gi].templateChain = [tmpl]                           // …but the COLOUR owns a euclid machine
        let b = box(colours: cs) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // processors == nil → inherit the colour template
            $0.cells[0][1] = Cell(colourID: "gold", buses: [.a])
        }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 24, "both gold cells render the COLOUR's euclid template (2 cells × 4-of-8 × 3 notes)")
        assertNothingLeftSounding(e)
    }
    // PLAY: THIS CELL (user 2026-08-09): forcing the effective column HOLDS the cell in that column playing every
    // window, regardless of the natural timeline — so an isolated cell sounds continuously, ungated by the sequence.
    // Uses an ARP (tick-emitter) — the case that needs iterateTicks UNGATED; a generator decouples via colStart.
    func testForceColumnHoldsTheCellPlayingEveryColumn() {
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // arp cell in column 0
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
    // still showed its colour "running". The fix re-runs the holds every window (immortal + adopted) under forceColumn.
    // pending-tasks E / 2026-08-23 adversarial hunt: PLAY: THIS CELL (forceColumnHold) on a SELF-COLLIDING harmonize —
    // {60,67}+7 fans 60's +7 onto 67's root — leaked a fresh immortal voice EVERY reconcile window: adoptLegatoBus
    // un-marked BOTH colliding pairs on the first source's call, so the second source found none and re-struck. It
    // machine-gunned and grew toward the voice cap under audition. The fix adopts one own+All pair per call, so the
    // colliding wire is struck once then HELD (adopted), not re-struck each window.
    func testForceColumnSelfCollidingHarmonizeDoesNotLeakVoices() {
        var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = [7, 0, 0]   // +7: 60→67 collides with 67's root
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .passgate   // identity hold (all-open, .retrig = non-legato)
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
    // STRUM colour was silent on the machine audition; the fix re-arms it each musical step. (Paul 2026-08-15)
    func testForceColumnReArmsStrumEachStep() {
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .strum; cs[colourIDs.firstIndex(of: "gold")!].paramsA.spread = 0.1
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
    // ARP → FIT (user 2026-08-11): cycle = one beat, so a bigger chord ticks FASTER (more note-ons in the same time).
    func testArpFitScalesRateWithChordSize() {
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].paramsA.arpFit = true
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        func ons(_ notes: [UInt8]) -> Int { let e = RecordingEmitter(); run(b, chord(notes), beats: 8, into: e); return e.ons.filter { $0.cable == 1 }.count }
        XCTAssertGreaterThan(ons([60, 64, 67, 71, 74, 77]), ons([60, 64]), "a 6-note chord fits faster → more ticks than a 2-note")
    }
    // CHANCE → WEIGHT/tilt RENDERED (not just the pure fn): with prob 0.5, +tilt drives the TOP note's p→1 (always
    // sounds) and the BOTTOM's p→0 (dropped); −tilt reverses. Proves the router READS chanceTilt at the hold path.
    func testChanceWeightBiasesEmittedNotes() {
        func topBot(_ tilt: Double) -> (top: Int, bot: Int) {
            var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
            cs[gi].type = .chance; cs[gi].paramsA.probability = 0.5; cs[gi].paramsA.chanceTilt = tilt
            let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
            var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
            cs[gi].type = .strum; cs[gi].paramsA.spread = 0.5; cs[gi].paramsA.strumSpreadNorm = norm
            let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 62, 64, 65, 67, 69]), beats: 1.9, into: e)
            return e.ons.filter { $0.cable == 1 }.map { $0.sample }.max() ?? 0
        }
        XCTAssertGreaterThan(lastOnset(false), lastOnset(true), "PER-NOTE spreads the rake wider → later last onset")
    }
    // DRONE = a LEGATO chord-hold (user 2026-08-10): placed across columns it HOLDS continuously (NO re-strike per
    // step) and is SILENT where no drone cell is (playhead-dependent). gold=drone in cols 0..3; hold a chord one pass.
    func testDroneIsALegatoHoldAcrossItsColumns() {
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .drone
        let b = box(colours: cs) { for c in 0..<4 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) } }   // drone cols 0-3, row 0
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
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .drone
        let bLive = box(colours: cs) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) } }   // drone the whole row → it holds every column
        let bMute = box(colours: cs, masterMute: true) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) } }
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
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!].type = .passgate   // identity holds → sustained voices to snapshot
        cs[colourIDs.firstIndex(of: "cyan")!].type = .passgate
        let b = box(colours: cs) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])
            $0.cells[0][1] = Cell(colourID: "cyan", buses: [.c])
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
    // PLAY: THIS CELL overrides MUTE (user 2026-08-10): a MUTED cell that is the solo target must still play — the
    // feature isolates and previews the cell's machine regardless of grid mute/dormant. (The muted orange cell that
    // "PLAY: THIS CELL did nothing on".) A non-target muted cell stays silent (mute enforced when not soloed).
    func testForceColumnPlaysAMutedSoloedCell() {
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .passgate   // identity hold
        let b = box(colours: cs) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])                                   // unmuted cell above
            $0.cells[0][1] = { var c = Cell(colourID: "gold", buses: [.a]); c.muted = true; return c }()   // MUTED cell (the solo target)
        }
        let e = RecordingEmitter(); let router = Router(); var diag = KernelDiag()
        let pool = chord([60, 64, 67]); let frames: UInt32 = 2048, tempo = 120.0, sr = 48_000.0
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        let soloMask = UInt64(1) << UInt64(0 * 8 + 1)   // solo the MUTED cell at (0,1)
        while beat < 16.0 {
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, soloCellMask: soloMask, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67], "the MUTED soloed cell still plays its chord under PLAY: THIS CELL")
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        assertNothingLeftSounding(e)
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
        let gi = colourIDs.firstIndex(of: "gold")!
        func mk(_ iv: [Int]) -> SnapshotBox {
            var cs = arpColours(); cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = iv
            return box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = [4, 7, 0]   // 60 → 60/64/67
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let gi = colourIDs.firstIndex(of: "gold")!
        func mk(_ n: Int) -> SnapshotBox {
            var cs = arpColours(); cs[gi].type = .octave; cs[gi].paramsA.utilOctave = n
            return box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        }
        let up = RecordingEmitter(); run(mk(1), chord([60, 64, 67]), beats: 2, into: up)
        XCTAssertEqual(Set(up.ons.filter { $0.cable == 1 }.map { Int($0.note) }), [72, 76, 79], "+1 octave lifts each held note")
        let dn = RecordingEmitter(); run(mk(-2), chord([60, 64, 67]), beats: 2, into: dn)
        XCTAssertEqual(Set(dn.ons.filter { $0.cable == 1 }.map { Int($0.note) }), [36, 40, 43], "−2 octaves lowers each note")
        assertNothingLeftSounding(up); assertNothingLeftSounding(dn)
    }
    // UTILITY — TRANSPOSE: shifts the held chord by semitones; notes shifted out of the MIDI range simply drop.
    func testTransposeShiftsBySemitonesAndDropsOutOfRange() {
        let gi = colourIDs.firstIndex(of: "gold")!
        func mk(_ st: Int) -> SnapshotBox {
            var cs = arpColours(); cs[gi].type = .transpose; cs[gi].paramsA.utilTranspose = st
            return box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
            box(colours: arpColours()) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = procs; return c }() }
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
        let b = box(colours: arpColours()) {
            var c = Cell(colourID: "gold", buses: [.a])
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
        let gi = colourIDs.firstIndex(of: "gold")!
        func mk(_ ch: Int) -> SnapshotBox {
            var cs = arpColours(); cs[gi].type = .channel; cs[gi].paramsA.utilChannel = ch
            return box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let gi = colourIDs.firstIndex(of: "gold")!
        func mk(_ n: Int) -> SnapshotBox {
            var cs = arpColours(); cs[gi].type = .nudge; cs[gi].paramsA.utilNudge = n
            return box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
            c.paramsA.euclidSteps = 8; c.paramsA.euclidPulsesFromPool = true; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e3 = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e3)          // 3 held → 3 pulses × 3 notes
        XCTAssertEqual(e3.ons.filter { $0.cable == 1 }.count, 9, "POOL: 3 held → E(3,8)")
        let e4 = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 2, into: e4)      // 4 held → 4 pulses × 4 notes
        XCTAssertEqual(e4.ons.filter { $0.cable == 1 }.count, 16, "POOL: 4 held → E(4,8)")
        assertNothingLeftSounding(e3); assertNothingLeftSounding(e4)
    }
    // GENERATORS AS CHAIN DRIVERS (user 2026-08-09): the driver drives, downstream slots fold; upstream composes.
    func testEuclidThenOpenPassgateStillGenerates() {
        let b = box(colours: arpColours()) {
            var c = Cell(colourID: "gold", buses: [.a])
            var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = 4; eu.params.euclidSteps = 8
            var gate = ProcessorSlot(type: .passgate); gate.params.passes = [true, true, true, true]
            c.processors = [eu, gate]; $0.cells[0][0] = c
        }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 12, "euclid drives; the open gate folds through → 4 pulses × 3 notes")
        assertNothingLeftSounding(e)
    }
    func testEuclidThenClosedPassgateIsSilent() {
        let b = box(colours: arpColours()) {
            var c = Cell(colourID: "gold", buses: [.a])
            var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = 4; eu.params.euclidSteps = 8
            var gate = ProcessorSlot(type: .passgate); gate.params.passes = [false, false, false, false]
            c.processors = [eu, gate]; $0.cells[0][0] = c
        }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "the closed gate after euclid folds to silence")
        assertNothingLeftSounding(e)
    }
    func testHarmonizeThenEuclidGeneratesOverTheComposedSet() {
        func mk(harm: Bool) -> SnapshotBox {
            box(colours: arpColours()) {
                var c = Cell(colourID: "gold", buses: [.a])
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
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .burst)
            c.paramsA.count = 4; c.paramsA.curve = 0; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 4, "a 4-strike burst on one note")
        assertNothingLeftSounding(e)
    }
    func testBurstDownbeatFiresOnAnUnalignedColumnBoundary() {
        // REGRESSION (Paul 2026-08-18): like EUCLID, a window-scan generator dropped its DOWNBEAT strike (f=0, at the
        // column boundary) when the boundary fell mid render-block. Placed in COLUMN 1 (start = S = 2, mid-block), the
        // 4-strike even burst must still sound all 4 (was 3 = the f=0 strike lost). The scanFrom fix catches it.
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .burst)
            c.paramsA.count = 4; c.paramsA.curve = 0; return c }) { $0.cells[1][0] = Cell(colourID: "gold", buses: [.a]) }
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
            box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .length)
                c.paramsA.lenSlices = [.short, .mute, .short, .mute, .short, .mute, .short, .mute]
                c.paramsA.lenSpan = span; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) }   // the LENGTH fills the whole row
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
            box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .burst)
                c.paramsA.count = 4; c.paramsA.curve = 0; c.paramsA.burstSpan = span; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) }
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
            let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .burst)
                c.paramsA.count = 4; c.paramsA.curve = 0; c.paramsA.burstMode = .pattern; c.paramsA.burstSlices = slices; c.paramsA.burstSpan = .cell; return c }) {
                $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
            let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .burst)
                c.paramsA.count = 2; c.paramsA.curve = 0; c.paramsA.burstMode = .pattern
                c.paramsA.burstSlices = [.burst, .rest, .burst, .rest, .burst, .rest, .burst, .rest]   // 4 launches / 8 slices
                c.paramsA.burstSpan = .row; c.paramsA.burstRateOn = rateOn; c.paramsA.burstRate = rate; return c }) {
                $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
            let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .burst)
                c.paramsA.count = 4; c.paramsA.curve = 0; c.paramsA.burstMode = .coin; c.paramsA.burstChance = chance; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) } }
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
            box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .cascade)
                c.paramsA.rate = .r1_8; c.paramsA.cascadeSpan = span; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) }
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
            box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .tutti)
                c.paramsA.tuttiMode = .pattern
                c.paramsA.tuttiSlices = [.all, .rest, .all, .rest, .all, .rest, .all, .rest]
                c.paramsA.tuttiRate = .r1_16; c.paramsA.tuttiSpan = span; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) }
            }
        }
        let eRow = RecordingEmitter(); run(rowBox(.row), chord([60, 64, 67]), beats: 16, into: eRow, releaseAtEnd: false)
        let eCell = RecordingEmitter(); run(rowBox(.cell), chord([60, 64, 67]), beats: 16, into: eCell, releaseAtEnd: false)
        let onsRow = eRow.ons.filter { $0.cable == 1 }.count, onsCell = eCell.ons.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(onsRow, 0, "the ROW tutti-pattern sounds")
        XCTAssertLessThan(onsRow, onsCell, "SPAN ROW spreads the 8-slice shape across the bar; CELL strides it at the fast RATE")
        assertNothingLeftSounding(eRow); assertNothingLeftSounding(eCell)
    }
    func testRatchetPatternSpanRowSpreadsCountsAcrossTheBar() {
        // SPAN ROW (Paul 2026-08-19): the 8 per-slice counts span the whole bar (slice i = column i); CELL strides at the RATE.
        func rowBox(_ span: PatternSpan) -> SnapshotBox {
            box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .ratchet)
                c.paramsA.rtcMode = .pattern
                c.paramsA.rtcSlices = [3, 0, 3, 0, 3, 0, 3, 0]
                c.paramsA.rtcRate = .r1_16; c.paramsA.rtcSpan = span; return c }) {
                for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) }
            }
        }
        let eRow = RecordingEmitter(); run(rowBox(.row), chord([60, 64, 67]), beats: 16, into: eRow, releaseAtEnd: false)
        let eCell = RecordingEmitter(); run(rowBox(.cell), chord([60, 64, 67]), beats: 16, into: eCell, releaseAtEnd: false)
        let onsRow = eRow.ons.filter { $0.cable == 1 }.count, onsCell = eCell.ons.filter { $0.cable == 1 }.count
        XCTAssertGreaterThan(onsRow, 0, "the ROW ratchet-pattern sounds")
        XCTAssertLessThan(onsRow, onsCell, "SPAN ROW spreads the per-slice counts across the bar; CELL strides at the fast RATE")
        assertNothingLeftSounding(eRow); assertNothingLeftSounding(eCell)
    }
    func testCascadeRevealsEachChordNoteOnce() {
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .cascade)
            c.paramsA.rate = .r1_8; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
            box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .cascade); c.paramsA.rate = .r1_8; return c }) {
                for c in cols { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .drone)
            c.paramsA.gate = 0.6; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 3, "the chord held once as a pad")
        assertNothingLeftSounding(e)
    }
    func testShiftNudgesTheChordLate() {
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .shift)
            c.paramsA.spread = 0.5; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 3, "the chord, nudged late, once")
        assertNothingLeftSounding(e)
    }
    func testHumanizeIsSeededAndReplaySafe() {
        func mk() -> SnapshotBox {
            box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .humanize)
                c.paramsA.spread = 0.8; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .echo)
            c.paramsA.echoDelayDiv = 1; c.paramsA.echoRepeats = 12; c.paramsA.echoFeedDelay = 1
            c.paramsA.echoDecay = 1; c.paramsA.echoPitch = 12; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([100]), beats: 3, into: e)             // 100 → 112 → 124 → 136 (out of range → dropped) …
        XCTAssertTrue(e.events.allSatisfy { $0.note <= 127 }, "no wire byte encodes a note above 127")
        assertNothingLeftSounding(e)
    }
    func testFloodGovernorCapsAndCountsDrops() {
        // Pathological flood: 8 dense euclid cells in column 0, all on emitter A, over a big chord — far past the
        // per-beat cap. The governor drops the overflow (counted, surfaced to HEALTH) and leaves nothing stuck.
        let cs = colourIDs.map { var c = Colour(colourID: $0, type: .euclid)
            c.paramsA.euclidPulses = 16; c.paramsA.euclidSteps = 16; return c }
        let b = box(colours: cs) { for r in 0..<8 { $0.cells[0][r] = Cell(colourID: colourIDs[r], buses: [.a]) } }
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
            var s = SceneState.empty(); s.cells[0][0] = Cell(colourID: "gold", buses: [.a])
            s.row8On = on ? [true, false, false, false, false, false, false, false] : nil
            var st = PluginState(colours: arpColours(), scenes: [s]); st.busChannels = [1, 2, 3, 4]
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
    // boundaries are crossed → half the (distinct-colour) drone re-strikes. ×1/none is byte-identical.
    func testRow8HalftimeSlowsTheColumnClock() {
        func onsOver8Beats(halftime: Bool) -> Int {
            var cs: [Colour] = []
            for (c, id) in colourIDs.enumerated() { var col = Colour(colourID: id, type: .drone); col.transpose = c; cs.append(col) }
            var s = SceneState.empty()
            for c in 0..<8 { s.cells[c][0] = Cell(colourID: colourIDs[c], buses: [.a]) }   // a distinct-note drone per column
            if halftime { s.row8On = [true, false, false, false, false, false, false, false] }
            var st = PluginState(colours: cs, scenes: [s]); st.busChannels = [1, 2, 3, 4]
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
            var s = SceneState.empty(); s.cells[0][0] = Cell(colourID: "gold", buses: [cellBus])
            s.row8On = [true, false, false, false, false, false, false, false]
            var st = PluginState(colours: arpColours(), scenes: [s]); st.busChannels = [1, 2, 3, 4]
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
        var s = SceneState.empty(); s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // the cell emits on A only
        s.row8On = [true, false, false, false, false, false, false, false]
        var st = PluginState(colours: arpColours(), scenes: [s]); st.busChannels = [1, 2, 3, 4]
        st.row8 = [Row8Cell.make(.broadcast)]
        let e = RecordingEmitter(); run(SnapshotBuilder.build(from: st), chord([60]), beats: 4, into: e)
        for cable: UInt8 in 1...4 {
            XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == cable }, "BROADCAST mirrors the note to wire \(cable)")
        }
        XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == 0 }, "…and the ALL cable")
        assertNothingLeftSounding(e)
    }

    func testPanicBlastsAllNotesOffAndAllSoundOffOnEveryChannel() {
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: arpColours(), busChannels: [5, 2, 3, 4]) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.events.count, 0)
        XCTAssertTrue(e.events.allSatisfy { $0.chan == 4 }, "every message carries the bus-A stamp (5 → wire 4)")
        assertNothingLeftSounding(e)
    }

    func testMutedCellEmitsNothing() {
        var cell = Cell(colourID: "gold"); cell.muted = true
        let b = box(colours: arpColours()) { $0.cells[0][0] = cell }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.events.isEmpty, "a muted cell (§6.2) produces no MIDI on any cable")
    }

    func testMutingMidPlaybackSilencesCellWithoutStuckNotes() {
        // DEFAULT GRID TAP = MUTE (2026-08-01): muting a SOUNDING cell mid-playback must (a) stop its emitter
        // output and (b) leave no hung note. Simulate the tap by swapping to a snapshot with the cell muted.
        let live = box(colours: arpColours()) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) } }
        let mb   = box(colours: arpColours()) { for c in 0..<8 { $0.cells[c][0] = { var cell = Cell(colourID: "gold", buses: [.a]); cell.muted = true; return cell }() } }
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
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b]) }
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
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, chord([60, 64, 67]), target: 0, windows: 24, into: e)   // 0 = col0*8+row0
        XCTAssertGreaterThan(e.ons.count, 0, "a held ARP should sound while stopped (audition)")
        assertNothingLeftSounding(e)
    }

    func testAuditionWithNoHeldNotesIsSilent() {
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, NotePool(), target: 0, windows: 12, into: e)            // no keys held
        XCTAssertTrue(e.events.isEmpty, "audition soundcheck is silent with no source notes")
    }

    func testAuditionOfEmptyCellIsSilent() {
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, chord([60, 64, 67]), target: 5 * 8 + 5, windows: 12, into: e)   // (col5,row5) empty
        XCTAssertTrue(e.events.isEmpty, "auditioning an empty cell produces nothing")
    }

    func testAuditionRatchetSounds() {
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .ratchet
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, chord([60, 63, 67]), target: 0, windows: 24, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "a held RATCHET re-strikes the chord while stopped")
        assertNothingLeftSounding(e)
    }

    func testAuditionEmitsOnTheCellsBusAndAllCable() {
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.b]) }
        let e = RecordingEmitter()
        auditionRun(b, chord([60, 64, 67]), target: 0, windows: 24, into: e)
        XCTAssertTrue(e.ons.contains { $0.cable == 2 }, "audition emits on the lit bus (B = cable 2)")
        XCTAssertTrue(e.ons.contains { $0.cable == 0 }, "audition also emits on the ALL cable")
        XCTAssertTrue(e.ons.allSatisfy { $0.cable == 0 || $0.cable == 2 }, "no emission on unlit buses")
    }

    func testTransportStartAutoReleasesAudition() {
        // Hold an ARP audition, then start the transport: the transport-start edge must flush the
        // audition voices (auto-release, §6.4) — nothing left sounding after a stop.
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold") }
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
        var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = [4, 7, 0]   // +4, +7, third off
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold") }
        let e = RecordingEmitter()
        auditionRun(b, chord([60]), target: 0, windows: 20, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 0 }.map { $0.note }), [60, 64, 67], "root + intervals")
        XCTAssertEqual(e.ons.filter { $0.cable == 0 }.count, 3, "sustained — each note struck once, not per window")
        assertNothingLeftSounding(e)
    }

    func testAuditionChancePassesAllAtOneAndNoneAtZero() {
        var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].type = .chance
        cs[gi].paramsA.probability = 1.0
        let bAll = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold") }
        let eAll = RecordingEmitter()
        auditionRun(bAll, chord([60, 64, 67]), target: 0, windows: 12, into: eAll)
        XCTAssertEqual(Set(eAll.ons.filter { $0.cable == 0 }.map { $0.note }), [60, 64, 67], "p=1 sustains the whole chord")
        assertNothingLeftSounding(eAll)

        cs[gi].paramsA.probability = 0.0
        let bNone = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold") }
        let eNone = RecordingEmitter()
        auditionRun(bNone, chord([60, 64, 67]), target: 0, windows: 12, into: eNone)
        XCTAssertTrue(eNone.events.isEmpty, "p=0 auditions to silence (processor drops everything)")
    }

    func testAuditionChordHoldTracksHeldKeysLive() {
        // The sustained preview must FOLLOW the keys: add one mid-hold → it sounds; release one → it
        // stops, while the rest keep sounding. (passgate is forced all-open, so it's an identity hold.)
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .passgate
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold") }
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
        var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].type = .strum; cs[gi].paramsA.spread = 0.4   // wide roll → spans several windows
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold") }
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
    private func box(colours cs: [Colour], busEnabled: [Bool]?, _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(colours: cs, scenes: [s]); st.busEnabled = busEnabled
        return SnapshotBuilder.build(from: st)
    }

    func testDisabledEmitterIsSilentOnItsCableAndAll() {
        // Cell → bus B only, with B disabled: nothing on cable 2 (B) or cable 0 (All).
        let b = box(colours: arpColours(), busEnabled: [true, false, true, true]) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(e.events.isEmpty, "a disabled emitter produces nothing on its own cable OR All")
    }

    func testAllIsTheSumOfEnabledEmitters() {
        // Fan-out to A and B; disable A → A silent, B sounds, All carries only B's stream.
        let b = box(colours: arpColours(), busEnabled: [false, true, true, true]) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
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
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold") }   // bus A
        let e = RecordingEmitter()
        let router = Router(); var diag = KernelDiag()
        let pool = chord([60]); let sr = 48_000.0; let frames: UInt32 = 2048
        let wb = Double(frames) * 120 / 60 / sr
        var beat = 0.0, ts = 0.0
        let boxOff = box(colours: arpColours(), busEnabled: [false, true, true, true]) { $0.cells[0][0] = Cell(colourID: "gold") }
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
        var st = PluginState(colours: arpColours(), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b]); return s }()])
        st.busChannels = [3, 3, 3, 4]              // A and B both stamp channel 3
        st.busEnabled = [false, true, true, true]  // A disabled
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 0 && $0.chan == 2 }.count, 0,
                             "All still carries the shared-channel note via B (wire ch 2 = stamp 3)")
        assertNothingLeftSounding(e)
    }

    func testMeteringFeedReportsPerEmitterPeakAndEventsThenClears() {
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .ratchet
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold") }   // bus A only
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
        let b = box(colours: arpColours(), busEnabled: [false, true, true, true]) { $0.cells[0][0] = Cell(colourID: "gold") }
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
        // sounding voice on emitter A (carrying its velocity + source colourIndex) and NONE on B/C/D; after the
        // chord releases and the notes close, every emitter's sounding set empties.
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .ratchet
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
                XCTAssertGreaterThanOrEqual(s[0].first!.col, 0, "…and its source colour (cargo tint)")
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

    // MARK: - item 4 VELOCITY MARKS — the per-note (velocity, source-colour) ring drained by drainMarks()

    func testDrainMarksStampsSourceColourAndReadClears() {
        // An arp on the GOLD cell (colourIndex 0) → bus A. Each note-on leaves a mark carrying its velocity
        // and the emitting cell's colourIndex — the source tint the strip meter draws.
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        XCTAssertTrue(m[0].allSatisfy { $0.col == 0 }, "each mark is tinted by the source Colour (gold = index 0)")
        XCTAssertTrue(m[0].allSatisfy { $0.vel > 0 }, "each mark carries the note-on velocity")
        XCTAssertEqual([m[1].count, m[2].count, m[3].count], [0, 0, 0], "silent emitters collect no marks")
        XCTAssertTrue(router.drainMarks()[0].isEmpty, "drain read-and-clears")
    }

    func testDrainMarksFansSameTintToEveryBus() {
        // A cell fanning to A+B stamps the SAME source colourIndex on both buses' marks.
        let wine = Int8(colourIDs.firstIndex(of: "wine")!)
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "wine", buses: [.a, .b]) }
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
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: arpColours(), busEnabled: [true, false, true, true]) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.b])
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
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold") }   // bus A
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
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b]) }
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
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold") }
        let e = RecordingEmitter()
        runVel(b, chord([60]), beats: 16, velOverride: 0, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "sounded")
        XCTAssertTrue(e.ons.allSatisfy { $0.vel > 0 }, "no override ⇒ natural velocity, never a zeroed note-on")
    }

    func testVelocityOverrideOnDisabledEmitterStaysSilent() {
        // The enable gate wins: overriding a DISABLED emitter still emits nothing (override is applied after it).
        let b = box(colours: arpColours(), busEnabled: [true, false, true, true]) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.b])
        }
        let e = RecordingEmitter()
        runVel(b, chord([60]), beats: 16, velOverride: packVel(1, 40), into: e)
        XCTAssertTrue(e.events.isEmpty, "a disabled emitter produces nothing even with an override set")
    }

    // MARK: - CLAIM (§6a) — one-claimant exclusivity, suppression against the live voice table

    /// A PASSGATE all-open colour (sustains the chord to the column boundary = the claimant "holds" a
    /// pitch), optionally transposed so a second emitter can hold a DIFFERENT pitch (the residue case).
    private func passgateColour(_ id: String, transpose: Int = 0) -> Colour {
        var c = Colour(colourID: id, type: .passgate)
        c.paramsA.passes = [true, true, true, true]
        c.paramsA.gate = 1.0
        c.transpose = transpose
        return c
    }
    /// Colours with gold → held on A (transpose 0) and cyan → held on B (transposeB); the rest are arps.
    private func claimColours(transposeB: Int) -> [Colour] {
        colourIDs.map { id in
            if id == "gold" { return passgateColour(id, transpose: 0) }
            if id == "cyan" { return passgateColour(id, transpose: transposeB) }
            return Colour(colourID: id, type: .arp)
        }
    }
    private func claimBox(_ cs: [Colour], claim: Int?, _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(colours: cs, scenes: [s]); st.claimEmitter = claim
        return SnapshotBuilder.build(from: st)
    }

    func testColourIndexBeyondOverrideTableDoesNotTrapRender() {
        // Paul 2026-08-15 crash (SIGTRAP adding a 2nd flattened part): the render-side override table is sized for the
        // 16 host-automatable colours (transpose at slot 2+i), but the unlimited-ephemeral-colours model can place a
        // cell whose colour index ≥33, so over(2+ci) read PAST the table end → out-of-bounds trap on the render thread.
        // A colour beyond the 16 automatable slots has no param override → it must fall back to its own transpose.
        var colours = colourIDs.map { Colour(colourID: $0, type: .arp) }        // the canonical 16
        for i in 0..<24 { colours.append(passgateColour("x\(i)", transpose: 0)) }   // 40 total → last index 39 ≫ 33
        colours[colours.count - 1].transpose = 7                                 // the high-index colour transposes +7
        let hi = colours[colours.count - 1].colourID
        var s = SceneState.empty()
        s.cells[0][0] = Cell(colourID: hi, buses: [.a])
        let box = SnapshotBuilder.build(from: PluginState(colours: colours, scenes: [s]))
        let e = RecordingEmitter()
        run(box, chord([60]), beats: 4, into: e)                                // must not trap
        XCTAssertTrue(e.events.contains { $0.status == 0x90 && $0.note == 67 }, "the high-index colour holds 60 transposed to 67, using its own transpose")
        assertNothingLeftSounding(e)
    }

    func testClaimSuppressesSamePitchOnNonClaimant() {
        // One cell fans A+B; A claims. Within the articulation A opens 60 first, so B yields it: nothing
        // on cable 2, and All (cable 0) carries A's copy only.
        let b = claimBox(claimColours(transposeB: 0), claim: 0) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
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
        let b = claimBox(claimColours(transposeB: 5), claim: 0) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // col 0, row 0 → held 60 on A
            $0.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // col 0, row 1 → held 65 on B (the residue)
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
        let b = claimBox(claimColours(transposeB: 12), claim: 0) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // held 60 (C3) on A — the claimant
            $0.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // held 72 (C4) on B — same class, one octave up
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
        let b = claimBox(claimColours(transposeB: 0), claim: 0) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // col 0, row 0 — claimant, emits first
            $0.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // col 0, row 1 — spillover
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "A holds 60")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 && $0.note == 60 }.isEmpty, "B yields 60 to the claimant")
        assertNothingLeftSounding(e)
    }

    func testNoClaimLetsBothEmittersSoundTheSamePitch() {
        // Control: with no claim, the same fan-out sounds the pitch on BOTH cables (§7 refcount, not exclusivity).
        let b = claimBox(claimColours(transposeB: 0), claim: nil) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
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
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!].paramsA.rate = .r1_32   // fast — note fits inside a window
        let b = claimBox(cs, claim: 0) {
            for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a, .b]) }
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
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // col 0, row 0 → A reserves 60 (muted)
            s.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // col 0, row 1 → B would hold 60
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
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
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
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!].paramsA.rate = .r1_32
        cs[colourIDs.firstIndex(of: "cyan")!].paramsA.rate = .r1_32
        let b = claimBox(cs, claim: 0) {
            for c in 0..<8 {
                $0.cells[c][0] = Cell(colourID: "gold", buses: [.a])   // row 0 — claimant, Emit A
                $0.cells[c][1] = Cell(colourID: "cyan", buses: [.b])   // row 1 — Emit B, same pitch
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
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!].paramsA.rate = .r1_32
        cs[colourIDs.firstIndex(of: "cyan")!].paramsA.rate = .r1_32
        var st = PluginState(colours: cs, scenes: [{ var s = SceneState.empty()
            for c in 0..<8 {
                s.cells[c][0] = Cell(colourID: "gold", buses: [.a])   // muted claimant
                s.cells[c][1] = Cell(colourID: "cyan", buses: [.b])
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
        let cs = arpColours()
        // Fill row 0 across every column so the arp fires whichever column is active in each phase.
        let claimA = claimBox(cs, claim: 0) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a, .b]) } }
        let claimB = claimBox(cs, claim: 1) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a, .b]) } }
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
    private func claimMaskBox(_ cs: [Colour], mask: UInt8, leak: [Int] = [0, 0, 0, 0],
                              _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(colours: cs, scenes: [s]); st.claimMask = mask; st.claimLeak = leak
        return SnapshotBuilder.build(from: st)
    }

    func testMultiClaimSuppressesNonClaimantsAcrossTheUnion() {
        // A and B both claim (SHARED tier). One cell fans A+B+C. C yields the pitch class (owned by the
        // union), but A and B BOTH sound it — claimants never suppress each other (deliberate doubling).
        let b = claimMaskBox(claimColours(transposeB: 0), mask: 0b0011) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b, .c])
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
        let b = claimMaskBox(claimColours(transposeB: 0), mask: 0b0001, leak: [50, 0, 0, 0]) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
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
        let b = claimMaskBox(claimColours(transposeB: 0), mask: 0b0011, leak: [60, 20, 0, 0]) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b, .c])
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
        let b = claimMaskBox(claimColours(transposeB: 0), mask: 0b0001, leak: [0, 0, 0, 0]) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(e.ons.filter { $0.cable == 2 }.isEmpty, "LEAK 0 ⇒ hard suppression (v1 behaviour)")
        assertNothingLeftSounding(e)
    }

    // MARK: - THE RACK (design-the-rack §3) — the two-tier gate: RACK off ⇒ raw wire regardless of the matrix

    private func rackClaimBox(_ cs: [Colour], claim: UInt8, rack: UInt8?, _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(colours: cs, scenes: [s]); st.claimMask = claim; st.rackEnabledMask = rack
        return SnapshotBuilder.build(from: st)
    }

    func testRackOffMakesClaimantARawWire() {
        // A claims (matrix armed) but A's RACK is OFF (bit 0 clear) → the board is out of the signal path, so A's
        // claim does NOT apply: a cell fanning A+B lets B keep the pitch (the raw wire, as if nothing were armed).
        let b = rackClaimBox(claimColours(transposeB: 0), claim: 0b0001, rack: 0b1110) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "A still sounds (LIVE, not RACK, silences)")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 && $0.note == 60 }.count, 0, "B keeps the pitch — A's rack is out of path, so no claim")
        assertNothingLeftSounding(e)
    }

    func testRackOnKeepsClaimSuppression() {
        // Same doc but A's RACK ON (all bits set) → claim applies exactly as before: B yields the claimed pitch.
        let b = rackClaimBox(claimColours(transposeB: 0), claim: 0b0001, rack: 0b1111) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 && $0.note == 60 }.count, 0, "A (claimant) sounds")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 }.isEmpty, "B yields — rack in path, claim applies")
        assertNothingLeftSounding(e)
    }

    func testRackGatePreAndsTreatmentMasksIntoTheBox() {
        // The builder pre-ANDs the rack gate into every treatment mask; a missing gate ⇒ all-on (old-doc safe).
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [SceneState.empty()])
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
        // CLAIM (leak 0) fully suppresses B → drainWithheld reports B's note, tinted by the source Colour
        // (gold = 0); the claimant A withholds nothing (it sounds).
        let b = claimMaskBox(claimColours(transposeB: 0), mask: 0b0001) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
        }
        let wh = drainWithheldAfter(b)
        XCTAssertFalse(wh[1].isEmpty, "B's CLAIM-suppressed note is recorded as withheld")
        XCTAssertTrue(wh[1].allSatisfy { $0.col == 0 }, "the withheld mark carries the source Colour (gold = 0)")
        XCTAssertTrue(wh[0].isEmpty, "the claimant (A) withholds nothing — it sounds")
    }

    func testLeakedNoteIsNotWithheld() {
        // A LEAK bleed (leak > 0) sounds as a shadow, so it is NOT a withholding — no hollow mark.
        let b = claimMaskBox(claimColours(transposeB: 0), mask: 0b0001, leak: [50, 0, 0, 0]) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
        }
        XCTAssertTrue(drainWithheldAfter(b)[1].isEmpty, "a LEAK bleed sounds → not withheld")
    }

    func testNoClaimWithholdsNothing() {
        let b = claimMaskBox(claimColours(transposeB: 0), mask: 0) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
        }
        XCTAssertTrue(drainWithheldAfter(b).allSatisfy { $0.isEmpty }, "no claim ⇒ nothing withheld")
    }

    // MARK: - COVERAGE HARDENING — device topologies (T-series) with no prior unit coverage

    func testCollisionRefcountKeepsSustainedNoteAliveThroughArpRestrikes() {
        // §7 collision policy + WIRE ARTICULATION = RESTRIKE (user 2026-08-09): a PASSGATE hold and a same-pitch ARP
        // on the SAME bus + channel. The arp re-strikes 60 every tick; each strike is now a clean OFF→ON re-attack
        // (retriggering), so ons and offs pace together. The refcount still keeps the hold alive across the strikes
        // (it never hits 0 mid-column) and pairs the final release exactly — nothing stuck.
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!] = passgateColour("gold")   // hold
        cs[colourIDs.firstIndex(of: "cyan")!].paramsA.rate = .r1_16      // arp, same pitch pool
        let b = box(colours: cs) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // col 0, row 0 → holds 60 on A (ch 1)
            $0.cells[0][1] = Cell(colourID: "cyan", buses: [.a])   // col 0, row 1 → arps 60 on A (ch 1)
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a]); s.cells[0][1] = Cell(colourID: "gold", buses: [.a])
        let box = SnapshotBuilder.build(from: PluginState(colours: claimColours(transposeB: 0), scenes: [s]))
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
        var st = PluginState(colours: arpColours(), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
            return s }()])
        st.receivers = [Receiver(name: "1", channel: 0, muted: true), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let e = RecordingEmitter()
        run(SnapshotBuilder.build(from: st), chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.events.isEmpty, "a muted receiver feeds its subscribers nothing")
    }

    func testReceiverChannelFilterRoutesSubscribersEndToEnd() {
        // Two cells subscribe to two receivers filtering different channels — the T6 routing, but the
        // filter now lives on the shared receiver rather than the cell.
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!] = passgateColour("gold")
        cs[colourIDs.firstIndex(of: "cyan")!] = passgateColour("cyan")
        var st = PluginState(colours: cs, scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()  // R1 = ch 1
            s.cells[0][1] = { var c = Cell(colourID: "cyan", buses: [.b]); c.inputReceiver = 1; return c }()  // R2 = ch 2
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
    // Colour it references (the head == the Colour's A face). Proves the per-cell head-treatment override.
    func testSingleSlotChainSoundsLikeTheColour() {
        let cs = arpColours()   // gold = ARP
        let gi = colourIDs.firstIndex(of: "gold")!
        let ctrl = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // Colour drives (no chain)
        let e0 = RecordingEmitter(); run(ctrl, chord([60, 64, 67]), beats: 16, into: e0)
        let head = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA)                    // an explicit head == A face
        let chained = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [head]; return c }() }
        let e1 = RecordingEmitter(); run(chained, chord([60, 64, 67]), beats: 16, into: e1)
        XCTAssertGreaterThan(e1.ons.count, 0, "the chained arp sounds")
        XCTAssertEqual(Set(e0.ons.map { $0.note }), Set(e1.ons.map { $0.note }), "a 1-slot chain renders like its Colour's A face")
        assertNothingLeftSounding(e1)
    }

    // CELL MACHINE: a bypassed HEAD slot = identity passthrough — the raw held chord passes; the arp is bypassed.
    func testBypassedHeadSlotIsPassthrough() {
        let cs = arpColours()   // gold = ARP
        let gi = colourIDs.firstIndex(of: "gold")!
        var head = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA); head.bypassed = true
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [head]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67],
                       "a bypassed head passes the raw held chord (identity), not an arp")
        assertNothingLeftSounding(e)
    }

    // MODE ROW: a NEWBORN cell has an EXPLICIT empty chain (`processors == []`) — born AUDIBLE as a passthrough.
    // The held chord flows to its emitter untreated (no PASS slot, no template), and nothing is left sounding.
    func testEmptyChainIsBornAudiblePassthrough() {
        let cs = arpColours()   // gold = ARP — proves the EMPTY chain does NOT fall back to the Colour's arp
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = []; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67],
                       "an empty chain passes the raw held chord (identity passthrough), not the Colour's arp")
        assertNothingLeftSounding(e)
    }

    // NO-MACHINE WIRE (Paul 2026-08-23): a door-connected empty chain passes its input STRAIGHT THROUGH in REALTIME
    // (via reconcileBypass), not on the grid's step clock — so a note pressed MID-column strikes immediately, where a
    // gridded hold would wait for the next column boundary. Also: no stuck notes on release.
    func testNoMachineChainIsARealtimeWire() {
        var st = PluginState(colours: arpColours(), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; c.processors = []; return c }()   // EMPTY chain, reads door R1 (OMNI)
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
    // The BUILD-workshop shape: a colour whose chain resolves to ALL-BYPASSED (an ephemeral empty colour carries a
    // bypassed-passgate placeholder), a nil-processors cell reading a door — must ALSO take the realtime wire.
    func testAllBypassedTemplateIsAlsoARealtimeWire() {
        var gold = Colour(colourID: "gold", type: .passgate)
        gold.templateChain = [{ var s = ProcessorSlot(type: .arp); s.bypassed = true; return s }()]   // all-bypassed ≡ empty
        var st = PluginState(colours: [gold] + arpColours().dropFirst(), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()   // nil processors → follows the all-bypassed template
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
        let cs = arpColours()   // gold = ARP → proves all-bypassed does NOT arp
        let gi = colourIDs.firstIndex(of: "gold")!
        func bypassedChain(_ n: Int) -> [ProcessorSlot] {
            (0..<n).map { _ in var s = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA); s.bypassed = true; return s }
        }
        for depth in [1, 8] {
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = bypassedChain(depth); return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
            XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67],
                           "a \(depth)-slot all-bypassed chain passes the raw held chord (identity passthrough)")
            assertNothingLeftSounding(e)
        }
        // Partial bypass is UNAFFECTED — one active arp among bypassed slots still drives (an arp, not the raw chord).
        let arp = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA)   // active ARP tail
        var byp = ProcessorSlot(type: cs[gi].type, params: cs[gi].paramsA); byp.bypassed = true
        let bp = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [byp, arp]; return c }() }
        let ep = RecordingEmitter(); run(bp, chord([60, 64, 67]), beats: 16, into: ep)
        XCTAssertGreaterThan(ep.ons.filter { $0.cable == 1 }.count, 3, "partial bypass unaffected — the active arp still drives")
        assertNothingLeftSounding(ep)
    }

    // CELL MACHINE stage-2 (serial execution, tick-tail slice): a 2-slot chain [open passgate → ARP] arps the
    // held chord — the intra-cell echo of the grid PASS→ARP routing (cf. testOpenPassgateParentFeedsArpChild).
    func testChainGateToArpArpsTheHeldChord() {
        let cs = arpColours()
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [true, true, true, true]
        let arp = ProcessorSlot(type: .arp)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [gate, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertTrue(notes.isSuperset(of: [60, 64, 67]), "the ARP tail arpeggiates every note the gate passed")
        assertNothingLeftSounding(e)
    }

    // MODE ROW (device round 2): the tick DRIVER need not be the TAIL. [ARP → open passgate] keeps ARPEGGIATING —
    // the arp drives the rhythm and the passgate folds onto each arp note — instead of the arp collapsing to one
    // held note (the pre-fix bug). An OPEN passgate after the arp is transparent.
    func testArpThenOpenPassgateStillArpeggiates() {
        let cs = arpColours()
        let arp = ProcessorSlot(type: .arp)
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [true, true, true, true]
        let plain = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp]; return c }() }
        let e0 = RecordingEmitter(); run(plain, chord([60, 64, 67]), beats: 16, into: e0)
        let chained = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp, gate]; return c }() }
        let e1 = RecordingEmitter(); run(chained, chord([60, 64, 67]), beats: 16, into: e1)
        XCTAssertGreaterThan(e1.ons.count, 3, "arp → open passgate arpeggiates (many onsets), not one held note")
        XCTAssertEqual(Set(e0.ons.map { $0.note }), Set(e1.ons.map { $0.note }), "an open passgate after the arp is transparent")
        assertNothingLeftSounding(e1)
    }
    // A CLOSED passgate after the arp gates every arp note → silence (the fold empties the set each tick).
    func testArpThenClosedPassgateIsSilent() {
        let cs = arpColours()
        let arp = ProcessorSlot(type: .arp)
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [false, false, false, false]
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.isEmpty, "a closed passgate after the arp gates every arp note → silence")
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
        let cs = arpColours(); let arp = ProcessorSlot(type: .arp)
        let lockRemove = avoidSlot(kind: .key, lock: true, move: false)   // LOCK to C major, REMOVE out-of-key
        let chord4 = chord([60, 61, 64, 67])                              // C · C#(out of C major) · E · G
        func classes(_ e: RecordingEmitter) -> Set<Int> { Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) % 12 }) }
        // BEFORE the arp → re-pool: the arp walks {C,E,G}; C# never enters the pool.
        let before = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [lockRemove, arp]; return c }() }
        let eB = RecordingEmitter(); run(before, chord4, beats: 16, into: eB)
        XCTAssertFalse(classes(eB).contains(1), "[LOCK→ARP]: C# (class 1) is re-pooled out — the arp never plays it")
        XCTAssertFalse(eB.ons.isEmpty, "the in-key notes still arp")
        // AFTER the arp → punch holes: the arp walks all 4, but the downstream LOCK drops C#.
        let after = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp, lockRemove]; return c }() }
        let eA = RecordingEmitter(); run(after, chord4, beats: 16, into: eA)
        XCTAssertFalse(classes(eA).contains(1), "[ARP→LOCK]: C# is dropped downstream — a hole in the line")
        XCTAssertTrue(classes(eA).contains(0) || classes(eA).contains(4), "in-key notes still emit")
        assertNothingLeftSounding(eB); assertNothingLeftSounding(eA)
    }
    func testAvoidMoveSnapsTheOutOfKeyNoteInsteadOfDropping() {
        let cs = arpColours(); let arp = ProcessorSlot(type: .arp)
        let lockMove = avoidSlot(kind: .key, lock: true, move: true)      // LOCK to C major, MOVE (snap) — nothing drops
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [lockMove, arp]; return c }() }
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
        let cs = arpColours()
        func mk(_ what: AvoidWhat) -> SnapshotBox {
            var av = ProcessorSlot(type: .avoid); av.params.avoidRefKind = .door; av.params.avoidRefIndex = 1
            av.params.avoidMode = .avoid; av.params.avoidAction = .remove; av.params.avoidWhat = what
            var st = PluginState(colours: cs, scenes: [{ var s = SceneState.empty()
                s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; c.processors = [av]; return c }()   // AVOID chain reads door 0 (ch 1)
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
        let cs = arpColours()
        var av = ProcessorSlot(type: .avoid); av.params.avoidRefKind = .door; av.params.avoidRefIndex = 1
        av.params.avoidMode = .avoid; av.params.avoidAction = .move; av.params.avoidWhat = .same
        var st = PluginState(colours: cs, scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; c.processors = [av]; return c }()   // AVOID chain reads door 0 (ch 1)
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
        let cs = arpColours()
        var st = PluginState(colours: cs, scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; c.processors = chain; return c }()
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
    // The downstream passgate gates on the PASS the user sees (diag.pass): pass 0 closed (passes[0]=false) → the
    // whole first lap is silent even though later passes are open.
    func testArpThenPassgateGatesPassZero() {
        let cs = arpColours()
        let arp = ProcessorSlot(type: .arp)
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [false, true, true, true]   // pass 0 closed
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 14, into: e)   // stay within the first lap (pass 0; cycle = 16 beats)
        XCTAssertTrue(e.ons.isEmpty, "pass 0 closed gates the arp for the whole first lap")
        assertNothingLeftSounding(e)
    }
    // HARMONIZE after the arp adds its interval voice to EACH arp note (the +7 of 64 = 71 is not a chord note).
    func testArpThenHarmonizeAddsVoiceToEachArpNote() {
        let cs = arpColours()
        let arp = ProcessorSlot(type: .arp)
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp, harm]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        let notes = Set(e.ons.map { $0.note })
        XCTAssertTrue(notes.contains(71) || notes.contains(74), "harmonize after the arp adds the +7 voice to arp notes")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2 (FULL note-set flow): [harmonize +7 → ARP] arps BOTH the source note AND the added
    // voice — the whole set flows to the tail, not one note.
    func testChainHarmonizeToArpArpsAllVoices() {
        let cs = arpColours()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let arp = ProcessorSlot(type: .arp)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [harm, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertTrue(notes.contains(60), "arps the source note")
        XCTAssertTrue(notes.contains(67), "arps the +7 harmonized voice too (full note-set flow)")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2: a BYPASSED head is a true-bypass — the tail sees only the raw source (no +7 voice).
    func testChainBypassedHeadArpsSourceOnly() {
        let cs = arpColours()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]; harm.bypassed = true
        let arp = ProcessorSlot(type: .arp)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [harm, arp]; return c }() }
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
        let cs = arpColours()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let arp = ProcessorSlot(type: .arp)
        let b = box(colours: cs) {
            $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputChannel = 2; c.processors = [harm, arp]; return c }()  // IN CH 2 = wire 1
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
        let cs = arpColours()
        var mod = ProcessorSlot(type: .mod)
        mod.params.modCC = 74; mod.params.modShape = .sine; mod.params.modRate = .r1
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        let ccs = modCC74Events(e)
        XCTAssertGreaterThan(ccs.count, 0, "the MOD cell emits CC 74 on Emit A")
        XCTAssertGreaterThan(Set(ccs.map { $0.vel }).count, 1, "the SINE shape produces VARYING values")
        XCTAssertTrue(ccs.allSatisfy { $0.vel <= 127 }, "every value is in 0…127")
        XCTAssertTrue(e.ons.isEmpty, "a MOD cell sounds NO notes")
        assertNothingLeftSounding(e)
    }
    // SPAN ROW (Paul 2026-08-19): one LFO cycle spans the whole bar (vs the per-rate CELL). A RAMP resets once per
    // cycle, so counting the big value-drops = counting cycles: ROW has far fewer than the fast per-rate CELL.
    func testModSpanRowStretchesOneCycleAcrossTheBar() {
        let cs = arpColours()
        func modBox(_ span: PatternSpan) -> SnapshotBox {
            var mod = ProcessorSlot(type: .mod)
            mod.params.modCC = 74; mod.params.modShape = .ramp; mod.params.modRate = .r1; mod.params.modSpan = span
            return box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
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
        let cs = arpColours()
        func modBox(_ span: ModStepSpan) -> SnapshotBox {
            var mod = ProcessorSlot(type: .mod)
            mod.params.modCC = 74; mod.params.modSource = .steps; mod.params.modSmooth = false; mod.params.modStepSpan = span
            mod.params.modSteps = Array(repeating: 30, count: 8) + Array(repeating: 100, count: 8)   // bar1 ≈30 · bar2 ≈100
            mod.params.modMin = 0; mod.params.modMax = 127
            return box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
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
        let cs = arpColours()
        var mod = ProcessorSlot(type: .mod)
        mod.params.modTarget = .chain; mod.params.modChainParam = .spread; mod.params.modShape = .sine
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .strum), mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e)
        XCTAssertTrue(e.events.filter { $0.status == 0xB0 }.isEmpty, "an internal-target MOD emits NO CC")
        XCTAssertFalse(e.ons.isEmpty, "the strum still plays")
        assertNothingLeftSounding(e)
    }
    // §2: the internal MOD actually MOVES the target param. A strum with base spread=0 rakes near-simultaneously; a MOD
    // → SPREAD pinned at max (MIN=MAX=127 → constant offset 1.0) forces spread=1, so the onsets fan out much wider.
    func testModInternalTargetModulatesSpread() {
        let cs = arpColours()
        func onsetSpan(withMod: Bool) -> Int {
            var strum = ProcessorSlot(type: .strum); strum.params.spread = 0
            var chain = [strum]
            if withMod {
                var mod = ProcessorSlot(type: .mod)
                mod.params.modTarget = .chain; mod.params.modChainParam = .spread
                mod.params.modMin = 127; mod.params.modMax = 127   // constant → offset = 1.0 → spread pinned to 1
                chain.append(mod)
            }
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = chain; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67, 72]), beats: 8, into: e)
            let ons = e.ons.map { Int($0.sample) }
            return (ons.max() ?? 0) - (ons.min() ?? 0)
        }
        XCTAssertGreaterThan(onsetSpan(withMod: true), onsetSpan(withMod: false), "MOD → SPREAD at max fans the strum onsets much wider")
    }
    /// [ARP → MOD]: MOD is note-transparent — the arp still plays AND MOD emits its CC.
    func testArpThenModKeepsArpNotesAndEmitsCC() {
        let cs = arpColours()
        let arp = ProcessorSlot(type: .arp)
        var mod = ProcessorSlot(type: .mod); mod.params.modCC = 71; mod.params.modRate = .r1
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp, mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "the ARP still plays (MOD is note-transparent as a post-driver stage)")
        XCTAssertGreaterThan(e.events.filter { $0.status == 0xB0 && $0.note == 71 }.count, 0, "AND MOD emits its CC")
        assertNothingLeftSounding(e)
    }
    /// [MOD → ARP]: MOD passes the chord through (composeChainSet identity) so the arp arps it — AND MOD emits CC.
    func testModThenArpArpsAndEmitsCC() {
        let cs = arpColours()
        var mod = ProcessorSlot(type: .mod); mod.params.modCC = 74; mod.params.modRate = .r1
        let arp = ProcessorSlot(type: .arp)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThanOrEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).count, 2, "the ARP arps the chord through the transparent MOD")
        XCTAssertGreaterThan(modCC74Events(e).count, 0, "MOD emits its CC")
        assertNothingLeftSounding(e)
    }
    /// The LEAVE-DISPOSITION: RESET sends an extra CC 0 each time the playhead exits the MOD's column; LEAVE does not.
    /// Same shape/timing in both runs, so the difference in CC-0 count is exactly the resets.
    func testModResetDispositionEmitsExtraZeroOnLeave() {
        func zeros(reset: Bool) -> Int {
            let cs = arpColours()
            var mod = ProcessorSlot(type: .mod)
            mod.params.modCC = 74; mod.params.modShape = .sine; mod.params.modReset = reset; mod.params.modRate = .r1
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
            return modCC74Events(e).filter { $0.vel == 0 }.count
        }
        XCTAssertGreaterThan(zeros(reset: true), zeros(reset: false), "RESET sends an extra CC 0 on each column exit; LEAVE holds the last value")
    }
    /// FOLLOW COUNT: the CC tracks the held-note count — more notes → a higher value.
    func testModFollowCountTracksHeldNotes() {
        func maxCC(_ notes: [UInt8]) -> Int {
            let cs = arpColours()
            var mod = ProcessorSlot(type: .mod); mod.params.modSource = .follow; mod.params.modFollow = .count; mod.params.modCC = 74
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
            let e = RecordingEmitter(); run(b, chord(notes), beats: 8, into: e)
            return modCC74Events(e).map { Int($0.vel) }.max() ?? 0
        }
        XCTAssertGreaterThan(maxCC([48, 50, 52, 55, 57, 60]), maxCC([60]), "FOLLOW COUNT rises with the held-note count")
    }
    /// STEPS: a stepped pattern emits its authored values (the high step 127 comes only from the pattern, not the reset).
    func testModStepsEmitsThePattern() {
        let cs = arpColours()
        var mod = ProcessorSlot(type: .mod); mod.params.modSource = .steps; mod.params.modSmooth = false
        mod.params.modSteps = [0, 127, 0, 127, 0, 127, 0, 127]; mod.params.modRate = .r1; mod.params.modCC = 74
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(modCC74Events(e).map { Int($0.vel) }).contains(127), "the STEP pattern emits its high step")
    }
    /// STRIKE: on column entry an AR envelope rises toward MAX then falls back — the CC spans a range.
    func testModStrikeEnvelopeRisesAndFalls() {
        let cs = arpColours()
        var mod = ProcessorSlot(type: .mod); mod.params.modSource = .strike; mod.params.modAttack = 0.1; mod.params.modRelease = 0.3
        mod.params.modCC = 74; mod.params.modMin = 0; mod.params.modMax = 127
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        let vals = modCC74Events(e).map { Int($0.vel) }
        XCTAssertGreaterThan(vals.max() ?? 0, 60, "the STRIKE envelope rises well above MIN")
        XCTAssertGreaterThan((vals.max() ?? 0) - (vals.min() ?? 0), 40, "…and spans a range (rise + fall)")
    }
    /// EXTERN: reads an incoming CC (the mod wheel, CC1) and re-emits it on the TARGET (CC74). Driven directly so the
    /// controller store can be fed (the `run` helper owns its router).
    func testModExternRetransmitsIncomingCC() {
        let cs = arpColours()
        var mod = ProcessorSlot(type: .mod); mod.params.modSource = .extern; mod.params.modExternCC = 1; mod.params.modCC = 74; mod.params.modMin = 0; mod.params.modMax = 127
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
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
            box(colours: arpColours()) {
                var c = Cell(colourID: "gold", buses: [.a])
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
            box(colours: arpColours()) {
                var c = Cell(colourID: "gold", buses: [.a])
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
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!].type = .glide       // gold = a single-slot GLIDE
        let b = box(colours: cs) {
            for c in 0..<8 {                                       // glide row 0 spans every column (crosses every boundary)
                $0.cells[c][0] = { var x = Cell(colourID: "gold", buses: [.a]); var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glideRange = 12; g.params.glidePriority = .last; g.params.glideTime = 0.1; x.processors = [g]; return x }()
                $0.cells[c][1] = { var x = Cell(colourID: "orange", buses: [.b]); x.processors = []; return x }()   // a LEGATO drone (empty chain = born-audible passthrough) — keeps the hold-continuity path busy each boundary
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
        let cs = arpColours()
        var g = ProcessorSlot(type: .glide); g.params.glideRange = 2; g.params.glidePriority = .last; g.params.glideReanchor = true; g.params.glideTime = 0
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [g]; return c }() }
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
        let cs = arpColours()
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glidePriority = .last; g.params.glideTime = 0
        let b = box(colours: cs) { $0.masterKey = 5; $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [g]; return c }() }
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
        let cs = arpColours()
        let g: ProcessorSlot = { var s = ProcessorSlot(type: .glide); s.params.glideMode = .bend; s.params.glidePriority = .last; s.params.glideTime = 0; return s }()
        func mk(_ en: [Bool]) -> SnapshotBox { box(colours: cs, busEnabled: en) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [g]; return c }() } }
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
        let cs = arpColours()
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glideRange = 12; g.params.glidePriority = .last; g.params.glideTime = 0
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [g]; return c }() }
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
        let cs = arpColours()
        var g = ProcessorSlot(type: .glide); g.params.glideRange = 2; g.params.glideTime = 0
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [g]; return c }() }
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
        let cs = arpColours()
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .synth; g.params.glidePriority = .last; g.params.glideTime = 0.5
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [g]; return c }() }
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
        let cs = arpColours()
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .step; g.params.glidePriority = .last; g.params.glideTime = 0.4
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [g]; return c }() }
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
        let cs = arpColours()
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_8
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .synth; g.params.glideTime = 0.3
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp, g]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 }, "SYNTH driven → CC65 portamento ON")
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 5 }, "SYNTH driven → CC5 time")
        XCTAssertFalse(e.events.contains { $0.status == 0xE0 }, "SYNTH driven → no pitch-bend")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 1, "the driver's walk emits legato note-ons")
        assertNothingLeftSounding(e)
    }
    func testArpThenGlideStepDrivenZippersNoBend() {
        // [ARP→GLIDE STEP] driven: each driver transition zippers chromatically (intermediate short notes), no bend.
        let cs = arpColours()
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_4
        var g = ProcessorSlot(type: .glide); g.params.glideMode = .step; g.params.glideTime = 0.2
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [arp, g]; return c }() }
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
            let cs = arpColours()
            var mod = ProcessorSlot(type: .mod); mod.params.modSource = .shape; mod.params.modShape = .ramp
            mod.params.modMin = 0; mod.params.modMax = 100; mod.params.modCC = cc
            return box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
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
            let cs = arpColours()
            var mod = ProcessorSlot(type: .mod); mod.params.modShape = .sampleHold; mod.params.modCC = 74; mod.params.modRate = .r1
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [mod]; return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
            return e.events.filter { $0.status == 0xB0 }
        }
        XCTAssertEqual(ccStream(), ccStream(), "the MOD CC stream is replay-safe (same beats → identical)")
    }

    // MODE ROW: the driver-not-tail fold also covers RATCHET. [ratchet → closed passgate] gates every re-strike →
    // silence; [ratchet → open passgate] re-strikes as a plain ratchet (the gate is transparent).
    // COIN — SHAPING THE DICE (Paul 2026-08-26): SIZE WEIGHTS change the audible burst length (size-8 bursts more notes
    // than size-2); QUOTA caps the fires per row; replay-exact. Proves the engine reads the new fields end-to-end.
    func testRatchetCoinSizeWeightsAndQuota() {
        func onCount(weights: [Int]? = nil, quota: Int? = nil) -> Int {
            var c = Colour(colourID: "gold", type: .ratchet)
            c.paramsA.rtcMode = .coin; c.paramsA.rtcChance = 1.0     // every step bursts
            if let weights { c.paramsA.rtcSizeWeights = weights }
            if let quota { c.paramsA.rtcQuota = quota }
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            // across the ROW so consecutive columns (= consecutive coin STEPS) fire — exercises quota-per-row
            let b = box(colours: cs) { s in for col in 0..<8 { s.cells[col][0] = Cell(colourID: "gold", buses: [.a]) } }
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
            var c = Colour(colourID: "gold", type: .riff)
            c.paramsA.riffRanks = [1, 2, 3, 1, 2, 3, 1, 2]; c.paramsA.riffSteps = 8; c.paramsA.riffRate = .r1_8; c.paramsA.riffWrap = .fold
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
    // SPAN RE-ANCHOR (Paul 2026-08-27, the universal re-sync model — riff is the first card): a 3-step stencil [1,2,3]
    // FREE-runs and cycles all three chord notes across the row; SPAN=1 re-syncs the stencil to step 0 EVERY column, so
    // only step 0 (rank 1 = the lowest note) ever plays. One step per column (riffRate == stepRate == 1/8 = 0.5 beat).
    func testRiffSpanReAnchorsTheStencil() {
        func played(spanN: Int?) -> [Int] {
            var c = Colour(colourID: "gold", type: .riff)
            c.paramsA.riffRanks = [1, 2, 3]; c.paramsA.riffSteps = 3; c.paramsA.riffRate = .r1_8; c.paramsA.riffWrap = .fold
            c.paramsA.riffSpanN = spanN
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { s in
                s.stepRate = .r1_8                                       // 0.5-beat columns == the riff rate → one step per column
                for col in 0..<8 { s.cells[col][0] = Cell(colourID: "gold", buses: [.a]) }   // the whole row → the stencil plays continuously
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
        var c = Colour(colourID: "gold", type: .riff)
        c.paramsA.riffRanks = [1, 1, 1, 1, 1, 1, 1, 1]; c.paramsA.riffSteps = 8; c.paramsA.riffRate = .r1_8; c.paramsA.riffWrap = .fold
        let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64]), beats: 2, into: e)
        assertNothingLeftSounding(e)
        let notes = e.ons.filter { $0.cable == 1 }.map { Int($0.note) }
        XCTAssertFalse(notes.isEmpty, "the riff sounds")
        XCTAssertTrue(notes.allSatisfy { $0 == 60 }, "every rank-1 tick plays the LOWEST held note (C=60), never E(64) — got \(notes)")
    }
    // RIFF STAGE 2 (Paul 2026-08-26): POLY strikes a SET of ranks per step (a chord that follows the held chord).
    func testRiffPolyStrikesTheRankSet() {
        var c = Colour(colourID: "gold", type: .riff)
        c.paramsA.riffPoly = true; c.paramsA.riffSteps = 4; c.paramsA.riffRate = .r1_8; c.paramsA.riffWrap = .fold
        c.paramsA.riffMask = [5, 5, 5, 5]   // bits 0 and 2 set ⇒ ranks 1 and 3 together
        let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e); assertNothingLeftSounding(e)
        let notes = Set(e.ons.filter { $0.cable == 1 }.map { Int($0.note) })
        XCTAssertTrue(notes.contains(60) && notes.contains(67), "a POLY step strikes rank 1 (60) AND rank 3 (67) together")
        XCTAssertFalse(notes.contains(64), "rank 2 (64) is not in the mask → not struck")
    }
    // §5 TIE: a tie step suppresses its own attack; the previous note sustains → fewer note-ons than the untied stencil.
    func testRiffTieSuppressesAttack() {
        func onCount(tie: Bool) -> Int {
            var c = Colour(colourID: "gold", type: .riff)
            c.paramsA.riffSteps = 2; c.paramsA.riffRate = .r1_4; c.paramsA.riffWrap = .fold; c.paramsA.riffRanks = [1, 2]
            if tie { c.paramsA.riffTie = [false, true] }
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.count
        }
        XCTAssertLessThan(onCount(tie: true), onCount(tie: false), "a TIE step suppresses its own attack — fewer note-ons")
    }
    // §5 SLIDE: a slide step arms the synth portamento (CC65=127); the next non-slide step clears it (CC65=0).
    func testRiffSlideArmsAndClearsPortamento() {
        var c = Colour(colourID: "gold", type: .riff)
        c.paramsA.riffSteps = 2; c.paramsA.riffRate = .r1_4; c.paramsA.riffWrap = .fold; c.paramsA.riffRanks = [1, 2]
        c.paramsA.riffSlide = [true, false]
        let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter(); run(b, chord([60, 64]), beats: 2, into: e); assertNothingLeftSounding(e)
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 && $0.vel == 127 }, "SLIDE arms portamento CC65=127")
        XCTAssertTrue(e.events.contains { $0.status == 0xB0 && $0.note == 65 && $0.vel == 0 }, "the non-slide step after clears CC65=0")
    }
    // Variable length (Paul 2026-08-26): a stencil longer than 16 steps is not truncated — step 20 of a 24-step stencil
    // still fires (the old min(16,...) cap would fold it to step 4). RIFF across the whole row so it ticks continuously.
    func testRiffVariableLengthBeyond16() {
        var c = Colour(colourID: "gold", type: .riff)
        c.paramsA.riffSteps = 24; c.paramsA.riffRate = .r1_16; c.paramsA.riffWrap = .fold
        var ranks = [Int](repeating: 0, count: 24); ranks[20] = 1   // ONLY step 20 fires
        c.paramsA.riffRanks = ranks
        let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
        let b = box(colours: cs) { for col in 0..<8 { $0.cells[col][0] = Cell(colourID: "gold", buses: [.a]) } }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 8, into: e); assertNothingLeftSounding(e)
        XCTAssertFalse(e.ons.filter { $0.cable == 1 }.isEmpty, "step 20 of a 24-step stencil fires — not capped at 16")
    }
    // EUCLID LINES (§10): up to 8 lines from ONE chord — one ALL line = the single euclid (byte-identical); a second line
    // adds its own pulses (polyrhythm); a NOTE-target line strikes only that pool rank. Nothing left sounding.
    func testEuclidLinesPolyrhythmAndNoteTargets() {
        func run4(_ lines: [EuclidLine]?, _ measure: (RecordingEmitter) -> Void) {
            var c = Colour(colourID: "gold", type: .euclid); c.paramsA.euclidPulses = 4; c.paramsA.euclidSteps = 8
            if let lines { c.paramsA.euclidLines = lines }
            let b = box(colours: colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
    func testEuclidLinesPerLinePickAndDie() {
        // EUCLID LINES v1b (Paul 2026-08-26): each ALL-target line has its OWN pick; a per-line die salts CYCLE/RANDOM apart.
        func notesOf(_ line: EuclidLine) -> [Int] {
            var c = Colour(colourID: "gold", type: .euclid); c.paramsA.euclidLines = [line]
            let b = box(colours: colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e)
            return e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map { Int($0.note) }
        }
        XCTAssertEqual(Set(notesOf(EuclidLine(target: 0, pulses: 4, steps: 8, pick: .low))), [60], "per-line PICK=LOW strikes only the low note")
        XCTAssertEqual(Set(notesOf(EuclidLine(target: 0, pulses: 4, steps: 8, pick: .high))), [67], "per-line PICK=HIGH strikes only the high note")
        let dieA = notesOf(EuclidLine(target: 0, pulses: 5, steps: 8, pick: .random, die: 0))
        let dieB = notesOf(EuclidLine(target: 0, pulses: 5, steps: 8, pick: .random, die: 5))
        XCTAssertNotEqual(dieA, dieB, "a different per-line DIE reseeds the RANDOM scatter → a different note sequence")
    }
    // ARP EUCLID MASK (SPEC-arp-euclid-mask): K=N is byte-identical (mask OFF); a 4-of-8 mask drops steps to the
    // Bjorklund hits; TIE keeps the same ONSET count as REST (non-hits sustain, they don't add notes) but lengthens
    // them; WAIT re-spaces the walk vs MARCH. Pure per-step Bjorklund — deterministic, off-device provable.
    func testArpEuclidMaskGatesRestsTiesAndWalk() {
        func run4(_ setup: (inout ColourParams) -> Void) -> (count: Int, notes: [Int], span: Int) {
            var c = Colour(colourID: "gold", type: .arp)
            c.paramsA.pattern = .up; c.paramsA.rate = .r1_16; c.paramsA.octaves = 1; c.paramsA.gate = 0.5
            setup(&c.paramsA)
            let cs = colourIDs.map { $0 == "gold" ? c : Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 4, into: e); assertNothingLeftSounding(e)
            let ons = e.ons.filter { $0.cable == 1 }
            var firstDur = 0
            if let on = ons.first, let off = e.offs.first(where: { $0.cable == 1 && $0.note == on.note && $0.sample >= on.sample }) {
                firstDur = Int(off.sample - on.sample)
            }
            return (ons.count, ons.map { Int($0.note) }, firstDur)
        }
        let full = run4 { _ in }                                              // no mask
        let explicit = run4 { $0.arpMaskN = 8; $0.arpMaskK = 8 }              // K = N ⇒ OFF
        let rest = run4 { $0.arpMaskN = 8; $0.arpMaskK = 4 }                  // 4-of-8, MARCH, REST
        let tie  = run4 { $0.arpMaskN = 8; $0.arpMaskK = 4; $0.arpMaskGap = .tie }
        let wait = run4 { $0.arpMaskN = 8; $0.arpMaskK = 4; $0.arpMaskWalk = .wait }
        XCTAssertEqual(explicit.count, full.count, "K = N is byte-identical to no mask (mask OFF)")
        XCTAssertEqual(explicit.notes, full.notes, "K = N leaves the walk untouched")
        XCTAssertLessThan(rest.count, full.count, "a 4-of-8 mask drops steps to the euclidean hits")
        XCTAssertGreaterThan(rest.count, 0, "the mask still sounds its hits")
        XCTAssertEqual(tie.count, rest.count, "TIE keeps the same ONSET count as REST — non-hits sustain, not new notes")
        XCTAssertGreaterThan(tie.span, rest.span, "a TIE note is LONGER than a rest-gated one (it holds through the gap)")
        XCTAssertNotEqual(wait.notes, rest.notes, "WAIT re-spaces the walk (advances only on hits) vs MARCH (holes punched)")
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
            let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = withTap ? [arp, tap] : [arp]; return c }() }
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
        let cs = colourIDs.map { Colour(colourID: $0, type: .harmonize) }
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [harm, tap]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 2, into: e); assertNothingLeftSounding(e)
        XCTAssertFalse(e.ons.filter { $0.cable == 2 }.isEmpty, "a HOLD-chain TAP mirrors to wire B")
        XCTAssertTrue(e.ons.contains { $0.cable == 2 && $0.note == 67 }, "the harmonized set (incl. 60+7=67) reaches the tap wire")
        let noTap = { () -> RecordingEmitter in
            let b2 = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [harm]; return c }() }
            let e2 = RecordingEmitter(); run(b2, chord([60, 64, 67]), beats: 2, into: e2); return e2 }()
        XCTAssertTrue(noTap.ons.filter { $0.cable == 2 }.isEmpty, "without TAP, nothing on wire B")
    }
    func testRatchetThenClosedPassgateIsSilent() {
        let cs = arpColours()
        let rat = ProcessorSlot(type: .ratchet)
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [false, false, false, false]
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [rat, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.isEmpty, "a closed passgate after the ratchet gates every re-strike")
        assertNothingLeftSounding(e)
    }
    func testRatchetThenOpenPassgateStillRatchets() {
        let cs = arpColours()
        let rat = ProcessorSlot(type: .ratchet)
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [true, true, true, true]
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [rat, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 64, 67]), "an open passgate after the ratchet is transparent")
        XCTAssertGreaterThan(e.ons.count, 3, "the ratchet re-strikes (more than one hit)")
        assertNothingLeftSounding(e)
    }
    // …and STRUM as a non-tail driver: a closed passgate after the strum silences every strummed note.
    func testStrumThenClosedPassgateIsSilent() {
        let cs = arpColours()
        let strum = ProcessorSlot(type: .strum)
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [false, false, false, false]
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [strum, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.isEmpty, "a closed passgate after the strum gates every strummed note")
        assertNothingLeftSounding(e)
    }
    // §cell-edit F CHOP render path: a cell whose every slice is MUTED emits nothing (the render reads muteMask).
    func testChopMuteMaskSilencesEveryNote() {
        let cs = arpColours()
        let b = box(colours: cs) { $0.cells[0][0] = {
            var c = Cell(colourID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]
            c.chop = Chop(mainMask: 0xFF, altMask: 0, muteMask: 0xFF, altDest: [])   // every slice muted (overrides main)
            return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.isEmpty, "chop muteMask over every slice → the whole column is silent")
        assertNothingLeftSounding(e)
    }
    // §cell-edit F CHOP alt row: every slice OFF main, ON alt, routed to altDest [.c] → notes emit on Emit C
    // (cable 3), NOT on the cell's own Emit A (cable 1). (The bottom-row ALT-destination routing.)
    func testChopAltRoutesToAltDestination() {
        let cs = arpColours()
        let b = box(colours: cs) { $0.cells[0][0] = {
            var c = Cell(colourID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]
            c.chop = Chop(mainMask: 0, altMask: 0xFF, muteMask: 0, altDest: [.c])   // main OFF, alt ON → alt dest C only
            return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 3 }.count, 0, "alt slices emit on the ALT destination (Emit C)")
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "main is OFF for every slice → nothing on Emit A")
        assertNothingLeftSounding(e)
    }
    // §cell-edit F CHOP on a HOLD (passthrough/identity) cell — main/mute/alt must apply, same as a tick cell.
    func testChopAppliesToHoldCell() {
        let cs = arpColours()
        let b = box(colours: cs) { $0.cells[0][0] = {
            var c = Cell(colourID: "gold", buses: [.a]); c.processors = []   // EMPTY chain = identity HOLD
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
        let cs = arpColours()
        let b = box(colours: cs) { $0.cells[0][0] = {
            var c = Cell(colourID: "gold", buses: [.a])
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
        let b = box(colours: echoColours(div: 2, repeats: 3, feedDelay: 0.7, decay: 0.6)) { $0.cells[0][0] = {
            var c = Cell(colourID: "gold", buses: [.a])
            c.chop = Chop(mainMask: 0, altMask: 0xFF, muteMask: 0, altDest: [.c])
            return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 8, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 3 }.count, 0, "the classic echo (dry + tail) routes to the ALT destination")
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "main OFF → the classic echo does not sound on Emit A")
        assertNothingLeftSounding(e)
    }
    // A MUTED slice silences the note AND its echoes — the tail resolves to mask 0, so no repeats are scheduled.
    func testChopMuteSilencesTheEchoesToo() {
        let cs = arpColours()
        let b = box(colours: cs) { $0.cells[0][0] = {
            var c = Cell(colourID: "gold", buses: [.a])
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
            default: break                                      // passgate: default passMask 0b1111 = open
            }
            return s
        }
        for mid in [ProcessorType.passgate, .chance, .harmonize, .echo] {
            let b = box(colours: arpColours()) { $0.cells[0][0] = {
                var c = Cell(colourID: "gold", buses: [.a])
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
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // rung row 0 → Emit A (cable 1)
            s.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // rung row 1 → Emit B (cable 2)
            s.activeRow = active
            var st = PluginState(colours: arpColours(), scenes: [s]); st.ladderMode = ladder
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
        let cs = arpColours()
        let b = box(colours: cs) {
            $0.stepRate = .r1_8   // fast columns (0.5 beat each) so the playhead sweeps to column 5 within the run
            $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }()
            $0.cells[5][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }()   // col 5 → index 5*16 = 80 (≥64: guards the strike-feed cap regression, Paul 2026-08-30)
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
        let cs = arpColours()
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }() }
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
        let cs = arpColours()
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }() }
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

    // The per-cell note ring CAPS at 6 and the wrap-index read returns valid pitches (Paul 2026-08-19). A cell emitting
    // many notes before a drain must return exactly 6 (the ring size), all real chord pitches (proving the modular read).
    func testCellNoteRingCapsAtSixWithValidWrap() {
        let cs = arpColours()
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }() }
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
        let cs = arpColours()
        // an EMPTY chain = born-audible PASSTHROUGH hold → the chord sustains (deterministic sounding voices)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = []; return c }() }
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
        let held = router.currentCellSounding()
        XCTAssertEqual(held.lo & 1, 1, "cell (0,0) is holding a note → its sounding bit is set")
        XCTAssertEqual(held.lo >> 1, 0, "no other cell sounds"); XCTAssertEqual(held.hi, 0)
        router.process(box: b, pool: chord([60, 64, 67]), playing: false, beatPos: beat, tempo: tempo,   // stop → release
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        router.snapshotCellSounding()
        let rel = router.currentCellSounding(); XCTAssertEqual(rel.lo, 0, "after release the gate clears"); XCTAssertEqual(rel.hi, 0)
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
        var st = PluginState(colours: claimColours(transposeB: 5), scenes: [{ var s = SceneState.empty()
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // index 0 — MUTED claimant → only a silent ghost (holds 60)
            s.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // index 1 — audible (holds 65, not the claimed pitch)
            return s }()])
        st.claimEmitter = 0
        st.busEnabled = [false, true, true, true]                 // A muted → the claimant makes no sound
        let router = runDirect(SnapshotBuilder.build(from: st), chord([60]))
        router.snapshotCellSounding()
        let mask = router.currentCellSounding()
        XCTAssertEqual(mask.lo & 1, 0, "the muted claimant's SILENT ghost must NOT light its comet (cell 0)")
        XCTAssertEqual((mask.lo >> 1) & 1, 1, "…while the audible non-claimant DOES light (cell 1) — the scene is live")
    }

    // SEAL comet — a MUTED (occupied) cell records NEITHER a strike NOR a sounding bit (tap-to-mute = dark comet).
    // Distinct from an EMPTY cell: this one has a colour + buses, but `cell.muted` short-circuits the emit loop
    // BEFORE currentCellIndex is set. (The same cell unmuted DOES fire — testCellStrikeFeedRecordsFiringCell.)
    func testMutedCellRecordsNoStrikeOrSoundingBit() {
        let b = box(colours: arpColours()) {
            $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = []; c.muted = true; return c }()
        }
        let router = runDirect(b, chord([60, 64, 67]))
        XCTAssertEqual(router.drainCellStrikes()[0], 0, "a muted cell records no strike")
        router.snapshotCellSounding()
        let ms = router.currentCellSounding(); XCTAssertEqual(ms.lo, 0, "a muted cell lights no comet"); XCTAssertEqual(ms.hi, 0)
    }

    // SEAL comet — a FAN-OUT cell (emitting to ≥2 buses → ≥2 voices sharing one cellIndex) reports EXACTLY ONE
    // sounding bit and ONE strike slot, not one per bus. Guards the per-CELL (not per-voice/per-bus) keying.
    func testFanOutCellReportsSingleSoundingBitAndOneStrike() {
        let b = box(colours: arpColours()) {
            $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a, .b]); c.processors = []; return c }()
        }
        let router = runDirect(b, chord([60, 64, 67]))
        let strikes = router.drainCellStrikes()
        XCTAssertGreaterThan(strikes[0], 0, "the fan-out cell records a strike at its index")
        XCTAssertEqual(strikes.filter { $0 > 0 }.count, 1, "recorded ONCE, not per bus")
        router.snapshotCellSounding()
        let fm = router.currentCellSounding()
        XCTAssertEqual(fm.lo.nonzeroBitCount + fm.hi.nonzeroBitCount, 1, "exactly one sounding bit despite the fan-out")
        XCTAssertEqual(fm.lo & 1, 1, "…at the cell's index")
    }

    // CELL MACHINE stage-2: a RATCHET tail re-strikes the HEAD stage's WHOLE output set each repeat.
    func testChainHarmonizeToRatchetRestrikesAllVoices() {
        let cs = arpColours()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let rat = ProcessorSlot(type: .ratchet)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [harm, rat]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 67]),
                      "ratchet re-strikes BOTH the source and the +7 harmonized voice")
        assertNothingLeftSounding(e)
    }

    func testChainGateToRatchetRestrikesChord() {
        let cs = arpColours()
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [true, true, true, true]
        let rat = ProcessorSlot(type: .ratchet)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [gate, rat]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 64, 67]),
                      "ratchet re-strikes the whole gated chord")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2 (N>2 slots): [gate → harmonize +7 → ARP] composes — the arp tail arps the harmonized
    // set that flowed through the open gate.
    func testChainThreeSlotGateHarmonizeArp() {
        let cs = arpColours()
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [true, true, true, true]
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let arp = ProcessorSlot(type: .arp)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [gate, harm, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 67]),
                      "3-slot chain: the arp tail arps both the source and the +7 voice, passed through the gate")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2: a CLOSED gate mid-chain empties the set — the tail falls silent.
    func testChainClosedGateSilencesTail() {
        let cs = arpColours()
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [false, false, false, false]
        let arp = ProcessorSlot(type: .arp)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [gate, arp]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "a closed gate head → the arp tail is silent")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2 (HOLD tail): a chain ending in a hold stage emits at column boundaries. [gate →
    // harmonize +7] HOLDS the harmonized chord (source + the +7 voice) rather than arping it.
    func testChainHoldTailGateToHarmonize() {
        let cs = arpColours()
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [true, true, true, true]
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [gate, harm]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 67]),
                      "hold-tail chain holds the harmonized chord (source + the +7 voice)")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2: a CLOSED gate as the hold TAIL yields nothing.
    func testChainHoldTailClosedGateSilent() {
        let cs = arpColours()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [false, false, false, false]
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [harm, gate]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "a closed gate TAIL → the chain is silent")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-2 (STRUM tail): [harmonize +7 → STRUM] staggers the WHOLE harmonized set each column.
    func testChainHarmonizeToStrumStrumsAllVoices() {
        let cs = arpColours()
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [7, 0, 0]
        let strum = ProcessorSlot(type: .strum)
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [harm, strum]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 67]),
                      "strum tail staggers both the source and the +7 harmonized voice")
        assertNothingLeftSounding(e)
    }

    // CELL MACHINE stage-3: a colour's shared TEMPLATE chain sounds for a FOLLOWING cell (no per-cell override).
    func testTemplateChainSoundsForFollowingCell() {
        var cs = arpColours()
        let gi = colourIDs.firstIndex(of: "gold")!
        var gate = ProcessorSlot(type: .passgate); gate.params.passes = [true, true, true, true]
        cs[gi].templateChain = [gate, ProcessorSlot(type: .arp)]                       // template = gate → arp
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // FOLLOWING (no override)
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }).isSuperset(of: [60, 64, 67]),
                      "a following cell sounds the colour TEMPLATE chain (arps the chord)")
        assertNothingLeftSounding(e)
    }

    // A per-cell OVERRIDE diverges from the template: template = arp, but this cell overrides with a bypassed
    // passgate (identity) → holds the raw chord instead of arping.
    func testCellOverrideDivergesFromTemplate() {
        var cs = arpColours()
        let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].templateChain = [ProcessorSlot(type: .arp)]
        var idle = ProcessorSlot(type: .passgate); idle.params.passes = [true, true, true, true]
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [idle]; return c }() }
        let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 1 }.map { $0.note }), [60, 64, 67],
                       "the OVERRIDE (open passgate = identity hold) ignores the arp TEMPLATE")
        assertNothingLeftSounding(e)
    }

    func testInputChannelFilterRoutesBySourceChannel() {
        // Device T6 (filter-in), previously unit-untested at the Router level: two MIDI-IN cells, one
        // filtering IN CH 1 → Emit A, the other IN CH 2 → Emit B. A note on wire ch 0 sounds only through
        // A; a note on wire ch 1 only through B. No origin channel survives — each is re-stamped on its bus.
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!] = passgateColour("gold")
        cs[colourIDs.firstIndex(of: "cyan")!] = passgateColour("cyan")
        let b = box(colours: cs) {
            $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputChannel = 1; return c }()  // IN CH 1 = wire 0
            $0.cells[0][1] = { var c = Cell(colourID: "cyan", buses: [.b]); c.inputChannel = 2; return c }()  // IN CH 2 = wire 1
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

    func testPassgateGatesByPassInThePlayingPath() {
        // A PASSGATE at MIDI IN, open every 2nd pass. Over two full cycles column 0 is entered on pass 0
        // (open → the chord sounds) and pass 1 (closed → silent): the held chord sounds exactly ONCE.
        var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].type = .passgate; cs[gi].paramsA.passes = [true, false, true, false]; cs[gi].paramsA.gate = 1.0
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold") }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 20, into: e)   // through pass 0 (open) + pass 1 (closed), before pass 2
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 0 }.map { $0.note }), [60, 64, 67])
        XCTAssertEqual(e.ons.filter { $0.cable == 0 }.count, 3, "sounds on pass 0 only — closed pass 1 stays silent")
        assertNothingLeftSounding(e)
    }

    // MARK: - COLUMN-SUBSET LAP (§5b) — the held set warps which column is effective

    func testLapStutterLocksPlaybackToTheHeldColumn() {
        // Hold column 2 only (k=1): column 2 plays CONTINUOUSLY (every step), column 5 never becomes
        // effective — vs. the normal 1-step-in-8 for each.
        let b = box(colours: arpColours()) {
            $0.cells[2][0] = Cell(colourID: "gold")                  // column 2 → A
            $0.cells[5][0] = Cell(colourID: "azure", buses: [.b])    // column 5 → B
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e, laneMask: 1 << 2)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 8, "column 2 plays continuously under the lap")
        XCTAssertTrue(e.ons.filter { $0.cable == 2 }.isEmpty, "column 5 never becomes effective")
        assertNothingLeftSounding(e)
    }

    func testLapAlternatesBetweenTwoHeldColumns() {
        // Hold columns 1 and 3 (k=2): both play, on alternating steps.
        let b = box(colours: arpColours()) {
            $0.cells[1][0] = Cell(colourID: "gold")                  // column 1 → A
            $0.cells[3][0] = Cell(colourID: "azure", buses: [.b])    // column 3 → B
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e, laneMask: (1 << 1) | (1 << 3))
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "column 1 plays on its lap steps")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "column 3 plays on its lap steps")
        assertNothingLeftSounding(e)
    }

    func testLapPolymeterRotationLeavesNothingStuckThroughRelease() {
        // Hold three columns (k=3 polymeter) over a held chord, then release + stop (run() does this).
        let b = box(colours: arpColours()) { for c in [1, 3, 5] { $0.cells[c][0] = Cell(colourID: "gold") } }
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
        var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].type = .harmonize; cs[gi].paramsA.harmIntervals = [4, 7, 0]
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold") }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 0 }.map { $0.note }), [60, 64, 67],
                       "playing HARMONIZE expands the held note to its voices")
        assertNothingLeftSounding(e)
    }

    func testStopEdgeFlushesEverySoundingVoice() {
        // Even with a slow ARP and a stop mid-window, the transport edge must leave nothing sounding.
        let b = box(colours: arpColours()) {
            $0.cells[0][0] = Cell(colourID: "gold")
            $0.cells[2][0] = Cell(colourID: "cyan", buses: [.b])
        }
        let e = RecordingEmitter()
        run(b, chord([60, 63, 67, 70]), beats: 20, into: e)   // 2+ columns worth, then stop
        XCTAssertGreaterThan(e.ons.count, 0)
        assertNothingLeftSounding(e)
    }

    // MARK: - PREVIEW / cell audition (Phase 2, Increment 1: ARP solo)

    @discardableResult
    private func runPreview(_ box: SnapshotBox, _ pool: NotePool,
                            _ preview: (active: Bool, colourIndex: Int, filter: Int, busMask: UInt8, inputRow: Int),
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
    private func boxWithBusEnabled(_ cs: [Colour], _ enabled: [Bool], _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(colours: cs, scenes: [s]); st.busEnabled = enabled
        return SnapshotBuilder.build(from: st)
    }

    // SOLO: a real bus-A ARP cell would sound on cable 1; with PREVIEW on bus B, ONLY the virtual cell
    // emits (cable 2 + All), and the real cell is silenced.
    func testPreviewSolosOnlyTheVirtualCell() {
        let gold = colourIDs.firstIndex(of: "gold")!
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: e)   // preview → bus B
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "preview emits on bus B (cable 2)")
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "the real bus-A cell is SOLOED OUT")
    }

    // The virtual cell emits through its STAGED buses, respecting busEnabled — a disabled staged emitter is silent.
    func testPreviewRespectsBusEnabled() {
        let gold = colourIDs.firstIndex(of: "gold")!
        let b = boxWithBusEnabled(arpColours(), [false, true, true, true]) { _ in }   // bus A disabled
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0001, -1), beats: 8, into: e)   // preview → bus A (disabled)
        XCTAssertEqual(e.ons.count, 0, "a disabled staged emitter stays silent under preview")
    }

    // Preview emits its arp over the source pool (receiver / OMNI input), and it works with a claim set
    // (CLAIM bypassed — solo has no other-emitter context).
    func testPreviewEmitsOverSourcePoolAndIgnoresClaim() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var s = SceneState.empty()
        var st = PluginState(colours: arpColours(), scenes: [s]); st.claimEmitter = 0   // CLAIM on bus A
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
        var cell = Cell(colourID: "gold", buses: [.a]); cell.inputReceiver = 0
        s.cells[0][0] = cell
        var st = PluginState(colours: arpColours(), scenes: [s])
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
        var cell = Cell(colourID: "gold", buses: [.a]); cell.inputReceiver = 0   // R1 arp (inherits colour machine)
        s.cells[0][0] = cell
        var st = PluginState(colours: arpColours(), scenes: [s])
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
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var cs = arpColours(); cs[colourIDs.firstIndex(of: "gold")!].type = .passgate   // an identity HOLD → reads via srcCount(for:) = inputChanMask
        var st = PluginState(colours: cs, scenes: [s])
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
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()   // gold = arp (arpColours)
        var st = PluginState(colours: arpColours(), scenes: [s])
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
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(colours: arpColours(), scenes: [s])
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
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(colours: arpColours(), scenes: [s])
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
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(colours: arpColours(), scenes: [s])
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
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(colours: arpColours(), scenes: [s])
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
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(colours: arpColours(), scenes: [s])
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
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: buses); c.inputReceiver = 0; c.processors = []; return c }()   // EMPTY chain → the live wire
        var st = PluginState(colours: arpColours(), scenes: [s]); st.busChannels = [1, 2, 3, 4]; st.masterMute = masterMute
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
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 1; return c }() }
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
        let b = box(colours: arpColours()) { _ in }
        let sr = 48_000.0, tempo = 120.0; let frames: UInt32 = 4096
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        func sweep(laneMask: UInt8) -> (cols: Set<Int>, steps: Set<Int>) {
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
        var cell = Cell(colourID: "gold", buses: [.a]); cell.inputRow = nil; cell.inputReceiver = 0
        s.cells[0][0] = cell
        var st = PluginState(colours: arpColours(), scenes: [s])
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

    // 1c: a STRUM colour previews (source chord strummed) and releases clean.
    func testPreviewStrumSoundsAndReleasesClean() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours(); cs[gold] = Colour(colourID: "gold", type: .strum)
        let b = box(colours: cs) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0001, -1), beats: 8, into: e)
        XCTAssertGreaterThan(e.ons.count, 0, "strum preview strums the source chord")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // 1c: a chord-hold colour (HARMONIZE) previews (treated held chord, re-emitted per column) and releases clean.
    func testPreviewChordHoldSoundsAndReleasesClean() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours(); cs[gold] = Colour(colourID: "gold", type: .harmonize)
        let b = box(colours: cs) { _ in }
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
        let gold = colourIDs.firstIndex(of: "gold")!
        let b = box(colours: arpColours()) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1),
                                         beats: 8, into: e, playing: false)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "stopped preview free-clock arps the source pool on bus B")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: false, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // Stopped preview handles only the time-varying ARP path (a chord-hold colour's stopped preview is a later
    // cut); a non-arp colour is silent when the transport is stopped.
    func testStoppedPreviewNonArpColourIsSilent() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours(); cs[gold] = Colour(colourID: "gold", type: .harmonize)
        let b = box(colours: cs) { _ in }
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0001, -1), beats: 8, into: e, playing: false)
        XCTAssertEqual(e.ons.count, 0, "a chord-hold colour is silent under stopped preview")
    }

    // PLAYING preview, RATCHET: the virtual cell repeats the source chord on its staged bus, releasing clean.
    func testPreviewRatchetSoundsAndReleasesClean() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours(); cs[gold] = Colour(colourID: "gold", type: .ratchet)
        let b = box(colours: cs) { _ in }
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
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours(); cs[gold] = Colour(colourID: "gold", type: .chance); cs[gold].paramsA.probability = 1
        let b = box(colours: cs) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 2 }.map { $0.note }), [60, 64, 67], "chance p=1 holds the source chord on bus B")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)

        var cs0 = arpColours(); cs0[gold] = Colour(colourID: "gold", type: .chance); cs0[gold].paramsA.probability = 0
        let b0 = box(colours: cs0) { _ in }
        let eNone = RecordingEmitter()
        runPreview(b0, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: eNone)
        XCTAssertEqual(eNone.ons.count, 0, "chance p=0 previews to silence")
    }

    // 1c: an all-open PASSGATE (= identity chord-hold) sustains the held chord on the staged bus, releasing clean.
    func testPreviewIdentityChordHoldSustains() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours(); cs[gold] = Colour(colourID: "gold", type: .passgate)
        cs[gold].paramsA.passes = [true, true, true, true]   // all-open → identity chord-hold
        let b = box(colours: cs) { _ in }
        let e = RecordingEmitter()
        let (router, _, ts) = runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, -1), beats: 8, into: e)
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 2 }.map { $0.note }), [60, 64, 67], "an all-open passgate sustains the held chord on bus B")
        var diag = KernelDiag()
        router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: 8, tempo: 120, sampleRate: 48_000,
                       timestampSample: ts, frameCount: 2048, preview: (false, -1, 0, 0, -1), out: e, diag: &diag)
        assertNothingLeftSounding(e)
    }

    // COG SIMPLIFICATION (2026-08-03): cables are RETIRED — the render ALWAYS hears every cable (union), even if a
    // saved receiver still carries a restricted `cable` field (kept for decode-compat but ignored by the builder).
    func testInputCablesAlwaysAcceptAllAfterRetirement() {
        var s = SceneState.empty()
        var cell = Cell(colourID: "gold", buses: [.a]); cell.inputReceiver = 1
        s.cells[0][0] = cell
        var st = PluginState(colours: arpColours(), scenes: [s])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2", cable: 0b0101), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.cells[0 * Snap.rows + 0].inputCableMask, 0b1111, "a subscriber cell hears ALL cables (cables retired)")
        XCTAssertEqual(b.receiverCables, [0b1111, 0b1111, 0b1111, 0b1111], "every receiver hears all cables — a saved cable filter is ignored")
    }

    // §item 11 mute ruling: a MUTED receiver resolves to the match-nothing filter on the box — this is what
    // makes its input meter go dark and (for R1) blocks passthrough. An unmuted OMNI receiver stays OMNI.
    func testMutedReceiverResolvesToMatchNothingFilter() {
        var st = PluginState(colours: arpColours(), scenes: [SceneState.empty()])
        var r0 = Receiver(name: "1"); r0.muted = true
        st.receivers = [r0, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.receiverChannels[0], Snap.mutedSourceFilter, "a muted receiver resolves to match-nothing")
        XCTAssertEqual(b.receiverChannels[1], 0, "an unmuted OMNI receiver stays OMNI (0)")
        XCTAssertFalse(receiverHears(filter: b.receiverChannels[0], channel: 0), "match-nothing → hears no channel")
    }

    // §9 item 1 ON ARRIVE (integration): ALT-ALTERNATE on a swap pair (A = open passgate → sounds,
    // B = closed passgate → silent) flips the cell's sounding every pass. Proves the derivation is wired
    // into the render (pass 0 = base A, pass 1 = flipped B).
    // (testArriveAltAlternateFlipsSoundingAcrossPasses removed 2026-08-27: A/B MORPH dropped → ON.arrive=.altAlternate no
    //  longer flips the sounding face, so both passes only assert `ons > 0` (the head always sounds) — vacuous.)

    // §9 item 1 ON ARRIVE (integration): EMITTER-ROTATE walks the firing cable each pass — a cell on
    // emitter A (cable 1) rotates to B (cable 2) on the next pass.
    func testArriveEmitterRotateWalksCablesAcrossPasses() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours()
        var on = OnConfig(); on.arrive = .emitterRotate; on.arriveEvery = 1; cs[gold].on = on
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // fires on A
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
        let gold = colourIDs.firstIndex(of: "gold")!
        func firstNoteLength(gate: Double) -> Int64 {
            var cs = arpColours()
            cs[gold].paramsA.gate = gate
            let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours()
        var on = OnConfig(); on.sceneEntrance = true; on.entrancePass = 3; cs[gold].on = on
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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

    // §9 item 1 ON TAP (4a, integration): the ephemeral tapAltMask flips a cell's effective ALT (unified model)
    // — a swap pair (A = open passgate, B = closed) goes silent when its tap bit is set.
    // (testTapAltMaskFlipsCellEphemerally removed 2026-08-27: A/B MORPH dropped → the tap-ALT flip no longer swaps the
    //  processor face, so both assertions are `ons > 0` (the head always sounds) — vacuous. The real tap-mute path is
    //  covered by testTapMuteSilencesCell below.)

    // §9 item 1 ON TAP = MUTE (4b): a cell whose tapMuteMask bit is set falls silent (momentary).
    func testTapMuteSilencesCell() {
        let gold = colourIDs.firstIndex(of: "gold")!
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // grid (0,0) = bit 0
        func ons(_ mute: UInt64) -> Int {
            let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
            let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
            let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
            while beat < 2.0 {
                router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, tapMuteMask: mute, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
            return e.ons.count
        }
        XCTAssertGreaterThan(ons(0), 0, "un-muted → the cell sounds")
        XCTAssertEqual(ons(1 << 0), 0, "ON TAP = MUTE (bit 0) → the cell is silent")
    }

    // §9 item 1 ON TAP = SOLO EMITTERS (4b): a solo set silences sibling emitters (cell on A + cell on B;
    // solo = {A} → B falls silent). Solo bypasses previewMode elsewhere; here two real cells on two buses.
    func testSoloEmitterMaskSilencesSiblings() {
        let cs = arpColours()
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]); $0.cells[0][1] = Cell(colourID: "orange", buses: [.b]) }
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
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours()
        var on = OnConfig(); on.hold = .oct; on.octUp = true; cs[gold].on = on
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // grid (0,0) = index 0
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
        let gold = colourIDs.firstIndex(of: "gold")!
        let b = box(colours: arpColours()) { _ in }
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
        var st = PluginState(colours: arpColours(), scenes: [s])
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
            $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
            $0.cells[0][1] = { var c = Cell(colourID: "cyan", buses: [.b]); c.inputReceiver = 1; return c }()
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
            $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        }
        XCTAssertEqual(soloOns(b, solo: 0b0001, cable: 1), 0, "a soloed BUT muted receiver stays silent")
    }

    // (grid-chaining retired: the solo-silences-chained-feed test was removed — no cross-cell feeds.)

    // MARK: - receiver OCT nudge (receiver strip) — ephemeral ±octave, composes with colour transpose

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
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }() }
        XCTAssertTrue(octNotes(b, inputOctave: 0, cable: 1).contains(60), "base ⇒ 60 sounds")
        let up = octNotes(b, inputOctave: packOct(0, 1), cable: 1)
        XCTAssertTrue(up.contains(72), "+1 oct on R1 ⇒ 60 becomes 72")
        XCTAssertFalse(up.contains(60), "the base 60 is gone once shifted")
        XCTAssertTrue(octNotes(b, inputOctave: packOct(0, -1), cable: 1).contains(48), "−1 oct ⇒ 48")
        // a nudge on a DIFFERENT receiver leaves this cell untouched
        XCTAssertTrue(octNotes(b, inputOctave: packOct(1, 2), cable: 1).contains(60), "R2's nudge doesn't move an R1 cell")
    }

    func testReceiverOctaveComposesWithColourTranspose() {
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!].transpose = 2      // +2 semitones on the colour
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        var st = PluginState(colours: cs, scenes: [s]); st.receivers = (0..<4).map { Receiver(name: "\($0 + 1)") }
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
            $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
            $0.cells[0][1] = { var c = Cell(colourID: "cyan", buses: [.b]); c.inputReceiver = 1; return c }()
        }
        XCTAssertEqual(velsOn(b, inputVel: 0, cable: 1), [100], "natural base velocity = the source note's velocity (was flat 96)")
        XCTAssertEqual(velsOn(b, inputVel: packVel(0, 40), cable: 1), [40], "R1 override flattens A to 40")
        XCTAssertEqual(velsOn(b, inputVel: packVel(0, 40), cable: 2), [100], "an R1 override leaves R2's B natural (source velocity)")
    }

    func testEmitterOverrideWinsOverInputOverride() {
        // Both ride at once: input R1 = 40, emitter A = 110 → the OUTPUT override (closest to the wire) wins.
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }() }
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
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }() }
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
        let b = receiverBox { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }() }
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
        let b = box(colours: arpColours()) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a])
            $0.cells[0][1] = Cell(colourID: "cyan", buses: [.b])
        }
        XCTAssertTrue(emitOctNotes(b, emitterOctave: 0, cable: 1).contains(60), "base ⇒ 60 on E1")
        let up = emitOctNotes(b, emitterOctave: packEmitOct(0, 1), cable: 1)
        XCTAssertTrue(up.contains(72) && !up.contains(60), "+1 oct on E1 ⇒ 60→72")
        XCTAssertTrue(emitOctNotes(b, emitterOctave: packEmitOct(0, 1), cable: 2).contains(60), "E2 (bus 1) unshifted")
    }

    func testEmitterOctaveDropsOutOfRangeNotes() {
        // a high note pushed past 127 by the shift is dropped (no voice, no stuck note).
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        XCTAssertTrue(emitOctNotes(b, emitterOctave: 0, cable: 1, chordNotes: [120]).contains(120), "120 sounds at base")
        XCTAssertTrue(emitOctNotes(b, emitterOctave: packEmitOct(0, 1), cable: 1, chordNotes: [120]).isEmpty,
                      "120 + 12 = 132 > 127 ⇒ dropped")
    }

    // MARK: - emitter FLATTEN (role family) — activity ducking, admission-time velocity scale

    private func flattenBox(_ flattenMask: UInt8, _ amount: [Int]) -> SnapshotBox {
        var cs = arpColours()
        let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].type = .passgate; cs[gi].paramsA.passes = [true, true, true, true]   // A holds the chord (sounds)
        var s = SceneState.empty()
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // → Emit A (cable 1): the sounding held chord
        s.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // → Emit B (cable 2): an arp of NEW note-ons
        var st = PluginState(colours: cs, scenes: [s])
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
        // A (passgate, holds) FLATTENs at 50%; B's new arp notes arrive velocity-scaled to 50 (100·50%).
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])   // one arp fanning to BOTH A and B
        var st = PluginState(colours: arpColours(), scenes: [s])
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // an arp on Emit A
        var st = PluginState(colours: arpColours(), scenes: [s]); st.masterMute = mute
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
        let b = box(colours: arpColours()) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) } }
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
        let b = box(colours: arpColours()) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) } }
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
        // A passgate HOLD (all-open) sustains the chord on A → the kill edge must send its note-offs (the DJ drop).
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!] = { var c = Colour(colourID: "gold", type: .passgate); c.paramsA.passes = [true, true, true, true]; return c }()
        let b = box(colours: cs) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) } }
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

    /// A drone of identical adjacent PASS-class cells. Two boundaries crossed → count note-offs on the wire.
    private func droneOffs(phase: ArpPhase, windows: Int = 48) -> (offs: Int, ons: Int, e: RecordingEmitter) {
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!] = { var c = Colour(colourID: "gold", type: .passgate); c.paramsA.passes = [true, true, true, true]; c.paramsA.phase = phase; return c }()
        let b = box(colours: cs) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) } }
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
        // matching voice (same note+emitter+colour/face); the chord is struck ONCE and never re-speaks.
        let r = droneOffs(phase: .legato)
        XCTAssertEqual(r.offs, 0, "LEGATO drone: ZERO note-offs should cross a boundary")
        XCTAssertEqual(r.ons, 6, "struck exactly ONCE (3 notes × 2 cables) — no re-strike at any boundary")
    }

    /// §2 CONTINUITY × THE RACK FENCE: a legato drone into a FENCE-CLAMP emitter. The note is clamped into the
    /// window, but it's the SAME clamped pitch in every column, so adoption must keep ONE voice — the drone flows.
    /// The adoption pitch prediction has to apply FENCE too, or it predicts the un-fenced pitch, fails to match the
    /// (fenced) sounding voice, and re-strikes every boundary (machine-guns). Regression lock for that.
    private func fencedDroneOffs(policy: Int, lo: Int, hi: Int) -> (offs: Int, ons: Int) {
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!] = { var c = Colour(colourID: "gold", type: .passgate)
            c.paramsA.passes = [true, true, true, true]; c.paramsA.phase = .legato; return c }()
        var st = PluginState(colours: cs, scenes: [{ var s = SceneState.empty()
            for c in 0..<8 { s.cells[c][0] = Cell(colourID: "gold", buses: [.a]) }; return s }()])
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
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!] = { var c = Colour(colourID: "gold", type: .passgate); c.paramsA.passes = [true, true, true, true]; c.paramsA.phase = .legato; return c }()
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // ONLY column 0
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
        var cs = arpColours()
        cs[colourIDs.firstIndex(of: "gold")!] = { var c = Colour(colourID: "gold", type: .passgate); c.paramsA.passes = [true, true, true, true]; c.paramsA.phase = .legato; return c }()
        let b = box(colours: cs) { for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]) } }
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
        let b = box(colours: arpColours()) {
            for c in 0..<8 { $0.cells[c][0] = Cell(colourID: "gold", buses: [.a]); $0.cells[c][1] = Cell(colourID: "cyan", buses: [.b]) }
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])       // ONE cell → A only
        var st = PluginState(colours: arpColours(), scenes: [s]); st.altMask = 0b0011; st.altCount = [1, 1, 1, 1]
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
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // cell 1 → A
            s.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // cell 2 → B
            var st = PluginState(colours: arpColours(), scenes: [s]); st.altMask = altMask; st.altCount = [1, 1, 1, 1]
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // passgate hold → A
        s.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // passgate hold → B
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s])
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
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])
            s.cells[0][1] = Cell(colourID: "cyan", buses: [.b])
            var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s])
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
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // hold → A
            s.cells[0][1] = Cell(colourID: "cyan", buses: [.b])   // hold → B (both strike at colStart)
            var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s])
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // passgate hold → A (one note-on at the source velocity)
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s])
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

    /// The set of output notes on A when a passgate holds note 60 → A under a FENCE window/policy.
    private func fenceOut(policy: Int, lo: Int, hi: Int, on: Bool = true, rack: UInt8? = nil) -> Set<UInt8> {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // passgate hold → A, note 60
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s])
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
        var s = SceneState.empty(); s.cells[0][0] = Cell(colourID: "gold", buses: [.a])
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s])
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // passgate hold → A holds the whole chord
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s])
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s]); st.monoMask = 0b0001
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
            var cs = arpColours(); cs[colourIDs.firstIndex(of: "orange")!].type = .glide
            var s = SceneState.empty()
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])                     // ARP on A — changing notes steal under MONO
            s.cells[0][1] = { var x = Cell(colourID: "orange", buses: [.a])         // GLIDE on A — its anchor is the immortal voice MONO steals
                var g = ProcessorSlot(type: .glide); g.params.glideMode = .bend; g.params.glideRange = 12
                g.params.glidePriority = .last; g.params.glideTime = 0.1; x.processors = [g]; return x }()
            var st = PluginState(colours: cs, scenes: [s]); st.monoMask = 0b0001; st.monoPriority = [0, 0, 0, 0]   // MONO LAST on A
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
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a])
            var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s])
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])
        s.cells[0][1] = Cell(colourID: "gold", buses: [.a])
        let box = SnapshotBuilder.build(from: PluginState(colours: claimColours(transposeB: 0), scenes: [s]))
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
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])       // a LEGATO drone → A (immortal hold, offSample .max)
        var gold = passgateColour("gold"); gold.paramsA.phase = .legato
        let cs = colourIDs.map { $0 == "gold" ? gold : Colour(colourID: $0, type: .arp) }
        let box = SnapshotBuilder.build(from: PluginState(colours: cs, scenes: [s]))
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
        if leadPresent { s.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // lead sustains on A
        s.cells[0][1] = Cell(colourID: "cyan", buses: [.b])                       // follower on B
        var st = PluginState(colours: claimColours(transposeB: 0), scenes: [s])
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
        let cs = arpColours()
        func gen(_ g: UInt64) -> SnapshotBox {
            var s = SceneState.empty(); s.cells[0][0] = Cell(colourID: "gold", buses: [.a])   // identity HOLD → emits the held note
            var st = PluginState(colours: cs, scenes: [s]); st.busChannels = [1, 2, 3, 4]
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
        router.applyParamEvent(100, 12, diag: &diag)                // +12 on gold (address 100 = colour 0 transpose)
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
        router.applyParamEvent(9_999, 42, diag: &diag)
        XCTAssertEqual(diag.paramEventCount, 0, "an unmapped address applies nothing")
    }

    // MARK: - the PLAYING CHANCE chord-hold path (distinct from audition/preview)

    /// The live emitColumnHolds CHANCE branch: probability 1 passes the whole chord, probability 0 silences it.
    /// Previously only the audition + preview chance paths were covered, not the playing one.
    func testPlayingChanceGatesOnProbability() {
        func chanceBox(_ p: Double) -> SnapshotBox {
            var cs = arpColours(); let gi = colourIDs.firstIndex(of: "gold")!
            cs[gi] = Colour(colourID: "gold", type: .chance); cs[gi].paramsA.probability = p
            return box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // identity hold
        let empty = box(colours: arpColours()) { _ in }                                               // the incoming (empty) scene
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

    private func echoColours(div: Int = 1, repeats: Int = 4, feedDelay: Double = 0.5, decay: Double = 0.5,
                             thru: Bool = true, pitch: Int = 0, offset: Double = 0) -> [Colour] {
        colourIDs.map { var c = Colour(colourID: $0, type: .echo)
            c.paramsA.echoSync = true; c.paramsA.echoDelayDiv = div; c.paramsA.echoRepeats = repeats
            c.paramsA.echoFeedDelay = feedDelay; c.paramsA.echoDecay = decay
            c.paramsA.echoThru = thru; c.paramsA.echoPitch = pitch; c.paramsA.echoOffset = offset; return c }
    }

    /// A single-slot [ECHO] cell re-strikes its held note the DRY + REPEATS times, velocities DECAYING, no stuck notes.
    func testEchoRepeatsHeldNoteWithDecay() {
        let b = box(colours: echoColours(div: 1, repeats: 4, feedDelay: 0.5, decay: 0.5)) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: echoColours(div: 1, repeats: 8, feedDelay: 0.2, decay: 0.2)) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
            box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .echo)
                c.paramsA.echoDelayDiv = 2; c.paramsA.echoRepeats = 12; c.paramsA.echoFeedDelay = 0.9
                c.paramsA.echoDecay = 0.95; c.paramsA.echoSpill = spill; return c
            }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        }
        let ring = RecordingEmitter(); run(spillBox(.ring), chord([60]), beats: 6, into: ring)
        let cut = RecordingEmitter(); run(spillBox(.cut), chord([60]), beats: 6, into: cut)
        XCTAssertLessThan(cut.ons.count, ring.ons.count, "CUT keeps echoes inside the bar; RING spills past it")
        XCTAssertGreaterThan(cut.ons.count, 0, "CUT still emits within the column")
        assertNothingLeftSounding(cut); assertNothingLeftSounding(ring)
    }
    /// ECHO via the REAL creation path: a cell whose COLOUR A-face is passgate, carrying an explicit single-slot
    /// [ECHO] processor chain (what addSlotCells builds) — must still dry + repeat (guards the chain→proc resolution).
    func testEchoViaExplicitSingleSlotChainStillRepeats() {
        let b = box(colours: [Colour(colourID: "gold", type: .passgate)]) {
            var c = Cell(colourID: "gold", buses: [.a])
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
    /// ECHO as a chain TAIL (user 2026-08-08 bug): `[PASSGATE(bypassed) → ECHO]` must echo the upstream hold set, not
    /// fall through to a silent passthrough (emitEchoColumn read the HEAD, so echo-as-tail did nothing).
    func testEchoThenHarmonizeEchoesTheHarmonizedSet() {
        // [ECHO → HARMONIZE]: echo in the FIRST slot of a HOLD-tail chain. Bug (user 2026-08-10): the echo was dropped
        // (composeChainSet folded it as pass-through); it now registers tails for the fully-processed (harmonized) set.
        var s0 = ProcessorSlot(type: .echo); s0.params.echoDelayDiv = 1; s0.params.echoRepeats = 4; s0.params.echoFeedDelay = 0.6; s0.params.echoDecay = 0.5
        var s1 = ProcessorSlot(type: .harmonize); s1.params.harmIntervals = [7, 0, 0]
        let b = box(colours: [Colour(colourID: "gold", type: .passgate)]) {
            var c = Cell(colourID: "gold", buses: [.a]); c.processors = [s0, s1]; $0.cells[0][0] = c
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
        let b = box(colours: [Colour(colourID: "gold", type: .passgate)]) {
            var c = Cell(colourID: "gold", buses: [.a]); c.processors = [s0, s1]; $0.cells[0][0] = c
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
            let b = box(colours: [Colour(colourID: "gold", type: .passgate)]) {
                var c = Cell(colourID: "gold", buses: [.a]); c.processors = [s0, s1]; $0.cells[0][0] = c }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 1.5, into: e); assertNothingLeftSounding(e); return e
        }
        let thru = run2(thru: true), mute = run2(thru: false)
        XCTAssertGreaterThan(mute.ons.count, 0, "MUTE still rings the echoes")
        XCTAssertLessThan(mute.ons.count, thru.ons.count, "MUTE drops the dry hold → fewer note-ons than THRU")
    }
    func testEchoAsChainTailEchoesUpstreamSet() {
        let b = box(colours: [Colour(colourID: "gold", type: .passgate)]) {
            var c = Cell(colourID: "gold", buses: [.a])
            var s0 = ProcessorSlot(type: .passgate); s0.bypassed = true         // passthrough upstream
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
            box(colours: arpColours()) {
                var c = Cell(colourID: "gold", buses: [.a])
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
            box(colours: arpColours()) {
                var c = Cell(colourID: "gold", buses: [.a])
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
        let b = box(colours: arpColours()) {
            var c = Cell(colourID: "gold", buses: [.a])
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
            box(colours: arpColours()) {
                var c = Cell(colourID: "gold", buses: [.a])
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
            box(colours: arpColours()) {
                var c = Cell(colourID: "gold", buses: [.a])
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
            box(colours: arpColours()) {
                var c = Cell(colourID: "gold", buses: [.a])
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
            box(colours: arpColours()) {
                var c = Cell(colourID: "gold", buses: [.a])
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
        let b = box(colours: echoColours(div: 1, repeats: 6, feedDelay: 0.7, decay: 0.7)) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let b = box(colours: echoColours(div: 1, repeats: 4, feedDelay: 0.6, decay: 0.6)) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
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
        let cs = colourIDs.map { id -> Colour in
            if id == "gold" { return Colour(colourID: id, type: .drone) }
            if id == "orange" { var c = Colour(colourID: id, type: .hocket)
                c.paramsA.hocketSource = 0; c.paramsA.hocketMode = .gaps; c.paramsA.hocketRate = .r1_8; return c }
            return Colour(colourID: id, type: .arp)
        }
        return box(colours: cs) {
            if wireOnA { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // the DRONE wire on emitter A
            $0.cells[0][1] = Cell(colourID: "orange", buses: [.b])                // HOCKET on emitter B, listening to A
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
        let cs = colourIDs.map { id -> Colour in
            if id == "gold" { var c = Colour(colourID: id, type: .hocket)
                c.paramsA.hocketSource = 0; c.paramsA.hocketMode = .gaps; c.paramsA.hocketRate = .r1_8; return c }
            return Colour(colourID: id, type: .arp)
        }
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // listens to A, emits on A
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 8, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "a self-listening loop falls silent")
        assertNothingLeftSounding(e)
    }
}

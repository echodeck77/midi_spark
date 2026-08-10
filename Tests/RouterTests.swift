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
    private func box(colours cs: [Colour], busChannels: [Int] = [1, 2, 3, 4],
                     _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(colours: cs, scenes: [s]); st.busChannels = busChannels
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
    func testCascadeRevealsEachChordNoteOnce() {
        let b = box(colours: colourIDs.map { var c = Colour(colourID: $0, type: .cascade)
            c.paramsA.rate = .r1_8; return c }) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 2, into: e)
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 3, "the 3-note chord revealed one note at a time")
        assertNothingLeftSounding(e)
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

    func testFanOutTreeEmitsThreeDerivedStreams() {
        // Device T9 (multi-level fan-out), previously unit-untested: one arp PARENT (MIDI IN, no bus →
        // silent source), two CHILDREN ⇐row0 on B and C, and a GRANDCHILD ⇐row1 on D. All three derived
        // streams sound simultaneously; the parent itself is silent (no bus).
        let b = box(colours: arpColours()) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [])                 // parent — silent source (no bus)
            $0.cells[0][1] = Cell(colourID: "gold", buses: [.b], inputRow: 0)  // child1 ⇐ row 0 → B
            $0.cells[0][2] = Cell(colourID: "gold", buses: [.c], inputRow: 0)  // child2 ⇐ row 0 → C
            $0.cells[0][3] = Cell(colourID: "gold", buses: [.d], inputRow: 1)  // grandchild ⇐ row 1 → D
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "the bus-less parent is silent")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "child1 derives onto B")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 3 }.count, 0, "child2 derives onto C")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 4 }.count, 0, "grandchild (⇐child) derives onto D")
        assertNothingLeftSounding(e)
    }

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

    func testBackwardTapDownwardReferenceEmits() {
        // Device T11b (backward tap), previously unit-untested at the Router level: a cell references a
        // row BELOW itself (legal in v3.0 — any-row refs). Row 0 ⇐ row 2 → A; row 2 ⇐ MIDI IN → B. Both
        // sound: the downward ref resolves (unit-delay sampling) and row 0 emits a processed row-2 stream.
        let b = box(colours: arpColours()) {
            $0.cells[0][0] = Cell(colourID: "gold", buses: [.a], inputRow: 2)  // row 0 ⇐ row 2 (below) → A
            $0.cells[0][2] = Cell(colourID: "gold", buses: [.b])               // row 2 ⇐ MIDI IN → B
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "row 2 (the source) sounds on B")
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 1 }.count, 0, "row 0 emits a processed downward-ref stream on A")
        assertNothingLeftSounding(e)
    }

    func testProcBFullMorphsToBFaceUnderAlt() {
        // CELL MACHINE (feat/EditPageSpike): A/B morph is DROPPED — the render uses the HEAD (A face) only, so
        // ALT no longer flips to procB's 3-oct arp. procB stays dormant in the model; NEITHER state reaches 72.
        var cs = arpColours()
        let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].paramsA.octaves = 1
        cs[gi].typeB = .arp; cs[gi].paramsB.octaves = 3
        func emitted(_ alt: Bool) -> Set<UInt8> {
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.alt = alt; return c }() }
            let e = RecordingEmitter(); run(b, chord([60]), beats: 16, into: e)
            return Set(e.ons.filter { $0.cable == 1 }.map { $0.note })
        }
        XCTAssertFalse(emitted(false).contains(72), "the head 1-oct arp never reaches 72")
        XCTAssertFalse(emitted(true).contains(72), "morph DROPPED: ALT stays on the head (A face) — never reaches procB's 72")
    }

    func testProcBSwapFlipsTypeUnderAlt() {
        // CELL MACHINE: A/B morph DROPPED — ALT no longer swaps type. The head (arp) sounds in BOTH states;
        // procB's closed passgate is dormant.
        var cs = arpColours()
        let gi = colourIDs.firstIndex(of: "gold")!
        cs[gi].typeB = .passgate; cs[gi].paramsB.passes = [false, false, false, false]
        func sounds(_ alt: Bool) -> Bool {
            let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.alt = alt; return c }() }
            let e = RecordingEmitter(); run(b, chord([60, 64, 67]), beats: 16, into: e)
            return !e.ons.isEmpty
        }
        XCTAssertTrue(sounds(false), "the head gold arp sounds")
        XCTAssertTrue(sounds(true), "morph DROPPED: ALT no longer swaps to the closed passgate — the head arp still sounds")
    }

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
        let b = box(colours: cs) { $0.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.processors = [ProcessorSlot(type: .arp)]; return c }() }
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        let frames: UInt32 = 2048, sr = 48_000.0, tempo = 120.0
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        for _ in 0..<8 {   // a few windows so the arp fires
            router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        let strikes = router.drainCellStrikes()
        XCTAssertEqual(strikes.count, 64)
        XCTAssertGreaterThan(strikes[0], 0, "cell (0,0) fired → its strike velocity is recorded at index 0")
        XCTAssertEqual(strikes[1], 0, "a silent cell records nothing")
        XCTAssertTrue(router.drainCellStrikes().allSatisfy { $0 == 0 }, "drain is read-and-clear")
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
        XCTAssertEqual(held & 1, 1, "cell (0,0) is holding a note → its sounding bit is set")
        XCTAssertEqual(held >> 1, 0, "no other cell sounds")
        router.process(box: b, pool: chord([60, 64, 67]), playing: false, beatPos: beat, tempo: tempo,   // stop → release
                       sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        router.snapshotCellSounding()
        XCTAssertEqual(router.currentCellSounding(), 0, "after release the gate clears")
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
        XCTAssertEqual(mask & 1, 0, "the muted claimant's SILENT ghost must NOT light its comet (cell 0)")
        XCTAssertEqual((mask >> 1) & 1, 1, "…while the audible non-claimant DOES light (cell 1) — the scene is live")
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
        XCTAssertEqual(router.currentCellSounding(), 0, "a muted cell lights no comet")
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
        XCTAssertEqual(router.currentCellSounding().nonzeroBitCount, 1, "exactly one sounding bit despite the fan-out")
        XCTAssertEqual(router.currentCellSounding() & 1, 1, "…at the cell's index")
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

    func testFedArpArpeggiatesTheParentsSoundingNote() {
        // Parent ARP (row 0 →A); child ARP references row 0 (row 1 →B). The child arpeggiates the
        // parent's CURRENT sounding note by derivation (window-independent) — with a single held note
        // and 1 octave, that note IS the parent's note.
        let b = box(colours: arpColours()) {
            $0.cells[0][0] = Cell(colourID: "gold")                              // parent, MIDI IN →A
            $0.cells[0][1] = Cell(colourID: "azure", buses: [.b], inputRow: 0)   // child ⇐R0 →B
        }
        let e = RecordingEmitter()
        run(b, chord([60]), beats: 16, into: e)
        let childNotes = Set(e.ons.filter { $0.cable == 2 }.map { $0.note })     // bus B = cable 2
        XCTAssertFalse(childNotes.isEmpty, "the fed child should sound")
        XCTAssertEqual(childNotes, [60], "child mirrors the parent's sounding note")
        assertNothingLeftSounding(e)
    }

    func testMutedParentReroutesChildToSource() {
        // Muted parent → child reverts to MIDI IN (delta §1 reroute), so it arps the WHOLE source
        // chord — not a silent mirror. Proven with a chord: the rerouted child sounds all three notes.
        var parent = Cell(colourID: "gold"); parent.muted = true
        let b = box(colours: arpColours()) {
            $0.cells[0][0] = parent
            $0.cells[0][1] = Cell(colourID: "azure", buses: [.b], inputRow: 0)
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.ons.filter { $0.cable == 1 }.isEmpty, "muted parent emits nothing on A")
        XCTAssertEqual(Set(e.ons.filter { $0.cable == 2 }.map { $0.note }), [60, 64, 67],
                       "child rerouted to MIDI IN arps the full source chord (not a nil mirror)")
        assertNothingLeftSounding(e)
    }

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

    // BYPASS (§1/§2) — a bypassed door skips the grid and injects straight to its dest emitters.
    private func bypassBox(dest: Int, rangeLo: Int? = nil, rangeHi: Int? = nil,
                           cell: Bool = false) -> SnapshotBox {
        var s = SceneState.empty()
        if cell { s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }() }
        var st = PluginState(colours: arpColours(), scenes: [s]); st.busChannels = [1, 2, 3, 4]
        var r1 = Receiver(name: "1"); r1.bypass = true; r1.bypassDest = dest; r1.rangeLo = rangeLo; r1.rangeHi = rangeHi
        st.receivers = [r1, Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        return SnapshotBuilder.build(from: st)
    }
    private func stepWindow(_ router: Router, _ box: SnapshotBox, _ pool: NotePool, playing: Bool,
                            beat: Double, out: RecordingEmitter) {
        var diag = KernelDiag()
        router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: 120, sampleRate: 48_000,
                       timestampSample: beat * 24_000, frameCount: 512, out: out, diag: &diag)
    }

    // A bypassed door's GRID cells fall silent — its stream skipped the grid (here with no dests, so nothing sounds).
    func testBypassDivertsItsGridCellsToSilence() {
        let b = bypassBox(dest: 0, cell: true)   // bypassed, NO destinations → total silence (isolates the diversion)
        let e = RecordingEmitter()
        run(b, chord([60, 64]), beats: 8, into: e)
        XCTAssertTrue(e.ons.isEmpty, "a bypassed door's grid cells are silent (the stream left the grid)")
    }

    // Bypass injects a held note on its destination emitter's cable (+ the ALL cable) with that emitter's channel.
    func testBypassInjectsHeldNotesToDestEmitters() {
        let b = bypassBox(dest: 0b0001)   // → emitter A: cable 1, channel 0 (busChannels[0] = 1 → wire 0)
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60]), playing: true, beat: 0, out: e)
        XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == 1 && $0.chan == 0 }, "injects on dest emitter A")
        XCTAssertTrue(e.ons.contains { $0.note == 60 && $0.cable == 0 }, "and on the ALL cable")
        XCTAssertFalse(e.ons.contains { $0.cable == 2 || $0.cable == 3 || $0.cable == 4 }, "not on unselected emitters")
    }

    // Releasing the key emits the bypass note-off — no stuck note.
    func testBypassReleaseEmitsNoteOff() {
        let b = bypassBox(dest: 0b0001)
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60]), playing: true, beat: 0, out: e)      // press
        stepWindow(router, b, NotePool(), playing: true, beat: 0.25, out: e)    // release
        XCTAssertTrue(e.offs.contains { $0.note == 60 && $0.cable == 1 }, "release emits the bypass note-off")
        assertNothingLeftSounding(e)
    }

    // BYPASS + LATCH (PIANO/held): a bypassed door with an ARMED latch injects its FROZEN chord — the live pool is
    // empty (PIANO has no physical keys), so reading live would inject nothing. Locks the reconcileBypass frozen read.
    func testBypassInjectsTheFrozenLatchPoolNotLive() {
        let b = bypassBox(dest: 0b0001)   // bypassed R1 → emitter A (cable 1)
        let frozen = NotePool(); frozen.noteOn(67, velocity: 100, channel: 0); frozen.noteOn(72, velocity: 100, channel: 0); frozen.rebuildSorted()
        let pools = [frozen, NotePool(), NotePool(), NotePool()]
        let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
        // LIVE pool empty (as with PIANO); the frozen R1 pool holds the picked chord. latchMask 0b0001 arms R1.
        router.process(box: b, pool: NotePool(), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                       timestampSample: 0, frameCount: 512, latchMask: 0b0001, latchedPools: pools, out: e, diag: &diag)
        XCTAssertTrue(e.ons.contains { $0.note == 67 && $0.cable == 1 }, "bypass injects the frozen chord (67)")
        XCTAssertTrue(e.ons.contains { $0.note == 72 && $0.cable == 1 }, "bypass injects the frozen chord (72)")
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

    // Bypass admits only in-range notes (the door's RANGE window applies to the injected stream too).
    func testBypassRespectsRange() {
        let b = bypassBox(dest: 0b0001, rangeLo: 62, rangeHi: 127)
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60, 64]), playing: true, beat: 0, out: e)
        XCTAssertFalse(e.ons.contains { $0.note == 60 }, "60 is below the window — not injected")
        XCTAssertTrue(e.ons.contains { $0.note == 64 && $0.cable == 1 }, "64 is in-window — injected")
    }

    // Bypass is a LIVE MONITOR: it survives a transport stop (the transport edge doesn't release it); only the key
    // lifting (or panic) closes it.
    func testBypassPersistsAcrossTransportStop() {
        let b = bypassBox(dest: 0b0001)
        let router = Router(); let e = RecordingEmitter()
        stepWindow(router, b, chord([60]), playing: true, beat: 0, out: e)      // press (playing)
        stepWindow(router, b, chord([60]), playing: false, beat: 0.25, out: e)  // transport STOP, key still down
        XCTAssertEqual(e.offs.filter { $0.note == 60 && $0.cable == 1 }.count, 0, "bypass survives the stop — no release")
        stepWindow(router, b, NotePool(), playing: false, beat: 0.5, out: e)    // release while stopped
        XCTAssertTrue(e.offs.contains { $0.note == 60 && $0.cable == 1 }, "released while stopped → off")
    }

    // SOLO includes bypass (ruling 2026-08-04): a receiver solo set that EXCLUDES the bypassed door silences its
    // bypass too; the SOLOED door's bypass still sounds.
    func testBypassRespectsReceiverSolo() {
        let b = bypassBox(dest: 0b0001)   // R1 bypassed → emitter A
        let e1 = RecordingEmitter(); var d1 = KernelDiag()
        Router().process(box: b, pool: chord([60]), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                         timestampSample: 0, frameCount: 512, soloReceiverMask: 0b0010, out: e1, diag: &d1)   // R2 soloed, R1 excluded
        XCTAssertTrue(e1.ons.isEmpty, "a solo set excluding the bypassed door silences its bypass")
        let e2 = RecordingEmitter(); var d2 = KernelDiag()
        Router().process(box: b, pool: chord([60]), playing: true, beatPos: 0, tempo: 120, sampleRate: 48_000,
                         timestampSample: 0, frameCount: 512, soloReceiverMask: 0b0001, out: e2, diag: &d2)   // R1 soloed
        XCTAssertTrue(e2.ons.contains { $0.note == 60 && $0.cable == 1 }, "the soloed door's bypass still sounds")
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
    func testPreviewRowFeedReadsParentRow() {
        let gold = colourIDs.firstIndex(of: "gold")!
        let b = box(colours: arpColours()) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // row 0 sounds
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, 0), beats: 8, into: e)   // preview → bus B, input ROW 0
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "row-feed: the virtual cell reads row 0")
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "row 0's own cell is soloed out")
    }

    // ROW-FEED with an EMPTY parent row → falls back to the source pool (still sounds).
    func testPreviewRowFeedEmptyParentFallsBackToSource() {
        let gold = colourIDs.firstIndex(of: "gold")!
        let b = box(colours: arpColours()) { _ in }                          // empty grid
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0001, 3), beats: 8, into: e)   // input ROW 3 (empty)
        XCTAssertGreaterThan(e.ons.count, 0, "empty parent → source-pool fallback still arps")
    }

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
    func testPreviewRatchetRowFeedReadsParentRow() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours(); cs[gold] = Colour(colourID: "gold", type: .ratchet)   // "orange" stays arp
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "orange", buses: [.a]) }
        let e = RecordingEmitter()
        runPreview(b, chord([60, 64, 67]), (true, gold, 0, 0b0010, 0), beats: 8, into: e)   // ratchet virtual fed from row 0
        XCTAssertGreaterThan(e.ons.filter { $0.cable == 2 }.count, 0, "ratchet row-feed reads row 0 and repeats it on bus B")
        XCTAssertEqual(e.ons.filter { $0.cable == 1 }.count, 0, "row 0's own cell is soloed out")
    }

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
    func testArriveAltAlternateFlipsSoundingAcrossPasses() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours()
        cs[gold] = Colour(colourID: "gold", type: .passgate)
        cs[gold].paramsA.passes = [true, true, true, true]         // A: open → holds the chord
        cs[gold].typeB = .passgate
        cs[gold].paramsB.passes = [false, false, false, false]     // procB: closed → silent
        var on = OnConfig(); on.arrive = .altAlternate; on.arriveEvery = 1; cs[gold].on = on
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }

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
        let e0 = RecordingEmitter(); runRange(0, cycle, into: e0)             // pass 0 → head (A open)
        let e1 = RecordingEmitter(); runRange(cycle, 2 * cycle, into: e1)     // pass 1 → ALT-ALTERNATE (no face flip now)
        XCTAssertGreaterThan(e0.ons.count, 0, "pass 0 (head: open passgate) sounds the held chord")
        // CELL MACHINE: A/B morph DROPPED — ALT-ALTERNATE no longer flips to procB, so the head (open) keeps sounding.
        XCTAssertGreaterThan(e1.ons.count, 0, "pass 1: morph dropped → ALT-ALTERNATE stays on the head, still sounds")
    }

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
    func testTapAltMaskFlipsCellEphemerally() {
        let gold = colourIDs.firstIndex(of: "gold")!
        var cs = arpColours()
        cs[gold] = Colour(colourID: "gold", type: .passgate); cs[gold].paramsA.passes = [true, true, true, true]
        cs[gold].typeB = .passgate; cs[gold].paramsB.passes = [false, false, false, false]   // procB: closed → silent
        let b = box(colours: cs) { $0.cells[0][0] = Cell(colourID: "gold", buses: [.a]) }   // grid (0,0) = bit 0, base A
        func ons(tapMask: UInt64) -> Int {
            let router = Router(); var diag = KernelDiag(); let e = RecordingEmitter()
            let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
            let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
            while beat < 2.0 {
                router.process(box: b, pool: chord([60, 64, 67]), playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                               timestampSample: ts, frameCount: frames, tapAltMask: tapMask, out: e, diag: &diag)
                beat += wb; ts += Double(frames)
            }
            return e.ons.count
        }
        XCTAssertGreaterThan(ons(tapMask: 0), 0, "no tap flip → head (open passgate) sounds")
        // CELL MACHINE: A/B morph DROPPED — the tap flip still sets the cell's ALT bit but no longer swaps the
        // processor face, so the head (open passgate) keeps sounding. (The tap-mute path is tested separately.)
        XCTAssertGreaterThan(ons(tapMask: 1 << 0), 0, "morph dropped: tap flip no longer swaps to procB — head still sounds")
    }

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
    func testBypassInjectsToMultipleDests() {
        let b = bypassBox(dest: 0b0011)   // emitters A + B → cables 1 and 2
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
}

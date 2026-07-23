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

    /// Drive the render engine across `beats` musical beats of PLAYING windows, then one STOP window
    /// (the transport edge flushes every voice). Mirrors how the Kernel calls it each render.
    private func run(_ box: SnapshotBox, _ pool: NotePool, beats: Double, into emitter: RecordingEmitter,
                     laneMask: UInt8 = 0, releaseAtEnd: Bool = true,
                     tempo: Double = 120, sr: Double = 48_000, frames: UInt32 = 2048) {
        let router = Router()
        var diag = KernelDiag()
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: laneMask, out: emitter, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        if releaseAtEnd {   // release the lap (laneMask 0) then stop — must return to the true timeline, no stuck notes
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: 0, out: emitter, diag: &diag)
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
        for ev in e.events {
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

    func testReferenceCycleIsTotallySilent() {
        // Two cells referencing each other (row 2 ⇐ row 4, row 4 ⇐ row 2), both lit → a closed loop
        // has no entry → TOTAL SILENCE (delta §1, broken by the depth guard).
        let b = box(colours: arpColours()) {
            $0.cells[0][2] = Cell(colourID: "gold",  buses: [.a], inputRow: 4)
            $0.cells[0][4] = Cell(colourID: "azure", buses: [.b], inputRow: 2)
        }
        let e = RecordingEmitter()
        run(b, chord([60, 64, 67]), beats: 16, into: e)
        XCTAssertTrue(e.events.isEmpty, "a reference cycle sounds nothing on any cable")
    }

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
}

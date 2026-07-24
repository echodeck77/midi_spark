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

    // MARK: - COVERAGE HARDENING — device topologies (T-series) with no prior unit coverage

    func testCollisionRefcountKeepsSustainedNoteAliveThroughArpRestrikes() {
        // §7 collision policy (device T7), previously unit-untested: a PASSGATE hold and a same-pitch ARP
        // on the SAME bus + channel. The arp re-strikes 60 every tick; each strike's off is ABSORBED by
        // the refcount while the hold keeps 60 sounding — so there are far MORE ons than offs and the
        // sustained note never drops mid-column. Exactly balanced at the end (nothing stuck).
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
        XCTAssertGreaterThan(ons, offs, "same (cable,ch,note) strikes merge — offs are absorbed by the refcount")
        assertNothingLeftSounding(e)   // the merged off still lands: nothing stuck
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

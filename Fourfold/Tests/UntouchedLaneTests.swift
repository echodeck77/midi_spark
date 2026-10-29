//  UntouchedLaneTests.swift — the page and the engine must read every stored lane the same way (2026-10-29).
//
//  The bug: a lane with none of the legacy note-selection fields set (a bare `EuclidLine()` — how a factory preset leaves its spare lanes, and how a lane saved before those fields existed looks) is "fresh" to the page: riff on,
//  nothing lit. The engine's copy of the lane goes through `euclidLinesForEditing()`, which fills in `noteSel`, so it no longer looked fresh and migrated to the legacy "rank 1 lit, riff off": switch such a lane on and its NOTES layer
//  sounded while the page showed the notes off and the riff on. `PluginState.euclideousLinesResolved` now says `useRiff = true` for an untouched lane, so both read it the same.

import XCTest

private struct Rng: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private final class Tap: MIDIEmitter {
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {}
}

final class UntouchedLaneTests: XCTestCase {

    /// The lines the page holds (the document's resolved lines) and the lines the engine's snapshot carries, by the production path: the page composes the scene from its lines, `SnapshotBuilder` builds the snapshot.
    private func pageAndEngineLines(_ st0: PluginState) -> (page: [EuclidLine], engine: [EuclidLine]) {
        var st = st0
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        let page = st.euclideousLinesResolved
        let input = FourfoldCompose.Input(lines: page, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: st.activeRiffResolved, soloMask: 0, locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        let box = SnapshotBuilder.build(from: st)
        return (page, box.cells[Snap.euclideousRow].procs.first?.euclidLines ?? [])
    }
    /// Everything about a lane's riff / notes layers that the page shows and the engine plays.
    private func agree(_ page: EuclidLine, _ engine: EuclidLine) -> String? {
        let pageNotes = euclideousNotesLayerIsOn(page), engineNotes = engine.notesOnResolved && engine.litOrderResolved.count > 0
        if pageNotes != engineNotes { return "notes layer: page \(pageNotes) / engine \(engineNotes)" }
        if page.riffOnResolved != engine.riffOnResolved { return "riff: page \(page.riffOnResolved) / engine \(engine.riffOnResolved)" }
        if page.litOrderResolved.array != engine.litOrderResolved.array { return "lit order: page \(page.litOrderResolved.array) / engine \(engine.litOrderResolved.array)" }
        if page.notesOnResolved != engine.notesOnResolved { return "notesOn: page \(page.notesOnResolved) / engine \(engine.notesOnResolved)" }
        if page.useRiffResolved != engine.useRiffResolved { return "useRiff: page \(page.useRiffResolved) / engine \(engine.useRiffResolved)" }
        return nil
    }

    // MARK: - the contract

    func testTheFreshDocumentAndEveryFactoryPresetAreReadTheSameByThePageAndTheEngine() {
        var checked = 0
        var docs: [(String, PluginState)] = [("fresh document", PluginState.makeInit())]
        for p in EuclideousPresets.all { docs.append((p.name, p.make())) }
        for (name, st) in docs {
            let (page, engine) = pageAndEngineLines(st)
            XCTAssertEqual(page.count, 4); XCTAssertEqual(engine.count, 4)
            for lane in 0..<4 {
                if let d = agree(page[lane], engine[lane]) { XCTFail("\(name), lane \(lane + 1): \(d)") }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 4 * 21)
    }

    /// Five thousand stored lanes — every mix of the legacy markers, the lit fields (legacy and the order, valid and not) and the switches, set or absent — read the same by the page and the engine.
    func testRandomStoredLanesAreReadTheSameByThePageAndTheEngine() {
        var g = Rng(s: 12345)
        var bad: [String] = []
        for _ in 0..<5_000 {
            var l = EuclidLine()
            if Bool.random(using: &g) { l.pulses = Int.random(in: 0...16, using: &g); l.steps = Int.random(in: 2...16, using: &g) }
            if Bool.random(using: &g) { l.useRiff = Bool.random(using: &g) }
            if Bool.random(using: &g) { l.riffOn = Bool.random(using: &g) }
            if Bool.random(using: &g) { l.noteSel = EuclidNoteSel.allCases.randomElement(using: &g)! }
            if Bool.random(using: &g) { l.melodyMode = EuclideousMelodyMode.allCases.randomElement(using: &g)! }
            if Bool.random(using: &g) { l.target = Int.random(in: 0...8, using: &g) }
            if Bool.random(using: &g) { l.pick = EuclidPick.allCases.randomElement(using: &g)! }
            if Bool.random(using: &g) { l.litNotes = UInt8.random(in: 0...255, using: &g) }
            if Bool.random(using: &g) { l.topLit = Bool.random(using: &g) }
            if Bool.random(using: &g) { l.top2Lit = Bool.random(using: &g) }
            switch Int.random(in: 0...3, using: &g) {
            case 0: break
            case 1: l.notesLitOrder = []
            case 2: l.notesLitOrder = Array(UInt8(0)...9).shuffled(using: &g).prefix(Int.random(in: 0...5, using: &g)).map { $0 }
            default: l.notesLitOrder = [11, 3]   // not a valid order
            }
            switch Int.random(in: 0...2, using: &g) { case 0: break; case 1: l.notesOn = true; default: l.notesOn = false }
            var st = PluginState.makeInit()
            var lines = (0..<4).map { _ in EuclidLine() }
            lines[1] = l
            st.euclideousLines = lines
            let (page, engine) = pageAndEngineLines(st)
            if let d = agree(page[1], engine[1]), bad.count < 5 {
                bad.append("\(d) | stored useRiff \(String(describing: l.useRiff)) riffOn \(String(describing: l.riffOn)) noteSel \(String(describing: l.noteSel)) melodyMode \(String(describing: l.melodyMode)) target \(l.target) pick \(String(describing: l.pick)) litNotes \(String(describing: l.litNotes)) order \(String(describing: l.notesLitOrder))")
            }
        }
        XCTAssertTrue(bad.isEmpty, bad.joined(separator: "\n"))
    }

    // MARK: - what an untouched lane is, and what it plays

    func testAnUntouchedLaneIsReadAsRiffOnAndNothingLitAndTheStoredDocumentIsNotRewritten() {
        var st = PluginState.makeInit()
        st.euclideousLines = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        XCTAssertTrue(st.euclideousLines![2].isUntouchedLane)
        let lane = st.euclideousLinesResolved[2]
        XCTAssertTrue(lane.riffOnResolved); XCTAssertTrue(lane.useRiffResolved)
        XCTAssertEqual(lane.litOrderResolved.count, 0); XCTAssertFalse(euclideousNotesLayerIsOn(lane))
        XCTAssertTrue(st.euclideousLines![2].isUntouchedLane, "reading a lane does not write it back: the stored document is exactly what it was")
        XCTAssertNil(st.euclideousLines![2].useRiff)
    }

    func testALaneWithAnyLegacyMarkerKeepsItsOwnMigration() {
        // a lane saved with the old LOWEST selector and no riff: one lit note (rank 1), riff off — on the page and in the engine alike
        var st = PluginState.makeInit()
        var old = EuclidLine(); old.noteSel = .low
        st.euclideousLines = [old, EuclidLine(), EuclidLine(), EuclidLine()]
        let (page, engine) = pageAndEngineLines(st)
        XCTAssertFalse(page[0].isUntouchedLane)
        XCTAssertEqual(page[0].litOrderResolved.array, [0]); XCTAssertFalse(page[0].riffOnResolved)
        XCTAssertNil(agree(page[0], engine[0]))
    }

    private func laneStrikes(_ st0: PluginState, lane: Int, beats: Double) -> (riff: Int, notes: Int) {
        var st = st0
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan()
        let page = st.euclideousLinesResolved
        let input = FourfoldCompose.Input(lines: page, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: st.activeRiffResolved, soloMask: 0, locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let tap = Tap()
        let pool = NotePool(); for n in [48, 52, 55, 59] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        var beat = 0.0, ts = 0.0
        while beat < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 1024, forceColumn: 0, out: tap, diag: &diag)
            ts += 1024; beat += 1024 * 120 / 60 / 48_000
        }
        var riff = 0, notes = 0
        for r in router.rollRing.drain() where !r.isEnd && Int(r.part) >> 1 == lane { if r.part & 1 == 0 { riff += 1 } else { notes += 1 } }
        return (riff, notes)
    }

    /// The report: load a factory preset, switch on the spare lane 4 (PLAY on, a few hits, nothing else touched). The page shows the riff on and the notes off; the lane now plays its RIFF and its notes layer stays silent.
    func testASparePresetLaneSwitchedOnPlaysItsRiffAndNotItsNotes() {
        var st = EuclideousPresets.strideWalk()
        var lines = st.euclideousLinesResolved
        XCTAssertFalse(lines[3].enabledResolved, "the preset leaves lane 4 PLAY-off")
        lines[3].enabled = nil; lines[3].pulses = 4; lines[3].steps = 8
        st.euclideousLines = lines
        let shown = st.euclideousLinesResolved[3]
        XCTAssertTrue(shown.riffOnResolved); XCTAssertFalse(euclideousNotesLayerIsOn(shown))
        let s = laneStrikes(st, lane: 3, beats: 8)
        XCTAssertGreaterThan(s.riff, 0, "the riff plays")
        XCTAssertEqual(s.notes, 0, "the notes layer — shown as off — is silent")
    }
}

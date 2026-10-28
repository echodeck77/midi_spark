import XCTest

// LANE LOCK ferry (2026-10-21) — the pure layer: lock fields, grid lines, the snap decision, bars / beats left, persistence, the control-change list, layouts and the undo rules. The engine's side (the tick-exact
// landing) is in RouterTests; the page's looks are device-owed.
final class LaneLockTests: XCTestCase {

    // MARK: fixtures
    private func json(_ f: LaneLockFields) -> String {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return String(data: try! e.encode(f), encoding: .utf8)!
    }
    /// One mutation per lock field (and what it writes), each changing what the field RESOLVES to from a blank lane.
    private var mutations: [(String, (inout EuclidLine) -> Void)] {
        [
            ("steps", { $0.steps = 12 }), ("pulses", { $0.pulses = 5 }), ("rotate", { $0.rotate = 3 }),
            ("customHits", { $0.customHits = [true, false, false, true, false, false, true, false] }),
            ("hitsRequested", { $0.hitsRequested = 7 }), ("offsetRequested", { $0.offsetRequested = 3 }),
            ("tilt", { $0.tilt = 0.5 }), ("rate", { $0.rate = .r1_8 }), ("listenFollowMult", { $0.listenFollowMult = 1 }),
            ("direction", { $0.direction = .bkw }), ("patternMiss", { $0.patternMiss = true }),
            ("restartRhythmBars", { $0.restartRhythmBars = [2] }), ("restartMelodyPasses", { $0.restartMelodyPasses = [4, 2] }),
            ("riffOn", { $0.riffOn = false }), ("riffDir", { $0.riffDir = .pendulum }), ("riffInvert", { $0.riffInvert = true }),
            ("riffAdvanceEvery", { $0.riffAdvanceEvery = 3 }), ("riffAdvanceStep", { $0.riffAdvanceStep = true }), ("riffOnRest", { $0.riffOnRest = .tie }),
            ("riffLength", { $0.riffLength = 5 }), ("riffRotate", { $0.riffRotate = 2 }),   // riffShiftRequested is decode-only since the RIFF WINDOW ferry (resolves to riffRotate): still restored raw, no longer compared
            ("riffStride", { $0.riffStride = 3 }), ("melodyTranspose", { $0.melodyTranspose = 2 }),
            ("notesLitOrder", { $0.setLitOrder(EuclideousLitOrder.derived(litNotes: 0b0000_0101, top: false, top2: true)) }),
            ("notesOn", { $0.notesOn = false }), ("notesWhen", { $0.notesWhen = 0b10 }), ("notesChance", { $0.notesChance = 50 }),
            ("notesPlayAs", { $0.notesPlayAs = .roll }), ("notesReceivedOnly", { $0.notesReceivedOnly = true }),
        ]
    }

    // MARK: 1 — the lock fields
    func testEveryLockFieldIsReadWrittenAndCompared() {
        let blank = EuclidLine()
        for (name, m) in mutations {
            var l = blank; m(&l)
            let f = LaneLockFields(line: l)
            XCTAssertNotEqual(f.key(), LaneLockFields(line: blank).key(), "\(name): changing it must change what the lock compares")
            XCTAssertTrue(euclideousLockDeviated(line: blank, from: f), "\(name): a lane at the blank state is deviated from a lock holding it")
            XCTAssertFalse(euclideousLockDeviated(line: l, from: f), "\(name): a lane equal to L is not deviated")
            // write then read returns the same value
            var w = EuclidLine(); f.applied(to: &w)
            XCTAssertEqual(json(LaneLockFields(line: w)), json(f), "\(name): write → read round-trips")
            // the write puts back exactly the one thing that differed
            var back = l; LaneLockFields(line: blank).applied(to: &back)
            XCTAssertEqual(LaneLockFields(line: back).key(), LaneLockFields(line: blank).key(), "\(name): writing L back undoes it")
        }
    }
    func testNothingOutsideTheListIsHeld() {
        let blank = EuclidLine()
        let others: [(String, (inout EuclidLine) -> Void)] = [
            ("enabled", { $0.enabled = false }), ("gate", { $0.gate = 0.5 }), ("velocityAbsolute", { $0.velocityAbsolute = 60 }),
            ("octave", { $0.octave = 1 }), ("riffOctave", { $0.riffOctave = -1 }), ("notesGate", { $0.notesGate = 0.4 }), ("notesVelocity", { $0.notesVelocity = 70 }),
            ("muteCells16", { $0.muteCells16 = 0x00FF }), ("muteUnit", { $0.muteUnit = 1 }), ("sourceMode", { $0.sourceMode = .midi }),
            ("listenRhythmMode", { $0.listenRhythmMode = .with }), ("listenPitchMode", { $0.listenPitchMode = .shadow }), ("listenLevelMode", { $0.listenLevelMode = .duck }),
            // LISTEN REBUILT (2026-10-23): the nine new fields are not lock fields either — confirmed, not assumed.
            ("listenSource", { $0.listenSource = 2 }), ("listenRhythm", { $0.listenRhythm = .copy }), ("listenDelay", { $0.listenDelay = 3 }),
            ("listenFeel", { $0.listenFeel = 0.5 }), ("listenSpeed", { $0.listenSpeed = 1 }), ("listenDirection", { $0.listenDirection = .bkw }),
            ("listenPitch", { $0.listenPitch = .echo }), ("listenInterval", { $0.listenInterval = 3 }), ("listenOctave", { $0.listenOctave = 1 }),
        ]
        let f0 = LaneLockFields(line: blank)
        for (name, m) in others {
            var l = blank; m(&l)
            XCTAssertFalse(euclideousLockDeviated(line: l, from: f0), "\(name) is not a lock field — a lane differing only in it is not deviated")
            XCTAssertEqual(json(LaneLockFields(line: l)), json(f0), "\(name) is not read into the lock")
        }
    }
    func testAnEditThatIsPutBackIsNotADeviation() {
        // HITS 3 → 7 → 3 leaves hitsRequested at 3 where it was nil: the lane sounds and reads as before, so it is not deviated.
        var l = EuclidLine(); l.pulses = 3
        let locked = LaneLockFields(line: l)
        euclideousSliderCommit(.hits, &l, snapshot: l, newValue: 7)
        XCTAssertTrue(euclideousLockDeviated(line: l, from: locked))
        euclideousSliderCommit(.hits, &l, snapshot: l, newValue: 3)
        XCTAssertFalse(euclideousLockDeviated(line: l, from: locked))
        // …and writing L back restores the stored form exactly (hitsRequested nil again).
        locked.applied(to: &l)
        XCTAssertNil(l.hitsRequested)
    }
    func testWritingLBackRestoresChainsAndRequestedFieldsExactly() {
        for pinned in [false, true] {
            var locked = EuclidLine(); locked.pulses = 3; locked.steps = 16
            if pinned { locked.restartRhythmBars = [2]; locked.restartMelodyPasses = [] }
            locked.hitsRequested = 5; locked.offsetRequested = 2; locked.riffShiftRequested = 6
            let L = LaneLockFields(line: locked)
            var edited = locked
            edited.pulses = 9; edited.restartRhythmBars = [4, 4]; edited.restartMelodyPasses = [1]; edited.hitsRequested = nil
            edited.offsetRequested = 9; edited.riffShiftRequested = nil
            L.applied(to: &edited)
            XCTAssertEqual(edited.restartRhythmBars, locked.restartRhythmBars, "pinned=\(pinned)")
            XCTAssertEqual(edited.restartMelodyPasses, locked.restartMelodyPasses)
            XCTAssertEqual(edited.hitsRequested, 5); XCTAssertEqual(edited.offsetRequested, 2); XCTAssertEqual(edited.riffShiftRequested, 6)
            XCTAssertEqual(edited.pulses, 3)
        }
    }

    // MARK: 2 — grid lines (the page's 4/4 clock; margin 0.05 beats)
    private let m = 0.05
    private func next(_ g: EuclideousLockGrid, _ x: Double, _ bb: Double = 4) -> Double { euclideousLockNextLine(grid: g, beat: x, barBeats: bb, marginBeats: m) }
    func testGridLinesTwoBars() {
        // Paul's example, verbatim: "if set to 2 bars then it'll wrap on 2 or 4 (if we're on bar 3)".
        for x in stride(from: 0.0, to: 7.9, by: 0.25) { XCTAssertEqual(next(.bars2, x), 8, "bar 1 or 2 → the end of bar 2 (beat \(x))") }
        for x in stride(from: 8.0, to: 15.9, by: 0.25) { XCTAssertEqual(next(.bars2, x), 16, "bar 3 or 4 → the end of bar 4 (beat \(x))") }
    }
    func testGridLinesFourEightSixteenAndBeat() {
        XCTAssertEqual(next(.bars4, 9), 16, "4 BARS from bar 3 → the end of bar 4")
        XCTAssertEqual(next(.bars4, 21), 32, "4 BARS from bar 6 → the end of bar 8")
        XCTAssertEqual(next(.bars8, 40), 64, "8 BARS from bar 11 → the end of bar 16")
        XCTAssertEqual(next(.bars16, 66), 128, "16 BARS from bar 17 → the end of bar 32")
        XCTAssertEqual(next(.beat, 2.5), 3, "BEAT from beat 2.5 → beat 3")
        XCTAssertEqual(next(.bar1, 4.0), 8)
    }
    func testAnEditInsideTheMarginWaitsOneLine() {
        // 3.97 beats into bar 2 = beat 7.97; the end of bar 2 is 8 — 0.03 away, inside the 0.05 margin → 2 BARS skips to the end of bar 4.
        XCTAssertEqual(next(.bars2, 7.97), 16)
        XCTAssertEqual(next(.bars2, 7.94), 8, "0.06 away is outside the margin")
        // the same with other bar lengths
        for bb in [3.0, 7.0] {
            let p = 2 * bb
            XCTAssertEqual(next(.bars2, p - 0.03, bb), 2 * p)
            XCTAssertEqual(next(.bars2, p - 0.06, bb), p)
            XCTAssertEqual(next(.bars2, 0, bb), p)
        }
    }
    func testLinesNeverDependOnWhenTheEditWasMade() {
        // The line after any beat inside one period is the same line.
        for g in EuclideousLockGrid.allCases {
            let p = g.periodBeats(barBeats: 4)
            for k in 0..<3 {
                let lo = Double(k) * p
                let lines = stride(from: lo, to: lo + p - 0.1, by: p / 16).map { next(g, $0) }
                XCTAssertEqual(Set(lines).count, 1, "\(g): one line per period")
                XCTAssertEqual(lines.first, lo + p)
            }
        }
    }
    func testTheRenderSidesLineInAWindow() {
        // (after, through]: a line is decided exactly once however the windows fall.
        XCTAssertEqual(euclideousLockLineIn(grid: .bars2, barBeats: 4, after: 7.99, through: 8.01), 8)
        XCTAssertEqual(euclideousLockLineIn(grid: .bars2, barBeats: 4, after: 8.0, through: 8.05), nil, "the previous window (…, 8] claimed it")
        XCTAssertEqual(euclideousLockLineIn(grid: .bars2, barBeats: 4, after: 7.9, through: 8.0), 8, "the window's end is inclusive")
        XCTAssertNil(euclideousLockLineIn(grid: .bars4, barBeats: 4, after: 7.99, through: 8.01), "a 4-bar lane has no line at the end of bar 2")
        XCTAssertEqual(euclideousLockLineIn(grid: .bars4, barBeats: 4, after: 15.99, through: 16.01), 16)
        XCTAssertEqual(euclideousLockLineIn(grid: .beat, barBeats: 4, after: 2.9, through: 3.1), 3)
        XCTAssertEqual(euclideousLockLineIn(grid: .bar1, barBeats: 3, after: 2.9, through: 3.1), 3, "3/4: bars are 3 beats")
        XCTAssertEqual(euclideousLockLineIn(grid: .bar1, barBeats: 4, after: 0, through: 0.02, inclusiveStart: true), 0, "the first window after a start sits on a line")
        XCTAssertNil(euclideousLockLineIn(grid: .bar1, barBeats: 4, after: 0, through: 0.02))
        // every line in 32 bars is found exactly once by 64-frame windows at 120 BPM
        for g in EuclideousLockGrid.allCases {
            var found = 0, a = 0.0
            let step = 64.0 * 120.0 / 60.0 / 48_000.0
            while a < 128 { if euclideousLockLineIn(grid: g, barBeats: 4, after: a, through: a + step) != nil { found += 1 }; a += step }
            let expected = g == .beat ? 128 : Int(128 / (Double(g.rawValue) * 4))
            XCTAssertEqual(found, expected, "\(g): every line once")
        }
    }

    // MARK: 3 — the snap decision
    func testSnapDecision() {
        XCTAssertTrue(euclideousLockSnapsAtLine(deviated: true, held: false, editInFlight: false), "deviated, not held, settled → snap")
        XCTAssertFalse(euclideousLockSnapsAtLine(deviated: true, held: true, editInFlight: false), "held → no")
        XCTAssertFalse(euclideousLockSnapsAtLine(deviated: false, held: false, editInFlight: false), "not deviated → no")
        XCTAssertFalse(euclideousLockSnapsAtLine(deviated: true, held: false, editInFlight: true), "an edit still on its way → no; the next line decides")
        XCTAssertTrue(euclideousLockSnapsAtLine(deviated: true, held: false, editInFlight: false), "…and the next line, with it settled, snaps")
        XCTAssertTrue(euclideousLockSnapsNow(deviated: true, held: false, running: false), "page stopped: deviated and not held → at once")
        XCTAssertFalse(euclideousLockSnapsNow(deviated: true, held: true, running: false))
        XCTAssertFalse(euclideousLockSnapsNow(deviated: false, held: false, running: false))
        XCTAssertFalse(euclideousLockSnapsNow(deviated: true, held: false, running: true), "a running page waits for a line")
    }

    func testStatusLine() {
        XCTAssertEqual(euclideousLockStatusText(locked: false, deviated: true, grid: .bar1, countdown: .bars(2)), "UNLOCKED")
        XCTAssertEqual(euclideousLockStatusText(locked: true, deviated: false, grid: .bar1, countdown: nil), "LOCKED")
        XCTAssertEqual(euclideousLockStatusText(locked: true, deviated: true, grid: .bars4, countdown: .bars(3)), "LOCKED · BACK IN 3 BARS")
        XCTAssertEqual(euclideousLockStatusText(locked: true, deviated: true, grid: .bars4, countdown: .beats(2)), "LOCKED · BACK THIS BAR")
        XCTAssertEqual(euclideousLockStatusText(locked: true, deviated: true, grid: .beat, countdown: .beats(1)), "LOCKED · BACK ON THE BEAT")
        XCTAssertEqual(euclideousLockStatusText(locked: true, deviated: true, grid: .bar1, countdown: .held), "LOCKED · BACK AFTER YOU LET GO")
    }
    func testGridStrings() {
        XCTAssertEqual(EuclideousLockGrid.allCases.map { $0.segmentLabel }, ["BEAT", "1 BAR", "2", "4", "8", "16"])
        XCTAssertEqual(EuclideousLockGrid.bars8.accessibilityValue, "every 8 bars"); XCTAssertEqual(EuclideousLockGrid.beat.accessibilityValue, "every beat")
        XCTAssertEqual(EuclideousLockGrid.bar1.ruleLine, "EDITS RETURN ON THE NEXT BAR LINE"); XCTAssertEqual(EuclideousLockGrid.bars16.ruleLine, "EDITS RETURN ON THE NEXT 16-BAR LINE")
        XCTAssertEqual(EuclideousLockGrid.beat.ruleLine, "EDITS RETURN ON THE NEXT BEAT")
    }

    // MARK: 12 — persistence
    func testLocksRoundTripAndAPreFeatureDocumentHasNone() throws {
        var s = PluginState.makeInit()
        var line = s.euclideousLinesResolved[1]; line.pulses = 3; line.steps = 16; line.restartRhythmBars = [2]
        var locks = s.euclideousLocksResolved
        locks[1] = EuclideousLaneLock.locking(line, grid: .bars4)
        locks[2] = EuclideousLaneLock(on: false, grid: .bars8, state: nil)
        s.euclideousLocks = locks
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.euclideousLocksResolved, s.euclideousLocksResolved)
        XCTAssertTrue(back.euclideousLocksResolved[1].isLocked); XCTAssertEqual(back.euclideousLocksResolved[1].gridResolved, .bars4)
        XCTAssertEqual(back.euclideousLocksResolved[1].state?.pulses, 3)
        XCTAssertFalse(back.euclideousLocksResolved[2].isLocked); XCTAssertEqual(back.euclideousLocksResolved[2].gridResolved, .bars8, "the grid is kept while unlocked")
        // a pre-feature document: no key at all
        var pre = PluginState.makeInit(); pre.euclideousLocks = nil
        let preBack = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(pre))
        XCTAssertNil(preBack.euclideousLocks)
        XCTAssertEqual(preBack.euclideousLocksResolved.map { $0.isLocked }, [false, false, false, false])
        XCTAssertEqual(preBack.euclideousLocksResolved.map { $0.gridResolved }, [.bar1, .bar1, .bar1, .bar1], "the default grid is 1 BAR")
    }
    func testMalformedLockEntriesReadAsUnlockedNeverAsAFailedDocument() throws {
        let garbage = #"{"on": "yes", "grid": 7, "state": {"pulses": "many", "steps": 12}}"#.data(using: .utf8)!
        let lock = try JSONDecoder().decode(EuclideousLaneLock.self, from: garbage)
        XCTAssertEqual(lock.gridResolved, .bar1, "an unknown grid falls back to 1 BAR")
        XCTAssertFalse(lock.isLocked, "'on' was not a Bool")
        let noState = try JSONDecoder().decode(EuclideousLaneLock.self, from: #"{"on": true}"#.data(using: .utf8)!)
        XCTAssertFalse(noState.isLocked, "a lock with no locked state holds nothing")
        let notAnObject = try JSONDecoder().decode([EuclideousLaneLock].self, from: #"[5, {"on": true}]"#.data(using: .utf8)!)
        XCTAssertEqual(notAnObject.count, 2)
    }
    func testASessionSavedDeviatedOpensAtItsLockedState() throws {
        var s = PluginState.makeInit()
        var lines = s.euclideousLinesResolved
        lines[0].pulses = 3; lines[0].steps = 8
        let locked = LaneLockFields(line: lines[0])
        var locks = s.euclideousLocksResolved
        locks[0] = EuclideousLaneLock(on: true, grid: .bar1, state: locked)
        lines[0].pulses = 7; lines[0].riffDir = .reverse; lines[0].gate = 0.5     // deviated lock fields + one thing outside the lock
        lines[1].pulses = 6                                                         // an unlocked lane, also edited
        s.euclideousLines = lines; s.euclideousLocks = locks
        var loaded = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(s))
        loaded.normalizeLocksAtLoad()
        let after = loaded.euclideousLinesResolved
        XCTAssertEqual(after[0].pulses, 3); XCTAssertEqual(after[0].riffDir, locked.riffDir); XCTAssertNotEqual(after[0].riffDir, .reverse)
        XCTAssertEqual(after[0].gate, 0.5, "a field outside the lock is not touched")
        XCTAssertEqual(after[1].pulses, 6, "an unlocked lane opens as saved")
        // a session with no locks is untouched
        var plain = PluginState.makeInit(); plain.euclideousLines = lines
        let before = plain; plain.normalizeLocksAtLoad()
        XCTAssertEqual(plain, before)
    }
    func testFactoryPresetsHaveNoLocks() {
        for (name, make) in EuclideousPresets.all {
            XCTAssertTrue(make().euclideousLocksResolved.allSatisfy { !$0.isLocked }, "\(name): factory presets carry no locks")
        }
    }

    // MARK: 14 — the control-change list
    func testControlListHitsAndRiffDirection() {
        var l = EuclidLine(); l.pulses = 3
        let L = LaneLockFields(line: l)
        XCTAssertTrue(euclideousLockChangedControls(from: L, to: l).isEmpty, "L against itself lists nothing")
        euclideousSliderCommit(.hits, &l, snapshot: l, newValue: 7)
        l.riffDir = .reverse
        let set = euclideousLockChangedControls(from: L, to: l)
        XCTAssertEqual(set, [.hits, .riffDirection, .cometStrip], "HITS, the RIFF direction row and the comet strip — nothing else")
        XCTAssertEqual(euclideousLockChangedTabs(set), [.rhythm, .riff])
    }
    func testControlListNamesTheControlThatMoved() {
        let blank = EuclidLine(), L = LaneLockFields(line: blank)
        func changed(_ m: (inout EuclidLine) -> Void) -> Set<EuclideousLockControl> { var l = blank; m(&l); return euclideousLockChangedControls(from: L, to: l) }
        XCTAssertEqual(changed { $0.steps = 12 }, [.steps, .cometStrip])
        XCTAssertEqual(changed { $0.rotate = 3 }, [.offset, .cometStrip])
        XCTAssertEqual(changed { $0.tilt = 0.5 }, [.tilt, .cometStrip])
        XCTAssertEqual(changed { $0.rate = .r1_8 }, [.rate, .cometStrip])
        XCTAssertEqual(changed { $0.direction = .bkw }, [.direction, .cometStrip])
        XCTAssertEqual(changed { $0.patternMiss = true }, [.inv, .cometStrip])
        XCTAssertEqual(changed { $0.restartRhythmBars = [2] }, [.rhythmRestart, .cometStrip])
        XCTAssertEqual(changed { $0.restartMelodyPasses = [2] }, [.melodyRestart, .cometStrip])
        XCTAssertEqual(changed { $0.riffLength = 4 }, [.length, .cometStrip])
        XCTAssertEqual(changed { $0.riffStride = 2 }, [.stride, .cometStrip])
        XCTAssertEqual(changed { $0.melodyTranspose = 1 }, [.transpose, .cometStrip])
        XCTAssertEqual(changed { $0.notesChance = 50 }, [.notesChance, .cometStrip])
        XCTAssertEqual(changed { $0.notesPlayAs = .roll }, [.notesPlayAs, .cometStrip])
        XCTAssertEqual(changed { $0.setLitOrder(EuclideousLitOrder.derived(litNotes: 0b101, top: false, top2: false)) }, [.noteKey(0), .noteKey(2), .cometStrip])
        XCTAssertEqual(changed { $0.gate = 0.3; $0.enabled = false }, [], "MIX / play are not lock controls")
    }

    // MARK: 15 — layout
    func testLockCardFramesAtBothReferenceSizes() {
        for size in [CGSize(width: 380.67, height: 319), CGSize(width: 387, height: 319.67)] {
            let L = euclideousLockCardLayout(size: size)
            XCTAssertFalse(L.belowFloor)
            let bounds = CGRect(origin: .zero, size: size)
            for (i, f) in L.allFrames.enumerated() { XCTAssertTrue(bounds.contains(f), "\(size): frame \(i) \(f) crosses the card's edge") }
            XCTAssertEqual(L.numberCircle, CGRect(x: 10, y: 14, width: 24, height: 24))
            XCTAssertEqual(L.padlock, CGRect(x: 10, y: 52, width: 88, height: 88))
            XCTAssertEqual(L.summary.minX, 106); XCTAssertEqual(L.summary.maxX, size.width - 10, accuracy: 1e-9); XCTAssertEqual(L.summary.maxY, 140)
            XCTAssertEqual((0..<3).map { L.summaryRow($0).minY }, [52, 83, 114]); XCTAssertEqual(L.summaryRow(0).height, 26)
            XCTAssertEqual(L.summaryValue(0).minX, 170); XCTAssertEqual(L.summaryLabel(0).width, 64)
            XCTAssertEqual(L.snapBackLabel, CGRect(x: 10, y: 150, width: size.width - 20, height: 12))
            XCTAssertEqual(L.gridRow, CGRect(x: 10, y: 166, width: size.width - 20, height: 44)); XCTAssertEqual(L.selector.height, 32); XCTAssertEqual(L.selector.midY, L.gridRow.midY)
            XCTAssertEqual(L.segmentWidth, (size.width - 28) / 6, accuracy: 1e-9)
            XCTAssertEqual(L.segment(0).minX, 14); XCTAssertEqual(L.segment(5).maxX, size.width - 14, accuracy: 1e-9)
            XCTAssertEqual(L.segment(2).height, 24); XCTAssertEqual(L.segmentTouch(2).height, 44)
            XCTAssertEqual(L.ruleLine.minY, 222); XCTAssertEqual(L.gridTicks.minY, 240); XCTAssertEqual(L.gridTicks.maxY, 252)
            XCTAssertEqual(L.hint.minY, size.height - 24); XCTAssertEqual(L.hint.maxY, size.height - 10)
        }
        XCTAssertEqual(euclideousLockCardLayout(size: CGSize(width: 380.67, height: 319)).segmentWidth, 58.78, accuracy: 0.01, "the spec's 58.78 per segment")
        XCTAssertTrue(euclideousLockCardLayout(size: CGSize(width: 299, height: 319)).belowFloor)
        XCTAssertTrue(euclideousLockCardLayout(size: CGSize(width: 380, height: 249)).belowFloor)
    }
    func testBadgeAndTabWidths() {
        for (card, with, without) in [(380.67, 77.67, 87.17), (387.0, 79.25, 88.75)] {
            let inner = card - 20
            XCTAssertEqual(EuclideousLockBadge.tabWidth(innerWidth: inner, withBadge: false), without, accuracy: 0.01)
            XCTAssertEqual(EuclideousLockBadge.tabWidth(innerWidth: inner, withBadge: true), with, accuracy: 0.01)
            let b = EuclideousLockBadge.frame(cardWidth: card)
            XCTAssertEqual(b, CGRect(x: card - 44, y: 54, width: 34, height: 34)); XCTAssertEqual(b.maxX, card - 10); XCTAssertEqual(b.maxY, 88)
            let t = EuclideousLockBadge.touchFrame(cardWidth: card)
            XCTAssertEqual(t.height, 44); XCTAssertEqual(t.midY, b.midY)
            // the longest label ("LISTEN" + its dot, 11pt heavy mono with 1pt tracking) fits the narrower tab: no truncation
            let longest = 6 * (11 * 0.6 + 1) + 5 + 7
            XCTAssertLessThan(longest, with)
        }
    }
    func testHeaderThresholds() {
        let full = euclideousHeaderGroupWidths(compact: false), compact = euclideousHeaderGroupWidths(compact: true)
        XCTAssertEqual(full.brand, 295.88, accuracy: 0.01); XCTAssertEqual(compact.brand, 181)
        // THE NINE PORTS (2026-10-26): no OUTPUTS group — A needs brand + notes + utilities + two gaps, B needs brand + utilities + one gap
        let a = euclideousHeaderANeeds(full)
        let b = full.brand + full.utilities + full.gap
        // HOCKET ferry (2026-10-27): the utilities group grew by the pill (92) + sp8 — A 929.88 → 1029.88, B 487.88 → 587.88.
        // CARD BACKS ferry (2026-10-28): the 116 pt PATTERN | MIX switch + its sp8 (124) lifts A to 1153.88 (view 1185.88); B is unchanged — the switch rides row 2 with NOTES there, so row 1 (BRAND + UTILITIES) still decides B against C.
        XCTAssertEqual(a, 1153.88, accuracy: 0.01); XCTAssertEqual(b, 587.88, accuracy: 0.01)
        XCTAssertEqual(euclideousHeaderKind(containerW: 1153.8, isLandscape: true), .b); XCTAssertEqual(euclideousHeaderKind(containerW: 1153.9, isLandscape: true), .a)
        XCTAssertEqual(euclideousHeaderKind(containerW: 587.8, isLandscape: false), .c); XCTAssertEqual(euclideousHeaderKind(containerW: 587.9, isLandscape: false), .b)
        XCTAssertEqual(euclideousHeaderKind(containerW: 992, isLandscape: true), .b, "a 1024-wide landscape window (container 992) takes the two-row header")
        XCTAssertEqual(euclideousHeaderKind(containerW: 1158, isLandscape: true), .a, "the 1190 reference still gets the one-row header with the switch")   // (1158 ≥ 1153.88, 4.12 pt to spare)
        XCTAssertEqual(euclideousHeaderKind(containerW: 1162, isLandscape: true), .a, "an iPad Pro 11\" (1194) keeps the one-row header")
        XCTAssertEqual(euclideousHeaderKind(containerW: 1148, isLandscape: true), .b, "an iPad Air 11\" at 1180 now takes the two-row header (it had the one-row header before the switch)")
        XCTAssertEqual(euclideousHeaderKind(containerW: 1144, isLandscape: true), .b, "a 1176-wide view — the width a 376 pt card implies — takes the two-row header with the switch")
        XCTAssertEqual(euclideousHeaderKind(containerW: 1101, isLandscape: true), .b, "an iPad mini 6 at its full 1133 width takes the two-row header again")
        XCTAssertEqual(euclideousHeaderKind(containerW: 929.9, isLandscape: false), .b, "portrait never uses the one-row header")
    }

    // MARK: 11 (pure part) — undo
    func testEditsToALockedLaneRecordNoUndoStepAndUndoNeverMovesIt() {
        let base = (0..<4).map { _ in EuclidLine() }
        let locked = [false, true, false, false]
        // an edit to locked lane 1's lock fields: no step
        var e1 = base; e1[1].pulses = 6; e1[1].riffDir = .reverse
        XCTAssertFalse(euclideousLockEditIsUndoable(old: base, new: e1, locked: locked))
        // …but a MIX edit to the same lane (gate) is a normal edit
        var e2 = base; e2[1].gate = 0.4
        XCTAssertTrue(euclideousLockEditIsUndoable(old: base, new: e2, locked: locked))
        // an edit to unlocked lane 2 records
        var e3 = base; e3[2].pulses = 5
        XCTAssertTrue(euclideousLockEditIsUndoable(old: base, new: e3, locked: locked))
        // a gesture that moves a locked and an unlocked lane together records (the unlocked half is undoable)
        var e4 = base; e4[1].pulses = 6; e4[3].rotate = 2
        XCTAssertTrue(euclideousLockEditIsUndoable(old: base, new: e4, locked: locked))
        // unlock lane 1 and the same edit records as today
        XCTAssertTrue(euclideousLockEditIsUndoable(old: base, new: e1, locked: [false, false, false, false]))
        XCTAssertFalse(euclideousLockEditIsUndoable(old: base, new: base, locked: locked), "nothing changed, nothing to record")

        // lock lane 2 (index 1), edit it, edit lane 3, undo → lane 3 goes back, lane 2's fields do not change
        var now = base; now[1].pulses = 6; now[1].riffDir = .reverse; now[2].pulses = 5
        let restored = base                      // the step recorded before lane 3's edit holds lane 2 at its old fields
        let merged = euclideousLockMergeForUndo(restored: restored, current: now, locked: locked)
        XCTAssertEqual(merged[2].pulses, base[2].pulses, "lane 3 goes back")
        XCTAssertEqual(merged[1].pulses, 6); XCTAssertEqual(merged[1].riffDir, .reverse, "locked lane 2 keeps what it is now")
        var gateEdit = now; gateEdit[1].gate = 0.3
        var oldGate = base; oldGate[1].gate = 0.9
        XCTAssertEqual(euclideousLockMergeForUndo(restored: oldGate, current: gateEdit, locked: locked)[1].gate, 0.9, "a field outside the lock still undoes")
        XCTAssertEqual(euclideousLockMergeForUndo(restored: restored, current: now, locked: [false, false, false, false])[1].pulses, base[1].pulses, "unlocked: undo reaches it as today")
    }

    /// The question the VC's undo funnel actually asks (`onEdit`/`onEditStep` call this wrapper, not the pure rule above): "did this change touch only lock fields of locked lanes?"
    func testTheUndoFunnelsQuestionSkipsOnlyLockFieldEditsOfLockedLanes() {
        let base = (0..<4).map { _ in EuclidLine() }
        let one = EuclideousLaneLock.locking(base[1], grid: .bars4)
        let locks = [EuclideousLaneLock(), one, EuclideousLaneLock(), EuclideousLaneLock()]
        var lockField = base; lockField[1].pulses = 6; lockField[1].riffDir = .reverse
        XCTAssertTrue(euclideousLockChangeIsLockOnly(old: base, new: lockField, locks: locks), "a locked lane's lock fields: no undo step")
        var gate = base; gate[1].gate = 0.4
        XCTAssertFalse(euclideousLockChangeIsLockOnly(old: base, new: gate, locks: locks), "MIX is not a lock field: records")
        var both = base; both[1].pulses = 6; both[1].gate = 0.4
        XCTAssertFalse(euclideousLockChangeIsLockOnly(old: base, new: both, locks: locks), "one undoable field in the same edit: records")
        var other = base; other[2].pulses = 3
        XCTAssertFalse(euclideousLockChangeIsLockOnly(old: base, new: other, locks: locks), "an unlocked lane records")
        var twoLanes = base; twoLanes[1].pulses = 6; twoLanes[2].pulses = 3
        XCTAssertFalse(euclideousLockChangeIsLockOnly(old: base, new: twoLanes, locks: locks), "a gesture across a locked and an unlocked lane records")
        XCTAssertFalse(euclideousLockChangeIsLockOnly(old: base, new: base, locks: locks), "no change records as it always did")
        XCTAssertFalse(euclideousLockChangeIsLockOnly(old: base, new: lockField, locks: (0..<4).map { _ in EuclideousLaneLock() }), "nothing locked: byte-identical to before the feature")
        XCTAssertFalse(euclideousLockChangeIsLockOnly(old: base, new: lockField, locks: []), "no lock array yet (a fresh document): same")
    }

    func testSnapBackWordsAreAppendedToAnOutlinedControlsValue() {
        XCTAssertEqual(euclideousLockAppendSnapWords("7 of 16", outlined: true), "7 of 16, will snap back")
        XCTAssertEqual(euclideousLockAppendSnapWords("", outlined: true), "will snap back")
        XCTAssertEqual(euclideousLockAppendSnapWords("7 of 16", outlined: false), "7 of 16")
    }
    func testASummaryIsSpokenAsOneSentence() {
        var l = EuclidLine(); l.pulses = 3; l.steps = 16; l.rotate = 12; l.riffOn = true; l.riffDir = .pendulum; l.riffAdvanceStep = true; l.riffAdvanceEvery = 2
        l.setLitOrder(EuclideousLitOrder.derived(litNotes: 0b111, top: false, top2: false)); l.notesPlayAs = .roll; l.notesWhen = 0b10
        let f = LaneLockFields(line: l)
        XCTAssertEqual(euclideousLockSummaryAccessibility(lane: 0, locked: true, fields: f, base: l), "Locked rhythm 3 of 16, offset 4; riff pendulum by step every 2; notes roll, 3 notes, on rests")
        XCTAssertTrue(euclideousLockSummaryAccessibility(lane: 2, locked: false, fields: f, base: l).hasPrefix("Lane 3 would lock rhythm 3 of 16"))
        XCTAssertEqual(euclideousLockRhythmTag(f, autoRate: .r1_16), "3 OF 16 · OFFSET 4 · 1/16")
        XCTAssertEqual(euclideousLockRiffTag(f, base: l), "PEND · BY STEP ÷2")
        XCTAssertEqual(euclideousLockNotesTag(f, base: l), "ROLL · 3 NOTES · ON RESTS")
        var off = l; off.riffOn = false; off.notesOn = false
        XCTAssertEqual(euclideousLockRiffTag(LaneLockFields(line: off), base: off), "RIFF OFF"); XCTAssertEqual(euclideousLockNotesTag(LaneLockFields(line: off), base: off), "NOTES OFF")
        var none = l; none.setLitOrder(EuclideousLitOrder())
        XCTAssertEqual(euclideousLockNotesTag(LaneLockFields(line: none), base: none), "NO NOTES LIT")
    }
    // 10 — capture: a hold (300 ms, the solo function's threshold; 299 is a tap) makes what is playing the locked state; a tap on a locked lane unlocks and keeps what is playing.
    func testCaptureMakesWhatIsPlayingTheLockedStateAndTheThresholdIsTheSolosOwn() {
        var l = EuclidLine(); l.pulses = 3
        var lock = EuclideousLaneLock.locking(l, grid: .bars4)
        l.pulses = 7; l.riffDir = .reverse
        XCTAssertTrue(euclideousLockDeviated(line: l, from: lock.state!))
        lock = EuclideousLaneLock.locking(l, grid: lock.gridResolved)   // what `lockCommand(.capture)` does
        XCTAssertTrue(lock.isLocked); XCTAssertEqual(lock.gridResolved, .bars4, "capture keeps the grid")
        XCTAssertFalse(euclideousLockDeviated(line: l, from: lock.state!), "nothing is left to snap")
        XCTAssertTrue(euclideousLockChangedControls(from: lock.state!, to: l).isEmpty, "the outlines go")
        var tap = EuclideousSoloPress(); tap.touchDown(at: 0)
        XCTAssertEqual(tap.touchEnded(at: 0.299), .ended(latchToggles: true), "299 ms is a tap")
        var hold = EuclideousSoloPress(); hold.touchDown(at: 0); hold.holdTimerFired()
        XCTAssertTrue(hold.showsHeldLook, "the held look shows from 300 ms")
        XCTAssertEqual(hold.touchEnded(at: 0.3), .ended(latchToggles: false), "a hold never toggles")
        var unlocked = lock; unlocked.on = false; unlocked.state = nil   // what `lockCommand(.unlock)` does
        XCTAssertFalse(unlocked.isLocked); XCTAssertEqual(unlocked.gridResolved, .bars4, "the grid is kept so relocking reuses it")
    }
    func testLockedLanesPhrase() {
        XCTAssertEqual(euclideousLockedLanesPhrase([]), "")
        XCTAssertEqual(euclideousLockedLanesPhrase([2]), "lane 3 locked")
        XCTAssertEqual(euclideousLockedLanesPhrase([0, 2]), "lanes 1 and 3 locked")
        XCTAssertEqual(euclideousLockedLanesPhrase([3, 0, 1]), "lanes 1, 2 and 4 locked")
    }
    func testGridTicksMarkTheBarLinesThatAreGridLines() {
        // bar index 5 (beat 21): dot i is the line at the end of bar 5 + i, i.e. the line before bar index 6 + i
        let t4 = euclideousLockTicks(grid: .bars4, beat: 21, barBeats: 4)
        XCTAssertEqual(t4.count, 16)
        XCTAssertEqual((0..<16).filter { t4[$0] }, [2, 6, 10, 14], "dot i is the line before bar 6 + i: the lines before bars 8, 12, 16, 20 are the 4-bar lines")
        XCTAssertTrue(euclideousLockTicks(grid: .bar1, beat: 3, barBeats: 4).allSatisfy { $0 })
        XCTAssertEqual(euclideousLockTicks(grid: .beat, beat: 3, barBeats: 4), [true, true, true, true], "one per beat of the next bar")
        XCTAssertEqual(euclideousLockTicks(grid: .beat, beat: 3, barBeats: 3).count, 3)
        XCTAssertEqual((0..<16).filter { euclideousLockTicks(grid: .bars16, beat: 0, barBeats: 4)[$0] }, [15], "16 BARS: only the end of bar 16")
    }

    // MARK: the live words
    func testLiveWordPacking() {
        var revs: UInt32 = 0
        revs = EuclideousLockLive.bumped(revs, lane: 2)
        revs = EuclideousLockLive.bumped(revs, lane: 2)
        revs = EuclideousLockLive.bumped(revs, lane: 0)
        let w = EuclideousLockLive.word(held: 0b0101, revs: revs)
        XCTAssertTrue(EuclideousLockLive.hasSpoken(w)); XCTAssertEqual(EuclideousLockLive.heldMask(w), 0b0101); XCTAssertEqual(EuclideousLockLive.revs(w), revs)
        XCTAssertEqual((0..<4).map { EuclideousLockLive.rev(revs, lane: $0) }, [1, 0, 2, 0])
        XCTAssertFalse(EuclideousLockLive.hasSpoken(0))
        var r = revs; for _ in 0..<255 { r = EuclideousLockLive.bumped(r, lane: 2) }
        XCTAssertEqual(EuclideousLockLive.rev(r, lane: 2), 1, "a revision wraps inside its own byte")
        XCTAssertEqual(EuclideousLockLive.rev(r, lane: 3), 0, "…without touching its neighbour")
    }

    // MARK: 4 — bars and beats left
    func testBarsAndBeatsLeftEqualTheBarLinesToTheNextLine() {
        for g in EuclideousLockGrid.allCases {
            var x = 0.0
            while x < 64 {
                let line = next(g, x)
                // an independent count of bar lines in (x, line]
                var bars = 0, b = (x / 4).rounded(.down) * 4 + 4
                while b <= line + 1e-9 { bars += 1; b += 4 }
                let beats = max(1, Int((line - x - 1e-9).rounded(.up)))
                let c = euclideousLockCountdown(grid: g, beat: x, barBeats: 4, marginBeats: m, held: false)
                if g == .beat {
                    XCTAssertEqual(c, .beats(beats), "BEAT at \(x)")
                } else {
                    let n = max(1, bars)
                    XCTAssertEqual(c, n <= 1 ? .beats(beats) : .bars(n), "\(g) at \(x): bars until the last one, then beats")
                }
                x += 0.25
            }
        }
        XCTAssertEqual(euclideousLockCountdown(grid: .bars4, beat: 3, barBeats: 4, marginBeats: m, held: true), .held, "held → no number, the lane waits for a lift")
    }

    func testRandomModeOnALockedLaneSaysWhy() {
        XCTAssertEqual(euclideousLockRandomIdleCaption(laneLocked: true), "LOCKED · UNLOCK TO ROLL")
        XCTAssertEqual(euclideousLockRandomIdleCaption(laneLocked: false), "THROW A NEW ONE · TWEAK WHAT'S PLAYING")
    }
}

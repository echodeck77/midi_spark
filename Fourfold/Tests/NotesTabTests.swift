//  NotesTabTests.swift
//  NOTES TAB ferry (2026-10-19, "octave and velocity go, WHEN RIFF, seven ways to PLAY AS, CHANCE and RECEIVED; FILL leaves ON REST"): the pure surface —
//  the model + migration (§5, test 10), the engine functions (§6-§7, tests 2-6), the layout (§1/§3/§4, test 12) and the displays (§10, test 11).
//  The Router side (tests 1, 7-9, 13, 14) lives in RouterTests next to the harness it needs.
//
//  The example lane (§13): riff ranks by column [8, 0, 8, 6, 0, 6, 5, 0] (0 = a rest), the hits on steps 1, 3, 5, 6, 8 read columns 6, 8, 2, 3, 5 — so the hits on
//  1 and 6 play the riff (A♭3, C4) and the hits on 3, 5, 8 are rests. KEY C MINOR pool: C3 D3 E♭3 F3 G3 A♭3 B♭3 + the octave copy C4. Lit in this order: rank 8, 5, 6.

import XCTest

final class NotesTabTests: XCTestCase {

    private func decode(_ json: String) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: Data(json.utf8)) }
    private func roundTrip(_ l: EuclidLine) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l)) }
    private func jsonObject(_ l: EuclidLine) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(l)) as! [String: Any]
    }

    // MARK: 10. persistence and migration

    func testAPreFeatureDocumentGetsTheSoundPreservingWhen() throws {
        // riff OFF: the lit notes sounded on every hit -> both, whatever ON REST said
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":false,"litNotes":16,"riffOnRest":"SKIP"}"#).notesWhenResolved, 0b11)
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":false,"litNotes":16,"riffOnRest":"TIE"}"#).notesWhenResolved, 0b11)
        // riff ON: SKIP and TIE silenced the lit notes on a rest hit -> PLAYS only; FILL and REPEAT sounded them -> both
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16,"riffOnRest":"SKIP"}"#).notesWhenResolved, 0b01)
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16}"#).notesWhenResolved, 0b01, "no ON REST stored = SKIP")
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16,"riffOnRest":"TIE"}"#).notesWhenResolved, 0b01)
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16,"riffOnRest":"REPEAT"}"#).notesWhenResolved, 0b11)
        let fill = try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16,"riffOnRest":"FILL"}"#)
        XCTAssertEqual(fill.notesWhenResolved, 0b11, "FILL sounded the lit notes on a rest, so it becomes SKIP with both"); XCTAssertEqual(fill.riffOnRestResolved, .skip)
        // the defaults of everything else
        let l = try decode(#"{"target":0,"pulses":5,"steps":8}"#)
        XCTAssertEqual(l.notesChanceResolved, 100); XCTAssertEqual(l.notesPlayAsResolved, .chord); XCTAssertFalse(l.notesReceivedOnlyResolved)
    }
    func testALaneMadeInThisBuildKeepsBothWhenWhenIsUntouchedEvenOnTie() throws {
        var l = EuclidLine(target: 0, pulses: 5, steps: 8); l.riffOn = true; l.riffOnRest = .tie
        XCTAssertEqual(l.notesWhenResolved, 0b11, "a fresh lane: PLAYS and RESTS both on")
        XCTAssertNotNil(try jsonObject(l)["notesWhen"], "the encoder always writes notesWhen, so the migration only ever meets an old document")
        let back = try roundTrip(l)
        XCTAssertEqual(back.notesWhenResolved, 0b11); XCTAssertEqual(back.riffOnRestResolved, .tie)
        l.notesWhen = 0b01
        XCTAssertEqual(try roundTrip(l).notesWhenResolved, 0b01, "a stored PLAYS-only survives")
    }
    func testWhenChanceAndWayDecodeToLegalValues() throws {
        func l(_ extra: String) throws -> EuclidLine { try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":false,"# + extra + "}") }
        XCTAssertEqual(try l(#""notesWhen":0"#).notesWhenResolved, 0b11, "neither bit -> both")
        XCTAssertEqual(try l(#""notesWhen":6"#).notesWhenResolved, 0b10, "higher bits dropped")
        XCTAssertEqual(try l(#""notesWhen":2"#).notesWhenResolved, 0b10)
        XCTAssertEqual([60, 63, 0, 200, 25, 50, 75, 100, 37, 38, -4].map { EuclidLine.nearestLegalNotesChance($0) }, [50, 75, 25, 100, 25, 50, 75, 100, 25, 50, 25])
        for (stored, want) in [(60, 50), (63, 75), (0, 25), (200, 100)] {
            XCTAssertEqual(try l(#""notesChance":\#(stored)"#).notesChance, want, "\(stored) is stored already normalised")
        }
        XCTAssertEqual(try l(#""notesPlayAs":"WIGGLE""#).notesPlayAsResolved, .chord, "an unknown way decodes as CHORD")
        XCTAssertEqual(try l(#""notesPlayAs":"BOUNCE""#).notesPlayAsResolved, .bounce)
        XCTAssertEqual(try l(#""notesPlayAs":7"#).notesPlayAsResolved, .chord, "a wrong-typed way is missing, not a whole-session reset")
    }
    func testTheLitOrderIsTheSourceOfTruthAndTheLegacyTrioFollowsIt() throws {
        // a lane without an order takes it from litNotes / TOP 2 / TOP: ranks low to high, then TOP 2, then TOP
        let old = try decode(#"{"target":0,"pulses":5,"steps":8,"litNotes":177,"topLit":true,"top2Lit":true}"#)   // 177 = ranks 1, 5, 6, 8
        XCTAssertEqual(old.litOrderResolved.array, [0, 4, 5, 7, 8, 9])
        // an invalid stored order (a repeat, a 10, too long) counts as missing
        for bad in ["[7,4,7]", "[10]", "[0,1,2,3,4,5,6,7,8,9,0]"] {
            let l = try decode(#"{"target":0,"pulses":5,"steps":8,"litNotes":16,"notesLitOrder":\#(bad)}"#)
            XCTAssertEqual(l.litOrderResolved.array, [4], "\(bad) falls back to 5.2")
        }
        // a valid one wins, and the trio is rewritten from it — read back and as encoded
        let l = try decode(#"{"target":0,"pulses":5,"steps":8,"litNotes":1,"notesLitOrder":[7,4,5,9]}"#)
        XCTAssertEqual(l.litOrderResolved.array, [7, 4, 5, 9])
        XCTAssertEqual(l.litNotesResolved, 0b1011_0000); XCTAssertTrue(l.topLitResolved); XCTAssertFalse(l.top2LitResolved)
        XCTAssertEqual(l.litNotes, 0b1011_0000, "the stored trio agrees with the order after decode"); XCTAssertEqual(l.topLit, true); XCTAssertEqual(l.top2Lit, false)
        // every writer goes through setLitOrder: the encoder writes the trio from the order
        var m = EuclidLine(target: 0, pulses: 5, steps: 8)
        var o = EuclideousLitOrder(); o.append(7); o.append(4); o.append(5); o.append(8)
        m.setLitOrder(o)
        let json = try jsonObject(m)
        XCTAssertEqual(json["notesLitOrder"] as? [Int], [7, 4, 5, 8])
        XCTAssertEqual(json["litNotes"] as? Int, 0b1011_0000); XCTAssertEqual(json["top2Lit"] as? Bool, true); XCTAssertEqual(json["topLit"] as? Bool, false)
        let back = try roundTrip(m)
        XCTAssertEqual(back.litOrderResolved.array, [7, 4, 5, 8]); XCTAssertEqual(back, m, "every field round-trips")
    }
    func testTheNotesTabFieldsAllRoundTripAndPerNoteShiftsStayDecodable() throws {
        var l = EuclidLine(target: 0, pulses: 5, steps: 8)
        l.notesWhen = 0b10; l.notesChance = 75; l.notesPlayAs = .build; l.notesReceivedOnly = true
        l.noteOctShifts = [1, -1, 0, 0, 0, 0, 0, 1]; l.notesVelOffset = -20
        var o = EuclideousLitOrder(); o.append(9); o.append(0); l.setLitOrder(o)
        let back = try roundTrip(l)
        XCTAssertEqual(back, l)
        XCTAssertEqual(back.notesWhenResolved, 0b10); XCTAssertEqual(back.notesChanceResolved, 75); XCTAssertEqual(back.notesPlayAsResolved, .build)
        XCTAssertTrue(back.notesReceivedOnlyResolved); XCTAssertEqual(back.noteOctShiftsResolved, [1, -1, 0, 0, 0, 0, 0, 1]); XCTAssertEqual(back.notesVelOffsetResolved, -20)
    }

    // MARK: the example lane, pure

    private let exBuf = [true, false, true, false, true, true, false, true]          // hits on steps 1, 3, 5, 6, 8
    private let exRanks = [8, 0, 8, 6, 0, 6, 5, 0]                                     // the riff's written ranks by column (0 = a rest)
    private let exPool = [48, 50, 51, 53, 55, 56, 58]                                  // C3 D3 E♭3 F3 G3 A♭3 B♭3 (+ the octave copy C4 = rank 8)
    private func walk(advanceStep: Bool = true, chains: EuclideousLaneRestartChains = .off, rotate: Int = 5) -> EuclideousNotesWalk {
        EuclideousNotesWalk(n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, chains: chains, legacySpanBeats: 0, advanceStep: advanceStep,
                            riffDir: .forward, stride: 1, length: 8, rotate: rotate, seed: 0, every: 1)
    }
    private func rankAt(_ ranks: [Int]) -> (Int, Double) -> Int { { c, _ in ranks[c] } }
    private func list(_ order: [Int], pool: [Int], received: Bool = false) -> EuclideousNotesList {
        var o = EuclideousLitOrder(); for p in order { o.append(p) }
        return euclideousNotesPlayList(order: o, poolCount: pool.count, receivedOnly: received) { rank in
            riffResolve(rank: rank, oct: 0, n: pool.count, wrap: .fold, asc: { pool[$0] })
        }
    }
    private func pitches(_ l: EuclideousNotesList) -> [Int] { (0..<l.count).map { l.pitch($0) } }
    private func pitches(_ l: EuclideousNotesList, _ pick: EuclideousNotesPick) -> [Int] { (0..<pick.count).map { l.pitch(pick[$0]) } }


    // MARK: 3. CHANCE
    func testChanceIsReplayExactAndThinsAboutTheRightShare() {
        for h in 0..<64 as Range<Int64> { XCTAssertTrue(euclideousNotesChanceAllows(chance: 100, lane: 0, h: h)) }
        for h in 0..<64 as Range<Int64> { XCTAssertEqual(euclideousNotesChanceRoll(lane: 2, h: h), euclideousNotesChanceRoll(lane: 2, h: h)); XCTAssertTrue((0..<100).contains(euclideousNotesChanceRoll(lane: 2, h: h))) }
        func share(_ chance: Int, lane: Int = 0) -> Double { Double((0..<10_000 as Range<Int64>).filter { euclideousNotesChanceAllows(chance: chance, lane: lane, h: $0) }.count) / 10_000 }
        XCTAssertEqual(share(50), 0.5, accuracy: 0.02); XCTAssertEqual(share(25), 0.25, accuracy: 0.02); XCTAssertEqual(share(75), 0.75, accuracy: 0.02)
        let a = (0..<200 as Range<Int64>).map { euclideousNotesChanceAllows(chance: 50, lane: 0, h: $0) }, b = (0..<200 as Range<Int64>).map { euclideousNotesChanceAllows(chance: 50, lane: 1, h: $0) }
        XCTAssertNotEqual(a, b, "two lanes thin differently")
        // h is the hit ordinal since the MELODY origin: from a transport start at beat 4 the answers match the run from beat 0, hit for hit; MELODY 1 repeats the same thinning every pass
        var melodyOne = EuclideousLaneRestartChains.off; melodyOne.melody = .from([1]); melodyOne.barBeats = 4; melodyOne.lapBeats = 4
        let hs = (0..<40).map { euclideousNotesHitOrdinal(buf: exBuf, w: walk(chains: melodyOne), tick: Int64($0)) }
        let hitTicks = (0..<40).filter { exBuf[$0 % 8] }
        for t in hitTicks { XCTAssertEqual(hs[t], Int64(([0, 2, 4, 5, 7].firstIndex(of: t % 8))!), "MELODY 1: every pass counts its hits from 0 again (tick \(t))") }
        let free = (0..<40).filter { exBuf[$0 % 8] }.map { euclideousNotesHitOrdinal(buf: exBuf, w: walk(), tick: Int64($0)) }
        XCTAssertEqual(free, (0..<free.count).map { Int64($0) }, "FREE: the ordinal counts every hit since the origin")
    }

    // MARK: 4. the play list
    func testThePlayListFollowsTheLitOrderAndTheReceivedNotes() {
        XCTAssertEqual(pitches(list([7, 4, 5], pool: exPool)), [60, 55, 56], "the example's list is C4, G3, A♭3")
        let held = [48, 51, 55]                                                            // C E♭ G held: ranks C3 E♭3 G3 C4 E♭4 G4 C5 E♭5
        XCTAssertEqual(pitches(list([0, 1, 2, 3, 4], pool: held)), [48, 51, 55, 60, 63], "RECEIVED off: ranks 1-5")
        XCTAssertEqual(pitches(list([0, 1, 2, 3, 4], pool: held, received: true)), [48, 51, 55], "RECEIVED on: the octave copies stay out")
        XCTAssertEqual(pitches(list([0, 1, 2, 9], pool: held, received: true)), [48, 51, 55], "TOP lit after rank 3 adds nothing — it is G3 again")
        XCTAssertEqual(pitches(list([9], pool: held)), [55]); XCTAssertEqual(pitches(list([8], pool: held)), [51, 55], "TOP 2 keeps its pair: the second-highest and the highest")
        XCTAssertEqual(pitches(list([8], pool: [60])), [60], "one received note: TOP 2 is that note")
        XCTAssertEqual(pitches(list([0, 4, 9, 8], pool: [])), [], "nothing held: the list is empty")
        // the rank each entry stands for (the mask's representative rank reads it)
        let l = list([7, 9, 8], pool: exPool)
        XCTAssertEqual((0..<l.count).map { l.rank($0) }, [8, 7, 6], "C4 = rank 8, TOP = rank 7, TOP 2 adds rank 6 (rank 7 is already in)")
    }

    // MARK: 5. the seven ways
    func testTheSevenWaysOnTheExampleListForK0To7() {
        let l = list([7, 4, 5], pool: exPool)   // C4, G3, A♭3 = 60, 55, 56
        func seq(_ way: EuclidNotesPlayAs) -> [[Int]] { (0..<8).map { pitches(l, euclideousNotesWayPick(list: l, way: way, k: $0)) } }
        XCTAssertEqual(seq(.chord), Array(repeating: [60, 55, 56], count: 8))
        XCTAssertEqual(seq(.roll), (0..<8).map { $0 % 2 == 0 ? [55, 56, 60] : [60, 56, 55] })
        XCTAssertEqual(seq(.run), Array(repeating: [60, 55, 56], count: 8))
        XCTAssertEqual(seq(.cycle), [[60], [55], [56], [60], [55], [56], [60], [55]])
        XCTAssertEqual(seq(.bounce), [[60], [55], [56], [55], [60], [55], [56], [55]])
        XCTAssertEqual(seq(.split).map { Set($0) }, [[55], [56, 60], [55], [56, 60], [55], [56, 60], [55], [56, 60]].map { Set($0) })
        XCTAssertEqual(seq(.build).map { Set($0) }, [[60], [60, 55], [60, 55, 56], [60], [60, 55], [60, 55, 56], [60], [60, 55]].map { Set($0) })
        // one note: every way plays it every time; two notes: BOUNCE alternates; an empty list plays nothing
        let one = list([0], pool: exPool)
        for way in EuclidNotesPlayAs.allCases { for k in 0..<5 { XCTAssertEqual(pitches(one, euclideousNotesWayPick(list: one, way: way, k: k)), [48], "\(way.rawValue) k \(k)") } }
        let two = list([7, 4], pool: exPool)
        XCTAssertEqual((0..<4).map { pitches(two, euclideousNotesWayPick(list: two, way: .bounce, k: $0)) }, [[60], [55], [60], [55]])
        for way in EuclidNotesPlayAs.allCases { XCTAssertEqual(euclideousNotesWayPick(list: EuclideousNotesList(), way: way, k: 3).count, 0) }
    }

    func testTheCountRunsInBlocksOf1024HitsFromTheMelodyOrigin() {
        let w = walk(advanceStep: false)
        // FREE melody: the hit with h = 1024 has k = 0; the one with h = 1023 has k equal to the count over hits 0-1022 (1023 when both are chosen, otherwise counted)
        XCTAssertEqual(euclideousNotesCountBefore(buf: exBuf, w: w, tick: 0, h: 1024, when: 0b11, chance: 100, lane: 0, thisBeat: 0, rankAt: rankAt(exRanks)), 0)
        XCTAssertEqual(euclideousNotesCountBefore(buf: exBuf, w: w, tick: 0, h: 1023, when: 0b11, chance: 100, lane: 0, thisBeat: 0, rankAt: rankAt(exRanks)), 1023)
        // one-sided WHEN: count the rest hits among hit ordinals 0-1022 by the closed form (the walk is ADV HIT here, so the column of hit h' is a function of h')
        var restCount = 0
        for hp in 0..<1023 { let col = euclideousRiffColumn(ordinal: Int64(hp), every: 1, direction: .forward, length: 8, stride: 1, shift: 5, seed: 0); if exRanks[col] < 1 { restCount += 1 } }
        XCTAssertEqual(euclideousNotesCountBefore(buf: exBuf, w: w, tick: 0, h: 1023, when: 0b10, chance: 100, lane: 0, thisBeat: 0, rankAt: rankAt(exRanks)), restCount)
        XCTAssertEqual(euclideousNotesCountBefore(buf: exBuf, w: w, tick: 0, h: 2047, when: 0b10, chance: 100, lane: 0, thisBeat: 0, rankAt: rankAt(exRanks)),
                       (1024..<2047).filter { exRanks[Int(euclideousRiffColumn(ordinal: Int64($0), every: 1, direction: .forward, length: 8, stride: 1, shift: 5, seed: 0))] < 1 }.count)
    }

    // MARK: 7. ROLL and RUN timing (pure)
    func testRollSpacingAndRunSlotsMatchTheFerrysExamples() {
        func ms(_ beats: Double, bpm: Double) -> Double { beats * 60_000 / bpm }
        // 110 BPM, three notes: a 1/8 lane whose next hit is two steps (1 beat) away, GATE 50 (length 0.5 beat): s is 25 ms
        XCTAssertEqual(ms(euclideousNotesRollSpacingBeats(m: 3, gapBeats: 1, lenBeats: 0.5, legato: false, tempo: 110), bpm: 110), 25, accuracy: 1e-9)
        // a 1/32 lane (68.18 ms step) whose next hit is one step away: 8.52 ms at GATE 50, 17.05 ms at GATE 100 (legato: the length is ignored)
        let step = 0.125
        XCTAssertEqual(ms(euclideousNotesRollSpacingBeats(m: 3, gapBeats: step, lenBeats: step * 0.5, legato: false, tempo: 110), bpm: 110), 8.52, accuracy: 0.01)
        XCTAssertEqual(ms(euclideousNotesRollSpacingBeats(m: 3, gapBeats: step, lenBeats: step, legato: true, tempo: 110), bpm: 110), 17.05, accuracy: 0.01)
        XCTAssertEqual(euclideousNotesRollSpacingBeats(m: 1, gapBeats: 1, lenBeats: 1, legato: false, tempo: 110), 0)
        // RUN: three notes on a 1/8 step at 110 BPM start 0, 1/6 and 1/3 of a beat after the hit (90.91 ms apart)
        let slot = euclideousNotesRunSlotBeats(stepBeats: 0.5, m: 3)
        XCTAssertEqual(slot, 1.0 / 6.0, accuracy: 1e-12); XCTAssertEqual(ms(slot, bpm: 110), 90.91, accuracy: 0.01)
        XCTAssertEqual(euclideousNotesRunSlotBeats(stepBeats: 0.5, m: 2), 0.25)
    }

    // MARK: 12. layout
    private func near(_ r: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.minX, x, accuracy: 0.01, "\(msg) x", file: file, line: line); XCTAssertEqual(r.minY, y, accuracy: 0.01, "\(msg) y", file: file, line: line)
        XCTAssertEqual(r.width, w, accuracy: 0.01, "\(msg) w", file: file, line: line); XCTAssertEqual(r.height, h, accuracy: 0.01, "\(msg) h", file: file, line: line)
    }
    func testTheLayoutAtTheReferenceMatchesTheFerrysFrames() {
        // the reference card 358.5 × 312: content x 10-348.5 (338.5 wide), y 94-302 (208 tall) — card coordinates below subtract (10, 94)
        let l = euclideousNotesTabLayout(contentAreaH: 208, fullWidth: 338.5)
        near(l.strip, 0, 0, 35, 208, "strip")
        near(l.keyRow, 38, 0, 300.5, 82, "key row"); near(l.whenRow, 38, 86, 300.5, 38, "WHEN row"); near(l.playAsRow, 38, 128, 300.5, 38, "PLAY AS row"); near(l.soundRow, 38, 170, 300.5, 38, "SOUND ONLY row")
        let ranksX: [(CGFloat, CGFloat)] = [(48, 75.85), (77.85, 105.7), (107.7, 135.55), (137.55, 165.4), (167.4, 195.25), (197.25, 225.1), (227.1, 254.95), (256.95, 284.8), (290.8, 318.65), (320.65, 348.5)]
        for (i, k) in l.keys.enumerated() { near(k, ranksX[i].0 - 10, 0, ranksX[i].1 - ranksX[i].0, 82, "key \(i)") }
        near(l.whenLabel, 38, 86, 48, 38, "WHEN label"); near(l.plays, 90, 86, 76.25, 38, "PLAYS"); near(l.rests, 170.25, 86, 76.25, 38, "RESTS"); near(l.chance, 250.5, 86, 88, 38, "CHANCE")
        near(l.playAsLabel, 38, 128, 48, 38, "PLAY AS label"); near(l.playAs, 90, 128, 248.5, 38, "PLAY AS button")
        near(l.soundLabel, 38, 170, 48, 38, "SOUND ONLY label"); near(l.received, 90, 170, 248.5, 38, "RECEIVED")
        near(l.picker, 0, 0, 338.5, 208, "picker"); near(l.pickerHeader, 6, 6, 326.5, 18, "picker header"); near(l.pickerClose, 302.5, 6, 30, 18, "close")
        let top: [(CGFloat, CGFloat)] = [(16, 122.17), (126.17, 232.33), (236.33, 342.5)], bottom: [(CGFloat, CGFloat)] = [(16, 94.625), (98.625, 177.25), (181.25, 259.875), (263.875, 342.5)]
        for (i, c) in top.enumerated() { near(l.pickerCells[i], c.0 - 10, 122 - 94, c.1 - c.0, 85, "top cell \(i)") }
        for (i, c) in bottom.enumerated() { near(l.pickerCells[3 + i], c.0 - 10, 211 - 94, c.1 - c.0, 85, "bottom cell \(i)") }
        XCTAssertFalse(l.underFloor)
    }
    func testTheLayoutAtNarrowerContentWidthsFlagsOnlyWhatFallsUnderTheFloors() {
        let at300 = euclideousNotesTabLayout(contentAreaH: 208, fullWidth: 300)
        XCTAssertEqual(at300.keys[0].width, 24, accuracy: 0.01); XCTAssertEqual(at300.plays.width, 57, accuracy: 0.01); XCTAssertEqual(at300.rests.width, 57, accuracy: 0.01)
        XCTAssertEqual(at300.playAs.width, 210, accuracy: 0.01); XCTAssertFalse(at300.underFloor, "keys exactly at the 24 floor: no flag")
        let at290 = euclideousNotesTabLayout(contentAreaH: 208, fullWidth: 290)
        XCTAssertEqual(at290.keys[0].width, 23, accuracy: 0.01); XCTAssertTrue(at290.underFloor); XCTAssertEqual(at290.floorFlags.count, 1)
        // heights: the WHEN row stays 38 and the key row takes the rest of the upper zone; a short card flags the key row
        let short = euclideousNotesTabLayout(contentAreaH: 180, fullWidth: 338.5)
        XCTAssertEqual(short.whenRow.height, 38); XCTAssertEqual(short.keyRow.height, 54, accuracy: 0.01); XCTAssertTrue(short.underFloor)
    }
    func testPreviewBarsAndPlaceNumbersFollowThePlayList() {
        let l = list([7, 4, 5], pool: exPool)   // C4 (rank 8), G3 (rank 5), A♭3 (rank 6)
        // CHORD / CYCLE bars span their row; RUN splits the row by m; ROLL is 76% wide with the stagger
        XCTAssertEqual(euclideousNotesPreviewBars(list: l, way: .chord, k: 0), [.init(rank: 8, x: 0, w: 1), .init(rank: 5, x: 0, w: 1), .init(rank: 6, x: 0, w: 1)])
        XCTAssertEqual(euclideousNotesPreviewBars(list: l, way: .cycle, k: 4), [.init(rank: 5, x: 0, w: 1)])
        let run = euclideousNotesPreviewBars(list: l, way: .run, k: 0)
        XCTAssertEqual(run.map { $0.x }, [0, 1.0 / 3, 2.0 / 3]); XCTAssertEqual(run.map { $0.w }, [1.0 / 3, 1.0 / 3, 1.0 / 3])
        let roll = euclideousNotesPreviewBars(list: l, way: .roll, k: 0)   // k even: low to high = G3, A♭3, C4
        XCTAssertEqual(roll.map { $0.rank }, [5, 6, 8]); XCTAssertEqual(roll.map { $0.w }, [0.76, 0.76, 0.76])
        for (b, want) in zip(roll, [0.0, 0.12, 0.24]) { XCTAssertEqual(b.x, want, accuracy: 1e-12) }
        XCTAssertEqual(euclideousNotesPreviewBars(list: list([7], pool: exPool), way: .run, k: 0), [.init(rank: 8, x: 0, w: 1)], "one note spans its row")
        XCTAssertEqual(euclideousNotesPreviewBars(list: list([9], pool: Array(40..<50)), way: .chord, k: 0), [], "TOP over a pool of ten sits on no grid row")
        // 11. place numbers: CYCLE on the example gives C4 1, G3 2, A♭3 3; CHORD / ROLL / SPLIT none
        let cycle = euclideousNotesPlaceNumbers(list: l, way: .cycle)
        XCTAssertEqual(cycle[7], "1"); XCTAssertEqual(cycle[4], "2"); XCTAssertEqual(cycle[5], "3"); XCTAssertNil(cycle[0])
        for way in [EuclidNotesPlayAs.chord, .roll, .split] { XCTAssertEqual(euclideousNotesPlaceNumbers(list: l, way: way).compactMap { $0 }, []) }
        // with C E♭ G held, ranks 1-5 lit and RECEIVED on: C3 1, E♭3 2, G3 3 and none on C4 or E♭4
        let held = list([0, 1, 2, 3, 4], pool: [48, 51, 55], received: true)
        let pn = euclideousNotesPlaceNumbers(list: held, way: .cycle)
        XCTAssertEqual(Array(pn[0..<5]), ["1", "2", "3", nil, nil])
        // TOP 2 keeps its pair: two places
        XCTAssertEqual(euclideousNotesPlaceNumbers(list: list([7, 8], pool: exPool), way: .cycle)[8], "2\u{2013}3")
    }

    // MARK: 11. displays (pure): pips, grey footers, key flash
    func testPipsMarkTheHitsThePlaysAndRestsChooseAndRingBelowChance100() {
        // the example lane's footers: steps 1 and 6 play the riff, 3, 5 and 8 are rests (step 2, 4, 7 are misses)
        let st: [EuclidFooterState] = [.hit(riffStep: 6), .miss, .hitOnRest(riffStep: 8), .miss, .hitOnRest(riffStep: 2), .hit(riffStep: 3), .miss, .hitOnRest(riffStep: 5)]
        XCTAssertEqual(euclideousNotesPips(states: st, when: 0b10, chance: 100), [0, 0, 1, 0, 1, 0, 0, 1], "RESTS gives hits 3, 5 and 8")
        XCTAssertEqual(euclideousNotesPips(states: st, when: 0b01, chance: 100), [1, 0, 0, 0, 0, 1, 0, 0], "PLAYS gives 1 and 6")
        XCTAssertEqual(euclideousNotesPips(states: st, when: 0b11, chance: 100), [1, 0, 1, 0, 1, 1, 0, 1])
        XCTAssertEqual(euclideousNotesPips(states: st, when: 0b10, chance: 50), [0, 0, 2, 0, 2, 0, 0, 2], "at CHANCE 50 they are rings")
        XCTAssertEqual(euclideousNotesPips(states: [.hitTied(riffStep: 2)], when: 0b11, chance: 100), [0], "an FX-tied hit strikes nothing")
    }
    func testGreyFootersOnlyWhenTheRiffIsOffTheNotesAreOnAndWhenIsOneSided() {
        XCTAssertTrue(euclideousNotesGreyFooters(riffOn: false, notesLayerOn: true, when: 0b01)); XCTAssertTrue(euclideousNotesGreyFooters(riffOn: false, notesLayerOn: true, when: 0b10))
        XCTAssertFalse(euclideousNotesGreyFooters(riffOn: false, notesLayerOn: true, when: 0b11), "both on: none")
        XCTAssertFalse(euclideousNotesGreyFooters(riffOn: true, notesLayerOn: true, when: 0b01)); XCTAssertFalse(euclideousNotesGreyFooters(riffOn: false, notesLayerOn: false, when: 0b01))
    }
    func testKeyFlashLightsTheKeysOfTheNotesThatSoundWithTheirRollAndRunOffsets() {
        let l = list([7, 4, 5], pool: exPool)   // C4 60 (rank 8, position 7), G3 55 (position 4), A♭3 56 (position 5)
        func flash(_ pitches: [UInt8], riff: Bool, rank: Int, secs: Double, way: EuclidNotesPlayAs = .chord, list: EuclideousNotesList? = nil, shift: Int = 0, scale: Double = 1, notesVel: Int = 100) -> EuclideousNotesKeyFlash {
            euclideousNotesKeyFlash(eventPitches: pitches, hasRiffNote: riff, riffRank: rank, seconds: secs, riffVel: 100, notesVel: notesVel, list: list ?? l, pitchShift: shift, way: way,
                                    stepBeats: 0.5, gapBeats: 1, lenBeats: 0.5, legato: false, tempo: 120, scale: scale)
        }
        // the hit on 1 with the riff on, CHORD, both: the riff A♭3 first, then C4 and G3 (A♭3 was dropped, 7.2) -> C4 and G3 light, A♭3 does not; the riff dot sits on rank 6
        let f = flash([56, 60, 55], riff: true, rank: 6, secs: 0.01)
        XCTAssertGreaterThan(f.sounding[7], 0.5); XCTAssertGreaterThan(f.sounding[4], 0.5); XCTAssertEqual(f.sounding[5], 0, "the key whose note the riff took never lights")
        XCTAssertEqual(f.riffDotRank, 6); XCTAssertGreaterThan(f.riffDotStrength, 0.5)
        // §8.1: the glow is §1's f for the notes layer's played velocity — a harder note lights harder, and it fades on the same timing
        XCTAssertEqual(f.sounding[7], euclideousPulseEnvelopes(velocity: 100, seconds: 0.01, scale: 1).f, accuracy: 1e-12)
        XCTAssertLessThan(flash([60], riff: false, rank: -1, secs: 0.01, notesVel: 30).sounding[7], flash([60], riff: false, rank: -1, secs: 0.01, notesVel: 120).sounding[7])
        XCTAssertEqual(flash([60], riff: false, rank: -1, secs: 1.6).sounding[7], 0, "gone after 1.5 s"); XCTAssertEqual(flash([60], riff: false, rank: -1, secs: 0.01, scale: 0).sounding[7], 0, "PULSE OFF")
        // a hit with no riff note puts no dot anywhere; the notes shifted by the lane's octave still find their keys
        let g = flash([72, 67], riff: false, rank: -1, secs: 0.01, shift: 12)
        XCTAssertNil(g.riffDotRank); XCTAssertGreaterThan(g.sounding[7], 0.5); XCTAssertGreaterThan(g.sounding[4], 0.5)
        // RUN: the second note starts a slot (1/6 beat = 1/12 s at 120 BPM… 0.5 beat / 3 notes = 1/6 beat = 0.0833 s) later, so right at the hit only the first key is lit
        let run = flash([60, 55, 56], riff: false, rank: -1, secs: 0.0, way: .run)
        XCTAssertGreaterThan(run.sounding[7], 0.5); XCTAssertEqual(run.sounding[4], 0, accuracy: 1e-9, "RUN: G3 has not started"); XCTAssertEqual(run.sounding[5], 0, accuracy: 1e-9)
        let later = flash([60, 55, 56], riff: false, rank: -1, secs: 1.0 / 12.0 + 0.001, way: .run)
        XCTAssertGreaterThan(later.sounding[4], 0.5, "RUN: G3 starts 1/6 beat after the hit"); XCTAssertEqual(later.sounding[5], 0, accuracy: 1e-9, "…and A♭3 a slot after that")
        // a key that is not in the list (held back) has nothing to light
        let held = list([0, 1, 2, 3, 4], pool: [48, 51, 55], received: true)
        let h = flash([48, 51, 55], riff: false, rank: -1, secs: 0, list: held)
        XCTAssertEqual(h.sounding[3], 0); XCTAssertEqual(h.sounding[4], 0); XCTAssertGreaterThan(h.sounding[0], 0.5)
    }

    // MARK: §11 VoiceOver words
    func testVoiceOverWordsMatchTheFerry() {
        XCTAssertEqual(euclideousNotesRankKeyAccessibilityLabel(rank: 6, spokenNote: "A flat 3", received: true, lit: true, heldBack: false, place: "3"), "Rank 6, A flat 3, received, lit, 3rd in the lit order")
        XCTAssertEqual(euclideousNotesRankKeyAccessibilityLabel(rank: 4, spokenNote: "C 4", received: false, lit: true, heldBack: true, place: nil),
                       "Rank 4, C 4, an octave copy, lit, held back because only received notes sound")
        XCTAssertEqual(euclideousNotesRankKeyAccessibilityLabel(rank: 1, spokenNote: nil, received: false, lit: false, heldBack: false, place: nil), "Rank 1, nothing held, an octave copy, not lit")
        // TOP keeps its single highest note; TOP 2 keeps its PAIR (the second-highest and the highest) — the one place this differs from the ferry's single-note wording
        XCTAssertEqual(euclideousNotesTopKeyAccessibilityLabel(isTopTwo: false, spokenNotes: ["B flat 3"], lit: true, place: nil), "The highest received note, B flat 3, lit")
        XCTAssertEqual(euclideousNotesTopKeyAccessibilityLabel(isTopTwo: true, spokenNotes: ["A flat 3", "B flat 3"], lit: false, place: nil), "The two highest received notes, A flat 3 and B flat 3, not lit")
        XCTAssertEqual(euclideousNotesTopKeyAccessibilityLabel(isTopTwo: true, spokenNotes: [], lit: false, place: nil), "The highest received note, nothing held, not lit")
        XCTAssertEqual(euclideousNotesTopKeyAccessibilityLabel(isTopTwo: true, spokenNotes: ["A flat 3", "B flat 3"], lit: true, place: "2\u{2013}3"), "The two highest received notes, A flat 3 and B flat 3, lit, 2nd and 3rd in the lit order")
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22].map(euclideousNotesOrdinal), ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"])
        XCTAssertEqual(euclideousNotesChanceValue(100), "100 percent: every chosen hit plays"); XCTAssertEqual(euclideousNotesChanceValue(50), "50 percent: each chosen hit plays 50 times in 100")
        XCTAssertEqual(euclideousNotesPlayAsButtonLabel(.cycle), "Play as cycle"); XCTAssertEqual(euclideousNotesPlayAsButtonValue(.cycle), "One lit note a hit, in the order you lit them")
        XCTAssertEqual(euclideousNotesWayAccessibilityLabel(.chord), "Chord: every lit note at once")
        XCTAssertEqual(euclideousNotesWayAccessibilityLabel(.run), "Run: every lit note one after another, spread across the hit\u{2019}s step, in the order you lit them")
        XCTAssertEqual(euclideousNotesWayAccessibilityLabel(.build), "Build: one more lit note each hit, in the order you lit them, then start again")
        XCTAssertEqual(euclideousNotesWhenHint(isOnlyOneOn: true, riffOn: true), "One of the two always stays on")
        XCTAssertEqual(euclideousNotesWhenHint(isOnlyOneOn: false, riffOn: false), "The riff is off but still decides")
        XCTAssertEqual(euclideousNotesWhenHint(isOnlyOneOn: true, riffOn: false), "One of the two always stays on. The riff is off but still decides")
        XCTAssertEqual(euclideousNotesKeyRowGroupLabel, "Lit notes: the riff grid\u{2019}s eight rows, then the top two received notes")
        for way in EuclidNotesPlayAs.allCases { XCTAssertNotNil(euclideousNotesWayDescriptions[way]); XCTAssertTrue(euclideousNotesWayOrder.contains(way)) }
    }

    // NOTES TAB §2.11 — a tap lights a key at the END of the lit order, unlights it, and turns an OFF layer on
    func testTappingAKeyLightsItAtTheEndUnlightsItAndTurnsAnOffLayerOn() {
        var l = EuclidLine(); l.setLitOrder(EuclideousLitOrder()); l.notesOn = false
        euclideousToggleLitPosition(&l, position: 2)
        XCTAssertTrue(l.notesOnResolved, "a tap on an off layer also turns it on")
        XCTAssertEqual(l.litOrderResolved.array, [2])
        euclideousToggleLitPosition(&l, position: 5); XCTAssertEqual(l.litOrderResolved.array, [2, 5], "lighting adds to the END")
        euclideousToggleLitPosition(&l, position: 2); XCTAssertEqual(l.litOrderResolved.array, [5], "tapping a lit key unlights it")
        euclideousToggleLitPosition(&l, position: 2); XCTAssertEqual(l.litOrderResolved.array, [5, 2], "lighting it again puts it at the end")
        euclideousToggleLitPosition(&l, position: EuclideousLitOrder.topTwoPosition); euclideousToggleLitPosition(&l, position: EuclideousLitOrder.topPosition)
        XCTAssertEqual(l.litOrderResolved.array, [5, 2, 8, 9], "TOP 2 and TOP are positions 8 and 9")
        let before = l
        euclideousToggleLitPosition(&l, position: -1); euclideousToggleLitPosition(&l, position: 10)
        XCTAssertEqual(l, before, "a position outside 0…9 changes nothing")
    }
}

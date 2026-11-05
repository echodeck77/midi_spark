//  PartSoloTests.swift — MIX v2 ferry (2026-11-05), §7 / §11 tests 7–9: PER-PART SOLO. The pure decision (`euclideousPartAudible`, `euclideousPartSoloSilences`, `euclideousLaneSilencedBySolo`), the Router through the real engine
//  (the note feed's `part` says which part struck), no stuck notes across solo changes, and the persistence of the latched part mask. A part index is 2·lane + (notes ? 1 : 0), the same as `FourfoldPorts.bus(lane:part:)`.

import XCTest

private final class TrackingEmitter: MIDIEmitter {
    private(set) var last: [Int: UInt8] = [:]
    private(set) var ons = 0, offs = 0
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let st = b0 & 0xF0
        guard st == 0x90 || st == 0x80 else { return }
        let key = Int(cable) * 128 + Int(b1)
        if st == 0x90 && b2 > 0 { last[key] = 0x90; ons += 1 } else { last[key] = 0x80; offs += 1 }
    }
    var stuck: Int { last.values.filter { $0 != 0x80 }.count }
}

final class PartSoloTests: XCTestCase {
    // MARK: the pure decision

    func testPartAudibleTruthTable() {
        for lane in 0..<4 { for part in 0..<2 {
            for laneMask in UInt8(0)...15 { for partMask in [UInt8(0), 0x01, 0x02, 0x81, 0x55, 0xAA, 0xFF] {
                for muteAudible in [true, false] { for enabled in [true, false] {
                    let anySolo = laneMask != 0 || partMask != 0
                    let heard = (laneMask >> UInt8(lane)) & 1 != 0 || (partMask >> UInt8(2 * lane + part)) & 1 != 0
                    let want = enabled && muteAudible && (!anySolo || heard)
                    XCTAssertEqual(euclideousPartAudible(lane: lane, part: part, laneMask: laneMask, partMask: partMask, muteAudible: muteAudible, enabled: enabled), want,
                                   "lane \(lane) part \(part) laneMask \(laneMask) partMask \(partMask) mute \(muteAudible) enabled \(enabled)")
                } }
            } }
        } }
    }
    func testWithNoPartMaskThePartDecisionIsLaneSoloExactly() {
        for lane in 0..<4 { for solo in UInt8(0)...15 {
            for part in 0..<2 { XCTAssertEqual(euclideousPartSoloSilences(lane: lane, part: part, soloMask: solo, partMask: 0), euclideousSoloSilences(lane: lane, soloMask: solo)) }
            XCTAssertEqual(euclideousLaneSilencedBySolo(lane: lane, soloMask: solo, partMask: 0), euclideousSoloSilences(lane: lane, soloMask: solo))
            for muteAudible in [true, false] { for enabled in [true, false] {
                XCTAssertEqual(euclideousLaneMayStrike(lane: lane, soloMask: solo, muteAudible: muteAudible, enabled: enabled),
                               euclideousLaneMayStrike(lane: lane, soloMask: solo, muteAudible: muteAudible, enabled: enabled, partMask: 0))
            } }
        } }
    }
    func testALaneIsSilencedOnlyWhenNeitherOfItsPartsMaySound() {
        // lane 0's riff alone: lane 0 still sounds (its riff), its notes are silenced, lanes 1–3 are silenced whole
        XCTAssertFalse(euclideousLaneSilencedBySolo(lane: 0, soloMask: 0, partMask: 0b0000_0001))
        XCTAssertTrue(euclideousPartSoloSilences(lane: 0, part: 1, soloMask: 0, partMask: 0b0000_0001))
        for lane in 1..<4 { XCTAssertTrue(euclideousLaneSilencedBySolo(lane: lane, soloMask: 0, partMask: 0b0000_0001), "lane \(lane)") }
        // lane 1 soloed whole + lane 3's notes: audible parts are exactly 2, 3 and 7
        let bits = euclideousSoloSilencedPartBits(soloMask: 0b0010, partMask: 1 << 7)
        XCTAssertEqual(bits, ~UInt8(0b1000_1100))
        XCTAssertEqual(euclideousSoloSilencedPartBits(soloMask: 0, partMask: 0), 0, "no solo: nothing silenced")
        XCTAssertEqual(euclideousPartSoloEffective(latched: 0b0001, held: 0b1000_0010), 0b1000_0011, "latched | held, eight bits")
    }

    // MARK: the Router

    private func lane(rate: ArpRate, steps: Int = 8, notes: UInt8 = 0b0000_0001, gate: Double = 0.5) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: steps, steps: steps, velocityAbsolute: 100, rate: rate, useRiff: true, riffOn: true, sourceMode: .midi)
        l.gate = gate; l.notesOn = true; l.litNotes = notes; l.notesGate = gate
        return l
    }
    private func fourLanes(gate: Double = 0.5) -> [EuclidLine] { [lane(rate: .r1_4, gate: gate), lane(rate: .r1_8, gate: gate), lane(rate: .r1_4, steps: 7, gate: gate), lane(rate: .r1_16, gate: gate)] }
    private func state(_ lines: [EuclidLine], fx: EuclideousFX? = nil, partSnapshot: UInt8? = nil) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = lines
        c.paramsA.partSoloMask = partSnapshot
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
        if let fx { st.euclideousFX = fx }
        return st
    }
    private struct Live { var lane: UInt8 = 0, part: UInt8 = 0 }
    /// `beats` of playing windows (480 frames each) then one STOP window; `live(beat)` is the page's live words at each window. Returns every roll record and the emitter's bookkeeping.
    private func play(_ st: PluginState, beats: Double, live: (Double) -> Live? = { _ in nil }) -> (records: [NoteRollRecord], emitter: TrackingEmitter) {
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = TrackingEmitter()
        let pool = NotePool(); for n in [UInt8]([48, 50, 52, 53, 55, 57, 59, 60]) { pool.noteOn(n, velocity: 100, channel: 0) }
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 480
        var ts = 0.0, out: [NoteRollRecord] = []
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            let l = live(beatNow())
            router.process(box: box, pool: pool, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0,
                           euclideousSoloLive: l.map { 0x100 | UInt16($0.lane) } ?? 0, euclideousPartSoloLive: l.map { 0x100 | UInt16($0.part) } ?? 0, out: e, diag: &diag)
            out += router.rollRing.drain()
            ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        out += router.rollRing.drain()
        return (out, e)
    }
    private func starts(_ r: [NoteRollRecord]) -> [NoteRollRecord] { r.filter { !$0.isEnd } }
    private func parts(_ r: [NoteRollRecord]) -> Set<Int> { Set(starts(r).map { Int($0.part) }) }
    private func beats(_ r: [NoteRollRecord], part: Int, from: Double = 0) -> [Double] { starts(r).filter { Int($0.part) == part && $0.onBeat >= from - 1e-9 }.map { $0.onBeat } }

    func testWithNothingSoloedEveryPartSounds() {
        let r = play(state(fourLanes()), beats: 6).records
        XCTAssertEqual(parts(r), Set(0..<8), "four lanes, riff and notes each")
    }
    func testWithBothMasksZeroTheStreamIsTheSameWhetherThePageHasSpokenOrNot() {
        let silent = play(state(fourLanes()), beats: 8).records
        let spoken = play(state(fourLanes()), beats: 8, live: { _ in Live() }).records
        XCTAssertEqual(starts(silent).map { [$0.part, $0.rank] }, starts(spoken).map { [$0.part, $0.rank] })
        XCTAssertEqual(starts(silent).map { $0.onBeat }, starts(spoken).map { $0.onBeat })
    }
    func testLaneOnesRiffSoloedAloneIsTheOnlyThingThatEmitsAndEverythingElseKeepsWalking() {
        let base = play(state(fourLanes()), beats: 10).records
        let solo = play(state(fourLanes()), beats: 10, live: { _ in Live(lane: 0, part: 0b0000_0001) })
        XCTAssertEqual(parts(solo.records), [0], "only lane 1's riff emits")
        XCTAssertEqual(beats(solo.records, part: 0), beats(base, part: 0), "…and it plays exactly the notes it always did")
        XCTAssertEqual(solo.emitter.stuck, 0)
    }
    func testUnsoloReturnsEveryPartToTheGridAndTheRiffWalkOfANeverSoloedRender() {
        let base = play(state(fourLanes()), beats: 14).records
        let solo = play(state(fourLanes()), beats: 14, live: { b in b < 6 ? Live(lane: 0, part: 0b0000_0001) : Live() }).records
        for part in 1..<8 {
            XCTAssertEqual(beats(solo, part: part, from: 6.2), beats(base, part: part, from: 6.2), "part \(part): the next note-ons land where the never-soloed render has them")
        }
        // the riff walk kept going while silenced: the rank each hit reads after the solo is the one the baseline reads
        let rank = { (r: [NoteRollRecord], part: Int) in self.starts(r).filter { Int($0.part) == part && $0.onBeat >= 6.2 - 1e-9 }.map { $0.rank } }
        for part in [2, 4, 6] { XCTAssertEqual(rank(solo, part), rank(base, part), "part \(part) (a riff part) kept its walk") }
        for part in 1..<8 { XCTAssertTrue(beats(solo, part: part).allSatisfy { $0 >= 5.99 }, "part \(part) was silent while lane 1's riff was soloed") }
    }
    func testAHeldPartSoloForTwoBarsSilencesTheRestForTwoBarsAndThenLetsGo() {
        let base = play(state(fourLanes()), beats: 16).records
        let held = play(state(fourLanes()), beats: 16, live: { b in b >= 4 && b < 12 ? Live(lane: 0, part: 1 << 5) : Live() }).records   // lane 2's notes (part 5)
        let during = starts(held).filter { $0.onBeat >= 4.05 && $0.onBeat < 11.95 }
        XCTAssertEqual(Set(during.map { Int($0.part) }), [5], "only lane 3's notes sound during the hold (part 5 = lane 2 index, notes)")
        XCTAssertEqual(beats(held, part: 0, from: 12.1), beats(base, part: 0, from: 12.1), "and lane 1 is back on its grid afterwards")
        XCTAssertGreaterThanOrEqual(parts(starts(held).filter { $0.onBeat >= 12.1 }).count, 8 - 0, "every part sounds again")
    }
    func testLaneSoloAndPartSoloTogetherHearTheUnion() {
        let r = play(state(fourLanes()), beats: 8, live: { _ in Live(lane: 0b0010, part: 1 << 7) }).records
        XCTAssertEqual(parts(r), [2, 3, 7], "lane 2 whole (parts 2 and 3) plus lane 4's notes (part 7)")
    }
    func testASnapshotMaskIsTheFallbackWhenThePageHasNotSpoken() {
        let r = play(state(fourLanes(), partSnapshot: 1 << 4), beats: 6).records   // lane 3's riff, from the snapshot alone
        XCTAssertEqual(parts(r), [4])
    }
    func testASilencedPartKeepsAHocketPassedLineFromSoundingOnIt() {
        // lane 1's riff (output 1) passes onto lane 2's riff output (output 3) by a PASS rule; with lane 2's riff part silenced by a part solo (lane 1's riff soloed), nothing is left to hear except lane 1's own riff
        var st = state(fourLanes())
        let rule = HocketRule(mode: .pass, main: [1], alt: [3])
        st.hocketRules = HocketRuleSet([rule])
        let r = play(st, beats: 8, live: { _ in Live(lane: 0, part: 0b0000_0001) })
        XCTAssertTrue(parts(r.records).isSubset(of: [0]), "no part but lane 1's riff emits: \(parts(r.records))")
        XCTAssertEqual(r.emitter.stuck, 0)
    }

    func testNoStuckNotesAcrossSoloChangesWithTiesRatchetsAndTheTopGate() {
        var fx = EuclideousFX(); fx.cells[0 * 8 + 1] = 3; fx.cells[0 * 8 + 4] = 2     // RATCH row: ×3 on riff column 2, ×2 on column 5
        for seed in 1...40 {
            var rng = SplitMix64(seed: UInt64(seed) &* 0x9E37_79B9)
            let changeEvery = 0.17 + Double(rng.next() % 90) / 100
            var table: [(Double, Live)] = []
            var t = 0.0
            while t < 22 {
                let laneBits = UInt8(truncatingIfNeeded: rng.next() % 16), laneOn: UInt8 = rng.next() % 3 == 0 ? 0x0F : 0
                let partBits = UInt8(truncatingIfNeeded: rng.next()), partOn: UInt8 = rng.next() % 2 == 0 ? 0xFF : 0
                table.append((t, Live(lane: laneBits & laneOn, part: partBits & partOn)))
                t += changeEvery
            }
            let st = state(fourLanes(gate: 0.99), fx: fx)
            let r = play(st, beats: 22, live: { b in table.last(where: { $0.0 <= b })?.1 })
            XCTAssertEqual(r.emitter.stuck, 0, "seed \(seed): a note was left sounding after the stop")
        }
    }

    // MARK: persistence

    func testThePartMaskRoundTripsAndNilMeansNone() throws {
        var d = PluginState(machines: [], scenes: [])
        XCTAssertNil(d.euclideousPartSoloMask); XCTAssertEqual(d.euclideousPartSoloMaskResolved, 0)
        d.euclideousPartSoloMask = 0xA5
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.euclideousPartSoloMask, 0xA5); XCTAssertEqual(back.euclideousPartSoloMaskResolved, 0xA5)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
        old.removeValue(forKey: "euclideousPartSoloMask")
        let legacy = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.euclideousPartSoloMask, "a document from before this ferry decodes with no part solo")
        XCTAssertEqual(legacy.euclideousPartSoloMaskResolved, 0)
        XCTAssertFalse(String(data: try JSONEncoder().encode(d), encoding: .utf8)!.lowercased().contains("held"), "the held mask is UI state and is never encoded")
    }
    func testTheSnapshotCarriesThePartMaskAndOtherwiseZero() {
        XCTAssertEqual(SnapshotBuilder.build(from: state(fourLanes(), partSnapshot: 0b0110_0001)).cells[Snap.euclideousRow].procs[0].partSoloMask, 0b0110_0001)
        XCTAssertEqual(SnapshotBuilder.build(from: state(fourLanes())).cells[Snap.euclideousRow].procs[0].partSoloMask, 0)
        let c = FourfoldCompose.chain(FourfoldCompose.Input(lines: fourLanes(), riff: EuclideousRiff(), riffs: [], activeRiff: 0, soloMask: 0, locks: [], lockRevs: 0, partSoloMask: 0x12))
        XCTAssertEqual(c[0].params.partSoloMask, 0x12)
        XCTAssertNil(FourfoldCompose.chain(FourfoldCompose.Input(lines: fourLanes(), riff: EuclideousRiff(), riffs: [], activeRiff: 0, soloMask: 0, locks: [], lockRevs: 0))[0].params.partSoloMask, "0 composes as nil: a pre-feature chain")
    }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

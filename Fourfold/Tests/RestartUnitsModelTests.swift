//  RestartUnitsModelTests.swift — RESTART UNITS ferry (2026-11-04), test 15: the model, its storage and its resolvers. Defaults, nil resolution for every field (a stored own-lane source on RHYTHM PASS included),
//  decode validation that keeps 5 and 7 only for HIT, the seven fields' trip through the codec, the SnapshotBuilder's fresh literal, the lane lock, and a pre-feature document resolving to what it always did.

import XCTest

final class RestartUnitsModelTests: XCTestCase {
    private func decode(_ json: String) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: Data(json.utf8)) }

    // MARK: defaults (2.10) and nil resolution (3.1)

    func testDefaultsResolveToBarAndPassOfTheLaneItselfOffAndNoWithRhythm() {
        let l = EuclidLine()
        for lane in 0..<4 {
            let s = euclideousRestartSettings(line: l, lane: lane)
            XCTAssertEqual(s.rhythmUnit, .bar); XCTAssertEqual(s.melodyUnit, .pass)
            XCTAssertEqual(s.melodySource, lane, "MELODY's source defaults to the lane itself")
            XCTAssertTrue(s.rhythm.isFree); XCTAssertTrue(s.melody.isFree)
            XCTAssertFalse(s.rhythmOn); XCTAssertFalse(s.melodyOn); XCTAssertFalse(s.withRhythm); XCTAssertFalse(s.anyActive)
        }
        XCTAssertNil(l.restartRhythmUnit); XCTAssertNil(l.restartMelodyWithRhythm, "new lanes store nothing: every field is nil")
    }
    func testEveryNilFieldResolvesAsTheEngineAlwaysPlayed() {
        var l = EuclidLine(); l.restartRhythmBars = [2, 1]; l.restartMelodyPasses = [3]   // a pre-feature lane: links only
        let s = euclideousRestartSettings(line: l, lane: 1)
        XCTAssertTrue(s.rhythmOn && s.melodyOn, "on nil → on exactly because the chain has links")
        XCTAssertEqual(s.rhythmUnit, .bar); XCTAssertEqual(s.melodyUnit, .pass); XCTAssertEqual(s.melodySource, 1)
        XCTAssertEqual(s.rhythm.links, [2, 1]); XCTAssertEqual(s.melody.links, [3])
        XCTAssertTrue(s.isClosedFormExpressible(ownLane: 1), "a pre-feature lane is exactly what the closed forms express")
        // an empty chain with no stored switch is off; FREE ([]) is not nil
        var e = EuclidLine(); e.restartRhythmBars = []
        XCTAssertFalse(e.restartRhythmOnResolved); XCTAssertFalse(euclideousRestartSettings(line: e, lane: 0).rhythmActive)
    }
    func testASwitchOffKeepsItsLinksAndBehavesAsFree() {
        var l = EuclidLine(); l.restartRhythmBars = [2, 1]; l.restartRhythmOn = false
        let s = euclideousRestartSettings(line: l, lane: 0)
        XCTAssertEqual(s.rhythm.links, [2, 1], "off keeps its links"); XCTAssertFalse(s.rhythmActive)
        XCTAssertTrue(euclideousLaneRestartChains(line: l, lane: 0, barBeats: 4, lapBeats: 4).rhythm.isFree, "…and the closed forms read FREE")
        l.restartRhythmOn = true
        XCTAssertEqual(euclideousLaneRestartChains(line: l, lane: 0, barBeats: 4, lapBeats: 4).rhythm.links, [2, 1], "back on restores them")
        var empty = EuclidLine(); empty.restartRhythmBars = []; empty.restartRhythmOn = true
        XCTAssertFalse(euclideousRestartSettings(line: empty, lane: 0).rhythmActive, "on with no link is inactive (2.4)")
    }
    func testAStoredOwnLaneSourceOnRhythmPassResolvesToTheNextLane() {
        for lane in 0..<4 {
            var l = EuclidLine(); l.restartRhythmUnit = .pass; l.restartRhythmSource = lane
            XCTAssertEqual(l.restartRhythmSourceResolved(ownLane: lane), (lane + 1) % 4, "lane \(lane): never itself — lane 4 wraps to lane 1")
            l.restartRhythmSource = nil
            XCTAssertEqual(l.restartRhythmSourceResolved(ownLane: lane), (lane + 1) % 4, "nil is the lane itself, which resolves the same way")
            l.restartRhythmSource = (lane + 2) % 4
            XCTAssertEqual(l.restartRhythmSourceResolved(ownLane: lane), (lane + 2) % 4, "another lane is kept")
        }
        var r = EuclidLine(); r.restartRhythmUnit = .riff; r.restartRhythmSource = 2
        XCTAssertEqual(r.restartRhythmSourceResolved(ownLane: 2), 2, "RIFF may count the lane itself")
        var b = EuclidLine(); b.restartRhythmUnit = .bar; b.restartRhythmSource = 3
        XCTAssertEqual(b.restartRhythmSourceResolved(ownLane: 0), 3, "BAR keeps a stored source (ignored)")
        var m = EuclidLine(); m.restartMelodySource = 9
        XCTAssertEqual(m.restartMelodySourceResolved(ownLane: 0), 3, "a source is clamped to a lane")
    }
    func testWhichUnitsReadASource() {
        XCTAssertFalse(EuclideousRhythmRestartUnit.bar.readsSource); XCTAssertTrue(EuclideousRhythmRestartUnit.pass.readsSource); XCTAssertTrue(EuclideousRhythmRestartUnit.riff.readsSource)
        XCTAssertTrue(EuclideousMelodyRestartUnit.pass.readsSource); XCTAssertFalse(EuclideousMelodyRestartUnit.bar.readsSource); XCTAssertFalse(EuclideousMelodyRestartUnit.hit.readsSource)
    }
    func testASettingTheClosedFormsCannotExpressIsNotClosedFormExpressible() {
        func s(_ f: (inout EuclidLine) -> Void) -> EuclideousRestartSettings { var l = EuclidLine(); l.restartRhythmBars = [1]; l.restartMelodyPasses = [2]; f(&l); return euclideousRestartSettings(line: l, lane: 1) }
        XCTAssertTrue(s { _ in }.isClosedFormExpressible(ownLane: 1))
        XCTAssertFalse(s { $0.restartRhythmUnit = .riff }.isClosedFormExpressible(ownLane: 1))
        XCTAssertFalse(s { $0.restartRhythmUnit = .pass; $0.restartRhythmSource = 0 }.isClosedFormExpressible(ownLane: 1))
        XCTAssertFalse(s { $0.restartMelodyUnit = .hit }.isClosedFormExpressible(ownLane: 1))
        XCTAssertFalse(s { $0.restartMelodyUnit = .bar }.isClosedFormExpressible(ownLane: 1))
        XCTAssertFalse(s { $0.restartMelodySource = 0 }.isClosedFormExpressible(ownLane: 1), "MELODY PASS of another lane")
        XCTAssertFalse(s { $0.restartMelodyWithRhythm = true }.isClosedFormExpressible(ownLane: 1))
        XCTAssertTrue(s { $0.restartRhythmOn = false; $0.restartMelodyOn = false }.isClosedFormExpressible(ownLane: 1), "inactive chains are FREE, which the closed forms express")
    }

    // MARK: decode validation (3.3)

    func testDecodeKeepsFiveAndSevenOnlyForAHitChain() throws {
        let hit = try decode(#"{"restartMelodyUnit":"HIT","restartMelodyPasses":[1,5,7,9,0,3]}"#)
        XCTAssertEqual(hit.restartMelodyPasses, [1, 5, 7, 3], "HIT keeps 1…8, drops 0 and 9")
        let pass = try decode(#"{"restartMelodyUnit":"PASS","restartMelodyPasses":[1,5,7,9,0,3]}"#)
        XCTAssertEqual(pass.restartMelodyPasses, [1, 3], "PASS keeps {1,2,3,4,6,8}")
        let bare = try decode(#"{"restartMelodyPasses":[1,5,7,6]}"#)
        XCTAssertEqual(bare.restartMelodyPasses, [1, 6], "no unit stored → PASS")
        let capped = try decode(#"{"restartMelodyUnit":"HIT","restartMelodyPasses":[1,2,3,4,5,6,7]}"#)
        XCTAssertEqual(capped.restartMelodyPasses, [1, 2, 3, 4], "at most the first four")
        let rhythm = try decode(#"{"restartRhythmUnit":"RIFF","restartRhythmBars":[1,5,6,8,7,2]}"#)
        XCTAssertEqual(rhythm.restartRhythmBars, [1, 6, 8, 2], "RHYTHM never keeps 5 or 7")
        XCTAssertNil(try decode("{}").restartRhythmBars, "nil stays nil (migrate)")
        XCTAssertEqual(try decode(#"{"restartRhythmBars":[]}"#).restartRhythmBars, [], "[] is FREE")
        // tolerant: a wrong-typed value or an unknown unit reads as missing
        let junk = try decode(#"{"restartRhythmUnit":"WEEK","restartRhythmSource":"x","restartMelodyOn":3,"restartMelodySource":7}"#)
        XCTAssertNil(junk.restartRhythmUnit); XCTAssertNil(junk.restartRhythmSource); XCTAssertNil(junk.restartMelodyOn); XCTAssertEqual(junk.restartMelodySource, 3, "clamped to a lane")
        XCTAssertEqual(try decode(#"{"restartRhythmSource":-4}"#).restartRhythmSource, 0)
    }
    func testChainFromRespectsTheUnit() {
        XCTAssertEqual(EuclideousRestartChain.from([5, 7, 9], hit: true).links, [5, 7])
        XCTAssertEqual(EuclideousRestartChain.from([5, 7, 9], hit: false).links, [])
        XCTAssertEqual(EuclideousRestartChain.from([2, 1, 1]).links, EuclideousRestartChain.from([2, 1, 1], hit: false).links, "the plain `.from` is the non-HIT one, unchanged")
        XCTAssertEqual(euclideousRestartLinkLadder(hit: true), [1, 2, 3, 4, 5, 6, 7, 8]); XCTAssertEqual(euclideousRestartLinkLadder(hit: false), [1, 2, 3, 4, 6, 8])
    }

    // MARK: all seven fields travel

    private func populated() -> EuclidLine {
        var l = EuclidLine(); l.restartRhythmBars = [2, 1]; l.restartMelodyPasses = [1, 5]
        l.restartRhythmUnit = .pass; l.restartRhythmSource = 2; l.restartRhythmOn = false
        l.restartMelodyUnit = .hit; l.restartMelodySource = 1; l.restartMelodyOn = true; l.restartMelodyWithRhythm = true
        return l
    }
    func testAllSevenFieldsRoundTripThroughTheCodec() throws {
        let l = populated()
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
        XCTAssertEqual(back.restartRhythmUnit, .pass); XCTAssertEqual(back.restartRhythmSource, 2); XCTAssertEqual(back.restartRhythmOn, false)
        XCTAssertEqual(back.restartMelodyUnit, .hit); XCTAssertEqual(back.restartMelodySource, 1); XCTAssertEqual(back.restartMelodyOn, true); XCTAssertEqual(back.restartMelodyWithRhythm, true)
        XCTAssertEqual(back.restartMelodyPasses, [1, 5], "a HIT chain's 5 survives the trip")
    }
    func testTheSnapshotBuildersFreshLiteralCarriesAllSevenFields() {
        var m = Machine(machineID: "gold", type: .euclid)
        var lines = (0..<4).map { _ in EuclidLine(noteSel: .all) }
        lines[1] = populated(); lines[1].noteSel = .all
        m.paramsA.euclidLines = lines
        let built = SnapshotBuilder.build(from: PluginState(machines: [m], scenes: [SceneState.empty()]))
        let out = built.machines.first { $0.a.euclidLines.count == 4 }?.a.euclidLines
        XCTAssertEqual(out?[1].restartRhythmUnit, .pass, "a fresh-literal rebuild that forgot a field would silently reset it on the next render")
        XCTAssertEqual(out?[1].restartRhythmSource, 2); XCTAssertEqual(out?[1].restartRhythmOn, false)
        XCTAssertEqual(out?[1].restartMelodyUnit, .hit); XCTAssertEqual(out?[1].restartMelodySource, 1); XCTAssertEqual(out?[1].restartMelodyOn, true); XCTAssertEqual(out?[1].restartMelodyWithRhythm, true)
        XCTAssertEqual(out?[1].restartMelodyPasses, [1, 5])
        XCTAssertNil(out?[0].restartRhythmUnit); XCTAssertNil(out?[0].restartMelodyWithRhythm, "a lane that never had them stays nil")
    }
    func testTheLockHoldsAllSevenFields() {
        let l = populated()
        let f = LaneLockFields(line: l)
        var w = EuclidLine(); f.applied(to: &w)
        XCTAssertEqual(w.restartRhythmUnit, .pass); XCTAssertEqual(w.restartRhythmSource, 2); XCTAssertEqual(w.restartRhythmOn, false)
        XCTAssertEqual(w.restartMelodyUnit, .hit); XCTAssertEqual(w.restartMelodySource, 1); XCTAssertEqual(w.restartMelodyOn, true); XCTAssertEqual(w.restartMelodyWithRhythm, true)
        XCTAssertEqual(w.restartMelodyPasses, [1, 5])
        XCTAssertEqual(euclideousLockChangedControls(from: f, to: l), [], "an unchanged lane differs from its lock in nothing")
        var m = l; m.restartMelodyWithRhythm = false
        XCTAssertEqual(euclideousLockChangedControls(from: f, to: m), [.melodyRestart, .cometStrip], "WITH RHYTHM is the melody restart's control")
        var r = l; r.restartRhythmUnit = .riff
        XCTAssertTrue(euclideousLockChangedControls(from: f, to: r).contains(.rhythmRestart))
    }

    // MARK: a pre-feature document resolves and plays as before

    func testAPreFeatureLaneResolvesToTheChainsTheEngineAlwaysBuilt() {
        // the same four lines the old build sites wrote: usesRestartChains → `.from(bars)`, `.from(passes)`; otherwise `.off`
        var pinned = EuclidLine(); pinned.restartRhythmBars = [2, 1, 1]; pinned.restartMelodyPasses = [2]
        let c = euclideousLaneRestartChains(line: pinned, lane: 2, barBeats: 4, lapBeats: 3.5)
        XCTAssertEqual(c, EuclideousLaneRestartChains(rhythm: .from([2, 1, 1]), melody: .from([2]), barBeats: 4, lapBeats: 3.5))
        XCTAssertEqual(euclideousLaneRestartChains(line: EuclidLine(), lane: 0, barBeats: 4, lapBeats: 3.5), .off, "never pinned → .off")
        var onlyMelody = EuclidLine(); onlyMelody.restartMelodyPasses = [1]
        XCTAssertEqual(euclideousLaneRestartChains(line: onlyMelody, lane: 0, barBeats: 4, lapBeats: 2).rhythm, .free, "the nil side reads FREE")
    }

    // MARK: adversarial review (2026-11-04) — three findings of the model reviewer

    /// A lane locked as RHYTHM BAR must not read as deviated because the user visited PASS and came back: BAR ignores the source, so the stored source cannot count.
    func testALockDoesNotSeeASourceTheUnitIgnores() {
        var l = EuclidLine(); l.restartRhythmBars = [1]
        let f = LaneLockFields(line: l)
        var m = l; m.restartRhythmSource = 1
        XCTAssertFalse(euclideousLockDeviated(line: m, from: f), "BAR ignores its source")
        XCTAssertEqual(euclideousLockChangedControls(from: f, to: m), [])
        var h = l; h.restartMelodyPasses = [1]; h.restartMelodyUnit = .hit
        let fh = LaneLockFields(line: h)
        var h2 = h; h2.restartMelodySource = 3
        XCTAssertFalse(euclideousLockDeviated(line: h2, from: fh), "HIT ignores its source")
        var r = l; r.restartRhythmUnit = .riff
        let fr = LaneLockFields(line: r)
        var r2 = r; r2.restartRhythmSource = 2
        XCTAssertTrue(euclideousLockDeviated(line: r2, from: fr), "RIFF does read it: another lane's riff is a different restart")
    }
    /// Spec §7.5: link edits never turn the switch on. On a lane whose switch was never touched (nil) and whose chain is empty, the switch reads OFF — a "+" must leave it off.
    func testAddingALinkNeverTurnsTheSwitchOn() {
        for rhythm in [true, false] {
            var a = EuclidLine(); a.restartRhythmBars = []; a.restartMelodyPasses = []
            XCTAssertFalse(rhythm ? a.restartRhythmOnResolved : a.restartMelodyOnResolved)
            euclideousApplyRestartEdit(.addLink(rhythm: rhythm), to: &a, lane: 0, pin: nil)
            XCTAssertFalse(rhythm ? a.restartRhythmOnResolved : a.restartMelodyOnResolved, "a link edit does not turn the switch on")
            XCTAssertEqual(rhythm ? a.restartRhythmChainResolved.links : a.restartMelodyChainResolved.links, [1], "the link is added")
        }
    }
    /// A tap that changes nothing must change nothing — a pin alone is not an edit (it would record an undo step and write the document).
    func testANoOpTapOnAnUnpinnedLaneLeavesTheLineAlone() {
        var l = EuclidLine(); l.restartRhythmUnit = .bar
        let before = l
        let pin = (rhythm: EuclideousRestartChain.from([2]), melody: EuclideousRestartChain.free)
        let changed = euclideousApplyRestartEdit(.unit(rhythm: true, index: 0), to: &l, lane: 0, pin: pin)
        XCTAssertFalse(changed); XCTAssertEqual(l, before, "the line is untouched, pin included")
        var k = EuclidLine()
        XCTAssertTrue(euclideousApplyRestartEdit(.unit(rhythm: true, index: 2), to: &k, lane: 0, pin: pin), "a real first edit still pins")
        XCTAssertEqual(k.restartRhythmBars, [2]); XCTAssertEqual(k.restartRhythmUnit, .riff)
    }
}

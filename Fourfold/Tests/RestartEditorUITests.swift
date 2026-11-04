//  RestartEditorUITests.swift — RESTART UNITS ferry (2026-11-04), tests 16–19: the editor's edits (unit changes with their side effects, link stepping for both value sets, the switch), the tile's text, the timeline's windows and marks, and
//  the editor's frames at the reference and at the sizes the page really gives it.

import XCTest

final class RestartEditorUITests: XCTestCase {
    private func settings(_ build: (inout EuclidLine) -> Void, lane: Int = 0) -> EuclideousRestartSettings {
        var l = EuclidLine(); l.restartRhythmBars = []; l.restartMelodyPasses = []; build(&l)
        return euclideousRestartSettings(line: l, lane: lane)
    }
    private func pinned() -> EuclidLine { var l = EuclidLine(); l.restartRhythmBars = []; l.restartMelodyPasses = []; return l }

    // MARK: test 17 — the tile's text

    func testTheTilesText() {
        func rhythm(_ s: EuclideousRestartSettings, lane: Int = 0) -> EuclideousRestartTileSpec { euclideousRestartTileSpec(rhythm: true, settings: s, ownLane: lane) }
        func melody(_ s: EuclideousRestartSettings, lane: Int = 0) -> EuclideousRestartTileSpec { euclideousRestartTileSpec(rhythm: false, settings: s, ownLane: lane) }
        let a = rhythm(settings { $0.restartRhythmBars = [2, 1, 1]; $0.restartRhythmUnit = .pass; $0.restartRhythmSource = 1 })
        XCTAssertEqual(a.text, "2·1·1 PASS"); XCTAssertEqual(a.sourceLane, 1); XCTAssertEqual(a.fillLane, 1)
        let b = rhythm(settings { $0.restartRhythmBars = [1]; $0.restartRhythmUnit = .riff; $0.restartRhythmSource = 0 })
        XCTAssertEqual(b.text, "1 RIFF"); XCTAssertNil(b.sourceLane, "no square for the lane itself"); XCTAssertEqual(b.fillLane, 0)
        let c = melody(settings { $0.restartMelodyPasses = [1]; $0.restartMelodyUnit = .pass; $0.restartMelodySource = 1 })
        XCTAssertEqual(c.text, "1 PASS"); XCTAssertEqual(c.sourceLane, 1); XCTAssertFalse(c.showsLinkGlyph)
        let d = melody(settings { $0.restartMelodyPasses = [3]; $0.restartMelodyUnit = .hit })
        XCTAssertEqual(d.text, "3 HIT"); XCTAssertNil(d.sourceLane, "HIT reads no source")
        let e = melody(settings { $0.restartMelodyWithRhythm = true })
        XCTAssertEqual(e.text, "RHYTHM"); XCTAssertTrue(e.showsLinkGlyph); XCTAssertTrue(e.isSet); XCTAssertNil(e.unitText)
        let f = melody(settings { $0.restartMelodyPasses = [2]; $0.restartMelodyUnit = .pass; $0.restartMelodySource = 1; $0.restartMelodyWithRhythm = true })
        XCTAssertEqual(f.text, "2 PASS"); XCTAssertTrue(f.showsLinkGlyph); XCTAssertEqual(f.sourceLane, 1)
        let g = rhythm(settings { $0.restartRhythmBars = [2, 1, 1, 1] })
        XCTAssertEqual(g.text, "2·1·1·1", "four links: no unit"); XCTAssertNil(g.unitText)
        let h = rhythm(settings { _ in })
        XCTAssertEqual(h.text, "FREE"); XCTAssertFalse(h.isSet); XCTAssertEqual(melody(settings { _ in }).text, "FREE")
        // a rhythm tile is set when its chain is active (the switch off leaves the links but not the look); a melody tile also when WITH RHYTHM is on
        XCTAssertFalse(rhythm(settings { $0.restartRhythmBars = [2]; $0.restartRhythmOn = false }).isSet); XCTAssertEqual(rhythm(settings { $0.restartRhythmBars = [2]; $0.restartRhythmOn = false }).text, "FREE")
        XCTAssertTrue(melody(settings { $0.restartMelodyPasses = [2]; $0.restartMelodyOn = false; $0.restartMelodyWithRhythm = true }).isSet)
        // the pre-feature tile reads exactly as it did: "2·1·1 BAR", "1 PASS"
        XCTAssertEqual(rhythm(settings { $0.restartRhythmBars = [2, 1, 1] }).text, "2·1·1 BAR"); XCTAssertEqual(melody(settings { $0.restartMelodyPasses = [1] }).text, "1 PASS")
    }
    func testTheTilesVoiceOverLabels() {
        func r(_ b: (inout EuclidLine) -> Void, lane: Int = 0) -> String { euclideousRestartTileLabel(rhythm: true, settings: settings(b, lane: lane), ownLane: lane) }
        func m(_ b: (inout EuclidLine) -> Void, lane: Int = 0) -> String { euclideousRestartTileLabel(rhythm: false, settings: settings(b, lane: lane), ownLane: lane) }
        XCTAssertEqual(r { _ in }, "Rhythm restarts, free")
        XCTAssertEqual(r { $0.restartRhythmBars = [2] }, "Rhythm restarts every 2 bars")
        XCTAssertEqual(r { $0.restartRhythmBars = [1] }, "Rhythm restarts every bar")
        XCTAssertEqual(r { $0.restartRhythmBars = [1]; $0.restartRhythmUnit = .pass; $0.restartRhythmSource = 1 }, "Rhythm restarts every pass of lane 2")
        XCTAssertEqual(r { $0.restartRhythmBars = [1]; $0.restartRhythmUnit = .riff; $0.restartRhythmSource = 0 }, "Rhythm restarts every riff")
        XCTAssertEqual(r { $0.restartRhythmBars = [2]; $0.restartRhythmUnit = .riff; $0.restartRhythmSource = 2 }, "Rhythm restarts every 2 riffs of lane 3")
        XCTAssertEqual(m { $0.restartMelodyPasses = [1] }, "Melody restarts every pass")
        XCTAssertEqual(m { $0.restartMelodyPasses = [3]; $0.restartMelodyUnit = .hit }, "Melody restarts every 3 hits")
        XCTAssertEqual(m { $0.restartMelodyWithRhythm = true }, "Melody restarts with the rhythm")
        XCTAssertEqual(m { $0.restartMelodyPasses = [2]; $0.restartMelodyUnit = .pass; $0.restartMelodySource = 1; $0.restartMelodyWithRhythm = true }, "Melody restarts every 2 passes of lane 2, and with the rhythm")
        XCTAssertEqual(r { $0.restartRhythmBars = [2, 1, 1] }, "Rhythm restarts after 2 bars, then 1, then 1, repeating")
        XCTAssertEqual(m { _ in }, "Melody restarts, free")
    }
    func testTheTileFitDropsTheUnitFirstThenTruncatesTheName() {
        let wide = euclideousRestartTileFit(spec: euclideousRestartTileSpec(rhythm: true, settings: settings { $0.restartRhythmBars = [2] }, ownLane: 0), name: "RHYTHM", tileWidth: 300)
        XCTAssertTrue(wide.showsUnit); XCTAssertFalse(wide.nameTruncates)
        // "2" PASS with the glyph and lane 2's square just fits beside "MELODY RESTART" at the live landscape width (171.8): the unit stays
        let short = euclideousRestartTileSpec(rhythm: false, settings: settings { $0.restartMelodyPasses = [2]; $0.restartMelodyUnit = .pass; $0.restartMelodySource = 1; $0.restartMelodyWithRhythm = true }, ownLane: 0)
        let fits = euclideousRestartTileFit(spec: short, name: "MELODY", tileWidth: 171.8)
        XCTAssertTrue(fits.showsUnit); XCTAssertFalse(fits.nameTruncates)
        // "2·1·1" PASS with both: the unit goes first — and the name then truncates, even so
        let long = euclideousRestartTileSpec(rhythm: false, settings: settings { $0.restartMelodyPasses = [2, 1, 1]; $0.restartMelodyUnit = .pass; $0.restartMelodySource = 1; $0.restartMelodyWithRhythm = true }, ownLane: 0)
        let narrow = euclideousRestartTileFit(spec: long, name: "MELODY", tileWidth: 171.8)
        XCTAssertFalse(narrow.showsUnit, "the glyph, the square and the value leave no room for the unit at the live landscape width"); XCTAssertTrue(narrow.nameTruncates)
        let tiny = euclideousRestartTileFit(spec: short, name: "MELODY", tileWidth: 100)
        XCTAssertFalse(tiny.showsUnit); XCTAssertTrue(tiny.nameTruncates, "…then the name truncates")
    }

    // MARK: test 16 — the editor's logic

    func testAUnitChangeIsOneEditAndFixesWhatItMust() {
        var l = pinned(); l.restartRhythmBars = [2]
        XCTAssertFalse(euclideousApplyRestartEdit(.unit(rhythm: true, index: 0), to: &l, lane: 0, pin: nil), "selecting the selected unit does nothing")
        XCTAssertTrue(euclideousApplyRestartEdit(.unit(rhythm: true, index: 1), to: &l, lane: 0, pin: nil))
        XCTAssertEqual(l.restartRhythmUnit, .pass); XCTAssertEqual(l.restartRhythmSource, 1, "RHYTHM PASS on the lane itself moves the source to the next lane, in the same step")
        var l4 = pinned(); l4.restartRhythmBars = [1]
        euclideousApplyRestartEdit(.unit(rhythm: true, index: 1), to: &l4, lane: 3, pin: nil)
        XCTAssertEqual(l4.restartRhythmSource, 0, "lane 4 wraps to lane 1")
        var keep = pinned(); keep.restartRhythmBars = [1]; keep.restartRhythmSource = 2
        euclideousApplyRestartEdit(.unit(rhythm: true, index: 1), to: &keep, lane: 0, pin: nil)
        XCTAssertEqual(keep.restartRhythmSource, 2, "another lane's source is kept")
        // leaving HIT maps links 5 → 6 and 7 → 8
        var m = pinned(); m.restartMelodyUnit = .hit; m.restartMelodyPasses = [5, 7, 3, 8]
        XCTAssertTrue(euclideousApplyRestartEdit(.unit(rhythm: false, index: 0), to: &m, lane: 0, pin: nil))
        XCTAssertEqual(m.restartMelodyUnit, .pass); XCTAssertEqual(m.restartMelodyPasses, [6, 8, 3, 8])
        var toBar = pinned(); toBar.restartMelodyUnit = .hit; toBar.restartMelodyPasses = [5]
        euclideousApplyRestartEdit(.unit(rhythm: false, index: 1), to: &toBar, lane: 0, pin: nil)
        XCTAssertEqual(toBar.restartMelodyPasses, [6])
        var toHit = pinned(); toHit.restartMelodyPasses = [6]
        euclideousApplyRestartEdit(.unit(rhythm: false, index: 2), to: &toHit, lane: 0, pin: nil)
        XCTAssertEqual(toHit.restartMelodyPasses, [6], "entering HIT keeps its links (all valid there)")
    }
    func testTheSourceSquares() {
        var l = pinned(); l.restartRhythmBars = [1]; l.restartRhythmUnit = .pass; l.restartRhythmSource = 2
        XCTAssertTrue(euclideousRestartSourceUnavailable(rhythm: true, line: l, ownLane: 0, square: 0), "the lane itself, on RHYTHM PASS")
        XCTAssertFalse(euclideousRestartSourceUnavailable(rhythm: true, line: l, ownLane: 0, square: 1))
        XCTAssertFalse(euclideousApplyRestartEdit(.source(rhythm: true, lane: 0), to: &l, lane: 0, pin: nil), "an unavailable square takes no taps")
        XCTAssertTrue(euclideousApplyRestartEdit(.source(rhythm: true, lane: 3), to: &l, lane: 0, pin: nil)); XCTAssertEqual(l.restartRhythmSource, 3)
        XCTAssertFalse(euclideousApplyRestartEdit(.source(rhythm: true, lane: 3), to: &l, lane: 0, pin: nil), "tapping the selected square changes nothing")
        l.restartRhythmUnit = .riff
        XCTAssertFalse(euclideousRestartSourceUnavailable(rhythm: true, line: l, ownLane: 0, square: 0), "RIFF may count the lane itself")
        XCTAssertTrue(euclideousApplyRestartEdit(.source(rhythm: true, lane: 0), to: &l, lane: 0, pin: nil))
        var bar = pinned(); bar.restartRhythmBars = [1]
        XCTAssertFalse(euclideousApplyRestartEdit(.source(rhythm: true, lane: 2), to: &bar, lane: 0, pin: nil), "BAR reads no source: the squares are not shown")
    }
    func testLinkSteppingForBothValueSets() {
        var l = pinned(); l.restartRhythmBars = [1]
        var seen: [[UInt8]] = []
        for _ in 0..<7 { euclideousApplyRestartEdit(.tapLink(rhythm: true, slot: 0), to: &l, lane: 0, pin: nil); seen.append(l.restartRhythmBars ?? []) }
        XCTAssertEqual(seen, [[2], [3], [4], [6], [8], [], []], "1 → 2 → 3 → 4 → 6 → 8, one more tap removes the link (a tap on the now-empty slot does nothing)")
        var h = pinned(); h.restartMelodyUnit = .hit; h.restartMelodyPasses = [1]
        var hs: [[UInt8]] = []
        for _ in 0..<8 { euclideousApplyRestartEdit(.tapLink(rhythm: false, slot: 0), to: &h, lane: 0, pin: nil); hs.append(h.restartMelodyPasses ?? []) }
        XCTAssertEqual(hs, [[2], [3], [4], [5], [6], [7], [8], []], "HIT steps 1 … 8")
        // later links move left; removing the last link turns the switch off
        var m = pinned(); m.restartRhythmBars = [8, 3]
        euclideousApplyRestartEdit(.tapLink(rhythm: true, slot: 0), to: &m, lane: 0, pin: nil)
        XCTAssertEqual(m.restartRhythmBars, [3], "[8, 3] → tap link 1 removes it, the next moves left")
        XCTAssertNotEqual(m.restartRhythmOn, false)
        euclideousApplyRestartEdit(.tapLink(rhythm: true, slot: 0), to: &m, lane: 0, pin: nil)
        XCTAssertEqual(m.restartRhythmBars, [4])
        var last = pinned(); last.restartRhythmBars = [8]
        euclideousApplyRestartEdit(.tapLink(rhythm: true, slot: 0), to: &last, lane: 0, pin: nil)
        XCTAssertEqual(last.restartRhythmBars, []); XCTAssertEqual(last.restartRhythmOn, false, "removing the last link turns the switch off")
        // + appends a 1, up to four
        var p = pinned()
        for _ in 0..<5 { euclideousApplyRestartEdit(.addLink(rhythm: false), to: &p, lane: 0, pin: nil) }
        XCTAssertEqual(p.restartMelodyPasses, [1, 1, 1, 1])
    }
    func testTheSwitchAndWithRhythm() {
        var l = pinned()
        XCTAssertTrue(euclideousApplyRestartEdit(.toggleOn(rhythm: true), to: &l, lane: 0, pin: nil))
        XCTAssertEqual(l.restartRhythmBars, [1], "turning on a chain with no links also appends a 1"); XCTAssertTrue(l.restartRhythmOnResolved)
        XCTAssertTrue(euclideousApplyRestartEdit(.toggleOn(rhythm: true), to: &l, lane: 0, pin: nil))
        XCTAssertEqual(l.restartRhythmBars, [1], "off keeps its links"); XCTAssertFalse(l.restartRhythmOnResolved)
        euclideousApplyRestartEdit(.tapLink(rhythm: true, slot: 0), to: &l, lane: 0, pin: nil)
        XCTAssertFalse(l.restartRhythmOnResolved, "an edit to a switched-off row does not turn the switch on"); XCTAssertEqual(l.restartRhythmBars, [2])
        euclideousApplyRestartEdit(.toggleOn(rhythm: true), to: &l, lane: 0, pin: nil)
        XCTAssertEqual(l.restartRhythmBars, [2], "back on restores them"); XCTAssertTrue(l.restartRhythmOnResolved)
        var m = pinned()
        XCTAssertTrue(euclideousApplyRestartEdit(.withRhythm, to: &m, lane: 0, pin: nil)); XCTAssertTrue(m.restartMelodyWithRhythmResolved)
        XCTAssertTrue(euclideousApplyRestartEdit(.withRhythm, to: &m, lane: 0, pin: nil)); XCTAssertFalse(m.restartMelodyWithRhythmResolved)
    }
    func testTheFirstEditOfAnUnpinnedLanePinsItsChainsInTheSameStep() {
        var l = EuclidLine()   // a pre-feature lane: both chains nil
        XCTAssertFalse(l.usesRestartChains)
        let pin = (rhythm: EuclideousRestartChain.from([2, 1]), melody: EuclideousRestartChain.from([4]))
        XCTAssertTrue(euclideousApplyRestartEdit(.withRhythm, to: &l, lane: 0, pin: pin))
        XCTAssertEqual(l.restartRhythmBars, [2, 1]); XCTAssertEqual(l.restartMelodyPasses, [4]); XCTAssertTrue(l.restartMelodyWithRhythmResolved)
        // an edit that changes nothing leaves even the pin undone — no step is recorded for it
        var untouched = EuclidLine()
        XCTAssertFalse(euclideousApplyRestartEdit(.source(rhythm: true, lane: 2), to: &untouched, lane: 0, pin: nil))
    }

    // MARK: test 18 — the timeline

    func testTheTimelineWindowsLabelsAndMarks() {
        let units: [(String, Bool)] = [("bar", true), ("pass", true), ("riff", true), ("hit", false)]
        for (word, rhythm) in units {
            let chain = EuclideousRestartChain.from([2, 1, 1])
            let t0 = euclideousRestartTimeline(chain: chain, active: true, unitWord: word, current: 0, rhythm: rhythm)
            XCTAssertEqual(t0.axisLabel, "\(word.uppercased()) 1\u{2013}16"); XCTAssertEqual(t0.windowStart, 0); XCTAssertEqual(t0.currentCell, 0)
            // [2,1,1] restarts at units 0, 2, 3, then 4, 6, 7, 8, 10, 11, 12, 14, 15 …
            XCTAssertEqual(t0.cells.enumerated().filter { $0.element.isMark }.map { $0.offset }, [0, 2, 3, 4, 6, 7, 8, 10, 11, 12, 14, 15], word)
            // the shade: the window's first cell is high; it switches at each later mark
            XCTAssertEqual(t0.cells.map { $0.shadeHigh }, [true, true, false, true, false, false, true, false, true, true, false, true, false, false, true, false], word)
        }
        let t2 = euclideousRestartTimeline(chain: EuclideousRestartChain.from([2, 1, 1]), active: true, unitWord: "pass", current: 20, rhythm: true)
        XCTAssertEqual(t2.axisLabel, "PASS 17\u{2013}32"); XCTAssertEqual(t2.windowStart, 16); XCTAssertEqual(t2.currentCell, 4)
        XCTAssertEqual(euclideousRestartTimeline(chain: .from([3]), active: true, unitWord: "hit", current: 40, rhythm: false).axisLabel, "HIT 33\u{2013}48")
        XCTAssertEqual(euclideousRestartTimeline(chain: .from([1]), active: true, unitWord: "riff", current: 5, rhythm: true).cells.filter { $0.isMark }.count, 16, "[1] marks every cell")
        // inactive: every cell flat, nothing to speak
        let off = euclideousRestartTimeline(chain: EuclideousRestartChain.from([2]), active: false, unitWord: "bar", current: 3, rhythm: true)
        XCTAssertTrue(off.cells.allSatisfy { !$0.isMark }); XCTAssertEqual(off.spoken, "No restarts")
        XCTAssertEqual(euclideousRestartTimeline(chain: .from([1]), active: true, unitWord: "riff", current: 0, rhythm: true).spoken, "Rhythm restarts at riffs 1, 2, 3, 4, …")
    }
    func testTheCurrentUnitFromTheScheduleForEveryUnit() {
        var a = EuclidLine(target: 0, pulses: 3, steps: 8); a.rate = .r1_8; a.restartRhythmBars = [1]; a.restartRhythmUnit = .riff; a.restartRhythmSource = 0
        var b = EuclidLine(target: 0, pulses: 5, steps: 12); b.rate = .r1_16; b.restartRhythmBars = []; b.restartMelodyPasses = []
        let lines = [a, b, EuclidLine(), EuclidLine()].map { l -> EuclidLine in var x = l; if x.restartRhythmBars == nil { x.restartRhythmBars = [] }; x.restartMelodyPasses = x.restartMelodyPasses ?? []; return x }
        let set = euclideousRestartScheduleSet(lines: lines, barBeats: 4, defaultRateBeats: 0.25, riffColumns: 8)
        let s = euclideousRestartSettings(line: lines[0], lane: 0)
        func unit(_ rhythm: Bool, _ st: EuclideousRestartSettings, beat: Double) -> Int { euclideousRestartCurrentUnit(rhythm: rhythm, settings: st, ownLane: 0, beat: beat, barBeats: 4, set: set) }
        XCTAssertEqual(unit(true, s, beat: 9.9), 0, "RIFF: the lane's riff completes at 9.5 → the event is at 10, so before 10 none have completed")
        XCTAssertEqual(unit(true, s, beat: 10.1), 1); XCTAssertEqual(unit(true, s, beat: 20.1), 2)
        var bar = s; bar.rhythmUnit = .bar
        XCTAssertEqual(unit(true, bar, beat: 9.9), 2, "BAR: the bar holding now"); XCTAssertEqual(unit(true, bar, beat: 16.0), 4)
        var pass = s; pass.rhythmUnit = .pass; pass.rhythmSource = 1
        XCTAssertEqual(unit(true, pass, beat: 7.0), 2, "PASS: lane 2's pass index (a pass every 3 beats)")
        var hit = s; hit.melodyUnit = .hit
        XCTAssertEqual(unit(false, hit, beat: 0.1), 0, "HIT: never below 0 (one hit played → cell 0)"); XCTAssertEqual(unit(false, hit, beat: 1.6), 1, "two hits played → cell 1")
        XCTAssertEqual(euclideousRestartCurrentUnit(rhythm: true, settings: s, ownLane: 0, beat: 50, barBeats: 4, set: nil), 0, "no schedule yet reads 0")
    }

    // MARK: test 19 — geometry

    func testTheEditorsFramesAtTheReference() {
        typealias M = EuclideousRestartEditorMetricsV2
        let f = euclideousRestartEditorFramesV2(size: CGSize(width: 338.5, height: 208))
        XCTAssertEqual(f.header, CGRect(x: 8, y: 8, width: 322.5, height: 20)); XCTAssertEqual(f.rightWidth, 262.5, accuracy: 1e-9); XCTAssertTrue(f.showsTimelines); XCTAssertTrue(f.row1Fits)
        XCTAssertEqual(f.rhythm.top, 36); XCTAssertEqual(f.melody.top, 122); XCTAssertEqual(f.melody.top + M.sectionH, 200, "ends at y 200")
        for (sec, melody) in [(f.rhythm, false), (f.melody, true)] {
            XCTAssertEqual(sec.labelColumn, CGRect(x: 8, y: sec.top, width: 56, height: 24))
            XCTAssertEqual(sec.chips.map { $0.minX }, [68, 112, 156]); XCTAssertTrue(sec.chips.allSatisfy { $0.width == 40 && $0.height == 24 })
            XCTAssertEqual(sec.sources.map { $0.minX }, [204, 226, 248, 270], "the source squares' 18 × 24 hit areas"); XCTAssertTrue(sec.sources.allSatisfy { $0.width == 18 && $0.height == 24 })
            XCTAssertEqual(sec.switchTrack, CGRect(x: 296.5, y: sec.top + 2, width: 34, height: 20)); XCTAssertEqual(sec.switchHit, CGRect(x: 296.5, y: sec.top, width: 34, height: 24)); XCTAssertEqual(sec.switchTrack.maxX, 330.5)
            XCTAssertEqual(sec.slots.map { $0.minX }, [68, 134.625, 201.25, 267.875]); XCTAssertEqual(sec.slots[0].width, 62.625, accuracy: 1e-9); XCTAssertTrue(sec.slots.allSatisfy { $0.minY == sec.top + 28 && $0.height == 32 })
            XCTAssertEqual(sec.axisLabel, CGRect(x: 8, y: sec.top + 64, width: 56, height: 14))
            XCTAssertEqual(sec.cells.count, 16); XCTAssertEqual(sec.cells[0].width, 14.53125, accuracy: 1e-9, "(262.5 − 30) ÷ 16 = 14.53"); XCTAssertEqual(sec.cells[1].minX - sec.cells[0].maxX, 2, accuracy: 1e-9)
            XCTAssertTrue(sec.cells.allSatisfy { $0.height == 14 && $0.minY == sec.top + 64 }); XCTAssertEqual(sec.cells.last!.maxX, 330.5, accuracy: 1e-9)
            XCTAssertEqual(sec.withRhythm != nil, melody)
        }
        XCTAssertEqual(f.melody.withRhythm, CGRect(x: 12, y: 122 + 28, width: 52, height: 32))
        XCTAssertFalse(f.clipsBottom)
    }
    func testTheEditorAtZoneTotals208And172AndTheLiveSizes() {
        let tall = euclideousRestartEditorFramesV2(size: CGSize(width: 338.5, height: 229))
        XCTAssertTrue(tall.showsTimelines); XCTAssertEqual(tall.rhythm.top, 36 + 10.5, accuracy: 1e-9); XCTAssertEqual(tall.melody.top, 122 + 21, accuracy: 1e-9, "the 21 pt over the reference is shared by the two upper gaps")
        XCTAssertEqual(tall.melody.top + 78, 229 - 8, accuracy: 1e-9, "the bottom padding stays 8")
        let under = euclideousRestartEditorFramesV2(size: CGSize(width: 338.5, height: 207))
        XCTAssertFalse(under.showsTimelines, "under 208: each section's timeline and the 4 before it are dropped"); XCTAssertTrue(under.rhythm.cells.isEmpty); XCTAssertNil(under.rhythm.axisLabel)
        XCTAssertEqual(under.rhythm.top, 36); XCTAssertEqual(under.melody.top, 36 + 60 + 8)
        let compact = euclideousRestartEditorFramesV2(size: CGSize(width: 338.5, height: 172))
        XCTAssertFalse(compact.clipsBottom, "the editor then needs 172"); XCTAssertEqual(compact.melody.top + 60 + 8, 172, accuracy: 1e-9)
        XCTAssertTrue(euclideousRestartEditorFramesV2(size: CGSize(width: 338.5, height: 171)).clipsBottom, "below that its bottom edge clips")
        // the sizes the page gives it
        let land = euclideousRestartEditorFramesV2(size: CGSize(width: 360.67, height: 229)), port = euclideousRestartEditorFramesV2(size: CGSize(width: 367, height: 229.67))
        XCTAssertEqual(land.rightWidth, 360.67 - 16 - 60, accuracy: 1e-9); XCTAssertEqual(land.rhythm.slots[0].width, (land.rightWidth - 12) / 4, accuracy: 1e-9); XCTAssertEqual(land.rhythm.cells[0].width, (land.rightWidth - 30) / 16, accuracy: 1e-9)
        XCTAssertEqual(land.rhythm.switchTrack.maxX, 360.67 - 8, accuracy: 1e-9, "the switch stays at the trailing edge"); XCTAssertTrue(land.row1Fits); XCTAssertTrue(port.row1Fits)
        let narrow = euclideousRestartEditorFramesV2(size: CGSize(width: 300, height: 229))
        XCTAssertFalse(narrow.row1Fits, "RW below 262 is reported, never shrunk"); XCTAssertEqual(narrow.rhythm.chips[0].width, 40)
    }
    /// §7.6: the editor's size at every page layout the layout tests pin (the card's body: card height − 72, card width − 20), and what the frames do there. Reported for the ferry's notes; the assertions are the floors the spec states.
    func testTheEditorSizeAtEveryPageLayout() {
        var rows: [String] = []
        for v in [CGSize(width: 1190, height: 726), CGSize(width: 1400, height: 900), CGSize(width: 814, height: 1102), CGSize(width: 1000, height: 1300), CGSize(width: 744, height: 1133), CGSize(width: 1024, height: 768), CGSize(width: 1366, height: 1024)] {
            let lay = euclideousPageLayout(size: v)
            let box = lay.laneBox
            let ed = CGSize(width: EuclideousLaneCardMetrics.innerWidth(cardWidth: box.width), height: EuclideousLaneCardMetrics.contentAreaH(cardHeight: box.height))
            let f = euclideousRestartEditorFramesV2(size: ed)
            rows.append("view \(Int(v.width))×\(Int(v.height)) card \(String(format: "%.2f×%.2f", box.width, box.height)) editor \(String(format: "%.2f×%.2f", ed.width, ed.height)) timelines \(f.showsTimelines) row1Fits \(f.row1Fits) clipsBottom \(f.clipsBottom) rightW \(String(format: "%.2f", f.rightWidth))")
            XCTAssertFalse(f.clipsBottom, "the editor never clips at a layout the page draws: \(rows.last!)")
            XCTAssertEqual(lay.floors.contains(.restartEditor), !f.row1Fits || f.clipsBottom, "the page's floors report exactly what the editor's frames say: \(rows.last!)")
        }
        print("RESTART UNITS editor sizes:\n" + rows.joined(separator: "\n"))
    }

    // MARK: adversarial review (2026-11-04)

    /// "Remove link" is ONE edit: the neighbouring link keeps its value (the old walk of taps stepped it on: [2, 3] → [4]).
    func testRemoveLinkRemovesExactlyThatLinkAndNothingElse() {
        var l = EuclidLine(); l.restartRhythmBars = [2, 3]; l.restartRhythmOn = true
        XCTAssertTrue(euclideousApplyRestartEdit(.removeLink(rhythm: true, slot: 0), to: &l, lane: 0, pin: nil))
        XCTAssertEqual(l.restartRhythmBars, [3]); XCTAssertEqual(l.restartRhythmOn, true, "the switch stays on while a link remains")
        XCTAssertTrue(euclideousApplyRestartEdit(.removeLink(rhythm: true, slot: 0), to: &l, lane: 0, pin: nil))
        XCTAssertEqual(l.restartRhythmBars, []); XCTAssertEqual(l.restartRhythmOn, false, "removing the last link switches the chain off")
        XCTAssertFalse(euclideousApplyRestartEdit(.removeLink(rhythm: true, slot: 0), to: &l, lane: 0, pin: nil), "nothing to remove: no edit")
        var m = EuclidLine(); m.restartMelodyPasses = [5, 7]; m.restartMelodyUnit = .hit; m.restartMelodyOn = true
        XCTAssertTrue(euclideousApplyRestartEdit(.removeLink(rhythm: false, slot: 1), to: &m, lane: 1, pin: nil))
        XCTAssertEqual(m.restartMelodyPasses, [5], "a HIT link keeps its value")
    }
    /// The lane's own square is stored as nil (the default), so a source set back to the lane's own is the same document as one never set.
    func testTheLanesOwnSourceIsStoredAsNilAndSoCannotLookLikeALockDeviation() {
        var l = EuclidLine(); l.restartRhythmBars = [1]; l.restartRhythmUnit = .riff
        let f = LaneLockFields(line: l)
        euclideousApplyRestartEdit(.source(rhythm: true, lane: 2), to: &l, lane: 2, pin: nil)   // lane 3's own square: already selected — no edit
        XCTAssertNil(l.restartRhythmSource)
        euclideousApplyRestartEdit(.source(rhythm: true, lane: 0), to: &l, lane: 2, pin: nil)
        XCTAssertEqual(l.restartRhythmSource, 0); XCTAssertTrue(euclideousLockDeviated(line: l, from: f), "lane 1's riff is a different restart")
        euclideousApplyRestartEdit(.source(rhythm: true, lane: 2), to: &l, lane: 2, pin: nil)   // back to the lane's own
        XCTAssertNil(l.restartRhythmSource, "stored as nil, not as an explicit own lane"); XCTAssertFalse(euclideousLockDeviated(line: l, from: f))
    }
}

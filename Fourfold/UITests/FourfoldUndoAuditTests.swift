//  FourfoldUndoAuditTests.swift — UNDO AUDIT layer 2 (Docs/pending-tasks.md "UNDO AUDIT"): the REAL app — real funnels, real model, real AU — attacked through the glass, with a read-out of the page's undo state, the document and the render input
//  after every operation. Launched `--fresh --undo-probe` (Fourfold/Shared/FourfoldUndoProbe.swift adds one hidden element, "Undo probe", whose value looks like
//    snap=… doc=… agree=1 stage=1 box=1 undo=3 redo=0 resyncs=0 pend=0 lanes=8/3r0,16/5r0,8/0r0,8/0r0
//  and two 8 pt buttons that do what an AUv3 HOST does behind the page's back). Tests that assert the IDEAL behaviour and currently fail are named `testBREAK_…` and wrapped in XCTExpectFailure (strict), so they stay green and
//  flip loudly the day the break is fixed; `testPOLICY_…` checks the app against the key policy as it is written today (everything but that policy must hold).

import XCTest

struct UndoProbeReading {
    let raw: String
    let kv: [String: String]
    init(_ raw: String) {
        self.raw = raw
        var d: [String: String] = [:]
        for part in raw.split(separator: " ") { let p = part.split(separator: "=", maxSplits: 1); if p.count == 2 { d[String(p[0])] = String(p[1]) } }
        kv = d
    }
    var snap: String { kv["snap"] ?? "?" }
    var consistent: Bool { kv["agree"] == "1" && kv["stage"] == "1" && kv["box"] == "1" }
    var undo: Int { Int(kv["undo"] ?? "") ?? -1 }
    var redo: Int { Int(kv["redo"] ?? "") ?? -1 }
    var resyncs: Int { Int(kv["resyncs"] ?? "") ?? -1 }
    var pend: Int { Int(kv["pend"] ?? "") ?? -1 }
    var voices: Int { Int(kv["voices"] ?? "") ?? -1 }
    var lanes: String { kv["lanes"] ?? "?" }
    var play: String { kv["play"] ?? "?" }
    static let partNames = ["lines", "riff", "resetSpanBars", "keyRoot", "keyType", "chordSets", "activeChordSet", "noteSource", "riffs", "activeRiff", "lanesSeq", "riffsSeq", "fx", "holdLatchMode"]
    var parts: [String] { (kv["parts"] ?? "").split(separator: ",").map(String.init) }
    /// Which snapshot fields differ from `other` — so a failing hash says WHAT is different.
    func differingParts(from other: UndoProbeReading) -> [String] { zip(parts, other.parts).enumerated().filter { $0.element.0 != $0.element.1 }.map { Self.partNames[$0.offset] } }
}

/// The undo contract as a timeline of states with a cursor (the same independent model `UndoAuditTests` fuzzes the real stack against): `moments[cursor]` is the live state; an edit drops everything after the cursor; a keyed edit that
/// continues the open run replaces the live moment instead of adding one; ↶/↷ move the cursor; one that cannot move changes nothing; at most 50 steps back.
private struct Timeline {
    var moments: [String]
    var cursor = 0
    var openKey: String? = nil
    let cap = 50
    init(start: String) { moments = [start] }
    var live: String { moments[cursor] }
    var past: Int { cursor }
    var future: Int { moments.count - 1 - cursor }
    /// `before` is the state the funnel saw; `after` what the edit produced.
    mutating func edit(after: String, key: String?) {
        moments.removeSubrange((cursor + 1)...)
        if let k = key, k == openKey, cursor > 0 { moments[cursor] = after; return }
        moments.append(after); cursor += 1; openKey = key
        if cursor > cap { moments.removeFirst(); cursor -= 1 }
    }
    /// A change that never reached an undo checkpoint (see S11): the live moment is replaced; nothing is recorded and the redo branch is NOT ended.
    mutating func silent(after: String) { moments[cursor] = after }
    mutating func undo() { if cursor > 0 { cursor -= 1; openKey = nil } }
    mutating func redo() { if cursor < moments.count - 1 { cursor += 1; openKey = nil } }
}

private struct SplitMix {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 { s &+= 0x9E37_79B9_7F4A_7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
}

final class FourfoldUndoAuditTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() { continueAfterFailure = true }

    @discardableResult func launch(fresh: Bool = true) -> UndoProbeReading {
        app = XCUIApplication(); app.launchArguments = (fresh ? ["--fresh"] : []) + ["--undo-probe"]; app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        return settled()
    }

    // MARK: reading the probe

    func read() -> UndoProbeReading {
        let e = app.descendants(matching: .any).matching(identifier: "undoProbe").firstMatch
        return UndoProbeReading((e.value as? String) ?? "no probe")
    }
    /// Wait until the page, the 4 Hz poll and the AU's rebuild have all had their say: two identical reads 0.35 s apart.
    func settled() -> UndoProbeReading {
        Thread.sleep(forTimeInterval: 0.45)
        var last = read()
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.35)
            let now = read()
            if now.raw == last.raw { return now }
            last = now
        }
        return last
    }

    // MARK: the operations (each is one gesture, found by the label a VoiceOver user hears)

    func stepsUp() { app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More steps'")).firstMatch.tap() }
    func stepsDown() { app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fewer steps'")).firstMatch.tap() }
    func dragHits(up: Bool) {
        let hits = app.otherElements.matching(NSPredicate(format: "label == 'HITS'")).firstMatch
        hits.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.9 : 0.1)).press(forDuration: 0.05, thenDragTo: hits.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.65)))
    }
    func dragOffset() {
        let o = app.otherElements.matching(NSPredicate(format: "label == 'OFFSET'")).firstMatch
        o.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.05, thenDragTo: o.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
    }
    func tapLabel(_ label: String) { app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch.tap() }
    func noteSource(_ name: String) { app.buttons[name].tap() }
    func riffSwitch(_ n: Int) { app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Riff \(n)")).firstMatch.tap() }
    func loadPreset(_ name: String) {
        app.buttons["Presets"].tap()
        let row = app.buttons["\(name), factory preset"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "preset row \(name)")
        row.tap()
        Thread.sleep(forTimeInterval: 0.3)
    }
    func undo() { app.buttons["Undo"].tap() }
    func redo() { app.buttons["Redo"].tap() }
    private func post(_ name: String) { CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true) }
    func hostLoadsPreset() { post("com.outliermidi.fourfold.undoprobe.hostLoadPreset") }
    func hostRestoresLaunchState() { post("com.outliermidi.fourfold.undoprobe.hostRestoreLaunch") }

    // MARK: the plain facts

    func testTheProbeIsConsistentAtLaunch() {
        let p = launch()
        XCTAssertTrue(p.consistent, p.raw)
        XCTAssertEqual(p.undo, 0); XCTAssertEqual(p.redo, 0); XCTAssertEqual(p.resyncs, 0, "the page and the document start in step: \(p.raw)")
    }

    func testOneEditIsOneStepAndUndoRedoRetraceExactly() {
        let p0 = launch()
        stepsUp(); let p1 = settled()
        XCTAssertNotEqual(p1.snap, p0.snap); XCTAssertEqual(p1.undo, 1); XCTAssertTrue(p1.consistent, p1.raw)
        undo(); let u = settled()
        XCTAssertEqual(u.snap, p0.snap, "undo returns to exactly the launch state"); XCTAssertEqual(u.redo, 1); XCTAssertTrue(u.consistent, u.raw)
        redo(); let r = settled()
        XCTAssertEqual(r.snap, p1.snap, "redo returns to exactly the edited state"); XCTAssertEqual(r.undo, 1); XCTAssertEqual(r.redo, 0); XCTAssertTrue(r.consistent, r.raw)
        XCTAssertEqual(r.resyncs, 0, "nothing here should have made the 4 Hz poll correct the page: \(r.raw)")
    }

    // MARK: S1 — different controls, one key

    func testBREAK_S1_OneUndoWipesEditsToThreeDifferentControls() {
        let p0 = launch()
        stepsUp(); let p1 = settled()          // lane 1 STEPS
        dragHits(up: true); let p2 = settled() // lane 1 HITS
        dragOffset(); let p3 = settled()       // lane 1 OFFSET
        XCTAssertNotEqual(p0.snap, p1.snap); XCTAssertNotEqual(p1.snap, p2.snap); XCTAssertNotEqual(p2.snap, p3.snap, "three real edits: \(p0.lanes) → \(p1.lanes) → \(p2.lanes) → \(p3.lanes)")
        undo(); let u = settled()
        print("UNDOAUDIT S1 steps=\(p1.undo) after-undo lanes=\(u.lanes) undoDepthBefore=\(p3.undo) (ideal one step back to \(p2.lanes); got \(u.snap == p0.snap ? "ALL THE WAY BACK to launch" : u.snap == p1.snap ? "back to after STEPS" : "?"))")
        XCTExpectFailure("S1: one ↶ should undo only the last control's edit", strict: true) {
            XCTAssertEqual(u.snap, p2.snap)
        }
    }

    // MARK: S2 — a no-op touch

    func testBREAK_S2_TouchingAControlWithoutChangingItEndsTheRedoBranch() {
        launch()
        stepsUp(); _ = settled()
        undo(); let afterUndo = settled()
        XCTAssertEqual(afterUndo.redo, 1)
        // riff 1 is already the one being edited: tapping it again changes nothing
        riffSwitch(1); let p = settled()
        print("UNDOAUDIT S2 snapChanged=\(p.snap != afterUndo.snap) redoBefore=\(afterUndo.redo) redoAfter=\(p.redo) undoDepth=\(p.undo)")
        XCTAssertEqual(p.snap, afterUndo.snap, "the tap really was a no-op")
        XCTExpectFailure("S2: touching a control without changing it should not destroy redo", strict: true) {
            XCTAssertEqual(p.redo, 1)
        }
    }

    // MARK: S3 — the document changes under the history

    func testBREAK_S3a_AHostPresetChangeLeavesTheHistoryPointingAtTheOldDocument() {
        let p0 = launch()
        stepsUp(); let edited = settled()
        XCTAssertEqual(edited.undo, 1)
        hostLoadsPreset(); let after = settled()
        XCTAssertNotEqual(after.lanes, edited.lanes, "the host's preset really replaced the lanes: \(edited.lanes) → \(after.lanes)")
        XCTAssertTrue(after.consistent, "after the host's change the page, the document and the engine agree: \(after.raw)")
        print("UNDOAUDIT S3a undoDepthAfterHostLoad=\(after.undo) resyncs=\(after.resyncs)")
        undo(); let u = settled()
        print("UNDOAUDIT S3a after Undo lanes=\(u.lanes) (preset's were \(after.lanes), launch's were \(p0.lanes))")
        XCTExpectFailure("S3: a host-side document change should invalidate the history", strict: true) {
            XCTAssertEqual(after.undo, 0, "↶ must not be offered a step from the previous document")
        }
    }
    func testBREAK_S3b_AHostStateRestoreLeavesTheHistoryPointingAtTheOldDocument() {
        launch()
        loadPreset("FIVE AGAINST EIGHT"); let loaded = settled()
        XCTAssertEqual(loaded.undo, 1)
        hostRestoresLaunchState(); let after = settled()
        XCTAssertNotEqual(after.lanes, loaded.lanes, "the restore changed the document: \(loaded.lanes) → \(after.lanes)")
        XCTAssertTrue(after.consistent, after.raw)
        print("UNDOAUDIT S3b undoDepthAfterHostRestore=\(after.undo)")
        XCTExpectFailure("S3: a host project load should invalidate the history", strict: true) {
            XCTAssertEqual(after.undo, 0)
        }
    }

    // MARK: S4 / S5a — a preset load

    func testAPresetLoadIsOneStepAndUndoRedoRetraceItExactly() {
        let p0 = launch()
        loadPreset("FIVE AGAINST EIGHT"); let loaded = settled()
        XCTAssertNotEqual(loaded.lanes, p0.lanes); XCTAssertEqual(loaded.undo, 1); XCTAssertTrue(loaded.consistent, loaded.raw)
        undo(); let u = settled()
        XCTAssertEqual(u.snap, p0.snap, "undo of a preset load returns to exactly the launch state; differs in \(u.differingParts(from: p0)); play flags launch \(p0.play) loaded \(loaded.play) after undo \(u.play)"); XCTAssertTrue(u.consistent, u.raw)
        redo(); let r = settled()
        XCTAssertEqual(r.snap, loaded.snap, "redo returns to exactly the loaded state (after the poll's own pin): \(r.lanes) vs \(loaded.lanes)"); XCTAssertTrue(r.consistent, r.raw)
    }
    func testBREAK_S4b_UndoingAPresetLoadLeavesTheLanesPlayStopFlagsAsThePresetSetThem() {
        let p0 = launch()
        XCTAssertEqual(p0.play, "1111")
        loadPreset("FIVE AGAINST EIGHT"); let loaded = settled()
        print("UNDOAUDIT S4b play flags launch=\(p0.play) afterLoad=\(loaded.play)")
        XCTAssertNotEqual(loaded.play, p0.play, "the preset turns some lanes off")
        undo(); let u = settled()
        print("UNDOAUDIT S4b play flags after Undo=\(u.play)")
        XCTExpectFailure("S4b: ↶ of a preset load should put the lanes back as they were, play/stop included", strict: true) {
            XCTAssertEqual(u.play, p0.play)
        }
    }
    func testUndoTappedInstantlyAfterAPresetLoadStillRetracesExactly() {
        let p0 = launch()
        loadPreset("FIVE AGAINST EIGHT")
        undo()                                  // inside the 250 ms before the poll pins the loaded lanes' restart chains
        let u = settled()
        XCTAssertEqual(u.snap, p0.snap, "an immediate undo lands exactly on the launch state; differs in \(u.differingParts(from: p0)); play launch \(p0.play) after undo \(u.play)"); XCTAssertTrue(u.consistent, u.raw)
        redo(); let r = settled()
        XCTAssertTrue(r.consistent, r.raw); XCTAssertEqual(r.redo, 0)
        let loadedLanes = r.lanes
        XCTAssertNotEqual(loadedLanes, p0.lanes, "redo brought the preset back: \(r.raw)")
    }

    // MARK: the cap and the monkey

    func testTheDepthCapIsFiftyAndEveryStepBackIsExact() {
        launch()
        var hashes = [read().snap]
        for i in 0..<52 {            // alternating note-source buttons: each tap is its own step (nil key)
            noteSource(i % 2 == 0 ? "Chords" : "Key")
            hashes.append(settledQuick().snap)
        }
        let full = settled()
        XCTAssertEqual(full.undo, 50, "50 steps kept of 52 edits: \(full.raw)")
        for k in 1...50 {
            undo(); let u = settledQuick()
            XCTAssertEqual(u.snap, hashes[52 - k], "step back \(k)")
        }
        undo(); let end = settled()
        XCTAssertEqual(end.undo, 0); XCTAssertEqual(end.redo, 50)
        XCTAssertEqual(end.snap, hashes[2], "the oldest reachable state is the one after edit 2 (edits 1 and 2's pre-states fell off the cap)")
        XCTAssertTrue(end.consistent, end.raw)
    }
    func settledQuick() -> UndoProbeReading { Thread.sleep(forTimeInterval: 0.3); return read() }

    func testSixtyRapidUndoRedoTapsLeaveEverythingConsistent() {
        launch()
        noteSource("Chords"); noteSource("MIDI in"); stepsUp(); riffSwitch(2); noteSource("Key")
        let before = settled()
        for i in 0..<60 { if i % 2 == 0 { undo() } else { redo() } }
        let after = settled()
        XCTAssertEqual(after.snap, before.snap, "an even number of alternating taps returns to the start: \(before.raw) → \(after.raw)")
        XCTAssertTrue(after.consistent, after.raw); XCTAssertEqual(after.resyncs, before.resyncs, "no poll had to correct the page")
        for _ in 0..<30 { undo() }
        let down = settled(); XCTAssertEqual(down.undo, 0, down.raw); XCTAssertTrue(down.consistent, down.raw)
        for _ in 0..<30 { redo() }
        let up = settled(); XCTAssertEqual(up.snap, before.snap, up.raw); XCTAssertEqual(up.redo, 0); XCTAssertTrue(up.consistent, up.raw)
    }

    func testRotatingTheDeviceBetweenUndoAndRedoKeepsTheHistory() {
        launch()
        stepsUp(); let edited = settled()
        undo()
        XCUIDevice.shared.orientation = .portrait; Thread.sleep(forTimeInterval: 1.0)
        XCUIDevice.shared.orientation = .landscapeRight; Thread.sleep(forTimeInterval: 1.0)
        let u = settled(); XCTAssertEqual(u.redo, 1, u.raw)
        redo(); let r = settled()
        XCTAssertEqual(r.snap, edited.snap); XCTAssertTrue(r.consistent, r.raw)
    }

    func testTheHistoryIsNotSavedButTheDocumentIs() {
        launch()
        stepsUp(); let edited = settled()
        XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 1.5)
        app.terminate()
        let p = launch(fresh: false)
        XCTAssertEqual(p.lanes, edited.lanes, "the edit survives a relaunch")
        XCTAssertEqual(p.undo, 0, "…but the history does not: a user cannot undo last session's edit (recorded, not a bug)")
        stepsDown(); _ = settled()      // leave the simulator's saved session as the factory one
        XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 1.5)
    }

    // MARK: S11 — the STEPS + / − buttons stop recording after the first tap

    func testBREAK_S11_OnlyTheFirstTapOnTheStepsButtonsEverMakesAnUndoStep() {
        let p0 = launch()
        stepsUp(); let p1 = settled()
        stepsUp(); let p2 = settled()
        stepsUp(); let p3 = settled()
        XCTAssertEqual([p1.lanes, p2.lanes, p3.lanes], ["9/3r0,16/5r0,8/0r0,8/0r0", "10/3r0,16/5r0,8/0r0,8/0r0", "11/3r0,16/5r0,8/0r0,8/0r0"], "three real edits")
        print("UNDOAUDIT S11 three STEPS taps → undo depth \(p3.undo)")
        undo(); let u = settled()
        print("UNDOAUDIT S11 after one Undo: \(u.lanes) (launch \(p0.lanes)) depth \(u.undo)")
        XCTExpectFailure("S11: every tap on + / − should be its own undo step (one ↶ → 10 steps)", strict: true) {
            XCTAssertEqual(u.lanes, p2.lanes)
        }
    }
    func testBREAK_S11b_AStepsTapAfterAnUndoIsNotRecordedAndRedoThenDiscardsIt() {
        launch()
        stepsUp(); _ = settled()                 // 9 steps — recorded
        undo(); let u = settled()                // 8 steps, redo has the 9
        XCTAssertEqual(u.redo, 1)
        stepsDown(); let edited = settled()      // the user now chooses 7
        XCTAssertEqual(edited.lanes, "7/3r0,16/5r0,8/0r0,8/0r0")
        redo(); let r = settled()
        print("UNDOAUDIT S11b after undo, '−', redo: edited=\(edited.lanes) undoDepth=\(edited.undo) redoDepth=\(edited.redo) → redo gave \(r.lanes)")
        XCTExpectFailure("S11b: a fresh edit ends the redo branch — ↷ must not throw the user's 7 away for the old 9", strict: true) {
            XCTAssertEqual(r.lanes, edited.lanes)
        }
    }

    // MARK: S5b — a queued random roll outlives an undo

    func testBREAK_S5b_ARollQueuedBeforeAnUndoStillLandsOnTheRestoredLane() {
        let p0 = launch()
        app.buttons["Play"].tap()                  // a roll waits for the next bar line, which only comes while the transport runs
        Thread.sleep(forTimeInterval: 0.5)
        stepsUp(); let edited = settled()
        XCTAssertNotEqual(edited.lanes, p0.lanes)
        app.buttons["Random mode"].tap()
        let throwBtn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Throw a new'")).firstMatch
        XCTAssertTrue(throwBtn.waitForExistence(timeout: 5), "random mode shows THROW")
        throwBtn.tap()
        let queued = read()
        undo(); let u = read()
        print("UNDOAUDIT S5b queued pend=\(queued.pend) lanes=\(queued.lanes) → right after Undo: pend=\(u.pend) lanes=\(u.lanes) (launch \(p0.lanes))")
        Thread.sleep(forTimeInterval: 8)          // past the next bar line
        let later = settled()
        print("UNDOAUDIT S5b 8 s later: pend=\(later.pend) lanes=\(later.lanes) undoDepth=\(later.undo) redoDepth=\(later.redo)")
        XCTAssertTrue(later.consistent, later.raw)
        app.buttons["Random mode"].tap()            // finish the random session: kept tabs become undo steps
        let finished = settled()
        print("UNDOAUDIT S5b after finishing random mode: lanes=\(finished.lanes) undoDepth=\(finished.undo)")
        undo(); let afterUndo = settled()
        print("UNDOAUDIT S5b ↶ after finishing: lanes=\(afterUndo.lanes) (edited lanes were \(edited.lanes), launch \(p0.lanes))")
        XCTExpectFailure("S5b: ↶ of the roll must return the lane to where it was before the roll — never to a state the user had already undone (9 steps)", strict: true) {
            XCTAssertEqual(afterUndo.lanes, p0.lanes)
        }
        app.buttons["Stop"].tap()
    }

    // MARK: under the live engine

    func testUndoRedoStormWhilePlayingLeavesTheEngineConsistentAndSilent() {
        launch()
        app.buttons["Play"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        noteSource("Chords"); noteSource("Key"); riffSwitch(2); stepsUp(); noteSource("MIDI in"); noteSource("Key")
        let before = settled()
        for i in 0..<40 { if i % 3 == 2 { redo() } else { undo() }; if i % 10 == 9 { let m = read(); XCTAssertTrue(m.consistent, "mid-storm: \(m.raw)") } }
        let mid = settled()
        XCTAssertTrue(mid.consistent, mid.raw); XCTAssertEqual(mid.resyncs, before.resyncs, "no poll had to correct the page during the storm: \(mid.raw)")
        app.buttons["Stop"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        let stopped = settled()
        print("UNDOAUDIT storm voices after stop=\(stopped.voices) consistent=\(stopped.consistent) undo=\(stopped.undo) redo=\(stopped.redo)")
        XCTAssertEqual(stopped.voices, 0, "nothing may be left sounding after the storm and a stop: \(stopped.raw)")
        XCTAssertTrue(stopped.consistent, stopped.raw)
    }

    // MARK: the fuzz against the policy as written

    private enum Op: CustomStringConvertible {
        case stepsUp, stepsDown, hits(Bool), offset, source(String), riff(Int), riffCell(Int, Int), keyScale, preset(String), undo, redo
        var description: String {
            switch self {
            case .stepsUp: return "steps+"; case .stepsDown: return "steps−"; case .hits(let u): return "hits\(u ? "↑" : "↓")"; case .offset: return "offset"
            case .source(let s): return "source:\(s)"; case .riff(let n): return "riff\(n)"; case .riffCell(let st, let r): return "cell(step \(st) rank \(r))"; case .keyScale: return "key-scale"
            case .preset(let p): return "preset:\(p)"; case .undo: return "UNDO"; case .redo: return "REDO"
            }
        }
        /// The coalesce key the page's funnel records this under (FourfoldRootView.swift): nil = a discrete step.
        var key: String? {
            switch self {
            case .hits, .offset: return "euclideous"                       // STEPS goes through `editStep` (a nil-key checkpoint per tap), HITS / OFFSET through `onEdit`
            case .riffCell: return "euclideousRiffs"                      // the riff grid's one write path (`onEditRiffs`)
            default: return nil
            }
        }
        var isEdit: Bool { switch self { case .undo, .redo: return false; default: return true } }
    }

    /// The oracle is the undo contract applied to probe hashes: every edit funnel records the state BEFORE the edit under its key; ↶/↷ move the cursor. Anything else — the apply, the mirror, the document, the engine — has to agree.
    private func runFuzz(seed: UInt64, length: Int) {
        var rng = SplitMix(seed)
        let first = launch()
        var oracle = Timeline(start: first.snap)
        var upCount = 0, lastSource = "Key", keyIsMinor = true, stepsRecordedOnce = false      // S11: the STEPS buttons only ever record their FIRST tap (until the value box is touched or the tab is left)
        var log: [String] = []
        for i in 0..<length {
            let op: Op
            switch rng.int(0...15) {
            case 0, 1: op = upCount < 3 ? .stepsUp : .stepsDown
            case 2: op = .hits(rng.int(0...1) == 0)
            case 3: op = .offset
            case 4, 5: op = .source(["Chords", "Key", "MIDI in"].filter { $0 != lastSource }[rng.int(0...1)])
            case 6: op = .riff(rng.int(2...4))
            case 7: op = .preset("FIVE AGAINST EIGHT")
            case 8, 9: op = .riffCell(rng.int(1...8), rng.int(1...8))
            case 10: op = .keyScale
            case 11, 12, 13: op = .undo
            default: op = .redo
            }
            log.append(op.description)
            let beforeResyncs = read().resyncs
            switch op {
            case .stepsUp: stepsUp(); upCount += 1
            case .stepsDown: stepsDown(); upCount -= 1
            case .hits(let u): dragHits(up: u)
            case .offset: dragOffset()
            case .source(let s): noteSource(s); lastSource = s
            case .riff(let n): riffSwitch(n)
            case .riffCell(let st, let r): app.buttons["Step \(st), rank \(r)"].firstMatch.tap()
            case .keyScale:
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Key, '")).firstMatch.tap()
                app.staticTexts[keyIsMinor ? "MAJOR" : "MINOR"].tap(); keyIsMinor.toggle()
            case .preset(let p): loadPreset(p)
            case .undo: undo()
            case .redo: redo()
            }
            let p = settled()
            switch op {
            case .undo: oracle.undo()
            case .redo: oracle.redo()
            case .stepsUp, .stepsDown:
                if stepsRecordedOnce { oracle.silent(after: p.snap) } else { oracle.edit(after: p.snap, key: nil); stepsRecordedOnce = true }
            case .source:
                // the note-source control ignores a tap on the segment that is already selected (nothing reaches `onSetNoteSource`), and the test cannot always know which one that is after an undo
                let evidence = p.undo > oracle.past || (oracle.future > 0 && p.redo == 0)
                if p.snap != oracle.live || evidence { oracle.edit(after: p.snap, key: nil) }
            case .hits, .offset:
                // a slider commits whenever its value changes DURING the gesture — a drag that wanders off and comes back to where it began (HITS: the press lands on 7, the finger ends on 3) still records, and ends the redo branch; one
                // that never moves records nothing. The probe can't see inside the gesture, so the evidence is the page's own counters: a deeper undo, or a redo branch that vanished.
                let evidence = p.undo > oracle.past || (oracle.future > 0 && p.redo == 0)
                if p.snap != oracle.live || evidence { oracle.edit(after: p.snap, key: op.key) }
            default: oracle.edit(after: p.snap, key: op.key)       // a tap on a button reaches its funnel whether or not the value changes; what it produced is whatever the app says — the claim under test is what undo/redo do with it
            }
            let ctx = "seed \(seed) op \(i) [\(op)] — history: \(log.joined(separator: ", "))\n  probe: \(p.raw)"
            XCTAssertEqual(p.snap, oracle.live, "the page's state is not what the history says it should be\n  \(ctx)")
            XCTAssertEqual(p.undo, oracle.past, "undo depth\n  \(ctx)")
            XCTAssertEqual(p.redo, oracle.future, "redo depth\n  \(ctx)")
            XCTAssertTrue(p.consistent, "page / document / engine disagree\n  \(ctx)")
            XCTAssertEqual(p.resyncs, beforeResyncs, "the 4 Hz poll had to correct the page after this op\n  \(ctx)")
            if p.snap != oracle.live || p.undo != oracle.past || !p.consistent { print("UNDOAUDIT FUZZ STOPPED \(ctx)"); return }
        }
    }
    func testPOLICY_RandomEditsUndoAndRedoAgreeWithTheHistoryContract_seed1() { runFuzz(seed: 1, length: 40) }
    func testPOLICY_RandomEditsUndoAndRedoAgreeWithTheHistoryContract_seed2() { runFuzz(seed: 2, length: 40) }
    func testPOLICY_RandomEditsUndoAndRedoAgreeWithTheHistoryContract_seed3() { runFuzz(seed: 3, length: 40) }
    func testPOLICY_RandomEditsUndoAndRedoAgreeWithTheHistoryContract_seed4() { runFuzz(seed: 4, length: 40) }
    func testPOLICY_RandomEditsUndoAndRedoAgreeWithTheHistoryContract_seed5() { runFuzz(seed: 5, length: 40) }
}

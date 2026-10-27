//  FourfoldUndoAuditTests.swift — UNDO AUDIT layer 2 (Docs/pending-tasks.md "UNDO AUDIT"): the REAL app — real funnels, real model, real AU — attacked through the glass, with a read-out of the page's undo state, the document and the render input
//  after every operation. Launched `--fresh --undo-probe` (Fourfold/Shared/FourfoldUndoProbe.swift adds one hidden element, "Undo probe", whose value looks like
//    snap=… doc=… agree=1 stage=1 box=1 undo=3 redo=0 resyncs=0 pend=0 lanes=8/3r0,16/5r0,8/0r0,8/0r0
//  and two 8 pt buttons that do what an AUv3 HOST does behind the page's back). The scenarios named `testUNDO_n_…` are the breaks the audit found (UNDO-1…8, Docs/pending-tasks.md), now FIXED and asserting the ideal behaviour; `testPOLICY_…` is a seeded fuzz against the undo contract.

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
    static let partNames = ["lines", "riff", "resetSpanBars", "keyRoot", "keyType", "chordSets", "activeChordSet", "noteSource", "sourcePlan", "riffs", "activeRiff", "lanesSeq", "riffsSeq", "fx", "holdLatchMode", "hocketRules"]
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
    // SOURCES STACK ferry (2026-10-26): the note-source radio became a SOURCES pop-up of CHORDS/KEY toggle cells.
    // Toggling a cell is ONE undoable step (opening/closing the pop-up is not), so the step accounting is unchanged.
    // Close by tapping outside the card (the bottom of the screen is the pop-up's full-screen tap-catcher).
    func noteSource(_ cell: String) {
        app.buttons["Sources"].tap(); Thread.sleep(forTimeInterval: 0.3)
        app.buttons[cell].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap(); Thread.sleep(forTimeInterval: 0.2)
    }
    func riffSwitch(_ n: Int) { app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Riff \(n)")).firstMatch.tap() }
    func loadPreset(_ name: String) {
        app.buttons["Presets"].tap()
        let row = app.buttons["\(name), factory preset"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "preset row \(name)")
        row.tap()
        Thread.sleep(forTimeInterval: 0.3)
    }
    /// An FX cell is "Note n, rank r, <row> <value>" — r is the riff's rank at that step, which edits change, so match on the note and the row only.
    func fxCell(note: Int, row: String) { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Note \(note), rank", ", \(row) ")).firstMatch.tap() }
    func openFX() { app.buttons["FX"].tap(); Thread.sleep(forTimeInterval: 0.4) }
    // SOURCES STACK ferry (2026-10-26): the chord grid opens from the SOURCES pop-up's CHORDS label (was: select
    // CHORDS as the note source, then tap the chosen segment).
    func openChordsPopup() {
        app.buttons["Sources"].tap(); Thread.sleep(forTimeInterval: 0.4)
        app.buttons["Chords, edit chord grid"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.6)
    }
    func chordColumn(_ col: Int, _ degree: String) { app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Column \(col), \(degree),")).firstMatch.tap() }
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

    func testUNDO2_EditsToDifferentControlsAreSeparateSteps() {
        let p0 = launch()
        stepsUp(); let p1 = settled()          // lane 1 STEPS
        dragHits(up: true); let p2 = settled() // lane 1 HITS
        dragOffset(); let p3 = settled()       // lane 1 OFFSET
        XCTAssertNotEqual(p0.snap, p1.snap); XCTAssertNotEqual(p1.snap, p2.snap); XCTAssertNotEqual(p2.snap, p3.snap, "three real edits: \(p0.lanes) → \(p1.lanes) → \(p2.lanes) → \(p3.lanes)")
        XCTAssertEqual(p3.undo, 3, "one step per control: \(p3.raw)")
        undo(); let u = settled()
        XCTAssertEqual(u.snap, p2.snap, "one ↶ undoes only the OFFSET edit")
        undo(); XCTAssertEqual(settled().snap, p1.snap)
        undo(); XCTAssertEqual(settled().snap, p0.snap)
    }

    // MARK: S2 — a no-op touch

    func testUNDO6_TouchingAControlWithoutChangingItLeavesRedoAlone() {
        launch()
        stepsUp(); _ = settled()
        undo(); let afterUndo = settled()
        XCTAssertEqual(afterUndo.redo, 1)
        riffSwitch(1); let p = settled()           // riff 1 is already the one being edited: tapping it again changes nothing
        XCTAssertEqual(p.snap, afterUndo.snap, "the tap really was a no-op")
        XCTAssertEqual(p.redo, 1, "…so redo is still there: \(p.raw)")
        XCTAssertEqual(p.undo, 0, "…and no empty step was pushed")
        redo(); XCTAssertEqual(settled().lanes, "9/3r0,16/5r0,8/0r0,8/0r0")
    }
    // (A slider drag that returns to its start is covered in UndoAuditTests: in the app that gesture also stores `hitsRequested`, which IS a change, so it cannot be staged through the glass.)

    // MARK: S3 — the document changes under the history

    func testUNDO3_AHostPresetChangeClearsTheHistory() {
        let p0 = launch()
        stepsUp(); let edited = settled()
        XCTAssertEqual(edited.undo, 1)
        hostLoadsPreset(); let after = settled()
        XCTAssertNotEqual(after.lanes, edited.lanes, "the host's preset really replaced the lanes: \(edited.lanes) → \(after.lanes)")
        XCTAssertTrue(after.consistent, "after the host's change the page, the document and the engine agree: \(after.raw)")
        XCTAssertEqual(after.undo, 0, "↶ must not be offered a step from the previous document: \(after.raw)")
        XCTAssertEqual(after.redo, 0)
        undo(); let u = settled()
        XCTAssertEqual(u.lanes, after.lanes, "↶ does nothing (launch's were \(p0.lanes))")
    }
    func testUNDO3_AHostStateRestoreClearsTheHistory() {
        launch()
        loadPreset("FIVE AGAINST EIGHT"); let loaded = settled()
        XCTAssertEqual(loaded.undo, 1)
        hostRestoresLaunchState(); let after = settled()
        XCTAssertNotEqual(after.lanes, loaded.lanes, "the restore changed the document: \(loaded.lanes) → \(after.lanes)")
        XCTAssertTrue(after.consistent, after.raw)
        XCTAssertEqual(after.undo, 0, after.raw)
        undo(); XCTAssertEqual(settled().lanes, after.lanes)
        stepsUp(); let edited = settled()
        XCTAssertEqual(edited.undo, 1, "…and the new document starts its own history")
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
    func testUNDO5_UndoingAPresetLoadPutsTheLanesPlayStopFlagsBackAndRedoRestoresThePresets() {
        let p0 = launch()
        XCTAssertEqual(p0.play, "1111")
        loadPreset("FIVE AGAINST EIGHT"); let loaded = settled()
        XCTAssertNotEqual(loaded.play, p0.play, "the preset turns some lanes off: launch \(p0.play) → \(loaded.play)")
        undo(); let u = settled()
        XCTAssertEqual(u.play, p0.play, "↶ of a preset load puts the lanes back as they were, play/stop included")
        redo(); let r = settled()
        XCTAssertEqual(r.play, loaded.play, "↷ brings the preset's flags back too")
        XCTAssertEqual(r.snap, loaded.snap)
        undo(); XCTAssertEqual(settled().play, p0.play, "and ↶ again")
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
            noteSource(i % 2 == 0 ? "CHORDS while MIDI plays" : "KEY with no MIDI")
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
        noteSource("CHORDS while MIDI plays"); noteSource("KEY while MIDI plays"); stepsUp(); riffSwitch(2); noteSource("CHORDS with no MIDI")
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

    func testUNDO1_EveryTapOnTheStepsButtonsIsItsOwnUndoStep() {
        let p0 = launch()
        stepsUp(); let p1 = settled()
        stepsUp(); let p2 = settled()
        stepsUp(); let p3 = settled()
        XCTAssertEqual([p1.lanes, p2.lanes, p3.lanes], ["9/3r0,16/5r0,8/0r0,8/0r0", "10/3r0,16/5r0,8/0r0,8/0r0", "11/3r0,16/5r0,8/0r0,8/0r0"], "three real edits")
        XCTAssertEqual(p3.undo, 3, "three taps, three steps: \(p3.raw)")
        undo(); XCTAssertEqual(settled().lanes, p2.lanes)
        undo(); XCTAssertEqual(settled().lanes, p1.lanes)
        undo(); XCTAssertEqual(settled().lanes, p0.lanes)
    }
    func testUNDO1_AStepsTapAfterAnUndoEndsTheRedoBranchSoRedoCannotDiscardIt() {
        launch()
        stepsUp(); _ = settled()                 // 9 steps — recorded
        undo(); let u = settled()                // 8 steps, redo has the 9
        XCTAssertEqual(u.redo, 1)
        stepsDown(); let edited = settled()      // the user now chooses 7
        XCTAssertEqual(edited.lanes, "7/3r0,16/5r0,8/0r0,8/0r0")
        XCTAssertEqual(edited.undo, 1, "the new edit is a step: \(edited.raw)")
        XCTAssertEqual(edited.redo, 0, "…and it ended the redo branch")
        redo(); let r = settled()
        XCTAssertEqual(r.lanes, edited.lanes, "↷ has nothing to do — the user's 7 stays")
        undo(); XCTAssertEqual(settled().lanes, "8/3r0,16/5r0,8/0r0,8/0r0")
    }

    // MARK: S5b — a queued random roll outlives an undo

    func testUNDO4_ARollQueuedBeforeAnUndoIsCancelledByIt() {
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
        XCTAssertEqual(queued.pend, 1, "the roll is queued: \(queued.raw)")
        undo(); let u = settled()
        XCTAssertEqual(u.pend, 0, "↶ cancels what was still queued for the document it left: \(u.raw)")
        XCTAssertEqual(u.lanes, p0.lanes)
        Thread.sleep(forTimeInterval: 8)          // past the next bar line
        let later = settled()
        XCTAssertEqual(later.lanes, u.lanes, "nothing lands on the restored lane")
        XCTAssertEqual(later.undo, 0, later.raw)
        app.buttons["Random mode"].tap()            // finish the random session
        let finished = settled()
        XCTAssertEqual(finished.undo, 0, "the cancelled roll leaves no step behind: \(finished.raw)")
        XCTAssertTrue(finished.consistent, finished.raw)
        undo(); XCTAssertEqual(settled().lanes, p0.lanes, "↶ has nothing left to undo — in particular it never brings back the 9 steps the user had undone")
        app.buttons["Stop"].tap()
    }
    func testUNDO4_ARandomSessionStillWorksAfterAnUndo() {
        launch()
        app.buttons["Play"].tap(); Thread.sleep(forTimeInterval: 0.5)
        stepsUp(); _ = settled()
        app.buttons["Random mode"].tap()
        undo(); _ = settled()
        let throwBtn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Throw a new'")).firstMatch
        XCTAssertTrue(throwBtn.waitForExistence(timeout: 5)); throwBtn.tap()
        Thread.sleep(forTimeInterval: 8)
        let rolled = settled()
        XCTAssertNotEqual(rolled.lanes, "8/3r0,16/5r0,8/0r0,8/0r0", "a new throw after the undo lands: \(rolled.raw)")
        app.buttons["Random mode"].tap()
        let finished = settled()
        XCTAssertEqual(finished.undo, 1, "…and finishing records it as ONE step: \(finished.raw)")
        undo(); XCTAssertEqual(settled().lanes, "8/3r0,16/5r0,8/0r0,8/0r0", "↶ returns to what the lane was before THIS roll")
        app.buttons["Stop"].tap()
    }

    // MARK: the areas the first audit never reached — FX, chords, lane lock, user presets, a preset loaded twice

    func testFX_EachCellTapIsItsOwnStepAndAnUndoThenAnEditEndsRedo() {
        let p0 = launch()
        openFX()
        fxCell(note: 1, row: "ratchet"); let a = settled()
        fxCell(note: 2, row: "gate"); let b = settled()
        XCTAssertNotEqual(a.snap, p0.snap); XCTAssertNotEqual(b.snap, a.snap, "two real FX edits")
        XCTAssertEqual(b.undo, 2, "each tap on an FX cell is a step: \(b.raw)")
        XCTAssertTrue(b.consistent, b.raw)
        undo(); XCTAssertEqual(settled().snap, a.snap)
        undo(); XCTAssertEqual(settled().snap, p0.snap)
        redo(); XCTAssertEqual(settled().snap, a.snap)
        fxCell(note: 3, row: "tie"); let c = settled()          // a fresh edit after a redo: ends the redo branch
        XCTAssertNotEqual(c.snap, a.snap); XCTAssertEqual(c.redo, 0, c.raw); XCTAssertEqual(c.undo, 2, c.raw)
        XCTAssertTrue(c.consistent, c.raw); XCTAssertEqual(c.resyncs, 0, c.raw)
    }

    func testChords_EditsAndProgressionSwitchesAreStepsAndUndoRestoresThem() {
        launch()
        openChordsPopup()                                                      // choosing CHORDS as the note source is itself a step
        let base = settled()
        chordColumn(3, "V"); let a = settled()
        chordColumn(4, "iv"); let b = settled()
        XCTAssertNotEqual(a.snap, base.snap); XCTAssertNotEqual(b.snap, a.snap, "two real chord edits")
        XCTAssertEqual(b.differingParts(from: base), ["chordSets"], "only the chord sets changed: \(b.raw)")
        XCTAssertEqual(b.undo, base.undo + 2, "each column edit made while the popup stays open is its own step (a pause > 0.5 s closes a run): \(b.raw)")
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Progression 2'")).firstMatch.tap(); let c = settled()
        XCTAssertEqual(c.undo, base.undo + 3, "switching progression is a step: \(c.raw)")
        XCTAssertNotEqual(c.snap, b.snap)
        undo()                                                                 // while the popup is open a tap on the header lands on its scrim and only closes it
        var back = settled(); if back.snap == c.snap { undo(); back = settled() }
        XCTAssertEqual(back.snap, b.snap, "↶ switches back to progression 1 with its edits intact")
        undo(); XCTAssertEqual(settled().snap, a.snap)
        undo(); XCTAssertEqual(settled().snap, base.snap)
        redo(); redo(); redo(); let r = settled()
        XCTAssertEqual(r.snap, c.snap); XCTAssertTrue(r.consistent, r.raw); XCTAssertEqual(r.resyncs, 0, r.raw)
    }

    func testLock_UndoNeverCreatesAnInconsistencyWithALockedLanePresent() {
        launch()
        app.switches["Lock mode"].tap()
        tapLabel("Lock lane 1")                                               // lane 1 is now locked at what it is
        app.switches["Lock mode"].tap()                                        // back to editing
        _ = settled()
        stepsUp()                                                              // lane 1's STEPS is a lock field of a locked lane: an edit the lock owns, no undo step
        let afterLockEdit = settled()
        print("UNDOAUDIT lock: after a lock-field edit on the locked lane: undo=\(afterLockEdit.undo) lanes=\(afterLockEdit.lanes)")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fewer steps'")).element(boundBy: 1).tap()    // lane 2 STEPS: a normal step
        let afterLane2 = settled()
        XCTAssertGreaterThanOrEqual(afterLane2.undo, 1, afterLane2.raw)
        for _ in 0..<6 { undo(); redo(); undo() }
        let end = settled()
        XCTAssertTrue(end.consistent, "page, document and engine agree after undo/redo with a locked lane: \(end.raw)")
        XCTAssertEqual(end.resyncs, afterLane2.resyncs, "the poll never had to correct the page: \(end.raw)")
        XCTAssertEqual(end.undo + end.redo, afterLane2.undo + afterLane2.redo, "no step appeared or vanished: \(afterLane2.raw) → \(end.raw)")
    }

    func testUserPresets_SaveLoadAndDeleteLeaveTheHistoryConsistent() {
        let name = "UndoProbe\(Int(Date().timeIntervalSince1970) % 100000)"
        let p0 = launch()
        stepsUp(); let edited = settled()
        XCTAssertEqual(edited.undo, 1)
        app.buttons["Presets"].tap()
        let field = app.textFields.firstMatch
        need(field, "the preset name field").tap(); field.typeText(name + "\n")
        app.buttons["Save preset"].tap()
        let row = need(app.buttons[name], "the saved preset")
        let afterSave = settled()
        XCTAssertEqual(afterSave.undo, 1, "saving a preset is not an edit of the document: \(afterSave.raw)")
        XCTAssertEqual(afterSave.snap, edited.snap)
        row.tap(); Thread.sleep(forTimeInterval: 0.3)
        let loaded = settled()
        XCTAssertEqual(loaded.snap, edited.snap, "the preset holds exactly what was saved")
        XCTAssertEqual(loaded.undo, 1, "loading what is already there is not a step: \(loaded.raw)")
        XCTAssertTrue(loaded.consistent, loaded.raw)
        loadPreset("FIVE AGAINST EIGHT"); let other = settled()
        XCTAssertEqual(other.undo, 2)
        app.buttons["Presets"].tap()
        need(app.buttons["Delete \(name)"], "its delete button").tap()
        need(app.buttons["Confirm delete \(name)"], "the confirmation").tap()
        gone(app.buttons[name], "the deleted preset")
        tapLabel("Close presets")
        let afterDelete = settled()
        XCTAssertEqual(afterDelete.snap, other.snap, "deleting a preset never touches the document: \(afterDelete.raw)")
        XCTAssertEqual(afterDelete.undo, 2)
        undo(); XCTAssertEqual(settled().snap, edited.snap)
        undo(); XCTAssertEqual(settled().snap, p0.snap)
    }

    func testUNDO6_LoadingThePresetThatIsAlreadyLoadedIsNotAStep() {
        launch()
        loadPreset("FIVE AGAINST EIGHT"); let first = settled()
        XCTAssertEqual(first.undo, 1)
        stepsUp(); undo(); let beforeSecond = settled()                         // an undo leaves a redo branch behind
        XCTAssertEqual(beforeSecond.redo, 1)
        XCTAssertEqual(beforeSecond.snap, first.snap)
        loadPreset("FIVE AGAINST EIGHT"); let second = settled()
        XCTAssertEqual(second.snap, first.snap)
        XCTAssertEqual(second.undo, 1, "the second load changed nothing, so it is no step: \(second.raw)")
        XCTAssertEqual(second.redo, 1, "…and the redo branch is still there: \(second.raw)")
    }

    // MARK: under the live engine

    func testUndoRedoStormWhilePlayingLeavesTheEngineConsistentAndSilent() {
        launch()
        app.buttons["Play"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        noteSource("CHORDS while MIDI plays"); noteSource("KEY with no MIDI"); riffSwitch(2); stepsUp(); noteSource("CHORDS with no MIDI"); noteSource("KEY while MIDI plays")
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
        case stepsUp, stepsDown, hits(Bool), offset, source(String), riff(Int), riffCell(Int, Int), keyScale, fxCell(Int, String), preset(String), undo, redo
        var description: String {
            switch self {
            case .stepsUp: return "steps+"; case .stepsDown: return "steps−"; case .hits(let u): return "hits\(u ? "↑" : "↓")"; case .offset: return "offset"
            case .source(let s): return "source:\(s)"; case .riff(let n): return "riff\(n)"; case .riffCell(let st, let r): return "cell(step \(st) rank \(r))"; case .keyScale: return "key-scale"; case .fxCell(let n, let r): return "fx(note \(n) \(r))"
            case .preset(let p): return "preset:\(p)"; case .undo: return "UNDO"; case .redo: return "REDO"
            }
        }
        var isEdit: Bool { switch self { case .undo, .redo: return false; default: return true } }
    }

    /// The oracle is the undo contract applied to probe hashes: every edit funnel records the state BEFORE the edit under its key; ↶/↷ move the cursor. Anything else — the apply, the mirror, the document, the engine — has to agree.
    private func runFuzz(seed: UInt64, length: Int) {
        var rng = SplitMix(seed)
        let first = launch()
        openFX()                                                                // the sequencer panel shows its FX tab for the whole run (the lane cards and the riff panel stay where they are)
        var oracle = Timeline(start: first.snap)
        var upCount = 0, keyIsMinor = true
        var log: [String] = []
        for i in 0..<length {
            let op: Op
            switch rng.int(0...17) {
            case 0, 1: op = upCount < 3 ? .stepsUp : .stepsDown
            case 2: op = .hits(rng.int(0...1) == 0)
            case 3: op = .offset
            case 4, 5: op = .source(["CHORDS while MIDI plays", "CHORDS with no MIDI", "KEY with no MIDI"][rng.int(0...2)])   // each toggle flips one SOURCES cell — always a change, always one step
            case 6: op = .riff(rng.int(2...4))
            case 7: op = .preset("FIVE AGAINST EIGHT")
            case 8, 9: op = .riffCell(rng.int(1...8), rng.int(1...8))
            case 10: op = .keyScale
            case 11, 12: op = .fxCell(rng.int(1...8), ["ratchet", "tie", "gate", "velocity", "note step"][rng.int(0...4)])
            case 13, 14, 15: op = .undo
            default: op = .redo
            }
            log.append(op.description)
            let beforeResyncs = read().resyncs
            switch op {
            case .stepsUp: stepsUp(); upCount += 1
            case .stepsDown: stepsDown(); upCount -= 1
            case .hits(let u): dragHits(up: u)
            case .offset: dragOffset()
            case .source(let s): noteSource(s)
            case .riff(let n): riffSwitch(n)
            case .riffCell(let st, let r): app.buttons["Step \(st), rank \(r)"].firstMatch.tap()
            case .fxCell(let n, let row): fxCell(note: n, row: row)
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
            case .preset:
                oracle.edit(after: p.snap, key: nil)   // always a step: a preset arrives un-pinned, so loading the one that is already there looks like a change until the poll pins it (residual of UNDO-6)
            default:
                // every edit funnel records exactly when it CHANGED something (a tap on what is already chosen, a drag that returned to its start: no step), and the fuzz leaves ≥ 0.8 s between operations,
                // so no two edits ever share a gesture key
                if p.snap != oracle.live { oracle.edit(after: p.snap, key: nil) }
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

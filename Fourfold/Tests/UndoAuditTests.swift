//  UndoAuditTests.swift — the UNDO / REDO adversarial audit, layer 1 (pure; no simulator). Docs/pending-tasks.md "UNDO AUDIT".
//  What is here: (1) a model-based fuzz of `UndoStack` against a reference written as a TIMELINE of states with a cursor (a different shape from the stack's past/future arrays, so a shared slip is unlikely);
//  (2) fuzz + properties for the lock merge, the random-finish step builder and the pad burst; (3) a source tripwire that fails when the undo snapshot, `euclideousSnapshot()` and `euclideousApply` stop agreeing;
//  (4) tests named `testBREAK_…` that pin a REAL break as it behaves today inside `XCTExpectFailure` — they stay green, and fail loudly the day the break is fixed (delete the wrapper then).

import XCTest

// MARK: - the reference: a timeline of states with a cursor

/// What an ideal user-level undo does, written without a past/future split: `moments[cursor]` is the live value; undo moves the cursor back, redo forward; an edit throws away everything after the cursor.
/// A keyed edit that continues the open run REPLACES the live moment instead of adding one (that is what "a continuous gesture is one step" means); a step too far back is dropped at `cap`.
private struct Timeline {
    var moments: [Int]
    var cursor = 0
    var openKey: String? = nil
    let cap: Int
    init(start: Int, cap: Int) { moments = [start]; self.cap = cap }
    var live: Int { moments[cursor] }
    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor < moments.count - 1 }
    var past: Int { cursor }
    var future: Int { moments.count - 1 - cursor }
    mutating func edit(to v: Int, key: String?) {
        moments.removeSubrange((cursor + 1)...)
        if let k = key, k == openKey, cursor > 0 { moments[cursor] = v; return }
        moments.append(v); cursor += 1; openKey = key
        if cursor > cap { moments.removeFirst(); cursor -= 1 }
    }
    // an undo/redo that cannot move (nothing to go back to) changes nothing — including the open run: an edit that follows still continues the drag
    mutating func undo() { if cursor > 0 { cursor -= 1; openKey = nil } }
    mutating func redo() { if cursor < moments.count - 1 { cursor += 1; openKey = nil } }
}

private struct SplitMix {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 { s &+= 0x9E37_79B9_7F4A_7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
    mutating func bool() -> Bool { next() & 1 == 1 }
    mutating func double(_ lo: Double, _ hi: Double) -> Double { lo + Double(next() % 100_000) / 100_000 * (hi - lo) }
}

final class UndoAuditTests: XCTestCase {

    // MARK: 1 — UndoStack against the timeline

    /// The live value is `live`; an edit records the value it is about to replace, then changes it — exactly the page's funnel order (`euclideousRecordUndo` then the write).
    private func fuzz(seed: UInt64, cap: Int, ops: Int, keys: [String?]) -> String? {
        var rng = SplitMix(seed)
        var stack = UndoStack<Int>(cap: cap)
        var ref = Timeline(start: 0, cap: cap)
        var live = 0, fresh = 1
        var log: [String] = []
        func fail(_ why: String) -> String { "seed \(seed) cap \(cap): \(why)\n  ops: " + log.joined(separator: " ") }
        for _ in 0..<ops {
            switch rng.int(0...9) {
            case 0...5:
                let key = keys[rng.int(0...(keys.count - 1))]
                log.append("edit(\(key ?? "nil"))")
                stack.record(live, coalesceKey: key); live = fresh; fresh += 1
                ref.edit(to: live, key: key)
            case 6, 7:
                log.append("undo")
                if let p = stack.undo(current: live) { live = p }
                ref.undo()
            default:
                log.append("redo")
                if let n = stack.redo(current: live) { live = n }
                ref.redo()
            }
            if live != ref.live { return fail("live \(live) ≠ ideal \(ref.live)") }
            if stack.canUndo != ref.canUndo { return fail("canUndo \(stack.canUndo) ≠ \(ref.canUndo)") }
            if stack.canRedo != ref.canRedo { return fail("canRedo \(stack.canRedo) ≠ \(ref.canRedo)") }
            if stack.past.count != ref.past { return fail("past \(stack.past.count) ≠ \(ref.past)") }
            if stack.future.count != ref.future { return fail("future \(stack.future.count) ≠ \(ref.future)") }
            if stack.past.count > cap { return fail("past exceeds the cap") }
        }
        // walk all the way back, then all the way forward: the values must retrace the timeline exactly
        var walkedBack = [live]
        while let p = stack.undo(current: live) { live = p; walkedBack.append(live) }
        if walkedBack != Array(ref.moments[0...ref.cursor].reversed()) { return fail("undo-to-the-start returned \(walkedBack), ideal \(Array(ref.moments[0...ref.cursor].reversed()))") }
        var walkedForward = [live]
        while let n = stack.redo(current: live) { live = n; walkedForward.append(live) }
        if walkedForward != ref.moments { return fail("redo-to-the-end returned \(walkedForward), ideal \(ref.moments)") }
        return nil
    }

    func testTheStackMatchesAnIdealTimelineUnderRandomOperations() {
        for cap in [1, 2, 3, 7, 50] {
            for seed in 0..<250 {
                if let why = fuzz(seed: UInt64(seed) &* 7919 &+ UInt64(cap), cap: cap, ops: 400, keys: [nil, "euclideous", "euclideousRiffs", nil, "a"]) { XCTFail(why); return }
            }
        }
    }
    func testTheStackMatchesTheTimelineWithOnlyOneKey() {
        for seed in 0..<200 { if let why = fuzz(seed: UInt64(seed) &+ 99_000, cap: 5, ops: 300, keys: ["only"]) { XCTFail(why); return } }
    }
    func testTheStackMatchesTheTimelineWithNoKeys() {
        for seed in 0..<200 { if let why = fuzz(seed: UInt64(seed) &+ 55_000, cap: 4, ops: 300, keys: [nil]) { XCTFail(why); return } }
    }
    func testTheDepthCapForgetsTheOldestStepAndOnlyThat() {
        var s = UndoStack<Int>(cap: 50)
        var live = 0
        for _ in 0..<80 { s.record(live); live += 1 }          // 80 discrete edits
        XCTAssertEqual(s.past.count, 50)
        var back = 0; var v = live
        while let p = s.undo(current: v) { v = p; back += 1 }
        XCTAssertEqual(back, 50); XCTAssertEqual(v, 30, "the oldest 30 steps are gone; the oldest reachable state is the one before step 31")
        var fwd = 0
        while let n = s.redo(current: v) { v = n; fwd += 1 }
        XCTAssertEqual(fwd, 50); XCTAssertEqual(v, 80)
    }
    func testACoalescedRunAtTheCapDoesNotEvictAnything() {
        var s = UndoStack<Int>(cap: 3)
        for i in 0..<3 { s.record(i) }                           // full
        for i in 3..<40 { s.record(i, coalesceKey: "drag") }      // the first keyed record pushes (evicting step 0); the rest join it
        XCTAssertEqual(s.past.count, 3)
        XCTAssertEqual(s.undo(current: 40), 3, "the whole drag is one step")
        XCTAssertEqual(s.undo(current: 3), 2); XCTAssertEqual(s.undo(current: 2), 1)
        XCTAssertNil(s.undo(current: 1))
    }
    func testUndoRedoAreNotAffectedByAHostileInterleavingOfFreshRecords() {
        // redo must not outlive a fresh record even when that record is coalesced into an earlier run
        var s = UndoStack<Int>()
        s.record(0, coalesceKey: "k"); s.record(1, coalesceKey: "k")           // one step 0→…
        XCTAssertEqual(s.undo(current: 2), 0)                                  // live 0, redo has 2
        XCTAssertTrue(s.canRedo)
        s.record(0, coalesceKey: "k")                                         // an edit right after the undo
        XCTAssertFalse(s.canRedo, "a fresh edit ends the redo branch even if its key matches the run that was just undone")
        XCTAssertEqual(s.past.count, 1, "…and the undone run does not silently re-open: it is a NEW step")
    }

    // MARK: 2 — the pad burst

    /// The rule written out independently: a touch continues the previous burst iff the previous burst had a write, and this touch starts within 0.35 s of the previous touch ENDING.
    func testThePadBurstTakesExactlyTheStepsTheRuleSays() {
        for seed in 0..<300 {
            var rng = SplitMix(UInt64(seed) &+ 500)
            var burst = EuclideousPadUndoBurst()
            var t = 0.0
            var prevEnd: Double? = nil, burstHasWrite = false
            for touch in 0..<40 {
                t += rng.double(0.02, 0.9)
                let continues = prevEnd.map { t - $0 <= EuclideousPadUndoBurst.continueWithin } ?? false
                if !(continues && burstHasWrite) { burstHasWrite = false }      // a new burst begins
                burst.touchDown(at: t)
                let writes = [0, 1, 1, 4][rng.int(0...3)]
                var gotSteps = 0
                for _ in 0..<writes { if burst.nextWriteNeedsNewStep() { gotSteps += 1 } }
                var wantSteps = 0
                if writes > 0 && !burstHasWrite { wantSteps = 1; burstHasWrite = true }
                XCTAssertEqual(gotSteps, wantSteps, "seed \(seed) touch \(touch) at t=\(t)")
                t += rng.double(0.02, 0.5)
                burst.touchEnd(at: t); prevEnd = t
            }
        }
    }

    // MARK: 3 — lock merge and the random-finish builder

    private func randomLine(_ rng: inout SplitMix) -> EuclidLine {
        var l = EuclidLine()
        l.steps = rng.int(2...16); l.pulses = rng.int(0...l.steps); l.rotate = rng.int(0...15)
        l.gate = rng.double(0.1, 0.95); l.velocityAbsolute = rng.int(20...127)
        l.riffDir = [.forward, .reverse, .pendulum, .pingpong][rng.int(0...3)]
        l.riffOn = rng.bool(); l.notesOn = rng.bool(); l.emitterMask = UInt8(rng.int(0...15))
        l.rate = [ArpRate.r1_8, .r1_16, .r1_4][rng.int(0...2)]
        l.litNotes = UInt8(rng.int(0...255))
        return l
    }
    func testTheLockMergeNeverMovesALockedLanesLockFieldsAndNeverTouchesTheRest() {
        for seed in 0..<400 {
            var rng = SplitMix(UInt64(seed) &+ 7000)
            let restored = (0..<4).map { _ in randomLine(&rng) }, current = (0..<4).map { _ in randomLine(&rng) }
            let locked = (0..<4).map { _ in rng.bool() }
            let out = euclideousLockMergeForUndo(restored: restored, current: current, locked: locked)
            XCTAssertEqual(out.count, 4)
            for i in 0..<4 {
                if locked[i] {
                    XCTAssertEqual(LaneLockFields(line: out[i]), LaneLockFields(line: current[i]), "seed \(seed) lane \(i): a locked lane keeps its lock fields")
                    var a = out[i], b = restored[i]
                    LaneLockFields(line: current[i]).applied(to: &b)          // restored with the current lock fields laid over it must BE the merge: nothing else moved
                    a.enabled = b.enabled
                    XCTAssertEqual(a, b, "seed \(seed) lane \(i): only the lock fields differ from what the step held")
                } else {
                    XCTAssertEqual(out[i], restored[i], "seed \(seed) lane \(i): an unlocked lane is restored exactly")
                }
            }
        }
    }
    func testWhichEditsRecordAUndoStepIsDecidedByLockFieldsOfLockedLanesOnly() {
        for seed in 0..<300 {
            var rng = SplitMix(UInt64(seed) &+ 9100)
            let base = (0..<4).map { _ in randomLine(&rng) }
            let locks = (0..<4).map { i -> EuclideousLaneLock in rng.bool() ? EuclideousLaneLock.locking(base[i], grid: .bars4) : EuclideousLaneLock() }
            let locked = locks.map { $0.isLocked }
            XCTAssertFalse(euclideousLockChangeIsLockOnly(old: base, new: base, locks: locks), "no change never counts as lock-only")
            var edit = base
            let lane = rng.int(0...3)
            let lockField = rng.bool()
            if lockField { edit[lane].pulses = (base[lane].pulses + 1) % (base[lane].steps + 1); edit[lane].riffDir = (base[lane].riffDir == .forward ? .reverse : .forward) }
            else { edit[lane].gate = (base[lane].gate ?? 0.5) > 0.5 ? 0.2 : 0.8 }
            let lockOnly = euclideousLockChangeIsLockOnly(old: base, new: edit, locks: locks)
            XCTAssertEqual(lockOnly, locked[lane] && lockField && edit != base, "seed \(seed) lane \(lane) lockField \(lockField) locked \(locked[lane])")
        }
    }
    private func snapshot(_ lines: [EuclidLine]) -> EuclideousUndoSnapshot {
        EuclideousUndoSnapshot(lines: lines, riff: EuclideousRiff(), resetSpanBars: 0, keyRoot: 0, keyType: .major,
                               chordSets: [MachineParams(), MachineParams(), MachineParams(), MachineParams()], activeChordSet: 0, noteSource: .midi, riffs: [], activeRiff: 0,
                               lanesSeq: EuclideousLanesSeq(), riffsSeq: EuclideousRiffsSeq())
    }
    func testTheRandomFinishBuilderMakesExactlyOneRealStepPerKeptTab() {
        for seed in 0..<300 {
            var rng = SplitMix(UInt64(seed) &+ 3300)
            let settled = (0..<4).map { _ in randomLine(&rng) }
            var tabsDone: Set<String> = []
            var entries: [EuclideousRandomUndoEntry] = []
            for _ in 0..<rng.int(1...5) {
                let lane = rng.int(0...3), tab = EuclideousRandomTab.allCases[rng.int(0...(EuclideousRandomTab.allCases.count - 1))]
                guard tabsDone.insert("\(lane)/\(tab.rawValue)").inserted else { continue }      // the page never offers the same (lane, tab) twice IF the KEEP order is deduplicated — see the BREAK test below
                var original = randomLine(&rng)
                // make the kept tab really differ: copy settled's tab fields into `original`, then perturb through the roll's own field set
                euclideousRandomApplyTabFields(from: settled[lane], tab: tab, into: &original)
                var other = original; other = randomLine(&rng)
                euclideousRandomApplyTabFields(from: other, tab: tab, into: &original)
                guard !euclideousRandomTabFieldsEqual(original, settled[lane], tab: tab) else { continue }      // the page keeps a tab only if its final state still differs from the baseline (EuclideousPage.swift:1313)
                entries.append(EuclideousRandomUndoEntry(lane: lane, tab: tab, original: original))
            }
            let seq = euclideousRandomUndoSequence(settled: snapshot(settled), entries: entries)
            XCTAssertEqual(seq.count, entries.count, "seed \(seed): one pushed step per kept tab")
            // every pushed step must differ from the live (settled) state — an undo that changes nothing is a bug
            for (i, s) in seq.enumerated() where entries.count > 0 {
                let tabsDiffer = entries.contains { e in !euclideousRandomTabFieldsEqual(s.lines[e.lane], settled[e.lane], tab: e.tab) }
                XCTAssertTrue(tabsDiffer, "seed \(seed) step \(i): this undo step changes nothing")
            }
        }
    }
    func testBREAK_KeepingTheSameTabTwiceMakesAnUndoStepThatDoesNothing() {
        // `euclideousRandomKeep` appends to `euclideousRandomKeepOrder` on EVERY KEEP press (EuclideousPage.swift:1171) and the finish builder only deduplicates the second loop (:1305-1309), so roll → KEEP → roll → KEEP
        // on one tab gives two entries with the same (lane, tab) and the same session baseline.
        var settled = (0..<4).map { _ in EuclidLine() }
        settled[0].steps = 16; settled[0].pulses = 5
        var baseline = EuclidLine(); baseline.steps = 8; baseline.pulses = 2
        let entries = [EuclideousRandomUndoEntry(lane: 0, tab: .rhythm, original: baseline), EuclideousRandomUndoEntry(lane: 0, tab: .rhythm, original: baseline)]
        let seq = euclideousRandomUndoSequence(settled: snapshot(settled), entries: entries)
        XCTAssertEqual(seq.count, 2)
        XCTExpectFailure("a duplicate KEEP entry pushes a step identical to the live state: the first ↶ looks dead", strict: true) {
            XCTAssertNotEqual(seq[1].lines[0].steps, settled[0].steps, "every pushed step should differ from the live state")
        }
    }

    // MARK: 4 — the snapshot, `euclideousSnapshot()` and `euclideousApply` must stay in step (a source tripwire)

    private func rootViewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Shared/FourfoldRootView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func body(of source: String, from start: String, to end: String) throws -> String {
        let a = try XCTUnwrap(source.range(of: start), "\(start) not found — the audit's source tripwire needs updating")
        let b = try XCTUnwrap(source.range(of: end, range: a.upperBound..<source.endIndex), "\(end) not found")
        return String(source[a.lowerBound..<b.lowerBound])
    }
    func testEverySnapshotFieldIsCapturedAndRestoredToBothTheModelAndTheDocument() throws {
        let src = try rootViewSource()
        let capture = try body(of: src, from: "func euclideousSnapshot()", to: "func euclideousRecordUndo")
        let apply = try body(of: src, from: "func euclideousApply(", to: "func euclideousUndoAction")
        let labels = Mirror(reflecting: snapshot([])).children.compactMap { $0.label }
        XCTAssertEqual(Set(labels), ["lines", "riff", "resetSpanBars", "keyRoot", "keyType", "chordSets", "activeChordSet", "noteSource", "riffs", "activeRiff", "lanesSeq", "riffsSeq", "fx", "holdLatchMode"],
                       "the undo snapshot changed shape: update `euclideousSnapshot()`, `euclideousApply` and this list together")
        for l in labels {
            XCTAssertTrue(capture.contains("\(l):"), "euclideousSnapshot() never captures `\(l)`")
            let uses = apply.components(separatedBy: "s.\(l)").count - 1
            XCTAssertGreaterThanOrEqual(uses, l == "lines" ? 1 : 2, "euclideousApply restores `\(l)` \(uses)× — it must write BOTH the page's mirror and the document")
        }
    }
    func testEveryDocumentFieldAnUndoableFunnelWritesIsRestoredByUndo() throws {
        let src = try rootViewSource()
        let funnels = try body(of: src, from: "onSetNoteSource:", to: "onSetMainOutMask:")          // every funnel between these two records an undo step (mainOut, solo, settings after it do not, by design — §7.3)
        let apply = try body(of: src, from: "func euclideousApply(", to: "func euclideousUndoAction")
        func fields(_ text: String) -> Set<String> {
            var out: Set<String> = []
            let ns = text as NSString
            let re = try! NSRegularExpression(pattern: "\\$0\\.(\\w+)", options: [])
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) { out.insert(ns.substring(with: m.range(at: 1))) }
            return out
        }
        var written = fields(funnels)
        if written.remove("setEuclideousChordSet") != nil { written.insert("euclideousChordSets") }          // the funnel writes one set through a method; apply writes the array
        let restored = fields(apply)
        XCTAssertEqual(written.subtracting(restored), [], "an undoable funnel writes document fields that ↶ does not put back")
        XCTAssertFalse(written.isEmpty, "the tripwire found no funnel writes — its anchors moved")
    }
    func testBREAK_HistoryHasNoWayToBeInvalidatedWhenTheDocumentIsReplacedUnderIt() throws {
        // S3: nothing ever resets `euclideousUndo` — a host `fullState` load, a host-menu preset change or a user-preset delete leaves ↶ pointing at snapshots of the PREVIOUS document.
        let src = try rootViewSource()
        let resets = src.components(separatedBy: "euclideousUndo = ").count - 1
        XCTExpectFailure("no code path clears the undo history when the document changes outside the page's own funnels (S3)", strict: true) {
            XCTAssertGreaterThan(resets, 1, "the history is only ever assigned by the property's own declaration/setter")
        }
    }

    // MARK: 5 — pinned breaks that are facts about the stack's policy

    func testBREAK_OneKeyMergesEditsToDifferentControlsIntoOneStep() {
        // The page's `onEdit` records EVERY lane edit under the one key "euclideous" (FourfoldRootView.swift:187): three different controls, minutes apart, are one step.
        var s = UndoStack<Int>(); var live = 0
        func edit() { s.record(live, coalesceKey: "euclideous"); live += 1 }
        edit()      // lane 1 HITS      0→1
        edit()      // lane 2 STEPS     1→2
        edit()      // lane 3 OFFSET    2→3
        let afterFirstUndo = s.undo(current: live)
        XCTExpectFailure("S1: one ↶ is expected to undo only the last control's edit (→ 2)", strict: true) {
            XCTAssertEqual(afterFirstUndo, 2)
        }
        XCTAssertEqual(afterFirstUndo, 0, "today it jumps all the way back to before the first edit")
    }
    func testBREAK_AnEditThatChangesNothingStillEndsTheRedoBranch() {
        // S2: `onEdit` records BEFORE it knows whether `mutate` changed anything; `record` clears the redo branch first thing.
        var s = UndoStack<Int>()
        s.record(0); s.record(1)                                       // live 2
        _ = s.undo(current: 2)                                         // live 1, redo has 2
        XCTAssertTrue(s.canRedo)
        s.record(1, coalesceKey: "euclideous")                        // the user touches a control and leaves it where it was
        XCTExpectFailure("S2: touching a control without changing it should not destroy redo", strict: true) {
            XCTAssertTrue(s.canRedo)
        }
    }
    func testBREAK_APadBurstSurvivesAnUndoSoTheNextEditIsNeverRecorded() {
        // S6: the pad opens its burst on the first value-changing write and the burst has no way to hear about an undo. ↶ inside the 0.35 s continue window, then a drag:
        var s = UndoStack<Int>(); var live = 0
        var burst = EuclideousPadUndoBurst()
        burst.touchDown(at: 0.0)
        if burst.nextWriteNeedsNewStep() { s.record(live, coalesceKey: nil) }; live = 1       // pad write #1: recorded
        burst.touchEnd(at: 0.1)
        if let p = s.undo(current: live) { live = p }                                          // the user taps ↶ (live 0, redo has 1)
        burst.touchDown(at: 0.25)                                                              // …and drags the pad again within 0.35 s of lifting
        var recorded = false
        if burst.nextWriteNeedsNewStep() { s.record(live, coalesceKey: nil); recorded = true }
        live = 2                                                                               // pad write #2
        XCTExpectFailure("S6: the edit after an undo must start a new step (and end the redo branch)", strict: true) {
            XCTAssertTrue(recorded)
            XCTAssertFalse(s.canRedo)
        }
        XCTAssertTrue(s.canRedo, "today redo still offers the pre-undo value over the new edit")
        XCTAssertEqual(s.redo(current: live), 1, "…and ↷ resurrects it, discarding the pad edit")
    }
}

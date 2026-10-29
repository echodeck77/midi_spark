//  UndoAuditTests.swift — the UNDO / REDO adversarial audit, layer 1 (pure; no simulator). Docs/pending-tasks.md "UNDO AUDIT".
//  What is here: (1) a model-based fuzz of `UndoStack` against a reference written as a TIMELINE of states with a cursor (a different shape from the stack's past/future arrays, so a shared slip is unlikely);
//  (2) fuzz + properties for the lock merge, the random-finish step builder and the pad burst; (3) a source tripwire that fails when the undo snapshot, `euclideousSnapshot()` and `euclideousApply` stop agreeing;
//  (4) the policy that FIXED the breaks the audit found (UNDO-1…8, Docs/pending-tasks.md): gesture-scoped keys, no-op edits recording nothing, burst checkpoints that survive an undo, a no-op run handing redo back.

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
        l.riffOn = rng.bool(); l.notesOn = rng.bool()
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
    func testKeepingTheSameTabTwiceStillMakesOneRealUndoStep() {
        // UNDO-7: `euclideousRandomKeep` appends to the KEEP order on EVERY press, so roll → KEEP → roll → KEEP on one tab hands the builder two entries with the same (lane, tab) and baseline.
        var settled = (0..<4).map { _ in EuclidLine() }
        settled[0].steps = 16; settled[0].pulses = 5
        var baseline = EuclidLine(); baseline.steps = 8; baseline.pulses = 2
        let entries = [EuclideousRandomUndoEntry(lane: 0, tab: .rhythm, original: baseline), EuclideousRandomUndoEntry(lane: 0, tab: .rhythm, original: baseline)]
        let seq = euclideousRandomUndoSequence(settled: snapshot(settled), entries: entries)
        XCTAssertEqual(seq.count, 1, "one step per kept tab")
        XCTAssertNotEqual(seq[0].lines[0].steps, settled[0].steps, "and it changes something")
        XCTAssertEqual(seq[0].lines[0].steps, 8)
    }
    func testEntriesThatChangeNothingOrNameNoLaneMakeNoStep() {
        var settled = (0..<4).map { _ in EuclidLine() }; settled[1].steps = 12
        let same = EuclideousRandomUndoEntry(lane: 1, tab: .rhythm, original: settled[1])
        let outOfRange = EuclideousRandomUndoEntry(lane: 7, tab: .rhythm, original: EuclidLine())
        XCTAssertEqual(euclideousRandomUndoSequence(settled: snapshot(settled), entries: [same, outOfRange]).count, 0)
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
        XCTAssertEqual(Set(labels), ["lines", "riff", "resetSpanBars", "keyRoot", "keyType", "chordSets", "activeChordSet", "noteSource", "sourcePlan", "riffs", "activeRiff", "lanesSeq", "riffsSeq", "fx", "holdLatchMode", "hocketRules", "emitterRatchets", "riffPoly", "polyRiff", "presetPlay"],
                       "the undo snapshot changed shape: update `euclideousSnapshot()`, `euclideousApply` and this list together")
        for l in labels {
            let uses = apply.components(separatedBy: "s.\(l)").count - 1
            if l == "presetPlay" {      // only a preset-load step carries it (`euclideousRecordPresetUndo`); apply puts it back onto the lines
                XCTAssertGreaterThanOrEqual(uses, 1, "euclideousApply never restores `presetPlay`")
                continue
            }
            XCTAssertTrue(capture.contains("\(l):"), "euclideousSnapshot() never captures `\(l)`")
            XCTAssertGreaterThanOrEqual(uses, l == "lines" ? 1 : 2, "euclideousApply restores `\(l)` \(uses)× — it must write BOTH the page's mirror and the document")
        }
    }
    func testEveryDocumentFieldAnUndoableFunnelWritesIsRestoredByUndo() throws {
        let src = try rootViewSource()
        let funnels = try body(of: src, from: "onSetNoteSource:", to: "onSoloDown:")          // every funnel between these two records an undo step (solo, settings after it do not, by design — §7.3)
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
    func testAReplacedDocumentClearsTheHistory() throws {
        // UNDO-3: every funnel writes the page AND the document, so the 4 Hz poll finding them different means the document was replaced behind the page's back (host preset menu, project load).
        let src = try rootViewSource()
        let poll = try body(of: src, from: "if euclideousResynced {", to: "let nd = au.kernelDiagnostics()")
        XCTAssertTrue(poll.contains("historyMoved(clearStack: true)"), "the resync must clear the undo history")
        let moved = try body(of: src, from: "func historyMoved(clearStack: Bool)", to: "func euclideousApply(")
        XCTAssertTrue(moved.contains("euclideousUndo = UndoStack<EuclideousUndoSnapshot>()"), "…and `historyMoved(clearStack: true)` must really empty the stack")
        XCTAssertTrue(moved.contains("setEuclideousPendingRolls") && moved.contains("setEuclideousHoldOverrides"), "…and cancel a queued roll / hold (UNDO-4)")
    }
    func testEveryUndoableFunnelRefusesAnEditThatChangesNothing() throws {
        // UNDO-6, as a tripwire over the source: each funnel that records must have an equality guard between "compute the new value" and "record" — a new funnel added without one fails here.
        let src = try rootViewSource()
        let funnels = try body(of: src, from: "onSetNoteSource:", to: "onSoloDown:")
        let parts = funnels.components(separatedBy: "\n").filter { $0.contains("euclideousRecordUndo(") || $0.contains("m.checkpoint.take(") }
        XCTAssertGreaterThan(parts.count, 8)
        let withoutGuard = funnels.components(separatedBy: ": { ").dropFirst().filter { $0.contains("euclideousRecordUndo(") && !($0.contains("guard ") && $0.range(of: "guard ")!.lowerBound < $0.range(of: "euclideousRecordUndo(")!.lowerBound) }
        XCTAssertEqual(withoutGuard.count, 0, "a recording funnel has no guard before its record: \(withoutGuard.first.map { String($0.prefix(160)) } ?? "")")
    }

    // MARK: 5 — the policy that replaced the breaks

    func testGestureKeysLastOnlyWhileEditsKeepArriving() {
        var g = EuclideousEditGestures()
        let k0 = g.key("euclideous.1", at: 0.0)
        XCTAssertEqual(g.key("euclideous.1", at: 0.2), k0, "a drag: events keep arriving")
        XCTAssertEqual(g.key("euclideous.1", at: 0.65), k0, "…up to the gap between two events")
        XCTAssertNotEqual(g.key("euclideous.1", at: 1.4), k0, "a pause longer than the gap closes the run")
        let k1 = g.key("euclideous.1", at: 1.5)
        XCTAssertNotEqual(g.key("euclideous.4", at: 1.6), k1, "a different set of lanes is a different run")
        g.historyMoved()
        XCTAssertNotEqual(g.key("euclideous.1", at: 1.7), k1, "an undo / redo / reset ends the run")
    }

    /// The lane funnel's decisions written as plain code over the real types — the same expressions `onEdit` uses (FourfoldRootView.swift).
    private struct FunnelSim {
        var stack = UndoStack<Int>()
        var gestures = EuclideousEditGestures()
        var live: [Int] = [0, 0, 0, 0]                     // one value per lane
        var snapshot: Int { live.reduce(0) { $0 * 31 + $1 } }
        mutating func edit(lane: Int, to v: Int, at t: Double) {
            var new = live; new[lane] = v
            guard new != live else { return }                                         // UNDO-6
            let bits = (0..<4).reduce(0) { new[$1] != live[$1] ? $0 | (1 << $1) : $0 }
            stack.record(snapshot, coalesceKey: gestures.key("euclideous.\(bits)", at: t))
            live = new
            stack.dropOpenRunIfUnchanged(current: snapshot)                           // a drag that came back
        }
        mutating func undo() { if let p = stack.undo(current: snapshot) { live = [p / 29791 % 31, p / 961 % 31, p / 31 % 31, p % 31]; gestures.historyMoved() } }
    }
    func testDifferentLanesAndPausedEditsAreSeparateStepsADragIsOne() {
        var f = FunnelSim()
        f.edit(lane: 0, to: 1, at: 0.0); f.edit(lane: 0, to: 2, at: 0.1); f.edit(lane: 0, to: 3, at: 0.2)      // one drag on lane 1
        f.edit(lane: 0, to: 9, at: 5.0)                                                                           // another control, seconds later
        f.edit(lane: 2, to: 4, at: 5.1)                                                                           // another lane at once
        XCTAssertEqual(f.stack.past.count, 3, "drag + a later edit + another lane: three steps, not one")
    }
    func testAnEditThatChangesNothingRecordsNothingAndLeavesRedo() {
        var f = FunnelSim()
        f.edit(lane: 0, to: 1, at: 0.0)
        f.undo()
        XCTAssertTrue(f.stack.canRedo)
        f.edit(lane: 0, to: 0, at: 3.0)                                            // the lane is already 0: the user touched it and left it
        XCTAssertTrue(f.stack.canRedo, "UNDO-6: a touch that changed nothing must not end the redo branch")
        XCTAssertEqual(f.stack.past.count, 0, "…and must not push an empty step")
    }
    func testADragThatReturnsToItsStartIsNotAStepAndGivesRedoBack() {
        var f = FunnelSim()
        f.edit(lane: 1, to: 5, at: 0.0)
        f.undo()                                                                    // redo holds the 5
        f.edit(lane: 1, to: 7, at: 3.0); f.edit(lane: 1, to: 8, at: 3.05)          // a drag starts…
        XCTAssertFalse(f.stack.canRedo, "a real change ends the redo branch")
        f.edit(lane: 1, to: 0, at: 3.1)                                             // …and comes back to where it began
        XCTAssertEqual(f.stack.past.count, 0, "the wandering drag is not a step")
        XCTAssertTrue(f.stack.canRedo, "and the redo branch it cleared is handed back")
        var five = FunnelSim(); five.edit(lane: 1, to: 5, at: 0.0)
        XCTAssertEqual(f.stack.redo(current: f.snapshot), five.snapshot, "…intact: ↷ still goes to the 5")
    }
    func testADropRunStillRestoresNothingAfterAnUndoMovedOn() {
        var s = UndoStack<Int>()
        s.record(0, coalesceKey: "a")                       // live 1
        _ = s.undo(current: 1)                              // live 0, redo has 1
        s.record(0, coalesceKey: "b")                       // new run, redo cleared and stashed
        _ = s.undo(current: 2)                              // an undo ends the run: the stash is gone
        XCTAssertFalse(s.dropOpenRunIfUnchanged(current: 0), "no open run any more")
    }

    func testABurstCheckpointIsTakenAtTheFirstWriteThatChangesSomethingAndAgainAfterAnUndo() {
        var c = EuclideousCheckpoint()
        c.newBurst()
        XCTAssertFalse(c.take(changed: false), "UNDO-1: a first write that changes nothing takes no checkpoint…")
        XCTAssertTrue(c.take(changed: true), "…the first one that does takes it")
        XCTAssertFalse(c.take(changed: true), "later writes of the burst join it")
        c.historyMoved()                                    // ↶ with a second finger / inside the pad's 0.35 s window
        XCTAssertTrue(c.take(changed: true), "UNDO-8: after an undo the next write is a new step (and ends the redo branch)")
        XCTAssertFalse(c.take(changed: true))
    }
    func testAFreshCheckpointStateTakesNothingUntilABurstBegins() {
        var c = EuclideousCheckpoint()
        XCTAssertFalse(c.take(changed: true), "a write that claims to continue a burst nobody started records nothing (the page's own newStep:false)")
        c.newBurst(); XCTAssertTrue(c.take(changed: true))
    }

    func testPlayFlagsRoundTripThroughASnapshotLikeAPresetLoadNeedsThem() {
        var lines = (0..<4).map { _ in EuclidLine() }
        lines[2].enabled = false; lines[3].enabled = false
        var withMask = lines; withMask[0].mask = EuclidLineMask(); withMask[0].mask?.enabled = true
        let flags = euclideousPlayFlags(of: withMask)
        var other = (0..<4).map { _ in EuclidLine() }; other[0].mask = EuclidLineMask()
        euclideousApplyPlayFlags(flags, to: &other)
        XCTAssertEqual(other.map { $0.enabled }, withMask.map { $0.enabled })
        XCTAssertEqual(other[0].mask?.enabled, true)
        XCTAssertNil(other[1].mask, "a lane without a mask gets none invented")
        XCTAssertEqual(euclideousPlayFlags(of: other), flags)
    }
}

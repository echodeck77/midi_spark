//  FourfoldAudioUnit.swift  — FOURFOLD's copy of the AU class (Step 4, 2026-10-23: copied from AUExtension/MidiSparkAudioUnit.swift and renamed; the 8x8 original is frozen). The standalone app builds it directly; the extension
//  returns it from its factory.
//  AUv3 MIDI processor (aumi). Spec v2.8.
//  Declares nine MIDI outputs (All + Emit Riff/Notes A–D, `FourfoldPorts`), the 35-parameter table with stable addresses (§8/§13.5),
//  fullState as the host-level Preset (§1/§9), and wires the render kernel.

import Foundation
import AudioToolbox
import AVFoundation
import CoreAudioKit

// THREAD-SAFE PARAMETER VALUE CACHE (Paul 2026-10-11 — fixing a confirmed SIGKILL crash; see the .ips report:
// the main thread was blocked inside `AUParameter.setValue` (`syncParameterTreeToDocument`, itself called
// synchronously from a preset-load tap — `loadFactoryPreset` → `applyFactoryDocument`) at the EXACT same
// moment a background `AUParameterTree.valueAccessQueue` thread was blocked inside this unit's OWN
// `implementorValueProvider`, waiting via `DispatchQueue.main.sync` for that same main thread to answer a
// host `getParameter` XPC call. AudioToolboxCore apparently serializes AUParameter get/set traffic through
// one internal mechanism, so a main-thread SET and an off-main GET can deadlock each other — main waits on
// AudioToolbox's queue, AudioToolbox's queue (or the thread holding it) waits on main. Neither can proceed;
// FrontBoard's 10-second scene-create watchdog then SIGKILLs the whole extension. This is exactly why
// factory/user presets looked like they "didn't load" — the crash discards the in-flight document replace
// before anything is visible, and the host silently relaunches the extension fresh afterward.
// FIX: `implementorValueProvider` now NEVER blocks waiting on main — it reads this small lock-protected cache
// instead. Every main-thread writer of a parameter-tree value (the host-automation observer AND
// `syncParameterTreeToDocument`, the only two places a tracked value can change) keeps it current, so an
// off-main read is never more than one main-thread write behind, with zero cross-thread blocking either way.
private final class ParamValueCache {
    private let lock = NSLock()
    private var values: [AUParameterAddress: AUValue] = [:]
    func set(_ address: AUParameterAddress, _ value: AUValue) { lock.lock(); values[address] = value; lock.unlock() }
    func get(_ address: AUParameterAddress) -> AUValue { lock.lock(); defer { lock.unlock() }; return values[address] ?? 0 }
}

public class FourfoldAudioUnit: AUAudioUnit {

    private let paramCache = ParamValueCache()
    private let kernel = Kernel()
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!
    private var _parameterTree: AUParameterTree!
    private var document: PluginState   // a fresh instance loads the EMPTY "INIT" (the ARC is a named preset); built ONCE in init (Paul 2026-09-11 startup perf — was makeInit'd twice)
    private let store: SnapshotStore
    private var rebuildPending = false
    private var snapshotGeneration: UInt64 = 1
    private var suppressRebuild = false

    /// Currently loaded test session id ("—" until one is loaded). Diagnostics only.

    /// Live kernel diagnostics for the debug UI (polled; torn reads are fine for display).
    func kernelDiagnostics() -> KernelDiag { kernel.diag }
    // FREE-RUN CLOCK (Paul 2026-08-25): let the plugin run its own beat when the host transport is stopped + a note is held.
    func setFreeRunEnabled(_ b: Bool) { kernel.setFreeRunEnabled(b) }
    #if DEBUG
    #endif



    /// Document-level edit path (busChannels, receivers, …) — same publish semantics as editScene.
    /// (The page's own undo lives in `FourfoldRootView` — `UndoStack<EuclideousUndoSnapshot>`. This path used to push every edit onto a second, 50-deep stack of whole `PluginState` copies that nothing ever undid from: ≈ 1.9 µs per edit and
    /// ≈ 330 KB of old documents kept alive in the extension, measured 2026-10-25. Removed as UNDO-9.)
    func editDocument(_ mutate: (inout PluginState) -> Void) {
        mutate(&document)
        scheduleRebuild()
    }


    // MARK: - CELL MACHINE (feat/EditPageSpike) — per-cell processor CHAIN edits (cell-scoped, undoable via editScene)


    private func passthroughTemplateSlot() -> ProcessorSlot { var s = ProcessorSlot(type: .empty); s.bypassed = true; return s }   // all-bypassed ≡ empty ≡ passthrough
    /// The pointed cell's twin positions (incl. itself) for the grid highlight.

    /// The live document — for the EDIT page's SELECTION undo (which snapshots (selection, document) per select/
    /// deselect and restores both). Separate from the transactional undo stack above (which it never touches).

    /// §5b COLUMN-SUBSET LAP: the held column keys as a bitmask (bit i = column i). Ephemeral, never
    /// persisted; the PERFORM UI sets it while column keys are held and clears it (0) on release /
    /// transport stop / EDIT switch. `laneMask == 0` = no lap (playback follows the true column).
    func setLaneMask(_ mask: UInt16) { kernel.setLaneMask(mask) }
    func reelTouch() { kernel.reelTouch() }                 // THE REEL-TO-REEL: toggle record→replay / resume (Paul 2026-08-18)
    func uiReelState() -> Int { kernel.reelStateValue() }   // 0 off · 1 armed · 2 replaying
    // THE PASS BROWSER (Paul 2026-08-19) reads the SESSION TAPE since REEL PHASE 1c (2026-10-25, Fourfold/Engine/ReelTapeAdapter.swift): every pass played whole since the first play, not the newest 64. All of these are MAIN THREAD.
    var sessionTape: SessionTape { kernel.tape }                // the session tape (main thread only)
    /// REEL PHASE 1d — THE STANDALONE APP keeps its session on disk: one file, restored here before the engine starts, so a relaunch carries on where the last run left off (the tape's clock continues after it). Returns how many
    /// records came back. A file past `tapeFileCapBytes` (about 11 hours of dense music) is set aside as `….previous` and a fresh one started: a stopgap until the reel has a "New session" button.
    @discardableResult
    func useDurableTape(at url: URL) -> Int {
        let tape = kernel.tape
        guard !tape.hasStore else { return 0 }
        var store = TapeStore(url: url, chunkEvents: tape.chunkEvents)
        if let s = store, s.lengthBytes() > FourfoldAudioUnit.tapeFileCapBytes {
            let previous = url.appendingPathExtension("previous")
            s.close()
            try? FileManager.default.removeItem(at: previous); try? FileManager.default.moveItem(at: url, to: previous)
            store = TapeStore(url: url, chunkEvents: tape.chunkEvents)
        }
        guard let store else { return 0 }
        let restored = tape.attach(store: store)
        if restored > 0 { kernel.tapeSetOrigin(tape.endTick()) }
        return restored
    }
    static let tapeFileCapBytes: UInt64 = 96 * 1024 * 1024
    /// Write every record not yet on disk (the app calls this as it leaves the foreground).
    func flushTape() { kernel.tape.flushNow() }
    /// THE EXTENSION (AUM) has no durable session yet — which instance's tape a relaunched host session should bring back needs an id carried in the host's saved state, and how hosts treat that is not something to guess at (REEL
    /// phase 1d, open item). It still needs the file: older chunks spill to a temporary one so the tape stays inside its 8 MiB, and the file goes when the unit does.
    private func attachSpillTapeIfNeeded() {
        let tape = kernel.tape
        guard !tape.hasStore else { return }
        let dir = FileManager.default.temporaryDirectory
        if !FourfoldAudioUnit.sweptSpills { FourfoldAudioUnit.sweptSpills = true; TapeStore.removeStale(in: dir, prefix: "fourfold-tape-") }
        if let s = TapeStore(url: dir.appendingPathComponent("fourfold-tape-\(UUID().uuidString).tape"), chunkEvents: tape.chunkEvents, deleteOnClose: true) { tape.attach(store: s) }
    }
    private static var sweptSpills = false
    func reelExportRangeFiles(fromPass lo: Int, toPass hi: Int, emitterMask: UInt8) -> [(name: String, data: Data)] { kernel.tape.reelExportFiles(from: lo, to: hi, emitterMask: emitterMask) }   // pass RANGE × emitter selection
    func reelRangeRoll(fromPass lo: Int, toPass hi: Int) -> (notes: [ReelDeck.Note], cycle: Double) { let r = kernel.tape.reelRangeRoll(from: lo, to: hi); return (r.notes, r.totalBeats) }   // the concatenated roll for a multi-pass selection
    func reelPassNumbers() -> [Int] { Array(0..<kernel.tape.filedPasses().count) }   // the passes played whole, oldest→newest (shown 1-based)
    func reelPassSignatures() -> [UInt64] { kernel.tape.reelSignatures() }   // per-pass content hash (aligned with passNumbers) → REMOVE DUPLICATES toggle
    func reelPassCounter() -> Int { kernel.tape.filedPasses().count }        // monotone count of passes played whole
    /// The pass the browser is "on": the pinned one, else the newest.
    private func reelFocusPass() -> Int { let n = kernel.tape.filedPasses().count; let sel = kernel.reelSelectedPassNo(); return sel >= 0 && sel < n ? sel : n - 1 }
    private var reelRollCache: (pass: Int, notes: [ReelDeck.Note])?
    func reelSelectedRoll() -> [ReelDeck.Note] {                        // the focus pass's notes (A–D lanes); a whole pass never changes, so it is computed once
        let p = reelFocusPass()
        guard p >= 0 else { return [] }
        if let c = reelRollCache, c.pass == p { return c.notes }
        let notes = kernel.tape.reelRangeRoll(from: p, to: p).notes
        reelRollCache = (p, notes)
        return notes
    }
    func reelSelectedPassNo() -> Int { kernel.reelSelectedPassNo() }     // the currently pinned/selected pass (−1 = auto latest)
    func reelSelectPass(_ p: Int) {                                      // tap a pass → pin it and replay it now (the render thread adopts the staged loop at its next window)
        let t = kernel.tape
        guard let cycle = t.reelPassCycleBeats(p) else { return }
        let events = t.reelPassEvents(p)
        for _ in 0..<8 { if kernel.reelStageLoop(events, cycle: cycle, pass: p) { break }; usleep(500) }   // the render thread holds the buffer for microseconds; give up after a few tries
    }
    /// UNDO AUDIT probe (main thread, read-only): is the snapshot the render thread holds the one the AU would build from what it was given right now? Compares the Euclideous lanes of the published box with a fresh build.
    func probeBoxAgreement() -> Bool {
        func lanesHash(_ box: SnapshotBox?) -> UInt64 {
            guard let d = box?.euclideousProbeDescription else { return 0 }
            return FourfoldUndoProbe.fnv(d)   // the lanes AND the HOCKET rules of the box (see `euclideousProbeDescription`: the rules live in the cell's procs[0])
        }
        return lanesHash(store.acquire()) == lanesHash(SnapshotBuilder.build(from: renderDoc(), generation: 0))
    }
    func tapeStats() -> (events: Int, dropped: Int, passes: Int, completePasses: Int, endTick: Int, residentBytes: Int, evictedChunks: Int, storeErrors: Int) {   // main thread: the session tape's size and shape (diagnostics, the harness)
        let t = kernel.tape; t.drain(); let ps = t.passes()
        return (t.eventCount, t.droppedEvents, ps.count, t.filed.count, t.endTick(), t.residentBytes, t.evictedCount, t.storeErrors)
    }
    func reelStopReplay() { kernel.reelStopReplay() }                    // stop replay → resume live
    func reelCycleBeats() -> Double { kernel.tape.reelPassCycleBeats(reelFocusPass()) ?? 4 }   // the focus pass's length (piano-roll x-axis)
    func reelSetBrowsing(_ on: Bool) { kernel.reelSetBrowsing(on) }      // pop-up open → freeze the history tape

    /// BUILD: when the STAGING voice is playing, the engine renders THIS scene (the staging grid) in place of the
    /// document's active scene — ephemeral, the document is NEVER touched (encode/persist read `document`). nil = off.
    private var stagingRenderScene: SceneState? = nil
    func setBuildStagingScene(_ scene: SceneState?) { stagingRenderScene = scene; scheduleRebuild() }
    // PHASE 2 render-time AUTO (Paul 2026-09-04): the LIVE per-machine AUTO lanes, folded into the rendered doc so
    // SnapshotBuilder can build the render-time descriptors (×N passes / SMOOTH). nil ⇒ use the document's own.
    private var stagingAuto: [String: PartAutoMachine]? = nil

    /// The document the snapshot renders from — the real `document`, plus the BUILD staging grid override. Never
    /// used by encode/persist (those read `document`).
    /// BUILD's EPHEMERAL machines (beyond the 16 document slots) — id → its machine. renderDoc appends them so cells /
    /// auditions referencing them resolve. Never persisted (encode/persist read `document`). (Paul 2026-08-15)
    private var buildEphemeralMachines: [(id: String, machine: [ProcessorSlot], transpose: Int)] = []
    func setBuildEphemeralMachines(_ cs: [(id: String, machine: [ProcessorSlot], transpose: Int)]) { buildEphemeralMachines = cs; scheduleRebuild() }

    private func renderDoc() -> PluginState {
        if stagingRenderScene == nil, buildEphemeralMachines.isEmpty, stagingAuto == nil { return document }
        var temp = document
        if let sa = stagingAuto { temp.partAuto = sa }   // PHASE 2: the LIVE AUTO lanes reach the box for render-time (×N / SMOOTH)
        for e in buildEphemeralMachines where !temp.machines.contains(where: { $0.machineID == e.id }) {   // append BUILD ephemeral machines
            var col = Machine(machineID: e.id, type: .arp)
            col.defined = true
            col.transpose = max(-24, min(24, e.transpose))              // REGISTER HOME (ensemble roll 2026-08-19): the row's octave offset
            // An EMPTY machine is a born-audible PASSTHROUGH, not "no chain": store the bypassed-EMPTY placeholder,
            // else the builder collapses [] → nil and falls to the legacy A-face (an ARP) — a seeded empty tab-1 machine
            // played as an arp despite showing an empty chain. (Paul 2026-08-17)
            col.templateChain = e.machine.isEmpty ? [passthroughTemplateSlot()] : e.machine
            temp.machines.append(col)
        }
        let si = temp.activeSceneResolved
        if temp.scenes.indices.contains(si) {
            if let sc = stagingRenderScene {                                   // STAGING grid overrides the played scene …
                var scene = sc                                                 // … but the staging scene is composed at defaults, so honour the LIVE
                scene.stepRate = temp.scenes[si].stepRate                      // rate + swing (the header clock) — else the audition ignores the rate control
                scene.swing = temp.scenes[si].swing
                scene.row8On = temp.scenes[si].row8On                          // ROW 8 (Paul 2026-08-24): preserve the lit action toggles (FREEZE/HALFTIME/REDIRECT/SWAP) — else the composed scene drops them + the engine never freezes/halftimes/redirects
                temp.scenes[si] = scene
            }
        }
        return temp
    }





    // pollEmitterMarks/pollWithheldMarks/pollEmitterSounding (UI mark-feed forwarders) RETIRED 2026-09-12 — no caller.
    // (The kernel drains they wrapped stay: drainEmitterSounding et al. are exercised directly by RouterTests.)

    /// Read-only snapshot of the per-bus stamp channels for the OUTPUTS panel (delta §7).
    func uiBusChannels() -> [Int] { document.busChannelsResolved }




    // EUCLIDEOUS (Paul 2026-10-05): the standalone 4-lane instrument page's persisted config.
    func uiEuclideousLines() -> [EuclidLine] { document.euclideousLinesResolved }
    func uiEuclideousRiff() -> EuclideousRiff { document.euclideousRiffResolved }   // EUCLIDEOUS's shared riff pattern (Paul 2026-10-06)
    // SEQUENCER PANEL (2026-10-14 ferry): four independently-stored riffs + per-lane reset's own LANES/RIFFS
    // step clocks. `uiEuclideousRiff()` above stays in place, decode-only — `riffsResolved` migrates it into
    // slot 0 the instant it's read, so nothing downstream of THIS forwarder ever needs the old field again.
    func uiEuclideousRiffs() -> [EuclideousRiff] { document.riffsResolved }
    func uiEuclideousActiveRiff() -> Int { document.activeRiffResolved }
    func uiRiffPoly() -> Bool { document.riffPolyResolved }                  // POLY RIFF (2026-10-29)
    func uiPolyRiff() -> EuclideousPolyRiff? { document.polyRiff }
    // `uiEuclideousLiveGrid()` (a forwarder for the looper's decode-only `euclideousLiveGridResolved`)
    // is DELETED here (2026-10-18 adversarial review found it orphaned — its one caller, `refreshFrom
    // Document`'s resync block, was removed by the same ferry that dropped the looper, and this one
    // slipped past that ferry's own "confirmed zero remaining callers" sweep). `PluginState.
    // euclideousLiveGrid`/`euclideousLiveGridResolved` themselves stay on the document — pure decode-
    // safety for an old saved session now (confirmed: nothing on the production side reads
    // `euclideousLiveGridResolved` any more — `SnapshotBuilder.swift`'s own `p.euclideousLiveGrid` is the
    // unrelated `MachineParams` field, not this one; only `EffectiveParamsTests.swift` still exercises
    // this resolver directly, to prove the migration itself still works).
    func uiEuclideousFX() -> EuclideousFX { document.euclideousFXResolved }   // FX TAB (2026-10-18)
    func uiHocketRules() -> [HocketRule] { document.hocketRulesResolved }   // HOCKET (2026-10-27): sanitised, ≤ 4 rules; [] = none stored
    func uiEmitterRatchets() -> EmitterRatchetSet { document.euclideousEmitterRatchetsResolved }   // EMITTER RATCHET (2026-10-28): the four output ratchets; nil in the document = all defaults
    func uiEuclideousLanesSeq() -> EuclideousLanesSeq {
        EuclideousLanesSeq(on: document.euclideousLanesSeqOnResolved, rate: document.euclideousLanesSeqRateResolved,
                            len: document.euclideousLanesSeqLenResolved, cells: document.euclideousLanesSeqCellsResolved)
    }
    func uiEuclideousRiffsSeq() -> EuclideousRiffsSeq {
        EuclideousRiffsSeq(on: document.euclideousRiffsSeqOnResolved, rate: document.euclideousRiffsSeqRateResolved,
                            len: document.euclideousRiffsSeqLenResolved, cells: document.euclideousRiffsSeqCellsResolved)
    }
    // EUCLIDEOUS PAGE REWORK (Paul 2026-10-07): the new global reset-span/key/source-mode/main-out config.
    func uiEuclideousResetSpanBars() -> Int { document.euclideousResetSpanBarsResolved }
    func uiEuclideousKeyRoot() -> Int { document.euclideousKeyRootResolved }
    func uiEuclideousKeyType() -> ScaleType { document.euclideousKeyTypeResolved }
    func uiEuclideousNoteSource() -> EuclideousLaneSource { document.euclideousNoteSourceResolved }
    func uiEuclideousSourcePlan() -> SourcePlan? { document.euclideousSourcePlan }   // SOURCES STACK: the raw optional (nil ⇒ UI shows the derived plan)
    func uiEuclideousHoldLatchMode() -> EuclideousHoldLatchMode? { document.euclideousHoldLatchMode }   // HOLD/LATCH (2026-10-20): nil = off, no Resolved coercion needed
    func uiEuclideousSoloMask() -> UInt8 { document.euclideousSoloMaskResolved }
    /// LANE SOLO: the effective mask (latched | held) straight to the render thread — no snapshot in the way. Main thread.
    func setEuclideousSoloLive(_ mask: UInt8) { kernel.setEuclideousSoloLive(mask) }   // LANE SOLO (2026-10-21): the LATCHED mask
    /// RANDOM MODE ferry: a per-lane pending THROW/TWEAK/BACK/hold override straight to the render thread — same hand-off as setEuclideousSoloLive above. Main thread.
    func setEuclideousPendingRolls(_ rolls: EuclideousPendingRollSlots) { kernel.setEuclideousPendingRolls(rolls) }
    /// §5.6: the hold's own higher-priority override — same hand-off, separate channel.
    func setEuclideousHoldOverrides(_ rolls: EuclideousPendingRollSlots) { kernel.setEuclideousHoldOverrides(rolls) }
    /// LANE LOCK ferry: the held lanes + per-lane revisions straight to the render thread — same hand-off as setEuclideousSoloLive above. Main thread.
    func setEuclideousLockLive(held: UInt8, revs: UInt32) { kernel.setEuclideousLockLive(held: held, revs: revs) }
    /// LANE LOCK: the Router's landed-snap counters (one byte per lane) and the beats they landed at — the page applies each landed snap to the document.
    func pollEuclideousLockSnapSeq() -> UInt32 { kernel.euclideousLockSnapSeq() }
    func pollEmitterIndexPacked() -> UInt32 { kernel.emitterIndexPacked() }   // EMITTER RATCHET §3.10: rides the existing 30 Hz fast poll (no array copy — nothing for the render thread to copy-on-write)
    func uiEuclideousLocks() -> [EuclideousLaneLock] { document.euclideousLocksResolved }
    // FOURFOLD SETTINGS (2026-10-15 ferry): MIDI IN tab's channel mask + CLOCK tab's host-stop behaviour.
    func uiEuclideousMidiInChannelMask() -> UInt16 { document.euclideousMidiInChannelMaskResolved }
    func uiEuclideousHostStopBehavior() -> EuclideousHostStopBehavior { document.euclideousHostStopBehaviorResolved }
    // CHORDS GRID ferry (2026-10-24): 4 independently-stored progressions + which one plays/is edited.
    func uiEuclideousChordSets() -> [MachineParams] { document.euclideousChordSetsResolved }
    func uiActiveChordSet() -> Int { document.activeChordSetResolved }
    /// Each of Euclideous's 4 lanes' own live riff-advance step index, polled on the SAME fast ~30fps cadence as
    /// `pollEuclideousLineReady` below (not the slow ~4Hz config-resync timer) — this is a per-hit, responsive
    /// indicator, not config.
    func pollEuclideousRiffPositions() -> [Int] { kernel.euclideousRiffPositions() }
    func pollEuclideousRiffWalkState() -> [Int64] { kernel.euclideousRiffWalkState() }
    /// Each lane's own mask position — hit-driven (advances only on a real sounding hit of the lane's
    /// Euclid pattern), never a self-clocked sweep; same fast ~30fps cadence as the riff positions above
    /// (Paul 2026-10-11: "Euclid mask was moving at the main rate... not progressing on hits" — the fix).
    func pollEuclideousMaskPositions() -> [Int] { kernel.euclideousMaskPositions() }
    /// The ascending notes currently feeding the riff's own pool — same fast cadence as the riff positions
    /// above, so the riff panel's resolved-note display can never lag its own cursor dots.
    func pollEuclideousRiffLivePool() -> [UInt8] { kernel.euclideousRiffLivePool() }
    func pollHocketLive() -> (counts: [Int64], running: Bool) { kernel.hocketLive() }   // HOCKET §8: rides the existing 30 Hz fast poll
    func pollNoteRoll() -> [NoteRollRecord] { kernel.drainNoteRoll() }                   // CARD BACKS §5: each part's piano-roll feed, on the same 30 Hz poll
    func pollEuclideousSourceStatus() -> Router.EuclideousSourceStatus { kernel.euclideousSourceStatus() }   // SOURCES STACK: rides the existing 30 Hz fastPoll
    /// Euclideous's own beacon readiness, polled independent of the BUILD-page editor's own editorOpen-gated
    /// poll — Euclideous's page can be open (and its beacon needs updating) whether or not BuildPage's own
    /// processor editor happens to be open at the same time. Its cell always sits at column 0 of its own
    /// reserved row, so the cell index IS the row index (col 0 × Snap.rows contributes nothing).
    /// NOTE VIEW (Paul 2026-10-10 ferry): each lane's queued hit/miss/rest-flash events since the last poll —
    /// same fast ~30fps cadence as the riff positions/beacon above (a per-tick feed, not config). A true
    /// drain (read-and-clear): each call only ever returns events posted SINCE the previous call.
    func pollEuclideousNoteViewEvents() -> [[Router.EuclideousNoteViewEventSnapshot]] { kernel.euclideousNoteViewEvents() }
    /// SEQUENCER PANEL (2026-10-14 ferry): same fast ~30fps cadence as the riff positions above — the
    /// step-clock "always runs" (§4), so the lit cell must track it live, not on the slower config-resync poll.
    func pollEuclideousLanesSeqStep() -> Int { kernel.euclideousLanesSeqStep() }
    func pollEuclideousRiffsSeqStep() -> Int { kernel.euclideousRiffsSeqStep() }








    func uiIgnoreAllNotesOff() -> Bool { document.ignoreAllNotesOffResolved }   // INPUT (Paul 2026-09-06): ignore a source's CC120/123 flood
    func setIgnoreAllNotesOff(_ on: Bool) { editDocument { $0.ignoreAllNotesOff = on } }
    func uiClashPolicy() -> ClashPolicy { document.euclideousClashPolicy ?? .allow }   // SOURCES STACK ferry (2026-10-26): the stored dev-only clash policy (the DEBUG settings control reflects it)
    func setClashPolicy(_ p: ClashPolicy) { editDocument { $0.euclideousClashPolicy = p } }   // rig setting — no undo
    func uiFxCounts() -> FxCountsMode { document.euclideousFxCounts ?? .hits }   // RATCH tab ferry (2026-10-28) §7: the stored dev-only FX COUNTS (the DEBUG settings control reflects it)
    func setFxCounts(_ m: FxCountsMode) { editDocument { $0.euclideousFxCounts = m } }   // rig setting — no undo
    // FOURFOLD SETTINGS, MAIN OUT tab (2026-10-15 ferry §4.6): same request/consume shape as masterPanic,
    // narrower scope (Euclideous's own row only — see Router.process's own consumption of the flag).
    func euclideousAllNotesOff() { kernel.euclideousAllNotesOffRequest() }





    /// Global STEP rate (AUParameter 0) and SWING (AUParameter 1) — the scene-level timing. Set via
    /// the tree so host automation stays in sync (§4). Read-back for the header display.
    func uiStepRateIndex() -> Int { StepRate.allCases.firstIndex(of: document.activeSceneState.stepRate) ?? 2 }
    func uiSwing() -> Int { document.activeSceneState.swing }
    func setSwing(_ v: Int) {
        _parameterTree.parameter(withAddress: ParamAddress.swing)?.value = AUValue(max(50, min(75, v)))
    }

    /// Document mutated → build a fresh snapshot and publish (main thread; coalesced).
    // COALESCED (Paul 2026-08-21, anti-crackle): a burst of edits (a drag, or several AU setters in one gesture) now
    // triggers ONE SnapshotBuilder.build per runloop instead of N synchronous builds — the heavy build is the biggest
    // main-thread spike, and repeated spikes can momentarily starve the audio thread on a loaded device. The snapshot
    // updates one runloop tick later (≈ a few audio blocks — imperceptible; only the render thread reads it). Was:
    // a synchronous build on every main-thread edit.
    private func scheduleRebuild() {
        if suppressRebuild || rebuildPending { return }
        rebuildPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuildPending = false
            if self.suppressRebuild { return }
            self.snapshotGeneration &+= 1
            let doc = self.renderDoc()
            self.store.publish(SnapshotBuilder.build(from: doc, generation: self.snapshotGeneration, hues: self.snapHues(doc)))
        }
    }
    // The display hue (packed RGB) per machineID — so the render can tag emitted notes with their cell's machine (the
    // reel piano roll paints each note its machine). Same resolution the UI uses: an ephemeral override, else the
    // canonical palette hex, else a neutral grey. (Paul 2026-08-19)
    private func snapHues(_ doc: PluginState) -> [String: UInt32] {
        var m: [String: UInt32] = [:]
        for c in doc.machines {
            m[c.machineID] = machineHueOverride[c.machineID] ?? machineIDs.firstIndex(of: c.machineID).map { machineHexes[$0] } ?? 0x808080
        }
        return m
    }

    // MARK: - Nine MIDI outputs — the load-bearing line (§7b/§8). AUM shows these as nine sources.
    // THE NINE PORTS (Paul 2026-10-26): All (cable 0) carries every stream, told apart by channel; then one port per lane per LAYER —
    // Riff A, Notes A, Riff B, Notes B … Notes D (cables 1–8). A note's port is fixed by its lane and layer; there is nothing to route.
    // Static; serves single-cable and multi-out hosts simultaneously. Labels as Paul named them (AUM prepends the plugin name).
    public override var midiOutputNames: [String] { FourfoldPorts.names }

    /// IDENTITY — keep in step with `Fourfold/AU/Info.plist` (type / subtype / manufacturer) and `project.yml` (bundle ids). The standalone app never registers this description (it builds the AU directly); it only needs to be well-formed.
    /// `Frfd` / `OutM` (Outlier MIDI) is a one-way door once anyone has saved an AUM session (plan: "Decisions").
    static let componentDescription = AudioComponentDescription(componentType: kAudioUnitType_MIDIProcessor,
                                                                componentSubType: fourCC("Frfd"), componentManufacturer: fourCC("OutM"),
                                                                componentFlags: 0, componentFlagsMask: 0)
    private static func fourCC(_ s: String) -> FourCharCode { s.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) } }

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        let initDoc = PluginState.makeInit()   // ONE build (Paul 2026-09-11): reuse it for both the document and the initial snapshot (was two makeInit calls at instantiation)
        document = initDoc
        store = SnapshotStore(initial: SnapshotBuilder.build(from: initDoc, generation: 1))
        try super.init(componentDescription: componentDescription, options: options)

        // aumi units still require audio busses; a silent stereo pair is conventional.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let inBus = try AUAudioUnitBus(format: format)
        let outBus = try AUAudioUnitBus(format: format)
        _inputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inBus])
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outBus])

        _parameterTree = Self.buildParameterTree()
        wireParameterTree()
    }

    public override var inputBusses: AUAudioUnitBusArray { _inputBusses }
    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }
    public override var parameterTree: AUParameterTree? {
        get { _parameterTree }
        set { /* immutable in this unit */ }
    }

    // MARK: - Parameters — addresses are the STABLE IDs (§8: never renumber).
    //   0            stepRate (index into StepRate.allCases)
    //   1            swing (50…75)
    //   100 + i      transpose per machine i (−24…+24)
    //   200 + i      FREE (was morph per machine) — render-dead params removed 2026-09-16; addresses reusable
    //   300          FREE (was MORPH MASTER) — ditto
    //   400 + i      MACRO i (0…1)                     ← the macro block, 400…423 reserved (24); only the 8
    //                                                     SLIDERS (400…407) are host-automatable now (macro-panel
    //                                                     spec §5). A future transposeB must pick a base ≥ 500.
    enum ParamAddress {
        static let stepRate: AUParameterAddress = 0
        static let swing: AUParameterAddress = 1
        static func transpose(_ i: Int) -> AUParameterAddress { 100 + AUParameterAddress(i) }
        // 200+i morph / 300 morphMaster REMOVED 2026-09-16 (render-dead params). Addresses 200–215/300 are free to reuse.
        static func macro(_ i: Int) -> AUParameterAddress { 400 + AUParameterAddress(i) }
        static let macroSliderCount = 8   // the automatable bank (0–7); buttons/timelines aren't single-value AU params
    }

    private static func buildParameterTree() -> AUParameterTree {
        let stepped: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable]
        let smooth: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp]

        var params: [AUParameter] = []
        params.append(AUParameterTree.createParameter(
            withIdentifier: "stepRate", name: "Step Rate", address: ParamAddress.stepRate,
            min: 0, max: AUValue(StepRate.allCases.count - 1), unit: .indexed, unitName: nil,
            flags: stepped, valueStrings: StepRate.allCases.map(\.rawValue), dependentParameters: nil))
        params.append(AUParameterTree.createParameter(
            withIdentifier: "swing", name: "Swing", address: ParamAddress.swing,
            min: 50, max: 75, unit: .percent, unitName: nil,
            flags: smooth, valueStrings: nil, dependentParameters: nil))
        for (i, id) in machineIDs.enumerated() {
            params.append(AUParameterTree.createParameter(
                withIdentifier: "transpose_\(id)", name: "Transpose \(id.capitalized)",
                address: ParamAddress.transpose(i),
                min: -24, max: 24, unit: .indexed, unitName: "st",
                flags: stepped, valueStrings: nil, dependentParameters: nil))
        }
        // MORPH params (200+i) + MORPH MASTER (300) REMOVED 2026-09-16 — A/B morph was removed from the render, so
        // these were render-dead host params cluttering every DAW's automation list. Addresses 200–215 + 300 are now
        // FREE to reuse (nothing shipped to preserve). The document's morph/morphMaster fields remain as decode-only zombies.
        // MACRO SLIDERS (macro-panel spec §5): the 8 slider macros as host-automatable params — the reborn
        // automation story (AUM lanes · host MIDI-learn · the CC rail all ride these; no MIDI-learn code of ours).
        for i in 0..<ParamAddress.macroSliderCount {
            params.append(AUParameterTree.createParameter(
                withIdentifier: "macro_\(i + 1)", name: "Macro \(i + 1)",
                address: ParamAddress.macro(i),
                min: 0, max: 1, unit: .generic, unitName: nil,
                flags: smooth, valueStrings: nil, dependentParameters: nil))
        }
        return AUParameterTree.createTree(withChildren: params)
    }

    // THREAD SAFETY (Paul 2026-10-05, REVISED 2026-10-11 — see `ParamValueCache`'s own header comment above for
    // the confirmed deadlock this revision fixes): `implementorValueObserver`/`Provider` are AUParameterTree
    // callbacks — Apple documents these as callable from ANY thread, including a realtime one, for host
    // automation. Architecture invariant #1 (document mutation is MAIN-THREAD-ONLY) still holds: the observer
    // still marshals its `document` write onto main exactly as before (hops via `.async` when off-main, runs
    // inline when already on it). The PROVIDER no longer touches `document` or the main thread AT ALL — it
    // reads `paramCache` directly, which is safe from any thread and can never block, eliminating the deadlock
    // the old `DispatchQueue.main.sync` fallback was exposed to.
    private func wireParameterTree() {
        _parameterTree.implementorValueObserver = { [weak self] param, value in
            guard let self else { return }
            self.paramCache.set(param.address, value)   // update the cache first, from whatever thread the host called on — cheap, lock-protected, no document touch
            if Thread.isMainThread { self.applyParamValue(param, value) }
            else { DispatchQueue.main.async { self.applyParamValue(param, value) } }
        }
        _parameterTree.implementorValueProvider = { [weak self] param in
            self?.paramCache.get(param.address) ?? 0
        }
    }
    private func applyParamValue(_ param: AUParameter, _ value: AUValue) {
        dispatchPrecondition(condition: .onQueue(.main))
        defer { scheduleRebuild() }
        switch param.address {
        case ParamAddress.stepRate:
            guard !document.scenes.isEmpty else { break }   // K3: never subscript an empty scenes array (host automation before a scene exists)
            let all = StepRate.allCases
            document.scenes[document.activeSceneResolved].stepRate = all[min(all.count - 1, max(0, Int(value)))]
        case ParamAddress.swing:
            guard !document.scenes.isEmpty else { break }   // K3
            document.scenes[document.activeSceneResolved].swing = Int(value)
        case let a where a >= 100 && a < 100 + AUParameterAddress(machineIDs.count):
            let idx = Int(a - 100); if idx < document.machines.count { document.machines[idx].transpose = Int(value) }
        case let a where a >= 400 && a < 400 + AUParameterAddress(ParamAddress.macroSliderCount):
            // MACRO SLIDER (host automation / CC rail / in-app fader): OFFSET only — bases untouched.
            if document.macros == nil { document.macros = document.macrosResolved }
            document.macros?[Int(a - 400)].value = max(0, min(1, Double(value)))
        default: break
        }
    }

    /// Load a factory scene (Docs/factory-scenes.md) — same replace-and-resync path as a test session.


    // MARK: - PRESETS v1 (§3): whole-document named files (PresetStore), surfaced through BOTH our in-plugin
    // browser AND the standard AUv3 user-preset API (so AUM et al. list them in their own preset menu). One
    // store (PresetStore), two front doors. Distinct from `fullState` (that stays the host's session autosave).
    private var currentPresetName = ""
    private var _currentPreset: AUAudioUnitPreset? = nil
    func uiCurrentPreset() -> String { currentPresetName }
    func listPresets() -> [String] { PresetStore.list() }

    // §3 FACTORY presets (READ-ONLY): the 20 EUCLIDEOUS presets (Paul 2026-10-11 — see EuclideousPresets.swift's
    // own header comment). SUPERSEDES the prior DEFAULT/curriculum list (INIT/ARC/THE LADDER/TIDE/FORGE/CHIME/
    // SPARK/DELAYS + SceneFactory's 16 scenes) entirely, per Paul's explicit "remove any existing presets" —
    // confirmed via AskUserQuestion as the whole-plugin factory list, not just a Euclideous-scoped addition.
    // Code-defined builders, not files — so no save/overwrite/delete. Numbered non-negative for the host API.
    static let factoryPresetBuilders: [(name: String, make: () -> PluginState)] = EuclideousPresets.all
    func factoryPresetNames() -> [String] { Self.factoryPresetBuilders.map { $0.name } }
    /// Apply a factory preset's document — one undoable step + voice flush (from a builder, not a file). No KVO.
    private func applyFactoryDocument(named name: String) {
        guard let fp = Self.factoryPresetBuilders.first(where: { $0.name == name }) else { return }
        kernel.flushVoices()
        // FOURFOLD SETTINGS (2026-10-15 ferry §6.2): "loading a factory preset keeps the current LISTEN ON,
        // ALL-NOTES-OFF, CHANNELS and WHEN THE HOST STOPS: they describe the user's rig, not the music."
        // Captured from the OUTGOING document before the wholesale replace, reapplied after — inside the SAME
        // editDocument call, so this stays "one undoable step" exactly like the replace already was (§6.3:
        // no undo steps for these 4 either way). DISCLOSED SCOPE CALL: §6.2's literal text names only "a
        // factory preset" — `applyPresetDocument` below (user presets) gets the identical treatment too,
        // since the stated reason ("they describe the user's rig, not the music") applies equally to either
        // source, and nothing in the ferry suggests the asymmetry is deliberate.
        let keepMidiInMask = document.euclideousMidiInChannelMask
        let keepIgnoreAllNotesOff = document.ignoreAllNotesOff
        let keepBusChannels = document.busChannels
        let keepHostStop = document.euclideousHostStopBehavior
        let keepClashPolicy = document.euclideousClashPolicy   // SOURCES STACK ferry (2026-10-26): a rig setting, kept across a preset load (§1.6)
        let keepFxCounts = document.euclideousFxCounts   // RATCH tab ferry (2026-10-28): rig setting, kept across a preset load (§7.3)
        editDocument {
            $0 = fp.make(); $0.migrateLegacyRoutingIfNeeded()   // migrate is a no-op for v4 builders
            $0.euclideousMidiInChannelMask = keepMidiInMask
            $0.ignoreAllNotesOff = keepIgnoreAllNotesOff
            $0.busChannels = keepBusChannels
            $0.euclideousHostStopBehavior = keepHostStop
            $0.euclideousClashPolicy = keepClashPolicy
            $0.euclideousFxCounts = keepFxCounts
        }
        clearPendingBuild()   // K2: the new doc carries its own BUILD state — drop the outgoing session's stale pending
        currentPresetName = name
        suppressRebuild = true; syncParameterTreeToDocument(); suppressRebuild = false; scheduleRebuild()   // CR-7: mirror the loaded doc into the param tree (else host automation snaps a fresh note back to the OLD morph/transpose/macros)
    }
    /// The fresh-instance default document (`PluginState.makeInit()`); the harness's "(default)" golden entry loads it.
    func resetToFreshInit() {
        dispatchPrecondition(condition: .onQueue(.main))
        kernel.flushVoices()
        editDocument { $0 = PluginState.makeInit() }
        clearPendingBuild()
        currentPresetName = ""
        suppressRebuild = true; syncParameterTreeToDocument(); suppressRebuild = false; scheduleRebuild()
    }
    /// LOAD a factory preset (our browser). Applies it AND updates the host's current-preset selection.
    func loadFactoryPreset(named name: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        applyFactoryDocument(named: name)
        let p = AUAudioUnitPreset(); p.name = name
        p.number = Self.factoryPresetBuilders.firstIndex(where: { $0.name == name }) ?? 0   // factory ⇒ non-negative
        willChangeValue(forKey: "currentPreset"); _currentPreset = p; didChangeValue(forKey: "currentPreset")
    }

    /// The document the host would persist right now — == what `fullState` encodes. BOTH the host session (`fullState`)
    /// AND user presets (`savePreset` → `documentToSave`) go through `encodeDocument`, so a preset carries the BUILD
    /// workspace too (K1, 2026-08-30: was `{ document }`, the RAW doc, so a "Save as preset" dropped the unassigned
    /// part / deployed scenes / rooms PLAY GRID — the exact fields the session path was engineered to preserve).
    private var documentToSave: PluginState { encodeDocument }
    /// `document` with BUILD's session-side pending fields folded in — the single source of what gets persisted.
    /// Falls back to the DECODED document's own fields when a `pending*` is nil (a load→save with the BUILD editor
    /// never opened leaves pending nil; consume* nils document.* once BUILD is visited, so the fallback engages only
    /// in the correct pre-consume window).
    private var encodeDocument: PluginState {
        var d = document
        d.buildUnassigned = pendingBuildUnassigned ?? document.buildUnassigned
        d.buildScenes = pendingBuildScenes ?? document.buildScenes
        d.buildScenesActive = pendingBuildScenesActive ?? document.buildScenesActive
        d.buildPlayGrid = pendingBuildPlayGrid ?? document.buildPlayGrid
        d.partAuto = pendingPartAuto ?? document.partAuto
        return d
    }
    /// Apply a preset's document — ONE undoable step (§3), voices closed via the transition machinery. No host
    /// notification (the caller owns that): used by both our LOAD and the host's `currentPreset` setter.
    private func applyPresetDocument(named name: String) {
        guard let doc = PresetStore.load(name) else { return }
        kernel.flushVoices()                 // a session act — no arm ceremony
        // FOURFOLD SETTINGS (2026-10-15 ferry §6.2) — same 4-field preservation as applyFactoryDocument above
        // (its own comment explains the disclosed scope call extending this to user presets too).
        let keepMidiInMask = document.euclideousMidiInChannelMask
        let keepIgnoreAllNotesOff = document.ignoreAllNotesOff
        let keepBusChannels = document.busChannels
        let keepHostStop = document.euclideousHostStopBehavior
        let keepClashPolicy = document.euclideousClashPolicy   // SOURCES STACK ferry (2026-10-26): rig setting (§1.6)
        let keepFxCounts = document.euclideousFxCounts   // RATCH tab ferry (2026-10-28): rig setting (§7.3)
        editDocument {                       // one undoable step
            $0 = doc
            $0.euclideousMidiInChannelMask = keepMidiInMask
            $0.ignoreAllNotesOff = keepIgnoreAllNotesOff
            $0.busChannels = keepBusChannels
            $0.euclideousHostStopBehavior = keepHostStop
            $0.euclideousClashPolicy = keepClashPolicy
            $0.euclideousFxCounts = keepFxCounts
        }
        clearPendingBuild()                  // K2: drop the outgoing session's stale BUILD pending (the preset carries its own)
        currentPresetName = PresetStore.sanitize(name)
        suppressRebuild = true; syncParameterTreeToDocument(); suppressRebuild = false; scheduleRebuild()   // CR-7: mirror the loaded doc into the param tree
    }
    private func presetNumber(for name: String) -> Int {
        (PresetStore.list().firstIndex(of: name).map { -($0 + 1) }) ?? -1   // user presets use negative numbers
    }
    private func makeCurrent(named name: String) {                 // update the host-visible current preset + KVO
        let s = PresetStore.sanitize(name)
        let p = AUAudioUnitPreset(); p.name = s; p.number = presetNumber(for: s)
        willChangeValue(forKey: "currentPreset"); _currentPreset = p; didChangeValue(forKey: "currentPreset")
    }
    private func userPresetsChanged() { willChangeValue(forKey: "userPresets"); didChangeValue(forKey: "userPresets") }

    /// SAVE AS (our browser + the host's saveUserPreset both land here). Returns false on a write failure.
    @discardableResult func savePreset(named name: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        let ok = PresetStore.save(documentToSave, as: name)
        if ok { currentPresetName = PresetStore.sanitize(name); userPresetsChanged(); makeCurrent(named: name) }
        return ok
    }
    /// LOAD (our browser). Applies the document AND updates the host's current-preset selection.
    func loadPreset(named name: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        applyPresetDocument(named: name)
        makeCurrent(named: name)
    }
    func deletePreset(named name: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        PresetStore.delete(name)
        if currentPresetName == PresetStore.sanitize(name) {
            currentPresetName = ""
            willChangeValue(forKey: "currentPreset"); _currentPreset = nil; didChangeValue(forKey: "currentPreset")
        }
        userPresetsChanged()
    }

    // MARK: standard AUv3 user-preset API (§ host compliance) — the host's own preset menu drives these
    public override var supportsUserPresets: Bool { true }
    public override var userPresets: [AUAudioUnitPreset] {
        PresetStore.list().enumerated().map { i, name in
            let p = AUAudioUnitPreset(); p.name = name; p.number = -(i + 1); return p
        }
    }
    public override var factoryPresets: [AUAudioUnitPreset]? {                          // §3 read-only, non-negative numbers
        Self.factoryPresetBuilders.enumerated().map { i, fp in let p = AUAudioUnitPreset(); p.name = fp.name; p.number = i; return p }
    }
    public override var currentPreset: AUAudioUnitPreset? {
        get { _currentPreset }
        set {
            _currentPreset = newValue
            guard let p = newValue else { return }
            if p.number < 0 { applyPresetDocument(named: p.name) }      // a user preset → load its file
            else { applyFactoryDocument(named: p.name) }               // a factory preset → build it
        }
    }
    public override func saveUserPreset(_ userPreset: AUAudioUnitPreset) throws {
        guard savePreset(named: userPreset.name) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not write preset."])
        }
    }
    public override func deleteUserPreset(_ userPreset: AUAudioUnitPreset) throws {
        deletePreset(named: userPreset.name)
    }
    /// The state blob for a user preset — the SAME shape `fullState` returns, so the host round-trips it through
    /// the fullState setter. We hand back the raw stored bytes under our state key.
    public override func presetState(for userPreset: AUAudioUnitPreset) throws -> [String: Any] {
        guard let data = PresetStore.rawData(for: userPreset.name) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: "Preset not found."])
        }
        var state = super.fullState ?? [:]
        state[Self.stateKey] = data
        return state
    }

    /// Push document values out to the AUParameterTree so host-visible state matches reality.
    private func syncParameterTreeToDocument() {
        func push(_ address: AUParameterAddress, _ value: AUValue) {
            paramCache.set(address, value)   // keep the off-main-safe read cache current alongside the real push — see ParamValueCache's own header comment
            _parameterTree.parameter(withAddress: address)?.value = value
        }
        let scene = document.activeSceneState
        push(ParamAddress.stepRate, AUValue(StepRate.allCases.firstIndex(of: scene.stepRate) ?? 2))
        push(ParamAddress.swing, AUValue(scene.swing))
        for i in machineIDs.indices where i < document.machines.count {   // CR-13b: a decoded doc may carry <16 machines
            push(ParamAddress.transpose(i), AUValue(document.machines[i].transpose))
        }
        let macros = document.macrosResolved
        for i in 0..<ParamAddress.macroSliderCount {
            push(ParamAddress.macro(i), AUValue(macros[i].value))
        }
    }

    // MARK: - fullState = the host-level Preset (§1: the only thing called a preset)
    private static let stateKey = "com.outliermidi.fourfold.document"   // a NEW product: its sessions are its own (the 8x8 key stays in the frozen original)

    // Staging live-preview overlay (main thread): while a staged cell is transiently placed on the grid
    // for the in-context preview, this records where + the cell it displaced, so fullState encodes the
    // RESTORED cell — a host autosave mid-hover must never persist the transient preview into a preset.

    // BUILD pushes its single UNASSIGNED workshop part here (via setBuildUnassigned) so `fullState` saves it with the
    // document. Session-only side-field — the stored `document` is never mutated by it (the encode copy carries it).
    private var pendingBuildUnassigned: BuildUnassignedData? = nil
    // SCENES V2 (Paul 2026-08-24): the DEPLOYED play-grid arrangements travel with the save, like the unassigned part.
    private var pendingBuildScenes: [BuildSceneSnapshot]? = nil
    private var pendingBuildScenesActive: Int? = nil
    // THE ROOMS PLAY GRID (Paul 2026-08-30): the play columns + their multi-step passes travel with the save.
    private var pendingBuildPlayGrid: BuildPlayGridData? = nil
    /// Drop the OUTGOING session's stale BUILD pending fields on every load — the loaded doc carries its OWN (restored
    /// via consume*), so the next save doesn't re-encode the previous session's part/scenes/play grid over the new one
    /// (K2/CR-10, 2026-08-30: was applied only in `fullState.set`; the factory/preset/test load paths leaked pending).
    private func clearPendingBuild() { pendingBuildUnassigned = nil; pendingBuildScenes = nil; pendingBuildScenesActive = nil; pendingBuildPlayGrid = nil; pendingPartAuto = nil }
    // PART AUTOMATION (Paul 2026-09-02): the per-machine AUTO lanes travel with the save. Baked at BUILD time (composeScene),
    // so it's not render-relevant — a plain pending/consume transport like the play grid (no rebuild).
    private var pendingPartAuto: [String: PartAutoMachine]? = nil

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            if let data = try? JSONEncoder().encode(encodeDocument) { state[Self.stateKey] = data }   // BUILD's piece + scenes + play grid fold in via encodeDocument (shared with the preset path)
            return state
        }
        set {
            super.fullState = newValue
            if let data = newValue?[Self.stateKey] as? Data,
               var doc = try? JSONDecoder().decode(PluginState.self, from: data) {
                doc.migrateLegacyRoutingIfNeeded()   // old saved AUM sessions → v3 schema on load (mandatory)
                doc.normalizeLocksAtLoad()           // LANE LOCK 3.5: a session always opens at its locked states
                doc.normalizeRiffsAtLoad()           // POLY RIFF: the four riff boxes are gone — the riff that was active is the one riff
                document = doc
                clearPendingBuild()   // CR-10/K2: the loaded doc carries its OWN BUILD state (via consume*) — drop the outgoing session's stale pending so the next save doesn't re-encode it over the restored doc
                kernel.flushVoices()                 // audit B3: flush like every other load path — a mid-play host
                                                     // session restore must not strand the outgoing document's voices
                suppressRebuild = true; syncParameterTreeToDocument(); suppressRebuild = false   // CR-7: mirror the restored doc into the param tree
                scheduleRebuild()
            }
        }
    }

    // MARK: - Render plumbing
    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        kernel.sampleRate = _outputBusses[0].format.sampleRate
        kernel.store = store
        kernel.midiOut = midiOutputEventBlock
        kernel.musicalContext = musicalContextBlock
        kernel.transportState = transportStateBlock
        kernel.reset()
        attachSpillTapeIfNeeded()
        startTapeDrain()
    }

    /// REEL PHASE 1b: the session tape's main-thread half — take back the chunks the render thread filled and top the pool up. Twice a second is far inside the pool's headroom (8 chunks ≈ 65 k records ≈ 100 s of the densest music measured).
    private var tapeDrainTimer: DispatchSourceTimer?
    private func startTapeDrain() {
        guard tapeDrainTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.kernel.tape.drain() }
        t.resume()
        tapeDrainTimer = t
    }

    public override func deallocateRenderResources() {
        tapeDrainTimer?.cancel(); tapeDrainTimer = nil
        kernel.midiOut = nil
        kernel.musicalContext = nil
        kernel.transportState = nil
        super.deallocateRenderResources()
    }

    public override func reset() {
        kernel.reset()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let kernel = self.kernel
        return { _, timestamp, frameCount, _, outputData, realtimeEventListHead, _ in
            kernel.render(timestamp: timestamp, frameCount: frameCount, events: realtimeEventListHead)
            // Silent audio output (aumi convention).
            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            for buffer in abl {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return noErr
        }
    }
}

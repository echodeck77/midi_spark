//  MidiSparkAudioUnit.swift
//  AUv3 MIDI processor (aumi). Spec v2.8.
//  Declares five MIDI outputs (§7b: All + Emit A–D), the 35-parameter table with stable addresses (§8/§13.5),
//  fullState as the host-level Preset (§1/§9), and wires the render kernel.

import Foundation
import AudioToolbox
import AVFoundation
import CoreAudioKit

public class MidiSparkAudioUnit: AUAudioUnit {

    private let kernel = Kernel()
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!
    private var _parameterTree: AUParameterTree!
    private var document = PluginState.defaultArc()   // §3b first launch IS music (the 3-scene arc, not a blank grid)
    private let store: SnapshotStore
    private var rebuildPending = false
    private var snapshotGeneration: UInt64 = 1
    private var suppressRebuild = false

    /// Currently loaded test session id ("—" until one is loaded). Diagnostics only.
    private(set) var loadedTestSession = "—"

    /// Live kernel diagnostics for the debug UI (polled; torn reads are fine for display).
    func kernelDiagnostics() -> KernelDiag { kernel.diag }
    #if DEBUG
    func chaosInjectMIDI(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) { kernel.chaosEnqueue(status, d1, d2) }   // CHAOS SIMULATED source
    func chaosSetActive(_ on: Bool) { kernel.chaosActive = on }                                               // gate the render-side oracle dump
    func chaosRoutingDump() -> String { kernel.chaosRoutingDump() }                                           // the chain-state dump @ suspicious silence
    #endif
    func uiPass() -> Int { kernel.diag.pass }   // MULTI-SCENE S2c: the live pass, polled fast while a switch is armed

    /// Read-only view of the active scene for the grid UI (main thread; value copy).
    func uiScene() -> SceneState { document.activeSceneState }   // MULTI-SCENE: bounds-safe active scene

    /// The single grid-edit path: mutate the active scene, then publish a fresh snapshot. MAIN
    /// THREAD (SwiftUI actions already are). All UI edits — paint, clear, wiring — go through here,
    /// so the render side sees them exactly as it sees a preset load. UI-only state (selection,
    /// brush) never touches the document.
    func editScene(record: Bool = true, coalesceKey: String? = nil, _ mutate: (inout SceneState) -> Void) {
        // MODE ROW: inside a transactional EDIT session, individual edits publish for LIVE PREVIEW but defer
        // their undo — the whole session records ONE step at APPLY (see beginEditSession/applyEditSession).
        if record && sessionBaseline == nil { undoStack.record(document, coalesceKey: coalesceKey) }   // a6: snapshot BEFORE the mutation
        mutate(&document.scenes[document.activeSceneResolved])   // MULTI-SCENE: edit the ACTIVE scene, bounds-safe
        scheduleRebuild()
    }

    /// Document-level edit path (busChannels, receivers, …) — same publish semantics as editScene.
    func editDocument(record: Bool = true, coalesceKey: String? = nil, _ mutate: (inout PluginState) -> Void) {
        if record && sessionBaseline == nil { undoStack.record(document, coalesceKey: coalesceKey) }
        mutate(&document)
        scheduleRebuild()
    }

    // MARK: - MODE ROW — transactional EDIT session (APPLY / CANCEL)
    // The EDIT page stages edits + births + clears against a baseline captured when the selection set opens.
    // Live edits publish for preview (see editScene above); CANCEL restores the baseline exactly; APPLY records
    // the whole baseline→applied transition as ONE undoable step. MUTE toggles run OUTSIDE the session (immediate).

    /// The document as it stood when the current session opened. Non-nil ⇒ a live session is staging.
    private var sessionBaseline: PluginState? = nil

    /// True while a transactional session is open (the selection/marks are pending APPLY/CANCEL).
    var sessionActive: Bool { sessionBaseline != nil }
    /// True when the live document diverges from the session baseline (drives APPLY/CANCEL enabled state).
    var sessionDirty: Bool { if let b = sessionBaseline { return b != document }; return false }

    /// Open a session (idempotent — the FIRST selecting tap calls this; later taps are no-ops).
    func beginEditSession() { if sessionBaseline == nil { sessionBaseline = document } }
    /// Revert every staged change since the session opened and close it (nothing enters the undo stack).
    func cancelEditSession() {
        if let b = sessionBaseline { document = b; scheduleRebuild() }
        sessionBaseline = nil
    }
    /// Commit the session: record the whole baseline→applied transition as one undo step, then close.
    func applyEditSession() {
        if let b = sessionBaseline, b != document { undoStack.record(b) }
        sessionBaseline = nil
    }

    // MARK: - CELL MACHINE (feat/EditPageSpike) — per-cell processor CHAIN edits (cell-scoped, undoable via editScene)

    /// The chain as it stands, materialising a 1-slot head from the referenced Colour the first time a cell with
    /// no explicit chain is edited (so an untouched cell keeps rendering as its Colour's A face until then).
    private func materializedChain(_ cell: Cell) -> [ProcessorSlot] {
        if let p = cell.processors { return p }                                // per-cell override — incl. an explicit EMPTY chain (passthrough)
        let c = document.colours.first { $0.colourID == cell.colourID }
        if let t = c?.templateChain, !t.isEmpty { return t }                   // colour TEMPLATE (3-tier — matches the builder)
        return [ProcessorSlot(type: c?.type ?? .passgate, params: c?.paramsA ?? ColourParams())]   // legacy A face
    }
    /// The pointed cell's TWIN positions (config-equal cells, incl. itself), as encoded indices — for the grid's
    /// advertise-PULSE set (twins only advertise now; editing is the manual selection set below).
    private func twinTargets(col: Int, row: Int) -> [Int] {
        document.scenes[document.activeSceneResolved].editScopeTargets(col: col, row: row, scope: .twins)
    }
    // MODE ROW — edit a MANUAL SELECTION SET (INSTRUCTIONS-edit-page-mode-row): apply the SAME operation to EACH
    // selected cell's OWN config — so a mixed selection keeps its per-cell differences except where the edit touches.
    func editCells(_ targets: [(col: Int, row: Int)], _ mutate: @escaping (inout Cell) -> Void) {
        editScene { s in for t in targets { if var c = s.cellAt(t.col, t.row) { mutate(&c); s.setCell(t.col, t.row, c) } } }   // bounds-safe (stale/ragged positions)
    }
    func withChainCells(_ targets: [(col: Int, row: Int)], _ mutate: (inout [ProcessorSlot]) -> Void) {
        // Materialise + mutate each target's chain OUTSIDE editScene — materializedChain reads `document`, and
        // doing that inside editScene's `&document…` mutation would be an exclusive-access violation (crash).
        var writes: [(col: Int, row: Int, chain: [ProcessorSlot])] = []
        let scene = document.scenes[document.activeSceneResolved]
        for t in targets {
            guard let cell = scene.cells[t.col][t.row] else { continue }
            var chain = materializedChain(cell); mutate(&chain)
            writes.append((t.col, t.row, chain))
        }
        editScene { s in for w in writes { s.cells[w.col][w.row]?.processors = w.chain } }
    }
    func editSlotCells(_ targets: [(col: Int, row: Int)], slot: Int, _ mutate: (inout ProcessorSlot) -> Void) {
        withChainCells(targets) { if slot < $0.count { mutate(&$0[slot]) } }
    }
    func setSlotTypeCells(_ targets: [(col: Int, row: Int)], slot: Int, _ type: ProcessorType) { editSlotCells(targets, slot: slot) { $0.type = type } }
    func toggleSlotBypassCells(_ targets: [(col: Int, row: Int)], slot: Int) { editSlotCells(targets, slot: slot) { $0.bypassed.toggle() } }
    func addSlotCells(_ targets: [(col: Int, row: Int)], type: ProcessorType = .passgate) { withChainCells(targets) { if $0.count < 8 { $0.append(ProcessorSlot(type: type)) } } }
    func removeSlotCells(_ targets: [(col: Int, row: Int)], slot: Int) { withChainCells(targets) { if slot < $0.count, $0.count > 1 { $0.remove(at: slot) } } }
    /// The pointed cell's twin positions (incl. itself) for the grid highlight.
    func twinPositions(col: Int, row: Int) -> [(col: Int, row: Int)] {
        twinTargets(col: col, row: row).map { (col: $0 / 8, row: $0 % 8) }
    }

    // MARK: - CELL MACHINE stage-4 — the CELL LIBRARY (named saved cells, reusable across sessions)

    /// Save the cell at (col,row) to the library under `name` — "machine minus routing" (chain materialised +
    /// source-shaping; routing/perform state stripped). Returns false if the slot is empty or the write fails.
    @discardableResult
    func saveCellToLibrary(col: Int, row: Int, name: String) -> Bool {
        guard let cell = document.scenes[document.activeSceneResolved].cells[col][row] else { return false }
        return CellLibraryStore.save(cell.libraryStripped(materialisedChain: materializedChain(cell)), as: name)
    }
    func listLibraryCells() -> [String] { CellLibraryStore.list() }
    func loadLibraryCell(name: String) -> Cell? { CellLibraryStore.load(name) }
    func deleteLibraryCell(name: String) { CellLibraryStore.delete(name) }
    func factoryLibraryCells() -> [(name: String, cell: Cell)] { CellLibraryStore.factory() }
    func factoryLibraryCell(name: String) -> Cell? { CellLibraryStore.factory().first { $0.name == name }?.cell }

    // delta §5 / a6: bounded document-value undo/redo at the mutation choke point. Scope-lean — EDIT-mode
    // mutations record (the callers above default record:true); the PERFORM ALT flip opts out (record:false),
    // and continuous AUParameter sliders (transpose/morph) are excluded for v1 (they bypass these paths).
    private var undoStack = UndoStack<PluginState>()
    var uiCanUndo: Bool { undoStack.canUndo }
    var uiCanRedo: Bool { undoStack.canRedo }
    @discardableResult func uiUndo() -> Bool {
        guard let restored = undoStack.undo(current: document) else { return false }
        document = restored; scheduleRebuild(); return true
    }
    @discardableResult func uiRedo() -> Bool {
        guard let restored = undoStack.redo(current: document) else { return false }
        document = restored; scheduleRebuild(); return true
    }

    /// AUDITION (§6.4 / delta §5): hold a cell → sound its processor alone while stopped. Ephemeral
    /// UI gesture — writes the render-thread target only, never the document (no rebuild, not persisted).
    func setAudition(col: Int, row: Int) { kernel.setAudition(col * 8 + row) }
    func clearAudition() { kernel.setAudition(-1) }
    // PREVIEW / cell audition (Phase 2): the staged VIRTUAL cell renders solo while PREVIEW is held.
    func setPreview(colourIndex: Int, filter: Int, busMask: UInt8, inputRow: Int) {
        kernel.setPreview(colourIndex: colourIndex, filter: filter, busMask: busMask, inputRow: inputRow)
    }
    func clearPreview() { kernel.clearPreview() }

    /// §5b COLUMN-SUBSET LAP: the held column keys as a bitmask (bit i = column i). Ephemeral, never
    /// persisted; the PERFORM UI sets it while column keys are held and clears it (0) on release /
    /// transport stop / EDIT switch. `laneMask == 0` = no lap (playback follows the true column).
    func setLaneMask(_ mask: UInt8) { kernel.setLaneMask(mask) }

    /// §9 item 1 ON HOLD: the grid cell (col*8+row, −1 = none) currently press-held in PERFORM — its ON HOLD
    /// treatment overlays while held. Ephemeral, never persisted; the UI clears it (−1) on release / stop / EDIT.
    func setHoldCell(_ cell: Int) { kernel.setHoldCell(cell) }

    /// §9 item 1 ON TAP (unified ALT model): the ephemeral per-cell ALT flips (bit col*8+row). A PERFORM tap
    /// toggles a bit; cleared (0) on transport stop / mode switch. Ephemeral, never persisted (audition's class).
    func setTapAltMask(_ mask: UInt64) { kernel.setTapAltMask(mask) }
    /// §9 item 1 ON TAP actions (4b): the ephemeral per-cell MUTE mask + the global emitter SOLO set (bits A–D).
    func setTapMuteMask(_ mask: UInt64) { kernel.setTapMuteMask(mask) }
    func setSoloEmitterMask(_ mask: UInt8) { kernel.setSoloEmitterMask(mask) }
    func setSoloReceiverMask(_ mask: UInt8) { kernel.setSoloReceiverMask(mask) }   // receiver strip: input SOLO set
    func setInputOctave(_ recv: Int, _ oct: Int) { kernel.setInputOctave(recv, oct) }   // receiver strip: ±octave nudge
    func setInputVelOverride(_ recv: Int, _ value: Int?) { kernel.setInputVelOverride(recv, value) }   // receiver strip: slider
    func setLatchArm(_ mask: UInt8) { kernel.setLatchArm(mask) }   // receiver strip: per-receiver chord LATCH arm mask
    func setEmitterOctave(_ bus: Int, _ oct: Int) { kernel.setEmitterOctave(bus, oct) }   // emitter strip: output ±octave

    /// §6a PERFORM velocity override: force emitter `bus` (0…3 = A…D) to `value` (1–127) for every new
    /// note-on while its slider is touched; pass `nil` to spring back to natural velocity on release.
    /// Ephemeral, never persisted — the momentary "whisper/slam a bus" gesture, not the parked scale-fader.
    func setVelOverride(_ bus: Int, _ value: Int?) { kernel.setVelOverride(bus, value) }
    func setEmitterVelKill(_ bus: Int, _ kill: Bool) { kernel.setEmitterVelKill(bus, kill) }   // §4b fader-kill

    /// §6a metering: per-emitter peak velocity (0–127) + event count since the last poll (read-and-clear).
    func pollEmitterActivity() -> (peak: [UInt8], events: [UInt32]) { kernel.drainEmitterActivity() }

    /// delta §9 item 11: per-receiver INPUT peak velocity + event count since the last poll (read-and-clear).
    func pollReceiverActivity() -> (peak: [UInt8], events: [UInt32], channels: [UInt16]) { kernel.drainReceiverActivity() }
    func pollEmitterMarks() -> [[(vel: UInt8, col: Int8)]] { kernel.drainEmitterMarks() }   // item 4 velocity marks
    func pollCellStrikes() -> [UInt8] { kernel.drainCellStrikes() }   // SEAL comet: per-cell peak strike velocity (col*8+row)
    func pollCellSounding() -> UInt64 { kernel.pollCellSounding() }   // SEAL comet: per-cell sounding gate (note-on/off)
    func pollWithheldMarks() -> [[(vel: UInt8, col: Int8)]] { kernel.drainWithheldMarks() }   // §6a the withheld tell
    func pollReceiverMarks() -> [[UInt8]] { kernel.drainReceiverMarks() }
    func pollReceiverSounding() -> [[UInt8]] { kernel.pollReceiverSounding() }   // duration: currently-held input notes (latch-aware meter)
    func pollReceiverLiveHeld() -> UInt8 { kernel.pollReceiverLiveHeld() }       // the header dot: bit i = a LIVE accepted note is held (scalar, race-safe)
    func pollEmitterSounding() -> [[(vel: UInt8, col: Int8)]] { kernel.drainEmitterSounding() }   // §strips-done: currently-sounding per emitter (cargo-tinted)

    /// Read-only snapshot of the per-bus stamp channels for the OUTPUTS panel (delta §7).
    func uiBusChannels() -> [Int] { document.busChannels }

    /// delta §9 item 11: the four resolved receivers (nil-safe) for the editor's INPUT radio + the panel.
    func uiReceivers() -> [Receiver] { document.receiversResolved }
    func setReceiverChannel(_ i: Int, _ ch: Int) { editReceiver(i) { $0.channel = max(0, min(16, ch)) } }
    // setReceiverCable retired 2026-08-03 (COG SIMPLIFICATION — cables gone from the UI; the render hears all cables).
    func toggleReceiverMute(_ i: Int)             { editReceiver(i) { $0.muted.toggle() } }
    // INPUT ENABLE (the strip header): DISABLE stops the door listening (dark meter, latch sealed) — an armed
    // latch keeps feeding the grid; a mute (below) is what stops the feed. Persisted, like mute.
    func toggleReceiverEnabled(_ i: Int)          { editReceiver(i) { $0.inputEnabled = !($0.inputEnabledResolved) } }
    func setReceiverLatchAdd(_ i: Int, _ add: Bool) { editReceiver(i) { $0.latchAdd = add } }   // KEYS|CHORD (true = KEYS)
    // RANGE (§2): the door's note window. Clamps to 0…127 and keeps lo ≤ hi so the window is never inverted.
    func setReceiverRange(_ i: Int, lo: Int, hi: Int) {
        let l = max(0, min(127, lo)), h = max(0, min(127, hi))
        editReceiver(i) { $0.rangeLo = min(l, h); $0.rangeHi = max(l, h) }
    }
    // BYPASS (§1/§2): the door injects straight to emitters, skipping the grid. Toggle (strip) + destinations (cog).
    func toggleReceiverBypass(_ i: Int)              { editReceiver(i) { $0.bypass = !($0.bypassResolved) } }
    func setReceiverBypassDest(_ i: Int, _ mask: Int) { editReceiver(i) { $0.bypassDest = mask & 0b1111 } }
    // §MPE (cog page, 2026-07-xx — supersedes the 2026-07-25 "no UI, silent auto-detect" ruling): the mpeMerge
    // field is now surfaced as an explicit per-receiver toggle, PLUS a live auto-detect indicator (mpeLikely).
    func setReceiverMpeMerge(_ i: Int, _ on: Bool) { editReceiver(i) { $0.mpeMerge = on } }
    private func editReceiver(_ i: Int, _ f: (inout Receiver) -> Void) {
        guard (0..<4).contains(i) else { return }
        editDocument { d in
            if d.receivers == nil { d.receivers = d.receiversResolved }   // materialize before editing
            f(&d.receivers![i])
        }
    }

    /// delta §6a: the four emitter enable flags (nil/old docs ⇒ all-enabled), and the setter (persisted).
    func uiBusEnabled() -> [Bool] { document.busEnabledResolved }
    func setBusEnabled(_ i: Int, _ on: Bool) {
        guard i >= 0, i < 4 else { return }
        editDocument { d in
            var e = d.busEnabled ?? [true, true, true, true]
            while e.count < 4 { e.append(true) }
            e[i] = on
            d.busEnabled = e
        }
    }

    /// THE RACK (design-the-rack §3): the four per-emitter "board in the signal path" gates (nil/old docs ⇒ all
    /// ON), and the toggle (persisted, undoable). Lit ⇒ the emitter's armed treatments apply; off ⇒ raw wire (the
    /// builder pre-ANDs this into claim/duck/alt). Distinct from LIVE (which silences the output entirely).
    func uiRackMask() -> UInt8 { document.rackEnabledResolved }
    func setRack(_ bus: Int, _ on: Bool) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var m = d.rackEnabledResolved
            if on { m |= UInt8(1 << bus) } else { m &= ~UInt8(1 << bus) }
            d.rackEnabledMask = m
        }
    }

    /// delta §6a CLAIM v2: MULTI-claim (persisted). `setClaim` toggles emitter `bus` in/out of the claim set
    /// (buttons are no longer a radio — several light); `setClaimLeak` sets its 0…100 % bleed. The legacy
    /// single `claimEmitter` field is kept in sync (lowest claimed bus) so an OLDER build downgrades cleanly.
    func uiClaimMask() -> UInt8 { document.claimMaskResolved }
    func uiClaimLeak() -> [Int] { document.claimLeakResolved }
    func setClaim(_ bus: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            let m = d.claimMaskResolved ^ UInt8(1 << bus)
            d.claimMask = m
            d.claimEmitter = m == 0 ? nil : Int(m.trailingZeroBitCount)
        }
    }
    func setClaimLeak(_ bus: Int, _ pct: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var a = d.claimLeak ?? d.claimLeakResolved
            if a.count < 4 { a += Array(repeating: 0, count: 4 - a.count) }
            a[bus] = max(0, min(100, pct))
            d.claimLeak = a
        }
    }

    /// emitter role family: FLATTEN — activity ducking (persisted). `uiFlatten*` read; `setFlatten` toggles an
    /// emitter into/out of the ducking set; `setFlattenAmount` sets its 0…100 % scale.
    func uiFlattenMask() -> UInt8 { document.flattenMask ?? 0 }
    func uiFlattenAmount() -> [Int] { document.flattenAmountResolved }
    func setFlatten(_ bus: Int, _ on: Bool) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var m = d.flattenMask ?? 0
            if on { m |= UInt8(1 << bus) } else { m &= ~UInt8(1 << bus) }
            d.flattenMask = m
        }
    }
    func setFlattenAmount(_ bus: Int, _ amount: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var a = d.flattenAmount ?? d.flattenAmountResolved
            if a.count < 4 { a += Array(repeating: 0, count: 4 - a.count) }
            a[bus] = max(0, min(100, amount))
            d.flattenAmount = a
        }
    }

    /// THE RACK — CURVE (persisted): `setCurve` toggles emitter `bus`'s velocity re-map; `setCurveAmount` sets its
    /// −100…100 bend (0 = linear, + harder, − softer). Rack-gated in the builder.
    func uiCurveMask() -> UInt8 { document.curveMask ?? 0 }
    func uiCurveAmount() -> [Int] { document.curveAmountResolved }
    func setCurve(_ bus: Int, _ on: Bool) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var m = d.curveMask ?? 0
            if on { m |= UInt8(1 << bus) } else { m &= ~UInt8(1 << bus) }
            d.curveMask = m
        }
    }
    func setCurveAmount(_ bus: Int, _ amount: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var a = d.curveAmount ?? d.curveAmountResolved
            if a.count < 4 { a += Array(repeating: 0, count: 4 - a.count) }
            a[bus] = max(-100, min(100, amount))
            d.curveAmount = a
        }
    }

    /// THE RACK — FENCE (persisted): `setFence` toggles emitter `bus`'s range policy; `cycleFencePolicy` steps
    /// DROP→CLAMP→FOLD→DROP; `setFenceLo`/`setFenceHi` set the window bounds (0…127). Rack-gated in the builder.
    func uiFenceMask() -> UInt8 { document.fenceMask ?? 0 }
    func uiFencePolicy() -> [Int] { document.fencePolicyResolved }
    func uiFenceLo() -> [Int] { document.fenceLoResolved }
    func uiFenceHi() -> [Int] { document.fenceHiResolved }
    func setFence(_ bus: Int, _ on: Bool) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var m = d.fenceMask ?? 0
            if on { m |= UInt8(1 << bus) } else { m &= ~UInt8(1 << bus) }
            d.fenceMask = m
            // FENCE UX (user 2026-08-05): a full-range window is a no-op, so on ENABLE seed a SENSIBLE default —
            // policy CLAMP + window C2…C6 — so FENCE immediately, audibly acts (CLAMP pulls stray notes in rather
            // than silently dropping them). Only when the window is still the full default (untouched).
            if on {
                let loFull = d.fenceLoResolved[bus] == 0, hiFull = d.fenceHiResolved[bus] == 127
                if loFull && hiFull {
                    var pol = d.fencePolicy ?? d.fencePolicyResolved; while pol.count < 4 { pol.append(0) }; pol[bus] = 1   // CLAMP
                    var lo = d.fenceLo ?? d.fenceLoResolved; while lo.count < 4 { lo.append(0) }; lo[bus] = 36            // C2
                    var hi = d.fenceHi ?? d.fenceHiResolved; while hi.count < 4 { hi.append(127) }; hi[bus] = 84         // C6
                    d.fencePolicy = pol; d.fenceLo = lo; d.fenceHi = hi
                }
            }
        }
    }
    func cycleFencePolicy(_ bus: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var a = d.fencePolicy ?? d.fencePolicyResolved
            if a.count < 4 { a += Array(repeating: 0, count: 4 - a.count) }
            a[bus] = (max(0, min(2, a[bus])) + 1) % 3
            d.fencePolicy = a
        }
    }
    func setFenceLo(_ bus: Int, _ note: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var a = d.fenceLo ?? d.fenceLoResolved
            if a.count < 4 { a += Array(repeating: 0, count: 4 - a.count) }
            a[bus] = max(0, min(127, note))
            d.fenceLo = a
        }
    }
    func setFenceHi(_ bus: Int, _ note: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var a = d.fenceHi ?? d.fenceHiResolved
            if a.count < 4 { a += Array(repeating: 127, count: 4 - a.count) }
            a[bus] = max(0, min(127, note))
            d.fenceHi = a
        }
    }

    /// THE RACK — MONO (persisted): `setMono` toggles emitter monophony; `cycleMonoPriority` steps LAST→LOW→HIGH.
    func uiMonoMask() -> UInt8 { document.monoMask ?? 0 }
    func uiMonoPriority() -> [Int] { document.monoPriorityResolved }
    func setMono(_ bus: Int, _ on: Bool) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var m = d.monoMask ?? 0
            if on { m |= UInt8(1 << bus) } else { m &= ~UInt8(1 << bus) }
            d.monoMask = m
        }
    }
    func cycleMonoPriority(_ bus: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var a = d.monoPriority ?? d.monoPriorityResolved
            if a.count < 4 { a += Array(repeating: 0, count: 4 - a.count) }
            a[bus] = (max(0, min(2, a[bus])) + 1) % 3
            d.monoPriority = a
        }
    }

    /// THE RACK — POCKET (persisted): `setPocket` toggles the timing shift; `setPocketMs` sets −50…50 ms.
    func uiPocketMask() -> UInt8 { document.pocketMask ?? 0 }
    func uiPocketMs() -> [Int] { document.pocketMsResolved }
    func setPocket(_ bus: Int, _ on: Bool) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var m = d.pocketMask ?? 0
            if on { m |= UInt8(1 << bus) } else { m &= ~UInt8(1 << bus) }
            d.pocketMask = m
        }
    }
    func setPocketMs(_ bus: Int, _ ms: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var a = d.pocketMs ?? d.pocketMsResolved
            if a.count < 4 { a += Array(repeating: 0, count: 4 - a.count) }
            a[bus] = max(-50, min(50, ms))
            d.pocketMs = a
        }
    }

    /// THE RACK — CONVERSATION (persisted): `setConvLead` sets/clears the LEAD (radio; passing the current lead
    /// clears it); `cycleConvStance` steps a follower FREE→WITH→AGAINST.
    func uiConvLead() -> Int { document.convLeadResolved }
    func uiConvStance() -> [Int] { document.convStanceResolved }
    func setConvLead(_ bus: Int) {
        editDocument { d in
            let cur = d.convLeadResolved
            d.convLead = (cur == bus) ? -1 : ((0..<4).contains(bus) ? bus : -1)
        }
    }
    func cycleConvStance(_ bus: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var a = d.convStance ?? d.convStanceResolved
            if a.count < 4 { a += Array(repeating: 0, count: 4 - a.count) }
            a[bus] = (max(0, min(2, a[bus])) + 1) % 3
            d.convStance = a
        }
    }

    /// emitter role family: ALT — turn-taking group (persisted). `setAlt` toggles membership; `setAltCount`
    /// sets an emitter's notes-per-turn (1…8).
    func uiAltMask() -> UInt8 { document.altMask ?? 0 }
    func uiAltCount() -> [Int] { document.altCountResolved }
    func setAlt(_ bus: Int, _ on: Bool) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var m = d.altMask ?? 0
            if on { m |= UInt8(1 << bus) } else { m &= ~UInt8(1 << bus) }
            d.altMask = m
        }
    }
    func setAltCount(_ bus: Int, _ count: Int) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var c = d.altCount ?? d.altCountResolved
            if c.count < 4 { c += Array(repeating: 1, count: 4 - c.count) }
            c[bus] = max(1, min(8, count))
            d.altCount = c
        }
    }
    /// TURNS hand-off mode (persisted, global): false = PER-MOMENT, true = PER-NOTE (exclusive, drop simultaneous).
    func uiTurnsPerNote() -> Bool { document.turnsPerNoteResolved }
    func setTurnsPerNote(_ on: Bool) { editDocument { $0.turnsPerNote = on } }

    // MASTER PANEL. KEY = per-scene transpose (persisted); MUTE = global emission kill (persisted); the FADER
    // = the momentary master velocity override (ephemeral kernel feed); PANIC = the one-shot hard flush.
    private func activeSceneIndex() -> Int { max(0, min(document.activeScene, document.scenes.count - 1)) }
    func uiMasterKey() -> Int { document.scenes[activeSceneIndex()].masterKeyResolved }
    func nudgeMasterKey(_ delta: Int) {
        editDocument { d in
            let i = max(0, min(d.activeScene, d.scenes.count - 1))
            d.scenes[i].masterKey = max(-12, min(12, d.scenes[i].masterKeyResolved + delta))
        }
    }
    func uiMasterMute() -> Bool { document.masterMute ?? false }
    func setMasterMute(_ on: Bool) { editDocument { $0.masterMute = on } }
    // LADDER MODE (exclusive columns). The on/off arm is document-level; the per-column chosen rung is scene state.
    func uiLadderMode() -> Bool { document.ladderModeResolved }
    func setLadderMode(_ on: Bool) { editDocument { $0.ladderMode = on } }
    /// The resolved active rung for a column (topmost-occupied default) — the UI lights it + dims the other rungs.
    func ladderActiveRow(_ col: Int) -> Int? { document.activeSceneState.ladderActiveRow(col) }
    /// Commit a LADDER rung switch for a column. A PERFORMANCE action (record:false → not on the undo stack) that
    /// rebuilds the snapshot; the render adopts/re-speaks at the next column boundary (no new render-thread concept).
    func setActiveRow(_ col: Int, _ row: Int) {
        guard col >= 0, col < 8 else { return }
        editScene(record: false) { s in
            var ar = s.activeRow ?? [Int?](repeating: nil, count: 8)
            while ar.count < 8 { ar.append(nil) }
            ar[col] = row
            s.activeRow = ar
        }
    }
    func uiEffColumn() -> Int { kernel.diag.effColumn }   // LADDER: the live playhead column, polled to commit an armed rung at its next entry
    func setMasterVelOverride(_ value: Int?) { kernel.setMasterVelOverride(value) }
    func setMasterKill(_ on: Bool) { kernel.setMasterKill(on) }   // §4b master fader-kill (bottom = all silent)
    func masterPanic() { kernel.panic() }

    /// receiver strip: the THRU pip — the receiver (0–3) passthrough follows. Persisted RADIO, but unlike
    /// CLAIM there is ALWAYS exactly one lit (no clear): tapping a strip's pip moves THRU there directly.
    func uiThruReceiver() -> Int { document.thruReceiverResolved }
    func setThruReceiver(_ i: Int) {
        guard (0..<4).contains(i) else { return }
        editDocument { $0.thruReceiver = i }
    }

    /// Read-only Colours (type + params) so the grid can render each cell's type glyph + params text.
    func uiColours() -> [Colour] { document.colours }

    /// Edit a Colour's NON-AUParameter fields (type, pattern, rate, octaves, gate, phase, count,
    /// passes, strum, chance, harmonize) → rebuild. Transpose/morph are AUParameters — use the
    /// dedicated setters below so host automation stays in sync.
    func editColour(_ index: Int, _ mutate: (inout Colour) -> Void) {
        guard index >= 0, index < document.colours.count else { return }
        undoStack.record(document)                              // a6: discrete Colour edit
        mutate(&document.colours[index])
        scheduleRebuild()
    }

    /// Switch a Colour's processor type, isolating transpose/morph per type (spec revision). The type
    /// change is a document edit; the restored transpose/morph are pushed to the AUParameter tree (with
    /// the observer's rebuild suppressed, like the load paths) so host/UI reflect the new type's values.
    func setColourType(_ index: Int, _ newType: ProcessorType) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard index >= 0, index < document.colours.count, document.colours[index].type != newType else { return }
        undoStack.record(document)                              // a6: discrete type switch
        document.colours[index].switchType(to: newType)
        suppressRebuild = true
        _parameterTree.parameter(withAddress: ParamAddress.transpose(index))?.value = AUValue(document.colours[index].transpose)
        _parameterTree.parameter(withAddress: ParamAddress.morph(index))?.value = AUValue(document.colours[index].morph)
        suppressRebuild = false
        scheduleRebuild()
    }

    /// Transpose (AUParameter 100+i) — set via the tree so the observer writes the document and host
    /// automation reflects it.
    func setColourTranspose(_ index: Int, _ value: Int) {
        _parameterTree.parameter(withAddress: ParamAddress.transpose(index))?.value = AUValue(max(-24, min(24, value)))
    }

    /// Morph (AUParameter 200+i) — the per-Colour macro fader.
    func setColourMorph(_ index: Int, _ value: Double) {
        _parameterTree.parameter(withAddress: ParamAddress.morph(index))?.value = AUValue(max(0, min(1, value)))
    }

    /// Set a macro's value. SLIDERS (0…7) route via the AU param tree so host automation / the CC rail / the in-app
    /// panel stay in sync (the observer folds it into the document). BUTTONS/TIMELINES (8…23) aren't AU params —
    /// write the document directly (still an OFFSET; bases untouched). Coalesced so a drag/hold isn't undo spam.
    func setMacroValue(_ index: Int, _ value: Double) {
        guard (0..<24).contains(index) else { return }
        let v = max(0, min(1, value))
        if index < ParamAddress.macroSliderCount {
            _parameterTree.parameter(withAddress: ParamAddress.macro(index))?.value = AUValue(v)
        } else {
            editDocument(record: false, coalesceKey: "macro\(index)") { d in
                if d.macros == nil { d.macros = d.macrosResolved }
                d.macros?[index].value = v
            }
        }
    }
    /// The 24 macros for the UI (panel / A/B authoring). Read-back; the values mirror the automatable sliders.
    func uiMacros() -> [Macro] { document.macrosResolved }
    /// Macro NAME (document-level, not an AU param) — 12 chars max; "" = unset/invitation.
    func setMacroName(_ index: Int, _ name: String) {
        guard (0..<24).contains(index) else { return }
        editDocument { d in
            if d.macros == nil { d.macros = d.macrosResolved }
            d.macros?[index].name = String(name.prefix(12))
        }
    }
    /// Macro PADLOCK — false = SPRING (release returns home) · true = FIXED (latched). Document-level.
    func setMacroFixed(_ index: Int, _ fixed: Bool) {
        guard (0..<24).contains(index) else { return }
        editDocument { d in
            if d.macros == nil { d.macros = d.macrosResolved }
            d.macros?[index].fixed = fixed
        }
    }
    /// A/B AUTHORING: replace a cell's chain wholesale — used to RESTORE the A state after a live B demonstration
    /// (the demonstration is heard at full while authoring; committing binds the delta, then the base returns to A).
    func setCellChain(_ col: Int, _ row: Int, _ chain: [ProcessorSlot]) {
        withChainCells([(col: col, row: row)]) { $0 = chain }
    }
    /// A/B AUTHORING: bind (append) offset targets to a macro — the delta vector (B − A per touched param). Overlaps
    /// on the same param SUM at derivation (the offset law), so appending is correct even across sections/cells.
    func addMacroTargets(_ index: Int, _ targets: [MacroTarget]) {
        guard (0..<24).contains(index), !targets.isEmpty else { return }
        editDocument { d in
            if d.macros == nil { d.macros = d.macrosResolved }
            d.macros?[index].targets.append(contentsOf: targets)
        }
    }
    /// A/B AUTHORING: remove a macro's binding to a cell — every target it holds on (col,row) (the "remove chip").
    func removeMacroTargets(_ index: Int, col: Int, row: Int) {
        guard (0..<24).contains(index), document.macros != nil else { return }
        editDocument { d in d.macros?[index].targets.removeAll { $0.col == col && $0.row == row } }
    }

    /// Global STEP rate (AUParameter 0) and SWING (AUParameter 1) — the scene-level timing. Set via
    /// the tree so host automation stays in sync (§4). Read-back for the header display.
    func uiStepRateIndex() -> Int { StepRate.allCases.firstIndex(of: document.activeSceneState.stepRate) ?? 2 }
    func uiSwing() -> Int { document.activeSceneState.swing }
    func setStepRateIndex(_ i: Int) {
        _parameterTree.parameter(withAddress: ParamAddress.stepRate)?.value = AUValue(max(0, min(StepRate.allCases.count - 1, i)))
    }
    func setSwing(_ v: Int) {
        _parameterTree.parameter(withAddress: ParamAddress.swing)?.value = AUValue(max(50, min(75, v)))
    }

    /// Document mutated → build a fresh snapshot and publish (main thread; coalesced).
    private func scheduleRebuild() {
        if suppressRebuild { return }
        if Thread.isMainThread {
            snapshotGeneration &+= 1
            store.publish(SnapshotBuilder.build(from: document, generation: snapshotGeneration))
        } else if !rebuildPending {
            rebuildPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rebuildPending = false
                self.snapshotGeneration &+= 1
                self.store.publish(SnapshotBuilder.build(from: self.document, generation: self.snapshotGeneration))
            }
        }
    }

    // MARK: - Five MIDI outputs — the load-bearing line (§7b/§8). AUM shows these as five sources.
    // delta §7b: FIVE cables — All (0) carries every emitter channel-distinguished; A–D (1–4) each
    // carry their own stream. Static; serves single-cable and multi-out hosts simultaneously.
    // Labels kept short (AUM prepends "MidiSpark @Mn:n "); "All" sorts before the "Emit ·" group in
    // AUM's alphabetical list, instead of landing between A and C.
    public override var midiOutputNames: [String] {
        ["All", "Emit A", "Emit B", "Emit C", "Emit D"]   // cables 0–4
    }

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        store = SnapshotStore(initial: SnapshotBuilder.build(from: PluginState.defaultArc(), generation: 1))
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
    //   100 + i      transpose per colour i (−24…+24)
    //   200 + i      morph per colour i (0…1)          ← the macro (§3.2)
    //   300          MORPH MASTER (0…1)                ← #35, reserved & functional (§13.5)
    //   400 + i      MACRO i (0…1)                     ← the macro block, 400…423 reserved (24); only the 8
    //                                                     SLIDERS (400…407) are host-automatable now (macro-panel
    //                                                     spec §5). A future transposeB must pick a base ≥ 500.
    enum ParamAddress {
        static let stepRate: AUParameterAddress = 0
        static let swing: AUParameterAddress = 1
        static func transpose(_ i: Int) -> AUParameterAddress { 100 + AUParameterAddress(i) }
        static func morph(_ i: Int) -> AUParameterAddress { 200 + AUParameterAddress(i) }
        static let morphMaster: AUParameterAddress = 300
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
        for (i, id) in colourIDs.enumerated() {
            params.append(AUParameterTree.createParameter(
                withIdentifier: "transpose_\(id)", name: "Transpose \(id.capitalized)",
                address: ParamAddress.transpose(i),
                min: -24, max: 24, unit: .indexed, unitName: "st",
                flags: stepped, valueStrings: nil, dependentParameters: nil))
        }
        for (i, id) in colourIDs.enumerated() {
            params.append(AUParameterTree.createParameter(
                withIdentifier: "morph_\(id)", name: "Morph \(id.capitalized)",
                address: ParamAddress.morph(i),
                min: 0, max: 1, unit: .generic, unitName: nil,
                flags: smooth, valueStrings: nil, dependentParameters: nil))
        }
        params.append(AUParameterTree.createParameter(
            withIdentifier: "morphMaster", name: "Morph Master", address: ParamAddress.morphMaster,
            min: 0, max: 1, unit: .generic, unitName: nil,
            flags: smooth, valueStrings: nil, dependentParameters: nil))
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

    private func wireParameterTree() {
        // TODO(spec §7): route into the snapshot. For the scaffold, write into the document directly.
        _parameterTree.implementorValueObserver = { [weak self] param, value in
            guard let self else { return }
            defer { self.scheduleRebuild() }
            switch param.address {
            case ParamAddress.stepRate:
                let all = StepRate.allCases
                self.document.scenes[self.document.activeSceneResolved].stepRate = all[min(all.count - 1, max(0, Int(value)))]
            case ParamAddress.swing:
                self.document.scenes[self.document.activeSceneResolved].swing = Int(value)
            case ParamAddress.morphMaster:
                self.document.morphMaster = Double(value)
            case let a where a >= 200 && a < 200 + AUParameterAddress(colourIDs.count):
                self.document.colours[Int(a - 200)].morph = Double(value)
            case let a where a >= 100 && a < 100 + AUParameterAddress(colourIDs.count):
                self.document.colours[Int(a - 100)].transpose = Int(value)
            case let a where a >= 400 && a < 400 + AUParameterAddress(ParamAddress.macroSliderCount):
                // MACRO SLIDER (host automation / CC rail / in-app fader): OFFSET only — bases untouched.
                if self.document.macros == nil { self.document.macros = self.document.macrosResolved }
                self.document.macros?[Int(a - 400)].value = max(0, min(1, Double(value)))
            default: break
            }
        }
        _parameterTree.implementorValueProvider = { [weak self] param in
            guard let self else { return 0 }
            switch param.address {
            case ParamAddress.stepRate:
                return AUValue(StepRate.allCases.firstIndex(of: self.document.activeSceneState.stepRate) ?? 2)
            case ParamAddress.swing: return AUValue(self.document.activeSceneState.swing)
            case ParamAddress.morphMaster: return AUValue(self.document.morphMaster)
            case let a where a >= 200 && a < 200 + AUParameterAddress(colourIDs.count):
                return AUValue(self.document.colours[Int(a - 200)].morph)
            case let a where a >= 100 && a < 100 + AUParameterAddress(colourIDs.count):
                return AUValue(self.document.colours[Int(a - 100)].transpose)
            case let a where a >= 400 && a < 400 + AUParameterAddress(ParamAddress.macroSliderCount):
                return AUValue(self.document.macrosResolved[Int(a - 400)].value)
            default: return 0
            }
        }
    }

    // MARK: - Test-session loading (docs/test-procedures.md; step 3 has no grid UI)

    /// DESTRUCTIVE by design: replaces the whole document, discarding whatever was loaded.
    /// Goes through the normal document path so it exercises the same code fullState does.
    /// Parameter tree is resynced afterwards — otherwise the tree would still hold the old
    /// morph/transpose values and the next host automation touch would fight the new document.
    func loadTestSession(_ session: TestSessions.Session) {
        dispatchPrecondition(condition: .onQueue(.main))
        document = session.make()
        document.migrateLegacyRoutingIfNeeded()   // fill inputRow from legacy stack (now the live routing field)
        loadedTestSession = session.id

        // Tree writes re-enter implementorValueObserver (each calling scheduleRebuild), so
        // suppress and publish exactly one snapshot at the end.
        suppressRebuild = true
        syncParameterTreeToDocument()
        suppressRebuild = false
        scheduleRebuild()
    }

    /// Load a factory scene (Docs/factory-scenes.md) — same replace-and-resync path as a test session.
    func loadFactoryScene(_ index: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard index >= 0, index < SceneFactory.scenes.count else { return }
        document = SceneFactory.load(index)
        document.migrateLegacyRoutingIfNeeded()   // no-op (scenes are v3) but keeps the one load path
        loadedTestSession = "S\(index + 1)"
        suppressRebuild = true
        syncParameterTreeToDocument()
        suppressRebuild = false
        scheduleRebuild()
    }

    // MARK: - MULTI-SCENE — the strip switches activeScene within one document (2026-07-27)
    func uiScenes() -> [SceneState] { document.scenes }
    func uiActiveScene() -> Int { document.activeSceneResolved }
    /// SWITCH to a non-empty scene (immediate, v1). Arms a one-shot voice flush so the old scene's notes close
    /// cleanly as the new scene's snapshot publishes (a generation change alone doesn't flush — no stuck notes).
    func setActiveScene(_ i: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard i >= 0, i < document.scenes.count, !document.scenes[i].isEmpty, i != document.activeSceneResolved else { return }
        kernel.flushVoices()
        editDocument { $0.switchScene(to: i) }
    }
    /// SAVE-HERE: write the ACTIVE scene into slot `i` (the "+" gesture). No flush — the playing scene is unchanged.
    func saveSceneHere(_ i: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        editDocument { $0.saveCurrentScene(toSlot: i) }
    }
    /// RESTART-the-pass (tap the active chip): re-anchor the playing clock so the current moment becomes column 0
    /// ("take it from the top"), flushing the old pass's voices. A transport gesture — no document edit/rebuild.
    func restartPass() {
        dispatchPrecondition(condition: .onQueue(.main))
        kernel.restartPass()
    }
    /// S3 drag: MOVE (onto empty) / SWAP (onto occupied) — never overwrite. The active scene's CONTENT is
    /// unchanged (it only moves slot), so no voice flush — the music plays on through a re-arrange.
    func moveOrSwapScene(from a: Int, to b: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        editDocument { $0.dragScene(from: a, to: b) }
    }
    /// S3 trash: delete a scene. Refuses (returns false) the ACTIVE scene / empty / out-of-range — the UI shakes.
    @discardableResult func deleteScene(_ i: Int) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        var ok = false
        editDocument { ok = $0.deleteScene(i) }
        return ok
    }

    // MARK: - PRESETS v1 (§3): whole-document named files (PresetStore), surfaced through BOTH our in-plugin
    // browser AND the standard AUv3 user-preset API (so AUM et al. list them in their own preset menu). One
    // store (PresetStore), two front doors. Distinct from `fullState` (that stays the host's session autosave).
    private var currentPresetName = ""
    private var _currentPreset: AUAudioUnitPreset? = nil
    func uiCurrentPreset() -> String { currentPresetName }
    func listPresets() -> [String] { PresetStore.list() }

    // §3 FACTORY presets (READ-ONLY): DEFAULT (the 3-scene arc) + THE CURRICULUM (SceneFactory's teaching scenes).
    // Code-defined builders, not files — so no save/overwrite/delete. Numbered non-negative for the host API.
    static let factoryPresetBuilders: [(name: String, make: () -> PluginState)] =
        [("DEFAULT", PluginState.defaultArc),
         ("THE LADDER", PluginState.makeLadder), ("TIDE", PluginState.makeLadderTide),
         ("FORGE", PluginState.makeLadderForge), ("CHIME", PluginState.makeLadderChime),
         ("SPARK", PluginState.makeLadderSpark)] + SceneFactory.scenes.map { s in (s.name, s.make) }
    func factoryPresetNames() -> [String] { Self.factoryPresetBuilders.map { $0.name } }
    /// Apply a factory preset's document — one undoable step + voice flush (from a builder, not a file). No KVO.
    private func applyFactoryDocument(named name: String) {
        guard let fp = Self.factoryPresetBuilders.first(where: { $0.name == name }) else { return }
        kernel.flushVoices()
        editDocument { $0 = fp.make(); $0.migrateLegacyRoutingIfNeeded() }   // migrate is a no-op for v4 builders
        currentPresetName = name
    }
    /// LOAD a factory preset (our browser). Applies it AND updates the host's current-preset selection.
    func loadFactoryPreset(named name: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        applyFactoryDocument(named: name)
        let p = AUAudioUnitPreset(); p.name = name
        p.number = Self.factoryPresetBuilders.firstIndex(where: { $0.name == name }) ?? 0   // factory ⇒ non-negative
        willChangeValue(forKey: "currentPreset"); _currentPreset = p; didChangeValue(forKey: "currentPreset")
    }

    /// The document the host would persist right now (preview restored, exactly like `fullState`).
    private var documentToSave: PluginState {
        previewOverlay.map { document.restoringCell(col: $0.col, row: $0.row, to: $0.under) } ?? document
    }
    /// Apply a preset's document — ONE undoable step (§3), voices closed via the transition machinery. No host
    /// notification (the caller owns that): used by both our LOAD and the host's `currentPreset` setter.
    private func applyPresetDocument(named name: String) {
        guard let doc = PresetStore.load(name) else { return }
        kernel.flushVoices()                 // a session act — no arm ceremony
        editDocument { $0 = doc }            // one undoable step
        currentPresetName = PresetStore.sanitize(name)
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
        let scene = document.activeSceneState
        _parameterTree.parameter(withAddress: ParamAddress.stepRate)?.value =
            AUValue(StepRate.allCases.firstIndex(of: scene.stepRate) ?? 2)
        _parameterTree.parameter(withAddress: ParamAddress.swing)?.value = AUValue(scene.swing)
        _parameterTree.parameter(withAddress: ParamAddress.morphMaster)?.value = AUValue(document.morphMaster)
        for i in colourIDs.indices {
            _parameterTree.parameter(withAddress: ParamAddress.morph(i))?.value =
                AUValue(document.colours[i].morph)
            _parameterTree.parameter(withAddress: ParamAddress.transpose(i))?.value =
                AUValue(document.colours[i].transpose)
        }
        let macros = document.macrosResolved
        for i in 0..<ParamAddress.macroSliderCount {
            _parameterTree.parameter(withAddress: ParamAddress.macro(i))?.value = AUValue(macros[i].value)
        }
    }

    // MARK: - fullState = the host-level Preset (§1: the only thing called a preset)
    private static let stateKey = "com.paulbarrett.midispark.document"

    // Staging live-preview overlay (main thread): while a staged cell is transiently placed on the grid
    // for the in-context preview, this records where + the cell it displaced, so fullState encodes the
    // RESTORED cell — a host autosave mid-hover must never persist the transient preview into a preset.
    private var previewOverlay: (col: Int, row: Int, under: Cell?)? = nil
    func setPreviewOverlay(col: Int, row: Int, under: Cell?) { previewOverlay = (col, row, under) }
    func clearPreviewOverlay() { previewOverlay = nil }

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            let encodeDoc = previewOverlay.map { document.restoringCell(col: $0.col, row: $0.row, to: $0.under) } ?? document
            if let data = try? JSONEncoder().encode(encodeDoc) { state[Self.stateKey] = data }
            return state
        }
        set {
            super.fullState = newValue
            if let data = newValue?[Self.stateKey] as? Data,
               var doc = try? JSONDecoder().decode(PluginState.self, from: data) {
                doc.migrateLegacyRoutingIfNeeded()   // old saved AUM sessions → v3 schema on load (mandatory)
                document = doc
                kernel.flushVoices()                 // audit B3: flush like every other load path — a mid-play host
                                                     // session restore must not strand the outgoing document's voices
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
    }

    public override func deallocateRenderResources() {
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

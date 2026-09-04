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
    private var document = PluginState.makeInit()   // user 2026-08-09: a fresh instance loads the EMPTY "INIT" (the ARC is a named preset)
    private let store: SnapshotStore
    private var rebuildPending = false
    private var snapshotGeneration: UInt64 = 1
    private var suppressRebuild = false

    /// Currently loaded test session id ("—" until one is loaded). Diagnostics only.
    private(set) var loadedTestSession = "—"

    /// Live kernel diagnostics for the debug UI (polled; torn reads are fine for display).
    func kernelDiagnostics() -> KernelDiag { kernel.diag }
    // FREE-RUN CLOCK (Paul 2026-08-25): let the plugin run its own beat when the host transport is stopped + a note is held.
    func setFreeRunEnabled(_ b: Bool) { kernel.setFreeRunEnabled(b) }
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
        guard !document.scenes.isEmpty else { return }   // K3 (2026-08-30): a decoded doc with scenes:[] would trap on scenes[0] — activeSceneResolved clamps the index but can't conjure a scene. Builders always make ≥1 + deleteScene refuses to empty, so unreachable today; a defensive guard on the main edit chokepoint.
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

    // (sessionActive / sessionDirty — the transactional-session status reads — were removed 2026-08-27, zero references.)

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
        return colourTemplateChain(cell.colourID)                              // else the colour TEMPLATE → legacy A face (3-tier, matches the builder)
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
            guard let cell = scene.cellAt(t.col, t.row) else { continue }   // bounds-safe (stale/ragged positions) — was a raw subscript that trapped, unlike editCells (U1 fix 2026-08-27)
            var chain = materializedChain(cell); mutate(&chain)
            writes.append((t.col, t.row, chain))
        }
        editScene { s in for w in writes { if var c = s.cellAt(w.col, w.row) { c.processors = w.chain; s.setCell(w.col, w.row, c) } } }
    }
    func editSlotCells(_ targets: [(col: Int, row: Int)], slot: Int, _ mutate: (inout ProcessorSlot) -> Void) {
        withChainCells(targets) { if slot < $0.count { mutate(&$0[slot]) } }
    }
    func setSlotTypeCells(_ targets: [(col: Int, row: Int)], slot: Int, _ type: ProcessorType) { editSlotCells(targets, slot: slot) { $0.type = type } }
    func toggleSlotBypassCells(_ targets: [(col: Int, row: Int)], slot: Int) { editSlotCells(targets, slot: slot) { $0.bypassed.toggle() } }
    func addSlotCells(_ targets: [(col: Int, row: Int)], type: ProcessorType = .passgate) { withChainCells(targets) { if $0.count < 8 { $0.append(ProcessorSlot(type: type)) } } }
    /// Remove a chain slot — ANY slot, incl. the head and the LAST one (user 2026-08-09: all processors are deletable).
    /// Deleting the final slot leaves an EMPTY chain `[]` = the born-audible passthrough (the source flows untreated).
    func removeSlotCells(_ targets: [(col: Int, row: Int)], slot: Int) { withChainCells(targets) { if slot < $0.count { $0.remove(at: slot) } } }

    // MARK: - COLOUR-OWNED chain (the per-colour machine — GLOBAL by construction: colours are document-level, and a
    // cell with no per-cell override inherits its colour's `templateChain`, so every cell of the colour, in EVERY
    // scene, renders the one machine. "You only ever edit colours." (user 2026-08-09: per-colour model, GLOBAL.)
    private func colourTemplateChain(_ colourID: String) -> [ProcessorSlot] {
        let c = document.colours.first { $0.colourID == colourID }
        if let t = c?.templateChain, !t.isEmpty { return t }
        return [ProcessorSlot(type: c?.type ?? .passgate, params: c?.paramsA ?? ColourParams())]   // materialise the legacy A face on first edit
    }
    private func passthroughTemplateSlot() -> ProcessorSlot { var s = ProcessorSlot(type: .passgate); s.bypassed = true; return s }   // all-bypassed ≡ empty ≡ passthrough
    /// Does this colour carry its OWN stored chain? A nil templateChain falls back to the legacy A-face (an arp, for
    /// the default colours) — BUILD reads this straight off `document` (NOT the polled `docColours` mirror, which is
    /// empty on first appear) to convert a bare colour to an explicit passthrough at load. (user 2026-08-12)
    func colourHasStoredChain(_ colourID: String) -> Bool { document.colours.first { $0.colourID == colourID }?.templateChain != nil }
    /// Mutate the colour's chain and clear the per-cell overrides of every cell of that colour (all scenes) so they
    /// inherit it. An empty result stores a single bypassed slot = the born-audible passthrough (an empty template
    /// would fall through to the legacy face). ONE undoable document edit.
    /// The chain as DISPLAYED for a colour — a representative placed cell's RESOLVED chain (per-cell override →
    /// template → legacy), so a colour-scoped edit is based on what the user sees, never the bare template. Without
    /// this, adding/editing a slot re-read the template + cleared overrides → a per-cell arp config reverted (user
    /// 2026-08-10). Falls back to the template/legacy face when the colour has no placed cell.
    private func resolvedColourChain(_ colourID: String) -> [ProcessorSlot] {
        for s in document.scenes {
            for col in s.cells {
                for cell in col where cell?.colourID == colourID { if let cell { return materializedChain(cell) } }
            }
        }
        return colourTemplateChain(colourID)
    }
    /// Store a colour's chain on its template (empty → a bypassed-passgate passthrough) + drop every matching cell's
    /// per-cell override so all inherit the template — ONE editDocument = one undo record. (shared, 2026-08-15)
    private func storeColourChainClearingOverrides(_ colourID: String, _ chain: [ProcessorSlot]) {
        let stored: [ProcessorSlot] = chain.isEmpty ? [passthroughTemplateSlot()] : chain
        editDocument { doc in
            if let ci = doc.colours.firstIndex(where: { $0.colourID == colourID }) { doc.colours[ci].templateChain = stored }
            for si in doc.scenes.indices {
                for c in doc.scenes[si].cells.indices {
                    for r in doc.scenes[si].cells[c].indices where doc.scenes[si].cells[c][r]?.colourID == colourID {
                        doc.scenes[si].cells[c][r]?.processors = nil     // inherit the template (drop any stale override)
                    }
                }
            }
        }
    }
    func withChainColour(_ colourID: String, _ mutate: (inout [ProcessorSlot]) -> Void) {
        var chain = resolvedColourChain(colourID)
        mutate(&chain)
        storeColourChainClearingOverrides(colourID, chain)
    }
    /// Set a colour's chain to EXACTLY `chain` (empty → a bypassed-passgate passthrough) + clear every cell's override.
    /// The UI computes `chain` from what's DISPLAYED (cellChain(editingCell)), so an edit never operates on a stale
    /// representative cell → deleting the first of two slots leaves the other, not a passgate. (user 2026-08-10 bug.)
    func setColourChain(_ colourID: String, _ chain: [ProcessorSlot]) {
        storeColourChainClearingOverrides(colourID, chain)
    }
    func addSlotColour(_ id: String, type: ProcessorType = .passgate) { withChainColour(id) { if $0.count < 8 { $0.append(ProcessorSlot(type: type)) } } }
    func removeSlotColour(_ id: String, slot: Int) { withChainColour(id) { if slot < $0.count { $0.remove(at: slot) } } }
    func editSlotColour(_ id: String, slot: Int, _ mutate: (inout ProcessorSlot) -> Void) { withChainColour(id) { if slot < $0.count { mutate(&$0[slot]) } } }
    func setSlotTypeColour(_ id: String, slot: Int, _ type: ProcessorType) { editSlotColour(id, slot: slot) { $0.type = type } }
    func toggleSlotBypassColour(_ id: String, slot: Int) { editSlotColour(id, slot: slot) { $0.bypassed.toggle() } }
    /// Apply `mutate` to EVERY cell of a colour, across all scenes — the colour-scoped path for the per-cell ROUTING
    /// fields (receiver / emitters / chop are stored on the Cell, not the Colour, so "edit the colour" fans out to
    /// all its cells). Used by the DRAG&DROP page so a receiver/emitter pick pushes to every instance. ONE undoable
    /// document edit. (user 2026-08-09)
    func editCellsOfColour(_ colourID: String, _ mutate: (inout Cell) -> Void) {
        editDocument { doc in
            for si in doc.scenes.indices {
                for c in doc.scenes[si].cells.indices {
                    for r in doc.scenes[si].cells[c].indices where doc.scenes[si].cells[c][r]?.colourID == colourID {
                        if var cell = doc.scenes[si].cells[c][r] { mutate(&cell); doc.scenes[si].cells[c][r] = cell }
                    }
                }
            }
        }
    }
    /// The pointed cell's twin positions (incl. itself) for the grid highlight.

    // MARK: - CELL MACHINE stage-4 — the CELL LIBRARY (named saved cells, reusable across sessions)

    /// Save the cell at (col,row) to the library under `name` — "machine minus routing" (chain materialised +
    /// source-shaping; routing/perform state stripped). Returns false if the slot is empty or the write fails.
    @discardableResult
    func saveCellToLibrary(col: Int, row: Int, name: String) -> Bool {
        guard let cell = document.scenes[document.activeSceneResolved].cells[col][row] else { return false }
        return CellLibraryStore.save(cell.libraryStripped(materialisedChain: materializedChain(cell)), as: name)
    }
    // BUILD-side save: a COLOUR's machine (chain) becomes a library cell (no grid cell needed). Routing stripped.
    @discardableResult
    func saveChainToLibrary(colourID: String, chain: [ProcessorSlot], name: String) -> Bool {
        var c = Cell(colourID: colourID); c.processors = chain; c.buses = []
        return CellLibraryStore.save(c, as: name)
    }
    // Browser rows for SAVED cells: name + chain processor types + star rating (loads each cell).
    func libraryCellSummaries() -> [LibEntry] {
        CellLibraryStore.list().map { name in
            let c = CellLibraryStore.load(name)
            return LibEntry(name: name, types: (c?.processors ?? []).map { $0.type }, stars: c?.starsResolved ?? 0)
        }
    }
    // Browser rows for the read-only FACTORY set (curated star ratings).
    func factoryLibrarySummaries() -> [LibEntry] {
        CellLibraryStore.factory().map { LibEntry(name: $0.name, types: ($0.cell.processors ?? []).map { $0.type }, stars: $0.cell.starsResolved) }
    }
    // Re-rate a SAVED cell (0–5) and persist. Factory cells are read-only.
    func setLibraryStars(_ name: String, _ stars: Int) {
        guard var c = CellLibraryStore.load(name) else { return }
        c.stars = max(0, min(5, stars)); CellLibraryStore.save(c, as: name)
    }
    func loadLibraryCell(name: String) -> Cell? { CellLibraryStore.load(name) }
    func deleteLibraryCell(name: String) { CellLibraryStore.delete(name) }
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
    // BUILD UNDO (Paul 2026-08-27): the BUILD page authors in VC @State, so its undo captures that @State PLUS a copy of
    // the document (document-colour chain / receiver / rack edits also happen there). These let a BUILD snapshot round-trip
    // the document without touching the transactional undoStack above. `restoreDocumentFromUndo` sets it WITHOUT recording.
    func documentSnapshot() -> PluginState { document }
    func restoreDocumentFromUndo(_ d: PluginState) { document = d; seedLatchArm(); scheduleRebuild() }
    /// The live document — for the EDIT page's SELECTION undo (which snapshots (selection, document) per select/
    /// deselect and restores both). Separate from the transactional undo stack above (which it never touches).

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
    func setLaneMask(_ mask: UInt16) { kernel.setLaneMask(mask) }
    func reelTouch() { kernel.reelTouch() }                 // THE REEL-TO-REEL: toggle record→replay / resume (Paul 2026-08-18)
    func uiReelState() -> Int { kernel.reelStateValue() }   // 0 off · 1 armed · 2 replaying
    func reelExportRangeFiles(fromPass lo: Int, toPass hi: Int, emitterMask: UInt8) -> [(name: String, data: Data)] { kernel.reelExportRange(fromPass: lo, toPass: hi, emitterMask: emitterMask) }   // pass RANGE × emitter selection
    func reelRangeRoll(fromPass lo: Int, toPass hi: Int) -> (notes: [ReelDeck.Note], cycle: Double) { kernel.reelRangeRoll(fromPass: lo, toPass: hi) }   // the concatenated roll for a multi-pass selection
    // THE PASS BROWSER (Paul 2026-08-19): the pop-up's 8×8 grid + piano roll.
    func reelPassNumbers() -> [Int] { kernel.reelPassNumbers() }          // 32 ring slots, oldest→newest (−1 = empty)
    func reelPassSignatures() -> [UInt64] { kernel.reelPassSignatures() } // per-pass content hash (aligned with passNumbers) → REMOVE DUPLICATES toggle
    func reelPassCounter() -> Int { kernel.reelPassCounter() }            // monotone completed-pass count → per-pass STATE capture (Paul #5)
    func reelSelectedRoll() -> [ReelDeck.Note] { kernel.reelSelectedRoll() }   // the selected pass's notes (A–D lanes)
    func reelSelectedPassNo() -> Int { kernel.reelSelectedPassNo() }     // the currently pinned/selected pass (−1 = auto latest)
    func reelSelectPass(_ p: Int) { kernel.reelSelectPass(p) }           // tap a pass → select + replay now
    func reelStopReplay() { kernel.reelStopReplay() }                    // stop replay → resume live
    func reelCycleBeats() -> Double { kernel.reelCycleValue() }          // the pass length (piano-roll x-axis)
    func reelSetBrowsing(_ on: Bool) { kernel.reelSetBrowsing(on) }      // pop-up open → freeze the history tape

    /// EDIT PAGE "play this cell only" (user 2026-08-08): solo the given cells while the transport plays — every
    /// PLAY: THIS CELL (user 2026-08-09) — isolate ONE cell and freeze the timeline on its column, so ONLY that
    /// cell's colour machine sounds, ungated by the grid sequence (the grid's active column is ignored). The full
    /// chain renders (normal render path, just held on this column). `clearColourSolo` restores normal play.
    func setColourSolo(col: Int, row: Int) {
        guard col >= 0, col < 8, row >= 0, row < 8 else { clearColourSolo(); return }
        if previewSolo != nil { previewSolo = nil; scheduleRebuild() }   // switching from an unplaced preview to a real placed cell
        kernel.setSoloCellMask(UInt64(1) << UInt64(col * 8 + row))
        kernel.setSoloColumn(col)
    }
    func clearColourSolo() {
        kernel.setSoloCellMask(0); kernel.setSoloColumn(-1)
        if previewSolo != nil { previewSolo = nil; scheduleRebuild() }   // drop the synthetic preview cell (republish the real document)
    }

    /// PLAY: THIS CELL for an UNPLACED colour (user 2026-08-10) — there's no grid cell to freeze on, so drop a
    /// SYNTHETIC cell of the colour at an empty slot of the active scene into an EPHEMERAL snapshot (never the
    /// document — encode/persist read `document`) and solo it. The REAL render path then plays the colour's full
    /// machine (templateChain via `processors = nil`, its latch/live input, sustained under the frozen column).
    /// Returns false if the grid is full. `clearColourSolo` drops the synthetic cell. `inputReceiver`/`buses` are the
    /// page STICKY (what a placed cell would inherit).
    private var previewSolo: (col: Int, row: Int, cell: Cell)? = nil
    @discardableResult
    func setColourSoloPreview(colourID: String, inputReceiver: Int, buses: [Bus]) -> Bool {
        let scene = document.activeSceneState
        var slot: (col: Int, row: Int)? = nil
        search: for c in 0..<8 { for r in 0..<8 where scene.cellAt(c, r) == nil { slot = (c, r); break search } }
        guard let (col, row) = slot else { return false }   // grid full → no room for the preview
        var cell = Cell(colourID: colourID, buses: buses.isEmpty ? [.a] : Set(buses))
        cell.inputReceiver = max(0, min(3, inputReceiver))
        cell.processors = nil                                // inherit the colour's templateChain (its machine)
        previewSolo = (col, row, cell)
        scheduleRebuild()                                    // publishes the snapshot WITH the synthetic cell (renderDoc)
        kernel.setSoloCellMask(UInt64(1) << UInt64(col * 8 + row))
        kernel.setSoloColumn(col)
        return true
    }
    /// BUILD: when the STAGING voice is playing, the engine renders THIS scene (the staging grid) in place of the
    /// document's active scene — ephemeral, the document is NEVER touched (encode/persist read `document`). nil = off.
    private var stagingRenderScene: SceneState? = nil
    func setBuildStagingScene(_ scene: SceneState?) { stagingRenderScene = scene; scheduleRebuild() }
    // PHASE 2 render-time AUTO (Paul 2026-09-04): the LIVE per-colour AUTO lanes, folded into the rendered doc so
    // SnapshotBuilder can build the render-time descriptors (×N passes / SMOOTH). nil ⇒ use the document's own.
    private var stagingAuto: [String: PartAutoColour]? = nil
    func setBuildAuto(_ a: [String: PartAutoColour]?) { stagingAuto = a; scheduleRebuild() }

    /// The document the snapshot renders from — the real `document`, plus the ephemeral PLAY: THIS CELL preview cell
    /// (unplaced-colour audition) injected at its empty slot, or the BUILD staging grid override. Never used by
    /// encode/persist (those read `document`).
    /// BUILD's EPHEMERAL colours (beyond the 16 document slots) — id → its machine. renderDoc appends them so cells /
    /// auditions referencing them resolve. Never persisted (encode/persist read `document`). (Paul 2026-08-15)
    private var buildEphemeralColours: [(id: String, machine: [ProcessorSlot], transpose: Int)] = []
    func setBuildEphemeralColours(_ cs: [(id: String, machine: [ProcessorSlot], transpose: Int)]) { buildEphemeralColours = cs; scheduleRebuild() }

    private func renderDoc() -> PluginState {
        if stagingRenderScene == nil, previewSolo == nil, buildEphemeralColours.isEmpty, stagingAuto == nil { return document }
        var temp = document
        if let sa = stagingAuto { temp.partAuto = sa }   // PHASE 2: the LIVE AUTO lanes reach the box for render-time (×N / SMOOTH)
        for e in buildEphemeralColours where !temp.colours.contains(where: { $0.colourID == e.id }) {   // append BUILD ephemeral colours
            var col = Colour(colourID: e.id, type: .arp)
            col.defined = true
            col.transpose = max(-24, min(24, e.transpose))              // REGISTER HOME (ensemble roll 2026-08-19): the row's octave offset
            // An EMPTY machine is a born-audible PASSTHROUGH, not "no chain": store the bypassed-passgate placeholder,
            // else the builder collapses [] → nil and falls to the legacy A-face (an ARP) — a seeded empty tab-1 colour
            // played as an arp despite showing an empty chain. (Paul 2026-08-17)
            col.templateChain = e.machine.isEmpty ? [passthroughTemplateSlot()] : e.machine
            temp.colours.append(col)
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
            if let p = previewSolo { temp.scenes[si].setCell(p.col, p.row, p.cell) }
        }
        return temp
    }

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
    func setInputSemitone(_ recv: Int, _ n: Int) { kernel.setInputSemitone(recv, n) }   // receiver strip: ±semitone NOTE nudge
    func setInputVelOverride(_ recv: Int, _ value: Int?) { kernel.setInputVelOverride(recv, value) }   // receiver strip: slider
    func setLatchArm(_ mask: UInt8) { kernel.setLatchArm(mask); document.latchArmMask = mask }   // live arm + PERSIST the intent so a saved session reopens engaged (Paul 2026-08-27). Direct doc write (no rebuild/undo) — the render reads the arm via the live kernel path, this field is for fullState only.
    func latchArm() -> UInt8 { kernel.latchArm() }                 // the UI polls this to RE-DERIVE the arm after a view rebuild (else it's lost)
    private func seedLatchArm() { kernel.setLatchArm(document.latchArmMask ?? 0) }   // on a document LOAD/restore, seed the kernel's live arm from the persisted mask
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
    func pollCellStrikes() -> [UInt8] { kernel.drainCellStrikes() }   // SEAL comet: per-cell peak strike velocity (col*Snap.rows+row)
    func pollCellNotes() -> (pitch: [UInt8], vel: [UInt8], count: [UInt8]) { kernel.drainCellNotes() }   // NOTE-SWEEP: per-cell recent emitted note-ons
    func setFocusCell(_ cell: Int) { kernel.setFocusCell(cell) }   // FOCUS note-event feed: the machine's cell
    func pollFocusNotes() -> (pitch: [UInt8], vel: [UInt8], beat: [Double], count: Int) { kernel.drainFocusNotes() }
    func pollCellSounding() -> (lo: UInt64, hi: UInt64) { kernel.pollCellSounding() }   // SEAL comet: per-cell sounding gate (128 cells: lo=0…63, hi=64…127)
    // PART ROLL (Paul 2026-09-02): the live per-part-cycle emitted-note capture for the part-page piano roll.
    func setPartRoll(active: Bool, cycleBeats: Double) { kernel.setPartRoll(active: active, cycleBeats: cycleBeats) }
    func pollPartRoll() -> [PartRollDeck.Note] { kernel.pollPartRoll() }
    func offlinePartRoll(cyc: Double) -> [PartRollDeck.Note] { kernel.offlinePartRoll(cyc: cyc) }   // the deterministic no-lag feed
    func pollWithheldMarks() -> [[(vel: UInt8, col: Int8)]] { kernel.drainWithheldMarks() }   // §6a the withheld tell
    func pollReceiverSounding() -> [[UInt8]] { kernel.pollReceiverSounding() }   // duration: currently-held input notes (latch-aware meter)
    func pollReceiverSoundingNotes() -> [[UInt8]] { kernel.pollReceiverSoundingNotes() }   // PITCHES held per door (REPLAY roll)
    func pollReceiverLiveHeld() -> UInt8 { kernel.pollReceiverLiveHeld() }       // the header dot: bit i = a LIVE accepted note is held (scalar, race-safe)
    func pollEmitterSounding() -> [[(vel: UInt8, col: Int8)]] { kernel.drainEmitterSounding() }   // §strips-done: currently-sounding per emitter (cargo-tinted)

    /// Read-only snapshot of the per-bus stamp channels for the OUTPUTS panel (delta §7).
    func uiBusChannels() -> [Int] { document.busChannelsResolved }

    /// delta §9 item 11: the four resolved receivers (nil-safe) for the editor's INPUT radio + the panel.
    func uiReceivers() -> [Receiver] { document.receiversResolved }
    func setReceiverChannel(_ i: Int, _ ch: Int) { editReceiver(i) { $0.channel = max(0, min(16, ch)) } }
    // MULTI-CHANNEL (Paul 2026-08-21): a door hears an arbitrary channel SUBSET (16-bit mask). Toggle one channel (1–16),
    // or set the whole mask (ALL = 0xFFFF, NONE = 0). Enables the door (so ALL/a channel un-blocks it).
    func toggleReceiverChannel(_ i: Int, _ ch: Int) {
        guard ch >= 1 && ch <= 16 else { return }
        editReceiver(i) { r in r.channelMask = r.channelMaskResolved ^ (UInt16(1) << UInt16(ch - 1)); r.inputEnabled = true }
    }
    func setReceiverChannelMask(_ i: Int, _ mask: UInt16) { editReceiver(i) { $0.channelMask = mask; $0.inputEnabled = true } }
    // setReceiverCable retired 2026-08-03 (COG SIMPLIFICATION — cables gone from the UI; the render hears all cables).
    func toggleReceiverMute(_ i: Int)             { editReceiver(i) { $0.muted.toggle() } }
    // INPUT ENABLE (the strip header): DISABLE stops the door listening (dark meter, latch sealed) — an armed
    // latch keeps feeding the grid; a mute (below) is what stops the feed. Persisted, like mute.
    func toggleReceiverEnabled(_ i: Int)          { editReceiver(i) { $0.inputEnabled = !($0.inputEnabledResolved) } }
    // KEYS EXCLUDE (Paul 2026-08-22): the complement door — subtract door `d`'s live notes (by pitch class) from this
    // door's typed KEYS pool. -1 = OFF; never self. UI offers the three doors that aren't this one.
    func setExcludeDoor(_ i: Int, _ d: Int) { editReceiver(i) { $0.excludeDoor = (d >= 0 && d <= 3 && d != i) ? d : -1 } }
    func setReceiverExcludeMode(_ i: Int, _ m: ExcludeMode) { editReceiver(i) { $0.excludeMode = m } }     // §3: MINUS (complement) | ONLY (in-key)
    func setReceiverExcludeReject(_ i: Int, _ r: ExcludeReject) { editReceiver(i) { $0.excludeReject = r } }  // §3: BLOCK (silence) | SNAP (nearest legal)
    // THE CONFIG SHEETS (Paul 2026-08-20): the door's MODE radio. Sets doorMode + syncs the legacy latch fields for the 3
    // existing modes (lossless downgrade). REPLAY/FILE store the mode only (their behaviour lands in stages 3/4).
    func setDoorMode(_ i: Int, _ mode: DoorMode) {
        editReceiver(i) { r in
            r.doorMode = mode
            switch mode {
            case .latch: r.latchAdd = true;  r.latchPiano = false
            case .hold:  r.latchAdd = false; r.latchPiano = false
            case .keys:  r.latchPiano = true
            case .scale: r.latchPiano = false   // SCALE derives its own pool (scaleNotes); the resolver keys off doorMode
            case .chord: r.latchPiano = false   // CHORD derives its own pool (chordDoorNotes); the resolver keys off doorMode
            case .thru, .replay, .file: break   // THRU can't arm (the resolvers key off doorMode), so the latch fields are moot
            }
        }
    }
    // THE SCALE DOOR (ratified §1): the picker sets root · scale · home-octave window; the derived pool feeds the KEYS pipeline.
    // FOUR SCALE POOLS (Paul 2026-09-04): slot-aware setters write into `scalePools[slot]`; `setReceiverActiveScale` is the
    // RADIO switch (live). `editReceiverScaleSlot` materializes the four concrete pools (from the resolver, migrating the
    // legacy single scale into slot 0) before mutating, so no edit path diverges. The legacy flat setters below delegate to
    // the ACTIVE slot (kept for any existing caller; new UI uses the slot setters directly).
    private func editReceiverScaleSlot(_ i: Int, _ slot: Int, _ f: (inout ScalePool) -> Void) {
        guard (0..<4).contains(slot) else { return }
        editReceiver(i) { r in
            var pools = r.scalePoolsResolved      // 4 concrete pools (migrates legacy single → slot 0)
            f(&pools[slot])
            r.scalePools = pools
        }
    }
    func setReceiverActiveScale(_ i: Int, _ slot: Int) {
        editReceiver(i) { r in
            if r.scalePools == nil { r.scalePools = r.scalePoolsResolved }   // materialize so the radio + pools travel together
            r.activeScale = max(0, min(3, slot))
        }
    }
    func setReceiverScaleSlotRoot(_ i: Int, _ slot: Int, _ root: Int) { editReceiverScaleSlot(i, slot) { $0.root = (root % 12 + 12) % 12 } }
    func setReceiverScaleSlotType(_ i: Int, _ slot: Int, _ type: ScaleType) { editReceiverScaleSlot(i, slot) { $0.type = type } }
    func setReceiverScaleSlotBaseOct(_ i: Int, _ slot: Int, _ oct: Int) { editReceiverScaleSlot(i, slot) { $0.baseOct = max(0, min(8, oct)) } }
    func setReceiverScaleSlotOctaves(_ i: Int, _ slot: Int, _ oct: Int) { editReceiverScaleSlot(i, slot) { $0.octaves = max(1, min(4, oct)) } }
    private func activeScaleSlot(_ i: Int) -> Int {
        let rs = document.receiversResolved
        return (0..<rs.count).contains(i) ? rs[i].activeScaleResolved : 0
    }
    // THE CHORD DOOR (Paul 2026-09-04): four chord pools + the radio, mirroring the scale-pool setters.
    private func editReceiverChordSlot(_ i: Int, _ slot: Int, _ f: (inout ChordPool) -> Void) {
        guard (0..<4).contains(slot) else { return }
        editReceiver(i) { r in
            var pools = r.chordPoolsResolved
            f(&pools[slot])
            r.chordPools = pools
        }
    }
    func setReceiverActiveChord(_ i: Int, _ slot: Int) {
        editReceiver(i) { r in
            if r.chordPools == nil { r.chordPools = r.chordPoolsResolved }
            r.activeChord = max(0, min(3, slot))
        }
    }
    func setReceiverChordSlotSource(_ i: Int, _ slot: Int, _ source: Int) { editReceiverChordSlot(i, slot) { $0.source = max(-1, min(3, source)) } }
    func setReceiverChordSlotDegree(_ i: Int, _ slot: Int, _ degree: Int) { editReceiverChordSlot(i, slot) { $0.degree = ((degree % 7) + 7) % 7 } }
    func setReceiverChordSlotVoicing(_ i: Int, _ slot: Int, _ v: ChordVoicing) { editReceiverChordSlot(i, slot) { $0.voicing = v } }
    func setReceiverChordSlotSpread(_ i: Int, _ slot: Int, _ s: ChordSpread) { editReceiverChordSlot(i, slot) { $0.spread = s } }
    func setReceiverChordSlotBaseOct(_ i: Int, _ slot: Int, _ oct: Int) { editReceiverChordSlot(i, slot) { $0.baseOct = max(0, min(8, oct)) } }
    func setReceiverScaleRoot(_ i: Int, _ root: Int) { setReceiverScaleSlotRoot(i, activeScaleSlot(i), root) }
    func setReceiverScaleType(_ i: Int, _ type: ScaleType) { setReceiverScaleSlotType(i, activeScaleSlot(i), type) }
    func setReceiverScaleBaseOct(_ i: Int, _ oct: Int) { setReceiverScaleSlotBaseOct(i, activeScaleSlot(i), oct) }
    func setReceiverScaleOctaves(_ i: Int, _ oct: Int) { setReceiverScaleSlotOctaves(i, activeScaleSlot(i), oct) }
    // REPLAY (stage 3): how much input history loops (1·2·4·8 passes).
    func setReplayPasses(_ i: Int, _ passes: Int) { editReceiver(i) { $0.replayPasses = [1, 2, 4, 8].contains(passes) ? passes : 1 } }
    func toggleReplayCatch(_ i: Int) { kernel.toggleReplayCatch(i) }   // "LAST N" — capture+loop / release (config-sheets, Paul 2026-08-20)
    func replayEngaged() -> UInt8 { kernel.replayEngaged() }           // which REPLAY doors are actively looping
    func replayLoopRoll(door i: Int) -> [DoorRing.Note] { kernel.replayLoopRoll(door: i) }   // the engaged door's captured loop as duration notes
    func replayLoopLen(door i: Int) -> Double { kernel.replayLoopLen(door: i) }
    func replayLoopAnchor(door i: Int) -> Double { kernel.replayLoopAnchor(door: i) }   // the engaged loop's anchor beat (config-roll playhead sync, Paul 2026-08-26)
    // FILE (config-sheets stage 4): decode a loaded .mid into the door's clip (stored on the document, copy-in). Sets the
    // door to FILE mode. Returns false if the file didn't parse into notes. Large files are capped (doc-size guard).
    @discardableResult func setDoorFile(_ i: Int, data: Data, name: String) -> Bool {
        guard let (notes, loopBeats) = MidiFile.decode(data), loopBeats > 0 else { return false }
        let capped = Array(notes.prefix(8192))
        editReceiver(i) { $0.fileClip = capped; $0.fileLoopBeats = loopBeats; $0.fileName = name; $0.doorMode = .file }
        return true
    }
    func clearDoorFile(_ i: Int) { editReceiver(i) { $0.fileClip = nil; $0.fileLoopBeats = nil; $0.fileName = nil } }
    func toggleReceiverPianoNote(_ i: Int, _ note: Int) {   // pick/unpick a note on the on-screen keyboard
        editReceiver(i) { var s = Set($0.pianoNotes ?? []); if s.contains(note) { s.remove(note) } else { s.insert(note) }; $0.pianoNotes = s.sorted() }
    }
    func clearReceiverPianoNotes(_ i: Int) { editReceiver(i) { $0.pianoNotes = [] } }
    // RANGE (§2): the door's note window. Clamps to 0…127 and keeps lo ≤ hi so the window is never inverted.
    func setReceiverRange(_ i: Int, lo: Int, hi: Int) {
        let l = max(0, min(127, lo)), h = max(0, min(127, hi))
        editReceiver(i) { $0.rangeLo = min(l, h); $0.rangeHi = max(l, h) }
    }
    // §MPE (cog page, 2026-07-xx — supersedes the 2026-07-25 "no UI, silent auto-detect" ruling): the mpeMerge
    // field is now surfaced as an explicit per-receiver toggle, PLUS a live auto-detect indicator (mpeLikely).
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
    func uiRackMask() -> UInt8 { document.rackMaskResolved }          // the ACTIVE config's membership
    func uiRackConfig() -> Int { document.rackActiveConfigResolved } // which of the 4 configs is live
    // Toggle emitter `bus`'s board membership IN THE ACTIVE CONFIG. Writes rackConfigs[active] + keeps the legacy
    // rackEnabledMask synced to the active config (lossless downgrade). (THE CONFIG SHEETS, Paul 2026-08-20)
    func setRack(_ bus: Int, _ on: Bool) {
        guard (0..<4).contains(bus) else { return }
        editDocument { d in
            var configs = d.rackConfigsResolved
            let active = d.rackActiveConfigResolved
            var m = configs[active]
            if on { m |= UInt8(1 << bus) } else { m &= ~UInt8(1 << bus) }
            configs[active] = m
            d.rackConfigs = configs
            d.rackActiveConfig = active
            d.rackEnabledMask = m                                    // legacy mirror = the active config
        }
    }
    // Switch the LIVE rack config (0…3). Syncs the legacy rackEnabledMask to the newly-live config.
    func setRackConfig(_ i: Int) {
        guard (0..<4).contains(i) else { return }
        editDocument { d in
            let configs = d.rackConfigsResolved
            d.rackConfigs = configs
            d.rackActiveConfig = i
            d.rackEnabledMask = configs[i]                           // legacy mirror = the newly-live config
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
    private func activeSceneIndex() -> Int { document.activeSceneResolved }   // CR-8: activeScene is Optional now
    func uiMasterKey() -> Int { document.scenes[activeSceneIndex()].masterKeyResolved }
    func nudgeMasterKey(_ delta: Int) {
        editDocument { d in
            let i = d.activeSceneResolved
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
    // ROW 8 (Paul 2026-08-22): the action strip. `uiRow8` = the authored cells (document); `uiRow8On` = the active
    // scene's lit TOGGLE state. `setRow8On` is a PERFORMANCE write (record:false, scene-captured, rebuilds — the toggle
    // engine FREEZE/HALFTIME reads it from the box). `setRow8Cell` AUTHORS a cell (undoable document edit).
    func uiRow8() -> [Row8Cell] { document.row8Resolved }
    func uiRow8On() -> [Bool] { document.activeSceneState.row8OnResolved }
    func setRow8On(_ i: Int, _ on: Bool) {
        guard i >= 0, i < 8 else { return }
        editScene(record: false) { s in
            var o = s.row8On ?? [Bool](repeating: false, count: 8)
            while o.count < 8 { o.append(false) }
            o[i] = on
            s.row8On = o
        }
    }
    func setRow8Cell(_ i: Int, _ cell: Row8Cell) {
        guard i >= 0, i < 8 else { return }
        editDocument { d in
            var r = d.row8 ?? Row8Cell.factoryDeck
            while r.count < 8 { r.append(Row8Cell()) }
            r[i] = cell
            d.row8 = r
        }
    }
    func setMasterVelOverride(_ value: Int?) { kernel.setMasterVelOverride(value) }
    func setMasterKill(_ on: Bool) { kernel.setMasterKill(on) }   // §4b master fader-kill (bottom = all silent)
    func masterPanic() { kernel.panic() }

    /// receiver strip: the THRU pip — the receiver (0–3) passthrough follows. Persisted RADIO, but unlike
    /// CLAIM there is ALWAYS exactly one lit (no clear): tapping a strip's pip moves THRU there directly.
    func uiThruReceiver() -> Int { document.thruReceiverResolved }

    /// Read-only Colours (type + params) so the grid can render each cell's type glyph + params text.
    func uiColours() -> [Colour] { document.colours }

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
    /// panel stay in sync (the observer folds it into the document). TOGGLES (8…15) aren't AU params — write the
    /// document directly (still an OFFSET; bases untouched). Coalesced so a drag/hold isn't undo spam.
    func setMacroValue(_ index: Int, _ value: Double) {
        guard (0..<PluginState.macroBankCount).contains(index) else { return }
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
    /// The 16 live macros for the UI (8 slider + 8 toggle; timelines retired §K3). Read-back; slider values mirror the automatable params.
    func uiMacros() -> [Macro] { document.macrosResolved }
    /// Macro NAME (document-level, not an AU param) — 12 chars max; "" = unset/invitation.
    func setMacroName(_ index: Int, _ name: String) {
        guard (0..<PluginState.macroBankCount).contains(index) else { return }
        editDocument { d in
            if d.macros == nil { d.macros = d.macrosResolved }
            d.macros?[index].name = String(name.prefix(12))
        }
    }
    /// Macro PADLOCK — false = SPRING (release returns home) · true = FIXED (latched). Document-level.
    func setMacroFixed(_ index: Int, _ fixed: Bool) {
        guard (0..<PluginState.macroBankCount).contains(index) else { return }
        editDocument { d in
            if d.macros == nil { d.macros = d.macrosResolved }
            d.macros?[index].fixed = fixed
        }
    }
    /// A/B AUTHORING: replace a cell's chain wholesale — used to RESTORE the A state after a live B demonstration
    /// (the demonstration is heard at full while authoring; committing binds the delta, then the base returns to A).
    /// A/B AUTHORING: bind (append) offset targets to a macro — the delta vector (B − A per touched param). Overlaps
    /// on the same param SUM at derivation (the offset law), so appending is correct even across sections/cells.
    func addMacroTargets(_ index: Int, _ targets: [MacroTarget]) {
        guard (0..<PluginState.macroBankCount).contains(index), !targets.isEmpty else { return }
        editDocument { d in
            if d.macros == nil { d.macros = d.macrosResolved }
            d.macros?[index].targets.append(contentsOf: targets)
        }
    }
    /// A/B AUTHORING: remove a macro's binding to a cell — every target it holds on (col,row), or only those on a
    /// specific `slot` when given (the macro pop-up's per-slot "Remove from M{n}"). Reflected LIVE in the MIDI out.
    func removeMacroTargets(_ index: Int, col: Int, row: Int, slot: Int? = nil) {
        guard (0..<PluginState.macroBankCount).contains(index), document.macros != nil else { return }
        editDocument { d in d.macros?[index].targets.removeAll { $0.col == col && $0.row == row && (slot == nil || $0.slot == slot) } }
    }
    /// A/B AUTHORING (OUTPUT group): bind (append) per-emitter role-amount deltas to a macro.
    func addMacroEmitterTargets(_ index: Int, _ targets: [MacroEmitterTarget]) {
        guard (0..<PluginState.macroBankCount).contains(index), !targets.isEmpty else { return }
        editDocument { d in
            if d.macros == nil { d.macros = d.macrosResolved }
            d.macros?[index].emitterTargets.append(contentsOf: targets)
        }
    }
    /// A/B AUTHORING (OUTPUT group): clear a macro's OUTPUT bindings (the "remove OUTPUT" chip).
    func removeMacroEmitterTargets(_ index: Int) {
        guard (0..<PluginState.macroBankCount).contains(index), document.macros != nil else { return }
        editDocument { d in d.macros?[index].emitterTargets.removeAll() }
    }
    /// MACRO AUTHORING (canonical pop-up): restore the WHOLE macros vector — the pop-up's CANCEL reverts every
    /// binding/value change since it opened. Re-syncs the slider AU params (0–7) so their live values match.
    func setMacrosDocument(_ m: [Macro]?) {
        editDocument(record: false) { $0.macros = m }
        if let m = m {
            for i in 0..<ParamAddress.macroSliderCount where i < m.count {
                _parameterTree.parameter(withAddress: ParamAddress.macro(i))?.value = AUValue(max(0, min(1, m[i].value)))
            }
        }
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
    // The display hue (packed RGB) per colourID — so the render can tag emitted notes with their cell's colour (the
    // reel piano roll paints each note its colour). Same resolution the UI uses: an ephemeral override, else the
    // canonical palette hex, else a neutral grey. (Paul 2026-08-19)
    private func snapHues(_ doc: PluginState) -> [String: UInt32] {
        var m: [String: UInt32] = [:]
        for c in doc.colours {
            m[c.colourID] = colourHueOverride[c.colourID] ?? colourIDs.firstIndex(of: c.colourID).map { colourHexes[$0] } ?? 0x808080
        }
        return m
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
        store = SnapshotStore(initial: SnapshotBuilder.build(from: PluginState.makeInit(), generation: 1))
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
    //   300          MORPH MASTER (0…1)                ← reserved-only (NON-functional; A/B morph removed from render)
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
                guard !self.document.scenes.isEmpty else { break }   // K3: never subscript an empty scenes array (host automation before a scene exists)
                let all = StepRate.allCases
                self.document.scenes[self.document.activeSceneResolved].stepRate = all[min(all.count - 1, max(0, Int(value)))]
            case ParamAddress.swing:
                guard !self.document.scenes.isEmpty else { break }   // K3
                self.document.scenes[self.document.activeSceneResolved].swing = Int(value)
            case ParamAddress.morphMaster:
                self.document.morphMaster = Double(value)
            case let a where a >= 200 && a < 200 + AUParameterAddress(colourIDs.count):
                let idx = Int(a - 200); if idx < self.document.colours.count { self.document.colours[idx].morph = Double(value) }   // CR-13b: a decoded doc may have <16 colours
            case let a where a >= 100 && a < 100 + AUParameterAddress(colourIDs.count):
                let idx = Int(a - 100); if idx < self.document.colours.count { self.document.colours[idx].transpose = Int(value) }
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
            case ParamAddress.morphMaster: return AUValue(self.document.morphMasterResolved)
            case let a where a >= 200 && a < 200 + AUParameterAddress(colourIDs.count):
                let idx = Int(a - 200); return idx < self.document.colours.count ? AUValue(self.document.colours[idx].morph) : 0   // CR-13b: <16-colour doc guard
            case let a where a >= 100 && a < 100 + AUParameterAddress(colourIDs.count):
                let idx = Int(a - 100); return idx < self.document.colours.count ? AUValue(self.document.colours[idx].transpose) : 0
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
        clearPendingBuild()                        // K2: the test doc carries its own BUILD state — drop stale pending
        loadedTestSession = session.id

        // Tree writes re-enter implementorValueObserver (each calling scheduleRebuild), so
        // suppress and publish exactly one snapshot at the end.
        suppressRebuild = true
        syncParameterTreeToDocument()
        suppressRebuild = false
        scheduleRebuild()
    }

    /// Load a factory scene (Docs/factory-scenes.md) — same replace-and-resync path as a test session.

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
        [("INIT", PluginState.makeInit), ("ARC", PluginState.defaultArc),
         ("THE LADDER", PluginState.makeLadder), ("TIDE", PluginState.makeLadderTide),
         ("FORGE", PluginState.makeLadderForge), ("CHIME", PluginState.makeLadderChime),
         ("SPARK", PluginState.makeLadderSpark), ("DELAYS", PluginState.makeDelays)] + SceneFactory.scenes.map { s in (s.name, s.make) }
    func factoryPresetNames() -> [String] { Self.factoryPresetBuilders.map { $0.name } }
    /// Apply a factory preset's document — one undoable step + voice flush (from a builder, not a file). No KVO.
    private func applyFactoryDocument(named name: String) {
        guard let fp = Self.factoryPresetBuilders.first(where: { $0.name == name }) else { return }
        kernel.flushVoices()
        editDocument { $0 = fp.make(); $0.migrateLegacyRoutingIfNeeded() }   // migrate is a no-op for v4 builders
        clearPendingBuild()   // K2: the new doc carries its own BUILD state — drop the outgoing session's stale pending
        currentPresetName = name
        seedLatchArm()                                       // restore the persisted door-arm intent
        suppressRebuild = true; syncParameterTreeToDocument(); suppressRebuild = false; scheduleRebuild()   // CR-7: mirror the loaded doc into the param tree (else host automation snaps a fresh note back to the OLD morph/transpose/macros)
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
        editDocument { $0 = doc }            // one undoable step
        clearPendingBuild()                  // K2: drop the outgoing session's stale BUILD pending (the preset carries its own)
        currentPresetName = PresetStore.sanitize(name)
        seedLatchArm()                                       // restore the persisted door-arm intent
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
        let scene = document.activeSceneState
        _parameterTree.parameter(withAddress: ParamAddress.stepRate)?.value =
            AUValue(StepRate.allCases.firstIndex(of: scene.stepRate) ?? 2)
        _parameterTree.parameter(withAddress: ParamAddress.swing)?.value = AUValue(scene.swing)
        _parameterTree.parameter(withAddress: ParamAddress.morphMaster)?.value = AUValue(document.morphMasterResolved)
        for i in colourIDs.indices where i < document.colours.count {   // CR-13b: a decoded doc may carry <16 colours
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

    // BUILD pushes its single UNASSIGNED workshop part here (via setBuildUnassigned) so `fullState` saves it with the
    // document. Session-only side-field — the stored `document` is never mutated by it (the encode copy carries it).
    private var pendingBuildUnassigned: BuildUnassignedData? = nil
    func setBuildUnassigned(_ d: BuildUnassignedData?) { pendingBuildUnassigned = d }
    /// On load, hand BUILD the restored part ONCE (then clear it from the document so it isn't re-restored).
    func consumeBuildUnassigned() -> BuildUnassignedData? {
        let u = document.buildUnassigned
        if u != nil { document.buildUnassigned = nil }   // not render-relevant → no rebuild; a plain one-shot transport
        return u
    }
    // SCENES V2 (Paul 2026-08-24): the DEPLOYED play-grid arrangements travel with the save, like the unassigned part.
    private var pendingBuildScenes: [BuildSceneSnapshot]? = nil
    private var pendingBuildScenesActive: Int? = nil
    func setBuildScenes(_ scenes: [BuildSceneSnapshot]?, active: Int) { pendingBuildScenes = scenes; pendingBuildScenesActive = active }
    /// On load, hand BUILD the restored scenes ONCE (then clear them so they aren't re-restored).
    func consumeBuildScenes() -> (scenes: [BuildSceneSnapshot], active: Int)? {
        guard let s = document.buildScenes, !s.isEmpty else { return nil }
        let a = document.buildScenesActive ?? 0
        document.buildScenes = nil; document.buildScenesActive = nil   // one-shot; not render-relevant
        return (s, a)
    }
    // THE ROOMS PLAY GRID (Paul 2026-08-30): the play columns + their multi-step passes travel with the save.
    private var pendingBuildPlayGrid: BuildPlayGridData? = nil
    func setBuildPlayGrid(_ d: BuildPlayGridData?) { pendingBuildPlayGrid = d }
    /// Drop the OUTGOING session's stale BUILD pending fields on every load — the loaded doc carries its OWN (restored
    /// via consume*), so the next save doesn't re-encode the previous session's part/scenes/play grid over the new one
    /// (K2/CR-10, 2026-08-30: was applied only in `fullState.set`; the factory/preset/test load paths leaked pending).
    private func clearPendingBuild() { pendingBuildUnassigned = nil; pendingBuildScenes = nil; pendingBuildScenesActive = nil; pendingBuildPlayGrid = nil; pendingPartAuto = nil }
    /// On load, hand BUILD the restored play grid ONCE (then clear it so it isn't re-restored).
    func consumeBuildPlayGrid() -> BuildPlayGridData? {
        let d = document.buildPlayGrid
        if d != nil { document.buildPlayGrid = nil }   // not render-relevant → no rebuild; a one-shot transport
        return d
    }
    // PART AUTOMATION (Paul 2026-09-02): the per-colour AUTO lanes travel with the save. Baked at BUILD time (composeScene),
    // so it's not render-relevant — a plain pending/consume transport like the play grid (no rebuild).
    private var pendingPartAuto: [String: PartAutoColour]? = nil
    func setPartAuto(_ d: [String: PartAutoColour]?) { pendingPartAuto = d }
    func consumePartAuto() -> [String: PartAutoColour]? {
        let d = document.partAuto
        if d != nil { document.partAuto = nil }
        return d
    }

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
                document = doc
                clearPendingBuild()   // CR-10/K2: the loaded doc carries its OWN BUILD state (via consume*) — drop the outgoing session's stale pending so the next save doesn't re-encode it over the restored doc
                kernel.flushVoices()                 // audit B3: flush like every other load path — a mid-play host
                                                     // session restore must not strand the outgoing document's voices
                seedLatchArm()                       // restore the persisted door-arm intent (Paul 2026-08-27)
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

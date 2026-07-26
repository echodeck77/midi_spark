//  AudioUnitViewController.swift
//  Extension principal class + the diagnostic panel (temporary UI for bridge debugging).

import CoreAudioKit
import SwiftUI

public class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: MidiSparkAudioUnit?

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let au = try MidiSparkAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = au
        DispatchQueue.main.async { [weak self] in self?.embedUI() }
        return au
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 760, height: 480)
        if audioUnit != nil { embedUI() }
    }

    private func embedUI() {
        guard children.isEmpty else { return }
        let host = UIHostingController(rootView: DiagView(au: audioUnit))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// delta item 8: a lifted processor on the clipboard — {type, params, transpose} — COPY'd from one panel,
/// PASTE'able onto any other (A or B, any Colour); a different type retypes the target.
struct ProcClip { let type: ProcessorType; let params: ColourParams; let transpose: Int }

/// Live diagnostics: what the kernel is actually seeing, at 4 Hz.
/// Interpreting it:
///  · PARAM EVENTS rising while you turn a mapped knob → host uses render-side events (kernel handles).
///  · TREE morph moving but PARAM EVENTS static → host uses setValue (observer/snapshot path).
///  · Neither moving → the mapping isn't reaching this instance (host-side routing).
///  · CC IN rising → raw CC arrives at the MIDI input (and is passed through on A).
struct DiagView: View {
    weak var au: MidiSparkAudioUnit?
    @State private var d = KernelDiag()      // polled for the grid's effColumn / playing
    @State private var loadedID = "—"
    @State private var scene = SceneState.empty()
    @State private var brush = "gold"        // the paint Colour (view-local; never in the document)
    @State private var selCol = -1
    @State private var selRow = -1
    @State private var busChannels: [Int] = [1, 2, 3, 4]
    @State private var busEnabled: [Bool] = [true, true, true, true]   // delta §6a
    @State private var claim: Int? = nil                              // delta §6a CLAIM (a7): the exclusive emitter
    @State private var thruReceiver: Int = 0                          // receiver strip: the THRU pip (passthrough source)
    @State private var soloReceiverMask: UInt8 = 0                    // receiver strip: additive input SOLO set (ephemeral)
    @State private var receiverOctave: [Int] = [0, 0, 0, 0]          // receiver strip: per-receiver ±octave nudge (ephemeral)
    @State private var procClipboard: ProcClip? = nil   // delta item 8: a lifted processor (COPY) to PASTE onto any panel
    // Cell-edit STAGING (user 2026-07-25): long-press a Colour → the receivers/emitters panels configure a
    // PENDING cell (input source + output buses). `stagedConfig` is ephemeral and RECALLED across enter/exit;
    // only the colour is set fresh by whichever chip is long-pressed. The drag-to-grid + live preview is
    // DEFERRED to the design spec — this scaffold is EDIT-only panel staging.
    @State private var staging = false
    @State private var stagedConfig = StampConfig(colourID: "gold")
    @State private var cellPreview = false      // the CELL box PREVIEW toggle (Phase 1: UI state; engine routing = Phase 2)
    // Hide-with-undo: a single tap HIDES a cell (muted, recoverable) and rings it in its own colour;
    // re-tapping restores it; touching ANY other cell COMMITS the deletion (nil = none).
    @State private var hiddenPending: GridView.GridPos? = nil
    // Live PREVIEW while dragging a staged cell over the grid: the staged cell is transiently placed at the
    // hovered position via the NON-undoable edit path, so it sounds IN CONTEXT (the LIVE LAW does the voice
    // transitions). `previewPos` = where it's placed; `previewUnder` = the cell it displaced (restored on
    // move-away / cancel). Never persisted, never recorded for undo. Committed for real only on DROP.
    @State private var previewPos: GridView.GridPos? = nil
    @State private var previewUnder: Cell? = nil
    // The cells PLACED during the current staging session — they pulse colour↔black (like their palette
    // chip), gate the empty-cell flash (empties only invite once ≥1 is placed), and are the "selected
    // cells" that live-reflect receiver/emitter edits. Cleared on enter/retarget/exit. View-local.
    @State private var stagedCells: Set<GridView.GridPos> = []
    // Hide-with-undo (user 2026-07-25): a single tap HIDES a cell (muted, recoverable) and marks it with a
    // ring in its own colour; re-tapping restores it; touching ANY other cell COMMITS the deletion. This is
    // the just-hidden cell in its undo window (nil = none).
    @State private var holdLatch = false             // delta §5c: HOLD — the sustain pedal for gestures (PERFORM)
    // §5 palette-to-grid drag: the grid's captured global frame, the in-flight chip drag, and the set of
    // provisional (palette-created, unreviewed) cells shown FADED until first opened in the editor.
    @State private var gridFrame: CGRect = .zero
    @State private var paletteDragColour: String? = nil
    @State private var paletteDragPoint: CGPoint? = nil
    @State private var emitPeak: [Double] = [0, 0, 0, 0]               // §6a meter: latched peak (0–1) per emitter
    @State private var emitPeakAt: [Date] = Array(repeating: .distantPast, count: 4)   // when each peak latched (for decay)
    @State private var receiverPeak: [Double] = [0, 0, 0, 0]           // §9 item 11 input meter: latched peak per receiver
    @State private var receiverPeakAt: [Date] = Array(repeating: .distantPast, count: 4)
    @State private var docColours: [Colour] = []
    @State private var receivers: [Receiver] = []                     // delta §9 item 11: the RECEIVERS panel
    @State private var stepIndex = 2
    @State private var swing = 50
    @State private var editing = true          // EDIT vs PERFORM (§6.1/6.2)
    @State private var flowVariation = 0       // FLOW view (item 10): 0 = grid; 1…5 cycle the visualisations
    @State private var laneMask: UInt8 = 0     // §5b lap: held column keys (bit i = column i), PERFORM only
    @State private var tapAltMask: UInt64 = 0  // §9 item 1 ON TAP (unified ALT): ephemeral per-cell alt flips
    @State private var tapMuteMask: UInt64 = 0 // §9 item 1 ON TAP = MUTE: ephemeral per-cell mute
    @State private var soloEmitterMask: UInt8 = 0  // §9 item 1 ON TAP = SOLO EMITTERS: the emitter solo set
    // §9 item 1 ON TAP quant/duration (4c): active TIMED actions. A tap adds one (onset from tapWhen, expiry
    // from tapFor); each poll derives the three ephemeral masks from the actions that are live at the beat.
    private enum TapKind { case alt, mute, solo }
    private struct TapAction { let cell: Int; let kind: TapKind; let busMask: UInt8; let onset: Double; let expiry: Double }
    @State private var tapActions: [TapAction] = []
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    // §5b COLUMN-SUBSET LAP: the PERFORM multi-column hold reports the held-set bitmask here. Push it to
    // the engine (ephemeral, never persisted) and keep a copy for the key LOOP highlight. Cleared to 0
    // on release (the overlay reports empty) and on the EDIT switch (see the mode toggle).
    private func setLane(_ mask: UInt8) { laneMask = mask; au?.setLaneMask(mask) }

    // EDIT/PERFORM toggle. Leaving PERFORM ends any lap (belt-and-suspenders — the overlay also cancels).
    private func toggleMode() { commitHiddenPending(); editing.toggle(); if editing { setLane(0); setHold(false); clearOnTap() } else { exitStaging() } }   // §5c: HOLD PERFORM-only; staging + ON-TAP overlays EDIT-clears

    // §9 item 1 ON TAP: clear every ephemeral perform-tap overlay (timed actions + alt flips, mutes, emitter solo).
    private func clearOnTap() {
        if !tapActions.isEmpty { tapActions.removeAll() }
        if tapAltMask != 0 { tapAltMask = 0; au?.setTapAltMask(0) }
        if tapMuteMask != 0 { tapMuteMask = 0; au?.setTapMuteMask(0) }
        if soloEmitterMask != 0 { soloEmitterMask = 0; au?.setSoloEmitterMask(0) }
    }

    // Close the hide-undo window: the recently-hidden cell is DELETED for good (recorded for undo).
    private func commitHiddenPending() {
        guard let au, let hp = hiddenPending else { return }
        au.editScene { $0.cells[hp.col][hp.row] = nil }
        hiddenPending = nil; scene = au.uiScene()
    }

    // Cell-edit STAGING (user 2026-07-25) — long-press a Colour opens the staging mode; the receivers/
    // emitters panels reconfigure `stagedConfig` (input source + output buses). Ephemeral, recalled.
    // Long-press a Colour (from EITHER mode) OR tap a Colour while staging → stage a cell of that Colour.
    // Forces EDIT on so it's always possible to re-enter after a drop drops us into PERFORM (bug fix
    // 2026-07-25); tapping a different chip while staging shifts focus to that Colour (same entry point).
    private func enterStaging(_ id: String) {
        commitHiddenPending()                       // moving into cell-edit closes any open hide-undo window
        stagedConfig.colourID = id; brush = id      // set/retarget the staged colour + reflect it in the desk
        stagedCells = []                            // fresh session (also on retarget): nothing placed yet
        editing = true                              // long-press always brings us into EDIT + staging
        staging = true
    }

    // Long-press a GRID CELL in EDIT → enter cell-edit for it: adopt its config as the staged config and
    // make it a FLASHING cell (exactly the dropped-in-staging state). An empty cell stages the brush + a
    // fresh flashing cell there. From here it behaves like any staging session (place more / recolour / commit).
    private func enterStagingForCell(_ col: Int, _ row: Int) {
        guard let au, editing else { return }
        commitHiddenPending()                       // long-pressing to stage closes any open hide-undo window
        let pos = GridView.GridPos(col: col, row: row)
        if let cell = scene.cells[col][row] {
            stagedConfig = StampConfig.from(cell); brush = cell.colourID     // adopt the cell's colour + routing
        } else {
            stagedConfig.colourID = brush                                    // empty: stage the brush, place a fresh cell
            au.editScene { $0.cells[col][row] = stagedConfig.makeCell() }
        }
        stagedCells = [pos]                                                  // this cell flashes + tracks staged edits
        editing = true; staging = true
        scene = au.uiScene(); docColours = au.uiColours()
    }

    // The staging accent = the SELECTED Colour's own hue (the moving outline follows it), cyan as fallback.
    private var stagingColor: Color { colourColor(stagedConfig.colourID) ?? Color(red: 0.15, green: 0.88, blue: 0.94) }

    private func exitStaging() {
        clearPreview(); staging = false; stagedCells = []
        setHold(false); cellPreview = false; au?.clearPreview()   // drop any latched cell preview + the HOLD
    }

    // Selecting a DIFFERENT Colour while staging recolours every FLASHING cell to it (keeping their staged
    // routing) and stages that Colour going forward — the flashing set persists, it does not reset.
    private func recolorStaged(_ id: String) {
        guard let au else { return }
        stagedConfig.colourID = id; brush = id
        if !stagedCells.isEmpty {
            au.editScene { s in
                for p in stagedCells {
                    guard var c = s.cells[p.col][p.row] else { continue }
                    c.colourID = id
                    s.cells[p.col][p.row] = c
                }
            }
            scene = au.uiScene(); docColours = au.uiColours()
        }
    }

    // A receiver/emitter edit while staging live-updates every cell placed this session (the "selected
    // cells") — input source + output buses; the staged Colour is unchanged within a session.
    private func applyStagedToPlaced() {
        guard let au, !stagedCells.isEmpty else { return }
        au.editScene { s in
            for p in stagedCells {
                guard var c = s.cells[p.col][p.row] else { continue }
                stagedConfig.applyRouting(to: &c)
                s.cells[p.col][p.row] = c
            }
        }
        scene = au.uiScene(); docColours = au.uiColours()
    }

    // Live preview: move the transient staged cell to the hovered grid cell (or clear it off-grid). Restores
    // whatever it displaces before moving, so the arrangement is never permanently altered until DROP.
    private func updatePreview(_ point: CGPoint) {
        guard let au, staging else { return }
        let hover = cellAtGlobal(point)
        if hover == previewPos { return }                     // same cell → nothing to do
        if let pp = previewPos { au.editScene(record: false) { $0.cells[pp.col][pp.row] = previewUnder } }  // restore prior
        if let h = hover {
            let fresh = au.uiScene()
            previewUnder = fresh.cells[h.col][h.row]           // remember what we're covering
            let cell = stagedConfig.makeCell()                 // the staged cell (input + emitters + colour)
            au.editScene(record: false) { $0.cells[h.col][h.row] = cell }
            au.setPreviewOverlay(col: h.col, row: h.row, under: previewUnder)   // fullState strips this
            previewPos = h
        } else {
            previewPos = nil; previewUnder = nil; au.clearPreviewOverlay()
        }
        scene = au.uiScene()
    }
    // Remove any live preview, restoring the cell it displaced. No-op if nothing is previewing.
    private func clearPreview() {
        guard let au, let pp = previewPos else { return }
        au.editScene(record: false) { $0.cells[pp.col][pp.row] = previewUnder }
        previewPos = nil; previewUnder = nil; au.clearPreviewOverlay()
        scene = au.uiScene()
    }
    private func setStagedReceiver(_ i: Int) { stagedConfig.inputRow = nil; stagedConfig.inputReceiver = max(0, min(3, i)); applyStagedToPlaced() }
    private func pickStagedRow() { stagedConfig.inputRow = stagedConfig.inputRow ?? 0; applyStagedToPlaced() }   // select FROM ROW (default row 1)
    private func stepStagedRow(_ delta: Int) {
        let cur = stagedConfig.inputRow ?? 0
        stagedConfig.inputRow = ((cur + delta) % 8 + 8) % 8
        applyStagedToPlaced()
    }
    private func toggleStagedBus(_ i: Int) {
        let bus = Bus.allCases[i]
        if stagedConfig.buses.contains(bus) { stagedConfig.buses.remove(bus) } else { stagedConfig.buses.insert(bus) }
        applyStagedToPlaced()
    }

    // Tap a cell. EDIT (user 2026-07-26): while STAGING, tapping any populated/flashing cell COMMITS the
    // flashing set and tapping an empty cell PLACES another staged cell. NOT staging → HIDE-with-undo:
    // tap a visible cell to hide it (recoverable), re-tap to restore, touch another cell to commit the
    // deletion. (Long-press, not tap, puts a cell into cell-edit.) PERFORM: flip ALT.
    private func tapCell(_ col: Int, _ row: Int) {
        guard let au else { return }
        if editing {
            let pos = GridView.GridPos(col: col, row: row)
            if staging {
                if scene.cells[col][row] == nil {            // EMPTY → place another staged (flashing) cell
                    au.editScene { $0.cells[col][row] = stagedConfig.makeCell() }
                    stagedCells.insert(pos)
                    selCol = col; selRow = row; scene = au.uiScene(); docColours = au.uiColours()
                } else {                                     // POPULATED (flashing or other) → commit the flashing set + leave cell-edit
                    exitStaging()
                }
                return
            }
            if hiddenPending == pos {                        // re-tap the recently-hidden cell → restore
                au.editScene { s in if var c = s.cells[col][row] { c.muted = false; s.cells[col][row] = c } }
                hiddenPending = nil; selCol = col; selRow = row; scene = au.uiScene()
                return
            }
            commitHiddenPending()                           // touched a different cell → delete the prior pending-hidden one
            if scene.cells[col][row] != nil {               // a visible populated cell → hide it (recoverable)
                au.editScene { s in if var c = s.cells[col][row] { c.muted = true; s.cells[col][row] = c } }
                hiddenPending = pos
            }
            selCol = col; selRow = row; scene = au.uiScene()
        } else {
            // §9 item 1 ON TAP (4b/4c): a PERFORM tap runs the Colour's ON TAP action as a TIMED, EPHEMERAL
            // overlay — onset from tapWhen (NOW/STEP/PASS/LAP), expiry from tapFor (RETAP toggle / 1-PASS /
            // 1-LAP). Never a document write; cleared on transport stop / EDIT switch. FILL/REPLAY await design.
            guard let c = scene.cells[col][row] else { return }
            let on = docColours.first { $0.colourID == c.colourID }?.onResolved ?? OnConfig()
            let kind: TapKind
            switch on.tap {
            case .mute:        kind = .mute
            case .solo:        kind = .solo
            case .alt, .none:  kind = .alt
            case .fill, .replay: return                       // not yet wired (design clarification pending)
            }
            let idx = col * 8 + row
            var buses: UInt8 = 0
            for b in c.buses { if let i = Bus.allCases.firstIndex(of: b) { buses |= (1 << UInt8(i)) } }
            let onset = tapOnsetBeat(tapBeat: d.beat, quant: on.tapWhen, stepBeats: stepBeats)
            let expiry = tapExpiryBeat(onsetBeat: onset, duration: on.tapFor, stepBeats: stepBeats)
            if on.tapFor == .retap, let i = tapActions.firstIndex(where: { $0.cell == idx && $0.kind == kind }) {
                tapActions.remove(at: i)                       // RETAP: a second tap toggles it off
            } else {
                tapActions.removeAll { $0.cell == idx && $0.kind == kind }   // re-tap replaces any prior for this cell/action
                tapActions.append(TapAction(cell: idx, kind: kind, busMask: buses, onset: onset, expiry: expiry))
            }
            refreshTapMasks()
        }
    }

    // §9 item 1 ON TAP (4c): derive the three ephemeral masks from the actions live at the current beat —
    // pruning expired ones. Runs on tap AND each poll (so onsets fire + durations expire). Dedup-guarded.
    private func refreshTapMasks() {
        let now = d.beat
        if tapActions.contains(where: { now >= $0.expiry }) { tapActions.removeAll { now >= $0.expiry } }  // only mutate @State on real expiry
        var alt: UInt64 = 0, mute: UInt64 = 0, solo: UInt8 = 0
        for a in tapActions where a.onset <= now {
            switch a.kind {
            case .alt:  alt  |= 1 << UInt64(a.cell)
            case .mute: mute |= 1 << UInt64(a.cell)
            case .solo: solo |= a.busMask
            }
        }
        if alt  != tapAltMask     { tapAltMask = alt;      au?.setTapAltMask(alt) }
        if mute != tapMuteMask    { tapMuteMask = mute;    au?.setTapMuteMask(mute) }
        if solo != soloEmitterMask { soloEmitterMask = solo; au?.setSoloEmitterMask(solo) }
    }

    // Cell-edit STAGING banner (user 2026-07-25) — the mode indicator + DONE exit. Cyan to match the
    // marching-ants outline on the repurposed panels. (Drag-to-grid hand-off is deferred to the spec.)
    private var stagingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.dashed").font(.system(size: 11, weight: .heavy))
            if let c = colourColor(brush) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12) }
            Text("STAGING \(stagedConfig.colourID.uppercased()) — drag or tap empty cells to place · tap its chip to exit")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
            Spacer()
            Text("DONE").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.35)))
                .contentShape(Rectangle()).onTapGesture { exitStaging() }
        }
        .foregroundColor(.black)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color(red: 0.15, green: 0.88, blue: 0.94))
    }

    // Relocate a cell (user 2026-07-26): long-press then drag → MOVE it to the target, OVERWRITING even a
    // populated cell; the source empties. Undoable. If the moved cell was flashing, its flash follows it.
    private func moveCell(_ from: (col: Int, row: Int), _ to: (col: Int, row: Int)) {
        guard let au, from.col != to.col || from.row != to.row else { return }
        au.editScene { s in
            s.cells[to.col][to.row] = s.cells[from.col][from.row]   // overwrite the target
            s.cells[from.col][from.row] = nil                        // source empties
        }
        let f = GridView.GridPos(col: from.col, row: from.row), t = GridView.GridPos(col: to.col, row: to.row)
        if stagedCells.remove(f) != nil { stagedCells.insert(t) }    // the flash moves with the cell
        scene = au.uiScene()
    }

    // §5 palette-to-grid: map a GLOBAL drop point to a grid cell (cell height derived from the captured
    // grid frame), then RECOLOUR a populated cell or CREATE a faded one on empty. EDIT only.
    private func cellAtGlobal(_ p: CGPoint) -> GridView.GridPos? {
        guard gridFrame.width > 0, gridFrame.height > 0 else { return nil }
        let local = CGPoint(x: p.x - gridFrame.minX, y: p.y - gridFrame.minY)
        let cellH = (gridFrame.height - GridGeometry.headH - 8 * GridGeometry.vGap) / 8
        return GridGeometry.cell(atLocal: local, gridWidth: gridFrame.width, cellHeight: cellH)
            .map { GridView.GridPos(col: $0.col, row: $0.row) }
    }
    private func paletteDragChanged(_ id: String, _ point: CGPoint) {
        guard editing else { return }                 // EDIT-only
        if !staging { enterStaging(id) }              // a QUICK drag enters cell-edit for this colour (unifies with long-press+drag)
        paletteDragColour = id; paletteDragPoint = point
        updatePreview(point)                          // staging now true → live-preview the staged cell at the hover
    }
    // Cell-edit staging: a chip drag is in flight while staging → the moving outline hands off to the grid.
    private var stagingDragging: Bool { staging && paletteDragPoint != nil }

    // A palette drop is ALWAYS a staging drop now (the drag entered staging above): clear the preview, then
    // commit the flashing cell. No faded/ghost path — quick-drag and long-press+drag both stage.
    private func paletteDrop(_ id: String, _ point: CGPoint) {
        defer { paletteDragColour = nil; paletteDragPoint = nil }
        guard let au, staging else { return }
        clearPreview()                                // remove the transient placement (restores what it covered)
        if editing, let pos = cellAtGlobal(point) {
            var c = stagedConfig.makeCell(); c.colourID = id     // staged input + emitters, colour from the chip
            au.editScene { $0.cells[pos.col][pos.row] = c }      // recorded for undo
            stagedCells.insert(pos)                             // a placed FLASHING cell: pulses + tracks staged edits
            brush = id; scene = au.uiScene(); docColours = au.uiColours()
            // STAY in cell-edit: empty cells now pulse; tap them / drag again to place more; tap a flashing cell to commit.
        } else {
            scene = au.uiScene()                      // dropped off-grid → preview cleared, stay in staging
        }
    }

    // delta §5c: HOLD LATCH — while ON, releases latch instead of springing; HOLD-off is the synchronous
    // "drop" (every captured gesture releases at once). PERFORM-only; cleared on transport stop / EDIT.
    // v1 captures: §6a velocity overrides (in OutputsView) + audition (below). Lap + ON-HOLD deferred.
    private func setHold(_ on: Bool) {
        guard holdLatch != on else { return }
        holdLatch = on
        if !on {                                 // the drop: release the captures this layer owns
            au?.clearAudition(); abox.target = nil
            au?.setHoldCell(-1); abox.held = false          // §9 item 1: a latched ON HOLD drops too
            au?.setLaneMask(0); laneMask = 0     // §5c: the latched lap set drops too (velocity springs
                                                 // back via OutputsView's onChange(holdLatch))
            if cellPreview { cellPreview = false; au?.clearPreview() }   // §5c: a latched cell PREVIEW drops too
        }
    }
    private func toggleHold() { setHold(!holdLatch) }

    // delta §5 / a6: undo/redo restore the WHOLE document, so refresh every document-derived @State.
    private func undo() { if au?.uiUndo() == true { refreshFromDocument() } }
    private func redo() { if au?.uiRedo() == true { refreshFromDocument() } }
    private func refreshFromDocument() {
        guard let au else { return }
        scene = au.uiScene()
        docColours = au.uiColours()
        busChannels = au.uiBusChannels()
        busEnabled = au.uiBusEnabled()
        claim = au.uiClaim()
        thruReceiver = au.uiThruReceiver()
    }

    // AUDITION (§6.4 / delta §5): press-hold a cell (stopped) → hear its processor alone. The held
    // target lives in a REFERENCE box mutated SILENTLY (never @State) so starting/stopping an audition
    // never re-renders the grid mid-press (which would tear down the long-press gesture). The deduped
    // poll above does the rest — when stopped the grid is quiescent, so the gesture is never disturbed.
    final class AuditionBox { var target: (col: Int, row: Int)? = nil; var held = false }
    @State private var abox = AuditionBox()

    // PERFORM press-hold. STOPPED → AUDITION (the cell alone). PLAYING → ON HOLD (§9 item 1): the cell's ON
    // HOLD treatment overlays while held. Both are kernel-only (no @State / re-render, like the audition path).
    private func startAudition(_ col: Int, _ row: Int) {
        guard let au, scene.cells[col][row] != nil else { return }
        if d.playing {
            au.setHoldCell(col * 8 + row); abox.held = true          // ON HOLD overlay (idempotent per onChanged)
            return
        }
        if abox.target?.col == col && abox.target?.row == row { return }
        abox.target = (col, row)
        au.setAudition(col: col, row: row)
    }
    private func endAudition() {                                     // release (SPRING); §5c-HOLD latch keeps it (see setHold)
        if abox.held { au?.setHoldCell(-1); abox.held = false }
        guard au != nil, abox.target != nil else { return }
        abox.target = nil
        au?.clearAudition()
    }

    // ---- PROCESSOR box: edit the selected (brush) Colour ----
    private var brushIndex: Int { colourIDs.firstIndex(of: brush) ?? 0 }
    private var brushColour: Colour? { docColours.first { $0.colourID == brush } }
    // delta item 8: does the brush Colour's procB GLIDE? (has B + same type as A = FULL). Gates the morph fader.
    private var brushGlides: Bool {
        guard let c = brushColour, let tb = c.typeB else { return false }
        return tb == c.type
    }
    // ON-section greying input (staged Colour = brush during staging): has a second processor (procB).
    private var stagedAltPaired: Bool { brushColour?.hasProcB ?? false }
    private var stagedStochastic: Bool {
        guard let c = brushColour else { return false }
        return c.type == .chance || (c.type == .arp && c.paramsA.pattern == .random)
    }
    // Write the staged Colour's ON config; per-Colour so it propagates to the whole flashing set, undo-covered.
    private func editStagedOn(_ mutate: @escaping (inout OnConfig) -> Void) {
        guard let au else { return }
        au.editColour(brushIndex) { c in var on = c.on ?? OnConfig(); mutate(&on); c.on = on }
        docColours = au.uiColours()
    }

    private func editBrushColour(_ f: @escaping (inout Colour) -> Void) {
        guard let au else { return }
        au.editColour(brushIndex, f)
        docColours = au.uiColours()
    }
    private func setBrushTranspose(_ v: Int) { au?.setColourTranspose(brushIndex, v); docColours = au?.uiColours() ?? docColours }
    private func setBrushMorph(_ v: Double)  { au?.setColourMorph(brushIndex, v);     docColours = au?.uiColours() ?? docColours }
    private func setBrushType(_ t: ProcessorType) { au?.setColourType(brushIndex, t); docColours = au?.uiColours() ?? docColours }

    // delta item 8: the processor CLIPBOARD — COPY lifts a face's {type, params, transpose}; PASTE drops it
    // onto ANY panel (A or B, any Colour), retyping the target if the clipboard is a different type.
    private func copyProc(_ face: ProcessorBox.Face) {
        guard let c = brushColour else { return }
        if face == .b {
            guard let tb = c.typeB else { return }                       // nothing to copy from a B-less panel
            procClipboard = ProcClip(type: tb, params: c.paramsB, transpose: c.transposeBResolved)
        } else {
            procClipboard = ProcClip(type: c.type, params: c.paramsA, transpose: c.transpose)
        }
    }
    private func pasteProc(_ face: ProcessorBox.Face) {
        guard let clip = procClipboard else { return }
        if face == .b {
            editBrushColour { $0.typeB = clip.type; $0.paramsB = clip.params; $0.transposeB = clip.transpose }
        } else {
            au?.setColourType(brushIndex, clip.type)                     // switchType (per-type stash) + tree sync
            au?.setColourTranspose(brushIndex, clip.transpose)
            editBrushColour { $0.paramsA = clip.params }                 // refreshes docColours
        }
    }
    private func refreshTiming() { stepIndex = au?.uiStepRateIndex() ?? stepIndex; swing = au?.uiSwing() ?? swing }
    private var stepBeats: Double { StepRate.allCases[min(stepIndex, StepRate.allCases.count - 1)].beats }

    // EMITTERS (delta §6a): toggle emitter i on/off; set its stamp channel (from the EDIT popover).
    private func toggleEmitter(_ i: Int) {
        guard let au else { return }
        au.setBusEnabled(i, !(i < busEnabled.count ? busEnabled[i] : true))
        busEnabled = au.uiBusEnabled()
    }
    // §6a PERFORM velocity override: while a fader is touched, force emitter i to `v` (1–127); nil on
    // release springs it back to natural velocity. Ephemeral — nothing is written to the document.
    private func setVelOverride(_ i: Int, _ v: Int?) {
        au?.setVelOverride(i, v)
    }
    // delta §9 item 11: RECEIVERS panel edits — channel filter / input cable / input mute (undoable doc edits).
    // MPE is silent auto-detect (user ruling 2026-07-25) — no control.
    private func setReceiverChannel(_ i: Int, _ ch: Int) { au?.setReceiverChannel(i, ch); receivers = au?.uiReceivers() ?? receivers }
    private func setReceiverCable(_ i: Int, _ mask: Int?) { au?.setReceiverCable(i, mask); receivers = au?.uiReceivers() ?? receivers }
    private func toggleReceiverMute(_ i: Int) { au?.toggleReceiverMute(i); receivers = au?.uiReceivers() ?? receivers }
    private func setThru(_ i: Int) { au?.setThruReceiver(i); thruReceiver = au?.uiThruReceiver() ?? thruReceiver }
    // receiver strip: additive SOLO (toggle a receiver in/out of the set). Ephemeral weather — the engine
    // gate is `audible = ¬muted ∧ (soloSet=∅ ∨ member)`; the whole set clears on transport stop.
    private func toggleReceiverSolo(_ i: Int) {
        guard (0..<4).contains(i) else { return }
        soloReceiverMask ^= UInt8(1 << i)
        au?.setSoloReceiverMask(soloReceiverMask)
    }
    // receiver strip: ±octave nudge (±1 per tap, clamp ±3). Ephemeral, composes with the colour transpose.
    private func nudgeReceiverOctave(_ i: Int, _ delta: Int) {
        guard (0..<4).contains(i) else { return }
        receiverOctave[i] = max(-3, min(3, receiverOctave[i] + delta))
        au?.setInputOctave(i, receiverOctave[i])
    }
    // receiver strip: the slider's momentary input-velocity override (touch = absolute, release = nil → spring).
    private func setReceiverVel(_ i: Int, _ value: Int?) { au?.setInputVelOverride(i, value) }
    /// Clear the receiver-strip PERFORM overlays (weather) — fired on the transport play→stop edge.
    private func clearReceiverPerform() {
        soloReceiverMask = 0; au?.setSoloReceiverMask(0)
        receiverOctave = [0, 0, 0, 0]; for i in 0..<4 { au?.setInputOctave(i, 0); au?.setInputVelOverride(i, nil) }
    }

    // §6a CLAIM: tap an emitter's CLAIM radio → it becomes the sole claimant (releasing any prior);
    // tapping the current claimant clears the claim. Persisted (the AU toggles + rebuilds).
    private func setClaim(_ i: Int) {
        guard let au else { return }
        au.setClaim(i)
        claim = au.uiClaim()
        thruReceiver = au.uiThruReceiver()
    }
    private func setEmitterChannel(_ i: Int, _ ch: Int) {
        guard let au else { return }
        au.editDocument { d in
            while d.busChannels.count < 4 { d.busChannels.append(d.busChannels.count + 1) }
            d.busChannels[i] = max(1, min(16, ch))
        }
        busChannels = au.uiBusChannels()
    }

    private var selected: TestSessions.Session? { TestSessions.all.first { $0.id == loadedID } }
    private var sceneName: String {
        guard loadedID.hasPrefix("S"), let i = Int(loadedID.dropFirst()), i >= 1, i <= SceneFactory.scenes.count
        else { return "1–16 · the factory curriculum" }
        return SceneFactory.scenes[i - 1].name
    }

    private func load(_ s: TestSessions.Session) {
        au?.loadTestSession(s)          // main thread: SwiftUI actions already are
        loadedID = s.id
    }

    /// Build stamp = the extension binary's link time. Not a compile-date macro (Swift has none);
    /// the executable's mtime is written at link, so it answers the real question — "is AUM running
    /// THIS build, or a cached older one?" (README: AU registration caches aggressively).
    private static let buildStamp: String = {
        let bundle = Bundle(for: MidiSparkAudioUnit.self)
        let url = bundle.executableURL ?? bundle.bundleURL
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = .current
        return date.map(fmt.string(from:)) ?? "unknown"
    }()

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height       // aspect-driven breakpoint (delta §6)
            ZStack(alignment: .topLeading) {
                Color(red: 0.066, green: 0.075, blue: 0.094).ignoresSafeArea()
                if landscape {
                    // §6d TWO FLOWS: the layout IS the signal path — RECEIVERS band above → the (smaller) GRID
                    // → EMITTERS band below, grid-aligned, one vertical anatomy. The right column is the COLOUR
                    // flow (COLOUR→ALT→SELECTOR→SETTINGS). Cells shrink so the two bands flank the grid.
                    VStack(spacing: 8) {
                        header
                        sceneStrip                                   // below the header, above the signal flow
                        HStack(alignment: .top, spacing: 10) {
                            signalColumn(geo.size.width)             // RECEIVERS → GRID → EMITTERS (the signal flow)
                            ScrollView(.vertical, showsIndicators: false) { identityColumn }.frame(width: 320)
                        }
                    }
                    .padding(12)
                } else {
                    // §6d TWO FLOWS (portrait): the same signal-flow anatomy top-to-bottom — RECEIVERS above →
                    // (smaller) GRID → EMITTERS below — then the COLOUR flow (COLOUR/ALT · SELECTOR/SETTINGS,
                    // 2 columns), scene strip, dev loader. The colour band is sized for the inline SETTINGS panel.
                    VStack(spacing: 8) {
                        header
                        sceneStrip                             // below the header, above the signal flow
                        signalColumn(geo.size.width)           // RECEIVERS → GRID → EMITTERS (the signal flow)
                        colourFlowBand(geo.size.width - 24, 300)   // the treatment axis (24 = the .padding(12) both sides)
                    }
                    .padding(12)
                }
                if staging { VStack(spacing: 0) { stagingBanner; Spacer() } }
                // §5 palette-to-grid: a chip ghost following the finger (positioned in the GeometryReader's
                // local space = the global drag point minus the reader's global origin).
                if let id = paletteDragColour, let pt = paletteDragPoint {
                    let o = geo.frame(in: .global).origin
                    RoundedRectangle(cornerRadius: 4).fill(colourColor(id) ?? .gray)
                        .frame(width: 44, height: 22).opacity(0.85)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: 1))
                        .position(x: pt.x - o.x, y: pt.y - o.y)
                        .allowsHitTesting(false)
                }
                // (§6c popup dropped — processor SETTINGS are inline in the §6d layout; the floating window
                //  survives only as the future EXTERNAL AUv3-view host, added when EXTERNAL Colours arrive.)
            }
        }
        .onReceive(timer) { _ in
            guard let au else { return }
            // Write @State ONLY when a DISPLAYED value changed — an unconditional write re-renders the
            // whole grid every 0.25s (which used to tear down in-progress press-holds). When STOPPED
            // nothing here changes, so the grid is quiescent; while PLAYING only the playhead fields move.
            let nd = au.kernelDiagnostics()
            if d.playing && !nd.playing {                                 // §5c/§9: transport stop = the drop
                if holdLatch { setHold(false) }
                clearOnTap()                                              // ON TAP: momentary flips/mute/solo clear on stop
                clearReceiverPerform()                                    // receiver strip: SOLO (+ OCT/vel/latch) = weather
            }
            if nd.playing != d.playing || nd.tempo != d.tempo || nd.pass != d.pass
                || (nd.playing && (nd.beat != d.beat || nd.effColumn != d.effColumn)) { d = nd }
            let nb = au.uiBusChannels();   if nb != busChannels { busChannels = nb }
            let be = au.uiBusEnabled();    if be != busEnabled { busEnabled = be }
            let cl = au.uiClaim();         if cl != claim { claim = cl }
            let th = au.uiThruReceiver();  if th != thruReceiver { thruReceiver = th }
            // §6a metering: drain the per-emitter event feed and latch peaks; the meter view decays them.
            let act = au.pollEmitterActivity()
            for i in 0..<4 where i < act.events.count && act.events[i] > 0 {
                emitPeak[i] = Double(act.peak[i]) / 127.0; emitPeakAt[i] = Date()
            }
            let rin = au.pollReceiverActivity()      // §9 item 11: per-receiver INPUT metering
            for i in 0..<4 where i < rin.events.count && rin.events[i] > 0 {
                receiverPeak[i] = Double(rin.peak[i]) / 127.0; receiverPeakAt[i] = Date()
            }
            let nc = au.uiColours();       if nc != docColours { docColours = nc }
            let nr = au.uiReceivers();     if nr != receivers { receivers = nr }
            let ns = au.uiScene();         if ns != scene { scene = ns }
            if !tapActions.isEmpty { refreshTapMasks() }   // §9 ON TAP 4c: fire quantized onsets + expire durations
            let si = au.uiStepRateIndex(); if si != stepIndex { stepIndex = si }
            let sw = au.uiSwing();         if sw != swing { swing = sw }
        }
    }

    // MARK: - layout pieces

    private var header: some View {
        HeaderView(stepIndex: stepIndex, swing: swing, playing: d.playing, pass: d.pass,
                   beat: d.beat, tempo: d.tempo, build: Self.buildStamp,
                   editing: editing,
                   onStep: { au?.setStepRateIndex($0); refreshTiming() },
                   onSwing: { au?.setSwing($0); refreshTiming() },
                   onToggleMode: toggleMode,
                   canUndo: au?.uiCanUndo ?? false, canRedo: au?.uiCanRedo ?? false,
                   onUndo: undo, onRedo: redo,
                   holdLatch: holdLatch, onToggleHold: toggleHold,
                   flowVariation: flowVariation, onCycleFlow: { flowVariation = (flowVariation + 1) % 6 })
    }

    // §6d TWO FLOWS: the grid FILLS the leftover the bands don't claim (this GeometryReader), so the signal
    // flow always FITS without scrolling and the emitter band (CLAIM/faders) is never clipped — the bands keep
    // their full natural height, the grid takes the rest. Cells stay compact (≤48); reclaiming grid room is
    // §6d TWO FLOWS signal column: RECEIVERS (4 grid-rows tall, 50% width, centred) → GRID → EMITTERS (same),
    // filling the available height as 17 equal rows (4 receiver + 9 grid [key + 8] + 4 emitter). The bands are
    // half-width and centred (user 2026-07-26); GridView height = 9·cell + 24, so total = 17·cell + 30.
    private func signalColumn(_ appWidth: CGFloat) -> some View {
        GeometryReader { g in
            let cell = max(18, min(48, (g.size.height - 30) / 21))   // 6 receiver + 9 grid + 6 emitter rows
            let bandH = cell * 6, half = g.size.width * 0.5   // bands are 6 grid-rows tall (+50%); 50% of grid width, centred
            VStack(spacing: 3) {
                HStack(spacing: 6) {                          // [placeholder] · RECEIVERS · [diagnostics]
                    placeholderBox.frame(maxWidth: .infinity)
                    receiversBox.frame(width: half)
                    diagBox.frame(maxWidth: .infinity)
                }.frame(height: bandH)
                gridBlock(cell)
                HStack(spacing: 6) {                          // [colour picker] · EMITTERS · [placeholder]
                    colourBox.frame(maxWidth: .infinity)
                    emittersBox.frame(width: half)
                    placeholderBox.frame(maxWidth: .infinity)
                }.frame(height: bandH)
            }
        }
    }

    @ViewBuilder private func gridBlock(_ cellHeight: CGFloat) -> some View {
        if flowVariation > 0 {
            // FLOW view (item 10): the grid region becomes the flow theater. Watch-only; the desk stays live.
            FlowView(variation: flowVariation, scene: scene, colours: docColours, receivers: receivers,
                     busChannels: busChannels, busEnabled: busEnabled,
                     playColumn: d.effColumn, playing: d.playing, beat: d.beat, tempo: d.tempo,
                     stepBeats: stepBeats, emitPeak: emitPeak, receiverPeak: receiverPeak)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
        GridView(scene: scene, colours: docColours, playColumn: d.effColumn, playing: d.playing,
                 beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                 cellHeight: cellHeight, editing: editing,
                 selCol: selCol, selRow: selRow, onTap: tapCell,
                 onAuditionStart: startAudition, onAuditionEnd: endAudition,
                 onLongPressStageCell: enterStagingForCell,
                 laneMask: laneMask, onLaneMask: setLane, holdLatch: holdLatch, onMoveCell: moveCell,
                 dropHoverCell: paletteDragPoint.flatMap(cellAtGlobal),
                 staging: staging, stagingColor: stagingColor, stagedCells: stagedCells,
                 hiddenPending: hiddenPending, tapAltMask: tapAltMask, tapMuteMask: tapMuteMask)
            .background(GeometryReader { g in Color.clear   // §5: capture the grid's global frame for palette drops
                .onAppear { gridFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { gridFrame = $0 } })
            .marchingAnts(stagingDragging, color: stagingColor, cornerRadius: 8)   // staging: the outline hands off to the grid mid-drag
        }
    }

    private var hint: some View {
        Text(flowVariation > 0
             ? "FLOW · \(FlowView.names[min(flowVariation, FlowView.names.count - 1)]) · watch-only · TAP a cell → TRACE its path · FLOW button → next view"
             : editing
             ? "EDIT · TAP cell → hide (tap again to restore) · HOLD cell → cell-edit · drag a colour → place"
             : "PERFORM · TAP cell → ALT flip · HOLD cell → audition (stopped) · HOLD column keys → lap · HOLD → latch")
            .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // §6d TWO FLOWS — the COLOUR flow (the treatment axis): COLOUR → ALT → PROCESSOR SELECTOR → SETTINGS.
    // LANDSCAPE stacks it top→bottom in the right column (this VStack); PORTRAIT lays it out via
    // `colourFlowBand` below the emitter band. The RECEIVERS/EMITTERS bands live on the SIGNAL flow (above/
    // below the grid), not here.
    private var identityColumn: some View {
        VStack(spacing: 8) {
            if staging { cellBox }         // COLOUR moved to the emitter row; cell-edit surface stays here
            processorPanels                // procA | procB, side by side
        }
    }

    // delta item 8 (portrait): the COLOUR flow — the treatment axis, separate from the signal flow (whose
    // RECEIVERS/EMITTERS bands flank the grid above). The two PROCESSOR PANELS (procA | procB) sit here; each
    // is a fixed frame sized for the largest field set, so truncation dies by geometry.
    private func colourFlowBand(_ width: CGFloat, _ height: CGFloat) -> some View {
        let gap: CGFloat = 8
        let avail = max(0, width - gap)
        return HStack(alignment: .top, spacing: gap) {
            if staging { VStack(spacing: gap) { cellBox }.frame(width: avail * 0.34) }   // cell-edit surface (staging only)
            processorPanels.frame(maxWidth: .infinity)
        }
    }

    private var emittersBox: some View {
        OutputsView(busEnabled: busEnabled, busChannels: busChannels, editing: editing,
                    emitPeak: emitPeak, emitPeakAt: emitPeakAt, claim: claim, holdLatch: holdLatch,
                    onToggle: toggleEmitter, onSetChannel: setEmitterChannel,
                    onVelOverride: setVelOverride, onClaim: setClaim)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // THE CELL BOX (user 2026-07-26) — cell-edit's single surface, below the COLOUR grid, shown only in
    // staging. Top→bottom: INPUT (receivers radio + ROW) · ON section · OUTPUT (A–D) · a wide PREVIEW toggle.
    // Moving border like the other cell-edit affordances; hands off to the grid during a drag.
    @ViewBuilder private var cellBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            StagingInputView(inputRow: stagedConfig.inputRow, inputReceiver: stagedConfig.inputReceiver,
                             receivers: receivers, onPickReceiver: setStagedReceiver,
                             onPickRow: pickStagedRow, onStepRow: stepStagedRow)
            OnSectionView(config: brushColour?.onResolved ?? OnConfig(),
                          altPaired: stagedAltPaired, morphCompatible: brushGlides, stochastic: stagedStochastic,
                          onEdit: editStagedOn)
            StagingEmittersView(buses: stagedConfig.buses, onToggle: toggleStagedBus)
            HStack(spacing: 6) { previewButton; previewHoldChip }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
        .marchingAnts(staging && !stagingDragging, color: stagingColor)
    }

    // PREVIEW — cell audition, a momentary HOLD button (user 2026-07-26): active only while pressed, and it
    // takes PRIORITY over the drag's preview-in-place (no longer suppressed during a grid drag). Phase 1: UI
    // state only. Phase 2 wires the routing (solo the staged cell + row-source-in-time; wins over in-place).
    private var previewButton: some View {
        let active = cellPreview
        return Text(active ? "PREVIEW ●" : "PREVIEW (hold)")
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundColor(active ? .black : .white.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(active ? stagingColor : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? .clear : Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)                 // press-and-hold: down = preview on, release = off
                .onChanged { _ in if !cellPreview { cellPreview = true; startCellPreview() } }
                .onEnded { _ in if !holdLatch { cellPreview = false; au?.clearPreview() } })   // §5c HOLD → LATCH (stays on)
    }

    // §5c HOLD in the CELL box — the sustain pedal for the PREVIEW spring: while ON, releasing PREVIEW
    // latches it (hands-free audition); toggling HOLD off (or leaving cell-edit) drops it.
    private var previewHoldChip: some View {
        Text("HOLD").font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(holdLatch ? .black : .white.opacity(0.6))
            .padding(.horizontal, 8).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(holdLatch ? Color(red: 0.98, green: 0.72, blue: 0.12) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(holdLatch ? .clear : Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture { toggleHold() }
    }

    // Increment 2: while PREVIEW is held, tell the engine the staged VIRTUAL cell (colour + input filter +
    // bus mask) so it solos. Also suspends the drag's preview-in-place (PREVIEW wins, per the design).
    // NOTE: audible only for an ARP colour with held notes (Increment 1 scope: arp of the source pool).
    private func startCellPreview() {
        guard let au else { return }
        let ci = colourIDs.firstIndex(of: stagedConfig.colourID) ?? -1
        var mask: UInt8 = 0
        for b in stagedConfig.buses { mask |= (1 as UInt8) << b.cable }
        // receiver input → its channel filter (0 = OMNI); row input's live feed is Increment 1b → OMNI source for now.
        let filter = (stagedConfig.inputRow == nil && stagedConfig.inputReceiver < receivers.count)
            ? receivers[stagedConfig.inputReceiver].channel : 0
        au.setPreview(colourIndex: ci, filter: filter, busMask: mask, inputRow: stagedConfig.inputRow ?? -1)
        clearPreview()   // suspend any in-place hover preview while PREVIEW is held
    }

    @ViewBuilder private var receiversBox: some View {
        ReceiversView(receivers: receivers, editing: editing, peak: receiverPeak, peakAt: receiverPeakAt,
                      thruReceiver: thruReceiver,
                      onSetChannel: setReceiverChannel, onToggleMute: toggleReceiverMute,
                      onSetCable: setReceiverCable, onSetThru: setThru,
                      soloMask: soloReceiverMask, onToggleSolo: toggleReceiverSolo,
                      octave: receiverOctave, onOct: nudgeReceiverOctave,
                      onVelOverride: setReceiverVel, holdLatch: holdLatch)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    private var colourBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("COLOUR").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                if let c = colourColor(brush) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12) }
                Text(brush.uppercased()).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            }
            PaletteView(brush: brush, scene: scene, playColumn: d.effColumn, playing: d.playing,
                        beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                        onPick: { id in                          // staging: tap SELECTED chip → exit; tap ANOTHER → recolour the flashing set
                            if staging { if id == stagedConfig.colourID { exitStaging() } else { recolorStaged(id) } }
                            else { pickPalette(id) }
                        },
                        onChipDrag: paletteDragChanged, onChipDrop: paletteDrop,
                        onLongPress: enterStaging,                // hold stays the drag/enter gesture — NOT an exit (user 2026-07-25)
                        stagingID: staging ? stagedConfig.colourID : nil)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // A neutral placeholder box (reserved space for a future control) — flanks the bands.
    private var placeholderBox: some View {
        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    // The dev diagnostics (a8 stuck-note monitor) as a compact VERTICAL box — sits to the RIGHT of RECEIVERS.
    private var diagBox: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DIAG").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            Text("VOICES \(d.activeVoiceCount)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            Text("HELD \(d.poolCount)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            Text("ECHO \(d.passthroughHeld)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            Text("PANICS \(d.panics)").font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(d.panics > 0 ? .black : .white.opacity(0.5))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(d.panics > 0 ? Color(red: 0.98, green: 0.35, blue: 0.3) : .clear))
            Spacer(minLength: 0)
        }
        .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // delta item 8 PROCESSOR PANELS — procA and procB side by side, each a self-contained face editor with
    // its own COPY (+ PASTE when the clipboard holds a processor).
    @ViewBuilder private var processorPanels: some View {
        if let bc = brushColour {
            HStack(alignment: .top, spacing: 8) {
                ProcessorBox(colour: bc, colourIndex: brushIndex, face: .a,
                             onEdit: editBrushColour, onTranspose: setBrushTranspose, onMorph: setBrushMorph,
                             onSetTypeA: setBrushType, canPaste: procClipboard != nil,
                             onCopy: { copyProc(.a) }, onPaste: { pasteProc(.a) })
                    .frame(maxWidth: .infinity)
                ProcessorBox(colour: bc, colourIndex: brushIndex, face: .b,
                             onEdit: editBrushColour, onTranspose: setBrushTranspose, onMorph: setBrushMorph,
                             canPaste: procClipboard != nil,
                             onCopy: { copyProc(.b) }, onPaste: { pasteProc(.b) })
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // Palette tap selects the desk brush (delta item 8 retired the ALT-targeting pairing gesture — a second
    // processor is now made on the B panel, not by pairing to another Colour).
    private func pickPalette(_ id: String) { brush = id }

    // SCENE strip — the 16 factory scenes (Docs/factory-scenes.md), full-width along the bottom.
    private var sceneStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("SCENE").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                Text(sceneName).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            }
            HStack(spacing: 4) {
                ForEach(Array(SceneFactory.scenes.enumerated()), id: \.offset) { i, _ in
                    let id = "S\(i + 1)"
                    Text("\(i + 1)").font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(id == loadedID ? .black : .white.opacity(0.8))
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(id == loadedID ? Color(red: 0.98, green: 0.72, blue: 0.12) : Color.white.opacity(0.08)))
                        .onTapGesture { au?.loadFactoryScene(i); loadedID = id }
                }
            }
        }
    }

    // Dev-only: the canned TestSessions loader (portrait scroll; not part of the release strip).
    // a8 stuck-note monitor (dev): the open-voices dump + the assert-on-silence self-heal count. PANICS > 0
    // means a stuck note was caught and force-cleared in the provably-silent state — a latent bug to chase.
    private var stuckNoteMonitor: some View {
        let panicked = d.panics > 0
        return HStack(spacing: 10) {
            Text("VOICES \(d.activeVoiceCount)").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
            Text("HELD \(d.poolCount)").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
            Text("ECHO \(d.passthroughHeld)").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
            Text("PANICS \(d.panics)").font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(panicked ? .black : .white.opacity(0.55))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(panicked ? Color(red: 0.98, green: 0.35, blue: 0.3) : Color.clear))
            Spacer()
        }
    }

    private var devLoader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TEST SESSIONS (dev)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.3))
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 6) {
                ForEach(Array(TestSessions.all.enumerated()), id: \.offset) { _, s in
                    Button(s.id) { load(s) }
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(s.id == loadedID ? .black : .white.opacity(0.75))
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(s.id == loadedID ? Color(red: 0.15, green: 0.88, blue: 0.94) : Color.white.opacity(0.08)))
                }
              }
            }
        }
    }
}

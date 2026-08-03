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

/// Live diagnostics: what the kernel is actually seeing, at 4 Hz.
/// Interpreting it:
///  · PARAM EVENTS rising while you turn a mapped knob → host uses render-side events (kernel handles).
///  · TREE morph moving but PARAM EVENTS static → host uses setValue (observer/snapshot path).
///  · Neither moving → the mapping isn't reaching this instance (host-side routing).
///  · CC IN rising → raw CC arrives at the MIDI input (and is passed through on A).
/// §11/11b THE ROUND HELD VERBS — the rebuilt authoring surface. Hold a verb → the grid invites → taps do the
/// verb → release = done (no armed state). Long-press a verb = LATCH (tap again releases). No verb held → taps
/// are TRIGGERS. HOLD (the 6th button) is the §5c gesture-latch, not a grid verb.
enum Verb: String, CaseIterable {
    // /btw ①: COPY · PASTE replace MOVE · COPY. COPY captures a cell into a session clipboard that PERSISTS
    // after release; PASTE stamps it (enabled once the clipboard is non-empty). Relocation = COPY→PASTE→DELETE.
    case place = "PLACE", delete = "DELETE", select = "SELECT", copy = "COPY", paste = "PASTE"
    var label: String { self == .place ? "PLACE CELL(S)" : rawValue }
    var hue: Color {
        switch self {
        case .place:  return Color(red: 0.35, green: 0.92, blue: 0.50)   // green — additive
        case .delete: return Color(red: 0.98, green: 0.35, blue: 0.30)   // red — destructive
        case .select: return Color(red: 0.15, green: 0.88, blue: 0.94)   // cyan — inspect/edit
        case .copy:   return Color(red: 0.70, green: 0.55, blue: 0.98)   // violet — capture
        case .paste:  return Color(red: 0.98, green: 0.72, blue: 0.12)   // amber — stamp
        }
    }
}

/// The EDIT page's tap modes. ADD/EDIT builds a live-edited selection set (the ONLY mode with APPLY/CANCEL
/// staging); MOVE drags cells to new positions; MUTE toggles per-cell mute; CLEAR removes a cell (re-tap the
/// empty slot to reinstate, while still in CLEAR). Everything except ADD/EDIT is IMMEDIATE + undo/redo.
enum EditPageMode { case addEdit, move, mute, clear }

struct DiagView: View {
    weak var au: MidiSparkAudioUnit?
    @State var d = KernelDiag()      // polled for the grid's effColumn / playing
    @State var uiAppeared = true     // §4c INVISIBLE=FROZEN: this view is on-screen (host shows our plugin)
    @State var appActive = true      // §4c: the app is foregrounded
    var animationsPaused: Bool { !(uiAppeared && appActive) }   // hidden OR backgrounded ⇒ freeze the canvas
    @State var loadedID = "—"
    @State var sceneEmpty: [Bool] = []       // MULTI-SCENE: per-slot occupancy (empty ⇒ a "+" save slot)
    @State var activeSceneIdx = 0             // MULTI-SCENE: the playing scene
    // (the arrangement bar's own interactive state — pending/recue/blink/drag/sweep-anchor/shake — lives in ArrangementBar)
    @State var showSettings = false           // AB: the ⚙ cog page (settings overlay — engine never stops)
    @State var showPresets = false             // §3 PRESETS: the browser sheet
    @State var presetList: [String] = []       // §3 the user preset names (refreshed on open)
    @State var currentPreset = ""              // §3 the loaded preset's name
    // CELL MACHINE stage-4: the CELL LIBRARY browser + the stamp mode (a saved cell awaiting placement).
    @State var showCellLibrary = false
    @State var cellLibraryList: [String] = []
    @State var scene = SceneState.empty()
    @State var brush = "gold"        // the paint Colour (view-local; never in the document)
    // §11b the held quasimode (SPRING-ONLY, user 2026-07-27): a verb is active ONLY while its button is pressed
    // (release = done). No latch/toggle. Nil = taps are triggers.
    @State var heldVerb: Verb? = nil          // the currently-pressed verb
    @State var selection: Set<GridView.GridPos> = []   // SELECT: the built set (outlives the hold)
    // /btw ①: the SESSION CLIPBOARD — COPY captures a cell here; it PERSISTS after the hold releases; PASTE
    // stamps it (PASTE is disabled while this is nil). Replaces the old per-hold moveSource/copySource.
    @State var clipboard: Cell? = nil
    // PLACE toggle-with-restore (user 2026-07-28): re-tapping a cell placed this hold undoes it — placed-on-empty
    // → removed; placed-over-a-cell → the ORIGINAL restored (all its properties). Memory resets each PLACE hold.
    @State var placeFresh: Set<GridView.GridPos> = []   // placed onto an empty cell (re-tap removes)
    @State var placeUndo: [GridView.GridPos: Cell] = [:]   // the original cell a place REPLACED (re-tap restores)
    @State var gridSnapshot: [[Cell?]]? = nil          // the grid before this PLACE/DELETE hold — CANCEL reverts to it
    @State var holdSeq = 0                             // /btw ④: bumps each PLACE hold → seeds the mid-hold recolour coalesce key
    @State var strokeKey: String? = nil               // STROKES: the per-drag undo coalesce key (nil between strokes)
    @State var strokeSeq = 0                           // STROKES: monotonic — makes each stroke's key unique
    @State var selectionSnapshot: Set<GridView.GridPos>? = nil   // the selection before this SELECT hold — CANCEL reverts
    var activeVerb: Verb? { heldVerb }
    var placedThisHold: Set<GridView.GridPos> { placeFresh.union(placeUndo.keys) }   // wear a white border
    @State var selCol = -1
    @State var selRow = -1
    // Cell Edit station (AcceptanceCriteria-cell-edit): EDIT is a 6th control, a TOGGLE (not a spring verb),
    // pointing the station at ONE cell (selCol/selRow) for deep editing. It is deliberately NOT a `heldVerb` —
    // `activeVerb` stays "a spring verb is held", so banners/routing-viz/candidate glow stay off for EDIT.
    @State var editArmed = false
    // MODE ROW: the EDIT page's tap modes. ADD/EDIT builds a selection set + edits it live under APPLY/CANCEL
    // staging (the ONLY mode that stages). MOVE drags cells; MUTE toggles mute; CLEAR removes — all IMMEDIATE + undo/redo.
    @State var editMode: EditPageMode = .addEdit
    // MODE ROW — ADD/EDIT mode's manual multi-SELECT set (ordered; the FIRST member is the ANCHOR). Edits apply live
    // to every member; twins of the set only PULSE to advertise inclusion. Replaces the old auto-twin/DETACH model.
    @State var editSel: [GridView.GridPos] = []
    // MODE ROW — cells BORN this session (empty-tap births). Re-tapping a newborn deletes it (it was just created);
    // cleared on APPLY/CANCEL (they become permanent / were reverted).
    @State var bornThisSession: Set<GridView.GridPos> = []
    // MODE ROW — ADD/EDIT: a POPULATED cell adopted into the group has its ORIGINAL config stashed here, so
    // deselecting it during the session reverts it to how it was (empty-cloned cells delete instead).
    @State var preAdoptStash: [GridView.GridPos: Cell] = [:]
    // MODE ROW — a long-press fires its mode action ONCE per press (the underlying gesture repeats while held).
    @State var longPressFired = false
    // MODE ROW — CLEAR mode's undo stash: cells removed this CLEAR session, keyed by position. Re-tapping the now-empty
    // slot reinstates the cell. Dropped when we leave CLEAR mode (thereafter, undo/redo covers the removal).
    @State var clearedStash: [GridView.GridPos: Cell] = [:]
    // MODE ROW — the edit-page column-loop set (bit i = column i), driven into the same laneMask path as PERFORM.
    @State var editLoopMask: UInt8 = 0
    var editingCell: Cell? { (editArmed && selCol >= 0 && selRow >= 0) ? scene.cells[selCol][selRow] : nil }
    static let editHue = Color(red: 0.95, green: 0.47, blue: 0.85)   // orchid — deep single-cell edit (distinct from the 5 verbs)
    @State var busChannels: [Int] = [1, 2, 3, 4]
    @State var busEnabled: [Bool] = [true, true, true, true]   // delta §6a
    @State var claimMask: UInt8 = 0                           // delta §6a CLAIM v2: the multi-claim mask (bits A–D)
    @State var claimLeak: [Int] = [0, 0, 0, 0]                // delta §6a CLAIM v2: per-claimant LEAK % (0…100)
    @State var thruReceiver: Int = 0                          // receiver strip: the THRU pip (passthrough source)
    @State var flattenMask: UInt8 = 0                         // role family: FLATTEN set (persisted)
    @State var flattenAmount: [Int] = [0, 0, 0, 0]           // role family: per-emitter FLATTEN amount %
    @State var altMask: UInt8 = 0                            // role family: ALT turn-taking group (persisted)
    @State var altCount: [Int] = [1, 1, 1, 1]               // role family: per-emitter ALT notes-per-turn
    @State var masterMute = false                           // master panel: global emission kill (persisted)
    @State var masterKey = 0                                // master panel: per-scene transpose (persisted)
    @State var soloReceiverMask: UInt8 = 0                    // receiver strip: additive input SOLO set (ephemeral)
    @State var receiverOctave: [Int] = [0, 0, 0, 0]          // receiver strip: per-receiver ±octave nudge (ephemeral)
    @State var latchMask: UInt8 = 0                          // receiver strip: per-receiver chord LATCH (ephemeral)
    @State var holdLatch = false             // delta §5c: HOLD — the sustain pedal for gestures (PERFORM)
    @State var muteArmed = false             // PERFORM: MUTE mode — while armed, a grid tap toggles the cell's mute
    // SEAL comet: per-cell last-strike time + velocity (index = col*8+row), stamped from the 4 Hz poll of
    // au.pollCellStrikes(); the cell's comet runs along its figure for ~1s after the last strike (UI owns the decay).
    @State var cellHitAt = [Date](repeating: .distantPast, count: 64)
    @State var cellHitVel = [Double](repeating: 0, count: 64)
    // SEAL comet note-on/off GATE: which cells are currently SOUNDING (from au.pollCellSounding), and when each
    // last went SILENT. The spark travels for exactly as long as the note is held, then fades ~0.45s from release.
    @State var cellSounding = [Bool](repeating: false, count: 64)
    @State var cellReleasedAt = [Date](repeating: .distantPast, count: 64)
    @State var emitPeak: [Double] = [0, 0, 0, 0]               // §6a meter: latched peak (0–1) per emitter
    @State var emitPeakAt: [Date] = Array(repeating: .distantPast, count: 4)   // when each peak latched (for decay)
    @State var receiverPeak: [Double] = [0, 0, 0, 0]           // §9 item 11 input meter: latched peak per receiver
    @State var receiverPeakAt: [Date] = Array(repeating: .distantPast, count: 4)
    @State var mpeSeenAt: [Date] = Array(repeating: .distantPast, count: 4)   // §MPE: last auto-detected per receiver
    @State var emitMarks: [[VelMark]] = [[], [], [], []]      // item 4: floating output velocity marks (Colour-tinted)
    @State var recvMarks: [[VelMark]] = [[], [], [], []]      // item 4: floating input velocity marks (strip hue)
    @State var recvHeld: [[Double]] = [[], [], [], []]        // duration: currently-held input velocities per receiver (0–1)
    @State var recvRelease: [[VelMark]] = [[], [], [], []]    // ③ marks left FADING (~250ms) as held input notes release
    @State var emitHeld: [[SoundMark]] = [[], [], [], []]     // §strips-done: notes currently sounding per emitter (steady, cargo-tinted)
    @State var emitRelease: [[VelMark]] = [[], [], [], []]    // §strips-done: marks FADING (~250ms) as sounding notes release
    @State var docColours: [Colour] = []
    @State var receivers: [Receiver] = []                     // delta §9 item 11: the RECEIVERS panel
    @State var stepIndex = 2
    @State var swing = 50
    // MODELESS (2026-07-27): GRID CONTROLS — the verb palette. Radio-armed; INSPECT is functional in 1b, the
    // others render inert until their increments land. EDIT mode survives alongside until verb coverage completes.
    @State var flowVariation = 0       // FLOW view (item 10): 0 = grid; 1…5 cycle the visualisations
    @State var vizIntensity = 1        // VISUALIZATION tenant: 0 = OFF · 1 = SUBTLE · 2 = SHOWCASE
    #if DEBUG
    @State var vizShowDiag = false     // dev: the VIZ slot flips to the DIAG face (design item 2)
    #endif
    @State var laneMask: UInt8 = 0     // §5b lap: held column keys (bit i = column i), PERFORM only
    @State var tapAltMask: UInt64 = 0  // §9 item 1 ON TAP (unified ALT): ephemeral per-cell alt flips
    @State var tapMuteMask: UInt64 = 0 // §9 item 1 ON TAP = MUTE: ephemeral per-cell mute
    @State var soloEmitterMask: UInt8 = 0  // §9 item 1 ON TAP = SOLO EMITTERS: the derived emitter solo set
    @State var emitterFootSolo: UInt8 = 0  // emitter strip: the foot SOLO button set (OR'd into the derived mask)
    @State var emitterOctave: [Int] = [0, 0, 0, 0]   // emitter strip: per-emitter output ±octave nudge (ephemeral)
    @State var showDevLoader = false                 // dev-build: the hidden T-session loader overlay is showing
    // §9 item 1 ON TAP quant/duration (4c): active TIMED actions. A tap adds one (onset from tapWhen, expiry
    // from tapFor); each poll derives the three ephemeral masks from the actions that are live at the beat.
    // ON-TAP overlay: TapKind/TapOverlay + the apply/mask logic are pure functions in Derivations (testable).
    @State var tapActions: [TapOverlay] = []
    let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    // §5b COLUMN-SUBSET LAP: the PERFORM multi-column hold reports the held-set bitmask here. Push it to
    // the engine (ephemeral, never persisted) and keep a copy for the key LOOP highlight. Cleared to 0
    // on release (the overlay reports empty) and on the EDIT switch (see the mode toggle).
    func setLane(_ mask: UInt8) { laneMask = mask; au?.setLaneMask(mask) }

    // EDIT/PERFORM toggle. Leaving PERFORM ends any lap (belt-and-suspenders — the overlay also cancels).

    // §9 item 1 ON TAP: clear every ephemeral perform-tap overlay (timed actions + alt flips, mutes, emitter solo).
    func clearOnTap() {
        if !tapActions.isEmpty { tapActions.removeAll() }
        if tapAltMask != 0 { tapAltMask = 0; au?.setTapAltMask(0) }
        if tapMuteMask != 0 { tapMuteMask = 0; au?.setTapMuteMask(0) }
        if emitterFootSolo != 0 { emitterFootSolo = 0 }
        if soloEmitterMask != 0 { soloEmitterMask = 0; au?.setSoloEmitterMask(0) }
    }

    // emitter strip: additive foot SOLO — toggle a bit, then re-derive so the kernel sees the union immediately.
    func toggleEmitterSolo(_ i: Int) {
        guard (0..<4).contains(i) else { return }
        emitterFootSolo ^= UInt8(1 << i)
        refreshTapMasks()
    }
    // emitter strip: output ±octave nudge (±1 per tap, clamp ±3). Ephemeral weather — clears on transport stop.
    func nudgeEmitterOctave(_ i: Int, _ delta: Int) {
        guard (0..<4).contains(i) else { return }
        emitterOctave[i] = max(-3, min(3, emitterOctave[i] + delta))
        au?.setEmitterOctave(i, emitterOctave[i])
    }
    func clearEmitterPerform() {
        emitterOctave = [0, 0, 0, 0]; for i in 0..<4 { au?.setEmitterOctave(i, 0) }
    }

    // §11b dispatch: a verb held → the tap does the verb (SELECT also routes candidates in-session); else a tap
    // is a TRIGGER (ON TAP). Routing happens WHILE SELECT is held (user 2026-07-28): the world offers wiring for
    // the selected cell, tapping a candidate wires it, RELEASE applies, CANCEL reverts.
    func tapCell(_ col: Int, _ row: Int) {
        if editArmed {                                       // MODE ROW: EDIT builds a selection set; MUTE/CLEAR = increment 4
            guard editMode == .addEdit else { editModeTap(col, row); return }
            let pos = GridView.GridPos(col: col, row: row)
            au?.beginEditSession()                           // idempotent — a real change is what dirties APPLY/CANCEL
            if editSel.contains(pos) {                       // already in the group → tapping DESELECTS + reverts it
                if editSel.first == pos {                    // the ANCHOR
                    if editSel.count == 1 { deselect(pos) }  // …sole selection → a tap deselects (grid returns to its prior state)
                    // …but the anchor of a GROUP needs a long-press to drop (protects the group from a stray tap)
                } else {
                    deselect(pos)
                }
            } else {                                         // NOT selected → add to the group (any tapped cell joins)
                let wasEmpty = scene.cells[col][row] == nil
                if editSel.isEmpty {                          // FIRST selection
                    if wasEmpty { au?.editScene { $0.cells[col][row] = newbornCell() }; refreshFromDocument(); bornThisSession.insert(pos) }
                    // a populated first cell is just selected as the anchor
                } else if let a = editSel.first {            // a group exists → the new cell ADOPTS the anchor's full config
                    if !wasEmpty { preAdoptStash[pos] = scene.cells[col][row] }   // stash the original so deselect can revert it
                    au?.editScene { s in if let anchor = s.cells[a.col][a.row] { s.cells[col][row] = anchor } }   // → identical twins, edit together
                    refreshFromDocument()
                    if wasEmpty { bornThisSession.insert(pos) }   // an empty cell cloned into the group is "born" (deselect deletes)
                }
                editSel.append(pos)
            }
            syncAnchor()
            return
        }
        if muteArmed {                                       // PERFORM · MUTE mode: a tap toggles the cell's mute
            guard scene.cells[col][row] != nil else { return }
            au?.editScene { $0.cells[col][row]?.muted.toggle() }; refreshFromDocument(); return
        }
        if let v = activeVerb { doVerb(v, col, row) } else { triggerTap(col, row) }
    }

    // §10/11c ROUTE FOCUS (multi-cell, AcceptanceCriteria 2026-07-29). PLACE: the most-recently-placed cell.
    // SELECT: EVERY column that holds EXACTLY ONE selected cell is a focus (a column with 2+ selected cells is
    // ambiguous → no routing there). Each focus lights ALL cells above it (SRC) and ALL cells below it (DEST) in
    // its own column. Release applies; CANCEL reverts.
    var routeFoci: [Int: Int] {                  // col → focus row (≤ one per column) — PLACE: cells placed
        let cells: [GridView.GridPos]                    // this hold (incl. a whole row); SELECT: the selection.
        if heldVerb == .place { cells = Array(placedThisHold) }
        else if heldVerb == .select { cells = Array(selection) }
        else { return [:] }
        let occupied = cells.filter { $0.col < scene.cells.count && $0.row < scene.cells[$0.col].count && scene.cells[$0.col][$0.row] != nil }
        return routeFociByColumn(occupied.map { (col: $0.col, row: $0.row) })
    }
    var routeFocusCells: Set<GridView.GridPos> {
        Set(routeFoci.map { GridView.GridPos(col: $0.key, row: $0.value) })
    }
    // §viz — the routing graph drawn while ANY verb is held, and the "selected" set that lights the paths
    // through it (PLACE = this hold's placed cells, SELECT = the selection).
    var vizSelectedCells: Set<RouteCell> {
        let src: Set<GridView.GridPos> = heldVerb == .place ? placedThisHold : (heldVerb == .select ? selection : [])
        return Set(src.map { RouteCell(col: $0.col, row: $0.row) })
    }
    var vizEdges: [RouteEdge] { routingEdges(cells: scene.cells, selected: vizSelectedCells) }
    func routeProbe(_ id: String) -> some View {
        GeometryReader { p in Color.clear.preference(key: RouteFramesKey.self, value: [id: p.frame(in: .named("signal"))]) }
    }
    // Grid-chaining retired: the SRC/DEST cell-to-cell candidate glow + tap-to-wire are gone. Receiver + emitter
    // routing (the strip ROUTE-IN/OUT faces, still driven by routeFoci) are unaffected.
    var routeInCandidates: Set<GridView.GridPos> { [] }
    var routeOutCandidates: Set<GridView.GridPos> { [] }
    @discardableResult func wireRouteCandidate(_ pos: GridView.GridPos) -> Bool { false }
    // §10 the strips wear a SESSION FACE while wiring; a tap applies to ALL foci.
    func routeInReceiver(_ r: Int) {
        guard !routeFoci.isEmpty else { return }
        au?.editScene { s in for (col, f) in routeFoci { s.routeInReceiver(col: col, row: f, receiver: r) } }; refreshFromDocument()
    }
    func toggleFocusEmitter(_ b: Bus) {
        guard !routeFoci.isEmpty else { return }
        au?.editScene { s in for (col, f) in routeFoci { s.toggleEmitter(col: col, row: f, bus: b) } }; refreshFromDocument()
    }
    var routeInCurrentReceiver: Int? {           // the receiver ALL foci share (nil ⇒ mixed / row-fed → no ring)
        var recv: Int?; var first = true
        for (col, f) in routeFoci {
            guard let cell = scene.cells[col][f] else { continue }
            let r = cell.inputRow == nil ? cell.inputReceiver : nil
            if first { recv = r; first = false } else if recv != r { return nil }
        }
        return recv
    }
    var routeOutBusesOn: [Bool] {                // a bus reads ON only if EVERY focus enables it
        guard !routeFoci.isEmpty else { return [false, false, false, false] }
        return Bus.allCases.map { b in routeFoci.allSatisfy { (col, f) in scene.cells[col][f]?.buses.contains(b) ?? false } }
    }

    // §11 dispatch a grid tap to the active verb.
    func doVerb(_ v: Verb, _ col: Int, _ row: Int) {
        guard let au else { return }
        let pos = GridView.GridPos(col: col, row: row)
        switch v {
        case .place:                                        // PLACE CELL(S) — toggle-with-restore; a candidate tap WIRES the focus
            if wireRouteCandidate(pos) { return }           // §10 route-as-you-place: a SRC/DEST of the last-placed cell wires it
            au.editScene { placeToggle(&$0, col, row) }
            refreshFromDocument()
        case .delete:                                       // §10b heal-on-delete: children inherit the input
            guard scene.cells[col][row] != nil else { return }
            au.editScene { $0.deleteCellSever(col: col, row: row) }
            selection.remove(pos); refreshFromDocument()
        case .select:                                       // tapping a SRC/DEST candidate WIRES it (per column);
            if !selection.contains(pos) && wireRouteCandidate(pos) { return }   // else tapping toggles membership
            guard scene.cells[col][row] != nil else { return }            // an empty tap does NOTHING (spec: nothing changes)
            if selection.contains(pos) { selection.remove(pos) } else { selection.insert(pos) }
        case .copy:                                         // capture the tapped cell into the session clipboard (persists after release)
            if let cell = scene.cells[col][row] { clipboard = cell }
        case .paste:                                        // stamp the clipboard cell wherever tapped (every tap while held)
            if var c = clipboard {
                if c.inputRow == nil && c.inputReceiver == nil { c.inputReceiver = 0 }   // top-of-chain paste keeps a receiver (no unpointed MIDI-IN bypass)
                au.editScene { $0.cells[col][row] = c }
                refreshFromDocument()
            }
        }
    }

    // PLACE toggle-with-memory for ONE cell (used by a cell tap AND, looped, by a row chevron). Call inside
    // `au.editScene { placeToggle(&$0, …) }`. Re-tapping a placed empty REMOVES it; re-tapping a replaced cell
    // RESTORES the original (wiring preserved); a fresh tap PLACES (empty, downhill-nudge) or REPLACES (populated).
    func placeToggle(_ s: inout SceneState, _ col: Int, _ row: Int) {
        let pos = GridView.GridPos(col: col, row: row)
        if placeFresh.contains(pos) {                        // placed onto empty this hold → REMOVE (retoggle)
            s.cells[col][row] = nil; placeFresh.remove(pos)
            return
        }
        if let original = placeUndo[pos] {                   // replaced this hold → RESTORE the original (retoggle)
            s.cells[col][row] = original; placeUndo.removeValue(forKey: pos)
            return
        }
        // /btw ⑥: a FRESH place is blocked if this column already holds a cell placed THIS hold (one per
        // column per hold — release + re-hold to stack a second). The two re-tap branches above returned.
        let placedColumns = Set(placedThisHold.map(\.col))
        guard placeHoldDecision(placedColumns: placedColumns, retoggle: false, col: col) == .allowed else { return }
        if let existing = s.cells[col][row] {                // fresh tap on populated → REPLACE (remember; keep wiring)
            placeUndo[pos] = existing
            var c = Cell(colourID: brush, buses: [.a]); c.inputRow = existing.inputRow; c.inputReceiver = existing.inputReceiver
            s.cells[col][row] = c
        } else {                                             // fresh tap on empty → PLACE, UNROUTED
            placeFresh.insert(pos)
            // A fresh cell takes NO routing at all (user, 2026-07-30): no input row, no receiver (inputReceiver
            // nil ⇒ no receiver ring / no viz edge), and NO emitter (buses empty). It is null until the user
            // actively wires a source and destination in the routing-select view. Supersedes the old sticky-
            // routing + §9.③ downhill nudge, and the emitter-A default.
            s.cells[col][row] = Cell(colourID: brush, buses: [])
        }
    }

    // §9 item 1 ON TAP (4b/4c): the TRIGGER path — a tap runs the Colour's ON TAP action as a TIMED, EPHEMERAL
    // overlay. Never a document write; cleared on transport stop.
    func triggerTap(_ col: Int, _ row: Int) {
        guard scene.cells[col][row] != nil, let c = scene.cells[col][row] else { return }
        let on = docColours.first { $0.colourID == c.colourID }?.onResolved ?? OnConfig()
        let kind: TapKind
        switch on.tap {
        case .none:                                       // DEFAULT grid tap = persisted MUTE-toggle (dimmed).
            au?.editScene { $0.cells[col][row]?.muted.toggle() }   // no emitter output; children read raw MIDI-IN
            refreshFromDocument(); return
        case .mute:        kind = .mute
        case .solo:        kind = .solo
        case .alt:         kind = .alt
        case .fill, .replay: return                       // not yet wired (design clarification pending)
        }
        let idx = col * 8 + row
        var buses: UInt8 = 0
        for b in c.buses { if let i = Bus.allCases.firstIndex(of: b) { buses |= (1 << UInt8(i)) } }
        let onset = tapOnsetBeat(tapBeat: d.beat, quant: on.tapWhen, stepBeats: stepBeats)
        let expiry = tapExpiryBeat(onsetBeat: onset, duration: on.tapFor, stepBeats: stepBeats)
        tapActions = applyTapOverlay(tapActions, cell: idx, kind: kind, busMask: buses,
                                     onset: onset, expiry: expiry, retap: on.tapFor == .retap)
        refreshTapMasks()
    }

    // §9 item 1 ON TAP (4c): derive the three ephemeral masks from the actions live at the current beat —
    // pruning expired ones. Runs on tap AND each poll (so onsets fire + durations expire). Dedup-guarded.
    func refreshTapMasks() {
        let r = tapOverlayMasks(tapActions, now: d.beat, footSolo: emitterFootSolo)   // pure: expire + build masks
        if r.surviving.count != tapActions.count { tapActions = r.surviving }          // only mutate @State on real expiry
        if r.alt  != tapAltMask      { tapAltMask = r.alt;        au?.setTapAltMask(r.alt) }
        if r.mute != tapMuteMask     { tapMuteMask = r.mute;      au?.setTapMuteMask(r.mute) }
        if r.solo != soloEmitterMask { soloEmitterMask = r.solo;  au?.setSoloEmitterMask(r.solo) }
    }

    // §11b THE VERB CLUSTER — six round buttons, bottom-left (thumb reach): PLACE·HOLD / DELETE·SELECT / MOVE·COPY.
    // HELD quasimode: press-hold a verb = spring-active; long-press (0.5s) = LATCH (tap again releases). HOLD is
    // the §5c gesture-latch (not a grid verb). While a verb is active a tap does the verb; else a tap is a TRIGGER.
    var verbCluster: some View {
        VStack(spacing: 6) {
            // HOLD (moved from the controls panel — the §5c sustain latch) · MUTE (arm → tap cells to mute) ·
            // SELECT (to be implemented). EDIT moved OUT of the cluster — it's the header PERFORM/EDIT toggle now.
            roundVerb(label: "HOLD", hue: sceneAmberHue, active: holdLatch, badge: nil)
                .contentShape(Rectangle()).onTapGesture { toggleHold() }
            roundVerb(label: muteArmed ? "MUTE ✕" : "MUTE", hue: Verb.delete.hue, active: muteArmed, badge: nil)
                .contentShape(Rectangle()).onTapGesture { muteArmed.toggle(); if muteArmed { heldVerb = nil; editArmed = false } }
            roundVerb(label: "SELECT", hue: Verb.select.hue, active: false, badge: "soon")   // SELECT — to be implemented
                .opacity(0.4).allowsHitTesting(false)
            Spacer(minLength: 0)
        }
        .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    let sceneAmberHue = Color(red: 0.98, green: 0.72, blue: 0.12)   // HOLD's latch hue
    func onVerbEngaged(_ v: Verb) {
        editArmed = false                                   // §cell-edit A3: engaging any spring verb disarms EDIT (one editing intent)
        switch v {                                          // snapshot the state CANCEL reverts to, per verb (clipboard PERSISTS)
        case .place:  placeFresh = []; placeUndo = [:]; gridSnapshot = scene.cells; holdSeq += 1
        case .delete: gridSnapshot = scene.cells
        case .select: gridSnapshot = scene.cells; selectionSnapshot = selection   // routing edits + the stack both revert
        default: break
        }
    }
    // §11 CANCEL (user 2026-07-28): revert the in-progress changes to the state when the verb was engaged AND
    // END the held status (release the button). PLACE/DELETE revert the grid; SELECT reverts the built selection.
    var verbHasBanner: Bool { activeVerb == .place || activeVerb == .delete || activeVerb == .select }
    func cancelVerb() {
        switch heldVerb {
        case .place, .delete, .select:                      // SELECT reverts its routing edits too (grid → prior state)
            if let au, let snap = gridSnapshot { au.editScene { $0.cells = snap }; refreshFromDocument() }
            placeFresh = []; placeUndo = [:]
        default: break
        }
        selection.removeAll()                               // CANCEL clears the stack (user 2026-07-28)
        heldVerb = nil                                      // end the held status
    }
    // The verb session banner — a top overlay while PLACE/DELETE/SELECT is held; CANCEL (free hand) reverts + ends.
    func verbBanner(_ v: Verb) -> some View {
        let text: String
        switch v {
        case .place:  text = "Place cell(s) — tap the grid or a row · Choose one route in and multiple out"
        case .delete: text = "Delete cell(s) — tap the grid or a row · links cut"
        case .select: text = "Select cell(s) — tap to toggle · recolour with the palette"
        default:      text = ""
        }
        return HStack(spacing: 12) {
            Text(text).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 8)
            Text("CANCEL").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.22)))
                .contentShape(Rectangle()).onTapGesture { cancelVerb() }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(v.hue)
    }
    func roundVerb(label: String, hue: Color, active: Bool, badge: String?) -> some View {
        RoundedRectangle(cornerRadius: 12).fill(active ? hue : Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(hue.opacity(active ? 0 : 0.4), lineWidth: 1.5))
            .overlay(Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(active ? .black : hue.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.6).padding(3))
            .overlay(alignment: .topTrailing) {
                if let b = badge {
                    Text(b).font(.system(size: 8, weight: .heavy)).foregroundColor(.black)
                        .frame(width: 15, height: 15).background(Circle().fill(hue)).offset(x: 3, y: -3)
                }
            }
            .frame(height: 42).frame(maxWidth: .infinity).contentShape(RoundedRectangle(cornerRadius: 12))
    }
    // delta §5c: HOLD LATCH — while ON, releases latch instead of springing; HOLD-off is the synchronous
    // "drop" (every captured gesture releases at once). PERFORM-only; cleared on transport stop / EDIT.
    // v1 captures: §6a velocity overrides (in OutputsView) + audition (below). Lap + ON-HOLD deferred.
    func setHold(_ on: Bool) {
        guard holdLatch != on else { return }
        holdLatch = on
        if !on {                                 // the drop: release the captures this layer owns
            au?.clearAudition(); abox.target = nil
            au?.setHoldCell(-1); abox.held = false          // §9 item 1: a latched ON HOLD drops too
            au?.setLaneMask(0); laneMask = 0     // §5c: the latched lap set drops too (velocity springs
                                                 // back via OutputsView's onChange(holdLatch))
        }
    }
    func toggleHold() { setHold(!holdLatch) }

    // delta §5 / a6: undo/redo restore the WHOLE document, so refresh every document-derived @State.
    func undo() { if au?.uiUndo() == true { refreshFromDocument() } }
    func redo() { if au?.uiRedo() == true { refreshFromDocument() } }
    func refreshFromDocument() {
        guard let au else { return }
        scene = au.uiScene()
        docColours = au.uiColours()
        busChannels = au.uiBusChannels()
        busEnabled = au.uiBusEnabled()
        claimMask = au.uiClaimMask()
        claimLeak = au.uiClaimLeak()
        thruReceiver = au.uiThruReceiver()
        flattenMask = au.uiFlattenMask()
        flattenAmount = au.uiFlattenAmount()
        altMask = au.uiAltMask()
        altCount = au.uiAltCount()
        masterMute = au.uiMasterMute()
        masterKey = au.uiMasterKey()
        sceneEmpty = au.uiScenes().map { $0.isEmpty }   // MULTI-SCENE strip occupancy + active
        activeSceneIdx = au.uiActiveScene()
    }

    // AUDITION (§6.4 / delta §5): press-hold a cell (stopped) → hear its processor alone. The held
    // target lives in a REFERENCE box mutated SILENTLY (never @State) so starting/stopping an audition
    // never re-renders the grid mid-press (which would tear down the long-press gesture). The deduped
    // poll above does the rest — when stopped the grid is quiescent, so the gesture is never disturbed.
    final class AuditionBox { var target: (col: Int, row: Int)? = nil; var held = false }
    @State var abox = AuditionBox()

    // PERFORM press-hold → ON HOLD (§9 item 1): while a cell is held (playing), its ON HOLD treatment overlays.
    // Kernel-only (no @State / re-render). (Stopped-audition retired with the editing UI — it returns via PLACE.)
    func startAudition(_ col: Int, _ row: Int) {
        guard let au, scene.cells[col][row] != nil, d.playing else { return }
        au.setHoldCell(col * 8 + row); abox.held = true             // ON HOLD overlay (idempotent per onChanged)
    }
    func endAudition() {                                     // release (SPRING); §5c-HOLD latch keeps it (see setHold)
        if abox.held { au?.setHoldCell(-1); abox.held = false }
    }

    // ---- PROCESSOR box: edit the selected (brush) Colour ----
    var brushIndex: Int { colourIDs.firstIndex(of: brush) ?? 0 }
    var brushColour: Colour? { docColours.first { $0.colourID == brush } }

    func editBrushColour(_ f: @escaping (inout Colour) -> Void) {
        guard let au else { return }
        au.editColour(brushIndex, f)
        docColours = au.uiColours()
    }
    func setBrushTranspose(_ v: Int) { au?.setColourTranspose(brushIndex, v); docColours = au?.uiColours() ?? docColours }
    // (setBrushMorph/setBrushType + the A/B processor CLIPBOARD removed with the retired shared-Colour desk.)
    func refreshTiming() { stepIndex = au?.uiStepRateIndex() ?? stepIndex; swing = au?.uiSwing() ?? swing }
    var stepBeats: Double { StepRate.allCases[min(stepIndex, StepRate.allCases.count - 1)].beats }

    // EMITTERS (delta §6a): toggle emitter i on/off; set its stamp channel (from the EDIT popover).
    func toggleEmitter(_ i: Int) {
        guard let au else { return }
        au.setBusEnabled(i, !(i < busEnabled.count ? busEnabled[i] : true))
        busEnabled = au.uiBusEnabled()
    }
    // §6a PERFORM velocity override: while a fader is touched, force emitter i to `v` (1–127); nil on
    // release springs it back to natural velocity. Ephemeral — nothing is written to the document.
    func setVelOverride(_ i: Int, _ v: Int?) {
        // §4b FADER-KILL: the fader's bottom sends 0 = KILL (full silence). 1–127 = velocity override; nil = release.
        if v == 0 { au?.setEmitterVelKill(i, true); au?.setVelOverride(i, nil) }
        else { au?.setEmitterVelKill(i, false); au?.setVelOverride(i, v) }
    }
    // delta §9 item 11: RECEIVERS panel edits — input mute (undoable). Channel filter / input cable / latch mode
    // now live on the cog page (CogPage.swift → au.setReceiverChannel/Cable/LatchAdd directly). MPE is silent
    // auto-detect (user ruling 2026-07-25) — no control.
    func toggleReceiverMute(_ i: Int) { au?.toggleReceiverMute(i); receivers = au?.uiReceivers() ?? receivers }
    func setThru(_ i: Int) { au?.setThruReceiver(i); thruReceiver = au?.uiThruReceiver() ?? thruReceiver }
    // receiver strip: additive SOLO (toggle a receiver in/out of the set). Ephemeral weather — the engine
    // gate is `audible = ¬muted ∧ (soloSet=∅ ∨ member)`; the whole set clears on transport stop.
    func toggleReceiverSolo(_ i: Int) {
        guard (0..<4).contains(i) else { return }
        soloReceiverMask ^= UInt8(1 << i)
        au?.setSoloReceiverMask(soloReceiverMask)
    }
    // receiver strip: ±octave nudge (±1 per tap, clamp ±3). Ephemeral, composes with the colour transpose.
    func nudgeReceiverOctave(_ i: Int, _ delta: Int) {
        guard (0..<4).contains(i) else { return }
        receiverOctave[i] = max(-3, min(3, receiverOctave[i] + delta))
        au?.setInputOctave(i, receiverOctave[i])
    }
    // receiver strip: the slider's momentary input-velocity override (touch = absolute, release = nil → spring).
    func setReceiverVel(_ i: Int, _ value: Int?) { au?.setInputVelOverride(i, value) }
    // receiver strip: per-receiver chord LATCH (additive toggle). Arm = detect-and-hold; a new chord replaces;
    // disarm releases (physical holds persist). PERFORM-only ⇒ clears on the EDIT switch as well as stop.
    func toggleReceiverLatch(_ i: Int) {
        guard (0..<4).contains(i) else { return }
        latchMask ^= UInt8(1 << i)
        au?.setLatchArm(latchMask)
    }
    func clearReceiverLatch() { if latchMask != 0 { latchMask = 0; au?.setLatchArm(0) } }
    /// Clear the receiver-strip PERFORM overlays (weather) — fired on the transport play→stop edge.
    func clearReceiverPerform() {
        soloReceiverMask = 0; au?.setSoloReceiverMask(0)
        receiverOctave = [0, 0, 0, 0]; for i in 0..<4 { au?.setInputOctave(i, 0); au?.setInputVelOverride(i, nil) }
        clearReceiverLatch()
    }

    // §6a CLAIM v2: tap an emitter's CLAIM button → toggle it in/out of the claim set (multi-claim, no longer
    // a radio); vertical drag sets its LEAK % (the bleed-through). Persisted (the AU toggles + rebuilds).
    func setClaim(_ i: Int) {
        guard let au else { return }
        au.setClaim(i)
        claimMask = au.uiClaimMask()
        thruReceiver = au.uiThruReceiver()
    }
    func setClaimLeak(_ i: Int, _ pct: Int) {
        guard let au else { return }
        au.setClaimLeak(i, pct)
        claimLeak = au.uiClaimLeak()
    }
    // role family: FLATTEN (persisted) — tap toggles the emitter into the ducking set; drag sets its amount %.
    func toggleFlatten(_ i: Int) {
        let on = flattenMask & (1 << UInt8(i)) != 0
        au?.setFlatten(i, !on)
        flattenMask = au?.uiFlattenMask() ?? flattenMask
    }
    func setFlatAmount(_ i: Int, _ amount: Int) {
        au?.setFlattenAmount(i, amount)
        flattenAmount = au?.uiFlattenAmount() ?? flattenAmount
    }
    // role family: ALT (persisted) — tap toggles group membership; drag sets notes-per-turn.
    func toggleAlt(_ i: Int) {
        let on = altMask & (1 << UInt8(i)) != 0
        au?.setAlt(i, !on)
        altMask = au?.uiAltMask() ?? altMask
    }
    func setAltCnt(_ i: Int, _ count: Int) {
        au?.setAltCount(i, count)
        altCount = au?.uiAltCount() ?? altCount
    }
    // master panel: MUTE (persisted, tap) / PANIC (long-press) / KEY ± (persisted per-scene) / the momentary fader.
    func toggleMasterMute() { au?.setMasterMute(!masterMute); masterMute = au?.uiMasterMute() ?? masterMute }
    func masterPanic() { au?.masterPanic() }
    func nudgeMasterKey(_ d: Int) { au?.nudgeMasterKey(d); masterKey = au?.uiMasterKey() ?? masterKey }
    func setMasterVel(_ v: Int?) {
        // §4b FADER-KILL: master fader bottom = 0 = KILL every emitter (the DJ master-down).
        if v == 0 { au?.setMasterKill(true); au?.setMasterVelOverride(nil) }
        else { au?.setMasterKill(false); au?.setMasterVelOverride(v) }
    }
    func setEmitterChannel(_ i: Int, _ ch: Int) {
        guard let au else { return }
        au.editDocument { d in
            while d.busChannels.count < 4 { d.busChannels.append(d.busChannels.count + 1) }
            d.busChannels[i] = max(1, min(16, ch))
        }
        busChannels = au.uiBusChannels()
    }

    var selected: TestSessions.Session? { TestSessions.all.first { $0.id == loadedID } }
    var sceneName: String {
        guard loadedID.hasPrefix("S"), let i = Int(loadedID.dropFirst()), i >= 1, i <= SceneFactory.scenes.count
        else { return "1–16 · the factory curriculum" }
        return SceneFactory.scenes[i - 1].name
    }

    func load(_ s: TestSessions.Session) {
        au?.loadTestSession(s)          // main thread: SwiftUI actions already are
        loadedID = s.id
    }

    /// Build stamp = the extension binary's link time. Not a compile-date macro (Swift has none);
    /// the executable's mtime is written at link, so it answers the real question — "is AUM running
    /// THIS build, or a cached older one?" (README: AU registration caches aggressively).

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(red: 0.066, green: 0.075, blue: 0.094).ignoresSafeArea()
                if editArmed {
                    editSpikePage(geo.size)   // feat/EditPageSpike: alt grid-setup surface (grid on top + inspector)
                } else {
                    // §6d ONE FLOW: the layout IS the signal path — RECEIVERS band above → the GRID → EMITTERS band
                    // below, grid-aligned. The COLOUR flow (palette + processor desk) is RETIRED — colour + chains
                    // are edited on the EDIT page now; the signal flow fills the width. Landscape/portrait identical.
                    VStack(spacing: 8) {
                        arrangementBar                         // §2: LOGO · undo/redo · ⚙ header, then the 16-scene row below
                        signalColumn(geo.size.width)           // RECEIVERS → GRID → EMITTERS (the signal flow)
                    }
                    .padding(12)
                }
                // (§6c popup dropped — processor SETTINGS are inline in the §6d layout; the floating window
                //  survives only as the future EXTERNAL AUv3-view host, added when EXTERNAL Colours arrive.)
                if showSettings {                       // §5 the cog page (overlay on the running instrument)
                    CogPage(au: au, receivers: receivers, busChannels: busChannels, d: d,
                            inAt: receiverPeakAt, outAt: emitPeakAt, mpeAt: mpeSeenAt, aboutLine: aboutLine,
                            onSetEmitterChannel: setEmitterChannel,
                            onChanged: { receivers = au?.uiReceivers() ?? receivers; busChannels = au?.uiBusChannels() ?? busChannels },
                            onClose: { showSettings = false })
                }
                if showPresets {                        // §3 the preset browser (overlay; the engine keeps running)
                    PresetBrowser(presets: presetList, factory: au?.factoryPresetNames() ?? [], current: currentPreset,
                                  onSave: savePreset, onLoad: loadPreset, onLoadFactory: loadFactoryPreset,
                                  onDelete: deletePreset, onClose: { showPresets = false })
                }
                if showCellLibrary {                    // CELL MACHINE stage-4: the cell library browser
                    CellBrowser(cells: cellLibraryList, factory: au?.factoryLibraryCells().map { $0.name } ?? [],
                                canSave: editingCell != nil,
                                onSave: saveCellNamed, onStamp: stampFromLibrary, onStampFactory: stampFromFactory,
                                onDelete: deleteLibraryCellNamed, onClose: { showCellLibrary = false })
                }
                if verbHasBanner, let v = activeVerb {   // §11 verb session banner (PLACE/DELETE/SELECT; CANCEL reverts; the
                    VStack(spacing: 0) { verbBanner(v); Spacer() }   // strips carry the ROUTE IN/OUT targets in-place now)
                }
                #if DEBUG
                if showDevLoader { devLoaderOverlay }   // hidden T-session loader (long-press the logotype)
                #endif
            }
        }
        .onChange(of: editArmed) { on in
            // MODE ROW: ADD/EDIT owns a transactional session (its baseline). Entering opens it; leaving via DONE
            // commits whatever was staged (live-previewed edits persist as one undo step) + clears transient state.
            if on {
                editMode = .addEdit
                au?.beginEditSession()
            } else {
                au?.applyEditSession()
                editMode = .addEdit; editSel = []; clearedStash = [:]; bornThisSession = []; preAdoptStash = [:]; syncAnchor()
                if editLoopMask != 0 { setEditLoop(0) }
            }
        }
        .onChange(of: selection) { sel in
            // HARD RULE: selecting a Colour ALWAYS re-points the processor desk to it. A SELECT set of ONE
            // distinct Colour sets brush = that Colour, so the COLOUR + PROCESSOR panels edit the SELECTED
            // cells' Colour (brush is the desk pointer). Multi-Colour → MIXED (handled elsewhere); empty → the
            // brush stays as-is.
            let ids = Set(sel.compactMap { scene.cells[$0.col][$0.row]?.colourID })
            if ids.count == 1, let id = ids.first, id != brush { brush = id }
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
                clearEmitterPerform()                                     // emitter strip: output OCT = weather
            }
            if nd.playing != d.playing || nd.tempo != d.tempo || nd.pass != d.pass
                || (nd.playing && (nd.beat != d.beat || nd.effColumn != d.effColumn)) { d = nd }
            let nb = au.uiBusChannels();   if nb != busChannels { busChannels = nb }
            let be = au.uiBusEnabled();    if be != busEnabled { busEnabled = be }
            let cm = au.uiClaimMask();     if cm != claimMask { claimMask = cm }
            let clk = au.uiClaimLeak();    if clk != claimLeak { claimLeak = clk }
            let th = au.uiThruReceiver();  if th != thruReceiver { thruReceiver = th }
            let fm = au.uiFlattenMask();   if fm != flattenMask { flattenMask = fm }
            let fa = au.uiFlattenAmount(); if fa != flattenAmount { flattenAmount = fa }
            let am = au.uiAltMask();       if am != altMask { altMask = am }
            let ac = au.uiAltCount();      if ac != altCount { altCount = ac }
            let mm = au.uiMasterMute();    if mm != masterMute { masterMute = mm }
            let se = au.uiScenes().map { $0.isEmpty }; if se != sceneEmpty { sceneEmpty = se }   // MULTI-SCENE strip sync
            let asi = au.uiActiveScene();  if asi != activeSceneIdx { activeSceneIdx = asi; editArmed = false }   // §cell-edit A6: a scene switch auto-closes EDIT
            let mk = au.uiMasterKey();     if mk != masterKey { masterKey = mk }
            // §6a metering: drain the per-emitter event feed and latch peaks; the meter view decays them.
            let act = au.pollEmitterActivity()
            for i in 0..<4 where i < act.events.count && act.events[i] > 0 {
                emitPeak[i] = Double(act.peak[i]) / 127.0; emitPeakAt[i] = Date()
            }
            let rin = au.pollReceiverActivity()      // §9 item 11: per-receiver INPUT metering (+ §MPE channel spread)
            for i in 0..<4 {
                if i < rin.events.count && rin.events[i] > 0 {
                    receiverPeak[i] = Double(rin.peak[i]) / 127.0; receiverPeakAt[i] = Date()
                }
                if i < rin.channels.count && mpeLikely(channelMask: rin.channels[i]) { mpeSeenAt[i] = Date() }
            }
            // item 4 VELOCITY MARKS: drain the per-note feeds, append new marks (born now), expire >250ms, cap 6.
            let emk = au.pollEmitterMarks(), rmk = au.pollReceiverMarks(), wmk = au.pollWithheldMarks(), mnow = Date()
            var markE = emitMarks, markR = recvMarks
            for i in 0..<4 {
                markE[i] = markE[i].filter { mnow.timeIntervalSince($0.born) < ($0.withheld ? 0.4 : 0.25) }
                for m in emk[i] { markE[i].append(VelMark(vel: Double(m.vel) / 127.0, col: m.col, born: mnow)) }
                for m in wmk[i] { markE[i].append(VelMark(vel: Double(m.vel) / 127.0, col: m.col, born: mnow, withheld: true)) }   // §6a the withheld tell
                if markE[i].count > 6 { markE[i] = Array(markE[i].suffix(6)) }
                markR[i] = markR[i].filter { mnow.timeIntervalSince($0.born) < 0.25 }
                for v in rmk[i] { markR[i].append(VelMark(vel: Double(v) / 127.0, col: -1, born: mnow)) }
                if markR[i].count > 6 { markR[i] = Array(markR[i].suffix(6)) }
            }
            if markE != emitMarks { emitMarks = markE }
            if markR != recvMarks { recvMarks = markR }
            // duration: the currently-held input notes per receiver (present-while-held → the MIDI-IN line + hold-while-ringing marks)
            let held = au.pollReceiverSounding().map { $0.map { Double($0) / 127.0 } }
            // ③ FADE-ON-RELEASE: a held input velocity that dropped from the set leaves a fading mark (~250ms),
            // so the receiver meter holds while sounding then fades on release (multiset-diff old held vs new).
            var rel = recvRelease
            for i in 0..<4 {
                rel[i] = rel[i].filter { mnow.timeIntervalSince($0.born) < 0.25 }
                var newCounts: [Int: Int] = [:]
                for v in (i < held.count ? held[i] : []) { newCounts[Int((v * 127).rounded()), default: 0] += 1 }
                for v in (i < recvHeld.count ? recvHeld[i] : []) {
                    let k = Int((v * 127).rounded())
                    if let c = newCounts[k], c > 0 { newCounts[k] = c - 1 } else { rel[i].append(VelMark(vel: v, col: -1, born: mnow)) }
                }
                if rel[i].count > 6 { rel[i] = Array(rel[i].suffix(6)) }
            }
            if rel != recvRelease { recvRelease = rel }
            if held != recvHeld { recvHeld = held }
            // §strips-done: the EMITTER twin — notes currently sounding per emitter (steady, cargo-tinted) + a
            // fade on release. Same multiset-diff as the receiver above, keyed on (velocity, source colour).
            let esnd = au.pollEmitterSounding()
            var eheld = [[SoundMark]](repeating: [], count: 4)
            var erel = emitRelease
            for i in 0..<4 {
                erel[i] = erel[i].filter { mnow.timeIntervalSince($0.born) < 0.25 }
                let cur = (i < esnd.count ? esnd[i] : [])
                for m in cur { eheld[i].append(SoundMark(vel: Double(m.vel) / 127.0, col: m.col)) }
                var newCounts: [Int: Int] = [:]
                for m in cur { newCounts[Int(m.vel) * 64 + Int(m.col) + 1, default: 0] += 1 }   // note-proxy key
                for old in (i < emitHeld.count ? emitHeld[i] : []) {
                    let k = Int((old.vel * 127).rounded()) * 64 + Int(old.col) + 1
                    if let c = newCounts[k], c > 0 { newCounts[k] = c - 1 }                      // still sounding
                    else { erel[i].append(VelMark(vel: old.vel, col: old.col, born: mnow)) }     // gone → fade it
                }
                if erel[i].count > 6 { erel[i] = Array(erel[i].suffix(6)) }
            }
            if erel != emitRelease { emitRelease = erel }
            if eheld != emitHeld { emitHeld = eheld }
            let nc = au.uiColours();       if nc != docColours { docColours = nc }
            let nr = au.uiReceivers();     if nr != receivers { receivers = nr }
            let ns = au.uiScene();         if ns != scene { scene = ns }
            if !tapActions.isEmpty { refreshTapMasks() }   // §9 ON TAP 4c: fire quantized onsets + expire durations
            let si = au.uiStepRateIndex(); if si != stepIndex { stepIndex = si }
            let sw = au.uiSwing();         if sw != swing { swing = sw }
            let strikes = au.pollCellStrikes()             // SEAL comet: stamp a hit time + velocity per struck cell
            if strikes.contains(where: { $0 > 0 }) {
                let now = Date(); var at = cellHitAt, vel = cellHitVel
                for i in 0..<min(64, strikes.count) where strikes[i] > 0 { at[i] = now; vel[i] = Double(strikes[i]) / 127.0 }
                cellHitAt = at; cellHitVel = vel
            }
            let sounding = au.pollCellSounding()           // SEAL comet: per-cell note-on/off gate (edge-detected)
            var newSounding = cellSounding, relAt = cellReleasedAt, gateChanged = false
            let nowG = Date()
            for i in 0..<64 {
                let on = (sounding >> UInt64(i)) & 1 == 1
                if on != newSounding[i] {
                    if !on { relAt[i] = nowG }             // falling edge → stamp the release (the spark fades from here)
                    newSounding[i] = on; gateChanged = true
                }
            }
            if gateChanged { cellSounding = newSounding; cellReleasedAt = relAt }
        }
        // §4c INVISIBLE = FROZEN: freeze every animated TimelineView (sweeps · marks · flow · emblems · dots)
        // when our plugin view is hidden or the app is backgrounded — the render engine is untouched. onAppear/
        // onDisappear catch the host showing/hiding us; the notifications catch app background/foreground.
        .environment(\.animationsPaused, animationsPaused)
        .onAppear { uiAppeared = true }
        .onDisappear { uiAppeared = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in appActive = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in appActive = true }
    }

    // MARK: - layout pieces

    // Dev-build only: a 1.2s long-press on the "8×8 STATE" logotype toggles the hidden T-session loader
    // overlay (the canned rigs for device passes). No-op in release — the loader never ships on the product face.
    func secretDevTap() {
        #if DEBUG
        showDevLoader.toggle()
        #endif
    }

    // §6d TWO FLOWS: the grid FILLS the leftover the bands don't claim (this GeometryReader), so the signal
    // flow always FITS without scrolling and the emitter band (CLAIM/faders) is never clipped — the bands keep
    // their full natural height, the grid takes the rest. Cells stay compact (≤48); reclaiming grid room is
    // §6d TWO FLOWS signal column: RECEIVERS (4 grid-rows tall, 50% width, centred) → GRID → EMITTERS (same),
    // filling the available height as 17 equal rows (4 receiver + 9 grid [key + 8] + 4 emitter). The bands are
    // half-width and centred (user 2026-07-26); GridView height = 9·cell + 24, so total = 17·cell + 30.
    func signalColumn(_ appWidth: CGFloat) -> some View {
        GeometryReader { g in
            let cell = max(18, min(48, (g.size.height - 30) / 21))   // 6 receiver + 9 grid + 6 emitter rows
            let bandH = cell * 6, half = g.size.width * 0.5   // bands are 6 grid-rows tall (+50%); 50% of grid width, centred
            VStack(spacing: 3) {
                HStack(spacing: 4) {                          // [CONTROLS] · RECEIVERS · [VISUALIZATION] — gutters tightened (SPACE-FILL)
                    controlsView.frame(maxWidth: .infinity)
                    receiversBox.frame(width: half).background(routeProbe("receivers"))   // §10 strips wear ROUTE IN faces
                    vizView.frame(maxWidth: .infinity)
                }.frame(height: bandH)
                gridBlock(cell, half)                         // `half` = the emitter section width (for the edit page's output block)
                HStack(spacing: 4) {                          // [VERB CLUSTER] · EMITTERS · MASTER
                    verbCluster.frame(maxWidth: .infinity)
                    emittersBox.frame(width: half).background(routeProbe("emitters"))     // §10 strips wear ROUTE OUT faces
                    masterView.frame(maxWidth: .infinity)
                }.frame(height: bandH)
            }
            .coordinateSpace(name: "signal")
            .overlayPreferenceValue(RouteFramesKey.self) { frames in                      // §viz routing lines while a verb is held
                if heldVerb != nil { RoutingVizOverlay(edges: vizEdges, frames: frames, cellHeight: cell) }
            }
        }
    }

    @ViewBuilder func gridBlock(_ cellHeight: CGFloat, _ emitterWidth: CGFloat) -> some View {
        if flowVariation > 0 {
            // FLOW view (item 10): the grid region becomes the flow theater. Watch-only; the desk stays live.
            FlowView(variation: flowVariation, scene: scene, colours: docColours, receivers: receivers,
                     busChannels: busChannels, busEnabled: busEnabled,
                     playColumn: d.effColumn, playing: d.playing, beat: d.beat, tempo: d.tempo,
                     stepBeats: stepBeats, emitPeak: emitPeak, receiverPeak: receiverPeak, emitMarks: emitMarks, recvMarks: recvMarks, receiverSounding: recvHeld.map { $0.max() ?? 0 })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
        HStack(spacing: 3) {
            rowRail(cellHeight, chevron: "chevron.right")   // LEFT rail — mirrors the right, points into the grid (user 2026-07-30)
            GridView(scene: scene, colours: docColours, playColumn: d.effColumn, playing: d.playing,
                     beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                     cellHeight: cellHeight, editing: false,   // demolition: the grid is PERFORM/triggers-only now
                     selCol: selCol, selRow: selRow, onTap: tapCell,
                     onAuditionStart: startAudition, onAuditionEnd: endAudition,
                     laneMask: laneMask, onLaneMask: setLane, holdLatch: holdLatch,
                     cellHitAt: cellHitAt, cellHitVel: cellHitVel,   // SEAL comet feed
                     cellSounding: cellSounding, cellReleasedAt: cellReleasedAt,   // SEAL comet gate
                     selection: selection,
                     whiteBorder: activeVerb == .place ? placedThisHold : [],   // §11 placed-this-hold cells wear a white border
                     verbInvite: verbHasBanner ? nil : activeVerb?.hue,   // PLACE/DELETE/SELECT light the chevrons only, not cells
                     routeFoci: routeFocusCells, routeIn: routeInCandidates, routeOut: routeOutCandidates,
                     tapAltMask: tapAltMask, tapMuteMask: tapMuteMask,
                     strokeActive: strokeActive, onStroke: strokeCell, onStrokeEnd: endStroke)
                .background(routeProbe("grid"))             // §viz: the grid's frame anchors the routing lines
            rowRail(cellHeight, chevron: "chevron.left")    // §11 ROW SELECT — RIGHT of the grid, always visible
        }
        }
    }
    // §11 ROW SELECT — a chevron per row, on BOTH sides of the grid, always visible (aligned past the column-
    // key row). Tapping a row applies the ACTIVE verb to that row's 8 cells (no-op if no verb is held). The
    // right rail points left, the left rail points right — both point INTO the grid. `chevron` picks which.
    func rowRail(_ cellHeight: CGFloat, chevron: String) -> some View {
        // PLACE lights the chevrons in the BRUSH colour (the cell to be placed); other verbs use the verb hue.
        let hue = activeVerb == .place ? (colourColor(brush) ?? .white) : (activeVerb?.hue ?? Color.white.opacity(0.35))
        return VStack(spacing: GridGeometry.vGap) {
            Color.clear.frame(width: 40, height: cellHeight)          // align past the column-key row
            ForEach(0..<8, id: \.self) { r in
                Image(systemName: chevron).font(.system(size: 20, weight: .heavy))
                    .foregroundColor(hue)
                    .frame(width: 40, height: cellHeight)
                    .background(RoundedRectangle(cornerRadius: 5).fill(hue.opacity(0.1)))
                    .contentShape(Rectangle())
                    .onTapGesture { if let v = activeVerb { doVerbOnRow(v, r) } }
            }
        }
    }
    // §11 apply the active verb across a whole row (all 8 columns).
    func doVerbOnRow(_ v: Verb, _ row: Int) {
        guard let au else { return }
        switch v {
        case .place: au.editScene { for c in 0..<8 { placeToggle(&$0, c, row) } }; refreshFromDocument()   // row toggle-with-memory
        case .delete: au.editScene { for c in 0..<8 { $0.deleteCellSever(col: c, row: row) } }
                      for c in 0..<8 { selection.remove(GridView.GridPos(col: c, row: row)) }; refreshFromDocument()
        case .select:
            for c in 0..<8 where scene.cells[c][row] != nil {
                let p = GridView.GridPos(col: c, row: row)
                if selection.contains(p) { selection.remove(p) } else { selection.insert(p) }
            }
        case .copy, .paste: break                           // row-scope copy/paste is deferred (ambiguous)
        }
    }
    // §11 SELECT "touching edits": recolour every selected cell to `id` (the Colour edit propagates per-Colour).
    func recolorSelection(_ id: String) {
        guard let au, !selection.isEmpty else { return }
        au.editScene { s in for p in selection { if var c = s.cells[p.col][p.row] { c.colourID = id; s.cells[p.col][p.row] = c } } }
        brush = id                                          // desk re-point: the recoloured (single-Colour) set points the desk at it
        refreshFromDocument()
    }

    // STROKES: a stroke is live while PLACE/DELETE/SELECT is held (COPY/PASTE don't stroke).
    var strokeActive: Bool { heldVerb == .place || heldVerb == .delete || heldVerb == .select }
    // Apply the HELD verb to one cell entered mid-drag. PLACE paints via placeToggle (⑥ enforced inside),
    // DELETE severs, SELECT lassos (additive; the visited-guard blocks re-toggle). The whole swathe coalesces
    // into ONE undo via strokeKey (opened on the first cell, closed by endStroke).
    func strokeCell(_ col: Int, _ row: Int) {
        guard let au, let v = heldVerb else { return }
        if strokeKey == nil { strokeSeq += 1; strokeKey = "stroke-\(strokeSeq)" }
        let pos = GridView.GridPos(col: col, row: row)
        switch v {
        case .place:
            au.editScene(coalesceKey: strokeKey) { placeToggle(&$0, col, row) }
            refreshFromDocument()
        case .delete:
            guard scene.cells[col][row] != nil else { return }
            au.editScene(coalesceKey: strokeKey) { $0.deleteCellSever(col: col, row: row) }
            selection.remove(pos); refreshFromDocument()
        case .select:
            if scene.cells[col][row] != nil { selection.insert(pos) }
        default: break
        }
    }
    func endStroke() { strokeKey = nil }

    var hint: some View {
        Text(flowVariation > 0
             ? "FLOW · \(FlowView.names[min(flowVariation, FlowView.names.count - 1)]) · comets = the PLAN · bright rings = LIVE (where notes really fired) · TAP a cell → TRACE"
             : "HOLD a verb → the grid does it (release = done; long-press = latch) · else TAP = ALT flip · HOLD cell → ON HOLD")
            .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - §cell-edit — the Cell Edit station (Phase 1: verb + primary-slot swap + identity + delete)

    /// The PRIMARY slot content: normally the sound `desk`; while EDIT is armed, the Cell Edit station CLAIMS it
    /// (B1) — a swap bar (B2) lets the user jump back to the full Colour desk. The desk is never hidden, just a
    /// tap away. Everything else on screen stays live (B3). Wraps whichever desk container each orientation uses.
    /// CHORD SPLIT (D) — a per-cell field (not Colour-side): ALL · TOP n · BOTTOM n · KEY RANGE (split + side).
    // §6d TWO FLOWS — the COLOUR flow (the treatment axis): COLOUR → ALT → PROCESSOR SELECTOR → SETTINGS.
    // LANDSCAPE stacks it top→bottom in the right column (this VStack); PORTRAIT lays it out via
    // `colourFlowBand` below the emitter band. The RECEIVERS/EMITTERS bands live on the SIGNAL flow (above/
    // below the grid), not here.
    // VISUALIZATION tenant (design item 2): the top-right flank — the picture IS the button. A compact live
    // FLOW thumbnail (intensity OFF/SUBTLE/SHOWCASE); TAP = open/close full FLOW, LONG-PRESS = cycle the view.
    // The header FLOW button retired into this. In DEBUG the slot flips to the DIAG face.
    var vizView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(flowVariation > 0 ? FlowView.names[min(flowVariation, FlowView.names.count - 1)] : "FLOW")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(flowVariation > 0 ? Color(red: 0.15, green: 0.88, blue: 0.94) : .white.opacity(0.45))
                Spacer(minLength: 0)
                vizChip(["OFF", "SUBTLE", "SHOW"][vizIntensity], lit: false) { vizIntensity = (vizIntensity + 1) % 3 }
                #if DEBUG
                vizChip("DIAG", lit: vizShowDiag) { vizShowDiag.toggle() }
                #endif
            }
            vizContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .onTapGesture { flowVariation = (flowVariation + 1) % 6 }   // cycle: grid → FLOW/CONSTELLATION/SCOPE/WATERFALL/RADAR → grid
                .onLongPressGesture { flowVariation = 0 }                   // long-press → back to the grid
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }
    @ViewBuilder var vizContent: some View {
        #if DEBUG
        if vizShowDiag { diagBox } else { vizPicture }
        #else
        vizPicture
        #endif
    }
    @ViewBuilder var vizPicture: some View {
        if vizIntensity == 0 {                       // OFF: a static door, still tappable
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04))
                Text("FLOW ▸").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            }
        } else {                                     // SUBTLE/SHOWCASE: the live mini visualiser (watch-only)
            FlowView(variation: max(1, flowVariation), thumbnail: true, scene: scene, colours: docColours, receivers: receivers,
                     busChannels: busChannels, busEnabled: busEnabled,
                     playColumn: d.effColumn, playing: d.playing, beat: d.beat, tempo: d.tempo,
                     stepBeats: stepBeats, emitPeak: emitPeak, receiverPeak: receiverPeak, emitMarks: emitMarks, recvMarks: recvMarks, receiverSounding: recvHeld.map { $0.max() ?? 0 })
                .allowsHitTesting(false)
        }
    }
    func vizChip(_ label: String, lit: Bool, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 6.5, weight: .heavy, design: .monospaced))
            .foregroundColor(lit ? .black : .white.opacity(0.5))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit ? Color(red: 0.98, green: 0.72, blue: 0.12) : Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    // CONTROLS panel: the top-left flank tenant (beside the receivers) — STEP · SWING · HOLD, moved out of
    // the (now slimmed) header.
    var controlsView: some View {
        ControlsView(stepIndex: stepIndex, swing: swing,
                     onStep: { au?.setStepRateIndex($0); refreshTiming() },
                     onSwing: { au?.setSwing($0); refreshTiming() })
    }

    // master panel: the bottom-right flank tenant (beside the emitters). Sum meter = the loudest emitter peak.
    var masterView: some View {
        MasterView(mute: masterMute, key: masterKey,
                   peak: emitPeak.max() ?? 0, peakAt: emitPeakAt.max() ?? .distantPast,
                   marks: Array(emitMarks.flatMap { $0 }.suffix(8)), holdLatch: holdLatch,
                   onMute: toggleMasterMute, onPanic: masterPanic, onKey: nudgeMasterKey, onVelOverride: setMasterVel)
    }

    var emittersBox: some View {
        OutputsView(busEnabled: busEnabled, busChannels: busChannels,
                    emitPeak: emitPeak, emitPeakAt: emitPeakAt, marks: emitMarks,
                    sounding: emitHeld, releaseMarks: emitRelease,
                    claimMask: claimMask, claimLeak: claimLeak, holdLatch: holdLatch,
                    onToggle: toggleEmitter,
                    onVelOverride: setVelOverride, onClaim: setClaim, onClaimLeak: setClaimLeak,
                    soloMask: emitterFootSolo, onToggleSolo: toggleEmitterSolo,
                    octave: emitterOctave, onOct: nudgeEmitterOctave,
                    flattenMask: flattenMask, flattenAmount: flattenAmount,
                    onToggleFlatten: toggleFlatten, onFlattenAmount: setFlatAmount,
                    altMask: altMask, altCount: altCount,
                    onToggleAlt: toggleAlt, onAltCount: setAltCnt,
                    wiring: !routeFoci.isEmpty, routeOn: routeOutBusesOn,     // §10 ROUTE OUT session face
                    onRouteOut: { toggleFocusEmitter(Bus.allCases[$0]) })
            .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)   // SPACE-FILL: fill the band
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    @ViewBuilder var receiversBox: some View {
        ReceiversView(receivers: receivers, peak: receiverPeak, peakAt: receiverPeakAt,
                      heldVels: recvHeld, releaseMarks: recvRelease, thruReceiver: thruReceiver,
                      onToggleMute: toggleReceiverMute, onSetThru: setThru,
                      soloMask: soloReceiverMask, onToggleSolo: toggleReceiverSolo,
                      latchMask: latchMask, onToggleLatch: toggleReceiverLatch,
                      latchAddMask: receivers.enumerated().reduce(UInt8(0)) { $1.offset < 4 && $1.element.latchAddResolved ? $0 | UInt8(1 << $1.offset) : $0 },
                      octave: receiverOctave, onOct: nudgeReceiverOctave,
                      onVelOverride: setReceiverVel, holdLatch: holdLatch,
                      wiring: !routeFoci.isEmpty, routeCurrent: routeInCurrentReceiver,   // §10 ROUTE IN session face
                      onRouteIn: routeInReceiver)
            .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // SPACE-FILL: fill the band
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // The dev diagnostics (a8 stuck-note monitor) as a compact VERTICAL box — sits to the RIGHT of RECEIVERS.
    var diagBox: some View {
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
    // §6d: the two PROCESSOR panels (A/B). PORTRAIT stacks them VERTICALLY (A above B, shorter) so each gets
    // full width (2026-07-27 layout); LANDSCAPE keeps them side by side (the width exists).
    // MIXED-SET law: a SELECT set spanning >1 distinct Colour has no honest Colour-level edit, so the
    // PROCESSOR panels dim to "MIXED" (cell-level edits still apply). Single-Colour (or empty→brush) = normal.
    var selectionMixed: Bool {
        Set(selection.compactMap { scene.cells[$0.col][$0.row]?.colourID }).count > 1
    }

    // (processorPanels — the retired shared-Colour A/B desk — removed with the morph layer; all processor
    //  editing is the per-cell CHAIN editor in EDIT now. ProcessorBox survives, used only in `slotMode`.)

    // Palette tap selects the desk brush (delta item 8 retired the ALT-targeting pairing gesture — a second
    // processor is now made on the B panel, not by pairing to another Colour).

    // §2 THE ARRANGEMENT BAR (extracted → ArrangementBar.swift). The VC keeps the poll + the grid's scene/
    // colours: it feeds the bar the polled sceneEmpty/activeSceneIdx and refreshes on `onSceneOpDone`.
    var arrangementBar: some View {
        ArrangementBar(au: au, d: d, stepBeats: stepBeats,
                       sceneEmpty: sceneEmpty, activeSceneIdx: activeSceneIdx,
                       onSecretTap: secretDevTap, onOpenSettings: { showSettings = true },
                       onRevertLiveFlips: clearOnTap, onSceneOpDone: refreshScenes,
                       currentPreset: currentPreset, onOpenPresets: openPresets,
                       canUndo: au?.uiCanUndo ?? false, canRedo: au?.uiCanRedo ?? false,   // /btw ②
                       onUndo: undo, onRedo: redo,
                       isEditMode: editArmed,                                   // the shared PERFORM/EDIT toggle
                       onSetEditMode: { on in if on { heldVerb = nil; muteArmed = false }; editArmed = on })
    }
    // §3 PRESETS wiring
    func openPresets() {
        presetList = au?.listPresets() ?? []
        currentPreset = au?.uiCurrentPreset() ?? ""
        showPresets = true
    }
    func savePreset(_ name: String) {
        au?.savePreset(named: name)
        presetList = au?.listPresets() ?? []
        currentPreset = au?.uiCurrentPreset() ?? ""
    }
    func loadPreset(_ name: String) {
        au?.loadPreset(named: name)
        refreshFromDocument()
        receivers = au?.uiReceivers() ?? receivers
        currentPreset = au?.uiCurrentPreset() ?? ""
        showPresets = false
    }
    func loadFactoryPreset(_ name: String) {        // §3 read-only DEFAULT / curriculum
        au?.loadFactoryPreset(named: name)
        refreshFromDocument()
        receivers = au?.uiReceivers() ?? receivers
        currentPreset = au?.uiCurrentPreset() ?? ""
        showPresets = false
    }
    func deletePreset(_ name: String) {
        au?.deletePreset(named: name)
        presetList = au?.listPresets() ?? []
        currentPreset = au?.uiCurrentPreset() ?? ""
    }


    // §5 THE COG PAGE → CogPage.swift (the full MIDI I/O rig config: input cable/channel/latch/MPE + emitter
    //  channel, live activity + MPE-detect indicators). `showSettings` gates it; the ⚙ in the bar opens it.
    var aboutLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "8×8 STATE · MidiSpark engine · v\(v)"
    }
    func refreshScenes() {
        guard let au else { return }
        let se = au.uiScenes().map { $0.isEmpty }; if se != sceneEmpty { sceneEmpty = se }
        let a = au.uiActiveScene(); if a != activeSceneIdx { activeSceneIdx = a }
        scene = au.uiScene(); docColours = au.uiColours()   // the grid follows the switched scene
    }

    // Dev-only: the canned TestSessions loader (portrait scroll; not part of the release strip).
    // a8 stuck-note monitor (dev): the open-voices dump + the assert-on-silence self-heal count. PANICS > 0
    // means a stuck note was caught and force-cleared in the provably-silent state — a latent bug to chase.
    var stuckNoteMonitor: some View {
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

    // Dev-build only: the hidden overlay revealed by a long-press on the logotype — the canned T-session
    // loader + the stuck-note monitor, for device passes. Tap the scrim (or ✕) to dismiss. Never in release.
    var devLoaderOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea().onTapGesture { showDevLoader = false }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("DEV — TEST SESSIONS").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text("✕").font(.system(size: 16, weight: .heavy)).foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8).contentShape(Rectangle()).onTapGesture { showDevLoader = false }
                }
                devLoader
                stuckNoteMonitor
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.10, green: 0.11, blue: 0.14)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12), lineWidth: 1))
            .padding(24)
        }
    }

    var devLoader: some View {
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

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

struct DiagView: View {
    weak var au: MidiSparkAudioUnit?
    @State private var d = KernelDiag()      // polled for the grid's effColumn / playing
    @State private var uiAppeared = true     // §4c INVISIBLE=FROZEN: this view is on-screen (host shows our plugin)
    @State private var appActive = true      // §4c: the app is foregrounded
    private var animationsPaused: Bool { !(uiAppeared && appActive) }   // hidden OR backgrounded ⇒ freeze the canvas
    @State private var loadedID = "—"
    @State private var sceneEmpty: [Bool] = []       // MULTI-SCENE: per-slot occupancy (empty ⇒ a "+" save slot)
    @State private var activeSceneIdx = 0             // MULTI-SCENE: the playing scene
    // (the arrangement bar's own interactive state — pending/recue/blink/drag/sweep-anchor/shake — lives in ArrangementBar)
    @State private var showSettings = false           // AB: the ⚙ cog page (settings overlay — engine never stops)
    @State private var showPresets = false             // §3 PRESETS: the browser sheet
    @State private var presetList: [String] = []       // §3 the user preset names (refreshed on open)
    @State private var currentPreset = ""              // §3 the loaded preset's name
    @State private var scene = SceneState.empty()
    @State private var brush = "gold"        // the paint Colour (view-local; never in the document)
    // §11b the held quasimode (SPRING-ONLY, user 2026-07-27): a verb is active ONLY while its button is pressed
    // (release = done). No latch/toggle. Nil = taps are triggers.
    @State private var heldVerb: Verb? = nil          // the currently-pressed verb
    @State private var selection: Set<GridView.GridPos> = []   // SELECT: the built set (outlives the hold)
    // /btw ①: the SESSION CLIPBOARD — COPY captures a cell here; it PERSISTS after the hold releases; PASTE
    // stamps it (PASTE is disabled while this is nil). Replaces the old per-hold moveSource/copySource.
    @State private var clipboard: Cell? = nil
    // PLACE toggle-with-restore (user 2026-07-28): re-tapping a cell placed this hold undoes it — placed-on-empty
    // → removed; placed-over-a-cell → the ORIGINAL restored (all its properties). Memory resets each PLACE hold.
    @State private var lastPlaced: GridView.GridPos? = nil      // §10 the most-recently-placed cell this PLACE hold — its routing focus
    @State private var placeFresh: Set<GridView.GridPos> = []   // placed onto an empty cell (re-tap removes)
    @State private var placeUndo: [GridView.GridPos: Cell] = [:]   // the original cell a place REPLACED (re-tap restores)
    @State private var gridSnapshot: [[Cell?]]? = nil          // the grid before this PLACE/DELETE hold — CANCEL reverts to it
    @State private var holdSeq = 0                             // /btw ④: bumps each PLACE hold → seeds the mid-hold recolour coalesce key
    @State private var strokeKey: String? = nil               // STROKES: the per-drag undo coalesce key (nil between strokes)
    @State private var strokeSeq = 0                           // STROKES: monotonic — makes each stroke's key unique
    @State private var latchedVerb: Verb? = nil               // LATCH: a long-pressed verb stays active after release (tap releases)
    @State private var latchArmed = false                     // the latching long-press's own release must not un-latch
    @State private var selectionSnapshot: Set<GridView.GridPos>? = nil   // the selection before this SELECT hold — CANCEL reverts
    private var activeVerb: Verb? { heldVerb }
    private var placedThisHold: Set<GridView.GridPos> { placeFresh.union(placeUndo.keys) }   // wear a white border
    @State private var selCol = -1
    @State private var selRow = -1
    @State private var busChannels: [Int] = [1, 2, 3, 4]
    @State private var busEnabled: [Bool] = [true, true, true, true]   // delta §6a
    @State private var claimMask: UInt8 = 0                           // delta §6a CLAIM v2: the multi-claim mask (bits A–D)
    @State private var claimLeak: [Int] = [0, 0, 0, 0]                // delta §6a CLAIM v2: per-claimant LEAK % (0…100)
    @State private var thruReceiver: Int = 0                          // receiver strip: the THRU pip (passthrough source)
    @State private var flattenMask: UInt8 = 0                         // role family: FLATTEN set (persisted)
    @State private var flattenAmount: [Int] = [0, 0, 0, 0]           // role family: per-emitter FLATTEN amount %
    @State private var altMask: UInt8 = 0                            // role family: ALT turn-taking group (persisted)
    @State private var altCount: [Int] = [1, 1, 1, 1]               // role family: per-emitter ALT notes-per-turn
    @State private var masterMute = false                           // master panel: global emission kill (persisted)
    @State private var masterKey = 0                                // master panel: per-scene transpose (persisted)
    @State private var soloReceiverMask: UInt8 = 0                    // receiver strip: additive input SOLO set (ephemeral)
    @State private var receiverOctave: [Int] = [0, 0, 0, 0]          // receiver strip: per-receiver ±octave nudge (ephemeral)
    @State private var latchMask: UInt8 = 0                          // receiver strip: per-receiver chord LATCH (ephemeral)
    @State private var procClipboard: ProcClip? = nil   // delta item 8: a lifted processor (COPY) to PASTE onto any panel
    @State private var holdLatch = false             // delta §5c: HOLD — the sustain pedal for gestures (PERFORM)
    @State private var emitPeak: [Double] = [0, 0, 0, 0]               // §6a meter: latched peak (0–1) per emitter
    @State private var emitPeakAt: [Date] = Array(repeating: .distantPast, count: 4)   // when each peak latched (for decay)
    @State private var receiverPeak: [Double] = [0, 0, 0, 0]           // §9 item 11 input meter: latched peak per receiver
    @State private var receiverPeakAt: [Date] = Array(repeating: .distantPast, count: 4)
    @State private var mpeSeenAt: [Date] = Array(repeating: .distantPast, count: 4)   // §MPE: last auto-detected per receiver
    @State private var emitMarks: [[VelMark]] = [[], [], [], []]      // item 4: floating output velocity marks (Colour-tinted)
    @State private var recvMarks: [[VelMark]] = [[], [], [], []]      // item 4: floating input velocity marks (strip hue)
    @State private var recvHeld: [[Double]] = [[], [], [], []]        // duration: currently-held input velocities per receiver (0–1)
    @State private var recvRelease: [[VelMark]] = [[], [], [], []]    // ③ marks left FADING (~250ms) as held input notes release
    @State private var docColours: [Colour] = []
    @State private var receivers: [Receiver] = []                     // delta §9 item 11: the RECEIVERS panel
    @State private var stepIndex = 2
    @State private var swing = 50
    // MODELESS (2026-07-27): GRID CONTROLS — the verb palette. Radio-armed; INSPECT is functional in 1b, the
    // others render inert until their increments land. EDIT mode survives alongside until verb coverage completes.
    @State private var flowVariation = 0       // FLOW view (item 10): 0 = grid; 1…5 cycle the visualisations
    @State private var vizIntensity = 1        // VISUALIZATION tenant: 0 = OFF · 1 = SUBTLE · 2 = SHOWCASE
    #if DEBUG
    @State private var vizShowDiag = false     // dev: the VIZ slot flips to the DIAG face (design item 2)
    #endif
    @State private var laneMask: UInt8 = 0     // §5b lap: held column keys (bit i = column i), PERFORM only
    @State private var tapAltMask: UInt64 = 0  // §9 item 1 ON TAP (unified ALT): ephemeral per-cell alt flips
    @State private var tapMuteMask: UInt64 = 0 // §9 item 1 ON TAP = MUTE: ephemeral per-cell mute
    @State private var soloEmitterMask: UInt8 = 0  // §9 item 1 ON TAP = SOLO EMITTERS: the derived emitter solo set
    @State private var emitterFootSolo: UInt8 = 0  // emitter strip: the foot SOLO button set (OR'd into the derived mask)
    @State private var emitterOctave: [Int] = [0, 0, 0, 0]   // emitter strip: per-emitter output ±octave nudge (ephemeral)
    @State private var showDevLoader = false                 // dev-build: the hidden T-session loader overlay is showing
    // §9 item 1 ON TAP quant/duration (4c): active TIMED actions. A tap adds one (onset from tapWhen, expiry
    // from tapFor); each poll derives the three ephemeral masks from the actions that are live at the beat.
    // ON-TAP overlay: TapKind/TapOverlay + the apply/mask logic are pure functions in Derivations (testable).
    @State private var tapActions: [TapOverlay] = []
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    // §5b COLUMN-SUBSET LAP: the PERFORM multi-column hold reports the held-set bitmask here. Push it to
    // the engine (ephemeral, never persisted) and keep a copy for the key LOOP highlight. Cleared to 0
    // on release (the overlay reports empty) and on the EDIT switch (see the mode toggle).
    private func setLane(_ mask: UInt8) { laneMask = mask; au?.setLaneMask(mask) }

    // EDIT/PERFORM toggle. Leaving PERFORM ends any lap (belt-and-suspenders — the overlay also cancels).

    // §9 item 1 ON TAP: clear every ephemeral perform-tap overlay (timed actions + alt flips, mutes, emitter solo).
    private func clearOnTap() {
        if !tapActions.isEmpty { tapActions.removeAll() }
        if tapAltMask != 0 { tapAltMask = 0; au?.setTapAltMask(0) }
        if tapMuteMask != 0 { tapMuteMask = 0; au?.setTapMuteMask(0) }
        if emitterFootSolo != 0 { emitterFootSolo = 0 }
        if soloEmitterMask != 0 { soloEmitterMask = 0; au?.setSoloEmitterMask(0) }
    }

    // emitter strip: additive foot SOLO — toggle a bit, then re-derive so the kernel sees the union immediately.
    private func toggleEmitterSolo(_ i: Int) {
        guard (0..<4).contains(i) else { return }
        emitterFootSolo ^= UInt8(1 << i)
        refreshTapMasks()
    }
    // emitter strip: output ±octave nudge (±1 per tap, clamp ±3). Ephemeral weather — clears on transport stop.
    private func nudgeEmitterOctave(_ i: Int, _ delta: Int) {
        guard (0..<4).contains(i) else { return }
        emitterOctave[i] = max(-3, min(3, emitterOctave[i] + delta))
        au?.setEmitterOctave(i, emitterOctave[i])
    }
    private func clearEmitterPerform() {
        emitterOctave = [0, 0, 0, 0]; for i in 0..<4 { au?.setEmitterOctave(i, 0) }
    }

    // §11b dispatch: a verb held → the tap does the verb (SELECT also routes candidates in-session); else a tap
    // is a TRIGGER (ON TAP). Routing happens WHILE SELECT is held (user 2026-07-28): the world offers wiring for
    // the selected cell, tapping a candidate wires it, RELEASE applies, CANCEL reverts.
    private func tapCell(_ col: Int, _ row: Int) {
        if let v = activeVerb { doVerb(v, col, row) } else { triggerTap(col, row) }
    }
    // §10/11c ROUTE FOCUS (multi-cell, AcceptanceCriteria 2026-07-29). PLACE: the most-recently-placed cell.
    // SELECT: EVERY column that holds EXACTLY ONE selected cell is a focus (a column with 2+ selected cells is
    // ambiguous → no routing there). Each focus lights ALL cells above it (SRC) and ALL cells below it (DEST) in
    // its own column. Release applies; CANCEL reverts.
    private var routeFoci: [Int: Int] {                  // col → focus row (at most one per column)
        if heldVerb == .place, let p = lastPlaced, scene.cells[p.col][p.row] != nil { return [p.col: p.row] }
        guard heldVerb == .select, !selection.isEmpty else { return [:] }
        var byCol: [Int: [Int]] = [:]
        for s in selection where s.col < scene.cells.count && s.row < scene.cells[s.col].count && scene.cells[s.col][s.row] != nil {
            byCol[s.col, default: []].append(s.row)
        }
        return byCol.compactMapValues { $0.count == 1 ? $0[0] : nil }   // exactly one selected in the column
    }
    private var routeFocusCells: Set<GridView.GridPos> {
        Set(routeFoci.map { GridView.GridPos(col: $0.key, row: $0.value) })
    }
    private var routeInCandidates: Set<GridView.GridPos> {   // SRC — all occupied cells ABOVE each focus, per column
        var s = Set<GridView.GridPos>()
        for (col, f) in routeFoci { for r in scene.routeInSourcesAbove(col: col, row: f) { s.insert(GridView.GridPos(col: col, row: r)) } }
        return s
    }
    private var routeOutCandidates: Set<GridView.GridPos> {  // DEST — all occupied cells BELOW each focus, per column
        var s = Set<GridView.GridPos>()
        for (col, f) in routeFoci { for r in scene.routeOutTargetsBelow(col: col, row: f) { s.insert(GridView.GridPos(col: col, row: r)) } }
        return s
    }
    // A candidate tap while routing: SRC (above the focus in its column) → the focus reads from it; DEST (below)
    // → that cell reads from the focus. Per column against routeFoci. Returns true if it wired (consumed the tap).
    @discardableResult private func wireRouteCandidate(_ pos: GridView.GridPos) -> Bool {
        guard let au, let f = routeFoci[pos.col], pos.row != f, scene.cells[pos.col][pos.row] != nil else { return false }
        if pos.row < f { au.editScene { $0.routeInRow(col: pos.col, row: f, sourceRow: pos.row) } }        // SRC above
        else           { au.editScene { $0.routeInRow(col: pos.col, row: pos.row, sourceRow: f) } }        // DEST below
        refreshFromDocument(); return true
    }
    // §10 the strips wear a SESSION FACE while wiring; a tap applies to ALL foci.
    private func routeInReceiver(_ r: Int) {
        guard !routeFoci.isEmpty else { return }
        au?.editScene { s in for (col, f) in routeFoci { s.routeInReceiver(col: col, row: f, receiver: r) } }; refreshFromDocument()
    }
    private func toggleFocusEmitter(_ b: Bus) {
        guard !routeFoci.isEmpty else { return }
        au?.editScene { s in for (col, f) in routeFoci { s.toggleEmitter(col: col, row: f, bus: b) } }; refreshFromDocument()
    }
    private var routeInCurrentReceiver: Int? {           // the receiver ALL foci share (nil ⇒ mixed / row-fed → no ring)
        var recv: Int?; var first = true
        for (col, f) in routeFoci {
            guard let cell = scene.cells[col][f] else { continue }
            let r = cell.inputRow == nil ? cell.inputReceiver : nil
            if first { recv = r; first = false } else if recv != r { return nil }
        }
        return recv
    }
    private var routeOutBusesOn: [Bool] {                // a bus reads ON only if EVERY focus enables it
        guard !routeFoci.isEmpty else { return [false, false, false, false] }
        return Bus.allCases.map { b in routeFoci.allSatisfy { (col, f) in scene.cells[col][f]?.buses.contains(b) ?? false } }
    }

    // §11 dispatch a grid tap to the active verb.
    private func doVerb(_ v: Verb, _ col: Int, _ row: Int) {
        guard let au else { return }
        let pos = GridView.GridPos(col: col, row: row)
        switch v {
        case .place:                                        // PLACE CELL(S) — toggle-with-restore; a candidate tap WIRES the focus
            if wireRouteCandidate(pos) { return }           // §10 route-as-you-place: a SRC/DEST of the last-placed cell wires it
            au.editScene { placeToggle(&$0, col, row) }
            lastPlaced = pos                                // the placed/replaced cell becomes the routing focus
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
    private func placeToggle(_ s: inout SceneState, _ col: Int, _ row: Int) {
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
        } else {                                             // fresh tap on empty → PLACE (§9.③ downhill nudge)
            placeFresh.insert(pos)
            let parentAbove = (row > 0 && s.cells[col][row - 1] != nil) ? row - 1 : nil
            var c = Cell(colourID: brush, buses: [.a]); c.inputRow = parentAbove
            if parentAbove == nil { c.inputReceiver = 0 }    // MIDI-IN cells must point at R1 (else they bypass the receiver)
            s.cells[col][row] = c
        }
    }

    // §9 item 1 ON TAP (4b/4c): the TRIGGER path — a tap runs the Colour's ON TAP action as a TIMED, EPHEMERAL
    // overlay. Never a document write; cleared on transport stop.
    private func triggerTap(_ col: Int, _ row: Int) {
        guard scene.cells[col][row] != nil, let c = scene.cells[col][row] else { return }
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
        tapActions = applyTapOverlay(tapActions, cell: idx, kind: kind, busMask: buses,
                                     onset: onset, expiry: expiry, retap: on.tapFor == .retap)
        refreshTapMasks()
    }

    // §9 item 1 ON TAP (4c): derive the three ephemeral masks from the actions live at the current beat —
    // pruning expired ones. Runs on tap AND each poll (so onsets fire + durations expire). Dedup-guarded.
    private func refreshTapMasks() {
        let r = tapOverlayMasks(tapActions, now: d.beat, footSolo: emitterFootSolo)   // pure: expire + build masks
        if r.surviving.count != tapActions.count { tapActions = r.surviving }          // only mutate @State on real expiry
        if r.alt  != tapAltMask      { tapAltMask = r.alt;        au?.setTapAltMask(r.alt) }
        if r.mute != tapMuteMask     { tapMuteMask = r.mute;      au?.setTapMuteMask(r.mute) }
        if r.solo != soloEmitterMask { soloEmitterMask = r.solo;  au?.setSoloEmitterMask(r.solo) }
    }

    // §11b THE VERB CLUSTER — six round buttons, bottom-left (thumb reach): PLACE·HOLD / DELETE·SELECT / MOVE·COPY.
    // HELD quasimode: press-hold a verb = spring-active; long-press (0.5s) = LATCH (tap again releases). HOLD is
    // the §5c gesture-latch (not a grid verb). While a verb is active a tap does the verb; else a tap is a TRIGGER.
    private var verbCluster: some View {
        VStack(spacing: 6) {
            if let v = activeVerb {
                Text(verbHint(v)).font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(v.hue).lineLimit(2).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
            }
            verbButton(.place)                             // PLACE — top, full width
            HStack(spacing: 6) { verbButton(.delete); verbButton(.select) }
            HStack(spacing: 6) { verbButton(.copy); verbButton(.paste) }   // /btw ①: COPY · PASTE (MOVE left the cluster)
            Spacer(minLength: 0)
        }
        .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func verbHint(_ v: Verb) -> String {
        switch v {
        case .place:  return "PLACE \(brush.uppercased()) — tap empties"
        case .delete: return "DELETE — tap cells (links cut)"
        case .select: return "SELECT \(selection.count) — tap to toggle"
        case .copy:   return "COPY — tap a cell to capture"
        case .paste:  return clipboard == nil ? "PASTE — copy a cell first" : "PASTE — tap to stamp"
        }
    }
    // §11b SPRING-ONLY (user 2026-07-27): the verb is active ONLY while the button is held; release = done.
    // No latch, no toggle. A plain press/release DragGesture gives exactly that.
    private func verbButton(_ v: Verb) -> some View {
        let active = activeVerb == v
        let disabled = v == .paste && clipboard == nil     // /btw ①: PASTE is inert until the clipboard holds a cell
        let badge: String? = v == .select && !selection.isEmpty ? "\(selection.count)"
            : (v == .copy && clipboard != nil) ? "•" : nil   // COPY wears a dot once something's on the clipboard
        return roundVerb(label: v.label, hue: v.hue, active: active, badge: badge)
            .opacity(disabled ? 0.4 : 1)
            .allowsHitTesting(!disabled)
            .simultaneousGesture(                              // LATCH: long-press (0.5s) locks the verb on
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    if latchedVerb != v {                      // latch this verb (replaces any prior latch)
                        if heldVerb != v { onVerbEngaged(v) }
                        heldVerb = v; latchedVerb = v; latchArmed = true
                    }
                })
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if latchedVerb == nil && heldVerb != v { heldVerb = v; onVerbEngaged(v) } }   // spring engage
                .onEnded { _ in
                    if latchedVerb == v {                      // this verb is latched
                        if latchArmed { latchArmed = false }   // the latching press's own release → keep it latched
                        else { if v == .select { selection.removeAll() }; heldVerb = nil; latchedVerb = nil }   // a tap → release (APPLY)
                    } else if latchedVerb == nil {             // spring release = APPLY (clear the stack)
                        if v == .select { selection.removeAll() }; heldVerb = nil
                    }
                })
    }
    private func onVerbEngaged(_ v: Verb) {
        switch v {                                          // snapshot the state CANCEL reverts to, per verb (clipboard PERSISTS)
        case .place:  placeFresh = []; placeUndo = [:]; lastPlaced = nil; gridSnapshot = scene.cells; holdSeq += 1
        case .delete: gridSnapshot = scene.cells
        case .select: gridSnapshot = scene.cells; selectionSnapshot = selection   // routing edits + the stack both revert
        default: break
        }
    }
    // §11 CANCEL (user 2026-07-28): revert the in-progress changes to the state when the verb was engaged AND
    // END the held status (release the button). PLACE/DELETE revert the grid; SELECT reverts the built selection.
    private var verbHasBanner: Bool { activeVerb == .place || activeVerb == .delete || activeVerb == .select }
    private func cancelVerb() {
        switch heldVerb {
        case .place, .delete, .select:                      // SELECT reverts its routing edits too (grid → prior state)
            if let au, let snap = gridSnapshot { au.editScene { $0.cells = snap }; refreshFromDocument() }
            placeFresh = []; placeUndo = [:]
        default: break
        }
        selection.removeAll()                               // CANCEL clears the stack (user 2026-07-28)
        heldVerb = nil; latchedVerb = nil                   // end the held status (and any latch)
    }
    // The verb session banner — a top overlay while PLACE/DELETE/SELECT is held; CANCEL (free hand) reverts + ends.
    private func verbBanner(_ v: Verb) -> some View {
        let text: String
        switch v {
        case .place:  text = "Place cell(s) — tap the grid or a row · choose routing"
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
    private func roundVerb(label: String, hue: Color, active: Bool, badge: String?) -> some View {
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
    private func setHold(_ on: Bool) {
        guard holdLatch != on else { return }
        holdLatch = on
        if !on {                                 // the drop: release the captures this layer owns
            au?.clearAudition(); abox.target = nil
            au?.setHoldCell(-1); abox.held = false          // §9 item 1: a latched ON HOLD drops too
            au?.setLaneMask(0); laneMask = 0     // §5c: the latched lap set drops too (velocity springs
                                                 // back via OutputsView's onChange(holdLatch))
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
    @State private var abox = AuditionBox()

    // PERFORM press-hold → ON HOLD (§9 item 1): while a cell is held (playing), its ON HOLD treatment overlays.
    // Kernel-only (no @State / re-render). (Stopped-audition retired with the editing UI — it returns via PLACE.)
    private func startAudition(_ col: Int, _ row: Int) {
        guard let au, scene.cells[col][row] != nil, d.playing else { return }
        au.setHoldCell(col * 8 + row); abox.held = true             // ON HOLD overlay (idempotent per onChanged)
    }
    private func endAudition() {                                     // release (SPRING); §5c-HOLD latch keeps it (see setHold)
        if abox.held { au?.setHoldCell(-1); abox.held = false }
    }

    // ---- PROCESSOR box: edit the selected (brush) Colour ----
    private var brushIndex: Int { colourIDs.firstIndex(of: brush) ?? 0 }
    private var brushColour: Colour? { docColours.first { $0.colourID == brush } }
    // delta item 8: does the brush Colour's procB GLIDE? (has B + same type as A = FULL). Gates the morph fader.
    private var brushGlides: Bool {
        guard let c = brushColour, let tb = c.typeB else { return false }
        return tb == c.type
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
        // §4b FADER-KILL: the fader's bottom sends 0 = KILL (full silence). 1–127 = velocity override; nil = release.
        if v == 0 { au?.setEmitterVelKill(i, true); au?.setVelOverride(i, nil) }
        else { au?.setEmitterVelKill(i, false); au?.setVelOverride(i, v) }
    }
    // delta §9 item 11: RECEIVERS panel edits — channel filter / input cable / input mute (undoable doc edits).
    // MPE is silent auto-detect (user ruling 2026-07-25) — no control.
    private func setReceiverChannel(_ i: Int, _ ch: Int) { au?.setReceiverChannel(i, ch); receivers = au?.uiReceivers() ?? receivers }
    private func setReceiverCable(_ i: Int, _ mask: Int?) { au?.setReceiverCable(i, mask); receivers = au?.uiReceivers() ?? receivers }
    private func toggleReceiverMute(_ i: Int) { au?.toggleReceiverMute(i); receivers = au?.uiReceivers() ?? receivers }
    private func setReceiverLatchAdd(_ i: Int, _ add: Bool) { au?.setReceiverLatchAdd(i, add); receivers = au?.uiReceivers() ?? receivers }   // TWO LATCH MODES
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
    // receiver strip: per-receiver chord LATCH (additive toggle). Arm = detect-and-hold; a new chord replaces;
    // disarm releases (physical holds persist). PERFORM-only ⇒ clears on the EDIT switch as well as stop.
    private func toggleReceiverLatch(_ i: Int) {
        guard (0..<4).contains(i) else { return }
        latchMask ^= UInt8(1 << i)
        au?.setLatchArm(latchMask)
    }
    private func clearReceiverLatch() { if latchMask != 0 { latchMask = 0; au?.setLatchArm(0) } }
    /// Clear the receiver-strip PERFORM overlays (weather) — fired on the transport play→stop edge.
    private func clearReceiverPerform() {
        soloReceiverMask = 0; au?.setSoloReceiverMask(0)
        receiverOctave = [0, 0, 0, 0]; for i in 0..<4 { au?.setInputOctave(i, 0); au?.setInputVelOverride(i, nil) }
        clearReceiverLatch()
    }

    // §6a CLAIM v2: tap an emitter's CLAIM button → toggle it in/out of the claim set (multi-claim, no longer
    // a radio); vertical drag sets its LEAK % (the bleed-through). Persisted (the AU toggles + rebuilds).
    private func setClaim(_ i: Int) {
        guard let au else { return }
        au.setClaim(i)
        claimMask = au.uiClaimMask()
        thruReceiver = au.uiThruReceiver()
    }
    private func setClaimLeak(_ i: Int, _ pct: Int) {
        guard let au else { return }
        au.setClaimLeak(i, pct)
        claimLeak = au.uiClaimLeak()
    }
    // role family: FLATTEN (persisted) — tap toggles the emitter into the ducking set; drag sets its amount %.
    private func toggleFlatten(_ i: Int) {
        let on = flattenMask & (1 << UInt8(i)) != 0
        au?.setFlatten(i, !on)
        flattenMask = au?.uiFlattenMask() ?? flattenMask
    }
    private func setFlatAmount(_ i: Int, _ amount: Int) {
        au?.setFlattenAmount(i, amount)
        flattenAmount = au?.uiFlattenAmount() ?? flattenAmount
    }
    // role family: ALT (persisted) — tap toggles group membership; drag sets notes-per-turn.
    private func toggleAlt(_ i: Int) {
        let on = altMask & (1 << UInt8(i)) != 0
        au?.setAlt(i, !on)
        altMask = au?.uiAltMask() ?? altMask
    }
    private func setAltCnt(_ i: Int, _ count: Int) {
        au?.setAltCount(i, count)
        altCount = au?.uiAltCount() ?? altCount
    }
    // master panel: MUTE (persisted, tap) / PANIC (long-press) / KEY ± (persisted per-scene) / the momentary fader.
    private func toggleMasterMute() { au?.setMasterMute(!masterMute); masterMute = au?.uiMasterMute() ?? masterMute }
    private func masterPanic() { au?.masterPanic() }
    private func nudgeMasterKey(_ d: Int) { au?.nudgeMasterKey(d); masterKey = au?.uiMasterKey() ?? masterKey }
    private func setMasterVel(_ v: Int?) {
        // §4b FADER-KILL: master fader bottom = 0 = KILL every emitter (the DJ master-down).
        if v == 0 { au?.setMasterKill(true); au?.setMasterVelOverride(nil) }
        else { au?.setMasterKill(false); au?.setMasterVelOverride(v) }
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
                        arrangementBar                               // §2: LOGO · scene chips · ⚙ (header + strip merged)
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
                        arrangementBar                         // §2: LOGO · scene chips · ⚙ (header + strip merged)
                        signalColumn(geo.size.width)           // RECEIVERS → GRID → EMITTERS (the signal flow)
                        colourFlowBand(geo.size.width - 24, 300)   // the treatment axis (24 = the .padding(12) both sides)
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
                if verbHasBanner, let v = activeVerb {   // §11 verb session banner (PLACE/DELETE/SELECT; CANCEL reverts; the
                    VStack(spacing: 0) { verbBanner(v); Spacer() }   // strips carry the ROUTE IN/OUT targets in-place now)
                }
                #if DEBUG
                if showDevLoader { devLoaderOverlay }   // hidden T-session loader (long-press the logotype)
                #endif
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
            let asi = au.uiActiveScene();  if asi != activeSceneIdx { activeSceneIdx = asi }
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
            let nc = au.uiColours();       if nc != docColours { docColours = nc }
            let nr = au.uiReceivers();     if nr != receivers { receivers = nr }
            let ns = au.uiScene();         if ns != scene { scene = ns }
            if !tapActions.isEmpty { refreshTapMasks() }   // §9 ON TAP 4c: fire quantized onsets + expire durations
            let si = au.uiStepRateIndex(); if si != stepIndex { stepIndex = si }
            let sw = au.uiSwing();         if sw != swing { swing = sw }
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
    private func secretDevTap() {
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
    private func signalColumn(_ appWidth: CGFloat) -> some View {
        GeometryReader { g in
            let cell = max(18, min(48, (g.size.height - 30) / 21))   // 6 receiver + 9 grid + 6 emitter rows
            let bandH = cell * 6, half = g.size.width * 0.5   // bands are 6 grid-rows tall (+50%); 50% of grid width, centred
            VStack(spacing: 3) {
                HStack(spacing: 4) {                          // [CONTROLS] · RECEIVERS · [VISUALIZATION] — gutters tightened (SPACE-FILL)
                    controlsView.frame(maxWidth: .infinity)
                    receiversBox.frame(width: half)           // §10 strips wear ROUTE IN faces in-place while wiring
                    vizView.frame(maxWidth: .infinity)
                }.frame(height: bandH)
                gridBlock(cell)
                HStack(spacing: 4) {                          // [VERB CLUSTER] · EMITTERS · MASTER
                    verbCluster.frame(maxWidth: .infinity)
                    emittersBox.frame(width: half)            // §10 strips wear ROUTE OUT faces in-place while wiring
                    masterView.frame(maxWidth: .infinity)
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
                     stepBeats: stepBeats, emitPeak: emitPeak, receiverPeak: receiverPeak, emitMarks: emitMarks, recvMarks: recvMarks, receiverSounding: recvHeld.map { $0.max() ?? 0 })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
        HStack(spacing: 3) {
            GridView(scene: scene, colours: docColours, playColumn: d.effColumn, playing: d.playing,
                     beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                     cellHeight: cellHeight, editing: false,   // demolition: the grid is PERFORM/triggers-only now
                     selCol: selCol, selRow: selRow, onTap: tapCell,
                     onAuditionStart: startAudition, onAuditionEnd: endAudition,
                     laneMask: laneMask, onLaneMask: setLane, holdLatch: holdLatch,
                     selection: selection,
                     whiteBorder: activeVerb == .place ? placedThisHold : [],   // §11 placed-this-hold cells wear a white border
                     verbInvite: verbHasBanner ? nil : activeVerb?.hue,   // PLACE/DELETE/SELECT light the chevrons only, not cells
                     routeFoci: routeFocusCells, routeIn: routeInCandidates, routeOut: routeOutCandidates,
                     tapAltMask: tapAltMask, tapMuteMask: tapMuteMask,
                     strokeActive: strokeActive, onStroke: strokeCell, onStrokeEnd: endStroke)
            rowRail(cellHeight)                             // §11 ROW SELECT — RIGHT of the grid, always visible
        }
        }
    }
    // §11 ROW SELECT — a left-pointing chevron per row, RIGHT of the grid, always visible (aligned past the
    // column-key row). Tapping a row applies the ACTIVE verb to that row's 8 cells (no-op if no verb is held).
    private func rowRail(_ cellHeight: CGFloat) -> some View {
        // PLACE lights the chevrons in the BRUSH colour (the cell to be placed); other verbs use the verb hue.
        let hue = activeVerb == .place ? (colourColor(brush) ?? .white) : (activeVerb?.hue ?? Color.white.opacity(0.35))
        return VStack(spacing: GridGeometry.vGap) {
            Color.clear.frame(width: 40, height: cellHeight)          // align past the column-key row
            ForEach(0..<8, id: \.self) { r in
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .heavy))
                    .foregroundColor(hue)
                    .frame(width: 40, height: cellHeight)
                    .background(RoundedRectangle(cornerRadius: 5).fill(hue.opacity(0.1)))
                    .contentShape(Rectangle())
                    .onTapGesture { if let v = activeVerb { doVerbOnRow(v, r) } }
            }
        }
    }
    // §11 apply the active verb across a whole row (all 8 columns).
    private func doVerbOnRow(_ v: Verb, _ row: Int) {
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
    private func recolorSelection(_ id: String) {
        guard let au, !selection.isEmpty else { return }
        au.editScene { s in for p in selection { if var c = s.cells[p.col][p.row] { c.colourID = id; s.cells[p.col][p.row] = c } } }
        brush = id                                          // desk re-point: the recoloured (single-Colour) set points the desk at it
        refreshFromDocument()
    }

    // STROKES: a stroke is live while PLACE/DELETE/SELECT is held (COPY/PASTE don't stroke).
    private var strokeActive: Bool { heldVerb == .place || heldVerb == .delete || heldVerb == .select }
    // Apply the HELD verb to one cell entered mid-drag. PLACE paints via placeToggle (⑥ enforced inside),
    // DELETE severs, SELECT lassos (additive; the visited-guard blocks re-toggle). The whole swathe coalesces
    // into ONE undo via strokeKey (opened on the first cell, closed by endStroke).
    private func strokeCell(_ col: Int, _ row: Int) {
        guard let au, let v = heldVerb else { return }
        if strokeKey == nil { strokeSeq += 1; strokeKey = "stroke-\(strokeSeq)" }
        let pos = GridView.GridPos(col: col, row: row)
        switch v {
        case .place:
            au.editScene(coalesceKey: strokeKey) { placeToggle(&$0, col, row) }
            lastPlaced = pos; refreshFromDocument()
        case .delete:
            guard scene.cells[col][row] != nil else { return }
            au.editScene(coalesceKey: strokeKey) { $0.deleteCellSever(col: col, row: row) }
            selection.remove(pos); refreshFromDocument()
        case .select:
            if scene.cells[col][row] != nil { selection.insert(pos) }
        default: break
        }
    }
    private func endStroke() { strokeKey = nil }

    // /btw ④: a mid-PLACE-hold palette pick switches the brush AND RETRO-REPAINTS — every cell placed THIS hold
    // recolours to the new brush, the brush-tinted PLACE chevrons follow, and the processor desk switches to
    // that colour (brush is the desk pointer). Coalesced per hold so repeated chip switches are one undo entry;
    // CANCEL still reverts the whole hold via gridSnapshot.
    private func repaintHoldToBrush(_ id: String) {
        brush = id
        guard let au, !placedThisHold.isEmpty else { return }
        au.editScene(coalesceKey: "place-recolor-\(holdSeq)") { s in
            for p in placedThisHold where s.cells[p.col][p.row] != nil {
                s.cells[p.col][p.row]!.colourID = id
            }
        }
        refreshFromDocument()
    }

    private var hint: some View {
        Text(flowVariation > 0
             ? "FLOW · \(FlowView.names[min(flowVariation, FlowView.names.count - 1)]) · comets = the PLAN · bright rings = LIVE (where notes really fired) · TAP a cell → TRACE"
             : "HOLD a verb → the grid does it (release = done; long-press = latch) · else TAP = ALT flip · HOLD cell → ON HOLD")
            .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // §6d TWO FLOWS — the COLOUR flow (the treatment axis): COLOUR → ALT → PROCESSOR SELECTOR → SETTINGS.
    // LANDSCAPE stacks it top→bottom in the right column (this VStack); PORTRAIT lays it out via
    // `colourFlowBand` below the emitter band. The RECEIVERS/EMITTERS bands live on the SIGNAL flow (above/
    // below the grid), not here.
    private var identityColumn: some View {
        // LANDSCAPE (user rev 2026-07-27): COLOUR · A · B STACKED top-to-bottom in the narrow right column.
        VStack(spacing: 8) {
            colourBox
            processorPanels(vertical: true)   // procA above procB (stacked)
        }
    }

    // delta item 8 (portrait): the COLOUR flow — the treatment axis, separate from the signal flow (whose
    // RECEIVERS/EMITTERS bands flank the grid above). The two PROCESSOR PANELS (procA | procB) sit here; each
    // is a fixed frame sized for the largest field set, so truncation dies by geometry.
    private func colourFlowBand(_ width: CGFloat, _ height: CGFloat) -> some View {
        let gap: CGFloat = 8
        let avail = max(0, width - gap)
        // PORTRAIT (user rev 2026-07-27): COLOUR · PROCESSOR A · PROCESSOR B all on ONE ROW (the wide-short band),
        // palette on the left, the two panels side by side taking the rest.
        return HStack(alignment: .top, spacing: gap) {
            colourBox.frame(width: min(160, avail * 0.28))
            processorPanels(vertical: false).frame(maxWidth: .infinity)
        }
        .frame(height: height)
    }

    // VISUALIZATION tenant (design item 2): the top-right flank — the picture IS the button. A compact live
    // FLOW thumbnail (intensity OFF/SUBTLE/SHOWCASE); TAP = open/close full FLOW, LONG-PRESS = cycle the view.
    // The header FLOW button retired into this. In DEBUG the slot flips to the DIAG face.
    private var vizView: some View {
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
    @ViewBuilder private var vizContent: some View {
        #if DEBUG
        if vizShowDiag { diagBox } else { vizPicture }
        #else
        vizPicture
        #endif
    }
    @ViewBuilder private var vizPicture: some View {
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
    private func vizChip(_ label: String, lit: Bool, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 6.5, weight: .heavy, design: .monospaced))
            .foregroundColor(lit ? .black : .white.opacity(0.5))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit ? Color(red: 0.98, green: 0.72, blue: 0.12) : Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    // CONTROLS panel: the top-left flank tenant (beside the receivers) — STEP · SWING · HOLD, moved out of
    // the (now slimmed) header.
    private var controlsView: some View {
        ControlsView(stepIndex: stepIndex, swing: swing, holdLatch: holdLatch,
                     onStep: { au?.setStepRateIndex($0); refreshTiming() },
                     onSwing: { au?.setSwing($0); refreshTiming() },
                     onToggleHold: toggleHold)
    }

    // master panel: the bottom-right flank tenant (beside the emitters). Sum meter = the loudest emitter peak.
    private var masterView: some View {
        MasterView(mute: masterMute, key: masterKey,
                   peak: emitPeak.max() ?? 0, peakAt: emitPeakAt.max() ?? .distantPast,
                   marks: Array(emitMarks.flatMap { $0 }.suffix(8)), holdLatch: holdLatch,
                   onMute: toggleMasterMute, onPanic: masterPanic, onKey: nudgeMasterKey, onVelOverride: setMasterVel)
    }

    private var emittersBox: some View {
        OutputsView(busEnabled: busEnabled, busChannels: busChannels, editing: false,
                    emitPeak: emitPeak, emitPeakAt: emitPeakAt, marks: emitMarks,
                    claimMask: claimMask, claimLeak: claimLeak, holdLatch: holdLatch,
                    onToggle: toggleEmitter, onSetChannel: setEmitterChannel,
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

    @ViewBuilder private var receiversBox: some View {
        ReceiversView(receivers: receivers, editing: false, peak: receiverPeak, peakAt: receiverPeakAt,
                      heldVels: recvHeld, releaseMarks: recvRelease, thruReceiver: thruReceiver,
                      onSetChannel: setReceiverChannel, onToggleMute: toggleReceiverMute,
                      onSetCable: setReceiverCable, onSetThru: setThru,
                      soloMask: soloReceiverMask, onToggleSolo: toggleReceiverSolo,
                      latchMask: latchMask, onToggleLatch: toggleReceiverLatch,
                      latchAddMask: receivers.enumerated().reduce(UInt8(0)) { $1.offset < 4 && $1.element.latchAddResolved ? $0 | UInt8(1 << $1.offset) : $0 },
                      onSetLatchAdd: setReceiverLatchAdd,
                      octave: receiverOctave, onOct: nudgeReceiverOctave,
                      onVelOverride: setReceiverVel, holdLatch: holdLatch,
                      wiring: !routeFoci.isEmpty, routeCurrent: routeInCurrentReceiver,   // §10 ROUTE IN session face
                      onRouteIn: routeInReceiver)
            .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // SPACE-FILL: fill the band
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
                        onPick: { id in                          // /btw ④ PLACE-hold: retro-repaint; SELECT: recolour the set; else set brush
                            if activeVerb == .place { repaintHoldToBrush(id) }
                            else if !selection.isEmpty { recolorSelection(id) }
                            else { pickPalette(id) }
                        })
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
    // §6d: the two PROCESSOR panels (A/B). PORTRAIT stacks them VERTICALLY (A above B, shorter) so each gets
    // full width (2026-07-27 layout); LANDSCAPE keeps them side by side (the width exists).
    // MIXED-SET law: a SELECT set spanning >1 distinct Colour has no honest Colour-level edit, so the
    // PROCESSOR panels dim to "MIXED" (cell-level edits still apply). Single-Colour (or empty→brush) = normal.
    private var selectionMixed: Bool {
        Set(selection.compactMap { scene.cells[$0.col][$0.row]?.colourID }).count > 1
    }

    @ViewBuilder private func processorPanels(vertical: Bool) -> some View {
        if let bc = brushColour {
            let h: CGFloat = vertical ? 200 : ProcessorBox.panelHeight
            let mixed = selectionMixed
            let a = ProcessorBox(colour: bc, colourIndex: brushIndex, face: .a,
                                 onEdit: editBrushColour, onTranspose: setBrushTranspose, onMorph: setBrushMorph,
                                 onSetTypeA: setBrushType, canPaste: procClipboard != nil,
                                 onCopy: { copyProc(.a) }, onPaste: { pasteProc(.a) }, height: h, mixed: mixed)
            let b = ProcessorBox(colour: bc, colourIndex: brushIndex, face: .b,
                                 onEdit: editBrushColour, onTranspose: setBrushTranspose, onMorph: setBrushMorph,
                                 canPaste: procClipboard != nil,
                                 onCopy: { copyProc(.b) }, onPaste: { pasteProc(.b) }, height: h, mixed: mixed)
            if vertical {
                VStack(spacing: 8) { a; b }
            } else {
                HStack(alignment: .top, spacing: 8) { a.frame(maxWidth: .infinity); b.frame(maxWidth: .infinity) }
            }
        }
    }

    // Palette tap selects the desk brush (delta item 8 retired the ALT-targeting pairing gesture — a second
    // processor is now made on the B panel, not by pairing to another Colour).
    private func pickPalette(_ id: String) { brush = id }

    // §2 THE ARRANGEMENT BAR (extracted → ArrangementBar.swift). The VC keeps the poll + the grid's scene/
    // colours: it feeds the bar the polled sceneEmpty/activeSceneIdx and refreshes on `onSceneOpDone`.
    private var arrangementBar: some View {
        ArrangementBar(au: au, d: d, stepBeats: stepBeats,
                       sceneEmpty: sceneEmpty, activeSceneIdx: activeSceneIdx,
                       onSecretTap: secretDevTap, onOpenSettings: { showSettings = true },
                       onRevertLiveFlips: clearOnTap, onSceneOpDone: refreshScenes,
                       currentPreset: currentPreset, onOpenPresets: openPresets,
                       canUndo: au?.uiCanUndo ?? false, canRedo: au?.uiCanRedo ?? false,   // /btw ②
                       onUndo: undo, onRedo: redo)
    }
    // §3 PRESETS wiring
    private func openPresets() {
        presetList = au?.listPresets() ?? []
        currentPreset = au?.uiCurrentPreset() ?? ""
        showPresets = true
    }
    private func savePreset(_ name: String) {
        au?.savePreset(named: name)
        presetList = au?.listPresets() ?? []
        currentPreset = au?.uiCurrentPreset() ?? ""
    }
    private func loadPreset(_ name: String) {
        au?.loadPreset(named: name)
        refreshFromDocument()
        receivers = au?.uiReceivers() ?? receivers
        currentPreset = au?.uiCurrentPreset() ?? ""
        showPresets = false
    }
    private func loadFactoryPreset(_ name: String) {        // §3 read-only DEFAULT / curriculum
        au?.loadFactoryPreset(named: name)
        refreshFromDocument()
        receivers = au?.uiReceivers() ?? receivers
        currentPreset = au?.uiCurrentPreset() ?? ""
        showPresets = false
    }
    private func deletePreset(_ name: String) {
        au?.deletePreset(named: name)
        presetList = au?.listPresets() ?? []
        currentPreset = au?.uiCurrentPreset() ?? ""
    }

    // §5 THE COG PAGE → CogPage.swift (the full MIDI I/O rig config: input cable/channel/latch/MPE + emitter
    //  channel, live activity + MPE-detect indicators). `showSettings` gates it; the ⚙ in the bar opens it.
    private var aboutLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "8×8 STATE · MidiSpark engine · v\(v)"
    }
    private func refreshScenes() {
        guard let au else { return }
        let se = au.uiScenes().map { $0.isEmpty }; if se != sceneEmpty { sceneEmpty = se }
        let a = au.uiActiveScene(); if a != activeSceneIdx { activeSceneIdx = a }
        scene = au.uiScene(); docColours = au.uiColours()   // the grid follows the switched scene
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

    // Dev-build only: the hidden overlay revealed by a long-press on the logotype — the canned T-session
    // loader + the stuck-note monitor, for device passes. Tap the scrim (or ✕) to dismiss. Never in release.
    private var devLoaderOverlay: some View {
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

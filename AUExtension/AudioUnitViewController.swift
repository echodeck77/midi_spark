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
    case place = "PLACE", delete = "DELETE", copy = "COPY", paste = "PASTE"   // SELECT retired 2026-08-05 (layout-v2)
    var label: String { self == .place ? "PLACE CELL(S)" : rawValue }
    var hue: Color {
        switch self {
        case .place:  return Color(red: 0.35, green: 0.92, blue: 0.50)   // green — additive
        case .delete: return UI.red   // red — destructive
        case .copy:   return Color(red: 0.70, green: 0.55, blue: 0.98)   // violet — capture
        case .paste:  return UI.amber   // amber — stamp
        }
    }
}

/// The EDIT page's tap modes. ADD/EDIT builds a live-edited selection set (the ONLY mode with APPLY/CANCEL
/// staging); MOVE drags cells to new positions; MUTE toggles per-cell mute; CLEAR removes a cell (re-tap the
/// empty slot to reinstate, while still in CLEAR). Everything except ADD/EDIT is IMMEDIATE + undo/redo.
enum EditPageMode { case addEdit, move, mute, clear }

/// LAYOUT v2 (2026-08-05): the permanent surface addresses — a tab per surface, replacing the PERFORM/EDIT toggle
/// and the in-grid overlays. GRID = the perform desk · PROCESSORS = the cell edit page · RECEIVERS = per-door config
/// (from the cog) · EMITTERS = the RACK matrix · MACROS/AUTOMATION = dimmed 'coming' seats (phase 2+).
enum AppTab: String, CaseIterable {
    case build = "BUILD"          // THE BUILD PAGE (design: two-grid-flow, user 2026-08-11) — the primary workshop; SUPERSEDED + removed the DRAG&DROP + PROCESSORS pages (user 2026-08-13)
    case grid = "GRID", receivers = "MIDI IN", emitters = "MIDI OUT"
    case macros = "MACROS", automation = "AUTOMATION"
    var live: Bool { self != .macros && self != .automation }
}

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
    @State var activeTab: AppTab = .build     // BUILD is the default landing page (user 2026-08-11); the AnyView boundaries fixed the metadata-stack crash
    // BUILD page (user 2026-08-11): the selected PART's cast colour (index into the part palette; −1 = none). Placement-skeleton state.
    @State var buildSelReceiver: Int = 0      // BUILD left column: the INPUT door (R1–R4) the machine's INPUT face edits
    // BUILD verbs (iteration 4: drag retires → PLACE · MOVE · DELETE spring-held verbs). The armed verb (nil = none).
    @State var buildRowMode: BuildRowMode = .select  // STAGING grid: what its left row buttons do (SELECT · MUTATE; PLACE retired from the centre column — Paul 2026-08-17)
    @State var buildPlaceArmed: Bool = false         // PLAY-grid PLACE mode — a standalone toggle (NOT the staging radio); armed from the left PLACE button
    @State var buildFlattenMode: Bool = false        // FLATTEN toggle (default OFF): ON = the valve/part-button play grid · OFF = plain row-master chevrons + hidden right column
    @State var buildPlaceMsg: String? = nil          // the processor pop-up's PLACE feedback line ("added to row 6 — 2 remaining")
    @State var buildEditSlot: Int? = nil        // BUILD footer: which chain slot's processor pop-up editor is open (nil = closed)
    @State var buildAddSlot: Int? = nil         // BUILD footer: which empty box's ADD-PROCESSOR picker is open (nil = closed)
    @State var buildRowUnder: [String?] = Array(repeating: nil, count: 8)   // one-colour-per-row: each row's revert-to colour when its colour relocates
    @State var buildPlayMode: BuildGridMode = .edit      // the play grid's PLAY/EDIT radio
    @State var buildDeletedRows: [Int: [String?]] = [:]  // DELETE verb: a staging row's saved contents (for restore on 2nd press)
    @State var buildPlacedOrig: [Int: String?] = [:]     // PLACE verb: a cell's content BEFORE it was placed (for revert on 2nd tap), keyed c*8+r
    @State var buildStagingSel: [Int] = Array(repeating: -1, count: 8)   // the ONE selected (playing) row per staging COLUMN (white outline); -1 = none
    @State var buildRowChain: [[ProcessorSlot]] = Array(repeating: [], count: 8)   // STAGE THE GRID: the generated machine (chain) for each row (empty = not a staged row)
    @State var buildRowShade: [Double] = Array(repeating: 0, count: 8)   // STAGE THE GRID: per-row shade of the selected colour (+lighter … −darker), by output complexity
    @State var buildPulseColourID: String? = nil   // a touched grid cell's colour, offered as a PULSING candidate in the last free palette slot (nil = none)
    @State var buildPulseChain: [ProcessorSlot] = []   // the candidate's machine (for a staged variation cell); empty → use the colour's own chain
    @State var buildParts: [BuildPart] = [BuildPart()]   // the PARTS (workshop lifecycle); the CURRENT part's fields live in the working @State below, synced on switch
    @State var buildCurrentPart: Int = 0                 // index of the part currently on the build column
    @State var buildReturnPart: Int? = nil               // QoL: the UNDEFINED bench to auto-return to after promoting a restored part (Paul 2026-08-15)
    @State var buildPartEmitters: Set<Bus> = [.a]        // the CURRENT part's output emitters (part-owned I/O; every colour follows)
    @State var buildPartCast: [String] = []              // the CURRENT part's cast MEMBERSHIP (visible palette over the global store); §2 cast view
    @State var buildCastSlots: [Int: String] = [:]       // §2 explicit slot→colourID for non-default colours (long-press places a colour on its pressed cell)
    @State var buildAuditionID: String? = nil            // the standing uncommitted "create a duplicate" candidate (ephemeral), auditioned after a PLACE
    @State var buildCastSeeded: Bool = false             // seed part 1's cast from the already-defined colours ONCE on first BUILD appear
    @State var buildPendingTab: Int? = nil               // the ONE pending (copied-unedited, PULSING) tab; nil = none
    @State var buildRandomizing = false                  // the grid RANDOMIZE is computing (disable its button)
    @State var buildMutating = false                     // the grid MUTATE is computing (disable its button)
    // PER-ROW I/O (Paul 2026-08-18): each staging row can override the part's default door/emitters; nil = inherit.
    @State var buildRowReceiver: [Int?] = Array(repeating: nil, count: 8)
    @State var buildRowEmitters: [Set<Bus>?] = Array(repeating: nil, count: 8)
    @State var buildPendingSource: [ProcessorSlot] = []  // the chain the pending tab was copied from — diverge = PLACED
    // THE PIECE — the perform (play) grid: deployed parts, ONE ROW per part (deployment order). Each cell keeps its
    // colourID + optional variation chain + the deploying part's I/O, so START/STOP THE PLAY GRID plays the assembly.
    @State var buildPerformCells: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    @State var buildPerformChain: [[[ProcessorSlot]]] = Array(repeating: Array(repeating: [], count: 8), count: 8)
    @State var buildPerformRecv: [Int] = Array(repeating: 0, count: 8)          // per perform-ROW input door
    @State var buildPerformEmit: [Set<Bus>] = Array(repeating: [.a], count: 8)  // per perform-ROW emitters
    @State var buildPerformPlaying: Bool = false                                // the PIECE is the active voice
    @State var buildPerformPart: [Int] = Array(repeating: -1, count: 8)         // which PART index sits in each perform row (§2 brightness: the current part's band lights bright)
    @State var buildPerformMute: Set<Int> = []                                  // play grid: per-cell MUTE (key c*8+r) — single-rung parts only, drops a step from the mix (Paul 2026-08-15)
    @State var buildPerformStagingRow: [Int] = Array(repeating: -1, count: 8)   // play grid: each MULTI-rung grid row ← its source staging row (−1 = single-rung/none). Maps play-grid rung selection back to the part's stagingSel (Paul 2026-08-15)
    @State var buildFlowOpen: Bool = false      // BUILD footer eye → the signal-flow diagram pop-up
    @State var buildGridPopup: Int? = nil        // BUILD grid eye → a full-screen grid pop-up (0 = staging, 1 = perform; nil = closed)
    // BUILD staging grid — an EPHEMERAL workshop store ([col][row] → colourID; nil = blank). Not the real scene; the
    // engine-backed ephemeral staging document + audition is a later slice. PLACE stocks a colour here.
    @State var buildStagingCells: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    // BUILD one-workshop-voice: PLAY THE STAGING GRID is active (mutually exclusive with PLAY THIS MACHINE / ddSolo).
    @State var buildStagingPlaying = false
    // BUILD workshop voice = which of the two SHOP sections sounds: the MIDI CHAIN audition, the PART grid, or NEITHER.
    // Each header toggles its own section (play ⇄ stop), so BOTH can be stopped (Paul 2026-08-15). The two never sound
    // together (picking one stops the other) — the PIECE (play grid) is independent of this.
    @State var buildPendingWorkshopVoice: BuildWorkshopVoice? = nil   // an armed voice switch, applied on the next cell boundary (nil = none)
    @State var buildPendingReengage: Bool = false      // a palette colour change made while the chain audition plays — re-engage on the next cell boundary (seamless)
    @State var ddColourSel: Int = -1          // DRAG&DROP page: the selected palette colour index (−1 = none)
    @State var buildSelID: String? = nil      // BUILD: the selected colour BY ID (supports ephemeral colours beyond the 16); nil = none
    @State var buildColourReg: [String: [ProcessorSlot]] = [:]   // BUILD: ephemeral colours' machines (id → chain), beyond the 16 document slots
    @State var buildIDCounter: Int = 0        // BUILD: monotonic source for ephemeral colour IDs ("b0", "b1", …)
    @State var ddStickyReceiver: Int = 0      // DRAG&DROP: the LAST receiver chosen on the page → the default input for a fresh cell (R1 = 0)
    @State var ddStickyBuses: Set<Bus> = [.a] // DRAG&DROP: the LAST emitters chosen on the page → the default output for a fresh cell (Emitter A)
    @State var ddBeatAnchor: Double = 0       // DRAG&DROP playhead: last polled beat + when — extrapolated for a phase-locked palette wipe
    @State var ddBeatAnchorAt: Date = Date()
    @State var ddSolo = false                  // DRAG&DROP PLAY: THIS CELL — isolate + freeze on the selected cell's column
    @State var showManual = false             // the "?" → the in-app manual overlay (scrolled to the last-touched control)
    @StateObject var helpTracker = HelpTracker()   // records the last-touched control's manual anchor (silent — no @Published)
    static let manualBlocks = ManualDoc.parse(ManualDoc.load())   // the parsed manual (once ever)
    @AppStorage("midispark.showScenes") var showScenes = false   // the scene row is HIDDEN by default; toggled on the cog page
    @AppStorage("midispark.showTabBar") var showTabBar = true     // the six-tab bar SHOWS by default; toggled on the cog page
    @State var showPresets = false             // §3 PRESETS: the browser sheet
    @State var presetList: [String] = []       // §3 the user preset names (refreshed on open)
    @State var currentPreset = ""              // §3 the loaded preset's name
    // CELL MACHINE stage-4: the CELL LIBRARY browser + the stamp mode (a saved cell awaiting placement).
    @State var showCellLibrary = false
    @State var cellLibraryFromBuild = false   // the browser was opened from the BUILD page → save/stamp target the SELECTED COLOUR's chain, not an EDIT cell
    @State var buildLibraryOriginalChain: [ProcessorSlot]? = nil   // the selected colour's chain at library-open — restored if the user leaves without APPLY
    @State var buildLibraryPreviewed = false                       // a preview temporarily overwrote the colour's chain (not yet committed)
    @State var cellLibraryList: [LibEntry] = []
    // MACRO AUTHORING FLOW (canonical, spec macro-authoring): the per-group MAIN/ALT authoring page.
    @State var macroAuthorOpen = false
    @State var macroAuthorSlot = 0
    @State var macroAuthorAnchor: (col: Int, row: Int) = (0, 0)
    @State var macroAuthorGroup: MacroControlGroup? = nil
    @State var macroAuthorBase: [String: Double] = [:]                        // the slot's current values (the offset base)
    @State var macroAuthorMacrosBaseline: [Macro] = []                        // every macro on open — CANCEL restores this
    @State var macroAuthorExisting: [MacroSlotBinding] = []                   // macros already bound to this slot — the dropdown/reflect
    // FLOW-DIAGRAM processor pop-up (user 2026-08-07): tap a populated processor box → edit its full controls; tap an
    // empty box → the type picker. APPLY keeps · CANCEL restores the document snapshot taken on open.
    @State var procEditOpen = false
    @State var procEditSlot = 0
    @State var procEditDocBaseline: PluginState? = nil
    @State var procTypePickerOpen = false
    @State var procMacroEngaged = false                                      // pop-up: the embedded macro section is open + auditioning
    @State var splitEditorOpen = false                                       // FLOW-DIAGRAM: tap the emitters' SPLIT → the output-split editor (user 2026-08-09)
    @State var scene = SceneState.empty()
    @State var brush = "gold"        // the paint Colour (view-local; never in the document)
    // §11b the held quasimode (SPRING-ONLY, user 2026-07-27): a verb is active ONLY while its button is pressed
    // (release = done). No latch/toggle. Nil = taps are triggers.
    @State var heldVerb: Verb? = nil          // the currently-pressed verb
    // /btw ①: the SESSION CLIPBOARD — COPY captures a cell here; it PERSISTS after the hold releases; PASTE
    // stamps it (PASTE is disabled while this is nil). Replaces the old per-hold moveSource/copySource.
    @State var clipboard: Cell? = nil
    // PLACE toggle-with-restore (user 2026-07-28): re-tapping a cell placed this hold undoes it — placed-on-empty
    // → removed; placed-over-a-cell → the ORIGINAL restored (all its properties). Memory resets each PLACE hold.
    @State var placeFresh: Set<GridView.GridPos> = []   // placed onto an empty cell (re-tap removes)
    @State var placeUndo: [GridView.GridPos: Cell] = [:]   // the original cell a place REPLACED (re-tap restores)
    @State var gridSnapshot: [[Cell?]]? = nil          // the grid before this PLACE/DELETE hold — CANCEL reverts to it
    @State var strokeKey: String? = nil               // STROKES: the per-drag undo coalesce key (nil between strokes)
    @State var strokeSeq = 0                           // STROKES: monotonic — makes each stroke's key unique
    var activeVerb: Verb? { heldVerb }
    var placedThisHold: Set<GridView.GridPos> { placeFresh.union(placeUndo.keys) }   // wear a white border
    @State var selCol = -1
    @State var selRow = -1
    // Cell Edit station (AcceptanceCriteria-cell-edit): EDIT is a 6th control, a TOGGLE (not a spring verb),
    // pointing the station at ONE cell (selCol/selRow) for deep editing. It is deliberately NOT a `heldVerb` —
    // `activeVerb` stays "a spring verb is held", so banners/routing-viz/candidate glow stay off for EDIT.
    @State var editArmed = false
    @State var playCellOnly = false                                          // EDIT: "play this cell only" vs "play from grid" (user 2026-08-08)
    @State var tapCoalesceKey: String? = nil                                 // ROW SELECTOR: coalesce a whole-row tap into ONE undo (user 2026-08-09)
    @State var tapSeq = 0
    // MODE ROW: the EDIT page's tap modes. ADD/EDIT builds a selection set + edits it live under APPLY/CANCEL
    // staging (the ONLY mode that stages). MOVE drags cells; MUTE toggles mute; CLEAR removes — all IMMEDIATE + undo/redo.
    @State var editMode: EditPageMode = .addEdit
    // MODE ROW — ADD/EDIT mode's multi-SELECT set (ordered; the FIRST member is the ANCHOR). Edits apply live to every
    // member; a tapped cell's TWINS auto-JOIN the set (user 2026-08-07 — history: auto-edit → pulse-only → join).
    // ADD/EDIT SELECTION (extracted 2026-08-07): one cohesive value — the selected cells + the per-session
    // bookkeeping (BORN cells deleted on deselect · ADOPTED originals stashed for restore) + the selection undo/redo
    // history. See `EditSelection` (EditPage.swift). The document effects stay in the view; this owns the state.
    @State var sel = EditSelection()
    // MODE ROW — a long-press fires its mode action ONCE per press (the underlying gesture repeats while held).
    @State var longPressFired = false
    // MODE ROW — CLEAR mode's undo stash: cells removed this CLEAR session, keyed by position. Re-tapping the now-empty
    // slot reinstates the cell. Dropped when we leave CLEAR mode (thereafter, undo/redo covers the removal).
    @State var clearedStash: [GridView.GridPos: Cell] = [:]
    // MODE ROW — the edit-page column loop drives the SAME `laneMask` as PERFORM (one engine field, one UI mirror);
    // BUG FIX 2026-08-05: no separate `editLoopMask`, so the loop survives the EDIT↔GRID page switch.
    var editingCell: Cell? { editArmed ? scene.cellAt(selCol, selRow) : nil }   // bounds-safe: a stale anchor never traps
    static let editHue = UI.editHue   // orchid — deep single-cell edit (distinct from the 5 verbs)
    @State var busChannels: [Int] = [1, 2, 3, 4]
    @State var busEnabled: [Bool] = [true, true, true, true]   // delta §6a
    @State var claimMask: UInt8 = 0                           // delta §6a CLAIM v2: the multi-claim mask (bits A–D)
    @State var claimLeak: [Int] = [0, 0, 0, 0]                // delta §6a CLAIM v2: per-claimant LEAK % (0…100)
    @State var thruReceiver: Int = 0                          // receiver strip: the THRU pip (passthrough source)
    @State var flattenMask: UInt8 = 0                         // role family: FLATTEN set (persisted)
    @State var flattenAmount: [Int] = [0, 0, 0, 0]           // role family: per-emitter FLATTEN amount %
    @State var altMask: UInt8 = 0                            // role family: ALT turn-taking group (persisted)
    @State var altCount: [Int] = [1, 1, 1, 1]               // role family: per-emitter ALT notes-per-turn
    @State var turnsPerNote = false                        // TURNS hand-off mode: false = per-moment, true = per-note (exclusive)
    @State var curveMask: UInt8 = 0                         // THE RACK CURVE: per-emitter velocity-remap set (persisted)
    @State var curveAmount: [Int] = [0, 0, 0, 0]            // THE RACK CURVE: per-emitter −100…100 bend
    @State var fenceMask: UInt8 = 0                         // THE RACK FENCE: per-emitter note-range policy set (persisted)
    @State var fencePolicy: [Int] = [0, 0, 0, 0]           // THE RACK FENCE: 0 DROP · 1 CLAMP · 2 FOLD
    @State var fenceLo: [Int] = [0, 0, 0, 0]               // THE RACK FENCE: per-emitter window low
    @State var fenceHi: [Int] = [127, 127, 127, 127]       // THE RACK FENCE: per-emitter window high
    @State var monoMask: UInt8 = 0                         // THE RACK MONO: per-emitter monophony set (persisted)
    @State var monoPriority: [Int] = [0, 0, 0, 0]         // THE RACK MONO: 0 LAST · 1 LOW · 2 HIGH
    @State var pocketMask: UInt8 = 0                       // THE RACK POCKET: per-emitter timing-shift set (persisted)
    @State var pocketMs: [Int] = [0, 0, 0, 0]             // THE RACK POCKET: per-emitter −50…50 ms
    @State var convLead: Int = -1                          // THE RACK CONVERSATION: the LEAD emitter (−1 = none)
    @State var convStance: [Int] = [0, 0, 0, 0]           // THE RACK CONVERSATION: 0 FREE · 1 WITH · 2 AGAINST
    @State var rackMask: UInt8 = 0b1111                     // THE RACK: per-emitter "board in the signal path" gate (persisted; nil-doc ⇒ all in path)
    @State var masterMute = false                           // master panel: global emission kill (persisted)
    @State var masterKey = 0                                // master panel: per-scene transpose (persisted)
    @State var soloReceiverMask: UInt8 = 0                    // receiver strip: additive input SOLO set (ephemeral)
    @State var receiverOctave: [Int] = [0, 0, 0, 0]          // receiver strip: per-receiver ±octave nudge (ephemeral)
    @State var receiverNote: [Int] = [0, 0, 0, 0]           // receiver strip: per-receiver ±semitone NOTE nudge (ephemeral)
    @State var latchMask: UInt8 = 0                          // receiver strip: per-receiver chord LATCH (ephemeral)
    @State var holdLatch = false             // delta §5c: HOLD — the sustain pedal for gestures (button removed 2026-08-05; localized holds pending)
    @State private var contentOverflows = false   // whole-UI scroll: the content column is taller than the viewport → wrap header+tabs+body in ONE ScrollView
    @State var ladderMode = false            // LADDER: exclusive-columns mode (mirror of au.uiLadderMode)
    @State var ladderPending: [Int: Int] = [:]   // LADDER: armed rung switches (column → row) — fire at the column's next entry
    @State var ladderBlink = false           // LADDER: the armed-cell blink (beat-toggled, like the scene arm)
    // SEAL comet: per-cell last-strike time + velocity (index = col*8+row), stamped from the 4 Hz poll of
    // au.pollCellStrikes(); the cell's comet runs along its figure for ~1s after the last strike (UI owns the decay).
    @State var cellHitAt = [Date](repeating: .distantPast, count: 64)
    @State var cellHitVel = [Double](repeating: 0, count: 64)
    // SEAL comet note-on/off GATE: which cells are currently SOUNDING (from au.pollCellSounding), and when each
    // last went SILENT. The spark travels for exactly as long as the note is held, then fades ~0.45s from release.
    @State var cellSounding = [Bool](repeating: false, count: 64)
    @State var cellReleasedAt = [Date](repeating: .distantPast, count: 64)
    @State var cellStrikeSeq = [Int](repeating: 0, count: 64)        // MOSAIC: per-cell strike-moment counter (each moment → the next rectangle)
    @State var emitPeak: [Double] = [0, 0, 0, 0]               // §6a meter: latched peak (0–1) per emitter
    @State var emitPeakAt: [Date] = Array(repeating: .distantPast, count: 4)   // when each peak latched (for decay)
    @State var emitDragVel: [Int?] = [nil, nil, nil, nil]     // BUILD emitter fader: the live drag velocity override per emitter (nil = not dragging)
    @State var recvDragVel: [Int?] = [nil, nil, nil, nil]     // BUILD receiver fader: the live drag input-velocity override per door (nil = not dragging)
    @State var receiverPeak: [Double] = [0, 0, 0, 0]           // §9 item 11 input meter: latched peak per receiver
    @State var receiverPeakAt: [Date] = Array(repeating: .distantPast, count: 4)
    @State var emitMarks: [[VelMark]] = [[], [], [], []]      // item 4: floating output velocity marks (Colour-tinted)
    @State var recvMarks: [[VelMark]] = [[], [], [], []]      // item 4: floating input velocity marks (strip hue)
    @State var recvHeld: [[Double]] = [[], [], [], []]        // duration: currently-held input velocities per receiver (0–1)
    @State var recvLiveHeld: [Bool] = [false, false, false, false]   // header dot: a LIVE (never latch) accepted note is held per receiver
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
    @State var laneMask: UInt8 = 0     // §5b lap: held column keys (bit i = column i), PERFORM only
    @State var tapAltMask: UInt64 = 0  // §9 item 1 ON TAP (unified ALT): ephemeral per-cell alt flips
    @State var tapMuteMask: UInt64 = 0 // §9 item 1 ON TAP = MUTE: ephemeral per-cell mute
    @State var soloEmitterMask: UInt8 = 0  // §9 item 1 ON TAP = SOLO EMITTERS: the derived emitter solo set
    @State var emitterFootSolo: UInt8 = 0  // emitter strip: the foot SOLO button set (OR'd into the derived mask)
    @State var emitterOctave: [Int] = [0, 0, 0, 0]   // emitter strip: per-emitter output ±octave nudge (ephemeral)
    @State var showDevLoader = false                 // dev-build: the hidden MIDI self-test overlay is showing
    #if DEBUG
    @State var selfTestResults: [SelfTestResult] = []  // the in-app MIDI-output self-tests, run on the dev overlay
    @State private var chaos = ChaosDriver()          // Layer 2 CHAOS MODE (debug-only): seeded control-surface fuzzer
    @State private var chaosSeed: UInt32 = 0
    @State private var chaosOn = false
    @State private var chaosStatus = "OK"             // live oracle readout (should-output check)
    @State private var chaosRecvMask: UInt8 = 0b0001  // which receivers chaos fuzzes (default R1 only)
    @State private var chaosEditMode = false          // false = PERFORM desk, true = EDIT screen
    #endif
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
            if sel.contains(pos) {                           // already selected → a tap DESELECTS it (the ANCHOR too,
                deselect(pos)                                // user 2026-08-07: previously the group anchor needed a long-press)
            } else {                                         // NOT selected → add to the group (any tapped cell joins)
                recordSelectionUndo()                        // snapshot (selection, doc) before this select
                let wasEmpty = scene.cells[col][row] == nil
                if sel.isEmpty {                              // FIRST selection
                    if wasEmpty { au?.editScene { $0.cells[col][row] = newbornCell() }; refreshFromDocument(); sel.markBorn(pos) }
                    // a populated first cell is just selected as the anchor
                } else if let a = sel.anchor {               // a group exists → the new cell ADOPTS the anchor's full config
                    if !wasEmpty, let orig = scene.cells[col][row] { sel.stash(pos, orig) }   // stash the original so deselect can revert it
                    au?.editScene { s in if let anchor = s.cells[a.col][a.row] { s.cells[col][row] = anchor } }   // → identical twins, edit together
                    refreshFromDocument()
                    if wasEmpty { sel.markBorn(pos) }        // an empty cell cloned into the group is "born" (deselect deletes)
                }
                sel.add(pos)
                // user 2026-08-08: directly selecting a MUTED cell for edit UNMUTES it (single/multi applies to the
                // column — in SINGLE it becomes the column's active rung so it plays). Twins that auto-join below stay
                // as they are; only the tapped cell unmutes. (Deselecting a still-muted twin just drops it — handled above.)
                if scene.cellAt(col, row)?.muted == true {
                    au?.editScene { $0.cells[col][row]?.muted = false }
                    if ladderMode {
                        au?.editScene(record: false) { s in
                            var ar = s.activeRow ?? [Int?](repeating: nil, count: 8); while ar.count < 8 { ar.append(nil) }
                            ar[col] = row; s.activeRow = ar
                        }
                    }
                    refreshFromDocument()
                }
                for t in au?.twinPositions(col: col, row: row) ?? [] {   // twins JOIN the selection (user 2026-08-07: selected, not just pulsing)
                    sel.add(GridView.GridPos(col: t.col, row: t.row))   // add() dedups
                }
            }
            syncAnchor()
            return
        }
        if ladderMode {                                      // SINGLE: a tap switches the column's active rung — POPULATED (that
            armLadderRung(col, row); return                  // cell plays) or EMPTY (the column mutes). User 2026-08-07.
        }
        if let v = activeVerb { doVerb(v, col, row) } else { triggerTap(col, row) }
    }
    /// LADDER tap (user 2026-08-03): tapping the ACTIVE rung toggles its MUTE (the column goes silent, dimmed like
    /// the dormant rungs; tap again restores). Tapping a DORMANT rung makes it the active one — but BLINK-arm (commit
    /// at the column's next entry) ONLY if the playhead is sounding this column right now; otherwise flip instantly.
    func armLadderRung(_ col: Int, _ row: Int) {
        if scene.cellAt(col, row)?.muted == true {       // BUG FIX (user 2026-08-08): a MULTI/edit-muted cell was
            au?.editScene { $0.cells[col][row]?.muted = false }   // un-clearable in SINGLE (the tap only armed a rung, never
            au?.editScene(record: false) { s in          // touched `muted`). Now tapping a muted cell UNMUTES it AND makes
                var ar = s.activeRow ?? [Int?](repeating: nil, count: 8); while ar.count < 8 { ar.append(nil) }
                ar[col] = row; s.activeRow = ar          // it the active rung (so it plays) — the single-mode path to clear a stuck mute.
            }
            ladderPending[col] = nil; refreshFromDocument(); return
        }
        if row == scene.ladderActiveRow(col) {           // re-tap the active rung → DESELECT: nothing speaks this column
            au?.editScene(record: false) { s in          // (a −1 sentinel — SINGLE never touches `muted`, so MULTI's mutes are preserved)
                var ar = s.activeRow ?? [Int?](repeating: nil, count: 8); while ar.count < 8 { ar.append(nil) }
                ar[col] = -1; s.activeRow = ar
            }
            ladderPending[col] = nil; refreshFromDocument(); return
        }
        let armed = d.playing && d.effColumn == col      // playhead on THIS column → arm (avoid cutting the sounding note); else instant
        au?.editScene(record: false) { s in              // set the active rung ONLY — `muted` stays MULTI's domain (a MULTI-muted rung stays silent)
            if !armed {
                var ar = s.activeRow ?? [Int?](repeating: nil, count: 8); while ar.count < 8 { ar.append(nil) }
                ar[col] = row; s.activeRow = ar
            }
        }
        ladderPending[col] = armed ? row : nil
        refreshFromDocument()
    }
    /// The dormant rungs (dimmed) while LADDER is on: every occupied cell that is NOT its column's active rung.
    var ladderDim: Set<GridView.GridPos> {
        guard ladderMode else { return [] }
        var s = Set<GridView.GridPos>()
        for c in 0..<8 {
            let active = scene.ladderActiveRow(c)
            for r in 0..<8 where scene.cellAt(c, r) != nil && r != active { s.insert(GridView.GridPos(col: c, row: r)) }
        }
        return s
    }
    /// The blinking cells while a SINGLE switch/mute is pending (commits at the column's next entry). The CURRENTLY
    /// ACTIVE cell flashes to show it's about to DEACTIVATE (user 2026-08-07 — whether the touched cell is populated
    /// or empty); an incoming POPULATED rung also flashes to show where the column is going (an empty rung shows nothing).
    var ladderArmedSet: Set<GridView.GridPos> {
        var s = Set<GridView.GridPos>()
        for (col, row) in ladderPending {
            if let active = scene.ladderActiveRow(col) { s.insert(GridView.GridPos(col: col, row: active)) }   // leaving → flashes
            if scene.cellAt(col, row) != nil { s.insert(GridView.GridPos(col: col, row: row)) }                // arriving (populated)
        }
        return s
    }

    // §10/11c ROUTE FOCUS (multi-cell, AcceptanceCriteria 2026-07-29). PLACE: the most-recently-placed cell.
    // SELECT: EVERY column that holds EXACTLY ONE selected cell is a focus (a column with 2+ selected cells is
    // ambiguous → no routing there). Each focus lights ALL cells above it (SRC) and ALL cells below it (DEST) in
    // its own column. Release applies; CANCEL reverts.
    var routeFoci: [Int: Int] {                  // col → focus row (≤ one per column) — PLACE: cells placed
        let cells: [GridView.GridPos]                    // this hold (incl. a whole row); SELECT: the selection.
        if heldVerb == .place { cells = Array(placedThisHold) }
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
        let src: Set<GridView.GridPos> = heldVerb == .place ? placedThisHold : []
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
            guard let cell = scene.cellAt(col, f) else { continue }
            let r = cell.inputRow == nil ? cell.inputReceiver : nil
            if first { recv = r; first = false } else if recv != r { return nil }
        }
        return recv
    }
    var routeOutBusesOn: [Bool] {                // a bus reads ON only if EVERY focus enables it
        guard !routeFoci.isEmpty else { return [false, false, false, false] }
        return Bus.allCases.map { b in routeFoci.allSatisfy { (col, f) in scene.cellAt(col, f)?.buses.contains(b) ?? false } }
    }

    // §11 dispatch a grid tap to the active verb.
    func doVerb(_ v: Verb, _ col: Int, _ row: Int) {
        guard let au else { return }
        let pos = GridView.GridPos(col: col, row: row)
        switch v {
        case .place:                                        // PLACE CELL(S) — toggle-with-restore; a candidate tap WIRES the focus
            if wireRouteCandidate(pos) { return }           // §10 route-as-you-place: a SRC/DEST of the last-placed cell wires it
            au.editScene(coalesceKey: tapCoalesceKey) { placeToggle(&$0, col, row) }
            refreshFromDocument()
        case .delete:                                       // §10b heal-on-delete: children inherit the input
            guard scene.cells[col][row] != nil else { return }
            au.editScene(coalesceKey: tapCoalesceKey) { $0.deleteCellSever(col: col, row: row) }
            refreshFromDocument()
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
            au?.editScene(coalesceKey: tapCoalesceKey) { $0.cells[col][row]?.muted.toggle() }   // no emitter output; children read raw MIDI-IN
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

    // SINGLE (true) = LADDER's exclusive-columns engine on; MULTI (false) = normal layering. The SINGLE|MULTI
    // toggle itself now lives in the title bar (ArrangementBar); this is the shared setter it drives.
    private func setSingle(_ on: Bool) {
        guard ladderMode != on else { return }
        ladderMode = on; au?.setLadderMode(on)
        if on { heldVerb = nil; syncSingleModeActivation() }   // entering SINGLE mid-edit: apply activation to the current selection
    }
    let sceneAmberHue = UI.amber   // HOLD's latch hue
    let ladderHue = Color(red: 0.25, green: 0.82, blue: 0.55)       // LADDER's teal-green (distinct from HOLD/MUTE)
    func onVerbEngaged(_ v: Verb) {
        editArmed = false                                   // §cell-edit A3: engaging any spring verb disarms EDIT (one editing intent)
        switch v {                                          // snapshot the state CANCEL reverts to, per verb (clipboard PERSISTS)
        case .place:  placeFresh = []; placeUndo = [:]; gridSnapshot = scene.cells
        case .delete: gridSnapshot = scene.cells
        default: break
        }
    }
    // §11 CANCEL (user 2026-07-28): revert the in-progress changes to the state when the verb was engaged AND
    // END the held status (release the button). PLACE/DELETE revert the grid; SELECT reverts the built selection.
    var verbHasBanner: Bool { activeVerb == .place || activeVerb == .delete }
    func cancelVerb() {
        switch heldVerb {
        case .place, .delete:
            if let au, let snap = gridSnapshot { au.editScene { $0.cells = snap }; refreshFromDocument() }
            placeFresh = []; placeUndo = [:]
        default: break
        }
        heldVerb = nil                                      // end the held status
    }
    // The verb session banner — a top overlay while PLACE/DELETE/SELECT is held; CANCEL (free hand) reverts + ends.
    func verbBanner(_ v: Verb) -> some View {
        let text: String
        switch v {
        case .place:  text = "Place cell(s) — tap the grid or a row · Choose one route in and multiple out"
        case .delete: text = "Delete cell(s) — tap the grid or a row · links cut"
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
    // SELECTION undo takes precedence while it has history (the recent select/deselect actions); once exhausted,
    // undo falls through to the transactional document undo.
    func undo() {
        if sel.canUndo { undoSelection() } else if au?.uiUndo() == true { refreshFromDocument() }
    }
    func redo() {
        if sel.canRedo { redoSelection() } else if au?.uiRedo() == true { refreshFromDocument() }
    }
    /// Snapshot the CURRENT (selection, document) before a select/deselect changes them (the undo point).
    func recordSelectionUndo() { if let d = au?.uiDocument() { sel.recordUndo(d) } }
    func undoSelection() {
        guard let d = au?.uiDocument(), let restored = sel.undo(currentDoc: d) else { return }
        au?.restoreDocument(restored); syncAnchor(); refreshFromDocument()
    }
    func redoSelection() {
        guard let d = au?.uiDocument(), let restored = sel.redo(currentDoc: d) else { return }
        au?.restoreDocument(restored); syncAnchor(); refreshFromDocument()
    }
    func clearSelectionUndo() { sel.clearHistory() }
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
        turnsPerNote = au.uiTurnsPerNote()
        curveMask = au.uiCurveMask()
        curveAmount = au.uiCurveAmount()
        fenceMask = au.uiFenceMask()
        fencePolicy = au.uiFencePolicy()
        fenceLo = au.uiFenceLo()
        fenceHi = au.uiFenceHi()
        monoMask = au.uiMonoMask()
        monoPriority = au.uiMonoPriority()
        pocketMask = au.uiPocketMask()
        pocketMs = au.uiPocketMs()
        convLead = au.uiConvLead()
        convStance = au.uiConvStance()
        rackMask = au.uiRackMask()
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
    func toggleReceiverEnabled(_ i: Int) { au?.toggleReceiverEnabled(i); receivers = au?.uiReceivers() ?? receivers }
    func setReceiverLatchKeys(_ i: Int, _ keys: Bool) { au?.setReceiverLatchAdd(i, keys); receivers = au?.uiReceivers() ?? receivers }   // KEYS|CHORD on the strip
    func toggleReceiverBypass(_ i: Int) { au?.toggleReceiverBypass(i); receivers = au?.uiReceivers() ?? receivers }   // BYPASS toggle on the strip
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
    // receiver strip: ±semitone NOTE nudge (±1 per tap, clamp ±12). Ephemeral; composes with the octave nudge.
    func nudgeReceiverNote(_ i: Int, _ delta: Int) {
        guard (0..<4).contains(i) else { return }
        receiverNote[i] = max(-12, min(12, receiverNote[i] + delta))
        au?.setInputSemitone(i, receiverNote[i])
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
        receiverOctave = [0, 0, 0, 0]; receiverNote = [0, 0, 0, 0]
        for i in 0..<4 { au?.setInputOctave(i, 0); au?.setInputSemitone(i, 0); au?.setInputVelOverride(i, nil) }
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
    // THE RACK — the strip RACK button toggles emitter i's whole board in/out of the signal path (persisted, undoable).
    func toggleRack(_ i: Int) {
        let inPath = rackMask & (1 << UInt8(i)) != 0
        au?.setRack(i, !inPath)
        rackMask = au?.uiRackMask() ?? rackMask
    }
    // THE RACK — CURVE: per-emitter velocity re-map (persisted). Tap toggles; the knob sets the −100…100 bend.
    func toggleCurve(_ i: Int) {
        let on = curveMask & (1 << UInt8(i)) != 0
        au?.setCurve(i, !on)
        curveMask = au?.uiCurveMask() ?? curveMask
    }
    func setCurveAmt(_ i: Int, _ amount: Int) {
        au?.setCurveAmount(i, amount)
        curveAmount = au?.uiCurveAmount() ?? curveAmount
    }
    // THE RACK — FENCE: per-emitter note-range policy (persisted). Tap toggles; the policy chip cycles DROP/CLAMP/
    // FOLD; the LO/HI knobs set the window bounds.
    func toggleFence(_ i: Int) {
        let on = fenceMask & (1 << UInt8(i)) != 0
        au?.setFence(i, !on)
        fenceMask = au?.uiFenceMask() ?? fenceMask
    }
    func cycleFence(_ i: Int) {
        au?.cycleFencePolicy(i)
        fencePolicy = au?.uiFencePolicy() ?? fencePolicy
    }
    func setFenceLoNote(_ i: Int, _ note: Int) {
        au?.setFenceLo(i, note)
        fenceLo = au?.uiFenceLo() ?? fenceLo
    }
    func setFenceHiNote(_ i: Int, _ note: Int) {
        au?.setFenceHi(i, note)
        fenceHi = au?.uiFenceHi() ?? fenceHi
    }
    // THE RACK — MONO / POCKET / CONVERSATION handlers (persisted).
    func toggleMono(_ i: Int) {
        let on = monoMask & (1 << UInt8(i)) != 0
        au?.setMono(i, !on); monoMask = au?.uiMonoMask() ?? monoMask
    }
    func cycleMono(_ i: Int) { au?.cycleMonoPriority(i); monoPriority = au?.uiMonoPriority() ?? monoPriority }
    func togglePocket(_ i: Int) {
        let on = pocketMask & (1 << UInt8(i)) != 0
        au?.setPocket(i, !on); pocketMask = au?.uiPocketMask() ?? pocketMask
    }
    func setPocketMsAmt(_ i: Int, _ ms: Int) { au?.setPocketMs(i, ms); pocketMs = au?.uiPocketMs() ?? pocketMs }
    func setConvLeadSel(_ i: Int) { au?.setConvLead(i); convLead = au?.uiConvLead() ?? convLead }
    func cycleConvStanceSel(_ i: Int) { au?.cycleConvStance(i); convStance = au?.uiConvStance() ?? convStance }
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
    func setTurnsPerNoteMode(_ on: Bool) { au?.setTurnsPerNote(on); turnsPerNote = au?.uiTurnsPerNote() ?? turnsPerNote }
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
                // LAYOUT v2: ONE header (with the tab bar), then the selected tab's body below. WHOLE-UI SCROLL
                // (user 2026-08-05): the header + tabs live INSIDE the scroll region so everything scrolls as one
                // unit when a reduced window can't fit it (the header no longer stays pinned as a "separate
                // window"). When the content FITS we render it RAW — a SwiftUI ScrollView delays/swallows the
                // UIKit ColumnHoldOverlay's multi-touch, so the lap gesture only works un-wrapped.
                mainContent(geo)
                // (§6c popup dropped — processor SETTINGS are inline in the §6d layout; the floating window
                //  survives only as the future EXTERNAL AUv3-view host, added when EXTERNAL Colours arrive.)
                if showManual {                         // the in-app MANUAL, scrolled to the last-touched control
                    ManualView(blocks: Self.manualBlocks, initialAnchor: helpTracker.lastAnchor,
                               onClose: { showManual = false })
                }
                if procTypePickerOpen { procTypePickerPopup() }   // FLOW-DIAGRAM: empty box → the welcoming type picker
                if procEditOpen { procEditPopup() }               // FLOW-DIAGRAM: populated box → the full processor controls
                if splitEditorOpen, let cell = editingCell { splitEditorPopup(cell) }   // FLOW-DIAGRAM: emitters SPLIT → the output-split editor
                if macroAuthorOpen, let g = macroAuthorGroup {   // MACRO AUTHORING (canonical) — the select-params → bind-to-macros pop-up (opens ON TOP of the proc pop-up)
                    MacroAuthoringView(group: g, macros: au?.uiMacros() ?? [], existing: macroAuthorExisting, accent: mainDestHue,
                                       base: macroAuthorBase,
                                       onPreview: macroAuthorPreview, onBind: macroAuthorBind, onUnbind: macroAuthorUnbind,
                                       onSetMacro: macroAuthorSetMacro, onClose: closeMacroAuthoring)
                }
                if showSettings {                       // §5 the cog page (overlay on the running instrument)
                    CogPage(au: au, busChannels: busChannels, d: d,
                            outAt: emitPeakAt, aboutLine: aboutLine,
                            showScenes: $showScenes, showTabBar: $showTabBar,
                            onSetEmitterChannel: setEmitterChannel,
                            onChanged: { busChannels = au?.uiBusChannels() ?? busChannels },
                            onClose: { showSettings = false })
                }
                if showPresets {                        // §3 the preset browser (overlay; the engine keeps running)
                    PresetBrowser(presets: presetList, factory: au?.factoryPresetNames() ?? [], current: currentPreset,
                                  onSave: savePreset, onLoad: loadPreset, onLoadFactory: loadFactoryPreset,
                                  onDelete: deletePreset, onClose: { showPresets = false })
                }
                if showCellLibrary {                    // CELL MACHINE stage-4: the cell library browser (BUILD-context routes to the selected colour's chain)
                    CellBrowser(cells: cellLibraryList, factory: au?.factoryLibrarySummaries() ?? [],
                                canSave: cellLibraryFromBuild ? (buildSelID != nil) : (editingCell != nil),
                                onSave: { name in if cellLibraryFromBuild { buildSaveColourToLibrary(name) } else { saveCellNamed(name) } },
                                onStamp: { name in if cellLibraryFromBuild { buildStampLibrary(au?.loadLibraryCell(name: name)) } else { stampFromLibrary(name) } },
                                onStampFactory: { name in if cellLibraryFromBuild { buildStampLibrary(au?.factoryLibraryCell(name: name)) } else { stampFromFactory(name) } },
                                onPreview: { name in if cellLibraryFromBuild { buildPreviewLibrary(au?.loadLibraryCell(name: name)) } },
                                onPreviewFactory: { name in if cellLibraryFromBuild { buildPreviewLibrary(au?.factoryLibraryCell(name: name)) } },
                                onSetStars: { name, stars in au?.setLibraryStars(name, stars); cellLibraryList = au?.libraryCellSummaries() ?? [] },
                                onDelete: deleteLibraryCellNamed,
                                onClose: { if cellLibraryFromBuild { buildCloseLibrary() } else { showCellLibrary = false } })
                }
                if verbHasBanner, let v = activeVerb {   // §11 verb session banner (PLACE/DELETE/SELECT; CANCEL reverts; the
                    VStack(spacing: 0) { verbBanner(v); Spacer() }   // strips carry the ROUTE IN/OUT targets in-place now)
                }
                #if DEBUG
                if showDevLoader { devLoaderOverlay }   // hidden T-session loader (long-press the logotype)
                #endif
            }
        }
        .environmentObject(helpTracker)         // the in-app manual: controls report their anchor via `.helpAnchor`
        .onChange(of: activeTab) { tab in
            // BUILD reuses the per-cell flow-diagram machinery via `editArmed` (drives the begin/apply session below).
            // Any tab switch clears transient GRID gestures (a held verb, MUTE arm) so state can't leak across tabs.
            editArmed = (tab == .build)
            if tab != .grid { heldVerb = nil }
            if tab != .build && ddSolo { ddSolo = false; au?.clearColourSolo() }   // audition (PLAY THIS MACHINE) — only clear it when leaving BUILD
            if tab == .build {
                if let u = au?.consumeBuildUnassigned() { buildRestoreUnassigned(u); buildCastSeeded = true }   // a saved half-built piece → restore it before seeding defaults
                buildSeedCastIfNeeded(); buildEnsureCastSelection()   // open BUILD with the part's cast selection (§2)
            }
            if tab == .build && !buildStagingPlaying { buildSelectMachineVoice() }   // BUILD lands on PLAY THIS MACHINE → SOLO the machine (never the whole grid)
        }
        .onChange(of: editArmed) { on in
            // MODE ROW: ADD/EDIT owns a transactional session (its baseline). Entering opens it; leaving via DONE
            // commits whatever was staged (live-previewed edits persist as one undo step) + clears transient state.
            if on {
                editMode = .addEdit
                au?.beginEditSession()
            } else {
                au?.applyEditSession()
                editMode = .addEdit; sel.reset(); clearedStash = [:]; syncAnchor()
                playCellOnly = false; au?.clearEditSolo()         // leaving EDIT → back to normal grid playback
                // BUG FIX 2026-08-05: leaving EDIT must NOT clear the column loop — it's one page-independent engine
                // state (`laneMask`). The old `setEditLoop(0)` here killed a loop armed on the EDIT page.
            }
        }
        .onChange(of: sel.cells) { _ in                       // SINGLE-mode editing: the selection drives the ladder's
            syncSingleModeActivation()                        // ACTIVE rung (ferry 2026-08-06); no-op in MULTI or outside ADD/EDIT
            if playCellOnly { au?.setEditSolo(editSelTargets) }   // "play this cell only" follows the selection
        }
        .onChange(of: d.absoluteStep) { _ in                  // LADDER commit: the armed column's current STEP just finished → set the new
            buildCommitPendingVoice()                          // BUILD: apply an armed CHAIN⟷PART voice switch on the cell boundary (Paul 2026-08-14)
            guard !ladderPending.isEmpty else { return }      // rung for its next entry. absoluteStep increments each step EVEN when the
            for (col, row) in ladderPending { au?.setActiveRow(col, row) }   // playhead is LOOPING one column (a lap) — where effColumn never changes, so
            ladderPending = [:]; refreshFromDocument()         // the old effColumn-change trigger never fired and the arm just blinked forever.
        }
        .onChange(of: d.playing) { playing in                 // transport stopped mid-arm → apply the pending voice switch now (no boundary will come)
            if !playing { buildCommitPendingVoice() }
        }
        .onChange(of: d.beat) { _ in                          // LADDER: blink the armed rungs (beat-driven, like the scene arm)
            if !ladderPending.isEmpty { ladderBlink.toggle() } else if ladderBlink { ladderBlink = false }
        }
        .onReceive(timer) { _ in
            guard let au else { return }
            buildPersistTick()   // BUILD: keep the saved unassigned part current + restore a just-loaded one (no-op off BUILD)
            #if DEBUG
            if chaosOn { let s = "\(chaos.oracleFlag) · \(chaos.eventCount)e"; if s != chaosStatus { chaosStatus = s } }   // CHAOS oracle readout
            #endif
            // Write @State ONLY when a DISPLAYED value changed — an unconditional write re-renders the
            // whole grid every 0.25s (which used to tear down in-progress press-holds). When STOPPED
            // nothing here changes, so the grid is quiescent; while PLAYING only the playhead fields move.
            let nd = au.kernelDiagnostics()
            if d.playing && !nd.playing {                                 // §5c/§9: transport stop = the drop
                if holdLatch { setHold(false) }
                // LOOP PERSISTS across a transport stop (user 2026-08-06): keep the selected columns (their LOOP
                // glyph stays) so a restart resumes looping — the transport edge already flushed the voices, so
                // nothing is stuck; the lap just isn't driven while stopped.
                clearOnTap()                                              // ON TAP: momentary flips/mute/solo clear on stop
                clearReceiverPerform()                                    // receiver strip: SOLO (+ OCT/vel/latch) = weather
                clearEmitterPerform()                                     // emitter strip: output OCT = weather
                if !ladderPending.isEmpty { ladderPending = [:] }         // LADDER: drop un-committed arms (no "next entry" while stopped)
            }
            let lm = au.uiLadderMode(); if lm != ladderMode { ladderMode = lm }   // LADDER: sync the mode (preset load / external change)
            if nd.playing != d.playing || nd.tempo != d.tempo || nd.pass != d.pass
                || (nd.playing && (nd.beat != d.beat || nd.effColumn != d.effColumn || nd.absoluteStep != d.absoluteStep)) { d = nd }
            let nb = au.uiBusChannels();   if nb != busChannels { busChannels = nb }
            let be = au.uiBusEnabled();    if be != busEnabled { busEnabled = be }
            let cm = au.uiClaimMask();     if cm != claimMask { claimMask = cm }
            let clk = au.uiClaimLeak();    if clk != claimLeak { claimLeak = clk }
            let th = au.uiThruReceiver();  if th != thruReceiver { thruReceiver = th }
            let fm = au.uiFlattenMask();   if fm != flattenMask { flattenMask = fm }
            let fa = au.uiFlattenAmount(); if fa != flattenAmount { flattenAmount = fa }
            let am = au.uiAltMask();       if am != altMask { altMask = am }
            let ac = au.uiAltCount();      if ac != altCount { altCount = ac }
            let tpn = au.uiTurnsPerNote(); if tpn != turnsPerNote { turnsPerNote = tpn }
            let cvm = au.uiCurveMask();    if cvm != curveMask { curveMask = cvm }
            let cva = au.uiCurveAmount();  if cva != curveAmount { curveAmount = cva }
            let fnm = au.uiFenceMask();    if fnm != fenceMask { fenceMask = fnm }
            let fnp = au.uiFencePolicy();  if fnp != fencePolicy { fencePolicy = fnp }
            let flo = au.uiFenceLo();      if flo != fenceLo { fenceLo = flo }
            let fhi = au.uiFenceHi();      if fhi != fenceHi { fenceHi = fhi }
            let mnm = au.uiMonoMask();     if mnm != monoMask { monoMask = mnm }
            let mnp = au.uiMonoPriority(); if mnp != monoPriority { monoPriority = mnp }
            let pkm = au.uiPocketMask();   if pkm != pocketMask { pocketMask = pkm }
            let pks = au.uiPocketMs();     if pks != pocketMs { pocketMs = pks }
            let cvl = au.uiConvLead();     if cvl != convLead { convLead = cvl }
            let cvs = au.uiConvStance();   if cvs != convStance { convStance = cvs }
            let rk = au.uiRackMask();      if rk != rackMask { rackMask = rk }
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
            let liveMask = au.pollReceiverLiveHeld()                   // header dot: LIVE (not latch) accepted-note-held per receiver (scalar mask)
            let live = (0..<4).map { liveMask & (1 << UInt8($0)) != 0 }   // unpack into a FRESH array (never shares the Kernel's buffer)
            if live != recvLiveHeld { recvLiveHeld = live }
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
                let now = Date(); var at = cellHitAt, vel = cellHitVel, seq = cellStrikeSeq
                for i in 0..<min(64, strikes.count) where strikes[i] > 0 { at[i] = now; vel[i] = Double(strikes[i]) / 127.0; seq[i] &+= 1 }
                cellHitAt = at; cellHitVel = vel; cellStrikeSeq = seq   // MOSAIC: advance the per-cell moment counter
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
        .onAppear {
            uiAppeared = true
            if activeTab == .build && !buildStagingPlaying { buildSelectMachineVoice() }   // land on BUILD already SOLOing the machine — never the whole grid
        }
        .onDisappear { uiAppeared = false }
        .onChange(of: d.beat) { b in ddBeatAnchor = b; ddBeatAnchorAt = Date() }   // keep the playhead anchor fresh on EVERY tab (BUILD sweep, not just DRAG&DROP)
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
    // LAYOUT v2: the active tab's body. Every surface has ONE permanent address — no in-grid overlays, no
    // PERFORM/EDIT toggle. GRID = the perform desk; PROCESSORS = the edit page; EMITTERS = the full rack matrix;
    // RECEIVERS = per-door config (Part 4); MACROS/AUTOMATION = coming-soon placeholders (later phase).
    // THE MAIN CONTENT COLUMN — header (+ tab bar) then the active tab's body. WHOLE-UI SCROLL (user 2026-08-05):
    // measure the column's natural height and, when it overflows the viewport, wrap the WHOLE thing (header + tabs
    // + body) in ONE ScrollView so it all scrolls together. When it fits, render RAW so the UIKit ColumnHoldOverlay
    // multi-touch stays alive (a ScrollView swallows those touches even with scrolling disabled).
    @ViewBuilder func mainContent(_ geo: GeometryProxy) -> some View {
        let column = VStack(spacing: 8) {
            arrangementBar.frame(maxWidth: .infinity)  // §2: LOGO · header · TAB BAR · scene row — full page width (Paul 2026-08-18, was capped to 1024)
            tabBody(geo)                               // the surface for the active tab
        }
        .padding(.horizontal, 12).padding(.top, 12)
        .padding(.bottom, activeTab == .build ? 0 : 12)   // BUILD: no bottom margin → the processor-box row is the lowest point (no scroll)
        .background(GeometryReader { g in Color.clear.preference(key: ContentHeightKey.self, value: g.size.height) })
        Group {
            if contentOverflows && activeTab != .build {   // BUILD never scrolls (user 2026-08-12) — it sizes to fit; the scroll view steals small-control taps
                ScrollView(.vertical, showsIndicators: true) { column }
            } else {
                column
            }
        }
        .onPreferenceChange(ContentHeightKey.self) { h in
            let over = h > geo.size.height + 0.5
            if over != contentOverflows { contentOverflows = over }
        }
    }

    @ViewBuilder func tabBody(_ geo: GeometryProxy) -> some View {
        switch activeTab {
        case .build:
            // Size the page to the space it ACTUALLY gets (below the header), not the full viewport — otherwise the
            // column is always taller than the viewport by the header's height → the whole UI scrolls, and the scroll
            // view steals taps from small controls (the piano/MIDI toggle + keys). The GeometryReader fills exactly the
            // remaining height → no overflow → no scroll → touches land. (user 2026-08-12)
            GeometryReader { g in buildPage(g.size) }
        case .grid:
            signalColumn(geo.size.width, isPortrait: geo.size.height > geo.size.width)
        case .emitters:
            rackMatrixView                    // the treatment matrix, now a full page
        case .receivers:
            ReceiverConfigView(au: au, receivers: receivers,
                               soloMask: soloReceiverMask, latchMask: latchMask, octave: receiverOctave, note: receiverNote,
                               onToggleEnable: toggleReceiverEnabled, onToggleMute: toggleReceiverMute,
                               onToggleSolo: toggleReceiverSolo, onToggleLatch: toggleReceiverLatch,
                               onSetLatchKeys: setReceiverLatchKeys, onToggleBypass: toggleReceiverBypass,
                               onOct: nudgeReceiverOctave, onNote: nudgeReceiverNote,
                               onChanged: { receivers = au?.uiReceivers() ?? receivers })
        case .macros:
            MacroPanel(macros: au?.uiMacros() ?? [],
                       onSetValue: { i, v in au?.setMacroValue(i, v) },
                       onSetFixed: { i, f in au?.setMacroFixed(i, f); refreshFromDocument() },
                       onSetName: { i, n in au?.setMacroName(i, n); refreshFromDocument() })
        case .automation:
            comingSoonPage(activeTab)
        }
    }

    @ViewBuilder func comingSoonPage(_ tab: AppTab) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(tab.rawValue).font(.system(size: 22, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            Text("coming").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.3)).tracking(2)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func signalColumn(_ appWidth: CGFloat, isPortrait: Bool) -> some View {
        // LAYOUT v2 (user 2026-08-05): PROCESSOR GRID title → the GRID → the CONTROL BAND (CONTROLS · MACROS ·
        // MACROS) → the MIDI INPUT label → the MIDI ROW (receivers · emitters · master). All bands share the grid's
        // width (1024 in landscape), centred. FIXED heights, rendered RAW — the whole UI scrolls as ONE via the
        // outer ScrollView in `body` when a reduced window can't fit it, which keeps the UIKit ColumnHoldOverlay's
        // multi-touch alive whenever the window DOES fit.
        let controlH: CGFloat = 150
        let landscapeFixed = !isPortrait && flowVariation == 0
        let cell: CGFloat = landscapeFixed ? (335 - 24) / 9 : 40
        let bandW = landscapeFixed ? min(appWidth - 24, 1024) : (appWidth - 24)
        return VStack(spacing: 6) {
            bandLabel("PROCESSOR GRID", bandW)                                                              // NEW section title (user 2026-08-05)
            gridBlock(cell, bandW).frame(width: bandW).frame(maxWidth: .infinity).helpAnchor("#grid")       // THE GRID
            controlBand.frame(width: bandW, height: controlH).frame(maxWidth: .infinity)                    // CONTROLS · MACRO rotaries · MACRO buttons
            bandLabel("MIDI INPUT", bandW)                                                                  // reinstated (user 2026-08-05)
            midiRow(isPortrait).frame(width: bandW, height: 172).frame(maxWidth: .infinity)                 // receivers · emitters · master
        }
        .coordinateSpace(name: "signal")
        .overlayPreferenceValue(RouteFramesKey.self) { frames in                      // §viz routing lines while a verb is held
            if heldVerb != nil { RoutingVizOverlay(edges: vizEdges, frames: frames, cellHeight: cell) }
        }
    }
    // A section label in the shared "MIDI INPUT" style (user 2026-08-05): left-aligned, above the section it names.
    // The one consistent panel-header treatment — PROCESSOR GRID · MIDI INPUT and the CONTROLS/MACROS control-band
    // panels all use it, so every header reads the same.
    private func bandLabel(_ s: String, _ width: CGFloat) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            .frame(width: width, alignment: .leading).frame(maxWidth: .infinity)
    }

    // THE CONTROL BAND — three equal sections under the grid (user 2026-08-05). Each carries a header ABOVE it in
    // the shared "MIDI INPUT" style (CONTROLS · MACROS · MACROS), so every panel reads consistently.
    var controlBand: some View {
        let macros = au?.uiMacros() ?? []
        return HStack(alignment: .top, spacing: 6) {
            labeledPanel("CONTROLS") {                         // LEFT: the placeholder engines (SINGLE|MULTI moved to the title bar)
                panelBox {
                    placeholderBtn("RANDOMIZE")
                    placeholderBtn("AUTOMATION")
                    placeholderBtn("MUTATE")                   // under AUTOMATION (user 2026-08-05)
                    placeholderBtn("AUTOPLAY")
                }
                .helpAnchor("#verbs")
            }
            labeledPanel("MACROS") {                           // CENTRE: 8 macro SLIDERS on ONE line, enlarged (user 2026-08-07)
                panelBox {
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(0..<8, id: \.self) { i in
                            GridMacroSlider(index: i, value: i < macros.count ? macros[i].value : 0, height: 74) { idx, v in au?.setMacroValue(idx, v) }
                        }
                    }
                }
            }
            labeledPanel("MACROS") {                           // RIGHT: 8 macro BUTTONS, two rows of four, enlarged
                panelBox {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 8) {
                        ForEach(8..<16, id: \.self) { i in
                            GridMacroButton(index: i, value: i < macros.count ? macros[i].value : 0,
                                            fixed: i < macros.count ? macros[i].fixed : false, height: 44) { idx, v in au?.setMacroValue(idx, v) }
                        }
                    }
                }
            }
        }
    }
    private func placeholderBtn(_ label: String) -> some View {
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5)).tracking(1)
            .frame(maxWidth: .infinity).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
    // A control-band section: the shared header ABOVE its panel body (matches the PROCESSOR GRID / MIDI INPUT labels).
    private func labeledPanel<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    // The panel body — a rounded translucent card that fills its section (no title inside; the title rides above).
    private func panelBox<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 6) {
            content()
            Spacer(minLength: 0)
        }
        .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }
    // THE MIDI ROW — receivers · emitters · master, three equal sections across the grid's width.
    @ViewBuilder func midiRow(_ isPortrait: Bool) -> some View {
        HStack(spacing: 6) {
            receiversBox(isPortrait).frame(maxWidth: .infinity).background(routeProbe("receivers")).helpAnchor("#receivers")
            emittersBox.frame(maxWidth: .infinity).background(routeProbe("emitters")).helpAnchor("#emitters")
            masterView.frame(maxWidth: .infinity).helpAnchor("#master")
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
            GridView(scene: scene, colours: docColours, playColumn: d.effColumn,
                     trueColumn: d.playing ? ((d.absoluteStep % 8) + 8) % 8 : -1, playing: d.playing,
                     beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                     cellHeight: cellHeight, editing: false,   // demolition: the grid is PERFORM/triggers-only now
                     selCol: selCol, selRow: selRow, onTap: tapCell,
                     onAuditionStart: startAudition, onAuditionEnd: endAudition,
                     laneMask: laneMask, laneHue: ladderMode ? ladderHue : sceneAmberHue, onColumnKey: toggleLoopColumn, holdLatch: holdLatch,
                     cellHitAt: cellHitAt, cellHitVel: cellHitVel,   // SEAL comet feed
                     cellSounding: cellSounding, cellReleasedAt: cellReleasedAt,   // SEAL comet gate
                     cellStrikeSeq: cellStrikeSeq,                   // MOSAIC: per-cell moment counter (one rectangle per moment)
                     whiteBorder: activeVerb == .place ? placedThisHold : [],   // §11 placed-this-hold cells wear a white border
                     ladderDim: ladderDim, ladderArmed: ladderArmedSet, ladderBlink: ladderBlink,   // LADDER: dormant dim · armed blink
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
        // Otherwise the rail wears the GRID MODE colour — SINGLE = green, MULTI = yellow (matching the column
        // selector + the SINGLE|MULTI radios; user 2026-08-05).
        let modeHue = ladderMode ? ladderHue : sceneAmberHue
        let hue = activeVerb == .place ? (colourColor(brush) ?? .white) : (activeVerb?.hue ?? modeHue)
        return VStack(spacing: GridGeometry.vGap) {
            Color.clear.frame(width: 40, height: cellHeight)          // align past the column-key row
            ForEach(0..<8, id: \.self) { r in
                 Image(systemName: chevron).font(.system(size: 20, weight: .heavy))
                    .foregroundColor(hue)
                    .frame(width: 40, height: cellHeight)
                    .background(RoundedRectangle(cornerRadius: 5).fill(hue.opacity(0.1)))
                    .contentShape(Rectangle())
                    // HARD RULE (user 2026-08-08): ANY gesture on a row selector == tapping EVERY cell in that row,
                    // regardless of mode. No mode-specific branch — `tapCell` already does the right per-cell thing.
                    .onTapGesture { tapRow(r) }
                    .onLongPressGesture(minimumDuration: 0.3) { tapRow(r) }
            }
        }
    }
    // The row selector's ONE behaviour: apply the per-cell tap to all 8 cells in the row (mute in MULTI, arm-the-rung
    // in SINGLE, place/delete under a held verb, select in EDIT — whatever a single tap does, done across the row).
    func tapRow(_ row: Int) {
        // ROW RULE (user 2026-08-08 rev): a UNIFORM row (all populated cells muted, or all unmuted) taps EVERY cell;
        // a MIXED row taps ONLY the unmuted cells (so a mixed row converges to all-muted rather than inverting).
        let populated = (0..<8).filter { scene.cellAt($0, row) != nil }
        guard !populated.isEmpty else { return }
        let muted = populated.filter { scene.cellAt($0, row)?.muted == true }.count
        let mixed = muted > 0 && muted < populated.count
        let targets = mixed ? populated.filter { scene.cellAt($0, row)?.muted != true } : populated
        tapSeq += 1; tapCoalesceKey = "rowtap-\(tapSeq)"   // one undo for the whole row (user 2026-08-09) — behaviour unchanged
        for c in targets { tapCell(c, row) }
        tapCoalesceKey = nil
    }

    // STROKES: a stroke is live while PLACE/DELETE/SELECT is held (COPY/PASTE don't stroke).
    var strokeActive: Bool { heldVerb == .place || heldVerb == .delete }
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
            refreshFromDocument()
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
    // master panel: the bottom-right flank tenant (beside the emitters). Sum meter = the loudest emitter peak.
    var masterView: some View {
        MasterView(mute: masterMute, key: masterKey,
                   peak: emitPeak.max() ?? 0, peakAt: emitPeakAt.max() ?? .distantPast,
                   marks: Array(emitMarks.flatMap { $0 }.suffix(8)), holdLatch: holdLatch,
                   onMute: toggleMasterMute, onPanic: masterPanic, onKey: nudgeMasterKey, onVelOverride: setMasterVel)
    }

    // THE RACK (pass 1) — the treatment matrix, now the full-page EMITTERS tab body (LAYOUT v2). Reuses the
    // strips' own callbacks (live + undoable). DONE returns to the GRID tab.
    var rackMatrixView: some View {
        RackMatrix(busChannels: busChannels, busEnabled: busEnabled, rackMask: rackMask,
                   claimMask: claimMask, claimLeak: claimLeak,
                   flattenMask: flattenMask, flattenAmount: flattenAmount,
                   altMask: altMask, altCount: altCount, turnsPerNote: turnsPerNote,
                   curveMask: curveMask, curveAmount: curveAmount,
                   fenceMask: fenceMask, fencePolicy: fencePolicy, fenceLo: fenceLo, fenceHi: fenceHi,
                   monoMask: monoMask, monoPriority: monoPriority,
                   pocketMask: pocketMask, pocketMs: pocketMs,
                   convLead: convLead, convStance: convStance,
                   emitPeak: emitPeak,
                   onClaim: setClaim, onClaimLeak: setClaimLeak,
                   onToggleDuck: toggleFlatten, onDuckAmount: setFlatAmount,
                   onToggleAlt: toggleAlt, onAltCount: setAltCnt, onSetTurnsPerNote: setTurnsPerNoteMode,
                   onToggleCurve: toggleCurve, onCurveAmount: setCurveAmt,
                   onToggleFence: toggleFence, onCycleFence: cycleFence,
                   onFenceLo: setFenceLoNote, onFenceHi: setFenceHiNote,
                   onToggleMono: toggleMono, onCycleMono: cycleMono,
                   onTogglePocket: togglePocket, onPocketMs: setPocketMsAmt,
                   onConvLead: setConvLeadSel, onConvStance: cycleConvStanceSel,
                   onClose: { activeTab = .grid })          // DONE returns to the GRID tab
    }

    var emittersBox: some View {
        OutputsView(busEnabled: busEnabled, busChannels: busChannels,
                    emitPeak: emitPeak, emitPeakAt: emitPeakAt, marks: emitMarks,
                    sounding: emitHeld, releaseMarks: emitRelease,
                    holdLatch: holdLatch,
                    onToggle: toggleEmitter,
                    onVelOverride: setVelOverride,
                    soloMask: emitterFootSolo, onToggleSolo: toggleEmitterSolo,
                    octave: emitterOctave, onOct: nudgeEmitterOctave,
                    rackMask: rackMask, onToggleRack: toggleRack,           // THE RACK: strip tap toggles the board in/out of path
                    wiring: !routeFoci.isEmpty, routeOn: routeOutBusesOn,     // §10 ROUTE OUT session face
                    onRouteOut: { toggleFocusEmitter(Bus.allCases[$0]) },
                    onOpenPage: { _, _ in activeTab = .emitters })          // THE RACK: long-press jumps to the EMITTERS tab
            .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)   // SPACE-FILL: fill the band
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    @ViewBuilder func receiversBox(_ isPortrait: Bool) -> some View {
        ReceiversView(receivers: receivers, peak: receiverPeak, peakAt: receiverPeakAt,
                      heldVels: recvHeld, releaseMarks: recvRelease, liveHeld: recvLiveHeld, isPortrait: isPortrait, thruReceiver: thruReceiver,
                      onToggleMute: toggleReceiverMute, onToggleEnable: toggleReceiverEnabled, onSetThru: setThru,
                      soloMask: soloReceiverMask, onToggleSolo: toggleReceiverSolo,
                      latchMask: latchMask, onToggleLatch: toggleReceiverLatch,
                      latchAddMask: receivers.enumerated().reduce(UInt8(0)) { $1.offset < 4 && $1.element.latchAddResolved ? $0 | UInt8(1 << $1.offset) : $0 },
                      onSetLatchKeys: setReceiverLatchKeys,
                      bypassMask: receivers.enumerated().reduce(UInt8(0)) { $1.offset < 4 && $1.element.bypassResolved ? $0 | UInt8(1 << $1.offset) : $0 },
                      onToggleBypass: toggleReceiverBypass,
                      octave: receiverOctave, onOct: nudgeReceiverOctave,
                      note: receiverNote, onNote: nudgeReceiverNote,
                      onVelOverride: setReceiverVel, holdLatch: holdLatch,
                      wiring: !routeFoci.isEmpty, routeCurrent: routeInCurrentReceiver,   // §10 ROUTE IN session face
                      onRouteIn: routeInReceiver)
            .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // SPACE-FILL: fill the band
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // The dev diagnostics (a8 stuck-note monitor) as a compact VERTICAL box — sits to the RIGHT of RECEIVERS.
    // delta item 8 PROCESSOR PANELS — procA and procB side by side, each a self-contained face editor with
    // its own COPY (+ PASTE when the clipboard holds a processor).
    // §6d: the two PROCESSOR panels (A/B). PORTRAIT stacks them VERTICALLY (A above B, shorter) so each gets
    // full width (2026-07-27 layout); LANDSCAPE keeps them side by side (the width exists).
    // MIXED-SET law: a SELECT set spanning >1 distinct Colour has no honest Colour-level edit, so the
    // PROCESSOR panels dim to "MIXED" (cell-level edits still apply). Single-Colour (or empty→brush) = normal.
    var selectionMixed: Bool {
        false   // SELECT retired (user 2026-08-09): the old perform-select set is gone; EDIT uses `sel`
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
                       canUndo: sel.canUndo || (au?.uiCanUndo ?? false),   // incl. SELECTION undo
                       canRedo: sel.canRedo || (au?.uiCanRedo ?? false),
                       onUndo: undo, onRedo: redo,
                       activeTab: activeTab,                                    // LAYOUT v2: the six-tab bar drives every surface
                       onSetTab: { tab in activeTab = tab },                     // the .onChange(of: activeTab) bridge handles editArmed + resets
                       showScenes: showScenes,                                  // scene row visibility (cog toggle)
                       showTabBar: showTabBar,                                  // tab bar visibility (cog toggle)
                       onOpenManual: { showManual = true },                     // "?" → the in-app manual
                       stepIndex: stepIndex, swing: swing,                      // LAYOUT v2: the clock now lives in the header
                       onStep: { au?.setStepRateIndex($0); refreshTiming() },
                       onSwing: { au?.setSwing($0); refreshTiming() },
                       ladderMode: ladderMode, onSetSingle: setSingle)             // GRID mode SINGLE|MULTI in the title bar (user 2026-08-05)
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
                .background(RoundedRectangle(cornerRadius: 3).fill(panicked ? UI.red : Color.clear))
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
                    Text("DEV — MIDI SELF-TESTS").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text("✕").font(.system(size: 16, weight: .heavy)).foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8).contentShape(Rectangle()).onTapGesture { showDevLoader = false }
                }
                buildSelfTestView
                stuckNoteMonitor
                chaosRow
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.10, green: 0.11, blue: 0.14)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12), lineWidth: 1))
            .padding(24)
        }
    }

    // Layer 2 CHAOS MODE start/stop — debug-only; drives the AU handlers on a seeded jittered loop while the engine
    // renders live. The seed shows on screen (SEED LAW) + is written to a per-session dump so an .ips pairs with it.
    @ViewBuilder var chaosRow: some View {
        #if DEBUG
        let red = UI.red
        HStack(spacing: 8) {
            if chaosOn {
                chaosBtn("⏹ STOP", active: true) { chaos.stop(); chaosOn = false }
                Text("0x\(String(chaosSeed, radix: 16)) · \(chaosStatus)")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(chaosStatus.hasPrefix("⚠") ? red : .white.opacity(0.6))
            } else {
                ForEach(0..<4, id: \.self) { r in                                   // which receivers chaos fuzzes (default R1)
                    let on = chaosRecvMask & (1 << UInt8(r)) != 0
                    Text("R\(r + 1)").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.5))
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 4).fill(on ? UI.cyan : Color.white.opacity(0.08)))
                        .contentShape(Rectangle()).onTapGesture { chaosRecvMask ^= (1 << UInt8(r)) }
                }
                chaosBtn(chaosEditMode ? "EDIT" : "PERF", active: chaosEditMode) { chaosEditMode.toggle() }   // what chaos fuzzes
                chaosBtn("▶ SIM", active: false) { startChaos(.simulated) }        // chaos plays its own spell-MIDI
                chaosBtn("▶ LIVE", active: false) { startChaos(.live) }             // MIDI from the host; chaos fuzzes controls
            }
            Spacer()
        }
        #endif
    }
    #if DEBUG
    private func chaosBtn(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        let red = UI.red
        return Button(label, action: tap)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(active ? .black : red)
            .padding(.vertical, 5).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 4).fill(active ? red : Color.white.opacity(0.08)))
    }
    private func startChaos(_ source: ChaosDriver.Source) {
        guard let au = au else { return }
        chaosSeed = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970))
        chaos.receiverMask = chaosRecvMask == 0 ? 0b0001 : chaosRecvMask   // at least R1
        chaosStatus = "OK"; chaos.start(au: au, seed: chaosSeed, source: source, mode: chaosEditMode ? .edit : .perform); chaosOn = true
    }
    #endif

    // The IN-APP MIDI self-tests (Paul 2026-08-16) — replaces the T-session loader. Runs the BuildSelfTest suite
    // offline against the real engine and lists PASS/FAIL; a failure shows its expected-vs-got detail. RE-RUN re-runs.
    @ViewBuilder var buildSelfTestView: some View {
        #if DEBUG
        let green = Color(red: 0.15, green: 0.88, blue: 0.55)
        let red = UI.red
        let results = selfTestResults
        let passed = results.filter { $0.passed }.count
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(results.isEmpty ? "RUNNING…" : "\(passed)/\(results.count) PASS")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(results.isEmpty ? .white.opacity(0.5) : (passed == results.count ? green : red))
                Button("RE-RUN") { selfTestResults = BuildSelfTest.runAll() }
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.black).padding(.vertical, 4).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 4).fill(UI.cyan))
                Spacer()
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(results) { r in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(r.passed ? "✓" : "✗").font(.system(size: 12, weight: .heavy)).foregroundColor(r.passed ? green : red)
                                Text(r.name).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.82))
                            }
                            if !r.passed {
                                Text(r.detail).font(.system(size: 8, weight: .regular, design: .monospaced))
                                    .foregroundColor(red).padding(.leading, 18)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(maxWidth: 520)
        .onAppear { if selfTestResults.isEmpty { selfTestResults = BuildSelfTest.runAll() } }
        #endif
    }
}

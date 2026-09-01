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

/// The EDIT page's tap modes. ADD/EDIT builds a live-edited selection set (the ONLY mode with APPLY/CANCEL
/// staging); MOVE drags cells to new positions; MUTE toggles per-cell mute; CLEAR removes a cell (re-tap the
/// empty slot to reinstate, while still in CLEAR). Everything except ADD/EDIT is IMMEDIATE + undo/redo.
enum EditPageMode { case addEdit, move, mute, clear }

/// LAYOUT v2 (2026-08-05): the permanent surface addresses — a tab per surface, replacing the PERFORM/EDIT toggle
/// and the in-grid overlays. GRID = the perform desk · PROCESSORS = the cell edit page · RECEIVERS = per-door config
/// (from the cog) · EMITTERS = the RACK matrix · MACROS/AUTOMATION = dimmed 'coming' seats (phase 2+).
// Only BUILD remains — the GRID/MIDI IN/MIDI OUT/MACROS/AUTOMATION tabs were retired 2026-08-21 (BUILD is the sole
// surface). `activeTab` is kept as a constant so the BUILD-only poll/render gates read cleanly.
enum AppTab: String, CaseIterable {
    case build = "BUILD"          // THE BUILD PAGE — the primary (and now only) workshop
}

/// One scrolling mark in the MIDI CONFIG REPLAY input roll: a note that ONSET at `born`, drifting right→left. (Paul 2026-08-20)
struct InputMark: Equatable { let note: UInt8; let born: Date; let beat: Double }   // beat = the onset beat → the roll is BEAT-driven (freezes when stopped, stays pass-synced); born = the memory-prune stamp

/// One emitted note in the TRUTH-STRIP "OUT" mini-roll (the processor editor): a note-on the plugin emitted at `born`,
/// drifting right→left as it fades. Accumulated from pollCellNotes (read-and-clear → each is a fresh onset). §1 truth strips.
struct OutMark: Equatable { let note: UInt8; let vel: Double; let born: Date }
struct BuildFocusNote: Equatable { let note: Int; let vel: Double; let beat: Double }   // the focus cell's REAL emitted note + its musical beat — the chain-flow comet source (Paul 2026-08-31)

/// CPU (device 2026-08-24): the FAST-changing telemetry — the emitter/receiver meter peaks (updated at 30 Hz) — used to
/// live as `@State` on the giant `DiagView`, so every peak update re-ran the WHOLE BuildPage body 30×/sec (80% CPU, the
/// watchdog kill). It now lives in this plain class held by `DiagView` via `@State` — `@State` tracks the class REFERENCE
/// (which never changes), NOT the object's mutations, so mutating it does NOT re-run the body. The meter timer writes it;
/// the meter TimelineViews (which already re-evaluate at 30 fps) read it LIVE through the shared reference. No SwiftUI
/// observation, no view extraction — the body only recomputes on real structural changes now.
final class LiveTelemetry {
    var emitPeak = [Double](repeating: 0, count: 4)
    var emitPeakAt = [Date](repeating: .distantPast, count: 4)
    var receiverPeak = [Double](repeating: 0, count: 4)
    var receiverPeakAt = [Date](repeating: .distantPast, count: 4)
    // The BEAT anchor (4 Hz): the playheads + the scene-chip sweep EXTRAPOLATE the beat from (anchor, anchorAt) at 30 fps,
    // so it only needs re-anchoring periodically. Holding it here (not @State) means the 4 Hz re-anchor doesn't re-run the
    // body either. `beat` is the raw polled beat (the InputMark roll reads it); `tempo` feeds the extrapolation.
    var beatAnchor = 0.0
    var beatAnchorAt = Date()
    var beat = 0.0
    var tempo = 120.0
    func emitter(_ i: Int, peak: Double) { guard i >= 0, i < 4 else { return }; emitPeak[i] = peak; emitPeakAt[i] = Date() }
    func receiver(_ i: Int, peak: Double) { guard i >= 0, i < 4 else { return }; receiverPeak[i] = peak; receiverPeakAt[i] = Date() }
    func anchorBeat(_ b: Double, tempo t: Double, at when: Date) { beat = b; beatAnchor = b; beatAnchorAt = when; tempo = t }
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
    @State var buildPlaceMsg: String? = nil          // the processor pop-up's PLACE feedback line ("added to row 6 — 2 remaining")
    @State var buildEditSlot: Int? = nil        // BUILD footer: which chain slot's processor pop-up editor is open (nil = closed)
    // PART MACRO BAND (Paul 2026-09-01): the 4-tab band + the BIND drill-down selection.
    @State var buildMacroTab: Int = 0           // 0 BIND · 1 PLAY · 2 PUNCH · 3 SPAN
    @State var buildMacroProc: Int = 0          // BIND: the selected processor slot (index into the selected colour's chain)
    @State var buildMacroParam: String? = nil   // BIND: the selected parameter key (nil ⇒ before/after + chips hidden — the calm resting view)
    @State var buildMacroSel: Int? = nil        // BIND: the chosen macro slot 0–15 (8 slider + 8 toggle) for the current binding
    @State var buildMacroAfter: Double = 0      // BIND: the AFTER value for the selected param (BEFORE = its current value; delta = after − before)
    @State var buildBypassHeld: Int? = nil      // HOLD-BYPASS A/B (idea 23): the slot momentarily bypassed while the BYPASS button is held
    @State var buildAddSlot: Int? = nil         // BUILD footer: which empty box's ADD-PROCESSOR picker is open (nil = closed)
    // DRAG-TO-REORDER the chain (Paul 2026-08-25): a custom finger-track (native .onDrag doesn't survive the AU host).
    @State var buildChainDragFrom: Int? = nil   // the processor box being dragged (nil = no drag in flight)
    @State var buildChainDragLoc: CGPoint = .zero   // finger location in the "chainBlock" coordinate space
    @State var buildChainDropTo: Int? = nil     // the slot index under the finger (highlighted; committed on release)
    @State var buildChainClipboard: [ProcessorSlot]? = nil   // COPY/PASTE buffer: a copied chain, pasted into a new row position
    // PROCESSOR EDITOR transaction (Paul 2026-08-19): the colour's chain as it was when the editor OPENED, so CANCEL can
    // revert (edits are live-previewed; exit keeps, cancel reverts) and the row-selector "overwrite" can restore the source.
    @State var buildEditorSnapshot: [ProcessorSlot] = []
    @State var buildEditorSnapCid: String? = nil
    // I/O toggle LONG-PRESS → apply to EVERY row (Paul 2026-08-19): a "Hold to apply to all" hint shows a moment into the hold.
    @State var buildIOHoldMsg: String? = nil
    @State var buildIOHoldPressing = false
    @State var buildRowUnder: [String?] = Array(repeating: nil, count: 8)   // one-colour-per-row: each row's revert-to colour when its colour relocates
    @State var buildDeletedRows: [Int: [String?]] = [:]  // DELETE verb: a staging row's saved contents (for restore on 2nd press)
    @State var buildStagingSel: [Int] = Array(repeating: -1, count: 8)   // the ONE selected (playing) row per staging COLUMN (white outline); -1 = none
    @State var buildRowChain: [[ProcessorSlot]] = Array(repeating: [], count: 8)   // STAGE THE GRID: the generated machine (chain) for each row (empty = not a staged row)
    @State var buildRowShade: [Double] = Array(repeating: 0, count: 8)   // STAGE THE GRID: per-row shade of the selected colour (+lighter … −darker), by output complexity
    @State var buildPulseColourID: String? = nil   // a touched grid cell's colour, offered as a PULSING candidate in the last free palette slot (nil = none)
    @State var buildPulseChain: [ProcessorSlot] = []   // the candidate's machine (for a staged variation cell); empty → use the colour's own chain
    @State var buildParts: [BuildPart] = [BuildPart()]   // the PARTS (workshop lifecycle); the CURRENT part's fields live in the working @State below, synced on switch
    @State var buildCurrentPart: Int = 0                 // index of the part currently on the build column
    @State var buildReturnPart: Int? = nil               // QoL: the UNDEFINED bench to auto-return to after promoting a restored part (Paul 2026-08-15)
    @State var buildPartEmitters: Set<Bus> = [.a]        // the CURRENT part's output emitters (part-owned I/O; every colour follows)
    @State var buildPartRate: StepRate? = nil            // PER-PART CLOCK (Paul 2026-08-19): the CURRENT part's step rate (nil ⇒ scene default) — deployed parts play at independent tempos
    @State var buildPartLen: Int? = nil                  // PER-PART CLOCK: the CURRENT part's loop length 1…8 (nil ⇒ 8) — a shorter part loops sooner (Stage D UI later)
    @State var buildPartCast: [String] = []              // the CURRENT part's cast MEMBERSHIP (visible palette over the global store); §2 cast view
    @State var buildCastSlots: [Int: String] = [:]       // §2 explicit slot→colourID for non-default colours (long-press places a colour on its pressed cell)
    @State var buildAuditionID: String? = nil            // the standing uncommitted "create a duplicate" candidate (ephemeral), auditioned after a PLACE
    @State var buildCastSeeded: Bool = false             // seed part 1's cast from the already-defined colours ONCE on first BUILD appear
    @State var buildPendingTab: Int? = nil               // the ONE pending (copied-unedited, PULSING) tab; nil = none
    @State var reelState: Int = 0                        // THE REEL-TO-REEL: 0 off · 1 armed · 2 replaying (polled)
    @State var reelShareURLs: [URL] = []                 // EXPORT: the written SMF files to share
    @State var reelShowShare = false
    @State var reelShowPopup = false                     // THE PASS BROWSER pop-up (tap the reel glyph)
    @State var reelPassNumbers: [Int] = []               // the 32 ring slots, oldest→newest (polled while the pop-up is open)
    @State var reelRoll: [ReelDeck.Note] = []            // the selected pass's notes (A–D piano-roll lanes)
    @State var reelSelPassNo: Int = -1                   // the currently selected/playing pass (−1 = auto latest)
    @State var reelCycle: Double = 4                     // the pass length in beats (piano-roll x-axis)
    @State var reelLastBeat: Double = 0                  // last polled beat + its wall-clock stamp → smooth roll playhead
    @State var reelLastBeatAt = Date()
    @State var reelPassSigs: [UInt64] = []               // per-pass content hashes (aligned with reelPassNumbers) → REMOVE DUPLICATES
    @State var reelDedup = false                         // REMOVE DUPLICATES toggle (collapse runs of identical passes)
    @State var reelPage = Int.max                        // PASS BROWSER page (clamped to the last page = newest → opens on newest, Paul 2026-08-26)
    // MULTI-PASS EXPORT (Paul 2026-08-26): a pass RANGE [lo,hi] by pass number (◀/▶ extend); the roll shows the whole range
    // concatenated, and SAVE exports it as ONE phrase. reelExportLanes = the selected emitter lanes (empty ⇒ the master sum).
    @State var reelSelLoPass = -1
    @State var reelSelHiPass = -1
    @State var reelRangeCyc: Double = 0                  // the concatenated range length in beats (0 ⇒ single pass, use reelCycle)
    @State var reelExportLanes: Set<Int> = []           // selected emitter lanes A–D (0…3); empty ⇒ export the MASTER (A–D sum)
    // #5 (Paul 2026-08-26): the per-pass STATE ring — the deployed play-grid arrangement live during each pass, keyed by
    // absolute pass number (main-thread; captured at each pass boundary from the 4 Hz poll). Selecting a pass can RESTORE it.
    @State var reelStateRing: [Int: BuildSceneSnapshot] = [:]
    @State var reelLastPassCounter = -1
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
    @State var buildRow8Cells: [Row8Cell] = Row8Cell.factoryDeck   // ROW 8 (Paul 2026-08-22): the authored action cells (refreshed from the document)
    @State var buildRow8On: [Bool] = Array(repeating: false, count: 8)   // ROW 8: the active scene's lit TOGGLE state
    @State var buildRow8EditOpen: Bool = false   // ROW 8: the EDIT PAGE (authoring) overlay
    @State var buildRow8EditSlot: Int = -1       // ROW 8 EDIT: which cell the page is authoring (−1 = the cell grid)
    // SCENES V2 (Paul 2026-08-12): in-memory play-grid arrangements. buildScenes holds the SAVED arrangements; index 0 is
    // the live one until the user captures more. Switching saves the current then restores the target (arrangement only —
    // parts/colours/master are shared). v1: not persisted, instant switch.
    @State var buildScenes: [BuildSceneSnapshot] = []
    @State var buildActiveScene: Int = 0
    @State var buildMidiConfigOpen: Bool = false   // BUILD [MIDI CONFIG] → the MIDI INPUTS sheet (config-sheets stage 5, Paul 2026-08-20)
    @State var buildMidiConfigTab: Int = 0         // MIDI INPUTS: which door (A–D) tab is shown (Paul 2026-08-23)
    @State var buildRackConfigOpen: Bool = false   // BUILD [RACK CONFIG] → the OUTPUT CHAIN sheet (config-sheets §6, Paul 2026-08-21)
    @State var buildMidiOutConfigOpen: Bool = false // BUILD [MIDI OUT] → the emitter stamp-channels sheet (moved out of the cog, Paul 2026-08-23)
    @State var buildFileImportDoor: Int? = nil     // FILE import: which door is picking a .mid (nil = closed)
    @State var buildRangeKbdDoor: Int? = nil       // RANGE picker: which door's keyboard is open (nil = closed)
    @State var buildRangeSetHi: Bool = false       // RANGE picker: setting the MAX bound (else MIN)
    // BUILD staging grid — an EPHEMERAL workshop store ([col][row] → colourID; nil = blank). Not the real scene; the
    // engine-backed ephemeral staging document + audition is a later slice. PLACE stocks a colour here.
    @State var buildStagingCells: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    // THE PLAY GRID (Paul 2026-08-29) — its OWN arrangement, INDEPENDENT of the part's buildStagingCells so the SELECT
    // top-button assign lands only on PLAY (was writing the shared staging → it wrongly lit the part-grid side buttons).
    // [column][row]; one selected rung per column (buildPlaySel, default ROW 1 = 0). Populated by the top-button ferry.
    @State var buildPlayCells: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    @State var buildPlaySel: [Int] = Array(repeating: 0, count: 8)   // per-column selected rung; 0 = ROW 1 default, −1 = none
    @State var buildPlayFerryRow: Int = 0   // the ROW the play-ferry buttons target (▲▼ moves it); a ferry lands on this rung of the touched column (Paul 2026-08-31)
    @State var buildSelectMode: Bool = false   // SELECT MODE (Paul 2026-08-31): a toggle under the machine play button — while on, every cell (select + ferry) lights white and a TAP only FOCUSES it into the machine (no start/stop), for editing/viewing
    // THE PLAY GRID — each column is a FULLY INDEPENDENT voice (Paul 2026-08-29): it starts/stops on its own and carries
    // the I/O it was FERRIED WITH (no separate I/O toggles). buildPlayColOn = per-column play state; buildPlayColRecv /
    // buildPlayColEmit = the door + emitters copied from the source at ferry time. (buildPlayPlaying is now a computed
    // "any column on", in the BuildPage extension.)
    @State var buildPlayColOn: [Bool] = Array(repeating: false, count: 8)
    @State var buildPlayColRecv: [Int] = Array(repeating: 0, count: 8)
    @State var buildPlayColEmit: [Set<Bus>] = Array(repeating: [.a], count: 8)
    // MULTI-STEP PASS (Paul 2026-08-30, "flatten the part"): a play column can hold an N-step pass. len[c] = 1 ⇒ the single
    // ferried cell (today); len[c] > 1 ⇒ steps[c] (the flattened part's per-column colours) swept + looped at rate[c].
    @State var buildPlayColLen: [Int] = Array(repeating: 1, count: 8)
    @State var buildPlayColSteps: [[String?]] = Array(repeating: [], count: 8)
    @State var buildPlayColRate: [StepRate?] = Array(repeating: nil, count: 8)
    @State var buildPlayColStepRecv: [[Int]] = Array(repeating: [], count: 8)      // per-step door (from the flattened part row)
    @State var buildPlayColStepEmit: [[Set<Bus>]] = Array(repeating: [], count: 8) // per-step emitters (from the flattened part row)
    // BUILD one-workshop-voice: PLAY THE STAGING GRID is active (mutually exclusive with PLAY THIS MACHINE / ddSolo).
    @State var buildVoiceOwner: BuildWorkshopVoice = .none   // SINGLE SOURCE OF TRUTH for the page-owned audition voice (none | chain | part). ddSolo/buildStagingPlaying are computed mirrors of this (Paul 2026-08-31) — one owner, so a play-ferry stop can never leave the shared audition sounding.
    // BUILD workshop voice = which of the two SHOP sections sounds: the MIDI CHAIN audition, the PART grid, or NEITHER.
    // Each header toggles its own section (play ⇄ stop), so BOTH can be stopped (Paul 2026-08-15). The two never sound
    // together (picking one stops the other) — the PIECE (play grid) is independent of this.
    @State var buildPendingWorkshopVoice: BuildWorkshopVoice? = nil   // an armed voice switch, applied on the next cell boundary (nil = none)
    @State var buildPendingReengage: Bool = false      // a palette colour change made while the chain audition plays — re-engage on the next cell boundary (seamless)
    @State var ddColourSel: Int = -1          // DRAG&DROP page: the selected palette colour index (−1 = none)
    @State var buildSelID: String? = nil      // BUILD: the selected colour BY ID (supports ephemeral colours beyond the 16); nil = none
    @State var buildColourReg: [String: [ProcessorSlot]] = [:]   // BUILD: ephemeral colours' machines (id → chain), beyond the 16 document slots
    @State var buildColourTranspose: [String: Int] = [:]        // BUILD: ephemeral colours' REGISTER HOME (id → transpose), for the ensemble roll
    @State var buildIDCounter: Int = 0        // BUILD: monotonic source for ephemeral colour IDs ("b0", "b1", …)
    // BUILD UNDO (Paul 2026-08-27): the BUILD page authors in @State, invisible to the AU document undo stack — so it gets
    // its OWN undo. Each snapshot captures the WHOLE authoring @State + the document, so a restore is always complete (never
    // partial/corrupting); an action that forgets to record is simply not undoable, never corrupt. `buildUndoKey` coalesces
    // a continuous gesture (a scrub / drag) into one step.
    @State var buildUndoStack: [BuildSnapshot] = []
    @State var buildRedoStack: [BuildSnapshot] = []
    @State var buildUndoKey: String? = nil
    @State var buildApplyingSnapshot = false   // true while an undo/redo restores state — suppresses any re-entrant record from an onChange
    // THE GRID SELECTOR (AcceptanceCriteria-grid-selector.md, 2026-08-23): the full-page 8×8 chain browser — each cell a
    // complete MIDI chain, tap = audition it live (mutually-exclusive, quantized, piece plays on), COMMIT overwrites the
    // arrival row's chain (one undo), CANCEL restores. Banks v1: DEALT (generated) + MY LIBRARY. All ephemeral/@State.
    @State var buildGridSelOpen = false
    @State var buildGridSelTab = 0                       // 0 = DEALT · 1 = MY LIBRARY
    @State var buildGridSelArrivalRow: Int? = nil        // the row selected when the selector OPENED — frozen (never re-read live)
    @State var buildFerryMirrorRow: Int? = nil           // the POPULATED part row a SELECT-grid ferry aim mirrors: card edits on gsAud write BACK to it (bidirectional, Paul 2026-08-30)
    @State var buildChainAuditionRow: Int? = nil         // the engine row the SELECT/chain audition parked on (col 0) → the aimed ferry reads its LIVE strikes there (#5, Paul 2026-08-30)
    @State var buildGridSelDealSeed: UInt64 = 1          // RE-DEAL bumps this
    @State var buildGridSelDealt: [Dice.EnsembleRow] = [] // the 64 shown chains (sampled from the corpus, or fresh while it builds)
    @State var buildGridSelCorpus: [Dice.EnsembleRow] = [] // §3.1 THE PREGEN CORPUS: the big pool DEAL samples 64 from (built once, background)
    @State var buildGridSelCorpusBuilding = false        // the corpus is generating (background)
    @State var buildGridSelLib: [LibEntry] = []          // MY LIBRARY summaries (chains loaded lazily on tap)
    @State var buildGridSelPage = 0                      // SELECT grid CATEGORY index (Paul 2026-08-29): the left rail's 8 buttons are fixed processor-type categories (ARP·RIFF·EUCLID·RATCHET·CHANCE·HARMONY·MOD/CC·GATE); this is the selected one. (Reuses the old page slot.)
    @State var buildGridSelCatIndices: [Int] = []        // the LIBRARY indices matching the current category (cached; recomputed on category change / library load), so grid position i → buildGridSelLib[catIndices[i]]
    @State var buildGridSelSel: Int? = nil               // the index of the auditioning cell (nil = none)
    @State var buildSelectGreyAlt: Bool = false          // SELECT machine grey ALTERNATES between two bright shades on each new selection, so a new pick visibly shifts even though the audition stays "gsAud" (Paul 2026-09-01)
    @State var buildGridSelGenerating = false            // DEALT is computing (disable the grid + show a spinner)
    @State var buildGridSelQuantStep = false             // §2 QUANTIZE: INSTANT (default — snappy switching) | STEP
    @State var buildGridSelActiveRoll: [GridSelBar] = []  // the auditioning chain's piano-roll (offline render, shown on the active cell + right column)
    @State var buildGridSelCellRoll: [Int: [GridSelBar]] = [:]   // per-CELL piano-roll fingerprints (bg-computed per deal/tab) — the drifting note face on every present cell (Paul 2026-08-26)
    @State var buildGridSelRowRoll: [Int: [GridSelBar]] = [:]    // per-ROW-chip piano-roll fingerprints (bg-computed on open) — the row selectors get the same drifting face
    @State var buildGridSelRollGen = 0                   // generation token so a stale bg roll batch (deal/tab changed under it) is discarded
    @State var buildGridSelStampRow: Int? = nil          // HOLD-TO-STAMP (Paul 2026-08-26): the row being held — a white sweep fills it while held; at completion the auditioning chain stamps onto it (keeping its colour)
    @State var buildGridSelStampAt: Date? = nil          // when the hold began (drives the rising white-fill fraction)
    @State var buildGridSelStampFlashRow: Int? = nil     // a just-stamped row — flashes fully white then fades to its colour
    @State var buildGridSelStampFlashAt: Date? = nil
    @State var buildGridSelStampSourceRow: Int? = nil    // NEW INTERFACE (Paul 2026-08-28): the ACTIVE SIDE BUTTON — the white-bordered part slot, and (if populated) the STAMP SOURCE for a long-press copy onto another side button/cell. Mutually exclusive with buildGridSelSel (a library-cell source).
    @State var buildFerryHeld = false                    // a ferry button was HELD (deliberate copy hold) then released BEFORE committing → suppress the follow-up tap so it doesn't steal focus / re-audition the playing cell (Paul 2026-08-29)
    @State var buildGridSelOverride: [Int: (chain: [ProcessorSlot], hex: UInt32)] = [:]   // NEW INTERFACE (Paul 2026-08-28): SELECT cell-to-cell copies land here as NEW in-memory INSTANCES (position → chain+hue) — the saved library on disk is never overwritten. Cleared on re-deal / tab switch.
    @State var buildGridSelLibFactoryFrom = 0            // buildGridSelLib[i] with i >= this is a FACTORY cell (resolve by section, not name)
    @State var buildGridSelPriorSolo = false             // pre-open workshop-voice snapshot — restored on CANCEL (never silence a voice we didn't own)
    @State var buildGridSelPriorStaging = false
    @State var buildGridSelPriorSel: String? = nil
    @State var buildGridSelPriorReceiver = 0
    @State var buildGridSelPriorEmitters: Set<Bus> = []   // the part-default emitters borrowed for the grid-sel audition (restored on teardown)
    @State var ddStickyReceiver: Int = 0      // DRAG&DROP: the LAST receiver chosen on the page → the default input for a fresh cell (R1 = 0)
    @State var ddStickyBuses: Set<Bus> = [.a] // DRAG&DROP: the LAST emitters chosen on the page → the default output for a fresh cell (Emitter A)
    // (the playhead beat anchor moved into `meters` — a @State-held class — so its 4 Hz re-anchor doesn't re-run the body)
    // ddSolo / buildStagingPlaying are now COMPUTED mirrors of buildVoiceOwner (see BuildPage) — not stored state.
    @State var showManual = false             // the "?" → the in-app manual overlay (scrolled to the last-touched control)
    @StateObject var helpTracker = HelpTracker()   // records the last-touched control's manual anchor (silent — no @Published)
    static let manualBlocks = ManualDoc.parse(ManualDoc.load())   // the parsed manual (once ever)
    @AppStorage("midispark.showScenes") var showScenes = false   // the scene row is HIDDEN by default; toggled on the cog page
    // INTERFACE REDESIGN (Docs/INSTRUCTIONS-interface-redesign.md) — a parallel NEW-interface shell behind a preview toggle
    // (old BUILD stays the default + fully working). Off ⇒ the current BUILD page; on ⇒ the room shell (roomsPage).
    @State var roomsRoom: Room = .select       // which room is in view in the new shell (one grid at a time)
    // (roomsTrackOn — the placeholder per-track toggle — retired 2026-08-29 when the top buttons became the PLAY FERRY,
    // which reflects its column's set play cell instead. See roomsPlayFerry.)
    @State var roomsMixerOpen: Bool = false   // §1 footer stack: the in/out STRIP-CONTROLS overlay (tap footer → open · tap outside → recede)
    @State var roomsMixerSel: Int? = nil      // MIXER stage 2 (Paul 2026-08-28): nil = the quarter-height strip row (stage 1); 0–3 = IN A–D · 4–7 = OUT A–D selected → full-page with that control's config below
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
    // FLOW-DIAGRAM processor pop-up (user 2026-08-07): tap a populated processor box → edit its full controls; tap an
    // empty box → the type picker. APPLY keeps · CANCEL restores the document snapshot taken on open.
    @State var scene = SceneState.empty()
    @State var brush = "gold"        // the paint Colour (view-local; never in the document)
    // §11b the held quasimode (SPRING-ONLY, user 2026-07-27): a verb is active ONLY while its button is pressed
    // (release = done). No latch/toggle. Nil = taps are triggers.
    // /btw ①: the SESSION CLIPBOARD — COPY captures a cell here; it PERSISTS after the hold releases; PASTE
    // stamps it (PASTE is disabled while this is nil). Replaces the old per-hold moveSource/copySource.
    // PLACE toggle-with-restore (user 2026-07-28): re-tapping a cell placed this hold undoes it — placed-on-empty
    // → removed; placed-over-a-cell → the ORIGINAL restored (all its properties). Memory resets each PLACE hold.
    @State var selCol = -1
    @State var selRow = -1
    // Cell Edit station (AcceptanceCriteria-cell-edit): EDIT is a 6th control, a TOGGLE (not a spring verb),
    // pointing the station at ONE cell (selCol/selRow) for deep editing. It is deliberately NOT a `heldVerb` —
    // `activeVerb` stays "a spring verb is held", so banners/routing-viz/candidate glow stay off for EDIT.
    @State var editArmed = false
    @State var playCellOnly = false                                          // EDIT: "play this cell only" vs "play from grid" (user 2026-08-08)
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
    // MODE ROW — CLEAR mode's undo stash: cells removed this CLEAR session, keyed by position. Re-tapping the now-empty
    // slot reinstates the cell. Dropped when we leave CLEAR mode (thereafter, undo/redo covers the removal).
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
    // CR-18[extra]: the ±semitone NOTE-nudge @State was write-only (init + reset, never read/driven — no UI control) —
    // removed. The ENGINE path (au.setInputSemitone → Kernel/Router inputSemitone) stays live for a future control.
    @State var latchMask: UInt8 = 0                          // receiver strip: per-receiver chord LATCH (ephemeral)
    @State var holdLatch = false             // delta §5c: HOLD — the sustain pedal for gestures (button removed 2026-08-05; localized holds pending)
    @State private var contentOverflows = false   // whole-UI scroll: the content column is taller than the viewport → wrap header+tabs+body in ONE ScrollView
    @State var ladderMode = false            // LADDER: exclusive-columns mode (mirror of au.uiLadderMode)
    @State var ladderPending: [Int: Int] = [:]   // LADDER: armed rung switches (column → row) — fire at the column's next entry
    @State var ladderBlink = false           // LADDER: the armed-cell blink (beat-toggled, like the scene arm)
    // SEAL comet: per-cell last-strike time + velocity (index = col*Snap.rows+row), stamped from the 4 Hz poll of
    // au.pollCellStrikes(); the cell's comet runs along its figure for ~1s after the last strike (UI owns the decay).
    @State var cellHitAt = [Date](repeating: .distantPast, count: Snap.cells)   // Snap.cells = 128 (rows 0–15; index = col*Snap.rows+row)
    @State var cellHitVel = [Double](repeating: 0, count: Snap.cells)
    // SEAL comet note-on/off GATE: which cells are currently SOUNDING (from au.pollCellSounding), and when each
    // last went SILENT. The spark travels for exactly as long as the note is held, then fades ~0.45s from release.
    @State var cellSounding = [Bool](repeating: false, count: Snap.cells)
    @State var cellReleasedAt = [Date](repeating: .distantPast, count: Snap.cells)
    @State var cellStrikeSeq = [Int](repeating: 0, count: Snap.cells)        // MOSAIC: per-cell strike-moment counter (each moment → the next rectangle)
    // NOTE-SWEEP feed (Paul 2026-08-19): per-cell RECENT emitted note-ons — pitch + velocity + count (6 slots/cell). The
    // piano-roll faces place marks at REAL pitch. Polled from au.pollCellNotes(); stored only on a tick that carried notes.
    @State var cellNotePitch = [UInt8](repeating: 0, count: Snap.cells * 6)
    @State var cellNoteVel   = [UInt8](repeating: 0, count: Snap.cells * 6)
    @State var cellNoteCount = [UInt8](repeating: 0, count: Snap.cells)
    // BUILD grid PIANO-ROLL (Paul 2026-08-19): the BUILD cells echo a piano roll too — accumulate per-cell scrolling notes
    // from the strike/note feed (same as the perform grid's face), read by buildNoteSweep→buildPianoRoll.
    @State var buildCellRoll: [[BuildRollNote]] = Array(repeating: [], count: Snap.cells)
    @State var buildRollPrevSeq = [Int](repeating: 0, count: Snap.cells)
    // §6a meter peaks (emitter + receiver) live in `meters` — a @State-held class so the 30 Hz updates DON'T re-run the
    // body (CPU, device 2026-08-24). The meter TimelineViews read `meters.emitPeak`/`emitPeakAt` etc. live through the reference.
    @State var meters = LiveTelemetry()
    @State var emitDragVel: [Int?] = [nil, nil, nil, nil]     // BUILD emitter fader: the live drag velocity override per emitter (nil = not dragging)
    @State var recvDragVel: [Int?] = [nil, nil, nil, nil]     // BUILD receiver fader: the live drag input-velocity override per door (nil = not dragging)
    @State var recvHeld: [[Double]] = [[], [], [], []]        // duration: currently-held input velocities per receiver (0–1) — the MIDI-IN length bar reads this
    @State var recvHeldNotes: [[UInt8]] = [[], [], [], []]    // per-door held input PITCHES (config-sheets REPLAY roll, Paul 2026-08-20)
    @State var buildOutRoll: [OutMark] = []                   // §1 TRUTH STRIPS: emitted note-ons drifting in the editor's OUT mini-roll (editor-open only)
    @State var buildFocusNotes: [BuildFocusNote] = []         // the focused machine cell's REAL emitted notes (+ beats) — drives the real chain-flow comets (Paul 2026-08-31)
    @State var buildStageEye = false                          // §4 STAGE EYE: the expanded 3-lane (input · mechanism · output) view is open
    @State var buildStageEyeDoor = -1                         // the door the eye watches (set on open) — drives the INPUT-onset accumulation below
    @State var buildEyeInRoll: [OutMark] = []                 // §4: INPUT onsets drifting in the eye's top lane (eye-open only)
    @State var buildEyeInPrev: Set<Int> = []                  // previous held set at the watched door (onset diffing)
    // §1 IN-STRIP DEBOUNCE: don't flash "nothing held" between notes — hold the state for a full PASS (8 steps when
    // playing, else ~0.8s) after the last input. Per door; the strip shows the sticky silhouette during the grace.
    @State var buildInSeenStep: [Int] = [-1, -1, -1, -1]      // absoluteStep when each door last had input
    @State var buildInLastHeldAt: [Date?] = [nil, nil, nil, nil]
    @State var buildInSticky: [[Int]] = [[], [], [], []]      // last non-empty held set per door (shown dimmed during the grace)
    @State var buildInGrace: [Bool] = [false, false, false, false]   // within one pass of the last input → suppress the teach text
    @State var buildLastEditAt: Date? = nil                   // idea 24 TOUCH-TO-DIFF: when the editor's chain last changed
    @State var buildEditStartedAt: Date? = nil                // the START of the current edit gesture (marks born after this = the NEW behaviour)
    @State var recvInputRoll: [[InputMark]] = [[], [], [], []]   // per-door scrolling input marks (onset-born), for the MIDI CONFIG REPLAY roll
    @State var recvReplayRoll: [[DoorRing.Note]] = [[], [], [], []]   // an ENGAGED REPLAY door's captured loop as DURATION notes — the roll reflects what's PLAYING (Paul 2026-08-23)
    @State var recvReplayLen: [Double] = [0, 0, 0, 0]                 // each engaged loop's length in beats (x-scale for the roll)
    @State var recvReplayAnchor: [Double] = [0, 0, 0, 0]             // each engaged loop's anchor beat — the config-roll playhead syncs to it (Paul 2026-08-26)
    @State var replayEngagedMask: UInt8 = 0                     // which REPLAY doors are actively looping (the "LAST N" toggle state)
    @State var docColours: [Colour] = []
    @State var receivers: [Receiver] = []                     // delta §9 item 11: the RECEIVERS panel
    @State var stepIndex = 2
    @State var swing = 50
    // MODELESS (2026-07-27): GRID CONTROLS — the verb palette. Radio-armed; INSPECT is functional in 1b, the
    // others render inert until their increments land. EDIT mode survives alongside until verb coverage completes.
    @State var laneMask: UInt16 = 0     // §5b lap: held column keys (bit i = column i), PERFORM only
    @State var buildStagingLane: UInt16 = 0   // PER-ROW LAP (Paul 2026-08-19): the BUILD STAGING grid's own column-loop (independent of the play grid)
    @State var buildPerformLane: UInt16 = 0   // PER-ROW LAP: the BUILD PLAY grid's own column-loop (baked into the composed scene per-row)
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
    @State private var autoPilot = AutoPilot()         // AUTO-RUN (debug-only): a CALM self-player — plays a chord loop by itself (not a fuzzer)
    @State private var autoOn = false
    @State private var autoStatus = "OK"
    #endif
    // §9 item 1 ON TAP quant/duration (4c): active TIMED actions. A tap adds one (onset from tapWhen, expiry
    // from tapFor); each poll derives the three ephemeral masks from the actions that are live at the beat.
    // ON-TAP overlay: TapKind/TapOverlay + the apply/mask logic are pure functions in Derivations (testable).
    @State var tapActions: [TapOverlay] = []
    let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    // A dedicated ~30 Hz drain for the peak METERS only (output + input velocity indicators), decoupled from the 4 Hz
    // poll so they track live input instead of lagging up to 250 ms (Paul 2026-08-21). Cheap read-and-clear; when idle
    // the feed returns 0 → no @State write → no re-render.
    let meterTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    // §5b COLUMN-SUBSET LAP: the PERFORM multi-column hold reports the held-set bitmask here. Push it to
    // the engine (ephemeral, never persisted) and keep a copy for the key LOOP highlight. Cleared to 0
    // on release (the overlay reports empty) and on the EDIT switch (see the mode toggle).

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
    // (ladderDim — the retired in-grid LADDER's dimmed-rung set — was removed 2026-08-27, zero references.)
    /// The blinking cells while a SINGLE switch/mute is pending (commits at the column's next entry). The CURRENTLY
    /// ACTIVE cell flashes to show it's about to DEACTIVATE (user 2026-08-07 — whether the touched cell is populated
    /// or empty); an incoming POPULATED rung also flashes to show where the column is going (an empty rung shows nothing).

    func refreshTapMasks() {
        let r = tapOverlayMasks(tapActions, now: d.beat, footSolo: emitterFootSolo)   // pure: expire + build masks
        if r.surviving.count != tapActions.count { tapActions = r.surviving }          // only mutate @State on real expiry
        if r.alt  != tapAltMask      { tapAltMask = r.alt;        au?.setTapAltMask(r.alt) }
        if r.mute != tapMuteMask     { tapMuteMask = r.mute;      au?.setTapMuteMask(r.mute) }
        if r.solo != soloEmitterMask { soloEmitterMask = r.solo;  au?.setSoloEmitterMask(r.solo) }
    }

    let sceneAmberHue = UI.amber   // HOLD's latch hue
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

    // delta §5 / a6: undo/redo restore the WHOLE document, so refresh every document-derived @State.
    // SELECTION undo takes precedence while it has history (the recent select/deselect actions); once exhausted,
    // undo falls through to the transactional document undo.
    // BUILD is the sole surface (Paul 2026-08-27): its authoring lives in @State, so route UNDO/REDO to the BUILD stack
    // (whose snapshot also carries the document, so document-colour/receiver/rack edits ride along). Fall back to the AU
    // document undo only if the BUILD stack is empty (defensive — nothing else drives the header now).
    func undo() { if buildCanUndo { buildDoUndo() } else if au?.uiUndo() == true { refreshFromDocument() } }
    func redo() { if buildCanRedo { buildDoRedo() } else if au?.uiRedo() == true { refreshFromDocument() } }
    func refreshFromDocument() {
        guard let au else { return }
        scene = au.uiScene()
        docColours = au.uiColours()
        buildRow8Cells = au.uiRow8()          // ROW 8: authored cells + the scene's lit toggles
        buildRow8On = au.uiRow8On()
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

    // (brushIndex + setBrushMorph/setBrushType + the A/B processor CLIPBOARD removed with the retired shared-Colour desk.)
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
    // receiver strip: the slider's momentary input-velocity override (touch = absolute, release = nil → spring).
    func setReceiverVel(_ i: Int, _ value: Int?) { au?.setInputVelOverride(i, value) }
    // receiver strip: per-receiver chord LATCH (additive toggle). Arm = detect-and-hold; a new chord replaces;
    // disarm releases (physical holds persist). PERFORM-only ⇒ clears on the EDIT switch as well as stop.
    func toggleReceiverLatch(_ i: Int) {
        guard (0..<4).contains(i) else { return }
        latchMask ^= UInt8(1 << i)
        au?.setLatchArm(latchMask)
    }
    /// Clear the receiver-strip PERFORM overlays (weather) — fired on the transport play→stop edge. The LATCH/KEYS arm is
    /// NO LONGER cleared here (Paul 2026-08-27): the latch section is durable CONFIG (saved with the document, restored on
    /// reload), so it survives a transport stop like the mode itself. Only the true weather (solo · octave · vel) resets.
    func clearReceiverPerform() {
        soloReceiverMask = 0; au?.setSoloReceiverMask(0)
        receiverOctave = [0, 0, 0, 0]
        for i in 0..<4 { au?.setInputOctave(i, 0); au?.setInputSemitone(i, 0); au?.setInputVelOverride(i, nil) }   // setInputSemitone still resets the live ENGINE nudge
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
    func masterPanic() { au?.masterPanic() }
    func nudgeMasterKey(_ d: Int) { au?.nudgeMasterKey(d); masterKey = au?.uiMasterKey() ?? masterKey }
    func setEmitterChannel(_ i: Int, _ ch: Int) {
        guard let au else { return }
        au.editDocument { d in
            var bc = d.busChannels ?? []                       // CR-8: busChannels is Optional now — seed to 4 before writing
            while bc.count < 4 { bc.append(bc.count + 1) }
            bc[i] = max(1, min(16, ch)); d.busChannels = bc
        }
        busChannels = au.uiBusChannels()
    }

    var selected: TestSessions.Session? { TestSessions.all.first { $0.id == loadedID } }

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
                if showSettings {                       // §5 the cog page (overlay on the running instrument)
                    CogPage(au: au, d: d, aboutLine: aboutLine,
                            showScenes: $showScenes,
                            onClose: { showSettings = false })
                }
                if showPresets {                        // §3 the preset browser (overlay; the engine keeps running)
                    PresetBrowser(presets: presetList, factory: au?.factoryPresetNames() ?? [], current: currentPreset,
                                  onSave: savePreset, onLoad: loadPreset, onLoadFactory: loadFactoryPreset,
                                  onDelete: deletePreset, onClose: { showPresets = false })
                }
                if showCellLibrary {                    // the cell library browser — BUILD-only now (routes to the selected colour's chain)
                    CellBrowser(cells: cellLibraryList, factory: au?.factoryLibrarySummaries() ?? [],
                                canSave: buildSelID != nil,
                                onSave: { name in buildSaveColourToLibrary(name) },
                                onStamp: { name in buildStampLibrary(au?.loadLibraryCell(name: name)) },
                                onStampFactory: { name in buildStampLibrary(au?.factoryLibraryCell(name: name)) },
                                onPreview: { name in buildPreviewLibrary(au?.loadLibraryCell(name: name)) },
                                onPreviewFactory: { name in buildPreviewLibrary(au?.factoryLibraryCell(name: name)) },
                                onSetStars: { name, stars in au?.setLibraryStars(name, stars); cellLibraryList = au?.libraryCellSummaries() ?? [] },
                                onDelete: deleteLibraryCellNamed,
                                onClose: { buildCloseLibrary() })
                }
                #if DEBUG
                if showDevLoader { devLoaderOverlay }   // hidden T-session loader (long-press the logotype)
                #endif
            }
        }
        .environmentObject(helpTracker)         // the in-app manual: controls report their anchor via `.helpAnchor`
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
        .onReceive(meterTimer) { _ in
            guard uiAppeared, let au else { return }   // ~30fps peak metering → the velocity indicators track live (not the 4Hz poll)
            let act = au.pollEmitterActivity()
            for i in 0..<4 where i < act.events.count && act.events[i] > 0 { meters.emitter(i, peak: Double(act.peak[i]) / 127.0) }   // → the @State-held class; DOES NOT re-run the body
            let rin = au.pollReceiverActivity()
            for i in 0..<4 where i < rin.events.count && rin.events[i] > 0 { meters.receiver(i, peak: Double(rin.peak[i]) / 127.0) }
        }
        .onReceive(timer) { _ in
            guard uiAppeared, let au else { return }   // CR-17: don't drain the render→main feeds while the view is hidden/backgrounded (perf + narrows CR-1's race window). buildPersistTick resumes on re-appear — a load restores then.
            buildPersistTick()   // BUILD: keep the saved unassigned part current + restore a just-loaded one (no-op off BUILD)
            #if DEBUG
            if chaosOn { let s = "\(chaos.oracleFlag) · \(chaos.eventCount)e"; if s != chaosStatus { chaosStatus = s } }   // CHAOS oracle readout
            if autoOn { let s = "\(autoPilot.status) · \(autoPilot.chordCount)c"; if s != autoStatus { autoStatus = s } }   // AUTO-RUN readout
            #endif
            // Write @State ONLY when a DISPLAYED value changed — an unconditional write re-renders the
            // whole grid every 0.25s (which used to tear down in-progress press-holds). When STOPPED
            // nothing here changes, so the grid is quiescent; while PLAYING only the playhead fields move.
            let nd = au.kernelDiagnostics()
            meters.anchorBeat(nd.beat, tempo: nd.tempo, at: Date())       // BEAT clock (4 Hz) → the @State-held telemetry; the playheads extrapolate from it at 30 fps, so no body re-run for the beat
            if d.playing && !nd.playing {                                 // §5c/§9: transport stop = the drop
                if holdLatch { setHold(false) }
                // LOOP PERSISTS across a transport stop (user 2026-08-06): keep the selected columns (their LOOP
                // glyph stays) so a restart resumes looping — the transport edge already flushed the voices, so
                // nothing is stuck; the lap just isn't driven while stopped.
                clearOnTap()                                              // ON TAP: momentary flips/mute/solo clear on stop
                clearReceiverPerform()                                    // receiver strip: SOLO (+ OCT/vel/latch) = weather
                clearEmitterPerform()                                     // emitter strip: output OCT = weather
                if !ladderPending.isEmpty { ladderPending = [:] }         // LADDER: drop un-committed arms (no "next entry" while stopped)
                if buildCellRoll.contains(where: { !$0.isEmpty }) { buildCellRoll = Array(repeating: [], count: Snap.cells) }   // BUILD piano-roll: clear on stop so idle faces pause
            }
            let lm = au.uiLadderMode(); if lm != ladderMode { ladderMode = lm }   // LADDER: sync the mode (preset load / external change)
            // `d` drives the BODY (effColumn highlight, pass, etc.). DON'T update it on `beat` alone — that fired every
            // tick while playing (→ a full BuildPage recompute at 4 Hz just to move a beat the playheads extrapolate).
            // The beat now lives in `meters`; `d` updates only at STEP boundaries (effColumn/absoluteStep) + transport/tempo/pass.
            if nd.playing != d.playing || nd.tempo != d.tempo || nd.pass != d.pass
                || (nd.playing && (nd.effColumn != d.effColumn || nd.absoluteStep != d.absoluteStep)) { d = nd }
            let nb = au.uiBusChannels();   if nb != busChannels { busChannels = nb }
            let be = au.uiBusEnabled();    if be != busEnabled { busEnabled = be }
            let rs = au.uiReelState();     if rs != reelState { reelState = rs }   // THE REEL-TO-REEL glyph state
            if reelShowPopup {                                                    // THE PASS BROWSER: refresh the ring + selected roll while open
                let pn = au.reelPassNumbers();     if pn != reelPassNumbers { reelPassNumbers = pn }
                let ps = au.reelPassSignatures();  if ps != reelPassSigs { reelPassSigs = ps }   // REMOVE DUPLICATES
                if reelRangeCyc <= 0 { let rr = au.reelSelectedRoll(); if rr != reelRoll { reelRoll = rr } }   // single pass → live roll; a multi-pass RANGE roll is set on selection (don't overwrite it)
                let sp = au.reelSelectedPassNo();  if sp != reelSelPassNo { reelSelPassNo = sp }
                let cy = au.reelCycleBeats();      if cy != reelCycle { reelCycle = cy }
                if nd.beat != reelLastBeat { reelLastBeat = nd.beat; reelLastBeatAt = Date() }   // stamp for the smooth roll playhead
            }
            // #5 PER-PASS STATE CAPTURE (Paul 2026-08-26): when a pass completes (the counter advances), snapshot the
            // arrangement live during it under that pass's number. Main-thread only, at boundaries only — no render change.
            let pc = au.reelPassCounter()
            if pc != reelLastPassCounter {
                if pc < reelLastPassCounter { reelStateRing.removeAll() }          // reel cleared/reset → drop the state ring
                else if reelLastPassCounter >= 0, pc > 0 {
                    reelStateRing[pc - 1] = buildCaptureCurrentScene()             // pass (pc−1) just finished → its live setup
                    let cutoff = pc - ReelDeck.histCount                           // keep only the passes still in the reel ring
                    if reelStateRing.count > ReelDeck.histCount { reelStateRing = reelStateRing.filter { $0.key >= cutoff } }
                }
                reelLastPassCounter = pc
            }
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
            // §6a metering: the per-emitter/receiver PEAK feeds are drained by the ~30fps meterTimer above (low latency).
            // duration: the currently-held input notes per receiver (present-while-held → the MIDI-IN length bar reads recvHeld)
            let held = au.pollReceiverSounding().map { $0.map { Double($0) / 127.0 } }, mnow = Date()
            if held != recvHeld { recvHeld = held }
            // config-sheets REPLAY roll: while the MIDI CONFIG sheet is open, accumulate per-door input ONSETS (a pitch
            // newly in the held set) as scrolling marks; prune to ~4s. Gated on the sheet so it costs nothing otherwise.
            // recvHeldNotes feeds the config REPLAY roll AND the §1 TRUTH-STRIP "IN" silhouette in the processor editor —
            // so poll it while EITHER is open. The scrolling-roll + replay accumulation stays config-only (the strip just
            // reads the held set). editorOpen is reused below for the OUT mini-roll.
            let editorOpen = buildEditSlot != nil
            // The held-input set is polled ALWAYS (it's cheap) — the machine-strip note COMETS + the IN strip read it, not just
            // the config sheet / editor (Paul 2026-08-31: the comets never had a chord because this was config-gated). The
            // expensive scrolling roll / replay accumulation stays gated below.
            let notes = au.pollReceiverSoundingNotes()
            let prevHeld = recvHeldNotes
            if notes != recvHeldNotes { recvHeldNotes = notes }
            if buildMidiConfigOpen {
                var roll = recvInputRoll
                for i in 0..<4 {
                    let cur = Set(i < notes.count ? notes[i] : []), prev = Set(i < prevHeld.count ? prevHeld[i] : [])
                    for n in cur.subtracting(prev) { roll[i].append(InputMark(note: n, born: mnow, beat: nd.beat)) }   // a new onset (beat-stamped for the beat-driven roll)
                    roll[i] = roll[i].filter { mnow.timeIntervalSince($0.born) < 40.0 }   // generous; the roll view clips to its own N-pass window
                    if roll[i].count > 128 { roll[i] = Array(roll[i].suffix(128)) }
                }
                recvInputRoll = roll
                let eng = au.replayEngaged(); if eng != replayEngagedMask { replayEngagedMask = eng }   // the LAST-N toggle state
                let la = au.latchArm();       if la != latchMask { latchMask = la }   // RE-DERIVE the KEYS/HOLD/LATCH arm from the engine so it survives a view rebuild / navigation (Paul 2026-08-27)
                // REPLAY loop roll (Paul 2026-08-23): while a door is ENGAGED, poll its captured loop as DURATION notes so
                // the piano roll shows exactly what's playing from the RECORDING (held chords, note lengths) — not live input.
                var lroll = recvReplayRoll, llen = recvReplayLen, lanc = recvReplayAnchor
                for i in 0..<4 {
                    if eng & (1 << UInt8(i)) != 0 { lroll[i] = au.replayLoopRoll(door: i); llen[i] = au.replayLoopLen(door: i); lanc[i] = au.replayLoopAnchor(door: i) }
                    else if !lroll[i].isEmpty { lroll[i] = []; llen[i] = 0; lanc[i] = 0 }
                }
                if lroll != recvReplayRoll { recvReplayRoll = lroll }
                if llen != recvReplayLen { recvReplayLen = llen }
                if lanc != recvReplayAnchor { recvReplayAnchor = lanc }
            }
            // §1 IN-STRIP DEBOUNCE (editor only): hold the "has input" state for a full PASS after the last note, so the
            // teach text never flashes on note-off. By STEP when playing (8 steps = one pass) · by ~0.8s wall-clock else.
            if editorOpen {
                for i in 0..<4 {
                    if !notes[i].isEmpty {
                        buildInSeenStep[i] = nd.absoluteStep; buildInLastHeldAt[i] = mnow
                        buildInSticky[i] = notes[i].map { Int($0) }; buildInGrace[i] = true
                    } else {
                        let byStep = nd.playing && buildInSeenStep[i] >= 0 && (nd.absoluteStep - buildInSeenStep[i]) < 8
                        let byClock = buildInLastHeldAt[i].map { mnow.timeIntervalSince($0) < 0.8 } ?? false
                        buildInGrace[i] = byStep || byClock
                    }
                }
            }
            if !buildMidiConfigOpen && (!recvInputRoll.allSatisfy({ $0.isEmpty }) || !recvReplayRoll.allSatisfy({ $0.isEmpty })) {
                recvInputRoll = [[], [], [], []]   // sheet closed → drop the scrolling marks (recvHeldNotes stays live)
                recvReplayRoll = [[], [], [], []]; recvReplayLen = [0, 0, 0, 0]; recvReplayAnchor = [0, 0, 0, 0]
            }
            let nc = au.uiColours();       if nc != docColours { docColours = nc }
            let nr = au.uiReceivers();     if nr != receivers { receivers = nr }
            let ns = au.uiScene();         if ns != scene { scene = ns }
            if !tapActions.isEmpty { refreshTapMasks() }   // §9 ON TAP 4c: fire quantized onsets + expire durations
            let si = au.uiStepRateIndex(); if si != stepIndex { stepIndex = si }
            let sw = au.uiSwing();         if sw != swing { swing = sw }
            let cn = au.pollCellNotes()                    // NOTE-SWEEP: per-cell recent emitted notes (pitch/vel/count) — drained every tick
            if cn.count.contains(where: { $0 > 0 }) { cellNotePitch = cn.pitch; cellNoteVel = cn.vel; cellNoteCount = cn.count }
            // FOCUS note-event feed (Paul 2026-08-31): the machine's cell → its REAL emitted notes + beats, for the chain-flow
            // comets. The focus cell = a selected ferry's play cell (col 0, row 8+col), else the chain audition's engine row.
            let focusIdx: Int = buildSelectedPlayCol.map { Snap.playLayerRowBase + $0 } ?? (buildDisplayVoice == .chain ? (buildChainAuditionRow ?? -1) : -1)
            au.setFocusCell(focusIdx)
            let ff = au.pollFocusNotes()
            if ff.count > 0 || !buildFocusNotes.isEmpty {
                var fn = focusIdx >= 0 ? buildFocusNotes : []
                for k in 0..<ff.count where focusIdx >= 0 { fn.append(BuildFocusNote(note: Int(ff.pitch[k]), vel: Double(ff.vel[k]) / 127.0, beat: ff.beat[k])) }
                fn = fn.filter { $0.beat > nd.beat - 2.5 }          // keep the last ~2.5 beats
                if fn.count > 160 { fn = Array(fn.suffix(160)) }
                if fn != buildFocusNotes { buildFocusNotes = fn }
            }
            // §1 TRUTH STRIPS — OUT mini-roll: while the processor editor is open, accumulate emitted note-ons into a
            // drifting roll (cn is read-and-clear → every note is a fresh onset; no diffing). Aggregated across the board:
            // during a chain audition (part stopped) that IS the chain's output. Pruned to ~2.5s; ≤96 marks.
            if editorOpen {
                var out = buildOutRoll
                for i in 0..<Snap.cells {
                    let k = min(Int(cn.count[i]), 6)
                    for j in 0..<k where i * 6 + j < cn.pitch.count {
                        out.append(OutMark(note: cn.pitch[i * 6 + j], vel: Double(cn.vel[i * 6 + j]) / 127.0, born: mnow))
                    }
                }
                out = out.filter { mnow.timeIntervalSince($0.born) < 2.5 }
                if out.count > 96 { out = Array(out.suffix(96)) }
                if out != buildOutRoll { buildOutRoll = out }   // guard idle re-renders
            } else if !buildOutRoll.isEmpty { buildOutRoll = [] }
            // §4 STAGE EYE — INPUT roll: while the eye is open, accumulate the watched door's note ONSETS (diff the held set)
            // so the top lane scrolls what arrives. recvHeldNotes is already updated above (editor open ⊇ eye open).
            if buildStageEye, buildStageEyeDoor >= 0, buildStageEyeDoor < recvHeldNotes.count {
                let cur = Set(recvHeldNotes[buildStageEyeDoor].map { Int($0) })
                var inr = buildEyeInRoll
                for n in cur.subtracting(buildEyeInPrev) { inr.append(OutMark(note: UInt8(n), vel: 1, born: mnow)) }
                inr = inr.filter { mnow.timeIntervalSince($0.born) < 2.5 }
                if inr.count > 96 { inr = Array(inr.suffix(96)) }
                if inr != buildEyeInRoll { buildEyeInRoll = inr }
                if cur != buildEyeInPrev { buildEyeInPrev = cur }
            } else if !buildEyeInRoll.isEmpty || !buildEyeInPrev.isEmpty { buildEyeInRoll = []; buildEyeInPrev = [] }
            // idea 24: the edit gesture is over once the chain has been quiet ~0.6s → the OUT diff-highlight relaxes.
            if let e = buildLastEditAt, Date().timeIntervalSince(e) > 0.6 { buildEditStartedAt = nil; buildLastEditAt = nil }
            let strikes = au.pollCellStrikes()             // SEAL comet: stamp a hit time + velocity per struck cell
            if strikes.contains(where: { $0 > 0 }) {
                let now = Date(); var at = cellHitAt, vel = cellHitVel, seq = cellStrikeSeq
                for i in 0..<min(Snap.cells, strikes.count) where strikes[i] > 0 { at[i] = now; vel[i] = Double(strikes[i]) / 127.0; seq[i] &+= 1 }
                cellHitAt = at; cellHitVel = vel; cellStrikeSeq = seq   // MOSAIC: advance the per-cell moment counter
                if activeTab == .build {                            // BUILD grid PIANO-ROLL: fold new strikes into per-cell scrolling notes (at real pitch)
                    let now = Date(); var roll = buildCellRoll; var changed = false
                    for i in 0..<Snap.cells {
                        roll[i].removeAll { now.timeIntervalSince($0.born) > 1.6 }   // drop notes that have crossed
                        guard cellStrikeSeq[i] > buildRollPrevSeq[i] else { continue }
                        let cnt = Int(cellNoteCount[i])
                        if cnt > 0 {                                // REAL pitch: one mark per emitted note
                            for k in 0..<min(cnt, 6) where i * 6 + k < cellNotePitch.count {
                                roll[i].append(BuildRollNote(born: now, vel: Double(cellNoteVel[i * 6 + k]) / 127.0, lane: rollLaneForPitch(Int(cellNotePitch[i * 6 + k]))))
                            }
                        } else {
                            roll[i].append(BuildRollNote(born: now, vel: cellHitVel[i], lane: 0.35 + 0.3 * Double((i &* 40503) % 100) / 100.0))
                        }
                        if roll[i].count > 16 { roll[i].removeFirst(roll[i].count - 16) }
                        changed = true
                    }
                    buildRollPrevSeq = cellStrikeSeq
                    if changed { buildCellRoll = roll }
                }
            }
            if activeTab == .build && nd.playing {         // BUILD piano-roll: prune crossed notes each tick so idle faces pause (matches GridUI's beat prune)
                let now = Date(); var roll = buildCellRoll; var pruned = false
                for i in 0..<roll.count { let n0 = roll[i].count; roll[i].removeAll { now.timeIntervalSince($0.born) > 1.6 }; if roll[i].count != n0 { pruned = true } }
                if pruned { buildCellRoll = roll }
            }
            let sounding = au.pollCellSounding()           // SEAL comet: per-cell note-on/off gate (edge-detected; 128 cells = lo 0…63 + hi 64…127)
            var newSounding = cellSounding, relAt = cellReleasedAt, gateChanged = false
            let nowG = Date()
            for i in 0..<Snap.cells {
                let on = i < 64 ? ((sounding.lo >> UInt64(i)) & 1 == 1) : ((sounding.hi >> UInt64(i - 64)) & 1 == 1)
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
            // Seed the cast, then default PLAY THIS MIDI CHAIN to ON (Paul 2026-08-25). The old reason NOT to auto-engage
            // (the reference-chord fallback that "played chords from nowhere") is GONE — that fallback was removed
            // 2026-08-23, so an engaged chain voice is SILENT until the user holds a note. Engaging on start-up just
            // arms the chain as the workshop voice so a held chord sounds the selected machine straight away.
            // SILENCE ON FRESH START (Paul 2026-08-29): the rooms interface auditions on TAP + starts play columns on their
            // own buttons, so it must NOT auto-arm any voice on launch (that engaged free-run + could leak a passthrough).
            if activeTab == .build { buildSeedCastIfNeeded() }   // (the OLD interface's auto-arm of PLAY THIS MIDI CHAIN retired with buildPage, Paul 2026-08-30)
            // FREE-RUN is no longer a blanket enable (Paul 2026-08-27, FERRY-strike-anchor ①: stopped = silent). It is
            // now GATED on an active BUILD play mode and synced from buildPublishScene() — the .chain request above
            // already published + synced it. Seed false so a non-BUILD entry (defensive; BUILD is the sole surface) stays silent.
            if activeTab != .build { au?.setFreeRunEnabled(false) }
            latchMask = au?.latchArm() ?? latchMask            // re-light the door-arm state at once on a view rebuild (the poll would else take a tick) — Paul 2026-08-27
            replayEngagedMask = au?.replayEngaged() ?? replayEngagedMask
        }
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

    // BUILD is the sole surface (the GRID/MIDI IN/MIDI OUT/MACROS/AUTOMATION tabs were retired 2026-08-21). Size the
    // page to the space it ACTUALLY gets (below the header), not the full viewport — otherwise the column is always
    // taller than the viewport by the header's height → the whole UI scrolls, and the scroll view steals taps from
    // small controls (the piano/MIDI toggle + keys). The GeometryReader fills exactly the remaining height → no
    // overflow → no scroll → touches land. (user 2026-08-12) The deep RackMatrix lives in a BUILD overlay now.
    @ViewBuilder func tabBody(_ geo: GeometryProxy) -> some View {
        GeometryReader { g in
            roomsPage(g.size)   // the rooms interface is the sole surface now (old buildPage retired, Paul 2026-08-30)
        }
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
                   emitPeak: meters.emitPeak,
                   onClaim: setClaim, onClaimLeak: setClaimLeak,
                   onToggleDuck: toggleFlatten, onDuckAmount: setFlatAmount,
                   onToggleAlt: toggleAlt, onAltCount: setAltCnt, onSetTurnsPerNote: setTurnsPerNoteMode,
                   onToggleCurve: toggleCurve, onCurveAmount: setCurveAmt,
                   onToggleFence: toggleFence, onCycleFence: cycleFence,
                   onFenceLo: setFenceLoNote, onFenceHi: setFenceHiNote,
                   onToggleMono: toggleMono, onCycleMono: cycleMono,
                   onTogglePocket: togglePocket, onPocketMs: setPocketMsAmt,
                   onConvLead: setConvLeadSel, onConvStance: cycleConvStanceSel,
                   onClose: { buildRackConfigOpen = false }, embedded: true)   // embedded in the OUTPUT CHAIN sheet (no own header/scroll)
    }


    // The dev diagnostics (a8 stuck-note monitor) as a compact VERTICAL box — sits to the RIGHT of RECEIVERS.
    // delta item 8 PROCESSOR PANELS — procA and procB side by side, each a self-contained face editor with
    // its own COPY (+ PASTE when the clipboard holds a processor).
    // §6d: the two PROCESSOR panels (A/B). PORTRAIT stacks them VERTICALLY (A above B, shorter) so each gets
    // full width (2026-07-27 layout); LANDSCAPE keeps them side by side (the width exists).

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
                       canUndo: buildCanUndo || (au?.uiCanUndo ?? false),   // BUILD undo (the sole surface) + the AU document fallback
                       canRedo: buildCanRedo || (au?.uiCanRedo ?? false),
                       onUndo: undo, onRedo: redo,
                       showScenes: showScenes,                                  // scene row visibility (cog toggle)
                       onOpenManual: { showManual = true },                     // "?" → the in-app manual
                       stepIndex: stepIndex, swing: swing,                      // LAYOUT v2: the clock now lives in the header
                       onStep: { au?.setStepRateIndex($0); refreshTiming() },
                       onSwing: { au?.setSwing($0); refreshTiming() },
                       headerExtras: AnyView(buildHeaderControls()))            // BUILD: RECORD · RATE · MIDI/RACK CONFIG in the header (Paul 2026-08-23)
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
                autoRow
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
    // AUTO-RUN — a CALM self-player (Paul 2026-09-01): the app plays a musical chord loop by itself (free-run on) so it can
    // be left running on device to hear + soak. NOT a fuzzer (that's chaosRow) and NOT a test — it never touches controls.
    @ViewBuilder var autoRow: some View {
        #if DEBUG
        let green = UI.green
        HStack(spacing: 8) {
            if autoOn {
                Button("⏹ AUTO", action: { autoPilot.stop(); autoOn = false })
                    .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 4).fill(green))
                Text(autoStatus).font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(autoStatus.hasPrefix("⚠") ? UI.red : .white.opacity(0.6))
            } else {
                Button("▶ AUTO-RUN", action: { if let au = au { autoPilot.start(au: au); autoOn = true } })
                    .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(green)
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                Text("plays a chord loop by itself (free-run)").font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
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

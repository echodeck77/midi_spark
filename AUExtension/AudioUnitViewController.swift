//  AudioUnitViewController.swift
//  Extension principal class + the diagnostic panel (temporary UI for bridge debugging).

import CoreAudioKit
import SwiftUI
import UIKit
import os

#if DEBUG
// DEV-ONLY FULL RELOAD (Paul 2026-09-11): the header RESET posts this; the VIEW CONTROLLER (which survives the SwiftUI
// rebuild) resets the document to INIT and TEARS DOWN + REBUILDS the hosting controller, so every BUILD @State is
// discarded and reconstructed from the fresh document — a true "just added" state. (loadFactoryPreset alone only reset
// the document; the GUI @State persisted, which is why the button seemed not to respond.)
extension Notification.Name { static let midiSparkReloadUI = Notification.Name("midiSparkReloadUI") }
#endif

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
        #if DEBUG
        NotificationCenter.default.addObserver(self, selector: #selector(reloadFresh), name: .midiSparkReloadUI, object: nil)
        #endif
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

    #if DEBUG
    // Reset the document to the fresh INIT, then rebuild the SwiftUI tree from scratch (new DiagView ⇒ all @State fresh).
    @objc private func reloadFresh() {
        audioUnit?.loadFactoryPreset(named: "INIT")     // flush voices · replace doc with INIT · clear pending BUILD · resync tree
        for child in children {                          // tear down the existing hosting controller
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        embedUI()                                        // children now empty → rebuilds a fresh DiagView over the INIT document
    }
    #endif
}

/// delta item 8: a lifted processor on the clipboard — {type, params, transpose} — COPY'd from one panel,
/// PASTE'able onto any other (A or B, any Machine); a different type retypes the target.

/// Live diagnostics: what the kernel is actually seeing, at 4 Hz.
/// Interpreting it:
///  · PARAM EVENTS rising while you turn a mapped knob → host uses render-side events (kernel handles).
///  · TREE transpose/macro moving but PARAM EVENTS static → host uses setValue (observer/snapshot path).
///  · Neither moving → the mapping isn't reaching this instance (host-side routing).
///  · CC IN rising → raw CC arrives at the MIDI input (and is passed through on A).
/// §11/11b THE ROUND HELD VERBS — the rebuilt authoring surface. Hold a verb → the grid invites → taps do the
/// verb → release = done (no armed state). Long-press a verb = LATCH (tap again releases). No verb held → taps
/// are TRIGGERS. HOLD (the 6th button) is the §5c gesture-latch, not a grid verb.

/// HISTORICAL (LAYOUT v2, 2026-08-05): a tab-per-surface era briefly existed (GRID/PROCESSORS/RECEIVERS/EMITTERS/
/// MACROS/AUTOMATION) — RETIRED 2026-08-21. See the note below.
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
    var wasPlaying = false        // dejitter: transport-edge detector for syncBeat
    var lastTempo = 120.0         // dejitter: tempo-change detector for syncBeat
    func emitter(_ i: Int, peak: Double) { guard i >= 0, i < 4 else { return }; emitPeak[i] = peak; emitPeakAt[i] = Date() }
    func receiver(_ i: Int, peak: Double) { guard i >= 0, i < 4 else { return }; receiverPeak[i] = peak; receiverPeakAt[i] = Date() }
    // DEJITTER (Paul 2026-09-11): the playhead stutter cure. `nd.beat` is the host beat sampled at the START of the last
    // render block; stamping it against the main-thread `Date()` every 4 Hz poll baked a VARYING clock-offset (render/output
    // latency + main-thread jitter) into the extrapolation base → the playheads lurched ~4×/s on a steady tempo. Fix: only
    // HARD re-anchor on a genuine discontinuity (first tick / transport start / tempo change / a jump = loop/seek); otherwise
    // FREE-RUN from the existing anchor (host tempo is exact, so drift is negligible) so 4 Hz sampling jitter never shows.
    func syncBeat(_ b: Double, tempo t: Double, playing: Bool, at when: Date) {
        beat = b                  // raw polled beat kept for the InputMark roll etc.
        let predicted = beatAnchor + when.timeIntervalSince(beatAnchorAt) * t / 60.0
        if !playing || !wasPlaying || t != lastTempo || abs(b - predicted) > 0.25 {
            beatAnchor = b; beatAnchorAt = when
        }
        tempo = t; wasPlaying = playing; lastTempo = t
    }

    // The per-cell STRIKE / SOUNDING / NOTE-SWEEP / ROLL feed (Paul 2026-09-10): the 4 Hz poll writes these on every tick that
    // carries notes. As @State on the giant DiagView, each write re-ran the WHOLE BuildPage body — the on/near-each-step, and
    // rapid-arp, choppiness. Held here (not @State) they mutate WITHOUT a body re-run; the two consumers — the emitter fader
    // and buildNoteSweep — read them LIVE inside their 30 fps TimelineViews, exactly like emitPeak. Index = col*Snap.rows+row.
    var cellHitAt     = [Date](repeating: .distantPast, count: Snap.cells)   // SEAL comet: last-strike time (UI owns the decay)
    var cellHitVel    = [Double](repeating: 0, count: Snap.cells)            // last-strike velocity 0…1 (the fader's release-decay start)
    var cellStrikeSeq = [Int](repeating: 0, count: Snap.cells)              // per-cell strike-moment counter → drives the roll fold
    var cellSoundVel  = [Double](repeating: 0, count: Snap.cells)            // SOUNDING velocity 0…1 (stays up while HELD) — the fader floor
    var cellSounding  = [Bool](repeating: false, count: Snap.cells)          // is the cell sounding now (gate for the release decay)
    var cellReleasedAt = [Date](repeating: .distantPast, count: Snap.cells)  // falling-edge stamp → the fader decays from here
    var cellNotePitch = [UInt8](repeating: 0, count: Snap.cells * 6)         // NOTE-SWEEP: per-cell recent emitted notes (6 slots/cell)
    var cellNoteVel   = [UInt8](repeating: 0, count: Snap.cells * 6)
    var cellNoteCount = [UInt8](repeating: 0, count: Snap.cells)
    var cellRoll: [[BuildRollNote]] = Array(repeating: [], count: Snap.cells)   // the drifting piano-roll notes per cell (buildNoteSweep)
    var rollPrevSeq   = [Int](repeating: 0, count: Snap.cells)              // last folded strike-seq per cell (the roll fold's diff)
    var partRollNotes: [[PartRowRollNote]] = Array(repeating: [], count: Snap.rowsPerFerry)   // PART grid's live per-row piano-roll (Paul 2026-09-29) — held here (not @State), same reason as cellRoll
    var selectRollNotes: [PartRowRollNote] = []   // SELECT grid's live scrolling piano-roll on the auditioning cell (Paul 2026-09-29) — one row, same reason as partRollNotes
    var lastStep = -1   // step-boundary detector for the quantized voice-switch commit (replaced .onChange(of: d.absoluteStep))
}

/// PART ROW ROLL (Paul 2026-09-29): the fixed trailing fade window, in musical BEATS (not wall-clock seconds — this
/// page is tempo-synced everywhere else; a wall-clock fade would visibly drift relative to the beat-synced sweep
/// under a tempo change). Module-internal (not `private`) — read by both the poll/reconcile in AudioUnitViewController
/// and the draw in BuildPage's roomsPartNoteRoll; extensions can't add stored properties, so this can't live on a type.
let partRollFadeBeats = 4.0   // was 2.0 (Paul 2026-09-29: increase the fade time)

/// SELECT ROLL (Paul 2026-09-29): how many beats of history the auditioning SELECT cell's width represents, right
/// edge = now, left edge = this many beats ago. A SELECT cell is one grid column, not a whole PART row, so it has
/// meaningfully less horizontal room than partRollFadeBeats' context — a smaller, separately-tunable default.
let selectRollWindowBeats = 2.0

/// PART ROW ROLL (Paul 2026-09-29): one tracked note in a part row's live piano-roll overlay. `onBeat` is the RAW
/// (un-swing-warped) beat from Router.Voice.onBeat — swing-warp is applied only at draw time (roomsPartNoteRoll),
/// never baked in here, so it can never drift from what the playhead itself does with the same raw beat.
struct PartRowRollNote: Equatable {
    var pitch: UInt8, vel: UInt8
    var onBeat: Double        // true onset beat (raw)
    var heldToBeat: Double?   // nil = still sounding (bar's head rides the live playhead); non-nil = frozen release point (raw beat)
}

// Paul 2026-09-05: the WHOLE part-grid state, archived onto a play cell when a part/cell is promoted FROM the part grid, so
// the part can be RESTORED later (restore is currently unimplemented). In-memory (value copy) this session.


struct DiagView: View {
    weak var au: MidiSparkAudioUnit?
    @State var d = KernelDiag()      // polled for the grid's effColumn / playing
    @State var lastStuckPanics: UInt64 = 0   // a8 STUCK-NOTE: last-seen heal count — the poll logs a heal ONCE (off the render thread) when this rises
    static let hangLog = OSLog(subsystem: "com.paulbarrett.MidiSpark", category: "hang")   // a8 corpse log — now written from the MAIN thread (the render thread only records counts) so it can't crackle the audio
    @State var uiAppeared = true     // §4c INVISIBLE=FROZEN: this view is on-screen (host shows our plugin)
    @State var appActive = true      // §4c: the app is foregrounded
    var animationsPaused: Bool { !(uiAppeared && appActive) }   // hidden OR backgrounded ⇒ freeze the canvas
    @State var loadedID = "—"
    @State var sceneEmpty: [Bool] = []       // MULTI-SCENE: per-slot occupancy (empty ⇒ a "+" save slot)
    @State var activeSceneIdx = 0             // MULTI-SCENE: the playing scene
    // (the arrangement bar's own interactive state — pending/recue/blink/drag/sweep-anchor/shake — lives in ArrangementBar)
    @State var showSettings = false           // AB: the ⚙ cog page (settings overlay — engine never stops)
    @State var activeTab: AppTab = .build     // BUILD is the default landing page (user 2026-08-11); the AnyView boundaries fixed the metadata-stack crash
    // BUILD page (user 2026-08-11): the selected PART's cast machine (index into the part palette; −1 = none). Placement-skeleton state.
    @State var buildSelReceiver: Int = 0      // BUILD left column: the INPUT door (R1–R4) the machine's INPUT face edits
    // BUILD verbs (iteration 4: drag retires → PLACE · MOVE · DELETE spring-held verbs). The armed verb (nil = none).
    @State var buildPlaceArmed: Bool = false         // PLAY-grid PLACE mode — a standalone toggle (NOT the staging radio); armed from the left PLACE button
    @State var buildEditSlot: Int? = nil        // BUILD footer: which chain slot's processor pop-up editor is open (nil = closed)
    @State var buildEditSlotDir: Int = 1        // ProcessorBox's slide-in direction for its NEXT swap (±1) — derived from buildEditSlot's own left/right movement through the chain, below (Paul 2026-09-29)
    @State private var buildEditSlotLast: Int = 0   // the last-known buildEditSlot value, kept purely to compute the direction above
    @State var buildSelectedProcessing = false  // PLAY-STATE GREY (Paul 2026-09-14): is the SELECTED machine's active cell sounding NOW? Updated (deduped) in the 4 Hz poll; feeds the processor editor's grey-when-idle. false = grey the controls (still usable).
    // EUCLID DRAG HUD (Paul 2026-10-02): reported UP from `ProcessorBox.onEuclidDragInfo` while dragging a comet
    // bar — lives HERE (not inside ProcessorBox) specifically so `buildProcessorPanel` can render the actual HUD
    // as a sibling OUTSIDE its own ScrollView, escaping the "fixed on the scrolling processor edit page" bug.
    @State var euclidDragHUDInfo: EuclidDragHUDInfo? = nil
    // PART AUTOMATION (Paul 2026-09-01): the 6-region Auto flow — AUTO 1–5 · processor · parameter · before/after · span ·
    // apply. Macros dropped to v2; each chain gets 5 direct-to-param automation lanes. The lanes live per-machine.
    // PART AUTOMATION (Paul 2026-09-02): per machineID → its automation (which lane is active + its 5 lanes). The ACTIVE
    // lane is per-machine (each machine's automation is independent); the focused machine's active lane drives the band.
    @State var buildAutoLanes: [String: PartAutoMachine] = [:]
    // PART ENTRY DEFAULT (Paul 2026-09-02): false until the user EDITS the part grid (selects a rung/row, stamps, punches,
    // edits the machine). While false, entering the PART room defaults the selected row to the currently-playing (audition)
    // machine's row. Reset to false when a fresh part is created, so a new part re-defaults.
    @State var buildPartTouched: Bool = false
    @State var buildAddSlot: Int? = nil         // BUILD footer: which empty box's ADD-PROCESSOR picker is open (nil = closed)
    // DRAG-TO-REORDER the chain (Paul 2026-08-25): a custom finger-track (native .onDrag doesn't survive the AU host).
    @State var buildChainDragFrom: Int? = nil   // the processor box being dragged (nil = no drag in flight)
    @State var buildChainDragLoc: CGPoint = .zero   // finger location in the "chainBlock" coordinate space
    @State var buildChainDropTo: Int? = nil     // the slot index under the finger (highlighted; committed on release)
    @State var buildChainOverTrash: Bool = false  // the dragged processor box is over the DELETE trash (left flank) — drop = remove (Paul 2026-09-10)
    @State var buildChainDragMoved: Bool = false  // the held box has actually MOVED (a real drag) — gates the DELETE trash so it shows on DRAG only, not on the hold (Paul 2026-09-11)
    @GestureState var chainDragActive: Bool = false   // TRUE only while a chain box is actively HELD/dragged — AUTO-RESETS when the gesture ends OR is cancelled (so the trash + destination highlights never stick visible). Paul 2026-09-10
    @State var buildChainClipboard: [ProcessorSlot]? = nil   // COPY/PASTE buffer: a copied chain, pasted into a new row position
    // FERRY DRAG-AND-DROP (Paul 2026-09-12): drag a SELECT cell / play ferry onto a ferry (populate / move) or the machine-box
    // trash (delete). Tracked in the shared "rooms" coordinate space; mirrors the chain-drag pattern (auto-resetting gesture state).
    @State var buildFerryDrag: FerryDragSource? = nil            // what's being dragged (nil = no drag)
    @State var buildFerryDragLoc: CGPoint = .zero                // finger location in the "rooms" space
    @State var buildFerryDragMoved: Bool = false                 // a real drag is underway (gates the ghost + trash + hover ring)
    @State var buildFerryHover: FerryDropZone? = nil             // the drop zone under the finger
    @State var buildFerryZones: [FerryDropZone: CGRect] = [:]    // drop-zone frames (8 ferries + trash) in the "rooms" space
    @GestureState var ferryDragActive: Bool = false              // TRUE only while a ferry drag is live — AUTO-RESETS on end/cancel so nothing sticks
    @State var buildFerryHueAlloc: [Int: UInt32] = [:]           // EMPTY-ferry colour reallocation: slot → displaced colour (populated ferries carry their hue on the part). Paul 2026-09-12
    // PROCESSOR EDITOR transaction (Paul 2026-08-19): the machine's chain as it was when the editor OPENED, so CANCEL can
    // revert (edits are live-previewed; exit keeps, cancel reverts) and the row-selector "overwrite" can restore the source.
    // I/O toggle LONG-PRESS → apply to EVERY row (Paul 2026-08-19): a "Hold to apply to all" hint shows a moment into the hold.
    @State var buildIOHoldMsg: String? = nil
    @State var buildIOHoldPressing = false
    @State var buildRowUnder: [String?] = Array(repeating: nil, count: Snap.rowsPerFerry)   // one-machine-per-row: each row's revert-to machine when its machine relocates
    @State var buildDeletedRows: [Int: [String?]] = [:]  // DELETE verb: a staging row's saved contents (for restore on 2nd press)
    @State var buildStagingSel: [Int] = Array(repeating: -1, count: Snap.maxCols)   // §E: 16-wide; the ONE selected (playing) row per staging COLUMN (white outline); -1 = none
    @State var buildStagingMulti: [UInt8] = Array(repeating: 0, count: Snap.maxCols)   // MULTI-SELECT (2026-09-27): bits 0..<rowsPerFerry = which rows ALSO sound per column, when the active ferry's selMulti is on; 0 = no mask (falls back to buildStagingSel's lead)
    @State var buildRowSelectRevert: (row: Int, prev: [Int], prevMulti: [UInt8])?   // left-rail row-select: the per-column selection (+ multi mask) BEFORE the last rail tap, so a 2nd tap on the same rail reverts an accidental whole-row select (Paul 2026-09-15; multi mask added 2026-09-27)
    @State var buildRowChain: [[ProcessorSlot]] = Array(repeating: [], count: Snap.rowsPerFerry)   // STAGE THE GRID: the generated machine (chain) for each row (empty = not a staged row)
    @State var buildRowShade: [Double] = Array(repeating: 0, count: Snap.rowsPerFerry)   // STAGE THE GRID: per-row shade of the selected machine (+lighter … −darker), by output complexity
    @State var buildParts: [BuildPart] = [BuildPart()]   // the PARTS (workshop lifecycle); the CURRENT part's fields live in the working @State below, synced on switch
    @State var buildCurrentPart: Int = 0                 // index of the part currently on the build column
    @State var buildPartEmitters: Set<Bus> = [.a]        // the CURRENT part's output emitters (part-owned I/O; every machine follows)
    @State var buildPartRate: StepRate? = nil            // PER-PART CLOCK (Paul 2026-08-19): the CURRENT part's step rate (nil ⇒ scene default) — deployed parts play at independent tempos
    @State var buildPartLen: Int? = Snap.maxCols         // PER-PART CLOCK: the CURRENT part's loop length 1…16 — DEFAULTS to 16 steps (Paul 2026-09-09); a loaded part restores its own length (nil ⇒ 8 for old docs)
    @State var buildPartLoopCols: [Int] = []             // PART LOOP SELECTION (Paul 2026-09-26): the CURRENT part's ordered loop columns; empty ⇒ play the whole part
    @State var buildPartCast: [String] = []              // the CURRENT part's cast MEMBERSHIP (visible palette over the global store); §2 cast view
    @State var buildCastSlots: [Int: String] = [:]       // §2 explicit slot→machineID for non-default machines (long-press places a machine on its pressed cell)
    @State var buildCastSeeded: Bool = false             // seed part 1's cast from the already-defined machines ONCE on first BUILD appear
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
    @State var buildRowReceiver: [Int?] = Array(repeating: nil, count: Snap.rowsPerFerry)
    @State var buildRowEmitters: [Set<Bus>?] = Array(repeating: nil, count: Snap.rowsPerFerry)
    @State var buildPendingSource: [ProcessorSlot] = []  // the chain the pending tab was copied from — diverge = PLACED
    @State var buildRow8Cells: [Row8Cell] = Row8Cell.factoryDeck   // ROW 8 (Paul 2026-08-22): the authored action cells (refreshed from the document)
    @State var buildRow8On: [Bool] = Array(repeating: false, count: 8)   // ROW 8: the active scene's lit TOGGLE state
    // SCENES V2 (Paul 2026-08-12): in-memory play-grid arrangements. buildScenes holds the SAVED arrangements; index 0 is
    // the live one until the user captures more. Switching saves the current then restores the target (arrangement only —
    // parts/machines/master are shared). v1: not persisted, instant switch.
    @State var buildScenes: [BuildSceneSnapshot] = []
    @State var buildActiveScene: Int = 0
    @State var buildMidiConfigOpen: Bool = false   // BUILD [MIDI CONFIG] → the MIDI INPUTS sheet (config-sheets stage 5, Paul 2026-08-20)
    @State var buildMidiConfigTab: Int = 0         // MIDI INPUTS: which door (A–D) tab is shown (Paul 2026-08-23)
    @State var buildRackConfigOpen: Bool = false   // BUILD [RACK CONFIG] → the OUTPUT CHAIN sheet (config-sheets §6, Paul 2026-08-21)
    @State var buildScalePopupDoor: Int? = nil     // FOUR SCALE POOLS (Paul 2026-09-04): the strip SCALE button opens the 4-pool switch/config pop-up for door i
    @State var buildChordPopupDoor: Int? = nil     // THE CHORD DOOR (Paul 2026-09-04): the strip CHORD button opens the 4-chord switch/config pop-up for door i
    @State var buildMidiOutConfigOpen: Bool = false // BUILD [MIDI OUT] → the emitter stamp-channels sheet (moved out of the cog, Paul 2026-08-23)
    @State var buildFileImportDoor: Int? = nil     // FILE import: which door is picking a .mid (nil = closed)
    @State var buildRangeKbdDoor: Int? = nil       // RANGE picker: which door's keyboard is open (nil = closed)
    @State var buildRangeSetHi: Bool = false       // RANGE picker: setting the MAX bound (else MIN)
    // BUILD staging grid — an EPHEMERAL workshop store ([col][row] → machineID; nil = blank). Not the real scene; the
    // engine-backed ephemeral staging document + audition is a later slice. PLACE stocks a machine here.
    @State var buildStagingCells: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: Snap.maxCols)   // §E: 16-wide part grid
    // buildPlayFerryRow RETIRED (Paul 2026-09-12 dead-code sweep — the ▲▼ ferry-row cursor is gone; never read/written).
    @State var buildSelectMode: Bool = false   // SELECT MODE (Paul 2026-08-31): a toggle under the machine play button — while on, every cell (select + ferry) lights white and a TAP only FOCUSES it into the machine (no start/stop), for editing/viewing
    // THE PLAY GRID — each column is a FULLY INDEPENDENT voice (Paul 2026-08-29): it starts/stops on its own.
    // buildPlayColOn = per-column play state. (buildPlayPlaying is now a computed "any column on", in the BuildPage
    // extension.) FERRY ROW UNIFICATION (Paul 2026-09-27): the old buildPlayColRecv/Emit/Len/Steps/Rate/StepRecv/
    // StepEmit "flatten cache" is GONE — every ferry now composes straight from its own BuildPart (buildFerryParts,
    // below) every publish, so there's no separate derived-playback representation left to keep in sync.
    @State var buildPlayColOn: [Bool] = Array(repeating: false, count: 8)
    @State var buildPlayColMute: [Bool] = Array(repeating: false, count: 8)   // per-ferry MUTE (Paul 2026-09-09) — the M button; ephemeral like buildPlayColOn
    @State var buildPlayColSolo: [Bool] = Array(repeating: false, count: 8)   // per-ferry SOLO — the S button; if any is set, only soloed ferries sound
    // PLAY-FERRY LAUNCH (Paul 2026-09-09): per-FERRY launch anchor beat (8-wide; 0 = no anchor). Stamped on launch
    // (buildToggleFerryPlay), cleared on stop; buildPublishScene fans each ON BACKGROUND ferry's anchor across all of
    // its own dedicated engine rows (Snap.ferryRowBase(t)..<+rowsPerFerry) — the active ferry is excluded (stays
    // transport-locked). Runtime only (not persisted). `launchBeat` mirrors the un-anchored launch beat (Phase-2b one-shot).
    @State var launchAnchor: [Double] = Array(repeating: 0, count: 8)
    @State var launchBeat: [Double] = Array(repeating: 0, count: 8)
    // THE PLAY FERRIES ARE PARTS (Paul 2026-09-08, AcceptanceCriteria-play-ferries-as-parts): each of the 8 ferries
    // owns ONE full BuildPart (nil = empty) — the SOLE source of truth for what a ferry plays, active or background
    // alike (buildActiveFerry = the ferry whose part is loaded on the bench; nil = browsing the SELECT grid).
    @State var buildFerryParts: [BuildPart?] = Array(repeating: nil, count: 8)
    @State var buildActiveFerry: Int? = 0   // a selector is ALWAYS selected (Paul 2026-09-12): defaults to 0 so its pre-allocated colour is the "selected colour" from launch
    // ROW-CREATOR CONFIRM (Paul 2026-09-11): after MUTATE/RANDOM generates a row's machine, that row shows KEEP | TRY AGAIN
    // in place of the creator buttons until the user picks one (KEEP dismisses; TRY AGAIN regenerates + re-offers). nil = none.
    @State var buildRowGenConfirm: RowGenConfirm? = nil
    // ROW-CREATOR PROGRESS (Paul 2026-09-29): the row-creator's MUTATE/RANDOM/TRY-AGAIN now run off-main like the
    // machine-box versions, showing a progress bar in the SAME row footprint. buildRowGenRow = which row (nil = none
    // busy) — keyed by row, not a bare bool, since a different row could in principle be selected while one is still
    // generating in the background.
    @State var buildRowGenRow: Int? = nil
    @State var buildRowGenProgress: Double = 0
    // BUILD one-workshop-voice: PLAY THE STAGING GRID is active (mutually exclusive with PLAY THIS MACHINE / ddSolo).
    @State var buildVoiceOwner: BuildWorkshopVoice = .none   // SINGLE SOURCE OF TRUTH for the page-owned audition voice (none | chain | part). ddSolo/buildStagingPlaying are computed mirrors of this (Paul 2026-08-31) — one owner, so a play-ferry stop can never leave the shared audition sounding.
    // BUILD workshop voice = which of the two SHOP sections sounds: the MIDI CHAIN audition, the PART grid, or NEITHER.
    // Each header toggles its own section (play ⇄ stop), so BOTH can be stopped (Paul 2026-08-15). The two never sound
    // together (picking one stops the other) — the PIECE (play grid) is independent of this.
    @State var buildPendingWorkshopVoice: BuildWorkshopVoice? = nil   // an armed voice switch, applied on the next cell boundary (nil = none)
    @State var buildPendingReengage: Bool = false      // a palette machine change made while the chain audition plays — re-engage on the next cell boundary (seamless)
    @State var ddMachineSel: Int = -1          // DRAG&DROP page: the selected palette machine index (−1 = none)
    @State var buildSelID: String? = nil      // BUILD: the selected machine BY ID (supports ephemeral machines beyond the 16); nil = none
    @State var buildMachineReg: [String: [ProcessorSlot]] = [:]   // BUILD: ephemeral machines' machines (id → chain), beyond the 16 document slots
    @State var buildMachineTranspose: [String: Int] = [:]        // BUILD: ephemeral machines' REGISTER HOME (id → transpose), for the ensemble roll
    @State var buildIDCounter: Int = 0        // BUILD: monotonic source for ephemeral machine IDs ("b0", "b1", …)
    // BUILD UNDO (Paul 2026-08-27): the BUILD page authors in @State, invisible to the AU document undo stack — so it gets
    // its OWN undo. Each snapshot captures the WHOLE authoring @State + the document, so a restore is always complete (never
    // partial/corrupting); an action that forgets to record is simply not undoable, never corrupt. `buildUndoKey` coalesces
    // a continuous gesture (a scrub / drag) into one step.
    // `buildUndoKeyAt` (Paul 2026-09-29 fix — "added two processors, undo dropped both"): a SLIDING TIME WINDOW on the
    // coalesce, not just key equality. `buildApplyChain` funnels every chain edit — add/remove/move/type/bypass/param —
    // through the SAME "chain" key, so two genuinely separate discrete taps (add processor A, then add processor B) were
    // silently merging into one undo step purely because both happened to reuse that key, with nothing to tell "still the
    // same drag" apart from "a brand-new tap." A real slider drag's onChanged ticks land well under 600ms apart; two
    // separate taps — which need the user to lift a finger, read the UI, and touch again — never do. See buildRecordUndo.
    @State var buildUndoStack: [BuildSnapshot] = []
    @State var buildRedoStack: [BuildSnapshot] = []
    @State var buildUndoKey: String? = nil
    @State var buildUndoKeyAt: Date? = nil
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
    // THE SELECT-PAGE SOURCE (Paul 2026-09-06): the ONE model value for what the machine points at on SELECT — a browse CELL or
    // a part-row FERRY. Replaces the two mutually-exclusive Int? (buildGridSelSel / buildGridSelStampSourceRow), which are now
    // COMPUTED projections over this (see BuildPage) — so the exclusivity is a type guarantee, not a hand-synced pair.
    @State var buildSelectSource: BuildSceneLogic.SelectSource = .none
    @State var buildSelectGreyAlt: Bool = false          // SELECT machine grey ALTERNATES between two bright shades on each new selection, so a new pick visibly shifts even though the audition stays "gsAud" (Paul 2026-09-01)
    @State var buildGridSelGenerating = false            // DEALT is computing (disable the grid + show a spinner)
    @State var buildMachineGenerating = false            // the machine-box RANDOMIZE/MUTATE is generating off-main (spinner + disable) — Paul 2026-09-13
    @State var buildMachineGenProgress: Double = 0       // 0...1 — drives the machine-box bar (Paul 2026-09-29, was an indeterminate spinner)
    @State var buildGridSelActiveRoll: [GridSelBar] = []  // the auditioning chain's piano-roll (offline render, shown on the active cell + right column)
    @State var buildGridSelCellRoll: [Int: [GridSelBar]] = [:]   // per-CELL piano-roll fingerprints (bg-computed per deal/tab) — the drifting note face on every present cell (Paul 2026-08-26)
    @State var buildGridSelRollGen = 0                   // generation token so a stale bg roll batch (deal/tab changed under it) is discarded
    // buildGridSelStampRow/At/FlashRow/FlashAt (+ buildFerryHeld below) are RETIRED (Paul 2026-09-12): the ferry/rail
    // long-press copy + its rising-fill/commit-flash animation are gone — replaced by ferry drag-and-drop.
    @State var buildPartJustPromoted = false             // Paul 2026-09-05: a part was flattened to a play ferry → the NEXT new select-grid cell starts with null I/O + pulsing toggles.
    @State var buildIONullPending = false                // Paul 2026-09-05: the 8 I/O toggles show null + pulse invitingly (the cell is silent until wired); cleared on the first I/O edit.
    @State var buildGridSelOverride: [Int: (chain: [ProcessorSlot], hex: UInt32)] = [:]   // NEW INTERFACE (Paul 2026-08-28): SELECT cell-to-cell copies land here as NEW in-memory INSTANCES (position → chain+hue) — the saved library on disk is never overwritten. Cleared on re-deal / tab switch.
    @State var buildGridSelName: [Int: String] = [:]   // a short lowercase hash NAME assigned to a SELECT cell on its FIRST edit (Paul 2026-09-12): the cell then shows the selector's colour + this name. Cleared on re-deal.
    @State var buildGridSelLibFactoryFrom = 0            // buildGridSelLib[i] with i >= this is a FACTORY cell (resolve by section, not name)
    @State var buildGridSelPriorSel: String? = nil
    @State var buildGridSelLastSlot: [Int: Int] = [:]     // per SELECT-grid cell index → the last processor slot VIEWED there; leaving remembers it, returning re-opens it (Paul 2026-09-10)
    @State var buildGridSelLastPick: Int? = nil           // RETURN-TO-SAME-CELL (Paul 2026-09-27): the browse-cell index active when PART last claimed the shared select-source (buildRoomsSetActiveSide always nils buildGridSelSel — "one thing active"); roomsSelectSetup restores it on a plain part→select return so the pick isn't lost. Synced (nil included) on every PART entry, so a deliberate deselect before leaving isn't resurrected.
    @State var ddStickyReceiver: Int = 0      // sticky: the LAST receiver chosen → the default input for a fresh cell (R1 = 0)
    @State var ddStickyBuses: Set<Bus> = [.a] // sticky: the LAST emitters chosen → the default output for a fresh cell (Emitter A)
    // (the playhead beat anchor moved into `meters` — a @State-held class — so its 4 Hz re-anchor doesn't re-run the body)
    // ddSolo / buildStagingPlaying are now COMPUTED mirrors of buildVoiceOwner (see BuildPage) — not stored state.
    @State var showManual = false             // the "?" → the in-app manual overlay (scrolled to the last-touched control)
    @StateObject var helpTracker = HelpTracker()   // records the last-touched control's manual anchor (silent — no @Published)
    static let manualBlocks = ManualDoc.parse(ManualDoc.load())   // the parsed manual (once ever)
    @AppStorage("midispark.showScenes") var showScenes = false   // the scene row is HIDDEN by default; toggled on the cog page
    // ORIENTATION (Paul 2026-10-01): a device-wide layout handedness preference — same persistence class as showScenes
    // (an @AppStorage display preference, not a PluginState/document field, since it's about the USER's own setup, not
    // any one project). TRUE (the NEW default) = machine column/receivers/emitters on the LEFT, the machine-box's
    // trash+row-rail flank on the RIGHT (swapped with the verb-button cluster), and the part grid's numbered rail on
    // the LEFT with the chevron rail on the RIGHT. FALSE = the classic layout (main's shape before this toggle existed).
    @AppStorage("midispark.roomsLeftOriented") var roomsLeftOriented = true
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
    @State var cellLibraryFromBuild = false   // the browser was opened from the BUILD page → save/stamp target the SELECTED MACHINE's chain, not an EDIT cell
    @State var buildLibraryOriginalChain: [ProcessorSlot]? = nil   // the selected machine's chain at library-open — restored if the user leaves without APPLY
    @State var buildLibraryPreviewed = false                       // a preview temporarily overwrote the machine's chain (not yet committed)
    @State var cellLibraryList: [LibEntry] = []
    // MACRO AUTHORING FLOW (canonical, spec macro-authoring): the per-group MAIN/ALT authoring page.
    // FLOW-DIAGRAM processor pop-up (user 2026-08-07): tap a populated processor box → edit its full controls; tap an
    // empty box → the type picker. APPLY keeps · CANCEL restores the document snapshot taken on open.
    @State var scene = SceneState.empty()
    // brush (the view-local paint Machine) RETIRED (Paul 2026-09-12 dead-code sweep — never read/written; the desk-brush wiring was never implemented).
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
    @State var ladderMode = false            // LADDER: exclusive-columns mode (mirror of au.uiLadderMode; LADDER factory presets)
    // The per-cell STRIKE / SOUNDING / NOTE-SWEEP / ROLL feed moved into `meters` (LiveTelemetry) so its 4 Hz per-note writes
    // no longer re-run the whole BuildPage body — see the class. Only the OFFLINE part-roll + drag/transport state stay @State.
    @State var partRollNotes: [PartRollDeck.Note] = []   // PART ROLL: the part's exact output (the OFFLINE feed, recomputed on input/selection/edit change — no lag)
    @State var partRollSig: String = ""                  // the recompute key (input · selection · rate · edit generation) — skip identical recomputes
    @State var partRollComputing = false                 // an offline part-roll render is in flight OFF-MAIN (one at a time) — the 188× Router loop no longer stalls the main thread (Paul 2026-09-11)
    @State var buildPartRollGen: Int = 0                 // bumped by buildPublishScene so a CELL/CHAIN edit forces an offline recompute (even if the selection didn't change)
    @State var buildPartDragLast: Int? = nil   // PART GRID (Paul 2026-09-02): the last cell touched in the current tap/drag selection (nil = no active drag)
    @State var buildHostHalted: Bool = false   // TRANSPORT (Paul 2026-09-02): the host stopped while we were following it → HALT (free-run off), cells stay armed; cleared on host START or an explicit BUILD play
    // §6a meter peaks (emitter + receiver) live in `meters` — a @State-held class so the 30 Hz updates DON'T re-run the
    // body (CPU, device 2026-08-24). The meter TimelineViews read `meters.emitPeak`/`emitPeakAt` etc. live through the reference.
    @State var meters = LiveTelemetry()
    @State var emitDragVel: [Int?] = [nil, nil, nil, nil]     // BUILD emitter fader: the live drag velocity override per emitter (nil = not dragging)
    @State var recvDragVel: [Int?] = [nil, nil, nil, nil]     // BUILD receiver fader: the live drag input-velocity override per door (nil = not dragging)
    @State var recvHeld: [[Double]] = [[], [], [], []]        // duration: currently-held input velocities per receiver (0–1) — the MIDI-IN length bar reads this
    @State var recvHeldNotes: [[UInt8]] = [[], [], [], []]    // per-door held input PITCHES (config-sheets REPLAY roll, Paul 2026-08-20)
    @State var buildOutRoll: [OutMark] = []                   // Stage Eye OUTPUT lane only now (Paul 2026-09-28: the truth strips' own OUT roll became a piano)
    @State var buildOutHeld: [Int] = []                       // §1 TRUTH STRIPS: the focused processor instance's currently-SOUNDING output pitches (editor-open only)
    @State var buildOutProcessing: Bool = false                // §1 TRUTH STRIPS: is MIDI reaching this instance right now (Paul 2026-09-29) — polled alongside buildOutHeld so the two can never disagree; see buildTruthStrips
    @State var buildRiffDrunkPos: Int = -1                     // RIFF's DRUNK walk position for the focused cell (editor-open only); −1 = unknown/not this mode (Paul 2026-09-28)
    @State var buildEuclidLineReady: UInt8 = 0                 // EUCLID beacon readiness bits for the focused cell (editor-open only); 0 = unknown/not this mode (Paul 2026-10-05)
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
    @State var docMachines: [Machine] = []
    @State var receivers: [Receiver] = []                     // delta §9 item 11: the RECEIVERS panel
    @State var stepIndex = 2
    @State var swing = 50
    // MODELESS (2026-07-27): GRID CONTROLS — the verb palette. Radio-armed; INSPECT is functional in 1b, the
    // others render inert until their increments land. EDIT mode survives alongside until verb coverage completes.
    @State var laneMask: UInt16 = 0     // §5b lap: held column keys (bit i = column i), PERFORM only
    @State var buildStagingLane: UInt16 = 0   // PER-ROW LAP (Paul 2026-08-19): the BUILD STAGING grid's own column-loop
    @State var soloEmitterMask: UInt8 = 0  // the derived emitter solo set (mirrors emitterFootSolo)
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
    let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    // A dedicated ~30 Hz drain for the peak METERS only (output + input velocity indicators), decoupled from the 4 Hz
    // poll so they track live input instead of lagging up to 250 ms (Paul 2026-08-21). Cheap read-and-clear; when idle
    // the feed returns 0 → no @State write → no re-render.
    let meterTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    // §5b COLUMN-SUBSET LAP: the PERFORM multi-column hold reports the held-set bitmask here. Push it to
    // the engine (ephemeral, never persisted) and keep a copy for the key LOOP highlight. Cleared to 0
    // on release (the overlay reports empty) and on the EDIT switch (see the mode toggle).

    // EDIT/PERFORM toggle. Leaving PERFORM ends any lap (belt-and-suspenders — the overlay also cancels).

    // emitter-strip foot SOLO: clear on transport stop.
    func clearOnTap() {
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

    // (armLadderRung + ladderDim — the retired in-grid LADDER's arm-and-blink tap machinery — removed 2026-09-03, zero
    //  callers after the GridView/old-UI cascade. LADDER factory presets still drive active rows via syncSingleModeActivation.)
    /// The blinking cells while a SINGLE switch/mute is pending (commits at the column's next entry). The CURRENTLY
    /// ACTIVE cell flashes to show it's about to DEACTIVATE (user 2026-08-07 — whether the touched cell is populated
    /// or empty); an incoming POPULATED rung also flashes to show where the column is going (an empty rung shows nothing).

    // emitter-strip foot SOLO: push the union to the kernel whenever it changes.
    func refreshTapMasks() {
        if soloEmitterMask != emitterFootSolo { soloEmitterMask = emitterFootSolo; au?.setSoloEmitterMask(emitterFootSolo) }
    }

    let sceneAmberHue = UI.amber   // HOLD's latch hue
    // delta §5c: HOLD LATCH — while ON, releases latch instead of springing; HOLD-off is the synchronous
    // "drop" (every captured gesture releases at once). PERFORM-only; cleared on transport stop / EDIT.
    // v1 captures: §6a velocity overrides (in OutputsView) + audition (below). Lap + ON-HOLD deferred.
    func setHold(_ on: Bool) {
        guard holdLatch != on else { return }
        holdLatch = on
        if !on {                                 // the drop: release the captures this layer owns
            au?.setHoldCell(-1)                             // §9 item 1: a latched ON HOLD drops too
            au?.setLaneMask(0); laneMask = 0     // §5c: the latched lap set drops too (velocity springs
                                                 // back via OutputsView's onChange(holdLatch))
        }
    }

    // delta §5 / a6: undo/redo restore the WHOLE document, so refresh every document-derived @State.
    // SELECTION undo takes precedence while it has history (the recent select/deselect actions); once exhausted,
    // undo falls through to the transactional document undo.
    // BUILD is the sole surface (Paul 2026-08-27): its authoring lives in @State, so route UNDO/REDO to the BUILD stack
    // (whose snapshot also carries the document, so document-machine/receiver/rack edits ride along). Fall back to the AU
    // document undo only if the BUILD stack is empty (defensive — nothing else drives the header now).
    func undo() { if buildCanUndo { buildDoUndo() } else if au?.uiUndo() == true { refreshFromDocument() } }
    func redo() { if buildCanRedo { buildDoRedo() } else if au?.uiRedo() == true { refreshFromDocument() } }
    func refreshFromDocument() {
        guard let au else { return }
        scene = au.uiScene()
        docMachines = au.uiMachines()
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

    // PERFORM press-hold → ON HOLD (§9 item 1): while a cell is held (playing), its ON HOLD treatment overlays.
    // Kernel-only (no @State / re-render). (Stopped-audition retired with the editing UI — it returns via PLACE.)

    // (brushIndex + setBrushMorph/setBrushType + the A/B processor CLIPBOARD removed with the retired shared-Machine desk.)
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
    // receiver strip: ±octave nudge (±1 per tap, clamp ±3). Ephemeral, composes with the machine transpose.
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
                // EUCLID DRAG HUD (Paul 2026-10-02, 2nd relocation: "the euclid overlay still does not move over
                // the grid. It only seems to be able to live within the confines of the processor edit"). The
                // card hosting the processor editor (`roomsProcessorCardAt`, BuildPage.swift) applies its own
                // `.clipShape(RoundedRectangle(cornerRadius: 8))` to its ENTIRE contents — an ancestor clip that
                // trapped the HUD no matter which container inside the card it was attached to (the 1st
                // relocation only escaped the card's OWN inner ScrollView, a narrower problem than this one).
                // Rendered HERE instead — a sibling of `mainContent(geo)` at the true top of the page, the SAME
                // tier as the manual/settings/presets overlays below — so it can float anywhere on screen,
                // including over the grid. Reuses the OUTER `geo` already in scope (no nested GeometryReader
                // needed) with the identical `.global`-conversion math the card-level version used, since
                // `info.point` is still reported in WINDOW coordinates (`ProcessorBox`'s UIKit gesture) and this
                // root's own origin relative to `.global` isn't assumed to be exactly (0,0) (safe-area insets,
                // etc.) — converting explicitly is the same safe assumption the original version already made.
                if let info = euclidDragHUDInfo {
                    let origin = geo.frame(in: .global).origin
                    let hudW: CGFloat = 230
                    let aboveTouch: CGFloat = 130   // "~1 inch above the touch" — see buildEuclidDragHUD's own history for the honest approximation caveat
                    let rawX = info.point.x - origin.x
                    let halfW = hudW / 2 + 8
                    let x = min(max(rawX, halfW), max(halfW, geo.size.width - halfW))
                    let y = max(40, info.point.y - origin.y - aboveTouch)
                    buildEuclidDragHUD(info).frame(width: hudW).position(x: x, y: y)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(2)
                }
                // SECOND-FINGER STEPS CATCHER — REMOVED ENTIRE (Paul 2026-10-04: "touches elsewhere on the
                // screen shouldn't work after the first lane touch, unless it's on another Euclid lane... the
                // idea is that we allow a user to control hits and offset for two or more lanes simultaneously").
                // The window-wide catcher claimed EVERY second touch once armed, REGARDLESS of where it landed —
                // including directly over a DIFFERENT lane's own comet-bar pad, stealing that touch away from
                // that pad's own, otherwise perfectly capable `UIPanGestureRecognizer` before it ever arrived.
                // That was the ONE thing standing between "two lanes independently touched" and working — UIKit
                // already supports multiple sibling views each tracking their own independent touch natively,
                // no extra plumbing needed, once nothing is stealing the second touch first. See
                // `euclidLaneBox`'s own `.scaleEffect` (GridUI.swift) for the new "which lane is in use" cue
                // this replaces the old second-finger-anywhere mechanism with.
                // (§6c popup dropped — processor SETTINGS are inline in the §6d layout; the floating window
                //  survives only as the future EXTERNAL AUv3-view host, added when EXTERNAL Machines arrive.)
                if showManual {                         // the in-app MANUAL, scrolled to the last-touched control
                    ManualView(blocks: Self.manualBlocks, initialAnchor: helpTracker.lastAnchor,
                               onClose: { showManual = false })
                }
                if showSettings {                       // §5 the cog page (overlay on the running instrument)
                    CogPage(au: au, d: d, aboutLine: aboutLine,
                            showScenes: $showScenes,
                            roomsLeftOriented: $roomsLeftOriented,
                            onClose: { showSettings = false })
                }
                if showPresets {                        // §3 the preset browser (overlay; the engine keeps running)
                    PresetBrowser(presets: presetList, factory: au?.factoryPresetNames() ?? [], current: currentPreset,
                                  onSave: savePreset, onLoad: loadPreset, onLoadFactory: loadFactoryPreset,
                                  onDelete: deletePreset, onClose: { showPresets = false })
                }
                if showCellLibrary {                    // the cell library browser — BUILD-only now (routes to the selected machine's chain)
                    CellBrowser(cells: cellLibraryList, factory: au?.factoryLibrarySummaries() ?? [],
                                canSave: buildSelID != nil,
                                onSave: { name in buildSaveMachineToLibrary(name) },
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
        }
        // (The quantized CHAIN⟷PART voice switch moved from .onChange(of: d.absoluteStep) into the poll — Paul 2026-09-10 —
        //  so the step no longer needs to be folded into `d` at step rate. See the poll's step-boundary block.)
        .onChange(of: d.playing) { playing in                 // transport stopped mid-arm → apply the pending voice switch now (no boundary will come)
            if !playing { buildCommitPendingVoice() }
        }
        // PROCESSOR SWAP DIRECTION (Paul 2026-09-29): buildEditSlot IS the chain's own left-to-right order (0…7), so
        // its own movement is the direction the processor editor's slide+fade should travel — no separate positional
        // concept needed. Closing the editor (nil) doesn't shift the remembered position (only a genuine slot→slot
        // move should set a direction for the NEXT open).
        .onChange(of: buildEditSlot) { new in
            if let n = new { buildEditSlotDir = n >= buildEditSlotLast ? 1 : -1; buildEditSlotLast = n }
        }
        .onReceive(meterTimer) { _ in
            guard uiAppeared, let au else { return }   // ~30fps peak metering → the velocity indicators track live (not the 4Hz poll)
            let act = au.pollEmitterActivity()
            for i in 0..<4 where i < act.events.count && act.events[i] > 0 { meters.emitter(i, peak: Double(act.peak[i]) / 127.0) }   // → the @State-held class; DOES NOT re-run the body
            let rin = au.pollReceiverActivity()
            for i in 0..<4 where i < rin.events.count && rin.events[i] > 0 { meters.receiver(i, peak: Double(rin.peak[i]) / 127.0) }
            // §1 TRUTH STRIPS — OUT piano (Paul 2026-09-29): moved off the 4 Hz diagnostic poll onto this ~30fps
            // timer, same reason as the peak meters above — the held-note snapshot was visibly laggy at 4 Hz. Also
            // now the ONE source for "is MIDI reaching this instance" (buildOutProcessing) — buildTruthStrips used to
            // recompute that itself in a paused-gated TimelineView (paused whenever the transport wasn't driving a
            // part), which could only refresh on its OWN schedule; a stop/restart cycle left it a plausible spot to
            // wedge (this fixes Paul's "piano stops updating after stop/restart" report by removing that dependency
            // — plain @State writes always force a re-render, a TimelineView's own paused schedule doesn't). Kept
            // OFF the render thread (a plain voices[] scan / array read, like cellSoundingVelSnapshot).
            let editorOpen = buildEditSlot != nil
            if editorOpen {
                let now = Date()
                let proc = buildProcessing(at: now)
                if proc != buildOutProcessing { buildOutProcessing = proc }
                let idx = buildOutputCellIndex(at: now)
                let held = idx >= 0 ? au.pollCellSoundingNotes(idx).map { Int($0) } : []
                if held != buildOutHeld { buildOutHeld = held }
                let drunk = idx >= 0 ? au.pollRiffDrunkPos(idx) : -1
                if drunk != buildRiffDrunkPos { buildRiffDrunkPos = drunk }
                let ready: UInt8 = idx >= 0 ? au.pollEuclidLineReady(idx) : 0
                if ready != buildEuclidLineReady { buildEuclidLineReady = ready }
            } else {
                if buildOutProcessing { buildOutProcessing = false }
                if !buildOutHeld.isEmpty { buildOutHeld = [] }
                if buildRiffDrunkPos != -1 { buildRiffDrunkPos = -1 }
                if buildEuclidLineReady != 0 { buildEuclidLineReady = 0 }
            }
            // PART ROW ROLL (Paul 2026-09-29): the part grid's live per-row piano-roll — same ~30fps timer as the
            // OUT piano above, same reason (a poll-driven held-note feed is visibly laggy at 4Hz). Deliberately does
            // NOT clear on a transport stop — the overlay itself is already gate-hidden while stopped (roomsPart-
            // NoteRoll shares roomsPartPlayhead's own gate), so a data-level clear here would only ever throw away
            // in-flight fade state on a brief stop/resume for no visual benefit — the plan explicitly rejected that.
            if activeTab == .build, roomsRoom == .part, let ferry = buildActiveFerry {
                let base = Snap.ferryRowBase(ferry)
                let liveAll = au.pollRowSoundingVoices()
                let nowRaw = meters.beatAnchor + Date().timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                for r in 0..<Snap.rowsPerFerry {
                    let live = base + r < liveAll.count ? liveAll[base + r] : []
                    var existing = meters.partRollNotes[r]
                    for i in existing.indices where existing[i].heldToBeat == nil
                        && !live.contains(where: { $0.note == existing[i].pitch && $0.onBeat == existing[i].onBeat }) {
                        existing[i].heldToBeat = nowRaw                       // just released — freeze the head here
                    }
                    for lv in live where !existing.contains(where: { $0.pitch == lv.note && $0.onBeat == lv.onBeat })
                        && abs(lv.onBeat - nowRaw) < 64 {                     // sanity clamp — reject an implausible onBeat outright
                        existing.append(PartRowRollNote(pitch: lv.note, vel: lv.vel, onBeat: lv.onBeat, heldToBeat: nil))
                    }
                    existing.removeAll { ($0.heldToBeat ?? nowRaw) < nowRaw - partRollFadeBeats - 0.05 }   // fully receded
                    if existing != meters.partRollNotes[r] { meters.partRollNotes[r] = existing }
                }
            } else if meters.partRollNotes.contains(where: { !$0.isEmpty }) {
                meters.partRollNotes = Array(repeating: [], count: Snap.rowsPerFerry)
            }
            // SELECT ROLL (Paul 2026-09-29): the SELECT grid's live scrolling piano-roll on the currently-auditioning
            // cell — same technique as the PART ROW ROLL above, scoped to the one engine row the chain audition is
            // parked on (buildChainAuditionRow) instead of a whole ferry's 4 rows. Gated on ddSolo (the precise "is a
            // SELECT cell genuinely the live voice" check), not the selGrey UI proxy — a selected-but-stopped cell
            // correctly reports no live notes and falls back to its static preview at the draw site.
            if roomsRoom == .select, buildGridSelSel != nil, ddSolo, let row = buildChainAuditionRow, row >= 0 {
                let liveAll = au.pollRowSoundingVoices()
                let nowRaw = meters.beatAnchor + Date().timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                let live = row < liveAll.count ? liveAll[row] : []
                var existing = meters.selectRollNotes
                for i in existing.indices where existing[i].heldToBeat == nil
                    && !live.contains(where: { $0.note == existing[i].pitch && $0.onBeat == existing[i].onBeat }) {
                    existing[i].heldToBeat = nowRaw
                }
                for lv in live where !existing.contains(where: { $0.pitch == lv.note && $0.onBeat == lv.onBeat })
                    && abs(lv.onBeat - nowRaw) < 64 {
                    existing.append(PartRowRollNote(pitch: lv.note, vel: lv.vel, onBeat: lv.onBeat, heldToBeat: nil))
                }
                existing.removeAll { ($0.heldToBeat ?? nowRaw) < nowRaw - selectRollWindowBeats - 0.05 }
                if existing != meters.selectRollNotes { meters.selectRollNotes = existing }
            } else if !meters.selectRollNotes.isEmpty {
                meters.selectRollNotes = []
            }
        }
        .onReceive(timer) { _ in
            guard uiAppeared, let au else { return }   // CR-17: don't drain the render→main feeds while the view is hidden/backgrounded (perf + narrows CR-1's race window). buildPersistTick resumes on re-appear — a load restores then.
            buildPersistTick()   // BUILD: keep the saved unassigned part current + restore a just-loaded one (no-op off BUILD)
            // PART ROLL: while the PART audition is on screen + playing, capture the true live output for the piano roll.
            au.setPartRoll(active: false, cycleBeats: 1)   // the LIVE capture is retired — the part roll is now the OFFLINE feed (recomputed below, after recvHeldNotes updates)
            #if DEBUG
            if chaosOn { let s = "\(chaos.oracleFlag) · \(chaos.eventCount)e"; if s != chaosStatus { chaosStatus = s } }   // CHAOS oracle readout
            if autoOn { let s = "\(autoPilot.status) · \(autoPilot.chordCount)c"; if s != autoStatus { autoStatus = s } }   // AUTO-RUN readout
            #endif
            // Write @State ONLY when a DISPLAYED value changed — an unconditional write re-renders the
            // whole grid every 0.25s (which used to tear down in-progress press-holds). When STOPPED
            // nothing here changes, so the grid is quiescent; while PLAYING only the playhead fields move.
            let nd = au.kernelDiagnostics()
            if nd.panics != lastStuckPanics {   // a8 STUCK-NOTE: the render thread healed since the last poll — log it ONCE here, off the audio thread (was an os_log PER BLOCK on the render path = crackle; Paul 2026-09-12)
                lastStuckPanics = nd.panics
                let why = nd.stuckReason == 1 ? "silence invariant violated (stopped)"
                        : nd.stuckReason == 2 ? "playing silence leak (no source)" : "stuck note"
                os_log(.fault, log: DiagView.hangLog, "MidiSpark STUCK-NOTE: %{public}s — voices=%d echoes=%d panics=%llu",
                       why, nd.stuckVoices, nd.stuckEchoes, nd.panics)
            }
            // BUG FIX (Paul 2026-09-29, "playhead jitters when stopped"): was `playing: nd.playing` (HOST-only) — during
            // PLUGIN free-run (a ferry/part driving its own clock while the host transport is genuinely stopped), the
            // host is never "playing" by definition, so `!playing` was permanently true → syncBeat's own dejitter guard
            // ("only hard re-anchor on a genuine discontinuity, else free-run") never took the free-run branch at all,
            // hard-re-anchoring on EVERY 4Hz poll instead — exactly the ~4Hz sawtooth this mechanism exists to kill,
            // just scoped to free-run playback specifically (steady host-driven playback was never affected, which is
            // why this went unnoticed until a low-motion-tolerant view — the new PART ROW ROLL — made it obvious).
            // `nd.beat` is ALREADY the effective (host-or-free-run) beat (Kernel.swift: "EFFECTIVE beat... UI beat-driven
            // playheads work while the host is stopped") — only this BOOLEAN was mismatched to the wrong field.
            meters.syncBeat(nd.beat, tempo: nd.tempo, playing: nd.effectivePlaying, at: Date())   // BEAT clock (4 Hz) → the telemetry; playheads extrapolate at 30 fps. DEJITTER: re-anchors only on a discontinuity, else free-runs (see syncBeat) → no 4 Hz stutter
            buildTickFerryOneShot(nd.beat)                                // PLAY-FERRY LAUNCH (Phase 2b): stop a ONE-SHOT ferry one part-length after its launch (≤ one poll of the pass end)
            if d.playing && !nd.playing {                                 // §5c/§9: transport stop = the drop
                if holdLatch { setHold(false) }
                // LOOP PERSISTS across a transport stop (user 2026-08-06): keep the selected columns (their LOOP
                // glyph stays) so a restart resumes looping — the transport edge already flushed the voices, so
                // nothing is stuck; the lap just isn't driven while stopped.
                clearOnTap()                                              // ON TAP: momentary flips/mute/solo clear on stop
                clearReceiverPerform()                                    // receiver strip: SOLO (+ OCT/vel/latch) = weather
                clearEmitterPerform()                                     // emitter strip: output OCT = weather
                if meters.cellRoll.contains(where: { !$0.isEmpty }) { meters.cellRoll = Array(repeating: [], count: Snap.cells) }   // BUILD piano-roll: clear on stop so idle faces pause
            }
            let lm = au.uiLadderMode(); if lm != ladderMode { ladderMode = lm }   // LADDER: sync the mode (preset load / external change)
            // `d` drives the BODY (effColumn highlight, pass, etc.). DON'T update it on `beat` alone — that fired every
            // tick while playing (→ a full BuildPage recompute at 4 Hz just to move a beat the playheads extrapolate).
            // The beat now lives in `meters`. FURTHER (Paul 2026-09-11): the STEP index (effColumn/absoluteStep) is NO LONGER
            // folded into `d` at all — every per-step playhead (the processor-editor matrices/lanes + the stage-eye)
            // now SELF-CLOCKS from the free-running beat anchor, so re-rendering the whole page each step is pure waste that
            // dropped a frame per step and hitched every playhead. `d` now updates only on the SLOW fields (playing/tempo/pass);
            // the beat-derived playheads stay smooth. The quantized voice switch rides the poll's own step detector (below).
            // BUG FIX (Paul 2026-09-29, part of the "playhead jitters when stopped" fix): `effectivePlaying` was missing
            // from this trigger — during free-run (host `playing` stays false throughout, by definition), `d.effectivePlaying`
            // could go stale indefinitely (never copied from `nd` unless tempo/pass ALSO happened to change at the same
            // moment), so roomsPartPlayhead/roomsPartNoteRoll's own `d.effectivePlaying` gate could desync from the TRUE
            // free-run state — visible as the sweep/roll failing to appear or disappear exactly when free-run actually
            // started/stopped.
            if nd.playing != d.playing || nd.effectivePlaying != d.effectivePlaying || nd.tempo != d.tempo || nd.pass != d.pass { d = nd }
            // QUANTIZED CHAIN⟷PART VOICE SWITCH (was .onChange(of: d.absoluteStep), Paul 2026-08-14): commit an armed switch on
            // the step boundary. Detect the boundary against the reference-held last-step so a plain step change re-runs nothing;
            // buildCommitPendingVoice (which does mutate @State) only runs when a switch/reengage is actually armed (rare).
            if nd.playing, nd.absoluteStep != meters.lastStep {
                meters.lastStep = nd.absoluteStep
                if buildPendingWorkshopVoice != nil || buildPendingReengage { buildCommitPendingVoice() }
            }
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
            // PART ROLL — the OFFLINE feed (Paul 2026-09-03): recompute the part's EXACT output deterministically (no lag)
            // when on the part page and the input / selection / part-edit generation changed. Runs after recvHeldNotes so it
            // reads the fresh input; the offline render reads the live pool + current box, so the notes are always current.
            if activeTab == .build && roomsRoom == .part {
                let cyc = Double(max(1, buildPartCols)) * (buildPartRate?.beats ?? stepBeats)
                let sig = "\(recvHeldNotes)|\(buildStagingSel)|\(buildStagingMulti)|\(cyc)|\(buildPartRollGen)"
                // OFF-MAIN (Paul 2026-09-11, perf): offlinePartRoll runs a fresh Router ~188× (a full part render). Doing that
                // synchronously on the main thread stalled the UI on every held-chord/selection/edit change. Run it on a
                // large-stack thread (deep enough for Router.process); marshal the result back. One at a time (partRollComputing);
                // the 4 Hz poll re-kicks within a tick if the key changed while computing. It only feeds a visual roll — no audio.
                if sig != partRollSig && !partRollComputing {
                    partRollSig = sig; partRollComputing = true
                    let auRef = au
                    runOnLargeStack {
                        let pr = auRef.offlinePartRoll(cyc: cyc)
                        DispatchQueue.main.async { self.partRollComputing = false; if pr != self.partRollNotes { self.partRollNotes = pr } }
                    }
                }
            } else if !partRollNotes.isEmpty { partRollNotes = []; partRollSig = "" }
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
            let nc = au.uiMachines();       if nc != docMachines { docMachines = nc }
            let nr = au.uiReceivers();     if nr != receivers { receivers = nr }
            let ns = au.uiScene();         if ns != scene { scene = ns }
            let si = au.uiStepRateIndex(); if si != stepIndex { stepIndex = si }
            let sw = au.uiSwing();         if sw != swing { swing = sw }
            let cn = au.pollCellNotes()                    // NOTE-SWEEP: per-cell recent emitted notes (pitch/vel/count) — drained every tick
            if cn.count.contains(where: { $0 > 0 }) { meters.cellNotePitch = cn.pitch; meters.cellNoteVel = cn.vel; meters.cellNoteCount = cn.count }
            // FOCUS note-event feed (Paul 2026-08-31): the machine's cell → its REAL emitted notes + beats, for the chain-flow
            // comets. The focus cell = a selected ferry's play cell (col 0, its own dedicated row), else the chain audition's engine row.
            let focusIdx: Int = buildSelectedPlayCol.map { Snap.ferryRowBase($0) } ?? (buildDisplayVoice == .chain ? (buildChainAuditionRow ?? -1) : -1)
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
            if editorOpen && buildProcessingNow {               // ACCUMULATE only while MIDI reaches THIS processor instance
                var out = buildOutRoll                          // (Paul 2026-09-12) — so a DIFFERENT row's output never enters this roll
                for i in 0..<Snap.cells {
                    let k = min(Int(cn.count[i]), 6)
                    for j in 0..<k where i * 6 + j < cn.pitch.count {
                        out.append(OutMark(note: cn.pitch[i * 6 + j], vel: Double(cn.vel[i * 6 + j]) / 127.0, born: mnow))
                    }
                }
                out = out.filter { mnow.timeIntervalSince($0.born) < 2.5 }
                if out.count > 96 { out = Array(out.suffix(96)) }
                if out != buildOutRoll { buildOutRoll = out }   // guard idle re-renders
            } else if editorOpen {                              // editor open but NOT processing: stop accumulating, let the
                let out = buildOutRoll.filter { mnow.timeIntervalSince($0.born) < 2.5 }   // last notes drift out + gray (never a different row's live output)
                if out != buildOutRoll { buildOutRoll = out }
            } else if !buildOutRoll.isEmpty { buildOutRoll = [] }
            // §1 TRUTH STRIPS — OUT piano: MOVED to the ~30fps meterTimer above (Paul 2026-09-29, latency + the
            // stop/restart freeze) — was polled here at 4 Hz.
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
            // STRIKE / ROLL / SOUNDING feed → written to `meters` (a reference class) so these per-note writes DON'T re-run the
            // BuildPage body; the emitter fader + buildNoteSweep read them live in their TimelineViews. (Paul 2026-09-10.)
            let strikes = au.pollCellStrikes()             // SEAL comet: stamp a hit time + velocity per struck cell
            if strikes.contains(where: { $0 > 0 }) {
                let now = Date()
                for i in 0..<min(Snap.cells, strikes.count) where strikes[i] > 0 { meters.cellHitAt[i] = now; meters.cellHitVel[i] = Double(strikes[i]) / 127.0; meters.cellStrikeSeq[i] &+= 1 }
                if activeTab == .build {                            // BUILD grid PIANO-ROLL: fold new strikes into per-cell scrolling notes (at real pitch)
                    for i in 0..<Snap.cells {
                        meters.cellRoll[i].removeAll { now.timeIntervalSince($0.born) > 1.6 }   // drop notes that have crossed
                        guard meters.cellStrikeSeq[i] > meters.rollPrevSeq[i] else { continue }
                        let cnt = Int(meters.cellNoteCount[i])
                        if cnt > 0 {                                // REAL pitch: one mark per emitted note
                            for k in 0..<min(cnt, 6) where i * 6 + k < meters.cellNotePitch.count {
                                meters.cellRoll[i].append(BuildRollNote(born: now, vel: Double(meters.cellNoteVel[i * 6 + k]) / 127.0, lane: rollLaneForPitch(Int(meters.cellNotePitch[i * 6 + k]))))
                            }
                        } else {
                            meters.cellRoll[i].append(BuildRollNote(born: now, vel: meters.cellHitVel[i], lane: 0.35 + 0.3 * Double((i &* 40503) % 100) / 100.0))
                        }
                        if meters.cellRoll[i].count > 16 { meters.cellRoll[i].removeFirst(meters.cellRoll[i].count - 16) }
                    }
                    meters.rollPrevSeq = meters.cellStrikeSeq
                }
            }
            if activeTab == .build && nd.playing {         // BUILD piano-roll: prune crossed notes each tick so idle faces pause (matches GridUI's beat prune)
                let now = Date()
                for i in 0..<meters.cellRoll.count { meters.cellRoll[i].removeAll { now.timeIntervalSince($0.born) > 1.6 } }
            }
            let svRaw = au.pollCellSoundingVel()           // per-cell SOUNDING velocity (256-wide) → the emitter fader's per-machine floor
            meters.cellSoundVel = svRaw.map { Double($0) / 127.0 }
            let nowG = Date()
            // PER-CELL SOUNDING GATE (Paul 2026-09-08): derive from the 256-wide velocity feed (sv > 0), NOT the old 128-bit
            // lo/hi mask — that mask only covered indices 0…127 (columns 0–7), so a 16-wide part's second half (cols 8–15,
            // index ≥128) always read "not sounding" and the emitter strip's HELD branch never fired there.
            for i in 0..<Snap.cells {
                let on = meters.cellSoundVel[i] > 0
                if on != meters.cellSounding[i] {
                    if !on { meters.cellReleasedAt[i] = nowG }   // falling edge → stamp the release (the spark fades from here)
                    meters.cellSounding[i] = on
                }
            }
            // PLAY-STATE GREY (Paul 2026-09-14): grey the processor editor unless MIDI is reaching THIS processor instance
            // right now. Deduped @State (only re-renders the editor when the grey state flips). BUILD-tab only.
            // UNIFIED with the IN piano + OUT roll gate (Paul 2026-09-16 fix, round 3): use the SAME buildProcessingNow the
            // OUT roll uses (line ~1049) instead of a parallel buildSelectedMachineProcessing() — that divergent copy read
            // bright throughout for a 16-step part with row A in cols 1–8 / row B in 9–16 (it stayed on row A's columns).
            // buildProcessing is positional per the FOCUSED rung vs the part's own playhead column: bright only while the
            // focused rung is the active rung under the current column → dims cleanly when the playhead reaches row B's half.
            if activeTab == .build {
                let proc = buildProcessingNow
                if proc != buildSelectedProcessing { buildSelectedProcessing = proc }
            }
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
    // The active surface's body. Only BUILD remains (the tab era was retired 2026-08-21); config (RACK, RECORD, the
    // MIDI IN/OUT sheets) opens as overlays over BUILD, not as separate tabs.
    // THE MAIN CONTENT COLUMN — header then the BUILD body. WHOLE-UI SCROLL (user 2026-08-05):
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

    // (processorPanels — the retired shared-Machine A/B desk — removed with the morph layer; all processor
    //  editing is the per-cell CHAIN editor in EDIT now. ProcessorBox survives, used only in `slotMode`.)

    // Palette tap selects the desk brush (delta item 8 retired the ALT-targeting pairing gesture — a second
    // processor is now made on the B panel, not by pairing to another Machine).

        // §2 THE ARRANGEMENT BAR (extracted → ArrangementBar.swift). The VC keeps the poll + the grid's scene/
    // machines: it feeds the bar the polled sceneEmpty/activeSceneIdx and refreshes on `onSceneOpDone`.
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
                       headerExtras: AnyView(buildHeaderControls()),           // BUILD: RECORD · RATE · MIDI/RACK CONFIG in the header (Paul 2026-08-23)
                       playStrip: AnyView(buildPlayStrip()))                    // THE PLAY STRIP — transport + sweeping playhead (Paul 2026-09-09)
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
        scene = au.uiScene(); docMachines = au.uiMachines()   // the grid follows the switched scene
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

    // HOLD BISECT — in the DEV overlay where device passes actually look (2026-09-07; the cog-HEALTH copy was the wrong
    // screen). PLAY = engine clock advancing · SND = notes on the wire · per armed door: mode (K = KEYS/note-toggle branch,
    // C = CHORD/mirror-and-freeze), L = live admitted, S = struck this block, F = frozen held. "HOLD ARM 0" (red) = the
    // engine sees NO door latch-armed → capture can't run → the frozen pool stays empty → silent.
    var holdBisectMonitor: some View {
        func n(_ a: [Int], _ i: Int) -> Int { i < a.count ? a[i] : 0 }
        return HStack(spacing: 10) {
            Text("PLAY \(d.effectivePlaying ? 1 : 0)").font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(d.effectivePlaying ? .white.opacity(0.55) : .black)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(d.effectivePlaying ? Color.clear : UI.red))
            Text("SND \(d.distinctSounding)").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
            if d.holdArmed == 0 {
                Text("HOLD ARM 0").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(UI.red))
            } else {
                ForEach(0..<4, id: \.self) { i in
                    if d.holdArmed & (1 << UInt8(i)) != 0 {
                        let mode = d.holdKeysMask & (1 << UInt8(i)) != 0 ? "K" : "C"
                        Text("\(["A","B","C","D"][i])·\(mode) L\(n(d.holdLiveN, i)) S\(n(d.holdStruckN, i)) F\(n(d.holdFrozenN, i))")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            Spacer()
        }
    }

    // The BINARY's build datetime — the extension executable's link/modification time. A quick "am I actually on the
    // fresh build?" tell in the hidden loader (the AUv3 host can cache the old plugin). Computed once from the extension
    // bundle (Bundle(for:) on the AU class → the extension binary, not the host app).
    static let buildStamp: String = {
        guard let exe = Bundle(for: MidiSparkAudioUnit.self).executableURL,
              let date = (try? FileManager.default.attributesOfItem(atPath: exe.path))?[.modificationDate] as? Date
        else { return "—" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: date)
    }()
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
                Text("BUILD \(Self.buildStamp)").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.5))   // the running binary's build time
                buildSelfTestView
                stuckNoteMonitor
                holdBisectMonitor
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

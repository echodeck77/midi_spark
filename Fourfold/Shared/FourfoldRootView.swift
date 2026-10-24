//  FourfoldRootView.swift
//  FOURFOLD Step 2 (2026-10-23, Docs/standalone-plan.md): the Fourfold root view — the Fourfold half of the 8x8 host (`DiagView`, AudioUnitViewController.swift) ported into its own view, so the Fourfold targets need no 8x8 workbench.
//
//  What it is: the owner of the live mirrors of the document's Fourfold fields (`euclideous*`), the 50-deep Fourfold undo, the lane-lock bookkeeping, the 4 Hz resync / 30 Hz poll, presets, and the ~60 closures the
//  page calls; every edit ends in `au.editDocument` + `publish()`. The undo / lock / page-call / poll code below is COPIED from DiagView verbatim (only `buildPublishScene()` → `publish()` and the 8x8-only lines dropped),
//  so Fourfold behaves exactly as the page does inside 8x8 State today. Copy-and-prune, not shared, by decision (plan: "Host glue"); 8x8 State keeps its own copy until Paul says otherwise.
//
//  `publish()` replaces `buildPublishScene()`: `FourfoldCompose` (pure; `FourfoldComposeTests` prove it equals the 8x8 composer) builds the one-slot chain and the one-cell scene, which go to the AU as a staging scene.

import SwiftUI
import UIKit
import os

struct FourfoldRootView: View {
    weak var au: FourfoldAudioUnit?
    /// true in the standalone app: the app's own transport is the clock, so Fourfold must NOT free-run on its own while it is stopped (and the "when the host stops" setting is hidden). The AUv3 extension (a host drives it) leaves this false.
    let internalTransport: Bool
    init(au: FourfoldAudioUnit?, internalTransport: Bool = false) { self.au = au; self.internalTransport = internalTransport }

    // ── host / display state ──
    static let hangLog = OSLog(subsystem: "com.outliermidi.Fourfold", category: "hang")
    @AppStorage("fourfold.pulseLevel") var pulseLevel = 2   // a device preference, not the document (PULSE ferry §7.1)
    /// The host stopped after playing: free-run off until the host starts again (8x8's `buildHostHalted`, kept so Fourfold behaves as it does in 8x8 State).

    // ── the document's Fourfold fields (live mirrors; loaded in refreshFromDocument, written back via au.editDocument) ──

    // The mutable state lives in ONE reference-type model (below), reached through the forwarding properties here: the page call hands ~60 closures a copy of `self`, and with ~55 @State members that was a 214 KB Debug stack
    // frame (Scripts/debug-frame-sizes.py) on a 1 MB main-thread stack. `self` is now a handful of words. Behaviour is the same: any change to a member re-evaluates the body, as with @State.
    @StateObject var m = FourfoldModel()
    var d: KernelDiag { get { m.d } nonmutating set { m.d = newValue } }
    var lastStuckPanics: UInt64 { get { m.lastStuckPanics } nonmutating set { m.lastStuckPanics = newValue } }
    var uiAppeared: Bool { get { m.uiAppeared } nonmutating set { m.uiAppeared = newValue } }
    var appActive: Bool { get { m.appActive } nonmutating set { m.appActive = newValue } }
    var meters: FourfoldTelemetry { m.meters }
    var swing: Int { get { m.swing } nonmutating set { m.swing = newValue } }
    var stepIndex: Int { get { m.stepIndex } nonmutating set { m.stepIndex = newValue } }
    var busChannels: [Int] { get { m.busChannels } nonmutating set { m.busChannels = newValue } }
    var ignoreAllNotesOff: Bool { get { m.ignoreAllNotesOff } nonmutating set { m.ignoreAllNotesOff = newValue } }
    var showPresets: Bool { get { m.showPresets } nonmutating set { m.showPresets = newValue } }
    var presetList: [String] { get { m.presetList } nonmutating set { m.presetList = newValue } }
    var currentPreset: String { get { m.currentPreset } nonmutating set { m.currentPreset = newValue } }
    var reelShowPopup: Bool { get { m.reelShowPopup } nonmutating set { m.reelShowPopup = newValue } }
    var reelState: Int { get { m.reelState } nonmutating set { m.reelState = newValue } }
    var hostHalted: Bool { get { m.hostHalted } nonmutating set { m.hostHalted = newValue } }
    var registeredChain: [ProcessorSlot] { get { m.registeredChain } nonmutating set { m.registeredChain = newValue } }
    var euclideousLines: [EuclidLine] { get { m.euclideousLines } nonmutating set { m.euclideousLines = newValue } }
    var euclideousUndo: UndoStack<EuclideousUndoSnapshot> { get { m.euclideousUndo } nonmutating set { m.euclideousUndo = newValue } }
    var euclideousRiff: EuclideousRiff { get { m.euclideousRiff } nonmutating set { m.euclideousRiff = newValue } }
    var euclideousRiffs: [EuclideousRiff] { get { m.euclideousRiffs } nonmutating set { m.euclideousRiffs = newValue } }
    var euclideousActiveRiff: Int { get { m.euclideousActiveRiff } nonmutating set { m.euclideousActiveRiff = newValue } }
    var euclideousLanesSeq: EuclideousLanesSeq { get { m.euclideousLanesSeq } nonmutating set { m.euclideousLanesSeq = newValue } }
    var euclideousFX: EuclideousFX { get { m.euclideousFX } nonmutating set { m.euclideousFX = newValue } }
    var euclideousRiffsSeq: EuclideousRiffsSeq { get { m.euclideousRiffsSeq } nonmutating set { m.euclideousRiffsSeq = newValue } }
    var euclideousRiffPositions: [Int] { get { m.euclideousRiffPositions } nonmutating set { m.euclideousRiffPositions = newValue } }
    var euclideousMaskPositions: [Int] { get { m.euclideousMaskPositions } nonmutating set { m.euclideousMaskPositions = newValue } }
    var euclideousRiffLivePool: [UInt8] { get { m.euclideousRiffLivePool } nonmutating set { m.euclideousRiffLivePool = newValue } }
    var euclideousLanesSeqStep: Int { get { m.euclideousLanesSeqStep } nonmutating set { m.euclideousLanesSeqStep = newValue } }
    var euclideousRiffsSeqStep: Int { get { m.euclideousRiffsSeqStep } nonmutating set { m.euclideousRiffsSeqStep = newValue } }
    var euclideousWipeEvent: [Router.EuclideousNoteViewEventSnapshot?] { get { m.euclideousWipeEvent } nonmutating set { m.euclideousWipeEvent = newValue } }
    var euclideousStrikeEvent: [Router.EuclideousNoteViewEventSnapshot?] { get { m.euclideousStrikeEvent } nonmutating set { m.euclideousStrikeEvent = newValue } }
    var euclideousRiffWalkState: [Int64] { get { m.euclideousRiffWalkState } nonmutating set { m.euclideousRiffWalkState = newValue } }
    var euclideousResetSpanBars: Int { get { m.euclideousResetSpanBars } nonmutating set { m.euclideousResetSpanBars = newValue } }
    var euclideousKeyRoot: Int { get { m.euclideousKeyRoot } nonmutating set { m.euclideousKeyRoot = newValue } }
    var euclideousKeyType: ScaleType { get { m.euclideousKeyType } nonmutating set { m.euclideousKeyType = newValue } }
    var euclideousNoteSource: EuclideousLaneSource { get { m.euclideousNoteSource } nonmutating set { m.euclideousNoteSource = newValue } }
    var euclideousHoldLatchMode: EuclideousHoldLatchMode? { get { m.euclideousHoldLatchMode } nonmutating set { m.euclideousHoldLatchMode = newValue } }
    var euclideousMainOutMask: UInt8 { get { m.euclideousMainOutMask } nonmutating set { m.euclideousMainOutMask = newValue } }
    var euclideousSoloMask: UInt8 { get { m.euclideousSoloMask } nonmutating set { m.euclideousSoloMask = newValue } }
    var euclideousSoloHeld: UInt8 { get { m.euclideousSoloHeld } nonmutating set { m.euclideousSoloHeld = newValue } }
    var euclideousLocks: [EuclideousLaneLock] { get { m.euclideousLocks } nonmutating set { m.euclideousLocks = newValue } }
    var euclideousLockRevs: UInt32 { get { m.euclideousLockRevs } nonmutating set { m.euclideousLockRevs = newValue } }
    var euclideousLockTouches: [Int] { get { m.euclideousLockTouches } nonmutating set { m.euclideousLockTouches = newValue } }
    var euclideousLockAppliedSeq: UInt32 { get { m.euclideousLockAppliedSeq } nonmutating set { m.euclideousLockAppliedSeq = newValue } }
    var euclideousLockRingStart: [Date?] { get { m.euclideousLockRingStart } nonmutating set { m.euclideousLockRingStart = newValue } }
    var euclideousPendingRolls: EuclideousPendingRollSlots { get { m.euclideousPendingRolls } nonmutating set { m.euclideousPendingRolls = newValue } }
    var euclideousHoldOverrides: EuclideousPendingRollSlots { get { m.euclideousHoldOverrides } nonmutating set { m.euclideousHoldOverrides = newValue } }
    var euclideousMidiInChannelMask: UInt16 { get { m.euclideousMidiInChannelMask } nonmutating set { m.euclideousMidiInChannelMask = newValue } }
    var euclideousHostStopBehavior: EuclideousHostStopBehavior { get { m.euclideousHostStopBehavior } nonmutating set { m.euclideousHostStopBehavior = newValue } }
    var euclideousChords: MachineParams { get { m.euclideousChords } nonmutating set { m.euclideousChords = newValue } }

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private let meterTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var stepBeats: Double { StepRate.allCases[min(stepIndex, StepRate.allCases.count - 1)].beats }

    // ── body ──
    @_optimize(speed)
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(red: 0.066, green: 0.075, blue: 0.094).ignoresSafeArea()
                pageView(geo)
                    .frame(width: geo.size.width, height: geo.size.height + geo.safeAreaInsets.bottom, alignment: .topLeading)
                    .ignoresSafeArea(.container, edges: .bottom)
                overlays(geo)
            }
        }
        .onReceive(meterTimer) { _ in fastPoll() }
        .onReceive(timer) { _ in slowPoll() }
        .onChange(of: d.playing) { playing in transportEdge(playing) }
        .onAppear {
            uiAppeared = true
            refreshFromDocument()
            refreshTiming()
            publish()   // the first sound does not wait for the 4 Hz resync to notice a difference
        }
        .onDisappear {
            uiAppeared = false
            // LANE SOLO: a page that goes away takes any finger-held solo with it — the render thread keeps only the LATCHED mask.
            euclideousSoloHeld = 0
            au?.setEuclideousSoloLive(euclideousSoloMask)
            euclideousLockTouches = [0, 0, 0, 0]   // LANE LOCK: a finger the page never saw lift must not hold a lane forever
            pushLockLive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in appActive = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in appActive = true }
    }

    /// The page. `body` frames it to the root `geo` on the view's FULL height (PAGE LAYOUT ferry 2026-10-19: the page ignores the bottom safe area and keeps a bottom margin of max(16, inset) itself); the modifiers sit OUTSIDE this function so the
    /// Debug frame holds one copy of the (large) page value, not four.
    /// An `AnyView`-returning leaf on purpose: the page call is ~240 lines of closures and the extension's main thread has a 1 MB stack (feedback_extension-main-stack-1mb).
    @_optimize(speed)
    func pageView(_ geo: GeometryProxy) -> AnyView {
        AnyView(
            EuclideousPage(lines: euclideousLines,
                                               riffs: euclideousRiffs, activeRiff: euclideousActiveRiff,
                                               riffPositions: euclideousRiffPositions, riffWalkState: euclideousRiffWalkState, maskPositions: euclideousMaskPositions, riffLivePool: euclideousRiffLivePool,
                                               lanesSeq: euclideousLanesSeq, riffsSeq: euclideousRiffsSeq, fx: euclideousFX,
                                               lanesSeqStep: euclideousLanesSeqStep, riffsSeqStep: euclideousRiffsSeqStep,
                                               wipeEvents: euclideousWipeEvent, strikeEvents: euclideousStrikeEvent,
                                               pulseFeed: meters.pulse, pulseLevel: pulseLevel,
                                               resetSpanBars: euclideousResetSpanBars, keyRoot: euclideousKeyRoot, keyType: euclideousKeyType,
                                               // SWING (2026-10-17): the SAME global setter/readback ArrangementBar's own header
                                               // slider already uses — a second UI surface onto one shared value, not new state
                                               // (`refreshTiming` re-polls `swing` right after, matching ArrangementBar's own
                                               // `onSwing` call site exactly).
                                               swing: swing, onSetSwing: { au?.setSwing($0); refreshTiming() },
                                               noteSource: euclideousNoteSource,
                                               onSetNoteSource: { v in
                                                   euclideousRecordUndo(coalesceKey: nil)
                                                   euclideousNoteSource = v
                                                   au?.editDocument { $0.euclideousNoteSource = v }
                                                   publish()
                                               },
                                               holdLatchMode: euclideousHoldLatchMode,
                                               onSetHoldLatchMode: { v in
                                                   euclideousRecordUndo(coalesceKey: nil)
                                                   euclideousHoldLatchMode = v
                                                   au?.editDocument { $0.euclideousHoldLatchMode = v }
                                                   publish()
                                               },
                                               // PER-LANE I/O (Paul 2026-10-08): riffSourceMidi/lanesSourceMidi no longer passed —
                                               // each lane now owns its own source directly on EuclidLine (sourceMode), edited via
                                               // the existing generic onEdit below; euclideousRiffSourceMidi/euclideousLanesSourceMidi
                                               // (the @State vars + their AU getter/setter plumbing) stay in place, just unreachable
                                               // from this call site — decode-safety for an old saved doc, matching how
                                               // euclideousReceiver was handled when ITS control was dropped.
                                               mainOutMask: euclideousMainOutMask,
                                               soloMask: euclideousSoloMask, soloHeld: euclideousSoloHeld,
                                               chords: euclideousChords,
                                               onEditChords: { mutate in
                                                   euclideousRecordUndo(coalesceKey: "euclideousChords")
                                                   var c = euclideousChords
                                                   mutate(&c)
                                                   euclideousChords = c
                                                   au?.editDocument(coalesceKey: "euclideousChords") { $0.euclideousChords = c }
                                                   publish()
                                               },
                                               clock: EuclidLiveClock(stepBeats: stepBeats, cols: Snap.cols, anchor: meters.beatAnchor, anchorAt: meters.beatAnchorAt, tempo: meters.tempo, playing: d.effectivePlaying, swing: Double(swing), beatsPerBar: meters.beatsPerBar),
                                               onEdit: { mutate in
                                                   applyLandedLockSnaps()   // LANE LOCK: an edit after a snap lands on L
                                                   var lines = euclideousLines
                                                   mutate(&lines)
                                                   // LANE LOCK §9.2: a change that is only lock fields of locked lanes records no undo step (so one that would record at touch-down doesn't either)
                                                   if !euclideousLockChangeIsLockOnly(old: euclideousLines, new: lines, locks: euclideousLocks) { euclideousRecordUndo(coalesceKey: "euclideous") }
                                                   setEuclideousLines(lines)
                                                   au?.editDocument(coalesceKey: "euclideous") { $0.euclideousLines = lines }
                                                   publish()
                                               },
                                               pendingRolls: euclideousPendingRolls,
                                               onSetPendingRolls: { rolls in
                                                   euclideousPendingRolls = rolls
                                                   au?.setEuclideousPendingRolls(rolls)
                                               },
                                               holdOverrides: euclideousHoldOverrides,
                                               onSetHoldOverrides: { rolls in
                                                   euclideousHoldOverrides = rolls
                                                   au?.setEuclideousHoldOverrides(rolls)
                                               },
                                               // RANDOM MODE ferry §7.2: one undo step per kept card-tab, in the order given —
                                               // `euclideousRandomUndoSequence` builds S0...S_{N-1} from the CURRENT (already
                                               // settled) snapshot; each push uses `coalesceKey: nil` so none coalesce away.
                                               onRandomFinish: { entries in
                                                   guard !entries.isEmpty else { return }
                                                   let settled = euclideousSnapshot()
                                                   for s in euclideousRandomUndoSequence(settled: settled, entries: entries) {
                                                       euclideousUndo.record(s, coalesceKey: nil)
                                                   }
                                               },
                                               locks: euclideousLocks, lockRingStart: euclideousLockRingStart, lockHeld: euclideousLockTouches.map { $0 > 0 },
                                               onLockCommand: { lane, cmd in lockCommand(lane, cmd) },
                                               onLockHeld: { lane, down in lockHeld(lane, down) },
                                               // MIX TAB (2026-10-18 §4.3): one undo step per TOUCH. `onEdit`'s fixed key merges consecutive edits across
                                               // different touches, so a pad takes an explicit `coalesceKey: nil` checkpoint at the first value-changing write
                                               // of a touch (`newStep`) and none for the rest — the write itself is the SAME document + publish path.
                                               onEditStep: { newStep, mutate in
                                                   applyLandedLockSnaps()
                                                   var lines = euclideousLines
                                                   mutate(&lines)
                                                   if newStep && !euclideousLockChangeIsLockOnly(old: euclideousLines, new: lines, locks: euclideousLocks) { euclideousRecordUndo(coalesceKey: nil) }
                                                   setEuclideousLines(lines)
                                                   au?.editDocument(coalesceKey: "euclideous") { $0.euclideousLines = lines }
                                                   publish()
                                               },
                                               onEditRiffs: { mutate in
                                                   euclideousRecordUndo(coalesceKey: "euclideousRiffs")
                                                   var riffs = euclideousRiffs
                                                   mutate(&riffs)
                                                   euclideousRiffs = riffs
                                                   au?.editDocument(coalesceKey: "euclideousRiffs") { $0.riffs = riffs }
                                                   publish()
                                               },
                                               onSetActiveRiff: { v in
                                                   euclideousRecordUndo(coalesceKey: nil)
                                                   euclideousActiveRiff = v
                                                   au?.editDocument { $0.activeRiff = v }
                                                   publish()
                                               },
                                               onEditLanesSeq: { mutate in
                                                   euclideousRecordUndo(coalesceKey: "euclideousLanesSeq")
                                                   var s = euclideousLanesSeq
                                                   mutate(&s)
                                                   euclideousLanesSeq = s
                                                   au?.editDocument(coalesceKey: "euclideousLanesSeq") {
                                                       $0.euclideousLanesSeqOn = s.on; $0.euclideousLanesSeqRate = s.rate
                                                       $0.euclideousLanesSeqLen = s.len; $0.euclideousLanesSeqCells = s.cells
                                                   }
                                                   publish()
                                               },
                                               // FX TAB (2026-10-18): one document write + one republish per edit; `newStep` takes a `coalesceKey: nil` undo checkpoint (a tap, a
                                               // stroke's first change, a value drag's first change, a lane toggle, a stepper tap) and the rest of that gesture writes into it.
                                               onEditFX: { newStep, mutate in
                                                   if newStep { euclideousRecordUndo(coalesceKey: nil) }
                                                   var f = euclideousFX
                                                   mutate(&f)
                                                   f = f.normalized()
                                                   euclideousFX = f
                                                   au?.editDocument(coalesceKey: "euclideousFX") { $0.euclideousFX = f }
                                                   publish()
                                               },
                                               onEditRiffsSeq: { mutate in
                                                   euclideousRecordUndo(coalesceKey: "euclideousRiffsSeq")
                                                   var s = euclideousRiffsSeq
                                                   mutate(&s)
                                                   euclideousRiffsSeq = s
                                                   au?.editDocument(coalesceKey: "euclideousRiffsSeq") {
                                                       $0.euclideousRiffsSeqOn = s.on; $0.euclideousRiffsSeqRate = s.rate
                                                       $0.euclideousRiffsSeqLen = s.len; $0.euclideousRiffsSeqCells = s.cells
                                                   }
                                                   publish()
                                               },
                                               // §4.8 (2026-10-15 ferry, "per-step restart points"): a discrete pick, same
                                               // class as onSetActiveRiff/onSetKeyRoot above/below — coalesceKey: nil so it
                                               // always records its OWN undo step, never merging into whatever unrelated
                                               // euclideous-line edit happened immediately before it (the generic onEdit
                                               // funnel's shared "euclideous" key would have let that happen).
                                               onSetRestartMask: { lane, mask in
                                                   euclideousRecordUndo(coalesceKey: nil)
                                                   guard lane >= 0, lane < euclideousLines.count else { return }
                                                   var lines = euclideousLines
                                                   lines[lane].restartMask = mask
                                                   setEuclideousLines(lines)
                                                   au?.editDocument { $0.euclideousLines = lines }
                                                   publish()
                                               },
                                               onSetResetSpanBars: { v in
                                                   euclideousRecordUndo(coalesceKey: nil)
                                                   euclideousResetSpanBars = v
                                                   au?.editDocument { $0.euclideousResetSpanBars = v }
                                                   publish()
                                               },
                                               onSetKeyRoot: { v in
                                                   euclideousRecordUndo(coalesceKey: nil)
                                                   euclideousKeyRoot = v
                                                   au?.editDocument { $0.euclideousKeyRoot = v }
                                                   publish()
                                               },
                                               onSetKeyType: { v in
                                                   euclideousRecordUndo(coalesceKey: nil)
                                                   euclideousKeyType = v
                                                   au?.editDocument { $0.euclideousKeyType = v }
                                                   publish()
                                               },
                                               onSetMainOutMask: { v in
                                                   // §7.3 ("main outputs... not undoable") — not recorded, deliberately.
                                                   euclideousMainOutMask = v
                                                   au?.editDocument { $0.euclideousMainOutMask = v }
                                                   publish()
                                               },
                                               // LANE SOLO (2026-10-21, §3): touch-down puts the lane in the HELD mask at once (it counts as soloed for sound and every dim from the moment of touch); the lift clears it and — for a tap
                                               // only — flips the lane's LATCHED bit, in the SAME update (one publish, no flicker). Neither records undo (the output rings don't); only the latched mask is saved.
                                               // The effective mask goes to the render thread FIRST (`setEuclideousSoloLive`: one store the kernel reads at its next window), so the mute does not wait for the scene to be composed and a
                                               // snapshot built and published; `publish()` still follows so the snapshot (the fallback, and what a session with no page open plays) agrees.
                                               onSoloDown: { lane in
                                                   guard (0..<4).contains(lane) else { return }
                                                   euclideousSoloHeld |= UInt8(1 << lane)
                                                   au?.setEuclideousSoloLive(euclideousSoloEffective(latched: euclideousSoloMask, held: euclideousSoloHeld))
                                                   publish()
                                               },
                                               onSoloUp: { lane, latchToggles in
                                                   guard (0..<4).contains(lane) else { return }
                                                   euclideousSoloHeld &= ~UInt8(1 << lane)
                                                   if latchToggles { euclideousSoloMask ^= UInt8(1 << lane) }
                                                   au?.setEuclideousSoloLive(euclideousSoloEffective(latched: euclideousSoloMask, held: euclideousSoloHeld))
                                                   if latchToggles {
                                                       let v = euclideousSoloMask
                                                       au?.editDocument { $0.euclideousSoloMask = v }
                                                   }
                                                   publish()
                                               },
                                               // FOURFOLD SETTINGS (2026-10-15 ferry) — §6.3/§6.4: "no undo steps... changes
                                               // apply at once," same as onSetMainOutMask/onToggleEnabled/onSetMainOutMask
                                               // above — none of these 4 record onto euclideousUndo.
                                               midiInChannelMask: euclideousMidiInChannelMask,
                                               onSetMidiInChannelMask: { v in
                                                   euclideousMidiInChannelMask = v
                                                   au?.editDocument { $0.euclideousMidiInChannelMask = v }
                                                   publish()
                                               },
                                               ignoreAllNotesOff: ignoreAllNotesOff,
                                               onSetIgnoreAllNotesOff: { v in
                                                   ignoreAllNotesOff = v
                                                   au?.setIgnoreAllNotesOff(v)   // the SAME setter the cog page's INPUT toggle uses (§3.6, literal)
                                               },
                                               busChannels: busChannels,
                                               // The page calls the outputs MAIN OUT A–D; Fourfold's AU names its MIDI ports the same (FourfoldAudioUnit.midiOutputNames).
                                               outputNames: ["Out A", "Out B", "Out C", "Out D"],
                                               allOutputName: "All",
                                               onSetBusChannel: { bus, ch in
                                                   guard bus >= 0, bus < busChannels.count else { return }
                                                   var bc = busChannels
                                                   bc[bus] = max(1, min(16, ch))
                                                   busChannels = bc
                                                   au?.editDocument { $0.busChannels = bc }
                                                   publish()
                                               },
                                               onAllNotesOff: { au?.euclideousAllNotesOff() },
                                               hostStopBehavior: euclideousHostStopBehavior,
                                               onSetHostStopBehavior: { v in
                                                   euclideousHostStopBehavior = v
                                                   au?.editDocument { $0.euclideousHostStopBehavior = v }
                                                   publish()
                                               },
                                               onSetPulseLevel: { pulseLevel = max(0, min(2, $0)) },   // PULSE §7.1: a device preference (@AppStorage), not the document — no undo, no publish
                                               onOpenPresets: openPresets,
                                               reelRecording: d.playing && reelState != 2,   // the 8×8 header's own rule for the tape's red
                                               onOpenReel: { reelShowPopup = true },
                                               canUndo: euclideousUndo.canUndo, canRedo: euclideousUndo.canRedo,
                                               onUndo: euclideousUndoAction, onRedo: euclideousRedoAction,
                                               pageBottomInset: geo.safeAreaInsets.bottom,
                                   showsHostStopBehavior: !internalTransport)
        )
    }

    @_optimize(speed)
    @ViewBuilder func overlays(_ geo: GeometryProxy) -> some View {
        if reelShowPopup {      // the REEL pass browser, above the page (FOURFOLD REEL LINK 2026-10-23); framed to the root geo like the page
            FourfoldReelBrowser(au: au, size: geo.size, playing: d.playing, tempo: d.tempo, onClose: { reelShowPopup = false })
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        if showPresets {        // the preset browser (overlay; the engine keeps running)
            PresetBrowser(presets: presetList, factory: au?.factoryPresetNames() ?? [], current: currentPreset,
                          onSave: savePreset, onLoad: loadPreset, onLoadFactory: loadFactoryPreset,
                          onDelete: deletePreset, onClose: { showPresets = false })
        }
    }

    // ── publish: the Fourfold replacement for 8x8's buildPublishScene ──
    /// Compose the Fourfold cell from the live mirrors and hand it to the AU. Called after every document write (the engine reads these @State vars only through here).
    func publish() {
        let input = FourfoldCompose.Input(lines: euclideousLines, riff: euclideousRiff, riffs: euclideousRiffs, activeRiff: euclideousActiveRiff, mainOutMask: euclideousMainOutMask,
                                          soloMask: euclideousSoloEffective(latched: euclideousSoloMask, held: euclideousSoloHeld),   // LANE SOLO: latched | held — the render thread sees only the union
                                          locks: euclideousLocks, lockRevs: euclideousLockRevs)
        let chain = FourfoldCompose.chain(input)
        // The cell's machine id must resolve against the document's machines + the ephemeral registry (SnapshotBuilder skips a cell whose machine doesn't); re-registered only when the chain changes.
        if registeredChain != chain {
            registeredChain = chain
            au?.setBuildEphemeralMachines([(id: FourfoldCompose.machineID, machine: chain, transpose: 0)])
        }
        au?.setBuildStagingScene(FourfoldCompose.scene(chain: chain))
        // FREE-RUN: KEEP PLAYING runs Fourfold on its own clock while the host is stopped — gated off after the host stopped following a play (8x8's `buildHostHalted`: resumes when the host starts again).
        au?.setFreeRunEnabled(!internalTransport && euclideousHostStopBehavior == .keepPlaying && !hostHalted)   // the standalone app's transport is authoritative: STOP is silent
    }
    /// HOST TRANSPORT (8x8's `buildTransportEdge`): STOP halts free-run, START resumes it.
    func transportEdge(_ playing: Bool) {
        if playing { if hostHalted { hostHalted = false; publish() } }
        else { hostHalted = true; publish() }
    }

    func refreshTiming() { stepIndex = au?.uiStepRateIndex() ?? stepIndex; swing = au?.uiSwing() ?? swing }

    /// Load every Fourfold mirror from the document (a preset load, an undo, a session restore, the first appearance).
    func refreshFromDocument() {
        guard let au else { return }
        busChannels = au.uiBusChannels()
        euclideousLocks = au.uiEuclideousLocks()
        euclideousLines = au.uiEuclideousLines()
        applyLandedLockSnaps(ring: false)   // LANE LOCK: a snap landed while the window was closed (the sound followed L at once) is written into the document now
        pushLockLive()
        euclideousRiff = au.uiEuclideousRiff()
        euclideousResetSpanBars = au.uiEuclideousResetSpanBars()
        euclideousKeyRoot = au.uiEuclideousKeyRoot()
        euclideousKeyType = au.uiEuclideousKeyType()
        euclideousNoteSource = au.uiEuclideousNoteSource()
        euclideousHoldLatchMode = au.uiEuclideousHoldLatchMode()
        euclideousMainOutMask = au.uiEuclideousMainOutMask()
        euclideousSoloMask = au.uiEuclideousSoloMask()
        au.setEuclideousSoloLive(euclideousSoloEffective(latched: euclideousSoloMask, held: euclideousSoloHeld))   // the live word follows the document (a restore / a preset load)
        euclideousMidiInChannelMask = au.uiEuclideousMidiInChannelMask()
        euclideousHostStopBehavior = au.uiEuclideousHostStopBehavior()
        ignoreAllNotesOff = au.uiIgnoreAllNotesOff()
        euclideousChords = au.uiEuclideousChords()
        euclideousRiffs = au.uiEuclideousRiffs()
        euclideousActiveRiff = au.uiEuclideousActiveRiff()
        euclideousLanesSeq = au.uiEuclideousLanesSeq()
        euclideousFX = au.uiEuclideousFX()
        euclideousRiffsSeq = au.uiEuclideousRiffsSeq()
    }

    // ── presets ──
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
        euclideousRecordUndo(coalesceKey: nil)   // usability ferry §7.2: "loading a preset" is undoable
        au?.loadPreset(named: name)
        presetLoaded()
    }
    func loadFactoryPreset(_ name: String) {
        euclideousRecordUndo(coalesceKey: nil)
        au?.loadFactoryPreset(named: name)
        presetLoaded()
    }
    private func presetLoaded() {
        refreshFromDocument()
        refreshTiming()
        currentPreset = au?.uiCurrentPreset() ?? ""
        showPresets = false
        publish()   // the AU swapped the document; the staging scene still holds the OLD chain until it is composed again
    }
    func deletePreset(_ name: String) {
        au?.deletePreset(named: name)
        presetList = au?.listPresets() ?? []
        currentPreset = au?.uiCurrentPreset() ?? ""
    }

    // ── undo / redo / lane lock (copied from DiagView) ──
    func euclideousSnapshot() -> EuclideousUndoSnapshot {
        EuclideousUndoSnapshot(lines: euclideousLines, riff: euclideousRiff, resetSpanBars: euclideousResetSpanBars,
                                keyRoot: euclideousKeyRoot, keyType: euclideousKeyType, chords: euclideousChords,
                                noteSource: euclideousNoteSource,
                                riffs: euclideousRiffs, activeRiff: euclideousActiveRiff,
                                lanesSeq: euclideousLanesSeq, riffsSeq: euclideousRiffsSeq, fx: euclideousFX,
                                holdLatchMode: euclideousHoldLatchMode)
    }
    /// Called BEFORE a mutation, with the PRE-mutation live state (`UndoStack.record`'s own documented
    /// contract) — every undoable Euclideous edit funnel (onEdit/onEditRiff/onEditChords/onSetResetSpanBars/
    /// onSetKeyRoot/onSetKeyType, + loadFactoryPreset/loadPreset below) calls this first.
    func euclideousRecordUndo(coalesceKey: String?) {
        euclideousUndo.record(euclideousSnapshot(), coalesceKey: coalesceKey)
    }
    /// Apply a restored snapshot. §7.3 ("play/stop... not undoable") is enforced HERE, not at record time —
    /// every per-lane PLAY/STOP and per-mask PLAY/STOP flows through the SAME generic `onEdit` funnel as every
    /// other (undoable) lane setting, so recording can't distinguish them; restoring can, by re-merging the
    /// CURRENT live values for exactly those two sub-fields back over whatever the snapshot itself carries.
    func euclideousApply(_ s: EuclideousUndoSnapshot) {
        var lines = s.lines
        for i in lines.indices where i < euclideousLines.count {
            lines[i].enabled = euclideousLines[i].enabled
            if var m = lines[i].mask { m.enabled = euclideousLines[i].mask?.enabled ?? m.enabled; lines[i].mask = m }
        }
        // LANE LOCK §9.2: restoring a step never moves a locked lane's lock fields (and the locks themselves are not in a step at all)
        lines = euclideousLockMergeForUndo(restored: lines, current: euclideousLines, locked: euclideousLocks.map { $0.isLocked })
        setEuclideousLines(lines)
        euclideousRiff = s.riff
        euclideousResetSpanBars = s.resetSpanBars
        euclideousKeyRoot = s.keyRoot
        euclideousKeyType = s.keyType
        euclideousChords = s.chords
        euclideousNoteSource = s.noteSource
        euclideousRiffs = s.riffs
        euclideousActiveRiff = s.activeRiff
        euclideousLanesSeq = s.lanesSeq
        euclideousRiffsSeq = s.riffsSeq
        euclideousFX = s.fx
        euclideousHoldLatchMode = s.holdLatchMode
        au?.editDocument {
            $0.euclideousLines = lines; $0.euclideousRiff = s.riff; $0.euclideousResetSpanBars = s.resetSpanBars
            $0.euclideousKeyRoot = s.keyRoot; $0.euclideousKeyType = s.keyType; $0.euclideousChords = s.chords
            $0.euclideousNoteSource = s.noteSource
            $0.riffs = s.riffs; $0.activeRiff = s.activeRiff
            $0.euclideousLanesSeqOn = s.lanesSeq.on; $0.euclideousLanesSeqRate = s.lanesSeq.rate
            $0.euclideousLanesSeqLen = s.lanesSeq.len; $0.euclideousLanesSeqCells = s.lanesSeq.cells
            $0.euclideousRiffsSeqOn = s.riffsSeq.on; $0.euclideousRiffsSeqRate = s.riffsSeq.rate
            $0.euclideousRiffsSeqLen = s.riffsSeq.len; $0.euclideousRiffsSeqCells = s.riffsSeq.cells
            $0.euclideousFX = s.fx
            $0.euclideousHoldLatchMode = s.holdLatchMode
        }
        publish()
    }
    func euclideousUndoAction() {
        guard let prev = euclideousUndo.undo(current: euclideousSnapshot()) else { return }
        euclideousApply(prev)
    }
    func euclideousRedoAction() {
        guard let next = euclideousUndo.redo(current: euclideousSnapshot()) else { return }
        euclideousApply(next)
    }

    // MARK: LANE LOCK (ferry 2026-10-21) — the page's side of the snap back
    /// The lanes a finger is on, and the revisions, straight to the render thread (BEFORE any publish, so "an edit is on its way" is true from the moment the document changes).
    func pushLockLive() {
        var held: UInt8 = 0
        for i in 0..<4 where euclideousLockTouches[i] > 0 { held |= 1 << UInt8(i) }
        au?.setEuclideousLockLive(held: held, revs: euclideousLockRevs)
    }
    func bumpLockRev(_ lane: Int) { euclideousLockRevs = EuclideousLockLive.bumped(euclideousLockRevs, lane: lane) }
    /// THE one way the mirror of `euclideousLines` changes: a locked lane whose line changes gets its revision bumped, so the render thread never mistakes a stale snapshot for a settled one (6.4).
    func setEuclideousLines(_ new: [EuclidLine]) {
        let old = euclideousLines
        for i in 0..<min(4, old.count, new.count) where old[i] != new[i] && euclideousLocks[i].isLocked { bumpLockRev(i) }
        euclideousLines = new
        pushLockLive()
    }
    /// A lock write (lock / capture / unlock / grid / a preset's locks arriving): the lane's revision moves with it, so the render thread drops any landed-snap override and reads the new snapshot.
    func setEuclideousLocks(_ new: [EuclideousLaneLock], persist: Bool) {
        for i in 0..<min(4, new.count, euclideousLocks.count) where new[i] != euclideousLocks[i] { bumpLockRev(i) }
        euclideousLocks = new
        if persist { au?.editDocument { $0.euclideousLocks = new } }
        pushLockLive()
    }
    /// 6.8 / D3: the render thread has switched lane(s) back to L at a grid line — write L into the document as ONE change (no undo), ring the card. Called by the 30 Hz poll, at the head of every edit funnel (so an edit
    /// after a snap lands on L, not on the stale deviated line) and when the page opens.
    func applyLandedLockSnaps(ring: Bool = true) {
        guard let au else { return }
        let seq = au.pollEuclideousLockSnapSeq()
        guard seq != euclideousLockAppliedSeq else { return }
        var lines = euclideousLines
        var changed = false
        for lane in 0..<4 where EuclideousLockLive.rev(seq, lane: lane) != EuclideousLockLive.rev(euclideousLockAppliedSeq, lane: lane) {
            guard lane < lines.count, euclideousLocks[lane].isLocked, let L = euclideousLocks[lane].state else { continue }
            let before = lines[lane]
            L.applied(to: &lines[lane])
            if lines[lane] != before { changed = true }
            if ring { euclideousLockRingStart[lane] = Date() }
        }
        euclideousLockAppliedSeq = seq
        if changed {
            setEuclideousLines(lines)
            au.editDocument { $0.euclideousLines = lines }
            publish()
        }
    }
    /// 6.5: the page is not running — there are no lines to wait for, so a deviated lane nobody is touching goes back to L at once.
    func applyLockStoppedRule() {
        guard !d.effectivePlaying, euclideousLocks.contains(where: { $0.isLocked }) else { return }
        var lines = euclideousLines
        var changed = false
        for lane in 0..<4 where lane < lines.count {
            guard euclideousLocks[lane].isLocked, let L = euclideousLocks[lane].state else { continue }
            if euclideousLockSnapsNow(deviated: euclideousLockDeviated(line: lines[lane], from: L), held: euclideousLockTouches[lane] > 0, running: false) {
                L.applied(to: &lines[lane]); changed = true
                euclideousLockRingStart[lane] = Date()
            }
        }
        if changed {
            setEuclideousLines(lines)
            au?.editDocument { $0.euclideousLines = lines }
            publish()
        }
    }
    /// The lock card's / badge's commands (7.1–7.4): document writes with no undo step. Chains are pinned by the main-thread migration within a quarter second of a load, so L captured here is already on the chain model.
    func lockCommand(_ lane: Int, _ cmd: EuclideousLockCommand) {
        guard (0..<4).contains(lane), lane < euclideousLines.count else { return }
        applyLandedLockSnaps()
        var locks = euclideousLocks
        let line = euclideousLines[lane]
        switch cmd {
        case .lock:
            locks[lane] = EuclideousLaneLock.locking(line, grid: locks[lane].gridResolved)
        case .capture:
            locks[lane] = EuclideousLaneLock.locking(line, grid: locks[lane].gridResolved)   // L = what is playing now, lockOn true, nothing left to snap
            euclideousLockRingStart[lane] = Date()
        case .unlock:
            locks[lane].on = false; locks[lane].state = nil                                      // what is playing stays, even if it was deviated
            euclideousLockTouches[lane] = 0                                                      // no finger is "held" on an unlocked lane (a touch counted before the unlock must not outlive it)
        case .setGrid(let g):
            locks[lane].grid = g
        }
        setEuclideousLocks(locks, persist: true)
        publish()
    }
    /// A finger goes down on / lifts from a lock-field control of `lane` (6.2). Several touches: held until the last lifts. At the lift, a stopped page puts the lane straight back (6.5).
    func lockHeld(_ lane: Int, _ down: Bool) {
        guard (0..<4).contains(lane) else { return }
        euclideousLockTouches[lane] = max(0, euclideousLockTouches[lane] + (down ? 1 : -1))
        pushLockLive()
        if !down && euclideousLockTouches[lane] == 0 { applyLockStoppedRule() }
    }

    // ── polls ──
    /// ~30 Hz: the live per-lane indicators, the lock snaps, the strike feed.
    @_optimize(speed)
    func fastPoll() {
        guard uiAppeared, let au else { return }
    let rp = au.pollEuclideousRiffPositions()
    if rp != euclideousRiffPositions { euclideousRiffPositions = rp }
    let rws = au.pollEuclideousRiffWalkState()
    if rws != euclideousRiffWalkState { euclideousRiffWalkState = rws }
    let mp = au.pollEuclideousMaskPositions()
    if mp != euclideousMaskPositions { euclideousMaskPositions = mp }
    let rlp = au.pollEuclideousRiffLivePool()
    if rlp != euclideousRiffLivePool { euclideousRiffLivePool = rlp }
    applyLandedLockSnaps()   // LANE LOCK: a snap the render thread has landed is written into the document within a poll tick (30 Hz)
    applyLockStoppedRule()   // LANE LOCK 6.5: a stopped page has no lines to wait for
    let lss = au.pollEuclideousLanesSeqStep()
    if lss != euclideousLanesSeqStep { euclideousLanesSeqStep = lss }
    let rss = au.pollEuclideousRiffsSeqStep()
    if rss != euclideousRiffsSeqStep { euclideousRiffsSeqStep = rss }
    // RIFF-CELL WIPES (Paul 2026-10-10 ferry): drain the per-lane event queue and fold it into
    // ONE reconciled slot — the NOTE VIEW panel this queue originally also fed (euclideousNV
    // LastEvent/RestFlash) was RETIRED by the 2026-10-14 sequencer-panel ferry (superseded by
    // the new SEQUENCER panel); this wipe-mark reconciliation is genuinely separate (it feeds
    // the riff grid's own walk-arrow markers, not that panel) and survives unchanged. Only a
    // genuinely wipe-eligible event (column >= 0) ever overwrites it, so an ordinary FILL/
    // CHORD-extra push (column == -1) can't clobber a wipe still mid-sweep.
    let nvEvents = au.pollEuclideousNoteViewEvents()
    if nvEvents.count == 4 {
        var newWipe = euclideousWipeEvent, changed = false
        var newStrike = euclideousStrikeEvent, strikeChanged = false
        for lane in 0..<4 {
            for ev in nvEvents[lane] where ev.column >= 0 {
                newWipe[lane] = ev
                changed = true
            }
            // A strike = a hit (kind 0) or a tied hit (kind 3) that actually carries notes; kind 2 is the SKIP rest flash.
            for ev in nvEvents[lane] where (ev.kind == 0 || ev.kind == 3) && !ev.notes.isEmpty {
                newStrike[lane] = ev
                strikeChanged = true
            }
        }
        if changed { euclideousWipeEvent = newWipe }
        if strikeChanged { euclideousStrikeEvent = newStrike }
        // PULSE: the same drained events, kept with their velocities and stamped on the display clock the comet dot reads (nothing new is polled).
        for lane in 0..<4 { meters.pulse.ingest(lane: lane, events: nvEvents[lane], anchorBeat: meters.beatAnchor, anchorAt: meters.beatAnchorAt, tempo: meters.tempo) }
    }

    }
    /// 4 Hz: resync the mirrors from the document (a host session restore, a preset), the migrations, the transport / beat clock.
    @_optimize(speed)
    func slowPoll() {
        guard uiAppeared, let au else { return }
        var euclideousResynced = false
        let elk = au.uiEuclideousLocks(); if elk != euclideousLocks { setEuclideousLocks(elk, persist: false); euclideousResynced = true }   // LANE LOCK: a preset load / session restore replaces the locks
        let elv = au.uiEuclideousLines(); if elv != euclideousLines { setEuclideousLines(elv); euclideousResynced = true }
        let erf = au.uiEuclideousRiff(); if erf != euclideousRiff { euclideousRiff = erf; euclideousResynced = true }
        // EUCLIDEOUS PAGE REWORK (Paul 2026-10-07): every new global field MUST be resynced here too — this
        // exact block has silently reset Euclideous on reload before when a field was missing from this
        // checklist (see the fresh-plugin-load history above), so each of the 6 new fields gets its own line.
        let ersb = au.uiEuclideousResetSpanBars(); if ersb != euclideousResetSpanBars { euclideousResetSpanBars = ersb; euclideousResynced = true }
        let ekr = au.uiEuclideousKeyRoot(); if ekr != euclideousKeyRoot { euclideousKeyRoot = ekr; euclideousResynced = true }
        let ekt = au.uiEuclideousKeyType(); if ekt != euclideousKeyType { euclideousKeyType = ekt; euclideousResynced = true }
        let emom = au.uiEuclideousMainOutMask(); if emom != euclideousMainOutMask { euclideousMainOutMask = emom; euclideousResynced = true }
        let esol = au.uiEuclideousSoloMask(); if esol != euclideousSoloMask { euclideousSoloMask = esol; au.setEuclideousSoloLive(euclideousSoloEffective(latched: esol, held: euclideousSoloHeld)); euclideousResynced = true }   // LANE SOLO: a preset load / session restore replaces it
        let emicm = au.uiEuclideousMidiInChannelMask(); if emicm != euclideousMidiInChannelMask { euclideousMidiInChannelMask = emicm; euclideousResynced = true }
        let ehsb = au.uiEuclideousHostStopBehavior(); if ehsb != euclideousHostStopBehavior { euclideousHostStopBehavior = ehsb; euclideousResynced = true }
        let echd = au.uiEuclideousChords(); if echd != euclideousChords { euclideousChords = echd; euclideousResynced = true }
        let ens = au.uiEuclideousNoteSource(); if ens != euclideousNoteSource { euclideousNoteSource = ens; euclideousResynced = true }
        let ehlm = au.uiEuclideousHoldLatchMode(); if ehlm != euclideousHoldLatchMode { euclideousHoldLatchMode = ehlm; euclideousResynced = true }
        // SEQUENCER PANEL (2026-10-14 ferry) — same checklist discipline as the 6 lines just above.
        let erfs = au.uiEuclideousRiffs(); if erfs != euclideousRiffs { euclideousRiffs = erfs; euclideousResynced = true }
        let ear = au.uiEuclideousActiveRiff(); if ear != euclideousActiveRiff { euclideousActiveRiff = ear; euclideousResynced = true }
        let els = au.uiEuclideousLanesSeq(); if els != euclideousLanesSeq { euclideousLanesSeq = els; euclideousResynced = true }
        let ers = au.uiEuclideousRiffsSeq(); if ers != euclideousRiffsSeq { euclideousRiffsSeq = ers; euclideousResynced = true }
        let efx = au.uiEuclideousFX(); if efx != euclideousFX { euclideousFX = efx; euclideousResynced = true }
        if euclideousResynced { publish() }
        let nd = au.kernelDiagnostics()
        if nd.panics != lastStuckPanics {   // a8 STUCK-NOTE: the render thread healed since the last poll — log it ONCE here, off the audio thread (was an os_log PER BLOCK on the render path = crackle; Paul 2026-09-12)
            lastStuckPanics = nd.panics
            let why = nd.stuckReason == 1 ? "silence invariant violated (stopped)"
                    : nd.stuckReason == 2 ? "playing silence leak (no source)" : "stuck note"
            os_log(.fault, log: FourfoldRootView.hangLog, "MidiSpark STUCK-NOTE: %{public}s — voices=%d echoes=%d panics=%llu",
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
        meters.beatsPerBar = nd.beatsPerBar
        // RESTART CHAINS (2026-10-19 ferry §12.2, render-thread safety): `migrateRestartChains` allocates
        // and walks a bounded-but-real 128-bar window — NOT safe to call from `Router.runEuclidLine` (the
        // audio render thread, invariant 3: no allocation on the render path). Migrated here instead, on
        // this MAIN-THREAD 4Hz poll, where `meters.beatsPerBar`/`nd.beatsPerBar` are ALSO available (the
        // same context the render path would have needed) — and PINNED immediately on first sight of a
        // pre-feature lane, not deferred until the user happens to edit it: an un-pinned lane would
        // otherwise render as FREE (Router's own safe fallback for `!usesRestartChains`) until this tick
        // catches up, and pinning here closes that window to about one poll interval, matching this same
        // loop's own "4 Hz is good enough" tolerance everywhere else on this page. Not an undo step (an
        // invisible stabilisation of what the lane already sounded like, not a user-authored change) —
        // mirrors how `euclideousApplyLaneGridOp`'s own first-touch pin works, just triggered by TIME
        // rather than by a touch.
        if nd.beatsPerBar > 0 {
            var migratedAny = false
            var lines = euclideousLines
            for i in lines.indices where !lines[i].usesRestartChains {
                let line = lines[i]
                let n = max(2, min(16, line.steps))
                let sub = line.rate?.beats ?? 0.5   // 1/8 note — the same machine-wide fallback every other reader of a possibly-nil `rate` ultimately resolves to
                let migrated = migrateRestartChains(line: line, lane: i, legacyOn: euclideousLanesSeq.on, legacyRate: euclideousLanesSeq.rate,
                                                    legacyLen: euclideousLanesSeq.len, legacyCells: euclideousLanesSeq.cells,
                                                    sub: sub, n: n, dir: line.directionResolved, barBeats: nd.beatsPerBar)
                euclideousPinRestartChains(&lines[i], .from(migrated.rhythm), .from(migrated.melody))
                // LANE LOCK: the pin is a main-thread stabilisation, not a user edit — if the lane is locked with its chains still unpinned in L, L is pinned the same way, so a pin is never "deviation"
                if euclideousLocks[i].isLocked, var st = euclideousLocks[i].state, !(st.restartRhythmBars != nil || st.restartMelodyPasses != nil) {
                    st.restartRhythmBars = lines[i].restartRhythmBars; st.restartMelodyPasses = lines[i].restartMelodyPasses
                    var locks = euclideousLocks; locks[i].state = st
                    setEuclideousLocks(locks, persist: true)
                }
                migratedAny = true
            }
            if migratedAny {
                setEuclideousLines(lines)
                au.editDocument { $0.euclideousLines = lines }
                publish()   // `euclideousResynced`'s own publish (above) already ran this tick — this block lands after it, so it republishes directly
            }
        }
        // RANDOM MODE ferry §6.3/§6.7: the render thread already switched exactly on time (its own per-tick
        // sample-accurate check, Router.swift); this main-thread commit is pure bookkeeping — write the
        // landed roll into the document so it's the live truth going forward, and clear its slot so Router
        // stops overriding a lane the document now already agrees with. The ~1/4 s poll-tick lag this
        // tolerates is harmless (not an audio-timing guarantee).
        if euclideousPendingRolls.contains(where: { $0 != nil }) {
            var lines = euclideousLines
            var rolls = euclideousPendingRolls
            var landedAny = false
            for lane in lines.indices {
                for tab in EuclideousRandomTab.allCases {
                    let slot = euclideousRandomPendingSlot(lane: lane, tab: tab)
                    guard slot < rolls.count, let roll = rolls[slot], euclideousRandomShouldApply(hostBeat: nd.beat, landingBeat: roll.landingBeat) else { continue }
                    euclideousRandomCommitPendingRoll(roll, into: &lines[lane])
                    rolls[slot] = nil
                    landedAny = true
                }
            }
            if landedAny {
                euclideousPendingRolls = rolls
                au.setEuclideousPendingRolls(rolls)
                setEuclideousLines(lines)
                au.editDocument { $0.euclideousLines = lines }
                publish()
            }
        }
        meters.pulse.noteTransport(playing: nd.effectivePlaying, at: Date())   // PULSE: a start drops the last run's strikes, a stop starts the 1.5 s settle
        meters.syncBeat(nd.beat, tempo: nd.tempo, playing: nd.effectivePlaying, at: Date())   // BEAT clock (4 Hz) → the telemetry; playheads extrapolate at 30 fps. DEJITTER: re-anchors only on a discontinuity, else free-runs (see syncBeat) → no 4 Hz stutter
        if nd.playing != d.playing || nd.effectivePlaying != d.effectivePlaying || nd.tempo != d.tempo || nd.pass != d.pass { d = nd }
        let nb = au.uiBusChannels();   if nb != busChannels { busChannels = nb }
        let ian = au.uiIgnoreAllNotesOff(); if ian != ignoreAllNotesOff { ignoreAllNotesOff = ian }
        let rs = au.uiReelState();     if rs != reelState { reelState = rs }   // the header tape icon's state
        let si = au.uiStepRateIndex(); if si != stepIndex { stepIndex = si }
        let sw = au.uiSwing();         if sw != swing { swing = sw }
    }
}

/// The Fourfold root view's mutable state (see the note in `FourfoldRootView`). Defaults are the ones the 8x8 host's @State declarations had.
final class FourfoldModel: ObservableObject {
    @Published var d: KernelDiag = KernelDiag()      // polled for playing / tempo / pass
    @Published var lastStuckPanics: UInt64 = 0   // a8 STUCK-NOTE: last-seen heal count — the poll logs a heal ONCE (off the render thread) when this rises
    @Published var uiAppeared: Bool = true     // §4c INVISIBLE=FROZEN: this view is on-screen
    @Published var appActive: Bool = true
    let meters = FourfoldTelemetry()
    @Published var swing: Int = 50
    @Published var stepIndex: Int = 2
    @Published var busChannels: [Int] = [1, 2, 3, 4]
    @Published var ignoreAllNotesOff: Bool = true
    @Published var showPresets: Bool = false
    @Published var presetList: [String] = []
    @Published var currentPreset: String = ""
    @Published var reelShowPopup: Bool = false
    @Published var reelState: Int = 0    // 0 off · 1 armed · 2 replaying (polled)
    @Published var hostHalted: Bool = false
    @Published var registeredChain: [ProcessorSlot] = []
    @Published var euclideousLines: [EuclidLine] = Array(repeating: EuclidLine(noteSel: .all), count: 4)
    @Published var euclideousUndo: UndoStack<EuclideousUndoSnapshot> = UndoStack<EuclideousUndoSnapshot>()   // a SEPARATE stack from the AU's whole-document undo (usability ferry §7); in-memory, cleared per instance
    @Published var euclideousRiff: EuclideousRiff = EuclideousRiff()
    @Published var euclideousRiffs: [EuclideousRiff] = [EuclideousRiff(), EuclideousRiff.empty, EuclideousRiff.empty, EuclideousRiff.empty]
    @Published var euclideousActiveRiff: Int = 0
    @Published var euclideousLanesSeq: EuclideousLanesSeq = EuclideousLanesSeq()
    @Published var euclideousFX: EuclideousFX = EuclideousFX()
    @Published var euclideousRiffsSeq: EuclideousRiffsSeq = EuclideousRiffsSeq()
    @Published var euclideousRiffPositions: [Int] = [-1, -1, -1, -1]
    @Published var euclideousMaskPositions: [Int] = [-1, -1, -1, -1]
    @Published var euclideousRiffLivePool: [UInt8] = []
    @Published var euclideousLanesSeqStep: Int = -1
    @Published var euclideousRiffsSeqStep: Int = -1
    @Published var euclideousWipeEvent: [Router.EuclideousNoteViewEventSnapshot?] = [nil, nil, nil, nil]
    @Published var euclideousStrikeEvent: [Router.EuclideousNoteViewEventSnapshot?] = [nil, nil, nil, nil]
    @Published var euclideousRiffWalkState: [Int64] = Array(repeating: 0, count: 4)
    @Published var euclideousResetSpanBars: Int = 0
    @Published var euclideousKeyRoot: Int = 0
    @Published var euclideousKeyType: ScaleType = .naturalMinor
    @Published var euclideousNoteSource: EuclideousLaneSource = .key
    @Published var euclideousHoldLatchMode: EuclideousHoldLatchMode? = nil
    @Published var euclideousMainOutMask: UInt8 = 0b1111
    @Published var euclideousSoloMask: UInt8 = 0
    @Published var euclideousSoloHeld: UInt8 = 0
    @Published var euclideousLocks: [EuclideousLaneLock] = Array(repeating: EuclideousLaneLock(), count: 4)
    @Published var euclideousLockRevs: UInt32 = 0
    @Published var euclideousLockTouches: [Int] = [0, 0, 0, 0]
    @Published var euclideousLockAppliedSeq: UInt32 = 0
    @Published var euclideousLockRingStart: [Date?] = [nil, nil, nil, nil]
    @Published var euclideousPendingRolls: EuclideousPendingRollSlots = EuclideousPendingRollSlots()
    @Published var euclideousHoldOverrides: EuclideousPendingRollSlots = EuclideousPendingRollSlots()
    @Published var euclideousMidiInChannelMask: UInt16 = 0xFFFF
    @Published var euclideousHostStopBehavior: EuclideousHostStopBehavior = .keepPlaying
    @Published var euclideousChords: MachineParams = MachineParams()
}

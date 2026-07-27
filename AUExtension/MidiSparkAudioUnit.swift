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
    private var document = PluginState.factory()
    private let store: SnapshotStore
    private var rebuildPending = false
    private var snapshotGeneration: UInt64 = 1
    private var suppressRebuild = false

    /// Currently loaded test session id ("—" until one is loaded). Diagnostics only.
    private(set) var loadedTestSession = "—"

    /// Live kernel diagnostics for the debug UI (polled; torn reads are fine for display).
    func kernelDiagnostics() -> KernelDiag { kernel.diag }

    /// Read-only view of the active scene for the grid UI (main thread; value copy).
    func uiScene() -> SceneState { document.scenes[document.activeScene] }

    /// The single grid-edit path: mutate the active scene, then publish a fresh snapshot. MAIN
    /// THREAD (SwiftUI actions already are). All UI edits — paint, clear, wiring — go through here,
    /// so the render side sees them exactly as it sees a preset load. UI-only state (selection,
    /// brush) never touches the document.
    func editScene(record: Bool = true, coalesceKey: String? = nil, _ mutate: (inout SceneState) -> Void) {
        if record { undoStack.record(document, coalesceKey: coalesceKey) }   // a6: snapshot BEFORE the mutation
        mutate(&document.scenes[document.activeScene])
        scheduleRebuild()
    }

    /// Document-level edit path (busChannels, receivers, …) — same publish semantics as editScene.
    func editDocument(record: Bool = true, coalesceKey: String? = nil, _ mutate: (inout PluginState) -> Void) {
        if record { undoStack.record(document, coalesceKey: coalesceKey) }
        mutate(&document)
        scheduleRebuild()
    }

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

    /// §6a metering: per-emitter peak velocity (0–127) + event count since the last poll (read-and-clear).
    func pollEmitterActivity() -> (peak: [UInt8], events: [UInt32]) { kernel.drainEmitterActivity() }

    /// delta §9 item 11: per-receiver INPUT peak velocity + event count since the last poll (read-and-clear).
    func pollReceiverActivity() -> (peak: [UInt8], events: [UInt32]) { kernel.drainReceiverActivity() }
    func pollEmitterMarks() -> [[(vel: UInt8, col: Int8)]] { kernel.drainEmitterMarks() }   // item 4 velocity marks
    func pollWithheldMarks() -> [[(vel: UInt8, col: Int8)]] { kernel.drainWithheldMarks() }   // §6a the withheld tell
    func pollReceiverMarks() -> [[UInt8]] { kernel.drainReceiverMarks() }
    func pollReceiverSounding() -> [[UInt8]] { kernel.pollReceiverSounding() }   // duration: currently-held input notes

    /// Read-only snapshot of the per-bus stamp channels for the OUTPUTS panel (delta §7).
    func uiBusChannels() -> [Int] { document.busChannels }

    /// delta §9 item 11: the four resolved receivers (nil-safe) for the editor's INPUT radio + the panel.
    func uiReceivers() -> [Receiver] { document.receiversResolved }
    func setReceiverChannel(_ i: Int, _ ch: Int) { editReceiver(i) { $0.channel = max(0, min(16, ch)) } }
    func setReceiverCable(_ i: Int, _ mask: Int?)  { editReceiver(i) { $0.cable = mask } }   // §item 11 INPUT CABLES
    func toggleReceiverMute(_ i: Int)             { editReceiver(i) { $0.muted.toggle() } }
    // MPE is silent auto-detect (user ruling 2026-07-25) — no setter/UI; the `mpeMerge` field is reserved.
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
    func setMasterVelOverride(_ value: Int?) { kernel.setMasterVelOverride(value) }
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

    /// Global STEP rate (AUParameter 0) and SWING (AUParameter 1) — the scene-level timing. Set via
    /// the tree so host automation stays in sync (§4). Read-back for the header display.
    func uiStepRateIndex() -> Int { StepRate.allCases.firstIndex(of: document.scenes[document.activeScene].stepRate) ?? 2 }
    func uiSwing() -> Int { document.scenes[document.activeScene].swing }
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
        store = SnapshotStore(initial: SnapshotBuilder.build(from: PluginState.factory(), generation: 1))
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
    enum ParamAddress {
        static let stepRate: AUParameterAddress = 0
        static let swing: AUParameterAddress = 1
        static func transpose(_ i: Int) -> AUParameterAddress { 100 + AUParameterAddress(i) }
        static func morph(_ i: Int) -> AUParameterAddress { 200 + AUParameterAddress(i) }
        static let morphMaster: AUParameterAddress = 300
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
                self.document.scenes[0].stepRate = all[min(all.count - 1, max(0, Int(value)))]
            case ParamAddress.swing:
                self.document.scenes[0].swing = Int(value)
            case ParamAddress.morphMaster:
                self.document.morphMaster = Double(value)
            case let a where a >= 200 && a < 200 + AUParameterAddress(colourIDs.count):
                self.document.colours[Int(a - 200)].morph = Double(value)
            case let a where a >= 100 && a < 100 + AUParameterAddress(colourIDs.count):
                self.document.colours[Int(a - 100)].transpose = Int(value)
            default: break
            }
        }
        _parameterTree.implementorValueProvider = { [weak self] param in
            guard let self else { return 0 }
            switch param.address {
            case ParamAddress.stepRate:
                return AUValue(StepRate.allCases.firstIndex(of: self.document.scenes[0].stepRate) ?? 2)
            case ParamAddress.swing: return AUValue(self.document.scenes[0].swing)
            case ParamAddress.morphMaster: return AUValue(self.document.morphMaster)
            case let a where a >= 200 && a < 200 + AUParameterAddress(colourIDs.count):
                return AUValue(self.document.colours[Int(a - 200)].morph)
            case let a where a >= 100 && a < 100 + AUParameterAddress(colourIDs.count):
                return AUValue(self.document.colours[Int(a - 100)].transpose)
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

    /// Push document values out to the AUParameterTree so host-visible state matches reality.
    private func syncParameterTreeToDocument() {
        let scene = document.scenes[document.activeScene]
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

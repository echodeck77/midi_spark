//  MidiSparkAudioUnit.swift
//  AUv3 MIDI processor (aumi). Spec v2.8.
//  Declares four MIDI outputs (§2/§8), the 35-parameter table with stable addresses (§8/§13.5),
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
    func editScene(_ mutate: (inout SceneState) -> Void) {
        mutate(&document.scenes[document.activeScene])
        scheduleRebuild()
    }

    /// Document-level edit path (busChannels, morphMaster, …) — same publish semantics as editScene.
    func editDocument(_ mutate: (inout PluginState) -> Void) {
        mutate(&document)
        scheduleRebuild()
    }

    /// Read-only snapshot of the per-bus stamp channels for the OUTPUTS panel (delta §7).
    func uiBusChannels() -> [Int] { document.busChannels }

    /// Read-only Colours (type + params) so the grid can render each cell's type glyph + params text.
    func uiColours() -> [Colour] { document.colours }

    /// Edit a Colour's NON-AUParameter fields (type, pattern, rate, octaves, gate, phase, count,
    /// passes, strum, chance, harmonize) → rebuild. Transpose/morph are AUParameters — use the
    /// dedicated setters below so host automation stays in sync.
    func editColour(_ index: Int, _ mutate: (inout Colour) -> Void) {
        guard index >= 0, index < document.colours.count else { return }
        mutate(&document.colours[index])
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

    // MARK: - Four MIDI outputs — the load-bearing line (§8). AUM shows these as four sources.
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
        document.migrateLegacyRoutingIfNeeded()   // fill inputRow (dormant until the commit-3 router flip)
        loadedTestSession = session.id

        // Tree writes re-enter implementorValueObserver (each calling scheduleRebuild), so
        // suppress and publish exactly one snapshot at the end.
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

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            if let data = try? JSONEncoder().encode(document) { state[Self.stateKey] = data }
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

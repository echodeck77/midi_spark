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
    @State private var emitPeak: [Double] = [0, 0, 0, 0]               // §6a meter: latched peak (0–1) per emitter
    @State private var emitPeakAt: [Date] = Array(repeating: .distantPast, count: 4)   // when each peak latched (for decay)
    @State private var docColours: [Colour] = []
    @State private var stepIndex = 2
    @State private var swing = 50
    @State private var editing = true          // EDIT vs PERFORM (§6.1/6.2)
    @State private var laneMask: UInt8 = 0     // §5b lap: held column keys (bit i = column i), PERFORM only
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    // §5b COLUMN-SUBSET LAP: the PERFORM multi-column hold reports the held-set bitmask here. Push it to
    // the engine (ephemeral, never persisted) and keep a copy for the key LOOP highlight. Cleared to 0
    // on release (the overlay reports empty) and on the EDIT switch (see the mode toggle).
    private func setLane(_ mask: UInt8) { laneMask = mask; au?.setLaneMask(mask) }

    // EDIT/PERFORM toggle. Leaving PERFORM ends any lap (belt-and-suspenders — the overlay also cancels).
    private func toggleMode() { editing.toggle(); if editing { setLane(0) } }

    // Tap a cell. EDIT: paint an empty cell / RECOLOUR an occupied one with the brush (delta §5).
    // PERFORM: flip an occupied cell to/from its ALT (B) state (engine-backed `alt`). Empty cells
    // ignore perform taps. (MUTE/BYP and the tap-action selector were removed pending the perform spec.)
    private func tapCell(_ col: Int, _ row: Int) {
        guard let au else { return }
        if editing {
            au.editScene { s in
                if var c = s.cells[col][row] { c.colourID = brush; s.cells[col][row] = c }
                else { s.cells[col][row] = Cell(colourID: brush) }
            }
            selCol = col; selRow = row
        } else {
            au.editScene { s in
                guard var c = s.cells[col][row] else { return }
                c.alt.toggle()
                s.cells[col][row] = c
            }
        }
        scene = au.uiScene()
    }

    // AUDITION (§6.4 / delta §5): press-hold a cell (stopped) → hear its processor alone. The held
    // target lives in a REFERENCE box mutated SILENTLY (never @State) so starting/stopping an audition
    // never re-renders the grid mid-press (which would tear down the long-press gesture). The deduped
    // poll above does the rest — when stopped the grid is quiescent, so the gesture is never disturbed.
    final class AuditionBox { var target: (col: Int, row: Int)? = nil }
    @State private var abox = AuditionBox()

    private func startAudition(_ col: Int, _ row: Int) {
        guard let au, scene.cells[col][row] != nil else { return }
        if abox.target?.col == col && abox.target?.row == row { return }
        abox.target = (col, row)
        au.setAudition(col: col, row: row)                           // kernel only — no @State, no re-render
    }
    private func endAudition() {
        guard au != nil, abox.target != nil else { return }
        abox.target = nil
        au?.clearAudition()
    }

    private func clearCell(_ col: Int, _ row: Int) {
        guard let au else { return }
        au.editScene { $0.cells[col][row] = nil }
        if selCol == col && selRow == row { selCol = -1; selRow = -1 }
        scene = au.uiScene()
    }

    // COPY = eyedropper: adopt this cell's Colour as the current brush.
    private func copyColour(_ col: Int, _ row: Int) {
        if let id = scene.cells[col][row]?.colourID { brush = id }
    }

    // ---- PROCESSOR box: edit the selected (brush) Colour ----
    private var brushIndex: Int { colourIDs.firstIndex(of: brush) ?? 0 }
    private var brushColour: Colour? { docColours.first { $0.colourID == brush } }

    private func editBrushColour(_ f: @escaping (inout Colour) -> Void) {
        guard let au else { return }
        au.editColour(brushIndex, f)
        docColours = au.uiColours()
    }
    private func setBrushTranspose(_ v: Int) { au?.setColourTranspose(brushIndex, v); docColours = au?.uiColours() ?? docColours }
    private func setBrushMorph(_ v: Double)  { au?.setColourMorph(brushIndex, v);     docColours = au?.uiColours() ?? docColours }
    private func setBrushType(_ t: ProcessorType) { au?.setColourType(brushIndex, t); docColours = au?.uiColours() ?? docColours }
    private func refreshTiming() { stepIndex = au?.uiStepRateIndex() ?? stepIndex; swing = au?.uiSwing() ?? swing }
    private var stepBeats: Double { StepRate.allCases[min(stepIndex, StepRate.allCases.count - 1)].beats }

    // ---- in-cell popover edits (target a specific col,row, not the selection) ----
    private func editCell(_ col: Int, _ row: Int, _ f: @escaping (inout Cell) -> Void) {
        guard let au else { return }
        au.editScene { s in if var c = s.cells[col][row] { f(&c); s.cells[col][row] = c } }
        scene = au.uiScene()
    }
    private func setInput(_ col: Int, _ row: Int, _ inputRow: Int?) { editCell(col, row) { $0.inputRow = inputRow } }
    private func cycleInChAt(_ col: Int, _ row: Int) { editCell(col, row) { $0.inputChannel = ($0.inputChannel + 1) % 17 } }
    private func toggleBusAt(_ col: Int, _ row: Int, _ b: Bus) {
        editCell(col, row) { if $0.buses.contains(b) { $0.buses.remove(b) } else { $0.buses.insert(b) } }
    }

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
    // §6a CLAIM: tap an emitter's CLAIM radio → it becomes the sole claimant (releasing any prior);
    // tapping the current claimant clears the claim. Persisted (the AU toggles + rebuilds).
    private func setClaim(_ i: Int) {
        guard let au else { return }
        au.setClaim(i)
        claim = au.uiClaim()
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
                    // Shrink the grid cells to fit the height left after header + scene strip, so the
                    // strip is never clipped (degradation ladder: cells clamp at a legible floor).
                    let cellH = max(30, min(54, (geo.size.height - 150) / 8))
                    VStack(spacing: 8) {
                        header
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 4) { gridBlock(cellH); hint }
                            ScrollView(.vertical, showsIndicators: false) { desk }   // only PROCESSOR-tall content scrolls
                                .frame(width: 320)
                        }
                        sceneStrip
                    }
                    .padding(12)
                } else {
                    // Portrait (delta §6): grid on top, then the desk as a COMPACT BAND below —
                    // COLOUR · PROCESSOR · EMITTERS left-to-right (not a vertical stack), then the
                    // scene strip full-width. The band is fixed-height (only PROCESSOR scrolls,
                    // within itself); the GRID absorbs the remaining height so the band + strip are
                    // always visible without an outer scroll. Final sizing tuned on device.
                    let bandH: CGFloat = 210
                    let cellH = max(28, min(54, (geo.size.height - bandH - 210) / 8))
                    VStack(spacing: 8) {
                        header
                        gridBlock(cellH)
                        hint
                        deskBand(geo.size.width - 24, bandH)   // 24 = the .padding(12) on both sides
                        sceneStrip
                        devLoader
                    }
                    .padding(12)
                }
            }
        }
        .onReceive(timer) { _ in
            guard let au else { return }
            // Write @State ONLY when a DISPLAYED value changed — an unconditional write re-renders the
            // whole grid every 0.25s (which used to tear down in-progress press-holds). When STOPPED
            // nothing here changes, so the grid is quiescent; while PLAYING only the playhead fields move.
            let nd = au.kernelDiagnostics()
            if nd.playing != d.playing || nd.tempo != d.tempo || nd.pass != d.pass
                || (nd.playing && (nd.beat != d.beat || nd.effColumn != d.effColumn)) { d = nd }
            let nb = au.uiBusChannels();   if nb != busChannels { busChannels = nb }
            let be = au.uiBusEnabled();    if be != busEnabled { busEnabled = be }
            let cl = au.uiClaim();         if cl != claim { claim = cl }
            // §6a metering: drain the per-emitter event feed and latch peaks; the meter view decays them.
            let act = au.pollEmitterActivity()
            for i in 0..<4 where i < act.events.count && act.events[i] > 0 {
                emitPeak[i] = Double(act.peak[i]) / 127.0; emitPeakAt[i] = Date()
            }
            let nc = au.uiColours();       if nc != docColours { docColours = nc }
            let ns = au.uiScene();         if ns != scene { scene = ns }
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
                   onToggleMode: toggleMode)
    }

    private func gridBlock(_ cellHeight: CGFloat) -> some View {
        GridView(scene: scene, colours: docColours, playColumn: d.effColumn, playing: d.playing,
                 beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                 cellHeight: cellHeight, editing: editing,
                 selCol: selCol, selRow: selRow, onTap: tapCell,
                 onSetInput: setInput, onCycleInCh: cycleInChAt, onToggleBus: toggleBusAt,
                 onClear: clearCell, onCopyColour: copyColour,
                 onAuditionStart: startAudition, onAuditionEnd: endAudition,
                 laneMask: laneMask, onLaneMask: setLane)
    }

    private var hint: some View {
        Text(editing
             ? "EDIT · TAP → paint \(brush.uppercased()) · header → FROM · A–D → OUT · HOLD → audition (stopped) / menu"
             : "PERFORM · TAP cell → ALT flip · HOLD cell → audition (stopped) · HOLD column keys → lap")
            .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The DESK — three named boxes in order: COLOUR · PROCESSOR · EMITTERS (delta §6). Order is
    // preserved in both orientations; only the AXIS flips with the leftover rectangle. LANDSCAPE
    // (this VStack, in a right-hand column) stacks them top→bottom; PORTRAIT uses `deskBand` below.
    private var desk: some View {
        VStack(spacing: 8) {
            colourBox
            if let bc = brushColour {
                ProcessorBox(colour: bc, colourIndex: brushIndex,
                             onEdit: editBrushColour, onTranspose: setBrushTranspose, onMorph: setBrushMorph,
                             onSetType: setBrushType)
            }
            emittersBox
        }
    }

    // PORTRAIT desk (delta §6): a COMPACT BAND below the grid — the three named panels run
    // LEFT-TO-RIGHT, COLOUR · PROCESSOR · EMITTERS. Only PROCESSOR scrolls, within its own fixed
    // frame (§6: "only PROCESSOR may scroll, content-sized up to a ceiling"); COLOUR and EMITTERS
    // sit at the top of their slots. PROCESSOR gets the widest share — it carries the 6-wide RATE
    // row — matching the ~320pt it enjoys in the landscape column.
    private func deskBand(_ width: CGFloat, _ height: CGFloat) -> some View {
        let gap: CGFloat = 8
        let avail = max(0, width - gap * 2)
        return HStack(alignment: .top, spacing: gap) {
            colourBox.frame(width: avail * 0.30)
            Group {
                if let bc = brushColour {
                    ScrollView(.vertical, showsIndicators: false) {
                        ProcessorBox(colour: bc, colourIndex: brushIndex,
                                     onEdit: editBrushColour, onTranspose: setBrushTranspose, onMorph: setBrushMorph,
                                     onSetType: setBrushType)
                    }
                }
            }
            .frame(width: avail * 0.44, height: height)
            emittersBox.frame(width: avail * 0.26)
        }
    }

    private var emittersBox: some View {
        OutputsView(busEnabled: busEnabled, busChannels: busChannels, editing: editing,
                    emitPeak: emitPeak, emitPeakAt: emitPeakAt, claim: claim,
                    onToggle: toggleEmitter, onSetChannel: setEmitterChannel,
                    onVelOverride: setVelOverride, onClaim: setClaim)
            .padding(8)
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
                        beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing) { brush = $0 }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

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

    private func row(_ label: String, _ main: String, _ sub: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).frame(width: 110, alignment: .leading)
            Text(main).font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
            Text(sub).font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(red: 0.15, green: 0.88, blue: 0.94).opacity(0.8))
            Spacer()
        }
    }
}

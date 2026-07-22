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
    @State private var docColours: [Colour] = []
    @State private var stepIndex = 2
    @State private var swing = 50
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    // Tap a cell BODY: paint an empty cell with the brush, or RECOLOUR an occupied one to the brush
    // (delta §5: tap body = apply the selected Colour — the mockup's stand-in for palette drag-drop).
    // FROM/OUT are the header/emitter popovers; CLEAR/COPY are the long-press cell menu.
    private func tapCell(_ col: Int, _ row: Int) {
        guard let au else { return }
        au.editScene { s in
            if var c = s.cells[col][row] { c.colourID = brush; s.cells[col][row] = c }   // recolour
            else { s.cells[col][row] = Cell(colourID: brush) }                            // paint
        }
        selCol = col; selRow = row
        scene = au.uiScene()
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
    private func refreshTiming() { stepIndex = au?.uiStepRateIndex() ?? stepIndex; swing = au?.uiSwing() ?? swing }

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

    // OUTPUTS: bump bus i's stamp channel 1…16 → wraps to 1.
    private func bumpBusChannel(_ i: Int) {
        guard let au else { return }
        au.editDocument { d in
            while d.busChannels.count < 4 { d.busChannels.append(d.busChannels.count + 1) }
            d.busChannels[i] = d.busChannels[i] % 16 + 1
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
                    VStack(spacing: 8) {
                        header
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 4) { gridBlock; hint }
                            ScrollView(.vertical, showsIndicators: false) { desk }   // only PROCESSOR-tall content scrolls
                                .frame(width: 320)
                        }
                        sceneStrip
                    }
                    .padding(12)
                } else {
                    ScrollView {
                        VStack(spacing: 8) { header; gridBlock; hint; desk; sceneStrip; devLoader }
                            .padding(12)
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            guard let au else { return }
            d = au.kernelDiagnostics()          // grid needs effColumn / playing
            busChannels = au.uiBusChannels()
            docColours = au.uiColours()
            scene = au.uiScene()
            stepIndex = au.uiStepRateIndex()
            swing = au.uiSwing()
        }
    }

    // MARK: - layout pieces

    private var header: some View {
        HeaderView(stepIndex: stepIndex, swing: swing, playing: d.playing, pass: d.pass,
                   beat: d.beat, tempo: d.tempo, build: Self.buildStamp,
                   onStep: { au?.setStepRateIndex($0); refreshTiming() },
                   onSwing: { au?.setSwing($0); refreshTiming() })
    }

    private var gridBlock: some View {
        GridView(scene: scene, colours: docColours, playColumn: d.effColumn, playing: d.playing,
                 beat: d.beat, tempo: d.tempo, stepBeats: StepRate.allCases[min(stepIndex, StepRate.allCases.count - 1)].beats,
                 selCol: selCol, selRow: selRow, onTap: tapCell,
                 onSetInput: setInput, onCycleInCh: cycleInChAt, onToggleBus: toggleBusAt,
                 onClear: clearCell, onCopyColour: copyColour)
    }

    private var hint: some View {
        Text("TAP cell → paint/recolour \(brush.uppercased()) · header → FROM · A–D → OUT · HOLD → clear/copy")
            .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The DESK — three named boxes in order: COLOUR · PROCESSOR · EMITTERS (delta §6).
    private var desk: some View {
        VStack(spacing: 8) {
            colourBox
            if let bc = brushColour {
                ProcessorBox(colour: bc, colourIndex: brushIndex,
                             onEdit: editBrushColour, onTranspose: setBrushTranspose, onMorph: setBrushMorph)
            }
            OutputsView(busChannels: busChannels, onBump: bumpBusChannel)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
        }
    }

    private var colourBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("COLOUR").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                if let c = colourColor(brush) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12) }
                Text(brush.uppercased()).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            }
            PaletteView(brush: brush) { brush = $0 }
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

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
    @State private var d = KernelDiag()
    @State private var treeMorphGold: Float = 0
    @State private var treeSwing: Float = 50
    @State private var loadedID = "—"
    @State private var scene = SceneState.empty()
    @State private var brush = "gold"        // the paint Colour (view-local; never in the document)
    @State private var selCol = -1
    @State private var selRow = -1
    @State private var emitActive = false
    @State private var lastEmitCount: UInt64 = 0
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var selectedCell: Cell? {
        guard selCol >= 0, selCol < scene.cells.count, selRow >= 0, selRow < scene.cells[selCol].count
        else { return nil }
        return scene.cells[selCol][selRow]
    }

    // Tap: paint an empty cell with the brush, or select an occupied one for wiring. Clear/repaint
    // are explicit in the editor strip.
    private func tapCell(_ col: Int, _ row: Int) {
        guard let au else { return }
        let empty = scene.cells[col][row] == nil
        if empty { au.editScene { $0.cells[col][row] = Cell(colourID: brush) } }   // default {A, ▾ off, +SRC off}
        selCol = col; selRow = row
        scene = au.uiScene()
    }

    private func editSelected(_ f: @escaping (inout Cell) -> Void) {
        guard let au, selCol >= 0 else { return }
        au.editScene { s in if var c = s.cells[selCol][selRow] { f(&c); s.cells[selCol][selRow] = c } }
        scene = au.uiScene()
    }

    private func paintSelected() {
        guard let au, selCol >= 0 else { return }
        au.editScene { s in
            if var c = s.cells[selCol][selRow] { c.colourID = brush; s.cells[selCol][selRow] = c }
            else { s.cells[selCol][selRow] = Cell(colourID: brush) }
        }
        scene = au.uiScene()
    }

    private func clearSelected() {
        guard let au, selCol >= 0 else { return }
        au.editScene { $0.cells[selCol][selRow] = nil }
        scene = au.uiScene()
    }

    /// Other occupied rows in the selected column — the legal reference targets (delta §1).
    private var occupiedRows: [Int] {
        guard selCol >= 0, selCol < scene.cells.count else { return [] }
        return (0..<8).filter { $0 != selRow && scene.cells[selCol][$0] != nil }
    }

    // FROM cycles: MIDI IN → each occupied row in order → back to MIDI IN.
    private func cycleFrom() {
        let targets = occupiedRows
        editSelected { c in
            if c.inputRow == nil { c.inputRow = targets.first }
            else if let cur = c.inputRow, let i = targets.firstIndex(of: cur), i + 1 < targets.count {
                c.inputRow = targets[i + 1]
            } else { c.inputRow = nil }
        }
    }

    // IN CH cycles: OMNI(0) → 1 → … → 16 → OMNI.
    private func cycleInCh() {
        editSelected { c in c.inputChannel = (c.inputChannel + 1) % 17 }
    }

    private var selected: TestSessions.Session? { TestSessions.all.first { $0.id == loadedID } }

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
        ZStack {
            Color(red: 0.066, green: 0.075, blue: 0.094).ignoresSafeArea()
            ScrollView {
              VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("MIDISPARK — GRID + DIAGNOSTICS")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(3)
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text("build \(Self.buildStamp)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                GridView(scene: scene, playColumn: d.effColumn, playing: d.playing,
                         selCol: selCol, selRow: selRow, onTap: tapCell)
                BusLanesView(scene: scene, active: emitActive)
                PaletteView(brush: brush) { brush = $0 }
                CellEditorStrip(cell: selectedCell, brush: brush, occupiedRows: occupiedRows,
                                onPaint: paintSelected, onClear: clearSelected,
                                onToggleBus: { b in editSelected { c in
                                    if c.buses.contains(b) { c.buses.remove(b) } else { c.buses.insert(b) } } },
                                onCycleFrom: cycleFrom, onCycleInCh: cycleInCh)
                Divider().background(Color.white.opacity(0.12)).padding(.vertical, 2)

                row("TRANSPORT", d.playing ? "PLAYING" : "stopped",
                    String(format: "beat %.2f · %.1f bpm", d.beat, d.tempo))
                row("RENDER", "\(d.renderCount) callbacks", "snapshot gen \(d.snapshotGen)")
                row("COLUMN", "col \(d.effColumn) · pass \(d.pass)",
                    d.activeCellRow >= 0
                      ? "active cell row \(d.activeCellRow) · input \(d.activeCellParent < 0 ? "MIDI IN" : "row \(d.activeCellParent)")"
                      : "empty (rest)")
                row("VOICES", "\(d.activeVoiceCount) instances",
                    "\(d.distinctSounding) distinct on wire\(d.activeVoiceCount > d.distinctSounding ? " · collision refcounted" : "")")
                row("POOL", "\(d.poolCount) held notes", d.poolCount == 0 ? "→ hold a chord on the routed keyboard" : "")
                row("PARAM EVENTS", "\(d.paramEventCount) received",
                    d.lastParamAddr >= 0 ? String(format: "last: addr %d = %.3f", d.lastParamAddr, d.lastParamValue) : "none yet")
                row("TREE VALUES", String(format: "morph gold %.3f", treeMorphGold),
                    String(format: "swing %.1f", treeSwing))
                row("EFFECTIVE", String(format: "morph %.3f → rate %.4f beats", d.effMorphGold, d.effRateBeats),
                    String(format: "swing %.1f", d.effSwing))
                row("CC IN", "\(d.ccCount) messages",
                    d.ccCount > 0 ? String(format: "last: %02X %d %d (passed on A)", d.ccStatus, d.ccData1, d.ccData2) : "none yet")
                row("EMIT", "\(d.emitCount) notes",
                    d.emitCount > 0
                      ? String(format: "last: note %d · bus ch %d (stamped)", d.lastEmitNote, d.lastEmitChan + 1)
                      : "none yet")

                Text("If PARAM EVENTS and TREE both sit still while you move a mapped control, the mapping isn't reaching this instance — check AUM's control target.")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 4)

                Divider().background(Color.white.opacity(0.15)).padding(.vertical, 2)

                row("TEST SESSION", loadedID, selected?.title ?? "none loaded")
                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 6) {
                    ForEach(Array(TestSessions.all.enumerated()), id: \.offset) { _, s in
                        Button(s.id) { load(s) }
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(s.id == loadedID ? .black : .white.opacity(0.85))
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(s.id == loadedID
                                      ? Color(red: 0.15, green: 0.88, blue: 0.94)
                                      : Color.white.opacity(0.10)))
                    }
                  }
                }
                if let s = selected {
                    Text(s.expect)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Loading a session REPLACES the document (host automation state included). Only ARP is implemented — every other type behaves as identity for now.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
              }
              .padding(18)
              .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onReceive(timer) { _ in
            guard let au else { return }
            d = au.kernelDiagnostics()
            emitActive = d.emitCount != lastEmitCount   // MIDI flowed since last poll → light the lanes
            lastEmitCount = d.emitCount
            scene = au.uiScene()
            treeMorphGold = au.parameterTree?.parameter(withAddress: 200)?.value ?? 0
            treeSwing = au.parameterTree?.parameter(withAddress: 1)?.value ?? 50
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

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
    // delta §5 (a5): the CELL EDITOR — target cell (-1 = closed), pending (empty, ghosted, uncommitted),
    // the session template = clipboard (one stamp object), and STAMP MODE ("COPY TO CELLS…").
    @State private var editorCol = -1
    @State private var editorRow = -1
    @State private var editorPending = false
    @State private var template: StampConfig? = nil
    @State private var stampMode = false
    @State private var altTargeting = false     // delta §9 item 5: the desk ALT box is picking a partner Colour
    // Cell-edit STAGING (user 2026-07-25): long-press a Colour → the receivers/emitters panels configure a
    // PENDING cell (input source + output buses). `stagedConfig` is ephemeral and RECALLED across enter/exit;
    // only the colour is set fresh by whichever chip is long-pressed. The drag-to-grid + live preview is
    // DEFERRED to the design spec — this scaffold is EDIT-only panel staging.
    @State private var staging = false
    @State private var stagedConfig = StampConfig(colourID: "gold")
    @State private var holdLatch = false             // delta §5c: HOLD — the sustain pedal for gestures (PERFORM)
    // §5 palette-to-grid drag: the grid's captured global frame, the in-flight chip drag, and the set of
    // provisional (palette-created, unreviewed) cells shown FADED until first opened in the editor.
    @State private var gridFrame: CGRect = .zero
    @State private var paletteDragColour: String? = nil
    @State private var paletteDragPoint: CGPoint? = nil
    @State private var fadedCells: Set<GridView.GridPos> = []
    @State private var emitPeak: [Double] = [0, 0, 0, 0]               // §6a meter: latched peak (0–1) per emitter
    @State private var emitPeakAt: [Date] = Array(repeating: .distantPast, count: 4)   // when each peak latched (for decay)
    @State private var receiverPeak: [Double] = [0, 0, 0, 0]           // §9 item 11 input meter: latched peak per receiver
    @State private var receiverPeakAt: [Date] = Array(repeating: .distantPast, count: 4)
    @State private var docColours: [Colour] = []
    @State private var receivers: [Receiver] = []                     // delta §9 item 11: the RECEIVERS panel
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
    private func toggleMode() { editing.toggle(); if editing { setLane(0); setHold(false) } else { staging = false } }   // §5c: HOLD PERFORM-only; staging EDIT-only

    // Cell-edit STAGING (user 2026-07-25) — long-press a Colour opens the staging mode; the receivers/
    // emitters panels reconfigure `stagedConfig` (input source + output buses). Ephemeral, recalled.
    private func enterStaging(_ id: String) {
        guard editing else { return }
        stagedConfig.colourID = id; brush = id      // set the staged colour + reflect it in the desk
        stampMode = false; editorClose()            // staging owns the panels — clear conflicting modes
        staging = true
    }
    private func setStagedReceiver(_ i: Int) { stagedConfig.inputRow = nil; stagedConfig.inputReceiver = max(0, min(3, i)) }
    private func pickStagedRow() { stagedConfig.inputRow = stagedConfig.inputRow ?? 0 }   // select FROM ROW (default row 1)
    private func stepStagedRow(_ delta: Int) {
        let cur = stagedConfig.inputRow ?? 0
        stagedConfig.inputRow = ((cur + delta) % 8 + 8) % 8
    }
    private func toggleStagedBus(_ i: Int) {
        let bus = Bus.allCases[i]
        if stagedConfig.buses.contains(bus) { stagedConfig.buses.remove(bus) } else { stagedConfig.buses.insert(bus) }
    }

    // Tap a cell. EDIT: paint an empty cell / RECOLOUR an occupied one with the brush (delta §5).
    // PERFORM: flip an occupied cell to/from its ALT (B) state (engine-backed `alt`). Empty cells
    // ignore perform taps. (MUTE/BYP and the tap-action selector were removed pending the perform spec.)
    private func tapCell(_ col: Int, _ row: Int) {
        guard let au else { return }
        if editing {
            if stampMode {                                 // delta §5 STAMP MODE: apply the stamp, no editor
                au.editScene { $0.cells[col][row] = currentTemplate.makeCell() }
                fadedCells.remove(GridView.GridPos(col: col, row: row))   // a deliberate stamp is a committed change → un-fade
                selCol = col; selRow = row; scene = au.uiScene(); docColours = au.uiColours()
            } else {                                       // open / RETARGET the inspector on this cell
                // Empty-cell taps are INERT in EDIT (user 2026-07-25): the editor is for OCCUPIED cells
                // only; empties are populated by DRAG (palette-to-grid or relocation), never by tap.
                guard scene.cells[col][row] != nil else { selCol = col; selRow = row; return }
                editorCol = col; editorRow = row          // opening does NOT un-fade (un-fade rule 2026-07-24)
                editorPending = false
                selCol = col; selRow = row
            }
        } else {
            au.editScene(record: false) { s in            // a6: PERFORM flips are OUT of undo scope (lean)
                guard var c = s.cells[col][row] else { return }
                c.alt.toggle()
                s.cells[col][row] = c
            }
            scene = au.uiScene()
        }
    }

    // MARK: - Cell editor (delta §5) — commit-on-first-interaction, inspector retarget, template/stamp

    private var currentTemplate: StampConfig { template ?? .bootstrap(colourID: brush) }

    /// Apply an edit to the target cell. A PENDING (empty) cell is CREATED from the template on this first
    /// interaction; an occupied cell is mutated in place. Committing also updates the template + desk brush.
    private func editorApply(_ f: (inout Cell) -> Void) {
        guard let au, editorCol >= 0 else { return }
        if scene.cells[editorCol][editorRow] == nil {
            var c = currentTemplate.makeCell(); f(&c)
            au.editScene { $0.cells[editorCol][editorRow] = c }
            editorPending = false
        } else {
            au.editScene { s in if var c = s.cells[editorCol][editorRow] { f(&c); s.cells[editorCol][editorRow] = c } }
        }
        scene = au.uiScene(); docColours = au.uiColours()
        fadedCells.remove(GridView.GridPos(col: editorCol, row: editorRow))   // un-fade on FIRST COMMITTED CHANGE (2026-07-24)
        if let c = scene.cells[editorCol][editorRow] { template = .from(c); brush = c.colourID }   // commit ⇒ template + desk
    }

    private func editorClear() {
        guard let au, editorCol >= 0 else { return }
        au.editScene { $0.cells[editorCol][editorRow] = nil }
        scene = au.uiScene(); editorClose()                 // cleared → empty; empties aren't editor targets, so dismiss (2026-07-25)
    }
    private func editorCopy() { if let c = scene.cells[editorCol][editorRow] { template = .from(c) } }
    private func editorCopyToCells() {                      // enter STAMP MODE, close the editor
        if let c = scene.cells[editorCol][editorRow] { template = .from(c) }
        stampMode = true; editorCol = -1
    }
    private func editorPasteColour()  { editorApply { $0.colourID = currentTemplate.colourID } }
    private func editorPasteRouting() { editorApply { $0.inputRow = currentTemplate.inputRow
                                                      $0.inputReceiver = currentTemplate.inputReceiver
                                                      $0.buses = currentTemplate.buses } }
    private func editorClose() { editorCol = -1; editorPending = false }

    // INPUT radio helpers: which rows are occupied (dim) and which are blocked (self + anti-2-cycle).
    private func occupiedRows(_ col: Int) -> Set<Int> {
        Set((0..<8).filter { scene.cells[col][$0] != nil })
    }
    private func blockedRows(_ col: Int, _ thisRow: Int) -> Set<Int> {
        var s: Set<Int> = [thisRow]                         // self-reference unexpressible
        for r in 0..<8 where scene.cells[col][r]?.inputRow == thisRow { s.insert(r) }   // direct 2-cycle guard
        return s
    }

    @ViewBuilder private var cellEditorCard: some View {
        if editorCol >= 0, editorCol < 8, editorRow < 8 {
            CellEditorView(
                col: editorCol, row: editorRow,
                cell: scene.cells[editorCol][editorRow],
                pending: editorPending,
                template: currentTemplate,
                colours: docColours,
                receivers: au?.uiReceivers() ?? [],
                occupiedRows: occupiedRows(editorCol),
                blockedRows: blockedRows(editorCol, editorRow),
                hasClipboard: template != nil,
                onColour: { id in editorApply { $0.colourID = id } },
                onInput: { rec, row in editorApply { $0.inputRow = row; if let r = rec { $0.inputReceiver = r } } },
                onToggleEmitter: { b in editorApply { if $0.buses.contains(b) { $0.buses.remove(b) } else { $0.buses.insert(b) } } },
                onClear: editorClear, onCopy: editorCopy, onCopyToCells: editorCopyToCells,
                onPasteColour: editorPasteColour, onPasteRouting: editorPasteRouting, onClose: editorClose)
        }
    }

    // delta §5 STAMP MODE: the non-negotiable banner. (Per-cell overwrite tint is a follow-up.)
    private var stampBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.on.square").font(.system(size: 11, weight: .heavy))
            Text("STAMPING — tap cells to apply").font(.system(size: 10, weight: .heavy, design: .monospaced))
            Spacer()
            Text("DONE").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.35)))
                .contentShape(Rectangle()).onTapGesture { stampMode = false }
        }
        .foregroundColor(.black)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color(red: 0.98, green: 0.72, blue: 0.12))
    }

    // Cell-edit STAGING banner (user 2026-07-25) — the mode indicator + DONE exit. Cyan to match the
    // marching-ants outline on the repurposed panels. (Drag-to-grid hand-off is deferred to the spec.)
    private var stagingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.dashed").font(.system(size: 11, weight: .heavy))
            if let c = colourColor(brush) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12) }
            Text("STAGING \(stagedConfig.colourID.uppercased()) — set input & emitters below")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
            Spacer()
            Text("DONE").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.35)))
                .contentShape(Rectangle()).onTapGesture { staging = false }
        }
        .foregroundColor(.black)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color(red: 0.15, green: 0.88, blue: 0.94))
    }

    // delta §5 drag-and-drop (EDIT): relocate a cell — move onto an empty slot, swap onto an occupied one.
    // A document edit (undoable via editScene); references move as-is (fields sacred).
    private func moveCell(_ from: (col: Int, row: Int), _ to: (col: Int, row: Int)) {
        guard let au else { return }
        au.editScene { $0.swapCells(from, to) }
        scene = au.uiScene()
    }

    // §5 palette-to-grid: map a GLOBAL drop point to a grid cell (cell height derived from the captured
    // grid frame), then RECOLOUR a populated cell or CREATE a faded one on empty. EDIT only.
    private func cellAtGlobal(_ p: CGPoint) -> GridView.GridPos? {
        guard gridFrame.width > 0, gridFrame.height > 0 else { return nil }
        let local = CGPoint(x: p.x - gridFrame.minX, y: p.y - gridFrame.minY)
        let cellH = (gridFrame.height - GridGeometry.headH - 8 * GridGeometry.vGap) / 8
        return GridGeometry.cell(atLocal: local, gridWidth: gridFrame.width, cellHeight: cellH)
            .map { GridView.GridPos(col: $0.col, row: $0.row) }
    }
    private func paletteDragChanged(_ id: String, _ point: CGPoint) {
        guard editing else { return }                 // EDIT-only
        paletteDragColour = id; paletteDragPoint = point
    }
    // Cell-edit staging: a chip drag is in flight while staging → the moving outline hands off to the grid.
    private var stagingDragging: Bool { staging && paletteDragPoint != nil }

    private func paletteDrop(_ id: String, _ point: CGPoint) {
        defer { paletteDragColour = nil; paletteDragPoint = nil }
        guard editing, let au, let pos = cellAtGlobal(point) else { return }
        if staging {                                  // STAGING drop: place the fully-configured pending cell
            var c = stagedConfig.makeCell(); c.colourID = id   // staged input + emitters, colour from the dragged chip
            au.editScene { $0.cells[pos.col][pos.row] = c }
            brush = id; scene = au.uiScene(); docColours = au.uiColours()
            staging = false; editing = false          // "once dropped, edit mode is off" → straight to PERFORM
            return
        }
        if scene.cells[pos.col][pos.row] != nil {     // POPULATED → recolour only (keep other settings)
            au.editScene { s in if var c = s.cells[pos.col][pos.row] { c.colourID = id; s.cells[pos.col][pos.row] = c } }
        } else {                                       // EMPTY → create from the template, shown FADED
            var c = currentTemplate.makeCell(); c.colourID = id
            au.editScene { $0.cells[pos.col][pos.row] = c }
            fadedCells.insert(pos)                     // provisional until the user opens the editor
        }
        brush = id; scene = au.uiScene(); docColours = au.uiColours()
    }

    // delta §5c: HOLD LATCH — while ON, releases latch instead of springing; HOLD-off is the synchronous
    // "drop" (every captured gesture releases at once). PERFORM-only; cleared on transport stop / EDIT.
    // v1 captures: §6a velocity overrides (in OutputsView) + audition (below). Lap + ON-HOLD deferred.
    private func setHold(_ on: Bool) {
        guard holdLatch != on else { return }
        holdLatch = on
        if !on {                                 // the drop: release the captures this layer owns
            au?.clearAudition(); abox.target = nil
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
        claim = au.uiClaim()
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

    // ---- PROCESSOR box: edit the selected (brush) Colour ----
    private var brushIndex: Int { colourIDs.firstIndex(of: brush) ?? 0 }
    private var brushColour: Colour? { docColours.first { $0.colourID == brush } }
    // delta §9 item 5: does the brush Colour's pairing GLIDE? (paired + same type = FULL). Gates the morph fader.
    private var brushGlides: Bool {
        guard let c = brushColour, let p = c.altColour, p >= 0, p < docColours.count else { return false }
        return docColours[p].type == c.type
    }

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
    // delta §9 item 11: RECEIVERS panel edits — channel filter / input mute / MPE-merge (undoable doc edits).
    private func setReceiverChannel(_ i: Int, _ ch: Int) { au?.setReceiverChannel(i, ch); receivers = au?.uiReceivers() ?? receivers }
    private func toggleReceiverMute(_ i: Int) { au?.toggleReceiverMute(i); receivers = au?.uiReceivers() ?? receivers }
    private func toggleReceiverMPE(_ i: Int) { au?.toggleReceiverMPE(i); receivers = au?.uiReceivers() ?? receivers }

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
                    // §6d landscape: grid on top with a grid-aligned RECEIVERS│EMITTERS band directly
                    // below it (50/50); the right quarter is the identity column (COLOUR→ALT→SELECTOR→
                    // SETTINGS). Cells clamp to leave room for the band + header + strip.
                    let cellH = max(26, min(50, (geo.size.height - 300) / 8))
                    VStack(spacing: 8) {
                        header
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 8) {
                                gridBlock(cellH)
                                HStack(spacing: 8) {                      // aligned to the grid's edges
                                    receiversBox.frame(maxWidth: .infinity)
                                    emittersBox.frame(maxWidth: .infinity)
                                }
                                hint
                            }
                            ScrollView(.vertical, showsIndicators: false) { identityColumn }.frame(width: 320)
                        }
                        sceneStrip
                    }
                    .padding(12)
                } else {
                    // §6d portrait: grid on top, then the 25/50/25 × 2 band (COLOUR/ALT · SELECTOR/
                    // SETTINGS · RECEIVERS/EMITTERS), then the scene strip + dev loader. The band is
                    // fixed-height (sized for the inline SETTINGS panel); the GRID absorbs the rest.
                    let bandH: CGFloat = 300
                    let cellH = max(26, min(54, (geo.size.height - bandH - 210) / 8))
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
                // delta §5: STAMP banner (top) + the floating CELL EDITOR card (top-leading, near the grid).
                // The card leaves most cells tappable so tapping another cell RETARGETS the open inspector.
                if stampMode { VStack(spacing: 0) { stampBanner; Spacer() } }
                if staging { VStack(spacing: 0) { stagingBanner; Spacer() } }
                if editorCol >= 0 { cellEditorCard.padding(.top, stampMode ? 92 : 52).padding(.leading, 14) }
                // §5 palette-to-grid: a chip ghost following the finger (positioned in the GeometryReader's
                // local space = the global drag point minus the reader's global origin).
                if let id = paletteDragColour, let pt = paletteDragPoint {
                    let o = geo.frame(in: .global).origin
                    RoundedRectangle(cornerRadius: 4).fill(colourColor(id) ?? .gray)
                        .frame(width: 44, height: 22).opacity(0.85)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: 1))
                        .position(x: pt.x - o.x, y: pt.y - o.y)
                        .allowsHitTesting(false)
                }
                // (§6c popup dropped — processor SETTINGS are inline in the §6d layout; the floating window
                //  survives only as the future EXTERNAL AUv3-view host, added when EXTERNAL Colours arrive.)
            }
        }
        .onReceive(timer) { _ in
            guard let au else { return }
            // Write @State ONLY when a DISPLAYED value changed — an unconditional write re-renders the
            // whole grid every 0.25s (which used to tear down in-progress press-holds). When STOPPED
            // nothing here changes, so the grid is quiescent; while PLAYING only the playhead fields move.
            let nd = au.kernelDiagnostics()
            if d.playing && !nd.playing && holdLatch { setHold(false) }   // §5c: transport stop = the drop
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
            let rin = au.pollReceiverActivity()      // §9 item 11: per-receiver INPUT metering
            for i in 0..<4 where i < rin.events.count && rin.events[i] > 0 {
                receiverPeak[i] = Double(rin.peak[i]) / 127.0; receiverPeakAt[i] = Date()
            }
            let nc = au.uiColours();       if nc != docColours { docColours = nc }
            let nr = au.uiReceivers();     if nr != receivers { receivers = nr }
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
                   onToggleMode: toggleMode,
                   canUndo: au?.uiCanUndo ?? false, canRedo: au?.uiCanRedo ?? false,
                   onUndo: undo, onRedo: redo,
                   holdLatch: holdLatch, onToggleHold: toggleHold)
    }

    private func gridBlock(_ cellHeight: CGFloat) -> some View {
        GridView(scene: scene, colours: docColours, playColumn: d.effColumn, playing: d.playing,
                 beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                 cellHeight: cellHeight, editing: editing,
                 selCol: selCol, selRow: selRow, onTap: tapCell,
                 onAuditionStart: startAudition, onAuditionEnd: endAudition,
                 laneMask: laneMask, onLaneMask: setLane, holdLatch: holdLatch, onMoveCell: moveCell,
                 faded: fadedCells, dropHoverCell: paletteDragPoint.flatMap(cellAtGlobal))
            .background(GeometryReader { g in Color.clear   // §5: capture the grid's global frame for palette drops
                .onAppear { gridFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { gridFrame = $0 } })
            .marchingAnts(stagingDragging, cornerRadius: 8)   // staging: the outline hands off to the grid mid-drag
    }

    private var hint: some View {
        Text(editing
             ? "EDIT · TAP cell → editor (input · colour · emitters) · HOLD cell → audition (stopped)"
             : "PERFORM · TAP cell → ALT flip · HOLD cell → audition (stopped) · HOLD column keys → lap · HOLD → latch")
            .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The DESK — three named boxes in order: COLOUR · PROCESSOR · EMITTERS (delta §6). Order is
    // preserved in both orientations; only the AXIS flips with the leftover rectangle. LANDSCAPE
    // (this VStack, in a right-hand column) stacks them top→bottom; PORTRAIT uses `deskBand` below.
    // §6d landscape identity column (right quarter): COLOUR → ALT → PROCESSOR SELECTOR → SETTINGS.
    // (RECEIVERS/EMITTERS move to the grid-aligned band under the grid in the layout increment.)
    private var identityColumn: some View {
        VStack(spacing: 8) {
            colourBox
            altPanel
            processorSelector
            processorSettings
        }
    }

    // PORTRAIT desk (delta §6): a COMPACT BAND below the grid — the three named panels run
    // LEFT-TO-RIGHT, COLOUR · PROCESSOR · EMITTERS. Only PROCESSOR scrolls, within its own fixed
    // frame (§6: "only PROCESSOR may scroll, content-sized up to a ceiling"); COLOUR and EMITTERS
    // sit at the top of their slots. PROCESSOR gets the widest share — it carries the 6-wide RATE
    // row — matching the ~320pt it enjoys in the landscape column.
    // §6d PORTRAIT band: three columns × two rows — LEFT 25% COLOUR/ALT · MIDDLE 50% SELECTOR/SETTINGS ·
    // RIGHT 25% RECEIVERS/EMITTERS. Per-orientation FIXED frames; the settings panel is sized for the
    // largest field set, so truncation dies by geometry.
    private func deskBand(_ width: CGFloat, _ height: CGFloat) -> some View {
        let gap: CGFloat = 8
        let avail = max(0, width - gap * 2)
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) { colourBox; altPanel }.frame(width: avail * 0.25)
            VStack(spacing: gap) { processorSelector; processorSettings }.frame(width: avail * 0.50)
            VStack(spacing: gap) { receiversBox; emittersBox }.frame(width: avail * 0.25)
        }
    }

    @ViewBuilder private var emittersBox: some View {
        Group {
            if staging {                              // cell-edit state: the pending cell's OUTPUT buses
                StagingEmittersView(buses: stagedConfig.buses, onToggle: toggleStagedBus)
            } else {
                OutputsView(busEnabled: busEnabled, busChannels: busChannels, editing: editing,
                            emitPeak: emitPeak, emitPeakAt: emitPeakAt, claim: claim, holdLatch: holdLatch,
                            onToggle: toggleEmitter, onSetChannel: setEmitterChannel,
                            onVelOverride: setVelOverride, onClaim: setClaim)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
        .marchingAnts(staging && !stagingDragging)   // hands off to the grid while a staging drag is in flight
    }

    @ViewBuilder private var receiversBox: some View {
        Group {
            if staging {                              // cell-edit state: the pending cell's INPUT source
                StagingInputView(inputRow: stagedConfig.inputRow, inputReceiver: stagedConfig.inputReceiver,
                                 receivers: receivers, onPickReceiver: setStagedReceiver,
                                 onPickRow: pickStagedRow, onStepRow: stepStagedRow)
            } else {
                ReceiversView(receivers: receivers, editing: editing, peak: receiverPeak, peakAt: receiverPeakAt,
                              onSetChannel: setReceiverChannel, onToggleMute: toggleReceiverMute, onToggleMPE: toggleReceiverMPE)
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
        .marchingAnts(staging && !stagingDragging)   // hands off to the grid while a staging drag is in flight
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
                        onPick: { pickPalette($0) }, onChipDrag: paletteDragChanged, onChipDrop: paletteDrop,
                        onLongPress: enterStaging, stagingID: staging ? stagedConfig.colourID : nil)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // §6d: ALT is now its own panel (delta §9 item 5) — the pairing home, a palette-cell-sized button
    // (empty dashed slot when unpaired) + the targeting hint. Tap → target; then pick a palette Colour.
    private var altPanel: some View {
        let partner = (brushIndex >= 0 && brushIndex < docColours.count) ? docColours[brushIndex].altColour : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("ALT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                Spacer()
                altBox(partner: partner)
            }
            if altTargeting {
                Text("pick a partner Colour (re-pick to unpair · tap ALT to cancel)")
                    .font(.system(size: 7, design: .monospaced)).foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.12))
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // §6d PROCESSOR SELECTOR / SETTINGS — the split inline panels (the §6c popup is gone).
    @ViewBuilder private var processorSelector: some View {
        if let bc = brushColour {
            ProcessorBox(colour: bc, colourIndex: brushIndex, mode: .selector, glides: brushGlides,
                         onEdit: editBrushColour, onTranspose: setBrushTranspose, onMorph: setBrushMorph, onSetType: setBrushType)
        }
    }
    @ViewBuilder private var processorSettings: some View {
        if let bc = brushColour {
            ProcessorBox(colour: bc, colourIndex: brushIndex, mode: .settings, glides: brushGlides,
                         onEdit: editBrushColour, onTranspose: setBrushTranspose, onMorph: setBrushMorph, onSetType: setBrushType)
        }
    }

    // delta §9 item 5: the ALT box beside the palette — shows the current Colour's PARTNER (or +). Tap to
    // enter targeting; then pick a palette Colour to pair (re-pick the current partner to unpair).
    private func altBox(partner: Int?) -> some View {
        HStack(spacing: 3) {
            Text("ALT").font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(altTargeting ? .black : .white.opacity(0.5))
            if let p = partner, p < colourHexes.count {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: colourHexes[p])).frame(width: 12, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.5), lineWidth: 1))
            } else {
                // empty slot waiting to be filled — a dashed outline (brighter while targeting)
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.15)).frame(width: 12, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(altTargeting ? Color.black.opacity(0.6) : Color.white.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1, dash: [2, 1.5])))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(altTargeting ? Color(red: 0.98, green: 0.72, blue: 0.12) : Color.white.opacity(0.08)))
        .contentShape(Rectangle()).onTapGesture { altTargeting.toggle() }
    }

    // Palette tap: normally selects the desk brush; while ALT-targeting it sets the brush Colour's partner
    // (re-picking the current partner unpairs; self-pick is ignored).
    private func pickPalette(_ id: String) {
        guard let bi = colourIDs.firstIndex(of: brush) else { return }
        if altTargeting {
            altTargeting = false
            guard let pi = colourIDs.firstIndex(of: id), pi != bi else { return }
            let current = (bi < docColours.count) ? docColours[bi].altColour : nil
            au?.editColour(bi) { $0.altColour = (current == pi ? nil : pi) }   // re-pick same ⇒ unpair
            docColours = au?.uiColours() ?? docColours
        } else {
            brush = id
        }
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

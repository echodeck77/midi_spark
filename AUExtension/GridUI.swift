//  GridUI.swift
//  MidiSpark — the 8×8 grid view (four-row cell) + palette + RECEIVERS/OUTPUTS panels + the CELL EDITOR.
//  Editing (delta §5 rev 2): in EDIT the whole pad is ONE tap target that opens the floating CELL EDITOR
//  (input · colour · emitters · actions); body long-press auditions (stopped); PERFORM tap flips ALT. The
//  old FROM/OUT popovers + tap-paint + hold-menu are retired (folded into the editor). Every edit goes
//  through MidiSparkAudioUnit.editScene/editDocument → scheduleRebuild. Tokens per docs/ui-port-guide.md.

import SwiftUI
import UIKit   // ColumnHoldOverlay: multi-touch column-key holds (§5b) need a UIView, not a SwiftUI gesture

// §4c INVISIBLE = FROZEN: set true at the root when the plugin view is hidden/backgrounded; every animated
// TimelineView ORs it into its `paused:`, so the whole canvas freezes (the render engine is untouched). One
// environment value → no parameter plumbing through the view tree.
private struct AnimationsPausedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var animationsPaused: Bool {
        get { self[AnimationsPausedKey.self] }
        set { self[AnimationsPausedKey.self] = newValue }
    }
}

extension Color {
    /// 0xRRGGBB → Color. Used for the 16 canonical Colour hexes (do not "harmonise" them, §ui-guide).
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - THE SEAL (derived cell face) — a 3×3-lattice route glyph. Geometry is pure (Derivations.sealHash/
// sealGeometry); this layer maps lattice nodes → the rect and draws the wire (arc/mitre corners), the coil,
// and the terminals (start dot + arrowhead). Same config ⇒ same seal (badge + edit page). Design INSTRUCTIONS §2–4.

/// The seal's rest ink — near-black, firm (design §3). Shared by the cell BADGE + the edit-page identity plate
/// (user: the edit seal must match the cells, black not white).
let sealInk = Color(.sRGB, red: 12.0 / 255, green: 12.0 / 255, blue: 16.0 / 255, opacity: 0.8)

/// Lay the seal into `size` by FITTING the route's bounding box to a padded rectangle (independent x/y scale),
/// so the glyph fills the full LENGTH + height regardless of where the route sits on the lattice — no more
/// hugging one side (user request). Returns the node points + a corner-arc radius from the tighter axis' node
/// spacing. Pad = padFraction of the shorter side; a zero-range axis (a straight run) centres on that axis.
func sealLayout(_ geo: SealGeometry, size: CGSize, padFraction: CGFloat) -> (pts: [CGPoint], arcRadius: CGFloat) {
    let pad = min(size.width, size.height) * padFraction
    let availW = size.width - 2 * pad, availH = size.height - 2 * pad
    let fit = sealFit(geo)                                   // pure bbox-fit fractions (Derivations, tested)
    let pts = fit.fractions.map { CGPoint(x: pad + CGFloat($0.x) * availW, y: pad + CGFloat($0.y) * availH) }
    let pitchX = fit.rangeX > 0 ? availW / CGFloat(fit.rangeX) : availW
    let pitchY = fit.rangeY > 0 ? availH / CGFloat(fit.rangeY) : availH
    return (pts, 0.45 * min(pitchX, pitchY))
}

/// The seal's node points inside `size` (arc-length source for the comet).
func sealNodePoints(_ geo: SealGeometry, size: CGSize, padFraction: CGFloat) -> [CGPoint] {
    sealLayout(geo, size: size, padFraction: padFraction).pts
}

/// Draw the seal into a GraphicsContext (design §2): the WIRE (quarter-arc iff flagged, else sharp mitre),
/// an optional COIL astride its node, and the filled TERMINALS (start dot + end arrowhead). `showLattice`
/// adds the nine faint lattice dots (edit page, §4). Pure of state — draws the same seal for the same geo.
func drawSeal(_ geo: SealGeometry, into ctx: GraphicsContext, size: CGSize, padFraction: CGFloat,
              stroke: CGFloat, ink: Color) {
    let (pts, radius) = sealLayout(geo, size: size, padFraction: padFraction)
    guard pts.count > 1 else { return }

    // the WIRE — quarter-arc (radius from the tighter axis) at flagged interior nodes, else a sharp mitre
    var wire = Path()
    wire.move(to: pts[0])
    for i in 1..<(pts.count - 1) {
        if geo.arcAtNode[i] { wire.addArc(tangent1End: pts[i], tangent2End: pts[i + 1], radius: radius) }
        else { wire.addLine(to: pts[i]) }
    }
    wire.addLine(to: pts[pts.count - 1])
    ctx.stroke(wire, with: .color(ink), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))

    // the COIL — one open 300° circle (§2), radius 2.1·stroke, astride the coil node
    if geo.coilNode >= 1 && geo.coilNode < pts.count {
        var coil = Path()
        coil.addArc(center: pts[geo.coilNode], radius: 2.1 * stroke,
                    startAngle: .radians(0.6), endAngle: .radians(0.6 + 1.66 * .pi), clockwise: false)
        ctx.stroke(coil, with: .color(ink), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
    }

    // TERMINALS — filled start dot (r 1.15·stroke) + end arrowhead (len 2.5·stroke, ±2.5-rad wings), §2
    let dotR = 1.15 * stroke
    ctx.fill(Path(ellipseIn: CGRect(x: pts[0].x - dotR, y: pts[0].y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(ink))
    let end = pts[pts.count - 1], prev = pts[pts.count - 2]
    let ang = atan2(end.y - prev.y, end.x - prev.x)
    let aLen = 2.5 * stroke, wing = 2.5
    var head = Path()
    head.move(to: end)
    head.addLine(to: CGPoint(x: end.x + aLen * cos(ang + wing), y: end.y + aLen * sin(ang + wing)))
    head.addLine(to: CGPoint(x: end.x + aLen * cos(ang - wing), y: end.y + aLen * sin(ang - wing)))
    head.closeSubpath()
    ctx.fill(head, with: .color(ink))
}

/// Canonical Colour hexes, in colourIDs / bank order (docs/ui-port-guide.md). Index = colour index.
let colourHexes: [UInt32] = [
    0xFFC53D, 0xFF7A1A, 0xFF4B33, 0xC2244B, 0xFF4D9E, 0xFFA8B8, 0xB44DFF, 0x7A3DF0,
    0x5566FF, 0x38A6FF, 0x25E0F0, 0x148F80, 0x7BF2CE, 0x2ECC5E, 0xC6F23D, 0xC9A227,
]
// delta §9 item 11: the four receivers' fixed "infrastructure family" hues (muted), shared by the
// RECEIVERS panel and the cells' band-as-deviation marker.
let receiverHues: [Color] = [Color(hex: 0x6B7A8F), Color(hex: 0x7E6B8F), Color(hex: 0x6B8F7E), Color(hex: 0x8F836B)]

// §5 drag-and-drop: the grid's fixed layout metrics + a point→cell map, SHARED by GridView (its own
// coordinate space) and the VC (mapping a cross-view palette drag by the grid's captured global frame).
enum GridGeometry {
    static let headH: CGFloat = 38      // the prominent column-key row (v57)
    static let vGap: CGFloat = 3
    /// Which cell contains a point in GRID-LOCAL coordinates (origin = the column-key row's top-left)?
    static func cell(atLocal p: CGPoint, gridWidth: CGFloat, cellHeight: CGFloat) -> (col: Int, row: Int)? {
        guard gridWidth > 0 else { return nil }
        let cellW = (gridWidth - CGFloat(7) * vGap) / 8
        let col = Int(p.x / (cellW + vGap))
        let y = p.y - (cellHeight + vGap)            // below the column-key row (now a cell's height)
        let row = Int(y / (cellHeight + vGap))
        guard col >= 0, col < 8, row >= 0, row < 8, y >= 0 else { return nil }
        return (col, row)
    }
}

func colourColor(_ id: String) -> Color? {
    colourIDs.firstIndex(of: id).map { Color(hex: colourHexes[$0]) }
}

private let accentCyan = Color(red: 0.15, green: 0.88, blue: 0.94)   // playhead / PERFORM accent

// v56 theme tokens (mockup `T`): cell recess, edges, dim ink.
private let cellBg = Color(hex: 0x0B0D11)
private let cellEdge = Color(hex: 0x20242D)
private let dimInk = Color(hex: 0x5C6472)

/// The 8×8 grid — v56 FOUR-ROW cell (delta §4): input header · type+params body · emitter strip;
/// empty cells show a row-number watermark. `scene.cells` is [column][row]. `colours` maps a cell's
/// colourID → its type/params for the body text.
struct GridView: View {
    @Environment(\.animationsPaused) private var animPaused
    let scene: SceneState
    let colours: [Colour]
    let playColumn: Int
    let playing: Bool
    var beat: Double = 0        // host beat position, polled ~4 Hz; extrapolated per-frame below
    var tempo: Double = 120
    var stepBeats: Double = 2   // beats per grid step (from the global STEP rate)
    var swing: Int = 50         // 50…75 — warps the sweep so it spans the real (swung) column window
    var cellHeight: CGFloat = 54   // set by the parent to fit the available height (landscape)
    var editing: Bool = true    // EDIT: pad tap → CELL EDITOR. PERFORM: pad tap → ALT flip. (Both = one target.)
    var selCol: Int = -1
    var selRow: Int = -1
    var onTap: ((Int, Int) -> Void)? = nil          // delta §5: whole-pad target → editor (EDIT, OCCUPIED cells only; empties inert)
    // AUDITION (§6.4 / delta §5): press-and-hold a cell (≈0.3s) → sound its processor alone while the
    // transport is stopped; release ends it. Fires in both modes; the engine only sounds it when stopped.
    var onAuditionStart: ((Int, Int) -> Void)? = nil
    var onAuditionEnd: (() -> Void)? = nil
    var onLongPressStageCell: ((Int, Int) -> Void)? = nil   // EDIT: long-press a populated cell → put it in cell-edit (+ armed for relocate)
    var laneMask: UInt8 = 0                          // §5b: held columns (bit i = column i) — for the LOOP highlight
    var onLaneMask: ((UInt8) -> Void)? = nil         // PERFORM: multi-column HOLD on the keys → held-set bitmask
    var onColumnKey: ((Int) -> Void)? = nil          // MODE ROW · EDIT page: TAP a column key → toggle it in the loop set
    var holdLatch: Bool = false                      // §5c: while ON, an audition release LATCHES (keeps droning)
    var onMoveCell: ((_ from: (col: Int, row: Int), _ to: (col: Int, row: Int)) -> Void)? = nil   // §5 drag-and-drop (EDIT)
    var moveMode: Bool = false                       // MODE ROW · MOVE: a plain drag (no long-press) relocates a cell
    var flagNoDest: Bool = true                      // show the "no emitter" red-dashed border (a PERFORM routing hint; off on the setup grid)
    var animateSelection: Bool = false               // MODE ROW: the SELECTED cells wear a marching black/white dashed border (setup grid)
    var showAddPlus: Bool = false                    // MODE ROW · ADD/EDIT with a selection: empty cells show a faint "+" (tap to add)
    var cellHitAt: [Date] = []                       // SEAL comet: per-cell last-strike time (index col*8+row)
    var cellHitVel: [Double] = []                    // SEAL comet: per-cell last-strike velocity (0–1)
    var cellSounding: [Bool] = []                    // SEAL comet: per-cell note-on/off gate (currently sounding)
    var cellReleasedAt: [Date] = []                  // SEAL comet: per-cell last release time (for the fade)
    var dropHoverCell: GridPos? = nil                // §5: the cell under a palette drag (highlight the drop target)
    var staging: Bool = false                        // cell-edit staging: EMPTY cells pulse a border to invite tap-to-place
    var stagingColor: Color = stagingCyan            // the staged Colour's own hue (the pulse colour)
    var stagedCells: Set<GridPos> = []               // cells placed this staging session: pulse colour↔black; gate the empty flash
    var hiddenPending: GridPos? = nil                // a just-hidden cell in its undo window: ring in its own colour, tap to restore
    var selection: Set<GridPos> = []                 // §11 SELECT: the built set — each member wears a ring
    var whiteBorder: Set<GridPos> = []               // §11 PLACE: cells placed this hold — a white "selected" border
    var twins: Set<GridPos> = []                     // CELL MACHINE: the pointed cell's TWINS (edit-together set) — dashed ring; non-twins dim
    var removeMarks: Set<GridPos> = []               // MODE ROW · CLEAR mode: cells marked for transactional removal — dashed red ring + ✕ + dim
    var ladderDim: Set<GridPos> = []                 // LADDER: dormant rungs — dimmed (present + visible, but silent)
    var ladderArmed: Set<GridPos> = []               // LADDER: armed rungs — blink until they commit at the column's next entry
    var ladderBlink = false                          // LADDER: the blink phase (beat-toggled by the parent)
    var verbInvite: Color? = nil                     // §11b a verb is held: the grid glows its hue (invite); nil = triggers
    var routeFoci: Set<GridPos> = []                 // §10 ROUTE mode: the cells being wired (solid amber ring)
    var routeIn: Set<GridPos> = []                   // §10 SRC candidates above (pulsing "SRC" label — tap = route-in)
    var routeOut: Set<GridPos> = []                  // §10 DEST candidates below (pulsing "DEST" label — tap = feed)
    var tapAltMask: UInt64 = 0                        // §9 item 1 ON TAP: ephemeral per-cell ALT flips (bit col*8+row)
    var tapMuteMask: UInt64 = 0                       // §9 item 1 ON TAP = MUTE: ephemeral per-cell mute (dims the cell)
    // STROKES: while a verb is held, a DRAG applies the verb once per NEWLY-ENTERED cell (PLACE paints a run —
    // one per column via ⑥ — DELETE sweeps, SELECT lassos). The whole swathe is ONE undo step.
    var strokeActive: Bool = false                   // a verb is held → drags stroke instead of doing nothing
    var onStroke: ((Int, Int) -> Void)? = nil        // called once per newly-entered cell during a stroke
    var onStrokeEnd: (() -> Void)? = nil             // drag ended → commit the swathe (close its one undo)
    @State private var breathe = false     // shared ALT-ring breathe phase (§6.5); decorative, not beat-locked
    @State private var strokeVisited: Set<GridPos> = []   // cells already painted THIS stroke (fire once each)
    @State private var lastBeat: Double = 0
    @State private var lastBeatAt = Date()
    // §5 drag-and-drop (EDIT): the cell being dragged + the hovered drop target; the grid's measured size
    // maps a drag location (in the "grid" coordinate space) to a cell.
    struct GridPos: Hashable { let col: Int; let row: Int }
    @State private var dragFrom: GridPos? = nil
    @State private var dragTo: GridPos? = nil
    @State private var stagePressed = false          // this long-press already fired staging (once per gesture)
    @State private var gridSize: CGSize = .zero
    // STROKES: a grid-wide drag that, while a verb is held, applies the verb once per newly-entered cell.
    // minimumDistance 10 keeps a plain tap flowing to onTapGesture (only a real drag strokes); it is a
    // simultaneousGesture so it never steals the per-cell tap / audition long-press. Inert when no verb held.
    private var strokeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("grid"))
            .onChanged { v in
                guard strokeActive, let p = cellAt(location: v.location), !strokeVisited.contains(p) else { return }
                strokeVisited.insert(p)
                onStroke?(p.col, p.row)
            }
            .onEnded { _ in
                let painted = strokeActive && !strokeVisited.isEmpty
                strokeVisited.removeAll()
                if painted { onStrokeEnd?() }
            }
    }

    private func cellAt(location p: CGPoint) -> GridPos? {
        GridGeometry.cell(atLocal: p, gridWidth: gridSize.width, cellHeight: cellHeight).map { GridPos(col: $0.col, row: $0.row) }
    }

    /// The beat position NOW, extrapolated from the last poll (one-clock rule, §4): the UI polls at
    /// ~4 Hz; between polls we advance the last value by elapsed·tempo so the playhead glides.
    private func liveBeat(_ now: Date) -> Double {
        playing ? lastBeat + now.timeIntervalSince(lastBeatAt) * tempo / 60.0 : lastBeat
    }

    // Layout constants — shared by cellView and the mutation-line overlay so they never drift.
    private static let vGap = GridGeometry.vGap
    private static let headH = GridGeometry.headH     // the prominent column-key row (v57)

    var body: some View {
        VStack(spacing: Self.vGap) {
            columnKeys                                   // v57 prominent column keys + sweeping arrow
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: Self.vGap) {
                    ForEach(0..<8, id: \.self) { col in cellView(col: col, row: row) }
                }
            }
        }
        .overlay { mutationLines }                        // per-cell falling lines in the active column
        .coordinateSpace(name: "grid")                   // §5 drag-and-drop: maps a drag location → a cell
        .simultaneousGesture(strokeGesture)              // STROKES: drag-paint while a verb is held
        .background(GeometryReader { g in Color.clear.onAppear { gridSize = g.size }.onChange(of: g.size) { gridSize = $0 } })
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { breathe = true } }
        .onChange(of: beat) { newBeat in lastBeat = newBeat; lastBeatAt = Date() }
    }

    // v57 PROMINENT COLUMN KEYS — a numbered 40px key per column; the active one lights while playing.
    // The master playhead arrow sweeps across the top of this row (delta §4, one-clock). The column-hold
    // LAP gesture (§5b) will attach here later; the tap-to-mute interaction was removed pending the spec.
    private var columnKeys: some View {
        HStack(spacing: Self.vGap) {
            ForEach(0..<8, id: \.self) { col in
                let active = playing && col == playColumn
                let held = (laneMask & (1 << UInt8(col))) != 0     // §5b lap: this column is in the held (loop) set
                Image(systemName: held ? "repeat" : "chevron.down")   // column key — LOOP glyph when in the set, else a down chevron
                    .font(.system(size: held ? 12 : 15, weight: .heavy))
                    .foregroundColor(active ? .black : (held ? accentCyan : .white.opacity(0.45)))
                    .frame(maxWidth: .infinity).frame(height: cellHeight)   // key row = a cell's height (user 2026-07-26)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(active ? accentCyan : Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6)                 // LOOP state = held key ring (§5b)
                        .stroke(held ? accentCyan : .clear, lineWidth: 2).padding(1))
                    .contentShape(Rectangle())
                    .onTapGesture { onColumnKey?(col) }             // MODE ROW · EDIT page: tap toggles this column in the loop
            }
        }
        .overlay { masterArrow }
        // PERFORM: a transparent multi-touch layer over the key row → held-column bitmask (the LAP). ALWAYS LATCHED
        // now (user 2026-08-03): a tap toggles a column into the loop set and it PERSISTS (like Hold was on), showing
        // the "repeat" LOOP glyph — the same tap-toggle behaviour + icon as the EDIT page's column keys.
        .overlay { if !editing, let cb = onLaneMask { ColumnHoldOverlay(gap: Self.vGap, latched: true, onChange: cb) } }
    }

    // Master playhead (delta §4): a glowing down-arrow sweeping left→right across the 8 columns over
    // one cycle, snapping at the loop. Pure function of the extrapolated beat — no view owns a clock.
    private var masterArrow: some View {
        GeometryReader { geo in
            let cycle = max(0.001, stepBeats * Double(Snap.cols))
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing || animPaused)) { tl in
                let b = liveBeat(tl.date)
                let frac = (b.truncatingRemainder(dividingBy: cycle) / cycle + 1).truncatingRemainder(dividingBy: 1)
                Text("▼")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.9), radius: 4)
                    .position(x: geo.size.width * frac, y: 5)
                    .opacity(playing ? 0.95 : 0)
            }
        }
        .allowsHitTesting(false)
    }

    // Per-cell MUTATION line (delta §4): in the ACTIVE column, one white horizontal line falls
    // through each WORKING cell over its step (the "this machine is running" cue). Faint & glowless
    // when bypassed (identity); absent when muted. One overlay for all — geometry derived from the
    // shared layout constants; hit-testing off so cell taps pass through.
    private var mutationLines: some View {
        GeometryReader { geo in
            let cellW = (geo.size.width - 7 * Self.vGap) / 8
            let colX = CGFloat(playColumn) * (cellW + Self.vGap) + cellW / 2
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing || animPaused)) { tl in
                // within-column fraction (0 at column entry → 1 at exit), swing-aware so it spans the
                // real (swung) column window rather than finishing early and wrapping.
                let f = columnSweepFraction(realBeat: liveBeat(tl.date), stepBeats: stepBeats, swing: swing)
                ForEach(0..<8, id: \.self) { r in
                    if playing, let c = cellAt(playColumn, r), !c.muted, !ladderDim.contains(GridPos(col: playColumn, row: r)) {   // LADDER: only the active rung
                        let faint = c.bypassed
                        Rectangle()
                            .fill(Color.white.opacity(faint ? 0.4 : 0.92))
                            .frame(width: cellW - 4, height: 2)
                            .shadow(color: faint ? .clear : Color.white.opacity(0.8), radius: faint ? 0 : 4)
                            .position(x: colX, y: (cellHeight + Self.vGap) + CGFloat(r) * (cellHeight + Self.vGap) + f * cellHeight)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // §10 a routing candidate wears a pulsing SRC/DEST chip — NO outline (must not read as "selected"). The
    // pulse rides the shared `breathe` phase (same cadence as the ALT ring + the strip ROUTE faces).
    private func routeLabel(_ text: String, _ hue: Color) -> some View {
        Text(text).font(.system(size: 18, weight: .heavy, design: .monospaced))          // SRC/DEST — prominent; NO outline
            .foregroundColor(hue).minimumScaleFactor(0.5).lineLimit(1)
            .shadow(color: .black.opacity(0.9), radius: 2)                                // legible while the body pulses beneath
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func cellView(col: Int, row: Int) -> some View {
        let raw = (col < scene.cells.count && row < scene.cells[col].count) ? scene.cells[col][row] : nil
        let cell = raw                                 // a MUTED cell renders DIMMED (not hidden) — visible + tappable to unmute
        let isSel = col == selCol && row == selRow
        let inActiveCol = playing && col == playColumn
        let parent = parentOf(col, row)
        let colour = cell.flatMap { c in colourColor(c.colourID) }
        let noDest = flagNoDest && (cell.map { $0.buses.isEmpty && !isTapped(col, row) } ?? false)
        let tapMutedHere = cell != nil && (tapMuteMask >> UInt64(col * 8 + row)) & 1 == 1   // §9 ON TAP = MUTE (momentary)
        let isRouteCand = routeIn.contains(GridPos(col: col, row: row)) || routeOut.contains(GridPos(col: col, row: row))

        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(colour ?? cellBg)

            if isRouteCand {
                EmptyView()                                 // §10 a routing candidate hides ALL content — only its colour, pulse + IN/OUT label show
            } else if let cell {
                // THE SEAL (which) — the derived glyph fills the WHOLE cell face now (user 2026-08-03: the bus dots
                // are dropped). An engraved plate carries the seal; a COMET runs the wire while the cell fires MIDI (§5).
                let geo = sealGeometry(sealHash(cell, colours: colours))
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.14))                       // engraved plate
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                    Canvas { ctx, size in drawSeal(geo, into: ctx, size: size, padFraction: 0.16, stroke: 2.4, ink: sealInk) }
                    sealComet(geo, col * 8 + row)
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showAddPlus {          // MODE ROW · ADD/EDIT with a selection: a faint "+" invites adding this empty cell
                Image(systemName: "plus").font(.system(size: 18, weight: .heavy)).foregroundColor(.white.opacity(0.22))
            }   // §quieting (2026-08-02): otherwise an empty cell is NEAR-SILENT — bare faint rect
        }
        .opacity(removeMarks.contains(GridPos(col: col, row: row)) ? 0.3          // MODE ROW · CLEAR: a marked cell recedes
                 : ladderArmed.contains(GridPos(col: col, row: row)) ? (ladderBlink ? 1.0 : 0.4)   // LADDER: an armed rung BLINKS
                 : ladderDim.contains(GridPos(col: col, row: row)) ? 0.28         // LADDER: a dormant rung dims (silent, still visible)
                 : (tapMutedHere || raw?.muted == true) ? 0.28 : 1)               // muted dims; otherwise cells stay full (twins advertise by PULSING, not by others dimming)
        .overlay {                                          // MODE ROW · CLEAR: a marked cell wears a dashed red ring + an ✕
            if removeMarks.contains(GridPos(col: col, row: row)) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(red: 0.95, green: 0.25, blue: 0.28), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    Image(systemName: "xmark").font(.system(size: 16, weight: .black)).foregroundColor(Color(red: 0.95, green: 0.35, blue: 0.38))
                }.allowsHitTesting(false)
            }
        }
        .overlay {                                          // MODE ROW: a MATCHING (twin, unselected) cell PULSES between its OWN
            let pos = GridPos(col: col, row: row)            // colour and BLACK (user 2026-08-03) — advertise, tap to add.
            if twins.contains(pos) && !isSel && !whiteBorder.contains(pos) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
                    let f = stagingPulseFraction(tl.date, period: 1.0)                          // 0→1→0
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.88 * f))       // fade toward black, revealing the cell's own colour
                }
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity).frame(height: cellHeight)
        .overlay {                                          // A2 COMPASS TINT — a slim parent-hue sliver on the parent-facing edge (row-fed cells only)
            if parent >= 0, let pc = cellAt(col, parent).flatMap({ colourColor($0.colourID) }) {
                VStack(spacing: 0) {
                    if parent < row { Rectangle().fill(pc.opacity(0.85)).frame(height: 3) }   // parent above → top edge
                    Spacer(minLength: 0)
                    if parent > row { Rectangle().fill(pc.opacity(0.85)).frame(height: 3) }   // parent below → bottom edge
                }
                .clipShape(RoundedRectangle(cornerRadius: 8)).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {              // A3 TRIGGER GLYPH — deviation-shown (default = nothing)
            if !isRouteCand, let cc = cell, let cl = colours.first(where: { $0.colourID == cc.colourID }), let mark = triggerMark(cl.onResolved) {
                Image(systemName: mark.glyph).font(.system(size: 7, weight: .heavy)).foregroundColor(.black.opacity(0.72))
                    .shadow(color: .white.opacity(0.5), radius: 0.6)   // keyline for dark hues
                    .padding(1.5)
                    .overlay { if mark.ring { Circle().stroke(.black.opacity(0.72), lineWidth: 1) } }
                    .padding(2).allowsHitTesting(false)
            }
        }
        .overlay {                                          // §10 ROUTE candidate: the BODY pulses (time-driven so it actually animates)
            if isRouteCand {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
                    let p = stagingPulseFraction(tl.date, period: 1.2)          // 0→1→0 over ~1.2s
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05 + 0.32 * p))
                }
            }
        }
        .overlay {                                          // border: recently-hidden > no-dest > selection > active > idle
            let activeGlow = inActiveCol && cell != nil && !ladderDim.contains(GridPos(col: col, row: row))   // LADDER: only the ACTIVE rung glows, not the dormant ones
            if GridPos(col: col, row: row) == hiddenPending, let hc = raw {
                // recently-HIDDEN (undo window): a ring in the hidden cell's own colour — tap to restore, touch elsewhere to delete
                RoundedRectangle(cornerRadius: 8).stroke(colourColor(hc.colourID) ?? .white, lineWidth: 2.5)
            } else if noDest && !isSel {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(red: 0.95, green: 0.25, blue: 0.28), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSel ? .white : (activeGlow ? Color.white.opacity(0.7) : cellEdge),   // A4: no amber on the face — selection is white
                            lineWidth: isSel ? 2 : (activeGlow ? 1.5 : 1))
            }
        }
        .overlay {                                          // §10 ROUTE candidates > §11 PLACE border > SELECT ring > verb glow
            let pos = GridPos(col: col, row: row)
            if routeIn.contains(pos) {                      // a source above → tap makes it this cell's INPUT
                routeLabel("IN", Color(red: 0.15, green: 0.88, blue: 0.94))
            } else if routeOut.contains(pos) {              // a cell below → tap makes it an OUTPUT of the focus
                routeLabel("OUT", Color(red: 0.35, green: 0.92, blue: 0.50))
            } else if whiteBorder.contains(pos) || selection.contains(pos) {
                // /btw ③ THE TWO-SOURCES LAW + item 4: a SELECTED or PLACED cell ALWAYS draws WHITE — never a
                // yellow ring (a yellow outline is invisible on a yellow cell). On the setup grid the ring BREATHES.
                if animateSelection {
                    // A thick MARCHING black/white dashed border (two offset dashed strokes) — reads as black/white chevrons.
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
                        let phase = CGFloat(tl.date.timeIntervalSinceReferenceDate * 22).truncatingRemainder(dividingBy: 16)
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).stroke(Color.white, style: StrokeStyle(lineWidth: 4, dash: [8, 8], dashPhase: phase))
                            RoundedRectangle(cornerRadius: 8).stroke(Color.black, style: StrokeStyle(lineWidth: 4, dash: [8, 8], dashPhase: phase + 8))
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 2.5)
                }
            } else if let inv = verbInvite {                // a verb is held (not PLACE): cells glow the verb hue
                RoundedRectangle(cornerRadius: 8).stroke(inv.opacity(0.55), lineWidth: 1.5)
            }
        }
        .overlay {                                          // ALT (B-state) breathing ring (§6.5) — effective ALT
            // §9 item 1 ON TAP (unified model): the ring follows base ALT XOR the ephemeral tap flip.
            let effAlt = cell.map { $0.alt != ((tapAltMask >> UInt64(col * 8 + row)) & 1 == 1) } ?? false
            if effAlt {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(breathe ? 0.95 : 0.35), lineWidth: 2)
                    .padding(3)
            }
        }
        .overlay {                                          // §5 drag-and-drop: the hovered drop target
            let pos = GridPos(col: col, row: row)
            if (dragFrom != nil && dragTo == pos && dragFrom != dragTo) || dropHoverCell == pos {
                RoundedRectangle(cornerRadius: 8).stroke(accentCyan, lineWidth: 2.5)
            }
        }
        .overlay {                                          // staging: EVERY empty cell pulses a border in the staged hue → tap to place
            if staging, cell == nil {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
                    let f = stagingPulseFraction(tl.date, period: 0.9)
                    RoundedRectangle(cornerRadius: 8).strokeBorder(stagingColor.opacity(0.2 + 0.7 * f), lineWidth: 2)
                }
                .allowsHitTesting(false)
            }
        }
        .overlay {                                          // staging: a PLACED cell pulses colour↔black, like its palette chip
            if stagedCells.contains(GridPos(col: col, row: row)) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
                    let f = stagingPulseFraction(tl.date, period: 0.85)
                    RoundedRectangle(cornerRadius: 8).fill(Color.black).opacity(f * 0.72)
                }
                .allowsHitTesting(false)
            }
        }
        .opacity(dragFrom == GridPos(col: col, row: row) ? 0.4 : 1)   // dim the cell being dragged
        .contentShape(Rectangle())
        // delta §5: the whole pad is ONE tap target in both modes — EDIT opens the CELL EDITOR (the VC
        // routes onTap), PERFORM flips ALT. FROM/OUT popovers + the hold menu are retired (contents moved
        // into the editor). Body-hold still auditions (stopped).
        // TAP → onTap (EDIT: hide-with-undo / staging commit-place; PERFORM: ALT flip). LONG-PRESS a
        // populated cell (user 2026-07-26): EDIT puts it into cell-edit AND arms a relocate — keep dragging
        // to move it (overwrite target); PERFORM auditions on the hold. The long-press must complete before
        // the drag, so a quick tap can never stage or move a cell.
        .onTapGesture { onTap?(col, row) }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("grid")))
                .onChanged { value in
                    guard case .second(true, let drag) = value else { return }   // long-press done → picked up
                    if editing {
                        if !stagePressed {                                        // fire staging ONCE: populated adopts,
                            stagePressed = true; onLongPressStageCell?(col, row)  // EMPTY stages the selected Colour (3rd entrance)
                        }
                        if cell != nil {                                          // relocate arms only for a pre-existing cell
                            if dragFrom == nil { dragFrom = GridPos(col: col, row: row) }
                            if let d = drag { dragTo = cellAt(location: d.location) }
                        }
                    } else {
                        onAuditionStart?(col, row)                                // PERFORM: hold → audition (idempotent)
                    }
                }
                .onEnded { value in
                    defer { dragFrom = nil; dragTo = nil; stagePressed = false }
                    if !editing { if !holdLatch { onAuditionEnd?() }; return }
                    guard case .second(true, let drag?) = value, let from = dragFrom,
                          let to = cellAt(location: drag.location), to != from else { return }
                    onMoveCell?((from.col, from.row), (to.col, to.row))           // relocate (overwrite)
                }
        )
        // MODE ROW · MOVE: a plain drag (no long-press) picks up this cell and drops it — over a populated cell SWAPS.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .named("grid"))
                .onChanged { v in
                    guard moveMode, cell != nil else { return }
                    if dragFrom == nil { dragFrom = GridPos(col: col, row: row) }
                    dragTo = cellAt(location: v.location)
                }
                .onEnded { v in
                    guard moveMode, let from = dragFrom else { dragFrom = nil; dragTo = nil; return }
                    defer { dragFrom = nil; dragTo = nil }
                    if let to = cellAt(location: v.location), to != from { onMoveCell?((from.col, from.row), (to.col, to.row)) }
                }
        )
    }

    // ① INPUT HEADER — "FROM MIDI" / "FROM R n" (a receiver) / "FROM ROW n"; flares white on the live
    // column. §9 item 11 BAND-AS-DEVIATION: a MIDI-IN cell on R2–R4 tints the header its receiver hue;
    // Receiver 1 (the default) and FROM-ROW cells show NO band — single-receiver grids stay clean.
    // (BUS DOTS retired 2026-08-03 — the seal now fills the whole cell face.)

    // THE SEAL COMET (§5) — a spark runs the wire while the cell SOUNDS. Position FREE-RUNS on a continuous clock
    // (loops the path START→ARROW→START), so a new note never resets it to the start. LIFE is gated by the per-cell
    // note-on/off feed (`cellSounding`): while the note is HELD the spark is fully alive — travelling for exactly the
    // sounding duration — then fades ~0.45s from release (`cellReleasedAt`). A very short note the 4Hz gate can miss
    // still completes a ~1.1s tail off its strike, so plucks aren't lost. Each strike re-glows the wire (~450ms).
    // Trail ∝ velocity. Frozen when hidden.
    @ViewBuilder private func sealComet(_ geo: SealGeometry, _ idx: Int) -> some View {
        let hitAt = (idx >= 0 && idx < cellHitAt.count) ? cellHitAt[idx] : Date.distantPast
        let vel = (idx >= 0 && idx < cellHitVel.count) ? cellHitVel[idx] : 0
        let sounding = (idx >= 0 && idx < cellSounding.count) ? cellSounding[idx] : false
        let releasedAt = (idx >= 0 && idx < cellReleasedAt.count) ? cellReleasedAt[idx] : Date.distantPast
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
            Canvas { ctx, size in
                let strikeAge = tl.date.timeIntervalSince(hitAt)
                let releaseAge = tl.date.timeIntervalSince(releasedAt)
                // STOP when the playhead leaves the column (user 2026-08-05). A TRACKED release (releasedAt after the
                // strike) fades FAST (~0.45s) — no extra pass. The ~1.1s strike-tail free-run is kept ONLY for a pluck
                // so short the 4Hz gate never recorded a release (no tracked release), so plucks still register.
                let hasRelease = releasedAt > hitAt
                let life = sounding ? 1.0
                                    : (hasRelease ? max(0.0, 1 - releaseAge / 0.45)
                                                  : max(0.0, 1 - strikeAge / 1.1))
                guard life > 0 else { return }
                let pts = sealNodePoints(geo, size: size, padFraction: 0.16)
                guard pts.count > 1 else { return }
                var dense: [CGPoint] = []                                       // arc-length samples along the node polyline
                let per = 10
                for i in 0..<(pts.count - 1) {
                    let a = pts[i], b = pts[i + 1]
                    for s in 0..<per {
                        let t = Double(s) / Double(per)
                        dense.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                    }
                }
                dense.append(pts[pts.count - 1])
                guard dense.count > 1 else { return }
                let glow = max(0.0, 1 - strikeAge / 0.45)                       // the strike glow decays ~450ms
                if glow > 0 {                                                   // §5: the wire brightens on strike
                    drawSeal(geo, into: ctx, size: size, padFraction: 0.16, stroke: 2.4, ink: .white.opacity(0.35 * glow))
                }
                // FREE-RUN while the note sounds (a new strike never resets it); FREEZE at the release position once
                // it lets go (a tracked release) so it fades IN PLACE instead of running an extra fraction of the path.
                let clock = (sounding || !hasRelease) ? tl.date.timeIntervalSinceReferenceDate
                                                      : releasedAt.timeIntervalSinceReferenceDate
                let prog = (clock * 0.9).truncatingRemainder(dividingBy: 1.0)
                let head = Int(prog * Double(dense.count - 1))                  // loops the path at ~0.9 lengths/s
                let trailLen = max(2, Int(vel * 12))                           // trail length ∝ velocity (§5)
                for k in 0..<trailLen {
                    let i = head - k
                    guard i >= 0, i < dense.count else { continue }
                    let alpha = life * (1 - Double(k) / Double(trailLen)) * 0.95
                    let r: CGFloat = k == 0 ? 2.6 : max(0.6, 2.2 - CGFloat(k) * 0.22)
                    ctx.fill(Path(ellipseIn: CGRect(x: dense[i].x - r, y: dense[i].y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // ---- routing derivation (mirrors engine resolvedParent/parentRow — truthful, delta §1) ----
    private func cellAt(_ col: Int, _ row: Int) -> Cell? {
        guard col >= 0, col < scene.cells.count, row >= 0, row < scene.cells[col].count else { return nil }
        return scene.cells[col][row]
    }
    private func parentOf(_ col: Int, _ row: Int) -> Int {
        guard let ir = cellAt(col, row)?.inputRow, ir != row, let p = cellAt(col, ir), !p.muted else { return -1 }
        return ir
    }
    private func isTapped(_ col: Int, _ row: Int) -> Bool {
        for r in 0..<8 where r != row && cellAt(col, r)?.inputRow == row { return true }
        return false
    }
}

// MARK: - Velocity marks (design item 4) — the strip meter is floating marks, not a bottom-fill

/// A floating velocity MARK: a note-on drawn at its velocity height, fading ~250ms. `col` is the source
/// colourIndex — emitters tint by the source Colour, −1 = the strip's own hue (receivers / master).
struct VelMark: Equatable { let vel: Double; let col: Int8; let born: Date; var withheld: Bool = false }

/// §strips-done: one currently-SOUNDING note on an emitter — a STEADY tick (no `born`; present while it
/// sounds, so the value only changes when the sounding set does — no per-poll state churn). `col` = the
/// source cell's colourIndex, for the cargo tint (the mark wears the Colour that struck it).
struct SoundMark: Equatable { let vel: Double; let col: Int8 }

/// Draw a strip's velocity marks — horizontal ticks at each mark's velocity height, opacity fading over
/// ~250ms. Behind a TimelineView (the caller animates by passing `now`). `hueFor` maps a mark to its colour.
/// §6a THE WITHHELD TELL: a `withheld` mark (a note CLAIM fully suppressed) draws HOLLOW (a stroked outline
/// in the source hue) + a small amber CLAIM tick, fading a touch slower — suppression made visible, not silent.
func velMarkLayer(_ marks: [VelMark], now: Date, hueFor: @escaping (Int8) -> Color) -> some View {
    let claimAmber = Color(red: 0.98, green: 0.72, blue: 0.12)
    return GeometryReader { g in
        ForEach(Array(marks.enumerated()), id: \.offset) { _, m in
            let op = max(0, 1 - now.timeIntervalSince(m.born) / (m.withheld ? 0.4 : 0.25))
            let y = g.size.height * (1 - CGFloat(max(0, min(1, m.vel))))
            if m.withheld {
                ZStack {
                    Rectangle().stroke(hueFor(m.col).opacity(op * 0.8), lineWidth: 1).frame(height: 3)
                    Rectangle().fill(claimAmber.opacity(op)).frame(width: 4, height: 3)
                }.position(x: g.size.width / 2, y: y)
            } else {
                Rectangle().fill(hueFor(m.col).opacity(op)).frame(height: 2).position(x: g.size.width / 2, y: y)
            }
        }
    }
}

// MARK: - RECEIVERS panel (delta §9 item 11) — the input twin of the EMITTERS panel

/// Velocity indicator (input + output faders, user 2026-08-03): a vertical GLOW brightest AT the level, fading
/// dimly ABOVE and BELOW — using the whole bar — plus a crisp white set-point line. `level` 0…1 from the bottom.
func velocityGlow(level: Double, hue: Color) -> some View {
    let p = max(0.02, min(0.98, 1 - level))           // the brightest band's location, measured from the TOP
    return GeometryReader { g in
        ZStack {
            Rectangle().fill(LinearGradient(stops: [
                .init(color: hue.opacity(0), location: 0),
                .init(color: hue.opacity(0.95), location: p),
                .init(color: hue.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            Rectangle().fill(Color.white.opacity(0.9)).frame(height: 1.5)
                .position(x: g.size.width / 2, y: g.size.height * CGFloat(p))
        }
    }
}

/// The four MIDI receivers as a strip panel above COLOUR: name + a cable stepper + a channel filter
/// (EDIT: ▲▼, OMNI…16) + an INPUT MUTE (both modes — "kill a live keyboard") + a LIVE input meter.
/// MPE is SILENT AUTO-DETECT (user ruling 2026-07-25) — no interface anywhere. Receiver colours are the
/// fixed "infrastructure family" (muted).
struct ReceiversView: View {
    @Environment(\.animationsPaused) private var animPaused
    let receivers: [Receiver]
    var peak: [Double] = [0, 0, 0, 0]                                    // §9 item 11 input meter: latched peak (0–1)
    var peakAt: [Date] = Array(repeating: .distantPast, count: 4)
    var heldVels: [[Double]] = [[], [], [], []]         // duration: currently-held input velocities (steady marks while held)
    var releaseMarks: [[VelMark]] = [[], [], [], []]    // ③ notes just RELEASED — fading marks (~250ms), strip hue
    var liveHeld: [Bool] = [false, false, false, false] // header dot: a LIVE (never latch) accepted note is held per receiver
    var isPortrait: Bool = false                        // PORTRAIT: tighten the strip — channel-only header (LATCH is padlock-only in every orientation now)
    var thruReceiver: Int = 0                           // receiver strip: the THRU pip (passthrough source) — retired from the header (bypass took its place)
    let onToggleMute: (Int) -> Void
    var onToggleEnable: (Int) -> Void = { _ in }        // INPUT ENABLE: the header toggles the door's listening
    var onSetThru: (Int) -> Void = { _ in }             // THRU pip radio
    // (channel/cable/latch-mode config lives on the cog page — CogPage.swift — not the strip. "Single-face forever".)
    // Feature overlays — present in the shell, wired by later increments (inert defaults here).
    var soloMask: UInt8 = 0                             // inc 2: additive SOLO set
    var onToggleSolo: (Int) -> Void = { _ in }
    var latchMask: UInt8 = 0                            // inc 5: per-receiver chord LATCH
    var onToggleLatch: (Int) -> Void = { _ in }
    var latchAddMask: UInt8 = 0                          // KEYS|CHORD: bit i = receiver i latches in KEYS (per-note toggle) mode; clear = CHORD
    var onSetLatchKeys: (Int, Bool) -> Void = { _, _ in }   // KEYS|CHORD toggle on the strip (true = KEYS)
    var bypassMask: UInt8 = 0                            // BYPASS: bit i = receiver i injects straight to emitters
    var onToggleBypass: (Int) -> Void = { _ in }
    var octave: [Int] = [0, 0, 0, 0]                   // inc 3: ephemeral ±octave nudge
    var onOct: (Int, Int) -> Void = { _, _ in }        // (receiver, ±1)
    var onVelOverride: (Int, Int?) -> Void = { _, _ in }   // inc 4: the slider's momentary input-velocity override
    var holdLatch: Bool = false                        // §5c HOLD latches the touched slider value
    // §10 STRIP SESSION FACE — while a verb is held the whole strip becomes one large ROUTE IN target: the
    // real content dims beneath (meters show through), the strip hue glows, a big label; the CURRENT source
    // wears a solid ring, the other (candidate) strips BREATHE. Tap routes the focus cell's input here.
    var wiring: Bool = false
    var routeCurrent: Int? = nil                       // the focus cell's current receiver (nil ⇒ row-fed/none — no ring)
    var onRouteIn: (Int) -> Void = { _ in }

    @State private var faderVel: [Int?] = [nil, nil, nil, nil]   // the touched slider value (nil = released → springs back)

    static let controlHeight: CGFloat = 61             // fixed control region (−20%, user 2026-08-05) — faces swap within it (§6a static-frame law)

    private var hues: [Color] { receiverHues }
    private func r(_ i: Int) -> Receiver { i < receivers.count ? receivers[i] : Receiver(name: "\(i + 1)") }
    private func bit(_ mask: UInt8, _ i: Int) -> Bool { mask & (1 << UInt8(i)) != 0 }

    var body: some View {
        // SPACE-FILL: the box grows to fill its band; the strips stretch VERTICALLY so the slider (and its
        // marks) gets the room — reclaimed pixels go to touch, not new controls.
        VStack(alignment: .leading, spacing: 3) {
            Text("MIDI INPUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            HStack(alignment: .top, spacing: 4) { ForEach(0..<4, id: \.self) { strip($0) } }
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // The strip: header (hue dot + R-label + THRU pip) · control region (SLIDER | features, faces swap) ·
    // foot (MUTE · SOLO). A soloed receiver GLOWs; when a solo set exists, excluded strips dim.
    private func strip(_ i: Int) -> some View {
        let rec = r(i), muted = rec.muted
        let soloed = bit(soloMask, i), excluded = soloMask != 0 && !soloed
        return VStack(spacing: 3) {
            header(i)
            HStack(alignment: .top, spacing: 3) {
                slider(i).frame(width: 16).frame(maxHeight: .infinity)   // input meter + FIXED velocity override — grows tall
                performFeatures(i)                          // LATCH+KEYS/CHORD · OCT · LIVE·SOLO (moved here, right of the slider)
            }
            .frame(minHeight: Self.controlHeight, maxHeight: .infinity)  // SPACE-FILL: control region spends the band's height
        }
        .padding(4).frame(maxWidth: .infinity, maxHeight: .infinity)   // SPACE-FILL: strip fills the band height
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(muted ? Color.white.opacity(0.02) : hues[i].opacity(soloed ? 0.22 : 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(soloed ? soloHue.opacity(0.8) : .clear, lineWidth: 1))
        .opacity(wiring ? 0.3 : (excluded ? 0.5 : 1))       // §10 dim-content-beneath while wiring (meters show through)
        .allowsHitTesting(!wiring)                          // the session face owns taps while wiring
        .overlay { if wiring { routeInFace(i) } }           // ROUTE IN session face on top
    }

    // The strip HEADER doubles as the INPUT ENABLE toggle (2026-08-03): it summarises the door's CHANNEL + key RANGE
    // (when narrowed) and tapping it OPENS/CLOSES the door to incoming notes. DISABLED = the door stops LISTENING
    // (dark pill, channel struck) — an armed latch keeps FEEDING its frozen chord to the grid ("close the door, keep
    // the room"). The small hue DOT lights whenever a LIVE accepted note is held (never the latch). BYPASS sits on
    // the right (it replaced the THRU pip), with its own tap outside the enable toggle's hit area.
    private func header(_ i: Int) -> some View {
        let rec = r(i), listening = rec.inputEnabledResolved
        let lit = i < liveHeld.count && liveHeld[i]   // LIVE input activity (not latch)
        // Summary = channel + (the key RANGE when it's been narrowed) — the door's sign. In PORTRAIT the strip is
        // narrow, so show the CHANNEL only. (§2 range chips live in the cog.)
        let chLabel = (rec.channel == 0 ? "OMNI" : "CH\(rec.channel)")
                    + ((isPortrait || rec.rangeIsFull) ? "" : " \(midiNoteName(rec.rangeLoResolved))–\(midiNoteName(rec.rangeHiResolved))")
        return HStack(spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(lit ? hues[i] : hues[i].opacity(listening ? 0.28 : 0.18))   // LIT while a live accepted note is held
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(hues[i].opacity(lit ? 0.9 : 0), lineWidth: 1))
                Text(["A", "B", "C", "D"][i]).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(listening ? .white.opacity(0.9) : .white.opacity(0.3))
                Text(chLabel).font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(listening ? .white.opacity(0.72) : .white.opacity(0.3))
                    .strikethrough(!listening, color: .white.opacity(0.35))
                    .lineLimit(1).minimumScaleFactor(0.6)   // the range suffix shrinks to fit the narrow strip
            }
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(listening ? hues[i].opacity(0.2) : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(listening ? hues[i].opacity(0.35) : Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { onToggleEnable(i) }
            Spacer(minLength: 0)
            bypassToggle(i)   // BYPASS — replaced the THRU pip (user 2026-08-03)
        }
    }

    // §10 the ROUTE IN session face — the whole strip is one target: hue glow, big label, the CURRENT source a
    // SOLID ring, the other (candidate) strips BREATHE. Tap routes the focus cell's input to this receiver.
    private func routeInFace(_ i: Int) -> some View {
        let hue = hues[i], isCurrent = routeCurrent == i
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
            let breathe = stagingPulseFraction(tl.date, period: 1.8)     // 0→1→0, shared cadence
            let ring = isCurrent ? 1.0 : (0.3 + 0.5 * breathe)          // current solid; candidates pulse
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(hue.opacity(isCurrent ? 0.22 : 0.08 + 0.06 * breathe))
                RoundedRectangle(cornerRadius: 6).stroke(hue.opacity(ring), lineWidth: isCurrent ? 2.5 : 1.5)
                Text("IN").font(.system(size: 26, weight: .heavy, design: .monospaced))   // nothing but IN
                    .foregroundColor(isCurrent ? .white : hue).tracking(2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onRouteIn(i) }
    }

    private let soloHue = Color(red: 0.98, green: 0.72, blue: 0.12)

    // (THRU pip retired 2026-08-03 — BYPASS replaced it in the header; `thruReceiver`/`onSetThru` stay wired but
    // the strip no longer surfaces the passthrough radio.)

    // PERFORM features (right of the slider): the LATCH + KEYS/CHORD cluster, the OCT−/OCT+ nudges + deviation
    // readout, and LIVE·SOLO (moved here from the foot). Single-face forever — channel/range config lives in the cog.
    private func performFeatures(_ i: Int) -> some View {
        let oct = i < octave.count ? octave[i] : 0
        let muted = r(i).muted, soloed = bit(soloMask, i), excluded = soloMask != 0 && !soloed
        let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
        return VStack(spacing: 3) {
            latchRow(i)              // LATCH (left) + KEYS/CHORD (right) — one related cluster
            Color.clear.frame(height: 5)   // gap: latch cluster ↔ OCT (user 2026-08-03)
            HStack(spacing: 2) {
                featBtn("OCT−", lit: false) { onOct(i, -1) }
                featBtn("OCT+", lit: false) { onOct(i, +1) }
            }
            Text(oct == 0 ? " " : (oct > 0 ? "+\(oct)" : "\(oct)"))
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(oct != 0 ? soloHue : .white.opacity(0.3))
            Color.clear.frame(height: 5)   // gap: OCT ↔ LIVE·SOLO (user 2026-08-03)
            HStack(spacing: 3) {     // LIVE · SOLO — moved here below OCT (user 2026-08-03); the EMITTER colours (LIVE cyan · SOLO amber)
                footBtn(muted ? "MUTED" : "LIVE", lit: !muted, hue: cyan, dim: muted) { onToggleMute(i) }
                footBtn("SOLO", lit: soloed, hue: soloHue, dim: excluded) { onToggleSolo(i) }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }

    // BYPASS toggle (§1) — compact, in the header where the THRU pip used to be. Lit = this door skips the grid and
    // injects straight to its destination emitters (chosen in the cog). Cyan, to distinguish it from the amber LATCH.
    private func bypassToggle(_ i: Int) -> some View {
        let on = bit(bypassMask, i)
        let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
        return HStack(spacing: 2) {
            Image(systemName: on ? "arrow.turn.down.right" : "arrow.right").font(.system(size: 7, weight: .heavy))
            Text("BYP").font(.system(size: 7, weight: .heavy, design: .monospaced))
        }
        .foregroundColor(on ? .black : .white.opacity(0.85))   // WHITE unless selected (user 2026-08-03); cyan fill when armed
        .padding(.horizontal, 4).frame(height: 15)
        .background(RoundedRectangle(cornerRadius: 3).fill(on ? cyan.opacity(0.9) : Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? .clear : Color.white.opacity(0.35), lineWidth: 1))
        .contentShape(Rectangle()).onTapGesture { onToggleBypass(i) }
    }

    // LATCH + KEYS|CHORD as ONE related cluster (user 2026-08-03): the LATCH button on the LEFT (padlock latched to
    // its side), the KEYS (top) / CHORD (bottom) mode stack on the RIGHT — both the same height so the three read as
    // a set. LATCH height = the two mode segments stacked (no longer the oversized headline).
    private func latchRow(_ i: Int) -> some View {
        let keys = bit(latchAddMask, i)
        return HStack(spacing: 3) {
            latchArm(i)
            VStack(spacing: 2) {
                modeSeg("KEYS", on: keys) { onSetLatchKeys(i, true) }
                modeSeg("CHORD", on: !keys) { onSetLatchKeys(i, false) }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 30)   // = two 14pt segments + 2pt spacing; the LATCH button matches this
    }

    // The LATCH ARM — the receiver's performance control. Padlock glyph LATCHED to the LEFT of the "LATCH" label
    // (horizontal), hue-tinted at rest, a solid glow when armed so it's legible across the band. Fills the row
    // height so it equals the KEYS/CHORD stack beside it.
    private func latchArm(_ i: Int) -> some View {
        let armed = bit(latchMask, i)
        return HStack(spacing: 4) {
            Image(systemName: armed ? "lock.fill" : "lock.open").font(.system(size: 12, weight: .heavy))
            // PADLOCK ONLY in every orientation (user 2026-08-05: the "LATCH" word removed from landscape too).
        }
        .foregroundColor(armed ? .black : soloHue.opacity(0.95))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 5).fill(armed ? soloHue : soloHue.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(soloHue.opacity(armed ? 0 : 0.55), lineWidth: 1))
        .contentShape(Rectangle()).onTapGesture { onToggleLatch(i) }
    }

    // KEYS | CHORD segments — the latch update rule (moved off the cog per §1). KEYS (default) = each key toggles
    // frozen-pool membership; CHORD = a detected chord clears & replaces the pool. Switching NEVER clears the pool.
    private func modeSeg(_ t: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Text(t).font(.system(size: 7, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.5))
            .frame(maxWidth: .infinity).frame(height: 14)
            .background(RoundedRectangle(cornerRadius: 3).fill(on ? soloHue.opacity(0.85) : Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }

    private func featBtn(_ label: String, lit: Bool, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced))
            .foregroundColor(lit ? .black : .white.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit ? soloHue : Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    private func footBtn(_ label: String, lit: Bool, hue: Color, dim: Bool, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced))
            .foregroundColor(lit ? .black : .white.opacity(dim ? 0.4 : 0.7))
            .frame(maxWidth: .infinity).frame(height: 15)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit ? hue.opacity(0.72) : Color.white.opacity(0.06)))   // ④ chrome quiet: the default LIVE pad recedes a step
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }


    // The SLIDER — the emitter fader's INPUT twin. Idle: the live input meter (held-note ticks — LATCH velocities
    // when armed). Touched: a FIXED absolute velocity override (drag = whisper/slam the receiver's subscribers) that
    // HOLDS where it's left (no spring-back). A glow marks the forced value while set.
    private func slider(_ i: Int) -> some View {
        let touched = (i < faderVel.count ? faderVel[i] : nil) != nil
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
            let level = touched ? Double(faderVel[i] ?? 0) / 127.0 : decayed(i, now: tl.date)
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05))
                    if touched {                                   // OVERRIDE: a glow brightest at the set velocity, fading above/below
                        velocityGlow(level: level, hue: hues[i])
                    } else {                                       // ③ VELOCITY MARKS: a steady tick per currently-HELD input
                        // note (holds while sounding, strip hue) + a FADING mark for each just-released note (~250ms).
                        ForEach(Array((i < heldVels.count ? heldVels[i] : []).enumerated()), id: \.offset) { _, v in
                            Rectangle().fill(hues[i].opacity(0.9)).frame(height: 2)
                                .position(x: g.size.width / 2, y: g.size.height * (1 - CGFloat(max(0, min(1, v)))))
                        }
                        velMarkLayer(i < releaseMarks.count ? releaseMarks[i] : [], now: tl.date) { _ in hues[i] }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let frac = 1.0 - min(1, max(0, v.location.y / g.size.height))
                    let val = max(1, Int(frac * 127))
                    if i < faderVel.count { faderVel[i] = val }; onVelOverride(i, val)
                }.onEnded { _ in
                    // FIXED position (user 2026-08-03): the fader HOLDS where it's left — no spring-back. The forced
                    // velocity persists (the engine keeps the override until it's moved again). Untouched = no override.
                })
            }
        }
    }

    private func decayed(_ i: Int, now: Date) -> Double {
        guard i < peak.count, i < peakAt.count else { return 0 }
        return peakHoldLevel(peak: peak[i], since: peakAt[i], now: now)
    }
}

/// OUTPUTS panel (delta §7/§7b): the fixed cable identities + each bus's stamp channel. Tap a bus's
/// channel to bump it (1…16 → wraps). Flags when two buses share a channel (their streams merge on
/// the All cable — legal, never blocked).
/// EMITTERS panel (delta §6a): the four pads ARE the emitters. Pad BODY = enable/disable TOGGLE in BOTH
/// modes (the per-output performance mute). In EDIT the CH caption is an OPENER for the channel popover
/// (1–16); in PERFORM CH is display-only. Disabled = recessed/dark. (Firing-flash animation deferred —
/// it needs a per-bus emit signal from the engine.)
/// EMITTERS panel (delta §6a rev — a7). A mode-aware, per-emitter CHANNEL-STRIP mixer that supersedes
/// the a2 caption-popover. Every emitter is a vertical strip: a TOGGLE pad on top (letter + live
/// metering flash, both modes) over a fixed-height control region — EDIT shows a dedicated CH stepper
/// (▲/▼, no popover, no selection state); PERFORM shows a velocity FADER + LED ladder (the momentary
/// absolute override — drag to whisper/slam the bus, release springs it back). Both faces fill the
/// SAME strip height, so the desk box never resizes across the mode flip (§6a static-frame law).
struct OutputsView: View {
    @Environment(\.animationsPaused) private var animPaused
    let busEnabled: [Bool]        // 4 flags (short/empty ⇒ enabled)
    let busChannels: [Int]        // 4 values, 1–16 (shown in the header; SET on the cog page, not the strip)
    var emitPeak: [Double] = [0, 0, 0, 0]                                  // §6a meter: latched peak (0–1)
    var emitPeakAt: [Date] = Array(repeating: .distantPast, count: 4)      // when latched (peak-hold decay)
    var marks: [[VelMark]] = [[], [], [], []]                             // item 4: floating output velocity marks (Colour-tinted)
    var sounding: [[SoundMark]] = [[], [], [], []]                        // §strips-done: notes currently sounding per emitter (steady, cargo-tinted)
    var releaseMarks: [[VelMark]] = [[], [], [], []]                      // §strips-done: notes just released — fading marks (~250ms), cargo-tinted
    var holdLatch: Bool = false                                            // §5c: fader release latches (keeps the value)
    let onToggle: (Int) -> Void           // toggle pad → enable/disable emitter i
    var onVelOverride: (Int, Int?) -> Void = { _, _ in }   // PERFORM fader → force vel (1–127); nil = release
    var soloMask: UInt8 = 0                                 // foot SOLO — additive set (reuses soloEmitterMask)
    var onToggleSolo: (Int) -> Void = { _ in }
    var octave: [Int] = [0, 0, 0, 0]                       // E-2: ephemeral output ±octave nudge
    var onOct: (Int, Int) -> Void = { _, _ in }            // (emitter, ±1)
    // THE RACK (design-the-rack §1): the strip is CLEAN — OCT±·velocity·LIVE·SOLO·RACK. The RACK button (tap =
    // toggle the board in/out of the signal path; long-press = open the matrix) supersedes the CLAIM/DUCK/ALT role
    // buttons, which move into the matrix overlay. `rackMask` bit i set ⇒ emitter i's rack is in path (lit).
    var rackMask: UInt8 = 0b1111
    var onToggleRack: (Int) -> Void = { _ in }             // strip RACK tap → toggle emitter i's rack in/out of path
    // §10 STRIP SESSION FACE — while a verb is held the emitter strip becomes a ROUTE OUT toggle, large and
    // geographic (content dims beneath, green glow; lit = this emitter carries the focus cell). Tap toggles.
    var wiring: Bool = false
    var routeOn: [Bool] = [false, false, false, false]     // the focus cell's enabled emitters (A–D)
    var onRouteOut: (Int) -> Void = { _ in }
    // EMITTER PAGE (2026-08-04): LONG-PRESS a role button (→ that section) or the header (→ top) opens the full page.
    var onOpenPage: (Int, String) -> Void = { _, _ in }

    // Live fader value per emitter WHILE its slider is touched (nil = released → engine springs back).
    @State private var faderVel: [Int?] = [nil, nil, nil, nil]
    @State private var rackLongFired = false                          // a RACK long-press opened the matrix → the release must not also toggle
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let letters = ["A", "B", "C", "D"]             // emitters A–D (box title MIDI OUTPUT disambiguates from inputs)
    private let controlHeight: CGFloat = 78   // the EDIT stepper / PERFORM fader region — identical both modes

    private func on(_ i: Int) -> Bool { i < busEnabled.count ? busEnabled[i] : true }
    private func ch(_ i: Int) -> Int { i < busChannels.count ? busChannels[i] : i + 1 }
    private func sharedWithEnabled(_ i: Int) -> Bool {
        on(i) && (0..<4).contains { $0 != i && on($0) && ch($0) == ch(i) }
    }

    var body: some View {
        // SPACE-FILL: the box grows to fill its band; strips stretch VERTICALLY so the fader + its marks get room.
        VStack(alignment: .leading, spacing: 3) {
            Text("MIDI OUTPUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            HStack(alignment: .top, spacing: 4) { ForEach(0..<4, id: \.self) { strip($0) } }
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: holdLatch) { latched in            // §5c: HOLD-off = the drop → every fader springs home
            if !latched { for i in 0..<4 { faderVel[i] = nil; onVelOverride(i, nil) } }
        }
    }

    // One emitter strip — the receiver strip's twin anatomy: header (dot + E-label + ch) · SLIDER | role
    // column (CLAIM/OCT in PERFORM, CHANNEL stepper in EDIT) · foot MUTE·SOLO. A soloed strip glows;
    // excluded strips dim. Both faces fill `controlHeight`, so the frame is identical across the mode flip.
    private func strip(_ i: Int) -> some View {
        let muted = !on(i), soloed = bit(soloMask, i), excluded = soloMask != 0 && !soloed
        return VStack(spacing: 3) {
            header(i, muted: muted)
            HStack(alignment: .top, spacing: 3) {
                fader(i).frame(width: 16).frame(maxHeight: .infinity)
                rackColumn(i)                               // THE RACK: RACK button + OCT± (roles moved into the matrix)
            }
            .frame(minHeight: controlHeight, maxHeight: .infinity)   // SPACE-FILL: fader region spends the band's height
            HStack(spacing: 3) {                             // foot: MUTE (the enable gate) · SOLO
                footBtn(muted ? "MUTED" : "LIVE", lit: !muted, hue: cyan, dim: muted) { onToggle(i) }
                footBtn("SOLO", lit: soloed, hue: amber, dim: excluded) { onToggleSolo(i) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // SPACE-FILL: strip fills the band height
        .opacity(wiring ? 0.3 : (excluded ? 0.5 : 1))       // §10 dim-content-beneath while wiring
        .allowsHitTesting(!wiring)
        .overlay { if wiring { routeOutFace(i) } }           // ROUTE OUT session face on top
    }

    // §10 the ROUTE OUT session face — the emitter strip is a big geographic toggle: green glow, lit when this
    // emitter carries the focus cell (candidates breathe when off). Tap toggles the cell's emitter.
    private func routeOutFace(_ i: Int) -> some View {
        let green = Color(red: 0.35, green: 0.92, blue: 0.50)
        let lit = i < routeOn.count && routeOn[i]
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
            let breathe = stagingPulseFraction(tl.date, period: 1.8)
            let ring = lit ? 1.0 : (0.3 + 0.5 * breathe)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(green.opacity(lit ? 0.28 : 0.07 + 0.05 * breathe))
                RoundedRectangle(cornerRadius: 6).stroke(green.opacity(ring), lineWidth: lit ? 2.5 : 1.5)
                Text("OUT").font(.system(size: 26, weight: .heavy, design: .monospaced))   // nothing but OUT
                    .foregroundColor(lit ? .black : green).tracking(2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onRouteOut(i) }
    }

    private func bit(_ mask: UInt8, _ i: Int) -> Bool { mask & (1 << UInt8(i)) != 0 }

    // Header: enable dot + E-label + the stamp channel (amber when shared with another enabled emitter).
    private func header(_ i: Int, muted: Bool) -> some View {
        HStack(spacing: 3) {
            Circle().fill(muted ? Color.white.opacity(0.25) : cyan).frame(width: 7, height: 7)
            Text(letters[i]).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(muted ? .white.opacity(0.3) : .white.opacity(0.85))
            Spacer(minLength: 0)
            Text("ch\(ch(i))").font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(sharedWithEnabled(i) ? amber : .white.opacity(0.5))
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) { onOpenPage(i, "top") }   // EMITTER PAGE at the top
    }

    // THE RACK (design-the-rack §1) — the strip's clean control column: one RACK button over the OCT−/OCT+
    // nudges. RACK = the loop switcher: TAP toggles this emitter's whole pedalboard in/out of the signal path;
    // LONG-PRESS opens the matrix (SETUP). The CLAIM/DUCK/ALT role buttons moved into the matrix.
    private func rackColumn(_ i: Int) -> some View {
        let oct = i < octave.count ? octave[i] : 0
        return VStack(spacing: 2) {
            rackButton(i)
            HStack(spacing: 2) {
                octBtn("OCT−") { onOct(i, -1) }
                octBtn("OCT+") { onOct(i, +1) }
            }
            Text(oct == 0 ? " " : (oct > 0 ? "+\(oct)" : "\(oct)"))
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(oct != 0 ? amber : .white.opacity(0.3))
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }

    // THE RACK button — lit (cyan) = the board is in the signal path; unlit (outlined) = raw wire. TAP toggles;
    // LONG-PRESS opens the matrix. `rackLongFired` stops the long-press release from also toggling.
    private func rackButton(_ i: Int) -> some View {
        let inPath = rackMask & (1 << UInt8(i)) != 0
        return Text("RACK")
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(inPath ? .black : cyan.opacity(0.85))
            .frame(maxWidth: .infinity).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 3).fill(inPath ? cyan.opacity(0.85) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(inPath ? .clear : cyan.opacity(0.5), lineWidth: 1.2))
            .contentShape(Rectangle())
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in rackLongFired = true; onOpenPage(i, "top") })
            .onTapGesture {
                if rackLongFired { rackLongFired = false; return }   // the matrix opened on long-press → don't toggle
                onToggleRack(i)
            }
    }
    private func octBtn(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 22)   // taller emitter buttons (user 2026-07-28)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    private func footBtn(_ label: String, lit: Bool, hue: Color, dim: Bool, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced))
            .foregroundColor(lit ? .black : .white.opacity(dim ? 0.4 : 0.7))
            .frame(maxWidth: .infinity).frame(height: 20)   // taller emitter buttons (user 2026-07-28)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit ? hue.opacity(0.72) : Color.white.opacity(0.06)))   // ④ chrome quiet: the default LIVE pad recedes a step
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    // EDIT — a dedicated per-emitter channel stepper (▲/▼, wrapping 1–16). Replaces the a2 popover;
    // no selection state, no floating layer. Amber number = shares a channel with another enabled emitter.
    // PERFORM — a vertical velocity fader with an 8-segment LED ladder. Idle: the ladder tracks the live
    // meter (decaying). Touched: it shows the forced value and a bright set-point line; drag maps y →
    // 1–127, release springs back (fader → nil, engine → natural velocity). Disabled emitter = greyed.
    private func fader(_ i: Int) -> some View {
        let enabled = on(i)
        return GeometryReader { g in
            let h = g.size.height
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
                let touched = faderVel[i] != nil
                let level = touched ? Double(faderVel[i]!) / 127.0 : decayed(i, now: tl.date)
                faderBody(i: i, level: level, touched: touched, enabled: enabled, now: tl.date)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled else { return }
                        let frac = 1 - min(1, max(0, v.location.y / max(1, h)))
                        let val = frac < 0.03 ? 0 : max(1, Int((frac * 127).rounded()))   // §4b bottom = KILL (0)
                        faderVel[i] = val
                        onVelOverride(i, val)
                    }
                    .onEnded { _ in
                        if holdLatch { return }             // §5c HOLD: latch at the released value (keep it)
                        faderVel[i] = nil
                        onVelOverride(i, nil)               // else spring back to natural velocity
                    }
            )
        }
        .frame(maxHeight: .infinity)   // fills the region above the CLAIM footer
    }


    // OVERRIDE (touched) = the LED-ladder FILL bottom-to-finger + set-point; PASSIVE (idle) = item-4 floating
    // velocity MARKS, each tinted in its source cell's Colour (who struck, how hard). Disabled = greyed.
    private func faderBody(i: Int, level: Double, touched: Bool, enabled: Bool, now: Date) -> some View {
        return ZStack {
            if touched {                                    // OVERRIDE: a glow brightest at the set velocity, fading above/below
                velocityGlow(level: level, hue: enabled ? cyan : Color.white.opacity(0.15))
            } else if enabled {
                soundingLayer(i < sounding.count ? sounding[i] : []) { col in emitterHue(col) }   // §strips-done: hold-while-sounding
                velMarkLayer(i < releaseMarks.count ? releaseMarks[i] : [], now: now) { col in emitterHue(col) }   // fade-on-release
                velMarkLayer(i < marks.count ? marks[i] : [], now: now) { col in emitterHue(col) }   // item 4: the note-on flash
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
        .overlay(alignment: .bottom) {
            Text(enabled ? (touched ? "\(faderVel[i]!)" : "ch \(ch(i))") : "off")
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(holdLatch && touched ? amber : .white.opacity(touched ? 0.7 : 0.25))  // §5c HELD cue
                .padding(.bottom, 1)
        }
    }
    // item 4: a mark's tint = its source cell's Colour (−1 / out of range → the emitter cyan).
    private func emitterHue(_ col: Int8) -> Color {
        (col >= 0 && Int(col) < colourIDs.count) ? (colourColor(colourIDs[Int(col)]) ?? cyan) : cyan
    }
    // §strips-done: STEADY hold-while-sounding ticks — one per currently-sounding note at its velocity height,
    // in the source Colour (cargo tint). Solid (no fade); each vanishes the poll after its note stops sounding.
    private func soundingLayer(_ marks: [SoundMark], hueFor: @escaping (Int8) -> Color) -> some View {
        GeometryReader { g in
            ForEach(Array(marks.enumerated()), id: \.offset) { _, m in
                Rectangle().fill(hueFor(m.col).opacity(0.85)).frame(height: 2)
                    .position(x: g.size.width / 2, y: g.size.height * (1 - CGFloat(max(0, min(1, m.vel)))))
            }
        }
    }

    private func decayed(_ i: Int, now: Date) -> Double {
        guard i < emitPeak.count, i < emitPeakAt.count else { return 0 }
        return peakHoldLevel(peak: emitPeak[i], since: emitPeakAt[i], now: now)   // ~150ms peak-hold decay
    }
}

/// MASTER PANEL (design item 3) — the bottom-right console corner, anatomy mirroring the strips: the SUM
/// METER behind a master velocity FADER (momentary-absolute over all output; spring / §5c HOLD-latch) beside
/// a feature column — MUTE (tap = kill · long-press = PANIC) · KEY −/+ (per-scene transpose). REVERT + INS are
/// reserved seats (snapshot + wire work). Fader = weather; MUTE/KEY = structure. NO SOLO (solo against nothing).
struct MasterView: View {
    @Environment(\.animationsPaused) private var animPaused
    let mute: Bool
    let key: Int
    var peak: Double = 0                                   // the sum meter (max of the emitter peaks)
    var peakAt: Date = .distantPast
    var marks: [VelMark] = []                              // item 4: the sum's velocity marks (Colour-tinted, capped)
    var holdLatch: Bool = false
    let onMute: () -> Void
    let onPanic: () -> Void
    let onKey: (Int) -> Void
    var onVelOverride: (Int?) -> Void = { _ in }

    @State private var faderVel: Int? = nil
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let red = Color(red: 0.98, green: 0.35, blue: 0.3)
    static let controlHeight: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MASTER").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            HStack(alignment: .top, spacing: 3) {
                fader.frame(width: 16).frame(maxHeight: .infinity)
                VStack(spacing: 2) {
                    Text(mute ? "MUTED" : "MUTE").font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(mute ? .black : .white.opacity(0.7))
                        .frame(maxWidth: .infinity).frame(height: 16)
                        .background(RoundedRectangle(cornerRadius: 3).fill(mute ? red : Color.white.opacity(0.08)))
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.6) { onPanic() }
                        .simultaneousGesture(TapGesture().onEnded { onMute() })
                    HStack(spacing: 2) { keyBtn("KEY−") { onKey(-1) }; keyBtn("KEY+") { onKey(+1) } }
                    Text(key == 0 ? "KEY 0" : "KEY \(key > 0 ? "+" : "")\(key)")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(key != 0 ? amber : .white.opacity(0.3))
                    HStack(spacing: 2) { seat("REVERT"); seat("INS") }   // reserved seats (item 7 / item 14)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity)
            }.frame(minHeight: Self.controlHeight, maxHeight: .infinity)   // SPACE-FILL: the fader takes the column's height
        }
        .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // The master fader: idle shows the sum meter; touched forces velocity over ALL output (spring / HOLD-latch).
    private var fader: some View {
        let touched = faderVel != nil
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
            let level = touched ? Double(faderVel ?? 0) / 127.0 : peakHoldLevel(peak: peak, since: peakAt, now: tl.date)
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05))
                    if touched {                                   // OVERRIDE: the fill over the sum + set-point
                        Rectangle().fill(amber).frame(height: g.size.height * CGFloat(level))
                        Rectangle().fill(Color.white).frame(height: 1.5).offset(y: -g.size.height * CGFloat(level) + 0.75)
                    } else {                                       // item 4: the sum's velocity marks (Colour-tinted)
                        velMarkLayer(marks, now: tl.date) { col in
                            (col >= 0 && Int(col) < colourIDs.count) ? (colourColor(colourIDs[Int(col)]) ?? cyan) : cyan
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let frac = 1.0 - min(1, max(0, v.location.y / g.size.height))
                    faderVel = frac < 0.03 ? 0 : max(1, Int(frac * 127)); onVelOverride(faderVel)   // §4b bottom = KILL (0)
                }.onEnded { _ in
                    if holdLatch { return }
                    faderVel = nil; onVelOverride(nil)
                })
            }
        }
    }
    private func keyBtn(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    private func seat(_ label: String) -> some View {   // a reserved (inert) seat — dim, non-interactive
        Text(label).font(.system(size: 6, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.22))
            .frame(maxWidth: .infinity).frame(height: 13)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.03)))
    }
}

/// HEADER (delta §6): logotype · STEP rate · SWING · PASS/transport readout. STEP/SWING are the
/// scene-level timing controls (AUParameters 0/1) — the only in-plugin way to set them.
/// §5b COLUMN-SUBSET LAP — the multi-column HOLD gesture. A `UIView` (not a SwiftUI gesture) because
/// SwiftUI can't reliably track SIMULTANEOUS touches across the sibling column keys; this one view
/// receives every touch, maps each to a column, and reports the held-column BITMASK. Being UIKit, it
/// SURVIVES SwiftUI re-renders — so the 4 Hz poll can never tear a hold down mid-gesture. Only mounted
/// in PERFORM; unmounting (mode switch) cancels its touches → the parent gets mask 0.
private struct ColumnHoldOverlay: UIViewRepresentable {
    let gap: CGFloat
    var latched: Bool = false          // §5c HOLD: column keys become membership TOGGLES (editable lap set)
    let onChange: (UInt8) -> Void

    func makeUIView(context: Context) -> TouchRow { let v = TouchRow(); v.gap = gap; v.onChange = onChange; v.latched = latched; return v }
    func updateUIView(_ v: TouchRow, context: Context) { v.gap = gap; v.onChange = onChange; v.latched = latched }

    final class TouchRow: UIView {
        var gap: CGFloat = 3
        var onChange: ((UInt8) -> Void)?
        // §5c: while latched, a TAP toggles a column's membership and the set persists (release does
        // nothing). HOLD-on GRADUATES the currently-held columns into the set; HOLD-off clears it (the
        // VC also drops the engine lap). Momentary hold is the un-latched behaviour, unchanged.
        var latched: Bool = false {
            didSet { if latched != oldValue { latchedMask = latched ? currentTouchMask() : 0 } }
        }
        private var latchedMask: UInt8 = 0
        private var active: Set<UITouch> = []

        override init(frame: CGRect) { super.init(frame: frame); isMultipleTouchEnabled = true; backgroundColor = .clear }
        required init?(coder: NSCoder) { fatalError("no coder") }

        private func column(_ t: UITouch) -> Int? {
            let w = bounds.width; guard w > 0 else { return nil }
            let stride = (w + gap) / 8            // per-key stride: 8 keys + 7 inter-key gaps ⇒ (w+gap)/8
            let c = Int((t.location(in: self).x / stride).rounded(.down))
            return (c >= 0 && c < 8) ? c : nil
        }
        private func currentTouchMask() -> UInt8 {
            var mask: UInt8 = 0
            for t in active where t.phase != .ended && t.phase != .cancelled {
                if let c = column(t) { mask |= 1 << UInt8(c) }
            }
            return mask
        }
        private func report() { onChange?(latched ? latchedMask : currentTouchMask()) }

        override func touchesBegan(_ ts: Set<UITouch>, with e: UIEvent?) {
            active.formUnion(ts)
            if latched { for t in ts { if let c = column(t) { latchedMask ^= (1 << UInt8(c)) } } }   // tap = toggle
            report()
        }
        override func touchesMoved(_ ts: Set<UITouch>, with e: UIEvent?)     { if !latched { report() } }
        override func touchesEnded(_ ts: Set<UITouch>, with e: UIEvent?)     { active.subtract(ts); if !latched { report() } }
        override func touchesCancelled(_ ts: Set<UITouch>, with e: UIEvent?) { active.subtract(ts); if !latched { report() } }
    }
}

// (HeaderView retired — the header + scene strip merged into the VC's `arrangementBar` for AB-1; its
//  logotype / mode-toggle / undo-redo / PASS-readout live inline there now.)

/// A PROCESSOR PANEL (delta item 8, TWO-PROCESSOR Colours): one self-contained editor for ONE face of the
/// selected Colour (= the palette brush) — the A face or the optional B face. Title row (PROCESSOR A/B +
/// COPY, and PASTE when the clipboard holds a processor) · type selector (A = 6 types; B = OFF + 6, OFF =
/// B-less) · TRANSPOSE + the full param set INLINE + (B only) the MORPH fader when B is a FULL glide.
/// FIXED frame sized for the largest (arp) field set, so truncation dies by geometry. A transpose/morph are
/// AUParameters (own callbacks); B's transpose + all params go through editColour. COPY/PASTE let any panel
/// lift a processor and drop it onto any other (cross-type paste retypes the target).
/// Apply a fixed height + clip ONLY when a height is given (the Colour-desk static-frames rule); pass nil to let
/// the view size to its content (slotMode, whose always-visible radio rows must all show).
private struct FixedHeightIf: ViewModifier {
    let height: CGFloat?
    func body(content: Content) -> some View {
        if let h = height { content.frame(height: h, alignment: .top).clipped() } else { content }
    }
}

struct ProcessorBox: View {
    enum Face { case a, b }
    let colour: Colour
    let colourIndex: Int
    var face: Face = .a
    let onEdit: (@escaping (inout Colour) -> Void) -> Void
    let onTranspose: (Int) -> Void                      // A face: transpose is an AUParameter
    let onMorph: (Double) -> Void
    var onSetTypeA: ((ProcessorType) -> Void)? = nil    // A face: switchType via the AU (per-type stash)
    var canPaste: Bool = false                          // clipboard non-empty ⇒ show PASTE
    var onCopy: () -> Void = {}
    var onPaste: () -> Void = {}
    var height: CGFloat = panelHeight                   // portrait A-above-B stacking passes a shorter height
    var mixed: Bool = false                             // MIXED-SET law: SELECT spans >1 Colour → dim + disable
    // CELL MACHINE (feat/EditPageSpike): when slotMode, this box edits ONE chain slot on a cell (not a Colour
    // face) — the title carries a BYPASS chip (and REMOVE) instead of COPY/PASTE, and transpose/morph are hidden
    // (those stay Colour-level). Bound via a synthetic Colour whose A face == the slot's type+params.
    var slotMode: Bool = false
    var slotBypassed: Bool = false
    var accentOverride: Color? = nil                     // MODE ROW: force the control accent (blue, to match the emitters)
    var passHead: Int = -1                               // MODE ROW: the live PASS index (0…3) for the passgate playhead; -1 = stopped
    var onBypass: () -> Void = {}
    var onRemove: (() -> Void)? = nil                   // nil = not removable (the head slot)
    @State private var showTypePicker = false           // B1: the title-as-picker popover

    static let panelHeight: CGFloat = 300               // fixed — sized for the largest field set + morph

    private var isB: Bool { face == .b }
    private var accent: Color { accentOverride ?? (colourColor(colour.colourID) ?? .gray) }
    private var faceType: ProcessorType? { isB ? colour.typeB : colour.type }   // B may be nil = B-less
    private var p: ColourParams { isB ? colour.paramsB : colour.paramsA }
    private var faceTranspose: Int { isB ? colour.transposeBResolved : colour.transpose }
    private var glides: Bool { colour.typeB == colour.type }   // FULL morph ⇔ B is the same type as A
    private func setParam(_ f: @escaping (inout ColourParams) -> Void) {
        onEdit { c in if isB { f(&c.paramsB) } else { f(&c.paramsA) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: slotMode ? 14 : 6) {
            titleRow
            if mixed {
                mixedFace                                // MIXED-SET: no honest Colour-level edit for a multi-Colour set
            } else {
                if let ft = faceType {
                    if !slotMode {                       // CELL MACHINE: transpose/morph stay Colour-level, hidden per-slot
                        field("TRANSPOSE \(faceTranspose > 0 ? "+" : "")\(faceTranspose)") {
                            stepper(faceTranspose, -24, 24) { v in
                                if isB { onEdit { $0.transposeB = v } } else { onTranspose(v) }
                            }
                        }
                    }
                    typeParams(ft)
                    if !slotMode && isB && glides {      // morph glides A↔B; only meaningful for a FULL B
                        field("MORPH \(Int(colour.morph * 100))%  → B") {
                            Slider(value: Binding(get: { colour.morph }, set: { onMorph($0) }), in: 0...1).tint(accent)
                        }
                    }
                } else {
                    Text("no B — pick a type or PASTE to add a second processor")
                        .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.4)).padding(.top, 4)
                }
            }
            if !slotMode { Spacer(minLength: 0) }
        }
        // slotMode sizes to content (no clipping — the always-visible radio rows must all show); the old
        // Colour-desk face keeps its FIXED frame (static-frames rule).
        .padding(slotMode ? 14 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FixedHeightIf(height: slotMode ? nil : height))
        .opacity(slotBypassed ? 0.45 : (mixed ? 0.55 : 1))   // CELL MACHINE: a bypassed slot dims; MIXED-SET dims too
        .disabled(mixed)                                  // …and block any stray hit (controls aren't rendered anyway)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }

    // MIXED-SET law: the selection spans more than one Colour, so there is no single Colour-level edit to
    // honour — say so plainly rather than editing the brush behind the user's back. Cell-level edits
    // (routing, emitters, delete) still act on the whole set; only this panel goes inert.
    private var mixedFace: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MIXED").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            Text("selection spans multiple Colours — select ONE Colour to edit its processor.")
                .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4).frame(maxWidth: .infinity, alignment: .leading)
    }

    // B1 TITLE-AS-PICKER: [EMBLEM] TYPE ▾ · COPY · PASTE — tap the type to open the picker popover.
    private var titleRow: some View {
        HStack(spacing: 5) {
            Button { if !mixed { showTypePicker = true } } label: {
                HStack(spacing: 6) {
                    if let ft = faceType { Image(systemName: emblemSymbol(ft)).font(.system(size: 17, weight: .black)) }
                    Text(faceType.map { typeShort($0) } ?? "OFF").font(.system(size: 17, weight: .heavy, design: .monospaced))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy)).opacity(0.7)
                }
                .foregroundColor(accent)
            }
            .buttonStyle(.plain).disabled(mixed)
            Spacer()
            if slotMode {                                   // CELL MACHINE: per-slot BYPASS (+ REMOVE) instead of COPY/PASTE
                pill(slotBypassed ? "BYPASSED" : "BYPASS", onBypass)
                if let onRemove { pill("✕", onRemove) }
            } else {
                if !mixed && faceType != nil { pill("COPY", onCopy) }
                if !mixed && canPaste { pill("PASTE", onPaste) }
            }
        }
        .popover(isPresented: $showTypePicker) { typePicker }
    }

    // The TYPE PICKER — one row per type (emblem · NAME · one-line description). Panel B leads with OFF.
    private var typePicker: some View {
        let rows: [ProcessorType?] = (isB ? [ProcessorType?.none] : []) + ProcessorType.allCases.map { Optional($0) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, t in
                Button {
                    if let t { if isB { onEdit { $0.typeB = t } } else { onSetTypeA?(t) } }
                    else { onEdit { $0.typeB = nil } }          // OFF (B only)
                    showTypePicker = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: t.map { emblemSymbol($0) } ?? "nosign").font(.system(size: 14, weight: .black)).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.map { typeShort($0) } ?? "OFF").font(.system(size: 12, weight: .heavy, design: .monospaced))
                            Text(t.map { typeDescription($0) } ?? "no B-side").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 240).padding(.vertical, 4)
    }
    private func typeDescription(_ t: ProcessorType) -> String {
        switch t {
        case .arp:       return "arpeggiate the held chord"
        case .ratchet:   return "re-trigger in bursts per step"
        case .passgate:  return "a gate the sound passes through"
        case .strum:     return "roll the chord in over a spread"
        case .chance:    return "let notes through by probability"
        case .harmonize: return "add tuned voices to each note"
        }
    }

    private func pill(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(accent)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.2)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    @ViewBuilder private func typeParams(_ ft: ProcessorType) -> some View {
        switch ft {
        case .arp:
            field("PATTERN") { seg(ArpPattern.allCases.map(\.rawValue), sel: p.pattern?.rawValue ?? "UP") { i in
                setParam { $0.pattern = ArpPattern.allCases[i] } } }
            field("RATE") { seg(ArpRate.allCases.map(\.rawValue), sel: p.rate?.rawValue ?? "1/16") { i in
                setParam { $0.rate = ArpRate.allCases[i] } } }
            HStack(spacing: 8) {
                field("OCT") { seg(["1","2","3","4"], sel: "\(p.octaves ?? 1)") { i in
                    setParam { $0.octaves = i + 1 } } }
                field("PHASE") { seg(ArpPhase.allCases.map(\.rawValue), sel: p.phase?.rawValue ?? "RETRIG") { i in
                    setParam { $0.phase = ArpPhase.allCases[i] } } }
            }
            field("GATE \(Int((p.gate ?? 0.6) * 100))%") {
                Slider(value: bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1).tint(accent)
            }
        case .ratchet:
            field("REPEATS") { seg(["2","3","4","6","8"], sel: "\(p.count ?? 3)") { i in
                setParam { $0.count = [2,3,4,6,8][i] } } }
            field("RAMP \(Int((p.ramp ?? 0.5) * 100))%") {
                Slider(value: bind(p.ramp ?? 0.5) { v in setParam { $0.ramp = v } }, in: 0...1).tint(accent)
            }
        case .passgate:
            field("PASSES") { HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    let on = (p.passes ?? [true,true,true,true])[i]
                    let head = i == passHead                 // MODE ROW: the playhead sits on the live pass
                    Text("\(i+1)").font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent : Color.white.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(head ? Color.white : .clear, lineWidth: 3))   // the playhead ring
                        .contentShape(Rectangle())
                        .onTapGesture { setParam { var pp = $0.passes ?? [true,true,true,true]; pp[i].toggle(); $0.passes = pp } }
                }
            } }
        case .strum:
            field("DIR") { seg(StrumDir.allCases.map(\.rawValue), sel: (p.strumDir ?? .up).rawValue) { i in
                setParam { $0.strumDir = StrumDir.allCases[i] } } }
            field("SPREAD \(Int((p.spread ?? 0.1) * 100))") {
                Slider(value: bind(p.spread ?? 0.1) { v in setParam { $0.spread = v } }, in: 0...1).tint(accent) }
            field("TILT \(Int((p.velTilt ?? 0) * 100))") {
                Slider(value: bind((p.velTilt ?? 0) / 2 + 0.5) { v in setParam { $0.velTilt = (v - 0.5) * 2 } }, in: 0...1).tint(accent) }
        case .chance:
            field("PROBABILITY \(Int((p.probability ?? 1) * 100))%") {
                Slider(value: bind(p.probability ?? 1) { v in setParam { $0.probability = v } }, in: 0...1).tint(accent) }
        case .harmonize:
            let iv = p.harmIntervals ?? [0,0,0]
            ForEach(0..<3, id: \.self) { k in
                field("VOICE \(k+1) \(iv[k] == 0 ? "off" : (iv[k] > 0 ? "+\(iv[k])" : "\(iv[k])"))") {
                    stepper(iv[k], -24, 24) { v in setParam { var a = $0.harmIntervals ?? [0,0,0]; a[k] = v; $0.harmIntervals = a } }
                }
            }
        }
    }

    // ---- small controls ----
    private func typeShort(_ t: ProcessorType) -> String { t.rawValue }   // FULL name (user 2026-07-30 — no abbreviations)
    private func bind(_ v: Double, _ set: @escaping (Double) -> Void) -> Binding<Double> {
        Binding(get: { v }, set: set)
    }
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
            content()
        }
    }
    // MODE ROW (device round 2): an enum field is an ALWAYS-VISIBLE RADIO ROW — every option shown, the selected
    // one filled. No dropdown; nothing hidden. Wraps to a second line when the options don't fit one row.
    private func seg(_ options: [String], sel: String, _ onPick: @escaping (Int) -> Void) -> some View {
        let rows = radioRows(options.count)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, span in
                HStack(spacing: 6) {
                    ForEach(span, id: \.self) { i in
                        let on = options[i] == sel
                        Text(options[i]).font(.system(size: 15, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : accent).lineLimit(1).minimumScaleFactor(0.55)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 7).fill(on ? accent : Color.white.opacity(0.09)))
                            .contentShape(Rectangle()).onTapGesture { onPick(i) }
                    }
                }
            }
        }
    }
    // Split N options into rows of at most 4 (keeps each segment finger-sized on a full-width box).
    private func radioRows(_ n: Int) -> [[Int]] {
        let per = n <= 4 ? n : Int(ceil(Double(n) / ceil(Double(n) / 4.0)))
        var out: [[Int]] = []; var i = 0
        while i < n { out.append(Array(i..<min(i + max(1, per), n))); i += max(1, per) }
        return out
    }
    private func stepper(_ v: Int, _ lo: Int, _ hi: Int, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Text("−").font(.system(size: 20, weight: .heavy)).foregroundColor(.white.opacity(0.8))
                .frame(width: 46, height: 42).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                .contentShape(Rectangle()).onTapGesture { set(max(lo, v - 1)) }
            Text("\(v)").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.95)).frame(minWidth: 48)
            Text("+").font(.system(size: 20, weight: .heavy)).foregroundColor(.white.opacity(0.8))
                .frame(width: 46, height: 42).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                .contentShape(Rectangle()).onTapGesture { set(min(hi, v + 1)) }
            Spacer()
        }
    }
}

// MARK: - Routing visualisation overlay (while any verb is held)

/// The three band frames (receivers · grid · emitters), measured in the "signal" coordinate space, so the
/// viz overlay can map routing anchors → screen points.
struct RouteFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

/// Curved white béziers for the routing graph, spanning receivers → grid → emitters. A path that runs through
/// a SELECTED cell is bright + pulsing; the rest are dim-but-visible. Anchors come from the measured band
/// frames + the grid geometry. Watch-only (no hit-testing). Live — it redraws from `edges` each render, so a
/// placed / moved / deleted / re-wired cell updates it.
struct RoutingVizOverlay: View {
    @Environment(\.animationsPaused) private var animPaused
    let edges: [RouteEdge]
    let frames: [String: CGRect]
    let cellHeight: CGFloat

    // --- grid geometry within the measured grid frame ---
    private func cellW(_ g: CGRect) -> CGFloat { (g.width - 7 * GridGeometry.vGap) / 8 }
    private func cellCenter(_ c: RouteCell, _ g: CGRect) -> CGPoint {
        let gap = GridGeometry.vGap, w = cellW(g)
        return CGPoint(x: g.minX + CGFloat(c.col) * (w + gap) + w / 2,
                       y: g.minY + (cellHeight + gap) + CGFloat(c.row) * (cellHeight + gap) + cellHeight / 2)   // past the column-key row
    }
    private func cellRect(_ col: Int, _ row: Int, _ g: CGRect) -> CGRect {
        let ctr = cellCenter(RouteCell(col: col, row: row), g), w = cellW(g)
        return CGRect(x: ctr.x - w / 2, y: ctr.y - cellHeight / 2, width: w, height: cellHeight)
    }
    // An edge connects to a cell at its TOP (a route arriving) or BOTTOM (a route leaving) — never the centre —
    // so lines meet cells at their edges (marked by dots) instead of crossing their bodies. Receivers anchor at
    // the strip bottom, emitters at the strip top.
    private func endpoint(_ a: RouteAnchor, source: Bool, _ g: CGRect) -> CGPoint? {
        switch a {
        case .receiver(let i): guard let f = frames["receivers"] else { return nil }; return CGPoint(x: f.minX + (CGFloat(i) + 0.5) / 4 * f.width, y: f.maxY)
        case .emitter(let i):  guard let f = frames["emitters"] else { return nil };  return CGPoint(x: f.minX + (CGFloat(i) + 0.5) / 4 * f.width, y: f.minY)
        case .cell(let c):     let ctr = cellCenter(c, g); return CGPoint(x: ctr.x, y: source ? ctr.y + cellHeight / 2 : ctr.y - cellHeight / 2)
        }
    }
    private func column(of e: RouteEdge) -> Int {
        if case .cell(let c) = e.from { return c.col }; if case .cell(let c) = e.to { return c.col }; return 0
    }
    // Occupied cells the route only PASSES (same column, strictly between its endpoints) — clipped out so the
    // line never renders over a cell it doesn't connect to.
    private func crossedRows(_ e: RouteEdge, occ: [Int: Set<Int>]) -> [Int] {
        let rows = occ[column(of: e)] ?? []
        func r(_ a: RouteAnchor) -> Int? { if case .cell(let c) = a { return c.row }; return nil }
        if let a = r(e.from), let b = r(e.to) { let lo = min(a, b), hi = max(a, b); return rows.filter { $0 > lo && $0 < hi } }
        if let b = r(e.to)   { return rows.filter { $0 < b } }   // receiver → cell: cells above it
        if let a = r(e.from) { return rows.filter { $0 > a } }   // cell → emitter: cells below it
        return []
    }
    private func ctrls(_ p0: CGPoint, _ p1: CGPoint, _ laneX: CGFloat) -> (CGPoint, CGPoint) {
        (CGPoint(x: laneX, y: p0.y + (p1.y - p0.y) * 0.34), CGPoint(x: laneX, y: p0.y + (p1.y - p0.y) * 0.66))
    }
    private func routePath(_ p0: CGPoint, _ p1: CGPoint, _ laneX: CGFloat) -> Path {
        let (c1, c2) = ctrls(p0, p1, laneX); var p = Path(); p.move(to: p0); p.addCurve(to: p1, control1: c1, control2: c2); return p
    }
    private func routePoint(_ p0: CGPoint, _ p1: CGPoint, _ laneX: CGFloat, _ t: CGFloat) -> CGPoint {
        let (c1, c2) = ctrls(p0, p1, laneX), u = 1 - t
        return CGPoint(x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p1.x,
                       y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p1.y)
    }

    var body: some View {
        // occupancy + per-column LANES (so parallel vertical routes don't coincide), plus which receivers /
        // emitters and cell edges carry a route — all computed off the animation clock, from the edge list.
        var occ: [Int: Set<Int>] = [:]
        for e in edges { for a in [e.from, e.to] { if case .cell(let c) = a { occ[c.col, default: []].insert(c.row) } } }
        var lane = [Int](repeating: 0, count: edges.count), laneN = [Int](repeating: 1, count: edges.count)
        var colEdges: [Int: [Int]] = [:]
        for (i, e) in edges.enumerated() { colEdges[column(of: e), default: []].append(i) }
        for (_, idxs) in colEdges { for (k, idx) in idxs.enumerated() { lane[idx] = k; laneN[idx] = idxs.count } }
        var usedRecv = Set<Int>(), usedEmit = Set<Int>(), recvDot = Set<RouteCell>(), emitDot = Set<RouteCell>()
        for e in edges {
            if case .receiver(let r) = e.from { usedRecv.insert(r); if case .cell(let c) = e.to { recvDot.insert(c) } }
            if case .emitter(let m) = e.to { usedEmit.insert(m); if case .cell(let c) = e.from { emitDot.insert(c) } }
        }

        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: animPaused)) { tl in
            let pulse = stagingPulseFraction(tl.date, period: 1.4)
            let now = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                guard let g = frames["grid"] else { return }
                let step = min(CGFloat(7), cellW(g) * 0.24)
                func render(_ i: Int) {
                    let e = edges[i]
                    guard let p0 = endpoint(e.from, source: true, g), let p1 = endpoint(e.to, source: false, g) else { return }
                    let laneX = (p0.x + p1.x) / 2 + (CGFloat(lane[i]) - CGFloat(laneN[i] - 1) / 2) * step
                    var c = ctx                                     // clip the route OUT of any cell it merely crosses
                    let crossed = crossedRows(e, occ: occ)
                    if !crossed.isEmpty {
                        var holes = Path(); for r in crossed { holes.addRect(cellRect(column(of: e), r, g)) }
                        c.clip(to: holes, options: .inverse)
                    }
                    // receiver → cell / cell → emitter: a curved flow line + a MIDI comet (head + fading tail).
                    // (grid-chaining retired → no cell→cell edges; every edge is a receiver or emitter flow now.)
                    c.stroke(routePath(p0, p1, laneX), with: .color(.white.opacity(e.lit ? (0.5 + 0.4 * pulse) : 0.14)), lineWidth: e.lit ? 2.0 : 1.0)
                    let speed = e.lit ? 0.55 : 0.32, phase = Double(i % 9) / 9.0
                    let head = CGFloat((now * speed + phase).truncatingRemainder(dividingBy: 1.0))
                    for k in 0..<6 {
                        let t = head - CGFloat(k) * 0.03; guard t >= 0 else { continue }
                        let pt = routePoint(p0, p1, laneX, t), fade = 1 - CGFloat(k) / 6, r = (e.lit ? 3.2 : 1.7) * fade
                        c.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity((e.lit ? 1.0 : 0.45) * fade)))
                    }
                }
                for i in edges.indices where !edges[i].lit { render(i) }   // dim underneath
                for i in edges.indices where edges[i].lit { render(i) }    // bright on top
                // LARGE dots at every receiver / emitter carrying a route; small dots where a curved flow meets a cell.
                func bigDot(_ p: CGPoint) { ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white.opacity(0.95))) }
                func smallDot(_ p: CGPoint) { ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.white.opacity(0.9))) }
                if let f = frames["receivers"] { for r in usedRecv { bigDot(CGPoint(x: f.minX + (CGFloat(r) + 0.5) / 4 * f.width, y: f.maxY)) } }
                if let f = frames["emitters"]  { for m in usedEmit { bigDot(CGPoint(x: f.minX + (CGFloat(m) + 0.5) / 4 * f.width, y: f.minY)) } }
                for cc in recvDot { let ctr = cellCenter(cc, g); smallDot(CGPoint(x: ctr.x, y: ctr.y - cellHeight / 2)) }
                for cc in emitDot { let ctr = cellCenter(cc, g); smallDot(CGPoint(x: ctr.x, y: ctr.y + cellHeight / 2)) }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cell-edit STAGING (user 2026-07-25) — long-press a colour → configure a pending cell in the
// side panels (EDIT only). The RECEIVERS panel becomes the cell's INPUT picker (R1–R4 radio + a FROM ROW
// option), the EMITTERS panel its OUTPUT buses. Ephemeral (a StampConfig), recalled across enter/exit.
// The render-path live-preview drag-to-grid is DEFERRED to the design spec — this is the panel scaffold.

private let stagingCyan = Color(red: 0.15, green: 0.88, blue: 0.94)
private let stagingAmber = Color(red: 0.98, green: 0.72, blue: 0.12)

/// A 0→1→0 breathing fraction for the staging pulses (chip, empty-cell border, placed-cell fill) — one
/// cosine so every pulse shares the same rhythm. `period` in seconds.
func stagingPulseFraction(_ date: Date, period: Double) -> Double {
    0.5 - 0.5 * cos(date.timeIntervalSinceReferenceDate * 2 * .pi / period)
}

/// Marching-ants animated dashed border — the "prominent moving outline" marking a panel in cell-edit
/// state. Pure UI (an animated dashPhase); no render-path involvement.
struct MarchingAnts: ViewModifier {
    @Environment(\.animationsPaused) private var animPaused
    var active: Bool
    var color: Color
    var cornerRadius: CGFloat = 6
    var lineWidth: CGFloat = 2
    func body(content: Content) -> some View {
        content.overlay {
            if active {
                // Drive the dash phase off the clock (TimelineView), not withAnimation — animating
                // StrokeStyle.dashPhase via withAnimation doesn't march reliably; a per-frame phase does.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
                    let period = 0.6                                   // seconds per 11pt dash cycle (7 on + 4 off)
                    let phase = -11 * CGFloat(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(color, style: StrokeStyle(lineWidth: lineWidth, dash: [7, 4], dashPhase: phase))
                }
            }
        }
    }
}
extension View {
    func marchingAnts(_ active: Bool, color: Color = stagingCyan, cornerRadius: CGFloat = 6, lineWidth: CGFloat = 2) -> some View {
        modifier(MarchingAnts(active: active, color: color, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}

//  GridUI.swift
//  MidiSpark — the 8×8 grid view (four-row cell) + palette + RECEIVERS/OUTPUTS panels + the CELL EDITOR.
//  Editing (delta §5 rev 2): in EDIT the whole pad is ONE tap target that opens the floating CELL EDITOR
//  (input · colour · emitters · actions); body long-press auditions (stopped); PERFORM tap flips ALT. The
//  old FROM/OUT popovers + tap-paint + hold-menu are retired (folded into the editor). Every edit goes
//  through MidiSparkAudioUnit.editScene/editDocument → scheduleRebuild. Tokens per docs/ui-port-guide.md.

import SwiftUI
import UIKit   // for UIColor (the old multi-touch ColumnHoldOverlay UIView that needed this is gone)

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
    0x5566FF, 0x38A6FF, 0x25E0F0, 0x148F80, 0x7BF2CE, 0x2ECC5E, 0xC6F23D, 0x4C6E8F,   // [15] SLATE (was BRONZE 0xC9A227 — too close to GOLD, user 2026-08-09)
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

// BUILD's STAGE-THE-GRID variations are REAL colour IDs given a custom hue near their source (a new, distinguishable
// colour — not a shade drawn over the source). Session-scoped, like the rest of the BUILD workspace. (Paul 2026-08-15)
var colourHueOverride: [String: UInt32] = [:]
func colourColor(_ id: String) -> Color? {
    if let hex = colourHueOverride[id] { return Color(hex: hex) }
    return colourIDs.firstIndex(of: id).map { Color(hex: colourHexes[$0]) }
}

private let accentCyan = UI.cyan   // playhead / PERFORM accent

// v56 theme tokens (mockup `T`): cell recess, edges, dim ink.
private let cellBg = Color(hex: 0x0B0D11)
private let cellEdge = Color(hex: 0x20242D)

/// The 8×8 grid — v56 FOUR-ROW cell (delta §4): input header · type+params body · emitter strip;
/// empty cells show a row-number watermark. `scene.cells` is [column][row]. `colours` maps a cell's
/// colourID → its type/params for the body text.
struct GridView: View {
    @Environment(\.animationsPaused) private var animPaused
    let scene: SceneState
    let colours: [Colour]
    let playColumn: Int
    var trueColumn: Int = -1     // the LINEAR scene column (absoluteStep % 8); dimly lit while looping so the position still reads
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
    var laneHue: Color = accentCyan                  // the COLUMN SELECTOR tint — GRID mode colour (SINGLE green · MULTI yellow), user 2026-08-05
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
    var cellStrikeSeq: [Int] = []                    // MOSAIC: per-cell moment counter (each strike moment → the next rectangle)
    var cellNotePitch: [UInt8] = []                  // NOTE-SWEEP: per-cell recent emitted note pitches (6 slots/cell)
    var cellNoteVel: [UInt8] = []                    // NOTE-SWEEP: their velocities
    var cellNoteCount: [UInt8] = []                  // NOTE-SWEEP: how many notes each cell emitted since the last poll (0–6)
    var dropHoverCell: GridPos? = nil                // §5: the cell under a palette drag (highlight the drop target)
    var staging: Bool = false                        // cell-edit staging: EMPTY cells pulse a border to invite tap-to-place
    var stagingColor: Color = stagingCyan            // the staged Colour's own hue (the pulse colour)
    var stagedCells: Set<GridPos> = []               // cells placed this staging session: pulse colour↔black; gate the empty flash
    var hiddenPending: GridPos? = nil                // a just-hidden cell in its undo window: ring in its own colour, tap to restore
    var whiteBorder: Set<GridPos> = []               // §11 PLACE: cells placed this hold — a white "selected" border
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
    // THE PIANO-ROLL FACE (Paul 2026-08-19): each strike MOMENT (cellStrikeSeq) births a scrolling note mark per cell.
    struct RollNote: Equatable { var born: Date; var vel: Double; var lane: Double }
    @State private var cellRoll: [[RollNote]] = Array(repeating: [], count: 64)
    @State private var rollPrevSeq: [Int] = Array(repeating: 0, count: 64)
    private static let rollLife = 1.6                 // seconds a note takes to cross the cell (gentle)
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
        .coordinateSpace(name: "grid")                   // §5 drag-and-drop: maps a drag location → a cell
        .simultaneousGesture(strokeGesture)              // STROKES: drag-paint while a verb is held
        .background(GeometryReader { g in Color.clear.onAppear { gridSize = g.size }.onChange(of: g.size) { gridSize = $0 } })
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { breathe = true } }
        .onChange(of: beat) { newBeat in lastBeat = newBeat; lastBeatAt = Date(); rollPrune() }
        .onChange(of: cellStrikeSeq) { seqs in rollAccumulate(seqs) }   // PIANO-ROLL: a strike moment → a new scrolling note
        .onChange(of: playing) { p in if !p { cellRoll = Array(repeating: [], count: 64); rollPrevSeq = Array(repeating: 0, count: 64) } }   // transport stop → clear the rolls (idle cells rest)
    }

    // Fold each new strike MOMENT into its cell's roll. With the NOTE-SWEEP feed we place one mark PER emitted note at
    // its REAL pitch lane (a chord → a vertical stack); without it, fall back to one mark at a hashed lane. Cap per cell.
    private func rollAccumulate(_ seqs: [Int]) {
        guard usePianoRollFace else { return }
        let now = Date(); var roll = cellRoll; var changed = false
        for i in 0..<min(64, seqs.count) where i < rollPrevSeq.count && seqs[i] > rollPrevSeq[i] {
            let cnt = i < cellNoteCount.count ? Int(cellNoteCount[i]) : 0
            if cnt > 0 {                                         // REAL pitch: one mark per emitted note
                for k in 0..<min(cnt, 6) where i * 6 + k < cellNotePitch.count {
                    let nv = i * 6 + k < cellNoteVel.count ? Double(cellNoteVel[i * 6 + k]) / 127.0 : 0.6
                    roll[i].append(RollNote(born: now, vel: nv, lane: rollLaneForPitch(Int(cellNotePitch[i * 6 + k]))))
                }
            } else {                                             // fallback (no note feed yet): one mark at a hashed lane
                let vel = i < cellHitVel.count ? cellHitVel[i] : 0.6
                let h = Double((UInt64(bitPattern: Int64(i &* 2654435761 &+ seqs[i] &* 40503)) >> 8) & 0xFF) / 255.0
                roll[i].append(RollNote(born: now, vel: vel, lane: 0.2 + 0.6 * h))
            }
            if roll[i].count > 16 { roll[i].removeFirst(roll[i].count - 16) }
            changed = true
        }
        if changed { cellRoll = roll }
        rollPrevSeq = seqs
    }
    // Drop notes that have crossed the cell (so an idle cell's roll empties → its TimelineView pauses). Runs on the beat poll.
    private func rollPrune() {
        guard usePianoRollFace else { return }
        let now = Date(); var roll = cellRoll; var changed = false
        for i in 0..<roll.count {
            let before = roll[i].count
            roll[i].removeAll { now.timeIntervalSince($0.born) > Self.rollLife }
            if roll[i].count != before { changed = true }
        }
        if changed { cellRoll = roll }
    }

    // v57 PROMINENT COLUMN KEYS — a numbered 40px key per column; the active one lights while playing.
    // The master playhead arrow sweeps across the top of this row (delta §4, one-clock). The column-hold
    // LAP gesture (§5b) will attach here later; the tap-to-mute interaction was removed pending the spec.
    private var columnKeys: some View {
        HStack(spacing: Self.vGap) {
            ForEach(0..<8, id: \.self) { col in
                let active = playing && col == playColumn
                let held = (laneMask & (1 << UInt8(col))) != 0     // §5b lap: this column is in the held (loop) set
                // TRUE-PLAYHEAD DIM (user 2026-08-06): while looping, the linear scene position still steps through the
                // headers DIMLY so you know where you are (the ▼ playhead is gone). The ACTIVE (playing) column always
                // wins — a dim mark only shows on the true column when it isn't the one currently playing.
                let trueLit = playing && col == trueColumn && !active
                Image(systemName: held ? "repeat" : "chevron.down")   // column key — LOOP glyph when in the set, else a down chevron
                    .font(.system(size: held ? 12 : 15, weight: .heavy))
                    .foregroundColor(active ? .black : laneHue)            // GRID mode tint (SINGLE green · MULTI yellow); playhead = black
                    .frame(maxWidth: .infinity).frame(height: cellHeight)   // key row = a cell's height (user 2026-07-26)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(active ? accentCyan : (trueLit ? accentCyan.opacity(0.28) : laneHue.opacity(0.10))))   // active = cyan · true-playhead = dim cyan · else the mode tint
                    .overlay(RoundedRectangle(cornerRadius: 6)                 // LOOP state = held key ring (§5b)
                        .stroke(held ? laneHue : .clear, lineWidth: 2).padding(1))
                    .contentShape(Rectangle())
                    // HARD RULE (user 2026-08-08): ANY gesture on a column selector toggles that column in the LOOP
                    // set, regardless of mode/page — ONE code path (tap + long-press → onColumnKey), no separate
                    // multi-touch overlay. Other looped columns persist alongside it.
                    .onTapGesture { onColumnKey?(col) }
                    .onLongPressGesture(minimumDuration: 0.3) { onColumnKey?(col) }
            }
        }
    }

    // (Master playhead ARROW retired 2026-08-06 — the sweeping ▼ across the key row is gone; the active column's
    //  lit key still marks the current column.)

    // (Per-cell MUTATION line retired 2026-08-06 — the downward falling playhead on the cells is gone; the master
    //  column arrow at the top of the key row remains the one-clock cue.)

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
                if usePianoRollFace {
                    // THE PIANO-ROLL FACE — note marks drift right→left as the cell sounds (identity = the hue).
                    pianoRollFace(col * 8 + row)
                } else {
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
                }
            } else if showAddPlus {          // MODE ROW · ADD/EDIT with a selection: a faint "+" invites adding this empty cell
                Image(systemName: "plus").font(.system(size: 18, weight: .heavy)).foregroundColor(.white.opacity(0.22))
            }   // §quieting (2026-08-02): otherwise an empty cell is NEAR-SILENT — bare faint rect
        }
        .opacity(removeMarks.contains(GridPos(col: col, row: row)) ? 0.3          // MODE ROW · CLEAR: a marked cell recedes
                 : ladderArmed.contains(GridPos(col: col, row: row)) ? (ladderBlink ? 1.0 : 0.4)   // LADDER: an armed rung BLINKS
                 : ladderDim.contains(GridPos(col: col, row: row)) ? 0.28         // LADDER: a dormant rung dims (silent, still visible)
                 : (tapMutedHere || raw?.muted == true) ? 0.28 : 1)               // muted dims; otherwise cells stay full
        .overlay {                                          // MODE ROW · CLEAR: a marked cell wears a dashed red ring + an ✕
            if removeMarks.contains(GridPos(col: col, row: row)) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(red: 0.95, green: 0.25, blue: 0.28), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    Image(systemName: "xmark").font(.system(size: 16, weight: .black)).foregroundColor(Color(red: 0.95, green: 0.35, blue: 0.38))
                }.allowsHitTesting(false)
            }
        }
        // (twin advertise-PULSE removed 2026-08-07 — twins now auto-JOIN the selection; the user deselects to decouple.)
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
                routeLabel("IN", UI.cyan)
            } else if routeOut.contains(pos) {              // a cell below → tap makes it an OUTPUT of the focus
                routeLabel("OUT", Color(red: 0.35, green: 0.92, blue: 0.50))
            } else if whiteBorder.contains(pos) {
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
    // THE PIANO-ROLL FACE (Paul 2026-08-19) — over the cell's HUE, soft white note marks enter at the RIGHT AS the cell
    // sounds and drift left, fading; nothing at rest. Gentle + non-distracting. Cheap: ≤12 rounded bars, one Canvas,
    // paused when the cell has no live notes. (Pitch isn't fed per-cell yet — the lane is a stable per-note hash.)
    @ViewBuilder private func pianoRollFace(_ idx: Int) -> some View {
        let notes = (idx >= 0 && idx < cellRoll.count) ? cellRoll[idx] : []
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused || notes.isEmpty)) { tl in
            let now = tl.date
            Canvas { ctx, size in
                let barW = size.width * 0.17, barH = max(2.5, size.height * 0.085)
                for n in notes {
                    let age = now.timeIntervalSince(n.born)
                    if age < 0 || age > Self.rollLife { continue }
                    let prog = age / Self.rollLife                       // 0 (right, just sounded) → 1 (left, gone)
                    let x = CGFloat(1 - prog) * size.width               // notes enter at the RIGHT and drift LEFT (Paul 2026-08-19)
                    let y = CGFloat(1 - n.lane) * size.height
                    let fade = min(1.0, prog / 0.10) * min(1.0, (1 - prog) / 0.45)   // ease in at the right, out at the left
                    let a = max(0.0, min(1.0, fade)) * (0.4 + 0.55 * n.vel)
                    let rect = CGRect(x: x - barW / 2, y: y - barH / 2, width: barW, height: barH)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barH / 2), with: .color(.white.opacity(a * 0.9)))
                }
            }
        }
        .padding(4).frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
    }

    @ViewBuilder private func sealComet(_ geo: SealGeometry, _ idx: Int) -> some View {
        let hitAt = (idx >= 0 && idx < cellHitAt.count) ? cellHitAt[idx] : Date.distantPast
        let vel = (idx >= 0 && idx < cellHitVel.count) ? cellHitVel[idx] : 0
        let sounding = (idx >= 0 && idx < cellSounding.count) ? cellSounding[idx] : false
        let releasedAt = (idx >= 0 && idx < cellReleasedAt.count) ? cellReleasedAt[idx] : Date.distantPast
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animPaused)) { tl in
            Canvas { ctx, size in
                let strikeAge = tl.date.timeIntervalSince(hitAt)
                let releaseAge = tl.date.timeIntervalSince(releasedAt)
                // STOP when the playhead leaves the column (user 2026-08-05). The spark TRAVELS only while the note
                // SOUNDS; once it lets go it FREEZES in place and fades — no extra pass. A tracked release fades fast
                // (~0.45s); a pluck the 4Hz gate never caught sounding still flashes a brief frozen spark (~0.5s).
                let hasRelease = releasedAt > hitAt
                let life = sounding ? 1.0
                                    : (hasRelease ? max(0.0, 1 - releaseAge / 0.45)
                                                  : max(0.0, 1 - strikeAge / 0.5))
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
                // TRAVEL only while sounding (a new strike never resets the free-run); once the note lets go, FREEZE
                // the spark's clock — at the release, or at the STRIKE for a pluck the gate never caught sounding — so
                // it fades IN PLACE. This is the fix: short single-column notes (whose release the 4Hz gate misses)
                // no longer free-run an extra fraction of the path after the playhead has left.
                let clock = sounding ? tl.date.timeIntervalSinceReferenceDate
                                     : (hasRelease ? releasedAt : hitAt).timeIntervalSinceReferenceDate
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
    var onMacro: (() -> Void)? = nil                    // slotMode: the MACRO button → the authoring flow (spec macro-authoring)
    var plainTitle: Bool = false                        // pop-up: show the type as a plain TITLE (no type-picker button)
    var showSlotChrome: Bool = true                     // slotMode: draw the built-in title row (name + BYPASS/✕ pills). BUILD hides it and supplies its own large Delete/Bypass header.
    @State private var showTypePicker = false           // B1: the title-as-picker popover
    @State private var tuttiPaint: TuttiSlice = .low     // TUTTI PATTERN: the brush shape — defaults to LOW so it CONTRASTS with the all-ALL slices (first tap visibly paints)
    @State private var burstPaint: BurstSlice = .carry   // BURST PATTERN: the brush (defaults to CARRY — the novel state — so a first tap visibly paints)
    @State private var lenPaint: LenState = .mute        // LENGTH: the brush — defaults to MUTE so it contrasts with the all-PASS slices (first tap carves a visible rest)
    @State private var weaveBrush: StepRate = .r1_8      // WEAVE DRAWN: the rate loaded on the brush
    @State private var rtcBrush: Int = 3                 // RATCHET PATTERN: the count loaded on the brush (0 = plain)

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
            if !slotMode || showSlotChrome { titleRow }   // BUILD supplies its own header → hide the built-in title row
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
            if plainTitle {                                 // pop-up: the type is fixed — show it as a TITLE, not a picker
                HStack(spacing: 6) {
                    if let ft = faceType { Image(systemName: emblemSymbol(ft)).font(.system(size: 17, weight: .black)) }
                    Text(faceType.map { typeShort($0) } ?? "OFF").font(.system(size: 17, weight: .heavy, design: .monospaced))
                }.foregroundColor(accent)
            } else {
                Button { if !mixed { showTypePicker = true } } label: {
                    HStack(spacing: 6) {
                        if let ft = faceType { Image(systemName: emblemSymbol(ft)).font(.system(size: 17, weight: .black)) }
                        Text(faceType.map { typeShort($0) } ?? "OFF").font(.system(size: 17, weight: .heavy, design: .monospaced))
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy)).opacity(0.7)
                    }
                    .foregroundColor(accent)
                }
                .buttonStyle(.plain).disabled(mixed)
            }
            Spacer()
            if slotMode {                                   // CELL MACHINE: per-slot MACRO · BYPASS (+ REMOVE) instead of COPY/PASTE
                if let onMacro { pill("MACRO", onMacro) }
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
        case .echo:      return "repeat the note at a delay, decaying"
        case .euclid:    return "spread K hits evenly across N steps"
        case .burst:     return "a one-shot accelerating/decelerating roll"
        case .cascade:   return "reveal the chord one note at a time"
        case .drone:     return "a flat sustained pad, held to the boundary"
        case .shift:     return "nudge the chord late — behind the beat"
        case .humanize:  return "seeded per-note timing + velocity jitter"
        case .mod:       return "a shaped CC on the emitters (sounds no notes)"
        case .glide:     return "one sliding voice — steps glide, leaps re-strike"
        case .tutti:     return "per step: one note (SOLO) or the whole chord (TUTTI)"
        case .length:    return "shape how long each note sounds, per slice"
        case .weave:     return "each held note pulses on its own clock — a polyrhythm"
        case .split:     return "keep only part of the chord (top / bottom / range / velocity)"
        case .octave:    return "shift this chain up or down by whole octaves"
        case .transpose: return "shift this chain by semitones (moves notes off the held chord)"
        case .channel:   return "send this chain out on a chosen MIDI channel"
        case .nudge:     return "slide this chain earlier or later in time"
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
            field("SPEED") { seg(ArpRate.allCases.map(\.rawValue), sel: p.rate?.rawValue ?? "1/16") { i in
                setParam { $0.rate = ArpRate.allCases[i] } } }
            HStack(spacing: 8) {
                field("OCTAVES") { seg(["1","2","3","4"], sel: "\(p.octaves ?? 1)") { i in
                    setParam { $0.octaves = i + 1 } } }
                field("NEW CHORD") { seg(ArpPhase.allCases.map(\.rawValue), sel: p.phase?.rawValue ?? "RETRIG") { i in
                    setParam { $0.phase = ArpPhase.allCases[i] } } }
            }
            field("LENGTH \(Int((p.gate ?? 0.6) * 100))%") {
                Slider(value: bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1).tint(accent)
            }
            field("FIT 1 BEAT") { seg(["OFF", "ON"], sel: (p.arpFit ?? false) ? "ON" : "OFF") { i in setParam { $0.arpFit = (i == 1) } } }
        case .ratchet:
            let rmode = p.rtcMode ?? .all      // mode set by the storefront card — no in-editor radio (Paul 2026-08-22)
            if rmode == .all {
                field("REPEATS") { seg(["2","3","4","6","8"], sel: "\(p.count ?? 3)") { i in
                    setParam { $0.count = [2,3,4,6,8][i] } } }
            } else if rmode == .coin {
                Text("each step rolls: ratchet (a burst) or plain (one hit)").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
                field("CHANCE — how often a step bursts  \(Int((p.rtcChance ?? 0.5) * 100))%") {
                    Slider(value: bind(p.rtcChance ?? 0.5) { v in setParam { $0.rtcChance = v } }, in: 0...1).tint(accent) }
                field("SIZE MIN  \(p.rtcCountLo ?? 2)") { seg((1...8).map { "\($0)" }, sel: "\(p.rtcCountLo ?? 2)") { i in
                    setParam { $0.rtcCountLo = i + 1; if ($0.rtcCountHi ?? 4) < i + 1 { $0.rtcCountHi = i + 1 } } } }
                field("SIZE MAX  \(p.rtcCountHi ?? 4)  (burst length range)") { seg((1...8).map { "\($0)" }, sel: "\(p.rtcCountHi ?? 4)") { i in
                    setParam { $0.rtcCountHi = i + 1; if ($0.rtcCountLo ?? 2) > i + 1 { $0.rtcCountLo = i + 1 } } } }
            } else {   // pattern
                field("PAINT ROLLS — pick, then tap slices  (· = plain · 2/3/4 = roll)") { seg(["·", "2", "3", "4"], sel: rtcBrush == 0 ? "·" : "\(rtcBrush)") { i in
                    rtcBrush = [0, 2, 3, 4][i] } }
                field("SLICES — the bar, left → right at RATE") { HStack(spacing: 4) {
                    ForEach(0..<8, id: \.self) { i in
                        let cur = rtcSliceAt(p.rtcSlices, i)
                        Text(cur <= 0 ? "·" : "\(cur)").font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(cur <= 0 ? .white.opacity(0.4) : .black)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 5).fill(cur <= 0 ? Color.white.opacity(0.06) : accent.opacity(0.85)))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { setParam { var s = $0.rtcSlices ?? Array(repeating: 0, count: 8); while s.count < 8 { s.append(0) }; s[i] = rtcBrush; $0.rtcSlices = s } }
                    }
                } }
                field("GRID — slices per bar") { seg(ArpRate.allCases.map(\.rawValue), sel: (p.rtcRate ?? .r1_8).rawValue) { i in
                    setParam { $0.rtcRate = ArpRate.allCases[i] } } }
                field("ROTATE — walk the pattern  (\(p.rtcRotate ?? 0))") { seg((0..<8).map { "\($0)" }, sel: "\(p.rtcRotate ?? 0)") { i in
                    setParam { $0.rtcRotate = i } } }
                let rspan = p.rtcSpan ?? .cell
                field("SPAN") { seg(["CELL", "ROW"], sel: rspan == .row ? "ROW" : "CELL") { i in setParam { $0.rtcSpan = (i == 1) ? .row : .cell } } }   // CELL = RATE stride · ROW = the 8 slices span the bar (Paul 2026-08-19)
            }
            field("BURST FADE — velocity across a burst  \(Int((p.ramp ?? 0.5) * 100))%") {
                Slider(value: bind(p.ramp ?? 0.5) { v in setParam { $0.ramp = v } }, in: 0...1).tint(accent)
            }
        case .passgate:
            field("PLAY ON PASS") { HStack(spacing: 6) {
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
            field("DIRECTION") { seg(StrumDir.allCases.map(\.rawValue), sel: (p.strumDir ?? .up).rawValue) { i in
                setParam { $0.strumDir = StrumDir.allCases[i] } } }
            field("SPREAD \(Int((p.spread ?? 0.1) * 100))") {
                Slider(value: bind(p.spread ?? 0.1) { v in setParam { $0.spread = v } }, in: 0...1).tint(accent) }
            field("RAKE (3 notes or 6)") { seg(["EVEN", "PER-NOTE"], sel: (p.strumSpreadNorm ?? true) ? "EVEN" : "PER-NOTE") { i in
                setParam { $0.strumSpreadNorm = (i == 0) } } }
            field("VOL TILT \(Int((p.velTilt ?? 0) * 100))") {
                Slider(value: bind((p.velTilt ?? 0) / 2 + 0.5) { v in setParam { $0.velTilt = (v - 0.5) * 2 } }, in: 0...1).tint(accent) }
        case .chance:
            field("CHANCE \(Int((p.probability ?? 1) * 100))%") {
                Slider(value: bind(p.probability ?? 1) { v in setParam { $0.probability = v } }, in: 0...1).tint(accent) }
            field("FAVOUR \(Int((p.chanceTilt ?? 0) * 100))  (−bottom · +top)") {
                Slider(value: bind((p.chanceTilt ?? 0) / 2 + 0.5) { v in setParam { $0.chanceTilt = (v - 0.5) * 2 } }, in: 0...1).tint(accent) }
            field("KEEP") { seg(["FIXED %", "CONSTANT N"], sel: (p.chanceDensity ?? false) ? "CONSTANT N" : "FIXED %") { i in setParam { $0.chanceDensity = (i == 1) } } }
        case .harmonize:
            let iv = p.harmIntervals ?? [0,0,0]
            ForEach(0..<3, id: \.self) { k in
                field("VOICE \(k+1) \(iv[k] == 0 ? "off" : (iv[k] > 0 ? "+\(iv[k])" : "\(iv[k])"))") {
                    stepper(iv[k], -24, 24) { v in setParam { var a = $0.harmIntervals ?? [0,0,0]; a[k] = v; $0.harmIntervals = a } }
                }
            }
        case .echo:   // the DELAY-ECHO controls (user 2026-08-08)
            let reps = p.echoRepeats ?? 3, sync = p.echoSync ?? true, div = p.echoDelayDiv ?? 4
            let ms = p.echoDelayMs ?? 250, off = p.echoOffset ?? 0, fd = p.echoFeedDelay ?? 0.7
            let dec = p.echoDecay ?? 0.5, pit = p.echoPitch ?? 0, thru = p.echoThru ?? true
            let spill = p.echoSpill ?? .ring
            field("REPEATS  \(reps)") { grid16(sel: reps) { v in setParam { $0.echoRepeats = v } } }
            field("SYNC") { seg(["ON", "OFF"], sel: sync ? "ON" : "OFF") { i in setParam { $0.echoSync = (i == 0) } } }
            if sync {
                field("DELAY  \(div)/16 note\(div == 4 ? "  (1 beat)" : "")") { grid16(sel: div) { v in setParam { $0.echoDelayDiv = v } } }
            } else {
                field("DELAY  \(Int(ms)) ms") { Slider(value: bind(ms) { v in setParam { $0.echoDelayMs = v } }, in: 10...2000).tint(accent) }
            }
            field("NUDGE  \(off > 0 ? "+" : "")\(Int(off * 100))%") {
                Slider(value: bind(off) { v in setParam { $0.echoOffset = v } }, in: -0.33...0.33).tint(accent) }
            field("1ST ECHO  \(Int(fd * 100))%") {
                Slider(value: bind(fd) { v in setParam { $0.echoFeedDelay = v } }, in: 0...1).tint(accent) }
            field("FADE  \(Int(dec * 100))%") {
                Slider(value: bind(dec) { v in setParam { $0.echoDecay = v } }, in: 0...1).tint(accent) }
            field("PITCH STEP  \(pit > 0 ? "+" : "")\(pit) st / echo") { stepper(pit, -24, 24) { v in setParam { $0.echoPitch = v } } }
            field("DRY NOTE") { seg(["THRU", "MUTE"], sel: thru ? "THRU" : "MUTE") { i in setParam { $0.echoThru = (i == 0) } } }
            // TAIL SPILL (design 2026-08-07): RING lets echoes spill past the bar; CUT keeps them inside it (the note
            // already sounding always finishes). HAND is a birthstone (deferred) — not offered yet.
            field("SPILL") { seg(["RING", "CUT"], sel: spill == .cut ? "CUT" : "RING") { i in setParam { $0.echoSpill = (i == 0 ? .ring : .cut) } } }
            // ROUTE (§7②, ratified 2026-08-22): DIRECT echoes the cell's final set (v1). CHAIN runs each repeat back
            // through the stages AFTER this ECHO slot — [ECHO→LENGTH] chokes/ties repeats, [ECHO→SPLIT] thins the trail.
            let route = p.echoRoute ?? .direct
            field("ROUTE") { seg(["DIRECT", "CHAIN"], sel: route == .chain ? "CHAIN" : "DIRECT") { i in setParam { $0.echoRoute = (i == 0 ? .direct : .chain) } } }
        case .euclid:   // GENERATOR — K-of-N euclidean rhythm (user 2026-08-08); PULSES FIXED | POOL (2026-08-09)
            let steps = p.euclidSteps ?? 8
            let fromPool = p.euclidPulsesFromPool ?? false
            field("HITS FROM") { seg(["FIXED", "POOL"], sel: fromPool ? "POOL" : "FIXED") { i in setParam { $0.euclidPulsesFromPool = (i == 1) } } }
            if !fromPool {
                field("  \(p.euclidPulses ?? 5)  of  \(steps)") { grid16(sel: p.euclidPulses ?? 5) { v in setParam { $0.euclidPulses = min(v, $0.euclidSteps ?? steps) } } }
            }
            field("STEPS  \(steps)") { grid16(sel: steps) { v in setParam { $0.euclidSteps = max(2, v); if ($0.euclidPulses ?? 5) > max(2, v) { $0.euclidPulses = max(2, v) } } } }
            field("ROTATE  \(p.euclidRot ?? 0)") { stepper(p.euclidRot ?? 0, 0, 15) { v in setParam { $0.euclidRot = v } } }
            let span = p.euclidSpan ?? .cell
            field("SPAN") { seg(["CELL", "ROW"], sel: span == .row ? "ROW" : "CELL") { i in setParam { $0.euclidSpan = (i == 1) ? .row : .cell } } }   // CELL = per-column · ROW = N steps span the bar (Paul 2026-08-18)
        case .burst:    // GENERATOR — accel/decel roll (family: ONCE | COIN | PATTERN, Paul 2026-08-19)
            let bmode = p.burstMode ?? .once   // mode set by the storefront card — no in-editor radio (Paul 2026-08-22)
            field("HITS  \(p.count ?? 4)") { seg(["2", "3", "4", "6", "8", "12", "16"], sel: "\(p.count ?? 4)") { i in setParam { $0.count = [2, 3, 4, 6, 8, 12, 16][i] } } }
            let cv = p.curve ?? 0
            field("SHAPE  \(cv > 0 ? "ACCEL" : (cv < 0 ? "DECEL" : "EVEN"))  \(Int(cv * 100))%") {
                Slider(value: bind(cv) { v in setParam { $0.curve = v } }, in: -1...1).tint(accent) }
            if bmode == .coin {
                let ch = p.burstChance ?? 0.5
                field("CHANCE  \(Int(ch * 100))%") { Slider(value: bind(ch) { v in setParam { $0.burstChance = v } }, in: 0...1).tint(accent) }
            }
            if bmode == .pattern {
                let brush = burstPaint
                field("PAINT") { HStack(spacing: 4) {
                    ForEach(BurstSlice.allCases, id: \.self) { st in
                        Text(burstSliceName(st)).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(brush == st ? .black : accent)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 5).fill(brush == st ? accent : accent.opacity(0.14)))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(brush == st ? Color.white : .clear, lineWidth: 2))
                            .contentShape(Rectangle()).onTapGesture { burstPaint = st }
                    }
                } }
                field("SLICES — B launch · C carry · R rest") { HStack(spacing: 4) {
                    ForEach(0..<8, id: \.self) { i in
                        let s = p.burstSlices ?? [.burst, .carry, .carry, .rest, .burst, .rest, .rest, .rest]
                        let cur = i < s.count ? s[i] : .rest
                        Text(cur.rawValue).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(cur == .rest ? .white.opacity(0.4) : .black)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 5).fill(burstSliceFill(cur, accent)))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { setParam { var s2 = $0.burstSlices ?? [.burst, .carry, .carry, .rest, .burst, .rest, .rest, .rest]; while s2.count < 8 { s2.append(.rest) }; s2[i] = brush; $0.burstSlices = s2 } }
                    }
                } }
                field("ROTATE  (\(p.burstRotate ?? 0))") { seg((0..<8).map { "\($0)" }, sel: "\(p.burstRotate ?? 0)") { i in setParam { $0.burstRotate = i } } }
            }
            let bspan = p.burstSpan ?? .cell
            field("SPAN") { seg(["CELL", "ROW"], sel: bspan == .row ? "ROW" : "CELL") { i in setParam { $0.burstSpan = (i == 1) ? .row : .cell } } }   // CELL = per-column roll (or 8 slices in the column) · ROW = across the bar (Paul 2026-08-19)
        case .cascade:  // GENERATOR — incremental chord reveal
            field("SPEED") { seg(ArpRate.allCases.map(\.rawValue), sel: (p.rate ?? .r1_8).rawValue) { i in setParam { $0.rate = ArpRate.allCases[i] } } }
            field("ORDER") { seg(["UP", "DOWN"], sel: (p.strumDir ?? .up) == .down ? "DOWN" : "UP") { i in setParam { $0.strumDir = (i == 0 ? .up : .down) } } }
            let cspan = p.cascadeSpan ?? .cell
            field("SPAN") { seg(["CELL", "ROW"], sel: cspan == .row ? "ROW" : "CELL") { i in setParam { $0.cascadeSpan = (i == 1) ? .row : .cell } } }   // CELL = per-column reveal · ROW = the reveal spans the bar (Paul 2026-08-19)
        case .drone:    // GENERATOR — flat sustained pad (gate = pad level)
            field("LEVEL  \(Int((p.gate ?? 0.6) * 127))") {
                Slider(value: bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1).tint(accent) }
        case .shift:    // GENERATOR — groove nudge (spread = push late)
            field("PUSH  \(Int((p.spread ?? 0.1) * 100))% late") {
                Slider(value: bind(p.spread ?? 0.1) { v in setParam { $0.spread = v } }, in: 0...1).tint(accent) }
        case .humanize: // GENERATOR — seeded jitter (spread = amount)
            field("FEEL  \(Int((p.spread ?? 0.5) * 100))%") {
                Slider(value: bind(p.spread ?? 0.5) { v in setParam { $0.spread = v } }, in: 0...1).tint(accent) }
        case .mod:      // CC GENERATOR / CC-stage §1 — a SOURCE spine (row 2 reshapes) + a universal TARGET/RANGE (row 3)
            let src = p.modSource ?? .shape    // source set by the storefront card — no in-editor radio (Paul 2026-08-22)
            switch src {
            case .shape:
                field("WAVE") { seg(ModShape.allCases.map(\.rawValue), sel: (p.modShape ?? .sine).rawValue) { i in setParam { $0.modShape = ModShape.allCases[i] } } }
                field("CYCLE  (beats / cycle)") { seg(ModRate.allCases.map(\.rawValue), sel: (p.modRate ?? .r2).rawValue) { i in setParam { $0.modRate = ModRate.allCases[i] } } }
            case .follow:
                field("LISTEN TO") { seg(ModFollow.allCases.map(\.rawValue), sel: (p.modFollow ?? .register).rawValue) { i in setParam { $0.modFollow = ModFollow.allCases[i] } } }
            case .steps:
                let sspan = p.modStepSpan ?? ((p.modSpan == .row) ? .row : .period)   // migrate the old cell|row span for display
                let n = sspan.stepCount
                let base = [0, 18, 36, 54, 72, 90, 108, 127]
                let shown = (0..<n).map { i -> Int in let s = p.modSteps ?? base; return s[i % s.count] }   // pad the stored steps to N for drawing
                field("STEPS  (drag to draw · \(n))") { modStepBars(shown, count: n) { i, v in
                    setParam { var s = $0.modSteps ?? base; let orig = s; while s.count < n { s.append(orig[s.count % orig.count]) }; s[i] = v; $0.modSteps = s } } }
                field("SPAN") { seg(ModStepSpan.allCases.map(\.rawValue), sel: sspan.rawValue) { i in setParam { $0.modStepSpan = ModStepSpan.allCases[i] } } }   // PERIOD (rate) · ROW · ROW×2 · ROW×4 (16/32 breakpoints)
                if sspan == .period { field("CYCLE  (beats / cycle)") { seg(ModRate.allCases.map(\.rawValue), sel: (p.modRate ?? .r2).rawValue) { i in setParam { $0.modRate = ModRate.allCases[i] } } } }   // the rate period only drives PERIOD span
                field("GLIDE") { seg(["SMOOTH", "STEP"], sel: (p.modSmooth ?? true) ? "SMOOTH" : "STEP") { i in setParam { $0.modSmooth = (i == 0) } } }
            case .strike:
                field("RISE  \(String(format: "%.2f", p.modAttack ?? 0.15)) beats") {
                    Slider(value: bind(p.modAttack ?? 0.15) { v in setParam { $0.modAttack = v } }, in: 0.01...4).tint(accent) }
                field("FALL  \(String(format: "%.2f", p.modRelease ?? 0.6)) beats") {
                    Slider(value: bind(p.modRelease ?? 0.6) { v in setParam { $0.modRelease = v } }, in: 0.01...4).tint(accent) }
            case .extern:
                let ec = p.modExternCC ?? 1
                field("FROM CC  \(ccLabelText(ec))") {
                    Slider(value: bind(Double(ec)) { v in setParam { $0.modExternCC = Int(v.rounded()) } }, in: 0...127).tint(accent) }
            }
            if src == .shape {                                     // SHAPE keeps CELL|ROW; STEPS has its own 4-way SPAN above
                let mspan = p.modSpan ?? .cell
                field("SPAN") { seg(["CELL", "ROW"], sel: mspan == .row ? "ROW" : "CELL") { i in setParam { $0.modSpan = (i == 1) ? .row : .cell } } }   // CELL = the CYCLE period · ROW = one cycle spans the bar
            }
            let target = p.modTarget ?? .cc
            field("SEND") { seg(ModTarget.allCases.map { $0 == .chain ? "THIS CHAIN" : $0.rawValue }, sel: target == .chain ? "THIS CHAIN" : "CC") { i in setParam { $0.modTarget = ModTarget.allCases[i] } } }   // §2: CC (emit) | THIS CHAIN (modulate a chain param, no CC)
            if target == .cc {
                let cc = p.modCC ?? 74
                field("SEND CC  \(ccLabelText(cc))") {
                    Slider(value: bind(Double(cc)) { v in setParam { $0.modCC = Int(v.rounded()) } }, in: 0...127).tint(accent) }
            } else {
                let params: [MacroParam] = [.gate, .ramp, .spread, .curve, .velTilt, .probability, .harmVelScale, .tuttiBalance, .lenShort, .lenLong, .rtcChance]
                let cur = p.modChainParam ?? .gate
                field("CHAIN PARAM") {
                    Menu {
                        ForEach(params, id: \.self) { pp in Button(pp.rawValue.uppercased()) { setParam { $0.modChainParam = pp } } }
                    } label: {
                        Text(cur.rawValue.uppercased()).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(accent)
                            .padding(.horizontal, 10).frame(height: 30).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                    }
                }
            }
            let lo = p.modMin ?? 0, hi = p.modMax ?? 127
            field("MIN  \(lo)") {
                Slider(value: bind(Double(lo)) { v in setParam { $0.modMin = Int(v.rounded()) } }, in: 0...127).tint(accent) }
            field("MAX  \(hi)\(lo > hi ? "   (inverted)" : "")") {
                Slider(value: bind(Double(hi)) { v in setParam { $0.modMax = Int(v.rounded()) } }, in: 0...127).tint(accent) }
            field("ON EXIT") { seg(["RESET", "LEAVE"], sel: (p.modReset ?? true) ? "RESET" : "LEAVE") { i in setParam { $0.modReset = (i == 0) } } }
        case .glide:    // notes→pitch-bend — one mono sliding voice
            field("TIME  \(String(format: "%.2f", p.glideTime ?? 0.25)) beats") {
                Slider(value: bind(p.glideTime ?? 0.25) { v in setParam { $0.glideTime = v } }, in: 0...2).tint(accent) }
            field("BEND RANGE  ±\(p.glideRange ?? 2) st  (match the synth)") {
                Slider(value: bind(Double(p.glideRange ?? 2)) { v in setParam { $0.glideRange = Int(v.rounded()) } }, in: 1...48).tint(accent) }
            field("FOLLOW") { seg(GlidePriority.allCases.map(\.rawValue), sel: (p.glidePriority ?? .last).rawValue) { i in setParam { $0.glidePriority = GlidePriority.allCases[i] } } }
            field("TOO FAR") { seg(["RE-ANCHOR", "CLAMP"], sel: (p.glideReanchor ?? true) ? "RE-ANCHOR" : "CLAMP") { i in setParam { $0.glideReanchor = (i == 0) } } }
        case .tutti:    // SET-level chance — one MODE radio; COIN now, PATTERN in phase 2
            // mode set by the storefront card — no in-editor radio (Paul 2026-08-22)
            if (p.tuttiMode ?? .coin) == .coin {
                field("BALANCE   SOLO  ◂  \(Int((p.tuttiBalance ?? 0.5) * 100))%  ▸  TUTTI") {   // the slider IS the idea
                    Slider(value: bind(p.tuttiBalance ?? 0.5) { v in setParam { $0.tuttiBalance = v } }, in: 0...1).tint(accent) }
                field("SOLO NOTE  (which note carries a SOLO step)") { seg(TuttiPick.allCases.map(\.rawValue), sel: (p.tuttiPick ?? .low).rawValue) { i in
                    setParam { $0.tuttiPick = TuttiPick.allCases[i] } } }
            } else {
                // PAINT palette — each chip DRAWS the chord shape (dots = which notes sound); tap to load the brush.
                field("PAINT — pick a shape, then tap the slices below") { HStack(spacing: 4) {
                    ForEach(TuttiSlice.allCases, id: \.self) { st in
                        let on = (tuttiPaint == st)
                        tuttiShapeIcon(st, tint: on ? .black : accent)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? accent : accent.opacity(0.14)))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? Color.white : .clear, lineWidth: 2))
                            .contentShape(Rectangle()).onTapGesture { tuttiPaint = st }
                    }
                } }
                Text("brush:  \(tuttiName(tuttiPaint))")   // names the loaded shape in plain English (learn by picking)
                    .font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                field("SLICES — the bar plays these left → right at RATE") { HStack(spacing: 4) {
                    ForEach(0..<8, id: \.self) { i in
                        let cur = tuttiSliceAt(p.tuttiSlices, i)
                        tuttiShapeIcon(cur, tint: cur == .rest ? .white.opacity(0.35) : .black)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 5).fill(cur == .rest ? Color.white.opacity(0.06) : accent.opacity(0.85)))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15), lineWidth: 1))   // reads as a tappable cell
                            .contentShape(Rectangle())
                            .onTapGesture { setParam { var s = $0.tuttiSlices ?? Array(repeating: .all, count: 8); while s.count < 8 { s.append(.all) }; s[i] = tuttiPaint; $0.tuttiSlices = s } }
                    }
                } }
                field("GRID — how many slices per bar") { seg(ArpRate.allCases.map(\.rawValue), sel: (p.tuttiRate ?? .r1_8).rawValue) { i in
                    setParam { $0.tuttiRate = ArpRate.allCases[i] } } }
                field("ROTATE — slide the whole figure earlier/later  (\(p.tuttiRotate ?? 0))") { seg((0..<8).map { "\($0)" }, sel: "\(p.tuttiRotate ?? 0)") { i in
                    setParam { $0.tuttiRotate = i } } }
                let tspan = p.tuttiSpan ?? .cell
                field("SPAN") { seg(["CELL", "ROW"], sel: tspan == .row ? "ROW" : "CELL") { i in setParam { $0.tuttiSpan = (i == 1) ? .row : .cell } } }   // CELL = GRID stride · ROW = the 8 slices span the bar (Paul 2026-08-19)
            }
        case .length:   // per-slice GATE override — PASS/MUTE/SHORT/LONG drawn as bars (how long the note sounds in the slice)
            field("PAINT — pick a length, then tap the slices") { HStack(spacing: 4) {
                ForEach(LenState.allCases, id: \.self) { st in
                    let on = (lenPaint == st)
                    lenGlyph(st, tint: on ? .black : accent)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 5).fill(on ? accent : accent.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? Color.white : .clear, lineWidth: 2))
                        .contentShape(Rectangle()).onTapGesture { lenPaint = st }
                }
            } }
            Text("brush:  \(lenName(lenPaint))")
                .font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            field("SLICES — the step, left → right") { HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    let cur = lenSliceAt(p.lenSlices, i)
                    lenGlyph(cur, tint: cur == .mute ? .white.opacity(0.35) : .black)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 5).fill(cur == .mute ? Color.white.opacity(0.06) : accent.opacity(0.8)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .contentShape(Rectangle())
                        .onTapGesture { setParam { var s = $0.lenSlices ?? Array(repeating: .pass, count: 8); while s.count < 8 { s.append(.pass) }; s[i] = lenPaint; $0.lenSlices = s } }
                }
            } }
            field("SHORT =  \(Int((p.lenShort ?? 0.4) * 100))% of a slice") {
                Slider(value: bind(p.lenShort ?? 0.4) { v in setParam { $0.lenShort = v } }, in: 0.05...0.95).tint(accent) }
            field("LONG =  \(Int((p.lenLong ?? 0.7) * 100))%  (25% … step end)") {
                Slider(value: bind(p.lenLong ?? 0.7) { v in setParam { $0.lenLong = v } }, in: 0...1).tint(accent) }
            field("ROTATE — shift the phrasing  (\(p.lenRotate ?? 0))") { seg((0..<8).map { "\($0)" }, sel: "\(p.lenRotate ?? 0)") { i in
                setParam { $0.lenRotate = i } } }
            let lspan = p.lenSpan ?? .cell
            field("SPAN") { seg(["CELL", "ROW"], sel: lspan == .row ? "ROW" : "CELL") { i in setParam { $0.lenSpan = (i == 1) ? .row : .cell } } }   // CELL = per-column gate · ROW = the 8 slices span the bar (Paul 2026-08-19)
        case .weave:   // rank-clocked polyrhythm driver — each held note on its own clock
            let wmode = p.weaveMode ?? .ladder   // mode set by the storefront card — no in-editor radio (Paul 2026-08-22)
            Text(weaveModeBlurb(wmode)).font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            if wmode == .ladder || wmode == .harmonic {
                field("BASS CLOCK — the bass rank's clock (higher ranks weave faster)") { seg(StepRate.allCases.map(\.rawValue), sel: (p.weaveBaseStep ?? .r1_4).rawValue) { i in
                    setParam { $0.weaveBaseStep = StepRate.allCases[i] } } }
            } else if wmode == .drawn {
                field("PER-NOTE — pick a rate below, then tap ranks") { HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { i in
                        Text(weaveDrawnAt(p.weaveDrawn, i).rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.8)))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { setParam { var s = $0.weaveDrawn ?? Array(repeating: StepRate.r1_8, count: 8); while s.count < 8 { s.append(.r1_8) }; s[i] = weaveBrush; $0.weaveDrawn = s } }
                    }
                } }
                field("BRUSH — rank 0 = bass (left) … rank 7 (right)") { seg(StepRate.allCases.map(\.rawValue), sel: weaveBrush.rawValue) { i in weaveBrush = StepRate.allCases[i] } }
            } else {   // euclid
                field("STEPS  \(p.weaveEuclidSteps ?? 8)  (bass fills 1, each rank up fills 2 more)") {
                    Slider(value: bind(Double(p.weaveEuclidSteps ?? 8)) { v in setParam { $0.weaveEuclidSteps = Int(v.rounded()) } }, in: 2...16).tint(accent) }
            }
            field("NEW CHORD — RETRIG restarts each step · FREE runs the grid · LEGATO flows from the hold") { seg(ArpPhase.allCases.map(\.rawValue), sel: (p.weavePhase ?? .retrig).rawValue) { i in
                setParam { $0.weavePhase = ArpPhase.allCases[i] } } }
            field("VOICES — how many notes weave  (\(p.weaveSpan ?? 4))") { seg((1...8).map { "\($0)" }, sel: "\(p.weaveSpan ?? 4)") { i in
                setParam { $0.weaveSpan = i + 1 } } }
            field("LENGTH \(Int((p.gate ?? 0.6) * 100))%") {
                Slider(value: bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1).tint(accent) }
        case .split:   // set-membership filter — keep a subset of the chord (before a driver = re-pool · after = punch holes)
            let sm = p.splitSet?.mode ?? .all
            field("KEEP") { seg(SplitMode.allCases.map(\.rawValue), sel: sm.rawValue) { i in
                setParam { var c = $0.splitSet ?? ChordSplit(); c.mode = SplitMode.allCases[i]; $0.splitSet = c } } }
            if sm == .top || sm == .bottom {
                field("NOTES — how many notes  (\(p.splitSet?.n ?? 2))") { seg((1...6).map { "\($0)" }, sel: "\(p.splitSet?.n ?? 2)") { i in
                    setParam { var c = $0.splitSet ?? ChordSplit(); c.n = i + 1; $0.splitSet = c } } }
            } else if sm == .range {
                field("AT NOTE  \(midiNoteName(UInt8(max(0, min(127, p.splitSet?.note ?? 60)))))") {
                    Slider(value: bind(Double(p.splitSet?.note ?? 60)) { v in setParam { var c = $0.splitSet ?? ChordSplit(); c.note = Int(v.rounded()); $0.splitSet = c } }, in: 0...127).tint(accent) }
                field("SIDE") { seg(["≥ SPLIT", "< SPLIT"], sel: (p.splitSet?.high ?? true) ? "≥ SPLIT" : "< SPLIT") { i in
                    setParam { var c = $0.splitSet ?? ChordSplit(); c.high = (i == 0); $0.splitSet = c } } }
            }
            field("VEL MIN  \(p.splitVel?.floor ?? 1)") {
                Slider(value: bind(Double(p.splitVel?.floor ?? 1)) { v in setParam { var w = $0.splitVel ?? VelWindow(); w.floor = min(Int(v.rounded()), w.ceil); $0.splitVel = w } }, in: 1...127).tint(accent) }
            field("VEL MAX  \(p.splitVel?.ceil ?? 127)") {
                Slider(value: bind(Double(p.splitVel?.ceil ?? 127)) { v in setParam { var w = $0.splitVel ?? VelWindow(); w.ceil = max(Int(v.rounded()), w.floor); $0.splitVel = w } }, in: 1...127).tint(accent) }
        case .octave:   // UTILITY — shift ±3 octaves (pitch-class preserved)
            let oct = p.utilOctave ?? 0
            field("OCTAVE  \(oct > 0 ? "+" : "")\(oct)") { stepper(oct, -3, 3) { v in setParam { $0.utilOctave = v } } }
        case .transpose:   // UTILITY — shift ±24 semitones
            let st = p.utilTranspose ?? 0
            field("SEMITONES  \(st > 0 ? "+" : "")\(st)") { stepper(st, -24, 24) { v in setParam { $0.utilTranspose = v } } }
        case .channel:   // UTILITY — output channel override (WIRE = the bus stamp)
            let ch = p.utilChannel ?? 0
            field("CHANNEL  \(ch == 0 ? "WIRE" : "\(ch)")") { seg(["WIRE"] + (1...16).map { "\($0)" }, sel: ch == 0 ? "WIRE" : "\(ch)") { i in setParam { $0.utilChannel = i } } }
        case .nudge:   // UTILITY — time offset in sixteenths
            let nu = p.utilNudge ?? 0
            field("NUDGE  \(nu > 0 ? "+" : "")\(nu)/16 beat") { stepper(nu, -8, 8) { v in setParam { $0.utilNudge = v } } }
        }
    }

    private func weaveModeBlurb(_ m: WeaveMode) -> String {
        switch m {
        case .ladder:   return "LADDER — each rank up plays twice as fast (÷2 per rank)"
        case .harmonic: return "HARMONIC — rank n plays n× the bass (1:2:3:4 — rhythm as pitch ratio)"
        case .drawn:    return "DRAWN — set each rank's own rate by hand below"
        case .euclid:   return "EUCLID — each rank an interlocking euclidean pulse (bass sparse → top dense)"
        }
    }
    private func weaveDrawnAt(_ arr: [StepRate]?, _ i: Int) -> StepRate {
        let a = arr ?? []; return i >= 0 && i < a.count ? a[i] : .r1_8
    }
    private func rtcSliceAt(_ arr: [Int]?, _ i: Int) -> Int {   // RATCHET PATTERN per-slice count (safe read)
        let a = arr ?? []; return i >= 0 && i < a.count ? a[i] : 0
    }

    private func tuttiSliceAt(_ arr: [TuttiSlice]?, _ i: Int) -> TuttiSlice {   // safe read (a loaded doc may carry <8)
        let a = arr ?? []; return i >= 0 && i < a.count ? a[i] : .all
    }
    /// TUTTI PATTERN — the shape's plain-English name (the caption teaches the vocabulary without a legend).
    private func burstSliceName(_ s: BurstSlice) -> String { s == .burst ? "BURST" : (s == .carry ? "CARRY" : "REST") }
    private func burstSliceFill(_ s: BurstSlice, _ accent: Color) -> Color {
        switch s { case .burst: return accent.opacity(0.85); case .carry: return accent.opacity(0.45); case .rest: return Color.white.opacity(0.06) }
    }
    private func tuttiName(_ s: TuttiSlice) -> String {
        switch s {
        case .all:        return "ALL — the whole chord"
        case .low:        return "LOW — the bottom note"
        case .high:       return "HIGH — the top note"
        case .top2:       return "TOP 2 — the two highest notes"
        case .bot2:       return "BOT 2 — the two lowest notes"
        case .lowOct:     return "LOW +8ᵛᵃ — bottom note, an octave up"
        case .allDownOct: return "ALL −8ᵛᵃ — whole chord, an octave down"
        case .rest:       return "REST — a silent slice"
        }
    }
    /// TUTTI PATTERN — DRAW the chord shape: 3 stacked dots (top = high note … bottom = low), filled = sounds; an
    /// arrow marks an octave shift; REST is a dash. Language-free, so T2/B2/L+8 don't need decoding.
    private func tuttiShapeFill(_ s: TuttiSlice) -> (fill: [Bool], oct: Int) {   // [low, mid, high] filled + octave shift
        switch s {
        case .all:        return ([true, true, true], 0)
        case .low:        return ([true, false, false], 0)
        case .high:       return ([false, false, true], 0)
        case .top2:       return ([false, true, true], 0)
        case .bot2:       return ([true, true, false], 0)
        case .lowOct:     return ([true, false, false], 1)
        case .allDownOct: return ([true, true, true], -1)
        case .rest:       return ([false, false, false], 0)
        }
    }
    @ViewBuilder private func tuttiShapeIcon(_ s: TuttiSlice, tint: Color) -> some View {
        let (fill, oct) = tuttiShapeFill(s)
        if s == .rest {
            Text("—").font(.system(size: 13, weight: .heavy)).foregroundColor(tint)
        } else {
            HStack(spacing: 2) {
                VStack(spacing: 2) {
                    ForEach([2, 1, 0], id: \.self) { i in   // top → bottom = high → low
                        Circle().fill(fill[i] ? tint : .clear)
                            .overlay(Circle().stroke(tint.opacity(fill[i] ? 0 : 0.45), lineWidth: 1))
                            .frame(width: 5, height: 5)
                    }
                }
                if oct != 0 { Image(systemName: oct > 0 ? "arrow.up" : "arrow.down").font(.system(size: 8, weight: .heavy)).foregroundColor(tint) }
            }
        }
    }

    private func lenName(_ s: LenState) -> String {
        switch s {
        case .pass:  return "PASS — the chord keeps sounding (sustain)"
        case .mute:  return "MUTE — silence (a rest)"
        case .short: return "SHORT — a staccato stab"
        case .long:  return "LONG — a re-attacked long note"
        }
    }
    private func lenSliceAt(_ arr: [LenState]?, _ i: Int) -> LenState {   // safe read (a loaded doc may carry <8)
        let a = arr ?? []; return i >= 0 && i < a.count ? a[i] : .pass
    }
    /// LENGTH glyph — a bar showing how long the note sounds in the slice: MUTE a dot (silent), SHORT a short bar with an
    /// attack tick, LONG a full bar with an attack tick, PASS a dim full bar (sustained, no re-attack).
    @ViewBuilder private func lenGlyph(_ s: LenState, tint: Color) -> some View {
        HStack(spacing: 1) {
            switch s {
            case .mute:
                Spacer(minLength: 0); Circle().fill(tint.opacity(0.6)).frame(width: 4, height: 4); Spacer(minLength: 0)
            case .short:
                Rectangle().fill(Color.white).frame(width: 2, height: 12)
                RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 10, height: 8); Spacer(minLength: 0)
            case .long:
                Rectangle().fill(Color.white).frame(width: 2, height: 12)
                RoundedRectangle(cornerRadius: 1).fill(tint).frame(maxWidth: .infinity).frame(height: 8)
            case .pass:
                RoundedRectangle(cornerRadius: 1).fill(tint.opacity(0.45)).frame(maxWidth: .infinity).frame(height: 8)
            }
        }
        .padding(.horizontal, 4)
    }
    // ECHO: a 1…16 selector as an 8×2 box (user 2026-08-08) — repeats + the synced 16th-note delay both use it.
    private func grid16(sel: Int, _ set: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { coln in
                        let val = 1 + row * 8 + coln
                        let on = val == sel
                        Text("\(val)").font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : accent).lineLimit(1).minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent : Color.white.opacity(0.09)))
                            .contentShape(Rectangle()).onTapGesture { set(val) }
                    }
                }
            }
        }
    }

    // CC-stage §1: a labelled CC number ("74 · CUTOFF" for the named dozen, else the bare number).
    private func ccLabelText(_ n: Int) -> String { ccName(n).map { "\(n) · \($0)" } ?? "\(n)" }
    // STEPS "drag to draw": `count` vertical bars (8/16/32 by SPAN); drag a column to set its 0…127 value.
    private func modStepBars(_ steps: [Int], count: Int = 8, _ set: @escaping (Int, Int) -> Void) -> some View {
        HStack(spacing: count > 16 ? 1 : (count > 8 ? 2 : 4)) {
            ForEach(0..<count, id: \.self) { i in
                let v = i < steps.count ? steps[i] : 0
                GeometryReader { g in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3).fill(accent).frame(height: max(2, g.size.height * CGFloat(v) / 127))
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                        set(i, Int((1 - min(1, max(0, val.location.y / max(1, g.size.height)))) * 127))
                    })
                }
                .frame(maxWidth: .infinity).frame(height: 84)
            }
        }
    }

    // ---- small controls ----
    private func typeShort(_ t: ProcessorType) -> String { t == .passgate ? "PASSES" : t.rawValue }   // FULL name (user 2026-07-30 — no abbreviations); PASSGATE panel display name → PASSES (friendly labels, enum rawValue untouched)
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

/// The natural (unscrolled) height of the main content column. The body compares it to the viewport to decide
/// whether the WHOLE UI (header + tabs + tab body) needs to scroll — so the header/tabs scroll WITH the grid
/// instead of staying pinned, while a window that FITS renders raw (keeping the UIKit ColumnHoldOverlay alive).
struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}


// MARK: - Cell-edit STAGING (user 2026-07-25) — long-press a colour → configure a pending cell in the
// side panels (EDIT only). The RECEIVERS panel becomes the cell's INPUT picker (R1–R4 radio + a FROM ROW
// option), the EMITTERS panel its OUTPUT buses. Ephemeral (a StampConfig), recalled across enter/exit.
// The render-path live-preview drag-to-grid is DEFERRED to the design spec — this is the panel scaffold.

// THE PIANO-ROLL FACE (Paul 2026-08-19): the perform-grid cells echo a piano roll — soft note marks enter at the right
// and drift left AS THE CELL SOUNDS, then fade. Gentle + calm (identity stays the cell's HUE). This is the shipped cell
// face; set false to fall back to THE SEAL (kept intact). (The mosaic face was dropped 2026-08-23, Paul.)
let usePianoRollFace = true

private let stagingCyan = UI.cyan

/// A 0→1→0 breathing fraction for the staging pulses (chip, empty-cell border, placed-cell fill) — one
/// cosine so every pulse shares the same rhythm. `period` in seconds.
func stagingPulseFraction(_ date: Date, period: Double) -> Double {
    0.5 - 0.5 * cos(date.timeIntervalSinceReferenceDate * 2 * .pi / period)
}


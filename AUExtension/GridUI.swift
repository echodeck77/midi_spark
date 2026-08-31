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
// THE PLAY GRID's own palette (Paul 2026-08-30): a muted "DUSK" family, so the play grid is differentiable from the VIVID
// part grid at a glance (each grid owns its own section of colour). Earthy, mid-brightness, low-saturation — a quieter world
// beside the loud part rainbow, and calm enough that the vivid emitter drift-notes still pop on top.
let playHexes: [UInt32] = [0xB08D57, 0xB06A4E, 0xA85A5A, 0x8F5A78, 0x7A6AA8, 0x5A7AA8, 0x5A9A8A, 0x8A9A5A]

// THE RECEIVER SIGNATURE GREYS (Paul 2026-08-30): the four MIDI-IN receivers A→D are now 4 shades of grey, LIGHT→DARK — their
// identity colour going forward (the OMNI/ENABLE button on the receiver strip + the MIDI-IN toggle chips). Kept light enough
// for black labels. (Distinct from the vivid emitter signature colours + the machine hues.)
let receiverGreys: [Color] = [Color(white: 0.88), Color(white: 0.74), Color(white: 0.60), Color(white: 0.46)]
func receiverGrey(_ i: Int) -> Color { receiverGreys[max(0, min(3, i))] }

// delta §9 item 11: the four receivers' fixed "infrastructure family" hues (muted), shared by the
// RECEIVERS panel and the cells' band-as-deviation marker.
let receiverHues: [Color] = [Color(hex: 0x6B7A8F), Color(hex: 0x7E6B8F), Color(hex: 0x6B8F7E), Color(hex: 0x8F836B)]

// EMITTER SIGNATURE COLOURS (Paul 2026-08-30): four VIVID, high-contrast hues for A/B/C/D — the ROUTING channel. They
// carry the DRIFTING piano-roll notes (and the MIDI-OUT toggles/dots). Kept the loudest colours in the app so the eye
// reads "vivid + moving = emitter" vs "calm frame = machine" — two colour languages that never fight on one small cell.
let emitterHexes: [UInt32] = [0xFF453A, 0x30D158, 0x0A84FF, 0xFF9F0A]   // A red · B green · C blue · D orange
func emitterColour(_ bus: Bus) -> Color {
    let i = Bus.allCases.firstIndex(of: bus) ?? 0
    return Color(hex: i < emitterHexes.count ? emitterHexes[i] : 0x808080)
}
// The representative emitter colour for a cell's output SET — the LOWEST enabled bus (A<B<C<D); the drift's colour.
func emitterHue(_ buses: Set<Bus>) -> Color {
    for b in Bus.allCases where buses.contains(b) { return emitterColour(b) }
    return emitterColour(.a)
}

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
    var cellHitAt: [Date] = []                       // SEAL comet: per-cell last-strike time (index col*Snap.rows+row)
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
                    pianoRollFace(col * Snap.rows + row)
                } else {
                    // THE SEAL (which) — the derived glyph fills the WHOLE cell face now (user 2026-08-03: the bus dots
                    // are dropped). An engraved plate carries the seal; a COMET runs the wire while the cell fires MIDI (§5).
                    let geo = sealGeometry(sealHash(cell, colours: colours))
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.14))                       // engraved plate
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                        Canvas { ctx, size in drawSeal(geo, into: ctx, size: size, padFraction: 0.16, stroke: 2.4, ink: sealInk) }
                        sealComet(geo, col * Snap.rows + row)
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
    var liveStep: Int = -1                               // PLAYHEAD (idea 15): the live GRID COLUMN (0…7) lit in the matrices/lanes; -1 = stopped
    var onBypass: () -> Void = {}
    var onRemove: (() -> Void)? = nil                   // nil = not removable (the head slot)
    var onMacro: (() -> Void)? = nil                    // slotMode: the MACRO button → the authoring flow (spec macro-authoring)
    var plainTitle: Bool = false                        // pop-up: show the type as a plain TITLE (no type-picker button)
    var showSlotChrome: Bool = true                     // slotMode: draw the built-in title row (name + BYPASS/✕ pills). BUILD hides it and supplies its own large Delete/Bypass header.
    @State private var showTypePicker = false           // B1: the title-as-picker popover
    @State private var weaveBrush: StepRate = .r1_8      // WEAVE DRAWN: the rate loaded on the brush
    @State private var laneReadout: String? = nil        // LANE READOUT (idea 18): the value floating while a lane bar is dragged

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
    // CRASH FIX (2026-08-27): each typeParams case is wrapped in AnyView(VStack(spacing: rowSpacing){…}) so the
    // switch's opaque type collapses to a shallow _ConditionalContent chain of AnyView (was a 28-deep nest of giant
    // TupleViews whose concrete-metadata instantiation overflowed the demangler stack → SIGSEGV when the editor
    // first rendered — e.g. adding an ARP). rowSpacing MATCHES the body VStack's spacing so layout is unchanged.
    private var rowSpacing: CGFloat { slotMode ? 14 : 6 }

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
                            slider(Binding(get: { colour.morph }, set: { onMorph($0) }), in: 0...1)
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
        case .dest:      return "route each step to a chosen emitter (hocket)"
        case .muteMatrix: return "mute chosen emitters per step (part-gating)"
        case .riff:      return "an authored line that follows the held chord (a stencil of ranks)"
        case .tap:       return "send a copy out here + pass it on (layered parallel outputs)"
        case .hocket:    return "play your notes in another synth's gaps — or trade hits with it (listen to a wire)"
        case .avoid:     return "remove or move notes that clash with a reference — or lock them to a key"
        }
    }

    private func pill(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(accent)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.2)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    // EUCLID LINES (§10): mutate line `idx` in place (through setParam → the colour-scoped edit).
    private func euclidLineEdit(_ idx: Int, _ f: @escaping (inout EuclidLine) -> Void) {
        setParam { var a = $0.euclidLines ?? []; guard idx < a.count else { return }; f(&a[idx]); $0.euclidLines = a }
    }

    @ViewBuilder private func typeParams(_ ft: ProcessorType) -> some View {
        switch ft {
        case .arp: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {
            heroField("PATTERN") { iconSeg(ArpPattern.allCases.map(\.rawValue), sel: p.pattern?.rawValue ?? "UP", glyph: { i, t in arpGlyph(i, t) }) { i in
                setParam { $0.pattern = ArpPattern.allCases[i] } } }
            // RANDOM ANCHOR (Paul 2026-08-22): only meaningful for RANDOM — pins the first note of each cycle low/high.
            // Sits DIRECTLY under PATTERN so the conditional chip reads with it (Paul 2026-08-25).
            if (p.pattern ?? .up) == .random {
                field("RANDOM ANCHOR", \.arpRandomAnchor) { seg(["OFF", "LOW", "HIGH"], sel: ["OFF", "LOW", "HIGH"][max(0, min(2, p.arpRandomAnchor ?? 0))]) { i in
                    setParam { $0.arpRandomAnchor = i } } }
            }
            field("SPEED", \.rate) { seg(ArpRate.allCases.map(\.rawValue), sel: p.rate?.rawValue ?? "1/16") { i in
                setParam { $0.rate = ArpRate.allCases[i] } } }
            HStack(spacing: 8) {
                field("OCTAVES", \.octaves) { numPair(p.octaves ?? 1, 1...4) { v in setParam { $0.octaves = v } } }
                // OCT DIRECTION (Paul 2026-08-22): the laps ascend the octaves (UP) or descend them (DOWN).
                field("OCT DIR", \.arpOctDown) { seg(["UP", "DOWN"], sel: (p.arpOctDown ?? false) ? "DOWN" : "UP") { i in
                    setParam { $0.arpOctDown = (i == 1) } } }
            }
            field("NEW CHORD", \.phase) { seg(ArpPhase.allCases.map(\.rawValue), sel: p.phase?.rawValue ?? "RETRIG") { i in
                setParam { $0.phase = ArpPhase.allCases[i] } } }
            field("LENGTH \(Int((p.gate ?? 0.6) * 100))%", \.gate) {
                slider(bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1)
            }
            optionsCluster([("FIT 1 BEAT", p.arpFit ?? false, { setParam { $0.arpFit = !($0.arpFit ?? false) } })])
            // EUCLID MASK (SPEC-arp-euclid-mask, ratified 2026-08-26): HITS ◀K▶ of ◀N▶. K = N ⇒ OFF (dimmed, defaults-recede);
            // turn K down and the kit ANIMATES IN — GAPS (rest/tie) · WALK (march/wait) · ROTATE.
            let mN = max(2, min(16, p.arpMaskN ?? 8))
            let mK = max(1, min(mN, p.arpMaskK ?? mN))
            field("EUCLID MASK — HITS  ◀K▶ of ◀N▶  (K < N gates the line)") {
                HStack(spacing: 10) {
                    numPair(mK, 1...mN) { v in setParam { $0.arpMaskK = v; if $0.arpMaskN == nil { $0.arpMaskN = mN } } }
                    Text("of").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    numPair(mN, 2...16) { v in setParam { $0.arpMaskN = v; if let k = $0.arpMaskK, k > v { $0.arpMaskK = v } } }
                }
            }
            .opacity(mK < mN ? 1 : 0.45)                                    // defaults-recede when OFF (K = N)
            if mK < mN {                                                    // the kit animates in only when the mask bites
                row2({ field("GAPS", \.arpMaskGap) { seg(["REST", "TIE"], sel: (p.arpMaskGap ?? .rest) == .tie ? "TIE" : "REST") { i in setParam { $0.arpMaskGap = (i == 1 ? .tie : .rest) } } } },
                     { field("WALK", \.arpMaskWalk) { seg(["MARCH", "WAIT"], sel: (p.arpMaskWalk ?? .march) == .wait ? "WAIT" : "MARCH") { i in setParam { $0.arpMaskWalk = (i == 1 ? .wait : .march) } } } })
                field("ROTATE", \.arpMaskRotate) { numPair(p.arpMaskRotate ?? 0, 0...(mN - 1), wrap: true) { v in setParam { $0.arpMaskRotate = v } } }
            }
        })
        case .ratchet: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {
            let rmode = p.rtcMode ?? .all      // mode set by the storefront card — no in-editor radio (Paul 2026-08-22)
            if rmode == .all {
                heroField("REPEATS") { numPair(p.count ?? 3, 2...8) { v in setParam { $0.count = v } } }
            } else if rmode == .coin {
                Text("each step rolls: ratchet (a burst) or plain (one hit)").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
                heroField("CHANCE — how often a step bursts  \(Int((p.rtcChance ?? 0.5) * 100))%") {
                    slider(bind(p.rtcChance ?? 0.5) { v in setParam { $0.rtcChance = v } }, in: 0...1) }
                // ① SIZE WEIGHTS (Paul 2026-08-26) — the drawn distribution over roll sizes 2·3·4·6·8 (replaces SIZE MIN/MAX).
                let defW: [Int] = rtcCoinSizes.map { ((p.rtcCountLo ?? 2)...(p.rtcCountHi ?? 4)).contains($0) ? 4 : 0 }
                field("SIZE WEIGHTS — draw each roll size's odds", \.rtcSizeWeights) {
                    VStack(spacing: 3) {
                        sliderLane(p.rtcSizeWeights ?? defW, count: 5, max: 8) { i, v in
                            setParam { var a = $0.rtcSizeWeights ?? defW; while a.count < 5 { a.append(0) }; a[i] = v; $0.rtcSizeWeights = a } }
                            .frame(height: 44)
                        HStack(spacing: 0) { ForEach(rtcCoinSizes, id: \.self) { s in
                            Text("\(s)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5)).frame(maxWidth: .infinity) } }
                    }
                }
                // ②③④ REFIRE GAP · QUOTA · ODDS FROM (the phrasing / density / performance couplings)
                row2({ field("REFIRE GAP — quiet steps after a fire", \.rtcGap) { numPair(p.rtcGap ?? 0, 0...4) { v in setParam { $0.rtcGap = v } } } },
                     { field("QUOTA — rough fires per row", \.rtcQuota) { seg(["FREE", "~2", "~3", "~4"], sel: ["FREE", "~2", "~3", "~4"][[0, 2, 3, 4].firstIndex(of: p.rtcQuota ?? 0) ?? 0]) { i in setParam { $0.rtcQuota = [0, 2, 3, 4][i] } } } })
                field("ODDS FROM", \.rtcOddsVel) { seg(["FIXED", "VELOCITY"], sel: (p.rtcOddsVel ?? false) ? "VELOCITY" : "FIXED") { i in setParam { $0.rtcOddsVel = (i == 1) } } }
            } else {   // pattern — a STATE MATRIX (rows = burst counts, cols = the 8 steps)
                heroField("ROLLS PER STEP — tap a cell  (· = plain · 2/3/4 = roll)") {
                    stateMatrixRadio([0, 2, 3, 4],
                        header: { v in AnyView(Text(v <= 0 ? "·" : "\(v)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75)).frame(width: 22, alignment: .leading)) },
                        eFill: true, onRotate: { d in setParam { $0.rtcRotate = ((($0.rtcRotate ?? 0) + d) % 8 + 8) % 8 } },
                        selected: { i in rtcSliceAt(p.rtcSlices, i) },
                        set: { i, v in setParam { var s = $0.rtcSlices ?? Array(repeating: 0, count: 8); while s.count < 8 { s.append(0) }; s[i] = v; $0.rtcSlices = s } })
                }
            }
            field("BURST FADE — velocity across a burst  \(Int((p.ramp ?? 0.5) * 100))%", \.ramp) {
                slider(bind(p.ramp ?? 0.5) { v in setParam { $0.ramp = v } }, in: 0...1)
            }
            // §1 STANDARD PANEL ANATOMY (Paul 2026-08-27) — THE FOOTER: the frame row (GRID · ROTATE · SPAN, PATTERN mode
            // only) in fixed order + place, then the pairs-well line. GRID = slice width · SPAN = the pattern's loop period.
            if rmode == .pattern {
                frameRow(grid:  { frameGrid(p.rtcRate ?? .r1_8) { r in setParam { $0.rtcRate = r } } },
                         rotate: { frameRotate(p.rtcRotate ?? 0, 0...7) { v in setParam { $0.rtcRotate = v } } },
                         span:   { frameSpan(p.rtcSpanN ?? 0, free: true) { v in setParam { $0.rtcSpanN = v } } },
                         pairs: .ratchet)
            }
        })
        case .passgate: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {
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
        })
        case .strum: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {
            heroField("SPREAD \(Int((p.spread ?? 0.1) * 100))") {
                slider(bind(p.spread ?? 0.1) { v in setParam { $0.spread = v } }, in: 0...1) }
            row2({ field("DIRECTION", \.strumDir) { seg(StrumDir.allCases.map(\.rawValue), sel: (p.strumDir ?? .up).rawValue) { i in
                setParam { $0.strumDir = StrumDir.allCases[i] } } } },
                 { bipolarSlider("VOL TILT \(Int((p.velTilt ?? 0) * 100))", p.velTilt ?? 0) { v in setParam { $0.velTilt = v } } })
            optionsCluster([("PER-NOTE RAKE", !(p.strumSpreadNorm ?? true), { setParam { $0.strumSpreadNorm = !($0.strumSpreadNorm ?? true) } })])
        })
        case .chance: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {
            // CHANCE PATTERN (Paul 2026-08-22 §5): SINGLE = one probability · PATTERN = the odds SLIDER LANE (per-step %).
            let cmode = p.chanceMode ?? .single
            field("MODE", \.chanceMode) { seg(ChanceMode.allCases.map(\.rawValue), sel: cmode.rawValue) { i in setParam { $0.chanceMode = ChanceMode.allCases[i] } } }
            Text(cmode == .pattern ? "PATTERN — draw the odds per step (the trig-condition)" : "SINGLE — one probability for every note")
                .font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
            if cmode == .pattern {
                let base: [Int] = [100, 40, 70, 40, 100, 40, 70, 40]
                let shown = (0..<8).map { i -> Int in let s = p.chanceSlices ?? base; return i < s.count ? s[i] : 100 }
                heroField("ODDS PER STEP  (drag to draw · %)") { sliderLane(shown, count: 8, max: 100, eFill: true) { i, v in
                    setParam { var s = $0.chanceSlices ?? base; while s.count < 8 { s.append(100) }; s[i] = v; $0.chanceSlices = s } } }
                field("ROTATE — walk the odds", \.chanceRotate) { numPair(p.chanceRotate ?? 0, 0...7, wrap: true) { v in setParam { $0.chanceRotate = v } } }
            } else {
                heroField("CHANCE \(Int((p.probability ?? 1) * 100))%") {
                    slider(bind(p.probability ?? 1) { v in setParam { $0.probability = v } }, in: 0...1) }
            }
            bipolarSlider("FAVOUR \(Int((p.chanceTilt ?? 0) * 100))  (−bottom · +top)", p.chanceTilt ?? 0) { v in setParam { $0.chanceTilt = v } }
            optionsCluster([("CONSTANT N", p.chanceDensity ?? false, { setParam { $0.chanceDensity = !($0.chanceDensity ?? false) } })])
        })
        case .harmonize: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {
            let iv = p.harmIntervals ?? [0,0,0]
            let hu = p.harmUnits ?? .semitones
            ForEach(0..<3, id: \.self) { k in
                field("VOICE \(k+1) \(iv[k] == 0 ? "off" : (iv[k] > 0 ? "+\(iv[k])" : "\(iv[k])"))") {
                    stepper(iv[k], -24, 24) { v in setParam { var a = $0.harmIntervals ?? [0,0,0]; a[k] = v; $0.harmIntervals = a } }
                }
            }
            field("UNITS", \.harmUnits) { seg(PitchUnits.allCases.map { $0.rawValue }, sel: hu.rawValue) { i in setParam { $0.harmUnits = PitchUnits.allCases[i] } } }   // §2 POOL-STEP
            Text(hu == .pool ? "POOL — intervals count in DEGREES of the pool feeding the chain (a scale ⇒ the diatonic third, in key; a chord ⇒ chord-tone stacking)" : "SEMITONES — fixed chromatic intervals")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        })
        case .echo: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // the DELAY-ECHO controls (user 2026-08-08)
            let reps = p.echoRepeats ?? 3, sync = p.echoSync ?? true, div = p.echoDelayDiv ?? 4
            let ms = p.echoDelayMs ?? 250, off = p.echoOffset ?? 0, fd = p.echoFeedDelay ?? 0.7
            let dec = p.echoDecay ?? 0.5, pit = p.echoPitch ?? 0, thru = p.echoThru ?? true
            let spill = p.echoSpill ?? .ring
            heroField("REPEATS") { numPair(reps, 1...16) { v in setParam { $0.echoRepeats = v } } }
            sectionLabel("TIMING")
            row2({ field("SYNC", \.echoSync) { seg(["ON", "OFF"], sel: sync ? "ON" : "OFF") { i in setParam { $0.echoSync = (i == 0) } } } },
                 { if sync {
                     field("DELAY\(div == 4 ? "  (1 beat)" : "")") { numPair(div, 1...16, format: { "\($0)/16" }) { v in setParam { $0.echoDelayDiv = v } } }
                   } else {
                     field("DELAY  \(Int(ms)) ms") { slider(bind(ms) { v in setParam { $0.echoDelayMs = v } }, in: 10...2000) }
                   } })
            bipolarSlider("NUDGE  \(off > 0 ? "+" : "")\(Int(off * 100))%", off, in: -0.33...0.33) { v in setParam { $0.echoOffset = v } }
            sectionLabel("TONE")
            row2({ field("1ST ECHO  \(Int(fd * 100))%", \.echoFeedDelay) {
                slider(bind(fd) { v in setParam { $0.echoFeedDelay = v } }, in: 0...1) } },
                 { field("FADE  \(Int(dec * 100))%", \.echoDecay) {
                slider(bind(dec) { v in setParam { $0.echoDecay = v } }, in: 0...1) } })
            let epu = p.echoPitchUnits ?? .semitones
            field("PITCH STEP  \(pit > 0 ? "+" : "")\(pit) \(epu == .pool ? "deg" : "st") / echo", \.echoPitch) { stepper(pit, -24, 24) { v in setParam { $0.echoPitch = v } } }
            if pit != 0 { field("UNITS", \.echoPitchUnits) { seg(PitchUnits.allCases.map { $0.rawValue }, sel: epu.rawValue) { i in setParam { $0.echoPitchUnits = PitchUnits.allCases[i] } } } }   // §2: POOL = the trail WALKS THE SCALE (in-key), not chromatic
            sectionLabel("TAIL")
            // ROUTE (§7②, ratified 2026-08-22): DIRECT echoes the cell's final set (v1). CHAIN runs each repeat back
            // through the stages AFTER this ECHO slot — [ECHO→LENGTH] chokes/ties repeats, [ECHO→SPLIT] thins the trail.
            let route = p.echoRoute ?? .direct
            field("ROUTE", \.echoRoute) { seg(["DIRECT", "CHAIN"], sel: route == .chain ? "CHAIN" : "DIRECT") { i in setParam { $0.echoRoute = (i == 0 ? .direct : .chain) } } }
            // DRY = the dry note passes (THRU) · MUTE = echoes only; CUT SPILL keeps repeats inside the bar (RING spills).
            optionsCluster([
                ("DRY", thru, { setParam { $0.echoThru = !($0.echoThru ?? true) } }),
                ("CUT SPILL", spill == .cut, { setParam { $0.echoSpill = ($0.echoSpill ?? .ring) == .cut ? .ring : .cut } }),
            ])
        })
        case .euclid: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // GENERATOR — K-of-N euclidean rhythm; LINES model (§10): up to 8 lines from ONE chord (kick/hat/pulse)
            let steps = p.euclidSteps ?? 8
            let fromPool = p.euclidPulsesFromPool ?? false
            let lines = p.euclidLines ?? []
            field("HITS FROM", \.euclidPulsesFromPool) { seg(["FIXED", "POOL"], sel: fromPool ? "POOL" : "FIXED") { i in setParam { $0.euclidPulsesFromPool = (i == 1) } } }
            if lines.isEmpty {
                // The single euclid (today) — the K-of-N hero row (§presentation ⑤): "◀5▶ of ◀16▶".
                if !fromPool {
                    heroField("HITS OF STEPS") { HStack(spacing: 8) {
                        numPair(p.euclidPulses ?? 5, 1...steps) { v in setParam { $0.euclidPulses = min(v, $0.euclidSteps ?? steps) } }
                        Text("of").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                        numPair(steps, 2...16) { v in setParam { $0.euclidSteps = max(2, v); if ($0.euclidPulses ?? 5) > max(2, v) { $0.euclidPulses = max(2, v) } } }
                    } }
                } else {
                    heroField("STEPS") { numPair(steps, 2...16) { v in setParam { $0.euclidSteps = max(2, v); if ($0.euclidPulses ?? 5) > max(2, v) { $0.euclidPulses = max(2, v) } } } }
                }
                optionsCluster([("INVERT", p.euclidInvert ?? false, { setParam { $0.euclidInvert = !($0.euclidInvert ?? false) } })])
                pill("+ ADD LINE") { setParam {   // convert to LINES: line 1 = the current euclid, + a second line to author
                    let l1 = EuclidLine(target: 0, pulses: $0.euclidPulses ?? 5, steps: $0.euclidSteps ?? 8, rotate: $0.euclidRot ?? 0, invert: $0.euclidInvert ?? false)
                    $0.euclidLines = [l1, EuclidLine(target: 1, pulses: 4, steps: 8, rotate: 0, invert: false)] } }
            } else {
                // THE LINES STACK (§10): each row = TARGET · K of N · ROTATE · HITS/REST · ×
                heroField("LINES — each a euclid from one chord (kick · hat · pulse)") {
                    VStack(spacing: 5) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { (idx, L) in
                            VStack(spacing: 3) {
                                HStack(spacing: 5) {
                                    numPair(L.target, 0...8, format: { $0 == 0 ? "ALL" : "N\($0)" }) { v in euclidLineEdit(idx) { $0.target = v } }
                                    numPair(L.pulses, 0...max(2, L.steps)) { v in euclidLineEdit(idx) { $0.pulses = min(v, $0.steps) } }
                                    Text("of").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                                    numPair(L.steps, 2...16) { v in euclidLineEdit(idx) { $0.steps = max(2, v); if $0.pulses > max(2, v) { $0.pulses = max(2, v) } } }
                                    numPair(L.rotate, 0...15, wrap: true, format: { "↻\($0)" }) { v in euclidLineEdit(idx) { $0.rotate = v } }
                                    Text(L.invert ? "REST" : "HITS").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(L.invert ? accent : .white.opacity(0.45))
                                        .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                                        .contentShape(Rectangle()).onTapGesture { euclidLineEdit(idx) { $0.invert.toggle() } }
                                    Button { setParam { var a = $0.euclidLines ?? []; if idx < a.count { a.remove(at: idx) }; $0.euclidLines = a.isEmpty ? nil : a } } label: {
                                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.red.opacity(0.8)).frame(width: 26, height: 34)
                                    }.buttonStyle(.plain)
                                }
                                if L.target == 0 {   // v1b (Paul 2026-08-26): per-line PICK (what each hit strikes) + DIE (salts CYCLE/RANDOM apart from other lines)
                                    HStack(spacing: 6) {
                                        Text("PICK").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                                        let cur = L.pick ?? (p.euclidPick ?? .all)
                                        Text(cur.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(accent)
                                            .frame(width: 64, height: 24).background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                                            .contentShape(Rectangle())
                                            .onTapGesture { euclidLineEdit(idx) { let all = EuclidPick.allCases; let c = $0.pick ?? (p.euclidPick ?? .all); $0.pick = all[(((all.firstIndex(of: c) ?? 0) + 1) % all.count)] } }
                                        Text("DIE").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                                        numPair(L.dieResolved, 0...8, format: { "⚄\($0)" }) { v in euclidLineEdit(idx) { $0.die = v } }
                                        Spacer(minLength: 0)
                                    }.padding(.leading, 8)
                                }
                            }
                        }
                        if lines.count < 8 { pill("+ ADD LINE") { setParam { var a = $0.euclidLines ?? []; a.append(EuclidLine(target: 0, pulses: 4, steps: 8, rotate: 0, invert: false)); $0.euclidLines = a } } }
                    }
                }
            }
            field("PICK — for ALL-target lines", \.euclidPick) { seg(EuclidPick.allCases.map(\.rawValue), sel: (p.euclidPick ?? .all).rawValue) { i in setParam { $0.euclidPick = EuclidPick.allCases[i] } } }
            frameRow(grid:  { frameGrid(p.euclidRate ?? .r1_16) { r in setParam { $0.euclidRate = r } } },   // §1 ANATOMY FOOTER — GRID = the step rate (density)
                     rotate: { if lines.isEmpty { frameRotate(p.euclidRot ?? 0, 0...15) { v in setParam { $0.euclidRot = v } } } },   // single euclid only (LINES rotate per-line)
                     span:   { frameSpan(p.euclidSpanN ?? 0, free: true) { v in setParam { $0.euclidSpanN = v } } },
                     pairs: .euclid)
        })
        case .burst: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {    // GENERATOR — accel/decel roll (family: ONCE | COIN | PATTERN, Paul 2026-08-19)
            let bmode = p.burstMode ?? .once   // mode set by the storefront card — no in-editor radio (Paul 2026-08-22)
            heroField("HITS") { numPair(p.count ?? 4, 2...16) { v in setParam { $0.count = v } } }
            let cv = p.curve ?? 0
            bipolarSlider("SHAPE  \(cv > 0 ? "ACCEL" : (cv < 0 ? "DECEL" : "EVEN"))  \(Int(cv * 100))%", cv) { v in setParam { $0.curve = v } }
            if bmode == .coin {
                let ch = p.burstChance ?? 0.5
                field("CHANCE  \(Int(ch * 100))%", \.burstChance) { slider(bind(ch) { v in setParam { $0.burstChance = v } }, in: 0...1) }
            }
            if bmode == .pattern {   // a STATE MATRIX — rows = B/C/R, cols = the 8 steps
                let defBurst: [BurstSlice] = [.burst, .carry, .carry, .rest, .burst, .rest, .rest, .rest]
                field("BURST SHAPE PER STEP — tap a cell  (B launch · C carry · R rest)") {
                    stateMatrixRadio(BurstSlice.allCases,
                        header: { st in AnyView(Text(burstSliceName(st)).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75)).frame(width: 46, alignment: .leading)) },
                        eFill: true, onRotate: { d in setParam { $0.burstRotate = ((($0.burstRotate ?? 0) + d) % 8 + 8) % 8 } },
                        selected: { i in let s = p.burstSlices ?? defBurst; return i < s.count ? s[i] : .rest },
                        set: { i, st in setParam { var s2 = $0.burstSlices ?? defBurst; while s2.count < 8 { s2.append(.rest) }; s2[i] = st; $0.burstSlices = s2 } })
                }
                // RATE AXIS (Paul 2026-08-26): FIXED 8 = the span split into 8 slices; RATE = the 8-figure WALKS the span at the footer GRID rate.
                let rateOn = p.burstRateOn ?? false
                field("SLICES  \(rateOn ? "AT RATE" : "FIXED 8")") { seg(["FIXED 8", "RATE"], sel: rateOn ? "RATE" : "FIXED 8") { i in setParam { $0.burstRateOn = (i == 1) } } }
            }
            if bmode == .pattern {   // §1 ANATOMY FOOTER — GRID = the walk rate (active when SLICES = RATE)
                frameRow(grid:  { frameGrid(p.burstRate ?? .r1_8) { r in setParam { $0.burstRate = r } } },
                         rotate: { frameRotate(p.burstRotate ?? 0, 0...7) { v in setParam { $0.burstRotate = v } } },
                         span:   { frameSpan(p.burstSpanN ?? ((p.burstSpan ?? .cell) == .row ? 8 : 1), free: false) { v in setParam { $0.burstSpanN = v } } },
                         pairs: .burst)
            } else {
                spanLadderField(p.burstSpanN ?? ((p.burstSpan ?? .cell) == .row ? 8 : 1)) { v in setParam { $0.burstSpanN = v } }   // ONCE/COIN keep the inline SPAN
            }
        })
        case .cascade: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {  // GENERATOR — incremental chord reveal
            heroField("SPEED") { seg(ArpRate.allCases.map(\.rawValue), sel: (p.rate ?? .r1_8).rawValue) { i in setParam { $0.rate = ArpRate.allCases[i] } } }
            field("ORDER", \.strumDir) { seg(["UP", "DOWN"], sel: (p.strumDir ?? .up) == .down ? "DOWN" : "UP") { i in setParam { $0.strumDir = (i == 0 ? .up : .down) } } }
            // SPAN LADDER (RATE×ladder): RATE = reveal spacing; this dial = the reveal window in columns.
            spanLadderField(p.cascadeSpanN ?? ((p.cascadeSpan ?? .cell) == .row ? 8 : 1)) { v in setParam { $0.cascadeSpanN = v } }
        })
        case .drone: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {    // GENERATOR — flat sustained pad (gate = pad level)
            heroField("LEVEL  \(Int((p.gate ?? 0.6) * 127))") {
                slider(bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1) }
            // STRIKE PER SPAN (Paul 2026-08-27): HOLD = one continuous pad (today) · PER SPAN = re-articulate the pad every N columns.
            field("STRIKE", \.strikePerSpan) { seg(["HOLD", "PER SPAN"], sel: (p.strikePerSpan ?? false) ? "PER SPAN" : "HOLD") { i in setParam { $0.strikePerSpan = (i == 1) } } }
            if p.strikePerSpan ?? false {
                field("RE-STRIKE EVERY") { spanLadderField(p.strikeSpanN ?? 8) { v in setParam { $0.strikeSpanN = v } } }   // finite period (1…×4); 8 = once per row lap
            }
        })
        case .shift: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {    // GENERATOR — groove nudge (spread = push late)
            heroField("PUSH  \(Int((p.spread ?? 0.1) * 100))% late") {
                slider(bind(p.spread ?? 0.1) { v in setParam { $0.spread = v } }, in: 0...1) }
        })
        case .humanize: AnyView(VStack(alignment: .leading, spacing: rowSpacing) { // GENERATOR — seeded jitter (spread = amount)
            heroField("FEEL  \(Int((p.spread ?? 0.5) * 100))%") {
                slider(bind(p.spread ?? 0.5) { v in setParam { $0.spread = v } }, in: 0...1) }
        })
        case .mod: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {      // CC GENERATOR / CC-stage §1 — a SOURCE spine (row 2 reshapes) + a universal TARGET/RANGE (row 3)
            let src = p.modSource ?? .shape    // source set by the storefront card — no in-editor radio (Paul 2026-08-22)
            switch src {
            case .shape:
                heroField("WAVE") { iconSeg(ModShape.allCases.map(\.rawValue), sel: (p.modShape ?? .sine).rawValue, glyph: { i, t in waveGlyph(ModShape.allCases[i], t) }) { i in setParam { $0.modShape = ModShape.allCases[i] } } }
                field("CYCLE  (beats / cycle)", \.modRate) { seg(ModRate.allCases.map(\.rawValue), sel: (p.modRate ?? .r2).rawValue) { i in setParam { $0.modRate = ModRate.allCases[i] } } }
            case .follow:
                field("LISTEN TO", \.modFollow) { seg(ModFollow.allCases.map(\.rawValue), sel: (p.modFollow ?? .register).rawValue) { i in setParam { $0.modFollow = ModFollow.allCases[i] } } }
            case .steps:
                let sspan = p.modStepSpan ?? ((p.modSpan == .row) ? .row : .period)   // migrate the old cell|row span for display
                let n = sspan.stepCount
                let base = [0, 18, 36, 54, 72, 90, 108, 127]
                let shown = (0..<n).map { i -> Int in let s = p.modSteps ?? base; return s[i % s.count] }   // pad the stored steps to N for drawing
                heroField("STEPS  (drag to draw · \(n))") { sliderLane(shown, count: n, eFill: true) { i, v in
                    setParam { var s = $0.modSteps ?? base; let orig = s; while s.count < n { s.append(orig[s.count % orig.count]) }; s[i] = v; $0.modSteps = s } } }
                field("SPAN", \.modStepSpan) { seg(ModStepSpan.allCases.map(\.rawValue), sel: sspan.rawValue) { i in setParam { $0.modStepSpan = ModStepSpan.allCases[i] } } }   // PERIOD (rate) · ROW · ROW×2 · ROW×4 (16/32 breakpoints)
                if sspan == .period { field("CYCLE  (beats / cycle)", \.modRate) { seg(ModRate.allCases.map(\.rawValue), sel: (p.modRate ?? .r2).rawValue) { i in setParam { $0.modRate = ModRate.allCases[i] } } } }   // the rate period only drives PERIOD span
                field("GLIDE", \.modSmooth) { seg(["SMOOTH", "STEP"], sel: (p.modSmooth ?? true) ? "SMOOTH" : "STEP") { i in setParam { $0.modSmooth = (i == 0) } } }
            case .strike:
                field("RISE  \(String(format: "%.2f", p.modAttack ?? 0.15)) beats", \.modAttack) {
                    slider(bind(p.modAttack ?? 0.15) { v in setParam { $0.modAttack = v } }, in: 0.01...4, detents: [0.25, 0.5, 1, 2]) }
                field("FALL  \(String(format: "%.2f", p.modRelease ?? 0.6)) beats", \.modRelease) {
                    slider(bind(p.modRelease ?? 0.6) { v in setParam { $0.modRelease = v } }, in: 0.01...4, detents: [0.25, 0.5, 1, 2]) }
            case .extern:
                let ec = p.modExternCC ?? 1
                field("FROM CC", \.modExternCC) { numPair(ec, 0...127, format: { ccLabelText($0) }) { v in setParam { $0.modExternCC = v } } }
            }
            if src == .shape {                                     // SHAPE keeps CELL|ROW; STEPS has its own 4-way SPAN above
                let mspan = p.modSpan ?? .cell
                field("SPAN", \.modSpan) { seg(["CELL", "ROW"], sel: mspan == .row ? "ROW" : "CELL") { i in setParam { $0.modSpan = (i == 1) ? .row : .cell } } }   // CELL = the CYCLE period · ROW = one cycle spans the bar
            }
            let target = p.modTarget ?? .cc
            sectionLabel("TARGET")
            field("SEND", \.modTarget) { seg(ModTarget.allCases.map { $0 == .chain ? "THIS CHAIN" : $0.rawValue }, sel: target == .chain ? "THIS CHAIN" : "CC") { i in setParam { $0.modTarget = ModTarget.allCases[i] } } }   // §2: CC (emit) | THIS CHAIN (modulate a chain param, no CC)
            if target == .cc {
                let cc = p.modCC ?? 74
                field("SEND CC", \.modCC) { numPair(cc, 0...127, format: { ccLabelText($0) }) { v in setParam { $0.modCC = v } } }
            } else {
                let params: [MacroParam] = [.gate, .ramp, .spread, .curve, .velTilt, .probability, .harmVelScale, .tuttiBalance, .lenShort, .lenLong, .rtcChance]
                let cur = p.modChainParam ?? .gate
                field("CHAIN PARAM", \.modChainParam) {
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
            row2({ field("MIN  \(lo)", \.modMin) {
                slider(bind(Double(lo)) { v in setParam { $0.modMin = Int(v.rounded()) } }, in: 0...127) } },
                 { field("MAX  \(hi)\(lo > hi ? "  (inv)" : "")", \.modMax) {
                slider(bind(Double(hi)) { v in setParam { $0.modMax = Int(v.rounded()) } }, in: 0...127) } })
            field("ON EXIT", \.modReset) { seg(["RESET", "LEAVE"], sel: (p.modReset ?? true) ? "RESET" : "LEAVE") { i in setParam { $0.modReset = (i == 0) } } }
        })
        case .glide: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {    // one mono sliding voice — small steps bend, big leaps jump (Paul 2026-08-22)
            let gmode = p.glideMode ?? .bend
            heroField("MODE") { seg(GlideMode.allCases.map(\.rawValue), sel: gmode.rawValue) { i in setParam { $0.glideMode = GlideMode.allCases[i] } } }
            Text(glideModeBlurb(gmode)).font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
            // TERMINAL (Paul 2026-08-25): GLIDE is one mono voice + continuous bend — it does NOT feed a downstream stage.
            // Say so, so a [GLIDE→X] chain isn't a silent surprise.
            Text("TERMINAL — GLIDE is the last stage. A processor placed after it is not fed.")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(UI.amber.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            if gmode == .bend {
                row2({ field("TIME  \(String(format: "%.2f", p.glideTime ?? 0.25)) beats") {
                    slider(bind(p.glideTime ?? 0.25) { v in setParam { $0.glideTime = v } }, in: 0...2, detents: [0, 0.25, 0.5, 1, 2]) } },
                     { field("BEND RANGE  ±\(p.glideRange ?? 2) st") {
                    slider(bind(Double(p.glideRange ?? 2)) { v in setParam { $0.glideRange = Int(v.rounded()) } }, in: 1...48, detents: [12, 24, 36, 48]) } })
            } else {
                field(gmode == .step ? "RUN TIME  \(String(format: "%.2f", p.glideTime ?? 0.25)) beats" : "TIME  \(String(format: "%.2f", p.glideTime ?? 0.25)) beats") {
                    slider(bind(p.glideTime ?? 0.25) { v in setParam { $0.glideTime = v } }, in: 0...2, detents: [0, 0.25, 0.5, 1, 2]) }
            }
            field("FOLLOW", \.glidePriority) { seg(GlidePriority.allCases.map(\.rawValue), sel: (p.glidePriority ?? .last).rawValue) { i in setParam { $0.glidePriority = GlidePriority.allCases[i] } } }
            if gmode == .bend {
                field("TOO FAR") { seg(["RE-ANCHOR", "CLAMP"], sel: (p.glideReanchor ?? true) ? "RE-ANCHOR" : "CLAMP") { i in setParam { $0.glideReanchor = (i == 0) } } }
            }
        })
        case .tutti: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {    // SET-level chance — one MODE radio; COIN now, PATTERN in phase 2
            // mode set by the storefront card — no in-editor radio (Paul 2026-08-22)
            if (p.tuttiMode ?? .coin) == .coin {
                heroField("BALANCE   SOLO  ◂  \(Int((p.tuttiBalance ?? 0.5) * 100))%  ▸  TUTTI") {   // the slider IS the idea
                    slider(bind(p.tuttiBalance ?? 0.5) { v in setParam { $0.tuttiBalance = v } }, in: 0...1) }
                field("SOLO NOTE  (which note carries a SOLO step)", \.tuttiPick) { seg(TuttiPick.allCases.map(\.rawValue), sel: (p.tuttiPick ?? .low).rawValue) { i in
                    setParam { $0.tuttiPick = TuttiPick.allCases[i] } } }
            } else {
                // An 8×8 STATE MATRIX — rows = the chord shapes, columns = the 8 steps; tap a cell to set that step.
                heroField("CHORD SHAPE PER STEP — tap a cell (dots = which notes sound)") {
                    stateMatrixRadio(TuttiSlice.allCases,
                        header: { st in AnyView(HStack(spacing: 4) {
                            tuttiShapeIcon(st, tint: accent).frame(width: 16)
                            Text(st.rawValue).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                        }) },
                        eFill: true, onRotate: { d in setParam { $0.tuttiRotate = ((($0.tuttiRotate ?? 0) + d) % 8 + 8) % 8 } },
                        selected: { i in tuttiSliceAt(p.tuttiSlices, i) },
                        set: { i, st in setParam { var s = $0.tuttiSlices ?? Array(repeating: .all, count: 8); while s.count < 8 { s.append(.all) }; s[i] = st; $0.tuttiSlices = s } })
                }
            }
            // §1 STANDARD PANEL ANATOMY — THE FOOTER: the frame row (GRID · ROTATE · SPAN, PATTERN mode only), then pairs-well.
            if (p.tuttiMode ?? .coin) == .pattern {
                frameRow(grid:  { frameGrid(p.tuttiRate ?? .r1_8) { r in setParam { $0.tuttiRate = r } } },
                         rotate: { frameRotate(p.tuttiRotate ?? 0, 0...7) { v in setParam { $0.tuttiRotate = v } } },
                         span:   { frameSpan(p.tuttiSpanN ?? 0, free: true) { v in setParam { $0.tuttiSpanN = v } } },
                         pairs: .tutti)
            }
        })
        case .length: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // per-slice GATE override — PASS/MUTE/SHORT/LONG as a STATE MATRIX (rows = states, cols = steps)
            heroField("LENGTH PER STEP — tap a cell: that step takes that length") {
                stateMatrixRadio(LenState.allCases,
                    header: { st in AnyView(HStack(spacing: 5) {
                        lenGlyph(st, tint: accent).frame(width: 20)
                        Text(st.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
                    }) },
                    eFill: true, onRotate: { d in setParam { $0.lenRotate = ((($0.lenRotate ?? 0) + d) % 8 + 8) % 8 } },
                    selected: { i in lenSliceAt(p.lenSlices, i) },
                    set: { i, st in setParam { var s = $0.lenSlices ?? Array(repeating: .pass, count: 8); while s.count < 8 { s.append(.pass) }; s[i] = st; $0.lenSlices = s } })
            }
            row2({ field("SHORT =  \(Int((p.lenShort ?? 0.4) * 100))%", \.lenShort) {
                slider(bind(p.lenShort ?? 0.4) { v in setParam { $0.lenShort = v } }, in: 0.05...0.95) } },
                 { field("LONG =  \(Int((p.lenLong ?? 0.7) * 100))%", \.lenLong) {
                slider(bind(p.lenLong ?? 0.7) { v in setParam { $0.lenLong = v } }, in: 0...1) } })
            field("ROTATE — shift the phrasing", \.lenRotate) { numPair(p.lenRotate ?? 0, 0...7, wrap: true) { v in setParam { $0.lenRotate = v } } }
            spanLadderField(p.lenSpanN ?? ((p.lenSpan ?? .cell) == .row ? 8 : 1)) { v in setParam { $0.lenSpanN = v } }
        })
        case .weave: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // rank-clocked polyrhythm driver — each held note on its own clock
            let wmode = p.weaveMode ?? .ladder   // mode set by the storefront card — no in-editor radio (Paul 2026-08-22)
            Text(weaveModeBlurb(wmode)).font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            if wmode == .ladder || wmode == .harmonic {
                heroField("BASS CLOCK — the bass rank's clock (higher ranks weave faster)") { seg(StepRate.allCases.map(\.rawValue), sel: (p.weaveBaseStep ?? .r1_4).rawValue) { i in
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
                field("STEPS  \(p.weaveEuclidSteps ?? 8)  (bass fills 1, each rank up fills 2 more)", \.weaveEuclidSteps) {
                    slider(bind(Double(p.weaveEuclidSteps ?? 8)) { v in setParam { $0.weaveEuclidSteps = Int(v.rounded()) } }, in: 2...16) }
            }
            field("NEW CHORD — RETRIG restarts each step · FREE runs the grid · LEGATO flows from the hold", \.weavePhase) { seg(ArpPhase.allCases.map(\.rawValue), sel: (p.weavePhase ?? .retrig).rawValue) { i in
                setParam { $0.weavePhase = ArpPhase.allCases[i] } } }
            row2({ field("VOICES — how many weave", \.weaveSpan) { numPair(p.weaveSpan ?? 4, 1...8) { v in setParam { $0.weaveSpan = v } } } },
                 { field("LENGTH \(Int((p.gate ?? 0.6) * 100))%", \.gate) {
                slider(bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1) } })
        })
        case .split: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // set-membership filter — keep a subset of the chord (before a driver = re-pool · after = punch holes)
            let sm = p.splitSet?.mode ?? .all
            heroField("KEEP") { seg(SplitMode.allCases.map(\.rawValue), sel: sm.rawValue) { i in
                setParam { var c = $0.splitSet ?? ChordSplit(); c.mode = SplitMode.allCases[i]; $0.splitSet = c } } }
            if sm == .top || sm == .bottom {
                field("NOTES — how many notes", \.splitSet) { numPair(p.splitSet?.n ?? 2, 1...6) { v in setParam { var c = $0.splitSet ?? ChordSplit(); c.n = v; $0.splitSet = c } } }
            } else if sm == .range {
                field("AT NOTE  \(midiNoteName(UInt8(max(0, min(127, p.splitSet?.note ?? 60)))))") {
                    slider(bind(Double(p.splitSet?.note ?? 60)) { v in setParam { var c = $0.splitSet ?? ChordSplit(); c.note = Int(v.rounded()); $0.splitSet = c } }, in: 0...127) }
                field("SIDE", \.splitSet) { seg(["≥ SPLIT", "< SPLIT"], sel: (p.splitSet?.high ?? true) ? "≥ SPLIT" : "< SPLIT") { i in
                    setParam { var c = $0.splitSet ?? ChordSplit(); c.high = (i == 0); $0.splitSet = c } } }
            }
            field("VEL MIN  \(p.splitVel?.floor ?? 1)") {
                slider(bind(Double(p.splitVel?.floor ?? 1)) { v in setParam { var w = $0.splitVel ?? VelWindow(); w.floor = min(Int(v.rounded()), w.ceil); $0.splitVel = w } }, in: 1...127) }
            field("VEL MAX  \(p.splitVel?.ceil ?? 127)") {
                slider(bind(Double(p.splitVel?.ceil ?? 127)) { v in setParam { var w = $0.splitVel ?? VelWindow(); w.ceil = max(Int(v.rounded()), w.floor); $0.splitVel = w } }, in: 1...127) }
        })
        case .octave: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // UTILITY — shift ±3 octaves (pitch-class preserved)
            let oct = p.utilOctave ?? 0
            field("OCTAVE  \(oct > 0 ? "+" : "")\(oct)", \.utilOctave) { stepper(oct, -3, 3) { v in setParam { $0.utilOctave = v } } }
        })
        case .transpose: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // UTILITY — shift ±24 semitones OR ±24 pool degrees (§2)
            let st = p.utilTranspose ?? 0
            let tu = p.utilTransposeUnits ?? .semitones
            field("\(tu == .pool ? "DEGREES" : "SEMITONES")  \(st > 0 ? "+" : "")\(st)", \.utilTranspose) { stepper(st, -24, 24) { v in setParam { $0.utilTranspose = v } } }
            field("UNITS", \.utilTransposeUnits) { seg(PitchUnits.allCases.map { $0.rawValue }, sel: tu.rawValue) { i in setParam { $0.utilTransposeUnits = PitchUnits.allCases[i] } } }
            Text(tu == .pool ? "POOL — “up a third in key”: steps DEGREES through the pool feeding the chain" : "SEMITONES — a fixed chromatic shift")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        })
        case .channel: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // UTILITY — output channel override (WIRE = the bus stamp)
            let ch = p.utilChannel ?? 0
            field("CHANNEL", \.utilChannel) { numPair(ch, 0...16, wrap: true, format: { $0 == 0 ? "WIRE" : "\($0)" }) { v in setParam { $0.utilChannel = v } } }
        })
        case .nudge: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // UTILITY — time offset in sixteenths; FIXED (one) | LANE (the pocket, drawn per column)
            let nmode = p.utilNudgeMode ?? .fixed
            field("MODE", \.utilNudgeMode) { seg(NudgeMode.allCases.map(\.rawValue), sel: nmode.rawValue) { i in setParam { $0.utilNudgeMode = NudgeMode.allCases[i] } } }
            Text(nmode == .lane ? "LANE — draw a push/pull per column (the pocket)" : "FIXED — one time offset for the whole chain")
                .font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
            if nmode == .lane {
                let base = [Int](repeating: 0, count: 8)
                let shown = (0..<8).map { i -> Int in let s = p.utilNudgeLane ?? base; return i < s.count ? s[i] : 0 }
                field("POCKET PER STEP  (drag · ±8/16 · centre = on-grid)") { sliderLane(shown, count: 8, max: 8, center: true, eFill: true) { i, v in
                    setParam { var s = $0.utilNudgeLane ?? base; while s.count < 8 { s.append(0) }; s[i] = v; $0.utilNudgeLane = s } } }
            } else {
                let nu = p.utilNudge ?? 0
                field("NUDGE  \(nu > 0 ? "+" : "")\(nu)/16 beat", \.utilNudge) { stepper(nu, -8, 8) { v in setParam { $0.utilNudge = v } } }
            }
        })
        case .dest: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {    // ROUTING (Paul 2026-08-22 §5) — the DEST MATRIX: which emitter each onset-slice hockets to
            let base = [0, 1, 2, 3, 0, 1, 2, 3]
            field("EMITTER PER STEP — tap a cell (the hocket)") {
                stateMatrixRadio([0, 1, 2, 3],
                    header: { e in AnyView(Text(["A", "B", "C", "D"][e]).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75)).frame(width: 22, alignment: .leading)) },
                    selected: { i in let s = p.destSlices ?? base; return i < s.count ? s[i] : 0 },
                    set: { i, e in setParam { var s = $0.destSlices ?? base; while s.count < 8 { s.append(0) }; s[i] = e; $0.destSlices = s } })
            }
        })
        case .muteMatrix: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // ROUTING (Paul 2026-08-25 §5) — the MUTE MATRIX: per-step PART-MUTING (A/B/C/D × 8 multi-select)
            field("MUTE PER COLUMN — tap to silence an emitter on that grid column") {
                VStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { e in
                        HStack(spacing: 3) {
                            EBrushButton(steps: 8, accent: accent) { pat in setParam { var arr = $0.muteSlices ?? Array(repeating: 0, count: 8); while arr.count < 8 { arr.append(0) }; for s in 0..<8 { if pat[s] { arr[s] |= (1 << e) } else { arr[s] &= ~(1 << e) } }; $0.muteSlices = arr } }   // §5 E-BRUSH: euclidean mute pattern for this emitter
                            Text(["A", "B", "C", "D"][e]).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75)).frame(width: 22, alignment: .leading)
                            ForEach(0..<8, id: \.self) { step in
                                let s = p.muteSlices ?? Array(repeating: 0, count: 8)
                                let muted = ((step < s.count ? s[step] : 0) >> e) & 1 == 1
                                let live = step == liveStep                   // PLAYHEAD (idea 15): the live grid column
                                RoundedRectangle(cornerRadius: 4).fill(muted ? Color.red.opacity(0.8) : Color.white.opacity(live ? 0.14 : 0.06))
                                    .frame(maxWidth: .infinity).frame(height: 24)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(muted ? 0.9 : 0.12), lineWidth: muted ? 1.5 : 1))
                                    .overlay { if muted { Image(systemName: "speaker.slash.fill").font(.system(size: 9, weight: .black)).foregroundColor(.white) } }
                                    .overlay(alignment: .top) { if live { Rectangle().fill(Color.white.opacity(0.9)).frame(height: 2) } }
                                    .contentShape(Rectangle()).onTapGesture {
                                        setParam { var arr = $0.muteSlices ?? Array(repeating: 0, count: 8); while arr.count < 8 { arr.append(0) }; arr[step] ^= (1 << e); $0.muteSlices = arr }
                                    }
                            }
                        }
                    }
                }
            }
        })
        case .riff: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // RIFF (SPEC-riff-processor) — THE RANK MATRIX: rows = pool ranks 1–8 · cols = steps · empty column = REST.
            let steps = max(1, min(32, p.riffSteps ?? 16))
            let poly = p.riffPoly ?? false   // POLY (Paul 2026-08-26): a step strikes a SET of ranks; MONO = one rank
            let dr = [1, 2, 3, 0, 2, 3, 4, 0, 1, 2, 3, 0, 5, 4, 3, 0]   // the default figure (matches SnapParams)
            let ranks = p.riffRanks ?? dr
            let mask = p.riffMask ?? []
            heroField(poly ? "THE STENCIL — POLY: tap ranks per step (a chord that follows the held chord)" : "THE STENCIL — tap a rank per step (empty column = rest); the held chord fills it") {
                VStack(spacing: 2) {
                    ForEach(Array((1...8).reversed()), id: \.self) { rank in
                        let bit = 1 << (rank - 1)
                        let allThis = poly ? (0..<steps).allSatisfy { ((($0 < mask.count ? mask[$0] : 0)) & bit) != 0 }
                                           : (0..<steps).allSatisfy { ($0 < ranks.count ? ranks[$0] : 0) == rank }
                        HStack(spacing: 2) {
                            Text("\(rank)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5)).frame(width: 16)
                            ForEach(0..<steps, id: \.self) { s in
                                let on = poly ? (((s < mask.count ? mask[s] : 0) & bit) != 0) : ((s < ranks.count ? ranks[s] : 0) == rank)
                                RoundedRectangle(cornerRadius: 3).fill(on ? accent : Color.white.opacity(0.06))
                                    .frame(maxWidth: .infinity).frame(height: 16)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(on ? 0.9 : 0.1), lineWidth: on ? 1.5 : 1))
                                    .contentShape(Rectangle()).onTapGesture {
                                        setParam {
                                            if poly { var a = $0.riffMask ?? []; while a.count < steps { a.append(0) }; a[s] ^= bit; $0.riffMask = a }   // POLY: toggle the rank's bit
                                            else { var a = $0.riffRanks ?? dr; while a.count < steps { a.append(0) }; a[s] = (a[s] == rank ? 0 : rank); $0.riffRanks = a }   // MONO: radio-per-column
                                        }
                                    }
                            }
                            // SET-ROW (Paul 2026-08-25): fill EVERY step with this rank (tap again = clear). Rank 1 = the lowest held note.
                            RoundedRectangle(cornerRadius: 3).fill(allThis ? accent.opacity(0.55) : Color.white.opacity(0.08))
                                .frame(width: 30, height: 16)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(allThis ? 0.8 : 0.2), lineWidth: 1))
                                .overlay(Text("SET").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75)))
                                .contentShape(Rectangle()).onTapGesture {
                                    setParam {
                                        if poly { var a = $0.riffMask ?? []; while a.count < steps { a.append(0) }; for i in 0..<steps { if allThis { a[i] &= ~bit } else { a[i] |= bit } }; $0.riffMask = a }
                                        else { var a = $0.riffRanks ?? dr; while a.count < steps { a.append(0) }; let t = allThis ? 0 : rank; for i in 0..<steps { a[i] = t }; $0.riffRanks = a }
                                    }
                                }
                        }
                    }
                }
            }
            // §5 MODIFIER LANES (Paul 2026-08-26): OCT (−·0·+) · ACCENT (louder) · TIE (⌒ hold) · SLIDE (↝ 303 glide).
            let octA = p.riffOct ?? [], accA = p.riffAccent ?? [], tieA = p.riffTie ?? [], slA = p.riffSlide ?? []
            field("OCT  −·0·+") {
                HStack(spacing: 2) { Color.clear.frame(width: 16, height: 14)
                    ForEach(0..<steps, id: \.self) { s in
                        let v = s < octA.count ? octA[s] : 0
                        RoundedRectangle(cornerRadius: 3).fill(v == 0 ? Color.white.opacity(0.06) : accent.opacity(0.5)).frame(maxWidth: .infinity).frame(height: 15)
                            .overlay(Text(v > 0 ? "+" : (v < 0 ? "−" : "·")).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(v == 0 ? 0.35 : 0.95)))
                            .contentShape(Rectangle()).onTapGesture { setParam { var a = $0.riffOct ?? []; while a.count < steps { a.append(0) }; a[s] = a[s] >= 1 ? -1 : a[s] + 1; $0.riffOct = a } }
                    }
                    Color.clear.frame(width: 30, height: 14)
                }
            }
            riffToggleLane("ACCENT", steps: steps, on: { $0 < accA.count && accA[$0] > 0 }, accent: accent, glyph: "▲") { s in setParam { var a = $0.riffAccent ?? []; while a.count < steps { a.append(0) }; a[s] = a[s] > 0 ? 0 : 40; $0.riffAccent = a } }
            riffToggleLane("TIE  ⌒", steps: steps, on: { $0 < tieA.count && tieA[$0] }, accent: accent, glyph: "⌒") { s in setParam { var a = $0.riffTie ?? []; while a.count < steps { a.append(false) }; a[s].toggle(); $0.riffTie = a } }
            riffToggleLane("SLIDE  ↝", steps: steps, on: { $0 < slA.count && slA[$0] }, accent: accent, glyph: "↝") { s in setParam { var a = $0.riffSlide ?? []; while a.count < steps { a.append(false) }; a[s].toggle(); $0.riffSlide = a } }
            row2({ field("STEPS", \.riffSteps) { numPair(steps, 1...32) { v in setParam { $0.riffSteps = v } } } },
                 { field("VOICING", \.riffPoly) { seg(["MONO", "POLY"], sel: poly ? "POLY" : "MONO") { i in setParam { $0.riffPoly = (i == 1) } } } })
            field("WRAP — a rank past the chord", \.riffWrap) { seg(RiffWrap.allCases.map(\.rawValue), sel: (p.riffWrap ?? .fold).rawValue) { i in setParam { $0.riffWrap = RiffWrap.allCases[i] } } }
            frameRow(grid:  { frameGrid(p.riffRate ?? .r1_16) { r in setParam { $0.riffRate = r } } },   // §1 ANATOMY FOOTER (riff has no ROTATE)
                     rotate: { EmptyView() },
                     span:   { frameSpan(p.riffSpanN ?? 0, free: true) { v in setParam { $0.riffSpanN = v } } },
                     pairs: .riff)
        })
        case .tap: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // ROUTING (AcceptanceCriteria-tap-processor) — the mid-chain send: LEVEL · TO · MUTE
            let lv = p.tapLevel ?? 1.0
            heroField("LEVEL  \(Int(lv * 100))%  (the send fader)") { slider(bind(lv) { v in setParam { $0.tapLevel = v } }, in: 0...1.5) }
            field("TO — where the copy exits", \.tapTo) { seg(["THIS", "A", "B", "C", "D"], sel: ["THIS", "A", "B", "C", "D"][max(0, min(4, p.tapTo ?? 0))]) { i in setParam { $0.tapTo = i } } }
            optionsCluster([("MUTE", p.tapMute ?? false, { setParam { $0.tapMute = !($0.tapMute ?? false) } })])
        })
        case .hocket: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // DRIVER (AcceptanceCriteria-hocket-processor) — listen to a wire; play in its GAPS or TRADE its hits
            let hm = p.hocketMode ?? .gaps
            heroField("LISTEN TO — the wire") { seg(["A", "B", "C", "D"], sel: ["A", "B", "C", "D"][max(0, min(3, p.hocketSource ?? 0))]) { i in setParam { $0.hocketSource = i } } }
            field("MODE", \.hocketMode) { seg(HocketMode.allCases.map(\.rawValue), sel: hm.rawValue) { i in setParam { $0.hocketMode = HocketMode.allCases[i] } } }
            Text(hm == .trade ? "TRADE — answer each of the wire's hits, hit-for-hit" : "GAPS — play only in the wire's silences (call-and-response)")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            field("RATE — its decision grid", \.hocketRate) { seg(ArpRate.allCases.map(\.rawValue), sel: (p.hocketRate ?? .r1_8).rawValue) { i in setParam { $0.hocketRate = ArpRate.allCases[i] } } }
            Text("Plays YOUR held notes (WHAT) timed by the wire (WHEN). Put it on a later row than what it listens to.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        })
        case .avoid: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // FILTER — the per-note pitch filter (avoid clashes / lock to key), placeable anywhere
            let rk = p.avoidRefKind ?? .sounding
            let md = p.avoidMode ?? .avoid
            let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            heroField("REFERENCE") { seg(AvoidRefKind.allCases.map(\.rawValue), sel: rk.rawValue) { i in setParam { $0.avoidRefKind = AvoidRefKind.allCases[i] } } }
            if rk == .door || rk == .wire {
                field(rk == .door ? "WHICH DOOR" : "WHICH WIRE", \.avoidRefIndex) { seg(["A", "B", "C", "D"], sel: ["A", "B", "C", "D"][max(0, min(3, p.avoidRefIndex ?? 0))]) { i in setParam { $0.avoidRefIndex = i } } }
            }
            if rk == .key {
                field("KEY", \.avoidRoot) { seg(noteNames, sel: noteNames[(((p.avoidRoot ?? 0) % 12) + 12) % 12]) { i in setParam { $0.avoidRoot = i } } }
                field("SCALE", \.avoidScale) { seg(ScaleType.allCases.map(\.label), sel: (p.avoidScale ?? .major).label) { i in setParam { $0.avoidScale = ScaleType.allCases[i] } } }
            }
            field("MODE", \.avoidMode) { seg(AvoidMode.allCases.map(\.rawValue), sel: md.rawValue) { i in setParam { $0.avoidMode = AvoidMode.allCases[i] } } }
            field("REJECTS", \.avoidAction) { seg(AvoidAction.allCases.map(\.rawValue), sel: (p.avoidAction ?? .remove).rawValue) { i in setParam { $0.avoidAction = AvoidAction.allCases[i] } } }
            Text(md == .lock ? "LOCK — keep only notes IN the reference (in-key)." : "AVOID — remove notes that CLASH with the reference.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Before a driver it filters the pool; after one it drops (REMOVE) or shifts (MOVE) each note. For a live reference, put it on a later row.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        })
        }
    }

    // GLIDE mode teach-in-place one-liners (Paul 2026-08-22 — the §7 teach-in-place law).
    private func glideModeBlurb(_ m: GlideMode) -> String {
        switch m {
        case .bend:  return "BEND — slides by pitch-bend. BEND RANGE must match your synth's setting."
        case .synth: return "SYNTH — your synth glides (CC65 on + CC5 time, notes legato). Polyphonic if the synth allows."
        case .step:  return "STEP — a fast chromatic run between notes. Works on any synth; sounds stepped."
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

    /// THE STATE MATRIX (Paul 2026-08-22): rows = options · columns = 8 steps · RADIO-PER-COLUMN (exactly one lit per
    /// step). Retires pick-then-paint — every touch responds instantly (tap a cell = that step takes that state, no
    /// brush, no dead first touch). Row headers (left edge) carry the option's glyph + name — permanent and positional;
    /// the whole pattern reads as geometry. One reusable widget for LENGTH · RATCHET PATTERN · TUTTI PATTERN · … .
    @ViewBuilder private func stateMatrixRadio<Opt: Hashable>(
        _ options: [Opt], header: @escaping (Opt) -> AnyView, eFill: Bool = false, onRotate: ((Int) -> Void)? = nil,
        selected: @escaping (Int) -> Opt, set: @escaping (Int, Opt) -> Void
    ) -> some View {
        let grid = VStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { (_, opt) in
                HStack(spacing: 3) {
                    if eFill { EBrushButton(steps: 8, accent: accent) { pat in for s in 0..<8 { set(s, pat[s] ? opt : options[0]) } } }   // §5 E-BRUSH: fill this state on K columns, rest = the default (options[0])
                    header(opt).frame(width: 64, alignment: .leading)
                    ForEach(0..<8, id: \.self) { step in
                        let on = selected(step) == opt
                        let live = step == liveStep                       // PLAYHEAD (idea 15): the live grid column
                        RoundedRectangle(cornerRadius: 4).fill(on ? accent : Color.white.opacity(live ? 0.14 : 0.06))
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(on ? 0.9 : 0.12), lineWidth: on ? 1.5 : 1))
                            .overlay(alignment: .top) { if live { Rectangle().fill(Color.white.opacity(0.9)).frame(height: 2) } }
                            .contentShape(Rectangle()).onTapGesture { set(step, opt) }
                    }
                }
            }
        }
        if let onRotate { grid.modifier(RotateOnDrag(onRotate: onRotate)) } else { grid }   // ROTATE §2: drag the matrix to rotate
    }
    // ECHO: a 1…16 selector as an 8×2 box (user 2026-08-08) — repeats + the synced 16th-note delay both use it.

    // CC-stage §1: a labelled CC number ("74 · CUTOFF" for the named dozen, else the bare number).
    private func ccLabelText(_ n: Int) -> String { ccName(n).map { "\(n) · \($0)" } ?? "\(n)" }
    // STEPS "drag to draw": `count` vertical bars (8/16/32 by SPAN); drag a column to set its 0…127 value.
    // THE SLIDER LANE (Paul 2026-08-22 §2): 8+ per-step bars — TAP sets to tap-height (first touch always responds), DRAG
    // draws the lane. The ONE shared continuous-per-step component: STEP MOD (CC 0…127) · CHANCE PATTERN (odds 0…100) ·
    // (future VELOCITY PATTERN · CHOP levels). `max` = the value ceiling; the bar height + the write both scale to it.
    private func sliderLane(_ steps: [Int], count: Int = 8, max maxV: Int = 127, center: Bool = false, eFill: Bool = false, _ set: @escaping (Int, Int) -> Void) -> some View {
        HStack(spacing: 6) {
        if eFill { EBrushButton(steps: count, accent: accent) { pat in for i in 0..<count { set(i, pat[i] ? maxV : 0) } } }   // §5 E-BRUSH: euclidean fill (hit = max, rest = 0)
        ZStack(alignment: .top) {
        HStack(spacing: count > 16 ? 1 : (count > 8 ? 2 : 4)) {
            ForEach(0..<count, id: \.self) { i in
                let v = i < steps.count ? steps[i] : 0
                let live = i == liveStep                       // PLAYHEAD (idea 15): the live grid column
                GeometryReader { g in
                    let h = g.size.height
                    ZStack(alignment: center ? .center : .bottom) {   // CENTRE = a bipolar lane (0 = mid, + above, − below) — the TIMING pocket
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(live ? 0.16 : 0.08))
                        if center {
                            let frac = CGFloat(v) / CGFloat(maxV)   // −1…1
                            let barH = Swift.max(2, abs(frac) * h / 2)
                            RoundedRectangle(cornerRadius: 3).fill(accent).frame(height: barH).offset(y: frac >= 0 ? -barH / 2 : barH / 2)
                        } else {
                            RoundedRectangle(cornerRadius: 3).fill(accent).frame(height: Swift.max(2, h * CGFloat(v) / CGFloat(maxV)))
                        }
                    }
                    .overlay(alignment: .top) { if live { Rectangle().fill(Color.white.opacity(0.9)).frame(height: 2) } }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                        let y = min(1, Swift.max(0, val.location.y / Swift.max(1, h)))   // 0 top … 1 bottom
                        let nv = center ? Int(((0.5 - y) * 2 * CGFloat(maxV)).rounded()) : Int((1 - y) * CGFloat(maxV))
                        set(i, nv); laneReadout = (center && nv > 0 ? "+" : "") + "\(nv)"   // idea 18: float the value
                    }.onEnded { _ in laneReadout = nil })
                }
                .frame(maxWidth: .infinity).frame(height: 84)
            }
        }
        if let r = laneReadout {   // LANE READOUT (idea 18): the touched bar's value floats at the top
            Text(r).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .padding(.horizontal, 8).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 5).fill(accent))
                .offset(y: -4)
        }
        }
        }
    }

    // ---- small controls ----
    private func typeShort(_ t: ProcessorType) -> String { t == .passgate ? "PASSES" : t.rawValue }   // FULL name (user 2026-07-30 — no abbreviations); PASSGATE panel display name → PASSES (friendly labels, enum rawValue untouched)
    private func bind(_ v: Double, _ set: @escaping (Double) -> Void) -> Binding<Double> {
        Binding(get: { v }, set: set)
    }
    // THE FADER (§presentation idea 5 — fine mode): a custom slider that replaces the plain SwiftUI one. Horizontal drag =
    // coarse (absolute, tap-to-position like before); PULL THE FINGER AWAY from the bar (>44pt vertical) and it latches to
    // FINE ×10 — a relative scrub at a tenth the sensitivity, anchored where you crossed, so there's no jump. The pro-audio
    // "drag away to fine-tune" idiom; discoverable, one gesture, no timing. Drop-in for the old `Slider(value:in:).tint`.
    private func slider(_ b: Binding<Double>, in range: ClosedRange<Double>, detents: [Double] = []) -> some View {
        FineSlider(value: b.wrappedValue, range: range, accent: accent, set: { b.wrappedValue = $0 }, detents: detents)
    }
    /// THE SPAN LADDER dial (Paul 2026-08-22 §3): 1·2·3·4·6·8·×2·×4 — the pattern's loop period in columns (odd N =
    /// polymeter against the 8-column row). Replaces the CELL|ROW toggle; 1 = CELL, 8 = ROW (byte-identical endpoints).
    @ViewBuilder private func spanLadderField(_ current: Int, _ set: @escaping (Int) -> Void) -> some View {
        field("SPAN — the pattern's loop, in columns  (odd = polymeter)") {
            seg(spanLadderValues.map { spanLadderLabel($0) }, sel: spanLadderLabel(current)) { i in set(spanLadderValues[i]) }
        }
    }
    // SPAN with a FREE end (Paul 2026-08-27, the universal re-sync model): 0 = FREE (free-run, no re-anchor — the
    // pattern phases against the grid forever) · 1·2·3·4·6·8·×2·×4 = re-sync the pattern to phase 0 every N columns.
    // An odd pattern length against an aligning span = drift then snap back. RIFF is the first card to adopt it.
    @ViewBuilder private func spanLadderFreeField(_ current: Int, _ set: @escaping (Int) -> Void) -> some View {
        let vals = [0] + spanLadderValues
        field("SPAN — re-sync the stencil every N columns  (FREE = phase forever · odd = drift then resync)") {
            seg(vals.map { $0 == 0 ? "FREE" : spanLadderLabel($0) }, sel: current == 0 ? "FREE" : spanLadderLabel(current)) { i in set(vals[i]) }
        }
    }
    // RIFF §5 (Paul 2026-08-26): a per-step TOGGLE lane (ACCENT · TIE · SLIDE), aligned under the rank matrix (16pt rank
    // gutter + 30pt SET gutter). `on(step)` reads the lit state; `tap(step)` flips it.
    private func riffToggleLane(_ label: String, steps: Int, on: @escaping (Int) -> Bool, accent: Color, glyph: String, _ tap: @escaping (Int) -> Void) -> some View {
        field(label) {
            HStack(spacing: 2) {
                Color.clear.frame(width: 16, height: 14)
                ForEach(0..<steps, id: \.self) { s in
                    let isOn = on(s)
                    RoundedRectangle(cornerRadius: 3).fill(isOn ? accent.opacity(0.6) : Color.white.opacity(0.06)).frame(maxWidth: .infinity).frame(height: 15)
                        .overlay(isOn ? Text(glyph).font(.system(size: 8, weight: .heavy)).foregroundColor(.white.opacity(0.95)) : nil)
                        .contentShape(Rectangle()).onTapGesture { tap(s) }
                }
                Color.clear.frame(width: 30, height: 14)
            }
        }
    }
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
            content()
        }
    }
    // DEFAULTS RECEDE (§presentation idea 21): a field whose param is still at its DEFAULT dims; a deviation brightens —
    // so a card reads as "hero + what you changed". The default is one shared snapshot (`paramDefaults`, built once →
    // no per-render cost), compared to the field's own keypath. Non-annotated fields (heroes, multi-param) stay normal.
    static let paramDefaults = ColourParams()
    private func field<C: View, V: Equatable>(_ label: String, _ kp: KeyPath<ColourParams, V>, @ViewBuilder _ content: () -> C) -> some View {
        let atDefault = p[keyPath: kp] == ProcessorBox.paramDefaults[keyPath: kp]
        return VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(atDefault ? 0.32 : 0.72))
            content()
        }.opacity(atDefault ? 0.62 : 1)
    }
    // A BIPOLAR slider (§presentation idea 4/22): centred on 0; DOUBLE-TAP the label = reset to centre. `v`/`set` are in
    // the natural range; the track maps it to 0…1.
    private func bipolarSlider(_ label: String, _ v: Double, in range: ClosedRange<Double> = -1...1, _ set: @escaping (Double) -> Void) -> some View {
        let lo = range.lowerBound, hi = range.upperBound
        return VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                .contentShape(Rectangle()).onTapGesture(count: 2) { set(0) }   // double-tap → centre (0)
            slider(bind((v - lo) / (hi - lo)) { set(lo + $0 * (hi - lo)) }, in: 0...1)
        }
    }
    // TWO-COLUMN PAIRING (§presentation rule 6 / E): two compact ★★ fields share one row on the wide panel — halving the
    // vertical run. Heroes / matrices / lanes / the options cluster stay full-width; only short segs+numPairs+sliders pair.
    private func row2<A: View, B: View>(@ViewBuilder _ a: () -> A, @ViewBuilder _ b: () -> B) -> some View {
        HStack(alignment: .top, spacing: 14) {
            a().frame(maxWidth: .infinity, alignment: .leading)
            b().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    // THE HERO (§presentation rule 1): the card's ★★★ control — a 2pt accent bar on the left edge (the only control that
    // wears one) + breathing room. Everything else is a plain `field`. A hero opens the card and never shares a row.
    private func heroField<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
            content()
        }
        .padding(.leading, 10).padding(.vertical, 7)
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 2) }
    }
    // A SECTION LABEL (§presentation rule 4): a quiet header + hairline that groups a long card (ECHO → TIMING·TONE·TAIL,
    // MOD → source·TARGET) so below-the-fold stops being a mystery.
    private func sectionLabel(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35)).tracking(1.5)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }.padding(.top, 5)
    }
    // THE OPTIONS CLUSTER (§presentation rule 2): the card's ★ minor toggles gathered into ONE compact foot row — each a
    // lit/unlit chip (idea 11: ON/OFF collapses to one chip). No minor toggle ever eats a full row again.
    private func optionsCluster(_ chips: [(label: String, on: Bool, act: () -> Void)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("OPTIONS").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            HStack(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, c in
                    Text(c.label).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(c.on ? .black : .white.opacity(0.6)).lineLimit(1)
                        .padding(.horizontal, 12).frame(minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: 6).fill(c.on ? accent : Color.white.opacity(0.08)))
                        .contentShape(Rectangle()).onTapGesture(perform: c.act)
                }
                Spacer(minLength: 0)
            }
        }
    }
    // §1 STANDARD PANEL ANATOMY (Paul 2026-08-27): THE FRAME ROW — every pattern card ends with GRID · ROTATE · SPAN in
    // this FIXED ORDER under one "FRAME" label, so hands learn ONE location across every pattern card. The card passes its
    // own three controls (each already a labelled field); this fixes their order + place (the footer). Pure re-layout.
    // ═══════════ FRAME FOOTER — ALL THE STYLING KNOBS IN ONE PLACE (Paul 2026-08-28: tweak here) ═══════════
    // GRID (left) · ROTATE (centre) · SPAN (right) spread across the footer, each with its LABEL ABOVE a single row of
    // chips; every button is chipH tall. Change any number to retune the whole footer — bigger chipText/chipH = larger.
    private enum FS {
        static let chipText:   CGFloat = 13    // chip label size
        static let chipH:      CGFloat = 30    // chip / rotate-button height (all uniform)
        static let chipPadH:   CGFloat = 11    // chip left/right padding (→ chip width)
        static let chipRadius: CGFloat = 5
        static let chipGap:    CGFloat = 5     // gap between chips in the row (and ◀ n ▶)
        static let labelText:  CGFloat = 11    // the GRID/ROTATE/SPAN labels + the FRAME heading
        static let labelGap:   CGFloat = 5     // gap between a control's label and its chips
        static let groupGap:   CGFloat = 16    // MIN gap between the three controls (they spread left · centre · right)
    }
    @ViewBuilder private func frameRow<G: View, R: View, S: View>(@ViewBuilder grid: () -> G, @ViewBuilder rotate: () -> R, @ViewBuilder span: () -> S, pairs: ProcessorType? = nil) -> some View {
        // GRID left · ROTATE centre · SPAN right (Spacers spread them). No "FRAME" heading — just the rule (Paul 2026-08-28).
        // The "pairs well" line sits UNDER the rotate, in the centre column.
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                grid()
                Spacer(minLength: FS.groupGap)
                VStack(alignment: .leading, spacing: 6) {
                    rotate()
                    if let t = pairs, let s = Self.pairsWellText(t) {
                        Text("pairs well:  \(s)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.32))
                    }
                }
                Spacer(minLength: FS.groupGap)
                span()
            }
        }.padding(.top, 5)
    }
    // §1 ANATOMY — the COMPACT frame controls (Paul 2026-08-28): small chips in a tight row, ALL options visible (no popup,
    // no finger-sized seg). frameSeg = the small-chip selector; frameGrid/frameSpan wrap it with a narrow prefix; ROTATE
    // stays the ◀n▶ nudge. The midway between the old full-size fields and the dropdowns.
    // The rate/span chips wrap into TWO rows (Paul 2026-08-28) — narrower + taller, so all three controls line up at
    // one height (`frameCtlH`, matched to the ROTATE nudge). Row 1 holds the first ceil(n/2) chips, row 2 the rest.
    // A control = its LABEL above its chips. The label is ALWAYS left-aligned (Paul 2026-08-28) even though the control
    // groups sit left / centre / right in the row — so the VStack is always .leading; frameRow's Spacers do the spread.
    private func frameCtl<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: FS.labelGap) {
            Text(label).font(.system(size: FS.labelText, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            content()
        }
    }
    private func frameChip(_ text: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Text(text).font(.system(size: FS.chipText, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.5))
            .padding(.horizontal, FS.chipPadH).frame(height: FS.chipH)
            .background(RoundedRectangle(cornerRadius: FS.chipRadius).fill(on ? accent : Color.white.opacity(0.07)))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    private func chipRow<T: Hashable>(_ values: [T], _ label: @escaping (T) -> String, _ on: @escaping (T) -> Bool, _ tap: @escaping (T) -> Void) -> some View {
        HStack(spacing: FS.chipGap) { ForEach(values, id: \.self) { v in frameChip(label(v), on: on(v)) { tap(v) } } }
    }
    private func frameGrid(_ current: ArpRate, _ set: @escaping (ArpRate) -> Void) -> some View {
        let rates = ArpRate.allCases, top = (rates.count + 1) / 2   // GRID over two rows (Paul 2026-08-28): 3 + 3
        return frameCtl("GRID") {
            VStack(alignment: .leading, spacing: FS.chipGap) {
                chipRow(Array(rates[0..<top]), { $0.rawValue }, { $0 == current }, { set($0) })
                chipRow(Array(rates[top...]), { $0.rawValue }, { $0 == current }, { set($0) })
            }
        }
    }
    private func frameSpan(_ current: Int, free: Bool, _ set: @escaping (Int) -> Void) -> some View {
        let topVals = (free ? [0] : []) + [16, 32]   // Paul 2026-08-28: FREE · ×2 · ×4 on top …
        let botVals = [1, 2, 3, 4, 6, 8]             // … 1 · 2 · 3 · 4 · 6 · 8 below
        let lbl: (Int) -> String = { $0 == 0 ? "FREE" : spanLadderLabel($0) }
        return frameCtl("SPAN") {
            VStack(alignment: .leading, spacing: FS.chipGap) {
                chipRow(topVals, lbl, { $0 == current }, { set($0) })
                chipRow(botVals, lbl, { $0 == current }, { set($0) })
            }
        }
    }
    private func frameRotate(_ current: Int, _ range: ClosedRange<Int>, _ set: @escaping (Int) -> Void) -> some View {
        let lo = range.lowerBound, hi = range.upperBound, n = max(1, hi - lo + 1)   // wrap the ◀▶ nudge within [lo, hi]
        return frameCtl("ROTATE") {
            HStack(spacing: FS.chipGap) {
                frameChip("◀", on: false) { set(lo + ((current - lo - 1 + n) % n)) }
                Text("\(current)").font(.system(size: FS.chipText, weight: .heavy, design: .monospaced)).foregroundColor(accent).frame(minWidth: 18).frame(height: FS.chipH)
                frameChip("▶", on: false) { set(lo + ((current - lo + 1) % n)) }
            }
        }
    }
    // §1 ANATOMY — the "pairs well" line (footer item 3): one dim row from the pairing catalog (processor-pairings.md),
    // teaching at the moment of choice. → = a good DOWNSTREAM stage · ← = a good UPSTREAM stage. Rendered under ROTATE
    // inside frameRow; this returns the text (nil = no line).
    static func pairsWellText(_ ft: ProcessorType) -> String? {
        switch ft {
        case .ratchet: return "→ LENGTH · ← SPLIT"     // catalog §3: downstream LENGTH chokes/rings the rolls; upstream SPLIT rolls a register
        case .tutti:   return "→ ARP · ← HARMONIZE"     // catalog §2: downstream ARP comps the voicings; upstream HARMONIZE enriches the set
        case .euclid:  return "→ LENGTH · ← SPLIT"     // catalog §3: LENGTH gates the pulses; SPLIT euclids a register (kick-and-hat)
        case .burst:   return "→ LENGTH · ← SPLIT"     // catalog §3: LENGTH shapes the roll's ring; SPLIT rolls a register
        case .riff:    return "→ GLIDE · ← SPLIT"      // riff's SLIDE lane feeds a glide synth; SPLIT riffs a register (not in catalog — my call)
        default: return nil
        }
    }
    // MODE ROW (device round 2): an enum field is an ALWAYS-VISIBLE RADIO ROW — every option shown, the selected
    // one filled. No dropdown; nothing hidden. Wraps to a second line when the options don't fit one row.
    private func seg(_ options: [String], sel: String, _ onPick: @escaping (Int) -> Void) -> some View {
        // Chips size to their LABEL (finger-min 52pt), LEFT-aligned — so a 2-option toggle is ~140pt, not the full panel
        // width (Paul 2026-08-25: "controls feel too wide"). Font unchanged; the trailing Spacer stops the row stretching.
        let rows = radioRows(options.count)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, span in
                HStack(spacing: 6) {
                    ForEach(span, id: \.self) { i in
                        let on = options[i] == sel
                        Text(options[i]).font(.system(size: 15, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : accent).lineLimit(1)
                            .padding(.horizontal, 15).frame(minWidth: 52, minHeight: 42)
                            .background(RoundedRectangle(cornerRadius: 7).fill(on ? accent : Color.white.opacity(0.09)))
                            .contentShape(Rectangle()).onTapGesture { onPick(i) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    // SELF-DRAWING CHIPS (§presentation idea 8): a `seg` whose chips carry a small drawn GLYPH above the label — the
    // control shows its meaning (a waveform, an arrow) not just its name. Same content-sized, left-aligned chip grammar.
    private func iconSeg<G: View>(_ options: [String], sel: String, glyph: @escaping (Int, Color) -> G, _ onPick: @escaping (Int) -> Void) -> some View {
        let rows = radioRows(options.count)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, span in
                HStack(spacing: 6) {
                    ForEach(span, id: \.self) { i in
                        let on = options[i] == sel
                        VStack(spacing: 3) {
                            glyph(i, on ? .black : accent).frame(width: 24, height: 13)
                            Text(options[i]).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : accent).lineLimit(1)
                        }
                        .padding(.horizontal, 12).frame(minWidth: 52, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? accent : Color.white.opacity(0.09)))
                        .contentShape(Rectangle()).onTapGesture { onPick(i) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    // A small waveform drawn for the MOD WAVE chips (idea 8). Stroked in a 24×13 box.
    private func waveGlyph(_ s: ModShape, _ tint: Color) -> some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, mid = h / 2
            var p = Path()
            switch s {
            case .sine:
                p.move(to: CGPoint(x: 0, y: mid))
                var x: CGFloat = 0
                while x <= w { p.addLine(to: CGPoint(x: x, y: mid - CGFloat(sin(Double(x / w) * 2 * .pi)) * (mid - 1))); x += 1 }
            case .triangle:
                p.move(to: CGPoint(x: 0, y: h - 1)); p.addLine(to: CGPoint(x: w / 2, y: 1)); p.addLine(to: CGPoint(x: w, y: h - 1))
            case .square:
                p.move(to: CGPoint(x: 0, y: h - 1)); p.addLine(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: w / 2, y: 1))
                p.addLine(to: CGPoint(x: w / 2, y: h - 1)); p.addLine(to: CGPoint(x: w, y: h - 1)); p.addLine(to: CGPoint(x: w, y: 1))
            case .ramp:
                p.move(to: CGPoint(x: 0, y: h - 1)); p.addLine(to: CGPoint(x: w - 1, y: 1)); p.addLine(to: CGPoint(x: w - 1, y: h - 1))
            case .sampleHold:
                let n = 4
                for i in 0..<n {
                    let x0 = w * CGFloat(i) / CGFloat(n), x1 = w * CGFloat(i + 1) / CGFloat(n)
                    let y = h - 1 - (h - 2) * CGFloat([0, 2, 1, 3][i]) / 3
                    if i == 0 { p.move(to: CGPoint(x: x0, y: y)) } else { p.addLine(to: CGPoint(x: x0, y: y)) }
                    p.addLine(to: CGPoint(x: x1, y: y))
                }
            }
            ctx.stroke(p, with: .color(tint), lineWidth: 1.5)
        }
    }
    // ARP PATTERN chip arrows (idea 8): up · down · up-down · random · as-played.
    private func arpGlyph(_ i: Int, _ tint: Color) -> some View {
        let names = ["arrow.up", "arrow.down", "arrow.up.arrow.down", "shuffle", "hand.point.up.left"]
        return Image(systemName: i >= 0 && i < names.count ? names[i] : "arrow.up").font(.system(size: 11, weight: .heavy)).foregroundColor(tint)
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
    // THE NUDGE PAIR (Paul 2026-08-25 §presentation rule 3): ◀ value ▶ — the ONE numeric grammar. tap = ±1 · drag the
    // value = scrub. Replaces grid16, numeric-as-radio, CHANNEL's chip wall, AND is the ROTATE control. `wrap` cycles
    // (rotate/channel); `format` prints units/glyphs (e.g. "3/16", "WIRE").
    private func numPair(_ v: Int, _ range: ClosedRange<Int>, wrap: Bool = false,
                         format: @escaping (Int) -> String = { "\($0)" }, _ set: @escaping (Int) -> Void) -> some View {
        NumPair(value: v, range: range, wrap: wrap, format: format, accent: accent, set: set)
    }
}

/// The nudge-pair view (its own struct so the drag-scrub can hold gesture state). §presentation rule 3.
private struct NumPair: View {
    let value: Int
    let range: ClosedRange<Int>
    var wrap = false
    var format: (Int) -> String = { "\($0)" }
    let accent: Color
    let set: (Int) -> Void
    @State private var dragBase: Int? = nil
    @State private var showPicker = false      // ideas 12/31: tap the value → a grid/keypad overlay for exact entry
    @State private var padEntry = ""
    private func clampWrap(_ raw: Int) -> Int {
        if wrap { let n = max(1, range.count); return range.lowerBound + (((raw - range.lowerBound) % n) + n) % n }
        return min(range.upperBound, max(range.lowerBound, raw))
    }
    private func apply(_ raw: Int) { let x = clampWrap(raw); if x != value { set(x) } }
    private func arrow(_ glyph: String, _ act: @escaping () -> Void) -> some View {
        Text(glyph).font(.system(size: 17, weight: .heavy)).foregroundColor(.white.opacity(0.85))
            .frame(width: 44, height: 42).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
            .contentShape(Rectangle()).onTapGesture(perform: act)
    }
    var body: some View {
        HStack(spacing: 6) {
            arrow("◀") { apply(value - 1) }
            Text(format(value)).font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(accent)
                .lineLimit(1).padding(.horizontal, 10).frame(minWidth: 56, minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                .contentShape(Rectangle())
                .onTapGesture { padEntry = ""; showPicker = true }            // tap = the value overlay (ideas 12/31)
                .gesture(DragGesture(minimumDistance: 4).onChanged { g in     // drag = scrub (idea 2)
                    let base = dragBase ?? value; if dragBase == nil { dragBase = value }
                    apply(base + Int((g.translation.width / 14).rounded()))   // ~14pt per step
                }.onEnded { _ in dragBase = nil })
                .popover(isPresented: $showPicker, arrowEdge: .bottom) { picker }
            arrow("▶") { apply(value + 1) }
        }   // content-sized; the parent field (VStack .leading) left-aligns it
    }
    // THE VALUE OVERLAY (§presentation ideas 12 + 31): tap the number → pick it exactly. A GRID for small ranges (grid16
    // reborn as an on-demand overlay) · a KEYPAD for big ranges (CC 0–127) — the raw path, exact numeric entry.
    @ViewBuilder private var picker: some View {
        if range.count <= 24 {
            let vals = Array(range); let cols = min(8, max(1, vals.count))
            VStack(spacing: 6) {
                ForEach(0..<((vals.count + cols - 1) / cols), id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<cols, id: \.self) { c in
                            let idx = r * cols + c
                            if idx < vals.count {
                                let vv = vals[idx]
                                Text(format(vv)).font(.system(size: 13, weight: .heavy, design: .monospaced)).lineLimit(1)
                                    .foregroundColor(vv == value ? .black : .white).padding(.horizontal, 6)
                                    .frame(minWidth: 34, minHeight: 36).background(RoundedRectangle(cornerRadius: 6).fill(vv == value ? accent : Color.white.opacity(0.12)))
                                    .contentShape(Rectangle()).onTapGesture { apply(vv); showPicker = false }
                            }
                        }
                    }
                }
            }.padding(14).background(Color.black)
        } else {
            VStack(spacing: 8) {
                Text(padEntry.isEmpty ? "\(value)" : padEntry).font(.system(size: 24, weight: .heavy, design: .monospaced)).foregroundColor(accent).frame(minHeight: 32)
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "✓"]], id: \.self) { keys in
                    HStack(spacing: 8) {
                        ForEach(keys, id: \.self) { key in
                            Text(key).font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundColor(key == "✓" ? .black : .white)
                                .frame(width: 56, height: 46).background(RoundedRectangle(cornerRadius: 8).fill(key == "✓" ? accent : Color.white.opacity(0.1)))
                                .contentShape(Rectangle()).onTapGesture { padKey(key) }
                        }
                    }
                }
            }.padding(16).background(Color.black)
        }
    }
    private func padKey(_ k: String) {
        switch k {
        case "⌫": if !padEntry.isEmpty { padEntry.removeLast() }
        case "✓": if let n = Int(padEntry) { apply(n) }; padEntry = ""; showPicker = false
        default:  if padEntry.count < 4 { padEntry += k }
        }
    }
}

/// THE EUCLID BRUSH (SPEC-euclid-variations §5): an "ε" button that fills a matrix row / slider lane with a K-of-N
/// euclidean pattern (dial HITS, rotate). Euclid becomes an authoring tool across the whole widget language — euclidean
/// accents, mutes, hockets, odds. `apply(euclidPattern)` lets the host lane set its hit/rest cells. Its own struct (K/rot @State).
private struct EBrushButton: View {
    let steps: Int
    let accent: Color
    let apply: ([Bool]) -> Void
    @State private var open = false
    @State private var k = 4
    @State private var rot = 0
    private func fire() { apply(euclidPattern(pulses: max(0, Swift.min(steps, k)), steps: Swift.max(1, steps), rotation: ((rot % Swift.max(1, steps)) + steps) % Swift.max(1, steps))) }
    var body: some View {
        Text("ε").font(.system(size: 12, weight: .black, design: .monospaced)).foregroundColor(accent)
            .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(accent.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture { k = Swift.max(1, Swift.min(steps, k)); open = true }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("EUCLID FILL — K of \(steps)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    HStack(spacing: 8) { Text("HITS").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7)).frame(width: 52, alignment: .leading)
                        NumPair(value: k, range: 1...Swift.max(1, steps), accent: accent) { k = $0; fire() } }
                    HStack(spacing: 8) { Text("ROTATE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7)).frame(width: 52, alignment: .leading)
                        NumPair(value: rot, range: 0...Swift.max(0, steps - 1), wrap: true, accent: accent) { rot = $0; fire() } }
                    Button { fire(); open = false } label: {
                        Text("FILL").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                            .padding(.horizontal, 18).frame(height: 32).background(RoundedRectangle(cornerRadius: 6).fill(accent))
                    }.buttonStyle(.plain)
                }.padding(16).background(Color.black)
            }
    }
}

/// ROTATE by DIRECT MANIPULATION (FERRY-rotate-control §2, ratified): drag a matrix horizontally to rotate its pattern
/// (wrap at edges). A `simultaneousGesture` so cell TAPS still set (a tap isn't a drag); ~26px per step. The ◀ n ▶ pair
/// stays as the visible hint + the precise control. `onRotate` receives the incremental delta (±1) as the finger moves.
private struct RotateOnDrag: ViewModifier {
    let onRotate: (Int) -> Void
    @State private var applied = 0
    func body(content: Content) -> some View {
        content.simultaneousGesture(DragGesture(minimumDistance: 20).onChanged { g in
            let steps = Int((g.translation.width / 26).rounded())
            if steps != applied { onRotate(steps - applied); applied = steps }
        }.onEnded { _ in applied = 0 })
    }
}

/// THE FADER (§presentation idea 5 — fine mode; idea 3 — detents + haptics). Its own struct so the drag can hold
/// latch/anchor @State. Coarse = absolute (tap-to-position); pull away from the bar (>44pt vertical) → latches FINE ×10,
/// a relative scrub anchored where you crossed (no jump), for the rest of that drag. Releases back to coarse. Every
/// slider fires a soft SELECTION haptic as the value crosses a notch (a "notched" tactile feel); `detents` (musical
/// values, natural range) add GRAVITY — a nearby value SNAPS to the detent + a firmer bump. Render-only; no engine touch.
private struct FineSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let accent: Color
    let set: (Double) -> Void
    var detents: [Double] = []
    @State private var fine = false
    @State private var anchorX: CGFloat = 0
    @State private var anchorVal: Double = 0
    @State private var lastNotch: Int = .min          // last notch index we ticked at (haptic dedup)
    @State private var inDetent: Double? = nil         // detent we're currently snapped to (bump dedup)
    private static let selHaptic = UISelectionFeedbackGenerator()   // shared → no per-render alloc, stays prepared
    private static let bumpHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private var lo: Double { range.lowerBound }
    private var hi: Double { range.upperBound }
    private var span: Double { max(0.000001, hi - lo) }
    private var frac: CGFloat { CGFloat((value - lo) / span) }
    // 20 notches across the range (coarse) / 100 (fine) — consistent tactile density regardless of the range's units.
    private func tick(_ v: Double) {
        let notches = Double(fine ? 100 : 20)
        let idx = Int(((v - lo) / span * notches).rounded())
        if idx != lastNotch { lastNotch = idx; FineSlider.selHaptic.selectionChanged() }
    }
    // DETENT gravity: a raw value within 2% of the range of a detent snaps to it (a firmer bump on entry). Small enough
    // never to block a value one integer/step away (glideRange octaves, glideTime beats, mod attack/release beats).
    private func snap(_ v: Double) -> Double {
        guard !detents.isEmpty else { inDetent = nil; return v }
        let thr = span * 0.02
        if let d = detents.min(by: { abs($0 - v) < abs($1 - v) }), abs(d - v) < thr {
            if inDetent != d { inDetent = d; FineSlider.bumpHaptic.impactOccurred(intensity: 0.7) }
            return d
        }
        inDetent = nil; return v
    }
    private func commit(_ raw: Double) { let v = snap(min(hi, max(lo, raw))); tick(v); set(v) }
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let d: CGFloat = fine ? 22 : 16          // thumb diameter (grows in fine mode)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 5)
                Capsule().fill(accent.opacity(0.85)).frame(width: max(5, frac * w), height: 5)
                // detent pips on the track (a faint tick where each snap value sits)
                ForEach(detents.indices, id: \.self) { i in
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 3, height: 3)
                        .offset(x: min(w - 3, max(0, CGFloat((detents[i] - lo) / span) * w - 1.5)))
                }
                Circle().fill(.white).frame(width: d, height: d)
                    .overlay(Circle().stroke(accent, lineWidth: fine ? 3 : 0))
                    .offset(x: min(w - d, max(0, frac * w - d / 2)))
            }
            .frame(height: 30, alignment: .center)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if fine {
                    Text("FINE ×10").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(accent).offset(y: -13)
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !fine && abs(g.translation.height) > 44 {   // pull away → latch fine for the rest of the drag
                        fine = true; anchorX = g.location.x; anchorVal = value
                    }
                    if fine {
                        let delta = Double((g.location.x - anchorX) / max(1, w)) * span * 0.1
                        commit(anchorVal + delta)
                    } else {
                        let f = min(1, max(0, g.location.x / max(1, w)))
                        commit(lo + Double(f) * span)              // coarse = absolute position
                    }
                }
                .onEnded { _ in fine = false; inDetent = nil })
        }
        .frame(height: 30)
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


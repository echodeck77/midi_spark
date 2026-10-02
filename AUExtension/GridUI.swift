//  GridUI.swift
//  MidiSpark — the 8×8 grid view (four-row cell) + palette + RECEIVERS/OUTPUTS panels + the CELL EDITOR.
//  Editing (delta §5 rev 2): in EDIT the whole pad is ONE tap target that opens the floating CELL EDITOR
//  (input · machine · emitters · actions); body long-press auditions (stopped); PERFORM tap flips ALT. The
//  old FROM/OUT popovers + tap-paint + hold-menu are retired (folded into the editor). Every edit goes
//  through MidiSparkAudioUnit.editScene/editDocument → scheduleRebuild. Tokens per docs/ui-port-guide.md.

import SwiftUI
import UIKit   // for UIColor (the old multi-touch ColumnHoldOverlay UIView that needed this is gone)

// A PROPER piano keyboard in a Canvas (Paul 2026-08-31 — the flat all-full-height stripes read as illegible bars, not a
// piano). White keys (C D E F G A B) fill the full height side-by-side; black keys (the 5 sharps) are narrower + ~62%
// height, drawn ON TOP straddling the gap after their lower white neighbour. `tint(midi)` fills a lit key (nil = the base
// key machine); `mark(midi)` (optional) draws a bright "being played" band at the key's base. Draws MIDI range [lo, hi).
// Shared by the AVOID pianos and the processor-header IN silhouette.
func pianoKeysCanvas(lo: Int, hi: Int, tint: @escaping (Int) -> Color?, mark: ((Int) -> Bool)? = nil) -> some View {
    Canvas { ctx, size in
        let whitePCs: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
        let whites = (lo..<hi).filter { whitePCs.contains(((($0 % 12) + 12) % 12)) }
        let nw = max(1, whites.count)
        let ww = size.width / CGFloat(nw)
        let h = size.height
        var xOf = [Int: Int]()                                             // white-key MIDI → its column index
        for (i, m) in whites.enumerated() { xOf[m] = i }
        for (i, m) in whites.enumerated() {                                // white keys, full height
            let rect = CGRect(x: CGFloat(i) * ww, y: 0, width: max(1, ww - 0.7), height: h)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.white.opacity(0.16)))
            if let c = tint(m) { ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(c)) }
            if mark?(m) == true {                                          // "being played" — a bright band at the key's base
                let b = CGRect(x: CGFloat(i) * ww, y: h * 0.7, width: max(1, ww - 0.7), height: h * 0.3)
                ctx.fill(Path(roundedRect: b, cornerRadius: 1.5), with: .color(.white.opacity(0.95)))
            }
        }
        let bw = ww * 0.62, bh = h * 0.62                                   // black keys, narrower + shorter, on top
        for m in lo..<hi {
            let pc = (((m % 12) + 12) % 12)
            guard !whitePCs.contains(pc), let wi = xOf[m - 1] else { continue }
            let rect = CGRect(x: CGFloat(wi + 1) * ww - bw / 2, y: 0, width: bw, height: bh)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Color(white: 0.07)))
            if let c = tint(m) { ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(c)) }
            if mark?(m) == true {                                          // played band on a black key (near its base)
                let b = CGRect(x: CGFloat(wi + 1) * ww - bw / 2, y: bh * 0.62, width: bw, height: bh * 0.38)
                ctx.fill(Path(roundedRect: b, cornerRadius: 1.5), with: .color(.white.opacity(0.95)))
            }
        }
    }
}

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
    /// 0xRRGGBB → Color. Used for the 16 canonical Machine hexes (do not "harmonise" them, §ui-guide).
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


/// Canonical Machine hexes, in machineIDs / bank order (docs/ui-port-guide.md). Index = machine index.
let machineHexes: [UInt32] = [
    0xFFC53D, 0xFF7A1A, 0xFF4B33, 0xC2244B, 0xFF4D9E, 0xFFA8B8, 0xB44DFF, 0x7A3DF0,
    0x5566FF, 0x38A6FF, 0x25E0F0, 0x148F80, 0x7BF2CE, 0x2ECC5E, 0xC6F23D, 0x4C6E8F,   // [15] SLATE (was BRONZE 0xC9A227 — too close to GOLD, user 2026-08-09)
]
// THE PLAY GRID's own palette (Paul 2026-08-30): a muted "DUSK" family, so the play grid is differentiable from the VIVID
// part grid at a glance (each grid owns its own section of machine). Earthy, mid-brightness, low-saturation — a quieter world
// beside the loud part rainbow, and calm enough that the vivid emitter drift-notes still pop on top.
// EVEN DUSK (Paul 2026-09-01): the muted "dusk" family collapsed together (8 hues at one lightness). Replaced with 8 hues
// spread EVENLY round the wheel — rust · amber · olive · jade · teal · steel · violet · orchid — so each column reads as its
// own machine while staying muted enough that the vivid emitter drift still pops on top.
let playHexes: [UInt32] = [0xBE6E5A, 0xC0925A, 0x9BA25E, 0x5FA37E, 0x4F9AA6, 0x5E80B8, 0x8A6EBE, 0xBC6AA0]

// THE PART GRID's FIXED ROW palette (Paul 2026-09-05, design-cell-language.md): 8 distinct, good-looking hues, ONE per row
// POSITION — a row's identity, independent of its machine. Part cells are drawn DARK + FLAT from these; the bright emitter
// notes ride on top. The part/emitter separation is by LIGHTNESS (dark ground · bright marks), not hue.
let partRowHexes: [UInt32] = [0xFF5A4D, 0xFF9E33, 0xFFD23D, 0x6FCF5B, 0x35C7C0, 0x4A90E2, 0xA97BE0, 0xFF7BB0]
// Linear RGB mix of two packed hexes (t: 0→a … 1→b).
func mixHex(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    let ar = Double((a >> 16) & 255), ag = Double((a >> 8) & 255), ab = Double(a & 255)
    let br = Double((b >> 16) & 255), bg = Double((b >> 8) & 255), bb = Double(b & 255)
    let r = UInt32(max(0, min(255, ar + (br - ar) * t))), g = UInt32(max(0, min(255, ag + (bg - ag) * t))), bl = UInt32(max(0, min(255, ab + (bb - ab) * t)))
    return (r << 16) | (g << 8) | bl
}

// ── THE FERRY-SHADE PALETTE (Paul 2026-09-08, PLAN-grid-rebuild) ────────────────────────────────────────────────────
// Eight jewel-toned base hues, ONE per play ferry — the obvious, referenceable identity a part carries (the ferry, its
// part rows, and the machine-box header echo all wear it). A part's four rows are DARKENING shades of its ferry's base
// (base at row 0 → progressively darker), so one hue reads as one family and the base stays vivid at the top. This is the
// grid's colour system going forward — it supersedes the by-position partRowHexes + the dusk playHexes on the grid.
let ferryHexes: [UInt32] = [0xD9524B, 0xD98A3A, 0xD4B23F, 0x54A85C, 0x2FA6A0, 0x4A7FCC, 0x8E68C8, 0xD46A9C]
func ferryBaseHex(_ ferry: Int) -> UInt32 { ferryHexes[((ferry % ferryHexes.count) + ferryHexes.count) % ferryHexes.count] }
/// A part ROW's colour = its ferry's base darkened by the row index (0 = base · 1…3 progressively darker). Four
/// differentiable shades of one hue (Paul 2026-09-08: DARKEN only). `row` clamps to 0…3.
func ferryShadeHex(_ base: UInt32, _ row: Int) -> UInt32 { mixHex(base, 0x000000, [0.0, 0.20, 0.38, 0.55][max(0, min(3, row))]) }

// THE RECEIVER SIGNATURE GREYS (Paul 2026-08-30): the four MIDI-IN receivers A→D are now 4 shades of grey, LIGHT→DARK — their
// identity machine going forward (the OMNI/ENABLE button on the receiver strip + the MIDI-IN toggle chips). Kept light enough
// for black labels. (Distinct from the vivid emitter signature machines + the machine hues.)
let receiverGreys: [Color] = [Color(hex: 0xC8D2DC), Color(hex: 0xA6B2BF), Color(hex: 0x808E9C), Color(hex: 0x5E6C7A)]   // Tide & Ember: cool-tinted greys (IN recedes cool)
func receiverGrey(_ i: Int) -> Color { receiverGreys[max(0, min(3, i))] }

// THE I/O CHIP CORE VISUAL (Paul 2026-09-29: "I want the styling... to be the same as on the main toggles") — a free
// function, not a DiagView method, so ProcessorBox (a separate View type that can't call DiagView's own instance
// methods) can render a door-reference chip that looks IDENTICAL to the main MIDI-IN/MIDI-OUT toggles. Deliberately a
// smaller, separate sibling of DiagView's own buildIOSelectChip (BuildPage.swift), not a shared extraction: that
// function also carries the chase-index "invite" animation and the long-press "apply to every row" gesture, both
// DiagView-only concepts (its own @State) that don't apply to a per-PROCESSOR door reference (ECHO/CHORDS/AVOID
// aren't rows) — pulling them apart risked changing gesture behaviour on the two already-shipped, heavily-used
// toggles for no real benefit here. Keep the two visually in sync by hand if the shared look ever changes.
@ViewBuilder func ioChip(_ letter: String, on: Bool, accent: Color? = nil, action: @escaping () -> Void) -> some View {
    // 11pt, not 15 (Paul 2026-09-29): matches buildIOSelectChip's own receiver-chip textSize — kept in sync by hand per
    // this function's own doc comment above, since this chip exists solely to show the SAME note-name/key/"no input"
    // readout on ECHO/CHORDS/AVOID's door pickers.
    Text(letter).font(.system(size: 11, weight: .black, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.4)
        .foregroundColor(on ? Color.black : buildDim)
        .frame(maxWidth: .infinity).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? (accent ?? buildCyan) : buildCell))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.clear : buildEdge, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
}
// Lowercase pitch-class-only readout of a set of held notes, e.g. "c e g" — no octave digit (Paul 2026-09-29:
// "lowercase without the octave number"). nil when empty (the caller shows "no input" instead). Shared by every
// door-reference picker that wants the main toggles' own live-note/no-input labeling.
func noteClassLabel(_ notes: [Int]) -> String? {
    let names = ["c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"]
    guard !notes.isEmpty else { return nil }
    return notes.sorted().map { names[(($0 % 12) + 12) % 12] }.joined(separator: " ")
}

// delta §9 item 11: the four receivers' fixed "infrastructure family" hues (muted), shared by the
// RECEIVERS panel and the cells' band-as-deviation marker.
let receiverHues: [Color] = [Color(hex: 0x4E8FA8), Color(hex: 0x4E79A8), Color(hex: 0x55A79C), Color(hex: 0x6E8CA8)]   // Tide & Ember: IN = COOL (incoming water)

// EMITTER SIGNATURE MACHINES (Paul 2026-08-30): four VIVID, high-contrast hues for A/B/C/D — the ROUTING channel. They
// carry the DRIFTING piano-roll notes (and the MIDI-OUT toggles/dots). Kept the loudest machines in the app so the eye
// reads "vivid + moving = emitter" vs "calm frame = machine" — two machine languages that never fight on one small cell.
let emitterHexes: [UInt32] = [0xF0463C, 0xFF8C1A, 0xF5C518, 0xF0479E]   // Tide & Ember: OUT = WARM (energy leaving) — A red · B orange · C gold · D magenta
func emitterHue(_ bus: Bus) -> Color {
    let i = Bus.allCases.firstIndex(of: bus) ?? 0
    return Color(hex: i < emitterHexes.count ? emitterHexes[i] : 0x808080)
}
// The representative emitter machine for a cell's output SET — the LOWEST enabled bus (A<B<C<D); the drift's machine.
func emitterHue(_ buses: Set<Bus>) -> Color {
    for b in Bus.allCases where buses.contains(b) { return emitterHue(b) }
    return emitterHue(.a)
}


// BUILD's STAGE-THE-GRID variations are REAL machine IDs given a custom hue near their source (a new, distinguishable
// machine — not a shade drawn over the source). Session-scoped, like the rest of the BUILD workspace. (Paul 2026-08-15)
var machineHueOverride: [String: UInt32] = [:]
func machineHue(_ id: String) -> Color? {
    if let hex = machineHueOverride[id] { return Color(hex: hex) }
    return machineIDs.firstIndex(of: id).map { Color(hex: machineHexes[$0]) }
}

// A grid cell coordinate — extracted to top level (was GridView.GridPos) when the dead perform-grid GridView was
// removed (2026-09-01); still used by EditSelection + the machine-scope helpers. (Paul 2026-09-01)
struct GridPos: Hashable { let col: Int; let row: Int }


private struct FixedHeightIf: ViewModifier {
    let height: CGFloat?
    func body(content: Content) -> some View {
        if let h = height { content.frame(height: h, alignment: .top).clipped() } else { content }
    }
}

/// EUCLID DRAG HUD (Paul 2026-10-02 relocation): what's live while dragging a lane's comet bar — reported UP to
/// whoever hosts `ProcessorBox`, since the HUD itself must render OUTSIDE this box's own (possibly scrolling)
/// container to float truly "above the touch," not fixed to the scrolling processor-edit page. `point` is in
/// WINDOW coordinates (UIKit's `location(in: view.window)`) — the host converts it into its own local space.
struct EuclidDragHUDInfo {
    let label: String    // "LANE 1"…"LANE 4" or "ALL LANES" (2-finger)
    let hits: Int
    let steps: Int
    let offset: Int
    let point: CGPoint
}

struct ProcessorBox: View {
    enum Face { case a, b }
    let machine: Machine
    let machineIndex: Int
    var face: Face = .a
    let onEdit: (@escaping (inout Machine) -> Void) -> Void
    let onTranspose: (Int) -> Void                      // A face: transpose is an AUParameter
    let onMorph: (Double) -> Void
    var onSetTypeA: ((ProcessorType) -> Void)? = nil    // A face: switchType via the AU (per-type stash)
    var canPaste: Bool = false                          // clipboard non-empty ⇒ show PASTE
    var onCopy: () -> Void = {}
    var onPaste: () -> Void = {}
    var height: CGFloat = panelHeight                   // portrait A-above-B stacking passes a shorter height
    var mixed: Bool = false                             // MIXED-SET law: SELECT spans >1 Machine → dim + disable
    // CELL MACHINE (feat/EditPageSpike): when slotMode, this box edits ONE chain slot on a cell (not a Machine
    // face) — the title carries a BYPASS chip (and REMOVE) instead of COPY/PASTE, and transpose/morph are hidden
    // (those stay Machine-level). Bound via a synthetic Machine whose A face == the slot's type+params.
    var slotMode: Bool = false
    var slotBypassed: Bool = false
    var swapDirection: Int = 1                            // the chain-box swap's slide+fade direction (Paul 2026-09-29): +1 slides the incoming controls in from the trailing edge (moved rightward in the chain), -1 from the leading edge; callers with no positional concept (e.g. the chord-sequencer popup) keep the +1 default.
    var accentOverride: Color? = nil                     // MODE ROW: force the control accent (blue, to match the emitters)
    var liveStep: Int = -1                               // PLAYHEAD (idea 15): the live GRID COLUMN (0…7) lit in the matrices/lanes; -1 = stopped
    // RATCHET PATTERN own-clock playhead (Paul 2026-09-07): the matrix highlight must sweep at the ratchet's OWN rate,
    // which is faster than the ~4 Hz diag poll — so we EXTRAPOLATE the beat in a TimelineView (the app's pattern), never
    // sample the polled beat (that aliases below Nyquist → a 1↔5 jump at 1/8). Anchor+tempo come from `meters`; playing gates it.
    var beatAnchor: Double = 0
    var beatAnchorAt: Date = .distantPast
    var tempo: Double = 120
    var clockPlaying: Bool = false
    var driverNoteRate: Double = 0                       // RATCHET PATTERN NOTE clock: the upstream driver's note rate in beats (0 = unknown/standalone → the playhead can't sweep per-note)
    // SEQUENTIAL SOURCES (Paul 2026-10-02): the type of the immediately-preceding, NON-BYPASSED chain slot, only
    // when this box is editing EUCLID — nil otherwise (no predecessor, predecessor bypassed, or not EUCLID). Lets
    // euclidSettingsPanel show a RIFF/ARP note-select chip only when that source is genuinely readable, mirroring
    // driverNoteRate's own "a neighbor slot's value threaded in for the editor" shape above, with the one
    // correction this needs that driverNoteRate's own backward scan doesn't: bypass-aware (see BuildPage.swift).
    var precedingSourceType: ProcessorType? = nil
    var riffDrunkPosLive: Int = -1                       // RIFF DRUNK's true walk position, polled from the render thread (−1 = unknown/not this mode/cell) — Paul 2026-09-28
    var gridStepBeats: Double = 0.25                     // the SCENE step in beats → the DEFAULT (grid-column) matrix/lane playhead clock (Paul 2026-09-11)
    // A self-clock for a state matrix's playhead — extrapolated per frame so it can sweep faster than the diag poll.
    // `span` = the loop period in BEATS (0 = free-run over all STEPS); the playhead re-anchors every `span`.
    struct StateMatrixClock { let anchor: Double; let anchorAt: Date; let tempo: Double; let rate: Double; let steps: Int; let rotate: Int; let span: Double }
    var onBypass: () -> Void = {}
    var onRemove: (() -> Void)? = nil                   // nil = not removable (the head slot)
    var onMacro: (() -> Void)? = nil                    // slotMode: the MACRO button → the authoring flow (spec macro-authoring)
    var plainTitle: Bool = false                        // pop-up: show the type as a plain TITLE (no type-picker button)
    var showSlotChrome: Bool = true                     // slotMode: draw the built-in title row (name + BYPASS/✕ pills). BUILD hides it and supplies its own large Delete/Bypass header.
    var embedInParent: Bool = false                     // slotMode: the controls sit DIRECTLY in the parent card — drop this box's own panel background + outer padding (no box-within-a-box). Paul 2026-09-13.
    var processing: Bool = true                          // PLAY-STATE GREY (Paul 2026-09-14): false ⇒ this machine's active cell isn't sounding right now → the controls DIM (still fully usable, no disable). Default true = no greying (unaffected call sites).
    var avoidInputNotes: [[Int]] = [[], [], [], []]     // AVOID editor: per-input held PITCHES (recvHeldNotes; armed/scale doors report their pool) — feeds both illustration pianos
    var avoidChainInputDoor: Int = -1                   // AVOID editor: the door feeding THIS chain (its receiver) — the notes the filter acts on; -1 = unknown
    var doorKeyLabels: [String?] = [nil, nil, nil, nil] // per-door SCALE key label (Receiver.scaleLabel), else nil — every door-reference picker (ECHO's FROM, CHORDS' SCALE FROM, AVOID's WHICH INPUT) shows this over live notes over "no input", matching the main MIDI-IN toggles (Paul 2026-09-29)
    // EUCLID DRAG HUD (Paul 2026-10-02): reports live steps/hits/offset + the touch's WINDOW-space location while
    // dragging a comet bar. Default no-op — only the real chain-slot editor (BuildPage's `buildSlotBox`, the one
    // place EUCLID is actually edited) wires this; the tab-strip/chord-sequencer-popup call sites never show
    // EUCLID's own editor and don't need it. The HOST renders the actual HUD OUTSIDE its own scrolling container
    // (this box can't escape its own embedding ScrollView from in here) — see `buildProcessorPanel`.
    var onEuclidDragInfo: (EuclidDragHUDInfo?) -> Void = { _ in }
    @State private var showTypePicker = false           // B1: the title-as-picker popover
    @State private var lfoEditTarget: String? = nil      // PER-PARAM LFO (Docs/PLAN-param-lfo.md): which param's ∿ LFO editor popover is open
    @State private var weaveBrush: StepRate = .r1_8      // WEAVE DRAWN: the rate loaded on the brush
    @State private var laneReadout: String? = nil        // LANE READOUT (idea 18): the value floating while a lane bar is dragged
    @State private var togglePaintTarget: Bool? = nil    // toggleLane drag-paint (Paul 2026-09-07): the state set by the first cell touched, painted across the drag
    /// STAGE 4 (Paul 2026-10-01, PLAY/SELECT + settings-panel redesign): which of the 4 lanes the side panel is
    /// currently showing. Non-optional, defaulting to 0 — "a selector is ALWAYS selected" (mirrors
    /// `buildActiveFerry`'s own documented rationale) — persistent UI state, unlike a drag-only signal.
    @State private var euclidSelectedLane: Int = 0

    static let panelHeight: CGFloat = 300               // fixed — sized for the largest field set + morph

    private var isB: Bool { face == .b }
    // DEFAULT grid-column clock (0…7 over one bar) for the matrices/lanes that DON'T carry a bespoke clock
    // (Paul 2026-09-11): these used to light the live column from the ~4 Hz polled `d.effColumn`, folded into the whole-page
    // @State — which re-rendered the entire page every step and hitched every playhead. Self-animating from the free-running
    // beat anchor (the RATCHET matrix's pattern) frees the page from the per-step re-render. span 0 = free-run over all STEPS.
    private var gridClock: StateMatrixClock? {
        clockPlaying ? StateMatrixClock(anchor: beatAnchor, anchorAt: beatAnchorAt, tempo: tempo,
                                        rate: Swift.max(0.0001, gridStepBeats), steps: 8, rotate: 0, span: 0) : nil
    }
    private var accent: Color { accentOverride ?? (machineHue(machine.machineID) ?? .gray) }
    private var faceType: ProcessorType? { isB ? machine.typeB : machine.type }   // B may be nil = B-less
    private var p: MachineParams { isB ? machine.paramsB : machine.paramsA }
    private var faceTranspose: Int { isB ? machine.transposeBResolved : machine.transpose }
    private var glides: Bool { machine.typeB == machine.type }   // FULL morph ⇔ B is the same type as A
    private func setParam(_ f: @escaping (inout MachineParams) -> Void) {
        onEdit { c in if isB { f(&c.paramsB) } else { f(&c.paramsA) } }
    }
    // CRASH FIX (2026-08-27): each typeParams case is wrapped in AnyView(VStack(spacing: rowSpacing){…}) so the
    // switch's opaque type collapses to a shallow _ConditionalContent chain of AnyView (was a 28-deep nest of giant
    // TupleViews whose concrete-metadata instantiation overflowed the demangler stack → SIGSEGV when the editor
    // first rendered — e.g. adding an ARP). rowSpacing MATCHES the body VStack's spacing so layout is unchanged.
    private var rowSpacing: CGFloat { slotMode ? 14 : 6 }
    // PROCESSOR SWAP — slide + fade (Paul 2026-09-29, replaces the plain opacity cross-fade): the incoming controls
    // nudge in from whichever edge matches swapDirection (the direction the user actually moved through the chain),
    // fading in together; the outgoing controls nudge out the opposite way. A small FIXED offset, not SwiftUI's
    // built-in .move(edge:) (which travels the view's own full width — too big a sweep at panel size for a subtle
    // swap cue). Chosen over a bare cross-fade after comparing candidates with Paul against a mockup — gives the
    // swap real spatial continuity with the tap instead of just dissolving in place.
    private var swapTransition: AnyTransition {
        let d: CGFloat = swapDirection >= 0 ? 14 : -14
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: d)),
                            removal: .opacity.combined(with: .offset(x: -d)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: slotMode ? 14 : 6) {
            if !slotMode || showSlotChrome { titleRow }   // BUILD supplies its own header → hide the built-in title row
            if mixed {
                mixedFace                                // MIXED-SET: no honest Machine-level edit for a multi-Machine set
            } else {
                if let ft = faceType {
                    if !slotMode {                       // CELL MACHINE: transpose/morph stay Machine-level, hidden per-slot
                        field("TRANSPOSE \(faceTranspose > 0 ? "+" : "")\(faceTranspose)") {
                            stepper(faceTranspose, -24, 24) { v in
                                if isB { onEdit { $0.transposeB = v } } else { onTranspose(v) }
                            }
                        }
                    }
                    typeParams(ft)
                        .id(ft)                                    // a type change is a fresh identity, not an in-place diff — lets the transition below actually fire
                        .transition(swapTransition)                // SLIDE + FADE on swap (Paul 2026-09-29, was a plain cross-fade) — catches the moment the controls change, directionally
                        .animation(.easeInOut(duration: 0.2), value: ft)
                    if !slotMode && isB && glides {      // morph glides A↔B; only meaningful for a FULL B
                        field("MORPH \(Int(machine.morph * 100))%  → B") {
                            slider(Binding(get: { machine.morph }, set: { onMorph($0) }), in: 0...1)
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
        // Machine-desk face keeps its FIXED frame (static-frames rule).
        .padding(embedInParent ? 0 : (slotMode ? 14 : 8))   // embedInParent: no inner box → no self-padding (the parent card pads); Paul 2026-09-13
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FixedHeightIf(height: slotMode ? nil : height))
        .opacity(slotBypassed ? 0.45 : (mixed ? 0.55 : (processing ? 1 : 0.68)))   // bypassed/MIXED dim; PLAY-STATE GREY dims when NOT processing — 0.4→0.68, was too dim (Paul 2026-09-16)
        .animation(.easeInOut(duration: 0.18), value: processing)   // smooth grey↔bright as the machine starts/stops sounding
        .disabled(mixed)                                  // MIXED blocks hits (controls aren't rendered); the play-state grey stays USABLE (not disabled)
        .background {   // embedInParent drops the box-within-a-box; controls sit in the parent card. Paul 2026-09-13
            if !embedInParent { RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)) }
        }
    }

    // MIXED-SET law: the selection spans more than one Machine, so there is no single Machine-level edit to
    // honour — say so plainly rather than editing the brush behind the user's back. Cell-level edits
    // (routing, emitters, delete) still act on the whole set; only this panel goes inert.
    private var mixedFace: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MIXED").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            Text("selection spans multiple Machines — select ONE Machine to edit its processor.")
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
        case .empty:     return "an empty chain slot"
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
        case .velocity:  return "set each note's velocity from a per-step lane (or pass it through)"
        case .dest:      return "route each step, on its own clock, to a chosen emitter — or none (hocket)"
        case .deal:      return "deal notes across two emitters by count"
        case .recorder:  return "record N steps/passes of the chain, then loop it back"
        case .clock:     return "retimes everything after it in the chain — a hand-drawn per-step speed grid, with glide"
        case .killStep:  return "switch steps off — everything after it jumps past them and repeats what's left"
        case .muteMatrix: return "mute chosen emitters per step (part-gating)"
        case .riff:      return "an authored line that follows the held chord (a stencil of ranks)"
        case .tap:       return "send a copy out here + pass it on (layered parallel outputs)"
        case .hocket:    return "play your notes in another synth's gaps — or trade hits with it (listen to a wire)"
        case .avoid:     return "remove or move notes that clash with a reference — or lock them to a key"
        case .chords:    return "turn a held note into a diatonic chord progression, in key"
        case .euclidMask: return "gate a driven rhythm through a K-of-N euclidean pattern — rest, tie, or chord the gaps"
        }
    }

    private func pill(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(accent)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.2)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    // EUCLID REDESIGN (Paul 2026-09-30, Stage 2 — the UI half of the fixed-4-row plan; Stage 1's model/engine
    // landed on `main` first). ALWAYS operates on exactly 4 rows via the shared `euclidLinesForEditing()`
    // (Models.swift, the SAME helper SnapshotBuilder's resolve calls) — editing any of the 4 always-visible rows
    // "promotes" the machine from the old flat/short representation to a real 4-line array on first touch,
    // mirroring the pre-redesign "+ ADD LINE" seed-on-tap idiom, just automatic instead of button-triggered. The
    // old `euclidLineEdit` (which no-op'd past whatever `euclidLines` happened to currently hold) had no other
    // caller once the fixed-4-row editor replaced the old dynamic "+ ADD LINE" stack — removed, not kept dead.
    private func euclidLineEdit4(_ idx: Int, _ f: @escaping (inout EuclidLine) -> Void) {
        setParam { var a = $0.euclidLinesForEditing(); guard idx < a.count else { return }; f(&a[idx]); $0.euclidLines = a }
    }
    /// Two-finger gesture target (Paul 2026-10-01): the SAME edit as `euclidLineEdit4`, applied to ALL 4 rows at
    /// once — each row clamps independently against its OWN steps/pulses, so a shared delta can't push one row's
    /// value somewhere another row's range wouldn't allow.
    private func euclidAllRowsEdit(_ f: @escaping (inout EuclidLine) -> Void) {
        setParam { var a = $0.euclidLinesForEditing(); for i in a.indices { f(&a[i]) }; $0.euclidLines = a }
    }
    /// The merged NOTE SELECT chip row — one of the two rows (ALL·N1…N8, or the aggregate strategies), sliced from
    /// `EuclidNoteSel.allCases`'s own declared order (Models.swift) rather than a second, separately-maintained list.
    // TRIMMED (Paul 2026-10-01: "only display 1, 2, 3, 4 and top") — was all 15 EuclidNoteSel cases over two chip
    // rows; now just the 5 Paul actually wants surfaced. The full enum (ALL/N5…N8/LOW/BOT2/TOP2/CYCLE/RANDOM) is
    // UNTOUCHED underneath — an old doc already using one of those still resolves and plays correctly, it just
    // won't highlight any of these 5 chips (an honest "none of these" rather than a wrong guess).
    private let euclidNoteSelShown: [EuclidNoteSel] = [.n1, .n2, .n3, .n4, .high]
    private func euclidNoteSelLabel(_ s: EuclidNoteSel) -> String {
        switch s {
        case .n1: return "1"; case .n2: return "2"; case .n3: return "3"; case .n4: return "4"
        case .high: return "TOP"   // Paul's own word — reuses the existing HIGH case (the top held note), just relabelled here
        default: return s.rawValue
        }
    }
    // `.low` picks the exact same pool rank as `.n1` (both strikeChord index 0 — confirmed by reading arpPick's
    // sibling euclidRow fold) — so a row still carrying the pre-trim default (`.low`, from the EUCLID storefront
    // card) highlights "1" here rather than reading as nothing-selected, with zero change in what's actually heard.
    @ViewBuilder private func euclidNoteSelChipRow(_ opts: [EuclidNoteSel], _ cur: EuclidNoteSel, _ set: @escaping (EuclidNoteSel) -> Void) -> some View {
        HStack(spacing: 5) {
            ForEach(opts, id: \.self) { s in
                let on = s == cur || (s == .n1 && cur == .low)
                Text(euclidNoteSelLabel(s))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.55))
                    .fixedSize(horizontal: true, vertical: false)   // LAYOUT FIX 2026-10-01: never ellipsize "TOP" under compression — hold its own natural width
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(on ? accent : Color.white.opacity(0.08)))
                    .contentShape(Rectangle())
                    .onTapGesture { set(s) }
            }
        }
    }
    /// THE COMET BAR (Paul 2026-09-30, box redesign 2026-10-02): a non-interactive, live K-of-N hit display — N
    /// gap-separated rounded-rect BOXES (one per step, "easier to see the number of steps" than a dot on a bare
    /// line) with a glowing comet running the pattern continuously over them, flaring each hit box as it passes.
    /// Reuses `euclidReadIndex` (Derivations.swift) for the per-box HIT/REST content — the SAME pure function
    /// the real render path uses for its own step math (Stage 1) — so the lit boxes can never silently disagree
    /// with what's actually heard the way RATCHET PATTERN/DEST once did.
    /// NOT swing-warped: a deliberate, disclosed simplification matching every OTHER pattern-processor live sweep
    /// in this file (BURST/RATCHET/TUTTI/DEST's StateMatrixClock/liveCol also read a plain linear beat) — only
    /// EUCLID's actual render path (Router.swift) applies `musicalOf`; threading swing into this widget too would
    /// need a new stored property on `ProcessorBox` for a discrepancy that only shows at non-50 swing settings.
    /// SWEEP DIRECTION (Paul 2026-10-02: "reverses direction when reverse is chosen... goes back and forth on
    /// pingpong") — SUPERSEDES the earlier "always left→right, any dir" choice (that read as steadier at the
    /// time, before this was actually asked for): `euclidCometPos`/`euclidCometRaw` (Derivations.swift) give the
    /// comet its own direction-aware continuous screen position — FWD left→right, BKW right→left, PING-PONG
    /// bounces between the two within one lap (now shown in FULL — the ascending-half-only simplification from
    /// when this bar had no bounce motion to show is gone, since PING-PONG now has somewhere to show it). The
    /// per-box HIT/REST content (still `euclidReadIndex` against the static integer screen index) is untouched —
    /// only the comet's own visual motion changed; `age` (how long ago the comet passed a given box, driving its
    /// flare/afterglow) is rederived per direction to match.
    @ViewBuilder private func euclidCometBar(pulses k: Int, steps nIn: Int, rotate: Int, invert: Bool, dir: EuclidDir, rate: ArpRate, spanN: Int, tint: Color,
                                              lanePlaying: Bool,
                                              onRotateDelta: @escaping (Int) -> Void, onHitsDelta: @escaping (Int) -> Void,
                                              onStepsDelta: @escaping (Int) -> Void,
                                              onAllRotateDelta: @escaping (Int) -> Void, onAllHitsDelta: @escaping (Int) -> Void,
                                              onDragState: @escaping (CGPoint?, Bool) -> Void) -> some View {
        let n = max(2, min(16, nIn))
        let sub = max(0.03125, rate.beats)
        let spanBeats = spanN > 0 ? spanLadderBeats(spanN, S: gridStepBeats, row: 8 * gridStepBeats) : 0
        // PER-LANE PLAY/STOP (Paul 2026-10-02: "make sure that if a lane is stopped then the comet doesn't move
        // across it") — a SECOND, independent gate alongside `clockPlaying` (the HOST transport). `running` is
        // true only when BOTH the transport is playing AND this specific lane's own PLAY/STOP is engaged; a
        // stopped lane freezes/hides its comet exactly like a stopped transport does (same `else` branch below),
        // regardless of whether OTHER lanes (or the transport itself) are still running.
        let running = clockPlaying && lanePlaying
        ZStack {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running)) { tl in
            let liveBeat = beatAnchor + tl.date.timeIntervalSince(beatAnchorAt) * tempo / 60.0
            // DIRECTION-AWARE SWEEP (Paul 2026-10-02: "reverses direction when reverse is chosen... goes back
            // and forth on pingpong") — SUPERSEDES the earlier deliberate "always left→right, any dir" choice
            // (see the box-redesign doc comment above). `cometRaw` is the raw tick count mod the direction's
            // real cycle length (n, or 2n under PING-PONG); `cometPos` is its continuous screen position, which
            // now actually reverses/bounces per `euclidCometPos`'s own doc comment. The per-box HIT/REST content
            // (`euclidReadIndex` below) is untouched — only the comet's own visual sweep motion changed.
            let cometRaw = euclidCometRaw(mTickBeat: liveBeat, sub: sub, spanBeats: spanBeats, n: n, dir: dir)
            let cometPos = euclidCometPos(cometRaw, n: n, dir: dir)
            let nD = Double(n)
            Canvas { ctx, size in
                var buf = [Bool](repeating: false, count: n)
                _ = euclidPatternInto(&buf, pulses: k, steps: n, rotation: rotate)
                let w = size.width, midY = size.height / 2
                let insetL: CGFloat = 6, insetR: CGFloat = 6
                let usable = max(1, w - insetL - insetR)
                func xFor(_ pos: Double) -> CGFloat { insetL + usable * CGFloat(pos / Double(n)) }   // the comet still rides this CONTINUOUS position — independent of the discrete boxes below
                // STEP BOXES (Paul 2026-10-02: "incorporate boxes into the design... to represent every step. It
                // needs to be easier to see the number of steps."). Replaces the old thin-baseline + floating-dot
                // track: N bounded, gap-separated rounded-rect slots read the step COUNT at a glance in a way a
                // dot sitting on an otherwise-blank line never did — the boxes themselves ARE the grid, with or
                // without anything lit. Gap narrows as N grows so a dense 16-step lane doesn't crush its boxes
                // into nothing; corner radius is capped relative to box width for the same reason at the thin end.
                let gap: CGFloat = n <= 8 ? 4 : (n <= 12 ? 3 : 2)
                let boxW = max(3, (usable - gap * CGFloat(n - 1)) / CGFloat(n))
                let boxH = min(30, size.height - 6)
                let corner = min(5, boxW / 2.2)
                func boxRect(_ i: Int) -> CGRect {
                    CGRect(x: insetL + CGFloat(i) * (boxW + gap), y: midY - boxH / 2, width: boxW, height: boxH)
                }
                for i in 0..<n {
                    let ri = euclidReadIndex(i, n: n, dir: dir)
                    let hit = invert ? !buf[ri] : buf[ri]
                    let rect = boxRect(i)
                    let box = Path(roundedRect: rect, cornerRadius: corner)
                    if hit {
                        // STOPPED (Paul 2026-10-02: "don't show the playhead comets when the playhead isn't
                        // running" — later widened the SAME day to per-lane: "make sure that if a lane is
                        // stopped then the comet doesn't move across it") — `running` false (either the HOST
                        // transport, or THIS LANE's own PLAY/STOP) means the TimelineView above is PAUSED, so
                        // `phase` is frozen at whatever it was the instant playback stopped, not a meaningful
                        // "time since the comet passed." Drawing the age/recede/burst flare off a frozen age
                        // would leave some hit box stuck mid-flash forever. A stopped lane shows every hit at
                        // one steady, unflared brightness instead — no comet, no animation, no stale frozen flare.
                        if running {
                            // steps since the comet passed this node (0 = just now), wrapped positive every lap —
                            // direction-aware (Paul 2026-10-02): FWD unchanged; BKW mirrors it (the comet visits
                            // box i when cometRaw = n−i); PING-PONG visits box i TWICE per lap (ascending at
                            // cometRaw=i, descending at cometRaw=2n−i) — age takes whichever visit was more recent.
                            let age: Double
                            switch dir {
                            case .fwd:
                                let raw = (cometRaw - Double(i)).truncatingRemainder(dividingBy: nD)
                                age = raw < 0 ? raw + nD : raw
                            case .bkw:
                                let raw = (cometRaw + Double(i)).truncatingRemainder(dividingBy: nD)
                                age = raw < 0 ? raw + nD : raw
                            case .pingpong:
                                let cycleLen = 2 * nD
                                func wrap(_ v: Double) -> Double { let r = v.truncatingRemainder(dividingBy: cycleLen); return r < 0 ? r + cycleLen : r }
                                age = min(wrap(cometRaw - Double(i)), wrap(cometRaw - (cycleLen - Double(i))))
                            }
                            let recede = max(0, 1 - age / 1.5)     // the lingering afterglow (unchanged window)
                            // DRAMATIC HIT (Paul 2026-10-01: "brighter, with effects, more dramatic when it hits") —
                            // a short, sharp BURST window layered on top of the lingering afterglow: the box's
                            // glow swells, a hot white flash core blooms inside it, and a shockwave OUTLINE (the
                            // box-shaped echo of the old circular ring) expands outward — all decay much faster
                            // than `recede` so the strike itself reads as an impact, not just a brighter box.
                            let burst = max(0, 1 - age / 0.35)
                            // a top-lit gradient fill (COOL factor, Paul 2026-10-02: "make it look cool") — a
                            // flat fill read as a dead swatch; light-to-dark top-to-bottom gives each box a
                            // glassy, lit-from-above quality, brightening further on its own burst.
                            ctx.drawLayer { layer in
                                layer.addFilter(.shadow(color: tint.opacity(min(1, 0.55 + burst)), radius: 5 + 14 * burst + 4 * recede))
                                layer.fill(box, with: .linearGradient(Gradient(colors: [tint.opacity(min(1, 0.95 + 0.3 * burst)), tint.opacity(0.55 + 0.25 * recede)]),
                                                                       startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                            }
                            ctx.stroke(box, with: .color(.white.opacity(0.18 + 0.5 * burst)), lineWidth: 1)
                            if burst > 0.04 {   // the hot flash core — a bright inset band, not a second shape
                                let core = Path(roundedRect: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.3), cornerRadius: corner * 0.6)
                                ctx.drawLayer { layer in
                                    layer.addFilter(.shadow(color: .white.opacity(burst), radius: 6 * burst))
                                    layer.fill(core, with: .color(.white.opacity(burst * 0.9)))
                                }
                            }
                            if burst > 0.06 {   // the shockwave — an expanding box outline, reads as an impact not just a flash
                                let grow = 11 * (1 - burst)
                                let ring = Path(roundedRect: rect.insetBy(dx: -grow, dy: -grow), cornerRadius: corner + grow * 0.4)
                                ctx.stroke(ring, with: .color(tint.opacity(0.4 * burst)), lineWidth: 1.5)
                            }
                        } else {
                            ctx.fill(box, with: .color(tint.opacity(0.55)))
                            ctx.stroke(box, with: .color(.white.opacity(0.2)), lineWidth: 1)
                        }
                    } else {
                        // REST (Paul 2026-10-01: "the position of the notes move, not just switch on and off") —
                        // every box's RECT is mathematically fixed per step index regardless of hit/rest, so the
                        // grid itself never relocates — only which boxes are lit does. A plainly visible FILLED +
                        // bordered box (same shape family as a hit, just dim), not a hollow ring, so the fixed
                        // slot grid stays legible regardless of which subset is currently lit.
                        ctx.fill(box, with: .color(.white.opacity(0.09)))
                        ctx.stroke(box, with: .color(.white.opacity(0.16)), lineWidth: 1)
                    }
                }
                // THE COMET — unchanged timing (a soft blurred trail + a glowing head), now riding OVER the box
                // row instead of a thin baseline. MOTION (Paul 2026-10-02) now reverses for BKW and bounces for
                // PING-PONG — `hx` tracks `cometPos`'s own direction-aware sweep; the TRAIL (which side of the
                // head it extends from — always "behind" the direction of travel) follows `movingRight`, which
                // flips for BKW and switches mid-lap for PING-PONG. STOPPED: not drawn at all (Paul 2026-10-02,
                // widened the same day to per-lane PLAY/STOP too) — a paused TimelineView freezes `cometPos`, so
                // without this guard the comet would sit motionless at its last live position instead of
                // disappearing.
                if running {
                    let hx = xFor(cometPos)
                    let movingRight: Bool
                    switch dir {
                    case .fwd: movingRight = true
                    case .bkw: movingRight = false
                    case .pingpong: movingRight = cometRaw < nD
                    }
                    let tx = movingRight ? max(insetL, hx - 22) : min(insetL + usable, hx + 22)
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 3))
                        var trail = Path()
                        trail.move(to: CGPoint(x: hx, y: midY)); trail.addLine(to: CGPoint(x: tx, y: midY))
                        layer.stroke(trail, with: .linearGradient(Gradient(colors: [tint.opacity(0.55), tint.opacity(0)]),
                                                                   startPoint: CGPoint(x: hx, y: midY), endPoint: CGPoint(x: tx, y: midY)),
                                     lineWidth: 5)
                    }
                    ctx.drawLayer { layer in
                        layer.addFilter(.shadow(color: tint, radius: 9))
                        layer.fill(Path(ellipseIn: CGRect(x: hx - 5, y: midY - 5, width: 10, height: 10)), with: .color(tint))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        // GESTURES (Paul 2026-10-01): 1-finger drag left/right = Δrotate, up/down = Δhits (this row); 2-finger drag
        // does the same but to EVERY row (`euclidAllRowsEdit`). PINCH = ΔSTEPS (`onStepsDelta`, EuclidGesturePad's
        // own pinch recognizer) is now the ONLY way to change STEPS from this bar — the thin +/- tap glyphs that
        // used to sit in the pad's side margins are REMOVED (Paul 2026-10-02: "remove the + and - buttons from
        // the Euclid lanes"), control only, not the underlying mechanism (pinch still calls the same
        // `onStepsDelta`). The 14pt inset is LEFT AS-IS, not widened to reclaim the freed margin — the glyphs'
        // removal wasn't an ask to resize the gesture pad itself, just to drop the redundant discrete buttons.
        EuclidGesturePad(onRotateDelta: onRotateDelta, onHitsDelta: onHitsDelta, onStepsDelta: onStepsDelta,
                         onAllRotateDelta: onAllRotateDelta, onAllHitsDelta: onAllHitsDelta, onDragState: onDragState)
            .padding(.horizontal, 14)
        }
    }
    /// A UIKit pan+pinch bridge (Paul 2026-10-01) — SwiftUI's own `DragGesture` doesn't distinguish touch COUNT,
    /// only position, and the EUCLID bar needs a genuine 1-vs-2-finger distinction (1 finger = this row, 2 fingers
    /// = every row). Touch count is LATCHED at `.began`, not re-read every `.changed`, so a finger lifting or
    /// landing mid-drag can't flip which mode the drag is in partway through. PINCH (spread = add steps, pinch-in
    /// = remove) runs on the SAME view as a second recognizer — a genuine pinch (fingers moving apart/together,
    /// centroid roughly static) and a 2-finger pan (both fingers moving together) measure near-orthogonal things,
    /// so they coexist without fighting in practice; the delegate below just lifts UIKit's own default "one
    /// gesture at a time per view" restriction so neither silently blocks the other.
    private struct EuclidGesturePad: UIViewRepresentable {
        let onRotateDelta: (Int) -> Void        // 1-finger horizontal — Δrotate, this row
        let onHitsDelta: (Int) -> Void          // 1-finger vertical — Δhits, this row
        let onStepsDelta: (Int) -> Void         // pinch — Δsteps, this row (shared with the +/- tap glyphs)
        let onAllRotateDelta: (Int) -> Void     // 2-finger horizontal — Δrotate, every row
        let onAllHitsDelta: (Int) -> Void       // 2-finger vertical — Δhits, every row
        // (location, isAllRows) — location is WINDOW-space (`location(in: view.window)`), non-nil while a touch is
        // down, nil the instant it lifts/cancels. Reported on EVERY `.changed` tick too (Paul 2026-10-02), not just
        // begin/end, so a HUD tracking the finger moves continuously, not just at the start of the gesture.
        let onDragState: (CGPoint?, Bool) -> Void
        func makeUIView(context: Context) -> UIView {
            // RAW TOUCH TRACKING (Paul 2026-10-02: "make sure that the overlay... appears on first touch") —
            // UIPanGestureRecognizer/UIPinchGestureRecognizer only transition to .began once a touch has moved
            // past UIKit's own recognition slop, so driving the HUD from them alone leaves a dead zone right
            // after contact (and a plain tap that never moves enough never shows anything). TouchView's raw
            // touchesBegan/Moved/Ended bridge that gap — see its own doc comment below.
            let v = TouchView(); v.backgroundColor = .clear; v.isOpaque = false
            v.coordinator = context.coordinator
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 2
            pan.delegate = context.coordinator
            pan.cancelsTouchesInView = false   // let TouchView keep receiving touch events through the whole gesture, not just up to the moment the recognizer takes over
            v.addGestureRecognizer(pan)
            let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
            pinch.delegate = context.coordinator
            pinch.cancelsTouchesInView = false
            v.addGestureRecognizer(pinch)
            return v
        }
        func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.owner = self }
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        /// Reports raw touch contact straight to the Coordinator, independent of whatever the pan/pinch
        /// recognizers decide — see `makeUIView`'s own comment for why this exists. Tracks the active touch SET
        /// (not just one) so a 2-finger gesture doesn't look "lifted" the instant the FIRST of the two fingers
        /// comes up; `allRows` (≥2 touches) is a plain snapshot of that count, not a latch — it's only used for
        /// this early, pre-recognition HUD label, and corrects itself within milliseconds once the real
        /// recognizer's own LATCHED `twoFinger` (handlePan) takes over reporting.
        private final class TouchView: UIView {
            weak var coordinator: Coordinator?
            private var active: Set<UITouch> = []
            private func report() {
                guard let t = active.first else { return }
                coordinator?.handleRawTouch(t.location(in: window), active.count >= 2)
            }
            override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
                super.touchesBegan(touches, with: event); active.formUnion(touches); report()
            }
            override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
                super.touchesMoved(touches, with: event); report()
            }
            override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
                super.touchesEnded(touches, with: event); active.subtract(touches)
                active.isEmpty ? coordinator?.handleRawTouch(nil, false) : report()
            }
            override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
                super.touchesCancelled(touches, with: event); active.subtract(touches)
                active.isEmpty ? coordinator?.handleRawTouch(nil, false) : report()
            }
        }
        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            var owner: EuclidGesturePad
            func handleRawTouch(_ point: CGPoint?, _ allRows: Bool) { owner.onDragState(point, allRows) }
            private var twoFinger = false
            private var appliedX = 0, appliedY = 0
            private var appliedPinchSteps = 0
            // ~18pt per step each axis — a first-pass sensitivity (tunable): deliberately coarser than NumPair's
            // own 14pt/step scrub, since this bar is small and a finger resting on it covers a fair chunk of it.
            private let stepPt: CGFloat = 18
            // ~15% scale change per ±1 step (log-spaced so pinching in and spreading out feel symmetric — a
            // linear mapping would make the two directions feel unequal) — also a first-pass, tunable threshold.
            private let pinchStepRatio: Double = 1.15
            init(_ o: EuclidGesturePad) { owner = o }
            func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
            @objc func handlePan(_ g: UIPanGestureRecognizer) {
                switch g.state {
                case .began:
                    twoFinger = g.numberOfTouches >= 2
                    appliedX = 0; appliedY = 0
                    owner.onDragState(g.location(in: g.view?.window), twoFinger)
                case .changed:
                    let t = g.translation(in: g.view)
                    let stepsX = Int((t.x / stepPt).rounded())
                    let stepsY = Int((-t.y / stepPt).rounded())   // screen-down is +y; dragging UP should INCREASE
                    if stepsX != appliedX {
                        let d = stepsX - appliedX
                        twoFinger ? owner.onAllRotateDelta(d) : owner.onRotateDelta(d)
                        appliedX = stepsX
                    }
                    if stepsY != appliedY {
                        let d = stepsY - appliedY
                        twoFinger ? owner.onAllHitsDelta(d) : owner.onHitsDelta(d)
                        appliedY = stepsY
                    }
                    owner.onDragState(g.location(in: g.view?.window), twoFinger)   // every tick — the HUD tracks the finger live, not just at touch-down
                case .ended, .cancelled, .failed:
                    owner.onDragState(nil, twoFinger)
                default: break
                }
            }
            @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
                switch g.state {
                case .began:
                    appliedPinchSteps = 0
                    owner.onDragState(g.location(in: g.view?.window), false)   // pinch is always scoped to this row — no "all rows" steps mode
                case .changed:
                    // clamp scale well above 0 before taking its log — two touches landing on nearly the same
                    // point would send scale → 0, and log(0) → -infinity, which traps converting to Int.
                    let steps = Int((log(max(0.05, g.scale)) / log(pinchStepRatio)).rounded())
                    if steps != appliedPinchSteps {
                        owner.onStepsDelta(steps - appliedPinchSteps)
                        appliedPinchSteps = steps
                    }
                    owner.onDragState(g.location(in: g.view?.window), false)
                case .ended, .cancelled, .failed:
                    owner.onDragState(nil, false)
                default: break
                }
            }
        }
    }
    // THE DRAG HUD moved OUT of this box entirely (Paul 2026-10-02: "I want the overlay... to be top level because
    // it's currently fixed on the scrolling processor edit page") — rendering it here could never escape this
    // box's own embedding ScrollView (`buildProcessorPanel`). See `EuclidDragHUDInfo`/`onEuclidDragInfo` above and
    // `BuildPage.swift`'s `buildEuclidDragHUD`/`buildProcessorPanel` for where it actually lives now.
    /// RELAYOUT (Paul 2026-10-02, THIRD pass): sizes a 2×2 box CELL — a 44pt PLAY/STOP button beside the 44pt
    /// comet bar + 6pt padding top/bottom = 56.
    private var euclidLaneH: CGFloat { 56 }
    private var euclidLaneGap: CGFloat { 8 }
    /// One of the four EUCLID lanes' box (Paul 2026-10-02, THIRD relayout pass: "I want the play button on its
    /// original position as part of the grid lane. No select button please, and if any lane is touched I want
    /// it highlighted (the previous behaviour of the select button) which will bring its control into focus").
    /// SUPERSEDES the immediately-prior pass, which had pulled PLAY/STOP out to a separate control row below
    /// and added a dedicated numbered SELECT chip — both reverted here. PLAY/STOP is back INLINE (left of the
    /// comet bar, its original position from before that pass); there is NO select chip anymore — tapping
    /// ANYWHERE on the box (`.onTapGesture` on the whole cell), OR starting a single-lane drag/pinch on its
    /// comet bar, selects it instead, driving the exact same highlight (`selected` border/background) the old
    /// SELECT button used to drive, and the settings panel below focuses on it. The comet bar's own gesture pad
    /// (1-finger drag, 2-finger drag, pinch) is UNCHANGED — still the only way to reshape hits/steps/rotate; a
    /// plain tap (no movement) is never consumed by the pan/pinch recognizers, so it falls through to this
    /// outer tap gesture cleanly (confirmed by reasoning through UIKit's own recognition rules, not guessed —
    /// `UIPanGestureRecognizer`/`UIPinchGestureRecognizer` only transition out of `.possible` once the touch
    /// moves past a system threshold; a touch that never moves simply fails them, un-consumed).
    @ViewBuilder private func euclidLaneBox(_ idx: Int, _ L: EuclidLine, width: CGFloat, onDragInfo: @escaping (EuclidDragHUDInfo?) -> Void) -> some View {
        let selected = euclidSelectedLane == idx
        let on = L.enabledResolved
        HStack(spacing: 8) {
            Image(systemName: on ? "play.fill" : "stop.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(on ? accent : .white.opacity(0.4))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { euclidLineEdit4(idx) { $0.enabled = !($0.enabledResolved) } }   // its own tap wins over the cell's outer select-tap below, at this exact spot — standard SwiftUI nested-gesture precedence
            euclidCometBar(pulses: L.pulses, steps: L.steps, rotate: L.rotate, invert: L.invert, dir: L.directionResolved,
                           rate: p.euclidRate ?? .r1_16, spanN: p.euclidSpanN ?? 0, tint: accent, lanePlaying: on,
                           // DRAG-DIRECTION FIX (Paul 2026-10-02: "I drag a dot one space left, the lit note doesn't
                           // follow — it jumps somewhere else"). Traced, not guessed: `euclidPatternInto`'s
                           // `rotation` is `buf[i] = test((i+rot) % n)` — a TRUE cyclic shift where INCREASING rot
                           // moves every hit LEFT by one screen slot (worked example: E(3,8) rot=0 hits {0,3,6} →
                           // rot=1 hits {2,5,7}, i.e. 0→7(wrap),3→2,6→5 — each exactly one slot left). The pan
                           // gesture's `d` carries the SAME sign as raw finger translation (negative when dragging
                           // left) and was applied as `rotate + d` — so dragging left DECREASED rotate, which
                           // shifts the pattern RIGHT: backwards from the finger, exactly the reported symptom.
                           // Under FWD (screen position i reads buffer index i directly) the fix is `rotate - d`.
                           // Under BKW (`euclidReadIndex` mirrors: screen position i reads buffer index n-1-i) the
                           // relationship flips — the ORIGINAL `rotate + d` is actually correct there, confirmed by
                           // the same substitution worked through the mirrored index. PING-PONG's comet bar reads
                           // the buffer identically to FWD (its own disclosed simplification, see euclidCometBar's
                           // doc comment), so it takes the FWD branch too.
                           onRotateDelta: { d in euclidLineEdit4(idx) { let s = $0.directionResolved == .bkw ? d : -d; $0.rotate = ((($0.rotate + s) % 16) + 16) % 16 } },
                           onHitsDelta: { d in euclidLineEdit4(idx) { let v = max(0, min(max(2, $0.steps), $0.pulses + d)); $0.pulses = min(v, $0.steps) } },
                           onStepsDelta: { d in euclidLineEdit4(idx) { let v = max(2, min(16, $0.steps + d)); $0.steps = v; if $0.pulses > v { $0.pulses = v } } },
                           onAllRotateDelta: { d in euclidAllRowsEdit { line in let s = line.directionResolved == .bkw ? d : -d; line.rotate = ((line.rotate + s) % 16 + 16) % 16 } },
                           onAllHitsDelta: { d in euclidAllRowsEdit { line in let v = max(0, min(max(2, line.steps), line.pulses + d)); line.pulses = min(v, line.steps) } },
                           onDragState: { point, allRows in
                               guard let point else { onDragInfo(nil); return }
                               if !allRows { euclidSelectedLane = idx }   // "if any lane is touched... bring its control into focus" — a single-lane drag/pinch selects too, not just a plain tap; the 2-finger ALL-LANES case doesn't name one lane, so it's excluded
                               let label = allRows ? "ALL LANES" : "LANE \(idx + 1)"
                               onDragInfo(EuclidDragHUDInfo(label: label, hits: L.pulses, steps: L.steps, offset: L.rotate, point: point))
                           })
                .frame(height: 44)
        }
        .padding(6)
        .frame(width: width, height: euclidLaneH)   // EXPLICIT width — the stroke/background below can never bleed past it
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(selected ? 0.07 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? accent.opacity(0.5) : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { euclidSelectedLane = idx }   // a plain tap anywhere on the cell selects it — the SELECT chip's replacement
    }
    /// THE INDIVIDUAL CONTROLS PER LANE (Paul 2026-10-02, HIT/MISS SPLIT: "I want the bottom controls... to
    /// split into two. On the left is 'Lane 1 hit' and on the right is 'Lane 1 miss', which plays the off
    /// notes... Ensure that both 'hits' and 'misses' boxes have identical controls"). DIRECTION stays SINGULAR,
    /// shared above both boxes — it shapes the one underlying K-of-N pattern itself, not a per-outcome setting,
    /// so "identical controls" doesn't apply to it (there's only one pattern to direct, not two). INVERT/DIE
    /// are GONE entire (Paul 2026-10-02, same day, "drop it, please"/"remove the hits button and functionality")
    /// — removed from this panel, not just hidden; see Router.swift's runEuclidLine for the engine-side removal.
    /// DIRECTION moved from `segV` (full-width stacked) back to `seg` (content-sized chips) — "reduce the width
    /// of the back, forward ping-pong buttons" — safe now that this panel spans the full editor width (the
    /// narrow-column truncation `segV` was built to dodge no longer applies here). Labels stay the same-day
    /// >/</>< shrink (display only — the persisted EuclidDir raw values are untouched). `compact: true` halves
    /// its chip height (Paul 2026-10-02) — the LANE N header above this row is GONE (each HIT/MISS box already
    /// labels itself "LANE N HIT"/"LANE N MISS", so the panel-level one was redundant).
    @ViewBuilder private func euclidSettingsPanel(_ L: EuclidLine, idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                field("DIRECTION") {
                    let dirLabels = [">", "<", "><"]
                    let dirSel = dirLabels[[EuclidDir.fwd, .bkw, .pingpong].firstIndex(of: L.directionResolved) ?? 0]
                    seg(dirLabels, sel: dirSel, compact: true) { i in
                        euclidLineEdit4(idx) { $0.direction = [EuclidDir.fwd, .bkw, .pingpong][i] } }
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 10) {
                euclidHitMissBox(idx, L, isMiss: false)
                euclidHitMissBox(idx, L, isMiss: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
    }
    /// One HIT or MISS box (Paul 2026-10-02) — "under these titles are note selectors, one for each... put
    /// octave to the right of the note selectors, and half its height... put velocity and gate (both controls
    /// in both sections) onto the same line." Structurally identical both ways, by construction (one function,
    /// an `isMiss` flag choosing which fields to read/write) — the ONE deliberate, flagged asymmetry is RIFF/
    /// ARP: offered on HIT when the preceding slot matches (unchanged `precedingSourceType` mechanism), never
    /// on MISS, which has no analogous "immediately-preceding slot" concept of its own — `runEuclidLine`
    /// (Router.swift) guards this explicitly on the engine side too, so a stray `.riff`/`.arp` miss pick can't
    /// silently read as ALL. No DIE row on either side — removed entire the same day ("drop it, please").
    @ViewBuilder private func euclidHitMissBox(_ idx: Int, _ L: EuclidLine, isMiss: Bool) -> some View {
        let cur: EuclidNoteSel = isMiss ? (L.missNoteSel ?? .all) : L.noteSelResolved   // MISS: nil (off) highlights nothing — .all is never in euclidNoteSelShown, so this reads honestly as "none picked"
        let shown: [EuclidNoteSel] = isMiss ? euclidNoteSelShown
            : euclidNoteSelShown + (precedingSourceType == .riff ? [.riff] : precedingSourceType == .arp ? [.arp] : [])
        VStack(alignment: .leading, spacing: 6) {
            Text(isMiss ? "LANE \(idx + 1) MISS" : "LANE \(idx + 1) HIT")
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            // RELAYOUT (Paul 2026-10-02: "ensure that the octave controls are lined up with the note selector to
            // its left and gate below it") — two columns, not the old chip-row+OCT / VEL+GATE split: LEFT = note
            // chips over VELOCITY, RIGHT = OCTAVE over GATE — so OCTAVE sits beside (lined up with) the note
            // chips, and GATE sits directly below OCTAVE specifically, not shared with VELOCITY anymore.
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    euclidNoteSelChipRow(shown, cur) { s in euclidLineEdit4(idx) { if isMiss { $0.missNoteSel = s } else { $0.noteSel = s } } }
                    field("VEL  \(Int((isMiss ? L.missVelocityResolved : L.velocityResolved) * 100))%") {
                        slider(bind(isMiss ? L.missVelocityResolved : L.velocityResolved) { v in
                            euclidLineEdit4(idx) { if isMiss { $0.missVelocity = v } else { $0.velocity = v } } }, in: 0...2)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 4) {   // OCT label kept (a bare stepper alone reads ambiguous); `compact: true` is the earlier "half its height" ask
                    Text("OCT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                    numPair(isMiss ? L.missOctaveResolved : L.octaveResolved, -3...3, compact: true) { v in
                        euclidLineEdit4(idx) { if isMiss { $0.missOctave = v } else { $0.octave = v } } }
                    field("GATE  \(Int((isMiss ? L.missGateResolved : L.gateResolved) * 100))%") {
                        slider(bind(isMiss ? L.missGateResolved : L.gateResolved) { v in
                            euclidLineEdit4(idx) { if isMiss { $0.missGate = v } else { $0.gate = v } } }, in: 0.05...1)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    @ViewBuilder private func typeParams(_ ft: ProcessorType) -> some View {
        switch ft {
        case .empty: EmptyView()   // the sentinel — buildIsEmptySlot filters this out before the editor ever opens on one
        case .arp: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {
            // ROW 1 — ARP PATTERN (two equally-sized rows of 5) | SPEED, equal height (Paul 2026-09-30 layout).
            // The pattern table (10 entries — see arpPatternOptions) splits evenly in half; each row renders through
            // the SAME arpPatternRow, just a different slice, so a selection in either row still lights correctly.
            // Height match, computed exactly (not eyeballed): 2 rows × 48pt chip + 1×6pt gap = 102 — SPEED's own
            // arpSpeedGrid is 3 rows × 32pt + 2×3pt gap = 102. Same total, by construction.
            HStack(alignment: .top, spacing: 12) {
                field("ARP PATTERN") {
                    let pick: (ArpPattern, Int) -> Void = { pat, anc in
                        setParam {
                            $0.pattern = pat; $0.arpRandomAnchor = anc
                            // RANDOM ONCE (Paul 2026-09-16): each tap rolls a FRESH persisted seed → a new fixed shuffle (and a
                            // re-tap = re-roll). Only for this pattern; every other pick leaves the stored seed untouched.
                            if pat == .randomOnce { $0.arpSeed = Int.random(in: Int.min...Int.max) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        arpPatternRow(Array(ProcessorBox.arpPatternOptions.prefix(5)), pattern: p.pattern ?? .up, anchor: p.arpRandomAnchor ?? 0, pick)
                        arpPatternRow(Array(ProcessorBox.arpPatternOptions.suffix(5)), pattern: p.pattern ?? .up, anchor: p.arpRandomAnchor ?? 0, pick)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                field("SPEED", \.rate, lfo: "arpRate") {   // ∿ LFO sweeps the rate ladder; the swept rate shows here as a dim ring (Paul 2026-09-16)
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !clockPlaying || lfoFor("arpRate") == nil)) { tl in
                        arpSpeedGrid(sel: p.rate ?? .r1_16, live: lfoFor("arpRate").flatMap { lfoLiveRateIndex($0, date: tl.date) }) { r in setParam { $0.rate = r } }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            // ROW 2 — ARP FLOW | OCTAVES+OCT DIR (stacked) | LENGTH/VELOCITY/VELOCITY TILT (stacked) (Paul 2026-09-30
            // layout, revised same day: the three sliders now stack instead of sitting side-by-side).
            // VELOCITY (arpVelocity, 1…100 — Paul 2026-09-30 revision: an ABSOLUTE value, not a multiplier; the
            // picked note's own input velocity is now ignored entirely) and VELOCITY TILT (arpVelTilt, −1…1, favours
            // the top/bottom of the held pool, applied ON TOP of the fixed VELOCITY base) — see Derivations.arpPick's
            // velocity/velTilt params and effectiveArpVelocity/Tilt (Snapshot.swift). Both carry a ∿ LFO.
            HStack(alignment: .top, spacing: 12) {
                // FLOW stacked VERTICALLY (Paul 2026-09-14): legato/retrig/free on top of each other — 3 rows × 32pt +
                // 2×3pt gap = 102, matching SPEED/PATTERN above by the same arithmetic.
                field("ARP FLOW", \.phase) { segV(["LEGATO", "RETRIG", "FREE"], sel: (p.phase ?? .legato).rawValue) { i in
                    setParam { $0.phase = [ArpPhase.legato, .retrig, .free][i] } } }
                    .frame(maxWidth: .infinity, alignment: .leading)
                // OCTAVES + OCT DIR stacked one over the other (Paul 2026-09-30, were side-by-side fields) — each keeps
                // its own label for clarity. DEVICE-EYE OWED: unlike the PATTERN/SPEED pair above, this compound
                // two-label stack's total height against FLOW's single-label segV isn't provably exact from source
                // alone (SwiftUI's own text-line-height metrics aren't something to hand-compute) — flagged, not
                // silently assumed equal.
                VStack(alignment: .leading, spacing: 8) {
                    field("OCTAVES", \.octaves) { numPair(p.octaves ?? 1, 1...4) { v in setParam { $0.octaves = v } } }
                    // OCT DIRECTION (Paul 2026-08-22): the laps ascend the octaves (UP) or descend them (DOWN).
                    field("OCT DIR", \.arpOctDown) { seg(["UP", "DOWN"], sel: (p.arpOctDown ?? false) ? "DOWN" : "UP") { i in
                        setParam { $0.arpOctDown = (i == 1) } } }
                }.frame(maxWidth: .infinity, alignment: .leading)
                // LENGTH / VELOCITY / VELOCITY TILT, stacked (Paul 2026-09-30: "stack the three sliders on top of
                // each other" — were three side-by-side slots; now one slot, top-to-bottom in the order Paul named
                // them). Each keeps its own label/LFO; naturally equal height already (all three are the same
                // slider/lfoSlider → FineSlider content underneath), now also equal WIDTH (one shared slot).
                VStack(alignment: .leading, spacing: 8) {
                    field("LENGTH \(Int((p.gate ?? 0.6) * 100))%", \.gate, lfo: "gate") {   // ∿ LFO on the label row (Docs/PLAN-param-lfo.md)
                        // Reflect a LENGTH LFO here too (Paul 2026-09-16): a dim live tick tracks the sweep on the MAIN slider.
                        if let glfo = lfoFor("gate") { lfoSlider(p.gate ?? 0.6, 0.05...1, lfo: glfo) { v in setParam { $0.gate = v } } }
                        else { slider(bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1) }
                    }
                    // VELOCITY (Paul 2026-09-30 revision): a plain 1…100 ABSOLUTE value — no "%" (this isn't a scale
                    // anymore, see arpVelocity's own doc comment in Models.swift/Snapshot.swift).
                    field("VELOCITY \(Int(p.arpVelocity ?? 100))", \.arpVelocity, lfo: "arpVelocity") {
                        if let vlfo = lfoFor("arpVelocity") { lfoSlider(p.arpVelocity ?? 100, 1...100, lfo: vlfo) { v in setParam { $0.arpVelocity = v } } }
                        else { slider(bind(p.arpVelocity ?? 100) { v in setParam { $0.arpVelocity = v } }, in: 1...100) }
                    }
                    bipolarSlider("VEL TILT \(Int((p.arpVelTilt ?? 0) * 100))  (−bottom · +top)", p.arpVelTilt ?? 0, lfo: "arpVelTilt") { v in setParam { $0.arpVelTilt = v } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            // SPAN (Paul 2026-09-13, replaces FIT): the universal span-ladder — FREE runs the global grid, N re-anchors
            // the pattern to index 0 every N columns (polymeter), same behaviour as riff/euclid/etc.
            frameSpan(p.arpSpanN ?? 0, free: true) { v in setParam { $0.arpSpanN = v } }
        })
        case .ratchet: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {
            let rmode = p.rtcMode ?? .all      // mode set by the storefront card — no in-editor radio (Paul 2026-08-22)
            if rmode == .all {
                heroField("REPEATS") { numPair(p.count ?? 3, 2...8) { v in setParam { $0.count = v } } }
            } else if rmode == .coin {
                Text("each step rolls: ratchet (a burst) or plain (one hit)").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
                heroField("CHANCE — how often a step bursts  \(Int((p.rtcChance ?? 0.5) * 100))%", lfo: "rtcChance") {
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
                // PASS-THROUGH (Paul 2026-09-06): downstream of a driver (e.g. [ARP → RATCHET]), RATCHET DRIVES re-pools the arp;
                // PASS · RATCHET CHOSEN keeps the arp driving — most notes pass through UNCHANGED, only the COIN-chosen ones burst.
                field("WHEN AFTER A DRIVER (e.g. ARP)", \.rtcFold) {
                    seg(["RATCHET DRIVES", "PASS · RATCHET CHOSEN"], sel: (p.rtcFold ?? false) ? "PASS · RATCHET CHOSEN" : "RATCHET DRIVES") { i in setParam { $0.rtcFold = (i == 1) } } }
            } else {   // pattern — a step MATRIX (Paul 2026-09-07, Model B): STEPS columns, each a COUNT (1 = pass the note
                       // through · 2–8 = ratchet). NO rest — every column sounds. Downstream of a driver it advances one column PER ARP NOTE.
                let steps = max(1, min(32, p.rtcSteps ?? 8))
                let clockMode = p.rtcClock ?? .time
                // PLAYHEAD (Paul 2026-09-07): the ratchet's OWN column, col = floor(beat ÷ ADVANCE) mod STEPS (+ ROTATE). In TIME
                // the advance = RATE; in NOTE the advance = the upstream DRIVER's note rate (so the playhead sweeps at the rate
                // notes actually arrive). Extrapolated per animation frame inside stateMatrixRadio (NOT the ~4 Hz poll — that
                // aliases a fast rate to a 1↔5 jump). SPAN re-anchors every N MATRIX columns.
                let ratchetRate = Swift.max(0.03125, (p.rtcRate ?? .r1_8).beats)
                let advanceRate = (clockMode == .note && driverNoteRate > 0) ? driverNoteRate : ratchetRate
                let ratchetSpanN = p.rtcSpanN ?? 0     // SPAN = re-anchor every N MATRIX columns (0 = FREE over all STEPS) — Paul 2026-09-07
                // NOTE mode with no known driver rate (standalone / irregular driver) → no periodic sweep; leave the playhead static.
                let ratchetClock = (clockPlaying && !(clockMode == .note && driverNoteRate <= 0))
                    ? StateMatrixClock(anchor: beatAnchor, anchorAt: beatAnchorAt, tempo: tempo,
                                       rate: advanceRate, steps: steps, rotate: p.rtcRotate ?? 0,
                                       span: ratchetSpanN > 0 ? Double(ratchetSpanN) * advanceRate : 0)
                    : nil
                heroField("STEPS — pattern length  (1–32)") {
                    numPair(p.rtcSteps ?? 8, 1...32) { v in setParam { $0.rtcSteps = v } } }
                field("CLOCK — how the playhead advances", \.rtcClock) {
                    seg(["TIME", "NOTE"], sel: clockMode == .note ? "NOTE" : "TIME") { i in setParam { $0.rtcClock = (i == 1 ? .note : .time) } } }
                field("PER STEP — tap a column  (· = off/mute · 1 = pass · 2–8 = ratchet)", \.rtcSlices) {
                    stateMatrixRadio([0, 1, 2, 3, 4, 5, 6, 7, 8], steps: steps, clock: ratchetClock,
                        header: { v in
                            let label: String = v == 0 ? "·" : String(v)
                            let op: Double = v == 0 ? 0.5 : 0.75
                            return AnyView(Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color.white.opacity(op)).frame(width: 22, alignment: .leading))
                        },
                        eFill: false,   // euclid control removed (Paul 2026-09-07)
                        onRotate: { d in setParam { $0.rtcRotate = ((($0.rtcRotate ?? 0) + d) % steps + steps) % steps } },
                        selected: { i in let a = p.rtcSlices ?? []; return i >= 0 && i < a.count ? max(0, a[i]) : 1 },
                        set: { i, v in setParam { var s = $0.rtcSlices ?? Array(repeating: 1, count: steps); while s.count < steps { s.append(1) }; s[i] = v; $0.rtcSlices = s } })
                }
            }
            field("BURST FADE — velocity across a burst  \(Int((p.ramp ?? 0.5) * 100))%", \.ramp) {
                slider(bind(p.ramp ?? 0.5) { v in setParam { $0.ramp = v } }, in: 0...1)
            }
            // §1 STANDARD PANEL ANATOMY (Paul 2026-08-27) — THE FOOTER: the frame row (GRID · ROTATE · SPAN, PATTERN mode
            // only) in fixed order + place, then the pairs-well line. GRID = slice width · SPAN = the pattern's loop period.
            if rmode == .pattern {
                frameRow(grid:  { frameGrid(p.rtcRate ?? .r1_8) { r in setParam { $0.rtcRate = r } } },
                         rotate: { EmptyView() },   // ROTATE dropped — no per-step pattern to rotate in the RIFF-shaped model (Paul 2026-09-06)
                         span:   { frameSpan(p.rtcSpanN ?? 0, free: true) { v in setParam { $0.rtcSpanN = v } } },
                         pairs: .ratchet)
            }
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
            let rawIv = p.harmIntervals ?? [0,0,0]
            let iv = rawIv.count >= 3 ? rawIv : rawIv + Array(repeating: 0, count: 3 - rawIv.count)   // bounds-safe: pad a ragged/short decoded array
            let hu = p.harmUnits ?? .semitones
            ForEach(0..<3, id: \.self) { k in
                field("VOICE \(k+1) \(iv[k] == 0 ? "off" : (iv[k] > 0 ? "+\(iv[k])" : "\(iv[k])"))") {
                    stepper(iv[k], -24, 24) { v in setParam { var a = $0.harmIntervals ?? [0,0,0]; while a.count <= k { a.append(0) }; a[k] = v; $0.harmIntervals = a } }
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
            let epm = p.echoPitchMode ?? .semitones
            field("PITCH STEP  \(pit > 0 ? "+" : "")\(pit) \(epm == .inKey ? "(in key)" : "st") / echo", \.echoPitch) { stepper(pit, -24, 24) { v in setParam { $0.echoPitch = v } } }
            if pit != 0 {
                field("UNITS", \.echoPitchMode) { seg(EchoPitchMode.allCases.map { $0.rawValue }, sel: epm.rawValue) { i in setParam { $0.echoPitchMode = EchoPitchMode.allCases[i] } } }   // IN-KEY = the trail WALKS THE SCALE live, from the FROM receivers below, not chromatic (supersedes the old POOL mode)
                if epm == .inKey {
                    // Styled + labelled IDENTICALLY to the main MIDI-IN toggles (Paul 2026-09-29) — the shared
                    // `ioChip` + `doorKeyLabels`/`noteClassLabel` (a door's key when it's a SCALE door, else its
                    // live notes, else "no input"). Multi-select (a bitmask, unlike the main toggles' single-select),
                    // so `on` reads per-bit instead of an equality check.
                    let recvMask = p.echoInKeyReceivers ?? 0
                    VStack(alignment: .leading, spacing: 5) {
                        Text("FROM").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            ForEach(0..<4, id: \.self) { i in
                                let on = (recvMask >> UInt8(i)) & 1 != 0
                                ioChip(doorKeyLabels[i] ?? noteClassLabel(avoidInputNotes[i]) ?? "no input", on: on, accent: receiverGrey(i)) {
                                    setParam { let cur = $0.echoInKeyReceivers ?? 0; $0.echoInKeyReceivers = cur ^ (1 << UInt8(i)) }
                                }
                            }
                        }
                    }
                }
            }
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
        case .euclid: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // GENERATOR — K-of-N euclidean rhythm; FOUR ALWAYS-VISIBLE FIXED LANES
            let rows = p.euclidLinesForEditing()   // ALWAYS exactly 4 (the fixed-4-row model) — direct rows[0...3] indexing below is safe by that standing invariant, not a guess
            let selIdx = min(max(0, euclidSelectedLane), max(0, rows.count - 1))
            // RELAYOUT (Paul 2026-10-02, FOURTH pass): "extend the width of the controls so that they take up
            // the entire processor control window... they should be below the output piano too. The total
            // width should be the same as the euclid controls box that sits underneath it." ROOT CAUSE of the
            // reported mismatch: `buildTruthStrips()` (BuildPage.swift) renders IN|OUT as two HALF-width
            // siblings side by side — the PRIOR pass's half-width, left-aligned 2×2 box only ever sat under the
            // IN half, never the OUT half, while `euclidSettingsPanel` below it was already full width. FIX:
            // the 2×2 grid now spans the FULL editor width (no more `* 0.5` + trailing Spacer) — matching
            // `euclidSettingsPanel`'s own width exactly, and reaching under both piano halves.
            GeometryReader { geo in
                let cellW = max(80, (geo.size.width - euclidLaneGap) / 2)
                VStack(spacing: euclidLaneGap) {
                    HStack(spacing: euclidLaneGap) {
                        euclidLaneBox(0, rows[0], width: cellW, onDragInfo: onEuclidDragInfo)
                        euclidLaneBox(1, rows[1], width: cellW, onDragInfo: onEuclidDragInfo)
                    }
                    HStack(spacing: euclidLaneGap) {
                        euclidLaneBox(2, rows[2], width: cellW, onDragInfo: onEuclidDragInfo)
                        euclidLaneBox(3, rows[3], width: cellW, onDragInfo: onEuclidDragInfo)
                    }
                }
            }
            .frame(height: euclidLaneH * 2 + euclidLaneGap)   // pins the reader's own height to the known 2-row box height — it doesn't need to measure this dimension
            if selIdx < rows.count {
                euclidSettingsPanel(rows[selIdx], idx: selIdx)
            }
            // FOOTER (HITS FROM / GRID / SPAN) REMAINS REMOVED (Paul 2026-10-02, earlier the same day: "remove
            // everything below the lanes") — those three params still exist and still resolve/render, just
            // with no UI left on this page to change them (flagged in full at the time).
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
                // LIVE SWEEP (Paul 2026-09-28): mirrors the engine's own read exactly (Router.swift layBurst/.pattern) —
                // FIXED 8 divides the span into 8 slices; RATE walks it at burstRateBeats instead, both tiled mod-8
                // by `burstSliceAt` — so the matrix's fixed 8-column width is always right, only the SLICE WIDTH
                // (and re-anchor span) changes with the mode. ROTATE is NEGATED: `burstSliceAt` reads slot
                // `(i − rotate) mod 8`, the opposite sign from stateMatrixRadio's own `(g + rotate)` convention —
                // confirmed by reading the engine, not assumed (BURST is the one processor in this file where the
                // two conventions run backwards from each other).
                let burstSpanBeats = spanLadderBeats(p.burstSpanN ?? ((p.burstSpan ?? .cell) == .row ? 8 : 1), S: gridStepBeats, row: 8 * gridStepBeats)
                let burstSliceW = (p.burstRateOn ?? false) ? Swift.max(0.03125, (p.burstRate ?? .r1_8).beats) : Swift.max(0.03125, burstSpanBeats / 8)
                let burstClock = clockPlaying
                    ? StateMatrixClock(anchor: beatAnchor, anchorAt: beatAnchorAt, tempo: tempo, rate: burstSliceW, steps: 8, rotate: -(p.burstRotate ?? 0), span: burstSpanBeats)
                    : nil
                field("BURST SHAPE PER STEP — tap a cell  (B launch · C carry · R rest)") {
                    stateMatrixRadio(BurstSlice.allCases, clock: burstClock,
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
        case .mod: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {      // CC GENERATOR — arp-LFO anatomy (Paul 2026-09-16): FROM · TO (+ live marker) · WAVE/DURATION/source rows · TARGET
            let src = p.modSource ?? .shape    // source set by the storefront card — no in-editor radio (Paul 2026-08-22)
            let lo = p.modMin ?? 0, hi = p.modMax ?? 127
            // FROM / TO — the value endpoints (ALL sources), with a live dim marker tracking the current CC output. MOD is
            // standalone so these are its OWN authored min/max (no two-views / no seed reset); MIN>MAX still inverts.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !clockPlaying)) { tl in
                let live = modLiveCC(date: tl.date)
                VStack(alignment: .leading, spacing: rowSpacing) {
                    modEndpointSlider("FROM  \(lo)", lo, live: live) { v in setParam { $0.modMin = v } }
                    modEndpointSlider("TO  \(hi)\(lo > hi ? "  (inv)" : "")", hi, live: live) { v in setParam { $0.modMax = v } }
                }
            }
            switch src {
            case .shape:
                heroField("WAVE") { iconSeg(ModShape.allCases.map(\.rawValue), sel: (p.modShape ?? .sine).rawValue, glyph: { i, t in waveGlyph(ModShape.allCases[i], t) }) { i in setParam { $0.modShape = ModShape.allCases[i] } } }
                modDurationControl()                              // DURATION — GRID STEPS · FIXED SUBDIVISION (the arp-LFO control), replaces CYCLE + SPAN
                let ph = Int(((p.modPhase ?? 0) * 360).rounded())   // §14② PHASE offset 0–360°
                field("PHASE  \(ph)°", \.modPhase) { slider(bind(p.modPhase ?? 0) { v in setParam { $0.modPhase = v } }, in: 0...1) }
            case .follow:
                field("LISTEN TO", \.modFollow) { seg(ModFollow.allCases.map(\.rawValue), sel: (p.modFollow ?? .register).rawValue) { i in setParam { $0.modFollow = ModFollow.allCases[i] } } }
            case .steps:
                let sspan = p.modStepSpan ?? ((p.modSpan == .row) ? .row : .period)   // migrate the old cell|row span for display
                let n = sspan.stepCount
                let base = [0, 18, 36, 54, 72, 90, 108, 127]
                let shown = (0..<n).map { i -> Int in let s = p.modSteps ?? base; return s[i % s.count] }   // pad the stored steps to N for drawing
                // LIVE SWEEP (Paul 2026-09-28, found while fixing the audit's named cases — MOD's own STEPS lane has
                // the identical "always reads the generic grid clock" gap): shares modLiveCC's own period exactly
                // (GRID STEPS override, else PERIOD/ROW/×2/×4), so the sweep and the live CC marker above can't disagree.
                let modStepsPeriod = modPeriodBeatsUI(src: .steps)
                let modStepsLive: ((Date) -> Int?)? = clockPlaying ? { date in
                    let beat = beatAnchor + date.timeIntervalSince(beatAnchorAt) * tempo / 60.0
                    return Int(positiveFract(beat / modStepsPeriod) * Double(n)) % Swift.max(1, n)
                } : nil
                heroField("STEPS  (drag to draw · \(n))") { sliderLane(shown, count: n, eFill: true, liveColOverride: modStepsLive) { i, v in
                    setParam { var s = $0.modSteps ?? base; let orig = s; while s.count < n { s.append(orig[s.count % orig.count]) }; s[i] = v; $0.modSteps = s } } }
                field("SPAN", \.modStepSpan) { seg(ModStepSpan.allCases.map(\.rawValue), sel: sspan.rawValue) { i in setParam { $0.modStepSpan = ModStepSpan.allCases[i] } } }   // STEPS keeps its coupled step-span (PERIOD/ROW/×2/×4)
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
                let em = p.modExternMode ?? .reEmit    // §6: RE-EMIT (re-range) | SCALE (the wheel scales the SHAPE's depth)
                field("MODE", \.modExternMode) { seg(["RE-EMIT", "SCALE"], sel: em == .scale ? "SCALE" : "RE-EMIT") { i in setParam { $0.modExternMode = (i == 1) ? .scale : .reEmit } } }
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
            // (MIN/MAX moved to the FROM/TO endpoints at the TOP — Paul 2026-09-16 arp-LFO anatomy.)
            field("ON EXIT", \.modReset) { seg(["RESET", "LEAVE"], sel: (p.modReset ?? true) ? "RESET" : "LEAVE") { i in setParam { $0.modReset = (i == 0) } } }
            let q = p.modQuantize ?? 0                             // §14① QUANTIZE — snap the output to N levels
            field("QUANTIZE", \.modQuantize) { numPair(q, 0...32, format: { $0 <= 1 ? "OFF" : "\($0) LVL" }) { v in setParam { $0.modQuantize = v } } }
            let free = p.modFree ?? false                          // §16 FREE / LFO CELL — speak regardless of the playhead
            field("SPEAK", \.modFree) { seg(["ON PLAYHEAD", "FREE (LFO)"], sel: free ? "FREE (LFO)" : "ON PLAYHEAD") { i in setParam { $0.modFree = (i == 1) } } }
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
                // LIVE SWEEP (Paul 2026-09-28): mirrors the engine's own standalone-driver read exactly
                // (Router.emitTuttiPatternRow) — the pattern walks at its own tuttiRate, re-anchoring every
                // tuttiSpanN columns when set (0 = free-running), never the scene's default grid clock.
                let tuttiSub = Swift.max(0.03125, (p.tuttiRate ?? .r1_8).beats)
                let tuttiSpanBeats = (p.tuttiSpanN ?? 0) > 0 ? spanLadderBeats(p.tuttiSpanN ?? 0, S: gridStepBeats, row: 8 * gridStepBeats) : 0
                let tuttiClock = clockPlaying
                    ? StateMatrixClock(anchor: beatAnchor, anchorAt: beatAnchorAt, tempo: tempo, rate: tuttiSub, steps: 8, rotate: p.tuttiRotate ?? 0, span: tuttiSpanBeats)
                    : nil
                // An 8×8 STATE MATRIX — rows = the chord shapes, columns = the 8 steps; tap a cell to set that step.
                heroField("CHORD SHAPE PER STEP — tap a cell (dots = which notes sound)") {
                    stateMatrixRadio(TuttiSlice.allCases, clock: tuttiClock,
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
            field("FLOW — RETRIG restarts each step · FREE runs the grid · LEGATO flows from the hold", \.weavePhase) { seg(ArpPhase.allCases.map(\.rawValue), sel: (p.weavePhase ?? .retrig).rawValue) { i in
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
        case .velocity: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // DYNAMICS (Paul 2026-09-07) — the VELOCITY SEQUENCER: a per-step velocity OVERRIDE lane + a per-step
                                                                                     // PASSTHROUGH toggle; STEPS/RATE/SPAN like the other lanes + a TIME|NOTE clock (advance per note).
            let steps = max(1, min(32, p.velSteps ?? 8))
            let lane: [Int] = { var a = p.velLane ?? Array(repeating: 100, count: steps); while a.count < steps { a.append(100) }; return Array(a.prefix(steps)) }()
            let pass: [Int] = { var a = p.velPass ?? Array(repeating: 0, count: steps); while a.count < steps { a.append(0) }; return Array(a.prefix(steps)) }()
            // LIVE SWEEP (Paul 2026-09-28): mirrors RATCHET PATTERN's own NOTE-clock guard exactly (`driverNoteRate`,
            // fed by the diagnostic poll) — TIME advances at velRate; NOTE advances one column per upstream driver
            // note (no known driver rate ⇒ leave the playhead static, same as RATCHET, rather than show a wrong one).
            // ONE clock feeds BOTH lanes below (the velocity lane's own sliderLane clock AND the BYPASS toggleLane's
            // liveColOverride, via the shared `liveCol(from:at:)`), so they can't disagree with each other either.
            let velClockMode = p.velClock ?? .time
            let velAdvance = velClockMode == .note ? driverNoteRate : Swift.max(0.03125, (p.velRate ?? .r1_8).beats)
            let velSpanBeats = (p.velSpanN ?? 0) > 0 ? Double(p.velSpanN ?? 0) * velAdvance : 0
            let velLiveClock = (clockPlaying && !(velClockMode == .note && driverNoteRate <= 0))
                ? StateMatrixClock(anchor: beatAnchor, anchorAt: beatAnchorAt, tempo: tempo, rate: velAdvance, steps: steps, rotate: 0, span: velSpanBeats)
                : nil
            heroField("VELOCITY PER STEP  (drag ACROSS the bars to draw · 1–127)") {
                sliderLane(lane, count: steps, max: 127, eFill: false, clock: velLiveClock) { i, v in   // no euclid brush (Paul 2026-09-07) — draw the lane by hand
                    setParam { var a = $0.velLane ?? Array(repeating: 100, count: steps); while a.count < steps { a.append(100) }; a[i] = Swift.max(1, v); $0.velLane = a } }
            }
            field("BYPASS PER STEP  (drag across to pass steps through — keep the note's OWN velocity)") {
                toggleLane(steps, on: { s in s < pass.count && pass[s] != 0 }, glyph: "arrow.right", live: { date in liveCol(from: velLiveClock, at: date) }) { s, target in
                    setParam { var a = $0.velPass ?? Array(repeating: 0, count: steps); while a.count < steps { a.append(0) }; a[s] = target ? 1 : 0; $0.velPass = a } }
            }
            field("STEPS — pattern length  (1–32)") { numPair(p.velSteps ?? 8, 1...32) { v in setParam { $0.velSteps = v } } }
            field("CLOCK — how the lane advances", \.velClock) {
                seg(["TIME", "NOTE"], sel: (p.velClock ?? .time) == .note ? "NOTE" : "TIME") { i in setParam { $0.velClock = (i == 1 ? .note : .time) } } }
            field("RATE — the step clock  (used in TIME mode)", \.velRate) {
                seg(ArpRate.allCases.map(\.rawValue), sel: (p.velRate ?? .r1_8).rawValue) { i in setParam { $0.velRate = ArpRate.allCases[i] } } }
            frameSpan(p.velSpanN ?? 0, free: true) { v in setParam { $0.velSpanN = v } }   // SPAN = re-anchor the lane every N columns (0 = FREE across all STEPS)
        })
        case .dest: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {    // ROUTING (Paul 2026-08-22 §5, reworked 2026-09-26) — the DEST MATRIX: which emitter each step hockets to
            let base = [0, 1, 2, 3, 0, 1, 2, 3]
            // OWN CLOCK (Paul 2026-09-26, RATCHET-PATTERN-shaped): the matrix used to light on the DEFAULT grid-column clock
            // while the engine routed by `chopSlice` (an 8-way subdivision of ONE column) — two different clocks, so the lit
            // cell had nothing to do with what emitter actually played. Both now read the SAME free-running self-clock
            // (col = floor(beat ÷ RATE) mod 8), extrapolated per animation frame — never the ~4 Hz poll, which aliases a
            // fast rate into a jump (the exact bug RATCHET PATTERN's matrix had before it got its own clock).
            let destRate = Swift.max(0.03125, (p.destRate ?? .r1_8).beats)
            let destClock = clockPlaying ? StateMatrixClock(anchor: beatAnchor, anchorAt: beatAnchorAt, tempo: tempo,
                                                             rate: destRate, steps: 8, rotate: 0, span: 0) : nil
            field("EMITTER PER STEP — tap a cell (the hocket; · = no emitter)", \.destSlices) {
                stateMatrixRadio([-1, 0, 1, 2, 3], clock: destClock,
                    header: { e in
                        let label = e == -1 ? "·" : ["A", "B", "C", "D"][e]
                        return AnyView(Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(e == -1 ? 0.5 : 0.75)).frame(width: 22, alignment: .leading))
                    },
                    selected: { i in let s = p.destSlices ?? base; return i < s.count ? max(-1, min(3, s[i])) : 0 },
                    set: { i, e in setParam { var s = $0.destSlices ?? base; while s.count < 8 { s.append(0) }; s[i] = e; $0.destSlices = s } })
            }
            field("RATE — the router's own clock (free-running)", \.destRate) {
                seg(ArpRate.allCases.map(\.rawValue), sel: (p.destRate ?? .r1_8).rawValue) { i in setParam { $0.destRate = ArpRate.allCases[i] } } }
        })
        case .deal: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {    // ROUTING (Paul 2026-09-16) — the DEAL: override the emitters, deal N1 → 1, N2 → 2
            let e1 = max(0, min(3, p.dealE1 ?? 0)), e2 = max(0, min(3, p.dealE2 ?? 1))
            let letters = ["A", "B", "C", "D"]
            row2({ field("EMITTER 1", \.dealE1) { seg(letters, sel: letters[e1]) { i in setParam { $0.dealE1 = i } } } },
                 { field("TO 1 — notes", \.dealN1) { numPair(p.dealN1 ?? 1, 1...16) { v in setParam { $0.dealN1 = v } } } })
            row2({ field("EMITTER 2", \.dealE2) { seg(letters, sel: letters[e2]) { i in setParam { $0.dealE2 = i } } } },
                 { field("TO 2 — notes", \.dealN2) { numPair(p.dealN2 ?? 1, 1...16) { v in setParam { $0.dealN2 = v } } } })
            field("DEAL — when a note advances the deal", \.dealMode) { seg(DealMode.allCases.map(\.rawValue), sel: (p.dealMode ?? .overTime).rawValue) { i in setParam { $0.dealMode = DealMode.allCases[i] } } }
            Text("OVER TIME — each strike in turn (a chord = one) · WITHIN CHORD — split a chord's notes · EVERY NOTE — every note-on")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        })
        case .recorder: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // TIME (Paul 2026-09-18) — the RECORDER: record N steps/passes upstream, then loop it back
            let grain = p.recGrain ?? .passes
            let mode = p.recMode ?? .loop
            let cap = p.recCapture ?? .once
            row2({ field("GRAIN", \.recGrain) { seg(RecGrain.allCases.map(\.rawValue), sel: grain.rawValue) { i in setParam { $0.recGrain = RecGrain.allCases[i] } } } },
                 { field("LENGTH — \(grain.rawValue.lowercased())", \.recLen) { numPair(p.recLen ?? 1, 1...32) { v in setParam { $0.recLen = v } } } })
            row2({ field("ARM", \.recArm) { seg(RecArm.allCases.map(\.rawValue), sel: (p.recArm ?? .onPlay).rawValue) { i in setParam { $0.recArm = RecArm.allCases[i] } } } },
                 { field("AFTER — N", \.recArmN) { numPair(p.recArmN ?? 1, 1...32) { v in setParam { $0.recArmN = v } } } })
            field("MODE", \.recMode) { seg(RecMode.allCases.map(\.rawValue), sel: mode.rawValue) { i in setParam { $0.recMode = RecMode.allCases[i] } } }
            if mode == .freeze {
                field("FREEZE STYLE — held pad | locked loop", \.recFreeze) { seg(RecFreeze.allCases.map(\.rawValue), sel: (p.recFreeze ?? .held).rawValue) { i in setParam { $0.recFreeze = RecFreeze.allCases[i] } } }
            }
            row2({ field("MIX", \.recMix) { seg(RecMix.allCases.map(\.rawValue), sel: (p.recMix ?? .replace).rawValue) { i in setParam { $0.recMix = RecMix.allCases[i] } } } },
                 { field("CAPTURE", \.recCapture) { seg(RecCapture.allCases.map(\.rawValue), sel: cap.rawValue) { i in setParam { $0.recCapture = RecCapture.allCases[i] } } } })
            if cap == .refresh {
                field("REFRESH EVERY — M", \.recRefreshM) { numPair(p.recRefreshM ?? 1, 1...32) { v in setParam { $0.recRefreshM = v } } }
            }
            let bufN = p.recEvents?.count ?? 0
            HStack {
                Text(bufN > 0 ? "\(bufN) events recorded" : "empty — records on play, then loops")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                Button("CLEAR") { setParam { $0.recEvents = nil } }
                    .font(.system(size: 11, weight: .heavy, design: .monospaced)).disabled(bufN == 0)
            }
        })
        case .clock: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // TIME (Paul 2026-09-26) — CLOCK: a
            // hand-authored grid — variable steps, each a mutually exclusive speed, with a GLIDE row on the same
            // grid (Paul's own final spec — FIXED/WAVE mode alternatives were built, then removed entire the same
            // day: this grid is the whole feature, not one of several). Placed before a driver (ARP/RIFF/RATCHET)
            // this genuinely retimes its ticks; placed before a fold consumer (RATCHET/DEST/VELOCITY/TUTTI/MOD) it
            // reshapes that stage's own math. Empty/CARRY columns hold the last explicit ratio.
            let steps = max(1, min(32, p.clockDrawnSteps ?? 8))
            let picks = p.clockDrawnRatios ?? []
            let glideArr = p.clockDrawnGlide ?? []
            // RATE REMOVED (Paul 2026-09-26: "what's the point of rate when we have a speed-per-step grid?"): a
            // clock column IS one grid column now — its width is always `gridStepBeats` (S), the SAME clock every
            // other matrix/lane in this app already extrapolates its own playhead from. That also fixes the
            // second complaint in the same message — the matrix used to light the PLAIN grid column (no clock
            // passed to stateMatrixRadio at all) while the engine read a SEPARATE, independently-dialled rate, so
            // the highlight and the audible column could disagree entirely. Now they're the same clock by
            // construction: `rate: gridStepBeats` below is exactly what the engine uses (`rateBeats: S` in Router).
            let S = Swift.max(0.0001, gridStepBeats)
            let bar = 8.0 * S
            let period = (p.clockSpanN ?? 8) > 0 ? Swift.max(0.03125, spanLadderBeats(p.clockSpanN ?? 8, S: S, row: bar)) : 0
            let clockLive = clockPlaying ? StateMatrixClock(anchor: beatAnchor, anchorAt: beatAnchorAt, tempo: tempo,
                                                            rate: S, steps: steps, rotate: 0, span: period) : nil
            field("STEPS — the grid's own length", \.clockDrawnSteps) {
                numPair(steps, 1...32) { v in setParam { $0.clockDrawnSteps = v } } }
            // SPEED PER STEP + GLIDE — ONE grid (Paul 2026-09-26: "the GLIDE option should be part of the same grid
            // control so it all lines up"): GLIDE used to be a separately-laid-out toggleLane below the matrix,
            // full-width with no header column, so its cells didn't align with the matrix's (offset by the 64pt
            // header label) — a real geometry mismatch, not just a stylistic one. It's now `stateMatrixRadio`'s
            // own extra row, sharing the exact column width/spacing AND the same live-column highlight.
            heroField("SPEED PER STEP — tap a rung; the top row (···) CARRIES the previous step's speed forward") {
                stateMatrixRadio(Array((-1...8)), steps: steps, clock: clockLive,
                    header: { opt in AnyView(Text(opt < 0 ? "···" : clockRatioLabels[opt]).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))) },
                    extraRowHeader: AnyView(Text("GLIDE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))),
                    extraRowCell: { step, live, date in
                        let on = step < glideArr.count && glideArr[step]
                        return AnyView(
                            RoundedRectangle(cornerRadius: 4).fill(on ? accent.opacity(0.85) : Color.white.opacity(0.06))
                                .frame(maxWidth: .infinity).frame(height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(on ? 0.9 : 0.12), lineWidth: on ? 1.5 : 1))
                                .overlay { if on { Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .black)).foregroundColor(.black) } }
                                .overlay { pulseGlowOverlay(live && on, date) }   // Paul 2026-09-28: only the SELECTED cell animates
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    setParam {
                                        var arr = $0.clockDrawnGlide ?? Array(repeating: false, count: steps)
                                        while arr.count <= step { arr.append(false) }
                                        arr[step].toggle()
                                        $0.clockDrawnGlide = arr
                                    }
                                }
                        )
                    },
                    selected: { s in s < picks.count ? picks[s] : -1 },
                    set: { s, opt in setParam {
                        var arr = $0.clockDrawnRatios ?? Array(repeating: -1, count: steps)
                        while arr.count <= s { arr.append(-1) }
                        arr[s] = opt
                        $0.clockDrawnRatios = arr
                    } })
            }
            Text("GLIDE (bottom row): this step ramps FROM the previous step's speed TO its own, instead of snapping.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            frameSpan(p.clockSpanN ?? 8, free: true) { v in setParam { $0.clockSpanN = v } }
            let resolved = clockDrawnResolveRatios(picks, steps: steps)
            let drift = clockDrawnDriftPerLap(resolved, glide: glideArr, steps: steps, rateBeats: S)
            Text(abs(drift) < 0.001 ? "This grid lands back in time every lap — no drift." :
                 "This grid drifts \(drift > 0 ? "ahead" : "behind") by \(String(format: "%.2f", abs(drift))) beats every lap against the transport.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Everything AFTER this stage in the chain ticks to its time; everything before keeps the part's. Position is meaning.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        })
        case .killStep: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // TIME (Paul 2026-09-26, sibling
            // to CLOCK; MUTE/PAUSE added 2026-09-27) — a row of per-step MODES with its own RATE + SPAN. DROP
            // (today's original "disabled") is removed from everything downstream's timeline entirely — the
            // surviving steps compact + repeat to refill the pass (4-of-8 ON/DROP plays the first half twice). MUTE
            // keeps the downstream clock advancing through it normally — only its sound is suppressed (a per-note
            // fold, not a timing change). PAUSE freezes the downstream clock at its current value for PAUSE LEN
            // extra steps, then resumes — a hold/breath: nothing new triggers during the freeze, whatever's already
            // sounding just rings on. Shares CLOCK's own transform plumbing (Router.killStepPhase, detected
            // alongside `.clock`) via ONE shared table (`killStepResolveTable`, Derivations.swift) — the SAME
            // function the engine resolves, so this live playhead and the audible step can't drift apart.
            let steps = max(1, min(32, p.killStepCount ?? 8))
            let modes: [KillStepMode] = {
                if let m = p.killStepMode, !m.isEmpty { var a = m; while a.count < steps { a.append(.on) }; return Array(a.prefix(steps)) }
                if let e = p.killStepEnabled, !e.isEmpty { return (0..<steps).map { i in (i < e.count ? e[i] : true) ? .on : .drop } }   // legacy migration preview
                return Array(repeating: .on, count: steps)
            }()
            let pauseLen = max(1, min(16, p.killStepPauseLen ?? 1))
            let table = killStepResolveTable(modes, pauseLen: pauseLen)
            let rate = Swift.max(0.03125, (p.killStepRate ?? .r1_8).beats)
            let bar = 8.0 * Swift.max(0.0001, gridStepBeats)
            let period = (p.killStepSpanN ?? 8) > 0 ? Swift.max(0.03125, spanLadderBeats(p.killStepSpanN ?? 8, S: rate, row: bar)) : 0
            let killLive: ((Date) -> Int?)? = clockPlaying ? { date in
                let b = beatAnchor + date.timeIntervalSince(beatAnchorAt) * tempo / 60.0
                let originBeat = period > 0 ? columnStart(b, period) : 0
                let local = killStepPhase(b, columnMap: table.columnMap, columnsPerLap: table.columnsPerLap, steps: steps, rateBeats: rate, periodBeats: period, originOverride: originBeat)
                return posMod(Int(((local - originBeat) / rate).rounded(.down)), steps)
            } : nil
            field("STEPS — the row's own length", \.killStepCount) {
                numPair(steps, 1...32) { v in setParam { $0.killStepCount = v } } }
            heroField("PER-STEP MODE — ON plays · MUTE silences it (clock still advances) · DROP is skipped (steps compact + repeat) · PAUSE freezes the clock for PAUSE LEN extra steps") {
                stateMatrixRadio(KillStepMode.allCases, steps: steps, liveColOverride: killLive,
                    header: { m in AnyView(Text(m.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))) },
                    selected: { s in s < modes.count ? modes[s] : .on },
                    set: { s, mode in setParam { var a = $0.killStepMode ?? modes; while a.count < steps { a.append(.on) }; a[s] = mode; $0.killStepMode = a; $0.killStepEnabled = nil } })
            }
            field("PAUSE LEN — extra steps a PAUSE step holds", \.killStepPauseLen) {
                numPair(pauseLen, 1...16) { v in setParam { $0.killStepPauseLen = v } } }
            field("RATE — this row's own clock", \.killStepRate) {
                seg(ArpRate.allCases.map(\.rawValue), sel: (p.killStepRate ?? .r1_8).rawValue) { i in setParam { $0.killStepRate = ArpRate.allCases[i] } } }
            frameSpan(p.killStepSpanN ?? 8, free: true) { v in setParam { $0.killStepSpanN = v } }
            let onCount = modes.filter { $0 == .on }.count
            Text(onCount == steps ? "Every step is on — a no-op, nothing skipped." :
                 "\(onCount) of \(steps) play on — \(modes.filter { $0 == .mute }.count) muted, \(modes.filter { $0 == .drop }.count) dropped (compact + repeat), \(modes.filter { $0 == .pause }.count) paused.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
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
                                        setParam { p in
                                            var arr: [Int] = p.muteSlices ?? Array(repeating: 0, count: 8)
                                            while arr.count < 8 { arr.append(0) }
                                            arr[step] ^= (1 << e)
                                            p.muteSlices = arr
                                        }
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
            // LIVE SWEEP (Paul 2026-09-28, closing the audit gap RIFF was named for): calls the SAME pure `riffStepAt`
            // the engine calls (Router.emitRiffRow) directly — not a re-derived approximation — so the lit cell and
            // the sounding step can never disagree, across all 5 non-stateful direction modes. DRUNK is the
            // exception — its true position is genuine per-cell RENDER-THREAD state (`riffDrunkPos`, Router.swift)
            // with no closed form this UI layer could extrapolate between frames (Paul confirmed the ceiling and
            // asked for it anyway): `riffDrunkPosLive` is the actual value, POLLED from the render thread at the
            // diagnostic cadence (`AudioUnitViewController`'s `editorOpen` block → `pollRiffDrunkPos`), so it jumps
            // between columns rather than sweeping — the honest cost of showing the real position instead of a
            // plausible-looking wrong one.
            let riffDirNow = p.riffDir ?? .forward
            let riffRateBeatsNow = Swift.max(0.03125, (p.riffRate ?? .r1_16).beats)
            let riffSpanBeatsNow = (p.riffSpanN ?? 0) > 0 ? spanLadderBeats(p.riffSpanN ?? 0, S: gridStepBeats, row: 8 * gridStepBeats) : 0
            let riffSeedNow = UInt64(bitPattern: Int64(p.riffDirSeed ?? 0))
            let riffLive: ((Date) -> Int?)? = clockPlaying ? (riffDirNow == .drunk
                ? { _ in (riffDrunkPosLive >= 0 && riffDrunkPosLive < steps) ? riffDrunkPosLive : nil }
                : { date in
                    let b = beatAnchor + date.timeIntervalSince(beatAnchorAt) * tempo / 60.0
                    let phase = riffSpanBeatsNow > 0 ? (b - columnStart(b, riffSpanBeatsNow)) : b
                    let raw = Int((phase / riffRateBeatsNow).rounded(.down))
                    return riffStepAt(riffDirNow, raw: raw, steps: steps, seed: riffSeedNow)
                }) : nil
            heroField("") {   // label removed (Paul 2026-09-13)
                liveClockWrap(riffLive) { liveCol, date in
                VStack(spacing: 2) {
                    playheadHeaderRow(cols: steps, liveCol: liveCol, date: date, spacing: 2, leading: 16, trailing: 30)
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
                                    .overlay { pulseGlowOverlay(s == liveCol && on, date, corner: 3) }   // Paul 2026-09-28: only the SELECTED cell animates
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
            }
            // §5 MODIFIER LANES (Paul 2026-08-26): OCT (−·0·+) · ACCENT (louder) · TIE (⌒ hold) · SLIDE (↝ 303 glide).
            let octA = p.riffOct ?? [], accA = p.riffAccent ?? [], tieA = p.riffTie ?? [], slA = p.riffSlide ?? []
            field("OCT  −·0·+") {
                liveClockWrap(riffLive) { liveCol, date in
                HStack(spacing: 2) { Color.clear.frame(width: 16, height: 14)
                    ForEach(0..<steps, id: \.self) { s in
                        let v = s < octA.count ? octA[s] : 0
                        RoundedRectangle(cornerRadius: 3).fill(v == 0 ? Color.white.opacity(0.06) : accent.opacity(0.5)).frame(maxWidth: .infinity).frame(height: 15)
                            .overlay(Text(v > 0 ? "+" : (v < 0 ? "−" : "·")).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(v == 0 ? 0.35 : 0.95)))
                            .overlay { pulseGlowOverlay(s == liveCol, date, corner: 3) }
                            .contentShape(Rectangle()).onTapGesture { setParam { var a = $0.riffOct ?? []; while a.count < steps { a.append(0) }; a[s] = a[s] >= 1 ? -1 : a[s] + 1; $0.riffOct = a } }
                    }
                    Color.clear.frame(width: 30, height: 14)
                }
                }
            }
            riffToggleLane("ACCENT", steps: steps, on: { $0 < accA.count && accA[$0] > 0 }, accent: accent, glyph: "▲", live: riffLive) { s in setParam { var a = $0.riffAccent ?? []; while a.count < steps { a.append(0) }; a[s] = a[s] > 0 ? 0 : 40; $0.riffAccent = a } }
            riffToggleLane("TIE  ⌒", steps: steps, on: { $0 < tieA.count && tieA[$0] }, accent: accent, glyph: "⌒", live: riffLive) { s in setParam { var a = $0.riffTie ?? []; while a.count < steps { a.append(false) }; a[s].toggle(); $0.riffTie = a } }
            riffToggleLane("SLIDE  ↝", steps: steps, on: { $0 < slA.count && slA[$0] }, accent: accent, glyph: "↝", live: riffLive) { s in setParam { var a = $0.riffSlide ?? []; while a.count < steps { a.append(false) }; a[s].toggle(); $0.riffSlide = a } }
            row2({ field("STEPS", \.riffSteps) { numPair(steps, 1...32) { v in setParam { $0.riffSteps = v } } } },
                 { field("VOICING", \.riffPoly) { seg(["MONO", "POLY"], sel: poly ? "POLY" : "MONO") { i in setParam { $0.riffPoly = (i == 1) } } } })
            row2({ field("WRAP — a rank past the chord", \.riffWrap) { seg(RiffWrap.allCases.map(\.rawValue), sel: (p.riffWrap ?? .fold).rawValue) { i in setParam { $0.riffWrap = RiffWrap.allCases[i] } } } },
                 { field("DIRECTION", \.riffDir) { seg(RiffDir.allCases.map(\.displayLabel), sel: (p.riffDir ?? .forward).displayLabel) { i in
                     setParam {
                         let d = RiffDir.allCases[i]; $0.riffDir = d
                         // RANDOM + DRUNK (Paul 2026-09-28): each pick rolls a FRESH persisted seed, mirroring RANDOM
                         // ONCE's own idiom above — a re-tap = re-roll; every other pick leaves the stored seed untouched.
                         if d == .random || d == .drunk { $0.riffDirSeed = Int.random(in: Int.min...Int.max) }
                     } } } })   // stencil playback order (Paul 2026-09-16, widened to 6 modes Paul 2026-09-28)
            if (p.riffDir ?? .forward) == .drunk {   // BIAS only matters for DRUNK's random walk
                bipolarSlider("BIAS \(Int((p.riffDirBias ?? 0) * 100))  (−rev · +fwd)", p.riffDirBias ?? 0) { v in setParam { $0.riffDirBias = v } }
            }
            // GATE LENGTH — the per-note length (the standard gate, which the riff already honours), with the ∿ LFO (Paul 2026-09-16).
            field("GATE LENGTH  \(Int((p.gate ?? 0.6) * 100))%", \.gate, lfo: "gate") { slider(bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1) }
            // RATE + SPAN — roomy, each on its OWN line (riff has a per-step RATE and a separate SPAN, not one DURATION — Paul 2026-09-16).
            field("RATE") { arpSpeedGrid(sel: p.riffRate ?? .r1_16) { r in setParam { $0.riffRate = r } } }
            field("SPAN") { frameSpan(p.riffSpanN ?? 0, free: true) { v in setParam { $0.riffSpanN = v } } }
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
        case .chords: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // HARMONY — a held note triggers the diatonic chord for the current degree; the KEY comes from a SCALE door
            let mode = p.chordsMode ?? .pattern
            let refIdx = p.chordsScaleRef ?? -1
            let letters = ["A", "B", "C", "D"]
            heroField("MODE") { seg(["PATTERN", "FOLLOW", "WALK"], sel: mode.rawValue.uppercased()) { i in setParam { $0.chordsMode = ChordsMode.allCases[i] } } }
            // SCALE FROM (Paul 2026-09-01): the KEY is read from a RECEIVER set to SCALE — point at it here (none →
            // C major). The cell's OWN input stays the TRIGGER (FOLLOW names the degree from the note you play);
            // this door only sets the key. Styled + labelled IDENTICALLY to the main MIDI-IN toggles (Paul
            // 2026-09-29): the shared `ioChip` + `doorKeyLabels`/`noteClassLabel`. No separate "—" option any more —
            // tapping the already-selected door deselects it (the same "none" the old 5-way seg control offered).
            heroField("SCALE FROM") {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        ioChip(doorKeyLabels[i] ?? noteClassLabel(avoidInputNotes[i]) ?? "no input", on: refIdx == i, accent: receiverGrey(i)) {
                            setParam { $0.chordsScaleRef = (refIdx == i) ? nil : i }
                        }
                    }
                }
            }
            // MODE body — only PATTERN authors a degree lane; FOLLOW/WALK derive the degrees, so they show a plain-language tell.
            let steps = max(1, min(16, p.chordsSteps ?? 8))
            let rateNames = StepRate.allCases.map { $0.rawValue }
            if mode == .pattern {
                // STEPS (pattern length 1…16) · RATE (the progression clock — a chord per rate-tick, not per grid column).
                field("STEPS · RATE") { HStack(spacing: 6) {
                    numPair(steps, 1...16) { n in setParam { $0.chordsSteps = n } }
                    seg(rateNames, sel: (p.chordsRate ?? .r1_1).rawValue) { i in setParam { $0.chordsRate = StepRate.allCases[i] } }
                } }
                // LIVE SWEEP (Paul 2026-09-28): mirrors chordSeqNotes exactly — "a chord per rate-tick, not per grid
                // column" (the comment above is the engine's own words) — free-running (no SPAN concept here at all).
                let chordsRateBeatsNow = Swift.max(0.03125, (p.chordsRate ?? .r1_1).beats)
                let chordsClock = clockPlaying
                    ? StateMatrixClock(anchor: beatAnchor, anchorAt: beatAnchorAt, tempo: tempo, rate: chordsRateBeatsNow, steps: steps, rotate: p.chordsRotate ?? 0, span: 0)
                    : nil
                // THE DEGREE MATRIX (width = STEPS): rows I…vii + REST · radio-per-column. Headers use a major reference for
                // POSITION (the real quality follows the SCALE-FROM door's scale at play time — the editor can't see it).
                stateMatrixRadio([0, 1, 2, 3, 4, 5, 6, 7], steps: steps, clock: chordsClock,
                    header: { (opt: Int) in AnyView(Text(opt == 7 ? "REST" : degreeLabel(degree: opt, scaleTones: ScaleType.major.intervals)).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))) },
                    onRotate: { d in setParam { $0.chordsRotate = ((($0.chordsRotate ?? 0) + d) % steps + steps) % steps } },
                    // BRIGHT = an AUTHORED degree/REST; a carry/unset column lights NOTHING bright (BUGFIX Paul 2026-09-15: it
                    // used to falsely light I). FAINT (`dim`) = the chord the column actually CARRIES → the matrix matches the
                    // audio when the length is extended past the authored columns. Both from the pure `chordsMatrixCell`.
                    dim: { c in chordsMatrixCell(p.chordsDegrees ?? [0, 0, 5, 5, 3, 3, 4, 4], step: c, steps: steps).faint },
                    selected: { c in chordsMatrixCell(p.chordsDegrees ?? [0, 0, 5, 5, 3, 3, 4, 4], step: c, steps: steps).bright ?? -1 },
                    set: { c, opt in setParam { var a = $0.chordsDegrees ?? [0, 0, 5, 5, 3, 3, 4, 4]; while a.count < steps { a.append(-1) }; if c < steps { a[c] = opt }; $0.chordsDegrees = a } })
            } else if mode == .follow {
                Text("FOLLOW — the note you PLAY names the degree, in the SCALE-FROM key. Play the 5th → the V chord; the 2nd → ii. Change the note, the chord follows.").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {   // walk
                field("RATE") { seg(rateNames, sel: (p.chordsRate ?? .r1_1).rawValue) { i in setParam { $0.chordsRate = StepRate.allCases[i] } } }   // how fast the walk advances
                field("WALK") { seg(["⟳ RE-ROLL"], sel: "") { _ in setParam { $0.chordsWalkSeed = ($0.chordsWalkSeed ?? 0) &+ 1 } } }
                Text("WALK — an evolving progression from one held trigger: a gravity wander through the SCALE-FROM key that leans home, advancing at RATE. RE-ROLL for a different wander.").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            field("VOICING") { seg(["TRIAD", "7TH", "ADD9"], sel: (p.chordsVoicing ?? .triad) == .triad ? "TRIAD" : ((p.chordsVoicing ?? .triad) == .seventh ? "7TH" : "ADD9")) { i in setParam { $0.chordsVoicing = [ChordVoicing.triad, .seventh, .add9][i] } } }
            field("SPREAD") { seg(["CLOSE", "OPEN"], sel: (p.chordsSpread ?? .close) == .close ? "CLOSE" : "OPEN") { i in setParam { $0.chordsSpread = i == 0 ? .close : .open } } }
            Text("Point SCALE FROM at a receiver set to SCALE — that door's key governs the chords. Follow with STRUM / ARP / DRONE.").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        })
        case .avoid: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // FILTER — compares your notes against another source and keeps clear of it (AVOID) or locks onto it (LOCK)
            // LISTEN-TO source: INPUT = another MIDI input's live notes (.door) · EVERYTHING = every note now playing (.sounding).
            // (KEY/WIRE removed from the UI per Paul 2026-08-31 — the key lives on a scale-channel INPUT; point at it.)
            let refIsInput = (p.avoidRefKind ?? .sounding) == .door
            let md = p.avoidMode ?? .avoid
            let idx = max(0, min(3, p.avoidRefIndex ?? 0))
            let letters = ["A", "B", "C", "D"]
            let clashSemis = md == .avoid ? avoidClashSemis(p.avoidWhat) : 0
            let avoidRed = Color(red: 1.0, green: 0.38, blue: 0.38)     // AVOIDED (input) · DROPPED (output)
            let avoidGreen = Color(red: 0.38, green: 0.85, blue: 0.5)   // LOCKED-TO (input) · PLAYING (output)
            let refTint = md == .lock ? avoidGreen : avoidRed           // input reference: green when locking to it, red when avoiding it
            heroField("LISTEN TO") { seg(["INPUT", "EVERYTHING"], sel: refIsInput ? "INPUT" : "EVERYTHING") { i in setParam { $0.avoidRefKind = (i == 0 ? .door : .sounding) } } }
            if refIsInput {
                // Styled + labelled IDENTICALLY to the main MIDI-IN toggles (Paul 2026-09-29): the shared `ioChip` +
                // `doorKeyLabels`/`noteClassLabel`.
                field("WHICH INPUT", \.avoidRefIndex) {
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { i in
                            ioChip(doorKeyLabels[i] ?? noteClassLabel(avoidInputNotes[i]) ?? "no input", on: idx == i, accent: receiverGrey(i)) {
                                setParam { $0.avoidRefIndex = i }
                            }
                        }
                    }
                }
            }
            field("MODE", \.avoidMode) { seg(["AVOID", "LOCK"], sel: md == .lock ? "LOCK" : "AVOID") { i in setParam { $0.avoidMode = (i == 0 ? .avoid : .lock) } } }
            if md == .avoid {   // how wide the avoided zone is: just the exact notes, or also the semitones next to them (the ones that clash)
                field("ALSO DODGE", \.avoidWhat) { seg(["NONE", "±1 SEMI", "±2 SEMIS"], sel: [AvoidWhat.same: "NONE", .clash: "±1 SEMI", .clash2: "±2 SEMIS"][p.avoidWhat ?? .same] ?? "NONE") { i in setParam { $0.avoidWhat = [AvoidWhat.same, .clash, .clash2][i] } } }
            }
            field("IF BLOCKED", \.avoidAction) { seg(["DROP", "MOVE"], sel: (p.avoidAction ?? .remove) == .move ? "MOVE" : "DROP") { i in setParam { $0.avoidAction = (i == 0 ? .remove : .move) } } }
            // THE PIANO — octave-agnostic (the filter works by pitch class), so two octaves lit by class. Top = the notes
            // you're listening to (the reference); bottom = the PREDICTED output = this chain's input notes with the rule
            // applied (NOT a board-wide feed — so "nothing to lock to" reads as empty, and the result stays in the input's key).
            let pd = avoidPianoData(refIsInput: refIsInput, idx: idx, clashSemis: clashSemis, lock: md == .lock, move: (p.avoidAction ?? .remove) == .move)
            let srcName = refIsInput ? "INPUT \(letters[idx])" : "everything else"
            let inLabel = md == .lock ? "INPUT — playing (white) · lock to \(srcName) (green)" : "INPUT — playing (white) · avoid \(srcName) (red)"
            let dropped = pd.chainIn.subtracting(pd.out)   // the played-in notes that don't make it out (removed, or the from-side of a MOVE)
            VStack(alignment: .leading, spacing: 5) {
                // INPUT piano: the avoid/lock reference zone (red/green + clash halo), with a WHITE band on the notes you're playing in.
                avoidKeyboard(inLabel, tint: { pc in
                    if pd.ref.contains(pc) { return refTint.opacity(0.9) }
                    if pd.clash.contains(pc) { return refTint.opacity(0.34) }   // the widened clash halo
                    return nil
                }, mark: { pc in pd.chainIn.contains(pc) })
                // OUTPUT piano: GREEN = what plays · RED = what's dropped (the avoided/removed notes).
                avoidKeyboard("OUTPUT — playing (green) · dropped (red)", tint: { pc in
                    if pd.out.contains(pc) { return avoidGreen.opacity(0.92) }
                    if dropped.contains(pc) { return avoidRed.opacity(0.85) }
                    return nil
                })
            }
            Text(avoidBlurb(input: refIsInput, letter: letters[idx], lock: md == .lock, clash: clashSemis, move: (p.avoidAction ?? .remove) == .move))
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        })
        case .euclidMask: AnyView(VStack(alignment: .leading, spacing: rowSpacing) {   // DYNAMICS (Paul 2026-09-27): a
            // downstream FOLD stage — gates ANY driver's notes with a K-of-N Bjorklund pattern (GAPS · ROTATE ·
            // CHORD-stab). WALK/WAIT is dropped here (it needs the driver's own phase-index, which a downstream fold
            // can't reach).
            let mN = max(2, min(16, p.maskN ?? 8))
            let mK = max(1, min(mN, p.maskK ?? mN))
            field("HITS  ◀K▶ of ◀N▶  (K < N gates the rhythm; K = N passes through)", \.maskK, lfo: "maskK") {   // ∿ LFO modulates the HIT COUNT K (density)
                HStack(spacing: 10) {
                    numPair(mK, 1...mN) { v in setParam { $0.maskK = v; if $0.maskN == nil { $0.maskN = mN } } }
                    Text("of").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    numPair(mN, 2...16) { v in setParam { $0.maskN = v; if let k = $0.maskK, k > v { $0.maskK = v } } }
                }
            }
            // GAPS/ROTATE/CHORD are always shown now (Paul 2026-09-29: they used to be hidden behind `mK < mN`,
            // a discoverability trap — a freshly-added slot starts at K=N/fully-open, so there was nothing to
            // tap toward "chord mode" until HITS had already been lowered). K = N still means "no gaps exist,
            // so none of this row has anything to act on yet" — said plainly instead of just disappearing.
            if mK == mN {
                Text("K = N — every step hits, so GAPS/ROTATE/CHORD have nothing to act on yet. Lower HITS below N to open gaps.")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            row2({ field("GAPS", \.maskGap) { seg(["REST", "TIE", "CHORD"], sel: (p.maskGap ?? .rest).rawValue) { i in setParam { $0.maskGap = [ArpMaskGap.rest, .tie, .chord][i] } } } },
                 { field("ROTATE", \.maskRotate, lfo: "maskRotate") { numPair(p.maskRotate ?? 0, 0...(mN - 1), wrap: true) { v in setParam { $0.maskRotate = v } } } })
            // INVERT + CHANCE (Paul 2026-09-28): INVERT plays the N−K rests instead (mirrors EUCLID's own
            // toggle); CHANCE thins the deterministic skeleton with a per-hit coin-flip (can only drop a hit,
            // never add one) — 100% = today's exact behaviour.
            row2({ field("PATTERN", \.maskInvert) { seg(["NORMAL", "INVERT"], sel: (p.maskInvert ?? false) ? "INVERT" : "NORMAL") { i in setParam { $0.maskInvert = (i == 1) } } } },
                 { field("CHANCE  \(Int((p.maskChance ?? 1) * 100))%", \.maskChance) { slider(bind(p.maskChance ?? 1) { v in setParam { $0.maskChance = v } }, in: 0...1) } })
            if (p.maskGap ?? .rest) == .chord {   // GAPS = CHORD gap-stab controls, mirroring the ARP mask's own (Docs/PLAN-param-lfo.md)
                row2({ field("CHORD OCT", \.maskChordOct, lfo: "maskChordOct") { numPair(p.maskChordOct ?? 0, -2...2, format: { $0 > 0 ? "+\($0)" : "\($0)" }) { v in setParam { $0.maskChordOct = v } } } },
                     { field("CHORD LEN  \(Int((p.maskChordGate ?? 0.6) * 100))%", \.maskChordGate, lfo: "maskChordGate") { slider(bind(p.maskChordGate ?? 0.6) { v in setParam { $0.maskChordGate = v } }, in: 0.05...1) } })
                field("CHORD VEL  \(Int((p.maskChordVel ?? 1) * 100))%", \.maskChordVel) { slider(bind(p.maskChordVel ?? 1) { v in setParam { $0.maskChordVel = v } }, in: 0...1) }
                // CHORD PICK (Paul 2026-09-28): which note(s) of the composed chord a gap strikes. ALL = today's
                // whole-chord stab; BOT2/TOP2 strike the two lowest/highest tones.
                field("CHORD PICK", \.maskChordPick) { seg(MaskChordPick.allCases.map(\.rawValue), sel: (p.maskChordPick ?? .all).rawValue) { i in setParam { $0.maskChordPick = MaskChordPick.allCases[i] } } }
            }
            // SPAN (Paul 2026-09-28): re-anchor the K-of-N pattern to ordinal 0 every N notes — the same universal
            // span-ladder model every other pattern processor (RIFF/EUCLID/RATCHET PATTERN/KILL STEP/CLOCK) already has.
            frameSpan(p.maskSpanN ?? 0, free: true) { v in setParam { $0.maskSpanN = v } }
            // FILL (Paul 2026-09-28): every Nth pass overrides the mask entirely — everything plays (a turnaround/
            // release), ignoring GATE/INVERT/CHANCE for that one pass. 0 = off.
            field("FILL — every ▶N◀ passes plays every step (0 = off)", \.maskFillEvery) {
                numPair(p.maskFillEvery ?? 0, 0...16) { v in setParam { $0.maskFillEvery = v } } }
            // ACCENT LAYER (Paul 2026-09-28): a SECOND, independent K-of-N pattern (own window/rotate) that boosts
            // velocity on its own hits — the classic two-euclid technique. K = N (default) leaves it off.
            let aN = max(2, min(16, p.maskAccentN ?? 8))
            let aK = max(1, min(aN, p.maskAccentK ?? aN))
            heroField("ACCENT LAYER — a second pattern that boosts velocity on its own hits") {
                HStack(spacing: 10) {
                    numPair(aK, 1...aN) { v in setParam { $0.maskAccentK = v; if $0.maskAccentN == nil { $0.maskAccentN = aN } } }
                    Text("of").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    numPair(aN, 2...16) { v in setParam { $0.maskAccentN = v; if let k = $0.maskAccentK, k > v { $0.maskAccentK = v } } }
                }
            }
            if aK < aN {
                row2({ field("ACCENT ROTATE", \.maskAccentRotate) { numPair(p.maskAccentRotate ?? 0, 0...(aN - 1), wrap: true) { v in setParam { $0.maskAccentRotate = v } } } },
                     { field("ACCENT AMOUNT +\(p.maskAccentAmount ?? 20)", \.maskAccentAmount) { numPair(p.maskAccentAmount ?? 20, 0...60) { v in setParam { $0.maskAccentAmount = v } } } })
            }
            Text("Downstream of a driver only — gates its notes by a K-of-N euclidean pattern. No driver upstream, no effect.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        })
        }
    }

    // AVOID/LOCK editor helpers (Paul 2026-08-31 — clearer terminology + the illustration piano).
    private func avoidClashSemis(_ w: AvoidWhat?) -> Int { switch w ?? .same { case .same: return 0; case .clash: return 1; case .clash2: return 2 } }
    // Widen a set of pitch classes to its ±1…semis neighbours (mirrors the engine's widenClashMask, on a Set).
    private func avoidWidenClasses(_ classes: Set<Int>, semis: Int) -> Set<Int> {
        guard semis > 0 else { return [] }
        var out = Set<Int>()
        for pc in classes { for d in 1...semis { out.insert((pc + d) % 12); out.insert((pc + 12 - (d % 12)) % 12) } }
        return out.subtracting(classes)   // the halo = only the NEW neighbours (the exact notes already read at full tint)
    }
    // The PREDICTED output pitch classes = this chain's input notes with the AVOID/LOCK rule applied. Mirrors keyFilterNote
    // (Derivations) exactly, on pitch classes: LOCK keeps only the reference (empty ⇒ nothing) · AVOID drops the blocked set
    // (empty ⇒ everything) · MOVE snaps a blocked note to the nearest legal class (down ties before up), else it's dropped.
    private func avoidPredict(_ chainIn: Set<Int>, blocked: Set<Int>, lock: Bool, refOnly: Set<Int>, move: Bool) -> Set<Int> {
        let empty = lock ? refOnly.isEmpty : blocked.isEmpty
        let allowed: (Int) -> Bool = lock ? { refOnly.contains($0) } : { !blocked.contains($0) }
        // MOVE lands ONLY on: LOCK → the referenced key · AVOID → the input scale's surviving notes (never a chromatic note outside it)
        let snapTo: Set<Int> = lock ? refOnly : chainIn.filter { !blocked.contains($0) }
        var out = Set<Int>()
        for pc in chainIn {
            if empty { if !lock { out.insert(pc) }; continue }   // refMask==0: LOCK admits nothing · AVOID excludes nothing
            if allowed(pc) { out.insert(pc) }
            else if move, !snapTo.isEmpty, let s = avoidSnapClass(pc, { snapTo.contains($0) }) { out.insert(s) }
        }
        return out
    }
    private func avoidSnapClass(_ pc: Int, _ allowed: (Int) -> Bool) -> Int? {
        for d in 1...6 { let down = ((pc - d) % 12 + 12) % 12; if allowed(down) { return down }; let up = (pc + d) % 12; if allowed(up) { return up } }
        return nil
    }
    // The AVOID illustration pianos' data, computed OUTSIDE the ViewBuilder (keeps typeParams' type-check cheap): the
    // reference classes (what's avoided/locked-to) · the clash halo · the predicted output classes.
    private func avoidPianoData(refIsInput: Bool, idx: Int, clashSemis: Int, lock: Bool, move: Bool) -> (ref: Set<Int>, clash: Set<Int>, chainIn: Set<Int>, out: Set<Int>) {
        func classesOf(_ d: Int) -> Set<Int> {
            guard d >= 0, d < avoidInputNotes.count else { return [] }
            return Set(avoidInputNotes[d].map { (($0 % 12) + 12) % 12 })
        }
        var ref = Set<Int>()
        if refIsInput { ref = classesOf(idx) }
        else { for d in 0..<min(4, avoidInputNotes.count) where d != avoidChainInputDoor { ref.formUnion(classesOf(d)) } }   // EVERYTHING = every OTHER input (never this chain's own — Paul 2026-08-31)
        let clash = clashSemis > 0 ? avoidWidenClasses(ref, semis: clashSemis) : []
        let blocked = ref.union(clash)
        let chainIn = classesOf(avoidChainInputDoor)                          // the notes actually feeding this chain (a scale door reports its pool) = "what's being played" in
        let out = avoidPredict(chainIn, blocked: blocked, lock: lock, refOnly: ref, move: move)
        return (ref, clash, chainIn, out)
    }
    // A compact TWO-OCTAVE piano for the AVOID illustration (the filter is octave-agnostic, so two octaves say it all):
    // `tint(pitchClass 0-11)` fills a lit key; `mark(pitchClass)` = "being played" (a bright band). Real keyboard, C4..C6.
    private func avoidKeyboard(_ label: String, tint: @escaping (Int) -> Color?, mark: ((Int) -> Bool)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.secondary)
            pianoKeysCanvas(lo: 60, hi: 84, tint: { midi in tint((((midi % 12) + 12) % 12)) },
                            mark: mark.map { m in { midi in m((((midi % 12) + 12) % 12)) } })   // C4..C6 = 2 octaves, by pitch class
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.28)))
        }
    }
    // The plain-language one-liner under the AVOID/LOCK controls.
    private func avoidBlurb(input: Bool, letter: String, lock: Bool, clash: Int, move: Bool) -> String {
        let src = input ? "INPUT \(letter)" : "everything else playing"
        // MOVE snaps to the nearest surviving note in the INPUT scale (never a chromatic note outside it); DROP just removes.
        let fix = move ? "moved to the nearest note still in the scale" : "dropped"
        if lock { return "LOCK — plays only the notes \(src) is playing. Point INPUT at a scale channel to stay in its key; anything else is \(fix)." }
        let sphere = clash == 0 ? "the exact notes \(src) plays" : (clash == 1 ? "\(src)'s notes and the semitone either side (the ones that clash)" : "\(src)'s notes and the two semitones either side")
        return "AVOID — your notes stay clear of \(sphere); any that land there are \(fix)."
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

    // PULSE GLOW (Paul 2026-09-28): the live-column indicator across every matrix/lane in this file — a soft white
    // bloom that breathes, replacing the old static top-edge line + background-opacity bump. ALWAYS plain white,
    // never a second hue, so it reads consistently over whichever colour this processor's own cells happen to be
    // (accent varies per machine) — the shared constraint the redesign review was built around. `date` comes from
    // the caller's OWN already-running TimelineView (stateMatrixRadio/sliderLane/toggleLane/riffToggleLane, or
    // RIFF's bespoke matrix) so every lit cell in one grid breathes in lockstep off ONE clock, not N independent ones.
    private func pulseGlowLevel(_ date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.6) / 0.6
        return 0.55 + 0.45 * (0.5 - 0.5 * cos(2 * .pi * t))   // smooth 0.55↔1.0 breathe, ~1.67 Hz — independent of tempo
    }
    @ViewBuilder private func pulseGlowOverlay(_ active: Bool, _ date: Date, corner: CGFloat = 4) -> some View {
        if active {
            let lvl = pulseGlowLevel(date)
            RoundedRectangle(cornerRadius: corner)
                .stroke(Color.white.opacity(lvl), lineWidth: 1.75)
                .shadow(color: Color.white.opacity(0.85 * lvl), radius: 6)
                .shadow(color: Color.white.opacity(0.6 * lvl), radius: 6)
        }
    }
    // ONE formula for "which column is live right now" from a StateMatrixClock — shared by stateMatrixRadio,
    // sliderLane, and any bespoke `live:`/`liveColOverride:` closure that wants to derive from the same clock shape
    // (e.g. VELOCITY's BYPASS toggleLane, built from the identical clock as its own velocity sliderLane) — so two
    // widgets fed the same clock can never disagree by having hand-duplicated the arithmetic twice.
    private func liveCol(from c: StateMatrixClock?, at date: Date) -> Int? {
        guard let c, c.steps > 0 else { return nil }
        let b = c.anchor + date.timeIntervalSince(c.anchorAt) * c.tempo / 60.0
        let localBeat = c.span > 0 ? (b - columnStart(b, c.span)) : b
        return (((Int((localBeat / Swift.max(0.0001, c.rate)).rounded(.down)) + c.rotate) % c.steps) + c.steps) % c.steps
    }
    // COLUMN-HEADER PLAYHEAD (Paul 2026-09-28: "only the selected cell should animate, not the entire column... I
    // also want a playhead on the header of the column"): a small marker in a thin strip ABOVE the grid, at the
    // live column — separate from the per-cell glow (which now marks only the ONE selected/sounding cell, so a
    // live column with nothing selected there, or a tall multi-row matrix, still reads clearly as sweeping).
    // `leading`/`trailing` mirror whatever gutter the caller's own rows reserve (the row-header width, RIFF's
    // trailing SET button…) so the marker's columns line up with the real cells exactly — the alignment lesson
    // CLOCK's GLIDE row already learned. Snaps to `liveCol` exactly, no fractional glide: RANDOM/DRUNK-class jumps
    // have no meaningful in-between position to interpolate through, so every direction/mode gets the same honest,
    // discrete motion (the same reasoning behind `pulseGlowLevel` being an independent breathe, not beat-synced).
    @ViewBuilder private func playheadHeaderRow(cols: Int, liveCol: Int, date: Date, spacing: CGFloat = 3, leading: CGFloat, trailing: CGFloat = 0) -> some View {
        HStack(spacing: spacing) {
            Color.clear.frame(width: leading, height: 11)
            ForEach(0..<cols, id: \.self) { step in
                ZStack {
                    if step == liveCol {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(pulseGlowLevel(date)))
                            .shadow(color: Color.white.opacity(0.8), radius: 3)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 11)
            }
            if trailing > 0 { Color.clear.frame(width: trailing, height: 11) }
        }
    }
    // For a raw/bespoke grid (no stateMatrixRadio/sliderLane underneath, e.g. RIFF's rank matrix) that has its own
    // live-column function: runs it in a TimelineView and hands the body (liveCol, date) — -1/Date() when `live` is
    // nil, so `s == liveCol` is simply always false and nothing pulses. Avoids duplicating the grid body per-branch.
    @ViewBuilder private func liveClockWrap<C: View>(_ live: ((Date) -> Int?)?, @ViewBuilder _ content: @escaping (Int, Date) -> C) -> some View {
        if let live {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in content(live(tl.date) ?? -1, tl.date) }
        } else {
            content(-1, Date())
        }
    }

    /// THE STATE MATRIX (Paul 2026-08-22): rows = options · columns = 8 steps · RADIO-PER-COLUMN (exactly one lit per
    /// step). Retires pick-then-paint — every touch responds instantly (tap a cell = that step takes that state, no
    /// brush, no dead first touch). Row headers (left edge) carry the option's glyph + name — permanent and positional;
    /// the whole pattern reads as geometry. One reusable widget for LENGTH · RATCHET PATTERN · TUTTI PATTERN · … .
    @ViewBuilder private func stateMatrixRadio<Opt: Hashable>(
        _ options: [Opt], steps: Int = 8, clock: StateMatrixClock? = nil,
        // BESPOKE LIVE COLUMN (Paul 2026-09-27, KILL STEP's MUTE/PAUSE rework): some processors' true live column
        // ISN'T a simple rotate-clock (`StateMatrixClock`'s own fixed `floor(beat/rate) mod steps` math) — KILL
        // STEP's own playhead must call `killStepPhase` itself (the skip/repeat/freeze table), or the lit cell would
        // drift from what actually plays, same lesson `clock:` itself exists for. Mirrors `toggleLane`'s own `live:`
        // shape exactly: a per-frame closure, re-invoked from inside this function's OWN TimelineView. nil (every
        // other caller) ⇒ falls through to `clock`/`gridClock` unchanged.
        liveColOverride: ((Date) -> Int?)? = nil,
        header: @escaping (Opt) -> AnyView, eFill: Bool = false, onRotate: ((Int) -> Void)? = nil,
        dim: ((Int) -> Opt?)? = nil,   // optional FAINT layer (Paul 2026-09-15): a column with no bright `selected` cell can show a dimmer cell — e.g. CHORDS shows the chord an empty column CARRIES, so the matrix matches the audio. nil ⇒ unchanged.
        // EXTRA ROW (Paul 2026-09-26, CLOCK's GLIDE): an optional row sharing this SAME per-column geometry AND the
        // SAME live-column highlight — for a control that isn't a mutually-exclusive "pick one option" pick (like
        // a per-column on/off toggle) but still needs to visually READ as part of the one grid, not a separately-
        // laid-out control underneath that may not line up. `extraRowCell(step, live)` draws that column.
        extraRowHeader: AnyView? = nil, extraRowCell: ((Int, Bool, Date) -> AnyView)? = nil,
        selected: @escaping (Int) -> Opt, set: @escaping (Int, Opt) -> Void
    ) -> some View {
        let cols = max(1, min(32, steps))   // variable matrix width (CHORDS ≤16; RATCHET PATTERN up to 32 — Paul 2026-09-07); other callers default to 8
        // The grid, parameterised on which column is lit + the current Date (Paul 2026-09-28: PULSE GLOW breathes off
        // this shared timestamp, so every lit cell in the grid pulses in lockstep instead of each running its own
        // clock). RATCHET PATTERN drives `liveCol` from its OWN clock (extrapolated, below); every other caller lights
        // the global grid column (`liveStep`). A `let` closure (a `func` isn't legal in a @ViewBuilder body) → AnyView
        // so both branches type-match.
        let makeGrid: (Int, Date) -> AnyView = { liveCol, date in AnyView(
            VStack(spacing: 3) {
                playheadHeaderRow(cols: cols, liveCol: liveCol, date: date, leading: 64)
                ForEach(Array(options.enumerated()), id: \.offset) { (_, opt) in
                    HStack(spacing: 3) {
                        if eFill { EBrushButton(steps: cols, accent: accent) { pat in for s in 0..<cols { set(s, pat[s] ? opt : options[0]) } } }   // §5 E-BRUSH: fill this state on K columns, rest = the default (options[0])
                        header(opt).frame(width: 64, alignment: .leading)
                        ForEach(0..<cols, id: \.self) { step in
                            let on = selected(step) == opt
                            let dimOn: Bool = { guard !on, let d = dim, let dv = d(step) else { return false }; return dv == opt }()   // FAINT: this column's carried/implied state
                            let live = step == liveCol                        // PLAYHEAD (idea 15): the live column (ratchet's own clock, or the global grid)
                            RoundedRectangle(cornerRadius: 4).fill(on ? accent : (dimOn ? accent.opacity(0.28) : Color.white.opacity(0.06)))
                                .frame(maxWidth: .infinity).frame(height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(on ? 0.9 : (dimOn ? 0.4 : 0.12)), lineWidth: on ? 1.5 : 1))
                                .overlay { pulseGlowOverlay(live && on, date) }   // Paul 2026-09-28: only the SELECTED cell animates, not the whole live column
                                .contentShape(Rectangle()).onTapGesture { set(step, opt) }
                        }
                    }
                }
                if let h = extraRowHeader, let cell = extraRowCell {
                    HStack(spacing: 3) {
                        h.frame(width: 64, alignment: .leading)
                        ForEach(0..<cols, id: \.self) { step in cell(step, step == liveCol, date) }
                    }
                }
            }
        ) }
        // RATCHET PATTERN own-clock playhead: EXTRAPOLATE the beat every animation frame (the ~4 Hz poll aliases a fast rate —
        // a 1/8 sweep read at 4 Hz collapses to a 1↔5 jump). col = floor(beat ÷ RATE) mod STEPS (+ ROTATE). No clock → liveStep.
        let grid = Group {
            if let ov = liveColOverride {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in makeGrid(ov(tl.date) ?? -1, tl.date) }
            } else if let c = clock ?? gridClock {   // bespoke ratchet clock, else the DEFAULT grid-column clock (Paul 2026-09-11) — both extrapolated per frame so NO per-step page re-render
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    makeGrid(liveCol(from: c, at: tl.date) ?? -1, tl.date)
                }
            } else {
                makeGrid(liveStep, Date())   // stopped (no clock) → liveStep is -1 from the caller → no playhead (and nothing to pulse)
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
    private func sliderLane(_ steps: [Int], count: Int = 8, max maxV: Int = 127, center: Bool = false, eFill: Bool = false,
                             clock: StateMatrixClock? = nil, liveColOverride: ((Date) -> Int?)? = nil,
                             _ set: @escaping (Int, Int) -> Void) -> some View {
        HStack(spacing: 6) {
        if eFill { EBrushButton(steps: count, accent: accent) { pat in for i in 0..<count { set(i, pat[i] ? maxV : 0) } } }   // §5 E-BRUSH: euclidean fill (hit = max, rest = 0)
        ZStack(alignment: .top) {
        // ONE gesture over the WHOLE lane (Paul 2026-09-07): run a finger ACROSS the bars to draw — the column is hit-tested
        // from the finger's X, so EVERY bar the finger crosses registers (was: each bar owned its own gesture, so the first
        // bar touched captured the whole drag and the rest never responded). x → column · y → value.
        GeometryReader { lane in
            let W = lane.size.width, H = lane.size.height
            // SELF-CLOCKED PLAYHEAD (Paul 2026-09-11): the bars' live-column highlight extrapolates from the beat anchor inside
            // its own TimelineView (so it no longer needs `liveStep` folded into the whole-page @State → no per-step re-render).
            // The DRAG gesture stays on a stable overlay layer (NOT inside the TimelineView) so it isn't re-created each frame.
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    // BESPOKE CLOCK (Paul 2026-09-28): a processor with its own independent RATE/SPAN (VELOCITY, MOD
                    // STEPS, …) passes `clock:`/`liveColOverride:` so this lane sweeps what's actually sounding —
                    // the same `clock ?? gridClock` fallback `stateMatrixRadio` already established. Unspecified
                    // (every pre-existing caller) ⇒ byte-identical to before.
                    let liveColNow: Int = liveColOverride.map { $0(tl.date) ?? -1 } ?? (liveCol(from: clock ?? gridClock, at: tl.date) ?? -1)
                    HStack(spacing: count > 16 ? 1 : (count > 8 ? 2 : 4)) {
                        ForEach(0..<count, id: \.self) { i in
                            let v = i < steps.count ? steps[i] : 0
                            let live = i == liveColNow                    // PLAYHEAD (idea 15): the live grid column
                            ZStack(alignment: center ? .center : .bottom) {   // CENTRE = a bipolar lane (0 = mid, + above, − below) — the TIMING pocket
                                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                                if center {
                                    let frac = CGFloat(v) / CGFloat(maxV)   // −1…1
                                    let barH = Swift.max(2, abs(frac) * H / 2)
                                    RoundedRectangle(cornerRadius: 3).fill(accent).frame(height: barH).offset(y: frac >= 0 ? -barH / 2 : barH / 2)
                                } else {
                                    RoundedRectangle(cornerRadius: 3).fill(accent).frame(height: Swift.max(2, H * CGFloat(v) / CGFloat(maxV)))
                                }
                            }
                            .overlay { pulseGlowOverlay(live, tl.date, corner: 3) }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: W, height: H)
                }
                Color.clear.frame(width: W, height: H)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                        let colW = W / CGFloat(Swift.max(1, count))
                        let col = Swift.max(0, Swift.min(count - 1, Int(val.location.x / Swift.max(1, colW))))   // which bar the finger is over
                        let y = Swift.min(1, Swift.max(0, val.location.y / Swift.max(1, H)))   // 0 top … 1 bottom
                        let nv = center ? Int(((0.5 - y) * 2 * CGFloat(maxV)).rounded()) : Int((1 - y) * CGFloat(maxV))
                        set(col, nv); laneReadout = (center && nv > 0 ? "+" : "") + "\(nv)"   // idea 18: float the value
                    }.onEnded { _ in laneReadout = nil })
            }
        }
        .frame(height: 84)
        if let r = laneReadout {   // LANE READOUT (idea 18): the touched bar's value floats at the top
            Text(r).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .padding(.horizontal, 8).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 5).fill(accent))
                .offset(y: -4)
        }
        }
        }
    }
    // A per-step TOGGLE ROW you can DRAW ACROSS (Paul 2026-09-07): ONE gesture over the whole row — the first cell the finger
    // touches sets the paint TARGET (its inverse), then every cell the finger crosses is SET to that target (idempotent, so
    // no flip-flop within a cell). Drag to enable/disable several at once; a plain tap still flips one. `on`/`setOn` per step.
    // `live` (Paul 2026-09-27, KILL STEP): an optional "given wall-clock now, which column (if any) is live" hook —
    // when supplied, the lane self-animates (a TimelineView, like every other bespoke matrix playhead in this file:
    // RATCHET PATTERN/DEST/CLOCK) and draws the SAME thin white top-bar `stateMatrixRadio` uses for its own live
    // column, so a lane control reads as part of one grid language, not a separately-animated thing. Every existing
    // caller omits it (nil) — unchanged, no TimelineView, byte-identical to before.
    private func toggleLane(_ count: Int, height: CGFloat = 24, on: @escaping (Int) -> Bool, glyph: String? = nil, live: ((Date) -> Int?)? = nil, _ setOn: @escaping (Int, Bool) -> Void) -> some View {
        Group {
            if let live {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
                    toggleLaneGrid(count, height: height, liveCol: live(tl.date), date: tl.date, on: on, glyph: glyph, setOn)
                }
            } else {
                toggleLaneGrid(count, height: height, liveCol: nil, date: Date(), on: on, glyph: glyph, setOn)
            }
        }
    }
    private func toggleLaneGrid(_ count: Int, height: CGFloat, liveCol: Int?, date: Date, on: @escaping (Int) -> Bool, glyph: String?, _ setOn: @escaping (Int, Bool) -> Void) -> some View {
        GeometryReader { row in
            let W = row.size.width
            HStack(spacing: count > 16 ? 1 : (count > 8 ? 2 : 4)) {
                ForEach(0..<count, id: \.self) { s in
                    let lit = on(s)
                    let live = s == liveCol
                    RoundedRectangle(cornerRadius: 4).fill(lit ? accent.opacity(0.85) : Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(lit ? accent : Color.white.opacity(0.14), lineWidth: lit ? 1.5 : 1))
                        .overlay { if lit, let g = glyph { Image(systemName: g).font(.system(size: 9, weight: .black)).foregroundColor(.black) } }
                        .overlay { pulseGlowOverlay(live, date) }
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: W, height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                let colW = W / CGFloat(Swift.max(1, count))
                let col = Swift.max(0, Swift.min(count - 1, Int(val.location.x / Swift.max(1, colW))))
                let target = togglePaintTarget ?? !on(col)   // first touch → the target state (the first cell's inverse)
                togglePaintTarget = target
                setOn(col, target)                            // idempotent SET → paints across, never flip-flops mid-cell
            }.onEnded { _ in togglePaintTarget = nil })
        }
        .frame(height: height)
    }

    // ---- small controls ----
    private func typeShort(_ t: ProcessorType) -> String { t.rawValue }   // FULL name (user 2026-07-30 — no abbreviations)
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
    // RIFF §5 (Paul 2026-08-26): a per-step TOGGLE lane (ACCENT · TIE · SLIDE), aligned under the rank matrix (16pt rank
    // gutter + 30pt SET gutter). `on(step)` reads the lit state; `tap(step)` flips it.
    // `live` (Paul 2026-09-28, closing RIFF's missing-sweep gap): mirrors `toggleLane`'s own optional live-column
    // hook exactly — nil (any future caller that doesn't need it) ⇒ static, unchanged; RIFF's ACCENT/TIE/SLIDE lanes
    // are the first to pass one (RIFF's own bespoke clock, since its playback order isn't a simple rotate).
    private func riffToggleLane(_ label: String, steps: Int, on: @escaping (Int) -> Bool, accent: Color, glyph: String, live: ((Date) -> Int?)? = nil, _ tap: @escaping (Int) -> Void) -> some View {
        field(label) {
            Group {
                if let live {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                        riffToggleLaneRow(steps: steps, on: on, accent: accent, glyph: glyph, liveCol: live(tl.date), date: tl.date, tap)
                    }
                } else {
                    riffToggleLaneRow(steps: steps, on: on, accent: accent, glyph: glyph, liveCol: nil, date: Date(), tap)
                }
            }
        }
    }
    private func riffToggleLaneRow(steps: Int, on: @escaping (Int) -> Bool, accent: Color, glyph: String, liveCol: Int?, date: Date, _ tap: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: 16, height: 14)
            ForEach(0..<steps, id: \.self) { s in
                let isOn = on(s)
                RoundedRectangle(cornerRadius: 3).fill(isOn ? accent.opacity(0.6) : Color.white.opacity(0.06)).frame(maxWidth: .infinity).frame(height: 15)
                    .overlay(isOn ? Text(glyph).font(.system(size: 8, weight: .heavy)).foregroundColor(.white.opacity(0.95)) : nil)
                    .overlay { pulseGlowOverlay(s == liveCol, date, corner: 3) }
                    .contentShape(Rectangle()).onTapGesture { tap(s) }
            }
            Color.clear.frame(width: 30, height: 14)
        }
    }
    // The label row shared by field/heroField: just the label, OR (when `lfo` is set) the label with the ∿ LFO button
    // IMMEDIATELY to its right (Paul 2026-09-15 — not right-aligned; a long label was pushing the button off-screen), taking
    // NO extra vertical space (Docs/PLAN-param-lfo.md). The label shrinks/truncates before the button, so the button is
    // always visible; the trailing Spacer keeps the pair left-packed.
    @ViewBuilder private func lfoLabelRow(_ label: String, opacity: Double, _ lfo: String?) -> some View {
        if let t = lfo {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(opacity)).layoutPriority(0)
                lfoButton(t).layoutPriority(1)
                Spacer(minLength: 0)
            }
        } else {
            Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(opacity))
        }
    }
    private func field<C: View>(_ label: String, lfo: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            lfoLabelRow(label, opacity: 0.55, lfo)
            content()
        }
    }
    // DEFAULTS-RECEDE greying REMOVED (Paul 2026-09-14): controls no longer dim when their param is at its default. This
    // keypath overload now renders identically to the plain `field(_:)` — the `kp` argument is kept so every call site
    // compiles unchanged, and a future "grey while the processor isn't PLAYING" treatment can hang here instead.
    static let paramDefaults = MachineParams()   // kept (harmless) in case a future play-state treatment wants a default reference
    private func field<C: View, V: Equatable>(_ label: String, _ kp: KeyPath<MachineParams, V>, lfo: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        _ = kp
        return VStack(alignment: .leading, spacing: 5) {
            lfoLabelRow(label, opacity: 0.55, lfo)
            content()
        }
    }
    // PER-PARAM LFO (Docs/PLAN-param-lfo.md, Stage 2) — model access (find / upsert / clear the LFO for a param key).
    private func lfoFor(_ target: String) -> ParamLFO? { (p.paramLFOs ?? []).first { $0.target == target } }
    private func setLFO(_ target: String, _ f: @escaping (inout ParamLFO) -> Void) {
        setParam { var arr = $0.paramLFOs ?? []
            if let i = arr.firstIndex(where: { $0.target == target }) { f(&arr[i]) } else { var l = ParamLFO(target: target); f(&l); arr.append(l) }
            $0.paramLFOs = arr.isEmpty ? nil : arr }
    }
    private func clearLFO(_ target: String) {
        setParam { let a = ($0.paramLFOs ?? []).filter { $0.target != target }; $0.paramLFOs = a.isEmpty ? nil : a }
    }
    private func lfoLabelText(_ target: String) -> String {
        switch target {
        case "gate": return "LENGTH"; case "rtcChance": return "CHANCE"
        case "arpRate": return "RATE"
        case "maskK": return "HITS"; case "maskRotate": return "ROTATE"
        case "maskChordOct": return "CHORD OCT"; case "maskChordGate": return "CHORD LEN"
        case "arpVelocity": return "VELOCITY"; case "arpVelTilt": return "VEL TILT"
        default: return target.uppercased()
        }
    }
    // The ∿ LFO button — idle = dim; ACTIVE (an LFO with depth > 0) = accent-filled + the chosen waveform. Tap opens the
    // editor popover (which seeds a default LFO on first open); REMOVE inside clears it.
    private func lfoButton(_ target: String) -> some View {
        let l = lfoFor(target)
        let active = { if let f = l?.from, let t = l?.to, f != t { return true }; return false }()   // ACTIVE = the two endpoints differ
        let shape = l?.shape ?? .sine
        return HStack(spacing: 3) {
            waveGlyph(shape, active ? .black : accent).frame(width: 15, height: 8)
            Text("LFO").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(active ? .black : accent.opacity(0.8))
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(active ? accent : accent.opacity(0.14)))
        .contentShape(Rectangle())
        .onTapGesture { lfoEditTarget = target }
        // AnyView breaks the opaque-type CYCLE (lfoButton → popover → lfoEditor → field → lfoLabelRow → lfoButton): the
        // editor's concrete type is erased here so lfoButton's `some View` no longer depends on itself.
        .popover(isPresented: Binding(get: { lfoEditTarget == target }, set: { if !$0 { lfoEditTarget = nil } })) { AnyView(lfoEditor(target)) }
    }
    // The LFO editor (Paul 2026-09-15 redesign): the LFO sweeps the param FROM → TO and back, over a DURATION, shaped by a
    // WAVE. FROM/TO are authored with the param's OWN control (a "second view" of the card control) and each carries a DIM
    // live marker that moves with the music. No depth/phase/quantize (they confused). Opening seeds FROM=the card's current
    // value, TO=a contrasting endpoint so the sweep is immediately audible; REMOVE (or FROM==TO) = off.
    private func lfoEditor(_ target: String) -> some View {
        let lfo = lfoFor(target) ?? ParamLFO(target: target)
        let shapes = ModShape.allCases
        // SCROLLABLE (Paul 2026-09-16): the popover clips in a short AUv3 host — wrap so the bottom is always reachable.
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        waveGlyph(lfo.shape, accent).frame(width: 20, height: 11)
                        Text("\(lfoLabelText(target)) LFO").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(accent)
                    }
                    Spacer()
                    Text("REMOVE").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.red.opacity(0.16)))
                        .contentShape(Rectangle()).onTapGesture { clearLFO(target) }   // keep the box OPEN — it now reflects the processor (FROM=TO=base) so you can re-author (Paul 2026-09-16); tap outside to close
                }
                if target == "arpRate" {   // INCLUDE rate families the sweep uses (Paul 2026-09-16) — grid unchanged, un-included rows dim + aren't visited. Default: NORMAL only.
                    let ig = lfo.rateIgnoreResolved   // stored as an IGNORE mask; the UI shows the INCLUDE inverse
                    VStack(alignment: .leading, spacing: 5) {
                        Text("INCLUDE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                        HStack(spacing: 6) {
                            ForEach(Array(["NORMAL", "DOTTED", "TRIPLETS"].enumerated()), id: \.offset) { bit, name in
                                let included = (ig & (1 << bit)) == 0
                                Text(name).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(included ? .black : accent)
                                    .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity, minHeight: 40)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(included ? accent : Color.white.opacity(0.09)))
                                    .contentShape(Rectangle()).onTapGesture {
                                        setLFO(target) { let next = ig ^ (1 << bit); $0.rateIgnore = (next & 0b111) == 0b111 ? ig : next }   // can't INCLUDE none (= ignore all three)
                                    }
                            }
                        }
                    }
                }
                // FROM ≡ the PROCESSOR's own param (two views of one value): read the live base, and writing it edits the
                // processor control itself (and vice-versa — the main control writes the same param). TO is the LFO endpoint.
                lfoEndpoint("FROM", target: target, value: lfoSeedFrom(target), lfo: lfo) { v in lfoSetBase(target, v) }
                lfoEndpoint("TO",   target: target, value: lfo.to ?? lfoSeedTo(target), lfo: lfo) { v in setLFO(target) { $0.to = v } }
                // WAVE — ONE row (Paul 2026-09-16), the 5 shapes equal-width across the full FROM/TO width (was iconSeg, which wrapped to 2 rows).
                VStack(alignment: .leading, spacing: 5) {
                    Text("WAVE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                    HStack(spacing: 6) {
                        ForEach(Array(shapes.enumerated()), id: \.offset) { i, s in
                            let on = s == lfo.shape
                            VStack(spacing: 3) {
                                waveGlyph(s, on ? .black : accent).frame(width: 22, height: 12)
                                Text(s.rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : accent).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 7).fill(on ? accent : Color.white.opacity(0.09)))
                            .contentShape(Rectangle()).onTapGesture { setLFO(target) { $0.shape = s } }
                        }
                    }
                }
                // DURATION — two clearly-labelled groups (Paul 2026-09-16): pick a GRID-locked step span OR a fixed subdivision
                // (they're mutually exclusive — choosing one clears the other, as the engine already resolves).
                VStack(alignment: .leading, spacing: 8) {
                    Text("DURATION").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GRID STEPS").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                        seg(lfoDurValues.map { lfoDurLabel($0) }, sel: lfo.stepSpan != nil ? lfoDurLabel(lfo.stepSpan!) : "—") { i in setLFO(target) { $0.stepSpan = lfoDurValues[i] } }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FIXED SUBDIVISION").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                        seg(ModRate.allCases.map(\.rawValue), sel: lfo.stepSpan == nil ? lfo.period.rawValue : "—") { i in setLFO(target) { $0.stepSpan = nil; $0.period = ModRate.allCases[i] } }
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 360).frame(maxHeight: 480)   // fixed width; capped height → the popover clamps to a short host + scrolls
        // NO auto-seed on open (Paul 2026-09-16): opening reflects the processor — FROM reads the live base, TO seeds = base
        // (from==to ⇒ inactive) until the user drags TO. The LFO is only created when TO is moved.
    }
    // DURATION grid ladder (Paul 2026-09-15): 1…8 steps · ×2/×4/×8 bars (16/32/64), matching spanLadderBeats.
    private let lfoDurValues = [1, 2, 3, 4, 6, 8, 16, 32, 64]
    private func lfoDurLabel(_ n: Int) -> String { n == 16 ? "×2" : (n == 32 ? "×4" : (n == 64 ? "×8" : "\(n)")) }
    // One FROM/TO endpoint: the param's own control + a DIM live readout (updates with the music while playing).
    @ViewBuilder private func lfoEndpoint(_ label: String, target: String, value: Double, lfo: ParamLFO, _ set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 0)
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !clockPlaying)) { tl in   // the dim "now" readout, moving with the music
                    if let live = lfoLiveNatural(lfo, date: tl.date) {
                        Text("♪ \(lfoFmt(target, live))").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            lfoEndpointControl(target: target, value: value, lfo: lfo, set)
        }
    }
    // The param's native control, bound to a FROM/TO endpoint (a "second view" of the card control). Sliders also carry a
    // dim live TICK; rate uses the speed grid; the counted params use the ◀n▶ pair (their dim live value shows in the header).
    @ViewBuilder private func lfoEndpointControl(target: String, value: Double, lfo: ParamLFO, _ set: @escaping (Double) -> Void) -> some View {
        switch target {
        case "arpRate":
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !clockPlaying)) { tl in   // the live swept rung, on BOTH FROM and TO
                lfoRateGrid(sel: max(0, min(17, Int(value.rounded()))), ignore: lfo.rateIgnoreResolved, live: lfoLiveRateIndex(lfo, date: tl.date), set)
            }
        case "maskK":
            numPair(max(1, min(16, Int(value.rounded()))), 1...16) { set(Double($0)) }
        case "maskRotate":
            numPair(max(0, min(15, Int(value.rounded()))), 0...15, wrap: true) { set(Double($0)) }
        case "maskChordOct":
            numPair(max(-2, min(2, Int(value.rounded()))), -2...2, format: { $0 > 0 ? "+\($0)" : "\($0)" }) { set(Double($0)) }
        case "arpVelocity":
            lfoSlider(value, 1...100, lfo: lfo, set)
        case "arpVelTilt":
            lfoSlider(value, -1...1, lfo: lfo, set)
        default:
            lfoSlider(value, (target == "rtcChance") ? 0...1 : 0.05...1, lfo: lfo, set)   // gate / chord-len / chance
        }
    }
    // ── MOD editor (arp-LFO anatomy, Paul 2026-09-16) — the FROM/TO endpoint slider + a live CC marker + the DURATION control.
    // A FROM/TO endpoint as a 0…127 slider with a dim live tick at the current CC value (nil ⇒ no marker: stopped, or a
    // source whose value the editor can't derive — FOLLOW/EXTERN/STRIKE depend on the live pool / incoming CC / column entry).
    private func modEndpointSlider(_ label: String, _ value: Int, live: Int?, _ set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 0)
                if let live { Text("♪ \(live)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4)) }
            }
            ZStack(alignment: .leading) {
                slider(bind(Double(value) / 127) { set(Int(($0 * 127).rounded())) }, in: 0...1)
                GeometryReader { g in
                    if let live { Rectangle().fill(Color.white.opacity(0.4)).frame(width: 2).offset(x: CGFloat(Double(live) / 127) * g.size.width).allowsHitTesting(false) }
                }
            }
        }
    }
    // DURATION as the arp-LFO two groups — GRID STEPS (modStepSpanN, via spanLadderBeats) · FIXED SUBDIVISION (modRate).
    // Mutually exclusive: GRID STEPS ⇒ modStepSpanN>0 · FIXED SUBDIVISION ⇒ modStepSpanN nil. (SHAPE source only.)
    @ViewBuilder private func modDurationControl() -> some View {
        let sn = p.modStepSpanN ?? 0
        VStack(alignment: .leading, spacing: 8) {
            Text("DURATION").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 4) {
                Text("GRID STEPS").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                seg(lfoDurValues.map { lfoDurLabel($0) }, sel: sn > 0 ? lfoDurLabel(sn) : "—") { i in setParam { $0.modStepSpanN = lfoDurValues[i] } }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("FIXED SUBDIVISION").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                seg(ModRate.allCases.map(\.rawValue), sel: sn == 0 ? (p.modRate ?? .r2).rawValue : "—") { i in setParam { $0.modStepSpanN = nil; $0.modRate = ModRate.allCases[i] } }
            }
        }
    }
    // The MOD's current CC output right now (mirrors the engine's modSourceUnipolar→modMap so the marker matches audio).
    // SHAPE + STEPS only (beat-derived); other sources return nil (no editor marker). nil when the clock is stopped.
    // Factored out of modLiveCC (Paul 2026-09-28) so the STEPS lane's own live-sweep can share the IDENTICAL period
    // math instead of a third hand-derived copy (the engine's modPeriodBeats is the second) — two readers, one formula.
    private func modPeriodBeatsUI(src: ModSource) -> Double {
        let S = Swift.max(0.0001, gridStepBeats)
        let bar = Double(Snap.cols) * S
        let sn = p.modStepSpanN ?? 0
        if sn > 0 { return Swift.max(0.03125, spanLadderBeats(sn, S: S, row: bar)) }
        if src == .steps {
            switch p.modStepSpan ?? .period {
            case .period: return Swift.max(0.03125, (p.modRate ?? .r2).periodBeats)
            case .row:    return Swift.max(0.03125, bar)
            case .row2:   return Swift.max(0.03125, 2 * bar)
            case .row4:   return Swift.max(0.03125, 4 * bar)
            }
        }
        return (p.modSpan ?? .cell) == .row ? Swift.max(0.03125, bar) : Swift.max(0.03125, (p.modRate ?? .r2).periodBeats)
    }
    private func modLiveCC(date: Date) -> Int? {
        guard clockPlaying else { return nil }
        let src = p.modSource ?? .shape
        let period = modPeriodBeatsUI(src: src)
        guard period > 0 else { return nil }
        let beat = beatAnchor + date.timeIntervalSince(beatAnchorAt) * tempo / 60.0
        let cyc = Int((beat / period).rounded(.down))
        let u: Double
        switch src {
        case .shape: u = modUnipolar(p.modShape ?? .sine, phase: beat / period + (p.modPhase ?? 0), column: 0, cc: p.modCC ?? 74, cycleIndex: cyc)
        case .steps: u = modStepsUnipolar(p.modSteps ?? [0, 18, 36, 54, 72, 90, 108, 127], phase: beat / period, smooth: p.modSmooth ?? true)
        default:     return nil
        }
        return modMap(u, min: p.modMin ?? 0, max: p.modMax ?? 127)
    }
    // A slider endpoint with a dim live TICK overlaid at the current LFO value (moves with the music).
    private func lfoSlider(_ v: Double, _ range: ClosedRange<Double>, lfo: ParamLFO, _ set: @escaping (Double) -> Void) -> some View {
        let lo = range.lowerBound, hi = range.upperBound
        return ZStack(alignment: .leading) {
            slider(bind(max(0, min(1, (v - lo) / (hi - lo)))) { set(lo + $0 * (hi - lo)) }, in: 0...1)
            GeometryReader { g in
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !clockPlaying)) { tl in
                    if let live = lfoLiveNatural(lfo, date: tl.date) {
                        let f = max(0, min(1, (live - lo) / (hi - lo)))
                        Rectangle().fill(Color.white.opacity(0.4)).frame(width: 2).offset(x: f * g.size.width).allowsHitTesting(false)
                    }
                }
            }
        }
    }
    // The rate speed grid as a FROM/TO endpoint: `sel` (the endpoint rung) is solid; the live rung gets a dim ring.
    // The rate ladder as an LFO endpoint: `sel` (the endpoint rung) is SOLID; `live` (the swept rung right now) gets a
    // DIM ring; families in `ignore` (bit0 normal · bit1 dotted · bit2 triplet) dim to show they're skipped. (Paul 2026-09-16)
    private func lfoRateGrid(sel: Int, ignore: Int = 0, live: Int? = nil, _ pick: @escaping (Double) -> Void) -> some View {
        let all = ArpRate.allCases
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                let famIgnored = (ignore & (1 << row)) != 0
                HStack(spacing: 3) {
                    ForEach(0..<6, id: \.self) { col in
                        let idx = row * 6 + col; let on = idx == sel; let isLive = live == idx
                        Text(all[idx].rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : accent).lineLimit(1).minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, minHeight: 26).padding(.horizontal, 1)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? accent : Color.white.opacity(0.09)))
                            .overlay { if isLive && !on { RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.5), lineWidth: 2) } }   // the live swept rate
                            .opacity(famIgnored ? 0.32 : 1)                                                                                       // ignored family = dimmed (still the full grid)
                            .contentShape(Rectangle()).onTapGesture { pick(Double(idx)) }
                    }
                }
            }
        }
    }
    // The current LFO output as a LADDER-SNAPPED rate index (mirrors the engine's ignore-aware sweep), for the dim live ring.
    private func lfoLiveRateIndex(_ lfo: ParamLFO, date: Date) -> Int? {
        let from = lfoSeedFrom(lfo.target)   // FROM ≡ the base param (two views)
        guard clockPlaying, let to = lfo.to, from != to else { return nil }
        let S = Swift.max(0.0001, gridStepBeats)
        let periodBeats = (lfo.stepSpan ?? 0) > 0 ? spanLadderBeats(lfo.stepSpan!, S: S, row: 8 * S) : lfo.period.periodBeats
        guard periodBeats > 0 else { return nil }
        let beat = beatAnchor + date.timeIntervalSince(beatAnchorAt) * tempo / 60.0
        let cyc = Int((beat / periodBeats).rounded(.down))
        let u = modUnipolar(lfo.shape, phase: beat / periodBeats, column: 0, cc: 0, cycleIndex: cyc)
        let ladder = arpRateAllowedLadder(ignore: lfo.rateIgnoreResolved)
        let fp = nearestLadderPos(ladder, Int(from.rounded())), tp = nearestLadderPos(ladder, Int(to.rounded()))
        let pos = Int((Double(fp) + u * Double(tp - fp)).rounded())
        return ladder[max(0, min(ladder.count - 1, pos))]
    }
    // The current LFO output in the param's NATURAL space, for the dim live markers (nil when stopped/inactive). Uses the
    // scene clock (gridStepBeats) so the step-span duration matches the engine; the beat is extrapolated like the playheads.
    private func lfoLiveNatural(_ lfo: ParamLFO, date: Date) -> Double? {
        let from = lfoSeedFrom(lfo.target)   // FROM ≡ the base param (two views)
        guard clockPlaying, let to = lfo.to, from != to else { return nil }
        let S = Swift.max(0.0001, gridStepBeats)
        let periodBeats = (lfo.stepSpan ?? 0) > 0 ? spanLadderBeats(lfo.stepSpan!, S: S, row: 8 * S) : lfo.period.periodBeats
        guard periodBeats > 0 else { return nil }
        let beat = beatAnchor + date.timeIntervalSince(beatAnchorAt) * tempo / 60.0
        let cyc = Int((beat / periodBeats).rounded(.down))
        let u = modUnipolar(lfo.shape, phase: beat / periodBeats, column: 0, cc: 0, cycleIndex: cyc)
        return from + u * (to - from)
    }
    // Format a natural value for a target's dim live readout.
    private func lfoFmt(_ target: String, _ v: Double) -> String {
        switch target {
        case "arpRate":         return ArpRate.allCases[max(0, min(17, Int(v.rounded())))].rawValue
        case "maskChordOct":    let n = Int(v.rounded()); return n > 0 ? "+\(n)" : "\(n)"
        case "maskK", "maskRotate": return "\(Int(v.rounded()))"
        case "arpVelocity":     return "\(Int(v.rounded()))"   // an ABSOLUTE 1…100 value now (Paul 2026-09-30) — not a %, the default's ×100 would mangle it
        case "arpVelTilt":      let n = Int((v * 100).rounded()); return n > 0 ? "+\(n)" : "\(n)"   // matches strum/chance's bare-number tilt convention (no %)
        default:                return "\(Int((v * 100).rounded()))%"
        }
    }
    // Seed FROM = the card's current value (a "second view"); TO = a contrasting endpoint so the sweep is audible at once.
    private func lfoSeedFrom(_ target: String) -> Double {
        switch target {
        case "arpRate":            return Double(ArpRate.allCases.firstIndex(of: p.rate ?? .r1_16) ?? 3)
        case "maskK":              return Double(max(1, min(16, p.maskK ?? (p.maskN ?? 8))))
        case "maskRotate":         return Double(max(0, min(15, p.maskRotate ?? 0)))
        case "maskChordOct":       return Double(max(-2, min(2, p.maskChordOct ?? 0)))
        case "maskChordGate":      return p.maskChordGate ?? 0.6
        case "rtcChance":          return p.rtcChance ?? 0.5
        case "arpVelocity":        return p.arpVelocity ?? 100
        case "arpVelTilt":         return p.arpVelTilt ?? 0
        default:                   return p.gate ?? 0.6
        }
    }
    // TO seeds = the processor's CURRENT value (Paul 2026-09-16): opening/deleting an LFO shows FROM==TO==the base, so the
    // box reflects how the control is set; the user drags TO to author a sweep.
    private func lfoSeedTo(_ target: String) -> Double { lfoSeedFrom(target) }
    // Write the PROCESSOR's own param — the inverse of lfoSeedFrom, so the FROM control IS the main control (two views).
    private func lfoSetBase(_ target: String, _ v: Double) {
        switch target {
        case "arpRate":            setParam { $0.rate = ArpRate.allCases[max(0, min(17, Int(v.rounded())))] }
        case "maskK":              setParam { $0.maskK = max(1, min(16, Int(v.rounded()))) }
        case "maskRotate":         setParam { $0.maskRotate = max(0, min(15, Int(v.rounded()))) }
        case "maskChordOct":       setParam { $0.maskChordOct = max(-2, min(2, Int(v.rounded()))) }
        case "maskChordGate":      setParam { $0.maskChordGate = v }
        case "rtcChance":          setParam { $0.rtcChance = v }
        case "arpVelocity":        setParam { $0.arpVelocity = v }
        case "arpVelTilt":         setParam { $0.arpVelTilt = v }
        default:                   setParam { $0.gate = v }
        }
    }
    // A BIPOLAR slider (§presentation idea 4/22): centred on 0; DOUBLE-TAP the label = reset to centre. `v`/`set` are in
    // the natural range; the track maps it to 0…1. `lfo` (Paul 2026-09-30, ARP VELOCITY TILT — the first bipolar field
    // to want one): swaps the plain label for the LFO-aware `lfoLabelRow` (the ∿ button) and, once an LFO is authored,
    // the slider for `lfoSlider` (its dim live tick) — nil (every existing caller: strum's VOL TILT, chance's FAVOUR)
    // renders BYTE-IDENTICAL to before, since `lfoLabelRow`'s own no-lfo branch is the same Text/font/opacity this
    // function used inline.
    private func bipolarSlider(_ label: String, _ v: Double, in range: ClosedRange<Double> = -1...1, lfo target: String? = nil, _ set: @escaping (Double) -> Void) -> some View {
        let lo = range.lowerBound, hi = range.upperBound
        return VStack(alignment: .leading, spacing: 5) {
            lfoLabelRow(label, opacity: 0.55, target)
                .contentShape(Rectangle()).onTapGesture(count: 2) { set(0) }   // double-tap → centre (0)
            if let t = target, let l = lfoFor(t) { lfoSlider(v, range, lfo: l) { set($0) } }
            else { slider(bind((v - lo) / (hi - lo)) { set(lo + $0 * (hi - lo)) }, in: 0...1) }
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
    private func heroField<C: View>(_ label: String, lfo: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty { lfoLabelRow(label, opacity: 0.85, lfo) }
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
        let topVals = (free ? [0] : []) + [16, 32]   // FREE · 16 · 32 on top …
        let botVals = [1, 2, 3, 4, 6, 8]             // … 1 · 2 · 3 · 4 · 6 · 8 below
        // RATCHET PATTERN SPAN is now in MATRIX COLUMNS (re-anchor every N of the STEPS columns), so label them as plain
        // counts — the old "×2/×4" (grid rows) no longer applies (Paul 2026-09-07).
        let lbl: (Int) -> String = { $0 == 0 ? "FREE" : "\($0)" }
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
    // `compact` (Paul 2026-10-02, EUCLID's own DIRECTION row): halves the chip height + trims the font, same
    // opt-in convention as `numPair`'s own `compact` — default false, so every other of this function's ~30
    // call sites is byte-identical.
    private func seg(_ options: [String], sel: String, compact: Bool = false, _ onPick: @escaping (Int) -> Void) -> some View {
        // Chips size to their LABEL (finger-min 52pt), LEFT-aligned — so a 2-option toggle is ~140pt, not the full panel
        // width (Paul 2026-08-25: "controls feel too wide"). Font unchanged; the trailing Spacer stops the row stretching.
        let rows = radioRows(options.count)
        return VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, span in
                HStack(spacing: compact ? 4 : 6) {
                    ForEach(span, id: \.self) { i in
                        let on = options[i] == sel
                        Text(options[i]).font(.system(size: compact ? 11 : 15, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : accent).lineLimit(1)
                            .padding(.horizontal, compact ? 10 : 15).frame(minWidth: compact ? 36 : 52, minHeight: compact ? 21 : 42)
                            .background(RoundedRectangle(cornerRadius: 7).fill(on ? accent : Color.white.opacity(0.09)))
                            .contentShape(Rectangle()).onTapGesture { onPick(i) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    // VERTICAL seg (Paul 2026-09-14): one option per row, stacked. Chips fill the column width so the box reads as a
    // tidy vertical group that LINES UP alongside a tall neighbour (the ARP FLOW box beside the 3-row SPEED grid).
    private func segV(_ options: [String], sel: String, _ onPick: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                let on = opt == sel
                Text(opt).font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : accent).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 32).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent : Color.white.opacity(0.09)))
                    .contentShape(Rectangle()).onTapGesture { onPick(i) }
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
    // THE ARP PATTERN ROW (Paul 2026-09-13): every pattern on ONE line, no wrap, no highlight bar. Each option maps to a
    // (pattern, RANDOM-anchor) pair — the last two are the retired RANDOM ANCHOR control (open each cycle HIGH / LOW),
    // now first-class buttons beside RANDOM. Ordered for future patterns to append to.
    static let arpPatternOptions: [(pattern: ArpPattern, anchor: Int, label: String, glyph: String)] = [
        (.up,       0, "UP",         "arrow.up"),
        (.down,     0, "DOWN",       "arrow.down"),
        (.upDown,   0, "UP/DOWN",    "arrow.up.arrow.down"),
        (.altLo,    0, "ALT LO",     "arrow.up.to.line"),
        (.altHi,    0, "ALT HI",     "arrow.down.to.line"),
        (.asPlayed, 0, "AS PLAYED",  "hand.point.up.left"),
        (.random,   0, "RANDOM",     "shuffle"),
        (.random,   2, "RND HI FIRST", "shuffle"),
        (.random,   1, "RAND LO FIRST", "shuffle"),
        (.randomOnce, 0, "RANDOM ONCE", "shuffle"),   // a FIXED shuffle off a persisted seed — repeats every cycle (Paul 2026-09-16)
    ]
    // `opts` is now an explicit SLICE (Paul 2026-09-30: "two equally sized rows" — the caller splits the 10-entry
    // table in half and calls this twice) rather than always the whole table. `sel` is Optional — nil when the
    // currently-picked pattern belongs to the OTHER row's slice, so a selection elsewhere can no longer wrongly
    // light this row's first chip (the old `?? 0` fallback only ever needed to cover "some chip in the ONE full
    // table always matches"; that's no longer true once the table is split).
    private func arpPatternRow(_ opts: [(pattern: ArpPattern, anchor: Int, label: String, glyph: String)], pattern: ArpPattern, anchor: Int, _ pick: @escaping (ArpPattern, Int) -> Void) -> some View {
        // Derive the lit index FROM the table (never hardcode positions — inserting a pattern shifts them). RANDOM has
        // three rows split by anchor, so match anchor there; every other pattern is a single row (anchor 0).
        let sel: Int? = opts.firstIndex { $0.pattern == pattern && (pattern == .random ? $0.anchor == anchor : true) }
        return HStack(spacing: 4) {
            ForEach(Array(opts.enumerated()), id: \.offset) { idx, o in
                let on = idx == sel
                Text(o.label).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : accent)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? accent : Color.white.opacity(0.09)))
                .contentShape(Rectangle()).onTapGesture { pick(o.pattern, o.anchor) }
            }
        }
    }
    // THE ARP SPEED GRID (Paul 2026-09-14): 3 rows of 6 — top standard, middle dotted, bottom triplet. Relies on
    // ArpRate.allCases being ordered [6 straight · 6 dotted · 6 triplet]. Chips share width + shrink-to-fit.
    // `live` = the LFO's current swept rate index (dim ring), so the main SPEED grid reflects the automation. (Paul 2026-09-16)
    private func arpSpeedGrid(sel: ArpRate, live: Int? = nil, _ pick: @escaping (ArpRate) -> Void) -> some View {
        let all = ArpRate.allCases
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<6, id: \.self) { col in
                        let idx = row * 6 + col; let r = all[idx]
                        let on = r == sel; let isLive = live == idx
                        Text(r.rawValue).font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : accent).lineLimit(1).minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, minHeight: 32).padding(.horizontal, 1)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? accent : Color.white.opacity(0.09)))
                            .overlay { if isLive && !on { RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.5), lineWidth: 2) } }   // the live swept rate
                            .contentShape(Rectangle()).onTapGesture { pick(r) }
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
    // THE NUDGE PAIR (Paul 2026-08-25 §presentation rule 3): ◀ value ▶ — the ONE numeric grammar. tap = ±1 · drag the
    // value = scrub. Replaces grid16, numeric-as-radio, CHANNEL's chip wall, AND is the ROTATE control. `wrap` cycles
    // (rotate/channel); `format` prints units/glyphs (e.g. "3/16", "WIRE").
    private func numPair(_ v: Int, _ range: ClosedRange<Int>, wrap: Bool = false, compact: Bool = false,
                         format: @escaping (Int) -> String = { "\($0)" }, _ set: @escaping (Int) -> Void) -> some View {
        NumPair(value: v, range: range, wrap: wrap, compact: compact, format: format, accent: accent, set: set)
    }
}

/// The nudge-pair view (its own struct so the drag-scrub can hold gesture state). §presentation rule 3.
private struct NumPair: View {
    let value: Int
    let range: ClosedRange<Int>
    var wrap = false
    // COMPACT (Paul 2026-10-01, the EUCLID row redesign): half-height variant — opt-in, every existing caller
    // across the whole file stays at the original 42pt (default false) so this is additive, not a global resize.
    var compact = false
    var format: (Int) -> String = { "\($0)" }
    let accent: Color
    let set: (Int) -> Void
    @State private var dragBase: Int? = nil
    @State private var showPicker = false      // ideas 12/31: tap the value → a grid/keypad overlay for exact entry
    @State private var padEntry = ""
    private var h: CGFloat { compact ? 21 : 42 }
    private func clampWrap(_ raw: Int) -> Int {
        if wrap { let n = max(1, range.count); return range.lowerBound + (((raw - range.lowerBound) % n) + n) % n }
        return min(range.upperBound, max(range.lowerBound, raw))
    }
    private func apply(_ raw: Int) { let x = clampWrap(raw); if x != value { set(x) } }
    private func arrow(_ glyph: String, _ act: @escaping () -> Void) -> some View {
        Text(glyph).font(.system(size: compact ? 12 : 17, weight: .heavy)).foregroundColor(.white.opacity(0.85))
            .frame(width: 44, height: h).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
            .contentShape(Rectangle()).onTapGesture(perform: act)
    }
    var body: some View {
        HStack(spacing: 6) {
            arrow("◀") { apply(value - 1) }
            Text(format(value)).font(.system(size: compact ? 12 : 16, weight: .heavy, design: .monospaced)).foregroundColor(accent)
                .lineLimit(1).padding(.horizontal, 10).frame(minWidth: 56, minHeight: h)
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
            // CHUNKIER + more grabbable (Paul 2026-09-16): fat track, big thumb, taller touch row — "grabbable, not precise"
            // (the pull-away FINE ×10 mode still covers precision). d = thumb diameter (grows further in fine mode).
            let d: CGFloat = fine ? 34 : 28
            let th: CGFloat = 9                       // track thickness
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: th)
                Capsule().fill(accent.opacity(0.9)).frame(width: max(th, frac * w), height: th)
                // detent pips on the track (a faint tick where each snap value sits)
                ForEach(detents.indices, id: \.self) { i in
                    Circle().fill(Color.white.opacity(0.32)).frame(width: 4, height: 4)
                        .offset(x: min(w - 4, max(0, CGFloat((detents[i] - lo) / span) * w - 2)))
                }
                Circle().fill(.white).frame(width: d, height: d)
                    .overlay(Circle().stroke(accent, lineWidth: fine ? 3 : 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 2.5, x: 0, y: 1)   // soft lift → reads as a grabbable knob
                    .offset(x: min(w - d, max(0, frac * w - d / 2)))
            }
            .frame(height: 40, alignment: .center)
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


// MARK: - Cell-edit STAGING (user 2026-07-25) — long-press a machine → configure a pending cell in the
// side panels (EDIT only). The RECEIVERS panel becomes the cell's INPUT picker (R1–R4 radio + a FROM ROW
// option), the EMITTERS panel its OUTPUT buses. Ephemeral (a StampConfig), recalled across enter/exit.
// The render-path live-preview drag-to-grid is DEFERRED to the design spec — this is the panel scaffold.

// THE PIANO-ROLL FACE (Paul 2026-08-19): the perform-grid cells echo a piano roll — soft note marks enter at the right
// and drift left AS THE CELL SOUNDS, then fade. Gentle + calm (identity stays the cell's HUE). This is the shipped cell
// face; set false to fall back to THE SEAL (kept intact). (The mosaic face was dropped 2026-08-23, Paul.)
let usePianoRollFace = true



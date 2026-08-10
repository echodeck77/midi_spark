import SwiftUI
import UIKit   // DDHoldTracker: a reliable press/release tracker for the DELETE box (SwiftUI gestures get cancelled by the second-finger cell taps)

// DELETE-BOX HOLD TRACKER (user 2026-08-10): SwiftUI sequenced long-press/drag gestures get CANCELLED by the
// second-finger cell taps during the hold, so their `onEnded` never fires and delete mode sticks after release. A
// bare UIView tracks touches DIRECTLY (immune to SwiftUI's gesture arena): it ARMS once a touch has been held on the
// box for `minDuration`, and RELEASES when the LAST touch on the box lifts/cancels. Cell taps land outside the box,
// so they never reach this view and never disturb the arm/release bookkeeping.
struct DDHoldTracker: UIViewRepresentable {
    var minDuration: TimeInterval = 0.35
    var onArm: () -> Void
    var onRelease: () -> Void
    func makeUIView(context: Context) -> HoldView { let v = HoldView(); v.backgroundColor = .clear; v.isMultipleTouchEnabled = true; return v }
    func updateUIView(_ v: HoldView, context: Context) { v.minDuration = minDuration; v.onArm = onArm; v.onRelease = onRelease }
    final class HoldView: UIView {
        var minDuration: TimeInterval = 0.35
        var onArm: () -> Void = {}
        var onRelease: () -> Void = {}
        private var armed = false
        private var armTimer: Timer?
        private var touchCount = 0
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchCount += touches.count
            guard armTimer == nil, !armed else { return }
            armTimer = Timer.scheduledTimer(withTimeInterval: minDuration, repeats: false) { [weak self] _ in
                guard let self, self.touchCount > 0 else { return }
                self.armed = true; self.onArm()
            }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
        private func end(_ touches: Set<UITouch>) {
            touchCount = max(0, touchCount - touches.count)
            guard touchCount == 0 else { return }
            armTimer?.invalidate(); armTimer = nil
            if armed { armed = false; onRelease() }
        }
    }
}

// THE DRAG&DROP PAGE (design stage, user 2026-08-09) — a NEW first tab. Per DESIGN-dragdrop-page.md: a colour is a
// machine; you edit colours, placed as cells. LANDSCAPE-first, ONE non-scrolling panel:
//   TOP band  = the 4×4 PALETTE (16 colours, flat swatches) + ROW SELECTORS + the 8×8 GRID (flat colour v1, calm).
//   BOTTOM band = the MACHINERY (the existing flow diagram) full-width, with PLAY THIS CELL + RANDOMIZE at its right.
// Built: layout · selection · machinery · row selectors · RANDOMIZE · the palette playhead · the SIX DRAG LANDINGS
// (palette→grid PLACE · grid→grid MOVE · grid→occupied-palette ADOPT · grid→empty-palette FORK · →LITTER delete).
// Deferred: palette↔palette reorg, SINGLE|MULTI|FREE, the true per-colour machine model.
private enum DDTarget { case grid(Int, Int), palette(Int), litter }

// The row-selector PAINT cycle (user 2026-08-09): press 1 fills the row's EMPTY cells with the colour; press 2 fills
// the WHOLE row (only if the row is now mixed, else it reverts like press 3); press 3 reverts to the original row.
struct DDRowCycle { var row: Int; var colour: Int; var phase: Int; var original: [Cell?] }

// DELETE MODE (user 2026-08-10): while the DELETE box is HELD, a tap deletes a cell/colour; a second tap reverts it.
// A stashed (col,row,cell) so a re-tap can put it back exactly.
struct DDCellAt: Equatable { let col: Int; let row: Int; let cell: Cell }

// Drop-zone frames for the CUSTOM finger-tracking drag (SwiftUI's .onDrag/.onDrop don't survive the AU host).
struct DDZonePref: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

extension DiagView {
    @ViewBuilder func dragDropPage(_ size: CGSize) -> some View {
        let pageW = min(size.width - 24, 1024)                       // hold the global 1024 content cap (user 2026-08-09)
        let landscape = size.width > size.height
        // grid + palette are HEIGHT-MATCHED (user 2026-08-09): the grid = loop row (18) + 8 cells; the palette = 4
        // swatches + the DELETE box (= a swatch). gridCell drives, swatch is derived so both stack to the same height.
        let H = min(size.height * (landscape ? 0.52 : 0.46), landscape ? 480 : 400)
        let gridCell = max(16, min(48, (H - 50) / 8))
        let matchedH = gridCell * 8 + 50                             // the actual grid height after clamping
        let swatch = landscape ? max(20, (matchedH - 64) / 5)        // landscape: HEADER (GOLD·cell·count) + 4 palette rows + DELETE match the grid height (user 2026-08-10)
                               : max(22, (matchedH - 128) / 5)       // portrait: palette + DELETE + identity (name·count·PLAY) matches it
        let paletteW = swatch * 4 + 18
        Group {
            if landscape {
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {            // TOP band (user 2026-08-10): LEFT palette column · CENTRED grid · RIGHT action box
                        VStack(spacing: 8) {                          // LEFT column, LEFT-aligned: header ABOVE the palette; whole column == grid height
                            ddColourHeader().frame(height: 28)
                            ddPalette(swatch: swatch, litterHeight: swatch)
                        }.frame(width: paletteW, height: matchedH, alignment: .top)
                        Spacer(minLength: 0)
                        HStack(alignment: .top, spacing: 5) {         // CENTRED grid (Spacers either side)
                            ddRowSelectors(cell: gridCell, topInset: 18)
                            VStack(spacing: 4) { ddColumnLoopRow(cell: gridCell); ddGrid(cell: gridCell) }
                            ddRowSelectors(cell: gridCell, topInset: 18, pointRight: true)   // RIGHT-side row selectors (user 2026-08-09)
                        }
                        Spacer(minLength: 0)
                        ddActionBox().frame(width: paletteW, height: matchedH)   // RIGHT box — EQUAL size to the left column; RANDOMIZE·MUTATE·LIBRARY, wired to the last slot
                    }
                    // MACHINERY (landscape): PLAY: THIS CELL sits top-left (where LIBRARY was). (user 2026-08-10)
                    ddMachinery(width: pageW, landscape: true).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 20) {            // PORTRAIT (user 2026-08-10): LEFT column · grid RIGHT-aligned
                        VStack(alignment: .leading, spacing: 10) {   // order: swatch+GOLD · "N cells" · palette · DELETE · PLAY: THIS CELL
                            ddColourIdentity(showPlay: false)         // the preview cell + GOLD, then "N cells" below
                            ddPalette(swatch: swatch, litterHeight: swatch)   // palette + DELETE
                            ddPlayCellButton()                        // PLAY: THIS CELL (bottom)
                        }.frame(width: paletteW, alignment: .leading)
                        Spacer(minLength: 0)                          // push the grid to the RIGHT
                        HStack(alignment: .top, spacing: 5) {
                            ddRowSelectors(cell: gridCell, topInset: 18)
                            VStack(spacing: 4) { ddColumnLoopRow(cell: gridCell); ddGrid(cell: gridCell) }
                            ddRowSelectors(cell: gridCell, topInset: 18, pointRight: true)   // RIGHT-side row selectors (user 2026-08-09)
                        }
                    }.frame(height: matchedH, alignment: .top)
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    ddMachinery(width: pageW).frame(maxWidth: .infinity, alignment: .top)
                    ddMacroControls().frame(maxWidth: 460).padding(.horizontal, 12)   // THE DICE: sliders + buttons BELOW the machinery (portrait) (user 2026-08-10)
                }
            }
        }
        .frame(width: pageW)
        .frame(maxWidth: .infinity)                                  // centre the capped content on wider canvases
        .padding(.vertical, 12)
        .coordinateSpace(name: "dd")                                               // the drag's shared frame of reference
        .onPreferenceChange(DDZonePref.self) { ddZones = $0 }                       // collect the drop-zone frames
        // SAFETY NET: a page-level release clears any stuck drag state. The page root survives the cell re-renders that
        // can cancel a source cell's own gesture mid-drop (leaving the ghost/highlights stuck). (user 2026-08-09)
        .simultaneousGesture(DragGesture(minimumDistance: 10, coordinateSpace: .named("dd")).onEnded { _ in ddResetDrag() })   // min 10 so a TAP never triggers the reset (was interfering with processor-box taps) (user 2026-08-10)
        .overlay(alignment: .topLeading) { if let p = ddDragPayload { ddGhost(p).position(x: ddDragLoc.x, y: ddDragLoc.y - 32).allowsHitTesting(false) } }   // the in-hand ghost, above the finger
        .overlay { if landscape { ddActionLine() } }   // the connector: action box → final processor box (both measured in "dd" space)
        .onChange(of: d.beat) { b in ddBeatAnchor = b; ddBeatAnchorAt = Date() }   // playhead: anchor each poll for extrapolation
    }
    // A cell/swatch reports its frame (in "dd" space) so a drag's end point can be hit-tested to a landing.
    func ddZone(_ key: String) -> some View {   // internal so flowDiagram (EditPage.swift) can measure the last processor slot for the action-box line
        GeometryReader { g in Color.clear.preference(key: DDZonePref.self, value: [key: g.frame(in: .named("dd"))]) }
    }
    // The custom drag (user 2026-08-09): a LONG PRESS (0.25s) ARMS the drag — the ghost appears + the actual move/copy
    // begins. A quick tap still flows to onTapGesture. The inner DragGesture has minimumDistance 0 so `.second` fires
    // at the press point the instant the hold completes.
    private func ddDragGesture(_ payload: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("dd")))
            .onChanged { value in
                if case .second(_, let drag) = value {
                    ddDragPayload = payload
                    // A HELD palette colour arms PAINT: while it's down, tapping grid cells sets them to it (user 2026-08-09).
                    if payload.hasPrefix("colour:") { ddPaintColour = String(payload.dropFirst("colour:".count)) }
                    if let d = drag { ddDragLoc = d.location; ddDropHover = ddZoneAt(d.location, excluding: payload) }
                }
            }
            .onEnded { value in
                if case .second(_, let drag) = value, let d = drag,
                   let target = ddZoneAt(d.location, excluding: payload) { ddLandingKey(payload: payload, targetKey: target) }
                if payload.hasPrefix("colour:") { ddPaintColour = nil }   // the held colour was released → paint off
                ddResetDrag()
            }
    }
    /// Clear ALL transient drag state — the in-hand ghost, the touched-source highlight, and the hover. A SAFETY NET:
    /// SwiftUI can CANCEL a gesture (its `.onEnded` never fires) when the drop's document mutation re-renders/re-identifies
    /// the source cell mid-gesture, which left the ghost + target highlights stuck on. Called from every gesture's end AND
    /// a page-level release gesture whose root survives the cell re-renders. (user 2026-08-09)
    func ddResetDrag() { ddDragPayload = nil; ddTouchSource = nil; ddDropHover = nil }
    // Drop-target HIGHLIGHT-on-TOUCH (user 2026-08-09): a bare minimumDistance-0 drag fires the instant a finger lands
    // on a draggable source, so the potential destinations light up BEFORE the long-press arms the real drag. Cleared
    // the moment the finger lifts (or the drag drops). Runs simultaneously with the tap + the long-press-drag above.
    private func ddTouchGesture(_ payload: String) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("dd"))
            .onChanged { _ in if ddTouchSource != payload { ddTouchSource = payload } }
            .onEnded { _ in ddResetDrag() }
    }
    // What's active for the HIGHLIGHT: the in-hand drag payload, a HELD paint colour, or the touched source. (The
    // paint colour keeps the grid lit even after the first paint tap clears the ghost.)
    private var ddActivePayload: String? { ddDragPayload ?? ddPaintColour.map { "colour:\($0)" } ?? ddTouchSource }
    // The colour of a payload ("colour:<id>" or "cell:<c>:<r>") → the drop-zone highlight hue.
    private func ddPayloadColourID(_ payload: String?) -> String? {
        guard let p = payload else { return nil }
        let t = p.split(separator: ":").map(String.init)
        if t.first == "colour", t.count == 2 { return t[1] }
        if t.first == "cell", t.count == 3, let c = Int(t[1]), let r = Int(t[2]) { return scene.cellAt(c, r)?.colourID }
        return nil
    }
    private var ddDragHue: Color { ddPayloadColourID(ddActivePayload).flatMap { colourColor($0) } ?? Self.editHue }
    private func ddZoneAt(_ p: CGPoint, excluding payload: String) -> String? {
        // a cell dragged onto its OWN frame isn't a landing — skip it so the ghost reads the litter/palette behind
        let selfKey = payload.hasPrefix("cell:") ? "grid:" + payload.dropFirst("cell:".count) : nil
        return ddZones.first(where: { $0.value.contains(p) && $0.key != selfKey })?.key
    }
    private func ddLandingKey(payload: String, targetKey k: String) {
        let t = k.split(separator: ":").map(String.init)
        if t.first == "grid", t.count == 3, let c = Int(t[1]), let r = Int(t[2]) { ddApplyDrop(payload: payload, onto: .grid(c, r)) }
        else if t.first == "palette", t.count == 2, let i = Int(t[1]) { ddApplyDrop(payload: payload, onto: .palette(i)) }
        else if t.first == "litter" { ddApplyDrop(payload: payload, onto: .litter) }
    }
    // The floating in-hand token that follows the finger.
    @ViewBuilder private func ddGhost(_ payload: String) -> some View {
        let hue: Color = {
            let t = payload.split(separator: ":").map(String.init)
            if t.first == "colour", t.count == 2 { return colourColor(t[1]) ?? .gray }
            if t.first == "cell", t.count == 3, let c = Int(t[1]), let r = Int(t[2]), let cell = scene.cellAt(c, r) { return colourColor(cell.colourID) ?? .gray }
            return .gray
        }()
        RoundedRectangle(cornerRadius: 7).fill(hue).frame(width: 40, height: 40).opacity(0.9)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.8), lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    // THE PALETTE — the 16 colours as a 4×4 of flat swatches (v1), with the DELETE box below. `litterHeight` sizes
    // the DELETE box (= a swatch in landscape, so palette+DELETE matches the grid height).
    @ViewBuilder private func ddPalette(swatch: CGFloat, litterHeight: CGFloat = 36) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { c in ddSwatch(r * 4 + c, side: swatch) }
                    }
                }
            }
            ddLitter(height: litterHeight)
        }
    }
    // THE COLOUR IDENTITY (landscape) — the swatch + colour name, with the cell count beneath; sits top-left, lined
    // up with the tops of the palette + grid (user 2026-08-09).
    // The colour whose identity/machine the page is showing: the SELECTED palette colour (shows even with 0 placed
    // cells, so a freshly-created colour labels immediately), falling back to the anchor cell's colour. (user 2026-08-09)
    var ddSelectedColourID: String? {
        if ddColourSel >= 0 && ddColourSel < colourIDs.count { return colourIDs[ddColourSel] }
        return editingCell?.colourID
    }
    // LANDSCAPE header (user 2026-08-10): the colour's EXAMPLE CELL (swatch) + its name GOLD, with the cell COUNT to
    // the right — sits ABOVE the palette grid, lined up with the top of the grid.
    @ViewBuilder private func ddColourHeader() -> some View {
        if editArmed, let cid = ddSelectedColourID {
            let hue = colourColor(cid) ?? .white
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(hue).frame(width: 26, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.55), lineWidth: 1.2))
                Text(cid.uppercased()).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(hue).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                Text("\(editSelTargets.count) cell\(editSelTargets.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else { Color.clear }
    }
    @ViewBuilder private func ddColourIdentity(showPlay: Bool = true) -> some View {
        if editArmed, let cid = ddSelectedColourID {
            let hue = colourColor(cid) ?? .white
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(hue).frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.55), lineWidth: 1.2))
                    Text(cid.uppercased()).font(.system(size: 18, weight: .black, design: .monospaced)).foregroundColor(hue).lineLimit(1).minimumScaleFactor(0.6)
                }
                Text("\(editSelTargets.count) cell\(editSelTargets.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                if showPlay { ddPlayCellButton() }   // PORTRAIT: PLAY under the labels · LANDSCAPE: PLAY sits right of the grid
            }
        }
    }
    // A palette slot: a DEFINED colour (created, or has placed cells) shows as a flat swatch; an UNDEFINED one is an
    // empty "+" slot — tap it to CREATE a new colour, or drag a grid cell onto it to FORK. Palette starts with one.
    @ViewBuilder private func ddSwatch(_ i: Int, side: CGFloat) -> some View {
        let id = colourIDs[i]
        let selected = ddColourSel == i
        let defined = ddColourShown(i)
        let hover = ddDropHover == "palette:\(i)"
        let dragging = ddActivePayload != nil                        // a source is touched/dragged → light the drop zones in its colour
        let brdr: Color = (ddDeleteMode && defined) ? Verb.delete.hue
                        : hover ? (dragging ? ddDragHue : Self.editHue)
                        : (dragging ? ddDragHue.opacity(0.65) : (selected ? .white : .white.opacity(0.12)))
        let brdrW: CGFloat = (ddDeleteMode && defined) ? 2.5 : (hover ? 3 : (dragging ? 2 : (selected ? 3 : 1)))
        Group {
            if defined {
                RoundedRectangle(cornerRadius: 8).fill(colourColor(id) ?? .gray)
                    .overlay { ddSwatchPlayhead(id, side: side) }        // THE REFILL: a downward fill-wipe on the active column
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(brdr, lineWidth: brdrW))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(ddDragPayload == "colour:\(id)" ? 0.35 : 1)  // lift the source while dragging
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.035))       // EMPTY slot — a FORK target
                    .overlay(Image(systemName: "plus").font(.system(size: side * 0.3, weight: .heavy)).foregroundColor(.white.opacity(hover ? 0.8 : 0.22)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(brdr, style: StrokeStyle(lineWidth: max(1, brdrW - 0.5), dash: [4, 3])))
            }
        }
        .frame(width: side, height: side)
        .background(ddZone("palette:\(i)"))                                             // drop-zone frame (cell → FORK/ADOPT)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if ddDeleteMode { if defined { ddToggleDeleteColour(i) } }   // DELETE MODE: tap a defined colour deletes it + its cells / re-tap reverts
            else if defined { ddSelectColour(i) } else { ddCreateColour(i) }   // tap "+" → create a new colour
        }
        .simultaneousGesture(ddTouchGesture("colour:\(id)"), including: defined ? .all : .subviews)  // touch → highlight targets
        .simultaneousGesture(ddDragGesture("colour:\(id)"), including: defined ? .all : .subviews)   // only defined colours drag
    }
    // THE PALETTE PLAYHEAD (design "THE REFILL"): while a colour has an UNMUTED cell in the ACTIVE column, its swatch
    // fills downward over the column window. v1 sweeps at the column rate (not yet phase-locked to the exact playhead).
    @ViewBuilder private func ddSwatchPlayhead(_ id: String, side: CGFloat) -> some View {
        if d.playing && ddColourInActiveColumn(id) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let live = ddBeatAnchor + tl.date.timeIntervalSince(ddBeatAnchorAt) * d.tempo / 60.0   // extrapolate the polled beat
                let musical = musicalOf(live, stepBeats: stepBeats, a: max(1.0, Double(swing) / 50.0))   // column progress runs in MUSICAL time (swing-warped)
                let raw = stepBeats > 0 ? (musical / stepBeats).truncatingRemainder(dividingBy: 1) : 0  // fraction through the current column
                let f = max(0, min(1, raw < 0 ? raw + 1 : raw))                                         // phase-locked to the column boundary
                VStack(spacing: 0) {
                    Rectangle().fill(.white.opacity(0.4)).frame(height: side * CGFloat(f))
                    Spacer(minLength: 0)
                }.allowsHitTesting(false)
            }
        }
    }
    // THE DELETE box (design "litter"): drop a colour here → delete it AND all its cells; a cell → clear that cell.
    // Always RED (user 2026-08-09), and lit throughout a drag so the delete target reads at a glance.
    private func ddLitter(height: CGFloat = 36) -> some View {
        let hover = ddDropHover == "litter"
        let flashing = ddLitterFlash != nil
        let dragging = ddActivePayload != nil                        // a source is touched/dragged → the delete zone is a live target
        let lit = hover || flashing || dragging || ddDeleteMode
        // DELETE MODE (user 2026-08-10): LONG-PRESS the box to arm delete — the box shows "DELETE", both grids go red,
        // and a tap on any cell/colour deletes it (a 2nd tap reverts); it stays armed until this box is RELEASED.
        // Otherwise: a drag makes it the drop target (trash + flash), and idle it carries the two-line instruction.
        let showDelete = dragging || flashing || ddDeleteMode
        return Group {
            if showDelete {
                VStack(spacing: 4) {
                    Image(systemName: "trash").font(.system(size: 14, weight: .heavy))
                    Text(ddLitterFlash ?? "DELETE").font(.system(size: 10, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundColor(Verb.delete.hue)
            } else {
                VStack(spacing: 1) {                                 // two lines: DRAG AND DROP big, the rest small (user 2026-08-10)
                    Text("Drag and Drop").font(.system(size: 14, weight: .heavy, design: .monospaced))
                    Text("to place and copy cells").font(.system(size: 9, weight: .heavy, design: .monospaced))
                }
                .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundColor(.white.opacity(0.55)).padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .background(RoundedRectangle(cornerRadius: 8).fill(lit ? Verb.delete.hue.opacity(ddDeleteMode || hover || flashing ? 0.18 : 0.10) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(lit ? Verb.delete.hue : .white.opacity(0.15), style: StrokeStyle(lineWidth: lit ? 2 : 1.2, dash: [4, 3]))))
        .contentShape(Rectangle())
        .background(ddZone("litter"))                                                  // drop-zone frame (a drop target only)
        // HOLD-TO-DELETE: a UIKit tracker ARMS delete mode after a hold + RELEASES it reliably when the box finger
        // lifts (SwiftUI gestures were cancelled by the second-finger cell taps → delete mode stuck). (user 2026-08-10)
        .overlay(DDHoldTracker(onArm: { ddEnterDeleteMode() }, onRelease: { ddExitDeleteMode() }))
        .animation(.easeOut(duration: 0.15), value: flashing)
    }

    // ROW SELECTORS (user 2026-08-09) — one key per grid row; a tap PAINTS the whole row with the selected colour
    // (its representative machine, or a default passthrough if unplaced). No column paint (by design).
    @ViewBuilder private func ddRowSelectors(cell: CGFloat, topInset: CGFloat, pointRight: Bool = false) -> some View {
        let tint = ddColourSel >= 0 ? (colourColor(colourIDs[ddColourSel]) ?? Color.white) : Color.white.opacity(0.25)
        VStack(spacing: 4) {
            Color.clear.frame(width: 18, height: topInset)   // align the row keys below the column-loop row
            ForEach(0..<8, id: \.self) { r in
                RoundedRectangle(cornerRadius: 4).fill(tint.opacity(ddColourSel >= 0 ? 0.6 : 0.12))
                    .overlay(Image(systemName: pointRight ? "arrow.right" : "arrow.left").font(.system(size: 9, weight: .black)).foregroundColor(.black.opacity(0.55)))
                    .frame(width: 18, height: cell)
                    .contentShape(Rectangle())
                    .onTapGesture { ddPaintRow(r) }
            }
        }
    }

    // COLUMN LOOP buttons (user 2026-08-09) — one per grid column, aligned over the grid; tap to hold/release that
    // column in the loop set (the same `laneMask` the perform grid drives). Lit = held; the active column is ringed.
    @ViewBuilder private func ddColumnLoopRow(cell size: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { c in
                let held = laneMask & (1 << UInt8(c)) != 0
                let active = d.playing && d.effColumn == c && !ddSolo   // solo freezes the timeline — no active-column ring
                RoundedRectangle(cornerRadius: 4).fill(held ? Self.editHue : Color.white.opacity(0.08))
                    .overlay(Image(systemName: "repeat").font(.system(size: 9, weight: .black)).foregroundColor(held ? .black : .white.opacity(0.4)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(active ? 0.8 : 0), lineWidth: 1.5))
                    .frame(width: size, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleLoopColumn(c) }
            }
        }
    }
    // THE GRID — flat-colour 8×8 (design v1: cells are flat colour, the grid stays calm). Tap = mute/unmute + select;
    // drag a cell → palette (FORK/ADOPT) / litter (clear) / another cell (MOVE); a colour drops here to PLACE.
    @ViewBuilder private func ddGrid(cell size: CGFloat) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { r in
                HStack(spacing: 4) { ForEach(0..<8, id: \.self) { c in ddGridCell(c, r, size: size) } }
            }
        }
    }
    @ViewBuilder private func ddGridCell(_ c: Int, _ r: Int, size: CGFloat) -> some View {
        let cell = scene.cellAt(c, r)
        let dormant = ladderDim.contains(GridView.GridPos(col: c, row: r))           // SINGLE (ladder): a non-active rung is silent → dim it
        let hover = ddDropHover == "grid:\(c):\(r)"
        let dragging = ddActivePayload != nil                                        // a source is touched/dragged → light the drop zones
        // NO grid cell is ever shown as SELECTED (user 2026-08-09) — only the hover/drag drop highlights. The selection
        // lives in the palette + machinery, never on the grid.
        let stroke: Color = ddDeleteMode ? Verb.delete.hue
                          : hover ? (dragging ? ddDragHue : Self.editHue)
                          : (dragging ? ddDragHue.opacity(0.65) : .white.opacity(0.12))
        let strokeW: CGFloat = ddDeleteMode ? 2.5 : (hover ? 3 : (dragging ? 2 : 1))
        let fill: Color = cell.flatMap { colourColor($0.colourID) } ?? Color.white.opacity(0.05)
        RoundedRectangle(cornerRadius: 5)
            .fill(fill.opacity(cell?.muted == true || dormant ? 0.28 : 1))
            .frame(width: size, height: size)
            .overlay {
                if cell?.muted == true {
                    Image(systemName: "speaker.slash.fill").font(.system(size: size * 0.3, weight: .heavy)).foregroundColor(.black.opacity(0.5))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(stroke, lineWidth: strokeW))
            .opacity(ddDragPayload == "cell:\(c):\(r)" ? 0.35 : 1)                         // lift the source while dragging
            .background(ddZone("grid:\(c):\(r)"))                                          // drop-zone frame (colour → PLACE · cell → MOVE)
            .overlay { if ddDeleteMode { RoundedRectangle(cornerRadius: 5).fill(Verb.delete.hue.opacity(0.14)) } }   // DELETE MODE red wash
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onTapGesture { if ddDeleteMode { ddToggleDeleteCell(c, r) } else { ddGridTap(c, r) } }   // DELETE MODE: tap deletes / re-tap reverts
            .simultaneousGesture(ddTouchGesture("cell:\(c):\(r)"), including: cell != nil ? .all : .subviews)  // touch → highlight targets
            .simultaneousGesture(ddDragGesture("cell:\(c):\(r)"), including: cell != nil ? .all : .subviews)   // only occupied cells drag
    }

    // THE MACHINERY — the selected colour's flow diagram (full-width), with the LIBRARY button to the LEFT of the
    // receivers and RANDOMIZE · MUTATE stacked to the RIGHT of them (user 2026-08-09).
    // The cell the machinery draws: a PLACED cell of the selected colour, else a SYNTHETIC cell for the selected
    // colour (so the machine is ALWAYS visible — a freshly-created, not-yet-placed colour still shows its chain via
    // the 3-tier resolution, and edits are colour-scoped so they persist). (user 2026-08-09)
    private var ddMachineryCell: Cell? {
        if let c = editingCell { return c }
        guard let cid = ddSelectedColourID else { return nil }
        // No placed cell yet: show the machine on a synthetic cell seeded with the page's STICKY routing, so the
        // receiver / emitter buttons DISPLAY the current default AND visibly respond when tapped (the tap updates the
        // sticky — see editPointedCell — and a later placement inherits it). Without this the buttons no-op'd because
        // editCellsOfColour had no cells to write to. (user 2026-08-10)
        var c = Cell(colourID: cid)
        c.inputReceiver = ddStickyReceiver
        c.buses = ddStickyBuses.isEmpty ? [] : ddStickyBuses
        return c
    }
    @ViewBuilder private func ddMachinery(width: CGFloat, landscape: Bool = false) -> some View {
        if editArmed, let cell = ddMachineryCell {
            if landscape {
                flowDiagram(cell, width: width)
                    .overlay(alignment: .topLeading) { ddPlayCellButton().padding(.leading, 10).padding(.top, 14) }   // PLAY: THIS CELL — where LIBRARY was (user 2026-08-10)
            } else {
                flowDiagram(cell, width: width)
                    .overlay(alignment: .topLeading) { ddLibraryButton().padding(.leading, 10).padding(.top, 14) }
                    .overlay(alignment: .topTrailing) {
                        VStack(spacing: 6) { ddRandomizeButton(); ddMutateButton() }.padding(.trailing, 10).padding(.top, 6)
                    }
            }
        } else {
            Text("Tap a colour to edit its machine")
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    // LANDSCAPE ACTION BOX (user 2026-08-10): a box EQUAL in size to the left palette column, on the RIGHT of the top
    // band, holding RANDOMIZE · MUTATE · LIBRARY (library at the bottom). Measured (ddZone "actionBox") so `ddActionLine`
    // can draw a connector from it to the FINAL processor box (measured as "procLast" in flowDiagram).
    @ViewBuilder private func ddActionBox() -> some View {
        VStack(spacing: 10) {
            ddRandomizeButton().frame(maxWidth: .infinity)
            ddMutateButton().frame(maxWidth: .infinity)
            ddLibraryButton().frame(maxWidth: .infinity)     // LIBRARY at the bottom (user 2026-08-10)
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1).padding(.vertical, 2)
            ddMacroControls()                                // THE DICE: 4 spring sliders + 4 binary buttons (user 2026-08-10)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04))      // FAINT GREY (user 2026-08-10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5]))))   // faint dotted, like the other lines
        .background(ddZone("actionBox"))                      // measure for the connector line
    }
    // THE DICE macro controls (user 2026-08-10): 4 SPRING sliders (each morphs a generated + evaluated continuous macro,
    // reverting to 0 on release) + 4 BINARY buttons (each toggles an evaluated bypass/type-switch macro). Inert until
    // the selected colour has a live roll (RANDOMIZE). Placed in the action box (landscape) / below the machinery (portrait).
    @ViewBuilder func ddMacroControls() -> some View {
        let active = ddDiceActive
        VStack(spacing: 8) {
            HStack(spacing: 8) {                                    // 4 VERTICAL sliders in a row, smaller (user 2026-08-11)
                ForEach(0..<4, id: \.self) { i in ddMacroSlider(i, enabled: active && i < (ddDice?.sliders.count ?? 0)) }
            }.frame(height: 52)
            VStack(spacing: 6) {                                    // 4 LARGER buttons, 2×2 (user 2026-08-11)
                HStack(spacing: 6) { ddMacroButton(0, active: active); ddMacroButton(1, active: active) }
                HStack(spacing: 6) { ddMacroButton(2, active: active); ddMacroButton(3, active: active) }
            }
        }
    }
    private func ddMacroSlider(_ i: Int, enabled: Bool) -> some View {   // VERTICAL, small (up = 1; spring to 0)
        let hue = ddSelHue
        return GeometryReader { g in
            let h = g.size.height
            let v = ddDiceSliders[i]
            ZStack(alignment: .bottom) {
                Capsule().fill(.white.opacity(0.12)).frame(width: 5)
                Capsule().fill(enabled ? hue : .white.opacity(0.15)).frame(width: 5, height: max(5, h * v))
                Circle().fill(enabled ? Color.white : .white.opacity(0.4)).frame(width: 12, height: 12)
                    .offset(y: -min(h - 12, max(0, h * v - 6)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g2 in guard enabled else { return }; ddDiceSliders[i] = max(0, min(1, 1 - g2.location.y / max(1, h))); ddApplyDice() }
                .onEnded { _ in guard enabled else { return }; ddDiceSliders[i] = 0; ddApplyDice() })   // SPRING back to 0
        }.frame(width: 26)
    }
    private func ddMacroButton(_ i: Int, active: Bool) -> some View {
        let macro = (active && i < (ddDice?.buttons.count ?? 0)) ? ddDice?.buttons[i] : nil
        let on = ddDiceButtons[i], enabled = macro != nil
        return Button {
            guard enabled else { return }
            ddDiceButtons[i].toggle(); ddApplyDice()
        } label: {
            Text(macro?.label ?? "—").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5)
                .foregroundColor(on ? .black : (enabled ? ddSelHue : .white.opacity(0.3)))
                .frame(maxWidth: .infinity).frame(height: 34)      // LARGER (user 2026-08-11)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? ddSelHue : ddSelHue.opacity(enabled ? 0.12 : 0.04))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(ddSelHue.opacity(enabled ? 0.5 : 0.15), lineWidth: 1)))
        }.buttonStyle(.plain).disabled(!enabled)
    }
    // The dashed connector from the action box to the FINAL processor slot — drawn at the page level in "dd" space
    // (both endpoints are measured frames), so it spans the top band → the machinery below. (user 2026-08-10)
    @ViewBuilder func ddActionLine() -> some View {
        if editArmed, let a = ddZones["actionBox"], let p = ddZones["procLast"] {
            Path { path in
                path.move(to: CGPoint(x: p.midX, y: p.minY))     // the FINAL processor box's TOP-CENTRE
                path.addLine(to: CGPoint(x: p.midX, y: a.maxY))  // straight UP to join the box (vertical) (user 2026-08-10)
            }
            .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5]))   // FAINT GREY, dotted like the other lines (user 2026-08-10)
            .allowsHitTesting(false)
        }
    }
    /// The SELECTED colour's hue — tints the DD action buttons (PLAY · LIBRARY · RANDOMIZE · MUTATE); falls back to the
    /// edit orchid when nothing resolves. (user 2026-08-09)
    private var ddSelHue: Color { ddSelectedColourID.flatMap { colourColor($0) } ?? Self.editHue }
    // PLAY: THIS CELL (user 2026-08-09) — isolate the selected cell's colour and freeze the timeline on its column, so
    // ONLY that machine sounds, ungated by the grid sequence (the grid's active column is ignored). Toggle.
    private func ddPlayCellButton() -> some View {
        let on = ddSolo
        return Button {
            ddSolo.toggle()
            if ddSolo { ddEngageSolo() } else { au?.clearColourSolo() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "speaker.wave.2.fill" : "play.fill").font(.system(size: 11, weight: .heavy))
                Text("PLAY: THIS CELL").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(on ? .black : ddSelHue).padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? ddSelHue : ddSelHue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(ddSelHue.opacity(0.5), lineWidth: 1)))
        }.buttonStyle(.plain)
    }
    // LIBRARY — open the cell library (left of the receivers).
    private func ddLibraryButton() -> some View {
        Button { openCellLibrary() } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill").font(.system(size: 12, weight: .heavy))
                Text("LIBRARY").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(ddSelHue).padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(ddSelHue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(ddSelHue.opacity(0.5), lineWidth: 1)))
        }.buttonStyle(.plain)
    }
    // RANDOMIZE — reroll the selected colour's PROCESSOR CHAIN + params (user 2026-08-09; receivers/emitters kept).
    private func ddRandomizeButton() -> some View {
        Button { ddRandomize() } label: {
            HStack(spacing: 6) {
                Image(systemName: "die.face.5.fill").font(.system(size: 12, weight: .heavy))
                Text("RANDOMIZE").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(ddSelHue).padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(ddSelHue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(ddSelHue.opacity(0.5), lineWidth: 1)))
        }.buttonStyle(.plain)
    }
    // MUTATE — placeholder (a nudged variation of the colour, to come). Inert dashed chip for now.
    private func ddMutateButton() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars").font(.system(size: 12, weight: .heavy))
            Text("MUTATE").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundColor(ddSelHue.opacity(0.4)).padding(.horizontal, 12).frame(height: 30)   // tinted but dashed/dim = still a placeholder
        .background(RoundedRectangle(cornerRadius: 7).strokeBorder(ddSelHue.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
    }

    // MARK: - selection helpers

    private func ddColourIsPlaced(_ id: String) -> Bool {
        for c in 0..<8 { for r in 0..<8 where scene.cellAt(c, r)?.colourID == id { return true } }
        return false
    }
    /// A palette slot shows a colour when it's been CREATED (defined flag) or has placed cells; else it's a "+" slot.
    private func ddColourShown(_ i: Int) -> Bool {
        (i < docColours.count && docColours[i].defined == true) || ddColourIsPlaced(colourIDs[i])
    }
    /// Tap a "+" slot → CREATE a new colour (mark it defined; its default machine is the colour's own head). It shows
    /// as a swatch, selected; drag it onto the grid to place + edit (no cells yet, so the machinery invites a place).
    func ddCreateColour(_ i: Int) {
        guard i >= 0 && i < colourIDs.count else { return }
        au?.editDocument { doc in if i < doc.colours.count { doc.colours[i].defined = true } }
        refreshFromDocument()
        ddColourSel = i
        ddScopeToColour(colourIDs[i], anchor: nil)
    }
    private func ddColourInActiveColumn(_ id: String) -> Bool {
        // PLAY: THIS CELL — only the SOLOED colour is sounding (regardless of mute/dormant), so only it sweeps.
        if ddSolo { return id == ddSelectedColourID }
        let col = d.effColumn
        guard col >= 0 && col < 8 else { return false }
        // SINGLE (ladder): a DORMANT rung isn't firing, so its colour must NOT sweep — only the active rung's colour does.
        for r in 0..<8 where !ladderDim.contains(GridView.GridPos(col: col, row: r)) {
            if let cell = scene.cellAt(col, r), cell.colourID == id, !cell.muted { return true }
        }
        return false
    }
    private func ddRepresentativeCell(_ id: String) -> Cell? {
        for c in 0..<8 { for r in 0..<8 { if let cell = scene.cellAt(c, r), cell.colourID == id { return cell } } }
        return nil
    }
    private func ddColourCells(_ id: String) -> [GridView.GridPos] {
        var out: [GridView.GridPos] = []
        for c in 0..<8 { for r in 0..<8 where scene.cellAt(c, r)?.colourID == id { out.append(GridView.GridPos(col: c, row: r)) } }
        return out
    }
    /// THE PER-COLOUR MODEL (user 2026-08-09): a colour IS a machine — selecting one scopes the edit to EVERY cell of
    /// that colour, so every machinery edit (add/remove/params/split) applies colour-wide. The anchor cell just drives
    /// what the flow diagram DISPLAYS. `editPointedCell`/`editChop`/`{add,edit,remove}SlotCells` all fan out to `sel`.
    private func ddScopeToColour(_ id: String, anchor: (Int, Int)?) {
        let cells = ddColourCells(id)
        sel.reset(); for p in cells { sel.add(p) }
        if let a = anchor { selCol = a.0; selRow = a.1 }
        else if let first = cells.first { selCol = first.col; selRow = first.row }
        else { selCol = -1; selRow = -1 }
        if ddSolo { ddEngageSolo() }   // PLAY: THIS CELL follows the selection
        ddCaptureStickyRouting()   // remember the last-chosen receiver + emitters (the default for the next fresh cell)
    }
    /// STICKY ROUTING (user 2026-08-10): a fresh cell inherits the LAST receiver + emitters chosen on the page (else
    /// the model default R1 + Emitter A). Captured from the anchor cell on select + after a routing edit.
    /// Engage PLAY: THIS CELL for the current selection. A PLACED cell freezes on its grid slot; an UNPLACED colour
    /// (no cell yet) plays via a SYNTHETIC preview cell at an empty slot (its sticky receiver + emitters + machine).
    /// If neither is possible (no colour selected, or the grid is full for a preview) the toggle springs back off.
    func ddEngageSolo() {
        if selCol >= 0, selRow >= 0 { au?.setColourSolo(col: selCol, row: selRow); return }
        if let cid = ddSelectedColourID, au?.setColourSoloPreview(colourID: cid, inputReceiver: ddStickyReceiver, buses: Array(ddStickyBuses)) == true { return }
        ddSolo = false; au?.clearColourSolo()
    }
    func ddCaptureStickyRouting() {
        guard let c = editingCell else { return }
        ddStickyReceiver = c.inputReceiver ?? 0
        ddStickyBuses = c.buses.isEmpty ? [.a] : c.buses
    }
    /// The placed cells of a colour — the cross-file-visible read `editPointedCell` uses to detect an unplaced colour.
    func ddColourCellsPublic(_ id: String) -> [GridView.GridPos] { ddColourCells(id) }
    /// UNPLACED-colour routing: apply a cell mutation to a synthetic cell carrying the current sticky routing, then
    /// read the result back into the sticky — so a receiver/emitter tap on a not-yet-placed colour sticks + shows.
    func ddApplyStickyRoutingMutation(_ id: String, _ mutate: (inout Cell) -> Void) {
        var c = Cell(colourID: id)
        c.inputReceiver = ddStickyReceiver
        c.buses = ddStickyBuses
        mutate(&c)
        ddStickyReceiver = c.inputReceiver ?? 0
        ddStickyBuses = c.buses
    }
    /// A fresh cell of `id` with the STICKY routing (last chosen · else R1/Emitter A) and the colour's machine (nil → template).
    private func ddNewborn(_ id: String) -> Cell {
        var c = newbornCell()
        c.colourID = id; c.processors = nil
        c.inputReceiver = ddStickyReceiver
        c.buses = ddStickyBuses.isEmpty ? [.a] : ddStickyBuses
        return c
    }
    private func ddSelect(_ c: Int, _ r: Int) {
        guard let cell = scene.cellAt(c, r) else { return }
        if let i = colourIDs.firstIndex(of: cell.colourID) { ddColourSel = i }
        ddScopeToColour(cell.colourID, anchor: (c, r))
    }
    /// Select a palette colour → scope the machinery to the whole colour (anchored on its first placed cell). No
    /// placed cell → nothing to edit yet (place it via a row selector or a drag).
    func ddSelectColour(_ i: Int) {
        guard i >= 0 && i < colourIDs.count else { return }
        ddColourSel = i
        ddScopeToColour(colourIDs[i], anchor: nil)
    }
    /// Open the DRAG&DROP page with a colour selected: keep a valid current selection, else fall back to GOLD (the
    /// default colour that's always present). Re-scopes so the selection picks up any newly-placed cells. (user 2026-08-09)
    func ddEnsureSelection() {
        let valid = ddColourSel >= 0 && ddColourSel < colourIDs.count && ddColourShown(ddColourSel)
        ddSelectColour(valid ? ddColourSel : (colourIDs.firstIndex(of: "gold") ?? 0))
    }
    /// Grid tap. SINGLE (ladder) — the tap chooses the column's ONE active rung (a populated cell plays, an EMPTY cell
    /// silences the column), reusing the GRID page's `armLadderRung`; MULTI — the tap MUTES/UNMUTES the cell. Either
    /// way, tapping a populated cell SELECTS its colour so the palette + machinery follow. (user 2026-08-09)
    func ddGridTap(_ col: Int, _ row: Int) {
        if let pc = ddPaintColour {                          // a palette colour is HELD → PAINT the tapped cell with it (user 2026-08-09)
            if let i = colourIDs.firstIndex(of: pc) { ddColourSel = i }
            ddPaintCell(col, row, pc)
            return
        }
        if ladderMode {
            if scene.cellAt(col, row) != nil { ddSelect(col, row) }
            armLadderRung(col, row)                              // one cell at a time — switch/mute the column's active rung
            return
        }
        guard scene.cellAt(col, row) != nil else { return }
        au?.editScene { $0.cells[col][row]?.muted.toggle() }
        refreshFromDocument(); ddSelect(col, row)
    }
    /// Row-selector PAINT — a 3-press cycle for the selected colour (user 2026-08-09):
    ///   1st press  → fill only the EMPTY cells (populated cells kept).
    ///   2nd press  → fill the WHOLE row, IF the row is now mixed (>1 colour); else revert (as a 3rd press would).
    ///   3rd press  → revert the row to its original state. Switching row/colour restarts the cycle.
    func ddPaintRow(_ r: Int) {
        guard ddColourSel >= 0 else { return }
        let colour = ddColourSel, id = colourIDs[colour]
        if let cyc = ddRowCycle, cyc.row == r, cyc.colour == colour {
            if cyc.phase == 1 && ddRowDistinctColours(r) > 1 {
                ddFillRow(r, id, wholeRow: true)                                       // press 2: mixed row → fill it
                ddRowCycle = DDRowCycle(row: r, colour: colour, phase: 2, original: cyc.original)
            } else {
                ddRevertRow(r, cyc.original); ddRowCycle = nil                         // press 2 (uniform) or press 3 → revert
            }
        } else {
            let original = (0..<8).map { scene.cellAt($0, r) }                         // press 1: capture + fill empties
            ddFillRow(r, id, wholeRow: false)
            ddRowCycle = DDRowCycle(row: r, colour: colour, phase: 1, original: original)
        }
    }
    /// Paint one cell with a colour (its machine + routing via the colour's representative / template). In SINGLE it
    /// becomes its column's active rung so it's visible + plays. Used by the HELD-colour paint gesture. (user 2026-08-09)
    private func ddPaintCell(_ c: Int, _ r: Int, _ id: String) {
        let template = ddCellOfColour(id)
        au?.editScene { s in s.cells[c][r] = template }
        if ladderMode {
            au?.editScene(record: false) { s in
                var ar = s.activeRow ?? [Int?](repeating: nil, count: 8); while ar.count < 8 { ar.append(nil) }
                ar[c] = r; s.activeRow = ar
            }
        }
        refreshFromDocument()
    }
    private func ddCellOfColour(_ id: String) -> Cell {
        var cell = ddRepresentativeCell(id) ?? ddNewborn(id)           // a colour with cells copies its routing; a fresh one takes the STICKY default
        cell.colourID = id; cell.muted = false; cell.processors = nil   // inherit the colour's machine (per-colour model)
        return cell
    }
    private func ddFillRow(_ r: Int, _ id: String, wholeRow: Bool) {
        let template = ddCellOfColour(id)
        au?.editScene { s in for c in 0..<8 where wholeRow || s.cells[c][r] == nil { s.cells[c][r] = template } }
        // SINGLE (ladder): make the painted row the ACTIVE rung wherever it now sits, so a just-added colour is visible
        // + plays (otherwise it defaults to dormant behind an existing rung and reads as "not added"). (user 2026-08-09)
        if ladderMode {
            au?.editScene(record: false) { s in
                var ar = s.activeRow ?? [Int?](repeating: nil, count: 8); while ar.count < 8 { ar.append(nil) }
                for c in 0..<8 where s.cellAt(c, r)?.colourID == id { ar[c] = r }
                s.activeRow = ar
            }
        }
        refreshFromDocument()
        ddScopeToColour(id, anchor: nil)                     // the palette + machinery follow the painted colour (confirms the add)
    }
    private func ddRevertRow(_ r: Int, _ original: [Cell?]) {
        au?.editScene { s in for c in 0..<8 { s.cells[c][r] = c < original.count ? original[c] : nil } }
        refreshFromDocument()
    }
    private func ddRowDistinctColours(_ r: Int) -> Int { Set((0..<8).compactMap { scene.cellAt($0, r)?.colourID }).count }

    // MARK: - the six drag landings

    private func ddApplyDrop(payload: String, onto target: DDTarget) {
        let parts = payload.split(separator: ":").map(String.init)
        if parts.first == "colour", parts.count == 2 {
            let id = parts[1]
            switch target {
            case .grid(let c, let r): ddPlace(id, at: c, r)          // palette → grid = PLACE
            case .litter:             ddDeleteColour(id)             // colour → litter = DELETE the colour + its cells
            case .palette:            break                          // palette → palette reorg (deferred)
            }
        } else if parts.first == "cell", parts.count == 3, let sc = Int(parts[1]), let sr = Int(parts[2]) {
            switch target {
            case .grid(let dc, let dr): if sc != dc || sr != dr { moveCell((sc, sr), (dc, dr)); ddSelect(dc, dr) }   // grid → grid = MOVE
            case .palette(let i):       ddRecolour(sc, sr, toSlot: i)   // grid → palette = ADOPT (occupied) / FORK (empty)
            case .litter:               ddClearCell(sc, sr)             // grid cell → litter = clear that cell
            }
        }
    }
    private func ddPlace(_ id: String, at c: Int, _ r: Int) {
        let template = ddRepresentativeCell(id) ?? ddNewborn(id)       // fresh colour → the STICKY routing (last chosen · else R1/Emitter A)
        au?.editScene { s in
            var cell = template
            cell.colourID = id; cell.muted = false
            s.cells[c][r] = cell
        }
        refreshFromDocument(); ddSelect(c, r)
    }
    /// Grid cell dropped on a palette slot: OCCUPIED slot = ADOPT (the cell takes that colour's machine); EMPTY
    /// (unused) slot = FORK (the cell keeps its own machine, just recolours to the unused colour).
    private func ddRecolour(_ sc: Int, _ sr: Int, toSlot i: Int) {
        guard i >= 0 && i < colourIDs.count else { return }
        let id = colourIDs[i]
        if ddColourIsPlaced(id), let rep = ddRepresentativeCell(id) {
            au?.editScene { s in                                                                    // ADOPT the target colour's machine
                guard var cell = s.cellAt(sc, sr) else { return }
                let keepMuted = cell.muted; cell = rep; cell.muted = keepMuted
                cell.colourID = id; cell.processors = nil                                           // inherit the target colour's TEMPLATE (no stale override → editor agrees)
                s.cells[sc][sr] = cell
            }
        } else {
            au?.forkCellToColour(col: sc, row: sr, colourIndex: i)                                  // FORK: the FRESH colour BECOMES the source cell's machine
        }
        refreshFromDocument(); ddColourSel = i; ddSelect(sc, sr)
    }
    private func ddClearCell(_ c: Int, _ r: Int) {
        guard scene.cellAt(c, r) != nil else { return }
        au?.editScene { $0.cells[c][r] = nil }
        refreshFromDocument()
        if selCol == c && selRow == r { selCol = -1; selRow = -1; sel.reset() }
        ddFlashLitter("−1 cell")
    }
    private func ddDeleteColour(_ id: String) {
        var removed = 0
        au?.editScene { s in
            for c in 0..<8 { for r in 0..<8 where s.cellAt(c, r)?.colourID == id { s.cells[c][r] = nil; removed += 1 } }
        }
        au?.editDocument { doc in if let ci = doc.colours.firstIndex(where: { $0.colourID == id }) { doc.colours[ci].defined = false } }   // un-create → back to a "+" slot
        refreshFromDocument()
        if ddColourSel >= 0 && colourIDs[ddColourSel] == id { ddColourSel = -1; selCol = -1; selRow = -1; sel.reset() }
        ddFlashLitter("−1 colour · \(removed) cell\(removed == 1 ? "" : "s")")
    }
    private func ddFlashLitter(_ msg: String) {
        ddLitterFlash = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if ddLitterFlash == msg { ddLitterFlash = nil } }
    }

    // MARK: - DELETE MODE (user 2026-08-10) — hold the DELETE box, tap cells/colours to delete (toggle-revert)

    /// Arm delete mode (the DELETE box was long-pressed). Cancels any in-flight drag so the red highlight reads cleanly.
    func ddEnterDeleteMode() {
        ddResetDrag()
        ddDeleteStashCells = [:]; ddDeleteStashColours = [:]
        ddDeleteMode = true
    }
    /// Disarm delete mode (the DELETE box was released) — the deletions stand; the stash is dropped (no more reverting).
    func ddExitDeleteMode() {
        ddDeleteMode = false
        ddDeleteStashCells = [:]; ddDeleteStashColours = [:]
    }
    /// DELETE MODE tap on a grid cell: delete it (stash the cell), or — if already deleted this hold — put it back.
    func ddToggleDeleteCell(_ c: Int, _ r: Int) {
        let key = "\(c):\(r)"
        if let stashed = ddDeleteStashCells[key] {                 // was deleted → RESTORE
            au?.editScene { s in if s.inBounds(c, r) { s.cells[c][r] = stashed } }
            ddDeleteStashCells[key] = nil
            refreshFromDocument()
        } else if let cell = scene.cellAt(c, r) {                  // present → DELETE
            ddDeleteStashCells[key] = cell
            au?.editScene { s in if s.inBounds(c, r) { s.cells[c][r] = nil } }
            refreshFromDocument()
            if selCol == c && selRow == r { selCol = -1; selRow = -1; sel.reset() }
        }
    }
    /// DELETE MODE tap on a palette colour: delete it + all its cells (stash them), or — if already deleted — restore.
    func ddToggleDeleteColour(_ i: Int) {
        guard i >= 0 && i < colourIDs.count else { return }
        let id = colourIDs[i]
        if let stashed = ddDeleteStashColours[id] {                // was deleted → RESTORE the colour + its cells
            au?.editScene { s in for x in stashed where s.inBounds(x.col, x.row) { s.cells[x.col][x.row] = x.cell } }
            au?.editDocument { doc in if let ci = doc.colours.firstIndex(where: { $0.colourID == id }) { doc.colours[ci].defined = true } }
            ddDeleteStashColours[id] = nil
            refreshFromDocument()
        } else if ddColourShown(i) {                               // present → DELETE (stash every placed cell first)
            var stash: [DDCellAt] = []
            for c in 0..<8 { for r in 0..<8 { if let cell = scene.cellAt(c, r), cell.colourID == id { stash.append(DDCellAt(col: c, row: r, cell: cell)) } } }
            ddDeleteStashColours[id] = stash
            au?.editScene { s in for x in stash where s.inBounds(x.col, x.row) { s.cells[x.col][x.row] = nil } }
            au?.editDocument { doc in if let ci = doc.colours.firstIndex(where: { $0.colourID == id }) { doc.colours[ci].defined = false } }
            refreshFromDocument()
            if ddColourSel == i { ddColourSel = -1; selCol = -1; selRow = -1; sel.reset() }
        }
    }

    // MARK: - RANDOMIZE (reroll the selected colour's chain)

    func ddRandomize() {
        // THE DICE (user 2026-08-10): roll a LONG chain where every slot CONTRIBUTES (evaluated offline through the
        // Router), plus 4 continuous + 4 binary MACROS whose impact is evaluated — bound to the spring sliders + the
        // buttons. Reroll the COLOUR'S machine (GLOBAL): `withChainColour` writes the templateChain + clears per-cell
        // overrides, so every cell of the colour renders the one rerolled chain.
        guard editArmed else { return }
        let cid = editingCell?.colourID ?? (ddColourSel >= 0 && ddColourSel < colourIDs.count ? colourIDs[ddColourSel] : nil)
        guard let colourID = cid else { return }
        var rng = SystemRandomNumberGenerator()
        let result = Dice.roll(target: 5, using: &rng)
        guard !result.base.isEmpty else { return }
        ddDice = result; ddDiceColour = colourID
        ddDiceSliders = [0, 0, 0, 0]; ddDiceButtons = [false, false, false, false]
        au?.withChainColour(colourID) { $0 = result.base }
        refreshFromDocument()
    }
    /// Apply the live macro controls (spring sliders + binary buttons) onto the rolled colour's chain.
    func ddApplyDice() {
        guard let r = ddDice, let cid = ddDiceColour else { return }
        let chain = r.chain(sliderVals: ddDiceSliders, buttonOn: ddDiceButtons)
        au?.withChainColour(cid) { $0 = chain }
        refreshFromDocument()
    }
    /// The dice macros drive the CURRENTLY-SELECTED colour only when its last roll is live (else the controls are inert).
    var ddDiceActive: Bool { ddDice != nil && ddDiceColour != nil && ddDiceColour == ddSelectedColourID }
}

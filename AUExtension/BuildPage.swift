import SwiftUI

// THE BUILD PAGE — design: Docs/AcceptanceCriteria/AcceptanceCriteria-build-page-two-grid-flow.md +
// -build-page-iteration-3.md + -build-page-iteration-4.md + Docs/mockup-build-three-grids-landscape.html
// (user 2026-08-11). The new PRIMARY workshop and default landing tab. Destined to REPLACE the DRAG&DROP + PROCESSORS
// (cell-edit) pages (both kept live until it supersedes them).
//
// THE FORM (user 2026-08-11: THREE EQUAL COLUMNS + the machinery strip along the bottom; NO focus highlight):
//   • LEFT COLUMN (the build flow, top→bottom): [● PLAY THIS CELL] → [PART ▾][+ NEW] → 1·INPUT (R1–R4, MIDI ⎓ | PIANO
//     ⌨ per door; a PIANO door reveals its octave keyboard) → 2·THE CAST (the FULL 4×4 palette, 16 slots) · 🎲
//     RANDOMIZE (the chain's die = roll the colour's machine) → 3·OUTPUT (A–D) → [APPLY TO STAGING →] → LITTER.
//   • MIDDLE COLUMN — STAGING (the workshop 8×8: row rail · loop keys · variation rows), with the VERBS in their own
//     box BELOW: [PLACE · MOVE · DELETE] (spring-held workbench verbs) then [APPLY TO PLAY → · MUTATE · 🎲 RE-ROLL].
//   • RIGHT COLUMN — the PLAY grid: five FIXED bands. THE TARGET DECIDES THE VERB: APPLY TO PLAY arms the bands →
//     tap a LANE = FLATTEN · tap a LADDER = COPY ROWS · tap FREE = takes land · long-press a ladder = flatten-into-row.
//   • MACHINERY STRIP (bottom, full width) — the chain: ID · receiver box · slots + ghost · emitter box.
//
// ┌─ BUILD STATUS ─ INCREMENT 1 (this file): LAYOUT SKELETON — placeholder content, NO engine wiring. Every dimension
// │ is a named constant in `BuildGeom`; each region is its own helper (placement edits are one-liners). NEXT (region
// │ by region): left-column I/O + cast → staging roll (reuse Dice) → the PLACE/MOVE/DELETE verbs (spring-hold + engine;
// │ retires the DRAG&DROP tab) → APPLY TO PLAY arming + the band-decides-verb landings → the real machinery snake.
// │ Deferred here: the PIANO keyboard is a placeholder; the real voice behind the buttons.  ──────────────────────────┘

// PLACEMENT KNOBS — every geometry number lives here so layout tweaks are one-liners.
private enum BuildGeom {
    static let colGap:   CGFloat = 10       // gap between the three equal columns
    static let cellMin:  CGFloat = 18       // grid cell clamp (both 8×8 grids share one cell size)
    static let cellMax:  CGFloat = 34
    static let cellGap:  CGFloat = 4         // inter-cell gap
    static let seam:     CGFloat = 2        // the gap between play bands
    static let barH:     CGFloat = 76       // the machinery snake bar height
    static let playCalm: Double = 0.45      // the PLAY grid CALMS — dimmer cells
    static let castSwatch: CGFloat = 28     // the cast palette swatch (8 across · 4 down)
    static let castGap:    CGFloat = 4
    static var castW: CGFloat { castSwatch * 8 + castGap * 7 }   // the cast's total width — INPUT/OUTPUT rows match it
}

// Placeholder cast hues (mockup palette). Real colours come from the part's cast when the palette is wired.
private let buildHues: [Color] = [
    Color(red: 0.91, green: 0.70, blue: 0.23),   // amber
    Color(red: 0.19, green: 0.83, blue: 0.91),   // cyan
    Color(red: 0.29, green: 0.49, blue: 1.00),   // blue
    Color(red: 0.91, green: 0.36, blue: 0.44),   // red
    Color(red: 0.35, green: 0.84, blue: 0.48),   // green
    Color(red: 0.69, green: 0.42, blue: 0.91),   // purple
]
private let buildPanel = Color(red: 0.08, green: 0.09, blue: 0.11)
private let buildCell  = Color(red: 0.10, green: 0.12, blue: 0.15)
private let buildDim   = Color(white: 0.36)
private let buildPink  = Color(red: 0.94, green: 0.41, blue: 0.85)
private let buildCyan  = Color(red: 0.19, green: 0.83, blue: 0.91)

// iteration 4: the spring-held workbench verbs that replace the drag (the house law). Skeleton: tap arms/disarms.
enum BuildVerb: String { case place = "PLACE", move = "MOVE", delete = "DELETE" }

extension DiagView {

    @ViewBuilder func buildPage(_ size: CGSize) -> some View {
        // AUv3 views get an initial ZERO / degenerate layout pass; laying the grids out then would compute a NEGATIVE
        // column width → SwiftUI's fatal "Invalid frame dimension" (the plugin fails to load in AUM). Draw nothing
        // until a real, finite size arrives.
        if size.width.isFinite, size.height.isFinite, size.width > 80, size.height > 80 {
            if size.width > size.height { buildLandscape(size) } else { buildPortrait(size) }
        } else {
            Color.clear
        }
    }

    // The selected colour's real hue (the cast selection drives the machine ID + grid tints). Falls back to cyan.
    fileprivate var buildSelHue: Color { colourColor(ddSelectedColourID ?? "") ?? buildCyan }

    // ── LANDSCAPE: three EQUAL columns (palette · staging · play) over the full-width machinery strip ──────────────
    @ViewBuilder private func buildLandscape(_ size: CGSize) -> some View {
        let avail = max(1, size.width - BuildGeom.colGap * 2 - 20)
        let leftW = max(1, avail / 3 * 0.8)                        // the MACHINE column is 20% narrower than an equal third
        let gridColW = max(1, (avail - leftW) / 2)                 // staging + play split the reclaimed width
        // the PERFORM grid is widest: LEFT part buttons + 8 grid cells + RIGHT per-row buttons = 10 cells (+ 9 gaps).
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (gridColW - BuildGeom.cellGap * 9) / 10))
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: BuildGeom.colGap) {
                // AnyView boundaries: opaque `some View` types get INLINED into the parent's concrete type, so the
                // whole page collapses into ONE giant nested generic whose metadata instantiation overflows the Swift
                // demangler's stack (SIGSEGV opening BUILD). AnyView is a nominal type the demangler won't recurse
                // through — each column's type is instantiated separately + bounded.
                AnyView(buildPaletteColumn().frame(width: leftW, alignment: .center))
                AnyView(buildStagingColumn(cell: cell).frame(width: gridColW, alignment: .center))
                AnyView(buildPlayColumn(cell: cell).frame(width: gridColW, alignment: .center))
            }
            AnyView(buildMachinery())
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── PORTRAIT: height is abundant → a plain stack (palette → staging → play → machinery) ────────────────────────
    @ViewBuilder private func buildPortrait(_ size: CGSize) -> some View {
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (size.width - BuildGeom.cellGap * 9 - 24) / 10))
        VStack(spacing: 12) {
            AnyView(buildPaletteColumn())          // AnyView boundaries — see buildLandscape's note (metadata-stack overflow)
            AnyView(buildStagingColumn(cell: cell))
            AnyView(buildPlayColumn(cell: cell))
            AnyView(buildMachinery())
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── LEFT COLUMN: play-cell · part · input(+keyboard) · cast 4×4 (+🎲) · output · APPLY TO STAGING · litter ──────
    // IMPORTANT: keep this VStack SHALLOW — the INPUT/CAST/OUTPUT groups are SEPARATE opaque sub-views. A single
    // deeply-nested SwiftUI view type here makes the Swift runtime's type-metadata demangler recurse until it
    // overflows the stack when the AU instantiates the view → SIGSEGV the moment BUILD opens (device crash 2026-08-11).
    @ViewBuilder private func buildPaletteColumn() -> some View {
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THIS MACHINE", active: ddSolo, action: { buildToggleMachineAudition() }))
            AnyView(buildPartHeader())
            AnyView(buildInputSection())
            AnyView(buildCastSection())
            AnyView(buildOutputSection())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder private func buildInputSection() -> some View {
        let recvs = au?.uiReceivers() ?? []
        let sel = buildSelReceiver
        let piano = sel < recvs.count && recvs[sel].latchPianoResolved
        VStack(alignment: .center, spacing: 8) {
            buildStep("1 · INPUT")
            HStack(spacing: 4) {                                   // R1–R4: pick the door (⌨ piano · ⎓ MIDI); the face below edits it
                ForEach(0..<4, id: \.self) { i in
                    let isPiano = i < recvs.count && recvs[i].latchPianoResolved
                    buildIOChip("R\(i + 1) \(isPiano ? "⌨" : "⎓")", on: i == sel, keys: isPiano, fill: true) { buildSelectDoor(i) }
                }
            }
            .frame(width: BuildGeom.castW)                         // match the receivers row to the cast palette width
            HStack(spacing: 5) {                                   // the SELECTED door's SOURCE toggle: DIN (MIDI in) | in-app piano; the middle SHOWS the chosen source
                buildSourceToggle("cable.connector", active: !piano, width: (BuildGeom.castW - 12) / 8) { au?.setReceiverLatchPiano(sel, false); refreshFromDocument() }
                if piano {
                    buildKeyboard(receiver: sel, held: sel < recvs.count ? Set(recvs[sel].pianoNotesResolved) : [], enabled: true)   // PIANO source → the keyboard
                } else {
                    buildChannelBox(receiver: sel, channel: sel < recvs.count ? recvs[sel].channel : 0)   // MIDI source → the channel box (tap = selector)
                }
                buildSourceToggle("pianokeys", active: piano, width: (BuildGeom.castW - 12) / 8, rotate: true) { au?.setReceiverLatchPiano(sel, true); refreshFromDocument() }
            }
            HStack(spacing: 6) {                                   // octave shift for the selected door, with the current offset between
                buildOctBtn("OCT −") { nudgeReceiverOctave(sel, -1) }
                let oct = sel < receiverOctave.count ? receiverOctave[sel] : 0
                Text(oct > 0 ? "+\(oct)" : "\(oct)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(buildCyan).frame(minWidth: 30)
                buildOctBtn("OCT +") { nudgeReceiverOctave(sel, +1) }
            }.frame(width: 176)
        }
    }

    // Select which INPUT door (R1–R4) the machine listens to + the face edits. Fans the choice onto the selected
    // colour's cells (its input receiver) and the page sticky, so a fresh cell inherits it.
    private func buildSelectDoor(_ i: Int) {
        buildSelReceiver = i
        ddStickyReceiver = i
        if let cid = ddSelectedColourID, ddColourIsPlaced(cid) {
            au?.editCellsOfColour(cid) { $0.inputReceiver = i }
            refreshFromDocument()
        }
    }

    @ViewBuilder private func buildCastSection() -> some View {
        VStack(alignment: .center, spacing: 8) {
            buildStep("2 · THE CAST")
            buildCastPalette()
        }
    }

    @ViewBuilder private func buildOutputSection() -> some View {
        let buses = ddSelectedColourBuses()
        VStack(alignment: .center, spacing: 8) {
            buildStep("3 · OUTPUT")
            HStack(spacing: 4) {                                   // A–D toggle the selected colour's output emitters
                ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, b in
                    buildIOChip(b.rawValue, on: buses.contains(b), fill: true) { buildToggleBus(b) }
                }
            }
            .frame(width: BuildGeom.castW)                         // match the emitters row to the cast palette width
            buildMidiOutInfo(buses: buses)                         // the lit emitters + their channels
        }
    }

    // The selected colour's output emitters (from its placed cells, else the page sticky default).
    private func ddSelectedColourBuses() -> Set<Bus> {
        if let cid = ddSelectedColourID, let c = ddRepresentativeCell(cid) { return c.buses }
        return ddStickyBuses
    }

    private func buildToggleBus(_ bus: Bus) {
        guard let cid = ddSelectedColourID else { return }
        var buses = ddSelectedColourBuses()
        if buses.contains(bus) { buses.remove(bus) } else { buses.insert(bus) }
        if buses.isEmpty { buses = [bus] }                        // never leave a colour with no output
        if ddColourIsPlaced(cid) { au?.editCellsOfColour(cid) { $0.buses = buses }; refreshFromDocument() }
        ddStickyBuses = buses                                     // sticks for the colour's next placement too
    }

    // PLAY THIS MACHINE — audition the selected colour (placed → solo its cell; unplaced → synthetic preview). Toggle;
    // mutually exclusive with PLAY THE STAGING GRID (one workshop voice).
    private func buildToggleMachineAudition() {
        if ddSolo { ddSolo = false; au?.clearColourSolo(); return }
        guard ddSelectedColourID != nil else { return }
        buildStagingPlaying = false                              // one workshop voice — stop staging
        ddSolo = true; ddEngageSolo()
    }
    // PLAY THE STAGING GRID — mutually exclusive with the machine audition (engine-backed staging audio is a later
    // slice; for now this holds the workshop-voice state + stops the machine audition).
    private func buildToggleStagingPlay() {
        if buildStagingPlaying { buildStagingPlaying = false; return }
        if ddSolo { ddSolo = false; au?.clearColourSolo() }      // one workshop voice — stop the machine audition
        buildStagingPlaying = true
    }

    // BUILD RANDOMIZE — the SIMPLER roll (a short 1–3-slot all-contributing chain, no macros); writes it colour-wide.
    private func buildRandomizeSimple() {
        guard let cid = ddSelectedColourID else { return }
        var rng = SystemRandomNumberGenerator()
        au?.withChainColour(cid) { $0 = Dice.rollSimple(using: &rng) }
        refreshFromDocument()
    }

    // The selected colour's OWN processors (its templateChain) — shown on the footer; EMPTY for a new colour.
    private func selectedColourChain() -> [ProcessorSlot] {
        guard let cid = ddSelectedColourID, let c = docColours.first(where: { $0.colourID == cid }) else { return [] }
        return c.templateChain ?? []
    }

    @ViewBuilder private func buildPartHeader() -> some View {
        HStack(spacing: 6) {
            Text("PART 1 ▾").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(buildPanel))
            Text("+ NEW").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(buildDim)
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
            Spacer(minLength: 0)
        }
    }

    // The selected door's MIDI-IN CHANNEL box (keyboard-sized) — tap opens a channel selector (OMNI · CH 1–16).
    @ViewBuilder private func buildChannelBox(receiver i: Int, channel: Int) -> some View {
        Menu {
            Button("OMNI") { au?.setReceiverChannel(i, 0); refreshFromDocument() }
            ForEach(1..<17, id: \.self) { ch in Button("CH \(ch)") { au?.setReceiverChannel(i, ch); refreshFromDocument() } }
        } label: {
            VStack(spacing: 2) {
                Text("MIDI IN ▾").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).tracking(1)
                Text(channel == 0 ? "OMNI" : "CH \(channel)").font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan)
            }
            .frame(width: 176, height: 52)
            .background(RoundedRectangle(cornerRadius: 7).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildCyan.opacity(0.4), lineWidth: 1))
        }
    }

    // The octave keyboard for the selected PIANO door (one octave from C3, matching the receiver keyboard). Tap a key
    // to pick/unpick it into the door's frozen pool; dimmed + inert when the door isn't in PIANO mode.
    @ViewBuilder private func buildKeyboard(receiver i: Int, held: Set<Int>, enabled: Bool) -> some View {
        let startNote = 48                                    // C3, one octave (matches ReceiverConfigView)
        let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
        let blackAfter: [Int: Int] = [0: 1, 1: 3, 3: 6, 4: 8, 5: 10]
        ZStack(alignment: .topLeading) {
            ForEach(0..<7, id: \.self) { wi in
                let note = startNote + whiteOffsets[wi]
                RoundedRectangle(cornerRadius: 3).fill(held.contains(note) ? buildCyan : Color(white: 0.9))
                    .frame(width: 24, height: 52).overlay(RoundedRectangle(cornerRadius: 3).stroke(buildPanel, lineWidth: 1))
                    .offset(x: CGFloat(wi) * 25)
                    .contentShape(Rectangle()).onTapGesture { au?.toggleReceiverPianoNote(i, note); refreshFromDocument() }
            }
            ForEach(0..<7, id: \.self) { wi in
                if let bOff = blackAfter[wi] {
                    let note = startNote + bOff
                    RoundedRectangle(cornerRadius: 2).fill(held.contains(note) ? buildCyan : buildPanel)
                        .frame(width: 15, height: 31).offset(x: CGFloat(wi) * 25 + 17)
                        .contentShape(Rectangle()).onTapGesture { au?.toggleReceiverPianoNote(i, note); refreshFromDocument() }
                }
            }
        }
        .frame(width: 176, height: 52, alignment: .topLeading)
        .padding(.vertical, 2)
        .opacity(enabled ? 1 : 0.35)
        .allowsHitTesting(enabled)
    }

    // The per-receiver SOURCE toggle flanking the piano: a DIN connector (MIDI in) on the left, the in-app piano on
    // the right — piano-height, half an R1 button wide. The active side is filled cyan.
    @ViewBuilder private func buildSourceToggle(_ icon: String, active: Bool, width: CGFloat, rotate: Bool = false, action: (() -> Void)? = nil) -> some View {
        Image(systemName: icon).font(.system(size: 18, weight: .semibold))
            .rotationEffect(.degrees(rotate ? 90 : 0))
            .foregroundColor(active ? .black : buildDim)
            .frame(width: width, height: 52)
            .background(RoundedRectangle(cornerRadius: 7).fill(active ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildCyan.opacity(active ? 0 : 0.4), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }

    // OCT −/+ buttons under the piano (octave shift for the selected PIANO door).
    @ViewBuilder private func buildOctBtn(_ s: String, action: (() -> Void)? = nil) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildCyan.opacity(0.4), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }

    // MIDI OUT readout below the emitters — the lit emitters + their stamp channels. Piano-height, cast-width.
    @ViewBuilder private func buildMidiOutInfo(buses: Set<Bus>) -> some View {
        let chans = au?.uiBusChannels() ?? [1, 2, 3, 4]
        let lit = Array(Bus.allCases.enumerated()).filter { buses.contains($0.element) }
        let summary = lit.isEmpty ? "—"
            : lit.map { "\($0.element.rawValue)→CH\(chans.indices.contains($0.offset) ? chans[$0.offset] : $0.offset + 1)" }.joined(separator: "   ")
        VStack(spacing: 3) {
            Text("MIDI OUT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1.2)
            Text(summary).font(.system(size: lit.count > 1 ? 11 : 15, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(width: BuildGeom.castW, height: 52)
        .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
    }

    @ViewBuilder private func buildCastPalette() -> some View {
        VStack(spacing: BuildGeom.castGap) {
            ForEach(0..<4, id: \.self) { row in                    // 8×4 = 32 slots (8 columns · 4 rows)
                HStack(spacing: BuildGeom.castGap) {
                    ForEach(0..<8, id: \.self) { col in
                        buildCastSlot(row * 8 + col)
                    }
                }
            }
        }
    }

    // One cast slot. Slots 0–15 map to the 16 real colours (swatch when defined/placed, else a "+" create slot);
    // slots 16–31 are INERT placeholders (the model has 16 colours — a >16 per-part palette is a future model change).
    @ViewBuilder private func buildCastSlot(_ i: Int) -> some View {
        if i < colourIDs.count {
            let id = colourIDs[i]
            let shown = ddColourShown(i)
            RoundedRectangle(cornerRadius: 6).fill(shown ? (colourColor(id) ?? buildCell) : buildCell)
                .frame(width: BuildGeom.castSwatch, height: BuildGeom.castSwatch)
                .overlay(Text("+").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).opacity(shown ? 0 : 1))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [3]))
                    .opacity(i == ddColourSel ? 1 : 0))
                .contentShape(Rectangle())
                .onTapGesture { shown ? ddSelectColour(i) : ddCreateColour(i) }
        } else {
            // beyond the 16 model colours: still a "+" that CREATES the next undefined colour (the palette caps at 16).
            RoundedRectangle(cornerRadius: 6).fill(buildCell)
                .frame(width: BuildGeom.castSwatch, height: BuildGeom.castSwatch)
                .overlay(Text("+").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(buildDim))
                .contentShape(Rectangle())
                .onTapGesture { buildCreateNextColour() }
        }
    }

    // Create the next undefined colour (a "+" cast slot beyond the 16 model colours taps this; no-op when all 16 exist).
    private func buildCreateNextColour() {
        for j in 0..<colourIDs.count where !ddColourShown(j) { ddCreateColour(j); return }
    }

    // ── MIDDLE COLUMN: STAGING (header · rail+loopkeys+grid · label) with the VERBS in their own box below ──────────
    @ViewBuilder private func buildStagingColumn(cell: CGFloat) -> some View {
        let hue = buildSelHue
        // the staging grid's total width = the row rail + 8 cells + the 8 gaps between them (rail↔grid + 7 inter-cell).
        let gridW = cell * 9 + BuildGeom.cellGap * 8              // row button + 8 cells + the 8 gaps between the 9
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THE STAGING GRID", active: buildStagingPlaying, action: { buildToggleStagingPlay() }))
            Color.clear.frame(height: cell / 2)                   // a little breathing room above the grid (≈ half a cell)
            AnyView(buildStagingGrid(cell: cell, hue: hue))       // AnyView — keeps the deep 8×8 type out of this body
            AnyView(buildStagingVerbBox(gridW: gridW))
            Spacer(minLength: 0)
            AnyView(buildPopulate(gridW: gridW))                  // bottom of the centre column, above the footer
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // STAGE THE GRID — the prominent call-to-action at the bottom of the centre column (upward chevron above the text).
    @ViewBuilder private func buildPopulate(gridW: CGFloat) -> some View {
        VStack(spacing: 3) {
            Image(systemName: "chevron.up").font(.system(size: 16, weight: .heavy)).foregroundColor(.black)
            Text("STAGE THE GRID").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black).tracking(1)
        }
        .frame(width: gridW).frame(minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 10).fill(buildPink))
    }

    // the staging 8×8 (row rail · loop keys · variation rows) — its OWN opaque view so its deep generic type doesn't
    // blow the metadata demangler's stack (see buildPaletteColumn's note).
    @ViewBuilder private func buildStagingGrid(cell: CGFloat, hue: Color) -> some View {
        HStack(alignment: .top, spacing: BuildGeom.cellGap) {
            buildRowButtons(cell: cell, hue: hue, bands: [8])     // cell-sized ROW BUTTONS on the LEFT (staging = one group of 8)
            VStack(spacing: BuildGeom.cellGap) {
                buildLoopKeys(cell: cell)                          // the column-selector (loop-key) row
                VStack(spacing: BuildGeom.cellGap) {               // the staging grid — BLANK until stocked (PLACE)
                    ForEach(0..<8, id: \.self) { r in
                        HStack(spacing: BuildGeom.cellGap) {
                            ForEach(0..<8, id: \.self) { c in
                                let id = buildStagingCells[c][r]
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(id.flatMap { colourColor($0) } ?? buildCell)
                                    .frame(width: cell, height: cell)
                                    .contentShape(Rectangle())
                                    .onTapGesture { buildStagingTap(c, r) }
                            }
                        }
                    }
                }
            }
        }
    }

    // A staging cell tap. PLACE (armed) stocks a cell of the selected colour + its machine (the colour IS its machine);
    // DELETE clears it. MOVE + the engine-backed audition land with the ephemeral staging document (a later slice).
    private func buildStagingTap(_ c: Int, _ r: Int) {
        switch buildVerb {
        case .place: if let cid = ddSelectedColourID { buildStagingCells[c][r] = cid }
        case .delete: buildStagingCells[c][r] = nil
        default: break
        }
    }

    // THE VERB BOX (a different box below staging): the workbench verbs, then the workshop's outcomes.
    @ViewBuilder private func buildStagingVerbBox(gridW: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) { buildVerbBtn(.place); buildVerbBtn(.move); buildVerbBtn(.delete) }
            HStack(spacing: 6) {
                buildActionBtn("CLEAR ALL")                        // clear the staging grid
                buildActionBtn("MUTATE")
                buildActionBtn("🎲 RE-ROLL")                        // re-roll the variation ladder (distinct from the column's 🎲)
            }
        }
        .padding(8)
        .frame(width: gridW)                                       // match the verb box to the grid above it
        .background(RoundedRectangle(cornerRadius: 10).fill(buildPanel))
    }

    // A part boundary. It occupies exactly ONE inter-cell gap so the grid stays uniformly spaced; the LINE is drawn
    // only where asked (the row buttons), centred in that gap so nothing shifts and both columns stay row-aligned.
    @ViewBuilder private func partDivider(line: Bool) -> some View {
        Color.clear.frame(maxWidth: .infinity).frame(height: BuildGeom.cellGap)
            .overlay { if line { Rectangle().fill(Color.white.opacity(0.6)).frame(height: 2) } }
    }

    // the top-row REPLAY (column) keys — SAME STYLE as the row buttons (a filled rounded cell), FULL cell size; a ▾
    // chevron per column, a ↻ repeat glyph when the column is in the loop/replay set. Shared by staging + play.
    @ViewBuilder private func buildLoopKeys(cell: CGFloat) -> some View {
        HStack(spacing: BuildGeom.cellGap) {
            ForEach(0..<8, id: \.self) { c in
                let held = c == 1 || c == 2                        // placeholder: these columns are in the replay set
                RoundedRectangle(cornerRadius: 7).fill(buildCyan.opacity(held ? 0.6 : 0.4))
                    .frame(width: cell, height: cell)
                    .overlay(Image(systemName: "repeat")           // ALWAYS the loop glyph (never a chevron); held shows via the fill
                        .font(.system(size: 12, weight: .heavy)).foregroundColor(.white.opacity(0.9)))
            }
        }
    }

    // ROW BUTTONS — a cell-sized selector per grid row on the LEFT edge; shared by both grids. `bands` is the row
    // grouping (staging = [8]; play = [3,2,1,1,1]) so the buttons carry the SAME part dividers as the grid → they align
    // row-for-row. A top spacer clears the loop-key row.
    @ViewBuilder private func buildRowButtons(cell: CGFloat, hue: Color, bands: [Int]) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row (now full cell height)
            VStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { idx, rows in
                    if idx > 0 { partDivider(line: true) }         // the DIVIDING LINE lives here, between the row buttons
                    VStack(spacing: BuildGeom.cellGap) {
                        ForEach(0..<rows, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 7).fill(hue.opacity(0.4))
                                .frame(width: cell, height: cell)
                                .overlay(Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.85)))
                        }
                    }
                }
            }
        }
    }

    // PART BUTTONS — the PERFORM grid's left selector: ONE button PER PART, MERGED across its rows (part 1 = rows 1–3,
    // part 2 = rows 4–5, then 6, 7, 8), styled identically to the staging row buttons but labelled with the part NUMBER
    // instead of a chevron. Same rhythm as the grid (top spacer + cellGap spacing) so it aligns row-for-row.
    @ViewBuilder private func buildPartButtons(cell: CGFloat, hue: Color, bands: [Int]) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row (now full cell height)
            ForEach(Array(bands.enumerated()), id: \.offset) { idx, rows in
                let h = cell * CGFloat(rows) + BuildGeom.cellGap * CGFloat(rows - 1)   // merge across the part's rows
                RoundedRectangle(cornerRadius: 7).fill(hue.opacity(0.4))
                    .frame(width: cell, height: h)
                    .overlay(Text("\(idx + 1)").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9)))
            }
        }
    }

    // RIGHT-side per-row buttons on the PERFORM grid — one per row for parts 1 & 2 ONLY (rows 1–3 = "1", rows 4–5 = "2");
    // rows 6–8 (parts 3–5) get no button here since they're already on the left. Identical appearance to the part buttons.
    @ViewBuilder private func buildRightPartButtons(cell: CGFloat, hue: Color) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row (now full cell height)
            ForEach(0..<5, id: \.self) { r in                            // rows 1–5 only
                let part = r < 3 ? 1 : 2
                RoundedRectangle(cornerRadius: 7).fill(hue.opacity(0.4))
                    .frame(width: cell, height: cell)
                    .overlay(Text("\(part)").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9)))
            }
        }
    }

    // ── RIGHT COLUMN: the PLAY grid — five fixed bands + glyph rail; the target decides the verb ───────────────────
    @ViewBuilder private func buildPlayColumn(cell: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("START/STOP THE PLAY GRID"))
            Color.clear.frame(height: cell / 2)                   // a little breathing room above the grid (≈ half a cell), matching staging
            // LEFT: merged PART BUTTONS 1–4 (part 5/row 8 removed). RIGHT: per-row buttons for parts 1 & 2 only (1,1,1,2,2)
            // — parts 3–5 aren't repeated on the right since they're already on the left. Assign STAGING → PERFORM (wires later).
            AnyView(HStack(alignment: .top, spacing: BuildGeom.cellGap) {   // same spacing as staging → attached the same way
                AnyView(buildPartButtons(cell: cell, hue: buildCyan, bands: [3, 2, 1, 1]))
                VStack(spacing: BuildGeom.cellGap) {
                    buildLoopKeys(cell: cell)                     // the column-selector row
                    AnyView(buildPlayBands(cell: cell))          // AnyView — keeps the deep bands type out of this body
                }
                AnyView(buildRightPartButtons(cell: cell, hue: buildCyan))
            })
            AnyView(buildEmitters(cell: cell))                   // EMITTERS fill from below the grid DOWN TO the M/S buttons
            AnyView(buildEmitterMuteSolo(cell: cell))            // per-emitter MUTE/SOLO — the emitters now reach it (no gap)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // EMITTERS — the four output strips (A–D), in the style of the GRID page's emitter section (placeholder). Sits
    // directly below the perform grid; since both grids are the same height and both columns share the button + spacing
    // rhythm, this aligns with the staging verb box.
    @ViewBuilder private func buildEmitters(cell: CGFloat) -> some View {
        let w = cell * 10 + BuildGeom.cellGap * 9                 // the perform grid's width → the strips sit under it
        HStack(spacing: 6) {
            ForEach(Array(["A", "B", "C", "D"].enumerated()), id: \.offset) { i, e in
                VStack(spacing: 4) {
                    Text(e).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan)
                    RoundedRectangle(cornerRadius: 4).fill(buildCell)   // the velocity fader STRETCHES down to the M/S row
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 4).fill(buildCyan.opacity(0.5)).frame(height: 26), alignment: .bottom)
                    Text("CH \(i + 1)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(buildPanel))
            }
        }
        .frame(width: w).frame(maxHeight: .infinity)              // the emitters fill the space down to the M/S buttons
    }

    // per-emitter MUTE / SOLO — a row of four A–D groups, each with an M and an S button. Spans the emitter width so
    // it sits under the strips; placed at the bottom of the perform column to line up with STAGE THE GRID.
    @ViewBuilder private func buildEmitterMuteSolo(cell: CGFloat) -> some View {
        let w = cell * 10 + BuildGeom.cellGap * 9
        HStack(spacing: 6) {
            ForEach(Array(["A", "B", "C", "D"].enumerated()), id: \.offset) { _, _ in
                HStack(spacing: 4) {
                    buildMSBtn("M", tint: buildHues[3])          // mute (red)
                    buildMSBtn("S", tint: buildHues[0])          // solo (amber)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: w)
    }

    @ViewBuilder private func buildMSBtn(_ label: String, tint: Color) -> some View {
        Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(tint)
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 7).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.5), lineWidth: 1.5))
    }

    // the PLAY grid rows — its OWN opaque view (see buildPaletteColumn's metadata-stack note).
    @ViewBuilder private func buildPlayBands(cell: CGFloat) -> some View {
        VStack(spacing: BuildGeom.cellGap) {                       // UNIFORM 8 rows — no line inside the grid; parts show on the row buttons
            ForEach(0..<8, id: \.self) { r in
                let p = r < 3 ? 0 : (r < 5 ? 1 : r - 3)            // this row's PART (parts: 0-2 · 3-4 · 5 · 6 · 7)
                let base = buildHues[p % buildHues.count]           // one base hue PER PART
                HStack(spacing: BuildGeom.cellGap) {
                    ForEach(0..<8, id: \.self) { c in
                        let shade = 0.35 + 0.5 * Double((r * 3 + c * 2 + p) % 4) / 3.0   // a variety of SIMILAR shades within the part
                        RoundedRectangle(cornerRadius: 7).fill(base.opacity(shade))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }

    // ── MACHINERY STRIP (bottom, full width): the chain — ID · IN box · slots + ghost · OUT box ────────────────────
    @ViewBuilder private func buildMachinery() -> some View {
        let chain = selectedColourChain()                         // the SELECTED colour's real processors (empty for a new colour)
        HStack(spacing: 10) {                                      // THE CHAIN — select-cell box → MIDI OUT box (centred)
            RoundedRectangle(cornerRadius: 9).fill(buildSelHue).frame(width: 40, height: 40)   // the PREVIEW cell = the selected colour
            buildBox("R1: MIDI IN", "OMNI")
            Text("┈┈▶").foregroundColor(buildDim).font(.system(size: 10, design: .monospaced))
            ForEach(0..<8, id: \.self) { i in                     // UP TO 8 processor slots (the chain's capacity)
                if i < chain.count {
                    buildSlot(chain[i].type.rawValue, colour: buildSelHue)   // a real processor — the selected colour
                } else if i == chain.count {
                    buildSlot("+", dashed: true)                  // the add-processor ghost (editing wires later)
                } else {
                    buildSlot("", dashed: true)                   // an empty capacity slot
                }
                if i < 7 { Text("┈").foregroundColor(buildDim) }
            }
            Text("┈┈▶").foregroundColor(buildDim).font(.system(size: 10, design: .monospaced))
            buildBox("A: MIDI OUT", "ch1")
        }
        .frame(maxWidth: .infinity)                               // centre the chain in the footer
        .overlay(alignment: .leading) {                          // RANDOMIZE pinned to the LEFT (footer MUTATE removed — the staging strip's MUTATE is THE mutate, iteration 5 §2)
            buildFooterBtn("🎲 RANDOMIZE", pink: true) { buildRandomizeSimple() }   // BUILD: the SIMPLER roll (short chain, no macros)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: BuildGeom.barH, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
    }

    // a fixed-width footer button (the footer uses a Spacer, so these can't be maxWidth-fill like buildActionBtn).
    @ViewBuilder private func buildFooterBtn(_ label: String, pink: Bool = false, action: (() -> Void)? = nil) -> some View {
        Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(pink ? Color.black : Color.white)
            .padding(.horizontal, 16).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 11).fill(pink ? buildPink : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(buildCyan.opacity(pink ? 0 : 0.35), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }

    // ── small shared placeholder widgets ─────────────────────────────────────────────────────────────────────────
    // The identical audition button at the top of each column (dot + label, cyan-bordered). `active` fills it cyan
    // (auditioning); `action` (when given) makes it tappable.
    @ViewBuilder private func buildColumnButton(_ label: String, active: Bool = false, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Circle().fill(active ? Color.black : buildCyan).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(active ? .black : buildCyan).tracking(1)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? buildCyan : buildCell))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(buildCyan, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }
    @ViewBuilder private func buildStep(_ s: String) -> some View {
        Text(s).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1.2)
    }
    @ViewBuilder private func buildIOChip(_ s: String, on: Bool = false, keys: Bool = false, fill: Bool = false, action: (() -> Void)? = nil) -> some View {
        Text(s).font(.system(size: 9, weight: on ? .heavy : .regular, design: .monospaced))
            .foregroundColor(on ? Color.black : (keys ? buildCyan : buildDim))
            .padding(.horizontal, 7)
            .frame(maxWidth: fill ? .infinity : nil).frame(height: 48)   // fill → the row spreads evenly to the cast width; height doubled (24→48)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildCyan, lineWidth: keys && !on ? 1 : 0))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }
    @ViewBuilder private func buildActionBtn(_ s: String, pink: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).multilineTextAlignment(.center)
            .foregroundColor(pink ? Color.black : Color.white).tracking(0.5)
            .frame(maxWidth: .infinity).frame(minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 9).fill(pink ? buildPink : buildCell))
    }
    // the spring-held workbench verb (iteration 4). Skeleton: a tap arms/disarms it (the real gesture is hold→release).
    @ViewBuilder private func buildVerbBtn(_ v: BuildVerb) -> some View {
        let armed = buildVerb == v
        Text(v.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(armed ? Color.black : Color.white)
            .frame(maxWidth: .infinity).frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(armed ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(buildCyan, lineWidth: 1).opacity(armed ? 0 : 0.5))
            .contentShape(Rectangle())
            .onTapGesture { buildVerb = armed ? nil : v }
    }
    @ViewBuilder private func buildBox(_ title: String, _ ch: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundColor(.white)
            Text(ch).font(.system(size: 8, design: .monospaced)).foregroundColor(buildCyan)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(buildCell))
    }
    // A processor slot in the footer chain. `colour` fills a REAL processor with the selected colour; else a dashed
    // empty/ghost slot. Boxes are a little bigger than before (50×40).
    @ViewBuilder private func buildSlot(_ s: String, dashed: Bool = false, colour: Color? = nil) -> some View {
        Text(s).font(.system(size: 9, weight: colour != nil ? .heavy : .regular, design: .monospaced))
            .foregroundColor(colour != nil ? .black : (dashed ? buildDim : .white))
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: 50, height: 40)
            .background(RoundedRectangle(cornerRadius: 7).fill(colour ?? (dashed ? Color.clear : buildCell)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(colour != nil ? Color.clear : (dashed ? buildDim : Color(white: 0.15)),
                                                              style: StrokeStyle(lineWidth: dashed ? 1.3 : 1, dash: dashed ? [4] : [])))
    }
}

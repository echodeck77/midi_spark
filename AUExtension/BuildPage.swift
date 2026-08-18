import SwiftUI

// The ONE workshop voice: which SHOP section sounds — the MIDI CHAIN audition, the PART grid, or NEITHER. Each header
// toggles its own section (play ⇄ stop) so both can be off; picking one stops the other (they never sound together).
enum BuildWorkshopVoice { case none, chain, part }

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
private let buildEdge  = Color(white: 1).opacity(0.17)   // §0 MUTED-CHROME: a neutral whisper for default (non-armed) chrome borders — replaces standing cyan strokes
private let buildPartInk = Color(white: 1).opacity(0.9)  // §2 BRIGHTNESS = WHICH PART: a NEUTRAL bright accent (no second hue) — the part's presence across bench + stage

// iteration 4: the spring-held workbench verbs that replace the drag (the house law). Skeleton: tap arms/disarms.
enum BuildGridMode: String { case play = "PLAY", edit = "EDIT" }   // the per-grid PLAY/EDIT radio (play grid only now; the part grid's EDIT mode was retired 2026-08-16)
// The part grid's ROW-BUTTON mode (Paul 2026-08-16): a radio that changes what the left row buttons DO — SELECT the
// whole row's rung · PLACE the selected colour · MUTATE a value-tweaked variant of it.
enum BuildRowMode: String, CaseIterable { case select = "SELECT", place = "PLACE", mutate = "MUTATE" }
enum BuildFill { case none, cell, grid }   // header playhead fill period: none · one step (.cell) · the whole loop (.grid)

// BuildPart / BuildUnassignedData moved to BuildModel.swift (now persisted + test-target-visible).

extension DiagView {

    @ViewBuilder func buildPage(_ size: CGSize) -> some View {
        // AUv3 views get an initial ZERO / degenerate layout pass; laying the grids out then would compute a NEGATIVE
        // column width → SwiftUI's fatal "Invalid frame dimension" (the plugin fails to load in AUM). Draw nothing
        // until a real, finite size arrives.
        if size.width.isFinite, size.height.isFinite, size.width > 80, size.height > 80 {
            ZStack {
                if size.width > size.height { AnyView(buildLandscape(size)) } else { AnyView(buildPortrait(size)) }
                if let slot = buildEditSlot { AnyView(buildProcessorEditor(slot: slot, size: size)) }   // the processor pop-up editor
                if let slot = buildAddSlot { AnyView(buildProcessorPicker(slot: slot, size: size)) }    // the ADD-processor picker
                if buildFlowOpen { AnyView(buildFlowPopup(size: size)) }                               // the signal-flow diagram pop-up
                if let kind = buildGridPopup { AnyView(buildGridPopupView(kind, size: size)) }          // the full-screen grid pop-up
            }
        } else {
            Color.clear
        }
    }

    // The selected colour's real hue (the cast selection drives the machine ID + grid tints). Falls back to cyan.
    fileprivate var buildSelHue: Color { colourColor(ddSelectedColourID ?? "") ?? buildCyan }

    // ── LANDSCAPE: three EQUAL columns (palette · staging · play) over the full-width machinery strip ──────────────
    @ViewBuilder private func buildLandscape(_ size: CGSize) -> some View {
        let avail = max(1, size.width - BuildGeom.colGap * 2 - 20)
        let leftW = max(1, avail / 3 * 0.726)                      // the MACHINE column: 0.968 × 0.75 → 25% narrower (Paul 2026-08-18)
        let gridColW = max(1, (avail - leftW) / 2)                 // staging + play split the reclaimed width
        // the PERFORM grid is widest: LEFT part buttons + 8 grid cells + RIGHT per-row buttons = 10 cells (+ 9 gaps).
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (gridColW - BuildGeom.cellGap * 9) / 10))
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: BuildGeom.colGap) {
                // AnyView boundaries: opaque `some View` types get INLINED into the parent's concrete type, so the
                // whole page collapses into ONE giant nested generic whose metadata instantiation overflows the Swift
                // demangler's stack (SIGSEGV opening BUILD). AnyView is a nominal type the demangler won't recurse
                // through — each column's type is instantiated separately + bounded.
                AnyView(buildPaletteColumn(colW: leftW, cell: cell).frame(width: leftW, alignment: .center))
                AnyView(buildStagingColumn(cell: cell).frame(width: gridColW, alignment: .center))
                AnyView(buildPlayColumn(cell: cell).frame(width: gridColW, alignment: .center))
            }   // each column now carries its OWN button box, directly below its grid (built inside the column)
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── PORTRAIT: height is abundant → a plain stack (palette → staging → play → machinery) ────────────────────────
    @ViewBuilder private func buildPortrait(_ size: CGSize) -> some View {
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (size.width - BuildGeom.cellGap * 9 - 24) / 10))
        VStack(spacing: 12) {
            AnyView(buildPaletteColumn(colW: size.width - 20, cell: cell))   // AnyView boundaries — see buildLandscape's note (metadata-stack overflow); each column carries its own button box
            AnyView(buildStagingColumn(cell: cell))
            AnyView(buildPlayColumn(cell: cell))
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── LEFT COLUMN: play-cell · part · input(+keyboard) · cast 4×4 (+🎲) · output · APPLY TO STAGING · litter ──────
    // IMPORTANT: keep this VStack SHALLOW — the INPUT/CAST/OUTPUT groups are SEPARATE opaque sub-views. A single
    // deeply-nested SwiftUI view type here makes the Swift runtime's type-metadata demangler recurse until it
    // overflows the stack when the AU instantiates the view → SIGSEGV the moment BUILD opens (device crash 2026-08-11).
    @ViewBuilder private func buildPaletteColumn(colW: CGFloat, cell: CGFloat) -> some View {
        let castW = max(160, colW - 4)                            // the cast + processor boxes FILL the column width
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THIS MIDI CHAIN", active: buildDisplayVoice == .chain, fill: .cell, action: { buildRequestWorkshopVoice(buildDisplayVoice == .chain ? .none : .chain) }))   // tap = play/STOP the chain; pairs with the grids' column button
            AnyView(buildMachineBlock(castW: castW, cell: cell))  // invisible header row + cast (rows 1–4) + processors (rows 5–8): the 8×8-equivalent block, grid-height
            AnyView(buildLeftControlBox())                        // RANDOMIZE · MUTATE · AUTOFILL / LIBRARY — directly below the processor section
            AnyView(buildEmitterToggles(castW: castW))            // the four MIDI-OUT emitter toggles, styled like the MIDI-IN selector (Paul 2026-08-18)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // The 8×8-equivalent machine block. An INVISIBLE, untouchable header row lands the cast one cell down, on the
    // grids' DATA top (matching their loop-key row) rather than their header. Then the cast (rows 1–4) and the
    // chain-as-boxes (rows 5–8) stack to exactly 8 grid cells tall, so all three columns read at equal height.
    @ViewBuilder private func buildMachineBlock(castW: CGFloat, cell: CGFloat) -> some View {
        VStack(spacing: BuildGeom.castGap) {
            AnyView(buildColourTabs(castW: castW, cell: cell))    // the 8 colour TABS (= part-grid rows 1–8) — the ROW SELECTOR
            AnyView(buildReceiverSelector(castW: castW))          // the MIDI-IN (receiver) selector — separates the row selector from the chain box
            AnyView(buildProcessorBlock(castW: castW, cell: cell))// the selected tab's chain (the MIDI CHAIN box), a 4×2 of 2×2-cell boxes
        }
    }
    // THE RECEIVER (MIDI-IN) SELECTOR — sits between the row selector and the MIDI-chain box. Four buttons styled
    // like the centre column's emitter A–D chips (buildIOChip: cyan-when-armed, muted idle), but two-line: "MIDI IN"
    // small over a big A/B/C/D. A radio — one door selected, feeding the part. (Paul 2026-08-18)
    @ViewBuilder private func buildReceiverSelector(castW: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in buildReceiverSelectChip(i) }
        }
        .frame(width: castW)
    }
    @ViewBuilder private func buildReceiverSelectChip(_ i: Int) -> some View {
        buildIOSelectChip(top: "MIDI IN", letter: ["A", "B", "C", "D"][i], on: buildSelReceiver == i) { buildSelectDoor(i) }   // radio: select the part's door
    }
    // THE EMITTER (MIDI-OUT) TOGGLES — below the left column's button box. Four toggles (A–D), IDENTICAL in style to
    // the MIDI-IN receiver selector, toggling the PART's output emitters (part-owned, so every colour follows). (Paul 2026-08-18)
    @ViewBuilder private func buildEmitterToggles(castW: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, b in
                buildIOSelectChip(top: "MIDI OUT", letter: b.rawValue, on: buildPartEmitters.contains(b)) { buildToggleBus(b) }   // toggle: multiple emitters can be lit
            }
        }
        .frame(width: castW)
    }
    // The shared two-line I/O chip: a small top label over a big A/B/C/D, styled like the centre column's emitter A–D
    // chips (cyan-when-on, muted idle, height 48). Used by BOTH the MIDI-IN receiver selector and the MIDI-OUT
    // emitter toggles so they read identically. (Paul 2026-08-18)
    @ViewBuilder private func buildIOSelectChip(top: String, letter: String, on: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 1) {
            Text(top).font(.system(size: 6, weight: .heavy, design: .monospaced)).tracking(0.5)
            Text(letter).font(.system(size: 15, weight: .black, design: .monospaced))
        }
        .foregroundColor(on ? Color.black : buildDim)
        .frame(maxWidth: .infinity).frame(height: 48)                        // matches the emitter chips (height 48, fill the row)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? buildCyan : buildCell))   // ON = the accent; idle mutes
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.clear : buildEdge, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
    // THE COLOUR TABS (Paul 2026-08-17): 8 tabs numbered 1–8, one per part-grid row. Each tab is a colour/midi-chain;
    // the SELECTED tab drives the processor block + MIDI + visuals. A SET tab shows its colour; an empty tab reads blank.
    @ViewBuilder private func buildColourTabs(castW: CGFloat, cell: CGFloat) -> some View {
        let gap = BuildGeom.castGap
        let tabW = (castW - gap * 7) / 8
        HStack(spacing: gap) {
            ForEach(0..<8, id: \.self) { n in buildColourTab(n, w: tabW, cell: cell) }
        }
    }
    @ViewBuilder private func buildColourTab(_ n: Int, w: CGFloat, cell: CGFloat) -> some View {
        let cid = buildRowColour(n)                              // tab N's colour = the colour on part-grid row N
        let selected = cid != nil && cid == ddSelectedColourID
        let tint = cid.flatMap { colourColor($0) }              // the tab's own colour (nil = empty)
        // Styled like the part-grid ROW buttons: the muted RAIL (light grey on dark grey) when empty or unselected;
        // a populated tab shows its colour as the NUMBER's text; the SELECTED tab keeps its solid-colour look. (Paul 2026-08-18)
        RoundedRectangle(cornerRadius: 6)
            .fill(selected ? (tint ?? buildRowButtonFill) : buildRowButtonFill)
            .frame(width: w, height: cell)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.white : (tint ?? buildEdge), lineWidth: (selected || tint != nil) ? 2 : 1))   // SELECTED = white; populated = its colour outline; empty = the faint edge
            .overlay { if buildPendingTab == n { buildPulseOverlay() } }   // PENDING (copied, unedited) → pulses
            .overlay(Text("\(n + 1)").font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(selected ? .black.opacity(0.7) : (tint ?? .white.opacity(0.7))))   // populated → the colour's TEXT; empty → grey; selected → black on the fill
            .contentShape(Rectangle())
            .onTapGesture { buildTapColourTab(n) }
    }
    // A breathing white pulse (the pending-tab / previewed-row highlight).
    @ViewBuilder private func buildPulseOverlay() -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
            let ph = 0.5 + 0.5 * sin(tl.date.timeIntervalSinceReferenceDate * 3.4)
            RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.12 + 0.32 * ph)).allowsHitTesting(false)
        }
    }
    private func buildTapColourTab(_ n: Int) {
        if let cid = buildRowColour(n) {                         // a SET tab → select its colour + play its row
            for c in 0..<8 { buildStagingSel[c] = n }
            buildSelectID(cid)
            buildStagingSyncIfPlaying()
        } else {
            buildPopulateTab(n)                                  // an EMPTY tab → create/copy/place, then pulse until edited
        }
    }
    // Touch an EMPTY tab: mint tab n's colour carrying a COPY of the last-selected colour's chain, place it on row n,
    // select it, and mark it PENDING (pulsing). Only one pending → revert the previous one first. (Paul 2026-08-17)
    private func buildPopulateTab(_ n: Int) {
        let sourceChain = buildSelID.map { buildColourMachine($0) } ?? []
        if let p = buildPendingTab, p != n {                     // ONE pending → discard the previous unedited candidate
            if let old = buildRowColour(p) { buildPartCast.removeAll { $0 == old } }
            buildSetRow(p, to: nil)
        }
        let y = buildNewTabColour(n, machine: sourceChain)       // tab n's fixed hue + the copied chain
        buildPartCast.append(y)
        buildSetRow(n, to: y)                                    // placed on part-grid row n
        for c in 0..<8 { buildStagingSel[c] = n }
        buildSelectID(y)
        buildPendingTab = n
        buildPendingSource = selectedColourChain()               // the exact form buildApplyChain compares against
        buildStagingSyncIfPlaying()
    }

    // The chain as the block's lower half: 8 processor boxes, each the size of 2×2 cast cells, laid 1·2·3·4 /
    // 5·6·7·8 with NO connectors. Empty slots read as their number (1–8); populated show the processor type.
    @ViewBuilder private func buildProcessorBlock(castW: CGFloat, cell: CGFloat) -> some View {
        let chain = selectedColourChain()
        let gap = BuildGeom.castGap
        let swW = (castW - gap * 7) / 8                            // same swatch width as the cast → boxes sit on the 8-column grid
        let boxW = swW * 2 + gap                                   // 2 cast columns wide
        let boxH = cell * 2 + gap                                  // 2 cast rows tall
        VStack(spacing: gap) {
            ForEach(0..<2, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<4, id: \.self) { c in
                        buildProcBox(r * 4 + c, chain: chain, w: boxW, h: boxH)
                    }
                }
            }
        }
    }

    @ViewBuilder private func buildProcBox(_ i: Int, chain: [ProcessorSlot], w: CGFloat, h: CGFloat) -> some View {
        let populated = i < chain.count && !buildIsEmptySlot(chain[i])
        let bw = w * 0.8, bh = h * 0.8                             // the button is 80% of the 2×2-cell footprint …
        Group {
            if populated {
                Text(chain[i].type.rawValue)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3)
                    .frame(width: bw, height: bh)
                    .background(RoundedRectangle(cornerRadius: 8).fill(buildSelHue))
                    .overlay { if chain[i].bypassed { RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45)) } }
            } else {
                Text("\(i + 1)")                                   // the slot NUMBER — prominent (big + black weight)
                    .font(.system(size: min(bh * 0.6, 26), weight: .black, design: .monospaced))
                    .foregroundColor(Color(white: 0.62))
                    .frame(width: bw, height: bh)
                    .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(buildEdge, lineWidth: 1))
            }
        }
        .frame(width: w, height: h)                               // … centred in the full cell footprint
        .contentShape(Rectangle())
        .onTapGesture { buildExitPlaceMode(); buildPlaceMsg = nil; if populated { buildEditSlot = i } else { buildAddSlot = i } }   // fresh pop-up → clear stale PLACE feedback; box is not a play-grid row → leaves PLACE mode
    }

    @ViewBuilder private func buildInputSection(castW: CGFloat) -> some View {
        let recvs = au?.uiReceivers() ?? []
        let sel = buildSelReceiver
        let piano = sel < recvs.count && recvs[sel].latchPianoResolved
        let togW = min(50, max(28, (castW - 80) / 2))            // comfortable toggle targets, clamped so the row always FITS castW
        let midW = max(60, castW - togW * 2 - 10)                // the keyboard/channel box FILLS the span between the two toggles (all widths fixed → no greedy layout)
        VStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {                                   // R1–R4: pick the door (⌨ piano · ⎓ MIDI); the face below edits it
                ForEach(0..<4, id: \.self) { i in
                    let isPiano = i < recvs.count && recvs[i].latchPianoResolved
                    buildIOChip("R\(i + 1) \(isPiano ? "⌨" : "⎓")", on: i == sel, keys: isPiano, fill: true) { buildSelectDoor(i) }
                }
            }
            .frame(width: castW)                                  // the receivers row fills the column
            HStack(spacing: 5) {                                   // the SELECTED door's SOURCE toggle: DIN (MIDI in) | in-app piano; the middle SHOWS the chosen source
                buildSourceToggle("cable.connector", active: !piano, width: togW) { buildSetSource(sel, piano: false) }
                if piano {
                    buildKeyboard(receiver: sel, held: sel < recvs.count ? Set(recvs[sel].pianoNotesResolved) : [], enabled: true, width: midW)
                } else {
                    buildChannelBox(receiver: sel, channel: sel < recvs.count ? recvs[sel].channel : 0).frame(width: midW)
                }
                buildSourceToggle("pianokeys", active: piano, width: togW, rotate: true) { buildSetSource(sel, piano: true) }
            }
            .frame(width: castW)                                  // the midi-select row fills the column
            HStack(spacing: 6) {                                   // octave shift for the selected door, with the current offset between
                buildOctBtn("OCT −") { nudgeReceiverOctave(sel, -1) }
                let oct = sel < receiverOctave.count ? receiverOctave[sel] : 0
                Text(oct > 0 ? "+\(oct)" : "\(oct)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(buildCyan).frame(minWidth: 30)
                buildOctBtn("OCT +") { nudgeReceiverOctave(sel, +1) }
            }.frame(width: 176)
        }
    }

    // §2: the INPUT door is PART-owned — one door for the whole part (every colour follows). Applied uniformly at
    // scene-build + audition; no per-colour cell fanning.
    private func buildSelectDoor(_ i: Int) {
        buildSelReceiver = i
        ddStickyReceiver = i
        receivers = au?.uiReceivers() ?? receivers               // mirror so the source toggle/keyboard reflect the newly-selected door at once
        buildStagingSyncIfPlaying()                              // the part's door applies to every staging cell, live
        refreshFromDocument()
    }

    // Flip the SELECTED door between MIDI-in and the in-app piano. Mirroring `receivers` guarantees SwiftUI
    // invalidates this row immediately (buildInputSection reads uiReceivers live, but the mirror forces the update).
    private func buildSetSource(_ i: Int, piano: Bool) {
        au?.setReceiverLatchPiano(i, piano)
        receivers = au?.uiReceivers() ?? receivers
        refreshFromDocument()
    }

    @ViewBuilder private func buildCastSection(castW: CGFloat, cell: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            buildCastPalette(castW: castW, cell: cell)
        }
    }

    @ViewBuilder private func buildOutputSection(castW: CGFloat) -> some View {
        let buses = buildPartEmitters                             // §2: OUTPUT is PART-owned — every colour follows
        VStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {                                   // A–D toggle the PART's output emitters
                ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, b in
                    buildIOChip(b.rawValue, on: buses.contains(b), fill: true) { buildToggleBus(b) }
                }
            }
            .frame(width: castW)                                  // the emitters row fills the column
            buildMidiOutInfo(buses: buses, castW: castW)          // the lit emitters + their channels
        }
    }

    // §2 (design ferry): the emitters are PART-owned now — shared across every colour/cell of the part.
    private func ddSelectedColourBuses() -> Set<Bus> { buildPartEmitters }

    private func buildToggleBus(_ bus: Bus) {
        var buses = buildPartEmitters
        if buses.contains(bus) { buses.remove(bus) } else { buses.insert(bus) }
        if buses.isEmpty { buses = [bus] }                        // never leave the PART with no output
        buildPartEmitters = buses
        ddStickyBuses = buses                                     // the machine audition preview reads this
        // The PART owns the output — apply it LIVE to whatever's sounding (Paul 2026-08-15): re-publishing the scene
        // re-stamps buildPartEmitters onto the chain audition's injected row AND the part/piece cells.
        buildPublishScene()
    }

    // The MIDI-CHAIN voice. Paul 2026-08-15: it plays the selected colour's machine RAW — behind the scenes a 1-row play
    // grid whose EVERY column is "selected", so the machine sounds on every column with NONE of the part grid's column
    // rules. It rides the SAME ephemeral scene as the part/piece (buildPublishScene injects it), so it coexists with the
    // play grid instead of owning the render via an isolating solo. `ddSolo` is just the "chain is the voice" flag now.
    func buildSelectMachineVoice() {
        buildStagingPlaying = false                              // CHAIN ⟂ PART; the PIECE is independent — it keeps sounding via the scene
        buildSeedCastIfNeeded()                                  // §2: part 1's cast reflects the already-defined colours (once); selects within the cast
        ddStickyReceiver = buildSelReceiver                      // §2: the chain audition uses the PART's I/O (door + emitters)
        ddStickyBuses = buildPartEmitters.isEmpty ? [.a] : buildPartEmitters
        // A document colour never given a chain shows an EMPTY chain but has a nil templateChain; make it an explicit []
        // once so the palette's shown-empty chain matches the raw sound (the injected cell reads buildColourChain, which
        // is [] here → a born-audible passthrough — never the legacy A-face arp). Only fires when the chain is unstored.
        if let cid = ddSelectedColourID, buildColourReg[cid] == nil, au?.colourHasStoredChain(cid) == false {
            au?.withChainColour(cid) { $0 = [] }; refreshFromDocument()   // document colour only — ephemeral colours always carry a registry machine
        }
        ddSolo = true                                           // the chain is the voice — sounded RAW via the ephemeral scene
        buildPublishScene()
    }
    private func buildSelectStagingVoice() {
        if ddSolo { ddSolo = false; au?.clearColourSolo() }      // CHAIN ⟂ PART: stop the chain audition (they're mutually exclusive)
        buildStagingPlaying = true                               // the PART is a voice — the PIECE (if playing) keeps sounding ALONGSIDE (correction)
        buildPublishScene()
    }

    // The LIVE workshop voice, read off the section flags (PART wins if somehow both are set — it shouldn't happen).
    var buildWorkshopVoice: BuildWorkshopVoice {
        if buildStagingPlaying { return .part }
        if ddSolo { return .chain }
        return .none
    }
    // The DISPLAYED workshop voice: the armed target if a switch is pending, else the live one. The HEADERS read this so
    // they highlight the new state IMMEDIATELY on tap, while the MIDI still switches quantized at the boundary. (Paul 2026-08-15)
    var buildDisplayVoice: BuildWorkshopVoice { buildPendingWorkshopVoice ?? buildWorkshopVoice }

    // A header TOGGLES its section: play it if stopped, STOP it if playing (Paul 2026-08-15). Both sections can be off.
    // While the transport runs the switch is QUANTIZED to the next cell boundary (buildCommitPendingVoice, fired from the
    // VC's absoluteStep hook) so it lands on the grid, not mid-cell. Stopped, or re-requesting the live voice → immediate.
    func buildRequestWorkshopVoice(_ target: BuildWorkshopVoice) {
        if d.playing && target != buildWorkshopVoice {
            buildPendingWorkshopVoice = target                   // arm — applied at the next cell boundary
        } else {
            buildPendingWorkshopVoice = nil
            buildApplyWorkshopVoice(target)
        }
    }
    private func buildApplyWorkshopVoice(_ v: BuildWorkshopVoice) {
        switch v {
        case .chain: buildSelectMachineVoice()
        case .part:  buildSelectStagingVoice()
        case .none:  buildStopWorkshop()
        }
    }
    // Stop BOTH shop sections (the header's STOP action). The PIECE (play grid) is independent and keeps sounding.
    private func buildStopWorkshop() {
        if ddSolo { ddSolo = false; au?.clearColourSolo() }
        buildStagingPlaying = false
        buildPublishScene()
    }
    // Apply an armed voice switch at a cell boundary (or on transport stop). Called from the VC.
    func buildCommitPendingVoice() {
        if let v = buildPendingWorkshopVoice {
            buildPendingWorkshopVoice = nil; buildPendingReengage = false
            buildApplyWorkshopVoice(v)
        } else if buildPendingReengage {                 // a palette colour change → re-inject the new chain colour on the boundary
            buildPendingReengage = false
            if ddSolo { buildPublishScene() }
        }
    }
    // Population (Paul 2026-08-15): real deployed play-grid cells (preview doesn't count) · any stocked staging cell.
    var buildPerformPopulated: Bool { buildPerformCells.contains { $0.contains { $0 != nil } } }
    var buildStagingPopulated: Bool { buildStagingCells.contains { $0.contains { $0 != nil } } }

    // Publish the ephemeral scene for the ACTIVE voices. §correction (2026-08-13): the PIECE is INDEPENDENT of the
    // audition — PLAY THIS PART + START/STOP THE PLAY GRID sound TOGETHER (the shopping/alongside workflow). Each
    // staging/perform cell takes its PART-owned I/O + the colour's machine (or a staged variation chain). Paul 2026-08-15:
    // the MIDI CHAIN now ALSO rides this scene (a 1-row grid, every column active → raw, no part-grid column rules), so it
    // sounds ALONGSIDE the play grid instead of owning the render via a solo.
    // The SHELL: gather @State into a pure input, let BuildSceneLogic.composeScene do the work (testable), publish it.
    private func buildPublishScene() {
        au?.clearColourSolo()                                    // BUILD never uses the AU solo now — drop any left by the vestigial ddCreateColour path, so the scene sweeps freely
        if laneMask != 0 { setLane(0) }                          // BUILD has NO column loop yet (its loop keys are a placeholder) — a stale PERFORM/EDIT lap would lock the audition to one column (Paul 2026-08-16). Never lap the workshop.
        var input = BuildSceneLogic.Input()
        input.stagingPlaying = buildStagingPlaying
        input.performPlaying = buildPerformPlaying
        input.chainActive = ddSolo
        input.performCells = buildPerformCells
        input.performMute = buildPerformMute
        input.performActiveRung = { self.buildPerformActiveRung($0, $1) }
        input.performEmit = buildPerformEmit
        input.performRecv = buildPerformRecv
        input.performChain = buildPerformChain
        input.stagingCells = buildStagingCells
        input.stagingSel = buildStagingSel
        input.partEmitters = buildPartEmitters
        input.selReceiver = buildSelReceiver
        input.rowChain = buildRowChain
        if ddSolo, let cid = ddSelectedColourID {
            input.chainColourID = cid
            input.chainMachine = buildColourChain(cid)
        }
        au?.setBuildStagingScene(BuildSceneLogic.composeScene(input))
    }

    // A colour's OWN machine (templateChain), audible slots only.
    // A colour's machine — EPHEMERAL registry (beyond the 16) OR the document templateChain (the canonical 16).
    private func buildColourMachine(_ cid: String) -> [ProcessorSlot] {
        buildColourReg[cid] ?? (docColours.first { $0.colourID == cid }?.templateChain ?? [])
    }
    private func buildColourChain(_ cid: String) -> [ProcessorSlot] {
        buildColourMachine(cid).filter { !buildIsEmptySlot($0) }
    }
    // Write a colour's machine to the right store, and reflect it live.
    private func buildWriteColourMachine(_ cid: String, _ chain: [ProcessorSlot]) {
        if buildColourReg[cid] != nil { buildColourReg[cid] = chain; buildSyncColours() }   // ephemeral
        else { au?.setColourChain(cid, chain); refreshFromDocument() }                       // document colour
        buildStagingSyncIfPlaying()
    }
    // Push the ephemeral colour registry to the AU so renderDoc appends them (their machines resolve).
    func buildSyncColours() { au?.setBuildEphemeralColours(buildColourReg.map { (id: $0.key, machine: $0.value) }) }
    // Allocate a NEW colour carrying `machine` + a custom hue: a free DOCUMENT slot if one remains, else an unlimited
    // EPHEMERAL colour ("b<n>"). Returns its id. (Paul 2026-08-15 — lifts the 16-slot cap.)
    private func buildNewColour(hex rawHex: UInt32, machine: [ProcessorSlot]) -> String {
        let hex = buildUniqueHue(rawHex)                                     // RULE: no two colours share a hue (Paul 2026-08-16)
        if let j = buildFirstUndefinedGlobal() {
            let id = colourIDs[j]
            ddCreateColour(j); au?.withChainColour(id) { $0 = machine }; refreshFromDocument()
            colourHueOverride[id] = hex
            return id
        }
        buildIDCounter += 1
        let id = "b\(buildIDCounter)"
        buildColourReg[id] = machine; colourHueOverride[id] = hex; buildSyncColours()
        return id
    }
    // Select a colour BY ID (document or ephemeral) — the ID-based BUILD selection.
    private func buildSelectID(_ id: String) {
        buildExitPlaceMode()                                     // choosing a colour is a non-(play-row) touch → leave PLACE mode
        buildSelID = id                                          // the DISPLAY selection updates immediately (target, footer, highlight)
        ddColourSel = colourIDs.firstIndex(of: id) ?? -1
        ddStickyReceiver = buildSelReceiver
        ddStickyBuses = buildPartEmitters.isEmpty ? [.a] : buildPartEmitters
        ddScopeToColour(id, anchor: nil, engage: false)          // BUILD never uses the AU solo — the chain plays via the scene
        if ddSolo {                                              // auditioning the chain → re-inject the newly-selected colour
            if d.playing { buildPendingReengage = true }         // SEAMLESS: swap on the next cell boundary
            else { buildPublishScene() }                         // stopped → immediate
        }
    }
    private func buildComplexity(_ chain: [ProcessorSlot]) -> Int { let e = Dice.evalRun(chain); return e.sig.count * 100 + e.peak }   // note frequency (×100) + concurrency
    // The base hue of a colour (its override if any, else its palette hex).
    private func buildBaseHex(_ id: String) -> UInt32 { colourHueOverride[id] ?? colourIDs.firstIndex(of: id).map { colourHexes[$0] } ?? 0x808080 }
    // Every hue currently IN USE by a live colour: the materialised document colours + every ephemeral/recoloured
    // override. An UNASSIGNED canonical hex is NOT counted — so a new colour can claim a genuinely distinct
    // canonical hue rather than a near-shade of its source. (Paul 2026-08-17)
    private func buildUsedHues() -> Set<UInt32> {
        var used = Set(colourHueOverride.values)
        for (i, id) in colourIDs.enumerated() where ddColourShown(i) { used.insert(buildBaseHex(id)) }
        return used
    }
    // A hue guaranteed UNUSED and, wherever possible, VISIBLY distinct: an unassigned canonical palette hue first,
    // else a canonical seed perturbed until it clears everything in use. The engine behind the "no two alike" rule.
    private func buildDistinctHue() -> UInt32 {
        let used = buildUsedHues()
        if let fresh = colourHexes.first(where: { !used.contains($0) }) { return fresh }
        for seed in colourHexes {
            var h = seed, n = 0
            while used.contains(h) && n < 128 { n += 1; h = buildPerturbHex(seed, by: n) }
            if !used.contains(h) { return h }
        }
        return 0x808080
    }
    // STRONG RULE (Paul 2026-08-17): no two colours may EVER share a hue. Keep `hex` if it is free, else nudge to
    // the nearest distinct shade, and if THAT still collides fall back to a guaranteed-distinct hue. Never returns
    // a used hue.
    private func buildUniqueHue(_ hex: UInt32) -> UInt32 {
        let used = buildUsedHues()
        if !used.contains(hex) { return hex }
        var h = hex, n = 0
        while used.contains(h) && n < 128 { n += 1; h = buildPerturbHex(hex, by: n) }
        return used.contains(h) ? buildDistinctHue() : h
    }
    // STRONG RULE: no two PALETTE (cast) colours share a hue. Any member whose hue duplicates an earlier member is
    // recoloured to a distinct hue. Call after any cast mutation.
    private func buildEnforceCastHues() {
        var seen = Set<UInt32>(); var changed = false
        for id in buildPartCast {
            let h = buildBaseHex(id)
            if seen.contains(h) { let nh = buildDistinctHue(); colourHueOverride[id] = nh; seen.insert(nh); changed = true }
            else { seen.insert(h) }
        }
        if changed { buildSyncColours() }
    }
    private func buildPerturbHex(_ h: UInt32, by d: Int) -> UInt32 {
        func ch(_ shift: Int) -> UInt32 { let c = Int((h >> shift) & 0xFF); return UInt32(max(0, min(255, c + (c < 128 ? d : -d)))) }   // push each channel toward its extreme by an increasing step
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }
    // Perceived darkness of a hex — used to invert a row button's background when its coloured icon would vanish.
    private func buildIsDark(_ hex: UInt32) -> Bool {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0 < 0.45
    }
    // The row button's background: normally the muted rail; but in PLACE/MUTATE, if the SELECTED colour (the icon
    // colour) is DARK, invert to a light button so the icon still reads. (Paul 2026-08-16)
    private var buildRowButtonFill: Color {
        if buildRowMode != .select, let cid = ddSelectedColourID, buildIsDark(buildBaseHex(cid)) { return Color.white.opacity(0.9) }
        return Color.white.opacity(0.11)
    }
    // A NEW hue near `source` — lighter (mix toward white) or darker (toward black), with a floor so it's always distinguishable.
    private func buildSimilarHue(of source: String, lighter: Bool, srcC: Int, newC: Int) -> UInt32 {
        let amount = min(0.6, abs(Double(srcC - newC)) / 400.0 + 0.18)        // ≥0.18 so siblings are always tellable apart
        let base = buildBaseHex(source), t = lighter ? 255.0 : 0.0
        func mix(_ shift: Int) -> UInt32 { let ch = Double((base >> shift) & 0xFF); return UInt32(max(0, min(255, ch + (t - ch) * amount))) }
        return (mix(16) << 16) | (mix(8) << 8) | mix(0)
    }

    // STAGE THE GRID (Paul 2026-08-15) — MUTATE what's already placed, filling the grid to 8 rows. Each pass duplicates the
    // populated row that's been duplicated FEWEST so far, tweaks its machine, analyses complexity (note frequency +
    // concurrency), and inserts it just ABOVE the source if LESS complex (a LIGHTER new colour) or just BELOW if MORE
    // complex (DARKER), rearranging the rows. The new colours are NOT added to the palette — touch one on the grid to
    // preview + add it (the pulse flow). Needs ≥1 populated row (the button is disabled otherwise).
    // GARBAGE-COLLECT colours (Paul 2026-08-15). A colour LIVES if referenced by ANY retained state you can revert to:
    // any part's cast · any part's staging grid · the play grid · any part's rowUnder reverts · pending row/cell
    // restores · the pulse candidate · the current selection. Anything else — ephemeral registry entries AND document
    // VARIATION slots (hue-overridden) — is freed. The canonical defaults (no override) are never touched.
    private func buildGCColours() {
        var live = Set<String>()
        live.formUnion(buildPartCast); for p in buildParts { live.formUnion(p.cast) }
        func addCells(_ cells: [[String?]]) { for col in cells { for c in col { if let c = c { live.insert(c) } } } }
        addCells(buildStagingCells); addCells(buildPerformCells); for p in buildParts { addCells(p.stagingCells) }
        for u in buildRowUnder { if let u = u { live.insert(u) } }
        for p in buildParts { for u in p.rowUnder { if let u = u { live.insert(u) } } }
        for (_, row) in buildDeletedRows { for c in row { if let c = c { live.insert(c) } } }
        for (_, c) in buildPlacedOrig { if let c = c { live.insert(c) } }
        if let p = buildPulseColourID { live.insert(p) }
        if let s = buildSelID { live.insert(s) }
        for p in buildParts { if let s = p.selID { live.insert(s) } }               // C3 (Paul 2026-08-16): a part's STORED selection keeps its colour alive — else GC frees it and buildLoadPart selects a dead id
        let dead = Set(buildColourReg.keys).union(colourHueOverride.keys).subtracting(live)
        guard !dead.isEmpty else { return }
        for id in dead { buildColourReg[id] = nil; colourHueOverride[id] = nil }   // free ephemeral + variation hues
        let docDead = dead.filter { colourIDs.contains($0) }                        // document VARIATION slots → undefine
        if !docDead.isEmpty {
            au?.editDocument { doc in for id in docDead { if let i = colourIDs.firstIndex(of: id), i < doc.colours.count { doc.colours[i].defined = false; doc.colours[i].templateChain = nil } } }
            refreshFromDocument()
        }
        buildSyncColours()
    }

    private func buildStageTheGrid() {
        for c in 0..<8 { for r in 0..<8 { if let id = buildStagingCells[c][r], !buildPartCast.contains(id) { buildStagingCells[c][r] = nil } } }   // strip prior (un-adopted) variations → back to the originals
        buildGCColours()                                                       // free the reclaimed variation colours
        var order: [String] = (0..<8).compactMap { buildRowColour($0) }        // the ORIGINAL populated rows, top→bottom (one colour each)
        guard !order.isEmpty else { return }
        var rng = SystemRandomNumberGenerator()
        var dup: [String: Int] = Dictionary(uniqueKeysWithValues: order.map { ($0, 0) })
        while order.count < 8 {   // unlimited now — buildNewColour overflows to ephemeral colours past the 16 slots
            guard let source = order.min(by: { (dup[$0] ?? 0, order.firstIndex(of: $0)!) < (dup[$1] ?? 0, order.firstIndex(of: $1)!) }) else { break }
            let srcMachine = buildColourChain(source)
            let mutated = buildVaryChain(srcMachine, &rng)
            let srcC = buildComplexity(srcMachine), newC = buildComplexity(mutated)
            let hue = buildSimilarHue(of: source, lighter: newC < srcC, srcC: srcC, newC: newC)
            let newID = buildNewColour(hex: hue, machine: mutated)             // document slot OR ephemeral; NOT added to the cast
            order.insert(newID, at: newC < srcC ? order.firstIndex(of: source)! : order.firstIndex(of: source)! + 1)   // lighter above · darker below
            dup[newID] = 0; dup[source, default: 0] += 1
        }
        refreshFromDocument()
        for r in 0..<8 {                                                       // lay the reordered rows top→bottom; machines are on the templates
            let cid = r < order.count ? order[r] : nil
            for c in 0..<8 { buildStagingCells[c][r] = cid; buildPlacedOrig.removeValue(forKey: c * 8 + r) }
            if r < buildRowChain.count { buildRowChain[r] = [] }
            if r < buildRowUnder.count { buildRowUnder[r] = nil }
        }
        buildReconcileStagingSel()                                            // keep each column's pick valid after the reshuffle
        buildDeletedRows.removeAll()
        buildSelectStagingVoice()                                             // play the staging grid (publishes the scene)
    }

    // One VARIATION of `base`: 1–3 random mutations (insert / remove / retype / bypass a slot), guaranteed audible.
    private func buildVaryChain(_ base: [ProcessorSlot], _ rng: inout SystemRandomNumberGenerator) -> [ProcessorSlot] {
        var chain = base
        if chain.isEmpty { chain = Dice.rollSimple(using: &rng) }
        for _ in 0..<Int.random(in: 1...3, using: &rng) {
            switch Int.random(in: 0..<4, using: &rng) {
            case 0 where chain.count < 6:
                if let s = Dice.rollSimple(using: &rng).first { chain.insert(s, at: Int.random(in: 0...chain.count, using: &rng)) }
            case 1 where chain.count > 1:
                chain.remove(at: Int.random(in: 0..<chain.count, using: &rng))
            case 2:
                let i = Int.random(in: 0..<chain.count, using: &rng); chain[i].type = ProcessorType.allCases.randomElement(using: &rng)!
            default:
                let i = Int.random(in: 0..<chain.count, using: &rng); chain[i].bypassed.toggle()
            }
        }
        if chain.isEmpty || chain.allSatisfy({ $0.bypassed }) || Dice.signature(chain).isEmpty { chain = Dice.rollSimple(using: &rng) }
        return chain
    }

    // Keep the per-column selection VALID: a selection pointing at an empty cell falls back to the topmost stocked cell
    // in that column (the gentle default), or −1 if the column is empty. An explicit valid selection is preserved.
    private func buildReconcileStagingSel() {
        buildStagingSel = BuildSceneLogic.reconcileStagingSel(buildStagingSel, cells: buildStagingCells)   // C1: an explicit −1 deselect is preserved, not resurrected
    }

    // Push the current staging grid to the engine IF the staging voice is live (call after any staging-grid edit).
    private func buildStagingSyncIfPlaying() { buildPublishScene() }   // re-publish the combined (part + piece) scene after an edit

    // BUILD RANDOMIZE — the SIMPLER roll (a short 1–3-slot all-contributing chain, no macros); writes it colour-wide.
    private func buildRandomizeSimple() {
        guard let cid = ddSelectedColourID else { return }
        var rng = SystemRandomNumberGenerator()
        au?.withChainColour(cid) { $0 = Dice.rollSimple(using: &rng) }
        refreshFromDocument()
    }

    // The selected colour's OWN processors (its templateChain) — shown on the footer. Interior EMPTY boxes (passthrough
    // placeholders) are kept so a processor's POSITION is remembered even with empty boxes to its left; TRAILING empties
    // collapse to "+" capacity slots. A fully blank/new colour → [] (all boxes are "+").
    private func selectedColourChain() -> [ProcessorSlot] {
        guard let cid = ddSelectedColourID else { return [] }
        var chain = buildColourMachine(cid)
        while let last = chain.last, buildIsEmptySlot(last) { chain.removeLast() }
        return chain
    }
    // An EMPTY processor box = a passthrough placeholder (a bypassed PASSGATE — a true no-op the engine passes through).
    private func buildIsEmptySlot(_ s: ProcessorSlot) -> Bool { s.type == .passgate && s.bypassed }
    private func buildPassthroughSlot() -> ProcessorSlot { var s = ProcessorSlot(type: .passgate); s.bypassed = true; return s }

    // ── PARTS lifecycle (unassigned → built → staged → deployed) ─────────────────────────────────────────────────
    // The CURRENT part's fields live in the working @State (buildStagingCells etc.); these snapshot/restore them so
    // switching parts keeps each part's workshop intact (§3). (design ferry: AcceptanceCriteria-part-lifecycle-io)
    private func buildSavePart() {
        guard buildCurrentPart >= 0, buildCurrentPart < buildParts.count else { return }
        var p = buildParts[buildCurrentPart]
        p.stagingCells = buildStagingCells; p.stagingSel = buildStagingSel
        p.rowChain = buildRowChain; p.rowShade = buildRowShade; p.rowUnder = buildRowUnder
        p.selID = buildSelID; p.receiver = buildSelReceiver; p.emitters = buildPartEmitters; p.cast = buildPartCast; p.castSlots = buildCastSlots
        buildParts[buildCurrentPart] = p
    }
    private func buildLoadPart(_ i: Int) {
        guard i >= 0, i < buildParts.count else { return }
        buildCurrentPart = i
        let p = buildParts[i]
        buildStagingCells = p.stagingCells; buildStagingSel = p.stagingSel
        buildRowChain = p.rowChain; buildRowShade = p.rowShade; buildRowUnder = p.rowUnder
        buildSelID = p.selID; ddColourSel = p.selID.flatMap { colourIDs.firstIndex(of: $0) } ?? -1; buildSelReceiver = p.receiver; buildPartEmitters = p.emitters; buildPartCast = p.cast; buildCastSlots = p.castSlots
        buildReslotCast()                                       // migrate old parts + backfill any extra colour missing a slot
        buildEnforceCastHues()                                  // strong rule: no two palette colours share a hue
        buildPulseColourID = nil; buildAuditionID = nil; buildDeletedRows = [:]; buildPlacedOrig = [:]   // transient — never crosses a part
        buildEnsureCastSelection()                              // §2: keep the selection inside this part's cast (empty cast → none)
        buildStagingSyncIfPlaying()
    }

    // ── PERSISTENCE (Paul 2026-08-16): the single UNASSIGNED part is saved with the document ("saving = committing").
    // CAPTURE is READ-ONLY (never touches @State, so it's safe to call from the 4 Hz poll): the live workshop if the
    // current part is the unassigned one, else the stored unassigned part. Bundles the EPHEMERAL colours it references
    // (machine + hue) so it reconstructs on load; canonical document colours are always present, so they aren't bundled.
    func buildCaptureUnassigned() -> BuildUnassignedData? {
        let part: BuildPart
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count, !buildParts[buildCurrentPart].deployed {
            var p = BuildPart()                                 // the live workshop IS the unassigned part — freshest from @State
            p.stagingCells = buildStagingCells; p.stagingSel = buildStagingSel; p.rowChain = buildRowChain
            p.rowShade = buildRowShade; p.rowUnder = buildRowUnder; p.selID = buildSelID
            p.receiver = buildSelReceiver; p.emitters = buildPartEmitters; p.cast = buildPartCast; p.castSlots = buildCastSlots; p.deployed = false
            part = p
        } else if let stored = buildParts.first(where: { !$0.deployed }) {
            part = stored                                       // viewing a deployed part → the unassigned one is stored
        } else { return nil }
        guard part.stagingCells.contains(where: { $0.contains { $0 != nil } }) else { return nil }   // no content yet → nothing to save
        var ids = Set(part.cast)                                // every colour the part could reference
        ids.formUnion(part.stagingCells.flatMap { $0.compactMap { $0 } })
        ids.formUnion(part.rowUnder.compactMap { $0 })
        if let s = part.selID { ids.insert(s) }
        let ephemeral = ids.filter { buildColourReg[$0] != nil }.sorted()
        let colours = ephemeral.map { id -> Colour in var c = Colour(colourID: id, type: .arp); c.defined = true; c.templateChain = buildColourReg[id]; return c }
        var hues: [String: UInt32] = [:]; for id in ephemeral { if let h = colourHueOverride[id] { hues[id] = h } }
        return BuildUnassignedData(part: part, colours: colours, hues: hues, idCounter: buildIDCounter)
    }
    // RESTORE the saved unassigned part on load: re-register its ephemeral colours + hues, lift the id counter past
    // them (so new colours don't collide), then place it as the single unassigned part and load it into the workshop.
    func buildRestoreUnassigned(_ u: BuildUnassignedData) {
        for c in u.colours { buildColourReg[c.colourID] = c.templateChain ?? [] }
        for (id, hue) in u.hues { colourHueOverride[id] = hue }
        buildIDCounter = max(buildIDCounter, u.idCounter)
        buildSyncColours()
        var part = u.part; part.deployed = false
        if let i = buildParts.firstIndex(where: { !$0.deployed }) { buildParts[i] = part; buildLoadPart(i) }
        else { buildParts.append(part); buildLoadPart(buildParts.count - 1) }
    }
    // The per-poll persistence tick (BUILD active only): restore a just-loaded part ONCE, then keep the save-state current.
    func buildPersistTick() {
        guard activeTab == .build else { return }
        if let u = au?.consumeBuildUnassigned() { buildRestoreUnassigned(u) }   // a host load happened while on BUILD
        au?.setBuildUnassigned(buildCaptureUnassigned())                         // keep fullState's copy fresh
    }
    // THE DEFAULT PALETTE (Paul 2026-08-14): eight starter colours, one per processor type (arp/ratchet/euclid/echo
    // named + strum/chance/harmonize/drone — NEVER passgate). They open the palette as 2 rows of 4 and are present in
    // every part's cast. Each carries a single-processor machine at that type's default settings.
    static let buildDefaultTypes: [ProcessorType] = [.arp, .ratchet, .euclid, .weave, .echo, .strum, .chance, .split, .tutti, .length, .harmonize, .drone]
    // Mint a FRESH set of 8 default colours for a PART — its OWN ephemeral copies (unique IDs, canonical hues), so a
    // colour is NEVER shared between parts. Editing one part's default doesn't touch another's. (Paul 2026-08-15)
    func buildFreshDefaultCast() -> [String] {
        var ids: [String] = []
        for (i, t) in Self.buildDefaultTypes.enumerated() {
            buildIDCounter += 1
            let id = "b\(buildIDCounter)"
            buildColourReg[id] = [ProcessorSlot(type: t)]
            colourHueOverride[id] = i < colourHexes.count ? colourHexes[i] : 0x808080
            ids.append(id)
        }
        buildSyncColours()
        return ids
    }
    // Mint a TAB colour: an ephemeral colour carrying `machine` with tab n's FIXED hue (colourHexes[n]), verbatim
    // (no uniquify — a tab always shows the same colour). (Paul 2026-08-17 — the 8-tab model)
    private func buildNewTabColour(_ n: Int, machine: [ProcessorSlot]) -> String {
        let hex = n < colourHexes.count ? colourHexes[n] : 0x808080
        buildIDCounter += 1
        let id = "b\(buildIDCounter)"
        buildColourReg[id] = machine
        colourHueOverride[id] = hex
        buildSyncColours()
        return id
    }
    // Seed TAB 1 (part-grid row 1) with an EMPTY PASSTHROUGH colour; tabs 2–8 stay empty. It plays + is selected.
    private func buildSeedTab1() {
        let y1 = buildNewTabColour(0, machine: [])
        buildSetRow(0, to: y1)
        buildPartCast = [y1]; buildCastSlots = [:]
        for c in 0..<8 { buildStagingSel[c] = 0 }
        buildSelectID(y1)
    }
    // Seed the workshop ONCE, on first BUILD appear. (Was: 8×4 default cast; now the single TAB 1.) §2.
    func buildSeedCastIfNeeded() {
        guard !buildCastSeeded else { return }
        buildCastSeeded = true
        buildSeedTab1()
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count { buildParts[buildCurrentPart].cast = buildPartCast }
    }
    // Keep the selection within the PART's cast (its own palette). A fresh, EMPTY cast → NO selection: the footer + the
    // machine audition have nothing until the user adds a colour. Replaces the global ddEnsureSelection on BUILD. §2.
    func buildEnsureCastSelection() {
        if let cid = ddSelectedColourID, buildPartCast.contains(cid) { return }   // already a valid cast member
        if let first = buildPartCast.first { buildSelectID(first) } else { buildSelID = nil; ddColourSel = -1 }
    }
    private func buildSwitchPart(_ i: Int) { guard i != buildCurrentPart else { return }; buildReturnPart = nil; buildSavePart(); buildLoadPart(i) }   // any manual switch cancels a pending return
    // A RESTORE switch (via a valve): remember the UNDEFINED bench we're leaving, so the next promote returns to it
    // instead of a blank part. (Paul 2026-08-15 QoL)
    private func buildRestoreSwitch(to p: Int) {
        let returning = (buildCurrentPart >= 0 && buildCurrentPart < buildParts.count && !buildParts[buildCurrentPart].deployed) ? buildCurrentPart : nil
        buildSwitchPart(p)                                   // clears buildReturnPart …
        buildReturnPart = returning                          // … then records the bench to come back to
    }
    // A part is UNUSED when nothing distinguishes it from a just-created one: un-deployed, empty staging, and its cast
    // is exactly its 8 pristine per-part defaults (no edits/adds). (Paul 2026-08-15 — per-part colours)
    private func buildPartIsUnused(_ p: BuildPart) -> Bool {
        guard !p.deployed, p.stagingCells.allSatisfy({ $0.allSatisfy { $0 == nil } }), p.cast.count == Self.buildDefaultTypes.count else { return false }
        return zip(p.cast, Self.buildDefaultTypes).allSatisfy { id, t in buildColourReg[id] == [ProcessorSlot(type: t)] }
    }
    // §3: a NEW part arrives FRESH — empty staging, unset I/O; its palette opens on the 8 DEFAULTS (Paul 2026-08-14).
    // REUSE an existing unused part instead of appending, so flatten→restore stops accumulating stray "UNASSIGNED PART"
    // entries. Reuse touches only an empty, un-deployed slot, so no deployed part's stored index shifts. (Paul 2026-08-15)
    private func buildAddPart() {
        buildSavePart()
        // QoL: if a restore left an undefined bench pending, RETURN to it (the part the user was building) instead of a
        // fresh one — so restore→promote drops them back on their in-progress work. (Paul 2026-08-15)
        if let ret = buildReturnPart, ret != buildCurrentPart, ret < buildParts.count, !buildParts[ret].deployed {
            buildReturnPart = nil; buildLoadPart(ret); return
        }
        buildReturnPart = nil
        if let reuse = buildParts.indices.first(where: { $0 != buildCurrentPart && buildPartIsUnused(buildParts[$0]) }) {
            buildLoadPart(reuse)   // pristine already — keep its OWN per-part defaults, just switch to it
        } else {
            let fresh = BuildPart()                                         // a new part opens on TAB 1 (empty passthrough)
            buildParts.append(fresh); buildLoadPart(buildParts.count - 1)
            buildSeedTab1()
        }
    }
    // A SINGLE deployed row = the staging SELECTION flattened: the selected cell per column (wherever its staging row
    // sits), and a column with NOTHING selected is left BLANK. Carries the part's I/O. Does NOT set deployed/claim/publish
    // — the caller owns those. (Paul 2026-08-14: single-row targets copy the selected cell regardless of row.)
    private func buildCopySelectedRow(toRow R: Int) {
        guard R >= 0, R < 8 else { return }
        for c in 0..<8 {
            let sr = c < buildStagingSel.count ? buildStagingSel[c] : -1   // this column's selected (playing) cell
            if sr >= 0, sr < 8, let cid = buildStagingCells[c][sr] {
                buildPerformCells[c][R] = cid
                buildPerformChain[c][R] = (sr < buildRowChain.count && !buildRowChain[sr].isEmpty) ? buildRowChain[sr] : []
            } else {
                buildPerformCells[c][R] = nil; buildPerformChain[c][R] = []   // nothing selected → blank in the play grid
            }
        }
        buildPerformRecv[R] = buildSelReceiver                   // the row carries the deploying part's I/O
        buildPerformEmit[R] = buildPartEmitters.isEmpty ? [.a] : buildPartEmitters
    }

    // §1: deploying the current part to a SINGLE play-grid row CHRISTENS it (PART n) and copies its per-column selection
    // into the tapped row (selected cell regardless of staging row · blank where unselected), carrying the part's I/O.
    func buildDeployCurrentPart(toRow R: Int) {
        guard buildCurrentPart < buildParts.count, R >= 0, R < 8 else { return }
        buildParts[buildCurrentPart].deployed = true
        buildCopySelectedRow(toRow: R)
        buildPerformPart[R] = buildCurrentPart                   // §2: the row now belongs to this part
        buildPerformStagingRow[R] = -1                           // a single-rung lane — no rung map (per-cell mute, not selection)
        for c in 0..<8 { buildPerformMute.remove(c * 8 + R) }    // fresh row starts unmuted
        buildPublishScene()                                      // reflect live if the piece is playing
    }

    // Land the current part on a BAND. Christens like a flatten. (Paul 2026-08-14 — deployment semantics by target shape:)
    //   • MULTI-ROW band (rows > 1): copy the whole staging LADDER — every OCCUPIED staging row (selected AND muted cells)
    //     becomes a band rung, top-down, capped to the band's height. Nothing is dropped; the muted cells are the rungs.
    //   • SINGLE-ROW band (rows == 1): the selected cell per column (regardless of row), blank where unselected.
    func buildDeployBand(base: Int, rows: Int) {
        guard buildCurrentPart < buildParts.count else { return }
        buildParts[buildCurrentPart].deployed = true
        for i in 0..<rows where base + i < 8 { for c in 0..<8 { buildPerformCells[c][base + i] = nil; buildPerformChain[c][base + i] = []; buildPerformMute.remove(c * 8 + base + i) }; buildPerformPart[base + i] = buildCurrentPart; buildPerformStagingRow[base + i] = -1 }   // clear the band (+ its mutes + rung map) + claim it (§2)
        if rows <= 1 {
            buildCopySelectedRow(toRow: base)                    // a lane: the selected melody, blank where unselected
        } else {
            let occupied = (0..<8).filter { sr in (0..<8).contains { c in buildStagingCells[c][sr] != nil } }   // staging rows that hold ANY cell
            for (i, sr) in occupied.prefix(rows).enumerated() {  // one rung per occupied staging row (muted cells included)
                let R = base + i; guard R < 8 else { break }
                buildPerformStagingRow[R] = sr                   // remember which staging row this rung came from (for selection sync-back)
                for c in 0..<8 {
                    if let cid = buildStagingCells[c][sr] {
                        buildPerformCells[c][R] = cid
                        buildPerformChain[c][R] = (sr < buildRowChain.count && !buildRowChain[sr].isEmpty) ? buildRowChain[sr] : []
                    }
                }
                buildPerformRecv[R] = buildSelReceiver
                buildPerformEmit[R] = buildPartEmitters.isEmpty ? [.a] : buildPartEmitters
            }
        }
        buildPublishScene()
    }

    // THE VALVE (design ferry: row-button-valve) — the LEFT band selector is a FLATTEN ⇄ RESTORE toggle.
    // EMPTY band → flatten the current part onto it (deploy + christen), STASH its workshop behind the band, and open
    // a FRESH part (staging/column clear). SET band (already holds a part) → UNLOAD it and RESTORE that part's stashed
    // workshop (a part switch: the current workshop retains under its own part). The RIGHT per-row rung-flatten is the
    // held exception — left unchanged until Paul defines it.
    // Shared valve output/focus (Paul 2026-08-14/15): chain audition off; FOCUS the part grid. PROMOTE starts the play
    // grid (it carries the output; the fresh part is empty/silent). RESTORE keeps the play grid going iff other parts
    // remain deployed, and the restored part plays from the part grid alongside.
    private func buildValveOutput(promote: Bool) {
        if ddSolo { ddSolo = false; au?.clearColourSolo() }
        buildStagingPlaying = true
        buildPerformPlaying = promote ? true : buildPerformPart.contains { $0 >= 0 }
        buildPublishScene()
    }
    // The play grid's band form → the (base, rows) range containing a grid row, and the band's 1-based label number.
    private func buildBandRange(forRow r: Int) -> (base: Int, rows: Int)? {
        var base = 0; for rows in [3, 2, 1, 1, 1] { if r >= base && r < base + rows { return (base, rows) }; base += rows }; return nil
    }
    private func buildBandNumber(base: Int) -> Int {
        var acc = 0; for (b, rows) in [3, 2, 1, 1, 1].enumerated() { if acc == base { return b + 1 }; acc += rows }; return 1
    }
    // A band is WHOLE (one part fills every rung — a LEFT-valve deploy) vs PER-RUNG (separate sub-parts on its rungs, or
    // partly empty — RIGHT-valve deploys). The two are mutually exclusive on a band. (Paul 2026-08-15)
    private func buildBandIsWhole(base: Int, rows: Int) -> Bool {
        let ps = (0..<rows).compactMap { base + $0 < 8 ? buildPerformPart[base + $0] : nil }
        return ps.allSatisfy { $0 >= 0 } && Set(ps).count == 1
    }
    private func buildRowInWholeBand(_ r: Int) -> Bool { buildBandRange(forRow: r).map { buildBandIsWhole(base: $0.base, rows: $0.rows) } ?? false }

    // LEFT band valve — the WHOLE band. EMPTY → flatten the current part onto every rung (deploy + christen · stash ·
    // clear · fresh part). WHOLE (one part fills it) → restore ALL rungs to the part grid. PER-RUNG band → INERT (use
    // the right buttons to restore individual rungs).
    func buildBandValve(base: Int, rows: Int) {
        let anySet = (0..<rows).contains { base + $0 < 8 && buildPerformPart[base + $0] >= 0 }
        if !anySet {
            buildDeployBand(base: base, rows: rows); buildAddPart(); buildValveOutput(promote: true)
        } else if buildBandIsWhole(base: base, rows: rows), buildPerformPart[base] >= 0, buildPerformPart[base] < buildParts.count {
            let p = buildPerformPart[base]
            buildRestoreSwitch(to: p)
            for i in 0..<rows where base + i < 8 { for c in 0..<8 { buildPerformCells[c][base + i] = nil; buildPerformChain[c][base + i] = []; buildPerformMute.remove(c * 8 + base + i) }; buildPerformPart[base + i] = -1; buildPerformStagingRow[base + i] = -1 }
            buildParts[p].deployed = false
            buildValveOutput(promote: false)
        }
        // else PER-RUNG → inert
    }
    // RIGHT per-rung valve (Paul 2026-08-15) — a SINGLE rung of a multi-row band, stored as a sub-part "PART na/nb/nc".
    // EMPTY rung → flatten the current part onto it (single-row flatten · stash · clear · fresh part). SET rung → restore
    // JUST that sub-part to the part grid (one at a time; the other rungs stay deployed). Inert on a WHOLE-band band.
    func buildRowValve(row R: Int) {
        guard R >= 0, R < 8, !buildRowInWholeBand(R) else { return }
        let p = buildPerformPart[R]
        if p >= 0, p < buildParts.count {                    // SET → restore this rung's sub-part
            buildRestoreSwitch(to: p)
            for c in 0..<8 { buildPerformCells[c][R] = nil; buildPerformChain[c][R] = []; buildPerformMute.remove(c * 8 + R) }
            buildPerformPart[R] = -1; buildPerformStagingRow[R] = -1
            buildParts[p].deployed = false
            buildValveOutput(promote: false)
        } else {                                             // EMPTY rung → deploy the current part to this single rung
            buildDeployCurrentPart(toRow: R); buildAddPart(); buildValveOutput(promote: true)
        }
    }

    // START/STOP THE PLAY GRID — the PIECE voice (third zoom level). INDEPENDENT of the auditions (correction):
    // starting/stopping it never touches the chain/part; the stage plays until the user stops it.
    private func buildTogglePerformVoice() {
        buildPerformPlaying.toggle()
        buildPublishScene()
    }
    // How many play-grid rows a deployed part occupies (1 = single-rung lane · >1 = multi-rung ladder).
    private func buildPerformPartRows(_ part: Int) -> Int { part < 0 ? 0 : (0..<8).filter { buildPerformPart[$0] == part }.count }
    // MUTE a single-rung part's cell (dropped from the mix) — toggled on the play grid, reflected live.
    private func buildTogglePerformMute(_ c: Int, _ r: Int) {
        let k = c * 8 + r
        if buildPerformMute.contains(k) { buildPerformMute.remove(k) } else { buildPerformMute.insert(k) }
        buildPublishScene()
    }
    // A play-grid cell SOUNDS this column when it's the active rung: single-rung parts always; a multi-rung part only
    // when its column's selection points at this rung's source staging row. (Paul 2026-08-15)
    private func buildPerformActiveRung(_ c: Int, _ r: Int) -> Bool {
        let part = buildPerformPart[r]
        guard part >= 0, buildPerformPartRows(part) > 1 else { return true }   // single-rung / empty band → always
        let sr = buildPerformStagingRow[r]
        return sr >= 0 && part < buildParts.count && c < buildParts[part].stagingSel.count && buildParts[part].stagingSel[c] == sr
    }
    // Tap a multi-rung cell → make it the column's active rung, or deselect it (column silent). Writes the DEPLOYED
    // part's stashed selection directly, so live changes mirror back to the part grid on revert. (Paul 2026-08-15)
    private func buildTogglePerformRung(_ c: Int, _ r: Int) {
        let sr = buildPerformStagingRow[r]; let part = buildPerformPart[r]
        guard sr >= 0, part >= 0, part < buildParts.count, c < buildParts[part].stagingSel.count else { return }
        let newSel = (buildParts[part].stagingSel[c] == sr) ? -1 : sr
        buildParts[part].stagingSel[c] = newSel
        if part == buildCurrentPart, c < buildStagingSel.count { buildStagingSel[c] = newSel }   // C2 (Paul 2026-08-16): keep the LIVE copy in sync, else the next buildSavePart clobbers this rung toggle
        buildPublishScene()
    }
    private var buildCurrentDeployed: Bool { buildCurrentPart < buildParts.count && buildParts[buildCurrentPart].deployed }
    // A deployed part is named for WHERE it lives: a WHOLE band → "PART n" (n = band number); a single rung of a
    // multi-row band → "PART na/nb/nc" (letter = the rung). Unassigned → "UNASSIGNED PART". (Paul 2026-08-15)
    private func buildPartName(_ i: Int) -> String {
        guard i >= 0, i < buildParts.count, buildParts[i].deployed else { return "UNASSIGNED PART" }
        let rows = (0..<8).filter { buildPerformPart[$0] == i }
        guard let first = rows.first, let (base, bandRows) = buildBandRange(forRow: first) else { return "PART \(i + 1)" }
        let n = buildBandNumber(base: base)
        if rows.count >= bandRows { return "PART \(n)" }                          // whole band (incl. a single-row lane)
        let letters = ["a", "b", "c", "d"], rung = first - base
        return "PART \(n)\(rung < letters.count ? letters[rung] : "")"           // a single rung of a multi-row band
    }

    @ViewBuilder private func buildPartHeader() -> some View {
        HStack(spacing: 6) {
            Menu {                                                // the selector — switch between parts
                ForEach(0..<buildParts.count, id: \.self) { i in Button(buildPartName(i)) { buildSwitchPart(i) } }
            } label: {
                Text("\(buildPartName(buildCurrentPart)) ▾").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(buildPanel))
                    .overlay(alignment: .bottom) { Rectangle().fill(buildPartInk).frame(height: 2) }   // §2: the part's bright-ink underline
            }
            // ADD PART — GLOWS (pink) once the current part is deployed; only then is it askable.
            Text("ADD PART").font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(buildCurrentDeployed ? .black : buildDim)
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(buildCurrentDeployed ? buildPink : buildCell))
                .opacity(buildCurrentDeployed ? 1 : 0.45)
                .contentShape(Rectangle())
                .onTapGesture { if buildCurrentDeployed { buildAddPart() } }
            Spacer(minLength: 0)
        }
    }

    // The per-grid PLAY/EDIT radio — two chips styled exactly like the PART 1 ▾ header (size-10 heavy mono, h26,
    // buildPanel), RIGHT-aligned so it sits at PART 1's row above each grid. The active side fills cyan.
    @ViewBuilder private func buildGridModeRadio(_ mode: Binding<BuildGridMode>, onEye: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)                                  // the eye moved to the grid's top-left corner (buildGridCornerEye)
            ForEach([BuildGridMode.play, .edit], id: \.self) { m in
                Text(m.rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(mode.wrappedValue == m ? .black : buildDim)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(mode.wrappedValue == m ? buildCyan : buildPanel))
                    .contentShape(Rectangle())
                    .onTapGesture { mode.wrappedValue = m }
            }
        }
    }
    // The grid's full-screen "eye" — seated in the grid's TOP-LEFT CORNER cell (immediately left of the column
    // selectors, immediately above the row selectors). popup 0 = the part grid · 1 = the play grid. (Paul 2026-08-17)
    @ViewBuilder private func buildGridCornerEye(cell: CGFloat, popup: Int) -> some View {
        Image(systemName: "eye").font(.system(size: min(15, cell * 0.55), weight: .semibold)).foregroundColor(buildCyan)
            .frame(width: cell, height: cell)
            .background(RoundedRectangle(cornerRadius: 6).fill(buildPanel))
            .contentShape(Rectangle())
            .onTapGesture { if popup == 1 { buildPlayMode = .play }; buildGridPopup = popup }
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
            .frame(maxWidth: .infinity).frame(height: 52)         // fills the midi-select row
            .background(RoundedRectangle(cornerRadius: 7).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildEdge, lineWidth: 1))
        }
    }

    // The octave keyboard for the selected PIANO door (one octave from C3, matching the receiver keyboard). Tap a key
    // to pick/unpick it into the door's frozen pool; dimmed + inert when the door isn't in PIANO mode.
    @ViewBuilder private func buildKeyboard(receiver i: Int, held: Set<Int>, enabled: Bool, width: CGFloat) -> some View {
        let startNote = 48                                    // C3, one octave (matches ReceiverConfigView)
        let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
        let blackAfter: [Int: Int] = [0: 1, 1: 3, 3: 6, 4: 8, 5: 10]
        let ww = max(1, width / 7)
        let bw = ww * 0.62
        ZStack(alignment: .topLeading) {
            // WHITE keys — a real HStack (LAYOUT-positioned, NOT .offset). `.offset` keeps each view's layout frame at
            // x=0 and only shifts the render, which breaks hit-testing here; an HStack gives each key an honest frame.
            HStack(spacing: 1) {
                ForEach(0..<7, id: \.self) { wi in
                    let note = startNote + whiteOffsets[wi]
                    RoundedRectangle(cornerRadius: 3).fill(held.contains(note) ? buildCyan : Color(white: 0.9))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(buildPanel, lineWidth: 1))
                        .frame(width: max(1, ww - 1), height: 52)
                        .contentShape(Rectangle())
                        .onTapGesture { au?.toggleReceiverPianoNote(i, note); receivers = au?.uiReceivers() ?? receivers; refreshFromDocument() }
                }
            }
            // BLACK keys straddle white-key boundaries → positioned in an overlay HStack of per-white slots (still
            // layout-based: each slot is ww wide, its black key pinned trailing so it sits over the boundary).
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { wi in
                    Color.clear.frame(width: ww, height: 52)
                        .overlay(alignment: .trailing) {
                            if let bOff = blackAfter[wi] {
                                let note = startNote + bOff       // pinned to the white-key boundary (trailing) — NO .offset, so its hit frame is honest
                                RoundedRectangle(cornerRadius: 2).fill(held.contains(note) ? buildCyan : buildPanel)
                                    .frame(width: bw, height: 31)
                                    .contentShape(Rectangle())
                                    .onTapGesture { au?.toggleReceiverPianoNote(i, note); receivers = au?.uiReceivers() ?? receivers; refreshFromDocument() }
                            }
                        }
                }
            }
            .allowsHitTesting(true)
        }
        .frame(width: width, height: 52, alignment: .topLeading)
        .padding(.vertical, 2)
        .opacity(enabled ? 1 : 0.35)
        .allowsHitTesting(enabled)
    }

    // The per-receiver SOURCE toggle flanking the piano: a DIN connector (MIDI in) on the left, the in-app piano on
    // the right — piano-height, half an R1 button wide. The active side is filled cyan.
    @ViewBuilder private func buildSourceToggle(_ icon: String, active: Bool, width: CGFloat, rotate: Bool = false, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {                        // a Button (not onTapGesture) — reliable hit-testing on this small target
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                .rotationEffect(.degrees(rotate ? 90 : 0))
                .foregroundColor(active ? .black : buildDim)
                .frame(width: width, height: 52)
                .background(RoundedRectangle(cornerRadius: 7).fill(active ? buildCyan : buildCell))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? Color.clear : buildEdge, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // OCT −/+ buttons under the piano (octave shift for the selected PIANO door).
    @ViewBuilder private func buildOctBtn(_ s: String, action: (() -> Void)? = nil) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildEdge, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }

    // MIDI OUT readout below the emitters — the lit emitters + their stamp channels. Piano-height, cast-width.
    @ViewBuilder private func buildMidiOutInfo(buses: Set<Bus>, castW: CGFloat) -> some View {
        let chans = au?.uiBusChannels() ?? [1, 2, 3, 4]
        let lit = Array(Bus.allCases.enumerated()).filter { buses.contains($0.element) }
        let summary = lit.isEmpty ? "—"
            : lit.map { "\($0.element.rawValue)→CH\(chans.indices.contains($0.offset) ? chans[$0.offset] : $0.offset + 1)" }.joined(separator: "   ")
        VStack(spacing: 3) {
            Text("MIDI OUT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1.2)
            Text(summary).font(.system(size: lit.count > 1 ? 11 : 15, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(width: castW, height: 52)
        .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
    }

    @ViewBuilder private func buildCastPalette(castW: CGFloat, cell: CGFloat) -> some View {
        let cols = 8                                                // 8×4 grid (original proportions); defaults sit in the top-left 4×2 block
        let swW = (castW - BuildGeom.castGap * CGFloat(cols - 1)) / CGFloat(cols)   // 8 swatches fill the column width
        let pulseSlot: Int? = {                                    // where the pulsing candidate lives (Paul 2026-08-14)
            guard let pid = buildPulseColourID else { return nil }
            if let existing = buildPartCast.firstIndex(of: pid) {  // already in the palette → pulse THAT slot, never a phantom new one …
                return pid == ddSelectedColourID ? nil : (0..<32).first { buildCastMemberAt($0) == existing }   // … UNLESS already selected
            }
            return buildFirstFreePaletteSlot()                     // a genuinely NEW colour → the "create me" candidate at the bottom-right
        }()
        VStack(spacing: BuildGeom.castGap) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: BuildGeom.castGap) {
                    ForEach(0..<cols, id: \.self) { col in
                        buildCastSlot(row * cols + col, swW: swW, swH: cell, pulseSlot: pulseSlot)   // rows sit at GRID-cell height so the cast aligns with the two grids
                    }
                }
            }
        }
    }

    // THE TARGET — a reticle marking the SELECTED machine wherever it appears: the cast swatch, the footer EXAMPLE cell,
    // and every grid cell that shares the selected colour (matches its properties). (Paul 2026-08-14)
    @ViewBuilder private func buildTargetMark(_ size: CGFloat) -> some View {
        Image(systemName: "scope")
            .font(.system(size: size, weight: .medium))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.7), radius: 1)
            .allowsHitTesting(false)
    }

    // One cast slot (of the 4×4 palette). DEFAULTS fill top-left, adds fill bottom-right (see buildCastMemberAt).
    @ViewBuilder private func buildCastSlot(_ i: Int, swW: CGFloat, swH: CGFloat, pulseSlot: Int?) -> some View {
        if i == pulseSlot, let pid = buildPulseColourID {          // the PULSING candidate → tap to commit (SELECT it; never a duplicate)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let phase = 0.5 + 0.5 * sin(tl.date.timeIntervalSinceReferenceDate * 3.4)   // pulse the colour in/out over black
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black)
                    RoundedRectangle(cornerRadius: 6).fill(colourColor(pid) ?? buildCell).opacity(0.15 + 0.85 * phase)
                }
                .frame(width: swW, height: swH)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))   // a NEUTRAL border — pulsing is NOT the selected/targeted state
                .contentShape(Rectangle())
                .onTapGesture { buildCommitPulse() }
            }
        } else if let m = buildCastMemberAt(i) {                   // a MEMBER of the cast — TAP selects, LONG-PRESS adds
            let id = buildPartCast[m]
            RoundedRectangle(cornerRadius: 6).fill(colourColor(id) ?? buildCell)
                .frame(width: swW, height: swH)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [3]))
                    .opacity(id == ddSelectedColourID ? 1 : 0))
                .overlay { if id == ddSelectedColourID { buildTargetMark(min(swW, swH) * 0.6) } }   // THE TARGET rides the selected cast cell
                .contentShape(Rectangle())
                .onTapGesture { buildSelectID(id) }
                .onLongPressGesture(minimumDuration: 0.4) { buildAddCastColour() }   // ANY button can ADD a colour — via long press (Paul 2026-08-14)
        } else {                                                   // an EMPTY slot — a "+" that ADDS on LONG PRESS (every button can add)
            RoundedRectangle(cornerRadius: 6).fill(buildCell)
                .frame(width: swW, height: swH)
                .overlay(Text("+").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(buildDim))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) { buildCloneLastColour(atSlot: i) }   // long-press an empty cell → clone the last-used colour onto THIS cell
        }
    }

    // THE PALETTE GRID stays 8×4 (32 slots). The 8 DEFAULTS occupy the TOP-LEFT 4×2 block (a proportion of the grid);
    // user-added colours fill from the BOTTOM-RIGHT corner (slot 31 first, then 30, …) so a new colour "starts bottom-right".
    private var buildCastDefaultCount: Int { min(Self.buildDefaultTypes.count, buildPartCast.count) }
    // Is a slot part of the top-left 4×2 DEFAULT block (which is positional), vs the freely-placeable extras region?
    private func buildIsDefaultSlot(_ slot: Int) -> Bool { let row = slot / 8, col = slot % 8; return row < 2 && col < 4 }
    // slot (0–31) → the buildPartCast index shown there, or nil (an empty slot). 8 cols × 4 rows. The default block is
    // positional (top-left); every OTHER colour sits where it was explicitly placed (buildCastSlots).
    private func buildCastMemberAt(_ slot: Int) -> Int? {
        let dc = buildCastDefaultCount
        if buildIsDefaultSlot(slot) {                                 // the top-left 4×2 default block
            let row = slot / 8, col = slot % 8, k = row * 4 + col
            return k < dc ? k : nil
        }
        guard let id = buildCastSlots[slot] else { return nil }       // extras live at their explicitly-placed slot
        return buildPartCast.firstIndex(of: id)
    }
    // The bottom-right-most FREE add slot — where the next auto-added colour lands (nil once the palette is full).
    private func buildFirstFreeCastSlot() -> Int? {
        for slot in stride(from: 31, through: 0, by: -1) where !buildIsDefaultSlot(slot) && buildCastSlots[slot] == nil { return slot }
        return nil
    }
    private func buildFirstFreePaletteSlot() -> Int? { buildFirstFreeCastSlot() }
    // Reconcile buildCastSlots with membership: drop stale slots, and give every extra member a slot (migrates old
    // parts saved before castSlots existed, and keeps auto-added colours visible).
    private func buildReslotCast() {
        buildCastSlots = buildCastSlots.filter { buildPartCast.contains($0.value) && !buildIsDefaultSlot($0.key) }
        let dc = buildCastDefaultCount
        var slotted = Set(buildCastSlots.values)
        for m in dc..<buildPartCast.count {
            let id = buildPartCast[m]
            if !slotted.contains(id), let s = buildFirstFreeCastSlot() { buildCastSlots[s] = id; slotted.insert(id) }
        }
    }
    // The next UNDEFINED global colour to materialize (nil = all 16 exist).
    private func buildFirstUndefinedGlobal() -> Int? { (0..<colourIDs.count).first { !ddColourShown($0) } }
    // ADD a fresh (passthrough) colour to THIS part's cast: a free DOCUMENT slot if one remains, else an unlimited
    // EPHEMERAL colour with a canonical-ish hue. Then select it. (Paul 2026-08-15 — no 16-colour cap.)
    // Long-pressing an empty cast cell CLONES the last-used colour: a brand-new colour carrying the SAME machine
    // (settings) as the currently-selected colour — the last one placed or whose settings were changed — under a
    // fresh unique hue. Falls back to a blank colour when nothing is selected yet. (Paul 2026-08-17)
    private func buildCloneLastColour(atSlot slot: Int? = nil) {
        guard let src = buildSelID else { buildAddCastColour(atSlot: slot); return }
        let id = buildNewColour(hex: buildDistinctHue(), machine: buildColourMachine(src))   // SAME settings, a genuinely DIFFERENT colour (never reuse the source hue)
        if !buildPartCast.contains(id) { buildPartCast.append(id) }
        buildPlaceCastSlot(id, slot)                                                          // land it on the LONG-PRESSED cell (else first-free)
        buildEnforceCastHues()                                                                // strong rule: never two alike in the cast
        buildPulseColourID = nil                                                              // the clone IS the commit — never leave the SOURCE strobing
        buildSelectID(id)
    }
    private func buildAddCastColour(atSlot slot: Int? = nil) {
        let id: String
        if let j = buildFirstUndefinedGlobal() {
            buildCreateColour(j); id = colourIDs[j]
        } else {
            buildIDCounter += 1; id = "b\(buildIDCounter)"
            buildColourReg[id] = []; colourHueOverride[id] = colourHexes[buildIDCounter % colourHexes.count]; buildSyncColours()
        }
        if !buildPartCast.contains(id) { buildPartCast.append(id) }
        buildPlaceCastSlot(id, slot)
        buildEnforceCastHues()                                                                // strong rule: never two alike in the cast
        buildSelectID(id)
    }
    // Assign a NON-default colour its cast slot: the requested one if it's a free extras cell, else the first free.
    private func buildPlaceCastSlot(_ id: String, _ requested: Int?) {
        buildCastSlots = buildCastSlots.filter { $0.value != id }                             // this colour claims exactly one slot
        if let s = requested, !buildIsDefaultSlot(s), buildCastSlots[s] == nil { buildCastSlots[s] = id }
        else if let s = buildFirstFreeCastSlot() { buildCastSlots[s] = id }
    }
    // Commit the pulsing candidate: a staged VARIATION becomes a NEW palette colour (carrying its machine); an existing
    // colour is simply selected. Either way the colour is SELECTED (its machine loads into the footer) — and THE TARGET
    // then marks it in the cast + on its selected grid cells, so the user edits the machine knowing what's in focus.
    private func buildCommitPulse() {
        guard let pid = buildPulseColourID else { buildPulseColourID = nil; return }
        if !buildPartCast.contains(pid) { buildPartCast.append(pid); buildPlaceCastSlot(pid, nil); buildEnforceCastHues() }   // LAST TOUCHED promotes the colour INTO the cast (first-free slot)
        if pid == buildAuditionID { buildAuditionID = nil }           // it graduated from candidate to a real cast colour
        buildSelectID(pid)                                             // select it (loads its machine into the footer)
        buildPulseColourID = nil; buildPulseChain = []
        refreshFromDocument()
    }
    // Create a colour on BUILD as a PASSTHROUGH machine (empty chain → unprocessed MIDI). A bare `defined` colour
    // has a nil templateChain, which the engine resolves via the LEGACY A-face — and every default colour is type
    // .arp, so it would play an arp the user can't see in the (empty) chain. Store a passthrough placeholder so the
    // audio matches the shown-empty chain. (user 2026-08-12)
    private func buildCreateColour(_ i: Int) {
        guard i < colourIDs.count else { return }
        ddCreateColour(i)
        au?.withChainColour(colourIDs[i]) { $0 = [] }          // [] → a bypassed-passgate passthrough (not the arp A-face)
        refreshFromDocument()
    }

    // ── MIDDLE COLUMN: STAGING (header · rail+loopkeys+grid · label) with the VERBS in their own box below ──────────
    @ViewBuilder private func buildStagingColumn(cell: CGFloat) -> some View {
        let hue = buildSelHue
        // the staging grid's total width = the row rail + 8 cells + the 8 gaps between them (rail↔grid + 7 inter-cell).
        let gridW = cell * 9 + BuildGeom.cellGap * 8              // row button + 8 cells + the 8 gaps between the 9
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THIS PART", active: buildDisplayVoice == .part, fill: .grid, enabled: buildStagingPopulated || buildPerformPopulated, action: { buildRequestWorkshopVoice(buildDisplayVoice == .part ? .none : .part) }))   // tap = play/STOP the part; enabled once EITHER grid has content
            AnyView(buildStagingGrid(cell: cell, hue: hue))       // AnyView — keeps the deep 8×8 type out of this body
            AnyView(buildStagingVerbBox(gridW: gridW))            // the SELECT · PLACE · MUTATE box IS this column's button box (a 3×2: verbs + reserved blanks)
            Spacer(minLength: 0)
            AnyView(buildReceiversBox())                         // bottom of the middle column — the four input doors (A–D), MOVED here from the left column (Paul 2026-08-18)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // STAGE THE GRID — the prominent call-to-action at the bottom of the centre column (upward chevron above the text).
    @ViewBuilder private func buildPopulate(gridW: CGFloat) -> some View {
        let enabled = buildStagingPopulated                                                  // disabled until ≥1 row is placed (Paul 2026-08-15)
        HStack(spacing: 5) {
            Image(systemName: "chevron.up").font(.system(size: 12, weight: .heavy)).foregroundColor(buildPink)
            Text("STAGE THE GRID").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1)
        }
        .frame(width: gridW).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(buildCell))                      // §0 MUTED: a restrained CTA — pink is a WHISPER (ink + edge), not a slab
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(buildPink.opacity(0.55), lineWidth: 1))
        .opacity(enabled ? 1 : 0.35)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { buildStageTheGrid() } }
        .allowsHitTesting(enabled)
    }

    // the staging 8×8 (row rail · loop keys · variation rows) — its OWN opaque view so its deep generic type doesn't
    // blow the metadata demangler's stack (see buildPaletteColumn's note).
    @ViewBuilder private func buildStagingGrid(cell: CGFloat, hue: Color) -> some View {
        HStack(alignment: .top, spacing: BuildGeom.cellGap) {
            buildRowButtons(cell: cell, hue: hue, bands: [8]) { row in                      // press a part-grid row button
                switch buildRowMode {
                case .select: buildSelectRow(row)                                           // select the whole row's rung
                case .place:  buildSelectRow(row)                                           // (PLACE retired — the colour tabs place now)
                case .mutate: buildMutateRow(row)                                           // a value-tweaked variant of the selected colour
                }
            }
            VStack(spacing: BuildGeom.cellGap) {
                buildLoopKeys(cell: cell)                          // the column-selector (loop-key) row
                VStack(spacing: BuildGeom.cellGap) {               // the staging grid — BLANK until stocked (PLACE)
                    ForEach(0..<8, id: \.self) { r in
                        HStack(spacing: BuildGeom.cellGap) {
                            ForEach(0..<8, id: \.self) { c in
                                let id = buildStagingCells[c][r]
                                let selected = buildStagingSel[c] == r   // a rung can be selected even when EMPTY (Paul 2026-08-15)
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(id.flatMap { colourColor($0) } ?? buildCell)   // ALWAYS the exact palette colour — no shading, no dimming (Paul 2026-08-15)
                                    .frame(width: cell, height: cell)
                                    .overlay(RoundedRectangle(cornerRadius: 7)     // WHITE box = the SELECTED (playing) rung; that alone decides playback
                                        .stroke(buildStagingStroke(c: c, r: r, stocked: id != nil), lineWidth: selected ? 2.5 : 2))
                                    // (the per-cell TARGET is gone — the selected colour now shows as the tinted ROW NUMBER on its rail, Paul 2026-08-17)
                                    .overlay { ZStack {
                                        if buildPendingTab == r { buildPulseOverlay() }   // PENDING tab → its row previews, pulsing
                                        buildNoteSweep(idx: c * 8 + r, active: buildStagingPlaying, id: id)   // THE NOTE SWEEP (v1)
                                    } }
                                    .contentShape(Rectangle())
                                    .onTapGesture { buildStagingTap(c, r) }
                            }
                        }
                    }
                }
                .overlay(alignment: .topLeading) { buildPlayhead(cell: cell, active: buildStagingPlaying) }   // sweeps only when the PART grid plays
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(buildPartInk, lineWidth: 1.5).padding(-4) }   // §2: the STAGING FRAME — bright-ink = the current part's bench
            }
        }
        .overlay(alignment: .topLeading) { buildGridCornerEye(cell: cell, popup: 0) }   // the eye in the grid's top-left corner cell
    }

    // The outline colour for a staging cell: WHITE for the ONE selected (playing) cell of its column; otherwise none.
    private func buildStagingStroke(c: Int, r: Int, stocked: Bool) -> Color {
        if buildStagingSel[c] == r { return .white }   // the selected (playing) rung — WHITE even when unpopulated (Paul 2026-08-15)
        return .clear
    }

    // A staging cell tap. In PLAY mode the verbs are DISABLED — a tap on a STOCKED cell just makes it the active
    // (playing) cell for its column. In EDIT mode: PLACE stocks the selected colour, DELETE clears, etc.
    private func buildStagingTap(_ c: Int, _ r: Int) {
        if let id = buildStagingCells[c][r] {                     // touching a STOCKED cell offers its colour+settings as a PULSING palette candidate
            buildPulseColourID = id
            buildPulseChain = (r < buildRowChain.count && !buildRowChain[r].isEmpty) ? buildRowChain[r] : []
        }
        // A cell tap always SELECTS / DESELECTS one rung per column (populated or NOT — Paul 2026-08-15). EDIT mode is
        // retired; the row BUTTONS carry the place/mutate actions now (buildRowMode). (Paul 2026-08-16)
        buildStagingSel[c] = (buildStagingSel[c] == r) ? -1 : r   // tap the selected rung → deselect (column silent); else select it
        buildStagingSyncIfPlaying()
    }

    private func buildRowColour(_ r: Int) -> String? { r >= 0 && r < 8 ? (0..<8).compactMap { buildStagingCells[$0][r] }.first : nil }
    private func buildColumnHasSelection(_ c: Int) -> Bool { let s = buildStagingSel[c]; return s >= 0 && s < 8 }   // an empty rung counts as a selection (Paul 2026-08-15)
    private func buildSetRow(_ r: Int, to cid: String?) {         // fill (or clear) a whole row with one colour
        for c in 0..<8 { buildStagingCells[c][r] = cid; buildPlacedOrig.removeValue(forKey: c * 8 + r) }
        if r < buildRowChain.count { buildRowChain[r] = [] }      // the row carries the colour's OWN machine (no per-row variation override)
        if r < buildRowShade.count { buildRowShade[r] = 0 }
        buildDeletedRows[r] = nil
    }

    // Press a staging ROW button → SET that row to the SELECTED colour + its machine. ONE COLOUR PER ROW (Paul 2026-08-15):
    //  • overwrites the row, remembering what it displaced (rowUnder) so it can come back;
    //  • if the colour already occupies ANOTHER row, that row REVERTS to what it held before this colour arrived — it does
    //    NOT blank (e.g. row A red → stamp green on A → A green; stamp green on B → A reverts to red).
    //  • a column with NO current selection then selects the placed cell (so a fresh stamp plays; it never steals an
    //    existing pick — the existing population survives).
    private func buildStampRow(_ row: Int) {
        guard let cid = ddSelectedColourID, row >= 0, row < 8 else { return }
        if buildRowColour(row) == cid { return }                 // already this colour → nothing to do
        for r in 0..<8 where r != row && buildRowColour(r) == cid {   // the colour's PRIOR row → REVERT it to what it displaced
            let under = r < buildRowUnder.count ? buildRowUnder[r] : nil
            buildSetRow(r, to: under)
            if r < buildRowUnder.count { buildRowUnder[r] = nil }
        }
        if row < buildRowUnder.count { buildRowUnder[row] = buildRowColour(row) }   // remember what THIS row displaces
        buildSetRow(row, to: cid)
        for c in 0..<8 { buildStagingSel[c] = row }              // the WHOLE new row becomes selected immediately (Paul 2026-08-16)
        buildStagingSyncIfPlaying()
    }

    // SELECT mode: make this row the selected rung in EVERY column — the whole-row equivalent of tapping a cell.
    private func buildSelectRow(_ row: Int) {
        guard row >= 0, row < 8 else { return }
        for c in 0..<8 { buildStagingSel[c] = row }
        buildStagingSyncIfPlaying()
    }

    // MUTATE mode (Paul 2026-08-16): create (empty) / replace (populated) row R with a VALUE-tweaked variant of the
    // SELECTED palette colour — same processor structure, up to 3 nudged values (biased to one), GUARANTEED to sound
    // different from the source and NOT silent (Dice signature), tinted a lighter/darker tone of the source by complexity.
    private func buildMutateRow(_ row: Int) {
        guard let cid = ddSelectedColourID, row >= 0, row < 8 else { return }
        let base = buildColourChain(cid)
        let srcC = buildComplexity(base)                        // note-frequency + concurrency (for the lighter/darker tint)
        let srcFP = Dice.fingerprint(base)
        var avoid = [srcFP]                                     // PREFER: don't reproduce the SOURCE (velocity+gate aware) …
        for r in 0..<8 where r != row {                         // … or ANY other row already on the grid (else repeats)
            if let rid = buildRowColour(r) { avoid.append(Dice.fingerprint(buildColourChain(rid))) }
        }
        var rng = SystemRandomNumberGenerator()
        // Relaxed fallback: only unlike the SOURCE + what's on THIS row now. Once the grid fills with variants the
        // strict search exhausts the source's small param space and returns nil — MUTATE would silently stop. Falling
        // back keeps it responsive (an occasional chain-repeat under a distinct colour beats a dead button). (2026-08-17)
        var relaxed = [srcFP]
        if let rid = buildRowColour(row) { relaxed.append(Dice.fingerprint(buildColourChain(rid))) }
        guard let mutated = BuildSceneLogic.mutateChain(base, avoid: avoid, &rng)
                ?? BuildSceneLogic.mutateChain(base, avoid: relaxed, &rng) else { return }   // no audible variant at all
        let newC = buildComplexity(mutated)
        let hue = buildSimilarHue(of: cid, lighter: newC < srcC, srcC: srcC, newC: newC)
        let newID = buildNewColour(hex: hue, machine: mutated)   // a NEW colour (never already placed) → no relocation
        if row < buildRowUnder.count { buildRowUnder[row] = buildRowColour(row) }   // remember what this row displaces
        buildSetRow(row, to: newID)
        for c in 0..<8 { buildStagingSel[c] = row }              // select the whole new row (like PLACE)
        buildPulseColourID = newID; buildPulseChain = mutated    // a new colour PULSES in the palette as a "create me" candidate (Paul 2026-08-16)
        buildStagingSyncIfPlaying()
    }


    // THE VERB BOX (a different box below staging): the workbench verbs, then the workshop's outcomes.
    @ViewBuilder private func buildStagingVerbBox(gridW: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) { buildRowModeBtn(.select); buildRowModeBtn(.mutate); buildFlattenButton() }   // SELECT ⟷ MUTATE radio (PLACE moved to the left column); FLATTEN placeholder (Paul 2026-08-17)
            HStack(spacing: 6) { buildBlankSlot(); buildBlankSlot(); buildBlankSlot() }   // reserved — left blank for now (Paul 2026-08-16)
        }
        .padding(8)
        .frame(width: gridW)                                       // match the verb box to the grid above it
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))   // the outline that matches the left/right button boxes
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
                let held = (laneMask & (1 << UInt8(c))) != 0       // reflect the REAL lap set (BUILD keeps it 0 — the keys aren't wired to set it yet)
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(held ? 0.22 : 0.11))   // §0 MUTED: neutral keys, held reads as a slight brightening
                    .frame(width: cell, height: cell)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildEdge, lineWidth: 1))
                    .overlay(Image(systemName: "repeat")           // ALWAYS the loop glyph (never a chevron); held shows via the fill
                        .font(.system(size: 12, weight: .heavy)).foregroundColor(.white.opacity(held ? 0.85 : 0.55)))
            }
        }
    }

    // ROW BUTTONS — a cell-sized selector per grid row on the LEFT edge; shared by both grids. `bands` is the row
    // grouping (staging = [8]; play = [3,2,1,1,1]) so the buttons carry the SAME part dividers as the grid → they align
    // row-for-row. A top spacer clears the loop-key row.
    @ViewBuilder private func buildRowButtons(cell: CGFloat, hue: Color, bands: [Int], onRow: ((Int) -> Void)? = nil) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row (now full cell height)
            VStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { idx, rows in
                    if idx > 0 { partDivider(line: true) }         // the DIVIDING LINE lives here, between the row buttons
                    let base = bands.prefix(idx).reduce(0, +)      // absolute grid-row offset for this band
                    VStack(spacing: BuildGeom.cellGap) {
                        ForEach(0..<rows, id: \.self) { r in
                            let gridRow = base + r
                            let rowCid = buildRowColour(gridRow)
                            let isSel = rowCid != nil && rowCid == ddSelectedColourID   // this row holds the SELECTED colour
                            RoundedRectangle(cornerRadius: 7).fill(buildRowButtonFill)   // muted rail; inverts to light when a DARK colour's icon needs contrast
                                .frame(width: cell, height: cell)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSel ? (rowCid.flatMap { colourColor($0) } ?? buildEdge) : buildEdge, lineWidth: isSel ? 2 : 1))
                                .overlay(Text("\(gridRow + 1)").font(.system(size: 13, weight: .heavy, design: .monospaced))
                                    .foregroundColor(isSel ? (rowCid.flatMap { colourColor($0) } ?? .white) : .white.opacity(0.7)))   // ROW NUMBER 1–8 — SHOWS THE SELECTED COLOUR when this row holds it (replaces the per-cell target)
                                .contentShape(Rectangle())
                                .onTapGesture { onRow?(gridRow) }  // press → run the current row mode on that grid row
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
                let base = bands.prefix(idx).reduce(0, +)          // this band's first grid row
                let mine = (0..<rows).contains { base + $0 < 8 && buildPerformPart[base + $0] == buildCurrentPart }   // §2: does the CURRENT part live in this band?
                let set = (0..<rows).contains { base + $0 < 8 && buildPerformPart[base + $0] >= 0 }   // VALVE: this band HOLDS a part (SET)
                RoundedRectangle(cornerRadius: 7).fill(buildHues[idx % buildHues.count].opacity(set ? 0.7 : 0.4))   // §4 band hue; SET reads more solid
                    .frame(width: cell, height: h)
                    .overlay(Text(set ? "\(idx + 1)" : "+").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(set ? (mine ? 0.95 : 0.6) : 0.4)))   // SET shows the number; EMPTY shows a + (deploy-here)
                    .overlay(alignment: .leading) { if mine { Rectangle().fill(buildPartInk).frame(width: 3) } }   // §2: the deployed band's bright-ink RAIL BRACKET (others sit dim)
                    .contentShape(Rectangle())
                    .onTapGesture { buildExitPlaceMode(); buildBandValve(base: base, rows: rows) }   // play-grid button → not a part-grid row, so it leaves PLACE mode; THE VALVE: empty → flatten+stash+clear · set → restore
            }
        }
    }

    // RIGHT-side per-row buttons on the PERFORM grid — one per row for parts 1 & 2 ONLY (rows 1–3 = "1", rows 4–5 = "2");
    // rows 6–8 (parts 3–5) get no button here since they're already on the left. Identical appearance to the part buttons.
    @ViewBuilder private func buildRightPartButtons(cell: CGFloat, hue: Color) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row (now full cell height)
            ForEach(0..<5, id: \.self) { r in                            // rows 1–5 only
                let bandIndex = r < 3 ? 0 : 1                             // rows 0–2 = band 1 · rows 3–4 = band 2
                let base = bandIndex == 0 ? 0 : 3
                let whole = buildRowInWholeBand(r)                        // this band is a WHOLE-band part → the rung valve is inert (restore via LEFT)
                let set = buildPerformPart[r] >= 0 && !whole             // this rung holds its own sub-part
                let mine = buildPerformPart[r] == buildCurrentPart
                let letter = ["a", "b", "c"][min(r - base, 2)]           // the rung letter (a/b/c)
                RoundedRectangle(cornerRadius: 7).fill(buildHues[bandIndex % buildHues.count].opacity(whole ? 0.15 : (set ? 0.7 : 0.4)))
                    .frame(width: cell, height: cell)
                    .overlay(Text(whole ? "" : (set ? letter : "+")).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(whole ? 0.2 : (set ? (mine ? 0.95 : 0.6) : 0.4))))   // SET → the rung letter · EMPTY → + · WHOLE band → inert
                    .overlay(alignment: .trailing) { if set && mine { Rectangle().fill(buildPartInk).frame(width: 3) } }   // §2: current part's rung gets the bright-ink bracket
                    .contentShape(Rectangle())
                    .onTapGesture { buildExitPlaceMode(); buildRowValve(row: r) }   // play-grid button → leaves PLACE mode; then the per-rung valve
            }
        }
    }

    // ── RIGHT COLUMN: the PLAY grid — five fixed bands + glyph rail; the target decides the verb ───────────────────
    @ViewBuilder private func buildPlayColumn(cell: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("START/STOP THE PLAY GRID", active: buildPerformPlaying, fill: .grid, enabled: buildPerformPopulated, action: { buildTogglePerformVoice() }))   // disabled until the play grid has REAL cells (preview doesn't count)
            // PLAY/EDIT radio dropped (Paul 2026-08-17); the eye moved to the grid's corner
            // LEFT: merged PART BUTTONS 1–4 (part 5/row 8 removed). RIGHT: per-row buttons for parts 1 & 2 only (1,1,1,2,2)
            // — parts 3–5 aren't repeated on the right since they're already on the left. Assign STAGING → PERFORM (wires later).
            AnyView(HStack(alignment: .top, spacing: BuildGeom.cellGap) {   // same spacing as staging → attached the same way
                // FLATTEN on → the valve/part buttons; off (default) → plain row-master chevrons
                buildFlattenMode ? AnyView(buildPartButtons(cell: cell, hue: buildCyan, bands: [3, 2, 1, 1])) : AnyView(buildPerformRowButtons(cell: cell))
                VStack(spacing: BuildGeom.cellGap) {
                    buildLoopKeys(cell: cell)                     // the column-selector row
                    AnyView(buildPlayBands(cell: cell))          // AnyView — keeps the deep bands type out of this body
                }
                // FLATTEN on → the right per-rung buttons; off → the SAME buttons hidden (reserves width, no touch) so the grid stays the same size
                buildFlattenMode ? AnyView(buildRightPartButtons(cell: cell, hue: buildCyan)) : AnyView(buildRightPartButtons(cell: cell, hue: buildCyan).hidden())
            }.overlay(alignment: .topLeading) { buildGridCornerEye(cell: cell, popup: 1) })   // the eye in the play grid's top-left corner cell
            // emitters + per-emitter MUTE/SOLO removed for now (non-functional) — they get rebuilt later
            AnyView(buildFooterBox(labels: ["", "", "", "", "", ""]))   // the play grid's own button box, directly below it
            Spacer(minLength: 0)
            AnyView(buildEmittersBox())                          // bottom of the right column — the four main emitter controls (fader + M/S + RACK)
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
                    Text(e).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))   // §0 MUTED: neutral identifier (was standing cyan)
                    RoundedRectangle(cornerRadius: 4).fill(buildCell)   // the velocity fader STRETCHES down to the M/S row
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.22)).frame(height: 26), alignment: .bottom)   // §0 MUTED: the level bar reads as a neutral value, not a cyan slab
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

    // THE DIMMED PREVIEW (Paul 2026-08-14): while the CURRENT part is UNASSIGNED, show its staging SELECTION on every
    // UNASSIGNED play-grid band. The shape follows the count of DISTINCT selected rows K:
    //   • a SINGLE-rung band always shows the FLATTEN (each column's selected cell — the same algorithm as deployment);
    //   • a multi-rung band with K == 1 shows the flatten on its TOP rung;
    //   • a multi-rung band whose rung count == K shows the K selected rows on its K rungs;
    //   • otherwise (K > 1 and ≠ the band's rungs) the selection doesn't fit that band → no preview.
    // Returns [col][row] colourIDs (nil = nothing to preview there).
    private func buildPreviewCells() -> [[String?]] {
        var out = Array(repeating: Array(repeating: String?.none, count: 8), count: 8)
        // Only while the PARTS (staging) grid is playing — NOT during a MIDI-chain audition. (Paul 2026-08-14)
        guard buildStagingPlaying, buildCurrentPart >= 0, buildCurrentPart < buildParts.count, !buildParts[buildCurrentPart].deployed else { return out }
        let selRows = Set((0..<8).compactMap { buildStagingSel[$0] >= 0 ? buildStagingSel[$0] : nil }).sorted()
        let K = selRows.count
        guard K > 0 else { return out }
        func flatten(intoRow R: Int) {                             // deployment's flatten: each column's selected cell, wherever its row
            for c in 0..<8 {
                let sr = buildStagingSel[c]
                if sr >= 0, sr < 8, let cid = buildStagingCells[c][sr] { out[c][R] = cid }
            }
        }
        let bands = [3, 2, 1, 1, 1]
        for (bi, N) in bands.enumerated() {
            let base = bands.prefix(bi).reduce(0, +)
            if (0..<N).contains(where: { base + $0 < 8 && buildPerformPart[base + $0] >= 0 }) { continue }   // band already holds a deployed part
            if N == 1 || K == 1 {
                flatten(intoRow: base)                             // single lane, or one selected row → flatten onto the (top) rung
            } else if K == N {
                for (i, sr) in selRows.enumerated() {              // K selected rows → the band's K rungs, top-down
                    for c in 0..<8 where buildStagingSel[c] == sr {
                        if let cid = buildStagingCells[c][sr] { out[c][base + i] = cid }
                    }
                }
            }
        }
        return out
    }

    // the PLAY grid rows — THE PIECE: real deployed cells. §4 BAND WASHES (design ferry): each band carries its own hue
    // family as a low-alpha WASH BEHIND its cells (empty cells go clear so the wash reads); the cells keep their TRUE
    // colour on top — rails differentiate, machines stay recognisable across grids. Alpha is a starting point.
    @ViewBuilder private func buildPlayBands(cell: CGFloat) -> some View {
        let bands = [3, 2, 1, 1, 1]                                // the play grid's band form (8 rows)
        let preview = buildPreviewCells()                          // the dimmed preview of the current unassigned part
        VStack(spacing: BuildGeom.cellGap) {
            ForEach(Array(bands.enumerated()), id: \.offset) { bi, rows in
                let base = bands.prefix(bi).reduce(0, +)
                VStack(spacing: BuildGeom.cellGap) {
                    ForEach(0..<rows, id: \.self) { ri in
                        let r = base + ri
                        HStack(spacing: BuildGeom.cellGap) {
                            ForEach(0..<8, id: \.self) { c in
                                let id = buildPerformCells[c][r]
                                let ghost = id == nil ? preview[c][r] : nil   // preview only where no cell is deployed
                                let muted = buildPerformMute.contains(c * 8 + r)
                                let multiRung = buildPerformPart[r] >= 0 && buildPerformPartRows(buildPerformPart[r]) > 1
                                let mutable = id != nil && buildPerformPart[r] >= 0 && !multiRung   // SINGLE-RUNG part → per-cell mute
                                let activeRung = buildPerformActiveRung(c, r)                        // MULTI-rung: the selected rung of this column
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(id.flatMap { colourColor($0) } ?? Color.black.opacity(0.35))   // TRUE colour · else the empty recess (preview shows as an outline, not a fill)
                                    .frame(width: cell, height: cell)
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.09), lineWidth: 1))   // outline every cell → the grid READS even when empty
                                    .overlay { if let g = ghost, let gc = colourColor(g) {   // THE PREVIEW = a THICK, DIMMED OUTLINE in the colour (not a fill)
                                        RoundedRectangle(cornerRadius: 7).strokeBorder(gc.opacity(0.45), lineWidth: 3) } }
                                    .overlay { if id != nil && multiRung && activeRung { RoundedRectangle(cornerRadius: 7).stroke(Color.white, lineWidth: 2.5) } }   // WHITE = the selected rung (like the part grid)
                                    .overlay { ZStack {                                            // TARGET + NOTE SWEEP (folded into one overlay to keep the cell type-checkable)
                                        if id != nil && id == ddSelectedColourID { buildTargetMark(cell * 0.55) }   // THE TARGET rides every play-grid cell matching the selected machine
                                        buildNoteSweep(idx: c * 8 + r, active: buildPerformPlaying, id: id)   // THE NOTE SWEEP (v1) — only when the PLAY grid plays
                                    } }
                                    .opacity(muted || (id != nil && multiRung && !activeRung) ? 0.3 : 1)   // MUTED cell OR a non-selected rung dims
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if mutable { buildTogglePerformMute(c, r) }               // single-rung → mute
                                        else if id != nil && multiRung { buildTogglePerformRung(c, r) }   // multi-rung → pick the active rung
                                    }
                            }
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(buildHues[bi % buildHues.count].opacity(0.16)))   // §4 the band's hue WASH, behind the cells
            }
        }
        .overlay(alignment: .topLeading) { buildPlayhead(cell: cell, active: buildPerformPlaying) }   // sweeps only when the PLAY grid plays
    }

    // THE PLAYHEAD — a 2pt vertical line sweeping L→R across the 8 grid columns, phase-locked to the transport beat and
    // looping with the engine's 8-column cycle. Attached to the CELLS block only (topLeading), so it never crosses the
    // loop-key row above or the row buttons to the side. Extrapolates the polled beat between frames (like the palette
    // playhead) and warps by SWING so it tracks the real (swung) column windows. (user 2026-08-12)
    @ViewBuilder private func buildPlayhead(cell: CGFloat, active: Bool) -> some View {
        if d.playing && active {                                  // only when THIS grid is the playing voice (Paul 2026-08-14)
            let width = cell * 8 + BuildGeom.cellGap * 7               // the cells span: 8 cells + the 7 gaps between them
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let live = ddBeatAnchor + tl.date.timeIntervalSince(ddBeatAnchorAt) * d.tempo / 60.0   // extrapolate the polled beat
                let musical = musicalOf(live, stepBeats: stepBeats, a: max(1.0, Double(swing) / 50.0)) // column progress in MUSICAL (swung) time
                let colF = stepBeats > 0 ? musical / stepBeats : 0    // continuous column index since transport start
                let wrapped = colF.truncatingRemainder(dividingBy: Double(Snap.cols))
                let p = wrapped < 0 ? wrapped + Double(Snap.cols) : wrapped   // 0…8 across the grid, looping with the engine
                let x = min(width, CGFloat(p) * (cell + BuildGeom.cellGap))
                Rectangle().fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: width == 0 ? 0 : cell * 8 + BuildGeom.cellGap * 7)
                    .offset(x: x)
                    .allowsHitTesting(false)
            }
        }
    }

    // THE NOTE SWEEP (v1 — spec `AcceptanceCriteria-note-sweep.md`, ratified 2026-08-16). A line sweeps across the
    // cell for as long as the note SOUNDS (note-off mid-travel = the line freezes where it got to → the note's length
    // reads visually). VELOCITY is the stroke (weight + opacity). AXIS = ROTATION: each new strike moment takes the
    // next edge (L→R · T→B · R→L · B→T) via cellStrikeSeq. Reuses the existing per-cell feeds (no new plumbing).
    // Deferred: velocity-fed density governor · CONTOUR axis (needs a per-note pitch feed) · face-dimming. (2026-08-17)
    // A hex lightened toward white by `t` (0…1) — the hue's BRIGHT tone.
    private func buildLighten(_ hex: UInt32, _ t: Double) -> UInt32 {
        func ch(_ s: Int) -> UInt32 { let c = Double((hex >> s) & 0xFF); return UInt32(max(0, min(255, c + (255 - c) * t))) }
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }
    @ViewBuilder private func buildNoteSweep(idx: Int, active: Bool, id: String?) -> some View {
      if active, let cid = id {                                    // ONLY on a POPULATED cell of the grid that is the PLAYING voice
        let hue = Color(hex: buildLighten(buildBaseHex(cid), 0.72))  // the hue's BRIGHT tone → visible over the same-colour face
        let hitAt = idx < cellHitAt.count ? cellHitAt[idx] : .distantPast
        let vel = idx < cellHitVel.count ? cellHitVel[idx] : 0
        let sounding = idx < cellSounding.count ? cellSounding[idx] : false
        let releasedAt = idx < cellReleasedAt.count ? cellReleasedAt[idx] : .distantPast
        let seq = idx < cellStrikeSeq.count ? cellStrikeSeq[idx] : 0
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
            Canvas { ctx, size in
                let hasRelease = releasedAt > hitAt
                let strikeAge = tl.date.timeIntervalSince(hitAt)
                let releaseAge = tl.date.timeIntervalSince(releasedAt)
                // LIFE: full while the note sounds; fades ~0.45s from release; a pluck the gate missed flashes ~0.5s.
                let life = sounding ? 1.0 : (hasRelease ? max(0, 1 - releaseAge / 0.45) : max(0, 1 - strikeAge / 0.5))
                guard life > 0.02, strikeAge >= 0 else { return }
                // TRAVEL: the head advances while sounding, then FREEZES at the reach it had on release.
                let elapsed = sounding ? strikeAge : max(0, releasedAt.timeIntervalSince(hitAt))
                let progress = min(1.0, elapsed / 0.8)                 // crosses the cell in ~0.8s of sustained sound
                let w = size.width, h = size.height
                let (p0, p1): (CGPoint, CGPoint)
                switch ((seq % 4) + 4) % 4 {                           // ROTATION axis
                case 0:  (p0, p1) = (CGPoint(x: 0, y: h / 2), CGPoint(x: w, y: h / 2))     // L→R
                case 1:  (p0, p1) = (CGPoint(x: w / 2, y: 0), CGPoint(x: w / 2, y: h))     // T→B
                case 2:  (p0, p1) = (CGPoint(x: w, y: h / 2), CGPoint(x: 0, y: h / 2))     // R→L
                default: (p0, p1) = (CGPoint(x: w / 2, y: h), CGPoint(x: w / 2, y: 0))     // B→T
                }
                let head = CGPoint(x: p0.x + (p1.x - p0.x) * progress, y: p0.y + (p1.y - p0.y) * progress)
                var path = Path(); path.move(to: p0); path.addLine(to: head)
                let weight = 1.5 + 3.0 * vel                           // VELOCITY IS THE STROKE — weight …
                let alpha = min(1.0, (0.35 + 0.65 * vel) * life)       // … and opacity
                ctx.stroke(path, with: .color(hue.opacity(alpha)), style: StrokeStyle(lineWidth: weight, lineCap: .round))
            }
            .padding(3)
        }
        .allowsHitTesting(false)
      }
    }

    // ── MACHINERY STRIP (bottom, full width): the chain — ID · IN box · slots + ghost · OUT box ────────────────────
    @ViewBuilder private func buildMachinery() -> some View {
        let chain = selectedColourChain()                         // the SELECTED colour's real processors (empty for a new colour)
        HStack(alignment: .center, spacing: 10) {                  // THE CHAIN — RANDOMIZE · EXAMPLE cell · IN box · slots (all in a row, none overlapping)
            buildFooterBtn("🎲 RANDOMIZE", pink: true) { buildRandomizeSimple() }   // LEFT: the SIMPLER roll — now IN the row (was an overlay covering the example cell)
            RoundedRectangle(cornerRadius: 9).fill(buildSelHue).frame(width: 40, height: 40)   // the EXAMPLE cell = the selected machine, to the LEFT of the processor boxes
                .overlay { if ddSelectedColourID != nil { buildTargetMark(24) } }              // …wearing the same TARGET as the cast swatch
            buildBox("R1: MIDI IN", "OMNI")
            Text("┈┈▶").foregroundColor(buildDim).font(.system(size: 10, design: .monospaced))
            ForEach(0..<8, id: \.self) { i in                     // UP TO 8 processor slots (the chain's capacity)
                if i < chain.count && !buildIsEmptySlot(chain[i]) {
                    buildSlot(chain[i].type.rawValue, colour: buildSelHue, bypassed: chain[i].bypassed)   // a real processor — the selected colour
                        .onTapGesture { buildEditSlot = i }       // touch → open the processor pop-up editor
                } else {
                    buildSlot("+", dashed: true)                  // EVERY empty box is a "+" — tap to add a processor AT THIS position
                        .onTapGesture { buildAddSlot = i }
                }
                if i < 7 { Text("┈").foregroundColor(buildDim) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 9)          // symmetric padding → the boxes centre in the footer
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildSelHue.opacity(0.45), lineWidth: 1.5))   // §1 THE THREAD: the chain frame wears the machine's hue (reads with the left column)
        .overlay(alignment: .bottomTrailing) {                   // EYE (bottom-right) → the signal-flow diagram pop-up
            Image(systemName: "eye").font(.system(size: 15, weight: .semibold)).foregroundColor(buildDim)   // §0 muted chrome: a whisper, not an accent
                .padding(10).contentShape(Rectangle()).onTapGesture { buildFlowOpen = true }
        }
    }

    // A 3×2 button box that sits beneath a column. All three (processor · staging · play) are built by this one
    // function → identical styling + button size; only the column width differs. `labels` fills row-major; an empty
    // string renders a blank placeholder button. RANDOMIZE is wired live; everything else is a stub for now.
    @ViewBuilder private func buildFooterBox(labels: [String]) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            ForEach(0..<2, id: \.self) { r in
                HStack(spacing: BuildGeom.cellGap) {
                    ForEach(0..<3, id: \.self) { c in
                        let idx = r * 3 + c
                        let label = idx < labels.count ? labels[idx] : ""
                        buildFooterBoxBtn(label)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }

    @ViewBuilder private func buildFooterBoxBtn(_ label: String) -> some View {
        let empty = label.isEmpty
        let live = label.contains("RANDOMIZE")   // RANDOMIZE runs the simple roll — but is styled plain, like MUTATE/LIBRARY (Paul 2026-08-18)
        Text(label)
            .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(.white)
            .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)   // FIXED height (min==max) — a flexible box competes with the column's Spacer and stretches to the screen bottom
            .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(buildEdge, lineWidth: 1).opacity(empty ? 0.5 : 1))
            .contentShape(Rectangle())
            .onTapGesture { buildExitPlaceMode(); if live { buildRandomizeSimple() } }   // any control button leaves PLACE mode
    }

    // PLACE is armed by the PLACE button / the verb-box radio; clicking any button that ISN'T a grid row selector
    // turns it back off (→ SELECT). Wired into the control buttons (transports + footer buttons).
    private func buildExitPlaceMode() { if buildPlaceArmed { buildPlaceArmed = false } }

    // The LEFT column's control box. Row 1: RANDOMIZE · MUTATE · AUTOFILL (all plain-styled). Row 2: the cell
    // LIBRARY, spanning the full width. (Paul 2026-08-18: AUTOFILL moved up from row 2; LIBRARY now full-width.)
    @ViewBuilder private func buildLeftControlBox() -> some View {
        let gap = BuildGeom.cellGap
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                buildFooterBoxBtn("RANDOMIZE")
                buildFooterBoxBtn("MUTATE")
                buildFillButton()                                           // AUTOFILL — moved into the third cell (was PLACE's placeholder)
            }
            buildLibraryButton()                                            // now spans the full row width
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }

    // The cell LIBRARY opener, sat across the two left cells of the control box. On BUILD the browser saves/stamps
    // the SELECTED COLOUR's chain (not an EDIT grid cell).
    @ViewBuilder private func buildLibraryButton() -> some View {
        Text("LIBRARY").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(buildEdge, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { buildExitPlaceMode(); buildOpenLibrary() }
    }
    // Open the library IN BUILD CONTEXT: its Save/Stamp act on the selected colour's chain. Remember the colour's
    // CURRENT chain so a preview can be reverted if the user leaves without APPLY.
    func buildOpenLibrary() {
        cellLibraryFromBuild = true
        buildLibraryOriginalChain = buildSelID.map { buildColourMachine($0) }
        buildLibraryPreviewed = false
        cellLibraryList = au?.libraryCellSummaries() ?? []
        showCellLibrary = true
    }
    // Save the SELECTED colour's chain as a named library cell.
    func buildSaveColourToLibrary(_ name: String) {
        guard let cid = buildSelID else { return }
        au?.saveChainToLibrary(colourID: cid, chain: buildColourMachine(cid), name: name)
        cellLibraryList = au?.libraryCellSummaries() ?? []
    }
    // PREVIEW a library cell: temporarily overwrite the selected colour's chain so it auditions live. Reverted on
    // close unless the user commits with APPLY.
    func buildPreviewLibrary(_ cell: Cell?) {
        guard let cell, let cid = buildSelID else { return }
        buildWriteColourMachine(cid, cell.processors ?? [])
        buildLibraryPreviewed = true
    }
    // APPLY — commit a library cell's chain ONTO the selected colour (keeps the colour + its I/O); no revert.
    func buildStampLibrary(_ cell: Cell?) {
        guard let cell, let cid = buildSelID else { return }
        buildWriteColourMachine(cid, cell.processors ?? [])
        buildLibraryPreviewed = false; buildLibraryOriginalChain = nil
        showCellLibrary = false; cellLibraryFromBuild = false
    }
    // CLOSE without APPLY → restore the colour's original chain if a preview changed it.
    func buildCloseLibrary() {
        if buildLibraryPreviewed, let cid = buildSelID { buildWriteColourMachine(cid, buildLibraryOriginalChain ?? []) }
        buildLibraryPreviewed = false; buildLibraryOriginalChain = nil
        showCellLibrary = false; cellLibraryFromBuild = false
    }

    // FILL — styled identically to PLACE (colour chip + ">>>"), but it's an ACTION not a mode: it runs the old
    // STAGE THE GRID (fills the part grid to 8 rows). Disabled until the staging grid has content.
    @ViewBuilder private func buildFillButton() -> some View {
        let enabled = buildStagingPopulated
        let selDark = buildIsDark(buildBaseHex(buildSelID ?? ""))
        let chipGround: Color = selDark ? Color.white.opacity(0.92) : Color.black.opacity(0.78)
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3).fill(chipGround).frame(width: 15, height: 15)
                .overlay(RoundedRectangle(cornerRadius: 2).fill(buildSelHue).frame(width: 9, height: 9))   // the same colour square as PLACE
            Text("AUTOFILL").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.3)
                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.4)
            Text(">>>").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(buildSelHue)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(buildEdge, lineWidth: 1))
        .opacity(enabled ? 1 : 0.35)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { buildExitPlaceMode(); buildStageTheGrid() } }
        .allowsHitTesting(enabled)
    }

    // FLATTEN — the third verb-box button (where MUTATE used to sit): a colour chip (the same small box as PLACE/
    // FILL) + "FLATTEN >>>". A TOGGLE for the PLAY grid's mode — ON shows the valve/part buttons, OFF (default)
    // shows plain row-master chevrons. Sized to the verb-box buttons (36pt). (Paul 2026-08-17)
    @ViewBuilder private func buildFlattenButton() -> some View {
        let armed = buildFlattenMode
        let selDark = buildIsDark(buildBaseHex(buildSelID ?? ""))
        let chipGround: Color = selDark ? Color.white.opacity(0.92) : Color.black.opacity(0.78)
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3).fill(chipGround).frame(width: 15, height: 15)
                .overlay(RoundedRectangle(cornerRadius: 2).fill(buildSelHue).frame(width: 9, height: 9))   // same size as the PLACE/FILL chip
            Text("FLATTEN").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.3)
                .foregroundColor(armed ? .black : .white).lineLimit(1).minimumScaleFactor(0.4)
            Text(">>>").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(armed ? .black : buildSelHue)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity).frame(minHeight: 36, maxHeight: 36)          // match the SELECT/MUTATE buttons
        .background(RoundedRectangle(cornerRadius: 9).fill(armed ? buildCyan : buildCell))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(armed ? Color.clear : buildEdge, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { buildFlattenMode.toggle() }
    }
    // NORMAL-mode play grid (FLATTEN off): a plain right-chevron button per row — a ROW MASTER. One per grid row,
    // aligned past the loop-key row like the part buttons.
    @ViewBuilder private func buildPerformRowButtons(cell: CGFloat) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row
            ForEach(0..<8, id: \.self) { r in
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.11))
                    .frame(width: cell, height: cell)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildEdge, lineWidth: 1))
                    .overlay(Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.7)))
                    .contentShape(Rectangle())
                    .onTapGesture { buildPerformRowToggle(r) }
            }
        }
    }
    // The row master: if any populated cell in the row is muted, UNMUTE the whole row; if every populated cell is
    // already unmuted, MUTE the whole row — exactly as if each cell had been pressed. Empty cells are left alone.
    private func buildPerformRowToggle(_ r: Int) {
        let cols = (0..<8).filter { buildPerformCells[$0][r] != nil }
        guard !cols.isEmpty else { return }
        let allUnmuted = cols.allSatisfy { !buildPerformMute.contains($0 * 8 + r) }
        for c in cols { let k = c * 8 + r; if allUnmuted { buildPerformMute.insert(k) } else { buildPerformMute.remove(k) } }
        buildPublishScene()
    }

    // THE RECEIVERS BOX (left column, bottom): four identical controls (A–D), one per input door. Each = a live
    // incoming-velocity meter (left) + a control stack (right): Mute/Solo on one line, then LATCH, then an ENABLE
    // button showing the door's MIDI channel — LATCH and ENABLE are the prominent pair. (Paul 2026-08-17)
    @ViewBuilder private func buildReceiversBox() -> some View {
        HStack(spacing: 6) {                                       // the four doors A–D sit side by side
            ForEach(0..<4, id: \.self) { i in buildReceiverControl(i) }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }
    @ViewBuilder private func buildReceiverControl(_ i: Int) -> some View {
        let rec = i < receivers.count ? receivers[i] : Receiver()
        let letter = ["A", "B", "C", "D"][i]
        let soloed = soloReceiverMask & (1 << UInt8(i)) != 0
        let latched = latchMask & (1 << UInt8(i)) != 0
        let h: CGFloat = 14 + 51 + 51 + 6                                       // mute/solo(14) + LATCH(51) + ENABLE(51) + 2 gaps
        HStack(spacing: 6) {
            buildReceiverMeter(i, letter: letter).frame(width: 22, height: h)   // velocity indicator — full control height
            VStack(spacing: 3) {
                HStack(spacing: 3) {                                            // MUTE · SOLO on one line
                    buildRecMini("M", on: rec.muted, colour: buildPink) { toggleReceiverMute(i) }
                    buildRecMini("S", on: soloed, colour: buildCyan) { toggleReceiverSolo(i) }
                }.frame(height: 14)
                buildRecProminent("LATCH", on: latched, colour: Color(red: 1.0, green: 0.72, blue: 0.2)) { toggleReceiverLatch(i) }.frame(height: 51)   // 3× taller (prominent)
                buildRecProminent(recChanLabel(rec), on: rec.inputEnabledResolved, colour: Color(red: 0.36, green: 0.92, blue: 0.52)) { toggleReceiverEnabled(i) }.frame(height: 51)   // ENABLE (channel), 3× taller
            }.frame(height: h)
        }
    }
    private func recChanLabel(_ rec: Receiver) -> String { rec.channel == 0 ? "OMNI" : "CH \(rec.channel)" }
    // The incoming-velocity meter: the door letter over a bottom-filling bar that peaks on input then decays.
    @ViewBuilder private func buildReceiverMeter(_ i: Int, letter: String) -> some View {
        VStack(spacing: 2) {
            Text(letter).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(buildDim)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let held = i < recvHeld.count ? (recvHeld[i].max() ?? 0) : 0     // SUSTAINED while notes are held → the bar shows note LENGTH
                let age = tl.date.timeIntervalSince(i < receiverPeakAt.count ? receiverPeakAt[i] : .distantPast)
                let flash = (i < receiverPeak.count ? receiverPeak[i] : 0) * max(0, 1 - age / 0.3)   // a brief attack flash on note-on
                let level = max(0, min(1, max(held, flash)))
                GeometryReader { g in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.5))
                        RoundedRectangle(cornerRadius: 3).fill(buildCyan.opacity(0.9)).frame(height: g.size.height * CGFloat(level))
                    }
                }
            }
        }
    }
    // A small square-ish Mute/Solo toggle.
    @ViewBuilder private func buildRecMini(_ label: String, on: Bool, colour: Color, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? colour : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Color.clear : buildEdge, lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    // A PROMINENT toggle (thicker edge, bold, strong lit colour) — used for LATCH and ENABLE.
    @ViewBuilder private func buildRecProminent(_ label: String, on: Bool, colour: Color, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(on ? .black : .white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? colour : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? Color.clear : buildEdge, lineWidth: 1.5))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    // THE EMITTER SELECT box (centre column, bottom): the four PART-owned output emitter toggles (A–D) + the
    // MIDI-OUT readout (lit emitters → their channels). Emitters are part-owned, so every colour follows. (2026-08-17)
    @ViewBuilder private func buildEmitterSelectBox(gridW: CGFloat) -> some View {
        let buses = buildPartEmitters
        VStack(spacing: 6) {
            HStack(spacing: 4) {                                  // A–D toggle the PART's output emitters
                ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, b in
                    buildIOChip(b.rawValue, on: buses.contains(b), fill: true) { buildToggleBus(b) }
                }
            }
            buildMidiOutInfo(buses: buses, castW: gridW - 20)    // the lit emitters + their channels
        }
        .padding(10)
        .frame(width: gridW)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }

    // THE MAIN EMITTERS BOX (right column, bottom): four output controls (A–D), styled like the receivers panel.
    // Each = an INTERACTIVE velocity fader (drag to override output velocity; bottom = kill; release = spring back)
    // + Mute/Solo on one line + a prominent RACK toggle. (Paul 2026-08-17)
    @ViewBuilder private func buildEmittersBox() -> some View {
        HStack(spacing: 6) {                                       // the four emitters A–D sit side by side
            ForEach(0..<4, id: \.self) { i in buildEmitterControl(i) }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }
    @ViewBuilder private func buildEmitterControl(_ i: Int) -> some View {
        let letter = ["A", "B", "C", "D"][i]
        let muted = !(i < busEnabled.count ? busEnabled[i] : true)
        let soloed = emitterFootSolo & (1 << UInt8(i)) != 0
        let racked = rackMask & (1 << UInt8(i)) != 0
        let h: CGFloat = 14 + 68 + 3
        HStack(spacing: 6) {
            buildEmitterFader(i, letter: letter).frame(width: 22, height: h)   // interactive velocity fader — full control height
            VStack(spacing: 3) {
                HStack(spacing: 3) {                                           // MUTE · SOLO on one line
                    buildRecMini("M", on: muted, colour: buildPink) { toggleEmitter(i) }       // mute = disable the bus
                    buildRecMini("S", on: soloed, colour: buildCyan) { toggleEmitterSolo(i) }
                }.frame(height: 14)
                buildRecProminent("RACK", on: racked, colour: Color(red: 0.36, green: 0.92, blue: 0.52)) { toggleRack(i) }.frame(height: 68)   // the RACK gate, prominent
            }.frame(height: h)
        }
    }
    // The interactive velocity fader: the meter (emitPeak, decayed) normally; while DRAGGED it forces the emitter's
    // output velocity (top = 127 · bottom = 0/KILL) via setVelOverride, and releases (springs back) on lift.
    @ViewBuilder private func buildEmitterFader(_ i: Int, letter: String) -> some View {
        let override = i < emitDragVel.count ? emitDragVel[i] : nil
        VStack(spacing: 2) {
            Text(override.map { "\($0)" } ?? letter).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(override != nil ? buildPink : buildDim)
            GeometryReader { g in
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                    let age = tl.date.timeIntervalSince(i < emitPeakAt.count ? emitPeakAt[i] : .distantPast)
                    let meter = (i < emitPeak.count ? emitPeak[i] : 0) * max(0, 1 - age / 0.6)
                    let level = override != nil ? Double(override!) / 127.0 : meter
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.5))
                        RoundedRectangle(cornerRadius: 3).fill((override != nil ? buildPink : buildCyan).opacity(0.9)).frame(height: g.size.height * CGFloat(min(1, max(0, level))))
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let frac = 1 - min(1, max(0, v.location.y / g.size.height))
                        let vel = Int((frac * 127).rounded())
                        if i < emitDragVel.count { emitDragVel[i] = vel }
                        setVelOverride(i, vel)                          // 0 = kill
                    }
                    .onEnded { _ in
                        if i < emitDragVel.count { emitDragVel[i] = nil }
                        setVelOverride(i, nil)                          // release → natural velocity
                    })
            }
        }
    }

    // A bottom-of-column placeholder box (receivers · emitter-select · emitter-out). Contents are stubs for now;
    // the styling (panel fill + edge outline + fixed height) matches the button boxes so all columns read alike.
    @ViewBuilder private func buildBottomPlaceholder(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)   // fixed height (min==max) → no stretch, consistent across columns
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }

    // a fixed-width footer button (the footer uses a Spacer, so these can't be maxWidth-fill like a fill button).
    @ViewBuilder private func buildFooterBtn(_ label: String, pink: Bool = false, action: (() -> Void)? = nil) -> some View {
        Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(pink ? buildPink : Color.white)                                 // §0 MUTED: pink is a WHISPER (ink + edge on neutral), not a slab
            .padding(.horizontal, 16).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 11).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(pink ? buildPink.opacity(0.55) : buildEdge, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }

    // ── small shared placeholder widgets ─────────────────────────────────────────────────────────────────────────
    // The identical audition button at the top of each column (transport glyph + label, cyan-bordered). `active` marks
    // it the playing voice; when active AND the transport plays, it becomes a PLAYHEAD — filling cyan L→R over `fill`'s
    // period (.cell = one step · .grid = the whole 8-column loop), looping. Inactive buttons never animate. (user 2026-08-13)
    @ViewBuilder private func buildColumnButton(_ label: String, active: Bool = false, fill: BuildFill = .none, enabled: Bool = true, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {                                    // BOTH transport signs, the CURRENT state boldly lit (Paul 2026-08-15)
                Image(systemName: "play.fill").font(.system(size: 15, weight: .black))
                    .foregroundColor(active ? Color(red: 0.36, green: 0.92, blue: 0.52) : .white.opacity(0.22))   // PLAYING → GREEN play
                Image(systemName: "stop.fill").font(.system(size: 15, weight: .black))
                    .foregroundColor(active ? .white.opacity(0.22) : Color(red: 0.98, green: 0.5, blue: 0.5))     // STOPPED → RED stop
            }
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(active ? .white : buildCyan).tracking(1)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity).frame(height: 38)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10).fill(active ? buildCyan.opacity(0.28) : buildCell)   // active = dim cyan base (empty)
                if active && d.playing && fill != .none {
                    GeometryReader { g in
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                            RoundedRectangle(cornerRadius: 10).fill(buildCyan.opacity(0.3))              // dim fill = the playhead sweeping L→R
                                .frame(width: g.size.width * buildHeaderFill(fill, tl.date))
                        }
                    }
                }
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? buildCyan : buildEdge, lineWidth: 1))   // §0: the voice keeps the accent; idle mutes
        .opacity(enabled ? 1 : 0.35)                             // DISABLED → greyed out (Paul 2026-08-15)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { buildExitPlaceMode(); action?() } }   // a transport button is not a row selector → leaves PLACE mode
        .allowsHitTesting(enabled)
    }

    // The header playhead's fill fraction (0…1) — phase-locked to the transport, warped by SWING (as the grid playhead).
    // .cell fills over ONE step; .grid fills over the whole 8-column loop.
    private func buildHeaderFill(_ fill: BuildFill, _ now: Date) -> CGFloat {
        let live = ddBeatAnchor + now.timeIntervalSince(ddBeatAnchorAt) * d.tempo / 60.0
        let musical = musicalOf(live, stepBeats: stepBeats, a: max(1.0, Double(swing) / 50.0))
        let period = fill == .cell ? stepBeats : stepBeats * Double(Snap.cols)
        let raw = period > 0 ? (musical / period).truncatingRemainder(dividingBy: 1) : 0
        return CGFloat(max(0, min(1, raw < 0 ? raw + 1 : raw)))
    }
    @ViewBuilder private func buildStep(_ s: String) -> some View {
        Text(s).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).tracking(1.2)   // §0 MUTED: step labels recede (were loud pink)
    }
    @ViewBuilder private func buildIOChip(_ s: String, on: Bool = false, keys: Bool = false, fill: Bool = false, action: (() -> Void)? = nil) -> some View {
        Text(s).font(.system(size: 9, weight: on ? .heavy : .regular, design: .monospaced))
            .foregroundColor(on ? Color.black : (keys ? buildCyan : buildDim))
            .padding(.horizontal, 7)
            .frame(maxWidth: fill ? .infinity : nil).frame(height: 48)   // fill → the row spreads evenly to the cast width; height doubled (24→48)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? buildCyan : buildCell))   // ON keeps the accent (armed); idle mutes
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.clear : buildEdge, lineWidth: 1))   // §0: neutral border when idle (was standing cyan)
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }
    // The SELECT · PLACE · MUTATE radio — a pure radio (always one active) that changes what the left row buttons DO.
    @ViewBuilder private func buildRowModeBtn(_ m: BuildRowMode, enabled: Bool = true) -> some View {
        let armed = buildRowMode == m && enabled
        Text(m.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(armed ? Color.black : Color.white)
            .frame(maxWidth: .infinity).frame(minHeight: 36, maxHeight: 36)   // FIXED height — else the verb box stretches to the page bottom (competes with the Spacer)
            .background(RoundedRectangle(cornerRadius: 9).fill(armed ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(armed ? Color.clear : buildEdge, lineWidth: 1))   // §0: armed keeps the cyan fill; idle mutes to a whisper
            .opacity(enabled ? 1 : 0.3)                                        // DISABLED (PLACE) → greyed, inert
            .contentShape(Rectangle())
            .onTapGesture { if enabled { buildExitPlaceMode(); buildRowMode = m } }   // a verb is not a play-grid row → leaves PLACE mode
            .allowsHitTesting(enabled)
    }
    // The left row-button icon for the current mode: a chevron (SELECT), the TARGET (PLACE) or a wand (MUTATE); the
    // latter two carry the SELECTED palette colour so you see what a press will lay down. (Paul 2026-08-16)
    @ViewBuilder private func buildRowButtonIcon() -> some View {
        switch buildRowMode {
        case .select: Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.55))
        case .place:  Image(systemName: "scope").font(.system(size: 13, weight: .medium)).foregroundColor(buildSelHue)
        case .mutate: Image(systemName: "wand.and.stars").font(.system(size: 12, weight: .medium)).foregroundColor(buildSelHue)
        }
    }
    // A reserved (inert) button slot — the second verb-box row is blank for now (Paul 2026-08-16).
    @ViewBuilder private func buildBlankSlot() -> some View {
        Color.clear.frame(maxWidth: .infinity).frame(minHeight: 36, maxHeight: 36)   // FIXED height — matches the row buttons; keeps the verb box compact
            .background(RoundedRectangle(cornerRadius: 9).fill(buildCell.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(buildEdge.opacity(0.5), lineWidth: 1))
    }
    @ViewBuilder private func buildBox(_ title: String, _ ch: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundColor(.white)
            Text(ch).font(.system(size: 8, design: .monospaced)).foregroundColor(buildDim)   // §0 MUTED: channel readout recedes (was standing cyan)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(buildCell))
    }
    // A processor slot in the footer chain. `colour` fills a REAL processor with the selected colour; else a dashed
    // empty/ghost slot. Boxes are a little bigger than before (50×40).
    @ViewBuilder private func buildSlot(_ s: String, dashed: Bool = false, colour: Color? = nil, bypassed: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: colour != nil ? .heavy : .regular, design: .monospaced))
            .foregroundColor(colour != nil ? .black : (dashed ? buildSelHue : .white))   // dashed capacity/ghost slots = the SELECTED colour
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: 50, height: 40)
            .background(RoundedRectangle(cornerRadius: 7).fill(colour ?? (dashed ? Color.clear : buildCell)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(colour != nil ? Color.clear : (dashed ? buildSelHue : Color(white: 0.15)),
                                                              style: StrokeStyle(lineWidth: dashed ? 1.3 : 1, dash: dashed ? [4] : [])))
            .overlay(bypassed ? RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.45)) : nil)   // a BYPASSED processor reads dimmed
            .opacity(bypassed ? 0.7 : 1)
    }

    // ── PROCESSOR POP-UP EDITOR ──────────────────────────────────────────────────────────────────────────────────
    // Touching a footer processor opens this large, colour-tinted pop-up showing ALL of that processor's controls
    // (reusing ProcessorBox in slotMode). The dimmed scrim closes on tap, but leaves the FOOTER exposed & live — so
    // touching another processor switches straight to its editor. DELETE PROCESSOR + BYPASS sit at the top. (user 2026-08-12)
    @ViewBuilder private func buildProcessorEditor(slot: Int, size: CGSize) -> some View {
        let chain = selectedColourChain()
        let footerReserve = BuildGeom.barH + 26                // keep the footer strip uncovered → still tappable to switch processors
        if slot < chain.count, let cid = ddSelectedColourID {
            ZStack {
                VStack(spacing: 0) {                            // scrim closes on tap — but NOT over the footer
                    Color.black.opacity(0.55).contentShape(Rectangle()).onTapGesture { buildEditSlot = nil }
                    Color.clear.frame(height: footerReserve)
                }
                .ignoresSafeArea()
                buildProcessorPanel(slot: slot, proc: chain[slot], cid: cid, size: size)
                    .padding(.bottom, footerReserve)
            }
        }
    }

    @ViewBuilder private func buildProcessorPanel(slot: Int, proc: ProcessorSlot, cid: String, size: CGSize) -> some View {
        let hue = buildSelHue
        let panelW = min(560, size.width - 80)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {                               // HEADER: colour + name · BYPASS · DELETE PROCESSOR
                RoundedRectangle(cornerRadius: 8).fill(hue).frame(width: 34, height: 34)
                Image(systemName: emblemSymbol(proc.type)).font(.system(size: 20, weight: .black)).foregroundColor(.white)
                Text(proc.type.rawValue).font(.system(size: 22, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                Spacer()
                Button { buildChainToggleBypass(slot) } label: {
                    Text(proc.bypassed ? "BYPASSED" : "BYPASS").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)                  // white on black
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(proc.bypassed ? 0.9 : 0.3), lineWidth: 1))
                }.buttonStyle(.plain)
                Button { buildChainRemoveSlot(slot); buildEditSlot = nil } label: {
                    Text("DELETE PROCESSOR").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(.red)                    // red on black
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.7), lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(hue.opacity(0.22))
            Rectangle().fill(hue.opacity(0.5)).frame(height: 1)
            AnyView(buildColourTabs(castW: panelW - 32, cell: 28))         // the SAME colour tabs, top of the body — select a tab / populate an empty one (pulses until edited; persists on close)
                .padding(.horizontal, 16).padding(.vertical, 8)
            Rectangle().fill(hue.opacity(0.25)).frame(height: 1)
            ScrollView { buildSlotBox(slot, proc, cid: cid).padding(16) }   // CONTROLS — reuse ProcessorBox (our chrome hidden)
        }
        .frame(width: panelW).frame(maxHeight: size.height * 0.82)
        .background(RoundedRectangle(cornerRadius: 16).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(hue, lineWidth: 2))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .contentShape(Rectangle()).onTapGesture { }            // swallow taps inside the panel so they don't reach the scrim (close)
    }

    // ProcessorBox for a BUILD colour-template slot — mirrors DiagView.slotBox but writes COLOUR-scoped (the selected
    // colour's templateChain via withChainColour). Our own header carries Delete/Bypass, so the box's chrome is hidden.
    @ViewBuilder private func buildSlotBox(_ i: Int, _ slot: ProcessorSlot, cid: String) -> some View {
        let sc: Colour = { var c = Colour(colourID: cid, type: slot.type); c.paramsA = slot.params; return c }()
        ProcessorBox(
            colour: sc, colourIndex: -1, face: .a,
            onEdit: { mutate in
                buildChainEditSlot(i) { s in
                    var tmp = Colour(colourID: cid, type: s.type); tmp.paramsA = s.params
                    mutate(&tmp); s.params = tmp.paramsA
                }
            },
            onTranspose: { _ in }, onMorph: { _ in },
            onSetTypeA: { t in buildChainSetType(i, t) },
            height: 260, slotMode: true, slotBypassed: slot.bypassed,
            accentOverride: buildSelHue,
            passHead: d.playing ? (d.pass & 3) : -1,
            onBypass: { buildChainToggleBypass(i) },
            onRemove: { buildChainRemoveSlot(i); buildEditSlot = nil },
            onMacro: nil, plainTitle: true, showSlotChrome: false)
    }

    // BUILD chain edits — colour-scoped + POSITION-PRESERVING: every edit works on the SHOWN chain and is written
    // whole with setColourChain (so slot indices stay put; a deleted slot leaves a passthrough GAP, not a shift).
    private func buildApplyChain(_ chain: [ProcessorSlot]) {
        guard let cid = ddSelectedColourID else { return }
        buildWriteColourMachine(cid, chain)
        // PLACED: a pending tab whose chain has diverged from its source is committed (stops pulsing). (2026-08-17)
        if let p = buildPendingTab, buildRowColour(p) == cid, chain != buildPendingSource {
            buildPendingTab = nil; buildPendingSource = []
        }
    }
    private func buildChainEditSlot(_ i: Int, _ mutate: (inout ProcessorSlot) -> Void) {
        var c = selectedColourChain(); guard i < c.count else { return }; mutate(&c[i]); buildApplyChain(c)
    }
    private func buildChainToggleBypass(_ i: Int) { buildChainEditSlot(i) { $0.bypassed.toggle() } }
    private func buildChainSetType(_ i: Int, _ t: ProcessorType) { buildChainEditSlot(i) { $0.type = t } }
    private func buildChainRemoveSlot(_ i: Int) {                  // DELETE → leave an empty (passthrough) box, keep positions
        var c = selectedColourChain(); guard i < c.count else { return }; c[i] = buildPassthroughSlot(); buildApplyChain(c)
    }
    // ADD a processor at box `i` — pad any empty boxes to its LEFT with passthroughs so its POSITION is remembered,
    // then open that processor's editor pop-up. (user 2026-08-12)
    private func buildChainAddAt(_ i: Int, type: ProcessorType) {
        var c = selectedColourChain()
        while c.count <= i { c.append(buildPassthroughSlot()) }
        c[i] = ProcessorSlot(type: type)
        buildApplyChain(c)
        buildAddSlot = nil; buildEditSlot = i
    }

    // ── ADD-PROCESSOR PICKER ─────────────────────────────────────────────────────────────────────────────────────
    // A big, clear pop-up listing every available processor. Selecting one populates box `slot` and opens its editor.
    @ViewBuilder private func buildProcessorPicker(slot: Int, size: CGSize) -> some View {
        let hue = buildSelHue
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildAddSlot = nil }
            VStack(alignment: .leading, spacing: 12) {
                Text("ADD PROCESSOR").font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundColor(.white).tracking(1)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(ProcessorType.allCases, id: \.self) { t in
                            Button { buildChainAddAt(slot, type: t) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: emblemSymbol(t)).font(.system(size: 20, weight: .black)).foregroundColor(hue).frame(width: 26)
                                    Text(t.rawValue).font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12).frame(height: 52).frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(hue.opacity(0.5), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: min(640, size.width - 60)).frame(maxHeight: size.height * 0.82)
            .background(RoundedRectangle(cornerRadius: 16).fill(buildPanel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(hue, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .contentShape(Rectangle()).onTapGesture { }           // swallow taps inside the panel
        }
    }

    // ── SIGNAL-FLOW DIAGRAM POP-UP (footer eye) ──────────────────────────────────────────────────────────────────
    // Reuses the PROCESSORS page's flow diagram (MIDI in → processor row → emitter row, one dotted thread) for the
    // SELECTED colour's machine. Display-only for now; animation is a later slice. (user 2026-08-13)
    @ViewBuilder private func buildFlowPopup(size: CGSize) -> some View {
        let hue = buildSelHue
        let w = min(1000, size.width - 80)
        let cell: Cell = {
            var c = Cell(colourID: ddSelectedColourID ?? "")
            c.processors = selectedColourChain()                  // show exactly the footer chain (incl. empty "+" slots)
            c.inputReceiver = buildSelReceiver
            c.buses = ddSelectedColourBuses()
            return c
        }()
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildFlowOpen = false }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "eye").font(.system(size: 16, weight: .semibold)).foregroundColor(hue)
                    Text("THE MIDI CHAIN").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(.white).tracking(1)
                    Spacer()
                }
                flowDiagram(cell, width: w).allowsHitTesting(false)   // the exact processors-page diagram — display-only
            }
            .padding(18)
            .frame(width: w + 36)
            .background(RoundedRectangle(cornerRadius: 16).fill(buildPanel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(hue, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .contentShape(Rectangle()).onTapGesture { }
        }
    }

    // ── FULL-SCREEN GRID POP-UP (grid eye) ───────────────────────────────────────────────────────────────────────
    // Shows JUST the respective grid (0 = staging, 1 = perform) at a large cell size, in PLAY mode. (user 2026-08-13)
    @ViewBuilder private func buildGridPopupView(_ kind: Int, size: CGSize) -> some View {
        let hue = buildSelHue
        let popupW = min(920, size.width - 80)
        let cellByW = (popupW - BuildGeom.cellGap * 9 - 44) / 10          // 10-cell span (matches the perform grid)
        let cellByH = (size.height - 150 - BuildGeom.cellGap * 8) / 10    // ~9 cells tall + header/padding → clamp so it FITS onscreen
        let cell = max(20, min(46, min(cellByW, cellByH)))
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildGridPopup = nil }
            VStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "eye").font(.system(size: 16, weight: .semibold)).foregroundColor(hue)
                    Text(kind == 0 ? "STAGING GRID" : "PERFORM GRID").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(.white).tracking(1)
                    Spacer()
                }
                if kind == 0 {
                    AnyView(buildStagingGrid(cell: cell, hue: hue))
                } else {
                    AnyView(HStack(alignment: .top, spacing: BuildGeom.cellGap) {
                        buildFlattenMode ? AnyView(buildPartButtons(cell: cell, hue: buildCyan, bands: [3, 2, 1, 1])) : AnyView(buildPerformRowButtons(cell: cell))
                        VStack(spacing: BuildGeom.cellGap) { buildLoopKeys(cell: cell); AnyView(buildPlayBands(cell: cell)) }
                        buildFlattenMode ? AnyView(buildRightPartButtons(cell: cell, hue: buildCyan)) : AnyView(buildRightPartButtons(cell: cell, hue: buildCyan).hidden())
                    })
                }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 16).fill(buildPanel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(hue, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .contentShape(Rectangle()).onTapGesture { }
        }
    }
}

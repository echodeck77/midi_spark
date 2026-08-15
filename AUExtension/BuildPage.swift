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
private let buildEdge  = Color(white: 1).opacity(0.17)   // §0 MUTED-CHROME: a neutral whisper for default (non-armed) chrome borders — replaces standing cyan strokes
private let buildPartInk = Color(white: 1).opacity(0.9)  // §2 BRIGHTNESS = WHICH PART: a NEUTRAL bright accent (no second hue) — the part's presence across bench + stage

// iteration 4: the spring-held workbench verbs that replace the drag (the house law). Skeleton: tap arms/disarms.
enum BuildVerb: String { case place = "PLACE", move = "MOVE", delete = "DELETE" }
enum BuildGridMode: String { case play = "PLAY", edit = "EDIT" }   // the per-grid PLAY/EDIT radio (styled like PART 1 ▾)
enum BuildFill { case none, cell, grid }   // header playhead fill period: none · one step (.cell) · the whole loop (.grid)

// A PART — the workshop-level unit of the BUILD lifecycle (unassigned → built → staged → deployed). It owns its own
// staging grid + variations, its cast selection, and its PART-OWNED I/O (one input door + a set of output emitters,
// shared across every colour/cell of the part). `deployed` christens it (PART n) on first assignment to the play grid.
// (design ferry AcceptanceCriteria-part-lifecycle-io, 2026-08-12)
struct BuildPart {
    var stagingCells: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    var stagingSel: [Int] = Array(repeating: -1, count: 8)
    var rowChain: [[ProcessorSlot]] = Array(repeating: [], count: 8)
    var rowShade: [Double] = Array(repeating: 0, count: 8)
    var rowUnder: [String?] = Array(repeating: nil, count: 8)   // one-colour-per-row: what a row REVERTS to when its colour is stamped elsewhere
    var colourSel: Int = 0            // the cast selection (colourIDs index)
    var cast: [String] = []           // §2 CAST VIEW: the part's visible palette — a per-part MEMBERSHIP over the global colour store (begins clean)
    var receiver: Int = 0             // the PART's input door (R1–R4) — shared across all its colours
    var emitters: Set<Bus> = [.a]     // the PART's output emitters — shared across all its colours
    var deployed: Bool = false        // christened (PART n) once deployed to the play grid
}

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
                AnyView(buildPaletteColumn(colW: leftW).frame(width: leftW, alignment: .center))
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
            AnyView(buildPaletteColumn(colW: size.width - 20))   // AnyView boundaries — see buildLandscape's note (metadata-stack overflow)
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
    @ViewBuilder private func buildPaletteColumn(colW: CGFloat) -> some View {
        let castW = max(160, colW - 4)                            // the receivers/cast/emitters/midi-select FILL the column width
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THIS MIDI CHAIN", active: !buildDisplayStaging, fill: .cell, action: { buildRequestMachineVoice() }))   // header responds immediately (display); MIDI switch quantized
            AnyView(buildPartHeader())                            // TOP: part · receivers · midi-select · octave
            AnyView(buildInputSection(castW: castW))
            Spacer(minLength: 0)
            AnyView(buildCastSection(castW: castW))               // CENTRE: the cast, vertically centred between the two
            Spacer(minLength: 0)
            AnyView(buildOutputSection(castW: castW))             // BOTTOM (above the footer): MIDI OUT + the emitters
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // §1 THE THREAD (colour-architecture): a thin selected-hue edge down the LEFT column → it reads with the
        // footer chain (also hue-framed) as ONE object — the machine's anatomy, input → thread → chain → output.
        // Alpha is a starting point; Paul tunes on glass.
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(buildSelHue.opacity(0.55)).frame(width: 2).padding(.vertical, 6) }
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

    @ViewBuilder private func buildCastSection(castW: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            buildCastPalette(castW: castW)
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
        buildStagingSyncIfPlaying()                               // the part's emitters apply to every staging cell, live
    }

    // PLAY THIS MACHINE ⟷ PLAY THE STAGING GRID are a RADIO — the ONE workshop voice, DEFAULTING to the MACHINE
    // (`buildStagingPlaying == false`). Selecting one deselects the other; the visual always follows the flag so the
    // buttons never appear dead. The MACHINE side also engages the audition (best-effort — needs a selected colour).
    // Internal so the VC can engage it on BUILD appear (so the default machine voice actually SOLOS — never the whole grid).
    func buildSelectMachineVoice() {
        au?.setBuildStagingScene(nil)                           // leave STAGING/PIECE playback → the solo audits against the real scene
        buildStagingPlaying = false                              // CHAIN ⟂ PART; the PIECE is independent (correction) — it keeps its flag/sound
        buildSeedCastIfNeeded()                                  // §2: part 1's cast reflects the already-defined colours (once); selects within the cast
        ddStickyReceiver = buildSelReceiver                      // §2: the chain audition uses the PART's I/O (door + emitters)
        ddStickyBuses = buildPartEmitters.isEmpty ? [.a] : buildPartEmitters
        // A colour that was never given a chain has a nil templateChain, which the engine resolves via the LEGACY
        // A-face — and every default colour is type .arp, so auditioning it plays an arp the user can't see in the
        // (empty) chain. Convert that implicit arp into an EXPLICIT passthrough once, so what you hear matches the
        // shown-empty chain (unprocessed MIDI). Only fires when templateChain is nil → no churn on real chains. (user 2026-08-12)
        if let cid = ddSelectedColourID, au?.colourHasStoredChain(cid) == false {
            au?.withChainColour(cid) { $0 = [] }; refreshFromDocument()   // read the LIVE document (docColours is empty on first appear)
        }
        ddSolo = true; ddEngageSolo()                            // engage the machine audition (springs back off if it can't)
    }
    private func buildSelectStagingVoice() {
        if ddSolo { ddSolo = false; au?.clearColourSolo() }      // CHAIN ⟂ PART: stop the chain audition (they're mutually exclusive)
        buildStagingPlaying = true                               // the PART is a voice — the PIECE (if playing) keeps sounding ALONGSIDE (correction)
        buildPublishScene()
    }

    // The header buttons REQUEST a workshop-voice switch; while the transport runs, the switch is QUANTIZED to the next
    // cell boundary (buildCommitPendingVoice, fired from the VC's absoluteStep hook) so it lands on the grid, not mid-cell.
    // Stopped, or re-selecting the same voice → immediate. (Paul 2026-08-14)
    func buildRequestMachineVoice() { buildRequestVoice(staging: false) }
    func buildRequestStagingVoice() { buildRequestVoice(staging: true) }
    private func buildRequestVoice(staging: Bool) {
        if d.playing && staging != buildStagingPlaying {
            buildPendingVoiceStaging = staging                   // arm — applied at the next cell boundary
        } else {
            buildPendingVoiceStaging = nil
            staging ? buildSelectStagingVoice() : buildSelectMachineVoice()
        }
    }
    // Apply an armed voice switch at a cell boundary (or on transport stop). Called from the VC.
    func buildCommitPendingVoice() {
        guard let s = buildPendingVoiceStaging else { return }
        buildPendingVoiceStaging = nil
        s ? buildSelectStagingVoice() : buildSelectMachineVoice()
    }
    // The DISPLAYED workshop voice: the armed target if a switch is pending, else the live one. The HEADER reads this so
    // it highlights the new voice IMMEDIATELY on tap, while the MIDI still switches quantized at the boundary. (Paul 2026-08-15)
    var buildDisplayStaging: Bool { buildPendingVoiceStaging ?? buildStagingPlaying }

    // Publish the ephemeral scene for the ACTIVE voices. §correction (2026-08-13): the PIECE is INDEPENDENT of the
    // audition — PLAY THIS PART + START/STOP THE PLAY GRID sound TOGETHER (the shopping/alongside workflow). Each
    // staging/perform cell takes its PART-owned I/O + the colour's machine (or a staged variation chain). The CHAIN
    // audition (PLAY THIS MIDI CHAIN) owns the render via a solo on the real scene, so it leaves the ephemeral clear.
    private func buildPublishScene() {
        if ddSolo { au?.setBuildStagingScene(nil); return }      // chain audition owns the render (solo)
        guard buildStagingPlaying || buildPerformPlaying else { au?.setBuildStagingScene(nil); return }
        var s = SceneState.empty()
        if buildPerformPlaying {                                 // THE PIECE — every deployed cell (one row per part)
            for c in 0..<8 { for r in 0..<8 {
                guard let cid = buildPerformCells[c][r] else { continue }
                var cell = Cell(colourID: cid, buses: buildPerformEmit[r].isEmpty ? [.a] : buildPerformEmit[r])
                cell.inputReceiver = max(0, min(3, buildPerformRecv[r]))
                cell.processors = buildPerformChain[c][r].isEmpty ? nil : buildPerformChain[c][r]
                s.setCell(c, r, cell)
            } }
        }
        if buildStagingPlaying {                                 // THE PART — the staging selection, ALONGSIDE the piece
            let buses = buildPartEmitters.isEmpty ? [.a] : buildPartEmitters
            let recv = max(0, min(3, buildSelReceiver))
            for c in 0..<8 {
                let r = c < buildStagingSel.count ? buildStagingSel[c] : -1
                guard r >= 0, r < 8, let cid = buildStagingCells[c][r] else { continue }
                var cell = Cell(colourID: cid, buses: buses)
                cell.inputReceiver = recv
                cell.processors = r < buildRowChain.count && !buildRowChain[r].isEmpty ? buildRowChain[r] : nil
                s.setCell(c, r, cell)                            // the audition sits in front on a slot collision
            }
        }
        au?.setBuildStagingScene(s)
    }

    // STAGE THE GRID — from the selected colour's machine, generate 7 VARIATIONS; order all 8 (original + variations)
    // by OUTPUT COMPLEXITY; lay one machine per row top→bottom (least→most complex), each row shaded lighter→darker;
    // select the ORIGINAL's row in every column; switch to PLAY mode + play the staging grid. (user 2026-08-12)
    private func buildStageTheGrid() {
        guard let cid = ddSelectedColourID else { return }
        var rng = SystemRandomNumberGenerator()
        let base = selectedColourChain().filter { !buildIsEmptySlot($0) }
        var machines: [[ProcessorSlot]] = [base.isEmpty ? [] : base]          // index 0 = the ORIGINAL
        for _ in 0..<7 { machines.append(buildVaryChain(base, &rng)) }
        func complexity(_ c: [ProcessorSlot]) -> Int { let e = Dice.evalRun(c); return e.sig.count * 100 + e.peak }   // output density
        let ranked = machines.enumerated().sorted { complexity($0.element) < complexity($1.element) }   // ascending: least → most complex
        var originalRow = 0
        for (row, item) in ranked.enumerated() {
            buildRowChain[row] = item.element
            buildRowShade[row] = 0.7 - Double(row) / 7.0 * 1.4                 // +0.7 (lightest, top) → −0.7 (darkest, bottom)
            if item.offset == 0 { originalRow = row }                          // where the original landed
        }
        for c in 0..<8 { for r in 0..<8 { buildStagingCells[c][r] = cid }; buildStagingSel[c] = originalRow }   // fill the grid; select the original's row everywhere
        buildDeletedRows.removeAll(); buildPlacedOrig.removeAll()
        buildStagingMode = .play                                              // auto-shift to PLAY mode
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
        for c in 0..<8 {
            let r = buildStagingSel[c]
            if r < 0 || r >= 8 || buildStagingCells[c][r] == nil {
                buildStagingSel[c] = (0..<8).first { buildStagingCells[c][$0] != nil } ?? -1
            }
        }
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
        guard let cid = ddSelectedColourID, let c = docColours.first(where: { $0.colourID == cid }) else { return [] }
        var chain = c.templateChain ?? []
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
        p.colourSel = ddColourSel; p.receiver = buildSelReceiver; p.emitters = buildPartEmitters; p.cast = buildPartCast
        buildParts[buildCurrentPart] = p
    }
    private func buildLoadPart(_ i: Int) {
        guard i >= 0, i < buildParts.count else { return }
        buildCurrentPart = i
        let p = buildParts[i]
        buildStagingCells = p.stagingCells; buildStagingSel = p.stagingSel
        buildRowChain = p.rowChain; buildRowShade = p.rowShade; buildRowUnder = p.rowUnder
        ddColourSel = p.colourSel; buildSelReceiver = p.receiver; buildPartEmitters = p.emitters; buildPartCast = p.cast
        buildPulseColourID = nil; buildDeletedRows = [:]; buildPlacedOrig = [:]   // transient — never crosses a part
        buildEnsureCastSelection()                              // §2: keep the selection inside this part's cast (empty cast → none)
        buildStagingSyncIfPlaying()
    }
    // THE DEFAULT PALETTE (Paul 2026-08-14): eight starter colours, one per processor type (arp/ratchet/euclid/echo
    // named + strum/chance/harmonize/drone — NEVER passgate). They open the palette as 2 rows of 4 and are present in
    // every part's cast. Each carries a single-processor machine at that type's default settings.
    static let buildDefaultTypes: [ProcessorType] = [.arp, .ratchet, .euclid, .echo, .strum, .chance, .harmonize, .drone]
    func buildDefaultCastIDs() -> [String] { Array(colourIDs.prefix(min(Self.buildDefaultTypes.count, colourIDs.count))) }
    // Define global colours 0–7 as the default machines (once). Idempotent — safe to re-run; re-stamps the machine.
    func buildSeedDefaultColours() {
        for (i, t) in Self.buildDefaultTypes.enumerated() where i < colourIDs.count {
            if !ddColourShown(i) { ddCreateColour(i) }                     // make the global colour exist
            au?.withChainColour(colourIDs[i]) { $0 = [ProcessorSlot(type: t)] }   // its default single-processor machine
        }
        refreshFromDocument()
    }
    // Seed the 8 default colours + open part 1's palette on them, ONCE. Every NEW part also opens on the defaults
    // (see buildAddPart) so the starter palette is always there. §2 cast view.
    func buildSeedCastIfNeeded() {
        guard !buildCastSeeded else { return }
        buildCastSeeded = true
        buildSeedDefaultColours()
        buildPartCast = buildDefaultCastIDs()
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count { buildParts[buildCurrentPart].cast = buildPartCast }
        buildEnsureCastSelection()
    }
    // Keep the selection within the PART's cast (its own palette). A fresh, EMPTY cast → NO selection: the footer + the
    // machine audition have nothing until the user adds a colour. Replaces the global ddEnsureSelection on BUILD. §2.
    func buildEnsureCastSelection() {
        if let cid = ddSelectedColourID, buildPartCast.contains(cid) { return }   // already a valid cast member
        if let first = buildPartCast.first, let gi = colourIDs.firstIndex(of: first) { ddColourSel = gi } else { ddColourSel = -1 }
    }
    private func buildSwitchPart(_ i: Int) { guard i != buildCurrentPart else { return }; buildSavePart(); buildLoadPart(i) }
    // §3: a NEW part arrives FRESH — empty staging, unset I/O; its palette opens on the 8 DEFAULTS (Paul 2026-08-14).
    private func buildAddPart() {
        buildSavePart()
        var p = BuildPart(); p.cast = buildDefaultCastIDs()
        buildParts.append(p); buildLoadPart(buildParts.count - 1)
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
        buildPublishScene()                                      // reflect live if the piece is playing
    }

    // Land the current part on a BAND. Christens like a flatten. (Paul 2026-08-14 — deployment semantics by target shape:)
    //   • MULTI-ROW band (rows > 1): copy the whole staging LADDER — every OCCUPIED staging row (selected AND muted cells)
    //     becomes a band rung, top-down, capped to the band's height. Nothing is dropped; the muted cells are the rungs.
    //   • SINGLE-ROW band (rows == 1): the selected cell per column (regardless of row), blank where unselected.
    func buildDeployBand(base: Int, rows: Int) {
        guard buildCurrentPart < buildParts.count else { return }
        buildParts[buildCurrentPart].deployed = true
        for i in 0..<rows where base + i < 8 { for c in 0..<8 { buildPerformCells[c][base + i] = nil; buildPerformChain[c][base + i] = [] }; buildPerformPart[base + i] = buildCurrentPart }   // clear the band + claim it for this part (§2)
        if rows <= 1 {
            buildCopySelectedRow(toRow: base)                    // a lane: the selected melody, blank where unselected
        } else {
            let occupied = (0..<8).filter { sr in (0..<8).contains { c in buildStagingCells[c][sr] != nil } }   // staging rows that hold ANY cell
            for (i, sr) in occupied.prefix(rows).enumerated() {  // one rung per occupied staging row (muted cells included)
                let R = base + i; guard R < 8 else { break }
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
    func buildBandValve(base: Int, rows: Int) {
        let setPart = (0..<rows).compactMap { i -> Int? in let R = base + i; return R < 8 && buildPerformPart[R] >= 0 ? buildPerformPart[R] : nil }.first
        if let p = setPart, p < buildParts.count {           // SET → RESTORE (the part comes home to be rethought)
            buildSwitchPart(p)                               // save the current (fresh) workshop, load p's stashed one
            for i in 0..<rows where base + i < 8 { for c in 0..<8 { buildPerformCells[c][base + i] = nil; buildPerformChain[c][base + i] = [] }; buildPerformPart[base + i] = -1 }
            buildParts[p].deployed = false
            // OUTPUT (Paul 2026-08-14): the play grid CONTINUES for every still-deployed part; the demoted part plays
            // from the PART grid (alongside). Chain audition off — output is now piece + this part.
            if ddSolo { ddSolo = false; au?.clearColourSolo() }
            buildStagingPlaying = true                       // the demoted part sounds from the part grid
            buildPerformPlaying = buildPerformPart.contains { $0 >= 0 }   // the play grid keeps going iff other parts remain deployed
            buildPublishScene()
        } else {                                             // EMPTY → FLATTEN + christen, then STASH + clear the bench
            buildDeployBand(base: base, rows: rows)          // deploy the current part (copy rows) + christen
            buildAddPart()                                   // stash the workshop behind the band + open a fresh part
            // OUTPUT + FOCUS (Paul 2026-08-14/15): the PLAY GRID starts on assignment and carries the output; FOCUS
            // moves to the fresh PART grid (empty → silent, so the output is the play grid) — NOT the chain. Chain off.
            if ddSolo { ddSolo = false; au?.clearColourSolo() }
            buildStagingPlaying = true
            buildPerformPlaying = true
            buildPublishScene()
        }
    }

    // START/STOP THE PLAY GRID — the PIECE voice (third zoom level). INDEPENDENT of the auditions (correction):
    // starting/stopping it never touches the chain/part; the stage plays until the user stops it.
    private func buildTogglePerformVoice() {
        buildPerformPlaying.toggle()
        buildPublishScene()
    }
    private var buildCurrentDeployed: Bool { buildCurrentPart < buildParts.count && buildParts[buildCurrentPart].deployed }
    private func buildPartName(_ i: Int) -> String { i < buildParts.count && buildParts[i].deployed ? "PART \(i + 1)" : "UNASSIGNED PART" }

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
            Image(systemName: "eye").font(.system(size: 13, weight: .semibold)).foregroundColor(buildCyan)   // LEFT: open this grid full-screen
                .padding(.horizontal, 10).frame(height: 26)      // a chip matching PLAY/EDIT's height, with side padding
                .background(RoundedRectangle(cornerRadius: 8).fill(buildPanel))
                .contentShape(Rectangle()).onTapGesture { onEye?() }
            Spacer(minLength: 0)
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

    @ViewBuilder private func buildCastPalette(castW: CGFloat) -> some View {
        let cols = 8                                                // 8×4 grid (original proportions); defaults sit in the top-left 4×2 block
        let swatch = (castW - BuildGeom.castGap * CGFloat(cols - 1)) / CGFloat(cols)   // 8 swatches fill the column width
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
                        buildCastSlot(row * cols + col, swatch: swatch, pulseSlot: pulseSlot)
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
    @ViewBuilder private func buildCastSlot(_ i: Int, swatch: CGFloat, pulseSlot: Int?) -> some View {
        if i == pulseSlot, let pid = buildPulseColourID {          // the PULSING candidate → tap to commit (SELECT it; never a duplicate)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let phase = 0.5 + 0.5 * sin(tl.date.timeIntervalSinceReferenceDate * 3.4)   // pulse the colour in/out over black
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black)
                    RoundedRectangle(cornerRadius: 6).fill(colourColor(pid) ?? buildCell).opacity(0.15 + 0.85 * phase)
                }
                .frame(width: swatch, height: swatch)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))   // a NEUTRAL border — pulsing is NOT the selected/targeted state
                .contentShape(Rectangle())
                .onTapGesture { buildCommitPulse() }
            }
        } else if let m = buildCastMemberAt(i) {                   // a MEMBER of the cast — TAP selects, LONG-PRESS adds
            let id = buildPartCast[m]
            RoundedRectangle(cornerRadius: 6).fill(colourColor(id) ?? buildCell)
                .frame(width: swatch, height: swatch)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [3]))
                    .opacity(id == ddSelectedColourID ? 1 : 0))
                .overlay { if id == ddSelectedColourID { buildTargetMark(swatch * 0.6) } }   // THE TARGET rides the selected cast cell
                .contentShape(Rectangle())
                .onTapGesture { if let gi = colourIDs.firstIndex(of: id) { ddSelectColour(gi) } }
                .onLongPressGesture(minimumDuration: 0.4) { buildAddCastColour() }   // ANY button can ADD a colour — via long press (Paul 2026-08-14)
        } else {                                                   // an EMPTY slot — a "+" that ADDS on LONG PRESS (every button can add)
            RoundedRectangle(cornerRadius: 6).fill(buildCell)
                .frame(width: swatch, height: swatch)
                .overlay(Text("+").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(buildDim))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) { buildAddCastColour() }
        }
    }

    // THE PALETTE GRID stays 8×4 (32 slots). The 8 DEFAULTS occupy the TOP-LEFT 4×2 block (a proportion of the grid);
    // user-added colours fill from the BOTTOM-RIGHT corner (slot 31 first, then 30, …) so a new colour "starts bottom-right".
    private var buildCastDefaultCount: Int { min(Self.buildDefaultTypes.count, buildPartCast.count) }
    // slot (0–31) → the buildPartCast index shown there, or nil (an empty slot). 8 cols × 4 rows.
    private func buildCastMemberAt(_ slot: Int) -> Int? {
        let dc = buildCastDefaultCount
        let row = slot / 8, col = slot % 8
        if row < 2 && col < 4 {                                       // the top-left 4×2 default block
            let k = row * 4 + col
            return k < dc ? k : nil
        }
        let a = 31 - slot                                            // adds fill from the bottom-right corner
        return (a >= 0 && a < buildPartCast.count - dc) ? dc + a : nil
    }
    // The bottom-right-most FREE add slot — where the next colour is proposed/committed (nil once the palette is full).
    private func buildFirstFreePaletteSlot() -> Int? {
        let slot = 31 - (buildPartCast.count - buildCastDefaultCount)
        return slot > 11 ? slot : nil                                 // adds live below/right of the default block; never collide with it
    }
    // The next UNDEFINED global colour to materialize (nil = all 16 exist).
    private func buildFirstUndefinedGlobal() -> Int? { (0..<colourIDs.count).first { !ddColourShown($0) } }
    // ADD a colour to THIS part's cast: materialize a fresh global colour (or reuse one not yet in the cast), add its ID.
    private func buildAddCastColour() {
        if let j = buildFirstUndefinedGlobal() {
            buildCreateColour(j)
            if !buildPartCast.contains(colourIDs[j]) { buildPartCast.append(colourIDs[j]) }
            ddSelectColour(j)
        } else if let j = (0..<colourIDs.count).first(where: { !buildPartCast.contains(colourIDs[$0]) }) {
            buildPartCast.append(colourIDs[j]); ddSelectColour(j)     // all 16 defined → SHARE an existing one into this cast
        }
    }
    // Commit the pulsing candidate: a staged VARIATION becomes a NEW palette colour (carrying its machine); an existing
    // colour is simply selected. Either way the colour is SELECTED (its machine loads into the footer) — and THE TARGET
    // then marks it in the cast + on its selected grid cells, so the user edits the machine knowing what's in focus.
    private func buildCommitPulse() {
        guard let pid = buildPulseColourID else { buildPulseColourID = nil; return }
        if buildPartCast.contains(pid), let idx = colourIDs.firstIndex(of: pid) {
            ddSelectColour(idx)                                   // ALREADY a palette member → just SELECT it, never duplicate (Paul 2026-08-14)
        } else if !buildPulseChain.isEmpty, let j = buildFirstUndefinedGlobal() {
            buildCreateColour(j)                                  // a NEW variation → materialize a new global colour carrying its machine
            au?.withChainColour(colourIDs[j]) { $0 = buildPulseChain }
            if !buildPartCast.contains(colourIDs[j]) { buildPartCast.append(colourIDs[j]) }
            ddSelectColour(j)
        } else if let idx = colourIDs.firstIndex(of: pid) {
            if !buildPartCast.contains(pid) { buildPartCast.append(pid) }   // LAST TOUCHED promotes the colour INTO this part's cast (§2)
            ddSelectColour(idx)                                   // select it (loads its machine into the footer)
        }
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
            AnyView(buildColumnButton("PLAY THIS PART", active: buildDisplayStaging, fill: .grid, action: { buildRequestStagingVoice() }))   // header responds immediately (display); MIDI switch quantized
            buildGridModeRadio($buildStagingMode) { buildStagingMode = .play; buildGridPopup = 0 }   // eye → full-screen staging grid (play mode)
            AnyView(buildStagingGrid(cell: cell, hue: hue))       // AnyView — keeps the deep 8×8 type out of this body
            AnyView(buildStagingVerbBox(gridW: gridW))
                .opacity(buildStagingMode == .play ? 0.35 : 1)    // PLAY mode disables the editing verbs
                .allowsHitTesting(buildStagingMode == .edit)
            Spacer(minLength: 0)
            AnyView(buildPopulate(gridW: gridW))                  // bottom of the centre column, above the footer
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // STAGE THE GRID — the prominent call-to-action at the bottom of the centre column (upward chevron above the text).
    @ViewBuilder private func buildPopulate(gridW: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.up").font(.system(size: 12, weight: .heavy)).foregroundColor(buildPink)
            Text("STAGE THE GRID").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1)
        }
        .frame(width: gridW).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(buildCell))                      // §0 MUTED: a restrained CTA — pink is a WHISPER (ink + edge), not a slab
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(buildPink.opacity(0.55), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { buildStageTheGrid() }
    }

    // the staging 8×8 (row rail · loop keys · variation rows) — its OWN opaque view so its deep generic type doesn't
    // blow the metadata demangler's stack (see buildPaletteColumn's note).
    @ViewBuilder private func buildStagingGrid(cell: CGFloat, hue: Color) -> some View {
        HStack(alignment: .top, spacing: BuildGeom.cellGap) {
            buildRowButtons(cell: cell, hue: hue, bands: [8]) { row in                      // press a row button …
                if buildStagingMode == .edit, buildVerb == .delete { buildDeleteStagingRow(row) }   // (edit + DELETE → clear the row; 2nd press restores)
                else { buildStampRow(row) }                                                 // else → SET the row to the selected colour (one colour per row)
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
                                    .overlay { if id != nil && id == ddSelectedColourID { buildTargetMark(cell * 0.55) } }   // TARGET on EVERY cell matching the selected palette colour (editable), selected or not
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
    }

    // The outline colour for a staging cell: WHITE for the ONE selected (playing) cell of its column; the SELECTED
    // colour when PLACE is armed (so you can see where a place lands); otherwise none.
    private func buildStagingStroke(c: Int, r: Int, stocked: Bool) -> Color {
        if buildStagingSel[c] == r { return .white }   // the selected (playing) rung — WHITE even when unpopulated (Paul 2026-08-15)
        if buildStagingMode == .edit && buildVerb == .place { return buildSelHue }   // place cue only when EDIT + PLACE
        return .clear
    }

    // A staging cell tap. In PLAY mode the verbs are DISABLED — a tap on a STOCKED cell just makes it the active
    // (playing) cell for its column. In EDIT mode: PLACE stocks the selected colour, DELETE clears, etc.
    private func buildStagingTap(_ c: Int, _ r: Int) {
        if let id = buildStagingCells[c][r] {                     // touching a STOCKED cell offers its colour+settings as a PULSING palette candidate
            buildPulseColourID = id
            buildPulseChain = (r < buildRowChain.count && !buildRowChain[r].isEmpty) ? buildRowChain[r] : []
        }
        if buildStagingMode == .play {                            // PLAY mode → SELECT / DESELECT one rung per column (populated or NOT — Paul 2026-08-15)
            buildStagingSel[c] = (buildStagingSel[c] == r) ? -1 : r   // tap the selected rung → deselect (column silent); else select it (any rung)
            buildStagingSyncIfPlaying()
            return                                                // early return → no reconcile, so an explicit −1 sticks
        }
        switch buildVerb {
        case .place:
            guard let cid = ddSelectedColourID else { break }
            let key = c * 8 + r
            if buildStagingCells[c][r] == cid, let orig = buildPlacedOrig[key] {   // 2nd tap → revert to what the cell held before
                buildStagingCells[c][r] = orig
                buildPlacedOrig.removeValue(forKey: key)
            } else {                                                                // 1st tap → remember the original, then place
                buildPlacedOrig.updateValue(buildStagingCells[c][r], forKey: key)  // updateValue (not subscript) so a nil original is KEPT, not dropped
                buildStagingCells[c][r] = cid
                buildStagingSel[c] = r                                             // a newly placed cell becomes the SELECTED (playing) cell for its column
            }
        case .delete: buildStagingCells[c][r] = nil; buildPlacedOrig.removeValue(forKey: c * 8 + r)
        default: break
        }
        if r < buildRowChain.count { buildRowChain[r] = [] }   // a manual edit turns a STAGED variation row back into a normal row
        buildReconcileStagingSel()                             // a revert/delete may have emptied the selected cell → fall back
        buildStagingSyncIfPlaying()                             // reflect the edit in the live staging audio
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
        for c in 0..<8 where !buildColumnHasSelection(c) { buildStagingSel[c] = row }   // auto-select only where the column has no pick
        buildStagingSyncIfPlaying()
    }

    // DELETE verb + a staging ROW button: first press empties every cell in the row (settings cleared); a second
    // press RESTORES the row to exactly what it held. (user 2026-08-12)
    private func buildDeleteStagingRow(_ row: Int) {
        guard row >= 0, row < 8 else { return }
        if let saved = buildDeletedRows[row] {                 // 2nd press → restore
            for c in 0..<8 { buildStagingCells[c][row] = c < saved.count ? saved[c] : nil }
            buildDeletedRows[row] = nil
        } else {                                                // 1st press → save + clear
            buildDeletedRows[row] = (0..<8).map { buildStagingCells[$0][row] }
            for c in 0..<8 { buildStagingCells[c][row] = nil }
        }
        buildReconcileStagingSel()                             // emptied/restored cells → refresh each column's selection
        buildStagingSyncIfPlaying()
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
                            RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.11))   // §0 MUTED: neutral row rail (matches the loop keys)
                                .frame(width: cell, height: cell)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildEdge, lineWidth: 1))
                                .overlay(Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.55)))
                                .contentShape(Rectangle())
                                .onTapGesture { onRow?(base + r) }  // press → fill that whole grid row
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
                    .onTapGesture { buildBandValve(base: base, rows: rows) }   // THE VALVE: empty → flatten+stash+clear · set → restore
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
                let mine = buildPerformPart[r] == buildCurrentPart
                RoundedRectangle(cornerRadius: 7).fill(buildHues[bandIndex % buildHues.count].opacity(0.4))   // §4: wears its BAND's hue (matches the cell wash + left rail)
                    .frame(width: cell, height: cell)
                    .overlay(Text("\(bandIndex + 1)").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(mine ? 0.95 : 0.45)))
                    .overlay(alignment: .trailing) { if mine { Rectangle().fill(buildPartInk).frame(width: 3) } }   // §2: current part's rows get the bright-ink bracket
                    .contentShape(Rectangle())
                    .onTapGesture { buildDeployCurrentPart(toRow: r) }   // §1: assign the current part to THIS row → deploy + christen
            }
        }
    }

    // ── RIGHT COLUMN: the PLAY grid — five fixed bands + glyph rail; the target decides the verb ───────────────────
    @ViewBuilder private func buildPlayColumn(cell: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("START/STOP THE PLAY GRID", active: buildPerformPlaying, fill: .grid, action: { buildTogglePerformVoice() }))   // the PIECE voice
            buildGridModeRadio($buildPlayMode) { buildPlayMode = .play; buildGridPopup = 1 }   // eye → full-screen perform grid (play mode)
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
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(id.flatMap { colourColor($0) } ?? Color.black.opacity(0.35))   // TRUE colour · else the empty recess (preview shows as an outline, not a fill)
                                    .frame(width: cell, height: cell)
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.09), lineWidth: 1))   // outline every cell → the grid READS even when empty
                                    .overlay { if let g = ghost, let gc = colourColor(g) {   // THE PREVIEW = a THICK, DIMMED OUTLINE in the colour (not a fill)
                                        RoundedRectangle(cornerRadius: 7).strokeBorder(gc.opacity(0.45), lineWidth: 3) } }
                                    .overlay { if id != nil && id == ddSelectedColourID { buildTargetMark(cell * 0.55) } }   // THE TARGET rides every play-grid cell matching the selected machine
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

    // a fixed-width footer button (the footer uses a Spacer, so these can't be maxWidth-fill like buildActionBtn).
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
    @ViewBuilder private func buildColumnButton(_ label: String, active: Bool = false, fill: BuildFill = .none, action: (() -> Void)? = nil) -> some View {
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
        .contentShape(Rectangle())
        .onTapGesture { action?() }
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
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(armed ? Color.clear : buildEdge, lineWidth: 1))   // §0: armed keeps the cyan fill; idle mutes to a whisper
            .contentShape(Rectangle())
            .onTapGesture { buildVerb = armed ? nil : v }
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
        au?.setColourChain(cid, chain); refreshFromDocument(); buildStagingSyncIfPlaying()
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
                        buildPartButtons(cell: cell, hue: buildCyan, bands: [3, 2, 1, 1])
                        VStack(spacing: BuildGeom.cellGap) { buildLoopKeys(cell: cell); AnyView(buildPlayBands(cell: cell)) }
                        buildRightPartButtons(cell: cell, hue: buildCyan)
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

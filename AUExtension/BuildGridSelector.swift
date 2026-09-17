import SwiftUI

// THE GRID SELECTOR — the full-page 8x8 CHAIN BROWSER. Extracted from BuildPage.swift 2026-09-16
// (behaviour-preserving file split). Each cell = a complete MIDI chain drawn as its piano-roll
// fingerprint; tap auditions it live via the transient "gsAud" machine. See CLAUDE.md status.
extension DiagView {
    func buildGridSelCategoryTypes(_ c: Int) -> [ProcessorType] { roomsSelectCategories[max(0, min(roomsSelectCategories.count - 1, c))].types }

    // Recompute the CURRENT category's matching library indices (an entry matches if its chain contains the category's
    // processor). Called on a category change + when the library loads. Cheap O(lib) scan, cached in buildGridSelCatIndices.
    func buildGridSelRecomputeCategory() {
        let cats = buildGridSelCategoryTypes(buildGridSelPage)
        buildGridSelCatIndices = buildGridSelLib.indices.filter { i in buildGridSelLib[i].types.contains { cats.contains($0) } }
    }

    // Switch the SELECT grid to a new CATEGORY: stop the transient audition, drop cell-copy overrides + the selection,
    // set the category, recompute its matching library slice + the drifting faces.
    func buildGridSelSetPage(_ c: Int) {
        buildGridSelStopAudition()
        buildGridSelOverride = [:]; buildGridSelSel = nil
        buildGridSelName.removeAll()                                    // committed names are index-keyed → stale after a page remap (Paul 2026-09-12)
        buildGridSelLastSlot.removeAll()                                // page remaps index→chain → the last-viewed-slot memory is stale (Paul 2026-09-10)
        buildGridSelPage = c
        buildGridSelRecomputeCategory()
        buildGridSelComputeCellRolls()
    }

    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
    // THE GRID SELECTOR (AcceptanceCriteria-grid-selector.md, ratified 2026-08-22) — a full-page 8×8 where each cell is
    // a COMPLETE MIDI chain. Tap = audition it live against the current input (mutually-exclusive, quantized next-step,
    // the deployed piece plays on); the RIGHT column shows the selected chain read-only; COMMIT overwrites the ARRIVAL
    // row's chain (one undo), CANCEL restores. It rides the EXISTING chain-audition path (ddSolo + buildPublishScene)
    // on ONE reusable transient ephemeral machine, so the document is untouched until COMMIT (non-destructive by
    // construction). Banks v1: DEALT (Dice.rollEnsemble ×8 = 64 seeded chains, RE-DEAL) + MY LIBRARY (saved + factory
    // cells). FACTORY-as-a-curated-bank + EXCLUSIVE-OFF layering are deferred (flagged for Paul). The reel records every
    // audition for free (real emission). §6 governor: ordinary derivation, standing caps apply.
    var buildGridSelAudID: String { "gsAud" }   // the ONE reusable transient machine that carries the browsed chain

    // DEALT — 64 seeded, replay-safe chains (8 archetypes × 8 re-rolls). rollEnsemble runs the offline Router many times,
    // so generate OFF the main thread with a spinner (64 = 8× the grid-RANDOMIZE cost, too much to block on).
    func buildGridSelDeal() {
        // §3.1 THE PREGEN CORPUS: once the pool exists, DEAL is INSTANT — a seeded shuffle drawing 64 (RE-DEAL bumps the
        // seed → a fresh 64). While the corpus is still building, fall back to a fresh 64-roll so the first open isn't empty.
        buildGridSelLastSlot.removeAll()                                // a re-deal remaps index→chain → drop the last-viewed-slot memory (Paul 2026-09-10)
        // COMMITTED cells PERSIST across a re-deal (Paul 2026-09-12): their override pins the index, so DON'T clear
        // buildGridSelName here — the background corpus upgrade re-deals, and wiping names made committed cells revert by themselves.
        if !buildGridSelCorpus.isEmpty {
            var rng = DiceRNG(seed: buildGridSelDealSeed)
            buildGridSelDealt = Array(buildGridSelCorpus.shuffled(using: &rng).prefix(64))
            buildGridSelComputeCellRolls()                               // the drifting note faces for the freshly-dealt 64
            return
        }
        guard !buildGridSelGenerating else { return }                    // re-entrancy: one deal at a time (racing deals could land out of seed order)
        buildGridSelGenerating = true
        let seed = buildGridSelDealSeed
        runOnLargeStack {                                                // large stack: rollEnsemble runs the offline Router many times
            var rng = DiceRNG(seed: seed)
            var out: [Dice.EnsembleRow] = []
            for _ in 0..<8 { out.append(contentsOf: Dice.rollEnsemble(using: &rng)) }   // each call = 8 contrasting archetypes
            DispatchQueue.main.async { self.buildGridSelDealt = out; self.buildGridSelGenerating = false; self.buildGridSelComputeCellRolls() }
        }
    }

    // §3.1 build the corpus INCREMENTALLY on a low-priority background thread — a batch of 64 at a time, chaining until the
    // target, so it never blocks and DEAL upgrades to the richer pool after each batch (the "background queue tops it up").
    // Each batch is seeded by the offset ⇒ a stable, deterministic library per session (persisting to disk is a follow-up).
    func buildGridSelBuildCorpus() {
        let target = 256
        guard !buildGridSelCorpusBuilding, buildGridSelCorpus.count < target else { return }
        buildGridSelCorpusBuilding = true
        let have = buildGridSelCorpus.count
        runOnLargeStack(qos: .utility) {                                 // large stack: rollCorpus runs the offline Router many times
            var rng = DiceRNG(seed: 0xC0DE_5EED &+ UInt64(have))         // per-batch seed offset → deterministic, non-repeating
            let batch = Dice.rollCorpus(count: 64, using: &rng)
            DispatchQueue.main.async {
                self.buildGridSelCorpus.append(contentsOf: batch)
                self.buildGridSelCorpusBuilding = false
                if self.buildGridSelOpen { self.buildGridSelDeal() }     // upgrade the shown 64 to the growing pool
                if self.buildGridSelCorpus.count < target { self.buildGridSelBuildCorpus() }   // top up
            }
        }
    }

    // Resolve a cell's chain + register + hue. DEALT reads memory; MY LIBRARY loads the cell from disk (TAP/COMMIT only,
    // never per render — the cell FACE uses the cheap in-memory key hash instead).
    func buildGridSelChainAt(_ i: Int) -> (chain: [ProcessorSlot], transpose: Int, hex: UInt32)? {
        if let ov = buildGridSelOverride[i] { return (ov.chain, 0, ov.hex) }   // NEW INTERFACE: a cell-to-cell COPY instance wins over the bank (Paul 2026-08-28)
        if buildGridSelTab == 0 {
            guard i >= 0 && i < buildGridSelDealt.count else { return nil }
            let e = buildGridSelDealt[i]
            return (e.chain, e.transpose, machineHexes[((i % 8) * 2) % 16])
        } else {
            guard i >= 0 && i < buildGridSelCatIndices.count else { return nil }   // CATEGORY: grid position i → the i-th library entry in the current category
            let L = buildGridSelCatIndices[i]
            guard L >= 0 && L < buildGridSelLib.count else { return nil }
            let name = buildGridSelLib[L].name
            // Resolve by SECTION, not by name — a saved cell may share a factory cell's name (saved rows are [0, factoryFrom)).
            let cell = L >= buildGridSelLibFactoryFrom ? au?.factoryLibraryCell(name: name) : au?.loadLibraryCell(name: name)
            return (cell?.processors ?? [], 0, machineHexes[i % 16])       // hue position-based
        }
    }

    func buildGridSelPresent(_ i: Int) -> Bool { buildGridSelOverride[i] != nil || (buildGridSelTab == 0 ? i < buildGridSelDealt.count : i < buildGridSelCatIndices.count) }   // a cell-to-cell COPY makes an empty position present too (Paul 2026-08-28); library filtered by CATEGORY (2026-08-29)

    func buildGridSelCellHex(_ i: Int) -> UInt32 { buildGridSelOverride[i]?.hex ?? (buildGridSelTab == 0 ? machineHexes[((i % 8) * 2) % 16] : machineHexes[i % 16]) }

    // AUDITION — register the browsed chain on the ONE transient machine, select it, and drive the existing chain-voice
    // path: turn the chain voice ON (quantized) if not already, else swap which chain (quantized). Piece plays on.
    func buildGridSelAudition(_ i: Int) {
        guard let hit = buildGridSelChainAt(i) else { return }
        buildGridSelStampSourceRow = nil                                 // a library CELL is now the active source → clear the active side button (mutual exclusivity; no-op in old BUILD)
        buildGridSelLoadChain(hit.chain, transpose: hit.transpose, hex: hit.hex, sel: i)   // a DEALT/LIBRARY cell — its index is the commit source
    }

    // A select-grid TAP: SELECT MODE focuses the cell into the machine (no play/stop); else it auditions. (Paul 2026-08-31)
    func buildGridSelTapCell(_ i: Int) {
        guard buildGridSelPresent(i) else { return }
        // Paul 2026-09-05: a NEW select-grid cell after a PART promote starts with NULL I/O + all-8-pulsing (silent until wired).
        if buildPartJustPromoted { buildPartJustPromoted = false; buildIONullPending = true }
        if buildSelectMode { buildGridSelFocus(i); buildSelectMode = false } else { buildGridSelAudition(i) }   // SELECT ends after one pick (Paul 2026-08-31)
    }

    // FOCUS ONLY (SELECT mode): load the cell into the machine + select it, but DON'T start/swap the audition voice. (Paul 2026-08-31)
    func buildGridSelFocus(_ i: Int) {
        guard let hit = buildGridSelChainAt(i) else { return }
        buildGridSelStampSourceRow = nil
        buildGridSelLoadChain(hit.chain, transpose: hit.transpose, hex: hit.hex, sel: i, play: false)
    }

    func buildMostImpactfulSlot(_ chain: [ProcessorSlot]) -> Int? {
        var best: Int? = nil; var bestRank = Int.min
        for (i, s) in chain.enumerated() where !s.bypassed {
            let r = buildImpactRank(s.type)
            if r > bestRank { bestRank = r; best = i }                       // first slot wins ties → earliest-in-chain
        }
        return best
    }

    // Load a chain onto the ONE transient audition machine, select it, and drive the chain voice (quantized). Shared by a
    // cell audition (sel = the cell index → the commit source) and a ROW press (sel = nil → a view/hear of that part's chain).
    func buildGridSelLoadChain(_ raw: [ProcessorSlot], transpose: Int, hex: UInt32, sel: Int?, play: Bool = true) {
        if let prev = buildGridSelSel, prev != sel, let s = buildEditSlot { buildGridSelLastSlot[prev] = s }   // REMEMBER the last processor viewed on the cell we're leaving (Paul 2026-09-10)
        buildGridSelSel = sel
        buildGridSelActiveRoll = gridSelRollBars(raw)                     // the piano-roll shown on the cell + the right column
        // BAKE the register home into the CHAIN (a leading TRANSPOSE utility) rather than the ephemeral machine's transpose:
        // the chain is baked into the published scene + swapped atomically at the STEP boundary, whereas the machine's
        // transpose is re-resolved on every rebuild — so an ephemeral transpose would jump the still-sounding old chain a
        // step early on a quantized swap. This keeps the whole swap quantized. (transpose stays 0 on the transient machine.)
        var chain = raw
        if transpose != 0 { var t = ProcessorSlot(type: .transpose); t.params.utilTranspose = max(-24, min(24, transpose)); chain.insert(t, at: 0) }
        buildMachineReg[buildGridSelAudID] = chain
        machineHueOverride[buildGridSelAudID] = hex
        buildMachineTranspose[buildGridSelAudID] = 0
        buildSyncMachines()
        buildSelID = buildGridSelAudID; ddMachineSel = -1                  // ddSelectedMachineID now returns the transient
        // THE PROCESSOR CARD (Paul 2026-09-10): RETURNING to a cell re-opens the LAST processor viewed there; a first visit
        // defaults to the most impactful stage of the chain (arp/riff …) — either way the card lands on a processor, not the
        // empty invitation. (The stored slot is guarded against a chain that changed length under it.)
        if let s = sel, let last = buildGridSelLastSlot[s], last < chain.count { buildEditSlot = last }
        else { buildEditSlot = buildMostImpactfulSlot(chain) }
        buildAddSlot = nil; buildStageEye = false
        guard play else { return }                                        // FOCUS ONLY (SELECT mode): shown in the machine, voice untouched (Paul 2026-08-31)
        // QUANTIZE STEP mode was never wired (buildGridSelQuantStep hardwired false) → audition switching is always INSTANT.
        if !ddSolo {                                                       // chain voice OFF → turn it on
            buildPendingWorkshopVoice = nil; buildPendingReengage = false; buildSelectMachineVoice()
        } else {                                                          // already the voice → swap the chain
            buildPendingReengage = false; buildPublishScene()
        }
    }

    // Stop the transient audition but KEEP the browser open (tab-switch / RE-DEAL): silence the chain voice, reap the
    // transient, and re-select the pre-open machine so nothing is stranded. The deployed piece plays on.
    func buildGridSelStopAudition() {
        buildFerryMirrorRow = nil                                        // stop mirroring — the transient is being reaped
        guard buildGridSelSel != nil || ddSolo || buildPendingWorkshopVoice != nil || buildPendingReengage else { return }
        buildGridSelSel = nil; buildGridSelActiveRoll = []
        buildPendingWorkshopVoice = nil; buildPendingReengage = false
        buildMachineReg[buildGridSelAudID] = nil; machineHueOverride[buildGridSelAudID] = nil; buildMachineTranspose[buildGridSelAudID] = nil
        if buildVoiceOwner == .chain { buildVoiceOwner = .none }
        buildSelID = buildGridSelPriorSel; ddMachineSel = machineIDs.firstIndex(of: buildGridSelPriorSel ?? "") ?? -1
        au?.clearMachineSolo(); buildSyncMachines(); buildPublishScene()
    }

    // HOLD-TO-STAMP (Paul 2026-08-26): while a browse CELL auditions, HOLDING a part-row stamps the auditioning chain onto
    // that row — KEEPING the row's own machine — WITHOUT closing the browser (so you can stamp one machine onto several
    // parts). A populated row keeps its hue + register (chain overwritten); an empty row mints a machine carrying the chain.
    // The active STAMP SOURCE — one of two (mutually exclusive, "one thing is active"): a browse CELL
    // (buildGridSelSel, SELECT library) or an active SIDE BUTTON's populated part row (buildGridSelStampSourceRow).
    // This is what a long-press copy stamps. (Paul 2026-08-28)
    func buildGridSelStampSource() -> (chain: [ProcessorSlot], transpose: Int)? {
        // Resolve the three candidates from @State, then defer to the pure, unit-tested priority (roomsStampSource):
        // the live audition (gsAud) holds card EDITS — on SELECT BOTH a browse cell AND an aimed side button load + edit
        // it (buildSelID == gsAud), so it wins (register home baked → transpose 0). PART edits the REAL machine instead
        // (buildSelID != gsAud there → falls through to the browse cell / side row, which already reflects the edit).
        // (BUG 2026-08-29: the old code read buildGridSelChainAt/buildMachineChain = the ORIGINAL, dropping edits.)
        roomsStampSource(
            auditionEdited: buildSelID == buildGridSelAudID ? buildMachineReg[buildGridSelAudID] : nil,
            libraryCell: buildGridSelSel.flatMap { buildGridSelChainAt($0) }.map { ($0.chain, $0.transpose) },
            sideRow: buildGridSelStampSourceRow.flatMap { s in buildRowMachine(s).map { (buildMachineChain($0), buildMachineTranspose[$0] ?? 0) } })
    }

    @ViewBuilder func buildGridSelCell(_ i: Int, w: CGFloat, h: CGFloat, greyUnlessSel: Bool = false, vPad: CGFloat = 3) -> some View {
        let present = buildGridSelPresent(i)
        let hue = Color(hex: buildGridSelCellHex(i))
        let sel = buildGridSelSel == i
        // COMMITTED (Paul 2026-09-12): a cell that's been edited + named wears the SELECTED colour (not grey) + shows its hash
        // name — even when not the current audition. It overrides the grey-unless-selected treatment below.
        let committed = greyUnlessSel && buildGridSelName[i] != nil
        // greyUnlessSel (SELECT grid, Paul 2026-08-29): an unselected present cell is a DARK-GREY button with a LIGHT-GREY
        // piano roll; only the SELECTED cell wears its chain's machine + white roll. Else (old grid selector) = coloured.
        let unselGrey = greyUnlessSel && !sel && !committed
        // SELECT grid (greyUnlessSel): the PLAYING (selected) cell is ONE machine — the INVERSE of the unselected dark-grey
        // view (a LIGHT-grey button with a DARK roll), NOT the chain's own hue (Paul 2026-08-30). Non-SELECT grids keep the hue.
        let selGrey = greyUnlessSel && sel && !committed
        let fill = present ? (sel ? (selGrey ? buildSelectGrey : hue.opacity(0.85)) : (unselGrey ? Color(white: 0.16) : hue.opacity(0.42))) : Color.white.opacity(0.03)   // selGrey ALTERNATES two bright shades per selection (matches the machine box; Paul 2026-09-01)
        let rollTint: Color = selGrey ? Color(white: 0.22) : (unselGrey ? Color(white: 0.78) : .white)
        // TASTEFUL CHEQUER (Paul 2026-08-31): the SELECT grid reads as a BOARD — a faint two-tone parity wash on every
        // non-selected cell (the classic chessboard), subtle enough not to fight the roll. SELECT grid only (greyUnlessSel);
        // the bright selected/focus cell stays clean.
        let chequer = greyUnlessSel && !sel && !committed && ((i / 8 + i % 8) % 2 == 0)
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(fill)
            if chequer { RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)) }   // the lighter square of the board
            if present && !committed {   // the piano-roll face — shown UNTIL the cell is committed, then REPLACED by its name (Paul 2026-09-12)
                buildGridSelPianoRoll(sel ? buildGridSelActiveRoll : (buildGridSelCellRoll[i] ?? []), playing: sel, tint: rollTint, strikeIdx: sel ? (buildChainAuditionRow.map { [$0] } ?? []) : [])
                    .padding(.vertical, vPad).padding(.horizontal, 3).opacity(sel ? 1.0 : 0.7)   // SELECT grid pads the roll 15% top/bottom (Paul 2026-08-29)
            }
            if committed, let nm = buildGridSelName[i] {   // the generated hash name, REPLACING the roll on a committed cell (Paul 2026-09-12)
                Text(nm).font(.system(size: min(11, h * 0.4), weight: .heavy, design: .monospaced)).tracking(0.5)
                    .foregroundColor(.black.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3)
                    .shadow(color: .white.opacity(0.25), radius: 1)
            }
            if sel {       // THE ACTIVE CELL — a STATIC strong frame (Paul 2026-09-08: was a breathing strobe)
                RoundedRectangle(cornerRadius: 6).stroke(selGrey ? Color.black : Color.white, lineWidth: 3)
            }
            if buildSelectMode && present { RoundedRectangle(cornerRadius: 6).stroke(Color.white, lineWidth: 2.5) }   // SELECT MODE: every cell lights white — tap to focus (Paul 2026-08-31)
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .onTapGesture { buildGridSelTapCell(i) }   // SELECT mode focuses; else auditions
    }

    // THE SELECT-CELL PIANO ROLL (Paul 2026-08-31 — replaces the looping drift on the SELECT grid CELLS only; the ferries
    // keep buildGridSelDriftFace/buildNoteSweep). A PRECISE one-frame piano roll of the chain's real output (gridSelRollBars
    // = an offline render → each note's start · LENGTH (x0→x1 = bar width) · PITCH lane · VELOCITY (opacity)). STATIC at the
    // real note positions when idle; when the cell is auditioning it SCROLLS LEFT→RIGHT, beat-locked to the music (the same
    // extrapolated beat the cell playheads use). Same machine scheme (the caller's `tint`).
    @ViewBuilder func buildGridSelPianoRoll(_ bars: [GridSelBar], playing: Bool, tint: Color, strikeIdx: [Int] = []) -> some View {
        buildOutputFace(bars, tint: tint, playing: playing, strikeIdx: strikeIdx)   // SELECT face = the unified expected-output constellation (Paul 2026-09-05 v2)
    }

    // THE DRIFTING NOTE FACE (Paul 2026-08-26): notes scroll RIGHT→LEFT, looping — the same aesthetic as the part/play grid
    // cells (buildNoteSweep). Every present cell + row selector wears its chain's fingerprint drifting across it (a browse
    // preview: you can't run 64 live voices, so each cell loops its chain's note pattern). Opacity by velocity.
    @ViewBuilder func buildGridSelDriftFace(_ bars: [GridSelBar], animated: Bool, period: Double = 2.4, tint: Color = .white) -> some View {
        buildOutputFace(bars, tint: tint, playing: animated)   // Paul 2026-09-05 v2: the row selectors wear the SAME constellation as the cells (was drifting bars)
    }

    // Compute the drifting-note fingerprint for every present cell of the CURRENT tab, off the main thread (64× gridSelRollBars
    // is too much to block on — the same reason DEAL is backgrounded). A generation token discards a batch if the deal/tab
    // changed under it. Chains are gathered on the main thread first (library resolves via `au`), then bars computed pure.
    func buildGridSelComputeCellRolls() {
        buildGridSelRollGen &+= 1
        let gen = buildGridSelRollGen
        var chains: [(Int, [ProcessorSlot])] = []
        for i in 0..<64 where buildGridSelPresent(i) { if let hit = buildGridSelChainAt(i) { chains.append((i, hit.chain)) } }
        // Paul 2026-09-05: do NOT clear the cache here — keep the old faces until the new ones are ready, else every cell
        // blanks in the async gap ("goes blank then redraws"). The gen guard + full-dict swap below replace them atomically.
        runOnLargeStack {                                                // large stack: gridSelRollBars → Dice.runRecorder (deep Router eval) ×64
            var out: [Int: [GridSelBar]] = [:]
            for (i, chain) in chains { out[i] = gridSelRollBars(chain) }
            DispatchQueue.main.async { if self.buildGridSelRollGen == gen { self.buildGridSelCellRoll = out } }
        }
    }

    // buildGridSelStampPressing / buildGridSelStampFire / buildGridSelStampSweep (the ferry+rail long-press copy gesture,
    // its rising-fill + commit-bloom animation) are RETIRED (Paul 2026-09-12) — superseded by ferry drag-and-drop.
    func buildGridSelAimRow(_ n: Int) {
        buildGridSelArrivalRow = n
        buildSelReceiver = buildRowReceiverResolved(n)                    // the audition plays through the AIMED part's door + emitters (so the MIDI-IN/OUT chips reflect it)
        buildPartEmitters = buildRowEmittersResolved(n)
        receivers = au?.uiReceivers() ?? receivers
        // LOAD the pressed part's own chain into the MIDI CHAIN panel + audition it (Paul 2026-08-26). sel = nil → it's a
        // view/hear of what's on the row, not a commit source (re-deal or tap a cell to change it). Empty row → clear.
        if let cid = buildRowMachine(n) {
            buildFerryMirrorRow = n                                       // a POPULATED ferry aim MIRRORS this row: card edits on gsAud write straight back to it (Paul 2026-08-30)
            buildGridSelLoadChain(buildMachineChain(cid), transpose: buildMachineTranspose[cid] ?? 0, hex: buildBaseHex(cid), sel: nil)
        } else {
            buildFerryMirrorRow = nil                                     // empty row → no mirror target
            buildGridSelStopAudition()                                    // empty part → nothing to load; silence the transient
        }
    }
}

// One note of a GRID SELECTOR chain's piano-roll fingerprint — normalized 0…1 (x = time, y = pitch, w = gate).
struct GridSelBar: Equatable { let x0: Double; let x1: Double; let y: Double; let vel: Double }

// The piano-roll fingerprint of a chain: an OFFLINE render (Dice.runRecorder vs a standard chord) → its emitter-A notes
// as normalized bars. Pure + Foundation-only, so it runs off the main thread during a deal. Empty for a silent chain.
func gridSelRollBars(_ chain: [ProcessorSlot]) -> [GridSelBar] {
    let rec = Dice.runRecorder(chain)
    let ons = rec.ons.filter { $0.cable == 1 }
    guard !ons.isEmpty else { return [] }
    let notes = ons.map { Int($0.note) }
    let lo = notes.min()!, hi = notes.max()!, span = max(1, hi - lo)
    let maxS = Double(max(Int64(1), max(ons.map { $0.sample }.max() ?? 1, rec.offs.map { $0.sample }.max() ?? 1)))
    var bars: [GridSelBar] = []
    for on in ons {
        let off = rec.offs.filter { $0.cable == 1 && $0.note == on.note && $0.sample >= on.sample }.map { $0.sample }.min()
        let x0 = Double(on.sample) / maxS
        let x1 = off.map { Double($0) / maxS } ?? min(1.0, x0 + 0.05)
        bars.append(GridSelBar(x0: x0, x1: max(x0 + 0.02, min(1.0, x1)), y: 1.0 - Double(Int(on.note) - lo) / Double(span), vel: Double(on.vel) / 127.0))
    }
    return bars
}

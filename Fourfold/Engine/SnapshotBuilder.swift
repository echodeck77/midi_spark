//  SnapshotBuilder.swift
//  MidiSpark — document → SnapshotBox, on the UI thread (spec v2.8 §7).
//  The builder resolves everything the render thread must never compute:
//  Optional → concrete params, enum → index mapping, LEGATO run starts. (The A/B morph layer is gone — paramsB is decode-only.)

import Foundation

enum SnapshotBuilder {

    /// Copy a MachineParams' CHORDS config into a SnapParams (the resolved snapshot form). ONE source of truth, SHARED by the
    /// processor's per-cell build AND the chord DOOR's per-door build — so a future `chords*` field reflects on both. (Paul 2026-09-04)
    static func applyChords(_ p: MachineParams, into out: inout SnapParams) {
        if let v = p.chordsMode { out.chordsMode = v }
        let cSteps = p.chordsStepsResolved
        out.chordsSteps = cSteps
        out.chordsDegrees = p.chordsDegreesResolved(steps: cSteps).map { clamp($0, -1, 7) }   // sized to the matrix width so cols 8–15 of a wide matrix play (Paul 2026-09-16)
        out.chordsVoicing = p.chordsVoicingResolved
        out.chordsSpread = p.chordsSpreadResolved
        if let v = p.chordsRotate { out.chordsRotate = ((v % cSteps) + cSteps) % cSteps }   // rotate strides the FULL matrix (was mod 8, capping rotate on a 16-wide matrix)
        if let v = p.chordsWalkSeed { out.chordsWalkSeed = v }
        out.chordsRateBeats = p.chordsRateResolved.beats
    }

    static func build(from doc: PluginState, generation: UInt64 = 0, hues: [String: UInt32] = [:]) -> SnapshotBox {
        let scene = doc.activeSceneState   // MULTI-SCENE: bounds-safe active scene (never an out-of-range crash)

        // ---- machines: resolve each Machine's single (A) param bag + its ON assignments (the A/B morph layer was
        //      removed — SnapMachine no longer carries b/tier/morph; paramsB/typeB stay decode-only legacy keys). ----
        // The machine array sizes to the DOCUMENT (≥16), so BUILD's ephemeral machines appended by renderDoc() render
        // too — the 16-slot cap is lifted. Cells look up their machine BY ID here (not the fixed global machineIDs), so
        // any appended machine resolves. Behaviour-identical for a plain 16-machine document. (Paul 2026-08-15)
        var machines = [SnapMachine](repeating: SnapMachine(), count: max(Snap.machines, doc.machines.count))
        var machineIndexByID: [String: Int] = [:]
        for (i, machine) in doc.machines.enumerated() {
            var sc = SnapMachine()
            sc.transpose = Int8(max(-24, min(24, machine.transpose)))   // the active type's transpose
            sc.on = machine.onResolved   // delta §9 item 1: carry the ON assignments to the render (nil → unassigned)
            sc.a = resolve(machine.paramsA, type: machine.type, fallback: nil)   // morph removed: the one param bag (A)
            sc.hue = hues[machine.machineID] ?? 0   // DISPLAY hue (packed RGB) for the reel's machine-by-cell roll; 0 ⇒ UI falls back
            machines[i] = sc
            machineIndexByID[machine.machineID] = i
        }

        // ---- cells ----
        let ladderOn = doc.ladderModeResolved                       // LADDER: exclusive columns (resolved here so render stays LADDER-unaware)
        var cells = [SnapCell](repeating: SnapCell(), count: Snap.maxCols * Snap.rows)   // §E: allocate the full 16-col storage (col 8–15 stay empty until a part is 16-wide → byte-identical)
        for c in 0..<Snap.maxCols {
            let ladderActive = ladderOn ? scene.ladderActiveRow(c) : nil   // the one speaking rung this column (topmost-occupied default)
            for r in 0..<Snap.rows {
                guard c < scene.cells.count, r < scene.cells[c].count,
                      let cell = scene.cells[c][r],
                      let machineIndex = machineIndexByID[cell.machineID] else { continue }   // resolve by the DOCUMENT-order index (correct-by-construction); the old canonical-first lookup read the wrong SnapMachine if machines were ever reordered (Paul 2026-08-16)
                var sc = SnapCell()
                sc.machineIndex = Int16(machineIndex)   // CR-13a: Int16 — a document machine index can exceed 127 (Int8 trapped)
                sc.alt = cell.alt
                // CELL MACHINE (feat/EditPageSpike): resolve the HEAD treatment — the FIRST chain slot's
                // type+params, else the referenced Machine's A face (already resolved into machines[machineIndex].a,
                // canonically ordered by machineIDs like the render's box.machines[ci]). `bypassed` carries the head
                // slot's bypass in the chain case (identity), or the legacy cell.bypassed in the fallback case.
                // CELL MACHINE stage-3: 3-tier resolution — per-cell OVERRIDE → machine TEMPLATE → legacy A face.
                // MODE ROW: an EXPLICIT empty chain (`processors == []`, a newborn) is a PASSTHROUGH — the held
                // source flows through untreated. It renders as a single BYPASSED identity slot (true-bypass =
                // source-only hold-tail), which the engine already handles; nil still means "follow the template".
                let override = cell.processors.flatMap { $0.isEmpty ? nil : $0 }
                let template = (machineIndex < doc.machines.count ? doc.machines[machineIndex].templateChain : nil).flatMap { $0.isEmpty ? nil : $0 }
                if cell.processors?.isEmpty == true {
                    markPassthrough(&sc)                  // EXPLICIT empty chain → source-only hold-tail (bypassed identity slot)
                } else if let chain = override ?? template, !chain.allSatisfy({ $0.bypassed }) {
                    sc.procs = chain.map { resolve($0.params, type: $0.type, fallback: nil) }
                    sc.slotBypass = chain.map { $0.bypassed }
                    sc.bypassed = chain[0].bypassed
                } else if override != nil || template != nil {
                    // BUG FIX (2026-08-05, Paul on device): a chain whose slots are ALL bypassed ≡ an EMPTY chain
                    // → the born-audible identity passthrough (the source plays untreated), ONE rule. Collapsing
                    // here means the Router keeps a single hold-tail path instead of relying on the fragile,
                    // count-dependent `cell.bypassed` / `isHoldTailChain` classifiers agreeing for every depth.
                    markPassthrough(&sc)                  // all-bypassed chain ≡ empty ⇒ the same one passthrough rule
                } else {
                    sc.procs = [machines[machineIndex].a]   // legacy: 1-slot head = the Machine's A face
                    sc.slotBypass = [cell.bypassed]
                    sc.bypassed = cell.bypassed
                }
                sc.muted = cell.muted
                sc.dormant = ladderOn && r != (ladderActive ?? -1)   // LADDER: non-active rungs are silent (visible + dimmed in the UI)
                sc.busMask = busBitmask(cell.buses)
                // PER-LANE I/O (Paul 2026-10-08, the new I/O tab): each of Euclideous's 4 lanes independently
                // resolves MIDI IN / KEY / CHORDS via its own EuclidLine.sourceModeResolved — resolved HERE,
                // post-hoc, since `resolve()` (which built sc.procs above, including each line's sourceMode)
                // is a context-free MachineParams→SnapParams mapper with no doc.receivers access.
                //
                // MIDI IN = OMNI across the WHOLE live pool, unconditionally — NOT one specific receiver index
                // (Paul 2026-10-09, 2nd report: "midi in does nothing"). This file previously hardcoded receiver
                // index 3 ("receiver 4") — my own unverified reading of the design spec's prose ordering during
                // planning, FLAGGED AT THE TIME as an assumption needing confirmation, never actually confirmed.
                // That guess silently mismatched whatever receiver Paul actually routes his controller into — and
                // per this file's own factory-rig convention (`Receiver.defaultChordSeqs`'s neighbouring doc:
                // "D → SCALE door... C → CHORD door"), receiver D/index 3 is typically ALREADY CLAIMED by a
                // self-arming SCALE door, not free for a user's live MIDI at all — which is exactly how the
                // FIRST report happened ("plays something even with nothing plumbed in": a self-arming door's
                // synthesized content leaking through `effectivePool`'s substitution) and, once that leak was
                // fixed to read genuinely-live input instead (Router.swift's `livePool`, not the substituted
                // `pool`), why it then went silent (no real MIDI controller was ever plugged into THAT specific
                // receiver to begin with). Rather than guess a THIRD specific index, MIDI IN now means exactly
                // what it says: any live note reaching the plugin, full stop — independent of this document's
                // receiver/door graph entirely, matching Euclideous's own standing design as a self-contained
                // instrument page (this file's own top-of-file comment). CHORDS and KEY need no receiver mask
                // at all — CHORDS reads Euclideous's own on-page chord generator (resolved below, into the
                // shared chords* fields); KEY reads a scale pool DERIVED from that same page-level KEY picker
                // (Router.swift's `.key` branch, fixed the same day this comment was written — see its own
                // note there for why it was previously silent).
                if r == Snap.euclideousRow, !sc.procs.isEmpty {
                    sc.procs[0].euclideousNoteSourceResolved = doc.euclideousNoteSourceResolved   // kept for diagnostics; the stacked pool reads the plan below
                    // SOURCES STACK ferry (2026-10-26): the stacking plan + the dev-only clash policy.
                    sc.procs[0].euclideousSourcePlan = doc.sourcePlanResolved
                    sc.procs[0].euclideousClashPolicy = doc.clashPolicyResolved
                    // SOURCES STACK: MIDI IN ALWAYS LISTENS now — the LISTEN ON mask is passed unconditionally (not
                    // gated to a `.midi` source), and HOLD/LATCH applies whenever MIDI contributes. Byte-identical for
                    // every existing document because the golden harness feeds no MIDI (an empty live pool contributes
                    // nothing regardless of the mask); the pre-ferry `== .midi ? … : 0`/`nil` gates are gone.
                    sc.procs[0].globalSrcChanMask = doc.euclideousMidiInChannelMaskResolved
                    sc.procs[0].globalSrcChanMaskSet = true
                    sc.procs[0].euclideousHoldLatchMode = doc.euclideousHoldLatchMode
                }
                // RESET SPAN (Paul 2026-10-08, §2.2): a SEPARATE, independent guard from the block above — this
                // has nothing to do with receivers, so it must not be skipped just because none are configured.
                if r == Snap.euclideousRow, !sc.procs.isEmpty {
                    sc.procs[0].euclideousResetSpanBars = doc.euclideousResetSpanBarsResolved
                }
                // SEQUENCER PANEL (2026-10-14 ferry) — a THIRD such guard, same shape as the RESET SPAN one
                // directly above: a page-level PluginState global reaching Euclideous's one cell's SnapParams
                // with NO MachineParams hop at all — genuinely page-level-only concepts (ON/RATE/LEN/cells
                // for either sequencer), unlike `euclideousRiffs`/`activeRiff` (moved to the per-machine
                // resolve below, a few hundred lines down — those need the SAME `MachineParams`-routed path
                // the OLDER singular `euclideousRiff` field already uses, confirmed the hard way: every
                // pre-existing RouterTest configures a Euclideous fixture via `c.paramsA.euclideousRiff =`,
                // not a PluginState-level field, and `BuildPage.swift`'s own publish path builds the
                // Euclideous cell's MachineParams fresh from live @State every time — a row-gated PluginState
                // read would silently never see what either of those actually populate).
                if r == Snap.euclideousRow, !sc.procs.isEmpty {
                    sc.procs[0].euclideousFX = doc.euclideousFXResolved   // FX TAB (2026-10-18): page-level, no MachineParams hop — same shape as the sequencer fields below
                    sc.procs[0].hocketRules = HocketRulesSnap(rules: doc.hocketRulesResolved)   // HOCKET (2026-10-27): page-level, no MachineParams hop — fixed-size value data for the render thread
                    sc.procs[0].emitterRatchets = EmitterRatchetSnap(doc.euclideousEmitterRatchetsResolved)   // EMITTER RATCHET (2026-10-28): page-level, no MachineParams hop; the Euclid masks are built here, on the main thread
                    sc.procs[0].euclideousLanesSeqOn = doc.euclideousLanesSeqOnResolved
                    sc.procs[0].euclideousLanesSeqRate = doc.euclideousLanesSeqRateResolved
                    sc.procs[0].euclideousLanesSeqLen = doc.euclideousLanesSeqLenResolved
                    sc.procs[0].euclideousLanesSeqCells = doc.euclideousLanesSeqCellsResolved
                    sc.procs[0].euclideousRiffsSeqOn = doc.euclideousRiffsSeqOnResolved
                    sc.procs[0].euclideousRiffsSeqRate = doc.euclideousRiffsSeqRateResolved
                    sc.procs[0].euclideousRiffsSeqLen = doc.euclideousRiffsSeqLenResolved
                    sc.procs[0].euclideousRiffsSeqCells = doc.euclideousRiffsSeqCellsResolved
                }
                // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry), Presets rule 1's own "any
                // other value: 1 lit, and logged" — the ONE place this warning may actually fire: once per
                // `build()`, main-thread-only (RENDER-THREAD SAFETY, per `EuclidLine.litMigrationNeedsWarning`'s
                // own doc comment — that property is pure, no I/O; this is the one and only call site that
                // turns a true result into the actual log line, mirroring the pre-existing `euclideousNote-
                // SourceResolved` warning precedent a few lines above, which is likewise PluginState-level and
                // main-thread-only, never embedded on the render path the way `EuclidLine` itself is).
                if r == Snap.euclideousRow {
                    for (i, L) in doc.euclideousLinesResolved.enumerated() where L.litMigrationNeedsWarning {
                        FileHandle.standardError.write("Fourfold: Euclideous lane \(i + 1) had an unexpected legacy noteSel — migrating to 1 lit\n".data(using: .utf8) ?? Data())
                    }
                }
                // EUCLIDEOUS CHORDS (Paul 2026-10-08; CHORDS GRID ferry 2026-10-24 repointed this at the ACTIVE
                // of 4 progressions): resolve the page's own chord grid into the SHARED chords* fields (see
                // Snapshot.swift's own doc comment on euclideousChordKeyRoot/KeyTones for why reusing them, not
                // a parallel set, is the right call) — PATTERN mode only, unconditionally (there's no MODE
                // picker on this page; the popup only ever authors PATTERN-shaped content). keyRoot/keyTones
                // come from Euclideous's own page-level KEY, not a receiver door.
                if r == Snap.euclideousRow, !sc.procs.isEmpty {
                    let chordCfg = doc.euclideousChordSetsResolved[doc.activeChordSetResolved]
                    let steps = chordCfg.chordsStepsResolved
                    sc.procs[0].chordsMode = .pattern
                    sc.procs[0].chordsDegrees = chordCfg.chordsDegreesResolved(steps: steps)
                    sc.procs[0].chordsColours = Array(chordCfg.chordsColoursResolved16().prefix(steps))
                    sc.procs[0].chordsSteps = steps
                    sc.procs[0].chordsRateBeats = max(0.03125, chordCfg.chordsRateResolved.beats)
                    sc.procs[0].chordsRotate = chordCfg.chordsRotate ?? 0
                    sc.procs[0].chordsVoicing = chordCfg.chordsVoicingResolved
                    sc.procs[0].chordsSpread = chordCfg.chordsSpreadResolved
                    sc.procs[0].euclideousChordKeyRoot = doc.euclideousKeyRootResolved
                    sc.procs[0].euclideousChordKeyTones = doc.euclideousKeyTypeResolved.intervals
                }
                sc.chordSplit = cell.chordSplitResolved         // §cell-edit D: the source-note split (ALL default)
                let vw = cell.velWindowResolved                 // §cell-edit D: the velocity window (1…127 default)
                sc.velFloor = UInt8(max(1, min(127, vw.floor)))
                sc.velCeil = max(sc.velFloor, UInt8(max(1, min(127, vw.ceil))))   // CR-18[extra]: order the bounds — an inverted decoded/library window (ceil < floor) would otherwise mute the cell (SPLIT's splitVel + RACK FENCE both guard theirs)
                let chp = cell.chopResolved                      // §cell-edit F: per-slice output chop (independent main/alt/mute)
                sc.chopMain = chp.mainMask; sc.chopAlt = chp.altMask; sc.chopMute = chp.muteMask
                sc.chopAltMask = busBitmask(chp.altDest)
                sc.chopActive = chp.mainMask != 0xFF || chp.altMask != 0 || chp.muteMask != 0
                // CELL MACHINE (grid-chaining retired): a cell is always MIDI-IN — resolvedParent stays −1.
                // `cell.inputRow` is RENDER-inert (grid-chaining retired) but IDENTITY-LIVE — it still feeds SealKey; don't delete it.
                // delta §9 item 11: a MIDI-IN cell's source filter comes from the RECEIVER it subscribes
                // to (channel, or match-nothing if the receiver is muted); with no receivers (or a row
                // ref) fall back to the legacy per-cell filter. resolvedReceiver drives the UI band later.
                if let recs = doc.receivers, let ri = cell.inputReceiver, ri >= 0, ri < recs.count {
                    sc.resolvedReceiver = Int8(ri)
                    // EUCLIDEOUS PAGE REWORK (2026-10-07): the lanes' own note-picking source is a GLOBAL
                    // KEY|MIDI switch, not this cell's own receiver filter being muted — when KEY is chosen
                    // (and §4.4's key-to-rank mapping is undecided), silence this cell's pool the SAME way an
                    // actually-muted receiver already does, rather than inventing a second sentinel.
                    let euclideousLanesKeyMode = r == Snap.euclideousRow && !doc.euclideousLanesSourceMidiResolved
                    sc.inputChannel = (recs[ri].muted || euclideousLanesKeyMode) ? Snap.mutedSourceFilter
                                                     : UInt8(max(0, min(16, recs[ri].channel)))
                    sc.inputChanMask = (recs[ri].muted || euclideousLanesKeyMode) ? 0 : recs[ri].channelMaskResolved   // MULTI-CHANNEL: the door's channel subset (0 = muted → nothing)
                    sc.inputCableMask = 0b1111   // COG SIMPLIFICATION (2026-08-03): always accept ALL input cables (union) — cables retired from the UI
                    sc.inputRangeLo = recs[ri].rangeLoResolved   // RANGE (§2): the door's note window, admitted before the split/vel window
                    sc.inputRangeHi = recs[ri].rangeHiResolved
                } else {
                    sc.inputChannel = UInt8(max(0, min(16, cell.inputChannel)))   // legacy / no receivers
                    let f = sc.inputChannel; sc.inputChanMask = f == 0 ? 0xFFFF : (f >= 1 && f <= 16 ? (UInt16(1) << UInt16(f - 1)) : 0)
                }
                cells[c * Snap.rows + r] = sc
            }
        }

        // ---- LEGATO run starts (§3.5/§7 v2.4): same machine + same ROW + contiguous COLUMNS.
        //      Wiring/perform state irrelevant to run identity (§1.1); computed for every cell. A LADDER-DORMANT
        //      rung breaks the run (like an empty cell) — otherwise a full-8×8 ladder reads as one long run from
        //      column 0, and each active rung's legato arp arrives badly phase-advanced (plays mid/end of its cycle).
        for r in 0..<Snap.rows {
            var runStart = -1
            var runMachine: Int16 = -1   // CR-13a: SnapCell.machineIndex is Int16 (a doc machine index can exceed 127)
            for c in 0..<Snap.maxCols {
                let idx = c * Snap.rows + r
                let ci = cells[idx].machineIndex
                if ci >= 0 && !cells[idx].dormant {
                    if ci != runMachine { runStart = c; runMachine = ci }
                    cells[idx].runStartColumn = Int8(runStart)
                } else {
                    runStart = -1; runMachine = -1
                }
            }
        }

        // v3.0 (delta §7): per-bus stamp channels A–D, clamped 1–16, defaulted if the doc is short.
        var busCh = [UInt8](repeating: 0, count: FourfoldPorts.outputCount)
        let busChResolved = doc.busChannelsResolved   // CR-8: nil/short-safe (busChannels is now Optional); CARD BACKS: one per output A–D
        for i in 0..<FourfoldPorts.outputCount {
            busCh[i] = UInt8(max(1, min(16, busChResolved[i])))
        }
        // The ONE passthrough rule: a bypassed identity slot = the source plays untreated as a hold-tail. LEGATO
        // (Paul 2026-08-23): a chain with NO machines just PASSES THROUGH — the held note is struck once and SUSTAINED
        // (adopted across columns) rather than re-struck every step. (A .retrig identity re-attacked the chord at each
        // column boundary = "why does it restrike?".) emitColumnHolds sustains an identity only when its phase == .legato.
        func markPassthrough(_ sc: inout SnapCell) { var sp = SnapParams(); sp.phase = .legato; sc.procs = [sp]; sc.slotBypass = [true]; sc.bypassed = true; sc.passthrough = true }
        // PER-PART CLOCK (Paul 2026-08-19): resolve each row's step + loop length from the scene's per-row overrides
        // (nil ⇒ the scene default / a full 8 → uniform = today).
        let rowStepBeats: [Double] = (0..<Snap.rows).map { r in
            (scene.rowStepRate.flatMap { arr -> StepRate? in r < arr.count ? arr[r] : nil })?.beats ?? scene.stepRate.beats
        }
        let rowLenResolved: [Int] = (0..<Snap.rows).map { r in
            (scene.rowLen.flatMap { arr -> Int? in r < arr.count ? arr[r] : nil }).map { max(1, min(Snap.maxCols, $0)) } ?? Snap.cols   // CLAMP allows 16; UNSET ⇒ the 8-wide default (byte-identical)
        }
        // PER-ROW LAP (Paul 2026-08-19): pass the per-row loop mask through when the scene set one (BUILD's two grids),
        // else empty ⇒ the render uses the ephemeral global lap for every row (GRID tab, byte-identical).
        let rowLaneResolved: [UInt16] = (scene.rowLane?.count == Snap.rows) ? scene.rowLane! : []
        // PLAY-FERRY LAUNCH (Paul 2026-09-09): per-engine-row launch anchor (0 ⇒ no anchor). Empty on any doc without one → byte-identical.
        let rowLaunchAnchorResolved: [Double] = (scene.rowLaunchAnchor?.count == Snap.rows) ? scene.rowLaunchAnchor! : []

        return SnapshotBox(generation: generation,
                           stepBeats: scene.stepRate.beats,
                           swing: Double(max(50, min(75, scene.swing))),
                           machines: machines,
                           cells: cells,
                           busChannels: busCh,
                           busEnabledMask: 0xFF,   // every part is always on (the per-output enable was an emitter toggle, retired 2026-10-26)
                           ignoreAllNotesOff: doc.ignoreAllNotesOffResolved,
                           rowStepBeats: rowStepBeats, rowLen: rowLenResolved, rowLaneMask: rowLaneResolved,
                           rowLaunchAnchor: rowLaunchAnchorResolved)
    }

    // Map document params → flat indices. `fallback` = A-state for sparse-B inheritance.
    private static func resolve(_ p: MachineParams, type: ProcessorType, fallback: SnapParams?) -> SnapParams {
        var out = fallback ?? SnapParams()
        out.type = type
        if let v = p.octaves { out.octaves = UInt8(clamp(v, 1, 4)) }
        if let v = p.gate { out.gate = clamp(v, 0.05, 1) }
        if let v = p.phase { out.phase = v }
        if let v = p.count { out.count = UInt8(clamp(v, 2, 16)) }   // CR-6: BURST reads up to 16 (Router min(16,·)); RATCHET re-snaps ≤8 via effectiveRepeats, so widening the clamp only unlocks BURST's HITS 12/16 (were both silently = 8)
        if let v = p.ramp { out.ramp = clamp(v, 0, 1) }
        if let v = p.spread { out.spread = clamp(v, 0, 1) }
        if let v = p.destSlices { out.destSlices = v.map { clamp($0, -1, 3) } }   // DEST MATRIX (Paul 2026-08-22 §5): −1 = NONE (Paul 2026-09-26)
        if let v = p.destRate { out.destRateBeats = max(0.03125, v.beats) }       // DEST's OWN CLOCK (Paul 2026-09-26)
        out.dealE1 = clamp(p.dealE1 ?? 0, 0, 3); out.dealE2 = clamp(p.dealE2 ?? 1, 0, 3)   // DEAL (Paul 2026-09-16)
        out.dealN1 = max(1, min(16, p.dealN1 ?? 1)); out.dealN2 = max(1, min(16, p.dealN2 ?? 1))
        if let v = p.dealMode { out.dealMode = v }
        // RECORDER (AcceptanceCriteria-recorder, 2026-09-18): resolve config + carry the persisted buffer.
        // CLOCK (Paul 2026-09-26; FIXED/WAVE removed same day): only the DRAWN lane resolves now.
        if let v = p.clockSpanN { out.clockSpanN = v }
        // DRAWN (Stage 2): resolve the lane ONCE here — carries −1/empty columns forward into real ratio VALUES
        // (clockDrawnResolveRatios), so the render side (Router.clockTransformedBeat) never re-maps or allocates.
        out.clockDrawnSteps = clamp(p.clockDrawnSteps ?? 8, 1, 32)
        out.clockDrawnGlide = (0..<out.clockDrawnSteps).map { i in (p.clockDrawnGlide?.count ?? 0) > i ? p.clockDrawnGlide![i] : false }
        out.clockDrawnRatios = clockDrawnResolveRatios(p.clockDrawnRatios ?? [], steps: out.clockDrawnSteps)
        // KILL STEP (Paul 2026-09-26; MUTE/PAUSE added 2026-09-27): resolve the per-step MODE row ONCE here —
        // short/missing entries default to ON (an untouched row is a true no-op) — then precompute the transform
        // TABLE the render side reads (Router.killStepPhase/…Inverse), so no re-derivation happens on the render
        // path. Prefer the new killStepMode; else migrate the legacy killStepEnabled bool row (true→ON, false→DROP,
        // byte-identical to what shipped before this); else all ON.
        out.killStepCount = clamp(p.killStepCount ?? 8, 1, 32)
        let ksModes: [KillStepMode]
        if let m = p.killStepMode, !m.isEmpty {
            ksModes = (0..<out.killStepCount).map { i in i < m.count ? m[i] : .on }
        } else if let e = p.killStepEnabled, !e.isEmpty {
            ksModes = (0..<out.killStepCount).map { i in (i < e.count ? e[i] : true) ? .on : .drop }
        } else {
            ksModes = Array(repeating: .on, count: out.killStepCount)
        }
        // The TABLE (shared with GridUI's live-playhead preview via killStepResolveTable, Derivations.swift, so the
        // two can never independently drift): walk the non-DROP steps in order; a PAUSE step repeats its own index
        // (1 + pauseLen) times, so downstream's local clock reads the SAME value across every real column of the
        // hold (a true freeze). ON and MUTE both consume exactly one column each — MUTE affects only whether a note
        // SOUNDS (a separate fold, Router.emitDriverNote), never this table. When no step is MUTE/PAUSE this reduces
        // to EXACTLY today's onIdx/k — same length, same contents, same order.
        if let v = p.killStepRate { out.killStepRateBeats = max(0.03125, v.beats) }
        if let v = p.killStepSpanN { out.killStepSpanN = v }
        if let v = p.muteSlices { out.muteSlices = v.map { clamp($0, 0, 15) } }   // MUTE MATRIX (Paul 2026-08-25 §5): 4-bit muted-emitter mask per slice
        // RIFF (SPEC-riff-processor): resolve the stencil. riffRanks nil ⇒ keeps the default figure. rate → beats.
        if let v = p.riffRanks { out.riffRanks = v.map { clamp($0, 0, 8) } }
        if let v = p.riffDir { out.riffDir = v }
        if let v = p.riffDirSeed { out.riffDirSeed = UInt64(bitPattern: Int64(v)) }   // RANDOM/DRUNK shared seed (mirrors arpSeed, line 566)
        if let v = p.riffDirBias { out.riffDirBias = clamp(v, -1, 1) }                // DRUNK bias
        // HOCKET (AcceptanceCriteria-hocket-processor, v1): the wire-listening driver.
        // AVOID / LOCK (unified 2026-08-31): the per-note pitch filter.
        // TAP (AcceptanceCriteria-tap-processor): the mid-chain send.
        SnapshotBuilder.applyChords(p, into: &out)   // CHORDS (ratified 2026-09-01) — SHARED with the chord DOOR (below)
        // COIN — SHAPING THE DICE (Paul 2026-08-26): weights kept only if any is >0 (else EMPTY ⇒ LO/HI fallback, byte-identical)
        // VELOCITY (Paul 2026-09-07): per-step override lane + passthrough flags, padded to 32; clamps mirror the rtc PATTERN copy.
        // EUCLID MASK, standalone processor: the same resolve shape (Bjorklund K-of-N), no WALK.
        out.maskN = max(1, min(64, p.maskN ?? 8))
        out.maskK = max(1, min(out.maskN, p.maskK ?? out.maskN))
        // EUCLID MASK options (Paul 2026-09-28): all additive-Optional, nil ⇒ today's exact behaviour.
        if let v = p.harmIntervals {
        }
        // ECHO (user 2026-08-08)
        if let v = p.euclidPulsesFromPool { out.euclidPulsesFromPool = v }
        if let v = p.euclidRate { out.euclidRateBeats = max(0.03125, v.beats) }   // GRID: the step grain (RATE×ladder, 2026-08-27)
        out.euclidSpanN = max(0, min(32, p.euclidSpanN ?? 0))                // SPAN re-anchor: nil ⇒ FREE (0), else re-sync every N cols
        // EUCLID LINES (2026-09-29 redesign): ALWAYS resolves to exactly 4 rows via the shared
        // `euclidLinesForEditing()` helper (Models.swift, also used by the GridUI editor so the two can't
        // independently derive this differently) — an untouched machine derives row 0 from the flat fields
        // above, rows 1-3 silent; Router.swift's EUCLID case no longer branches on "is euclidLines empty,"
        // it always loops these 4 (a doc that used the old up-to-8 LINES model keeps only its first 4 —
        // deliberate, per the fixed-4-row redesign, not an oversight).
        out.euclidLines = p.euclidLinesForEditing().map { EuclidLine(target: clamp($0.target, 0, 8), pulses: clamp($0.pulses, 0, 16),
                                                                      steps: clamp($0.steps, 2, 16), rotate: $0.rotate, invert: $0.invert,
                                                                      pick: $0.pick, die: $0.die, noteSel: $0.noteSel, reverse: $0.reverse,
                                                                      gate: $0.gate.map { clamp($0, 0.05, 1.0) }, octave: $0.octave.map { clamp($0, -3, 3) },
                                                                      direction: $0.direction, enabled: $0.enabled,
                                                                      velocity: $0.velocity.map { clamp($0, 0, 2) },
                                                                      velocityAbsolute: $0.velocityAbsolute.map { clamp($0, 1, 127) },
                                                                      missNoteSel: $0.missNoteSel,
                                                                      missGate: $0.missGate.map { clamp($0, 0.05, 1.0) },
                                                                      missOctave: $0.missOctave.map { clamp($0, -3, 3) },
                                                                      missVelocity: $0.missVelocity.map { clamp($0, 0, 2) },
                                                                      patternMiss: $0.patternMiss,
                                                                      rate: $0.rate,
                                                                      // CARD BACKS (2026-10-28): each part's output mask — declared right after `rate` in Models.swift, so this literal's argument order must match; a field left out here silently resets every render.
                                                                      riffOutMask: $0.riffOutMask.map { $0 & 0x0F }, notesOutMask: $0.notesOutMask.map { $0 & 0x0F },
                                                                      useRiff: $0.useRiff, melodyMode: $0.melodyMode,
                                                                      litNotes: $0.litNotes, topLit: $0.topLit, top2Lit: $0.top2Lit, riffOn: $0.riffOn,
                                                                      // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, 2nd same-day ferry) — `melodyMode`
                                                                      // (the PRIOR same-day ferry's own mode field) was MISSING from this fresh
                                                                      // literal entirely, confirmed by reading — a real, pre-existing gap (this
                                                                      // reconstruction's own comment at the end of this call already names the
                                                                      // exact gotcha class: "every field must be threaded through here or it
                                                                      // silently resets each render"), closed here alongside adding the new
                                                                      // fields themselves, so neither the just-shipped MELODY tab nor this one
                                                                      // repeats it.
                                                                      riffRotate: $0.riffRotate,
                                                                      // RIFF WALK ferry (2026-10-19): SHIFT memory, declared right after riffRotate
                                                                      // in Models.swift — this memberwise literal's argument order must match.
                                                                      riffShiftRequested: $0.riffShiftRequested.map { clamp($0, 0, 7) },
                                                                      riffOctave: $0.riffOctave.map { clamp($0, -2, 2) },   // narrowed from the old -3...3 (2026-10-13 adversarial review): Models.swift's riffOctaveResolved already clamps -2...2 unconditionally (riffOctave is Euclideous-exclusive), so this fresh-literal's own bound must match it, not silently disagree
                                                                      riffDir: $0.riffDir, riffDirSeed: $0.riffDirSeed,
                                                                      riffDirBias: $0.riffDirBias.map { clamp($0, -1, 1) },
                                                                      mask: $0.mask, sourceMode: $0.sourceMode,
                                                                      tilt: $0.tilt.map { clamp($0, -1, 1) },
                                                                      riffLock: $0.riffLock, riffInvert: $0.riffInvert, riffOnRest: $0.riffOnRest,
                                                                      riffStride: $0.riffStride.map { clamp($0, 1, 7) },
                                                                      riffLength: $0.riffLength.map { clamp($0, 1, 8) },
                                                                      riffAdvanceStep: $0.riffAdvanceStep,
                                                                      // RIFF WALK ferry (2026-10-19): declared right after riffAdvanceStep in
                                                                      // Models.swift — threaded here for the exact same reason every field on
                                                                      // this call is: miss this spot and the field silently resets every render.
                                                                      riffAdvanceEvery: $0.riffAdvanceEvery.map { clamp($0, 1, 8) },
                                                                      melodyTranspose: $0.melodyTranspose.map { clamp($0, -7, 7) },
                                                                      customHits: $0.customHits,
                                                                      // RIFF/NOTES SPLIT (Paul 2026-10-13 ferry): the NOTES-tab layer's own 3 new fields —
                                                                      // threaded here for the exact same reason every other field on this line is (the
                                                                      // comment right below). noteOctShifts is a RAW passthrough, no clamp, matching
                                                                      // customHits' own identical treatment one line up — the render thread reads it
                                                                      // raw too (never the padded/clamped noteOctShiftsResolved, which allocates).
                                                                      notesOn: $0.notesOn, noteOctShifts: $0.noteOctShifts,
                                                                      notesVelOffset: $0.notesVelOffset.map { clamp($0, -64, 64) },
                                                                      // SEQUENCER PANEL (2026-10-14 ferry §3): per-lane RESET, in sequencer steps —
                                                                      // raw passthrough (no clamp needed here; `resetStepsResolved`'s own set-
                                                                      // membership check {0,1,2,4,8} already guards it wherever it's actually read).
                                                                      // Kept decodable, nothing writes it anymore (see restartMask below).
                                                                      resetSteps: $0.resetSteps,
                                                                      // PER-STEP RESTART MASK (2026-10-15 ferry) — raw passthrough, same reasoning
                                                                      // as resetSteps above; `restartMaskResolved`'s own fallback does the real work
                                                                      // wherever this is actually read.
                                                                      restartMask: $0.restartMask,
                                                                      // LISTEN TAB (ferry 2026-10-14) — threaded here for the EXACT SAME reason every
                                                                      // other field on this line is (see this line's own trailing comment): missing
                                                                      // any of these would silently reset every LISTEN setting to "off" on the very
                                                                      // next snapshot rebuild, the identical gotcha class `customHits`/`notesOn`
                                                                      // above were each added to guard against in turn.
                                                                      listenRhythmMode: $0.listenRhythmMode, listenRhythmPartner: $0.listenRhythmPartner.map { clamp($0, 0, 3) },
                                                                      listenFollowMult: $0.listenFollowMult.map { clamp($0, -3, 2) },
                                                                      listenPitchMode: $0.listenPitchMode, listenPitchPartner: $0.listenPitchPartner.map { clamp($0, 0, 3) },
                                                                      listenPitchPartnerAny: $0.listenPitchPartnerAny,
                                                                      listenShadowInterval: $0.listenShadowInterval.map { clamp($0, -7, 7) },
                                                                      listenShadowOctave: $0.listenShadowOctave.map { clamp($0, -2, 2) },
                                                                      listenAvoidAction: $0.listenAvoidAction,
                                                                      listenLevelMode: $0.listenLevelMode, listenLevelPartner: $0.listenLevelPartner.map { clamp($0, 0, 3) },
                                                                      listenLevelAmount: $0.listenLevelAmount.map { clamp($0, 0, 1) },
                                                                      // LISTEN REBUILT (2026-10-23): the nine new fields — same fresh-literal reason as every field above.
                                                                      listenSource: $0.listenSource.map { clamp($0, 0, 3) }, listenRhythm: $0.listenRhythm,
                                                                      listenDelay: $0.listenDelay.map { max(0, $0) }, listenFeel: $0.listenFeel.map { clamp($0, -1, 1) },
                                                                      listenSpeed: $0.listenSpeed.map { clamp($0, -2, 2) }, listenDirection: $0.listenDirection,
                                                                      listenPitch: $0.listenPitch, listenInterval: $0.listenInterval.map { clamp($0, -6, 6) },
                                                                      listenOctave: $0.listenOctave.map { clamp($0, -3, 3) },
                                                                      // MIX TAB (2026-10-18): the notes layer's own gate/velocity — threaded here for the
                                                                      // same reason as every field above (a fresh literal silently resets anything missing).
                                                                      // notesGate clamps EXACTLY like `gate` (5%…100%) so the two layers agree at the low end.
                                                                      notesGate: $0.notesGate.map { clamp($0, 0.05, 1.0) },
                                                                      notesVelocity: $0.notesVelocity.map { clamp($0, 1, 127) },
                                                                      // LANES GRID (2026-10-18): the five per-lane grid fields — raw passthrough (the resolvers
                                                                      // range-check wherever they are read), threaded here for the same fresh-literal reason as above.
                                                                      muteCells16: $0.muteCells16, muteUnit: $0.muteUnit,
                                                                      restartRhythmMask16: $0.restartRhythmMask16, restartMelodyMask16: $0.restartMelodyMask16,
                                                                      restartUnit: $0.restartUnit,
                                                                      // RESTART CHAINS (2026-10-19): raw passthrough, same fresh-literal reason as every field
                                                                      // above — missing any of these four would silently reset a lane's restart chains or its
                                                                      // remembered HITS/OFFSET to "needs migration"/"nothing requested" on the very next render.
                                                                      restartRhythmBars: $0.restartRhythmBars, restartMelodyPasses: $0.restartMelodyPasses,
                                                                      hitsRequested: $0.hitsRequested, offsetRequested: $0.offsetRequested,
                                                                      // NOTES TAB (2026-10-19): WHEN / CHANCE / PLAY AS / RECEIVED / the lit order — threaded here for the same fresh-literal reason as
                                                                      // every field above (`notesWhen` DEFAULTS to both, so leaving it out would silently turn every stored PLAYS-only lane back to both).
                                                                      notesWhen: $0.notesWhen, notesChance: $0.notesChance.map(EuclidLine.nearestLegalNotesChance),
                                                                      notesPlayAs: $0.notesPlayAs, notesReceivedOnly: $0.notesReceivedOnly, notesLitOrder: $0.notesLitOrder,
                                                                      // RHYTHM POLISH (2026-10-22): the continuous OFFSET fraction and TILT's fine value — raw passthrough, the same fresh-literal reason as every field above.
                                                                      offsetFraction: $0.offsetFraction, tiltFine: $0.tiltFine.map { clamp($0, -1, 1) },
                                                                      // CARD BACKS v2 (2026-10-28): each part's out-transpose, declared last in Models.swift — this memberwise literal's argument order must match.
                                                                      riffOutTranspose: $0.riffOutTranspose.map { clamp($0, -7, 7) }, notesOutTranspose: $0.notesOutTranspose.map { clamp($0, -7, 7) }) }   // EUCLIDEOUS (Paul 2026-10-05): this is a fresh literal, not copy-with-mutation — every EuclidLine field must be threaded through here or it silently resets each render (the exact gotcha a prior RATE-automation feature was bitten by). customHits (the usability-ferry hand-edited-pattern override) added 2026-10-12 — missing it here would have silently reverted every hand edit to pure Euclid on the very next snapshot rebuild.
        // LISTEN TAB preset-load safety (§4's own "(My interpretation.)"): "if a loaded preset contains a
        // loop, switch off the row that closes it." Applied ONCE here, after every lane's own fields have
        // been resolved above, so a hand-edited or legacy doc can never reach the render path (or the UI,
        // which reads this SAME resolved `out.euclidLines`) carrying an un-processable cycle.
        // LISTEN REBUILT (2026-10-23): the new single-source model's own loop-breaker. Runs after every
        // line's old fields have already been migrated into the new ones (the decoder's own §8 migration),
        // so only the new fields matter here — the old `euclideousListenBreakLoops` and the rest of its
        // 3-row-partner section are now deleted entirely (orphaned once the engine/UI rewiring removed
        // their own, separate call sites, tasks #31/#32).
        out.euclidLines = euclideousListenBreakLoopsOnTheNewModel(out.euclidLines)
        out.euclideousRiff = { let r = p.euclideousRiff ?? EuclideousRiff(); var rr = r
            rr.steps = max(1, min(32, r.steps)); rr.ranks = r.ranksResolved
            return rr }()   // EUCLIDEOUS's own shared riff pattern (Paul 2026-10-06), pre-resolved/clamped once here
        // FOUR RIFFS (2026-10-14 ferry §7) — same `MachineParams`-routed path as `euclideousRiff` directly
        // above (not the row-gated PluginState path other Euclideous page-globals use — see that block's
        // own doc comment for why). Each slot normalized the SAME way the singular field just was
        // (`.ranksResolved` applies the R1-default-shape fallback for a nil/unauthored riff) — a raw
        // pass-through would leave `.ranks` nil for any slot whose user-authored value is nil, and
        // Router.swift's `playingRiffIdx` lookup reads `.ranks ?? []` (empty, not the real default).
        out.euclideousRiffs = euclideousRiffsMigrated(p.riffs, legacySingular: out.euclideousRiff).map { r in
            var rr = r
            rr.steps = max(1, min(32, r.steps)); rr.ranks = r.ranksResolved
            return rr
        }
        out.activeRiff = max(0, min(3, p.activeRiff ?? 0))
        // THE RIFF — `p.euclideousLiveGrid` (this `MachineParams` field, NOT `PluginState`'s own same-
        // named decode-only field) is never set any more (2026-10-18, "drop the loop functionality" —
        // `BuildPage.swift`'s publish line stopped populating it), so this `??` fallback fires
        // UNCONDITIONALLY now: the riff = `riffs[activeRiff]`, directly, every time. It stays written
        // this way (rather than simplified to a plain assignment) only so a `MachineParams` built
        // directly — a `RouterTests` fixture, say — can still override it if a future test needs to.
        out.euclideousLiveGrid = p.euclideousLiveGrid ?? out.euclideousRiffs[out.activeRiff]
        // THE LOOPER (§6/§8.5) — NEVER saved; `BuildPage.swift` republishes these fresh from its own live
        // @State on every edit, same as every other live Euclideous control. `active == false` (the
        // default) is "no loop," by far the common case.
        out.euclideousLooperActive = p.euclideousLooperActive ?? false
        out.euclideousLooperStartBeat = p.euclideousLooperStartBeat ?? 0
        out.euclideousLooperPasses = (p.euclideousLooperPasses ?? .fourPasses).passes
        if let r = p.euclideousLooperStartRanks { out.euclideousLooperStartRanks = r.count == 8 ? r : (0..<8).map { $0 < r.count ? r[$0] : 0 } }
        out.euclideousLooperEvents = p.euclideousLooperEvents ?? []
        out.soloMask = (p.soloMask ?? 0) & 0x0F               // LANE SOLO (2026-10-21): nil ⇒ no solo, byte-identical for every other chain
        if let locks = p.euclideousLocks, locks.contains(where: { $0.isLocked }) {   // LANE LOCK (2026-10-21): nil / nothing locked ⇒ [] ⇒ the Router takes its untouched path
            out.euclideousLocks = locks.prefix(4).map { EuclideousLockSnap(on: $0.isLocked, grid: $0.gridResolved, state: $0.state) }
        }
        out.lockRevs = p.lockRevs ?? 0
        // THE MOD PROCESSOR (CC generator / CC-stage §1)
        // PER-PARAM LFOs (Docs/PLAN-param-lfo.md): keep only ACTIVE (depth > 0) entries on a KNOWN target — so a
        // depth-0 / unknown-key LFO resolves away → paramLFOs empty → hasParamLFO false → byte-identical.
        // MIGRATE the old cell|row STEPS span onto modStepSpan when unset: row→ROW, cell→PERIOD (both 8 steps → byte-
        // identical). A doc that never touched STEPS is unaffected (modStepSpan only reshapes the STEPS source).
        // STEPS SPAN (Paul 2026-08-20): the box carries EXACTLY `stepCount` (8/16/32) breakpoints — tile the source
        // (custom or the 8-default) up to N. N=8 (PERIOD/ROW) reproduces the old exactly-8 pack → byte-identical.
        // GLIDE
        return out
    }
}

//  SnapshotBuilder.swift
//  MidiSpark — document → SnapshotBox, on the UI thread (spec v2.8 §7).
//  The builder resolves everything the render thread must never compute:
//  Optional → concrete params, enum → index mapping, LEGATO run starts. (The A/B morph layer is gone — paramsB is decode-only.)

import Foundation

enum SnapshotBuilder {

    static func build(from doc: PluginState, generation: UInt64 = 0, hues: [String: UInt32] = [:]) -> SnapshotBox {
        let scene = doc.activeSceneState   // MULTI-SCENE: bounds-safe active scene (never an out-of-range crash)

        // ---- colours: resolve each Colour's single (A) param bag + its ON assignments (the A/B morph layer was
        //      removed — SnapColour no longer carries b/tier/morph; paramsB/typeB stay decode-only legacy keys). ----
        // The colour array sizes to the DOCUMENT (≥16), so BUILD's ephemeral colours appended by renderDoc() render
        // too — the 16-slot cap is lifted. Cells look up their colour BY ID here (not the fixed global colourIDs), so
        // any appended colour resolves. Behaviour-identical for a plain 16-colour document. (Paul 2026-08-15)
        var colours = [SnapColour](repeating: SnapColour(), count: max(Snap.colours, doc.colours.count))
        var colourIndexByID: [String: Int] = [:]
        for (i, colour) in doc.colours.enumerated() {
            var sc = SnapColour()
            sc.transpose = Int8(max(-24, min(24, colour.transpose)))   // the active type's transpose
            sc.on = colour.onResolved   // delta §9 item 1: carry the ON assignments to the render (nil → unassigned)
            sc.a = resolve(colour.paramsA, type: colour.type, fallback: nil)   // morph removed: the one param bag (A)
            sc.hue = hues[colour.colourID] ?? 0   // DISPLAY hue (packed RGB) for the reel's colour-by-cell roll; 0 ⇒ UI falls back
            colours[i] = sc
            colourIndexByID[colour.colourID] = i
        }

        // ---- cells ----
        let ladderOn = doc.ladderModeResolved                       // LADDER: exclusive columns (resolved here so render stays LADDER-unaware)
        // MACRO MODULATION (macro-panel spec): fold each macro's A→B deltas into its target slots' resolved params
        // below — effective = base + Σ value×delta (Snapshot.applyMacros). Bases (the document, and the seals that
        // read it) are NEVER touched; value 0 = home. Grouped by (col,row,slot) so a slot folds every macro pointing
        // at it in ONE clamp (overlaps sum). v1: values bake at publish → a macro move rebuilds; the render-time
        // path (needed for TIMELINE lanes' per-column f(column)) lands with that bank.
        let macroVals = doc.macrosResolved.map { max(0, min(1, $0.value)) }
        var macroMods: [Int: [MacroMod]] = [:]
        for (mi, macro) in doc.macrosResolved.enumerated() {
            for t in macro.targets {
                guard let param = MacroParam(rawValue: t.param), t.delta != 0,
                      t.col >= 0, t.col < Snap.cols, t.row >= 0, t.row < Snap.rows, t.slot >= 0, t.slot < 64 else { continue }
                macroMods[(t.col * Snap.rows + t.row) * 64 + t.slot, default: []].append(MacroMod(macro: mi, param: param, delta: t.delta))
            }
        }
        var cells = [SnapCell](repeating: SnapCell(), count: Snap.cols * Snap.rows)
        for c in 0..<Snap.cols {
            let ladderActive = ladderOn ? scene.ladderActiveRow(c) : nil   // the one speaking rung this column (topmost-occupied default)
            for r in 0..<Snap.rows {
                guard c < scene.cells.count, r < scene.cells[c].count,
                      let cell = scene.cells[c][r],
                      let colourIndex = colourIndexByID[cell.colourID] else { continue }   // resolve by the DOCUMENT-order index (correct-by-construction); the old canonical-first lookup read the wrong SnapColour if colours were ever reordered (Paul 2026-08-16)
                var sc = SnapCell()
                sc.colourIndex = Int16(colourIndex)   // CR-13a: Int16 — a document colour index can exceed 127 (Int8 trapped)
                sc.alt = cell.alt
                // CELL MACHINE (feat/EditPageSpike): resolve the HEAD treatment — the FIRST chain slot's
                // type+params, else the referenced Colour's A face (already resolved into colours[colourIndex].a,
                // canonically ordered by colourIDs like the render's box.colours[ci]). `bypassed` carries the head
                // slot's bypass in the chain case (identity), or the legacy cell.bypassed in the fallback case.
                // CELL MACHINE stage-3: 3-tier resolution — per-cell OVERRIDE → colour TEMPLATE → legacy A face.
                // MODE ROW: an EXPLICIT empty chain (`processors == []`, a newborn) is a PASSTHROUGH — the held
                // source flows through untreated. It renders as a single BYPASSED identity slot (true-bypass =
                // source-only hold-tail), which the engine already handles; nil still means "follow the template".
                let override = cell.processors.flatMap { $0.isEmpty ? nil : $0 }
                let template = (colourIndex < doc.colours.count ? doc.colours[colourIndex].templateChain : nil).flatMap { $0.isEmpty ? nil : $0 }
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
                    sc.procs = [colours[colourIndex].a]   // legacy: 1-slot head = the Colour's A face
                    sc.slotBypass = [cell.bypassed]
                    sc.bypassed = cell.bypassed
                }
                sc.muted = cell.muted
                sc.dormant = ladderOn && r != (ladderActive ?? -1)   // LADDER: non-active rungs are silent (visible + dimmed in the UI)
                sc.busMask = busBitmask(cell.buses)
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
                    sc.inputChannel = recs[ri].muted ? Snap.mutedSourceFilter
                                                     : UInt8(max(0, min(16, recs[ri].channel)))
                    sc.inputChanMask = recs[ri].muted ? 0 : recs[ri].channelMaskResolved   // MULTI-CHANNEL: the door's channel subset (0 = muted → nothing)
                    sc.inputCableMask = 0b1111   // COG SIMPLIFICATION (2026-08-03): always accept ALL input cables (union) — cables retired from the UI
                    sc.inputRangeLo = recs[ri].rangeLoResolved   // RANGE (§2): the door's note window, admitted before the split/vel window
                    sc.inputRangeHi = recs[ri].rangeHiResolved
                } else {
                    sc.inputChannel = UInt8(max(0, min(16, cell.inputChannel)))   // legacy / no receivers
                    let f = sc.inputChannel; sc.inputChanMask = f == 0 ? 0xFFFF : (f >= 1 && f <= 16 ? (UInt16(1) << UInt16(f - 1)) : 0)
                }
                // MACRO MODULATION: fold any macro offsets targeting this cell's slots into the resolved chain.
                if !macroMods.isEmpty {
                    for k in sc.procs.indices {
                        if let mods = macroMods[(c * Snap.rows + r) * 64 + k] {
                            sc.procs[k] = applyMacros(sc.procs[k], mods: mods, values: macroVals)
                        }
                    }
                }
                cells[c * Snap.rows + r] = sc
            }
        }

        // ---- LEGATO run starts (§3.5/§7 v2.4): same colour + same ROW + contiguous COLUMNS.
        //      Wiring/perform state irrelevant to run identity (§1.1); computed for every cell. A LADDER-DORMANT
        //      rung breaks the run (like an empty cell) — otherwise a full-8×8 ladder reads as one long run from
        //      column 0, and each active rung's legato arp arrives badly phase-advanced (plays mid/end of its cycle).
        for r in 0..<Snap.rows {
            var runStart = -1
            var runColour: Int16 = -1   // CR-13a: SnapCell.colourIndex is Int16 (a doc colour index can exceed 127)
            for c in 0..<Snap.cols {
                let idx = c * Snap.rows + r
                let ci = cells[idx].colourIndex
                if ci >= 0 && !cells[idx].dormant {
                    if ci != runColour { runStart = c; runColour = ci }
                    cells[idx].runStartColumn = Int8(runStart)
                } else {
                    runStart = -1; runColour = -1
                }
            }
        }

        // NO-MACHINE WIRE (Paul 2026-08-23): per DOOR, the UNION of the emitters of every empty-chain (passthrough) cell
        // reading it, EXCLUDING muted cells. The Router passes each door's input straight to these emitters in realtime
        // (reconcileBypass), and skips these cells in the grid's step clock — so a no-machine chain plays LIVE, not quantized.
        var passEmit = [UInt8](repeating: 0, count: 4)
        for idx in 0..<cells.count where cells[idx].passthrough && !cells[idx].muted {
            let r = Int(cells[idx].resolvedReceiver)
            if r >= 0 && r < 4 { passEmit[r] |= cells[idx].busMask }
        }

        // v3.0 (delta §7): per-bus stamp channels A–D, clamped 1–16, defaulted if the doc is short.
        var busCh = [UInt8](repeating: 0, count: 4)
        for i in 0..<4 {
            let v = doc.busChannelsResolved[i]   // CR-8: nil/short-safe (busChannels is now Optional)
            busCh[i] = UInt8(max(1, min(16, v)))
        }
        // delta §6a: enable mask (nil/old docs ⇒ all enabled — the loader default).
        func packMask(_ flags: [Bool]) -> UInt8 { var m: UInt8 = 0; for (i, on) in flags.prefix(4).enumerated() where on { m |= 1 << UInt8(i) }; return m }
        // The ONE passthrough rule: a bypassed identity slot = the source plays untreated as a hold-tail. LEGATO
        // (Paul 2026-08-23): a chain with NO machines just PASSES THROUGH — the held note is struck once and SUSTAINED
        // (adopted across columns) rather than re-struck every step. (A .retrig identity re-attacked the chord at each
        // column boundary = "why does it restrike?".) emitColumnHolds sustains an identity only when its phase == .legato.
        func markPassthrough(_ sc: inout SnapCell) { var sp = SnapParams(); sp.phase = .legato; sc.procs = [sp]; sc.slotBypass = [true]; sc.bypassed = true; sc.passthrough = true }
        let busEnabledMask = packMask(doc.busEnabledResolved)
        // THE RACK (design-the-rack §3, the two-tier law): pre-AND the per-emitter "board in the signal path"
        // gate into every treatment mask. A rack-off emitter drops out of claim/duck/alt entirely → its output is
        // the raw wire regardless of the matrix (no claim ghost/reservation, no duck, no alt turn). The raw doc
        // masks stay the "armed" truth the matrix UI reads directly; only the RENDER sees the gated masks. nil/old
        // docs ⇒ 0b1111 (all racks in path) so existing claim/duck/alt keep applying unchanged.
        let rackMask = doc.rackMaskResolved   // THE CONFIG SHEETS: the ACTIVE rack config's membership (== rackEnabledResolved for old docs)
        func gated(_ m: UInt8?) -> UInt8 { (m ?? 0) & rackMask }   // the two-tier law: a treatment mask is off wherever its emitter's rack is out of path
        // delta §6a CLAIM v2: the claim MASK (from claimMask, or derived from the legacy single field) + the
        // per-claimant LEAK % (0 = full suppression = v1). Gated by the rack.
        let claimMask = doc.claimMaskResolved & rackMask
        // MACRO OUTPUT (macro-panel spec §3): fold each macro's A→B deltas into the per-emitter role AMOUNTS —
        // effective = base + Σ value×delta, summed then clamped ONCE per amount (the offset law). Bases (the
        // document) untouched. These amounts are per-emitter, so they fold HERE (not through applyMacros, which is
        // per-slot). Same v1 bake-at-publish boundary as M1.
        var leakOff = [0.0, 0, 0, 0], duckOff = [0.0, 0, 0, 0], curveOff = [0.0, 0, 0, 0], pocketOff = [0.0, 0, 0, 0]
        for (mi, macro) in doc.macrosResolved.enumerated() {
            for t in macro.emitterTargets where t.emitter >= 0 && t.emitter < 4 && t.delta != 0 {
                let off = macroVals[mi] * t.delta
                switch MacroEmitterParam(rawValue: t.param) {
                case .leak:   leakOff[t.emitter] += off
                case .duck:   duckOff[t.emitter] += off
                case .curve:  curveOff[t.emitter] += off
                case .pocket: pocketOff[t.emitter] += off
                case .none:   break
                }
            }
        }
        func modAmount(_ base: [Int], _ off: [Double], _ lo: Int, _ hi: Int) -> [Int] {
            base.enumerated().map { clamp(Int((Double($1) + off[$0]).rounded()), lo, hi) }
        }
        let claimLeakM  = modAmount(doc.claimLeakResolved, leakOff, 0, 100)      // LEAK %
        let flattenM    = modAmount(doc.flattenAmountResolved, duckOff, 0, 100)  // DUCK %
        let curveM      = modAmount(doc.curveAmountResolved, curveOff, -100, 100)
        let pocketM     = modAmount(doc.pocketMsResolved, pocketOff, -50, 50)
        let claimLeak = claimLeakM.map { UInt8($0) }
        // delta §9 item 11: receiver channel filters (0 = OMNI, 1–16) — for input metering attribution.
        // A MUTED receiver resolves to the match-nothing filter (like a muted cell) so metering goes dark AND
        // the R1 passthrough gate blocks it (mute ruling 2026-07-26) — one representation, both consumers.
        // A MUTED or DISABLED receiver resolves to the match-nothing filter: metering goes dark AND the latch
        // capture (which reads this filter) admits nothing, so a disabled door's frozen pool is SEALED (no
        // re-capture). Muted goes further — its CELLS also read match-nothing (line ~78), killing the grid feed;
        // a disabled door's cells keep their real channel so an ARMED latch's frozen chord still feeds (effectivePool).
        let recvCh = doc.receiversResolved.map {
            ($0.muted || !$0.inputEnabledResolved) ? Snap.mutedSourceFilter : UInt8(max(0, min(16, $0.channel)))
        }
        let recvChMask = doc.receiversResolved.map { UInt16($0.muted || !$0.inputEnabledResolved ? 0 : $0.channelMaskResolved) }   // MULTI-CHANNEL: the door's admission subset (0 = muted/disabled)
        let recvCable = doc.receiversResolved.map { _ in UInt8(0b1111) }   // COG SIMPLIFICATION: always accept ALL input cables (union)
        // TWO LATCH MODES: pack the per-receiver ADD flag into a mask (bit i = receiver i toggles, not replaces).
        let latchAddMask = packMask(doc.receiversResolved.map { $0.latchAddResolved })
        // INPUT ENABLE: bit i = receiver i is NOT listening (door closed) — the Router blocks its cells' LIVE read.
        let receiverDisabledMask = packMask(doc.receiversResolved.map { !$0.inputEnabledResolved })
        // RANGE (§2): the 4 receivers' note windows, for the latch capture (upstream of latch — the grid feed reads
        // the per-cell window resolved above).
        let receiverRangeLo = doc.receiversResolved.map { $0.rangeLoResolved }
        let receiverRangeHi = doc.receiversResolved.map { $0.rangeHiResolved }
        // BYPASS (§1/§2): which doors inject straight to emitters + each door's destination emitter mask (A–D).
        let receiverBypassMask = packMask(doc.receiversResolved.map { $0.bypassResolved })
        let receiverBypassDest = doc.receiversResolved.map { $0.bypassDestResolved }
        let receiverControllerMask = doc.receiversResolved.map { $0.controllerMaskResolved }   // CONTROLLER ROUTING: per-door emitter forward mask
        let receiverPianoMask = packMask(doc.receiversResolved.map { $0.latchPianoResolved })   // PIANO LATCH: doors whose latch reads the keyboard
        let receiverPianoNotes = doc.receiversResolved.map { $0.pianoNotesResolved.map { UInt8(max(0, min(127, $0))) } }
        let receiverExcludeDoor = doc.receiversResolved.enumerated().map { (i, r) -> Int8 in let d = r.excludeDoorResolved; return d == i ? -1 : Int8(d) }   // never exclude self
        let receiverReplayMask = packMask(doc.receiversResolved.map { $0.doorModeResolved == .replay })   // REPLAY doors
        let receiverFile: [SnapFileClip] = doc.receiversResolved.map { r in   // FILE clips — only for a door in FILE mode with a loaded clip
            guard r.doorModeResolved == .file, let clip = r.fileClip, !clip.isEmpty, let lb = r.fileLoopBeats, lb > 0 else { return SnapFileClip() }
            return SnapFileClip(beats: clip.map { $0.beat }, notes: clip.map { $0.note }, vels: clip.map { $0.vel }, ons: clip.map { $0.on }, loopBeats: lb)
        }
        let receiverReplayPasses = doc.receiversResolved.map { UInt8($0.replayPassesResolved) }

        // PER-PART CLOCK (Paul 2026-08-19): resolve each row's step + loop length from the scene's per-row overrides
        // (nil ⇒ the scene default / a full 8 → uniform = today).
        let rowStepBeats: [Double] = (0..<Snap.rows).map { r in
            (scene.rowStepRate.flatMap { arr -> StepRate? in r < arr.count ? arr[r] : nil })?.beats ?? scene.stepRate.beats
        }
        let rowLenResolved: [Int] = (0..<Snap.rows).map { r in
            (scene.rowLen.flatMap { arr -> Int? in r < arr.count ? arr[r] : nil }).map { max(1, min(Snap.cols, $0)) } ?? Snap.cols
        }
        // PER-ROW LAP (Paul 2026-08-19): pass the per-row loop mask through when the scene set one (BUILD's two grids),
        // else empty ⇒ the render uses the ephemeral global lap for every row (GRID tab, byte-identical).
        let rowLaneResolved: [UInt8] = (scene.rowLane?.count == Snap.rows) ? scene.rowLane! : []

        // ROW 8 (Paul 2026-08-22): the toggle cells that flow through the box. A cell counts as ACTIVE when its scene
        // toggle (row8On) is lit. FREEZE ⇒ sustain + pause; HALFTIME ⇒ scale the play-grid clock (÷2 = 2.0 = slower).
        let row8 = doc.row8Resolved, row8On = scene.row8OnResolved
        var freezeActive = false, clockScale = 1.0, broadcastActive = false
        var busRemap: [UInt8] = [0, 1, 2, 3]   // REDIRECT/SWAP: the per-bus output remap
        func wire(_ v: Int?) -> Int { max(0, min(3, v ?? 0)) }
        for i in 0..<min(8, row8.count) where row8On[i] {
            switch row8[i].type {
            case .freeze:    freezeActive = true
            case .halftime:  clockScale = [2.0, 1.0, 0.5][max(0, min(2, row8[i].halftimeMode ?? 1))]   // 0 ÷2 · 1 ×1 · 2 ×2
            case .redirect:  let f = wire(row8[i].wireFrom), t = wire(row8[i].wireTo); busRemap[f] = UInt8(t)          // A→B
            case .swap:      let f = wire(row8[i].wireFrom), t = wire(row8[i].wireTo); busRemap[f] = UInt8(t); busRemap[t] = UInt8(f)   // A↔B
            case .broadcast: broadcastActive = true
            default: break
            }
        }

        return SnapshotBox(generation: generation,
                           stepBeats: scene.stepRate.beats,
                           swing: Double(max(50, min(75, scene.swing))),
                           morphMaster: max(0, min(1, doc.morphMasterResolved)),
                           colours: colours,
                           cells: cells,
                           busChannels: busCh,
                           busEnabledMask: busEnabledMask,
                           claimMask: claimMask,
                           claimLeak: claimLeak,
                           flattenMask: gated(doc.flattenMask),
                           flattenAmount: flattenM.map { UInt8($0) },
                           altMask: gated(doc.altMask),
                           altCount: doc.altCountResolved.map { UInt8($0) },
                           turnsPerNote: doc.turnsPerNoteResolved,
                           curveMask: gated(doc.curveMask),
                           curveAmount: curveM.map { Int8($0) },
                           fenceMask: gated(doc.fenceMask),
                           fencePolicy: doc.fencePolicyResolved.map { UInt8($0) },
                           fenceLo: doc.fenceLoResolved.map { UInt8($0) },
                           fenceHi: doc.fenceHiResolved.map { UInt8($0) },
                           monoMask: gated(doc.monoMask),
                           monoPriority: doc.monoPriorityResolved.map { UInt8($0) },
                           pocketMask: gated(doc.pocketMask),
                           pocketMs: pocketM.map { Int8($0) },
                           convLead: Int8(doc.convLeadResolved),
                           convStance: doc.convStanceResolved.enumerated().map { (i, s) in (rackMask & (1 << UInt8(i)) != 0) ? UInt8(s) : 0 },
                           rackMask: rackMask,
                           masterKey: Int8(scene.masterKeyResolved),
                           masterMute: doc.masterMute ?? false,
                           thruReceiver: Int8(doc.thruReceiverResolved),
                           receiverChannels: recvCh,
                           receiverChannelMask: recvChMask,
                           receiverCables: recvCable,
                           latchAddMask: latchAddMask,
                           receiverDisabledMask: receiverDisabledMask,
                           receiverRangeLo: receiverRangeLo,
                           receiverRangeHi: receiverRangeHi,
                           receiverBypassMask: receiverBypassMask,
                           receiverBypassDest: receiverBypassDest,
                           passEmitterMask: passEmit,
                           receiverControllerMask: receiverControllerMask,
                           receiverPianoMask: receiverPianoMask,
                           receiverPianoNotes: receiverPianoNotes,
                           receiverExcludeDoor: receiverExcludeDoor,
                           receiverReplayMask: receiverReplayMask,
                           receiverReplayPasses: receiverReplayPasses,
                           receiverFile: receiverFile,
                           macroValues: macroVals,
                           rowStepBeats: rowStepBeats, rowLen: rowLenResolved, rowLaneMask: rowLaneResolved,
                           freezeActive: freezeActive, clockScale: clockScale, busRemap: busRemap,
                           broadcastActive: broadcastActive)
    }

    // Map document params → flat indices. `fallback` = A-state for sparse-B inheritance.
    private static func resolve(_ p: ColourParams, type: ProcessorType, fallback: SnapParams?) -> SnapParams {
        var out = fallback ?? SnapParams()
        out.type = type
        if let v = p.pattern { out.patternIndex = UInt8(ArpPattern.allCases.firstIndex(of: v) ?? 0) }
        if let v = p.rate { out.rateIndex = Int8(ArpRate.allCases.firstIndex(of: v) ?? 3) }
        if let v = p.octaves { out.octaves = UInt8(clamp(v, 1, 4)) }
        if let v = p.gate { out.gate = clamp(v, 0.05, 1) }
        if let v = p.phase { out.phase = v }
        if let v = p.count { out.count = UInt8(clamp(v, 2, 16)) }   // CR-6: BURST reads up to 16 (Router min(16,·)); RATCHET re-snaps ≤8 via effectiveRepeats, so widening the clamp only unlocks BURST's HITS 12/16 (were both silently = 8)
        if let v = p.ramp { out.ramp = clamp(v, 0, 1) }
        if let v = p.passes {
            out.passMask = 0
            for (i, on) in v.prefix(4).enumerated() where on { out.passMask |= UInt8(1 << i) }
        }
        if let v = p.strumDir { out.strumDir = v }
        if let v = p.spread { out.spread = clamp(v, 0, 1) }
        if let v = p.curve { out.curve = clamp(v, -1, 1) }
        if let v = p.velTilt { out.velTilt = clamp(v, -1, 1) }
        if let v = p.strumSpreadNorm { out.strumSpreadNorm = v }
        if let v = p.probability { out.probability = clamp(v, 0, 1) }
        if let v = p.chanceTilt { out.chanceTilt = clamp(v, -1, 1) }
        if let v = p.chanceDensity { out.chanceDensity = v }
        if let v = p.chanceMode { out.chanceMode = v }
        if let v = p.chanceSlices { out.chanceSlices = v.map { max(0, min(100, $0)) } }
        if let v = p.chanceRotate { out.chanceRotate = ((v % 8) + 8) % 8 }
        if let v = p.tuttiMode { out.tuttiMode = v }
        if let v = p.tuttiBalance { out.tuttiBalance = clamp(v, 0, 1) }
        if let v = p.tuttiPick { out.tuttiPick = v }
        if let v = p.tuttiSlices { var s = v; while s.count < 8 { s.append(.all) }; out.tuttiSlices = Array(s.prefix(8)) }
        if let v = p.tuttiRate { out.tuttiSliceBeats = max(0.03125, v.beats) }
        if let v = p.tuttiRotate { out.tuttiRotate = ((v % 8) + 8) % 8 }
        if let v = p.tuttiSpan { out.tuttiSpan = v }
        out.tuttiSpanN = p.tuttiSpanN ?? 0   // SPAN LADDER (RATE×ladder): 0 = legacy CELL|ROW; >0 = the loop period in columns
        if let v = p.lenSlices { var s = v; while s.count < 8 { s.append(.pass) }; out.lenSlices = Array(s.prefix(8)) }
        if let v = p.lenShort { out.lenShort = clamp(v, 0.05, 0.95) }
        if let v = p.lenLong { out.lenLong = clamp(v, 0, 1) }
        if let v = p.lenRotate { out.lenRotate = ((v % 8) + 8) % 8 }
        if let v = p.lenSpan { out.lenSpan = v }
        out.lenSpanN = p.lenSpanN ?? (out.lenSpan == .row ? 8 : 1)   // SPAN LADDER: explicit N wins; else migrate CELL→1 / ROW→8
        if let v = p.weaveMode { out.weaveMode = v }
        if let v = p.weaveBaseStep { out.weaveBaseBeats = max(0.03125, v.beats) }
        if let v = p.weaveSpan { out.weaveSpan = clamp(v, 1, 8) }
        if let v = p.weavePhase { out.weavePhase = v }
        if let v = p.weaveDrawn { var s = v; while s.count < 8 { s.append(.r1_8) }; out.weaveDrawnBeats = Array(s.prefix(8)).map { max(0.03125, $0.beats) } }
        if let v = p.weaveEuclidSteps { out.weaveEuclidSteps = clamp(v, 2, 16) }
        if var v = p.splitSet { v.n = clamp(v.n, 1, 8); v.note = clamp(v.note, 0, 127); out.splitSet = v }
        if var v = p.splitVel { v.floor = clamp(v.floor, 1, 127); v.ceil = clamp(v.ceil, v.floor, 127); out.splitVel = v }
        if let v = p.utilOctave { out.utilOctave = clamp(v, -3, 3) }         // UTILITY (Paul 2026-08-22)
        if let v = p.utilTranspose { out.utilTranspose = clamp(v, -24, 24) }
        if let v = p.utilChannel { out.utilChannel = clamp(v, 0, 16) }       // 0 = WIRE · 1–16 override
        if let v = p.utilNudge { out.utilNudge = clamp(v, -8, 8) }           // ± sixteenths
        if let v = p.utilNudgeMode { out.utilNudgeMode = v }                 // TIMING LANE (Paul 2026-08-22 §5)
        if let v = p.utilNudgeLane { out.utilNudgeLane = v.map { clamp($0, -8, 8) } }
        if let v = p.destSlices { out.destSlices = v.map { clamp($0, 0, 3) } }   // DEST MATRIX (Paul 2026-08-22 §5)
        if let v = p.muteSlices { out.muteSlices = v.map { clamp($0, 0, 15) } }   // MUTE MATRIX (Paul 2026-08-25 §5): 4-bit muted-emitter mask per slice
        // RIFF (SPEC-riff-processor): resolve the stencil. riffRanks nil ⇒ keeps the default figure. rate → beats.
        if let v = p.riffSteps { out.riffSteps = clamp(v, 1, 16) }
        if let v = p.riffRate { out.riffRateBeats = max(0.03125, v.beats) }
        if let v = p.riffRanks { out.riffRanks = v.map { clamp($0, 0, 8) } }
        if let v = p.riffOct { out.riffOct = v.map { clamp($0, -1, 1) } }
        if let v = p.riffAccent { out.riffAccent = v.map { clamp($0, 0, 127) } }
        if let v = p.riffTie { out.riffTie = v }
        if let v = p.riffSlide { out.riffSlide = v }
        if let v = p.riffWrap { out.riffWrap = v }
        if let v = p.rtcMode { out.rtcMode = v }
        if let v = p.rtcChance { out.rtcChance = clamp(v, 0, 1) }
        if let v = p.rtcCountLo { out.rtcCountLo = clamp(v, 1, 8) }
        if let v = p.rtcCountHi { out.rtcCountHi = clamp(v, out.rtcCountLo, 8) }
        // COIN — SHAPING THE DICE (Paul 2026-08-26): weights kept only if any is >0 (else EMPTY ⇒ LO/HI fallback, byte-identical)
        if let w = p.rtcSizeWeights, w.contains(where: { $0 > 0 }) { out.rtcSizeWeights = w.map { max(0, min(100, $0)) } }
        if let v = p.rtcGap { out.rtcGap = clamp(v, 0, 4) }
        if let v = p.rtcQuota { out.rtcQuota = clamp(v, 0, 4) }
        if let v = p.rtcOddsVel { out.rtcOddsVel = v }
        if let v = p.rtcSlices { var s = v; while s.count < 8 { s.append(0) }; out.rtcSlices = Array(s.prefix(8)).map { clamp($0, 0, 8) } }
        if let v = p.rtcRate { out.rtcRateBeats = max(0.03125, v.beats) }
        if let v = p.rtcRotate { out.rtcRotate = ((v % 8) + 8) % 8 }
        if let v = p.rtcSpan { out.rtcSpan = v }
        out.rtcSpanN = p.rtcSpanN ?? 0   // SPAN LADDER (RATE×ladder): 0 = legacy CELL|ROW; >0 = loop period in columns
        if let v = p.arpFit { out.arpFit = v }
        if let v = p.arpOctDown { out.arpOctDown = v }
        if let v = p.arpRandomAnchor { out.arpRandomAnchor = max(0, min(2, v)) }
        if let v = p.harmIntervals {
            func clampInt(_ i: Int) -> Int8 { Int8(clamp(i, -24, 24)) }
            out.harmIntervals = (clampInt(v.count > 0 ? v[0] : 0),
                                 clampInt(v.count > 1 ? v[1] : 0),
                                 clampInt(v.count > 2 ? v[2] : 0))
        }
        if let v = p.harmVelScale { out.harmVelScale = clamp(v, 0.1, 1) }
        // ECHO (user 2026-08-08)
        if let v = p.echoSync { out.echoSync = v }
        if let v = p.echoDelayDiv { out.echoDelayDiv = clamp(v, 1, 16) }
        if let v = p.echoDelayMs { out.echoDelayMs = clamp(v, 1, 5000) }
        if let v = p.echoRepeats { out.echoRepeats = clamp(v, 1, 16) }
        if let v = p.echoOffset { out.echoOffset = clamp(v, -0.33, 0.33) }
        if let v = p.echoFeedDelay { out.echoFeedDelay = clamp(v, 0, 1) }
        if let v = p.echoDecay { out.echoDecay = clamp(v, 0, 1) }
        if let v = p.echoPitch { out.echoPitch = clamp(v, -24, 24) }
        if let v = p.echoThru { out.echoThru = v }
        if let v = p.echoSpill { out.echoSpill = v }
        if let v = p.echoRoute { out.echoRoute = v }
        if let v = p.euclidSteps { out.euclidSteps = clamp(v, 2, 16) }
        if let v = p.euclidPulses { out.euclidPulses = clamp(v, 1, 16) }
        if let v = p.euclidRot { out.euclidRot = clamp(v, 0, 15) }
        if let v = p.euclidPulsesFromPool { out.euclidPulsesFromPool = v }
        if let v = p.euclidSpan { out.euclidSpan = v }
        out.euclidSpanN = p.euclidSpanN ?? (out.euclidSpan == .row ? 8 : 1)
        if let v = p.euclidPick { out.euclidPick = v }
        if let v = p.euclidInvert { out.euclidInvert = v }
        if let v = p.euclidLines {   // EUCLID LINES (§10): clamp each line + cap at 8; empty ⇒ single-euclid fallback
            out.euclidLines = v.prefix(8).map { EuclidLine(target: clamp($0.target, 0, 8), pulses: clamp($0.pulses, 0, 16),
                                                           steps: clamp($0.steps, 2, 16), rotate: $0.rotate, invert: $0.invert) }
        }
        if let v = p.burstSpan { out.burstSpan = v }
        out.burstSpanN = p.burstSpanN ?? (out.burstSpan == .row ? 8 : 1)
        if let v = p.burstMode { out.burstMode = v }
        if let v = p.burstSlices { var s = v; while s.count < 8 { s.append(.rest) }; out.burstSlices = Array(s.prefix(8)) }
        if let v = p.burstRotate { out.burstRotate = ((v % 8) + 8) % 8 }
        if let v = p.burstChance { out.burstChance = clamp(v, 0, 1) }
        if let v = p.cascadeSpan { out.cascadeSpan = v }
        out.cascadeSpanN = p.cascadeSpanN ?? 0   // SPAN LADDER (RATE×ladder): 0 = legacy CELL|ROW; >0 = reveal window in columns
        // THE MOD PROCESSOR (CC generator / CC-stage §1)
        if let v = p.modCC { out.modCC = clamp(v, 0, 127) }
        if let v = p.modSource { out.modSource = v }
        if let v = p.modShape { out.modShape = v }
        if let v = p.modRate { out.modRate = v }
        if let v = p.modSpan { out.modSpan = v }
        // MIGRATE the old cell|row STEPS span onto modStepSpan when unset: row→ROW, cell→PERIOD (both 8 steps → byte-
        // identical). A doc that never touched STEPS is unaffected (modStepSpan only reshapes the STEPS source).
        if let v = p.modStepSpan { out.modStepSpan = v } else { out.modStepSpan = (out.modSpan == .row) ? .row : .period }
        if let v = p.modMin { out.modMin = clamp(v, 0, 127) }
        if let v = p.modMax { out.modMax = clamp(v, 0, 127) }
        if let v = p.modReset { out.modReset = v }
        if let v = p.modTarget { out.modTarget = v }
        if let v = p.modChainParam { out.modChainParam = v }
        if let v = p.modFollow { out.modFollow = v }
        // STEPS SPAN (Paul 2026-08-20): the box carries EXACTLY `stepCount` (8/16/32) breakpoints — tile the source
        // (custom or the 8-default) up to N. N=8 (PERIOD/ROW) reproduces the old exactly-8 pack → byte-identical.
        let stepN = out.modStepSpan.stepCount
        let stepSrc = { () -> [Int] in if let v = p.modSteps, !v.isEmpty { return v }; return out.modSteps }()
        out.modSteps = (0..<stepN).map { clamp(stepSrc[$0 % stepSrc.count], 0, 127) }
        if let v = p.modSmooth { out.modSmooth = v }
        if let v = p.modAttack { out.modAttack = clamp(v, 0.01, 4) }
        if let v = p.modRelease { out.modRelease = clamp(v, 0.01, 4) }
        if let v = p.modExternCC { out.modExternCC = clamp(v, 0, 127) }
        // GLIDE
        if let v = p.glideTime { out.glideTime = clamp(v, 0, 4) }
        if let v = p.glideRange { out.glideRange = clamp(v, 1, 48) }
        if let v = p.glidePriority { out.glidePriority = v }
        if let v = p.glideReanchor { out.glideReanchor = v }
        if let v = p.glideMode { out.glideMode = v }
        return out
    }
}

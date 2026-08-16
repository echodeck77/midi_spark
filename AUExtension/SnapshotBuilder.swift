//  SnapshotBuilder.swift
//  MidiSpark — document → SnapshotBox, on the UI thread (spec v2.8 §7).
//  The builder resolves everything the render thread must never compute:
//  paramsB merged over paramsA, enum → index mapping, LEGATO run starts.

import Foundation

enum SnapshotBuilder {

    static func build(from doc: PluginState, generation: UInt64 = 0) -> SnapshotBox {
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
                sc.colourIndex = Int8(colourIndex)
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
                sc.velFloor = UInt8(max(1, min(127, vw.floor))); sc.velCeil = UInt8(max(1, min(127, vw.ceil)))
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
                    sc.inputCableMask = 0b1111   // COG SIMPLIFICATION (2026-08-03): always accept ALL input cables (union) — cables retired from the UI
                    sc.inputRangeLo = recs[ri].rangeLoResolved   // RANGE (§2): the door's note window, admitted before the split/vel window
                    sc.inputRangeHi = recs[ri].rangeHiResolved
                } else {
                    sc.inputChannel = UInt8(max(0, min(16, cell.inputChannel)))   // legacy / no receivers
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
            var runColour: Int8 = -1
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

        // v3.0 (delta §7): per-bus stamp channels A–D, clamped 1–16, defaulted if the doc is short.
        var busCh = [UInt8](repeating: 0, count: 4)
        for i in 0..<4 {
            let v = i < doc.busChannels.count ? doc.busChannels[i] : (i + 1)
            busCh[i] = UInt8(max(1, min(16, v)))
        }
        // delta §6a: enable mask (nil/old docs ⇒ all enabled — the loader default).
        func packMask(_ flags: [Bool]) -> UInt8 { var m: UInt8 = 0; for (i, on) in flags.prefix(4).enumerated() where on { m |= 1 << UInt8(i) }; return m }
        // The ONE passthrough rule: a bypassed identity slot = the source plays untreated as a hold-tail.
        func markPassthrough(_ sc: inout SnapCell) { sc.procs = [SnapParams()]; sc.slotBypass = [true]; sc.bypassed = true }
        let busEnabledMask = packMask(doc.busEnabledResolved)
        // THE RACK (design-the-rack §3, the two-tier law): pre-AND the per-emitter "board in the signal path"
        // gate into every treatment mask. A rack-off emitter drops out of claim/duck/alt entirely → its output is
        // the raw wire regardless of the matrix (no claim ghost/reservation, no duck, no alt turn). The raw doc
        // masks stay the "armed" truth the matrix UI reads directly; only the RENDER sees the gated masks. nil/old
        // docs ⇒ 0b1111 (all racks in path) so existing claim/duck/alt keep applying unchanged.
        let rackMask = doc.rackEnabledResolved
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

        return SnapshotBox(generation: generation,
                           stepBeats: scene.stepRate.beats,
                           swing: Double(max(50, min(75, scene.swing))),
                           morphMaster: max(0, min(1, doc.morphMaster)),
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
                           receiverCables: recvCable,
                           latchAddMask: latchAddMask,
                           receiverDisabledMask: receiverDisabledMask,
                           receiverRangeLo: receiverRangeLo,
                           receiverRangeHi: receiverRangeHi,
                           receiverBypassMask: receiverBypassMask,
                           receiverBypassDest: receiverBypassDest,
                           receiverControllerMask: receiverControllerMask,
                           receiverPianoMask: receiverPianoMask,
                           receiverPianoNotes: receiverPianoNotes,
                           macroValues: macroVals)
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
        if let v = p.count { out.count = UInt8(clamp(v, 2, 8)) }
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
        if let v = p.tuttiMode { out.tuttiMode = v }
        if let v = p.tuttiBalance { out.tuttiBalance = clamp(v, 0, 1) }
        if let v = p.tuttiPick { out.tuttiPick = v }
        if let v = p.arpFit { out.arpFit = v }
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
        if let v = p.euclidSteps { out.euclidSteps = clamp(v, 2, 16) }
        if let v = p.euclidPulses { out.euclidPulses = clamp(v, 1, 16) }
        if let v = p.euclidRot { out.euclidRot = clamp(v, 0, 15) }
        if let v = p.euclidPulsesFromPool { out.euclidPulsesFromPool = v }
        // THE MOD PROCESSOR (CC generator / CC-stage §1)
        if let v = p.modCC { out.modCC = clamp(v, 0, 127) }
        if let v = p.modSource { out.modSource = v }
        if let v = p.modShape { out.modShape = v }
        if let v = p.modRate { out.modRate = v }
        if let v = p.modMin { out.modMin = clamp(v, 0, 127) }
        if let v = p.modMax { out.modMax = clamp(v, 0, 127) }
        if let v = p.modReset { out.modReset = v }
        if let v = p.modFollow { out.modFollow = v }
        if let v = p.modSteps, !v.isEmpty { out.modSteps = (0..<8).map { clamp(v[$0 % v.count], 0, 127) } }
        if let v = p.modSmooth { out.modSmooth = v }
        if let v = p.modAttack { out.modAttack = clamp(v, 0.01, 4) }
        if let v = p.modRelease { out.modRelease = clamp(v, 0.01, 4) }
        if let v = p.modExternCC { out.modExternCC = clamp(v, 0, 127) }
        // GLIDE
        if let v = p.glideTime { out.glideTime = clamp(v, 0, 4) }
        if let v = p.glideRange { out.glideRange = clamp(v, 1, 48) }
        if let v = p.glidePriority { out.glidePriority = v }
        if let v = p.glideReanchor { out.glideReanchor = v }
        return out
    }
}

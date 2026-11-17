//  FillPreview.swift — FILL TAB ferry (2026-11-15) §5: the rich note-level preview's PURE predictor.
//
//  A faithful mirror of the Router's fill loop (`runEuclidLine`'s override path) for the RIFF layer: it calls the SAME
//  pure functions the engine does — euclideousFillSourceStep (ORDER), euclideousFillSlotHostBeat / …StepHostLength (RUSH
//  timing), euclideousFillRankOffset (RANKS SHAPE), euclideousFillSwellFactor (SWELL), euclideousFillRollCount (ROLL),
//  euclideousFillBreakDrops (BREAK), euclideousLaneChainTick (the walk ordinal, with ADV-STEP forced in a HITS region),
//  euclideousRiffColumn + riffResolve (the pitch) — so the drawn notes equal what the AU emits (pinned by FillPreviewTests).
//
//  Foundation-only (test target). Scope: the RIFF layer, ON REST = SKIP (TIE / REPEAT and the NOTES-layer stack are not
//  previewed — a disclosed limit; the riff is the fill's primary content). INVERT / TRANSPOSE ride cfg; the per-lane MASK
//  (inert in production) does not.

import CoreGraphics

/// One predicted fill note (absolute host beats). `broken` = dropped by BREAK (drawn hatched, silent); `land` = the LAND
/// rejoin accent; `stack` = a NOTES-layer note (vs the riff), so the view can shade the two apart.
struct EuclideousFillPreviewNote: Equatable {
    var bar: Int
    var onset: Double
    var length: Double
    var pitch: Int
    var vel: Int
    var broken: Bool = false
    var land: Bool = false
    var stack: Bool = false
}

// MARK: - FILL TAB V2 §3.6 — the ROLL ROW's per-bar prediction (fill notes AND the bar's normal notes, so a cell can draw
// grey-outside / lane-colour-inside; a CHANCE-skipped bar keeps its normal notes and flags the dashed would-be region).
// The same pure functions the Router uses, the same seeds; the FLAT latch is computed in time order exactly as the Router
// latches it. Declared limits (the existing preview's): riff ON REST = SKIP (no TIE / REPEAT), no swing / HIT-TIMING
// offsets, no MASK; a PITCH-borrowing (SHADOW / ECHO) lane predicts nothing.

/// One drawn note of a roll-row cell (absolute host beats). `fill` = inside a region (lane colour); plain notes grey.
struct EuclideousFillRollNote: Equatable {
    var onset: Double
    var length: Double
    var pitch: Int
    var vel: Int
    var fill = false
    var land = false
    var broken = false   // BREAK-dropped (drawn as the region's silence — hatched span, no fill)
    var stack = false
}

/// One bar of the roll row. `regionLo/Hi` frame the fill region's wash (0/0 = none this bar); `skipped` = lit but the
/// CHANCE draw skipped it (§3.6: outline the region dashed, draw the notes as no fill); `breakLo/Hi` BREAK's quarter.
struct EuclideousFillRollBar: Equatable {
    var notes: [EuclideousFillRollNote] = []
    var regionLo = 0.0, regionHi = 0.0
    var skipped = false
    var breakLo = 0.0, breakHi = 0.0
}

/// The §3.6 prediction for (0-based) bar `b` — the bar's PLAIN notes outside any region, the fill's notes inside it,
/// the previous bar's LAND accent on this bar's first step, and the skipped-bar state.
func euclideousFillRollBar(cfg: EuclideousWalkLaneConfig, line: EuclidLine, lane: Int,
                           pool: [Int], riffOct: Int, baseVel: Int, ranks: [Int],
                           bar b: Int, beatsPerBar: Double, originBeat: Double) -> EuclideousFillRollBar {
    var out = EuclideousFillRollBar()
    guard cfg.sub > 0, beatsPerBar > 0, !pool.isEmpty, !ranks.isEmpty else { return out }
    let borrowing = line.listenPitchResolved == .shadow || line.listenPitchResolved == .echo
    let riffLive = cfg.riffOn && !borrowing
    let notesLive = euclideousNotesLayerIsOn(line) && !borrowing
    let notesOct = max(-2, min(2, line.octaveResolved))
    let notesGate = line.notesGateResolved
    let notesVel = line.notesVelocityResolved
    let cycleLen = euclidCycleLen(cfg.dir, n: cfg.n)
    let plan = EuclideousFillPlan(line: line, lane: lane, originBeat: originBeat, beatsPerBar: beatsPerBar, sub: cfg.sub)
    let region = plan.active ? plan.region(bar: b) : nil
    // lit-but-skipped: armed and FILL active, but the CHANCE draw said no — frame the would-be region, dashed (§3.6).
    if plan.active, region == nil, (plan.armed >> UInt16(((b % plan.loop) + plan.loop) % plan.loop)) & 1 != 0,
       !euclideousFillChancePlays(lane: lane, bar: b, chance: plan.chance) {
        out.skipped = true
        let E = Double(b + 1) * beatsPerBar
        out.regionHi = E; out.regionLo = E - plan.lengthFraction * beatsPerBar
    }
    func rawRankAt(_ advOrd: Int64) -> Int {
        let col = euclideousRiffColumn(ordinal: advOrd, every: cfg.every, direction: cfg.riffDir, length: cfg.length, stride: cfg.stride, shift: cfg.rotate, seed: cfg.seed, columns: cfg.columns)
        return (col >= 0 && col < ranks.count) ? ranks[col] : 0
    }
    func pitchAt(advOrd: Int64, extra: Int, flatRank: Int, mode: EuclideousFillNotes, odd: Bool) -> (pitch: Int, rank: Int)? {
        let rawRank = rawRankAt(advOrd)
        guard rawRank >= 1 else { return nil }
        let q0 = (cfg.invert ? 9 - rawRank : rawRank) + cfg.transpose
        guard q0 >= 1 else { return nil }
        let fv = euclideousFillNotesVoice(mode: mode, q0: q0, offset: extra, flatRank: flatRank, oddSlot: odd)
        guard let p0 = riffResolve(rank: fv.r0, oct: riffOct, n: pool.count, wrap: .fold, asc: { pool[$0] }) else { return nil }
        let p = p0 + (fv.octUp ? 12 : 0)
        guard (0...127).contains(p) else { return nil }
        return (p, fv.r0)
    }
    let barLo = Double(b) * beatsPerBar, barHi = Double(b + 1) * beatsPerBar
    let originTick = Int64((originBeat / cfg.sub).rounded(.down))
    // the previous bar's LAND: this bar's FIRST step is the accented rejoin (vel ×1.3, gate ×2, strikes even on a rest).
    let landedInto = plan.active && (plan.region(bar: b - 1)?.land ?? false)
    // ---- the PLAIN span: [barLo, region?.F ?? barHi) — the lane's ordinary ×1 walk (SKIP semantics) ----
    let plainHi = region?.F ?? barHi
    var t = Int64((barLo / cfg.sub - 1e-9).rounded(.up))
    while Double(t) * cfg.sub < plainHi - 1e-9 {
        let hostBeat = Double(t) * cfg.sub
        let info = euclideousLaneChainTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: t,
                                           chains: cfg.chains, legacySpanBeats: cfg.spanBeats, advanceStep: cfg.advanceStep, hostBeat: hostBeat)
        let isLandStep = landedInto && hostBeat < barLo + cfg.sub - 1e-9
        if info.rawIsHit || isLandStep {   // LAND part b: the rejoin strikes even on a rest
            let isRestHit = rawRankAt(info.advOrd) < 1
            if riffLive, let pr = pitchAt(advOrd: info.advOrd, extra: 0, flatRank: 0, mode: .riff, odd: false) {
                let gateLen = max(0.002, cfg.sub * cfg.gate * (isLandStep ? 2 : 1))
                let v = isLandStep ? Int((Double(baseVel) * 1.3).rounded()) : baseVel
                out.notes.append(EuclideousFillRollNote(onset: hostBeat, length: gateLen, pitch: pr.pitch, vel: max(1, min(127, v)), land: isLandStep))
            }
            if notesLive, info.rawIsHit {
                for p in euclideousNotesHitPitches(line: line, pool: pool, cfg: cfg, tick: t, lane: lane, oct: notesOct, isRestHit: isRestHit, ranks: ranks, poly: nil) where (0...127).contains(p) {
                    out.notes.append(EuclideousFillRollNote(onset: hostBeat, length: max(0.002, cfg.sub * notesGate), pitch: p, vel: notesVel, stack: true))
                }
            }
        }
        t += 1
    }
    // ---- the FILL region ----
    guard let rg = region else { return out }
    out.regionLo = rg.F; out.regionHi = rg.E
    if rg.breakOn { out.breakLo = rg.E - rg.D / 4; out.breakHi = rg.E }
    let N = euclideousFillCount(rg, origin: originBeat, sub: cfg.sub)
    guard N > 0 else { return out }
    var shuf = [Int](repeating: 0, count: euclideousFillReverseCap)
    if rg.order == .shuffle, euclideousFillOrderBuffered(rg, count: N) { euclideousFillShuffle(lane: lane, bar: b, count: N, into: &shuf) }
    let h = (N + 1) / 2
    var flatRiff = 0, flatStack = 0   // the FLAT latch, in time order — exactly the Router's rule
    for s in 0..<N {
        let contentK = euclideousFillSourceStep(rg, origin: originBeat, sub: cfg.sub, count: N, slot: s, shuffle: rg.order == .shuffle ? shuf : nil)
        let tick = contentK + originTick
        let hostBeat = euclideousFillSlotHostBeat(rg, origin: originBeat, sub: cfg.sub, slot: s)
        let slotLen = euclideousFillStepHostLength(rg, origin: originBeat, sub: cfg.sub, slot: s)
        let broken = euclideousFillBreakDrops(rg, hostBeat: hostBeat)
        let hitsActive = rg.hits != .keep
        let info = euclideousLaneChainTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: tick,
                                           chains: cfg.chains, legacySpanBeats: cfg.spanBeats, advanceStep: cfg.advanceStep || hitsActive, hostBeat: hostBeat)
        let sounds: Bool
        switch rg.hits {   // §2.2 (BUILD: k < h as KEEP, k ≥ h sounds — the as-built ALL/FLIP advance mechanism)
        case .keep: sounds = info.rawIsHit
        case .all: sounds = true
        case .flip: sounds = !info.rawIsHit
        case .build: sounds = s >= h ? true : info.rawIsHit
        }
        guard sounds else { continue }
        let swell = euclideousFillSwellFactor(swell: rg.swell, slot: s, count: N)
        let odd = s % 2 == 1
        let offset = euclideousFillRankOffset(ranks: rg.ranks, slot: s, count: N, shape: rg.shape)
        let isRestHit = rawRankAt(info.advOrd) < 1
        if riffLive {
            // latch FLAT's first sounding riff rank (time order), then the voice(s) through the mode
            if rg.notes == .flat, flatRiff == 0 {
                let rr = rawRankAt(info.advOrd)
                if rr >= 1 { let q = (cfg.invert ? 9 - rr : rr) + cfg.transpose; if q >= 1 { flatRiff = q } }
            }
            let vel = max(1, min(127, Int((Double(baseVel) * swell).rounded())))
            let rollN = max(1, euclideousFillRollCount(roll: rg.roll, slot: s, count: N))
            let subLen = slotLen / Double(rollN)
            // CHORD = up to 3 voices; others 1 (PEDAL's odd slot replaces the voice; the engine's addPitch dedupe is mirrored by a tiny scan)
            var voices = 0
            var struck0 = 0, struck1 = 0, struck2 = 0
            func addVoice(_ p: Int) { if voices == 0 { struck0 = p } else if voices == 1 { struck1 = p } else { struck2 = p }; voices += 1 }
            if let pr = pitchAt(advOrd: info.advOrd, extra: offset, flatRank: flatRiff, mode: rg.notes, odd: odd) {
                addVoice(pr.pitch)
                if rg.notes == .chord {
                    let q0r = rawRankAt(info.advOrd)
                    if q0r >= 1 {
                        let q0 = (cfg.invert ? 9 - q0r : q0r) + cfg.transpose
                        for extraRank in [q0 + offset + 2, q0 + offset + 4] {
                            if let p = riffResolve(rank: extraRank, oct: riffOct, n: pool.count, wrap: .fold, asc: { pool[$0] }), (0...127).contains(p),
                               p != struck0, voices < 2 || p != struck1 { addVoice(p) }
                        }
                    }
                }
            }
            var vi = 0
            while vi < voices {
                let p = vi == 0 ? struck0 : (vi == 1 ? struck1 : struck2)
                for r in 0..<rollN {
                    out.notes.append(EuclideousFillRollNote(onset: hostBeat + Double(r) * subLen, length: max(0.002, subLen * cfg.gate), pitch: p, vel: vel, fill: true, broken: broken))
                }
                vi += 1
            }
        }
        if notesLive {
            let sv = max(1, min(127, Int((Double(notesVel) * swell).rounded())))
            var pedalDone = false
            for p0 in euclideousNotesHitPitches(line: line, pool: pool, cfg: cfg, tick: tick, lane: lane, oct: notesOct, isRestHit: isRestHit, ranks: ranks, poly: nil) {
                // the stack voices through the mode (rank-space transform mirrored in pitch form: the engine transforms the RANK;
                // here each voice's rank is recovered from the play list — use the engine's own voice fn on the voice's rank)
                var pitches = [p0]
                if rg.notes != .riff {
                    // recover the voice's rank: the stack resolves rank r at notesOct — invert riffResolve by scanning 1…pool.count+16
                    var vr = 0
                    var rr = 1
                    while rr <= pool.count * 3 { if riffResolve(rank: rr, oct: notesOct, n: pool.count, wrap: .fold, asc: { pool[$0] }) == p0 { vr = rr; break }; rr += 1 }
                    if vr > 0 {
                        if rg.notes == .flat, flatStack == 0 { flatStack = vr }
                        let fv = euclideousFillNotesVoice(mode: rg.notes, q0: vr, offset: offset, flatRank: flatStack, oddSlot: odd)
                        if fv.isPedal { if pedalDone { continue }; pedalDone = true }
                        pitches = []
                        var fvi = 0
                        while fvi < fv.count {
                            let fr = fvi == 0 ? fv.r0 : (fvi == 1 ? fv.r1 : fv.r2)
                            if fr > 0, let p = riffResolve(rank: fr, oct: notesOct, n: pool.count, wrap: .fold, asc: { pool[$0] }) {
                                let pp = p + (fv.octUp ? 12 : 0)
                                if (0...127).contains(pp), !pitches.contains(pp) { pitches.append(pp) }
                            }
                            fvi += 1
                        }
                    }
                }
                for p in pitches where (0...127).contains(p) {
                    out.notes.append(EuclideousFillRollNote(onset: hostBeat, length: max(0.002, slotLen * notesGate), pitch: p, vel: sv, fill: true, broken: broken, stack: true))
                }
            }
        }
    }
    return out
}

/// The riff notes a lane's fill plays across bars [fromBar, toBar). Empty when the lane does not fill (neutral / unlit / no pool).
func euclideousFillPreviewNotes(cfg: EuclideousWalkLaneConfig, line: EuclidLine, lane: Int,
                                pool: [Int], riffOct: Int, baseVel: Int, ranks: [Int],
                                fromBar: Int, toBar: Int, beatsPerBar: Double, originBeat: Double) -> [EuclideousFillPreviewNote] {
    guard line.usesFill, cfg.sub > 0, beatsPerBar > 0, !pool.isEmpty, !ranks.isEmpty, toBar > fromBar else { return [] }
    let plan = EuclideousFillPlan(line: line, lane: lane, originBeat: originBeat, beatsPerBar: beatsPerBar, sub: cfg.sub)
    guard plan.active else { return [] }
    let cycleLen = euclidCycleLen(cfg.dir, n: cfg.n)
    let originTick = Int64((originBeat / cfg.sub).rounded(.down))
    var out: [EuclideousFillPreviewNote] = []
    var shuf = [Int](repeating: 0, count: euclideousFillReverseCap)
    // A PITCH-borrowing lane (SHADOW / ECHO) plays its source's notes, not its own riff / stack — not mirrored here.
    let borrowing = line.listenPitchResolved == .shadow || line.listenPitchResolved == .echo
    let riffLive = cfg.riffOn && !borrowing
    // NOTES-layer (stack) context — mirrors laneGhostPlans: live only when the layer is on and not borrowing.
    let notesLive = euclideousNotesLayerIsOn(line) && !borrowing
    let notesOct = max(-2, min(2, line.octaveResolved))
    let notesGate = line.notesGateResolved
    let notesVel = line.notesVelocityResolved

    // The grid rank the walk reads at an ordinal (0 = a rest). `extra` is the RANKS-SHAPE climb.
    func rawRankAt(_ advOrd: Int64) -> Int {
        let playedStep = euclideousRiffColumn(ordinal: advOrd, every: cfg.every, direction: cfg.riffDir, length: cfg.length, stride: cfg.stride, shift: cfg.rotate, seed: cfg.seed, columns: cfg.columns)
        return (playedStep >= 0 && playedStep < ranks.count) ? ranks[playedStep] : 0
    }
    // The riff pitch at a walk ordinal (nil = a rest or out of MIDI range).
    func pitchAt(advOrd: Int64, extra: Int) -> Int? {
        let rawRank = rawRankAt(advOrd)
        guard rawRank >= 1 else { return nil }
        let rank = (cfg.invert ? 9 - rawRank : rawRank) + cfg.transpose + extra
        guard rank >= 1, let p = riffResolve(rank: rank, oct: riffOct, n: pool.count, wrap: .fold, asc: { pool[$0] }), (0...127).contains(p) else { return nil }
        return p
    }

    for b in fromBar..<toBar {
        guard let region = plan.region(bar: b) else { continue }
        let N = euclideousFillCount(region, origin: originBeat, sub: cfg.sub)
        guard N > 0 else { continue }
        let hitsActive = region.hits != .keep
        if region.order == .shuffle, euclideousFillOrderBuffered(region, count: N) { euclideousFillShuffle(lane: lane, bar: b, count: N, into: &shuf) }
        for s in 0..<N {
            let contentK = euclideousFillSourceStep(region, origin: originBeat, sub: cfg.sub, count: N, slot: s, shuffle: region.order == .shuffle ? shuf : nil)
            let tick = contentK + originTick
            let hostBeat = euclideousFillSlotHostBeat(region, origin: originBeat, sub: cfg.sub, slot: s)
            let slotLen = euclideousFillStepHostLength(region, origin: originBeat, sub: cfg.sub, slot: s)
            let broken = euclideousFillBreakDrops(region, hostBeat: hostBeat)
            let info = euclideousLaneChainTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: tick,
                                               chains: cfg.chains, legacySpanBeats: cfg.spanBeats, advanceStep: cfg.advanceStep || hitsActive, hostBeat: hostBeat)
            let rawIsHit = region.hits == .all ? true : (region.hits == .flip ? !info.rawIsHit : info.rawIsHit)   // §2.3
            guard rawIsHit else { continue }                                                                      // no rhythm hit (SKIP; TIE / REPEAT not previewed)
            let swell = euclideousFillSwellFactor(swell: region.swell, slot: s, count: N)
            let isRestHit = rawRankAt(info.advOrd) < 1                                                            // the riff column is a rest → the NOTES layer's RESTS mode fires
            // RIFF layer — a note per ROLL strike (nil when the column is a grid rest; skipped when the riff is off / borrowed)
            if riffLive, let pitch = pitchAt(advOrd: info.advOrd, extra: euclideousFillRankOffset(ranks: region.ranks, slot: s, count: N, shape: region.shape)) {
                let vel = max(1, min(127, Int((Double(baseVel) * swell).rounded())))
                let rollN = max(1, euclideousFillRollCount(roll: region.roll, slot: s, count: N))
                let subLen = slotLen / Double(rollN)
                for r in 0..<rollN {
                    out.append(EuclideousFillPreviewNote(bar: b, onset: hostBeat + Double(r) * subLen, length: max(0.002, subLen * cfg.gate), pitch: pitch, vel: vel, broken: broken))
                }
            }
            // NOTES (stack) layer — the same euclideousNotesHitPitches the Router's body runs, struck at the hit's onset (WHEN / CHANCE / the play list inside); the swell scales it like the riff
            if notesLive {
                let sv = max(1, min(127, Int((Double(notesVel) * swell).rounded())))
                for p in euclideousNotesHitPitches(line: line, pool: pool, cfg: cfg, tick: tick, lane: lane, oct: notesOct, isRestHit: isRestHit, ranks: ranks, poly: nil) where (0...127).contains(p) {
                    out.append(EuclideousFillPreviewNote(bar: b, onset: hostBeat, length: max(0.002, slotLen * notesGate), pitch: p, vel: sv, broken: broken, stack: true))
                }
            }
        }
        // §2.6 LAND: the rejoin accent note at E (a ×1 step, vel ×1.3, gate ×2, forced strike) — only when the riff is live and the walk's column there has a rank.
        if region.land, riffLive {
            let tickE = Int64((region.E / cfg.sub + 1e-9).rounded(.down))
            let infoE = euclideousLaneChainTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: tickE,
                                                chains: cfg.chains, legacySpanBeats: cfg.spanBeats, advanceStep: cfg.advanceStep, hostBeat: region.E)
            if let pitch = pitchAt(advOrd: infoE.advOrd, extra: 0) {
                out.append(EuclideousFillPreviewNote(bar: b, onset: region.E, length: max(0.002, cfg.sub * cfg.gate * 2), pitch: pitch,
                                                     vel: max(1, min(127, Int((Double(baseVel) * 1.3).rounded()))), land: true))
            }
        }
    }
    return out
}

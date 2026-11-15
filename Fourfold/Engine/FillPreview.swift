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

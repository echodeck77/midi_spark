//  RestartSchedule.swift — RESTART UNITS ferry (2026-11-04): the ONE pure schedule every restart consumer reads (Foundation only; built on the MAIN thread, read by the render thread — which never simulates, never allocates).
//
//  Restart beats can no longer be closed forms: a RHYTHM chain may count another lane's passes or riff completions, a MELODY chain bars, hits or another lane's passes, and WITH RHYTHM welds the two. So the beats come from a
//  deterministic simulation from beat 0 over the four lanes (§4), reduced to per-lane tables (§5): the rhythm restarts (beat, origin tick, cumulative passes and hits), the melody restarts, the riff completions, and — when the
//  joint state repeats at a bar line — one period to wrap round. Lanes are simulated per CONNECTED COMPONENT of the source graph (lanes outside it never read each other, so the result is identical to a joint sweep — and an
//  independent lane keeps its own short period). Engine conventions are reproduced exactly: a restart's origin TICK is `euclideousOriginTick` (floor, no ε); hit counts follow `euclideousChainHitsBefore`'s convention
//  (`cumulative at the segment's origin tick + pattern hits since it`); a pass is counted `ceil(length / lap − ε)` to a segment; comparisons use ε 1e-9 only where the closed forms do.

import Foundation

private let schedEps = 1e-9

/// A schedule beat on the lane's tick grid: floor with ε (in ticks). A restart that falls exactly on a tick start is a float product (`(t + 1) × sub`, `rhythmBeat + j × lap`) that can land a hair BELOW the integer for a triplet step; a plain floor then puts the origin one tick early
/// and the new pass enters at its second step, swallowing the downbeat (adversarial review 2026-11-04). Used for every beat the schedule hands out; the closed forms (a pre-feature lane) keep their own floor, so old sound is untouched.
@inline(__always) func euclideousScheduleTick(_ beat: Double, sub: Double) -> Int64 {
    guard sub > 0, beat.isFinite else { return 0 }
    return Int64(((beat / sub) + schedEps).rounded(.down))
}

// MARK: - the inputs (Hashable: the memo key)

struct EuclideousScheduleLaneInput: Hashable {
    var sub: Double
    /// Is the pattern's tick `raw` (0 ..< cycleLen) a hit — already read through the lane's direction (and tick-space timing layout), exactly as the engine reads it.
    var rawHit: [Bool]
    /// One full riff cycle in the riff ordinal's units (hits under ADV HIT, ticks under ADV STEP): the walk's period × ADVANCE EVERY.
    var riffCycle: Int64 = 1
    var advanceStep = false
    var rhythmLinks: [UInt8] = []
    var rhythmUnit: EuclideousRhythmRestartUnit = .bar
    var rhythmSource = 0
    var melodyLinks: [UInt8] = []
    var melodyUnit: EuclideousMelodyRestartUnit = .pass
    var melodySource = 0
    var withRhythm = false
    var cycleLen: Int { max(1, rawHit.count) }
    var lapBeats: Double { Double(cycleLen) * sub }
    var rhythmChain: EuclideousRestartChain { .from(rhythmLinks, hit: false) }
    var melodyChain: EuclideousRestartChain { .from(melodyLinks, hit: melodyUnit == .hit) }
    var rhythmActive: Bool { !rhythmLinks.isEmpty }
    var melodyActive: Bool { !melodyLinks.isEmpty }
    /// Does this lane's melody ever restart (a chain, or WITH RHYTHM over an active rhythm chain)?
    var melodyRestarts: Bool { melodyActive || (withRhythm && rhythmActive) }
    /// Can the closed forms express this lane's restarts (RHYTHM BAR, MELODY own PASS, no WITH RHYTHM — every setting that existed before the ferry)? `ownLane` is the lane's own index.
    func closedFormExpressible(ownLane: Int) -> Bool {
        (!rhythmActive || rhythmUnit == .bar) && (!melodyActive || (melodyUnit == .pass && melodySource == ownLane)) && !withRhythm
    }
    /// The lane this lane reads through its RHYTHM chain / MELODY chain (nil = none).
    var rhythmReads: Int? { rhythmActive && rhythmUnit != .bar ? rhythmSource : nil }
    var melodyReads: Int? { melodyActive && melodyUnit == .pass ? melodySource : nil }
}
struct EuclideousScheduleInputs: Hashable {
    var lanes: [EuclideousScheduleLaneInput]
    var barBeats: Double
}

/// A lane's input from the lines: the pattern the engine ACTUALLY plays (a COPY / FILL follower reads the source's, in tick space when it has timing), its riff cycle, and its restart settings (a borrowing lane reads the SOURCE's
/// chains with its own lap, as `Router.runEuclidLine` does — the donor's own-lane references become the follower's own).
func euclideousScheduleLaneInput(lane: Int, lines: [EuclidLine], defaultRateBeats: Double, riffColumns: Int) -> EuclideousScheduleLaneInput? {
    guard lane >= 0, lane < lines.count, let eff = euclideousEffectiveHitPattern(lane: lane, lines: lines, defaultRateBeats: defaultRateBeats) else { return nil }
    let L = lines[lane]
    var buf = eff.buf, n = eff.n
    var dir = eff.followsPartner ? EuclidDir.fwd : L.directionResolved
    if eff.hasTiming {
        var tc = [Bool](repeating: false, count: 32), td = [Double](repeating: 0, count: 32)
        let cl = euclideousHitLayoutInto(cells: eff.buf, micro: eff.micro, fraction: eff.fraction, n: eff.n, dir: dir, outCells: &tc, outDelay: &td)
        buf = Array(tc[0..<cl]); n = cl; dir = .fwd
    }
    let cycleLen = euclidCycleLen(dir, n: n)
    var raw = [Bool](repeating: false, count: cycleLen)
    for r in 0..<cycleLen { let i = euclidReadIndex(r, n: n, dir: dir); raw[r] = i >= 0 && i < buf.count ? buf[i] : false }
    let length = riffColumns == 8 ? L.riffLengthResolved : L.riffLengthResolved(columns: riffColumns)
    let period = euclideousFXWalkPeriod(dir: L.euclideousRiffDirResolved, length: length, stride: L.riffStrideResolved)
    var inp = EuclideousScheduleLaneInput(sub: max(1e-6, eff.rateBeats), rawHit: raw, riffCycle: Int64(max(1, period)) * Int64(max(1, L.riffAdvanceEveryResolved)), advanceStep: L.riffAdvanceStepResolved)
    // restart settings: the donor's under COPY / FILL
    let donorIdx = eff.followsPartner ? (euclideousRhythmBorrowPartner(lane: lane, lines: lines) ?? lane) : lane
    let donor = lines[donorIdx]
    guard donor.usesRestartChains else { return inp }
    let s = euclideousRestartSettings(line: donor, lane: donorIdx)
    func lanewise(_ v: Int) -> Int { v == donorIdx ? lane : v }   // the donor's references to itself are the follower's own
    if s.rhythmActive {
        let src = lanewise(s.rhythmSource)
        let valid = src >= 0 && src < min(4, lines.count) && !(s.rhythmUnit == .pass && src == lane)
        if valid { inp.rhythmLinks = s.rhythm.links; inp.rhythmUnit = s.rhythmUnit; inp.rhythmSource = src }
    }
    if s.melodyActive {
        let src = lanewise(s.melodySource)
        if src >= 0 && src < min(4, lines.count) { inp.melodyLinks = s.melody.links; inp.melodyUnit = s.melodyUnit; inp.melodySource = src }
    }
    inp.withRhythm = s.withRhythm && inp.rhythmActive
    return inp
}
func euclideousScheduleInputs(lines: [EuclidLine], barBeats: Double, defaultRateBeats: Double, riffColumns: Int) -> EuclideousScheduleInputs {
    var out: [EuclideousScheduleLaneInput] = []
    for i in 0..<min(4, lines.count) {
        out.append(euclideousScheduleLaneInput(lane: i, lines: lines, defaultRateBeats: defaultRateBeats, riffColumns: riffColumns)
                   ?? EuclideousScheduleLaneInput(sub: max(1e-6, defaultRateBeats), rawHit: [false, false]))
    }
    return EuclideousScheduleInputs(lanes: out, barBeats: max(1e-6, barBeats))
}
/// Lanes whose restarts the simulation cannot own: a lane engaged in an ANSWER cycle or trade plays a DIFFERENT effective line in phase B (a runtime latch no pure simulation has), so the Router keeps the closed forms for it.
func euclideousScheduleEngagedLanes(lines: [EuclidLine]) -> UInt8 {
    var m: UInt8 = 0
    let n = min(4, lines.count)
    for i in 0..<n {
        let l = lines[i]
        if euclideousAnswerHasCycle(l) { m |= UInt8(1) << UInt8(i) }
        if l.answerTradeOnResolved {
            m |= UInt8(1) << UInt8(i)
            let w = l.answerTradeWithResolved(ownLane: i)
            if w >= 0 && w < n { m |= UInt8(1) << UInt8(w) }
        }
    }
    for i in 0..<n where m & (UInt8(1) << UInt8(i)) != 0 {
        if let p = euclideousAnswerPairPartner(lane: i, lines: lines), p >= 0, p < n { m |= UInt8(1) << UInt8(p) }
    }
    return m
}

// MARK: - one lane's tables

/// Immutable, built on the main thread. Arrays are sorted by beat; index 0 of the restart tables is beat 0 (a restart of both chains of every lane). When `period > 0` the tables hold the prefix and exactly ONE period
/// (restarts with beat < prefixEnd + period): everything later is the period repeated, with the per-period increments.
final class EuclideousLaneScheduleData {
    let sub: Double, cycleLen: Int, lapBeats: Double, barBeats: Double
    let cycleHits: Int64
    let rawHit: [Bool]
    /// A lane whose RHYTHM chain counts bars (or has none) counts its hits with the closed form `euclideousChainHitsBefore` — which models the cycle as a FIXED number of ticks, so for a rate whose bar is not a whole number of steps (a dotted
    /// 1/8 against a 4-beat bar) it drifts from the restarts' true ticks; the engine has always played that count, so the schedule reproduces it. A lane counting another lane's passes or riffs has no closed form: it counts true hits.
    let hitsViaClosedForm: Bool
    let closedRhythm: EuclideousRestartChain
    /// prefix[r] = pattern hits among raws 0 ..< r (r ≤ cycleLen).
    let prefix: [Int32]
    let riffCycle: Int64
    let advanceStep: Bool
    // rhythm restarts
    let rBeat: [Double], rTick: [Int64], rPass: [Int64], rHits: [Int64]
    // melody restarts
    let mBeat: [Double], mTick: [Int64], mHits: [Int64]
    // riff completions (after beat 0)
    let fBeat: [Double]
    // the periodic wrap
    let prefixEnd: Double, period: Double
    let dPass: Int64, dHits: Int64, dTick: Int64, dRiff: Int64
    let rPeriodStart: Int, mPeriodStart: Int, fPeriodStart: Int
    /// Non-periodic: the tables are complete for beats below this (the main thread extends it ahead of the playhead); periodic: +∞.
    let coveredUntil: Double
    let rhythmRestarts: Bool, melodyRestarts: Bool, melodyEveryPass: Bool
    /// Can the closed-form reference functions express this lane's restarts (RHYTHM BAR, MELODY own PASS, no WITH RHYTHM)? Anything else only the schedule knows.
    let closedFormExpressible: Bool
    let id: Int

    private static var nextId = 0
    private static let idLock = NSLock()
    init(sub: Double, cycleLen: Int, barBeats: Double, rawHit: [Bool], riffCycle: Int64, advanceStep: Bool,
         rBeat: [Double], rTick: [Int64], rPass: [Int64], rHits: [Int64], mBeat: [Double], mTick: [Int64], mHits: [Int64], fBeat: [Double],
         prefixEnd: Double, period: Double, dPass: Int64, dHits: Int64, dTick: Int64, dRiff: Int64, rPeriodStart: Int, mPeriodStart: Int, fPeriodStart: Int,
         coveredUntil: Double, rhythmRestarts: Bool, melodyRestarts: Bool, melodyEveryPass: Bool, closedFormExpressible: Bool = true, hitsViaClosedForm: Bool = true, closedRhythm: EuclideousRestartChain = .free) {
        self.sub = sub; self.cycleLen = cycleLen; self.lapBeats = Double(cycleLen) * sub; self.barBeats = barBeats
        var pre = [Int32](repeating: 0, count: cycleLen + 1)
        for r in 0..<cycleLen { pre[r + 1] = pre[r] + (r < rawHit.count && rawHit[r] ? 1 : 0) }
        self.prefix = pre; self.cycleHits = Int64(pre[cycleLen]); self.rawHit = rawHit
        self.hitsViaClosedForm = hitsViaClosedForm; self.closedRhythm = closedRhythm
        self.riffCycle = max(1, riffCycle); self.advanceStep = advanceStep
        self.rBeat = rBeat; self.rTick = rTick; self.rPass = rPass; self.rHits = rHits
        self.mBeat = mBeat; self.mTick = mTick; self.mHits = mHits; self.fBeat = fBeat
        self.prefixEnd = prefixEnd; self.period = period
        self.dPass = dPass; self.dHits = dHits; self.dTick = dTick; self.dRiff = dRiff
        self.rPeriodStart = rPeriodStart; self.mPeriodStart = mPeriodStart; self.fPeriodStart = fPeriodStart
        self.coveredUntil = coveredUntil
        self.rhythmRestarts = rhythmRestarts; self.melodyRestarts = melodyRestarts; self.melodyEveryPass = melodyEveryPass; self.closedFormExpressible = closedFormExpressible
        EuclideousLaneScheduleData.idLock.lock(); EuclideousLaneScheduleData.nextId += 1; self.id = EuclideousLaneScheduleData.nextId; EuclideousLaneScheduleData.idLock.unlock()
    }
    /// Pattern hits in the first `m` ticks of the cyclic pattern (any integer `m`).
    @inline(__always) func pat(_ m: Int64) -> Int64 {
        let cl = Int64(cycleLen)
        let q = floorDiv(m, cl)
        return q * cycleHits + Int64(prefix[Int(m - q * cl)])
    }
}

/// A restart record as the readers hand it back (already shifted into the periodic extension).
struct EuclideousRestartRecord: Equatable {
    var beat: Double
    var tick: Int64
    var pass: Int64
    var hits: Int64
}

struct EuclideousLaneSchedule: Equatable {
    let data: EuclideousLaneScheduleData
    static func == (a: EuclideousLaneSchedule, b: EuclideousLaneSchedule) -> Bool { a.data === b.data }

    var rhythmRestarts: Bool { data.rhythmRestarts }
    var melodyRestarts: Bool { data.melodyRestarts }
    var melodyEveryPass: Bool { data.melodyEveryPass }
    /// Does the table answer for `beat`? (A non-periodic window ends; a periodic one is unbounded.)
    func covers(_ beat: Double) -> Bool { data.period > 0 || beat < data.coveredUntil - schedEps }

    // ── the periodic tables: the prefix holds every restart with beat ≤ prefixEnd (b_j); the period part (from `periodStart`) holds those in (b_j, b_k] — RIGHT-closed, because the state at b_j is the state AFTER that instant's events, so the
    //    restart AT b_j (beat 0's implicit one included) is the past, and the restart at b_k is the first of the next repetition's mirror image.
    private func pred(_ beats: [Double], periodStart: Int, x: Double, tol: Double) -> (Int, Int64)? {
        guard !beats.isEmpty, x.isFinite else { return nil }
        func last(atOrBelow v: Double, from lo: Int) -> Int? {
            var a = lo, b = beats.count
            while a < b { let mid = (a + b) / 2; if beats[mid] <= v + tol { a = mid + 1 } else { b = mid } }
            return a > lo ? a - 1 : nil
        }
        let p = data.period
        if p <= 0 || x <= data.prefixEnd + p + tol { return last(atOrBelow: x, from: 0).map { ($0, 0) } }
        let kd = ((x - (data.prefixEnd + p) - tol) / p).rounded(.up)
        let k = Int64(kd), xr = x - kd * p
        if let i = last(atOrBelow: xr, from: periodStart) { return (i, k) }             // inside this repetition
        if periodStart < beats.count { return (beats.count - 1, k - 1) }                // the previous repetition's last
        return last(atOrBelow: xr, from: 0).map { ($0, 0) }                             // the period holds none: the prefix's last stays
    }
    private func succ(_ beats: [Double], periodStart: Int, after x: Double, tol: Double) -> Double? {
        guard !beats.isEmpty, x.isFinite else { return nil }
        func first(after v: Double, from lo: Int) -> Int? {
            var a = lo, b = beats.count
            while a < b { let mid = (a + b) / 2; if beats[mid] <= v + tol { a = mid + 1 } else { b = mid } }
            return a < beats.count ? a : nil
        }
        let p = data.period
        if let i = first(after: x, from: 0) { return beats[i] }                        // anything left in the table
        guard p > 0, periodStart < beats.count else { return nil }
        let end = data.prefixEnd + p
        let kd = x <= end + tol ? 0.0 : ((x - end - tol) / p).rounded(.up)
        let xr = x - kd * p
        if let i = first(after: xr, from: periodStart) { return beats[i] + kd * p }
        return beats[periodStart] + (kd + 1) * p
    }

    // ── the readers (§5.1)
    func rhythmRecord(atOrBefore beat: Double) -> EuclideousRestartRecord {
        guard let (i, k) = pred(data.rBeat, periodStart: data.rPeriodStart, x: beat, tol: 1e-9) else { return EuclideousRestartRecord(beat: 0, tick: 0, pass: 0, hits: 0) }
        return EuclideousRestartRecord(beat: data.rBeat[i] + Double(k) * data.period, tick: data.rTick[i] + k * data.dTick, pass: data.rPass[i] + k * data.dPass, hits: data.rHits[i] + k * data.dHits)
    }
    func nextRhythmRestart(after beat: Double) -> Double? { succ(data.rBeat, periodStart: data.rPeriodStart, after: beat, tol: 1e-9) }
    func melodyRecord(atOrBefore beat: Double) -> EuclideousRestartRecord {
        guard let (i, k) = pred(data.mBeat, periodStart: data.mPeriodStart, x: beat, tol: 1e-9) else { return EuclideousRestartRecord(beat: 0, tick: 0, pass: 0, hits: 0) }
        let tick = data.mTick[i] + k * data.dTick
        return EuclideousRestartRecord(beat: data.mBeat[i] + Double(k) * data.period, tick: tick, pass: 0, hits: hitsBefore(tick: tick))   // hits as the lane counts them (the closed form's drift included)
    }
    func nextMelodyRestart(after beat: Double) -> Double? { succ(data.mBeat, periodStart: data.mPeriodStart, after: beat, tol: 1e-9) }
    /// §1.5 / `euclideousPassIndex`: with no rhythm restart the plain `floor(beat / lap)` (no ε — the FREE closed form); otherwise the segment's cumulative passes plus whole laps since its restart.
    func passIndex(beat: Double) -> Int64 {
        guard data.lapBeats > 0, beat.isFinite else { return 0 }
        if !data.rhythmRestarts { return Int64((beat / data.lapBeats).rounded(.down)) }
        let r = rhythmRecord(atOrBefore: beat)
        return r.pass + Int64(((beat - r.beat + schedEps) / data.lapBeats).rounded(.down))
    }
    /// §1.5 / `euclideousPassStart`: the beat pass `q` starts at.
    func passStart(_ q: Int64) -> Double {
        guard data.lapBeats > 0 else { return 0 }
        if !data.rhythmRestarts { return Double(q) * data.lapBeats }
        let n = data.rBeat.count
        var k: Int64 = 0
        var qr = q
        if data.period > 0, data.dPass > 0, data.rPeriodStart < n {
            let firstPass = data.rPass[data.rPeriodStart]
            if q >= firstPass + data.dPass { k = floorDiv(q - firstPass, data.dPass); qr = q - k * data.dPass }   // reduce by whole periods
        }
        var lo = 0, hi = n
        while lo < hi { let mid = (lo + hi) / 2; if data.rPass[mid] <= qr { lo = mid + 1 } else { hi = mid } }
        let i = max(0, lo - 1)
        return data.rBeat[i] + Double(k) * data.period + Double(qr - data.rPass[i]) * data.lapBeats
    }
    /// `euclideousChainHitsBefore`'s convention: cumulative hits at the last rhythm restart whose ORIGIN TICK ≤ `m`, plus the pattern hits since that tick.
    func hitsBefore(tick m: Int64) -> Int64 {
        if data.hitsViaClosedForm {
            return euclideousChainHitsBefore(m, rhythm: data.closedRhythm, barBeats: data.barBeats, sub: data.sub, buf: data.rawHit, n: data.cycleLen, dir: .fwd, cycleLen: data.cycleLen, cycleHits: Int(data.cycleHits))
        }
        let n = data.rTick.count
        guard n > 0 else { return data.pat(m) }
        var k: Int64 = 0
        var mr = m
        if data.period > 0, data.dTick > 0, data.rPeriodStart < n {
            let first = data.rTick[data.rPeriodStart]
            if m >= first + data.dTick { k = floorDiv(m - first, data.dTick); mr = m - k * data.dTick }   // reduce by whole periods
        }
        var lo = 0, hi = n
        while lo < hi { let mid = (lo + hi) / 2; if data.rTick[mid] <= mr { lo = mid + 1 } else { hi = mid } }
        guard lo > 0 else { return data.pat(m) }
        let i = lo - 1
        return data.rHits[i] + k * data.dHits + data.pat(mr - data.rTick[i])
    }
    /// How many riff completions (natural and restarted) happened strictly before `beat`.
    func riffCompletions(before beat: Double) -> Int64 {
        let f = data.fBeat
        guard !f.isEmpty, beat.isFinite else { return 0 }
        let p = data.period
        var kd = 0.0
        var xr = beat
        if p > 0, beat > data.prefixEnd + p + schedEps {
            kd = ((beat - (data.prefixEnd + p) - schedEps) / p).rounded(.up)
            xr = beat - kd * p
        }
        var lo = 0, hi = f.count
        while lo < hi { let mid = (lo + hi) / 2; if f[mid] < xr - schedEps { lo = mid + 1 } else { hi = mid } }
        return Int64(lo) + Int64(kd) * data.dRiff
    }
    /// The riff ordinal count at a tick (ADV HIT: hits since the melody origin; ADV STEP: ticks) — what `advOrd + 1` is at that tick.
    func riffCount(upToTick u: Int64, melodyRecord m: EuclideousRestartRecord) -> Int64 {
        data.advanceStep ? u - m.tick : hitsBefore(tick: u) - m.hits
    }

    // ── CHORDS PAGE ferry (2026-11-04) §3.6: cumulative count + k-th-event beat for RHYTHM RESTARTS and RIFF
    //    COMPLETIONS, so `chordColumn` can advance/restart a chord grid on a lane's loops or riffs with a binary
    //    search (no event loop, no allocation). They mirror `riffCompletions` / `passStart`'s own periodic wrap —
    //    the period part holds one repetition and each whole period adds `count − periodStart` events. Verified
    //    against a brute-force walk of `nextRhythmRestart` / the completion list in `RestartScheduleTests`.

    /// How many rhythm restarts happened at or before `beat` (beat 0's implicit restart INCLUDED, so the count at
    /// beat 0 is 1). The number of restart LOOP events in (0, beat] is therefore `rhythmRestartCount(..beat) − 1`.
    func rhythmRestartCount(atOrBefore beat: Double) -> Int64 {
        let rb = data.rBeat
        guard !rb.isEmpty else { return 0 }
        let p = data.period
        var kd = 0.0, xr = beat
        if p > 0, beat > data.prefixEnd + p + schedEps {
            kd = ((beat - (data.prefixEnd + p) - schedEps) / p).rounded(.up)
            xr = beat - kd * p
        }
        var lo = 0, hi = rb.count
        while lo < hi { let mid = (lo + hi) / 2; if rb[mid] <= xr + schedEps { lo = mid + 1 } else { hi = mid } }
        let perPeriod = Int64(rb.count - data.rPeriodStart)
        return Int64(lo) + Int64(kd) * perPeriod
    }
    /// The beat of the `k`-th rhythm restart (0-indexed: restart 0 is beat 0, restart 1 is the first loop event).
    func rhythmRestartBeat(_ k: Int64) -> Double {
        let rb = data.rBeat
        guard !rb.isEmpty, k >= 0 else { return 0 }
        let rs = Int64(data.rPeriodStart), per = Int64(rb.count - data.rPeriodStart)
        if data.period > 0, per > 0, k >= rs {
            let into = k - rs
            return rb[Int(rs + into % per)] + Double(into / per) * data.period
        }
        return rb[Int(min(k, Int64(rb.count - 1)))]
    }
    /// How many riff completions happened at or before `beat` (INCLUSIVE — a completion AT `beat` counts, unlike
    /// `riffCompletions(before:)` which is strictly-before even with a +ε, its internal −schedEps cancelling it).
    /// §3.8: a RIFF advance takes effect at the completion's own beat, so `chordColumn` needs the inclusive count.
    func riffCompletionCount(atOrBefore beat: Double) -> Int64 {
        let f = data.fBeat
        guard !f.isEmpty else { return 0 }
        let p = data.period
        var kd = 0.0, xr = beat
        if p > 0, beat > data.prefixEnd + p + schedEps {
            kd = ((beat - (data.prefixEnd + p) - schedEps) / p).rounded(.up)
            xr = beat - kd * p
        }
        var lo = 0, hi = f.count
        while lo < hi { let mid = (lo + hi) / 2; if f[mid] <= xr + schedEps { lo = mid + 1 } else { hi = mid } }
        return Int64(lo) + Int64(kd) * data.dRiff
    }
    /// The beat of the `k`-th riff completion (0-indexed; completions start after beat 0, so k 0 is the first one).
    func riffCompletionBeat(_ k: Int64) -> Double {
        let f = data.fBeat
        guard !f.isEmpty, k >= 0 else { return 0 }
        let fs = Int64(data.fPeriodStart)
        if data.period > 0, data.dRiff > 0, k >= fs {
            let into = k - fs
            return f[Int(fs + into % data.dRiff)] + Double(into / data.dRiff) * data.period
        }
        return f[Int(min(k, Int64(f.count - 1)))]
    }
}

/// The four lanes' schedules plus what the Router needs to decide whether to read them.
final class EuclideousRestartScheduleSet {
    let lanes: [EuclideousLaneSchedule?]
    let barBeats: Double
    /// Bit i: lane i is engaged in an ANSWER cycle / trade — the Router keeps the closed forms for it.
    let engagedMask: UInt8
    /// `engagedMask` widened to whole components: a lane that counts an engaged lane's passes or riffs would read that lane's STATIC document pattern, which the cycle swaps at runtime — so it keeps the closed forms too (adversarial review 2026-11-04).
    let detachedMask: UInt8
    let key: EuclideousScheduleInputs
    /// Which lanes the simulation had to run for (a component with a restart in it); the rest are trivially "no restarts".
    let simulatedMask: UInt8
    /// Did any component fail to find a period within its window (→ the main thread extends it ahead of the playhead)?
    let windowed: Bool
    /// The first beat every simulated lane's tables are complete for (+∞ when every one is periodic).
    let coveredUntil: Double
    fileprivate let components: [(lanes: [Int], sim: EuclideousScheduleSim?)]
    /// Per lane: the bits of every lane in its connected component (the lanes whose patterns its restarts can depend on).
    let componentMasks: [UInt8]
    func componentMask(lane: Int) -> UInt8 { lane >= 0 && lane < componentMasks.count ? componentMasks[lane] : UInt8(1) << UInt8(max(0, min(7, lane))) }
    fileprivate init(lanes: [EuclideousLaneSchedule?], barBeats: Double, engagedMask: UInt8, key: EuclideousScheduleInputs, simulatedMask: UInt8, windowed: Bool, coveredUntil: Double,
                     components: [(lanes: [Int], sim: EuclideousScheduleSim?)]) {
        var widened = engagedMask
        for c in components { let m = c.lanes.reduce(UInt8(0)) { $0 | (UInt8(1) << UInt8($1)) }; if m & engagedMask != 0 { widened |= m } }
        self.detachedMask = widened
        self.componentMasks = (0..<4).map { lane in components.first { $0.lanes.contains(lane) }.map { $0.lanes.reduce(UInt8(0)) { $0 | (UInt8(1) << UInt8($1)) } } ?? UInt8(1) << UInt8(lane) }
        self.lanes = lanes; self.barBeats = barBeats; self.engagedMask = engagedMask; self.key = key; self.simulatedMask = simulatedMask; self.windowed = windowed; self.coveredUntil = coveredUntil; self.components = components
    }
    func lane(_ i: Int) -> EuclideousLaneSchedule? { i >= 0 && i < lanes.count ? lanes[i] : nil }
    /// §4.6: the same set with every non-periodic component simulated further, up to `bars` bar lines — what the main thread hands the Router as the playhead nears the end of the window. nil when nothing needs extending.
    func extended(untilBars bars: Int) -> EuclideousRestartScheduleSet? {
        guard windowed, coveredUntil < Double(bars) * barBeats else { return nil }
        for c in components { c.sim?.run(untilBars: bars) }
        return euclideousAssembleScheduleSet(key, engagedMask: engagedMask, components: components)
    }
}

// MARK: - the simulation (§4)

final class EuclideousScheduleSim {
    struct StateKey: Hashable { var v: [Int64] }
    struct BarSnap { var pass: [Int64]; var hits: [Int64]; var tick: [Int64]; var riff: [Int]; var rCount: [Int]; var mCount: [Int] }
    private struct LaneState {
        var inp: EuclideousScheduleLaneInput
        var rChain: EuclideousRestartChain, mChain: EuclideousRestartChain
        var viaClosedForm: Bool, closedRhythm: EuclideousRestartChain
        var prefix: [Int32]
        var cycleHits: Int64
        var cl: Int64
        var nextTick: Int64 = 0
        var O: Int64 = 0, cumAtO: Int64 = 0, rhythmBeat = 0.0, cumPassAtRestart: Int64 = 0
        var M: Int64 = 0, hitsAtM: Int64 = 0
        var passJ: Int64 = 1                      // the next natural pass is `passJ` laps after the rhythm restart
        var nextPassBeat: Double
        var pendingRiff = Double.infinity
        var rhythmCount: Int64 = 0, melodyCount: Int64 = 0
        var rBeat: [Double] = [0], rTick: [Int64] = [0], rPass: [Int64] = [0], rHits: [Int64] = [0]
        var mBeat: [Double] = [0], mTick: [Int64] = [0], mHits: [Int64] = [0]
        var fBeat: [Double] = []
        // per-instant flags
        var passEvent = false, riffEvent = false, rCounted = false, mCounted = false, rRestarted = false, mRestarted = false
        /// The EXACT beat of this instant's pass / riff event: a restart a pass or riff event causes happens at THAT beat (the closed forms' `passStart`), not at the grouped instant's earliest beat.
        var passBeat = 0.0, riffBeat = 0.0
        init(_ i: EuclideousScheduleLaneInput) {
            inp = i
            rChain = i.rhythmChain; mChain = i.melodyChain
            viaClosedForm = !i.rhythmActive || i.rhythmUnit == .bar
            closedRhythm = viaClosedForm && i.rhythmActive ? i.rhythmChain : .free
            cl = Int64(i.cycleLen)
            var pre = [Int32](repeating: 0, count: i.cycleLen + 1)
            for r in 0..<i.cycleLen { pre[r + 1] = pre[r] + (i.rawHit[r] ? 1 : 0) }
            prefix = pre; cycleHits = Int64(pre[i.cycleLen])
            nextPassBeat = i.lapBeats
        }
        func pat(_ m: Int64) -> Int64 { let q = floorDiv(m, cl); return q * cycleHits + Int64(prefix[Int(m - q * cl)]) }
        func hitsBefore(_ t: Int64) -> Int64 {
            if viaClosedForm { return euclideousChainHitsBefore(t, rhythm: closedRhythm, barBeats: barBeatsForHits, sub: inp.sub, buf: inp.rawHit, n: Int(cl), dir: .fwd, cycleLen: Int(cl), cycleHits: Int(cycleHits)) }
            return cumAtO + pat(t - O)
        }
        var barBeatsForHits = 4.0
        func rawHitAt(_ t: Int64) -> Bool { let loc = t - O; let r = Int(((loc % cl) + cl) % cl); return inp.rawHit[r] }
        func tickBeat(_ t: Int64) -> Double { Double(t) * inp.sub }
    }
    let globalLanes: [Int]
    let barBeats: Double
    private var L: [LaneState]
    private var nextBar = 1
    private(set) var barsDone = 0
    private(set) var periodFound: (j: Int, k: Int)? = nil
    private var seen: [StateKey: Int] = [:]
    private var snaps: [BarSnap] = []
    private var done = false
    /// The first beat the tables are NOT yet complete for.
    var coveredUntil: Double { Double(barsDone) * barBeats }

    private let detectPeriod: Bool
    init(globalLanes: [Int], inputs: [EuclideousScheduleLaneInput], barBeats: Double, detectPeriod: Bool = true) {
        self.globalLanes = globalLanes; self.barBeats = barBeats; self.detectPeriod = detectPeriod
        L = inputs.map { var l = LaneState($0); l.barBeatsForHits = barBeats; return l }
        processInstant(0)   // beat 0: both chains of every lane restart (implicitly); the hits at beat 0 play
        recordBar(0)
    }

    // MARK: running
    /// Simulate bar lines up to `maxBars` (or until a period is found).
    func run(untilBars maxBars: Int) {
        while !done && barsDone < maxBars {
            var b = Double(nextBar) * barBeats
            for i in L.indices {
                b = min(b, L[i].tickBeat(L[i].nextTick), L[i].nextPassBeat, L[i].pendingRiff)
            }
            processInstant(b)
            if abs(b - Double(nextBar) * barBeats) <= schedEps { barsDone = nextBar; recordBar(nextBar); nextBar += 1 }
            if periodFound != nil { done = true }
        }
    }

    private func isTotal(_ chain: EuclideousRestartChain, _ c: Int64) -> Bool {
        let total = Int64(chain.total)
        guard total > 0 else { return false }
        let r = ((c % total) + total) % total
        var i = 0
        while i < chain.count { if Int64(chain.runningTotal(i)) == r { return true }; i += 1 }
        return false
    }

    private func originTick(_ lane: Int, _ b: Double) -> Int64 { euclideousScheduleTick(b, sub: L[lane].inp.sub) }

    private func melodyRestart(_ x: Int, _ b: Double) {
        guard !L[x].mRestarted else { return }
        L[x].mRestarted = true
        let inp = L[x].inp
        // 2.7(b): a restart counts as a riff completion unless the ordinal is already a whole multiple of the cycle (0 included)
        let tNext = Int64(((b / inp.sub) - schedEps / inp.sub).rounded(.up))
        let c = max(0, inp.advanceStep ? tNext - L[x].M : L[x].hitsBefore(max(L[x].O, tNext)) - L[x].hitsAtM)
        if c % max(1, inp.riffCycle) != 0 && !L[x].riffEvent { L[x].riffEvent = true; L[x].riffBeat = b; L[x].fBeat.append(b) }
        let M2 = originTick(x, b)
        let hm = L[x].hitsBefore(max(L[x].O, M2))
        L[x].M = M2; L[x].hitsAtM = hm
        L[x].mBeat.append(b); L[x].mTick.append(M2); L[x].mHits.append(hm)
    }
    private func rhythmRestart(_ x: Int, _ b: Double) {
        guard !L[x].rRestarted else { return }
        L[x].rRestarted = true
        let lap = L[x].inp.lapBeats
        let O2 = max(L[x].O, originTick(x, b))
        let cum2 = L[x].cumAtO + L[x].pat(O2 - L[x].O)
        let passesIn = Int64(((b - L[x].rhythmBeat) / lap - schedEps).rounded(.up))
        let pass2 = L[x].cumPassAtRestart + max(0, passesIn)
        L[x].rBeat.append(b); L[x].rTick.append(O2); L[x].rPass.append(pass2); L[x].rHits.append(cum2)
        L[x].O = O2; L[x].cumAtO = cum2; L[x].rhythmBeat = b; L[x].cumPassAtRestart = pass2
        if !L[x].passEvent { L[x].passEvent = true; L[x].passBeat = b }          // a pass of X starts at b (the natural one, if it falls here, is the same pass)
        L[x].passJ = 1; L[x].nextPassBeat = b + lap
        if L[x].inp.withRhythm { melodyRestart(x, b) }
    }

    private func processInstant(_ b: Double) {
        let atStart = b <= schedEps
        let barDue = !atStart && abs(b - Double(nextBar) * barBeats) <= schedEps
        let barBeatNow = Double(nextBar) * barBeats
        for i in L.indices {
            L[i].passEvent = false; L[i].riffEvent = false; L[i].rCounted = false; L[i].mCounted = false; L[i].rRestarted = false; L[i].mRestarted = false
            if !atStart, abs(L[i].nextPassBeat - b) <= schedEps {
                L[i].passEvent = true; L[i].passBeat = L[i].nextPassBeat
                L[i].passJ += 1; L[i].nextPassBeat = L[i].rhythmBeat + Double(L[i].passJ) * L[i].inp.lapBeats
            }
            if abs(L[i].pendingRiff - b) <= schedEps { L[i].riffEvent = true; L[i].riffBeat = L[i].pendingRiff; L[i].fBeat.append(L[i].pendingRiff); L[i].pendingRiff = .infinity }
        }
        // (2) resolve the restarts: lanes 1 to 4, again and again until a sweep adds nothing
        if !atStart {
            var changed = true
            var sweeps = 0
            while changed && sweeps < 16 {
                changed = false; sweeps += 1
                let before = flagsDigest()
                for x in L.indices {
                    let inp = L[x].inp
                    // RHYTHM chain
                    if inp.rhythmActive, !L[x].rCounted {
                        var present = false
                        var at = b
                        switch inp.rhythmUnit {
                        case .bar: present = barDue; at = barBeatNow
                        case .pass: if let y = local(inp.rhythmSource) { present = L[y].passEvent; at = L[y].passBeat }
                        case .riff: if let y = local(inp.rhythmSource) { present = L[y].riffEvent; at = L[y].riffBeat }
                        }
                        if present {
                            L[x].rCounted = true; L[x].rhythmCount += 1
                            if isTotal(L[x].rChain, L[x].rhythmCount) { rhythmRestart(x, at) }
                        }
                    }
                    // MELODY chain (PASS / BAR)
                    if inp.melodyActive, inp.melodyUnit != .hit, !L[x].mCounted {
                        var present = false
                        var at = b
                        switch inp.melodyUnit {
                        case .bar: present = barDue; at = barBeatNow
                        case .pass: if let y = local(inp.melodySource) { present = L[y].passEvent; at = L[y].passBeat }
                        case .hit: break
                        }
                        if present {
                            L[x].mCounted = true; L[x].melodyCount += 1
                            if isTotal(L[x].mChain, L[x].melodyCount) { melodyRestart(x, at) }
                        }
                    }
                    // MELODY chain (HIT): the restart falls on a hit of X, before it plays
                    if inp.melodyActive, inp.melodyUnit == .hit, !L[x].mRestarted {
                        let t = L[x].nextTick
                        if abs(L[x].tickBeat(t) - b) <= schedEps, L[x].rawHitAt(t) {
                            let h = L[x].hitsBefore(t)
                            if h > L[x].hitsAtM, isTotal(L[x].mChain, h) { melodyRestart(x, b) }
                        }
                    }
                }
                if flagsDigest() != before { changed = true }
            }
        }
        // (3) play the hits at b: each takes the riff ordinal; reaching a whole multiple of the cycle sets the natural completion at the start of the lane's next step
        for x in L.indices {
            let t = L[x].nextTick
            guard abs(L[x].tickBeat(t) - b) <= schedEps else { continue }
            let inp = L[x].inp
            let hit = L[x].rawHitAt(t)
            if hit || inp.advanceStep {
                let c = inp.advanceStep ? (t + 1 - L[x].M) : (L[x].hitsBefore(t + 1) - L[x].hitsAtM)
                if c > 0, c % max(1, inp.riffCycle) == 0 { L[x].pendingRiff = L[x].tickBeat(t + 1) }
            }
            L[x].nextTick = t + 1
        }
    }
    private func local(_ global: Int) -> Int? { globalLanes.firstIndex(of: global) }
    private func flagsDigest() -> Int {
        var d = 0
        for i in L.indices {
            d = d &* 31 &+ (L[i].passEvent ? 1 : 0); d = d &* 31 &+ (L[i].riffEvent ? 1 : 0); d = d &* 31 &+ (L[i].rRestarted ? 1 : 0); d = d &* 31 &+ (L[i].mRestarted ? 1 : 0)
            d = d &* 31 &+ (L[i].rCounted ? 1 : 0); d = d &* 31 &+ (L[i].mCounted ? 1 : 0)
        }
        return d
    }

    // MARK: periodicity (§4.5)
    private func q(_ x: Double) -> Int64 { Int64((x * 1e6).rounded()) }
    private func recordBar(_ k: Int) {
        let b = Double(k) * barBeats
        var v: [Int64] = []
        var snap = BarSnap(pass: [], hits: [], tick: [], riff: [], rCount: [], mCount: [])
        for i in L.indices {
            let s = L[i], inp = s.inp
            v.append(q(s.tickBeat(s.nextTick) - b))
            v.append(((s.nextTick - s.O) % s.cl + s.cl) % s.cl)
            v.append(q(s.nextPassBeat - b))
            v.append(s.pendingRiff.isFinite ? q(s.pendingRiff - b) : Int64.min)
            let rTotal = Int64(s.rChain.total), mTotal = Int64(s.mChain.total)
            v.append(inp.rhythmActive && rTotal > 0 ? ((s.rhythmCount % rTotal) + rTotal) % rTotal : -1)
            let melodyState: Int64 = inp.melodyUnit == .hit ? s.hitsBefore(s.nextTick) : s.melodyCount
            v.append(inp.melodyActive && mTotal > 0 ? ((melodyState % mTotal) + mTotal) % mTotal : -1)
            let ord = inp.advanceStep ? s.nextTick - s.M : s.hitsBefore(s.nextTick) - s.hitsAtM
            v.append(((ord % max(1, inp.riffCycle)) + max(1, inp.riffCycle)) % max(1, inp.riffCycle))
            v.append(ord == 0 ? 1 : 0)
            // a lane that counts hits with the closed form (BAR chain): the closed form's own fixed-tick cycle phase is part of its state
            let ct = s.closedRhythm.isFree ? Int64(0) : Int64(euclideousOriginTick(Double(s.closedRhythm.total) * barBeats, sub: inp.sub))
            v.append(ct > 0 ? ((s.nextTick % ct) + ct) % ct : -1)
            snap.tick.append(s.nextTick); snap.hits.append(s.cumAtO + s.pat(s.nextTick - s.O)); snap.riff.append(s.fBeat.count)
            snap.rCount.append(s.rBeat.count); snap.mCount.append(s.mBeat.count)
            // the pass index at b (after this instant), the closed form's own
            let pr = passIndexNow(i, b)
            snap.pass.append(pr)
        }
        let key = StateKey(v: v)
        if detectPeriod { if let j = seen[key], periodFound == nil { periodFound = (j, k) } else if seen[key] == nil { seen[key] = k } }
        snaps.append(snap)
    }
    private func passIndexNow(_ i: Int, _ b: Double) -> Int64 {
        let s = L[i]
        guard s.inp.lapBeats > 0 else { return 0 }
        return s.cumPassAtRestart + Int64(((b - s.rhythmBeat + schedEps) / s.inp.lapBeats).rounded(.down))
    }

    // MARK: the tables
    func laneData(_ local: Int) -> EuclideousLaneScheduleData {
        let s = L[local], inp = s.inp
        var rB = s.rBeat, rT = s.rTick, rP = s.rPass, rH = s.rHits
        var mB = s.mBeat, mT = s.mTick, mH = s.mHits
        var fB = s.fBeat
        var prefixEnd = 0.0, period = 0.0
        var dPass: Int64 = 0, dHits: Int64 = 0, dTick: Int64 = 0, dRiff: Int64 = 0
        var rStart = rB.count, mStart = mB.count, fStart = fB.count
        var covered = coveredUntil
        if let (j, k) = periodFound {
            prefixEnd = Double(j) * barBeats; period = Double(k - j) * barBeats
            let a = snaps[j], z = snaps[k]
            dPass = z.pass[local] - a.pass[local]; dHits = z.hits[local] - a.hits[local]; dTick = z.tick[local] - a.tick[local]; dRiff = Int64(z.riff[local] - a.riff[local])
            let cut = Double(k) * barBeats + schedEps          // keep every restart up to and including bar k's own instant
            func trimIdx(_ beats: [Double]) -> Int { var n = 0; while n < beats.count, beats[n] <= cut { n += 1 }; return n }
            func startIdx(_ beats: [Double]) -> Int { var n = 0; while n < beats.count, beats[n] <= prefixEnd + schedEps { n += 1 }; return n }   // the period part: beats in (b_j, b_k]
            let rn = trimIdx(rB), mn = trimIdx(mB), fn = trimIdx(fB)
            rStart = min(startIdx(rB), rn); mStart = min(startIdx(mB), mn); fStart = min(startIdx(fB), fn)
            rB = Array(rB[0..<rn]); rT = Array(rT[0..<rn]); rP = Array(rP[0..<rn]); rH = Array(rH[0..<rn])
            mB = Array(mB[0..<mn]); mT = Array(mT[0..<mn]); mH = Array(mH[0..<mn]); fB = Array(fB[0..<fn])
            covered = .infinity
        }
        return EuclideousLaneScheduleData(sub: inp.sub, cycleLen: inp.cycleLen, barBeats: barBeats, rawHit: inp.rawHit, riffCycle: inp.riffCycle, advanceStep: inp.advanceStep,
                                          rBeat: rB, rTick: rT, rPass: rP, rHits: rH, mBeat: mB, mTick: mT, mHits: mH, fBeat: fB,
                                          prefixEnd: prefixEnd, period: period, dPass: dPass, dHits: dHits, dTick: dTick, dRiff: dRiff,
                                          rPeriodStart: rStart, mPeriodStart: mStart, fPeriodStart: fStart, coveredUntil: covered,
                                          rhythmRestarts: inp.rhythmActive, melodyRestarts: inp.melodyRestarts,
                                          melodyEveryPass: inp.melodyActive && inp.melodyUnit == .pass && inp.melodySource == globalLanes[local] && inp.melodyLinks == [1],
                                          closedFormExpressible: inp.closedFormExpressible(ownLane: globalLanes[local]),
                                          hitsViaClosedForm: s.viaClosedForm, closedRhythm: s.closedRhythm)
    }
}

// MARK: - building the set

/// Connected components of the "reads another lane" graph, lanes ascending in each.
private func scheduleComponents(_ lanes: [EuclideousScheduleLaneInput]) -> [[Int]] {
    var parent = Array(0..<lanes.count)
    func find(_ x: Int) -> Int { var r = x; while parent[r] != r { r = parent[r] }; return r }
    func union(_ a: Int, _ b: Int) { let ra = find(a), rb = find(b); if ra != rb { parent[max(ra, rb)] = min(ra, rb) } }
    for (i, l) in lanes.enumerated() {
        if let y = l.rhythmReads, y < lanes.count { union(i, y) }
        if let y = l.melodyReads, y < lanes.count { union(i, y) }
    }
    var groups: [Int: [Int]] = [:]
    for i in lanes.indices { groups[find(i), default: []].append(i) }
    return groups.keys.sorted().map { groups[$0]!.sorted() }
}

/// The set for the inputs: every lane that has a restart (or is read by a lane that has one) is simulated; the others get empty tables. `maxBars` is the first window (1024 bars); `detectPeriod` false runs a straight simulation (the tests'
/// reference for the periodic wrap).
func euclideousBuildRestartScheduleSet(_ inputs: EuclideousScheduleInputs, engagedMask: UInt8 = 0, maxBars: Int = 1024, detectPeriod: Bool = true, skipClosedFormOnly: Bool = false) -> EuclideousRestartScheduleSet {
    var comps: [(lanes: [Int], sim: EuclideousScheduleSim?)] = []
    for comp in scheduleComponents(inputs.lanes) {
        // `skipClosedFormOnly` (production): a component whose every lane the closed forms can express is never read from the schedule (the Router attaches it only to the others), so it is not simulated — a pre-feature document pays nothing on a publish
        let any = comp.contains { (inputs.lanes[$0].rhythmActive || inputs.lanes[$0].melodyRestarts) && !(skipClosedFormOnly && comp.allSatisfy { inputs.lanes[$0].closedFormExpressible(ownLane: $0) }) }
        if any {
            let sim = EuclideousScheduleSim(globalLanes: comp, inputs: comp.map { inputs.lanes[$0] }, barBeats: inputs.barBeats, detectPeriod: detectPeriod)
            sim.run(untilBars: maxBars)
            comps.append((comp, sim))
        } else { comps.append((comp, nil)) }   // nothing restarts: the trivial beat-0 tables; every reader falls back to the FREE arithmetic
    }
    return euclideousAssembleScheduleSet(inputs, engagedMask: engagedMask, components: comps)
}
fileprivate func euclideousAssembleScheduleSet(_ inputs: EuclideousScheduleInputs, engagedMask: UInt8, components: [(lanes: [Int], sim: EuclideousScheduleSim?)]) -> EuclideousRestartScheduleSet {
    var laneSchedules = [EuclideousLaneSchedule?](repeating: nil, count: inputs.lanes.count)
    var simulated: UInt8 = 0
    var windowed = false
    var covered = Double.infinity
    for c in components {
        for (li, g) in c.lanes.enumerated() {
            if let sim = c.sim { laneSchedules[g] = EuclideousLaneSchedule(data: sim.laneData(li)); simulated |= UInt8(1) << UInt8(g) }
            else { laneSchedules[g] = EuclideousLaneSchedule(data: trivialData(inputs.lanes[g], inputs.barBeats)) }
        }
        if let sim = c.sim, sim.periodFound == nil { windowed = true; covered = min(covered, sim.coveredUntil) }
    }
    return EuclideousRestartScheduleSet(lanes: laneSchedules, barBeats: inputs.barBeats, engagedMask: engagedMask, key: inputs, simulatedMask: simulated, windowed: windowed, coveredUntil: covered, components: components)
}
private func trivialData(_ inp: EuclideousScheduleLaneInput, _ bar: Double) -> EuclideousLaneScheduleData {
    EuclideousLaneScheduleData(sub: inp.sub, cycleLen: inp.cycleLen, barBeats: bar, rawHit: inp.rawHit, riffCycle: inp.riffCycle, advanceStep: inp.advanceStep,
                               rBeat: [0], rTick: [0], rPass: [0], rHits: [0], mBeat: [0], mTick: [0], mHits: [0], fBeat: [],
                               prefixEnd: 0, period: 0, dPass: 0, dHits: 0, dTick: 0, dRiff: 0, rPeriodStart: 1, mPeriodStart: 1, fPeriodStart: 0,
                               coveredUntil: .infinity, rhythmRestarts: false, melodyRestarts: false, melodyEveryPass: false)
}

/// A tiny memo: the last few sets by inputs (the page, the snapshot builder and the tests all ask for the same ones). Locked — `SnapshotBuilder.build` also runs in the AU's init, whose thread the host chooses — and never touched by the render thread.
final class EuclideousRestartScheduleMemo {
    static let shared = EuclideousRestartScheduleMemo()
    private let lock = NSLock()
    private var entries: [(EuclideousScheduleInputs, UInt8, EuclideousRestartScheduleSet)] = []
    private var _version = 0
    /// Bumped whenever an entry is replaced by a longer set, so a holder that cached the shorter one fetches the new one.
    var version: Int { lock.lock(); defer { lock.unlock() }; return _version }
    func replace(_ inputs: EuclideousScheduleInputs, engagedMask: UInt8, with set: EuclideousRestartScheduleSet) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.0 == inputs && $0.1 == engagedMask }
        entries.insert((inputs, engagedMask, set), at: 0)
        _version += 1
    }
    func set(_ inputs: EuclideousScheduleInputs, engagedMask: UInt8) -> EuclideousRestartScheduleSet {
        lock.lock()
        if let e = entries.first(where: { $0.0 == inputs && $0.1 == engagedMask }) { lock.unlock(); return e.2 }
        lock.unlock()
        let s = euclideousBuildRestartScheduleSet(inputs, engagedMask: engagedMask, skipClosedFormOnly: true)   // simulated outside the lock: a build can take tens of milliseconds
        lock.lock(); defer { lock.unlock() }
        if let e = entries.first(where: { $0.0 == inputs && $0.1 == engagedMask }) { return e.2 }
        entries.insert((inputs, engagedMask, s), at: 0)
        if entries.count > 6 { entries.removeLast() }
        return s
    }
}
/// One-slot holder a view keeps (a reference type in `@State`, so filling it never invalidates the view): the page asks for the set many times a body; the lines are compared once, the inputs rebuilt only on a change — or when the memo's entry was extended
/// (a non-periodic schedule simulated further ahead of the playhead), which the page must read too or its tiles and arrows fall back to the closed forms past the first window while the engine keeps the schedule.
final class EuclideousScheduleHolder {
    private var lines: [EuclidLine] = []
    private var bar = 0.0, rate = 0.0, cols = 0, memoVersion = -1
    private var cached: EuclideousRestartScheduleSet?
    func set(lines l: [EuclidLine], barBeats: Double, defaultRateBeats: Double, riffColumns: Int) -> EuclideousRestartScheduleSet {
        let v = EuclideousRestartScheduleMemo.shared.version
        if let c = cached, bar == barBeats, rate == defaultRateBeats, cols == riffColumns, memoVersion == v, lines == l { return c }
        let s = euclideousRestartScheduleSet(lines: l, barBeats: barBeats, defaultRateBeats: defaultRateBeats, riffColumns: riffColumns)
        lines = l; bar = barBeats; rate = defaultRateBeats; cols = riffColumns; memoVersion = EuclideousRestartScheduleMemo.shared.version; cached = s
        return s
    }
}
extension EuclideousRestartScheduleMemo {
    /// §4.6: extend the memoised set for these inputs further ahead (so the next build, and the page, read the longer one). True when something changed.
    func extend(_ set: EuclideousRestartScheduleSet, untilBars bars: Int) -> Bool {
        guard let longer = set.extended(untilBars: bars) else { return false }
        replace(set.key, engagedMask: set.engagedMask, with: longer)
        return true
    }
}
func euclideousRestartScheduleSet(lines: [EuclidLine], barBeats: Double, defaultRateBeats: Double, riffColumns: Int) -> EuclideousRestartScheduleSet {
    EuclideousRestartScheduleMemo.shared.set(euclideousScheduleInputs(lines: lines, barBeats: barBeats, defaultRateBeats: defaultRateBeats, riffColumns: riffColumns),
                                             engagedMask: euclideousScheduleEngagedLanes(lines: lines))
}

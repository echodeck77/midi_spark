//  PlayAsRows.swift — PLAY AS ROWS ferry (2026-11-11): the engine. The lit notes play through three independent CHAINS — ORDER (how the lit ranks are walked), VOICES (how many sound per hit) and SPREAD (how they're spread in time) —
//  plus per-rank repeat COUNTS (with AGAIN/LATER timing), a BASS row and SHIFT/DRIFT. One pure function builds a PASS of ranks (§2), another walks a CURSOR across it hit by hit (§3, §4). Everything is a pure function of the hit ordinal
//  since the melody origin (`euclideousNotesHitOrdinal`, which already resets at a melody restart), so §3.4 needs no accumulator — the simulation runs from the origin each window into FIXED-SIZE buffers (no allocation, invariant 3). The
//  Router and the STACK/MUTE prediction twin call the SAME functions, so a display can never disagree with the engine. RANK-based throughout (positions 0…7 = ranks 1…8; TOP / TOP 2 are not part of this model — the RANKS row is 1…8).

import Foundation

// MARK: - Fixed-size buffers (render-safe; no array ever reaches the render thread)

/// Up to eight ranks (1…8) in order — a key order or the ranks in play.
struct EuclideousRowsRankList: Equatable {
    private(set) var count = 0
    private var bytes = SIMD8<UInt8>(repeating: 0)
    init() {}
    subscript(i: Int) -> Int { Int(bytes[i]) }
    mutating func append(_ r: Int) { guard count < 8, r >= 1, r <= 8 else { return }; bytes[count] = UInt8(r); count += 1 }
    func contains(_ r: Int) -> Bool { for i in 0..<count where Int(bytes[i]) == r { return true }; return false }
    func firstIndex(of r: Int) -> Int? { for i in 0..<count where Int(bytes[i]) == r { return i }; return nil }
    var array: [Int] { (0..<count).map { Int(bytes[$0]) } }   // tests / display (allocates); the render path reads via subscript + count
}

/// One pass of ranks — up to 8 ranks × 3 copies = 24, doubled by BOUNCE to ≤ 46, so 64 bytes cover it.
struct EuclideousRowsPass: Equatable {
    private(set) var count = 0
    private var bytes = SIMD64<UInt8>(repeating: 0)
    init() {}
    subscript(i: Int) -> Int { Int(bytes[i]) }
    mutating func append(_ r: Int) { guard count < 64, r >= 1, r <= 8 else { return }; bytes[count] = UInt8(r); count += 1 }
    /// The distinct ranks in first-appearance order (ALL's "round 1's order", §4.2) and GROW's "first n distinct ranks" (§4.3).
    func distinct(firstN n: Int = 64) -> EuclideousRowsRankList {
        var out = EuclideousRowsRankList()
        for i in 0..<count { let r = bytes[i]; if !out.contains(Int(r)) { out.append(Int(r)); if out.count >= n { break } } }
        return out
    }
    var array: [Int] { (0..<count).map { Int(bytes[$0]) } }   // tests / display (allocates); the render path reads via subscript + count
    /// A left rotation by `k` (0 ≤ k < count) — §2.5 SHIFT.
    func rotatedLeft(_ k: Int) -> EuclideousRowsPass {
        guard count > 1, k % count != 0 else { return self }
        let r = ((k % count) + count) % count
        var out = EuclideousRowsPass()
        for i in 0..<count { out.append(Int(bytes[(i + r) % count])) }
        return out
    }
}

/// The notes one hit strikes (RANK-based; the Router resolves each rank to a pitch at note-on). `bassRank` 0 = no bass this hit; else it is struck AT the hit (not spread) ahead of the chord.
struct EuclideousRowsHit: Equatable {
    private(set) var count = 0
    private var bytes = SIMD16<UInt8>(repeating: 0)
    var spread: EuclideousSpreadMode = .together
    var bassRank = 0
    init() {}
    subscript(i: Int) -> Int { Int(bytes[i]) }
    mutating func append(_ r: Int) { guard count < 16, r >= 1, r <= 8 else { return }; bytes[count] = UInt8(r); count += 1 }
    /// Chord ranks only (the strum/run-spread notes), low-level access for the Router and tests.
    var ranks: [Int] { (0..<count).map { Int(bytes[$0]) } }
    var allRanks: [Int] { (bassRank > 0 ? [bassRank] : []) + ranks }   // bass first, then the chord — tests only (allocates)
}

// MARK: - §2.1 ranks in play

/// The lit ranks (positions 0…7 of the lit order), ascending and in ADDED order (§1.7 = the lit order itself), minus the lowest lit rank while bass is on (§2.1). `bassRank` 0 = none (bass off, or nothing lit).
func euclideousRowsRanksInPlay(litOrder: EuclideousLitOrder, bassOn: Bool) -> (asc: EuclideousRowsRankList, added: EuclideousRowsRankList, bassRank: Int) {
    // lit ranks in ADDED order (the lit order, positions < 8), and the lowest lit rank
    var added = EuclideousRowsRankList(); var lowest = 0
    for i in 0..<litOrder.count { let p = litOrder[i]; if p < 8 { let r = p + 1; added.append(r); if lowest == 0 || r < lowest { lowest = r } } }
    let bass = (bassOn && lowest > 0) ? lowest : 0
    // ascending, both lists dropping the bass rank
    var asc = EuclideousRowsRankList(); var added2 = EuclideousRowsRankList()
    for r in 1...8 where added.contains(r) && r != bass { asc.append(r) }
    for i in 0..<added.count { let r = added[i]; if r != bass { added2.append(r) } }
    return (asc, added2, bass)
}

// MARK: - §2.2 key order · §2.3-§2.5 the pass

/// §2.2: the ranks in play in the ORDER chip's key order K (UP / DOWN / OUTSIDE IN / INSIDE OUT / AS ADDED / SHUFFLE; BOUNCE uses UP and §2.4 mirrors the pass). SHUFFLE is a fresh permutation per pass, seeded replay-exact on (lane, passIndex).
func euclideousRowsKeyOrder(asc: EuclideousRowsRankList, added: EuclideousRowsRankList, order: EuclideousOrderMode, passIndex: Int, lane: Int) -> EuclideousRowsRankList {
    var K = EuclideousRowsRankList()
    switch order {
    case .up, .bounce:
        for i in 0..<asc.count { K.append(asc[i]) }
    case .down:
        var i = asc.count - 1; while i >= 0 { K.append(asc[i]); i -= 1 }
    case .outsideIn:
        var lo = 0, hi = asc.count - 1
        while lo <= hi { K.append(asc[lo]); if lo != hi { K.append(asc[hi]) }; lo += 1; hi -= 1 }
    case .insideOut:
        var oi = EuclideousRowsRankList(); var lo = 0, hi = asc.count - 1
        while lo <= hi { oi.append(asc[lo]); if lo != hi { oi.append(asc[hi]) }; lo += 1; hi -= 1 }
        var i = oi.count - 1; while i >= 0 { K.append(oi[i]); i -= 1 }
    case .asAdded:
        for i in 0..<added.count { K.append(added[i]) }
    case .shuffle:
        // Fisher-Yates over a splitmix64 stream seeded on (lane, passIndex) — a fresh permutation per pass, replay-exact. In-place on a SIMD8 (no array), so it is allocation-free on the render path.
        let n = asc.count
        var tmp = SIMD8<UInt8>(repeating: 0); for i in 0..<n { tmp[i] = UInt8(asc[i]) }
        var s = splitmix64Mix(UInt64(bitPattern: Int64(lane)) &* 0x9E3779B97F4A7C15 &+ UInt64(bitPattern: Int64(passIndex)) &+ 0xD1B54A32D192ED03)
        var i = n - 1
        while i > 0 { s = splitmix64Mix(s); let j = Int(s % UInt64(i + 1)); let a = tmp[i]; tmp[i] = tmp[j]; tmp[j] = a; i -= 1 }
        for i in 0..<n { K.append(Int(tmp[i])) }
    }
    return K
}

/// §2.3-§2.5: the full pass of ranks for one play-through — the copies laid out in rounds (§2.3), BOUNCE mirrored (§2.4), SHIFT-rotated (§2.5, not for SHUFFLE). `counts` is 2 bits per rank (0⇒1 copy, 1⇒2, 2⇒3); `secondLater`/`thirdLater`
/// are one bit per rank (set ⇒ that copy is LATER, i.e. the next round). `passIndex` is passes since the melody origin (for DRIFT). Empty when nothing is in play.
func euclideousRowsBuildPass(asc: EuclideousRowsRankList, added: EuclideousRowsRankList, order: EuclideousOrderMode,
                             counts: UInt16, secondLater: UInt8, thirdLater: UInt8, passIndex: Int, lane: Int,
                             shiftStart: Int, driftOn: Bool, driftStep: Int) -> EuclideousRowsPass {
    var pass = EuclideousRowsPass()
    guard asc.count > 0 else { return pass }
    let K = euclideousRowsKeyOrder(asc: asc, added: added, order: order, passIndex: passIndex, lane: lane)
    // §2.3: copy k of rank r sits in round R(k). R(1)=1; R(2)=1 if 2nd is AGAIN else 2; R(3)=R(2) if 3rd is AGAIN else R(2)+1. Round r lists, in K order, every copy whose round is r.
    func cnt(_ r: Int) -> Int { min(3, Int((counts >> UInt16(2 * (r - 1))) & 0b11) + 1) }
    func roundOfCopy2(_ r: Int) -> Int { (secondLater >> UInt8(r - 1)) & 1 != 0 ? 2 : 1 }
    func roundOfCopy3(_ r: Int) -> Int { roundOfCopy2(r) + ((thirdLater >> UInt8(r - 1)) & 1 != 0 ? 1 : 0) }
    for round in 1...3 {
        for i in 0..<K.count {
            let r = K[i]; let c = cnt(r)
            var copies = 0
            if round == 1 { copies += 1 }                               // copy 1 is always round 1
            if c >= 2 && roundOfCopy2(r) == round { copies += 1 }
            if c >= 3 && roundOfCopy3(r) == round { copies += 1 }
            for _ in 0..<copies { pass.append(r) }
        }
    }
    // §2.4: BOUNCE — P then P reversed without its first and last entries (a P of 1 or 2 entries is the whole pass).
    if order == .bounce, pass.count > 2 {
        var tail = EuclideousRowsPass()
        var i = pass.count - 2; while i >= 1 { tail.append(pass[i]); i -= 1 }   // reverse of P without its first and last — snapshot it before appending (appending to `pass` would move its end)
        for j in 0..<tail.count { pass.append(tail[j]) }
    }
    // §2.5: SHIFT (no effect on SHUFFLE) — rotate left by (start + step × passIndex while drift on) mod len.
    if order != .shuffle, pass.count > 0 {
        let drift = driftOn ? driftStep * passIndex : 0
        pass = pass.rotatedLeft(((shiftStart + drift) % pass.count + pass.count) % pass.count)
    }
    return pass
}

// MARK: - §3 the chains · §4 each hit

/// The active chip index of a chain at hit `h` (hits since the melody origin): walk the chips by their cumulative hit counts, looping after the last; a one-chip (or nil/empty) chain is index 0 always (§3.1). Pure, O(chips).
@inline(__always) func euclideousRowsActiveChip<C>(_ chain: [C]?, hits: (C) -> Int, hitOrdinal h: Int64) -> Int {
    guard let c = chain, c.count > 1 else { return 0 }
    var total: Int64 = 0; for x in c { total += Int64(max(1, hits(x))) }
    guard total > 0 else { return 0 }
    var pos = ((h % total) + total) % total
    for (i, x) in c.enumerated() { let n = Int64(max(1, hits(x))); if pos < n { return i }; pos -= n }
    return c.count - 1
}

/// The §1.9 default chips, so a nil / empty chain resolves without allocating.
@inline(__always) func euclideousRowsOrderValue(_ chain: [EuclideousOrderChip]?, _ idx: Int) -> EuclideousOrderMode { guard let c = chain, idx >= 0, idx < c.count else { return .up }; return c[idx].value }
@inline(__always) func euclideousRowsVoicesValue(_ chain: [EuclideousVoicesChip]?, _ idx: Int) -> EuclideousVoicesMode { guard let c = chain, idx >= 0, idx < c.count else { return .one }; return c[idx].value }
@inline(__always) func euclideousRowsSpreadValue(_ chain: [EuclideousSpreadChip]?, _ idx: Int) -> EuclideousSpreadMode { guard let c = chain, idx >= 0, idx < c.count else { return .together }; return c[idx].value }

/// The simulation bound: a lane that plays this many notes-hits without a melody restart has its pass/cursor phase reduced modulo the chains' combined period (a bounded, documented seam, like the canon ring's depth limit). The chain
/// phase is preserved exactly; only the far-out pass seam moves. In practice a melody restart keeps `h` small (`euclideousNotesHitOrdinal` resets there), so this never triggers for a restarting lane.
let euclideousRowsSimCap: Int64 = 4096
/// The RUN BLOCK (code-review 2026-11-12): a non-restarting lane's hit ordinal grows without bound, so the walk is reduced to `h mod block`, where `block` is the smallest whole number of chain periods that reaches this target. The PASS
/// restarts every `block` hits — the same deliberate loop the old `euclideousNotesCountBefore` made in 1024-hit blocks, not a glitch — which bounds the per-hit render cost (the walk is O(block), not O(h)) and never freezes (the earlier
/// `(cap − p)` floor pinned a small-period lane on one note forever). `block` is a multiple of the chains' period so the chain phase stays continuous across the seam. 2048 ⇒ a 32-bar harness (≤ ~2048 hits) never reduces, so no golden moves.
let euclideousRowsRunBlock: Int64 = 2048

@inline(__always) private func euclideousRowsChainTotal<C>(_ chain: [C]?, hits: (C) -> Int) -> Int64 {
    guard let c = chain, c.count > 1 else { return 1 }
    var t: Int64 = 0; for x in c { t += Int64(max(1, hits(x))) }; return max(1, t)
}
@inline(__always) private func euclideousRowsLCM(_ a: Int64, _ b: Int64) -> Int64 {
    guard a > 0, b > 0 else { return max(1, max(a, b)) }
    func gcd(_ x: Int64, _ y: Int64) -> Int64 { var a = x, b = y; while b != 0 { (a, b) = (b, a % b) }; return a }
    let g = gcd(a, b); let l = a / g * b
    return l > 0 ? l : euclideousRowsSimCap
}

/// §4 — the notes the NOTES layer strikes on the hit that falls `h` hits after the lane's melody origin. ONE closed simulation from the origin: the three chains cycle independently (§3.2), a pass is built when it starts (an ORDER-chip change,
/// a cursor wrap, GROW's wrap, or every hit under ALL — §3.3, §4.2, §4.3) and consumed across hits by VOICES (§4.1), SPREAD decides the strike spacing (§4.4), BASS the root (§4.5). Pure and allocation-free on the common path.
func euclideousRowsResolve(orderChain: [EuclideousOrderChip]?, voicesChain: [EuclideousVoicesChip]?, spreadChain: [EuclideousSpreadChip]?,
                           litOrder: EuclideousLitOrder, counts: UInt16, secondLater: UInt8, thirdLater: UInt8,
                           bassOn: Bool, bassMode: EuclideousBassMode, shiftStart: Int, driftOn: Bool, driftStep: Int,
                           lane: Int, hitOrdinal h: Int64) -> EuclideousRowsHit {
    var out = EuclideousRowsHit()
    let rip = euclideousRowsRanksInPlay(litOrder: litOrder, bassOn: bassOn)
    let m = rip.asc.count
    // §2.8: nothing in play ⇒ the chord is empty (bass may still play).
    let bassSounds: Bool = rip.bassRank > 0 && (bassMode == .hold || h % 2 == 0)   // §4.5: HOLD every hit; FIRST on even hits (SPLIT's low-then-rest), the chord plays regardless
    out.bassRank = bassSounds ? rip.bassRank : 0
    out.spread = euclideousRowsSpreadValue(spreadChain, euclideousRowsActiveChip(spreadChain, hits: { $0.hits }, hitOrdinal: h))
    guard m > 0 else { return out }

    // Bound the walk to a RUN BLOCK of whole chain periods (see euclideousRowsRunBlock): the pass LOOPS at the block,
    // it never freezes, and the per-hit render cost is O(block) instead of O(h). The chain phase is preserved exactly.
    var hEff = h
    if h >= euclideousRowsRunBlock {
        var cp = euclideousRowsLCM(euclideousRowsChainTotal(orderChain, hits: { $0.hits }), euclideousRowsChainTotal(voicesChain, hits: { $0.hits }))
        cp = euclideousRowsLCM(cp, euclideousRowsChainTotal(spreadChain, hits: { $0.hits }))
        cp = max(1, min(euclideousRowsSimCap, cp))
        let block = cp >= euclideousRowsRunBlock ? cp : ((euclideousRowsRunBlock + cp - 1) / cp) * cp   // smallest whole number of chain periods ≥ the run block
        hEff = h % block
    }

    var pass = EuclideousRowsPass()
    var cursor = 0
    var passIndex = 0
    var prevOrderIdx = -1, prevVoicesIdx = -1
    var voicesStartHit: Int64 = 0

    // The mutated state is INOUT, never captured — a nested func that captures mutable locals heap-boxes them, which the render-path alloc audit forbids (invariant 3). Only the immutable `rip`/counts/… are captured (by value, stack).
    @inline(__always) func rebuild(_ order: EuclideousOrderMode, _ pass: inout EuclideousRowsPass, _ cursor: inout Int, _ passIndex: inout Int) {
        pass = euclideousRowsBuildPass(asc: rip.asc, added: rip.added, order: order, counts: counts, secondLater: secondLater, thirdLater: thirdLater,
                                       passIndex: passIndex, lane: lane, shiftStart: shiftStart, driftOn: driftOn, driftStep: driftStep)
        passIndex += 1; cursor = 0
    }

    var i: Int64 = 0
    while i <= hEff {
        let oIdx = euclideousRowsActiveChip(orderChain, hits: { $0.hits }, hitOrdinal: i)
        let vIdx = euclideousRowsActiveChip(voicesChain, hits: { $0.hits }, hitOrdinal: i)
        if vIdx != prevVoicesIdx { voicesStartHit = i }     // GROW's n counts from the current VOICES-chip occurrence
        let order = euclideousRowsOrderValue(orderChain, oIdx)
        let vVal = euclideousRowsVoicesValue(voicesChain, vIdx)
        let orderChanged = (prevOrderIdx != oIdx)           // §3.3: an ORDER-chip change starts a new pass at position 0
        let grown = Int(i - voicesStartHit)
        let last = (i == hEff)

        switch vVal {
        case .all:
            // §4.2: every rank in play once, in round 1's order; a whole pass each hit; cursor stays 0; DRIFT steps once per hit.
            rebuild(order, &pass, &cursor, &passIndex)
            if last { let d = pass.distinct(); for j in 0..<d.count { out.append(d[j]) } }
        case .grow:
            // §4.3: hit n of the GROW chip plays the first ((n−1) mod m)+1 distinct ranks; a new pass starts when the size wraps to 1.
            if orderChanged || grown % m == 0 { rebuild(order, &pass, &cursor, &passIndex) }
            if last { let size = (grown % m) + 1; let d = pass.distinct(firstN: size); for j in 0..<d.count { out.append(d[j]) } }
        default:
            // §4.1: VOICES 1 / 2 / 3 — take entries from the cursor until the chord holds that many distinct ranks; a repeat ends the chord early and is not consumed; a chord runs over a pass boundary, which is built then.
            if orderChanged { rebuild(order, &pass, &cursor, &passIndex) }
            let v = (vVal == .three) ? 3 : (vVal == .two ? 2 : 1)
            let cap = min(v, m)
            var chordCount = 0
            var inChord = EuclideousRowsRankList()
            while chordCount < cap {
                if cursor >= pass.count { rebuild(order, &pass, &cursor, &passIndex) }
                if pass.count == 0 { break }
                let r = pass[cursor]
                if inChord.contains(r) { break }            // a rank already in the chord ends it early and is NOT consumed (starts the next hit)
                inChord.append(r); if last { out.append(r) }; cursor += 1; chordCount += 1
            }
        }
        prevOrderIdx = oIdx; prevVoicesIdx = vIdx
        i += 1
    }
    return out
}

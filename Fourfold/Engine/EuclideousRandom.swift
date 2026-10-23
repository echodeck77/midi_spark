//  EuclideousRandom.swift
//  RANDOM MODE ferry (Fourfold roll, ratified 2026-10-21): THROW/TWEAK's pure generation (§8-9), the
//  §10 invariants, the future-beat landing type (§6), and the §7.2 undo-sequence builder. Foundation-
//  only, no UI import — same testability contract as Derivations.swift (the macOS test target compiles
//  this directly). Every "which steps hit / which column / is a rest / play list" decision calls the
//  SAME engine function Router.swift and Derivations.swift already use — never a second derivation.

import Foundation

// MARK: - Seeded RNG — wraps the existing splitmix64Mix (Derivations.swift), no second hash.

struct EuclideousRandomRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state = splitmix64Mix(state &+ 0x9E37_79B9_7F4A_7C15)
        return state
    }
}

/// Picks one option by integer weight. Weights must sum > 0 (callers always supply a non-empty, positive-weight list).
func euclideousRandomWeightedPick<T>(_ options: [(T, Int)], rng: inout EuclideousRandomRNG) -> T {
    let total = options.reduce(0) { $0 + max(0, $1.1) }
    guard total > 0 else { return options[0].0 }
    var r = Int(rng.next() % UInt64(total))
    for (v, w) in options {
        if r < w { return v }
        r -= w
    }
    return options[options.count - 1].0
}

/// Uniform pick from a (possibly repeat-weighted-by-literal-repetition) list.
func euclideousRandomUniformPick<T>(_ options: [T], rng: inout EuclideousRandomRNG) -> T {
    options[Int(rng.next() % UInt64(options.count))]
}

// MARK: - §8.1 Density and roles

enum EuclideousRandomRole: Equatable { case sparse, medium, dense }

/// ρ = HITS ÷ (STEPS × stepBeats).
@inline(__always)
func euclideousRandomOnsetRate(hits: Int, steps: Int, stepBeats: Double) -> Double {
    guard steps > 0, stepBeats > 0 else { return 0 }
    return Double(hits) / (Double(steps) * stepBeats)
}

/// sparse ρ ≤ 0.5 · medium ρ ≤ 1.5 · dense otherwise.
func euclideousRandomRole(hits: Int, steps: Int, stepBeats: Double) -> EuclideousRandomRole {
    let rho = euclideousRandomOnsetRate(hits: hits, steps: steps, stepBeats: stepBeats)
    if rho <= 0.5 { return .sparse }
    if rho <= 1.5 { return .medium }
    return .dense
}

/// §8.1 target bands: sparse 0.2–0.5 · medium 0.6–1.4 · dense 1.6–3.2.
func euclideousRandomRoleBand(_ role: EuclideousRandomRole) -> ClosedRange<Double> {
    switch role {
    case .sparse: return 0.2...0.5
    case .medium: return 0.6...1.4
    case .dense: return 1.6...3.2
    }
}

/// §10: the pyramid — at most one dense lane among the four, at least one sparse. `roles` is every
/// lane counted for the pyramid (callers pre-filter to "playing with riff or notes on", §8.1).
func euclideousRandomPyramidHolds(_ roles: [EuclideousRandomRole]) -> Bool {
    guard !roles.isEmpty else { return true }
    let denseCount = roles.filter { $0 == .dense }.count
    let anySparse = roles.contains(.sparse)
    return denseCount <= 1 && anySparse
}

/// §10/§8.3: at most one lane with an odd STEPS.
func euclideousRandomOddStepsHolds(_ stepsList: [Int]) -> Bool {
    stepsList.filter { $0 % 2 == 1 }.count <= 1
}

/// §8.2: the role a throw aims for, for lane L, given the OTHER (participating) lanes' CURRENT roles.
func euclideousRandomTargetRole(otherRoles: [EuclideousRandomRole], rng: inout EuclideousRandomRNG) -> EuclideousRandomRole {
    let weighted: [(EuclideousRandomRole, Int)] = [(.dense, 4), (.medium, 4), (.sparse, 2)]
    guard !otherRoles.isEmpty else { return euclideousRandomWeightedPick(weighted, rng: &rng) }
    if !otherRoles.contains(.sparse) { return .sparse }
    if otherRoles.contains(.dense) { return Bool.random(using: &rng) ? .sparse : .medium }
    return euclideousRandomWeightedPick(weighted, rng: &rng)
}

// MARK: - Shared "other lane" facts (rhythm + riff + notes throws/tweaks all read a slice of this)

struct EuclideousRandomOtherLane {
    var steps: Int
    var hits: Int
    var offset: Int          // displayed OFFSET, 0..<steps
    var stepBeats: Double
    var participates: Bool   // riff or notes layer on — counts for the pyramid (§8.1)
    var riffOn: Bool
    var riffDir: RiffDir
    var riffAdvanceStep: Bool
    var riffAdvanceEvery: Int
    var riffStride: Int
    var riffShift: Int
}

// MARK: - §8.3 / §9.2 RHYTHM

struct EuclideousRandomRhythmResult: Equatable {
    var steps: Int
    var hits: Int
    var offset: Int   // displayed OFFSET, 0..<steps
    var tag: String
}

private func euclideousRandomRhythmTag(role: EuclideousRandomRole, hits: Int, steps: Int, offset: Int) -> String {
    let roleName: String
    switch role { case .sparse: roleName = "SPARSE"; case .medium: roleName = "MEDIUM"; case .dense: roleName = "DENSE" }
    var s = "\(roleName) · \(hits) OF \(steps)"
    if offset > 0 { s += " · OFFSET \(offset)" }
    return s
}

/// §8.3: THROW. `current`/`others` carry only what this function reads (steps/hits/displayed-offset/stepBeats).
func euclideousRandomThrowRhythm(current: (steps: Int, hits: Int, offset: Int, stepBeats: Double),
                                  others: [EuclideousRandomOtherLane],
                                  rng: inout EuclideousRandomRNG) -> EuclideousRandomRhythmResult {
    let participating = others.filter { $0.participates }
    let otherRoles = participating.map { euclideousRandomRole(hits: $0.hits, steps: $0.steps, stepBeats: $0.stepBeats) }
    let othersHaveOdd = others.contains { $0.steps % 2 == 1 }

    enum StepsChoice { case fixed(Int); case odd }
    var stepsOptions: [(StepsChoice, Int)] = [(.fixed(16), 4), (.fixed(8), 3), (.fixed(12), 1), (.fixed(6), 1)]
    if !othersHaveOdd { stepsOptions.append((.odd, 1)) }

    for _ in 0..<40 {
        let stepsChoice = euclideousRandomWeightedPick(stepsOptions, rng: &rng)
        let steps: Int
        switch stepsChoice {
        case .fixed(let s): steps = s
        case .odd: steps = euclideousRandomUniformPick([5, 7, 9, 11, 13], rng: &rng)
        }
        let targetRole = euclideousRandomTargetRole(otherRoles: otherRoles, rng: &rng)
        let band = euclideousRandomRoleBand(targetRole)
        let rho = Double.random(in: band, using: &rng)
        let hits = max(1, min(steps - 1, Int((rho * Double(steps) * current.stepBeats).rounded())))
        guard euclideousRandomRole(hits: hits, steps: steps, stepBeats: current.stepBeats) == targetRole else { continue }

        let offset: Int
        if targetRole == .sparse, Double.random(in: 0..<1, using: &rng) < 0.6 {
            offset = 0
        } else {
            offset = Int(rng.next() % UInt64(steps))
        }

        if steps == current.steps, hits == current.hits, offset == current.offset { continue }
        if others.contains(where: { $0.steps == steps && $0.hits == hits && $0.offset == offset && $0.stepBeats == current.stepBeats }) { continue }

        // §10: the pyramid must hold after a RHYTHM throw (the new lane's own role replaces nothing of
        // the others' — just check the resulting set, including this lane if it participates).
        var roles = otherRoles
        roles.append(targetRole)
        guard euclideousRandomPyramidHolds(roles) else { continue }
        if case .odd = stepsChoice, othersHaveOdd == false {
            guard euclideousRandomOddStepsHolds(others.map { $0.steps } + [steps]) else { continue }
        }

        return EuclideousRandomRhythmResult(steps: steps, hits: hits, offset: offset,
                                             tag: euclideousRandomRhythmTag(role: targetRole, hits: hits, steps: steps, offset: offset))
    }
    // §8.3: after 40 failed tries — nudge HITS, keep STEPS/OFFSET.
    let hits = current.hits < current.steps - 1 ? current.hits + 1 : current.hits - 1
    let role = euclideousRandomRole(hits: hits, steps: current.steps, stepBeats: current.stepBeats)
    return EuclideousRandomRhythmResult(steps: current.steps, hits: max(1, hits), offset: current.offset,
                                         tag: euclideousRandomRhythmTag(role: role, hits: max(1, hits), steps: current.steps, offset: current.offset))
}

/// Builds the pure Euclid hit-set for a (hits, steps) pair at the CURRENT tilt/rotate — the engine's own
/// pattern builder (§0(c)), never a second derivation. Returns a fixed-size `[Bool]` of length `steps`.
func euclideousRandomPattern(hits: Int, steps: Int, offset: Int, tilt: Double) -> [Bool] {
    let rotate = (steps - min(offset, steps - 1)) % steps
    var buf = [Bool](repeating: false, count: max(1, min(64, steps)))
    _ = euclidPatternInto(&buf, pulses: hits, steps: steps, rotation: 0)
    if tilt != 0 { euclidTiltPattern(&buf, pulses: hits, steps: steps, tilt: tilt) }
    euclidRotateBuffer(&buf, steps: steps, rotation: rotate)
    return buf
}

private func euclideousRandomSharedHits(_ a: [Bool], _ b: [Bool]) -> Int {
    (0..<min(a.count, b.count)).filter { a[$0] && b[$0] }.count
}

/// §9.2: TWEAK — one named move from what's currently playing.
func euclideousRandomTweakRhythm(current: (steps: Int, hits: Int, offset: Int, stepBeats: Double, tilt: Double),
                                  others: [EuclideousRandomOtherLane],
                                  rng: inout EuclideousRandomRNG) -> EuclideousRandomRhythmResult {
    enum Move { case hitsUp, hitsDown, offsetUp, offsetDown, stepsUp, stepsDown }
    let options: [(Move, Int)] = [(.hitsUp, 3), (.hitsDown, 3), (.offsetUp, 2), (.offsetDown, 2), (.stepsUp, 1), (.stepsDown, 1)]
    let currentPattern = euclideousRandomPattern(hits: current.hits, steps: current.steps, offset: current.offset, tilt: current.tilt)
    let othersHaveOdd = others.contains { $0.steps % 2 == 1 }

    func bestOffset(forHits hits: Int, steps: Int) -> Int {
        var best = 0, bestShared = -1
        for o in 0..<steps {
            let p = euclideousRandomPattern(hits: hits, steps: steps, offset: o, tilt: current.tilt)
            let shared = euclideousRandomSharedHits(p, currentPattern)
            if shared > bestShared || (shared == bestShared && abs(o - current.offset) < abs(best - current.offset)) {
                bestShared = shared; best = o
            }
        }
        return best
    }

    for _ in 0..<40 {
        let move = euclideousRandomWeightedPick(options, rng: &rng)
        var steps = current.steps, hits = current.hits, offset = current.offset
        var tag = ""
        switch move {
        case .hitsUp, .hitsDown:
            let newHits = move == .hitsUp ? current.hits + 1 : current.hits - 1
            guard newHits >= 1, newHits <= current.steps - 1 else { continue }
            let newOffset = bestOffset(forHits: newHits, steps: current.steps)
            let newPattern = euclideousRandomPattern(hits: newHits, steps: current.steps, offset: newOffset, tilt: current.tilt)
            guard euclideousRandomSharedHits(newPattern, currentPattern) >= min(current.hits, newHits) - 1 else { continue }
            hits = newHits; offset = newOffset
            tag = "HITS \(current.hits)→\(newHits)"
        case .offsetUp, .offsetDown:
            let n = current.steps
            let newOffset = ((move == .offsetUp ? current.offset + 1 : current.offset - 1) % n + n) % n
            offset = newOffset
            tag = "OFFSET \(current.offset)→\(newOffset)"
        case .stepsUp, .stepsDown:
            let newSteps = move == .stepsUp ? current.steps + 1 : current.steps - 1
            guard newSteps >= 2, newSteps <= 16 else { continue }
            if newSteps % 2 == 1, othersHaveOdd { continue }
            guard current.hits <= newSteps - 1 else { continue }
            let newOffset = bestOffset(forHits: current.hits, steps: newSteps)
            steps = newSteps; offset = min(newOffset, newSteps - 1)
            tag = "STEPS \(current.steps)→\(newSteps)"
        }
        guard steps != current.steps || hits != current.hits || offset != current.offset else { continue }
        let newRole = euclideousRandomRole(hits: hits, steps: steps, stepBeats: current.stepBeats)
        let participating = others.filter { $0.participates }
        var roles = participating.map { euclideousRandomRole(hits: $0.hits, steps: $0.steps, stepBeats: $0.stepBeats) }
        let oldRole = euclideousRandomRole(hits: current.hits, steps: current.steps, stepBeats: current.stepBeats)
        let heldBefore = euclideousRandomPyramidHolds(roles + [oldRole])
        roles.append(newRole)
        if heldBefore { guard euclideousRandomPyramidHolds(roles) else { continue } }
        return EuclideousRandomRhythmResult(steps: steps, hits: hits, offset: offset, tag: tag)
    }
    return EuclideousRandomRhythmResult(steps: current.steps, hits: current.hits, offset: current.offset, tag: "")
}

// MARK: - §8.4 / §9.3 RIFF (the walk)

struct EuclideousRandomRiffResult: Equatable {
    var dir: RiffDir
    var advanceStep: Bool   // false = HIT, true = STEP (riffAdvanceStep)
    var advanceEvery: Int
    var invert: Bool
    var onRest: EuclidRiffOnRest
    var stride: Int
    var shift: Int
    var tag: String
}

let euclideousRandomRiffDirections: [RiffDir] = [.forward, .reverse, .pendulum, .pingpong]

func euclideousRandomRiffDirShort(_ d: RiffDir) -> String {   // internal since the LANE LOCK ferry: the lock card's RIFF row reuses the tag text (no second formatting)
    switch d {
    case .forward: return "FWD"
    case .reverse: return "REV"
    case .pendulum: return "PEND"
    case .pingpong: return "PING"
    case .random, .drunk: return "FWD"
    }
}

func euclideousRandomRiffTag(dir: RiffDir, invert: Bool, advanceStep: Bool, every: Int, stride: Int) -> String {
    var s = euclideousRandomRiffDirShort(dir)
    if invert { s += " INV" }
    s += advanceStep ? " · BY STEP" : " · BY HIT"
    if every > 1 { s += " ÷\(every)" }
    if stride > 1 { s += " · STRIDE \(stride)" }
    return s
}

/// §8.4's coverage check, over the lane's first 8 passes from the melody origin (ordinals 0..<8·HITS),
/// via the SAME `euclideousRiffColumn` the Router/UI walk mirror calls — never a second walk formula.
func euclideousRandomRiffCoverage(dir: RiffDir, every: Int, stride: Int, shift: Int, length: Int, hits: Int,
                                   writtenRanks: [Int]) -> (reached: Set<Int>, soundingReached: Bool) {
    var reached = Set<Int>()
    var soundingReached = false
    let ordinals = max(1, 8 * hits)
    for o in 0..<ordinals {
        let col = euclideousRiffColumn(ordinal: Int64(o), every: every, direction: dir, length: length, stride: stride, shift: shift)
        reached.insert(col)
        if col < writtenRanks.count, writtenRanks[col] >= 1 { soundingReached = true }
    }
    return (reached, soundingReached)
}

/// §8.4: THROW.
func euclideousRandomThrowRiff(current: (dir: RiffDir, advanceStep: Bool, advanceEvery: Int, invert: Bool,
                                          onRest: EuclidRiffOnRest, stride: Int, shift: Int, length: Int, hits: Int,
                                          role: EuclideousRandomRole),
                                writtenRanks: [Int],
                                others: [EuclideousRandomOtherLane],
                                rng: inout EuclideousRandomRNG) -> EuclideousRandomRiffResult? {
    let riffOnOthers = others.filter { $0.riffOn }
    let otherDirs = Set(riffOnOthers.map { $0.riffDir })

    for _ in 0..<80 {
        let dir: RiffDir
        if Double.random(in: 0..<1, using: &rng) < 0.75, !otherDirs.isEmpty {
            let pool = euclideousRandomRiffDirections.filter { !otherDirs.contains($0) }
            dir = pool.isEmpty ? euclideousRandomUniformPick(euclideousRandomRiffDirections, rng: &rng)
                                : euclideousRandomUniformPick(pool, rng: &rng)
        } else {
            dir = euclideousRandomUniformPick(euclideousRandomRiffDirections, rng: &rng)
        }
        let invert = Double.random(in: 0..<1, using: &rng) < 0.15

        let everyWeights: [(Int, Int)] = current.role == .dense
            ? [(1, 3), (2, 4), (3, 1), (4, 1)]
            : [(1, 7), (2, 2), (3, 1)]
        let every = euclideousRandomWeightedPick(everyWeights, rng: &rng)

        let advanceStep: Bool = current.role == .sparse
            ? euclideousRandomWeightedPick([(true, 3), (false, 2)], rng: &rng)
            : euclideousRandomWeightedPick([(false, 3), (true, 2)], rng: &rng)

        let onRest = euclideousRandomWeightedPick([(EuclidRiffOnRest.skip, 5), (.tie, 3), (.repeatLast, 2)], rng: &rng)
        let stride = euclideousRandomWeightedPick([(1, 6), (2, 2), (3, 2)], rng: &rng)
        let shift = Double.random(in: 0..<1, using: &rng) < 0.5 ? 0 : Int(rng.next() % UInt64(max(1, current.length)))

        let (reached, soundingReached) = euclideousRandomRiffCoverage(dir: dir, every: every, stride: stride, shift: shift,
                                                                        length: current.length, hits: current.hits, writtenRanks: writtenRanks)
        guard reached.count >= Int(ceil(Double(current.length) / 2)) else { continue }
        guard current.length - reached.count <= 2 else { continue }
        guard soundingReached else { continue }

        if dir == current.dir, advanceStep == current.advanceStep, every == current.advanceEvery,
           stride == current.stride, shift == current.shift, invert == current.invert, onRest == current.onRest { continue }
        if riffOnOthers.contains(where: {
            $0.riffDir == dir && $0.riffAdvanceStep == advanceStep && $0.riffAdvanceEvery == every &&
            $0.riffStride == stride && $0.riffShift == shift
        }) { continue }

        return EuclideousRandomRiffResult(dir: dir, advanceStep: advanceStep, advanceEvery: every, invert: invert,
                                           onRest: onRest, stride: stride, shift: shift,
                                           tag: euclideousRandomRiffTag(dir: dir, invert: invert, advanceStep: advanceStep, every: every, stride: stride))
    }
    return nil   // §5.4: NOTHING TO CHANGE
}

/// §9.3: TWEAK.
func euclideousRandomTweakRiff(current: (dir: RiffDir, advanceStep: Bool, advanceEvery: Int, invert: Bool,
                                          onRest: EuclidRiffOnRest, stride: Int, shift: Int, length: Int, hits: Int),
                                writtenRanks: [Int],
                                rng: inout EuclideousRandomRNG) -> EuclideousRandomRiffResult? {
    enum Move { case direction, every, stride, shift, hitStep, onRest }
    let options: [(Move, Int)] = [(.direction, 3), (.every, 2), (.stride, 2), (.shift, 2), (.hitStep, 1), (.onRest, 1)]

    for _ in 0..<60 {
        let move = euclideousRandomWeightedPick(options, rng: &rng)
        var dir = current.dir, every = current.advanceEvery, stride = current.stride, shift = current.shift
        var advanceStep = current.advanceStep, onRest = current.onRest
        var tag = ""
        switch move {
        case .direction:
            let pool = euclideousRandomRiffDirections.filter { $0 != current.dir }
            dir = euclideousRandomUniformPick(pool, rng: &rng)
            tag = "\(euclideousRandomRiffDirShort(current.dir))→\(euclideousRandomRiffDirShort(dir))"
        case .every:
            let newEvery = Bool.random(using: &rng) ? current.advanceEvery + 1 : current.advanceEvery - 1
            guard newEvery >= 1, newEvery <= 8 else { continue }   // raised from 4, 2026-10-22
            every = newEvery
            tag = "EVERY \(current.advanceEvery)→\(newEvery)"
        case .stride:
            let newStride = Bool.random(using: &rng) ? current.stride + 1 : current.stride - 1
            guard newStride >= 1, newStride <= 3 else { continue }
            stride = newStride
            tag = "STRIDE \(current.stride)→\(newStride)"
        case .shift:
            let n = max(1, current.length)
            let newShift = ((Bool.random(using: &rng) ? current.shift + 1 : current.shift - 1) % n + n) % n
            shift = newShift
            tag = "SHIFT \(current.shift)→\(newShift)"
        case .hitStep:
            advanceStep = !current.advanceStep
            tag = advanceStep ? "BY HIT→STEP" : "BY STEP→HIT"
        case .onRest:
            let others = ([EuclidRiffOnRest.skip, .tie, .repeatLast]).filter { $0 != current.onRest }
            onRest = euclideousRandomUniformPick(others, rng: &rng)
            tag = "ON REST \(current.onRest.rawValue)→\(onRest.rawValue)"
        }
        let (reached, soundingReached) = euclideousRandomRiffCoverage(dir: dir, every: every, stride: stride, shift: shift,
                                                                        length: current.length, hits: current.hits, writtenRanks: writtenRanks)
        guard reached.count >= Int(ceil(Double(current.length) / 2)), current.length - reached.count <= 2, soundingReached else { continue }
        return EuclideousRandomRiffResult(dir: dir, advanceStep: advanceStep, advanceEvery: every, invert: current.invert,
                                           onRest: onRest, stride: stride, shift: shift, tag: tag)
    }
    return nil
}

// MARK: - §8.5 / §9.4 NOTES

struct EuclideousRandomNotesResult: Equatable {
    var litOrder: EuclideousLitOrder
    var when: UInt8
    var chance: Int
    var playAs: EuclidNotesPlayAs
    var tag: String
}

private func euclideousRandomNotesCandidates(role: EuclideousRandomRole) -> [Int] {
    switch role {
    case .sparse: return [0, 1, 2, 3, 4]
    case .medium: return [1, 2, 3, 4, 5, 8]
    case .dense: return [2, 3, 4, 5, 6, 8, 9]
    }
}

/// The riff's own most-written rank (1...8) over columns 0..<LEN, ties to the lower rank — a plain tally
/// over the static written-ranks array, no walk involved (§8.5's "the riff's own written ranks").
func euclideousRandomRiffMostWrittenRank(writtenRanks: [Int], length: Int) -> Int? {
    var counts = [Int: Int]()
    for i in 0..<min(length, writtenRanks.count) where writtenRanks[i] >= 1 { counts[writtenRanks[i], default: 0] += 1 }
    guard !counts.isEmpty else { return nil }
    let maxCount = counts.values.max()!
    return counts.filter { $0.value == maxCount }.keys.min()
}

func euclideousRandomNotesTag(playAs: EuclidNotesPlayAs, count: Int, when: UInt8, chance: Int) -> String {
    var s = playAs.rawValue + " · \(count) NOTES"
    switch when { case 0b01: s += " · ON NOTES"; case 0b10: s += " · ON RESTS"; default: s += " · ON BOTH" }
    if chance < 100 { s += " · \(chance)%" }
    return s
}

private func euclideousRandomPlayAsWeights(_ role: EuclideousRandomRole) -> [(EuclidNotesPlayAs, Int)] {
    switch role {
    case .dense: return [(.cycle, 4), (.bounce, 3), (.build, 1), (.run, 1)]
    case .medium: return [(.roll, 2), (.run, 2), (.bounce, 2), (.cycle, 2), (.build, 2), (.split, 1)]
    case .sparse: return [(.chord, 4), (.roll, 3), (.split, 2), (.build, 1)]
    }
}

private func euclideousRandomCountOptions(_ role: EuclideousRandomRole) -> [Int] {
    switch role {
    case .dense: return [2, 3, 3, 4]
    case .medium: return [2, 3, 3]
    case .sparse: return [3, 3, 4]
    }
}

private func euclideousRandomChanceOptions(_ role: EuclideousRandomRole) -> [Int] {
    switch role {
    case .dense: return [50, 75, 75]
    case .medium: return [75, 100, 100]
    case .sparse: return [100]
    }
}

private func euclideousRandomOrderShape(_ positions: [Int], rng: inout EuclideousRandomRNG) -> [Int] {
    enum Shape { case up, down, zigzag }
    let shape = euclideousRandomUniformPick([Shape.up, .down, .zigzag], rng: &rng)
    let sorted = positions.sorted()
    switch shape {
    case .up: return sorted
    case .down: return sorted.reversed()
    case .zigzag:
        guard sorted.count >= 3 else { return sorted }
        var out = [sorted.first!, sorted.last!]
        out.append(contentsOf: sorted.dropFirst().dropLast())
        return out
    }
}

/// §8.5: THROW. `riffOn`/`writtenRanks`/`length` are this LANE's own riff layer facts (for the "remove the
/// riff's most-written rank" exclusion); `receivedCount` is 0 when unknown/nothing received (§8.5: "with
/// nothing received, remove nothing for this reason").
/// §8.5's candidate-position computation (role band ∩ "not the riff's most-written rank" ∩ RECEIVED's
/// overflow exclusion) — shared by THROW (here) and the UI's own TWEAK call site (which needs the same
/// `allowed` set but mustn't re-derive it), so the exclusion rules can't drift between the two.
func euclideousRandomAllowedNotesPositions(role: EuclideousRandomRole, riffOn: Bool, writtenRanks: [Int], length: Int,
                                            receivedOnly: Bool, receivedCount: Int) -> [Int] {
    var candidates = euclideousRandomNotesCandidates(role: role)
    if riffOn, let mostWritten = euclideousRandomRiffMostWrittenRank(writtenRanks: writtenRanks, length: length) {
        candidates.removeAll { $0 == mostWritten - 1 }   // position (mostWritten-1) == rank mostWritten, 0-based
    }
    if receivedOnly, receivedCount > 0 {
        candidates.removeAll { $0 < 8 && ($0 + 1) > receivedCount }
    }
    return candidates
}

func euclideousRandomThrowNotes(role: EuclideousRandomRole,
                                 current: (litOrder: EuclideousLitOrder, when: UInt8, chance: Int, playAs: EuclidNotesPlayAs),
                                 riffOn: Bool, writtenRanks: [Int], length: Int,
                                 receivedOnly: Bool, receivedCount: Int,
                                 rng: inout EuclideousRandomRNG) -> EuclideousRandomNotesResult? {
    let candidates = euclideousRandomAllowedNotesPositions(role: role, riffOn: riffOn, writtenRanks: writtenRanks, length: length,
                                                            receivedOnly: receivedOnly, receivedCount: receivedCount)

    for _ in 0..<80 {
        let playAs = euclideousRandomWeightedPick(euclideousRandomPlayAsWeights(role), rng: &rng)
        let count = euclideousRandomUniformPick(euclideousRandomCountOptions(role), rng: &rng)
        guard candidates.count >= count else { continue }
        if playAs == .split, count < 3 { continue }

        var pool = candidates
        var chosen: [Int] = []
        for _ in 0..<count {
            guard !pool.isEmpty else { break }
            let i = Int(rng.next() % UInt64(pool.count))
            chosen.append(pool[i]); pool.remove(at: i)
        }
        guard chosen.count == count else { continue }
        let ordered = euclideousRandomOrderShape(chosen, rng: &rng)
        var order = EuclideousLitOrder()
        for p in ordered { order.append(p) }

        var when: UInt8 = riffOn
            ? euclideousRandomWeightedPick([(UInt8(0b10), 6), (0b11, 3), (0b01, 1)], rng: &rng)
            : euclideousRandomWeightedPick([(UInt8(0b11), 7), (0b01, 3)], rng: &rng)
        let hasRest = (0..<length).contains { $0 < writtenRanks.count && writtenRanks[$0] < 1 }
        let hasNote = (0..<length).contains { $0 < writtenRanks.count && writtenRanks[$0] >= 1 }
        if when == 0b10, !hasRest { when = 0b11 }
        if when == 0b01, !hasNote { when = 0b11 }

        let chance = euclideousRandomUniformPick(euclideousRandomChanceOptions(role), rng: &rng)

        if order == current.litOrder, playAs == current.playAs, when == current.when, chance == current.chance { continue }
        return EuclideousRandomNotesResult(litOrder: order, when: when, chance: chance, playAs: playAs,
                                            tag: euclideousRandomNotesTag(playAs: playAs, count: count, when: when, chance: chance))
    }
    return nil   // §5.4: NOTHING TO CHANGE
}

/// §9.4: TWEAK — one move. `allowed` is the same candidate-exclusion set §8.5 computes (riff-rank + RECEIVED).
func euclideousRandomTweakNotes(role: EuclideousRandomRole,
                                 current: (litOrder: EuclideousLitOrder, when: UInt8, chance: Int, playAs: EuclidNotesPlayAs),
                                 allowed: [Int], riffOn: Bool, writtenRanks: [Int], length: Int,
                                 rng: inout EuclideousRandomRNG) -> EuclideousRandomNotesResult? {
    enum Move { case swap, playAs, order, add, drop, chance, when }
    var weights: [(Move, Int)] = [(.swap, 4), (.playAs, 3), (.add, 1), (.drop, 1), (.chance, 1), (.when, 1)]
    let usesOrder: Bool = [.roll, .run, .cycle, .bounce, .build].contains(current.playAs)
    if usesOrder { weights.append((.order, 2)) }

    let playAsNeighbors: [EuclidNotesPlayAs: [EuclidNotesPlayAs]] = [
        .chord: [.roll, .split], .roll: [.chord, .run], .run: [.roll, .cycle], .cycle: [.bounce, .run],
        .bounce: [.cycle, .build], .split: [.chord, .build], .build: [.split, .bounce]
    ]
    let hasRest = (0..<length).contains { $0 < writtenRanks.count && writtenRanks[$0] < 1 }
    let hasNote = (0..<length).contains { $0 < writtenRanks.count && writtenRanks[$0] >= 1 }

    for _ in 0..<60 {
        let move = euclideousRandomWeightedPick(weights, rng: &rng)
        var order = current.litOrder
        var playAs = current.playAs, when = current.when, chance = current.chance
        var tag = ""
        func label(_ p: Int) -> String { p == EuclideousLitOrder.topPosition ? "TOP" : (p == EuclideousLitOrder.topTwoPosition ? "TOP2" : "RANK \(p + 1)") }
        switch move {
        case .swap:
            guard order.count > 0 else { continue }
            let i = Int(rng.next() % UInt64(order.count))
            let pos = order[i]
            guard pos < 8 else { continue }
            let neighbor = Bool.random(using: &rng) ? pos + 1 : pos - 1
            guard neighbor >= 0, neighbor < 8, !order.contains(neighbor), allowed.contains(neighbor) else { continue }
            order.remove(pos); order.append(neighbor)
            tag = "\(label(pos))→\(label(neighbor))"
        case .playAs:
            guard let pool = playAsNeighbors[current.playAs], !pool.isEmpty else { continue }
            playAs = euclideousRandomUniformPick(pool, rng: &rng)
            if playAs == .split, order.count < 3 { continue }
            tag = "\(current.playAs.rawValue)→\(playAs.rawValue)"
        case .order:
            guard order.count >= 2 else { continue }
            if Bool.random(using: &rng) {
                var reversed = EuclideousLitOrder()
                for p in order.array.reversed() { reversed.append(Int(p)) }
                order = reversed; tag = "ORDER REVERSED"
            } else {
                var rotated = EuclideousLitOrder()
                let arr = order.array
                for p in arr.dropFirst() { rotated.append(Int(p)) }
                if let f = arr.first { rotated.append(Int(f)) }
                order = rotated; tag = "ORDER ROTATED"
            }
        case .add:
            guard order.count >= 1, order.count <= 3 else { continue }
            let near = allowed.filter { c in !order.contains(c) && order.array.contains { abs(Int($0) - c) <= 2 } }
            guard !near.isEmpty else { continue }
            let pick = euclideousRandomUniformPick(near, rng: &rng)
            order.append(pick)
            tag = "+ \(label(pick))"
        case .drop:
            guard order.count >= 3 else { continue }
            let i = Int(rng.next() % UInt64(order.count))
            let pos = order[i]
            order.remove(pos)
            tag = "− \(label(pos))"
        case .chance:
            let newChance = Bool.random(using: &rng) ? current.chance + 25 : current.chance - 25
            guard newChance >= 25, newChance <= 100 else { continue }
            chance = newChance
            tag = "CHANCE \(current.chance)→\(newChance)%"
        case .when:
            var pool: [UInt8] = [0b01, 0b10, 0b11].filter { $0 != current.when }
            pool.removeAll { $0 == 0b10 && !hasRest }
            pool.removeAll { $0 == 0b01 && !hasNote }
            guard !pool.isEmpty else { continue }
            when = euclideousRandomUniformPick(pool, rng: &rng)
            tag = "WHEN \(whenName(current.when))→\(whenName(when))"
        }
        if playAs == .split, order.count < 3 { continue }
        if order.count == 0, current.litOrder.count == 0 { continue }
        return EuclideousRandomNotesResult(litOrder: order, when: when, chance: chance, playAs: playAs, tag: tag)
    }
    return nil
}

private func whenName(_ w: UInt8) -> String { w == 0b01 ? "PLAYS" : (w == 0b10 ? "RESTS" : "BOTH") }

// MARK: - §6 Future-beat landing

enum EuclideousRandomTab: Int, Equatable, CaseIterable { case rhythm = 0, riff = 1, notes = 2 }

/// §3-§7: one card-tab's own random-mode bookkeeping. `original` is non-nil exactly when the tab has an
/// undecided roll (§3.4's dot, §6.6's "the tab's state just before a landing becomes the roll's original").
/// `waiting` is non-nil while a THROW/TWEAK/BACK is queued for the next bar/beat (§3.6's "NEXT BAR" caption).
struct EuclideousRandomRollState: Equatable {
    enum Waiting: Equatable { case throwing, tweaking, back }
    /// The CURRENT roll's own original (§5.6's ghost, §5.2's BACK target) — reset each time a new
    /// undecided roll starts (including right after a KEEP, per §6.6: "a later throw or tweak... starts a
    /// new undecided roll whose original is the state KEEP locked in").
    var original: EuclidLine?
    var decided = true
    /// The tab's state from BEFORE random mode touched it AT ALL this session — captured once, on the
    /// first roll, held until the session ends (§7.2 needs this baseline; `original` above isn't it once
    /// a KEEP has happened mid-session).
    var sessionBaseline: EuclidLine?
    var goes = 0
    var tag = ""
    var waiting: Waiting?
    var decidedAt: Date?   // §7.3: when KEEP/a landed BACK decided this tab — drives the two-bar "KEPT" caption
    var isUndecided: Bool { !decided }
}

/// §6.1/§6.3: a per-lane pending override. Reaches the render thread via `Kernel.setEuclideousPendingRolls`
/// — the SAME plain main-thread-writes/render-thread-reads hand-off `Kernel.euclideousSoloLive` already
/// uses for live UI state, not the Snapshot/SnapParams pipeline (never on `EuclidLine` — its Codable/
/// Equatable surface must stay untouched; `EuclidLine` is reused wholesale by both the persisted
/// `MachineParams.euclidLines` and the render-time `SnapParams.euclidLines`, so a new stored property
/// there would both leak into the save file's encoding and change what "two lines are equal" means
/// everywhere that's checked). `landingBeat` is an ABSOLUTE beat, the same unit/origin Router's own
/// `beatPos`/`beatsPerBar` already use (restart chains' own convention: bar lines are multiples of
/// `beatsPerBar` from beat 0 — no second phase/origin concept).
struct EuclideousPendingRoll: Equatable {
    var tab: EuclideousRandomTab
    var landingBeat: Double
    // rhythm
    var steps: Int = 0
    var pulses: Int = 0
    var rotate: Int = 0
    // riff
    var riffDir: RiffDir = .forward
    var riffInvert: Bool = false
    var riffAdvanceEvery: Int = 1
    var riffAdvanceStep: Bool = false
    var riffOnRest: EuclidRiffOnRest = .skip
    var riffRotate: Int = 0
    var riffStride: Int = 1
    // notes
    var notesLitOrder: EuclideousLitOrder = EuclideousLitOrder()
    var notesWhen: UInt8 = 0b11
    var notesChance: Int = 100
    var notesPlayAs: EuclidNotesPlayAs = .chord
}

/// §6.1-6.2: the one comparison both Router (per-tick, sample-accurate) and the UI's own poll (bookkeeping
/// only) must use — never two formulas for "has it landed."
@inline(__always)
func euclideousRandomShouldApply(hostBeat: Double, landingBeat: Double) -> Bool { hostBeat >= landingBeat }

/// §6.1: "one slot per card tab" — a lane can have THREE independent rolls in flight at once (one per tab),
/// not one. The flat index every reader/writer of the pending-rolls storage uses, so none can drift.
@inline(__always)
func euclideousRandomPendingSlot(lane: Int, tab: EuclideousRandomTab) -> Int { lane * 3 + tab.rawValue }

/// Fixed-size (12-slot), VALUE-type-only storage for `euclideousPendingRolls`/`euclideousHoldOverrides` —
/// the main-thread-writes/render-thread-reads hand-off these two channels use (Kernel's own doc comment).
/// Deliberately NOT `[EuclideousPendingRoll?]`: a plain Array is a pointer to a class-backed, reference-
/// counted heap buffer, so reassigning the WHOLE property from the main thread while the render thread
/// concurrently reads it races on that buffer's OWN refcount — a genuine use-after-free hazard class
/// under the wrong interleaving, not just a stale read, and a materially different risk than the plain
/// scalar hand-off (`euclideousSoloLive`) this was modelled on. A tuple of 12 plain optionals has no
/// shared heap buffer to race over at all: each side gets its own independent VALUE the instant it reads
/// or assigns the property, so the worst case left is the same bounded staleness every other plain-var
/// hand-off here already accepts (one render call seeing one slot's old value next to another's new one)
/// — never a crash. Architecture invariant #3: "fixed-size storage only" on the render path.
struct EuclideousPendingRollSlots: Equatable, Collection {
    static let count = 12
    private var slots: (EuclideousPendingRoll?, EuclideousPendingRoll?, EuclideousPendingRoll?, EuclideousPendingRoll?,
                         EuclideousPendingRoll?, EuclideousPendingRoll?, EuclideousPendingRoll?, EuclideousPendingRoll?,
                         EuclideousPendingRoll?, EuclideousPendingRoll?, EuclideousPendingRoll?, EuclideousPendingRoll?)
        = (nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil)

    init() {}

    // Collection, so `for roll in rolls` / `.contains(where:)` / `.firstIndex(...)` keep working exactly
    // as they did against `[EuclideousPendingRoll?]` — index(after:) is the only Collection requirement
    // not already covered by the stored properties below.
    var startIndex: Int { 0 }
    var endIndex: Int { Self.count }
    func index(after i: Int) -> Int { i + 1 }

    subscript(i: Int) -> EuclideousPendingRoll? {
        get {
            switch i {
            case 0: return slots.0; case 1: return slots.1; case 2: return slots.2; case 3: return slots.3
            case 4: return slots.4; case 5: return slots.5; case 6: return slots.6; case 7: return slots.7
            case 8: return slots.8; case 9: return slots.9; case 10: return slots.10; case 11: return slots.11
            default: return nil
            }
        }
        set {
            switch i {
            case 0: slots.0 = newValue; case 1: slots.1 = newValue; case 2: slots.2 = newValue; case 3: slots.3 = newValue
            case 4: slots.4 = newValue; case 5: slots.5 = newValue; case 6: slots.6 = newValue; case 7: slots.7 = newValue
            case 8: slots.8 = newValue; case 9: slots.9 = newValue; case 10: slots.10 = newValue; case 11: slots.11 = newValue
            default: break
            }
        }
    }

    static func == (a: EuclideousPendingRollSlots, b: EuclideousPendingRollSlots) -> Bool {
        for i in 0..<count where a[i] != b[i] { return false }
        return true
    }
}

/// The displayed OFFSET ↔ stored `rotate` mirror — the EXACT formula `EuclidLine.offsetRequestedResolved`/
/// `euclideousSliderCommit(.offset)` already use (Derivations.swift), reused rather than re-derived so a
/// roll's OFFSET always means what the RHYTHM tab's own OFFSET control already means.
@inline(__always)
func euclideousRandomDisplayedOffset(rotate: Int, steps: Int) -> Int {
    let n = max(2, min(16, steps))
    let r = ((rotate % n) + n) % n
    return (n - r) % n
}
@inline(__always)
func euclideousRandomRotateFromDisplayed(offset: Int, steps: Int) -> Int {
    let n = max(2, min(16, steps))
    let d = ((offset % n) + n) % n
    return (n - d) % n
}

/// §6.7: the main thread's own write once a roll has landed — direct field writes, mirroring the AUTO-ramp
/// precedent (`Snapshot.swift`'s own `euclidPulses`/`euclidRot` writer), never `euclideousSliderCommit`
/// (§6.7: "Not through the STEPS setter") or `euclideousSetRiffShift`. Pins both restart chains first if the
/// lane is still on the pre-chains model (idempotent — a no-op once pinned, so calling this on every landing
/// is safe regardless of session history).
func euclideousRandomCommitPendingRoll(_ roll: EuclideousPendingRoll, into line: inout EuclidLine) {
    switch roll.tab {
    case .rhythm:
        if !line.usesRestartChains {
            euclideousPinRestartChains(&line, .from(line.restartRhythmBars ?? []), .from(line.restartMelodyPasses ?? []))
        }
        line.steps = roll.steps; line.pulses = roll.pulses; line.rotate = roll.rotate
        line.hitsRequested = nil; line.offsetRequested = nil
        line.offsetFraction = nil   // RHYTHM POLISH §4.1: a randomise sets rotate another way, so the fraction goes with it
    case .riff:
        line.riffDir = roll.riffDir; line.riffInvert = roll.riffInvert
        line.riffAdvanceEvery = roll.riffAdvanceEvery; line.riffAdvanceStep = roll.riffAdvanceStep
        line.riffOnRest = roll.riffOnRest; line.riffStride = roll.riffStride
        line.riffRotate = roll.riffRotate; line.riffShiftRequested = nil   // RIFF ferry §4.3: a writer that sets riffRotate some other way nils this instead
    case .notes:
        line.notesLitOrder = roll.notesLitOrder.array
        line.notesWhen = roll.notesWhen; line.notesChance = roll.notesChance; line.notesPlayAs = roll.notesPlayAs
    }
}

/// §6.1: the next bar line at or after `afterBeat + marginBeats`, on the SAME "bar lines are multiples of
/// `barBeats` from beat 0" convention the restart chains already use (Router.swift's `EuclideousLaneRestartChains`).
func euclideousRandomNextBarLine(afterBeat: Double, barBeats: Double, marginBeats: Double) -> Double {
    guard barBeats > 0 else { return afterBeat }
    let target = afterBeat + marginBeats
    let bar = (target / barBeats).rounded(.down) + 1
    return bar * barBeats
}

/// §6.1: 150 ms safety margin (a judgment call — see the ferry report), converted to beats at `tempo` BPM.
func euclideousRandomLandingMarginBeats(tempo: Double) -> Double {
    guard tempo > 0 else { return 0.5 }
    return 0.15 * tempo / 60.0
}

/// §6.4: when the page isn't running (no bar line to wait for), a request lands at once — the queuing
/// site's own choice of `landingBeat`, not a Router-side special case (Router only ever compares beats).
func euclideousRandomQueuedLandingBeat(running: Bool, currentBeat: Double, barBeats: Double, marginBeats: Double) -> Double {
    running ? euclideousRandomNextBarLine(afterBeat: currentBeat, barBeats: barBeats, marginBeats: marginBeats) : currentBeat
}

/// §5.6: the hold switches "from the next beat" — the SAME bar-line formula with a one-beat period
/// (never a second "what's the next boundary" formula), so the hold's margin behaves identically to
/// THROW/TWEAK/BACK's own bar-line landing.
func euclideousRandomQueuedHoldBeat(running: Bool, currentBeat: Double, marginBeats: Double) -> Double {
    euclideousRandomQueuedLandingBeat(running: running, currentBeat: currentBeat, barBeats: 1, marginBeats: marginBeats)
}

// MARK: - §7.2 Undo-sequence builder

/// One kept card-tab, in the order §7.2 wants pushed: KEEP-order first, then finish-order (lane, then
/// RHYTHM/RIFF/NOTES). `original` is the FULL lane state to revert ONLY this tab's own fields to.
struct EuclideousRandomUndoEntry {
    var lane: Int
    var tab: EuclideousRandomTab
    var original: EuclidLine
}

/// Copies only `tab`'s own fields from `from` onto `into` — never the whole line (another tab on the same
/// lane may already hold its own, independently-kept state).
func euclideousRandomApplyTabFields(from original: EuclidLine, tab: EuclideousRandomTab, into line: inout EuclidLine) {
    switch tab {
    case .rhythm:
        // Neither Throw/TweakRhythm ever touches the restart chains, so this undo/equality scope must
        // not either — otherwise an unrelated chain edit made mid-session on the same lane would get
        // smuggled into (or reverted by) this tab's own random-mode undo step.
        line.steps = original.steps; line.pulses = original.pulses; line.rotate = original.rotate
        line.hitsRequested = original.hitsRequested; line.offsetRequested = original.offsetRequested
        line.offsetFraction = original.offsetFraction   // RHYTHM POLISH: BACK / undo restores the fraction the roll cleared
    case .riff:
        line.riffDir = original.riffDir; line.riffInvert = original.riffInvert
        line.riffAdvanceEvery = original.riffAdvanceEvery; line.riffAdvanceStep = original.riffAdvanceStep
        line.riffOnRest = original.riffOnRest; line.riffRotate = original.riffRotate
        line.riffShiftRequested = original.riffShiftRequested; line.riffStride = original.riffStride
    case .notes:
        line.notesLitOrder = original.notesLitOrder; line.notesWhen = original.notesWhen
        line.notesChance = original.notesChance; line.notesPlayAs = original.notesPlayAs
    }
}

/// §7.2's own last line: "a tab that was rolled and then put back with BACK records nothing" — compares
/// ONLY the tab's own fields (never the whole line, which may differ for unrelated reasons), via the SAME
/// field groups `euclideousRandomApplyTabFields` touches, so the two can't drift.
func euclideousRandomTabFieldsEqual(_ a: EuclidLine, _ b: EuclidLine, tab: EuclideousRandomTab) -> Bool {
    var la = EuclidLine(); euclideousRandomApplyTabFields(from: a, tab: tab, into: &la)
    var lb = EuclidLine(); euclideousRandomApplyTabFields(from: b, tab: tab, into: &lb)
    return la == lb
}

/// §7.2: builds `[S0, ..., S_{N-1}]` to push (in order, each with `coalesceKey: nil`) so one undo restores
/// exactly one kept card-tab, latest first, ending at `settled` (the live document — already correct,
/// nothing further to push for it). `entries` must already be in §7.2's own push order.
func euclideousRandomUndoSequence(settled: EuclideousUndoSnapshot, entries: [EuclideousRandomUndoEntry]) -> [EuclideousUndoSnapshot] {
    guard !entries.isEmpty else { return [] }
    var sequence: [EuclideousUndoSnapshot] = []
    var acc = settled
    for lane in Set(entries.map { $0.lane }) {
        for entry in entries where entry.lane == lane {
            euclideousRandomApplyTabFields(from: entry.original, tab: entry.tab, into: &acc.lines[lane])
        }
    }
    // `acc` is now S0 (every kept tab reverted). Walk forward, re-applying one tab at a time, in order.
    sequence.append(acc)
    for entry in entries {
        euclideousRandomApplyTabFields(from: settled.lines[entry.lane], tab: entry.tab, into: &acc.lines[entry.lane])
        sequence.append(acc)
    }
    return Array(sequence.dropLast())   // the last element equals `settled`, already live — don't push it
}

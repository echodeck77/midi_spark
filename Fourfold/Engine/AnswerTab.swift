//  AnswerTab.swift
//  ANSWER ferry (2026-11-02; LISTEN renamed): the pure functions behind the ANSWER tab's rows, its CYCLE and its TRADE — Foundation only, allocation-free where the render thread reads them, and tested in `AnswerTabTests`.
//  The engine and every display call these and nothing else: no second derivation of "who follows whom", "which phase is it" or "whose strikes does this lane emit" anywhere (spec §11).
//
//  Vocabulary: a row (RHYTHM, PITCH) has a SWITCH, a remembered MODE and a CYCLE flag; TRADE has a switch, a mode (SWAP · BORROW) and a WITH lane and ALWAYS cycles. A lane has ONE cycle: EACH units (1…16) of BARS or PASSES.
//  A cycling lane alternates PHASE A (the lane exactly as set) and PHASE B (a cycling row acts as if switched off; TRADE, if on, substitutes the WITH lane's own strikes), EACH units each, A first, counted from transport start.

import Foundation

// MARK: - 11.1 – 11.6: following, cycling, phase, rows, source

enum EuclideousCyclePhase: Equatable { case a, b }

/// 11.1 — a lane FOLLOWS another lane while RHYTHM or PITCH is on (a cycling row still counts; TRADE never does).
@inline(__always) func euclideousAnswerIsFollowing(rhythmOn: Bool, pitchOn: Bool) -> Bool { rhythmOn || pitchOn }

/// 11.2 — does the lane have a cycle (the CYCLE row is shown, the engine alternates phases)? A row with CYCLE on counts only while it is switched on; TRADE always cycles.
@inline(__always) func euclideousAnswerHasCycle(rhythmOn: Bool, rhythmCycle: Bool, pitchOn: Bool, pitchCycle: Bool, tradeOn: Bool) -> Bool {
    (rhythmOn && rhythmCycle) || (pitchOn && pitchCycle) || tradeOn
}
@inline(__always) func euclideousAnswerHasCycle(_ l: EuclidLine) -> Bool {
    euclideousAnswerHasCycle(rhythmOn: l.answerRhythmOnResolved, rhythmCycle: l.answerRhythmCycleResolved, pitchOn: l.answerPitchOnResolved,
                             pitchCycle: l.answerPitchCycleResolved, tradeOn: l.answerTradeOnResolved)
}

/// 11.3 — EACH units A, EACH units B, A again. `unitsSinceStart` is the number of whole units elapsed since the transport started (0 = the first). Negative counts as 0.
@inline(__always) func euclideousCyclePhase(unitsSinceStart: Int, each: Int) -> EuclideousCyclePhase {
    let e = max(1, each)
    return (max(0, unitsSinceStart) / e) % 2 == 0 ? .a : .b
}

/// A SWAP pair is two lanes that SWAP with each other: the lane's partner, or nil. (A SWAP whose partner does not SWAP back is not a pair — `euclideousNormalizeTrades` switches such a TRADE off at load, 6.5.)
func euclideousAnswerPairPartner(lane: Int, lines: [EuclidLine]) -> Int? {
    let n = min(4, lines.count)
    guard lane >= 0, lane < n else { return nil }
    let l = lines[lane]
    guard l.answerTradeOnResolved, l.answerTradeModeResolved == .swap else { return nil }
    let w = l.answerTradeWithResolved(ownLane: lane)
    guard w < n else { return nil }
    let p = lines[w]
    guard p.answerTradeOnResolved, p.answerTradeModeResolved == .swap, p.answerTradeWithResolved(ownLane: w) == lane else { return nil }
    return w
}
/// 11.4 — the lane whose units count this lane's phase: itself, or the LOWER-numbered lane of its SWAP pair (both lanes of a pair share one phase).
func euclideousAnswerPhaseLane(lane: Int, lines: [EuclidLine]) -> Int {
    if let p = euclideousAnswerPairPartner(lane: lane, lines: lines) { return min(lane, p) }
    return lane
}

/// 11.5 — which rows ACT in a phase. Phase A: the rows that are on. Phase B: a row that is on WITH cycle acts as if switched off (the lane plays its own rhythm / its own riff and NOTES); a row on without cycle keeps acting.
struct EuclideousAnswerRows: Equatable { var rhythm: Bool; var pitch: Bool }
@inline(__always) func euclideousAnswerEffectiveRows(phase: EuclideousCyclePhase, rhythmOn: Bool, rhythmCycle: Bool, pitchOn: Bool, pitchCycle: Bool) -> EuclideousAnswerRows {
    phase == .a ? EuclideousAnswerRows(rhythm: rhythmOn, pitch: pitchOn)
                : EuclideousAnswerRows(rhythm: rhythmOn && !rhythmCycle, pitch: pitchOn && !pitchCycle)
}
@inline(__always) func euclideousAnswerEffectiveRows(_ l: EuclidLine, phase: EuclideousCyclePhase) -> EuclideousAnswerRows {
    euclideousAnswerEffectiveRows(phase: phase, rhythmOn: l.answerRhythmOnResolved, rhythmCycle: l.answerRhythmCycleResolved,
                                  pitchOn: l.answerPitchOnResolved, pitchCycle: l.answerPitchCycleResolved)
}
/// The lane as it PLAYS in a phase: the same line with `answerRhythmOn` / `answerPitchOn` replaced by the rows that act. The displays (strip, riff marker, FX idle reasons, borrowed cards…) read this so they follow the phase
/// without a second rule; the engine feeds the same two booleans to `runEuclidLine`.
func euclideousAnswerEffectiveLine(_ l: EuclidLine, phase: EuclideousCyclePhase) -> EuclidLine {
    guard phase == .b else { return l }
    let rows = euclideousAnswerEffectiveRows(l, phase: .b)
    var out = l
    if out.answerRhythmOnResolved != rows.rhythm { out.answerRhythmOn = rows.rhythm }
    if out.answerPitchOnResolved != rows.pitch { out.answerPitchOn = rows.pitch }
    return out
}

/// 11.6 — whose OWN strikes this lane emits: its own, except in phase B with TRADE on, when it is the WITH lane's.
@inline(__always) func euclideousAnswerEmitSource(lane: Int, phase: EuclideousCyclePhase, tradeOn: Bool, tradeWith: Int) -> Int {
    (phase == .b && tradeOn) ? tradeWith : lane
}

// MARK: - 11.8: the phase bar

/// 4.3 — the two halves' colours, as LANE INDICES (the view maps them through the lane colours): half A is the source's if RHYTHM or PITCH is on with CYCLE on, else the lane's own; half B is the WITH lane's if TRADE is on, else the lane's own.
struct EuclideousPhaseColours: Equatable { var a: Int; var b: Int }
func euclideousAnswerPhaseColours(lane: Int, line: EuclidLine) -> EuclideousPhaseColours {
    let cyclingRow = (line.answerRhythmOnResolved && line.answerRhythmCycleResolved) || (line.answerPitchOnResolved && line.answerPitchCycleResolved)
    return EuclideousPhaseColours(a: cyclingRow ? line.listenSourceResolved(ownLane: lane) : lane,
                                  b: line.answerTradeOnResolved ? line.answerTradeWithResolved(ownLane: lane) : lane)
}
/// 4.2 — the playhead's place across the bar, 0…1: (units elapsed in this A-then-B cycle + the fraction of the current unit elapsed) ÷ (2 × EACH).
func euclideousAnswerPhaseProgress(unitsSinceStart: Int, fractionOfUnit: Double, each: Int) -> Double {
    let e = max(1, each)
    let inCycle = max(0, unitsSinceStart) % (2 * e)
    let f = fractionOfUnit.isFinite ? max(0, min(1, fractionOfUnit)) : 0
    return min(1, (Double(inCycle) + f) / Double(2 * e))
}

// MARK: - 11.9: the borrowed tabs

/// §8 — which tabs are BORROWED (drawn at 18 %, untouchable, with the card over them): RHYTHM while it is on with CYCLE off; RIFF while PITCH is on, SHADOW is chosen and CYCLE is off (AVOID, or a cycling PITCH, is not borrowed);
/// NOTES pauses with RIFF when it reads the riff. TRADE never pauses a tab (8.6).
func euclideousAnswerBorrowedTabs(rhythmOn: Bool, rhythmCycle: Bool, pitchOn: Bool, pitchMode: EuclideousAnswerPitchMode, pitchCycle: Bool, notesReadsRiff: Bool) -> EuclideousListenBorrowedTabs {
    let riff = pitchOn && pitchMode == .shadow && !pitchCycle
    return EuclideousListenBorrowedTabs(rhythm: rhythmOn && !rhythmCycle, riff: riff, notes: riff && notesReadsRiff)
}
func euclideousAnswerBorrowedTabs(_ l: EuclidLine, notesReadsRiff: Bool) -> EuclideousListenBorrowedTabs {
    euclideousAnswerBorrowedTabs(rhythmOn: l.answerRhythmOnResolved, rhythmCycle: l.answerRhythmCycleResolved, pitchOn: l.answerPitchOnResolved,
                                 pitchMode: l.answerPitchModeResolved, pitchCycle: l.answerPitchCycleResolved, notesReadsRiff: notesReadsRiff)
}

// MARK: - 5.3: phase is decided at unit boundaries only

/// The engine state behind one lane's phase (9.5: engine state — never saved, never an undo step). The settings a lane runs on (`active`, `each`, `unit`) are LATCHED: a change to EACH or UNIT, or anything that starts or ends a cycle,
/// reaches the latch only at the next boundary of the unit then in force, and the phase is decided only there. `known` is false until the lane has been looked at: its first look adopts the unit in force without starting a cycle
/// (a cycle starts at the NEXT boundary), except at the transport start, which is itself a boundary.
struct EuclideousCycleLatch: Equatable {
    var known = false
    var active = false
    var each = euclideousAnswerCycleEachDefault
    var unit: EuclideousAnswerCycleUnit = .bars
    var phase: EuclideousCyclePhase = .a

    mutating func reset() { self = EuclideousCycleLatch() }
    /// First look at a lane mid-run: stand by on the unit in force; nothing cycles until a boundary of it.
    mutating func standBy(liveUnit: EuclideousAnswerCycleUnit) {
        known = true; active = false; unit = liveUnit; phase = .a
    }
    /// A boundary of the unit in force (or the transport start): take the live settings, then decide the phase from the units elapsed since the start, counted in the unit NOW in force.
    mutating func boundary(liveActive: Bool, liveEach: Int, liveUnit: EuclideousAnswerCycleUnit, barUnitsSinceStart: Int, passUnitsSinceStart: Int) {
        known = true
        active = liveActive
        each = max(euclideousAnswerCycleEachMin, min(euclideousAnswerCycleEachMax, liveEach))
        unit = liveUnit
        phase = liveActive ? euclideousCyclePhase(unitsSinceStart: liveUnit == .bars ? barUnitsSinceStart : passUnitsSinceStart, each: each) : .a
    }
}

// MARK: - 11.7: TRADE pairing

/// One edit to a lane's TRADE / CYCLE settings, as the ANSWER tab makes it.
enum EuclideousTradeEdit: Equatable {
    case on(Bool)
    case mode(EuclideousAnswerTradeMode)
    case with(Int)
    case each(Int)
    case unit(EuclideousAnswerCycleUnit)
}
/// 6.4 — apply `edit` to `lane` and keep SWAP pairs consistent, returning ALL four lines (the caller writes them in ONE edit = one undo step for every lane it changes, 6.4e):
///  a. TRADE on, SWAP, WITH Y on lane X sets Y to TRADE on, SWAP, WITH X and copies X's EACH and UNIT to Y.
///  b. If Y was in a SWAP with Z, Z's TRADE switches off (its mode and WITH kept). If Y was BORROWing, that is replaced.
///  c. TRADE off on either lane of a pair switches both off. A mode change to BORROW, or a WITH to another lane, on either lane of a pair switches the OTHER lane's TRADE off; a new WITH under SWAP pairs per a.
///  d. EACH and UNIT edited on either lane of a pair write both.
func euclideousApplyTradeEdit(_ lines: [EuclidLine], lane x: Int, edit: EuclideousTradeEdit) -> [EuclidLine] {
    var L = lines
    let n = min(4, L.count)
    guard x >= 0, x < n else { return L }
    let oldPartner = euclideousAnswerPairPartner(lane: x, lines: L)
    switch edit {
    case .each(let v):
        let c = max(euclideousAnswerCycleEachMin, min(euclideousAnswerCycleEachMax, v))
        L[x].answerCycleEach = c
        if let p = oldPartner { L[p].answerCycleEach = c }
        return L
    case .unit(let u):
        L[x].answerCycleUnit = u
        if let p = oldPartner { L[p].answerCycleUnit = u }
        return L
    case .on(let on):
        L[x].answerTradeOn = on
        if !on { if let p = oldPartner { L[p].answerTradeOn = false }; return L }
    case .mode(let m):
        L[x].answerTradeMode = m
        if m == .borrow { if let p = oldPartner { L[p].answerTradeOn = false }; return L }
    case .with(let w):
        guard w != x, w >= 0, w < n else { return L }
        L[x].answerTradeWith = w
        if let p = oldPartner, p != w { L[p].answerTradeOn = false }
    }
    guard L[x].answerTradeOnResolved, L[x].answerTradeModeResolved == .swap else { return L }
    let y = L[x].answerTradeWithResolved(ownLane: x)
    guard y < n else { return L }
    if let z = euclideousAnswerPairPartner(lane: y, lines: L), z != x { L[z].answerTradeOn = false }
    L[x].answerTradeWith = y
    L[y].answerTradeOn = true; L[y].answerTradeMode = .swap; L[y].answerTradeWith = x
    L[y].answerCycleEach = L[x].answerCycleEachResolved; L[y].answerCycleUnit = L[x].answerCycleUnitResolved
    return L
}

/// 6.5 — a loaded document, a preset or an undo result: walking lanes 1 → 4, a SWAP whose partner does not SWAP back has its TRADE switched off; a pair whose EACH or UNIT differ takes the lower-numbered lane's. `changes` is the load
/// log (one line each). Idempotent.
func euclideousNormalizeTrades(_ lines: [EuclidLine]) -> (lines: [EuclidLine], changes: [String]) {
    var L = lines
    var log: [String] = []
    let n = min(4, L.count)
    for i in 0..<n where L[i].answerTradeOnResolved && L[i].answerTradeModeResolved == .swap {
        if euclideousAnswerPairPartner(lane: i, lines: L) == nil {
            L[i].answerTradeOn = false
            log.append("ANSWER: lane \(i + 1) SWAPs with lane \(L[i].answerTradeWithResolved(ownLane: i) + 1), which does not SWAP back; its TRADE is switched off")
        }
    }
    for i in 0..<n {
        guard let p = euclideousAnswerPairPartner(lane: i, lines: L), p > i else { continue }
        if L[p].answerCycleEachResolved != L[i].answerCycleEachResolved || L[p].answerCycleUnitResolved != L[i].answerCycleUnitResolved {
            L[p].answerCycleEach = L[i].answerCycleEachResolved; L[p].answerCycleUnit = L[i].answerCycleUnitResolved
            log.append("ANSWER: lanes \(i + 1) and \(p + 1) SWAP with different EACH or UNIT; lane \(p + 1) takes lane \(i + 1)'s")
        }
    }
    return (L, log)
}
extension PluginState {
    /// 6.5: run wherever a document is loaded (a session, a user preset), beside `normalizeLocksAtLoad`. The load log is a stderr line, one per change (there is no in-app log).
    mutating func normalizeTradesAtLoad() {
        guard euclideousLines != nil else { return }
        let r = euclideousNormalizeTrades(euclideousLinesResolved)
        guard !r.changes.isEmpty else { return }
        euclideousLines = r.lines
        for c in r.changes { FileHandle.standardError.write(Data((c + "\n").utf8)) }
    }
}

// MARK: - 2.x: the ANSWER tab's layout

/// ANSWER's body: FOLLOW, RHYTHM, PITCH, [the PITCH panel while PITCH is on with SHADOW], TRADE, [the CYCLE row while something cycles], sp8 apart, in `contentAreaH` (229 / 229.67 at the reference card). Rows are 44 pt when they fit;
/// otherwise the space left after every row's 30 pt floor (the panel's is 38: a 30 pt stepper in 4 pt padding) is shared out in proportion to how much each could still grow. `fits` is false only when even the floors do not fit —
/// nothing ever draws below its floor. The CYCLE row's phase bar needs 5; its steppers are the same 30 pt floor.
struct EuclideousAnswerTabLayout: Equatable {
    var followRowH: CGFloat, rhythmRowH: CGFloat, pitchRowH: CGFloat
    var pitchPanelH: CGFloat       // 0 unless PITCH is on with SHADOW — no space kept
    var tradeRowH: CGFloat
    var cycleRowH: CGFloat         // 0 unless something cycles — no space kept
    var gap: CGFloat
    var fits: Bool
    /// Top to bottom: the heights actually drawn (absent rows left out).
    var heights: [CGFloat] {
        var h: [CGFloat] = [followRowH, rhythmRowH, pitchRowH]
        if pitchPanelH > 0 { h.append(pitchPanelH) }
        h.append(tradeRowH)
        if cycleRowH > 0 { h.append(cycleRowH) }
        return h
    }
    var totalHeight: CGFloat { heights.reduce(0, +) + gap * CGFloat(heights.count - 1) }
}
enum EuclideousAnswerTabMetrics {
    static let gap: CGFloat = 8, rowIdeal: CGFloat = 44, rowFloor: CGFloat = 30
    static let panelPad: CGFloat = 4, panelIdeal: CGFloat = 52, panelFloor: CGFloat = 38
    static let labelColumn: CGFloat = 50
}
func euclideousAnswerTabLayout(contentAreaH: CGFloat, pitchPanelShown: Bool, cycleRowShown: Bool) -> EuclideousAnswerTabLayout {
    typealias M = EuclideousAnswerTabMetrics
    var ideals: [CGFloat] = [M.rowIdeal, M.rowIdeal, M.rowIdeal]      // FOLLOW, RHYTHM, PITCH
    var floors: [CGFloat] = [M.rowFloor, M.rowFloor, M.rowFloor]
    if pitchPanelShown { ideals.append(M.panelIdeal); floors.append(M.panelFloor) }
    ideals.append(M.rowIdeal); floors.append(M.rowFloor)               // TRADE
    if cycleRowShown { ideals.append(M.rowIdeal); floors.append(M.rowFloor) }
    let gaps = CGFloat(ideals.count - 1) * M.gap
    let avail = contentAreaH - gaps
    let floorSum = floors.reduce(0, +)
    let growRoom = zip(ideals, floors).map { $0 - $1 }
    let extra = avail - floorSum
    var heights = floors
    if extra > 0 {
        let totalRoom = growRoom.reduce(0, +)
        let share = totalRoom > 0 ? min(1, extra / totalRoom) : 0
        for i in 0..<heights.count { heights[i] = floors[i] + (growRoom[i] * share).rounded(.down) }
    }
    // Whole points still unspent go to the PITCH panel (the one flexible row, up to its ideal) so the rows stay equal.
    if pitchPanelShown, extra > 0 {
        let used = heights.reduce(0, +)
        let panelIdx = 3
        heights[panelIdx] += max(0, min(M.panelIdeal - heights[panelIdx], (avail - used).rounded(.down)))
    }
    var i = 0
    func next() -> CGFloat { let h = heights[i]; i += 1; return h }
    let follow = next(), rhythm = next(), pitch = next()
    let panel = pitchPanelShown ? next() : 0
    let trade = next()
    let cycle = cycleRowShown ? next() : 0
    return EuclideousAnswerTabLayout(followRowH: follow, rhythmRowH: rhythm, pitchRowH: pitch, pitchPanelH: panel, tradeRowH: trade, cycleRowH: cycle, gap: M.gap, fits: extra >= 0)
}

// MARK: - the status the UI polls (ENGINE → page, 30 Hz; display only)

/// One lane's running cycle, for the CYCLE row's phase bar and its spoken value. `running` is false until a cycle is latched (and always while the transport is stopped — the page draws the playhead at 0 then).
struct EuclideousAnswerLaneStatus: Equatable {
    var running = false
    var phaseB = false
    var unitInHalf = 0         // 0-based unit within the current half (0 ..< each)
    var each = euclideousAnswerCycleEachDefault
    var progress = 0.0         // 0…1 across A-then-B (`euclideousAnswerPhaseProgress`)
}
/// The pool one lane is choosing from right now (after CANON and FREEZE): up to 16 ascending MIDI notes and the true count.
struct EuclideousLanePoolStatus: Equatable {
    var count = 0
    var notes: [UInt8] = []
    /// POOL ferry: the pool's two highest notes (0 when it has fewer), so TOP 2 / TOP stay right for a pool of more than 16 notes.
    var top2: UInt8 = 0
    var top: UInt8 = 0
    /// The lane's EFFECTIVE sources (the sources panel's switches AND the lane's own), bit n = MIDI IN · CHORDS · PICK · KEY.
    var srcBits: UInt8 = euclideousPoolSrcAll
    var pedalDown = false
    /// SUSTAIN KEEP is holding this lane's pool right now.
    var keepHolding = false
    /// The ranks (bit r−1) the lane's last hit struck.
    var playedRanks: UInt8 = 0
}

/// The per-lane pool status the render thread writes and the UI's 30 Hz poll reads, as PLAIN FIXED MEMORY allocated once: no ARC, no copy-on-write, no bounds traps. A Swift array shared across two threads is not safe even for a display feed — a write
/// while the other thread holds the buffer copies it (an allocation on the render thread) and a racing read can trap on a stale count (the POOL ferry's monkey run crashed on exactly that, `Router.euclideousLanePoolStatus`). A torn read here is a stale
/// number, never a crash.
final class EuclideousLaneStatusStore {
    let notes = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)        // 4 lanes × 16 ascending notes
    let count = UnsafeMutablePointer<Int>.allocate(capacity: 4)           // each pool's true size (the notes beyond 16 are not copied)
    let top = UnsafeMutablePointer<UInt8>.allocate(capacity: 8)           // lane * 2: second-highest, highest
    let srcBits = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)       // the lane's effective sources (bit n = source n on)
    let keep = UnsafeMutablePointer<Bool>.allocate(capacity: 4)           // SUSTAIN KEEP is holding
    let played = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)        // the ranks (bit r−1) the lane's last hit struck
    var pedal = false
    // The ANSWER cycle status and the FREEZE status ride the same hand-off (they were arrays: the same race).
    let answer = UnsafeMutablePointer<EuclideousAnswerLaneStatus>.allocate(capacity: 4)
    let holdRunning = UnsafeMutablePointer<Bool>.allocate(capacity: 4)
    let holdLocked = UnsafeMutablePointer<Bool>.allocate(capacity: 4)
    let holdFraction = UnsafeMutablePointer<Double>.allocate(capacity: 4)
    init() {
        answer.initialize(repeating: EuclideousAnswerLaneStatus(), count: 4); holdRunning.initialize(repeating: false, count: 4); holdLocked.initialize(repeating: false, count: 4); holdFraction.initialize(repeating: 0, count: 4)
        notes.initialize(repeating: 0, count: 64); count.initialize(repeating: 0, count: 4); top.initialize(repeating: 0, count: 8)
        srcBits.initialize(repeating: euclideousPoolSrcAll, count: 4); keep.initialize(repeating: false, count: 4); played.initialize(repeating: 0, count: 4)
    }
    deinit { notes.deallocate(); count.deallocate(); top.deallocate(); srcBits.deallocate(); keep.deallocate(); played.deallocate(); answer.deallocate(); holdRunning.deallocate(); holdLocked.deallocate(); holdFraction.deallocate() }
    func answerSnapshot() -> [EuclideousAnswerLaneStatus] { (0..<4).map { answer[$0] } }
    func holdSnapshot() -> [EuclideousPoolHoldLaneStatus] { (0..<4).map { EuclideousPoolHoldLaneStatus(running: holdRunning[$0], locked: holdLocked[$0], fraction: holdFraction[$0]) } }
    /// The UI's read (main thread): everything clamped, so a torn read cannot index out of range.
    func snapshot() -> [EuclideousLanePoolStatus] {
        (0..<4).map { l in
            let c = max(0, count[l]), n = min(16, c)
            return EuclideousLanePoolStatus(count: c, notes: (0..<n).map { notes[l * 16 + $0] }, top2: top[l * 2], top: top[l * 2 + 1], srcBits: srcBits[l], pedalDown: pedal, keepHolding: keep[l], playedRanks: played[l])
        }
    }
}
/// The part of a lane's pool status the PAGE reads (the NOTES keys): the notes and the two highest — nothing that changes with every hit, so the page is not re-run at the hit rate.
struct EuclideousLanePoolNotes: Equatable {
    var count = 0
    var notes: [UInt8] = []
    var top2: UInt8 = 0
    var top: UInt8 = 0
    init() {}
    init(_ s: EuclideousLanePoolStatus) { count = s.count; notes = s.notes; top2 = s.top2; top = s.top }
}

// MARK: - 12: VoiceOver words (the page reads these and nothing else)

/// The three switchable rows.
enum EuclideousAnswerRow: Int, CaseIterable { case rhythm = 0, pitch = 1, trade = 2
    var name: String { switch self { case .rhythm: return "Rhythm"; case .pitch: return "Pitch"; case .trade: return "Trade" } }
}
/// 12.2 — a mode button: "Rhythm: copy, plays where lane 1 plays"; on a switched-off row ", off" is appended. `lane` is the 1-based lane the mode refers to (the source, or the WITH lane).
func euclideousAnswerModeSpoken(row: EuclideousAnswerRow, mode: String, lane: Int, rowOn: Bool) -> String {
    let what: String
    switch (row, mode.uppercased()) {
    case (.rhythm, "COPY"): what = "plays where lane \(lane) plays"
    case (.rhythm, "FILL"): what = "plays where lane \(lane) rests"
    case (.pitch, "SHADOW"): what = "plays the note lane \(lane) plays now"
    case (.pitch, "AVOID"): what = "mutes on the same hit as lane \(lane)"
    case (.trade, "SWAP"): what = "trades places with lane \(lane)"
    case (.trade, "BORROW"): what = "takes lane \(lane)'s setup"
    default: what = ""
    }
    return "\(row.name): \(mode.lowercased())\(what.isEmpty ? "" : ", \(what)")\(rowOn ? "" : ", off")"
}
/// 12.3 — the CYCLE toggle's name.
func euclideousAnswerCycleToggleLabel(row: EuclideousAnswerRow, lane: Int) -> String { "Cycle \(row.name.lowercased()), lane \(lane + 1)" }
/// 12.4 — WITH's value: "lane 3, swap" / "lane 2, borrow".
func euclideousAnswerWithSpoken(lane: Int, mode: EuclideousAnswerTradeMode) -> String { "lane \(lane + 1), \(mode == .swap ? "swap" : "borrow")" }
/// 12.5 — the phase bar's value: whose turn it is ("following lane 1", "own", "lane 2") and ", n of m" — the unit within the half (1-based) of EACH. Not running ⇒ "not running".
func euclideousAnswerPhaseSpoken(lane: Int, line: EuclidLine, status: EuclideousAnswerLaneStatus) -> String {
    guard status.running else { return "not running" }
    let colours = euclideousAnswerPhaseColours(lane: lane, line: line)
    let turn: String
    if status.phaseB { turn = colours.b == lane ? "own" : "lane \(colours.b + 1)" }
    else { turn = colours.a == lane ? "own" : "following lane \(colours.a + 1)" }
    return "\(turn), \(status.unitInHalf + 1) of \(max(1, status.each))"
}
/// Reduce Motion (4.2): the playhead moves once a beat, not per frame — progress quantised to 1/(2 × EACH × 4) of the cycle (four stops a unit; a unit is a bar, or a pass, a few beats).
func euclideousAnswerPlayheadQuantised(_ progress: Double, each: Int) -> Double {
    let steps = Double(2 * max(1, each) * 4)
    return min(1, (progress * steps).rounded(.down) / steps)
}

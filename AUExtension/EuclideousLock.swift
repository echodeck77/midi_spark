import Foundation
import CoreGraphics

// LANE LOCK ferry (2026-10-21): a padlock in the header opens lock mode. A locked lane can be edited; while its settings differ from the locked state it snaps back, exactly, on a quantised line of the
// page clock (a beat, or every 1 / 2 / 4 / 8 / 16 bars counted from the page's bar 1 = host beat 0 — the restart chains' own convention). Foundation-only, like EuclideousRandom.swift, so every decision here
// reaches the macOS test target and the Router / the page / the tests all call the SAME functions (the recurring bug class: one derivation, never two).

// MARK: - The grid

/// A lane's snap-back grid. The raw value is the number of bars between lines (0 = every beat).
enum EuclideousLockGrid: Int, Codable, CaseIterable, Equatable {
    case beat = 0, bar1 = 1, bars2 = 2, bars4 = 4, bars8 = 8, bars16 = 16
    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(Int.self)) ?? 1
        self = EuclideousLockGrid(rawValue: raw) ?? .bar1
    }
    /// The selector's segment label (4.6): BEAT · 1 BAR · 2 · 4 · 8 · 16.
    var segmentLabel: String { self == .beat ? "BEAT" : (self == .bar1 ? "1 BAR" : "\(rawValue)") }
    /// The selector's VoiceOver value (4.9).
    var accessibilityValue: String { self == .beat ? "every beat" : (self == .bar1 ? "every bar" : "every \(rawValue) bars") }
    /// The rule line (4.7).
    var ruleLine: String {
        switch self {
        case .beat: return "EDITS RETURN ON THE NEXT BEAT"
        case .bar1: return "EDITS RETURN ON THE NEXT BAR LINE"
        default: return "EDITS RETURN ON THE NEXT \(rawValue)-BAR LINE"
        }
    }
    /// The distance between two lines, in beats: a beat, or `bars` bars.
    func periodBeats(barBeats: Double) -> Double {
        let bb = barBeats > 0 ? barBeats : 4
        return self == .beat ? 1 : Double(rawValue) * bb
    }
}

/// 6.3 / 6.10 — THE next grid line, for everything on the main thread (the badge, the status line, the grid ticks, the tests): the beat of the first line at least `marginBeats` after `beat`. A line is a multiple of
/// the grid's period counted from beat 0 (= the line before 0-based bar `b` when `b % n == 0`), so it never depends on when an edit was made.
func euclideousLockNextLine(grid: EuclideousLockGrid, beat: Double, barBeats: Double, marginBeats: Double) -> Double {
    let p = grid.periodBeats(barBeats: barBeats)
    let k = ((beat + max(0, marginBeats)) / p - 1e-9).rounded(.up)
    return max(k, 0) * p
}

/// 6.8 — THE grid line the RENDER THREAD lands on: the first line in `(after, through]` (or `[after, through]` when `inclusiveStart`: the first window after a start / loop discontinuity), or nil. The window's end is
/// inclusive because the engine's tick scaffold also fires a tick that sits exactly on the window's end beat; each window pair is therefore a half-open partition and a line is decided exactly once.
func euclideousLockLineIn(grid: EuclideousLockGrid, barBeats: Double, after: Double, through: Double, inclusiveStart: Bool = false) -> Double? {
    let p = grid.periodBeats(barBeats: barBeats)
    guard p > 0, through >= after else { return nil }
    let k = (through / p + 1e-9).rounded(.down)
    let g = k * p
    if g > after + 1e-9 || (inclusiveStart && g > after - 1e-9) { return g }
    return nil
}

/// 6.4 — at a line: the lane snaps back when it is deviated, not held, and no edit to it is still on its way to the render thread. Otherwise the line passes and the next one decides again.
func euclideousLockSnapsAtLine(deviated: Bool, held: Bool, editInFlight: Bool) -> Bool { deviated && !held && !editInFlight }
/// 6.5 — the page not running: there are no lines to wait for, so a deviated, not-held lane snaps back at once.
func euclideousLockSnapsNow(deviated: Bool, held: Bool, running: Bool) -> Bool { !running && deviated && !held }

/// What the badge and the status line count (6.6): `held` (waiting for a lift, not a line), `beats(n)` (the BEAT grid, or the last bar of a longer one: n beats to go), or `bars(n)` (n bar lines up to and including
/// the next grid line; 1 means the line ends the current bar).
enum EuclideousLockCountdown: Equatable {
    case held
    case bars(Int)
    case beats(Int)
}
func euclideousLockCountdown(grid: EuclideousLockGrid, beat: Double, barBeats: Double, marginBeats: Double, held: Bool) -> EuclideousLockCountdown {
    if held { return .held }
    let line = euclideousLockNextLine(grid: grid, beat: beat, barBeats: barBeats, marginBeats: marginBeats)
    let beatsLeft = max(1, Int((line - beat - 1e-9).rounded(.up)))
    if grid == .beat { return .beats(beatsLeft) }
    let bb = barBeats > 0 ? barBeats : 4
    let barsLeft = max(1, Int((line / bb + 1e-9).rounded(.down)) - Int((beat / bb + 1e-9).rounded(.down)))
    return barsLeft <= 1 ? .beats(beatsLeft) : .bars(barsLeft)
}
/// 6.6 / 4.2 — the number the status line shows ("BACK IN n BARS"): bar lines from now up to and including the lane's next line; 1 when that line ends the current bar. Built from the same next-line function.
func euclideousLockBarsLeft(grid: EuclideousLockGrid, beat: Double, barBeats: Double, marginBeats: Double) -> Int {
    guard grid != .beat else { return 0 }
    let line = euclideousLockNextLine(grid: grid, beat: beat, barBeats: barBeats, marginBeats: marginBeats)
    let bb = barBeats > 0 ? barBeats : 4
    return max(1, Int((line / bb + 1e-9).rounded(.down)) - Int((beat / bb + 1e-9).rounded(.down)))
}

/// 4.2 — the card's status text.
func euclideousLockStatusText(locked: Bool, deviated: Bool, grid: EuclideousLockGrid, countdown: EuclideousLockCountdown?) -> String {
    guard locked else { return "UNLOCKED" }
    guard deviated, let c = countdown else { return "LOCKED" }
    switch c {
    case .held: return "LOCKED · BACK AFTER YOU LET GO"
    case .beats: return grid == .beat ? "LOCKED · BACK ON THE BEAT" : "LOCKED · BACK THIS BAR"
    case .bars(let n): return "LOCKED · BACK IN \(n) BARS"
    }
}

/// The main→render latency the count-down and the "edit just before a line" estimate use (the render thread itself needs no margin: it checks "an edit is on its way" exactly — see the Router). Seconds → beats.
enum EuclideousLockMargin {
    static let seconds = 0.06
    static func beats(tempo: Double) -> Double { tempo > 0 ? seconds * tempo / 60.0 : 0.1 }
}

// MARK: - The lock fields

/// THE list of what a lock holds (3.1) as one value: every stored `EuclidLine` field a control on the RHYTHM, RIFF or NOTES tab (or the card's comet-bar gestures) writes. Raw optionals, so `applied(to:)` restores a lane
/// EXACTLY (restart chains pinned or not, hitsRequested / offsetRequested / riffShiftRequested as stored); equality compares what the fields RESOLVE to, so an edit that is put back (HITS 3 → 7 → 3, which leaves
/// `hitsRequested` at 3 where it was nil) is not a deviation. Not lock fields: the play button, SOLO, LISTEN, outputs, MIX, LANES, FX, the riff grid, key and source.
struct LaneLockFields: Codable {
    // RHYTHM
    var steps: Int = 8, pulses: Int = 1, rotate: Int = 0
    var customHits: [Bool]? = nil
    var hitsRequested: Int? = nil, offsetRequested: Int? = nil
    var tilt: Double? = nil
    var rate: ArpRate? = nil
    var listenFollowMult: Int? = nil      // the FOLLOW multiplier chips sit on the RHYTHM tab, so they lock with it (a LISTEN field — listed per 3.1)
    var direction: EuclidDir? = nil
    var patternMiss: Bool? = nil
    var restartRhythmBars: [UInt8]? = nil, restartMelodyPasses: [UInt8]? = nil
    // RIFF
    var riffOn: Bool? = nil
    var riffDir: RiffDir? = nil, riffInvert: Bool? = nil
    var riffAdvanceEvery: Int? = nil, riffAdvanceStep: Bool? = nil
    var riffOnRest: EuclidRiffOnRest? = nil
    var riffLength: Int? = nil, riffRotate: Int? = nil, riffShiftRequested: Int? = nil
    var riffStride: Int? = nil, melodyTranspose: Int? = nil
    // NOTES
    var notesLitOrder: [UInt8]? = nil
    var litNotes: UInt8? = nil, topLit: Bool? = nil, top2Lit: Bool? = nil
    var notesOn: Bool? = nil
    var notesWhen: UInt8? = nil, notesChance: Int? = nil
    var notesPlayAs: EuclidNotesPlayAs? = nil
    var notesReceivedOnly: Bool? = nil

    init() {}
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        steps = ((try? c.decodeIfPresent(Int.self, forKey: .steps)) ?? nil) ?? 8
        pulses = ((try? c.decodeIfPresent(Int.self, forKey: .pulses)) ?? nil) ?? 1
        rotate = ((try? c.decodeIfPresent(Int.self, forKey: .rotate)) ?? nil) ?? 0
        customHits = (try? c.decodeIfPresent([Bool].self, forKey: .customHits)) ?? nil
        hitsRequested = (try? c.decodeIfPresent(Int.self, forKey: .hitsRequested)) ?? nil
        offsetRequested = (try? c.decodeIfPresent(Int.self, forKey: .offsetRequested)) ?? nil
        tilt = (try? c.decodeIfPresent(Double.self, forKey: .tilt)) ?? nil
        rate = (try? c.decodeIfPresent(ArpRate.self, forKey: .rate)) ?? nil
        listenFollowMult = (try? c.decodeIfPresent(Int.self, forKey: .listenFollowMult)) ?? nil
        direction = (try? c.decodeIfPresent(EuclidDir.self, forKey: .direction)) ?? nil
        patternMiss = (try? c.decodeIfPresent(Bool.self, forKey: .patternMiss)) ?? nil
        restartRhythmBars = (try? c.decodeIfPresent([UInt8].self, forKey: .restartRhythmBars)) ?? nil
        restartMelodyPasses = (try? c.decodeIfPresent([UInt8].self, forKey: .restartMelodyPasses)) ?? nil
        riffOn = (try? c.decodeIfPresent(Bool.self, forKey: .riffOn)) ?? nil
        riffDir = (try? c.decodeIfPresent(RiffDir.self, forKey: .riffDir)) ?? nil
        riffInvert = (try? c.decodeIfPresent(Bool.self, forKey: .riffInvert)) ?? nil
        riffAdvanceEvery = (try? c.decodeIfPresent(Int.self, forKey: .riffAdvanceEvery)) ?? nil
        riffAdvanceStep = (try? c.decodeIfPresent(Bool.self, forKey: .riffAdvanceStep)) ?? nil
        riffOnRest = (try? c.decodeIfPresent(EuclidRiffOnRest.self, forKey: .riffOnRest)) ?? nil
        riffLength = (try? c.decodeIfPresent(Int.self, forKey: .riffLength)) ?? nil
        riffRotate = (try? c.decodeIfPresent(Int.self, forKey: .riffRotate)) ?? nil
        riffShiftRequested = (try? c.decodeIfPresent(Int.self, forKey: .riffShiftRequested)) ?? nil
        riffStride = (try? c.decodeIfPresent(Int.self, forKey: .riffStride)) ?? nil
        melodyTranspose = (try? c.decodeIfPresent(Int.self, forKey: .melodyTranspose)) ?? nil
        notesLitOrder = (try? c.decodeIfPresent([UInt8].self, forKey: .notesLitOrder)) ?? nil
        litNotes = (try? c.decodeIfPresent(UInt8.self, forKey: .litNotes)) ?? nil
        topLit = (try? c.decodeIfPresent(Bool.self, forKey: .topLit)) ?? nil
        top2Lit = (try? c.decodeIfPresent(Bool.self, forKey: .top2Lit)) ?? nil
        notesOn = (try? c.decodeIfPresent(Bool.self, forKey: .notesOn)) ?? nil
        notesWhen = (try? c.decodeIfPresent(UInt8.self, forKey: .notesWhen)) ?? nil
        notesChance = (try? c.decodeIfPresent(Int.self, forKey: .notesChance)) ?? nil
        notesPlayAs = (try? c.decodeIfPresent(EuclidNotesPlayAs.self, forKey: .notesPlayAs)) ?? nil
        notesReceivedOnly = (try? c.decodeIfPresent(Bool.self, forKey: .notesReceivedOnly)) ?? nil
    }

    /// 3.3 — the ONE read: a lane's lock fields as a value.
    init(line l: EuclidLine) {
        steps = l.steps; pulses = l.pulses; rotate = l.rotate
        customHits = l.customHits; hitsRequested = l.hitsRequested; offsetRequested = l.offsetRequested
        tilt = l.tilt; rate = l.rate; listenFollowMult = l.listenFollowMult; direction = l.direction; patternMiss = l.patternMiss
        restartRhythmBars = l.restartRhythmBars; restartMelodyPasses = l.restartMelodyPasses
        riffOn = l.riffOn; riffDir = l.riffDir; riffInvert = l.riffInvert
        riffAdvanceEvery = l.riffAdvanceEvery; riffAdvanceStep = l.riffAdvanceStep; riffOnRest = l.riffOnRest
        riffLength = l.riffLength; riffRotate = l.riffRotate; riffShiftRequested = l.riffShiftRequested
        riffStride = l.riffStride; melodyTranspose = l.melodyTranspose
        notesLitOrder = l.notesLitOrder; litNotes = l.litNotes; topLit = l.topLit; top2Lit = l.top2Lit
        notesOn = l.notesOn; notesWhen = l.notesWhen; notesChance = l.notesChance
        notesPlayAs = l.notesPlayAs; notesReceivedOnly = l.notesReceivedOnly
    }

    /// 3.3 — the ONE write: every lock field onto `line` as a single change. Direct field writes — no setter's side effects (no `hitsRequested` nil-ing, no chain pinning, no STEPS memory), so restart chains, hitsRequested,
    /// offsetRequested and riffShiftRequested come back exactly as stored. `notesLitOrder`'s observer projects the three legacy fields, then they are written raw so a legacy-only lane round-trips too.
    func applied(to l: inout EuclidLine) {
        l.steps = steps; l.pulses = pulses; l.rotate = rotate
        l.customHits = customHits; l.hitsRequested = hitsRequested; l.offsetRequested = offsetRequested
        l.tilt = tilt; l.rate = rate; l.listenFollowMult = listenFollowMult; l.direction = direction; l.patternMiss = patternMiss
        l.restartRhythmBars = restartRhythmBars; l.restartMelodyPasses = restartMelodyPasses
        l.riffOn = riffOn; l.riffDir = riffDir; l.riffInvert = riffInvert
        l.riffAdvanceEvery = riffAdvanceEvery; l.riffAdvanceStep = riffAdvanceStep; l.riffOnRest = riffOnRest
        l.riffLength = riffLength; l.riffRotate = riffRotate; l.riffShiftRequested = riffShiftRequested
        l.riffStride = riffStride; l.melodyTranspose = melodyTranspose
        l.notesLitOrder = notesLitOrder
        l.litNotes = litNotes; l.topLit = topLit; l.top2Lit = top2Lit
        l.notesOn = notesOn; l.notesWhen = notesWhen; l.notesChance = notesChance
        l.notesPlayAs = notesPlayAs; l.notesReceivedOnly = notesReceivedOnly
    }
}

/// What a set of lock fields RESOLVES to, read through the lane's own resolved accessors (`base` supplies the legacy fields a few of them migrate from) — the thing equality and the control-change list compare.
struct LaneLockKey: Equatable {
    var steps: Int, pulses: Int, rotate: Int
    var customHits: [Bool]?
    var hitsRequested: Int, offsetRequested: Int
    var tilt: Double, rate: ArpRate?, followMult: Int, direction: EuclidDir, patternMiss: Bool
    var chainRhythm: [UInt8]?, chainMelody: [UInt8]?
    var riffOn: Bool, riffDir: RiffDir, riffInvert: Bool
    var advanceEvery: Int, advanceStep: Bool, onRest: EuclidRiffOnRest
    var length: Int, shift: Int, shiftRequested: Int, stride: Int, transpose: Int
    var litOrder: EuclideousLitOrder
    var notesOn: Bool, notesWhen: UInt8, notesChance: Int, notesPlayAs: EuclidNotesPlayAs, notesReceived: Bool
}
extension LaneLockFields {
    func key(base: EuclidLine = EuclidLine()) -> LaneLockKey {
        var l = base
        applied(to: &l)
        return LaneLockKey(steps: l.steps, pulses: l.pulses, rotate: l.rotate, customHits: l.customHits,
                           hitsRequested: l.hitsRequestedResolved, offsetRequested: l.offsetRequestedResolved,
                           tilt: l.tiltResolved, rate: l.rate, followMult: l.listenFollowMultResolved, direction: l.directionResolved, patternMiss: l.patternMissResolved,
                           chainRhythm: l.restartRhythmBars, chainMelody: l.restartMelodyPasses,
                           riffOn: l.riffOnResolved, riffDir: l.riffDirResolved, riffInvert: l.riffInvertResolved,
                           advanceEvery: l.riffAdvanceEveryResolved, advanceStep: l.riffAdvanceStepResolved, onRest: l.riffOnRestResolved,
                           length: l.riffLengthResolved, shift: l.riffRotateResolved, shiftRequested: l.riffShiftRequestedResolved, stride: l.riffStrideResolved, transpose: l.melodyTransposeResolved,
                           litOrder: l.litOrderResolved,
                           notesOn: l.notesOnResolved, notesWhen: l.notesWhenResolved, notesChance: l.notesChanceResolved, notesPlayAs: l.notesPlayAsResolved, notesReceived: l.notesReceivedOnlyResolved)
    }
}
extension LaneLockFields: Equatable {
    static func == (a: LaneLockFields, b: LaneLockFields) -> Bool { a.key() == b.key() }
}

/// 6.1 / 3.3 — a lane is DEVIATED when its lock fields differ from L. The one definition: the Router (at a line), the badge, the status line, the outlines and the stopped-page rule all call it.
func euclideousLockDeviated(line: EuclidLine, from locked: LaneLockFields) -> Bool {
    LaneLockFields(line: line).key(base: line) != locked.key(base: line)
}

// MARK: - The document type

/// One lane's lock, as saved (3.2): `on` (nil ⇒ off), `grid` (nil ⇒ 1 BAR; kept while the lane is unlocked so relocking reuses it) and `state`, the locked state L — present only while on. Tolerant decode: anything
/// malformed reads as "unlocked", never as a failed document.
struct EuclideousLaneLock: Codable, Equatable {
    var on: Bool? = nil
    var grid: EuclideousLockGrid? = nil
    var state: LaneLockFields? = nil
    init() {}
    init(on: Bool?, grid: EuclideousLockGrid?, state: LaneLockFields?) { self.on = on; self.grid = grid; self.state = state }
    private enum CodingKeys: String, CodingKey { case on, grid, state }
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        on = (try? c.decodeIfPresent(Bool.self, forKey: .on)) ?? nil
        grid = (try? c.decodeIfPresent(EuclideousLockGrid.self, forKey: .grid)) ?? nil
        state = (try? c.decodeIfPresent(LaneLockFields.self, forKey: .state)) ?? nil
    }
    /// Locked = switched on AND a locked state to hold (a lock with no L holds nothing).
    var isLocked: Bool { (on ?? false) && state != nil }
    var gridResolved: EuclideousLockGrid { grid ?? .bar1 }
    /// Tapped on: L = what the lane is now.
    static func locking(_ line: EuclidLine, grid: EuclideousLockGrid) -> EuclideousLaneLock {
        EuclideousLaneLock(on: true, grid: grid, state: LaneLockFields(line: line))
    }
}
extension PluginState {
    var euclideousLocksResolved: [EuclideousLaneLock] {
        var a = euclideousLocks ?? []
        if a.count > 4 { a = Array(a.prefix(4)) }
        while a.count < 4 { a.append(EuclideousLaneLock()) }
        return a
    }
    /// 3.5 — a session always opens at its locked states: a locked lane whose saved fields differ from L is set to L before it plays. Called beside `migrateLegacyRoutingIfNeeded()` on every load path.
    mutating func normalizeLocksAtLoad() {
        let locks = euclideousLocksResolved
        guard locks.contains(where: { $0.isLocked }) else { return }
        var lines = euclideousLinesResolved
        var changed = false
        for i in 0..<4 where locks[i].isLocked {
            let before = lines[i]
            locks[i].state?.applied(to: &lines[i])
            if lines[i] != before { changed = true }
        }
        if changed { euclideousLines = lines }
    }
}

/// The render-time view of one lane's lock (SnapParams carries four).
struct EuclideousLockSnap: Equatable {
    var on = false
    var grid: EuclideousLockGrid = .bar1
    var state: LaneLockFields? = nil
}

// MARK: - The live words (the render thread's fast channel, the `euclideousSoloLive` hand-off)

/// Layout of the 64-bit word the main thread stores for the render thread: bit 63 = "the page has spoken", bits 0–3 = the lanes a finger is on (HELD, 6.2), bits 8–39 = four revision bytes (byte i = lane i). The
/// snapshot carries the revisions it was built from, so `live ≠ snapshot` for a lane means an edit to it is still on its way (6.4).
enum EuclideousLockLive {
    static let spoken: UInt64 = 1 << 63
    static func word(held: UInt8, revs: UInt32) -> UInt64 { spoken | UInt64(held & 0x0F) | (UInt64(revs) << 8) }
    static func heldMask(_ w: UInt64) -> UInt8 { UInt8(w & 0x0F) }
    static func revs(_ w: UInt64) -> UInt32 { UInt32((w >> 8) & 0xFFFF_FFFF) }
    static func hasSpoken(_ w: UInt64) -> Bool { w & spoken != 0 }
    static func rev(_ packed: UInt32, lane: Int) -> UInt8 { UInt8((packed >> UInt32(8 * lane)) & 0xFF) }
    static func bumped(_ packed: UInt32, lane: Int) -> UInt32 {
        let sh = UInt32(8 * lane)
        let nv = (packed >> sh) &+ 1
        return (packed & ~(0xFF << sh)) | ((nv & 0xFF) << sh)
    }
}

// MARK: - The control-change list (5.4) and the tags

enum EuclideousLockTab: Int, Equatable { case rhythm = 0, riff = 1, notes = 2 }
/// Every control on the three tabs whose value can differ from L, plus the comet strip. Note keys are `noteKey(position)`: 0–7 = ranks 1–8, 8 = TOP 2, 9 = TOP.
enum EuclideousLockControl: Hashable {
    case hits, steps, offset, tilt, rate, followMult, direction, inv, rhythmRestart, melodyRestart
    case riffOn, riffDirection, riffInvert, advanceEvery, advanceMode, onRest, length, shift, stride, transpose
    case noteKey(Int), notesStrip, notesWhen, notesChance, notesPlayAs, notesReceived
    case cometStrip
    var tab: EuclideousLockTab? {
        switch self {
        case .hits, .steps, .offset, .tilt, .rate, .followMult, .direction, .inv, .rhythmRestart, .melodyRestart: return .rhythm
        case .riffOn, .riffDirection, .riffInvert, .advanceEvery, .advanceMode, .onRest, .length, .shift, .stride, .transpose: return .riff
        case .noteKey, .notesStrip, .notesWhen, .notesChance, .notesPlayAs, .notesReceived: return .notes
        case .cometStrip: return nil
        }
    }
}
/// 5.4 — "random mode 7.3's control-change list, called with L and the current state". Random mode shipped no such list (its §7.3 return highlight is a ring and a tag), so this is the one: each control on a tab whose
/// resolved value differs from L; the comet strip is listed whenever anything it draws differs (every lock field but nothing else feeds it).
func euclideousLockChangedControls(from locked: LaneLockFields, to line: EuclidLine) -> Set<EuclideousLockControl> {
    let a = locked.key(base: line), b = LaneLockFields(line: line).key(base: line)
    guard a != b else { return [] }
    var s = Set<EuclideousLockControl>()
    if a.pulses != b.pulses || a.customHits != b.customHits { s.insert(.hits) }
    if a.steps != b.steps { s.insert(.steps) }
    if a.rotate != b.rotate { s.insert(.offset) }
    if a.tilt != b.tilt { s.insert(.tilt) }
    if a.rate != b.rate { s.insert(.rate) }
    if a.followMult != b.followMult { s.insert(.followMult) }
    if a.direction != b.direction { s.insert(.direction) }
    if a.patternMiss != b.patternMiss { s.insert(.inv) }
    if a.chainRhythm != b.chainRhythm { s.insert(.rhythmRestart) }
    if a.chainMelody != b.chainMelody { s.insert(.melodyRestart) }
    if a.riffOn != b.riffOn { s.insert(.riffOn) }
    if a.riffDir != b.riffDir { s.insert(.riffDirection) }
    if a.riffInvert != b.riffInvert { s.insert(.riffInvert) }
    if a.advanceEvery != b.advanceEvery { s.insert(.advanceEvery) }
    if a.advanceStep != b.advanceStep { s.insert(.advanceMode) }
    if a.onRest != b.onRest { s.insert(.onRest) }
    if a.length != b.length { s.insert(.length) }
    if a.shift != b.shift { s.insert(.shift) }
    if a.stride != b.stride { s.insert(.stride) }
    if a.transpose != b.transpose { s.insert(.transpose) }
    if a.litOrder != b.litOrder {
        for p in 0..<10 where a.litOrder.contains(p) != b.litOrder.contains(p) { s.insert(.noteKey(p)) }
        if a.litOrder.array != b.litOrder.array && !s.contains(where: { if case .noteKey = $0 { return true }; return false }) {
            for p in 0..<10 where a.litOrder.index(of: p) != b.litOrder.index(of: p) { s.insert(.noteKey(p)) }
        }
    }
    if a.notesOn != b.notesOn { s.insert(.notesStrip) }
    if a.notesWhen != b.notesWhen { s.insert(.notesWhen) }
    if a.notesChance != b.notesChance { s.insert(.notesChance) }
    if a.notesPlayAs != b.notesPlayAs { s.insert(.notesPlayAs) }
    if a.notesReceived != b.notesReceived { s.insert(.notesReceived) }
    s.insert(.cometStrip)
    return s
}
/// The tabs that carry a dot (5.4, random mode 3.2's dot) because a control on them differs.
func euclideousLockChangedTabs(_ controls: Set<EuclideousLockControl>) -> Set<EuclideousLockTab> {
    Set(controls.compactMap { $0.tab })
}

/// 4.4 — the three summary rows, built from the tag pieces random mode already uses (no second formatting). `autoRate` is what a lane with no rate of its own reads (the nearest rate to the page's step).
func euclideousLockRhythmTag(_ f: LaneLockFields, autoRate: ArpRate) -> String {
    let n = max(2, min(16, f.steps))
    let r = ((f.rotate % n) + n) % n
    let offset = (n - r) % n
    var s = "\(f.pulses) OF \(n)"
    if offset > 0 { s += " · OFFSET \(offset)" }
    s += " · " + (f.rate ?? autoRate).rawValue
    return s
}
func euclideousLockRiffTag(_ f: LaneLockFields, base: EuclidLine = EuclidLine()) -> String {
    let k = f.key(base: base)
    guard k.riffOn else { return "RIFF OFF" }
    return euclideousRandomRiffTag(dir: k.riffDir == .drunk || k.riffDir == .random ? .forward : k.riffDir, invert: k.riffInvert, advanceStep: k.advanceStep, every: k.advanceEvery, stride: k.stride)
}
func euclideousLockNotesTag(_ f: LaneLockFields, base: EuclidLine = EuclidLine()) -> String {
    let k = f.key(base: base)
    guard k.notesOn else { return "NOTES OFF" }
    guard k.litOrder.count > 0 else { return "NO NOTES LIT" }
    return euclideousRandomNotesTag(playAs: k.notesPlayAs, count: k.litOrder.count, when: k.notesWhen, chance: k.notesChance)
}
/// 4.9 — the summary as one spoken sentence: "Locked rhythm 3 of 16, offset 4; riff pendulum by step every 2; notes roll, 3 notes, on rests" (or "Lane n would lock …" while unlocked).
func euclideousLockSummaryAccessibility(lane: Int, locked: Bool, fields f: LaneLockFields, base: EuclidLine = EuclidLine()) -> String {
    let k = f.key(base: base)
    let n = max(2, min(16, f.steps))
    let off = ((n - ((f.rotate % n) + n) % n) % n)
    var s = locked ? "Locked" : "Lane \(lane + 1) would lock"
    s += " rhythm \(f.pulses) of \(n)" + (off > 0 ? ", offset \(off)" : "")
    if k.riffOn {
        let dirWord: String
        switch k.riffDir { case .forward: dirWord = "forward"; case .reverse: dirWord = "reverse"; case .pendulum: dirWord = "pendulum"; case .pingpong: dirWord = "ping pong"; case .random, .drunk: dirWord = "forward" }
        s += "; riff \(dirWord) by \(k.advanceStep ? "step" : "hit")" + (k.advanceEvery > 1 ? " every \(k.advanceEvery)" : "")
    } else { s += "; riff off" }
    if k.notesOn && k.litOrder.count > 0 {
        let when = k.notesWhen == 0b01 ? "on notes" : (k.notesWhen == 0b10 ? "on rests" : "on both")
        s += "; notes \(k.notesPlayAs.rawValue.lowercased()), \(k.litOrder.count) note\(k.litOrder.count == 1 ? "" : "s"), \(when)"
    } else { s += "; notes off" }
    return s
}

// MARK: - Layout (4.1–4.8, 5.1)

/// The lock card's frames, from the card's top-left (4.1–4.8). Coordinates are for the 380.67 × 319 reference; other sizes follow the content width (x) and keep the y positions from the top (the hint from the bottom).
struct EuclideousLockCardLayout: Equatable {
    var size: CGSize
    /// Floor (4.8): a card under 250 tall or 300 wide is built at the formula's values and reported.
    var belowFloor: Bool { size.height < 250 || size.width < 300 }
    static let inset: CGFloat = 10
    var contentWidth: CGFloat { size.width - 2 * Self.inset }
    var numberCircle: CGRect { CGRect(x: 10, y: 14, width: 24, height: 24) }
    var titleOrigin: CGPoint { CGPoint(x: 42, y: 14) }
    var titleRow: CGRect { CGRect(x: 42, y: 10, width: 64, height: 32) }
    var statusRow: CGRect { CGRect(x: 110, y: 10, width: max(0, size.width - 120), height: 32) }
    var padlock: CGRect { CGRect(x: 10, y: 52, width: 88, height: 88) }
    var summary: CGRect { CGRect(x: 106, y: 52, width: max(0, size.width - 116), height: 88) }
    static let labelColumnW: CGFloat = 64
    func summaryRow(_ i: Int) -> CGRect { CGRect(x: 106, y: 52 + CGFloat(i) * 31, width: max(0, size.width - 116), height: 26) }
    func summaryLabel(_ i: Int) -> CGRect { CGRect(x: 106, y: 52 + CGFloat(i) * 31, width: Self.labelColumnW, height: 26) }
    func summaryValue(_ i: Int) -> CGRect { CGRect(x: 106 + Self.labelColumnW, y: 52 + CGFloat(i) * 31, width: max(0, size.width - 116 - Self.labelColumnW), height: 26) }
    var snapBackLabel: CGRect { CGRect(x: 10, y: 150, width: contentWidth, height: 12) }
    var gridRow: CGRect { CGRect(x: 10, y: 166, width: contentWidth, height: 44) }
    var selector: CGRect { CGRect(x: 10, y: 172, width: contentWidth, height: 32) }
    var segmentWidth: CGFloat { (contentWidth - 8) / 6 }
    func segment(_ i: Int) -> CGRect { CGRect(x: 14 + CGFloat(i) * segmentWidth, y: 176, width: segmentWidth, height: 24) }
    func segmentTouch(_ i: Int) -> CGRect { CGRect(x: 14 + CGFloat(i) * segmentWidth, y: 166, width: segmentWidth, height: 44) }
    var ruleLine: CGRect { CGRect(x: 10, y: 222, width: contentWidth, height: 14) }
    var gridTicks: CGRect { CGRect(x: 10, y: 240, width: contentWidth, height: 12) }
    var hint: CGRect { CGRect(x: 10, y: size.height - 24, width: contentWidth, height: 14) }
    /// Every frame, for the "nothing crosses the card's edge" test.
    var allFrames: [CGRect] {
        var r: [CGRect] = [numberCircle, titleRow, statusRow, padlock, summary, snapBackLabel, gridRow, selector, ruleLine, gridTicks, hint]
        for i in 0..<3 { r.append(summaryRow(i)) }
        for i in 0..<6 { r.append(segment(i)); r.append(segmentTouch(i)) }
        return r
    }
}
func euclideousLockCardLayout(size: CGSize) -> EuclideousLockCardLayout { EuclideousLockCardLayout(size: size) }

/// 5.1 — the badge on a locked lane's tab row: 34 × 34 at the row's trailing end (card x width − 44 … width − 10, y 54 … 88: it rises 6 into the gap above the 28-tall tab row), a 44-tall touch target centred on it.
enum EuclideousLockBadge {
    static let size: CGFloat = 34, gapToTabs: CGFloat = 4
    static func frame(cardWidth: CGFloat) -> CGRect { CGRect(x: cardWidth - 44, y: 54, width: size, height: size) }
    static func touchFrame(cardWidth: CGFloat) -> CGRect { CGRect(x: cardWidth - 44, y: 54 + size / 2 - 22, width: size, height: 44) }
    /// The tabs share what is left by their existing rule (equal width, spacing 4): with the badge, 34 + 4 less.
    static func tabWidth(innerWidth: CGFloat, tabCount: Int = 4, spacing: CGFloat = 4, withBadge: Bool) -> CGFloat {
        let n = CGFloat(tabCount)
        let taken = withBadge ? size + spacing : 0
        return (innerWidth - taken - spacing * (n - 1)) / n
    }
}

// MARK: - Undo (9.2) — edits to a locked lane record no step; restoring a step never moves a locked lane

/// True when a change from `old` to `new` touches anything OTHER than the lock fields of a locked lane. A change that is only lock fields of locked lanes records no undo step (including one that records at touch-down).
func euclideousLockEditIsUndoable(old: [EuclidLine], new: [EuclidLine], locked: [Bool]) -> Bool {
    guard old.count == new.count else { return true }
    for i in old.indices where old[i] != new[i] {
        guard i < locked.count, locked[i] else { return true }
        var n = new[i]
        LaneLockFields(line: old[i]).applied(to: &n)
        if n != old[i] { return true }
    }
    return false
}
/// Restoring an undo / redo step: everything changes as today except a locked lane's lock fields, which stay as they are now.
func euclideousLockMergeForUndo(restored: [EuclidLine], current: [EuclidLine], locked: [Bool]) -> [EuclidLine] {
    var out = restored
    for i in out.indices where i < current.count && i < locked.count && locked[i] {
        LaneLockFields(line: current[i]).applied(to: &out[i])
    }
    return out
}

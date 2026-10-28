//  Snapshot.swift
//  MidiSpark — the snapshot bridge (spec v2.8 §7).
//
//  The render thread NEVER reads the document. It reads a SnapshotBox: flat, fixed-size,
//  immutable after construction, published by atomic pointer swap. The UI thread builds
//  boxes (SnapshotBuilder) and publishes them (SnapshotStore.publish, MAIN THREAD ONLY).
//  Reads on the render thread are lock-free and allocation-free (acquire = one atomic load).

import Foundation
// Foundation-only on purpose: the effective-parameter functions below (§3.2 morph interpolation +
// quantization) are pure and unit-tested off-device. SnapshotStore — the one piece needing
// swift-atomics — lives in SnapshotStore.swift so this file can join the test target.

// MARK: - Fixed geometry

enum Snap {
    // FERRY ROW UNIFICATION (Paul 2026-09-27): rows = ferries × rowsPerFerry. Every one of the 8 play ferries — the
    // one currently open on the bench or playing quietly in the background, no distinction — owns a FIXED, DEDICATED
    // block of `rowsPerFerry` engine rows (`ferryRowBase(t)..<ferryRowBase(t)+rowsPerFerry`), always live. This
    // replaces the old model (rows 0–7 shared by whichever ferry was on the bench + a dead pre-ferry "PIECE"
    // arrangement grid, rows 8–15 one mono row per background ferry via `playLayerRowBase`, now gone) — see
    // Docs status log "FERRY ROW UNIFICATION" and the plan it landed from. Cell index stays `col * Snap.rows + row`.
    // §E 16-STEP FLIP (Paul 2026-09-02): `cols` is the DEFAULT/uniform BAR width (8 — one bar = 8 steps; the whole cycle
    // math + uniform fast path key on it, so it STAYS 8 and the default part is byte-identical). `maxCols` is the
    // ALLOCATION ceiling — the widest a part's loop can be (16). Cell storage + column loops + per-row loop-length CLAMPS
    // use maxCols; a part whose rowLength > cols is non-uniform → the proven multi-clock per-row path plays its 16 columns.
    static let cols = 8, machines = 16, maxCols = 16
    static let ferries = 8, rowsPerFerry = 4
    // EUCLIDEOUS (Paul 2026-10-05): ONE further reserved row, past the last ferry's own block — the standalone
    // 4-lane instrument page's one EuclidMachine cell lives here, PINNED (its rowLane set to a single-column lap
    // mask), always live, independent of which ferry is open on the BUILD-page bench. Deliberately NOT reused
    // from the existing "chain audition" squat-in-whichever-ferry-row-is-empty mechanism — that's singular,
    // fragile, and coupled to unrelated BUILD-page bench state, the wrong foundation for "a reliable, always-on
    // instrument." The render engine itself is confirmed ferry-agnostic (every `for r in 0..<Snap.rows` loop in
    // Router.swift/Kernel.swift/SnapshotBuilder.swift treats every row identically; ferry/row-block semantics
    // live entirely in BUILD-page authoring code, which derives a row range FROM a ferry index via
    // `ferryRowBase(t)`, never a ferry index FROM a row via reverse division) — so one extra non-ferry row is
    // safe to add without touching render-path logic at all.
    static let euclideousRow = ferries * rowsPerFerry   // = 32, the first index beyond the last ferry's own block
    static let rows = ferries * rowsPerFerry + 1   // 33 = 32 ferry rows + Euclideous's own reserved row
    static var cells: Int { maxCols * rows }   // the per-cell array/feed size (index = col*rows + row, col 0…15)
    // delta §9 item 11: a source filter ≥17 matches no held note (NotePool.matches never sees chan ≥16),
    // so it is the render-free way to express a MUTED receiver — its subscribers read an empty pool.
    static let mutedSourceFilter: UInt8 = 17
    // §E 16-step: pad a per-COLUMN array up to maxCols (an old 8-col save decodes short) so 16-wide indexing is safe.
    static func padCols<T>(_ a: [T], _ fill: T) -> [T] { a.count >= maxCols ? a : a + Array(repeating: fill, count: maxCols - a.count) }
    // Ladders shared by builder and kernel. Order MUST match the enums' allCases (§8: stable).
    static let stepRateBeats: [Double] = StepRate.allCases.map(\.beats)
}

// MARK: - Flat cell (one per grid position; machineIndex < 0 = empty)

struct SnapCell {
    var machineIndex: Int16 = -1   // CR-13a: Int16 (was Int8) — with the 16-machine cap gone, a document machine index can exceed 127; Int8(index) trapped at ≥128
    var alt = false
    var bypassed = false
    var passthrough = false     // NO-MACHINE chain (Paul 2026-08-23): a LIVE WIRE — its input passes straight through in
                                // realtime via the bypass monitor (reconcileBypass), NOT the grid's step clock; skipped in emitColumnHolds.
    var muted = false
    var dormant = false        // LADDER: a non-active rung while LADDER mode is on — silent (skipped at the emit
                               // guards, like `muted`) but present/visible; resolved in the builder so the render
                               // thread stays LADDER-unaware. Default false → identical to pre-LADDER behaviour.
    var busMask: UInt8 = 0     // the cell's exits (non-zero ⇒ it emits); a Euclideous lane's real port is chosen per note (`FourfoldPorts`)
    var runStartColumn: Int8 = -1   // LEGATO precompute (§7 v2.4) — UI-thread work, render just reads
    // v3.0 graph routing (delta §1, precomputed here so render never scans):
    var resolvedParent: Int8 = -1   // referenced row IF occupied & ≠ self, else −1 (= MIDI IN)
    var inputChannel: UInt8 = 0     // delta §7: source filter, 0 = OMNI, 1–16 channel, ≥17 = match-nothing
                                    // (a muted receiver; Snap.mutedSourceFilter). Resolved from the cell's
                                    // receiver at build time — MIDI-IN cells only; render just reads it.
    var inputChanMask: UInt16 = 0xFFFF   // MULTI-CHANNEL (Paul 2026-08-21): the cell's channel bitmask (bit c = channel c+1); 0xFFFF = OMNI. The render filters on THIS; `inputChannel` above stays for metering/compat.
    var resolvedReceiver: Int8 = -1 // delta §9 item 11: the receiver a MIDI-IN cell reads (0–3), else −1
    var inputCableMask: UInt8 = 0b1111  // §item 11 INPUT CABLES: the receiver's cable bitmask (ANY = all); render just reads it
    var chordSplit = ChordSplit()   // §cell-edit D: which held source notes this cell takes (ALL default); render reads via srcCount/srcAscending(for:)
    var velFloor: UInt8 = 1         // §cell-edit D VELOCITY WINDOW: admit source notes with velocity in [floor, ceil]
    var velCeil: UInt8 = 127        // (1…127 default = admit all); applied in srcCount/srcAscending(for:) before the split
    var inputRangeLo: UInt8 = 0     // RANGE (§2): the receiver's note WINDOW — admit source notes with note ∈ [lo, hi]
    var inputRangeHi: UInt8 = 127   // (0…127 default = admit all); applied in srcCount/srcAscending(for:) with the vel window
    var chopMain: UInt8 = 0xFF       // §cell-edit F: per-slice → the cell's own emitters (bit i = slice i)
    var chopAlt: UInt8 = 0           // §cell-edit F: per-slice → ALSO the shared ALT destination
    var chopMute: UInt8 = 0          // §cell-edit F: per-slice → silenced (overrides)
    var chopAltMask: UInt8 = 0       // §cell-edit F: the shared ALT destination as a bus bitmask
    var chopActive = false           // fast-path: any slice deviates from all-MAIN
    // CELL MACHINE (feat/EditPageSpike): the resolved processor CHAIN — one SnapParams per slot, head first,
    // resolved from the cell's `processors` (or a 1-slot head from the Machine's A face when the cell has none).
    // `slotBypass[k]` = slot k's true-bypass. (Morph removed — SnapMachine carries only the single A face.) The
    // head-only stage-1 reads `proc` (== procs[0]) and `bypassed` (== slotBypass[0]); stage-2 runs the whole
    // chain in series (Router pipeline) with only the TAIL emitting.
    var procs: [SnapParams] = [SnapParams()]
    var slotBypass: [Bool] = [false]
    var proc: SnapParams { procs.first ?? SnapParams() }   // the head treatment (stage-1 read path)
}

// MARK: - Resolved per-state params (the single resolved param bag — the A/B morph layer was removed; paramsB/typeB are decode-only legacy)

// MARK: - HOCKET (ferry 2026-10-27) — the rules as the render thread reads them
// Fixed-size VALUE storage only (a count and a SIMD vector, no array): copying a snapshot never touches the heap and the render thread never allocates (spec §5.6). Four rules, groups of up to eight outputs.
/// An ordered group of up to eight outputs as BUS indices (0…7 = Emit Riff A … Emit Notes D, `FourfoldPorts.bus`). The document stores CABLES (`HocketRule`); `init(cables:)` converts once, on the main thread.
struct HocketGroup: Equatable {
    private(set) var count = 0
    private var buses = SIMD8<UInt8>(repeating: 0)
    init() {}
    init(cables: [Int]) {
        for c in cables where (1...8).contains(c) && count < 8 { buses[count] = UInt8(c - 1); count += 1 }
    }
    subscript(i: Int) -> Int { Int(buses[i]) }
    var isEmpty: Bool { count == 0 }
    func index(of bus: Int) -> Int? {
        for i in 0..<count where Int(buses[i]) == bus { return i }
        return nil
    }
    func contains(bus: Int) -> Bool { index(of: bus) != nil }
    /// Bit b set ⇔ bus b is in the group.
    var mask: UInt8 {
        var m: UInt8 = 0
        for i in 0..<count { m |= UInt8(1) << buses[i] }
        return m
    }
}
struct HocketRuleSnap: Equatable {
    var lit = false                       // on AND MAIN not empty (§3.3) — an unlit rule touches nothing (§6.1)
    var mode: HocketRuleMode = .swap
    var main = HocketGroup(), alt = HocketGroup()
    var unit: HocketUnit = .hits
    var mainLen = 1, altLen = 1, offset = 0
    var rotate = false                    // several == ROTATE
    var replace = true                    // own == REPLACE
    var countOnBus = -1                   // the bus of COUNT ON's output (its lane is the rule's reference lane); −1 = none
    init() {}
    init(_ r: HocketRule) {
        lit = r.isLit; mode = r.mode; main = HocketGroup(cables: r.main); alt = HocketGroup(cables: r.alt)
        unit = r.unit; mainLen = r.mainLen; altLen = r.altLen; offset = r.offset
        rotate = r.several == .rotate; replace = r.own == .replace
        countOnBus = r.main.indices.contains(r.countOn) ? r.main[r.countOn] - 1 : -1
    }
    var cycleLength: Int { mainLen + altLen }
    var referenceLane: Int { countOnBus >= 0 ? countOnBus / 2 : -1 }
}
struct HocketRulesSnap: Equatable {
    var r0 = HocketRuleSnap(), r1 = HocketRuleSnap(), r2 = HocketRuleSnap(), r3 = HocketRuleSnap()
    var litMask: UInt8 = 0                // bit i = rule i is lit
    var litBusMask: UInt8 = 0             // every output in either group of a LIT rule — the outputs whose strikes JOIN a sounding key (§7.3)
    var ruleOfBus = SIMD8<Int8>(repeating: -1)   // the lit rule an output is in (−1 = none); at most one by §5.4
    init() {}
    init(rules: [HocketRule]) {
        for (i, r) in rules.prefix(HocketRuleSet.maxRules).enumerated() {
            let s = HocketRuleSnap(r)
            self[i] = s
            guard s.lit else { continue }
            litMask |= UInt8(1) << UInt8(i)
            litBusMask |= s.main.mask | s.alt.mask
            for b in 0..<8 where (s.main.mask | s.alt.mask) & (UInt8(1) << UInt8(b)) != 0 { ruleOfBus[b] = Int8(i) }
        }
    }
    subscript(i: Int) -> HocketRuleSnap {
        get { switch i { case 0: return r0; case 1: return r1; case 2: return r2; default: return r3 } }
        set { switch i { case 0: r0 = newValue; case 1: r1 = newValue; case 2: r2 = newValue; default: r3 = newValue } }
    }
    /// No lit rule: the Router's output is unchanged, bit for bit (§7.6).
    var isInert: Bool { litMask == 0 }
}

struct SnapParams {
    var type: ProcessorType = .arp
    var octaves: UInt8 = 1
    var gate: Double = 0.6
    var phase: ArpPhase = .legato   // arp FLOW default (Paul 2026-09-14): LEGATO (was RETRIG) — matches MachineParams so a nil-phase arp reads + plays legato
    var count: UInt8 = 3             // ratchet
    var ramp: Double = 0.5
    var spread: Double = 0.1         // strum stagger, beats
    // EUCLID MASK, standalone processor (Paul 2026-09-27): the resolved shape for the downstream-fold processor type
    // (§ isModifierFoldable) — gates ANY driver, not just ARP (the arp's own embedded version is removed, Paul
    // 2026-09-28). No WALK field: WAIT was dropped (a downstream fold can't reach the driver's own phase-index).
    var maskN: Int = 8
    var maskK: Int = 8
    var euclidPulsesFromPool: Bool = false   // POOL mode: K = the held-note count
    var euclidRateBeats: Double = 0.25       // GRID: the step grain (resolved from euclidRate; 1/16 = 0.25 beat)
    var euclidSpanN: Int = 0                  // SPAN re-anchor: 0 = FREE (free-run) · >0 = re-sync the pattern every N columns
    var euclidLines: [EuclidLine] = []       // EUCLID LINES (§10): up to 8 lines; EMPTY ⇒ the single euclid above (byte-identical)
    var euclideousRiff: EuclideousRiff = EuclideousRiff()   // EUCLIDEOUS's own shared riff pattern (Paul 2026-10-06), pre-resolved
    // LANE SOLO (2026-10-21): bit i = Euclideous lane i is soloed (latched | held). 0 (the default, and every non-Euclideous cell) = no solo ⇒ the Router's output is unchanged.
    var soloMask: UInt8 = 0
    // LANE LOCK (2026-10-21): per Euclideous lane — on, snap-back grid, the locked state L — and the document revisions this snapshot was built from. Empty / 0 (the default, and every non-Euclideous cell) ⇒ the Router's
    // output is unchanged, bit for bit.
    var euclideousLocks: [EuclideousLockSnap] = []
    var lockRevs: UInt32 = 0
    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry) — SUPERSEDES the old per-lane
    // (Paul 2026-10-08) `laneSrcChanMasks: [UInt16]` entirely: one resolved channel mask for the WHOLE page
    // when the global source is MIDI (0xFFFF default — "any live input"; irrelevant for KEY/CHORDS, which
    // read elsewhere — see Router.swift's `.euclid` case). `globalSrcChanMaskSet` mirrors the old array's
    // own empty-vs-populated distinction (Router.swift's legacy-pool fallback check) — false for every
    // non-Euclideous `.euclid` cell.
    var globalSrcChanMask: UInt16 = 0xFFFF
    var globalSrcChanMaskSet: Bool = false
    var euclideousNoteSourceResolved: EuclideousLaneSource = .key
    // SOURCES STACK ferry (2026-10-26): the resolved stacking plan + the dev-only clash policy, threaded from
    // `doc.sourcePlanResolved` / `doc.clashPolicyResolved`. Only the Euclideous row's cell reads them (Router's
    // `.euclid` stacked-pool build). Defaults keep every non-Euclideous cell and a pre-thread build inert.
    var euclideousSourcePlan: SourcePlan = SourcePlan()
    var euclideousClashPolicy: ClashPolicy = .allow
    // HOLD/LATCH (Paul 2026-10-20): nil = off (plain live MIDI, today's behaviour). Only consulted by
    // Router.swift's `.euclid` `case .midi:` branch — inert for CHORDS/KEY and every non-Euclideous `.euclid` cell.
    var euclideousHoldLatchMode: EuclideousHoldLatchMode? = nil
    // EUCLIDEOUS CHORDS (Paul 2026-10-08): the page's own self-contained chord progression reuses the SHARED
    // chords* fields directly (chordsMode/chordsDegrees/chordsSteps/chordsRateBeats/chordsRotate/chordsVoicing/
    // chordsSpread, already present on SnapParams for the regular CHORDS processor) rather than a parallel
    // field set — chordSeqNotes (Derivations.swift) is EXPLICITLY designed to take any SnapParams, by its own
    // doc comment: "SHARED by the CHORDS PROCESSOR stage AND the chord DOOR pool-fill... the 'future processor
    // work reflects on the door' contract in one function." Safe: Router.swift's `.euclid` switch arm never
    // reads chordsMode/chordsDegrees/etc itself — those fields are inert on an EUCLID-typed SnapParams except
    // where THIS feature explicitly reads them for its own CHORDS-mode lanes. keyRoot/keyTones are the two
    // things chordSeqNotes needs that AREN'T part of the shared chords* fields (it takes them as explicit
    // params, resolved by whichever caller owns a key) — Euclideous's own page-level KEY, not a receiver door.
    var euclideousChordKeyRoot: Int = 0
    var euclideousChordKeyTones: [Int] = [0, 2, 4, 5, 7, 9, 11]   // natural minor's own intervals would be more apt as a default, but this is overwritten every render for Euclideous's row regardless — harmless placeholder
    var euclideousResetSpanBars: Int = 0   // 0 = OFF; resolved straight from doc.euclideousResetSpanBarsResolved, gated to Snap.euclideousRow
    // SEQUENCER PANEL (2026-10-14 ferry): four independently-stored riffs (replacing the single shared
    // `euclideousRiff` above for Euclideous's own row — see Router.swift's `playingRiffIdx` in the unified
    // "lit notes plus the riff" pipeline) + two 1-bar-default step clocks (LANES: which lanes sound each
    // step; RIFFS: which of the four riffs plays each step), both gated to `Snap.euclideousRow` exactly
    // like `euclideousResetSpanBars` above — inert (all-default) for every other `.euclid` cell in the grid.
    var euclideousRiffs: [EuclideousRiff] = [EuclideousRiff(), EuclideousRiff(), EuclideousRiff(), EuclideousRiff()]
    var activeRiff: Int = 0   // which riff plays when RIFFS seq is off (and which tab the editor shows)
    // FX TAB (2026-10-18): the page-level FX rows, resolved/clamped by `PluginState.euclideousFXResolved`, gated to `Snap.euclideousRow` — fixed-size flat arrays, only ever READ on the render thread.
    var euclideousFX: EuclideousFX = EuclideousFX()
    // HOCKET (2026-10-27): the page-level rules, gated to `Snap.euclideousRow`; inert (no lit rule) ⇒ the Router's output is unchanged, bit for bit.
    var hocketRules: HocketRulesSnap = HocketRulesSnap()
    var euclideousLanesSeqOn: Bool = false
    var euclideousLanesSeqRate: EuclideousSeqRate = .oneBar
    var euclideousLanesSeqLen: Int = 8
    var euclideousLanesSeqCells: [Bool] = [Bool](repeating: true, count: 32)   // step*4 + lane, row-major
    var euclideousRiffsSeqOn: Bool = false
    var euclideousRiffsSeqRate: EuclideousSeqRate = .oneBar
    var euclideousRiffsSeqLen: Int = 8
    var euclideousRiffsSeqCells: [Int] = [Int](repeating: 0, count: 8)   // which riff (0...3) plays each step
    // THE RIFF + THE LOOPER (FERRY "looper tabs replace the riff tabs", ratified 2026-10-16) — SAME
    // `MachineParams`-routed path as `euclideousRiffs`/`activeRiff` above (not the page-level-only
    // RIFFS-seq fields right above those): BuildPage's publish line builds these fresh from live @State
    // every time, and the engine reads them per render, gated to `Snap.euclideousRow`. The looper fields
    // are NEVER persisted (§8.5) — `euclideousLooperActive == false` is simply "no loop," the common case.
    var euclideousLiveGrid: EuclideousRiff = EuclideousRiff()
    var euclideousLooperActive: Bool = false
    var euclideousLooperStartBeat: Double = 0            // B
    var euclideousLooperPasses: Int = 4                  // N, already resolved to a plain Int here
    var euclideousLooperStartRanks: [Int] = [Int](repeating: 0, count: 8)
    var euclideousLooperEvents: [EuclideousLoopEvent] = []   // capped 128/column at the write site (§3.4)
    var destSlices: [Int] = [0, 1, 2, 3, 0, 1, 2, 3]      // DEST MATRIX (Paul 2026-08-22 §5): per-step emitter (−1=NONE·0=A…3=D), the hocket
    var destRateBeats: Double = 0.5                       // DEST's OWN CLOCK (Paul 2026-09-26): free-running step spacing in beats (from destRate) — decoupled from the driver
    var dealE1 = 0; var dealE2 = 1                       // DEAL (Paul 2026-09-16): the two emitters (0=A…3=D) — the engine finds the .deal proc by type
    var dealN1 = 1; var dealN2 = 1                       // notes to each (≥1)
    var dealMode: DealMode = .overTime                  // when the deal advances
    // CLOCK (Paul 2026-09-26; FIXED/WAVE removed same day — see Models.swift's field comment): resolved DRAWN lane.
    var clockSpanN: Int = 8
    // DRAWN (Stage 2): already fully resolved — clockDrawnRatios carries no −1 sentinels (SnapshotBuilder ran
    // clockDrawnResolveRatios once); the render side just reads these arrays, no further mapping/allocation.
    var clockDrawnRatios: [Double] = [1, 1, 1, 1, 1, 1, 1, 1]
    var clockDrawnGlide: [Bool] = [false, false, false, false, false, false, false, false]
    var clockDrawnSteps: Int = 8
    // KILL STEP (Paul 2026-09-26, MUTE/PAUSE added 2026-09-27): resolved per-step mode row + this stage's own clock.
    // killStepMode is fully resolved (length == killStepCount). killStepColumnMap/ColumnsPerLap/FirstSlot are the
    // PRECOMPUTED transform table (built once in SnapshotBuilder, off the render thread) that killStepPhase/…Inverse
    // read instead of deriving the ON/DROP cycle live — see Derivations.swift's doc comment for why (PAUSE breaks
    // the old closed-form "every real column maps to one local step" assumption). No SnapParams field is ever
    // persisted (rebuilt fresh every publish from MachineParams), so none of this needs decode/migration care.
    var killStepCount: Int = 8
    var killStepColumnMap: [Int] = [0, 1, 2, 3, 4, 5, 6, 7]   // real-column-within-a-lap → local step index
    var killStepColumnsPerLap: Int = 8                        // table length (replaces the old bare "k")
    var killStepRateBeats: Double = 0.5
    var killStepSpanN: Int = 8
    var muteSlices: [Int] = [0, 0, 0, 0, 0, 0, 0, 0]      // MUTE MATRIX (Paul 2026-08-25 §5): per-onset-slice MUTED-emitter mask (bit i = emitter i muted); 0 ⇒ nothing muted
    var riffRanks: [Int] = [1, 2, 3, 0, 2, 3, 4, 0, 1, 2, 3, 0, 5, 4, 3, 0]   // 0 = REST · 1–8 = pool rank (the default figure)
    var riffDir: RiffDir = .forward                      // DIRECTION: the stencil playback order (Paul 2026-09-16)
    var riffDirSeed: UInt64 = 0                          // RANDOM/DRUNK shared seed (mirrors arpSeed); 0 = unset (still deterministic)
    var riffDirBias: Double = 0                          // DRUNK only: −1…1, 0 = neutral
    // CHORDS (ratified 2026-09-01) — resolved. v1 (C2) = PATTERN, stage-declared key.
    var chordsMode: ChordsMode = .pattern
    var chordsDegrees: [Int] = [0, 0, 5, 5, 3, 3, 4, 4]   // 8-step matrix: −1 CARRY · 0…6 degree · 7 REST (default I–vi–IV–V)
    var chordsVoicing: ChordVoicing = .triad
    var chordsSpread: ChordSpread = .close
    var chordsRotate: Int = 0
    var chordsWalkSeed: Int = 0
    var chordsRateBeats: Double = 4                       // the progression clock in beats (default 1/1 = 4 = one chord per bar)
    var chordsSteps: Int = 8                              // the PATTERN matrix length (1…16); the progression loops every N
    // CHORDS GRID ferry (Paul 2026-10-24) §1.4: per-column colour, 0...`chordsSteps`-1 — 0 none · 1...6 = `ChordColour`.
    // [] (the default) ⇒ no colour anywhere, so every caller that never resolves this (the regular CHORDS processor,
    // the chord door) pays zero extra cost and is byte-identical to before this ferry.
    var chordsColours: [Int] = []
}


struct SnapMachine {
    var transpose: Int8 = 0
    var a = SnapParams()             // the one resolved param bag (A/B morph removed)
    var on = OnConfig()              // delta §9 item 1: the resolved ON assignments (arrive/scene = derivations,
    var hue: UInt32 = 0              // the DISPLAY hue (packed RGB) — carried so the render can tag emitted notes with their machine (the reel piano roll paints each note its cell's machine). 0 = unknown ⇒ UI falls back.
}                                    // tap/hold = ephemeral gestures); render reads it precomputed here.



// MARK: - The box: immutable after construction → safe concurrent reads, no locks

final class SnapshotBox {
    let generation: UInt64           // increments per publish; render clears param overrides on change
    let stepBeats: Double
    let swing: Double                // 50…75 (§4 v2.3)
    let machines: [SnapMachine]        // ≥16 — sized to the document
    let cells: [SnapCell]            // Snap.cells (256 = maxCols·rows), index = column * Snap.rows + row
    let busChannels: [UInt8]         // v3.0 (delta §7): 4 stamp channels (1–16), one per OUTPUT (A … D, `FourfoldPorts`)
    let busEnabledMask: UInt8        // delta §6a: bit i set ⇒ part i enabled; disabled = no output (always 0xFF now)
    let ignoreAllNotesOff: Bool      // INPUT (Paul 2026-09-06): ignore an incoming CC120/123 (All Sound/Notes Off) so a chatty source (which floods these around each chord) can't wipe the live input pool. Default true.
    // PER-PART CLOCK (Paul 2026-08-19): the raw per-row step/len arrive as init params + are resolved below; only the RESOLVED arrays are stored.
    let rowStep: [Double]            // RESOLVED per-row step (always Snap.rows long; falls back to `stepBeats`) — what the render reads
    let rowLength: [Int]             // RESOLVED per-row loop length (always Snap.rows long; falls back to Snap.cols) — what the render reads
    let rowLaunchAnchor: [Double]    // PLAY-FERRY LAUNCH (Paul 2026-09-09): per-row launch phase anchor in beats. 0 ⇒ no anchor (transport-locked = today, byte-identical).
    let rowLaneMask: [UInt16]         // PER-ROW LAP (Paul 2026-08-19): per-row column-loop mask; empty ⇒ use the EPHEMERAL global lap (laneMask) for every row. Non-empty (count Snap.rows) ⇒ each row reads its own.

    init(generation: UInt64, stepBeats: Double, swing: Double,
         machines: [SnapMachine], cells: [SnapCell], busChannels: [UInt8], busEnabledMask: UInt8 = 0xFF,
         ignoreAllNotesOff: Bool = true,
         rowStepBeats: [Double] = [], rowLen: [Int] = [], rowLaneMask: [UInt16] = [],
         rowLaunchAnchor: [Double] = []) {
        self.rowLaneMask = rowLaneMask
        self.generation = generation
        self.stepBeats = stepBeats
        self.swing = swing
        self.machines = machines
        self.cells = cells
        self.busChannels = busChannels
        self.busEnabledMask = busEnabledMask
        self.ignoreAllNotesOff = ignoreAllNotesOff
        // PER-PART CLOCK helpers: resolve a row's step + loop length, falling back to the global values (uniform = today).
        func resolvedStep(_ r: Int) -> Double { (r >= 0 && r < rowStepBeats.count && rowStepBeats[r] > 0) ? rowStepBeats[r] : stepBeats }
        func resolvedLen(_ r: Int) -> Int { (r >= 0 && r < rowLen.count && rowLen[r] >= 1) ? min(Snap.maxCols, rowLen[r]) : Snap.cols }   // CLAMP to maxCols (allow a 16-wide loop); UNSET ⇒ the default
        self.rowStep = (0..<Snap.rows).map(resolvedStep)
        self.rowLength = (0..<Snap.rows).map(resolvedLen)
        self.rowLaunchAnchor = (0..<Snap.rows).map { $0 < rowLaunchAnchor.count ? rowLaunchAnchor[$0] : 0 }   // PLAY-FERRY LAUNCH: pad to Snap.rows; unset ⇒ 0 = no anchor (byte-identical)
    }

    /// UNDO PROBE (`FourfoldAudioUnit.probeBoxAgreement`): what this box holds for the Euclideous row that the page's document can change — the four lanes (the machine face) and the HOCKET rules. The rules are read from the
    /// CELL's `procs[0]` because that is where `SnapshotBuilder` writes them (the machine face's `hocketRules` is always the default, so hashing it could never see a missed republish). nil when the box has no Euclideous row.
    var euclideousProbeDescription: String? {
        guard Snap.euclideousRow < cells.count else { return nil }
        let cell = cells[Snap.euclideousRow]
        guard cell.machineIndex >= 0, Int(cell.machineIndex) < machines.count else { return nil }
        return String(describing: machines[Int(cell.machineIndex)].a.euclidLines) + "|" + String(describing: cell.procs.first?.hocketRules)
    }
}

// MARK: - Macro modulation (the offset applier — base ⊕ Σ value×delta, clamped)





// MARK: - Effective params (render-side, §3.2: stepped fields quantize, never glide)

// CELL MACHINE (morph removed): the A/B blend is gone — every effective* reads the single (A) param bag.
// They keep a `t` arg (always 0, ignored) so the render call sites are unchanged; the render feeds them the
// per-cell chain slot via the `treat.a = head` injection SnapMachine. (The retired a→b interpolation, tiers,
// and morphMaster #300 are history — the Codable fields are decode-only, and the param addresses (200-215/300)
// were REMOVED 2026-09-16 and are FREE to reuse.)
@inline(__always)
func effectiveType(_ c: SnapMachine) -> ProcessorType { c.a.type }











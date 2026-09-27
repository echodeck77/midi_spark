import Foundation

// PURE BUILD-page logic (Paul 2026-08-16) — the decision cores pulled out from `buildPublishScene` and the staging
// reconcile so they can be UNIT-TESTED (BuildPage.swift is a SwiftUI `extension DiagView` and never reaches the test
// target). Foundation-only, no @State, no `au?` — data in, data out. The view layer (BuildPage) is now a thin shell
// that gathers @State into these inputs and publishes the result.
enum BuildSceneLogic {

    /// Everything `composeScene` needs, gathered from the BUILD @State by the shell.
    struct Input {
        var chainActive = false              // PLAY THIS MIDI CHAIN is the voice (was `ddSolo`)
        // THE MIDI CHAIN (raw audition of the selected machine)
        var chainMachineID: String? = nil
        var chainMachine: [ProcessorSlot] = []         // the machine's audible chain — [] = a born-audible passthrough
        var chainReceiver = 0                          // the SELECTED machine's input door (its row's, resolved) — Paul 2026-08-18
        var chainEmitters: Set<Bus> = []               // the SELECTED machine's output emitters (its row's, resolved)
        // FERRY ROW UNIFICATION (Paul 2026-09-27, Stage 3): every one of the 8 play ferries composes from its OWN
        // BuildPart into its OWN dedicated row block (Snap.ferryRowBase(t)) — the one currently open on the bench or
        // playing quietly in the background, no distinction. `ferryParts[activeFerry]` is captured fresh from the LIVE
        // bench @State each publish (so an edit is heard at once); every other entry is that ferry's stored part.
        // `ferryRowChain` carries the per-ferry, per-ROW variation chain ALREADY RESOLVED (a row's own override, else
        // its machine's own chain) — that fallback needs `buildMachineChain` (the AU-backed registry), which this
        // Foundation-only shell can't reach, so `buildPublishScene` resolves it before handing the Input over.
        var ferryParts: [BuildPart?] = Array(repeating: nil, count: Snap.ferries)
        var ferryRowChain: [[[ProcessorSlot]]] = Array(repeating: Array(repeating: [], count: Snap.rowsPerFerry), count: Snap.ferries)
        var ferryOn: [Bool] = Array(repeating: false, count: Snap.ferries)         // per-ferry play state (buildPlayColOn)
        var ferryAudible: [Bool] = Array(repeating: true, count: Snap.ferries)     // per-ferry mute/solo gate (buildFerryAudible)
        var activeFerry: Int = -1              // which ferry (if any) is open on the bench — only it takes `stagingLane`'s manual loop-hold + hosts the chain audition's free-row search
        // PER-ROW LAP (Paul 2026-08-19): the loop mask a live bench "hold columns" gesture applies to the ACTIVE ferry
        // only (background ferries have no such gesture running on them).
        var stagingLane: UInt16 = 0
        var playLane: UInt16 = 0
        var rowLaunchAnchor: [Double] = []             // PLAY-FERRY LAUNCH (Paul 2026-09-09): per-ENGINE-row launch anchor in beats (0 ⇒ no anchor). The active ferry is excluded (stays transport-locked); a background ferry's anchor fans out across all of its own dedicated rows.
        // PART AUTOMATION (Paul 2026-09-02): per-machine AUTO lanes. A machine's active lane ramps a param across its
        // EXTENT of part cells, baked per-cell here (applyAuto). Empty ⇒ byte-identical.
        var partAuto: [String: PartAutoMachine] = [:]
    }

    /// Build the ephemeral SceneState the engine renders for the active BUILD voices, or `nil` when nothing plays.
    /// Three independent passes — piece → part → chain — matching `buildPublishScene`. The chain lands raw on the
    /// LEAST-occupied free row (every free column active), so it sounds alongside the piece with none of the part
    /// grid's per-column rules; it only goes gappy when all 8 rows are full.
    /// A play column's pass length, clamped to [1, Snap.cols] (out-of-range / short array → a single cell). Shared by
    /// the composer + BuildPage's sweep-index helper so the clamp lives in ONE place. (refactor 2026-08-30)
    static func passLen(_ arr: [Int], _ c: Int) -> Int { c < arr.count ? max(1, min(Snap.maxCols, arr[c])) : 1 }   // §E: a play pass can be up to 16 steps
    // POLY-PREP (Paul 2026-09-14): the ONE place that reads "which rung(s) speak in column `c`" of a per-column
    // selection array. Mono today (`stagingSel` is a single Int per column, -1 = silent). When a column
    // can hold a SET of rungs (poly selections), only these two bodies change — every caller already asks here.
    /// The primary selected rung for column `c` (-1 = the column is silent / out of range). Poly's "lead" rung.
    static func selectedRung(_ sel: [Int], _ c: Int) -> Int { (c >= 0 && c < sel.count) ? sel[c] : -1 }
    /// POLY LANDS (Paul 2026-09-27): every rung sounding in column `c` — the plural half of the seam above. SINGLE mode
    /// (`multi` nil/out-of-range/that column's byte is 0) degenerates to exactly `[lead]` (or `[]` when silent) — byte-
    /// identical to `selectedRung` everywhere multi-select is unused. Once a column's mask is non-zero it's read
    /// EXCLUSIVELY (the mask IS the selection, not an addition to the lead) — bit `r` set ⇒ row `r` sounds.
    static func activeRungs(_ sel: [Int], _ multi: [UInt8]?, _ c: Int) -> [Int] {
        let lead = selectedRung(sel, c)
        guard let m = multi, c >= 0, c < m.count, m[c] != 0 else { return lead >= 0 ? [lead] : [] }
        return (0..<Snap.rowsPerFerry).filter { m[c] & (1 << $0) != 0 }
    }
    // FERRY ROW UNIFICATION (Paul 2026-09-27): pure per-BuildPart equivalents of the bench's `buildRowMachine`/
    // `buildRowReceiverResolved`/`buildRowEmittersResolved`, so every ferry — not just whichever is on the bench —
    // resolves its own rows the same way. `rowMachine` finds the row's own machine (the first populated column in it,
    // "one machine per row"); the chain fallback itself still needs `buildMachineChain` (AU-backed), so it's resolved
    // by `buildPublishScene` into `Input.ferryRowChain` — these two stay here since they're pure data lookups.
    static func rowMachine(_ part: BuildPart, _ r: Int) -> String? {
        guard r >= 0, r < Snap.rowsPerFerry else { return nil }
        return (0..<Snap.maxCols).compactMap { c in c < part.stagingCells.count && r < part.stagingCells[c].count ? part.stagingCells[c][r] : nil }.first
    }
    static func partRowReceiver(_ part: BuildPart, _ r: Int) -> Int {
        if let arr = part.rowReceiver, r >= 0, r < arr.count, let own = arr[r] { return max(0, min(3, own)) }
        return max(0, min(3, part.receiver))
    }
    static func partRowEmitters(_ part: BuildPart, _ r: Int) -> Set<Bus> {
        if let arr = part.rowEmitters, r >= 0, r < arr.count, let own = arr[r], !own.isEmpty { return own }
        return part.emitters.isEmpty ? [.a] : part.emitters
    }
    /// PART LOOP SELECTION (Paul 2026-09-26): when `loopCols` is non-empty, play ONLY those columns, in the order
    /// they were added — not sorted, not the whole part. Out-of-range entries (e.g. from a since-shortened part) are
    /// dropped silently; if that empties the selection, falls back to full playback (identity map) rather than going
    /// silent. `count` is the effective step length (feeds rowLen); `physicalColumn(i)` maps a LOGICAL position
    /// (0..<count, the sequential scene column) to the REAL part column to read from / draw at — the one function
    /// every audio path AND both playheads share, so the lit cell and the emitter actually heard never disagree
    /// (the RATCHET/DEST/ferry-rate lesson). Pure.
    static func loopColumnPlan(_ loopCols: [Int], length: Int) -> (count: Int, physicalColumn: (Int) -> Int) {
        let valid = loopCols.filter { $0 >= 0 && $0 < length }
        guard !valid.isEmpty else { return (length, { $0 }) }
        return (valid.count, { i in valid[max(0, min(valid.count - 1, i))] })
    }
    // PLAY-FERRY LAUNCH (Paul 2026-09-09, Phase 3): the ferries a NEW launch chokes — every OTHER currently-ON ferry sharing
    // the launching ferry's non-OFF choke group. Pure so the choke rule is unit-tested. group ≤ 0 (OFF) ⇒ no victims.
    static func chokeVictims(launching t: Int, group g: Int, parts: [BuildPart?], on: [Bool]) -> [Int] {
        guard g > 0 else { return [] }
        var victims: [Int] = []
        for u in 0..<parts.count where u != t {
            guard u < on.count, on[u], let p = parts[u], p.chokeGroupResolved == g else { continue }
            victims.append(u)
        }
        return victims
    }

    // MARK: PART AUTOMATION (the AUTO lanes, Paul 2026-09-02) — pure, testable, single source of truth for the band + the bake.
    /// The pre-mapped USEFUL default param per processor (Paul: "length for arp"). "" ⇒ fall to the first param.
    static func autoPrimaryKey(_ type: ProcessorType) -> String {
        switch type {
        case .arp, .riff, .ratchet: return "gate"        // note length
        case .strum:    return "spread"                  // rake width
        case .chance:   return "probability"             // density
        case .harmonize: return "harmVelScale"
        default:        return ""
        }
    }
    /// The param a lane automates: the lane's chosen key if valid, else the curated default, else the first NON-BYPASS
    /// param (never BYPASS — it's always params.first, so a plain fallback would ramp a mute gate for the ~12 types
    /// without a curated default; a fresh lane must sweep something musical, Paul 2026-09-02). Only a bypass-ONLY type
    /// (no automatable param) falls to bypass, unavoidably.
    static func autoResolvedParamKey(_ type: ProcessorType, laneParam: String) -> String {
        let params = macroParamsForProcessor(type)
        if !laneParam.isEmpty, params.contains(where: { $0.key == laneParam }) { return laneParam }
        let prim = autoPrimaryKey(type)
        if !prim.isEmpty, params.contains(where: { $0.key == prim }) { return prim }
        return params.first(where: { $0.key != "bypass" })?.key ?? params.first?.key ?? ""
    }
    /// The musical SUB-RANGE the ramp sweeps for a param (Paul 2026-09-02: a sub-range, not the full param range — a
    /// fresh lane must sound musical). Curated for the common continuous params; a generic continuous trims the dead
    /// bottom fifth; discrete params sweep their whole discrete range (applyProcessorValues rounds/snaps).
    static func autoSubRange(_ key: String, _ kind: MacroControlKind) -> (lo: Double, hi: Double) {
        switch key {
        case "gate":            return (0.3, 1.0)
        case "spread":          return (0.1, 1.0)
        case "probability":     return (0.2, 1.0)
        case "harmVelScale":    return (0.35, 1.0)
        case "curve", "velTilt": return (-1.0, 1.0)      // bipolar — full sweep
        default: break
        }
        switch kind {
        case .continuous(let lo, let hi): return (lo + 0.2 * (hi - lo), hi)   // trim the dead bottom fifth
        case .toggle:                     return (0.0, 1.0)
        case .option(let opts):           return (0.0, Double(max(0, opts.count - 1)))
        case .stepper(let lo, let hi):    return (Double(lo), Double(hi))
        case .mask(let bits):             return (0.0, Double((1 << max(0, bits)) - 1))
        }
    }
    /// The param's FULL value range (the FROM/TO faders' bounds — the user can set the sweep anywhere in it). Continuous
    /// returns the raw range (autoSubRange TRIMS it for the default); discrete = the whole discrete range.
    static func autoParamFullRange(_ kind: MacroControlKind) -> (lo: Double, hi: Double) {
        if case .continuous(let lo, let hi) = kind { return (lo, hi) }
        return autoSubRange("", kind)   // discrete: autoSubRange already returns the full discrete range
    }
    /// The ramped value at a cell = its rank in the extent (column→row order) → sub-range low→high. A single cell = the
    /// top (full effect). Pure — the ramp is derived from the extent, nothing stored per cell.
    static func autoRamp(_ lo: Double, _ hi: Double, rank: Int, count: Int) -> Double {
        guard count > 1 else { return hi }
        return lo + (Double(rank) / Double(count - 1)) * (hi - lo)
    }
    /// Fold a machine's active AUTO lane onto a cell's chain at (col,row): if the lane's extent includes this cell, set
    /// its resolved param to the ramped value. Returns the chain unchanged when there's no active lane / this cell isn't
    /// in the extent / the slot is out of range → BYTE-IDENTICAL when no automation is armed. (Baked at build, invariant 1.)
    static func applyAuto(_ chain: [ProcessorSlot], machineID: String?, col: Int, row: Int,
                          partAuto: [String: PartAutoMachine], partWidth: Int) -> [ProcessorSlot] {
        guard let cid = machineID, let pa = partAuto[cid], pa.activeLane >= 0, pa.activeLane < 5,
              pa.activeLane < pa.lanes.count else { return chain }
        let lane = pa.lanes[pa.activeLane]
        guard lane.slot >= 0, lane.slot < chain.count else { return chain }
        // PHASE 2 (Paul 2026-09-04): a ×N-passes or SMOOTH lane is applied at RENDER time (box.renderAuto), NOT baked here —
        // the compile-time bake is one loop and can't progress across bars / sample per-note. Leave the base param.
        if (lane.spanPasses ?? 0) >= 2 || lane.smooth { return chain }
        // SPAN-ONLY (Paul 2026-09-04): the automation is one contiguous span that TILES across the row. A cell at/after
        // the span start gets the FROM→TO ramp at its position WITHIN its tile: rank = (col − start) mod len. The default
        // (start 0, len = partWidth) is a single sweep across the whole part. Cells before the start are untouched.
        let start = max(0, lane.spanStart ?? 0)
        let len = max(1, lane.spanLen ?? max(1, partWidth))
        guard col >= start else { return chain }
        let type = chain[lane.slot].type
        let key = autoResolvedParamKey(type, laneParam: lane.param)
        guard !key.isEmpty, let p = macroParamsForProcessor(type).first(where: { $0.key == key }) else { return chain }
        let (subLo, subHi) = autoSubRange(key, p.kind)
        let lo = lane.lo ?? subLo, hi = lane.hi ?? subHi   // FROM → TO: the lane's set endpoints, else the curated sub-range
        let rank = (col - start) % len
        let value = autoRamp(lo, hi, rank: rank, count: len)
        var out = chain
        out[lane.slot] = applyProcessorValues([key: value], to: out[lane.slot])
        return out
    }
    static func composeScene(_ i: Input) -> SceneState? { composeSceneMeta(i).scene }
    /// As `composeScene`, but also returns the engine ROW the SELECT/chain audition parked on (col 0) — so the UI can read
    /// its LIVE strike feed at `idx = col0*Snap.rows + auditionRow` and drift the aimed ferry's real notes (Paul 2026-08-30,
    /// #5: the audition composes on a DYNAMIC row, so the ferry couldn't line up its strikes without knowing which).
    static func composeSceneMeta(_ i: Input) -> (scene: SceneState?, auditionRow: Int?) {
        let anyFerryOn = zip(i.ferryOn, i.ferryAudible).contains { on, audible in on && audible }
        guard anyFerryOn || i.chainActive else { return (nil, nil) }
        var s = SceneState.empty()
        var chainLaneRow: Int? = nil                                // the SELECT audition's engine row → looped to column 0 (a 1-step continuous pass)
        var chainPinned = false                                     // P1 (2026-08-30): pin col 0 ONLY for the single-cell (empty-row) audition; the fallback lays across many cols and must SWEEP
        var rowStepRate = [StepRate?](repeating: nil, count: Snap.rows)   // PER-PART CLOCK (Paul 2026-08-19): each scene ROW takes its owning part's rate/length; nil ⇒ the scene default
        var rowLen = [Int?](repeating: nil, count: Snap.rows)
        var rowLane = [UInt16](repeating: 0, count: Snap.rows)            // PER-ROW LAP (Paul 2026-08-19): the loop mask whichever voice's cell landed on a row takes

        // FERRY ROW UNIFICATION (Paul 2026-09-27, Stage 3): ONE loop, every ferry — the one open on the bench or playing
        // quietly in the background, no distinction — composes identically into its own dedicated `ferryRowBase(t)`
        // block. Folds together what were 3 separate passes (cell placement, the rate/length clock-claim, the rowLane
        // contribution): each needs the same per-column `selectedRung` + `loopColumnPlan`, so computing it once per
        // column here (rather than once per PASS, as before) is a straight simplification, not a behaviour change.
        for t in 0..<Snap.ferries {
            guard t < i.ferryOn.count, i.ferryOn[t], t < i.ferryAudible.count, i.ferryAudible[t],
                  t < i.ferryParts.count, let part = i.ferryParts[t] else { continue }
            let base = Snap.ferryRowBase(t)
            let dfltBuses: Set<Bus> = part.emitters.isEmpty ? [.a] : part.emitters
            let partLen = max(1, min(Snap.maxCols, part.length ?? Snap.cols))
            // PART LOOP SELECTION (Paul 2026-09-26): loopColumnPlan falls back to the identity map (every physical
            // column, in order) when the part's loopCols is empty, so this is byte-identical when unused.
            let plan = loopColumnPlan(part.loopCols ?? [], length: partLen)
            let rowChain: [[ProcessorSlot]] = t < i.ferryRowChain.count ? i.ferryRowChain[t] : []
            var rowOccupied = [Bool](repeating: false, count: Snap.rowsPerFerry)   // which of this ferry's rows actually sounded — feeds the clock-claim + rowLane blocks below without a second scan
            for logical in 0..<plan.count {   // §E: 16-wide part, or the LOOP SELECTION's own length/order
                let c = plan.physicalColumn(logical)         // read from the REAL part column…
                // MULTI-SELECT (Paul 2026-09-27): the mask is only consulted when the ferry's own selMulti is ON — a
                // ferry switched back to SINGLE plays just its lead rung even if a stale mask survives from before
                // (activeRungs degenerates to [selectedRung] whenever `multi` is nil, byte-identical to the old
                // single-`r` loop everywhere multi-select is unused).
                for r in activeRungs(part.stagingSel, part.selMultiResolved ? part.stagingMulti : nil, c) {
                    guard r >= 0, r < Snap.rowsPerFerry, c < part.stagingCells.count, r < part.stagingCells[c].count,
                          let cid = part.stagingCells[c][r] else { continue }
                    let chain = r < rowChain.count ? rowChain[r] : []
                    // A MACHINE-LESS cell on the PART GRID is SILENT (Paul 2026-08-26): the user only SELECTED it, they
                    // haven't set it up — no output until a machine is added. (The no-machine live-wire still monitors
                    // input when you're BUILDING a chain — PLAY THIS MIDI CHAIN / the chain branch below.)
                    guard !chain.isEmpty else { continue }
                    rowOccupied[r] = true
                    let buses = partRowEmitters(part, r)
                    let recv = partRowReceiver(part, r)
                    var cell = Cell(machineID: cid, buses: buses.isEmpty ? dfltBuses : buses)
                    cell.inputReceiver = recv
                    cell.processors = applyAuto(chain, machineID: cid, col: c, row: r, partAuto: i.partAuto, partWidth: partLen)   // PART AUTOMATION bake
                    s.setCell(logical, base + r, cell)           // …write to the SEQUENTIAL scene column (the audition sits in front on a slot collision)
                }
            }
            for r in 0..<Snap.rowsPerFerry where rowOccupied[r] {
                // rowLen reflects the LOOP's own length only when it actually changes the count (byte-identical when
                // the feature is unused — an unset loop resolves plan.count == partLen == part.length).
                rowStepRate[base + r] = part.rate
                rowLen[base + r] = (plan.count == partLen) ? part.length : plan.count
                // ROW LANE: a truly single-column pass (plan.count <= 1) plays CONTINUOUSLY — pinned to column 0 — same
                // as the old background-ferry flatten's len<=1 case; the ACTIVE ferry instead takes its own manual
                // "hold columns to loop" gesture (stagingLane) regardless of plan.count, same as the old staging pass;
                // any other background ferry sweeps naturally (rowLane 0, rowLen loops it) — its own multi-step case.
                if plan.count <= 1 { rowLane[base + r] = 0b0000_0001 }
                else if t == i.activeFerry { rowLane[base + r] = i.stagingLane }
            }
        }
        if rowStepRate.contains(where: { $0 != nil }) || rowLen.contains(where: { $0 != nil }) {
            s.rowStepRate = rowStepRate; s.rowLen = rowLen
        }

        if i.chainActive, let cid = i.chainMachineID {               // THE MIDI CHAIN / SELECT audition — a 1-step CONTINUOUS pass
            let buses: Set<Bus> = i.chainEmitters.isEmpty ? [.a] : i.chainEmitters   // the SELECTED machine's own I/O (Paul 2026-08-18)
            let recv = max(0, min(3, i.chainReceiver))
            // The audition parks ALONGSIDE the active ferry, scanning the SAME dedicated block its own staging content
            // just composed into above (so "an empty row in the active ferry's part" and "a free row for the chain
            // audition" are the same question, as they always have been).
            if i.activeFerry >= 0 {
                let base = Snap.ferryRowBase(i.activeFerry)
                let activeRows = base..<(base + Snap.rowsPerFerry)
                let occ = activeRows.map { r in (0..<Snap.maxCols).filter { s.cellAt($0, r) != nil }.count }   // scan the full 16-wide part (Paul 2026-09-08) so a row busy only in cols 8–15 isn't treated as empty for the audition overlay
                func mk() -> Cell { var c = Cell(machineID: cid, buses: buses); c.inputReceiver = recv; c.processors = i.chainMachine; return c }
                if let emptyIdx = occ.firstIndex(where: { $0 == 0 }) {
                    let emptyRow = base + emptyIdx
                    // NO RE-STRIKING (Paul 2026-08-29): park at COLUMN 0 of a FULLY-EMPTY row + loop that row to column 0
                    // (below), so the audition plays CONTINUOUSLY — a 1-step pass, exactly like a play cell. (Was laid
                    // across all 8 columns → the grid clock re-triggered it every step, the "select page re-striking"
                    // Paul flagged.)
                    s.setCell(0, emptyRow, mk())
                    chainLaneRow = emptyRow; chainPinned = true            // a single cell at col 0 → pin col 0 (continuous, no re-strike)
                } else if let minIdx = occ.indices.min(by: { occ[$0] < occ[$1] }), occ[minIdx] < 8 {
                    let row = base + minIdx
                    for c in 0..<8 where s.cellAt(c, row) == nil { s.setCell(c, row, mk()) }   // FALLBACK (no empty row — every row already sounds): lay across (may re-strike)
                    chainLaneRow = row                                     // expose the row so the aimed ferry still has a live-strike index (Paul 2026-08-30; col 0 = a chain cell iff it was free)
                }
            }
        }

        // PLAY-FERRY LAUNCH (Paul 2026-09-09): carry the per-engine-row launch anchors onto the scene (0 ⇒ no anchor,
        // transport-locked). A non-zero anchor forces the multi-clock path in the Router and phases the row from column 0.
        if i.rowLaunchAnchor.contains(where: { $0 != 0 }) {
            s.rowLaunchAnchor = (0..<Snap.rows).map { $0 < i.rowLaunchAnchor.count ? i.rowLaunchAnchor[$0] : 0 }
        }

        if let cr = chainLaneRow, chainPinned { rowLane[cr] = 0b0000_0001 }   // P1: pin ONLY the single-cell audition; the fallback laid chain cells across cols 1..7 → leave rowLane 0 so the row SWEEPS (else the pin loops col 0, often ANOTHER voice's cell → the audition is silent)
        // PRESERVE THE FULL-LENGTH-ARRAY CONTRACT (Snapshot.swift's rowLaneMask doc comment): an EMPTY box.rowLaneMask
        // means "use the ephemeral GLOBAL lap key for every row" — a full Snap.rows array (even all-zero) means "each
        // row's own entry decides (0 = no loop)". So this must fire whenever ANY ferry is on, not just when a pin/lane
        // is actually non-zero, else a currently-held global lap key would leak onto a ferry row that should play free.
        if i.stagingLane != 0 || i.playLane != 0 || anyFerryOn || chainLaneRow != nil { s.rowLane = rowLane }

        return (s, chainLaneRow)
    }

    /// Keep each staging column's pick VALID after an edit. Paul 2026-08-16 (bug C1): an explicit −1 (the user
    /// deliberately silenced this column) is PRESERVED — the old code treated −1 like an invalid pick and resurrected
    /// it to the topmost stocked cell. Only a POSITIVE pick at a now-empty/out-of-range cell falls back (to the
    /// topmost stocked cell, or −1 if the column is empty).
    // MUTATE (Paul 2026-08-16): a VALUE-only variation of a processor chain — same STRUCTURE, up to 3 nudged params
    // (biased to one, biased to continuous), GUARANTEED to be NOT silent and to have a Dice FINGERPRINT unlike every one
    // in `avoid` (the source AND every other row already on the grid — else subsequent hits converge). The fingerprint
    // includes VELOCITY + GATE, so a subtle value tweak counts as distinct (not just note-pattern changes). As the loop
    // struggles it escalates (more params, more discrete flips) to reach further. nil if no distinct+audible variant.
    // `scored` (Paul 2026-09-13): when true, collect a few distinct+audible variants and return the MOST MUSICAL
    // (Dice.musicality) instead of the FIRST — so a MUTATE lands a good-sounding variation, not just a different one.
    // Off (default) keeps the cheap first-distinct behaviour for the synchronous row-creator path.
    static func mutateChain<R: RandomNumberGenerator>(_ base: [ProcessorSlot], avoid: [[Int]], _ rng: inout R, scored: Bool = false) -> [ProcessorSlot]? {
        var all: [(slot: Int, param: MacroControlParam)] = []
        for (i, slot) in base.enumerated() where !slot.bypassed {
            for p in macroParamsForProcessor(slot.type) { all.append((i, p)) }
        }
        guard !all.isEmpty else { return nil }
        let cont = all.filter { !$0.param.kind.isDiscrete }, disc = all.filter { $0.param.kind.isDiscrete }
        var candidates: [[ProcessorSlot]] = []
        for attempt in 0..<24 {                                // retry until distinct + audible (escalating with each miss)
            var chain = base
            var contPool = cont.shuffled(using: &rng), discPool = disc.shuffled(using: &rng)
            let count = mutateCount(&rng) + attempt / 6         // escalate breadth as the space gets crowded
            let discChance = 0.5 + Double(attempt) * 0.02       // EQUAL footing note-pattern vs subtle (Paul 2026-08-16); leans discrete only when struggling
            for _ in 0..<count {
                let useDiscrete = !discPool.isEmpty && (contPool.isEmpty || Double.random(in: 0..<1, using: &rng) < discChance)
                guard let tw = (useDiscrete ? discPool.popLast() : (contPool.popLast() ?? discPool.popLast())) else { break }
                var vals = processorValues(chain[tw.slot])
                vals[tw.param.key] = mutateNudge(tw.param, vals[tw.param.key], &rng)
                chain[tw.slot] = applyProcessorValues(vals, to: chain[tw.slot])
            }
            let fp = Dice.fingerprint(chain)
            if !fp.isEmpty && !avoid.contains(fp) {            // NOT silent + unlike everything already present
                if !scored { return chain }                    // fast path: the first distinct variant
                candidates.append(chain)
                if candidates.count >= 3 { break }             // enough to choose the most musical from
            }
        }
        guard scored else { return nil }
        guard !candidates.isEmpty else { return nil }
        return candidates.map { ($0, Dice.musicality($0, band: (0.5, 9.0))) }.max { $0.1 < $1.1 }!.0   // the most musical variation
    }
    static func mutateCount<R: RandomNumberGenerator>(_ rng: inout R) -> Int {
        let r = Double.random(in: 0..<1, using: &rng); return r < 0.65 ? 1 : (r < 0.90 ? 2 : 3)   // ≈65/25/10% one/two/three
    }
    // A bounded nudge of one param value by its kind: continuous ±10–15% of range; discrete a single step / flip.
    static func mutateNudge<R: RandomNumberGenerator>(_ p: MacroControlParam, _ v: Double?, _ rng: inout R) -> Double {
        let cur = v ?? 0
        switch p.kind {
        case .continuous(let lo, let hi):
            let delta = (hi - lo) * Double.random(in: 0.10...0.15, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            return min(hi, max(lo, cur + delta))
        case .toggle: return cur >= 0.5 ? 0 : 1
        case .option(let labels): let n = max(1, labels.count); return Double((Int(cur.rounded()) + (Bool.random(using: &rng) ? 1 : n - 1)) % n)
        case .stepper(let lo, let hi): return Double(min(hi, max(lo, Int(cur.rounded()) + (Bool.random(using: &rng) ? 1 : -1))))
        case .mask(let bits): return Double(Int(cur.rounded()) ^ (1 << Int.random(in: 0..<max(1, bits), using: &rng)))
        }
    }

    // ── SCALE LOCK for generated chains (Paul 2026-09-13) ─────────────────────────────────────────────────────────────
    // When a receiver door is set to SCALE, a RANDOMIZE/MUTATE result can be kept IN KEY by appending a LOCK-to-key AVOID
    // tail that REFERENCES that door — so out-of-key notes snap into the scale (MOVE), and the lock FOLLOWS the door (change
    // the scale → the lock updates). This is the lever that lets generation use richer harmony safely. Pure → unit-tested.

    /// Which door to lock into: the machine's OWN receiver if it's a scale door, else the first scale door among the four.
    /// `isScale[i]` = receiver i is in SCALE mode. nil = no scale set anywhere → don't lock.
    static func scaleLockDoor(isScale: [Bool], preferred: Int?) -> Int? {
        if let p = preferred, p >= 0, p < isScale.count, isScale[p] { return p }
        return isScale.firstIndex(of: true)
    }

    /// Re-assert a LOCK-to-key AVOID tail referencing `door` (snap out-of-key notes into that door's scale). No-op when
    /// there's no scale door (door == nil). IDEMPOTENT: any prior door-referenced LOCK is stripped first (so a re-MUTATE
    /// that bypassed/edited it can't accumulate a second, and the tail stays exactly one active lock). If stripping still
    /// leaves the chain full, it's returned unchanged (can't fit the lock).
    static func scaleLocked(_ chain: [ProcessorSlot], door: Int?, maxSlots: Int = 8) -> [ProcessorSlot] {
        guard let door else { return chain }
        let stripped = chain.filter { !($0.type == .avoid && ($0.params.avoidMode ?? .avoid) == .lock && $0.params.avoidRefKind == .door) }
        guard stripped.count < maxSlots else { return chain }
        var lock = ProcessorSlot(type: .avoid)
        lock.params.avoidRefKind = .door       // reference the scale door's pool → lock to its key, and follow it live
        lock.params.avoidRefIndex = door
        lock.params.avoidMode = .lock          // keep only in-key notes …
        lock.params.avoidAction = .move        // … by SNAPPING out-of-key notes to the nearest scale note (never dropped)
        return stripped + [lock]
    }

    /// DIATONIC HARMONIZE (Paul 2026-09-13): only safe WITH a scale lock (a fixed interval drifts out of key over an
    /// arbitrary held chord). So when we're about to scale-lock, upgrade any OCTAVE-ONLY harmonize to MUSICAL intervals
    /// (thirds/fourths/fifths/sixths) — the lock then snaps them onto the scale, giving in-key harmony. Note COUNT is
    /// preserved (each octave interval is REPLACED, not added), so density/flood is unchanged. Pure → unit-tested.
    /// Call ONLY when a scale door exists (the caller gates it); with no lock these intervals would drift.
    static func scaleEnrichHarmony(_ chain: [ProcessorSlot]) -> [ProcessorSlot] {
        let musical = [4, 7, 3, 5, -5, 9]   // major/minor third, fifth, fourth-down, sixth — snapped to scale by the lock
        return chain.map { slot in
            guard slot.type == .harmonize, let iv = slot.params.harmIntervals else { return slot }
            var out = iv; var k = 0
            for i in out.indices where out[i] != 0 && out[i] % 12 == 0 {   // an octave-only interval → a musical one
                out[i] = musical[k % musical.count]; k += 1
            }
            guard out != iv else { return slot }
            var s = slot; s.params.harmIntervals = out; return s
        }
    }

    static func reconcileStagingSel(_ sel: [Int], cells: [[String?]]) -> [Int] {
        (0..<Snap.maxCols).map { c in   // §E: 16-wide part

            let r = c < sel.count ? sel[c] : -1
            if r < 0 { return -1 }                                  // explicit deselect → keep it silent
            guard c < cells.count else { return -1 }
            let col = cells[c]                                       // guard the ROW bound too: a ragged (< 8) decoded column must not trap (C5 fix 2026-08-27)
            if r >= col.count || col[r] == nil {                    // a positive pick at a missing/empty cell → gentle fallback
                return (0..<col.count).first { col[$0] != nil } ?? -1
            }
            return r
        }
    }
    /// MULTI-SELECT (Paul 2026-09-27): the `stagingMulti` sibling of `reconcileStagingSel` — after an edit, drop any bit
    /// that now points at a missing/empty cell (mirrors the single-select fallback: a positive pick surviving only if
    /// its cell still exists). All-zero (like `stagingSel`'s -1) is the sentinel for "no mask" — no Optional needed.
    static func reconcileStagingMulti(_ multi: [UInt8], cells: [[String?]]) -> [UInt8] {
        (0..<Snap.maxCols).map { c -> UInt8 in
            guard c < multi.count, multi[c] != 0, c < cells.count else { return 0 }
            let col = cells[c]
            var mask: UInt8 = 0
            for r in 0..<Snap.rowsPerFerry where multi[c] & (1 << r) != 0 && r < col.count && col[r] != nil { mask |= (1 << r) }
            return mask
        }
    }

    // ── THE MACHINE BINDING (Paul 2026-09-01, the state-unification refactor) ─────────────────────────────────────────
    // The machine (box + MIDI chain + play button) ALWAYS represents exactly ONE thing, and its play/stop drives THAT
    // thing. Today that binding is re-derived independently at ~5 sites (the play button's `active`, the hue's `isGrey`,
    // each cell's "playing") off four @State axes (buildVoiceOwner · buildPlayColOn · buildSelID · buildGridSelSel), so
    // they desync. This is the ONE pure resolution they all derive from — data in, data out, unit-tested. The shell
    // (BuildPage) gathers the axes into these primitives (Room/BuildWorkshopVoice live in UIKit files, out of the test
    // target, so the inputs are Bool/Int/String).
    enum MachineKind: Equatable { case none, selectAudition, partRow, playFerry(Int) }
    struct MachineBinding: Equatable { var kind: MachineKind; var isGrey: Bool; var playing: Bool }

    /// THE SELECT-PAGE SOURCE (Paul 2026-09-06): the ONE model value for what the machine currently points at on the SELECT
    /// page — a browsed catalog CELL, or a SELECT→part FERRY (a real coloured part row). Both ride the shared `gsAud` audition
    /// transient, so which one it is was previously inferred from two mutually-exclusive Int? @State (buildGridSelSel /
    /// buildGridSelStampSourceRow) kept in sync by hand — a desync risk, and the reason the ferry could render as the colourless
    /// grey (the grey rule couldn't tell a ferry from a cell). As one sum type the exclusivity is a type guarantee.
    enum SelectSource: Equatable {
        case none
        case browseCell(Int)   // a catalog/library cell auditioning on gsAud (colourless → grey)
        case ferryRow(Int)     // a part-row ferry the machine names (rides gsAud but wears the ROW's real machine)
        var isFerry: Bool { if case .ferryRow = self { return true }; return false }
        var browseCell: Int? { if case .browseCell(let i) = self { return i }; return nil }
        var ferryRow: Int? { if case .ferryRow(let n) = self { return n }; return nil }
    }

    /// Resolve what the machine represents + whether it is playing.
    ///  - selID: the machine identity (ddSelectedMachineID) · audID: the transient SELECT-audition machine ("gsAud").
    ///  - onSelectPage: room == .select — only there can the machine bind to a play ferry (the SELECT grid owns them).
    ///  - chainActive / partActive: the DISPLAYED audition voice (buildDisplayVoice == .chain / .part).
    ///  - selectedPlayCol: the play column selID names (buildSelectedPlayCol), or nil · playColOn: per-column play state.
    /// Reproduces roomsVerticalPlay's `ferryCol.map{playColOn} ?? (displayVoice==voice)` + buildMachineHue's grey rule.
    ///  - source: the SELECT-page source (the single model value). A `.ferryRow` rides gsAud like a plain cell audition, but it
    ///    IS a real coloured machine → it must wear its machine, never the colourless grey. Grey is the `.browseCell` case only.
    static func machineBinding(selID: String?, audID: String, onSelectPage: Bool,
                               chainActive: Bool, partActive: Bool,
                               selectedPlayCol: Int?, playColOn: [Bool], source: SelectSource = .none) -> MachineBinding {
        // A play ferry the machine names (SELECT page only) BINDS to that column — its play state is the column's OWN, and
        // it wears the cell's real machine (never grey).
        if onSelectPage, let c = selectedPlayCol, c >= 0, c < playColOn.count {
            return MachineBinding(kind: .playFerry(c), isGrey: false, playing: playColOn[c])
        }
        // grey ONLY on the colourless PLAIN SELECT audition — NOT when a ferry is the source (it carries a real machine via
        // machineHueOverride[gsAud], so it keeps it; a ferry rides gsAud too and used to fall to grey here). Derived from the
        // one model value, not a paired bool: grey ⇔ the audition is loaded AND the source isn't a ferry.
        let grey = onSelectPage && (selID == audID) && !source.isFerry
        let playing = onSelectPage ? chainActive : partActive
        let kind: MachineKind = (selID == nil && !playing) ? .none : (onSelectPage ? .selectAudition : .partRow)
        return MachineBinding(kind: kind, isGrey: grey, playing: playing)
    }

    // THE PART-GRID TAP DECISION (Paul 2026-09-04). ONE pure resolver for what a tap on the part interior does, so the
    // "an UNPOPULATED cell is selectable" rule is LOCKED by tests and cannot silently revert again. It did revert once:
    // the AUTO-lane PUNCH mode was added AFTER that fix and swallowed EVERY non-punch tap (including empty cells) with a
    // bare `return`. Here PUNCH intercepts ONLY its own cells (the selected machine, populated); everything else falls
    // through to normal rung selection — so empty cells stay selectable whether or not a lane is armed.
    enum PartGridTap: Equatable {
        case focus(machineID: String)   // SELECT MODE: focus this machine (populated cell)
        case exitSelectMode            // SELECT MODE tap on an empty cell: just leave select mode
        case deselect                  // tapped the currently-selected rung → the column goes silent
        case selectRung(row: Int)      // select (or drag-paint) this rung — POPULATED OR NOT (SINGLE mode)
        case toggleRung(row: Int)      // MULTI mode: XOR this rung's bit in the column's mask — POPULATED OR NOT
    }
    // The rung/select decision when NO AUTO lane is armed. (When a lane IS armed the drag DRAWS the automation span
    // instead — that's UI-side in buildPartGridDrag, since it needs the drag anchor. Paul 2026-09-04, span-only.)
    // MULTI-SELECT (Paul 2026-09-27): `multi` off reproduces today's behaviour exactly (unchanged branches below); `multi`
    // on always toggles — there's no "first tap of gesture deselects" special case, since a column can have more than
    // one rung active and a tap should only ever affect the ONE rung tapped.
    static func partGridTap(col: Int, row: Int, currentRung: Int, cid: String?, selectedMachineID: String?,
                            selectMode: Bool, firstTapOfGesture: Bool, multi: Bool = false) -> PartGridTap {
        if selectMode { return cid.map { .focus(machineID: $0) } ?? .exitSelectMode }
        if multi { return .toggleRung(row: row) }
        if firstTapOfGesture && currentRung == row { return .deselect }
        return .selectRung(row: row)   // EMPTY cells ARE selectable — the contract, locked by test
    }

}

// ── FERRY DRAG-AND-DROP (Paul 2026-09-12) — the drag carries a SELECT cell or a play ferry; it drops on a ferry (populate
//    / move-overwrite) or the machine-box trash (delete). The enums live here (not in the SwiftUI BuildPage) so the pure
//    decision cores below reach the unit-test target; BuildPage's gesture + FerryZoneKey reference them from the same module.
enum FerryDragSource: Equatable { case selectCell(Int), ferry(Int) }
enum FerryDropZone: Hashable { case ferry(Int), trash }
extension BuildSceneLogic {
    /// Which drop zone (if any) contains point `p`, in the shared drag space. The trash wins ties; then ferries 0…<ferries>. Pure.
    static func ferryZoneAt(_ p: CGPoint, zones: [FerryDropZone: CGRect], ferries: Int = 8) -> FerryDropZone? {
        if let r = zones[.trash], r.contains(p) { return .trash }
        for t in 0..<ferries { if let r = zones[.ferry(t)], r.contains(p) { return .ferry(t) } }
        return nil
    }
    /// FERRY COLOUR SWAP (Paul 2026-09-12, generalised 2026-09-27): a SELECT cell of colour `cellHex` is landing on
    /// ferry `target` (current colour `oldHex`) — the dropped colour always wins at the target, regardless of what
    /// was predetermined there. If `cellHex` is already worn by some OTHER ferry — an empty placeholder OR a
    /// populated one — that ferry takes the DISPLACED colour `oldHex` instead: a true two-slot swap, so the palette
    /// never doubles up and the target never has to fall back to an invented third colour. Returns the other
    /// ferry's index (the first match, ≠ target), or nil when no swap is needed. Pure.
    static func ferryColourDisplacement(target: Int, cellHex: UInt32, oldHex: UInt32, hex: [UInt32]) -> Int? {
        guard oldHex != cellHex else { return nil }
        return hex.indices.first { u in u != target && hex[u] == cellHex }
    }
}

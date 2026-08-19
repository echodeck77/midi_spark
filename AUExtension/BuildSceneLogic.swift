import Foundation

// PURE BUILD-page logic (Paul 2026-08-16) — the decision cores pulled out from `buildPublishScene` and the staging
// reconcile so they can be UNIT-TESTED (BuildPage.swift is a SwiftUI `extension DiagView` and never reaches the test
// target). Foundation-only, no @State, no `au?` — data in, data out. The view layer (BuildPage) is now a thin shell
// that gathers @State into these inputs and publishes the result.
enum BuildSceneLogic {

    /// Everything `composeScene` needs, gathered from the BUILD @State by the shell. A `performActiveRung` CLOSURE is
    /// passed (it reads the deployed parts' selection) so the composer stays pure over its data.
    struct Input {
        var stagingPlaying = false          // PLAY THIS PART is the voice
        var performPlaying = false           // the PLAY grid (THE PIECE) is running
        var chainActive = false              // PLAY THIS MIDI CHAIN is the voice (was `ddSolo`)
        // THE PIECE (play grid)
        var performCells: [[String?]] = []             // [col][row] → colourID
        var performMute: Set<Int> = []                 // key c*8+r
        var performActiveRung: (Int, Int) -> Bool = { _, _ in true }
        var performEmit: [Set<Bus>] = []               // per perform-ROW emitters
        var performRecv: [Int] = []                    // per perform-ROW input door
        var performChain: [[[ProcessorSlot]]] = []     // [col][row] → per-cell variation chain ([] = the colour's own)
        // THE PART (staging grid)
        var stagingCells: [[String?]] = []             // [col][row] → colourID
        var stagingSel: [Int] = []                     // the ONE selected rung per column (-1 = silent)
        var partEmitters: Set<Bus> = []                // the part's DEFAULT output emitters (a row inherits it when unset)
        var selReceiver = 0                            // the part's DEFAULT input door (a row inherits it when unset)
        var rowEmitters: [Set<Bus>] = []               // per staging-ROW emitters, RESOLVED (Paul 2026-08-18); empty/short → partEmitters
        var rowReceiver: [Int] = []                    // per staging-ROW input door, RESOLVED; short → selReceiver
        var rowChain: [[ProcessorSlot]] = []           // per staging-ROW variation chain
        // THE MIDI CHAIN (raw audition of the selected colour)
        var chainColourID: String? = nil
        var chainMachine: [ProcessorSlot] = []         // the colour's audible chain — [] = a born-audible passthrough
        var chainReceiver = 0                          // the SELECTED colour's input door (its row's, resolved) — Paul 2026-08-18
        var chainEmitters: Set<Bus> = []               // the SELECTED colour's output emitters (its row's, resolved)
        // PER-PART CLOCK (Paul 2026-08-19): each part is a TRACK with its own rate/length. nil ⇒ the scene default.
        var performRate: [StepRate?] = []              // per play-grid ROW: its deployed part's rate
        var performLen: [Int?] = []                    // per play-grid ROW: its deployed part's loop length
        var stagingRate: StepRate? = nil               // the CURRENT part's rate (the staging audition rows)
        var stagingLen: Int? = nil                     // the CURRENT part's loop length
        // PER-ROW LAP (Paul 2026-08-19): the two grids' column-loop masks, kept SEPARATE — staging (current part) rows
        // lap `stagingLane`, piece rows lap `performLane`, so looping one grid never loops the other.
        var stagingLane: UInt8 = 0                     // the CURRENT part's column-loop mask (staging grid)
        var performLane: UInt8 = 0                     // the PIECE's column-loop mask (play grid)
    }

    /// Build the ephemeral SceneState the engine renders for the active BUILD voices, or `nil` when nothing plays.
    /// Three independent passes — piece → part → chain — matching `buildPublishScene`. The chain lands raw on the
    /// LEAST-occupied free row (every free column active), so it sounds alongside the piece with none of the part
    /// grid's per-column rules; it only goes gappy when all 8 rows are full.
    static func composeScene(_ i: Input) -> SceneState? {
        guard i.stagingPlaying || i.performPlaying || i.chainActive else { return nil }
        var s = SceneState.empty()

        if i.performPlaying {                                        // THE PIECE — deployed cells, mute + active-rung honoured
            for c in 0..<8 { for r in 0..<8 {
                guard c < i.performCells.count, r < i.performCells[c].count, let cid = i.performCells[c][r],
                      !i.performMute.contains(c * 8 + r), i.performActiveRung(c, r) else { continue }
                let emit: Set<Bus> = (r < i.performEmit.count && !i.performEmit[r].isEmpty) ? i.performEmit[r] : [.a]
                var cell = Cell(colourID: cid, buses: emit)
                cell.inputReceiver = max(0, min(3, r < i.performRecv.count ? i.performRecv[r] : 0))
                let chain = (c < i.performChain.count && r < i.performChain[c].count) ? i.performChain[c][r] : []
                cell.processors = chain.isEmpty ? nil : chain       // [] → fall to the colour's templateChain
                s.setCell(c, r, cell)
            } }
        }

        if i.stagingPlaying {                                       // THE PART — the staging selection, ALONGSIDE the piece; each ROW carries its OWN I/O (Paul 2026-08-18)
            let dfltBuses: Set<Bus> = i.partEmitters.isEmpty ? [.a] : i.partEmitters
            for c in 0..<8 {
                let r = c < i.stagingSel.count ? i.stagingSel[c] : -1
                guard r >= 0, r < 8, c < i.stagingCells.count, r < i.stagingCells[c].count, let cid = i.stagingCells[c][r] else { continue }
                let buses: Set<Bus> = (r < i.rowEmitters.count && !i.rowEmitters[r].isEmpty) ? i.rowEmitters[r] : dfltBuses
                let recv = max(0, min(3, r < i.rowReceiver.count ? i.rowReceiver[r] : i.selReceiver))
                var cell = Cell(colourID: cid, buses: buses)
                cell.inputReceiver = recv
                let chain = r < i.rowChain.count ? i.rowChain[r] : []
                cell.processors = chain.isEmpty ? nil : chain
                s.setCell(c, r, cell)                               // the audition sits in front on a slot collision
            }
        }

        if i.chainActive, let cid = i.chainColourID {               // THE MIDI CHAIN — raw, on the least-occupied free row
            let buses: Set<Bus> = i.chainEmitters.isEmpty ? [.a] : i.chainEmitters   // the SELECTED colour's own I/O (Paul 2026-08-18)
            let recv = max(0, min(3, i.chainReceiver))
            let occ = (0..<8).map { r in (0..<8).filter { s.cellAt($0, r) != nil }.count }
            if let row = (0..<8).min(by: { occ[$0] < occ[$1] }), occ[row] < 8 {
                for c in 0..<8 where s.cellAt(c, row) == nil {
                    var cell = Cell(colourID: cid, buses: buses)
                    cell.inputReceiver = recv
                    cell.processors = i.chainMachine                // explicit chain (even []) — never the legacy A-face arp
                    s.setCell(c, row, cell)
                }
            }
        }

        // PER-PART CLOCK (Paul 2026-08-19): each scene ROW takes its owning part's rate/length. The STAGING (current
        // part) rows win over the piece (they sit in front); a nil ⇒ the scene default (uniform = today).
        var rowStepRate = [StepRate?](repeating: nil, count: 8)
        var rowLen = [Int?](repeating: nil, count: 8)
        if i.stagingPlaying {
            for c in 0..<8 {
                let r = c < i.stagingSel.count ? i.stagingSel[c] : -1
                if r >= 0, r < 8, c < i.stagingCells.count, r < i.stagingCells[c].count, i.stagingCells[c][r] != nil {
                    rowStepRate[r] = i.stagingRate; rowLen[r] = i.stagingLen
                }
            }
        }
        if i.performPlaying {
            for r in 0..<8 where rowStepRate[r] == nil {
                if r < i.performRate.count, let rr = i.performRate[r] { rowStepRate[r] = rr; rowLen[r] = (r < i.performLen.count ? i.performLen[r] : nil) }
            }
        }
        if rowStepRate.contains(where: { $0 != nil }) || rowLen.contains(where: { $0 != nil }) {
            s.rowStepRate = rowStepRate; s.rowLen = rowLen
        }

        // PER-ROW LAP (Paul 2026-08-19): each row takes the loop mask of whichever voice's cell landed on it — mirroring
        // the placement precedence above (piece first, staging overwrites), so the two grids' loops stay independent.
        if i.stagingLane != 0 || i.performLane != 0 {
            var rowLane = [UInt8](repeating: 0, count: 8)
            if i.performPlaying {
                for c in 0..<8 { for r in 0..<8 {
                    guard c < i.performCells.count, r < i.performCells[c].count, i.performCells[c][r] != nil,
                          !i.performMute.contains(c * 8 + r), i.performActiveRung(c, r) else { continue }
                    rowLane[r] = i.performLane
                } }
            }
            if i.stagingPlaying {
                for c in 0..<8 {
                    let r = c < i.stagingSel.count ? i.stagingSel[c] : -1
                    if r >= 0, r < 8, c < i.stagingCells.count, r < i.stagingCells[c].count, i.stagingCells[c][r] != nil {
                        rowLane[r] = i.stagingLane                  // staging is in front → its loop wins the row
                    }
                }
            }
            s.rowLane = rowLane
        }

        return s
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
    static func mutateChain<R: RandomNumberGenerator>(_ base: [ProcessorSlot], avoid: [[Int]], _ rng: inout R) -> [ProcessorSlot]? {
        var all: [(slot: Int, param: MacroControlParam)] = []
        for (i, slot) in base.enumerated() where !slot.bypassed {
            for p in macroParamsForProcessor(slot.type) { all.append((i, p)) }
        }
        guard !all.isEmpty else { return nil }
        let cont = all.filter { !$0.param.kind.isDiscrete }, disc = all.filter { $0.param.kind.isDiscrete }
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
            if !fp.isEmpty && !avoid.contains(fp) { return chain }   // NOT silent + unlike everything already present
        }
        return nil
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

    static func reconcileStagingSel(_ sel: [Int], cells: [[String?]]) -> [Int] {
        (0..<8).map { c in
            let r = c < sel.count ? sel[c] : -1
            if r < 0 { return -1 }                                  // explicit deselect → keep it silent
            guard c < cells.count else { return -1 }
            if r >= 8 || cells[c][r] == nil {                       // a positive pick at an empty cell → gentle fallback
                return (0..<8).first { cells[c][$0] != nil } ?? -1
            }
            return r
        }
    }
}

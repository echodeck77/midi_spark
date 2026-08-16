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
        var partEmitters: Set<Bus> = []                // the part's output emitters
        var selReceiver = 0                            // the part's input door
        var rowChain: [[ProcessorSlot]] = []           // per staging-ROW variation chain
        // THE MIDI CHAIN (raw audition of the selected colour)
        var chainColourID: String? = nil
        var chainMachine: [ProcessorSlot] = []         // the colour's audible chain — [] = a born-audible passthrough
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

        if i.stagingPlaying {                                       // THE PART — the staging selection, ALONGSIDE the piece
            let buses: Set<Bus> = i.partEmitters.isEmpty ? [.a] : i.partEmitters
            let recv = max(0, min(3, i.selReceiver))
            for c in 0..<8 {
                let r = c < i.stagingSel.count ? i.stagingSel[c] : -1
                guard r >= 0, r < 8, c < i.stagingCells.count, r < i.stagingCells[c].count, let cid = i.stagingCells[c][r] else { continue }
                var cell = Cell(colourID: cid, buses: buses)
                cell.inputReceiver = recv
                let chain = r < i.rowChain.count ? i.rowChain[r] : []
                cell.processors = chain.isEmpty ? nil : chain
                s.setCell(c, r, cell)                               // the audition sits in front on a slot collision
            }
        }

        if i.chainActive, let cid = i.chainColourID {               // THE MIDI CHAIN — raw, on the least-occupied free row
            let buses: Set<Bus> = i.partEmitters.isEmpty ? [.a] : i.partEmitters
            let recv = max(0, min(3, i.selReceiver))
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

        return s
    }

    /// Keep each staging column's pick VALID after an edit. Paul 2026-08-16 (bug C1): an explicit −1 (the user
    /// deliberately silenced this column) is PRESERVED — the old code treated −1 like an invalid pick and resurrected
    /// it to the topmost stocked cell. Only a POSITIVE pick at a now-empty/out-of-range cell falls back (to the
    /// topmost stocked cell, or −1 if the column is empty).
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

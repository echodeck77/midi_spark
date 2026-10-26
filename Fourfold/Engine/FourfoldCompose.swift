//  FourfoldCompose.swift
//  FOURFOLD Step 1b (2026-10-23, Docs/standalone-plan.md) — the Fourfold-only scene composer. Foundation-only, pure.
//
//  Fourfold's sound reaches the engine as ONE cell on the reserved `Snap.euclideousRow`: a single `.euclid` processor carrying the four lanes. In 8x8 State that cell is placed by
//  `BuildSceneLogic.composeSceneMeta` (its `euclideousOn` block) next to the ferries / chain audition, and `DiagView.buildPublishScene` builds the chain. This file is the same two steps
//  with nothing else in them, so a Fourfold target does not need BuildSceneLogic (nor Dice / MacroAuthoring / SceneFactory behind it) — and so, by construction, no cell other than a
//  `.euclid` one can ever exist in a Fourfold scene, which is what makes deleting the other processors from Fourfold's engine copy provably safe (plan Step 4).
//  `FourfoldComposeTests` proves the scene equals `composeSceneMeta`'s for the same input; change the placement there and here together until Step 4 retires the 8x8 copy.

import Foundation

enum FourfoldCompose {
    /// The fixed id the Euclideous machine is registered under (can't collide with the auto-incrementing "b<n>" ephemeral ids or the 16 canonical palette ids).
    static let machineID = "euclideous"

    /// The document / UI state that goes into the chain's params. Everything else Fourfold has (FX, key, note source, chords, HOLD/LATCH, the sequencers) is read by `SnapshotBuilder` from the DOCUMENT, not from the chain.
    struct Input: Equatable {
        var lines: [EuclidLine]
        var riff: EuclideousRiff
        var riffs: [EuclideousRiff]
        var activeRiff: Int
        var mainOutMask: UInt8
        /// The EFFECTIVE solo mask (latched | held) — `euclideousSoloEffective`; the render thread sees only the union.
        var soloMask: UInt8
        var locks: [EuclideousLaneLock]
        /// The per-lane document revisions this snapshot is built from (one byte per lane).
        var lockRevs: UInt32
    }

    /// The single-slot EUCLID chain the cell carries.
    static func chain(_ i: Input) -> [ProcessorSlot] {
        var p = MachineParams()
        p.euclidLines = i.lines
        p.euclideousRiff = i.riff
        p.riffs = i.riffs; p.activeRiff = i.activeRiff
        p.mainOutMask = i.mainOutMask
        p.soloMask = i.soloMask
        p.euclideousLocks = i.locks; p.lockRevs = i.lockRevs
        return [ProcessorSlot(type: .euclid, params: p)]
    }

    /// The scene: the Euclideous cell at column 0 of the reserved row, all outputs open (a note's port is fixed by its lane and layer, `FourfoldPorts`), its input the door at index 3 ("receiver 4"),
    /// and the row pinned to a 1-step continuous pass. Every other cell is empty. `rowLane` is always a full `Snap.rows` array (the Snapshot contract: an empty one means "use the global lap key").
    static func scene(chain: [ProcessorSlot]) -> SceneState {
        var s = SceneState.empty()
        var rowLane = [UInt16](repeating: 0, count: Snap.rows)
        var cell = Cell(machineID: machineID, buses: [.a, .b, .c, .d])
        cell.inputReceiver = 3
        cell.processors = chain
        s.setCell(0, Snap.euclideousRow, cell)
        rowLane[Snap.euclideousRow] = 0b0000_0001
        s.rowLane = rowLane
        return s
    }

    static func scene(_ i: Input) -> SceneState { scene(chain: chain(i)) }
}

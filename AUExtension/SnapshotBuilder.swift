//  SnapshotBuilder.swift
//  MidiSpark — document → SnapshotBox, on the UI thread (spec v2.8 §7).
//  The builder resolves everything the render thread must never compute:
//  paramsB merged over paramsA, enum → index mapping, LEGATO run starts.

import Foundation

enum SnapshotBuilder {

    static func build(from doc: PluginState, generation: UInt64 = 0) -> SnapshotBox {
        let scene = doc.scenes[doc.activeScene]

        // ---- colours: resolve A, then B = A overlaid with paramsB's set fields ----
        var colours = [SnapColour](repeating: SnapColour(), count: Snap.colours)
        for (i, colour) in doc.colours.prefix(Snap.colours).enumerated() {
            var sc = SnapColour()
            sc.outChannel = UInt8(max(0, min(16, colour.outChannel)))
            sc.transpose = Int8(max(-24, min(24, colour.transpose)))
            sc.morph = max(0, min(1, colour.morph))
            sc.a = resolve(colour.paramsA, type: colour.type, fallback: nil)
            sc.b = resolve(colour.paramsB, type: colour.type, fallback: sc.a)   // sparse B inherits from A
            colours[i] = sc
        }

        // ---- cells ----
        var cells = [SnapCell](repeating: SnapCell(), count: Snap.cols * Snap.rows)
        for c in 0..<Snap.cols {
            for r in 0..<Snap.rows {
                guard c < scene.cells.count, r < scene.cells[c].count,
                      let cell = scene.cells[c][r],
                      let colourIndex = colourIDs.firstIndex(of: cell.colourID) else { continue }
                var sc = SnapCell()
                sc.colourIndex = Int8(colourIndex)
                sc.stack = cell.stack
                sc.srcMix = cell.srcMix
                sc.alt = cell.alt
                sc.bypassed = cell.bypassed
                sc.muted = cell.muted
                sc.busMask = cell.buses.reduce(0) { $0 | (1 << $1.cable) }
                cells[c * Snap.rows + r] = sc
            }
        }

        // ---- LEGATO run starts (§3.5/§7 v2.4): same colour + same ROW + contiguous COLUMNS.
        //      Wiring/perform state irrelevant to run identity (§1.1); computed for every cell.
        for r in 0..<Snap.rows {
            var runStart = -1
            var runColour: Int8 = -1
            for c in 0..<Snap.cols {
                let idx = c * Snap.rows + r
                let ci = cells[idx].colourIndex
                if ci >= 0 {
                    if ci != runColour { runStart = c; runColour = ci }
                    cells[idx].runStartColumn = Int8(runStart)
                } else {
                    runStart = -1; runColour = -1
                }
            }
        }

        return SnapshotBox(generation: generation,
                           stepBeats: scene.stepRate.beats,
                           swing: Double(max(50, min(75, scene.swing))),
                           morphMaster: max(0, min(1, doc.morphMaster)),
                           colours: colours,
                           cells: cells)
    }

    // Map document params → flat indices. `fallback` = A-state for sparse-B inheritance.
    private static func resolve(_ p: ColourParams, type: ProcessorType, fallback: SnapParams?) -> SnapParams {
        var out = fallback ?? SnapParams()
        out.type = type
        if let v = p.pattern { out.patternIndex = UInt8(ArpPattern.allCases.firstIndex(of: v) ?? 0) }
        if let v = p.rate { out.rateIndex = Int8(ArpRate.allCases.firstIndex(of: v) ?? 3) }
        if let v = p.octaves { out.octaves = UInt8(max(1, min(4, v))) }
        if let v = p.gate { out.gate = max(0.05, min(1, v)) }
        if let v = p.phase { out.phase = v }
        if let v = p.count { out.count = UInt8(max(2, min(8, v))) }
        if let v = p.ramp { out.ramp = max(0, min(1, v)) }
        if let v = p.passes {
            out.passMask = 0
            for (i, on) in v.prefix(4).enumerated() where on { out.passMask |= UInt8(1 << i) }
        }
        if let v = p.strumDir { out.strumDir = v }
        if let v = p.spread { out.spread = max(0, min(1, v)) }
        if let v = p.curve { out.curve = max(-1, min(1, v)) }
        if let v = p.velTilt { out.velTilt = max(-1, min(1, v)) }
        if let v = p.probability { out.probability = max(0, min(1, v)) }
        return out
    }
}

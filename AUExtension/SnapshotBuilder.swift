//  SnapshotBuilder.swift
//  MidiSpark — document → SnapshotBox, on the UI thread (spec v2.8 §7).
//  The builder resolves everything the render thread must never compute:
//  paramsB merged over paramsA, enum → index mapping, LEGATO run starts.

import Foundation

enum SnapshotBuilder {

    static func build(from doc: PluginState, generation: UInt64 = 0) -> SnapshotBox {
        let scene = doc.activeSceneState   // MULTI-SCENE: bounds-safe active scene (never an out-of-range crash)

        // ---- colours: resolve A (procA); B = this Colour's OWN procB (delta item 8, two-processor model).
        //      typeB == nil ⇒ B-less ⇒ b = a, tier none. paramsB is resolved with fallback A, so a SPARSE
        //      procB inherits A's fields. tier gates render glide (full = same type) vs flip (swap). The old
        //      partner-Colour lookup (altColour) retires — it stays a decode-only legacy key for migration. ----
        var colours = [SnapColour](repeating: SnapColour(), count: Snap.colours)
        for (i, colour) in doc.colours.prefix(Snap.colours).enumerated() {
            var sc = SnapColour()
            sc.transpose = Int8(max(-24, min(24, colour.transpose)))   // single value — both faces share A's transpose (v1)
            sc.morph = max(0, min(1, colour.morph))
            sc.on = colour.onResolved   // delta §9 item 1: carry the ON assignments to the render (nil → unassigned)
            sc.a = resolve(colour.paramsA, type: colour.type, fallback: nil)
            if let tb = colour.typeB {
                sc.b = resolve(colour.paramsB, type: tb, fallback: sc.a)
                sc.tier = morphTier(selfType: colour.type, partner: tb)
            } else {
                sc.b = sc.a
                sc.tier = .none
            }
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
                sc.alt = cell.alt
                sc.bypassed = cell.bypassed
                sc.muted = cell.muted
                sc.busMask = cell.buses.reduce(0) { $0 | (1 << $1.cable) }
                sc.chordSplit = cell.chordSplitResolved         // §cell-edit D: the source-note split (ALL default)
                let vw = cell.velWindowResolved                 // §cell-edit D: the velocity window (1…127 default)
                sc.velFloor = UInt8(max(1, min(127, vw.floor))); sc.velCeil = UInt8(max(1, min(127, vw.ceil)))
                // v3.0 (delta §1): resolve the input reference — inputRow if that row is occupied and
                // not self, else MIDI IN. Occupancy checked here; the muted-parent reroute is runtime.
                if let ir = cell.inputRow, ir != r, ir >= 0, ir < Snap.rows,
                   ir < scene.cells[c].count, scene.cells[c][ir] != nil {
                    sc.resolvedParent = Int8(ir)
                }
                // delta §9 item 11: a MIDI-IN cell's source filter comes from the RECEIVER it subscribes
                // to (channel, or match-nothing if the receiver is muted); with no receivers (or a row
                // ref) fall back to the legacy per-cell filter. resolvedReceiver drives the UI band later.
                if let recs = doc.receivers, let ri = cell.inputReceiver, ri >= 0, ri < recs.count {
                    sc.resolvedReceiver = Int8(ri)
                    sc.inputChannel = recs[ri].muted ? Snap.mutedSourceFilter
                                                     : UInt8(max(0, min(16, recs[ri].channel)))
                    sc.inputCableMask = UInt8(recs[ri].cableResolved & 0b1111)   // §item 11 INPUT CABLES
                } else {
                    sc.inputChannel = UInt8(max(0, min(16, cell.inputChannel)))   // legacy / no receivers
                }
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

        // v3.0 (delta §7): per-bus stamp channels A–D, clamped 1–16, defaulted if the doc is short.
        var busCh = [UInt8](repeating: 0, count: 4)
        for i in 0..<4 {
            let v = i < doc.busChannels.count ? doc.busChannels[i] : (i + 1)
            busCh[i] = UInt8(max(1, min(16, v)))
        }
        // delta §6a: enable mask (nil/old docs ⇒ all enabled — the loader default).
        var busEnabledMask: UInt8 = 0
        for (i, on) in doc.busEnabledResolved.enumerated() where on { busEnabledMask |= 1 << UInt8(i) }
        // delta §6a CLAIM v2: the claim MASK (from claimMask, or derived from the legacy single field) + the
        // per-claimant LEAK % (0 = full suppression = v1).
        let claimMask = doc.claimMaskResolved
        let claimLeak = doc.claimLeakResolved.map { UInt8($0) }
        // delta §9 item 11: receiver channel filters (0 = OMNI, 1–16) — for input metering attribution.
        // A MUTED receiver resolves to the match-nothing filter (like a muted cell) so metering goes dark AND
        // the R1 passthrough gate blocks it (mute ruling 2026-07-26) — one representation, both consumers.
        let recvCh = doc.receiversResolved.map {
            $0.muted ? Snap.mutedSourceFilter : UInt8(max(0, min(16, $0.channel)))
        }
        let recvCable = doc.receiversResolved.map { UInt8($0.cableResolved & 0b1111) }   // §item 11 INPUT CABLES
        // TWO LATCH MODES: pack the per-receiver ADD flag into a mask (bit i = receiver i toggles, not replaces).
        var latchAddMask: UInt8 = 0
        for (i, r) in doc.receiversResolved.enumerated() where i < 4 && r.latchAddResolved { latchAddMask |= 1 << UInt8(i) }

        return SnapshotBox(generation: generation,
                           stepBeats: scene.stepRate.beats,
                           swing: Double(max(50, min(75, scene.swing))),
                           morphMaster: max(0, min(1, doc.morphMaster)),
                           colours: colours,
                           cells: cells,
                           busChannels: busCh,
                           busEnabledMask: busEnabledMask,
                           claimMask: claimMask,
                           claimLeak: claimLeak,
                           flattenMask: doc.flattenMask ?? 0,
                           flattenAmount: doc.flattenAmountResolved.map { UInt8($0) },
                           altMask: doc.altMask ?? 0,
                           altCount: doc.altCountResolved.map { UInt8($0) },
                           masterKey: Int8(scene.masterKeyResolved),
                           masterMute: doc.masterMute ?? false,
                           thruReceiver: Int8(doc.thruReceiverResolved),
                           receiverChannels: recvCh,
                           receiverCables: recvCable,
                           latchAddMask: latchAddMask)
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
        if let v = p.harmIntervals {
            func clampInt(_ i: Int) -> Int8 { Int8(max(-24, min(24, i))) }
            out.harmIntervals = (clampInt(v.count > 0 ? v[0] : 0),
                                 clampInt(v.count > 1 ? v[1] : 0),
                                 clampInt(v.count > 2 ? v[2] : 0))
        }
        if let v = p.harmVelScale { out.harmVelScale = max(0.1, min(1, v)) }
        return out
    }
}

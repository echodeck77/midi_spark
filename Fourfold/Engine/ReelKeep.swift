//  ReelKeep.swift — REEL redesign Phase 4 (keep + export), slice 4a: the pure KEEP model + its naming and list ops (Foundation-only, in the FourfoldTests target).
//  A KEEP is a named tape range the user marked to export, stored WITH the session (`PluginState.reelKeeps`). It is NOT render data — the engine never reads it — so it is never threaded into the snapshot and never moves the golden.
//  Beats are session-absolute. Auto-names reuse the existing `reelExportStamp` (Derivations.swift). The beat-range EXPORT itself is slice 4b (`ReelTapeAdapter`), the UI slice 4c (`FourfoldReel`).

import Foundation

struct ReelKeep: Codable, Equatable {
    var startBeat: Double
    var endBeat: Double
    var name: String
    var spanBeats: Double { max(0, endBeat - startBeat) }
}

/// The 1-based bar label for a keep's range, e.g. "5–12" (or "5" for one bar).
func reelKeepBarLabel(startBeat: Double, endBeat: Double, beatsPerBar: Double) -> String {
    let bpb = max(0.0001, beatsPerBar)
    let b0 = Int(startBeat / bpb) + 1
    let n = max(1, Int((max(0, endBeat - startBeat) / bpb).rounded()))
    return n == 1 ? "\(b0)" : "\(b0)\u{2013}\(b0 + n - 1)"
}

/// A keep's auto name: "Keep · bars 5–12 · 14-52-07" — the time keeps two keeps of the same bars apart.
func reelKeepName(startBeat: Double, endBeat: Double, beatsPerBar: Double, at date: Date, timeZone: TimeZone = .current) -> String {
    let stamp = reelExportStamp(date, timeZone: timeZone)                        // "YYYY-MM-DD HH-MM-SS"
    let time = stamp.split(separator: " ").last.map(String.init) ?? stamp        // HH-MM-SS
    return "Keep \u{b7} bars \(reelKeepBarLabel(startBeat: startBeat, endBeat: endBeat, beatsPerBar: beatsPerBar)) \u{b7} \(time)"
}

/// Add a keep for `[startBeat, endBeat]` with an auto name. An empty range is ignored; a range within half a bar of an existing keep (both ends) is treated as a duplicate and dropped.
func reelAddKeep(_ keeps: [ReelKeep], startBeat: Double, endBeat: Double, beatsPerBar: Double, at date: Date) -> [ReelKeep] {
    guard endBeat > startBeat else { return keeps }
    let eps = max(0.0001, beatsPerBar) / 2
    if keeps.contains(where: { abs($0.startBeat - startBeat) < eps && abs($0.endBeat - endBeat) < eps }) { return keeps }
    return keeps + [ReelKeep(startBeat: startBeat, endBeat: endBeat, name: reelKeepName(startBeat: startBeat, endBeat: endBeat, beatsPerBar: beatsPerBar, at: date))]
}
/// Remove the keep at `index` (no-op if out of range).
func reelRemoveKeep(_ keeps: [ReelKeep], at index: Int) -> [ReelKeep] {
    guard index >= 0, index < keeps.count else { return keeps }
    var k = keeps; k.remove(at: index); return k
}

/// The export FILENAME for a keep: "Fourfold 2026-11-16 14-52-07 bars 5–12 <label>.mid" (`label` = All / A / B / …). Reuses `reelExportStamp`; `reelUniqueFileName` (Derivations) still de-dupes on disk.
func reelKeepExportFileName(stamp: String, startBeat: Double, endBeat: Double, beatsPerBar: Double, label: String) -> String {
    "Fourfold \(stamp) bars \(reelKeepBarLabel(startBeat: startBeat, endBeat: endBeat, beatsPerBar: beatsPerBar)) \(label).mid"
}

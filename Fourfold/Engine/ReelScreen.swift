//  ReelScreen.swift — REEL redesign Phase 3 (the new screen), slice 3a: the PURE layer (Foundation + CoreGraphics, in the FourfoldTests target).
//  Three shapes of ONE tape — overview (whole session, stacked by lane) → tape (a window of bars, snapping selection) → close-up (the selection as a piano roll) — plus a control bar and a LIVE/TAPE pill.
//  Everything here is a pure function of the view size, the session length and the selection: the layout frames, the shape choice, the selection/snap/zoom maths, the x↔beat mapping, the overview density and the ×n repeat
//  brackets. The SwiftUI views (slice 3b) paint these and nothing else. GEOMETRY IS DEVICE-OWED — every number lives in `ReelScreenMetrics`, named and tunable; the three shapes follow `Docs/reel-redesign-plan.md`'s mockup.

import Foundation
import CoreGraphics

// MARK: - the three shapes

/// `wide` — a roomy landscape (the standalone app, a big host): overview on top, the tape strip, the close-up, a control bar.
/// `tall` — portrait / narrow-but-tall: the same, stacked, the close-up taking the slack. `small` — the AUM plug-in window
/// (short): NO tape strip (the plan's §"small"); the overview selects directly and the keeps collapse to one button.
enum ReelScreenShape: Equatable { case wide, tall, small }

func reelScreenShape(size: CGSize) -> ReelScreenShape {
    if size.height < ReelScreenMetrics.smallMaxHeight { return .small }         // a short plug-in strip, whatever its width
    if size.width < ReelScreenMetrics.tallMaxWidth && size.height >= size.width { return .tall }
    return size.width >= size.height ? .wide : .tall
}

enum ReelScreenMetrics {   // all device-owed; named so a device pass can retune without touching logic
    static let smallMaxHeight: CGFloat = 340     // at or below this height ⇒ `small` (no tape strip)
    static let tallMaxWidth: CGFloat = 560       // narrower than this (and taller than wide) ⇒ `tall`
    static let margin: CGFloat = 16
    static let gap: CGFloat = 12
    static let controlBarH: CGFloat = 56
    static let pillW: CGFloat = 96, pillH: CGFloat = 30
    static let overviewH: CGFloat = 72           // the stacked-by-lane whole-session band (wide/tall)
    static let overviewSmallH: CGFloat = 96      // `small`: the overview is the only selectable surface, so it is taller
    static let tapeH: CGFloat = 132              // the bar-ruler tape strip (wide/tall only)
    static let minCloseUpH: CGFloat = 80         // a close-up below this is drawn at the formula value and flagged (a floor, not a clamp)
    static let defaultWindowBars: Double = 48    // the tape window spans ~48 bars (the plan's figure)
    static let minWindowBars: Double = 4, maxWindowBars: Double = 256
    static let defaultKeepBars: Double = 8       // Keep N bars default (plan §Decisions)
}

// MARK: - the layout

struct ReelScreenLayout: Equatable {
    var shape: ReelScreenShape
    var size: CGSize
    var overview: CGRect       // the whole-session band (always present)
    var tape: CGRect           // the bar-window strip (.zero in `small`)
    var closeUp: CGRect        // the selection piano roll
    var controlBar: CGRect     // the transport + keep + export row
    var pill: CGRect           // the LIVE/TAPE pill (top-trailing of the overview)
    var hasTape: Bool { tape.width > 0 && tape.height > 0 }
    /// A floor was crossed: the close-up is shorter than `minCloseUpH` — the view still draws at these frames (nothing is hidden), it is a signal to retune on device.
    var belowFloor: Bool { closeUp.height < ReelScreenMetrics.minCloseUpH }
}

func reelScreenLayout(size: CGSize) -> ReelScreenLayout {
    typealias M = ReelScreenMetrics
    let shape = reelScreenShape(size: size)
    let x = M.margin, w = max(0, size.width - 2 * M.margin)
    let top = M.margin, bottomBarTop = max(top, size.height - M.margin - M.controlBarH)
    let controlBar = CGRect(x: x, y: bottomBarTop, width: w, height: M.controlBarH)
    let pill = CGRect(x: size.width - M.margin - M.pillW, y: top, width: M.pillW, height: M.pillH)
    switch shape {
    case .small:
        // No tape strip: the overview is the selectable surface; the close-up fills the rest.
        let ovY = top, ovH = M.overviewSmallH
        let cuY = ovY + ovH + M.gap
        let cuH = max(1, bottomBarTop - M.gap - cuY)
        return ReelScreenLayout(shape: shape, size: size,
                                overview: CGRect(x: x, y: ovY, width: w, height: ovH),
                                tape: .zero,
                                closeUp: CGRect(x: x, y: cuY, width: w, height: cuH),
                                controlBar: controlBar, pill: pill)
    case .wide, .tall:
        let ovY = top, ovH = M.overviewH
        let tpY = ovY + ovH + M.gap, tpH = M.tapeH
        let cuY = tpY + tpH + M.gap
        let cuH = max(1, bottomBarTop - M.gap - cuY)
        return ReelScreenLayout(shape: shape, size: size,
                                overview: CGRect(x: x, y: ovY, width: w, height: ovH),
                                tape: CGRect(x: x, y: tpY, width: w, height: tpH),
                                closeUp: CGRect(x: x, y: cuY, width: w, height: cuH),
                                controlBar: controlBar, pill: pill)
    }
}

// MARK: - the tape window (pan / zoom) + x↔beat mapping

/// The visible span of the tape strip: `bars` bars starting at `startBeat`. Panned/zoomed by gestures, always clamped so it stays inside [0, sessionEndBeat] and within the bar limits.
struct ReelTapeWindow: Equatable { var startBeat: Double; var bars: Double }

func reelClampWindow(_ win: ReelTapeWindow, sessionEndBeat: Double, beatsPerBar: Double) -> ReelTapeWindow {
    typealias M = ReelScreenMetrics
    let bpb = max(0.0001, beatsPerBar)
    let sessionBars = max(M.minWindowBars, sessionEndBeat / bpb)
    let bars = min(max(M.minWindowBars, win.bars), min(M.maxWindowBars, sessionBars))
    let span = bars * bpb
    let start = min(max(0, win.startBeat), max(0, sessionEndBeat - span))
    return ReelTapeWindow(startBeat: start, bars: bars)
}
/// The beat under x within the tape rect (clamped to the window).
func reelTapeBeatAtX(_ x: CGFloat, tape: CGRect, window: ReelTapeWindow, beatsPerBar: Double) -> Double {
    guard tape.width > 0 else { return window.startBeat }
    let frac = min(1, max(0, Double((x - tape.minX) / tape.width)))
    return window.startBeat + frac * window.bars * max(0.0001, beatsPerBar)
}
/// The x for a beat within the tape rect (not clamped — a beat outside the window maps outside the rect, so the view can cull).
func reelTapeXAtBeat(_ beat: Double, tape: CGRect, window: ReelTapeWindow, beatsPerBar: Double) -> CGFloat {
    let span = window.bars * max(0.0001, beatsPerBar)
    guard span > 0 else { return tape.minX }
    return tape.minX + CGFloat((beat - window.startBeat) / span) * tape.width
}

// MARK: - the selection (snaps to bar lines)

/// The chosen range on the tape, in beats. A keep/export/replay reads this. Always `start ≤ end`.
struct ReelSelection: Equatable { var startBeat: Double; var endBeat: Double
    var spanBeats: Double { max(0, endBeat - startBeat) }
}
/// Snap a beat to the nearest bar line.
func reelSnapToBar(beat: Double, beatsPerBar: Double) -> Double {
    let bpb = max(0.0001, beatsPerBar)
    return (beat / bpb).rounded() * bpb
}
/// A fresh selection of `bars` bars ending at `atBeat` (snapped), clamped to [0, sessionEndBeat] — the "Keep N bars" grab, default back from the live edge.
func reelSelectionBars(endingAt atBeat: Double, bars: Double, beatsPerBar: Double, sessionEndBeat: Double) -> ReelSelection {
    let bpb = max(0.0001, beatsPerBar)
    let end = min(reelSnapToBar(beat: atBeat, beatsPerBar: bpb), max(0, reelSnapToBar(beat: sessionEndBeat, beatsPerBar: bpb)))
    let start = max(0, end - max(1, bars) * bpb)
    return ReelSelection(startBeat: start, endBeat: max(start + bpb, end))
}
/// Drag a selection handle (`.start` / `.end`) to `beat`, snapped, keeping a ≥ 1-bar span and staying in [0, sessionEndBeat].
enum ReelSelectionHandle { case start, end }
func reelMoveHandle(_ sel: ReelSelection, _ handle: ReelSelectionHandle, toBeat beat: Double, beatsPerBar: Double, sessionEndBeat: Double) -> ReelSelection {
    let bpb = max(0.0001, beatsPerBar)
    let b = min(max(0, reelSnapToBar(beat: beat, beatsPerBar: bpb)), max(0, reelSnapToBar(beat: sessionEndBeat, beatsPerBar: bpb)))
    switch handle {
    case .start: return ReelSelection(startBeat: min(b, sel.endBeat - bpb), endBeat: sel.endBeat)
    case .end:   return ReelSelection(startBeat: sel.startBeat, endBeat: max(b, sel.startBeat + bpb))
    }
}

// MARK: - the overview (whole session, stacked by lane) + the ×n repeat brackets

/// Per lane (0…3 = outputs A–D), per time-bin, a 0…1 activity level — the stacked overview's heights. Input: the tape's drawable notes
/// (`cable` 1…4, `start`/`end` in session beats), the session end and the bin count. A note adds to every bin its span touches; each lane
/// is normalised to its own peak (so a quiet lane still reads). Pure — the view bins the tape once and hands it here.
func reelOverviewDensity(notes: [ReelDeck.Note], sessionEndBeat: Double, bins: Int) -> [[Double]] {
    let lanes = FourfoldPorts.outputCount
    var out = [[Double]](repeating: [Double](repeating: 0, count: max(1, bins)), count: lanes)
    guard bins > 0, sessionEndBeat > 0 else { return out }
    let per = sessionEndBeat / Double(bins)
    for n in notes {
        let lane = Int(n.cable) - 1
        guard lane >= 0, lane < lanes, per > 0 else { continue }
        let lo = max(0, min(bins - 1, Int(n.start / per)))
        let hi = max(0, min(bins - 1, Int(max(n.start, n.end - 1e-9) / per)))
        for b in lo...hi { out[lane][b] += 1 }
    }
    for lane in 0..<lanes { let peak = out[lane].max() ?? 0; if peak > 0 { for b in 0..<out[lane].count { out[lane][b] /= peak } } }
    return out
}

/// One content fingerprint per bar (note-ONs only: pitch + lane + the sixteenth within the bar), so identical bars hash equal and a run of
/// them becomes one ×n bracket (replacing REMOVE DUPLICATES). `bars` is how many bars from beat 0 to fingerprint.
func reelBarFingerprints(notes: [ReelDeck.Note], beatsPerBar: Double, bars: Int) -> [UInt64] {
    let bpb = max(0.0001, beatsPerBar)
    var h = [UInt64](repeating: 0xcbf2_9ce4_8422_2325, count: max(0, bars))    // FNV-1a basis per bar
    for n in notes where n.vel > 0 {
        let bar = Int(n.start / bpb)
        guard bar >= 0, bar < h.count else { continue }
        let within = n.start - Double(bar) * bpb
        let sixteenth = UInt64(max(0, (within / bpb * 16).rounded()))           // timing to a 16th, float-noise-proof
        var x = h[bar]
        x = (x ^ (sixteenth &+ 1)) &* 0x100_0000_01b3
        x = (x ^ (UInt64(n.cable) << 8 | UInt64(n.note))) &* 0x100_0000_01b3
        h[bar] = x
    }
    return h
}
/// Runs of two or more adjacent bars that fingerprint equal → an ×n bracket over `[firstBar, firstBar+count)`. A lone bar yields no bracket.
struct ReelRepeatBracket: Equatable { var firstBar: Int; var count: Int }
func reelRepeatBrackets(fingerprints: [UInt64]) -> [ReelRepeatBracket] {
    var out: [ReelRepeatBracket] = []
    var i = 0
    while i < fingerprints.count {
        var j = i + 1
        while j < fingerprints.count, fingerprints[j] == fingerprints[i], fingerprints[i] != 0xcbf2_9ce4_8422_2325 { j += 1 }
        if j - i >= 2 { out.append(ReelRepeatBracket(firstBar: i, count: j - i)) }
        i = j > i ? j : i + 1
    }
    return out
}

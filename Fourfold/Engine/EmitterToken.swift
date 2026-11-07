//  EmitterToken.swift — EMITTER TOKEN ferry (2026-11-07): the ONE emitter drawing, as pure functions (Foundation + CoreGraphics only, in the FourfoldTests target).
//
//  Every emitter and routing circle in the app is this token: a disc, a ring with a gap at 12 o'clock holding a small key square, the letter centred — at three sizes (22 / 28 / 36). The geometry (§1) and the look (§2) are pure
//  here; the SwiftUI `View` and the `GraphicsContext` draw helper in `Fourfold/UI/EmitterTokenView.swift` are the two paint sites that read ONE spec (a View and a Canvas cannot share one draw call — the rank-chip precedent, §2.4).
//
//  Emitters are NEUTRAL (white ring live, grey unused, a lane-coloured FLARE while a lane plays through, dashed grey when muted) — lane colour is signal, never identity. Routing circles keep their lane colour. Colour that comes from
//  the lane is an `EuclideousTokenInk.lane(alpha)`; the paint site supplies the actual lane Color. Fixed colours are `.hex`.

import Foundation
import CoreGraphics

// MARK: - §1 geometry

/// The three token sizes (overall diameter D): the MIX A–D routing circle (22), the RATCH / RIFF / NOTES disc (28), the MIX emitter (36).
enum EuclideousEmitterTokenSize: Equatable { case d22, d28, d36 }

/// §1.1–1.3: every measurement the token draws, in a D×D box. The ring is on radius `D/2 − w/2`; the gap, g wide at the ring's centre line, is centred on 12 o'clock; the key (k on a side, r0.5) sits in the gap, its top edge 1 pt below the ring's inner edge.
struct EuclideousEmitterTokenGeom: Equatable {
    var diameter: CGFloat        // D
    var ringWidth: CGFloat       // w
    var ringRadius: CGFloat      // D/2 − w/2 (the stroke's centre line)
    var letterSize: CGFloat
    var gap: CGFloat             // g, the gap's width at the ring's centre line
    var gapAngle: CGFloat        // g ÷ ringRadius, radians — the gap's angular span, centred on 12 o'clock
    var keySide: CGFloat         // k
    var keyRadius: CGFloat       // 0.5
    var keyRect: CGRect          // in the D×D box
    var center: CGPoint          // D/2, D/2
}

func euclideousEmitterTokenGeom(_ size: EuclideousEmitterTokenSize) -> EuclideousEmitterTokenGeom {
    let d: CGFloat, w: CGFloat, letter: CGFloat, g: CGFloat, k: CGFloat
    switch size {
    case .d22: d = 22; w = 2; letter = 8;  g = 4; k = 2.5
    case .d28: d = 28; w = 2; letter = 11; g = 5; k = 3
    case .d36: d = 36; w = 3; letter = 14; g = 6; k = 3.5
    }
    let ringRadius = d / 2 - w / 2
    // the ring's inner edge sits at radius (D/2 − w) from the centre → at 12 o'clock it is `w` below the box top; the key's top edge is 1 pt below that.
    let keyTop = w + 1
    let keyRect = CGRect(x: d / 2 - k / 2, y: keyTop, width: k, height: k)
    return EuclideousEmitterTokenGeom(diameter: d, ringWidth: w, ringRadius: ringRadius, letterSize: letter,
                                      gap: g, gapAngle: g / ringRadius, keySide: k, keyRadius: 0.5,
                                      keyRect: keyRect, center: CGPoint(x: d / 2, y: d / 2))
}

// MARK: - §2 look

/// An ink either resolves to a fixed colour at an alpha, or to the lane/output colour at an alpha (the paint site supplies the lane Color), or draws nothing.
enum EuclideousTokenInk: Equatable {
    case none
    case hex(UInt32, Double)
    case lane(Double)
}

/// The token's look. The base look (live / unused / muted / routed / not-routed / routed-muted) is fully described; PLAYING is the live base plus a `flare` the paint site draws as a lane glow + wash + lane ring/key (§2.1 "fades back to live").
struct EuclideousEmitterTokenPaint: Equatable {
    var disc: EuclideousTokenInk       // §1.2 the disc inside the ring; .none = no disc (the surface shows through — muted / routed looks)
    var ring: EuclideousTokenInk
    var ringWidth: CGFloat
    var dashed: Bool                   // a dashed ring keeps the gap (§1.3); 3 on 3 off
    var key: EuclideousTokenInk        // the key always takes the ring's colour (§1.3)
    var letter: EuclideousTokenInk
    var flare: Double                  // 0 = none; >0 = the playing flare's activity (§2.1)
}

/// The states one look function serves (§2.4). Emitter: live / unused / playing / muted. Routing: routed / notRouted / routedMuted.
enum EuclideousEmitterTokenState: Equatable {
    case live, unused, playing(Double), muted
    case routed, notRouted, routedMuted
}

/// §2.1 the playing flare's fixed overlays, drawn over the live base at the flare activity: a 6 pt lane40 glow under the ring, a lane20 wash over the disc, the ring thickened to w+1 in lane100, the key lane100. (Mirrors the RATCH disc's flare.)
enum EuclideousEmitterTokenFlare {
    static let glowWidth: CGFloat = 6
    static let glowAlpha: Double = 0.4
    static let washAlpha: Double = 0.2
    static let ringDelta: CGFloat = 1
    /// The muted / routed-muted dash (§2.1, §2.3): 3 on, 3 off, butt caps, starting at a gap edge.
    static let dash: [CGFloat] = [3, 3]
}

/// §2 the one look function. Colours exactly as §2.1 (emitter) and §2.3 (routing), with two deliberate source-wins deviations from the ferry, reported in the findings doc:
///  • routed disc fill is lane @ 20 % (source `EuclideousPartOutDiscArt`), not the ferry's 18 %;
///  • not-routed ring/key is #3A3E47 (source), not the ferry's #4A4E57.
func euclideousEmitterTokenPaint(_ state: EuclideousEmitterTokenState, size: EuclideousEmitterTokenSize) -> EuclideousEmitterTokenPaint {
    let w = euclideousEmitterTokenGeom(size).ringWidth
    switch state {
    case .live:
        return EuclideousEmitterTokenPaint(disc: .hex(0x2A2D34, 1), ring: .hex(0xDFE3EA, 1), ringWidth: w, dashed: false, key: .hex(0xDFE3EA, 1), letter: .hex(0xF2F4F7, 1), flare: 0)
    case .unused:
        return EuclideousEmitterTokenPaint(disc: .hex(0x2A2D34, 1), ring: .hex(0x3A3E47, 1), ringWidth: w, dashed: false, key: .hex(0x3A3E47, 1), letter: .hex(0x8A909A, 1), flare: 0)
    case .muted:
        // §2.1: no disc (the surface shows through); ring 2 pt #5C626C dashed; key #5C626C; letter #5C626C. Muted never plays.
        return EuclideousEmitterTokenPaint(disc: .none, ring: .hex(0x5C626C, 1), ringWidth: 2, dashed: true, key: .hex(0x5C626C, 1), letter: .hex(0x5C626C, 1), flare: 0)
    case .playing(let a):
        var p = euclideousEmitterTokenPaint(.live, size: size)
        p.flare = max(0, min(1, a))
        return p
    case .routed:
        return EuclideousEmitterTokenPaint(disc: .lane(0.2), ring: .lane(1), ringWidth: w, dashed: false, key: .lane(1), letter: .hex(0xF2F4F7, 1), flare: 0)
    case .notRouted:
        return EuclideousEmitterTokenPaint(disc: .none, ring: .hex(0x3A3E47, 1), ringWidth: w, dashed: false, key: .hex(0x3A3E47, 1), letter: .hex(0x8A909A, 1), flare: 0)
    case .routedMuted:
        // §2.3: no disc; ring lane100 @ 45 % dashed; key lane100 @ 45 %; letter #8A909A.
        return EuclideousEmitterTokenPaint(disc: .none, ring: .lane(0.45), ringWidth: w, dashed: true, key: .lane(0.45), letter: .hex(0x8A909A, 1), flare: 0)
    }
}

/// §3.4 / §2.1: which EMITTER look applies (MIX column, RATCH toggle) — muted wins, then a non-zero activity plays, then live if anything routes to it, else unused.
func euclideousEmitterTokenEmitterState(muted: Bool, activity: Double, anyRouted: Bool) -> EuclideousEmitterTokenState {
    if muted { return .muted }
    if activity > 0 { return .playing(activity) }
    return anyRouted ? .live : .unused
}

/// §2.3: which ROUTING look applies (MIX A–D, RIFF / NOTES OUT). A not-routed circle ignores the output's mute.
func euclideousEmitterTokenRoutingState(routed: Bool, outputMuted: Bool) -> EuclideousEmitterTokenState {
    guard routed else { return .notRouted }
    return outputMuted ? .routedMuted : .routed
}

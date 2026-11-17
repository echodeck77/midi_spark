//  ReelHeaderIcon.swift
//  FOURFOLD REEL LINK (2026-10-23) — the tape icon that opens the REEL pass browser from Fourfold's UTILITIES group.
//  SwiftUI-only on purpose (GridUI seam rule). Whether the tape is rolling is decided by the caller (`d.playing && reelState != 2`, the 8×8 header's own rule); this file only draws it.
//
//  STYLE PASS 1 (2026-11-17) §5.3: the glyph is #B4BAC4 like every header icon, in EVERY state — the recording state
//  (the only state that showed red) now carries a 5 pt #F0475B dot at the top-trailing corner instead. The dot keeps
//  the old dot's opacity pulse (so recording is still noticed, §10) — the red glyph tint, the glow shadow and the
//  scale pulse are gone with the red. Size, frame and the caller's rule unchanged.

import SwiftUI

struct EuclideousReelIcon: View {
    let recording: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !recording || reduceMotion)) { tl in
            let p = (recording && !reduceMotion) ? abs(sin(tl.date.timeIntervalSinceReferenceDate * 2.4)) : 0.0
            ZStack(alignment: .topTrailing) {
                Image(systemName: "recordingtape").font(.system(size: 18, weight: .medium))   // §5.2 one weight
                    .foregroundColor(Color(hex: FourfoldStyle.label))
                if recording {
                    Circle().fill(Color(hex: FourfoldStyle.tapeDot))
                        .frame(width: FourfoldStyle.tapeDotSize, height: FourfoldStyle.tapeDotSize)
                        .opacity(0.7 + 0.3 * p).offset(x: 3, y: -1)
                }
            }
        }
    }
}

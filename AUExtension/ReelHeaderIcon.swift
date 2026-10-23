//  ReelHeaderIcon.swift
//  FOURFOLD REEL LINK (2026-10-23) — the tape icon that opens the REEL pass browser from Fourfold's UTILITIES group.
//  SwiftUI-only on purpose (GridUI seam rule). Whether the tape is rolling is decided by the caller (`d.playing && reelState != 2`, the 8×8 header's own rule); this file only draws it.

import SwiftUI

struct EuclideousReelIcon: View {
    let recording: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let red = Color(red: 0.95, green: 0.24, blue: 0.24)
    static let glow = Color(red: 0.98, green: 0.2, blue: 0.2)
    static let idle = Color(hex: 0x8A909A)   // the header's own `headerDim`

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !recording || reduceMotion)) { tl in
            let p = (recording && !reduceMotion) ? abs(sin(tl.date.timeIntervalSinceReferenceDate * 2.4)) : 0.0
            ZStack(alignment: .topTrailing) {
                Image(systemName: "recordingtape").font(.system(size: 18))
                    .foregroundColor(recording ? Self.red : Self.idle)
                    .scaleEffect(1.0 + 0.07 * p)
                    .shadow(color: Self.glow.opacity(recording ? 0.35 + 0.4 * p : 0), radius: 4)
                if recording {
                    Circle().fill(Self.glow).frame(width: 6, height: 6).opacity(0.7 + 0.3 * p).offset(x: 3, y: -1)
                }
            }
        }
    }
}

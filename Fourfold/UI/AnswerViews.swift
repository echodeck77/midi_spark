//  AnswerViews.swift
//  ANSWER ferry (2026-11-02): the leaf views of the ANSWER and POOL tabs that read the live status feed (`AnswerLiveModel`) — the CYCLE row's phase bar and the POOL tab's NOW row. They observe the model themselves, so a playhead moving at 30 Hz re-runs
//  these two views and nothing else on the page.

import SwiftUI

/// §4.2–§4.3: the phase bar — vertically centred in its column, inset 3 either side, 5 tall, radius 2.5, clipped; two equal halves 1.5 apart (phase A, then phase B) in the §4.3 colours; a 1.5-wide #F2F4F7 playhead at the cycle's progress, polled from
/// the status feed (with Reduce Motion it moves in quarter-unit steps — about once a beat). Transport stopped, or the lane not cycling: the playhead sits at 0. One VoiceOver element, "Phase", whose value names whose turn it is.
struct AnswerPhaseBarView: View {
    let lane: Int
    let line: EuclidLine
    let colours: [Color]
    let width: CGFloat
    let height: CGFloat
    let playing: Bool
    let reduceMotion: Bool
    @ObservedObject var live: AnswerLiveModel

    var body: some View {
        let st = live.status(lane: lane)
        let c = euclideousAnswerPhaseColours(lane: lane, line: line)
        let raw = (st.running && playing) ? st.progress : 0
        let p = reduceMotion ? euclideousAnswerPlayheadQuantised(raw, each: st.each) : raw
        let barW = max(1, width - 6)
        let half = max(0, (barW - 1.5) / 2)
        ZStack(alignment: .leading) {
            HStack(spacing: 1.5) {
                Rectangle().fill(colours[c.a % colours.count]).frame(width: half, height: 5)
                Rectangle().fill(colours[c.b % colours.count]).frame(width: half, height: 5)
            }
            .frame(width: barW, height: 5, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 2.5))
            Rectangle().fill(Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF7 / 255)).frame(width: 1.5, height: 5).offset(x: max(0, min(barW - 1.5, p * barW)))
        }
        .frame(width: barW, height: 5)
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Phase, lane \(lane + 1)")
        .accessibilityValue(euclideousAnswerPhaseSpoken(lane: lane, line: line, status: playing ? st : EuclideousAnswerLaneStatus()))
    }
}

/// POOL ferry 2.2: the NOW row's chips — eight rank chips (§5), ranks 1 to 8 left to right in eight equal columns sp3 apart, naming this lane's pool after CANON, FREEZE and SUSTAIN (the per-lane pool every part of the lane reads) with the NOTES keys'
/// own received / octave-copy looks; the lit bar marks the ranks the lane struck on its last hit. While FREEZE is holding, or SUSTAIN KEEP is holding with the pedal down, the chips draw at 60 %. One VoiceOver element, "Now", whose value
/// is the note names in rank order (or "empty"). Fixed-size data from the status feed; the model is observed here, not by the page.
struct PoolNowChipsView: View {
    let lane: Int
    let tint: Color
    let size: CGSize          // the whole row: eight chips and their gaps
    let frozen: Bool          // FREEZE is running (the page's own status)
    let spokenName: (Int, [UInt8]) -> String
    let name: (UInt8, [UInt8]) -> String
    @ObservedObject var live: AnswerLiveModel

    var body: some View {
        let st = live.pool(lane: lane)
        let sorted = st.notes.map { Int($0) }
        let chips = euclideousRankChips(sortedPool: sorted, litMask: st.playedRanks) { n in n >= 0 && n <= 127 ? name(UInt8(n), st.notes) : "\u{2013}" }
        let gap: CGFloat = 3
        let w = max(1, (size.width - gap * 7) / 8)
        HStack(spacing: gap) {
            ForEach(0..<8, id: \.self) { i in EuclideousRankChipView(spec: chips[i], accent: tint, size: CGSize(width: w, height: size.height)) }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
        .opacity(frozen || st.keepHolding ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now")
        .accessibilityValue(euclideousPoolNowSpoken(names: st.notes.isEmpty ? [] : (0..<8).compactMap { r in
            let ext = euclideousGlobalPoolExtended(sortedRaw: sorted)
            return r < ext.count ? spokenName(ext[r], st.notes) : nil
        }))
    }
}

/// POOL ferry 2.5: the PEDAL light — a DISPLAY, not a button: a 5 pt circle, sp4, then "PEDAL" in the mode buttons' heavy label face, centred together on the row's third column. Row on and the pedal down: lane100 fill, ink #15161A, circle
/// #15161A. Row on, pedal up: no fill, a 1 pt #3A3E47 border, text #AAB0BA, circle #4A4E57. Row off: the off look (#24262C, #7C828D, circle #4A4E57). One VoiceOver element, "Pedal", whose value is "down" or "up".
struct PoolPedalLightView: View {
    let lane: Int
    let rowOn: Bool
    let accent: Color
    let size: CGSize
    @ObservedObject var live: AnswerLiveModel

    var body: some View {
        let down = live.pool(lane: lane).pedalDown
        let look = euclideousPedalLook(rowOn: rowOn, pedalDown: down)
        let ink = Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x1A / 255)
        let text: Color = look == .down ? ink : (look == .up ? Color(red: 0xAA / 255, green: 0xB0 / 255, blue: 0xBA / 255) : Color(red: 0x7C / 255, green: 0x82 / 255, blue: 0x8D / 255))
        let dot: Color = look == .down ? ink : Color(red: 0x4A / 255, green: 0x4E / 255, blue: 0x57 / 255)
        HStack(spacing: 4) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Text("PEDAL").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5).foregroundColor(text).lineLimit(1)
        }
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: 7).fill(look == .down ? accent : (look == .off ? Color(red: 0x24 / 255, green: 0x26 / 255, blue: 0x2C / 255) : Color.clear)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(look == .up ? Color(red: 0x3A / 255, green: 0x3E / 255, blue: 0x47 / 255) : Color.clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pedal, lane \(lane + 1)")
        .accessibilityValue(euclideousPoolPedalSpoken(down: down))
    }
}

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
        .accessibilityLabel("Phase")
        .accessibilityValue(euclideousAnswerPhaseSpoken(lane: lane, line: line, status: playing ? st : EuclideousAnswerLaneStatus()))
    }
}

/// §10.3: the NOW row's chips — the notes this lane is choosing from right now (its pool after CANON and FREEZE: the per-lane pool every part of the lane reads), ascending, named as the SOURCES panel names a pool note, in the sources panel's held-chip look
/// (24 tall, 30 drawn, 9 pt heavy, radius 4, 4 apart) tinted with the lane's colour; as many as fit at the chip width, then "+n" in the reserved slot; an empty pool is one ghost chip. While FREEZE is holding the chips draw at 60 % (FREEZE's own running
/// look, its value at 60 %). One VoiceOver element, "Now", whose value is the note names. Fixed-size data from the status feed; the model is observed here, not by the page.
struct AnswerPoolNowView: View {
    let lane: Int
    let tint: Color
    let room: CGFloat
    let frozen: Bool
    let flatKey: Bool
    @ObservedObject var live: AnswerLiveModel

    var body: some View {
        let pool = live.pool(lane: lane)
        let names = pool.notes.map { euclideousNoteViewName($0, flatKey: flatKey) }
        let count = max(pool.count, names.count)
        let fit = euclideousMidiChipFit(room: room, count: count)
        HStack(spacing: 4) {
            if count == 0 {
                if room >= euclideousMidiChipW { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(red: 0x3A / 255, green: 0x3E / 255, blue: 0x47 / 255), lineWidth: 1).frame(width: euclideousMidiChipW, height: 24) }
            } else {
                ForEach(Array(names.prefix(fit.shown).enumerated()), id: \.offset) { _, name in
                    Text(name).font(.system(size: 9, weight: .heavy, design: .monospaced)).lineLimit(1)
                        .foregroundColor(Color(red: 0x0D / 255, green: 0x0F / 255, blue: 0x14 / 255))
                        .frame(minWidth: euclideousMidiChipW - 6, minHeight: 24).padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(tint))
                }
                if fit.showsOverflow {
                    Text("+\(count - fit.shown)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(red: 0x8A / 255, green: 0x90 / 255, blue: 0x9A / 255)).frame(width: euclideousMidiChipW)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: max(1, room), alignment: .leading)
        .opacity(frozen ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now")
        .accessibilityValue(count == 0 ? "empty" : (names.joined(separator: ", ") + (count > names.count ? ", and \(count - names.count) more" : "")))
    }
}

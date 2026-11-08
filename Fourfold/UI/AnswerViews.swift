//  AnswerViews.swift
//  ANSWER ferry (2026-11-02): the leaf views of the ANSWER and POOL tabs that read the live status feed (`AnswerLiveModel`) — the CYCLE row's phase bar and the INPUTS tab's NOW row. They observe the model themselves, so a playhead moving at 30 Hz re-runs
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

/// POOL ferry 2.2: the NOW row's chips — eight rank chips (§5), ranks 1 to 8 left to right in eight equal columns sp3 apart, naming this lane's pool after CANON (the per-lane pool every part of the lane reads) with the NOTES keys'
/// own received / octave-copy looks; the lit bar marks the ranks the lane struck on its last hit. One VoiceOver element, "Now", whose value
/// is the note names in rank order (or "empty"). Fixed-size data from the status feed; the model is observed here, not by the page.
struct PoolNowChipsView: View {
    let lane: Int
    let tint: Color
    let size: CGSize          // the whole row: eight chips and their gaps
    let spokenName: (Int, [UInt8]) -> String
    let name: (UInt8, [UInt8]) -> String
    @ObservedObject var live: AnswerLiveModel

    var body: some View {
        let st = live.pool(lane: lane)
        let sorted = st.notes.map { Int($0) }
        let chips = euclideousRankChips(sortedPool: sorted, litMask: st.playedRanks, sources: st.sources) { n in n >= 0 && n <= 127 ? name(UInt8(n), st.notes) : "\u{2013}" }
        let gap: CGFloat = 3
        let w = max(1, (size.width - gap * 7) / 8)
        HStack(spacing: gap) {
            ForEach(0..<8, id: \.self) { i in EuclideousRankChipView(spec: chips[i], accent: tint, size: CGSize(width: w, height: size.height), stackRank: true) }   // NOW: two rows — rank number over the assigned note (2026-11-08)
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, lane \(lane + 1)")   // the lane is part of the name: four cards carry a NOW row
        .accessibilityValue(euclideousPoolNowSpoken(names: st.notes.isEmpty ? [] : (0..<8).compactMap { r in
            let ext = euclideousGlobalPoolExtended(sortedRaw: sorted)
            guard r < ext.count else { return nil }
            let n = spokenName(ext[r], st.notes)
            return r < sorted.count && r < st.sources.count ? n + " " + EuclideousSourceColour.name(source: st.sources[r]) : n   // 7.6: a received note names its source ("A3 key, A sharp 3 MIDI"); a copy does not
        }))
    }
}

/// INPUTS ferry 3.4: the MIDI row's readout — 44 × 28, radius 6, #22252C, 12 pt heavy: in ROOT the lane's applied transpose (from the status feed: 0 unless the lane is ROOT with its MIDI IN chip on), otherwise a dim "–". Leaf-observed.
struct MidiRootReadoutView: View {
    let lane: Int
    let mode: MidiMode          // the lane's mode as the page has it (its own field, else the document's)
    let size: CGSize
    @ObservedObject var live: AnswerLiveModel

    var body: some View {
        let r = euclideousInputsRootReadout(mode: mode, t: live.pool(lane: lane).rootT)
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(red: 0x22 / 255, green: 0x25 / 255, blue: 0x2C / 255))
            Text(r.text).font(.system(size: 12, weight: .heavy, design: .monospaced)).lineLimit(1)
                .foregroundColor(r.bright ? Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF7 / 255) : Color(red: 0x5C / 255, green: 0x62 / 255, blue: 0x6C / 255))
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(r.spoken == nil)
        .accessibilityLabel(r.spoken.map { $0 + ", lane \(lane + 1)" } ?? "")   // four cards carry one: the lane is part of the name
    }
}

/// POOL ferry 6.2: the riff grid's note-label column — eight rank chips, rank 8 at the top and rank 1 at the bottom, each `cellH` tall and `labelW` wide with the grid's own row gap, naming the PICKED lane's pool through the NOTES keys' naming function
/// (received bright, octave copies dark, "–" for a rank with no note), the lit bar on the ranks that lane struck on its last hit. One VoiceOver element per chip, "Rank n, <note>". Observes the status feed itself.
struct RiffGridLabelColumnView: View {
    let lane: Int
    let tint: Color
    let cellH: CGFloat
    let labelW: CGFloat
    let gap: CGFloat
    let name: (UInt8, [UInt8]) -> String
    let spokenName: (Int, [UInt8]) -> String
    /// The picked lane's RIFF octave (−2…+2): the column names what that part will sound, not the pool before OCT (`euclideousRankLabelSoundingPitch`).
    var octave = 0
    @ObservedObject var live: AnswerLiveModel

    var body: some View {
        let st = live.pool(lane: lane)
        let sorted = st.notes.map { Int($0) }
        let extended = euclideousGlobalPoolExtended(sortedRaw: sorted)
        let chips = euclideousRankChips(sortedPool: sorted, litMask: st.playedRanks, sources: st.sources) { n in euclideousRankLabelSoundingPitch(n, octave: octave).map { name(UInt8($0), st.notes) } ?? "\u{2013}" }
        VStack(spacing: gap) {
            ForEach((1...8).reversed(), id: \.self) { rank in
                EuclideousRankChipView(spec: chips[rank - 1], accent: tint, size: CGSize(width: labelW, height: cellH))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel({ () -> String in
                        guard rank <= extended.count, let sounding = euclideousRankLabelSoundingPitch(extended[rank - 1], octave: octave) else { return "Rank \(rank), no note" }
                        return euclideousRankChipGridSpoken(rank: rank, note: spokenName(sounding, st.notes))
                    }())
            }
        }
        .frame(width: labelW)
    }
}

/// POOL ferry 6.3: the lane picker — four 7 pt circles in a 2 × 2 grid (lanes 1 2 over 3 4), centred in its blank: the picked lane's in its lane100 with a 1 pt lane100 ring 2 out from it, the others at 45 %. A tap anywhere in the blank steps to the
/// next lane; VoiceOver: adjustable, "Notes shown for", value "lane n".
struct RiffGridPickerView: View {
    let picked: Int
    let accents: [Color]
    let size: CGSize
    let step: (Int) -> Void     // +1 / −1

    private func dot(_ lane: Int) -> some View {
        let on = lane == picked
        let c = accents[lane % accents.count]
        return ZStack {
            Circle().fill(c.opacity(on ? 1 : 0.45)).frame(width: 7, height: 7)
            if on { Circle().stroke(c, lineWidth: 1).frame(width: 7 + 2 * 2 + 1, height: 7 + 2 * 2 + 1) }   // the ring: 2 pt clear of the circle
        }
        .frame(width: 7, height: 7)
    }
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) { dot(0); dot(1) }
            HStack(spacing: 7) { dot(2); dot(3) }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { step(1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notes shown for")
        .accessibilityValue(euclideousPickedLaneSpoken(picked))
        .accessibilityAdjustableAction { dir in step(dir == .increment ? 1 : -1) }
    }
}

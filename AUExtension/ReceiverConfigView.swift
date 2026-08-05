import SwiftUI

/// LAYOUT v2 — THE MIDI RECEIVERS TAB. Promoted out of the cog page (the per-door config is a working surface, not a
/// set-once rarity): four LENSES on one stream — the plugin hears every cable. Shape each door: channel (OMNI
/// default) · range · bypass destinations · MPE-merge, each with a live IN dot + an auto-detect MPE dot. The cog
/// keeps the true globals (MIDI OUTPUT · DISPLAY · HEALTH). Same AU setters; edits apply live.
struct ReceiverConfigView: View {
    @Environment(\.animationsPaused) private var animPaused
    let au: MidiSparkAudioUnit?
    let receivers: [Receiver]
    let inAt: [Date]                  // last input activity per receiver (for the IN dot fade)
    let mpeAt: [Date]                 // last MPE-detected per receiver (auto-detect dot)
    let onChanged: () -> Void         // refresh the VC's receivers after a live edit

    private let ink = Color.white
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let green = Color(red: 0.35, green: 0.92, blue: 0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIDI RECEIVERS").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.7)).tracking(1.5)
            Text("Four LENSES on one stream — the plugin hears every cable. Shape each door: channel · range · bypass destinations · MPE. (Latch KEYS|CHORD lives on the strip.)")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(ink.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { doorRow($0) }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .center)   // centre the config column on the wide tab canvas
    }

    // ONE line per door: hue·label · IN/MPE dots · CH chip (OMNI default) · RANGE · BYP→ · MPE.
    private func doorRow(_ i: Int) -> some View {
        let r = i < receivers.count ? receivers[i] : Receiver()
        return HStack(spacing: 8) {
            Text("R\(i + 1)").font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(i < receiverHues.count ? receiverHues[i] : ink.opacity(0.85)).frame(width: 28, alignment: .leading)
            liveDot(inAt[safe: i], cyan)
            mpeDot(mpeAt[safe: i], on: r.mpeMerge)
            Spacer(minLength: 8)
            channelMenu(current: r.channel) { au?.setReceiverChannel(i, $0); onChanged() }
            labeled("RANGE") { rangeChips(lo: r.rangeLoResolved, hi: r.rangeHiResolved) { lo, hi in au?.setReceiverRange(i, lo: lo, hi: hi); onChanged() } }
            labeled("BYP→") { bypassDestChips(mask: r.bypassDestResolved, active: r.bypassResolved) { d in au?.setReceiverBypassDest(i, Int(r.bypassDestResolved ^ (1 << UInt8(d)))); onChanged() } }
            labeled("MPE") { mpeToggle(on: r.mpeMerge) { au?.setReceiverMpeMerge(i, $0); onChanged() } }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(0.03)))
    }

    // MARK: controls (self-contained copies — the cog keeps its own for OUTPUT/DISPLAY)

    private func labeled<V: View>(_ t: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 4) {
            Text(t).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.4))
            content()
        }
    }
    private func channelMenu(current: Int, _ set: @escaping (Int) -> Void) -> some View {
        Menu {
            Button("OMNI") { set(0) }
            ForEach(1...16, id: \.self) { ch in Button("\(ch)") { set(ch) } }
        } label: {
            Text(current == 0 ? "OMNI" : "CH \(current)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(cyan)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.08)))
        }
    }
    private func rangeChips(lo: UInt8, hi: UInt8, _ set: @escaping (Int, Int) -> Void) -> some View {
        HStack(spacing: 2) {
            noteMenu(current: lo, isLo: true) { set(Int($0), Int(hi)) }
            Text("–").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.4))
            noteMenu(current: hi, isLo: false) { set(Int(lo), Int($0)) }
        }
    }
    private func noteMenu(current: UInt8, isLo: Bool, _ set: @escaping (UInt8) -> Void) -> some View {
        Menu {
            Button(isLo ? "MIN (all below)" : "MAX (all above)") { set(isLo ? 0 : 127) }
            ForEach(0..<11, id: \.self) { oct in
                Menu("Oct \(oct - 1)") {
                    ForEach(0..<12, id: \.self) { pc in
                        let n = oct * 12 + pc
                        if n <= 127 { Button(midiNoteName(UInt8(n))) { set(UInt8(n)) } }
                    }
                }
            }
        } label: {
            Text(midiNoteName(current))
                .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(cyan)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.08)))
        }
    }
    private func bypassDestChips(mask: UInt8, active: Bool, _ toggle: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { d in
                let on = mask & (1 << UInt8(d)) != 0
                Text(["A", "B", "C", "D"][d]).font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : ink.opacity(active ? 0.5 : 0.3))
                    .frame(width: 15, height: 18)
                    .background(RoundedRectangle(cornerRadius: 3).fill(on ? amber.opacity(active ? 1 : 0.45) : ink.opacity(0.08)))
                    .contentShape(Rectangle()).onTapGesture { toggle(d) }
            }
        }
    }
    private func mpeToggle(on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Text(on ? "ON" : "OFF").font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : ink.opacity(0.45))
            .frame(width: 34, height: 20)
            .background(RoundedRectangle(cornerRadius: 3).fill(on ? green : ink.opacity(0.07)))
            .contentShape(Rectangle()).onTapGesture { set(!on) }
    }
    private func liveDot(_ at: Date, _ hue: Color) -> some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: animPaused)) { tl in
            let lit = max(0, 1 - tl.date.timeIntervalSince(at) / 0.35)
            Circle().fill(hue.opacity(0.12 + 0.88 * lit)).frame(width: 8, height: 8)
                .overlay(Circle().stroke(hue.opacity(0.35), lineWidth: 0.5))
        }
    }
    private func mpeDot(_ at: Date, on: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: animPaused)) { tl in
            let lit = max(0, 1 - tl.date.timeIntervalSince(at) / 0.6)
            Text("M").font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(green.opacity(lit > 0.05 ? (0.3 + 0.7 * lit) : (on ? 0.28 : 0)))
        }
    }
}

private extension Array where Element == Date {
    subscript(safe i: Int) -> Date { indices.contains(i) ? self[i] : .distantPast }
}

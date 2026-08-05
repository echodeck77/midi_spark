import SwiftUI

/// LAYOUT v2 — THE MIDI RECEIVERS TAB (rebuilt 2026-08-05 to hold the full per-door surface). Four tall R blocks,
/// each: a header where R# is the on/off (input-enable) button + channel + range; the LATCH arm beside its two
/// KEYS|CHORD radios; NOTE± / OCTAVE± transpose; a "Bypass MIDI processors" emitter-destination row; the MPE toggle;
/// and MUTE · SOLO. Every control uses the SAME VC methods as the grid strip, so behaviour is identical.
struct ReceiverConfigView: View {
    let au: MidiSparkAudioUnit?
    let receivers: [Receiver]
    let soloMask: UInt8
    let latchMask: UInt8
    let octave: [Int]
    let note: [Int]
    let onToggleEnable: (Int) -> Void
    let onToggleMute: (Int) -> Void
    let onToggleSolo: (Int) -> Void
    let onToggleLatch: (Int) -> Void
    let onSetLatchKeys: (Int, Bool) -> Void
    let onToggleBypass: (Int) -> Void
    let onOct: (Int, Int) -> Void
    let onNote: (Int, Int) -> Void
    let onChanged: () -> Void

    private let ink = Color.white
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let green = Color(red: 0.35, green: 0.92, blue: 0.5)
    private func bit(_ mask: UInt8, _ i: Int) -> Bool { mask & (1 << UInt8(i)) != 0 }
    private func hue(_ i: Int) -> Color { i < receiverHues.count ? receiverHues[i] : ink.opacity(0.85) }
    private func rec(_ i: Int) -> Receiver { i < receivers.count ? receivers[i] : Receiver() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MIDI RECEIVERS").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.75)).tracking(1.5)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(0..<4, id: \.self) { block($0) }
                }
            }
        }
        .frame(width: 1024, alignment: .leading)                     // the two receivers per row total 1024 (user 2026-08-05)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)   // centred horizontally on the tab
    }

    private func block(_ i: Int) -> some View {
        let r = rec(i), h = hue(i)
        return VStack(alignment: .leading, spacing: 14) {
            headerRow(i, r, h)
            latchSection(i, r)
            transposeRow(i)
            bypassSection(i, r)
            mpeRow(i, r)
            muteSoloRow(i, r)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(h.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(h.opacity(0.28), lineWidth: 1))
    }

    // Header: R# = the INPUT-ENABLE on/off (off ⇒ blocks incoming notes, but an armed latch still feeds its frozen
    // pool → output continues via the toggle) · channel · range.
    private func headerRow(_ i: Int, _ r: Receiver, _ h: Color) -> some View {
        let on = r.inputEnabledResolved
        return HStack(spacing: 12) {
            Text("R\(i + 1)").font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundColor(on ? .black : h.opacity(0.85))
                .frame(width: 52, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? h : h.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(h.opacity(on ? 0 : 0.5), lineWidth: 1))
                .contentShape(Rectangle()).onTapGesture { onToggleEnable(i) }
            labeled("CH") { channelMenu(current: r.channel) { au?.setReceiverChannel(i, $0); onChanged() } }
            labeled("RANGE") { rangeChips(lo: r.rangeLoResolved, hi: r.rangeHiResolved) { lo, hi in au?.setReceiverRange(i, lo: lo, hi: hi); onChanged() } }
            Spacer(minLength: 0)
        }
    }

    // LATCH: the arm (left, spans both radios) + two mode radios stacked.
    private func latchSection(_ i: Int, _ r: Receiver) -> some View {
        let armed = bit(latchMask, i), keys = r.latchAddResolved
        return HStack(spacing: 12) {
            Image(systemName: armed ? "lock.fill" : "lock.open").font(.system(size: 20, weight: .heavy))
                .foregroundColor(armed ? .black : amber.opacity(0.95))
                .frame(width: 54).frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 7).fill(armed ? amber : amber.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(amber.opacity(armed ? 0 : 0.5), lineWidth: 1))
                .contentShape(Rectangle()).onTapGesture { onToggleLatch(i) }
            VStack(spacing: 8) {
                radio("LATCH: Add new notes to pool", on: keys) { onSetLatchKeys(i, true) }
                radio("LATCH: Replace pool with new notes", on: !keys) { onSetLatchKeys(i, false) }
            }
        }
        .frame(height: 68)
    }
    private func radio(_ label: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Circle().stroke(amber.opacity(0.85), lineWidth: 1.5).frame(width: 15, height: 15)
                .overlay(Circle().fill(amber).frame(width: 8, height: 8).opacity(on ? 1 : 0))
            Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(ink.opacity(on ? 0.95 : 0.55)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle()).onTapGesture(perform: tap)
    }

    // NOTE± (semitone) · OCTAVE±.
    private func transposeRow(_ i: Int) -> some View {
        HStack(spacing: 24) {
            nudge("NOTE", value: i < note.count ? note[i] : 0) { onNote(i, $0) }
            nudge("OCTAVE", value: i < octave.count ? octave[i] : 0) { onOct(i, $0) }
            Spacer(minLength: 0)
        }
    }
    private func nudge(_ label: String, value: Int, _ act: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 7) {
            Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.6))
            stepBtn("−") { act(-1) }
            Text(value == 0 ? "0" : (value > 0 ? "+\(value)" : "\(value)")).font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(value != 0 ? amber : ink.opacity(0.4)).frame(width: 30)
            stepBtn("+") { act(+1) }
        }
    }
    private func stepBtn(_ s: String, _ tap: @escaping () -> Void) -> some View {
        Text(s).font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.85))
            .frame(width: 30, height: 28).background(RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.1)))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }

    // "Bypass MIDI processors" — the four emitter destination toggles. Any selected ⇒ this door skips the grid and
    // injects straight to those emitters; none selected ⇒ bypass off (kept in sync with the door's bypass flag).
    private func bypassSection(_ i: Int, _ r: Receiver) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bypass MIDI processors").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.65))
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { d in
                    let on = Int(r.bypassDestResolved) & (1 << d) != 0
                    Text(["A", "B", "C", "D"][d]).font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : ink.opacity(0.6))
                        .frame(width: 38, height: 30)
                        .background(RoundedRectangle(cornerRadius: 5).fill(on ? cyan : ink.opacity(0.1)))
                        .contentShape(Rectangle()).onTapGesture {
                            let newDest = Int(r.bypassDestResolved) ^ (1 << d)
                            au?.setReceiverBypassDest(i, newDest)
                            if (newDest != 0) != r.bypassResolved { onToggleBypass(i) }   // sync the door's bypass on/off
                            onChanged()
                        }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func mpeRow(_ i: Int, _ r: Receiver) -> some View {
        let on = r.mpeMerge
        return HStack(spacing: 10) {
            Text("MPE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.65))
            Text(on ? "ON" : "OFF").font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(on ? .black : ink.opacity(0.5))
                .frame(width: 50, height: 28).background(RoundedRectangle(cornerRadius: 5).fill(on ? green : ink.opacity(0.1)))
                .contentShape(Rectangle()).onTapGesture { au?.setReceiverMpeMerge(i, !on); onChanged() }
            Spacer(minLength: 0)
        }
    }

    // MUTE · SOLO — same behaviour as the grid (onToggleMute / onToggleSolo).
    private func muteSoloRow(_ i: Int, _ r: Receiver) -> some View {
        let muted = r.muted, soloed = bit(soloMask, i)
        return HStack(spacing: 8) {
            bigBtn("MUTE", lit: muted, hue: cyan) { onToggleMute(i) }
            bigBtn("SOLO", lit: soloed, hue: amber) { onToggleSolo(i) }
            Spacer(minLength: 0)
        }
    }
    private func bigBtn(_ label: String, lit: Bool, hue: Color, _ tap: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced))
            .foregroundColor(lit ? .black : ink.opacity(0.7))
            .frame(width: 78, height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(lit ? hue : ink.opacity(0.1)))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }

    // MARK: shared control helpers

    private func labeled<V: View>(_ t: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 5) {
            Text(t).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.45))
            content()
        }
    }
    private func channelMenu(current: Int, _ set: @escaping (Int) -> Void) -> some View {
        Menu {
            Button("OMNI") { set(0) }
            ForEach(1...16, id: \.self) { ch in Button("\(ch)") { set(ch) } }
        } label: {
            Text(current == 0 ? "OMNI" : "CH \(current)")
                .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(cyan)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.1)))
        }
    }
    private func rangeChips(lo: UInt8, hi: UInt8, _ set: @escaping (Int, Int) -> Void) -> some View {
        HStack(spacing: 3) {
            noteMenu(current: lo, isLo: true) { set(Int($0), Int(hi)) }
            Text("–").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.4))
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
                .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(cyan)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.1)))
        }
    }
}

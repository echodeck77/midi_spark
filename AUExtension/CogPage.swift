import SwiftUI

/// §5 THE COG PAGE — the one settings door (⚙, top-right of the arrangement bar). A full-screen overlay ON
/// the running instrument: audio/render never stop, MIDI flows, latches hold; every edit applies live; dismiss
/// returns to uninterrupted play. It hosts the MIDI I/O RIG CONFIG (set-once rarities), NOT performance roles.
///
/// INPUT (4 receiver LENSES, one line each — COG SIMPLIFICATION 2026-08-03): channel (OMNI default) · MPE-merge
/// toggle — each with a live IN dot + an auto-detect MPE dot. CABLES are retired (the plugin hears every cable;
/// routing-in is the host's job); the LATCH mode (KEYS|CHORD) moved to the STRIP (§2). OUTPUT (4 emitters A–D):
/// stamp channel — each with a live OUT dot.
struct CogPage: View {
    @Environment(\.animationsPaused) private var animPaused
    let au: MidiSparkAudioUnit?
    let receivers: [Receiver]
    let busChannels: [Int]
    let d: KernelDiag                 // health readout (voices / held / panics)
    let inAt: [Date]                  // last input activity per receiver (for the IN dot fade)
    let outAt: [Date]                 // last output activity per emitter (for the OUT dot fade)
    let mpeAt: [Date]                 // last MPE-detected per receiver (auto-detect dot)
    let aboutLine: String
    @Binding var showScenes: Bool     // DISPLAY: the arrangement bar's 16-scene row (hidden by default)
    let onSetEmitterChannel: (Int, Int) -> Void
    let onChanged: () -> Void         // refresh the VC's receivers/busChannels after a live edit
    let onClose: () -> Void

    private let ink = Color.white
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let green = Color(red: 0.35, green: 0.92, blue: 0.5)

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea().onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        section("MIDI INPUT")
                        Text("Four LENSES on one stream — the plugin hears every cable. Shape each door: channel · range · MPE. (Latch KEYS|CHORD lives on the strip.)")
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.4))
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(0..<4, id: \.self) { inputRow($0) }
                        divider
                        section("MIDI OUTPUT")
                        ForEach(0..<4, id: \.self) { outputRow($0) }
                        divider
                        section("DISPLAY")
                        HStack(spacing: 8) {
                            Text("SCENES").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.85)).frame(width: 60, alignment: .leading)
                            Text("show the arrangement's 16-scene row").font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.4))
                            Spacer()
                            mpeToggle(on: showScenes) { showScenes = $0 }
                        }
                        divider
                        section("HEALTH")
                        healthRow
                        Text(aboutLine).font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.3))
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: 540, maxHeight: 620)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(0.1)))
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("SETTINGS").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.9))
                Spacer()
                Text("✕").font(.system(size: 18, weight: .heavy)).foregroundColor(ink.opacity(0.7))
                    .contentShape(Rectangle()).onTapGesture { onClose() }
            }
            Text("The engine keeps running — changes apply live.").font(.system(size: 10, design: .monospaced)).foregroundColor(ink.opacity(0.4))
        }
        .padding(.bottom, 12)
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.55)).tracking(1.5)
    }
    private var divider: some View { Divider().overlay(ink.opacity(0.12)).padding(.vertical, 2) }

    // MARK: INPUT — ONE line per door (COG SIMPLIFICATION 2026-08-03): hue·label · IN/MPE dots · CH chip
    // (OMNI default) · RANGE chips (§2, note window, default ALL) · MPE toggle. Cables are RETIRED and the LATCH
    // mode (KEYS|CHORD) moved to the strip (§2).

    private func inputRow(_ i: Int) -> some View {
        let r = i < receivers.count ? receivers[i] : Receiver()
        return HStack(spacing: 8) {
            Text("R\(i + 1)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(i < receiverHues.count ? receiverHues[i] : ink.opacity(0.85)).frame(width: 26, alignment: .leading)   // hue · label
            liveDot(inAt[safe: i], cyan)                                   // note-ons arriving
            mpeDot(mpeAt[safe: i], on: r.mpeMerge)                         // auto-detected MPE spread
            Spacer(minLength: 8)
            channelMenu(current: r.channel) { au?.setReceiverChannel(i, $0); onChanged() }   // CH chip — OMNI default, the one optional decision
            // (LATCH CHORD|ADD chip REMOVED 2026-08-03 — the mode is now KEYS|CHORD on the STRIP, per redesign §2.)
            labeled("RANGE") { rangeChips(lo: r.rangeLoResolved, hi: r.rangeHiResolved) { lo, hi in au?.setReceiverRange(i, lo: lo, hi: hi); onChanged() } }   // §2 note window (default ALL)
            labeled("BYP→") { bypassDestChips(mask: r.bypassDestResolved, active: r.bypassResolved) { d in au?.setReceiverBypassDest(i, Int(r.bypassDestResolved ^ (1 << UInt8(d)))); onChanged() } }   // §2 bypass destinations (default ALL)
            labeled("MPE") { mpeToggle(on: r.mpeMerge) { au?.setReceiverMpeMerge(i, $0); onChanged() } }
        }
    }

    private func outputRow(_ i: Int) -> some View {
        HStack(spacing: 8) {
            Text(["A", "B", "C", "D"][i]).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(amber).frame(width: 26, alignment: .leading)
            liveDot(outAt[safe: i], green)
            Spacer()
            labeled("CH") {
                channelMenu(current: i < busChannels.count ? busChannels[i] : i + 1, omni: false) { onSetEmitterChannel(i, $0) }
            }
        }
    }

    private var healthRow: some View {
        HStack(spacing: 14) {
            healthStat("VOICES", Int(d.activeVoiceCount))
            healthStat("HELD", Int(d.poolCount))
            healthStat("PANICS", Int(d.panics), alert: d.panics > 0)
            Spacer()
        }
    }
    private func healthStat(_ label: String, _ v: Int, alert: Bool = false) -> some View {
        Text("\(label) \(v)").font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(alert ? .black : ink.opacity(0.55))
            .padding(.horizontal, alert ? 5 : 0).padding(.vertical, alert ? 1 : 0)
            .background(RoundedRectangle(cornerRadius: 3).fill(alert ? Color(red: 0.98, green: 0.35, blue: 0.3) : .clear))
    }

    // MARK: controls

    private func labeled<V: View>(_ t: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 4) {
            Text(t).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.4))
            content()
        }
    }
    // CHANNEL: OMNI + 1–16 (emitters: 1–16 only). A Menu — legible, no tiny steppers.
    private func channelMenu(current: Int, omni: Bool = true, _ set: @escaping (Int) -> Void) -> some View {
        Menu {
            if omni { Button("OMNI") { set(0) } }
            ForEach(1...16, id: \.self) { ch in Button("\(ch)") { set(ch) } }
        } label: {
            Text(current == 0 ? "OMNI" : "CH \(current)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(cyan)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.08)))
        }
    }
    // (CABLE toggles retired 2026-08-03 — cables are router-admin the host owns; the plugin always hears all cables.)
    // (LATCH CHORD|ADD segments removed 2026-08-03 — the mode is now KEYS|CHORD on the strip, per redesign §2.)

    // RANGE (§2): the door's note WINDOW — two note chips (lo – hi), default ALL. Each chip is a menu of octave
    // submenus + a MIN/MAX (all) reset. The door admits only notes in [lo, hi], upstream of the latch.
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
            ForEach(0..<11, id: \.self) { oct in                    // octave submenus: index 0…10 ⇒ octave −1…9
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
    // BYPASS DESTINATIONS (§2): a per-door A–D multiselect — where the strip's BYPASS injects. Default ALL. Dimmed
    // when the door isn't bypassed (a hint that they only bite once BYPASS is armed on the strip).
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

    // MARK: indicators — a dot that fades from its last activity time (live while the page is open)

    private func liveDot(_ at: Date, _ hue: Color) -> some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: animPaused)) { tl in
            let lit = max(0, 1 - tl.date.timeIntervalSince(at) / 0.35)
            Circle().fill(hue.opacity(0.12 + 0.88 * lit)).frame(width: 8, height: 8)
                .overlay(Circle().stroke(hue.opacity(0.35), lineWidth: 0.5))
        }
    }
    // MPE dot: a small "M" — bright when MPE input is auto-detected now; dim outline when merge is toggled on
    // but nothing MPE is arriving; invisible when both off.
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

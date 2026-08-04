import SwiftUI

/// THE EMITTER PAGE — PASS 1 (the band desk at full size). A full-size surface that REPLACES THE GRID while the
/// strips + master stay live around it (edit-page geometry: the grid is the canvas that yields). Reached by
/// LONG-PRESSING an emitter's role button (→ that section) or its header (→ top). Header = A·B·C·D tabs · DONE.
/// PASS 1 re-surfaces only the controls that already exist in the engine (channel · OCT · CLAIM+leak · DUCK+amount
/// · ALT+count); the new sections (VOICE curve/MONO/FENCE · FEEL · CONVERSATION · ECHO/CHOKE/DENSITY) are dimmed
/// "coming" seats. Changes are LIVE + undoable — the same callbacks the strips use; no transaction.
struct EmitterPage: View {
    @Environment(\.animationsPaused) private var animPaused
    let emitter: Int            // the pointed emitter (0–3 = A–D)
    let section: String         // scroll target on open: "top" | "voice" | "claim" | "duck" | "alt"
    let busChannels: [Int]
    let busEnabled: [Bool]
    let claimMask: UInt8
    let claimLeak: [Int]
    let flattenMask: UInt8      // the DUCK engine (label renamed; code stays flatten*)
    let flattenAmount: [Int]
    let altMask: UInt8
    let altCount: [Int]
    let octave: [Int]
    let onTab: (Int) -> Void
    let onClaim: (Int) -> Void
    let onClaimLeak: (Int, Int) -> Void
    let onToggleDuck: (Int) -> Void
    let onDuckAmount: (Int, Int) -> Void
    let onToggleAlt: (Int) -> Void
    let onAltCount: (Int, Int) -> Void
    let onOct: (Int, Int) -> Void
    let onClose: () -> Void

    private let ink = Color.white
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let green = Color(red: 0.35, green: 0.92, blue: 0.5)
    private let letters = ["A", "B", "C", "D"]
    private func bit(_ m: UInt8, _ i: Int) -> Bool { m & (1 << UInt8(i)) != 0 }
    private func e<T>(_ a: [T], _ d: T) -> T { emitter < a.count ? a[emitter] : d }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            readout.padding(.vertical, 8)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        voiceSection.id("voice")
                        divider
                        claimSection.id("claim")
                        divider
                        duckSection.id("duck")
                        divider
                        altSection.id("alt")
                        divider
                        comingSeats
                    }.padding(.bottom, 24)
                }
                .onAppear { if section != "top" { proxy.scrollTo(section, anchor: .top) } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.09, green: 0.10, blue: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink.opacity(0.08)))
    }

    // MARK: header — A·B·C·D tabs (pointed lit) · DONE
    private var header: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                let pointed = i == emitter, off = i < busEnabled.count && !busEnabled[i]
                Text(letters[i]).font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(pointed ? .black : (off ? ink.opacity(0.3) : cyan))
                    .frame(width: 34, height: 26)
                    .background(RoundedRectangle(cornerRadius: 5).fill(pointed ? cyan : ink.opacity(0.08)))
                    .contentShape(Rectangle()).onTapGesture { onTab(i) }
            }
            Spacer()
            Text("DONE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .padding(.horizontal, 12).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.85)))
                .contentShape(Rectangle()).onTapGesture { onClose() }
        }
    }

    // MARK: readout — the emitter's social life in words (only TRUE clauses)
    private var readout: some View {
        var clauses: [String] = []
        if bit(claimMask, emitter) { clauses.append(e(claimLeak, 0) > 0 ? "CLAIMS · leaks \(e(claimLeak, 0))%" : "CLAIMS (hard)") }
        if bit(flattenMask, emitter) { clauses.append("DUCKS others by \(e(flattenAmount, 0))%") }
        if bit(altMask, emitter) { clauses.append("takes turns, \(max(1, e(altCount, 1))) note\(e(altCount, 1) == 1 ? "" : "s") each") }
        let line = clauses.isEmpty ? "A plain voice — no roles yet." : clauses.joined(separator: "  ·  ")
        return Text(line).font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
    }

    private var divider: some View { Divider().overlay(ink.opacity(0.12)) }
    private func title(_ t: String, on: Bool = false, hue: Color? = nil) -> some View {
        Text(t).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1.5)
            .foregroundColor(on ? (hue ?? cyan) : ink.opacity(0.55))
    }

    // MARK: VOICE — channel (display) · OCT (existing). Curve/MONO/FENCE are future seats.
    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            title("VOICE")
            HStack(spacing: 10) {
                Text("CH \(emitter < busChannels.count ? busChannels[emitter] : emitter + 1)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(cyan)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.08)))
                Text("set on the cog").font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.35))
                Spacer()
                stepper(label: "OCT", value: e(octave, 0), suffix: e(octave, 0) == 0 ? "" : (e(octave, 0) > 0 ? "+\(e(octave, 0))" : "\(e(octave, 0))")) { onOct(emitter, $0) }
            }
            futureLine("velocity curve · MONO · the FENCE — coming")
        }
    }

    // MARK: CLAIM — toggle · LEAK %
    private var claimSection: some View {
        let on = bit(claimMask, emitter)
        return VStack(alignment: .leading, spacing: 8) {
            HStack { title("CLAIM", on: on, hue: amber); Spacer(); toggle(on: on, hue: amber) { onClaim(emitter) } }
            pctRow("LEAK", value: e(claimLeak, 0), enabled: on) { onClaimLeak(emitter, $0) }
            futureLine("scope CLASS | RANGE · release-lag — coming")
        }
    }

    // MARK: DUCK — toggle · AMOUNT %
    private var duckSection: some View {
        let on = bit(flattenMask, emitter)
        return VStack(alignment: .leading, spacing: 8) {
            HStack { title("DUCK", on: on, hue: amber); Spacer(); toggle(on: on, hue: amber) { onToggleDuck(emitter) } }
            pctRow("AMOUNT", value: e(flattenAmount, 0), enabled: on) { onDuckAmount(emitter, $0) }
            futureLine("ATTACK / RELEASE · TARGETS · note-class filter — coming")
        }
    }

    // MARK: ALT — toggle · COUNT
    private var altSection: some View {
        let on = bit(altMask, emitter)
        return VStack(alignment: .leading, spacing: 8) {
            HStack { title("ALT", on: on, hue: amber); Spacer(); toggle(on: on, hue: amber) { onToggleAlt(emitter) } }
            HStack(spacing: 10) {
                Text("NOTES / TURN").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(enabled: on))
                stepper(label: "", value: max(1, e(altCount, 1)), suffix: "\(max(1, e(altCount, 1)))") { onAltCount(emitter, max(1, min(8, max(1, e(altCount, 1)) + $0))) }
                Spacer()
            }
            futureLine("ROTATE | DEAL · RING · reset-at-pass — coming")
        }
    }

    // MARK: future seats — present, dimmed, recessive
    private var comingSeats: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(["FEEL — push / lay-back · humanize", "CONVERSATION — lead · free | with | against",
                     "ECHO", "CHOKE group", "DENSITY governor"], id: \.self) { s in
                Text(s).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.22))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.03)))
            }
            Text("Future seats — the page anticipates them; no rework when they land.")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.25)).padding(.top, 2)
        }
    }

    // MARK: controls
    private func toggle(on: Bool, hue: Color, _ tap: @escaping () -> Void) -> some View {
        Text(on ? "ON" : "OFF").font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : ink.opacity(0.5)).frame(width: 40, height: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? hue : ink.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    private func pctRow(_ label: String, value: Int, enabled: Bool, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(enabled: enabled)).frame(width: 64, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4).fill((enabled ? amber : ink.opacity(0.2)).opacity(0.7))
                        .frame(width: max(2, g.size.width * CGFloat(value) / 100))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    set(max(0, min(100, Int(v.location.x / g.size.width * 100))))
                })
            }.frame(height: 22)
            Text("\(value)%").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(enabled ? 0.7 : 0.3)).frame(width: 40, alignment: .trailing)
        }
    }
    private func stepper(label: String, value: Int, suffix: String, _ nudge: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            if !label.isEmpty { Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.5)) }
            stepBtn("−") { nudge(-1) }
            Text(suffix.isEmpty ? "0" : suffix).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(cyan).frame(minWidth: 24)
            stepBtn("+") { nudge(+1) }
        }
    }
    private func stepBtn(_ t: String, _ tap: @escaping () -> Void) -> some View {
        Text(t).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.8))
            .frame(width: 26, height: 24).background(RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.1)))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    private func futureLine(_ t: String) -> some View {
        Text(t).font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.28))
    }
}

private extension Color {
    /// ink opacity keyed on an enabled flag — a section whose role is OFF reads recessive (chrome-quiet law).
    func opacity(enabled: Bool) -> Color { self.opacity(enabled ? 0.7 : 0.35) }
}

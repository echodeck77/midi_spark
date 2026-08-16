import SwiftUI

/// §5 THE COG PAGE — the one settings door (⚙, top-right of the arrangement bar). A full-screen overlay ON
/// the running instrument: audio/render never stop, MIDI flows, latches hold; every edit applies live; dismiss
/// returns to uninterrupted play. It hosts the true GLOBALS, NOT performance roles.
///
/// LAYOUT v2: the per-door MIDI INPUT config moved to its own RECEIVERS tab (`ReceiverConfigView`). The cog now
/// holds OUTPUT (4 emitters A–D: stamp channel, each with a live OUT dot) · DISPLAY · HEALTH · about.
struct CogPage: View {
    @Environment(\.animationsPaused) private var animPaused
    let au: MidiSparkAudioUnit?
    let busChannels: [Int]
    let d: KernelDiag                 // health readout (voices / held / panics)
    let outAt: [Date]                 // last output activity per emitter (for the OUT dot fade)
    let aboutLine: String
    @Binding var showScenes: Bool     // DISPLAY: the arrangement bar's 16-scene row (hidden by default)
    let onSetEmitterChannel: (Int, Int) -> Void
    let onChanged: () -> Void         // refresh the VC's receivers/busChannels after a live edit
    let onClose: () -> Void

    private let ink = Color.white
    private let cyan = UI.cyan
    private let amber = UI.amber
    private let green = UI.green

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea().onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        // LAYOUT v2: MIDI INPUT (the per-door config) moved to its own RECEIVERS tab. The cog keeps
                        // the true globals below: MIDI OUTPUT · DISPLAY · HEALTH.
                        section("MIDI OUTPUT")
                        ForEach(0..<4, id: \.self) { outputRow($0) }
                        divider
                        section("DISPLAY")
                        HStack(spacing: 8) {
                            Text("SCENES").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.85)).frame(width: 60, alignment: .leading)
                            Text("show the arrangement's 16-scene row").font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.4))
                            Spacer()
                            onOffToggle(on: showScenes) { showScenes = $0 }
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
            healthStat("DROPPED", d.floodDropped, alert: d.floodDropped > 0)   // FLOOD GOVERNOR tell (incident 2026-08-08)
            Spacer()
        }
    }
    private func healthStat(_ label: String, _ v: Int, alert: Bool = false) -> some View {
        Text("\(label) \(v)").font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(alert ? .black : ink.opacity(0.55))
            .padding(.horizontal, alert ? 5 : 0).padding(.vertical, alert ? 1 : 0)
            .background(RoundedRectangle(cornerRadius: 3).fill(alert ? UI.red : .clear))
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
    private func onOffToggle(on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
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
}

private extension Array where Element == Date {
    subscript(safe i: Int) -> Date { indices.contains(i) ? self[i] : .distantPast }
}

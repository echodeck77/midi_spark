import SwiftUI

/// §5 THE COG PAGE — the one settings door (⚙, top-right of the arrangement bar). A full-screen overlay ON
/// the running instrument: audio/render never stop, MIDI flows, latches hold; every edit applies live; dismiss
/// returns to uninterrupted play. It hosts the true GLOBALS, NOT performance roles.
///
/// The MIDI INPUT (doors) + MIDI OUTPUT (emitter channels) config moved to their own MIDI IN / MIDI OUT buttons
/// (Paul 2026-08-23). The cog now holds the true globals: DISPLAY · HEALTH · about.
struct CogPage: View {
    let au: MidiSparkAudioUnit?
    let d: KernelDiag                 // health readout (voices / held / panics)
    let aboutLine: String
    @Binding var showScenes: Bool     // DISPLAY: the arrangement bar's 16-scene row (hidden by default)
    @Binding var showRoomsFooter: Bool   // DISPLAY: the extend-page MIDI footer (hidden by default now — its controls moved onto the machine column)
    let onClose: () -> Void

    private let ink = Color.white
    private let green = UI.green

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea().onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        // MIDI INPUT (the doors) has its own MIDI IN button; MIDI OUTPUT (emitter channels) moved to its
                        // own MIDI OUT button (Paul 2026-08-23). The cog keeps the true globals: DISPLAY · HEALTH.
                        section("DISPLAY")
                        HStack(spacing: 8) {
                            Text("SCENES").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.85)).frame(width: 60, alignment: .leading)
                            Text("show the arrangement's 16-scene row").font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.4))
                            Spacer()
                            onOffToggle(on: showScenes) { showScenes = $0 }
                        }
                        HStack(spacing: 8) {
                            Text("MIDI BAR").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.85)).frame(width: 60, alignment: .leading)
                            Text("show the old extend-page MIDI footer (its controls now live on the machine column)").font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.4))
                            Spacer()
                            onOffToggle(on: showRoomsFooter) { showRoomsFooter = $0 }
                        }
                        divider
                        section("HEALTH")
                        healthRow
                        replayRow
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

    private var healthRow: some View {
        HStack(spacing: 14) {
            healthStat("VOICES", Int(d.activeVoiceCount))
            healthStat("HELD", Int(d.poolCount))
            healthStat("PANICS", Int(d.panics), alert: d.panics > 0)
            healthStat("DROPPED", d.floodDropped, alert: d.floodDropped > 0)   // FLOOD GOVERNOR tell (incident 2026-08-08)
            Spacer()
        }
    }
    // DOOR REPLAY diagnostic (2026-08-22): shown only while a REPLAY door is engaged. Reads the chain left→right —
    // ENG (which doors loop) · LOOP (events captured) · RPOOL (notes the loop feeds the grid). LOOP 0 = capture empty;
    // LOOP>0 & RPOOL 0 = the loop→pool fill is broken; RPOOL>0 yet no sound = no grid cell reads that door.
    @ViewBuilder private var replayRow: some View {
        if d.replayEngaged != 0 {
            HStack(spacing: 14) {
                healthStat("RPLY ENG", Int(d.replayEngaged))
                healthStat("LOOP", d.replayLoopN, alert: d.replayLoopN == 0)
                healthStat("RPOOL", d.replayPoolN, alert: d.replayPoolN == 0)
                Spacer()
            }
        }
    }
    private func healthStat(_ label: String, _ v: Int, alert: Bool = false) -> some View {
        Text("\(label) \(v)").font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(alert ? .black : ink.opacity(0.55))
            .padding(.horizontal, alert ? 5 : 0).padding(.vertical, alert ? 1 : 0)
            .background(RoundedRectangle(cornerRadius: 3).fill(alert ? UI.red : .clear))
    }

    // MARK: controls

    private func onOffToggle(on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Text(on ? "ON" : "OFF").font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : ink.opacity(0.45))
            .frame(width: 34, height: 20)
            .background(RoundedRectangle(cornerRadius: 3).fill(on ? green : ink.opacity(0.07)))
            .contentShape(Rectangle()).onTapGesture { set(!on) }
    }

}

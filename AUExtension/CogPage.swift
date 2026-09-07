import SwiftUI

/// §5 THE COG PAGE — the one settings door (⚙, top-right of the arrangement bar). A full-screen overlay ON
/// the running instrument: audio/render never stop, MIDI flows, latches hold; every edit applies live; dismiss
/// returns to uninterrupted play. It hosts the true GLOBALS, NOT performance roles.
///
/// The MIDI INPUT (doors) + MIDI OUTPUT (emitter channels) config moved to their own MIDI IN / MIDI OUT buttons
/// (Paul 2026-08-23). The cog now holds the true globals: DISPLAY · INPUT (ignore all-notes-off) · HEALTH · about.
struct CogPage: View {
    let au: MidiSparkAudioUnit?
    let d: KernelDiag                 // health readout (voices / held / panics)
    let aboutLine: String
    @Binding var showScenes: Bool     // DISPLAY: the arrangement bar's 16-scene row (hidden by default)
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
                        divider
                        section("INPUT")
                        HStack(spacing: 8) {
                            Text("IGNORE ALL-NOTES-OFF").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.85)).fixedSize()
                            Text("drop incoming CC120/123 so a source can't wipe a held chord").font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.4))
                            Spacer()
                            onOffToggle(on: au?.uiIgnoreAllNotesOff() ?? true) { au?.setIgnoreAllNotesOff($0) }
                        }
                        divider
                        section("HEALTH")
                        healthRow
                        replayRow
                        holdRow
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
        HStack(spacing: 12) {
            // PLAY = the engine's CLOCK is advancing (host transport OR free-run). A HOLD chord is only SEQUENCED while the
            // clock runs; if PLAY 0 while a chord is HELD/FRZ, the grid isn't advancing (transport stopped + free-run off) —
            // that's the "HOLD enabled but nothing sounds" case, and it's the CLOCK, not the latch. (Paul 2026-09-06)
            healthStat("PLAY", d.effectivePlaying ? 1 : 0, alert: !d.effectivePlaying)
            healthStat("SND", Int(d.distinctSounding))    // distinct notes actually on the WIRE (emitted output) — 0 = nothing coming out
            healthStat("VOICES", Int(d.activeVoiceCount))
            healthStat("HELD", Int(d.poolCount))          // raw LIVE input pool
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
    // HOLD BISECT (Paul 2026-08-31): while any door latch is armed, show per-armed-door LIVE (admitted input) vs FRZ (held).
    // Play a chord → arm → play a NEW chord: if FRZ doesn't follow, the live→frozen capture is at fault; if LIVE never shows
    // the new chord, the input isn't reaching that door (channel / cable / range).
    @ViewBuilder private var holdRow: some View {
        if d.holdArmed != 0 {
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    if d.holdArmed & (1 << UInt8(i)) != 0 {
                        let mode = d.holdKeysMask & (1 << UInt8(i)) != 0 ? "K" : "C"   // K = KEYS/note-toggle branch · C = CHORD/mirror-and-freeze (staccato-fixed)
                        healthStat("\(["A","B","C","D"][i])·\(mode) LIV", i < d.holdLiveN.count ? d.holdLiveN[i] : 0)
                        healthStat("STR", i < d.holdStruckN.count ? d.holdStruckN[i] : 0)   // notes struck THIS block (did the staccato capture see the strike?)
                        healthStat("FRZ", i < d.holdFrozenN.count ? d.holdFrozenN[i] : 0)
                    }
                }
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

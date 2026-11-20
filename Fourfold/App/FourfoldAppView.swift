//  FourfoldAppView.swift
//  FOURFOLD Step 3 (2026-10-23): the standalone app's window — a slim TRANSPORT BAR (what AUM's transport is to the plugin: PLAY/STOP, tempo, bar/beat) above the same `FourfoldRootView` the extension shows.

import SwiftUI
import UIKit

struct FourfoldAppView: View {
    @StateObject private var model = FourfoldAppModel()
    @StateObject private var visibility = FourfoldViewVisibility()   // UI-CPU fix (2026-11-20): driven by scenePhase; false while backgrounded → the page freezes its animations
    @Environment(\.scenePhase) private var scenePhase
    @State private var showBluetooth = false
    private let autosave = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    #if FOURFOLD_LINK   // ABLETON LINK is OFF until after release — see `Docs/standalone-plan.md` "Ableton Link" for the switch
    // ABLETON LINK (2026-10-24 ferry): tap the LINK button toggles it like PLAY; a long-press opens
    // Ableton's own settings screen (the only place "Start Stop Sync" can be turned on) — tap-vs-
    // long-press for toggle-vs-menu is this codebase's established convention (e.g. the riff tabs).
    @State private var showLinkSettings = false
    #endif

    private let bg = Color(red: 0.066, green: 0.075, blue: 0.094)
    private let panel = Color(red: 0.10, green: 0.11, blue: 0.14)
    private let text = Color(red: 0.949, green: 0.957, blue: 0.969)
    private let dim = Color(red: 0.541, green: 0.565, blue: 0.604)
    private let accent = Color(red: 0.31, green: 0.82, blue: 0.91)

    var body: some View {
        ZStack(alignment: .top) {
            bg.ignoresSafeArea()
            VStack(spacing: 0) {
                transportBar
                if let au = model.engine?.au {
                    FourfoldRootView(au: au, internalTransport: true, visibility: visibility).modifier(FourfoldTestWindowSize())
                } else {
                    Spacer()
                    Text(model.launchError ?? "NO ENGINE").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(dim)
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
        // A best-effort ask that the window not shrink below the plugin's own preferred size. Apple's docs call `sizeRestrictions` "a preference, not a guarantee" (it can still let the
        // window go smaller, and on some iPadOS versions resets to 0), so the page itself stays live and interactive at whatever size it is given (the old "RESIZE TO CONTINUE" fallback was removed).
        .onAppear {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.sizeRestrictions?.minimumSize = CGSize(width: 760, height: 480)
            }
        }
        .onChange(of: scenePhase) { phase in visibility.onScreen = (phase == .active); if phase != .active { model.saveState() } }
        .onReceive(autosave) { _ in model.saveState() }
        #if FOURFOLD_LINK
        .sheet(isPresented: $showLinkSettings) {
            if let link = model.engine?.link {
                NavigationView {
                    FourfoldLinkSettingsView(link: link)
                        .navigationTitle("Link Settings").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showLinkSettings = false } } }
                }
            }
        }
        #endif
    }

    private var transportBar: some View {
        HStack(spacing: 12) {
            // HEADER v2 §6.2: separate ▶ and ■. ▶ starts (does nothing while playing); ■ stops while playing, and while
            // stopped returns to bar 1 beat 1 + silences every output. sp4 between them.
            HStack(spacing: 4) {
                Button { if !model.playing { model.togglePlaying() } } label: {
                    Image(systemName: "play.fill").font(.system(size: 18))
                        .foregroundColor(model.playing ? bg : accent)
                        .frame(width: 52, height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(model.playing ? accent : Color(red: 0.137, green: 0.149, blue: 0.176)))   // playing: cyan/bg triangle · stopped: #23262D/#AAB0BA
                }
                .accessibilityLabel("Play")
                Button { if model.playing { model.togglePlaying() } else { model.returnToStart() } } label: {
                    Image(systemName: "stop.fill").font(.system(size: 18))
                        .foregroundColor(model.playing ? Color(red: 0.874, green: 0.890, blue: 0.918) : dim)   // #DFE3EA playing · #8A909A stopped
                        .frame(width: 52, height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.137, green: 0.149, blue: 0.176)))   // always #23262D
                }
                .accessibilityLabel(model.playing ? "Stop" : "Return to start")
            }

            HStack(spacing: 4) {
                stepButton("minus") { model.setTempo(model.tempo - 1) }
                VStack(spacing: 0) {
                    Text("\(Int(model.tempo))").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(text)
                    Text("BPM").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.2).foregroundColor(dim)
                }
                .frame(width: 56)
                stepButton("plus") { model.setTempo(model.tempo + 1) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tempo, \(Int(model.tempo)) beats per minute")
            .accessibilityAdjustableAction { dir in model.setTempo(model.tempo + (dir == .increment ? 1 : -1)) }

            Slider(value: Binding(get: { model.tempo }, set: { model.setTempo($0) }), in: FourfoldTransportClock.tempoRange)
                .tint(accent).frame(maxWidth: 260)
                .accessibilityHidden(true)

            bluetoothButton

            #if FOURFOLD_LINK
            linkButton
            #endif

            Spacer(minLength: 0)

            // HEADER v2 §6.6: two lines — "<bar> · <beat>" over one pip per beat of the bar (4/4). "BAR" is gone.
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                positionReadout
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(panel.opacity(0.6))
    }

    // HEADER v2 §6.6: the position — two lines (84 wide, 5 apart). Numbers #AAB0BA playing / #5C626C stopped; the " · "
    // always #5C626C. Below, one 6×6 pip per beat of the bar: the current beat #DFE3EA while playing, the rest #3A3E47;
    // all #3A3E47 while stopped. Beats per bar = 4 (Fourfold's internal clock is 4/4).
    private var positionReadout: some View {
        let beatsPerBar = 4
        let beat = model.engine?.au.kernelDiagnostics().beat ?? 0
        let pos = euclideousTransportPosition(beat: beat, beatsPerBar: beatsPerBar)
        let numC = model.playing ? Color(red: 0.667, green: 0.690, blue: 0.729) : Color(red: 0.361, green: 0.384, blue: 0.424)
        let sepC = Color(red: 0.361, green: 0.384, blue: 0.424)
        let dot = Color(red: 0.227, green: 0.243, blue: 0.278), live = Color(red: 0.874, green: 0.890, blue: 0.918)
        return VStack(alignment: .leading, spacing: 5) {
            (Text("\(pos.bar)").foregroundColor(numC) + Text(" · ").foregroundColor(sepC) + Text("\(pos.beatInBar)").foregroundColor(numC))
                .font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(0.06 * 13)
            HStack(spacing: 4) {
                ForEach(0..<beatsPerBar, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5).fill((model.playing && i == pos.beatInBar - 1) ? live : dot).frame(width: 6, height: 6)
                }
            }.accessibilityHidden(true)
        }
        .frame(width: 84, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("bar \(pos.bar), beat \(pos.beatInBar)")
    }

    #if FOURFOLD_LINK
    /// ABLETON LINK: tap toggles `linkEnabled` (same gesture as PLAY); long-press opens the real
    /// settings screen. OFF = dim outline; ON but no peer yet = lit outline, no count; connected =
    /// filled, showing the peer count — three states, one glance, same visual language as PLAY's own
    /// filled-vs-outline.
    private var linkButton: some View {
        let on = model.linkEnabled
        let connected = on && model.linkConnected
        return Button { model.setLinkEnabled(!on) } label: {
            HStack(spacing: 4) {
                Image(systemName: "link").font(.system(size: 13, weight: .bold))
                if connected { Text("\(model.linkPeerCount)").font(.system(size: 12, weight: .heavy, design: .monospaced)) }
            }
            .foregroundColor(connected ? bg : (on ? accent : dim))
            .frame(height: 36)
            .padding(.horizontal, connected ? 10 : 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(connected ? accent : panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? accent : .clear, lineWidth: 1.5))
        }
        .onLongPressGesture(minimumDuration: 0.5) { showLinkSettings = true }
        .accessibilityLabel(on ? (connected ? "Link, connected to \(model.linkPeerCount) peers" : "Link, on, no peers") : "Link, off")
        .accessibilityHint("Double-tap to turn Link on or off. Long-press for Link settings.")
    }
    #endif

    /// Opens Apple's Bluetooth MIDI pairing screen (a sheet, in a navigation bar with Done — the way CoreAudioKit wants it shown).
    private var bluetoothButton: some View {
        Button { showBluetooth = true } label: {
            Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 14, weight: .bold)).foregroundColor(dim)
                .frame(width: 44, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(panel))
        }
        .accessibilityLabel("Bluetooth MIDI devices")
        .accessibilityHint("Opens the screen for pairing a Bluetooth MIDI keyboard or controller.")
        .sheet(isPresented: $showBluetooth) {   // on the button itself: SwiftUI before iOS 16 keeps only the last .sheet on one view
            NavigationView {
                FourfoldBluetoothMIDIView()
                    .navigationTitle("Bluetooth MIDI").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showBluetooth = false } } }
            }
            .navigationViewStyle(.stack)
        }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundColor(text)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(panel))
        }
        .accessibilityHidden(true)
    }
}

/// UI-test seam: the launch argument `--window-size=480x320` frames the page to that size, as a small host window would. It does nothing without the argument.
struct FourfoldTestWindowSize: ViewModifier {
    static let size: CGSize? = {
        guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--window-size=") }) else { return nil }
        let wh = arg.dropFirst("--window-size=".count).split(separator: "x").compactMap { Double($0) }
        return wh.count == 2 ? CGSize(width: wh[0], height: wh[1]) : nil
    }()
    @ViewBuilder func body(content: Content) -> some View {
        if let s = Self.size { content.frame(width: s.width, height: s.height, alignment: .topLeading).clipped() } else { content }
    }
}

//  FourfoldAppView.swift
//  FOURFOLD Step 3 (2026-10-23): the standalone app's window — a slim TRANSPORT BAR (what AUM's transport is to the plugin: PLAY/STOP, tempo, bar/beat) above the same `FourfoldRootView` the extension shows.

import SwiftUI

struct FourfoldAppView: View {
    @StateObject private var model = FourfoldAppModel()
    @Environment(\.scenePhase) private var scenePhase
    private let autosave = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

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
                    FourfoldRootView(au: au, internalTransport: true)
                } else {
                    Spacer()
                    Text(model.launchError ?? "NO ENGINE").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(dim)
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in if phase != .active { model.saveState() } }
        .onReceive(autosave) { _ in model.saveState() }
    }

    private var transportBar: some View {
        HStack(spacing: 12) {
            Button { model.togglePlaying() } label: {
                Image(systemName: model.playing ? "stop.fill" : "play.fill").font(.system(size: 18))
                    .foregroundColor(model.playing ? bg : accent)
                    .frame(width: 52, height: 40)
                    .background(RoundedRectangle(cornerRadius: 8).fill(model.playing ? accent : panel))
            }
            .accessibilityLabel(model.playing ? "Stop" : "Play")

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

            Spacer(minLength: 0)

            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let beat = model.playing ? (model.engine?.au.kernelDiagnostics().beat ?? 0) : 0
                let bar = Int(beat / 4) + 1, inBar = Int(beat.truncatingRemainder(dividingBy: 4)) + 1
                Text(model.playing ? "BAR \(bar) · \(inBar)" : "STOPPED").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.2).foregroundColor(dim)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(panel.opacity(0.6))
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

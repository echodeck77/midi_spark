//  AudioUnitViewController.swift
//  Extension principal class + the diagnostic panel (temporary UI for bridge debugging).

import CoreAudioKit
import SwiftUI

public class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: MidiSparkAudioUnit?

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let au = try MidiSparkAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = au
        DispatchQueue.main.async { [weak self] in self?.embedUI() }
        return au
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 760, height: 480)
        if audioUnit != nil { embedUI() }
    }

    private func embedUI() {
        guard children.isEmpty else { return }
        let host = UIHostingController(rootView: DiagView(au: audioUnit))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// Live diagnostics: what the kernel is actually seeing, at 4 Hz.
/// Interpreting it:
///  · PARAM EVENTS rising while you turn a mapped knob → host uses render-side events (kernel handles).
///  · TREE morph moving but PARAM EVENTS static → host uses setValue (observer/snapshot path).
///  · Neither moving → the mapping isn't reaching this instance (host-side routing).
///  · CC IN rising → raw CC arrives at the MIDI input (and is passed through on A).
struct DiagView: View {
    weak var au: MidiSparkAudioUnit?
    @State private var d = KernelDiag()
    @State private var treeMorphGold: Float = 0
    @State private var treeSwing: Float = 50
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(red: 0.066, green: 0.075, blue: 0.094).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 7) {
                Text("MIDISPARK — BRIDGE DIAGNOSTICS")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(3)
                    .foregroundColor(.white.opacity(0.85))

                row("TRANSPORT", d.playing ? "PLAYING" : "stopped",
                    String(format: "beat %.2f · %.1f bpm", d.beat, d.tempo))
                row("RENDER", "\(d.renderCount) callbacks", "snapshot gen \(d.snapshotGen)")
                row("POOL", "\(d.poolCount) held notes", d.poolCount == 0 ? "→ hold a chord on the routed keyboard" : "")
                row("PARAM EVENTS", "\(d.paramEventCount) received",
                    d.lastParamAddr >= 0 ? String(format: "last: addr %d = %.3f", d.lastParamAddr, d.lastParamValue) : "none yet")
                row("TREE VALUES", String(format: "morph gold %.3f", treeMorphGold),
                    String(format: "swing %.1f", treeSwing))
                row("EFFECTIVE", String(format: "morph %.3f → rate %.4f beats", d.effMorphGold, d.effRateBeats),
                    String(format: "swing %.1f", d.effSwing))
                row("CC IN", "\(d.ccCount) messages",
                    d.ccCount > 0 ? String(format: "last: %02X %d %d (passed on A)", d.ccStatus, d.ccData1, d.ccData2) : "none yet")

                Text("If PARAM EVENTS and TREE both sit still while you move a mapped control, the mapping isn't reaching this instance — check AUM's control target.")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onReceive(timer) { _ in
            guard let au else { return }
            d = au.kernelDiagnostics()
            treeMorphGold = au.parameterTree?.parameter(withAddress: 200)?.value ?? 0
            treeSwing = au.parameterTree?.parameter(withAddress: 1)?.value ?? 50
        }
    }

    private func row(_ label: String, _ main: String, _ sub: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).frame(width: 110, alignment: .leading)
            Text(main).font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
            Text(sub).font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(red: 0.15, green: 0.88, blue: 0.94).opacity(0.8))
            Spacer()
        }
    }
}

//  AudioUnitViewController.swift
//  Extension principal class: creates the audio unit, hosts the placeholder SwiftUI UI.

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
        let host = UIHostingController(rootView: PlaceholderView())
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// Scaffold UI. TODO(spec §5/§6): the real grid replaces this — reference: midispark-preview-v26.html.
struct PlaceholderView: View {
    private let hexes: [UInt32] = [0xFFC53D, 0xFF7A1A, 0xFF4B33, 0xC2244B, 0xFF4D9E, 0xFFA8B8,
                                   0xB44DFF, 0x7A3DF0, 0x5566FF, 0x38A6FF, 0x25E0F0, 0x148F80,
                                   0x7BF2CE, 0x2ECC5E, 0xC6F23D, 0xC9A227]
    var body: some View {
        ZStack {
            Color(red: 0.066, green: 0.075, blue: 0.094).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("MIDISPARK").font(.system(size: 15, weight: .heavy, design: .monospaced)).tracking(6)
                    .foregroundColor(.white.opacity(0.85))
                Text("engine scaffold · four MIDI outs declared · hold a chord, press play in the host")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 8), spacing: 8) {
                    ForEach(0..<16, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(hex: hexes[i]))
                            .frame(width: 30, height: 30)
                    }
                }
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

//  FourfoldApp.swift
//  FOURFOLD Step 1c: the standalone app's entry point — a placeholder container until Step 3 adds the transport, render pump and CoreMIDI shell.

import SwiftUI

@main
struct FourfoldApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 0.066, green: 0.075, blue: 0.094).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("FOURFOLD").font(.system(size: 18, weight: .heavy, design: .monospaced)).tracking(8).foregroundColor(.white.opacity(0.9))
                    Text("The Fourfold AUv3 is installed with this app.\nOpen AUM → add a MIDI Processor → Fourfold.").multilineTextAlignment(.center)
                        .font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                }.padding()
            }
        }
    }
}

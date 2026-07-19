import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(red: 0.066, green: 0.075, blue: 0.094).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("MIDISPARK").font(.system(size: 18, weight: .heavy, design: .monospaced)).tracking(8)
                    .foregroundColor(.white.opacity(0.9))
                Text("The AUv3 extension is installed with this app.\nOpen AUM → add a MIDI Processor → MidiSpark: MidiSpark.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Text("Hold a chord on the routed keyboard.\nTransport stopped = passthrough · playing = 1/16 arp on output A.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }.padding()
        }
    }
}

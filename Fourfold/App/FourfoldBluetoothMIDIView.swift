//  FourfoldBluetoothMIDIView.swift
//  Bluetooth MIDI (release hygiene, 2026-10-24): Apple's own pairing screen from CoreAudioKit, wrapped for SwiftUI. Pairing a Bluetooth MIDI keyboard or controller is done HERE (or in another app that shows the same screen — AUM does);
//  once paired, the device is just another CoreMIDI source, and `FourfoldMIDI.connectAllSources` (which re-runs on every MIDI setup change) already listens to it. Standalone app only: a plug-in inside AUM never shows this.

import SwiftUI
import CoreAudioKit

struct FourfoldBluetoothMIDIView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController { CABTMIDICentralViewController() }
    func updateUIViewController(_ uiViewController: CABTMIDICentralViewController, context: Context) {}
}

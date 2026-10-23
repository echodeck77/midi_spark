//  FourfoldViewController.swift
//  FOURFOLD Step 1c (2026-10-23, Docs/standalone-plan.md): the Fourfold extension's principal class. Replaces AudioUnitViewController.swift (the 8x8 State host, DiagView), which the FourfoldAU target excludes.
//  The UI is a placeholder until Step 2 ports the Fourfold half of DiagView into a FourfoldRootView.

import CoreAudioKit
import SwiftUI
import UIKit

/// The shared engine class under Fourfold's own MIDI port names (the page calls them MAIN OUT A–D). Step 4 renames the class itself when the engine is copied.
final class FourfoldAudioUnit: MidiSparkAudioUnit {
    public override var midiOutputNames: [String] { ["All", "Out A", "Out B", "Out C", "Out D"] }
}

public class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: FourfoldAudioUnit?

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let au = try FourfoldAudioUnit(componentDescription: componentDescription, options: [])
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
        let host = UIHostingController(rootView: FourfoldPlaceholderView())
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

struct FourfoldPlaceholderView: View {
    var body: some View {
        ZStack {
            Color(red: 0.066, green: 0.075, blue: 0.094).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("FOURFOLD").font(.system(size: 18, weight: .heavy, design: .monospaced)).tracking(8).foregroundColor(.white.opacity(0.9))
                Text("The Fourfold page arrives in Step 2.").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

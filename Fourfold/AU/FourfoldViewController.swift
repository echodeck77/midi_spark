//  FourfoldViewController.swift
//  FOURFOLD Step 1c (2026-10-23, Docs/standalone-plan.md): the Fourfold extension's principal class. Replaces AudioUnitViewController.swift (the 8x8 State host, DiagView), which the FourfoldAU target excludes.
//  The UI is `FourfoldRootView` (Fourfold/Shared): the Fourfold half of DiagView, ported in Step 2.

import CoreAudioKit
import SwiftUI
import UIKit

public class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: FourfoldAudioUnit?
    // UI-CPU fix (2026-11-20): the host calls these appearance callbacks when it shows / hides the plugin view — the
    // reliable "on screen" signal for the AUv3 (SwiftUI's own `.onDisappear` may not fire when a host hides rather than
    // removes the view). While off screen the page freezes its animations; the audio render thread is unaffected.
    private let visibility = FourfoldViewVisibility()

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let au = try FourfoldAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = au
        DispatchQueue.main.async { [weak self] in self?.embedUI() }
        return au
    }

    public override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); visibility.onScreen = true }
    public override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); visibility.onScreen = false }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 760, height: 480)
        if audioUnit != nil { embedUI() }
    }

    private func embedUI() {
        guard children.isEmpty else { return }
        let host = UIHostingController(rootView: FourfoldRootView(au: audioUnit, visibility: visibility))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

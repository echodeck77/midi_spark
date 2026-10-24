//  FourfoldLinkSettingsView.swift
//  Ableton Link sync (2026-10-24 ferry): wraps LinkKit's own `ABLLinkSettingsViewController` for
//  SwiftUI, exactly the pattern Ableton's own LinkHut sample uses (examples/LinkHut/LinkHut/
//  ContentView.swift). This view is NOT optional chrome — per ABLLink.h, "Start Stop Sync Enabled"
//  has no programmatic setter; the user can only turn it on from inside this controller. A fully
//  custom settings UI could show tempo/peers, but could never offer that one switch.

import SwiftUI

#if FOURFOLD_LINK   // ABLETON LINK is OFF until after release — this file compiles to nothing without the flag

struct FourfoldLinkSettingsView: UIViewControllerRepresentable {
    let link: ABLLinkRef

    func makeUIViewController(context: Context) -> ABLLinkSettingsViewController {
        ABLLinkSettingsViewController.instance(link)
    }
    func updateUIViewController(_ uiViewController: ABLLinkSettingsViewController, context: Context) {}
}
#endif

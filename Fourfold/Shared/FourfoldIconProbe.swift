//  FourfoldIconProbe.swift — AU ICON PROBE (DEBUG only; v1 2026-11-18, v2 2026-11-19).
//
//  Paul's Fourfold AU shows NO icon in AUM — and in a second host — while the standalone app's icon is fine, and the
//  appex's built bundle is verifiably complete (Assets.car + loose PNGs + CFBundleIcons / ~ipad / CFBundleIconName).
//  v1 asked the DEVICE the question a host asks — `AudioComponentGetIcon` (deprecated since iOS 13, still shipping) —
//  for our own registered component, and the device answered ICON NO: the system's record for us has no icon.
//
//  v2 turns the next run into a CONTROLLED EXPERIMENT, because ICON NO alone cannot say whether the API path is dead
//  for every v3 extension or deficient only for ours:
//    • our identities: `AudioComponentGetIcon` AND the modern `AVAudioUnitComponent.icon` (iOS 16+), per line;
//    • positive controls: the same two calls across EVERY non-Apple component on the device (on iOS those are all
//      extension-based AUv3s — the plug-ins whose icons DO show in AUM), reported as counts plus the NO names.
//  Readings: controls mostly YES + ours NO → our record/bundle genuinely differs (the full-size icon set shipped with
//  this same build is the fix candidate). Controls ALL NO on GetIcon but YES on .icon → hosts ride the modern path and
//  only .icon matters. Everything NO → neither public API serves icons and hosts use a private path.
//  The simulator returns nil for every extension-based component (no positive control) — device results only.

#if DEBUG
import AVFoundation
import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

/// One registered component and what the system says about its icon through both public APIs.
struct FourfoldIconProbeHit {
    var name: String
    var manufacturer: String
    var version: String
    var typeSubtype: String
    var isOurs: Bool
    var legacyIcon: Bool    // AudioComponentGetIcon (deprecated, the AUM-era API)
    var modernIcon: Bool    // AVAudioUnitComponent.icon (iOS 16+); false below iOS 16
}

/// Every registered audio component, with the system's own icon answers. Main thread; DEBUG only; on-demand (a button runs it).
func fourfoldIconProbeHits() -> [FourfoldIconProbeHit] {
    let any = AudioComponentDescription(componentType: 0, componentSubType: 0, componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
    let all = AVAudioUnitComponentManager.shared().components(matching: any)
    func fourCC(_ v: UInt32) -> String {
        let b = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        return String(bytes: b, encoding: .ascii) ?? String(v)
    }
    var out: [FourfoldIconProbeHit] = []
    for c in all {
        let name = c.name, maker = c.manufacturerName
        let ours = name.localizedCaseInsensitiveContains("fourfold") || maker.localizedCaseInsensitiveContains("outlier")
            || name.localizedCaseInsensitiveContains("euclideous")
            || (fourCC(c.audioComponentDescription.componentManufacturer) == "MSPK" && fourCC(c.audioComponentDescription.componentSubType) == "Frfd")
        var legacy = false, modern = false
        #if canImport(UIKit)
        legacy = AudioComponentGetIcon(c.audioComponent, 44) != nil
        if #available(iOS 16.0, *) { modern = c.icon != nil }
        #endif
        let v = c.versionString.isEmpty ? String(c.version) : c.versionString
        out.append(FourfoldIconProbeHit(name: name, manufacturer: maker, version: v,
                                        typeSubtype: "\(fourCC(c.audioComponentDescription.componentType))/\(fourCC(c.audioComponentDescription.componentSubType))/\(fourCC(c.audioComponentDescription.componentManufacturer))",
                                        isOurs: ours, legacyIcon: legacy, modernIcon: modern))
    }
    return out
}

/// The probe's report for the settings sheet: our identities line by line, then the device-wide positive controls.
func fourfoldIconProbeReport() -> String {
    let hits = fourfoldIconProbeHits()
    guard !hits.isEmpty else { return "No components registered (simulator, or the registry hasn't scanned yet)" }
    func yn(_ b: Bool) -> String { b ? "YES" : "NO" }
    var lines: [String] = []

    // The registry population this process can see — 0 third-party here means the iOS visibility gate (an app without
    // the legacy inter-app-audio entitlement, or an extension's sandbox), not an empty iPad. Debug builds of the
    // standalone app carry the entitlement since 2026-11-19.
    let apple = hits.filter { $0.manufacturer == "Apple" }.count
    lines.append("REGISTRY: \(hits.count) components · Apple \(apple) · 3rd-party \(hits.count - apple)")

    let ours = hits.filter { $0.isOurs }
    if ours.isEmpty { lines.append("⚠︎ no Fourfold component registered") }
    for h in ours {
        lines.append("\(h.name) · \(h.typeSubtype) · v\(h.version) · GetIcon \(yn(h.legacyIcon)) · icon \(yn(h.modernIcon))")
    }
    if ours.count > 1 { lines.append("⚠︎ \(ours.count) Fourfold identities registered — a stale install is likely what hosts list") }

    // Positive controls: every non-Apple component on an iPad is an extension-based AUv3 — the comparable population.
    let controls = hits.filter { !$0.isOurs && $0.manufacturer != "Apple" }
    let gYes = controls.filter { $0.legacyIcon }.count, mYes = controls.filter { $0.modernIcon }.count
    lines.append("CONTROLS (non-Apple): \(controls.count) · GetIcon YES \(gYes) · icon YES \(mYes)")
    if controls.isEmpty {
        // Paul's two 2026-11-19 runs proved this happens in BOTH contexts without the entitlement: a hosted extension's
        // sandbox hides every other plug-in, and an app without inter-app-audio sees only Apple components (the
        // standalone couldn't even see our own extension). With 0 controls nothing in this report is conclusive.
        lines.append("⚠︎ 0 third-party components visible — this process lacks AU-scan visibility. Run the DEBUG standalone app (it carries the inter-app-audio entitlement).")
    }
    let interesting = controls.filter { !$0.legacyIcon || !$0.modernIcon }.prefix(10)
    for h in interesting {
        lines.append("  \(h.name) (\(h.manufacturer)) · GetIcon \(yn(h.legacyIcon)) · icon \(yn(h.modernIcon))")
    }
    if controls.filter({ !$0.legacyIcon || !$0.modernIcon }).count > 10 { lines.append("  …and more NOs not shown") }
    return lines.joined(separator: "\n")
}
#endif

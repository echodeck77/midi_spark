//  FourfoldIconProbe.swift — AU ICON PROBE (DEBUG only, 2026-11-18).
//
//  Paul has reported the Fourfold AU showing NO icon in AUM — and now in a second host — while the standalone app's icon
//  is fine. The appex's built bundle is verifiably complete (Assets.car + loose PNGs + CFBundleIcons / ~ipad /
//  CFBundleIconName), so config guessing is over: this probe asks the DEVICE the exact question a host asks —
//  `AudioComponentGetIcon` (the API AUM-era hosts call; deprecated but shipping) for every registered component whose
//  name or maker looks like ours — and reports what the system actually hands back, per identity. Run it ON THE IPAD
//  from the settings sheet's CLOCK tab (DEBUG builds only): it distinguishes, with data,
//    (a) the system returns an icon and hosts just don't show it   → a host-display matter,
//    (b) the system returns NO icon for the live component          → the device's icon/registration record is the problem,
//    (c) more than one Fourfold identity is registered              → a stale install (the pre-rename com.paulbarrett one)
//                                                                     is what the hosts are actually listing.
//  The simulator returns nil for every extension-based component (no positive control) — device results only.

#if DEBUG
import AVFoundation
import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

/// One registered component that looks like ours, and what the system says about its icon.
struct FourfoldIconProbeHit {
    var name: String
    var manufacturer: String
    var version: String
    var typeSubtype: String
    var hasIcon: Bool
}

/// Every registered audio component whose name or manufacturer matches Fourfold / Outlier / the old MSPK identity,
/// with the system's own icon answer for each. Main thread; DEBUG only; on-demand (a button runs it).
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
        guard name.localizedCaseInsensitiveContains("fourfold") || maker.localizedCaseInsensitiveContains("outlier")
            || name.localizedCaseInsensitiveContains("euclideous") || fourCC(c.audioComponentDescription.componentManufacturer) == "MSPK" && fourCC(c.audioComponentDescription.componentSubType) == "Frfd" else { continue }
        var hasIcon = false
        #if canImport(UIKit)
        hasIcon = AudioComponentGetIcon(c.audioComponent, 44) != nil   // THE host-side question (deprecated since iOS 13, still what hosts get)
        #endif
        let v = c.versionString.isEmpty ? String(c.version) : c.versionString
        out.append(FourfoldIconProbeHit(name: name, manufacturer: maker, version: v,
                                        typeSubtype: "\(fourCC(c.audioComponentDescription.componentType))/\(fourCC(c.audioComponentDescription.componentSubType))/\(fourCC(c.audioComponentDescription.componentManufacturer))",
                                        hasIcon: hasIcon))
    }
    return out
}

/// The probe's one-line-per-identity report for the settings sheet.
func fourfoldIconProbeReport() -> String {
    let hits = fourfoldIconProbeHits()
    guard !hits.isEmpty else { return "No Fourfold component registered (simulator, or the registry hasn't scanned yet)" }
    let lines = hits.map { h in "\(h.name) · \(h.typeSubtype) · v\(h.version) · ICON \(h.hasIcon ? "YES" : "NO")" }
    var s = lines.joined(separator: "\n")
    if hits.count > 1 { s += "\n⚠︎ \(hits.count) identities registered — a stale install is likely what hosts list" }
    return s
}
#endif

//  FourfoldAudioUnit.swift
//  FOURFOLD (2026-10-23): the shared engine class under Fourfold's own MIDI port names (the page calls the outputs MAIN OUT A–D). Used by the extension (`FourfoldViewController`) and by the standalone app, which instantiates it
//  DIRECTLY in-process (no registration, no extension loading) and plays the host for it. Step 4 renames the class itself when the engine is copied.

import AudioToolbox
import Foundation

final class FourfoldAudioUnit: MidiSparkAudioUnit {
    public override var midiOutputNames: [String] { ["All", "Out A", "Out B", "Out C", "Out D"] }

    /// IDENTITY — keep in step with `Fourfold/AU/Info.plist` (type / subtype / manufacturer) and `project.yml` (bundle ids). The standalone app never registers this description (it builds the AU directly); it only needs to be well-formed.
    /// `Frfd` / `MSPK` is a one-way door once anyone has saved an AUM session (plan: "Decisions").
    static let componentDescription = AudioComponentDescription(componentType: kAudioUnitType_MIDIProcessor,
                                                                componentSubType: fourCC("Frfd"), componentManufacturer: fourCC("MSPK"),
                                                                componentFlags: 0, componentFlagsMask: 0)
    private static func fourCC(_ s: String) -> FourCharCode { s.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) } }
}

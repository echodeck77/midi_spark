# MidiSpark — Xcode Scaffold

Container app + AUv3 MIDI-processor extension (`aumi`, four MIDI outputs), per **spec v2.8**.
Scope of this scaffold = **acceptance items 1–3**: load in AUM with four declared outputs,
raw passthrough when stopped, and a host-locked hardcoded 1/16 arp on output A when playing —
the moment the design meets real MIDI.

> Written off-Mac: expect minor compiler fix-ups (API signatures drift between SDK versions),
> not structural ones. Everything uses boring, standard AUv3 plumbing.

## Setup — Path A (recommended): XcodeGen

```bash
brew install xcodegen
cd MidiSparkScaffold
# 1. Edit project.yml: set bundleIdPrefix to your reverse-DNS, DEVELOPMENT_TEAM to your Team ID
xcodegen generate
open MidiSpark.xcodeproj
```

## Setup — Path B: manual Xcode

1. Xcode → New Project → iOS **App** → name `MidiSpark`, SwiftUI, iPad. Replace its Swift files with `App/`.
2. File → New → Target → **Audio Unit Extension** → name `MidiSparkAU`
   (any AU type in the wizard — we overwrite the declaration next). Delete the template's generated
   AU/DSP files; add everything in `AUExtension/`.
3. Replace the extension target's Info.plist content with `AUExtension/Info.plist`
   (this is what declares `aumi` / `MSpk` / `MSPK` and tags MIDI).
4. Both targets: Signing & Capabilities → your team, unique bundle IDs
   (extension ID must be prefixed by the app's, e.g. `com.you.midispark` / `com.you.midispark.au`).

## Signing on a free account
The component name is "MidiSpark: MidiSpark" (Manufacturer: Product); replace the left half with your own dev/brand name in AUExtension/Info.plist if you have one.
Personal Team works: 7-day provisioning, re-deploy weekly. Change `com.example` everywhere
(project.yml + `MidiSparkAudioUnit.stateKey`). First run on device: Settings → General →
VPN & Device Management → trust your certificate.

## Verify in AUM (= acceptance 1–3)

1. Build & run **MidiSpark** (the app) on the iPad once — this registers the extension.
2. Open AUM → `+` → MIDI Processors → **MidiSpark: MidiSpark**. It should list and instantiate. *(item 1)*
3. Check AUM's MIDI routing: MidiSpark exposes **four sources (A–D)**. Route A → any synth,
   and a keyboard → MidiSpark's input. *(item 1)*
4. Transport **stopped**: play the keyboard → notes pass straight through (soundcheck). *(item 1)*
5. Hold a chord, press **play**: an ascending 1/16 arp on output A, locked to AUM's clock.
   Change tempo mid-hold; loop a section; relocate — the arp must follow with zero drift,
   because position is derived, never accumulated. *(items 2–3)*
6. Stop with notes sounding: no stuck notes (transport-edge all-notes-off). *(item 2)*

If the plugin doesn't appear in AUM: reboot the iPad once (AU registration cache),
confirm the extension's Info.plist made it into the build, and that `sandboxSafe` is true.

## What's here

```
project.yml                          XcodeGen definition (targets, embed, signing knobs)
App/                                 Container app (registers the extension; instructions screen)
AUExtension/
  Info.plist                         aumi declaration: type/subtype/manufacturer, MIDI tag
  MidiSparkAudioUnit.swift            AUAudioUnit: midiOutputNames ["A","B","C","D"],
                                     35-parameter tree (STABLE addresses: 0 stepRate, 1 swing,
                                     100+i transpose, 200+i morph, 300 morphMaster — never renumber),
                                     fullState = the host-level Preset (spec §1), render plumbing
  Kernel.swift                       Render kernel: omni note pool, derived playhead,
                                     passthrough-when-stopped, hardcoded UP arp on cable A,
                                     all-notes-off on transport edges
  Models.swift                       Spec §9 schema: Colour / Cell / SceneState / PluginState,
                                     Codable, factory session
  AudioUnitViewController.swift      Extension UI host + placeholder SwiftUI view
```

## Build order from here (per spec + our plan)

1. **Prove sync** (this scaffold): acceptance 1–3 pass in AUM.
2. **Snapshot bridge** (spec §7): flat, atomically-swapped engine state; kernel reads snapshots,
   never the document. Replace the kernel's hardcoded arp with snapshot-driven cells.
3. **Router**: sender-decides derivation, buses, OUT CH stamping, collision refcount (§7 v2.3).
4. **Processors**: ARP (full: patterns, rates, octaves, gate, PHASE modes) → RATCHET → PASSGATE →
   STRUM/CHANCE/HARMONIZE. Note tracker invariants throughout (acceptance 4–6).
5. **UI**: the grid + wiring visualisation, porting `midispark-preview-v26.html` into SwiftUI
   (after the COLOUR-panel layout pass). Then performance layers, audition, Launchpad.
6. Regenerate the stale architecture/domain diagrams once the snapshot layout is real.

Known scaffold shortcuts (all TODO-tagged in source): incoming-MIDI passthrough copies only
3-byte messages; no MIDI 2 event-list path; parameters write to the document directly instead
of through the snapshot; the arp ignores swing/step-rate (fixed 1/16). All are replaced in
build-order steps 2–4.

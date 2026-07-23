# MidiSpark — shipping as "8x8 State"

Container app + AUv3 MIDI-processor extension (`aumi`) for iPadOS. An 8×8 grid
sequences MIDI *processors* (arps, ratchets, gates) over time; held chords go
in, five MIDI outputs come out — ALL + A–D (delta §7b cables). Primary host: AUM.
Public name **"8x8 State"** (display-only; the code/bundle identity stays MidiSpark).

**Spec:** `Docs/midispark-spec-v2.8.md` read together with
`Docs/midispark-spec-v3.0-delta.md` (the delta wins conflicts).
**Live status and the current plan:** `CLAUDE.md`.
**UI reference:** the built plugin is the living reference for shipped features;
`Docs/midispark-preview-v60.html` (now exported, with v59) is the behavioural
spec for unbuilt ones — currently the §6a emitter toggles and the §5b lap visuals.

> Status in one line: the v3.0 graph-routing migration is DONE; all six processors,
> channels/outputs, graph routing, the full GUI reconcile, the perform layer, and
> audition (all types) are built and DEVICE-VERIFIED, with an 89-test off-device suite
> covering the render engine itself. Next is PERFORM v2 (stutter/isolate — engine-blocked
> + spec-pending). See CLAUDE.md; do not code from this README.

## Setup — Path A (recommended): XcodeGen

```
brew install xcodegen
# 1. Edit project.yml: set bundleIdPrefix to your reverse-DNS, DEVELOPMENT_TEAM to your Team ID
xcodegen generate
open MidiSpark.xcodeproj
```

## Setup — Path B: manual Xcode

1. Xcode → New Project → iOS **App** → name `MidiSpark`, SwiftUI, iPad. Replace its Swift files with `App/`.
2. File → New → Target → **Audio Unit Extension** → name `MidiSparkAU` (any AU type in the wizard — we overwrite the declaration next). Delete the template's generated AU/DSP files; add everything in `AUExtension/`.
3. Replace the extension target's Info.plist content with `AUExtension/Info.plist` (this is what declares `aumi` / `MSpk` / `MSPK` and tags MIDI).
4. Both targets: Signing & Capabilities → your team, unique bundle IDs (extension ID must be prefixed by the app's, e.g. `com.you.midispark` / `com.you.midispark.au`).

## Signing on a free account

The component name is "8x8 State: 8x8 State" (Manufacturer: Product; the aumi
codes stay `MSpk`/`MSPK`). Personal Team works: 7-day provisioning, re-deploy
weekly. First run on device:
Settings → General → VPN & Device Management → trust your certificate.

## Verify in AUM

Smoke test (scaffold-era acceptance 1–3 still apply): instantiate under MIDI
Processors, route outputs to synths and a keyboard to the input, passthrough
when stopped, host-locked playing behaviour with zero drift across tempo
changes / loops / relocations, no stuck notes on stop. Full device
verification lives in `Docs/test-procedures.md` (canned sessions loaded from the
DEV LOADER in the portrait plugin UI — the in-plugin diagnostics panel was removed;
the AUM MIDI monitor is the source of truth; the repo's T-numbering is authoritative).

If the plugin doesn't appear in AUM: reboot the iPad once (AU registration
cache), confirm the extension's Info.plist made it into the build, and that
`sandboxSafe` is true.

## What's here

```
project.yml                          XcodeGen definition (targets, embed, signing, test target)
App/                                 Container app (registers the extension; instructions screen; AppIcon)
AUExtension/
  Info.plist                         aumi declaration: type/subtype/manufacturer, MIDI tag
  MidiSparkAudioUnit.swift           AUAudioUnit: midiOutputNames (ALL + A–D), 35-parameter tree (STABLE
                                     addresses: 0 stepRate, 1 swing, 100+i transpose, 200+i morph,
                                     300 morphMaster), fullState = host Preset (§1); setColourType
  Kernel.swift                       INPUT side + render boundary: transport/context derivation, incoming
                                     MIDI (source pool + passthrough + CC), param events, audition
                                     suppression → Router; hosts LiveMIDIEmitter (the one AudioToolbox user)
  Router.swift                       OUTPUT side (§2/§7), Foundation-only: grid columns, v3.0 GRAPH routing
                                     (receiver-picked references, reroute, cycles), all six processors,
                                     fan-out, the voice table + 5-cable collision refcount, AUDITION
  Emission.swift                     The MIDIEmitter seam (delta §7b): Router emits through this, not
                                     AudioToolbox → the whole engine unit-tests off-device
  Derivations.swift                  PURE core (Foundation-only, unit-tested): NotePool, swing warp,
                                     phase indexing, arp patterns, cellMode dispatch, processor math
  Snapshot.swift                     Flat snapshot schema + effective-param morph (§3.2/§13.5), pure
  SnapshotStore.swift                Atomic publish/acquire bridge (the one swift-atomics user)
  SnapshotBuilder.swift              document → SnapshotBox: B-over-A resolve, enum→index, run-starts
  Diag.swift                         KernelDiag (pure) — render-side counters threaded through the pass
  Models.swift                       Spec §9 schema: Colour / Cell / SceneState / PluginState, Codable
  GridUI.swift                       The 8×8 grid + palette + PROCESSOR box + OUTPUTS (SwiftUI-only)
  SceneFactory.swift                 The sixteen factory scenes (Foundation-only; Docs/factory-scenes.md)
  TestSessions.swift                 T1–T17 canned patches, loaded from the DEV LOADER (portrait UI)
  AudioUnitViewController.swift      Extension UI host: the grid / responsive DESK / scene strip (4 Hz
                                     poll drives the playheads; no diagnostics panel)
Tests/                               Off-device unit tests (macOS MidiSparkTests target, 89 tests over the
                                     pure core AND the render engine — first line of verification; green
                                     through every commit)
Docs/                                Specs, migration plan, test playbook, factory scenes, UI guide, mockups
```

## Where the plan lives (this section intentionally does not duplicate it)

The build order that used to sit here described the pre-v3.0 model and is
retired; the v3.0 graph-routing migration and GUI reconciliation (to preview
v59) are both DONE. The single source of truth for what to do next is
**CLAUDE.md** (status + doc index). Behaviour questions go to the spec + delta;
device verification goes to Docs/test-procedures.md.

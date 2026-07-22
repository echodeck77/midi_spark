# MidiSpark — working title "8x8 State"

Container app + AUv3 MIDI-processor extension (`aumi`) for iPadOS. An 8×8 grid
sequences MIDI *processors* (arps, ratchets, gates) over time; held chords go
in, bus outputs come out (currently four cables A–D; becomes five — ALL + A–D —
with the v0.5 outputs work). Primary host: AUM.

**Spec:** `Docs/midispark-spec-v2.8.md` read together with
`Docs/midispark-spec-v3.0-delta.md` (the delta wins conflicts).
**Live status and the current plan:** `CLAUDE.md` → `Docs/migration-tree-routing.md`.
**UI reference:** `Docs/midispark-preview-v56.html` (open in a browser).

> Status in one line: router complete under the OLD chain model
> (tag `v0.3-router`), five of six processors built, a first SwiftUI grid
> slice exists — the current task is the survey-first migration to the v3.0
> graph-routing model, then GUI reconciliation. See CLAUDE.md; do not code
> from this README.

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

The component name is "MidiSpark: MidiSpark" (Manufacturer: Product). Personal
Team works: 7-day provisioning, re-deploy weekly. First run on device:
Settings → General → VPN & Device Management → trust your certificate.

## Verify in AUM

Smoke test (scaffold-era acceptance 1–3 still apply): instantiate under MIDI
Processors, route outputs to synths and a keyboard to the input, passthrough
when stopped, host-locked playing behaviour with zero drift across tempo
changes / loops / relocations, no stuck notes on stop. Full device
verification lives in `Docs/test-procedures.md` (canned sessions loaded from
the diagnostic panel; the repo's T-numbering is authoritative).

If the plugin doesn't appear in AUM: reboot the iPad once (AU registration
cache), confirm the extension's Info.plist made it into the build, and that
`sandboxSafe` is true.

## What's here

```
project.yml                          XcodeGen definition (targets, embed, signing, test target)
App/                                 Container app (registers the extension; instructions screen)
GridUI/                              SwiftUI grid slice (work-in-progress; reconciliation target = preview v56)
AUExtension/
  Info.plist                         aumi declaration: type/subtype/manufacturer, MIDI tag
  MidiSparkAudioUnit.swift           AUAudioUnit: midiOutputNames, 35-parameter tree (STABLE
                                     addresses: 0 stepRate, 1 swing, 100+i transpose, 200+i morph,
                                     300 morphMaster), fullState = host Preset (§1)
  Kernel.swift                       INPUT side: transport/context derivation, incoming MIDI
                                     (source pool + passthrough + CC), param events → Router
  Router.swift                       OUTPUT side (§2/§7): grid columns, routing derivation, per-cell
                                     processors, fan-out, the voice table + collision refcount
                                     (chain model as built — migrating per Docs/migration-tree-routing.md)
  Derivations.swift                  PURE core (Foundation-only, unit-tested): NotePool, swing warp,
                                     phase indexing, arp patterns, cellMode dispatch, processor math
  Snapshot.swift                     Flat snapshot schema + effective-param morph (§3.2/§13.5), pure
  SnapshotStore.swift                Atomic publish/acquire bridge (the one swift-atomics user)
  SnapshotBuilder.swift              document → SnapshotBox: B-over-A resolve, enum→index, run-starts
  Models.swift                       Spec §9 schema: Colour / Cell / SceneState / PluginState, Codable
  TestSessions.swift                 T1–T16 canned patches, loaded from the diagnostic panel
  AudioUnitViewController.swift      Extension UI host + the live diagnostic panel (4 Hz)
Tests/                               Off-device unit tests (macOS MidiSparkTests target, 42 tests —
                                     first line of verification; keep green through every commit)
Docs/                                Specs, migration plan, test playbook, UI guide, preview mockups
```

## Where the plan lives (this section intentionally does not duplicate it)

The build order that used to sit here described the pre-v3.0 model and is
retired. The single source of truth for what to do next is **CLAUDE.md**
(status + doc index) and **Docs/migration-tree-routing.md** (the sequenced
plan: engine migration commits, then GUI reconciliation to preview v56).
Behaviour questions go to the spec + delta; device verification goes to
Docs/test-procedures.md.

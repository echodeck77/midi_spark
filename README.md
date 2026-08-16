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
spec for unbuilt ones — currently the §5 rev 2 CELL EDITOR, the §6a
channel-strip perform face, and undo/redo (CLAUDE.md a5–a7; v60 predates
these revs — the delta wins).

> Status in one line: the v3.0 graph-routing migration is DONE; fifteen processor
> types, channels/outputs, graph routing, receivers (with LATCH + controller routing),
> macros (with the authoring flow), the RACK, and audition (all types) are built and
> DEVICE-VERIFIED, with a 600+-test off-device suite covering the render engine itself.
> The UI is now a TAB shell (BUILD · GRID · MIDI IN · MIDI OUT · MACROS · AUTOMATION);
> the BUILD page is the primary workshop and default landing tab — it superseded the old
> DRAG&DROP + PROCESSORS/cell-edit pages. A/B-state morph was removed from the render.
> See CLAUDE.md for live status; do not code from this README.

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
verification lives in `Docs/test-procedures.md` (the large in-plugin diagnostics panel
was reduced to a compact dev stuck-note monitor, and the canned T-session loader was
replaced by the developer self-test panel — long-press the "8×8 STATE" logotype; for
MIDI verification the AUM monitor is the source of truth; the repo's T-numbering is
authoritative).

If the plugin doesn't appear in AUM: reboot the iPad once (AU registration
cache), confirm the extension's Info.plist made it into the build, and that
`sandboxSafe` is true.

## What's here

```
project.yml                          XcodeGen definition (targets, embed, signing, test target)
App/                                 Container app (registers the extension; instructions screen; AppIcon)
AUExtension/
  Info.plist                         aumi declaration: type/subtype/manufacturer, MIDI tag
  MidiSparkAudioUnit.swift           AUAudioUnit: midiOutputNames (ALL + A–D), parameter tree (STABLE
                                     addresses: 0 stepRate, 1 swing, 100+i transpose, 200+i morph,
                                     300 morphMaster, 400+i macro ×8), fullState = host Preset (§1); setColourType
  Kernel.swift                       INPUT side + render boundary: transport/context derivation, incoming
                                     MIDI (source pool + passthrough + CC), param events, audition
                                     suppression → Router; hosts LiveMIDIEmitter (the one AudioToolbox user)
  Router.swift                       OUTPUT side (§2/§7), Foundation-only: grid columns, v3.0 GRAPH routing
                                     (receiver-picked references, reroute, cycles), all 15 processor types,
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
  BuildPage.swift                    THE BUILD PAGE — the primary workshop + default tab (cast / part-staging /
                                     PLAY grid / chain footer; SELECT·PLACE·MUTATE row modes; ephemeral colours)
  SceneFactory.swift                 The sixteen factory scenes (Foundation-only; Docs/factory-scenes.md)
  TestSessions.swift                 T1–T17 canned patches (the in-app loader is retired; now dev-only)
  AudioUnitViewController.swift      Extension UI host: the TAB shell (BUILD·GRID·MIDI IN·MIDI OUT·MACROS·
                                     AUTOMATION) / grid / responsive DESK (4 Hz poll drives the playheads)
Tests/                               Off-device unit tests (macOS MidiSparkTests target, 600+ tests over the
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

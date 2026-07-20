# MidiSpark — project briefing

AUv3 MIDI processor (`aumi`) for iPadOS. One line: **"Don't sequence notes. Sequence what
happens to them."** An 8×8 grid sequences MIDI *processors* (arps, ratchets, gates) over
time; held chords go in, four independent MIDI outputs (A–D) come out. Primary host: AUM.

## Authoritative documents (read before designing anything)
- `docs/midispark-spec-v2.8.md` — THE spec (consolidated, self-contained: all 13 sections,
  28 acceptance items). Behaviour changes require a spec revision first.
- `docs/router-design.md` — the step-3 engineering plan: processing model (chains pass
  time-varying POOLS, not event streams), derivation algorithm, voice/refcount design,
  the testability-first rule (TestSessions before router code), commit plan. START HERE
  for step 3.
- `docs/test-procedures.md` — the device playbook: canned sessions T1–T8, bridge
  regression B1–B4, milestone gates, and the reporting template. When asking the human
  to verify anything, quote the procedure by name.
- `docs/ui-port-guide.md` — step 5: mockup→SwiftUI mapping, design tokens (the 16 Colour
  hexes are canonical), gesture map, porting order.
- `docs/midispark-architecture.mermaid`, `docs/midispark-domain-model.mermaid` — runtime + schema maps.
- `BRIDGE_NOTES.md` — snapshot bridge design + hear-it tests.
- `docs/midispark-preview-v26.html` — the GUI reference mockup (open in a browser); the
  behavioural spec for the UI.

## Vocabulary (spec §1 — enforced, including in code comments and UI strings)
- **Colour** = the treatment (type + params + A/B states + morph). 16 of them. Never "preset".
- **Cell** = one Colour placed at a grid position with its own wiring/state.
- **Preset** = ONLY the host-level fullState document. Nothing inside the app uses this word.

## Architecture invariants (violating these = bug, regardless of tests passing)
1. **The render thread reads ONLY `SnapshotBox`** (immutable, atomically published).
   It never touches `PluginState`. UI/document → `SnapshotBuilder` → `SnapshotStore.publish`
   (MAIN THREAD ONLY) → kernel `acquire()` (one atomic load, no locks, no allocation).
2. **Derived, never accumulated:** playhead, arp phase, swing — all pure functions of host
   beat position. No timers, no counters that persist across renders (the note tracker and
   the param-override table are the sanctioned exceptions; see Kernel.swift comments).
3. **No allocation / locks / ObjC dispatch on the render path.** Fixed-size storage only.
4. **No stuck notes, ever:** every transition (transport edge, mute, edit, column change)
   closes sounding notes; note-offs will be reference-counted per (bus, channel, note)
   when the router lands (spec §7 collision policy).
5. **Parameter addresses are STABLE forever:** 0 stepRate · 1 swing · 100+i transpose ·
   200+i morph · 300 morphMaster. Add new addresses; never renumber or reuse.
6. Host parameter changes arrive via TWO routes: tree setValue (observer → snapshot) and
   render-side `.parameter/.parameterRamp` events (kernel override table, cleared on each
   new snapshot generation). Keep both paths working.

## Build system gotchas (learned the hard way)
- The `.xcodeproj` is a BUILD ARTEFACT. `xcodegen generate` after ANY file add/remove or
  project.yml change. Editing existing files needs nothing.
- `AUExtension/Info.plist` is HAND-MAINTAINED (declares the `aumi` audio component:
  type `aumi`, subtype `MSpk`, manufacturer `MSPK`). It is excluded from XcodeGen's
  `info:` generation deliberately — never add an `info:` block to the MidiSparkAU target,
  and never let the plist into sources without the exclude. XcodeGen will silently gut it.
- Extension bundle ID must be prefixed by the app's:
  app `com.paulbarrett.MidiSpark`, extension `com.paulbarrett.MidiSpark.AU` (explicit
  PRODUCT_BUNDLE_IDENTIFIER in the MidiSparkAU target).
- Compile check from CLI: `xcodegen generate && xcodebuild -project MidiSpark.xcodeproj
  -scheme MidiSpark -destination 'generic/platform=iOS' build` (signing may need the
  user's team set; building for *device install* happens in Xcode).
- Device testing is manual: the human runs from Xcode onto the iPad and verifies in AUM.
  You cannot hear anything. When behaviour needs verification, say exactly what to check
  in AUM (the diagnostic panel in the plugin UI shows live kernel state at 4 Hz).

## Current status (update this section as work lands)
- DONE step 1 (scaffold): loads in AUM, 4 MIDI outputs, passthrough stopped, hardcoded
  gold arp playing, derived sync verified.
- DONE step 2 (snapshot bridge): kernel is snapshot-driven; morph/master/swing/stepRate
  live end-to-end; render-side param events handled; CC passthrough on cable A always;
  diagnostic UI in the extension.
- NEXT step 3 (the ROUTER): kernel consumes `SnapshotBox.cells` (busMask, stack, srcMix,
  runStartColumn already carried): sender-decides chain derivation (§2), per-cell processor
  invocation (§1.1: cells are independent; Colours are definitions), bus emission with
  OUT CH stamping (§2.6), collision refcount (§7). Replaces the hardcoded demo arp.
- THEN step 4: full processors (ARP patterns + PHASE modes, RATCHET, PASSGATE, STRUM,
  CHANCE, HARMONIZE) against acceptance items 4–6; step 5: SwiftUI grid UI (port of
  preview v26) — but the COLOUR-panel layout pass in the spec's pending list comes first.
- Acceptance checklist: spec §11, 28 items. Tag milestones (`v0.1-scaffold` exists;
  tag `v0.2-bridge` once the bridge tests pass on device).

## Style
- Swift, no external deps beyond apple/swift-atomics (SPM, already in project.yml).
- Comments cite spec sections (e.g. `// §3.2: stepped fields quantize`). Keep doing this —
  the spec is the contract, and drift between code and spec is the project's main risk.

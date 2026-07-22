# MidiSpark — project briefing

AUv3 MIDI processor (`aumi`) for iPadOS. One line: **"Don't sequence notes. Sequence what
happens to them."** An 8×8 grid sequences MIDI *processors* (arps, ratchets, gates) over
time; held chords go in, four independent MIDI outputs (A–D) come out. Primary host: AUM.

## Authoritative documents (read before designing anything)
- `Docs/midispark-spec-v2.8.md` — the base spec (consolidated, self-contained) —
  **read together with `Docs/midispark-spec-v3.0-delta.md`, which supersedes the
  routing model (§2: receiver-picked references — any row, cycles legal-and-
  silent, fan-out; ▾/+SRC/OUT CH/INHERIT removed; channels are filter-in/
  stamp-out; outputs are ALL + A–D cables) and the perform visual language
  (§5: four-row text cells, arrow playhead, one-clock rule) and the desk
  (§6: responsive performance surface).** Where they conflict, the delta wins. Behaviour
  changes still require a spec revision first.
- `Docs/migration-tree-routing.md` — **THE CURRENT TASK**: the router exists and
  works under the old chain model, and a first grid-UI slice exists built to an
  earlier visual generation; this is the survey-first migration plan to the
  v3.0 graph model (6 engine changes + GUI reconciliation, green-suite commits,
  saved-session compatibility). Read it before touching ANY of
  Router/Snapshot/TestSessions/the grid UI.
- `Docs/router-design.md` — the engine reference (pools/sounding-sets model,
  voice/refcount design, PHASE formulas, per-render flow). Its routing
  derivation and commit plan are marked HISTORICAL (old model, as built);
  use it for what the migration's guard-rail says not to touch.
- `Docs/test-procedures.md` — the device playbook: canned sessions T1–T11, bridge
  regression B1–B4, milestone gates, and the reporting template. When asking the human
  to verify anything, quote the procedure by name.
- `Docs/ui-port-guide.md` — mockup→SwiftUI mapping, design tokens (the 16 Colour
  hexes are canonical), gesture map, and the REVISED order of work (a grid
  slice exists; reconcile, don't rebuild).
- `Docs/midispark-architecture.mermaid`, `Docs/midispark-domain-model.mermaid` — runtime + schema maps.
- `BRIDGE_NOTES.md` — snapshot bridge design + hear-it tests.
- `Docs/midispark-preview-v53.html` — the GUI reference mockup (open in a browser);
  the behavioural spec for the UI. v26–v49 are history; v50/v51 are BROKEN
  (JSX bug) — never open as reference; v40 is the preserved abandoned fork
  (module boxes / linear chains) — do not implement it.

## Vocabulary (spec §1 — enforced, including in code comments and UI strings)
- **Colour** = the treatment (type + params + A/B states + morph). 16 of them. Never "preset".
- **Cell** = one Colour placed at a grid position with its own wiring/state.
- **Preset** = ONLY the host-level fullState document. Nothing inside the app uses this word.
- **Emitter** = a bus A–D as the user-facing concept (its cable + its channel stamp).
- Product name candidate: **"8x8 State"** (display name only, undecided);
  bundle IDs stay `com.paulbarrett.MidiSpark` FOREVER regardless.

## Architecture invariants (violating these = bug, regardless of tests passing)
1. **The render thread reads ONLY `SnapshotBox`** (immutable, atomically published).
   It never touches `PluginState`. UI/document → `SnapshotBuilder` → `SnapshotStore.publish`
   (MAIN THREAD ONLY) → kernel `acquire()` (one atomic load, no locks, no allocation).
2. **Derived, never accumulated:** playhead, arp phase, swing — all pure functions of host
   beat position. No timers, no counters that persist across renders (the note tracker and
   the param-override table are the sanctioned exceptions; see Kernel.swift comments).
3. **No allocation / locks / ObjC dispatch on the render path.** Fixed-size storage only.
4. **No stuck notes, ever:** every transition (transport edge, mute, edit, column change)
   closes sounding notes; note-offs are reference-counted per EMITTED
   (cable, channel, note) — five cables once ALL lands (spec §7 collision
   policy + delta §7b).
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
- DONE step 3 (the ROUTER) — **under the OLD chain model** (▾/srcMix,
  sender-decides, OUT CH). Works; tagged `v0.3-router`.
- DONE step 4 (mostly): FIVE of six processors built (ARP/RATCHET/PASSGATE/
  STRUM/CHANCE); **HARMONIZE outstanding** (identity until built).
- DONE (partial) grid UI: a first SwiftUI grid slice exists, built to an
  earlier visual generation.
- Test assets: `TestSessions.swift` carries **T1–T16** (numbering authority —
  see test-procedures preamble) and `Tests/` holds a **42-test macOS unit
  suite** over the pure core (Derivations.swift). BOTH must stay green
  through every commit; unit tests run off-device and come FIRST.
- **NEXT: THE MIGRATION** (Docs/migration-tree-routing.md): engine commits 1–5
  to the v3.0 graph model + outputs, THEN GUI reconciliation to preview v53.
  Survey-first on everything. Old saved AUM sessions must load and convert.
- THEN: HARMONIZE (the step-4 remainder) and the remaining UI passes per
  ui-port-guide's revised order.
- Acceptance checklist: spec §11, 28 items. Tag milestones (`v0.1-scaffold` exists;
  tag `v0.2-bridge` once the bridge tests pass on device).

## Style
- Swift, no external deps beyond apple/swift-atomics (SPM, already in project.yml).
- Comments cite spec sections (e.g. `// §3.2: stepped fields quantize`). Keep doing this —
  the spec is the contract, and drift between code and spec is the project's main risk.

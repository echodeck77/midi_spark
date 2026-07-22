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
- `Docs/migration-tree-routing.md` — the survey-first plan for the v3.0 graph-routing
  migration. Its ENGINE commits (1–5) are DONE and tagged (see status); its GUI
  reconciliation section is the live task. Read it before touching Router/Snapshot/
  TestSessions/the grid UI.
- `Docs/standalone-plan.md` — DEFERRED milestone (standalone app = a second HOST of
  the same AUv3), but its THREE SEAM RULES are enforced NOW: (1) import hygiene —
  only `MidiSparkAudioUnit.swift` / `AudioUnitViewController.swift` may import
  AudioToolbox/AU frameworks; Kernel/Router/Derivations/Snapshot*/Models/TestSessions
  and ALL of GridUI stay Foundation/SwiftUI-only (GridUI is shared by both targets).
  (2) one-named beat seam. (3) emission is the only place that knows cables. KNOWN
  VIOLATION: Kernel.swift + Router.swift still import AudioToolbox (AU event/time
  types) — fix when the standalone milestone opens or when those files are touched
  for that purpose; GridUI is already clean (SwiftUI-only).
- `Docs/router-design.md` — the engine reference (pools/sounding-sets model,
  voice/refcount design, PHASE formulas, per-render flow). Its routing
  derivation and commit plan are marked HISTORICAL (old model, as built);
  use it for what the migration's guard-rail says not to touch.
- `Docs/test-procedures.md` — the device playbook: canned sessions (repo carries
  T1–T17; the doc details T1–T11 + reconciled intents), bridge regression B1–B4,
  the UI-size-checkpoint gate, milestone gates, and the reporting template. When
  asking the human to verify anything, quote the procedure by name.
- `Docs/factory-scenes.md` — the SIXTEEN factory scenes for the scene strip (a
  curriculum, slot 1 → 16; slot 15's cycle/backward-tap are INTENTIONAL; every
  LISTEN line ships ear-tested). Distinct from TestSessions T1–T17 — never merge.
- `Docs/ui-port-guide.md` — mockup→SwiftUI mapping, design tokens (the 16 Colour
  hexes are canonical), gesture map, and the REVISED order of work (a grid
  slice exists; reconcile, don't rebuild).
- `Docs/midispark-architecture.mermaid`, `Docs/midispark-domain-model.mermaid` — runtime + schema maps.
- `BRIDGE_NOTES.md` — snapshot bridge design + hear-it tests.
- `Docs/midispark-preview-v59.html` — the GUI reference mockup (open in a browser);
  the behavioural spec for the UI. v57 added PROMINENT COLUMN KEYS (40px,
  number-primary, state as hue+sublabel); v58 the STATIC FRAMES rule made
  visible; v59 the SIXTEEN-slot scene strip. v26–v58 are history; v50/v51 are
  BROKEN (JSX bug) — never open as reference; v40 is the preserved abandoned
  fork (module boxes / linear chains) — do not implement it. The mockup's
  AUTO/WIDE/TALL toggle is a browser preview affordance — never port it.

## Vocabulary (spec §1 — enforced, including in code comments and UI strings)
- **Colour** = the treatment (type + params + A/B states + morph). 16 of them. Never "preset".
- **Cell** = one Colour placed at a grid position with its own wiring/state.
- **Preset** = ONLY the host-level fullState document. Nothing inside the app uses this word.
- **Emitter** = a bus A–D as the user-facing concept (its cable + its channel stamp).
- Product name candidate: **"8x8 State"** (the v54+ mockups display it as the
  logotype; still display-name-only and undecided); bundle IDs and code-level
  product strings stay `MidiSpark` / `com.paulbarrett.MidiSpark` regardless.

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
- Compile check from CLI (the `DEVELOPER_DIR` prefix is REQUIRED — `xcode-select`
  points at CommandLineTools, whose older Swift can't parse the Xcode SDK):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project
  MidiSpark.xcodeproj -scheme MidiSpark -destination 'generic/platform=iOS'
  CODE_SIGNING_ALLOWED=NO build`. Prepend `xcodegen generate &&` only after
  adding/removing files. *Device install* happens in Xcode.
- Off-device unit tests (FIRST line of verification, ~seconds, no simulator):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test
  -project MidiSpark.xcodeproj -scheme MidiSparkTests -destination
  'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData`. The pinned
  `-derivedDataPath` is REQUIRED: the default DerivedData intermittently serves a
  STALE test bundle (old count, hidden failures). The macOS `MidiSparkTests`
  target compiles the Foundation-only pure sources directly (no iOS/CoreAudio
  link); keep new pure logic in Derivations.swift so it stays testable.
- Device testing is manual: the human runs from Xcode onto the iPad and verifies in AUM.
  You cannot hear anything. When behaviour needs verification, say exactly what to check
  in AUM (the diagnostic panel in the plugin UI shows live kernel state at 4 Hz).

## Current status (update this section as work lands)
- DONE steps 1–2 (scaffold + snapshot bridge): loads in AUM, MIDI outputs,
  passthrough stopped, derived sync, snapshot-driven kernel, render-side param
  events, diagnostic UI.
- DONE step 3 (the ROUTER) — shipped under the OLD chain model, tagged
  `v0.3-router` (HISTORICAL).
- DONE step 4 — ALL SIX processors built (ARP incl. all 5 patterns + 3 PHASE modes /
  RATCHET / PASSGATE / STRUM / CHANCE / HARMONIZE). cellMode has no identity-fallback
  default left; the roster is complete.
- **DONE — THE MIGRATION to v3.0 graph routing** (Docs/migration-tree-routing.md),
  engine complete:
  - `v0.4-graph-routing` (tag): receiver-picked `inputRow` references replace
    ▾/+SRC — any row, cycles legal-and-silent, fan-out. Loader migrates v2
    saved sessions on load (stack→inputRow). Precompute: resolvedParent/isTapped.
  - `v0.5-outputs` (tag): channels are filter-in (`inputChannel`, OMNI default) /
    stamp-out (`busChannels`, default 1-4); OUT CH & INHERIT removed; FIVE cables
    (All + Emit A–D), every note emitted on its own cable + All; refcount keys on
    the EMITTED (cable, channel, note). Labels: "All", "Emit A"…"Emit D".
- **ENGINE FEATURE-COMPLETE and fully device-verified** — tag `v0.6-processors`.
  The full manual suite (T1–T17 + B1–B4) passes on device; graph routing +
  channels/outputs + all six processors, zero stuck notes. `TestSessions.swift`
  carries **T1–T17** (numbering authority — see test-procedures preamble);
  `Tests/` holds a **63-test macOS unit suite** over the pure core
  (Derivations + Snapshot/Builder + loader migration + SceneFactory). BOTH stay
  green every commit; unit tests run off-device and come FIRST.
- **GUI RECONCILE — DONE** (`GridUI.swift`, all SwiftUI-only; target preview
  **v59**). Shipped: header (STEP rate + SWING + PASS/bpm readout, params 0/1);
  FOUR-ROW cells (input header · type+params body · A–D emitter strip · empty-cell
  watermark); real FROM/OUT POPOVERS (not cycling chips); fully in-cell EDITING
  (tap body = paint/recolour, long-press = clear/copy colour); the PROCESSOR box
  (all 6 types, A/B state tabs, per-type params, TRANSPOSE, MORPH — fixed-size box,
  static-frames rule); OUTPUTS busChannels editing; cell badges (transpose · ∞) +
  breathing ALT ring; the one-clock playheads (master sweep + per-cell MUTATION
  LINES via TimelineView beat extrapolation between the 4 Hz polls); the delta §6
  three-box responsive DESK (COLOUR·PROCESSOR·EMITTERS, landscape column / portrait
  band); the PROMINENT COLUMN KEYS (v57, tappable); the SIXTEEN-slot SCENE strip
  (dev builds wire session slots, release wires `SceneFactory`). The debug
  diagnostics + wiring lanes are REMOVED. The instrument is fully authorable
  in-plugin — no host automation needed for any control.
- **PERFORM LAYER v1 — DONE, device-verified** (`53d3591`, §6.1/6.2). EDIT/PERFORM
  mode toggle; TAP action selector (ALT/BYP/MUTE); in PERFORM the whole pad is one
  tap target (applies the TAP action via the engine-backed cell flags the router
  reads — alt/bypassed/muted), and a column-key tap mutes/unmutes the whole column
  (coral indicator). EDIT keeps painting + popovers + long-press menu. User: "it
  feels good. There are issues we can come back to with a revised spec."
- **NEXT:** (a) GATE — the UI-size checkpoints in test-procedures (screenshot-verify
  1024×768 / 11" / 13" both orientations + a small panel; static frames hold,
  nothing truncates) — the formal layout lockdown, not yet run. (b) PERFORM v2 —
  stutter/loop (hold column key), isolate/solo, hold-to-stutter — all **engine-
  blocked** on the lock/effColumn override (`lockLo/lockHi` currently STUBBED in
  Router as `effColumn == trueColumn`) AND **spec-pending** (user flagged perform
  issues for a revised spec). (c) MORPH desk (16 faders) — parked per delta.
- Acceptance checklist: spec §11 (+ delta §8 items 29–32). Tags shipped:
  `v0.1-scaffold`, `v0.2-bridge`, `v0.3-router`, `v0.4-graph-routing`,
  `v0.5-outputs`, `v0.6-processors`. The GUI reconcile + perform-layer v1 are on
  main **untagged** (next tag candidate `v0.7-gui`, pending the size-checkpoint gate).

## Style
- Swift, no external deps beyond apple/swift-atomics (SPM, already in project.yml).
- Comments cite spec sections (e.g. `// §3.2: stepped fields quantize`). Keep doing this —
  the spec is the contract, and drift between code and spec is the project's main risk.

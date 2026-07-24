# MidiSpark — project briefing

AUv3 MIDI processor (`aumi`) for iPadOS. One line: **"Don't sequence notes. Sequence what
happens to them."** An 8×8 grid sequences MIDI *processors* (arps, ratchets, gates) over
time; held chords go in, five MIDI outputs come out — ALL + A–D (delta §7b). Primary host: AUM.

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
  migration. Now HISTORICAL: its engine commits AND the GUI reconciliation are both DONE
  and device-verified. Read it for the rationale behind Router/Snapshot/graph-routing shape,
  not for "what's next" (that's the status section below).
- `Docs/standalone-plan.md` — DEFERRED milestone (standalone app = a second HOST of
  the same AUv3), but its THREE SEAM RULES are enforced NOW: (1) import hygiene —
  only `MidiSparkAudioUnit.swift` / `AudioUnitViewController.swift` / `Kernel.swift`
  may import AudioToolbox/AU frameworks; Router/Derivations/Snapshot*/Models/Emission/
  Diag/TestSessions and ALL of GridUI stay Foundation/SwiftUI-only. (2) one-named beat
  seam. (3) emission is the only place that knows cables. STATUS: seam (3) is realised
  as the `MIDIEmitter` protocol (`Emission.swift`); `Router.swift` was made Foundation-
  only against it (was a violation through v0.6) and now compiles into the unit-test
  target — see `RouterTests.swift`. `Kernel.swift` KEEPS AudioToolbox on purpose (the
  render boundary — host transport/context blocks + render-event types; it hosts the
  `LiveMIDIEmitter` adapter and sheds the import only when the standalone swap replaces
  those host reads per rule 2). GridUI is clean (SwiftUI-only).
- `Docs/router-design.md` — the engine reference (pools/sounding-sets model,
  voice/refcount design, PHASE formulas, per-render flow). Its routing
  derivation and commit plan are marked HISTORICAL (old model, as built);
  use it for what the migration's guard-rail says not to touch.
- `Docs/test-procedures.md` — the device playbook: canned sessions (repo carries
  T1–T17; the doc details T1–T11 + reconciled intents), bridge regression B1–B4,
  the UI-size-checkpoint gate, milestone gates, and the reporting template. When
  asking the human to verify anything, quote the procedure by name.
- `Docs/factory-scenes.md` — the SIXTEEN factory scenes for the scene strip: a
  curriculum disguised as a record (Part I no routing → Part II vertical →
  Part III the graph), with a STANDING RIG (recommended sounds on emitters A–D)
  and PLAY/LISTEN lines per scene. Slot 15's cycle/backward-tap are INTENTIONAL;
  every LISTEN line ships ear-tested with the rig as described. Distinct from
  TestSessions T1–T17 — never merge. **REVISED AFTER SceneFactory landed: the
  doc is authoritative — scenes 9 and 11 changed mechanically (9: the wine toll
  now taps ⇐R1, not ⇐MIDI; 11: gold RETRIG line now ⇐R1 →B, teal moved to
  C5–C8 R2) plus new SOUNDS/PLAY guidance throughout. Reconcile SceneFactory +
  its tests to the doc, then re-ear-verify the changed scenes.**
- `Docs/ui-port-guide.md` — mockup→SwiftUI mapping, design tokens (the 16 Colour
  hexes are canonical), gesture map, and the REVISED order of work (a grid
  slice exists; reconcile, don't rebuild).
- `Docs/midispark-architecture.mermaid`, `Docs/midispark-domain-model.mermaid` — runtime + schema maps.
- `BRIDGE_NOTES.md` — snapshot bridge design + hear-it tests.
- GUI mockups — **the built plugin is the living reference for SHIPPED features**;
  mockups are the behavioural spec for UNBUILT ones. `Docs/midispark-preview-v59.html`
  and `-v60.html` NOW EXIST (exported 2026-07-23; the earlier dangling-v59 note is
  resolved). v60 = canonical, and is the reference for the §6a EMITTER TOGGLES
  (pads toggle in both modes; CH caption = opener in EDIT; selectedBus concept
  DEAD). Lineage: v57 column keys · v58 static frames · v59 sixteen-slot strip ·
  v60 emitter toggles · **v61 = the RATIFICATION BOARD** (decision surface,
  not a full sim — v60 stays the last full simulator: colour pairs/ALT
  box/gradient morph bodies, cell editor + stamp banner, §6a faces,
  parametric glyphs, receiver bands, the legibility card). v26–v59 are history; v50/v51 are BROKEN (JSX bug) — never
  open; v40 is the preserved abandoned fork — do not implement it. The AUTO/WIDE/
  TALL toggle is a browser preview affordance — never port it.

## Vocabulary (spec §1 — enforced, including in code comments and UI strings)
- **Colour** = the treatment (type + params + A/B states + morph). 16 of them. Never "preset".
- **Cell** = one Colour placed at a grid position with its own wiring/state.
- **Preset** = ONLY the host-level fullState document. Nothing inside the app uses this word.
- **Emitter** = a bus A–D as the user-facing concept (its cable + its channel stamp).
- Public/product name: **"8x8 State"** — DECIDED and APPLIED (display-only). It is the
  app `CFBundleDisplayName`, the extension `CFBundleDisplayName`, the AudioComponents
  `name` ("8x8 State: 8x8 State" → AUM shows "8x8 State"), and the in-plugin/app
  logotype ("8×8 STATE"). The AppIcon (App/Assets.xcassets, single 1024 master →
  actool downscales) carries the same mark. EVERYTHING at the code/identity level stays
  `MidiSpark`: target/scheme/module names, `PRODUCT_NAME`/`CFBundleName`, bundle IDs
  (`com.paulbarrett.MidiSpark[.AU]`), and the aumi component codes (type `aumi`,
  subtype `MSpk`, manufacturer `MSPK` — never change these; they are the plugin's
  identity and saved AUM sessions key on them).

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
  `Tests/` holds a **130-test macOS unit suite** over the pure core (Derivations +
  Snapshot/Builder + loader migration + SceneFactory) AND the render engine itself
  (`RouterTests.swift` — a recording `MIDIEmitter` double asserts no-stuck-notes /
  §7b two-cable / channel-stamp / muted-silence / AUDITION / GRAPH ROUTING (fed-cell
  derivation, muted-parent reroute, silent cycles, fan-out TREE, backward/downward tap) /
  playing-HARMONIZE / IN-CH filter routing / §7 COLLISION (sustained survives same-pitch
  arp) / the §5b LAP (column-subset mapping incl. k=3 polymeter + stutter-lock) / §6a
  EMITTER TOGGLES (disabled-silent, All = enabled sum, disable-close, shared-channel
  survives) / §6a a7 VELOCITY OVERRIDE + CLAIM (fan-out + cross-cell suppression at every
  rate, muted-claimant reservation, radio switch), off-device, since Router went Foundation-
  only). BOTH stay green every commit; unit tests off-device, FIRST.
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
  band); the PROMINENT COLUMN KEYS (v57; the numbered keys stay for the playhead + the
  future §5b lap holds — the tap-to-mute was removed, see PERFORM below); the SIXTEEN-slot
  SCENE strip (dev builds wire session slots, release wires `SceneFactory`). The debug
  diagnostics + wiring lanes are REMOVED. The instrument is fully authorable
  in-plugin — no host automation needed for any control.
- **PERFORM LAYER — EDIT/PERFORM mode + ALT flip** (§6.1/6.2). The EDIT/PERFORM mode toggle
  stays; in PERFORM a cell TAP flips it to/from its B-state (engine-backed `alt`). EDIT keeps
  painting + popovers + long-press menu. **MUTE/BYP, the ALT/BYP/MUTE tap-action selector, and
  the column-key mute were REMOVED** (`3e816ee`) — the user is undecided on that feature; the
  engine fields (`Cell.muted`/`bypassed`, `SceneState.tapAction`) stay in the model (harmless,
  defaulted) so re-adding is trivial. (Perform v1 with the full tap-action set was device-verified
  before removal; user: "it feels good, issues to revisit with a revised spec.")
- **AUDITION — DONE, all six types, DEVICE-VERIFIED** (§6.4 / delta §5). Press-hold a cell while
  the transport is STOPPED → its processor sounds ALONE against the held source (phase zeroed,
  input source-forced, all-open passgate, host tempo); release or transport-start ends it.
  Time-varying types (ARP/RATCHET) run a free phase clock (`Router.auditionRender/auditionTicks`);
  chord-hold types (HARMONIZE/CHANCE/passgate) sustain the treated chord, reconciled to the held
  keys LIVE each window (`auditionChordHold` — a 128-note desired/current bitset diff via
  `reconcileAuditionVoices`); STRUM ROLLS the chord in over its spread then sustains
  (`auditionStrum`). All Foundation-only + unit-tested (`RouterTests`). `Kernel` suppresses raw note
  passthrough whenever the audition cell will sound (`auditionCellSounds`); target set via
  `MidiSparkAudioUnit.setAudition/clearAudition` (ephemeral, never persisted). GESTURE: an
  `onLongPressGesture` (0.3s) whose held target lives in a SILENT reference box (`AuditionBox`, never
  @State). Reliability comes from the DEDUPED 4 Hz poll (see architecture debt) — a stopped/idle grid
  never re-renders, so no re-render tears down the gesture mid-press (that had caused intermittent
  audition + strum-plays-a-chord). Closes acceptance #6-audition / #10.
- **DEVICE-VERIFIED since v0.6** (all confirmed on-device by the user): the full GUI reconcile;
  perform layer v1; audition (all six types, incl. strum roll); the per-type transpose/morph
  isolation (`Colour.switchType`/`AU.setColourType` — each type keeps its own transpose+morph,
  no cross-type leak, A→B→A restores); the portrait DESK band (COLOUR·PROCESSOR·EMITTERS L→R);
  `SceneFactory` reconciled to the revised Docs/factory-scenes.md (8 scenes) + ear-verified on the
  STANDING RIG; the audition-gesture reliability fix; **the UI-size-checkpoint GATE PASSED**.
  → **`v0.7-gui` is ready to tag** (user tags manually).
- **NEXT:** (a) PERFORM v2 — the COLUMN-SUBSET LAP (delta §5b): **ENGINE DONE + unit-tested**
  (`f30b006`, test-first). `Derivations.lapColumn(laneMask:absoluteStep:trueColumn:)` is the whole
  rule (`effColumn = S[absoluteStep mod k]`, S = held columns sorted; k∤8 = intended polymeter,
  never reset at pass boundaries); Router routes `effColumn` through it and `iterateTicks`'s column
  gate is lap-aware; the `lockLo/lockHi` stub is gone; the column-transition machinery gives
  invariant 4 for free. Ephemeral `laneMask` bitmask (Kernel + `AU.setLaneMask`, audition's category).
  Tests: 6 pure `lapColumn` + 3 Router integration. **UI GESTURE DONE + DEVICE-VERIFIED** (`6f28e88`):
  `ColumnHoldOverlay` (a multi-touch `UIView`, since SwiftUI can't track simultaneous key touches;
  survives re-renders) → `setLaneMask`, live as fingers join/leave, cleared on release/stop/EDIT; held
  keys show the LOOP ring. The k=1-chord-hold-sustain and touch-mapping were both confirmed good on
  device. (Cell-hold ISOLATE remains provisional pending the TOUCH design pass.)
  (a2) EMITTER TOGGLES — **delta §6a — DONE** (`a3227fa`, engine test-first + UI). `busEnabled[4]`
  (optional → old docs all-enabled), gated ONLY at the emission boundary (Voice carries origin bus;
  disabled emitter → no own-cable + no All; All = enabled sum; disable-close via `closeBus`; shared-
  channel survives via refcount). Pad body toggles in BOTH modes; EDIT CH caption opens the 1–16
  channel popover. 4 RouterTests. (The firing-flash / velocity metering is item **a4** below.)
  (a3) COLOUR-chip activity playheads — delta §6b — **DONE** (`b3d2445`, UI-only). Palette
  chips sweep top→bottom while ≥1 non-muted instance of their Colour works in the live column
  (`PaletteView.activity`, follows the LAP via effColumn), left→right when alt-only (main wins
  mixed), faint when all-bypassed; one-clock (same TimelineView + liveBeat as the cell lines).
  (a4) MIDI-activity metering — delta §6a metering block — **DONE** (`43c6cf5`). New EVENT-driven
  feed: Router accumulates per-emitter peak velocity (post-transform) + event count in `emitArtic`
  (after the enable gate → disabled emitters never meter), `drainMeters()` read-and-clears →
  `Kernel.drainEmitterActivity` → `AU.pollEmitterActivity`. (b) emitter-panel pads meter VELOCITY
  (glow-flash + thin peak-hold level bar, ~150ms decay, `OutputsView.meter`; UI owns the decay).
  2 RouterTests. (a) per-cell emitter-letter firing = the existing v59 white-flip (in the active
  column); a strictly per-cell-per-event flash would need a per-CELL feed — DEFERRED.
  **RATIFICATIONS (2026-07-24, off preview v61 — all in the delta):** the
  COLOUR-PAIR morph model (item 5: wedges/gradients/ALT box) · RECEIVERS
  (item 11, band-as-deviation rule) · §6c THE PROCESSOR WINDOW (desk box =
  type + description + pinned QUICK CONTROL + LAUNCH; params in a floating
  window; kills the portrait truncation BY DESIGN; = the future EXTERNAL
  view host) · **§5 rev 2 FINAL (the cell editor: SIGNAL-PATH ORDER —
  input radio [receivers + rows, dimmed-selectable unpopulated,
  anti-2-cycle guard] → colour + glyph + summary + alt swatch → emitter
  toggles → the ON trigger section → action row; live blinks; the LIVE
  LAW; session template; stamp mode; disclosure/accordion)** · **the ON
  TRIGGER SYSTEM (five sections, blessed shortlist, derive-vs-mutate law,
  SPRING|LATCH, composition rules + contextual greying)** · **§5c THE
  HOLD LATCH** (global spring-class latch; HOLD-off = the drop;
  PERFORM-only). Column ON system drafted (JUMP; NEXT-SCENE×EVERY-N =
  SONG MODE) — conversation deferred at the user's request.
  **⚠ PLAN ALIGNMENT REQUIRED BEFORE APPROVAL:** the a5+a6 plan below was
  written against the PRE-ratification §5 — re-align increment 1 to the
  FINAL editor spec (signal-path order; INPUT = receivers+rows radio; the
  ON section row; live blinks), and decide sequencing: the wave's
  schema-first rule says RECEIVERS + COLOUR-PAIR schema/loader land
  BEFORE the editor, else its input/colour sections get built twice.
  Remaining wave after a7's device pass: schemas → a5+a6 → §6c → §5c →
  ON engine.
  (a5)+(a6) — PLAN WRITTEN, awaiting approval: `~/.claude/plans/a5-a6-cell-editor-and-undo.md`
  (5 device-verifiable increments: cell-editor inspector → session template/clipboard →
  stamp mode → audition-returns-to-EDIT → undo/redo; each with a testable model layer). Specs:
  (a5) EDIT rework — delta §5 rev 2 (user spec 2026-07-23): the unified
  CELL EDITOR — tap any cell in EDIT → one pop-up (colour picker + input
  rows/IN CH + emitter toggles + CLEAR/COPY/PASTE-COLOUR/PASTE-ROUTING).
  Inspector behaviour (picks persist; cell-taps retarget); the SESSION
  TEMPLATE (= clipboard, one stamp object: last-committed config pre-fills
  empties; commit on FIRST interaction, never on open); STAMP MODE ("COPY
  TO CELLS…" banner + amber overwrite tint); invalid ⇐ROW stays
  derivation-fallback with dimmed display. RETIRES: tap-to-paint (as
  built), the separate FROM/OUT popovers, the hold menu. AUDITION returns
  to EDIT+stopped (hold freed). Drag survives as accelerator.
  (a6) UNDO/REDO — delta §5 (DECIDED): document-value stack at the
  mutation choke point (UndoManager; three-finger gestures free); coalesce
  continuous gestures; scope lean EDIT-only (open question); RECORD's
  future undo-last-layer unifies. Implement with (a5).
  (a7) EMITTER PANEL v2 — delta §6a revs — **BUILT + OFF-DEVICE VERIFIED, awaiting device
  confirmation** (130 tests green, iOS builds). `OutputsView` is now a mode-aware channel-
  strip mixer within one static frame: EDIT face = per-emitter CH STEPPER (▲/▼, wraps 1–16 —
  SUPERSEDES the a2 caption popover); PERFORM face = velocity FADER + 8-seg LED ladder
  (MOMENTARY ABSOLUTE override, ephemeral, spring-back on release; idle ladder tracks the live
  meter) over a CLAIM radio. Engine: `velOverride` = packed UInt32 (byte/emitter, ephemeral,
  audition's category) applied in `emitOneBus`; `claimEmitter` = persisted `PluginState` field
  → `SnapshotBox` → Router. CLAIM = suppress-never-defer at the emission boundary, checked
  against a PERSISTENT SILENT "ghost" voice (`Voice.silent`) the claimant always leaves — so
  suppression is RATE-INDEPENDENT for single-cell fan-out AND cross-cell, and a MUTED claimant
  still reserves (sidechain-style). Claimant is emitted FIRST within a fan-out. Known caveat
  (L1, accepted): two DIFFERENT cells whose same-pitch notes both NEWLY onset in one render
  window are row-order-dependent. Device procedures in test-procedures.md (a7 T-intent + CLAIM).
  (Review-fixed alongside: M1 — a per-event render-thread allocation in `handleIncoming` →
  reused scratch; L2 — audition reconcile now excludes silent ghosts; L4 comment.)
  (b) MORPH desk (16 faders) — parked per delta.
  (c) MULTI-SCENE is the flagship-but-unbuilt gap: `scenes[]` is always length 1 and `activeScene`
  is never assigned; the strip REPLACES the document rather than switching a live scene.
- **RESOLVED (`e4bfa30`):** CC/PB/AT + stopped-note passthrough now go out on **All (0) + Emit A (1)**
  (§2.6 reconciled to §7b — option 3). Pure `Derivations.passthroughCableMask` (unit-tested); the §6a
  emitter toggle governs NOTE emission, not this raw stream. No open decisions remain.
- **Architecture debt (log, tackle opportunistically):** the 4 Hz poll is now DEDUPED — it writes
  `@State` only when a DISPLAYED value changed, so a stopped/idle grid never re-renders (this
  replaced the `AuditionBox` poll-pause workaround and is what keeps press-hold gestures alive; the
  audition target still lives in a silent reference box). CLEANED UP (`c28d0c4`): the dead `guard
  playing` and the dead `SceneState.rowBypass/stackMute/stackSolo` are removed (old saves still decode
  — Codable ignores the keys; guarded by a test). Remaining: `Cell.stack`/`srcMix` stay (load-bearing
  for the v2→v3 migration); the `TODO(spec §7)` param route writes the document then rebuilds rather
  than routing into the snapshot directly. (A fuller UI isolation — pads Equatable so they don't
  re-render even while PLAYING — is possible but unneeded: audition is stopped-only, the pads are cheap.)
  §6a CLAIM residual (L3, accepted): two ENABLED emitters sharing an All stamp channel, fanned from ONE
  articulation with a SHORT note, emit `on,off,on,off` on All instead of the §7-merged `on,…,off` —
  because each per-bus voice is immediate-closed at its own `offSample`. Audibly negligible (the offs
  coincide); fixing it would require deferring the real off, which breaks fast same-note articulation.
  The primary case (long HOLD + same-pitch arp) is unaffected (the hold voice straddles the window).
- Acceptance checklist: spec §11 (+ delta §8 items 29–32). Tags shipped:
  `v0.1-scaffold`, `v0.2-bridge`, `v0.3-router`, `v0.4-graph-routing`,
  `v0.5-outputs`, `v0.6-processors`. The GUI reconcile + perform-layer v1 + audition +
  per-type params + the scene-factory reconcile are all on main **untagged and device-verified**;
  the size-checkpoint gate has PASSED, so **`v0.7-gui` is ready to tag**.

## Style
- Swift, no external deps beyond apple/swift-atomics (SPM, already in project.yml).
- Comments cite spec sections (e.g. `// §3.2: stepped fields quantize`). Keep doing this —
  the spec is the contract, and drift between code and spec is the project's main risk.

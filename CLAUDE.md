# MidiSpark — project briefing

AUv3 MIDI processor (`aumi`) for iPadOS. One line: **"Don't sequence notes. Sequence what
happens to them."** An 8×8 grid sequences MIDI *processors* (arps, ratchets, gates) over
time; held chords go in, five MIDI outputs come out — ALL + A–D (delta §7b). Primary host: AUM.

## Claude↔Claude message passing (`_dear_claude_code/` inbox · `_dear_claude/` outbox — gitignored)

An async channel with a PARTNER Claude (design/planning context). Both dirs are gitignored and
NEVER committed. The names read as the letter's salutation: **`_dear_claude_code/`** holds messages
addressed to ME (my INBOX, from the design side); **`_dear_claude/`** is where I write TO the design
Claude (my OUTBOX). Trigger is **MANUAL** — run this when the user asks (e.g. "check incoming"):
1. **CHECK `_dear_claude_code/`** for new files. Each is documentation/instruction from the partner.
   - An UPDATED version of a doc I hold (this CLAUDE.md, a `Docs/*` file) → **MERGE** its changes
     into my copy (reconcile, don't blindly overwrite — we edit in parallel, so watch for reverts).
   - A NEW document → **ADD** it to the right place (`Docs/`, etc.).
   - After processing a file, **DELETE it** from `_dear_claude_code/` (it's consumed), and **RECORD
     which files I read** so my next message can ACKNOWLEDGE them back to the partner (symmetry:
     he applies the same delete-on-acknowledgment rule to his outbox that I apply to mine).
2. **REPLY via `_dear_claude/` — but only when there's something of IMMEDIATE VALUE** (a merge that
   changed something, a real answer, a decision, a blocker). **Do NOT write a ceremonial/empty
   reply.** Silence is a valid response.
   - **DELETE-ON-ACKNOWLEDGMENT (2026-07-25): do NOT pre-empty the outbox.** Outbox files STAY until
     the partner has explicitly acknowledged reading them (he lists which files he read in his
     messages). Only then delete the acknowledged files. This makes the manual, human-relayed channel
     lossless — nothing is cleared before it's confirmed received. **Ask the partner, in each reply,
     to tell me which files he read.**
   - **CONSTRAINTS: keep it FLAT (no subdirectories) and ≤ 20 files total** — Claude's document read
     limit is 20. Bundle source into a SINGLE file (`SOURCE-SNAPSHOT.md`, each `.swift` under an H2
     header) rather than shipping loose files, so FINDINGS + bundle = 2 documents.
3. Keep the tracked side clean: commit only real repo changes (`.gitignore`, docs, code) — the
   inbox/outbox contents are transient and untracked.

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
- **This section is the BACKWARD log (what landed, with commit refs). `Docs/pending-tasks.md` is the FORWARD
  checklist (what's open). Keep both current as work lands — tick pending-tasks + add a commit line here — and
  keep them from overlapping.**
- **▶ DRAG&DROP dynamic palette + drag rebuild + FORK (2026-08-09, on `main`, PUSHED …→`96cb114`; macOS 550 green, iOS
  builds; Paul confirms drag works on device). System `.onDrag/.onDrop` doesn't survive the AU host → rebuilt as a
  CUSTOM finger-tracking drag (onTapGesture + simultaneousGesture(DragGesture) in a shared "dd" space, measured drop
  zones via `DDZonePref`, floating ghost, source-lift). Held the 1024 content cap. PALETTE is now DYNAMIC: renders
  only DEFINED colours (has cells, via `ddColourIsPlaced`) as swatches, undefined as "+" FORK slots; `makeInit` starts
  with ONE colour (GOLD, top row). Grid→"+"-slot = FORK (recolour + keep machine); grid→swatch = ADOPT. Playhead
  phase-locked + swing-warped; litter flashes.**
- **▶ PER-COLOUR STORAGE MOVE — decision: GLOBAL (Paul 2026-08-09), NOT YET STARTED. Colour-scoped EDITING is live on
  the DRAG&DROP page (edit a colour = edit all its cells, current scene). The PHYSICAL move (machine fields
  processors/buses/inputReceiver/chop off Cell → onto the global Colour; cells → position+mute; SnapshotBuilder reads
  the colour's machine; migration folds divergent per-cell machines) is a MULTI-TURN refactor: ~330 test sites set
  cell machine fields (223 in RouterTests) + a real semantic shift (per-colour cells share one machine) + no device
  verification. Deliberately not half-started (would break the suite + app). Needs its own staged effort.**
- **▶ VELOCITY INHERITANCE — soundcheck paths (2026-08-09, on `main`, PUSHED `ea8fe81`; macOS 550 green FROM SCRATCH,
  iOS builds). Closes the follow-up from `28dbd29`: previewStopped/previewPlaying/previewChordHold/auditionRender/
  auditionChordHold/auditionStrum took a flat 96, so audition ≠ playback. They now inherit the source velocity too
  (arp via `arpPick`; ratchet/strum shape relative; chord-holds/harmonize take the note's velocity). Test
  `testAuditionInheritsSourceVelocity` drives `process(playing:false, audition:0)`. Velocity inheritance is now
  complete across the real AND soundcheck paths.**
- **▶ DRAG&DROP phase 2 — row selectors · drag · randomize · playhead (2026-08-09, on `main`, PUSHED `ea0647b`,
  `4fca424`; iOS builds, tests untouched; DEVICE eye owed). Paul's answers: RANDOMIZE = reroll chain+params · modes
  DEFERRED. **ROW SELECTORS** (left of the grid) paint a row with the selected colour. **RANDOMIZE** rerolls the
  selected colour's processor chain (1–3 random procs) + params. **PALETTE PLAYHEAD** ("THE REFILL") — a swatch fills
  downward while its colour has an unmuted cell in the active column (v1 column-rate, not yet phase-locked). The grid
  is now a **flat-colour 8×8** I fully own (design v1 "flat, calm"), so tap/drag/drop live in one place. **SIX DRAG
  LANDINGS** via .onDrag/.onDrop: palette→grid PLACE · grid→grid MOVE · grid→occupied-palette ADOPT · grid→empty-
  palette FORK · cell→LITTER clear · colour→LITTER delete-colour+cells. Deferred: palette↔palette reorg, SINGLE|MULTI|
  FREE, the true per-colour machine model (FORK/ADOPT copy machines cell-wise for now). ⚠ .onDrag/.onDrop needs device
  verification inside the AU host.**
- **▶ DRAG&DROP polish (2026-08-09, on `main`, PUSHED `8fd10a6`,`dcba092`; iOS builds). Playhead PHASE-LOCKED to the
  column boundary (extrapolates the ~4Hz beat; swing warp still a follow-up); DROP-TARGET HIGHLIGHT (cells/swatches
  ring in the edit hue, LITTER glows red under a hovering drag); the LITTER FLASHES what it took ("−1 colour · N
  cells"). Remaining Drag&Drop work is all big-ticket + needs Paul's steer: the per-colour machine model, SINGLE|MULTI|
  FREE (FREE launcher = engine work), palette↔palette reorg.**
- **▶ PER-COLOUR EDITING MODEL (2026-08-09, on `main`, PUSHED `894abde`; iOS builds). "You only ever edit colours":
  selecting a colour on the DRAG&DROP page scopes the edit to EVERY cell of that colour (editPointedCell/editChop/
  {add,edit,remove}SlotCells already fan out to `sel`); siblings ring on the grid, the machinery shows the swatch +
  cell count. This is the model's BEHAVIOUR on the existing per-cell storage. The deeper STORAGE move (machine
  physically on Colour; cells → position+mute; presets carry colour-machines) is LARGER than it looks + has a real
  design fork: **colours are document-global but cells are per-scene**, so "a colour is a machine" implies cross-scene
  sharing — a semantic change with hairy migration (divergent per-cell machines → one) and a full RouterTests rewrite
  (every test sets cell.processors/buses). Not started; awaiting Paul's call on cross-scene semantics + whether the
  storage purity is worth the churn now.**
- **▶ DRAG&DROP page — new first tab, phase 1 (2026-08-09, on `main`, PUSHED `230f5bb`; iOS builds, tests untouched;
  DEVICE eye owed). From `Docs/design-dragdrop-page-2026-08-08.md` (ferried in, preserved `ce6d170`). Paul's forks:
  grid 8×8 · palette 4×4 · scaffold on the per-cell flow diagram · first cut = layout+selection+machinery. New
  `AppTab.dragDrop` leads the bar; `DragDropPage.swift` = ONE non-scrolling panel — TOP: 4×4 palette (16 colours, dot
  = has placed cells) + 8×8 GridView; BOTTOM: the flow diagram full-width + PLAY THIS CELL (reuses `playScopeButton`)
  + RANDOMIZE placeholder; LITTER box under the palette. Palette tap → edit the colour's FIRST placed cell; grid tap →
  mute/unmute + select. `editArmed` now also arms on `.dragDrop` so the flow diagram + its pop-ups work unchanged.
  New file added via `xcodegen generate` (project.yml includes the whole AUExtension folder). DEFERRED (in the doc):
  the six drag landings, the palette fill-wipe playhead, SINGLE|MULTI|FREE, a real RANDOMIZE + LITTER delete, and the
  true per-colour machine model. Reply in `_dear_paul/reply-2026-08-09-dragdrop-phase1.md`.**
- **▶ VELOCITY INHERITANCE + cell-edit page reshape (2026-08-09, on `main`, PUSHED `28dbd29`,`c1bf1f5`; macOS 549 green
  FROM SCRATCH, iOS builds; DEVICE ear/eye owed). Paul: the arp (and in fact every processor) emitted a flat velocity
  96. **FIX:** the whole REAL signal path now carries the source note's velocity — `arpPick()` returns note+velocity
  (octave-invariant); `applyStage`/`composeChainSet`/`emitDriverNote` carry it through the chain; ARP/RATCHET/STRUM
  pass the picked source velocity (ratchet ramp + strum tilt shape RELATIVE to it, via their `base:` param); the
  generators scale it by their envelope (`strikeChord` takes a `velScale`); column holds + classic ECHO inherit too.
  Preview/audition paths still sound a flat default (soundcheck only — honest follow-up). Tests: testArpInherits… /
  testChainInherits…Harmonize / testEuclidGeneratorInherits…; updated the tests that had baked the old 96 as
  "natural" (now the source velocity, e.g. 100 from `chord()`). **LAYOUT `c1bf1f5`:** the cell-edit page is now ONE
  non-scrolling panel — LANDSCAPE: grid LEFT · flow RIGHT · mode buttons row along the BOTTOM; PORTRAIT: grid TOP ·
  slim mode-button column to its right · flow in the BOTTOM half. Removed the informational/guidance text; "Play from
  grid" → a single enable/disable `playScopeButton` by the flow; `flowDiagram` takes an explicit width. Earlier this
  turn (`4d7693b`): flow-diagram tightened receiver→processor gap + centre-bottom drop; (`8f5e3b7`): 4 processor
  slots, plus-only ghost, retired everything below IDENTITY.**
- **▶ CHOP-ON-ECHO + fold guard + SPLIT pop-up (2026-08-09, on `main`, PUSHED `60853b1`; macOS 546 green FROM SCRATCH,
  iOS builds; DEVICE ear owed). Paul: the 8×3 output SPLIT worked on the arp but not the echo after it. **BUG:**
  `drainEchoTails` emitted repeats on the RAW bus mask — the per-slice chop was never applied; the classic
  `registerEcho` path bypassed it for BOTH dry + tail. **FIX:** resolve `chopMask` at the source note's slice and
  store it in the tail (echoes inherit the note's destination; a muted slice → mask 0 → the `pushEchoTail` guard
  drops the tail, silencing note + echoes). Tests: testChopRoutesEchoRepeats… / …ClassicEcho… / testChopMuteSilences-
  TheEchoesToo. **GUARD (Paul's option A):** testNoDownstreamProcessorTerminatesTheFold — each downstream type
  (passgate/chance/harmonize/echo) between an arp driver and a +12 harmonize must let the harmony fire; locks "no
  stage is terminal" (the echo `break` bug). **UI:** the SPLIT (MAIN·CHOP·ALT / outputSection) moved OFF the cell-edit
  page into `splitEditorPopup`, reached via a dashed SPLIT button on the flow-diagram emitters box — step one of
  retiring the under-flow-diagram sections. ⚠ BUILD TRAP: the session clock jumps break xcodebuild incrementals (it
  reused a stale binary → phantom "546 green" that skipped new tests); `rm -rf DerivedData/MidiSpark-*` before
  trusting results. See memory `midispark-stale-build-clock-skew`.**
- **▶ ECHO IN A CHAIN + flow-diagram labels (2026-08-09, on `main`, PUSHED `eb1bc3c`→`96af278`; macOS 542 green, iOS
  builds; DEVICE ear owed). Paul's `[ARP→ECHO→HARMONIZE]` heard no harmonize. First fix `eb1bc3c`: `emitDriverNote`'s
  echo branch `break`ed → any slot after echo was skipped; removed the break so the fold reaches harmonize.
  Paul then asked the right question — should harmonize shape echo's OUTPUT? **`96af278`: yes** — echo now passes the
  fold as IDENTITY and registers its tails AFTER every downstream stage, so the ECHOES are harmonised too (THRU keeps
  dry, MUTE = echoes only). v1 trade-off: echo's chain position no longer changes tail CONTENT — always echoes the
  final emitted set (right for linear stages like HARMONIZE; per-repeat-as-it-fires = the deferred "hand the tails"
  work). Test `testEchoRepeatsTheHarmonizedSetSoTheEchoesAreHarmonised`. Also `dc09cbd`: flow-diagram ghost boxes now
  read "Output Filter +" / "Processor +" (flowGhost renders the label + a plus-icon add affordance).**
- **▶ DECISIONS BATCH — generators-as-drivers · RESTRIKE · EUCLID POOL · SELECT retire · INIT default · macro/undo
  (2026-08-09, on `main`, PUSHED `4f06d47`→`204432d`; macOS 540 green, iOS builds; DEVICE ear owed). Paul's rulings.
  **#1 GENERATORS ARE CHAIN DRIVERS** — euclid/burst/cascade/drone/shift/humanize join arp/ratchet/strum (shared
  `isDriverType`); `emitGeneratorRow` gained `chainDriver`/`cycleBeats` — composes upstream (composeChainSet) + folds
  downstream (emitDriverNote). `[EUCLID→PASSGATE]` generates+gates; `[HARMONIZE→EUCLID]` pulses the composed set.
  Single-slot unchanged. **#2 WIRE = RESTRIKE** — a strike on an already-sounding (cable,ch,note) emits a clean
  off→on (off first, same ts); refcount unchanged (governs the true release) → no stuck notes. In `openVoice`;
  collision test updated + `testRestrikeEmitsOffBeforeOnForAnAlreadySoundingNote`. **#5 EUCLID PULSES = FIXED|POOL**
  (POOL → K tracks the held-note count; append-only `euclidPulsesFromPool`). **#6 SELECT retired** — the always-empty
  `selection` vestige removed (GridView param, the dead two-sources onChange, doVerb/strokeCell/cancel writes,
  selectionMixed); EDIT's `sel` untouched. **#8** macro bind stays SILENT until the grid slider moves (reverted
  drive-to-full). **#9** row-selector tap = ONE undo (per-row `coalesceKey`); behaviour identical. **INIT** (mid-turn)
  — a blank grid is the new FACTORY DEFAULT (fresh instance loads it); the 3-scene arc kept as the "ARC" preset.
  Deferred by ruling: #3 SCALE (leave), #4 DRONE (keep), #7 TURNS (no change), #10 MIDI-delays (spec to follow), #11
  governor cap (fixed at 48).**
- **▶ THE FLOOD GOVERNOR — field-incident safety (2026-08-09, on `main`, PUSHED `f16500b`→`db0b928`; macOS 535 green,
  iOS builds; DEVICE re-test owed). Paul's AUM incident: a runaway ECHO patch (+12/repeat, high repeats, dense Scaler
  chord feed) flooded thousands of note-ons/sec → two synths cut simultaneously, crash-free, no MIDI from 8x8. Design
  ferry `INCIDENT-flood-governor` diagnosed count-strain seizing downstream allocators (+ a >127 byte from the drain
  would desync every synth's parser at once). **FIX SET:** (1) RANGE-DROP verified — `drainEchoTails` already guards
  n∈0…127 (drops, never encodes ≥128); locked by `testEchoPitchClimbNeverEncodesAboveMidi127` (so the desync isn't in
  current code — likely the build Paul ran, or pure count-strain). (2) **FLOOD GOVERNOR** (safety-class): a hard
  per-emitter note-on cap per BEAT (`Router.floodCapPerBeat`=48, dev-tunable) at `emitOneBus` (after every suppression
  gate); over-cap ons DROP, counted → `diag.floodDropped` → cog HEALTH "DROPPED N". Offs never governed → no stuck
  notes; budget resets each beat + on reset. (3) PANIC now also blasts CC120+CC123 on every channel/cable
  (`panicControllers`). Tests: governor caps+counts (dense euclid flood, nothing stuck) · panic CC (5×16 each) · the
  range lock. Fuzz/assert helpers updated to accept CC (0xB0) as valid wire. Reply
  `_dear_claude/REPLY-2026-08-09-flood-governor-shipped`. FEED DELAY: design reconciled → KEEP (distinct from DECAY).**
- **▶ GENERATORS II — DRONE · SHIFT · HUMANIZE (2026-08-08, on `main`, PUSHED `095f5b7`; macOS 532 green, iOS builds;
  DEVICE ear-check owed). Three more feel/texture processors via the shared `emitGeneratorRow` — NO new schema (each
  reuses a param). **DRONE** — flat sustained pad, entry chord held to boundary (reuses `gate`=level). **SHIFT** —
  groove nudge, pushes the onset late 0…~40% of the step (reuses `spread`). **HUMANIZE** — seeded per-note timing +
  velocity jitter, replay-safe (seed = column·note·index, `splitmix64Mix`; AMOUNT=`spread`). Wiring mirrors euclid/
  burst/cascade; all added to fuzz `randomDoc`. Tests: DRONE/SHIFT once (3 ons), HUMANIZE replay-safe. **ROSTER NOW
  13 types.** Remaining list: generators-as-chain-drivers · SCALE (pitch-correct, a transform path) · MOD/BEND (need
  CC/bend emission infra).**
- **▶ GENERATORS — EUCLID · BURST · CASCADE (three new processor types) (2026-08-08, on `main`, PUSHED `41fee32`;
  macOS 529 green, iOS builds; DEVICE ear-check owed). The spec's generator brainstorm, first three: single-slot tick
  processors that generate from the held chord. **EUCLID** — K-of-N euclidean rhythm (PULSES hits spread across STEPS,
  rotatable; strikes the whole chord per pulse); pure `euclidPattern(pulses:steps:rotation:)` (hit on step 0, exactly
  K). **BURST** — one-shot accel/decel roll (COUNT strikes, CURVE bends spacing +1 accel/0 even/−1 decel, vel fades);
  pure `burstFractions(count:curve:)`. **CASCADE** — reveals the chord one note at a time (RATE, UP/DOWN), each held
  to the boundary. EUCLID adds 3 append-only params (euclidPulses/Steps/Rot); BURST reuses count+curve, CASCADE reuses
  rate+strumDir. Wiring: ProcessorType/CellMode/cellMode/emblem/typeDescription/macroParams + resolve + shared
  `emitGeneratorRow` (window-scan, half-open, chop-routed, offs scheduled). **Single-slot only in v1** (not chain
  drivers yet — like echo's intro; the driver dispatch + chainDriverIndex are unchanged). Tests: pure pattern + render
  (euclid=12·burst=4·cascade=3) + all three added to the fuzz `randomDoc` (no-stuck-notes across every edge). ROSTER
  is now 10 types. DEFERRED: generators as chain drivers · the rest of the brainstorm (DRONE·HUMANIZE·SHIFT·MOD·BEND).**
- **▶ ECHO: FEEDBACK removed (→ DECAY) + TAIL SPILL RING|CUT — design ferry (2026-08-08, on `main`, PUSHED `802e6ac`;
  macOS 524 green, iOS builds; DEVICE ear-check owed). Actioned `_dear_claude_code/ASK-echo-feedback-removal` (design
  2026-08-07). §1: my echo is TAPS-EQUIVALENT (drainEchoTails computes each repeat directly; no repeat REGISTERS a
  repeat) → the FEEDBACK param is removed, renamed `echoFeedback`→`echoDecay` (per-echo falloff) everywhere. KEPT
  FEED DELAY (Paul's 2026-08-08 ask, not named in the ruling) — flagged to design to reconcile. §3: `EchoSpill` enum
  three-valued (RING·CUT·HAND); RING (default) spills past the column, CUT kills pending repeats once the playhead
  crosses the tail's column boundary (last repeat finishes its gate — lap-safe, done in drainEchoTails, no stuck
  notes), HAND is birthstone (in enum, not in UI). ProcessorBox RING|CUT chip. §2 ROUTE (CHAIN|DIRECT) stays moot
  (echo always last); §4 TAILS DOOR/HAND captured. Test `testEchoSpillCutStopsRepeatsAtColumnExit`. Reply
  `_dear_claude/REPLY-2026-08-08-echo-feedback-and-spill` (awaits design ack).**
- **▶ MIDI DELAYS — playable preset + stampable cells (2026-08-08, on `main`, PUSHED `edd6f19`; macOS 523 green, iOS
  builds; DEVICE ear-check owed). Built on the echo engine. `PluginState.makeDelays()` (factory preset "DELAYS"): 8
  delay flavours (SLAP·DOUBLE·DOTTED·QUARTER·DUB·RISER·FALLER·CANYON), one per ROW in COLUMN 0 only (sparse → tails
  ring across the empty columns), SINGLE mode, 3 scenes (SLAP·DUB·CANYON), OMNI-in→Emit A. Six stampable factory
  delay CELLS (`CellLibraryStore.factory`: Slap·Double·Dub·Rise·Fall·Canyon — single-slot echoes, machine-minus-
  routing). Shared `PluginState.lEcho(...)` builder. Test `testMidiDelaysPresetIsEightSparseEchoes` + the factory-
  cell test covers the new cells.**
- **▶ ECHO REDESIGN + [ARP→ECHO] + selector/mute rule revisions (2026-08-08, on `main`, PUSHED `ec2a4d9`→`f1800e4`;
  macOS 521→522 green, iOS builds; DEVICE ear-check owed). Paul's batch. **ECHO now a real delay engine** (replaces
  rate/count/ramp reuse): new append-only `ColourParams`/`SnapParams` echo fields — REPEATS 1–16 (8×2 box) · SYNC
  on/off · DELAY synced (1–16 sixteenths, 4=beat) or free (ms @ tempo) · OFFSET ±33% · FEED DELAY (first-echo send)
  · FEEDBACK (per-echo decay/tail) · PITCH (semitones/echo, climb/descend) · THRU/MUTE · Bypass (existing).
  `EchoTail`/`drainEchoTails`/`registerEcho` reworked (echo k at onset+(k+offset)·time, vel=dry·feedDelay·feedback^
  (k-1), note=dry+k·pitch; repeats cap 16; offs always scheduled → no real stuck notes). Full 8×2+slider editor in
  ProcessorBox. **[ARP→ECHO]** (answers Paul's "hard rule" Q — yes, the chain is serial): the post-driver fold
  (`emitDriverNote`) now registers an echo tail per driver TICK (`pushEchoForNote`) instead of passing echo through
  applyStage; THRU keeps the dry tick, MUTE drops it. v1 tick-echo = SYNCED-delay only (tick emitters don't thread
  tempo). **SELECTOR rule (revised, supersedes prior):** a row selector taps EVERY cell when the row is uniform (all
  muted/all unmuted); MIXED → taps only the UNMUTED cells. Double-tap not special-cased. **CELL-EDIT mute:** directly
  selecting a MUTED cell unmutes it (+ becomes the SINGLE active rung); auto-joined muted twins stay muted; tapping a
  selected muted twin deselects. +3 echo tests (single-slot real-path · echo-as-tail · [ARP→ECHO]). FLAGGED:
  free-ms tick echo + discrete-param echo macros deferred.**
- **▶ SELECTOR CONSISTENCY + 3 BUG FIXES (2026-08-08, on `main`, PUSHED `5c42a37`; macOS 519→521 green, iOS builds;
  DEVICE pass owed). Paul's batch. **SELECTORS (hard rules, mode-independent):** ROW selector — ANY gesture now ==
  tapping EVERY cell in that row (`tapRow`→`tapCell` per cell); removed `setLadderRow`/`doVerbOnRow` (the mode
  branches). COLUMN selector — ANY gesture toggles that column in the LOOP set via ONE path (`onColumnKey`, tap +
  long-press, both pages); removed the separate multi-touch `ColumnHoldOverlay` UIView + `onLaneMask` param. (Row-tap
  in MULTI is now 8 undo steps — matches "tap every cell". Stale ColumnHoldOverlay comments remain; scroll behaviour
  untouched.) **BUG — single-mode unmute:** a MULTI/edit-muted cell was un-clearable in SINGLE (tap only armed a
  rung); now tapping a muted cell in SINGLE unmutes it + makes it the active rung. **BUG — echo as a chain tail:**
  `[…→ECHO]` had no effect (emitEchoColumn read the HEAD); new `isEchoTail` recognises a non-tick-driven ECHO-tail,
  echoes the composed upstream set; emitColumnHolds skips it. **Single-slot [ECHO] already worked** (proven by
  `testEchoViaExplicitSingleSlotChainStillRepeats`) — so if a single-slot echo is still silent on device the cause is
  wiring, not the engine. `[ARP→ECHO]` tick echo stays Phase-2. **BUG — macro apply inaudible:** a freshly-bound
  macro sat at value 0; `macroAuthorBind` now drives it to FULL (1.0) on bind so the authored sound is live (grid
  slider pulls back). +2 echo tests. FLAGGED: discrete-param macros (PATTERN/DIR) still don't fold (Phase-2).**
- **▶ COVERAGE + REFACTOR PASS — audit-driven (2026-08-08, on `main`, PUSHED `df27ae2`; macOS 514→519 green, iOS
  builds). Two parallel survey agents (missing tests · safe refactorings), findings VERIFIED against the code before
  acting. **+5 TESTS** closing verified pure-core gaps: `resolvedCellChain`/`sealHash` explicit-empty `[]` seals
  distinctly from the A-face cell (`testExplicitEmptyChain…`) · `NotePool.srcPlayed(noteLo:noteHi:)` RANGE variant
  (`testAsPlayedRangeWindow…`) · echo DECAY FLOOR drops <1-vel repeats, never emits vel-0 (`testEchoDecayFloor…`) ·
  `macroSlotBindings` SUMS same-(slot,param) targets (`testMacroSlotBindingsSums…`) · the unit-range `effective*`
  reads clamp (`testEffectiveUnitRangeScalarsClamp`). **REFACTOR** (behavior-identical): the survey found NO safe
  dead code (all inert pure logic is deliberately kept per this file) — so comments + a small dedup only: deleted the
  orphaned `effectiveT` doc comment; trimmed the stale a→b-morph block (Snapshot); reworded Router `topCell`'s stale
  "commit 5"; adopted `clamp()` in the 5 test-covered `effective*` reads; extracted `busBitmask(_:)` (Models) for the
  two SnapshotBuilder Set<Bus>→mask sites. Left the broad Models/Builder clamp sweep alone (low value, hot-path
  blast radius). ALSO wrote `_dear_paul/concepts-of-8x8-state.md` — a 12-section plain-language concepts map (not
  tracked; a note to Paul).**
- **▶ FLOW-DIAGRAM PROCESSOR POP-UP + MACRO MERGE + CELL-SOLO (2026-08-08, on `main`, PUSHED `196d9cd`→`a16b19c`;
  iOS builds, macOS 514 green; DEVICE pass owed). Paul's batch on the cell edit page's flow diagram. (1) **INTERACTIVE
  BOXES** (`196d9cd`): tap a POPULATED processor box → a modal pop-up with the FULL controls (reuses `ProcessorBox`
  slotMode — big/legible/per-type); tap an EMPTY box → a welcoming TYPE PICKER (emblem buttons). (2) **MACRO MERGE**
  (`1fb7c19`): the macro authoring page now lives INSIDE that pop-up — title-row is a plain TITLE + BYPASS only
  (type-picker/MACRO/MIXER dropped, user flow answers); at the FOOT, one adaptive control — "+ ADD MACRO" (no
  macros) or the macros dropdown ("add new…" + this slot's macros) — engaging it reveals the authoring controls
  inline. `MacroAuthoringView` gained an `embedded` mode (headerless, gated, `onEngage`) + `plainTitle` on
  ProcessorBox; ONE APPLY/CANCEL governs BOTH the param edits and the macros (document snapshot); the macro morph
  auditions live; the macro BASE tracks param edits (`slotBox onEdited`). Picking a type in the empty-box picker now
  opens the edit form immediately (was: close, tap again). The standalone macro pop-up stays for the chain-stack
  editor. FLAGGED: editing params AFTER binding a macro in one session isn't fully reconciled (author macros last).
  (3) **"PLAY FROM GRID / PLAY THIS CELL ONLY"** (`a16b19c`): a top-of-page toggle solos the edit selection while
  the transport plays. Engine = an ephemeral `soloCellMask` (bits col*8+row) threaded into `Router.process` like
  laneMask — a cell whose bit is unset is skipped in all three emit guards (parallel to muted/dormant, no stuck
  notes); Kernel `setSoloCellMask`, AU `setEditSolo`/`clearEditSolo` (never persisted; follows the selection, clears
  on leaving EDIT). Test `testPlayCellOnlySilencesEveryOtherCell`. OWED (design/device): MIXER was DROPPED per the
  flow answers (not a placeholder anymore); the whole batch is device-look/ear owed.**
- **▶ ECHO processor — THE TAIL ERA, Phase 0 + 1 (2026-08-07, on `main`, PUSHED `3f8a27b`; macOS 513 green, iOS
  builds; DEVICE ear-check owed). Spec `AcceptanceCriteria-tail-era-delay-echo.md`. The FIRST tail stage — repeats a
  note at delayed beats with decay. **THE TAIL ENGINE (§0):** echo repeats fire at FUTURE beats, and the render only
  visits the ACTIVE column's cells (`Router.swift` row loop keys `box.cells[effColumn*rows+r]`), so a tail must
  outlive its cell/column AND the source's held state — NOT re-derivable from the current pool. Implemented as the
  spec's **activation RING** (fixed 256-cap, evict-oldest, `EchoTail`): each DRY strike registers; `drainEchoTails`
  emits each due repeat every window, column-independent (rings out past the column + past release). A NEW sanctioned
  mutable-state exception — CLEARED on every transport/scene/panic/latch/sceneRestart edge + reset + beat
  discontinuity (tails die on stop, spec v1; never leak). `Router.quiescent` now also requires the ring empty, and
  the fuzz/chaos suites GENERATE echo cells (`.echo` in randomDoc) → they assert no-stuck + quiescent with echo
  across every edge. Each repeat opens a voice with a scheduled off (drainDue → invariant 4); half-open [mStart,mEnd)
  filter so a repeat lands in exactly its window (never bunched at the block head); roles eat echoes for free
  (emitArtic path). **MINIMAL ECHO (Phase 1):** single-slot `[ECHO]` cell; TIME/REPEATS/DECAY REUSE rate/count/ramp
  (zero new snapshot plumbing); dry = a short strike per column entry (repeats retrigger); wet repeats decay by
  DECAY^k with a vel floor; KEEP pitch, MAIN dest. Plumbing: `ProcessorType += .echo` (append-only) · `CellMode` +
  cellMode · macroParamsForProcessor · emblemSymbol("repeat")/typeDescription/ProcessorBox editor. **3 RouterTests**
  (`testEchoRepeatsHeldNoteWithDecay` · `testEchoTailRingsOutAfterSourceReleasesThenStopClearsIt` (the tail + no-leak
  gate) · `testEchoIsBlockSizeInvariant`). **DEFERRED Phase 2** (flagged): mid-chain echo / `[ARP → ECHO]` riding a
  tick-driver (v1 = single-slot only; multi-slot echo folds as pass-through, no crash) · FOLLOW mode · PING spread ·
  CHAIN|DIRECT tail route · factory presets (CANYON CALL/DUB TABLE) · seek/loop look-back (v1 drops tails on a jump)
  · the seal spark ringing with tails. ALSO: the PROCESSORS-page grid width is now fixed at 512 (height proportional,
  `EditPage.editSpikePage`; commit `3f8a27b`).**
- **▶ MACRO POP-UP rev 3 + grid macro band resize + mosaic crest reshape (2026-08-07, on `main`, PUSHED `0fc407b`;
  iOS builds, macOS 510 green; DEVICE pass owed). Paul's batch. **MACRO POP-UP** (`MacroAuthoringView`): (1) a
  DROPDOWN at top — "add new macro…" + every macro already bound to THIS slot with its overridden controls in
  brackets; picking one REFLECTS it (controls · alt values · applied state) via new pure `macroSlotBindings(macros,
  col,row,slot)` read-back (`EditPage.openMacroAuthoring` computes it; VC `macroAuthorExisting`). On open, existing
  bindings reflect (widgets show REMOVE, params grey). (2) Processor controls ENLARGED to match the main edit
  section. (3) The MAIN…WITH-MACRO slider is now ALWAYS present (dims when no divergent selection). (4) Macro
  sliders/buttons stay DRIVEABLE when greyed (dropped `.disabled`, grey = opacity only). (5) Scrim-tap now KEEPS the
  macros (APPLY) — only the CANCEL button reverts, so grid-page macros work with the applied bindings unless
  explicitly cancelled. (6) `macroAuthorBind` is idempotent per slot (`removeMacroTargets` then add — no duplicate
  targets on reflect/re-bind). **PURE**: `macroApply` OPTION+STEPPER now SWEEP through their values across the
  slider (a multi-select isn't binary); TOGGLE+MASK still snap. Test renamed→`testMacroApplySweepsOptionStepperSnapsMask`
  + `testMacroSlotBindingsReadsBackPerSlot`. **GRID MACRO BAND** (`controlBand` + `GridMacroBand`): 8 sliders on ONE
  line enlarged; 8 buttons still two rows of four but bigger (widgets gained an optional `height:` param, pop-up
  defaults unchanged). **MOSAIC** (`mosaicLayout` + `drawMosaic`): crest shapes now OUTLINED not filled; the crest
  square is placed at a HASH-CHOSEN CORNER (not always leftmost) and is TWO-THIRDS cell height, square in px
  (L-decomposition of the remainder, Σ area = 1 verified at all four corners; test
  →`testMosaicCrestBlockIsTwoThirdsHeightSquareAtACorner`). BOUNDARY unchanged: only the 7 foldable continuous keys
  reach the engine — discretes render/audition (now sweeping) + record-as-bound but don't modulate yet, so the
  dropdown's bracket list + reflect only round-trip the continuous targets.**
- **▶ MACRO POP-UP rev 2 — Paul's revisions (2026-08-07, on `main`, PUSHED `3f4ab03`; iOS builds, macOS 509 green;
  DEVICE pass owed). Reworked the processor macro authoring pop-up (`MacroAuthoringView.swift`) per Paul's spec:
  (1) ONE big audition slider per pending macro, labelled **MAIN … WITH MACRO** (replaced the per-param
  `VTestSlider`s) — morphs the whole selection base→alt live via the existing pure `macroApply`. (2) Each control
  shows its **MAIN processor value in text** beside the label (per-kind: number · ON/OFF · option label · int ·
  mask bits — `mainText`). (3) The per-macro button is **"ADD TO M{n}"**, DIM until a selected control actually
  diverges from MAIN (`canAdd = !sparse.isEmpty`); after binding it flips to **"REMOVE FROM M{n}"** and drops the
  binding LIVE in the MIDI out (`AU.removeMacroTargets` gained an optional `slot:` filter → `EditPage.macroAuthorUnbind`
  → VC `onUnbind`). (4) A macro's live slider/button is **DISABLED/dimmed until something is added to it**
  (`isBound(i)`). (5) A selected control whose alternative == source **stores nothing** (`macroSparseDelta` drops
  zero/epsilon deltas). JUDGMENT CALL: binding now clears the round + greys the bound params, so the old macro
  DROPDOWN + "+ ADD ANOTHER MACRO" + per-param test sliders were superseded and REMOVED (the flow is select → ADD
  TO M{n} → repeat). Offset engine (M1 fold / AU params / 24 slots) unchanged. Discrete-param binding still deferred
  (only the 7 foldable continuous keys reach the engine; discretes render + record-as-bound but don't modulate yet).**
- **▶ FUZZ HARNESS — TRANSPORT + SNAPSHOT-SWAP CHAOS scenarios (2026-08-07, on `main`, PUSHED `6a79e93`; macOS 509
  green). Extends `Tests/FuzzTests.swift` (Layer 1) with two adversarial-SCHEDULE scenarios at the failure class
  unit tests can't reach (state corruption + stuck notes under pathological host behaviour); both obey the SEED LAW
  (replayable; failures pin per-runner in `testPinnedRegressionSeeds`). **TRANSPORT CHAOS** (`runTransportChaos`/
  `testTransportChaosInvariants`, 300 seeds): seek-backward · loop-to-top · big forward jumps · tempo+sample-rate
  switches · pathological block sizes (1 sample…4096…a prime), all with a chord held across the discontinuities —
  everything is derived from beatPos (invariant 2) so no schedule may strand a voice or break quiescence after the
  flush. **SNAPSHOT-SWAP CHAOS** (`runSnapshotSwapChaos`/`testSnapshotSwapChaosInvariants`, 300 seeds): republish
  the box at high frequency while a chord sounds, rerouting UNDER the live notes (bus channels · buses ·
  emitter-enables · key) — a generation change alone doesn't flush (only edges do), so the close/adoption machinery
  + the unconditional panic must retire the old (cable,ch,note) wires. **`testChaosDeterminism`** (80+80): same seed
  ⇒ byte-identical stream. Both scenarios GREEN — confirms the derivation + panic-flush are robust across the
  adversarial space. Refactor: shared `flushAndSettle`/`measure` (runFuzz reuses them, behaviour-identical). NOT
  DONE (needs the user, device): the near-free TSan-on-ChaosDriver run — the off-device harness is single-threaded
  so TSan pays off only against ChaosDriver's live render↔main concurrency (Layer 2, device/`#if DEBUG`). Flip
  Thread Sanitizer on the DEBUG device scheme to catch races-that-would-fire (the class the `recvLiveHeld` crash was).**
- **▶ UNATTENDED COVERAGE + REFACTOR PASS (2026-08-07, on `main`, PUSHED `a78af50`; macOS 506 green, iOS + macOS
  build). Ran after pushing the macro-rebuild/mosaic-crest/playhead batch (`af2040d`). +5 tests:
  `testMosaicLayoutClampsExtremeAspectAndStillTiles` (extreme/degenerate crest aspect stays valid, width ≤0.9,
  face still tiles to 1.0) · `testMacroApplySnapsOptionStepperMask` (macroApply snaps option/stepper/mask at the
  halfway point like toggle) · `testMacroGroupForProcessor` (group id/domain/title/params) ·
  `testProcessorParamKindsPerType` (each type's own mask/stepper kinds) · `testApplyProcessorValuesClampsDiscretes`
  (write-back clamps out-of-range octaves/pattern-option/passMask — a stale value never traps). REFACTOR:
  `MacroParam` is now `CaseIterable`; the "foldable continuous params" set in `macroAuthorBind` (EditPage) + the
  descriptor test derive from `MacroParam.allCases` instead of a duplicated string literal (single source). Orphan
  scan clean — `ProcessorSlot.paramsAlt`/`bypassedAlt` are now unused by the redesigned pop-up but KEPT reserved
  (Paul's macro revisions land 2026-08-08). Ferry UPDATE `_dear_claude/UPDATE-2026-08-07-macro-mosaic-playhead.md`
  written (gitignored, awaits design ack of it + `REPLY-2026-08-06-macro-authoring-plan.md`).**
- **▶ MERGED `feat/macro-authoring` + `feat/mosaic-cell-face` → `main` (2026-08-06; iOS builds, macOS 499 green;
  DEVICE pass owed). Two features consolidated at the user's word ("merge everything").**
  - **MACRO AUTHORING FLOW (canonical, spec `AcceptanceCriteria-macro-authoring.md`) — processor domain, device-
    tuned.** A GENERIC control-group authoring flow (Paul: "about CONTROLS, not processors"): `MacroAuthoring.swift`
    = data-only registry (`MacroControlKind` continuous/toggle/option/stepper/mask · `MacroControlParam/Group`) +
    pure logic (`macroSparseDelta` §3 · `macroDeltaHasDiscrete` §5 · `macroApply` offset preview) + processor
    value get/set (`processorValues`/`applyProcessorValues`, round-trip tested) + `macroParamsForProcessor`.
    `MacroAuthoringView.swift` = the MAIN/ALT authoring page (generic `MacroControlEditor` per kind) + TEST morph
    slider + `MacroAssignmentView` (8 sliders/8 buttons; discrete deltas dim sliders §5) + APPLY/CANCEL. A MACRO
    pill on each processor slot (`ProcessorBox` slotMode) opens it; `EditPage` callbacks: MAIN is REAL, TEST
    previews live, ALT persists to `ProcessorSlot.paramsAlt` (§7, additive Optional), bindings stage on ASSIGN +
    commit on APPLY (continuous keys → `addMacroTargets`); rides the processors-page edit session (§6). DEVICE
    tuning: real-time audibility (dropped per-tick `refreshFromDocument`; auto-AUDITION the cell while open) +
    SWAP/RESET on both boxes. Keeps the offset engine (M1)/AU params (M2)/MACROS tab (M3); `MacroBindPopup` still
    present (retire once device-verified). DEFERRED: receiver/emitter/rack domains · the discrete-param (button/
    timeline) binding path · the future MACRO MAIN management tab. 9 tests (`MacroAuthoringTests`).
  - **THE MOSAIC cell face (candidate F, spec `-mosaic-face.md`) SHIPS as the cell face** (`useMosaicFace = true`
    in GridUI — flip to restore the SEAL, kept intact). `Derivations.mosaicLayout(hash:)` (pure, 4 tests) → a 4–6
    block Mondrian from the seal hash (twins share); `GridUI.drawMosaic` = coloured blocks + dark grout + rank
    depth, envelope-driven per-strike flash (device-tuned for legibility + change-on-play), used by the grid cells
    + the edit identity plate. **Phase-2 owed: the per-NOTE pool-rank + duration feed (engine work).**
- **▶ QUALITY PASS — tests · dead-code · dedup · one real bug (2026-08-05, on `main`; macOS 460→487 green, iOS
  builds; NOT pushed). A survey-driven legibility/coverage pass (3 parallel survey agents → verified + implemented
  in-loop). Commits `c9f28cb`→`753b875`. (1) `c9f28cb`: UI — whole-UI scroll (header+tabs scroll WITH the body when
  the content overflows, raw when it fits to keep ColumnHoldOverlay alive), SINGLE|MULTI moved to the title bar,
  row/column selectors tint by mode (SINGLE green · MULTI yellow via `GridView.laneHue`), CONTROLS placeholders
  RANDOMIZE·AUTOMATION·MUTATE·AUTOPLAY, macro rotaries→sliders (`GridMacroSlider`), consistent `bandLabel`/
  `labeledPanel` panel headers + PROCESSOR GRID title. (2) `d6377e2`: +18 pure-core tests (resolved4 all branches ·
  rack/modulation Codable round-trips + old-doc-nil→resolved-default · effectiveRepeats/Octaves/HarmInterval/
  RateBeats clamps · applyMacros neg-index/zero-offset · midiNoteName · chopSlice wrap · tapOverlayMasks future-
  onset · colourCensus empty · trigger-glyph totality · heldVelocity). (3) `8c19e45`: +5 Router tests (render-side
  param route/invariant 6 · playing CHANCE · sceneFlush · bypass multi-dest). (4) **`84e67d8`: REAL BUG FIX** — a
  fenced LEGATO drone machine-gunned: `emitColumnHolds` predicted the adoption wire pitch as `n+emitterOctaveShift+
  masterKey` but `emitOneBus` applies FENCE after, so a CLAMP/FOLD emitter's voice diverged → adoption failed →
  re-strike every boundary. Fix: one `fencedNote(_:bus:)` helper used by BOTH the emit path (behaviour-identical
  refactor) and the prediction. Regression test reproduces (ons 6→2, offs>0→0). (5) `8ea1cb0`: −224 lines
  grep-verified dead code (VIZ view cluster + roundVerb/recolorSelection/editBrushColour/holdSeq/selectionSnapshot
  in VC · ReceiversView strip leftovers bypassToggle/latchRow/modeSeg/featBtn/slider/decayed/faderVel +
  MarchingAnts in GridUI · Cell.hasChain/Colour.hasTemplate · EditPage inputSourceLabel/setEditSourceNone · Kernel
  dup import). (6) `7b8817d`: extracted shared pure helpers `clampVel`/`positiveFract`/`splitmix64Mix` (dedup 5+2+2
  sites) +3 helper tests. (7) `753b875`: stale-comment/naming fixes (chainDriverIndex doc · currentColourIndex ·
  CHOP fragment · CogPage mpeToggle→onOffToggle · TestSessions header). DEFERRED (flagged, need a ruling — see
  pending-tasks): the accent-colour dedup (B1: ~35 sites/14 names for 2 colours; FlowView's `0.145` cyan is a real
  near-miss needing a decision) · `midiNoteName` vs `RackMatrix.noteName` octave convention (C4 vs C5) · the
  over-long-function decompositions (poll closure/cellView/renderFlow — high-churn, skipped as unsafe unattended).**
- **▶ MERGED `feat/macros` → `main` (fast-forward, PUSHED, `c661025..6b2d609`, 2026-08-05). Banked: the whole MACROS
  feature (M0–M4 + BUTTON bank + OUTPUT engine/authoring) · the MIDI compliance audit + its fixes (B1 THRU-system ·
  B2 stuck k=1-lap drone · B3 fullState flush · B5 altSequence prealloc; B4/B7 deferred) · a test/refactor hardening
  pass (clamp/gated/packMask/resolved4/bit helpers) · ferry captures. macOS 453 green, iOS builds. DEVICE pass owed
  (macros + the audit fixes + the tab era). All other feature branches (EditPageSpike/emitter-page/flow-view/step3/
  multiple_features) are already contained in main's history. NEXT macro: TIMELINE bank (needs the render-time
  per-column path); INPUT [AB] group skipped as underspecified.**
- **▶ MACROS (phase 2 track) — engine + AU params + tab panel + A/B authoring; NOW ON `main` (see the merge line
  above), 2026-08-05. The macro MODULATION layer per the macro-panel + macro-ab-authoring + overlay-rule-macro-lanes
  specs. Commits `1c23fad`→`895f8c9` (M0–M3). **M0** `1c23fad`: the state model —
  `Macro { name·value 0…1·fixed(padlock)·targets[] }` + `MacroTarget { col·row·slot·param·delta(B−A) }` + `MacroKind`;
  `PluginState.macros: [Macro]?` (additive-Optional) + `macrosResolved` (24, banked 0–7 sliders·8–15 buttons·16–23
  timelines) + `macroKind(i)`; `SnapshotBox.macroValues: [Double]`. **M1** `fe814f8`: the offset term
  `Snapshot.applyMacros(base, mods, values)` = `clamp(base + Σ vₖ×deltaₖ)` (overlaps SUM then clamp once; clamps
  match `resolve`), FOLDED into each cell's resolved `procs` in `SnapshotBuilder`'s cell loop (grouped by
  (col,row,slot)). Bases/document/seals (sealHash reads the document, not procs) are UNTOUCHED → twins stay twins.
  **KNOWN v1 BOUNDARY: values bake at publish (a macro move = a rebuild); the render-time per-column path that
  TIMELINE lanes need lands with that bank.** **M2** `921bbc6`: `ParamAddress.macro(i)=400+i` — the 8 SLIDERS
  (400–407) as host-automatable AU params (block 400–423 reserved for the 24; a future transposeB must use base
  ≥500); observer folds a write into `document.macros` as an offset, provider + on-load sync mirror doc→tree;
  `setMacroValue` UI twin. **M3** `895f8c9`: `MacroPanel.swift` = the MACROS tab — BTN|SLD|TML selector; SLIDER bank
  = 8 vertical faders (drive values via the tree; name-chip rename; foot padlock SPRING-releases-home / FIXED-latches);
  BUTTON bank = A|B pads (momentary/toggle); TIMELINE = placeholder; unset slots recede as invitations. AU
  `setMacroName`/`setMacroFixed`/`uiMacros`. **M4** `03a7015`: A/B AUTHORING — `MacroBindPopup.swift`, opened by an
  `[AB]` button on the Edit page's CHAIN header. Captures A on open; per-slot continuous-param sliders live-write B
  to every selected cell (twin write law, heard live); binding a macro slider stores delta = B−A per touched param
  (`addMacroTargets`); close restores A (`setCellChain`) so the macro holds B as an offset. `ColourParams.macroValue/
  setMacroValue`; `removeMacroTargets` (the "THIS CELL ✕" chip). **v1 scope: CHAIN group + SLIDER bank only.**
  MACROS ARE NOW USABLE END-TO-END (author on Edit → drive from the MACROS tab / host automation). DEFERRED (honest
  boundaries): INPUT/OUTPUT [AB] groups (need the offset extended to receiver/emitter-amount param families) ·
  BUTTON/TIMELINE binding + mover-eligibility live-dim · the A↔B morph-audition slider (v1 auditions by editing B
  directly). Tests in `Tests/EffectiveParamsTests.swift` (M0 state · M1 offset math · builder end-to-end · seal
  stability · M4 A/B-reconstructs-B-at-1/A-at-0). Plan/specs: `Docs/AcceptanceCriteria/AcceptanceCriteria-macro-panel.md`
  · `-macro-ab-authoring.md` · `-overlay-rule-macro-lanes.md`. **NEXT: device pass; then either the TIMELINE bank
  (needs the render-time per-column path, replacing M1's bake-at-build) or extend the offset to INPUT/OUTPUT.**
- **▶ LAYOUT v2 — THE TAB ERA, phase 1 (the tab shell); all on `main`, 2026-08-05; iOS builds, 428 green; DEVICE
  pass owed. Six commits `41aa233`→`8504957` (Parts 0-5). Replaces the PERFORM/EDIT toggle + in-grid overlays with
  ONE permanent address per surface — a six-tab bar (`enum AppTab`: GRID · PROCESSORS · RECEIVERS · EMITTERS ·
  MACROS · AUTOMATION; `.live` gates the last two dim/inert). **Part 0** (`41aa233`) retired the (inert) SELECT verb
  — enum case + hue + button + `doVerbOnRow`/`strokeCell`/`onVerbEngaged` branches gone; verb cluster now
  HOLD·MUTE·LADDER; `selection`/`selectionSnapshot` kept (always empty). **Parts 1-2** (`b228a64`): `ArrangementBar`
  `modeToggle`→`tabBar` (own row under the header; `activeTab`/`onSetTab` replace `isEditMode`/`onSetEditMode`);
  VC body switches on `activeTab` via `tabBody` (.grid→signalColumn · .processors→editSpikePage · .emitters→
  rackMatrixView · others→`comingSoonPage`); `.onChange(of: activeTab)` bridges `editArmed = (tab == .processors)`
  so the begin/apply edit-session logic is unchanged; `EditPage` dropped its own `arrangementBar` (parent renders
  once). **Part 3** (`1a50756`): STEP+SWING leave the grid `ControlsView` (struct + `controlsView` var deleted) →
  a `clockControl` chip+popover in the header; receivers band's left flank is now empty (keeps RECEIVERS centred).
  **Part 4** (`b96bc09`): per-door MIDI INPUT config extracted from `CogPage` into new
  `AUExtension/ReceiverConfigView.swift` = the RECEIVERS tab; cog keeps OUTPUT·DISPLAY·HEALTH (its `receivers`/
  `inAt`/`mpeAt` inputs + input-only helpers removed). **Part 5** (`8504957`): rack matrix is the full-page EMITTERS
  tab; `GridView.cellAreaOverride` machinery removed; strip RACK long-press → `activeTab = .emitters`, DONE →
  `.grid`; `rackMatrixOpen` state gone. DEFERRED phase 2+ (captured, not built): GRID top-band 8 macro sliders+
  buttons · SINGLE|MULTI · HOLD localisation · MACROS/AUTOMATION engines · global FREEZE/STUTTER · MIDI-OUT channels
  into the emitters tab. Plan: `~/.claude/plans/resilient-imagining-truffle.md`.**
- **▶ MERGED `feat/multiple_features` → `main` + EDIT-PAGE REARRANGE + 6 design captures (2026-08-05; iOS builds,
  427 green). The whole branch (FENCE UX · per-note TURNS · bypass + loop bug fixes · seal lock · in-app manual ·
  manual Why-merge · macro capture) fast-forwarded onto `main`. Design **endorsed the RACK full-bypass** ruling
  (rack-off = whole board out, as built). NEW: EDIT-PAGE REARRANGE (`INSTRUCTIONS-edit-page-rearrange`, on `main`) —
  `EditPage.editSpikePage`: grid LEFT-aligned + smaller; a VERTICAL `modeRail` beside it (ADD/EDIT·MOVE·MUTE·CLEAR +
  the mode helper under the buttons + APPLY/CANCEL anchored at the grid's bottom, rail height == grid height);
  `sectionSeam()` faint dividers between IDENTITY/FROM/CHAIN/TO; "+ ADD PROCESSOR" is a dim dashed GHOST BOX the
  width of a processor window. CAPTURED (spec-of-record, NOT built — large): `AcceptanceCriteria-split-processor`
  (SPLIT chain stage — membership law, [SPLIT→ARP] re-pool vs [ARP→SPLIT] punch-holes) · `-shape-arp` (fixed
  LENGTH + OVERFLOW) · `-dice-authoring` (randomization authoring) · `-pool-aware-family` (set-awareness roster) ·
  `-layout-v2-tabs` (THE TAB ERA — supersedes PERFORM|EDIT + verb cluster + global HOLD; SELECT → RETIRE implied,
  still on Paul's word) · `-edit-page-rearrange`. Ferry inbox cleared; the bugs/macro/manual + specs replies await
  the design side's ack. Device pass owed for the whole RACK + the edit-page rearrange.**
- **▶ IN-APP MANUAL — the "?" reader (2026-08-05, branch `feat/multiple_features`; 427 green, iOS builds; DEVICE
  pass owed). User: a "?" in the top-right that opens the manual scrolled to the LAST-TOUCHED control. Built native
  (no WKWebView): `AUExtension/ManualView.swift` = `HelpTracker` (ObservableObject, lastAnchor NOT @Published — a
  silent reference read on open, no per-touch re-render) + a `.helpAnchor("#id")` view modifier (simultaneous
  TapGesture → never steals the control's gesture) + `ManualDoc.load()/parse()` (loads the BUNDLED
  `Docs/manual/manual-skeleton.md` — added as a `buildPhase: resources` source in `project.yml`; renders line-based
  markdown to blocks, inline via `AttributedString(markdown:)`) + `ManualView` (a `ScrollViewReader` that
  `scrollTo`s the anchor; the target block highlights). The "?" is in `ArrangementBar` (`helpButton`, by the cog) →
  VC `showManual` overlay reading `helpTracker.lastAnchor`; `helpTracker` injected via `.environmentObject` at the
  VC root; `Self.manualBlocks` parsed once (static). WIRING v1: per-control on the HEADER (#logo · #presets-open ·
  #perform-edit-toggle · #transport-readout · #undo · #cog-open) + SECTION-level on the surfaces (#receivers · #grid
  · #emitters · #master · #verbs · #clock) — all anchors that exist in the skeleton. DEFERRED: per-control depth
  inside the strips/grid (section-level for now); manual entries for the RACK (touching it lands on #grid); the
  docs-test (registry ⇔ anchors). Project regenerated via xcodegen (new file + resource).**
- **▶ BRANCH `feat/multiple_features` — FENCE UX · per-note TURNS · 3 device bugs · manual merge · macro capture
  (2026-08-05; NOT on `main` — user merges; 427 green, iOS builds). Batched the user's asks + Paul's device-session
  ferry. (1) **FENCE UX**: `setFence` on-ENABLE now seeds a sensible window when it's still full-range — policy
  CLAMP + C2…C6 — so FENCE audibly acts instead of no-op'ing; `RackMatrix.fenceRow` shows the active range inline
  ("C2–C6") beneath the policy chip (the LO/HI were undiscoverable in the detail strip). (2) **per-note TURNS** —
  the selectable hand-off mode, refined by the user to be EXCLUSIVE: `PluginState.turnsPerNote` (+ box + builder);
  `Router.emitArtic` — PER-MOMENT (default, simultaneous → one holder, both sound) vs PER-NOTE (the group is
  TIME-EXCLUSIVE — a note at the same onset as an already-played group note is DROPPED, never delayed; leftmost
  wins). AU `setTurnsPerNote`; a global HAND-OFF PER MOMENT|PER NOTE toggle in the TURNS detail strip. Test
  `testTurnsPerNoteDropsSimultaneousNoteNotDelayed`. (3) **BUG bypass-passthrough** (Paul): `SnapshotBuilder` now
  collapses an all-bypassed chain to the empty-chain passthrough (`chain.allSatisfy(\.bypassed)` ⇒ born-audible
  identity), ONE rule instead of the fragile count-dependent Router paths. Test `testAllBypassedChainIsPassthrough
  AtAnyDepth` (1-slot + 8-slot + partial-unaffected). (4) **BUG loop-persistence** (Paul): deleted the duplicate
  `editLoopMask`; the EDIT page drives the one perform `laneMask` (`setLane`) + reads it, and leaving EDIT no
  longer zeroes it — the column loop survives the EDIT↔GRID switch and shows on both pages. (5) **BUG seal/outputs**:
  investigated — the reported premise is STALE (`sealHash` ALREADY covers buses/chop/altDest/input; a passing test
  asserts emitter-change ⇒ different seal). Added `testSealHashCoversTheFullTwinContract` (altDest/altMask/inputRow/
  chordSplit/velWindow) to LOCK it. Did NOT do the literal twin←sealHash unify: `sealHash` is JSONEncoder-based and
  `twinCells` recomputes per render (128 encodes/frame = perf regression), and it would make twins colour-blind
  (semantic change) — flagged to design for confirmation. (6) Captured `DESIGN-macro-panel.md` →
  `AcceptanceCriteria-macro-panel.md` (build later, own branch). (7) Merged all 67 authored `_Why:_` fills into
  `Docs/manual/manual-skeleton.md` (only `{#select}` + the template line remain TBD). DEVICE pass owed for the UI
  items (FENCE range, TURNS mode toggle, loop persistence, bypass passthrough).**
- **▶ THE RACK — MONO · POCKET · CONVERSATION un-dimmed (all 8 primary treatments now LIVE) (2026-08-05, on `main`;
  424 green, iOS builds; DEVICE pass owed). User: "implement all of these." Three new render-path treatments, each
  model (additive Optional) + box + builder (rack-gated) + `Router.emitOneBus` + AU + RackMatrix UI + tests.
  **MONO** (`monoMask`/`monoPriority` 0 LAST·1 LOW·2 HIGH): force one note per emitter — reads the emitter's current
  holder from the voice table (scan, no tracker to clean), decides by priority, and STEALS (closes holder own+All at
  the new onset via `closeVoice`, then opens new = RETRIG); loser suppressed. UI = a PRIORITY cycle chip (new
  generic `cycleRow`). **POCKET** (`pocketMask`/`pocketMs` −50…50): shift a note's on/off equally (duration kept),
  clamped into [renderStart, windowEnd]; `pocketSamples` = ms·sr/1000 computed per render. UI = bipolar knob (ms).
  **CONVERSATION** (`convLead: Int8`/`convStance` 0 FREE·1 WITH·2 AGAINST, stance rack-gated to FREE): a follower's
  note-on gated on `emitterSounding(convLead)` — WITH admits while the lead sounds, AGAINST in its silences (a live
  query like KEY; co-onset order-dependent, the claim L1 caveat). UI = a LEAD radio + per-column STANCE chips
  (`conversationRow`). Tests: `testMonoKeepsOneNotePerEmitterByPriority` + `testMonoLeavesNoStuckNotes` +
  `testPocketLagDelaysOnsetAndIsRackGated` + `testConversationWithAndAgainstGateOnTheLead`. ALSO added
  `testTurnsDoesNotAlterNoteTiming` (per user: TURNS COUNT 1 must not shift timing — confirmed, only the emitter
  changes). No new files (no xcodegen). DEFERRED: mono RETRIG|LEGATO detail (chords churn re-strikes at onset, v1);
  pocket humanize; ECHO/CHOKE/GOVERNOR seats; all secondary detail params. Spec `AcceptanceCriteria-the-rack.md`
  §5/§6 (all 8 primary live) + device steps `test-procedures.md` RK-MONO/RK-POCKET/RK-CONV.**
- **▶ THE RACK — FENCE treatment un-dimmed + knob sensitivity lowered (2026-08-05, on `main`; 419 green, iOS builds;
  DEVICE pass owed). FENCE = a per-emitter note-RANGE policy on the OUTPUT pitch: out-of-[lo,hi] notes DROP
  (suppress) · CLAMP (to nearest bound) · FOLD (octave-fold in). `PluginState.fenceMask`/`fencePolicy`/`fenceLo`/
  `fenceHi` (additive Optional) → box fields → builder pre-ANDs `fenceMask & rackMask` → `Router.emitOneBus`
  applies the policy to the note right after the OCT/masterKey shift (so CLAIM/metering/refcount key on the fenced
  pitch and the note-off pairs cleanly; `fenceFold` ±12, clamps if the window < an octave; previewMode bypasses).
  AU: `uiFenceMask`/`setFence`/`cycleFencePolicy`/`uiFencePolicy`/`setFenceLo`/`setFenceHi` (persisted). UI: the
  RackMatrix THIS-VOICE **FENCE** row (`fenceRow`) — toggle over a POLICY cycle chip (DROP→CLAMP→FOLD, an ENUM
  primary, so no knob); LO/HI note-steppers are LIVE in the detail strip (`fenceDetail`/`noteStepper`, C4=60);
  readout "FENCE FOLD C2–C4". Also: the rack KNOB drag is LESS SENSITIVE (÷6 → ÷14 px/unit, user request). No new
  files (no xcodegen). Test: `RouterTests.testFencePolicyDropClampFoldAndRackGate` (drop/clamp/fold/in-range/rack-off).
  Spec `AcceptanceCriteria-the-rack.md` §5/§6 + device step `test-procedures.md` RK-FENCE. STILL DIMMED: MONO (needs
  voice-stealing) · POCKET (timing) · CONVERSATION.**
- **▶ THE RACK — CURVE treatment un-dimmed (2026-08-05, on `main`; 418 green, iOS builds; DEVICE pass owed).
  Continuing the emitter work: the first of the dimmed THIS-VOICE seats goes live. CURVE = a per-emitter output
  velocity RE-MAP (soft↔hard). `PluginState.curveMask`/`curveAmount` (−100…100, additive Optional) → box
  `curveMask`/`curveAmount: [Int8]` → builder pre-ANDs `curveMask & rackMask` (rack-gated like claim/duck/alt) →
  `Router.emitOneBus` applies `curveVelocity(v, amount)` = `u^(2^(−amount/100))` (u = v/127) to the shaped velocity
  BEFORE the master fader (previewMode bypasses). AU: `uiCurveMask`/`setCurve`/`uiCurveAmount`/`setCurveAmount`
  (persisted, undoable). UI: the RackMatrix THIS-VOICE **CURVE** row is now a `liveRow` with the existing rotary
  KNOB run BIPOLAR (minV −100 / maxV +100; toggle → `toggleCurve`, knob → `setCurveAmt`); readout gains a "CURVE
  +30" clause; detail strip names FLOOR/CEILING as coming. No new files (no xcodegen). Test:
  `RouterTests.testCurveRemapsOutputVelocityAndIsRackGated` (+50 boosts, −50 softens, 0/off = identity, rack-off =
  raw). Spec `AcceptanceCriteria-the-rack.md` §5/§6 + device step `test-procedures.md` RK-CURVE. STILL DIMMED:
  MONO (needs voice-stealing) · FENCE (range policy, needs an enum chip) · POCKET (timing) · CONVERSATION.**
- **▶ TURNS — cross-cell dealing on the EMITTER (2026-08-04, on `main`; 416 green, iOS builds; DEVICE pass owed).
  Two-step: (1) REVERTED the short-lived cell-turns feature (commit `d0ac7f4` reverts `f137e03` — `Cell.turnsGroup`,
  the SnapCell fields, builder resolution, `turnsSilent`, the EDIT ▸ TAKES TURNS UI, and the RackMatrix TURNS-row
  removal are all GONE; the emitter TURNS row is back). The user's true intent was NOT per-cell grouping. (2)
  REWORKED the emitter ALT/TURNS engine (`Router.emitArtic`) so the TURNS emitters take turns IN TIME playing the
  INCOMING notes from ANY cell. The turn advances once per ARTICULATION MOMENT (a new onset SAMPLE — `altLastOnset`/
  `altMomentIndex`, `currentPass` idea dropped); every note at that moment routes to the one holder
  `altSequence[altMomentIndex % len]`, then the next moment hands off. So two independent cells firing at the SAME
  instant both sound on ONE emitter and alternate over moments (A then B — NOT both at once), while a single fan-out
  cell whose notes land at distinct times still ping-pongs per note. COUNT = moments of DWELL (was notes-per-turn).
  Two iterations landed: first whole-group dealing via a per-NOTE pointer (fixed single-target cells stuck on their
  own emitter — the old code dealt only among members PRESENT in one cell's fan-out); then the per-MOMENT hand-off
  (the per-note pointer SPLIT simultaneous cells at COUNT 1 — the user's second report). Reset at transport-start
  only. No model/snapshot/AU/UI change — the rack TURNS toggle + COUNT knob (`altMask`/`altCount`) unchanged; only
  the render routing rule. Tests: replaced `testAltEdgeSkipsAbsentMemberWithoutStarving` (obsolete) with
  `testAltDealsSingleTargetNotesAcrossTheGroup`, `testAltPoolsTwoIndependentCellsAcrossTheGroup`,
  `testAltHoldsAtSameMomentDoNotSplitSimultaneously`; `testAltTurnTakingPingPongsAndHonoursCount` still green (417
  total). KNOWN minor: a window holding 2+ arp ticks across multiple cells can misalign a moment (cells processed
  sequentially, onSample non-monotonic) — negligible at normal rates; holds (one onset/lap) are exact. Docs:
  `AcceptanceCriteria-the-rack.md` §6 TURNS + `test-procedures.md` RK-TURNS updated.
  **⚠ REVIEW OWED (user, 2026-08-05): confirm the per-MOMENT hand-off is what's wanted on device — the user may
  prefer the per-NOTE variant ("by note"), where the turn advances every note (alternates faster; is the pre-fix
  behaviour, and splits simultaneous cells). Both are viable; the switch is a ~1-line change in `Router.emitArtic`
  (advance per onset-moment vs per note). Do NOT retire the per-moment code until the user rules — they flagged they
  might want it by note later.**
- **▶ THE RACK — emitter treatment matrix, PASS 1 (2026-08-04, on `main`; 415 green, iOS builds; DEVICE pass owed).
  Design ferry `DESIGN-the-rack.md` → spec of record `Docs/AcceptanceCriteria/AcceptanceCriteria-the-rack.md`.
  SUPERSEDES the tabbed emitter page (`EmitterPage.swift` DELETED; `AcceptanceCriteria-emitter-page-pass1.md`
  retired). The metaphor: each output has a RACK — matrix toggles ARM pedals; a strip button decides whether the
  board is in the signal path (the TWO-TIER LAW). Pass-1 scope (user-confirmed): the full shell + the gate + the 3
  engine-backed verbs' PRIMARY controls; the rest are dimmed 'coming' seats. What landed: (1) STRIP goes clean —
  OCT±·velocity·LIVE·SOLO·**RACK** (`OutputsView.rackColumn`/`rackButton`; the CLAIM/DUCK/ALT `roleButton`s +
  their inputs REMOVED). RACK tap = `toggleRack` (toggle board in/out of path); long-press = open the matrix.
  (2) NEW `AUExtension/RackMatrix.swift` — a 4-column (emitters A–D) × treatment-rows matrix, grouped THIS VOICE /
  OVER OTHERS / TOGETHER (design §5); OWNS/KEY/TURNS live (toggle + primary ROTARY KNOB → existing claim/duck/alt;
  descriptive row labels "Claims this note from others" / "Ducks others' velocity" / "Takes turns with others");
  MONO·FENCE·CURVE·POCKET·LEAD-STANCE·ECHO·CHOKE·GOVERNOR dimmed; column-header tap → social-sentence readout;
  detail strip follows the last-touched row (secondary params named-but-dimmed). (3) GEOMETRY — drawn INSIDE the
  grid's cell area (user: 'keep the chevron row + column selectors, draw the panel inside'): new
  `GridView.cellAreaOverride` swaps ONLY the 8×8 body, so the chevron column-key row + both `rowRail`s stay framing
  it; the wholesale `emitterPageFor` branch in `signalColumn` is gone (`emitterPageFor`→`rackMatrixOpen`).
  (4) ENGINE — the only new engine this pass = the two-tier gate: `PluginState.rackEnabledMask: UInt8?` (nil ⇒
  0b1111, old-doc/clean safe) + `rackEnabledResolved`; `SnapshotBuilder` PRE-ANDs it into claim/flatten/alt before
  the box (`SnapshotBox.rackMask` also carried for future self-affecting treatments); Router UNCHANGED; AU
  `uiRackMask()`/`setRack()`. Tests: `RouterTests.testRackOffMakesClaimantARawWire`, `testRackOnKeepsClaimSuppression`,
  `testRackGatePreAndsTreatmentMasksIntoTheBox`. Project regenerated via `xcodegen`. OPEN RULING (flagged, device):
  RACK-off = FULL-column bypass (suspends the emitter's OWNS/KEY over others too, since those are its pedals) — the
  alternative (gate only self-affecting) is a 1-line builder change. DEFERRED (later passes, un-dim a seat as each
  lands): MONO·FENCE·CURVE·POCKET·CONVERSATION engines + all secondary detail params (claim scope/range/lag · duck
  targeting/envelope/match-class · alt rotate|deal/ring/reset).**
- **▶ FUZZ HARNESS + CHAOS MODE — both built (2026-08-04, on `main`; 412 green, iOS builds; Layer 2 device-run owed).
  Ferry-ratified pre-beta hardening. LAYER 1 `Tests/FuzzTests.swift` (5 tests, ~18s): seeded (`mulberry32`) random
  doc + a SPELL-driven pool (**held → short → silence**, per the user) + pathological orderings, driving
  `Router.process`. Invariants: I5 in-range · I1/I2 no-key-sounding-after-flush (LAST-event-per-key, NOT a net count
  — the collision refcount folds many ons into one off) · I8/I10 `Router.quiescent` · I6 determinism (byte-identical
  same-seed, 200) · I12 SnapshotBuilder totality (4000) · I13 NotePool robustness (3000). Failing seeds pin into
  `testPinnedRegressionSeeds`. Added `Router.quiescent` (+ `hasDuplicateVoices`, unused — naive I3 flags legit
  refcount collisions; needs an adoption-aware hook). LAYER 2 `AUExtension/ChaosDriver.swift` (`#if DEBUG` whole
  file): seeded jittered MAIN-thread loop driving ~24 AU control handlers while the engine renders live (catches the
  render↔main crash class); `▶ CHAOS` chip in the dev overlay shows the seed + writes `chaos-0x<seed>.log`. The
  harness caught its OWN check bugs first pass (net-count I1/I2, over-strict I3) — corrected; `quiescent` never
  failed → the engine is clean under the fuzz. Determinism CONFIRMED. Spec: `AcceptanceCriteria-fuzz-and-chaos.md`.
  Project regenerated via `xcodegen`. NEXT (deferred): nightly-soak scheme; ring-buffer logger; adoption-aware I3;
  optional `KernelCore` extraction to fuzz the Kernel orchestration pre-device.**
- **▶ EMITTER PAGE — pass 1 (2026-08-04, on `main` via merge `b0668d9`; 407→green, iOS builds).
  The full-size band desk, first pass = shell + entry/exit + today's controls only (no new engine). New
  `EmitterPage.swift` renders IN PLACE OF THE GRID (signalColumn swaps `gridBlock` when `emitterPageFor != nil`);
  strips/master/verbs stay live around it. Entry: LONG-PRESS an emitter role button (CLAIM/DUCK/ALT → that section)
  or its header (→ top) — `OutputsView.onOpenPage`; the role long-press uses a `roleLongFired` flag so the drag's
  release doesn't also toggle (a >10px drag cancels the long-press, so drag-to-set still works). Header: A·B·C·D
  tabs + DONE. Live readout (true clauses only). Sections wired to the EXISTING callbacks (VOICE = channel display +
  OCT · CLAIM+leak · DUCK+amount · ALT+count); FEEL/CONVERSATION/ECHO/CHOKE/DENSITY + VOICE curve/MONO/FENCE are
  dimmed "coming" seats. Closes on DONE · EDIT toggle · scene switch. Project regenerated via `xcodegen generate` to
  include the new file. Spec: `AcceptanceCriteria-emitter-page-pass1.md`. Pure UI → covered by the iOS build; the
  claim/duck/alt engine paths already have Router tests. Later passes add the new engine (MONO/FENCE/DUCK envelope/
  ALT rotate-deal-ring/FEEL/CONVERSATION).**
- **▶ CRASH FIXED — render↔main race on the header-dot poll (2026-08-03, on `main`; 406 green, iOS builds).
  Device crash (AUM host, MidiSparkAU): `EXC_BAD_ACCESS` in `_swift_release_dealloc`, main thread, via the 4 Hz poll
  timer (`NSTimer.TimerPublisher` → `.onReceive` → `DiagView.body` closure). ROOT CAUSE: the `recvLiveHeld` poll I
  added in the strip-polish commit returned the Kernel's `[Bool]` BY REFERENCE and the VC stored it in `@State`,
  keeping the Kernel's buffer PERSISTENTLY shared — so `updateReceiverSounding` (audio render thread) triggered
  copy-on-write + a refcount race on every per-element write, corrupting the buffer → crash on the next @State
  release. FIX: `recvLiveHeld` is now a scalar `recvLiveHeldMask: UInt8` (published in ONE store — race-safe like
  the other render→main masks); the VC unpacks it into a FRESH `[Bool]` that never shares the Kernel's buffer.
  LESSON: every render→main poll must return a COPY or a scalar, NEVER a stored array by reference (the other polls
  build a fresh `out` or self-detach via drain-reset). Races aren't unit-testable; verified by build + reasoning.**
- **▶ LADDER arm-commit FIXED — lap + row selector (2026-08-03, on `main`; 406 green, iOS builds; DEVICE pass
  owed). Two bugs, both arm-commit timing. ROOT CAUSE (bug 1 — looping a column, the armed rung just blinks, never
  switches): the commit fired on `onChange(of: d.effColumn)`, but during a column LAP (`heldColumns`) the engine
  REMAPS effColumn to the held column so it never changes → the arm never committed. FIX: expose
  `diag.absoluteStep` (Router: `Int((mNow / S).rounded(.down))`, set BEFORE the empty-pool guard) — the global step
  counter that increments each step EVEN during a lap — and commit on `onChange(of: d.absoluteStep)` (also added to
  the diag-poll write condition). Handles normal + lap uniformly (a step boundary = the sounding cell finished).
  Bug 2 — the ROW selector switched the currently-playing column INSTANTLY (cut the note): `setLadderRow` now flips
  every column EXCEPT the sounding one instantly and ARMS the sounding column (`ladderPending[effColumn]`) so its
  cell finishes then the new rung takes over. Test: `testAbsoluteStepAdvancesDuringAColumnLap` (effColumn pinned to
  the held column while absoluteStep still advances). Commit logic itself is VC-side (untested).**
- **▶ STRIP polish round 2 — scenes toggle, portrait, fixed height, +3 (2026-08-03, on `main`; 405 green, iOS
  builds; DEVICE pass owed). (1) The 16-scene row is HIDDEN by default — `@AppStorage("midispark.showScenes")` (VC)
  gates `ArrangementBar.showScenes`; a SHOW-SCENES toggle lives in a new cog DISPLAY section (`CogPage.showScenes`
  binding). (2) PORTRAIT (`isPortrait = geo.h > geo.w`, threaded body→signalColumn→receiversBox→ReceiversView): the
  LATCH button shows the padlock ONLY (no "LATCH" text). (3) PORTRAIT: the header shows the CHANNEL only (drops the
  range suffix). (4) The RECEIVERS band is now a FIXED height (`recvBandH = 168`, an ESTIMATE — flagged) instead of
  6 grid-rows; signalColumn recomputes `cell` from the remaining 15 rows (9 grid + 6 emitter). Emitters stay
  grid-aligned (so the two bands are now asymmetric — flagged). (5) Gaps (`Color.clear.frame(height: 5)`) between the
  LATCH cluster ↔ OCT and OCT ↔ LIVE·SOLO in performFeatures. (6) The BYP button is WHITE unless armed (cyan fill
  when on). THRU pip stays retired.**
- **▶ RECEIVER STRIP polish — 6 tweaks (2026-08-03, on `main`; 405 green, iOS builds; DEVICE pass owed). (1) BYPASS
  toggle moved into the header where the THRU pip was (pip retired; `thruReceiver`/`onSetThru` stay wired but
  unsurfaced). (2) `midiNoteName` now non-negative octaves (note 0 = C0 … G10) — no more "-1"; ASSUMPTION: 0-based
  (the note that read "D-1" now reads "D0", not literally "D1" — flagged to user). (3)(4) LIVE·SOLO moved from the
  foot to below the OCT nudges in performFeatures (right of the slider); the foot row is gone. Colours now match the
  EMITTERS: LIVE = cyan, SOLO = amber. (5) The slider meter shows LATCH velocities when a receiver is armed —
  `Kernel.updateReceiverSounding` reads `latchedPools[i]` (OMNI, already filtered) when `latchArmMask` bit set, else
  the live pool. (6) The velocity fader is now FIXED (no spring-back): the slider `onEnded` keeps the value; the
  engine override already persists. Plus: the header hue DOT lights from LIVE accepted input (never the latch) — new
  `Kernel.recvLiveHeld` (channel+cable+RANGE) → `pollReceiverLiveHeld` → AU → VC `recvLiveHeld` → ReceiversView
  `liveHeld`. v1 notes: fixed-vel is session-only (not doc-persisted); a muted/disabled door's dot is off (shares the
  admission filter).**
- **▶ BYPASS — per-door direct injection to emitters (2026-08-03, on `main`; 405 green, iOS builds; DEVICE pass
  owed). Redesign §1 strip toggle + §2 cog A–D destinations — the LAST redesign feature. A bypassed door skips the
  grid and its shaped, in-range held notes sound DIRECTLY on its destination emitters (a live monitor — works
  stopped). Model: `Receiver.bypass: Bool?` + `bypassDest: Int?` (A–D mask, nil ⇒ all) → `box.receiverBypassMask` +
  `receiverBypassDest`. Built ROUTER-side (testable via the MIDIEmitter double — a Kernel passthrough would NOT be):
  `effectivePool` returns emptyPool for a bypassed door's cells (grid diverted); `reconcileBypass` runs every render
  BEFORE the stopped/playing split (so it monitors while stopped), diffing each door's desired (note × dest) set and
  opening/closing via `openVoice`/`closeVoice` (reuses refcount + dual-cable + panic-safety). Bypass voices are
  IMMORTAL + tagged `Voice.bypassRecv ≥ 0`; `allNotesOff` gained `includeBypass` (default FALSE so transport/latch/
  scene edges leave them; PANIC passes true), and the grid's `holdCandidate` reconcile skips them. v1 SCOPE (flagged):
  applies RANGE + channel/cable admission (a MUTED/DISABLED door's bypass goes quiet — shares receiverChannels);
  octave/velocity shaping DEFERRED (output note = source note, so on/off balance by note). UI: strip BYPASS toggle
  (cyan, in performFeatures); cog A–D dest chips (dim until bypass armed). Tests: diversion, inject-to-dest (cable+ch),
  release-off, range, transport-stop-persistence. §3 defaults all hold via nil-resolvers (KEYS·OMNI·RANGE all·
  ENABLED·BYPASS off/dests all·LATCH off). REDESIGN COMPLETE pending device pass + SELECT verb ruling.**
- **▶ RANGE — per-door note window (2026-08-03, on `main`; 400 green, iOS builds; DEVICE pass owed). Redesign §2
  cog GAIN. A receiver admits only notes with lo ≤ note ≤ hi (default ALL), UPSTREAM of the latch + grid feed.
  Model: `Receiver.rangeLo/rangeHi: Int?` (nil ⇒ 0/127) + `rangeLoResolved`/`rangeHiResolved`/`rangeIsFull`. The
  window rides two ways: (1) per-cell `SnapCell.inputRangeLo/Hi` (from the cell's receiver) → the grid feed's source
  readers apply it — `srcCountFiltered`/`srcAscendingFiltered` (holds/strum/ratchet, alongside the vel window) AND
  `arpPickSource(for:)` (arps: RANGE only, vel intentionally still not applied to arps — added a range-aware
  `srcPlayed` so AS-PLAYED keeps press order); (2) `box.receiverRangeLo/Hi` → the Kernel's `captureFiltered`/
  `latchAddStep` (range gated the frozen pool = upstream of latch). Cog: RANGE chips (two note menus, octave
  submenus + MIN/MAX reset) on the input row via `midiNoteName` (shared, C4=60). Strip header now appends the range
  to its summary when narrowed (honors the earlier 'summarize channel + key range' ask). Tests:
  `testReceiverRangeFiltersSourceNotes` (robust to arp octave-span), `testReceiverRangeResolvesOntoCellAndBox`,
  `testLatchCaptureExcludesOutOfRangeNotes`. Chosen over BYPASS first (user call) — bypass's 'post-shaping' wants
  range in the stream. NEXT: BYPASS (§1 strip toggle + §2 cog A–D dests; Kernel direct-injection, device-verified).**
- **▶ STRIP LATCH — BIG LATCH + KEYS|CHORD on the strip (2026-08-03, on `main`; 397 green, iOS builds; DEVICE pass
  owed). Redesign §1 (sizing law + mode-to-strip) + §2 (latch chip leaves the cog) + §3 (KEYS default). The strip
  LATCH arm is now the BIG headline (40pt, lock glyph + "LATCH"; everything else on the strip stays small). The
  latch MODE moved OFF the cog ONTO the strip directly under LATCH as a **KEYS | CHORD** toggle (`keysChordToggle`/
  `modeSeg` in GridUI; `onSetLatchKeys` → VC `setReceiverLatchKeys` → `au.setReceiverLatchAdd`). KEYS = per-note
  toggle (was "ADD"), CHORD = detect-and-replace; the engine field stays `Receiver.latchAdd` (decode-compat, true =
  KEYS). DEFAULT flipped to KEYS: `latchAddResolved = latchAdd ?? true` (was `?? false`) — updated
  `testLatchAddMaskFromReceivers` (nil ⇒ KEYS, mask 0b1111). Cog INPUT row lost its CHORD|ADD chip + `latchSeg`/`seg`
  (doc lines updated). Mode-switching never clears the pool (Kernel resets only on the arm rising edge — unchanged).**
- **▶ INPUT ENABLE / DISABLE — the strip HEADER (2026-08-03, on `main`; 397 green, iOS builds; DEVICE pass owed).
  Redesign §1 ENABLE/DISABLE, delivered as the user asked: each receiver strip's HEADER now SUMMARISES the door
  (hue · letter · CHANNEL — "CH3"/"OMNI"; RANGE appends here once §2 ships) AND doubles as the listen toggle. Two
  independent per-door gates now: DISABLE (header) = the door stops LISTENING (dark meter, latch SEALED — no
  re-capture) while an ARMED latch keeps FEEDING its frozen chord to the grid; MUTE (foot LIVE/MUTED, existing) =
  stops the FEED into the grid entirely. Workflow: latch A, disable A, play B untouched ("close the door, keep the
  room"). Impl: `Receiver.inputEnabled: Bool?` (nil ⇒ enabled, persisted like mute) → builder sets
  `receiverChannels[i] = mutedSourceFilter` for disabled (dark meter + Kernel capture seals) BUT leaves the CELL's
  `inputChannel` = real channel so the frozen chord still reads → `box.receiverDisabledMask` → Router
  `effectivePool` returns the frozen pool when armed (feeds even while disabled), else `emptyPool` when disabled
  (blocks live read), else live. `toggleReceiverEnabled` on AU+VC; header tap in `ReceiversView.header(_:isThru:)`.
  Tests: `testDisabledReceiverKeepsFeedingArmedLatchIgnoringLive`, `testDisabledReceiverNotArmedIsSilent`,
  `testDisabledReceiverSealsMeteringButCellKeepsChannel` (RouterTests).**
- **▶ LATCH BUG FIXED (2026-08-03, on `main`; 394 green, iOS builds; DEVICE pass owed). Prereq §0 of the MIDI-IN
  redesign ("on-strip LATCH does nothing"). ROOT CAUSE: `Router.process` gated BOTH emission loops on the LIVE pool
  — `if pool.count > 0` (hold loop ~767) and `guard pool.count > 0 else { return }` (tick/arp loop ~1096) — both
  BEFORE `effectivePool(for:live:)` runs. So releasing the keys emptied the live pool, skipped the whole cell loop,
  and the FROZEN latch pool never sounded — the one case the latch exists for. FIX: both gates now read
  `pool.count > 0 || latchMask != 0` (armed → subscribers emit from the frozen pool; non-subscribers read the empty
  live pool → nothing, so safe). Regression test `testLatchedReceiverSustainsFrozenChordWhenLiveEmpty` (RouterTests).
  My first ferry diagnosis ("mechanism intact, tested stopped") was WRONG; a repro test pinned the real gate bug.**
- **▶ COG SIMPLIFICATION (2026-08-03, on `main`; 393 green, iOS builds; DEVICE pass owed). Spec:
  `Docs/AcceptanceCriteria/AcceptanceCriteria-cog-simplification.md`. CABLES RETIRED from the UI — the plugin now
  always hears every input cable (union): `SnapshotBuilder` forces `inputCableMask`/`recvCable` to `0b1111`,
  ignoring any saved receiver `cable` filter (kept decode-only). Removed `cableToggles` + `AU.setReceiverCable`.
  The CogPage INPUT is now ONE LINE per receiver "lens" (hue·R# · IN dot · MPE dot · CH chip [OMNI default] · LATCH
  CHORD|ADD · MPE toggle) + a lens doc line. OUTPUT (emitter channels) + HEALTH kept — HEALTH justified against the
  admission law (the stuck-note/voice safety readout is a true global). Tests repurposed: cable filtering →
  always-accept-all (`testInputCablesAlwaysAcceptAllAfterRetirement`, `testCabledReceiverStillHearsAllCablesAfterRetirement`).
  SEAL fix (`b4d05cf`): `sealHash` now hashes the RESOLVED chain (template/A-face cells were all one shape).**
- **▶ THE LADDER — exclusive-columns MODE + factory preset (2026-08-03, on `main`; 391 green, iOS builds; DEVICE
  pass owed). Spec: `Docs/AcceptanceCriteria/AcceptanceCriteria-ladder.md`. Built in 4 increments (`c012d55` =
  engine core; then AU+UI; then preset). PART 1 — MODE: while on, at most one cell "speaks" per column. Model:
  `SceneState.activeRow: [Int?]?` (per-column rung, append-only) + `ladderActiveRow(col)` (committed rung if it
  points at an occupied cell, else the TOPMOST occupied = gentle default) + `PluginState.ladderMode: Bool?`
  (document-level, mirrors masterMute). Resolved ENTIRELY in the builder → `SnapCell.dormant`; the two Router
  emit-guards (emitColumnHolds + tick loop) skip `cell.dormant` like `muted`, so the render thread stays
  LADDER-unaware and the column-boundary ADOPTION law handles rung handovers unchanged. AU: uiLadderMode/
  setLadderMode, ladderActiveRow, setActiveRow (a PERFORMANCE commit — `editScene(record:false)`, not undoable),
  uiEffColumn. UI: a LADDER toggle in the verbs panel (teal-green); a perform tap TRADES the trigger/mute for a
  rung ARM (`armLadderRung`) — playing → arm + BLINK, committed at the column's NEXT ENTRY via `onChange(of:
  d.effColumn)`; stopped → switch now. Dormant rungs dim (0.28), armed rungs blink; un-committed arms drop on
  stop. PART 2 — PRESET `PluginState.makeLadder()` ("THE LADDER" in the factory browser): full 8×8, each ROW one
  machine (R1 STILL pass/legato → R8 STORM harm+arp+chance), stamped as 8 twins per column; 3 scenes = intensity
  curves via `activeRow` over the SAME grid; colours light→dark; single emitter A; HARM = +12 octave only; LADDER
  ships ON. Tests: `testLadderModeMakesColumnExclusive` (engine) + `testLadderPresetIsEightMachineLadder` (preset
  structure + Codable round-trip of activeRow/ladderMode). KNOWN FOLLOW-UPS: the ON-HOLD trigger trade (only TAP
  traded so far); a tighter column-entry commit than the 4 Hz poll if fast step rates need it; the preset's exact
  colour ramp + scene curves are a tunable first pass.**
- **▶ LADDER UX refinements + preset family (2026-08-03, on `main`; 391 green, iOS builds; `5265d8a` = feedback
  round 1). Device feedback fixes: playhead + active-column glow gated on `!ladderDim` (dormant rungs no longer
  show them); tap a DORMANT rung → arm+BLINK only if the playhead is on that column now, else flip INSTANTLY; tap
  the ACTIVE rung → toggle its MUTE (column silent); ROW selectors ENABLE a whole row (one-directional, never
  disable); verbs panel is 2×2 (HOLD·MUTE / SELECT·LADDER). FLASH FIX: an armed rung commits when the playhead
  LEAVES its column (the arm is only ever for the just-current column), not on re-entry — so the blink stops at the
  end of the current column pass, not a full lap later. PRESET FAMILY: `makeLadder` refactored to a shared
  `ladderPreset(hues,machines,curves)` builder + slot helpers; added 4 MORE ladder presets — TIDE (up-down flow),
  FORGE (ratchet bursts), CHIME (octave-doubled bells), SPARK (chance-thinned generative) — all registered in the
  factory browser. Test generalised to `testLadderPresetsAreEightMachineLadders` (all 5 validate). Colour ramps +
  scene curves are tunable first passes.**
- **▶ CRASH HARDENING — bounds-safe cell access (2026-08-03, on `main`; 389 green, iOS builds). User hit a crash
  changing the colour of a (multi-cell) selection; no exception captured. Root cause not confirmed, but the whole
  colour-edit path + several UI reads subscripted `scene.cells[col][row]` UNGUARDED on the upper bound — a trap if a
  UI selection outlives its cell (clear / scene switch) or a decoded scene is RAGGED (< 8×8; `editScopeTargets`
  already guards for this, confirming ragged grids are possible). FIX: added `SceneState.inBounds/cellAt/setCell`
  (bounds-safe read/write; nil/no-op out of range) and routed every unguarded site through them — `editCells` (the
  colour mutation), `editingCell`, `syncAnchor`, `recolorSelection`, the route-foci reads, the selection `onChange`,
  the mixed-selection check, the deselect-restore, plus hardened `swapCells` and `restoringCell` (were `< 8`, not
  `< cells.count`). Test `testBoundsSafeCellAccessNeverTraps` (ragged + out-of-range never trap). DEVICE retest owed
  — if it still crashes, we need the exception to locate a different site.**
- **▶ CHOP BUG FIX — the ALT (bottom) row on HOLD cells (2026-08-03, on `main`; 388 green, iOS builds). The 8×3
  chop grid (top=MAIN dest · middle=MUTE · bottom=ALT dest) routed correctly for TICK cells (arp/ratchet/strum,
  via `emitChop`→`chopMask`) but was ENTIRELY IGNORED for HOLD cells (identity/passthrough/chance/harmonize) —
  `emitColumnHolds` emitted the raw `bm`, never calling `chopMask`, so the ALT/MAIN/MUTE rows did nothing on a
  hold (the default passthrough cell). FIX: `emitColumnHolds` now routes the held note by its ONSET slice
  (`hbm = chopMask(cell, m: colStart, S:S, base: bm)` — a hold is one articulation at colStart=slice 0; MAIN→own
  buses, ALT→altDest, MUTE→silent). `chopMask` returns `bm` unchanged when the cell has no chop → zero behaviour
  change for ordinary holds; all legato/drone tests still green. Tests: `testChopAltRoutesToAltDestination` (tick),
  `testChopAppliesToHoldCell` (hold). NOTE/LIMITATION: for a SUSTAINED hold this routes the WHOLE note by slice 0
  (setting the whole bottom row → routes to alt; a subset not including slice 0 won't) — true per-slice CHOPPING of
  a sustain (re-striking into 8 rerouted segments) is a larger follow-up needing device-verified future-note
  scheduling. The dead PREVIEW path (`previewChordHold`) is unchanged. Fixed the stale "routing engine is a
  separate increment" / "8×2 grid" UI comments.**
- **▶ DEAD-CODE SWEEP (2026-08-03, on `main`; 386 green, iOS builds; net −346 lines). A vetted survey found these
  orphans (all confirmed zero-caller): the whole `PaletteView` (retired colour-brush palette, GridUI) + `RoutePanelView`
  (FlowView) Views; the disconnected EDIT-page TRIGGERS accordion cluster (`triggersInline`/`tapEditor`/`holdEditor`/
  `arriveEditor`/`trigLabel`/`editOn`/`trigMenu`/`trigSeg`/`trigStepper` — the ON model stays on `Colour`, its inline UI
  returns with TOUCH; `facetRow` KEPT, shared with `inputShiftRow`); the dead EDIT helpers `editName`/`inputSourceChip`/
  `setEditSource`; the dead AU read helpers `uiCellChain`/`twinCount`/`uiColourCensus`; and the unused `landscape`
  var (fixed the sole compiler warning). Refreshed the stale `ORBIT comet` → `SEAL comet` comments (14 sites).
  STILL DEFERRED (noted, own passes): the woven verb machinery (heldVerb-gated: onVerbEngaged/doVerb/RoutingVizOverlay/
  etc. — parked until SELECT is defined); the inert preview plumbing (`Kernel.setPreview`/`AU.setPreview`/
  `setPreviewOverlay`/`previewInputRow` — dead but threads the render path); `setColourType`/`setColourMorph` (dead but
  morph param addresses 200+i/300 are reserved). `colourCensus` (Derivations) is now prod-dead but kept (still tested,
  documents the D3 census). Already-removed per an earlier note: the SceneState chaining ops + routingEdges cell→cell edge.**
- **▶ TEST SWEEP + sealFit REFACTOR (2026-08-03, on `main`; 386 green, iOS builds). REFACTOR: extracted the seal's
  pure bbox-fit math out of the SwiftUI `GridUI.sealLayout` into `Derivations.sealFit` (`SealFit{fractions,rangeX,
  rangeY}`, Foundation-only) — keeps pure logic testable (project rule) with zero behaviour change; `sealLayout`
  now just maps fractions → the rect. TESTS added (a coverage-survey found these gaps): `sealFit` fills-the-length
  + centres-straight-runs (Derivations); the seal COIL positive branch (was only negative-tested); and three Router
  comet-feed edge cases — the SILENT CLAIM-GHOST must NOT light the sounding comet (the load-bearing `!v.silent`
  guard in `snapshotCellSounding`, previously unguarded), a MUTED occupied cell records no strike/no sounding bit,
  and a FAN-OUT cell reports exactly one bit + one strike (per-cell not per-voice keying). Added a `runDirect`
  RouterTests helper (direct router so `drainCellStrikes`/`snapshotCellSounding` are inspectable).**
- **▶ HEADER/SCENES BAR SHARED across perform + edit + PERFORM/EDIT toggle (2026-08-02, `35f22b9`; 380 green, iOS
  builds). `ArrangementBar` now tops BOTH pages (one consistent header + 16-scene strip); a prominent two-segment
  PERFORM/EDIT toggle (cyan/orchid, `isEditMode`/`onSetEditMode`) drives `editArmed`. Removed the EDIT verb from the
  perform verbs cluster (HOLD·MUTE·SELECT remain) + the edit page's DONE close button + its own header (GRID SETUP/
  undo-redo) + the orphaned `editVerbButton`/`headerIcon`. NOTE: a scene switch still auto-closes EDIT (§cell-edit
  A6, per-scene session) — kept; revisit if EDIT should persist across scene switches. DEVICE pass owed (header
  crowding in portrait).**
- **▶ THE SEAL — the derived cell face, SUPERSEDES THE ORBIT (2026-08-02, on `main` PENDING COMMIT; 379 green,
  iOS builds; DEVICE pass owed). Spec of record: `Docs/AcceptanceCriteria/AcceptanceCriteria-seal-face.md`
  (renamed from -orbit-face). Design ferry `INSTRUCTIONS-implement-the-seal.md` RETIRED the lissajous ORBIT
  (ratio table gone) for THE SEAL — a maze/route glyph on a 3×3 lattice, generated from the SAME behavioural-
  config hash (§A unchanged; `orbitHash`→`sealHash`). Grammar: hue (whose) · THE SEAL (which) · bus dots (where).
  Applied in ALL THREE places (user: "same icon in all three places"): the perform grid cell, the edit-page
  mini-grid cell (both via `GridView.cellView`), and the edit-page IDENTITY plate — one `sealGeometry(sealHash)`,
  so twins visibly share it. PURE CORE (`Derivations.swift`): `SealRNG` (mulberry32 seeded by the hash) +
  `sealGeometry(hash) -> SealGeometry{nodes,arcAtNode,coilNode}` per the mockup prose §2 (START on lattice → ≤4
  orthogonal moves, no backtrack/OOB, ≤8 tries → corner-arc bits from one hash word → ≤1 coil iff hash%4==0).
  RENDERER (`GridUI.drawSeal`/`sealNodePoints`): the WIRE (quarter-arc/mitre corners) + optional COIL + filled
  TERMINALS (start dot + arrowhead). Cell BADGE (§C): a LEFT-set engraved rounded-square plate (14% black + 10%
  hairline), seal ink `rgba(12,12,16,0.8)` 2.4pt, NO lattice; bus dots moved to bottom-RIGHT. EDIT plate (§E1):
  large, ink `rgba(236,234,223,0.9)` 3.4pt, lattice VISIBLE, ~250ms opacity crossfade on hash change. COMET
  (`sealComet`, §D): the existing per-cell strike feed drives a spark START→ARROW, trail ∝ vel, strike glow
  ~450ms, dies ~1.1s. Tests: 6 seal (hash stable/config-sensitive/excludes colour+mute/bus-order-invariant;
  geometry deterministic+twin-shared, obeys lattice grammar, coil only when hash%4==0). ⚠ The mockup HTML
  `seal-glyph-mockup.html` was NOT shipped in the inbox — ported from the prose §2 with a faithful mulberry32;
  exact PRNG/proportions may differ from the reference (grammar is fixed) — flagged in the ferry reply. DEFERRED
  (§5/§E polish): coil-node spark slowdown; the 64-point arc-length re-route glide; the edit-page audition comet.
  Prior ORBIT figure/comet history (retired) is in the bullet below + git (`31b893f`…`a7c30b2`).**
- **▶ THE ORBIT — RETIRED (superseded by THE SEAL above). The derived cell face (2026-08-02; 379 green, iOS builds).
  Historical. Was: a lissajous figure DERIVED from the cell's behavioural config. Plan:
  `~/.claude/plans/resilient-imagining-truffle.md`. Replaces the type emblem + digest text on the cell face with
  a lissajous figure DERIVED from the cell's BEHAVIOURAL config (twin-equality fields MINUS colourID) — so config-
  twins VISIBLY share one figure ("the orbit cannot be dressed"). Grammar: hue block (whose) · orbit (which) ·
  bus dots (where). PHASE 1 — THE FIGURE (`31b893f`/`a8ca5ac`/`952e71a`): pure derivation in `Derivations.swift`
  (`orbitHash` = FNV-1a over a `.sortedKeys` JSON of processors/inputReceiver/inputRow/sorted-buses/chordSplit/
  velWindow/chop; `orbitFigure` draws (a,b)/phi/squish from the hash via a frozen low-order 5-ratio table;
  `orbitPoints` full t∈[0,2π] + `orbitInitialPoints` reduced half-period). TWO-SCALE signature: CELLS draw a
  reduced open "initial" stroke (`OrbitInitialShape`, Catmull-Rom smoothed) since a full lissajous knots at ~30px;
  the EDIT-page identity box draws the full `OrbitShape` with a ~400ms `animatableData` GLIDE on config change.
  Ink `orbitInk` (near-black 0.38α, ~2.4pt round). PHASE 2 — THE COMET (`a7c30b2`): body A FROZEN (harness/
  WaveformShape/orbitWaveform scaffolding removed) + a velocity-scaled comet runs the orbit while the cell fires.
  NEW per-cell strike feed (the engine had only per-bus/per-colour marks): render-thread `Router.cellStrike[64]`
  keyed by grid index, `currentCellIndex` tracked in emitColumnHolds + the tick loop, peak vel recorded in
  emitArtic → `drainCellStrikes` (read-and-clear, mirrors drainMeters) → `Kernel.drainCellStrikes` →
  `AU.pollCellStrikes` → VC 4Hz poll stamps `cellHitAt`/`cellHitVel[64]` → GridView → `orbitComet` (TimelineView+
  Canvas: ping-pong head along the stroke, trail ∝ velocity, strike glow decaying ~450ms, dies ~1.1s after the
  last strike, paused when idle/backgrounded). Tests: 6 Derivations (hash stable/config-sensitive/excludes colour+
  name+mute+position/bus-order-invariant, figure ratios, reduced stroke = half-period unit space) +
  `RouterTests.testCellStrikeFeedRecordsFiringCell`. DEFERRED: edit-page comet during the AUDITION loop (spec §E3
  — only the grid comet + edit-page glide are built); update spec §B6 (body A frozen, harness removed) — done.**
- **▶ REFACTORS (2026-08-02, on `main`; 372 green, iOS builds). (1) DEAD-CODE SWEEP `c2ceab8` — removed the
  mode-row wave's superseded designs (AU twin/solo path, stamp mode, hue popover, MIDI-IN splits UI, old
  cellEditPage, ChopSlot). (2) PERFORM-REWORK SWEEP `8d1d59a` — colour-desk name-editor/trash/birth-picker +
  pickPalette/repaintHoldToBrush/placeholderBox/verbButton/verbHint. DEFERRED: the woven verb machinery
  (heldVerb/activeVerb/doVerb/place/clipboard/strokes) — entangled with tapCell/gridBlock/rowRail + the
  selection/SELECT bits; own pass once SELECT is defined. (3) EDIT-PAGE FILE SPLIT `3aa2cd6` — the whole edit
  page moved to `AUExtension/EditPage.swift` (`extension DiagView`); AudioUnitViewController.swift 1882 → 1239
  lines. Widened DiagView `private` → internal (extension can't see file-scoped private); @State stays in the
  struct. Pure relocation, zero behaviour change.**
- **▶ EDIT-PAGE — THE MODE ROW WAVE — MERGED TO `main` + DEVICE-ACCEPTED (2026-08-02, `8cbdd84`; 368 unit
  green, iOS builds). User: "very happy with this." Rounds 1–6 + the chop rework are all on `main`; work
  continues from `main`. SUPERSEDES W1's auto-twin/DETACH (INSTRUCTIONS-edit-page-mode-row). The EDIT
  page grows a big MODE ROW below the grid — `EDIT · MUTE · CLEAR ‖ APPLY · CANCEL` — and one TRANSACTIONAL
  session: edits/births/clears preview LIVE, APPLY commits them as ONE undo step, CANCEL reverts (AU
  `beginEditSession`/`applyEditSession`/`cancelEditSession` + session-aware `editScene`; `sessionBaseline`
  defers per-edit undo). **EDIT** = a MANUAL select-set (`editSel`, anchor = first, 2nd tap toggles others,
  LONG-PRESS drops the anchor — repurposes the parked spike-grid audition hold); edits write through to the
  whole set via new AU `editCells`/`withChainCells`/`editSlotCells`/`addSlotCells(type:)`; twins now only PULSE
  to advertise (dashed pulsing ring), never auto-edit. **Newborn** empty-tap births a PASSTHROUGH — R1 → Emitter
  A, an EXPLICIT empty chain (`processors == []`); the builder renders empty as a single true-bypass identity
  hold-tail (born audible), and CHAIN shows a "+ ADD PROCESSOR" invitation + emblem type selector, never a PASS
  slot. **MUTE** = immediate mute toggle (outside the session). **CLEAR** = transactional removal marks
  (`clearMarks`/GridView `removeMarks` dashed-red ✕; APPLY deletes via `deleteCellSever`, CANCEL/retap reinstate).
  **Column-loop row** above the grid → `au.setLaneMask` (same lap path as the perform column-hold). REMOVED the
  superseded APPLY TO… foot menu + `applyCellToScope` + `EditScope.row/.column` + DETACH/`soloEdit` + foot
  DELETE (`footUtilities`/`deleteEditedCell`/`utilBtn`/`scopeCount`) + their test. Test: empty-chain =
  born-audible passthrough (`testEmptyChainIsBornAudiblePassthrough`). **DEVICE ROUND 1 FIXES (2026-08-02):**
  (1) CRASH editing arp PATTERN/RATE — `withChainCells` read `document` (via `materializedChain`) INSIDE the
  `editScene` `&document…` mutation = exclusive-access trap; now materialises each chain BEFORE `editScene`.
  (2) re-tapping a NEWBORN now deletes it (+ its controls) via `bornThisSession`. (3) a newborn defaults to a
  NEW colour (first unused palette hue), not the brush. (4) the two column rows collapsed to ONE — the grid's
  own column keys are now tappable (`GridView.onColumnKey`) and drive the loop (fixes "looping not working").
  (5) twin PULSE made an unmistakable cyan dashed ring (was a subtle white one). **DEVICE ROUND 2 (2026-08-02):**
  enum slot params (PATTERN/RATE/OCT/PHASE/DIR/REPEATS) are ALWAYS-VISIBLE radio rows (ProcessorBox `seg`
  rewritten, no dropdown); slot boxes are full-inspector-width + content-sized (no clip, `FixedHeightIf`); form
  labels/controls enlarged throughout (radio 15, steppers/toggles 42pt tall, headers 17); twin PULSE is now a
  WHOLE-CELL cyan wash; SELECTION grouping — a true newborn is created ONLY when nothing is selected, and while a
  group is open a tapped cell JOINS it (an empty one is born as a CLONE of the anchor so the group edits together).
  **DEVICE ROUND 3 (2026-08-02):** (1) SERIAL-EXECUTION FIX — the chain's tick DRIVER is now the LAST non-bypassed
  arp/ratchet/strum (`Router.chainDriverIndex`), not necessarily the tail; slots before it compose as its source,
  slots AFTER it FOLD onto each emitted note (`emitDriverNote`/`emitChop`). So `[arp → passgate]` KEEPS
  arpeggiating (the arp drives, the passgate gates each note) instead of collapsing to one held note; `emit*Row`
  take `chainDriver:` (was `chainTail:`). Tests: arp→open-gate arpeggiates, arp→closed-gate silent, arp→harmonize
  adds voices (367 green). (2) ADD-PROCESSOR shows the big emblem TYPE SELECTOR (`processorTypeRow`, shared with
  the empty invitation) — no default passgate. (3) enum slot params are always-visible radio rows; slots
  full-width. (4) IDENTITY shows a count-only summary (no name/type/position) + the chosen-colour box beside an
  always-visible equal-size 16-swatch picker. **DEVICE ROUND 4 (2026-08-02):** modes are now ADD/EDIT · MOVE ·
  MUTE · CLEAR; **APPLY/CANCEL + the transactional session apply ONLY to ADD/EDIT** — MOVE/MUTE/CLEAR are
  IMMEDIATE + undo/redo (fixes the intermittent mute: the session no longer wraps it). MUTE is an immediate
  undoable toggle (dims 0.28, persists across modes); the confusing "no-emitter" red-dashed border is suppressed
  on the setup grid (`GridView.flagNoDest:false`). CLEAR removes a cell immediately and reinstates it if the now-
  empty slot is re-tapped (`clearedStash`, dropped on leaving CLEAR — undo/redo covers it after). MOVE (new,
  between ADD/EDIT and MUTE): a plain drag relocates a cell, dropping over a populated cell SWAPS
  (`GridView.moveMode` + `SceneState.swapCells`). UNDO/REDO buttons added to the header. The MIDI-IN splits (chord
  split · vel window) are removed from the page (to return as a chain processor). The passgate PASSES row shows a
  PLAYHEAD ring on the live pass (`ProcessorBox.passHead` ← `d.pass & 3`). IDENTITY colour picker is now 4×4,
  swatch = a grid cell's size, with the selection count to its right. **DEVICE ROUND 5 (2026-08-02):** passgate
  fix — a downstream passgate now gates on `diag.pass` (the authoritative lap counter) not a beat-derived recompute,
  so `[arp → passgate]` opens/closes on the lap the user sees (`emitDriverNote` takes `pass:`); test
  `testArpThenPassgateGatesPassZero` (368 green). UI: selected-cell ring BREATHES (`GridView.animateSelection`);
  IDENTITY has a chosen-colour box (= the picker's footprint) + a 50%-smaller 4×4 grid + count + "N IDENTICAL
  CELLS AVAILABLE"; mode hints ("Select 1 cell then duplicates" / "Drag and drop" / "Choose cells to mute|clear");
  TO section renamed "TO · MIDI OUT"; the MIDI-IN receiver radio + chain controls now use the emitter BLUE
  (`mainDestHue`, via `ProcessorBox.accentOverride`); a MUTE/CLEAR long-press now does the same as a short press
  (`longPressFired` once-guard). Spec of record: §C of
  `Docs/AcceptanceCriteria/AcceptanceCriteria-cell-machine.md` (rewritten). The audition head-fix from `ea4206a`
  stays (parked); its APPLY TO… half is reverted by this wave. NOT on main. JUDGMENT CALLS / owed: MIXED-set
  markers are minimal; the anchor isn't yet visually distinct from other selected cells; a full multi-slot
  audition preview stays owed (audition parked until TRIGGERS).**
- **▶ EDIT-PAGE WAVE W1 — TWIN EDITING (2026-08-02, DEVICE-VERIFIED + on `main`; 363 green). SUPERSEDES the
  stage-3 scope toggle: `EditScope.twins` (config-equal cells, perform state ignored); every chain/input/output/
  chop edit applies to the pointed cell + its DERIVED twins in one undoable step (AU `withChain`/`editTwins` route
  through `editScopeTargets(.twins)`); DETACH (`soloEdit`) targets only the pointed cell → it diverges + leaves the
  set; header "EDITING N IDENTICAL CELLS"; grid shows twins (dashed) + dims non-twins. Removed the ChainScope
  toggle + template-EDIT AU methods (KEEP `Colour.templateChain` as the render fallback + birth default; KEEP
  APPLY TO… utilities).**
- **▶ EDIT-PAGE WAVE W2+W3+W4 (2026-08-02, DEVICE-VERIFIED + on `main`; iOS builds + 363 green). Spec of
  record for the model + this page: `Docs/AcceptanceCriteria/AcceptanceCriteria-cell-machine.md`. W2: sections
  read IDENTITY · FROM·MIDI-IN · CHAIN · TO·SYNTHS; INPUT is a
  RECEIVER RADIO (R1–R4 chips in the identity hues `receiverHues` + NONE); OUTPUT left-aligned with per-bus
  channel tags; DELETE demoted to a compact foot button; the IDENTITY swatch is tappable → a 16-hue popover that
  re-tints the cell + its twins (`setCellColour` via `editTwins`). W3: killed the empty-cell chevron watermark
  (empty = bare faint rect); empty-state = a centred invitation line; tapping an EMPTY cell in EDIT now CREATES a
  cell (brush default) + points it (grid = position picker); removed the "(routing engine pending)" dev
  annotation. W4: enum params are VALUE CHIPS now (the `ProcessorBox.seg` helper reimplemented as a tap-Menu
  chip — PATTERN/RATE/OCT/PHASE/REPEATS/DIR); GATE/sliders + PASSES toggles unchanged; sparse pass (headers up a
  step, ~2× section spacing, max content width 560, emitters left-aligned). JUDGMENT CALLS / owed: the twin-count
  header stays in the CHAIN section (W1 placement, not moved to IDENTITY); the column-key chevrons kept (they're
  the functional playhead, not empty-cell noise); no separate TRIGGERS section reinstated; chip drag-to-scrub not
  added (tap-picker only); the DIN glyph is SF `cable.connector` (approximation).**
- **▶ CELL MACHINE — SHIPPED + DEVICE-VERIFIED (2026-08-02, on `main` via feat/EditPageSpike). The proposal is
  built end-to-end and confirmed on device. READ THIS, not the per-stage "NOT on main"/"DEVICE owed" flags in the
  bullets below — those are STALE. On `main`: per-cell processor chains · full serial execution (all six types,
  N slots deep, pure per-beat derivation) · shared TEMPLATE + explicit edit SCOPE (colour = template+tag) · the
  cell LIBRARY (save/stamp "machine minus routing" + FACTORY starter cells) · default grid tap = mute · the EDIT
  page's RECEIVER source picker. Deferred-features roadmap (`~/.claude/plans/resilient-imagining-truffle.md`)
  executed: **A** A/B MORPH REMOVED (render + UI gone; Codable fields + param addresses 200+i/300 reserved for
  decode/automation) · **B** GRID-CHAINING RETIRED (`Cell.inputRow` inert decode-only; parentRow/parentSoundingNote/
  chordHoldRelayFilter/emitMirrorRow deleted; receiver + emitter routing kept) · **D** factory cells · **E** ferry
  acknowledged + this note. **DEAD-CODE SWEEP done (2026-08-02):** removed the unused `SceneState` chaining ops
  (isChainHead/routeInSourcesAbove/routeOutTargetsBelow/wouldCycle/routeInRow/graftHead(s)Below) + the deleteCell
  base/deleteCellHealing (deleteCellSever → plain delete); the retired `processorPanels` desk + its brush morph/
  clipboard helpers (setBrushMorph/setBrushType/brushGlides/copyProc/pasteProc/procClipboard/ProcClip); the
  routing-viz cell→cell edge in `routingEdges` + the `RoutingVizOverlay` isChain branch; and ~10 dead tests.
  **DEFERRED follow-ups (not done):** (C) audition/preview still reads the Colour A face, not the resolved chain
  (a preview-fidelity gap, low priority); a few CONSERVATIVELY-LEFT inert items (the unreachable ProcessorBox
  `.b`-face branches — fiddly internal refactor · the FlowView `srcRow` chain-hop half — tangled family logic ·
  the inert Kernel/AU preview-`inputRow` plumbing · factory/T-session inert `inputRow` data); the strum-mid-chain
  rhythm approximation (accepted as inherent); a full AcceptanceCriteria/spec write-up of the new model.**
- **▶ CELL MACHINE — per-cell processor CHAIN, stage 1 (branch `feat/EditPageSpike`, 2026-08-01; off-device:
  iOS builds + 374 unit tests green; DEVICE pass owed). Alternative setup model (`_dear_claude_code/PROPOSAL-
  cell-machine.md`): a cell OWNS a serial chain of ≤8 processor slots (type + params + per-slot bypass), shown
  as a vertical stack of 50%-width boxes in the EDIT spike page. Stage-1 scope (user rulings): model + stacked
  UI + engine renders the HEAD slot only (serial run of slots 2…8 = next stage); A/B MORPH DROPPED on this
  branch (chains seed from the Colour's A face; morph layer dormant); grid-chaining left working. What landed:
  `ProcessorSlot` + `Cell.processors: [ProcessorSlot]?` (Models, additive Optional, no migration); `SnapCell.proc`
  resolved head + builder fallback `cell.processors ?? [colour A face]` (SnapshotBuilder); Router reads the
  per-cell head via a `treat` colour (a==b==head, morph neutralised) at every dispatch incl. parentSoundingNote/
  chordHoldRelayFilter; cell-scoped undoable slot setters (setSlotType/editSlot/toggleSlotBypass/add/removeSlot,
  MidiSparkAudioUnit); `ProcessorBox.slotMode` (bypass chip, no transpose/morph) + `chainStack` in editSpikePage.
  Tests: 1-slot chain == Colour A face, bypassed head = passthrough, chain JSON round-trip + old-doc nil; 4 morph
  tests updated to the head-only reality. KNOWN stage-1 gaps: audition previews the Colour not the head; the
  normal (non-spike) processor desk still edits the shared Colour. Plan: `~/.claude/plans/resilient-imagining-
  truffle.md`. NOT on main.**
  - **STAGE 2 — SERIAL EXECUTION (tick-tail slice, 2026-08-01; off-device: iOS builds + 379 unit tests green).**
    The chain now RUNS in series for the covered case: a 2-slot chain whose TAIL is an ARP or RATCHET runs the
    HEAD stage's output SET, DERIVED per tick (window-independent) → pool-correct (harmonize→arp arps ALL voices;
    harmonize→ratchet re-strikes all voices; gate→arp/ratchet; chance→arp; arp→arp). `SnapCell` carries the full resolved chain (`procs:[SnapParams]` + `slotBypass`); a new
    `fillChainInput` computes the head's set at beat m into a fixed `chainScratch` NotePool (identity/gate pass the
    shaped source, chance drops, harmonize expands, arp head = its note at m); `emitArpRow` gains a `chainHead`
    input branch; the dispatch routes covered chains to the tail (grid-fed cells defer to grid-chaining) and
    `emitColumnHolds` skips them so the head doesn't double. Per-slot BYPASS = true-bypass. Tests: gate→arp,
    harmonize→arp (all voices), harmonize→ratchet, gate→ratchet, bypassed-head=source-only. **N-SLOT (2026-08-01,
    381 green): generalised to any-length chains ending in arp/ratchet — `composeChainSet` folds every upstream
    stage into the scratch via a ping-pong of two working pools (identity/gate/ratchet/strum pass, closed gate
    empties, chance drops, harmonize expands, an ARP mid-chain collapses to its one note at m). Tests: 3-slot
    gate→harmonize→arp, closed-gate-silences-tail. **HOLD TAILS (2026-08-01, 383 green): chains ending in a HOLD
    stage (gate/chance/harmonize, or a bypassed tail) now emit at column boundaries — `emitColumnHolds` holds the
    TAIL slot's transform of `composeChainSet(upto: tail-1)` (window-independent, derived at colStart). Routing:
    tick-tail (arp/ratchet)→tick loop; hold-tail→emitColumnHolds; non-bypassed STRUM tail→head-only fallback.
    Tests: gate→harmonize holds the harmonized chord, closed-gate-tail silent. Since the whole pipeline is now a
    pure per-m derivation (no buffers), the earlier "cross-window sustained intermediate" concern is MOOT.
    **STRUM TAILS (2026-08-01, 384 green): the last gap — a strum tail staggers the composed upstream set (derived
    once at colStart, read via chainScratch). So SERIAL EXECUTION IS NOW COMPLETE for all six types in any slot
    position, N slots deep: {arp·ratchet·strum} tick tails, {gate·chance·harmonize·bypassed} hold tails, any mix
    upstream. Test: harmonize→strum staggers all voices. UI caption = "Chain runs in series." DEFERRED (minor,
    arguably inherent): a mid-chain ratchet/strum passes the note SET through without imprinting its own rhythm
    (a downstream stage samples the set at m, not the rhythm). Device ear-check owed for the whole chain.** NOT on main.**
  - **STAGE 3 — shared TEMPLATE chain + explicit edit SCOPE (2026-08-02, 388 green; off-device). Answers "if I
    change scene 1's harmonize, does scene 3 change?": now user-chosen. `Colour.templateChain: [ProcessorSlot]?`
    (additive Optional) = the colour's shared default chain; builder resolves 3 tiers `cell.processors ??
    colour.templateChain ?? [type+paramsA]` (per-cell OVERRIDE → colour TEMPLATE → legacy A face). The CHAIN
    editor gains a scope segment: THIS CELL (writes `cell.processors`, per-scene) | ALL <colour> (writes
    `templateChain`, every FOLLOWING cell in every scene) + a FOLLOWS/OVERRIDES badge + ↺ FOLLOW (clears the
    override). AU: template-path slot setters (via `editColour`, undoable) + `followTemplate`/`cellOverrides`/
    `uiColourTemplate`. The old shared-Colour processor desk (`processorPanels` in identityColumn/colourFlowBand)
    is RETIRED — all processor editing goes through EDIT. Tests: 3-tier resolution, template-sounds-for-following-
    cell, override-diverges, templateChain round-trip. DEFERRED: cell library · per-slot override granularity.**
  - **▲ Stages 1–3 above were MERGED to `main` + pushed (`4c3288a`, 2026-08-02) with the mute commit.**
  - **STAGE 4 — the CELL LIBRARY (2026-08-02, 390 green; off-device; branch `feat/EditPageSpike`). Save a
    configured cell under a name + stamp it into other cells/sessions. Ruling: a saved cell is "MACHINE MINUS
    ROUTING" — chain (materialised) + colour + source-shaping (split/vel/chop) travel; input receiver/row +
    output emitters are wired fresh on stamp. `CellLibraryStore` (in PresetStore.swift; `Application Support/
    Cells`, `.8x8cell`, mirrors PresetStore) stores one Codable `Cell` per file. `Cell.libraryStripped(
    materialisedChain:)` shapes it. AU: `saveCellToLibrary`/`list`/`load`/`delete`/`stampLibraryCell`. Also FIXED
    `AU.materializedChain` to the 3-tier resolution (was skipping the template tier → detach/save of a following
    cell lost the template). UI: `CellBrowser` (in PresetBrowser.swift) opened by a LIBRARY button in the EDIT
    header; STAMP arms a `pendingLibraryCell` mode (banner + tap-to-place, routed at the top of `tapCell`). Tests:
    store round-trip, libraryStripped keeps-machine-drops-routing. DEFERRED: factory cells · browser thumbnails ·
    App-Group container.** NOT yet on main.**
  - **DEVICE-VERIFIED (2026-08-02): the whole cell machine (stages 1–4) + mute + receiver-picker fix accepted on
    device. Stages 1–4 merged to `main` (`d60689b`).**
  - **ROADMAP DEFERRED-FEATURES (branch `feat/EditPageSpike`, NOT on main). A: A/B MORPH REMOVED (`715861c`) —
    effective* read the one A bag; arriveMorph/arriveAlt gone. B: GRID-CHAINING RETIRED + morph dead-code cleaned
    (2026-08-02, 368 green, iOS builds). `Cell.inputRow` is now inert decode-only; `resolvedParent` always −1;
    deleted `parentRow`/`parentSoundingNote`/`chordHoldRelayFilter`/`emitMirrorRow` + all `fed`/`parent` branches
    (incl. the preview path); `SnapColour.b/.tier/.morph`, the `treat.b/.tier`, `MorphTier`/`morphTier`/
    `effectiveT`/`effectiveTWithArrive` all deleted. UI: the "FROM ROW" source option + the SRC/DEST route-
    candidate glow/wiring removed. Receiver + emitter routing, EMITTER-ROTATE, ALT voice-identity/turn-taking,
    and the routing viz for receiver/emitter edges all KEPT. Removed the ~7 grid-chaining + morph-tier tests.
    KEPT reserved: Codable morph fields + param addresses 200+i/300. DEFERRED cleanup (harmless dead code, no
    effect since inputRow is always nil now): the unused `SceneState` chaining ops, the `routingEdges` cell→cell
    edge + `RoutingVizOverlay` `isChain` branch + `FlowView` `srcRow` half, SceneFactory/TestSessions still set
    inert `inputRow`, and the unreachable ProcessorBox B-face/MORPH fader.**
  - **ROADMAP-A: A/B MORPH removed — FUNCTIONAL (2026-08-02, 376 green, iOS builds; branch `feat/EditPageSpike`).
    `effective*` now read the single (A) param bag (no A→B interpolation); `arriveMorph`/`arriveAlt` (MORPH-DRIFT
    + ALT-ALTERNATE, both only steered the gone face) deleted; `effectiveTWithArrive` → 0-shim. Removed tests:
    EffectiveParamsTests (emptied), 5 SnapshotBuilder procB tests, 2 Derivations arrive tests. KEPT (invariant 5 /
    old-doc decode): Colour.morph/paramsB/typeB/… + morph param addresses 200+i/300 + arriveBusMask + ALT/voice
    plumbing. DEFERRED to fold with ROADMAP-B (same engine paths): deleting the inert `SnapColour.b/.tier/.morph`
    fields + the `treat` plumbing + `morphTier`/`MorphTier` + the dead UI B-face/MORPH fader (already unreachable
    via the retired `processorPanels`).** NOT yet on main.**
- **▶ DEFAULT GRID TAP = MUTE-TOGGLE — LANDED (2026-08-01, off-device: iOS builds + full unit suite green;
  DEVICE pass owed). User ruling: a plain perform tap on an occupied cell toggles a PERSISTED mute (dimmed,
  not hidden); muted = no emitter output + children read raw MIDI-IN (arp bypassed downstream). Reuses the
  existing `Cell.muted` engine (already did no-output + `parentRow` muted→MIDI-IN reroute; tests 114/1096).
  Changes: (1) `triggerTap` (AudioUnitViewController) — `on.tap == .none` now toggles `Cell.muted` via
  `au.editScene` (undoable) instead of falling through to alt-flip; `.alt/.mute/.solo` triggers unchanged
  (COEXIST — mute only when no ON-TAP trigger set). (2) `cellView` (GridUI) — a muted cell renders DIMMED
  (0.28), no longer nil'd to empty. New test `testMutingMidPlaybackSilencesCellWithoutStuckNotes` (no hung
  note when muting mid-play). Plan: `~/.claude/plans/resilient-imagining-truffle.md`.**
- **▶ /btw AUTHORING UX + ACCEPTANCE-CRITERIA WAVE — LANDED on main (2026-07-29 session; off-device verified:
  iOS builds + 343 unit tests green; DEVICE pass owed for every UI item). The spec of record for the verbs / grid /
  routing / strips is now `Docs/AcceptanceCriteria/verbs-behaviour.md`. What landed:**
  - **/btw ⑥ one-per-column, per hold** (`aaff54c`) — pure `placeHoldDecision` (Derivations), gated in `placeToggle`.
  - **/btw ④ retro-repaint + DESK RE-POINT hard rule** (`ef82935`) — a mid-PLACE brush switch recolours the whole
    hold + switches the desk; selecting a single Colour ALWAYS re-points the COLOUR+PROCESSOR desk (brush = pointer).
  - **SELECT empty-tap = no-op; DELETE = SEVER** (`86be8c0`) — a deleted cell's children are CUT to MIDI-IN (R1),
    NOT healed to its parent (`SceneState.deleteCellSever`).
  - **MIXED-SET law** (`7be6517`) — processor panels dim to "MIXED" for multi-Colour selections.
  - **STROKES** (`2a02cb4`) — drag = batch place/delete/select, one undo per swathe.
  - **Multi-cell routing (per-column) + SRC/DEST look** (`1d75170`, refined `b1d9fb3`) — every column with exactly
    one focus offers ALL cells above (SRC) / below (DEST); PLACE foci = all cells placed this hold, so a whole ROW
    invokes routing + the strips (which apply to all foci). Candidates PULSE (the cell BODY, time-driven) with
    prominent SRC/DEST labels and NO ring. Placed/selected cells ALWAYS draw WHITE (the amber focus ring was
    invisible on gold cells — removed).
  - **PLACE nearest-above nudge** (`10fc259`) — a fresh cell wires to the NEAREST occupied cell above (bridges gaps).
  - **STICKY ROUTING** (`4183a41`) — a fresh PLACE cell inherits the last-set-up cell's emitters + receiver.
  - **Verbs do NOT latch** (`1f3ef92`) — long-press latch was built (`88af24f`) then RULED OUT; verbs are spring-only.
  - **Refactor + tests** (`181bf7c`) — routing logic extracted to pure `Derivations` helpers (`routeFociByColumn`,
    `placedCellRouting`) + a `deleteCell(reparentChild:)` dedup; the multi-cell/sticky-routing logic is now unit-tested.
  - **ROUTING VIEW + VISUALISATION (2026-07-30)** — a chosen SRC/DEST candidate returns to standard (`6dd1d96`);
    a **routing overlay** spanning receivers→grid→emitters (`26e34cf`) with **MIDI comets** (`ae445ae`), then
    refined to connection dots + clip-over-uncrossed + lane-separated routes (`723b5f2`), then the redesign
    (`d6684e6`): candidates + strips read **IN / OUT** only, a candidate cell hides all content (just colour +
    pulse + label), PLACE banner "Choose one route in and multiple out", LARGE band dots, cell→cell drawn as a
    solid line + downward arrow (curved+comet reserved for receiver/emitter flow). Pure `Derivations.routingEdges`
    (+tests). Off-device only. Doc updated (`Docs/AcceptanceCriteria/verbs-behaviour.md`).
  - **CELLS & COLOUR DESK overhaul (2026-07-30)** — `Docs/AcceptanceCriteria/AcceptanceCriteria-cells-and-colour-
    desk.md` + plan `implementation-plan-cells-and-colour-desk.md`, built A→D: **emblems** prereq (`caec3fa`); **A1**
    cell face = emblem + digest + bus DOTS (`34f93a9`); **A2** compass tint (`a7b0358`); **A3** trigger glyph
    (`8eb6168`); **A4** no-amber/white selection (`67d7ffd`); **B1** desk title-as-picker + type popover
    (`0045ba7`); **B2** emblem keyline (`7112168`); **C1** optional `Colour.name` + desk editor (`ed7ae4e`, folds
    the `Colour.defined` model); **D1+D2** sparse palette (defined chips + "+" slots) + birth-via-type-picker,
    `markDefinedFromUsage` (`01e2914`); **D3** census protection (`colourCensus`, undoable un-define) (`32458ed`).
    New pure/testable: emblemSymbol · triggerMark · colourCensus. Off-device only.
  - **PLACEMENT + FURNITURE follow-ups (2026-07-30, user)** — (1) fresh cells take NO pre-selected routing:
    first the neighbour auto-wire / sticky routing was removed (`7e8d559`), then tightened to FULLY NULL —
    no input row, no receiver, no emitter (`9d2352d`); the routing viz + flow overlay no longer coalesce a nil
    receiver to R1 (an unrouted MIDI-IN cell draws no entry hop). Removed dead `placedCellRouting`/`PlacedRouting`
    + `lastPlaced`. (2) processor names shown in FULL — no abbreviations (`cb65424`). (3) grid numbers → down
    chevrons (empty-cell watermark + top column keys) and a NEW left row-select rail mirroring the right, both
    points-into-grid, shared whole-row verb via a parameterised `rowRail` (`9d2352d`). 351 tests green (net −3:
    dropped 4 sticky-routing tests, added 1 null-cell viz test). Off-device only.
  - **NULL-ERA SEVER + STRIPS-DONE feed (2026-07-30, user)** — (1) DELETE-sever now drops severed children to
    NULL input (inputRow nil AND inputReceiver nil, own emitters kept) instead of a phantom R1, matching new
    cells being born null (user ruling). (2) **Emitter hold-while-sounding feed** (strips-done wave pt 1): the
    render thread snapshots the voice table sliced by bus (`Router.snapshotEmitterSounding`, Voice gains `vel`),
    the UI polls it (`drainEmitterSounding`) and renders a steady cargo-tinted `SoundMark` tick per sounding note
    + a fade-on-release, mirroring `recvHeld`/`recvRelease`. 352 tests green (+ sever + sounding-feed tests).
    Remaining strips-done: hold-mark visual polish + ④ tuning are device-only. Off-device only.
  - **Docs** — `4d6a486` adds `Docs/AcceptanceCriteria/verbs-behaviour.md`; `b427cb4` fixes its mistakes/stale info;
    the null-cell placement, chevrons/dual-rails, and full-names are folded into that doc (PLACE + a new "Grid
    furniture" section; the old "sticky routing" rule is superseded).
  - **DEFERRED (user 2026-07-29): BYPASS** (receiver→emitter relay — the receivers-ferry next-priority) is dropped
    for now; its plan + ferry capture were reverted and NOT re-created (receivers ferry LATCH-single-mode /
    held-note-strip likewise un-captured). The Claude↔Claude ferry channel was cleared at the user's request.
  - **✅ DEVICE-VERIFIED (user device pass, 2026-07-30)** — the whole accumulated GUI + engine stack above was run
    on device and ACCEPTED ("happy with things as they stand"): the AcceptanceCriteria wave, routing view +
    visualisation, cells & colour desk overhaul, null cells, chevrons + dual rails, DELETE-sever→NULL, and the
    strips-done emitter hold-while-sounding feed. The device-verify backlog is cleared. (Real emblem/glyph
    ARTWORK is still a separate asset task — placeholders stand in, by design, not a defect.)
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
  Remaining wave after a7's device pass: schemas → a5+a6 → **§6d THE
  SIX-PANEL LAYOUT (2026-07-24: landscape = receivers|emitters band
  under the grid, grid-aligned, + right identity column COLOUR→ALT→TYPE→
  SETTINGS-inline; portrait = 25/50/25 × 2 band; §6c popup DROPPED —
  settings inline, the window narrows to the future EXTERNAL view host;
  truncation dies by geometry both orientations)** → §5c → ON engine.
  CHORD-LATCH (receiver tab, delta item 11) is user-DEFINITE — include
  in the receivers schema/panel work.
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
  **CLAIM v2 — SHIPPED (2026-07-27, off-device verified; device pass pending). delta §6a.**
  Three deltas built on the ghost/refcount machinery: ① PITCH-CLASS match (note mod 12 in the
  suppression check + ghost comparison — a claimed C3 suppresses every C on other emitters);
  ② MULTI-claim SHARED tier — `claimMask` (persisted; legacy `claimEmitter` kept synced = lowest
  bit for lossless downgrade); non-claimants yield the UNION of claimants' sounding classes,
  claimants never suppress each other + emit first, a muted claimant still reserves; ③ LEAK % —
  per-claimant `claimLeak[4]` (persisted); a yielded class bleeds through at scaled velocity (the
  SHADOW) instead of silence, MIN leak wins in multi (strictest shadow); LEAK 0 == v1 suppression.
  UI: the CLAIM button is now a `roleButton` (tap = toggle membership, multiple light; vertical drag
  = LEAK %). STILL PARKED: CASCADE mode + EXACT-NOTE option (the config popover). L1 caveat widens
  (pitch-class = more collisions). DEVICE-VERIFY next: octave suppression, A+B double while C/D yield,
  LEAK bleed-at-reduced-velocity.
  **THE WITHHELD TELL — strip slice SHIPPED (off-device verified).** CLAIM-suppressed (leak 0) note-ons
  now feed a parallel `Router.drainWithheld()` ring (→ Kernel `drainWithheldMarks` → AU `pollWithheldMarks`
  → VC merges into `emitMarks` as `VelMark(withheld: true)`); `velMarkLayer` draws them HOLLOW (source-hue
  outline) + an amber CLAIM tick, fading ~0.4 s. So a suppressed note reads as "withheld here", not a silent
  bug. Only full CLAIM suppression records (a LEAK shadow already shows as a dimmer normal mark; solo/mute/
  disabled are intentional). DEFERRED (slice 2): hollow comet-fizzles in FLOW (FlowView).
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
- **THREAD 2026-07-28/29 — LANDED on main (off-device verified: iOS builds + 329 unit tests green;
  DEVICE pass still pending for all UI items).** Recorded here because CLAUDE.md drifted stale — keep
  this current as work lands, not only ferry merges.
  - **Boundary LEGATO adoption** (`8d5f1b3`) — the drone-continuity engine (§2). Identity holds under
    LEGATO now flow through column boundaries instead of machine-gunning: an immortal hold voice is
    ADOPTED when the new column re-holds the same **note + emitter(bus) + Colour-and-face**; else fresh
    strike. RETRIG/.free re-strike; CHANCE/HARMONIZE re-speak; ALT-group re-strikes. Pass-length envelope
    (close-at-first-empty, wrap-reopen). `Voice` gained `colourIndex`+`alt`; drainDue skips `.max` voices;
    every other close path still `allNotesOff` (no stuck notes). Tests: `testLegatoDrone…` flipped green
    + partial-envelope + transport-stop-clean.
  - **Strips performance-surface wave** — session faces IN-PLACE (`fc3f6c3`: ROUTE IN/OUT on each strip,
    dim-beneath·glow·whole-strip target·ring·breathing; compact route bar retired) · **LATCH arm** +
    **FLAT→DUCK** (`3070ea4`, label only, `flattenMask` stays) · **SPACE-FILL** (`eecd314`: taller
    sliders/faders, MASTER full-height, HOLD grows, gutters 6→4) · **receiver VELOCITY MARKS** (`edb51d2`:
    hold-while-sounding + fade-on-release ~250ms) · **polish-laws v1** (`ffef361`: LIVE pads + role lights
    recede a step — conservative, wants device tuning) · emitter role/foot buttons taller (`2bbe8cd`).
  - **Verbs: RULED = PILLS, not circles.** I built circles (`e47c6c9`) then REVERTED to the pills
    (`2bbe8cd`) — "round and inviting" referred to the EMITTER buttons, not the verbs. Verb cluster stays
    PLACE·(DELETE·SELECT)·(COPY·PASTE) rounded-rectangles.
  - **/btw features** — ② preset selector enlarged + UNDO/REDO in the header (`9d7eac4`, model API existed,
    had no UI) · ③ the selected-visual two-sources law (`0c79ed9`: PLACE-placed + SELECT-selected share
    ONE white ring) · ① **COPY·PASTE replace MOVE·COPY** (`aa10f89`: session clipboard persists after
    release; PASTE greyed until non-empty; MOVE left the cluster).
  - **CONTROLS single-face** (`443c1e0`) — retired the dead `editing` param (behaviour-preserving).
  - **Spec updated**: `Docs/midispark-spec-v3.0-delta.md` **§10 THREAD FOLD** (`28a681e`) consolidates this
    thread's rulings + build log (newest-wins layer). New design docs preserved:
    `design-strips-target-state`, `design-btw-six-requirements` (+ the earlier verb-rebuild/spatial/
    completions docs).
  - **DEFERRED (with reasons, do not re-derive):** /btw ④⑤⑥ tails (need the user's intent — mid-PLACE
    retint scope · row/column selectors · one-per-column scope) · **emitter hold-while-sounding marks**
    (needs a per-emitter sounding-note engine feed = render-path work; the receiver has its feed) · the
    **full strip EDIT-face sweep** (OutputsView.channelStepper / ReceiversView.editFeatures still host real
    channel/cable/latch editing — must re-home to the cog before removal, per "single-face, config in the
    cog").
  - **⚠ UNVERIFIED / JUDGMENT CALLS I'm unsure about (2026-07-28/29 — flagged for the user's device pass).**
    Everything in the THREAD above builds + passes the 329 unit tests, but the unit target does NOT compile the
    UI files (VC/GridUI/ArrangementBar/CogPage), so **every UI item below is off-device-only** — logic + build
    checked, never seen or heard. Specific doubts, most-to-least concerning:
    1. **SPACE-FILL layout at small sizes.** The strips/master/controls now use `maxHeight:.infinity` with
       `minHeight` floors. On a SHORT band the floors could overflow or the fill could look stretched/empty.
       Only reasoned about, not seen. (`eecd314`)
    2. **The ROUTE-IN session face still "looks like a selection"** — the user already said so before my
       ring/breathing polish; unsure the white ring + glow distinguishes it enough vs the new white
       SELECT/PLACE ring (`0c79ed9`). May need a clearer routing treatment.
    3. **COPY·PASTE paste semantics** — I chose: paste stamps the WHOLE clipboard cell, but a top-of-chain
       paste gets `inputReceiver=0` (avoids the unpointed-MIDI-IN bypass). A pasted cell keeps its `inputRow`
       reference, which may be invalid at the new position (model falls back to derivation, dimmed). Whether
       paste should carry routing at all, or only the processor, was NOT specified — my call. (`aa10f89`)
    4. **UNDO/REDO dim-state reactivity** — `canUndo/canRedo` are read from `au` at render (not polled into
       @State); refreshes at 4 Hz + after edits. Might lag briefly. (`9d7eac4`)
    5. **Polish-laws steps are guesses** (LIVE pads → 0.72, roles → 0.82) — explicitly a v1 wanting the eye.
       (`ffef361`)
    6. **Emitter vs receiver meters are ASYMMETRIC** — receiver = hold-while-sounding + fade-on-release; emitter
       = strike-marks. RESOLVED (design 2026-07-29): the asymmetry is NOT acceptable — build the emitter
       sounding-feed with the polish pass (the "strips DONE" wave, `pending-tasks.md` §C). (`edb51d2`)
    7. **Adoption is off-device-verified only for the byte stream** (tests green) — the AUDIBLE result (drones
       actually gliding through boundaries, no clicks, claim/ALT/emitter-octave edge cases) is unheard. Confident
       in the logic; device ear-check still owed. (`8d5f1b3`)
    8. **/btw ⑥ "one placement per column"** was DEFERRED partly because I couldn't reconcile it with vertical
       chains (which need multiple cells per column) — I suspect it means per-STROKE (drag-paint), but I'm unsure
       drag-to-place is even built. Needs the user's intent before implementing.
  - **Design-vs-user note:** the ferry explicitly wanted the verbs ROUND ("enforce circles OR the user amends
    the word"); the user amended → PILLS. If the design side pushes round again, this is the resolution to cite.

## Style
- Swift, no external deps beyond apple/swift-atomics (SPM, already in project.yml).
- Comments cite spec sections (e.g. `// §3.2: stepped fields quantize`). Keep doing this —
  the spec is the contract, and drift between code and spec is the project's main risk.

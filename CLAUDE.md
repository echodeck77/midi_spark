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

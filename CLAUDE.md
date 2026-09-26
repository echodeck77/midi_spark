# MidiSpark — project briefing

AUv3 MIDI processor (`aumi`) for iPadOS. One line: **"Don't sequence notes. Sequence what
happens to them."** An 8×8 grid sequences MIDI *processors* (arps, ratchets, gates) over
time; held chords go in, five MIDI outputs come out — ALL + A–D (delta §7b). Primary host: AUM.

## How I respond to Paul (apply to EVERY reply)
- **TL;DR FIRST.** Open every response with a one- or two-sentence TL;DR — the bottom line before any
  detail, so Paul gets the gist without reading the whole thing. (This is a hard rule, not a sometimes.)
- **FLAG POSSIBLE MISMATCHES.** Whenever I make a change, explicitly point out where it might NOT match
  Paul's expectations — device-owed visuals I can't see or hear, judgment calls I made on an ambiguous
  ask, opacity/size/colour values I picked, and interpretations that could differ from his intent. Never
  let a likely mismatch go unstated; naming it up front saves a round-trip.

## Git workflow — AT LEAST TWO INSTANCES, SEPARATE WORKTREES (Paul 2026-09-11, hard rule — supersedes the shared-tree rule)
Paul runs **AT LEAST TWO Claude Code instances at once** (sometimes more), each in its OWN git **worktree** — a
separate working directory backed by the ONE shared `.git`. This is why they can NEVER collide in the working tree
(the old shared-tree "only commit my own files" rule caused 3 collisions and is RETIRED):
- **Worktree A (primary):** `/Users/paulbarrett/src/midi_spark`
- **Worktree B (second instance):** `/Users/paulbarrett/src/midi_spark-b` (branch `wt-b`)
- (Further worktrees may exist — the same rules apply to all.) Every worktree shares the SAME `.git` (one repo, one
  set of refs/remotes) but has its OWN checkout + its OWN branch, so `git status` in one NEVER shows another's edits,
  and `build/`/`DerivedData` are per-worktree (gitignored). The only shared state is the refs/remote — so integration
  is the only coordination point.

**▶ WHEN A PIECE OF WORK IS COMPLETE: commit → merge to `main` → push — ROUTINELY, WITHOUT ASKING (standing
authorization).** Don't leave finished work sitting on a local branch. "Complete" = it builds and its tests are green
(for device-only/visual work, when the off-device checks pass — flag that device verification is still owed, but
still commit+merge+push).

**Rules (standing authorization; don't ask each time):**
1. **Stay in your own worktree.** Never `cd` into another instance's worktree dir. Work, commit, and push from the
   directory you were launched in. `git status` is clean of the other instances, so stage `-A` freely (no
   cross-instance sweep risk — their edits live in their own checkouts).
2. **Branch per task, off `main`** (`git checkout -b <feature>`); commit as you go.
3. **On completion, integrate into `main` via REMOTE fast-forward** (needs no local `main` checkout, so the worktrees
   never fight over who holds `main`): `git fetch origin && git push origin <feature>:main`, then `git fetch` to refresh
   local `main`. If rejected (another instance advanced `main`), `git rebase origin/main` the feature branch, rebuild to
   confirm it still compiles, then push again. (Equivalently: FF a local `main` to `origin/main`, FF it to the feature,
   `git push origin main` — but then return your worktree to its own branch; don't leave `main` checked out, as that
   blocks the other worktrees.)
4. If a shared file genuinely conflicts on integration (two instances changed it), git surfaces it at the rebase/merge
   — resolve it there, don't guess in the working tree.
(A stale worktree can be pruned with `git worktree remove <path>` / `git worktree prune`; `git worktree list` shows both.)

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
- `BRIDGE_NOTES.md` — snapshot bridge design + hear-it tests.
- GUI mockups — **the built plugin is the living reference for SHIPPED features**;
  mockups are the behavioural spec for UNBUILT ones. TWO mockups survive (the earlier
  v26–v59 + v62 lineage were deleted 2026-09-04 as spent history): **`Docs/midispark-
  preview-v60.html` = canonical** (the last full simulator: colour pairs/ALT box/gradient
  morph bodies, cell editor + stamp banner, §6a faces, parametric glyphs, receiver bands,
  the legibility card; also the §6a EMITTER TOGGLES reference) and **`-v61.html` = the
  RATIFICATION BOARD** (a decision surface, not a full sim). NOTE: both PREDATE the rooms
  interface that actually shipped — they're the old tab/perform-era simulators, useful for
  colour/face/glyph reference but NOT the current surface (that's the built plugin + the
  CLAUDE.md status log). The AUTO/WIDE/TALL toggle is a browser preview affordance — never port it.

## Vocabulary (spec §1 — enforced, including in code comments and UI strings)
- **Machine** = the treatment (type + params + its chain). ID-based: the 16 canonical
  palette defaults PLUS unlimited ephemeral machines (`buildMachineReg` registry + `machineHueOverride`
  + GC). The old fixed-16 cap is gone. (A/B states + morph are decode-only zombies — render-dead.) Never "preset".
  (RENAMED 2026-09-09 from "Colour" — the object is a machine, not a user-picked sound colour; its display
  **hue** is *derived* from its `machineID` via `machineHue`/`machineHexes`. On-disk keys moved with the
  rename; pre-rename saved sessions factory-reset by design. Older status-log entries below still say "Colour".)
- **Cell** = one Machine placed at a grid position with its own wiring/state.
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
   200+i morph · 300 morphMaster · 400+i macro (the 8-slider automatable bank).
   Add new addresses; never renumber or reuse.
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
- **▶ KILL STEP — a new TIME processor, sibling to CLOCK (2026-09-26, on `main`, commit TBD; macOS 1121 green, iOS
  builds; DEVICE ear/eye owed). Paul's spec: a single row of ON/OFF steps (variable count, default 8) with its own
  RATE + SPAN — a disabled step is skipped, and everything downstream jumps past it; the enabled steps repeat to
  fill the pass ("enable steps 1–4 of 8 → the second half never plays, the first half plays twice"), and an UNEVEN
  count rotates a sub-cycle that drifts against the bar ("enable 3 of 8 → it rotates just those three, overriding
  the clock"). **THE INSIGHT that made this cheap:** this is EXACTLY `Derivations.lapColumn`'s ephemeral-LAP
  algorithm (`effColumn = S[absoluteStep mod k]`), now AUTHORED per-cell as a chain-position processor with its own
  clock — and CLOCK's driver-retiming plumbing (`Router.driverClockBeat`/…Inverse/`clockTransformedBeat`) already
  detects `.clock` slots ANYWHERE in a chain range and composes them in order; generalizing those THREE functions to
  ALSO detect `.killStep` slots (dispatching to a KILL STEP-specific phase function instead of CLOCK's ratio warp)
  means KILL STEP reaches the ENTIRE roster CLOCK's own multi-stage widening earned this session — every
  `iterateTicks` driver (ARP/RIFF/RATCHET-ALL/EUCLID/HOCKET), every `clockLocalAnchor`/`clockDriverTiming` generator
  (BURST/CASCADE/DRONE/SHIFT/HUMANIZE/WEAVE/RATCHET PATTERN&COIN), and every `clockTransformedBeat` fold consumer
  (DEST/VELOCITY/TUTTI/MOD) — with ZERO new call sites, because those three functions were the only place `.clock`
  was ever type-checked. KILL STEP and CLOCK also compose with each other in chain order for free (heterogeneous,
  not just "multiple CLOCKs multiply").
  **THE MATH (Derivations.swift, `killStepPhase`/`killStepPhaseInverse`):** genuinely different from CLOCK's
  continuous, everywhere-invertible ratio warp — this is a DISCRETE remap with real gaps in local time (a disabled
  column is deleted from the timeline, not slowed/sped). Construction: sort the enabled indices `e_0<…<e_{k-1}`; at
  the n-th real column since the span origin, the value fed downstream is `lap·steps + e_{n mod k}` (`lap = n/k`) —
  so `value mod steps` cycles through exactly the enabled indices in order, and `value` is STRICTLY increasing in
  `n` (monotonic local beat, which is what the shared tick-search machinery needs to walk forward and invert).
  All-disabled falls back to all-enabled (never silent/undefined, matching `clockDrawnResolveRatios`'s empty-lane
  convention) — so a fresh, untouched KILL STEP is a TRUE no-op, algebraically exact at any RATE/SPAN (`value ≡ n`
  when nothing's off). The INVERSE has a real design decision at its heart: a local beat that lands inside a
  disabled column's gap (routine, since a downstream driver's own tick grid runs at ITS rate, not KILL STEP's) has
  no real beat that produced it — POLICY (documented, not a bug): snap FORWARD to the start of the next enabled
  repeat, so a tick that would have spoken during a killed step instead speaks promptly once real content resumes.
  **MODEL:** `ProcessorType.killStep` + `killStepCount`/`killStepEnabled`/`killStepRate`/`killStepSpanN` on
  MachineParams (all additive-Optional) → resolved SnapParams fields (short/missing enabled entries default to ON,
  so an untouched row is a no-op) → the exhaustive-switch sites the compiler forced (cellMode `.identity` —
  note-transparent, like CLOCK · emblemSymbol · typeDescription · macroParamsForProcessor `[bypass]` — edited
  directly, no foldable scalar). **UI** (GridUI.swift): STEPS numPair, an ON/OFF `toggleLane` row (the RIFF/VELOCITY-
  style paint-across widget), a RATE seg (ArpRate, its own clock — unlike CLOCK, which ties to the grid's S), and
  the same `frameSpan(free: true)` SPAN control every span-having processor uses; a TIME storefront card beside
  CLOCK; `buildProcLabel` self-names "N/total" (e.g. "4/8") on the chain box, mirroring CLOCK's "N-STEP".
  **TESTS:** 6 Derivations (identity at any rate/period · the user's literal 4-of-8 and 3-of-8 examples asserted as
  exact value sequences · all-disabled fallback · a continuous-sweep forward→inverse round-trip, since every output
  the forward transform can produce is by construction never a gap · the gap-snap policy, hand-verified and then
  confirmed non-round-tripping on purpose) + 3 Router (mirrors `testClockTransformsDestsOwnRoutingClock` — DEST is
  the clearest external witness of "which step landed here"; the first draft's `beats:8`/`forceColumn:0` combination
  landed exactly on a tick boundary and picked up a spurious 17th note — caught by the test run disagreeing with the
  hand derivation, not by re-reading the arithmetic, this session's own standing discipline — fixed by widening to
  `beats: 3.9`, which stops strictly between ticks) + the fuzz roster (`.killStep` in both the machine-level and
  chain-slot rosters, `applyRandomKillStep`, including the all-disabled edge). **NEXT:** device ear/eye pass, as
  with every CLOCK-family change this session.**
- **▶ CLOCK — driver retiming WIDENED to the whole generator roster (2026-09-26, on `main`, `e5e00cd`; macOS 1112
  green, iOS builds; DEVICE ear owed). Paul's repro after the RATE-removal pass above: "euclid isn't effected by
  tempo changes, neither is ratchet — put a 1-step grid on speed, change it, put a euclid or ratchet pattern after
  it" — and asked "shouldn't all downstream processors read an upstream clock, defaulting to real time if none is
  present?", then "do the lot please." Stages 1–3 (this file, earlier entries) only wired `iterateTicks` — shared
  by ARP/RIFF/RATCHET-ALL — to the clock-transform params; every OTHER self-clocked generator computed its own
  onset/gate math directly and never read an upstream CLOCK at all: EUCLID's own `iterateTicks` call site (the
  params just weren't threaded through, even though the shared walker already supported it), HOCKET (same), BURST
  (`layBurst`), CASCADE, DRONE, SHIFT, HUMANIZE, WEAVE (both its EUCLID sub-mode and its LADDER/HARMONIC/DRAWN
  sub-mode), and RATCHET's PATTERN and COIN modes (`emitRatchetModal`) — three distinct code shapes across the
  roster, none reachable by extending `iterateTicks` alone. **NEW shared helpers** `clockLocalAnchor`/
  `clockDriverTiming` (Router.swift, beside `driverClockBeat`/`driverClockBeatInverse`) factor the pattern every
  one of these needed: shift a real anchor forward into LOCAL (retimed) time once per driver, then for each
  sub-strike invert the local onset+off pair back to real time INDEPENDENTLY — a duration can never be inverted
  directly under a non-uniform DRAWN transform, only points can, so a note's real gate length is always the real
  difference of two separately-inverted points. Both helpers are no-ops when `chainDriver < 0` (plain, non-CLOCK-
  prefixed chains stay byte-identical). **THE SOVEREIGN LAW held throughout the widening**: RATCHET-COIN's per-step
  chance decision (`rtcCoinFires(step:...)`) still reads the REAL column index — only its sub-strike SCHEDULING
  reads the transformed local beat; column-membership never moves. **TEST FIX**: `testClockDrawnDoesNotReachEuclid`
  asserted the OLD gap as correct behaviour (a deliberate scope-boundary lock at the time) — renamed/rewritten to
  `testClockDrawnRetimesEuclidToo`, asserting ×1 is a no-op and ×3 packs meaningfully more pulses into the same
  real window (an inequality, not a hand-derived count — this session's standing rule, hit twice already by trusting
  un-traced hand derivations). **NEXT**: device ear-check, as with every CLOCK change this session — confirm EUCLID
  and RATCHET (Paul's literal repro) now audibly retime, alongside the rest of the newly-wired roster.**
- **▶ CLOCK — RATE removed (a column IS a grid step) · GLIDE merged into one grid widget · the playhead now actually
  tracks the grid · GLIDE SPANS a multi-step run instead of flatlining (2026-09-26, on `main`, `f8eb2fd`; iOS
  builds, macOS 1112 green incl. fuzz; DEVICE ear/eye owed). Four fixes from one device-driven thread, none of them
  the driver-retiming feature itself — all about the grid's OWN feel now that it's built. **(1) RATE REMOVED**
  ("what's the point of rate when we have a speed-per-step grid? I think we'd lose nothing"): `clockDrawnRate`/
  `clockDrawnRateBeats` deleted from Models/Snapshot/SnapshotBuilder; every `rateBeats:` call site in
  `clockTransformedBeat`/`driverClockBeat`/`driverClockBeatInverse` now passes `S` (the cell's own grid step) — a
  clock column IS a grid column, no independent dial. **(2) GLIDE MERGED INTO THE GRID** ("should be part of the
  same grid control so it all lines up"): the old `toggleLane` GLIDE row was a SEPARATE full-width widget with no
  leading label offset, so its columns didn't align with the ratio matrix's (which reserves a 64pt header column) —
  a real geometry bug, not just a look. `stateMatrixRadio` gained an optional `extraRowHeader`/`extraRowCell` pair
  (any other caller omits them, unaffected) so GLIDE now renders as one more row INSIDE the same widget, sharing
  identical column geometry AND the same live-column highlight. **(3) THE PLAYHEAD NOW TRACKS THE REAL CLOCK**
  ("it doesn't line up with what I'm hearing at all"): the CLOCK editor never passed a `clock:` argument to
  `stateMatrixRadio` at all, so it fell through to the generic whole-grid `liveStep` column — unrelated to CLOCK's
  own steps/rate/SPAN. Now constructs its own `StateMatrixClock` (`rate: gridStepBeats` — the SAME S as (1), so the
  UI and the engine are provably the same clock — `steps:`/`span:` from the lane's own STEPS/SPAN controls) and
  passes it through. **(4) GLIDE SPANS** (caught mid-fix, against a worked example Paul gave: "three glides in a
  row, all on a distinct speed — should ramp up over three steps"): the ORIGINAL glide math ramped from a column's
  IMMEDIATE PREDECESSOR's landed value to its own target, each column independently — so three consecutive columns
  all targeting ×2 would reach ×2 after the FIRST column (1→2) then sit FLAT for the other two (2→2 has no slope
  to inherit). Root-caused live in conversation (a segment whose two ends are numerically equal can't produce a
  climb no matter how it's read) rather than guessed at. Fix: new `clockDrawnGlideEndpoints` coalesces a run of
  CONSECUTIVE glide columns that all target the SAME ratio into one SPAN, and gives a column its own linear-
  interpolated slice of the whole span's ramp (three ×2-glides after a ×1 now climb ~1.33→~1.67→2.0, reaching the
  target only at the end of the third column). A run of DIFFERING consecutive targets (1→2→3→2, each a genuinely
  new value) forms spans of length 1 throughout, reducing EXACTLY to the original one-column formula — confirmed
  unaffected, not just assumed. Threaded into `clockDrawnPhase`, its inverse, and the drift readout (all three had
  their own local `columnAdvance`/`(from,to)` lookup — now all three call the one shared span function, so they
  can't independently drift out of sync). **THE TESTING, honestly recorded because it went sideways more than
  once:** two hand-written span-math tests had OFF-BY-ONE column-boundary errors on the first draft (mapped a beat
  to the wrong column — e.g. asserting col1's midpoint at beat 0.5 when col0 occupies [0,1) and col1 occupies
  [1,2)) — caught by the actual test run disagreeing with the hand derivation, not by a second read-through; fixed
  by recomputing from the column boundaries directly rather than trusting the first arithmetic pass twice. Separately,
  three Router-level integration tests went from passing to failing to passing again as RATE's removal changed what
  S actually is: a bare, un-held test cell only ever ticks during ITS OWN grid column's real-time span `[0, S)` —
  fine for a single-step CLOCK lane (whose own real-time width is also just `S`, so it never needs to look further),
  but a MULTI-step lane now needs `steps × S` of real time to show its later columns, which a bare cell's own
  natural column window can't reach on its own. Pinning the scene's `stepRate` to force a convenient S was tried
  first and made it WORSE (it also changes how many ticks the driver's own generation fits per column, an
  unrelated engine behaviour, breaking a DIFFERENT assumption); the actual fix was `forceColumn: 0` (the existing
  PLAY-THIS-CELL mechanism, newly threaded through the `run()` test helper), which bypasses the column-lap gate so
  real time keeps advancing past the cell's own column regardless of grid width. **NEXT:** device ear/eye pass on
  the merged grid + corrected playhead + the real 3-step glide feel, as always.**
- **▶ CLOCK — FIXED and WAVE modes REMOVED ENTIRE; CLOCK is now always the one grid (2026-09-26, on `main`,
  `5a857df`; iOS builds, macOS 1110 green incl. fuzz; DEVICE ear owed). SUPERSEDES the same-day "driver retiming,
  REBUILT against DRAWN" entry below — that pass was STILL INCOMPLETE, caught by Paul directly: "tell me what I
  asked you to do that you haven't done." He'd said "remove everything you've done on clock because it's wrong,
  and complete it to this specification" — I only removed the driver-retiming layer added that same session (the
  FIXED-only `driverClockBeat`/Inverse pair + the global GLIDE toggle), and left FIXED mode, WAVE mode, and the
  three-way mode picker completely untouched, even though I'd built FIXED and WAVE earlier in the SAME session and
  neither matches Paul's spec ("a grid with a variable number of steps, each step a mutually exclusive speed, and
  another row on the same grid for glide" — one mechanism, not a choice of three). The root cause, named plainly
  when Paul asked why this keeps happening: resolving ambiguous instructions toward whatever's already loaded in
  recent context (today's narrow addition) instead of re-checking the literal instruction against the FULL current
  codebase. **REMOVED, completely, this pass:** `ClockMode` enum + the `clockMode` field entirely (CLOCK has no
  mode now — DRAWN's grid IS the whole feature); FIXED's `clockRatio`/`clockOffset` + `clockFixedPhase`; WAVE's
  `ClockWaveShape`/`clockShape`/`clockDepth` + `clockWavePhase`; the mode-picker `seg` + both branches in the
  GridUI editor; the FIXED/WAVE storefront cards (CLOCK/CLOCK WAVE/CLOCK DRAWN → one "CLOCK" card); `clockTransformedBeat`
  (the Stage 1–3 downstream-fold function) collapsed from a 3-way mode switch to unconditionally applying the DRAWN
  transform; `driverClockBeat`/`driverClockBeatInverse` dropped their now-meaningless `clockMode == .drawn` guard
  (every `.clock` slot IS the grid). KEPT: `clockRatioLadder`/`clockRatioLabels` (DRAWN's per-column picks still
  index into it) and `clockSpanN` (DRAWN's own SPAN control — was shared with WAVE, now DRAWN-only). **TESTS:**
  removed the whole FIXED/WAVE pure-function test cluster in DerivationsTests (ratio/offset math, composition,
  WAVE re-landing, monotonicity — the properties DRAWN's own tests already cover for the grid that ships); rewrote
  6 RouterTests (the RATCHET-fold flagship test, the two-CLOCK composition test, and the DEST/VELOCITY/TUTTI/MOD
  Stage-3 tests) from FIXED-mode clock construction to a shared `drawnClock(ratioIndex:)` helper — a single-step,
  all-SET DRAWN lane, algebraically identical to a FIXED ratio (`clockDrawnPhase` collapses to `beat×ratio` for one
  constant column, independent of steps/rate) — deleted the now-pointless `testClockDrawnWithOneConstantColumnMatchesFixedAtThatRatio`
  (its whole point was proving DRAWN reduces to FIXED; nothing left to compare against); trimmed
  `testClockParamsResolveAndClamp` to only the DRAWN `clockDrawnSteps` clamp (the `clockDepth`/`clockRatio` clamps
  it tested are gone with the fields); simplified `applyRandomClock`'s fuzz randomizer to DRAWN-only fields. Net
  −7 tests (1117→1110) — FIXED/WAVE tests removed outright rather than converted, since there's no FIXED/WAVE
  behavior left to test. **NEXT:** the one grid is now unconditionally what CLOCK is — no follow-up mode work
  planned; revisit only if Paul asks for a second control paradigm alongside it.**
- **▶ CLOCK — driver retiming, REBUILT against Paul's own grid (DRAWN, not FIXED) (2026-09-26, on `main`, `790fb39`;
  iOS builds, macOS 1117 green incl. fuzz; DEVICE ear owed). SUPERSEDES the same-day "driver retiming (FIXED only) +
  a GLIDE row" entry below — that build was WRONG and was entirely removed, not kept alongside this one. The story,
  for the record (a real misunderstanding, not a euphemism): Paul tested `[CLOCK→ARP]`, heard nothing, and said "the
  clock control will override the transport for everything downstream" — I read "grid" (from his own words, "we
  have a grid with x2, x3, etc, as we see now") as FIXED mode's simple ×2/×3 seg-picker (a literal reading of what's
  labelled on that row) and built driver retiming + a brand-new global GLIDE toggle for THAT mode. Paul's actual,
  much more specific follow-up spec — "a grid with a variable number of steps, each step a mutually exclusive
  speed, and another row on the same grid for glide" — describes something else entirely: DRAWN mode, which
  ALREADY EXISTED (built in an earlier stage of this same feature, well before this driver-retiming conversation) —
  variable steps (`clockDrawnSteps`, 1–32), a per-column mutually-exclusive ratio matrix (`clockDrawnRatios`), and
  an existing per-column GLIDE row (`clockDrawnGlide`) directly beneath it. So the FIXED-mode work retimed the wrong
  mode, and the new GLIDE toggle duplicated — badly, as a single global switch instead of a per-step row — a
  mechanism DRAWN already had. Paul caught this ("the grid that appears on drawn still doesn't do anything… it
  feels like you're not being straight with me") and, once the mismatch was confirmed back to him in plain language,
  said to remove all of it and build to the real spec. **REMOVED, completely:** `driverClockBeat`/
  `driverClockBeatInverse`'s FIXED-mode bodies, `clockFixedPhaseInverse`, `resolveGlideRatio` + its 3 backing arrays
  (`clockPrevRatio`/`clockTargetRatio`/`clockChangeBeat` — a whole "remember across renders" exception that turned
  out to be unnecessary), `clockRatioGlide`/`clockRatioGlideTime(Beats)` on `MachineParams`/`SnapParams` + their
  resolve lines + their FIXED-mode UI row + the `buildProcLabel` "~" suffix. **REBUILT for DRAWN instead:**
  `driverClockBeat`/`driverClockBeatInverse` now walk ONLY `.drawn` slots, calling the EXISTING `clockDrawnPhase`
  (which gained an `originOverride` param, default nil ⇒ byte-identical for its Stage 1–3 fold-consumer callers) and
  a new `clockDrawnPhaseInverse` (Derivations.swift) — SET columns invert linearly, GLIDE columns invert the
  closed-form quadratic (the antiderivative of a linear rate ramp) via the quadratic formula's `+` root, proven the
  only valid one in-range since a column's own rate is always positive throughout its span (monotonic, one root).
  Both closed-form — a bounded O(steps) walk to find the column, then one algebraic solve, no iteration — so DRAWN's
  own GLIDE needed NO new cross-render memory at all (unlike the FIXED attempt's now-deleted `resolveGlideRatio`):
  a column's ramp is purely a function of its own position, stateless by construction. `iterateTicks` threads
  `cycleBeats` + an `originRef` (the window's real start, pinned once per tick search so every slot's own SPAN-
  origin and every discovered tick agree) instead of the old `nowBeat`. Same 3 call sites (`emitArpRow`,
  `emitRiffRow`, `emitRatchetRow`'s ALL-mode branch), same sovereign-law shape (search in LOCAL time, invert to REAL
  immediately on discovery, only note-selection stays local). **TESTS:** rewrote the 4 FIXED-mode RouterTests as
  DRAWN-mode equivalents (`testClockDrawnRetimesArpsOwnGeneration`/`…RiffAndRatchetAllOwnGeneration`/
  `…DoesNotReachEuclid`/`…GlideRowSoftensTheColumnTransition` — a single-step all-SET DRAWN lane is algebraically
  identical to FIXED's linear math, so the doubling/no-op assertions carry over unchanged in spirit; the GLIDE test
  is new — hand-derived a 2-step ×1→×4 lane, SET reaches the ARP's next tick at real beat 1.125 vs GLIDE's 1.333,
  asserted comparatively per this session's standing "don't hard-code the exact sample, the discontinuity's own
  quantization isn't the property under test" rule); replaced `clockFixedPhaseInverse`'s round-trip test with
  `clockDrawnPhaseInverse`'s (5 ratio/glide/lane-shape cases × 3 origins × a beat sweep). Full suite + all 8 fuzz
  scenarios stay green. **NEXT:** FIXED/WAVE driver retiming stay explicitly unbuilt — Paul's spec describes DRAWN's
  grid specifically, not a mode choice; revisit only if asked. Device ear owed, as always.**
- **▶ HOUSEKEEPING — dead-code sweep + 3 test-coverage gaps (2026-09-26, on `main`, `7fcac1e`; iOS builds, macOS 1112
  green). Three parallel read-only surveys (dead code · missing tests · refactor/efficiency) over the whole codebase,
  every finding independently re-verified before acting (per this file's own standing pattern). **DEAD CODE (6, all
  pre-existing, unrelated to CLOCK):** `buildCreateMachine` + its stale doc comment, `buildHeaderFill` + the `BuildFill`
  enum it was the sole consumer of, `partRollCamera` + its function-specific doc (the SECTION 1 header above it
  describes still-live code and was kept), three unused colour aliases (`buildRed`/`stagingCyan`/`ladderGreen`).
  **TESTS (closing the 2 load-bearing gaps CLOCK Stage 1–3 left behind):** `SnapshotBuilder`'s WHOLE `clock*` resolve/
  clamp block had ZERO coverage — including the one safety-critical clamp (`clockDepth ≤ 0.95`, the monotonicity
  ceiling keeping WAVE's local time from running backward; a regression there wouldn't fail anywhere else in the
  suite) — +`testClockParamsResolveAndClamp`. `clockDrawnPhase`'s SPAN re-anchor branch (`periodBeats > 0`) was also
  untested (every existing test only exercises FREE) — +`testClockDrawnPhaseReAnchorsAtEverySpanBoundary`. Plus a
  minor `loopColumnPlan` out-of-range-clamp test. **REFACTOR survey: nothing actionable** — no render-path allocations
  in the CLOCK code, one flagged-but-not-urgent pre-existing duplication (`emitColumnMod`/`emitFreeMod`'s parallel
  loops), no stale comments, no bugs.**
- **▶ CLOCK — a placeable pattern-clock transform, Stage 1 (2026-09-26, on `main`, `4afe9dd`; iOS builds, macOS 1098
  green; DEVICE ear/eye owed). Design-partner spec (`AcceptanceCriteria-clock-processor`, ratified via the
  `_dear_claude_code/` channel), planned first (`~/.claude/plans/whimsical-wibbling-walrus.md`): a chain stage where
  everything downstream ticks to a transformed local time and everything upstream keeps the part's — polymeter,
  rubato, stutter-time as an ordinary chain citizen. `[EUCLID→CLOCK 3:2→RATCHET]` = hemiola; `[ARP→CLOCK ÷2→ECHO]` =
  half-time trails. **THE SOVEREIGN LAW, mechanically:** CLOCK never touches windows/columns/spans'-own-extents/the
  reel/boundary-deferred switching — only a downstream FOLD consumer's OWN internal step/rate math reads the
  transformed beat. Two pure functions (`Derivations.swift`): `clockFixedPhase` (beat×ratio+offset) and
  `clockWavePhase` (a zero-mean closed-form wobble around ×1 — SINE or TRIANGLE, both hand-verified to re-land
  EXACTLY in phase at every SPAN boundary, any depth); `depth` clamped <1 at resolve (`SnapshotBuilder`) so
  dphase/dbeat never goes non-positive (local time must never run backward, or a downstream fold's note-ordering
  breaks). **THE ENGINEERING:** `emitDriverNote`'s fold consumers (RATCHET/SPLIT/AVOID/GLIDE/VELOCITY/RECORDER) each
  do their OWN independent backward-scan for "the first/last slot of type X after the driver" — no single sequential
  pipeline to slot into. New `Router.clockTransformedBeat(cell,from:to:atBeat:S:cycleBeats:)` composes every CLOCK
  stage strictly between two slot indices (multiple CLOCKs multiply, in chain order) — wired into exactly ONE
  flagship consumer this stage, RATCHET's fold, matching the spec's own headline example. Every other self-clocked
  consumer (DEST/VELOCITY/MOD/EUCLID/TUTTI/BURST/CASCADE/WEAVE/RIFF) is an explicit Stage-3+ follow-on, not built
  blind — mirrors this session's own SPAN-LADDER staged rollout. **SCOPING CALL flagged to design (not blocking):**
  CLOCK-before-a-driver (transforming a driver's OWN generation cadence, e.g. `[CLOCK→ARP]`) is OUT of v1 — it needs
  inverting the phase function back to real time to schedule ticks, no closed form for WAVE; v1 = CLOCK strictly
  between a driver and a downstream fold consumer, matching both of the spec's given examples. Model:
  `ProcessorType.clock` + `ClockMode`(FIXED|WAVE) + `ClockWaveShape`(SINE|TRIANGLE only — SQUARE is discontinuous, S&H
  isn't periodic/deterministic the way re-landing needs) + the 9-rung ratio ladder (×4…÷4, dotted/triplet deferred
  per the spec). UI reuses only existing widgets (seg/numPair/slider/frameSpan); self-names the slot ("CLOCK ×2" /
  "CLOCK WAVE") via `buildProcLabel`; two TIME-group storefront cards. +6 DerivationsTests (fixed math, multiplicative
  composition, ×1/depth-0 no-ops, WAVE re-landing at every span boundary for both shapes/several depths/periods,
  monotonicity at the clamp ceiling) +2 RouterTests (the RATCHET fold genuinely reads the transformed beat — caught +
  fixed a test-design pitfall along the way: column 0 is invariant under any pure ratio scaling, so a first-draft
  test picked it as the "special" column and couldn't distinguish a working transform from a no-op; an RTCDEBUG trace
  confirmed the transform itself was correct throughout; two-CLOCK composition matches the product ratio regardless
  of stage order). **STAGE 2 — DRAWN mode landed same day (`e528b94`; iOS builds, macOS 1105 green):** a hand-
  authored per-column ratio LANE — `ClockMode` gains `.drawn`; `clockDrawnRatios`/`clockDrawnGlide`/`clockDrawnSteps`/
  `clockDrawnRate` (Models.swift, MachineParams) resolve ONCE at `SnapshotBuilder` time via `clockDrawnResolveRatios`
  (empty/−1 "CARRY" columns hold the PREVIOUS explicit ratio, wrapping around the lane if the whole thing is empty —
  a pure carry-forward scan, never re-mapped on the render side) into fully-resolved `SnapParams` arrays. Two more
  pure functions (`Derivations.swift`): `clockDrawnPhase` (per-column SET = snap to the column's ratio immediately ·
  GLIDE = linearly ramp FROM the previous column's landed ratio TO this one, a quadratic phase accumulation within
  that column — factored via `fullLaps × lapAdvance + partial + current` so it stays O(steps) and exact no matter how
  many laps have elapsed, never a per-lap summation) and `clockDrawnDriftPerLap` (the lane's own net beats gained/
  lost per lap against real grid time — an honesty readout, not a correction). SPAN's FREE (0) end is a genuine mode
  here (the lane just laps forever from absolute beat 0) — `spanLadderBeats` has no "0 = free" sentinel of its own
  (n≤1 means ONE COLUMN), so `Router.clockTransformedBeat`'s DRAWN branch guards `clockSpanN > 0` explicitly before
  calling it, mirroring the same idiom RATCHET PATTERN/DEST already use for their own free-run spans (caught before
  it shipped — DRAWN's UI passes `frameSpan(free: true)`, unlike WAVE's `free: false`, since WAVE's period can never
  sensibly be zero but DRAWN's can). UI: STEPS/RATE/a `stateMatrixRadio` ratio-per-column matrix (a "···" CARRY rung
  above the 9 ratio rungs) + a `toggleLane` GLIDE row + SPAN + the drift-readout `Text`, reusing only pre-existing
  widgets per the spec; a "CLOCK DRAWN" storefront card. +5 DerivationsTests (carry-forward/wrap/empty-lane fallback,
  all-×1 no-op, SET-vs-GLIDE hand-verified exact values, the drift readout cross-checked against the phase function's
  own lap advance, exactness across 50 simulated laps) +2 RouterTests (a single constant-ratio DRAWN column reduces
  EXACTLY to FIXED at that ratio — an equivalence check, not a hand-derived count, so it can't hit the column-0-style
  invariance trap again · SET vs GLIDE genuinely fold differently, hand-verified via a fresh RTCDEBUG trace after the
  first draft's parameters coincidentally produced the SAME strike total for both — the same lesson twice now: never
  trust a hand-derived beat/column mapping without an empirical trace first). Also caught pre-merge: a `toggleLane`
  call with two named arguments in the wrong order (Swift requires labelled arguments in declaration order) — would
  have failed only the iOS build, not the macOS unit-test target (GridUI.swift isn't in that target), so it's a
  standing reminder that this codebase's off-device verification needs BOTH passes, not just the faster one.
  **STAGE 3 — DEST/VELOCITY/TUTTI/MOD (`4da7446`; iOS builds, macOS 1109 green):** threads `clockTransformedBeat`
  into every self-clocked consumer that's ARCHITECTURALLY REACHABLE under the current fold model. **DEST + VELOCITY**
  ride `emitDriverNote`'s fold exactly like RATCHET's Stage-1 wiring (`clockFrom = driver + 1`) — `chopMask`/
  `emitChop` gained an optional `clockFrom`/`cycleBeats` pair (default −1/0, byte-identical at every other of the
  now-16 call sites that don't pass it); VELOCITY's slot index is now captured during the forward scan (it only had
  its params before). **TUTTI** rides `applyStage`'s generic dispatch (it's note-transparent, not pulled into its
  own explicit branch like RATCHET/VELOCITY) — `applyStage` gained the SAME optional `clockFrom`/`atSlot` pair,
  read by its ONE self-clocked case (`.tutti`) only; every other mode (ARP/CHANCE/HARMONIZE/…) ignores them
  entirely. **MOD is the odd one out — it has NO driver at all** (`emitColumnMod`/`emitFreeMod` scan every MOD slot
  in a cell unconditionally, column-gated or not), so it threads from CHAIN-START (`from: 0`) instead of driver-
  relative — the first departure from the driver-relative framing all of Stages 1–3 used until now, since "down-
  stream of a driver" simply doesn't apply to a processor whose whole point is speaking regardless of what's driving
  notes. Only the shape-READ beat is transformed; the real sample-time a CC is actually sent at (and `entryBeat`,
  the STRIKE envelope's re-trigger reference, which lives in real column-space) are both untouched — the sovereign
  law again. **BLOCKED, not attempted:** EUCLID/BURST/CASCADE/WEAVE/RIFF are `isDriverType` themselves —
  `chainDriverIndex` always makes the LAST one the chain's own driver (confirmed by re-reading its scan: only
  driver-type slots enter the `lastDriver`/`lastNonFold` tracking at all), so they never reach a downstream-fold
  position under this architecture regardless of chain order — `[ARP→EUCLID]` makes EUCLID the driver (re-pooling
  from the ARP's output via `composeChainSet`), not a folded consumer reading ARP's per-tick beat. Retiming these
  five needs the SAME phase-inversion problem Stage 1 scoped out (no closed-form inverse for WAVE or DRAWN) — not
  a threading exercise like this stage, a genuine open design question. +4 RouterTests, one `[ARP→CLOCK→X]` pair
  per consumer, each hand-verified via a fresh RTCDEBUG-style trace before asserting (two of the four — TUTTI and
  VELOCITY — looked wrong on first run: every note emits on BOTH its own cable and the shared ALL cable per §7b, so
  an unfiltered/vel-filtered count silently doubled; fixed by filtering to one cable, not a bug in the wiring — the
  THIRD time this session an apparent CLOCK bug turned out to be a test-counting artefact once traced, not an engine
  fault). **NEXT:** the CLOCK-before-a-driver scoping question is still open, going to design via the outbox — until
  it lands, EUCLID/BURST/CASCADE/WEAVE/RIFF stay untouched by CLOCK; this closes out the reachable half of the
  Stage-3 roster.**
- **▶ PART GRID — LOOP-COLUMN BUTTONS, order-preserving (2026-09-26, on `main`, `8530379`; iOS builds, macOS 1090
  green; DEVICE eye/ear owed). Paul: toggle buttons on the part grid's bottom rail restricting playback to a chosen
  subset of columns, played in the order they were ADDED (not left-to-right) — both the part-grid playhead and the
  play-ferry button's playhead must reflect it. Planned first (`~/.claude/plans/whimsical-wibbling-walrus.md`), then
  built to the approved plan. The bottom rail already existed as a placeholder for exactly this (`roomsGridFooter`,
  "PART = column-loop buttons, not wired" — drew empty boxes); the existing engine lap primitive (`Derivations.
  lapColumn`) is bitmask-based (always ascending order) and driven by a UIKit hold-gesture belonging to the retired
  GRID tab — unreachable from BUILD and unable to express "added order" anyway. **DESIGN:** resequence at scene-
  composition time rather than teach the real-time render engine a new ordered-lap concept — ONE pure primitive,
  `BuildSceneLogic.loopColumnPlan(loopCols:length:)`, maps a logical step (0..<count) to the real part column to
  read from / draw at (identity map when unused, byte-identical). BOTH audio paths — `composeSceneMeta`'s staging
  block (the active ferry) and `buildFlattenFerry` (background ferries, already a live per-publish derivation since
  the ferry-purity fix above) — and BOTH playheads (`roomsPartPlayhead`/`roomsCardRowPlayhead` for the part grid,
  `roomsCellPlayhead`'s new `steps:` param for the ferry button) call the SAME function, so the lit cell and what
  plays can never disagree (this session's standing lesson: RATCHET PATTERN → DEST → the ferry-rate fix → this).
  `BuildPart.loopCols: [Int]?` (ordered, nil/empty ⇒ play the whole part) round-trips through `buildLoadBenchPart`/
  `buildCaptureBenchPart` + the undo `BuildSnapshot`, exactly like `rate`/`length`; `buildTogglePartLoopColumn`
  APPENDS on select (added-order — re-adding a removed column goes to the END, not its old position). New
  `roomsPartLoopFooter` (a "repeat" SF Symbol per column, same size/shell as the placeholder) replaces the call at
  the PART site only — the SELECT-page footer + `roomsGridFooter` itself are untouched. **ADJACENT BUG FOLDED IN:**
  `roomsCellPlayhead`'s bar length was hardcoded to `Snap.cols` (8) even for a 16-step part — a 16-step ferry's
  button already swept 2× too fast regardless of looping; now takes the caller's real effective step count. +5
  `BuildSceneLogicTests` (loopColumnPlan identity/added-order/out-of-range-fallback; composeScene plays the selected
  columns in added order, not sorted; an empty selection composes byte-identical to today).**
- **▶ PLAY FERRIES — the background playback line is now a LIVE DERIVATION, not a cache (2026-09-26, on `main`,
  `80c1dc4`; iOS builds, macOS 1085 green; DEVICE eye/ear owed). Follow-up to the ferry-playhead rate fix, prompted by
  Paul's own mental model of the feature: "every play ferry is a part grid, only the selected one is visible" —
  TRUE of the storage (`buildFerryParts`, one `BuildPart` per ferry) but NOT of playback. The active ferry's staging
  sequencer already recomposes from the live bench every publish (pure); every OTHER on-air ferry played from
  `buildPlayColSteps/Rate/Len/StepRecv/StepEmit` — a snapshot `buildFlattenFerry` only refreshed at specific event
  boundaries (a ferry goes on / stops being active). Any edit to a background ferry's stored `BuildPart` between
  those events (its rate, its I/O, a drag-and-drop overwrite) left the cached line stale until the next transition —
  the same root cause as the rate-playhead bug, generalised. FIX: `buildPublishScene` now re-derives every ON,
  non-active ferry's flattened line from `buildFerryParts[t]` (the one source of truth) on EVERY publish, before
  those arrays are read into the scene `Input` — giving background ferries the same "always live" treatment the
  active ferry already had, just collapsed to the ONE hidden play-layer row each background ferry is allocated
  (`Snap.playLayerRowBase` — a genuine engine constraint: poly background playback isn't built, so a background
  ferry's whole grid must reduce to a mono line regardless). The persisted `@State` shape and the existing event-
  triggered `buildFlattenFerry` calls are untouched (now harmless belt-and-braces) — this closes the staleness GAP
  between those events rather than replacing the mechanism. Should also fix any other background-ferry field (I/O,
  chain) that could have gone stale the same way, not just rate — device-owed to confirm.**
- **▶ PLAY FERRY PLAYHEAD — now follows the cell's own PER-PART RATE (2026-09-26, on `main`, `c6f0f5a`; iOS builds,
  macOS 1085 green; DEVICE eye owed). Paul: changing a ferry's RATE updates the part-grid playhead at once but the
  play-ferry BUTTON's own playhead kept sweeping at the original rate. ROOT CAUSE: `roomsCellPlayhead` (the sweep
  drawn on every ferry's PLAY button) was hardcoded to the scene-default `stepBeats`, never reading PER-PART CLOCK at
  all — unlike `roomsPartPlayhead` (the part grid's own sweep), which already reads `buildPartRate` live. FIX:
  `roomsCellPlayhead` takes an optional `rate: StepRate?` (nil ⇒ `stepBeats`, byte-identical elsewhere — its only
  caller is the ferry button); `roomsPlayFerry` passes the ferry's TRUE rate — the live `buildPartRate` for the
  ACTIVE (bench-open) ferry (matches `roomsPartPlayhead` exactly, updates the instant the RATE menu changes) or the
  stored `buildPlayColRate[t]` for a background ferry (refreshed whenever that ferry stops being active).**
- **▶ ARP-RATE LFO — the ladder is now TEMPO-SORTED, not declaration-block order (2026-09-26, on `main`, `04b7807`;
  iOS builds, macOS 1085 green; DEVICE ear owed). Paul: "the LFO on the arp rate seems to miss out dotted and triplets
  even when I include them in the selection. It jumps right past them" — and pointed at the RATCHET PATTERN saga as
  the model for diagnosing it. ROOT CAUSE (same shape as the RATCHET/DEST bugs — a ladder/clock whose position axis
  didn't correspond to the real musical quantity it claimed to): `arpRateAllowedLadder(ignore:)` returned the kept
  rate indices in ArpRate's DECLARATION-BLOCK order (all 6 normal · all 6 dotted · all 6 triplet). But a dotted/
  triplet rate musically falls BETWEEN two adjacent normal rates (1/4T=0.667 beats and 1/8D=0.75 beats both sit
  between 1/8=0.5 and 1/4=1.0). Since FROM defaults to the arp's own base rate, the common sweep is between two
  NORMAL rates — and because both endpoints sat in the same contiguous ladder block, `applyParamLFO`'s linear FROM→TO
  interpolation over ladder POSITIONS never crossed into the dotted/triplet block, even with those families fully
  "included" (inclusion only ever affected which VALUES could exist in the set, never where they SAT in position-
  space). **FIX:** the ladder is now sorted by ACTUAL DURATION (`.beats`, slow→fast) instead of declaration block —
  ladder position is a true proxy for musical position, so any included rate that tempo-wise falls between the two
  endpoints is genuinely visited. `nearestLadderPos` + the interpolation math untouched, only the ladder's order.
  +1 regression test (`testArpRateLFOSweepBetweenNormalRatesCrossesIncludedDottedAndTriplet`, reproduces the exact
  reported symptom: 1/8→1/4 must cross 1/4T and 1/8D) + `testArpRateIgnoreLadderAndSnap` updated to the new order.**
- **▶ DEST MATRIX — NONE emitter + its own free-running RATE, the RATCHET-PATTERN-class fix (2026-09-26, on `main`,
  `0104c95`; iOS builds, macOS 1084 green incl. fuzz; DEVICE ear/eye owed). Paul's report on DEST (§5 routing-class,
  built 2026-08-22): zero emitters should be selectable, it needs a rate control, and "the visuals for which cell is
  lit up has nothing to do with what I hear" — he named RATCHET PATTERN's development as the precedent for how to
  read + fix this. ROOT CAUSE (same shape as RATCHET's pre-v6 bug): DEST indexed its 8-slot matrix via `chopSlice(m,
  columnBeats: S)` — an 8-way subdivision of the CELL'S OWN column, tied to whatever was driving notes through it —
  while the EDITOR matrix lit the unrelated DEFAULT grid-column clock (one column per whole bar step, ~8× slower).
  Two different clocks: the lit cell never corresponded to the emitter actually heard. FIX (mirrors RATCHET PATTERN
  v6/v7's self-clocked model): DEST now runs its OWN free-running clock — `destRate: ArpRate?` (nil ⇒ 1/8) →
  `destRateBeats`; `Router.chopMask`'s DEST branch computes `sl = floor(m ÷ destRateBeats) mod 8` (absolute beat,
  decoupled from the column/driver) instead of `chopSlice`; CHOP's own chopSlice branch is UNTOUCHED (that's a
  distinct, intentional per-column feature). The editor matrix (`GridUI` `.dest` case) extrapolates the IDENTICAL
  formula per animation frame via `StateMatrixClock` (RATCHET PATTERN's own mechanism — never the ~4 Hz poll, which
  aliases a fast rate into a jump), so the lit cell and the audible route are now always the same clock. **NONE**:
  `destSlices` gains `−1` (silence this step, no emitter) alongside 0=A…3=D — the matrix shows a 5th "·" column; a
  NONE slice yields mask 0, which every existing chopMask consumer already handles safely (no voice opens, no stuck
  note — the same path MUTE=0 already proved). FuzzTests' DEST randomizer widened to hit NONE + a random RATE. 2
  pre-existing RouterTests (`testDestMatrixHocketsTheArpAcrossEmitters`/`testMuteMatrixComposesOverDest`) still pass
  unchanged under the new clock. DEVICE-owed: the editor RATE control feel, the NONE "·" column, and confirming the
  playhead now visibly tracks what's heard.**
- **▶ RECORDER — a new looper-in-a-chain processor, stages 0–4 (2026-09-18, on `main` `87934e5`…`09d690a`; iOS builds,
  macOS 1084 green incl. fuzz; DEVICE ear owed). Paul ratified a spec (`AcceptanceCriteria-recorder.md`) then greenlit the
  build; done in tested stages while he's away (no device checks). A `ProcessorType.recorder` that records the upstream
  chain output over N steps/passes and plays it back — TRANSPARENT while recording (captured in the driver fold, GLIDE-
  style), a DRIVER while playing back (a per-window `emitColumnRecorder` pass, echo-ring class). Built: the full surface
  (editor + TIME storefront card + persisted config); the engine for a DRIVER-fed recorder — GRAIN passes|steps · LENGTH
  1…32 · ARM on-play|after-N · MODE **LOOP · FREEZE(held/repeat) · CANON** · MIX replace|layer · CAPTURE **once|refresh** ;
  and the persistence READ/CLEAR half (a persisted/authored `recEvents` = paired notes {beat·note·vel·gate} seeds the loop
  directly — a stored-clip player; CLEAR resumes live recording). The phase is a pure fn of the pass/step number → a
  committed loop is replay-exact; only the live capture window isn't seek-exact (accepted, TURNS/DEAL class). No stuck
  notes (fuzz across every edge + all modes; `testRecorder*` in RouterTests). **DEFERRED (device-ear owed on the feel):**
  the live-capture→document **SAVE drain** (render→main, so a session-recorded loop persists to disk — the crash-prone
  boundary, wants host verification); **standalone/hold-fed** recorder REPLACE-suppress (no driver ⇒ the hold layers);
  **FREEZE-HELD** true legato (v1 re-pulses per loop); **HOLD**'s momentary grab (needs a control signal). Per-cell render
  state (recNoteCap=96) reset on every flush edge (scene/panic drop the loop; transport/latch/freeze keep it).**
- **▶ THE 2026-09-14→16 ARC — RANDOM ONCE · per-param ∿ LFO (+ redesign) · MOD rework · RIFF additions · DEAL · card-grey ·
  sliders · housekeeping (all on `main`; iOS builds, macOS 1116 green; DEVICE eye/ear owed on the UI). A run of Paul's asks.
  (1) **RANDOM ONCE arp pattern** (`cd65b3e`) — `ArpPattern.randomOnce`, a per-pool shuffle from a PERSISTED `arpSeed`
  (`splitmix64Mix(asc+seed) % span`), replay-exact; PATTERN→"ARP PATTERN", FLOW→"ARP FLOW". (2) **PROCESSOR-CARD PLAY-GREY is
  POSITIONAL, not sounding** (`44fe3d9`/`bbeeaac`/`26a361c`/`6ac926c`, earlier per-cell `5592eab`/`8521d86`) — the card dims when
  the machine can't receive MIDI in the current column, read from `buildProcessingNow` (fixed the flashing: was gated on
  live SOUND, which flickered). (3) **ARP euclid GAPS=CHORD stab controls** (OCTAVE·LENGTH·VELOCITY) + LFO on HITS/ROTATE/CHANCE
  (`605c74f`/`a244ff2`/`dbc4abc`). (4) **THE PER-PARAM ∿ LFO** (`0a516a2`→`d4de554`) — a mod button beside a param label. Stage 1
  engine + Stage 2 UI, THEN a REDESIGN: `ParamLFO { target, shape (WAVE), period/stepSpan (DURATION), to }` sweeps the base
  param → TO over a DURATION (GRID STEPS · FIXED SUBDIVISION); **FROM ≡ the base param — two views of one value** (editing either
  updates both, seeded on open, kept on REMOVE); DEPTH/PHASE/QUANTIZE + `paramLFOValue` all REMOVED. Arp RATE is special-cased
  (`applyParamLFO` sweeps the rate ladder) with **INCLUDE-family toggles** (NORMAL/DOTTED/TRIPLETS via `rateIgnore`). Engine
  `applyParamLFO`; editor `lfoEditor`. (5) **SLIDERS chunkier/grabbier** (`4d12f40`, `FineSlider` track 5→9pt · thumb 16→28pt).
  (6) **HOUSEKEEPING** (`a3d57b2`) — CHORDS **8→16 fix** (`chordsDegreesResolved`/`applyChords` now size the degree matrix + rotate
  to the matrix WIDTH — a 16-wide progression was truncated to 8), Dice fillRole fix, dead `paramLFOValue` removed, stale
  "128 cells"→256 comments. (7) **MOD editor → the arp-LFO anatomy** (`383ca9c`) — reworked to FROM/TO + DURATION [GRID STEPS ·
  FIXED SUBDIVISION] + WAVE (was MIN/MAX; engine still stores `modMin`/`modMax`, only the labels/editor changed) + a live CC
  marker + `modStepSpanN` (grid-steps duration via `spanLadderBeats`). (8) **RIFF gate-length + DIRECTION** (`9afa57c`) —
  a gate-length control (with ∿ LFO) + `RiffDir` FWD/REV/PING-PONG step reorder + a roomier RATE grid + SPAN on its own line.
  (9) **NEW `DEAL` processor** (`ce1f54a`) — a simple OUTPUT dealer (ROUTING group): OVERRIDE the cell's emitters and deal N1
  notes to emitter 1 then N2 to emitter 2 (repeat, defaults 1/1). Note-transparent (`cellMode .deal = .identity`); reuses the
  TURNS moment-counter idiom in `emitArtic` with per-cell counters (reset on every transport/scene/panic edge → no stuck notes);
  DEAL mode = **OVER TIME** (per strike) · **WITHIN CHORD** (per note-in-moment) · **EVERY NOTE** (per note-on). +Router/fuzz
  tests. v1 flag (like TURNS): the deal position isn't replay-exact across a mid-phrase seek/loop; WITHIN CHORD after a mono
  driver sits at position 0. DEVICE-owed: every ∿ button + the MOD/RIFF/DEAL editors + DEAL splitting across two synths audibly.**
- **▶ FERRY DRAG-AND-DROP — long-press copy/seed RETIRED; SELECT-cell-is-a-part; colour inherit + reallocation; housekeeping
  (2026-09-12, on `main`, `7f1bd88`…`6852381` + the housekeeping commit; iOS builds, macOS 1086→1090 green; DEVICE eye owed).
  Paul reworked how a SELECT cell reaches a play ferry. **COPY GESTURE RETIRED:** the play-ferry + right side-rail LONG-PRESS
  copy/seed (and the rising-fill/commit-bloom animation) are GONE. **DRAG-AND-DROP (`947d866`)** in a shared `"rooms"`
  coordinate space (custom finger-track + FerryZoneKey drop-zone frames + floating ghost — `.onDrag` doesn't survive the AU
  host): a **SELECT cell → play ferry** populates it; a **ferry → ferry** MOVES (overwrites target, vacates source, carries
  play/mute/solo); a **ferry → the machine-box trash** deletes it (the trash now reveals on a ferry drag too). Ferry
  spring-momentary play is kept; the side-rail is tap-to-select only. **SELECT-CELL = A PART WITH ONE ROW + INHERIT
  (`6852381`):** dragging a SELECT cell makes the ferry INHERIT the cell's **name** (committed hash, else a short chain
  hash), **colour** (`ferryHue`), and **settings** (chain) — not a fresh positional part hue. **COLOUR REALLOCATION:** a cell
  dropped on a populated ferry of a DIFFERENT colour whose incoming colour is currently allocated to an EMPTY ferry → that
  empty ferry is re-allocated the DISPLACED colour (`buildFerryHueAlloc`, consulted by `buildFerryHex` for empty slots,
  persisted in `BuildPlayGridData.ferryHueAlloc`, additive-Optional). **SELECT-CELL FACE (`7f1bd88`/`d186888`):** the SELECT
  cell keeps its piano-roll face UNTIL it's committed (named), then the name replaces the roll; committed cells persist with
  the session (`gridSelChains`/`Hues`/`Names`) + no auto-revert; the ferry settings tab takes the cell's name.
  **HOUSEKEEPING (this pass):** extracted the pure ferry-drop cores to `BuildSceneLogic` (`FerryDragSource`/`FerryDropZone`
  enums + `ferryZoneAt` + `ferryColourDisplacement`) so they reach the test target (+4 BuildSceneLogicTests: ferryHueAlloc &
  gridSel* round-trips, zone hit-test, reallocation); DRY'd the ferry activate path (`buildReactivateFerry`); removed the
  now-dead copy/stamp cluster (`buildGridSelStampSweep`/`Pressing`/`Fire`/`Commit`/`CanStamp`, `roomsStampFire`, +
  `roomsAssignPlayColumn`/`roomsFlattenPartToPlay`/`roomsStampSourceIO` — the retired play-column ferry — + 5 dead @State).
  **FLAGGED:** `buildArchivePartToPlay`/`buildSelectPlayColumn`/`buildPlayFerryRow` are now orphaned too (a deeper retired
  play-column cluster — left for a dedicated dead-code pass, they touch part-grid persistence). DEVICE-owed: the whole drag
  feel (ghost, hovered-ferry cyan ring, trash reveal), the inherited name/colour read, the reallocation on a real palette.**
- **▶ COLOUR → MACHINE — the concept renamed (2026-09-09, on branch `feature/machine-rename`; macOS 1085 green, iOS builds;
  awaiting merge). Paul: the `Colour` object no longer means "a sound colour the user picks" — it is a MIDI treatment/machine
  (a processor `type` + `MachineParams`/`templateChain` + identity), carrying zero routing (that's on `Cell`) and zero stored
  colour (the display **hue** is *derived* from `machineID`). The code had drifted to "machine" in newer UI (`buildMachine*`,
  RackMatrix), so there were two words for one thing. Full rename across `AUExtension/*.swift` + `Tests/*.swift`:
  `Colour`→`Machine`, `SnapColour`→`SnapMachine`, `ColourParams`→`MachineParams`, `colourID`→`machineID`,
  `PluginState.colours`→`machines`, `colourIDs`→`machineIDs`, `buildColourReg`→`buildMachineReg`, the enum case
  `.allColour`→`.allMachine`, etc. The genuine HUE helpers took hue names not machine: `colourColor`→`machineHue`,
  `colourHexes`→`machineHexes`, `colourHueOverride`→`machineHueOverride`, `emitterColour`→`emitterHue` (overloads the
  existing `emitterHue(Set<Bus>)`), `markColour`→`markHue`, `buildEmitterPlayingColours`→`buildEmitterPlayingHues`;
  `buildColourMachine`/`buildWriteColourMachine`→`buildMachineSlots`/`buildWriteMachineSlots` (avoid `MachineMachine`).
  **KEPT unchanged (data, not names):** the palette id string VALUES `"gold".."slate"` + ephemeral `"b<n>"`/`"gsAud"` (they
  anchor the default hue palette); AU param addresses (numeric, invariant 5); position/role palettes (`playHexes`,
  `partRowHexes`, `emitterHexes`, `receiverHues`); the prose adjectives `coloured`/`colourless` (genuinely about hue). The
  British spelling isolated the project token from SwiftUI's `Color` (no 'u'), so a substring sweep was safe. **NOTHING
  SHIPPED → on-disk Codable keys moved with the field names (synthesized), so pre-rename saved sessions factory-reset — Paul
  accepted this, no migration written.** Plan: `Docs/PLAN-machine-rename.md`. Pure rename, no behaviour change; device pass
  only to confirm UI strings read "machine". NOTE: this status log's OLDER entries below still say "Colour" (history, not
  revised). FLAGGED FOLLOW-UP: the wider `Docs/*.md` corpus (specs/manual/factory-scenes) still says "colour" — a separate
  vocabulary pass if wanted; the test FILE names (`ColourTypeSwitchTests.swift` etc.) keep their filenames (symbols inside
  renamed; a file rename would need xcodegen).**
- **▶ MOD finishing — FREE/LFO cell + QUANTIZE + PHASE + EXTERN SCALE (2026-09-09, on `main`, merge of `feature/mod-finishing`;
  iOS builds, macOS 1085 green incl. fuzz; DEVICE ear owed). Launch-critical MOD polish (MOD already FUNCTIONED — all 5 sources
  SHAPE/FOLLOW/STEPS/STRIKE/EXTERN + MIN/MAX + SPAN + CC/CHAIN targets, tested; Paul's pick = FREE/LFO + refinements, NOT the
  tactile fader or ownership pin). **FREE / THE LFO CELL (§16):** `modFree` — a MOD slot speaks EVERY window regardless of the
  playhead → the grid becomes a mod-matrix (a modulation-only cell beside music cells). `emitFreeMod` scans all cells once/window
  (beat-derived, replay-safe, block-invariant; active-column FREE slots skipped in emitColumnMod → no double-emit; NO
  leave-disposition — a flush stops it; CC targets only, a FREE chain-target has no active column to fold into — v1). **QUANTIZE
  (§14①):** `modQuantize` snaps the output to N levels (pure `modQuantizeValue`, both emit paths). **PHASE (§14②):** `modPhase`
  0–360° on the SHAPE wave (quadrature sines). **EXTERN SCALE (§6):** `modExternMode` RE-EMIT|SCALE — the incoming CC scales the
  SHAPE's depth ("rhythm from us, amount from the wheel"). Model (additive-Optional) + builder + engine + UI chips (SPEAK ON
  PLAYHEAD|FREE · QUANTIZE · PHASE · EXTERN MODE). **DEFERRED with reason: FOLLOW averaging WINDOW** — a true time-average needs
  pool/event HISTORY accumulated across renders (violates invariant 2, derived-never-accumulated); wants a sanctioned state
  exception (a design call), so v1 FOLLOW stays instantaneous — flagged for Paul. +2 tests (FREE cell speaks off the playhead ·
  QUANTIZE snaps to the level set). Spec `AcceptanceCriteria-mod-finishing.md`. DEVICE-owed: the CC feel (LFO cell · EXTERN SCALE
  with a real wheel · QUANTIZE steppiness). **Launch trio DONE: RATCHET (P1 fix) · RIFF (CAPTURE) · MOD (finishing).**
- **▶ RIFF CAPTURE §2 — "play a line in", the RIFF headline (2026-09-09, on `main`, merge of `feature/riff-capture`; iOS
  builds, macOS 1083 green incl. fuzz; DEVICE ear/eye owed). Paul's launch-critical RIFF finishing (the stencil engine §1/§5
  was already solid + tested). CAPTURE: LATCH a chord (the FRAME) → arm → play the line on the SAME door → keep. The line is
  recorded AS RANKS against the frame → it FOLLOWS every chord after (zero pitches stored). **PURE (tested):**
  `riffCaptureRank(pitch,frame)` = inverse of `riffResolve` (nearest rank+oct, round-trips a frame note; passing tone snaps) +
  `riffCaptureStencil(events,frame,steps,rateBeats,startBeat)` = quantize the (beat,pitch) take onto the step grid → MONO
  riffRanks/riffOct, unplayed steps REST, a take past one loop truncated. **KERNEL:** ephemeral capture state (never persisted,
  like auditionTarget) — arm snapshots the door's held/latched chord as the frame + starts a ring; `handleIncoming` DIVERTS the
  capture door's live line into the ring (never touches the pool → the frame can't shift); disarm drains on the main thread
  (record-on-render / convert-on-main, the reel pattern → no stuck notes). **AU:** `armRiffCapture`/`cancelRiffCapture`/
  `commitRiffCapture(colourID:)` (drain → `riffCaptureStencil` → write riffRanks/riffOct onto the colour's RIFF slot). **UI:** a
  CAPTURE row on the RIFF editor (◉ PLAY A LINE IN · ● RECORDING—TAP TO KEEP · CANCEL). **v1 SCOPE (Paul-confirmed): HELD frame +
  MONO line** — FOLLOWING (§4 re-voicing / pool-timeline) · POLY (chord capture) · §3 generator are flagged fast-follows. +1
  RouterTest (capture→playback→FOLLOW-a-new-chord) + 2 DerivationsTests (round-trip incl. octave · quantize/rest/truncate).
  Spec `AcceptanceCriteria-riff-capture.md`. **DEVICE-owed caveats:** capture needs a RUNNING CLOCK (host/free-run — beat-quantized,
  so stopped lands all on step 0); LATCH-first (a physically-held chord on the same OMNI door pollutes the take); the recorder +
  arm gesture aren't unit-testable (live MIDI in) — the pure conversion + playback are locked, the feel is Paul's to verify.
  NEXT launch-critical: MOD (the CC-stage sources).**
- **▶ RATCHET PATTERN standalone = PASS-THROUGH + unselect-to-mute (2026-09-09, on `main`, merge of `fix/ratchet-passthrough`;
  iOS builds, macOS 1080 green incl. fuzz; DEVICE EAR OWED). Paul's priority-1 fix. A lone (SINGLE-SLOT) RATCHET PATTERN cell
  is now a PROCESSOR of the input, NOT a self-clocked generator: it PASSES the held chord through, and its OWN clock
  (rtcRate·STEPS·SPAN·rotate) only decides the per-column treatment — **count 1 = sustain (rate-INDEPENDENT legato hold) · 2…8 =
  ratchet N over the column's slot · 0 = OFF/mute**. No input → silence. Fixes "a short chord stab plays for each step" (the old
  standalone `emitRatchetModal .pattern` GENERATED a note per column-tick regardless of input) + adds unselect-to-mute (both
  confirmed by Paul; the OFF state REVERSES the earlier "no rest-as-silence" ruling — he now wants it). **ENGINE:** a per-window
  subsystem `emitColumnRatchetPattern` (called before the pool guard, like emitColumnMod/Glide) — a STATELESS diff-reconcile
  modelled on `reconcileBypass`, owning IMMORTAL `rtcHold` voices (a new `Voice` tag, EXCLUDED from the grid hold-reconcile;
  `allNotesOff` closes them on every transport/scene edge → no stuck notes). PASS sustains keyed on (wire,bus,colour) so a ROW of
  same-colour cells sustains SEAMLESSLY (adopt across cells); RATCHET columns window-scan staccato sub-strikes (`ratchetStrikeAt`).
  `emitRatchetModal .pattern` returns early for single-slot cells (the subsystem owns them); the `[ARP→RATCHET PATTERN]` per-note
  FOLD is unchanged + gains OFF=mute (drops the driven note). Builder clamp `1→0` so OFF survives; the matrix editor gains a `0/·`
  OFF state. **KEY BUG caught in test (not device):** first read the ratchet params from `colour.a` — wrong for a chain cell whose
  colour is a passgate; the resolved slot is `cell.proc`. **v1 SCOPE:** single-slot standalone only (a `[RATCHET PATTERN → X]`
  chain keeps the old generator — flagged follow-up). +2 tests (RouterTests rate-independence/ratchet-adds/OFF-mutes/no-input;
  DerivationsTests rewritten from the retired self-clock test). Spec `AcceptanceCriteria-ratchet-passthrough.md`. Part of the
  launch-set work (`PLAN-stream-unification.md`, on branch `feature/grid-rebuild`): RATCHET was Paul's P1; RIFF + MOD are the next
  launch-critical finishing targets, all well-tested processors ship, only hocket + weave shelved.**
- **▶ THE 2026-09-08 WORKBENCH BATCH — VELOCITY processor · grid footers · PLAY-FERRIES-ARE-PARTS · add-a-row · a
  housekeeping sweep (all on `main`, pushed; iOS builds, macOS suite green; DEVICE eye/ear owed on the UI). (1) VELOCITY
  (`ProcessorType.velocity`, `76f2027`) — a per-step velocity SEQUENCER, a note-transparent DYNAMICS MODIFIER folded in
  `emitDriverNote` (velLane/velPass/velSteps/velRate/velSpanN/velClock; `velLaneStep` pure): downstream of a driver it
  sets each note's velocity from a per-step lane, TIME clock (own RATE grid) or NOTE clock (one column per note), SPAN
  re-anchor, per-step PASSTHROUGH. Editor drag-across sliders + drag-paint bypass row (`fix/velocity-lane-drag`), euclid
  brush dropped (`cd8f803`). SCALE compressor MODE deferred. (2) GRID FOOTERS (`f81b6ae`+`b700af8`) — a placeholder row
  flush under both grids, 2/3 ferry height, interior-body width (SELECT=pages · PART=column-loop; NOT wired). (3)
  **PLAY-FERRIES-ARE-PARTS** (spec `AcceptanceCriteria-play-ferries-as-parts.md`; Phases 1–3 `c21a7d3`…`ffb9bc0`, merge
  `b4f18d3`) — each of the 8 play ferries IS a full `BuildPart` (`buildFerryParts`/`buildActiveFerry`, persisted via
  `BuildPlayGridData.parts` + `partsResolved` migration). The ferry row is the SOLE navigation (SELECT|PART toggle
  retired): a populated ferry's SELECTOR opens its part on the bench, an empty ferry → the SELECT browser; long-press an
  empty ferry on SELECT seeds a part from the selected chain **[SUPERSEDED 2026-09-12 — the long-press seed/copy is RETIRED;
  populate a ferry by DRAGGING a SELECT cell onto it (see the top FERRY DRAG-AND-DROP entry)]**; CLEAR frees a ferry (empties the part → the ferry clears →
  SELECT). Playback: the ACTIVE (on-bench) ferry plays via the STAGING step-sequencer (visible sweep, per-column selected
  rung, live edits); BACKGROUND on-ferries via the play-layer flatten — up to 8 at once. Seed fills the whole first row;
  extending a part to 16 tiles the pattern. Retired the SELECT-backed play cells / hand-authored passes / cursor. STILL
  LEFT (flagged): an entangled dead-code cluster (`buildPlayCells`/`buildPlaySel`/`buildSelectMode`/… + the `.play`/`.reel`
  room subtree) for a dedicated device-verified pass. (4) ADD-A-ROW (`buildRowCreatorMenu`, `e2ebf76`) — selecting an
  EMPTY part row turns the machine-box interior into a fixed-footprint menu: DUPLICATE/MUTATE per populated row · RANDOMIZE
  · CREATE NEW · PICK FROM LIBRARY, each minting a colour onto the row. (5) HOUSEKEEPING (5-agent survey, every finding
  re-verified) — the emitter strip now maps the active ferry whenever it's ON + background ferries from their flatten
  steps (was blank on some passes); the per-cell SOUNDING gate now covers all 256 cells (the 128-bit lo/hi gate that
  dropped a 16-wide part's cols 8–15 is RETIRED — the UI derives the gate from the 256-wide `cellSoundVel > 0`); +CR-8
  decode-tolerant `init(from:)` for `Colour`/`ProcessorSlot`/`SceneState`/`Receiver` (a future non-Optional field can no
  longer factory-reset an older doc; +round-trip tests); composeScene occ scans the full 16-wide part; +VELOCITY TIME/SPAN
  RouterTests. DEVICE-owed: the whole ferry UI + the strip + VELOCITY ear.**
- **▶ RATCHET PATTERN v6 — SELF-CLOCKED PASS-THROUGH, ✅ DEVICE-VERIFIED (2026-09-07, on `main`, `6db4ae6` engine + `c6fcbb4`
  playhead; iOS builds, macOS 1072 green). SUPERSEDES Model B (v5) below. Paul's final ruling: "Ratchet pattern is NOT a driver.
  It receives MIDI, passes it through, unless the current column is active in which case it ratchets it the specified number of
  times" + "should have its OWN clock, and any notes passed through should ratchet or not based on the timing of the ratchet
  pattern processor." So Model B's per-arp-NOTE ordinal (`g=floor(m/driverStep)`) was WRONG — a fast arp hit the ratchet every
  step or two, decoupled from the ratchet's own rhythm. **ENGINE (`emitDriverNote` PATTERN fold):** the ARP still drives; a note
  passing through reads whichever column the ratchet's OWN-RATE playhead is on AT THE NOTE'S TIME — `col = floor(localBeat ÷
  rtcRate) mod STEPS` (+ rtcRotate; SPAN re-anchors via `spanLadderBeats`/`columnStart`). `1` = pass through untouched · `2…8` =
  ratchet N over the ratchet's OWN rate slot (spacing `rtcRate ÷ N`, via the ECHO ring). NEVER silent (no rest — Paul rejected
  rest-as-silence twice). So two 1/8 notes inside one 1/4 ratchet column BOTH read that column and both ratchet. **PLAYHEAD
  (`stateMatrixRadio` + `StateMatrixClock`):** the matrix highlight was aliasing to a 1↔5 jump on 1/8 — I'd fed it the ~4 Hz
  polled `d.beat`, and sampling an ~8 Hz sweep at 4 Hz is below Nyquist → jumps of STEPS÷2. FIX: the ratchet matrix playhead now
  runs in a `TimelineView` that EXTRAPOLATES the beat per frame (`meters.beatAnchor + elapsed×tempo/60` — the app's standard
  pattern), `col = floor(beat÷rtcRate) mod STEPS`, sweeping all STEPS smoothly at RATE. `ProcessorBox` carries the beat-anchor
  trio; other matrix callers still light the global grid column (`liveStep`). Test renamed `testRatchetPatternRatchetsOnActive
  Columns` (all-1 == bare arp · all-3 > all-pass). **PROCESS LESSON (Paul, hard):** I burned his time going in circles by iterating
  on the VISUAL playhead blind (I can't see/hear the device) and by implementing from my own synthesis / reviewer notes instead of
  his literal words (twice reverted rest-as-silence + a driver rewrite mid-flight). The engine is unit-testable off-device (trust
  that); the playhead is cosmetic — when reporting, SEPARATE "does it sound right" (engine, chase with tests) from "does the light
  track" (cosmetic). v1 flags still open: burst sub-strikes ~0.6 staccato; COIN fold velFactor 1.0; the visual runs FREE (no SPAN
  re-anchor / gated on `d.playing` not free-run).**
- **▶ RATCHET PATTERN v5 (Model B) — a PER-ARP-NOTE fold + adversarial-review fixes (2026-09-07, on `main`; iOS builds, macOS
  1067+ green incl. fuzz; DEVICE ear owed). Paul: v4 "isn't very good" → a thorough adversarial sweep. VERDICT: v4's self-
  clocked driver RE-CLOCKED the arp onto its own RATE grid (point-sampling "what note is the arp on now" per tick), throwing
  away the arp's rhythm — the opposite of "process the input in front of it" / "ratchet both of the 1/8 notes." (WHY A can't
  ratchet two: a RATE tick samples ONCE, so the second 1/8 note falls between ticks, unseen.) Paul chose **Model B**: downstream
  of a driver the PATTERN ratchet FOLDS — the ARP drives, and each arp note reads the NEXT matrix column (by its tick ordinal
  `g=floor(m/driverStep)`, +rtcRotate, mod STEPS): **0 = REST (drop) · 1 = passthrough (the note at its own on/off) · 2–8 =
  ratchet** (re-fire N over the gap to the next arp note, spacing driverStep÷N, via the ECHO ring). So both 1/8 notes get their
  own column. ENGINE: `isRatchetFoldable` includes PATTERN again → `chainDriverIndex` makes the ARP the driver + the ratchet
  foldable; `emitDriverNote` gained the PATTERN branch (foldBurst/foldRest by column). STANDALONE (no driver) keeps the v4 self-
  clocked `emitRatchetModal` (RATE playhead) — now honouring 0=rest too. **REVIEW FIXES:** B1 ROTATE was clamped mod-8 in the
  builder (dead past col 8) → mod-32; B4 rtcSlices clamped 1…8 dropped authored RESTS (Dice/preset `0`s became passthrough) →
  clamp 0…8; matrix gained the **· (rest)** option (0,1,2…8). Tests: [ARP→RATCHET PATTERN] all-1 plays the arp · all-3 > all-1 ·
  all-rest silent; standalone/self-clock + rate tests kept. **STILL FLAGGED (device-eye):** B2 the matrix PLAYHEAD highlight is
  the GLOBAL grid column (`liveStep`), not the ratchet's per-arp-note position — so the visible sweep still won't match; needs a
  per-cell liveStep feed (not wired). B3 a ratcheted sub-strike is ~0.6-staccato (not the note's own length). RATE only drives
  standalone now (the arp's rate drives in a chain). The tick-ordinal advances per arp TICK (a masked/rested arp step skips a
  column). NOTE: Diag.swift/Kernel.swift were the partner instance's HOLD work — untouched; I committed only my 4 files.**
- **▶ RATCHET PATTERN v4 — the step MATRIX restored (self-clocked, per-column counts) (2026-09-07, on `main`; iOS builds, macOS
  1067+ green incl. fuzz; DEVICE ear owed). Paul: "I was wrong to say ditch the numbers" — bring the grid back, without the
  euclid control, self-clocked like RIFF with a defined step count; each column, when the playhead reaches it, decides
  passthrough or how many to ratchet. So v3's bare RATE+STEPS is replaced by: a STEP MATRIX of **STEPS columns (1–32)**, each a
  COUNT (**1 = passthrough · 2–8 = ratchet**); the playhead sweeps the columns at **RATE** (its own clock, RIFF-shaped),
  **SPAN** re-anchors (FREE = free-run). ENGINE (`emitRatchetModal` PATTERN): window-scan RATE ticks over the absolute beat;
  `col = (localTick + rtcRotate) mod STEPS` (localTick re-anchored by SPAN); `count = rtcSlices[col]`; subdivide that column's
  RATE slot into `count` staccato sub-strikes (count 1 = one hit). Feeds the upstream note (re-clocks the arp) → spreads across
  render blocks, free-runs independent of the grid. `rtcSlices` widened to 32 (builder pads/clamps 1…8); `rtcSteps` = the matrix
  length. UI: the `stateMatrixRadio` count matrix is back (`steps: rtcSteps`, options 1–8, **eFill:false** = euclid brush
  removed, drag-to-rotate kept) + a STEPS numPair; the matrix column cap raised 16→32; RATE/SPAN in the frame footer. Tests:
  per-column-count (all-4 > all-1) + the self-clock rate tests; retired the v3 span-window test. **v1 FLAGS (device-eye):** 32
  columns × 8 option-rows is cramped; a HOLD driver combo (`[DRONE→RATCHET PATTERN]`) still won't re-clock (drone rides
  emitColumnHolds); SPAN re-anchors the phase (no rests — every column fires its count).**
- **▶ HOUSEKEEPING SWEEP + the session's HOLD/colour/diagnostic fixes (2026-09-07, on `main`, PUSHED; iOS builds, macOS 1072
  green +5). Five parallel read-only survey agents (engine bug-hunt · pure-core · test-gap · docs · dead-code), every finding
  re-verified before acting. **ENGINE (`1c20892`):** Finding 1 (HIGH) — the Kernel's reel + free-run edge `router.allNotesOff`
  calls run OUTSIDE `Router.process()` (no transport edge) and couldn't reach the private `flushGlide`/`flushMod`, so a closed
  glide anchor left a dangling `glideVoices[]` slot → a reused voice wrong-closed on resume (spurious note-off). New
  `Router.externalFlush(box:atSample:out:includeBypass:)` = allNotesOff + flushGlide + flushMod; the 4 reel/free-run edges route
  through it. Finding 2 (MED) — a chatty source's incoming CC120/123 was still FORWARDED to the synth when NO latch was armed
  (silencing the grid's own sustained output while our refcount held it); `suppressAllOff` now also fires when
  `ignoreAllNotesOff`. **DEAD CODE (`6ad51cf`):** removed `buildIsDark` + `rtcSliceAt` (grep-verified zero-ref, 2026-08-16
  orphans) + the now-dead `holdReleasing` var (orphaned by the HOLD mirror-and-freeze rewrite). **TESTS (`a6e35f4`, +5):**
  `passLen` clamp + `mutateCount` range/seed; SHIFT-fold DELAYS onsets + HUMANIZE-fold replay-safe-and-perturbs (the old test
  only checked note COUNT, so an identity-regression fold would've passed) + a lone fold-ratchet still DRIVES. **KEPT + flagged
  (not removed):** `holdCaptureDecision`+`HoldCapture` (dead in prod since the HOLD rewrite but still test-documented — pending
  HOLD device-verification, may be needed if mirror-and-freeze is reverted); `hasDuplicateVoices` (reserved I3 hook); the
  dead-but-tested pure cluster (`laneValue`/`voiceLeadTowardPrevious`/`peakHoldLevel`/`triggerMark`/`poolStep` array-wrapper).
  **FLAGGED for a careful pass (not done — see pending-tasks):** decode-safety hardening — `Colour`/`SceneState`/`Receiver` are
  the three central persisted types and still lack a decode-tolerant `init(from:)`, so ADDING any non-Optional field to them =
  a whole-doc factory reset (CR-8 class; `Cell` already got the fix). Finding 3 (MED, deferred) — under `ignoreAllNotesOff` the
  live pool isn't cleared on a transport stop, so a CC123-only source re-sequences dead notes next play (the sustained-input
  case self-clears on real release; a stop-edge reset would break free-run-on-host-stop, so not fixed blind). This session's
  earlier landings are folded in here: **HOLD MIRROR-AND-FREEZE (`4549d2e`)** — the frozen HOLD pool now tracks the live chord
  when the admitted set is non-empty + freezes the last chord when it goes silent (replaced the detect-replace
  `holdCaptureDecision`; the invariant "never empty while input present"); **DERIVE-FROM-POSITION colour (`693ab8f`)** —
  `buildSelHue` derives `partPosHue(row)` for a focused ferry/part row so every machine surface shows the row's true position
  colour (`buildMachineHue` simplified); **cog HEALTH PLAY + SND (`90cc1dc`)** — the HOLD-silence bisect readout. All the HOLD/
  colour/diagnostic items are DEVICE-owed (the Kernel + UI aren't unit-tested).**
- **▶ HUMANIZE / SHIFT reclassified as per-note MODIFIERS (2026-09-06, on `main`; iOS builds, macOS 1067 green incl. fuzz;
  DEVICE ear owed; engine-only). Paul flagged these were miscategorized as DRIVERS (they re-pooled the chord on their own grid
  in a chain, discarding the upstream rhythm). Now, downstream of a real driver they FOLD — jitter/push each driven note IN
  PLACE, keeping the driver's rhythm: `[ARP→HUMANIZE]` humanizes the arp's notes (seeded per-note timing + velocity jitter,
  replay-safe by seed = column·note·index); `[ARP→SHIFT]` pushes each arp note late. MECHANISM (mirrors the ratchet-COIN-fold):
  they stay in `isDriverType` (so STANDALONE / as the ONLY driver they still GENERATE via emitGeneratorRow), but a new
  `isModifierFoldable` (shift/humanize) makes `chainDriverIndex` skip them when a real driver precedes it → the upstream drives
  and `emitDriverNote` records the downstream SHIFT/HUMANIZE (like `lenP`) and applies the per-note timing offset (on/off shift
  together, length preserved, clamped to the window like NUDGE/POCKET) + velocity scale at the final emit. So `[ARP→SHIFT]` /
  `[ARP→HUMANIZE]` emit the SAME note count as the arp (one modified note per arp note, not a re-pool). +1 RouterTest (fold ==
  arp count · standalone still generates). **v1 LIMITS (flagged):** applies on the tick-driver fold (arp/ratchet/strum/euclid/
  burst/cascade/weave/riff/hocket); a HOLD driver combo (e.g. `[DRONE→HUMANIZE]`) doesn't jitter (drone rides emitColumnHolds,
  not emitDriverNote); SHIFT still overlaps the NUDGE utility (both per-note timing — left as-is); a late push is clamped to the
  block edge like NUDGE. UI/storefront copy still calls them generators (a copy nicety, not wired — flagged).**
- **▶ RATCHET PATTERN v3 — a SELF-CLOCKED ratchet (RATE·STEPS·SPAN, RIFF-shaped) (2026-09-06, on `main`; iOS builds, macOS 1066
  green incl. fuzz; DEVICE ear owed). SUPERSEDES the fold v1/v2 below. After a long design thread Paul redefined RATCHET
  PATTERN away from a per-note fold: it now has its OWN clock like RIFF. THE BUG that triggered this: the fold indexed the
  pattern on the ratchet's rate grid, which drifted from the visible grid columns (scene step ≠ ratchet rate) → cells fired
  "every couple of steps," not once per playhead column. Paul's ruling: **RATE = the ratchet's own tick clock (replaces the
  global grid for this proc) · STEPS (1–32) = strikes per SPAN window · SPAN (like RIFF) = the window it fills then rests;
  FREE = a seamless STEPS×RATE loop (steady stream).** Each tick re-fires the upstream note (the arp's current note). Removed:
  the per-cell number matrix + euclid/rotate controls. **ENGINE:** PATTERN is a DRIVER again (not a fold) — `isRatchetFoldable`
  reverted to COIN-only, `emitDriverNote` fold reverted to COIN-only. `emitRatchetModal`'s PATTERN branch rewritten to a
  SELF-CLOCKED, absolute-beat window-scan (spreads across render blocks, free-runs independent of the grid): anchors at
  `period = SPAN>0 ? spanLadderBeats : rate×steps`, fires `steps` strikes at `rate` from each anchor then rests. New model
  field `rtcSteps` (ColourParams + SnapParams + builder; `rtcSlices`/`rtcRotate`/`rtcSpan` now decode-only). **UI:** PATTERN
  editor = STEPS numPair (1–32) + the frame footer's GRID(=RATE) · SPAN (ROTATE dropped), no matrix. **TESTS:** rewrote the two
  ratchet-PATTERN tests to the self-clock (faster RATE = more strikes; SPAN window w/ small STEPS < free-run) + the Derivations
  density test; retired the CELL|ROW slice test. **v1 LIMITS/FLAGS (device-ear owed):** STEPS is audible mainly via SPAN
  (with SPAN FREE every tick fires, so STEPS just sets the seamless loop length — flagged to Paul, accepted); the ratchet
  re-clock replaces the arp's note LENGTHS with RATE-staccato strikes (Paul embraced the re-clock); each strike ~0.6-staccato;
  the frameRow ROTATE slot is now an EmptyView (possible layout gap — device-eye). The COIN pass-through fold (rtcFold) is
  unchanged + still spreads via the echo ring.**
- **▶ RATCHET PATTERN fold v2 — AUDIBLE ratchet via the echo ring, REST dropped, matrix 1–8 (2026-09-06, on `main`; iOS builds,
  macOS 1066 green incl. fuzz; DEVICE ear owed). SUPERSEDES the same-day "true REST = silence" fold below (two mis-reads
  corrected). Paul: (1) REST should be pass-through, not silence — so DROP rest entirely, matrix = **1,2,3,4,5,6,7,8** (1 =
  plain/untouched · 2–8 = ratchet); (2) `[ARP 1/8 → RATCHET PATTERN 1/8]` with a 2/3/4 slice gave only "slightly shorter length,
  not ratcheting." ROOT CAUSE of (2): the fold bursted each arp note over its own SHORT GATE (`offOut−onSample`) → sub-strikes
  crammed into a near-inaudible flam; and a per-tick fold can't spread strikes across audio blocks (the engine emits note-ONs
  immediately, only note-OFFs defer). RATIFIED MODEL: the ratchet's RATE = a pattern LENS (which count each arp note reads);
  the count N = re-fire that arp note (its OWN pitch + length) N times spaced over the gap to the NEXT arp note (spacing =
  driverStep÷N); RATE never touches length; long notes' copies OVERLAP (engine re-articulates same-pitch, no stuck notes).
  IMPL: `emitDriverNote` emits strike 0 (the note at its own length) then registers N−1 copies as **ECHO-ring tails**
  (`pushEchoTail`, feedDelay 1 · decay from BURST-FADE · gateBeats = note length) — reusing the proven cross-block, no-stuck,
  flood-governed, replay-safe drain. `driverStep = Snap.arpRateBeats[driver.rateIndex]`. COIN fold now spreads the same way.
  Standalone/driver PATTERN path: REST removed (`count = max(1,min(8,raw))`, window-scans as before). Matrix → `[1…8]` +
  `rtcSliceAt`/set default 1; `rtcSlices` default `[2,1,2,1…]`. Tests updated (all-1 == arp alone · 2/4-per-step > arp; dropped
  the silence assertions). **v1 LIMITS (flagged):** `driverStep` uses the driver's nominal rate (exact for a uniform arp;
  approximate for variable-spacing drivers); a downstream ECHO echoes only strike 0, not the ratchet copies; N−1 tails/arp-note
  can hit the 256-tail ring / 48-per-beat flood cap under extreme settings (copies drop, no stuck notes). DEVICE ear owed.**
- **▶ RATCHET PATTERN — a downstream PER-NOTE FOLD + a true REST (2026-09-06, on `main`; iOS builds, macOS 1066 green incl.
  fuzz; DEVICE ear owed). Paul: `[ARP → RATCHET PATTERN]` altered notes on rest + made short arp notes long. ROOT CAUSE:
  RATCHET PATTERN, as the LAST driver, BECAME the chain driver and RE-POOLED the arp — a chain driver reads only the upstream
  NOTE POOL (via composeChainSet), never its rhythm/lengths — so it discarded the arp's 1/8 timing + note-lengths and played
  its own grid (long notes, firing on the arp's rests); and a "·"/0 pattern slice was coded as ONE PLAIN HIT, never silence.
  Paul's model (ratified): PATTERN should PROCESS the upstream input per-note — ratchet each arp note IN PLACE. FIX (generalises
  the 2026-09-06 COIN `rtcFold`): `isRatchetFold`→`isRatchetFoldable` now true for PATTERN too (always) — so `chainDriverIndex`
  (rewritten: last non-foldable driver, else the last driver so a lone/`[HARMONIZE→RATCHET PATTERN]` ratchet still DRIVES)
  skips a PATTERN ratchet when a real driver precedes it → the ARP keeps rhythm + lengths and `emitDriverNote` folds the
  pattern onto each driven note: slice REST (0/·) DROPS the note (+ its echoes, like LENGTH MUTE), 1 = pass through, 2/3/4 =
  burst its own [on,off] span (ramp = BURST FADE). Fold slice = the pattern's own RATE grid at the note's time (`floor(m/rate)`
  + rotate). **TRUE REST (Paul's ruling, changes existing patterns):** 0/· is now SILENCE in BOTH the fold AND the
  standalone/driver path (`emitRatchetModal`: `if raw<=0 { continue }`), and the PATTERN matrix gained a **1 = plain** state
  (was `[0,2,3,4]` → now `[0,1,2,3,4]`, `·`=REST). +1 RouterTest (all-1 == arp alone · all-REST = silence · all-2 bursts ·
  standalone all-REST silent) + updated the DerivationsTest that had encoded 0=plain. **v1 LIMITS (flagged):** the fold samples
  the pattern on its RATE grid (Paul's "1/4" example), not the SPAN-ladder/CELL|ROW span (that still shapes the standalone
  driver path); the matrix has no per-slice velocity; two PATTERN ratchets after one driver → only the first folds. DEVICE ear
  owed. NOTE: default rtcSlices `[2,0,2,0…]` now reads as roll-2/REST (was roll-2/plain).**
- **▶ RECEIVER STRIP — velocity indicator stripped back to a simple bar (2026-09-06, on `main`, `40dd3bd`; iOS builds; UI-only,
  DEVICE eye owed). Paul: strip the receiver strips right back to a simple velocity indicator + controller "as it was before",
  keeping the MIDI-accuracy fixes. Removed the two fader accretions in `buildReceiverFader` (BuildPage.swift): the per-machine
  FEED COLOURS (`buildReceiverFeedColours` — bands tinted by the cells the door feeds; DELETED, receiver-only, unused) and the
  chord/key-aware meter treatment (`buildMeterBands(faded:true)` energy-waist + `buildMeterNoFeedBand` grey shimmer). The fader
  is again ONE flat bar — cyan for the metered/held velocity, pink while dragging the override. KEPT (the accuracy fixes):
  `recvHeld` sustained-while-held level, the 30 Hz attack flash (`meters.receiverPeak`), the latch-velocity read, and drag-to-
  override (`setReceiverVel`). Strip BUTTONS unchanged (CH/ENABLE, LATCH mode, OCT, S/M — Paul chose "meter only" scope, not the
  mode-button or bare-fader options). `buildMeterBands`/`MeterBand`/`buildMeterNoFeedBand` KEPT (the EMITTER fader still uses them
  via `buildEmitterPlayingColours`). **TWO-INSTANCE NOTE:** BuildPage.swift had the other instance's uncommitted work; I staged
  ONLY my 3 hunks (`git apply --cached` of an isolated patch) and FF-pushed to main, leaving their work untouched in the tree.**
- **▶ IGNORE INCOMING ALL-NOTES-OFF — the sustained-chord "empty pass" fix (2026-09-06, on `main`, merge `27304e1`; iOS builds,
  macOS 1065 green; DEVICE ear owed). Paul: a third-party app feeding SUSTAINED chords dropped out for most of a pass even
  WITHOUT hold — a synth on the same source held it fine. ROOT CAUSE (confirmed via Paul's MIDI monitor): the source floods
  **CC120 (All Sound Off) + CC123 (All Notes Off) on all 16 channels** around each chord (loop/phrase/transport resets are
  common), and `Kernel.handleIncoming` wiped the ENTIRE live input pool on the first CC120/123 (`pool.reset()`), CHANNEL-
  AGNOSTIC — so it nuked even a channel-filtered door, and since the burst shares the chord's render block (all Time:0), the
  just-arrived chord was erased before the grid read it → silent pass. (The 2026-08-31 fix already spared the FROZEN/HOLD
  pool from this; the LIVE pool was still wiped, which is why HOLD only partly rescued it + why the HOLD `.replace`-thinning
  bit on top.) FIX (Paul chose toggle, default ignore): document-level `PluginState.ignoreAllNotesOff` (additive-Optional,
  resolved DEFAULT TRUE = ignore) → `SnapshotBox.ignoreAllNotesOff` → Kernel guard `… && !ignoreAllNotesOff` on the pool
  reset. Real note-offs still release notes; host/transport panic + the a8 stuck-note nets still flush. Cog **INPUT** section
  toggle ("IGNORE ALL-NOTES-OFF"). +1 SnapshotBuilder test (resolver default TRUE + box carry; explicit false honors). DEVICE
  ear owed (Kernel isn't unit-tested). FLAG: default flips existing docs to ignore — intended (a MIDI processor re-sequences
  input, so a source's routine reset shouldn't clear it); turn it OFF per project if a source uses CC123 as its only release.**
- **▶ RATCHET COIN "PASS-THROUGH" — a downstream per-note ratchet fold (2026-09-06, on `main`; iOS builds, macOS 1064 +
  fuzz green; DEVICE ear owed). Paul: "[ARP → ratchet] that plays through most notes but hits particular notes with a
  ratchet, by probability — pass through when NOT ratcheting." The existing `[ARP → RATCHET]` makes RATCHET the DRIVER
  (it's the last driver → re-pools the arp), and it gates every note ~60%, so it can't pass notes through untouched. NEW
  opt-in `rtcFold` (COIN-only): a fold-ratchet is NOT counted as the chain driver (`chainDriverIndex` skips
  `isRatchetFold`), so the UPSTREAM driver (the ARP) keeps its rhythm + note lengths; a new `downstreamRatchetFoldIndex`
  fold in `emitDriverNote` decides ONCE per driver note (seeded on its column step → replay-safe, gap/quota reuse the COIN
  scan): COIN fires → REPLACE the note with a burst subdividing its OWN [on,off] span (`rtcCoinCount`/`rtcCoinSize` +
  `ratchetVelocity` ramp); else emit it UNCHANGED (true passthrough). The ratchet slot is note-transparent in the set fold.
  Additive-Optional `ColourParams.rtcFold` (synthesized-Codable safe) → `SnapParams.rtcFold` → builder copy; UI = a
  RATCHET-DRIVES | PASS · RATCHET CHOSEN seg on the COIN editor. +1 RouterTest (chance 0 = byte-count-identical to the arp
  alone = passthrough · chance 1 = every note bursts) + fuzz randomizes `rtcFold` (~200s chaos, no stuck notes). **v1
  LIMITS (flagged):** the COIN chance is evaluated on the SCENE-step grid (one decision per column) — for a clean per-note
  chance, run the arp at the column rate; a sub-column-fast arp shares a column's decision. ODDS-FROM-VELOCITY isn't wired
  in fold mode (velFactor 1.0). The burst sub-strikes are ~60% staccato (a ratchet roll), not the note's own length.**
- **▶ CELL CONSTELLATION v2 — the device-feedback rework (2026-09-05, on branch `fix/cell-constellation-v2`; iOS builds; UI-only,
    DEVICE eye owed). v1 (`c7ad7f4`) failed on device: constellations appeared ONLY on SELECT, part/play cells lost their notes,
    the part cell colour didn't match the selector + looked faded, and the playing cell didn't animate. ROOT CAUSE: v1 only
    converted the LIVE-DRIFT face (`buildNoteSweep`), which draws only while notes are ACTUALLY sounding → idle cells blank;
    SELECT used the always-visible OFFLINE roll. **FIX — one unified always-visible face `buildOutputFace(bars,tint,playing)`:**
    every cell (SELECT · PART · PLAY · ferries · row selectors) now draws its EXPECTED-OUTPUT constellation from the offline
    rolls, static when idle, with a beat-locked PLAYHEAD sweep + dot-glow when playing. `buildGridSelPianoRoll` +
    `buildGridSelDriftFace` delegate to it; `roomsPartCell` + `roomsPlayFerry` use it (replacing the idle-blank `buildNoteSweep`).
    Rolls: PART = the existing per-row `buildGridSelRowRoll`; PLAY = a new per-column `buildPlayColRoll` (`buildComputePlayColRolls`);
    both recomputed in `buildPublishScene` so they stay current. **PART colour = the row's MACHINE hue** (not v1's separate
    fixed-position palette — "row 7 always yellow" = its yellow machine), drawn DARK + SATURATED + FLAT (`partCellFill`/`Frame`
    via `buildBaseHex`) so it MATCHES the selector and isn't faded. **[SUPERSEDED 2026-09-06 (`4966de5`/`693ab8f`): PART +
    ferry colour REVERTED to FIXED-BY-ROW-POSITION (`partRowHexes` via `partPos*`) per design-cell-language decision 4 — the
    machine-hue `partCellFill`/`buildBaseHex` recipe now serves ONLY the PLAY ferry; `partRowHexes` is the LIVE token.]** **drawConstellation tuned:** smaller dots, stronger sigil
    lines, + the `playhead` param (bright sweep line + dots brighten as crossed). **DEVICE-OWED / flags:** still can't verify the
    look; the `isEditedRow` black breathe (an edit invite) is a possible "faded row" Paul saw — flagged, removable; v1's
    `partRowHexes` token is now unused (harmless); the face is the EXPECTED-output constellation animating (not literal live
    strikes) — if Paul wants actual live-strike drift back it's a follow-up overlay.**
    **v3 device fixes (same day): the playing/selected cell now SCROLLS the constellation (two beat-offset copies, seamless
    loop) instead of a playhead — the NEW playheads were removed (`drawConstellation` playhead param gone; existing
    roomsPartPlayhead/roomsCellPlayhead untouched); SELECT scrolls on mere selection (was gated on live MIDI); the part cell
    is DARKER (`partCellFill` mix 0.24, `partCellFrame` 0.48 — was 0.52/bright-0.85) + the PART-PAGE ferries now wear the same
    dark fill/frame (gated `roomsRoom == .part`; the PLAY grid keeps its dusk blends) to kill the "still bright" look.**
    **v4 device fixes (same day): the scroll now runs ONLY while `d.effectivePlaying` (host or free-run advancing) → STATIC
    when the transport is stopped (v3 free-ran off wall-clock → skipping, esp. when stopped) and beat-locked/in-sync when
    playing. + THE STARS BLINK on a live strike: `buildOutputFace` gained `strikeIdx` (part `[idx]` · play `buildPlayColSweep-
    Indices(t)` · select `buildChainAuditionRow`); the timeline runs only when scrolling OR the strike feed (`buildCellRoll`)
    is non-empty, so a cell with no MIDI in never blinks; `drawConstellation` boosts a dot's size+opacity when a recent strike
    (age<0.3s) matches its pitch lane. DEVICE eye owed (blink delay ≤ the 4Hz poll; boost/decay constants tunable).**
    **v5 ANIMATION REWRITE (Paul: "worth rewriting completely?" — yes). The v2–v4 face fought itself: offline sigil + beat-
    EXTRAPOLATED scroll (jittered, ran when stopped) + offline↔live blink MATCH (missed/doubled). REWRITTEN around ONE source,
    the LIVE strike feed (`buildCellRoll`): idle/stopped → the STATIC expected-output sigil (no timeline → no jitter); notes
    SOUNDING → each real strike is a bright STAR at its true pitch drifting left + fading (in sync by construction, ONE star per
    note → no misses/doubles), over the dimmed sigil. The beat-scroll + the lane-matching blink are GONE. Also fixed the
    LONG-STANDING blank-then-redraw flash — the roll caches (`buildGridSelCellRoll`/`RowRoll`/`buildPlayColRoll`) no longer
    eager-`= [:]`-clear before the async refill (kept until the new dict swaps in atomically). And the PART grid is DEEPER dark
    (`partCellFill` mix 0.16, `partCellFrame` 0.34 over the ground — was 0.24/0.48) to kill the "primary as fuck" look. FLAG: I
    read "the side grid" as the PART grid (SELECT is already grey) — if a different grid is meant, redirect; the resting sigil
    is still the bright EMITTER colour (per the ratified design) — if THAT reads too primary, dimming it is the next lever.**
    **v6 (Paul corrected the model): the CONSTELLATION ITSELF scrolls + its OWN notes light — NOT a static sigil with a
    separate note layer drifting over it (v5 was wrong). `buildOutputFace`: when the live strike feed is non-empty (MIDI
    flowing → static otherwise, incl. stopped), the whole sigil (dots + path) scrolls right→left beat-locked (two beat-offset
    copies, seamless loop) and `drawConstellation(phase:)` LIGHTS each dot as the scroll carries it to the play line (x≈phase)
    — deterministic, in sync, no matching. The v5 drifting-live-stars-over-static-sigil is gone. **v7: the flash sat at the
    LEFT edge (x=0) + the wrap copy off the RIGHT edge → "flash on both edges, off-screen, disconnected." Moved the PLAY-POINT
    to ~28% from the left (`translate (0.28 − phase + k)·w`, k∈{−1,0,1}) so a note reaches it EXACTLY when it sounds → the flash
    is on-screen + singular (wrap copies fall fully off-screen); the glow is symmetric (`d = min(f, 1−f)`) so its peak lands on
    the beat. **v8 (the REAL disconnect — "dots flash on the beat but not on the note"): in v6/v7 the dots were ALWAYS the
    OFFLINE render (`gridSelRollBars` → `Dice.runRecorder` against the fixed standard chord `[60,64,67]`) on ALL THREE grids;
    the live strike feed was only an on/off "is it playing" gate. So the sigil showed a DIFFERENT chord's output — right beat
    grid, wrong pitches/sequence. FIX: `buildOutputFace` now — IDLE → the static offline blueprint (the identity at rest, no
    sound to contradict); PLAYING → the ACTUAL EMITTED NOTES from the live strike feed (`buildCellRoll`), a dot per real note
    at its real pitch, drifting right→left, brightest as it sounds (the buildNoteSweep model). The dots ARE the notes you hear
    → correspondence by construction, no offline↔live matching. Removed the scroll/`phase` machinery + `drawConstellation`'s
    phase param. All three grids route through `buildOutputFace`; the offline rolls survive only as the idle blueprint.**
    **v9 (the SELECT→part FERRY brought into line — it had never migrated to the part-cell look): the right-rail ferry
    (`roomsSideChip`, `part: false`) violated the spec 6 ways — a machine wash that brightened on play, the REJECTED two-layer
    note model (`buildGridSelDriftFace` static blueprint + a separate `buildNoteSweep` over it, dimmed 0.45–0.55), an emitter
    GLOW on play, a ground fill that didn't match the part cell, and a bright-on-play machine frame. FIX (part:false only, the
    part-grid rail untouched): flat `partCellFill(buildRowColour(n))` ground + `partCellFrame` frame (white ring when active,
    never a hue-brighten) + ONE `buildOutputFace(strikeIdx:)` (blueprint at rest → live emitted notes when auditioning) + the
    glow/wash/dimming/two-layer all removed. Ground now routes through `partCellFill(buildRowColour(n))` = the SAME recipe as
    the part cell, so the two read identical AND the position-vs-machine-hue colour choice (#6, ~~PARKED for Paul~~ RESOLVED
    2026-09-06 `4966de5`/`693ab8f`: FIXED-BY-POSITION via `partPos*`/`partRowHexes` — the derive-from-position model) is a
    one-place change in `partCellFill`.**
    **BUGFIX (2026-09-06, macOS 1063+2 green): re-selecting (TAPPING) a populated SELECT→part ferry made the machine box/chain/
    play-button colour fall to light GREY. Root cause: `buildGridSelAimRow`→`buildGridSelLoadChain` sets `buildSelID = gsAud`
    (the transient audition), and `machineBinding`'s `grey = onSelectPage && selID == gsAud` fired even though a real coloured
    ferry was the active source (the STAMP path dodged it by focusing the row's real colour via `buildTapColourTab`, so it was
    inconsistent — "often"). `colourHueOverride[gsAud]` already holds the ferry's hex, so the only defect was `isGrey`. FIX:
    `machineBinding` gains `activeFerry` (= `buildGridSelStampSourceRow != nil`); `grey = … && !activeFerry`. A ferry keeps its
    colour; a plain gsAud cell audition still greys. +2 assertions in `testMachineBindingResolvesFerryAuditionAndGrey`.**
    **MODEL REFACTOR (2026-09-06, Paul: "should be in the model, not an if statement"; macOS 1063 green, iOS builds): the
    ferry-vs-cell identity was two mutually-exclusive `Int?` @State (`buildGridSelSel` / `buildGridSelStampSourceRow`) kept in
    sync BY HAND across ~13 paired assignments + inferred via ~16 `!= nil` checks — a desync risk, and why the ferry could
    render grey (the resolver couldn't tell a ferry from a cell). Now ONE model value: `BuildSceneLogic.SelectSource` enum
    (`.none/.browseCell(Int)/.ferryRow(Int)`, pure/testable) as the single `@State buildSelectSource`; the two old fields are
    COMPUTED projections over it (`nonmutating set`, a nil-write clears only its OWN case) so every existing read/write site
    compiles unchanged AND exclusivity is now a TYPE GUARANTEE (can't be both). `machineBinding` drops the `activeFerry` bool
    for `source: SelectSource` — grey ⇔ the audition is loaded AND `!source.isFerry`, derived from the one value. Test updated
    to the `source:` signature + SelectSource projection assertions.**
- **▶ CELL DESIGN LANGUAGE — the CONSTELLATION face + three-grid differentiation (2026-09-05, on branch `feature/cell-
    constellation`; iOS builds; UI-only, DEVICE eye owed on the WHOLE look). Ratified with Paul over a mockup
    (`claude.ai/code/artifact/2b727eeb…`, spec `Docs/design-cell-language.md`). ONE idea: every cell paints its output as a
    CONSTELLATION (a dot per note, radius ∝ velocity, at x=time/y=pitch, joined by a faint sigil path); the three grids differ
    only by COLOUR + MOTION. **RENDERER:** new shared `drawConstellation(ctx,size,points,tint)` (Canvas; faint x-ordered path +
    velocity-sized dots) replaces the note-BAR drawing in `buildNoteSweep` (the live drift, PART+PLAY) and `buildGridSelPianoRoll`
    (the offline SELECT roll). **SELECT = monochrome blueprint:** the constellation in grey ink (tint from `buildGridSelCell`),
    a STABLE sigil with a sweeping PLAYHEAD when auditioning (replaces the old scrolling-notes); selected cell = the INVERSE
    (light stage, dark sigil) — inverse is SELECT-only. **PART = dark colour + bright notes:** `roomsGridCellBody` gained
    `flatFill`/`flatFrame`; `roomsPartCell` passes a DARK, FLAT, FIXED-ROW colour (`partRowFill`/`partRowFrame` from a new
    8-hue `partRowHexes` token — row identity by POSITION, not machine) + a row-colour frame; the constellation rides on top in
    the bright EMITTER colour (kept). The emitter/part separation is by LIGHTNESS (dark ground · bright marks), the fix for
    their overlapping hues. AUTO ramp is the one allowed exception. **PLAY = blended (unchanged look):** keeps the dusk washes +
    per-cell playhead + PLAYING glow; only the note FORM becomes constellation dots. **RATIFIED (Paul):** constellation face ·
    keep current emitter colours (dark cell makes them pop; NOT lightened globally) · velocity kept (dot size) · fixed-by-row
    palette (any distinct set) · inverse = SELECT-only · Part keeps live drift. **DEVICE-OWED / flags:** the entire look is
    unverifiable off-device (dot sizes, path opacity, drift feel, the 8 row hues, dark-cell saturation — all tunable constants);
    `buildGridSelDriftFace` (the row-selector fingerprints) still draws BARS — a consistency follow-up; empty part cells stay
    blank (row colour on populated cells only); the SELECT playhead-sweep is a behaviour change from the old note-scroll.**
- **▶ PROMOTE = ARCHIVE-THE-PART-GRID-then-CLEAR (Paul changed his mind; 2026-09-05, on branch `feature/promote-archive-restore`;
    iOS builds; UI-only, DEVICE eye/ear owed). SUPERSEDES the same-day "PROMOTE = MOVE / remove the source row" below. Paul:
    "if promoted to the playgrid FROM the part grid, store the status on the WHOLE part grid with the new play grid cell so it
    can be restored later (restore currently unimplemented)." Rulings (AskUserQuestion): the grid is CLEARED after archiving;
    the null-I/O pulse (the other half) STAYS. **IMPL (`BuildPage.swift` + `AudioUnitViewController.swift`):** dropped
    `buildRemovePartRow`; added `BuildPartSnapshot` (a value-copy of the whole part grid — stagingCells/stagingSel/rowReceiver/
    rowEmitters/rowChain/rowShade/rowUnder/deletedRows/partLen/partRate/partCast/selReceiver/partEmitters), `@State
    buildPlayColPartSnapshot: [Int: BuildPartSnapshot]` (keyed by play COLUMN), `buildCapturePartSnapshot()` +
    `buildClearPartGrid()` (clears every row + resets the per-row/part state) + `buildArchivePartToPlay(t)` (snapshot → store →
    clear). Both promote paths call it: `roomsFlattenPartToPlay` (a PART promote — always) and `roomsAssignPlayColumn` (a
    SELECT-cell ferry — only when the source is a part row, `buildGridSelStampSourceRow != nil`; a library-sourced ferry leaves
    the grid alone). The null-I/O pulse (B2, `buildPartJustPromoted`→`buildIONullPending`) is unchanged. **RESTORE is NOT built**
    — the snapshot is captured + stored only. **FLAGGED:** the store is IN-MEMORY (`@State`), so it does NOT survive save/load
    yet — persisting it (with the play grid's `BuildPlayGridData`) lands with the restore feature; keyed per play COLUMN (per-cell
    keying possible if wanted); a cell-ferry from a part row now also archives+clears the WHOLE grid (device-check that breadth).**
- **▶ PROMOTE = MOVE (remove the source part row) + FRESH-CELL NULL-I/O PULSE (2026-09-05, on branch
    `feature/promote-remove-row`; iOS builds; UI-only, DEVICE eye/ear owed). Paul: "when a cell or part is promoted to the play
    ferries, remove the row it was promoted from from the part grid; when a part is promoted and a new cell is selected/created
    on the select grid, the emitter+receiver toggles are set to null and all 8 controls PULSE invitingly." **B1 PROMOTE = MOVE
    (`BuildPage.swift`):** a new `buildRemovePartRow(r)` (clears the row's cells via `buildSetRow(r,nil)` + nils per-row I/O +
    de-selects any column rungs pointing at it). `roomsAssignPlayColumn` (a SELECT-cell ferry) captures `buildGridSelStampSourceRow`
    BEFORE `buildSelectPlayColumn` clears it, then removes it (nil source = a library cell → nothing removed). `roomsFlattenPartToPlay`
    (a PART promote) removes the DISTINCT rows the part was made of (the rungs across the flattened columns — Paul's ruling:
    "the rows it was made of", not the whole grid). **B2 FRESH-CELL NULL PULSE:** `roomsFlattenPartToPlay` arms
    `buildPartJustPromoted`; the NEXT select-grid cell tap (`buildGridSelTapCell`) consumes it → `buildIONullPending = true`.
    While pending: all 8 I/O chips render OFF + a breathing cyan keyline (`buildIOSelectChip` gained a `pulse` param using the
    house `stagingPulseFraction`/TimelineView idiom), and `buildDefaultEmitters` returns [] → busMask 0 → the cell is SILENT
    (Paul's ruling: "silent until wired"). The invitation clears on the FIRST I/O edit (`buildSelectDoor`/`buildToggleBus` +
    the two ALL variants clear the flag; the emitter setters build from EMPTY on the first pick, not the [.a] default).
    **JUDGMENT CALL / flagged mismatch:** Paul chose "silent until you pick BOTH a receiver AND an emitter"; v1 clears the
    whole invitation on the FIRST I/O touch (the existing fresh-row-flash idiom), so picking a receiver first un-silences on
    the default emitter A. A strict silent-until-BOTH gate would need a true-null receiver (buildSelReceiver = −1, risk of
    index crashes) + decoupling silence from display — a device-tunable follow-up. Whole feature is UI, DEVICE eye/ear owed.**
- **▶ SPAN AUTOMATION PHASE 2 — render-time ×N passes + STEP|SMOOTH, LANDED (2026-09-05, on `main`, `50159b8`+merge
    `c6ab8fb`; iOS builds, macOS suite green). Completes the parked Phase 2 (Paul: "all of phase 2 except cc dominance").
    A part-AUTO lane spans multiple bars (×2/×4/×8 passes) and/or ramps SMOOTHLY, overriding one SCALAR proc param FROM
    the beat instead of the compile-time bake. `AutoLane.spanPasses`/`smooth` (decode-tolerant) → `AutoParamField` (24
    scalar targets) + `SnapParams.settingAuto` (value-copy, clamps mirror applyProcessorValues) + `ColourAuto` in
    `SnapshotBox.renderAuto` (builder populates for an ACTIVE ×N/SMOOTH lane; STEP/default spans stay the Phase-1 bake) →
    `Router.applyRenderAuto` at emitTickRow + emitColumnHolds (STEP = integer column rank endpoint-inclusive; SMOOTH =
    continuous sawtooth). UI (`autoSpanColumn`): ×N live + MUTUALLY EXCLUSIVE with the 1–8 step ladder + a STEP|SMOOTH
    row (SMOOTH continuous-only; ×N/SMOOTH greyed for nested params that can't reach the render engine). +6 RouterTests +
    AutoParamField/settingAuto-clamp tests. **NOTE (two-instance collision):** the BuildPage (autoSpanColumn) + AU
    (setBuildAuto) halves were swept into the scale-pools commit `4ba091a`, briefly breaking main; `50159b8` added the
    model/engine/tests to make it whole. **v1 LIMITS (flagged):** SMOOTH sampled per render window (block-start, like
    applyInternalMods — deterministic per schedule, not block-size-invariant) · scalar-only render surface · per-part-
    clock/16-wide parts use the SCENE beat for the pass math (exact for uniform 8-wide). **CC-prominence PARKED** (Paul's
    carve-out; design elaborated 2026-09-05 — see pending-tasks + PLAN §11). DEVICE-eye owed on the ×N/SMOOTH UI.**
- **▶ THE CHORD DOOR = a chord SEQUENCER — re-architected to REUSE the CHORDS processor (2026-09-05, on branch
    `feature/chord-door-sequencer`; iOS builds, macOS 1057 green; DEVICE eye/ear owed). Paul: "the same chord sequencer that
    appears in the sequencer, identical controls; future processor dev must reflect on the door; 4 interesting default chord
    sequences; D as the chord door's key source; chord mode default on receiver C." SUPERSEDES the 2026-09-04 single-chord
    `ChordPool` door (fe708c7) — that model is gone (its stale JSON key decodes away harmlessly). **THE SHARING (the "future
    dev reflects" contract — three shared surfaces):** ① CONFIG = `ColourParams` — `Receiver.chordSeqs: [ColourParams]?` (4;
    only `chords*` fields used) + `activeChord`; a future `chords*` field appears on the door for free. ② EDITOR = the
    processor's own `ProcessorBox` — the pop-up MOUNTS it (slotMode, `showSlotChrome:false`, `plainTitle`) bound to the active
    instance's ColourParams, so the controls are LITERALLY identical (MODE·SCALE-FROM·degree MATRIX·VOICING·SPREAD·RATE·STEPS·
    WALK); `onEdit` persists via `setReceiverChordSeq`. ③ ENGINE = one pure `chordSeqNotes(beat,p,keyRoot,keyTones,followNote)`
    (Derivations) — the Router's CHORDS stage was REFACTORED to call it (behaviour-identical; all existing CHORDS RouterTests
    green) AND the Kernel door-fill calls it. `SnapshotBuilder.applyChords` (the ColourParams→SnapParams chords copy) is also
    shared between the cell build + the door build. **TIME-VARYING POOL:** the builder puts each chord door's active config into
    the box (`receiverChordsParams: [SnapParams?]`); the Kernel walks the progression per render on `renderBeatPos` (host/free-
    run), keyed by the SCALE-FROM door (`chordsScaleRef` → `receiverScaleRoot/Type`), and fills the latch pool (beat-derived,
    replay-safe). The builder bakes NO static chord pool (`receiverPianoNotes` empty for a chord door; piano bit still set so
    the Kernel fills it live). **DEFAULT RIG (makeInit):** D → SCALE door (existing A mixolydian); C → CHORD door; C's 4
    instances = `Receiver.defaultChordSeqs` (AXIS I–V–vi–IV · 50s I–vi–IV–V · JAZZ ii7–V7–I7–vi7 · PACHELBEL, all KEY FROM D).
    **UI:** strip CHORD button opens `buildReceiverChordPopup` (mounts the editor); door-sheet "EDIT CHORD SEQUENCER ▸"
    launcher; slot RADIO (SEQ 1–4); strip/tab label "A · CHRD" (`buildChordDoorLabel`). **+5 tests** (chordSeqNotes pattern/
    walk/follow/rest/loop · box carries the config + no static pool · radio switches the box config · chordSeqs decode-tolerant
    incl. the stale `chordPools` key ignored · the default rig wires C→D). **JUDGMENT CALLS (Paul-answered + flagged):** RADIO
    switch confirmed; time-varying autonomous confirmed; FOLLOW on a door sits on the tonic (no play-along trigger wired, v1);
    free-run interaction device-owed; no matrix playhead in the door editor yet (liveStep −1). Spec: `Docs/SPEC-four-scale-
    pools.md` (CHORD section rewritten). **BUGFIX (2026-09-05, `Kernel.swift`): the CHORD door never self-armed → silent by
    default (Paul: "can't arm it"). `computeEffectiveLatchMask` only self-armed a piano/scale door when `pianoNotes[i]` was
    non-empty, but a chord door's pool is TIME-VARYING so its pianoNotes is ALWAYS [] → its bit never entered the latch mask.
    FIX: a chord door (`chordDoorParams[i] != nil`) self-arms unconditionally (being a chord door IS reason to arm, like a
    scale door with notes). Kernel-only, device-verified.**
- **▶ THE CHORD DOOR — a new latch/key/hold-class door mode (2026-09-04, on branch `feature/chord-door`; iOS builds, macOS
    1057 green +5; DEVICE eye/ear owed). Paul's spec: a new `DoorMode.chord`, a SIBLING of the scale door — FOUR instances
    radio-switched from a strip pop-up, each a DIATONIC CHORD generated (CHORDS-processor primitives) from a referenced SCALE
    door, output as the receiver's pool. **MODEL (`Models.swift`):** `ChordPool {source·degree·voicing·spread·baseOct}` +
    `Receiver.chordPools`/`activeChord` (additive-Optional; nil ⇒ four defaults, no legacy migration — new mode).
    `latchPianoResolved` true for `.chord` (rides the KEYS pipeline: self-arm · EXCLUDE · play-along). **ENGINE:** pure
    `chordDoorNotes(root,tones,degree,voicing,spread,baseOct)` (Derivations, wraps the existing `diatonicChord`); the
    SnapshotBuilder's piano-notes map gained a `.chord` branch that resolves the SOURCE scale door (root+scale from
    `recvsForPool`, C-major fallback if the source isn't a SCALE door) → `receiverPianoNotes`. A CHORD door's
    `receiverScaleRoot` stays −1 (it's not a scale door; the CHORDS PROCESSOR reads scale only from scale doors). No render/
    Kernel change (rides SCALE's pipeline). **AU:** `setReceiverActiveChord` + slot setters (source/degree/voicing/spread/
    baseOct) via `editReceiverChordSlot` (materializes the 4 pools). `setDoorMode` .chord case. **UI (`BuildPage.swift`):** the
    strip CHORD button opens `buildReceiverChordPopup` (twin of the scale pop-up, in `roomsSharedOverlays`, gated on
    `buildChordPopupDoor`); `buildChordPoolEditor` = a 4-slot RADIO (each names its chord via quality-aware `degreeLabel`) over
    KEY-FROM(▸·A–D scale doors, non-scale dimmed) · DEGREE(I–VII) · VOICING · SPREAD · OCT + a live note-name readout; the
    MIDI-IN door sheet's CHORD row is an "EDIT 4 CHORDS ▸" launcher; strip label "CHORD"; the mode radio auto-lists it
    (DoorMode.allCases); tab/chip name themselves ("A · V7", `buildChordDoorLabel`). **+5 tests** (builder generates the right
    chord from a referenced scale door · no-source→C major · radio switches the chord · decode-tolerance/default · the pure
    `chordDoorNotes` anchoring). **DECISIONS (Paul-implied, flagged):** each instance = ONE standing chord (no PATTERN/FOLLOW/
    WALK — the 4 instances + hand-switching ARE the progression); KEY FROM references a SCALE door (C-major fallback). Spec:
    `Docs/SPEC-four-scale-pools.md` (CHORD section). DEVICE-OWED: the live radio switch (heard), pop-up legibility, the
    self-arm amber caveat (shared with SCALE). NOTE: built on the two-instance feature-branch workflow — merge+push routine.**
- **▶ FOUR SCALE POOLS PER SCALE DOOR — model + migration + the switch/config pop-up (2026-09-04, on `main`, UNCOMMITTED;
    iOS builds, macOS 1046 green +5; DEVICE eye/ear owed — UI + the live switch). Paul's spec (he chose RADIO + config-in-the-
    pop-up via AskUserQuestion): a SCALE door now holds FOUR configurable scale pools and switches between them LIVE via a
    pop-up on the strip SCALE button (RADIO — exactly one active). **MODEL (`Models.swift`, the load-bearing/elegant part):**
    new `ScalePool { root·type·baseOct·octaves }` (Codable/Equatable, defaults = the legacy single-scale defaults) +
    `Receiver.scalePools: [ScalePool]?` / `activeScale: Int?` (both additive-Optional). The FOUR existing resolvers
    (`scaleRootResolved`/`scaleTypeResolved`/`scaleBaseOctResolved`/`scaleOctavesResolved`) were RE-POINTED at the ACTIVE pool
    (`activePool` = `scalePoolsResolved[activeScaleResolved]`) — so the whole render pipeline (builder/box/kernel/CHORDS) is
    UNTOUCHED; switching the radio just republishes the box with the new active scale. `scalePoolsResolved` MIGRATES a legacy
    door (scalePools nil ⇒ pool 0 = the legacy single scale, pools 1–3 default, active = 0) → BYTE-IDENTICAL for old docs; a
    stray `activeScale` with no `scalePools` is ignored (guard). **AU (`MidiSparkAudioUnit.swift`):** slot-aware setters
    (`setReceiverScaleSlot{Root,Type,BaseOct,Octaves}`) + `setReceiverActiveScale` (the live radio) via a
    `editReceiverScaleSlot` that materializes the 4 concrete pools before mutating; the 4 legacy flat setters now DELEGATE to
    the active slot (no divergent path). **UI (`BuildPage.swift`):** the strip SCALE button (`buildReceiverLatchButton`) now
    OPENS the pop-up for a SCALE door (other modes keep arming — SCALE self-arms via the derived pool, so nothing to toggle);
    the MIDI-IN door sheet's scale row became a LAUNCHER (active-scale summary + "EDIT 4 SCALE POOLS ▸") to the same pop-up;
    `buildReceiverScalePopup` = a top-aligned card (like MIDI INPUTS, in `roomsSharedOverlays`, gated on `buildScalePopupDoor`)
    wrapping the shared `buildScalePoolEditor` = a 4-slot RADIO row (each names its scale, tap = switch active LIVE via
    `buildRecvEdit`) over the ROOT/SCALE/RANGE/EXCLUDE editor for the active slot. **+5 tests** (SnapshotBuilderTests: legacy→pool-0
    byte-identity + stray-active guard · radio switches the resolved scale · pad/clamp · decode-tolerance round-trip · the
    builder pool switches the fed derived set). **EXTENSIBILITY:** the pop-up shell is built to host a future CHORD variant
    ("later show as chord selected — to be defined"). Spec: `Docs/SPEC-four-scale-pools.md`. **DEVICE-OWED / judgment calls:**
    the SCALE button's amber "engaged" visual still reads off the MANUAL latchMask (a SCALE door self-arms, so it may look
    un-engaged though it's feeding — pre-existing, flagged) · the strip button label stays "SCALE" (doesn't show which slot is
    live — a nice-to-have) · editing a slot requires making it active first (radio model) · pop-up sizing/legibility.**
- **▶ SPAN-ONLY PART AUTOMATION + the AUTO-section batch (2026-09-04, on `main`, `7bd06ea`…`97038c7`; iOS builds,
  macOS 1041 green; DEVICE-eye owed — UI-heavy). Reworked the part-page AUTO band + rebuilt the automation MODEL to
  span-only, per the ratified plan `Docs/PLAN-span-automation.md`. **THE AUTO-SECTION UI (`7bd06ea`+`bb5d8d8`):** the
  panel below the tabs is TWO COLUMNS (left ~30%… wait, left ~80% MACHINE/PARAM/SWEEP · right 30% the SPAN ladder);
  SWEEP endpoints render the control APPROPRIATE to the param kind (continuous→slider · toggle→ON/OFF · option→cycle ·
  stepper→◀n▶ · mask→raw); a STATE row draws the live FROM→TO ramp + a playhead; the row headers + tabs wear the
  SELECTED machine colour; the edited row PULSES a black face over the static colour; every automation cell shows an
  "AUTO N" label. **SPAN-ONLY MODEL (`ad9fb75`, the keystone):** an AUTO lane is now ONE contiguous FROM→TO span that
  TILES across the row (replaces the punch-arbitrary-`cells` extent). `AutoLane` gained `spanStart`/`spanLen` (additive-
  Optional; legacy `cells`/`span` retained for decode + MIGRATED on load — a cells range → a span). `applyAuto` tiles
  the ramp (`rank = (col−start) mod len` → the existing linear `autoRamp`); a cell before the start is untouched;
  default (start 0, len = partWidth) = one sweep across the whole part; `partWidth` threaded through composeScene.Input;
  byte-identical when no lane armed. **UI:** arming a lane applies a default whole-part span IMMEDIATELY (audible at
  once — the fix for "armed a lane, heard nothing"); a DRAG on the part grid DRAWS the span (press=start, release=end,
  live; `buildPartDragAnchor`); `partGridTap` lost its punch case (span-draw is UI-side); the 1–8 ladder sets the
  length, ×2/×4/×8 (passes) are GREYED (Phase 2 = render-time). Retired `buildAutoToggle`/`buildAutoArmedParam`.
  **FOLLOW-UP (`97038c7`):** fixed 3 leftover `cells`-reading sites the switch broke — the tab "has-content" dot,
  CLEAR (now resets the span), and `buildCaptureAuto` (was pruning span-only lanes from the save). **DECISIONS (Paul):**
  span TILES · DRAG to draw · ×N deferred · 1-D per row. +11 tests (span tile/offset/default/no-lane byte-identity/
  round-trip/legacy-cells migration; partGridTap updated). **OPEN:** [Phase 2 LANDED 2026-09-05 — see the top entry] · device-eye ·
  2 small UI calls (highlight tiles the whole row vs first span; 1-D drag on any row) · minor dead-code (legacy
  `span`/`cells` fields). Plan: `Docs/PLAN-span-automation.md` (marked BUILT) + `Docs/PLAN-span-automation-phase2.md`.**
- **▶ PART PAGE POLISH BATCH — piano-roll rebuilt OFFLINE + a run of device-driven fixes (2026-09-04, on `main`,
  `5f70c7d`…`0254c3a`; iOS builds, macOS 1032 green; ALL device-eye/ear owed — the whole batch is UI). A long
  device-driven thread with Paul. **THE PART PIANO ROLL, rebuilt to an OFFLINE deterministic feed (`5f70c7d`):**
  the live-capture roll lagged one cycle (the "audio up / notation down octave" report) + was unreliable; replaced
  with `renderOfflinePartRoll(box:pool:latched:latchMask:cyc:)` (Emission.swift, Foundation-only, unit-tested) — runs
  the REAL Router over the current box for ONE pass against a CLONE of the live/latched pools (`NotePool.clone()`),
  so the roll is the part's exact output with NO lag + no audio-thread dependence. `Kernel.offlinePartRoll` +
  AU forwarder + a VC recompute gated by a `partRollSig` (held notes · selection · rate · `buildPartRollGen`,
  bumped by buildPublishScene); the live PartTap capture is retired. Router tags each emitted note with its cell
  index (`markCell`) + display hue (`markColour`) so the roll filters to the SELECTED rung per column. **THE ROLL
  LOOK (`0d20d1c`…`2bc89d3`, after several wrong turns — the bars were ~2px tall, too small to render two colours):
  notes = the EMITTER colour (a note reflecting ALL its cell's selected emitters as stacked horizontal bands); the
  CELL is a BORDER-only box around each column's section (the cell's colour). Readable fixed bar height.** **PLAY
  BUTTON (`bbe4d65`):** the machine play-button playhead now animates ONLY while the HOST transport runs (`d.playing`),
  never free-run/auto-engage — added `diag.effectivePlaying`; fixes the "strobes/jiggles when stopped" report (it was
  wall-clock-extrapolating a frozen beat). **8 PLAY FERRIES (`cd8726e`):** the part-page ferry row is ALWAYS 8 (the
  play layer), not `cols` — a 16-wide part no longer draws 16 ferries indexing the 8-slot play layer out of range.
  **PART-GRID SELECTION (`8dbe8cb`):** unpopulated cells are selectable again — the AUTO-lane PUNCH mode had been
  swallowing every non-punch tap; PUNCH now intercepts only its own cells and everything else (empty included) falls
  through. Extracted the decision to pure `BuildSceneLogic.partGridTap` + 5 locking tests. **LAYOUT + AUTO POLISH
  (`bec319f`…`0254c3a`):** the AUTO footer slide-up is retired — the piano roll is FIXED at two play-grid cells and
  the AUTO controls are ALWAYS visible below it to the page bottom (tabs top-anchored); the AUTO row headers +
  tabs wear the SELECTED machine colour; when a lane is armed non-selected part cells go HOLLOW (face → background,
  border kept); the SELECTED rung is ALWAYS a white outline drawn on top (never recoloured, faded only slightly under
  a lane); the FOCUSED number-rail chip INVERTS (solid machine-colour fill + alpha number). +1 side-rail fix
  (`6ddeb36`, the part rail is a simple selector, no longer follows the sequencer). Plan: `Docs/PLAN-part-piano-roll.md`.**
- **▶ OVERNIGHT BATCH — 7 queued jobs (2026-09-03, on `main`, `9010ca1`…`64330ae`; iOS builds, macOS 1023 green incl.
  fuzz; part-roll/AVOID-seg DEVICE-owed). Paul: "queue ten high-value jobs that don't need my involvement." Landed the
  safe, off-device-verifiable ones; flagged the two needing his semantic ruling. **Job 1 (`9010ca1`)** Info.plist — all
  four orientations + dropped `UIRequiresFullScreen` (clears the two Xcode deprecation warnings Paul flagged; project.yml
  → regen App/Info.plist; AU UI is host-sized so inert for the plugin). **Job 2 (`36834d1`)** decode-tolerant
  `AutoLane`/`PartAutoColour` — the newest persisted types were synthesized-Codable with non-Optional fields; partAuto is
  a PluginState dict, so a future field would throw → whole-session reset (CR-8 class). Added the tolerant inits + 2 tests.
  **Job 3 (`7b93b2e`)** THREE read-only bug-hunt agents (AUTO bake · 16-step · CHORDS · AVOID · macro fold · part-roll) —
  NO stuck-note/determinism bugs; fixed 4 confirmed: (a) **PartRollDeck render↔main RACE** — render wrote cur/last while
  the 4 Hz poll read them (violates the value-copy invariant, garbles the roll) → double-buffered publish (render writes
  the inactive of two flat buffers + flips a scalar; roll() snapshots the active by value); (b) **AUTO lane default →
  BYPASS** for the ~12 types w/o a curated autoPrimaryKey (params.first is always bypass) → falls back to the first
  NON-bypass param; (c) **CHORDS WALK froze after 64 rate-ticks** (free-running step, clamped) → loops mod 64; (d) an
  unguarded receiverRangeLo read. +3 tests. **Job 4 (`0abf896`)** dead-code + refactors — removed the inert ladder/old-EDIT
  tap machinery (armLadderRung/ladderPending/ladderBlink/playCellOnly/setEditSolo/editSelTargets — grep-proven inert, the
  old-UI triggers are deleted; syncSingleModeActivation stays live for LADDER presets) + dead `chordsModeResolved`; added a
  `posMod` helper, hoisted RATCHET's legal-repeats literal, fixed a DEBUG cell-coord (i/8→i/Snap.rows). **Job 9 (`dfb46c9`)**
  fuzz the 16-WIDE multi-clock path (was only ≤8-col) — ~30% of docs now widen to maxCols + loop >8 → non-uniform; all 8
  fuzz scenarios green. **Job 7 (`64330ae`)** AVOID §G "EVERYTHING OUT" (ratified) — `AvoidRefKind.soundingOut` = all
  emitter output minus this cell's own buses (self-exclude by bus); avoidRefMask gains ownBusMask (threaded ×3). +1
  RouterTest + fuzz allCases. **FLAGGED for Paul (in pending-tasks): job 5** (16-wide ROW-span procs — polymeter-every-8
  vs full-span, a v1 SEMANTIC), **job 6** (CHORDS invert-toward-previous — voice-leading is path-dependent vs the replay-
  exact rule), and the deferred perf/cosmetic items (CHORDS render-path alloc; 16-wide sounding/solo mask widening; the
  editMode/EditPageMode residue; the AVOID §G editor seg + OUTPUT-ref piano). Job 8 (coverage) folded — the AUTO/macro/
  16-step surfaces were already test-thorough.**
- **▶ 16-STEP GRID — the §E flip, DONE (2026-09-02, on `main`, Stage A `bf6ccaa` + Stage B `e696f07`; iOS builds, macOS
  1015 green; the part-grid UI is DEVICE-EYE owed). Paul: "the 16 step grid." A part's grid can now be 8 OR 16 columns.
  **STAGE A (engine substrate, byte-identical):** the safe framing — `Snap.cols` STAYS 8 (the DEFAULT/uniform BAR width;
  ALL cycle math, ROW-span, and the uniform fast-path key on it → the default part is UNTOUCHED), and a new `Snap.maxCols`
  = 16 is the ALLOCATION ceiling. `Snap.cells` = maxCols·rows (128→256); SceneState.empty + SnapshotBuilder allocate/scan
  maxCols; the per-row loop-length CLAMP widens to maxCols (a part loops 16), the UNSET fallback stays Snap.cols=8. So a
  16-wide part is NON-uniform → the proven, fuzzed MULTI-CLOCK per-row path (cycR = Lr·Sr) plays its 16 columns; an
  8-wide part stays uniform-fast, byte-identical. Router emission/index guards + topCell wrap → maxCols (≤7 identical).
  **STAGE B (authoring):** BuildPart.stagingCells/stagingSel + BuildSceneSnapshot.performCells/Chain + the @State mirrors
  are 16-wide (old 8-col saves decode short + are padded — `Snap.padCols`; `buildNormalizeStaging` normalizes to 16×8,
  was 8×8-TRUNCATING); composeScene builds staging+perform across maxCols (play grid stays 8 columns, each a ≤16-step
  pass via passLen→maxCols); `reconcileStagingSel` → 16; `roomsPartGrid` renders `buildPartCols` (= buildPartLen 1…16,
  nil⇒8) columns (cells shrink); a NEW header STEPS **8 | 16** control sets the part width (`buildSetPartLen` →
  stagingLen → rowLength). Drift feedback (buildNoteSweep) covers 16 for free (Snap.cells=256). **+2 tests** (a 16-wide
  part composes col 12 + row loops 16; the ramp/clamp updated); 4 pre-existing 8-assumption tests re-pointed (rowLen
  clamp 1…16, swap out-of-range past 16×16, 2 reconcile counts). **FLAGGED (device/deferred):** ROW-span processors
  (tutti/length) use the 8-wide bar → in a 16-wide part they repeat every 8 columns (polymeter, not full-span — a v1
  semantic); the old-grid cellSounding/tap/solo masks aren't widened (rooms uses the Snap.cells drift feed, not them);
  the piano-roll mock doesn't scale to 16; the STEPS control placement + 16-col legibility are device-eye owed.**
- **▶ PART AUTOMATION — the AUTO lanes now PLAY + persist (2026-09-02, on `main`, `b7d82e5`+`8d2837a`; iOS builds, macOS
  1014 green; the band is DEVICE-EYE owed). The part-page AUTO band became AUDIBLE. Per colour, FIVE lanes + NONE; ONE
  active lane (per-colour `activeLane`, −1=NONE). Paul's 4 rulings: per-param SUB-RANGE · one active lane per colour ·
  low→high column-order single sweep · extent = the colour's own cells. **MODEL:** `AutoLane`/`PartAutoColour` moved to
  BuildModel.swift (Foundation-only, Codable, in the test target); `PluginState.partAuto` (additive-Optional, keyed by
  colourID). **ENGINE BAKE:** `BuildSceneLogic` gained the pure core (autoPrimaryKey/autoResolvedParamKey/autoSubRange/
  autoRamp/applyAuto) + composeScene folds the active lane onto each part cell via `applyProcessorValues` — a cell in the
  extent gets its param set to the ramped sub-range value (rank/(count−1), column→row). Baked at BUILD time → the render
  is unchanged (invariant 1), like the macro/M2 fold. Byte-identical when no lane armed. **LIVE:** selecting a lane /
  editing / punching a cell republishes (buildPublishScene). Persistence rides the play-grid pattern (pending/consume +
  buildPersistTick). **HEADER:** NONE (left) · AUTO 1–5 (span) · CLEAR (separate, right); select = enable. **+4 tests**
  (ramp across the extent, NONE = base untouched, sub-range/ramp endpoints, doc round-trip). Plan:
  `Docs/PLAN-part-automation.md`. DEFERRED (P4, if wanted): configurable BEFORE/AFTER + a RATE/curve within the extent.
  Macros are SHELVED to v2 (the AUTO flow replaces them). DEVICE-OWED: the whole band + the punch-on-grid feel.**
- **▶ MACRO AUTOMATION M1+M2 — the engine foundation (2026-09-01, on `main`, `2aa17ed`+`f157ef8`; iOS builds, macOS 999 green;
  engine-only, no UI yet). The ratified macro-automation build (§K settled) begins with its two ENGINE increments — the parts
  that build+test off-device with confidence; M3–M6 (the 4-tab part-page band) are the device-owed UI remainder. **M1 (model
  tidy, `2aa17ed`):** the LIVE bank is now SIXTEEN in TWO species — 8 SLIDER (0–7) + 8 TOGGLE (8–15); the 8 TIMELINE macros
  (16–23) are RETIRED (§K3). Decode-safe by construction: a doc that stored the old 24-bank still DECODES whole (the Codable
  `macros` array is untouched → encode round-trips), but only the first 16 RESOLVE (`PluginState.macroBankCount`), so a retired
  timeline's offset simply stops applying — no crash, no factory-reset; byte-identical for any doc that used 0–15. `SnapshotBox.
  macroValues` 24→16; the AU setter guards narrowed `0..<24`→`0..<macroBankCount` (REQUIRED — they do `d.macros = d.macrosResolved`
  (now 16) then index, so a 24-guard would trap). **M2 (the per-cell value store, `f157ef8`) — the ONLY real engine change:**
  `MacroCellValue { col·row·macro·value }` + `PluginState.macroCellValues` (sparse, additive-Optional). Today a macro has ONE
  global value; PUNCH/SPAN need the DRIVING value to vary per cell. The builder folds `override[macro] ?? global` per cell —
  NO SnapCell field, NO render change (macros already bake into `sc.procs` at BUILD time → the fold is builder-side; the render
  still reads only the baked box, invariant 1). The macro's TARGETS stay shared; only the value is per-cell. Byte-identical when
  the store is empty/nil; persistence FREE (the field is on PluginState → fullState). **+6 tests** (M1: bank-is-16-two-species,
  short/over-long pad-truncate, the 24-doc decode-safe retirement, builder mirrors 16; M2: per-cell override shifts one cell not
  its neighbour, empty-store byte-identity, round-trip + old-doc-nil). **NEXT: M3–M6 — the 4-tab band (BIND · PLAY · PUNCH ·
  SPAN) as the bottom HALF of the PART grid (interior −50% height; ferry/▲▼/STOP unchanged), PART-PAGE-ONLY. Device-owed UI over
  the proven M1/M2 fold — held for Paul's device eye (band chrome / tab collapse / STOP placement have real interpretation room).**
- **▶ CHORDS — the diatonic-progression stage, FEATURE-COMPLETE (2026-09-01, on `main`, `64ed992`+`df5289c`+`2fd8d98`; iOS
  builds, macOS 995 green incl. fuzz; DEVICE ear owed). Paul ratified all three modes; built C1→C5. A new HARMONY set-shaper
  `ProcessorType.chords` — a held note TRIGGERS the diatonic chord for the current DEGREE, DERIVED from a stage-declared KEY
  by RANK ARITHMETIC (degree n = pool-steps {n,n+2,n+4} — stacked thirds, quality falls out of the key; NO chord stored, so
  one stencil plays in any key). Wired like harmonize/split/avoid — `applyStage` (composeChainSet folds it UPSTREAM →
  `[CHORDS→ARP/STRUM/DRONE]` all play the progression) + `emitColumnHolds` (lone/tail hold). NOT a driver. **MODES:** PATTERN
  (the authored 8-step degree matrix — empty column CARRIES, quality-aware Roman headers) · FOLLOW (the played note NAMES the
  degree via `scaleDegreeOf`, off-scale snaps) · WALK (`chordsWalkDegreeAt` — a seeded gravity walk chained from the tonic,
  recomputed per window → replay-exact, no accumulated RNG). **VOICING** TRIAD|7TH|ADD9 · **SPREAD** CLOSE|OPEN · `diatonicChord`
  + `voiceLeadTowardPrevious` (nearest inversion) + `walkNextDegree` (7×7 gravity table) + `degreeLabel` — all pure/Foundation,
  concept-derived tests. **C5 lone/tail fix:** a bare `[CHORDS]` was silent (only sang via a downstream, the AVOID hold-path
  gap in CHORDS form); now `isHoldTailChain` recognises a `.chords` tail + `emitColumnHolds` composes the stage INTO
  chainScratch (upto-inclusive) and emits it as a legato-adoptable hold (existing adopt/close machinery → no stuck notes;
  forceColumnHold sustains via soloSustain). Full surface: CellMode `.chords` + emblem `pianokeys` + typeParams editor (MODE ·
  KEY root+scale · quality-aware degree matrix via stateMatrixRadio · VOICING · SPREAD) + storefront card (HARMONY) + fuzz
  roster/randomizer. **+11 tests** (4 Derivations pure-core + 7 Router: PATTERN in-key/transpose/V · FOLLOW G→V/C→I · WALK
  seeded/valid/replay-exact · lone sounds V · VOICING 7TH reaches the engine · [CHORDS→ARP] pitch-class-clean). **DEVICE-FIX
  PASS (2026-09-01, `a038a68`; Paul: "doesn't respond to midi; one chord on play"):** NOT a stuck-note bug — the storefront
  seeded PATTERN, which IGNORES the played pitch (authored degree lane) and under the SELECT audition's frozen column shows
  only degree[0] = "no response, one chord." TWO fixes: ① DEFAULT → FOLLOW (the responsive mode: play a note → its diatonic
  chord; PATTERN/WALK picked in the editor); ② C2b#1 DONE — CHORDS reads the KEY from a receiver door in SCALE mode
  (`receiverScaleRoot`/`Type` threaded box→Router→applyStage; −1 = not a scale door → card key, byte-identical), so it "plays
  in whatever key D declares." +3 RouterTests (FOLLOW tracks a changing held note under audition; a filled row plays a real
  progression; a CHORDS on an E-major SCALE door sounds E G# B). **THE REAL "NOTHING SOUNDS" FIX (Paul pushed back — 2nd pass,
  `0091e2b`):** the default-mode answer DODGED the bug. The SELECT/ferry audition parks the cell at col 0 of a row PINNED to
  that column (rowLane single bit) — a row that NEVER re-transitions, so `emitColumnHolds` fires exactly ONCE. A legato drone
  survives (immortal voice never closes); a NON-legato hold (CHORDS — and in fact HARMONIZE/CHANCE) strikes once, gates off at
  the column end, never re-fires → "nothing sounds / one chord." (The earlier forceColumn test used a DIFFERENT path and masked
  it.) FIX (scoped to CHORDS): ① CHORDS is now a LEGATO hold (sustains + adopts; a SWEEPING row re-strikes only when the chord
  CHANGES — same degree in consecutive columns sustains); ② a PINNED continuous row (single held column — audition / single play
  cell) RE-RECONCILES every window like forceColumnHold (reconcileOnly), so a legato CHORDS follows a LATE-armed latch + a
  changing FOLLOW note instead of freezing at window 1. +3 RouterTests (sustains on the pinned audition like a drone; FOLLOW
  picks up a note played AFTER the audition starts; sustains from a LATCHED receiver with no live keys). 1005 green, fuzz +
  per-row-lap + no-stuck all green. **GENERALIZED (Paul: [CHORDS→ARP] plays, BYPASS the arp → silence; "extend to the other
  relevant processors" — `bb59b20`):** bypassing the driver makes the tail a non-legato identity passthrough → the SAME fire-
  once bug, but the CHORDS-scoped fix missed it. Reverted the CHORDS-only legato hack; folded a new `auditionSustain` (set when a
  row is PINNED) into `soloSustain`, so a frozen-column preview (forceColumnHold OR the pinned audition) sustains EVERY hold —
  identity/harmonize/chance/split/avoid/octave/transpose/chords + a bypassed-driver tail. Byte-identical on a SWEEPING row
  (auditionSustain false unless pinned). +2 tests (1007 green): [CHORDS→bypassed arp] sustains; harmonize + chance sustain on
  the audition. **SCALE FROM a REFERENCED door (`0ab1b00`):** Paul — the card KEY picker was confusing + WALK/FOLLOW should
  reference a SCALE door (like AVOID's "listen to"). REMOVED the KEY picker; added **SCALE FROM ▸ — · A · B · C · D**
  (`chordsScaleRef`) — a receiver set to SCALE supplies root+scale while the cell's OWN input stays the TRIGGER (FOLLOW names
  the degree from the note you play; a separate door sets the key). No valid ref → C-major fallback (never keyless). Engine
  reads `receiverScaleRoot/Type[chordsScaleRef]` (supersedes the own-receiver read). Editor shows a mode-appropriate body:
  PATTERN keeps the matrix; FOLLOW/WALK get plain-language tells + WALK a RE-ROLL. +2 tests (referenced E major → E G# B; no
  ref → C major), 1008 green. **STEPS + RATE (`0cd2b17`):** Paul — "we need steps and rate on chord." RATE (StepRate 2/1…1/8,
  default 1/1) gives the progression its OWN clock (a chord per rate-tick, not per grid column) so it steps musically AND plays
  THROUGH on the frozen/pinned audition (the beat advances even when the column is pinned); STEPS (1…16, default 8) is the
  PATTERN matrix length (loops every N; the editor matrix is now variable-width). PATTERN+WALK step on RATE; FOLLOW is
  continuous. KEY FIX: the rate step reads the RAW beat (mNow), not the grid-quantized colStart the hold path passes (else it
  aliases to one frozen degree). +3 tests (progression steps; STEPS=2 loops the first two degrees; regressions hold), fuzz
  randomizes mode/rate/steps/scaleRef, 1010 green. **C2b REMAINING (flagged, not blockers):** INVERT-toward-previous (pure `voiceLeadTowardPrevious`
  exists+tested; wiring needs per-cell last-chord memory) · WINDOW ROW|BAR (span family) · the PATTERN degree-matrix headers
  show major-quality Roman numerals (POSITION reference; the real quality follows the SCALE-FROM door at play — threading that
  door's scale into the editor for live-accurate headers is a device-owed nicety).**
- **▶ TIDE & EMBER COLOUR SCHEME + play-grid legibility + SELECT chequer/feedback + HOUSEKEEPING (2026-09-01, on `main`,
  `6537159`…`e32925b`; iOS builds, macOS 978 green; DEVICE eye/ear owed). Paul picked the **Tide & Ember** scheme with the
  **Even Dusk** play palette from a colour-study artifact. **PALETTE (`6537159`, GridUI + BuildPage tokens):** direction as
  temperature — `receiverHues`/`receiverGreys` → COOL (IN), `emitterHexes` → WARM red·orange·gold·magenta (OUT), `playHexes`
  → EVEN DUSK (8 evenly-spread muted hues, fixing the old dusk set that collapsed together), `roomsAmber`/`roomsIndigo` →
  warm-ember/cool-tide signatures (roomsIndigo keeps its NAME but now holds a sea-blue — also flows to the STOP + ▲▼ ferry
  buttons), `roomsRainbowHues` → warm→cool span. The 16 machine `colourHexes` were LEFT a full vivid spectrum (a warm-only
  set would lose machine differentiability; PART character comes via the amber door). SELECT nav stays the rainbow (no muted-
  nav pick made). **UI:** SELECT-grid cells get a tasteful two-tone CHEQUER (`fab29ac`); the ▲▼ ferry-row cursor is ONE solid
  indigo block, not two buttons (`711cfd7`); the SELECT machine grey ALTERNATES between two bright shades on each new pick
  (`cdf1345` — `buildSelectGrey`/`buildSelectGreyAlt`, flips on `buildGridSelSel` change) so a new selection visibly shifts
  even though the audition is always the transient `gsAud`; STOP + ▲▼ restyled to the play-nav indigo (`898e8c3`). **HOUSEKEEPING
  (`e32925b`, 3 read-only survey agents, every finding re-verified):** ① the CC120/123 forward path COMPLETED the 2026-08-31
  HOLD fix — an incoming all-notes-off was still FORWARDED to the synth while a HOLD/LATCH is armed, silencing the held chord
  DOWNSTREAM though it survived internally; now suppressed while `effectiveLatchMask != 0` (device-owed, Kernel isn't unit-
  tested). ② dead-code sweep, net −149 lines (7 dead @State + `BuildGridMode` + `roomsPlayHeader` + `spanLadderFreeField` +
  the old editor tab-overwrite cluster `buildColourTab`→`buildTabNowPlaying`/`buildPulseOverlay`/`buildEditorOverwriteRow` +
  AU orphans `setCellsChain`/`forkCellToColour`/`setRow8OnRadioSetup`/`punchCC`/`sendProgramChange`/`editColour`/`uiExcludeDoor`).
  ③ +1 test (`DoorRing.loadLoopParallel` round-trips == `loadLoop` + ragged-array clamp). ④ fixed the last stale `column*8+row`
  comment (`Router.topCell`). Bug-hunt cleared all this session's changes (CC123-internal, focus-note feed, ferry duplicate).**

- **Older entries (2026-09-01 and before) archived to `Docs/status-log-archive.md`** — moved out
  2026-09-26 to keep this file inside the context char limit; nothing was deleted, just relocated.
  Read that file for build history predating the entries above; `Docs/pending-tasks.md` stays the
  forward checklist.

## Style
- Swift, no external deps beyond apple/swift-atomics (SPM, already in project.yml).
- Comments cite spec sections (e.g. `// §3.2: stepped fields quantize`). Keep doing this —
  the spec is the contract, and drift between code and spec is the project's main risk.

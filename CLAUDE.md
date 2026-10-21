# MidiSpark / Euclideous → FourStep — project briefing

AUv3 MIDI processor (`aumi`) for iPadOS, built around a shared engine. Two products live on it:
**8x8 State** (the full 8×8 grid: processors/rooms/ferries/macros/scenes — ON HOLD, see Scope
below) and **Euclideous** (a 4-lane Euclidean-rhythm processor, one reserved engine row of the
same grid) — which is now the active focus, being extracted into **FourStep**: a standalone AUv3
*and* a standalone app, as a second Xcode target sharing the engine sources. Primary host today:
AUM; FourStep adds a second, self-hosting target (see `Docs/standalone-plan.md`).

## Scope — read this before picking up any task

**Euclideous/FourStep is the active goal. 8x8 State's wider grid/rooms/ferries/macros/scenes work
is ON HOLD** — don't pick up new feature work there unless Paul explicitly asks for it. The two
share ONE engine (Router/Kernel/Derivations/Models/Snapshot*/Emission) — touching that code for a
Euclideous need is normal and expected; building new 8×8-grid-workbench UI is not, right now.

- **Euclideous-first docs** (read these for anything Euclideous/FourStep): `Docs/what-is-
  fourstep.md` (the pitch, four-lane model, vocabulary, v1 scope + architecture diagram) ·
  `Docs/SPEC-euclideous-rework.md` + `Docs/euclideous-rework-mockup-2026-10-07.html` (the current
  UI/behaviour spec) · `Docs/standalone-plan.md` (NOW ACTIVE — the FourStep target architecture +
  the three seam rules, load-bearing, not aspirational) · `Docs/standalone-app-analysis.md` ·
  `Docs/euclideous-status-log.md` (the full ferry-by-ferry history) ·
  `Docs/euclideous-device-verification-debt.md` (the running open-device-check list — append one
  line here per ferry, don't let it only live buried in the log) ·
  `Docs/claude-playbook.md` (how to work effectively on this codebase — the loop, the recurring
  bug class, the testing split, named plainly) · `Docs/fourstep-design-tokens.md` (the real
  palette/lane-accents/spacing, each tagged \[verified] from source or \[consolidated] from the
  log — read before picking a colour or a gap value for new UI). Each of these three has a
  browsable, nicer-looking twin published as a Claude artifact (linked from inside the file) —
  the `Docs/` file is the one Claude actually reads; the artifact is for handing to a person.
- **ON HOLD (8x8 State's own UI/feature docs — don't start new work from these without asking)**:
  `Docs/factory-scenes.md` (16 curriculum scenes) · `Docs/ui-port-guide.md` (mockup→SwiftUI port
  plan for the 8×8 workbench) · `Docs/migration-tree-routing.md` (historical) · the routing-model/
  rooms sections of `midispark-spec-v2.8.md` + `v3.0-delta.md` · the `midispark-preview-v60/v61.html`
  mockups · `Docs/pending-tasks.md`'s 8×8-State-only items (its Euclideous items are still live).
- **Still-live shared-engine reference, not on hold** — these describe the engine both products
  ride on: `Docs/router-design.md` (pools/voice/PHASE formulas), the architecture invariants and
  build gotchas below, and `Docs/test-procedures.md`'s underlying device-test discipline (its
  specific T1–T17 canned sessions are 8×8-State scope; its method isn't).
- **Status log rule, going forward:** don't append ferry history inline in THIS file again — it's
  how the file grew to 8,800+ lines once already. Append to `Docs/euclideous-status-log.md`'s tail
  (same append-only convention, just relocated); update the condensed "Current Euclideous state"
  section below only when the real architecture changes, not on every fix.

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
3. **On completion, integrate into `main` with `sh Scripts/land-on-main.sh`** (from your own worktree, on the feature branch, once the build is green). It does the REMOTE
   fast-forward (`git push origin <feature>:main` — needs no local `main` checkout, so the worktrees never fight over who holds `main`) AND the catch-up that a bare push does NOT do:
   a push moves only `origin/main`, **not the local `main` branch and not the build directories Paul builds from** (`/Users/paulbarrett/src/midi_spark` and `-b`) — "landed on main" has
   repeatedly looked like "my changes aren't there" because of that (2026-09-26, 09-30, 10-01, 10-20). The script therefore also fast-forwards the local `main` ref (`git fetch origin main:main`,
   ff-only) and each build dir that is clean and strictly behind (`git -C <dir> merge --ff-only origin/main`), reports any dir it must NOT touch (uncommitted work, ahead/diverged), and prints
   what it found — **quote that output in your reply**. If it exits "origin/main has advanced" (another instance landed first), `git rebase origin/main`, rebuild to confirm it still compiles,
   rerun. **Do not run the bare push and stop; `git fetch` alone does not refresh local `main`.** (Manual equivalent, only if the script is unusable: push, `git fetch origin main:main`, then
   `git -C <build dir> merge --ff-only origin/main` per build dir. Don't leave `main` checked out in your worktree — it blocks the others.)
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

## Vocabulary — two layers: the shared engine, then each product's own slice

**8x8 State's full vocabulary** (spec §1 — enforced, including in code comments and UI strings,
for any 8×8-State-scope work):
- **Machine** = the treatment (type + params + its chain). ID-based: the 16 canonical
  palette defaults PLUS unlimited ephemeral machines (`buildMachineReg` registry + `machineHueOverride`
  + GC). The old fixed-16 cap is gone. (A/B states + morph are decode-only zombies — render-dead.) Never "preset".
  (RENAMED 2026-09-09 from "Colour" — the object is a machine, not a user-picked sound colour; its display
  **hue** is *derived* from its `machineID` via `machineHue`/`machineHexes`. On-disk keys moved with the
  rename; pre-rename saved sessions factory-reset by design. Older status-log entries still say "Colour".)
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
  identity and saved AUM sessions key on them). **FourStep will need the equivalent set
  of identity decisions once its target exists — see `Docs/standalone-plan.md`'s
  checklist; don't assume any of MidiSpark's codes carry over.**

**Euclideous's own vocabulary** (narrower, deliberately NOT the routing-graph language above —
Euclideous has no receiver/door graph, no cables beyond a flat A–D toggle, no chain-of-processors):
- **Lane** = one of 4 `EuclidLine` instances (`PluginState.euclideousLines`), each with its own
  RHYTHM (K-of-N pattern, offset/tilt/gate/velocity, direction, two restart chains — RHYTHM in
  bars, MELODY in passes), RIFF (a walk over
  the shared rank matrix), NOTES (an additive lit-note layer), and MASK (an 11-mode per-lane
  modifier) tab.
- **Riff** = a stencil of *ranks* (not pitches) over an 8-step grid — 4 independently stored, one
  editable at a time via the RIFFS tab, shared by every lane that walks it. "Riff capture" records
  a played line as ranks against the chord held at the moment of capture, so it replays correctly
  against any later chord.
- **Mask** (per-lane) = a second K-of-N pattern gating a lane's own hits (mute/pause/ratchet/
  repeat/chord-stab/octave-shift/mirror/leap/climb/accent/swell), distinct from the standalone
  `EUCLID MASK` processor type that exists elsewhere in the 8×8 grid's processor roster.
- **Sequencer panel** = the MIX / LANES / FX tabs of the bottom-right panel (RIFFS is hidden; FX shows in both orientations since the PAGE LAYOUT ferry). LANES is four lane blocks of
  16 cells, mute-only (restart-chains ferry, 2026-10-19 — the old MUTE/RESTART sub-tabs and their RESTART view are gone;
  restarts are set on each lane's own RHYTHM tab instead, §6 below), each lane's own MUTE grid on its own cell size
  (STEP/4STP/PASS/2PASS), with read-only rhythm/melody restart marks drawn from that lane's resolved chains.
- **FX** = the sequencer panel's third tab: six fixed page-level rows (RATCH, GATE, TIE, VEL, NOTE, CC) over the riff's eight columns, each with its
  own lane set; a cell holds a value or nothing and acts only on a hit that plays the riff, through the column it reads, never on a written rest.
- **Emitters A–D** here are a flat per-lane output toggle (`MAIN OUT`), not the full 8×8-State
  bus/cable/channel-stamp model above.

## Architecture invariants (violating these = bug, regardless of tests passing)
These bind BOTH products — Euclideous's row is composed, rendered, and emitted through exactly
the same pipeline as any other row; it is not a special-cased render path.
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
- **FourStep target — not yet created; none of the below is scaffolded.** See
  `Docs/standalone-plan.md`'s checklist for the open decisions (bundle ID, `aumi` subtype/
  manufacturer code, app identity, which engine sources the new targets share, whether
  `BuildPage.swift`/`RoomsPage.swift`/`GridUI.swift`/`RackMatrix.swift` are excluded from
  the new AU target). When it IS created, this section needs its own compile/test commands
  (mirroring the two above, with `FourStep`/`FourStepAU` schemes) — don't assume the
  existing commands cover it.

## Current Euclideous state (hand-maintained — update when the real architecture changes,
## not on every fix; full history is `Docs/euclideous-status-log.md`)

- **Entry point.** `EuclideousPage.swift` — a full-screen SwiftUI overlay, opened via the
  workbench header icon, or automatically on a fresh plugin instance (cog toggle
  `launchIntoEuclideous`, default on). Closing it falls back to the normal 8×8 workbench.
- **Engine.** One reserved row, `Snap.euclideousRow`, composed every publish by
  `composeSceneMeta` when `PluginState.euclideousEnabled` — a regular authored row through the
  ordinary Router/Kernel/SnapshotBox pipeline, not a separate render path.
- **Four lanes** (`EuclidLine` × 4, `PluginState.euclideousLines`), each with RHYTHM (K-of-N
  pattern; HITS (vertical fader) / STEPS (a +/− stepper opening a 15-length picker, each cell
  previewing this lane's own rhythm) / OFFSET / TILT (full-width horizontal sliders, TILT with
  EARLY/LATE end labels) — GATE/VELOCITY are edited on MIX instead, restart-chains ferry 2026-10-19;
  FWD/BKW/PING-PONG direction; two restart CHAINS — `restartRhythmBars`/`restartMelodyPasses`
  (`[UInt8]?`, FREE or up to four links of 1/2/3/4/6/8, set via the RHYTHM tab's own restart tiles +
  editor) are now the ONE live restart model, replacing the LANES GRID ferry's 16-cell
  `restartRhythmMask16`/`restartMelodyMask16`/`restartUnit` masks (still decodable, no longer written;
  read ONLY by the FX tab's own preserved closed-form pass index, out of the restart-chains ferry's
  scope) and `resetSteps`/`restartMask` before them (decode-only); migration
  (`migrateRestartChains`) runs on `AudioUnitViewController`'s main-thread resync loop and auto-pins
  on load (never on the render thread, which sees a safe FREE default until then); `hitsRequested`/
  `offsetRequested` remember what HITS/OFFSET were last actually asked for, so shrinking STEPS and
  growing it back restores the exact pattern left behind); a 16-cell MUTE grid (`muteCells16`/
  `muteUnit`, LANES GRID ferry 2026-10-18, UNCHANGED by the restart-chains ferry — mute stays on the
  LANES tab), RIFF (a walk — FWD/REV/PENDULUM/PING-PONG — over the
  shared 8-step rank matrix; DRUNK/RANDOM were removed from this walk 2026-10-13 and now coerce to
  FWD; FREE, INVERT, ON-REST SKIP/TIE/REPEAT (FILL left ON REST in the NOTES TAB ferry 2026-10-19 — RESTS does what it was for; REPEAT added RIFF WALK ferry 2026-10-19: a hit on
  a rest plays the nearest earlier non-rest column's note again, found by `euclideousRiffRepeatLookback`),
  STRIDE/LENGTH/ADVANCE EVERY 1-4/TRANSPOSE (ADVANCE EVERY added the same ferry — the walk moves once
  every N hits/steps, via `euclideousRiffWalkStep`/`Column`, the ONE ordinal→column pair every site
  — the Router, the TIE lookahead, the riff-grid marker mirror, the FX tab's pass index, REPEAT, the
  WALK strip — now calls; EVERY 1 is byte-identical to before except ties the lookahead's now-wider
  P×EVERY bound catches), ±2 octave — **the RIFF tab's own OCT row is gone (same ferry); MIX's riff
  OCT stepper is the only riffOctave control now** —, riff
  capture — LOCK is RETIRED, restart-chains ferry 2026-10-19: a melody chain of exactly `[1]` does
  what it did, §4.7; `riffLock` stays decodable, read only by migration), NOTES (an additive lit-note layer independent of the riff — it reads ON only while its switch is on AND a note is selected, `euclideousNotesLayerIsOn`; **rebuilt by the NOTES TAB ferry
  2026-10-19**: ONE stored lit ORDER (`notesLitOrder`, `EuclideousLitOrder` — positions 0–7 = ranks 1–8, 8 = TOP 2, 9 = TOP; `litNotes`/`topLit`/`top2Lit` are decodable read-only projections written
  from it), WHEN (`notesWhen`: PLAYS/RESTS — a *rest hit* is a hit whose WRITTEN riff column is a rest, riff on or off), CHANCE (`notesChance` 25/50/75/100, `splitmix64Mix` replay-exact),
  PLAY AS (`notesPlayAs`: CHORD/ROLL/RUN/CYCLE/BOUNCE/SPLIT/BUILD) and RECEIVED (`notesReceivedOnly`); the per-note octave shifts and NOTES VEL are gone from the tab and **no longer sound/are no
  longer set** — `noteOctShifts`/`notesVelOffset` stay decodable and are encoded as decoded; MIX's notes pad + notes OCT stepper are the only velocity/gate/octave controls. TOP 2 keeps its PAIR
  (second-highest AND highest). **ONE derivation:** `euclideousNotes*` in Derivations.swift (WhenChooses, ChanceRoll/Allows, HitOrdinal, CountBefore — k in 1024-hit blocks —, PlayList, WayPick,
  RollSpacingBeats, RunSlotBeats, KeyFlash, Pips, GreyFooters, and `euclideousNotesTabLayout`); the Router and every display call them. A rest no longer ends a hit by itself: the riff layer sets
  `restEnd` (SKIP-like / tied) and the notes layer may strike on it; only when it plays nothing does the old SKIP / tied-rest exit run. TIE answers per layer
  (`euclideousChainTieExtensions` → riff, notes; the notes carry on only up to the first tied rest the notes themselves strike on), and `euclideousHeldRiffPitch` stops the notes re-striking the held riff
  pitch. ROLL/RUN later notes are deferred strikes on the shared echo ring (or struck directly when their sample is still inside the current window). The 5.6 migration (decoder): `notesWhen` nil →
  riff off ⇒ both; riff on ⇒ SKIP/TIE PLAYS only, FILL/REPEAT both — sound-preserving; **FILL decodes as SKIP**), and MASK (11 modes — MUTE/PAUSE/RATCHET/
  REPEAT/CHORD/OCT/MIRROR/LEAP/CLIMB/ACCENT/SWELL — gated by CHANCE).
- **Sequencer panel** (replaced an earlier "NOTE VIEW" telemetry panel entirely): tabs are MIX (the default —
  eight XY pads, gate × velocity, + a 24pt OCT stepper per layer (shrunk from 28pt, restart-chains ferry
  2026-10-19) and, new in that same ferry, a 20pt OUT A–D row under each lane's pad pair (`mixOutRow`,
  moved here from the RHYTHM tab's old OUT circles — reuses `euclideousLaneOutChipStyle` verbatim as a
  rounded rect): each lane's RIFF and NOTES; RIFF = the lane's GATE/VEL,
  NOTES = its own `notesGate`/`notesVelocity`, which PART from GATE/VEL at the first edit), then LANES
  (mute-only since the restart-chains ferry, 2026-10-19 — `LanesPanelPainter.swift`: no sub-tabs, just a
  static hint line; four 16-cell lane blocks each with a RATE box that edits that lane's MUTE unit, a roll
  of the lane's hits behind the cells, a playhead per lane, and read-only rhythm/melody restart marks now
  drawn from each lane's resolved CHAINS (`euclideousChainRhythmMarkBeats`/`ChainMelodyMarkBeats`) instead
  of the retired masks); RIFFS is hidden. The tab row is tabs only. Every sounding pitch in a
  Euclideous hit carries its OWN gate. A lane's RIFF/NOTES gate tops out at 99% (`euclideousLaneGateMax`; 2026-10-19 — the XY pad no longer offers LEGATO, and a stored 100% loads as 99%);
  the engine's per-pitch legato is unchanged but nothing the UI or a document can set reaches it any more (the FX tab's GATE row stopped at 95 on 2026-10-20 — `EuclideousFX.gateMax`; a stored 100 loads as 95).
- **PULSE (ferry 2026-10-20).** Every strike on the page is ONE velocity-scaled envelope (`euclideousPulse*` in Derivations.swift: vis = 0.2 + 0.8·(v/127)^1.3; burst b τ0.05 · flash f τ0.16 · key k τ0.08 · tail a τ0.35, × the PULSE scale P = 0 / 0.6 / 1) fed by `EuclideousPulseFeed` — a bounded per-lane ring of strikes
  (onset beat, wall-clock `onsetAt` stamped ONCE from the dejittered beat anchor when the NOTE VIEW event arrives, riff and notes-layer velocities, riff row/column) held on `LiveTelemetry` and filled from the existing 30 Hz NOTE VIEW poll (nothing new is polled; the feed adds no body re-run, though the older `euclideousStrikeEvent` @State still re-evaluates the page per strike batch). Each strike's comet tile is resolved once per lane geometry (`resolveTiles`). The event carries `vels`
  (the velocity each pitch actually played with — added by this ferry, no sound change). Colour is the lane's identity and never shows velocity. **Gaps:** a hit on a riff REST under SKIP/TIE (REPEAT strikes; an FX-tied hit is not a rest) draws as a gap on the lane strip (`euclideousPulseIsGap`) and makes no strike anywhere. **Lane strip** (below; the comet's flare core, dot swell, tail and level mark were removed 2026-10-21, and with them `euclideousPulseStrikeVelocity` — the BUILD-page editor passes no feed and keeps the old geometric flare): a riff strike dips and glows its chip, a notes strike glows its key. **Riff panel** (arrow 1 + 0.24f scale / 12f glow, rails, note-cell tint, lit note name), **MIX** (one overlay: ripple, fill flash, puck swell, OUT-button glow outside the button), **header rings** (stroke 2.5 + 2.5f, wash, glow,
  white letter), and the FX firing flash + NOTES key glow all read the same f. The old step-based `euclideousRingFlare`/`euclideousArrowFlare` are deleted. PULSE level = `@AppStorage("midispark.pulseLevel")` on `DiagView` (0 OFF · 1 SUBTLE · 2 FULL), a row on the settings sheet's CLOCK tab; Reduce Motion = the SwiftUI `accessibilityReduceMotion` environment. Each surface keeps its own 60 fps `TimelineView` on a shared
  time base and stays un-paused for 1.5 s after a stop (`pulseLive`).
- **LANE STRIP (ferry 2026-10-21).** The lane card's 44 pt header strip is two rows on the same step columns (`euclidGroupedBoxGeometry`, now in Derivations.swift): a 27 pt RIFF TRACK (a dark cell per hit — #28292D, the riff grid's empty cell; a dashed #1A1C21 per rhythm rest; a lane-colour inner ring on a GAP) with a CHIP per hit that reads a riff note (9 tall, top `(8 − r) × 18 ÷ 7`, the WRITTEN rank — the arrow's rule — labelled with the riff column, #DCDCDD = the riff grid's note cell; REPEAT = a hollow dashed chip at the repeated rank; the lane's CURRENT chip = the chip of the hit its riff arrow shows, drawn with the arrow's own gradient, following TIE's stay-put; grey chips with the riff off and WHEN one-sided) and a PLAYHEAD band (lane @ 14% + a 2 pt leading edge, gliding column to column over group gaps, sliding off the end of an FWD/BKW pass) over a 14 pt KEY ROW (a key per hit in the NOTES tab's key look; lit with the lane bar / a CHANCE ring and the way's note name when WHEN/CHANCE/the way play there — "G3+2" for several). ALL of it is pure functions in Derivations.swift (`euclideousStrip*`: layout, `euclideousStripHits`, `euclideousStripCurrentStep`, `euclideousStripPlayhead`, strikes, looks, VoiceOver) built from the footers' (`euclideousFooterPass`, `euclideousFooterStates`), the arrow's (`euclideousWalkTagPlan`, `euclideousLaneArrowState`) and the notes' functions; `LaneStripPainter.swift` only paints them; `EuclideousPage.laneStripPlan` assembles the per-body plan and `EuclidCometBar` draws it when handed one (the BUILD-page editor keeps its old comet). The footers' prediction now honours ADVANCE EVERY (it did not before). A SHADOW lane shows no chips and the partner band over its keys. One VoiceOver element per strip. Strikes: chip = riff strike (dip 2k, glow 10f), key = notes strike (ring 1.5 @ f, glow 45% f, label #F2F4F7 while f > 0.25); a muted lane draws at 42% with no strikes. Sizes/looks/60 fps cost are device-owed.
- **FX tab (2026-10-18).** Third tab of the sequencer panel (both orientations since the PAGE LAYOUT ferry, 2026-10-19 — in portrait the panel sits beside the riff
  panel at the same width, so its columns match the riff grid's; its six rows now SHARE the panel's height, `euclideousFXRowH`). ONE document field `PluginState.euclideousFX` (`EuclideousFX`, additive-Optional, clamping Codable) →
  `SnapParams.euclideousFX` → Router. **ONE decision function** `euclideousFXApply` (Derivations.swift) decides what the rows do to a hit; the Router, the TIE
  lookahead, the LANES roll and the flash all call it (VoiceOver reads the cells' values directly — there is no per-hit decision for it to make) — change the rule THERE. The NOTE pass index is `euclideousFXPassIndex` (a pure function of
  the beat; LOCK in closed form). RATCH reuses the mask RATCHET's deferred-strike engine (`pushEchoTail`) with n exact; CC goes through `emitModCC(force:)`
  with the notes' own channel stamp. The tab's columns come from `euclideousRiffCellW` — the riff grid's own function — and every UI number is a pure
  `euclideousFX*` function; `FXPanelPainter.swift` only paints them. A moved NOTE rank folds through `riffResolveExtended` (rank 0 is never a rest).
- **ONE per-tick core (restart chains, 2026-10-19 — supersedes the LANES GRID ferry's own masked core).**
  `euclideousLaneChainTick`/`euclideousLaneChainPhase` (Derivations.swift) decide, for a lane tick, the
  pattern phase from the RHYTHM chain's origin and the riff ordinal (`advOrd`) counted from the MELODY
  chain's origin on the lane's real hit schedule (`euclideousChainHitsBefore`, a bounded closed form spanning
  rhythm restarts). The Router, the TIE lookahead (`euclideousChainTieExtensionBeats`), the next-hit gap
  (`euclideousNextChainHitGapBeats`), the walk-tag mirror, the LANES roll's marks and the footer baseline
  (`euclideousLapStartOrdinal`, now chain-based) all call it — change the arithmetic THERE, nowhere else. No
  `locked:` parameter anywhere in this generation: a melody chain of exactly `[1]` subsumes old LOCK with no
  special-casing. Mute is UNCHANGED — still `euclideousLaneAudible` at the hit's own beat (per hit, not per
  window), still reads `muteCells16`/`muteUnit`, nothing to do with chains. The OLD masked core
  (`euclideousLaneTick`/`euclideousLanePhase`, `EuclideousLaneRestartGrid`) is kept, byte-for-byte untouched,
  ONLY for the FX tab's own closed-form pass index (`euclideousFXLockPass`/`FXPassIndex`) — the two models
  now coexist permanently, by design, each with its own test suite; never modify one expecting it to affect
  the other. A rhythm restart on a muted cell still takes effect; a muted hit still advances the walk.
  Render-thread care: nothing in either core may allocate; `migrateRestartChains` (which does allocate) runs
  only on `AudioUnitViewController`'s main-thread resync loop, never from `Router`.
- **Source.** One page-level selector — MIDI IN / CHORDS (a self-contained degree-matrix+rate
  chord generator, no 8×8-grid receiver dependency) / KEY (a scale pool). No per-lane source, no
  dependency on the wider receiver/door graph.
- **Header (Fourfold, 2026-10-15).** Four groups: BRAND (mark, FOURFOLD, undo/redo — ↶/↷ bounded 50-deep, scoped to
  Euclideous's own fields only) · OUTPUTS (four output RINGS = MAIN OUT A–D, 75% scale since 2026-10-20 —
  `EuclideousHeaderMetrics.outputRingScale`, rendered at natural size then `.scaleEffect`-shrunk, same technique as
  the Settings Sheet's own 0.8× mini rings, so the hardcoded radius-17 Canvas circle never clips: each quarter
  lights in the colour of a lane routed to it, tap pulses those lanes, hold traces them, a quarter flares on a real
  strike) · NOTES (MIDI IN · CHORDS · KEY control + a key pill that opens the key pop-up + HOLD/LATCH, added
  2026-10-20: two mutually-exclusive chips — a behavioural port of the 8x8-State door graph's `DoorMode.hold`/
  `.latch` onto Euclideous's own page-level MIDI IN pool, since Euclideous has no receiver/door graph to reuse the
  original mechanism from; HOLD mirrors live input and sustains the last chord once every key releases, replacing
  it the moment a new one arrives; LATCH toggles each newly-risen note in/out of an accumulated pool and ignores
  note-off entirely; both reuse `NotePool.captureFiltered`/`latchAddStep` (the door LATCH/HOLD's own primitives,
  Derivations.swift) against a NEW Router-owned persistent pool (`euclideousHoldLatchPool`), gated to `.midi`
  source only and reset on a mode switch or transport restart) · UTILITIES (presets, settings — a gear, not ×; see
  below). There is NO ON chip: the page always runs (`euclideousEnabledResolved` is always true; the stored field
  is decode-only). The A/B/C fit ladder, group widths and positions all come from ONE pure `euclideousHeaderLayout`
  (Derivations.swift) that the body layouts also read — change header metrics there, not in the views. **Ring TARGET repointed (restart-chains ferry, 2026-10-19):** a tap/hold's ring used to go around
  "this lane's own OUT circle, or its RHYTHM tab chip" — both are gone (OUT moved to MIX, §9; RHYTHM never had a
  ring of its own again after that). `euclideousOutputRingTargets` (replacing the ring half of
  `euclideousOutputCues`, which is now dim-only) decides, page-wide not per-lane-card: one ring per routed lane's
  own MIX OUT button when the sequencer panel is showing MIX, else ONE ring around the MIX tab chip (drawn once
  however many lanes are routed). Lane-card TRACE dimming while held is unchanged.
- **Settings sheet (Fourfold, 2026-10-15).** The gear (replacing ×) opens a 3-tab sheet overlay —
  MIDI IN (LISTEN ON channel mask, ALL-NOTES-OFF ignore/obey) · MAIN OUT (per-output A–D channel
  stepper, ALL NOTES OFF) · CLOCK (KEEP PLAYING/STOP when the host transport stops) — presented the
  same non-modal way as the key pop-up (engine never stops), one overlay at a time with the other
  page pop-ups. ×'s old "back to the 8×8 workbench" job moved to the sheet footer's WORKBENCH link
  (`EuclideousSettingsSheet.swift`). New document fields: `euclideousMidiInChannelMask` (16-bit, nil/0
  ⇒ every channel — SnapshotBuilder feeds it into the Euclideous row's existing `globalSrcChanMask`,
  which all 4 lanes AND the riff already shared one pool through) and `euclideousHostStopBehavior`
  (nil ⇒ KEEP PLAYING, today's free-run-while-stopped default). MAIN OUT's per-output channel reuses
  the existing, already-shared `busChannels` stamp (1-based; Router's `emitArtic` converts to the
  0-based wire nibble at emission — the SAME path Euclideous's own strikes already went through).
  ALL NOTES OFF is a one-shot render-thread-consumed request (`Router.process`'s own
  `euclideousAllNotesOff` parameter), modelled on `Kernel.panic()` but scoped to only Euclideous's
  own row's sounding voices, never the whole plugin. Loading a factory OR user preset preserves all
  4 settings (captured/reapplied around the wholesale document replace); a session restore restores
  them normally.
- **Presets.** 20 Euclideous-only factory presets, reachable via a PRESETS button on the page
  itself — this REPLACED the old whole-plugin preset menu entirely (a confirmed, one-way
  decision; an old saved session loading the 8×8-State preset list will no longer find it there).
- **Layout (PAGE LAYOUT ferry 2026-10-19).** SIX EQUAL BOXES from ONE pure function: `euclideousPageLayout(size:headerKind:)` (Derivations.swift) takes the
  view's size and the header's kind (A/B/C, `euclideousHeaderKind`) and returns the four lane cards, the riff panel and the MIX | LANES | FX panel — landscape 3
  columns × 2 rows (lane 1 · lane 2 · riff / lane 3 · lane 4 · panel), portrait 2 × 3 (lane 1 · lane 2 / lane 3 · lane 4 / riff · panel) — sp16 margins, sp8 gaps,
  top edge 64 (header A) or 111 (B/C), plus the lane gutter's x (the rings centre on it) and a floor list (`euclideousPageFloors`: a box under some panel's floor is
  DRAWN at the formula's values and listed, never shrunk or left empty). `pageBody` (EuclideousPage.swift) is the only arrangement; `pageGeometry` is the one place
  that derives (container width, header layout, page layout) — body, swing popover and settings sheet all call it. Every panel lays itself out in its box from
  its own formulas (lane card `EuclideousLaneCardMetrics`, riff panel `euclideousRiffRowH`, MIX `euclideousMixGrid`, FX `euclideousFXRowH`, LANES
  `euclideousLanesLayout`); nothing measured from content sizes a box. **Do not frame the page from a screen/window/minimum**: the page shares DiagView's root ZStack
  with the 8×8 workbench, which is WIDER than a portrait view — an unframed page's GeometryReader is offered the workbench's width (the old "laid out ≈885 in an 814
  view" bug), so `AudioUnitViewController` frames the page to the root `geo` (plus its bottom safe-area inset: the page is laid out on the view's FULL height with a bottom margin of
  `max(16, inset)`, `EuclideousPageMetrics.bottomMargin`). Sizes are device-owed.
- **RIFF tab (RIFF WALK ferry 2026-10-19).** Fills the RHYTHM tab's own two zones exactly, via the
  same `patternBlockH`(80)/derived-`upperH` split (`euclideousRiffTabLayout`, ONE pure function),
  so the header/tab rows sit at the same y whichever tab is showing. Upper zone: the riff card +
  a non-interactive WALK strip (16 cells, the columns the walk reads at each walk step, rest
  dashes, EVERY pips, a live ring at the current step) + the direction row (FWD/REV/PEND/PING/INV)
  + an ADVANCE EVERY row (the EVERY 1-4 stepper + HIT/STEP). Lower zone: ON REST (SKIP/TIE/
  REPEAT, three buttons since the NOTES TAB ferry) + the values row (LEN/SHIFT/STRIDE/TRANS — SHIFT was NUDGE). **Confirmed, numeric
  discrepancy vs the ferry's own reference arithmetic**: the real formula gives row A 76pt, not
  the ferry's assumed 82pt (6pt under its own stated floor even at the reference) — built against
  the real, derived formula throughout, not hand-fitted; see the status log's own §0.2 writeup.
- **Riff-grid arrows + lane rails (RIFF PANEL ferry 2026-10-19; replaced the 2026-10-15 walk tags).** The marker is now ONE big arrow per CELL (lanes on the same note
  share it — `euclideousArrowCells`), numbered, pointing the way the walk heads (`euclideousArrowHeading`: FWD right, REV left, PEND/PING turn at the ends; still = capsule;
  opposite heads = double-headed), filled with the lane's colour or the OKLCH blend of the lanes in it (`euclideousBlendStops`), hollow dashed on a rest, 42% when the LANES
  grid mutes it, with a glow + 1.06 scale while a lane in it strikes (the per-lane strike feed `strikeEvents` through the comet bar's own `euclideousRingFlare` timing — a lane
  whose cell is routed to no enabled MAIN OUT posts no events, so it never flares). Under each grid column sits a RAIL per lane (`euclideousRailSpec`): played columns (the riff
  readout's never-play set, the same one the lane card's mini-grid dims), a 3-column trail and the current column with a heading chevron (`euclideousRailWalk`). All of it is STILL
  stateless: every frame `riffPanelOverlay` (EuclideousPage.swift) re-derives it from `euclideousWalkTagPlan` (the walk plan the tags used — polled `riffPositions`/`riffWalkState` + the
  UI beat, the pure mirror of `runEuclidLine`; TIE-on-rest stay-put and the shown hit's ordinal were added to it) — change the walk in `euclideousLaneTick`/the chain core, nowhere else.
  The mirror is `euclideousWalkTick` (a call of the one per-tick core — `Router.runEuclidLine` and the mirror cannot drift on the walk; `RouterTests.testWalkTag*` compare them against the real
  router): if you change how the walk advances (ordinal, LOCK, ADV STEP, the RHYTHM/MELODY restarts, FOLLOW, the WITH/GAPS strike filter, swing), change it THERE. WITH/GAPS silence a tick only at the
  strike decision (the ordinal still counts every raw hit), which is why the mirror has both `isHit` and `strikes`. The UI-clock-vs-audible-time offset is an accepted, unmeasured risk (Paul, 2026-10-15);
  a FOLLOW lane's step bar + strip draw the PARTNER's inherited pattern via `euclideousEffectivePattern` (one function shared with the mirror) — plain cells since the LANE STRIP ferry (its count box's dot names the partner), the
  playhead at the partner's rate × multiplier, its bar gestures editing the PARTNER (`euclideousFollowPartner` is the one definition of "following").
  `RiffArrowPainter.swift` only paints the pure specs. The old tag/thread code (`riffWalkTagOverlay`, `drawWalkTag`, `drawWalkThread`, `WalkTagPainter.swift`, `euclideousTagDrawing`)
  is kept, unused. The panel's inside is laid out by ONE pure function, `euclideousRiffPanelLayout(box:)`: 20pt riff tabs, grid from y 34, rows `(box height − 119) / 8`, four 8pt rails.
- **Recurring bug class, worth knowing before touching playhead/indicator code:** a UI
  indicator reading a DIFFERENT clock/formula than the one the engine actually uses to decide
  what sounds — hit repeatedly across RATCHET, DEST, the per-lane mask step bar, the ARP-rate
  LFO, CLOCK's glide math. The fix is always the same: share ONE pure function between the draw
  code and the engine; never let a UI widget re-derive its own version of "what step is this."
- **Test coverage split, unusually sharp here:** `Router.swift`/`Derivations.swift` (the engine
  half) are fully covered by `MidiSparkTests` — trust a passing suite. `EuclideousPage.swift`/
  `EuclidLaneUI.swift` (the whole UI) have ZERO macOS test-target reach — device verification is
  the *only* check that exists for layout, gesture feel, and legibility. See
  `Docs/euclideous-device-verification-debt.md` for what's still unconfirmed.

## Style
- Swift, no external deps beyond apple/swift-atomics (SPM, already in project.yml).
- Comments cite spec sections (e.g. `// §3.2: stepped fields quantize`). Keep doing this —
  the spec is the contract, and drift between code and spec is the project's main risk.

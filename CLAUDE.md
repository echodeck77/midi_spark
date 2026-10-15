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
  RHYTHM (K-of-N pattern, offset/tilt/gate/velocity, direction, per-lane reset), RIFF (a walk over
  the shared rank matrix), NOTES (an additive lit-note layer), and MASK (an 11-mode per-lane
  modifier) tab.
- **Riff** = a stencil of *ranks* (not pitches) over an 8-step grid — 4 independently stored, one
  editable at a time via the RIFFS tab, shared by every lane that walks it. "Riff capture" records
  a played line as ranks against the chord held at the moment of capture, so it replays correctly
  against any later chord.
- **Mask** (per-lane) = a second K-of-N pattern gating a lane's own hits (mute/pause/ratchet/
  repeat/chord-stab/octave-shift/mirror/leap/climb/accent/swell), distinct from the standalone
  `EUCLID MASK` processor type that exists elsewhere in the 8×8 grid's processor roster.
- **Sequencer panel** = the LANES/RIFFS two-tab step grid controlling which lane sounds, and which
  riff plays, at each step of its own independent step-sequence (own ON/RATE/LEN).
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
  pattern, HITS/STEPS/OFFSET/TILT/GATE/VELOCITY sliders, FWD/BKW/PING-PONG direction, a per-lane
  RESET — an 8-bit restart MASK, 2026-10-15 ferry, one bit per LANES step, editable by holding the
  box and tapping steps, or via an EVERY-1/2/4/8/OFF presets popover — that re-anchors to the LANES
  sequencer's own lap boundary rather than a raw bar count; `EuclidLine.restartMaskResolved`, engine
  formula `euclideousMaskedResetOrigin`), RIFF (a walk — FWD/REV/PENDULUM/PING-PONG — over the
  shared 8-step rank matrix; DRUNK/RANDOM were removed from this walk 2026-10-13 and now coerce to
  FWD; LOCK/FREE, INVERT, ON-REST SKIP/FILL/TIE, STRIDE/LENGTH/ADVANCE/TRANSPOSE, ±2 octave, riff
  capture), NOTES (an additive lit-note layer independent of the riff — up to 8 ranks + TOP/TOP2,
  per-note octave shift, a bipolar velocity offset), and MASK (11 modes — MUTE/PAUSE/RATCHET/
  REPEAT/CHORD/OCT/MIRROR/LEAP/CLIMB/ACCENT/SWELL — gated by CHANCE).
- **Sequencer panel** (replaced an earlier "NOTE VIEW" telemetry panel entirely): LANES tab
  (which of the 4 lanes sounds each step) and RIFFS tab (which of the 4 riffs plays each step),
  each with its own ON/RATE/LEN, sharing the riff grid's own column geometry.
- **Source.** One page-level selector — MIDI IN / CHORDS (a self-contained degree-matrix+rate
  chord generator, no 8×8-grid receiver dependency) / KEY (a scale pool). No per-lane source, no
  dependency on the wider receiver/door graph.
- **Header (Fourfold, 2026-10-15).** Four groups: BRAND (mark, FOURFOLD, undo/redo — ↶/↷ bounded 50-deep, scoped to
  Euclideous's own fields only) · OUTPUTS (four output RINGS = MAIN OUT A–D: each quarter lights in the colour of a
  lane routed to it, tap pulses those lanes, hold traces them, a quarter flares on a real strike) · NOTES (one
  MIDI IN · CHORDS · KEY control + a key pill that opens the key pop-up) · UTILITIES (presets, close). There is NO ON
  chip: the page always runs (`euclideousEnabledResolved` is always true; the stored field is decode-only). The A/B/C
  fit ladder, group widths and positions all come from ONE pure `euclideousHeaderLayout` (Derivations.swift) that the
  body layouts also read — change header metrics there, not in the views.
- **Presets.** 20 Euclideous-only factory presets, reachable via a PRESETS button on the page
  itself — this REPLACED the old whole-plugin preset menu entirely (a confirmed, one-way
  decision; an old saved session loading the 8×8-State preset list will no longer find it there).
- **Layout.** A six-equal-box portrait/landscape grid (4 lane cards + the riff grid + one
  reserved placeholder box), proportionally sized — no literal pixel formula survives from any
  mockup; every size claim in the log is reasoned-from-the-layout-model, not measured against a
  real screen, unless explicitly marked device-confirmed.
- **Riff-grid walk tags (2026-10-15).** Each riff-on lane's marker on the shared riff grid is a STATELESS
  tag + thread: every frame it is re-derived from the polled step (`riffPositions`, the same value the RIFF-tab
  thumbnail reads) and the live beat, via a pure mirror of `runEuclidLine`'s tick arithmetic
  (`euclideousWalkTick`, Derivations.swift) — that mirror is what lets a tag depart BEFORE the hit. If you change
  how the walk advances in `Router.runEuclidLine` (ordinal, LOCK, ADV STEP, RESET, FOLLOW, swing), change the
  mirror too — `RouterTests.testWalkTag*` compare the two against the real router and will fail if they drift.
  Open timing risk (UI clock vs audible time) and known footer/engine disagreement: see the status log entry.
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
